---
name: migrate-mediatr
description: "Receita de migração: remove MediatR de um projeto .NET e substitui por um dispatcher nativo. Use quando o usuário mencionar migração de MediatR, remover MediatR, ou substituir MediatR."
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
argument-hint: "<caminho-do-projeto>"
context: fork
---

# Migração: MediatR → Dispatcher Nativo

Migrar o projeto em `$ARGUMENTS` removendo a dependência do MediatR e substituindo por um dispatcher nativo.

## Contexto

O MediatR é uma biblioteca de mediação para .NET que implementa o padrão Mediator/CQRS. Esta migração remove essa dependência externa, substituindo por interfaces e implementação próprias, reduzindo acoplamento com terceiros.

## O que criar

### Infrastructure/IRequest.cs
```csharp
namespace {Namespace}.Infrastructure;
public interface IRequest<TResponse> { }
```

### Infrastructure/IRequestHandler.cs
```csharp
namespace {Namespace}.Infrastructure;
public interface IRequestHandler<TRequest, TResponse> where TRequest : IRequest<TResponse>
{
    Task<TResponse> Handle(TRequest request, CancellationToken cancellationToken = default);
}
```

### Infrastructure/IDispatcher.cs
```csharp
namespace {Namespace}.Infrastructure;
public interface IDispatcher
{
    Task<TResponse> Send<TResponse>(IRequest<TResponse> request, CancellationToken cancellationToken = default);
}
```

### Infrastructure/Dispatcher.cs
```csharp
namespace {Namespace}.Infrastructure;
public class Dispatcher : IDispatcher
{
    private readonly IServiceProvider _serviceProvider;
    public Dispatcher(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
    }
    public async Task<TResponse> Send<TResponse>(IRequest<TResponse> request, CancellationToken cancellationToken = default)
    {
        var handlerType = typeof(IRequestHandler<,>).MakeGenericType(request.GetType(), typeof(TResponse));
        dynamic handler = _serviceProvider.GetRequiredService(handlerType);
        return await handler.Handle((dynamic)request, cancellationToken);
    }
}
```

## O que alterar

### Em todos os Commands e Queries:
- Substituir `using MediatR;` por `using {Namespace}.Infrastructure;`
- A interface `IRequest<T>` mantém o mesmo nome (agora é local)

### Em todos os Handlers:
- Substituir `using MediatR;` por `using {Namespace}.Infrastructure;`
- `IRequestHandler<TRequest, TResponse>` agora vem do Infrastructure
- Assinatura do Handle: `Task<TResponse> Handle(TRequest request, CancellationToken cancellationToken = default)`

### Nos Controllers:
- Substituir `IMediator` por `IDispatcher`
- Substituir `_mediator` por `_dispatcher`
- Substituir `using MediatR;` por `using {Namespace}.Infrastructure;`

### No Program.cs:
- Remover `builder.Services.AddMediatR(...)`
- Adicionar `builder.Services.AddScoped<IDispatcher, Dispatcher>();`
- Registrar cada handler individualmente:
  `builder.Services.AddScoped<IRequestHandler<CreateXxxCommand, Guid>, CreateXxxCommandHandler>();`

### No .csproj:
- Executar `dotnet remove package MediatR`

## Nos testes (se existirem):
- Mesmas substituições de using e interfaces
- Remover `dotnet remove package MediatR` do projeto de testes também

## Branch e PR

- Branch: `migration/remove-mediatr`
- Commit: `refactor: replace MediatR with native dispatcher`
- PR title: `refactor: replace MediatR with native dispatcher`
- PR body deve listar: o que foi removido, o que foi adicionado, resultados dos testes

## Detecção

Para identificar se um projeto usa MediatR, procure por:
- `<PackageReference Include="MediatR"` no .csproj
- `using MediatR;` nos arquivos .cs
- `IMediator` nos controllers
- `AddMediatR` no Program.cs
