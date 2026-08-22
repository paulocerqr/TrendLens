\set ON_ERROR_STOP on

BEGIN;

UPDATE settings SET value = '168'::JSONB WHERE key = 'TREND_PERIOD_HOURS';
UPDATE settings SET value = '60'::JSONB WHERE key = 'TREND_BUCKET_MINUTES';
UPDATE settings SET value = '2'::JSONB WHERE key = 'TREND_MIN_SAMPLE_SIZE';
UPDATE settings SET value = '"trend-test-v1"'::JSONB WHERE key = 'TREND_CALCULATION_VERSION';
UPDATE settings SET value = '"metrics-test-v1"'::JSONB WHERE key = 'METRICS_CALCULATION_VERSION';
UPDATE settings SET value = '"monetization-test-v1"'::JSONB WHERE key = 'MONETIZATION_CALCULATION_VERSION';

DO $$
DECLARE
    as_of TIMESTAMPTZ := TIMESTAMPTZ '1900-01-15 12:30:00+00';
    technology_category BIGINT;
    fixture RECORD;
    fixture_video BIGINT;
    fixture_snapshot BIGINT;
    result_row RECORD;
    tutorial_row RECORD;
    statistic_count INTEGER;
BEGIN
    SELECT id INTO technology_category
      FROM categories
     WHERE slug = 'technology';

    FOR fixture IN
        SELECT *
          FROM (VALUES
              ('__trend_current_tutorial_1', TIMESTAMPTZ '1900-01-10 12:00:00+00', 'educational', 'tutorial', 'question', 'original', 900::BIGINT, 0.12::NUMERIC, 900::NUMERIC, 0.95::NUMERIC, 0.90::NUMERIC, 0.90::NUMERIC, 9.0::NUMERIC, 8.0::NUMERIC),
              ('__trend_current_tutorial_2', TIMESTAMPTZ '1900-01-11 12:00:00+00', 'educational', 'tutorial', 'question', 'original', 800::BIGINT, 0.10::NUMERIC, 800::NUMERIC, 0.85::NUMERIC, 0.80::NUMERIC, 0.85::NUMERIC, 8.0::NUMERIC, 7.0::NUMERIC),
              ('__trend_current_clip_1', TIMESTAMPTZ '1900-01-12 12:00:00+00', 'entertainment', 'clip', 'direct_statement', 'movie_or_tv_clip', 400::BIGINT, 0.05::NUMERIC, 300::NUMERIC, 0.70::NUMERIC, 0.50::NUMERIC, 0.55::NUMERIC, 4.0::NUMERIC, 2.0::NUMERIC),
              ('__trend_current_clip_2', TIMESTAMPTZ '1900-01-13 12:00:00+00', 'entertainment', 'clip', 'direct_statement', 'movie_or_tv_clip', 300::BIGINT, 0.04::NUMERIC, 200::NUMERIC, 0.60::NUMERIC, 0.40::NUMERIC, 0.45::NUMERIC, 3.0::NUMERIC, 1.5::NUMERIC),
              ('__trend_previous_tutorial_1', TIMESTAMPTZ '1900-01-03 12:00:00+00', 'educational', 'tutorial', 'question', 'original', 500::BIGINT, 0.08::NUMERIC, 400::NUMERIC, 0.75::NUMERIC, 0.70::NUMERIC, 0.70::NUMERIC, 5.0::NUMERIC, 7.0::NUMERIC),
              ('__trend_previous_tutorial_2', TIMESTAMPTZ '1900-01-04 12:00:00+00', 'educational', 'tutorial', 'question', 'original', 450::BIGINT, 0.07::NUMERIC, 350::NUMERIC, 0.70::NUMERIC, 0.65::NUMERIC, 0.65::NUMERIC, 5.0::NUMERIC, 6.5::NUMERIC),
              ('__trend_previous_clip_1', TIMESTAMPTZ '1900-01-05 12:00:00+00', 'entertainment', 'clip', 'direct_statement', 'movie_or_tv_clip', 600::BIGINT, 0.07::NUMERIC, 500::NUMERIC, 0.80::NUMERIC, 0.75::NUMERIC, 0.75::NUMERIC, 6.0::NUMERIC, 2.0::NUMERIC),
              ('__trend_previous_clip_2', TIMESTAMPTZ '1900-01-06 12:00:00+00', 'entertainment', 'clip', 'direct_statement', 'movie_or_tv_clip', 550::BIGINT, 0.06::NUMERIC, 450::NUMERIC, 0.78::NUMERIC, 0.72::NUMERIC, 0.72::NUMERIC, 6.0::NUMERIC, 1.8::NUMERIC)
          ) AS data (
              external_id, published_at, content_type, format, hook_type, source_type,
              views, engagement_rate, velocity, outlier_percentile, views_percentile,
              engagement_percentile, virality_score, monetization_score
          )
    LOOP
        INSERT INTO videos (
            platform, external_id, channel_id, channel_name, title, description, url,
            published_at, duration_seconds, language, region, short_confidence
        ) VALUES (
            'youtube', fixture.external_id, fixture.external_id || '_channel', 'Fixture channel',
            fixture.external_id, '', 'https://www.youtube.com/watch?v=' || fixture.external_id,
            fixture.published_at, 45, 'pt', 'BR', 'high'
        ) RETURNING id INTO fixture_video;

        INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
        VALUES (fixture_video, fixture.published_at + INTERVAL '1 hour', fixture.views, 50, 5)
        RETURNING id INTO fixture_snapshot;

        INSERT INTO video_classifications (
            video_id, category_id, topic, content_type, format, hook_type, source_type,
            presentation_style, originality_score, copyright_risk, reused_content_risk,
            ai_confidence, classification_model, prompt_version, classified_at
        ) VALUES (
            fixture_video, technology_category, 'technology', fixture.content_type,
            fixture.format, fixture.hook_type, fixture.source_type, 'voice_over',
            0.8, 0.2, 0.2, 1, 'fixture-model', 'fixture-v1', fixture.published_at
        );

        INSERT INTO video_metrics (
            video_id, snapshot_id, engagement_rate, view_velocity, outlier_percentile,
            views_percentile, engagement_percentile, virality_score,
            calculation_version, calculated_at
        ) VALUES (
            fixture_video, fixture_snapshot, fixture.engagement_rate, fixture.velocity,
            fixture.outlier_percentile, fixture.views_percentile,
            fixture.engagement_percentile, fixture.virality_score,
            'metrics-test-v1', fixture.published_at + INTERVAL '2 hours'
        );

        INSERT INTO video_monetization_scores (
            video_id, originality, policy_eligibility, advertiser_suitability,
            production_feasibility, engagement_quality, copyright_risk,
            reused_content_risk, positive_base, combined_risk, monetization_score,
            calculation_version, calculated_at
        ) VALUES (
            fixture_video, 0.8, 0.8, 0.8, 0.8, fixture.engagement_percentile,
            0.2, 0.2, 0.8, 0.2, fixture.monetization_score,
            'monetization-test-v1', fixture.published_at + INTERVAL '2 hours'
        );
    END LOOP;

    SELECT * INTO result_row FROM refresh_category_statistics(as_of);

    IF result_row.videos_in_current_period <> 4
       OR result_row.dimension_rows <> 12
       OR result_row.statistics_upserted <> 12
       OR result_row.sufficient_sample_statistics <> 12
       OR result_row.rising_statistics <> 5
       OR result_row.stable_statistics <> 2
       OR result_row.declining_statistics <> 5
       OR result_row.insufficient_statistics <> 0
       OR result_row.calculation_version <> 'trend-test-v1'
       OR result_row.period_end <> TIMESTAMPTZ '1900-01-15 13:00:00+00' THEN
        RAISE EXCEPTION 'Unexpected Trend Engine result: %', row_to_json(result_row);
    END IF;

    SELECT * INTO tutorial_row
      FROM category_statistics
     WHERE dimension_type = 'format'
       AND dimension_value = 'tutorial'
       AND calculation_version = 'trend-test-v1';

    IF tutorial_row.sample_size <> 2
       OR tutorial_row.previous_sample_size <> 2
       OR tutorial_row.median_views <> 850
       OR tutorial_row.p75_views <> 875
       OR tutorial_row.p90_views <> 890
       OR tutorial_row.median_engagement <> 0.11
       OR tutorial_row.median_velocity <> 850
       OR tutorial_row.median_virality <> 8.5
       OR tutorial_row.median_monetization <> 7.5
       OR tutorial_row.outlier_count <> 1
       OR tutorial_row.outlier_rate <> 0.5
       OR tutorial_row.high_performance_rate <> 1
       OR tutorial_row.p75_performance_rate <> 1
       OR tutorial_row.p90_performance_rate <> 0.5
       OR tutorial_row.dispersion_score <> 0.9529
       OR tutorial_row.consistency_score <> 8.7029
       OR tutorial_row.trend_change <> 0.35
       OR tutorial_row.trend_direction <> 'rising' THEN
        RAISE EXCEPTION 'Tutorial aggregate is incorrect: %', row_to_json(tutorial_row);
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM category_statistics
         WHERE dimension_type = 'format'
           AND dimension_value = 'clip'
           AND trend_direction = 'declining'
           AND trend_change = -0.25
    ) THEN
        RAISE EXCEPTION 'Declining clip trend was not detected';
    END IF;

    PERFORM * FROM refresh_category_statistics(as_of);

    SELECT count(*) INTO statistic_count
      FROM category_statistics
     WHERE calculation_version = 'trend-test-v1';

    IF statistic_count <> 12 THEN
        RAISE EXCEPTION 'Trend refresh is not idempotent; found % rows', statistic_count;
    END IF;

    BEGIN
        UPDATE category_statistics
           SET dimension_value = 'invalid value'
         WHERE dimension_type = 'format' AND dimension_value = 'tutorial';
        RAISE EXCEPTION 'Invalid dimension value was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE category_statistics
           SET calculation_version = '   '
         WHERE dimension_type = 'format' AND dimension_value = 'tutorial';
        RAISE EXCEPTION 'Blank trend calculation version was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'Trend Engine SQL validation passed' AS result;
