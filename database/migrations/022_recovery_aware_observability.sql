BEGIN;

INSERT INTO settings (key, value, description)
VALUES (
    'OBSERVABILITY_VERSION',
    '"v3-recovery-aware"'::JSONB,
    'Versão da observabilidade com reconciliação de runs obsoletos e saúde baseada no estado terminal mais recente.'
)
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value,
    description = EXCLUDED.description;

CREATE OR REPLACE FUNCTION build_pipeline_observability_recovery_aware(
    p_generated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ,
    generated_at TIMESTAMPTZ,
    observability_version TEXT,
    overall_status TEXT,
    workflow_count INTEGER,
    run_count INTEGER,
    error_count INTEGER,
    retry_count INTEGER,
    report_json JSONB,
    source_hash TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    base_report RECORD;
    health_items JSONB;
    rendered_report JSONB;
    source_payload JSONB;
    rendered_hash TEXT;
    healthy_count INTEGER;
    degraded_count INTEGER;
    critical_count INTEGER;
    unknown_count INTEGER;
    recovered_overall_status TEXT;
BEGIN
    SELECT *
      INTO STRICT base_report
      FROM build_pipeline_observability(p_generated_at);

    SELECT COALESCE(
        jsonb_agg(
            jsonb_set(item, '{health_status}', to_jsonb(
                CASE
                    WHEN COALESCE((item #>> '{runs,stale_running}')::INTEGER, 0) > 0
                      OR item #>> '{latest_run,status}' = 'failed'
                        THEN 'critical'
                    WHEN COALESCE((item #>> '{runs,failed}')::INTEGER, 0) > 0
                      OR COALESCE((item #>> '{runs,partial}')::INTEGER, 0) > 0
                      OR COALESCE((item #>> '{counters,error_events}')::INTEGER, 0) > 0
                      OR item #>> '{latest_run,status}' IN ('partial', 'cancelled')
                        THEN 'degraded'
                    WHEN COALESCE((item #>> '{runs,total}')::INTEGER, 0) = 0
                        THEN 'unknown'
                    ELSE 'healthy'
                END
            ), false)
            ORDER BY item_order
        ),
        '[]'::JSONB
    )
      INTO health_items
      FROM jsonb_array_elements(base_report.report_json -> 'workflow_health')
           WITH ORDINALITY AS workflow_item(item, item_order);

    SELECT
        count(*) FILTER (WHERE item ->> 'health_status' = 'healthy')::INTEGER,
        count(*) FILTER (WHERE item ->> 'health_status' = 'degraded')::INTEGER,
        count(*) FILTER (WHERE item ->> 'health_status' = 'critical')::INTEGER,
        count(*) FILTER (WHERE item ->> 'health_status' = 'unknown')::INTEGER
      INTO healthy_count, degraded_count, critical_count, unknown_count
      FROM jsonb_array_elements(health_items) AS workflow_item(item);

    recovered_overall_status := CASE
        WHEN critical_count > 0 THEN 'critical'
        WHEN degraded_count > 0 THEN 'degraded'
        ELSE 'healthy'
    END;

    rendered_report := base_report.report_json
        || jsonb_build_object(
            'observability_version', 'v3-recovery-aware',
            'status', recovered_overall_status,
            'workflow_health', health_items,
            'summary', (base_report.report_json -> 'summary') || jsonb_build_object(
                'healthy_workflows', healthy_count,
                'degraded_workflows', degraded_count,
                'critical_workflows', critical_count,
                'unknown_workflows', unknown_count
            ),
            'methodology', (base_report.report_json -> 'methodology') || jsonb_build_object(
                'health_state_policy', 'latest_terminal_status_with_window_history'
            )
        );

    source_payload := rendered_report - 'generated_at' - 'source_hash';
    rendered_hash := md5(source_payload::TEXT);
    rendered_report := source_payload || jsonb_build_object(
        'generated_at', p_generated_at,
        'source_hash', rendered_hash
    );

    RETURN QUERY
    SELECT
        base_report.period_start,
        base_report.period_end,
        p_generated_at,
        'v3-recovery-aware'::TEXT,
        recovered_overall_status,
        base_report.workflow_count,
        base_report.run_count,
        base_report.error_count,
        base_report.retry_count,
        rendered_report,
        rendered_hash;
END;
$$;

COMMIT;

