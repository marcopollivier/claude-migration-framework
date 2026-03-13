#!/bin/bash
# migrate.sh - Orquestra migração em massa usando Claude Code agents em paralelo
#
# Uso: ./migrate.sh <tipo-migracao> [repos.txt] [--max-parallel N] [--batch-size N]
#
# Exemplos:
#   ./migrate.sh mediatr                              # migra todos os repos de repos.txt
#   ./migrate.sh mediatr repos.txt --batch-size 5    # processa apenas 5 repos por vez
#   ./migrate.sh mediatr repos.txt --max-parallel 3  # limita paralelismo
#   ./migrate.sh mediatr repos.txt --batch-size 5 --max-parallel 2
#
# Fluxo de saída dos repos:
#   repos.txt  → done.txt     (migração aplicada com sucesso)
#   repos.txt  → skipped.txt  (não-.NET ou migração não necessária)
#   repos.txt  → repos.txt    (falha — permanece para reprocessamento)

set -euo pipefail

# ─── Args ───────────────────────────────────────────────────────────
MIGRATION_TYPE="${1:-}"
REPOS_FILE="${2:-repos.txt}"
MAX_PARALLEL=0  # 0 = sem limite
BATCH_SIZE=0    # 0 = todos

shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-parallel) MAX_PARALLEL="$2"; shift 2 ;;
        --batch-size)   BATCH_SIZE="$2";   shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$MIGRATION_TYPE" ]; then
    echo "Usage: ./migrate.sh <tipo-migracao> [repos.txt] [--max-parallel N] [--batch-size N]"
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
DONE_FILE="$BASE_DIR/done.txt"
SKIPPED_FILE="$BASE_DIR/skipped.txt"
LOCK_FILE="$BASE_DIR/.migrate.lock"
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
touch "$DONE_FILE" "$SKIPPED_FILE"

# Read repos (skip empty lines and comments)
mapfile -t ALL_REPOS < <(grep -v '^\s*#' "$REPOS_FILE" | grep -v '^\s*$')

if [ "${#ALL_REPOS[@]}" -eq 0 ]; then
    echo -e "${GREEN}Nothing to do — repos.txt is empty.${NC}"
    exit 0
fi

# Apply batch size
if [ "$BATCH_SIZE" -gt 0 ] && [ "${#ALL_REPOS[@]}" -gt "$BATCH_SIZE" ]; then
    REPOS=("${ALL_REPOS[@]:0:$BATCH_SIZE}")
else
    REPOS=("${ALL_REPOS[@]}")
fi

# Read the migration skill content
SKILL_CONTENT=$(cat "$SKILL_DIR/SKILL.md")

echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN} Migration Orchestrator${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e " Type:         ${YELLOW}${MIGRATION_TYPE}${NC}"
echo -e " Processing:   ${#REPOS[@]} of ${#ALL_REPOS[@]} repos"
echo -e " Max parallel: ${MAX_PARALLEL:-unlimited}"
echo -e " Batch size:   ${BATCH_SIZE:-all}"
echo -e " Workdir:      $WORK_DIR"
echo -e " Logs:         $LOG_DIR"
echo -e ""
echo -e " Tracking:"
echo -e "   repos.txt   → pending / failed"
echo -e "   done.txt    → migrated successfully"
echo -e "   skipped.txt → not-.NET or migration not needed"
echo ""

# ─── Tracking (concurrency-safe via flock) ───────────────────────────
update_tracking() {
    local repo="$1"
    local disposition="$2"  # done | skipped
    local reason="${3:-}"

    (
        flock 9
        # Remove from repos.txt atomically
        grep -v "^${repo}[[:space:]]*$\|^${repo}[[:space:]]*#" "$REPOS_FILE" \
            > "${REPOS_FILE}.tmp" && mv "${REPOS_FILE}.tmp" "$REPOS_FILE"
        # Append to target file
        if [ "$disposition" = "done" ]; then
            echo "$repo" >> "$DONE_FILE"
        else
            if [ -n "$reason" ]; then
                echo "$repo  # $reason" >> "$SKIPPED_FILE"
            else
                echo "$repo" >> "$SKIPPED_FILE"
            fi
        fi
    ) 9>"$LOCK_FILE"
}
export -f update_tracking
export REPOS_FILE DONE_FILE SKIPPED_FILE LOCK_FILE

# ─── Migrate a single repo ───────────────────────────────────────────
migrate_repo() {
    local repo="$1"
    local repo_name
    repo_name=$(basename "$repo")
    local repo_dir="$WORK_DIR/$repo_name"
    local log_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.log"
    local result_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.result.json"
    local disp_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.disposition"

    echo -e "${YELLOW}[$repo_name]${NC} Cloning/pulling..."

    # Clone or pull
    if [ -d "$repo_dir" ]; then
        (cd "$repo_dir" \
            && git checkout main 2>/dev/null || git checkout master 2>/dev/null \
            && git pull) >> "$log_file" 2>&1
    else
        if ! gh repo clone "$repo" "$repo_dir" >> "$log_file" 2>&1; then
            echo -e "${RED}[$repo_name]${NC} ❌ Failed to clone — stays in repos.txt"
            echo "failed:clone-error" > "$disp_file"
            return 1
        fi
    fi

    # ── Check 1: is this a .NET project? ───────────────────────────
    if ! find "$repo_dir" -name "*.csproj" -maxdepth 6 2>/dev/null | grep -q .; then
        echo -e "${YELLOW}[$repo_name]${NC} ⏭️  Not a .NET project — skipping"
        echo "skipped:not-dotnet" > "$disp_file"
        update_tracking "$repo" "skipped" "not-dotnet"
        return 0
    fi

    # ── Check 2: does this project need the migration? ─────────────
    local detect_script="$SKILL_DIR/detect.sh"
    if [ -f "$detect_script" ]; then
        if ! bash "$detect_script" "$repo_dir" >> "$log_file" 2>&1; then
            echo -e "${YELLOW}[$repo_name]${NC} ⏭️  No migration needed — skipping"
            echo "skipped:not-needed" > "$disp_file"
            update_tracking "$repo" "skipped" "not-needed:${MIGRATION_TYPE}"
            return 0
        fi
    fi

    echo -e "${YELLOW}[$repo_name]${NC} Starting migration..."

    # ── Run migration via Claude Code ──────────────────────────────
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
        echo "done" > "$disp_file"
        update_tracking "$repo" "done"
    else
        echo -e "${RED}[$repo_name]${NC} ❌ Migration failed — stays in repos.txt for retry"
        echo "failed:migration-error" > "$disp_file"
    fi

    return $exit_code
}

export -f migrate_repo
export WORK_DIR LOG_DIR TIMESTAMP MIGRATION_TYPE SKILL_CONTENT SKILL_DIR GREEN RED YELLOW CYAN NC

# ─── Launch parallel migrations ──────────────────────────────────────
echo "Launching ${#REPOS[@]} migrations..."
echo ""

PIDS=()
RUNNING=0

for repo in "${REPOS[@]}"; do
    if [ "$MAX_PARALLEL" -gt 0 ]; then
        while [ "$RUNNING" -ge "$MAX_PARALLEL" ]; do
            wait -n 2>/dev/null || true
            RUNNING=$((RUNNING - 1))
        done
    fi

    migrate_repo "$repo" &
    PIDS+=($!)
    RUNNING=$((RUNNING + 1))
done

# ─── Wait and collect results ────────────────────────────────────────
echo "Waiting for all migrations to complete..."
echo ""

FAILED=0
SUCCEEDED=0
SKIPPED_COUNT=0

for i in "${!PIDS[@]}"; do
    pid=${PIDS[$i]}
    repo=${REPOS[$i]}
    repo_name=$(basename "$repo")
    disp_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.disposition"

    wait "$pid" || true

    disp="unknown"
    [ -f "$disp_file" ] && disp=$(cat "$disp_file")

    case "$disp" in
        done)            ((SUCCEEDED++)) ;;
        skipped:*)       ((SKIPPED_COUNT++)) ;;
        failed:*|unknown) ((FAILED++)) ;;
    esac
done

# ─── Summary ─────────────────────────────────────────────────────────
REMAINING=$(grep -v '^\s*#' "$REPOS_FILE" 2>/dev/null | grep -v '^\s*$' | wc -l | tr -d ' ')

echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN} Migration Summary${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e " Type:         ${MIGRATION_TYPE}"
echo -e " Processed:    ${#REPOS[@]}"
echo -e " Migrated:     ${GREEN}${SUCCEEDED}${NC}  → done.txt"
echo -e " Skipped:      ${YELLOW}${SKIPPED_COUNT}${NC}  → skipped.txt"
echo -e " Failed:       ${RED}${FAILED}${NC}  → repos.txt (retry)"
echo -e " Remaining:    ${REMAINING} in repos.txt"
echo ""

echo -e "${CYAN} Per-repo results:${NC}"
for repo in "${REPOS[@]}"; do
    repo_name=$(basename "$repo")
    disp_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.disposition"
    result_file="$LOG_DIR/${repo_name}_${MIGRATION_TYPE}_${TIMESTAMP}.result.json"

    disp="unknown"
    [ -f "$disp_file" ] && disp=$(cat "$disp_file")

    case "$disp" in
        done)
            pr_url=$(jq -r '.pr_url // "-"' "$result_file" 2>/dev/null || echo "-")
            tests=$(jq -r '"\(.tests_passed // "?")/\(.tests_total // "?")"' "$result_file" 2>/dev/null || echo "?/?")
            echo -e "  ${GREEN}✅${NC} $repo_name  PR: $pr_url  Tests: $tests"
            ;;
        skipped:not-dotnet)
            echo -e "  ${YELLOW}⏭️ ${NC} $repo_name  (not a .NET project)"
            ;;
        skipped:not-needed)
            echo -e "  ${YELLOW}⏭️ ${NC} $repo_name  (already migrated / no ${MIGRATION_TYPE} found)"
            ;;
        failed:clone-error)
            echo -e "  ${RED}❌${NC} $repo_name  (clone failed — check $LOG_DIR)"
            ;;
        failed:*)
            echo -e "  ${RED}❌${NC} $repo_name  (migration failed — check $LOG_DIR)"
            ;;
        *)
            echo -e "  ${YELLOW}⚠️ ${NC} $repo_name  (unknown — check $LOG_DIR)"
            ;;
    esac
done

if [ "$REMAINING" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}  ℹ️  ${REMAINING} repo(s) remaining in repos.txt — run again to continue${NC}"
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo "Logs: $LOG_DIR"
