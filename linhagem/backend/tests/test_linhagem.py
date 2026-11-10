FONTES = {"F-MAT", "F-NOT", "F-FRE", "F-AVA", "F-SOC"}


def _codigos(resposta, campo="codigo"):
    assert resposta.status_code == 200, resposta.text
    return {linha[campo] for linha in resposta.json()["linhas"]}


def test_painel_chega_as_cinco_fontes(cliente, ids):
    assert _codigos(cliente.get(f"/api/linhagem/{ids['D-EVA']}/fontes")) == FONTES


def test_ascendentes_incluem_toda_a_cadeia(cliente, ids):
    codigos = _codigos(cliente.get(f"/api/linhagem/{ids['D-EVA']}/ascendentes"))
    assert {"IN-EVA", "M-PERM", "FE-ENG", "V-TRAJ", "T-TRAJ", "I-TRAJ", "B-MAT", "F-MAT"} <= codigos
    assert "R-CAM" not in codigos


def test_profundidade_limita_a_subida(cliente, ids):
    r = cliente.get(f"/api/linhagem/{ids['D-EVA']}/ascendentes", params={"profundidade": 1})
    assert _codigos(r) == {"IN-EVA"}


def test_descendentes_de_fonte_alcancam_consumidores(cliente, ids):
    r = cliente.get(f"/api/linhagem/{ids['F-MAT']}/descendentes")
    codigos = _codigos(r)
    assert {"B-MAT", "D-EVA", "R-CAM", "A-EVA", "C-PRO", "C-COO", "C-APP"} <= codigos
    assert "F-NOT" not in codigos
    severidade = {l["codigo"]: l["severidade"] for l in r.json()["linhas"]}
    assert severidade["D-EVA"] == "critica"


def test_caminhos_mostram_rota_pela_feature(cliente, ids):
    r = cliente.get("/api/linhagem/caminho", params={"origem": ids["V-TRAJ"], "destino": ids["M-PERM"]})
    assert _codigos(r, "caminho") == {"V-TRAJ -> M-PERM", "V-TRAJ -> FE-ENG -> M-PERM"}


def test_linhagem_de_atributo_chega_as_colunas_originais(cliente):
    atributos = {a["rotulo"]: a["id"] for a in cliente.get("/api/atributos").json()}
    r = cliente.get(f"/api/atributos/{atributos['D-EVA.taxa_evasao']}/linhagem")
    origens = _codigos(r, "atributo_origem")
    assert {"F-MAT.situacao", "F-MAT.ano", "F-MAT.semestre"} <= origens


def test_ciclo_e_rejeitado_com_o_caminho(cliente, ids):
    r = cliente.post(
        "/api/dependencias",
        json={"origem_id": ids["D-EVA"], "destino_id": ids["F-MAT"], "tipo_relacao": "alimentou"},
    )
    assert r.status_code == 409
    assert "ciclo" in r.json()["detail"]
    assert "F-MAT -> B-MAT" in r.json()["detail"]


def test_reexecucao_sem_mudanca_nao_cria_versao(cliente, ids, processos):
    antes = cliente.get(f"/api/ativos/{ids['B-AVA']}").json()["versoes"]
    r = cliente.post(f"/api/processos/{processos['ING-AVA']}/executar", json={})
    assert r.status_code == 200
    assert cliente.get(f"/api/ativos/{ids['B-AVA']}").json()["versoes"] == antes


def test_falha_desfaz_dados_e_mantem_log(cliente, ids, processos):
    versoes = len(cliente.get(f"/api/ativos/{ids['V-TRAJ']}").json()["versoes"])
    r = cliente.post(f"/api/processos/{processos['VAL-TRAJ']}/executar", json={"parametros": {"min_completude": 0.999}})
    assert r.status_code == 422
    execucao = cliente.get(f"/api/execucoes/{r.json()['execucao_id']}").json()
    assert execucao["status"] == "falha"
    assert "Validação reprovada" in execucao["log"]
    assert execucao["saidas"] == []
    assert len(cliente.get(f"/api/ativos/{ids['V-TRAJ']}").json()["versoes"]) == versoes


def test_parametro_desconhecido_nao_gera_execucao(cliente, processos):
    antes = len(cliente.get("/api/execucoes", params={"limite": 500}).json())
    r = cliente.post(f"/api/processos/{processos['MRT-PERM']}/executar", json={"parametros": {"drop": "x"}})
    assert r.status_code == 422
    assert len(cliente.get("/api/execucoes", params={"limite": 500}).json()) == antes


def test_proveniencia_por_versao_preserva_a_versao_antiga(cliente, ids):
    primeira = next(v for v in cliente.get(f"/api/ativos/{ids['D-EVA']}").json()["versoes"] if v["numero"] == 1)

    assert cliente.post(f"/api/fontes/{ids['F-MAT']}/simular-atualizacao").status_code == 200
    desatualizados = {d["codigo"] for d in cliente.get("/api/desatualizados").json()}
    assert {"B-MAT", "D-EVA", "C-PRO"} <= desatualizados
    assert "F-NOT" not in desatualizados

    assert cliente.post("/api/pipeline/executar", json={}).status_code == 200
    assert cliente.get("/api/desatualizados").json() == []

    linhas = cliente.get(f"/api/versoes/{primeira['id']}/proveniencia").json()["linhas"]
    fonte = next(l for l in linhas if l["codigo"] == "F-MAT")
    assert fonte["versao"] == 1
    atual = cliente.get(f"/api/ativos/{ids['F-MAT']}").json()["versoes"][0]
    assert atual["numero"] == 2


def test_nova_definicao_de_evasao_gera_diferencas_comparaveis(cliente, ids, processos):
    cliente.post(f"/api/processos/{processos['MRT-PERM']}/executar", json={"parametros": {"periodos_sem_matricula": 1}})
    for codigo in ("IND-EVA", "PUB-PAI"):
        cliente.post(f"/api/processos/{processos[codigo]}/executar", json={})
    versoes = cliente.get(f"/api/ativos/{ids['D-EVA']}").json()["versoes"]
    r = cliente.get(f"/api/ativos/{ids['D-EVA']}/versoes/comparar", params={"a": versoes[1]["numero"], "b": versoes[0]["numero"]})
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["comparavel"] and any(d["coluna"] == "taxa_evasao" for d in corpo["diferencas"])
    assert cliente.get("/api/painel/evasao").json()["definicao"] == {"periodos_sem_matricula": 1}


def test_grafo_no_passado_mostra_a_fonte_legada(cliente, ids):
    passado = cliente.get(f"/api/linhagem/{ids['B-SOC']}/grafo", params={"em": "2024-06-01T00:00:00-03:00", "direcao": "ascendentes"})
    atual = cliente.get(f"/api/linhagem/{ids['B-SOC']}/grafo", params={"direcao": "ascendentes"})
    assert {n["codigo"] for n in passado.json()["nos"]} == {"B-SOC", "F-SOC-LEG"}
    assert {n["codigo"] for n in atual.json()["nos"]} == {"B-SOC", "F-SOC"}


def test_grafo_completo_expoe_processos_e_regras(cliente, ids):
    grafo = cliente.get(f"/api/linhagem/{ids['T-TRAJ']}/grafo", params={"detalhe": "completo", "direcao": "ascendentes", "profundidade": 1}).json()
    classes = {n["classe"] for n in grafo["nos"]}
    assert classes == {"ativo", "processo", "regra"}


def test_descontinuar_preserva_historico(cliente):
    criado = cliente.post("/api/ativos", json={"codigo": "T-X", "nome": "Temporário", "tipo": "dataset_tratado", "camada": "tratado"}).json()
    assert cliente.delete(f"/api/ativos/{criado['id']}").status_code == 204
    detalhe = cliente.get(f"/api/ativos/{criado['id']}").json()
    assert detalhe["status"] == "obsoleto"
    assert [h["operacao"] for h in detalhe["historico"]] == ["UPDATE", "INSERT"]


def test_valores_numeric_saem_como_numero_json(cliente):
    assert isinstance(cliente.get("/api/painel/evasao").json()["linhas"][0]["taxa_evasao"], float)


def test_metricas_e_criterios_completos(cliente):
    assert len(cliente.get("/api/metricas").json()) == 15
    assert [c["numero"] for c in cliente.get("/api/metricas/criterios").json()] == list(range(1, 13))
