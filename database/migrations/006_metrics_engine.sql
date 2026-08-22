BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('METRICS_MAX_VIDEOS_PER_RUN', '1000'::JSONB, 'Quantidade máxima de vídeos cujas métricas atuais são recalculadas por execução.'),
    ('METRICS_ANALYSIS_WINDOW_DAYS', '7'::JSONB, 'Janela, em dias, usada para selecionar vídeos e formar coortes comparáveis.'),
    ('METRICS_CHANNEL_BASELINE_WINDOW_DAYS', '30'::JSONB, 'Janela recente, em dias, usada no baseline de visualizações do canal.'),
    ('METRICS_CHANNEL_BASELINE_MIN_VIDEOS', '3'::JSONB, 'Quantidade mínima de outros vídeos necessária para calcular o baseline do canal.'),
    ('METRICS_FRESHNESS_HORIZON_HOURS', '168'::JSONB, 'Horizonte, em horas, no qual o Freshness Score decai linearmente de 1 para 0.'),
    ('METRICS_MIN_VIRALITY_COMPONENTS', '3'::JSONB, 'Quantidade mínima de componentes disponíveis para calcular o Virality Score.'),
    ('METRICS_CALCULATION_VERSION', '"v1"'::JSONB, 'Versão das fórmulas do Metrics Engine e do Virality Score.'),
    ('VIRALITY_VELOCITY_WEIGHT', '0.35'::JSONB, 'Peso inicial do percentil de View Velocity no Virality Score.'),
    ('VIRALITY_ENGAGEMENT_WEIGHT', '0.20'::JSONB, 'Peso inicial do percentil de Engagement Rate no Virality Score.'),
    ('VIRALITY_OUTLIER_WEIGHT', '0.20'::JSONB, 'Peso inicial do percentil de Outlier Score no Virality Score.'),
    ('VIRALITY_VIEWS_WEIGHT', '0.15'::JSONB, 'Peso inicial do percentil de views no Virality Score.'),
    ('VIRALITY_FRESHNESS_WEIGHT', '0.10'::JSONB, 'Peso inicial do Freshness Score no Virality Score.')
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'video_metrics'::regclass
           AND conname = 'video_metrics_calculation_version_check'
    ) THEN
        ALTER TABLE video_metrics
            ADD CONSTRAINT video_metrics_calculation_version_check
            CHECK (length(btrim(calculation_version)) > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'video_metrics'::regclass
           AND conname = 'video_metrics_distinct_snapshots_check'
    ) THEN
        ALTER TABLE video_metrics
            ADD CONSTRAINT video_metrics_distinct_snapshots_check
            CHECK (previous_snapshot_id IS NULL OR previous_snapshot_id <> snapshot_id);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS video_metrics_calculation_version_idx
    ON video_metrics (calculation_version, calculated_at DESC);

CREATE OR REPLACE FUNCTION refresh_video_metrics(
    p_limit INTEGER,
    p_as_of TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    eligible_videos BIGINT,
    candidates_selected BIGINT,
    metrics_upserted BIGINT,
    virality_scored BIGINT,
    velocity_available BIGINT,
    acceleration_available BIGINT,
    channel_baseline_available BIGINT,
    calculation_version TEXT,
    calculated_at TIMESTAMPTZ
)
LANGUAGE sql
VOLATILE
AS $$
WITH config AS (
    SELECT
        COALESCE(MAX(value #>> '{}') FILTER (WHERE key = 'METRICS_CALCULATION_VERSION'), 'v1') AS calculation_version,
        GREATEST(COALESCE(MAX((value #>> '{}')::INTEGER) FILTER (WHERE key = 'METRICS_ANALYSIS_WINDOW_DAYS'), 7), 0) AS analysis_window_days,
        GREATEST(COALESCE(MAX((value #>> '{}')::INTEGER) FILTER (WHERE key = 'METRICS_CHANNEL_BASELINE_WINDOW_DAYS'), 30), 0) AS baseline_window_days,
        GREATEST(COALESCE(MAX((value #>> '{}')::INTEGER) FILTER (WHERE key = 'METRICS_CHANNEL_BASELINE_MIN_VIDEOS'), 3), 1) AS baseline_min_videos,
        GREATEST(COALESCE(MAX((value #>> '{}')::NUMERIC) FILTER (WHERE key = 'METRICS_FRESHNESS_HORIZON_HOURS'), 168), 0) AS freshness_horizon_hours,
        GREATEST(COALESCE(MAX((value #>> '{}')::INTEGER) FILTER (WHERE key = 'METRICS_MIN_VIRALITY_COMPONENTS'), 3), 1) AS min_virality_components,
        GREATEST(COALESCE(MAX((value #>> '{}')::INTEGER) FILTER (WHERE key = 'MIN_SAMPLE_SIZE'), 30), 2) AS min_sample_size,
        GREATEST(COALESCE(MAX((value #>> '{}')::NUMERIC) FILTER (WHERE key = 'COMMENT_WEIGHT'), 3), 0) AS comment_weight,
        GREATEST(COALESCE(MAX((value #>> '{}')::NUMERIC) FILTER (WHERE key = 'VIRALITY_VELOCITY_WEIGHT'), 0.35), 0) AS velocity_weight,
        GREATEST(COALESCE(MAX((value #>> '{}')::NUMERIC) FILTER (WHERE key = 'VIRALITY_ENGAGEMENT_WEIGHT'), 0.20), 0) AS engagement_weight,
        GREATEST(COALESCE(MAX((value #>> '{}')::NUMERIC) FILTER (WHERE key = 'VIRALITY_OUTLIER_WEIGHT'), 0.20), 0) AS outlier_weight,
        GREATEST(COALESCE(MAX((value #>> '{}')::NUMERIC) FILTER (WHERE key = 'VIRALITY_VIEWS_WEIGHT'), 0.15), 0) AS views_weight,
        GREATEST(COALESCE(MAX((value #>> '{}')::NUMERIC) FILTER (WHERE key = 'VIRALITY_FRESHNESS_WEIGHT'), 0.10), 0) AS freshness_weight
      FROM settings
), snapshot_history AS (
    SELECT
        snapshot.*,
        lag(snapshot.id) OVER snapshot_order AS previous_snapshot_id,
        lag(snapshot.views) OVER snapshot_order AS previous_views,
        lag(snapshot.collected_at) OVER snapshot_order AS previous_collected_at,
        lag(snapshot.views, 2) OVER snapshot_order AS second_previous_views,
        lag(snapshot.collected_at, 2) OVER snapshot_order AS second_previous_collected_at
      FROM video_snapshots snapshot
    WINDOW snapshot_order AS (
        PARTITION BY snapshot.video_id
        ORDER BY snapshot.collected_at, snapshot.id
    )
), latest_snapshots AS (
    SELECT DISTINCT ON (video.id)
        video.id AS video_id,
        video.platform,
        video.channel_id,
        video.published_at,
        video.region,
        classification.category_id,
        history.id AS snapshot_id,
        history.collected_at,
        history.views,
        history.likes,
        history.comments,
        history.previous_snapshot_id,
        history.previous_views,
        history.previous_collected_at,
        history.second_previous_views,
        history.second_previous_collected_at
      FROM videos video
      CROSS JOIN config
      JOIN snapshot_history history ON history.video_id = video.id
      LEFT JOIN video_classifications classification ON classification.video_id = video.id
     WHERE video.platform = 'youtube'
       AND video.published_at <= p_as_of
       AND video.published_at >= p_as_of - make_interval(days => config.analysis_window_days)
       AND history.collected_at <= p_as_of
     ORDER BY video.id, history.collected_at DESC, history.id DESC
), ordered_targets AS (
    SELECT
        latest_snapshots.snapshot_id,
        row_number() OVER (
            ORDER BY
                (metrics.snapshot_id IS NULL OR metrics.calculation_version <> config.calculation_version) DESC,
                latest_snapshots.collected_at DESC,
                latest_snapshots.snapshot_id
        ) AS target_order
      FROM latest_snapshots
      CROSS JOIN config
      LEFT JOIN video_metrics metrics ON metrics.snapshot_id = latest_snapshots.snapshot_id
), targets AS (
    SELECT snapshot_id
      FROM ordered_targets
     WHERE target_order <= GREATEST(p_limit, 0)
), metric_basis AS (
    SELECT
        latest.*,
        CASE
            WHEN latest.views > 0 AND latest.likes IS NOT NULL
                THEN latest.likes::NUMERIC / latest.views
            ELSE NULL
        END AS like_rate,
        CASE
            WHEN latest.views > 0 AND latest.comments IS NOT NULL
                THEN latest.comments::NUMERIC / latest.views
            ELSE NULL
        END AS comment_rate,
        CASE
            WHEN latest.views > 0 AND latest.likes IS NOT NULL AND latest.comments IS NOT NULL
                THEN (latest.likes + (latest.comments * config.comment_weight))::NUMERIC / latest.views
            ELSE NULL
        END AS engagement_rate,
        CASE
            WHEN latest.previous_snapshot_id IS NOT NULL
             AND latest.collected_at > latest.previous_collected_at
                THEN (latest.views - latest.previous_views)::NUMERIC
                     / (EXTRACT(EPOCH FROM (latest.collected_at - latest.previous_collected_at)) / 3600.0)
            ELSE NULL
        END AS view_velocity,
        CASE
            WHEN latest.second_previous_collected_at IS NOT NULL
             AND latest.previous_collected_at > latest.second_previous_collected_at
                THEN (latest.previous_views - latest.second_previous_views)::NUMERIC
                     / (EXTRACT(EPOCH FROM (latest.previous_collected_at - latest.second_previous_collected_at)) / 3600.0)
            ELSE NULL
        END AS previous_view_velocity,
        CASE
            WHEN config.freshness_horizon_hours > 0 THEN
                GREATEST(
                    0::NUMERIC,
                    LEAST(
                        1::NUMERIC,
                        1 - (EXTRACT(EPOCH FROM (p_as_of - latest.published_at)) / 3600.0)
                            / config.freshness_horizon_hours
                    )
                )
            ELSE NULL
        END AS freshness_score,
        baseline.sample_size AS channel_baseline_sample_size,
        CASE
            WHEN baseline.sample_size >= config.baseline_min_videos
                THEN baseline.median_views
            ELSE NULL
        END AS channel_median_views
      FROM latest_snapshots latest
      CROSS JOIN config
      LEFT JOIN LATERAL (
          SELECT
              count(*)::INTEGER AS sample_size,
              percentile_cont(0.5) WITHIN GROUP (ORDER BY sample.views)::NUMERIC AS median_views
            FROM (
                SELECT DISTINCT ON (baseline_video.id)
                    baseline_snapshot.views
                  FROM videos baseline_video
                  JOIN video_snapshots baseline_snapshot ON baseline_snapshot.video_id = baseline_video.id
                 WHERE baseline_video.platform = latest.platform
                   AND baseline_video.channel_id = latest.channel_id
                   AND length(btrim(baseline_video.channel_id)) > 0
                   AND baseline_video.id <> latest.video_id
                   AND baseline_video.published_at <= p_as_of
                   AND baseline_video.published_at >= p_as_of - make_interval(days => config.baseline_window_days)
                   AND baseline_snapshot.collected_at <= p_as_of
                 ORDER BY baseline_video.id, baseline_snapshot.collected_at DESC, baseline_snapshot.id DESC
            ) sample
      ) baseline ON TRUE
), raw_metrics AS (
    SELECT
        metric_basis.*,
        CASE
            WHEN metric_basis.view_velocity IS NOT NULL
             AND metric_basis.previous_view_velocity IS NOT NULL
             AND metric_basis.collected_at > metric_basis.previous_collected_at
                THEN (metric_basis.view_velocity - metric_basis.previous_view_velocity)
                     / (EXTRACT(EPOCH FROM (metric_basis.collected_at - metric_basis.previous_collected_at)) / 3600.0)
            ELSE NULL
        END AS view_acceleration,
        CASE
            WHEN metric_basis.channel_median_views > 0
                THEN metric_basis.views::NUMERIC / metric_basis.channel_median_views
            ELSE NULL
        END AS relative_performance,
        CASE
            WHEN metric_basis.channel_median_views > 0
                THEN metric_basis.views::NUMERIC / metric_basis.channel_median_views
            ELSE NULL
        END AS outlier_score
      FROM metric_basis
), fallback_views AS (
    SELECT
        snapshot_id,
        count(*) OVER (PARTITION BY platform, region) AS sample_size,
        percent_rank() OVER (PARTITION BY platform, region ORDER BY views) AS percentile
      FROM raw_metrics
), category_views AS (
    SELECT
        snapshot_id,
        count(*) OVER (PARTITION BY platform, region, category_id) AS sample_size,
        percent_rank() OVER (PARTITION BY platform, region, category_id ORDER BY views) AS percentile
      FROM raw_metrics
     WHERE category_id IS NOT NULL
), fallback_velocity AS (
    SELECT
        snapshot_id,
        count(*) OVER (PARTITION BY platform, region) AS sample_size,
        percent_rank() OVER (PARTITION BY platform, region ORDER BY view_velocity) AS percentile
      FROM raw_metrics
     WHERE view_velocity IS NOT NULL
), category_velocity AS (
    SELECT
        snapshot_id,
        count(*) OVER (PARTITION BY platform, region, category_id) AS sample_size,
        percent_rank() OVER (PARTITION BY platform, region, category_id ORDER BY view_velocity) AS percentile
      FROM raw_metrics
     WHERE category_id IS NOT NULL AND view_velocity IS NOT NULL
), fallback_engagement AS (
    SELECT
        snapshot_id,
        count(*) OVER (PARTITION BY platform, region) AS sample_size,
        percent_rank() OVER (PARTITION BY platform, region ORDER BY engagement_rate) AS percentile
      FROM raw_metrics
     WHERE engagement_rate IS NOT NULL
), category_engagement AS (
    SELECT
        snapshot_id,
        count(*) OVER (PARTITION BY platform, region, category_id) AS sample_size,
        percent_rank() OVER (PARTITION BY platform, region, category_id ORDER BY engagement_rate) AS percentile
      FROM raw_metrics
     WHERE category_id IS NOT NULL AND engagement_rate IS NOT NULL
), fallback_outlier AS (
    SELECT
        snapshot_id,
        count(*) OVER (PARTITION BY platform, region) AS sample_size,
        percent_rank() OVER (PARTITION BY platform, region ORDER BY outlier_score) AS percentile
      FROM raw_metrics
     WHERE outlier_score IS NOT NULL
), category_outlier AS (
    SELECT
        snapshot_id,
        count(*) OVER (PARTITION BY platform, region, category_id) AS sample_size,
        percent_rank() OVER (PARTITION BY platform, region, category_id ORDER BY outlier_score) AS percentile
      FROM raw_metrics
     WHERE category_id IS NOT NULL AND outlier_score IS NOT NULL
), percentile_metrics AS (
    SELECT
        raw_metrics.*,
        CASE
            WHEN category_velocity.sample_size >= config.min_sample_size THEN category_velocity.percentile
            WHEN fallback_velocity.sample_size >= config.min_sample_size THEN fallback_velocity.percentile
            ELSE NULL
        END::NUMERIC AS velocity_percentile,
        CASE
            WHEN category_engagement.sample_size >= config.min_sample_size THEN category_engagement.percentile
            WHEN fallback_engagement.sample_size >= config.min_sample_size THEN fallback_engagement.percentile
            ELSE NULL
        END::NUMERIC AS engagement_percentile,
        CASE
            WHEN category_outlier.sample_size >= config.min_sample_size THEN category_outlier.percentile
            WHEN fallback_outlier.sample_size >= config.min_sample_size THEN fallback_outlier.percentile
            ELSE NULL
        END::NUMERIC AS outlier_percentile,
        CASE
            WHEN category_views.sample_size >= config.min_sample_size THEN category_views.percentile
            WHEN fallback_views.sample_size >= config.min_sample_size THEN fallback_views.percentile
            ELSE NULL
        END::NUMERIC AS views_percentile
      FROM raw_metrics
      CROSS JOIN config
      JOIN fallback_views USING (snapshot_id)
      LEFT JOIN category_views USING (snapshot_id)
      LEFT JOIN fallback_velocity USING (snapshot_id)
      LEFT JOIN category_velocity USING (snapshot_id)
      LEFT JOIN fallback_engagement USING (snapshot_id)
      LEFT JOIN category_engagement USING (snapshot_id)
      LEFT JOIN fallback_outlier USING (snapshot_id)
      LEFT JOIN category_outlier USING (snapshot_id)
), score_components AS (
    SELECT
        percentile_metrics.*,
        num_nonnulls(
            velocity_percentile,
            engagement_percentile,
            outlier_percentile,
            views_percentile,
            freshness_score
        ) AS component_count,
        (CASE WHEN velocity_percentile IS NOT NULL THEN config.velocity_weight ELSE 0 END
         + CASE WHEN engagement_percentile IS NOT NULL THEN config.engagement_weight ELSE 0 END
         + CASE WHEN outlier_percentile IS NOT NULL THEN config.outlier_weight ELSE 0 END
         + CASE WHEN views_percentile IS NOT NULL THEN config.views_weight ELSE 0 END
         + CASE WHEN freshness_score IS NOT NULL THEN config.freshness_weight ELSE 0 END) AS available_weight,
        (COALESCE(velocity_percentile * config.velocity_weight, 0)
         + COALESCE(engagement_percentile * config.engagement_weight, 0)
         + COALESCE(outlier_percentile * config.outlier_weight, 0)
         + COALESCE(views_percentile * config.views_weight, 0)
         + COALESCE(freshness_score * config.freshness_weight, 0)) AS weighted_score
      FROM percentile_metrics
      CROSS JOIN config
), scored AS (
    SELECT
        score_components.*,
        CASE
            WHEN component_count >= config.min_virality_components
             AND available_weight > 0
                THEN round(10 * weighted_score / available_weight, 4)
            ELSE NULL
        END AS virality_score
      FROM score_components
      CROSS JOIN config
), upserted AS (
    INSERT INTO video_metrics (
        video_id,
        snapshot_id,
        previous_snapshot_id,
        like_rate,
        comment_rate,
        engagement_rate,
        view_velocity,
        view_acceleration,
        channel_median_views,
        relative_performance,
        outlier_score,
        velocity_percentile,
        engagement_percentile,
        outlier_percentile,
        views_percentile,
        freshness_score,
        virality_score,
        calculation_version,
        calculated_at
    )
    SELECT
        scored.video_id,
        scored.snapshot_id,
        scored.previous_snapshot_id,
        scored.like_rate,
        scored.comment_rate,
        scored.engagement_rate,
        scored.view_velocity,
        scored.view_acceleration,
        scored.channel_median_views,
        scored.relative_performance,
        scored.outlier_score,
        scored.velocity_percentile,
        scored.engagement_percentile,
        scored.outlier_percentile,
        scored.views_percentile,
        scored.freshness_score,
        scored.virality_score,
        config.calculation_version,
        p_as_of
      FROM scored
      JOIN targets USING (snapshot_id)
      CROSS JOIN config
    ON CONFLICT (snapshot_id) DO UPDATE
    SET
        video_id = EXCLUDED.video_id,
        previous_snapshot_id = EXCLUDED.previous_snapshot_id,
        like_rate = EXCLUDED.like_rate,
        comment_rate = EXCLUDED.comment_rate,
        engagement_rate = EXCLUDED.engagement_rate,
        view_velocity = EXCLUDED.view_velocity,
        view_acceleration = EXCLUDED.view_acceleration,
        channel_median_views = EXCLUDED.channel_median_views,
        relative_performance = EXCLUDED.relative_performance,
        outlier_score = EXCLUDED.outlier_score,
        velocity_percentile = EXCLUDED.velocity_percentile,
        engagement_percentile = EXCLUDED.engagement_percentile,
        outlier_percentile = EXCLUDED.outlier_percentile,
        views_percentile = EXCLUDED.views_percentile,
        freshness_score = EXCLUDED.freshness_score,
        virality_score = EXCLUDED.virality_score,
        calculation_version = EXCLUDED.calculation_version,
        calculated_at = EXCLUDED.calculated_at
    RETURNING
        snapshot_id,
        view_velocity,
        view_acceleration,
        channel_median_views,
        virality_score
)
SELECT
    (SELECT count(*) FROM latest_snapshots) AS eligible_videos,
    (SELECT count(*) FROM targets) AS candidates_selected,
    (SELECT count(*) FROM upserted) AS metrics_upserted,
    (SELECT count(*) FROM upserted WHERE virality_score IS NOT NULL) AS virality_scored,
    (SELECT count(*) FROM upserted WHERE view_velocity IS NOT NULL) AS velocity_available,
    (SELECT count(*) FROM upserted WHERE view_acceleration IS NOT NULL) AS acceleration_available,
    (SELECT count(*) FROM upserted WHERE channel_median_views IS NOT NULL) AS channel_baseline_available,
    config.calculation_version,
    p_as_of AS calculated_at
  FROM config;
$$;

COMMIT;
