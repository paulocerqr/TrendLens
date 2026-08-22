BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('OPPORTUNITY_CALCULATION_VERSION', '"v1"'::JSONB, 'Versão da fórmula e do ranking calculados pelo Opportunity Engine.'),
    ('OPPORTUNITY_VIRALITY_WEIGHT', '0.50'::JSONB, 'Peso da mediana de Virality Score no Opportunity Score.'),
    ('OPPORTUNITY_MONETIZATION_WEIGHT', '0.35'::JSONB, 'Peso da mediana de Monetization Score no Opportunity Score.'),
    ('OPPORTUNITY_CONSISTENCY_WEIGHT', '0.15'::JSONB, 'Peso do Consistency Score no Opportunity Score.')
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

ALTER TABLE category_statistics
    ADD COLUMN IF NOT EXISTS opportunity_rank INTEGER,
    ADD COLUMN IF NOT EXISTS opportunity_percentile NUMERIC(5, 4),
    ADD COLUMN IF NOT EXISTS opportunity_component_count SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS opportunity_calculation_version TEXT,
    ADD COLUMN IF NOT EXISTS opportunity_calculated_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_opportunity_rank_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_opportunity_rank_check CHECK (opportunity_rank IS NULL OR opportunity_rank > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_opportunity_percentile_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_opportunity_percentile_check CHECK (opportunity_percentile IS NULL OR opportunity_percentile BETWEEN 0 AND 1);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_opportunity_component_count_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_opportunity_component_count_check CHECK (opportunity_component_count BETWEEN 0 AND 3);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_opportunity_version_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_opportunity_version_check CHECK (opportunity_calculation_version IS NULL OR length(btrim(opportunity_calculation_version)) > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'category_statistics'::regclass AND conname = 'category_statistics_opportunity_completeness_check') THEN
        ALTER TABLE category_statistics ADD CONSTRAINT category_statistics_opportunity_completeness_check CHECK (
            (opportunity_score IS NULL AND opportunity_rank IS NULL AND opportunity_percentile IS NULL)
            OR
            (opportunity_score IS NOT NULL AND opportunity_rank IS NOT NULL AND opportunity_percentile IS NOT NULL AND opportunity_component_count = 3)
        );
    END IF;
END;
$$;

DROP INDEX IF EXISTS category_statistics_opportunity_idx;

CREATE INDEX category_statistics_opportunity_idx
    ON category_statistics (
        period_end DESC,
        dimension_type,
        opportunity_rank,
        opportunity_score DESC
    )
    WHERE opportunity_score IS NOT NULL;

CREATE OR REPLACE FUNCTION refresh_opportunity_rankings(
    p_as_of TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    statistics_considered BIGINT,
    statistics_scored BIGINT,
    statistics_incomplete BIGINT,
    categories_ranked BIGINT,
    top_opportunity_score NUMERIC,
    opportunity_calculation_version TEXT,
    trend_calculation_version TEXT,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ
)
LANGUAGE sql
VOLATILE
AS $$
WITH config AS (
    SELECT
        COALESCE((SELECT value #>> '{}' FROM settings WHERE key = 'OPPORTUNITY_CALCULATION_VERSION'), 'v1') AS opportunity_version,
        COALESCE((SELECT value #>> '{}' FROM settings WHERE key = 'TREND_CALCULATION_VERSION'), 'v1') AS trend_version,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'OPPORTUNITY_VIRALITY_WEIGHT'), 0.50), 0) AS virality_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'OPPORTUNITY_MONETIZATION_WEIGHT'), 0.35), 0) AS monetization_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'OPPORTUNITY_CONSISTENCY_WEIGHT'), 0.15), 0) AS consistency_weight
), latest_period AS (
    SELECT max(statistic.period_end) AS period_end
      FROM category_statistics statistic
      CROSS JOIN config
     WHERE statistic.calculation_version = config.trend_version
), target AS MATERIALIZED (
    SELECT statistic.*
      FROM category_statistics statistic
      CROSS JOIN config
      CROSS JOIN latest_period
     WHERE statistic.calculation_version = config.trend_version
       AND statistic.period_end = latest_period.period_end
), components AS (
    SELECT
        target.*,
        ((target.median_virality IS NOT NULL)::INTEGER
         + (target.median_monetization IS NOT NULL)::INTEGER
         + (target.consistency_score IS NOT NULL)::INTEGER)::SMALLINT AS component_count,
        config.opportunity_version,
        config.virality_weight,
        config.monetization_weight,
        config.consistency_weight,
        config.virality_weight + config.monetization_weight + config.consistency_weight AS available_weight
      FROM target
      CROSS JOIN config
), scored AS (
    SELECT
        components.*,
        CASE
            WHEN components.component_count = 3
             AND components.available_weight > 0
                THEN round(
                    (
                        GREATEST(0::NUMERIC, LEAST(10::NUMERIC, components.median_virality)) * components.virality_weight
                      + GREATEST(0::NUMERIC, LEAST(10::NUMERIC, components.median_monetization)) * components.monetization_weight
                      + GREATEST(0::NUMERIC, LEAST(10::NUMERIC, components.consistency_score)) * components.consistency_weight
                    ) / components.available_weight,
                    4
                )
            ELSE NULL
        END AS calculated_score
      FROM components
), ranked AS (
    SELECT
        scored.id,
        scored.calculated_score,
        dense_rank() OVER (
            PARTITION BY scored.period_start, scored.period_end, scored.platform, scored.region, scored.language, scored.dimension_type, scored.calculation_version
            ORDER BY scored.calculated_score DESC
        )::INTEGER AS calculated_rank,
        CASE
            WHEN count(*) OVER (
                PARTITION BY scored.period_start, scored.period_end, scored.platform, scored.region, scored.language, scored.dimension_type, scored.calculation_version
            ) = 1 THEN 1::NUMERIC
            ELSE round(percent_rank() OVER (
                PARTITION BY scored.period_start, scored.period_end, scored.platform, scored.region, scored.language, scored.dimension_type, scored.calculation_version
                ORDER BY scored.calculated_score ASC
            )::NUMERIC, 4)
        END AS calculated_percentile
      FROM scored
     WHERE scored.calculated_score IS NOT NULL
), updated AS (
    UPDATE category_statistics statistic
       SET opportunity_score = scored.calculated_score,
           opportunity_rank = ranked.calculated_rank,
           opportunity_percentile = ranked.calculated_percentile,
           opportunity_component_count = scored.component_count,
           opportunity_calculation_version = scored.opportunity_version,
           opportunity_calculated_at = p_as_of
      FROM scored
      LEFT JOIN ranked ON ranked.id = scored.id
     WHERE statistic.id = scored.id
    RETURNING
        statistic.dimension_type,
        statistic.opportunity_score,
        statistic.opportunity_rank,
        statistic.period_start,
        statistic.period_end
)
SELECT
    (SELECT count(*) FROM target) AS statistics_considered,
    (SELECT count(*) FROM updated WHERE opportunity_score IS NOT NULL) AS statistics_scored,
    (SELECT count(*) FROM updated WHERE opportunity_score IS NULL) AS statistics_incomplete,
    (SELECT count(*) FROM updated WHERE dimension_type = 'category' AND opportunity_score IS NOT NULL) AS categories_ranked,
    (SELECT max(opportunity_score) FROM updated WHERE dimension_type = 'category') AS top_opportunity_score,
    config.opportunity_version,
    config.trend_version,
    (SELECT min(target.period_start) FROM target),
    (SELECT max(target.period_end) FROM target)
  FROM config;
$$;

COMMIT;
