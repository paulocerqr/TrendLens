BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('REGION', '"BR"'::JSONB, 'Região principal utilizada na coleta e nas comparações.'),
    ('LANGUAGE', '"pt"'::JSONB, 'Idioma principal utilizado na coleta e classificação.'),
    ('COLLECTION_WINDOW_HOURS', '168'::JSONB, 'Janela inicial de coleta, em horas.'),
    ('MAX_RESULTS_PER_QUERY', '25'::JSONB, 'Limite inicial de resultados por query e grupo amostral.'),
    ('SHORT_MAX_DURATION', '180'::JSONB, 'Duração máxima, em segundos, para priorizar candidatos a Shorts.'),
    ('SNAPSHOT_ACTIVE_DAYS', '7'::JSONB, 'Quantidade inicial de dias de acompanhamento ativo.'),
    ('COMMENT_WEIGHT', '3'::JSONB, 'Peso heurístico inicial dos comentários no Engagement Rate.'),
    ('LLM_MODEL', 'null'::JSONB, 'Modelo a ser definido antes da Fase 4, sem armazenar credenciais.'),
    ('MIN_SAMPLE_SIZE', '30'::JSONB, 'Amostra mínima inicial para estatísticas agregadas.'),
    ('REPORT_PERIOD', '"7 days"'::JSONB, 'Período padrão dos relatórios agregados.')
ON CONFLICT (key) DO UPDATE
SET
    value = EXCLUDED.value,
    description = EXCLUDED.description;

COMMIT;
