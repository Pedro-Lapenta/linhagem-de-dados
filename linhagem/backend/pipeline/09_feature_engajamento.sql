DROP TABLE IF EXISTS mart.feature_engajamento;
CREATE TABLE mart.feature_engajamento AS
SELECT ra,
       round(avg(acessos), 2) AS acessos_medios,
       round(avg(atividades), 2) AS atividades_medias,
       round(avg(baixa_frequencia::int), 4) AS proporcao_baixa_frequencia
FROM validado.trajetoria_academica
GROUP BY ra;
