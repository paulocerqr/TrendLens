# Metodologia

## Princípio

O TrendLens separa dados observados de interpretações heurísticas. Views, likes, comentários, datas e durações são coletados da API. Scores, classificação de formato e riscos são derivados posteriormente e devem indicar a fórmula ou o modelo utilizados.

## Amostragem do YouTube

O collector usa dois grupos para reduzir o viés de analisar apenas vídeos já virais:

- `recent`: resultados ordenados por data, usados como baseline;
- `high_performance`: resultados ordenados por visualizações dentro da mesma janela, usados para localizar padrões de alto desempenho.

As queries ficam em `collection_queries`, nunca fixadas no workflow. Cada query possui categoria, grupo amostral, idioma, região, prioridade e estado da última coleta.

O collector selecionará primeiro queries nunca executadas e depois as menos recentemente coletadas. `MAX_QUERIES_PER_RUN` limita cada execução e permite distribuir as queries ao longo do tempo.

No deployment atual, o Schedule Trigger inicia uma coleta a cada três horas, no minuto 5, usando `America/Sao_Paulo`. Com quatro queries por execução, isso representa no máximo 32 buscas agendadas por dia, abaixo do limite diário configurado de 100 chamadas de busca. A seleção pelas queries menos recentemente coletadas distribui as 22 combinações ativas entre os ciclos.

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

A validação inicial recebeu 100 resultados, processou todos sem erro, registrou 99 vídeos novos, 1 duplicado, 100 correspondências de proveniência e 99 snapshots.

Antes da ativação, uma nova execução integrada recebeu 100 resultados, processou 98 candidatos, ignorou dois itens e não registrou falhas. Ela persistiu 98 vídeos novos, 98 correspondências e 98 snapshots. Após essa revisão, o workflow foi publicado e ativado com o agendamento de três horas.

Durante o teste, a passagem do timestamp do PostgreSQL pelo n8n revelou perda de precisão abaixo de milissegundos. A persistência passou a obter `pipeline_runs.started_at` diretamente do banco para manter uma chave temporal idêntica entre execução e snapshots. A finalização também usa uma referência explícita ao node inicial, pois a saída concluída do loop não preserva necessariamente o item de contexto.

## Acompanhamento por snapshots

O Snapshot Tracker usa o instante de publicação e o snapshot mais recente para decidir quando consultar novamente um vídeo:

- até 24 horas de idade: intervalo mínimo inicial de 60 minutos;
- acima de 24 e até 72 horas: intervalo mínimo inicial de 360 minutos;
- acima de 72 horas e até 7 dias: intervalo mínimo inicial de 1.440 minutos;
- acima de 7 dias: fora do acompanhamento ativo.

Os limites, intervalos e o máximo de vídeos por execução ficam em `settings`. A função `select_snapshot_candidates` aplica a mesma regra de forma centralizada e ordena primeiro as observações há mais tempo sem atualização.

Cada chamada `videos.list` contém no máximo 50 IDs e solicita somente estatísticas. Um retorno válido cria um novo snapshot no instante inicial do `pipeline_run`; o registro anterior nunca é atualizado. Likes e comentários ausentes permanecem `NULL`.

Vídeos omitidos pela API ou sem `viewCount` recebem estado próprio em `video_snapshot_tracking_state`. O backoff começa em seis horas, dobra a cada omissão consecutiva e é limitado a sete dias; um retorno válido zera o estado. O erro registra o `external_id`, o motivo, o contador e `retry_after`, sem impedir o processamento dos demais IDs.

## Primeira execução do Snapshot Tracker

A validação integrada selecionou 149 vídeos vencidos, consultou três lotes e inseriu 149 snapshots sem falhas. Os contadores persistidos registraram três chamadas `videos.list`, três unidades estimadas de quota e duração de 1,685 segundo. Uma execução imediata subsequente selecionou zero candidatos e não chamou a API, confirmando a aplicação do intervalo mínimo com base no snapshot mais recente.

## Classificação estruturada por IA

O classificador usa apenas metadados públicos já persistidos: título, descrição truncada, canal, publicação, duração, idioma, região, confiança de Short e categorias de proveniência. Título e descrição são tratados como dados não confiáveis, e o prompt instrui o modelo a ignorar comandos contidos nesses campos.

Cada execução horária seleciona até 30 candidatos. Esse limite acompanha a vazão observada do Collector sem prolongar o lote até o próximo gatilho; o workflow possui timeout de 55 minutos como barreira operacional contra sobreposição.

A resposta deve obedecer a um JSON Schema fechado. Campos livres usam `snake_case`; formato, hook, origem e categoria usam vocabulários controlados; scores e confiança ficam entre 0 e 1. Uma saída inválida passa por uma tentativa automática de correção com o mesmo provedor. Se ainda falhar, o erro é sanitizado, contabilizado e o próximo vídeo é processado.

As categorias derivadas da coleta são apenas pistas e não determinam a resposta. O classificador não afirma violação de copyright nem elegibilidade de monetização: `copyright_risk` e `reused_content_risk` representam somente estimativas baseadas nos metadados disponíveis. `classification_model` e `prompt_version` tornam cada resultado auditável.

## Primeira execução do AI Content Classifier

A revisão final selecionou cinco candidatos, criou quatro classificações e ignorou uma linha já inserida por uma execução concorrente. O run terminou com zero falhas, cinco chamadas estimadas ao modelo e duração de 134,315 segundos. A execução concorrente também finalizou com sucesso, confirmando que o conflito por vídeo é tratado de forma idempotente.

A validação de capacidade posterior classificou 30 de 30 candidatos em 218,674 segundos, sem falhas ou conflitos. A média de 7,289 segundos por vídeo confirmou folga operacional diante do ciclo horário.

## Métricas e Virality Score

O Metrics Engine calcula o snapshot atual de cada vídeo elegível em SQL. Rates exigem denominador positivo e mantêm `NULL` quando likes ou comentários estão ausentes. Velocity exige dois snapshots; acceleration exige três. O baseline do canal considera outros vídeos recentes e só é aceito quando alcança a amostra mínima configurada.

Percentis são calculados para velocity, engagement, outlier e views. A coorte preferida combina plataforma, região e categoria; grupos pequenos usam o fallback de plataforma e região. Se o fallback também for insuficiente, o percentil permanece ausente.

O Virality Score aplica os pesos 35% velocity, 20% engagement, 20% outlier, 15% views e 10% freshness. Pesos ausentes são redistribuídos proporcionalmente, e o score exige pelo menos três componentes. A definição completa está em [scoring.md](scoring.md).

## Primeira execução do Metrics Engine

A execução final processou 268 vídeos em 0,177 segundo, gerou 264 Virality Scores, 150 velocities e 11 baselines de canal. O score variou de 1,0765 a 8,8983, com média 5,1283, e nenhum valor violou as faixas tipadas. Não havia vídeos com três snapshots; portanto acceleration permaneceu `NULL`, conforme a regra de dados insuficientes.

## Monetization Score

O Monetization Engine usa originalidade, riscos e confiança produzidos pelo classificador, duração pública do vídeo e percentil de engajamento calculado pelo Metrics Engine. Elegibilidade de política deriva de um mapa por `source_type`; adequação a anunciantes e viabilidade de produção usam mapas por `format`. A confiança da classificação aproxima cada proxy de 0,5 quando a incerteza aumenta.

A base positiva aplica pesos de 30% para originalidade, 25% para elegibilidade de política e 15% para adequação a anunciantes, viabilidade de produção e qualidade do engajamento. A penalidade combina 60% de risco autoral e 40% de risco de conteúdo reutilizado. Se o percentil de engajamento estiver ausente, seu peso é redistribuído entre os demais fatores, nunca convertido em zero. A definição completa está em [scoring.md](scoring.md).

## Primeira execução do Monetization Engine

A execução final processou 15 classificações em 0,076 segundo. Quatorze possuíam qualidade de engajamento observada, duas ficaram acima do limite de risco combinado e nenhuma violou as constraints. O score variou de 0,9065 a 5,5480, com média 3,4076. A amostra ainda é pequena e esses valores não devem ser generalizados como perfil do YouTube brasileiro.

## Tendências e consistência

O Trend Engine compara a janela móvel atual de sete dias com a janela anterior equivalente. Cada vídeo classificado contribui para visões independentes por categoria, tópico, tipo, formato, hook, origem e combinação categoria–formato–origem. O bucket horário torna tentativas repetidas idempotentes sem apagar o histórico de períodos.

Cada grupo preserva tamanho da amostra, medianas, P75/P90 de views, taxas de outlier e alto desempenho, percentuais acima de P75/P90, dispersão e Consistency Score. A direção compara a mediana de Virality Score das duas janelas e exige a amostra mínima configurada em ambas. A fórmula completa está em [scoring.md](scoring.md).

## Primeira execução do Trend Engine

A execução final processou 20 vídeos e persistiu 104 agregações em 0,102 segundo. A maior dimensão continha quatro vídeos e nenhuma alcançou a amostra mínima padrão de 30 nas duas janelas; por isso todas as direções ficaram como `insufficient_data`. O Consistency Score variou de 0,6667 a 3,9470, sem violações de faixa.

## Opportunity Score e ranking

O Opportunity Engine usa o bucket materializado mais recente da versão corrente do Trend Engine. Cada linha precisa das medianas de Virality e Monetization e do Consistency Score; se algum componente estiver ausente, o score e o rank permanecem `NULL` em vez de assumir zero.

O cálculo aplica 50% a Virality, 35% a Monetization e 15% a Consistency. O rank denso e o percentil são calculados separadamente por período, versão, plataforma, região, idioma e tipo de dimensão, evitando comparar contextos incompatíveis. A definição completa está em [scoring.md](scoring.md).

## Primeira execução do Opportunity Engine

Após sincronizar Metrics, Monetization e Trend, a execução final processou 104 agregações em 0,070 segundo. Todas possuíam os três componentes, 14 linhas de categoria foram ranqueadas e nenhuma linha violou as constraints. Os scores ficaram entre 1,8664 e 6,5374, com média 4,3410. A amostra ainda é pequena e os resultados descrevem somente o conjunto coletado pelo TrendLens.

## Recomendações estruturadas por IA

O Recommendation AI seleciona apenas dimensões de categoria do bucket mais recente que possuem Opportunity Score. O contexto entregue ao modelo contém estatísticas agregadas da categoria, padrões agregados de categoria–formato–origem e rankings agregados de formatos e hooks; IDs, títulos, descrições e metadados de vídeos individuais não fazem parte da evidência.

O modelo produz uma síntese acionável e de uma a cinco sugestões em cada grupo: formatos, hooks, riscos e observações de monetização. O prompt proíbe copiar vídeos específicos, inventar ou recalcular métricas, tratar correlação como causalidade e prometer viralização, receita ou conformidade. As sugestões descrevem padrões reutilizáveis, enquanto os scores persistidos continuam vindo exclusivamente do PostgreSQL.

A resposta deve obedecer a um JSON Schema fechado e pode passar por uma tentativa automática de correção. A persistência registra modelo, versão do prompt, versões dos cálculos de origem, contexto comparável e hash da evidência. Uma chave única com `NULLS NOT DISTINCT` evita recomendações duplicadas para a mesma evidência, inclusive quando execuções concorrentes selecionam os mesmos candidatos.

## Primeira execução do Recommendation AI

A primeira execução final selecionou cinco categorias agregadas e criou cinco recomendações, sem falhas, em 369,624 segundos. Uma execução concorrente selecionou cinco candidatos, criou duas recomendações ainda pendentes e ignorou três conflitos já persistidos, confirmando a idempotência. O fluxo definitivo, já sem o bootstrap da migration, criou outras cinco recomendações em 331,140 segundos.

A revisão qualitativa das respostas `v1` revelou interpretações indevidas do idioma da audiência e da unidade do Monetization Score. O prompt `v2` passou a distinguir o idioma analisado do idioma da resposta, a identificar scores como índices heurísticos de 0 a 10 e a proibir sua apresentação como moeda, receita, taxa, porcentagem ou contagem. A validação limitada a uma categoria criou uma recomendação `v2` em 46,320 segundos, sem falhas.

A auditoria final encontrou 13 recomendações persistidas, sendo 12 preservadas como histórico `v1` e uma `v2`. Todas usavam evidência exclusivamente agregada; não havia campos de vídeo individual, scores fora da faixa, arrays inválidos nem evidências duplicadas. Treze contextos ainda aguardavam processamento pelo prompt atual, que voltará a consumir no máximo cinco categorias por execução.

## Relatório determinístico

O Report Engine não chama um modelo de linguagem. JSON e Markdown são renderizados pela função `build_trendlens_report` a partir do bucket mais recente do Trend Engine, dos rankings do Opportunity Engine e das recomendações estruturadas que usam a versão de prompt atualmente configurada. Isso mantém cada número ligado diretamente ao PostgreSQL e evita propagar recomendações históricas já substituídas.

O relatório usa um único contexto comparável. Plataforma e região vêm das configurações; para idioma, a função prefere a correspondência exata e, quando ela não possui estatísticas, escolhe a variante regional com maior cobertura, como `pt-BR` para `pt`. O JSON registra tanto o idioma solicitado quanto o selecionado.

Top Opportunities ordena categorias pelo Opportunity Score. Viral but Risky exige simultaneamente a mediana mínima de Virality Score e a mediana máxima de Monetization Score configuradas, expondo também a diferença entre os índices. Tendências emergentes incluem somente grupos `rising`, cuja direção já exige amostra mínima nas janelas atual e anterior. Se uma seção estiver vazia, o Markdown explica a ausência em vez de inventar resultados.

O hash exclui apenas o instante de geração e inclui contexto, período, versões, cobertura, evidências e seções. Uma execução com a mesma fonte reutiliza o relatório persistido; quando os dados ou versões mudam, um novo registro é criado.

## Primeira execução do Report Engine

A execução final usou o contexto `youtube/BR/pt-BR`, analisou seis vídeos distribuídos em quatro categorias e gerou quatro Top Opportunities e dois casos Viral but Risky. Nenhuma tendência emergente possuía amostra suficiente, condição apresentada explicitamente nos dois formatos. Duas categorias tinham recomendações `v2`; as demais mantiveram somente os scores e as evidências do PostgreSQL.

O contrato final foi versionado como `v2`. O relatório foi persistido em JSON e Markdown sem falhas em 0,224 segundo; uma execução imediata do fluxo definitivo encontrou o mesmo hash, reutilizou o mesmo registro em 0,145 segundo, com um item ignorado e zero falhas, confirmando a idempotência.

## Observabilidade do pipeline

A observabilidade usa `pipeline_runs` como fonte de status, contadores e duração, e `pipeline_errors` como fonte de eventos terminais e retries. A função `build_pipeline_observability` avalia os nove workflows produtivos em uma janela configurável de 24 horas com limite superior exclusivo no início da hora corrente.

Cada workflow recebe um estado derivado:

- `critical`: existe execução falha no período ou execução `running` acima do limite configurado;
- `degraded`: existe execução parcial ou evento de erro sem condição crítica;
- `healthy`: houve execução no período sem falha ou erro;
- `unknown`: não houve execução dentro da janela.

O estado geral é `critical` quando qualquer etapa é crítica, `degraded` quando não há etapa crítica mas existe etapa degradada e `healthy` nos demais casos. Workflows `unknown` permanecem contabilizados sem tornar o estado geral crítico, pois nem todas as etapas possuem a mesma frequência ou estão publicadas.

Os indicadores operacionais distinguem vídeos coletados, novos e duplicados, snapshots, classificações, erros de classificação, erros de API, itens com erro e retries. A latência média de classificação é ponderada pela quantidade processada mais a quantidade com erro. A distribuição por categoria usa o inventário classificado; alta viralidade considera somente a métrica mais recente de cada vídeo na versão corrente; oportunidades usam o bucket agregado mais recente e as versões configuradas.

Retries representam as novas tentativas registradas quando um erro terminal persiste após `maxTries = 3`. Tentativas internas que terminam com sucesso não são expostas pelo n8n e, portanto, não entram no contador. A lista de erros recentes omite deliberadamente `error_message` e `metadata`.

## Primeira execução da observabilidade

A execução final do workflow analisou 69 runs na janela fechada, com 48 sucessos, três execuções parciais, 18 falhas, 21 eventos de erro e dois retries registrados. Foram observadas 25 classificações, 227 snapshots e 31 vídeos distintos cuja métrica mais recente atingia o limite de alta viralidade. A saúde geral ficou `critical` porque o Snapshot Tracker acumulou falhas de itens omitidos pela API; Recommendation AI ficou `degraded` e seis workflows ficaram saudáveis.

O snapshot foi persistido sem falha, o bootstrap da migration foi removido e o workflow final executou em 0,102 segundo. Ele possui seis nodes, permanece inativo e não publicado.

## Validação da Fase 12

A validação usa uma janela fechada de sete dias e três portas independentes antes de permitir revisão de pesos: três dias de observações, 30 avaliações humanas do classificador e amostra 30 em todas as seis categorias obrigatórias. A decisão é conservadora: qualquer porta ausente mantém os pesos v1.

Snapshots são verificados por cobertura, monotonicidade e cadência. O classificador é auditado em uma amostra determinística estratificada por categoria e confiança; as decisões humanas ficam separadas das respostas do modelo. Os scores são avaliados por quantis, caudas, disponibilidade de componentes e correlações descritivas.

A primeira execução real analisou 210 vídeos, 568 snapshots, 45 classificações, 210 Virality Scores e 45 Monetization Scores. O período observado era de 1,236 dia e nenhuma revisão humana havia sido concluída. Nenhuma das seis categorias atingiu a amostra mínima; Tutoriais e Storytelling ainda não estavam representadas no bucket comparável.

O componente de outlier estava ausente nos 210 Virality Scores, enquanto velocity apresentou correlação de `0,9074` com o resultado. Esse diagnóstico pode indicar dominância temporária causada pela redistribuição de pesos, mas a amostra ainda não autoriza calibração. O relatório retornou `insufficient_data` e `hold_v1_collect_more_data`; nenhum peso foi alterado. A análise completa está em [validation.md](validation.md).
