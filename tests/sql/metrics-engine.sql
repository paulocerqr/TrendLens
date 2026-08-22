\set ON_ERROR_STOP on

BEGIN;

UPDATE settings SET value = '3'::jsonb WHERE key = 'MIN_SAMPLE_SIZE';
UPDATE settings SET value = '1'::jsonb WHERE key = 'METRICS_CHANNEL_BASELINE_MIN_VIDEOS';
UPDATE settings SET value = '7'::jsonb WHERE key = 'METRICS_ANALYSIS_WINDOW_DAYS';
UPDATE settings SET value = '30'::jsonb WHERE key = 'METRICS_CHANNEL_BASELINE_WINDOW_DAYS';
UPDATE settings SET value = '168'::jsonb WHERE key = 'METRICS_FRESHNESS_HORIZON_HOURS';
UPDATE settings SET value = '3'::jsonb WHERE key = 'METRICS_MIN_VIRALITY_COMPONENTS';
UPDATE settings SET value = '"metrics-test-v1"'::jsonb WHERE key = 'METRICS_CALCULATION_VERSION';

DO $$
DECLARE
    as_of TIMESTAMPTZ := TIMESTAMPTZ '2100-01-10 12:00:00+00';
    target_video BIGINT;
    target_previous_snapshot BIGINT;
    target_snapshot BIGINT;
    middle_video BIGINT;
    low_video BIGINT;
    zero_video BIGINT;
    missing_video BIGINT;
    fixture_video BIGINT;
    result_row RECORD;
    metric_row RECORD;
    metric_count INTEGER;
    low_virality NUMERIC;
BEGIN
    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__metrics_baseline_high', '__metrics_channel_high', 'High channel',
        'Older baseline', '', 'https://www.youtube.com/watch?v=__metrics_baseline_high',
        as_of - INTERVAL '10 days', 30, 'pt', 'BR', 'high'
    ) RETURNING id INTO fixture_video;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (fixture_video, as_of - INTERVAL '1 hour', 100, 5, 1);

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__metrics_target', '__metrics_channel_high', 'High channel',
        'Fast original tutorial', '', 'https://www.youtube.com/watch?v=__metrics_target',
        as_of - INTERVAL '4 hours', 45, 'pt', 'BR', 'high'
    ) RETURNING id INTO target_video;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (target_video, as_of - INTERVAL '3 hours', 100, 10, 1);
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (target_video, as_of - INTERVAL '2 hours', 200, 20, 2)
    RETURNING id INTO target_previous_snapshot;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (target_video, as_of - INTERVAL '1 hour', 500, 50, 10)
    RETURNING id INTO target_snapshot;

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__metrics_baseline_middle', '__metrics_channel_middle', 'Middle channel',
        'Older baseline', '', 'https://www.youtube.com/watch?v=__metrics_baseline_middle',
        as_of - INTERVAL '10 days', 30, 'pt', 'BR', 'high'
    ) RETURNING id INTO fixture_video;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (fixture_video, as_of - INTERVAL '1 hour', 100, 5, 1);

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__metrics_middle', '__metrics_channel_middle', 'Middle channel',
        'Steady explainer', '', 'https://www.youtube.com/watch?v=__metrics_middle',
        as_of - INTERVAL '4 hours', 45, 'pt', 'BR', 'high'
    ) RETURNING id INTO middle_video;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES
        (middle_video, as_of - INTERVAL '2 hours', 100, 5, 1),
        (middle_video, as_of - INTERVAL '1 hour', 200, 10, 2);

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__metrics_baseline_low', '__metrics_channel_low', 'Low channel',
        'Older baseline', '', 'https://www.youtube.com/watch?v=__metrics_baseline_low',
        as_of - INTERVAL '10 days', 30, 'pt', 'BR', 'high'
    ) RETURNING id INTO fixture_video;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (fixture_video, as_of - INTERVAL '1 hour', 100, 5, 1);

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__metrics_low', '__metrics_channel_low', 'Low channel',
        'Slow clip', '', 'https://www.youtube.com/watch?v=__metrics_low',
        as_of - INTERVAL '4 hours', 45, 'pt', 'BR', 'high'
    ) RETURNING id INTO low_video;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES
        (low_video, as_of - INTERVAL '2 hours', 40, 1, 0),
        (low_video, as_of - INTERVAL '1 hour', 50, 1, 0);

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__metrics_zero', '__metrics_channel_zero', 'Zero channel',
        'Zero views', '', 'https://www.youtube.com/watch?v=__metrics_zero',
        as_of - INTERVAL '4 hours', 45, 'pt', 'BR', 'high'
    ) RETURNING id INTO zero_video;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (zero_video, as_of - INTERVAL '1 hour', 0, 0, 0);

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__metrics_missing', '__metrics_channel_missing', 'Missing channel',
        'Missing engagement', '', 'https://www.youtube.com/watch?v=__metrics_missing',
        as_of - INTERVAL '4 hours', 45, 'pt', 'BR', 'high'
    ) RETURNING id INTO missing_video;
    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (missing_video, as_of - INTERVAL '1 hour', 100, NULL, NULL);

    SELECT * INTO result_row FROM refresh_video_metrics(100, as_of);

    IF result_row.eligible_videos <> 5
       OR result_row.candidates_selected <> 5
       OR result_row.metrics_upserted <> 5 THEN
        RAISE EXCEPTION 'Unexpected refresh counts: %', row_to_json(result_row);
    END IF;

    IF result_row.virality_scored <> 3
       OR result_row.velocity_available <> 3
       OR result_row.acceleration_available <> 1
       OR result_row.channel_baseline_available <> 3 THEN
        RAISE EXCEPTION 'Unexpected metric availability: %', row_to_json(result_row);
    END IF;

    SELECT * INTO metric_row
      FROM video_metrics
     WHERE snapshot_id = target_snapshot;

    IF metric_row.previous_snapshot_id <> target_previous_snapshot
       OR abs(metric_row.like_rate - 0.1) > 0.000001
       OR abs(metric_row.comment_rate - 0.02) > 0.000001
       OR abs(metric_row.engagement_rate - 0.16) > 0.000001
       OR abs(metric_row.view_velocity - 300) > 0.000001
       OR abs(metric_row.view_acceleration - 200) > 0.000001
       OR abs(metric_row.channel_median_views - 100) > 0.000001
       OR abs(metric_row.relative_performance - 5) > 0.000001
       OR abs(metric_row.outlier_score - 5) > 0.000001 THEN
        RAISE EXCEPTION 'Target raw metrics are incorrect: %', row_to_json(metric_row);
    END IF;

    IF metric_row.velocity_percentile <> 1
       OR metric_row.engagement_percentile <> 1
       OR metric_row.outlier_percentile <> 1
       OR metric_row.views_percentile <> 1
       OR metric_row.virality_score < 9.9
       OR metric_row.calculation_version <> 'metrics-test-v1' THEN
        RAISE EXCEPTION 'Target percentile or score is incorrect: %', row_to_json(metric_row);
    END IF;

    SELECT virality_score INTO low_virality
      FROM video_metrics
     WHERE video_id = low_video;

    IF low_virality IS NULL OR metric_row.virality_score <= low_virality THEN
        RAISE EXCEPTION 'High-performance fixture must outrank low-performance fixture';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM video_metrics
         WHERE video_id IN (zero_video, missing_video)
           AND (like_rate IS NOT NULL OR comment_rate IS NOT NULL OR engagement_rate IS NOT NULL OR virality_score IS NOT NULL)
    ) THEN
        RAISE EXCEPTION 'Zero views or missing engagement was converted into a fabricated rate or score';
    END IF;

    PERFORM * FROM refresh_video_metrics(100, as_of);
    SELECT count(*) INTO metric_count
      FROM video_metrics
     WHERE video_id IN (target_video, middle_video, low_video, zero_video, missing_video);

    IF metric_count <> 5 THEN
        RAISE EXCEPTION 'Metrics refresh is not idempotent; found % rows', metric_count;
    END IF;

    BEGIN
        UPDATE video_metrics
           SET calculation_version = '   '
         WHERE snapshot_id = target_snapshot;
        RAISE EXCEPTION 'Blank calculation version was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE video_metrics
           SET previous_snapshot_id = snapshot_id
         WHERE snapshot_id = target_snapshot;
        RAISE EXCEPTION 'A snapshot was accepted as its own predecessor';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'Metrics Engine SQL validation passed' AS result;
