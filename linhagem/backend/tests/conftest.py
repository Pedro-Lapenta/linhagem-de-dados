"""Testes em um banco próprio, criado do zero, sem tocar nos dados da demonstração."""
import os
from pathlib import Path

import psycopg
import pytest

BASE = os.environ.get("TESTE_ADMIN_URL", "postgresql://linhagem:linhagem@127.0.0.1:5433/postgres")
BANCO = "linhagem_teste"
URL = BASE.rsplit("/", 1)[0] + f"/{BANCO}"
os.environ["DATABASE_URL"] = URL  # precisa vir antes de importar a aplicação

DB_DIR = Path(__file__).parents[2] / "db"


def _recriar_banco() -> None:
    with psycopg.connect(BASE, autocommit=True) as admin:
        admin.execute(f"DROP DATABASE IF EXISTS {BANCO} WITH (FORCE)")
        admin.execute(f"CREATE DATABASE {BANCO}")
    for arquivo in sorted(DB_DIR.glob("*.sql")):
        # Uma conexão por arquivo, como o entrypoint do Postgres faz.
        with psycopg.connect(URL, autocommit=True) as conn:
            conn.execute(arquivo.read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def cliente():
    _recriar_banco()
    from fastapi.testclient import TestClient

    from app.main import app
    from app.runner import executar_pipeline

    executar_pipeline("teste")
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def ids(cliente):
    return {a["codigo"]: a["id"] for a in cliente.get("/api/ativos").json()}


@pytest.fixture(scope="session")
def processos(cliente):
    return {p["codigo"]: p["id"] for p in cliente.get("/api/processos").json()}
