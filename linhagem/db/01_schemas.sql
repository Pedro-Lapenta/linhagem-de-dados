-- Camadas de dados percorridas pelo pipeline e schema de metadados de linhagem.
CREATE SCHEMA fontes;     -- sistemas de origem (simulados)
CREATE SCHEMA bruto;      -- cópia fiel das fontes
CREATE SCHEMA integrado;  -- fontes harmonizadas em uma trajetória única
CREATE SCHEMA tratado;    -- limpeza, imputação e atributos derivados
CREATE SCHEMA validado;   -- dados aprovados pelas regras de qualidade
CREATE SCHEMA mart;       -- data mart, indicadores e produtos de consumo
CREATE SCHEMA linhagem;   -- metadados: proveniência, linhagem e auditoria
