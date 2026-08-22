\set ON_ERROR_STOP on

BEGIN;

UPDATE settings SET value = '"recommendation-test-model"'::JSONB WHERE key = 'RECOMMENDATION_MODEL';
UPDATE settings SET value = '"recommendation-test-v1"'::JSONB WHERE key = 'RECOMMENDATION_PROMPT_VERSION';
UPDATE settings SET value = '3'::JSONB WHERE key = 'RECOMMENDATION_MAX_CATEGORIES_PER_RUN';
UPDATE settings SET value = '5'::JSONB WHERE key = 'RECOMMENDATION_MIN_OPPORTUNITY_SCORE';
UPDATE settings SET value = '3'::JSONB WHERE key = 'RECOMMENDATION_CONTEXT_LIMIT';
UPDATE settings SET value = '"trend-recommendation-test-v1"'::JSONB WHERE key = 'TREND_CALCULATION_VERSION';

INSERT INTO category_statistics (
    period_start, period_end, platform, region, language, category_slug,
    dimension_type, dimension_value, sample_size, median_views, p75_views,
    p90_views, median_engagement, median_velocity, median_virality,
    median_monetization, outlier_rate, high_performance_rate,
    consistency_score, opportunity_score, opportunity_rank,
    opportunity_percentile, opportunity_component_count,
    opportunity_calculation_version, opportunity_calculated_at,
    trend_direction, calculation_version
)
VALUES
    ('1900-02-01', '1900-02-08', 'youtube', 'BR', 'pt', 'technology', 'category', 'technology', 40, 1000, 1500, 2200, 0.08, 500, 9, 8, 0.20, 0.30, 7, 8.35, 1, 1, 3, 'opportunity-test-v1', '1900-02-08', 'rising', 'trend-recommendation-test-v1'),
    ('1900-02-01', '1900-02-08', 'youtube', 'BR', 'pt', 'education', 'category', 'education', 35, 800, 1200, 1800, 0.06, 350, 7, 7, 0.12, 0.20, 6, 6.85, 2, 0.5, 3, 'opportunity-test-v1', '1900-02-08', 'stable', 'trend-recommendation-test-v1'),
    ('1900-02-01', '1900-02-08', 'youtube', 'BR', 'pt', 'gaming', 'category', 'gaming', 20, 400, 700, 1100, 0.04, 180, 4, 4, 0.05, 0.10, 3, 3.85, 3, 0, 3, 'opportunity-test-v1', '1900-02-08', 'declining', 'trend-recommendation-test-v1'),
    ('1900-02-01', '1900-02-08', 'youtube', 'BR', 'pt', 'technology', 'category_format_source', 'technology|tutorial|original', 25, 900, 1400, 2000, 0.07, 420, 8, 8, 0.18, 0.25, 6, 7.7, 1, 1, 3, 'opportunity-test-v1', '1900-02-08', 'rising', 'trend-recommendation-test-v1'),
    ('1900-02-01', '1900-02-08', 'youtube', 'BR', 'pt', NULL, 'format', 'tutorial', 50, 850, 1300, 1900, 0.065, 390, 7.5, 7.8, 0.16, 0.22, 6.5, 7.41, 1, 1, 3, 'opportunity-test-v1', '1900-02-08', 'rising', 'trend-recommendation-test-v1'),
    ('1900-02-01', '1900-02-08', 'youtube', 'BR', 'pt', NULL, 'hook_type', 'curiosity_gap', 45, 820, 1250, 1850, 0.064, 380, 7.4, 7.4, 0.15, 0.21, 6.4, 7.19, 1, 1, 3, 'opportunity-test-v1', '1900-02-08', 'rising', 'trend-recommendation-test-v1');

DO $$
DECLARE
    candidate RECORD;
    candidate_count INTEGER;
BEGIN
    SELECT count(*) INTO candidate_count FROM select_recommendation_candidates();
    IF candidate_count <> 2 THEN
        RAISE EXCEPTION 'Expected two recommendation candidates, found %', candidate_count;
    END IF;

    SELECT * INTO candidate FROM select_recommendation_candidates() LIMIT 1;

    IF candidate.category <> 'technology'
       OR candidate.opportunity_score <> 8.35
       OR candidate.recommendation_model <> 'recommendation-test-model'
       OR candidate.prompt_version <> 'recommendation-test-v1'
       OR candidate.evidence_json #>> '{input_scope,level}' <> 'aggregated'
       OR (candidate.evidence_json #>> '{input_scope,contains_individual_videos}')::BOOLEAN
       OR candidate.evidence_json::TEXT ~ '"(video_id|external_id|title|description|channel_id)"'
       OR jsonb_array_length(candidate.evidence_json -> 'category_format_source_patterns') <> 1
       OR jsonb_array_length(candidate.evidence_json -> 'context_top_formats') <> 1
       OR jsonb_array_length(candidate.evidence_json -> 'context_top_hooks') <> 1
       OR candidate.evidence_hash !~ '^[a-f0-9]{32}$' THEN
        RAISE EXCEPTION 'Recommendation candidate is incorrect: %', row_to_json(candidate);
    END IF;

    INSERT INTO recommendations (
        category, period_start, period_end, platform, region, language,
        opportunity_score, virality_score, monetization_score, consistency_score,
        summary, recommended_formats, recommended_hooks, risks,
        monetization_notes, evidence_json, evidence_hash, model,
        prompt_version, source_calculation_version, source_opportunity_version
    ) VALUES (
        candidate.category, candidate.period_start, candidate.period_end,
        candidate.platform, candidate.region, candidate.language,
        candidate.opportunity_score, candidate.virality_score,
        candidate.monetization_score, candidate.consistency_score,
        'Resumo agregado de teste.', ARRAY['tutorial_original'],
        ARRAY['pergunta_com_lacuna_de_curiosidade'],
        ARRAY['amostra_limitada'], ARRAY['priorizar_producao_original'],
        candidate.evidence_json, candidate.evidence_hash,
        candidate.recommendation_model, candidate.prompt_version,
        candidate.source_calculation_version, candidate.source_opportunity_version
    );

    SELECT count(*) INTO candidate_count FROM select_recommendation_candidates();
    IF candidate_count <> 1 THEN
        RAISE EXCEPTION 'Persisted evidence was selected again; found % candidates', candidate_count;
    END IF;

    BEGIN
        UPDATE recommendations SET summary = '   ' WHERE category = 'technology';
        RAISE EXCEPTION 'Blank recommendation summary was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE recommendations SET recommended_formats = ARRAY[]::TEXT[] WHERE category = 'technology';
        RAISE EXCEPTION 'Empty recommended formats were accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE recommendations SET evidence_json = '{}'::JSONB WHERE category = 'technology';
        RAISE EXCEPTION 'Evidence without aggregate scope was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'Recommendation AI SQL validation passed' AS result;
