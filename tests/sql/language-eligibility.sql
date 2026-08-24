\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    portuguese_video BIGINT;
    foreign_video BIGINT;
    uncertain_video BIGINT;
    result_row RECORD;
BEGIN
    IF to_regprocedure('select_language_detection_candidates(integer,integer,timestamptz)') IS NULL
       OR to_regprocedure('persist_language_detection(bigint,text,numeric,text,timestamptz)') IS NULL
       OR to_regprocedure('set_manual_language_eligibility(bigint,text,text,timestamptz)') IS NULL THEN
        RAISE EXCEPTION 'Language eligibility functions are missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM settings
         WHERE key = 'LANGUAGE_GATE_MIN_CONFIDENCE'
           AND (value #>> '{}')::NUMERIC BETWEEN 0 AND 1
    ) THEN
        RAISE EXCEPTION 'Language gate settings are missing or invalid';
    END IF;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, target_language, language_eligibility, short_confidence
    ) VALUES (
        'youtube', '__language_pt', '__language_channel', 'Tutorial rápido em português',
        'https://example.test/__language_pt', '2100-02-03 00:00:00+00',
        40, 'pt', 'uncertain', 'medium'
    ) RETURNING id INTO portuguese_video;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, target_language, language_eligibility, short_confidence
    ) VALUES (
        'youtube', '__language_en', '__language_channel', 'Quick tutorial in English',
        'https://example.test/__language_en', '2100-02-02 00:00:00+00',
        40, 'en', 'uncertain', 'medium'
    ) RETURNING id INTO foreign_video;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, target_language, language_eligibility, short_confidence
    ) VALUES (
        'youtube', '__language_uncertain', '__language_channel', 'Sem evidência suficiente',
        'https://example.test/__language_uncertain', '2100-02-01 00:00:00+00',
        40, 'pt', 'uncertain', 'medium'
    ) RETURNING id INTO uncertain_video;

    IF (SELECT count(*) FROM select_language_detection_candidates(10, 100, '2100-02-04') WHERE external_id IN ('__language_pt', '__language_en', '__language_uncertain')) <> 3 THEN
        RAISE EXCEPTION 'Language gate candidate selection is incorrect';
    END IF;

    SELECT * INTO result_row
      FROM persist_language_detection(portuguese_video, 'pt-BR', 0.95, 'llm_metadata', '2100-02-04');
    IF result_row.language_eligibility <> 'eligible'
       OR result_row.detected_language <> 'pt-br' THEN
        RAISE EXCEPTION 'Portuguese detection was not accepted: %', row_to_json(result_row);
    END IF;

    SELECT * INTO result_row
      FROM persist_language_detection(foreign_video, 'en-US', 0.99, 'llm_metadata', '2100-02-04');
    IF result_row.language_eligibility <> 'rejected'
       OR result_row.target_language <> 'pt' THEN
        RAISE EXCEPTION 'Foreign detection was not rejected against the global target: %', row_to_json(result_row);
    END IF;

    SELECT * INTO result_row
      FROM persist_language_detection(uncertain_video, 'pt', 0.50, 'llm_metadata', '2100-02-04');
    IF result_row.language_eligibility <> 'uncertain'
       OR result_row.language_retry_after IS NULL THEN
        RAISE EXCEPTION 'Low-confidence detection did not remain uncertain: %', row_to_json(result_row);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM select_classification_candidates(10, 100)
         WHERE video_id = portuguese_video
    ) OR EXISTS (
        SELECT 1 FROM select_classification_candidates(10, 100)
         WHERE video_id IN (foreign_video, uncertain_video)
    ) THEN
        RAISE EXCEPTION 'Classifier did not enforce language eligibility';
    END IF;

    PERFORM *
      FROM set_manual_language_eligibility(foreign_video, 'pt', 'eligible', '2100-02-05');

    IF NOT EXISTS (
        SELECT 1 FROM videos
         WHERE id = foreign_video
           AND language_eligibility = 'eligible'
           AND language_detection_source = 'manual'
           AND language_confidence = 1
    ) THEN
        RAISE EXCEPTION 'Manual language review was not persisted';
    END IF;

    BEGIN
        UPDATE videos SET language_eligibility = 'invalid' WHERE id = portuguese_video;
        RAISE EXCEPTION 'Invalid language eligibility was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END;
$$;

ROLLBACK;

SELECT 'Language eligibility SQL validation passed' AS result;
