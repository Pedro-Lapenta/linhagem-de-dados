DROP TABLE IF EXISTS mart.indicador_taxa_evasao;
CREATE TABLE mart.indicador_taxa_evasao AS
SELECT cod_curso, curso, campus,
       count(*) AS alunos,
       count(*) FILTER (WHERE evadido) AS evadidos,
       round(count(*) FILTER (WHERE evadido)::numeric / count(*), 4) AS taxa_evasao
FROM mart.permanencia
GROUP BY cod_curso, curso, campus;
