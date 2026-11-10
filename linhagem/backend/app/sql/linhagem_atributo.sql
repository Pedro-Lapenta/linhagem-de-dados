-- De quais colunas este atributo deriva, até a origem?
WITH RECURSIVE acima AS (
    SELECT d.origem_id AS atributo_id, d.destino_id AS deriva_id, d.regra_id, d.processo_id,
           1 AS profundidade, ARRAY[d.destino_id, d.origem_id] AS visitados
    FROM linhagem.atributo_derivacao d
    WHERE d.destino_id = %(atributo_id)s
    UNION ALL
    SELECT d.origem_id, d.destino_id, d.regra_id, d.processo_id,
           a.profundidade + 1, a.visitados || d.origem_id
    FROM acima a
    JOIN linhagem.atributo_derivacao d ON d.destino_id = a.atributo_id
    WHERE d.origem_id <> ALL (a.visitados)
),
unico AS (
    SELECT DISTINCT ON (atributo_id, deriva_id) *
    FROM acima
    ORDER BY atributo_id, deriva_id, profundidade
)
SELECT u.profundidade, u.atributo_id, u.deriva_id,
       ao.codigo || '.' || o.nome AS atributo_origem,
       ad.codigo || '.' || d.nome AS atributo_derivado,
       r.codigo AS regra, r.expressao, p.codigo AS processo,
       NOT EXISTS (SELECT 1 FROM linhagem.atributo_derivacao x WHERE x.destino_id = u.atributo_id) AS coluna_original
FROM unico u
JOIN linhagem.atributo o ON o.id = u.atributo_id
JOIN linhagem.ativo ao ON ao.id = o.ativo_id
JOIN linhagem.atributo d ON d.id = u.deriva_id
JOIN linhagem.ativo ad ON ad.id = d.ativo_id
LEFT JOIN linhagem.regra r ON r.id = u.regra_id
LEFT JOIN linhagem.processo p ON p.id = u.processo_id
ORDER BY u.profundidade, atributo_origem;
