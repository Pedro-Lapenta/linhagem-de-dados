-- Zona bruta: cópia fiel da fonte, sem alterar nenhum valor.
DROP TABLE IF EXISTS bruto.frequencia;
CREATE TABLE bruto.frequencia AS SELECT * FROM fontes.frequencia;
