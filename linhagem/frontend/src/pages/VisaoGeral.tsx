import { useState } from "react";
import { pedir, useDados } from "../api";
import GrafoVisual, { Legenda } from "../components/GrafoVisual";
import { Aviso, Estado, Selo } from "../components/Ui";
import { fData, fNum, fPct } from "../format";
import { caminho, irPara } from "../rota";
import { Criterio, Desatualizado, Execucao, Grafo, LinhaPainel, Metrica, NoGrafo, Painel } from "../types";

const FAIXAS: Record<string, string> = { alta: "Alta", media: "Média", baixa: "Baixa" };

function BarrasEvasao({ linhas }: { linhas: LinhaPainel[] }) {
  const maximo = Math.max(...linhas.map((l) => l.taxa_evasao), 0.01);
  return (
    <ul className="barras" aria-label="Taxa de evasão por curso">
      {linhas.map((l) => (
        <li key={l.cod_curso} tabIndex={0}>
          <span className="barra-rotulo">{l.curso}<small>{l.campus}</small></span>
          <span className="barra-trilho">
            <span className={`barra faixa-${l.faixa_risco}`} style={{ width: `${(l.taxa_evasao / maximo) * 100}%` }} />
          </span>
          <span className="barra-valor">{fPct(l.taxa_evasao)}</span>
          <span className="barra-faixa">{FAIXAS[l.faixa_risco]}</span>
          <span className="dica" role="tooltip">
            {fNum(l.evadidos)} evadidos de {fNum(l.alunos)} alunos. Faixa de risco {FAIXAS[l.faixa_risco].toLowerCase()}.
          </span>
        </li>
      ))}
    </ul>
  );
}

function valorMetrica(m: Metrica) {
  if (m.valor === null) return "Sem dados";
  if (m.unidade === "proporcao") return fPct(m.valor, 0);
  if (m.unidade === "ms") return `${m.valor.toLocaleString("pt-BR")} ms`;
  return `${m.valor.toLocaleString("pt-BR")} etapas`;
}

export default function VisaoGeral() {
  const [selecionado, setSelecionado] = useState<NoGrafo | null>(null);
  const dados = useDados(
    () =>
      Promise.all([
        pedir<Painel>("/painel/evasao"),
        pedir<Grafo>("/linhagem/grafo"),
        pedir<Metrica[]>("/metricas"),
        pedir<Criterio[]>("/metricas/criterios"),
        pedir<Execucao[]>("/execucoes?limite=6"),
        pedir<Desatualizado[]>("/desatualizados"),
      ]),
    [],
  );

  if (!dados.dados) return <Estado erro={dados.erro} carregando={dados.carregando} />;
  const [painel, grafo, metricas, criterios, execucoes, desatualizados] = dados.dados;
  const atendidos = criterios.filter((c) => c.atendido).length;
  const periodos = painel.definicao?.periodos_sem_matricula;

  return (
    <>
      <div className="cabeca-hero">
        <h1>De onde vem cada número do painel de evasão</h1>
        <p>
          {painel.versao ? (
            <>
              O painel está na versão {painel.versao.numero}, publicada em {fData(painel.versao.criado_em)}.
              {periodos !== undefined && ` Evasão considera ${periodos} período${periodos === 1 ? "" : "s"} sem matrícula.`}
            </>
          ) : (
            "O painel ainda não foi publicado. Execute o pipeline para gerar a primeira versão."
          )}
          {" "}Selecione um ativo para acender tudo o que vem antes e depois dele.
        </p>
      </div>

      {desatualizados.length > 0 && (
        <Aviso tipo="atencao">
          {desatualizados.length} ativos estão desatualizados por mudança em {[...new Set(desatualizados.map((d) => d.causa))].join(", ")}.{" "}
          <a href={caminho("pipeline")}>Executar o pipeline</a>
        </Aviso>
      )}

      <section className="palco-hero">
        <GrafoVisual ajustar grafo={grafo} selecionado={selecionado?.chave ?? null} aoSelecionar={setSelecionado} />
        <div className="palco-rodape">
          <Legenda />
          {selecionado?.classe === "ativo" && (
            <div className="acoes">
              <strong>{selecionado.nome}</strong>
              <button onClick={() => irPara("catalogo", { ativo: selecionado.id })}>Abrir no catálogo</button>
              <button onClick={() => irPara("grafo", { ativo: selecionado.id })}>Explorar no grafo</button>
              <button onClick={() => irPara("impacto", { ativo: selecionado.id })}>Analisar impacto</button>
            </div>
          )}
        </div>
      </section>

      <div className="duas-colunas">
        <section>
          <h2>Taxa de evasão por curso</h2>
          <BarrasEvasao linhas={painel.linhas} />
          <p className="suave pequena">
            Painel simulado. <a href={caminho("grafo", { ativo: painel.ativo.id, direcao: "ascendentes" })}>Ver de onde vieram estes números</a>
          </p>
        </section>
        <section>
          <h2>Critérios do Módulo 11: {atendidos} de {criterios.length} atendidos</h2>
          <ol className="criterios">
            {criterios.map((c) => (
              <li key={c.numero} className={c.atendido ? "feito" : "pendente"}>
                <span className="criterio-icone" aria-hidden="true">{c.atendido ? "✓" : "!"}</span>
                <span>{c.criterio}</span>
                <span className="criterio-conta">
                  <span className="sr-only">{c.atendido ? "Atendido: " : "Pendente: "}</span>
                  {c.atendidos}/{c.total}
                </span>
              </li>
            ))}
          </ol>
        </section>
      </div>

      <section>
        <h2>Métricas de linhagem</h2>
        <dl className="metricas">
          {metricas.map((m) => (
            <div key={m.sigla}>
              <dt><abbr title={m.nome}>{m.sigla}</abbr> <span>{m.descricao}</span></dt>
              <dd>
                {valorMetrica(m)}
                {m.denominador !== null && m.denominador > 0 && <small>{fNum(m.numerador)} de {fNum(m.denominador)}</small>}
              </dd>
            </div>
          ))}
        </dl>
      </section>

      <section>
        <h2>Últimas execuções</h2>
        <ul className="eventos">
          {execucoes.map((e) => (
            <li key={e.id}>
              <Selo valor={e.status} />
              <span>{e.processo_nome}</span>
              <span className="suave">por {e.executor}</span>
              <span className="suave">{fData(e.iniciada_em)}</span>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
