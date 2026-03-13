#!/bin/bash
# Hook: PostToolUse — roda dotnet format após edição de arquivos .cs
# Garante que o código sempre segue as convenções de formatação

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Só age em arquivos .cs
if [[ "$FILE_PATH" != *.cs ]]; then
    exit 0
fi

# Verifica se o arquivo existe
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Encontra o .csproj mais próximo
DIR=$(dirname "$FILE_PATH")
PROJECT_FILE=""
while [ "$DIR" != "/" ]; do
    CSPROJ=$(ls "$DIR"/*.csproj 2>/dev/null | head -1)
    if [ -n "$CSPROJ" ]; then
        PROJECT_FILE="$CSPROJ"
        break
    fi
    DIR=$(dirname "$DIR")
done

if [ -z "$PROJECT_FILE" ]; then
    exit 0
fi

# Formata apenas o arquivo editado
dotnet format "$PROJECT_FILE" --include "$FILE_PATH" 2>/dev/null

exit 0
