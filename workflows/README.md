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

## 03 - TrendLens - AI Content Classifier

O arquivo [03-ai-content-classifier.json](03-ai-content-classifier.json) implementa:

- seleção configurável de vídeos do YouTube ainda não classificados;
- envio somente dos metadados necessários, com descrição truncada;
- classificação com NVIDIA Nemotron e prompt versionado;
- saída JSON validada por schema e uma tentativa automática de correção;
- persistência tipada em `video_classifications`, sem sobrescrever classificações existentes;
- estimativas separadas de originalidade, risco autoral e conteúdo reutilizado;
- retries limitados, erros sanitizados e contadores em `pipeline_runs`;
- Manual Trigger e Schedule Trigger de execução a cada hora.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos cinco nodes PostgreSQL e uma credencial `nvidiaApi` aos dois nodes de modelo.

O workflow deve permanecer inativo durante o desenvolvimento. Enquanto estiver inativo, o Schedule Trigger não executará.

A execução integrada final no workflow `86iKeeCFXiiX3fki` selecionou cinco vídeos, criou quatro classificações e ignorou uma classificação inserida por uma execução concorrente. Terminou com zero falhas em 134,315 segundos. O bootstrap temporário da migration foi removido; a versão final possui 13 nodes, permanece inativa e não publicada.

## 04 - TrendLens - Metrics Engine & Virality Score

O arquivo [04-metrics-engine.json](04-metrics-engine.json) implementa:

- cálculo em lote de Like Rate, Comment Rate e Engagement Rate;
- View Velocity e View Acceleration a partir dos snapshots anteriores;
- mediana recente do canal, Relative Performance e Outlier Score;
- percentis por coorte comparável com fallback explícito;
- Freshness Score e Virality Score versionado de 0 a 10;
- recálculo idempotente por snapshot;
- logs de execução e erro sanitizado;
- Manual Trigger e Schedule Trigger a cada hora.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL.

A execução integrada final no workflow `zf3Wwl1aUINxrGEy` processou 268 vídeos e produziu 264 Virality Scores, 150 velocities e 11 baselines de canal, sem falhas. O recálculo imediato preservou 268 linhas, confirmou zero scores fora das faixas e terminou em 0,177 segundo. O workflow final possui seis nodes e foi publicado e ativado pelo usuário; sua exportação versionável permanece inativa.

## 05 - TrendLens - Trend Engine

O arquivo [05-trend-engine.json](05-trend-engine.json) implementa:

- agregações por categoria, tópico, tipo, formato, hook e origem;
- combinação categoria–formato–origem;
- mediana, P75/P90, taxas de outlier e alto desempenho;
- Consistency Score com pesos e dados ausentes explícitos;
- comparação da janela atual com a anterior equivalente;
- direções `rising`, `stable`, `declining` e `insufficient_data`;
- recálculo idempotente por bucket, retries e erro sanitizado;
- Manual Trigger e Schedule Trigger a cada seis horas, no minuto 30.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL.

A execução integrada final no workflow `WLiCVXsMdALZN6Xq` processou 20 vídeos e persistiu 104 agregações, sem falhas, em 0,102 segundo. A maior dimensão continha quatro vídeos; por isso todas as direções permaneceram `insufficient_data` diante do mínimo de 30. O workflow final possui seis nodes, permanece inativo e não publicado.

## 06 - TrendLens - Monetization Engine

O arquivo [06-monetization-engine.json](06-monetization-engine.json) implementa:

- fatores positivos explicáveis a partir da classificação, duração e engajamento;
- elegibilidade de política por `source_type` configurável;
- adequação a anunciantes e viabilidade de produção por `format` configurável;
- ajuste dos proxies pela confiança da classificação;
- risco combinado de copyright e conteúdo reutilizado;
- Monetization Score versionado de 0 a 10;
- redistribuição explícita do peso de engajamento ausente;
- recálculo idempotente, retries e erro sanitizado;
- Manual Trigger e Schedule Trigger a cada hora, no minuto 20.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL.

A execução integrada final no workflow `oSqF120sKMd9AIh6` processou 15 classificações, persistiu 15 scores, encontrou 14 qualidades de engajamento e 2 riscos combinados altos, sem falhas. O recálculo preservou 15 linhas; os scores ficaram entre 0,9065 e 5,5480 e a execução final terminou em 0,076 segundo. O workflow final possui seis nodes e está publicado e ativo; sua exportação permanece inativa.

## 07 - TrendLens - Opportunity Engine

O arquivo [07-opportunity-engine.json](07-opportunity-engine.json) implementa:

- Opportunity Score com 50% de Virality, 35% de Monetization e 15% de Consistency;
- exigência explícita dos três componentes, sem converter ausência em zero;
- rank denso e percentil por contexto comparável e tipo de dimensão;
- atualização em lote do bucket mais recente do Trend Engine;
- versão de cálculo, instante do recálculo e quantidade de componentes;
- logs de execução e erro sanitizado;
- Manual Trigger e Schedule Trigger a cada seis horas, no minuto 40.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL.

A execução integrada final no workflow `IfeeHrIuecGxlORX` processou 104 agregações e ranqueou 14 linhas de categoria, sem falhas, em 0,070 segundo. Os 104 scores ficaram entre 1,8664 e 6,5374, com média 4,3410 e zero violações de faixa. Os nodes temporários de migration e auditoria foram removidos; o workflow final possui seis nodes, permanece inativo e não publicado.

## 08 - TrendLens - Recommendation AI

O arquivo [08-recommendation-engine.json](08-recommendation-engine.json) implementa:

- seleção idempotente de categorias ranqueadas no bucket mais recente;
- contexto restrito a estatísticas e padrões agregados, sem vídeos individuais;
- geração com NVIDIA Nemotron e prompt versionado;
- síntese, formatos, hooks, riscos e observações de monetização acionáveis;
- validação por JSON Schema e uma tentativa automática de correção;
- persistência dos scores originais, versões e hash da evidência;
- tratamento de conflitos concorrentes, retries e erros sanitizados;
- Manual Trigger e Schedule Trigger a cada seis horas, no minuto 50.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos cinco nodes PostgreSQL e uma credencial `nvidiaApi` aos dois nodes de modelo.

A primeira execução integrada no workflow `wtOD6YTBpRHsHawO` selecionou cinco categorias e criou cinco recomendações, sem falhas. Uma execução concorrente criou mais duas e ignorou três conflitos, confirmando a idempotência da persistência. O fluxo definitivo criou outras cinco recomendações; depois, uma validação limitada criou uma recomendação com o prompt semântico reforçado `v2`.

A auditoria final encontrou 13 recomendações válidas, zero campos de vídeo individual, zero violações de score ou arrays e 13 candidatos ainda pendentes para o prompt atual. O limite de cinco categorias foi restaurado e o workflow temporário foi arquivado. O workflow final possui 13 nodes, permanece inativo e não publicado.

## 09 - TrendLens - Report

O arquivo [09-report.json](09-report.json) implementa:

- relatório semanal determinístico em JSON e Markdown;
- seleção de uma variante regional compatível com o idioma configurado;
- tamanho da amostra, cobertura, período, contexto e versões das fontes;
- Top Opportunities ordenado pelo score persistido;
- seção Viral but Risky com limites configuráveis;
- tendências emergentes restritas à direção `rising`;
- recomendações somente da versão de prompt atual;
- persistência idempotente por hash e versões;
- logs de execução, retries e erro sanitizado;
- Manual Trigger e Schedule Trigger às segundas-feiras, às 08:00.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL.

A execução integrada final no workflow `X3BctkFEVmBRK1e1` analisou seis vídeos e quatro categorias no contexto `youtube/BR/pt-BR`, produziu quatro Top Opportunities, dois casos Viral but Risky e nenhuma tendência emergente com amostra suficiente. O contrato final `v2` foi criado em JSON e Markdown sem falhas em 0,224 segundo; a repetição reutilizou o mesmo registro em 0,145 segundo, confirmando a idempotência. O bootstrap da migration foi removido; o workflow final possui seis nodes, permanece inativo e não publicado.

## 10 - TrendLens - Observability

O arquivo [10-observability.json](10-observability.json) implementa:

- janela fechada e configurável de 24 horas;
- saúde global e por cada workflow produtivo;
- contadores de runs, itens, erros, API, quota e retries;
- duração média e P95 por etapa;
- vídeos coletados, novos e duplicados;
- snapshots e classificações processadas;
- latência média ponderada da classificação;
- distribuição atual de vídeos por categoria;
- vídeos distintos de alta viralidade e categorias de alta oportunidade;
- erros recentes sem mensagem nem metadata;
- persistência JSON idempotente por período, versão e hash;
- Manual Trigger e Schedule Trigger a cada hora, no minuto 5.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL.

A execução integrada final no workflow `J4xto6VE3UahmSmo` analisou 69 runs, 21 eventos de erro e dois retries na janela de 24 horas. Ela contabilizou 25 classificações, 227 snapshots e 31 vídeos distintos de alta viralidade. O estado ficou `critical` por falhas do Snapshot Tracker; seis workflows ficaram saudáveis, Recommendation AI ficou degradado e o collector ficou sem execução na janela.

O bootstrap temporário da migration foi removido. O workflow final possui seis nodes, permanece inativo e não publicado.

## 11 - TrendLens - Phase 12 Validation

O arquivo [11-validation.json](11-validation.json) implementa:

- relatório quantitativo em uma janela fechada de sete dias;
- cobertura de vídeos, classificações, métricas e grupos amostrais;
- qualidade e cadência dos snapshots;
- fila estratificada de 30 classificações para revisão humana;
- quantis, caudas, disponibilidade e correlações dos scores;
- comparação Movie/TV Clips contra cinco categorias obrigatórias;
- portas explícitas antes de qualquer calibração de pesos;
- persistência idempotente e erro sanitizado.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL.

A primeira execução integrada no workflow `sWGVyfbhaiGfanPZ` analisou 210 vídeos, 568 snapshots e 45 classificações. O relatório foi persistido em 0,120 segundo; a repetição reutilizou o mesmo registro em 0,119 segundo. O estado permaneceu `insufficient_data`, pois havia somente 1,236 dia de observação, nenhuma revisão humana e amostras insuficientes nas seis categorias. Nenhum peso foi alterado.

O bootstrap temporário da migration foi removido. O workflow final possui cinco nodes, permanece inativo e não publicado.
