"""Catálogo das consultas recursivas. Cada execução alimenta as métricas TMR e TCLR."""
from __future__ import annotations

import time
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

from .db import carregar_sql

_ID = {"nome": "id", "tipo": "ativo", "rotulo": "Ativo"}
_PROF = {"nome": "profundidade", "tipo": "inteiro", "rotulo": "Profundidade máxima", "padrao": 30}

CONSULTAS: dict[str, dict[str, Any]] = {
    "ascendentes": {
        "titulo": "Ascendentes",
        "pergunta": "De onde este ativo veio?",
        "parametros": [_ID, _PROF],
    },
    "fontes_originais": {
        "titulo": "Fontes originais",
        "pergunta": "Quais fontes originaram este dashboard ou indicador?",
        "parametros": [_ID],
    },
    "descendentes": {
        "titulo": "Descendentes e impacto",
        "pergunta": "Quais ativos serão afetados se esta fonte mudar?",
        "parametros": [_ID],
    },
    "transformacoes": {
        "titulo": "Transformações em ordem",
        "pergunta": "Quais transformações e regras produziram este ativo?",
        "parametros": [_ID],
    },
    "linhagem_atributo": {
        "titulo": "Linhagem de atributo",
        "pergunta": "De quais colunas este atributo deriva?",
        "parametros": [{"nome": "atributo_id", "tipo": "atributo", "rotulo": "Atributo"}],
    },
    "proveniencia_versao": {
        "titulo": "Proveniência por versão",
        "pergunta": "Qual versão dos dados alimentou esta versão do relatório?",
        "parametros": [{"nome": "versao_id", "tipo": "versao", "rotulo": "Versão"}],
    },
    "caminhos": {
        "titulo": "Caminhos entre ativos",
        "pergunta": "Por onde o dado passa de um ativo até o outro?",
        "parametros": [
            {"nome": "origem", "tipo": "ativo", "rotulo": "Origem"},
            {"nome": "destino", "tipo": "ativo", "rotulo": "Destino"},
        ],
    },
    "grafo_em_data": {
        "titulo": "Grafo em uma data",
        "pergunta": "Como eram as dependências deste ativo naquela data?",
        "parametros": [
            _ID,
            {"nome": "em", "tipo": "data", "rotulo": "Data"},
            {"nome": "subir", "tipo": "booleano", "rotulo": "Ascendentes", "padrao": True},
            {"nome": "descer", "tipo": "booleano", "rotulo": "Descendentes", "padrao": True},
            _PROF,
        ],
    },
}

# Consultas de apoio: usam o mesmo mecanismo, mas não aparecem na tela de consultas.
_INTERNAS = {"desatualizados", "impacto_atributo"}


def executar(conn: psycopg.Connection, nome: str, parametros: dict[str, Any]) -> dict[str, Any]:
    if nome not in CONSULTAS and nome not in _INTERNAS:
        raise KeyError(nome)
    sql = carregar_sql(nome)
    inicio = time.perf_counter()
    cur = conn.execute(sql, parametros)
    linhas = cur.fetchall()
    duracao = (time.perf_counter() - inicio) * 1000
    colunas = [c.name for c in cur.description or []]
    if nome in CONSULTAS:
        conn.execute(
            "INSERT INTO linhagem.consulta_log (consulta, parametros, duracao_ms, linhas, respondida)"
            " VALUES (%s, %s, %s, %s, %s)",
            (nome, Jsonb(parametros), round(duracao, 3), len(linhas), bool(linhas)),
        )
    return {"colunas": colunas, "linhas": linhas, "sql": sql, "duracao_ms": round(duracao, 2)}
