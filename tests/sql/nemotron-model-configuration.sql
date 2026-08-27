\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    expected_model CONSTANT TEXT := 'nvidia/nemotron-3-ultra-550b-a55b';
    configured_count INTEGER;
BEGIN
    SELECT count(*)
      INTO configured_count
      FROM settings
     WHERE key IN ('LLM_MODEL', 'LANGUAGE_GATE_MODEL', 'RECOMMENDATION_MODEL')
       AND value #>> '{}' = expected_model;

    IF configured_count <> 3 THEN
        RAISE EXCEPTION
            'Expected all three NVIDIA model settings to use %, found %',
            expected_model,
            configured_count;
    END IF;
END;
$$;

ROLLBACK;

SELECT 'Nemotron model configuration SQL validation passed' AS result;
