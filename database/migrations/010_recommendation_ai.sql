BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('RECOMMENDATION_MAX_CATEGORIES_PER_RUN', '5'::JSONB, 'Quantidade máxima de categorias enviadas à IA por execução do Recommendation Engine.'),
    ('RECOMMENDATION_MIN_OPPORTUNITY_SCORE', '0'::JSONB, 'Opportunity Score mínimo para uma categoria se tornar candidata a recomendação.'),
    ('RECOMMENDATION_CONTEXT_LIMIT', '5'::JSONB, 'Quantidade máxima de padrões agregados por dimensão incluídos como contexto da IA.'),
    ('RECOMMENDATION_PROMPT_VERSION', '"v2"'::JSONB, 'Versão do prompt estruturado do Recommendation Engine.'),
    ('RECOMMENDATION_MODEL', '"nvidia/llama-3.3-nemotron-super-49b-v1"'::JSONB, 'Modelo NVIDIA NIM utilizado pelo Recommendation Engine, sem armazenar credenciais.')
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

ALTER TABLE recommendations
    ADD COLUMN IF NOT EXISTS platform TEXT NOT NULL DEFAULT 'youtube',
    ADD COLUMN IF NOT EXISTS region CHAR(2),
    ADD COLUMN IF NOT EXISTS language VARCHAR(16),
    ADD COLUMN IF NOT EXISTS consistency_score NUMERIC(6, 4) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS prompt_version TEXT NOT NULL DEFAULT 'v2',
    ADD COLUMN IF NOT EXISTS source_calculation_version TEXT NOT NULL DEFAULT 'v1',
    ADD COLUMN IF NOT EXISTS source_opportunity_version TEXT NOT NULL DEFAULT 'v1',
    ADD COLUMN IF NOT EXISTS evidence_hash TEXT NOT NULL DEFAULT md5('{}'::JSONB::TEXT);

UPDATE recommendations
   SET evidence_hash = md5(evidence_json::TEXT);

ALTER TABLE recommendations
    ALTER COLUMN consistency_score DROP DEFAULT,
    ALTER COLUMN evidence_hash DROP DEFAULT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_category_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_category_check CHECK (category ~ '^[a-z0-9_]+$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_consistency_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_consistency_check CHECK (consistency_score BETWEEN 0 AND 10);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_summary_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_summary_check CHECK (length(btrim(summary)) > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_formats_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_formats_check CHECK (cardinality(recommended_formats) BETWEEN 1 AND 5);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_hooks_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_hooks_check CHECK (cardinality(recommended_hooks) BETWEEN 1 AND 5);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_risks_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_risks_check CHECK (cardinality(risks) BETWEEN 1 AND 5);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_monetization_notes_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_monetization_notes_check CHECK (cardinality(monetization_notes) BETWEEN 1 AND 5);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_model_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_model_check CHECK (length(btrim(model)) > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_prompt_version_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_prompt_version_check CHECK (length(btrim(prompt_version)) > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_source_versions_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_source_versions_check CHECK (length(btrim(source_calculation_version)) > 0 AND length(btrim(source_opportunity_version)) > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_evidence_hash_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_evidence_hash_check CHECK (evidence_hash ~ '^[a-f0-9]{32}$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'recommendations'::regclass AND conname = 'recommendations_evidence_scope_check') THEN
        ALTER TABLE recommendations ADD CONSTRAINT recommendations_evidence_scope_check CHECK (evidence_json ? 'input_scope' AND evidence_json ? 'category_statistics');
    END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS recommendations_evidence_version_idx
    ON recommendations (
        category,
        period_start,
        period_end,
        platform,
        region,
        language,
        prompt_version,
        model,
        evidence_hash
    )
    NULLS NOT DISTINCT;

CREATE INDEX IF NOT EXISTS recommendations_context_rank_idx
    ON recommendations (
        period_end DESC,
        platform,
        region,
        language,
        opportunity_score DESC
    );

CREATE OR REPLACE FUNCTION select_recommendation_candidates(
    p_limit INTEGER DEFAULT NULL
)
RETURNS TABLE (
    category TEXT,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ,
    platform TEXT,
    region CHAR(2),
    language VARCHAR(16),
    opportunity_score NUMERIC,
    virality_score NUMERIC,
    monetization_score NUMERIC,
    consistency_score NUMERIC,
    source_calculation_version TEXT,
    source_opportunity_version TEXT,
    recommendation_model TEXT,
    prompt_version TEXT,
    evidence_json JSONB,
    evidence_hash TEXT
)
LANGUAGE sql
STABLE
AS $$
WITH config AS (
    SELECT
        GREATEST(0, LEAST(50, COALESCE(p_limit, (SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'RECOMMENDATION_MAX_CATEGORIES_PER_RUN'), 5))) AS max_categories,
        GREATEST(1, LEAST(20, COALESCE((SELECT (value #>> '{}')::INTEGER FROM settings WHERE key = 'RECOMMENDATION_CONTEXT_LIMIT'), 5))) AS context_limit,
        GREATEST(0::NUMERIC, LEAST(10::NUMERIC, COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'RECOMMENDATION_MIN_OPPORTUNITY_SCORE'), 0))) AS minimum_score,
        COALESCE(NULLIF((SELECT value #>> '{}' FROM settings WHERE key = 'RECOMMENDATION_MODEL'), ''), NULLIF((SELECT value #>> '{}' FROM settings WHERE key = 'LLM_MODEL'), ''), 'nvidia/llama-3.3-nemotron-super-49b-v1') AS recommendation_model,
        COALESCE(NULLIF((SELECT value #>> '{}' FROM settings WHERE key = 'RECOMMENDATION_PROMPT_VERSION'), ''), 'v2') AS prompt_version,
        COALESCE(NULLIF((SELECT value #>> '{}' FROM settings WHERE key = 'TREND_CALCULATION_VERSION'), ''), 'v1') AS trend_version
), latest_period AS (
    SELECT max(statistic.period_end) AS period_end
      FROM category_statistics statistic
      CROSS JOIN config
     WHERE statistic.calculation_version = config.trend_version
       AND statistic.dimension_type = 'category'
       AND statistic.opportunity_score IS NOT NULL
), category_candidates AS (
    SELECT statistic.*
      FROM category_statistics statistic
      CROSS JOIN config
      CROSS JOIN latest_period
     WHERE statistic.calculation_version = config.trend_version
       AND statistic.period_end = latest_period.period_end
       AND statistic.dimension_type = 'category'
       AND statistic.category_slug IS NOT NULL
       AND statistic.opportunity_score >= config.minimum_score
), evidenced AS (
    SELECT
        candidate.*,
        config.recommendation_model,
        config.prompt_version,
        jsonb_build_object(
            'input_scope', jsonb_build_object(
                'level', 'aggregated',
                'contains_individual_videos', false,
                'period_start', candidate.period_start,
                'period_end', candidate.period_end,
                'platform', candidate.platform,
                'region', candidate.region,
                'language', candidate.language
            ),
            'category_statistics', jsonb_build_object(
                'category', candidate.category_slug,
                'sample_size', candidate.sample_size,
                'previous_sample_size', candidate.previous_sample_size,
                'median_views', candidate.median_views,
                'p75_views', candidate.p75_views,
                'p90_views', candidate.p90_views,
                'median_engagement_rate', candidate.median_engagement,
                'median_view_velocity', candidate.median_velocity,
                'median_virality_score', candidate.median_virality,
                'median_monetization_score', candidate.median_monetization,
                'consistency_score', candidate.consistency_score,
                'opportunity_score', candidate.opportunity_score,
                'opportunity_rank', candidate.opportunity_rank,
                'opportunity_percentile', candidate.opportunity_percentile,
                'outlier_rate', candidate.outlier_rate,
                'high_performance_rate', candidate.high_performance_rate,
                'trend_change', candidate.trend_change,
                'trend_direction', candidate.trend_direction
            ),
            'category_format_source_patterns', COALESCE((
                SELECT jsonb_agg(to_jsonb(pattern) ORDER BY pattern.opportunity_score DESC NULLS LAST, pattern.sample_size DESC)
                  FROM (
                      SELECT related.format, related.source_type, related.sample_size,
                             related.median_virality, related.median_monetization,
                             related.consistency_score, related.opportunity_score,
                             related.outlier_rate, related.trend_direction
                        FROM category_statistics related
                       WHERE related.period_start = candidate.period_start
                         AND related.period_end = candidate.period_end
                         AND related.platform = candidate.platform
                         AND related.region IS NOT DISTINCT FROM candidate.region
                         AND related.language IS NOT DISTINCT FROM candidate.language
                         AND related.calculation_version = candidate.calculation_version
                         AND related.dimension_type = 'category_format_source'
                         AND related.category_slug = candidate.category_slug
                       ORDER BY related.opportunity_score DESC NULLS LAST, related.sample_size DESC
                       LIMIT config.context_limit
                  ) pattern
            ), '[]'::JSONB),
            'context_top_formats', COALESCE((
                SELECT jsonb_agg(to_jsonb(format_statistic) ORDER BY format_statistic.opportunity_score DESC NULLS LAST, format_statistic.sample_size DESC)
                  FROM (
                      SELECT related.dimension_value AS format, related.sample_size,
                             related.median_virality, related.median_monetization,
                             related.consistency_score, related.opportunity_score,
                             related.outlier_rate, related.trend_direction
                        FROM category_statistics related
                       WHERE related.period_start = candidate.period_start
                         AND related.period_end = candidate.period_end
                         AND related.platform = candidate.platform
                         AND related.region IS NOT DISTINCT FROM candidate.region
                         AND related.language IS NOT DISTINCT FROM candidate.language
                         AND related.calculation_version = candidate.calculation_version
                         AND related.dimension_type = 'format'
                       ORDER BY related.opportunity_score DESC NULLS LAST, related.sample_size DESC
                       LIMIT config.context_limit
                  ) format_statistic
            ), '[]'::JSONB),
            'context_top_hooks', COALESCE((
                SELECT jsonb_agg(to_jsonb(hook_statistic) ORDER BY hook_statistic.opportunity_score DESC NULLS LAST, hook_statistic.sample_size DESC)
                  FROM (
                      SELECT related.dimension_value AS hook_type, related.sample_size,
                             related.median_virality, related.median_monetization,
                             related.consistency_score, related.opportunity_score,
                             related.outlier_rate, related.trend_direction
                        FROM category_statistics related
                       WHERE related.period_start = candidate.period_start
                         AND related.period_end = candidate.period_end
                         AND related.platform = candidate.platform
                         AND related.region IS NOT DISTINCT FROM candidate.region
                         AND related.language IS NOT DISTINCT FROM candidate.language
                         AND related.calculation_version = candidate.calculation_version
                         AND related.dimension_type = 'hook_type'
                       ORDER BY related.opportunity_score DESC NULLS LAST, related.sample_size DESC
                       LIMIT config.context_limit
                  ) hook_statistic
            ), '[]'::JSONB)
        ) AS evidence_json
      FROM category_candidates candidate
      CROSS JOIN config
), hashed AS (
    SELECT evidenced.*, md5(evidenced.evidence_json::TEXT) AS evidence_hash
      FROM evidenced
), pending AS (
    SELECT hashed.*
      FROM hashed
     WHERE NOT EXISTS (
         SELECT 1
           FROM recommendations recommendation
          WHERE recommendation.category = hashed.category_slug
            AND recommendation.period_start = hashed.period_start
            AND recommendation.period_end = hashed.period_end
            AND recommendation.platform = hashed.platform
            AND recommendation.region IS NOT DISTINCT FROM hashed.region
            AND recommendation.language IS NOT DISTINCT FROM hashed.language
            AND recommendation.prompt_version = hashed.prompt_version
            AND recommendation.model = hashed.recommendation_model
            AND recommendation.evidence_hash = hashed.evidence_hash
     )
)
SELECT
    pending.category_slug,
    pending.period_start,
    pending.period_end,
    pending.platform,
    pending.region,
    pending.language,
    pending.opportunity_score,
    pending.median_virality,
    pending.median_monetization,
    pending.consistency_score,
    pending.calculation_version,
    pending.opportunity_calculation_version,
    pending.recommendation_model,
    pending.prompt_version,
    pending.evidence_json,
    pending.evidence_hash
 FROM pending
 ORDER BY pending.opportunity_score DESC, pending.opportunity_rank, pending.category_slug
 LIMIT (SELECT max_categories FROM config);
$$;

COMMIT;
