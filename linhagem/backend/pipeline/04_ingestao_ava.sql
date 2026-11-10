-- Zona bruta: cópia fiel da fonte, sem alterar nenhum valor.
DROP TABLE IF EXISTS bruto.ava;
CREATE TABLE bruto.ava AS SELECT * FROM fontes.ava;
