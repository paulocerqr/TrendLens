BEGIN;

CREATE OR REPLACE FUNCTION canonicalize_analytical_language(p_language TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
WITH normalized AS (
    SELECT normalize_language_code(p_language) AS language_code
)
SELECT CASE
    WHEN language_code IS NULL THEN NULL
    WHEN split_part(language_code, '-', 1) = 'pt' THEN 'pt'
    ELSE language_code
END
FROM normalized;
$$;

CREATE OR REPLACE FUNCTION canonicalize_video_analytical_language()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.language := canonicalize_analytical_language(NEW.language);
    RETURN NEW;
END;
$$;

UPDATE videos
   SET language = 'pt'
 WHERE (
        split_part(normalize_language_code(language), '-', 1) = 'pt'
        OR split_part(normalize_language_code(detected_language), '-', 1) = 'pt'
   )
   AND language IS DISTINCT FROM 'pt';

DROP TRIGGER IF EXISTS videos_canonicalize_analytical_language ON videos;

CREATE TRIGGER videos_canonicalize_analytical_language
BEFORE INSERT OR UPDATE OF language ON videos
FOR EACH ROW
EXECUTE FUNCTION canonicalize_video_analytical_language();

ALTER TABLE videos
    DROP CONSTRAINT IF EXISTS videos_portuguese_language_canonical_check;

ALTER TABLE videos
    ADD CONSTRAINT videos_portuguese_language_canonical_check
    CHECK (
        language IS NULL
        OR split_part(normalize_language_code(language), '-', 1) <> 'pt'
        OR language = 'pt'
    );

UPDATE settings
   SET value = '"v3-language-canonical"'::JSONB,
       description = 'Versão das agregações com português canônico em language e variantes preservadas em detected_language.'
 WHERE key = 'TREND_CALCULATION_VERSION';

UPDATE settings
   SET value = '"v3-language-canonical"'::JSONB,
       description = 'Versão do ranking calculado sobre agregações com português analítico canônico.'
 WHERE key = 'OPPORTUNITY_CALCULATION_VERSION';

COMMIT;
