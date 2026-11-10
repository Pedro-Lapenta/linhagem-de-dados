-- Quais fontes originaram este ativo? Mantém só os ativos sem predecessores vigentes.
WITH RECURSIVE acima AS (
    SELECT %(id)s::integer AS ativo_id, 0 AS profundidade, ARRAY[%(id)s::integer] AS visitados
    UNION ALL
    SELECT d.origem_id, a.profundidade + 1, a.visitados || d.origem_id
    FROM acima a
    JOIN linhagem.dependencia d ON d.destino_id = a.ativo_id
    WHERE d.vigente_ate IS NULL AND d.origem_id <> ALL (a.visitados)
),
raiz AS (
    SELECT ativo_id, max(profundidade) AS etapas
    FROM acima
    WHERE profundidade > 0
      AND NOT EXISTS (SELECT 1 FROM linhagem.dependencia d
                      WHERE d.destino_id = acima.ativo_id AND d.vigente_ate IS NULL)
    GROUP BY ativo_id
)
SELECT at.id AS ativo_id, at.codigo, at.nome, r.etapas,
       p.sistema_origem, p.instituicao, p.cidade, p.periodicidade, p.data_extracao,
       (SELECT max(v.numero) FROM linhagem.ativo_versao v WHERE v.ativo_id = at.id) AS versao_atual
FROM raiz r
JOIN linhagem.ativo at ON at.id = r.ativo_id
LEFT JOIN linhagem.proveniencia p ON p.ativo_id = at.id
ORDER BY at.codigo;
