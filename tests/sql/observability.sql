\set ON_ERROR_STOP on

BEGIN;

UPDATE settings SET value = '"24 hours"'::JSONB WHERE key = 'OBSERVABILITY_PERIOD';
UPDATE settings SET value = '"observability-test-v1"'::JSONB WHERE key = 'OBSERVABILITY_VERSION';
UPDATE settings SET value = '60'::JSONB WHERE key = 'OBSERVABILITY_STALE_RUN_MINUTES';
UPDATE settings SET value = '7'::JSONB WHERE key = 'OBSERVABILITY_HIGH_VIRALITY_THRESHOLD';
UPDATE settings SET value = '7'::JSONB WHERE key = 'OBSERVABILITY_HIGH_OPPORTUNITY_THRESHOLD';
UPDATE settings SET value = '10'::JSONB WHERE key = 'OBSERVABILITY_ERROR_LIMIT';
UPDATE settings SET value = '"metrics-observability-test-v1"'::JSONB WHERE key = 'METRICS_CALCULATION_VERSION';
UPDATE settings SET value = '"trend-observability-test-v1"'::JSONB WHERE key = 'TREND_CALCULATION_VERSION';
UPDATE settings SET value = '"opportunity-observability-test-v1"'::JSONB WHERE key = 'OPPORTUNITY_CALCULATION_VERSION';

INSERT INTO pipeline_runs (
    id, workflow, started_at, finished_at, status,
    items_received, items_processed, items_skipped, items_failed,
    api_calls, quota_units_estimated, duration_seconds, metadata
)
VALUES
    (
        91001, '01 - TrendLens - YouTube Data Collector',
        '1900-04-03 01:00:00+00', '1900-04-03 01:00:12+00', 'success',
        5, 4, 1, 0, 4, 2, 12,
        '{"new_videos":3,"duplicate_videos":1,"snapshots_collected":3}'::JSONB
    ),
    (
        91002, '02 - TrendLens - Video Snapshot Tracker',
        '1900-04-03 02:00:00+00', '1900-04-03 02:00:06+00', 'partial',
        3, 2, 0, 1, 1, 1, 6,
        '{"snapshots_collected":2}'::JSONB
    ),
    (
        91003, '03 - TrendLens - AI Content Classifier',
        '1900-04-03 03:00:00+00', '1900-04-03 03:00:09+00', 'partial',
        3, 2, 0, 1, 3, 0, 9,
        '{"classifications_created":2,"classifications_failed":1}'::JSONB
    ),
    (
        91004, '04 - TrendLens - Metrics Engine & Virality Score',
        '1900-04-02 00:00:00+00', NULL, 'running',
        1, 0, 0, 0, 0, 0, NULL, '{}'::JSONB
    );

INSERT INTO pipeline_errors (
    pipeline_run_id, workflow, node, occurred_at, error_type,
    error_message, external_id, retry_count, metadata
)
VALUES
    (
        91002, '02 - TrendLens - Video Snapshot Tracker', 'Persistir snapshots do lote',
        '1900-04-03 02:00:05+00', 'youtube_snapshot_items_incomplete',
        'Statistics were incomplete', 'obs-video-missing', 0, '{"batch_number":1}'::JSONB
    ),
    (
        91003, '03 - TrendLens - AI Content Classifier', 'Gerar classificação com IA',
        '1900-04-03 03:00:08+00', 'ai_classification_error',
        'Provider request failed after retries', 'obs-video-error', 2, '{"model":"test-model"}'::JSONB
    );

INSERT INTO videos (
    id, platform, external_id, channel_id, title, url, published_at,
    duration_seconds, language, region, short_confidence, target_language, detected_language, language_confidence, language_detection_source, language_eligibility
)
VALUES
    (91001, 'youtube', 'obs-video-1', 'obs-channel', 'Observability video 1', 'https://example.test/obs-video-1', '1900-04-02 12:00:00+00', 45, 'pt', 'BR', 'high', 'pt', 'pt', 1, 'manual', 'eligible'),
    (91002, 'youtube', 'obs-video-2', 'obs-channel', 'Observability video 2', 'https://example.test/obs-video-2', '1900-04-02 13:00:00+00', 50, 'pt', 'BR', 'medium', 'pt', 'pt', 1, 'manual', 'eligible');

INSERT INTO video_classifications (
    video_id, category_id, topic, content_type, format, hook_type,
    source_type, presentation_style, originality_score, copyright_risk,
    reused_content_risk, ai_confidence, classification_model,
    prompt_version, classified_at
)
SELECT
    video_id, category.id, 'technology', 'education', 'explainer', 'question',
    'original', 'voiceover', 0.9, 0.1, 0.1, 0.9,
    'observability-test-model', 'observability-test-prompt-v1', classified_at
FROM (
    VALUES
        (91001::BIGINT, '1900-04-03 03:00:03+00'::TIMESTAMPTZ),
        (91002::BIGINT, '1900-04-03 03:00:06+00'::TIMESTAMPTZ)
) fixture(video_id, classified_at)
CROSS JOIN (SELECT id FROM categories WHERE slug = 'technology') category;

INSERT INTO video_snapshots (id, video_id, collected_at, views, likes, comments)
VALUES
    (91001, 91001, '1900-04-03 04:00:00+00', 10000, 1000, 100),
    (91002, 91001, '1900-04-03 05:00:00+00', 12000, 1100, 120);

INSERT INTO video_metrics (
    video_id, snapshot_id, virality_score, calculation_version, calculated_at
)
VALUES
    (91001, 91001, 8.5, 'metrics-observability-test-v1', '1900-04-03 04:01:00+00'),
    (91001, 91002, 8.0, 'metrics-observability-test-v1', '1900-04-03 05:01:00+00');

INSERT INTO category_statistics (
    period_start, period_end, platform, region, language, category_slug,
    dimension_type, dimension_value, sample_size, median_virality,
    opportunity_score, opportunity_rank, opportunity_percentile,
    opportunity_component_count, opportunity_calculation_version,
    opportunity_calculated_at, trend_direction, calculation_version
)
VALUES (
    '1900-04-01 00:00:00+00', '1900-04-03 06:00:00+00',
    'youtube', 'BR', 'pt', 'technology', 'category', 'technology',
    40, 8.0, 8.2, 1, 1, 3, 'opportunity-observability-test-v1',
    '1900-04-03 06:01:00+00', 'rising', 'trend-observability-test-v1'
);

DO $$
DECLARE
    observability RECORD;
    persisted_count INTEGER;
    category_count INTEGER;
BEGIN
    SELECT * INTO observability
      FROM build_pipeline_observability('1900-04-03 12:34:00+00');

    IF observability.period_start <> TIMESTAMPTZ '1900-04-02 12:00:00+00'
       OR observability.period_end <> TIMESTAMPTZ '1900-04-03 12:00:00+00'
       OR observability.observability_version <> 'observability-test-v1'
       OR observability.overall_status <> 'critical'
       OR observability.workflow_count <> 10
       OR observability.run_count <> 3
       OR observability.error_count <> 2
       OR observability.retry_count <> 2 THEN
        RAISE EXCEPTION 'Observability summary is incorrect: %', row_to_json(observability);
    END IF;

    IF observability.report_json #>> '{pipeline_metrics,videos_collected}' <> '4'
       OR observability.report_json #>> '{pipeline_metrics,new_videos}' <> '3'
       OR observability.report_json #>> '{pipeline_metrics,duplicate_videos}' <> '1'
       OR observability.report_json #>> '{pipeline_metrics,snapshots_collected}' <> '5'
       OR observability.report_json #>> '{pipeline_metrics,ai_classifications}' <> '2'
       OR observability.report_json #>> '{pipeline_metrics,classification_errors}' <> '1'
       OR observability.report_json #>> '{pipeline_metrics,average_classification_latency_seconds}' <> '3.000'
       OR observability.report_json #>> '{pipeline_metrics,api_errors}' <> '2'
       OR observability.report_json #>> '{pipeline_metrics,retries}' <> '2'
       OR observability.report_json #>> '{pipeline_metrics,items_with_error}' <> '2'
       OR observability.report_json #>> '{pipeline_metrics,high_virality_videos,total}' <> '1'
       OR jsonb_array_length(observability.report_json #> '{pipeline_metrics,high_virality_videos,top_items}') <> 1
       OR observability.report_json #>> '{pipeline_metrics,high_virality_videos,top_items,0,virality_score}' <> '8.0000'
       OR observability.report_json #>> '{pipeline_metrics,high_opportunity_categories,total}' <> '1'
       OR jsonb_array_length(observability.report_json -> 'workflow_health') <> 10
       OR jsonb_array_length(observability.report_json -> 'recent_errors') <> 2
       OR observability.report_json::TEXT ~ '"error_message"[[:space:]]*:|Provider request failed|batch_number|test-model'
       OR observability.source_hash !~ '^[a-f0-9]{32}$' THEN
        RAISE EXCEPTION 'Observability JSON is incorrect: %', observability.report_json;
    END IF;

    SELECT (item ->> 'videos')::INTEGER INTO category_count
      FROM jsonb_array_elements(observability.report_json #> '{pipeline_metrics,videos_by_category}') item
     WHERE item ->> 'category' = 'technology';

    IF category_count <> 2 THEN
        RAISE EXCEPTION 'Videos by category is incorrect: %', category_count;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM jsonb_array_elements(observability.report_json -> 'workflow_health') item
         WHERE item ->> 'stage' = 'metrics'
           AND item ->> 'health_status' = 'critical'
           AND item #>> '{runs,stale_running}' = '1'
    ) OR NOT EXISTS (
        SELECT 1
          FROM jsonb_array_elements(observability.report_json -> 'workflow_health') item
         WHERE item ->> 'stage' = 'classification'
           AND item ->> 'health_status' = 'degraded'
           AND item #>> '{counters,items_processed}' = '2'
           AND item #>> '{counters,items_failed}' = '1'
           AND item #>> '{counters,retries}' = '2'
    ) THEN
        RAISE EXCEPTION 'Workflow health does not expose stale runs and classifier counters';
    END IF;

    INSERT INTO pipeline_observability_reports (
        period_start, period_end, generated_at, observability_version,
        overall_status, workflow_count, run_count, error_count, retry_count,
        report_json, source_hash
    ) VALUES (
        observability.period_start, observability.period_end, observability.generated_at,
        observability.observability_version, observability.overall_status,
        observability.workflow_count, observability.run_count, observability.error_count,
        observability.retry_count, observability.report_json, observability.source_hash
    );

    INSERT INTO pipeline_observability_reports (
        period_start, period_end, generated_at, observability_version,
        overall_status, workflow_count, run_count, error_count, retry_count,
        report_json, source_hash
    ) VALUES (
        observability.period_start, observability.period_end, observability.generated_at,
        observability.observability_version, observability.overall_status,
        observability.workflow_count, observability.run_count, observability.error_count,
        observability.retry_count, observability.report_json, observability.source_hash
    )
    ON CONFLICT (period_start, period_end, observability_version, source_hash) DO NOTHING;

    SELECT count(*) INTO persisted_count
      FROM pipeline_observability_reports
     WHERE source_hash = observability.source_hash;

    IF persisted_count <> 1 THEN
        RAISE EXCEPTION 'Observability persistence is not idempotent; found % rows', persisted_count;
    END IF;

    BEGIN
        UPDATE pipeline_observability_reports
           SET report_json = '{}'::JSONB
         WHERE source_hash = observability.source_hash;
        RAISE EXCEPTION 'Incomplete observability JSON was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'Observability SQL validation passed' AS result;
