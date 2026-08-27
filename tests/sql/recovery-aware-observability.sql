\set ON_ERROR_STOP on

BEGIN;

UPDATE settings
   SET value = '"v3-recovery-aware"'::JSONB
 WHERE key = 'OBSERVABILITY_VERSION';

INSERT INTO pipeline_runs (
    id, workflow, started_at, finished_at, status,
    items_received, items_processed, items_skipped, items_failed,
    api_calls, quota_units_estimated, duration_seconds, metadata
)
VALUES
    (
        92201, '03 - TrendLens - AI Content Classifier',
        '2100-06-01 09:00:00+00', '2100-06-01 09:01:00+00', 'failed',
        1, 0, 0, 1, 1, 0, 60, '{"fixture":"historical_failure"}'::JSONB
    ),
    (
        92202, '03 - TrendLens - AI Content Classifier',
        '2100-06-01 10:00:00+00', '2100-06-01 10:01:00+00', 'success',
        1, 1, 0, 0, 1, 0, 60, '{"fixture":"recovered"}'::JSONB
    );

DO $$
DECLARE
    observability RECORD;
    classifier_health JSONB;
BEGIN
    IF to_regprocedure('build_pipeline_observability_recovery_aware(timestamptz)') IS NULL THEN
        RAISE EXCEPTION 'Recovery-aware observability function is missing';
    END IF;

    SELECT *
      INTO observability
      FROM build_pipeline_observability_recovery_aware('2100-06-01 12:34:00+00');

    SELECT item
      INTO classifier_health
      FROM jsonb_array_elements(observability.report_json -> 'workflow_health') item
     WHERE item ->> 'workflow' = '03 - TrendLens - AI Content Classifier';

    IF observability.observability_version <> 'v3-recovery-aware'
       OR observability.overall_status <> 'degraded'
       OR observability.report_json ->> 'status' <> 'degraded'
       OR observability.report_json #>> '{summary,critical_workflows}' <> '0'
       OR classifier_health ->> 'health_status' <> 'degraded'
       OR classifier_health #>> '{latest_run,status}' <> 'success'
       OR classifier_health #>> '{runs,failed}' <> '1'
       OR observability.report_json #>> '{methodology,health_state_policy}' <> 'latest_terminal_status_with_window_history'
       OR observability.source_hash !~ '^[a-f0-9]{32}$'
       OR observability.report_json ->> 'source_hash' <> observability.source_hash THEN
        RAISE EXCEPTION 'Recovered observability state is incorrect: %', observability.report_json;
    END IF;

    INSERT INTO pipeline_runs (
        id, workflow, started_at, finished_at, status,
        items_received, items_processed, items_skipped, items_failed,
        api_calls, quota_units_estimated, duration_seconds, metadata
    )
    VALUES (
        92203, '03 - TrendLens - AI Content Classifier',
        '2100-06-01 11:00:00+00', '2100-06-01 11:01:00+00', 'failed',
        1, 0, 0, 1, 1, 0, 60, '{"fixture":"current_failure"}'::JSONB
    );

    SELECT *
      INTO observability
      FROM build_pipeline_observability_recovery_aware('2100-06-01 12:34:00+00');

    SELECT item
      INTO classifier_health
      FROM jsonb_array_elements(observability.report_json -> 'workflow_health') item
     WHERE item ->> 'workflow' = '03 - TrendLens - AI Content Classifier';

    IF observability.overall_status <> 'critical'
       OR classifier_health ->> 'health_status' <> 'critical'
       OR classifier_health #>> '{latest_run,status}' <> 'failed' THEN
        RAISE EXCEPTION 'Current failure was not marked critical: %', observability.report_json;
    END IF;
END;
$$;

ROLLBACK;

SELECT 'Recovery-aware observability SQL validation passed' AS result;

