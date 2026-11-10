-- Quais atributos são afetados se esta coluna mudar?
WITH RECURSIVE abaixo AS (
    SELECT d.destino_id AS atributo_id, 1 AS profundidade, ARRAY[d.origem_id, d.destino_id] AS visitados
    FROM linhagem.atributo_derivacao d
    WHERE d.origem_id = %(atributo_id)s
    UNION ALL
    SELECT d.destino_id, a.profundidade + 1, a.visitados || d.destino_id
    FROM abaixo a
    JOIN linhagem.atributo_derivacao d ON d.origem_id = a.atributo_id
    WHERE d.destino_id <> ALL (a.visitados)
),
menor AS (
    SELECT DISTINCT ON (atributo_id) * FROM abaixo ORDER BY atributo_id, profundidade
)
SELECT m.profundidade, ati.id AS ativo_id, ati.codigo, ati.nome, ati.tipo,
       ati.codigo || '.' || at.nome AS atributo,
       CASE WHEN at.critico AND ati.tipo IN ('dashboard', 'indicador', 'api', 'relatorio') THEN 'critica'
            WHEN at.critico THEN 'alta' ELSE 'media' END AS severidade,
       CASE WHEN ati.tipo IN ('dashboard', 'api', 'relatorio', 'indicador') THEN 'revisar'
            ELSE 'reprocessar' END AS acao,
       r.nome AS responsavel
FROM menor m
JOIN linhagem.atributo at ON at.id = m.atributo_id
JOIN linhagem.ativo ati ON ati.id = at.ativo_id
LEFT JOIN linhagem.responsavel r ON r.id = ati.responsavel_id
ORDER BY m.profundidade, atributo;
