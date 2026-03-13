# Claude Code — Migration Framework (.NET)

Framework generico para executar migracoes em massa em repositorios .NET usando [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Usa **skills**, **agents**, **hooks** e **rules** do Claude Code para orquestrar, executar e validar migracoes de forma automatizada e paralela.

## Estrutura

```
.claude/
├── settings.json                          # Hooks de guardrail
├── hooks/
│   ├── pre-commit-guard.sh                # Bloqueia commit se build/test falhar
│   ├── pre-push-guard.sh                  # Bloqueia push se build/test falhar
│   └── post-edit-format.sh                # Roda dotnet format apos editar .cs
├── rules/
│   └── dotnet.md                          # Padroes .NET (scoped para *.cs)
├── skills/
│   ├── migrate/SKILL.md                   # /migrate — orquestrador generico
│   └── migrate-mediatr/SKILL.md           # /migrate-mediatr — receita MediatR
├── agents/
│   └── dotnet-migrator.md                 # Executor isolado de migracoes
CLAUDE.md                                  # Contexto geral do framework
migrate.sh                                 # Execucao em massa via shell
repos.txt                                  # Lista de repositorios
```

## Conceitos do Claude Code

Este projeto usa 4 mecanismos de configuracao do Claude Code. Cada um tem um papel distinto:

### CLAUDE.md — Contexto

Arquivo markdown lido automaticamente no inicio de cada conversa. Da ao Claude o contexto geral do projeto: o que e, como funciona, quais convencoes seguir.

Nao executa nada — e apenas informacao.

### Skills — Receitas (`/slash-commands`)

Arquivos `SKILL.md` dentro de `.claude/skills/{nome}/`. Cada skill vira um comando invocavel via `/nome`.

Contem um **frontmatter** (bloco YAML entre `---`) com metadados e depois as instrucoes em markdown:

```yaml
---
name: migrate-mediatr
description: "Remove MediatR de um projeto .NET"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit
---

# Instrucoes da migracao aqui...
```

| Campo | O que faz |
|---|---|
| `name` | Nome do `/slash-command` |
| `description` | Quando o Claude deve usar automaticamente |
| `user-invocable` | Se aparece no menu `/` |
| `allowed-tools` | Ferramentas liberadas durante execucao |
| `context: fork` | Roda em contexto isolado (subagent) |
| `argument-hint` | Dica de argumentos no autocomplete |

### Agents — Executores isolados

Arquivos `.md` em `.claude/agents/`. Definem assistentes especializados que rodam em **contexto proprio**, separados da conversa principal.

Diferenca chave vs skills:

| | Skill | Agent |
|---|---|---|
| Contexto | Compartilha com a conversa | Isolado |
| Ideal para | Receitas, instrucoes inline | Tarefas pesadas, paralelas |
| Output | Inline na conversa | Resumo ao final |

### Hooks — Guardrails automaticos

Definidos em `.claude/settings.json`. Sao **scripts shell que executam automaticamente** em momentos especificos do ciclo de vida do Claude Code.

Diferente dos outros mecanismos, hooks sao **deterministicos** — sempre executam, o Claude nao pode ignorar.

| Hook | Evento | O que faz |
|---|---|---|
| `pre-commit-guard.sh` | `PreToolUse` (Bash com `git commit`) | Roda `dotnet build` e `dotnet test`. Bloqueia commit se falhar |
| `pre-push-guard.sh` | `PreToolUse` (Bash com `git push`) | Rebuild + testes completos antes de push |
| `post-edit-format.sh` | `PostToolUse` (Edit/Write em `*.cs`) | Roda `dotnet format` no arquivo editado |

O script retorna **exit code 2** para bloquear a acao, com mensagem de erro no stderr que o Claude recebe como feedback.

### Rules — Padroes scoped

Arquivos em `.claude/rules/` com frontmatter `paths:` que limita quando a regra e carregada:

```yaml
---
paths:
  - "**/*.cs"
---
# So carrega quando trabalhando com arquivos .cs
```

## Como cada peca funciona junto

```
CLAUDE.md         →  Contexto. Lido no inicio. Nao executa nada.
Skills            →  /slash-commands. Receitas inline na conversa.
Agents            →  Especialistas isolados. Bom pra paralelo/pesado.
Hooks             →  Automacao que SEMPRE roda. Formatar, bloquear, validar.
Rules             →  Padroes de codigo por tipo de arquivo. Scoped.
```

## Uso

### Interativo (dentro do Claude Code)

```bash
# Migrar um projeto especifico
/migrate-mediatr ./caminho/do/projeto

# Ou via orquestrador generico
/migrate mediatr ./caminho/do/projeto
```

### Em massa (headless, via shell)

```bash
# Edite repos.txt com os repositorios (um por linha, formato owner/repo)
echo "myorg/order-service" >> repos.txt
echo "myorg/product-service" >> repos.txt

# Execute a migracao em paralelo
./migrate.sh mediatr repos.txt

# Com limite de paralelismo
./migrate.sh mediatr repos.txt --max-parallel 5
```

Cada repositorio e processado por uma instancia independente do Claude Code (`claude -p`), rodando em paralelo.

### Fluxo de migracao (11 passos)

Cada repo passa por:

1. `git pull`
2. `dotnet build` — valida estado inicial
3. `dotnet test` — roda testes existentes
4. Cria testes se nao existirem (xUnit)
5. Roda testes novos
6. Aplica a receita de migracao (skill)
7. `dotnet build` — valida pos-migracao
8. `dotnet test` — valida pos-migracao
9. Cria branch `migration/{tipo}`
10. Commit com co-author
11. Push + abre PR

Os passos 2, 7, 8 sao reforcados por **hooks** — mesmo que o Claude "esqueca" de buildar, o hook bloqueia o commit/push se o build ou testes falharem.

## Adicionando uma nova migracao

Para criar uma migracao de MassTransit, por exemplo:

```bash
mkdir -p .claude/skills/migrate-masstransit
```

Crie `.claude/skills/migrate-masstransit/SKILL.md`:

```yaml
---
name: migrate-masstransit
description: "Remove MassTransit e substitui por implementacao nativa"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
argument-hint: "<caminho-do-projeto>"
context: fork
---

# Instrucoes especificas da migracao MassTransit
...
```

Pronto. O `migrate.sh`, o agent `dotnet-migrator` e os hooks **nao precisam mudar** — sao genericos.

```bash
./migrate.sh masstransit repos-masstransit.txt
```

## Repositorios de exemplo

Esta POC inclui dois projetos .NET com MediatR usados para demonstracao:

- [poc-order-service](https://github.com/marcopollivier/poc-order-service) — API de pedidos com CQRS/MediatR
- [poc-product-service](https://github.com/marcopollivier/poc-product-service) — API de produtos com CQRS/MediatR

Ambos tiveram PRs de migracao abertas automaticamente por este framework:

- [poc-order-service PR #1](https://github.com/marcopollivier/poc-order-service/pull/1)
- [poc-product-service PR #1](https://github.com/marcopollivier/poc-product-service/pull/1)
