import { useState } from "react";
import { pedir, useDados } from "../api";
import GrafoVisual, { Legenda } from "../components/GrafoVisual";
import { Campo, Estado } from "../components/Ui";
import { fData, RELACOES, TIPOS } from "../format";
import { caminho } from "../rota";
import { ArestaGrafo, AtivoResumo, AtributoRotulado, Grafo, NoGrafo } from "../types";

export default function GrafoPagina({ params }: { params: URLSearchParams }) {
  const [ativo, setAtivo] = useState(params.get("ativo") ?? "");
  const [atributo, setAtributo] = useState("");
  const [direcao, setDirecao] = useState(params.get("direcao") ?? "ambos");
  const [profundidade, setProfundidade] = useState(30);
  const [detalhe, setDetalhe] = useState("ativos");
  const [data, setData] = useState("");
  const [no, setNo] = useState<NoGrafo | null>(null);
  const [aresta, setAresta] = useState<ArestaGrafo | null>(null);

  const listas = useDados(() => Promise.all([pedir<AtivoResumo[]>("/ativos"), pedir<AtributoRotulado[]>("/atributos")]), []);
  const em = data ? new Date(`${data}T12:00:00`).toISOString() : null;
  const grafo = useDados<Grafo>(() => {
    if (atributo) return pedir(`/atributos/${atributo}/grafo`);
    const busca = new URLSearchParams({ detalhe });
    if (em) busca.set("em", em);
    if (ativo) {
      busca.set("direcao", direcao);
      busca.set("profundidade", String(profundidade));
      return pedir(`/linhagem/${ativo}/grafo?${busca}`);
    }
    return pedir(`/linhagem/grafo?${busca}`);
  }, [ativo, atributo, direcao, profundidade, detalhe, em]);

  const selecionarNo = (n: NoGrafo | null) => {
    setNo(n);
    setAresta(null);
  };
  const porChave = (c: string) => grafo.dados?.nos.find((n) => n.chave === c)?.codigo ?? c;

  return (
    <>
      <h1>Grafo de linhagem</h1>
      <form className="filtros" onSubmit={(e) => e.preventDefault()}>
        <Campo rotulo="Ativo">
          <select value={ativo} disabled={!!atributo} onChange={(e) => { setAtivo(e.target.value); selecionarNo(null); }}>
            <option value="">Grafo completo</option>
            {listas.dados?.[0].map((a) => <option key={a.id} value={a.id}>{a.codigo}: {a.nome}</option>)}
          </select>
        </Campo>
        <Campo rotulo="Direção">
          <select value={direcao} disabled={!ativo || !!atributo} onChange={(e) => setDirecao(e.target.value)}>
            <option value="ambos">Antes e depois</option>
            <option value="ascendentes">Só de onde veio</option>
            <option value="descendentes">Só para onde vai</option>
          </select>
        </Campo>
        <Campo rotulo="Profundidade">
          <input type="number" min={1} max={100} value={profundidade} disabled={!ativo || !!atributo} onChange={(e) => setProfundidade(Number(e.target.value) || 1)} />
        </Campo>
        <Campo rotulo="Mostrar">
          <select value={detalhe} disabled={!!atributo} onChange={(e) => setDetalhe(e.target.value)}>
            <option value="ativos">Ativos</option>
            <option value="completo">Ativos, processos e regras</option>
          </select>
        </Campo>
        <Campo rotulo="Como estava em">
          <input type="date" value={data} disabled={!!atributo} onChange={(e) => setData(e.target.value)} />
        </Campo>
        <Campo rotulo="Linhagem de atributo">
          <select value={atributo} onChange={(e) => { setAtributo(e.target.value); selecionarNo(null); }}>
            <option value="">Nenhum</option>
            {listas.dados?.[1].filter((a) => a.critico).map((a) => <option key={a.id} value={a.id}>{a.rotulo}</option>)}
          </select>
        </Campo>
      </form>

      <Estado erro={grafo.erro ?? listas.erro} carregando={grafo.carregando && !grafo.dados} />
      {grafo.dados && (
        <section className="palco-hero">
          <GrafoVisual
            ajustar={detalhe === "ativos" && !atributo}
            grafo={grafo.dados}
            selecionado={no?.chave ?? null}
            aoSelecionar={selecionarNo}
            aoSelecionarAresta={(a) => { setAresta(a); setNo(null); }}
          />
          <div className="palco-rodape"><Legenda /></div>
        </section>
      )}

      {no && (
        <section className="detalhe-faixa">
          <h2>{no.codigo}: {no.nome}</h2>
          <p>
            {TIPOS[no.tipo] ?? no.tipo}.{" "}
            {no.expressao && <>Regra: {no.expressao}. </>}
            {no.desatualizado && "Leu uma versão já superada. "}
          </p>
          {no.classe === "ativo" && (
            <p className="acoes">
              <a className="botao" href={caminho("catalogo", { ativo: no.id })}>Abrir no catálogo</a>
              <a className="botao" href={caminho("impacto", { ativo: no.id })}>Analisar impacto</a>
            </p>
          )}
        </section>
      )}
      {aresta && (
        <section className="detalhe-faixa">
          <h2>{porChave(aresta.origem)} {RELACOES[aresta.tipo_relacao] ?? aresta.tipo_relacao} {porChave(aresta.destino)}</h2>
          <p>
            {aresta.evidencia ? `Evidência: ${aresta.evidencia}. ` : "Sem evidência registrada. "}
            {aresta.vigente_de && `Vigente desde ${fData(aresta.vigente_de)}`}
            {aresta.vigente_ate && ` até ${fData(aresta.vigente_ate)}`}
          </p>
        </section>
      )}
    </>
  );
}
