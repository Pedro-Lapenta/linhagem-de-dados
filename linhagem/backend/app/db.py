"""Acesso ao PostgreSQL com psycopg 3 e SQL puro."""
from __future__ import annotations

import os
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import psycopg
from psycopg.rows import dict_row
from psycopg.types.numeric import FloatLoader
from psycopg_pool import ConnectionPool

DSN = os.environ.get("DATABASE_URL", "postgresql://linhagem:linhagem@127.0.0.1:5433/linhagem")
SQL_DIR = Path(__file__).parent / "sql"

# Sem isto, numeric vira Decimal e a API o serializa como texto em vez de número JSON.
psycopg.adapters.register_loader("numeric", FloatLoader)

pool = ConnectionPool(DSN, min_size=1, max_size=10, open=False, kwargs={"row_factory": dict_row})


@contextmanager
def transacao(usuario: str = "interface-web") -> Iterator[psycopg.Connection]:
    """Abre uma transação; confirma ao sair e desfaz em caso de exceção."""
    with pool.connection() as conn:
        # is_local = true: o usuário vale só nesta transação, lido pela trigger de auditoria.
        conn.execute("SELECT set_config('app.usuario', %s, true)", (usuario,))
        yield conn


def carregar_sql(nome: str) -> str:
    return (SQL_DIR / f"{nome}.sql").read_text(encoding="utf-8")
