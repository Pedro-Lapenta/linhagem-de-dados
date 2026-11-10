-- Sistemas de origem SIMULADOS (cenário de evasão do Módulo 11). Nenhum dado é real.
-- setseed torna a geração determinística. Períodos: 1 = 2021/1 ... 8 = 2024/2.
SELECT setseed(0.42);

CREATE TEMP TABLE _curso (idx, cod_curso, curso, campus) AS VALUES
    (1, 'BCC-BAU', 'Ciência da Computação', 'Bauru'),
    (2, 'BSI-RIO', 'Sistemas de Informação', 'São José do Rio Preto'),
    (3, 'EST-PPR', 'Estatística', 'Presidente Prudente'),
    (4, 'FAR-ARA', 'Farmácia', 'Araraquara'),
    (5, 'MED-BOT', 'Medicina', 'Botucatu'),
    (6, 'ELE-ISO', 'Engenharia Elétrica', 'Ilha Solteira'),
    (7, 'PED-MAR', 'Pedagogia', 'Marília'),
    (8, 'GEO-RCL', 'Geologia', 'Rio Claro');

CREATE TEMP TABLE _aluno AS
SELECT 'RA' || lpad(n::text, 6, '0') AS ra,
       1 + floor(random() * 8)::int AS curso_idx,
       1 + floor(random() * 5)::int AS periodo_ingresso,
       random() AS risco,
       random() AS sorteio_fim,
       random() AS sorteio_cancela
FROM generate_series(1, 3000) AS n;

CREATE TEMP TABLE _trajetoria AS
SELECT a.*,
       CASE WHEN a.sorteio_fim < 0.22 + a.curso_idx * 0.025
            THEN LEAST(8, a.periodo_ingresso + floor(a.risco * 4)::int)
            ELSE 8 END AS ultimo_periodo
FROM _aluno a;

CREATE TEMP TABLE _periodo AS
SELECT t.ra, t.curso_idx, t.risco, t.ultimo_periodo, t.sorteio_cancela, p,
       2021 + (p - 1) / 2 AS ano,
       1 + (p - 1) % 2 AS semestre
FROM _trajetoria t
CROSS JOIN LATERAL generate_series(t.periodo_ingresso, t.ultimo_periodo) AS p;

CREATE TABLE fontes.matricula AS
SELECT p.ra, p.ano, p.semestre,
       c.cod_curso,
       CASE WHEN random() < 0.004 THEN NULL ELSE c.curso END AS curso,
       c.campus,
       CASE
           WHEN p.p = p.ultimo_periodo AND p.ultimo_periodo < 8 AND p.sorteio_cancela < 0.35
               THEN (ARRAY['CANCELADO', 'Cancelado'])[1 + floor(random() * 2)::int]
           WHEN random() < 0.03 THEN (ARRAY['TRANCADO', 'Trancado'])[1 + floor(random() * 2)::int]
           ELSE (ARRAY['ATIVO', 'Ativo', 'MATRICULADO'])[1 + floor(random() * 3)::int]
       END AS situacao
FROM _periodo p
JOIN _curso c ON c.idx = p.curso_idx
ORDER BY p.ra, p.ano, p.semestre;

CREATE TABLE fontes.notas AS
SELECT p.ra, p.ano, p.semestre,
       'D' || lpad((d + p.p * 10)::text, 3, '0') AS cod_disciplina,
       CASE WHEN random() < 0.002 THEN (ARRAY[11.0, -1.0])[1 + floor(random() * 2)::int]
            ELSE round(greatest(0, least(10, 8.2 - 4 * p.risco + random() * 3 - 1.5))::numeric, 1)
       END::numeric(4, 1) AS nota_final
FROM _periodo p CROSS JOIN generate_series(1, 4) AS d
ORDER BY 1, 2, 3, 4;

CREATE TABLE fontes.frequencia AS
SELECT p.ra, p.ano, p.semestre,
       'D' || lpad((d + p.p * 10)::text, 3, '0') AS cod_disciplina,
       CASE WHEN random() < 0.002 THEN 120.0
            ELSE round(greatest(0, least(100, 96 - 35 * p.risco + random() * 16 - 8))::numeric, 1)
       END::numeric(5, 1) AS percentual
FROM _periodo p CROSS JOIN generate_series(1, 4) AS d
ORDER BY 1, 2, 3, 4;

CREATE TABLE fontes.ava AS
SELECT p.ra, p.ano, p.semestre,
       floor(60 * (1 - p.risco) + random() * 30)::int AS acessos,
       floor(20 * (1 - p.risco) + random() * 8)::int AS atividades
FROM _periodo p
WHERE random() > 0.03
ORDER BY 1, 2, 3;

CREATE TABLE fontes.socioeconomico AS
SELECT t.ra,
       CASE WHEN random() < 0.04 THEN NULL
            ELSE (ARRAY['ate_1_sm', '1_a_3_sm', '3_a_5_sm', 'acima_5_sm'])[1 + floor(random() * 4)::int]
       END AS renda_faixa,
       random() < 0.55 AS escola_publica,
       random() < 0.30 AS trabalha
FROM _trajetoria t
ORDER BY 1;
