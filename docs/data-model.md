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
    |
    +-- reports

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

O idioma possui campos com responsabilidades distintas: `api_language` preserva o valor explícito da plataforma; `target_language` representa a configuração da análise; `detected_language`, `language_confidence` e `language_detection_source` registram a avaliação; `language_eligibility` controla a passagem para o pipeline analítico. Tentativas e `language_retry_after` formam uma fila operacional sem apagar vídeos rejeitados.

### `video_snapshots`

Armazena observações históricas imutáveis. Likes e comentários aceitam `NULL` quando a métrica não estiver disponível; isso não equivale a zero.

### `video_snapshot_tracking_state`

Mantém somente o estado operacional mutável de cada vídeo: falhas consecutivas, último motivo, último sucesso e `retry_after`. O histórico observado continua imutável em `video_snapshots`, enquanto um sucesso posterior limpa o backoff.

### `select_snapshot_candidates`

Função SQL que seleciona vídeos do YouTube ainda dentro da janela ativa, cujo snapshot mais recente venceu o intervalo da respectiva faixa de idade e cujo backoff já expirou. Ela retorna também a faixa e o intervalo aplicado, permitindo testar a política independentemente do n8n.

### `persist_snapshot_batch`

Função transacional que compara os IDs pedidos e retornados, persiste snapshots válidos, atualiza ou limpa o backoff, registra um erro auditável por vídeo e atualiza os contadores do `pipeline_run`.

### `video_collection_matches`

Relaciona cada vídeo elegível à query e à execução que o encontrou, preservando a posição na busca. Essa proveniência permite comparar as amostras `recent` e `high_performance` sem duplicar registros em `videos`.

### `select_language_detection_candidates`

Seleciona vídeos do YouTube com elegibilidade `uncertain`, backoff vencido e tentativas abaixo do limite configurado. A descrição é truncada no PostgreSQL e as categorias de proveniência entram apenas como pistas.

### `persist_language_detection`

Normaliza o código de idioma, carrega o idioma-alvo global de `LANGUAGE_GATE_TARGET_LANGUAGE`, aplica a confiança mínima e decide `eligible`, `rejected` ou `uncertain` pela correspondência entre os idiomas-base. A função também realinha `videos.target_language` ao valor global, impedindo que o idioma declarado pelo vídeo se torne acidentalmente o critério de elegibilidade. O resultado registra fonte, instante, quantidade de tentativas e próximo retry de forma atômica.

### `set_manual_language_eligibility`

Permite revisão explícita de um vídeo inconclusivo. A origem passa a `manual`, a confiança fica registrada como 1 e os metadados públicos do vídeo continuam preservados.

### `select_classification_candidates`

Função SQL que retorna somente vídeos do YouTube com `language_eligibility` no estado `eligible` e sem linha em `video_classifications`. O limite e o tamanho máximo da descrição são argumentos explícitos; as categorias das queries que encontraram o vídeo são agregadas como pistas de baixa confiança.

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

### `reports`

Persiste o contrato JSON e a apresentação Markdown do mesmo relatório. A linha registra período, contexto, versões das fontes, cobertura, quantidade de itens em cada seção e hash determinístico. O índice único trata região e idioma nulos como iguais e impede duplicação quando o conteúdo agregado não mudou.

### `build_trendlens_report`

Função SQL estável que seleciona um contexto de idioma compatível, reúne categorias do bucket atual e renderiza Top Opportunities, Viral but Risky e tendências emergentes. Recomendações entram somente quando usam o prompt configurado; todas as métricas permanecem copiadas das agregações. A função também produz mensagens explícitas para seções sem dados e retorna os contadores usados por `pipeline_runs`.

## Observabilidade

### `pipeline_runs`

Registra status, duração, contadores, chamadas de API e estimativa de quota por execução.

### `pipeline_errors`

Registra falhas associadas opcionalmente a uma execução. A sanitização de secrets é responsabilidade do workflow antes do insert.

`retry_count` representa a quantidade de novas tentativas configuradas que antecederam um erro terminal. Eventos sem retry, como itens omitidos por uma resposta válida da API, usam zero.

### `pipeline_observability_reports`

Persiste snapshots JSON de saúde operacional. Cada linha registra a janela fechada, instante de geração, versão do contrato, estado geral, quantidade de workflows, runs, eventos de erro e retries, além do hash determinístico da fonte.

O índice único em período, versão e hash permite reutilizar o mesmo snapshot quando as fontes não mudaram. Alterações tardias nos dados operacionais geram uma nova linha, preservando a auditoria anterior.

### `build_pipeline_observability`

Função SQL estável que consolida `pipeline_runs`, `pipeline_errors` e indicadores atuais das tabelas analíticas. O JSON inclui resumo global, saúde por workflow, vídeos coletados, snapshots, classificações, latência média, erros, retries, distribuição por categoria, vídeos de alta viralidade e categorias de alta oportunidade.

A função considera somente a métrica mais recente de cada vídeo para evitar contagem duplicada no indicador de alta viralidade. Eventos recentes não incluem mensagem nem metadata do erro.

## Validação

### `classification_validation_reviews`

Armazena avaliações humanas sem alterar a classificação produzida pela IA. Cada linha identifica vídeo, versão do prompt e pessoa revisora, mantém dez decisões booleanas, correções opcionais em JSONB e notas limitadas. A identidade lógica impede que a mesma pessoa registre duas revisões do mesmo vídeo e prompt.

### `select_classification_review_candidates`

Seleciona vídeos ainda não revisados na versão do prompt, estratificados por categoria e confiança. A seed torna a amostragem reproduzível e a saída inclui metadados públicos, classificação atual e grupos amostrais de proveniência.

### `pipeline_validation_reports`

Persiste o contrato JSON da Fase 12 por janela, versão e hash da fonte. O estado pode ser `insufficient_data`, `needs_attention` ou `ready_for_weight_review`. O relatório preserva cobertura, qualidade dos snapshots, resultado das revisões humanas, diagnóstico dos scores, comparação de categorias e decisão sobre pesos.

### `build_phase12_validation`

Consolida a janela fechada configurável, verifica as portas de prontidão e executa a análise Movie/TV Clips vs outros formatos. A função apenas reporta a decisão de calibração; ela nunca altera configurações ou recalcula scores com pesos novos.

## Regras de exclusão

Entidades dependentes de um vídeo usam `ON DELETE CASCADE`. O sistema não implementará exclusão automática de vídeos durante o MVP. Categorias referenciadas por queries usam `ON DELETE RESTRICT`, preservando a configuração operacional.
