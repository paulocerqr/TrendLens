\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    unclassified_video_id BIGINT;
    classified_video_id BIGINT;
    selected_count INTEGER;
    truncated_description TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM settings
         WHERE key = 'LLM_MODEL'
           AND jsonb_typeof(value) = 'string'
           AND length(value #>> '{}') > 0
    ) THEN
        RAISE EXCEPTION 'LLM_MODEL is missing or invalid';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM settings
         WHERE key = 'CLASSIFIER_MAX_VIDEOS_PER_RUN'
           AND (value #>> '{}')::integer = 30
    ) THEN
        RAISE EXCEPTION 'CLASSIFIER_MAX_VIDEOS_PER_RUN does not match the operational capacity of 30';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM settings
         WHERE key = 'CLASSIFIER_DESCRIPTION_MAX_CHARS'
           AND (value #>> '{}')::integer BETWEEN 0 AND 10000
    ) THEN
        RAISE EXCEPTION 'CLASSIFIER_DESCRIPTION_MAX_CHARS is missing or invalid';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM settings
         WHERE key = 'CLASSIFIER_PROMPT_VERSION'
           AND jsonb_typeof(value) = 'string'
           AND length(value #>> '{}') > 0
    ) THEN
        RAISE EXCEPTION 'CLASSIFIER_PROMPT_VERSION is missing or invalid';
    END IF;

    IF to_regprocedure('select_classification_candidates(integer,integer)') IS NULL THEN
        RAISE EXCEPTION 'select_classification_candidates function is missing';
    END IF;

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    )
    VALUES (
        'youtube', '__classifier_unclassified', '__classifier_channel', 'Classifier fixture',
        'Tutorial rápido com narração original', repeat('x', 50),
        'https://www.youtube.com/watch?v=__classifier_unclassified',
        TIMESTAMPTZ '2100-01-02 12:00:00+00', 45, 'pt', 'BR', 'medium'
    )
    RETURNING id INTO unclassified_video_id;

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, region, short_confidence
    )
    VALUES (
        'youtube', '__classifier_classified', '__classifier_channel', 'Classifier fixture',
        'Corte de filme com legendas', 'Trecho de uma produção audiovisual.',
        'https://www.youtube.com/watch?v=__classifier_classified',
        TIMESTAMPTZ '2100-01-01 12:00:00+00', 30, 'pt', 'BR', 'high'
    )
    RETURNING id INTO classified_video_id;

    INSERT INTO video_classifications (
        video_id, topic, content_type, format, hook_type, source_type,
        presentation_style, originality_score, copyright_risk,
        reused_content_risk, ai_confidence, classification_model, prompt_version
    )
    VALUES (
        classified_video_id, 'cinema', 'movie_clip', 'clip', 'direct_statement',
        'movie_or_tv_clip', 'clip_with_subtitles', 0.2000, 0.9000, 0.9000,
        0.8500, 'fixture-model', 'fixture-v1'
    );

    SELECT count(*), max(description)
      INTO selected_count, truncated_description
      FROM select_classification_candidates(1000, 10)
     WHERE video_id IN (unclassified_video_id, classified_video_id);

    IF selected_count <> 1 THEN
        RAISE EXCEPTION 'Expected only the unclassified fixture, found % candidates', selected_count;
    END IF;

    IF length(truncated_description) <> 10 THEN
        RAISE EXCEPTION 'Description truncation was not applied';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM select_classification_candidates(1000, 10)
         WHERE video_id = unclassified_video_id
           AND category_hints = '[]'::jsonb
    ) THEN
        RAISE EXCEPTION 'Unclassified fixture or empty category hints were not returned';
    END IF;

    BEGIN
        INSERT INTO video_classifications (
            video_id, topic, content_type, format, hook_type, source_type,
            presentation_style, originality_score, copyright_risk,
            reused_content_risk, ai_confidence, classification_model, prompt_version
        )
        VALUES (
            unclassified_video_id, 'invalid topic', 'educational', 'tutorial', 'promise',
            'original', 'voice_over', 1.1000, 0.0000, 0.0000, 0.9000,
            'fixture-model', 'fixture-v1'
        );

        RAISE EXCEPTION 'Invalid structured classification was accepted';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;

    BEGIN
        INSERT INTO video_classifications (
            video_id, topic, content_type, format, hook_type, source_type,
            presentation_style, originality_score, copyright_risk,
            reused_content_risk, ai_confidence, classification_model, prompt_version
        )
        VALUES (
            unclassified_video_id, 'tutorial', 'educational', 'tutorial', 'promise',
            'original', 'voice_over', 0.9000, 0.1000, 0.1000, 0.9000,
            '   ', 'fixture-v1'
        );

        RAISE EXCEPTION 'Blank classification model was accepted';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;

    BEGIN
        INSERT INTO video_classifications (
            video_id, topic, content_type, format, hook_type, source_type,
            presentation_style, originality_score, copyright_risk,
            reused_content_risk, ai_confidence, classification_model, prompt_version
        )
        VALUES (
            unclassified_video_id, 'tutorial', 'educational', 'tutorial', 'promise',
            'original', 'voice_over', 0.9000, 0.1000, 0.1000, 0.9000,
            'fixture-model', '   '
        );

        RAISE EXCEPTION 'Blank prompt version was accepted';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'AI content classifier SQL validation passed' AS result;
