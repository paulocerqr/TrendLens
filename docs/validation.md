# Validação da Fase 12

## Objetivo

A Fase 12 verifica a qualidade dos dados e das heurísticas antes de qualquer calibração de pesos. O processo separa evidência quantitativa, revisão humana do classificador e decisão de calibração.

O relatório é gerado por `build_phase12_validation` em uma janela fechada de sete dias. Cada execução persiste o mesmo contrato JSON em `pipeline_validation_reports` e prepara até 30 vídeos ainda não revisados por `select_classification_review_candidates`.

Depois da migration de idioma, tanto a cobertura quanto a fila de revisão consideram somente vídeos com `language_eligibility` no estado `eligible`. Isso evita usar classificações estrangeiras para estimar a qualidade do classificador voltado ao mercado brasileiro, sem apagar revisões ou resultados históricos.

## Portas de prontidão

Os pesos v1 só ficam elegíveis para calibração manual quando as três condições abaixo forem atendidas:

- ao menos três dias de observações de snapshots;
- ao menos 30 classificações revisadas por uma pessoa;
- amostra mínima de 30 vídeos em cada uma das seis categorias da comparação obrigatória.

As categorias exigidas são Movie / TV Clips, Curiosidades, Tutoriais, Podcast Clips, Tecnologia e Storytelling.

Enquanto alguma porta estiver fechada, o relatório retorna `insufficient_data` e a decisão `hold_v1_collect_more_data`. O sistema nunca ajusta pesos automaticamente.

## Revisão manual do classificador

A fila é estratificada por categoria e pelas faixas de confiança `low`, `medium` e `high`. A seleção é determinística para uma mesma seed e exclui vídeos já revisados na mesma versão de prompt.

Cada revisão é armazenada em `classification_validation_reviews`. Os valores produzidos pela IA não são sobrescritos. A pessoa revisora marca a adequação de dez dimensões e pode registrar correções em `corrected_values`.

Exemplo de registro:

```sql
INSERT INTO classification_validation_reviews (
    video_id, prompt_version, reviewer,
    category_correct, topic_correct, content_type_correct,
    format_correct, hook_type_correct, source_type_correct,
    presentation_style_correct, originality_reasonable,
    copyright_risk_reasonable, reused_content_risk_reasonable,
    corrected_values, notes
) VALUES (
    123, 'v1', 'reviewer-id',
    true, true, true,
    false, true, true,
    true, true,
    true, true,
    '{"format":"commentary"}'::JSONB,
    'O vídeo adiciona comentário próprio ao trecho.'
);
```

O nome da pessoa revisora deve ser um identificador interno, sem email, token ou outro dado sensível.

## Diagnósticos

### Snapshots

O relatório verifica cobertura, pares comparáveis, redução observada de contadores, lacunas acima da cadência configurada e erros terminais do Snapshot Tracker. Reduções não são corrigidas automaticamente. Likes e comentários podem cair por ações legítimas da plataforma; esses sinais exigem investigação, não alteração dos dados históricos.

### Scores

Virality e Monetization expõem mínimo, P10, mediana, P90, máximo e taxas nas caudas `<= 1` e `>= 9`. O Virality Score também reporta disponibilidade e correlação de cada componente com o resultado final.

Correlação é usada apenas para localizar possível dominância ou redundância. Ela não mede causalidade e não autoriza ajuste isolado de peso.

### Movie/TV Clips vs outros formatos

O relatório apresenta tamanho da amostra, mediana, P75 e P90 de views, velocidade, engajamento, taxa de outliers e os scores de Virality, Monetization, Consistency e Opportunity. Categorias ausentes permanecem no JSON com métricas nulas e `sufficient_sample = false`.

## Primeira execução real

O primeiro relatório foi gerado em 22 de agosto de 2026, usando a janela fechada até 22:00 em `America/Sao_Paulo`.

| Indicador | Resultado |
| --- | ---: |
| Vídeos na janela | 210 |
| Snapshots | 568 |
| Vídeos com acompanhamento | 210 |
| Período observado | 1,236 dia |
| Classificações | 45 |
| Revisões humanas | 0 |
| Virality Scores | 210 |
| Monetization Scores | 45 |
| Vídeos da amostra `recent` | 149 |
| Vídeos da amostra `high_performance` | 61 |

A confiança média do classificador foi `0,6289`; 25 das 45 classificações ficaram abaixo do piso `0,65`. O workflow preparou 30 candidatos estratificados para revisão humana.

O Virality Score apresentou mediana `5,3402`, P10 `2,8194` e P90 `7,2265`. O Monetization Score apresentou mediana `4,0910`, P10 `1,2812` e P90 `5,0933`. As taxas nas caudas não ultrapassaram o limite de 10%.

O componente `outlier_percentile` estava ausente nos 210 vídeos. Isso decorre da falta de baseline de canal suficiente na amostra atual e faz o peso correspondente ser redistribuído entre os demais componentes disponíveis. A correlação observada entre velocity e Virality Score foi `0,9074`; esse valor deve ser reavaliado quando o componente de outlier ganhar cobertura.

O Snapshot Tracker apresentou 318 lacunas de cadência, sete reduções de likes e 20 eventos terminais na janela. Não houve redução de views. Esses números indicam atenção operacional, mas não provam perda ou corrupção de dados.

## Comparação inicial real

Os resultados abaixo são exploratórios e não sustentam a hipótese por causa da amostra reduzida.

| Categoria | Amostra | Mediana de views | P75 | P90 | Virality | Monetization | Opportunity |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Movie / TV Clips | 2 | 2.666,5 | 2.717,75 | 2.748,5 | 4,2123 | 0,9476 | 2,6943 |
| Curiosidades | 1 | 2.886 | 2.886 | 2.886 | 4,3089 | 3,8386 | 3,7527 |
| Tutoriais | 0 | n/d | n/d | n/d | n/d | n/d | n/d |
| Podcast Clips | 1 | 0 | 0 | 0 | 1,3619 | 2,8157 | 1,8664 |
| Tecnologia | 2 | 49.359 | 72.637,5 | 86.604,6 | 6,5261 | 3,5483 | 4,7943 |
| Storytelling | 0 | n/d | n/d | n/d | n/d | n/d | n/d |

Nenhuma categoria atingiu a amostra mínima de 30. Portanto, a hipótese Movie/TV Clips vs outros formatos permanece não testada.

## Decisão sobre pesos

Decisão atual: `hold_v1_collect_more_data`.

Não foi aplicado ajuste. Uma proposta de pesos v2 só deve ser documentada depois da revisão humana, da cobertura mínima das categorias e de uma nova leitura dos componentes ausentes e das correlações.
