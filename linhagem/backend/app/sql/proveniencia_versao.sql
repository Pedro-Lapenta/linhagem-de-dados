-- Qual versão de cada ativo alimentou esta versão? Segue as execuções, não o catálogo atual.
WITH RECURSIVE prov AS (
    SELECT v.id AS versao_id, v.ativo_id, v.numero, v.checksum, v.linhas, v.parametros, v.execucao_id,
           v.criado_em, 0 AS profundidade, ARRAY[v.id] AS visitadas
    FROM linhagem.ativo_versao v
    WHERE v.id = %(versao_id)s
    UNION ALL
    SELECT ve.id, ve.ativo_id, ve.numero, ve.checksum, ve.linhas, ve.parametros, ve.execucao_id,
           ve.criado_em, p.profundidade + 1, p.visitadas || ve.id
    FROM prov p
    JOIN linhagem.execucao_entrada ee ON ee.execucao_id = p.execucao_id
    JOIN linhagem.ativo_versao ve ON ve.id = ee.ativo_versao_id
    WHERE ve.id <> ALL (p.visitadas)
),
unica AS (
    SELECT DISTINCT ON (versao_id) * FROM prov ORDER BY versao_id, profundidade
)
SELECT u.profundidade, a.codigo, a.nome, a.tipo, u.versao_id, u.numero AS versao, u.linhas,
       left(u.checksum, 12) AS checksum, u.parametros, u.execucao_id, u.criado_em
FROM unica u
JOIN linhagem.ativo a ON a.id = u.ativo_id
ORDER BY u.profundidade, a.codigo;
