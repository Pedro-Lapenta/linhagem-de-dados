import { KeyboardEvent, useMemo } from "react";
import { CAMADAS, RELACOES, TIPOS } from "../format";
import { ArestaGrafo, Grafo, NoGrafo } from "../types";

const LARGURA_NO = 132;
const ALTURA_NO = 46;
const PASSO_X = 164;
const PASSO_Y = 62;
const MARGEM_X = 16;
const TOPO = 34;

interface Posicionado extends NoGrafo { x: number; y: number; coluna: number }

function organizar(grafo: Grafo) {
  const entradas = new Map<string, string[]>();
  const saidas = new Map<string, string[]>();
  for (const no of grafo.nos) {
    entradas.set(no.chave, []);
    saidas.set(no.chave, []);
  }
  for (const a of grafo.arestas) {
    entradas.get(a.destino)?.push(a.origem);
    saidas.get(a.origem)?.push(a.destino);
  }

  // Camada = caminho mais longo a partir de uma raiz; memo porque o grafo é acíclico.
  const memo = new Map<string, number>();
  const nivel = (chave: string): number => {
    if (memo.has(chave)) return memo.get(chave)!;
    const pais = entradas.get(chave) ?? [];
    const valor = pais.length ? Math.max(...pais.map(nivel)) + 1 : 0;
    memo.set(chave, valor);
    return valor;
  };
  grafo.nos.forEach((n) => nivel(n.chave));

  // Regras não têm entradas: ficam logo antes do processo que as usa, não na primeira coluna.
  for (const no of grafo.nos) {
    if (no.classe === "regra") {
      const alvos = saidas.get(no.chave) ?? [];
      if (alvos.length) memo.set(no.chave, Math.max(0, Math.min(...alvos.map((a) => memo.get(a)!)) - 1));
    }
  }

  const colunas: NoGrafo[][] = [];
  for (const no of grafo.nos) (colunas[memo.get(no.chave)!] ??= []).push(no);
  const colunasCheias = colunas.map((c) => c ?? []);
  colunasCheias.forEach((c) => c.sort((a, b) => a.codigo.localeCompare(b.codigo)));

  // Duas passadas de baricentro reduzem o cruzamento de arestas.
  for (let passada = 0; passada < 2; passada++) {
    const ordem = new Map<string, number>();
    colunasCheias.forEach((c) => c.forEach((n, i) => ordem.set(n.chave, i)));
    for (const coluna of colunasCheias) {
      const peso = (n: NoGrafo) => {
        const vizinhos = [...(entradas.get(n.chave) ?? []), ...(saidas.get(n.chave) ?? [])];
        return vizinhos.length ? vizinhos.reduce((s, v) => s + (ordem.get(v) ?? 0), 0) / vizinhos.length : Infinity;
      };
      coluna.sort((a, b) => peso(a) - peso(b));
    }
  }

  const maiorColuna = Math.max(1, ...colunasCheias.map((c) => c.length));
  const altura = TOPO + maiorColuna * PASSO_Y + 8;
  const posicoes = new Map<string, Posicionado>();
  colunasCheias.forEach((coluna, x) => {
    const inicio = TOPO + ((maiorColuna - coluna.length) * PASSO_Y) / 2;
    coluna.forEach((no, i) => {
      posicoes.set(no.chave, { ...no, coluna: x, x: MARGEM_X + x * PASSO_X, y: inicio + i * PASSO_Y });
    });
  });

  const rotulos = colunasCheias.map((coluna) => {
    const camadas = [...new Set(coluna.filter((n) => n.classe === "ativo" && n.camada).map((n) => n.camada!))];
    return camadas.map((c) => CAMADAS[c]).join(" e ");
  });

  return { posicoes, largura: MARGEM_X * 2 + colunasCheias.length * PASSO_X - (PASSO_X - LARGURA_NO), altura, rotulos };
}

function alcance(grafo: Grafo, inicio: string) {
  const andar = (chaveDe: keyof ArestaGrafo, chavePara: keyof ArestaGrafo) => {
    const vistos = new Set<string>();
    const fila = [inicio];
    while (fila.length) {
      const atual = fila.pop()!;
      for (const a of grafo.arestas) {
        if (a[chaveDe] === atual && !vistos.has(a[chavePara] as string)) {
          vistos.add(a[chavePara] as string);
          fila.push(a[chavePara] as string);
        }
      }
    }
    return vistos;
  };
  return { acima: andar("destino", "origem"), abaixo: andar("origem", "destino") };
}

const cortar = (t: string, n: number) => (t.length > n ? `${t.slice(0, n - 1)}…` : t);

interface Props {
  grafo: Grafo;
  selecionado: string | null;
  aoSelecionar: (no: NoGrafo | null) => void;
  aoSelecionarAresta?: (a: ArestaGrafo) => void;
  ajustar?: boolean;
}

export default function GrafoVisual({ grafo, selecionado, aoSelecionar, aoSelecionarAresta, ajustar }: Props) {
  const { posicoes, largura, altura, rotulos } = useMemo(() => organizar(grafo), [grafo]);
  const destaque = useMemo(() => (selecionado ? alcance(grafo, selecionado) : null), [grafo, selecionado]);

  const noAceso = (chave: string) =>
    !destaque || chave === selecionado || destaque.acima.has(chave) || destaque.abaixo.has(chave);
  const arestaAcesa = (a: ArestaGrafo) => {
    if (!destaque || !selecionado) return false;
    const naSubida = (destaque.acima.has(a.origem) || a.origem === selecionado) && (destaque.acima.has(a.destino) || a.destino === selecionado);
    const naDescida = (destaque.abaixo.has(a.origem) || a.origem === selecionado) && (destaque.abaixo.has(a.destino) || a.destino === selecionado);
    return naSubida || naDescida;
  };

  const teclado = (e: KeyboardEvent, no: NoGrafo) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      aoSelecionar(no);
    }
  };

  if (!grafo.nos.length) return <p className="suave">Nenhuma dependência registrada para esta seleção.</p>;

  return (
    <div className="palco" onClick={() => aoSelecionar(null)}>
      <svg
        {...(ajustar
          ? { viewBox: `0 0 ${largura} ${altura}`, style: { width: "100%", minWidth: 940, maxWidth: largura, height: "auto" } }
          : { width: largura, height: altura })}
        role="group"
        aria-label="Grafo de linhagem"
      >
        <defs>
          <marker id="seta" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto">
            <path d="M0 0.8 L7 4 L0 7.2 Z" fill="#8fa8bf" />
          </marker>
          <marker id="seta-acesa" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto">
            <path d="M0 0.8 L7 4 L0 7.2 Z" fill="#0079b8" />
          </marker>
        </defs>

        {rotulos.map((rotulo, i) => (
          <text key={i} className="rotulo-coluna" x={MARGEM_X + i * PASSO_X} y={18}>{rotulo}</text>
        ))}

        {grafo.arestas.map((a, i) => {
          const de = posicoes.get(a.origem);
          const para = posicoes.get(a.destino);
          if (!de || !para) return null;
          const x1 = de.x + LARGURA_NO;
          const y1 = de.y + ALTURA_NO / 2;
          const x2 = para.x - 2;
          const y2 = para.y + ALTURA_NO / 2;
          const curva = Math.max(36, (x2 - x1) / 2);
          const d = `M${x1} ${y1} C${x1 + curva} ${y1}, ${x2 - curva} ${y2}, ${x2} ${y2}`;
          const acesa = arestaAcesa(a);
          const apagada = destaque && !acesa;
          const descricao = `${de.codigo} ${RELACOES[a.tipo_relacao] ?? a.tipo_relacao} ${para.codigo}`;
          return (
            <g key={i} className="aresta-grupo">
              <path
                className={`aresta ${acesa ? "acesa" : ""} ${apagada ? "apagada" : ""} ${a.vigente_ate ? "encerrada" : ""}`}
                d={d}
                markerEnd={`url(#${acesa ? "seta-acesa" : "seta"})`}
              />
              <path
                className="aresta-alvo"
                d={d}
                onClick={(e) => {
                  e.stopPropagation();
                  aoSelecionarAresta?.(a);
                }}
              >
                <title>{descricao}</title>
              </path>
            </g>
          );
        })}

        {[...posicoes.values()].map((no) => {
          const classes = ["no", `classe-${no.classe}`];
          if (no.chave === selecionado) classes.push("selecionado");
          else if (no.chave === grafo.foco && !selecionado) classes.push("foco");
          if (!noAceso(no.chave)) classes.push("apagado");
          if (no.desatualizado) classes.push("desatualizado");
          if (no.status === "obsoleto") classes.push("obsoleto");
          const raio = no.classe === "processo" ? 23 : no.classe === "regra" ? 2 : 8;
          return (
            <g
              key={no.chave}
              className={classes.join(" ")}
              transform={`translate(${no.x} ${no.y})`}
              tabIndex={0}
              role="button"
              aria-label={`${TIPOS[no.tipo] ?? no.tipo} ${no.codigo}, ${no.nome}${no.desatualizado ? ", desatualizado" : ""}`}
              aria-pressed={no.chave === selecionado}
              onClick={(e) => {
                e.stopPropagation();
                aoSelecionar(no);
              }}
              onKeyDown={(e) => teclado(e, no)}
            >
              <rect width={LARGURA_NO} height={ALTURA_NO} rx={raio} />
              <text className="no-codigo" x={14} y={20}>
                {no.classe === "atributo" ? cortar(no.nome, 15) : cortar(no.codigo, 13)}
                <title>{no.codigo}</title>
              </text>
              <text className="no-nome" x={14} y={35}>
                {no.classe === "atributo" ? no.codigo.split(".")[0] : cortar(no.nome, 19)}
                <title>{no.nome}</title>
              </text>
              {no.critico && <circle className="marca-critico" cx={LARGURA_NO - 11} cy={12} r={3.5}><title>Ativo crítico</title></circle>}
              {no.desatualizado && <text className="marca-desatualizado" x={LARGURA_NO - 16} y={38} aria-hidden="true">!</text>}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

export function Legenda() {
  return (
    <ul className="legenda">
      <li><span className="amostra ativo" />Ativo</li>
      <li><span className="amostra processo" />Processo</li>
      <li><span className="amostra regra" />Regra</li>
      <li><span className="amostra critico" />Crítico</li>
      <li><span className="amostra desatualizado">!</span>Desatualizado</li>
    </ul>
  );
}
