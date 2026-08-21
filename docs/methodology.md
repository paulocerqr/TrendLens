# Metodologia

## Princípio

O TrendLens separa dados observados de interpretações heurísticas. Views, likes, comentários, datas e durações são coletados da API. Scores, classificação de formato e riscos são derivados posteriormente e devem indicar a fórmula ou o modelo utilizados.

## Amostragem do YouTube

O collector usa dois grupos para reduzir o viés de analisar apenas vídeos já virais:

- `recent`: resultados ordenados por data, usados como baseline;
- `high_performance`: resultados ordenados por visualizações dentro da mesma janela, usados para localizar padrões de alto desempenho.

As queries ficam em `collection_queries`, nunca fixadas no workflow. Cada query possui categoria, grupo amostral, idioma, região, prioridade e estado da última coleta.

O collector selecionará primeiro queries nunca executadas e depois as menos recentemente coletadas. `MAX_QUERIES_PER_RUN` limita cada execução e permite distribuir as queries ao longo do tempo.

## Janela e contexto

Cada chamada de busca deverá usar:

- `type=video`;
- `publishedAfter` calculado com `COLLECTION_WINDOW_HOURS`;
- `regionCode` vindo de `REGION`;
- `relevanceLanguage` vindo de `LANGUAGE`;
- `maxResults` limitado a no máximo 50;
- `order=date` para `recent`;
- `order=viewCount` para `high_performance`.

`relevanceLanguage` aumenta a relevância para o idioma escolhido, mas não garante que todos os resultados estejam nesse idioma.

Referência: [YouTube Data API — search.list](https://developers.google.com/youtube/v3/docs/search/list).

## Detalhes e candidatos a Shorts

A busca fornece IDs e snippets. Detalhes de vídeo serão obtidos em lote com `videos.list`, incluindo:

- `snippet`;
- `contentDetails`;
- `statistics`.

A duração ISO 8601 será convertida para segundos. Vídeos com duração acima de `SHORT_MAX_DURATION` não serão priorizados no MVP.

`short_confidence` combinará duração, presença de `#shorts` e sinais de metadados. O resultado será `high`, `medium` ou `low`; não será tratado como uma flag oficial do YouTube.

## Dados ausentes

- `views` deve ser uma contagem não negativa.
- Likes ou comentários ausentes permanecem `NULL`.
- Ausência não será convertida automaticamente em zero.
- O YouTube MVP não inventará shares, reposts ou favorites.

## Deduplicação

`videos` possui unicidade em `platform + external_id`. O collector usará upsert para metadados e insert separado para snapshots. Um vídeo existente pode gerar um novo snapshot, mas não uma segunda linha em `videos`.
Cada correspondência entre vídeo, query e execução será preservada em `video_collection_matches`, incluindo a posição retornada pela busca. A tabela mantém a proveniência necessária para comparar as amostras `recent` e `high_performance` sem duplicar o cadastro do vídeo.



A documentação oficial atual usa um bucket separado para `search.list`, com custo de uma chamada e limite padrão configurável de 100 chamadas diárias. Operações de leitura como `videos.list` usam o bucket geral e normalmente custam uma unidade.

Como limites podem variar por projeto e mudar ao longo do tempo, todos esses valores ficam em `settings`. O collector registrará chamadas e estimativas em `pipeline_runs`.

Referências:

- [YouTube Data API — visão geral de quota](https://developers.google.com/youtube/v3/getting-started#quota)
- [YouTube Data API — calculadora de quota](https://developers.google.com/youtube/v3/determine_quota_cost)

## Primeira execução real

As primeiras execuções foram manuais e limitadas a quatro combinações de query e grupo amostral, com até 25 resultados por busca. Elas validaram a credencial OAuth, o formato das respostas, a normalização, o upsert, o primeiro snapshot, a proveniência e os logs.

A validação final recebeu 100 resultados, processou todos sem erro, registrou 99 vídeos novos, 1 duplicado, 100 correspondências de proveniência e 99 snapshots. O workflow permanece inativo até revisão explícita.

Durante o teste, a passagem do timestamp do PostgreSQL pelo n8n revelou perda de precisão abaixo de milissegundos. A persistência passou a obter `pipeline_runs.started_at` diretamente do banco para manter uma chave temporal idêntica entre execução e snapshots. A finalização também usa uma referência explícita ao node inicial, pois a saída concluída do loop não preserva necessariamente o item de contexto.
