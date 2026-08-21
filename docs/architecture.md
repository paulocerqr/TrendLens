# Arquitetura

## Objetivo da fundação

A fundação separa a aplicação TrendLens do banco interno do n8n e de outros projetos do servidor. O PostgreSQL do TrendLens possui volume, banco, usuário e rede próprios.

## Ambiente reproduzível

```text
Repositório TrendLens
        |
        v
Docker Compose
        |
        +-- trendlens-postgres:5432
        |
        +-- trendlens_postgres_data
        |
        +-- trendlens_backend
```

A porta 5432 existe somente dentro da rede Docker. O Compose não contém um mapeamento `ports`, portanto não há conflito com outro PostgreSQL que use a porta 5432 em outro container.

## Deployment com n8n existente

```text
Cloudflare
    |
    v
Caddy
    |
    v
n8n:5678
    |
    | trendlens_backend
    v
trendlens-postgres:5432
```

O n8n continua conectado à rede `reverse_proxy` para receber tráfego do Caddy e passa a participar também de `trendlens_backend` para acessar o banco. O PostgreSQL não participa da rede do reverse proxy.

O Compose deste repositório cria uma rede com o nome estável `trendlens_backend`. No Compose externo do n8n, essa rede deve ser declarada como `external: true`.

## Fronteiras de responsabilidade

- O repositório fornece schema, índices, seeds, testes e Compose do PostgreSQL.
- O arquivo `.env` existe apenas no ambiente onde o banco é executado.
- Credenciais são criadas e armazenadas no n8n.
- Workflows não contêm senhas, tokens ou chaves.
- Caddy e Cloudflare não precisam conhecer o PostgreSQL.

## Fluxo atual da coleta

```text
YouTube Data API
        |
        v
01 - Data Collector
        |
        v
videos + video_snapshots + video_collection_matches
        |
        v
classificação + métricas + tendências
        |
        v
recomendações + relatório
```

O collector consulta configurações e queries no PostgreSQL, processa uma query por vez, obtém detalhes em lote e registra contadores por execução. Os workflows seguintes permanecem no roadmap e serão implementados separadamente.

O Snapshot Tracker consulta a função `select_snapshot_candidates`, agrupa os vídeos vencidos em lotes de até 50 IDs, atualiza somente as estatísticas públicas via `videos.list` e insere uma nova linha em `video_snapshots`. A política de idade e intervalo fica em `settings`; o Schedule Trigger funciona apenas como verificação periódica da fila.

## Persistência e inicialização

Os scripts em `database/` são montados em `/docker-entrypoint-initdb.d`. A imagem oficial do PostgreSQL executa esses arquivos somente ao inicializar um volume vazio.

O volume nomeado `trendlens_postgres_data` preserva os dados quando o container é recriado. Alterações posteriores no schema deverão usar migrations, pois editar os scripts de bootstrap não modifica volumes existentes.
