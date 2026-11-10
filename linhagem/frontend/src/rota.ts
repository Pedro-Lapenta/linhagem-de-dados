import { useEffect, useState } from "react";

export type Pagina = "visao" | "catalogo" | "grafo" | "consultas" | "impacto" | "pipeline" | "mapa" | "auditoria";

const ler = () => {
  const [caminho, busca] = location.hash.replace(/^#\/?/, "").split("?");
  return { pagina: (caminho || "visao") as Pagina, params: new URLSearchParams(busca ?? "") };
};

export function useRota() {
  const [rota, setRota] = useState(ler);
  useEffect(() => {
    const aoMudar = () => setRota(ler());
    window.addEventListener("hashchange", aoMudar);
    return () => window.removeEventListener("hashchange", aoMudar);
  }, []);
  return rota;
}

export function caminho(pagina: Pagina, params?: Record<string, string | number>) {
  const busca = new URLSearchParams(Object.entries(params ?? {}).map(([k, v]) => [k, String(v)])).toString();
  return `#/${pagina}${busca ? `?${busca}` : ""}`;
}

export const irPara = (pagina: Pagina, params?: Record<string, string | number>) => {
  location.hash = caminho(pagina, params);
};
