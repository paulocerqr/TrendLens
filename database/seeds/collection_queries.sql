BEGIN;

WITH query_seed (category_slug, query_text, priority) AS (
    VALUES
        ('movie_tv_clips', 'filme', 10),
        ('movie_tv_clips', 'série', 20),
        ('podcast_clips', 'corte podcast', 30),
        ('curiosities', 'curiosidades', 40),
        ('technology', 'tecnologia', 50),
        ('games', 'games', 60),
        ('humor', 'humor', 70),
        ('quick_tutorials', 'tutorial rápido', 80),
        ('sports', 'futebol', 90),
        ('storytelling', 'storytelling', 100),
        ('motivation', 'motivação', 110)
),
sample_groups (sample_group) AS (
    VALUES
        ('recent'),
        ('high_performance')
)
INSERT INTO collection_queries (
    category_id,
    query_text,
    sample_group,
    language,
    region,
    is_active,
    priority
)
SELECT
    category.id,
    query_seed.query_text,
    sample_groups.sample_group,
    'pt',
    'BR',
    TRUE,
    query_seed.priority
FROM query_seed
JOIN categories AS category
  ON category.slug = query_seed.category_slug
CROSS JOIN sample_groups
ON CONFLICT (lower(query_text), sample_group, language, region) DO UPDATE
SET
    category_id = EXCLUDED.category_id,
    is_active = TRUE,
    priority = EXCLUDED.priority;

COMMIT;
