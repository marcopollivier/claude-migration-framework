#!/bin/bash
# Hook: PreToolUse — bloqueia git commit se build ou testes falharem
# Exit 0 = permite, Exit 2 = bloqueia (mensagem vai pro Claude)

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Só intercepta comandos git commit
if ! echo "$COMMAND" | grep -q "git commit"; then
    exit 0
fi

# Descobre o diretório do projeto (procura .csproj subindo)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROJECT_DIR=""

# Tenta encontrar um .csproj ou .sln no CWD ou nos pais
SEARCH_DIR="$CWD"
while [ "$SEARCH_DIR" != "/" ]; do
    if ls "$SEARCH_DIR"/*.csproj 2>/dev/null | head -1 > /dev/null 2>&1; then
        PROJECT_DIR="$SEARCH_DIR"
        break
    fi
    if ls "$SEARCH_DIR"/*.sln 2>/dev/null | head -1 > /dev/null 2>&1; then
        PROJECT_DIR="$SEARCH_DIR"
        break
    fi
    SEARCH_DIR=$(dirname "$SEARCH_DIR")
done

# Se não encontrou projeto .NET, permite o commit
if [ -z "$PROJECT_DIR" ]; then
    exit 0
fi

cd "$PROJECT_DIR"

# Guardrail 1: Build deve passar
echo "🔨 [hook] Validando build antes do commit..." >&2
BUILD_OUTPUT=$(dotnet build 2>&1)
if [ $? -ne 0 ]; then
    echo "❌ [hook] COMMIT BLOQUEADO: build falhou. Corrija os erros antes de commitar." >&2
    echo "" >&2
    echo "$BUILD_OUTPUT" | tail -20 >&2
    exit 2
fi

# Guardrail 2: Testes devem passar (se existirem)
if ls "$PROJECT_DIR"/**/*.Tests.csproj 2>/dev/null | head -1 > /dev/null 2>&1 || \
   ls "$PROJECT_DIR"/*Tests*/*.csproj 2>/dev/null | head -1 > /dev/null 2>&1; then
    echo "🧪 [hook] Validando testes antes do commit..." >&2
    TEST_OUTPUT=$(dotnet test --no-build 2>&1)
    if [ $? -ne 0 ]; then
        echo "❌ [hook] COMMIT BLOQUEADO: testes falharam. Corrija antes de commitar." >&2
        echo "" >&2
        echo "$TEST_OUTPUT" | tail -20 >&2
        exit 2
    fi
fi

echo "✅ [hook] Build e testes OK. Commit permitido." >&2
exit 0
