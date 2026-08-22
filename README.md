# TrendLens

Plataforma de inteligência de conteúdo baseada em n8n, PostgreSQL e LLMs para coletar e analisar métricas de vídeos curtos, identificar padrões de viralização e estimar oportunidades de conteúdo considerando engajamento, velocidade de crescimento e elegibilidade de monetização.

## Estado do projeto

As Fases 1 a 7 foram concluídas. O pipeline já coleta vídeos, acompanha snapshots, classifica o conteúdo e calcula métricas, Virality Score, Monetization Score e tendências agregadas de forma versionada e auditável.

O MVP terá como foco vídeos públicos do YouTube, candidatos a Shorts, em português e voltados ao mercado brasileiro. Nenhum número analítico será apresentado como fato antes de ser calculado a partir dos dados coletados.

## Componentes

- PostgreSQL dedicado para dados e configurações operacionais.
- n8n para coleta, snapshots, classificação e processamento.
- YouTube Data API como fonte pública do MVP.
- LLM configurado por credencial do n8n para classificações e recomendações.
- Docker Compose para uma instalação reproduzível.

Cloudflare Tunnel e Caddy fazem parte do deployment original, mas não são dependências para executar este repositório localmente.

## Requisitos

- Docker Engine
- Docker Compose v2 com suporte a `include`

## Inicialização do PostgreSQL

Copie o arquivo de exemplo e defina uma senha forte:

```bash
cp .env.example .env
```

Edite apenas o arquivo `.env`, que não deve ser versionado. Depois execute:

```bash
docker compose up -d
```

O PostgreSQL não publica a porta 5432 no host. Containers conectados à rede Docker `trendlens_backend` podem acessá-lo em:

```text
Host: trendlens-postgres
Port: 5432
Database: trendlens
```

Verifique a saúde do serviço:

```bash
docker compose ps
```

## Validação do banco

Com o container saudável, execute:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /workspace/tests/sql/foundation-smoke.sql'
```

O teste roda dentro de uma transação e desfaz os dados temporários ao terminar.

Os scripts de `/docker-entrypoint-initdb.d` são executados automaticamente apenas quando o volume do PostgreSQL está vazio. Mudanças futuras em bancos existentes deverão ser aplicadas por migrations versionadas.

## Atualização de um banco existente

Depois de atualizar o repositório para a Fase 7, aplique as migrations e os seeds idempotentes na ordem abaixo:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/002_youtube_collector.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/003_video_collection_provenance.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/004_video_snapshot_tracker.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/005_ai_content_classifier.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/006_metrics_engine.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/007_monetization_engine.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/008_trend_engine.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/seeds/settings.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/seeds/collection_queries.sql
```

Valide a configuração:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/youtube-collector-foundation.sql
```

Valide a política do Snapshot Tracker:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/video-snapshot-tracker.sql
```

Valide a fundação do AI Content Classifier:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/ai-content-classifier.sql
```

Valide o Metrics Engine e o Virality Score:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/metrics-engine.sql
```

Valide o Monetization Engine:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/monetization-engine.sql
```

Valide o Trend Engine:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/trend-engine.sql
```

## Integração com um n8n existente

No servidor de deployment, o container n8n deverá participar da rede externa `trendlens_backend`. A credencial PostgreSQL deve ser criada na interface do n8n, sem versionar ou inserir a senha em workflows.

Exemplo para o Compose do n8n:

```yaml
services:
  n8n:
    networks:
      - reverse_proxy
      - trendlens_backend

networks:
  reverse_proxy:
    external: true
  trendlens_backend:
    external: true
```

O workflow de smoke test permanece inativo e sua exportação não contém associação com uma credencial específica da instância. Depois da importação, atribua manualmente a credencial PostgreSQL dedicada.

## Validação integrada

O workflow `00 - TrendLens - PostgreSQL Smoke Test` foi executado com sucesso contra PostgreSQL 16.15. A execução confirmou:

- banco `trendlens`;
- schema esperado disponível;
- 10 categorias e 10 configurações;
- insert em `pipeline_runs`;
- leitura do mesmo registro;
- conexão exclusivamente pela rede Docker privada.

O artefato versionável está em [workflows/00-postgresql-smoke-test.json](workflows/00-postgresql-smoke-test.json).

O collector exportado, sem associações de credenciais, está em [workflows/01-youtube-data-collector.json](workflows/01-youtube-data-collector.json).

O Snapshot Tracker exportado, também sem associações de credenciais, está em [workflows/02-video-snapshot-tracker.json](workflows/02-video-snapshot-tracker.json). Depois da importação, associe `TrendLens PostgreSQL` aos quatro nodes PostgreSQL e a credencial OAuth2 do YouTube ao node HTTP Request. O workflow validado no deployment original possui ID `LTjMbH3UGW994lCA` e permanece inativo.

O AI Content Classifier exportado, sem associações de credenciais, está em [workflows/03-ai-content-classifier.json](workflows/03-ai-content-classifier.json). Depois da importação, associe `TrendLens PostgreSQL` aos cinco nodes PostgreSQL e a credencial NVIDIA aos dois nodes de modelo. O workflow no deployment original possui ID `86iKeeCFXiiX3fki`, permanece inativo e não foi publicado.

O Metrics Engine exportado está em [workflows/04-metrics-engine.json](workflows/04-metrics-engine.json). A exportação permanece inativa e não contém credenciais; depois da importação, associe `TrendLens PostgreSQL` aos quatro nodes PostgreSQL. O workflow do deployment original possui ID `zf3Wwl1aUINxrGEy` e foi publicado e ativado após validação explícita do usuário.

O Trend Engine exportado está em [workflows/05-trend-engine.json](workflows/05-trend-engine.json). A exportação permanece inativa e não contém credenciais; depois da importação, associe `TrendLens PostgreSQL` aos quatro nodes PostgreSQL. O workflow validado no deployment original possui ID `WLiCVXsMdALZN6Xq`, permanece inativo e não foi publicado.

O Monetization Engine exportado está em [workflows/06-monetization-engine.json](workflows/06-monetization-engine.json). A exportação permanece inativa e não contém credenciais; depois da importação, associe `TrendLens PostgreSQL` aos quatro nodes PostgreSQL. O workflow do deployment original possui ID `oSqF120sKMd9AIh6` e está publicado e ativo.

## Validação do collector

O workflow `01 - TrendLens - YouTube Data Collector` permanece inativo e foi testado manualmente. A execução de validação final processou quatro combinações de query e grupo amostral:

- 100 resultados recebidos;
- 100 itens processados;
- 99 vídeos novos e 1 duplicado;
- 100 correspondências de proveniência registradas;
- 99 snapshots históricos inseridos;
- 8 chamadas de API e 4 unidades estimadas no bucket de busca;
- nenhum item ignorado e nenhum erro.

Os contadores foram persistidos em `pipeline_runs`. O resultado reflete apenas essa execução de teste e não constitui uma análise de tendências.

## Política de snapshots

A seleção usa configurações do PostgreSQL:

- vídeos com até 24 horas: intervalo mínimo de 60 minutos;
- vídeos entre 1 e 3 dias: intervalo mínimo de 360 minutos;
- vídeos entre 3 e 7 dias: intervalo mínimo de 1.440 minutos;
- vídeos com mais de 7 dias: fora do acompanhamento ativo;
- no máximo 200 vídeos por execução, respeitando o orçamento de quota configurado.

Esses valores são defaults operacionais e podem ser alterados em `settings`. O Schedule Trigger verifica a fila a cada 15 minutos, mas a decisão de atualizar cada vídeo é tomada pela política armazenada no banco. Como o workflow é exportado inativo, o agendamento não executa até ativação explícita.

## Validação do Snapshot Tracker

A primeira execução manual integrada aplicou a migration, selecionou 149 vídeos vencidos e processou três lotes:

- 149 itens recebidos e processados;
- 149 novos snapshots;
- zero itens ignorados e zero falhas;
- 3 chamadas `videos.list` e 3 unidades estimadas de quota;
- duração total de 1,685 segundo.

Uma segunda execução imediata selecionou zero vídeos, não chamou a API e finalizou com sucesso. Isso confirmou que os snapshots recém-inseridos passaram a controlar corretamente o próximo instante elegível. O node temporário de migration foi removido após a validação; a versão final possui nove nodes, está inativa e não foi publicada.

## Classificação estruturada por IA

O classificador seleciona no máximo cinco vídeos ainda não processados por execução, envia título, descrição truncada e contexto público ao NVIDIA Nemotron e exige uma resposta compatível com JSON Schema. O parser possui uma tentativa automática de correção; falhas remanescentes são sanitizadas e registradas sem bloquear os próximos itens.

Cada classificação persiste categoria, tópico, tipo de conteúdo, formato, hook, origem, estilo de apresentação, confiança e três scores entre 0 e 1. Originalidade, risco autoral e risco de conteúdo reutilizado são estimativas heurísticas, não decisões jurídicas, afirmações de violação ou garantias de monetização. Modelo e versão do prompt são gravados em cada linha para auditoria.

## Validação do AI Content Classifier

A execução manual da revisão final selecionou cinco candidatos e terminou com sucesso:

- 5 itens recebidos;
- 4 novas classificações estruturadas;
- 1 item ignorado porque uma execução concorrente o persistiu primeiro;
- 0 falhas;
- 5 chamadas estimadas ao modelo;
- duração total de 134,315 segundos.

A validação também confirmou a idempotência entre execuções concorrentes: a chave primária de `video_classifications` impediu duplicação e o conflito foi contabilizado como item ignorado. O bootstrap temporário da migration foi removido depois do teste; a versão final possui 13 nodes, está inativa e não foi publicada.

## Validação do Metrics Engine

A revisão final calculou a coorte real de sete dias em uma única operação transacional:

- 268 vídeos elegíveis e processados;
- 264 Virality Scores;
- 150 View Velocities;
- 11 baselines de canal;
- zero falhas e zero scores fora das faixas;
- Virality Score entre 1,0765 e 8,8983, com média 5,1283;
- duração total de 0,177 segundo na execução final.

Nenhuma View Acceleration foi produzida porque os vídeos reais ainda não possuíam três snapshots. O campo permanece `NULL` até existir histórico suficiente. A fórmula completa e a estratégia de dados ausentes estão em [docs/scoring.md](docs/scoring.md).

## Validação do Monetization Engine

A execução final calculou os fatores explicáveis de todas as classificações disponíveis:

- 15 classificações elegíveis e processadas;
- 14 scores com qualidade de engajamento observada;
- 1 score com redistribuição explícita do peso de engajamento ausente;
- 2 classificações acima do limite heurístico de risco combinado;
- zero falhas e zero scores fora das faixas;
- Monetization Score entre 0,9065 e 5,5480, com média 3,4076;
- duração total de 0,076 segundo na execução final.

Esses números descrevem somente a pequena amostra classificada existente. O score estima a atratividade de um formato para monetização sustentável; não prevê receita nem substitui decisões do YouTube.

## Validação do Trend Engine

A execução final agregou a janela atual de sete dias em dimensões comparáveis:

- 20 vídeos classificados na janela;
- 104 estatísticas persistidas em sete tipos de dimensão;
- maior grupo com 4 vídeos;
- Consistency Score entre 0,6667 e 3,9470, com média 3,2893;
- zero valores fora das faixas e zero falhas;
- duração total de 0,102 segundo.

As 104 direções permaneceram `insufficient_data`, pois nenhum grupo atingiu a amostra mínima padrão de 30 vídeos nas janelas atual e anterior. O sistema não fabricou uma tendência com base em uma amostra pequena.

## Segurança

- Não publique a porta do PostgreSQL na internet.
- Não versione `.env`, tokens, chaves, credenciais OAuth ou a chave de criptografia do n8n.
- Use uma credencial PostgreSQL dedicada ao TrendLens.
- Dados de erro devem ser sanitizados antes da persistência.

## Documentação

- [Arquitetura](docs/architecture.md)
- [Modelo de dados](docs/data-model.md)
- [Metodologia](docs/methodology.md)
- [Metodologia de scoring](docs/scoring.md)
- [Limitações](docs/limitations.md)

## Roadmap resumido

1. Fundação PostgreSQL e conexão com o n8n.
2. Coleta de vídeos e primeiro snapshot.
3. Acompanhamento periódico de snapshots.
4. Classificação estruturada por IA.
5. Métricas e Virality Score.
6. Monetization Score.
7. Tendências, oportunidades, recomendações e relatório.

## Licença

Distribuído sob a licença MIT. Consulte [LICENSE](LICENSE).
