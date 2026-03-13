#!/bin/bash
# migrate.sh - Orquestra migração em massa usando Claude Code agents em paralelo
#
# Uso: ./migrate.sh <tipo-migracao> [repos.txt] [--max-parallel N]
#
# Exemplos:
#   ./migrate.sh mediatr                       # migra repos de repos.txt
#   ./migrate.sh mediatr repos-lote2.txt       # migra repos de arquivo específico
#   ./migrate.sh mediatr repos.txt --max-parallel 5  # limita paralelismo
#
# Cada repositório é migrado em paralelo por uma instância do Claude Code
# usando o agent dotnet-migrator e a skill migrate-{tipo}.

set -euo pipefail

# ─── Args ───────────────────────────────────────────────────────────
MIGRATION_TYPE="${1:-}"
REPOS_FILE="${2:-repos.txt}"
MAX_PARALLEL=0  # 0 = sem limite

shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-parallel) MAX_PARALLEL="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$MIGRATION_TYPE" ]; then
    echo "Usage: ./migrate.sh <tipo-migracao> [repos.txt] [--max-parallel N]"
    echo ""
    echo "Migrações disponíveis:"
    for skill_dir in .claude/skills/migrate-*/; do
        if [ -d "$skill_dir" ]; then
            name=$(basename "$skill_dir" | sed 's/^migrate-//')
            desc=$(grep -m1 'description:' "$skill_dir/SKILL.md" | sed 's/.*description: *"\(.*\)"/\1/' | head -c 80)
            echo "  $name  — $desc"
        fi
    done
    exit 0
fi

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$BASE_DIR/workspaces"
LOG_DIR="$BASE_DIR/logs"
SKILL_DIR="$BASE_DIR/.claude/skills/migrate-${MIGRATION_TYPE}"
AGENT_FILE="$BASE_DIR/.claude/agents/dotnet-migrator.md"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ─── Colors ─────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Validation ─────────────────────────────────────────────────────
if [ ! -d "$SKILL_DIR" ]; then
    echo -e "${RED}Error: skill 'migrate-${MIGRATION_TYPE}' not found in .claude/skills/${NC}"
    exit 1
fi

if [ ! -f "$REPOS_FILE" ]; then
    echo -e "${RED}Error: repos file '$REPOS_FILE' not found${NC}"
    exit 1
fi

mkdir -p "$WORK_DIR" "$LOG_DIR"

# Read repos (skip empty lines and comments)
mapfile -t REPOS < <(grep -v '^\s*#' "$REPOS_FILE" | grep -v '^\s*$')

# Read the migration skill content
SKILL_CONTENT=$(cat "$SKILL_DIR/SKILL.md")

echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN} Migration Orchestrator${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e " Type:         ${YELLOW}${MIGRATION_TYPE}${NC}"
echo -e " Repos:        ${#REPOS[@]}"
echo -e " Max parallel: ${MAX_PARALLEL:-unlimited}"
echo -e " Workdir:      $WORK_DIR"
echo -e " Logs:         $LOG_DIR"
echo ""

# ─── Migrate a single repo ──────────────────────────────────────────
migrate_repo() {
    local repo="$1"
    local repo_name=$(basename "$repo")
    local repo_dir="$WORK_DIR/$repo_name"
    local log_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.log"
    local result_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.result.json"

    echo -e "${YELLOW}[$repo_name]${NC} Starting migration..."

    # Clone or pull
    if [ -d "$repo_dir" ]; then
        (cd "$repo_dir" && git checkout main 2>/dev/null || git checkout master 2>/dev/null; git pull) >> "$log_file" 2>&1
    else
        gh repo clone "$repo" "$repo_dir" >> "$log_file" 2>&1
    fi

    # Launch Claude Code with the agent instructions + skill recipe
    claude -p \
        --allowedTools "Bash,Read,Write,Edit,Glob,Grep" \
        "You are the dotnet-migrator agent. Your task is to migrate the project at: $repo_dir

## Migration Recipe (from skill migrate-${MIGRATION_TYPE})

${SKILL_CONTENT}

## Your Instructions

Follow the 11-step migration flow:
1. cd to $repo_dir and git pull
2. dotnet build — fix if fails
3. dotnet test — note results
4. If no tests exist, create xUnit test project with tests for all handlers/services
5. Run tests — all must pass
6. Apply the migration recipe above
7. dotnet build — fix until clean
8. dotnet test — fix until all pass
9. git checkout -b migration/remove-${MIGRATION_TYPE}
10. git add -A && git commit (include Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>)
11. git push -u origin migration/remove-${MIGRATION_TYPE} && gh pr create

IMPORTANT:
- Work ONLY in $repo_dir
- Discover the namespace from existing code
- At the very end, output ONLY a JSON result:
{\"repo\": \"$repo\", \"status\": \"success|failure\", \"pr_url\": \"...\", \"tests_passed\": N, \"tests_total\": N, \"errors\": []}" \
        >> "$log_file" 2>&1

    local exit_code=$?

    # Try to extract the JSON result from the log
    grep -o '{\"repo\":.*}' "$log_file" | tail -1 > "$result_file" 2>/dev/null || true

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}[$repo_name]${NC} ✅ Migration completed"
    else
        echo -e "${RED}[$repo_name]${NC} ❌ Migration failed (check $log_file)"
    fi

    return $exit_code
}

export -f migrate_repo
export WORK_DIR LOG_DIR TIMESTAMP MIGRATION_TYPE SKILL_CONTENT GREEN RED YELLOW CYAN NC

# ─── Launch parallel migrations ─────────────────────────────────────
echo "Launching ${#REPOS[@]} migrations..."
echo ""

PIDS=()
RUNNING=0

for repo in "${REPOS[@]}"; do
    # Throttle if max-parallel is set
    if [ "$MAX_PARALLEL" -gt 0 ]; then
        while [ "$RUNNING" -ge "$MAX_PARALLEL" ]; do
            # Wait for any child to finish
            wait -n 2>/dev/null || true
            RUNNING=$((RUNNING - 1))
        done
    fi

    migrate_repo "$repo" &
    PIDS+=($!)
    RUNNING=$((RUNNING + 1))
done

# ─── Wait and collect results ───────────────────────────────────────
echo "Waiting for all migrations to complete..."
echo ""

FAILED=0
SUCCEEDED=0

for i in "${!PIDS[@]}"; do
    pid=${PIDS[$i]}
    repo=${REPOS[$i]}
    repo_name=$(basename "$repo")

    if wait "$pid"; then
        ((SUCCEEDED++))
    else
        ((FAILED++))
    fi
done

# ─── Summary ────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN} Migration Summary${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e " Type:      ${MIGRATION_TYPE}"
echo -e " Total:     ${#REPOS[@]}"
echo -e " Succeeded: ${GREEN}${SUCCEEDED}${NC}"
echo -e " Failed:    ${RED}${FAILED}${NC}"
echo ""

# Print individual results if available
echo -e "${CYAN} Results:${NC}"
for repo in "${REPOS[@]}"; do
    repo_name=$(basename "$repo")
    result_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.result.json"
    if [ -f "$result_file" ] && [ -s "$result_file" ]; then
        status=$(jq -r '.status // "unknown"' "$result_file" 2>/dev/null || echo "unknown")
        pr_url=$(jq -r '.pr_url // "-"' "$result_file" 2>/dev/null || echo "-")
        tests=$(jq -r '"\(.tests_passed // "?")/\(.tests_total // "?")"' "$result_file" 2>/dev/null || echo "?/?")
        if [ "$status" = "success" ]; then
            echo -e "  ${GREEN}✅${NC} $repo_name  PR: $pr_url  Tests: $tests"
        else
            echo -e "  ${RED}❌${NC} $repo_name  PR: $pr_url  Tests: $tests"
        fi
    else
        echo -e "  ${YELLOW}⚠️${NC}  $repo_name  (no result file — check log)"
    fi
done

echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo "Logs: $LOG_DIR"
