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
Interface totalmente genérica — sem `dynamic`, com segurança de tipos em tempo de compilação:
```csharp
namespace {Namespace}.Infrastructure;
public interface IDispatcher
{
    Task<TResponse> Send<TRequest, TResponse>(TRequest request, CancellationToken cancellationToken = default)
        where TRequest : IRequest<TResponse>;
}
```

### Infrastructure/Dispatcher.cs
Implementação sem reflection nem `dynamic` — o handler é resolvido diretamente pelo tipo genérico:
```csharp
namespace {Namespace}.Infrastructure;
public class Dispatcher : IDispatcher
{
    private readonly IServiceProvider _serviceProvider;

    public Dispatcher(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
    }

    public async Task<TResponse> Send<TRequest, TResponse>(TRequest request, CancellationToken cancellationToken = default)
        where TRequest : IRequest<TResponse>
    {
        var handler = _serviceProvider.GetService<IRequestHandler<TRequest, TResponse>>()
            ?? throw new InvalidOperationException(
                $"No handler registered for '{typeof(TRequest).Name}'. " +
                $"Make sure IRequestHandler<{typeof(TRequest).Name}, {typeof(TResponse).Name}> is registered in the DI container.");
        return await handler.Handle(request, cancellationToken);
    }
}
```

### Infrastructure/ServiceCollectionExtensions.cs
Registro automático de handlers via assembly scanning — evita registros hardcoded que quebram em runtime:
```csharp
namespace {Namespace}.Infrastructure;
public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddHandlers(this IServiceCollection services, Assembly assembly)
    {
        var handlerInterface = typeof(IRequestHandler<,>);
        var handlers = assembly.GetTypes()
            .Where(t => t.IsClass && !t.IsAbstract)
            .SelectMany(t => t.GetInterfaces()
                .Where(i => i.IsGenericType && i.GetGenericTypeDefinition() == handlerInterface)
                .Select(i => (Handler: t, Interface: i)));

        foreach (var (handler, iface) in handlers)
            services.AddScoped(iface, handler);

        return services;
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
- Atualizar chamadas: `await _dispatcher.Send(request)` → `await _dispatcher.Send<TRequest, TResponse>(request)`
  - Exemplo: `await _dispatcher.Send<GetCampaignQuery, CampaignDto>(query, cancellationToken)`

### No Program.cs / módulo de IoC:
- Remover `builder.Services.AddMediatR(...)`
- Substituir registros individuais de handlers pelo scanning automático:
```csharp
using {Namespace}.Infrastructure;
using System.Reflection;

builder.Services.AddScoped<IDispatcher, Dispatcher>();
builder.Services.AddHandlers(typeof({SomeHandler}).Assembly);
```
- Remover quaisquer linhas `AddScoped<IRequestHandler<...>>` hardcoded

### No .csproj:
- Executar `dotnet remove package MediatR`
- Executar `dotnet remove package MediatR.Extensions.Microsoft.DependencyInjection` (se presente)

## Nos testes (se existirem):
- Mesmas substituições de using e interfaces
- Substituir mocks de `IMediator` por mocks de `IDispatcher`
- Verificar chamadas: `.Send<TRequest, TResponse>(...)` em vez de `.Send(...)`
- Remover pacotes MediatR dos projetos de teste também
- Nomear helpers de verificação corretamente: usar `ShouldSendToDispatcherAtLeastOnce` (não `ShouldSentTo...`)

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
