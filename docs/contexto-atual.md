  ## Objetivo

  TrendLens é uma plataforma baseada em n8n, PostgreSQL e LLMs para coletar e analisar métricas públicas
  de vídeos curtos do YouTube, identificar padrões de viralização e estimar oportunidades de conteúdo e
  monetização.

  O MVP é direcionado ao Brasil, com idioma principal português.

  ## Repositório

  Repositório local esperado:

  `TrendLens`

  Branch principal:

  `main`

  Antes de trabalhar:

  ```bash
  git pull --ff-only
  git status
  git log -5 --oneline

  O commit mais recente esperado é:

  adc1012 fix: finalize YouTube collector validation

  Se esse commit não estiver disponível, verificar se foi enviado pelo computador anterior.

  ## Infraestrutura

  O n8n está no servidor Ubuntu, separado deste repositório:

  https://n8n.utileasy.com.br

  Arquitetura:

  Internet
  → Cloudflare
  → Cloudflare Tunnel
  → Caddy
  → n8n:5678

  O MCP do n8n está configurado e autenticado:

  https://n8n.utileasy.com.br/mcp-server/http

  Utilizar preferencialmente o MCP n8n para inspecionar, criar, alterar, validar e testar workflows.

  Não alterar a infraestrutura sem explicar previamente.

  ## PostgreSQL do TrendLens

  Existe um PostgreSQL exclusivo:

  Container: trendlens-postgres
  Host Docker: trendlens-postgres
  Porta interna: 5432
  Banco: trendlens
  Rede Docker: trendlens_backend

  A porta 5432 não está publicada no host.

  O n8n participa da rede trendlens_backend e possui uma credencial chamada:

  TrendLens PostgreSQL

  Não expor a senha ou outros dados da credencial.

  ## Estado da Fase 1

  A fundação PostgreSQL foi concluída.

  Foram implementados:

  - Docker Compose reproduzível;
  - schema inicial;
  - índices;
  - categorias;
  - settings operacionais;
  - queries de coleta;
  - observabilidade com pipeline_runs e pipeline_errors;
  - teste SQL da fundação;
  - workflow de smoke test PostgreSQL.

  O smoke test PostgreSQL passou no servidor.

  Principais commits:

  dc167b8 feat: add reproducible PostgreSQL foundation
  71a0630 docs: document foundation and deployment
  b710d54 feat: add PostgreSQL smoke test workflow

  ## Estado da Fase 2

  A Fase 2 — YouTube Collector foi implementada e validada com dados reais.

  Workflow no n8n:

  Nome: 01 - TrendLens - YouTube Data Collector
  ID: yXv20DXsRyIyoat2
  Nodes: 16
  Estado: inativo
  Versão publicada: nenhuma

  O workflow possui somente gatilho manual durante o desenvolvimento.

  Não ativar ou publicar sem autorização explícita.

  Credenciais configuradas no n8n:

  - TrendLens PostgreSQL;
  - credencial OAuth2 da YouTube Data API.

  Não alterar ou expor essas credenciais.

  ## Funcionalidades do collector

  O workflow:

  1. carrega configurações do PostgreSQL;
  2. cria um registro em pipeline_runs;
  3. escolhe queries de forma configurável;
  4. alterna entre grupos recent e high_performance;
  5. consulta search.list;
  6. consulta detalhes em lote com videos.list;
  7. converte duração ISO 8601;
  8. filtra candidatos com até SHORT_MAX_DURATION;
  9. calcula short_confidence;
  10. faz upsert em videos;
  11. insere snapshots históricos;
  12. preserva proveniência em video_collection_matches;
  13. evita duplicatas;
  14. atualiza contadores;
  15. registra erros sanitizados;
  16. finaliza o pipeline_run.

  Não existem Code nodes.

  ## Resultado do teste real final

  A execução manual final terminou com sucesso:

  Resultados recebidos:       100
  Itens processados:          100
  Itens ignorados:              0
  Itens com erro:               0
  Vídeos novos:                99
  Duplicados:                   1
  Correspondências registradas: 100
  Snapshots inseridos:         99
  Chamadas de API:              8
  Unidades estimadas de busca:  4

  Os 99 snapshots são esperados porque um mesmo vídeo apareceu mais de uma vez na execução e a chave
  histórica evita um snapshot duplicado no mesmo instante de coleta.

  Os dados reais estão no PostgreSQL do TrendLens.

  ## Problemas encontrados e corrigidos

  ### Limite SQL

  O PostgreSQL rejeitou uma expressão variável diretamente em LIMIT.

  Foi substituída por:

  - ROW_NUMBER();
  - coluna query_limit;
  - filtro collection_order <= query_limit.

  ### Finalização após o loop

  A saída concluída do loop não preservava o pipeline_run_id.

  A finalização agora usa referência explícita:

  Iniciar execução e carregar queries
  → first()
  → pipeline_run_id

  ### Precisão dos snapshots

  A passagem do timestamp do PostgreSQL pelo n8n perdeu precisão abaixo de milissegundos.

  A persistência agora consulta diretamente:

  pipeline_runs.started_at

  Isso mantém timestamps consistentes entre execução, proveniência e snapshots.

  As execuções afetadas foram recuperadas durante o teste seguinte.

  ## Banco e migrations

  As migrations da Fase 2 foram aplicadas no servidor:

  database/migrations/002_youtube_collector.sql
  database/migrations/003_video_collection_provenance.sql

  O teste abaixo passou:

  tests/sql/youtube-collector-foundation.sql

  A tabela video_collection_matches preserva:

  - execução;
  - query;
  - vídeo;
  - posição no resultado;
  - instante da correspondência.

  Isso permite comparar os grupos recent e high_performance.

  ## Arquivos importantes

  workflows/00-postgresql-smoke-test.json
  workflows/01-youtube-data-collector.json

  database/schema.sql
  database/indexes.sql
  database/migrations/002_youtube_collector.sql
  database/migrations/003_video_collection_provenance.sql
  database/seeds/categories.sql
  database/seeds/settings.sql
  database/seeds/collection_queries.sql

  tests/sql/foundation-smoke.sql
  tests/sql/youtube-collector-foundation.sql

  README.md
  docs/architecture.md
  docs/data-model.md
  docs/methodology.md
  docs/limitations.md

  A exportação do collector:

  - não contém credenciais;
  - não contém secrets;
  - permanece inativa;
  - possui 16 nodes;
  - não possui Code nodes;
  - não inclui configurações específicas de exposição via MCP.

  ## Commits da Fase 2

  3fff500 feat: add YouTube collector query configuration
  21d3436 feat: preserve YouTube collection provenance
  e66fb9d feat: add YouTube data collector workflow
  adc1012 fix: finalize YouTube collector validation

  ## Próxima etapa

  A próxima etapa é:

  Fase 3 — Video Snapshot Tracker

  Ainda não foi implementada.

  Antes de criar o workflow:

  1. verificar o repositório;
  2. verificar o MCP;
  3. inspecionar o collector existente;
  4. inspecionar o schema e os dados reais;
  5. propor um plano limitado para a Fase 3;
  6. aguardar minha autorização antes de criar recursos persistentes.

  ## Requisitos da Fase 3

  Criar futuramente:

  02 - Video Snapshot Tracker

  Responsabilidades:

  - selecionar vídeos ainda relevantes;
  - consultar novamente views, likes e comentários;
  - inserir novos registros em video_snapshots;
  - nunca atualizar snapshots anteriores;
  - usar frequências configuráveis por idade;
  - implementar retries limitados;
  - registrar execução e erros;
  - minimizar chamadas à API;
  - manter o workflow inativo durante o desenvolvimento.

  Política inicial:

  vídeos com até 24 horas:
  acompanhamento frequente

  1 a 3 dias:
  frequência intermediária

  3 a 7 dias:
  frequência menor

  mais de 7 dias:
  encerrar acompanhamento ativo

  Os valores devem ficar no PostgreSQL, não fixados diretamente no workflow.

  ## Regras permanentes

  - Usar nodes nativos do n8n quando suficientes.
  - Evitar Code nodes.
  - Inspecionar antes de alterar.
  - Validar após alterações.
  - Executar testes quando possível.
  - Não ativar workflows sem autorização.
  - Não excluir workflows.
  - Não alterar credenciais sem necessidade.
  - Não armazenar API keys nos workflows.
  - Nunca revelar tokens ou secrets.
  - Preservar workflows fora do escopo.
  - Não misturar arquivos do Utileasy com o TrendLens.
  - Não inserir emojis em código, fixtures, documentação versionada ou commits.
  - Todos os números analíticos devem vir do PostgreSQL.
  - Recomendações e monetização serão heurísticas, não decisões oficiais do YouTube.


  Depois, no computador de casa, confirme também que o clone recebeu o commit:

  ```bash
  git log -1 --oneline

  A saída esperada começa com:

  adc1012