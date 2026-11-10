-- A definição de evasão é parâmetro: alterá-la gera uma nova versão dos produtos.
DROP TABLE IF EXISTS mart.permanencia;
CREATE TABLE mart.permanencia AS
WITH fim AS (
    SELECT max(periodo) AS periodo FROM validado.trajetoria_academica
),
aluno AS (
    SELECT ra,
           min(cod_curso) AS cod_curso,
           min(curso) AS curso,
           min(campus) AS campus,
           max(periodo) AS ultimo_periodo,
           (array_agg(situacao ORDER BY periodo DESC))[1] AS ultima_situacao,
           round(avg(media_notas), 2) AS media_geral,
           round(avg(frequencia_media), 2) AS frequencia_geral
    FROM validado.trajetoria_academica
    GROUP BY ra
)
SELECT a.ra, a.cod_curso, a.curso, a.campus, a.ultimo_periodo, a.ultima_situacao,
       a.media_geral, a.frequencia_geral,
       e.acessos_medios, e.proporcao_baixa_frequencia,
       (a.ultima_situacao = 'CANCELADO'
        OR fim.periodo - a.ultimo_periodo >= %(periodos_sem_matricula)s) AS evadido
FROM aluno a
CROSS JOIN fim
LEFT JOIN mart.feature_engajamento e USING (ra);
