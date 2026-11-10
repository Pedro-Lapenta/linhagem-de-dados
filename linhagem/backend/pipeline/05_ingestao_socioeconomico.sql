-- Zona bruta: cópia fiel da fonte, sem alterar nenhum valor.
DROP TABLE IF EXISTS bruto.socioeconomico;
CREATE TABLE bruto.socioeconomico AS SELECT * FROM fontes.socioeconomico;
