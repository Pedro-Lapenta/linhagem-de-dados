import { FormEvent, useState } from "react";
import { enviar, pedir, useDados } from "../api";
import { Aviso, Campo, Estado, TabelaDados } from "../components/Ui";
import { AtivoResumo, AtributoRotulado, DefinicaoConsulta, ParametroConsulta, ResultadoConsulta, VersaoRotulada } from "../types";

type Valores = Record<string, string | number | boolean>;

export default function Consultas() {
  const dados = useDados(
    () =>
      Promise.all([
        pedir<DefinicaoConsulta[]>("/consultas"),
        pedir<AtivoResumo[]>("/ativos"),
        pedir<AtributoRotulado[]>("/atributos"),
        pedir<VersaoRotulada[]>("/versoes"),
      ]),
    [],
  );
  const [ativa, setAtiva] = useState<string | null>(null);
  const [valores, setValores] = useState<Valores>({});
  const [resultado, setResultado] = useState<ResultadoConsulta | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  if (!dados.dados) return <Estado erro={dados.erro} carregando={dados.carregando} />;
  const [consultas, ativos, atributos, versoes] = dados.dados;
  const consulta = consultas.find((c) => c.id === ativa) ?? consultas[0];

  const padroes = (c: DefinicaoConsulta): Valores => {
    const painel = ativos.find((a) => a.codigo === "D-EVA");
    const inicial: Valores = {};
    for (const p of c.parametros) {
      if (p.padrao !== undefined) inicial[p.nome] = p.padrao;
      else if (p.tipo === "ativo") {
        // Começar pela fonte é o que dá resposta útil às perguntas que descem o grafo.
        const desce = p.nome === "origem" || c.id === "descendentes";
        inicial[p.nome] = (desce ? ativos.find((a) => a.codigo === "F-MAT") : painel)?.id ?? ativos[0]?.id;
      }
      else if (p.tipo === "atributo") inicial[p.nome] = atributos.find((a) => a.rotulo === "D-EVA.taxa_evasao")?.id ?? atributos[0]?.id;
      else if (p.tipo === "versao") inicial[p.nome] = versoes.find((v) => v.codigo === "D-EVA")?.id ?? versoes[0]?.id;
      else inicial[p.nome] = "";
    }
    return inicial;
  };
  const atuais = { ...padroes(consulta), ...valores };

  const trocar = (c: DefinicaoConsulta) => {
    setAtiva(c.id);
    setValores({});
    setResultado(null);
    setErro(null);
  };

  const executar = async (e: FormEvent) => {
    e.preventDefault();
    setErro(null);
    try {
      setResultado(await enviar(`/consultas/${consulta.id}/executar`, atuais));
    } catch (falha) {
      setResultado(null);
      setErro((falha as Error).message);
    }
  };

  const controle = (p: ParametroConsulta) => {
    const definir = (v: string | number | boolean) => setValores({ ...atuais, [p.nome]: v });
    const opcoes =
      p.tipo === "ativo" ? ativos.map((a) => [a.id, `${a.codigo}: ${a.nome}`] as const)
      : p.tipo === "atributo" ? atributos.map((a) => [a.id, a.rotulo] as const)
      : p.tipo === "versao" ? versoes.map((v) => [v.id, v.rotulo] as const)
      : null;
    if (opcoes) {
      return (
        <select value={String(atuais[p.nome])} onChange={(e) => definir(Number(e.target.value))}>
          {opcoes.map(([v, r]) => <option key={v} value={v}>{r}</option>)}
        </select>
      );
    }
    if (p.tipo === "booleano") {
      return <input type="checkbox" checked={Boolean(atuais[p.nome])} onChange={(e) => definir(e.target.checked)} />;
    }
    if (p.tipo === "data") {
      return <input type="date" value={String(atuais[p.nome])} onChange={(e) => definir(e.target.value)} />;
    }
    return <input type="number" min={1} value={String(atuais[p.nome])} onChange={(e) => definir(Number(e.target.value))} />;
  };

  return (
    <>
      <h1>Consultas recursivas</h1>
      <div className="mestre-detalhe">
        <ul className="lista-escolha">
          {consultas.map((c) => (
            <li key={c.id}>
              <button className={c.id === consulta.id ? "ativo" : ""} onClick={() => trocar(c)} aria-pressed={c.id === consulta.id}>
                <strong>{c.titulo}</strong>
                <span>{c.pergunta}</span>
              </button>
            </li>
          ))}
        </ul>
        <div className="coluna-detalhe">
          <h2>{consulta.pergunta}</h2>
          <form className="filtros" onSubmit={executar}>
            {consulta.parametros.map((p) => <Campo key={p.nome} rotulo={p.rotulo}>{controle(p)}</Campo>)}
            <button type="submit" className="primario">Executar consulta</button>
          </form>
          {erro && <Aviso tipo="erro">{erro}</Aviso>}
          {resultado && (
            <>
              <p className="suave">{resultado.linhas.length} linhas em {resultado.duracao_ms.toLocaleString("pt-BR")} ms.</p>
              <TabelaDados colunas={resultado.colunas} linhas={resultado.linhas} />
              <details open>
                <summary>SQL executado</summary>
                <pre className="sql">{resultado.sql}</pre>
              </details>
            </>
          )}
        </div>
      </div>
    </>
  );
}
