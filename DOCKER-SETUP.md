# Banco de dados com Docker

Como subir pela primeira vez o PostgreSQL do sistema de Linhagem de Dados e acessar o banco mock.

Todos os dados são **simulados**. A senha abaixo serve só para este ambiente local, e o banco aceita conexões apenas da própria máquina.

## Pré-requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado. No Windows, use o backend WSL 2, que o instalador oferece por padrão.
- A porta `5433` livre.
- Para gerar as camadas processadas (passo 3): Python 3.12.

## Primeira execução

### 0. Abra o Docker Desktop

Abra o aplicativo e espere o rodapé indicar **Engine running**. Ele precisa ficar aberto enquanto o banco estiver em uso. Depois, em um terminal (no Windows, o PowerShell), confira:

```bash
docker ps
```

O comando deve listar os containers, mesmo que a lista venha vazia, sem mostrar erro.

### 1. Suba o banco

Execute a partir da raiz do repositório:

```bash
cd linhagem
docker compose up -d --wait
```

O primeiro início baixa a imagem `postgres:17` e carrega os scripts de `linhagem/db/`, criando esquemas, triggers, métricas, catálogo e dados simulados. O comando termina quando o banco estiver pronto. O container `linhagem-postgres` passa a aparecer na aba **Containers** do Docker Desktop, dentro do grupo `linhagem`.

### 2. Confira a carga

```bash
docker exec linhagem-postgres psql -U linhagem -d linhagem -c "SELECT count(*) AS ativos FROM linhagem.ativo;"
```

O resultado esperado é `26` ativos.

### 3. Gere as camadas processadas

Depois do passo 1, só `fontes` e os cadastros de `linhagem` têm dados. As tabelas de `bruto`, `integrado`, `tratado`, `validado` e `mart` são criadas ao executar o pipeline:

No macOS ou Linux:

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m app.runner --historico
```

No Windows (PowerShell):

```powershell
cd backend
py -3.12 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m app.runner --historico
```

Ao final deve aparecer `Pipeline concluído.`. Rode este passo uma única vez em um banco novo. Para repetir, faça antes o reset descrito abaixo.

## Dados de conexão

| Campo | Valor |
|---|---|
| Host | `127.0.0.1` |
| Porta | `5433` |
| Banco | `linhagem` |
| Usuário | `linhagem` |
| Senha | `linhagem` |
| URL | `postgresql://linhagem:linhagem@127.0.0.1:5433/linhagem` |

## Como acessar

**Pelo Docker Desktop** (não precisa instalar nada): na aba **Containers**, abra `linhagem-postgres`, entre na aba **Exec** e rode:

```bash
psql -U linhagem -d linhagem
```

**Pelo terminal, usando o container:**

```bash
docker exec -it linhagem-postgres psql -U linhagem -d linhagem
```

**Com o `psql` instalado na sua máquina**, no macOS ou Linux:

```bash
PGPASSWORD=linhagem psql -h 127.0.0.1 -p 5433 -U linhagem -d linhagem
```

No Windows (PowerShell):

```powershell
$env:PGPASSWORD = "linhagem"
psql -h 127.0.0.1 -p 5433 -U linhagem -d linhagem
```

**Com um cliente gráfico** (DBeaver, pgAdmin, DataGrip): crie uma conexão PostgreSQL com os dados da tabela acima.

## O que existe no banco

| Esquema | Conteúdo |
|---|---|
| `fontes` | Sistemas de origem simulados: `matricula`, `notas`, `frequencia`, `ava`, `socioeconomico` |
| `bruto` | Cópia fiel das fontes |
| `integrado` | `trajetoria`: uma linha por aluno e período |
| `tratado` | `trajetoria_academica` e `trajetoria_rejeitados` |
| `validado` | `trajetoria_academica` e `relatorio_qualidade` |
| `mart` | `permanencia`, `feature_engajamento`, `indicador_taxa_evasao`, `painel_evasao`, `relatorio_evasao_campus`, `api_evasao` |
| `linhagem` | Metadados: `ativo`, `proveniencia`, `dependencia`, `processo`, `execucao`, `ativo_versao`, `auditoria` e outras |

## Consultas para começar

```sql
-- Listar esquemas e as tabelas de um deles (comandos do psql)
\dn
\dt linhagem.*

-- Amostra de uma fonte simulada
SELECT * FROM fontes.matricula LIMIT 10;

-- Métricas e critérios do Módulo 11
SELECT sigla, nome, valor, unidade FROM linhagem.vw_metricas;
SELECT numero, criterio, atendidos, total, atendido FROM linhagem.vw_criterios;

-- Taxa de evasão publicada no painel
SELECT curso, campus, alunos, evadidos, taxa_evasao, faixa_risco
FROM mart.painel_evasao
ORDER BY taxa_evasao DESC;

-- De onde o painel vem: consulta recursiva sobre o grafo
WITH RECURSIVE acima AS (
    SELECT a.id, a.codigo, 0 AS profundidade
    FROM linhagem.ativo a
    WHERE a.codigo = 'D-EVA'
    UNION
    SELECT o.id, o.codigo, acima.profundidade + 1
    FROM acima
    JOIN linhagem.dependencia d ON d.destino_id = acima.id AND d.vigente_ate IS NULL
    JOIN linhagem.ativo o ON o.id = d.origem_id
)
SELECT codigo, max(profundidade) AS etapas
FROM acima
GROUP BY codigo
ORDER BY etapas, codigo;
```

## Comandos do dia a dia

Execute os comandos dentro de `linhagem/`, ou use o Docker Desktop.

| Ação | Comando | No Docker Desktop |
|---|---|---|
| Parar, mantendo os dados | `docker compose stop` | Botão de parar em **Containers** |
| Iniciar de novo | `docker compose up -d --wait` | Botão de iniciar em **Containers** |
| Ver os logs | `docker compose logs db` | Aba **Logs** do container |
| Apagar tudo e recomeçar | `docker compose down -v` | Use o comando: ele apaga o container e os dados |

Fechar o Docker Desktop também desliga o banco, mas os dados são mantidos.

Depois de `docker compose down -v`, repita os passos 1 e 3 (o `pip install` não precisa ser refeito). Se a API estiver rodando, reinicie-a.

## Problemas comuns

| Sintoma | Causa e solução |
|---|---|
| `Cannot connect to the Docker daemon` ou erro citando `dockerDesktopLinuxEngine` | O Docker Desktop está fechado ou ainda iniciando. Abra o aplicativo e espere **Engine running**. |
| Erro sobre WSL ao abrir o Docker Desktop (Windows) | Rode `wsl --update` no PowerShell e abra o aplicativo de novo. |
| Erro de acesso à pasta `db` ao subir o container | Em **Settings > Resources > File sharing**, libere a pasta do projeto, se essa opção existir na sua instalação. |
| `port is already allocated` | Outro programa usa a porta `5433`. Pare esse programa ou altere o primeiro número em `ports` no `linhagem/docker-compose.yml`. |
| Mudei um arquivo em `linhagem/db/` e nada aconteceu | Esses scripts só rodam com o banco vazio. Use `docker compose down -v` e suba de novo. |
| `relation "mart.painel_evasao" does not exist` | O pipeline ainda não foi executado. Faça o passo 3. |
| `Connection refused` na porta `5433` | O banco não está no ar. Confira com `docker compose ps`. |

Para rodar a API e a interface, veja [`linhagem/README.md`](linhagem/README.md).
