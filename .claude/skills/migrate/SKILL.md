---
name: migrate
description: "Orquestra uma migração completa em um projeto .NET. Recebe o tipo de migração e o caminho do projeto. Usa o agent dotnet-migrator para execução isolada."
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, Agent
argument-hint: "<tipo-migracao> <caminho-do-projeto>"
---

# Orquestrador de Migração

Você está orquestrando uma migração do tipo `$ARGUMENTS`.

## Instruções

1. Identifique o tipo de migração (primeiro argumento) e o caminho do projeto (segundo argumento)
2. Carregue a skill específica da migração: `/migrate-{tipo}`
3. Delegue a execução para o agent `dotnet-migrator`, passando:
   - O caminho do projeto
   - As instruções específicas da migração

## Se invocado sem argumentos

Liste as migrações disponíveis buscando skills que começam com `migrate-` em:
- `.claude/skills/`
- `~/.claude/skills/`

## Se invocado com múltiplos repos

Para cada repositório, lance um agent `dotnet-migrator` em paralelo usando `run_in_background: true`.
Aguarde todos completarem e reporte o resultado consolidado.

## Formato de saída esperado

```
Migration Report
================
| Repo | Status | PR | Tests |
|------|--------|----|-------|
| repo1 | OK | #1 | 4/4 |
| repo2 | FAIL | - | 2/3 |
```
