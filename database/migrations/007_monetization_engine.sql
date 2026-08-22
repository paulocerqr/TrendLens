BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('MONETIZATION_MAX_VIDEOS_PER_RUN', '1000'::JSONB, 'Quantidade máxima de classificações recalculadas por execução do Monetization Engine.'),
    ('MONETIZATION_CALCULATION_VERSION', '"v1"'::JSONB, 'Versão das fórmulas e dos critérios heurísticos do Monetization Score.'),
    ('MONETIZATION_ORIGINALITY_WEIGHT', '0.30'::JSONB, 'Peso inicial da originalidade na base positiva do Monetization Score.'),
    ('MONETIZATION_POLICY_WEIGHT', '0.25'::JSONB, 'Peso inicial da elegibilidade de política na base positiva do Monetization Score.'),
    ('MONETIZATION_ADVERTISER_WEIGHT', '0.15'::JSONB, 'Peso inicial da adequação a anunciantes na base positiva do Monetization Score.'),
    ('MONETIZATION_PRODUCTION_WEIGHT', '0.15'::JSONB, 'Peso inicial da viabilidade de produção na base positiva do Monetization Score.'),
    ('MONETIZATION_ENGAGEMENT_WEIGHT', '0.15'::JSONB, 'Peso inicial da qualidade de engajamento na base positiva do Monetization Score.'),
    ('MONETIZATION_COPYRIGHT_RISK_WEIGHT', '0.60'::JSONB, 'Peso inicial do risco autoral na penalidade do Monetization Score.'),
    ('MONETIZATION_REUSED_RISK_WEIGHT', '0.40'::JSONB, 'Peso inicial do risco de conteúdo reutilizado na penalidade do Monetization Score.'),
    ('MONETIZATION_PRODUCTION_DURATION_WEIGHT', '0.30'::JSONB, 'Participação da duração observada no fator de viabilidade de produção.'),
    ('MONETIZATION_HIGH_RISK_THRESHOLD', '0.70'::JSONB, 'Limite inicial do risco combinado usado apenas para observabilidade.'),
    ('MONETIZATION_POLICY_SOURCE_SCORES', '{"original":1.0,"user_generated":0.9,"stock_media":0.8,"gameplay":0.75,"reaction":0.65,"podcast_clip":0.45,"third_party_content":0.35,"compilation":0.25,"movie_or_tv_clip":0.15,"unknown":0.5}'::JSONB, 'Mapa configurável de elegibilidade heurística por source_type.'),
    ('MONETIZATION_ADVERTISER_FORMAT_SCORES', '{"tutorial":0.95,"explainer":0.9,"curiosity":0.85,"comparison":0.85,"ranking":0.8,"storytelling":0.8,"motivation":0.85,"commentary":0.75,"news":0.65,"reaction":0.65,"meme":0.6,"clip":0.55,"compilation":0.55,"unknown":0.5}'::JSONB, 'Mapa configurável de adequação publicitária por formato inferido.'),
    ('MONETIZATION_PRODUCTION_FORMAT_SCORES', '{"clip":0.95,"meme":0.9,"reaction":0.85,"compilation":0.85,"ranking":0.8,"curiosity":0.75,"motivation":0.75,"commentary":0.7,"comparison":0.7,"news":0.7,"explainer":0.65,"storytelling":0.65,"tutorial":0.6,"unknown":0.5}'::JSONB, 'Mapa configurável de viabilidade de produção por formato inferido.')
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

ALTER TABLE video_monetization_scores
    ALTER COLUMN engagement_quality DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS positive_base NUMERIC(5, 4),
    ADD COLUMN IF NOT EXISTS combined_risk NUMERIC(5, 4);

UPDATE video_monetization_scores
   SET positive_base = round(
           0.30 * originality
         + 0.25 * policy_eligibility
         + 0.15 * advertiser_suitability
         + 0.15 * production_feasibility
         + 0.15 * engagement_quality,
           4
       )
 WHERE positive_base IS NULL;

UPDATE video_monetization_scores
   SET combined_risk = round(
           0.60 * copyright_risk
         + 0.40 * reused_content_risk,
           4
       )
 WHERE combined_risk IS NULL;

ALTER TABLE video_monetization_scores
    ALTER COLUMN positive_base SET NOT NULL,
    ALTER COLUMN combined_risk SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'video_monetization_scores'::regclass
           AND conname = 'video_monetization_positive_base_check'
    ) THEN
        ALTER TABLE video_monetization_scores
            ADD CONSTRAINT video_monetization_positive_base_check
            CHECK (positive_base BETWEEN 0 AND 1);
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'video_monetization_scores'::regclass
           AND conname = 'video_monetization_combined_risk_check'
    ) THEN
        ALTER TABLE video_monetization_scores
            ADD CONSTRAINT video_monetization_combined_risk_check
            CHECK (combined_risk BETWEEN 0 AND 1);
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'video_monetization_scores'::regclass
           AND conname = 'video_monetization_version_check'
    ) THEN
        ALTER TABLE video_monetization_scores
            ADD CONSTRAINT video_monetization_version_check
            CHECK (length(btrim(calculation_version)) > 0);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS video_monetization_scores_version_idx
    ON video_monetization_scores (calculation_version, calculated_at DESC);

CREATE OR REPLACE FUNCTION refresh_video_monetization_scores(
    p_limit INTEGER,
    p_as_of TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    eligible_classifications BIGINT,
    candidates_selected BIGINT,
    scores_upserted BIGINT,
    engagement_quality_available BIGINT,
    high_risk_scores BIGINT,
    calculation_version TEXT,
    calculated_at TIMESTAMPTZ
)
LANGUAGE sql
VOLATILE
AS $$
WITH config AS (
    SELECT
        COALESCE((SELECT value #>> '{}' FROM settings WHERE key = 'MONETIZATION_CALCULATION_VERSION'), 'v1') AS calculation_version,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_ORIGINALITY_WEIGHT'), 0.30), 0) AS originality_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_POLICY_WEIGHT'), 0.25), 0) AS policy_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_ADVERTISER_WEIGHT'), 0.15), 0) AS advertiser_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_PRODUCTION_WEIGHT'), 0.15), 0) AS production_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_ENGAGEMENT_WEIGHT'), 0.15), 0) AS engagement_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_COPYRIGHT_RISK_WEIGHT'), 0.60), 0) AS copyright_weight,
        GREATEST(COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_REUSED_RISK_WEIGHT'), 0.40), 0) AS reused_weight,
        GREATEST(0::NUMERIC, LEAST(1::NUMERIC, COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_PRODUCTION_DURATION_WEIGHT'), 0.30))) AS duration_weight,
        GREATEST(0::NUMERIC, LEAST(1::NUMERIC, COALESCE((SELECT (value #>> '{}')::NUMERIC FROM settings WHERE key = 'MONETIZATION_HIGH_RISK_THRESHOLD'), 0.70))) AS high_risk_threshold,
        COALESCE(
            (SELECT value FROM settings WHERE key = 'MONETIZATION_POLICY_SOURCE_SCORES'),
            '{"original":1.0,"user_generated":0.9,"stock_media":0.8,"gameplay":0.75,"reaction":0.65,"podcast_clip":0.45,"third_party_content":0.35,"compilation":0.25,"movie_or_tv_clip":0.15,"unknown":0.5}'::JSONB
        ) AS policy_source_scores,
        COALESCE(
            (SELECT value FROM settings WHERE key = 'MONETIZATION_ADVERTISER_FORMAT_SCORES'),
            '{"tutorial":0.95,"explainer":0.9,"curiosity":0.85,"comparison":0.85,"ranking":0.8,"storytelling":0.8,"motivation":0.85,"commentary":0.75,"news":0.65,"reaction":0.65,"meme":0.6,"clip":0.55,"compilation":0.55,"unknown":0.5}'::JSONB
        ) AS advertiser_format_scores,
        COALESCE(
            (SELECT value FROM settings WHERE key = 'MONETIZATION_PRODUCTION_FORMAT_SCORES'),
            '{"clip":0.95,"meme":0.9,"reaction":0.85,"compilation":0.85,"ranking":0.8,"curiosity":0.75,"motivation":0.75,"commentary":0.7,"comparison":0.7,"news":0.7,"explainer":0.65,"storytelling":0.65,"tutorial":0.6,"unknown":0.5}'::JSONB
        ) AS production_format_scores
), classified AS (
    SELECT
        classification.*,
        video.duration_seconds,
        metric.engagement_percentile,
        metric.calculated_at AS metric_calculated_at
      FROM video_classifications classification
      JOIN videos video ON video.id = classification.video_id
      LEFT JOIN LATERAL (
          SELECT
              video_metric.engagement_percentile,
              video_metric.calculated_at
            FROM video_metrics video_metric
           WHERE video_metric.video_id = classification.video_id
             AND video_metric.calculated_at <= p_as_of
           ORDER BY video_metric.calculated_at DESC, video_metric.id DESC
           LIMIT 1
      ) metric ON TRUE
     WHERE classification.classified_at <= p_as_of
), ordered_targets AS (
    SELECT
        classified.video_id,
        row_number() OVER (
            ORDER BY
                (score.id IS NULL) DESC,
                COALESCE(classified.metric_calculated_at, classified.classified_at) DESC,
                classified.video_id
        ) AS target_order
      FROM classified
      CROSS JOIN config
      LEFT JOIN video_monetization_scores score
        ON score.video_id = classified.video_id
       AND score.calculation_version = config.calculation_version
), targets AS (
    SELECT video_id
      FROM ordered_targets
     WHERE target_order <= GREATEST(p_limit, 0)
), mapped AS (
    SELECT
        classified.*,
        config.*,
        GREATEST(
            0::NUMERIC,
            LEAST(
                1::NUMERIC,
                COALESCE(
                    NULLIF(config.policy_source_scores ->> classified.source_type, '')::NUMERIC,
                    NULLIF(config.policy_source_scores ->> 'unknown', '')::NUMERIC,
                    0.5
                )
            )
        ) AS mapped_policy,
        GREATEST(
            0::NUMERIC,
            LEAST(
                1::NUMERIC,
                COALESCE(
                    NULLIF(config.advertiser_format_scores ->> classified.format, '')::NUMERIC,
                    NULLIF(config.advertiser_format_scores ->> 'unknown', '')::NUMERIC,
                    0.5
                )
            )
        ) AS mapped_advertiser,
        GREATEST(
            0::NUMERIC,
            LEAST(
                1::NUMERIC,
                COALESCE(
                    NULLIF(config.production_format_scores ->> classified.format, '')::NUMERIC,
                    NULLIF(config.production_format_scores ->> 'unknown', '')::NUMERIC,
                    0.5
                )
            )
        ) AS mapped_production
      FROM classified
      CROSS JOIN config
), factors AS (
    SELECT
        mapped.*,
        round(mapped.originality_score, 4) AS originality,
        round(0.5 + (mapped.mapped_policy - 0.5) * mapped.ai_confidence, 4) AS policy_eligibility,
        round(0.5 + (mapped.mapped_advertiser - 0.5) * mapped.ai_confidence, 4) AS advertiser_suitability,
        round(
            CASE
                WHEN mapped.duration_seconds IS NULL THEN
                    0.5 + (mapped.mapped_production - 0.5) * mapped.ai_confidence
                ELSE
                    (1 - mapped.duration_weight)
                    * (0.5 + (mapped.mapped_production - 0.5) * mapped.ai_confidence)
                    + mapped.duration_weight
                    * CASE
                        WHEN mapped.duration_seconds <= 60 THEN 1.0
                        WHEN mapped.duration_seconds <= 120 THEN 0.8
                        WHEN mapped.duration_seconds <= 180 THEN 0.6
                        ELSE 0.4
                      END
            END,
            4
        ) AS production_feasibility,
        CASE
            WHEN mapped.engagement_percentile IS NOT NULL
                THEN round(GREATEST(0::NUMERIC, LEAST(1::NUMERIC, mapped.engagement_percentile)), 4)
            ELSE NULL
        END AS engagement_quality
      FROM mapped
), components AS (
    SELECT
        factors.*,
        (factors.originality_weight
         + factors.policy_weight
         + factors.advertiser_weight
         + factors.production_weight
         + CASE WHEN factors.engagement_quality IS NOT NULL THEN factors.engagement_weight ELSE 0 END) AS available_positive_weight,
        (factors.originality * factors.originality_weight
         + factors.policy_eligibility * factors.policy_weight
         + factors.advertiser_suitability * factors.advertiser_weight
         + factors.production_feasibility * factors.production_weight
         + COALESCE(factors.engagement_quality * factors.engagement_weight, 0)) AS weighted_positive,
        (factors.copyright_weight + factors.reused_weight) AS available_risk_weight,
        (factors.copyright_risk * factors.copyright_weight
         + factors.reused_content_risk * factors.reused_weight) AS weighted_risk
      FROM factors
), scored AS (
    SELECT
        components.*,
        CASE
            WHEN components.available_positive_weight > 0
                THEN round(components.weighted_positive / components.available_positive_weight, 4)
            ELSE NULL
        END AS positive_base,
        CASE
            WHEN components.available_risk_weight > 0
                THEN round(components.weighted_risk / components.available_risk_weight, 4)
            ELSE NULL
        END AS combined_risk
      FROM components
), final_scores AS (
    SELECT
        scored.*,
        CASE
            WHEN scored.positive_base IS NOT NULL AND scored.combined_risk IS NOT NULL
                THEN round(10 * scored.positive_base * GREATEST(0::NUMERIC, 1 - scored.combined_risk), 4)
            ELSE NULL
        END AS monetization_score
      FROM scored
), upserted AS (
    INSERT INTO video_monetization_scores (
        video_id,
        originality,
        policy_eligibility,
        advertiser_suitability,
        production_feasibility,
        engagement_quality,
        copyright_risk,
        reused_content_risk,
        positive_base,
        combined_risk,
        monetization_score,
        calculation_version,
        calculated_at
    )
    SELECT
        final_scores.video_id,
        final_scores.originality,
        final_scores.policy_eligibility,
        final_scores.advertiser_suitability,
        final_scores.production_feasibility,
        final_scores.engagement_quality,
        final_scores.copyright_risk,
        final_scores.reused_content_risk,
        final_scores.positive_base,
        final_scores.combined_risk,
        final_scores.monetization_score,
        final_scores.calculation_version,
        p_as_of
      FROM final_scores
      JOIN targets USING (video_id)
     WHERE final_scores.positive_base IS NOT NULL
       AND final_scores.combined_risk IS NOT NULL
       AND final_scores.monetization_score IS NOT NULL
    ON CONFLICT (video_id, calculation_version) DO UPDATE
    SET
        originality = EXCLUDED.originality,
        policy_eligibility = EXCLUDED.policy_eligibility,
        advertiser_suitability = EXCLUDED.advertiser_suitability,
        production_feasibility = EXCLUDED.production_feasibility,
        engagement_quality = EXCLUDED.engagement_quality,
        copyright_risk = EXCLUDED.copyright_risk,
        reused_content_risk = EXCLUDED.reused_content_risk,
        positive_base = EXCLUDED.positive_base,
        combined_risk = EXCLUDED.combined_risk,
        monetization_score = EXCLUDED.monetization_score,
        calculated_at = EXCLUDED.calculated_at
    RETURNING
        engagement_quality,
        combined_risk,
        calculation_version
)
SELECT
    (SELECT count(*) FROM classified) AS eligible_classifications,
    (SELECT count(*) FROM targets) AS candidates_selected,
    (SELECT count(*) FROM upserted) AS scores_upserted,
    (SELECT count(*) FROM upserted WHERE engagement_quality IS NOT NULL) AS engagement_quality_available,
    (SELECT count(*) FROM upserted WHERE combined_risk >= config.high_risk_threshold) AS high_risk_scores,
    config.calculation_version,
    p_as_of AS calculated_at
  FROM config;
$$;

COMMIT;
