# TrendLens

> **Plataforma de inteligência de conteúdo baseada em n8n, PostgreSQL e LLMs para coletar e analisar métricas de vídeos curtos, identificar padrões de viralização e estimar oportunidades de conteúdo considerando engajamento, velocidade de crescimento e elegibilidade de monetização.**

---

## 1. Objetivo deste documento

Este documento deve servir como **plano de execução para implementação pelo Codex CLI**, utilizando o servidor MCP do n8n já configurado.

O Codex deve utilizar este plano como fonte principal para:

* criar os workflows no n8n;
* criar a estrutura SQL;
* organizar o repositório Git;
* implementar cálculos e regras;
* validar os workflows;
* executar testes;
* documentar decisões;
* exportar os workflows para versionamento no GitHub.

O projeto deve ser implementado incrementalmente. Não criar todos os workflows de uma única vez.

Cada etapa deve estar funcional antes da próxima.

---

# 2. Escopo do MVP

O MVP será focado inicialmente em:

```text
Plataforma:
YouTube

Formato:
vídeos curtos / candidatos a YouTube Shorts

Região:
Brasil

Idioma principal:
Português

Objetivo:
identificar tipos de conteúdo com alto potencial de:
- viralização;
- engajamento;
- crescimento rápido;
- monetização;
- reprodução por novos criadores.
```

TikTok, Instagram Reels e outras plataformas **não fazem parte do MVP**, mas a arquitetura deve permitir adicionar novos adapters posteriormente.

---

# 3. Hipótese inicial do projeto

Uma hipótese inicial a ser testada com dados é:

> Cortes de filmes e séries apresentam alto potencial de viralização no YouTube Shorts, porém podem apresentar baixo potencial de monetização por conta de copyright, conteúdo reutilizado e baixa originalidade.

O TrendLens não deve assumir que essa hipótese é verdadeira.

O objetivo do sistema é **testá-la com dados reais**.

Além de cortes de filmes/séries, inicialmente analisar:

1. cortes de filmes e séries;
2. cortes de podcasts;
3. curiosidades;
4. tecnologia;
5. games;
6. humor;
7. tutoriais rápidos;
8. esportes;
9. storytelling;
10. conteúdo motivacional.

As categorias devem ser extensíveis.

---

# 4. O que o TrendLens deve responder

Ao final do MVP, o sistema deve conseguir responder perguntas como:

* Quais tipos de conteúdo estão crescendo mais rápido?
* Quais categorias apresentam maior engajamento?
* Quais formatos conseguem viralizar em canais pequenos?
* Qual é a velocidade média de crescimento dos vídeos de determinado nicho?
* Quais formatos apresentam maior quantidade de outliers?
* Quais categorias possuem grande quantidade de vídeos acima de 100 mil ou 1 milhão de views?
* Quais tipos de conteúdo viralizam, mas possuem alto risco para monetização?
* Quais formatos combinam viralidade e potencial de monetização?
* Que tipo de conteúdo um novo criador poderia produzir?
* Quais características aparecem repetidamente nos vídeos de melhor desempenho?

O sistema deve diferenciar:

```text
"Isso viraliza"
```

de:

```text
"Isso representa uma boa oportunidade de conteúdo monetizável"
```

---

# 5. Arquitetura geral

```text
                         YouTube Data API
                                |
                                v
                    +------------------------+
                    | 01 - Data Collector    |
                    +-----------+------------+
                                |
                                v
                         PostgreSQL
                                |
                                v
                    +------------------------+
                    | 02 - Snapshot Tracker  |
                    +-----------+------------+
                                |
                                v
                    +------------------------+
                    | 03 - AI Classifier     |
                    +-----------+------------+
                                |
                                v
                    +------------------------+
                    | 04 - Metrics Engine    |
                    |                        |
                    | engagement             |
                    | velocity               |
                    | outlier                |
                    | virality               |
                    +-----------+------------+
                                |
                                v
                    +------------------------+
                    | 05 - Trend Engine      |
                    +-----------+------------+
                                |
                                v
                    +------------------------+
                    | 06 - Monetization      |
                    |      Engine            |
                    +-----------+------------+
                                |
                                v
                    +------------------------+
                    | 07 - Opportunity       |
                    |      Engine            |
                    +-----------+------------+
                                |
                                v
                    +------------------------+
                    | 08 - Recommendation AI |
                    +-----------+------------+
                                |
                   +------------+-------------+
                   |                          |
                   v                          v
             PostgreSQL                Report / API
```

---

# 6. Princípios técnicos

O Codex deve seguir estes princípios durante toda a implementação.

* Usar nodes nativos do n8n sempre que possível.
* Evitar `Code` nodes quando uma operação puder ser feita de forma clara com nodes nativos.
* Usar `Code` apenas quando o cálculo ou transformação justificar.
* Manter workflows pequenos e especializados.
* Nunca colocar API Keys diretamente nos workflows.
* Utilizar Credentials do n8n.
* Todos os workflows devem possuir tratamento de erro.
* Todos os workflows devem produzir logs de execução.
* Não apagar workflows sem autorização.
* Não ativar workflows automaticamente durante desenvolvimento.
* Sempre validar o workflow após alterações.
* Executar testes quando possível.
* Não coletar nem armazenar dados privados.
* Utilizar somente informações públicas obtidas por APIs ou fontes permitidas.
* Não fazer download ou redistribuição dos vídeos.
* Não armazenar conteúdo protegido desnecessariamente.
* Não implementar scraping do TikTok neste MVP.

---

# 7. Estrutura do repositório

Criar:

```text
trendlens/
│
├── README.md
│
├── LICENSE
├── .gitignore
├── .env.example
│
├── workflows/
│   ├── 01-youtube-data-collector.json
│   ├── 02-video-snapshot-tracker.json
│   ├── 03-ai-content-classifier.json
│   ├── 04-metrics-engine.json
│   ├── 05-trend-engine.json
│   ├── 06-monetization-engine.json
│   ├── 07-opportunity-engine.json
│   └── 08-recommendation-engine.json
│
├── database/
│   ├── schema.sql
│   ├── indexes.sql
│   └── seeds/
│       └── categories.sql
│
├── infra/
│   └── compose.yaml
│
├── docs/
│   ├── architecture.md
│   ├── scoring.md
│   ├── data-model.md
│   ├── methodology.md
│   ├── limitations.md
│   └── images/
│
├── examples/
│   ├── raw-video.json
│   ├── classified-video.json
│   ├── recommendation.json
│   └── report.json
│
└── tests/
    ├── fixtures/
    └── expected-results/
```

---

# 8. Banco de dados

Usar PostgreSQL.

Preferencialmente criar um banco exclusivo:

```text
trendlens
```

Não utilizar o banco interno do n8n como banco de dados da aplicação.

---

# 9. Tabela `videos`

Criar tabela:

```text
videos
```

Campos mínimos:

```text
id
platform
external_id

channel_id
channel_name

title
description
url

published_at
duration_seconds

language
region

short_confidence

created_at
updated_at
```

Regras:

```text
platform + external_id
```

deve ser único.

Exemplo:

```json
{
  "platform": "youtube",
  "external_id": "abc123",
  "channel_id": "channel123",
  "title": "3 curiosidades sobre...",
  "url": "https://youtube.com/shorts/...",
  "duration_seconds": 42,
  "language": "pt",
  "region": "BR"
}
```

---

# 10. Identificação de candidatos a Shorts

A API pública do YouTube não deve ser tratada como se fornecesse uma flag perfeita `isShort`.

Criar:

```text
short_confidence
```

com valores:

```text
high
medium
low
```

Usar sinais como:

* duração;
* presença de `#shorts`;
* padrões da URL quando disponíveis;
* metadados;
* outros sinais confiáveis disponíveis.

No MVP, considerar prioritariamente vídeos com:

```text
duration <= 180 segundos
```

Não afirmar que todo vídeo curto é obrigatoriamente um Short.

---

# 11. Tabela `video_snapshots`

Criar:

```text
video_snapshots
```

Campos:

```text
id
video_id

collected_at

views
likes
comments

created_at
```

Futuramente outras plataformas poderão acrescentar:

```text
shares
favorites
reposts
```

O YouTube MVP não deve inventar métricas que a API não fornecer.

---

# 12. Por que snapshots são obrigatórios

Não basta armazenar:

```text
1.000.000 views
```

Precisamos saber **quanto tempo levou para chegar lá**.

Exemplo:

```text
10:00 → 20.000 views
16:00 → 70.000 views
22:00 → 230.000 views
10:00 → 810.000 views
```

Com isso calcular:

```text
View Velocity
```

e futuramente:

```text
View Acceleration
```

---

# 13. Tabela `video_classifications`

Criar:

```text
video_classifications
```

Campos:

```text
video_id

topic
content_type
format
hook_type
source_type
presentation_style

originality_score
copyright_risk
reused_content_risk

ai_confidence

classification_model
classified_at
```

Valores devem ser estruturados.

---

# 14. Classificação por IA

Usar inicialmente um modelo acessível via NVIDIA NIM ou outro LLM configurado no n8n.

O LLM deve retornar **JSON estruturado**.

Exemplo:

```json
{
  "topic": "cinema",
  "content_type": "movie_clip",
  "format": "curiosity",
  "hook_type": "curiosity_gap",
  "source_type": "third_party_content",
  "presentation_style": "clip_with_subtitles",

  "originality_score": 0.25,
  "copyright_risk": 0.9,
  "reused_content_risk": 0.9,

  "confidence": 0.86
}
```

Outro exemplo:

```json
{
  "topic": "technology",
  "content_type": "educational",
  "format": "explainer",
  "hook_type": "question",
  "source_type": "original",
  "presentation_style": "voice_over",

  "originality_score": 0.9,
  "copyright_risk": 0.05,
  "reused_content_risk": 0.1,

  "confidence": 0.93
}
```

---

# 15. Importante sobre a IA

O LLM não deve afirmar:

```text
"Este vídeo viola copyright."
```

Ele deve produzir uma estimativa:

```text
copyright_risk = high
```

ou:

```text
copyright_risk = 0.85
```

O mesmo vale para monetização.

O TrendLens fornece **indicadores heurísticos**, não decisões oficiais das plataformas.

---

# 16. Categorias de `source_type`

Inicialmente suportar:

```text
original
third_party_content
movie_or_tv_clip
podcast_clip
gameplay
stock_media
user_generated
compilation
reaction
unknown
```

---

# 17. Tipos de formato

Inicialmente:

```text
explainer
curiosity
tutorial
storytelling
reaction
clip
ranking
news
meme
comparison
motivation
commentary
compilation
unknown
```

---

# 18. Hooks

Exemplos:

```text
question
curiosity_gap
controversy
surprising_fact
promise
fear
challenge
before_after
story
list
direct_statement
unknown
```

---

# 19. Coleta de dados

Criar workflow:

```text
01 - YouTube Data Collector
```

Responsabilidades:

1. definir janela de coleta;
2. consultar vídeos;
3. coletar detalhes;
4. filtrar candidatos a vídeos curtos;
5. normalizar dados;
6. evitar duplicatas;
7. inserir novos vídeos;
8. registrar primeiro snapshot;
9. registrar execução.

---

# 20. Estratégia de coleta

Não coletar apenas vídeos já virais.

Isso causaria viés.

Utilizar dois grupos.

## Grupo A — Recentes

Vídeos recentes relacionados aos nichos analisados.

Objetivo:

```text
criar baseline
```

## Grupo B — Alto desempenho

Vídeos com grande quantidade de visualizações dentro da janela pesquisada.

Objetivo:

```text
encontrar padrões de viralização
```

Depois comparar:

```text
viral sample
vs
baseline sample
```

---

# 21. Queries iniciais

Criar uma tabela configurável:

```text
collection_queries
```

Exemplos:

```text
filme
série
corte podcast
curiosidades
tecnologia
games
humor
tutorial
motivação
futebol
```

Não deixar queries fixadas diretamente no workflow.

---

# 22. Snapshot Tracker

Criar:

```text
02 - Video Snapshot Tracker
```

Execução periódica.

Selecionar vídeos ainda relevantes para acompanhamento.

Atualizar:

```text
views
likes
comments
```

Criar novo registro em:

```text
video_snapshots
```

Não atualizar o snapshot anterior.

Snapshots devem ser históricos.

---

# 23. Política de acompanhamento

Exemplo inicial:

```text
vídeos <= 24h:
coleta frequente

1–3 dias:
frequência intermediária

3–7 dias:
frequência menor

> 7 dias:
encerrar acompanhamento ativo
```

Valores exatos devem ficar configuráveis.

---

# 24. Métricas fundamentais

O Metrics Engine deve calcular pelo menos:

```text
Like Rate
Comment Rate
Engagement Rate
View Velocity
Relative Performance
Outlier Score
Virality Score
```

---

# 25. Like Rate

```text
likes
────────
views
```

Tratar divisão por zero.

---

# 26. Comment Rate

```text
comments
────────
 views
```

---

# 27. Engagement Rate

Não depender apenas de likes.

Versão inicial:

```text
likes + (comments × COMMENT_WEIGHT)
──────────────────────────────────
               views
```

`COMMENT_WEIGHT` deve ser configurável.

Valor inicial sugerido:

```text
3
```

Isso não deve ser apresentado como verdade científica.

É uma escolha de modelagem ajustável.

---

# 28. View Velocity

```text
views_atual - views_anterior
────────────────────────────
       horas_decorridas
```

Unidade:

```text
views/hour
```

---

# 29. View Acceleration

Pode ser implementada após o View Velocity estar estável.

```text
velocity_atual - velocity_anterior
─────────────────────────────────
          horas_decorridas
```

Ajuda a diferenciar:

```text
vídeo crescendo
```

de:

```text
vídeo já desacelerando
```

---

# 30. Outlier Score

Objetivo:

detectar vídeos que performam muito acima do desempenho típico do próprio canal.

Versão inicial:

```text
views_do_video
─────────────────────────
mediana_recente_do_canal
```

Exemplo:

```text
views vídeo = 2.400.000
mediana canal = 30.000

outlier = 80x
```

Para canais sem histórico suficiente:

```text
outlier_score = null
```

Não fabricar baseline.

---

# 31. Percentis

Sempre que possível, converter métricas para percentis dentro de contextos comparáveis.

Exemplo:

```text
categoria = technology
janela = 7 dias
região = BR

video_velocity_percentile = 0.96
```

Isso significa:

```text
melhor que aproximadamente 96% da amostra analisada
```

Percentis serão particularmente importantes quando novas plataformas forem adicionadas.

---

# 32. Virality Score

Criar score:

```text
0–10
```

O score deve ser baseado principalmente em dados observados.

Versão inicial sugerida:

```text
35% View Velocity Percentile
20% Engagement Percentile
20% Outlier Percentile
15% Views Percentile
10% Freshness
```

Formalmente:

```text
virality_raw =
    0.35 * velocity_percentile
  + 0.20 * engagement_percentile
  + 0.20 * outlier_percentile
  + 0.15 * views_percentile
  + 0.10 * freshness_score
```

Depois:

```text
Virality Score = virality_raw × 10
```

Se não houver Outlier Score, redistribuir o peso de forma documentada ou usar uma estratégia explícita de dados ausentes.

Nunca substituir valor ausente por zero sem justificativa.

---

# 33. Interpretação do Virality Score

```text
0–3
baixo desempenho

3–5
normal

5–7
acima da média

7–8.5
forte

8.5–10
viral / outlier
```

Essas faixas são heurísticas e podem ser recalibradas.

---

# 34. Monetization Score

Criar:

```text
Monetization Score
```

Escala:

```text
0–10
```

Ele NÃO representa:

```text
"quanto dinheiro esse conteúdo irá gerar"
```

Ele representa:

> quão favorável parece ser aquele formato para um criador produzir conteúdo com possibilidade de monetização sustentável.

---

# 35. Fatores positivos do Monetization Score

Utilizar:

```text
Originality
Policy Eligibility
Advertiser Suitability
Production Feasibility
Engagement Quality
```

Todos normalizados entre:

```text
0 e 1
```

---

# 36. Fatores de risco

Separadamente calcular:

```text
Copyright Risk
Reused Content Risk
```

Também:

```text
0–1
```

Onde:

```text
0 = baixo risco
1 = alto risco
```

---

# 37. Fórmula inicial do Monetization Score

Base:

```text
base =
    0.30 * originality
  + 0.25 * policy_eligibility
  + 0.15 * advertiser_suitability
  + 0.15 * production_feasibility
  + 0.15 * engagement_quality
```

Penalidade:

```text
risk =
    0.60 * copyright_risk
  + 0.40 * reused_content_risk
```

Resultado:

```text
monetization_raw =
    base * max(0, 1 - risk)
```

Depois:

```text
Monetization Score =
    monetization_raw * 10
```

---

# 38. Exemplo conceitual

## Corte de filme

```text
Originality             0.20
Policy Eligibility      0.30
Advertiser Suitability  0.70
Production Feasibility  0.90
Engagement Quality      0.80

Copyright Risk          0.95
Reused Content Risk     0.95
```

É possível obter:

```text
Virality Score       alto
Monetization Score   baixo
```

Este é um resultado válido e desejável.

---

# 39. Opportunity Score

Esse deverá ser o principal ranking exibido ao usuário.

Escala:

```text
0–10
```

Versão inicial:

```text
50% Virality Score
35% Monetization Score
15% Consistency Score
```

Normalizando previamente para `0–1`.

```text
opportunity_raw =
    0.50 * virality
  + 0.35 * monetization
  + 0.15 * consistency
```

Depois:

```text
Opportunity Score =
    opportunity_raw * 10
```

---

# 40. Consistency Score

Não queremos recomendar um formato apenas porque **um vídeo isolado viralizou**.

Calcular consistência por categoria/formato.

Exemplo:

```text
quantidade de vídeos analisados
percentual acima do P75
percentual acima do P90
mediana de engagement
dispersão dos resultados
```

Alta consistência significa:

```text
vários vídeos apresentam bom desempenho
```

Baixa consistência:

```text
um vídeo gigante e dezenas de fracassos
```

---

# 41. Saturation Score

Implementar se houver dados suficientes.

Objetivo:

estimar saturação.

Exemplo:

```text
muitos criadores
+
muitos uploads
+
baixo crescimento médio
=
alta saturação
```

Escala:

```text
0 = baixa saturação
1 = alta saturação
```

Depois poderá entrar na V2 do Opportunity Score.

---

# 42. Trend Engine

Criar:

```text
05 - Trend Engine
```

Agrupar por:

```text
topic
content_type
format
hook_type
source_type
```

E calcular:

```text
video_count

median_views
p75_views
p90_views

median_engagement
median_velocity
median_virality

outlier_count
outlier_rate

high_performance_rate
```

---

# 43. Trend temporal

Comparar janelas.

Exemplo:

```text
últimas 24h
vs
7 dias

7 dias
vs
30 dias
```

Criar:

```text
trend_direction
```

Valores:

```text
rising
stable
declining
insufficient_data
```

---

# 44. AI Recommendation Engine

Criar:

```text
08 - Recommendation Engine
```

O LLM NÃO deve simplesmente analisar vídeos individuais.

Ele deve receber **estatísticas agregadas**.

Exemplo:

```json
{
  "category": "cinema_curiosity",
  "sample_size": 842,
  "median_views": 184000,
  "median_engagement_rate": 0.068,
  "median_virality_score": 7.9,
  "median_monetization_score": 8.4,
  "outlier_rate": 0.142,
  "trend": "rising"
}
```

---

# 45. Saída do Recommendation Engine

JSON estruturado:

```json
{
  "category": "Curiosidades sobre cinema",

  "opportunity_score": 8.7,

  "evidence": {
    "sample_size": 842,
    "median_views": 184000,
    "median_engagement_rate": 0.068,
    "outlier_rate": 0.142
  },

  "recommended_formats": [
    "curiosidades narradas",
    "detalhes escondidos",
    "explicações de cenas",
    "bastidores"
  ],

  "common_hooks": [
    "Você nunca percebeu isso...",
    "Existe um detalhe nessa cena..."
  ],

  "monetization_notes": [
    "Priorizar roteiro e narração originais",
    "Evitar republicação direta de cenas"
  ]
}
```

---

# 46. Regra essencial para recomendações

O sistema deve aprender o **padrão**, e não incentivar a cópia de um vídeo específico.

Errado:

```text
Copie este vídeo.
```

Correto:

```text
Vídeos com curiosidade + narração + hook de surpresa
apresentam desempenho acima da média.
```

---

# 47. Recomendações de cinema

Um caso esperado é:

```text
Cortes de filmes
Virality Score: alto
Monetization Score: baixo
```

O Recommendation Engine pode transformar esse insight em:

```text
Existe forte interesse por cinema.

Em vez de simplesmente republicar cenas,
formatos originais relacionados ao mesmo interesse
apresentam melhor perfil de monetização.

Sugestões:

- curiosidades;
- detalhes escondidos;
- análise de cenas;
- explicação de finais;
- bastidores;
- ranking comentado;
- erros de continuidade.
```

---

# 48. Dados reais vs IA

A IA nunca deve inventar métricas.

Toda afirmação quantitativa deve vir do PostgreSQL.

Errado:

```text
"Esse formato cresce 40% mais rápido."
```

sem cálculo real.

Correto:

```text
median_velocity = 18.234 views/h
```

seguido por interpretação da IA.

---

# 49. Tabela `category_statistics`

Criar:

```text
category_statistics
```

Campos possíveis:

```text
id

period_start
period_end

topic
content_type
format

sample_size

median_views
p75_views
p90_views

median_engagement
median_velocity

median_virality
median_monetization

outlier_rate
high_performance_rate

consistency_score
opportunity_score

trend_direction

created_at
```

---

# 50. Tabela `recommendations`

Criar:

```text
recommendations
```

Campos:

```text
id

category
generated_at

opportunity_score
virality_score
monetization_score

summary

recommended_formats
recommended_hooks

risks
monetization_notes

evidence_json
model
```

---

# 51. Observabilidade

Criar:

```text
pipeline_runs
```

Campos:

```text
id
workflow
started_at
finished_at
status

items_received
items_processed
items_skipped
items_failed

duration_seconds
```

---

# 52. Erros

Criar:

```text
pipeline_errors
```

Campos:

```text
id
workflow
node

timestamp

error_type
error_message

external_id

retry_count

metadata
```

Nunca persistir secrets no erro.

---

# 53. Retentativas

Para requisições HTTP:

```text
429
→ Wait
→ Retry

5xx
→ Retry com backoff

4xx definitivo
→ log
→ não repetir indefinidamente
```

Implementar limites de retentativa.

---

# 54. Controle de quota

YouTube API possui limites.

O collector deve:

* minimizar chamadas;
* evitar consultar novamente dados imutáveis;
* fazer batch quando possível;
* registrar quantidade de chamadas;
* permitir configurar quantidade de queries;
* permitir configurar quantidade máxima de resultados;
* interromper coleta de forma controlada se necessário.

---

# 55. Configurações

Não fixar valores importantes nos workflows.

Criar configuração para:

```text
REGION
LANGUAGE

COLLECTION_WINDOW_HOURS

MAX_RESULTS_PER_QUERY

SHORT_MAX_DURATION

SNAPSHOT_ACTIVE_DAYS

COMMENT_WEIGHT

LLM_MODEL

MIN_SAMPLE_SIZE

REPORT_PERIOD
```

Pode ser implementado por:

* environment variables;
* Data Tables do n8n;
* tabela PostgreSQL `settings`.

Preferência:

```text
configuração operacional no PostgreSQL
+
secrets no n8n Credentials
```

---

# 56. Workflow de relatório

Depois do Recommendation Engine, criar relatório.

Inicialmente pode gerar:

```text
JSON
+
Markdown
```

Exemplo:

```text
TrendLens — Relatório Semanal

Período:
14/08/2026 → 21/08/2026

Vídeos analisados:
8.432

TOP OPORTUNIDADES

1. Curiosidades de tecnologia

Opportunity Score: 8.9
Virality: 8.7
Monetization: 9.1

Amostra: 943 vídeos
Mediana: 182k views
Outlier rate: 17%

Padrões observados:
- pergunta inicial;
- 30–50 segundos;
- narração;
- legendas;
- curiosidade.

2. Storytelling de cinema
...
```

---

# 57. Endpoint do MVP

Depois dos workflows internos estarem funcionando, criar opcionalmente:

```text
GET /webhook/trendlens/recommendations
```

ou equivalente via webhook n8n.

Suportar filtros:

```text
category
period
minimum_opportunity_score
```

Resposta JSON.

Não implementar autenticação complexa inicialmente; se o endpoint for publicado, protegê-lo adequadamente antes de exposição real.

---

# 58. Testes obrigatórios

Criar fixtures para pelo menos:

```text
vídeo normal
vídeo viral
vídeo sem likes
vídeo sem comentários
vídeo recém-publicado
vídeo antigo
canal sem baseline
movie clip
tutorial original
podcast clip
```

---

# 59. Testar divisão por zero

As métricas nunca devem falhar quando:

```text
views = 0
```

---

# 60. Testar dados ausentes

Exemplo:

```text
likes = null
comments = null
```

Não assumir automaticamente:

```text
null = 0
```

sem regra explícita.

---

# 61. Testar classificação LLM

O parser deve rejeitar respostas fora do schema.

Se a IA retornar:

```text
texto livre inválido
```

o workflow deve:

```text
retry
```

e, se continuar falhando:

```text
registrar erro
```

---

# 62. Testar scores

Criar casos conhecidos.

Exemplo:

```text
Video A
velocity extremamente alta
engagement alto
outlier alto
```

deve produzir Virality Score maior que:

```text
Video B
velocity baixa
engagement baixo
```

---

# 63. Avaliação do classificador

Separar uma pequena amostra manual.

Exemplo:

```text
100 vídeos
```

Classificar manualmente:

```text
movie_clip
tutorial
podcast_clip
curiosity
etc.
```

Comparar com classificação da IA.

Documentar:

```text
accuracy aproximada
erros mais comuns
categorias ambíguas
```

---

# 64. Limitações metodológicas

Documentar explicitamente:

* não temos acesso ao algoritmo interno do YouTube;
* views não significam receita;
* classificação de monetização é heurística;
* análise de copyright é risco estimado;
* não conhecemos receita real dos criadores;
* candidatos a Shorts podem conter falsos positivos;
* amostras vindas de queries podem introduzir viés;
* performance varia por região;
* performance varia ao longo do tempo;
* correlação não implica causalidade.

---

# 65. Não comparar plataformas diretamente

Quando TikTok for implementado futuramente:

```text
1 milhão de views no YouTube
```

não deve ser tratado automaticamente como equivalente a:

```text
1 milhão de views no TikTok
```

Usar:

```text
percentis por plataforma
```

antes de comparações.

---

# 66. Roadmap

## V1 — MVP

```text
YouTube
↓
PostgreSQL
↓
Snapshots
↓
AI Classification
↓
Metrics
↓
Virality Score
↓
Monetization Score
↓
Opportunity Score
↓
Recommendations
```

## V2

```text
melhor detecção de tendências
saturation score
dashboard
histórico
melhores visualizações
```

## V3

```text
TikTok via fonte autorizada
```

## V4

```text
Instagram Reels
```

## V5

```text
RAG sobre histórico de tendências
```

Permitir consultas como:

```text
"Quais formatos relacionados a games cresceram mais
nos últimos três meses?"
```

---

# 67. Ordem exata de implementação

O Codex deve seguir esta ordem.

## Fase 1 — Fundação

* [ ] Criar estrutura do repositório.
* [ ] Criar `.gitignore`.
* [ ] Criar `.env.example`.
* [ ] Criar PostgreSQL do projeto.
* [ ] Criar schema inicial.
* [ ] Criar indexes.
* [ ] Criar seeds de categorias.
* [ ] Testar conexão n8n → PostgreSQL.

**Definition of Done:**

```text
n8n consegue inserir e consultar dados no PostgreSQL.
```

---

## Fase 2 — YouTube Collector

* [ ] Configurar YouTube Data API Credential.
* [ ] Criar tabela de queries.
* [ ] Criar workflow `01 - YouTube Data Collector`.
* [ ] Implementar coleta.
* [ ] Implementar normalização.
* [ ] Implementar duração.
* [ ] Implementar short confidence.
* [ ] Implementar deduplicação.
* [ ] Salvar `videos`.
* [ ] Salvar primeiro snapshot.
* [ ] Implementar logs.

**Definition of Done:**

```text
O PostgreSQL contém vídeos reais e métricas reais do YouTube.
```

---

## Fase 3 — Snapshot Tracker

* [ ] Criar workflow `02 - Video Snapshot Tracker`.
* [ ] Selecionar vídeos ativos.
* [ ] Consultar métricas novamente.
* [ ] Salvar novos snapshots.
* [ ] Não alterar snapshots anteriores.
* [ ] Implementar retries.

**Definition of Done:**

```text
Um mesmo vídeo possui múltiplos snapshots ao longo do tempo.
```

---

## Fase 4 — AI Classification

* [ ] Criar schema estruturado.
* [ ] Configurar LLM.
* [ ] Criar workflow `03 - AI Content Classifier`.
* [ ] Classificar vídeos ainda não processados.
* [ ] Validar JSON.
* [ ] Registrar confidence.
* [ ] Registrar modelo utilizado.
* [ ] Persistir resultado.

**Definition of Done:**

```text
Os vídeos possuem tipo, formato, hook e source_type estruturados.
```

---

## Fase 5 — Metrics Engine

* [ ] Implementar Like Rate.
* [ ] Implementar Comment Rate.
* [ ] Implementar Engagement Rate.
* [ ] Implementar View Velocity.
* [ ] Implementar baseline do canal.
* [ ] Implementar Outlier Score.
* [ ] Implementar percentis.
* [ ] Implementar Virality Score.

**Definition of Done:**

```text
Cada vídeo elegível possui métricas derivadas e Virality Score.
```

---

## Fase 6 — Monetization Engine

* [ ] Criar fatores positivos.
* [ ] Criar copyright risk.
* [ ] Criar reused content risk.
* [ ] Criar policy eligibility.
* [ ] Criar production feasibility.
* [ ] Implementar fórmula.
* [ ] Persistir Monetization Score.
* [ ] Documentar critérios.

**Definition of Done:**

```text
Cada classificação possui estimativa de Monetization Score explicável.
```

---

## Fase 7 — Trend Engine

* [ ] Agrupar por categoria.
* [ ] Agrupar por formato.
* [ ] Agrupar por source type.
* [ ] Calcular medianas.
* [ ] Calcular P75/P90.
* [ ] Calcular outlier rate.
* [ ] Calcular consistency.
* [ ] Calcular tendência.
* [ ] Salvar `category_statistics`.

**Definition of Done:**

```text
TrendLens consegue comparar formatos usando estatísticas agregadas.
```

---

## Fase 8 — Opportunity Engine

* [ ] Combinar Virality.
* [ ] Combinar Monetization.
* [ ] Combinar Consistency.
* [ ] Calcular Opportunity Score.
* [ ] Rankear categorias.

**Definition of Done:**

```text
Existe ranking objetivo de oportunidades.
```

---

## Fase 9 — Recommendation AI

* [ ] Criar workflow.
* [ ] Fornecer apenas dados agregados.
* [ ] Gerar explicações.
* [ ] Gerar formatos sugeridos.
* [ ] Gerar hooks sugeridos.
* [ ] Gerar riscos.
* [ ] Gerar observações de monetização.
* [ ] Persistir recomendações.

**Definition of Done:**

```text
TrendLens converte estatísticas em recomendações acionáveis.
```

---

## Fase 10 — Report

* [ ] Gerar relatório Markdown.
* [ ] Gerar JSON.
* [ ] Mostrar tamanho da amostra.
* [ ] Mostrar evidências.
* [ ] Mostrar Top Opportunities.
* [ ] Mostrar Viral but Risky.
* [ ] Mostrar tendências emergentes.

**Definition of Done:**

```text
Uma pessoa consegue entender as melhores oportunidades sem abrir o banco.
```

---

## Fase 11 — Observabilidade

* [ ] `pipeline_runs`.
* [ ] `pipeline_errors`.
* [ ] retries.
* [ ] contadores.
* [ ] duração.
* [ ] quantidade coletada.
* [ ] quantidade classificada.
* [ ] quantidade com erro.

---

## Fase 12 — Validação

* [ ] Rodar coleta real por alguns dias.
* [ ] Verificar snapshots.
* [ ] Avaliar classificador manualmente.
* [ ] Revisar scores.
* [ ] Detectar distorções.
* [ ] Ajustar pesos.
* [ ] Documentar alterações.

---

# 68. Métricas do próprio pipeline

O sistema deve conseguir reportar:

```text
Videos collected
New videos
Duplicate videos
Snapshots collected

AI classifications
Classification errors

Average classification latency

API errors
Retries

Videos by category

High virality videos

High opportunity categories
```

---

# 69. Primeira análise importante

Quando houver dados suficientes, executar uma análise específica:

## Movie/TV Clips vs outros formatos

Comparar:

```text
sample size
median views
P75
P90
median velocity
median engagement
outlier rate
Virality Score
Monetization Score
Opportunity Score
```

Comparar contra pelo menos:

```text
Curiosidades
Tutoriais
Podcast Clips
Tecnologia
Storytelling
```

Objetivo:

testar quantitativamente a hipótese inicial.

---

# 70. Resultado esperado

O sistema deve ser capaz de produzir algo equivalente a:

```text
CATEGORY
Movie / TV Clips

Sample size:
1.284

Median Views:
312.450

Median Engagement:
5.9%

Outlier Rate:
18.2%

Virality:
9.1 / 10

Monetization:
2.8 / 10

Opportunity:
5.7 / 10


INTERPRETATION

Conteúdos baseados em cenas de filmes apresentam forte
capacidade de viralização na amostra analisada.

Entretanto, riscos relacionados a conteúdo reutilizado
e direitos autorais reduzem significativamente sua
atratividade como estratégia de monetização.


ALTERNATIVE OPPORTUNITIES

Cinema Curiosities:
8.6

Movie Commentary:
8.3

Movie Storytelling:
8.1
```

Todos os números devem vir de dados reais.

---

# 71. GitHub e documentação

O README final deve apresentar:

1. problema;
2. solução;
3. arquitetura;
4. tecnologias;
5. metodologia de coleta;
6. metodologia dos scores;
7. modelo de dados;
8. screenshots dos workflows;
9. exemplo real de análise;
10. como executar;
11. como configurar credenciais;
12. limitações;
13. decisões técnicas;
14. roadmap.

---

# 72. Tecnologias que devem aparecer no projeto

```text
n8n
PostgreSQL
Docker
REST APIs
YouTube Data API
LLM
NVIDIA NIM, se utilizado
SQL
MCP
Codex CLI
Cloudflare Tunnel
Caddy
Git
GitHub
```

Cloudflare e Caddy devem ser documentados como infraestrutura de deployment, não como dependências obrigatórias para quem executar localmente.

---

# 73. Ambiente reproduzível

O GitHub deve fornecer uma configuração simplificada:

```bash
docker compose up -d
```

para PostgreSQL e dependências necessárias.

O usuário que clonar o projeto não deve depender de:

```text
utileasy.com.br
```

ou da infraestrutura particular do servidor original.

---

# 74. Segurança

Nunca versionar:

```text
.env
API Keys
OAuth tokens
Google credentials
NVIDIA token
n8n encryption key
Cloudflare token
senhas PostgreSQL reais
```

Fornecer somente:

```text
.env.example
```

---

# 75. Commits

O Codex deve preferir commits pequenos e descritivos.

Exemplos:

```text
feat: add YouTube video collector workflow

feat: add video snapshot tracking

feat: implement engagement metrics

feat: add AI content classifier

feat: implement virality score

feat: implement monetization score

feat: add opportunity ranking

docs: document scoring methodology
```

---

# 76. Regra de desenvolvimento com MCP

Quando o Codex criar ou editar workflows através do MCP:

1. inspecionar antes o estado atual;
2. criar uma mudança limitada;
3. validar;
4. executar teste;
5. analisar saída;
6. corrigir se necessário;
7. somente depois seguir para a próxima funcionalidade.

Não construir todo o projeto em uma única chamada.

---

# 77. Critério final de sucesso do MVP

O MVP estará concluído quando for possível executar:

```text
Coleta de vídeos reais
        ↓
Snapshots
        ↓
Classificação por IA
        ↓
Cálculo de métricas
        ↓
Virality Score
        ↓
Monetization Score
        ↓
Opportunity Score
        ↓
Ranking por categoria
        ↓
Recomendações
        ↓
Relatório
```

e obter uma análise baseada em dados reais capaz de responder:

> **Quais tipos de conteúdo curto apresentam hoje a melhor combinação entre viralidade, engajamento e potencial de monetização no YouTube para o mercado brasileiro?**

O sistema deve sempre mostrar junto da resposta:

```text
tamanho da amostra
período analisado
dados utilizados
scores calculados
riscos
limitações
```

para evitar apresentar inferências como fatos absolutos.

---

# 78. Primeira tarefa para o Codex

Não implementar tudo ainda.

Comece somente pela **Fase 1 — Fundação**.

Antes de alterar o n8n:

1. analise este plano;
2. verifique o estado atual do repositório;
3. verifique a conexão MCP com o n8n;
4. proponha os arquivos a serem criados;
5. proponha o schema PostgreSQL;
6. mostre o plano específico da Fase 1;
7. aguarde autorização antes de criar ou alterar recursos persistentes.

Após a autorização, implemente a Fase 1 e valide completamente antes de iniciar a Fase 2.
