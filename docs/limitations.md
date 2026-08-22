# Limitações

## Fundação

- A Fase 1A valida o repositório e o PostgreSQL isoladamente; ela não comprova conectividade com o n8n remoto.
- O teste integrado n8n para PostgreSQL depende do clone e deployment no servidor e pertence à Fase 1B.
- Scripts de bootstrap não substituem migrations em volumes já inicializados.
- A estimativa de quota armazenada em `pipeline_runs` dependerá da contabilização implementada pelo collector.
- O Schedule Trigger do Snapshot Tracker verifica candidatos a cada 15 minutos; os intervalos efetivos por vídeo são aplicados pelo PostgreSQL e podem ter atraso de até um ciclo de verificação.
- Execuções simultâneas do Snapshot Tracker não são coordenadas por um lock distribuído no MVP. A operação é idempotente para o mesmo vídeo e instante de execução, mas dois runs iniciados em instantes diferentes podem coletar observações muito próximas.
- Execuções simultâneas do AI Content Classifier podem selecionar os mesmos candidatos; a chave primária por vídeo impede duplicação, mas uma das execuções será contabilizada como ignorada após consumir uma chamada ao modelo.
- Latência e disponibilidade do provedor NVIDIA podem produzir timeouts. O workflow limita retries, registra a falha e continua, mas não mantém uma fila explícita de tentativas por vídeo.
- O Metrics Engine recalcula percentis sobre a coorte atual; scores históricos podem mudar quando a amostra cresce ou a versão das fórmulas é alterada.
- Baseline de canal exige outros vídeos recentes do mesmo canal. Canais com pouca presença na amostra mantêm `channel_median_views` e `outlier_score` como `NULL`.
- Execuções simultâneas do Metrics Engine são idempotentes por snapshot, mas podem repetir trabalho de cálculo. O intervalo padrão de uma hora é muito maior que a duração observada da execução.

## Dados e metodologia

- A API pública do YouTube não fornece uma flag perfeita para Shorts.
- Duração e metadados permitem apenas identificar candidatos com diferentes níveis de confiança.
- Queries de pesquisa introduzem viés amostral.
- Views e engajamento não representam receita.
- Não há acesso ao algoritmo interno do YouTube nem à receita real dos criadores.
- Copyright, conteúdo reutilizado e elegibilidade de monetização serão riscos heurísticos, não decisões oficiais.
- A classificação usa metadados, não analisa frames, áudio ou transcrição; portanto origem, estilo, hook e riscos podem ter confiança limitada.
- Correlação entre características e desempenho não implica causalidade.
- Métricas ausentes não devem ser convertidas automaticamente em zero.
- Resultados só podem ser comparados dentro de contextos compatíveis de plataforma, região, período e amostra.
- O Virality Score é relativo à amostra coletada e aos pesos v1; ele não reproduz nem prevê diretamente o algoritmo interno do YouTube.

## Segurança

- O Compose não publica o PostgreSQL no host.
- O arquivo `.env.example` contém apenas placeholders.
- A credencial real deverá permanecer no n8n e no ambiente privado do servidor.
- O banco não consegue detectar sozinho todos os secrets em mensagens de erro; os workflows devem sanitizar conteúdo antes de persistir.
