\set ON_ERROR_STOP on

BEGIN;

UPDATE settings SET value = '"7 days"'::JSONB WHERE key = 'VALIDATION_PERIOD';
UPDATE settings SET value = '"validation-test-v1"'::JSONB WHERE key = 'VALIDATION_VERSION';
UPDATE settings SET value = '3'::JSONB WHERE key = 'VALIDATION_MIN_OBSERVATION_DAYS';
UPDATE settings SET value = '30'::JSONB WHERE key = 'VALIDATION_MIN_CATEGORY_SAMPLE_SIZE';
UPDATE settings SET value = '30'::JSONB WHERE key = 'VALIDATION_MIN_CLASSIFIER_REVIEWS';
UPDATE settings SET value = '0.65'::JSONB WHERE key = 'VALIDATION_CLASSIFIER_CONFIDENCE_FLOOR';
UPDATE settings SET value = '0.10'::JSONB WHERE key = 'VALIDATION_SCORE_TAIL_THRESHOLD';
UPDATE settings SET value = '1.50'::JSONB WHERE key = 'VALIDATION_SNAPSHOT_CADENCE_TOLERANCE';
UPDATE settings SET value = '"metrics-validation-test-v1"'::JSONB WHERE key = 'METRICS_CALCULATION_VERSION';
UPDATE settings SET value = '"monetization-validation-test-v1"'::JSONB WHERE key = 'MONETIZATION_CALCULATION_VERSION';
UPDATE settings SET value = '"trend-validation-test-v1"'::JSONB WHERE key = 'TREND_CALCULATION_VERSION';
UPDATE settings SET value = '"opportunity-validation-test-v1"'::JSONB WHERE key = 'OPPORTUNITY_CALCULATION_VERSION';

INSERT INTO collection_queries (
    id, category_id, query_text, sample_group, language, region, priority
)
VALUES
    (95001, (SELECT id FROM categories WHERE slug = 'movie_tv_clips'), 'validation recent', 'recent', 'pt', 'BR', 1),
    (95002, (SELECT id FROM categories WHERE slug = 'movie_tv_clips'), 'validation high performance', 'high_performance', 'pt', 'BR', 1);

WITH required_categories AS (
    SELECT * FROM (VALUES
        (0, 'movie_tv_clips'),
        (1, 'curiosities'),
        (2, 'quick_tutorials'),
        (3, 'podcast_clips'),
        (4, 'technology'),
        (5, 'storytelling')
    ) AS required(offset_value, slug)
)
INSERT INTO videos (
    id, platform, external_id, channel_id, title, description, url,
    published_at, duration_seconds, language, target_language, detected_language,
    language_confidence, language_detection_source, language_eligibility,
    region, short_confidence
)
SELECT
    92000 + fixture.number,
    'youtube',
    'validation-video-' || fixture.number,
    'validation-channel-' || (fixture.number % 20),
    'Validation video ' || fixture.number,
    'Description for manual classifier review ' || fixture.number,
    'https://example.test/validation-video-' || fixture.number,
    TIMESTAMPTZ '1900-05-01 13:00:00+00' + make_interval(mins => fixture.number),
    45,
    'pt',
    'pt',
    'pt',
    1,
    'manual',
    'eligible',
    'BR',
    'high'
FROM generate_series(1, 180) fixture(number);

WITH required_categories AS (
    SELECT * FROM (VALUES
        (0, 'movie_tv_clips'),
        (1, 'curiosities'),
        (2, 'quick_tutorials'),
        (3, 'podcast_clips'),
        (4, 'technology'),
        (5, 'storytelling')
    ) AS required(offset_value, slug)
)
INSERT INTO video_classifications (
    video_id, category_id, topic, content_type, format, hook_type,
    source_type, presentation_style, originality_score, copyright_risk,
    reused_content_risk, ai_confidence, classification_model,
    prompt_version, classified_at
)
SELECT
    92000 + fixture.number,
    category.id,
    required.slug,
    'education',
    CASE WHEN required.slug = 'movie_tv_clips' THEN 'clip' ELSE 'explainer' END,
    'question',
    CASE WHEN required.slug = 'movie_tv_clips' THEN 'movie_or_tv_clip' ELSE 'original' END,
    'voiceover',
    CASE WHEN required.slug = 'movie_tv_clips' THEN 0.3 ELSE 0.8 END,
    CASE WHEN required.slug = 'movie_tv_clips' THEN 0.8 ELSE 0.2 END,
    CASE WHEN required.slug = 'movie_tv_clips' THEN 0.8 ELSE 0.2 END,
    CASE fixture.number % 3 WHEN 0 THEN 0.60 WHEN 1 THEN 0.75 ELSE 0.90 END,
    'validation-test-model',
    'validation-test-prompt-v1',
    TIMESTAMPTZ '1900-05-02 00:00:00+00'
FROM generate_series(1, 180) fixture(number)
JOIN required_categories required ON required.offset_value = (fixture.number - 1) % 6
JOIN categories category ON category.slug = required.slug;

INSERT INTO pipeline_runs (
    id, workflow, started_at, finished_at, status,
    items_received, items_processed, items_failed, duration_seconds
)
VALUES (
    96001, '01 - TrendLens - YouTube Data Collector',
    '1900-05-01 12:00:00+00', '1900-05-01 12:00:10+00', 'success',
    180, 180, 0, 10
);

INSERT INTO video_collection_matches (
    pipeline_run_id, collection_query_id, video_id, search_rank, matched_at
)
SELECT
    96001,
    CASE WHEN fixture.number <= 90 THEN 95001 ELSE 95002 END,
    92000 + fixture.number,
    ((fixture.number - 1) % 50) + 1,
    TIMESTAMPTZ '1900-05-01 12:00:05+00'
FROM generate_series(1, 180) fixture(number);

INSERT INTO video_snapshots (id, video_id, collected_at, views, likes, comments)
SELECT
    93000 + fixture.number,
    92000 + fixture.number,
    TIMESTAMPTZ '1900-05-02 00:00:00+00' + make_interval(days => fixture.number % 5),
    1000 + fixture.number * 10,
    100 + fixture.number,
    10 + fixture.number
FROM generate_series(1, 180) fixture(number)
UNION ALL
SELECT
    94000 + fixture.number,
    92000 + fixture.number,
    TIMESTAMPTZ '1900-05-02 00:30:00+00' + make_interval(days => fixture.number % 5),
    CASE WHEN fixture.number = 1 THEN 900 ELSE 1100 + fixture.number * 10 END,
    110 + fixture.number,
    11 + fixture.number
FROM generate_series(1, 180) fixture(number);

INSERT INTO video_metrics (
    video_id, snapshot_id, previous_snapshot_id, engagement_rate,
    view_velocity, velocity_percentile, engagement_percentile,
    outlier_percentile, views_percentile, freshness_score,
    virality_score, calculation_version, calculated_at
)
SELECT
    92000 + fixture.number,
    94000 + fixture.number,
    93000 + fixture.number,
    0.01 + (fixture.number % 20)::NUMERIC / 1000,
    10 + fixture.number,
    (fixture.number % 100)::NUMERIC / 100,
    ((fixture.number + 13) % 100)::NUMERIC / 100,
    ((fixture.number + 29) % 100)::NUMERIC / 100,
    ((fixture.number + 47) % 100)::NUMERIC / 100,
    0.50,
    2 + (fixture.number % 61)::NUMERIC / 10,
    'metrics-validation-test-v1',
    TIMESTAMPTZ '1900-05-07 00:00:00+00'
FROM generate_series(1, 180) fixture(number);

INSERT INTO video_monetization_scores (
    video_id, originality, policy_eligibility, advertiser_suitability,
    production_feasibility, engagement_quality, copyright_risk,
    reused_content_risk, positive_base, combined_risk,
    monetization_score, calculation_version, calculated_at
)
SELECT
    92000 + fixture.number,
    0.8, 0.8, 0.8, 0.8, 0.7, 0.2, 0.2, 0.78, 0.2,
    2 + ((fixture.number + 17) % 61)::NUMERIC / 10,
    'monetization-validation-test-v1',
    TIMESTAMPTZ '1900-05-07 00:10:00+00'
FROM generate_series(1, 180) fixture(number);

WITH required_categories AS (
    SELECT * FROM (VALUES
        (1, 'movie_tv_clips'),
        (2, 'curiosities'),
        (3, 'quick_tutorials'),
        (4, 'podcast_clips'),
        (5, 'technology'),
        (6, 'storytelling')
    ) AS required(rank_value, slug)
)
INSERT INTO category_statistics (
    period_start, period_end, platform, region, language,
    category_slug, dimension_type, dimension_value, sample_size,
    median_views, p75_views, p90_views, median_engagement,
    median_velocity, median_virality, median_monetization,
    outlier_count, outlier_rate, high_performance_rate,
    p75_performance_rate, p90_performance_rate, dispersion_score,
    consistency_score, opportunity_score, opportunity_rank,
    opportunity_percentile, opportunity_component_count,
    opportunity_calculation_version, opportunity_calculated_at,
    previous_sample_size, trend_change, trend_direction,
    calculation_version, created_at
)
SELECT
    '1900-05-01 12:00:00+00', '1900-05-08 12:00:00+00',
    'youtube', 'BR', 'pt', required.slug, 'category', required.slug, 30,
    10000 * required.rank_value, 15000 * required.rank_value, 20000 * required.rank_value,
    0.04 + required.rank_value::NUMERIC / 1000,
    100 * required.rank_value,
    8 - required.rank_value::NUMERIC / 2,
    3 + required.rank_value::NUMERIC / 2,
    3, 0.10, 0.20, 0.25, 0.10, 0.70,
    6.0, 6.5 - required.rank_value::NUMERIC / 10,
    required.rank_value, 1 - (required.rank_value - 1)::NUMERIC / 6,
    3, 'opportunity-validation-test-v1', '1900-05-08 11:30:00+00',
    30, 0.01, 'stable', 'trend-validation-test-v1', '1900-05-08 11:00:00+00'
FROM required_categories required;

DO $$
DECLARE
    candidate_count INTEGER;
    distinct_candidate_count INTEGER;
    initial_report RECORD;
BEGIN
    SELECT count(*), count(DISTINCT video_id)
      INTO candidate_count, distinct_candidate_count
      FROM select_classification_review_candidates(18, 'validation-test-seed');

    IF candidate_count <> 18 OR distinct_candidate_count <> 18 THEN
        RAISE EXCEPTION 'Review candidate selection is not limited and unique: %, %', candidate_count, distinct_candidate_count;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM select_classification_review_candidates(18, 'validation-test-seed')
         WHERE confidence_bucket = 'low'
    ) OR NOT EXISTS (
        SELECT 1 FROM select_classification_review_candidates(18, 'validation-test-seed')
         WHERE confidence_bucket = 'medium'
    ) OR NOT EXISTS (
        SELECT 1 FROM select_classification_review_candidates(18, 'validation-test-seed')
         WHERE confidence_bucket = 'high'
    ) THEN
        RAISE EXCEPTION 'Review candidates are not stratified by confidence';
    END IF;

    SELECT * INTO initial_report
      FROM build_phase12_validation('1900-05-08 12:34:00+00');

    IF initial_report.overall_status <> 'insufficient_data'
       OR initial_report.reviewed_classifications <> 0
       OR initial_report.report_json #>> '{weight_review,decision}' <> 'hold_v1_collect_more_data' THEN
        RAISE EXCEPTION 'Initial validation readiness is incorrect: %', row_to_json(initial_report);
    END IF;
END;
$$;

INSERT INTO classification_validation_reviews (
    video_id, prompt_version, reviewer,
    category_correct, topic_correct, content_type_correct,
    format_correct, hook_type_correct, source_type_correct,
    presentation_style_correct, originality_reasonable,
    copyright_risk_reasonable, reused_content_risk_reasonable,
    corrected_values, notes, reviewed_at
)
SELECT
    92000 + fixture.number,
    'validation-test-prompt-v1',
    'phase12-test-reviewer',
    true, true, true,
    fixture.number <> 1,
    true, true,
    true, true,
    true, true,
    CASE WHEN fixture.number = 1 THEN '{"format":"commentary"}'::JSONB ELSE '{}'::JSONB END,
    CASE WHEN fixture.number = 1 THEN 'Formato corrigido durante a revisão.' ELSE NULL END,
    TIMESTAMPTZ '1900-05-08 10:00:00+00'
FROM generate_series(1, 30) fixture(number);

DO $$
DECLARE
    validation RECORD;
    persisted_count INTEGER;
BEGIN
    SELECT * INTO validation
      FROM build_phase12_validation('1900-05-08 12:34:00+00');

    IF validation.period_start <> TIMESTAMPTZ '1900-05-01 12:00:00+00'
       OR validation.period_end <> TIMESTAMPTZ '1900-05-08 12:00:00+00'
       OR validation.validation_version <> 'validation-test-v1'
       OR validation.overall_status <> 'needs_attention'
       OR validation.sample_size <> 180
       OR validation.reviewed_classifications <> 30
       OR validation.source_hash !~ '^[a-f0-9]{32}$' THEN
        RAISE EXCEPTION 'Validation summary is incorrect: %', row_to_json(validation);
    END IF;

    IF validation.report_json #>> '{snapshot_quality,views_decreased}' <> '1'
       OR validation.report_json #>> '{classifier_review,field_acceptance_rate}' <> '0.9967'
       OR validation.report_json #>> '{category_comparison,sufficient_categories}' <> '6'
       OR jsonb_array_length(validation.report_json #> '{category_comparison,items}') <> 6
       OR validation.report_json #>> '{category_comparison,items,0,category}' <> 'movie_tv_clips'
       OR validation.report_json #>> '{category_comparison,items,0,sample_size}' <> '30'
       OR validation.report_json #>> '{weight_review,decision}' <> 'hold_v1_resolve_distortions'
       OR validation.report_json #>> '{weight_review,automatic_adjustment_applied}' <> 'false' THEN
        RAISE EXCEPTION 'Validation JSON is incorrect: %', validation.report_json;
    END IF;

    INSERT INTO pipeline_validation_reports (
        period_start, period_end, generated_at, validation_version,
        overall_status, sample_size, reviewed_classifications,
        report_json, source_hash
    ) VALUES (
        validation.period_start, validation.period_end, validation.generated_at,
        validation.validation_version, validation.overall_status,
        validation.sample_size, validation.reviewed_classifications,
        validation.report_json, validation.source_hash
    );

    INSERT INTO pipeline_validation_reports (
        period_start, period_end, generated_at, validation_version,
        overall_status, sample_size, reviewed_classifications,
        report_json, source_hash
    ) VALUES (
        validation.period_start, validation.period_end, validation.generated_at,
        validation.validation_version, validation.overall_status,
        validation.sample_size, validation.reviewed_classifications,
        validation.report_json, validation.source_hash
    ) ON CONFLICT (period_start, period_end, validation_version, source_hash) DO NOTHING;

    SELECT count(*) INTO persisted_count
      FROM pipeline_validation_reports
     WHERE source_hash = validation.source_hash;

    IF persisted_count <> 1 THEN
        RAISE EXCEPTION 'Validation persistence is not idempotent; found % rows', persisted_count;
    END IF;

    BEGIN
        UPDATE pipeline_validation_reports
           SET report_json = '{}'::JSONB
         WHERE source_hash = validation.source_hash;
        RAISE EXCEPTION 'Incomplete validation JSON was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END;
$$;

UPDATE video_snapshots
   SET views = 1110
 WHERE id = 94001;

DO $$
DECLARE
    validation RECORD;
BEGIN
    SELECT * INTO validation
      FROM build_phase12_validation('1900-05-08 12:34:00+00');

    IF validation.overall_status <> 'ready_for_weight_review'
       OR validation.report_json #>> '{weight_review,decision}' <> 'eligible_for_manual_calibration' THEN
        RAISE EXCEPTION 'Validation did not become ready after resolving distortion: %', row_to_json(validation);
    END IF;

    IF EXISTS (
        SELECT 1
          FROM select_classification_review_candidates(180, 'validation-test-seed')
         WHERE video_id BETWEEN 92001 AND 92030
    ) THEN
        RAISE EXCEPTION 'Reviewed videos were returned to the manual review queue';
    END IF;
END;
$$;

ROLLBACK;

SELECT 'Phase 12 validation SQL passed' AS result;
