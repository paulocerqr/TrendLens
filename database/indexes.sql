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

CREATE INDEX IF NOT EXISTS videos_language_gate_queue_idx
    ON videos (language_eligibility, language_retry_after, published_at DESC, id)
    WHERE platform = 'youtube' AND language_eligibility = 'uncertain';

CREATE INDEX IF NOT EXISTS videos_analysis_eligibility_idx
    ON videos (platform, language_eligibility, published_at DESC);

CREATE INDEX IF NOT EXISTS video_snapshots_video_collected_idx
    ON video_snapshots (video_id, collected_at DESC);

CREATE INDEX IF NOT EXISTS video_snapshots_collected_at_idx
    ON video_snapshots (collected_at DESC);

CREATE INDEX IF NOT EXISTS video_snapshot_tracking_retry_idx
    ON video_snapshot_tracking_state (retry_after, video_id)
    WHERE retry_after IS NOT NULL;

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

CREATE INDEX IF NOT EXISTS category_statistics_opportunity_idx
    ON category_statistics (
        period_end DESC,
        dimension_type,
        opportunity_rank,
        opportunity_score DESC
    )
    WHERE opportunity_score IS NOT NULL;

CREATE INDEX IF NOT EXISTS recommendations_generated_idx
    ON recommendations (generated_at DESC);

CREATE INDEX IF NOT EXISTS recommendations_category_score_idx
    ON recommendations (category, opportunity_score DESC, generated_at DESC);

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

CREATE UNIQUE INDEX IF NOT EXISTS reports_source_version_idx
    ON reports (
        period_start,
        period_end,
        platform,
        region,
        language,
        report_version,
        source_calculation_version,
        source_opportunity_version,
        recommendation_prompt_version,
        source_hash
    )
    NULLS NOT DISTINCT;

CREATE INDEX IF NOT EXISTS reports_generated_context_idx
    ON reports (generated_at DESC, platform, region, language);

CREATE UNIQUE INDEX IF NOT EXISTS pipeline_observability_source_idx
    ON pipeline_observability_reports (
        period_start,
        period_end,
        observability_version,
        source_hash
    );

CREATE INDEX IF NOT EXISTS pipeline_observability_generated_idx
    ON pipeline_observability_reports (generated_at DESC, overall_status);

CREATE INDEX IF NOT EXISTS classification_validation_reviewed_idx
    ON classification_validation_reviews (reviewed_at DESC, prompt_version);

CREATE UNIQUE INDEX IF NOT EXISTS pipeline_validation_source_idx
    ON pipeline_validation_reports (
        period_start,
        period_end,
        validation_version,
        source_hash
    );

CREATE INDEX IF NOT EXISTS pipeline_validation_generated_idx
    ON pipeline_validation_reports (generated_at DESC, overall_status);

CREATE INDEX IF NOT EXISTS pipeline_runs_workflow_started_idx
    ON pipeline_runs (workflow, started_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_runs_started_at_idx
    ON pipeline_runs (started_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_runs_status_started_idx
    ON pipeline_runs (status, started_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_errors_workflow_occurred_idx
    ON pipeline_errors (workflow, occurred_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_errors_occurred_at_idx
    ON pipeline_errors (occurred_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_errors_run_idx
    ON pipeline_errors (pipeline_run_id, occurred_at DESC)
    WHERE pipeline_run_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS video_collection_matches_query_idx
    ON video_collection_matches (collection_query_id, matched_at DESC);

CREATE INDEX IF NOT EXISTS video_collection_matches_video_idx
    ON video_collection_matches (video_id, matched_at DESC);

COMMIT;
