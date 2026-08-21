BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('SNAPSHOT_RECENT_MAX_AGE_HOURS', '24'::JSONB, 'Limite de idade, em horas, da faixa de acompanhamento frequente.'),
    ('SNAPSHOT_INTERMEDIATE_MAX_AGE_HOURS', '72'::JSONB, 'Limite de idade, em horas, da faixa de acompanhamento intermediário.'),
    ('SNAPSHOT_RECENT_INTERVAL_MINUTES', '60'::JSONB, 'Intervalo mínimo, em minutos, entre snapshots de vídeos com até 24 horas.'),
    ('SNAPSHOT_INTERMEDIATE_INTERVAL_MINUTES', '360'::JSONB, 'Intervalo mínimo, em minutos, entre snapshots de vídeos com 1 a 3 dias.'),
    ('SNAPSHOT_OLDER_INTERVAL_MINUTES', '1440'::JSONB, 'Intervalo mínimo, em minutos, entre snapshots de vídeos com 3 a 7 dias.'),
    ('SNAPSHOT_MAX_VIDEOS_PER_RUN', '200'::JSONB, 'Quantidade máxima de vídeos atualizados por execução do Snapshot Tracker.')
ON CONFLICT (key) DO NOTHING;

CREATE INDEX IF NOT EXISTS videos_youtube_snapshot_tracking_idx
    ON videos (published_at DESC, id)
    WHERE platform = 'youtube';

CREATE OR REPLACE FUNCTION select_snapshot_candidates(
    p_as_of TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    p_limit INTEGER DEFAULT NULL
)
RETURNS TABLE (
    video_id BIGINT,
    external_id TEXT,
    published_at TIMESTAMPTZ,
    last_collected_at TIMESTAMPTZ,
    age_bucket TEXT,
    due_interval_minutes INTEGER
)
LANGUAGE sql
STABLE
AS $$
WITH config_values AS (
    SELECT jsonb_object_agg(key, value) AS values
      FROM settings
     WHERE key = ANY (ARRAY[
        'SNAPSHOT_ACTIVE_DAYS',
        'SNAPSHOT_RECENT_MAX_AGE_HOURS',
        'SNAPSHOT_INTERMEDIATE_MAX_AGE_HOURS',
        'SNAPSHOT_RECENT_INTERVAL_MINUTES',
        'SNAPSHOT_INTERMEDIATE_INTERVAL_MINUTES',
        'SNAPSHOT_OLDER_INTERVAL_MINUTES'
     ])
),
configured AS (
    SELECT
        (values ->> 'SNAPSHOT_ACTIVE_DAYS')::integer AS active_days,
        (values ->> 'SNAPSHOT_RECENT_MAX_AGE_HOURS')::integer AS recent_max_age_hours,
        (values ->> 'SNAPSHOT_INTERMEDIATE_MAX_AGE_HOURS')::integer AS intermediate_max_age_hours,
        (values ->> 'SNAPSHOT_RECENT_INTERVAL_MINUTES')::integer AS recent_interval_minutes,
        (values ->> 'SNAPSHOT_INTERMEDIATE_INTERVAL_MINUTES')::integer AS intermediate_interval_minutes,
        (values ->> 'SNAPSHOT_OLDER_INTERVAL_MINUTES')::integer AS older_interval_minutes
      FROM config_values
),
bucketed AS (
    SELECT
        v.id AS video_id,
        v.external_id,
        v.published_at,
        latest.collected_at AS last_collected_at,
        CASE
            WHEN v.published_at >= p_as_of - make_interval(hours => configured.recent_max_age_hours)
                THEN 'recent'
            WHEN v.published_at >= p_as_of - make_interval(hours => configured.intermediate_max_age_hours)
                THEN 'intermediate'
            ELSE 'older'
        END AS age_bucket,
        CASE
            WHEN v.published_at >= p_as_of - make_interval(hours => configured.recent_max_age_hours)
                THEN configured.recent_interval_minutes
            WHEN v.published_at >= p_as_of - make_interval(hours => configured.intermediate_max_age_hours)
                THEN configured.intermediate_interval_minutes
            ELSE configured.older_interval_minutes
        END AS due_interval_minutes
      FROM videos v
      CROSS JOIN configured
      JOIN LATERAL (
          SELECT s.collected_at
            FROM video_snapshots s
           WHERE s.video_id = v.id
           ORDER BY s.collected_at DESC
           LIMIT 1
      ) latest ON TRUE
     WHERE v.platform = 'youtube'
       AND v.published_at <= p_as_of
       AND v.published_at >= p_as_of - make_interval(days => configured.active_days)
)
SELECT
    bucketed.video_id,
    bucketed.external_id,
    bucketed.published_at,
    bucketed.last_collected_at,
    bucketed.age_bucket,
    bucketed.due_interval_minutes
  FROM bucketed
 WHERE bucketed.last_collected_at <= p_as_of - make_interval(mins => bucketed.due_interval_minutes)
 ORDER BY bucketed.last_collected_at, bucketed.published_at, bucketed.video_id
 LIMIT p_limit;
$$;

COMMIT;
