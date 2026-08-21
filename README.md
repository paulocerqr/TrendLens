# TrendLens

Plataforma de inteligência de conteúdo baseada em n8n, PostgreSQL e LLMs para coletar e analisar métricas de vídeos curtos, identificar padrões de viralização e estimar oportunidades de conteúdo considerando engajamento, velocidade de crescimento e elegibilidade de monetização.

## Estado do projeto

O projeto está na Fase 1A: fundação reproduzível. Esta etapa entrega o modelo de dados, o PostgreSQL executável por Docker Compose e testes SQL. Os workflows do n8n serão implementados incrementalmente após a implantação do banco no mesmo servidor da instância n8n.

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

Essa integração e o workflow de smoke test pertencem à Fase 1B e não são executados automaticamente por este repositório.

## Segurança

- Não publique a porta do PostgreSQL na internet.
- Não versione `.env`, tokens, chaves, credenciais OAuth ou a chave de criptografia do n8n.
- Use uma credencial PostgreSQL dedicada ao TrendLens.
- Dados de erro devem ser sanitizados antes da persistência.

## Documentação

- [Arquitetura](docs/architecture.md)
- [Modelo de dados](docs/data-model.md)
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
