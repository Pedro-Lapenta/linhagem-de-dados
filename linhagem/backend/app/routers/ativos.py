from __future__ import annotations

from datetime import date
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, Query, Response
from psycopg.types.json import Jsonb
from pydantic import BaseModel, Field

from .. import consultas
from ..db import transacao

router = APIRouter(tags=["catálogo"])

TipoAtivo = Literal[
    "fonte", "dataset_bruto", "dataset_integrado", "dataset_tratado", "dataset_validado", "data_mart",
    "feature", "indicador", "modelo", "dashboard", "api", "relatorio", "produto_dados", "consumidor",
]
Camada = Literal["fontes", "bruto", "integrado", "tratado", "validado", "mart", "consumo"]
Sensibilidade = Literal["publico", "interno", "restrito", "sensivel"]
TipoRelacao = Literal[
    "originou", "foi_extraido_de", "foi_integrado_com", "foi_transformado_por", "gerou",
    "derivou_de", "validou", "alimentou", "consumiu", "substituiu", "depende_de",
]


class AtivoEntrada(BaseModel):
    codigo: str = Field(min_length=1, max_length=40)
    nome: str = Field(min_length=1, max_length=160)
    tipo: TipoAtivo
    camada: Camada
    descricao: str | None = None
    localizacao: str | None = None
    sensibilidade: Sensibilidade = "interno"
    critico: bool = False
    responsavel_id: int | None = None
    metadados: dict[str, Any] = Field(default_factory=dict)


class AtributoEntrada(BaseModel):
    nome: str = Field(min_length=1, max_length=120)
    tipo_dado: str = Field(min_length=1, max_length=60)
    critico: bool = False
    sensivel: bool = False
    descricao: str | None = None


class ProvenienciaEntrada(BaseModel):
    sistema_origem: str = Field(min_length=1)
    instituicao: str = Field(min_length=1)
    cidade: str | None = None
    campus: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    periodicidade: str | None = None
    cobertura_inicio: date | None = None
    cobertura_fim: date | None = None
    data_extracao: date | None = None
    condicoes_uso: str | None = None


class DependenciaEntrada(BaseModel):
    origem_id: int
    destino_id: int
    tipo_relacao: TipoRelacao
    processo_id: int | None = None
    regra_id: int | None = None
    responsavel_id: int | None = None
    evidencia: str | None = None


def _exigir_ativo(conn, ativo_id: int) -> dict[str, Any]:
    ativo = conn.execute(
        """SELECT a.*, r.nome AS responsavel
           FROM linhagem.ativo a LEFT JOIN linhagem.responsavel r ON r.id = a.responsavel_id
           WHERE a.id = %s""",
        (ativo_id,),
    ).fetchone()
    if ativo is None:
        raise HTTPException(404, "Ativo não encontrado.")
    return ativo


@router.get("/responsaveis")
def listar_responsaveis() -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute("SELECT * FROM linhagem.responsavel ORDER BY nome").fetchall()


@router.get("/ativos")
def listar_ativos(
    busca: str | None = None, tipo: str | None = None, camada: str | None = None
) -> list[dict[str, Any]]:
    with transacao() as conn:
        linhas = conn.execute(
            """SELECT a.id, a.codigo, a.nome, a.tipo, a.camada, a.sensibilidade, a.critico, a.status,
                      r.nome AS responsavel, v.numero AS versao_atual, v.criado_em AS versao_em,
                      au.iaa, EXISTS (SELECT 1 FROM linhagem.proveniencia p WHERE p.ativo_id = a.id) AS tem_proveniencia
               FROM linhagem.ativo a
               LEFT JOIN linhagem.responsavel r ON r.id = a.responsavel_id
               LEFT JOIN LATERAL (
                   SELECT numero, criado_em FROM linhagem.ativo_versao x
                   WHERE x.ativo_id = a.id ORDER BY numero DESC LIMIT 1
               ) v ON true
               LEFT JOIN linhagem.vw_auditabilidade au ON au.ativo_id = a.id
               WHERE (%(busca)s::text IS NULL OR a.nome ILIKE '%%' || %(busca)s || '%%'
                      OR a.codigo ILIKE '%%' || %(busca)s || '%%')
                 AND (%(tipo)s::text IS NULL OR a.tipo = %(tipo)s)
                 AND (%(camada)s::text IS NULL OR a.camada = %(camada)s)
               ORDER BY CASE a.camada WHEN 'fontes' THEN 1 WHEN 'bruto' THEN 2 WHEN 'integrado' THEN 3
                        WHEN 'tratado' THEN 4 WHEN 'validado' THEN 5 WHEN 'mart' THEN 6 ELSE 7 END, a.codigo""",
            {"busca": busca or None, "tipo": tipo or None, "camada": camada or None},
        ).fetchall()
        desatualizados = consultas.executar(conn, "desatualizados", {})["linhas"]
    causas = {d["ativo_id"]: d["causa"] for d in desatualizados}
    for linha in linhas:
        linha["desatualizado_por"] = causas.get(linha["id"])
    return linhas


@router.get("/ativos/{ativo_id}")
def detalhar_ativo(ativo_id: int) -> dict[str, Any]:
    with transacao() as conn:
        ativo = _exigir_ativo(conn, ativo_id)
        ativo["proveniencia"] = conn.execute(
            "SELECT * FROM linhagem.proveniencia WHERE ativo_id = %s", (ativo_id,)
        ).fetchone()
        ativo["atributos"] = conn.execute(
            "SELECT * FROM linhagem.atributo WHERE ativo_id = %s ORDER BY critico DESC, nome", (ativo_id,)
        ).fetchall()
        ativo["versoes"] = conn.execute(
            """SELECT v.id, v.numero, v.checksum, v.linhas, v.parametros, v.execucao_id, v.criado_em,
                      v.esquema, p.codigo AS processo, e.executor
               FROM linhagem.ativo_versao v
               LEFT JOIN linhagem.execucao e ON e.id = v.execucao_id
               LEFT JOIN linhagem.processo p ON p.id = e.processo_id
               WHERE v.ativo_id = %s ORDER BY v.numero DESC""",
            (ativo_id,),
        ).fetchall()
        ativo["auditabilidade"] = conn.execute(
            "SELECT * FROM linhagem.vw_auditabilidade WHERE ativo_id = %s", (ativo_id,)
        ).fetchone()
        ativo["vizinhos"] = conn.execute(
            """SELECT d.id, d.tipo_relacao, d.vigente_de, d.vigente_ate, d.evidencia,
                      CASE WHEN d.destino_id = %(id)s THEN 'entrada' ELSE 'saida' END AS sentido,
                      o.id AS outro_id, o.codigo AS outro_codigo, o.nome AS outro_nome,
                      p.codigo AS processo
               FROM linhagem.dependencia d
               JOIN linhagem.ativo o ON o.id = CASE WHEN d.destino_id = %(id)s THEN d.origem_id ELSE d.destino_id END
               LEFT JOIN linhagem.processo p ON p.id = d.processo_id
               WHERE (d.origem_id = %(id)s OR d.destino_id = %(id)s)
               ORDER BY d.vigente_ate NULLS FIRST, sentido, o.codigo""",
            {"id": ativo_id},
        ).fetchall()
        ativo["historico"] = conn.execute(
            """SELECT * FROM linhagem.auditoria
               WHERE tabela = 'ativo' AND registro_id = %s ORDER BY em DESC LIMIT 30""",
            (str(ativo_id),),
        ).fetchall()
    return ativo


@router.post("/ativos", status_code=201)
def criar_ativo(dados: AtivoEntrada) -> dict[str, Any]:
    with transacao() as conn:
        return conn.execute(
            """INSERT INTO linhagem.ativo
                   (codigo, nome, tipo, camada, descricao, localizacao, sensibilidade, critico, responsavel_id, metadados)
               VALUES (%(codigo)s, %(nome)s, %(tipo)s, %(camada)s, %(descricao)s, %(localizacao)s,
                       %(sensibilidade)s, %(critico)s, %(responsavel_id)s, %(meta)s)
               RETURNING *""",
            {**dados.model_dump(), "meta": Jsonb(dados.metadados)},
        ).fetchone()


@router.put("/ativos/{ativo_id}")
def atualizar_ativo(ativo_id: int, dados: AtivoEntrada) -> dict[str, Any]:
    with transacao() as conn:
        linha = conn.execute(
            """UPDATE linhagem.ativo SET codigo = %(codigo)s, nome = %(nome)s, tipo = %(tipo)s,
                   camada = %(camada)s, descricao = %(descricao)s, localizacao = %(localizacao)s,
                   sensibilidade = %(sensibilidade)s, critico = %(critico)s,
                   responsavel_id = %(responsavel_id)s, metadados = %(meta)s
               WHERE id = %(id)s RETURNING *""",
            {**dados.model_dump(), "meta": Jsonb(dados.metadados), "id": ativo_id},
        ).fetchone()
    if linha is None:
        raise HTTPException(404, "Ativo não encontrado.")
    return linha


@router.delete("/ativos/{ativo_id}", status_code=204)
def descontinuar_ativo(ativo_id: int) -> Response:
    """Linhagem não se apaga: o ativo vira obsoleto e suas arestas são encerradas."""
    with transacao() as conn:
        _exigir_ativo(conn, ativo_id)
        conn.execute("UPDATE linhagem.ativo SET status = 'obsoleto' WHERE id = %s", (ativo_id,))
        conn.execute(
            """UPDATE linhagem.dependencia SET vigente_ate = GREATEST(now(), vigente_de + interval '1 second')
               WHERE vigente_ate IS NULL AND (origem_id = %(id)s OR destino_id = %(id)s)""",
            {"id": ativo_id},
        )
    return Response(status_code=204)


@router.post("/ativos/{ativo_id}/atributos", status_code=201)
def criar_atributo(ativo_id: int, dados: AtributoEntrada) -> dict[str, Any]:
    with transacao() as conn:
        _exigir_ativo(conn, ativo_id)
        return conn.execute(
            """INSERT INTO linhagem.atributo (ativo_id, nome, tipo_dado, critico, sensivel, descricao)
               VALUES (%s, %s, %s, %s, %s, %s) RETURNING *""",
            (ativo_id, dados.nome, dados.tipo_dado, dados.critico, dados.sensivel, dados.descricao),
        ).fetchone()


@router.put("/ativos/{ativo_id}/proveniencia")
def salvar_proveniencia(ativo_id: int, dados: ProvenienciaEntrada) -> dict[str, Any]:
    with transacao() as conn:
        _exigir_ativo(conn, ativo_id)
        return conn.execute(
            """INSERT INTO linhagem.proveniencia
                   (ativo_id, sistema_origem, instituicao, cidade, campus, latitude, longitude,
                    periodicidade, cobertura_inicio, cobertura_fim, data_extracao, condicoes_uso)
               VALUES (%(id)s, %(sistema_origem)s, %(instituicao)s, %(cidade)s, %(campus)s, %(latitude)s,
                       %(longitude)s, %(periodicidade)s, %(cobertura_inicio)s, %(cobertura_fim)s,
                       %(data_extracao)s, %(condicoes_uso)s)
               ON CONFLICT (ativo_id) DO UPDATE SET
                   sistema_origem = EXCLUDED.sistema_origem, instituicao = EXCLUDED.instituicao,
                   cidade = EXCLUDED.cidade, campus = EXCLUDED.campus, latitude = EXCLUDED.latitude,
                   longitude = EXCLUDED.longitude, periodicidade = EXCLUDED.periodicidade,
                   cobertura_inicio = EXCLUDED.cobertura_inicio, cobertura_fim = EXCLUDED.cobertura_fim,
                   data_extracao = EXCLUDED.data_extracao, condicoes_uso = EXCLUDED.condicoes_uso
               RETURNING *""",
            {**dados.model_dump(), "id": ativo_id},
        ).fetchone()


@router.get("/ativos/{ativo_id}/versoes/comparar")
def comparar_versoes(ativo_id: int, a: int = Query(ge=1), b: int = Query(ge=1)) -> dict[str, Any]:
    with transacao() as conn:
        versoes = conn.execute(
            """SELECT numero, checksum, linhas, parametros, snapshot, esquema, criado_em
               FROM linhagem.ativo_versao WHERE ativo_id = %s AND numero = ANY(%s)""",
            (ativo_id, [a, b]),
        ).fetchall()
    por_numero = {v["numero"]: v for v in versoes}
    if a not in por_numero or b not in por_numero:
        raise HTTPException(404, "Versão não encontrada.")
    va, vb = por_numero[a], por_numero[b]
    diferencas: list[dict[str, Any]] = []
    if va["snapshot"] is not None and vb["snapshot"] is not None and vb["esquema"]:
        # A primeira coluna do esquema identifica a linha; jsonb não preserva a ordem das chaves.
        chave = vb["esquema"][0]["nome"]
        linhas_a = {l[chave]: l for l in va["snapshot"]}
        linhas_b = {l[chave]: l for l in vb["snapshot"]}
        for valor in sorted(set(linhas_a) | set(linhas_b), key=str):
            la, lb = linhas_a.get(valor, {}), linhas_b.get(valor, {})
            for coluna in [c["nome"] for c in vb["esquema"][1:]]:
                if la.get(coluna) != lb.get(coluna):
                    diferencas.append({"chave": valor, "coluna": coluna, "a": la.get(coluna), "b": lb.get(coluna)})
    resumo = lambda v: {k: v[k] for k in ("numero", "checksum", "linhas", "parametros", "criado_em")}
    return {
        "a": resumo(va),
        "b": resumo(vb),
        "comparavel": va["snapshot"] is not None and vb["snapshot"] is not None,
        "diferencas": diferencas,
    }


@router.get("/atributos")
def listar_atributos() -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute(
            """SELECT at.id, at.nome, at.tipo_dado, at.critico, at.sensivel, a.id AS ativo_id,
                      a.codigo AS ativo_codigo, a.codigo || '.' || at.nome AS rotulo
               FROM linhagem.atributo at JOIN linhagem.ativo a ON a.id = at.ativo_id
               ORDER BY a.codigo, at.nome"""
        ).fetchall()


@router.get("/versoes")
def listar_versoes() -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute(
            """SELECT v.id, v.numero, a.codigo, a.nome, v.linhas, v.criado_em,
                      a.codigo || ' v' || v.numero AS rotulo
               FROM linhagem.ativo_versao v JOIN linhagem.ativo a ON a.id = v.ativo_id
               ORDER BY a.codigo, v.numero DESC"""
        ).fetchall()


@router.get("/dependencias")
def listar_dependencias(incluir_encerradas: bool = False) -> list[dict[str, Any]]:
    with transacao() as conn:
        return conn.execute(
            """SELECT d.*, o.codigo AS origem, x.codigo AS destino, p.codigo AS processo
               FROM linhagem.dependencia d
               JOIN linhagem.ativo o ON o.id = d.origem_id
               JOIN linhagem.ativo x ON x.id = d.destino_id
               LEFT JOIN linhagem.processo p ON p.id = d.processo_id
               WHERE %s OR d.vigente_ate IS NULL
               ORDER BY o.codigo, x.codigo""",
            (incluir_encerradas,),
        ).fetchall()


@router.post("/dependencias", status_code=201)
def criar_dependencia(dados: DependenciaEntrada) -> dict[str, Any]:
    with transacao() as conn:
        return conn.execute(
            """INSERT INTO linhagem.dependencia
                   (origem_id, destino_id, tipo_relacao, processo_id, regra_id, responsavel_id, evidencia)
               VALUES (%(origem_id)s, %(destino_id)s, %(tipo_relacao)s, %(processo_id)s, %(regra_id)s,
                       %(responsavel_id)s, %(evidencia)s)
               RETURNING *""",
            dados.model_dump(),
        ).fetchone()


@router.delete("/dependencias/{dependencia_id}", status_code=204)
def encerrar_dependencia(dependencia_id: int) -> Response:
    """Encerra a vigência em vez de apagar, preservando o histórico do grafo."""
    with transacao() as conn:
        linha = conn.execute(
            """UPDATE linhagem.dependencia SET vigente_ate = GREATEST(now(), vigente_de + interval '1 second')
               WHERE id = %s AND vigente_ate IS NULL RETURNING id""",
            (dependencia_id,),
        ).fetchone()
    if linha is None:
        raise HTTPException(404, "Dependência vigente não encontrada.")
    return Response(status_code=204)
