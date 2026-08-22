\set ON_ERROR_STOP on

BEGIN;

UPDATE settings SET value = '"BR"'::JSONB WHERE key = 'REGION';
UPDATE settings SET value = '"pt"'::JSONB WHERE key = 'LANGUAGE';
UPDATE settings SET value = '"trend-report-test-v1"'::JSONB WHERE key = 'TREND_CALCULATION_VERSION';
UPDATE settings SET value = '"opportunity-report-test-v1"'::JSONB WHERE key = 'OPPORTUNITY_CALCULATION_VERSION';
UPDATE settings SET value = '"report-test-v2"'::JSONB WHERE key = 'RECOMMENDATION_PROMPT_VERSION';
UPDATE settings SET value = '"report-test-v1"'::JSONB WHERE key = 'REPORT_VERSION';
UPDATE settings SET value = '3'::JSONB WHERE key = 'REPORT_TOP_OPPORTUNITIES_LIMIT';
UPDATE settings SET value = '2'::JSONB WHERE key = 'REPORT_VIRAL_RISK_LIMIT';
UPDATE settings SET value = '2'::JSONB WHERE key = 'REPORT_EMERGING_TRENDS_LIMIT';
UPDATE settings SET value = '6'::JSONB WHERE key = 'REPORT_VIRALITY_RISK_MIN';
UPDATE settings SET value = '5'::JSONB WHERE key = 'REPORT_MONETIZATION_RISK_MAX';

INSERT INTO category_statistics (
    period_start, period_end, platform, region, language, category_slug,
    dimension_type, dimension_value, sample_size, median_views, p75_views,
    p90_views, median_engagement, median_velocity, median_virality,
    median_monetization, outlier_rate, high_performance_rate,
    consistency_score, opportunity_score, opportunity_rank,
    opportunity_percentile, opportunity_component_count,
    opportunity_calculation_version, opportunity_calculated_at,
    previous_sample_size, trend_change, trend_direction, calculation_version
)
VALUES
    ('1900-03-01', '1900-03-08', 'youtube', 'BR', 'pt', 'technology', 'category', 'technology',
     40, 1000, 1500, 2200, 0.08, 500, 9, 8, 0.20, 0.30, 7, 8.35, 1, 1, 3,
     'opportunity-report-test-v1', '1900-03-08', 35, 0.20, 'rising', 'trend-report-test-v1'),
    ('1900-03-01', '1900-03-08', 'youtube', 'BR', 'pt', 'movie_tv_clips', 'category', 'movie_tv_clips',
     35, 900, 1300, 2000, 0.06, 420, 8.5, 3, 0.18, 0.25, 5, 6.80, 2, 0.6667, 3,
     'opportunity-report-test-v1', '1900-03-08', 34, 0.03, 'stable', 'trend-report-test-v1'),
    ('1900-03-01', '1900-03-08', 'youtube', 'BR', 'pt', 'education', 'category', 'education',
     50, 800, 1200, 1800, 0.05, 350, 6, 7, 0.10, 0.18, 8, 6.25, 3, 0.3333, 3,
     'opportunity-report-test-v1', '1900-03-08', 48, 0.02, 'stable', 'trend-report-test-v1'),
    ('1900-03-01', '1900-03-08', 'youtube', 'BR', 'pt', 'gaming', 'category', 'gaming',
     20, 400, 700, 1100, 0.04, 180, 4, 4, 0.05, 0.10, 3, 3.85, 4, 0, 3,
     'opportunity-report-test-v1', '1900-03-08', 10, NULL, 'insufficient_data', 'trend-report-test-v1');

INSERT INTO recommendations (
    category, period_start, period_end, platform, region, language,
    opportunity_score, virality_score, monetization_score, consistency_score,
    summary, recommended_formats, recommended_hooks, risks,
    monetization_notes, evidence_json, evidence_hash, model,
    prompt_version, source_calculation_version, source_opportunity_version
)
VALUES
    (
        'technology', '1900-03-01', '1900-03-08', 'youtube', 'BR', 'pt',
        8.35, 9, 8, 7, 'Tecnologia combina oportunidade e produção original.',
        ARRAY['tutorial_original'], ARRAY['pergunta_contextual'],
        ARRAY['amostra_limitada'], ARRAY['priorizar_roteiro_original'],
        '{"input_scope":{"level":"aggregated","contains_individual_videos":false},"category_statistics":{"sample_size":40}}',
        md5('technology-report-evidence'), 'report-test-model', 'report-test-v2',
        'trend-report-test-v1', 'opportunity-report-test-v1'
    ),
    (
        'movie_tv_clips', '1900-03-01', '1900-03-08', 'youtube', 'BR', 'pt',
        6.80, 8.5, 3, 5, 'Interesse alto, com necessidade de abordagem transformativa.',
        ARRAY['analise_de_cenas'], ARRAY['contexto_antes_do_trecho'],
        ARRAY['risco_de_conteudo_reutilizado'], ARRAY['evitar_republicacao_direta'],
        '{"input_scope":{"level":"aggregated","contains_individual_videos":false},"category_statistics":{"sample_size":35}}',
        md5('movie-report-evidence'), 'report-test-model', 'report-test-v1',
        'trend-report-test-v1', 'opportunity-report-test-v1'
    );

DO $$
DECLARE
    report_row RECORD;
    persisted_count INTEGER;
BEGIN
    SELECT * INTO report_row
      FROM build_trendlens_report(TIMESTAMPTZ '1900-03-09 12:00:00+00');

    IF report_row.period_start <> TIMESTAMPTZ '1900-03-01'
       OR report_row.period_end <> TIMESTAMPTZ '1900-03-08'
       OR report_row.platform <> 'youtube'
       OR report_row.region <> 'BR'
       OR report_row.language <> 'pt'
       OR report_row.report_version <> 'report-test-v1'
       OR report_row.source_calculation_version <> 'trend-report-test-v1'
       OR report_row.source_opportunity_version <> 'opportunity-report-test-v1'
       OR report_row.recommendation_prompt_version <> 'report-test-v2'
       OR report_row.videos_analyzed <> 145
       OR report_row.categories_analyzed <> 4
       OR report_row.top_opportunities_count <> 3
       OR report_row.viral_but_risky_count <> 1
       OR report_row.emerging_trends_count <> 1 THEN
        RAISE EXCEPTION 'Report summary is incorrect: %', row_to_json(report_row);
    END IF;

    IF jsonb_array_length(report_row.report_json -> 'top_opportunities') <> 3
       OR jsonb_array_length(report_row.report_json -> 'viral_but_risky') <> 1
       OR jsonb_array_length(report_row.report_json -> 'emerging_trends') <> 1
       OR report_row.report_json #>> '{top_opportunities,0,category}' <> 'technology'
       OR report_row.report_json #> '{top_opportunities,1,recommendation}' <> 'null'::JSONB
       OR report_row.report_json #>> '{coverage,recommendations_available}' <> '1'
       OR report_row.report_json #>> '{coverage,current_prompt_recommendations}' <> '1'
       OR report_row.report_json #>> '{viral_but_risky,0,category}' <> 'movie_tv_clips'
       OR report_row.report_json #>> '{emerging_trends,0,category}' <> 'technology'
       OR report_row.report_json #>> '{methodology,quantitative_source}' <> 'postgresql'
       OR report_row.report_json::TEXT ~ '"(video_id|external_id|description|channel_id)"'
       OR report_row.source_hash !~ '^[a-f0-9]{32}$' THEN
        RAISE EXCEPTION 'Report JSON is incorrect: %', report_row.report_json;
    END IF;

    IF position('# TrendLens — Relatório Semanal' IN report_row.report_markdown) <> 1
       OR position('## Top Opportunities' IN report_row.report_markdown) = 0
       OR position('## Viral but Risky' IN report_row.report_markdown) = 0
       OR position('## Tendências emergentes' IN report_row.report_markdown) = 0
       OR position('Amostra: 40 vídeos' IN report_row.report_markdown) = 0
       OR position('movie_tv_clips' IN lower(replace(report_row.report_markdown, ' ', '_'))) = 0 THEN
        RAISE EXCEPTION 'Report Markdown is incomplete: %', report_row.report_markdown;
    END IF;

    INSERT INTO reports (
        period_start, period_end, platform, region, language, generated_at,
        report_version, source_calculation_version, source_opportunity_version,
        recommendation_prompt_version, videos_analyzed, categories_analyzed,
        top_opportunities_count, viral_but_risky_count, emerging_trends_count,
        report_json, report_markdown, source_hash
    ) VALUES (
        report_row.period_start, report_row.period_end, report_row.platform,
        report_row.region, report_row.language, report_row.generated_at,
        report_row.report_version, report_row.source_calculation_version,
        report_row.source_opportunity_version, report_row.recommendation_prompt_version,
        report_row.videos_analyzed, report_row.categories_analyzed,
        report_row.top_opportunities_count, report_row.viral_but_risky_count,
        report_row.emerging_trends_count, report_row.report_json,
        report_row.report_markdown, report_row.source_hash
    );

    INSERT INTO reports (
        period_start, period_end, platform, region, language, generated_at,
        report_version, source_calculation_version, source_opportunity_version,
        recommendation_prompt_version, videos_analyzed, categories_analyzed,
        top_opportunities_count, viral_but_risky_count, emerging_trends_count,
        report_json, report_markdown, source_hash
    ) VALUES (
        report_row.period_start, report_row.period_end, report_row.platform,
        report_row.region, report_row.language, report_row.generated_at,
        report_row.report_version, report_row.source_calculation_version,
        report_row.source_opportunity_version, report_row.recommendation_prompt_version,
        report_row.videos_analyzed, report_row.categories_analyzed,
        report_row.top_opportunities_count, report_row.viral_but_risky_count,
        report_row.emerging_trends_count, report_row.report_json,
        report_row.report_markdown, report_row.source_hash
    )
    ON CONFLICT (
        period_start, period_end, platform, region, language, report_version,
        source_calculation_version, source_opportunity_version,
        recommendation_prompt_version, source_hash
    ) DO NOTHING;

    SELECT count(*) INTO persisted_count
      FROM reports
     WHERE source_hash = report_row.source_hash;

    IF persisted_count <> 1 THEN
        RAISE EXCEPTION 'Report persistence is not idempotent; found % rows', persisted_count;
    END IF;

    BEGIN
        UPDATE reports SET report_markdown = '   ' WHERE source_hash = report_row.source_hash;
        RAISE EXCEPTION 'Blank Markdown was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE reports SET report_json = '{}'::JSONB WHERE source_hash = report_row.source_hash;
        RAISE EXCEPTION 'JSON without report sections was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'Report Engine SQL validation passed' AS result;
