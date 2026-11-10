-- Fechamento transitivo, auditabilidade, métricas e critérios de validação do Módulo 11.
SET search_path TO linhagem;

CREATE VIEW vw_aresta_vigente AS
SELECT * FROM dependencia WHERE vigente_ate IS NULL;

CREATE VIEW vw_fechamento AS
WITH RECURSIVE fechamento (ascendente_id, descendente_id, profundidade, caminho) AS (
    SELECT origem_id, destino_id, 1, ARRAY[origem_id, destino_id]
    FROM vw_aresta_vigente
    UNION ALL
    SELECT f.ascendente_id, d.destino_id, f.profundidade + 1, f.caminho || d.destino_id
    FROM fechamento f
    JOIN vw_aresta_vigente d ON d.origem_id = f.descendente_id
    WHERE d.destino_id <> ALL (f.caminho)
)
SELECT * FROM fechamento;

-- Um ativo é auditável quando origem, versões, processos, regras, responsável,
-- evidências e produtos derivados estão documentados (Módulo 11, seção 10.4).
CREATE VIEW vw_auditabilidade AS
WITH fech AS (SELECT DISTINCT ascendente_id, descendente_id FROM vw_fechamento),
base AS (
    SELECT a.id AS ativo_id, a.codigo, a.nome, a.tipo, a.critico,
        (EXISTS (SELECT 1 FROM proveniencia p WHERE p.ativo_id = a.id)
         OR EXISTS (SELECT 1 FROM fech f JOIN proveniencia p ON p.ativo_id = f.ascendente_id
                    WHERE f.descendente_id = a.id)) AS tem_origem,
        EXISTS (SELECT 1 FROM ativo_versao v WHERE v.ativo_id = a.id) AS tem_versoes,
        (EXISTS (SELECT 1 FROM processo_saida s WHERE s.ativo_id = a.id)
         OR (a.tipo = 'fonte' AND EXISTS (SELECT 1 FROM processo_entrada e WHERE e.ativo_id = a.id))) AS tem_processos,
        (a.tipo = 'fonte'
         OR EXISTS (SELECT 1 FROM processo_saida s JOIN processo_regra r USING (processo_id)
                    WHERE s.ativo_id = a.id)
         OR EXISTS (SELECT 1 FROM fech f JOIN processo_saida s ON s.ativo_id = f.ascendente_id
                    JOIN processo_regra r USING (processo_id)
                    WHERE f.descendente_id = a.id)) AS tem_regras,
        a.responsavel_id IS NOT NULL AS tem_responsavel,
        (EXISTS (SELECT 1 FROM ativo_versao v JOIN execucao_saida es ON es.ativo_versao_id = v.id
                 JOIN execucao e ON e.id = es.execucao_id
                 WHERE v.ativo_id = a.id AND e.evidencia IS NOT NULL)
         OR (a.tipo = 'fonte' AND EXISTS (SELECT 1 FROM ativo_versao v WHERE v.ativo_id = a.id))) AS tem_evidencias,
        EXISTS (SELECT 1 FROM vw_aresta_vigente d WHERE d.origem_id = a.id) AS tem_derivados
    FROM ativo a
    WHERE a.status = 'ativo' AND a.tipo <> 'consumidor'
)
SELECT base.*,
    round((tem_origem::int + tem_versoes::int + tem_processos::int + tem_regras::int
           + tem_responsavel::int + tem_evidencias::int + tem_derivados::int) / 7.0, 4) AS iaa
FROM base;

CREATE FUNCTION razao(numerador numeric, denominador numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$ SELECT round(numerador / NULLIF(denominador, 0), 4) $$;

CREATE VIEW vw_metricas AS
WITH
ativos AS (SELECT * FROM ativo WHERE status = 'ativo' AND tipo <> 'consumidor'),
produtos AS (SELECT * FROM ativos WHERE tipo IN ('indicador', 'dashboard', 'api', 'relatorio', 'produto_dados')),
transf AS (SELECT * FROM processo WHERE tipo IN ('integracao', 'transformacao')),
prof AS (
    SELECT f.descendente_id, max(f.profundidade) AS profundidade
    FROM vw_fechamento f
    JOIN ativo o ON o.id = f.ascendente_id AND o.tipo = 'fonte'
    JOIN produtos p ON p.id = f.descendente_id
    GROUP BY f.descendente_id
),
m (ordem, sigla, nome, descricao, numerador, denominador, valor, unidade) AS (
    SELECT 1, 'CLA', 'Cobertura de linhagem de ativos', 'Ativos com linhagem registrada',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM vw_aresta_vigente x
                 WHERE x.origem_id = a.id OR x.destino_id = a.id))::numeric n, count(*)::numeric d FROM ativos a) s
    UNION ALL
    SELECT 2, 'CP', 'Cobertura de proveniência', 'Ativos com origem documentada',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE tem_origem)::numeric n, count(*)::numeric d FROM vw_auditabilidade) s
    UNION ALL
    SELECT 3, 'CLAtr', 'Cobertura de linhagem de atributos', 'Atributos críticos com linhagem registrada',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM atributo_derivacao x
                 WHERE x.origem_id = at.id OR x.destino_id = at.id))::numeric n, count(*)::numeric d
          FROM atributo at JOIN ativos a ON a.id = at.ativo_id WHERE at.critico) s
    UNION ALL
    SELECT 4, 'CPR', 'Cobertura de processos rastreáveis', 'Processos com entrada, saída e parâmetros documentados',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM processo_entrada e WHERE e.processo_id = p.id)
                 AND EXISTS (SELECT 1 FROM processo_saida s WHERE s.processo_id = p.id))::numeric n,
                 count(*)::numeric d FROM processo p) s
    UNION ALL
    SELECT 5, 'TAA', 'Taxa de ativos auditáveis', 'Ativos críticos com IAA mínimo de 0,85',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE iaa >= 0.85)::numeric n, count(*)::numeric d
          FROM vw_auditabilidade WHERE critico) s
    UNION ALL
    SELECT 6, 'TPFI', 'Taxa de produtos com fontes identificáveis', 'Produtos que alcançam ao menos uma fonte original',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT (SELECT count(*) FROM prof)::numeric n, (SELECT count(*) FROM produtos)::numeric d) s
    UNION ALL
    SELECT 7, 'TTR', 'Taxa de transformações rastreáveis', 'Transformações com entrada, saída, regra, parâmetro e evidência',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM processo_entrada e WHERE e.processo_id = t.id)
                 AND EXISTS (SELECT 1 FROM processo_saida s WHERE s.processo_id = t.id)
                 AND EXISTS (SELECT 1 FROM processo_regra r WHERE r.processo_id = t.id)
                 AND EXISTS (SELECT 1 FROM execucao e WHERE e.processo_id = t.id AND e.evidencia IS NOT NULL))::numeric n,
                 count(*)::numeric d FROM transf t) s
    UNION ALL
    SELECT 8, 'PML', 'Profundidade média da linhagem', 'Etapas rastreáveis entre fonte e produto',
        NULL::numeric, NULL::numeric, round(avg(profundidade), 2), 'etapas'
    FROM prof
    UNION ALL
    SELECT 9, 'TDD', 'Taxa de dependências documentadas', 'Relações com processo ou evidência registrados',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE processo_id IS NOT NULL OR evidencia IS NOT NULL)::numeric n,
                 count(*)::numeric d FROM vw_aresta_vigente) s
    UNION ALL
    SELECT 10, 'TIR', 'Taxa de impacto rastreável', 'Análises de impacto com propagação identificada',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE jsonb_array_length(ativos) > 0)::numeric n,
                 count(*)::numeric d FROM analise_impacto) s
    UNION ALL
    SELECT 11, 'TLI', 'Taxa de linhagem incompleta', 'Ativos com lacunas de rastreabilidade (quanto menor, melhor)',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE iaa < 0.85)::numeric n, count(*)::numeric d FROM vw_auditabilidade) s
    UNION ALL
    SELECT 12, 'TMR', 'Tempo médio de reconstrução', 'Duração média das consultas que reconstroem a trajetória',
        NULL::numeric, NULL::numeric, round(avg(duracao_ms), 2), 'ms'
    FROM consulta_log
    WHERE respondida AND consulta IN ('ascendentes', 'fontes_originais', 'proveniencia_versao')
    UNION ALL
    SELECT 13, 'TEA', 'Taxa de evidências associadas', 'Execuções com manifesto ou log associado',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE evidencia IS NOT NULL OR log IS NOT NULL)::numeric n,
                 count(*)::numeric d FROM execucao) s
    UNION ALL
    SELECT 14, 'TCLR', 'Taxa de consultas de linhagem respondidas', 'Consultas executadas com resposta',
        n, d, razao(n, d), 'proporcao'
    FROM (SELECT count(*) FILTER (WHERE respondida)::numeric n, count(*)::numeric d FROM consulta_log) s
    UNION ALL
    SELECT 15, 'IAA', 'Índice de auditabilidade do ativo', 'Média do índice nos ativos críticos',
        NULL::numeric, NULL::numeric, round(avg(iaa), 4), 'proporcao'
    FROM vw_auditabilidade WHERE critico
)
SELECT * FROM m ORDER BY ordem;

-- Os 12 critérios da seção 23 do Módulo 11. Cada linha traz atendidos/total.
CREATE VIEW vw_criterios AS
WITH
crit AS (SELECT * FROM ativo WHERE status = 'ativo' AND critico AND tipo <> 'consumidor'),
c (numero, criterio, atendidos, total) AS (
    SELECT 1, 'Ativos críticos possuem origem documentada',
        (SELECT count(*) FROM vw_auditabilidade WHERE critico AND tem_origem),
        (SELECT count(*) FROM crit)
    UNION ALL
    SELECT 2, 'Datasets brutos possuem registros de proveniência',
        (SELECT count(*) FROM ativo a WHERE a.tipo = 'dataset_bruto' AND EXISTS (
            SELECT 1 FROM vw_aresta_vigente d JOIN proveniencia p ON p.ativo_id = d.origem_id WHERE d.destino_id = a.id)),
        (SELECT count(*) FROM ativo WHERE tipo = 'dataset_bruto')
    UNION ALL
    SELECT 3, 'Ingestões possuem logs e manifestos associados',
        (SELECT count(*) FROM processo p WHERE p.tipo = 'ingestao' AND EXISTS (
            SELECT 1 FROM execucao e WHERE e.processo_id = p.id AND e.log IS NOT NULL AND e.evidencia IS NOT NULL)),
        (SELECT count(*) FROM processo WHERE tipo = 'ingestao')
    UNION ALL
    SELECT 4, 'Integrações possuem fontes, chaves, regras e saídas documentadas',
        (SELECT count(*) FROM processo p WHERE p.tipo = 'integracao'
            AND EXISTS (SELECT 1 FROM processo_entrada x WHERE x.processo_id = p.id)
            AND EXISTS (SELECT 1 FROM processo_saida x WHERE x.processo_id = p.id)
            AND EXISTS (SELECT 1 FROM processo_regra x WHERE x.processo_id = p.id)),
        (SELECT count(*) FROM processo WHERE tipo = 'integracao')
    UNION ALL
    SELECT 5, 'Transformações possuem entrada, saída, regra, parâmetro e evidência',
        (SELECT numerador::bigint FROM vw_metricas WHERE sigla = 'TTR'),
        (SELECT denominador::bigint FROM vw_metricas WHERE sigla = 'TTR')
    UNION ALL
    SELECT 6, 'Datasets tratados possuem vínculo com datasets de origem',
        (SELECT count(*) FROM ativo a WHERE a.tipo = 'dataset_tratado' AND EXISTS (
            SELECT 1 FROM vw_aresta_vigente d WHERE d.destino_id = a.id)),
        (SELECT count(*) FROM ativo WHERE tipo = 'dataset_tratado')
    UNION ALL
    SELECT 7, 'Produtos de dados possuem relação com os ativos que os alimentam',
        (SELECT numerador::bigint FROM vw_metricas WHERE sigla = 'TPFI'),
        (SELECT denominador::bigint FROM vw_metricas WHERE sigla = 'TPFI')
    UNION ALL
    SELECT 8, 'Atributos derivados críticos possuem linhagem documentada',
        (SELECT numerador::bigint FROM vw_metricas WHERE sigla = 'CLAtr'),
        (SELECT denominador::bigint FROM vw_metricas WHERE sigla = 'CLAtr')
    UNION ALL
    SELECT 9, 'Versões e snapshots estão associados aos ativos',
        (SELECT count(*) FROM crit a WHERE EXISTS (SELECT 1 FROM ativo_versao v WHERE v.ativo_id = a.id)),
        (SELECT count(*) FROM crit)
    UNION ALL
    SELECT 10, 'É possível navegar da fonte ao produto e do produto à fonte',
        (SELECT numerador::bigint FROM vw_metricas WHERE sigla = 'TPFI'),
        (SELECT denominador::bigint FROM vw_metricas WHERE sigla = 'TPFI')
    UNION ALL
    SELECT 11, 'Mudanças em fontes permitem análise de impacto',
        (SELECT count(*) FROM ativo a WHERE a.tipo = 'fonte' AND a.status = 'ativo'
            AND EXISTS (SELECT 1 FROM vw_aresta_vigente d WHERE d.origem_id = a.id)),
        (SELECT count(*) FROM ativo WHERE tipo = 'fonte' AND status = 'ativo')
    UNION ALL
    SELECT 12, 'Ativos críticos possuem índice de auditabilidade satisfatório',
        (SELECT numerador::bigint FROM vw_metricas WHERE sigla = 'TAA'),
        (SELECT denominador::bigint FROM vw_metricas WHERE sigla = 'TAA')
)
SELECT numero, criterio, atendidos, total,
       total > 0 AND atendidos = total AS atendido
FROM c ORDER BY numero;
