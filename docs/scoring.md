# Metodologia de scoring

## Metrics Engine v1

O Metrics Engine calcula somente dados derivados de snapshots públicos armazenados no PostgreSQL. A versão utilizada é persistida em `video_metrics.calculation_version` e em `pipeline_runs.metadata`.

### Rates

Para snapshots com `views > 0`:

```text
like_rate = likes / views
comment_rate = comments / views
engagement_rate = (likes + comments * COMMENT_WEIGHT) / views
```

`COMMENT_WEIGHT` começa em 3 e é configurável. Se uma métrica necessária estiver ausente, o rate correspondente permanece `NULL`. Divisão por zero também produz `NULL`.

### Velocidade e aceleração

```text
view_velocity = (views_atual - views_anterior) / horas_decorridas

view_acceleration =
    (velocity_atual - velocity_anterior) / horas_decorridas
```

Velocity exige dois snapshots ordenados; acceleration exige três. Valores negativos são preservados, pois contadores públicos podem sofrer correções e não devem ser artificialmente truncados.

### Baseline e outlier

O baseline usa a mediana do snapshot mais recente de outros vídeos do mesmo canal dentro da janela configurada:

```text
relative_performance = views_atual / channel_median_views
outlier_score = views_atual / channel_median_views
```

Na versão v1, `relative_performance` e `outlier_score` compartilham a mesma razão. O valor permanece `NULL` se o canal não possuir a quantidade mínima de outros vídeos ou se a mediana for zero.

### Percentis comparáveis

Os percentis são calculados separadamente para velocity, engagement, outlier e views. A coorte preferida combina plataforma, região e categoria. Quando a categoria não alcança `MIN_SAMPLE_SIZE`, o cálculo usa a coorte mais ampla de plataforma e região. Se nem ela atingir o mínimo, o percentil permanece `NULL`.

### Freshness Score

O freshness decai linearmente de 1 para 0 durante `METRICS_FRESHNESS_HORIZON_HOURS`, inicialmente 168 horas:

```text
freshness = clamp(1 - idade_em_horas / horizonte_em_horas, 0, 1)
```

## Virality Score v1

Pesos iniciais:

| Componente | Peso |
|---|---:|
| Velocity Percentile | 0,35 |
| Engagement Percentile | 0,20 |
| Outlier Percentile | 0,20 |
| Views Percentile | 0,15 |
| Freshness Score | 0,10 |

```text
virality = 10 * soma(valor_disponível * peso) / soma(pesos_disponíveis)
```

Esse denominador redistribui explicitamente o peso de componentes ausentes entre os componentes disponíveis; `NULL` nunca é substituído por zero. O score só é produzido quando pelo menos `METRICS_MIN_VIRALITY_COMPONENTS`, inicialmente 3, estão disponíveis.

Faixas heurísticas iniciais:

| Score | Interpretação |
|---|---|
| 0 a 3 | baixo desempenho |
| 3 a 5 | normal |
| 5 a 7 | acima da média |
| 7 a 8,5 | forte |
| 8,5 a 10 | viral ou outlier na amostra |

Essas faixas não representam o algoritmo interno do YouTube e deverão ser recalibradas com mais histórico.

## Monetization Score v1

O Monetization Score estima quão favorável parece ser um formato para produção sustentável por um criador. Ele não estima receita, elegibilidade oficial, aprovação no Programa de Parcerias ou resultado de uma análise de copyright.

### Fatores positivos

| Fator | Origem | Peso |
|---|---|---:|
| Originality | `video_classifications.originality_score` | 0,30 |
| Policy Eligibility | mapa configurável por `source_type` | 0,25 |
| Advertiser Suitability | mapa configurável por `format` | 0,15 |
| Production Feasibility | formato classificado e duração observada | 0,15 |
| Engagement Quality | percentil de engajamento observado | 0,15 |

Os mapas ficam em `settings`, não no workflow. Para os três fatores derivados de campos classificados, a confiança da IA reduz afirmações fortes em direção ao ponto neutro:

```text
fator_ajustado = 0,5 + (fator_mapeado - 0,5) * ai_confidence
```

Production Feasibility combina 70% do proxy ajustado por formato e 30% de um fator de duração. O fator de duração começa em 1 para vídeos de até 60 segundos, 0,8 até 120 segundos, 0,6 até 180 segundos e 0,4 acima disso. Se a duração estiver ausente, somente o proxy por formato é utilizado.

Advertiser Suitability é apenas um proxy de metadados. O TrendLens ainda não analisa frames, áudio, transcrição, linguagem imprópria ou temas sensíveis; portanto esse fator não equivale a uma avaliação real de segurança para anunciantes.

### Base positiva e dados ausentes

```text
base = soma(fator_disponível * peso) / soma(pesos_disponíveis)
```

Originalidade, elegibilidade, adequação e viabilidade existem para toda classificação válida. Engagement Quality permanece `NULL` quando não há percentil comparável. Nesse caso, os 15% são redistribuídos proporcionalmente entre os demais fatores; ausência nunca é tratada como zero.

### Risco combinado

```text
risk = 0,60 * copyright_risk + 0,40 * reused_content_risk
```

Os riscos vêm diretamente da classificação estruturada e permanecem entre 0 e 1. Eles representam estimativas baseadas nos metadados públicos disponíveis, não afirmações de violação.

### Score final

```text
monetization = 10 * base * max(0, 1 - risk)
```

`positive_base`, `combined_risk`, cada fator e a versão da fórmula são persistidos em `video_monetization_scores`, permitindo explicar e recalcular o resultado.

Faixas heurísticas iniciais:

| Score | Interpretação |
|---|---|
| 0 a 3 | perfil desfavorável ou risco alto |
| 3 a 5 | potencial limitado |
| 5 a 7 | potencial moderado |
| 7 a 8,5 | perfil favorável |
| 8,5 a 10 | perfil fortemente favorável na heurística |

As faixas deverão ser recalibradas quando existirem mais classificações e avaliações manuais.
