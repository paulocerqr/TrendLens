\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    required_tables TEXT[] := ARRAY[
        'categories',
        'settings',
        'collection_queries',
        'videos',
        'video_snapshots',
        'video_classifications',
        'video_metrics',
        'video_monetization_scores',
        'category_statistics',
        'recommendations',
        'pipeline_runs',
        'pipeline_errors'
    ];
    existing_count INTEGER;
BEGIN
    SELECT count(*)
      INTO existing_count
      FROM pg_catalog.pg_tables
     WHERE schemaname = 'public'
       AND tablename = ANY(required_tables);

    IF existing_count <> cardinality(required_tables) THEN
        RAISE EXCEPTION
            'Expected % foundation tables, found %',
            cardinality(required_tables),
            existing_count;
    END IF;
END;
$$;

DO $$
DECLARE
    category_count INTEGER;
    setting_count INTEGER;
BEGIN
    SELECT count(*) INTO category_count FROM categories WHERE active;
    SELECT count(*) INTO setting_count FROM settings;

    IF category_count < 10 THEN
        RAISE EXCEPTION 'Expected at least 10 active categories, found %', category_count;
    END IF;

    IF setting_count < 10 THEN
        RAISE EXCEPTION 'Expected at least 10 settings, found %', setting_count;
    END IF;
END;
$$;

INSERT INTO videos (
    platform,
    external_id,
    channel_id,
    channel_name,
    title,
    description,
    url,
    published_at,
    duration_seconds,
    language,
    region,
    short_confidence
)
VALUES (
    'youtube',
    'trendlens_foundation_smoke_test',
    'test_channel',
    'Test Channel',
    'Foundation smoke test',
    'Temporary row rolled back at the end of the test.',
    'https://www.youtube.com/watch?v=trendlens_foundation_smoke_test',
    '2026-08-21T12:00:00Z',
    42,
    'pt',
    'BR',
    'high'
);

INSERT INTO video_snapshots (
    video_id,
    collected_at,
    views,
    likes,
    comments
)
SELECT
    id,
    '2026-08-21T12:05:00Z',
    0,
    NULL,
    NULL
FROM videos
WHERE platform = 'youtube'
  AND external_id = 'trendlens_foundation_smoke_test';

DO $$
DECLARE
    snapshot_count INTEGER;
    snapshot_likes BIGINT;
    snapshot_comments BIGINT;
BEGIN
    SELECT count(*), max(likes), max(comments)
      INTO snapshot_count, snapshot_likes, snapshot_comments
      FROM video_snapshots AS snapshot
      JOIN videos AS video ON video.id = snapshot.video_id
     WHERE video.platform = 'youtube'
       AND video.external_id = 'trendlens_foundation_smoke_test'
       AND snapshot.views = 0;

    IF snapshot_count <> 1 THEN
        RAISE EXCEPTION 'Expected one zero-view snapshot, found %', snapshot_count;
    END IF;

    IF snapshot_likes IS NOT NULL OR snapshot_comments IS NOT NULL THEN
        RAISE EXCEPTION 'Missing likes and comments must remain NULL';
    END IF;
END;
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO videos (
            platform,
            external_id,
            channel_id,
            title,
            url,
            published_at,
            short_confidence
        )
        VALUES (
            'youtube',
            'trendlens_foundation_smoke_test',
            'another_channel',
            'Duplicate test',
            'https://www.youtube.com/watch?v=duplicate',
            '2026-08-21T12:00:00Z',
            'medium'
        );

        RAISE EXCEPTION 'Duplicate platform and external_id was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            NULL;
    END;
END;
$$;

DO $$
DECLARE
    test_video_id BIGINT;
BEGIN
    SELECT id
      INTO test_video_id
      FROM videos
     WHERE platform = 'youtube'
       AND external_id = 'trendlens_foundation_smoke_test';

    BEGIN
        INSERT INTO video_snapshots (
            video_id,
            collected_at,
            views
        )
        VALUES (
            test_video_id,
            '2026-08-21T12:10:00Z',
            -1
        );

        RAISE EXCEPTION 'Negative views were accepted';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;
END;
$$;

INSERT INTO pipeline_runs (
    workflow,
    started_at,
    finished_at,
    status,
    items_received,
    items_processed,
    duration_seconds,
    metadata
)
VALUES (
    'foundation-smoke-test',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'success',
    1,
    1,
    0,
    '{"temporary": true}'::JSONB
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pipeline_runs
         WHERE workflow = 'foundation-smoke-test'
           AND status = 'success'
    ) THEN
        RAISE EXCEPTION 'Pipeline run insert and query test failed';
    END IF;
END;
$$;

ROLLBACK;

SELECT 'TrendLens foundation smoke test passed' AS result;
