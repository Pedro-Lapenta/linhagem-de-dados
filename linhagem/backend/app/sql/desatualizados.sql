-- Ativos cuja última execução leu uma versão já superada, mais tudo o que depende deles.
WITH RECURSIVE ultima AS (
    SELECT DISTINCT ON (s.ativo_id) s.ativo_id, e.id AS execucao_id
    FROM linhagem.processo_saida s
    JOIN linhagem.execucao e ON e.processo_id = s.processo_id AND e.status IN ('sucesso', 'parcial')
    ORDER BY s.ativo_id, e.iniciada_em DESC
),
direto AS (
    SELECT DISTINCT u.ativo_id, a.codigo AS causa
    FROM ultima u
    JOIN linhagem.execucao_entrada ee ON ee.execucao_id = u.execucao_id
    JOIN linhagem.ativo_versao v ON v.id = ee.ativo_versao_id
    JOIN linhagem.ativo a ON a.id = v.ativo_id
    WHERE v.numero < (SELECT max(m.numero) FROM linhagem.ativo_versao m WHERE m.ativo_id = v.ativo_id)
),
propagado AS (
    SELECT ativo_id, causa, ARRAY[ativo_id] AS visitados FROM direto
    UNION ALL
    SELECT d.destino_id, p.causa, p.visitados || d.destino_id
    FROM propagado p
    JOIN linhagem.dependencia d ON d.origem_id = p.ativo_id
    WHERE d.vigente_ate IS NULL AND d.destino_id <> ALL (p.visitados)
)
SELECT a.id AS ativo_id, a.codigo, a.nome, a.tipo,
       string_agg(DISTINCT p.causa, ', ') AS causa
FROM propagado p
JOIN linhagem.ativo a ON a.id = p.ativo_id
GROUP BY a.id, a.codigo, a.nome, a.tipo
ORDER BY a.codigo;
