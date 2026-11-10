from __future__ import annotations

from typing import Any, Literal

from fastapi import APIRouter, HTTPException, Query
from psycopg.types.json import Jsonb
from pydantic import BaseModel, Field

from .. import consultas
from ..db import carregar_sql, transacao

router = APIRouter(tags=["governança"])


class ImpactoEntrada(BaseModel):
    ativo_id: int
    atributo_id: int | None = None
    mudanca: str = Field(min_length=3, max_length=400)
    tipo_impacto: Literal["estrutural", "semantico", "qualidade", "consumo"]
    acao: str = Field(min_length=3, max_length=400)
    responsavel_id: int | None = None


class ImpactoStatus(BaseModel):
    status: Literal["aberto", "tratado", "encerrado"]


_ORDEM_SEVERIDADE = ["baixa", "media", "alta", "critica"]


def _alcance(conn, ativo_id: int, atributo_id: int | None) -> dict[str, Any]:
    if atributo_id is not None:
        return consultas.executar(conn, "impacto_atributo", {"atributo_id": atributo_id})
    return consultas.executar(conn, "descendentes", {"id": ativo_id})


@router.get("/impacto/calcular")
def calcular_impacto(ativo_id: int, atributo_id: int | None = None) -> dict[str, Any]:
    with transacao() as conn:
        return _alcance(conn, ativo_id, atributo_id)


@router.get("/impacto")
def listar_impactos() -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute(
            """SELECT i.*, a.codigo, a.nome, r.nome AS responsavel
               FROM linhagem.analise_impacto i
               JOIN linhagem.ativo a ON a.id = i.ativo_id
               LEFT JOIN linhagem.responsavel r ON r.id = i.responsavel_id
               ORDER BY i.criada_em DESC"""
        ).fetchall()


@router.post("/impacto", status_code=201)
def salvar_impacto(dados: ImpactoEntrada) -> dict[str, Any]:
    with transacao() as conn:
        linhas = _alcance(conn, dados.ativo_id, dados.atributo_id)["linhas"]
        severidade = max(
            (l["severidade"] for l in linhas), key=_ORDEM_SEVERIDADE.index, default="baixa"
        )
        return conn.execute(
            """INSERT INTO linhagem.analise_impacto
                   (ativo_id, mudanca, tipo_impacto, severidade, acao, responsavel_id, ativos)
               VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING *""",
            (
                dados.ativo_id, dados.mudanca, dados.tipo_impacto, severidade, dados.acao, dados.responsavel_id,
                Jsonb([{"codigo": l.get("atributo") or l["codigo"], "severidade": l["severidade"], "acao": l["acao"]} for l in linhas]),
            ),
        ).fetchone()


@router.patch("/impacto/{impacto_id}")
def atualizar_status_impacto(impacto_id: int, dados: ImpactoStatus) -> dict[str, Any]:
    with transacao() as conn:
        linha = conn.execute(
            "UPDATE linhagem.analise_impacto SET status = %s WHERE id = %s RETURNING *",
            (dados.status, impacto_id),
        ).fetchone()
    if linha is None:
        raise HTTPException(404, "Análise não encontrada.")
    return linha


@router.get("/metricas")
def metricas() -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute("SELECT * FROM linhagem.vw_metricas").fetchall()


@router.get("/metricas/criterios")
def criterios() -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute("SELECT * FROM linhagem.vw_criterios").fetchall()


@router.get("/auditoria")
def auditoria(limite: int = Query(default=100, ge=1, le=500), tabela: str | None = None) -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute(
            """SELECT * FROM linhagem.auditoria
               WHERE %(tabela)s::text IS NULL OR tabela = %(tabela)s
               ORDER BY em DESC, id DESC LIMIT %(limite)s""",
            {"tabela": tabela or None, "limite": limite},
        ).fetchall()


@router.get("/mapa/fontes")
def mapa_fontes() -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute(
            """SELECT a.id, a.codigo, a.nome, a.status, a.sensibilidade, p.sistema_origem, p.instituicao,
                      p.cidade, p.campus, p.latitude::float AS latitude, p.longitude::float AS longitude,
                      p.periodicidade, p.data_extracao, p.demonstracao,
                      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', x.id, 'codigo', x.codigo, 'nome', x.nome, 'tipo', x.tipo)
                                                 ORDER BY x.codigo), '[]')
                       FROM (SELECT DISTINCT at.id, at.codigo, at.nome, at.tipo
                             FROM linhagem.vw_fechamento f
                             JOIN linhagem.ativo at ON at.id = f.descendente_id
                             WHERE f.ascendente_id = a.id) x) AS dependentes
               FROM linhagem.ativo a
               JOIN linhagem.proveniencia p ON p.ativo_id = a.id
               WHERE p.latitude IS NOT NULL AND p.longitude IS NOT NULL
               ORDER BY a.codigo"""
        ).fetchall()


@router.get("/painel/evasao")
def painel_evasao() -> dict[str, Any]:
    with transacao() as conn:
        ativo = conn.execute("SELECT id, codigo, nome FROM linhagem.ativo WHERE codigo = 'D-EVA'").fetchone()
        versao = conn.execute(
            """SELECT v.id, v.numero, v.parametros, v.criado_em, e.executor
               FROM linhagem.ativo_versao v LEFT JOIN linhagem.execucao e ON e.id = v.execucao_id
               WHERE v.ativo_id = %s ORDER BY v.numero DESC LIMIT 1""",
            (ativo["id"],),
        ).fetchone()
        if versao is None:
            return {"ativo": ativo, "versao": None, "definicao": None, "linhas": []}
        # A definição exibida vem da proveniência desta versão, não da última execução:
        # o data mart pode ter sido refeito sem que o painel tenha sido republicado.
        cadeia = conn.execute(carregar_sql("proveniencia_versao"), {"versao_id": versao["id"]}).fetchall()
        definicao = next((l["parametros"] for l in cadeia if l["codigo"] == "M-PERM"), None)
        linhas = conn.execute(
            """SELECT cod_curso, curso, campus, alunos, evadidos, taxa_evasao, faixa_risco
               FROM mart.painel_evasao ORDER BY taxa_evasao DESC, cod_curso"""
        ).fetchall()
    return {"ativo": ativo, "versao": versao, "definicao": definicao, "linhas": linhas}
