export interface Responsavel { id: number; nome: string; papel: string }

export interface AtivoResumo {
  id: number; codigo: string; nome: string; tipo: string; camada: string;
  sensibilidade: string; critico: boolean; status: string; responsavel: string | null;
  versao_atual: number | null; versao_em: string | null; iaa: number | null;
  tem_proveniencia: boolean; desatualizado_por: string | null;
}

export interface Atributo {
  id: number; nome: string; tipo_dado: string; critico: boolean; sensivel: boolean; descricao: string | null;
}

export interface Proveniencia {
  sistema_origem: string; instituicao: string; cidade: string | null; campus: string | null;
  latitude: number | null; longitude: number | null; periodicidade: string | null;
  cobertura_inicio: string | null; cobertura_fim: string | null; data_extracao: string | null;
  condicoes_uso: string | null; demonstracao?: boolean;
}

export interface Versao {
  id: number; numero: number; checksum: string; linhas: number; parametros: Record<string, unknown>;
  execucao_id: number | null; criado_em: string; processo: string | null; executor: string | null;
}

export interface Vizinho {
  id: number; tipo_relacao: string; vigente_de: string; vigente_ate: string | null; evidencia: string | null;
  sentido: "entrada" | "saida"; outro_id: number; outro_codigo: string; outro_nome: string; processo: string | null;
}

export interface RegistroAuditoria {
  id: number; tabela: string; registro_id: string | null; operacao: string;
  antes: Record<string, unknown> | null; depois: Record<string, unknown> | null; usuario: string; em: string;
}

export interface Auditabilidade {
  iaa: number; tem_origem: boolean; tem_versoes: boolean; tem_processos: boolean; tem_regras: boolean;
  tem_responsavel: boolean; tem_evidencias: boolean; tem_derivados: boolean;
}

export interface AtivoDetalhe {
  id: number; codigo: string; nome: string; tipo: string; camada: string; descricao: string | null;
  localizacao: string | null; sensibilidade: string; critico: boolean; status: string;
  responsavel_id: number | null; responsavel: string | null; proveniencia: Proveniencia | null;
  atributos: Atributo[]; versoes: Versao[]; auditabilidade: Auditabilidade | null;
  vizinhos: Vizinho[]; historico: RegistroAuditoria[];
}

export interface NoGrafo {
  chave: string; id: number; codigo: string; nome: string; classe: "ativo" | "processo" | "regra" | "atributo";
  tipo: string; camada?: string; critico?: boolean; status?: string; desatualizado?: boolean; expressao?: string;
}

export interface ArestaGrafo {
  origem: string; destino: string; tipo_relacao: string; processo_id: number | null;
  evidencia: string | null; vigente_de?: string; vigente_ate?: string | null;
}

export interface Grafo { nos: NoGrafo[]; arestas: ArestaGrafo[]; foco?: string }

export interface Metrica {
  sigla: string; nome: string; descricao: string; numerador: number | null;
  denominador: number | null; valor: number | null; unidade: "proporcao" | "etapas" | "ms";
}

export interface Criterio { numero: number; criterio: string; atendidos: number; total: number; atendido: boolean }

export interface LinhaPainel {
  cod_curso: string; curso: string; campus: string; alunos: number; evadidos: number;
  taxa_evasao: number; faixa_risco: "alta" | "media" | "baixa";
}

export interface Painel {
  ativo: { id: number; codigo: string; nome: string };
  versao: { id: number; numero: number; criado_em: string; executor: string | null } | null;
  definicao: Record<string, number> | null;
  linhas: LinhaPainel[];
}

export interface Processo {
  id: number; codigo: string; nome: string; tipo: string; descricao: string | null; script: string;
  parametros_padrao: Record<string, number>; ordem: number; entradas: string[] | null; saidas: string[] | null;
  ultimo_status: string | null; ultima_execucao: string | null; responsavel: string | null;
}

export interface Execucao {
  id: number; processo: string; processo_nome: string; processo_tipo: string; executor: string;
  iniciada_em: string; finalizada_em: string | null; status: string; parametros: Record<string, unknown>;
  linhas_lidas: number | null; linhas_gravadas: number | null; linhas_rejeitadas: number | null;
  log: string | null; evidencia: Record<string, unknown> | null; duracao_ms: number | null;
}

export interface VersaoLigada {
  versao_id: number; ativo_id: number; codigo: string; nome: string; numero: number; linhas: number; checksum: string;
}

export interface ExecucaoDetalhe extends Execucao { entradas: VersaoLigada[]; saidas: VersaoLigada[] }

export interface Desatualizado { ativo_id: number; codigo: string; nome: string; tipo: string; causa: string }

export interface ParametroConsulta {
  nome: string; tipo: "ativo" | "atributo" | "versao" | "inteiro" | "data" | "booleano";
  rotulo: string; padrao?: number | boolean;
}

export interface DefinicaoConsulta { id: string; titulo: string; pergunta: string; parametros: ParametroConsulta[] }

export type Linha = Record<string, unknown>;

export interface ResultadoConsulta { colunas: string[]; linhas: Linha[]; sql: string; duracao_ms: number }

export interface AtributoRotulado extends Atributo { ativo_id: number; ativo_codigo: string; rotulo: string }

export interface VersaoRotulada { id: number; rotulo: string; codigo: string; numero: number }

export interface AnaliseImpacto {
  id: number; codigo: string; nome: string; mudanca: string; tipo_impacto: string; severidade: string;
  acao: string; status: string; ativos: { codigo: string; severidade: string }[]; criada_em: string;
  responsavel: string | null;
}

export interface Comparacao {
  a: { numero: number; checksum: string; linhas: number; parametros: Record<string, unknown>; criado_em: string };
  b: { numero: number; checksum: string; linhas: number; parametros: Record<string, unknown>; criado_em: string };
  comparavel: boolean;
  diferencas: { chave: string; coluna: string; a: unknown; b: unknown }[];
}

export interface FonteMapa {
  id: number; codigo: string; nome: string; status: string; sensibilidade: string; sistema_origem: string;
  instituicao: string; cidade: string | null; campus: string | null; latitude: number; longitude: number;
  periodicidade: string | null; data_extracao: string | null; demonstracao: boolean;
  dependentes: { id: number; codigo: string; nome: string; tipo: string }[];
}
