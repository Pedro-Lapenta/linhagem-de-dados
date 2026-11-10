-- Como o grafo em torno deste ativo estava na data informada?
WITH RECURSIVE vigente AS (
    SELECT * FROM linhagem.dependencia
    WHERE vigente_de <= %(em)s::timestamptz
      AND (vigente_ate IS NULL OR vigente_ate > %(em)s::timestamptz)
),
acima AS (
    SELECT v.id, v.origem_id, 1 AS profundidade, ARRAY[v.destino_id, v.origem_id] AS visitados
    FROM vigente v WHERE v.destino_id = %(id)s AND %(subir)s::boolean
    UNION ALL
    SELECT v.id, v.origem_id, a.profundidade + 1, a.visitados || v.origem_id
    FROM acima a JOIN vigente v ON v.destino_id = a.origem_id
    WHERE v.origem_id <> ALL (a.visitados) AND a.profundidade < %(profundidade)s
),
abaixo AS (
    SELECT v.id, v.destino_id, 1 AS profundidade, ARRAY[v.origem_id, v.destino_id] AS visitados
    FROM vigente v WHERE v.origem_id = %(id)s AND %(descer)s::boolean
    UNION ALL
    SELECT v.id, v.destino_id, a.profundidade + 1, a.visitados || v.destino_id
    FROM abaixo a JOIN vigente v ON v.origem_id = a.destino_id
    WHERE v.destino_id <> ALL (a.visitados) AND a.profundidade < %(profundidade)s
),
arestas AS (
    SELECT id FROM acima UNION SELECT id FROM abaixo
)
SELECT d.id, d.origem_id, d.destino_id, o.codigo AS origem, x.codigo AS destino, d.tipo_relacao,
       d.processo_id, d.regra_id, d.evidencia, d.vigente_de, d.vigente_ate
FROM arestas a
JOIN linhagem.dependencia d ON d.id = a.id
JOIN linhagem.ativo o ON o.id = d.origem_id
JOIN linhagem.ativo x ON x.id = d.destino_id
ORDER BY o.codigo, x.codigo;
