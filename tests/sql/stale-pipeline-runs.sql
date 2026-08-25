\set ON_ERROR_STOP on

BEGIN;

UPDATE settings
   SET value = '60'::JSONB
 WHERE key = 'OBSERVABILITY_STALE_RUN_MINUTES';

INSERT INTO pipeline_runs (
    id, workflow, started_at, finished_at, status,
    items_received, items_processed, items_skipped, items_failed,
    api_calls, quota_units_estimated, duration_seconds, metadata
)
VALUES
    (
        92001, '03 - TrendLens - AI Content Classifier',
        '2100-05-01 08:00:00+00', NULL, 'running',
        30, 27, 0, 3, 30, 0, NULL, '{"fixture":"stale"}'::JSONB
    ),
    (
        92002, '05 - TrendLens - Trend Engine',
        '2100-05-01 11:00:00+00', NULL, 'running',
        1, 0, 0, 0, 0, 0, NULL, '{"fixture":"boundary"}'::JSONB
    ),
    (
        92003, '08 - TrendLens - Recommendation AI',
        '2100-05-01 11:01:00+00', NULL, 'running',
        1, 0, 0, 0, 0, 0, NULL, '{"fixture":"recent"}'::JSONB
    ),
    (
        92004, '01 - TrendLens - YouTube Data Collector',
        '2100-05-01 08:00:00+00', '2100-05-01 08:10:00+00', 'success',
        5, 5, 0, 0, 2, 2, 600, '{"fixture":"completed"}'::JSONB
    );

DO $$
DECLARE
    reconciled RECORD;
    reconciled_count INTEGER;
BEGIN
    IF to_regprocedure('reconcile_stale_pipeline_runs(timestamptz,integer)') IS NULL THEN
        RAISE EXCEPTION 'Stale pipeline run reconciliation function is missing';
    END IF;

    SELECT count(*) INTO reconciled_count
      FROM reconcile_stale_pipeline_runs('2100-05-01 12:00:00+00', NULL);

    IF reconciled_count <> 1 THEN
        RAISE EXCEPTION 'Expected one stale run to be reconciled, found %', reconciled_count;
    END IF;

    SELECT * INTO reconciled
      FROM pipeline_runs
     WHERE id = 92001;

    IF reconciled.status <> 'cancelled'
       OR reconciled.finished_at <> TIMESTAMPTZ '2100-05-01 09:00:00+00'
       OR reconciled.duration_seconds <> 3600
       OR reconciled.items_received <> 30
       OR reconciled.items_processed <> 27
       OR reconciled.items_failed <> 3
       OR reconciled.metadata ->> 'fixture' <> 'stale'
       OR reconciled.metadata #>> '{stale_run_reconciliation,previous_status}' <> 'running'
       OR reconciled.metadata #>> '{stale_run_reconciliation,reconciled_status}' <> 'cancelled'
       OR reconciled.metadata #>> '{stale_run_reconciliation,reason}' <> 'stale_running_timeout'
       OR reconciled.metadata #>> '{stale_run_reconciliation,stale_after_minutes}' <> '60'
       OR (reconciled.metadata #>> '{stale_run_reconciliation,finished_at_inferred}')::BOOLEAN IS NOT TRUE THEN
        RAISE EXCEPTION 'Stale run reconciliation is incorrect: %', row_to_json(reconciled);
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pipeline_runs
         WHERE id IN (92002, 92003)
           AND status <> 'running'
    ) OR NOT EXISTS (
        SELECT 1
          FROM pipeline_runs
         WHERE id = 92004
           AND status = 'success'
           AND finished_at = TIMESTAMPTZ '2100-05-01 08:10:00+00'
    ) THEN
        RAISE EXCEPTION 'Boundary, recent, or completed runs were modified';
    END IF;

    SELECT count(*) INTO reconciled_count
      FROM reconcile_stale_pipeline_runs('2100-05-01 12:00:00+00', NULL);

    IF reconciled_count <> 0 THEN
        RAISE EXCEPTION 'Reconciliation is not idempotent; found % rows on the second call', reconciled_count;
    END IF;

    BEGIN
        PERFORM * FROM reconcile_stale_pipeline_runs(NULL, 60);
        RAISE EXCEPTION 'Null reconciliation reference time was accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'Reconciliation reference time must not be null' THEN
            RAISE;
        END IF;
    END;
END;
$$;

ROLLBACK;

SELECT 'Stale pipeline run reconciliation SQL validation passed' AS result;
