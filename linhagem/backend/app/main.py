from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .db import pool
from .routers import ativos, governanca, linhagem, processos
from .runner import ErroExecucao, ParametroInvalido


@asynccontextmanager
async def ciclo_de_vida(_: FastAPI) -> AsyncIterator[None]:
    pool.open(wait=True)
    yield
    pool.close()


app = FastAPI(title="UnespDataLens-RM: Linhagem de Dados", lifespan=ciclo_de_vida)

for router in (ativos.router, processos.router, linhagem.router, governanca.router):
    app.include_router(router, prefix="/api")


@app.exception_handler(psycopg.Error)
async def erro_banco(_: Request, exc: psycopg.Error) -> JSONResponse:
    mensagem = exc.diag.message_primary or "Erro no banco de dados."
    if exc.sqlstate == "LN001":
        return JSONResponse({"detail": mensagem}, status_code=409)
    if exc.sqlstate == "23505":
        return JSONResponse({"detail": "Já existe um registro com esses dados."}, status_code=409)
    if exc.sqlstate == "23503":
        return JSONResponse({"detail": "O registro referencia ou é referenciado por outro."}, status_code=409)
    if exc.sqlstate in ("23514", "23502", "22P02", "22007", "22008"):
        return JSONResponse({"detail": f"Dados inválidos: {mensagem}"}, status_code=422)
    return JSONResponse({"detail": mensagem}, status_code=500)


@app.exception_handler(ParametroInvalido)
async def parametro_invalido(_: Request, exc: ParametroInvalido) -> JSONResponse:
    return JSONResponse({"detail": str(exc)}, status_code=422)


@app.exception_handler(ErroExecucao)
async def erro_execucao(_: Request, exc: ErroExecucao) -> JSONResponse:
    # Falha prevista do pipeline: a execução fica registrada e é devolvida ao cliente.
    return JSONResponse(
        {"detail": str(exc).splitlines()[-1], "execucao_id": exc.execucao["id"]},
        status_code=422,
    )


@app.exception_handler(KeyError)
async def nao_encontrado(_: Request, exc: KeyError) -> JSONResponse:
    return JSONResponse({"detail": f"Registro não encontrado: {exc.args[0]}"}, status_code=404)
