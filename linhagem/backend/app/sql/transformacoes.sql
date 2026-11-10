-- Quais transformações produziram este ativo, na ordem em que acontecem?
WITH RECURSIVE acima AS (
    SELECT %(id)s::integer AS ativo_id, ARRAY[%(id)s::integer] AS visitados
    UNION ALL
    SELECT d.origem_id, a.visitados || d.origem_id
    FROM acima a
    JOIN linhagem.dependencia d ON d.destino_id = a.ativo_id
    WHERE d.vigente_ate IS NULL AND d.origem_id <> ALL (a.visitados)
),
processos AS (
    SELECT DISTINCT s.processo_id
    FROM acima a
    JOIN linhagem.processo_saida s ON s.ativo_id = a.ativo_id
)
SELECT p.ordem AS etapa, p.codigo, p.nome, p.tipo, p.script,
       (SELECT string_agg(r.codigo || ': ' || r.expressao, ' | ' ORDER BY r.codigo)
        FROM linhagem.processo_regra pr JOIN linhagem.regra r ON r.id = pr.regra_id
        WHERE pr.processo_id = p.id) AS regras,
       u.status AS ultima_execucao, u.parametros, u.finalizada_em
FROM processos x
JOIN linhagem.processo p ON p.id = x.processo_id
LEFT JOIN LATERAL (
    SELECT e.status, e.parametros, e.finalizada_em
    FROM linhagem.execucao e
    WHERE e.processo_id = p.id
    ORDER BY e.iniciada_em DESC
    LIMIT 1
) u ON true
ORDER BY p.ordem;
