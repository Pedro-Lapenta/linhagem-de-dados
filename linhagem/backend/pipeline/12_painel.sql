DROP TABLE IF EXISTS mart.painel_evasao;
CREATE TABLE mart.painel_evasao AS
SELECT cod_curso, curso, campus, alunos, evadidos, taxa_evasao,
       CASE WHEN taxa_evasao >= 0.35 THEN 'alta'
            WHEN taxa_evasao >= 0.25 THEN 'media'
            ELSE 'baixa' END AS faixa_risco
FROM mart.indicador_taxa_evasao;
