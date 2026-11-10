import { useState } from "react";
import { pedir, useDados } from "../api";
import { Campo, Estado } from "../components/Ui";
import { fCelula, fData } from "../format";
import { RegistroAuditoria } from "../types";

function Mudancas({ r }: { r: RegistroAuditoria }) {
  const chaves = Object.keys({ ...r.antes, ...r.depois }).filter(
    (k) => k !== "atualizado_em" && JSON.stringify(r.antes?.[k]) !== JSON.stringify(r.depois?.[k]),
  );
  if (r.operacao === "INSERT") return <span className="suave">Criado: {String(r.depois?.codigo ?? r.depois?.nome ?? r.depois?.tipo_relacao ?? "")}</span>;
  return (
    <ul className="mudancas">
      {chaves.map((k) => (
        <li key={k}><strong>{k}</strong>: <del>{fCelula(r.antes?.[k]) || "vazio"}</del> <ins>{fCelula(r.depois?.[k]) || "vazio"}</ins></li>
      ))}
    </ul>
  );
}

const OPERACOES: Record<string, string> = { INSERT: "Criação", UPDATE: "Alteração", DELETE: "Exclusão" };

export default function Auditoria() {
  const [tabela, setTabela] = useState("");
  const dados = useDados(() => pedir<RegistroAuditoria[]>(`/auditoria?limite=200${tabela ? `&tabela=${tabela}` : ""}`), [tabela]);
  return (
    <>
      <h1>Auditoria</h1>
      <form className="filtros" onSubmit={(e) => e.preventDefault()}>
        <Campo rotulo="Tabela">
          <select value={tabela} onChange={(e) => setTabela(e.target.value)}>
            <option value="">Todas</option>
            <option value="ativo">Ativos</option>
            <option value="atributo">Atributos</option>
            <option value="dependencia">Dependências</option>
            <option value="processo">Processos</option>
            <option value="regra">Regras</option>
          </select>
        </Campo>
      </form>
      <Estado erro={dados.erro} carregando={dados.carregando && !dados.dados} />
      <div className="rolagem">
        <table>
          <thead><tr><th>Quando</th><th>Operação</th><th>Tabela</th><th>Registro</th><th>Usuário</th><th>O que mudou</th></tr></thead>
          <tbody>
            {dados.dados?.map((r) => (
              <tr key={r.id}>
                <td>{fData(r.em)}</td>
                <td>{OPERACOES[r.operacao]}</td>
                <td>{r.tabela}</td>
                <td className="num">{r.registro_id}</td>
                <td>{r.usuario}</td>
                <td><Mudancas r={r} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
