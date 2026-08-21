# TrendLens

Plataforma de inteligência de conteúdo baseada em n8n, PostgreSQL e LLMs para coletar e analisar métricas de vídeos curtos, identificar padrões de viralização e estimar oportunidades de conteúdo considerando engajamento, velocidade de crescimento e elegibilidade de monetização.

## Estado do projeto

A Fase 1 foi concluída. A Fase 2 está em implementação: o collector do YouTube foi criado e validado no n8n, com configuração no PostgreSQL, coleta em lote, deduplicação, primeiro snapshot, proveniência amostral e observabilidade. A execução real limitada confirmou o fluxo completo contra a YouTube Data API e o PostgreSQL do TrendLens.

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

Depois de atualizar o repositório para a Fase 2, aplique a migration e os seeds idempotentes:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/002_youtube_collector.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/003_video_collection_provenance.sql

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

## Segurança

- Não publique a porta do PostgreSQL na internet.
- Não versione `.env`, tokens, chaves, credenciais OAuth ou a chave de criptografia do n8n.
- Use uma credencial PostgreSQL dedicada ao TrendLens.
- Dados de erro devem ser sanitizados antes da persistência.

## Documentação

- [Arquitetura](docs/architecture.md)
- [Modelo de dados](docs/data-model.md)
- [Metodologia](docs/methodology.md)
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
