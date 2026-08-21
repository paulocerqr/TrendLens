BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('LLM_MODEL', '"nvidia/llama-3.3-nemotron-super-49b-v1"'::JSONB, 'Modelo NVIDIA NIM utilizado inicialmente pelo classificador, sem armazenar credenciais.'),
    ('CLASSIFIER_MAX_VIDEOS_PER_RUN', '5'::JSONB, 'Quantidade máxima de vídeos classificados por execução.'),
    ('CLASSIFIER_DESCRIPTION_MAX_CHARS', '2000'::JSONB, 'Quantidade máxima de caracteres da descrição enviada ao classificador.'),
    ('CLASSIFIER_PROMPT_VERSION', '"v1"'::JSONB, 'Versão do prompt estruturado utilizado pelo classificador.')
ON CONFLICT (key) DO UPDATE
SET
    value = CASE
        WHEN settings.key = 'LLM_MODEL' AND settings.value <> 'null'::jsonb
            THEN settings.value
        ELSE EXCLUDED.value
    END,
    description = EXCLUDED.description;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'video_classifications'::regclass
           AND conname = 'video_classifications_model_check'
    ) THEN
        ALTER TABLE video_classifications
            ADD CONSTRAINT video_classifications_model_check
            CHECK (length(btrim(classification_model)) > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'video_classifications'::regclass
           AND conname = 'video_classifications_prompt_version_check'
    ) THEN
        ALTER TABLE video_classifications
            ADD CONSTRAINT video_classifications_prompt_version_check
            CHECK (length(btrim(prompt_version)) > 0);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS video_classifications_classified_at_idx
    ON video_classifications (classified_at DESC);

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
    v.id AS video_id,
    v.external_id,
    v.channel_name,
    v.title,
    left(COALESCE(v.description, ''), GREATEST(p_description_max_chars, 0)) AS description,
    v.published_at,
    v.duration_seconds,
    v.language,
    v.region,
    v.short_confidence,
    COALESCE(hints.category_hints, '[]'::jsonb) AS category_hints
  FROM videos v
  LEFT JOIN LATERAL (
      SELECT jsonb_agg(DISTINCT c.slug ORDER BY c.slug) AS category_hints
        FROM video_collection_matches m
        JOIN collection_queries q ON q.id = m.collection_query_id
        JOIN categories c ON c.id = q.category_id
       WHERE m.video_id = v.id
  ) hints ON TRUE
 WHERE v.platform = 'youtube'
   AND NOT EXISTS (
       SELECT 1
         FROM video_classifications classification
        WHERE classification.video_id = v.id
   )
 ORDER BY v.published_at DESC, v.id
 LIMIT GREATEST(p_limit, 0);
$$;

COMMIT;
