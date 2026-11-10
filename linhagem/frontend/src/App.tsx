import Auditoria from "./pages/Auditoria";
import Catalogo from "./pages/Catalogo";
import Consultas from "./pages/Consultas";
import GrafoPagina from "./pages/GrafoPagina";
import Impacto from "./pages/Impacto";
import Mapa from "./pages/Mapa";
import Pipeline from "./pages/Pipeline";
import VisaoGeral from "./pages/VisaoGeral";
import { caminho, Pagina, useRota } from "./rota";

const ITENS: { pagina: Pagina; rotulo: string }[] = [
  { pagina: "visao", rotulo: "Visão geral" },
  { pagina: "grafo", rotulo: "Grafo de linhagem" },
  { pagina: "catalogo", rotulo: "Catálogo" },
  { pagina: "consultas", rotulo: "Consultas recursivas" },
  { pagina: "impacto", rotulo: "Análise de impacto" },
  { pagina: "pipeline", rotulo: "Pipeline" },
  { pagina: "mapa", rotulo: "Mapa das fontes" },
  { pagina: "auditoria", rotulo: "Auditoria" },
];

export default function App() {
  const { pagina, params } = useRota();
  return (
    <div className="app">
      <header className="lateral">
        <a className="marca" href={caminho("visao")}>
          <strong>Linhagem de Dados</strong>
          <span>UnespDataLens-RM, Módulo 11</span>
        </a>
        <nav aria-label="Principal">
          {ITENS.map((item) => (
            <a key={item.pagina} href={caminho(item.pagina)} aria-current={pagina === item.pagina ? "page" : undefined}>
              {item.rotulo}
            </a>
          ))}
        </nav>
        <p className="nota-lateral">Dados simulados para demonstração.</p>
      </header>
      <main className="conteudo">
        {pagina === "visao" && <VisaoGeral />}
        {/* A key recria a tela quando a URL aponta para outro ativo. */}
        {pagina === "grafo" && <GrafoPagina key={params.toString()} params={params} />}
        {pagina === "catalogo" && <Catalogo params={params} />}
        {pagina === "consultas" && <Consultas />}
        {pagina === "impacto" && <Impacto key={params.toString()} params={params} />}
        {pagina === "pipeline" && <Pipeline />}
        {pagina === "mapa" && <Mapa />}
        {pagina === "auditoria" && <Auditoria />}
      </main>
    </div>
  );
}
