BEGIN;

ALTER TABLE collection_queries
    ADD COLUMN IF NOT EXISTS last_collected_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_status TEXT,
    ADD COLUMN IF NOT EXISTS consecutive_failures INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_runs BIGINT NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'collection_queries'::regclass
           AND conname = 'collection_queries_last_status_check'
    ) THEN
        ALTER TABLE collection_queries
            ADD CONSTRAINT collection_queries_last_status_check
            CHECK (last_status IS NULL OR last_status IN ('success', 'partial', 'failed', 'skipped'));
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'collection_queries'::regclass
           AND conname = 'collection_queries_consecutive_failures_check'
    ) THEN
        ALTER TABLE collection_queries
            ADD CONSTRAINT collection_queries_consecutive_failures_check
            CHECK (consecutive_failures >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'collection_queries'::regclass
           AND conname = 'collection_queries_total_runs_check'
    ) THEN
        ALTER TABLE collection_queries
            ADD CONSTRAINT collection_queries_total_runs_check
            CHECK (total_runs >= 0);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS collection_queries_collection_schedule_idx
    ON collection_queries (last_collected_at ASC NULLS FIRST, priority, id)
    WHERE is_active;

COMMIT;
