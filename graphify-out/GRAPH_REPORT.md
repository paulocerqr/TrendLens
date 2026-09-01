# Graph Report - TrendLens  (2026-08-31)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 165 nodes · 200 edges · 41 communities (10 shown, 4 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e398a191`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 16
- Community 17

## God Nodes (most connected - your core abstractions)
1. `videos` - 24 edges
2. `settings` - 20 edges
3. `build_phase12_validation()` - 15 edges
4. `refresh_category_statistics()` - 14 edges
5. `video_collection_matches` - 11 edges
6. `categories` - 11 edges
7. `collection_queries` - 10 edges
8. `persist_snapshot_batch()` - 10 edges
9. `build_pipeline_observability()` - 9 edges
10. `video_snapshots` - 8 edges

## Surprising Connections (you probably didn't know these)
- `snapshot_backoff_minutes()` --reads_from--> `settings`  [EXTRACTED]
  database/migrations/014_collection_reliability.sql → database/schema.sql
- `record_classification_failure()` --reads_from--> `settings`  [EXTRACTED]
  database/migrations/017_classifier_reliability.sql → database/schema.sql
- `persist_language_detection()` --reads_from--> `videos`  [EXTRACTED]
  database/migrations/015_language_eligibility.sql → database/schema.sql
- `record_language_detection_failure()` --reads_from--> `settings`  [EXTRACTED]
  database/migrations/015_language_eligibility.sql → database/schema.sql
- `persist_language_detection()` --reads_from--> `videos`  [EXTRACTED]
  database/migrations/016_global_language_target.sql → database/schema.sql

## Import Cycles
- None detected.

## Communities (41 total, 4 thin omitted)

### Community 1 - "Community 1"
Cohesion: 0.14
Nodes (8): refresh_opportunity_rankings(), category_statistics, persist_language_detection(), record_language_detection_failure(), persist_language_detection(), reconcile_stale_pipeline_runs(), settings, snapshot_backoff_minutes()

### Community 2 - "Community 2"
Cohesion: 0.25
Nodes (12): pipeline_runs, video_collection_matches, select_classification_candidates(), video_classifications, select_classification_candidates(), select_language_detection_candidates(), video_classifications, select_language_detection_candidates() (+4 more)

### Community 3 - "Community 3"
Cohesion: 0.22
Nodes (11): select_snapshot_candidates(), refresh_video_metrics(), video_classifications, video_metrics, select_snapshot_candidates(), snapshot_backoff_minutes(), video_snapshot_tracking_state, select_snapshot_candidates() (+3 more)

### Community 4 - "Community 4"
Cohesion: 0.21
Nodes (11): category_rows, build_phase12_validation(), classification_validation_reviews, pipeline_validation_reports, select_classification_review_candidates(), category_statistics, pipeline_errors, video_classifications (+3 more)

### Community 5 - "Community 5"
Cohesion: 0.18
Nodes (10): compared, consistency_components, refresh_category_statistics(), video_classifications, video_metrics, video_monetization_scores, derived_aggregates, final_statistics (+2 more)

### Community 6 - "Community 6"
Cohesion: 0.20
Nodes (10): persist_snapshot_batch(), pipeline_runs, error_insert, external_id, failed_items, failed_state_upsert, matched, returned (+2 more)

### Community 7 - "Community 7"
Cohesion: 0.25
Nodes (7): build_pipeline_observability(), pipeline_observability_reports, category_statistics, pipeline_errors, pipeline_runs, video_classifications, video_metrics

### Community 8 - "Community 8"
Cohesion: 0.33
Nodes (4): record_classification_failure(), select_classification_failure_review_candidates(), pipeline_errors, video_classification_processing_state

### Community 10 - "Community 10"
Cohesion: 0.40
Nodes (4): refresh_video_monetization_scores(), video_classifications, video_metrics, video_monetization_scores

### Community 11 - "Community 11"
Cohesion: 0.40
Nodes (4): build_trendlens_report(), reports, category_statistics, recommendations

## Knowledge Gaps
- **3 isolated node(s):** `reports`, `pipeline_validation_reports`, `pipeline_observability_reports`
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 117 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `settings` connect `Community 1` to `Community 0`, `Community 2`, `Community 3`, `Community 4`, `Community 5`, `Community 7`, `Community 8`, `Community 10`, `Community 11`?**
  _High betweenness centrality (0.212) - this node is a cross-community bridge._
- **Why does `videos` connect `Community 3` to `Community 0`, `Community 1`, `Community 2`, `Community 4`, `Community 5`, `Community 7`, `Community 8`, `Community 10`?**
  _High betweenness centrality (0.203) - this node is a cross-community bridge._
- **Why does `refresh_category_statistics()` connect `Community 5` to `Community 1`, `Community 2`, `Community 3`?**
  _High betweenness centrality (0.093) - this node is a cross-community bridge._
- **What connects `reports`, `pipeline_validation_reports`, `pipeline_observability_reports` to the rest of the system?**
  _3 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.07142857142857142 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._