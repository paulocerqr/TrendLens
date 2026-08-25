BEGIN;

INSERT INTO settings (key, value, description)
VALUES (
    'MIN_SAMPLE_SIZE',
    '30'::JSONB,
    'Amostra mínima obrigatória para categorias e padrões agregados enviados ao Recommendation AI.'
)
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

DO $migration$
DECLARE
    definition TEXT;
    patched TEXT;
BEGIN
    SELECT pg_get_functiondef('select_recommendation_candidates(integer)'::REGPROCEDURE)
      INTO definition;
    patched := definition;

    IF position('AS minimum_sample_size' IN patched) = 0 THEN
        patched := replace(
            patched,
            '        GREATEST(1, LEAST(20, COALESCE((SELECT (value #>> ''{}'')::INTEGER FROM settings WHERE key = ''RECOMMENDATION_CONTEXT_LIMIT''), 5))) AS context_limit,' || chr(10),
            '        GREATEST(1, LEAST(20, COALESCE((SELECT (value #>> ''{}'')::INTEGER FROM settings WHERE key = ''RECOMMENDATION_CONTEXT_LIMIT''), 5))) AS context_limit,' || chr(10) ||
            '        GREATEST(1, COALESCE((SELECT (value #>> ''{}'')::INTEGER FROM settings WHERE key = ''MIN_SAMPLE_SIZE''), 30)) AS minimum_sample_size,' || chr(10)
        );
    END IF;

    IF position('AND statistic.sample_size >= config.minimum_sample_size' IN patched) = 0 THEN
        patched := replace(
            patched,
            '       AND statistic.opportunity_score >= config.minimum_score' || chr(10),
            '       AND statistic.opportunity_score >= config.minimum_score' || chr(10) ||
            '       AND statistic.sample_size >= config.minimum_sample_size' || chr(10)
        );
    END IF;

    IF position(
        'AND related.dimension_type = ''category_format_source''' || chr(10) ||
        '                         AND related.sample_size >= config.minimum_sample_size'
        IN patched
    ) = 0 THEN
        patched := replace(
            patched,
            '                         AND related.dimension_type = ''category_format_source''' || chr(10),
            '                         AND related.dimension_type = ''category_format_source''' || chr(10) ||
            '                         AND related.sample_size >= config.minimum_sample_size' || chr(10)
        );
    END IF;

    IF position(
        'AND related.dimension_type = ''format''' || chr(10) ||
        '                         AND related.sample_size >= config.minimum_sample_size'
        IN patched
    ) = 0 THEN
        patched := replace(
            patched,
            '                         AND related.dimension_type = ''format''' || chr(10),
            '                         AND related.dimension_type = ''format''' || chr(10) ||
            '                         AND related.sample_size >= config.minimum_sample_size' || chr(10)
        );
    END IF;

    IF position(
        'AND related.dimension_type = ''hook_type''' || chr(10) ||
        '                         AND related.sample_size >= config.minimum_sample_size'
        IN patched
    ) = 0 THEN
        patched := replace(
            patched,
            '                         AND related.dimension_type = ''hook_type''' || chr(10),
            '                         AND related.dimension_type = ''hook_type''' || chr(10) ||
            '                         AND related.sample_size >= config.minimum_sample_size' || chr(10)
        );
    END IF;

    IF position('AS minimum_sample_size' IN patched) = 0
       OR position('AND statistic.sample_size >= config.minimum_sample_size' IN patched) = 0
       OR position(
           'AND related.dimension_type = ''category_format_source''' || chr(10) ||
           '                         AND related.sample_size >= config.minimum_sample_size'
           IN patched
       ) = 0
       OR position(
           'AND related.dimension_type = ''format''' || chr(10) ||
           '                         AND related.sample_size >= config.minimum_sample_size'
           IN patched
       ) = 0
       OR position(
           'AND related.dimension_type = ''hook_type''' || chr(10) ||
           '                         AND related.sample_size >= config.minimum_sample_size'
           IN patched
       ) = 0 THEN
        RAISE EXCEPTION 'Could not apply Recommendation AI minimum sample policy';
    END IF;

    IF patched <> definition THEN
        EXECUTE patched;
    END IF;
END;
$migration$;

COMMIT;
