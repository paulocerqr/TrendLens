BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('LANGUAGE_GATE_MODEL', '"nvidia/llama-3.3-nemotron-super-49b-v1"'::JSONB, 'Modelo NVIDIA NIM usado somente para detectar idioma a partir de metadados públicos.'),
    ('LANGUAGE_GATE_PROMPT_VERSION', '"v1"'::JSONB, 'Versão do prompt estruturado do gate de idioma.'),
    ('LANGUAGE_GATE_MAX_VIDEOS_PER_RUN', '30'::JSONB, 'Quantidade máxima de vídeos avaliados por execução do gate de idioma.'),
    ('LANGUAGE_GATE_DESCRIPTION_MAX_CHARS', '1000'::JSONB, 'Quantidade máxima de caracteres da descrição enviada ao detector de idioma.'),
    ('LANGUAGE_GATE_MIN_CONFIDENCE', '0.80'::JSONB, 'Confiança mínima para aceitar ou rejeitar automaticamente um idioma detectado.'),
    ('LANGUAGE_GATE_MAX_ATTEMPTS', '3'::JSONB, 'Quantidade máxima de tentativas automáticas para metadados inconclusivos.'),
    ('LANGUAGE_GATE_RETRY_HOURS', '24'::JSONB, 'Espera antes de repetir uma detecção inconclusiva ou com erro.'),
    ('LANGUAGE_GATE_TARGET_LANGUAGE', '"pt"'::JSONB, 'Idioma primário desejado para a análise; não prova a variante regional.'),
    ('LANGUAGE_GATE_TARGET_REGION', '"BR"'::JSONB, 'Mercado-alvo operacional da coleta; não representa a origem comprovada do vídeo.')
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

ALTER TABLE videos
    ADD COLUMN IF NOT EXISTS api_language VARCHAR(16),
    ADD COLUMN IF NOT EXISTS target_language VARCHAR(16),
    ADD COLUMN IF NOT EXISTS detected_language VARCHAR(16),
    ADD COLUMN IF NOT EXISTS language_confidence NUMERIC(5,4),
    ADD COLUMN IF NOT EXISTS language_detection_source TEXT NOT NULL DEFAULT 'unknown',
    ADD COLUMN IF NOT EXISTS language_eligibility TEXT NOT NULL DEFAULT 'uncertain',
    ADD COLUMN IF NOT EXISTS language_evaluated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS language_detection_attempts INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS language_retry_after TIMESTAMPTZ;

UPDATE videos
   SET target_language = COALESCE(
           NULLIF(lower(replace(btrim(
               (SELECT value #>> '{}' FROM settings WHERE key = 'LANGUAGE_GATE_TARGET_LANGUAGE')
           ), '_', '-')), ''),
           'pt'
       ),
       api_language = NULL,
       language = NULL,
       detected_language = NULL,
       language_confidence = NULL,
       language_detection_source = 'unknown',
       language_eligibility = 'uncertain',
       language_evaluated_at = NULL,
       language_detection_attempts = 0,
       language_retry_after = NULL
 WHERE target_language IS NULL;

ALTER TABLE videos
    ALTER COLUMN target_language SET DEFAULT 'pt',
    ALTER COLUMN target_language SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'videos'::regclass
           AND conname = 'videos_language_confidence_check'
    ) THEN
        ALTER TABLE videos
            ADD CONSTRAINT videos_language_confidence_check
            CHECK (language_confidence IS NULL OR language_confidence BETWEEN 0 AND 1);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'videos'::regclass
           AND conname = 'videos_language_detection_source_check'
    ) THEN
        ALTER TABLE videos
            ADD CONSTRAINT videos_language_detection_source_check
            CHECK (language_detection_source IN ('youtube_api', 'llm_metadata', 'manual', 'unknown'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'videos'::regclass
           AND conname = 'videos_language_eligibility_check'
    ) THEN
        ALTER TABLE videos
            ADD CONSTRAINT videos_language_eligibility_check
            CHECK (language_eligibility IN ('eligible', 'uncertain', 'rejected'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'videos'::regclass
           AND conname = 'videos_language_attempts_check'
    ) THEN
        ALTER TABLE videos
            ADD CONSTRAINT videos_language_attempts_check
            CHECK (language_detection_attempts >= 0);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS videos_language_gate_queue_idx
    ON videos (language_eligibility, language_retry_after, published_at DESC, id)
    WHERE platform = 'youtube' AND language_eligibility = 'uncertain';

CREATE INDEX IF NOT EXISTS videos_analysis_eligibility_idx
    ON videos (platform, language_eligibility, published_at DESC);

CREATE OR REPLACE FUNCTION normalize_language_code(p_language TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
SELECT CASE
    WHEN p_language IS NULL OR btrim(p_language) = '' THEN NULL
    WHEN lower(replace(btrim(p_language), '_', '-')) IN ('und', 'unknown', 'null') THEN NULL
    ELSE lower(replace(btrim(p_language), '_', '-'))
END;
$$;

CREATE OR REPLACE FUNCTION language_matches_target(
    p_detected_language TEXT,
    p_target_language TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
SELECT split_part(normalize_language_code(p_detected_language), '-', 1)
       = split_part(normalize_language_code(p_target_language), '-', 1);
$$;

CREATE OR REPLACE FUNCTION select_language_detection_candidates(
    p_limit INTEGER,
    p_description_max_chars INTEGER,
    p_as_of TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    video_id BIGINT,
    external_id TEXT,
    channel_name TEXT,
    title TEXT,
    description TEXT,
    published_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    api_language VARCHAR(16),
    target_language VARCHAR(16),
    target_region CHAR(2),
    short_confidence TEXT,
    detection_attempts INTEGER,
    category_hints JSONB
)
LANGUAGE sql
STABLE
AS $$
WITH config AS (
    SELECT GREATEST(
        COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'LANGUAGE_GATE_MAX_ATTEMPTS'), 3),
        1
    ) AS max_attempts,
    COALESCE(
        normalize_language_code((SELECT value #>> '{}' FROM settings WHERE key = 'LANGUAGE_GATE_TARGET_LANGUAGE')),
        'pt'
    ) AS target_language
)
SELECT
    video.id,
    video.external_id,
    video.channel_name,
    video.title,
    left(COALESCE(video.description, ''), GREATEST(p_description_max_chars, 0)),
    video.published_at,
    video.duration_seconds,
    video.api_language,
    config.target_language,
    video.region,
    video.short_confidence,
    video.language_detection_attempts,
    COALESCE(hints.category_hints, '[]'::JSONB)
  FROM videos video
  CROSS JOIN config
  LEFT JOIN LATERAL (
      SELECT jsonb_agg(DISTINCT category.slug ORDER BY category.slug) AS category_hints
        FROM video_collection_matches match
        JOIN collection_queries query ON query.id = match.collection_query_id
        JOIN categories category ON category.id = query.category_id
       WHERE match.video_id = video.id
  ) hints ON TRUE
 WHERE video.platform = 'youtube'
   AND video.language_eligibility = 'uncertain'
   AND video.language_detection_attempts < config.max_attempts
   AND (video.language_retry_after IS NULL OR video.language_retry_after <= p_as_of)
 ORDER BY video.published_at DESC, video.id
 LIMIT GREATEST(COALESCE(p_limit, 0), 0);
$$;

CREATE OR REPLACE FUNCTION persist_language_detection(
    p_video_id BIGINT,
    p_detected_language TEXT,
    p_confidence NUMERIC,
    p_source TEXT DEFAULT 'llm_metadata',
    p_evaluated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    video_id BIGINT,
    detected_language VARCHAR(16),
    target_language VARCHAR(16),
    language_confidence NUMERIC,
    language_detection_source TEXT,
    language_eligibility TEXT,
    language_detection_attempts INTEGER,
    language_retry_after TIMESTAMPTZ
)
LANGUAGE sql
VOLATILE
AS $$
WITH config AS (
    SELECT
        GREATEST(0::NUMERIC, LEAST(1::NUMERIC, COALESCE(
            (SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'LANGUAGE_GATE_MIN_CONFIDENCE'),
            0.80
        ))) AS minimum_confidence,
        GREATEST(COALESCE(
            (SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'LANGUAGE_GATE_RETRY_HOURS'),
            24
        ), 1) AS retry_hours,
        COALESCE(
            normalize_language_code((SELECT value #>> '{}' FROM settings WHERE key = 'LANGUAGE_GATE_TARGET_LANGUAGE')),
            'pt'
        ) AS target_language
), evaluated AS (
    SELECT
        video.id,
        config.target_language,
        normalize_language_code(p_detected_language) AS detected_language,
        GREATEST(0::NUMERIC, LEAST(1::NUMERIC, COALESCE(p_confidence, 0))) AS confidence,
        CASE
            WHEN p_source IN ('youtube_api', 'llm_metadata', 'manual') THEN p_source
            ELSE 'llm_metadata'
        END AS detection_source,
        config.minimum_confidence,
        config.retry_hours
      FROM videos video
      CROSS JOIN config
     WHERE video.id = p_video_id
), decided AS (
    SELECT
        evaluated.*,
        CASE
            WHEN detected_language IS NULL OR confidence < minimum_confidence THEN 'uncertain'
            WHEN language_matches_target(detected_language, target_language) THEN 'eligible'
            ELSE 'rejected'
        END AS eligibility
      FROM evaluated
), updated AS (
    UPDATE videos video
       SET detected_language = decided.detected_language,
           target_language = decided.target_language,
           language = decided.detected_language,
           language_confidence = decided.confidence,
           language_detection_source = decided.detection_source,
           language_eligibility = decided.eligibility,
           language_evaluated_at = p_evaluated_at,
           language_detection_attempts = video.language_detection_attempts + 1,
           language_retry_after = CASE
               WHEN decided.eligibility = 'uncertain'
                   THEN p_evaluated_at + make_interval(hours => decided.retry_hours)
               ELSE NULL
           END
      FROM decided
     WHERE video.id = decided.id
    RETURNING video.*
)
SELECT
    updated.id,
    updated.detected_language,
    updated.target_language,
    updated.language_confidence,
    updated.language_detection_source,
    updated.language_eligibility,
    updated.language_detection_attempts,
    updated.language_retry_after
  FROM updated;
$$;

CREATE OR REPLACE FUNCTION record_language_detection_failure(
    p_video_id BIGINT,
    p_failed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    video_id BIGINT,
    language_detection_attempts INTEGER,
    language_retry_after TIMESTAMPTZ
)
LANGUAGE sql
VOLATILE
AS $$
WITH config AS (
    SELECT GREATEST(COALESCE(
        (SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'LANGUAGE_GATE_RETRY_HOURS'),
        24
    ), 1) AS retry_hours
), updated AS (
    UPDATE videos video
       SET language_evaluated_at = p_failed_at,
           language_detection_attempts = video.language_detection_attempts + 1,
           language_retry_after = p_failed_at + make_interval(hours => config.retry_hours)
      FROM config
     WHERE video.id = p_video_id
    RETURNING video.id, video.language_detection_attempts, video.language_retry_after
)
SELECT * FROM updated;
$$;

CREATE OR REPLACE FUNCTION set_manual_language_eligibility(
    p_video_id BIGINT,
    p_detected_language TEXT,
    p_eligibility TEXT,
    p_reviewed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    video_id BIGINT,
    detected_language VARCHAR(16),
    language_eligibility TEXT,
    language_evaluated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF p_eligibility NOT IN ('eligible', 'uncertain', 'rejected') THEN
        RAISE EXCEPTION 'Invalid language eligibility: %', p_eligibility;
    END IF;

    RETURN QUERY
    UPDATE videos video
       SET detected_language = normalize_language_code(p_detected_language),
           language = normalize_language_code(p_detected_language),
           language_confidence = 1,
           language_detection_source = 'manual',
           language_eligibility = p_eligibility,
           language_evaluated_at = p_reviewed_at,
           language_retry_after = NULL
     WHERE video.id = p_video_id
    RETURNING video.id, video.detected_language, video.language_eligibility, video.language_evaluated_at;
END;
$$;

CREATE OR REPLACE FUNCTION select_classification_candidates(
    p_limit INTEGER,
    p_description_max_chars INTEGER
)
RETURNS TABLE (
    video_id BIGINT,
    external_id TEXT,
    channel_name TEXT,
    title TEXT,
    description TEXT,
    published_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    language VARCHAR(16),
    region CHAR(2),
    short_confidence TEXT,
    category_hints JSONB
)
LANGUAGE sql
STABLE
AS $$
SELECT
    video.id,
    video.external_id,
    video.channel_name,
    video.title,
    left(COALESCE(video.description, ''), GREATEST(p_description_max_chars, 0)),
    video.published_at,
    video.duration_seconds,
    video.detected_language,
    video.region,
    video.short_confidence,
    COALESCE(hints.category_hints, '[]'::JSONB)
  FROM videos video
  LEFT JOIN LATERAL (
      SELECT jsonb_agg(DISTINCT category.slug ORDER BY category.slug) AS category_hints
        FROM video_collection_matches match
        JOIN collection_queries query ON query.id = match.collection_query_id
        JOIN categories category ON category.id = query.category_id
       WHERE match.video_id = video.id
  ) hints ON TRUE
 WHERE video.platform = 'youtube'
   AND video.language_eligibility = 'eligible'
   AND NOT EXISTS (
       SELECT 1
         FROM video_classifications classification
        WHERE classification.video_id = video.id
   )
 ORDER BY video.published_at DESC, video.id
 LIMIT GREATEST(p_limit, 0);
$$;

DO $migration$
DECLARE
    definition TEXT;
    patched TEXT;
BEGIN
    SELECT pg_get_functiondef('refresh_category_statistics(timestamptz)'::regprocedure)
      INTO definition;
    IF position('video.language_eligibility = ''eligible''' IN definition) = 0 THEN
        patched := replace(
            definition,
            'AND video.published_at < period_window.window_end',
            'AND video.published_at < period_window.window_end' || chr(10) ||
            '       AND video.language_eligibility = ''eligible'''
        );
        IF patched = definition THEN
            RAISE EXCEPTION 'Could not patch refresh_category_statistics language eligibility';
        END IF;
        EXECUTE patched;
    END IF;

    SELECT pg_get_functiondef('select_classification_review_candidates(integer,text)'::regprocedure)
      INTO definition;
    IF position('video.language_eligibility = ''eligible''' IN definition) = 0 THEN
        patched := replace(
            definition,
            '     WHERE NOT EXISTS (',
            '     WHERE video.language_eligibility = ''eligible''' || chr(10) ||
            '       AND NOT EXISTS ('
        );
        IF patched = definition THEN
            RAISE EXCEPTION 'Could not patch select_classification_review_candidates language eligibility';
        END IF;
        EXECUTE patched;
    END IF;

    SELECT pg_get_functiondef('build_phase12_validation(timestamptz)'::regprocedure)
      INTO definition;
    IF position('video.language_eligibility = ''eligible''' IN definition) = 0 THEN
        patched := replace(
            definition,
            'WHERE video.platform = ''youtube''' || chr(10) ||
            '       AND video.published_at >= bounds.period_start',
            'WHERE video.platform = ''youtube''' || chr(10) ||
            '       AND video.language_eligibility = ''eligible''' || chr(10) ||
            '       AND video.published_at >= bounds.period_start'
        );
        IF patched = definition THEN
            RAISE EXCEPTION 'Could not patch build_phase12_validation language eligibility';
        END IF;
        EXECUTE patched;
    END IF;

    SELECT pg_get_functiondef('build_pipeline_observability(timestamptz)'::regprocedure)
      INTO definition;
    patched := definition;
    IF position('JOIN videos video ON video.id = classification.video_id' IN patched) = 0 THEN
        patched := replace(
            patched,
            'FROM video_classifications classification' || chr(10) ||
            '          LEFT JOIN categories category',
            'FROM video_classifications classification' || chr(10) ||
            '          JOIN videos video ON video.id = classification.video_id' || chr(10) ||
            '             AND video.language_eligibility = ''eligible''' || chr(10) ||
            '          LEFT JOIN categories category'
        );
    END IF;
    IF position('WHERE metric.calculation_version = config.metrics_version' || chr(10) || '               AND video.language_eligibility = ''eligible''' IN patched) = 0 THEN
        patched := replace(
            patched,
            'WHERE metric.calculation_version = config.metrics_version',
            'WHERE metric.calculation_version = config.metrics_version' || chr(10) ||
            '               AND video.language_eligibility = ''eligible'''
        );
    END IF;
    IF position('01B - TrendLens - Content Language Gate' IN patched) = 0 THEN
        patched := replace(
            patched,
            '(9, ''09 - TrendLens - Report'', ''reporting'')',
            '(9, ''09 - TrendLens - Report'', ''reporting''),' || chr(10) ||
            '        (10, ''01B - TrendLens - Content Language Gate'', ''language_eligibility'')'
        );
    END IF;
    IF position('JOIN videos video ON video.id = classification.video_id' IN patched) = 0
       OR position(
           'WHERE metric.calculation_version = config.metrics_version' || chr(10) ||
           '               AND video.language_eligibility = ''eligible'''
           IN patched
       ) = 0
       OR position('01B - TrendLens - Content Language Gate' IN patched) = 0 THEN
        RAISE EXCEPTION 'Could not patch build_pipeline_observability language eligibility';
    END IF;
    IF patched <> definition THEN
        EXECUTE patched;
    END IF;
END;
$migration$;

UPDATE settings
   SET value = '"v2-language-eligible"'::JSONB,
       description = 'Versão das agregações com exclusão explícita de vídeos linguisticamente rejeitados.'
 WHERE key = 'TREND_CALCULATION_VERSION';

UPDATE settings
   SET value = '"v2-language-eligible"'::JSONB,
       description = 'Versão do ranking calculado somente sobre agregações linguisticamente elegíveis.'
 WHERE key = 'OPPORTUNITY_CALCULATION_VERSION';

UPDATE settings
   SET value = '"v2-language-eligible"'::JSONB,
       description = 'Versão da observabilidade com o gate de idioma e indicadores analíticos filtrados.'
 WHERE key = 'OBSERVABILITY_VERSION';

UPDATE settings
   SET value = '"v2-language-eligible"'::JSONB,
       description = 'Versão da validação restrita aos vídeos linguisticamente elegíveis.'
 WHERE key = 'VALIDATION_VERSION';

COMMIT;
