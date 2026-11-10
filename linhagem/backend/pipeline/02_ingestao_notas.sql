-- Zona bruta: cópia fiel da fonte, sem alterar nenhum valor.
DROP TABLE IF EXISTS bruto.notas;
CREATE TABLE bruto.notas AS SELECT * FROM fontes.notas;
