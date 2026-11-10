DROP TABLE IF EXISTS mart.api_evasao;
CREATE TABLE mart.api_evasao AS
SELECT cod_curso, taxa_evasao
FROM mart.indicador_taxa_evasao;
