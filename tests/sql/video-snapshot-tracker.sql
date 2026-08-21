\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    reference_time CONSTANT TIMESTAMPTZ := TIMESTAMPTZ '2100-01-15 12:00:00+00';
    recent_age_hours INTEGER;
    intermediate_age_hours INTEGER;
    active_days INTEGER;
    recent_interval_minutes INTEGER;
    intermediate_interval_minutes INTEGER;
    older_interval_minutes INTEGER;
    recent_due_id BIGINT;
    recent_wait_id BIGINT;
    intermediate_due_id BIGINT;
    older_due_id BIGINT;
    expired_id BIGINT;
    selected_count INTEGER;
    snapshot_count INTEGER;
BEGIN
    SELECT
        (values ->> 'SNAPSHOT_RECENT_MAX_AGE_HOURS')::integer,
        (values ->> 'SNAPSHOT_INTERMEDIATE_MAX_AGE_HOURS')::integer,
        (values ->> 'SNAPSHOT_ACTIVE_DAYS')::integer,
        (values ->> 'SNAPSHOT_RECENT_INTERVAL_MINUTES')::integer,
        (values ->> 'SNAPSHOT_INTERMEDIATE_INTERVAL_MINUTES')::integer,
        (values ->> 'SNAPSHOT_OLDER_INTERVAL_MINUTES')::integer
      INTO
        recent_age_hours,
        intermediate_age_hours,
        active_days,
        recent_interval_minutes,
        intermediate_interval_minutes,
        older_interval_minutes
      FROM (
          SELECT jsonb_object_agg(key, value) AS values
            FROM settings
           WHERE key = ANY (ARRAY[
              'SNAPSHOT_RECENT_MAX_AGE_HOURS',
              'SNAPSHOT_INTERMEDIATE_MAX_AGE_HOURS',
              'SNAPSHOT_ACTIVE_DAYS',
              'SNAPSHOT_RECENT_INTERVAL_MINUTES',
              'SNAPSHOT_INTERMEDIATE_INTERVAL_MINUTES',
              'SNAPSHOT_OLDER_INTERVAL_MINUTES'
           ])
      ) configured;

    IF recent_age_hours IS NULL
       OR intermediate_age_hours IS NULL
       OR active_days IS NULL
       OR recent_interval_minutes IS NULL
       OR intermediate_interval_minutes IS NULL
       OR older_interval_minutes IS NULL THEN
        RAISE EXCEPTION 'Snapshot Tracker settings are incomplete';
    END IF;

    IF recent_age_hours <= 0
       OR intermediate_age_hours <= recent_age_hours
       OR active_days * 24 <= intermediate_age_hours
       OR recent_interval_minutes <= 0
       OR intermediate_interval_minutes < recent_interval_minutes
       OR older_interval_minutes < intermediate_interval_minutes THEN
        RAISE EXCEPTION 'Snapshot Tracker age or interval settings are inconsistent';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM settings
         WHERE key = 'SNAPSHOT_MAX_VIDEOS_PER_RUN'
           AND (value #>> '{}')::integer BETWEEN 1 AND 10000
    ) THEN
        RAISE EXCEPTION 'SNAPSHOT_MAX_VIDEOS_PER_RUN is missing or invalid';
    END IF;

    IF to_regprocedure('select_snapshot_candidates(timestamp with time zone,integer)') IS NULL THEN
        RAISE EXCEPTION 'select_snapshot_candidates function is missing';
    END IF;

    INSERT INTO videos (
        platform,
        external_id,
        channel_id,
        title,
        url,
        published_at,
        duration_seconds,
        language,
        region,
        short_confidence
    )
    VALUES (
        'youtube',
        '__snapshot_tracker_recent_due',
        '__snapshot_tracker_channel',
        'Snapshot tracker recent due fixture',
        'https://www.youtube.com/watch?v=__snapshot_tracker_recent_due',
        reference_time - make_interval(hours => greatest(recent_age_hours / 2, 1)),
        30,
        'pt',
        'BR',
        'medium'
    )
    RETURNING id INTO recent_due_id;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, language, region, short_confidence
    )
    VALUES (
        'youtube',
        '__snapshot_tracker_recent_wait',
        '__snapshot_tracker_channel',
        'Snapshot tracker recent wait fixture',
        'https://www.youtube.com/watch?v=__snapshot_tracker_recent_wait',
        reference_time - make_interval(hours => greatest(recent_age_hours / 2, 1)),
        30,
        'pt',
        'BR',
        'medium'
    )
    RETURNING id INTO recent_wait_id;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, language, region, short_confidence
    )
    VALUES (
        'youtube',
        '__snapshot_tracker_intermediate_due',
        '__snapshot_tracker_channel',
        'Snapshot tracker intermediate due fixture',
        'https://www.youtube.com/watch?v=__snapshot_tracker_intermediate_due',
        reference_time - make_interval(hours => recent_age_hours + 1),
        30,
        'pt',
        'BR',
        'medium'
    )
    RETURNING id INTO intermediate_due_id;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, language, region, short_confidence
    )
    VALUES (
        'youtube',
        '__snapshot_tracker_older_due',
        '__snapshot_tracker_channel',
        'Snapshot tracker older due fixture',
        'https://www.youtube.com/watch?v=__snapshot_tracker_older_due',
        reference_time - make_interval(hours => intermediate_age_hours + 1),
        30,
        'pt',
        'BR',
        'medium'
    )
    RETURNING id INTO older_due_id;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, language, region, short_confidence
    )
    VALUES (
        'youtube',
        '__snapshot_tracker_expired',
        '__snapshot_tracker_channel',
        'Snapshot tracker expired fixture',
        'https://www.youtube.com/watch?v=__snapshot_tracker_expired',
        reference_time - make_interval(days => active_days + 1),
        30,
        'pt',
        'BR',
        'medium'
    )
    RETURNING id INTO expired_id;

    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES
        (recent_due_id, reference_time - make_interval(mins => recent_interval_minutes + 1), 100, 10, 2),
        (recent_wait_id, reference_time - make_interval(mins => greatest(recent_interval_minutes - 1, 0)), 100, NULL, NULL),
        (intermediate_due_id, reference_time - make_interval(mins => intermediate_interval_minutes + 1), 200, 20, 4),
        (older_due_id, reference_time - make_interval(mins => older_interval_minutes + 1), 300, 30, 6),
        (expired_id, reference_time - make_interval(days => active_days + 1), 400, 40, 8);

    SELECT count(*)
      INTO selected_count
      FROM select_snapshot_candidates(reference_time, NULL) selected
     WHERE selected.video_id = ANY (ARRAY[
        recent_due_id,
        recent_wait_id,
        intermediate_due_id,
        older_due_id,
        expired_id
     ]);

    IF selected_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 due fixtures, found %', selected_count;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM select_snapshot_candidates(reference_time, NULL)
         WHERE video_id = recent_due_id
           AND age_bucket = 'recent'
           AND due_interval_minutes = recent_interval_minutes
    ) THEN
        RAISE EXCEPTION 'Recent policy was not applied correctly';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM select_snapshot_candidates(reference_time, NULL)
         WHERE video_id = intermediate_due_id
           AND age_bucket = 'intermediate'
           AND due_interval_minutes = intermediate_interval_minutes
    ) THEN
        RAISE EXCEPTION 'Intermediate policy was not applied correctly';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM select_snapshot_candidates(reference_time, NULL)
         WHERE video_id = older_due_id
           AND age_bucket = 'older'
           AND due_interval_minutes = older_interval_minutes
    ) THEN
        RAISE EXCEPTION 'Older policy was not applied correctly';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM select_snapshot_candidates(reference_time, NULL)
         WHERE video_id IN (recent_wait_id, expired_id)
    ) THEN
        RAISE EXCEPTION 'A not-due or expired video was selected';
    END IF;

    INSERT INTO video_snapshots (video_id, collected_at, views, likes, comments)
    VALUES (recent_due_id, reference_time, 150, NULL, NULL);

    SELECT count(*)
      INTO snapshot_count
      FROM video_snapshots
     WHERE video_id = recent_due_id;

    IF snapshot_count <> 2 THEN
        RAISE EXCEPTION 'Historical snapshots were not preserved';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM select_snapshot_candidates(reference_time, NULL)
         WHERE video_id = recent_due_id
    ) THEN
        RAISE EXCEPTION 'A video with a snapshot at the reference time remained due';
    END IF;
END;
$$;

ROLLBACK;

SELECT 'video snapshot tracker SQL validation passed' AS result;
