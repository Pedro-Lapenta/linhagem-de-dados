-- Zona bruta: cópia fiel da fonte, sem alterar nenhum valor.
DROP TABLE IF EXISTS bruto.matricula;
CREATE TABLE bruto.matricula AS SELECT * FROM fontes.matricula;
