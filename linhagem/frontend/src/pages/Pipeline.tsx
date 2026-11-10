import { useState } from "react";
import { enviar, pedir, useDados } from "../api";
import { Aviso, Campo, Estado, Selo } from "../components/Ui";
import { fData, fNum, PARAMETROS } from "../format";
import { AtivoResumo, Comparacao, Desatualizado, Execucao, ExecucaoDetalhe, Processo } from "../types";

function DetalheExecucao({ id }: { id: number }) {
  const { dados, erro, carregando } = useDados(() => pedir<ExecucaoDetalhe>(`/execucoes/${id}`), [id]);
  if (!dados) return <Estado erro={erro} carregando={carregando} />;
  return (
    <div className="execucao-detalhe">
      <div className="duas-colunas apertadas">
        <div>
          <h3>Leu</h3>
          <ul className="dependentes">{dados.entradas.map((v) => <li key={v.versao_id}>{v.codigo} v{v.numero}, {fNum(v.linhas)} linhas</li>)}</ul>
          {!dados.entradas.length && <p className="suave">Nada registrado: a transação foi desfeita.</p>}
        </div>
        <div>
          <h3>Gravou</h3>
          <ul className="dependentes">{dados.saidas.map((v) => <li key={v.versao_id}>{v.codigo} v{v.numero}, {fNum(v.linhas)} linhas</li>)}</ul>
          {!dados.saidas.length && <p className="suave">Nada foi gravado.</p>}
        </div>
      </div>
      <h3>Log</h3>
      <pre className="sql">{dados.log}</pre>
      <details><summary>Manifesto da execução</summary><pre className="sql">{JSON.stringify(dados.evidencia, null, 2)}</pre></details>
    </div>
  );
}

function ComparaVersoes({ ativos }: { ativos: AtivoResumo[] }) {
  const candidatos = ativos.filter((a) => (a.versao_atual ?? 0) > 1);
  const [ativo, setAtivo] = useState("");
  const [a, setA] = useState(1);
  const [b, setB] = useState(2);
  const atual = candidatos.find((c) => String(c.id) === ativo) ?? candidatos.find((c) => c.codigo === "D-EVA") ?? candidatos[0];
  const numeros = Array.from({ length: atual?.versao_atual ?? 0 }, (_, i) => i + 1);
  const comparacao = useDados<Comparacao | null>(
    () => (atual ? pedir(`/ativos/${atual.id}/versoes/comparar?a=${a}&b=${b}`) : Promise.resolve(null)),
    [atual?.id, a, b],
  );
  if (!atual) return <p className="suave">Execute o pipeline após uma mudança para ter versões a comparar.</p>;
  const c = comparacao.dados;
  return (
    <>
      <form className="filtros" onSubmit={(e) => e.preventDefault()}>
        <Campo rotulo="Ativo">
          <select value={atual.id} onChange={(e) => { setAtivo(e.target.value); setA(1); setB(2); }}>
            {candidatos.map((x) => <option key={x.id} value={x.id}>{x.codigo}: {x.nome}</option>)}
          </select>
        </Campo>
        <Campo rotulo="Versão A"><select value={a} onChange={(e) => setA(Number(e.target.value))}>{numeros.map((n) => <option key={n}>{n}</option>)}</select></Campo>
        <Campo rotulo="Versão B"><select value={b} onChange={(e) => setB(Number(e.target.value))}>{numeros.map((n) => <option key={n}>{n}</option>)}</select></Campo>
      </form>
      <Estado erro={comparacao.erro} carregando={comparacao.carregando && !c} />
      {c && (
        <>
          <p className="suave">
            A: {fNum(c.a.linhas)} linhas, {fData(c.a.criado_em)}. B: {fNum(c.b.linhas)} linhas, {fData(c.b.criado_em)}.
            {c.a.checksum === c.b.checksum ? " Conteúdo idêntico." : " Conteúdo diferente."}
          </p>
          {!c.comparavel && <p className="suave">Tabela grande demais para guardar o conteúdo de cada versão. Só linhas e checksum são comparados.</p>}
          {c.comparavel && c.diferencas.length > 0 && (
            <div className="rolagem">
              <table>
                <thead><tr><th>Linha</th><th>Coluna</th><th className="num">Versão {a}</th><th className="num">Versão {b}</th></tr></thead>
                <tbody>
                  {c.diferencas.map((d, i) => (
                    <tr key={i}><td>{d.chave}</td><td>{d.coluna}</td><td className="num">{String(d.a ?? "")}</td><td className="num">{String(d.b ?? "")}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </>
  );
}

export default function Pipeline() {
  const processos = useDados(() => pedir<Processo[]>("/processos"), []);
  const execucoes = useDados(() => pedir<Execucao[]>("/execucoes?limite=40"), []);
  const desatualizados = useDados(() => pedir<Desatualizado[]>("/desatualizados"), []);
  const ativos = useDados(() => pedir<AtivoResumo[]>("/ativos"), []);
  const [valores, setValores] = useState<Record<string, Record<string, number>>>({});
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [mensagem, setMensagem] = useState<{ tipo: "ok" | "erro"; texto: string } | null>(null);
  const [aberta, setAberta] = useState<number | null>(null);
  const [fonteSim, setFonteSim] = useState("");

  const atualizar = () => {
    processos.recarregar();
    execucoes.recarregar();
    desatualizados.recarregar();
    ativos.recarregar();
  };

  const acao = async (chave: string, tarefa: () => Promise<string>) => {
    setOcupado(chave);
    setMensagem(null);
    try {
      setMensagem({ tipo: "ok", texto: await tarefa() });
    } catch (falha) {
      setMensagem({ tipo: "erro", texto: (falha as Error).message });
    } finally {
      setOcupado(null);
      atualizar();
    }
  };

  const fontes = ativos.dados?.filter((a) => a.tipo === "fonte" && a.versao_atual) ?? [];

  return (
    <>
      <h1>Pipeline</h1>
      <div className="barra-acoes">
        <button className="primario" disabled={!!ocupado} onClick={() => acao("todos", async () => {
          const r = await enviar<Execucao[]>("/pipeline/executar", {});
          return `Pipeline executado: ${r.length} etapas concluídas.`;
        })}>
          {ocupado === "todos" ? "Executando…" : "Executar pipeline completo"}
        </button>
        <form className="filtros embutido" onSubmit={(e) => {
          e.preventDefault();
          const id = fonteSim || String(fontes[0]?.id ?? "");
          if (id) acao("simular", async () => {
            const r = await enviar<{ ativo: string; linhas_alteradas: number; versao: number }>(`/fontes/${id}/simular-atualizacao`, {});
            return `${r.ativo} atualizada: ${r.linhas_alteradas} linhas alteradas, agora na versão ${r.versao}.`;
          });
        }}>
          <Campo rotulo="Fonte">
            <select value={fonteSim} onChange={(e) => setFonteSim(e.target.value)}>
              {fontes.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}
            </select>
          </Campo>
          <button type="submit" disabled={!!ocupado || !fontes.length}>Simular atualização da fonte</button>
        </form>
      </div>
      {mensagem && <Aviso tipo={mensagem.tipo}>{mensagem.texto}</Aviso>}
      {!!desatualizados.dados?.length && (
        <Aviso tipo="atencao">
          Desatualizados por mudança em {[...new Set(desatualizados.dados.map((d) => d.causa))].join(", ")}: {desatualizados.dados.map((d) => d.codigo).join(", ")}.
        </Aviso>
      )}

      <section>
        <h2>Etapas, na ordem de execução</h2>
        <Estado erro={processos.erro} carregando={processos.carregando && !processos.dados} />
        <ol className="etapas">
          {processos.dados?.map((p) => {
            const atuais = { ...p.parametros_padrao, ...valores[p.codigo] };
            return (
              <li key={p.id}>
                <div className="etapa-texto">
                  <strong>{p.nome}</strong>
                  <span className="suave">{p.entradas?.join(", ")} para {p.saidas?.join(", ")}</span>
                </div>
                <div className="etapa-parametros">
                  {Object.keys(p.parametros_padrao).map((nome) => (
                    <Campo key={nome} rotulo={PARAMETROS[nome] ?? nome}>
                      <input
                        type="number"
                        step="any"
                        value={atuais[nome]}
                        onChange={(e) => setValores({ ...valores, [p.codigo]: { ...valores[p.codigo], [nome]: Number(e.target.value) } })}
                      />
                    </Campo>
                  ))}
                </div>
                <Selo valor={p.ultimo_status} />
                <button disabled={!!ocupado} onClick={() => acao(p.codigo, async () => {
                  const r = await enviar<Execucao>(`/processos/${p.id}/executar`, { parametros: valores[p.codigo] ?? {} });
                  return `${p.nome}: ${fNum(r.linhas_gravadas)} linhas gravadas.`;
                })}>
                  {ocupado === p.codigo ? "Executando…" : "Executar"}
                </button>
              </li>
            );
          })}
        </ol>
      </section>

      <section>
        <h2>Comparar versões</h2>
        {ativos.dados && <ComparaVersoes ativos={ativos.dados} />}
      </section>

      <section>
        <h2>Histórico de execuções</h2>
        <ul className="eventos expansivel">
          {execucoes.dados?.map((e) => (
            <li key={e.id}>
              <button className="linha-evento" aria-expanded={aberta === e.id} onClick={() => setAberta(aberta === e.id ? null : e.id)}>
                <Selo valor={e.status} />
                <span>{e.processo_nome}</span>
                <span className="suave">{e.linhas_gravadas !== null ? `${fNum(e.linhas_gravadas)} linhas` : "Sem gravação"}</span>
                <span className="suave">por {e.executor}</span>
                <span className="suave">{fData(e.iniciada_em)}</span>
              </button>
              {aberta === e.id && <DetalheExecucao id={e.id} />}
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
