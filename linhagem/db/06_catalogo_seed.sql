-- Catálogo inicial: responsáveis, ativos, proveniência, regras, processos, arestas e atributos.
-- Localizações e responsáveis são fictícios (dados de demonstração).
SET search_path TO linhagem;
SET app.usuario TO 'carga-inicial';

INSERT INTO responsavel (nome, papel, equipe) VALUES
    ('Secretaria Acadêmica', 'Curadoria da fonte', 'Graduação'),
    ('Equipe de Engenharia de Dados', 'Pipeline', 'Dados'),
    ('Núcleo de Qualidade', 'Validação', 'Dados'),
    ('Observatório de Permanência', 'Produto analítico', 'Pró-Reitoria');

CREATE FUNCTION pg_temp.resp(p text) RETURNS integer LANGUAGE sql AS
$$ SELECT id FROM linhagem.responsavel WHERE nome = p $$;
CREATE FUNCTION pg_temp.a(p text) RETURNS integer LANGUAGE sql AS
$$ SELECT id FROM linhagem.ativo WHERE codigo = p $$;
CREATE FUNCTION pg_temp.p(p text) RETURNS integer LANGUAGE sql AS
$$ SELECT id FROM linhagem.processo WHERE codigo = p $$;
CREATE FUNCTION pg_temp.r(p text) RETURNS integer LANGUAGE sql AS
$$ SELECT id FROM linhagem.regra WHERE codigo = p $$;
CREATE FUNCTION pg_temp.c(p_ativo text, p_nome text) RETURNS integer LANGUAGE sql AS
$$ SELECT at.id FROM linhagem.atributo at JOIN linhagem.ativo a ON a.id = at.ativo_id
   WHERE a.codigo = p_ativo AND at.nome = p_nome $$;

INSERT INTO ativo (codigo, nome, tipo, camada, descricao, localizacao, sensibilidade, critico, status, responsavel_id)
SELECT v.codigo, v.nome, v.tipo, v.camada, v.descricao, v.loc, v.sens, v.critico, v.status, pg_temp.resp(v.resp)
FROM (VALUES
    ('F-MAT', 'Sistema Acadêmico: Matrículas', 'fonte', 'fontes', 'Matrículas por aluno e período letivo.', 'fontes.matricula', 'sensivel', true, 'ativo', 'Secretaria Acadêmica'),
    ('F-NOT', 'Sistema Acadêmico: Notas', 'fonte', 'fontes', 'Nota final por disciplina.', 'fontes.notas', 'sensivel', true, 'ativo', 'Secretaria Acadêmica'),
    ('F-FRE', 'Diário de Classe: Frequência', 'fonte', 'fontes', 'Percentual de presença por disciplina.', 'fontes.frequencia', 'sensivel', true, 'ativo', 'Secretaria Acadêmica'),
    ('F-AVA', 'Ambiente Virtual de Aprendizagem', 'fonte', 'fontes', 'Acessos e atividades por período.', 'fontes.ava', 'restrito', true, 'ativo', 'Equipe de Engenharia de Dados'),
    ('F-SOC', 'Questionário Socioeconômico', 'fonte', 'fontes', 'Perfil socioeconômico declarado no ingresso.', 'fontes.socioeconomico', 'sensivel', true, 'ativo', 'Observatório de Permanência'),
    ('F-SOC-LEG', 'Questionário Socioeconômico (legado)', 'fonte', 'fontes', 'Formulário substituído em 2025. Mantido para consulta histórica.', 'arquivo morto', 'sensivel', false, 'obsoleto', 'Observatório de Permanência'),
    ('F-BOL', 'Planilha manual de bolsas', 'fonte', 'fontes', 'Planilha sem curadoria nem proveniência. Lacuna proposital de demonstração.', 'compartilhamento de rede', 'restrito', false, 'ativo', NULL),
    ('B-MAT', 'Bruto: Matrículas', 'dataset_bruto', 'bruto', 'Cópia fiel da fonte.', 'bruto.matricula', 'sensivel', true, 'ativo', 'Equipe de Engenharia de Dados'),
    ('B-NOT', 'Bruto: Notas', 'dataset_bruto', 'bruto', 'Cópia fiel da fonte.', 'bruto.notas', 'sensivel', true, 'ativo', 'Equipe de Engenharia de Dados'),
    ('B-FRE', 'Bruto: Frequência', 'dataset_bruto', 'bruto', 'Cópia fiel da fonte.', 'bruto.frequencia', 'sensivel', true, 'ativo', 'Equipe de Engenharia de Dados'),
    ('B-AVA', 'Bruto: AVA', 'dataset_bruto', 'bruto', 'Cópia fiel da fonte.', 'bruto.ava', 'restrito', true, 'ativo', 'Equipe de Engenharia de Dados'),
    ('B-SOC', 'Bruto: Socioeconômico', 'dataset_bruto', 'bruto', 'Cópia fiel da fonte.', 'bruto.socioeconomico', 'sensivel', true, 'ativo', 'Equipe de Engenharia de Dados'),
    ('I-TRAJ', 'Trajetória integrada', 'dataset_integrado', 'integrado', 'Uma linha por aluno e período, com as cinco fontes harmonizadas.', 'integrado.trajetoria', 'sensivel', true, 'ativo', 'Equipe de Engenharia de Dados'),
    ('T-TRAJ', 'Trajetória acadêmica tratada', 'dataset_tratado', 'tratado', 'Sem inconsistências, com imputação e atributos derivados.', 'tratado.trajetoria_academica', 'sensivel', true, 'ativo', 'Equipe de Engenharia de Dados'),
    ('V-TRAJ', 'Trajetória acadêmica validada', 'dataset_validado', 'validado', 'Dados aprovados pelas regras de qualidade.', 'validado.trajetoria_academica', 'sensivel', true, 'ativo', 'Núcleo de Qualidade'),
    ('R-QUAL', 'Relatório de qualidade', 'relatorio', 'validado', 'Resultado de cada regra de validação.', 'validado.relatorio_qualidade', 'interno', false, 'ativo', 'Núcleo de Qualidade'),
    ('FE-ENG', 'Feature de engajamento', 'feature', 'mart', 'Engajamento no AVA e frequência por aluno.', 'mart.feature_engajamento', 'restrito', false, 'ativo', 'Equipe de Engenharia de Dados'),
    ('M-PERM', 'Data mart de permanência', 'data_mart', 'mart', 'Situação final de cada aluno.', 'mart.permanencia', 'sensivel', true, 'ativo', 'Observatório de Permanência'),
    ('IN-EVA', 'Indicador de taxa de evasão', 'indicador', 'mart', 'Taxa de evasão por curso.', 'mart.indicador_taxa_evasao', 'interno', true, 'ativo', 'Observatório de Permanência'),
    ('D-EVA', 'Painel de evasão', 'dashboard', 'consumo', 'Painel com evasão e faixa de risco por curso.', 'mart.painel_evasao', 'interno', true, 'ativo', 'Observatório de Permanência'),
    ('R-CAM', 'Relatório de evasão por câmpus', 'relatorio', 'consumo', 'Consolidado por câmpus.', 'mart.relatorio_evasao_campus', 'interno', false, 'ativo', 'Observatório de Permanência'),
    ('A-EVA', 'API de evasão', 'api', 'consumo', 'Dados publicados para outros sistemas.', 'mart.api_evasao', 'interno', false, 'ativo', 'Equipe de Engenharia de Dados'),
    ('D-LEG', 'Painel legado de retenção', 'dashboard', 'consumo', 'Painel sem linhagem registrada. Lacuna proposital de demonstração.', 'servidor legado', 'interno', false, 'ativo', NULL),
    ('C-PRO', 'Pró-Reitoria de Graduação', 'consumidor', 'consumo', 'Usa o painel nas decisões de permanência.', NULL, 'interno', false, 'ativo', NULL),
    ('C-COO', 'Coordenações de curso', 'consumidor', 'consumo', 'Recebem o relatório semestral.', NULL, 'interno', false, 'ativo', NULL),
    ('C-APP', 'Portal do estudante', 'consumidor', 'consumo', 'Consome a API de evasão.', NULL, 'interno', false, 'ativo', NULL)
) AS v (codigo, nome, tipo, camada, descricao, loc, sens, critico, status, resp);

INSERT INTO proveniencia (ativo_id, sistema_origem, instituicao, cidade, campus, latitude, longitude,
                          periodicidade, cobertura_inicio, cobertura_fim, data_extracao, condicoes_uso)
SELECT pg_temp.a(v.cod), v.sistema, 'Universidade simulada (demonstração)', v.cidade, v.campus, v.lat, v.lon,
       v.per, DATE '2021-01-01', v.fim, DATE '2025-01-15', 'Uso acadêmico; dados simulados'
FROM (VALUES
    ('F-MAT', 'Sistema Acadêmico', 'São Paulo', 'Reitoria', -23.5505, -46.6333, 'Semestral', DATE '2024-12-31'),
    ('F-NOT', 'Sistema Acadêmico', 'Bauru', 'Bauru', -22.3246, -49.0871, 'Semestral', DATE '2024-12-31'),
    ('F-FRE', 'Diário de Classe', 'Rio Claro', 'Rio Claro', -22.4149, -47.5651, 'Semestral', DATE '2024-12-31'),
    ('F-AVA', 'Moodle institucional', 'Presidente Prudente', 'Presidente Prudente', -22.1207, -51.3925, 'Contínua', DATE '2024-12-31'),
    ('F-SOC', 'Formulário de ingresso', 'Araraquara', 'Araraquara', -21.7845, -48.1780, 'Anual', DATE '2024-12-31'),
    ('F-SOC-LEG', 'Formulário em papel digitalizado', 'Araraquara', 'Araraquara', -21.7945, -48.1680, 'Anual', DATE '2024-01-31')
) AS v (cod, sistema, cidade, campus, lat, lon, per, fim);

INSERT INTO regra (codigo, nome, tipo, expressao, versao, responsavel_id)
SELECT v.cod, v.nome, v.tipo, v.expr, v.ver, pg_temp.resp(v.resp) FROM (VALUES
    ('R-HARM-SIT', 'Harmonizar situação', 'harmonizacao', 'upper(situacao); MATRICULADO vira ATIVO', '1.0', 'Equipe de Engenharia de Dados'),
    ('R-CHAVE', 'Chave de integração', 'harmonizacao', 'Junção por (ra, ano, semestre)', '1.0', 'Equipe de Engenharia de Dados'),
    ('R-REJ', 'Rejeitar inconsistentes', 'limpeza', 'curso nulo, nota fora de 0..10 ou frequência acima de 100', '1.0', 'Equipe de Engenharia de Dados'),
    ('R-IMP', 'Imputar ausentes', 'imputacao', 'renda nula vira nao_informada; acessos nulos viram 0', '1.0', 'Equipe de Engenharia de Dados'),
    ('R-BFREQ', 'Baixa frequência', 'derivacao', 'frequencia_media < limite_frequencia', '1.0', 'Equipe de Engenharia de Dados'),
    ('R-COMPL', 'Completude de renda', 'validacao', 'renda informada / total >= min_completude', '1.0', 'Núcleo de Qualidade'),
    ('R-ENG', 'Engajamento', 'derivacao', 'média de acessos e atividades; proporção de períodos em baixa frequência', '1.0', 'Equipe de Engenharia de Dados'),
    ('R-EVASAO', 'Definição de evasão', 'derivacao', 'CANCELADO no último período ou períodos sem matrícula >= periodos_sem_matricula', '1.0', 'Observatório de Permanência'),
    ('R-TAXA', 'Taxa de evasão', 'agregacao', 'evadidos / alunos, por curso', '1.0', 'Observatório de Permanência'),
    ('R-FAIXA', 'Faixa de risco', 'derivacao', 'alta >= 0,35; média >= 0,25; caso contrário baixa', '1.0', 'Observatório de Permanência')
) AS v (cod, nome, tipo, expr, ver, resp);

INSERT INTO processo (codigo, nome, tipo, descricao, script, parametros_padrao, tabela_rejeitos, ordem, responsavel_id)
SELECT v.cod, v.nome, v.tipo, v.descr, v.script, v.params::jsonb, v.rej, v.ordem, pg_temp.resp(v.resp) FROM (VALUES
    ('ING-MAT', 'Ingestão de matrículas', 'ingestao', 'Copia a fonte para a zona bruta.', '01_ingestao_matricula.sql', '{}', NULL, 1, 'Equipe de Engenharia de Dados'),
    ('ING-NOT', 'Ingestão de notas', 'ingestao', 'Copia a fonte para a zona bruta.', '02_ingestao_notas.sql', '{}', NULL, 2, 'Equipe de Engenharia de Dados'),
    ('ING-FRE', 'Ingestão de frequência', 'ingestao', 'Copia a fonte para a zona bruta.', '03_ingestao_frequencia.sql', '{}', NULL, 3, 'Equipe de Engenharia de Dados'),
    ('ING-AVA', 'Ingestão do AVA', 'ingestao', 'Copia a fonte para a zona bruta.', '04_ingestao_ava.sql', '{}', NULL, 4, 'Equipe de Engenharia de Dados'),
    ('ING-SOC', 'Ingestão socioeconômica', 'ingestao', 'Copia a fonte para a zona bruta.', '05_ingestao_socioeconomico.sql', '{}', NULL, 5, 'Equipe de Engenharia de Dados'),
    ('INT-TRAJ', 'Integração da trajetória', 'integracao', 'Combina as cinco bases por aluno e período.', '06_integracao.sql', '{}', NULL, 6, 'Equipe de Engenharia de Dados'),
    ('TRT-TRAJ', 'Tratamento da trajetória', 'transformacao', 'Rejeita inconsistentes, imputa e deriva atributos.', '07_tratamento.sql', '{"limite_frequencia": 75}', 'tratado.trajetoria_rejeitados', 7, 'Equipe de Engenharia de Dados'),
    ('VAL-TRAJ', 'Validação de qualidade', 'validacao', 'Falha se a completude ficar abaixo do mínimo.', '08_validacao.sql', '{"min_completude": 0.9}', NULL, 8, 'Núcleo de Qualidade'),
    ('FEA-ENG', 'Cálculo da feature de engajamento', 'transformacao', 'Agrega o engajamento por aluno.', '09_feature_engajamento.sql', '{}', NULL, 9, 'Equipe de Engenharia de Dados'),
    ('MRT-PERM', 'Construção do data mart', 'armazenamento', 'Aplica a definição de evasão.', '10_data_mart.sql', '{"periodos_sem_matricula": 2}', NULL, 10, 'Observatório de Permanência'),
    ('IND-EVA', 'Cálculo do indicador', 'transformacao', 'Calcula a taxa de evasão por curso.', '11_indicador.sql', '{}', NULL, 11, 'Observatório de Permanência'),
    ('PUB-PAI', 'Publicação do painel', 'disponibilizacao', 'Publica o painel com a faixa de risco.', '12_painel.sql', '{}', NULL, 12, 'Observatório de Permanência'),
    ('PUB-REL', 'Publicação do relatório', 'disponibilizacao', 'Consolida a evasão por câmpus.', '13_relatorio.sql', '{}', NULL, 13, 'Observatório de Permanência'),
    ('PUB-API', 'Publicação da API', 'disponibilizacao', 'Prepara os dados expostos pela API.', '14_api.sql', '{}', NULL, 14, 'Equipe de Engenharia de Dados')
) AS v (cod, nome, tipo, descr, script, params, rej, ordem, resp);

INSERT INTO processo_entrada (processo_id, ativo_id)
SELECT pg_temp.p(v.p), pg_temp.a(v.a) FROM (VALUES
    ('ING-MAT', 'F-MAT'), ('ING-NOT', 'F-NOT'), ('ING-FRE', 'F-FRE'), ('ING-AVA', 'F-AVA'), ('ING-SOC', 'F-SOC'),
    ('INT-TRAJ', 'B-MAT'), ('INT-TRAJ', 'B-NOT'), ('INT-TRAJ', 'B-FRE'), ('INT-TRAJ', 'B-AVA'), ('INT-TRAJ', 'B-SOC'),
    ('TRT-TRAJ', 'I-TRAJ'), ('VAL-TRAJ', 'T-TRAJ'), ('FEA-ENG', 'V-TRAJ'),
    ('MRT-PERM', 'V-TRAJ'), ('MRT-PERM', 'FE-ENG'), ('IND-EVA', 'M-PERM'),
    ('PUB-PAI', 'IN-EVA'), ('PUB-REL', 'IN-EVA'), ('PUB-API', 'IN-EVA')
) AS v (p, a);

INSERT INTO processo_saida (processo_id, ativo_id)
SELECT pg_temp.p(v.p), pg_temp.a(v.a) FROM (VALUES
    ('ING-MAT', 'B-MAT'), ('ING-NOT', 'B-NOT'), ('ING-FRE', 'B-FRE'), ('ING-AVA', 'B-AVA'), ('ING-SOC', 'B-SOC'),
    ('INT-TRAJ', 'I-TRAJ'), ('TRT-TRAJ', 'T-TRAJ'), ('VAL-TRAJ', 'V-TRAJ'), ('VAL-TRAJ', 'R-QUAL'),
    ('FEA-ENG', 'FE-ENG'), ('MRT-PERM', 'M-PERM'), ('IND-EVA', 'IN-EVA'),
    ('PUB-PAI', 'D-EVA'), ('PUB-REL', 'R-CAM'), ('PUB-API', 'A-EVA')
) AS v (p, a);

INSERT INTO processo_regra (processo_id, regra_id)
SELECT pg_temp.p(v.p), pg_temp.r(v.r) FROM (VALUES
    ('INT-TRAJ', 'R-HARM-SIT'), ('INT-TRAJ', 'R-CHAVE'), ('TRT-TRAJ', 'R-REJ'), ('TRT-TRAJ', 'R-IMP'),
    ('TRT-TRAJ', 'R-BFREQ'), ('VAL-TRAJ', 'R-COMPL'), ('FEA-ENG', 'R-ENG'), ('MRT-PERM', 'R-EVASAO'),
    ('IND-EVA', 'R-TAXA'), ('PUB-PAI', 'R-FAIXA'), ('PUB-REL', 'R-TAXA'), ('PUB-API', 'R-FAIXA')
) AS v (p, r);

-- Arestas vigentes.
INSERT INTO dependencia (origem_id, destino_id, tipo_relacao, processo_id, regra_id, responsavel_id, evidencia, vigente_de)
SELECT pg_temp.a(v.o), pg_temp.a(v.d), v.t, pg_temp.p(v.p), pg_temp.r(v.r),
       pg_temp.resp('Equipe de Engenharia de Dados'),
       CASE WHEN v.p IS NOT NULL THEN 'manifesto da execução de ' || v.p END,
       TIMESTAMPTZ '2025-02-01 00:00:00-03'
FROM (VALUES
    ('F-MAT', 'B-MAT', 'foi_extraido_de', 'ING-MAT', NULL),
    ('F-NOT', 'B-NOT', 'foi_extraido_de', 'ING-NOT', NULL),
    ('F-FRE', 'B-FRE', 'foi_extraido_de', 'ING-FRE', NULL),
    ('F-AVA', 'B-AVA', 'foi_extraido_de', 'ING-AVA', NULL),
    ('F-SOC', 'B-SOC', 'foi_extraido_de', 'ING-SOC', NULL),
    ('B-MAT', 'I-TRAJ', 'foi_integrado_com', 'INT-TRAJ', 'R-CHAVE'),
    ('B-NOT', 'I-TRAJ', 'foi_integrado_com', 'INT-TRAJ', 'R-CHAVE'),
    ('B-FRE', 'I-TRAJ', 'foi_integrado_com', 'INT-TRAJ', 'R-CHAVE'),
    ('B-AVA', 'I-TRAJ', 'foi_integrado_com', 'INT-TRAJ', 'R-CHAVE'),
    ('B-SOC', 'I-TRAJ', 'foi_integrado_com', 'INT-TRAJ', 'R-CHAVE'),
    ('I-TRAJ', 'T-TRAJ', 'foi_transformado_por', 'TRT-TRAJ', 'R-REJ'),
    ('T-TRAJ', 'V-TRAJ', 'validou', 'VAL-TRAJ', 'R-COMPL'),
    ('T-TRAJ', 'R-QUAL', 'gerou', 'VAL-TRAJ', 'R-COMPL'),
    ('V-TRAJ', 'FE-ENG', 'derivou_de', 'FEA-ENG', 'R-ENG'),
    ('V-TRAJ', 'M-PERM', 'alimentou', 'MRT-PERM', 'R-EVASAO'),
    ('FE-ENG', 'M-PERM', 'alimentou', 'MRT-PERM', NULL),
    ('M-PERM', 'IN-EVA', 'gerou', 'IND-EVA', 'R-TAXA'),
    ('IN-EVA', 'D-EVA', 'alimentou', 'PUB-PAI', 'R-FAIXA'),
    ('IN-EVA', 'R-CAM', 'alimentou', 'PUB-REL', 'R-TAXA'),
    ('IN-EVA', 'A-EVA', 'alimentou', 'PUB-API', 'R-FAIXA'),
    ('D-EVA', 'C-PRO', 'consumiu', NULL, NULL),
    ('R-CAM', 'C-COO', 'consumiu', NULL, NULL),
    ('A-EVA', 'C-APP', 'consumiu', NULL, NULL)
) AS v (o, d, t, p, r);

-- Arestas encerradas: permitem ver como o grafo estava antes da troca do questionário.
INSERT INTO dependencia (origem_id, destino_id, tipo_relacao, evidencia, vigente_de, vigente_ate)
VALUES
    (pg_temp.a('F-SOC-LEG'), pg_temp.a('B-SOC'), 'foi_extraido_de', 'carga histórica',
     TIMESTAMPTZ '2024-02-01 00:00:00-03', TIMESTAMPTZ '2025-02-01 00:00:00-03'),
    (pg_temp.a('F-SOC-LEG'), pg_temp.a('F-SOC'), 'substituiu', 'ata de substituição do formulário',
     TIMESTAMPTZ '2024-02-01 00:00:00-03', TIMESTAMPTZ '2025-02-01 00:00:00-03');

INSERT INTO atributo (ativo_id, nome, tipo_dado, critico, sensivel, descricao)
SELECT pg_temp.a(v.a), v.nome, v.tipo, v.crit, v.sens, v.descr FROM (VALUES
    ('F-MAT', 'ra', 'text', false, true, 'Registro acadêmico'),
    ('F-MAT', 'situacao', 'text', true, false, 'Situação no período, sem padronização'),
    ('F-MAT', 'ano', 'integer', true, false, 'Ano letivo'),
    ('F-MAT', 'semestre', 'integer', true, false, 'Semestre letivo'),
    ('F-NOT', 'nota_final', 'numeric', true, false, 'Nota na disciplina'),
    ('F-FRE', 'percentual', 'numeric', true, false, 'Presença na disciplina'),
    ('F-AVA', 'acessos', 'integer', false, false, 'Acessos no período'),
    ('F-SOC', 'renda_faixa', 'text', true, true, 'Faixa de renda declarada'),
    ('B-MAT', 'situacao', 'text', true, false, 'Cópia da fonte'),
    ('B-MAT', 'ano', 'integer', true, false, 'Cópia da fonte'),
    ('B-MAT', 'semestre', 'integer', true, false, 'Cópia da fonte'),
    ('B-NOT', 'nota_final', 'numeric', true, false, 'Cópia da fonte'),
    ('B-FRE', 'percentual', 'numeric', true, false, 'Cópia da fonte'),
    ('B-AVA', 'acessos', 'integer', false, false, 'Cópia da fonte'),
    ('B-SOC', 'renda_faixa', 'text', true, true, 'Cópia da fonte'),
    ('I-TRAJ', 'situacao', 'text', true, false, 'Situação harmonizada'),
    ('I-TRAJ', 'periodo', 'integer', true, false, 'Índice do período letivo'),
    ('I-TRAJ', 'media_notas', 'numeric', true, false, 'Média das disciplinas no período'),
    ('I-TRAJ', 'frequencia_media', 'numeric', true, false, 'Frequência média no período'),
    ('I-TRAJ', 'renda_faixa', 'text', true, true, 'Renda sem imputação'),
    ('T-TRAJ', 'situacao', 'text', true, false, 'Situação tratada'),
    ('T-TRAJ', 'periodo', 'integer', true, false, 'Índice do período letivo'),
    ('T-TRAJ', 'media_notas', 'numeric', true, false, 'Média tratada'),
    ('T-TRAJ', 'baixa_frequencia', 'boolean', true, false, 'Derivado da frequência média'),
    ('T-TRAJ', 'renda_faixa', 'text', true, true, 'Renda imputada'),
    ('V-TRAJ', 'situacao', 'text', true, false, 'Situação validada'),
    ('V-TRAJ', 'periodo', 'integer', true, false, 'Índice do período letivo'),
    ('V-TRAJ', 'media_notas', 'numeric', true, false, 'Média validada'),
    ('V-TRAJ', 'baixa_frequencia', 'boolean', true, false, 'Baixa frequência validada'),
    ('M-PERM', 'ultimo_periodo', 'integer', true, false, 'Último período com matrícula'),
    ('M-PERM', 'evadido', 'boolean', true, false, 'Resultado da definição de evasão'),
    ('M-PERM', 'media_geral', 'numeric', false, false, 'Média no curso'),
    ('IN-EVA', 'alunos', 'bigint', true, false, 'Alunos no curso'),
    ('IN-EVA', 'evadidos', 'bigint', true, false, 'Alunos evadidos'),
    ('IN-EVA', 'taxa_evasao', 'numeric', true, false, 'Evadidos sobre alunos'),
    ('D-EVA', 'taxa_evasao', 'numeric', true, false, 'Valor exibido no painel'),
    ('D-EVA', 'faixa_risco', 'text', true, false, 'Classificação exibida no painel')
) AS v (a, nome, tipo, crit, sens, descr);

INSERT INTO atributo_derivacao (origem_id, destino_id, regra_id, processo_id)
SELECT pg_temp.c(v.oa, v.oc), pg_temp.c(v.da, v.dc), pg_temp.r(v.r), pg_temp.p(v.p) FROM (VALUES
    ('F-MAT', 'situacao', 'B-MAT', 'situacao', NULL, 'ING-MAT'),
    ('F-MAT', 'ano', 'B-MAT', 'ano', NULL, 'ING-MAT'),
    ('F-MAT', 'semestre', 'B-MAT', 'semestre', NULL, 'ING-MAT'),
    ('F-NOT', 'nota_final', 'B-NOT', 'nota_final', NULL, 'ING-NOT'),
    ('F-FRE', 'percentual', 'B-FRE', 'percentual', NULL, 'ING-FRE'),
    ('F-AVA', 'acessos', 'B-AVA', 'acessos', NULL, 'ING-AVA'),
    ('F-SOC', 'renda_faixa', 'B-SOC', 'renda_faixa', NULL, 'ING-SOC'),
    ('B-MAT', 'situacao', 'I-TRAJ', 'situacao', 'R-HARM-SIT', 'INT-TRAJ'),
    ('B-MAT', 'ano', 'I-TRAJ', 'periodo', 'R-CHAVE', 'INT-TRAJ'),
    ('B-MAT', 'semestre', 'I-TRAJ', 'periodo', 'R-CHAVE', 'INT-TRAJ'),
    ('B-NOT', 'nota_final', 'I-TRAJ', 'media_notas', 'R-CHAVE', 'INT-TRAJ'),
    ('B-FRE', 'percentual', 'I-TRAJ', 'frequencia_media', 'R-CHAVE', 'INT-TRAJ'),
    ('B-SOC', 'renda_faixa', 'I-TRAJ', 'renda_faixa', 'R-CHAVE', 'INT-TRAJ'),
    ('I-TRAJ', 'situacao', 'T-TRAJ', 'situacao', 'R-REJ', 'TRT-TRAJ'),
    ('I-TRAJ', 'periodo', 'T-TRAJ', 'periodo', 'R-REJ', 'TRT-TRAJ'),
    ('I-TRAJ', 'media_notas', 'T-TRAJ', 'media_notas', 'R-REJ', 'TRT-TRAJ'),
    ('I-TRAJ', 'frequencia_media', 'T-TRAJ', 'baixa_frequencia', 'R-BFREQ', 'TRT-TRAJ'),
    ('I-TRAJ', 'renda_faixa', 'T-TRAJ', 'renda_faixa', 'R-IMP', 'TRT-TRAJ'),
    ('T-TRAJ', 'situacao', 'V-TRAJ', 'situacao', 'R-COMPL', 'VAL-TRAJ'),
    ('T-TRAJ', 'periodo', 'V-TRAJ', 'periodo', 'R-COMPL', 'VAL-TRAJ'),
    ('T-TRAJ', 'media_notas', 'V-TRAJ', 'media_notas', 'R-COMPL', 'VAL-TRAJ'),
    ('T-TRAJ', 'baixa_frequencia', 'V-TRAJ', 'baixa_frequencia', 'R-COMPL', 'VAL-TRAJ'),
    ('V-TRAJ', 'periodo', 'M-PERM', 'ultimo_periodo', 'R-EVASAO', 'MRT-PERM'),
    ('V-TRAJ', 'situacao', 'M-PERM', 'evadido', 'R-EVASAO', 'MRT-PERM'),
    ('V-TRAJ', 'media_notas', 'M-PERM', 'media_geral', 'R-EVASAO', 'MRT-PERM'),
    ('M-PERM', 'ultimo_periodo', 'M-PERM', 'evadido', 'R-EVASAO', 'MRT-PERM'),
    ('M-PERM', 'evadido', 'IN-EVA', 'evadidos', 'R-TAXA', 'IND-EVA'),
    ('M-PERM', 'evadido', 'IN-EVA', 'alunos', 'R-TAXA', 'IND-EVA'),
    ('IN-EVA', 'evadidos', 'IN-EVA', 'taxa_evasao', 'R-TAXA', 'IND-EVA'),
    ('IN-EVA', 'alunos', 'IN-EVA', 'taxa_evasao', 'R-TAXA', 'IND-EVA'),
    ('IN-EVA', 'taxa_evasao', 'D-EVA', 'taxa_evasao', 'R-FAIXA', 'PUB-PAI'),
    ('IN-EVA', 'taxa_evasao', 'D-EVA', 'faixa_risco', 'R-FAIXA', 'PUB-PAI')
) AS v (oa, oc, da, dc, r, p);
