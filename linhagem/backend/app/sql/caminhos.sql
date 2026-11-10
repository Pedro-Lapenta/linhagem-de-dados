-- Todos os caminhos entre dois ativos.
WITH RECURSIVE busca AS (
    SELECT %(origem)s::integer AS ativo_id, ARRAY[%(origem)s::integer] AS visitados
    UNION ALL
    SELECT d.destino_id, b.visitados || d.destino_id
    FROM busca b
    JOIN linhagem.dependencia d ON d.origem_id = b.ativo_id
    WHERE d.vigente_ate IS NULL
      AND d.destino_id <> ALL (b.visitados)
      AND b.ativo_id <> %(destino)s::integer
)
SELECT cardinality(b.visitados) - 1 AS etapas,
       (SELECT string_agg(x.codigo, ' -> ' ORDER BY v.ord)
        FROM unnest(b.visitados) WITH ORDINALITY AS v (id, ord)
        JOIN linhagem.ativo x ON x.id = v.id) AS caminho
FROM busca b
WHERE b.ativo_id = %(destino)s::integer AND cardinality(b.visitados) > 1
ORDER BY etapas, caminho;
