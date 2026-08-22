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
    ('LLM_MODEL', '"nvidia/llama-3.3-nemotron-super-49b-v1"'::JSONB, 'Modelo NVIDIA NIM utilizado inicialmente pelo classificador, sem armazenar credenciais.'),
    ('CLASSIFIER_MAX_VIDEOS_PER_RUN', '5'::JSONB, 'Quantidade máxima de vídeos classificados por execução.'),
    ('CLASSIFIER_DESCRIPTION_MAX_CHARS', '2000'::JSONB, 'Quantidade máxima de caracteres da descrição enviada ao classificador.'),
    ('CLASSIFIER_PROMPT_VERSION', '"v1"'::JSONB, 'Versão do prompt estruturado utilizado pelo classificador.'),
    ('METRICS_MAX_VIDEOS_PER_RUN', '1000'::JSONB, 'Quantidade máxima de vídeos cujas métricas atuais são recalculadas por execução.'),
    ('METRICS_ANALYSIS_WINDOW_DAYS', '7'::JSONB, 'Janela, em dias, usada para selecionar vídeos e formar coortes comparáveis.'),
    ('METRICS_CHANNEL_BASELINE_WINDOW_DAYS', '30'::JSONB, 'Janela recente, em dias, usada no baseline de visualizações do canal.'),
    ('METRICS_CHANNEL_BASELINE_MIN_VIDEOS', '3'::JSONB, 'Quantidade mínima de outros vídeos necessária para calcular o baseline do canal.'),
    ('METRICS_FRESHNESS_HORIZON_HOURS', '168'::JSONB, 'Horizonte, em horas, no qual o Freshness Score decai linearmente de 1 para 0.'),
    ('METRICS_MIN_VIRALITY_COMPONENTS', '3'::JSONB, 'Quantidade mínima de componentes disponíveis para calcular o Virality Score.'),
    ('METRICS_CALCULATION_VERSION', '"v1"'::JSONB, 'Versão das fórmulas do Metrics Engine e do Virality Score.'),
    ('VIRALITY_VELOCITY_WEIGHT', '0.35'::JSONB, 'Peso inicial do percentil de View Velocity no Virality Score.'),
    ('VIRALITY_ENGAGEMENT_WEIGHT', '0.20'::JSONB, 'Peso inicial do percentil de Engagement Rate no Virality Score.'),
    ('VIRALITY_OUTLIER_WEIGHT', '0.20'::JSONB, 'Peso inicial do percentil de Outlier Score no Virality Score.'),
    ('VIRALITY_VIEWS_WEIGHT', '0.15'::JSONB, 'Peso inicial do percentil de views no Virality Score.'),
    ('VIRALITY_FRESHNESS_WEIGHT', '0.10'::JSONB, 'Peso inicial do Freshness Score no Virality Score.'),
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
