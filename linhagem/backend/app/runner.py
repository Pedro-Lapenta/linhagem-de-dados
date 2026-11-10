"""Executa o pipeline e grava a linhagem de cada execução.

A execução nasce em uma conexão autocommit própria. Assim, quando o trabalho sofre
rollback, o registro da falha e o log sobrevivem.
"""
from __future__ import annotations

import argparse
import hashlib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg import sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from .db import DSN

PIPELINE_DIR = Path(__file__).parent.parent / "pipeline"
LIMITE_SNAPSHOT = 200
_LOCK_PIPELINE = 727_001

_FAIXAS = {
    "limite_frequencia": (0, 100),
    "min_completude": (0, 1),
    "periodos_sem_matricula": (1, 7),
}

_ATUALIZACOES = {
    "F-MAT": """UPDATE fontes.matricula SET situacao = 'CANCELADO' WHERE ctid IN (
        SELECT ctid FROM fontes.matricula
        WHERE ano = 2024 AND semestre = 2 AND upper(situacao) <> 'CANCELADO'
        ORDER BY random() LIMIT 40)""",
    "F-NOT": """UPDATE fontes.notas SET nota_final = least(10, nota_final + 0.5) WHERE ctid IN (
        SELECT ctid FROM fontes.notas WHERE nota_final BETWEEN 0 AND 9.5 ORDER BY random() LIMIT 200)""",
    "F-FRE": """UPDATE fontes.frequencia SET percentual = least(100, percentual + 2) WHERE ctid IN (
        SELECT ctid FROM fontes.frequencia WHERE percentual <= 98 ORDER BY random() LIMIT 200)""",
    "F-AVA": """UPDATE fontes.ava SET acessos = acessos + 5 WHERE ctid IN (
        SELECT ctid FROM fontes.ava ORDER BY random() LIMIT 200)""",
    "F-SOC": """UPDATE fontes.socioeconomico SET trabalha = NOT trabalha WHERE ctid IN (
        SELECT ctid FROM fontes.socioeconomico ORDER BY random() LIMIT 30)""",
}


class ParametroInvalido(ValueError):
    pass


class ErroExecucao(RuntimeError):
    def __init__(self, execucao: dict[str, Any]):
        super().__init__(execucao.get("log") or "Falha na execução")
        self.execucao = execucao


def _agora() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _tabela(localizacao: str) -> sql.Identifier:
    return sql.Identifier(*localizacao.split(".", 1))


def validar_parametros(padrao: dict[str, Any], informados: dict[str, Any] | None) -> dict[str, Any]:
    """Aceita só os parâmetros declarados pelo processo, no tipo e na faixa esperados."""
    informados = informados or {}
    desconhecidos = set(informados) - set(padrao)
    if desconhecidos:
        raise ParametroInvalido(f"Parâmetros desconhecidos: {', '.join(sorted(desconhecidos))}")
    finais = dict(padrao)
    for nome, valor in informados.items():
        try:
            finais[nome] = type(padrao[nome])(valor)
        except (TypeError, ValueError) as exc:
            raise ParametroInvalido(f"Valor inválido para {nome}: {valor!r}") from exc
    for nome, valor in finais.items():
        minimo, maximo = _FAIXAS.get(nome, (float("-inf"), float("inf")))
        if not minimo <= valor <= maximo:
            raise ParametroInvalido(f"{nome} deve estar entre {minimo} e {maximo}")
    return finais


def _medir(conn: psycopg.Connection, localizacao: str) -> dict[str, Any]:
    tabela = _tabela(localizacao)
    medida = conn.execute(
        sql.SQL(
            """SELECT count(*) AS linhas,
                      md5(COALESCE(string_agg(t::text, E'\\n' ORDER BY t::text COLLATE "C"), '')) AS checksum
               FROM {} t"""
        ).format(tabela)
    ).fetchone()
    esquema_nome, tabela_nome = localizacao.split(".", 1)
    colunas = conn.execute(
        """SELECT column_name AS nome, data_type AS tipo
           FROM information_schema.columns
           WHERE table_schema = %s AND table_name = %s
           ORDER BY ordinal_position""",
        (esquema_nome, tabela_nome),
    ).fetchall()
    snapshot = None
    if medida["linhas"] <= LIMITE_SNAPSHOT:
        snapshot = conn.execute(
            sql.SQL(
                """SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t::text COLLATE "C"), '[]') AS dados
                   FROM {} t"""
            ).format(tabela)
        ).fetchone()["dados"]
    return {**medida, "esquema": colunas, "snapshot": snapshot}


def registrar_versao(
    conn: psycopg.Connection,
    ativo: dict[str, Any],
    execucao_id: int | None = None,
    parametros: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Devolve a versão atual do ativo; cria uma nova apenas se o conteúdo mudou."""
    medida = _medir(conn, ativo["localizacao"])
    ultima = conn.execute(
        "SELECT * FROM linhagem.ativo_versao WHERE ativo_id = %s ORDER BY numero DESC LIMIT 1",
        (ativo["id"],),
    ).fetchone()
    if ultima and ultima["checksum"] == medida["checksum"]:
        return {**ultima, "nova": False}
    nova = conn.execute(
        """INSERT INTO linhagem.ativo_versao
               (ativo_id, numero, checksum, linhas, esquema, snapshot, parametros, execucao_id)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
           RETURNING *""",
        (
            ativo["id"],
            (ultima["numero"] if ultima else 0) + 1,
            medida["checksum"],
            medida["linhas"],
            Jsonb(medida["esquema"]),
            Jsonb(medida["snapshot"]) if medida["snapshot"] is not None else None,
            Jsonb(parametros or {}),
            execucao_id,
        ),
    ).fetchone()
    return {**nova, "nova": True}


def executar_processo(
    processo_id: int,
    parametros: dict[str, Any] | None = None,
    executor: str = "interface-web",
) -> dict[str, Any]:
    with psycopg.connect(DSN, autocommit=True, row_factory=dict_row) as registro:
        processo = registro.execute(
            "SELECT * FROM linhagem.processo WHERE id = %s", (processo_id,)
        ).fetchone()
        if processo is None:
            raise KeyError(processo_id)
        params = validar_parametros(processo["parametros_padrao"], parametros)
        execucao_id = registro.execute(
            """INSERT INTO linhagem.execucao (processo_id, executor, parametros)
               VALUES (%s, %s, %s) RETURNING id""",
            (processo_id, executor, Jsonb(params)),
        ).fetchone()["id"]

        log = [f"{_agora()} início de {processo['codigo']} por {executor}; parâmetros: {params}"]
        try:
            _trabalhar(processo, params, execucao_id, executor, log)
        except psycopg.Error as exc:
            mensagem = exc.diag.message_primary or str(exc)
            log.append(f"{_agora()} FALHA, transação desfeita: {mensagem}")
            falha = registro.execute(
                """UPDATE linhagem.execucao
                   SET status = 'falha', finalizada_em = clock_timestamp(), log = %s,
                       evidencia = %s
                   WHERE id = %s RETURNING *""",
                ("\n".join(log), Jsonb({"erro": mensagem, "script": processo["script"]}), execucao_id),
            ).fetchone()
            raise ErroExecucao(falha) from exc
        return registro.execute(
            "SELECT * FROM linhagem.execucao WHERE id = %s", (execucao_id,)
        ).fetchone()


def _ativos_do_processo(conn: psycopg.Connection, tabela: str, processo_id: int) -> list[dict[str, Any]]:
    consulta = sql.SQL(
        """SELECT a.* FROM linhagem.ativo a
           JOIN linhagem.{} x ON x.ativo_id = a.id
           WHERE x.processo_id = %s ORDER BY a.codigo"""
    ).format(sql.Identifier(tabela))
    return conn.execute(consulta, (processo_id,)).fetchall()


def _trabalhar(
    processo: dict[str, Any],
    params: dict[str, Any],
    execucao_id: int,
    executor: str,
    log: list[str],
) -> None:
    script = (PIPELINE_DIR / processo["script"]).read_text(encoding="utf-8")
    with psycopg.connect(DSN, row_factory=dict_row) as conn:
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (_LOCK_PIPELINE,))
        conn.execute("SELECT set_config('app.usuario', %s, true)", (executor,))

        entradas = []
        for ativo in _ativos_do_processo(conn, "processo_entrada", processo["id"]):
            versao = registrar_versao(conn, ativo)
            entradas.append((ativo, versao))
            conn.execute(
                "INSERT INTO linhagem.execucao_entrada VALUES (%s, %s)", (execucao_id, versao["id"])
            )
        lidas = sum(v["linhas"] for _, v in entradas)
        log.append(f"{_agora()} entradas: " + ", ".join(f"{a['codigo']} v{v['numero']}" for a, v in entradas))

        # Cursor cliente: o script tem vários comandos, o que o bind no servidor não permite.
        with psycopg.ClientCursor(conn) as cursor:
            cursor.execute(script, params or None)

        saidas = []
        for ativo in _ativos_do_processo(conn, "processo_saida", processo["id"]):
            versao = registrar_versao(conn, ativo, execucao_id, params)
            saidas.append((ativo, versao))
            conn.execute(
                "INSERT INTO linhagem.execucao_saida VALUES (%s, %s)", (execucao_id, versao["id"])
            )
            situacao = "nova versão" if versao["nova"] else "sem alteração"
            log.append(f"{_agora()} saída {ativo['codigo']} v{versao['numero']}: {versao['linhas']} linhas ({situacao})")
        gravadas = sum(v["linhas"] for _, v in saidas)

        rejeitadas = 0
        if processo["tabela_rejeitos"]:
            rejeitadas = conn.execute(
                sql.SQL("SELECT count(*) AS n FROM {}").format(_tabela(processo["tabela_rejeitos"]))
            ).fetchone()["n"]
            log.append(f"{_agora()} rejeitadas: {rejeitadas} linhas em {processo['tabela_rejeitos']}")

        manifesto = {
            "script": processo["script"],
            "sha256_script": hashlib.sha256(script.encode()).hexdigest(),
            "parametros": params,
            "entradas": [{"ativo": a["codigo"], "versao": v["numero"], "checksum": v["checksum"]} for a, v in entradas],
            "saidas": [{"ativo": a["codigo"], "versao": v["numero"], "checksum": v["checksum"], "linhas": v["linhas"]} for a, v in saidas],
        }
        status = "parcial" if rejeitadas else "sucesso"
        log.append(f"{_agora()} fim: {status}")
        conn.execute(
            """UPDATE linhagem.execucao
               SET status = %s, finalizada_em = clock_timestamp(), linhas_lidas = %s,
                   linhas_gravadas = %s, linhas_rejeitadas = %s, log = %s, evidencia = %s
               WHERE id = %s""",
            (status, lidas, gravadas, rejeitadas, "\n".join(log), Jsonb(manifesto), execucao_id),
        )


def executar_pipeline(
    executor: str = "interface-web",
    a_partir_de: str | None = None,
    parametros: dict[str, dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Roda os processos em ordem e para na primeira falha."""
    parametros = parametros or {}
    with psycopg.connect(DSN, autocommit=True, row_factory=dict_row) as conn:
        processos = conn.execute("SELECT id, codigo, ordem FROM linhagem.processo ORDER BY ordem").fetchall()
    if a_partir_de:
        ordem = next(p["ordem"] for p in processos if p["codigo"] == a_partir_de)
        processos = [p for p in processos if p["ordem"] >= ordem]
    return [executar_processo(p["id"], parametros.get(p["codigo"]), executor) for p in processos]


def simular_atualizacao(ativo_id: int, usuario: str = "interface-web") -> dict[str, Any]:
    """Altera a fonte de verdade e registra a nova versão, deixando os dependentes desatualizados."""
    with psycopg.connect(DSN, row_factory=dict_row) as conn:
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (_LOCK_PIPELINE,))
        conn.execute("SELECT set_config('app.usuario', %s, true)", (usuario,))
        ativo = conn.execute("SELECT * FROM linhagem.ativo WHERE id = %s", (ativo_id,)).fetchone()
        if ativo is None:
            raise KeyError(ativo_id)
        if ativo["codigo"] not in _ATUALIZACOES:
            raise ParametroInvalido("Esta fonte não tem dados que possam ser atualizados.")
        alteradas = conn.execute(_ATUALIZACOES[ativo["codigo"]]).rowcount
        versao = registrar_versao(conn, ativo)
        return {"ativo": ativo["codigo"], "linhas_alteradas": alteradas, "versao": versao["numero"]}


def construir_historico() -> None:
    """Gera uma história de demonstração: carga, mudança na fonte, nova definição e uma falha."""
    executar_pipeline("carga-inicial", parametros={"MRT-PERM": {"periodos_sem_matricula": 3}})
    with psycopg.connect(DSN, autocommit=True, row_factory=dict_row) as conn:
        ids = {r["codigo"]: r["id"] for r in conn.execute("SELECT id, codigo FROM linhagem.ativo")}
        processos = {r["codigo"]: r["id"] for r in conn.execute("SELECT id, codigo FROM linhagem.processo")}
    simular_atualizacao(ids["F-MAT"], "secretaria-academica")
    executar_pipeline("agendador", parametros={"MRT-PERM": {"periodos_sem_matricula": 3}})
    executar_pipeline("observatorio", a_partir_de="MRT-PERM")
    try:
        executar_processo(processos["VAL-TRAJ"], {"min_completude": 0.99}, "nucleo-qualidade")
    except ErroExecucao:
        pass

    from . import consultas

    with psycopg.connect(DSN, row_factory=dict_row) as conn:
        conn.execute("SELECT set_config('app.usuario', 'carga-inicial', true)")
        consultas.executar(conn, "ascendentes", {"id": ids["D-EVA"], "profundidade": 30})
        consultas.executar(conn, "fontes_originais", {"id": ids["D-EVA"]})
        impacto = consultas.executar(conn, "descendentes", {"id": ids["F-MAT"]})
        conn.execute(
            """INSERT INTO linhagem.analise_impacto
                   (ativo_id, mudanca, tipo_impacto, severidade, acao, ativos)
               VALUES (%s, %s, 'semantico', 'critica', 'Reprocessar a partir da ingestão e comunicar consumidores', %s)""",
            (
                ids["F-MAT"],
                "Novo código de situação no Sistema Acadêmico",
                Jsonb([{"codigo": l["codigo"], "severidade": l["severidade"]} for l in impacto["linhas"]]),
            ),
        )
        versao = conn.execute(
            "SELECT max(id) AS id FROM linhagem.ativo_versao WHERE ativo_id = %s", (ids["D-EVA"],)
        ).fetchone()["id"]
        consultas.executar(conn, "proveniencia_versao", {"versao_id": versao})


def main() -> None:
    parser = argparse.ArgumentParser(description="Executa o pipeline de evasão")
    parser.add_argument("--historico", action="store_true", help="gera o histórico de demonstração")
    args = parser.parse_args()
    if args.historico:
        construir_historico()
    else:
        executar_pipeline("linha-de-comando")
    print("Pipeline concluído.")


if __name__ == "__main__":
    main()
