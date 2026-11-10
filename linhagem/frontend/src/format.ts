export const TIPOS: Record<string, string> = {
  fonte: "Fonte", dataset_bruto: "Dataset bruto", dataset_integrado: "Dataset integrado",
  dataset_tratado: "Dataset tratado", dataset_validado: "Dataset validado", data_mart: "Data mart",
  feature: "Feature", indicador: "Indicador", modelo: "Modelo", dashboard: "Dashboard", api: "API",
  relatorio: "Relatório", produto_dados: "Produto de dados", consumidor: "Consumidor",
  processo: "Processo", regra: "Regra", atributo: "Atributo",
};

export const CAMADAS: Record<string, string> = {
  fontes: "Fontes", bruto: "Bruto", integrado: "Integrado", tratado: "Tratado",
  validado: "Validado", mart: "Mart", consumo: "Consumo",
};

export const RELACOES: Record<string, string> = {
  originou: "originou", foi_extraido_de: "foi extraído de", foi_integrado_com: "foi integrado com",
  foi_transformado_por: "foi transformado por", gerou: "gerou", derivou_de: "derivou de",
  validou: "validou", alimentou: "alimentou", consumiu: "consumiu", substituiu: "substituiu",
  depende_de: "depende de",
};

export const SENSIBILIDADES: Record<string, string> = {
  publico: "Público", interno: "Interno", restrito: "Restrito", sensivel: "Sensível",
};

export const PARAMETROS: Record<string, string> = {
  limite_frequencia: "Frequência mínima (%)",
  min_completude: "Completude mínima (0 a 1)",
  periodos_sem_matricula: "Períodos sem matrícula para evasão",
};

const dataHora = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" });
const numero = new Intl.NumberFormat("pt-BR");

const dia = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short" });

export function fData(v: string | null | undefined) {
  if (!v) return "Sem registro";
  // Data sem hora seria lida como meia-noite UTC e voltaria um dia no fuso local.
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return dia.format(new Date(`${v}T12:00:00`));
  return dataHora.format(new Date(v));
}
export const fNum = (v: number | null | undefined) => (v === null || v === undefined ? "Sem dados" : numero.format(v));
export const fPct = (v: number | null | undefined, casas = 1) =>
  v === null || v === undefined
    ? "Sem dados"
    : `${(v * 100).toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas })}%`;

export function fCelula(v: unknown): string {
  if (v === null || v === undefined) return "";
  if (typeof v === "boolean") return v ? "Sim" : "Não";
  if (typeof v === "number") return numero.format(v);
  if (typeof v === "object") return JSON.stringify(v);
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}T/.test(v)) return fData(v);
  return String(v);
}

export const rotuloColuna = (c: string) => c.replace(/_/g, " ").replace(/^./, (l) => l.toUpperCase());
