\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    brazilian_video BIGINT;
    european_video BIGINT;
    manual_video BIGINT;
BEGIN
    IF to_regprocedure('canonicalize_analytical_language(text)') IS NULL THEN
        RAISE EXCEPTION 'Analytical language canonicalization function is missing';
    END IF;

    IF canonicalize_analytical_language('pt-BR') <> 'pt'
       OR canonicalize_analytical_language('pt_PT') <> 'pt'
       OR canonicalize_analytical_language('pt') <> 'pt'
       OR canonicalize_analytical_language('en-US') <> 'en-us'
       OR canonicalize_analytical_language(NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'Analytical language canonicalization returned an unexpected value';
    END IF;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, language, target_language, detected_language,
        language_eligibility, region, short_confidence
    ) VALUES (
        'youtube', '__analytical_pt_br', '__analytical_channel', 'Conteúdo brasileiro',
        'https://example.test/__analytical_pt_br', '2100-03-01 00:00:00+00',
        40, 'pt-BR', 'pt', 'pt-br', 'eligible', 'BR', 'medium'
    ) RETURNING id INTO brazilian_video;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, language, target_language, detected_language,
        language_eligibility, region, short_confidence
    ) VALUES (
        'youtube', '__analytical_pt_pt', '__analytical_channel', 'Conteúdo europeu',
        'https://example.test/__analytical_pt_pt', '2100-03-02 00:00:00+00',
        40, 'pt-PT', 'pt', 'pt-pt', 'eligible', 'BR', 'medium'
    ) RETURNING id INTO european_video;

    INSERT INTO videos (
        platform, external_id, channel_id, title, url, published_at,
        duration_seconds, target_language, language_eligibility, region, short_confidence
    ) VALUES (
        'youtube', '__analytical_manual', '__analytical_channel', 'Revisão manual',
        'https://example.test/__analytical_manual', '2100-03-03 00:00:00+00',
        40, 'pt', 'uncertain', 'BR', 'medium'
    ) RETURNING id INTO manual_video;

    PERFORM * FROM persist_language_detection(
        manual_video, 'pt-PT', 0.95, 'llm_metadata', '2100-03-04 00:00:00+00'
    );

    IF EXISTS (
        SELECT 1
          FROM videos
         WHERE id IN (brazilian_video, european_video, manual_video)
           AND (
               language IS DISTINCT FROM 'pt'
               OR region IS DISTINCT FROM 'BR'
           )
    ) THEN
        RAISE EXCEPTION 'Portuguese analytical language or BR region was not preserved correctly';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM videos
         WHERE id = brazilian_video
           AND detected_language = 'pt-br'
           AND language = 'pt'
           AND region = 'BR'
    ) OR NOT EXISTS (
        SELECT 1 FROM videos
         WHERE id = european_video
           AND detected_language = 'pt-pt'
           AND language = 'pt'
           AND region = 'BR'
    ) OR NOT EXISTS (
        SELECT 1 FROM videos
         WHERE id = manual_video
           AND detected_language = 'pt-pt'
           AND language = 'pt'
           AND language_eligibility = 'eligible'
           AND region = 'BR'
    ) THEN
        RAISE EXCEPTION 'Detected language variants were not preserved separately from analytical language';
    END IF;

    IF (SELECT value #>> '{}' FROM settings WHERE key = 'TREND_CALCULATION_VERSION') <> 'v3-language-canonical'
       OR (SELECT value #>> '{}' FROM settings WHERE key = 'OPPORTUNITY_CALCULATION_VERSION') <> 'v3-language-canonical' THEN
        RAISE EXCEPTION 'Analytical calculation versions were not advanced';
    END IF;
END;
$$;

ROLLBACK;

SELECT 'Analytical language normalization SQL validation passed' AS result;
