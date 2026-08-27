BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    (
        'LLM_MODEL',
        '"nvidia/nemotron-3-ultra-550b-a55b"'::JSONB,
        'Modelo NVIDIA NIM utilizado pelo classificador, sem armazenar credenciais.'
    ),
    (
        'LANGUAGE_GATE_MODEL',
        '"nvidia/nemotron-3-ultra-550b-a55b"'::JSONB,
        'Modelo NVIDIA NIM usado somente para detectar idioma a partir de metadados públicos.'
    ),
    (
        'RECOMMENDATION_MODEL',
        '"nvidia/nemotron-3-ultra-550b-a55b"'::JSONB,
        'Modelo NVIDIA NIM utilizado pelo Recommendation Engine, sem armazenar credenciais.'
    )
ON CONFLICT (key) DO UPDATE
SET
    value = EXCLUDED.value,
    description = EXCLUDED.description;

COMMIT;
