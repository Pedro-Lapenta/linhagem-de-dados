-- Reprovar aqui desfaz a transação: nada segue para a camada validada.
DROP TABLE IF EXISTS validado.relatorio_qualidade;
CREATE TABLE validado.relatorio_qualidade AS
SELECT 'completude_renda'::text AS regra,
       count(*) AS total,
       count(*) FILTER (WHERE renda_faixa <> 'nao_informada') AS conformes,
       round(count(*) FILTER (WHERE renda_faixa <> 'nao_informada')::numeric / count(*), 4) AS taxa,
       %(min_completude)s::numeric AS minimo
FROM tratado.trajetoria_academica;

DO $$
DECLARE
    v_taxa numeric;
    v_minimo numeric;
BEGIN
    SELECT taxa, minimo INTO v_taxa, v_minimo FROM validado.relatorio_qualidade;
    IF v_taxa < v_minimo THEN
        RAISE EXCEPTION 'Validação reprovada: completude de renda %% abaixo do mínimo %%', v_taxa, v_minimo;
    END IF;
END;
$$;

DROP TABLE IF EXISTS validado.trajetoria_academica;
CREATE TABLE validado.trajetoria_academica AS
SELECT * FROM tratado.trajetoria_academica;
