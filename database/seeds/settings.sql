BEGIN;

INSERT INTO settings (key, value, description)
VALUES
    ('REGION', '"BR"'::JSONB, 'Região principal utilizada na coleta e nas comparações.'),
    ('LANGUAGE', '"pt"'::JSONB, 'Idioma principal utilizado na coleta e classificação.'),
    ('COLLECTION_WINDOW_HOURS', '168'::JSONB, 'Janela inicial de coleta, em horas.'),
    ('MAX_RESULTS_PER_QUERY', '25'::JSONB, 'Limite inicial de resultados por query e grupo amostral.'),
    ('MAX_QUERIES_PER_RUN', '4'::JSONB, 'Quantidade máxima de combinações query e grupo processadas por execução.'),
    ('SHORT_MAX_DURATION', '180'::JSONB, 'Duração máxima, em segundos, para priorizar candidatos a Shorts.'),
    ('SNAPSHOT_ACTIVE_DAYS', '7'::JSONB, 'Quantidade inicial de dias de acompanhamento ativo.'),
    ('SNAPSHOT_RECENT_MAX_AGE_HOURS', '24'::JSONB, 'Limite de idade, em horas, da faixa de acompanhamento frequente.'),
    ('SNAPSHOT_INTERMEDIATE_MAX_AGE_HOURS', '72'::JSONB, 'Limite de idade, em horas, da faixa de acompanhamento intermediário.'),
    ('SNAPSHOT_RECENT_INTERVAL_MINUTES', '60'::JSONB, 'Intervalo mínimo, em minutos, entre snapshots de vídeos com até 24 horas.'),
    ('SNAPSHOT_INTERMEDIATE_INTERVAL_MINUTES', '360'::JSONB, 'Intervalo mínimo, em minutos, entre snapshots de vídeos com 1 a 3 dias.'),
    ('SNAPSHOT_OLDER_INTERVAL_MINUTES', '1440'::JSONB, 'Intervalo mínimo, em minutos, entre snapshots de vídeos com 3 a 7 dias.'),
    ('SNAPSHOT_MAX_VIDEOS_PER_RUN', '200'::JSONB, 'Quantidade máxima de vídeos atualizados por execução do Snapshot Tracker.'),
    ('COMMENT_WEIGHT', '3'::JSONB, 'Peso heurístico inicial dos comentários no Engagement Rate.'),
    ('LLM_MODEL', 'null'::JSONB, 'Modelo a ser definido antes da Fase 4, sem armazenar credenciais.'),
    ('MIN_SAMPLE_SIZE', '30'::JSONB, 'Amostra mínima inicial para estatísticas agregadas.'),
    ('REPORT_PERIOD', '"7 days"'::JSONB, 'Período padrão dos relatórios agregados.'),
    ('YOUTUBE_QUOTA_BUDGET_PER_RUN', '1000'::JSONB, 'Orçamento máximo estimado para operações do bucket geral por execução.'),
    ('YOUTUBE_SEARCH_DAILY_CALL_LIMIT', '100'::JSONB, 'Limite diário configurável do bucket separado de search.list.'),
    ('YOUTUBE_SEARCH_QUOTA_COST', '1'::JSONB, 'Custo configurável de uma chamada search.list em seu bucket separado.'),
    ('YOUTUBE_VIDEOS_LIST_QUOTA_COST', '1'::JSONB, 'Custo configurável estimado de uma chamada videos.list.')
ON CONFLICT (key) DO UPDATE
SET
    value = EXCLUDED.value,
    description = EXCLUDED.description;

COMMIT;
