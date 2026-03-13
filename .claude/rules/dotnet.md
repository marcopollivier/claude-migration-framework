---
paths:
  - "**/*.cs"
  - "**/*.csproj"
---

# Padrões .NET para Migrações

## Estrutura de projeto
- Um namespace por projeto, derivado do nome do .csproj
- Pastas mapeiam para namespaces: `Commands/`, `Queries/`, `Handlers/`, `Models/`, `Infrastructure/`, `Controllers/`
- Projeto de testes: `{Projeto}.Tests/` usando xUnit

## Convenções de código
- File-scoped namespaces: `namespace Foo;` (não `namespace Foo { }`)
- Uma classe/interface/record por arquivo
- Nome do arquivo = nome do tipo
- Usar `var` quando o tipo é óbvio
- Async/await em todo I/O
- CancellationToken propagado em toda cadeia async

## Convenções de teste
- Um arquivo de teste por handler/service
- Nome: `{ClasseSobTeste}Tests.cs`
- Método: `{Metodo}_{Cenario}_{Esperado}` ou `{Metodo}_Should{Resultado}`
- Instanciar handlers diretamente (não usar mocks para esta POC)
- Usar xUnit: `[Fact]` para testes simples, `[Theory]` para parametrizados

## DI / Program.cs
- Registrar interfaces com implementações concretas
- Usar `AddScoped` para handlers e dispatchers
- Usar `AddControllers` + `MapControllers` para APIs

## Migrações
- Ao remover um pacote NuGet, verificar TODOS os .csproj (incluindo testes)
- Ao trocar interfaces, buscar `using {PackageAntigo};` em TODOS os .cs
- Sempre verificar se o namespace antigo ficou em algum arquivo após migração
