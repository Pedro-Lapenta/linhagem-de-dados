-- De onde este ativo veio? Sobe o grafo aresta a aresta, sem revisitar nós.
WITH RECURSIVE arvore AS (
    SELECT d.origem_id AS ativo_id, d.destino_id AS alimenta_id, d.tipo_relacao, d.processo_id,
           1 AS profundidade,
           ARRAY[d.destino_id, d.origem_id] AS visitados
    FROM linhagem.dependencia d
    WHERE d.destino_id = %(id)s AND d.vigente_ate IS NULL
    UNION ALL
    SELECT d.origem_id, d.destino_id, d.tipo_relacao, d.processo_id,
           a.profundidade + 1,
           a.visitados || d.origem_id
    FROM arvore a
    JOIN linhagem.dependencia d ON d.destino_id = a.ativo_id
    WHERE d.vigente_ate IS NULL
      AND d.origem_id <> ALL (a.visitados)
      AND a.profundidade < %(profundidade)s
),
unico AS (
    SELECT DISTINCT ON (ativo_id, alimenta_id) *
    FROM arvore
    ORDER BY ativo_id, alimenta_id, profundidade
)
SELECT u.profundidade, at.id AS ativo_id, at.codigo, at.nome, at.tipo,
       al.codigo AS alimenta, u.tipo_relacao, p.codigo AS processo,
       (SELECT string_agg(x.codigo, ' <- ' ORDER BY v.ord)
        FROM unnest(u.visitados) WITH ORDINALITY AS v (id, ord)
        JOIN linhagem.ativo x ON x.id = v.id) AS caminho
FROM unico u
JOIN linhagem.ativo at ON at.id = u.ativo_id
JOIN linhagem.ativo al ON al.id = u.alimenta_id
LEFT JOIN linhagem.processo p ON p.id = u.processo_id
ORDER BY u.profundidade, at.codigo, al.codigo;
