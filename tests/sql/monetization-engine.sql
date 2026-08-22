\set ON_ERROR_STOP on

BEGIN;

UPDATE settings
   SET value = '"monetization-test-v1"'::JSONB
 WHERE key = 'MONETIZATION_CALCULATION_VERSION';

DO $$
DECLARE
    as_of TIMESTAMPTZ := TIMESTAMPTZ '1900-01-10 12:00:00+00';
    original_video BIGINT;
    risky_video BIGINT;
    missing_engagement_video BIGINT;
    original_snapshot BIGINT;
    risky_snapshot BIGINT;
    result_row RECORD;
    original_score RECORD;
    risky_score RECORD;
    missing_score RECORD;
    score_count INTEGER;
BEGIN
    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__monetization_original', '__monetization_channel_original', 'Original channel',
        'Original tutorial', '', 'https://www.youtube.com/watch?v=__monetization_original',
        as_of - INTERVAL '1 hour', 45, 'pt', 'BR', 'high'
    ) RETURNING id INTO original_video;

    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (original_video, as_of - INTERVAL '10 minutes', 1000, 100, 10)
    RETURNING id INTO original_snapshot;

    INSERT INTO video_metrics (
        video_id, snapshot_id, engagement_percentile, calculation_version, calculated_at
    ) VALUES (
        original_video, original_snapshot, 0.9, 'metrics-test-v1', as_of - INTERVAL '5 minutes'
    );

    INSERT INTO video_classifications (
        video_id, topic, content_type, format, hook_type, source_type,
        presentation_style, originality_score, copyright_risk,
        reused_content_risk, ai_confidence, classification_model,
        prompt_version, classified_at
    ) VALUES (
        original_video, 'technology', 'educational', 'tutorial', 'question', 'original',
        'voice_over', 0.9, 0.05, 0.1, 1, 'fixture-model', 'fixture-v1', as_of - INTERVAL '30 minutes'
    );

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__monetization_risky', '__monetization_channel_risky', 'Risky channel',
        'Movie clip', '', 'https://www.youtube.com/watch?v=__monetization_risky',
        as_of - INTERVAL '1 hour', 45, 'pt', 'BR', 'high'
    ) RETURNING id INTO risky_video;

    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (risky_video, as_of - INTERVAL '10 minutes', 1000, 100, 10)
    RETURNING id INTO risky_snapshot;

    INSERT INTO video_metrics (
        video_id, snapshot_id, engagement_percentile, calculation_version, calculated_at
    ) VALUES (
        risky_video, risky_snapshot, 0.9, 'metrics-test-v1', as_of - INTERVAL '5 minutes'
    );

    INSERT INTO video_classifications (
        video_id, topic, content_type, format, hook_type, source_type,
        presentation_style, originality_score, copyright_risk,
        reused_content_risk, ai_confidence, classification_model,
        prompt_version, classified_at
    ) VALUES (
        risky_video, 'cinema', 'movie_clip', 'clip', 'direct_statement', 'movie_or_tv_clip',
        'clip_with_subtitles', 0.2, 0.95, 0.95, 1, 'fixture-model', 'fixture-v1', as_of - INTERVAL '30 minutes'
    );

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    ) VALUES (
        'youtube', '__monetization_missing_engagement', '__monetization_channel_missing', 'Missing channel',
        'Original tutorial without metrics', '', 'https://www.youtube.com/watch?v=__monetization_missing_engagement',
        as_of - INTERVAL '1 hour', 45, 'pt', 'BR', 'high'
    ) RETURNING id INTO missing_engagement_video;

    INSERT INTO video_classifications (
        video_id, topic, content_type, format, hook_type, source_type,
        presentation_style, originality_score, copyright_risk,
        reused_content_risk, ai_confidence, classification_model,
        prompt_version, classified_at
    ) VALUES (
        missing_engagement_video, 'technology', 'educational', 'tutorial', 'question', 'original',
        'voice_over', 0.9, 0.05, 0.1, 1, 'fixture-model', 'fixture-v1', as_of - INTERVAL '30 minutes'
    );

    SELECT * INTO result_row
      FROM refresh_video_monetization_scores(100, as_of);

    IF result_row.eligible_classifications <> 3
       OR result_row.candidates_selected <> 3
       OR result_row.scores_upserted <> 3
       OR result_row.engagement_quality_available <> 2
       OR result_row.high_risk_scores <> 1
       OR result_row.calculation_version <> 'monetization-test-v1' THEN
        RAISE EXCEPTION 'Unexpected monetization refresh result: %', row_to_json(result_row);
    END IF;

    SELECT * INTO original_score
      FROM video_monetization_scores
     WHERE video_id = original_video
       AND calculation_version = 'monetization-test-v1';

    IF original_score.originality <> 0.9
       OR original_score.policy_eligibility <> 1
       OR original_score.advertiser_suitability <> 0.95
       OR original_score.production_feasibility <> 0.72
       OR original_score.engagement_quality <> 0.9
       OR original_score.positive_base <> 0.9055
       OR original_score.combined_risk <> 0.07
       OR original_score.monetization_score <> 8.4212 THEN
        RAISE EXCEPTION 'Original-content score is incorrect: %', row_to_json(original_score);
    END IF;

    SELECT * INTO risky_score
      FROM video_monetization_scores
     WHERE video_id = risky_video
       AND calculation_version = 'monetization-test-v1';

    IF risky_score.policy_eligibility <> 0.15
       OR risky_score.advertiser_suitability <> 0.55
       OR risky_score.production_feasibility <> 0.965
       OR risky_score.positive_base <> 0.4598
       OR risky_score.combined_risk <> 0.95
       OR risky_score.monetization_score <> 0.2299
       OR risky_score.monetization_score >= original_score.monetization_score THEN
        RAISE EXCEPTION 'Risky-content score is incorrect: %', row_to_json(risky_score);
    END IF;

    SELECT * INTO missing_score
      FROM video_monetization_scores
     WHERE video_id = missing_engagement_video
       AND calculation_version = 'monetization-test-v1';

    IF missing_score.engagement_quality IS NOT NULL
       OR missing_score.positive_base <> 0.9065
       OR missing_score.combined_risk <> 0.07
       OR missing_score.monetization_score <> 8.4305 THEN
        RAISE EXCEPTION 'Missing engagement was not redistributed correctly: %', row_to_json(missing_score);
    END IF;

    PERFORM * FROM refresh_video_monetization_scores(100, as_of);

    SELECT count(*) INTO score_count
      FROM video_monetization_scores
     WHERE video_id IN (original_video, risky_video, missing_engagement_video)
       AND calculation_version = 'monetization-test-v1';

    IF score_count <> 3 THEN
        RAISE EXCEPTION 'Monetization refresh is not idempotent; found % rows', score_count;
    END IF;

    BEGIN
        UPDATE video_monetization_scores
           SET calculation_version = '   '
         WHERE video_id = original_video;
        RAISE EXCEPTION 'Blank monetization calculation version was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE video_monetization_scores
           SET combined_risk = 1.1
         WHERE video_id = original_video;
        RAISE EXCEPTION 'Combined risk outside 0..1 was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'Monetization Engine SQL validation passed' AS result;
