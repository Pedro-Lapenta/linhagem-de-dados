-- Uma linha por aluno e período, combinando as cinco bases.
DROP TABLE IF EXISTS integrado.trajetoria;
CREATE TABLE integrado.trajetoria AS
WITH notas AS (
    SELECT ra, ano, semestre,
           round(avg(nota_final), 2) AS media_notas,
           min(nota_final) AS nota_minima,
           max(nota_final) AS nota_maxima
    FROM bruto.notas
    GROUP BY ra, ano, semestre
),
frequencia AS (
    SELECT ra, ano, semestre,
           round(avg(percentual), 2) AS frequencia_media,
           max(percentual) AS frequencia_maxima
    FROM bruto.frequencia
    GROUP BY ra, ano, semestre
)
SELECT m.ra,
       (m.ano - 2021) * 2 + m.semestre AS periodo,
       m.ano, m.semestre, m.cod_curso, m.curso, m.campus,
       CASE upper(m.situacao) WHEN 'MATRICULADO' THEN 'ATIVO' ELSE upper(m.situacao) END AS situacao,
       n.media_notas, n.nota_minima, n.nota_maxima,
       f.frequencia_media, f.frequencia_maxima,
       a.acessos, a.atividades,
       s.renda_faixa, s.escola_publica, s.trabalha
FROM bruto.matricula m
LEFT JOIN notas n USING (ra, ano, semestre)
LEFT JOIN frequencia f USING (ra, ano, semestre)
LEFT JOIN bruto.ava a USING (ra, ano, semestre)
LEFT JOIN bruto.socioeconomico s USING (ra);
