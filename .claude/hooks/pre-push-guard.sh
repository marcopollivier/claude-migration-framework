#!/bin/bash
# Hook: PreToolUse — bloqueia git push se build ou testes falharem
# Mais rigoroso que o pre-commit: rebuilda do zero

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Só intercepta comandos git push
if ! echo "$COMMAND" | grep -q "git push"; then
    exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROJECT_DIR=""

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

if [ -z "$PROJECT_DIR" ]; then
    exit 0
fi

cd "$PROJECT_DIR"

# Rebuild completo antes de push
echo "🔨 [hook] Rebuild completo antes do push..." >&2
BUILD_OUTPUT=$(dotnet build 2>&1)
if [ $? -ne 0 ]; then
    echo "❌ [hook] PUSH BLOQUEADO: build falhou." >&2
    echo "$BUILD_OUTPUT" | tail -20 >&2
    exit 2
fi

# Testes completos antes de push
if ls "$PROJECT_DIR"/**/*.Tests.csproj 2>/dev/null | head -1 > /dev/null 2>&1 || \
   ls "$PROJECT_DIR"/*Tests*/*.csproj 2>/dev/null | head -1 > /dev/null 2>&1; then
    echo "🧪 [hook] Rodando testes antes do push..." >&2
    TEST_OUTPUT=$(dotnet test 2>&1)
    if [ $? -ne 0 ]; then
        echo "❌ [hook] PUSH BLOQUEADO: testes falharam." >&2
        echo "$TEST_OUTPUT" | tail -20 >&2
        exit 2
    fi
fi

echo "✅ [hook] Build e testes OK. Push permitido." >&2
exit 0
