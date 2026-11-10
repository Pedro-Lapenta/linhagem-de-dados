import { FormEvent, ReactNode, useState } from "react";
import { enviar, pedir, useDados } from "../api";
import { Aviso, Campo, Estado } from "../components/Ui";
import { CAMADAS, fData, fNum, fPct, RELACOES, SENSIBILIDADES, TIPOS } from "../format";
import { caminho, irPara } from "../rota";
import { AtivoDetalhe, AtivoResumo, Proveniencia, Responsavel } from "../types";

const opcoes = (m: Record<string, string>, excluir: string[] = []) =>
  Object.entries(m).filter(([k]) => !excluir.includes(k)).map(([k, v]) => <option key={k} value={k}>{v}</option>);

const VAZIO = { codigo: "", nome: "", tipo: "dataset_tratado", camada: "tratado", descricao: "", localizacao: "", sensibilidade: "interno", critico: false, responsavel_id: "" };
type FormAtivo = typeof VAZIO;

function FormularioAtivo({ inicial, id, responsaveis, aoSalvar, aoCancelar }: {
  inicial: FormAtivo; id?: number; responsaveis: Responsavel[]; aoSalvar: (novoId: number) => void; aoCancelar: () => void;
}) {
  const [f, setF] = useState(inicial);
  const [erro, setErro] = useState<string | null>(null);
  const mudar = (k: keyof FormAtivo, v: string | boolean) => setF({ ...f, [k]: v });
  const salvar = async (e: FormEvent) => {
    e.preventDefault();
    try {
      const corpo = { ...f, responsavel_id: f.responsavel_id ? Number(f.responsavel_id) : null };
      const r = await enviar<{ id: number }>(id ? `/ativos/${id}` : "/ativos", corpo, id ? "PUT" : "POST");
      aoSalvar(r.id);
    } catch (falha) {
      setErro((falha as Error).message);
    }
  };
  return (
    <form className="formulario" onSubmit={salvar}>
      <Campo rotulo="Código"><input required value={f.codigo} onChange={(e) => mudar("codigo", e.target.value)} /></Campo>
      <Campo rotulo="Nome"><input required value={f.nome} onChange={(e) => mudar("nome", e.target.value)} /></Campo>
      <Campo rotulo="Tipo"><select value={f.tipo} onChange={(e) => mudar("tipo", e.target.value)}>{opcoes(TIPOS, ["processo", "regra", "atributo"])}</select></Campo>
      <Campo rotulo="Camada"><select value={f.camada} onChange={(e) => mudar("camada", e.target.value)}>{opcoes(CAMADAS)}</select></Campo>
      <Campo rotulo="Sensibilidade"><select value={f.sensibilidade} onChange={(e) => mudar("sensibilidade", e.target.value)}>{opcoes(SENSIBILIDADES)}</select></Campo>
      <Campo rotulo="Responsável">
        <select value={f.responsavel_id} onChange={(e) => mudar("responsavel_id", e.target.value)}>
          <option value="">Sem responsável</option>
          {responsaveis.map((r) => <option key={r.id} value={r.id}>{r.nome}</option>)}
        </select>
      </Campo>
      <Campo rotulo="Localização"><input value={f.localizacao} onChange={(e) => mudar("localizacao", e.target.value)} /></Campo>
      <Campo rotulo="Descrição"><input value={f.descricao} onChange={(e) => mudar("descricao", e.target.value)} /></Campo>
      <label className="marcar"><input type="checkbox" checked={f.critico} onChange={(e) => mudar("critico", e.target.checked)} /> Ativo crítico</label>
      <div className="acoes">
        <button type="submit" className="primario">{id ? "Salvar alterações" : "Cadastrar ativo"}</button>
        <button type="button" onClick={aoCancelar}>Cancelar</button>
      </div>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
    </form>
  );
}

const ITENS_AUDITORIA: [string, string][] = [
  ["tem_origem", "Origem"], ["tem_versoes", "Versões"], ["tem_processos", "Processos"], ["tem_regras", "Regras"],
  ["tem_responsavel", "Responsável"], ["tem_evidencias", "Evidências"], ["tem_derivados", "Derivados ou consumidores"],
];

function Secao({ titulo, children }: { titulo: string; children: ReactNode }) {
  return <section className="secao-detalhe"><h3>{titulo}</h3>{children}</section>;
}

function Detalhe({ id, ativos, responsaveis, aoMudar }: { id: number; ativos: AtivoResumo[]; responsaveis: Responsavel[]; aoMudar: () => void }) {
  const { dados: a, erro, carregando, recarregar } = useDados(() => pedir<AtivoDetalhe>(`/ativos/${id}`), [id]);
  const [editando, setEditando] = useState(false);
  const [mensagem, setMensagem] = useState<{ tipo: "ok" | "erro"; texto: string } | null>(null);
  const [atr, setAtr] = useState({ nome: "", tipo_dado: "text", critico: false, sensivel: false });
  const [dep, setDep] = useState({ outro: "", sentido: "destino", tipo_relacao: "depende_de", evidencia: "" });
  const [prov, setProv] = useState<Partial<Proveniencia> | null>(null);

  if (!a) return <Estado erro={erro} carregando={carregando} />;

  const tentar = async (tarefa: () => Promise<unknown>, sucesso: string) => {
    setMensagem(null);
    try {
      await tarefa();
      setMensagem({ tipo: "ok", texto: sucesso });
      recarregar();
      aoMudar();
    } catch (falha) {
      setMensagem({ tipo: "erro", texto: (falha as Error).message });
    }
  };

  const adicionarDep = (e: FormEvent) => {
    e.preventDefault();
    const outro = Number(dep.outro);
    const corpo = {
      origem_id: dep.sentido === "destino" ? a.id : outro,
      destino_id: dep.sentido === "destino" ? outro : a.id,
      tipo_relacao: dep.tipo_relacao,
      evidencia: dep.evidencia || null,
    };
    void tentar(() => enviar("/dependencias", corpo), "Dependência registrada.");
  };

  const inicialProv: Partial<Proveniencia> = a.proveniencia ?? { sistema_origem: "", instituicao: "" };
  const vizinhosVigentes = a.vizinhos.filter((v) => !v.vigente_ate);
  const encerrados = a.vizinhos.filter((v) => v.vigente_ate);

  return (
    <div className="ficha-ativo">
      <div className="ficha-topo">
        <div>
          <h2>{a.nome}</h2>
          <p className="suave">
            {a.codigo}, {TIPOS[a.tipo]}, camada {CAMADAS[a.camada]}{a.status === "obsoleto" ? ", obsoleto" : ""}
          </p>
        </div>
        <div className="acoes">
          <a className="botao" href={caminho("grafo", { ativo: a.id })}>Ver no grafo</a>
          <button onClick={() => setEditando(!editando)}>Editar</button>
          {a.status === "ativo" && (
            <button onClick={() => void tentar(() => pedir(`/ativos/${a.id}`, { method: "DELETE" }), "Ativo marcado como obsoleto e arestas encerradas.")}>Descontinuar</button>
          )}
        </div>
      </div>
      {mensagem && <Aviso tipo={mensagem.tipo}>{mensagem.texto}</Aviso>}
      {editando && (
        <FormularioAtivo
          id={a.id}
          responsaveis={responsaveis}
          inicial={{ codigo: a.codigo, nome: a.nome, tipo: a.tipo, camada: a.camada, descricao: a.descricao ?? "", localizacao: a.localizacao ?? "", sensibilidade: a.sensibilidade, critico: a.critico, responsavel_id: a.responsavel_id ? String(a.responsavel_id) : "" }}
          aoSalvar={() => { setEditando(false); recarregar(); aoMudar(); }}
          aoCancelar={() => setEditando(false)}
        />
      )}

      <Secao titulo="Metadados">
        <dl className="ficha">
          <dt>Descrição</dt><dd>{a.descricao || "Sem descrição"}</dd>
          <dt>Localização</dt><dd>{a.localizacao || "Não informada"}</dd>
          <dt>Responsável</dt><dd>{a.responsavel || "Sem responsável"}</dd>
          <dt>Sensibilidade</dt><dd>{SENSIBILIDADES[a.sensibilidade]}</dd>
          <dt>Crítico</dt><dd>{a.critico ? "Sim" : "Não"}</dd>
        </dl>
      </Secao>

      {a.auditabilidade && (
        <Secao titulo={`Auditabilidade: ${fPct(a.auditabilidade.iaa, 0)}`}>
          <ul className="checagens">
            {ITENS_AUDITORIA.map(([k, r]) => {
              const ok = a.auditabilidade![k as keyof typeof a.auditabilidade] as unknown as boolean;
              return <li key={k} className={ok ? "feito" : "pendente"}><span aria-hidden="true">{ok ? "✓" : "✕"}</span> {r}<span className="sr-only">{ok ? ": presente" : ": ausente"}</span></li>;
            })}
          </ul>
        </Secao>
      )}

      <Secao titulo="Proveniência">
        {a.proveniencia ? (
          <dl className="ficha">
            <dt>Sistema</dt><dd>{a.proveniencia.sistema_origem}</dd>
            <dt>Instituição</dt><dd>{a.proveniencia.instituicao}</dd>
            <dt>Local</dt><dd>{[...new Set([a.proveniencia.cidade, a.proveniencia.campus].filter(Boolean))].join(", ")}</dd>
            <dt>Periodicidade</dt><dd>{a.proveniencia.periodicidade}</dd>
            <dt>Cobertura</dt><dd>{fData(a.proveniencia.cobertura_inicio)} a {fData(a.proveniencia.cobertura_fim)}</dd>
            <dt>Condições de uso</dt><dd>{a.proveniencia.condicoes_uso}</dd>
          </dl>
        ) : <p className="suave">{a.tipo === "fonte" ? "Origem não documentada." : "Origem herdada dos ascendentes no grafo."}</p>}
        <button onClick={() => setProv(prov ? null : inicialProv)}>{a.proveniencia ? "Editar proveniência" : "Documentar proveniência"}</button>
        {prov && (
          <form className="formulario" onSubmit={(e) => {
            e.preventDefault();
            void tentar(() => enviar(`/ativos/${a.id}/proveniencia`, prov, "PUT"), "Proveniência salva.").then(() => setProv(null));
          }}>
            <Campo rotulo="Sistema de origem"><input required value={prov.sistema_origem ?? ""} onChange={(e) => setProv({ ...prov, sistema_origem: e.target.value })} /></Campo>
            <Campo rotulo="Instituição"><input required value={prov.instituicao ?? ""} onChange={(e) => setProv({ ...prov, instituicao: e.target.value })} /></Campo>
            <Campo rotulo="Cidade"><input value={prov.cidade ?? ""} onChange={(e) => setProv({ ...prov, cidade: e.target.value })} /></Campo>
            <Campo rotulo="Latitude"><input type="number" step="any" value={prov.latitude ?? ""} onChange={(e) => setProv({ ...prov, latitude: e.target.value === "" ? null : Number(e.target.value) })} /></Campo>
            <Campo rotulo="Longitude"><input type="number" step="any" value={prov.longitude ?? ""} onChange={(e) => setProv({ ...prov, longitude: e.target.value === "" ? null : Number(e.target.value) })} /></Campo>
            <Campo rotulo="Periodicidade"><input value={prov.periodicidade ?? ""} onChange={(e) => setProv({ ...prov, periodicidade: e.target.value })} /></Campo>
            <div className="acoes"><button type="submit" className="primario">Salvar proveniência</button></div>
          </form>
        )}
      </Secao>

      <Secao titulo={`Relações (${vizinhosVigentes.length} vigentes)`}>
        <ul className="relacoes">
          {vizinhosVigentes.map((v) => (
            <li key={v.id}>
              <span>
                {v.sentido === "entrada"
                  ? <><button className="link" onClick={() => irPara("catalogo", { ativo: v.outro_id })}>{v.outro_codigo}</button> {RELACOES[v.tipo_relacao]} {a.codigo}</>
                  : <>{a.codigo} {RELACOES[v.tipo_relacao]} <button className="link" onClick={() => irPara("catalogo", { ativo: v.outro_id })}>{v.outro_codigo}</button></>}
                {v.processo && <span className="suave"> via {v.processo}</span>}
              </span>
              <button onClick={() => void tentar(() => pedir(`/dependencias/${v.id}`, { method: "DELETE" }), "Dependência encerrada.")}>Encerrar</button>
            </li>
          ))}
        </ul>
        {encerrados.length > 0 && (
          <details><summary>{encerrados.length} encerradas</summary>
            <ul className="relacoes">{encerrados.map((v) => <li key={v.id}><span>{v.outro_codigo}: {RELACOES[v.tipo_relacao]}, até {fData(v.vigente_ate)}</span></li>)}</ul>
          </details>
        )}
        <form className="formulario" onSubmit={adicionarDep}>
          <Campo rotulo="Este ativo">
            <select value={dep.sentido} onChange={(e) => setDep({ ...dep, sentido: e.target.value })}>
              <option value="destino">alimenta</option>
              <option value="origem">recebe de</option>
            </select>
          </Campo>
          <Campo rotulo="Outro ativo">
            <select required value={dep.outro} onChange={(e) => setDep({ ...dep, outro: e.target.value })}>
              <option value="">Escolha</option>
              {ativos.filter((x) => x.id !== a.id).map((x) => <option key={x.id} value={x.id}>{x.codigo}: {x.nome}</option>)}
            </select>
          </Campo>
          <Campo rotulo="Relação"><select value={dep.tipo_relacao} onChange={(e) => setDep({ ...dep, tipo_relacao: e.target.value })}>{opcoes(RELACOES)}</select></Campo>
          <Campo rotulo="Evidência"><input value={dep.evidencia} onChange={(e) => setDep({ ...dep, evidencia: e.target.value })} /></Campo>
          <div className="acoes"><button type="submit" className="primario">Registrar dependência</button></div>
        </form>
      </Secao>

      <Secao titulo={`Atributos (${a.atributos.length})`}>
        {a.atributos.length > 0 && (
          <div className="rolagem"><table>
            <thead><tr><th>Nome</th><th>Tipo</th><th>Crítico</th><th>Sensível</th><th>Descrição</th></tr></thead>
            <tbody>{a.atributos.map((x) => <tr key={x.id}><td>{x.nome}</td><td>{x.tipo_dado}</td><td>{x.critico ? "Sim" : "Não"}</td><td>{x.sensivel ? "Sim" : "Não"}</td><td>{x.descricao}</td></tr>)}</tbody>
          </table></div>
        )}
        <form className="formulario" onSubmit={(e) => {
          e.preventDefault();
          void tentar(() => enviar(`/ativos/${a.id}/atributos`, atr), "Atributo adicionado.").then(() => setAtr({ ...atr, nome: "" }));
        }}>
          <Campo rotulo="Nome"><input required value={atr.nome} onChange={(e) => setAtr({ ...atr, nome: e.target.value })} /></Campo>
          <Campo rotulo="Tipo de dado"><input required value={atr.tipo_dado} onChange={(e) => setAtr({ ...atr, tipo_dado: e.target.value })} /></Campo>
          <label className="marcar"><input type="checkbox" checked={atr.critico} onChange={(e) => setAtr({ ...atr, critico: e.target.checked })} /> Crítico</label>
          <label className="marcar"><input type="checkbox" checked={atr.sensivel} onChange={(e) => setAtr({ ...atr, sensivel: e.target.checked })} /> Sensível</label>
          <div className="acoes"><button type="submit" className="primario">Adicionar atributo</button></div>
        </form>
      </Secao>

      <Secao titulo={`Versões (${a.versoes.length})`}>
        {a.versoes.length === 0 ? <p className="suave">Este ativo ainda não tem versões registradas.</p> : (
          <div className="rolagem"><table>
            <thead><tr><th className="num">Versão</th><th className="num">Linhas</th><th>Checksum</th><th>Processo</th><th>Parâmetros</th><th>Criada em</th></tr></thead>
            <tbody>{a.versoes.map((v) => (
              <tr key={v.id}><td className="num">{v.numero}</td><td className="num">{fNum(v.linhas)}</td><td>{v.checksum.slice(0, 10)}</td><td>{v.processo ?? "Fonte"}</td><td>{JSON.stringify(v.parametros)}</td><td>{fData(v.criado_em)}</td></tr>
            ))}</tbody>
          </table></div>
        )}
      </Secao>

      <Secao titulo="Histórico de alterações">
        <ul className="eventos">
          {a.historico.map((h) => (
            <li key={h.id}><span>{h.operacao === "INSERT" ? "Criado" : "Alterado"}</span><span className="suave">por {h.usuario}</span><span className="suave">{fData(h.em)}</span></li>
          ))}
        </ul>
      </Secao>
    </div>
  );
}

export default function Catalogo({ params }: { params: URLSearchParams }) {
  const [busca, setBusca] = useState("");
  const [tipo, setTipo] = useState("");
  const [camada, setCamada] = useState("");
  const [criando, setCriando] = useState(false);
  const responsaveis = useDados(() => pedir<Responsavel[]>("/responsaveis"), []);
  const consulta = new URLSearchParams({ busca, tipo, camada }).toString();
  const lista = useDados(() => pedir<AtivoResumo[]>(`/ativos?${consulta}`), [consulta]);
  const selecionado = Number(params.get("ativo")) || null;

  return (
    <>
      <div className="titulo-com-acao">
        <h1>Catálogo de ativos</h1>
        <button className="primario" onClick={() => setCriando(!criando)}>Cadastrar ativo</button>
      </div>
      {criando && responsaveis.dados && (
        <FormularioAtivo
          inicial={VAZIO}
          responsaveis={responsaveis.dados}
          aoSalvar={(id) => { setCriando(false); lista.recarregar(); irPara("catalogo", { ativo: id }); }}
          aoCancelar={() => setCriando(false)}
        />
      )}
      <form className="filtros" onSubmit={(e) => e.preventDefault()}>
        <Campo rotulo="Buscar"><input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome ou código" /></Campo>
        <Campo rotulo="Tipo"><select value={tipo} onChange={(e) => setTipo(e.target.value)}><option value="">Todos</option>{opcoes(TIPOS, ["processo", "regra", "atributo"])}</select></Campo>
        <Campo rotulo="Camada"><select value={camada} onChange={(e) => setCamada(e.target.value)}><option value="">Todas</option>{opcoes(CAMADAS)}</select></Campo>
      </form>
      <Estado erro={lista.erro} carregando={lista.carregando && !lista.dados} />
      <div className="catalogo">
        <div className="rolagem catalogo-lista">
          <table>
            <thead><tr><th>Ativo</th><th>Tipo</th><th className="num">Versão</th><th className="num">Auditável</th><th>Situação</th></tr></thead>
            <tbody>
              {lista.dados?.map((a) => (
                <tr key={a.id} className={a.id === selecionado ? "linha-ativa" : ""}>
                  <td><a href={caminho("catalogo", { ativo: a.id })}><strong>{a.codigo}</strong> {a.nome}</a></td>
                  <td>{TIPOS[a.tipo]}</td>
                  <td className="num">{a.versao_atual ?? ""}</td>
                  <td className="num">{a.iaa !== null ? fPct(a.iaa, 0) : ""}</td>
                  <td>{a.status === "obsoleto" ? "Obsoleto" : a.desatualizado_por ? <span className="selo atencao"><span aria-hidden="true">!</span> Desatualizado</span> : a.versao_atual ? "Em dia" : "Sem versão"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {lista.dados?.length === 0 && <p className="suave">Nenhum ativo corresponde a esses filtros.</p>}
        </div>
        {selecionado && lista.dados && responsaveis.dados ? (
          <Detalhe key={selecionado} id={selecionado} ativos={lista.dados} responsaveis={responsaveis.dados} aoMudar={lista.recarregar} />
        ) : (
          <p className="suave ficha-vazia">Selecione um ativo para ver metadados, proveniência, relações e versões.</p>
        )}
      </div>
    </>
  );
}
