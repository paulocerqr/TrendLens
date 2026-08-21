\set ON_ERROR_STOP on

DO $$
DECLARE
    configured_query_count INTEGER;
    recent_query_count INTEGER;
    high_performance_query_count INTEGER;
    represented_category_count INTEGER;
    required_setting_count INTEGER;
    provenance_table_exists BOOLEAN;
BEGIN
    SELECT count(*)
      INTO configured_query_count
      FROM collection_queries
     WHERE query_text IN (
        'filme',
        'série',
        'corte podcast',
        'curiosidades',
        'tecnologia',
        'games',
        'humor',
        'tutorial rápido',
        'futebol',
        'storytelling',
        'motivação'
     )
       AND language = 'pt'
       AND region = 'BR';

    SELECT count(*)
      INTO recent_query_count
      FROM collection_queries
     WHERE sample_group = 'recent'
       AND is_active;

    SELECT count(*)
      INTO high_performance_query_count
      FROM collection_queries
     WHERE sample_group = 'high_performance'
       AND is_active;

    SELECT count(DISTINCT category_id)
      INTO represented_category_count
      FROM collection_queries
     WHERE is_active;

    SELECT count(*)
      INTO required_setting_count
      FROM settings
     WHERE key IN (
        'REGION',
        'LANGUAGE',
        'COLLECTION_WINDOW_HOURS',
        'MAX_RESULTS_PER_QUERY',
        'MAX_QUERIES_PER_RUN',
        'SHORT_MAX_DURATION',
        'YOUTUBE_QUOTA_BUDGET_PER_RUN',
        'YOUTUBE_SEARCH_DAILY_CALL_LIMIT',
        'YOUTUBE_SEARCH_QUOTA_COST',
        'YOUTUBE_VIDEOS_LIST_QUOTA_COST'
     );

    SELECT to_regclass('public.video_collection_matches') IS NOT NULL
      INTO provenance_table_exists;

    IF configured_query_count <> 22 THEN
        RAISE EXCEPTION 'Expected 22 seeded query-group combinations, found %', configured_query_count;
    END IF;

    IF recent_query_count < 11 THEN
        RAISE EXCEPTION 'Expected at least 11 active recent queries, found %', recent_query_count;
    END IF;

    IF high_performance_query_count < 11 THEN
        RAISE EXCEPTION 'Expected at least 11 active high-performance queries, found %', high_performance_query_count;
    END IF;

    IF represented_category_count < 10 THEN
        RAISE EXCEPTION 'Expected all 10 categories to be represented, found %', represented_category_count;
    END IF;

    IF required_setting_count <> 10 THEN
        RAISE EXCEPTION 'Expected 10 collector settings, found %', required_setting_count;
    END IF;

    IF NOT provenance_table_exists THEN
        RAISE EXCEPTION 'Expected video_collection_matches table to exist';
    END IF;
END;
$$;

SELECT
    query.query_text,
    query.sample_group,
    category.slug AS category,
    query.priority
FROM collection_queries AS query
JOIN categories AS category
  ON category.id = query.category_id
WHERE query.is_active
ORDER BY query.priority, query.sample_group;
