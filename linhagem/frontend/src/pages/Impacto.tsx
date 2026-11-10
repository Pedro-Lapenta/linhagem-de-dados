import { FormEvent, useState } from "react";
import { enviar, pedir, useDados } from "../api";
import { Aviso, Campo, Estado, Selo, TabelaDados } from "../components/Ui";
import { fData } from "../format";
import { AnaliseImpacto, AtivoResumo, AtributoRotulado, Responsavel, ResultadoConsulta } from "../types";

export default function Impacto({ params }: { params: URLSearchParams }) {
  const listas = useDados(
    () => Promise.all([pedir<AtivoResumo[]>("/ativos"), pedir<AtributoRotulado[]>("/atributos"), pedir<Responsavel[]>("/responsaveis")]),
    [],
  );
  const salvas = useDados(() => pedir<AnaliseImpacto[]>("/impacto"), []);
  const [ativo, setAtivo] = useState(params.get("ativo") ?? "");
  const [atributo, setAtributo] = useState("");
  const [mudanca, setMudanca] = useState("");
  const [tipo, setTipo] = useState("estrutural");
  const [acao, setAcao] = useState("Reprocessar os ativos afetados e comunicar os consumidores");
  const [responsavel, setResponsavel] = useState("");
  const [mensagem, setMensagem] = useState<{ tipo: "ok" | "erro"; texto: string } | null>(null);

  const alcance = useDados<ResultadoConsulta | null>(
    () => (ativo ? pedir(`/impacto/calcular?ativo_id=${ativo}${atributo ? `&atributo_id=${atributo}` : ""}`) : Promise.resolve(null)),
    [ativo, atributo],
  );

  if (!listas.dados) return <Estado erro={listas.erro} carregando={listas.carregando} />;
  const [ativos, atributos, responsaveis] = listas.dados;
  const atributosDoAtivo = atributos.filter((a) => String(a.ativo_id) === ativo);
  const contagem = (s: string) => alcance.dados?.linhas.filter((l) => l.severidade === s).length ?? 0;

  const salvar = async (e: FormEvent) => {
    e.preventDefault();
    try {
      await enviar("/impacto", {
        ativo_id: Number(ativo), atributo_id: atributo ? Number(atributo) : null, mudanca,
        tipo_impacto: tipo, acao, responsavel_id: responsavel ? Number(responsavel) : null,
      });
      setMensagem({ tipo: "ok", texto: "Relatório de impacto salvo." });
      setMudanca("");
      salvas.recarregar();
    } catch (falha) {
      setMensagem({ tipo: "erro", texto: (falha as Error).message });
    }
  };

  const mudarStatus = async (id: number, status: string) => {
    try {
      await enviar(`/impacto/${id}`, { status }, "PATCH");
      salvas.recarregar();
    } catch (falha) {
      setMensagem({ tipo: "erro", texto: (falha as Error).message });
    }
  };

  return (
    <>
      <h1>Análise de impacto</h1>
      <form className="filtros" onSubmit={(e) => e.preventDefault()}>
        <Campo rotulo="O que vai mudar">
          <select value={ativo} onChange={(e) => { setAtivo(e.target.value); setAtributo(""); }}>
            <option value="">Escolha um ativo</option>
            {ativos.map((a) => <option key={a.id} value={a.id}>{a.codigo}: {a.nome}</option>)}
          </select>
        </Campo>
        <Campo rotulo="Coluna específica">
          <select value={atributo} disabled={!atributosDoAtivo.length} onChange={(e) => setAtributo(e.target.value)}>
            <option value="">Ativo inteiro</option>
            {atributosDoAtivo.map((a) => <option key={a.id} value={a.id}>{a.nome}</option>)}
          </select>
        </Campo>
      </form>

      <Estado erro={alcance.erro} carregando={alcance.carregando && !!ativo} />
      {!ativo && <p className="suave">Escolha um ativo para ver tudo o que depende dele.</p>}
      {alcance.dados && (
        <section>
          <h2>
            {alcance.dados.linhas.length} afetados: {contagem("critica")} críticos, {contagem("alta")} altos, {contagem("media")} médios, {contagem("baixa")} baixos
          </h2>
          <TabelaDados colunas={alcance.dados.colunas} linhas={alcance.dados.linhas} />
          {alcance.dados.linhas.length > 0 && (
            <form className="formulario" onSubmit={salvar}>
              <Campo rotulo="Mudança analisada">
                <input required minLength={3} value={mudanca} onChange={(e) => setMudanca(e.target.value)} placeholder="Ex.: novo código de situação" />
              </Campo>
              <Campo rotulo="Tipo de impacto">
                <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
                  <option value="estrutural">Estrutural</option>
                  <option value="semantico">Semântico</option>
                  <option value="qualidade">Qualidade</option>
                  <option value="consumo">Consumo</option>
                </select>
              </Campo>
              <Campo rotulo="Ação recomendada">
                <input required minLength={3} value={acao} onChange={(e) => setAcao(e.target.value)} />
              </Campo>
              <Campo rotulo="Responsável">
                <select value={responsavel} onChange={(e) => setResponsavel(e.target.value)}>
                  <option value="">Sem responsável</option>
                  {responsaveis.map((r) => <option key={r.id} value={r.id}>{r.nome}</option>)}
                </select>
              </Campo>
              <button type="submit" className="primario">Salvar relatório</button>
            </form>
          )}
        </section>
      )}
      {mensagem && <Aviso tipo={mensagem.tipo}>{mensagem.texto}</Aviso>}

      <section>
        <h2>Relatórios salvos</h2>
        <Estado erro={salvas.erro} carregando={salvas.carregando && !salvas.dados} />
        {salvas.dados?.length === 0 && <p className="suave">Nenhum relatório salvo ainda.</p>}
        <ul className="relatorios">
          {salvas.dados?.map((r) => (
            <li key={r.id}>
              <div>
                <strong>{r.mudanca}</strong>
                <p className="suave">{r.codigo}: {r.nome}. {r.ativos.length} afetados. {fData(r.criada_em)}. {r.acao}.</p>
              </div>
              <Selo valor={r.severidade} />
              <Campo rotulo="Status">
                <select value={r.status} onChange={(e) => mudarStatus(r.id, e.target.value)}>
                  <option value="aberto">Aberto</option>
                  <option value="tratado">Tratado</option>
                  <option value="encerrado">Encerrado</option>
                </select>
              </Campo>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
