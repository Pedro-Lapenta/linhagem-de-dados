import L from "leaflet";
import { useEffect, useRef, useState } from "react";
import { pedir, useDados } from "../api";
import { Estado } from "../components/Ui";
import { fData, TIPOS } from "../format";
import { caminho } from "../rota";
import { FonteMapa } from "../types";

export default function Mapa() {
  const dados = useDados(() => pedir<FonteMapa[]>("/mapa/fontes"), []);
  const [fonte, setFonte] = useState<FonteMapa | null>(null);
  const elemento = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!elemento.current || !dados.dados?.length) return;
    const mapa = L.map(elemento.current);
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 18,
      attribution: "&copy; colaboradores do OpenStreetMap",
    }).addTo(mapa);
    const pontos = dados.dados.map((f) => {
      const obsoleta = f.status === "obsoleto";
      const marcador = L.circleMarker([f.latitude, f.longitude], {
        radius: 7 + Math.sqrt(f.dependentes.length) * 2.2,
        color: "#ffffff",
        weight: 2,
        fillColor: obsoleta ? "#8493a3" : "#003b71",
        fillOpacity: 0.92,
      }).addTo(mapa);
      marcador.bindTooltip(`${f.codigo}: ${f.cidade ?? ""}`);
      marcador.on("click", () => setFonte(f));
      return [f.latitude, f.longitude] as [number, number];
    });
    mapa.fitBounds(L.latLngBounds(pontos).pad(0.25));
    return () => {
      mapa.remove();
    };
  }, [dados.dados]);

  return (
    <>
      <h1>Mapa das fontes</h1>
      <p className="suave">Cada círculo é um sistema de origem, maior quanto mais ativos dependem dele. As localizações são fictícias.</p>
      <Estado erro={dados.erro} carregando={dados.carregando && !dados.dados} />
      <div className="mapa-area">
        <div ref={elemento} className="mapa" role="application" aria-label="Mapa com a origem das fontes de dados" />
        <aside className="mapa-painel">
          {!fonte && (
            <ul className="lista-fontes">
              {dados.dados?.map((f) => (
                <li key={f.id}><button onClick={() => setFonte(f)}><strong>{f.codigo}</strong> {f.nome}<span>{f.cidade}</span></button></li>
              ))}
            </ul>
          )}
          {fonte && (
            <>
              <button className="voltar" onClick={() => setFonte(null)}>Ver todas as fontes</button>
              <h2>{fonte.nome}</h2>
              <dl className="ficha">
                <dt>Sistema</dt><dd>{fonte.sistema_origem}</dd>
                <dt>Local</dt><dd>{[...new Set([fonte.cidade, fonte.campus].filter(Boolean))].join(", ")}</dd>
                <dt>Periodicidade</dt><dd>{fonte.periodicidade}</dd>
                <dt>Extração</dt><dd>{fData(fonte.data_extracao)}</dd>
                <dt>Situação</dt><dd>{fonte.status === "obsoleto" ? "Obsoleta" : "Em uso"}</dd>
              </dl>
              <p className="acoes">
                <a className="botao" href={caminho("catalogo", { ativo: fonte.id })}>Abrir no catálogo</a>
                <a className="botao" href={caminho("impacto", { ativo: fonte.id })}>Analisar impacto</a>
              </p>
              <h3>{fonte.dependentes.length} ativos dependem desta fonte</h3>
              <ul className="dependentes">
                {fonte.dependentes.map((d) => (
                  <li key={d.id}><a href={caminho("grafo", { ativo: d.id })}>{d.codigo}</a> {TIPOS[d.tipo]}</li>
                ))}
              </ul>
            </>
          )}
        </aside>
      </div>
    </>
  );
}
