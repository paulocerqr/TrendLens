# Workflows

Os workflows são adicionados incrementalmente depois de criados, validados e testados na instância n8n.

## 00 - TrendLens - PostgreSQL Smoke Test

O arquivo [00-postgresql-smoke-test.json](00-postgresql-smoke-test.json) valida:

- identificação do banco e da versão do PostgreSQL;
- presença das tabelas essenciais;
- quantidade inicial de categorias e configurações;
- insert auditável em `pipeline_runs`;
- leitura do registro recém-inserido.

A associação da credencial foi removida da exportação para evitar IDs específicos da instância. Depois de importar, atribua a credencial `TrendLens PostgreSQL` aos três nodes PostgreSQL.

O workflow deve permanecer inativo e ser executado manualmente.

## 01 - TrendLens - YouTube Data Collector

O arquivo [01-youtube-data-collector.json](01-youtube-data-collector.json) implementa:

- seleção configurável das queries `recent` e `high_performance`;
- buscas do YouTube com janela, idioma, região e limite vindos do PostgreSQL;
- consulta de detalhes em lote para reduzir chamadas de API;
- conversão de duração e classificação heurística de candidatos a Shorts;
- upsert de vídeos, primeiro snapshot e proveniência da amostra;
- logs em `pipeline_runs` e `pipeline_errors` com retries limitados.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos nodes PostgreSQL e uma credencial do tipo `youTubeOAuth2Api` aos dois nodes HTTP Request.

O workflow possui somente Manual Trigger e deve permanecer inativo durante o desenvolvimento.
