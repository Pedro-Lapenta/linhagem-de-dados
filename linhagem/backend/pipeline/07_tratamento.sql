-- Separa inconsistentes, imputa ausentes e deriva a baixa frequência.
DROP TABLE IF EXISTS tratado.trajetoria_rejeitados;
CREATE TABLE tratado.trajetoria_rejeitados AS
SELECT t.*,
       CASE WHEN t.curso IS NULL THEN 'curso_nulo'
            WHEN t.nota_maxima > 10 OR t.nota_minima < 0 THEN 'nota_fora_do_intervalo'
            ELSE 'frequencia_fora_do_intervalo' END AS motivo
FROM integrado.trajetoria t
WHERE t.curso IS NULL OR t.nota_maxima > 10 OR t.nota_minima < 0 OR t.frequencia_maxima > 100;

DROP TABLE IF EXISTS tratado.trajetoria_academica;
CREATE TABLE tratado.trajetoria_academica AS
SELECT t.ra, t.periodo, t.ano, t.semestre, t.cod_curso, t.curso, t.campus, t.situacao,
       t.media_notas, t.frequencia_media,
       t.frequencia_media < %(limite_frequencia)s AS baixa_frequencia,
       COALESCE(t.acessos, 0) AS acessos,
       COALESCE(t.atividades, 0) AS atividades,
       COALESCE(t.renda_faixa, 'nao_informada') AS renda_faixa,
       t.escola_publica, t.trabalha
FROM integrado.trajetoria t
WHERE NOT (t.curso IS NULL OR t.nota_maxima > 10 OR t.nota_minima < 0 OR t.frequencia_maxima > 100);
