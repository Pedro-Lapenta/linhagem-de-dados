-- Modelo de metadados do Módulo 11 (grafo G = (V, E), artefatos A11.1 a A11.10).
SET search_path TO linhagem;

CREATE TABLE responsavel (
    id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome    text NOT NULL UNIQUE,
    papel   text NOT NULL,
    equipe  text
);

CREATE TABLE ativo (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo         text NOT NULL UNIQUE,
    nome           text NOT NULL,
    tipo           text NOT NULL CHECK (tipo IN (
        'fonte', 'dataset_bruto', 'dataset_integrado', 'dataset_tratado', 'dataset_validado',
        'data_mart', 'feature', 'indicador', 'modelo', 'dashboard', 'api', 'relatorio',
        'produto_dados', 'consumidor')),
    camada         text NOT NULL CHECK (camada IN (
        'fontes', 'bruto', 'integrado', 'tratado', 'validado', 'mart', 'consumo')),
    descricao      text,
    localizacao    text,
    sensibilidade  text NOT NULL DEFAULT 'interno'
                   CHECK (sensibilidade IN ('publico', 'interno', 'restrito', 'sensivel')),
    critico        boolean NOT NULL DEFAULT false,
    status         text NOT NULL DEFAULT 'ativo' CHECK (status IN ('ativo', 'obsoleto')),
    responsavel_id integer REFERENCES responsavel (id),
    metadados      jsonb NOT NULL DEFAULT '{}',
    criado_em      timestamptz NOT NULL DEFAULT now(),
    atualizado_em  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ativo_tipo_idx ON ativo (tipo);

-- A11.1: de onde o dado veio.
CREATE TABLE proveniencia (
    ativo_id         integer PRIMARY KEY REFERENCES ativo (id) ON DELETE CASCADE,
    sistema_origem   text NOT NULL,
    instituicao      text NOT NULL,
    cidade           text,
    campus           text,
    latitude         numeric(9, 6) CHECK (latitude BETWEEN -90 AND 90),
    longitude        numeric(9, 6) CHECK (longitude BETWEEN -180 AND 180),
    periodicidade    text,
    cobertura_inicio date,
    cobertura_fim    date,
    data_extracao    date,
    condicoes_uso    text,
    demonstracao     boolean NOT NULL DEFAULT true,
    CHECK (cobertura_fim IS NULL OR cobertura_inicio IS NULL OR cobertura_fim >= cobertura_inicio)
);

CREATE TABLE atributo (
    id         integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ativo_id   integer NOT NULL REFERENCES ativo (id) ON DELETE CASCADE,
    nome       text NOT NULL,
    tipo_dado  text NOT NULL,
    critico    boolean NOT NULL DEFAULT false,
    sensivel   boolean NOT NULL DEFAULT false,
    descricao  text,
    UNIQUE (ativo_id, nome)
);

CREATE TABLE regra (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo         text NOT NULL UNIQUE,
    nome           text NOT NULL,
    tipo           text NOT NULL CHECK (tipo IN (
        'harmonizacao', 'limpeza', 'imputacao', 'derivacao', 'validacao', 'agregacao')),
    expressao      text NOT NULL,
    versao         text NOT NULL DEFAULT '1.0',
    responsavel_id integer REFERENCES responsavel (id)
);

CREATE TABLE processo (
    id                 integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo             text NOT NULL UNIQUE,
    nome               text NOT NULL,
    tipo               text NOT NULL CHECK (tipo IN (
        'ingestao', 'integracao', 'transformacao', 'validacao', 'armazenamento', 'disponibilizacao')),
    descricao          text,
    script             text NOT NULL,
    parametros_padrao  jsonb NOT NULL DEFAULT '{}',
    tabela_rejeitos    text,
    ordem              integer NOT NULL UNIQUE,
    responsavel_id     integer REFERENCES responsavel (id)
);

CREATE TABLE processo_entrada (
    processo_id integer NOT NULL REFERENCES processo (id) ON DELETE CASCADE,
    ativo_id    integer NOT NULL REFERENCES ativo (id),
    PRIMARY KEY (processo_id, ativo_id)
);
CREATE TABLE processo_saida (
    processo_id integer NOT NULL REFERENCES processo (id) ON DELETE CASCADE,
    ativo_id    integer NOT NULL REFERENCES ativo (id),
    PRIMARY KEY (processo_id, ativo_id)
);
CREATE TABLE processo_regra (
    processo_id integer NOT NULL REFERENCES processo (id) ON DELETE CASCADE,
    regra_id    integer NOT NULL REFERENCES regra (id),
    PRIMARY KEY (processo_id, regra_id)
);

-- A11.3: cada execução é um evento auditável.
CREATE TABLE execucao (
    id                integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    processo_id       integer NOT NULL REFERENCES processo (id),
    executor          text NOT NULL,
    iniciada_em       timestamptz NOT NULL DEFAULT clock_timestamp(),
    finalizada_em     timestamptz,
    status            text NOT NULL DEFAULT 'em_execucao'
                      CHECK (status IN ('em_execucao', 'sucesso', 'parcial', 'falha')),
    parametros        jsonb NOT NULL DEFAULT '{}',
    linhas_lidas      bigint,
    linhas_gravadas   bigint,
    linhas_rejeitadas bigint,
    log               text,
    evidencia         jsonb
);
CREATE INDEX execucao_processo_idx ON execucao (processo_id, iniciada_em DESC);

CREATE TABLE ativo_versao (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ativo_id    integer NOT NULL REFERENCES ativo (id) ON DELETE CASCADE,
    numero      integer NOT NULL CHECK (numero > 0),
    checksum    text NOT NULL,
    linhas      bigint NOT NULL,
    esquema     jsonb NOT NULL DEFAULT '[]',
    snapshot    jsonb,
    parametros  jsonb NOT NULL DEFAULT '{}',
    execucao_id integer REFERENCES execucao (id),
    criado_em   timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (ativo_id, numero)
);

-- Liga a execução às versões exatas que ela leu e gravou.
CREATE TABLE execucao_entrada (
    execucao_id     integer NOT NULL REFERENCES execucao (id) ON DELETE CASCADE,
    ativo_versao_id integer NOT NULL REFERENCES ativo_versao (id),
    PRIMARY KEY (execucao_id, ativo_versao_id)
);
CREATE TABLE execucao_saida (
    execucao_id     integer NOT NULL REFERENCES execucao (id) ON DELETE CASCADE,
    ativo_versao_id integer NOT NULL REFERENCES ativo_versao (id),
    PRIMARY KEY (execucao_id, ativo_versao_id)
);
CREATE INDEX execucao_entrada_versao_idx ON execucao_entrada (ativo_versao_id);
CREATE INDEX execucao_saida_versao_idx ON execucao_saida (ativo_versao_id);

-- A11.2 e A11.5: arestas do grafo, com vigência para consultar o passado.
CREATE TABLE dependencia (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    origem_id      integer NOT NULL REFERENCES ativo (id),
    destino_id     integer NOT NULL REFERENCES ativo (id),
    tipo_relacao   text NOT NULL CHECK (tipo_relacao IN (
        'originou', 'foi_extraido_de', 'foi_integrado_com', 'foi_transformado_por', 'gerou',
        'derivou_de', 'validou', 'alimentou', 'consumiu', 'substituiu', 'depende_de')),
    processo_id    integer REFERENCES processo (id),
    regra_id       integer REFERENCES regra (id),
    responsavel_id integer REFERENCES responsavel (id),
    evidencia      text,
    vigente_de     timestamptz NOT NULL DEFAULT now(),
    vigente_ate    timestamptz,
    CHECK (origem_id <> destino_id),
    CHECK (vigente_ate IS NULL OR vigente_ate > vigente_de)
);
CREATE UNIQUE INDEX dependencia_vigente_uq ON dependencia (origem_id, destino_id, tipo_relacao)
    WHERE vigente_ate IS NULL;
CREATE INDEX dependencia_origem_idx ON dependencia (origem_id);
CREATE INDEX dependencia_destino_idx ON dependencia (destino_id);

-- A11.6: linhagem em nível de atributo.
CREATE TABLE atributo_derivacao (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    origem_id   integer NOT NULL REFERENCES atributo (id) ON DELETE CASCADE,
    destino_id  integer NOT NULL REFERENCES atributo (id) ON DELETE CASCADE,
    regra_id    integer REFERENCES regra (id),
    processo_id integer REFERENCES processo (id),
    UNIQUE (origem_id, destino_id),
    CHECK (origem_id <> destino_id)
);
CREATE INDEX atributo_derivacao_destino_idx ON atributo_derivacao (destino_id);

-- A11.8: relatório de impacto salvo.
CREATE TABLE analise_impacto (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ativo_id       integer NOT NULL REFERENCES ativo (id),
    mudanca        text NOT NULL,
    tipo_impacto   text NOT NULL CHECK (tipo_impacto IN ('estrutural', 'semantico', 'qualidade', 'consumo')),
    severidade     text NOT NULL CHECK (severidade IN ('baixa', 'media', 'alta', 'critica')),
    acao           text NOT NULL,
    responsavel_id integer REFERENCES responsavel (id),
    status         text NOT NULL DEFAULT 'aberto' CHECK (status IN ('aberto', 'tratado', 'encerrado')),
    ativos         jsonb NOT NULL,
    criada_em      timestamptz NOT NULL DEFAULT now()
);

-- Alimenta as métricas TMR (tempo de reconstrução) e TCLR (consultas respondidas).
CREATE TABLE consulta_log (
    id         integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    consulta   text NOT NULL,
    parametros jsonb NOT NULL DEFAULT '{}',
    duracao_ms numeric(12, 3) NOT NULL,
    linhas     integer NOT NULL,
    respondida boolean NOT NULL,
    em         timestamptz NOT NULL DEFAULT now()
);

-- A11.9: trilha de auditoria.
CREATE TABLE auditoria (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabela      text NOT NULL,
    registro_id text,
    operacao    text NOT NULL,
    antes       jsonb,
    depois      jsonb,
    usuario     text NOT NULL,
    em          timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX auditoria_em_idx ON auditoria (em DESC);
