# Migration Framework — Claude Code

Framework genérico para executar migrações em massa em repositórios .NET usando Claude Code.

## Estrutura

```
.claude/
├── skills/
│   ├── migrate/SKILL.md              # /migrate — orquestrador genérico
│   └── migrate-mediatr/SKILL.md      # /migrate-mediatr — receita MediatR
├── agents/
│   └── dotnet-migrator.md            # Executor isolado de migrações .NET
├── rules/
│   └── dotnet.md                     # Padrões de código .NET (scoped *.cs)
├── settings.json                     # Hooks de guardrail
repos.txt                             # Lista de repos (owner/repo, um por linha)
migrate.sh                            # Orquestrador shell para execução em massa
```

## Como funciona

1. **Skills** definem O QUE fazer — cada tipo de migração é uma skill separada
2. **Agents** definem QUEM faz — executor isolado com ferramentas e modelo específicos
3. **Hooks** garantem QUALIDADE — build e testes são validados automaticamente antes de commit/push
4. **Rules** definem PADRÕES — convenções de código aplicadas por escopo de arquivo

## Fluxo de migração (11 passos)

```
git pull → build → test → [criar testes] → [rodar testes] → aplicar migração → build → test → commit → push → PR
           ▲               hooks garantem                                       ▲
           └── hook valida build antes de prosseguir                            └── hook valida build+test antes de commit
```

## Migrações disponíveis

| Skill | Descrição | Branch |
|---|---|---|
| `/migrate-mediatr` | Remove MediatR → dispatcher nativo | `migration/remove-mediatr` |

Para adicionar uma nova migração, crie uma pasta em `.claude/skills/migrate-{nome}/SKILL.md`.

## Uso interativo

```bash
# Migrar um projeto específico
/migrate-mediatr ./caminho/do/projeto

# Orquestrar migração genérica
/migrate mediatr ./caminho/do/projeto
```

## Uso em massa (headless)

```bash
# Edite repos.txt com os repositórios
./migrate.sh mediatr repos.txt
```

## Convenções

- Branches: `migration/{nome-da-migracao}`
- Commits: `refactor: {descrição da migração}`
- PRs: título curto, body com summary + test plan
- Co-author: `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
