# Limitações

## Fundação

- A Fase 1A valida o repositório e o PostgreSQL isoladamente; ela não comprova conectividade com o n8n remoto.
- O teste integrado n8n para PostgreSQL depende do clone e deployment no servidor e pertence à Fase 1B.
- Scripts de bootstrap não substituem migrations em volumes já inicializados.
- A estimativa de quota armazenada em `pipeline_runs` dependerá da contabilização implementada pelo collector.
- O Schedule Trigger do Snapshot Tracker verifica candidatos a cada 15 minutos; os intervalos efetivos por vídeo são aplicados pelo PostgreSQL e podem ter atraso de até um ciclo de verificação.
- Execuções simultâneas do Snapshot Tracker não são coordenadas por um lock distribuído no MVP. A operação é idempotente para o mesmo vídeo e instante de execução, mas dois runs iniciados em instantes diferentes podem coletar observações muito próximas.

## Dados e metodologia

- A API pública do YouTube não fornece uma flag perfeita para Shorts.
- Duração e metadados permitem apenas identificar candidatos com diferentes níveis de confiança.
- Queries de pesquisa introduzem viés amostral.
- Views e engajamento não representam receita.
- Não há acesso ao algoritmo interno do YouTube nem à receita real dos criadores.
- Copyright, conteúdo reutilizado e elegibilidade de monetização serão riscos heurísticos, não decisões oficiais.
- Correlação entre características e desempenho não implica causalidade.
- Métricas ausentes não devem ser convertidas automaticamente em zero.
- Resultados só podem ser comparados dentro de contextos compatíveis de plataforma, região, período e amostra.

## Segurança

- O Compose não publica o PostgreSQL no host.
- O arquivo `.env.example` contém apenas placeholders.
- A credencial real deverá permanecer no n8n e no ambiente privado do servidor.
- O banco não consegue detectar sozinho todos os secrets em mensagens de erro; os workflows devem sanitizar conteúdo antes de persistir.
