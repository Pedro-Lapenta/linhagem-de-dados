-- O que é afetado se este ativo mudar? Desce o grafo e classifica a severidade.
WITH RECURSIVE abaixo AS (
    SELECT d.destino_id AS ativo_id, 1 AS profundidade,
           ARRAY[d.origem_id, d.destino_id] AS visitados
    FROM linhagem.dependencia d
    WHERE d.origem_id = %(id)s AND d.vigente_ate IS NULL
    UNION ALL
    SELECT d.destino_id, a.profundidade + 1, a.visitados || d.destino_id
    FROM abaixo a
    JOIN linhagem.dependencia d ON d.origem_id = a.ativo_id
    WHERE d.vigente_ate IS NULL AND d.destino_id <> ALL (a.visitados)
),
menor AS (
    SELECT DISTINCT ON (ativo_id) *
    FROM abaixo
    ORDER BY ativo_id, profundidade
)
SELECT m.profundidade, at.id AS ativo_id, at.codigo, at.nome, at.tipo,
       CASE
           WHEN at.critico AND at.tipo IN ('dashboard', 'indicador', 'api', 'relatorio') THEN 'critica'
           WHEN at.critico OR at.tipo = 'consumidor' THEN 'alta'
           WHEN at.tipo IN ('dashboard', 'api', 'relatorio', 'feature') THEN 'media'
           ELSE 'baixa'
       END AS severidade,
       CASE
           WHEN at.tipo = 'consumidor' THEN 'comunicar'
           WHEN at.tipo IN ('dashboard', 'api', 'relatorio', 'indicador') THEN 'revisar'
           ELSE 'reprocessar'
       END AS acao,
       r.nome AS responsavel,
       (SELECT string_agg(x.codigo, ' -> ' ORDER BY v.ord)
        FROM unnest(m.visitados) WITH ORDINALITY AS v (id, ord)
        JOIN linhagem.ativo x ON x.id = v.id) AS caminho
FROM menor m
JOIN linhagem.ativo at ON at.id = m.ativo_id
LEFT JOIN linhagem.responsavel r ON r.id = at.responsavel_id
ORDER BY m.profundidade, at.codigo;
