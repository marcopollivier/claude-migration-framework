---
name: migrate-owner
description: "Verifica e corrige o owner no CODEOWNERS de um projeto. @neon/cards → PR para @neon/cards-engagement. Outros owners → reporta."
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
argument-hint: "<caminho-do-projeto>"
---

# Verificação e correção de CODEOWNERS owner

Verifique e corrija o owner no CODEOWNERS do projeto em `$ARGUMENTS`.

## Regras

| Owner encontrado          | Ação                                                        |
|---------------------------|-------------------------------------------------------------|
| `@neon/cards-engagement`  | ✅ Correto — nenhuma ação necessária                        |
| `@neon/cards`             | 🔄 Criar PR para substituir por `@neon/cards-engagement`   |
| Qualquer outro / ausente  | ⚠️  Reportar no console (não alterar)                      |

## Passos

1. Localize o arquivo CODEOWNERS em (nesta ordem):
   - `.github/CODEOWNERS`
   - `CODEOWNERS`
   - `docs/CODEOWNERS`

2. Se não encontrado → informe "No CODEOWNERS file found" e pare.

3. Se contém `@neon/cards-engagement` → informe "Owner already correct" e pare.

4. Se contém `@neon/cards` (mas NÃO `@neon/cards-engagement`):
   - Crie branch `fix/update-codeowners-owner`
   - Substitua `@neon/cards` por `@neon/cards-engagement` (cuidado para não alterar `@neon/cards-engagement`)
   - Commit: `fix: update CODEOWNERS owner to @neon/cards-engagement`
   - Push e abra PR com título: `fix: update CODEOWNERS owner to @neon/cards-engagement`
   - Co-author: `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`

5. Se contém outro owner → informe quais são os owners encontrados e pare.

## Formato do PR body

```
## Summary

- Updates `CODEOWNERS` replacing `@neon/cards` → `@neon/cards-engagement`

## Test plan

- [ ] CODEOWNERS contains `@neon/cards-engagement`
- [ ] No remaining references to bare `@neon/cards`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```
