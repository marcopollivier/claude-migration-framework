#!/bin/bash
# detect.sh — Detecta se a migração MediatR é necessária neste projeto .NET
#
# Retorna:
#   0 — migração necessária (MediatR encontrado)
#   1 — migração não necessária (MediatR não presente)
#
# Uso: ./detect.sh <repo-dir>

REPO_DIR="${1:-}"

if [ -z "$REPO_DIR" ] || [ ! -d "$REPO_DIR" ]; then
    echo "Usage: detect.sh <repo-dir>" >&2
    exit 2
fi

# Verifica referência ao pacote MediatR em .csproj
if grep -rl 'PackageReference.*MediatR' "$REPO_DIR" --include="*.csproj" > /dev/null 2>&1; then
    echo "MediatR package reference found" >&2
    exit 0
fi

# Verifica using MediatR em arquivos .cs
if grep -rl 'using MediatR' "$REPO_DIR" --include="*.cs" > /dev/null 2>&1; then
    echo "MediatR using directive found" >&2
    exit 0
fi

# Verifica AddMediatR no Program.cs / Startup.cs
if grep -rl 'AddMediatR\|IMediator' "$REPO_DIR" --include="*.cs" > /dev/null 2>&1; then
    echo "MediatR service registration found" >&2
    exit 0
fi

# Nenhum vestígio de MediatR — migração não necessária
echo "No MediatR usage found — skipping" >&2
exit 1
