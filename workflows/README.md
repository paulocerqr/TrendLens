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

## 02 - TrendLens - Video Snapshot Tracker

O arquivo [02-video-snapshot-tracker.json](02-video-snapshot-tracker.json) implementa:

- seleção de vídeos vencidos por política configurável no PostgreSQL;
- faixas de acompanhamento recente, intermediária e antiga;
- limite de vídeos por execução e lotes de até 50 IDs para `videos.list`;
- novos registros imutáveis em `video_snapshots`;
- preservação de `NULL` para likes ou comentários ausentes;
- retries limitados, erros sanitizados e contadores em `pipeline_runs`;
- Manual Trigger para validação e Schedule Trigger de verificação a cada 15 minutos.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL e uma credencial do tipo `youTubeOAuth2Api` ao node HTTP Request.

O workflow deve permanecer inativo durante o desenvolvimento. Enquanto estiver inativo, o Schedule Trigger não executará.

A validação integrada no workflow `LTjMbH3UGW994lCA` processou 149 vídeos em três lotes, inseriu 149 snapshots e terminou sem falhas. Uma segunda execução imediata não encontrou vídeos vencidos e não consumiu quota da API. Depois do teste, o bootstrap temporário da migration foi removido; a versão final possui nove nodes e permanece inativa e não publicada.
