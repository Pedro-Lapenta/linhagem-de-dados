DROP TABLE IF EXISTS mart.relatorio_evasao_campus;
CREATE TABLE mart.relatorio_evasao_campus AS
SELECT campus,
       sum(alunos)::bigint AS alunos,
       sum(evadidos)::bigint AS evadidos,
       round(sum(evadidos)::numeric / sum(alunos), 4) AS taxa_evasao
FROM mart.indicador_taxa_evasao
GROUP BY campus;
