BEGIN;

INSERT INTO settings (key, value, description)
VALUES (
    'LANGUAGE_GATE_TARGET_LANGUAGE',
    '"pt"'::JSONB,
    'Idioma primário desejado para a análise; não prova a variante regional.'
)
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

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
    SELECT
        GREATEST(
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

WITH config AS (
    SELECT
        COALESCE(
            normalize_language_code((SELECT value #>> '{}' FROM settings WHERE key = 'LANGUAGE_GATE_TARGET_LANGUAGE')),
            'pt'
        ) AS target_language,
        GREATEST(0::NUMERIC, LEAST(1::NUMERIC, COALESCE(
            (SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'LANGUAGE_GATE_MIN_CONFIDENCE'),
            0.80
        ))) AS minimum_confidence
), corrected AS (
    SELECT
        video.id,
        config.target_language,
        CASE
            WHEN video.language_detection_source = 'manual' THEN video.language_eligibility
            WHEN normalize_language_code(video.detected_language) IS NULL
              OR video.language_confidence IS NULL
              OR video.language_confidence < config.minimum_confidence THEN 'uncertain'
            WHEN language_matches_target(video.detected_language, config.target_language) THEN 'eligible'
            ELSE 'rejected'
        END AS eligibility
      FROM videos video
      CROSS JOIN config
)
UPDATE videos video
   SET target_language = corrected.target_language,
       language_eligibility = corrected.eligibility,
       language_retry_after = CASE
           WHEN corrected.eligibility = 'uncertain'
             AND video.language_detection_attempts < COALESCE(
                 (SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'LANGUAGE_GATE_MAX_ATTEMPTS'),
                 3
             )
               THEN CURRENT_TIMESTAMP
           ELSE NULL
       END
  FROM corrected
 WHERE video.id = corrected.id
   AND (
       video.target_language IS DISTINCT FROM corrected.target_language
       OR video.language_eligibility IS DISTINCT FROM corrected.eligibility
       OR (
           corrected.eligibility = 'uncertain'
           AND video.language_retry_after IS NULL
           AND video.language_detection_attempts < COALESCE(
               (SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'LANGUAGE_GATE_MAX_ATTEMPTS'),
               3
           )
       )
   );

COMMIT;
