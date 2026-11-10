import { useCallback, useEffect, useState } from "react";

export async function pedir<T>(caminho: string, opcoes?: RequestInit): Promise<T> {
  let resposta: Response;
  try {
    resposta = await fetch(`/api${caminho}`, {
      ...opcoes,
      headers: { "Content-Type": "application/json", ...opcoes?.headers },
    });
  } catch {
    throw new Error("A API não respondeu. Confira se o uvicorn está rodando na porta 8000.");
  }
  if (resposta.status === 204) return undefined as T;
  const corpo = await resposta.json().catch(() => null);
  if (!resposta.ok) {
    const detalhe = corpo?.detail;
    const mensagem =
      typeof detalhe === "string"
        ? detalhe
        : Array.isArray(detalhe)
          ? detalhe.map((d: { msg: string }) => d.msg).join("; ")
          : `A API respondeu com erro ${resposta.status}.`;
    throw new Error(mensagem);
  }
  return corpo as T;
}

export const enviar = <T,>(caminho: string, corpo: unknown, metodo = "POST") =>
  pedir<T>(caminho, { method: metodo, body: JSON.stringify(corpo) });

export function useDados<T>(carregar: () => Promise<T>, dependencias: unknown[]) {
  const [dados, setDados] = useState<T | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(true);
  const [versao, setVersao] = useState(0);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  const chamar = useCallback(carregar, dependencias);

  useEffect(() => {
    let vigente = true;
    setCarregando(true);
    chamar()
      .then((r) => {
        if (vigente) {
          setDados(r);
          setErro(null);
        }
      })
      .catch((e: Error) => vigente && setErro(e.message))
      .finally(() => vigente && setCarregando(false));
    return () => {
      vigente = false;
    };
  }, [chamar, versao]);

  return { dados, erro, carregando, recarregar: () => setVersao((v) => v + 1) };
}
