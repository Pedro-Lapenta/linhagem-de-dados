from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, Query

from .. import consultas
from ..db import carregar_sql, transacao

router = APIRouter(tags=["linhagem"])

_TIPOS_NUMERICOS = {"ativo", "atributo", "versao", "inteiro"}


def _converter(definicao: dict[str, Any], bruto: dict[str, Any]) -> dict[str, Any]:
    params: dict[str, Any] = {}
    for campo in definicao["parametros"]:
        nome = campo["nome"]
        valor = bruto.get(nome, campo.get("padrao"))
        if campo["tipo"] == "data" and valor in (None, ""):
            valor = datetime.now(timezone.utc).isoformat()
        if valor in (None, ""):
            raise HTTPException(422, f"Informe o parâmetro {campo['rotulo']}.")
        if campo["tipo"] in _TIPOS_NUMERICOS:
            try:
                valor = int(valor)
            except (TypeError, ValueError):
                raise HTTPException(422, f"{campo['rotulo']} deve ser um número inteiro.") from None
        params[nome] = valor
    return params


def _consultar(nome: str, params: dict[str, Any]) -> dict[str, Any]:
    with transacao() as conn:
        return consultas.executar(conn, nome, params)


@router.get("/consultas")
def listar_consultas() -> list[dict[str, Any]]:
    return [{"id": chave, **valor} for chave, valor in consultas.CONSULTAS.items()]


@router.post("/consultas/{consulta}/executar")
def executar_consulta(consulta: str, parametros: dict[str, Any]) -> dict[str, Any]:
    definicao = consultas.CONSULTAS.get(consulta)
    if definicao is None:
        raise HTTPException(404, "Consulta não encontrada.")
    return _consultar(consulta, _converter(definicao, parametros))


@router.get("/linhagem/caminho")
def caminho(origem: int, destino: int) -> dict[str, Any]:
    return _consultar("caminhos", {"origem": origem, "destino": destino})


@router.get("/linhagem/{ativo_id}/ascendentes")
def ascendentes(ativo_id: int, profundidade: int = Query(default=30, ge=1, le=100)) -> dict[str, Any]:
    return _consultar("ascendentes", {"id": ativo_id, "profundidade": profundidade})


@router.get("/linhagem/{ativo_id}/descendentes")
def descendentes(ativo_id: int) -> dict[str, Any]:
    return _consultar("descendentes", {"id": ativo_id})


@router.get("/linhagem/{ativo_id}/fontes")
def fontes(ativo_id: int) -> dict[str, Any]:
    return _consultar("fontes_originais", {"id": ativo_id})


@router.get("/linhagem/{ativo_id}/transformacoes")
def transformacoes(ativo_id: int) -> dict[str, Any]:
    return _consultar("transformacoes", {"id": ativo_id})


@router.get("/atributos/{atributo_id}/linhagem")
def linhagem_atributo(atributo_id: int) -> dict[str, Any]:
    return _consultar("linhagem_atributo", {"atributo_id": atributo_id})


@router.get("/versoes/{versao_id}/proveniencia")
def proveniencia_versao(versao_id: int) -> dict[str, Any]:
    return _consultar("proveniencia_versao", {"versao_id": versao_id})


def _montar_grafo(conn, arestas: list[dict[str, Any]], foco: int | None, detalhe: str) -> dict[str, Any]:
    ids = {a["origem_id"] for a in arestas} | {a["destino_id"] for a in arestas}
    if foco is not None:
        ids.add(foco)
    ativos = conn.execute(
        """SELECT id, codigo, nome, tipo, camada, critico, status
           FROM linhagem.ativo WHERE id = ANY(%s)""",
        (list(ids),),
    ).fetchall()
    desatualizados = {d["ativo_id"] for d in consultas.executar(conn, "desatualizados", {})["linhas"]}
    nos: dict[str, dict[str, Any]] = {
        f"a{a['id']}": {**a, "chave": f"a{a['id']}", "classe": "ativo", "desatualizado": a["id"] in desatualizados}
        for a in ativos
    }
    saida: list[dict[str, Any]] = []

    def ligar(origem: str, destino: str, relacao: str, base: dict[str, Any]) -> None:
        saida.append({"origem": origem, "destino": destino, "tipo_relacao": relacao,
                      "processo_id": base.get("processo_id"), "evidencia": base.get("evidencia"),
                      "vigente_de": base.get("vigente_de"), "vigente_ate": base.get("vigente_ate")})

    if detalhe == "ativos":
        for aresta in arestas:
            ligar(f"a{aresta['origem_id']}", f"a{aresta['destino_id']}", aresta["tipo_relacao"], aresta)
        return {"nos": list(nos.values()), "arestas": saida}

    processos_ids = {a["processo_id"] for a in arestas if a["processo_id"]}
    for p in conn.execute(
        "SELECT id, codigo, nome, tipo FROM linhagem.processo WHERE id = ANY(%s)", (list(processos_ids),)
    ).fetchall():
        nos[f"p{p['id']}"] = {**p, "chave": f"p{p['id']}", "classe": "processo", "tipo": "processo", "processo_tipo": p["tipo"]}
    vistos: set[tuple[str, str]] = set()
    for aresta in arestas:
        origem, destino = f"a{aresta['origem_id']}", f"a{aresta['destino_id']}"
        if not aresta["processo_id"]:
            ligar(origem, destino, aresta["tipo_relacao"], aresta)
            continue
        processo = f"p{aresta['processo_id']}"
        for de, para, relacao in ((origem, processo, "foi_transformado_por"), (processo, destino, "gerou")):
            if (de, para) not in vistos:
                vistos.add((de, para))
                ligar(de, para, relacao, aresta)
    for r in conn.execute(
        """SELECT r.id, r.codigo, r.nome, r.tipo, r.expressao, x.processo_id
           FROM linhagem.regra r JOIN linhagem.processo_regra x ON x.regra_id = r.id
           WHERE x.processo_id = ANY(%s)""",
        (list(processos_ids),),
    ).fetchall():
        chave = f"r{r['id']}"
        nos[chave] = {"id": r["id"], "chave": chave, "codigo": r["codigo"], "nome": r["nome"],
                      "classe": "regra", "tipo": "regra", "expressao": r["expressao"]}
        relacao = "validou" if r["tipo"] == "validacao" else "depende_de"
        ligar(chave, f"p{r['processo_id']}", relacao, {"processo_id": r["processo_id"]})
    return {"nos": list(nos.values()), "arestas": saida}


@router.get("/linhagem/grafo")
def grafo_completo(em: datetime | None = None, detalhe: Literal["ativos", "completo"] = "ativos") -> dict[str, Any]:
    momento = em or datetime.now(timezone.utc)
    with transacao() as conn:
        arestas = conn.execute(
            """SELECT * FROM linhagem.dependencia
               WHERE vigente_de <= %(em)s AND (vigente_ate IS NULL OR vigente_ate > %(em)s)""",
            {"em": momento},
        ).fetchall()
        return _montar_grafo(conn, arestas, None, detalhe)


@router.get("/linhagem/{ativo_id}/grafo")
def grafo_do_ativo(
    ativo_id: int,
    direcao: Literal["ambos", "ascendentes", "descendentes"] = "ambos",
    profundidade: int = Query(default=30, ge=1, le=100),
    em: datetime | None = None,
    detalhe: Literal["ativos", "completo"] = "ativos",
) -> dict[str, Any]:
    params = {
        "id": ativo_id,
        "em": em or datetime.now(timezone.utc),
        "subir": direcao != "descendentes",
        "descer": direcao != "ascendentes",
        "profundidade": profundidade,
    }
    with transacao() as conn:
        if conn.execute("SELECT 1 FROM linhagem.ativo WHERE id = %s", (ativo_id,)).fetchone() is None:
            raise HTTPException(404, "Ativo não encontrado.")
        resultado = conn.execute(carregar_sql("grafo_em_data"), params).fetchall()
        return {**_montar_grafo(conn, resultado, ativo_id, detalhe), "foco": f"a{ativo_id}"}


@router.get("/atributos/{atributo_id}/grafo")
def grafo_do_atributo(atributo_id: int) -> dict[str, Any]:
    with transacao() as conn:
        atributo = conn.execute(
            """SELECT at.id, at.nome, at.critico, a.codigo, a.tipo
               FROM linhagem.atributo at JOIN linhagem.ativo a ON a.id = at.ativo_id WHERE at.id = %s""",
            (atributo_id,),
        ).fetchone()
        if atributo is None:
            raise HTTPException(404, "Atributo não encontrado.")
        linhas = consultas.executar(conn, "linhagem_atributo", {"atributo_id": atributo_id})["linhas"]
    nos = {
        f"c{atributo_id}": {"id": atributo_id, "chave": f"c{atributo_id}", "classe": "atributo", "tipo": "atributo",
                            "codigo": f"{atributo['codigo']}.{atributo['nome']}", "nome": atributo["nome"]}
    }
    arestas = []
    for linha in linhas:
        for chave, rotulo in ((linha["atributo_id"], linha["atributo_origem"]), (linha["deriva_id"], linha["atributo_derivado"])):
            nos[f"c{chave}"] = {"id": chave, "chave": f"c{chave}", "classe": "atributo", "tipo": "atributo",
                                "codigo": rotulo, "nome": rotulo.split(".", 1)[1]}
        arestas.append({"origem": f"c{linha['atributo_id']}", "destino": f"c{linha['deriva_id']}",
                        "tipo_relacao": "derivou_de", "processo_id": None, "evidencia": linha["expressao"]})
    return {"nos": list(nos.values()), "arestas": arestas, "foco": f"c{atributo_id}"}
