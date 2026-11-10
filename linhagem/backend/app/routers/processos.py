from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from .. import consultas, runner
from ..db import transacao

router = APIRouter(tags=["pipeline"])

_SELECT_EXECUCAO = """
    SELECT e.*, p.codigo AS processo, p.nome AS processo_nome, p.tipo AS processo_tipo,
           round(extract(epoch FROM e.finalizada_em - e.iniciada_em) * 1000)::bigint AS duracao_ms
    FROM linhagem.execucao e JOIN linhagem.processo p ON p.id = e.processo_id
"""


class ExecucaoEntrada(BaseModel):
    parametros: dict[str, Any] = Field(default_factory=dict)
    executor: str = Field(default="interface-web", min_length=1, max_length=80)


class PipelineEntrada(BaseModel):
    executor: str = Field(default="interface-web", min_length=1, max_length=80)
    a_partir_de: str | None = None


@router.get("/processos")
def listar_processos() -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute(
            """SELECT p.*, r.nome AS responsavel,
                   (SELECT array_agg(a.codigo ORDER BY a.codigo) FROM linhagem.processo_entrada x
                    JOIN linhagem.ativo a ON a.id = x.ativo_id WHERE x.processo_id = p.id) AS entradas,
                   (SELECT array_agg(a.codigo ORDER BY a.codigo) FROM linhagem.processo_saida x
                    JOIN linhagem.ativo a ON a.id = x.ativo_id WHERE x.processo_id = p.id) AS saidas,
                   u.status AS ultimo_status, u.finalizada_em AS ultima_execucao
               FROM linhagem.processo p
               LEFT JOIN linhagem.responsavel r ON r.id = p.responsavel_id
               LEFT JOIN LATERAL (
                   SELECT status, finalizada_em FROM linhagem.execucao e
                   WHERE e.processo_id = p.id ORDER BY e.iniciada_em DESC LIMIT 1
               ) u ON true
               ORDER BY p.ordem"""
        ).fetchall()


@router.get("/processos/{processo_id}")
def detalhar_processo(processo_id: int) -> dict[str, Any]:
    with transacao() as conn:
        processo = conn.execute("SELECT * FROM linhagem.processo WHERE id = %s", (processo_id,)).fetchone()
        if processo is None:
            raise HTTPException(404, "Processo não encontrado.")
        processo["regras"] = conn.execute(
            """SELECT r.* FROM linhagem.regra r JOIN linhagem.processo_regra x ON x.regra_id = r.id
               WHERE x.processo_id = %s ORDER BY r.codigo""",
            (processo_id,),
        ).fetchall()
    processo["sql"] = (runner.PIPELINE_DIR / processo["script"]).read_text(encoding="utf-8")
    return processo


@router.post("/processos/{processo_id}/executar")
def executar_processo(processo_id: int, dados: ExecucaoEntrada) -> dict[str, Any]:
    return runner.executar_processo(processo_id, dados.parametros, dados.executor)


@router.post("/pipeline/executar")
def executar_pipeline(dados: PipelineEntrada) -> list[dict[str, Any]]:
    return runner.executar_pipeline(dados.executor, dados.a_partir_de)


@router.get("/execucoes")
def listar_execucoes(limite: int = Query(default=50, ge=1, le=500)) -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute(_SELECT_EXECUCAO + " ORDER BY e.iniciada_em DESC LIMIT %s", (limite,)).fetchall()


@router.get("/execucoes/{execucao_id}")
def detalhar_execucao(execucao_id: int) -> dict[str, Any]:
    with transacao() as conn:
        execucao = conn.execute(_SELECT_EXECUCAO + " WHERE e.id = %s", (execucao_id,)).fetchone()
        if execucao is None:
            raise HTTPException(404, "Execução não encontrada.")
        for campo, tabela in (("entradas", "execucao_entrada"), ("saidas", "execucao_saida")):
            execucao[campo] = conn.execute(
                f"""SELECT v.id AS versao_id, a.id AS ativo_id, a.codigo, a.nome, v.numero, v.linhas, v.checksum
                    FROM linhagem.{tabela} x
                    JOIN linhagem.ativo_versao v ON v.id = x.ativo_versao_id
                    JOIN linhagem.ativo a ON a.id = v.ativo_id
                    WHERE x.execucao_id = %s ORDER BY a.codigo""",
                (execucao_id,),
            ).fetchall()
    return execucao


@router.post("/fontes/{ativo_id}/simular-atualizacao")
def simular_atualizacao(ativo_id: int) -> dict[str, Any]:
    return runner.simular_atualizacao(ativo_id)


@router.get("/desatualizados")
def listar_desatualizados() -> list[dict[str, Any]]:
    with transacao() as conn:
        return consultas.executar(conn, "desatualizados", {})["linhas"]
