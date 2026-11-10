import { ReactNode } from "react";
import { fCelula, rotuloColuna } from "../format";
import { Linha } from "../types";

export function Estado({ erro, carregando }: { erro: string | null; carregando: boolean }) {
  if (erro) return <p className="aviso erro" role="alert">{erro}</p>;
  if (carregando) return <p className="suave" role="status">Carregando…</p>;
  return null;
}

export function Aviso({ tipo = "info", children }: { tipo?: "info" | "erro" | "ok" | "atencao"; children: ReactNode }) {
  return <div className={`aviso ${tipo}`} role={tipo === "erro" ? "alert" : "status"}>{children}</div>;
}

const STATUS: Record<string, [string, string]> = {
  sucesso: ["ok", "Sucesso"], parcial: ["atencao", "Parcial"], falha: ["erro", "Falha"], em_execucao: ["info", "Em execução"],
  critica: ["erro", "Crítica"], alta: ["serio", "Alta"], media: ["atencao", "Média"], baixa: ["ok", "Baixa"],
  aberto: ["atencao", "Aberto"], tratado: ["info", "Tratado"], encerrado: ["ok", "Encerrado"],
};

const ICONES: Record<string, string> = { ok: "✓", atencao: "!", erro: "✕", serio: "▲", info: "•" };

export function Selo({ valor }: { valor: string | null | undefined }) {
  if (!valor) return <span className="suave">Nunca executado</span>;
  const [classe, rotulo] = STATUS[valor] ?? ["info", valor];
  return (
    <span className={`selo ${classe}`}>
      <span aria-hidden="true">{ICONES[classe]}</span> {rotulo}
    </span>
  );
}

export function Campo({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return (
    <label className="campo">
      <span>{rotulo}</span>
      {children}
    </label>
  );
}

export function TabelaDados({ colunas, linhas }: { colunas: string[]; linhas: Linha[] }) {
  if (!linhas.length) return <p className="suave">A consulta não retornou linhas.</p>;
  return (
    <div className="rolagem">
      <table>
        <thead>
          <tr>{colunas.map((c) => <th key={c} scope="col">{rotuloColuna(c)}</th>)}</tr>
        </thead>
        <tbody>
          {linhas.map((linha, i) => (
            <tr key={i}>
              {colunas.map((c) => (
                <td key={c} className={typeof linha[c] === "number" ? "num" : undefined}>
                  {c === "severidade" ? <Selo valor={String(linha[c])} /> : fCelula(linha[c])}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
