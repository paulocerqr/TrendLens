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
03 - AI Content Classifier
        |
        v
video_classifications
        |
        v
04 - Metrics Engine & Virality Score
        |
        v
video_metrics
        |
        v
06 - Monetization Engine
        |
        v
video_monetization_scores
        |
        v
05 - Trend Engine
        |
        v
category_statistics
        |
        v
07 - Opportunity Engine
        |
        v
Opportunity Score + ranking em category_statistics
        |
        v
recomendações + relatório
```

O collector consulta configurações e queries no PostgreSQL, processa uma query por vez, obtém detalhes em lote e registra contadores por execução. Cada etapa analítica permanece separada em um workflow especializado.

O Snapshot Tracker consulta a função `select_snapshot_candidates`, agrupa os vídeos vencidos em lotes de até 50 IDs, atualiza somente as estatísticas públicas via `videos.list` e insere uma nova linha em `video_snapshots`. A política de idade e intervalo fica em `settings`; o Schedule Trigger funciona apenas como verificação periódica da fila.

O AI Content Classifier consulta `select_classification_candidates`, processa um vídeo por vez e conecta o Basic LLM Chain a um modelo NVIDIA e a um parser estruturado. A saída validada é persistida em colunas tipadas de `video_classifications`; falhas do modelo, do parser ou da persistência seguem rotas próprias para `pipeline_errors` e o loop continua.

O Metrics Engine chama `refresh_video_metrics` em uma operação set-based. A função identifica o snapshot atual de cada vídeo elegível, deriva o histórico necessário, calcula baselines e percentis sobre a coorte completa e faz upsert idempotente em `video_metrics`. O n8n apenas inicia, audita e finaliza a operação; todos os números analíticos vêm do PostgreSQL.

O Monetization Engine chama `refresh_video_monetization_scores` depois do Metrics Engine. A função combina classificação estruturada, duração observada e percentil de engajamento, persiste cada fator positivo e cada risco e mantém versões de cálculo em `video_monetization_scores`.

O Trend Engine chama `refresh_category_statistics` e materializa estatísticas por categoria, tópico, tipo, formato, hook, origem e combinação categoria–formato–origem. A janela atual é comparada com a anterior equivalente; grupos sem amostra mínima permanecem explicitamente como `insufficient_data`.

O Opportunity Engine chama `refresh_opportunity_rankings` sobre o bucket mais recente do Trend Engine. A função exige Virality, Monetization e Consistency, calcula o score ponderado e persiste rank e percentil dentro de cada contexto comparável e tipo de dimensão.

## Persistência e inicialização

Os scripts em `database/` são montados em `/docker-entrypoint-initdb.d`. A imagem oficial do PostgreSQL executa esses arquivos somente ao inicializar um volume vazio.

O volume nomeado `trendlens_postgres_data` preserva os dados quando o container é recriado. Alterações posteriores no schema deverão usar migrations, pois editar os scripts de bootstrap não modifica volumes existentes.
