# Claude .Net

## Estrutura final

  .claude/
  ├── settings.json                          # 🔒 Hooks de guardrail
  ├── hooks/
  │   ├── pre-commit-guard.sh                #    Bloqueia commit se build/test falhar
  │   ├── pre-push-guard.sh                  #    Bloqueia push se build/test falhar
  │   └── post-edit-format.sh                #    Roda dotnet format após editar .cs
  ├── rules/
  │   └── dotnet.md                          # 📏 Padrões .NET (scoped para *.cs)
  ├── skills/
  │   ├── migrate/SKILL.md                   # 🎯 /migrate — orquestrador genérico
  │   └── migrate-mediatr/SKILL.md           # 📋 /migrate-mediatr — receita específica
  ├── agents/
  │   └── dotnet-migrator.md                 # 🤖 Executor isolado de migrações
  CLAUDE.md                                  # 📖 Contexto geral do framework
  migrate.sh                                 # 🚀 Execução em massa via shell
  repos.txt                                  # 📝 Lista de repositórios

  Como cada peça funciona

  ┌────────────────────────┬──────────────────────────────────────┬───────────────────────────────────────────┐
  │          Peça          │                Papel                 │                  Exemplo                  │
  ├────────────────────────┼──────────────────────────────────────┼───────────────────────────────────────────┤
  │ CLAUDE.md              │ Contexto — "o que é este projeto"    │ Lido automaticamente em toda conversa     │
  ├────────────────────────┼──────────────────────────────────────┼───────────────────────────────────────────┤
  │ Skill /migrate         │ Orquestrador — "qual migração rodar" │ /migrate mediatr ./projeto                │
  ├────────────────────────┼──────────────────────────────────────┼───────────────────────────────────────────┤
  │ Skill /migrate-mediatr │ Receita — "o que mudar no código"    │ Detalhes de MediatR → Dispatcher          │
  ├────────────────────────┼──────────────────────────────────────┼───────────────────────────────────────────┤
  │ Agent dotnet-migrator  │ Executor — "quem faz o trabalho"     │ Roda isolado, segue os 11 passos          │
  ├────────────────────────┼──────────────────────────────────────┼───────────────────────────────────────────┤
  │ Hook pre-commit        │ Guardrail — "build passa?"           │ Bloqueia commit se dotnet build falhar    │
  ├────────────────────────┼──────────────────────────────────────┼───────────────────────────────────────────┤
  │ Hook pre-push          │ Guardrail — "testes passam?"         │ Bloqueia push se dotnet test falhar       │
  ├────────────────────────┼──────────────────────────────────────┼───────────────────────────────────────────┤
  │ Hook post-edit         │ Formatação — "código limpo?"         │ dotnet format automático após editar .cs  │
  ├────────────────────────┼──────────────────────────────────────┼───────────────────────────────────────────┤
  │ Rule dotnet.md         │ Padrões — "como escrever código"     │ Scoped para **/*.cs, convenções de naming │
  └────────────────────────┴──────────────────────────────────────┴───────────────────────────────────────────┘

  Para adicionar uma nova migração (ex: MassTransit)

  Basta criar um arquivo:

  .claude/skills/migrate-masstransit/SKILL.md

  Com o frontmatter + receita. O migrate.sh, o agent e os hooks não precisam mudar — tudo já é genérico.

## Uso futuro

  ./migrate.sh masstransit repos-masstransit.txt --max-parallel 5
