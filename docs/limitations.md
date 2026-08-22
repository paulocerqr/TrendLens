# Limitações

## Fundação

- A Fase 1A valida o repositório e o PostgreSQL isoladamente; ela não comprova conectividade com o n8n remoto.
- O teste integrado n8n para PostgreSQL depende do clone e deployment no servidor e pertence à Fase 1B.
- Scripts de bootstrap não substituem migrations em volumes já inicializados.
- A estimativa de quota armazenada em `pipeline_runs` dependerá da contabilização implementada pelo collector.
- O Schedule Trigger do Snapshot Tracker verifica candidatos a cada 15 minutos; os intervalos efetivos por vídeo são aplicados pelo PostgreSQL e podem ter atraso de até um ciclo de verificação.
- Execuções simultâneas do Snapshot Tracker não são coordenadas por um lock distribuído no MVP. A operação é idempotente para o mesmo vídeo e instante de execução, mas dois runs iniciados em instantes diferentes podem coletar observações muito próximas.
- Execuções simultâneas do AI Content Classifier podem selecionar os mesmos candidatos; a chave primária por vídeo impede duplicação, mas uma das execuções será contabilizada como ignorada após consumir uma chamada ao modelo.
- Latência e disponibilidade do provedor NVIDIA podem produzir timeouts. O workflow limita retries, registra a falha e continua, mas não mantém uma fila explícita de tentativas por vídeo.
- O Metrics Engine recalcula percentis sobre a coorte atual; scores históricos podem mudar quando a amostra cresce ou a versão das fórmulas é alterada.
- Baseline de canal exige outros vídeos recentes do mesmo canal. Canais com pouca presença na amostra mantêm `channel_median_views` e `outlier_score` como `NULL`.
- Execuções simultâneas do Metrics Engine são idempotentes por snapshot, mas podem repetir trabalho de cálculo. O intervalo padrão de uma hora é muito maior que a duração observada da execução.
- Elegibilidade de política, adequação a anunciantes e viabilidade de produção usam proxies configuráveis baseados em metadados classificados e duração; não analisam áudio, frames, transcrição, linguagem sensível nem o estado real do canal.
- Execuções simultâneas do Monetization Engine são idempotentes por vídeo e versão, mas podem recalcular as mesmas classificações. O score muda quando fatores, pesos, mapas ou a versão de cálculo mudam.
- O Trend Engine usa a classificação e as versões atuais das métricas ao recalcular janelas históricas; correções posteriores podem revisar estatísticas do mesmo bucket.
- Direção temporal exige amostra mínima nas duas janelas. Grupos novos, raros ou muito fragmentados permanecerão como `insufficient_data` até acumular observações suficientes.
- O Opportunity Engine depende da sincronização dos engines anteriores. Se Virality, Monetization ou Consistency estiver ausente no bucket mais recente, a linha permanece sem score e sem rank.
- O ranking é recalculado somente dentro do mesmo período, versão, plataforma, região, idioma e tipo de dimensão. Grupos com amostra pequena ainda podem receber score, mas o componente de consistência reduz sua força e o resultado não deve ser generalizado.
- O Recommendation AI usa apenas o bucket agregado mais recente. Mudanças na amostra, nas classificações ou nos cálculos alteram a evidência e podem gerar uma nova recomendação para a mesma categoria.
- Execuções concorrentes do Recommendation AI podem consumir chamadas do modelo para a mesma evidência; a chave idempotente impede duplicação, mas uma execução contabiliza o conflito como item ignorado.
- A saída textual é estruturada, mas continua sujeita a erros e simplificações do modelo. Formatos, hooks, riscos e observações precisam de revisão humana antes de orientar produção ou decisões comerciais.

## Dados e metodologia

- A API pública do YouTube não fornece uma flag perfeita para Shorts.
- Duração e metadados permitem apenas identificar candidatos com diferentes níveis de confiança.
- Queries de pesquisa introduzem viés amostral.
- Views e engajamento não representam receita.
- Não há acesso ao algoritmo interno do YouTube nem à receita real dos criadores.
- Copyright, conteúdo reutilizado e elegibilidade de monetização serão riscos heurísticos, não decisões oficiais.
- A classificação usa metadados, não analisa frames, áudio ou transcrição; portanto origem, estilo, hook e riscos podem ter confiança limitada.
- Correlação entre características e desempenho não implica causalidade.
- Métricas ausentes não devem ser convertidas automaticamente em zero.
- Resultados só podem ser comparados dentro de contextos compatíveis de plataforma, região, período e amostra.
- O Virality Score é relativo à amostra coletada e aos pesos v1; ele não reproduz nem prevê diretamente o algoritmo interno do YouTube.
- O Monetization Score não estima receita, CPM, aprovação no Programa de Parcerias ou resultado de revisão de copyright. Ele compara somente os sinais heurísticos disponíveis no TrendLens.
- Consistency Score mede repetição de desempenho dentro da amostra coletada; queries enviesadas ou poucos vídeos por dimensão podem limitar sua representatividade.
- Opportunity Score é uma priorização relativa aos sinais e pesos v1, não uma previsão de viralização, receita ou sucesso futuro.
- Recomendações derivam de correlações na amostra agregada, não estabelecem causalidade e não garantem viralização, monetização, conformidade legal ou resultado financeiro.
- O modelo não recebe vídeos individuais e não pode avaliar execução criativa, imagens, áudio ou contexto completo. Em dimensões esparsas, os melhores formatos e hooks do contexto podem refletir padrões globais em vez de evidência forte da categoria.

## Segurança

- O Compose não publica o PostgreSQL no host.
- O arquivo `.env.example` contém apenas placeholders.
- A credencial real deverá permanecer no n8n e no ambiente privado do servidor.
- O banco não consegue detectar sozinho todos os secrets em mensagens de erro; os workflows devem sanitizar conteúdo antes de persistir.
