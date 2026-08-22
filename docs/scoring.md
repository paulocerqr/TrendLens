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
