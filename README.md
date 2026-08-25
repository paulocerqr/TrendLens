# TrendLens

Plataforma de inteligência de conteúdo baseada em n8n, PostgreSQL e LLMs para coletar e analisar métricas de vídeos curtos, identificar padrões de viralização e estimar oportunidades de conteúdo considerando engajamento, velocidade de crescimento e elegibilidade de monetização.

## Estado do projeto

As Fases 1 a 11 foram concluídas e a Fase 12 está em validação observacional. O pipeline coleta vídeos, separa idioma observado de mercado-alvo, acompanha snapshots, classifica somente conteúdo linguisticamente elegível, calcula scores, agrega tendências, ranqueia oportunidades, produz recomendações e relatórios e consolida a própria saúde operacional.

A primeira execução da Fase 12 foi concluída tecnicamente, mas retornou `insufficient_data`: o histórico real ainda não atingiu três dias, não há 30 revisões humanas e as seis categorias obrigatórias ainda não possuem amostra 30. Os pesos v1 permanecem inalterados.

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

Depois de atualizar o repositório, aplique as migrations e os seeds idempotentes na ordem abaixo:

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
  < database/migrations/009_opportunity_engine.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/010_recommendation_ai.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/011_report_engine.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/012_observability.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/013_validation.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/014_collection_reliability.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/015_language_eligibility.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/016_global_language_target.sql

docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < database/migrations/017_classifier_reliability.sql

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

Valide o backoff, o limite de tentativas e a fila de revisão manual:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/classifier-reliability.sql
```

Valide o gate de idioma:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/language-eligibility.sql
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

Valide a Fase 12:

```bash
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < tests/sql/validation.sql
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

O collector exportado, sem associações de credenciais, está em [workflows/01-youtube-data-collector.json](workflows/01-youtube-data-collector.json). O workflow do deployment original possui ID `yXv20DXsRyIyoat2` e está publicado e ativo, com coleta a cada três horas no minuto 5 em `America/Sao_Paulo`; a exportação versionável permanece inativa.

O Content Language Gate exportado está em [workflows/01b-content-language-gate.json](workflows/01b-content-language-gate.json). Ele usa metadados públicos para avaliar somente vídeos sem idioma confiável, compara o idioma detectado com o alvo global `pt`, aplica confiança mínima configurável e mantém resultados `uncertain` ou `rejected` fora do classificador. Após a migration corretiva `016`, a execução manual 485 processou 30 vídeos sem falhas: 13 elegíveis exclusivamente em português, sete rejeitados e dez incertos; todos usaram `target_language=pt`. O workflow do deployment original possui ID `1cjqpTWdMiaNzNgU`, usa as credenciais `TrendLens PostgreSQL` e NVIDIA e está publicado e ativo, com execução horária no minuto 15, entre o collector do minuto 5 e o classificador do minuto 30.

O Snapshot Tracker exportado, também sem associações de credenciais, está em [workflows/02-video-snapshot-tracker.json](workflows/02-video-snapshot-tracker.json). Depois da importação, associe `TrendLens PostgreSQL` aos quatro nodes PostgreSQL e a credencial OAuth2 do YouTube ao node HTTP Request. O workflow do deployment original possui ID `LTjMbH3UGW994lCA`, está publicado e ativo e usa backoff auditável para vídeos omitidos por `videos.list`.

O AI Content Classifier exportado, sem associações de credenciais, está em [workflows/03-ai-content-classifier.json](workflows/03-ai-content-classifier.json). Depois da importação, associe `TrendLens PostgreSQL` aos cinco nodes PostgreSQL e a credencial NVIDIA aos dois nodes de modelo. O workflow do deployment original possui ID `86iKeeCFXiiX3fki`, processa até 30 vídeos por hora e possui timeout de 55 minutos. A versão com confiabilidade persistente exige a migration `017`: falhas terminais aguardam 6h e 12h, e a terceira falha sai da fila automática para revisão manual. O draft está salvo no n8n, mas a versão ativa anterior permanece publicada até a aplicação da migration no servidor.

O Metrics Engine exportado está em [workflows/04-metrics-engine.json](workflows/04-metrics-engine.json). A exportação permanece inativa e não contém credenciais; depois da importação, associe `TrendLens PostgreSQL` aos quatro nodes PostgreSQL. O workflow do deployment original possui ID `zf3Wwl1aUINxrGEy` e foi publicado e ativado após validação explícita do usuário.

O Trend Engine exportado está em [workflows/05-trend-engine.json](workflows/05-trend-engine.json). A exportação permanece inativa e não contém credenciais; depois da importação, associe `TrendLens PostgreSQL` aos quatro nodes PostgreSQL. O workflow validado no deployment original possui ID `WLiCVXsMdALZN6Xq`, permanece inativo e não foi publicado.

O Monetization Engine exportado está em [workflows/06-monetization-engine.json](workflows/06-monetization-engine.json). A exportação permanece inativa e não contém credenciais; depois da importação, associe `TrendLens PostgreSQL` aos quatro nodes PostgreSQL. O workflow do deployment original possui ID `oSqF120sKMd9AIh6` e está publicado e ativo.

## Validação do collector

O workflow `01 - TrendLens - YouTube Data Collector` foi testado manualmente antes da publicação. A validação inicial processou quatro combinações de query e grupo amostral:

- 100 resultados recebidos;
- 100 itens processados;
- 99 vídeos novos e 1 duplicado;
- 100 correspondências de proveniência registradas;
- 99 snapshots históricos inseridos;
- 8 chamadas de API e 4 unidades estimadas no bucket de busca;
- nenhum item ignorado e nenhum erro.

Os contadores foram persistidos em `pipeline_runs`. O resultado reflete apenas essa execução de teste e não constitui uma análise de tendências.

Uma nova execução integrada imediatamente anterior à ativação recebeu 100 resultados, processou 98 candidatos, ignorou dois itens e terminou sem falhas em 4,036 segundos. Ela registrou 98 vídeos novos, 98 correspondências e 98 snapshots, com oito chamadas de API e quatro unidades estimadas no bucket de busca. Em seguida, a versão com 17 nodes foi publicada e ativada com Schedule Trigger a cada três horas, no minuto 5, em `America/Sao_Paulo`.

## Política de snapshots

A seleção usa configurações do PostgreSQL:

- vídeos com até 24 horas: intervalo mínimo de 60 minutos;
- vídeos entre 1 e 3 dias: intervalo mínimo de 360 minutos;
- vídeos entre 3 e 7 dias: intervalo mínimo de 1.440 minutos;
- vídeos com mais de 7 dias: fora do acompanhamento ativo;
- no máximo 200 vídeos por execução, respeitando o orçamento de quota configurado.

Quando `videos.list` omite um ID ou não retorna `viewCount`, o estado do vídeo recebe backoff exponencial de 6 horas, 12 horas, 24 horas e assim por diante, limitado a 7 dias. Um retorno válido zera o contador. O evento em `pipeline_errors` preserva o `external_id`, a quantidade de falhas consecutivas e o próximo instante de tentativa.

Esses valores são defaults operacionais e podem ser alterados em `settings`. O Schedule Trigger verifica a fila a cada 15 minutos, mas a decisão de atualizar cada vídeo é tomada pela política armazenada no banco. Como o workflow é exportado inativo, o agendamento não executa até ativação explícita.

## Validação do Snapshot Tracker

A primeira execução manual integrada aplicou a migration, selecionou 149 vídeos vencidos e processou três lotes:

- 149 itens recebidos e processados;
- 149 novos snapshots;
- zero itens ignorados e zero falhas;
- 3 chamadas `videos.list` e 3 unidades estimadas de quota;
- duração total de 1,685 segundo.

Uma segunda execução imediata selecionou zero vídeos, não chamou a API e finalizou com sucesso. Isso confirmou que os snapshots recém-inseridos passaram a controlar corretamente o próximo instante elegível.

Após a migration `014`, uma validação real processou sete candidatos, inseriu seis snapshots e colocou o ID omitido `Pjbm2QB6ktk` em backoff por seis horas. A execução seguinte selecionou zero candidatos e não chamou a API, comprovando que a omissão deixou de reaparecer a cada 15 minutos. A versão final possui nove nodes e está publicada e ativa.

## Classificação estruturada por IA

Antes da classificação temática, o gate de idioma preserva separadamente `api_language`, `target_language` e `detected_language`. Idioma explícito da API é aceito ou rejeitado por correspondência do idioma-base; metadados sem esse sinal entram em uma fila limitada para detecção conservadora por LLM. O mercado `BR` orienta a coleta, mas não é usado como prova de que o vídeo é brasileiro ou de que sua variante é `pt-BR`.

O classificador seleciona no máximo 30 vídeos ainda não processados e com `language_eligibility` no estado `eligible` por execução horária, envia título, descrição truncada e contexto público ao NVIDIA Nemotron e exige uma resposta compatível com JSON Schema. O parser possui uma tentativa automática de correção; falhas remanescentes são sanitizadas e registradas sem bloquear os próximos itens. O timeout de 55 minutos encerra um lote excepcionalmente lento antes do próximo gatilho horário.

Cada classificação persiste categoria, tópico, tipo de conteúdo, formato, hook, origem, estilo de apresentação, confiança e três scores entre 0 e 1. Originalidade, risco autoral e risco de conteúdo reutilizado são estimativas heurísticas, não decisões jurídicas, afirmações de violação ou garantias de monetização. Modelo e versão do prompt são gravados em cada linha para auditoria.

## Validação do AI Content Classifier

A execução manual da revisão final selecionou cinco candidatos e terminou com sucesso:

- 5 itens recebidos;
- 4 novas classificações estruturadas;
- 1 item ignorado porque uma execução concorrente o persistiu primeiro;
- 0 falhas;
- 5 chamadas estimadas ao modelo;
- duração total de 134,315 segundos.

A validação também confirmou a idempotência entre execuções concorrentes: a chave primária de `video_classifications` impediu duplicação e o conflito foi contabilizado como item ignorado. O bootstrap temporário da migration foi removido depois do teste; a versão daquela validação possuía 13 nodes e ainda não estava publicada.

Após a migration `014`, a validação de capacidade selecionou e persistiu 30 classificações, sem falhas ou conflitos, em 218,674 segundos. A média observada de 7,289 segundos por vídeo mantém ampla margem diante do intervalo horário e do timeout de 55 minutos. A nova versão está publicada e ativa.

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

## Validação observacional da Fase 12

O workflow `11 - TrendLens - Phase 12 Validation` persiste um relatório quantitativo e devolve uma fila estratificada de 30 classificações para avaliação humana. Ele audita snapshots, cobertura do classificador, quantis e caudas dos scores, disponibilidade dos componentes e a comparação Movie/TV Clips contra Curiosidades, Tutoriais, Podcast Clips, Tecnologia e Storytelling.

A primeira execução real analisou 210 vídeos e 568 snapshots. Apenas 45 vídeos estavam classificados, o período observado era de 1,236 dia e nenhuma revisão humana havia sido registrada. O componente de outlier estava ausente em todos os 210 Virality Scores e nenhuma categoria comparável atingiu a amostra mínima. O sistema manteve os pesos v1 e registrou a decisão `hold_v1_collect_more_data`.

O procedimento, os resultados reais e o contrato de revisão estão em [docs/validation.md](docs/validation.md).

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
- [Validação da Fase 12](docs/validation.md)
- [Limitações](docs/limitations.md)

## Roadmap resumido

1. Fundação PostgreSQL e conexão com o n8n.
2. Coleta de vídeos e primeiro snapshot.
3. Acompanhamento periódico de snapshots.
4. Classificação estruturada por IA.
5. Métricas e Virality Score.
6. Monetization Score.
7. Tendências, oportunidades, recomendações e relatório.
8. Observabilidade do pipeline.
9. Validação observacional, revisão humana e calibração versionada.

## Licença

Distribuído sob a licença MIT. Consulte [LICENSE](LICENSE).
