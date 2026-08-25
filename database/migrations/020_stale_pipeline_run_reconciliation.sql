BEGIN;

INSERT INTO settings (key, value, description)
VALUES (
    'OBSERVABILITY_STALE_RUN_MINUTES',
    '120'::JSONB,
    'Tempo máximo, em minutos, antes de uma execução running ser considerada interrompida e elegível para reconciliação.'
)
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

CREATE INDEX IF NOT EXISTS pipeline_runs_running_started_at_idx
    ON pipeline_runs (started_at)
    WHERE status = 'running';

CREATE OR REPLACE FUNCTION reconcile_stale_pipeline_runs(
    p_as_of TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    p_stale_minutes INTEGER DEFAULT NULL
)
RETURNS TABLE (
    pipeline_run_id BIGINT,
    workflow TEXT,
    started_at TIMESTAMPTZ,
    inferred_finished_at TIMESTAMPTZ,
    previous_status TEXT,
    reconciled_status TEXT,
    stale_after_minutes INTEGER
)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    effective_stale_minutes INTEGER;
BEGIN
    IF p_as_of IS NULL THEN
        RAISE EXCEPTION 'Reconciliation reference time must not be null';
    END IF;

    effective_stale_minutes := GREATEST(
        1,
        COALESCE(
            p_stale_minutes,
            (SELECT (value #>> '{}')::INTEGER
               FROM settings
              WHERE key = 'OBSERVABILITY_STALE_RUN_MINUTES'),
            120
        )
    );

    RETURN QUERY
    WITH updated AS (
        UPDATE pipeline_runs run
           SET finished_at = run.started_at + make_interval(mins => effective_stale_minutes),
               status = 'cancelled',
               duration_seconds = round((effective_stale_minutes::NUMERIC * 60), 3),
               metadata = run.metadata || jsonb_build_object(
                   'stale_run_reconciliation',
                   jsonb_build_object(
                       'previous_status', 'running',
                       'reconciled_status', 'cancelled',
                       'reason', 'stale_running_timeout',
                       'reconciled_at', p_as_of,
                       'stale_after_minutes', effective_stale_minutes,
                       'finished_at_inferred', true
                   )
               )
         WHERE run.status = 'running'
           AND run.started_at < p_as_of - make_interval(mins => effective_stale_minutes)
        RETURNING run.id, run.workflow, run.started_at, run.finished_at, run.status
    )
    SELECT
        updated.id,
        updated.workflow,
        updated.started_at,
        updated.finished_at,
        'running'::TEXT,
        updated.status,
        effective_stale_minutes
      FROM updated
     ORDER BY updated.started_at, updated.id;
END;
$$;

SELECT * FROM reconcile_stale_pipeline_runs(CURRENT_TIMESTAMP);

COMMIT;
