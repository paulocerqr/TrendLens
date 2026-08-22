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
    |
    +-- video_collection_matches

category_statistics
    |
    +-- recommendations

pipeline_runs
    |
    +-- pipeline_errors
    |
    +-- video_collection_matches
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

### `select_snapshot_candidates`

Função SQL que seleciona vídeos do YouTube ainda dentro da janela ativa e cujo snapshot mais recente venceu o intervalo da respectiva faixa de idade. Ela retorna também a faixa e o intervalo aplicado, permitindo testar a política independentemente do n8n.

### `video_collection_matches`

Relaciona cada vídeo elegível à query e à execução que o encontrou, preservando a posição na busca. Essa proveniência permite comparar as amostras `recent` e `high_performance` sem duplicar registros em `videos`.

### `select_classification_candidates`

Função SQL que retorna somente vídeos do YouTube sem linha em `video_classifications`. O limite e o tamanho máximo da descrição são argumentos explícitos; as categorias das queries que encontraram o vídeo são agregadas como pistas de baixa confiança.

## Dados derivados

### `video_classifications`

Mantém uma classificação estruturada por vídeo, incluindo categoria opcional, dimensões em `snake_case`, modelo, versão do prompt, confiança, originalidade e riscos heurísticos. Constraints protegem as faixas de 0 a 1 e impedem modelo ou versão de prompt vazios.

### `video_metrics`

Relaciona métricas derivadas ao snapshot que as originou. Cada snapshot possui no máximo uma linha, atualizável de forma idempotente quando percentis da coorte mudam. A linha referencia o snapshot anterior, preserva `NULL` quando o histórico é insuficiente e registra a versão das fórmulas. Percentis permanecem entre 0 e 1, enquanto Virality Score permanece entre 0 e 10.

### `refresh_video_metrics`

Função SQL transacional que calcula métricas para o snapshot mais recente dos vídeos dentro da janela configurada. Percentis usam a coorte completa mesmo quando o limite operacional restringe quantas linhas são persistidas. O retorno resume elegibilidade, disponibilidade das métricas e quantidade de scores produzidos para alimentar `pipeline_runs`.

### `video_monetization_scores`

Mantém fatores positivos, riscos, base positiva, risco combinado e resultado por versão de cálculo. `engagement_quality` aceita `NULL` quando o Metrics Engine ainda não produziu um percentil comparável; o peso ausente é redistribuído durante o cálculo. O score representa adequação heurística a uma estratégia sustentável, não receita prevista nem decisão oficial do YouTube.

### `refresh_video_monetization_scores`

Função SQL transacional que transforma classificações e métricas observadas em fatores normalizados, aplica pesos configuráveis e faz upsert idempotente por vídeo e versão. O retorno informa elegibilidade, persistência, disponibilidade de engajamento e quantidade de scores acima do limite operacional de risco.

### `category_statistics`

Armazena agregações por período e dimensão classificatória. `dimension_type` e `dimension_value` identificam visões por categoria, tópico, tipo, formato, hook, origem ou combinação categoria–formato–origem. A linha preserva medianas, P75/P90, taxas, dispersão, consistência, amostra anterior, variação e direção. Também mantém Opportunity Score, rank, percentil, quantidade de componentes, versão e instante do cálculo. O índice único inclui período e versão e trata valores `NULL` como não distintos.

### `refresh_category_statistics`

Função SQL transacional que compara duas janelas equivalentes, agrega os vídeos classificados e faz upsert idempotente no bucket temporal. O retorno resume vídeos, dimensões, suficiência amostral e quantidades por direção de tendência.

### `refresh_opportunity_rankings`

Função SQL transacional que seleciona o bucket de tendências mais recente, combina os três componentes obrigatórios e atualiza scores e rankings em lote. Ranks e percentis são particionados por contexto comparável e tipo de dimensão; o retorno resume linhas consideradas, completas, incompletas, categorias ranqueadas e maior score de categoria.

### `recommendations`

Armazena síntese, formatos, hooks, riscos e observações de monetização em campos tipados. Os scores de oportunidade, viralidade, monetização e consistência são copiados das agregações do PostgreSQL, nunca produzidos pelo modelo. A linha registra plataforma, região, idioma, período, modelo, versão do prompt, versões dos cálculos de origem, evidência JSONB agregada e seu hash.

Os quatro arrays exigem de um a cinco itens. O índice único de evidência trata dimensões nulas como iguais e impede duplicação da mesma recomendação por categoria, período, contexto, modelo, prompt e hash. Não existe referência a um vídeo individual.

### `select_recommendation_candidates`

Função SQL estável que seleciona categorias com Opportunity Score no bucket corrente, aplica limite e score mínimo configuráveis e monta a evidência agregada. O JSON inclui o escopo, as estatísticas da categoria e listas limitadas de padrões de formato, origem e hook do mesmo contexto. Candidatos cuja combinação de evidência, modelo e versão já foi persistida são excluídos antes da chamada à IA.

## Observabilidade

### `pipeline_runs`

Registra status, duração, contadores, chamadas de API e estimativa de quota por execução.

### `pipeline_errors`

Registra falhas associadas opcionalmente a uma execução. A sanitização de secrets é responsabilidade do workflow antes do insert.

## Regras de exclusão

Entidades dependentes de um vídeo usam `ON DELETE CASCADE`. O sistema não implementará exclusão automática de vídeos durante o MVP. Categorias referenciadas por queries usam `ON DELETE RESTRICT`, preservando a configuração operacional.
