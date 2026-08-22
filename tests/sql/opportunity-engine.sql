\set ON_ERROR_STOP on

BEGIN;

UPDATE settings SET value = '"opportunity-test-v1"'::JSONB WHERE key = 'OPPORTUNITY_CALCULATION_VERSION';
UPDATE settings SET value = '"trend-opportunity-test-v1"'::JSONB WHERE key = 'TREND_CALCULATION_VERSION';
UPDATE settings SET value = '0.50'::JSONB WHERE key = 'OPPORTUNITY_VIRALITY_WEIGHT';
UPDATE settings SET value = '0.35'::JSONB WHERE key = 'OPPORTUNITY_MONETIZATION_WEIGHT';
UPDATE settings SET value = '0.15'::JSONB WHERE key = 'OPPORTUNITY_CONSISTENCY_WEIGHT';

INSERT INTO category_statistics (
    period_start, period_end, platform, region, language, category_slug,
    dimension_type, dimension_value, sample_size, median_virality,
    median_monetization, consistency_score, trend_direction, calculation_version
)
VALUES
    ('1900-01-07 00:00:00+00', '1900-01-14 00:00:00+00', 'youtube', 'BR', 'pt', 'technology', 'category', 'technology', 30, 9, 8, 7, 'rising', 'trend-opportunity-test-v1'),
    ('1900-01-07 00:00:00+00', '1900-01-14 00:00:00+00', 'youtube', 'BR', 'pt', 'education', 'category', 'education', 30, 6, 7, 8, 'stable', 'trend-opportunity-test-v1'),
    ('1900-01-07 00:00:00+00', '1900-01-14 00:00:00+00', 'youtube', 'BR', 'pt', 'entertainment', 'category', 'entertainment', 30, 2, 4, 6, 'declining', 'trend-opportunity-test-v1'),
    ('1900-01-07 00:00:00+00', '1900-01-14 00:00:00+00', 'youtube', 'BR', 'pt', 'gaming', 'category', 'gaming', 30, 8, NULL, 7, 'insufficient_data', 'trend-opportunity-test-v1'),
    ('1900-01-07 00:00:00+00', '1900-01-14 00:00:00+00', 'youtube', 'BR', 'pt', NULL, 'format', 'tutorial', 30, 8, 9, 8, 'rising', 'trend-opportunity-test-v1');

DO $$
DECLARE
    result_row RECORD;
    technology_row RECORD;
    education_row RECORD;
    entertainment_row RECORD;
    gaming_row RECORD;
    tutorial_row RECORD;
    score_count INTEGER;
BEGIN
    SELECT * INTO result_row
      FROM refresh_opportunity_rankings(TIMESTAMPTZ '1900-01-15 00:00:00+00');

    IF result_row.statistics_considered <> 5
       OR result_row.statistics_scored <> 4
       OR result_row.statistics_incomplete <> 1
       OR result_row.categories_ranked <> 3
       OR result_row.top_opportunity_score <> 8.35
       OR result_row.opportunity_calculation_version <> 'opportunity-test-v1'
       OR result_row.trend_calculation_version <> 'trend-opportunity-test-v1' THEN
        RAISE EXCEPTION 'Opportunity summary is incorrect: %', row_to_json(result_row);
    END IF;

    SELECT * INTO technology_row FROM category_statistics WHERE calculation_version = 'trend-opportunity-test-v1' AND dimension_type = 'category' AND dimension_value = 'technology';
    SELECT * INTO education_row FROM category_statistics WHERE calculation_version = 'trend-opportunity-test-v1' AND dimension_type = 'category' AND dimension_value = 'education';
    SELECT * INTO entertainment_row FROM category_statistics WHERE calculation_version = 'trend-opportunity-test-v1' AND dimension_type = 'category' AND dimension_value = 'entertainment';
    SELECT * INTO gaming_row FROM category_statistics WHERE calculation_version = 'trend-opportunity-test-v1' AND dimension_type = 'category' AND dimension_value = 'gaming';
    SELECT * INTO tutorial_row FROM category_statistics WHERE calculation_version = 'trend-opportunity-test-v1' AND dimension_type = 'format' AND dimension_value = 'tutorial';

    IF technology_row.opportunity_score <> 8.35 OR technology_row.opportunity_rank <> 1 OR technology_row.opportunity_percentile <> 1 THEN
        RAISE EXCEPTION 'Top category ranking is incorrect: %', row_to_json(technology_row);
    END IF;
    IF education_row.opportunity_score <> 6.65 OR education_row.opportunity_rank <> 2 OR education_row.opportunity_percentile <> 0.5 THEN
        RAISE EXCEPTION 'Middle category ranking is incorrect: %', row_to_json(education_row);
    END IF;
    IF entertainment_row.opportunity_score <> 3.3 OR entertainment_row.opportunity_rank <> 3 OR entertainment_row.opportunity_percentile <> 0 THEN
        RAISE EXCEPTION 'Low category ranking is incorrect: %', row_to_json(entertainment_row);
    END IF;
    IF gaming_row.opportunity_score IS NOT NULL OR gaming_row.opportunity_rank IS NOT NULL OR gaming_row.opportunity_component_count <> 2 THEN
        RAISE EXCEPTION 'Incomplete category should remain unranked: %', row_to_json(gaming_row);
    END IF;
    IF tutorial_row.opportunity_score <> 8.35 OR tutorial_row.opportunity_rank <> 1 OR tutorial_row.opportunity_percentile <> 1 THEN
        RAISE EXCEPTION 'Format ranking should be isolated from categories: %', row_to_json(tutorial_row);
    END IF;

    PERFORM * FROM refresh_opportunity_rankings(TIMESTAMPTZ '1900-01-15 00:00:00+00');

    SELECT count(*) INTO score_count
      FROM category_statistics
     WHERE calculation_version = 'trend-opportunity-test-v1'
       AND opportunity_score IS NOT NULL;

    IF score_count <> 4 THEN
        RAISE EXCEPTION 'Opportunity refresh is not idempotent; found % scores', score_count;
    END IF;

    BEGIN
        UPDATE category_statistics SET opportunity_rank = 0 WHERE id = technology_row.id;
        RAISE EXCEPTION 'Invalid opportunity rank was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE category_statistics SET opportunity_percentile = 1.1 WHERE id = technology_row.id;
        RAISE EXCEPTION 'Invalid opportunity percentile was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE category_statistics SET opportunity_calculation_version = '   ' WHERE id = technology_row.id;
        RAISE EXCEPTION 'Blank opportunity calculation version was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'Opportunity Engine SQL validation passed' AS result;
