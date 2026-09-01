# Graph Report - TrendLens  (2026-09-01)

## Corpus Check
- 71 files · ~87,204 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 184 nodes · 222 edges · 43 communities (38 shown, 5 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 7 edges (avg confidence: 0.88)
- Token cost: 0 input · 0 output

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
- Community 12
- Community 15
- Community 18
- Community 19

## God Nodes (most connected - your core abstractions)
1. `videos` - 24 edges
2. `settings` - 20 edges
3. `build_phase12_validation()` - 15 edges
4. `refresh_category_statistics()` - 14 edges
5. `video_collection_matches` - 11 edges
6. `categories` - 11 edges
7. `persist_snapshot_batch()` - 10 edges
8. `collection_queries` - 10 edges
9. `build_pipeline_observability()` - 9 edges
10. `video_snapshots` - 8 edges

## Surprising Connections (you probably didn't know these)
- `General Project Context` --semantically_similar_to--> `TrendLens Platform`  [INFERRED] [semantically similar]
  docs/contexto-geral.md → README.md
- `Local Docker Stack` --implements--> `System Architecture`  [INFERRED]
  compose.yaml → docs/architecture.md
- `Infrastructure Docker Stack` --implements--> `System Architecture`  [INFERRED]
  infra/compose.yaml → docs/architecture.md
- `Scoring Reference` --semantically_similar_to--> `Scoring Methodology`  [INFERRED] [semantically similar]
  docs/scoring.md → docs/methodology.md
- `Analytical Pipeline Workflows` --references--> `Workflow Catalog`  [INFERRED]
  docs/architecture.md → workflows/README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Scoring Pipeline Scores** — docs_methodology_virality_score, docs_methodology_monetization_score, docs_methodology_opportunity_score [EXTRACTED 1.00]
- **Validation Readiness Evidence** — docs_validation_phase12_validation, docs_validation_calibration_readiness, docs_methodology_scoring_methodology [EXTRACTED 1.00]

## Communities (43 total, 5 thin omitted)

### Community 1 - "Community 1"
Cohesion: 0.14
Nodes (23): category_rows, pipeline_runs, video_collection_matches, select_classification_candidates(), video_classifications, build_phase12_validation(), classification_validation_reviews, pipeline_validation_reports (+15 more)

### Community 2 - "Community 2"
Cohesion: 0.12
Nodes (12): refresh_opportunity_rankings(), category_statistics, select_snapshot_candidates(), snapshot_backoff_minutes(), video_snapshot_tracking_state, video_snapshot_tracking_state_set_updated_at, persist_language_detection(), record_language_detection_failure() (+4 more)

### Community 3 - "Community 3"
Cohesion: 0.18
Nodes (10): compared, consistency_components, refresh_category_statistics(), video_classifications, video_metrics, video_monetization_scores, derived_aggregates, final_statistics (+2 more)

### Community 4 - "Community 4"
Cohesion: 0.20
Nodes (10): persist_snapshot_batch(), pipeline_runs, error_insert, external_id, failed_items, failed_state_upsert, matched, returned (+2 more)

### Community 5 - "Community 5"
Cohesion: 0.28
Nodes (9): Local Docker Stack, Analytical Pipeline Workflows, System Architecture, General Project Context, Data Model, Language Eligibility, Infrastructure Docker Stack, TrendLens Platform (+1 more)

### Community 6 - "Community 6"
Cohesion: 0.28
Nodes (6): record_classification_failure(), select_classification_candidates(), select_classification_failure_review_candidates(), pipeline_errors, video_classifications, video_classification_processing_state

### Community 7 - "Community 7"
Cohesion: 0.33
Nodes (9): Current Project Context, Product Limitations, Monetization Score, Opportunity Score, Scoring Methodology, Virality Score, Scoring Reference, Calibration Readiness Gates (+1 more)

### Community 8 - "Community 8"
Cohesion: 0.25
Nodes (7): build_pipeline_observability(), pipeline_observability_reports, category_statistics, pipeline_errors, pipeline_runs, video_classifications, video_metrics

### Community 9 - "Community 9"
Cohesion: 0.29
Nodes (5): select_snapshot_candidates(), refresh_video_metrics(), video_classifications, video_metrics, video_snapshots

### Community 11 - "Community 11"
Cohesion: 0.40
Nodes (4): refresh_video_monetization_scores(), video_classifications, video_metrics, video_monetization_scores

### Community 12 - "Community 12"
Cohesion: 0.40
Nodes (4): build_trendlens_report(), reports, category_statistics, recommendations

## Knowledge Gaps
- **11 isolated node(s):** `reports`, `pipeline_observability_reports`, `pipeline_validation_reports`, `Graphify Instructions`, `Local Docker Stack` (+6 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `settings` connect `Community 2` to `Community 0`, `Community 1`, `Community 3`, `Community 6`, `Community 8`, `Community 9`, `Community 11`, `Community 12`?**
  _High betweenness centrality (0.170) - this node is a cross-community bridge._
- **Why does `videos` connect `Community 1` to `Community 0`, `Community 2`, `Community 3`, `Community 6`, `Community 8`, `Community 9`, `Community 11`?**
  _High betweenness centrality (0.163) - this node is a cross-community bridge._
- **Why does `refresh_category_statistics()` connect `Community 3` to `Community 1`, `Community 2`, `Community 9`?**
  _High betweenness centrality (0.075) - this node is a cross-community bridge._
- **What connects `reports`, `pipeline_observability_reports`, `pipeline_validation_reports` to the rest of the system?**
  _11 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.07407407407407407 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.14245014245014245 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.12280701754385964 - nodes in this community are weakly interconnected._