BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('TREND_PERIOD_HOURS', '168'::JSONB, 'Tamanho, em horas, das janelas atual e anterior comparadas pelo Trend Engine.'),
    ('TREND_BUCKET_MINUTES', '60'::JSONB, 'Tamanho do bucket temporal usado para tornar recálculos do Trend Engine idempotentes.'),
    ('TREND_MIN_SAMPLE_SIZE', '30'::JSONB, 'Amostra mínima por dimensão em cada janela para classificar a direção da tendência.'),
    ('TREND_CALCULATION_VERSION', '"v1"'::JSONB, 'Versão das agregações, da consistência e da direção calculadas pelo Trend Engine.'),
    ('TREND_OUTLIER_PERCENTILE_THRESHOLD', '0.90'::JSONB, 'Percentil mínimo de outlier usado para contabilizar outliers por grupo.'),
    ('TREND_HIGH_VIRALITY_THRESHOLD', '7.0'::JSONB, 'Virality Score mínimo usado para a taxa de alto desempenho.'),
    ('TREND_DIRECTION_CHANGE_THRESHOLD', '0.10'::JSONB, 'Variação mínima da mediana de Virality Score normalizada em 0 a 1 para rising ou declining.'),
    ('CONSISTENCY_SAMPLE_WEIGHT', '0.20'::JSONB, 'Peso da adequação do tamanho da amostra no Consistency Score.'),
    ('CONSISTENCY_P75_WEIGHT', '0.30'::JSONB, 'Peso da taxa de vídeos acima do percentil 75 no Consistency Score.'),
    ('CONSISTENCY_P90_WEIGHT', '0.20'::JSONB, 'Peso da taxa de vídeos acima do percentil 90 no Consistency Score.'),
    ('CONSISTENCY_ENGAGEMENT_WEIGHT', '0.20'::JSONB, 'Peso da mediana do percentil de engajamento no Consistency Score.'),
    ('CONSISTENCY_DISPERSION_WEIGHT', '0.10'::JSONB, 'Peso da estabilidade entre mediana e P90 de views no Consistency Score.')
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

ALTER TABLE category_statistics
    ADD COLUMN IF NOT EXISTS category_slug TEXT,
    ADD COLUMN IF NOT EXISTS dimension_type TEXT,
    ADD COLUMN IF NOT EXISTS dimension_value TEXT,
    ADD COLUMN IF NOT EXISTS p75_performance_rate NUMERIC(5, 4),
    ADD COLUMN IF NOT EXISTS p90_performance_rate NUMERIC(5, 4),
    ADD COLUMN IF NOT EXISTS dispersion_score NUMERIC(5, 4),
    ADD COLUMN IF NOT EXISTS previous_sample_size INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS trend_change NUMERIC(8, 6),
    ADD COLUMN IF NOT EXISTS calculation_version TEXT NOT NULL DEFAULT 'v1';

UPDATE category_statistics
   SET dimension_type = CASE
           WHEN topic IS NOT NULL THEN 'topic'
           WHEN content_type IS NOT NULL THEN 'content_type'
           WHEN format IS NOT NULL THEN 'format'
           WHEN hook_type IS NOT NULL THEN 'hook_type'
           WHEN source_type IS NOT NULL THEN 'source_type'
           ELSE 'topic'
       END,
       dimension_value = COALESCE(topic, content_type, format, hook_type, source_type, 'unknown')
 WHERE dimension_type IS NULL OR dimension_value IS NULL;

ALTER TABLE category_statistics
    ALTER COLUMN dimension_type SET NOT NULL,
    ALTER COLUMN dimension_value SET NOT NULL;

DROP INDEX IF EXISTS category_statistics_dimensions_period_idx;

CREATE UNIQUE INDEX category_statistics_dimensions_period_idx
    ON category_statistics (
        period_start,
        period_end,
        platform,
        region,
        language,
        dimension_type,
        dimension_value,
        calculation_version
    )
    NULLS NOT DISTINCT;

CREATE INDEX IF NOT EXISTS category_statistics_dimension_rank_idx
    ON category_statistics (
        dimension_type,
        period_end DESC,
        median_virality DESC,
        consistency_score DESC
    );

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_previous_sample_size_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_previous_sample_size_check CHECK (previous_sample_size >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_dimension_type_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_dimension_type_check CHECK (dimension_type IN ('category', 'topic', 'content_type', 'format', 'hook_type', 'source_type', 'category_format_source'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_dimension_value_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_dimension_value_check CHECK (dimension_value ~ '^[a-z0-9_|]+$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_p75_performance_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_p75_performance_check CHECK (p75_performance_rate IS NULL OR p75_performance_rate BETWEEN 0 AND 1);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_p90_performance_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_p90_performance_check CHECK (p90_performance_rate IS NULL OR p90_performance_rate BETWEEN 0 AND 1);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_dispersion_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_dispersion_check CHECK (dispersion_score IS NULL OR dispersion_score BETWEEN 0 AND 1);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_trend_change_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_trend_change_check CHECK (trend_change IS NULL OR trend_change BETWEEN -1 AND 1);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_version_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_version_check CHECK (length(btrim(calculation_version)) > 0);
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION refresh_category_statistics(
    p_as_of TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    videos_in_current_period BIGINT,
    dimension_rows BIGINT,
    statistics_upserted BIGINT,
    sufficient_sample_statistics BIGINT,
    rising_statistics BIGINT,
    stable_statistics BIGINT,
    declining_statistics BIGINT,
    insufficient_statistics BIGINT,
    calculation_version TEXT,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ
)
LANGUAGE sql
VOLATILE
AS $$
WITH config AS (
    SELECT
        GREATEST(COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'TREND_PERIOD_HOURS'), 168), 1) AS period_hours,
        GREATEST(COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'TREND_BUCKET_MINUTES'), 60), 1) AS bucket_minutes,
        GREATEST(COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'TREND_MIN_SAMPLE_SIZE'), 30), 1) AS min_sample_size,
        COALESCE((SELECT value #>> '{}' FROM settings WHERE key = 'TREND_CALCULATION_VERSION'), 'v1') AS calculation_version,
        GREATEST(0::NUMERIC, LEAST(1::NUMERIC, COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'TREND_OUTLIER_PERCENTILE_THRESHOLD'), 0.90))) AS outlier_threshold,
        GREATEST(0::NUMERIC, LEAST(10::NUMERIC, COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'TREND_HIGH_VIRALITY_THRESHOLD'), 7.0))) AS high_virality_threshold,
        GREATEST(0::NUMERIC, LEAST(1::NUMERIC, COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'TREND_DIRECTION_CHANGE_THRESHOLD'), 0.10))) AS direction_threshold,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'CONSISTENCY_SAMPLE_WEIGHT'), 0.20), 0) AS sample_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'CONSISTENCY_P75_WEIGHT'), 0.30), 0) AS p75_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'CONSISTENCY_P90_WEIGHT'), 0.20), 0) AS p90_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'CONSISTENCY_ENGAGEMENT_WEIGHT'), 0.20), 0) AS engagement_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'CONSISTENCY_DISPERSION_WEIGHT'), 0.10), 0) AS dispersion_weight,
        COALESCE((SELECT value #>> '{}' FROM settings WHERE key = 'METRICS_CALCULATION_VERSION'), 'v1') AS metrics_version,
        COALESCE((SELECT value #>> '{}' FROM settings WHERE key = 'MONETIZATION_CALCULATION_VERSION'), 'v1') AS monetization_version
), bucketed AS (
    SELECT
        config.*,
        date_bin(
            make_interval(mins => config.bucket_minutes),
            p_as_of,
            TIMESTAMPTZ '2000-01-01 00:00:00+00'
        ) AS bucket_floor
      FROM config
), bounds AS (
    SELECT
        bucketed.*,
        CASE
            WHEN bucketed.bucket_floor = p_as_of THEN p_as_of
            ELSE bucketed.bucket_floor + make_interval(mins => bucketed.bucket_minutes)
        END AS period_end,
        CASE
            WHEN bucketed.bucket_floor = p_as_of THEN p_as_of
            ELSE bucketed.bucket_floor + make_interval(mins => bucketed.bucket_minutes)
        END - make_interval(hours => bucketed.period_hours) AS period_start,
        CASE
            WHEN bucketed.bucket_floor = p_as_of THEN p_as_of
            ELSE bucketed.bucket_floor + make_interval(mins => bucketed.bucket_minutes)
        END - make_interval(hours => bucketed.period_hours * 2) AS previous_period_start
      FROM bucketed
), period_videos AS (
    SELECT
        period_window.window_name,
        video.id AS video_id,
        video.platform,
        video.region,
        video.language,
        category.slug AS category_slug,
        classification.topic,
        classification.content_type,
        classification.format,
        classification.hook_type,
        classification.source_type,
        snapshot.views,
        metric.engagement_rate,
        metric.view_velocity,
        metric.outlier_percentile,
        metric.views_percentile,
        metric.engagement_percentile,
        metric.virality_score,
        monetization.monetization_score
      FROM bounds
      CROSS JOIN LATERAL (
          VALUES
              ('current'::TEXT, bounds.period_start, bounds.period_end),
              ('previous'::TEXT, bounds.previous_period_start, bounds.period_start)
      ) period_window (window_name, window_start, window_end)
      JOIN videos video
        ON video.published_at >= period_window.window_start
       AND video.published_at < period_window.window_end
      JOIN video_classifications classification
        ON classification.video_id = video.id
      LEFT JOIN categories category ON category.id = classification.category_id
      JOIN LATERAL (
          SELECT video_snapshot.*
            FROM video_snapshots video_snapshot
           WHERE video_snapshot.video_id = video.id
             AND video_snapshot.collected_at < period_window.window_end
           ORDER BY video_snapshot.collected_at DESC, video_snapshot.id DESC
           LIMIT 1
      ) snapshot ON TRUE
      LEFT JOIN video_metrics metric
        ON metric.snapshot_id = snapshot.id
       AND metric.calculation_version = bounds.metrics_version
      LEFT JOIN video_monetization_scores monetization
        ON monetization.video_id = video.id
       AND monetization.calculation_version = bounds.monetization_version
), dimensioned AS (
    SELECT
        period_videos.*,
        dimension.dimension_type,
        dimension.dimension_value
      FROM period_videos
      CROSS JOIN LATERAL (
          VALUES
              ('category'::TEXT, period_videos.category_slug),
              ('topic'::TEXT, period_videos.topic),
              ('content_type'::TEXT, period_videos.content_type),
              ('format'::TEXT, period_videos.format),
              ('hook_type'::TEXT, period_videos.hook_type),
              ('source_type'::TEXT, period_videos.source_type),
              (
                  'category_format_source'::TEXT,
                  CASE
                      WHEN period_videos.category_slug IS NOT NULL THEN
                          period_videos.category_slug || '|' || period_videos.format || '|' || period_videos.source_type
                      ELSE NULL
                  END
              )
      ) dimension (dimension_type, dimension_value)
     WHERE dimension.dimension_value IS NOT NULL
       AND length(btrim(dimension.dimension_value)) > 0
), raw_aggregates AS (
    SELECT
        dimensioned.window_name,
        dimensioned.platform,
        dimensioned.region,
        dimensioned.language,
        dimensioned.dimension_type,
        dimensioned.dimension_value,
        count(*)::INTEGER AS sample_size,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY dimensioned.views)::NUMERIC AS median_views,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY dimensioned.views)::NUMERIC AS p75_views,
        percentile_cont(0.90) WITHIN GROUP (ORDER BY dimensioned.views)::NUMERIC AS p90_views,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY dimensioned.engagement_rate)::NUMERIC AS median_engagement,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY dimensioned.view_velocity)::NUMERIC AS median_velocity,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY dimensioned.virality_score)::NUMERIC AS median_virality,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY dimensioned.monetization_score)::NUMERIC AS median_monetization,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY dimensioned.engagement_percentile)::NUMERIC AS median_engagement_percentile,
        count(*) FILTER (WHERE dimensioned.outlier_percentile >= bounds.outlier_threshold)::INTEGER AS outlier_count,
        count(dimensioned.outlier_percentile)::INTEGER AS outlier_available,
        count(*) FILTER (WHERE dimensioned.virality_score >= bounds.high_virality_threshold)::INTEGER AS high_performance_count,
        count(dimensioned.virality_score)::INTEGER AS virality_available,
        count(*) FILTER (WHERE dimensioned.views_percentile >= 0.75)::INTEGER AS p75_count,
        count(*) FILTER (WHERE dimensioned.views_percentile >= 0.90)::INTEGER AS p90_count,
        count(dimensioned.views_percentile)::INTEGER AS views_percentile_available
      FROM dimensioned
      CROSS JOIN bounds
     GROUP BY
        dimensioned.window_name,
        dimensioned.platform,
        dimensioned.region,
        dimensioned.language,
        dimensioned.dimension_type,
        dimensioned.dimension_value
), derived_aggregates AS (
    SELECT
        raw_aggregates.*,
        CASE
            WHEN raw_aggregates.outlier_available > 0
                THEN round(raw_aggregates.outlier_count::NUMERIC / raw_aggregates.outlier_available, 4)
            ELSE NULL
        END AS outlier_rate,
        CASE
            WHEN raw_aggregates.virality_available > 0
                THEN round(raw_aggregates.high_performance_count::NUMERIC / raw_aggregates.virality_available, 4)
            ELSE NULL
        END AS high_performance_rate,
        CASE
            WHEN raw_aggregates.views_percentile_available > 0
                THEN round(raw_aggregates.p75_count::NUMERIC / raw_aggregates.views_percentile_available, 4)
            ELSE NULL
        END AS p75_performance_rate,
        CASE
            WHEN raw_aggregates.views_percentile_available > 0
                THEN round(raw_aggregates.p90_count::NUMERIC / raw_aggregates.views_percentile_available, 4)
            ELSE NULL
        END AS p90_performance_rate,
        CASE
            WHEN raw_aggregates.median_views IS NOT NULL AND raw_aggregates.p90_views IS NOT NULL THEN
                round(
                    GREATEST(
                        0::NUMERIC,
                        1 - LEAST(
                            1::NUMERIC,
                            (raw_aggregates.p90_views - raw_aggregates.median_views)
                            / GREATEST(raw_aggregates.median_views, 1)
                        )
                    ),
                    4
                )
            ELSE NULL
        END AS dispersion_score
      FROM raw_aggregates
), consistency_components AS (
    SELECT
        derived_aggregates.*,
        LEAST(1::NUMERIC, derived_aggregates.sample_size::NUMERIC / bounds.min_sample_size) AS sample_adequacy,
        (bounds.sample_weight
         + CASE WHEN derived_aggregates.p75_performance_rate IS NOT NULL THEN bounds.p75_weight ELSE 0 END
         + CASE WHEN derived_aggregates.p90_performance_rate IS NOT NULL THEN bounds.p90_weight ELSE 0 END
         + CASE WHEN derived_aggregates.median_engagement_percentile IS NOT NULL THEN bounds.engagement_weight ELSE 0 END
         + CASE WHEN derived_aggregates.dispersion_score IS NOT NULL THEN bounds.dispersion_weight ELSE 0 END) AS available_consistency_weight,
        (LEAST(1::NUMERIC, derived_aggregates.sample_size::NUMERIC / bounds.min_sample_size) * bounds.sample_weight
         + COALESCE(derived_aggregates.p75_performance_rate * bounds.p75_weight, 0)
         + COALESCE(derived_aggregates.p90_performance_rate * bounds.p90_weight, 0)
         + COALESCE(derived_aggregates.median_engagement_percentile * bounds.engagement_weight, 0)
         + COALESCE(derived_aggregates.dispersion_score * bounds.dispersion_weight, 0)) AS weighted_consistency
      FROM derived_aggregates
      CROSS JOIN bounds
), scored_aggregates AS (
    SELECT
        consistency_components.*,
        CASE
            WHEN consistency_components.available_consistency_weight > 0
                THEN round(10 * consistency_components.weighted_consistency / consistency_components.available_consistency_weight, 4)
            ELSE NULL
        END AS consistency_score
      FROM consistency_components
), compared AS (
    SELECT
        current_group.*,
        COALESCE(previous_group.sample_size, 0) AS previous_sample_size,
        CASE
            WHEN current_group.sample_size >= bounds.min_sample_size
             AND COALESCE(previous_group.sample_size, 0) >= bounds.min_sample_size
             AND current_group.median_virality IS NOT NULL
             AND previous_group.median_virality IS NOT NULL
                THEN round((current_group.median_virality - previous_group.median_virality) / 10, 6)
            ELSE NULL
        END AS trend_change
      FROM scored_aggregates current_group
      CROSS JOIN bounds
      LEFT JOIN scored_aggregates previous_group
        ON previous_group.window_name = 'previous'
       AND previous_group.platform = current_group.platform
       AND previous_group.region IS NOT DISTINCT FROM current_group.region
       AND previous_group.language IS NOT DISTINCT FROM current_group.language
       AND previous_group.dimension_type = current_group.dimension_type
       AND previous_group.dimension_value = current_group.dimension_value
     WHERE current_group.window_name = 'current'
), final_statistics AS (
    SELECT
        compared.*,
        CASE
            WHEN compared.trend_change IS NULL THEN 'insufficient_data'
            WHEN compared.trend_change >= bounds.direction_threshold THEN 'rising'
            WHEN compared.trend_change <= -bounds.direction_threshold THEN 'declining'
            ELSE 'stable'
        END AS trend_direction
      FROM compared
      CROSS JOIN bounds
), upserted AS (
    INSERT INTO category_statistics (
        period_start,
        period_end,
        platform,
        region,
        language,
        category_slug,
        dimension_type,
        dimension_value,
        topic,
        content_type,
        format,
        hook_type,
        source_type,
        sample_size,
        median_views,
        p75_views,
        p90_views,
        median_engagement,
        median_velocity,
        median_virality,
        median_monetization,
        outlier_count,
        outlier_rate,
        high_performance_rate,
        p75_performance_rate,
        p90_performance_rate,
        dispersion_score,
        consistency_score,
        saturation_score,
        opportunity_score,
        previous_sample_size,
        trend_change,
        trend_direction,
        calculation_version,
        created_at
    )
    SELECT
        bounds.period_start,
        bounds.period_end,
        final_statistics.platform,
        final_statistics.region,
        final_statistics.language,
        CASE
            WHEN final_statistics.dimension_type = 'category' THEN final_statistics.dimension_value
            WHEN final_statistics.dimension_type = 'category_format_source' THEN split_part(final_statistics.dimension_value, '|', 1)
            ELSE NULL
        END,
        final_statistics.dimension_type,
        final_statistics.dimension_value,
        CASE WHEN final_statistics.dimension_type = 'topic' THEN final_statistics.dimension_value ELSE NULL END,
        CASE WHEN final_statistics.dimension_type = 'content_type' THEN final_statistics.dimension_value ELSE NULL END,
        CASE
            WHEN final_statistics.dimension_type = 'format' THEN final_statistics.dimension_value
            WHEN final_statistics.dimension_type = 'category_format_source' THEN split_part(final_statistics.dimension_value, '|', 2)
            ELSE NULL
        END,
        CASE WHEN final_statistics.dimension_type = 'hook_type' THEN final_statistics.dimension_value ELSE NULL END,
        CASE
            WHEN final_statistics.dimension_type = 'source_type' THEN final_statistics.dimension_value
            WHEN final_statistics.dimension_type = 'category_format_source' THEN split_part(final_statistics.dimension_value, '|', 3)
            ELSE NULL
        END,
        final_statistics.sample_size,
        final_statistics.median_views,
        final_statistics.p75_views,
        final_statistics.p90_views,
        final_statistics.median_engagement,
        final_statistics.median_velocity,
        final_statistics.median_virality,
        final_statistics.median_monetization,
        final_statistics.outlier_count,
        final_statistics.outlier_rate,
        final_statistics.high_performance_rate,
        final_statistics.p75_performance_rate,
        final_statistics.p90_performance_rate,
        final_statistics.dispersion_score,
        final_statistics.consistency_score,
        NULL,
        NULL,
        final_statistics.previous_sample_size,
        final_statistics.trend_change,
        final_statistics.trend_direction,
        bounds.calculation_version,
        p_as_of
      FROM final_statistics
      CROSS JOIN bounds
    ON CONFLICT (
        period_start,
        period_end,
        platform,
        region,
        language,
        dimension_type,
        dimension_value,
        calculation_version
    ) DO UPDATE
    SET
        category_slug = EXCLUDED.category_slug,
        topic = EXCLUDED.topic,
        content_type = EXCLUDED.content_type,
        format = EXCLUDED.format,
        hook_type = EXCLUDED.hook_type,
        source_type = EXCLUDED.source_type,
        sample_size = EXCLUDED.sample_size,
        median_views = EXCLUDED.median_views,
        p75_views = EXCLUDED.p75_views,
        p90_views = EXCLUDED.p90_views,
        median_engagement = EXCLUDED.median_engagement,
        median_velocity = EXCLUDED.median_velocity,
        median_virality = EXCLUDED.median_virality,
        median_monetization = EXCLUDED.median_monetization,
        outlier_count = EXCLUDED.outlier_count,
        outlier_rate = EXCLUDED.outlier_rate,
        high_performance_rate = EXCLUDED.high_performance_rate,
        p75_performance_rate = EXCLUDED.p75_performance_rate,
        p90_performance_rate = EXCLUDED.p90_performance_rate,
        dispersion_score = EXCLUDED.dispersion_score,
        consistency_score = EXCLUDED.consistency_score,
        previous_sample_size = EXCLUDED.previous_sample_size,
        trend_change = EXCLUDED.trend_change,
        trend_direction = EXCLUDED.trend_direction,
        created_at = EXCLUDED.created_at
    RETURNING
        sample_size,
        trend_direction
)
SELECT
    (SELECT count(DISTINCT video_id) FROM period_videos WHERE window_name = 'current') AS videos_in_current_period,
    (SELECT count(*) FROM final_statistics) AS dimension_rows,
    (SELECT count(*) FROM upserted) AS statistics_upserted,
    (SELECT count(*) FROM upserted WHERE sample_size >= bounds.min_sample_size) AS sufficient_sample_statistics,
    (SELECT count(*) FROM upserted WHERE trend_direction = 'rising') AS rising_statistics,
    (SELECT count(*) FROM upserted WHERE trend_direction = 'stable') AS stable_statistics,
    (SELECT count(*) FROM upserted WHERE trend_direction = 'declining') AS declining_statistics,
    (SELECT count(*) FROM upserted WHERE trend_direction = 'insufficient_data') AS insufficient_statistics,
    bounds.calculation_version,
    bounds.period_start,
    bounds.period_end
  FROM bounds;
$$;

COMMIT;
