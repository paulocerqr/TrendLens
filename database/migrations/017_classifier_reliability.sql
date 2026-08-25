BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('CLASSIFIER_MAX_ATTEMPTS', '3'::JSONB, 'Quantidade máxima de falhas terminais automáticas antes de encaminhar o vídeo para revisão manual.'),
    ('CLASSIFIER_RETRY_BACKOFF_BASE_HOURS', '6'::JSONB, 'Espera inicial, em horas, antes de repetir uma classificação que falhou.'),
    ('CLASSIFIER_RETRY_BACKOFF_MAX_HOURS', '48'::JSONB, 'Espera máxima, em horas, aplicada ao backoff exponencial do classificador.')
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

CREATE TABLE IF NOT EXISTS video_classification_processing_state (
    video_id BIGINT PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    attempt_count INTEGER NOT NULL DEFAULT 0,
    total_attempt_count INTEGER NOT NULL DEFAULT 0,
    retry_after TIMESTAMPTZ,
    last_error_type TEXT,
    last_failed_at TIMESTAMPTZ,
    last_succeeded_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    reviewed_by TEXT,
    review_note TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT video_classification_processing_status_check
        CHECK (status IN ('pending', 'retry_wait', 'manual_review', 'excluded', 'completed')),
    CONSTRAINT video_classification_processing_attempts_check
        CHECK (attempt_count >= 0 AND total_attempt_count >= attempt_count),
    CONSTRAINT video_classification_processing_retry_check
        CHECK (
            (status = 'retry_wait' AND retry_after IS NOT NULL)
            OR (status <> 'retry_wait' AND retry_after IS NULL)
        ),
    CONSTRAINT video_classification_processing_error_type_check
        CHECK (last_error_type IS NULL OR length(btrim(last_error_type)) > 0),
    CONSTRAINT video_classification_processing_reviewer_check
        CHECK (reviewed_by IS NULL OR length(btrim(reviewed_by)) > 0),
    CONSTRAINT video_classification_processing_note_check
        CHECK (review_note IS NULL OR length(review_note) <= 4000)
);

CREATE INDEX IF NOT EXISTS video_classification_processing_retry_idx
    ON video_classification_processing_state (retry_after, video_id)
    WHERE status = 'retry_wait';

CREATE INDEX IF NOT EXISTS video_classification_processing_review_idx
    ON video_classification_processing_state (last_failed_at, video_id)
    WHERE status = 'manual_review';

CREATE INDEX IF NOT EXISTS pipeline_errors_classifier_video_idx
    ON pipeline_errors ((metadata ->> 'video_id'), occurred_at DESC)
    WHERE workflow = '03 - TrendLens - AI Content Classifier'
      AND error_type IN ('ai_classification_error', 'classification_persistence_error');

CREATE OR REPLACE FUNCTION record_classification_failure(
    p_video_id BIGINT,
    p_error_type TEXT,
    p_failed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    video_id BIGINT,
    status TEXT,
    attempt_count INTEGER,
    total_attempt_count INTEGER,
    retry_after TIMESTAMPTZ,
    requires_manual_review BOOLEAN,
    max_attempts INTEGER
)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    configured_max_attempts INTEGER;
    configured_base_hours INTEGER;
    configured_max_hours INTEGER;
BEGIN
    IF p_error_type IS NULL OR length(btrim(p_error_type)) = 0 THEN
        RAISE EXCEPTION 'Classification error type must not be blank';
    END IF;

    SELECT
        GREATEST(1, LEAST(100, COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'CLASSIFIER_MAX_ATTEMPTS'), 3))),
        GREATEST(1, LEAST(720, COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'CLASSIFIER_RETRY_BACKOFF_BASE_HOURS'), 6))),
        GREATEST(1, LEAST(720, COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'CLASSIFIER_RETRY_BACKOFF_MAX_HOURS'), 48)))
      INTO configured_max_attempts, configured_base_hours, configured_max_hours;

    configured_max_hours := GREATEST(configured_base_hours, configured_max_hours);

    RETURN QUERY
    INSERT INTO video_classification_processing_state AS processing (
        video_id,
        status,
        attempt_count,
        total_attempt_count,
        retry_after,
        last_error_type,
        last_failed_at,
        updated_at
    )
    VALUES (
        p_video_id,
        CASE WHEN configured_max_attempts <= 1 THEN 'manual_review' ELSE 'retry_wait' END,
        1,
        1,
        CASE
            WHEN configured_max_attempts <= 1 THEN NULL
            ELSE p_failed_at + make_interval(hours => LEAST(configured_max_hours, configured_base_hours))
        END,
        btrim(p_error_type),
        p_failed_at,
        p_failed_at
    )
    ON CONFLICT ON CONSTRAINT video_classification_processing_state_pkey DO UPDATE
    SET attempt_count = processing.attempt_count + 1,
        total_attempt_count = processing.total_attempt_count + 1,
        status = CASE
            WHEN processing.attempt_count + 1 >= configured_max_attempts THEN 'manual_review'
            ELSE 'retry_wait'
        END,
        retry_after = CASE
            WHEN processing.attempt_count + 1 >= configured_max_attempts THEN NULL
            ELSE p_failed_at + make_interval(
                hours => LEAST(
                    configured_max_hours::NUMERIC,
                    configured_base_hours::NUMERIC
                        * power(2::NUMERIC, LEAST(30, processing.attempt_count))
                )::INTEGER
            )
        END,
        last_error_type = btrim(p_error_type),
        last_failed_at = p_failed_at,
        last_succeeded_at = NULL,
        updated_at = p_failed_at
    RETURNING
        processing.video_id,
        processing.status,
        processing.attempt_count,
        processing.total_attempt_count,
        processing.retry_after,
        processing.status = 'manual_review',
        configured_max_attempts;
END;
$$;

CREATE OR REPLACE FUNCTION mark_classification_completed(
    p_video_id BIGINT,
    p_succeeded_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS BOOLEAN
LANGUAGE sql
VOLATILE
AS $$
WITH updated AS (
    UPDATE video_classification_processing_state
       SET status = 'completed',
           retry_after = NULL,
           last_succeeded_at = p_succeeded_at,
           updated_at = p_succeeded_at
     WHERE video_id = p_video_id
    RETURNING true AS state_updated
)
SELECT COALESCE((SELECT state_updated FROM updated), false);
$$;

CREATE OR REPLACE FUNCTION select_classification_failure_review_candidates(
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
    video_id BIGINT,
    external_id TEXT,
    url TEXT,
    title TEXT,
    channel_name TEXT,
    published_at TIMESTAMPTZ,
    attempt_count INTEGER,
    total_attempt_count INTEGER,
    last_error_type TEXT,
    last_error_message TEXT,
    last_failed_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
SELECT
    video.id,
    video.external_id,
    video.url,
    video.title,
    video.channel_name,
    video.published_at,
    processing.attempt_count,
    processing.total_attempt_count,
    processing.last_error_type,
    latest_error.error_message,
    processing.last_failed_at
  FROM video_classification_processing_state processing
  JOIN videos video ON video.id = processing.video_id
  LEFT JOIN LATERAL (
      SELECT error.error_message
        FROM pipeline_errors error
       WHERE error.workflow = '03 - TrendLens - AI Content Classifier'
         AND error.error_type IN ('ai_classification_error', 'classification_persistence_error')
         AND error.metadata ->> 'video_id' = processing.video_id::TEXT
       ORDER BY error.occurred_at DESC, error.id DESC
       LIMIT 1
  ) latest_error ON TRUE
 WHERE processing.status = 'manual_review'
 ORDER BY processing.last_failed_at, processing.video_id
 LIMIT GREATEST(p_limit, 0);
$$;

CREATE OR REPLACE FUNCTION resolve_classification_failure_review(
    p_video_id BIGINT,
    p_action TEXT,
    p_reviewer TEXT,
    p_note TEXT DEFAULT NULL,
    p_reviewed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    video_id BIGINT,
    status TEXT,
    attempt_count INTEGER,
    total_attempt_count INTEGER,
    retry_after TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    reviewed_by TEXT
)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    normalized_action TEXT := lower(btrim(p_action));
BEGIN
    IF normalized_action NOT IN ('retry', 'exclude') THEN
        RAISE EXCEPTION 'Invalid classification review action: %', p_action;
    END IF;
    IF p_reviewer IS NULL OR length(btrim(p_reviewer)) = 0 THEN
        RAISE EXCEPTION 'Classification reviewer must not be blank';
    END IF;
    IF p_note IS NOT NULL AND length(p_note) > 4000 THEN
        RAISE EXCEPTION 'Classification review note exceeds 4000 characters';
    END IF;

    RETURN QUERY
    UPDATE video_classification_processing_state processing
       SET status = CASE WHEN normalized_action = 'retry' THEN 'pending' ELSE 'excluded' END,
           attempt_count = CASE WHEN normalized_action = 'retry' THEN 0 ELSE processing.attempt_count END,
           retry_after = NULL,
           reviewed_at = p_reviewed_at,
           reviewed_by = btrim(p_reviewer),
           review_note = p_note,
           updated_at = p_reviewed_at
     WHERE processing.video_id = p_video_id
       AND processing.status = 'manual_review'
    RETURNING
        processing.video_id,
        processing.status,
        processing.attempt_count,
        processing.total_attempt_count,
        processing.retry_after,
        processing.reviewed_at,
        processing.reviewed_by;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Video % is not awaiting classification failure review', p_video_id;
    END IF;
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
  LEFT JOIN video_classification_processing_state processing
    ON processing.video_id = video.id
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
   AND (
       processing.video_id IS NULL
       OR processing.status = 'pending'
       OR (
           processing.status = 'retry_wait'
           AND processing.retry_after <= CURRENT_TIMESTAMP
       )
   )
 ORDER BY
    CASE WHEN processing.status = 'retry_wait' THEN 0 ELSE 1 END,
    video.published_at DESC,
    video.id
 LIMIT GREATEST(p_limit, 0);
$$;

WITH config AS (
    SELECT GREATEST(
        1,
        COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'CLASSIFIER_MAX_ATTEMPTS'), 3)
    ) AS max_attempts,
    GREATEST(
        1,
        COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'CLASSIFIER_RETRY_BACKOFF_BASE_HOURS'), 6)
    ) AS base_hours,
    GREATEST(
        1,
        COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'CLASSIFIER_RETRY_BACKOFF_MAX_HOURS'), 48)
    ) AS max_hours
), historical AS (
    SELECT
        (error.metadata ->> 'video_id')::BIGINT AS video_id,
        count(*)::INTEGER AS failure_count,
        (array_agg(error.error_type ORDER BY error.occurred_at DESC, error.id DESC))[1] AS last_error_type,
        max(error.occurred_at) AS last_failed_at
      FROM pipeline_errors error
     WHERE error.workflow = '03 - TrendLens - AI Content Classifier'
       AND error.error_type IN ('ai_classification_error', 'classification_persistence_error')
       AND error.metadata ->> 'video_id' ~ '^[0-9]+$'
     GROUP BY (error.metadata ->> 'video_id')::BIGINT
), eligible AS (
    SELECT historical.*, config.max_attempts, config.base_hours, GREATEST(config.base_hours, config.max_hours) AS max_hours
      FROM historical
      CROSS JOIN config
      JOIN videos video ON video.id = historical.video_id
     WHERE NOT EXISTS (
         SELECT 1 FROM video_classifications classification
          WHERE classification.video_id = historical.video_id
     )
)
INSERT INTO video_classification_processing_state (
    video_id,
    status,
    attempt_count,
    total_attempt_count,
    retry_after,
    last_error_type,
    last_failed_at,
    updated_at
)
SELECT
    eligible.video_id,
    CASE WHEN eligible.failure_count >= eligible.max_attempts THEN 'manual_review' ELSE 'retry_wait' END,
    eligible.failure_count,
    eligible.failure_count,
    CASE
        WHEN eligible.failure_count >= eligible.max_attempts THEN NULL
        ELSE eligible.last_failed_at + make_interval(
            hours => LEAST(
                eligible.max_hours::NUMERIC,
                eligible.base_hours::NUMERIC
                    * power(2::NUMERIC, LEAST(30, GREATEST(eligible.failure_count - 1, 0)))
            )::INTEGER
        )
    END,
    eligible.last_error_type,
    eligible.last_failed_at,
    eligible.last_failed_at
  FROM eligible
ON CONFLICT (video_id) DO NOTHING;

COMMIT;
