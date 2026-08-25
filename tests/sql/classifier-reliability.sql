\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    retry_video_id BIGINT;
    exclude_video_id BIGINT;
    first_failure RECORD;
    second_failure RECORD;
    third_failure RECORD;
    review_result RECORD;
    completion_updated BOOLEAN;
BEGIN
    IF to_regclass('video_classification_processing_state') IS NULL THEN
        RAISE EXCEPTION 'video_classification_processing_state table is missing';
    END IF;

    IF to_regprocedure('record_classification_failure(bigint,text,timestamptz)') IS NULL
       OR to_regprocedure('mark_classification_completed(bigint,timestamptz)') IS NULL
       OR to_regprocedure('select_classification_failure_review_candidates(integer)') IS NULL
       OR to_regprocedure('resolve_classification_failure_review(bigint,text,text,text,timestamptz)') IS NULL THEN
        RAISE EXCEPTION 'One or more classifier reliability functions are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM settings
         WHERE key = 'CLASSIFIER_MAX_ATTEMPTS' AND (value #>> '{}')::INTEGER = 3
    ) OR NOT EXISTS (
        SELECT 1 FROM settings
         WHERE key = 'CLASSIFIER_RETRY_BACKOFF_BASE_HOURS' AND (value #>> '{}')::INTEGER = 6
    ) OR NOT EXISTS (
        SELECT 1 FROM settings
         WHERE key = 'CLASSIFIER_RETRY_BACKOFF_MAX_HOURS' AND (value #>> '{}')::INTEGER = 48
    ) THEN
        RAISE EXCEPTION 'Classifier reliability settings are missing or invalid';
    END IF;

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, target_language, detected_language,
        language_confidence, language_detection_source, language_eligibility,
        region, short_confidence
    )
    VALUES (
        'youtube', '__classifier_retry_state', '__classifier_reliability_channel',
        'Classifier reliability fixture', 'Retry fixture', 'Reliability retry fixture',
        'https://www.youtube.com/watch?v=__classifier_retry_state',
        TIMESTAMPTZ '2100-02-01 12:00:00+00', 45, 'pt', 'pt', 'pt',
        1, 'manual', 'eligible', 'BR', 'medium'
    )
    RETURNING id INTO retry_video_id;

    IF NOT EXISTS (
        SELECT 1 FROM select_classification_candidates(1000, 100)
         WHERE video_id = retry_video_id
    ) THEN
        RAISE EXCEPTION 'Untracked video was not selected for classification';
    END IF;

    SELECT * INTO first_failure
      FROM record_classification_failure(
          retry_video_id,
          'ai_classification_error',
          TIMESTAMPTZ '2100-02-01 13:00:00+00'
      );

    IF first_failure.status <> 'retry_wait'
       OR first_failure.attempt_count <> 1
       OR first_failure.total_attempt_count <> 1
       OR first_failure.retry_after <> TIMESTAMPTZ '2100-02-01 19:00:00+00'
       OR first_failure.requires_manual_review THEN
        RAISE EXCEPTION 'First failure did not apply the six-hour backoff: %', row_to_json(first_failure);
    END IF;

    IF EXISTS (
        SELECT 1 FROM select_classification_candidates(1000, 100)
         WHERE video_id = retry_video_id
    ) THEN
        RAISE EXCEPTION 'Video in retry_wait was selected before retry_after';
    END IF;

    UPDATE video_classification_processing_state
       SET retry_after = CURRENT_TIMESTAMP - INTERVAL '1 minute'
     WHERE video_id = retry_video_id;

    IF NOT EXISTS (
        SELECT 1 FROM select_classification_candidates(1000, 100)
         WHERE video_id = retry_video_id
    ) THEN
        RAISE EXCEPTION 'Video was not selected after its backoff expired';
    END IF;

    SELECT * INTO second_failure
      FROM record_classification_failure(
          retry_video_id,
          'ai_classification_error',
          TIMESTAMPTZ '2100-02-02 00:00:00+00'
      );

    IF second_failure.status <> 'retry_wait'
       OR second_failure.attempt_count <> 2
       OR second_failure.total_attempt_count <> 2
       OR second_failure.retry_after <> TIMESTAMPTZ '2100-02-02 12:00:00+00'
       OR second_failure.requires_manual_review THEN
        RAISE EXCEPTION 'Second failure did not apply the twelve-hour backoff: %', row_to_json(second_failure);
    END IF;

    SELECT * INTO third_failure
      FROM record_classification_failure(
          retry_video_id,
          'ai_classification_error',
          TIMESTAMPTZ '2100-02-03 00:00:00+00'
      );

    IF third_failure.status <> 'manual_review'
       OR third_failure.attempt_count <> 3
       OR third_failure.total_attempt_count <> 3
       OR third_failure.retry_after IS NOT NULL
       OR NOT third_failure.requires_manual_review THEN
        RAISE EXCEPTION 'Third failure was not sent to manual review: %', row_to_json(third_failure);
    END IF;

    IF EXISTS (
        SELECT 1 FROM select_classification_candidates(1000, 100)
         WHERE video_id = retry_video_id
    ) OR NOT EXISTS (
        SELECT 1 FROM select_classification_failure_review_candidates(100)
         WHERE video_id = retry_video_id
    ) THEN
        RAISE EXCEPTION 'Manual review queue did not isolate the terminal failure';
    END IF;

    SELECT * INTO review_result
      FROM resolve_classification_failure_review(
          retry_video_id,
          'retry',
          'sql-test',
          'Retry autorizado pela fixture.',
          TIMESTAMPTZ '2100-02-04 00:00:00+00'
      );

    IF review_result.status <> 'pending'
       OR review_result.attempt_count <> 0
       OR review_result.total_attempt_count <> 3
       OR review_result.reviewed_by <> 'sql-test'
       OR review_result.retry_after IS NOT NULL THEN
        RAISE EXCEPTION 'Manual retry did not reset only the current attempt cycle: %', row_to_json(review_result);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM select_classification_candidates(1000, 100)
         WHERE video_id = retry_video_id
    ) THEN
        RAISE EXCEPTION 'Manually released video did not return to the candidate queue';
    END IF;

    PERFORM record_classification_failure(retry_video_id, 'ai_classification_error', TIMESTAMPTZ '2100-02-05 00:00:00+00');

    INSERT INTO video_classifications (
        video_id, topic, content_type, format, hook_type, source_type,
        presentation_style, originality_score, copyright_risk,
        reused_content_risk, ai_confidence, classification_model, prompt_version
    )
    VALUES (
        retry_video_id, 'technology', 'educational', 'tutorial', 'promise',
        'original', 'voice_over', 0.9, 0.1, 0.1, 0.9,
        'fixture-model', 'fixture-v1'
    );

    SELECT mark_classification_completed(
        retry_video_id,
        TIMESTAMPTZ '2100-02-05 01:00:00+00'
    ) INTO completion_updated;

    IF NOT completion_updated OR NOT EXISTS (
           SELECT 1 FROM video_classification_processing_state
            WHERE video_id = retry_video_id
              AND status = 'completed'
              AND retry_after IS NULL
              AND last_succeeded_at = TIMESTAMPTZ '2100-02-05 01:00:00+00'
       ) THEN
        RAISE EXCEPTION 'Successful classification did not close the failure state';
    END IF;

    INSERT INTO videos (
        platform, external_id, channel_id, channel_name, title, description, url,
        published_at, duration_seconds, language, target_language, detected_language,
        language_confidence, language_detection_source, language_eligibility,
        region, short_confidence
    )
    VALUES (
        'youtube', '__classifier_excluded_state', '__classifier_reliability_channel',
        'Classifier exclusion fixture', 'Exclusion fixture', 'Reliability exclusion fixture',
        'https://www.youtube.com/watch?v=__classifier_excluded_state',
        TIMESTAMPTZ '2100-02-01 11:00:00+00', 45, 'pt', 'pt', 'pt',
        1, 'manual', 'eligible', 'BR', 'medium'
    )
    RETURNING id INTO exclude_video_id;

    PERFORM record_classification_failure(exclude_video_id, 'ai_classification_error', TIMESTAMPTZ '2100-02-01 12:00:00+00');
    PERFORM record_classification_failure(exclude_video_id, 'ai_classification_error', TIMESTAMPTZ '2100-02-02 12:00:00+00');
    PERFORM record_classification_failure(exclude_video_id, 'ai_classification_error', TIMESTAMPTZ '2100-02-03 12:00:00+00');

    SELECT * INTO review_result
      FROM resolve_classification_failure_review(
          exclude_video_id,
          'exclude',
          'sql-test',
          'Metadados insuficientes para classificação automática.',
          TIMESTAMPTZ '2100-02-04 12:00:00+00'
      );

    IF review_result.status <> 'excluded'
       OR EXISTS (
           SELECT 1 FROM select_classification_candidates(1000, 100)
            WHERE video_id = exclude_video_id
       )
       OR EXISTS (
           SELECT 1 FROM select_classification_failure_review_candidates(100)
            WHERE video_id = exclude_video_id
       ) THEN
        RAISE EXCEPTION 'Manual exclusion did not remove the video from automatic and review queues';
    END IF;

    BEGIN
        PERFORM resolve_classification_failure_review(
            exclude_video_id,
            'invalid',
            'sql-test',
            NULL,
            CURRENT_TIMESTAMP
        );
        RAISE EXCEPTION 'Invalid manual review action was accepted';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM = 'Invalid manual review action was accepted' THEN
                RAISE;
            END IF;
    END;
END;
$$;

ROLLBACK;

SELECT 'Classifier reliability SQL validation passed' AS result;
