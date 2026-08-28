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
- persistência separada do idioma declarado pela API e do idioma-alvo da coleta, sem preencher ausência como `pt`;
- upsert de vídeos, primeiro snapshot e proveniência da amostra;
- logs em `pipeline_runs` e `pipeline_errors` com retries limitados;
- Manual Trigger e Schedule Trigger a cada três horas, no minuto 5.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos nodes PostgreSQL e uma credencial do tipo `youTubeOAuth2Api` aos dois nodes HTTP Request.

O workflow `yXv20DXsRyIyoat2` foi publicado e ativado por solicitação explícita do usuário. O agendamento usa o fuso `America/Sao_Paulo`; sua exportação versionável permanece inativa.

Antes da publicação, a execução integrada final recebeu 100 resultados, processou 98 candidatos e ignorou dois itens, sem falhas. Ela persistiu 98 vídeos novos, 98 correspondências e 98 snapshots em 4,036 segundos, usando oito chamadas de API e quatro unidades estimadas no bucket de busca. A versão publicada possui 17 nodes e um gatilho agendado.

## 01B - TrendLens - Content Language Gate

O arquivo [01b-content-language-gate.json](01b-content-language-gate.json) implementa:

- fila PostgreSQL para vídeos com idioma `uncertain`;
- aceitação direta de códigos `pt` e `pt-*` declarados pela API;
- detecção conservadora por NVIDIA NIM quando o idioma da API estiver ausente;
- requisição JSON ao endpoint compatível com OpenAI da NVIDIA, com raciocínio desativado;
- normalização e validação fechada de idioma, confiança e fonte de evidência;
- confiança mínima, limite de tentativas e backoff configuráveis;
- estados `eligible`, `uncertain` e `rejected`, sem excluir o vídeo bruto;
- logs em `pipeline_runs` e `pipeline_errors`, com mensagens sanitizadas;
- Manual Trigger e Schedule Trigger horário no minuto 5.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos cinco nodes PostgreSQL e uma credencial `nvidiaApi` ao node HTTP Request.

O workflow `1cjqpTWdMiaNzNgU` possui 11 nodes. O fluxo de erro do HTTP, da validação e da persistência retorna ao loop, inclusive quando o provedor falha, garantindo a passagem pelo finalizador. A execução real `1190` processou um candidato em 16,77 segundos, finalizou o `pipeline_run 1128` com zero falhas e confirmou o JSON do modelo `nvidia/nemotron-3-ultra-550b-a55b`. A versão `496fc60f-279b-43fc-88a2-5ce05fc7101c` está publicada e ativa, com execução horária no minuto 15.

## 02 - TrendLens - Video Snapshot Tracker

O arquivo [02-video-snapshot-tracker.json](02-video-snapshot-tracker.json) implementa:

- seleção de vídeos vencidos por política configurável no PostgreSQL;
- faixas de acompanhamento recente, intermediária e antiga;
- limite de vídeos por execução e lotes de até 50 IDs para `videos.list`;
- novos registros imutáveis em `video_snapshots`;
- preservação de `NULL` para likes ou comentários ausentes;
- backoff exponencial e auditável para vídeos omitidos ou sem `viewCount`;
- retries limitados, erros sanitizados e contadores em `pipeline_runs`;
- Manual Trigger para validação e Schedule Trigger de verificação a cada 15 minutos.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos quatro nodes PostgreSQL e uma credencial do tipo `youTubeOAuth2Api` ao node HTTP Request.

O workflow `LTjMbH3UGW994lCA` está publicado e ativo. A exportação versionável permanece inativa.

A validação da migration `014` processou sete candidatos, inseriu seis snapshots e registrou o vídeo omitido `Pjbm2QB6ktk` com backoff de seis horas. Uma segunda execução imediata selecionou zero candidatos e não consumiu quota, confirmando que o ID não voltou à fila. O workflow final possui nove nodes e está publicado e ativo.

## 03 - TrendLens - AI Content Classifier

O arquivo [03-ai-content-classifier.json](03-ai-content-classifier.json) implementa:

- seleção configurável de vídeos do YouTube ainda não classificados e com idioma elegível;
- envio somente dos metadados necessários, com descrição truncada;
- classificação com NVIDIA Nemotron e prompt versionado;
- saída JSON extraída e validada por enums, scores e limites;
- conversão determinística de scores percentuais entre `1–100` para a escala analítica `0–1`;
- persistência tipada em `video_classifications`, sem sobrescrever classificações existentes;
- estimativas separadas de originalidade, risco autoral e conteúdo reutilizado;
- backoff persistente de 6h e 12h para falhas terminais;
- limite inicial de três falhas e encaminhamento para revisão manual;
- erros sanitizados, tentativas auditáveis e contadores em `pipeline_runs`;
- lote configurável de até 30 vídeos por execução;
- Manual Trigger e Schedule Trigger de execução a cada hora, com timeout de 55 minutos.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos cinco nodes PostgreSQL e uma credencial `nvidiaApi` ao node HTTP Request.

O workflow `86iKeeCFXiiX3fki` está publicado e ativo na versão `fd51fd61-0455-4f01-a782-56df3cf6d805`. A exportação versionável permanece inativa.

A primeira execução integrada no workflow `86iKeeCFXiiX3fki` selecionou cinco vídeos, criou quatro classificações e ignorou uma classificação inserida por uma execução concorrente. Terminou com zero falhas em 134,315 segundos. O bootstrap temporário da migration foi removido; a versão daquela validação possuía 13 nodes e ainda não estava publicada.

Após a migration `014`, uma nova execução integrada classificou 30 de 30 candidatos, sem falhas ou conflitos, em 218,674 segundos, com média de 7,289 segundos por vídeo. A migration `017` acrescenta estado durável por vídeo e converte falhas históricas ainda não classificadas para `retry_wait` ou `manual_review`.

A execução manual `703`, já na versão da migration `017`, selecionou 30 candidatos, criou 27 classificações e registrou três falhas de parser ou modelo como primeira tentativa. Cada falha recebeu backoff de seis horas; o fechamento do `pipeline_run 648` mostrou três itens em `retry_wait`, um item histórico em `manual_review` e nenhum encaminhamento manual prematuro. A execução do n8n terminou com status técnico `success`, enquanto o pipeline registrou corretamente `partial`.

A substituição do parser nativo por HTTP Request e validação determinística eliminou a interferência do conteúdo de raciocínio. Depois de reforçar enums e normalizar campos livres para `snake_case`, a execução real `1188` classificou e persistiu um candidato em 21,456 segundos, com zero falhas e passagem pelo finalizador. O workflow final possui 11 nodes.

A execução real `1427` validou a normalização percentual: dez candidatos produziram dez classificações, sem falhas, em 136,626 segundos. Scores já contidos em `0–1` foram preservados; valores maiores que `1` e até `100` foram divididos por `100`; valores negativos, não numéricos ou acima de `100` continuaram inválidos.

Consulte e resolva a fila manual pelo PostgreSQL:

```sql
SELECT *
FROM select_classification_failure_review_candidates(100);

SELECT *
FROM resolve_classification_failure_review(
    1705,
    'retry',
    'reviewer-name',
    'Metadados revisados; liberar novo ciclo.'
);
```

Troque `retry` por `exclude` quando o vídeo deva permanecer armazenado, mas não voltar ao classificador.

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
- validação local de campos obrigatórios, tamanhos, unicidade e limites;
- persistência dos scores originais, versões e hash da evidência;
- tratamento de conflitos concorrentes, retries e erros sanitizados;
- Manual Trigger e Schedule Trigger a cada seis horas, no minuto 50.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos cinco nodes PostgreSQL e uma credencial `nvidiaApi` ao node HTTP Request.

A primeira execução integrada no workflow `wtOD6YTBpRHsHawO` selecionou cinco categorias e criou cinco recomendações, sem falhas. Uma execução concorrente criou mais duas e ignorou três conflitos, confirmando a idempotência da persistência. O fluxo definitivo criou outras cinco recomendações; depois, uma validação limitada criou uma recomendação com o prompt semântico reforçado `v2`.

A auditoria final encontrou 13 recomendações válidas, zero campos de vídeo individual e zero violações de score ou arrays. Com o novo endpoint, a execução real `1189` criou uma recomendação em 34,696 segundos, sem falhas, e finalizou o `pipeline_run 1127`. O limite de categorias foi restaurado; o workflow final possui 11 nodes e está publicado e ativo na versão `ec118010-e9fa-4590-8752-ae4616d1b15b`.

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
- reconciliação de runs `running` obsoletos antes da consulta;
- saúde recovery-aware que preserva falhas históricas sem manter falso crítico após recuperação;
- persistência JSON idempotente por período, versão e hash;
- Manual Trigger e Schedule Trigger a cada hora, no minuto 5.

A exportação não contém associações de credenciais. Depois de importar, atribua `TrendLens PostgreSQL` aos cinco nodes PostgreSQL.

A execução final `1204` reconciliou mais um run obsoleto, analisou 220 runs, preservou 558 eventos de erro e 902 retries históricos e confirmou zero workflows críticos. O estado geral ficou `degraded`, com quatro workflows degradados, cinco saudáveis e um sem execução na janela. O hash retornado e o `source_hash` interno do JSON coincidiram em `0970497ff9e254a66d75d2384840086b`.

O workflow final possui sete nodes e está publicado e ativo na versão `5969fe92-abed-4ab9-a2b8-b31bb7bee55a`; a exportação versionável permanece inativa.

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
