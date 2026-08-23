BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('SNAPSHOT_FAILURE_BACKOFF_BASE_MINUTES', '360'::JSONB, 'Espera inicial, em minutos, antes de tentar novamente um vídeo omitido por videos.list.'),
    ('SNAPSHOT_FAILURE_BACKOFF_MAX_MINUTES', '10080'::JSONB, 'Espera máxima, em minutos, aplicada a vídeos repetidamente omitidos por videos.list.'),
    ('CLASSIFIER_MAX_VIDEOS_PER_RUN', '30'::JSONB, 'Quantidade máxima de vídeos classificados por execução.')
ON CONFLICT (key) DO UPDATE
SET
    value = EXCLUDED.value,
    description = EXCLUDED.description;

CREATE TABLE IF NOT EXISTS video_snapshot_tracking_state (
    video_id BIGINT PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    last_failure_at TIMESTAMPTZ,
    retry_after TIMESTAMPTZ,
    last_error_type TEXT,
    last_error_reason TEXT,
    last_success_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT video_snapshot_tracking_failures_check
        CHECK (consecutive_failures >= 0),
    CONSTRAINT video_snapshot_tracking_failure_state_check
        CHECK (
            (consecutive_failures = 0 AND retry_after IS NULL)
            OR
            (consecutive_failures > 0 AND last_failure_at IS NOT NULL AND retry_after IS NOT NULL)
        )
);

CREATE INDEX IF NOT EXISTS video_snapshot_tracking_retry_idx
    ON video_snapshot_tracking_state (retry_after, video_id)
    WHERE retry_after IS NOT NULL;

CREATE OR REPLACE FUNCTION snapshot_backoff_minutes(p_failure_count INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
WITH configured AS (
    SELECT
        GREATEST(
            COALESCE(
                (SELECT (value #>> '{}')::INTEGER
                   FROM settings
                  WHERE key = 'SNAPSHOT_FAILURE_BACKOFF_BASE_MINUTES'),
                360
            ),
            1
        ) AS base_minutes,
        GREATEST(
            COALESCE(
                (SELECT (value #>> '{}')::INTEGER
                   FROM settings
                  WHERE key = 'SNAPSHOT_FAILURE_BACKOFF_MAX_MINUTES'),
                10080
            ),
            1
        ) AS max_minutes
)
SELECT LEAST(
           configured.max_minutes,
           (
               configured.base_minutes
               * power(2::NUMERIC, LEAST(GREATEST(COALESCE(p_failure_count, 1) - 1, 0), 20))
           )::INTEGER
       )
  FROM configured;
$$;

CREATE OR REPLACE FUNCTION select_snapshot_candidates(
    p_as_of TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    p_limit INTEGER DEFAULT NULL
)
RETURNS TABLE (
    video_id BIGINT,
    external_id TEXT,
    published_at TIMESTAMPTZ,
    last_collected_at TIMESTAMPTZ,
    age_bucket TEXT,
    due_interval_minutes INTEGER
)
LANGUAGE sql
STABLE
AS $$
WITH config_values AS (
    SELECT jsonb_object_agg(key, value) AS values
      FROM settings
     WHERE key = ANY (ARRAY[
        'SNAPSHOT_ACTIVE_DAYS',
        'SNAPSHOT_RECENT_MAX_AGE_HOURS',
        'SNAPSHOT_INTERMEDIATE_MAX_AGE_HOURS',
        'SNAPSHOT_RECENT_INTERVAL_MINUTES',
        'SNAPSHOT_INTERMEDIATE_INTERVAL_MINUTES',
        'SNAPSHOT_OLDER_INTERVAL_MINUTES'
     ])
),
configured AS (
    SELECT
        (values ->> 'SNAPSHOT_ACTIVE_DAYS')::INTEGER AS active_days,
        (values ->> 'SNAPSHOT_RECENT_MAX_AGE_HOURS')::INTEGER AS recent_max_age_hours,
        (values ->> 'SNAPSHOT_INTERMEDIATE_MAX_AGE_HOURS')::INTEGER AS intermediate_max_age_hours,
        (values ->> 'SNAPSHOT_RECENT_INTERVAL_MINUTES')::INTEGER AS recent_interval_minutes,
        (values ->> 'SNAPSHOT_INTERMEDIATE_INTERVAL_MINUTES')::INTEGER AS intermediate_interval_minutes,
        (values ->> 'SNAPSHOT_OLDER_INTERVAL_MINUTES')::INTEGER AS older_interval_minutes
      FROM config_values
),
bucketed AS (
    SELECT
        v.id AS video_id,
        v.external_id,
        v.published_at,
        latest.collected_at AS last_collected_at,
        tracking.retry_after,
        CASE
            WHEN v.published_at >= p_as_of - make_interval(hours => configured.recent_max_age_hours)
                THEN 'recent'
            WHEN v.published_at >= p_as_of - make_interval(hours => configured.intermediate_max_age_hours)
                THEN 'intermediate'
            ELSE 'older'
        END AS age_bucket,
        CASE
            WHEN v.published_at >= p_as_of - make_interval(hours => configured.recent_max_age_hours)
                THEN configured.recent_interval_minutes
            WHEN v.published_at >= p_as_of - make_interval(hours => configured.intermediate_max_age_hours)
                THEN configured.intermediate_interval_minutes
            ELSE configured.older_interval_minutes
        END AS due_interval_minutes
      FROM videos v
      CROSS JOIN configured
      JOIN LATERAL (
          SELECT s.collected_at
            FROM video_snapshots s
           WHERE s.video_id = v.id
           ORDER BY s.collected_at DESC
           LIMIT 1
      ) latest ON TRUE
      LEFT JOIN video_snapshot_tracking_state tracking ON tracking.video_id = v.id
     WHERE v.platform = 'youtube'
       AND v.published_at <= p_as_of
       AND v.published_at >= p_as_of - make_interval(days => configured.active_days)
)
SELECT
    bucketed.video_id,
    bucketed.external_id,
    bucketed.published_at,
    bucketed.last_collected_at,
    bucketed.age_bucket,
    bucketed.due_interval_minutes
  FROM bucketed
 WHERE bucketed.last_collected_at <= p_as_of - make_interval(mins => bucketed.due_interval_minutes)
   AND (bucketed.retry_after IS NULL OR bucketed.retry_after <= p_as_of)
 ORDER BY bucketed.last_collected_at, bucketed.published_at, bucketed.video_id
 LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION persist_snapshot_batch(
    p_pipeline_run_id BIGINT,
    p_batch_number INTEGER,
    p_candidates JSONB,
    p_response_items JSONB,
    p_quota_cost INTEGER
)
RETURNS TABLE (
    pipeline_run_id BIGINT,
    status TEXT,
    items_received INTEGER,
    items_processed INTEGER,
    items_skipped INTEGER,
    items_failed INTEGER,
    api_calls INTEGER,
    quota_units_estimated INTEGER,
    batch_number INTEGER,
    expected_count INTEGER,
    inserted_count INTEGER,
    duplicate_count INTEGER,
    missing_count INTEGER,
    invalid_count INTEGER,
    backoff_count INTEGER,
    pipeline_error_ids BIGINT[]
)
LANGUAGE sql
VOLATILE
AS $$
WITH arguments AS (
    SELECT
        p_pipeline_run_id AS pipeline_run_id,
        (SELECT started_at FROM pipeline_runs WHERE id = p_pipeline_run_id) AS collected_at,
        p_batch_number AS batch_number,
        COALESCE(p_candidates, '[]'::JSONB) AS candidates,
        COALESCE(p_response_items, '[]'::JSONB) AS response_items,
        GREATEST(COALESCE(p_quota_cost, 0), 0) AS quota_cost
),
expected AS (
    SELECT item.video_id, item.external_id
      FROM arguments
      CROSS JOIN LATERAL jsonb_to_recordset(arguments.candidates)
          AS item(video_id BIGINT, external_id TEXT)
),
returned AS (
    SELECT
        element ->> 'id' AS external_id,
        NULLIF(element #>> '{statistics,viewCount}', '')::BIGINT AS views,
        NULLIF(element #>> '{statistics,likeCount}', '')::BIGINT AS likes,
        NULLIF(element #>> '{statistics,commentCount}', '')::BIGINT AS comments
      FROM arguments
      CROSS JOIN LATERAL jsonb_array_elements(arguments.response_items) AS element
),
matched AS (
    SELECT
        expected.video_id,
        expected.external_id,
        returned.external_id AS returned_external_id,
        returned.views,
        returned.likes,
        returned.comments
      FROM expected
      LEFT JOIN returned USING (external_id)
),
successful_items AS (
    SELECT matched.*
      FROM matched
     WHERE matched.returned_external_id IS NOT NULL
       AND matched.views IS NOT NULL
),
failed_items AS (
    SELECT
        matched.video_id,
        matched.external_id,
        CASE
            WHEN matched.returned_external_id IS NULL THEN 'youtube_video_not_returned'
            ELSE 'youtube_view_count_missing'
        END AS error_type,
        CASE
            WHEN matched.returned_external_id IS NULL
                THEN 'YouTube videos.list omitted the requested video'
            ELSE 'YouTube videos.list returned the video without a public viewCount'
        END AS error_reason
      FROM matched
     WHERE matched.returned_external_id IS NULL
        OR matched.views IS NULL
),
snapshot_insert AS (
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    SELECT
        successful_items.video_id,
        arguments.collected_at,
        successful_items.views,
        successful_items.likes,
        successful_items.comments
      FROM successful_items
      CROSS JOIN arguments
    ON CONFLICT (video_id, collected_at) DO NOTHING
    RETURNING video_id
),
success_state_upsert AS (
    INSERT INTO video_snapshot_tracking_state (
        video_id,
        consecutive_failures,
        last_failure_at,
        retry_after,
        last_error_type,
        last_error_reason,
        last_success_at
    )
    SELECT
        successful_items.video_id,
        0,
        NULL,
        NULL,
        NULL,
        NULL,
        arguments.collected_at
      FROM successful_items
      CROSS JOIN arguments
    ON CONFLICT (video_id) DO UPDATE
    SET
        consecutive_failures = 0,
        last_failure_at = NULL,
        retry_after = NULL,
        last_error_type = NULL,
        last_error_reason = NULL,
        last_success_at = EXCLUDED.last_success_at,
        updated_at = CURRENT_TIMESTAMP
    RETURNING video_id
),
failed_state_upsert AS (
    INSERT INTO video_snapshot_tracking_state AS tracking (
        video_id,
        consecutive_failures,
        last_failure_at,
        retry_after,
        last_error_type,
        last_error_reason
    )
    SELECT
        failed_items.video_id,
        1,
        arguments.collected_at,
        arguments.collected_at + make_interval(mins => snapshot_backoff_minutes(1)),
        failed_items.error_type,
        failed_items.error_reason
      FROM failed_items
      CROSS JOIN arguments
    ON CONFLICT (video_id) DO UPDATE
    SET
        consecutive_failures = tracking.consecutive_failures + 1,
        last_failure_at = EXCLUDED.last_failure_at,
        retry_after = EXCLUDED.last_failure_at
            + make_interval(mins => snapshot_backoff_minutes(tracking.consecutive_failures + 1)),
        last_error_type = EXCLUDED.last_error_type,
        last_error_reason = EXCLUDED.last_error_reason,
        updated_at = CURRENT_TIMESTAMP
    RETURNING video_id, consecutive_failures, retry_after
),
error_insert AS (
    INSERT INTO pipeline_errors (
        pipeline_run_id,
        workflow,
        node,
        error_type,
        error_message,
        external_id,
        retry_count,
        metadata
    )
    SELECT
        arguments.pipeline_run_id,
        '02 - TrendLens - Video Snapshot Tracker',
        'Persistir snapshots do lote',
        failed_items.error_type,
        failed_items.error_reason,
        failed_items.external_id,
        0,
        jsonb_build_object(
            'batch_number', arguments.batch_number,
            'video_id', failed_items.video_id,
            'consecutive_failures', failed_state_upsert.consecutive_failures,
            'retry_after', failed_state_upsert.retry_after
        )
      FROM arguments
      JOIN failed_items ON TRUE
      JOIN failed_state_upsert USING (video_id)
    RETURNING id
),
counts AS (
    SELECT
        (SELECT count(*)::INTEGER FROM expected) AS expected_count,
        (SELECT count(*)::INTEGER FROM failed_items WHERE error_type = 'youtube_video_not_returned') AS missing_count,
        (SELECT count(*)::INTEGER FROM failed_items WHERE error_type = 'youtube_view_count_missing') AS invalid_count,
        (SELECT count(*)::INTEGER FROM snapshot_insert) AS inserted_count,
        (SELECT count(*)::INTEGER FROM successful_items)
            - (SELECT count(*)::INTEGER FROM snapshot_insert) AS duplicate_count,
        (SELECT count(*)::INTEGER FROM failed_state_upsert) AS backoff_count
),
run_update AS (
    UPDATE pipeline_runs
       SET items_received = pipeline_runs.items_received + counts.expected_count,
           items_processed = pipeline_runs.items_processed + counts.inserted_count,
           items_skipped = pipeline_runs.items_skipped + counts.duplicate_count,
           items_failed = pipeline_runs.items_failed + counts.missing_count + counts.invalid_count,
           api_calls = pipeline_runs.api_calls + 1,
           quota_units_estimated = pipeline_runs.quota_units_estimated + arguments.quota_cost,
           metadata = jsonb_set(
               jsonb_set(
                   pipeline_runs.metadata,
                   '{videos_list_calls}',
                   to_jsonb(COALESCE((pipeline_runs.metadata ->> 'videos_list_calls')::INTEGER, 0) + 1),
                   TRUE
               ),
               '{snapshot_backoff_videos}',
               to_jsonb(COALESCE((pipeline_runs.metadata ->> 'snapshot_backoff_videos')::INTEGER, 0) + counts.backoff_count),
               TRUE
           )
      FROM arguments
      CROSS JOIN counts
     WHERE pipeline_runs.id = arguments.pipeline_run_id
    RETURNING
        pipeline_runs.id,
        pipeline_runs.status,
        pipeline_runs.items_received,
        pipeline_runs.items_processed,
        pipeline_runs.items_skipped,
        pipeline_runs.items_failed,
        pipeline_runs.api_calls,
        pipeline_runs.quota_units_estimated
)
SELECT
    run_update.id,
    run_update.status,
    run_update.items_received,
    run_update.items_processed,
    run_update.items_skipped,
    run_update.items_failed,
    run_update.api_calls,
    run_update.quota_units_estimated,
    arguments.batch_number,
    counts.expected_count,
    counts.inserted_count,
    counts.duplicate_count,
    counts.missing_count,
    counts.invalid_count,
    counts.backoff_count,
    COALESCE((SELECT array_agg(id ORDER BY id) FROM error_insert), ARRAY[]::BIGINT[])
  FROM run_update
  CROSS JOIN arguments
  CROSS JOIN counts;
$$;

DROP TRIGGER IF EXISTS video_snapshot_tracking_state_set_updated_at
    ON video_snapshot_tracking_state;
CREATE TRIGGER video_snapshot_tracking_state_set_updated_at
BEFORE UPDATE ON video_snapshot_tracking_state
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

COMMIT;
