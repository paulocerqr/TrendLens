BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS collection_queries_identity_idx
    ON collection_queries (
        lower(query_text),
        sample_group,
        language,
        region
    );

CREATE INDEX IF NOT EXISTS collection_queries_active_priority_idx
    ON collection_queries (is_active, priority, id)
    WHERE is_active;

CREATE INDEX IF NOT EXISTS collection_queries_collection_schedule_idx
    ON collection_queries (last_collected_at ASC NULLS FIRST, priority, id)
    WHERE is_active;

CREATE INDEX IF NOT EXISTS videos_published_at_idx
    ON videos (published_at DESC);

CREATE INDEX IF NOT EXISTS videos_channel_published_idx
    ON videos (platform, channel_id, published_at DESC);

CREATE INDEX IF NOT EXISTS videos_candidate_filter_idx
    ON videos (platform, region, language, short_confidence, published_at DESC);

CREATE INDEX IF NOT EXISTS videos_youtube_snapshot_tracking_idx
    ON videos (published_at DESC, id)
    WHERE platform = 'youtube';

CREATE INDEX IF NOT EXISTS video_snapshots_video_collected_idx
    ON video_snapshots (video_id, collected_at DESC);

CREATE INDEX IF NOT EXISTS video_snapshots_collected_at_idx
    ON video_snapshots (collected_at DESC);

CREATE INDEX IF NOT EXISTS video_classifications_dimensions_idx
    ON video_classifications (
        category_id,
        topic,
        content_type,
        format,
        source_type
    );

CREATE INDEX IF NOT EXISTS video_classifications_classified_at_idx
    ON video_classifications (classified_at DESC);

CREATE INDEX IF NOT EXISTS video_metrics_video_calculated_idx
    ON video_metrics (video_id, calculated_at DESC);

CREATE INDEX IF NOT EXISTS video_metrics_calculation_version_idx
    ON video_metrics (calculation_version, calculated_at DESC);

CREATE INDEX IF NOT EXISTS video_metrics_virality_idx
    ON video_metrics (virality_score DESC)
    WHERE virality_score IS NOT NULL;

CREATE INDEX IF NOT EXISTS video_monetization_scores_rank_idx
    ON video_monetization_scores (monetization_score DESC, calculated_at DESC);

CREATE INDEX IF NOT EXISTS video_monetization_scores_version_idx
    ON video_monetization_scores (calculation_version, calculated_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS category_statistics_dimensions_period_idx
    ON category_statistics (
        period_start,
        period_end,
        platform,
        region,
        language,
        topic,
        content_type,
        format,
        hook_type,
        source_type
    )
    NULLS NOT DISTINCT;

CREATE INDEX IF NOT EXISTS category_statistics_opportunity_idx
    ON category_statistics (period_end DESC, opportunity_score DESC)
    WHERE opportunity_score IS NOT NULL;

CREATE INDEX IF NOT EXISTS recommendations_generated_idx
    ON recommendations (generated_at DESC);

CREATE INDEX IF NOT EXISTS recommendations_category_score_idx
    ON recommendations (category, opportunity_score DESC, generated_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_runs_workflow_started_idx
    ON pipeline_runs (workflow, started_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_runs_status_started_idx
    ON pipeline_runs (status, started_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_errors_workflow_occurred_idx
    ON pipeline_errors (workflow, occurred_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_errors_run_idx
    ON pipeline_errors (pipeline_run_id, occurred_at DESC)
    WHERE pipeline_run_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS video_collection_matches_query_idx
    ON video_collection_matches (collection_query_id, matched_at DESC);

CREATE INDEX IF NOT EXISTS video_collection_matches_video_idx
    ON video_collection_matches (video_id, matched_at DESC);

COMMIT;
