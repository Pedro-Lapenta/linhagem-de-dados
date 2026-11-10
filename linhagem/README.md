# Linhagem de Dados: parte prática

Sistema que registra **origem, transformações e destino** de cada conjunto de dados, com histórico, metadados, relacionamentos, consultas recursivas e proveniência. Implementa o **Módulo 11 (Proveniência, Linhagem e Rastreabilidade)** do UnespDataLens-RM.

O cenário é o painel de evasão citado no próprio módulo. **Todos os dados são simulados.** Cada execução do pipeline transforma dados de verdade no PostgreSQL e grava sua linhagem.

## Stack

| Camada | Tecnologia |
|---|---|
| Front-end | React, TypeScript e TSX (Vite) |
| API | Python e FastAPI, REST em JSON |
| Banco | PostgreSQL 17 |
| Acesso a dados | psycopg 3 com SQL puro, sem ORM |
| Mapa | Leaflet |

## Como rodar

Pré-requisitos: Docker em execução, Python 3.12 e Node 22. Execute a partir desta pasta (`linhagem/`).

```bash
# 1. Banco: cria os esquemas e os dados simulados
docker compose up -d --wait

# 2. API e histórico de demonstração
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m app.runner --historico
.venv/bin/uvicorn app.main:app --port 8000
```

Em outro terminal:

```bash
# 3. Interface
cd frontend
npm install
npm run dev
```

Abra <http://localhost:5173>. A documentação da API fica em <http://localhost:8000/docs>. O mapa usa tiles do OpenStreetMap e precisa de internet.

Para voltar ao estado inicial, rode `docker compose down -v` e repita os passos 1 e 2 (o `pip install` não precisa ser refeito).

## Testes

Com o banco no ar, a partir de `backend/`:

```bash
.venv/bin/python -m pytest
```

Os testes criam um banco próprio (`linhagem_teste`) e não alteram os dados da demonstração.

## Roteiro de demonstração

1. **Visão geral:** clique em `F-MAT` para acender tudo o que depende dessa fonte, ou em `D-EVA` para ver de onde o painel vem.
2. **Pipeline:** mude "Períodos sem matrícula" para 1 e execute o data mart, o indicador e o painel. Em "Comparar versões", veja as taxas mudarem.
3. **Pipeline:** execute a validação com completude mínima 0,99. A etapa falha, nada é gravado e o log fica no histórico.
4. **Pipeline:** simule a atualização de uma fonte. Os dependentes ficam desatualizados até o pipeline rodar de novo.
5. **Consultas recursivas:** execute "Proveniência por versão" e veja o SQL. Uma versão antiga continua apontando para as fontes antigas.
6. **Catálogo:** abra `D-EVA` e tente registrar que ele alimenta `F-MAT`. O banco recusa e mostra o caminho que fecharia o ciclo.
7. **Grafo:** em "Como estava em", informe 01/06/2024 com `B-SOC` selecionado para ver a fonte legada, substituída em 2025.
8. **Análise de impacto, Mapa e Auditoria:** alcance de uma mudança, origem das fontes e trilha antes/depois.

A planilha `F-BOL` e o painel `D-LEG` não têm linhagem de propósito: eles mostram como o sistema expõe lacunas, por isso os critérios 7, 10 e 11 aparecem pendentes.

## Onde cada requisito está

| Requisito | Implementação |
|---|---|
| Origem | `linhagem.proveniencia`, tela Mapa, consulta `fontes_originais.sql` |
| Transformações | `linhagem.processo`, `regra`, `backend/pipeline/*.sql`, consulta `transformacoes.sql` |
| Destino | `linhagem.dependencia`, consumidores, consulta `descendentes.sql` |
| Histórico | `execucao`, `ativo_versao`, `execucao_entrada/saida`, `auditoria`, vigência das arestas |
| Metadados | `ativo`, `atributo`, `responsavel` |
| Relacionamentos | `dependencia` (ativos), `atributo_derivacao` (colunas), trigger anti-ciclo em `db/03_triggers.sql` |
| Consultas recursivas | `backend/app/sql/*.sql` e `linhagem.vw_fechamento` |
| Proveniência | `proveniencia_versao.sql` percorre as versões exatas lidas em cada execução |
| Métricas (15) e critérios (12) do Módulo 11 | `db/04_views_metricas.sql` |

## Organização

```
db/        esquema, triggers, métricas e dados simulados (carregados pelo Compose)
backend/   app/ (API, runner, SQL das consultas), pipeline/ (etapas), tests/
frontend/  interface React
```
