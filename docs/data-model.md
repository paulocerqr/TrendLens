# Modelo de dados

## Convenções

- Chaves internas usam `BIGINT` com identity.
- Instantes usam `TIMESTAMPTZ`.
- Contagens usam `BIGINT`.
- Scores normalizados usam faixas verificadas por constraints.
- Campos ausentes permanecem `NULL` quando zero teria significado diferente.
- Metadados variáveis usam `JSONB`; atributos consultados frequentemente usam colunas tipadas.
- Vocabulários classificatórios usam slugs em `snake_case`, evitando enums rígidos.

## Relacionamentos principais

```text
categories
    +-- collection_queries
    +-- video_classifications

videos
    |
    +-- video_snapshots
    |       |
    |       +-- video_metrics
    |
    +-- video_classifications
    |
    +-- video_monetization_scores

category_statistics
    |
    +-- recommendations

pipeline_runs
    |
    +-- pipeline_errors
```

`recommendations` mantém a evidência agregada em JSONB, sem uma chave estrangeira direta para uma única linha estatística. Uma recomendação pode sintetizar múltiplas dimensões e janelas.

## Tabelas operacionais

### `categories`

Catálogo extensível de categorias de conteúdo. O seed inicial contém os dez grupos definidos para o MVP.

### `settings`

Configuração operacional versionável no banco. Os valores são JSONB para representar strings, números, booleanos ou `null` sem transformar secrets em configuração.

### `collection_queries`

Queries associadas a categorias. `sample_group` diferencia amostras `recent` e `high_performance`. A identidade lógica é case-insensitive por query, grupo, idioma e região.

## Dados observados

### `videos`

Armazena metadados públicos normalizados. A combinação `platform + external_id` é única. `short_confidence` expressa uma estimativa e não uma afirmação de que o vídeo é oficialmente um Short.

### `video_snapshots`

Armazena observações históricas imutáveis. Likes e comentários aceitam `NULL` quando a métrica não estiver disponível; isso não equivale a zero.

## Dados derivados

### `video_classifications`

Mantém a classificação estruturada atual de cada vídeo, incluindo modelo, versão do prompt, confiança, originalidade e riscos heurísticos.

### `video_metrics`

Relaciona métricas derivadas ao snapshot que as originou. Percentis permanecem entre 0 e 1, enquanto Virality Score permanece entre 0 e 10.

### `video_monetization_scores`

Mantém fatores positivos, riscos e resultado por versão de cálculo. O score representa adequação heurística a uma estratégia sustentável, não receita prevista nem decisão oficial do YouTube.

### `category_statistics`

Armazena agregações por período e combinação de dimensões classificatórias. O índice único trata valores `NULL` como não distintos para impedir a duplicação da mesma agregação.

### `recommendations`

Armazena recomendações estruturadas, riscos, formatos, hooks e evidências quantitativas. Toda evidência numérica deverá ser produzida a partir do PostgreSQL.

## Observabilidade

### `pipeline_runs`

Registra status, duração, contadores, chamadas de API e estimativa de quota por execução.

### `pipeline_errors`

Registra falhas associadas opcionalmente a uma execução. A sanitização de secrets é responsabilidade do workflow antes do insert.

## Regras de exclusão

Entidades dependentes de um vídeo usam `ON DELETE CASCADE`. O sistema não implementará exclusão automática de vídeos durante o MVP. Categorias referenciadas por queries usam `ON DELETE RESTRICT`, preservando a configuração operacional.
