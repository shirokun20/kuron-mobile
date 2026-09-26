#!/usr/bin/env bash
# ============================================================
# smart_search.sh — Intelligent search wrapper for Kuron
# Uses: ripgrep (rg), ugrep, semgrep
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEFAULT_DIR="lib/"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

usage() {
    echo -e "${CYAN}🔍 Kuron Smart Search${NC}"
    echo ""
    echo -e "Usage: $0 ${GREEN}<mode>${NC} ${YELLOW}<pattern>${NC} [directory]"
    echo ""
    echo -e "${GREEN}Modes:${NC}"
    echo "  text         Fast text search (ripgrep)"
    echo "  ast          AST-aware pattern search (semgrep)"
    echo "  interactive  Interactive TUI search (ugrep)"
    echo "  fuzzy        Fuzzy/approximate search (ugrep)"
    echo "  audit        Run architecture audit checks (mirrors AGENTS.md rules)"
    echo "  debugprint   Find debugPrint/print violations"
    echo "  violations   Find code standard violations"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 text 'pattern' lib/"
    echo "  $0 ast '\$X.find()'"
    echo "  $0 interactive 'pattern'"
    echo "  $0 audit"
    echo "  $0 debugprint"
    echo "  $0 violations"
    exit 1
}

check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}✗ $1 not found. Install with: brew install $2${NC}"
        exit 1
    fi
}

# --- Search Modes ---

search_text() {
    local pattern="$1"
    local dir="${2:-$DEFAULT_DIR}"
    check_tool rg ripgrep
    echo -e "${BLUE}🔎 ripgrep search: '${pattern}' in ${dir}${NC}"
    echo "─────────────────────────────────────────"
    rg --color=always -n --heading -t dart "$pattern" "$PROJECT_ROOT/$dir" || echo -e "${YELLOW}No matches found.${NC}"
}

search_ast() {
    local pattern="$1"
    local dir="${2:-$DEFAULT_DIR}"
    check_tool semgrep semgrep
    echo -e "${BLUE}🌳 semgrep AST search: '${pattern}' in ${dir}${NC}"
    echo "─────────────────────────────────────────"
    semgrep --lang dart -e "$pattern" "$PROJECT_ROOT/$dir" --no-git-ignore 2>/dev/null || echo -e "${YELLOW}No matches found.${NC}"
}

search_interactive() {
    local pattern="$1"
    local dir="${2:-$DEFAULT_DIR}"
    check_tool ugrep ugrep
    echo -e "${BLUE}🖥 ugrep interactive: '${pattern}' in ${dir}${NC}"
    ugrep -Q -n -t dart "$pattern" "$PROJECT_ROOT/$dir"
}

search_fuzzy() {
    local pattern="$1"
    local dir="${2:-$DEFAULT_DIR}"
    check_tool ugrep ugrep
    echo -e "${BLUE}🔮 ugrep fuzzy: '${pattern}' in ${dir}${NC}"
    echo "─────────────────────────────────────────"
    ugrep -Z -n -t dart "$pattern" "$PROJECT_ROOT/$dir" || echo -e "${YELLOW}No matches found.${NC}"
}

audit_architecture() {
    check_tool rg ripgrep
    echo -e "${CYAN}🏗 Architecture Audit — Kuron${NC}"
    echo "═══════════════════════════════════════════"
    
    echo ""
    echo -e "${YELLOW}1. injectable Ban (manual GetIt only):${NC}"
    rg --color=always -n "package:injectable|@injectable|@singleton|@lazySingleton" "$PROJECT_ROOT/lib/" "$PROJECT_ROOT/pubspec.yaml" 2>/dev/null || echo -e "  ${GREEN}✓ Clean — no injectable usage${NC}"

    echo ""
    echo -e "${YELLOW}2. Domain Purity (no Flutter in lib/domain):${NC}"
    rg --color=always -n -l "package:flutter" "$PROJECT_ROOT/lib/domain/" -t dart 2>/dev/null || echo -e "  ${GREEN}✓ Clean — domain is pure Dart${NC}"

    echo ""
    echo -e "${YELLOW}3. Print/DebugPrint Violations (code only, comments ignored):${NC}"
    rg --color=always -n "^\s*(print|debugPrint)\(" "$PROJECT_ROOT/lib/" -t dart 2>/dev/null || echo -e "  ${GREEN}✓ Clean — no print violations${NC}"

    echo ""
    echo -e "${YELLOW}4. New Dio Clients in Presentation (inject, don't construct):${NC}"
    rg --color=always -n "(= Dio\(|Dio\(BaseOptions|Dio\(\)\s*;)" "$PROJECT_ROOT/lib/presentation/" -t dart 2>/dev/null || echo -e "  ${GREEN}✓ Clean — no constructed Dio clients in UI${NC}"

    echo ""
    echo -e "${YELLOW}5. Cubits Not Extending BaseCubit:${NC}"
    rg --color=always -n "extends Cubit<" "$PROJECT_ROOT/lib/presentation/" -t dart 2>/dev/null | grep -v "base_cubit.dart" || echo -e "  ${GREEN}✓ Clean — all cubits extend BaseCubit${NC}"

    echo ""
    echo -e "${YELLOW}6. Hardcoded Strings in UI:${NC}"
    local count
    count=$(rg -c "Text\(['\"][A-Z]" "$PROJECT_ROOT/lib/presentation/" -t dart 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
    echo -e "  Found ${count} potential hardcoded strings (consider l10n)"
    
    echo ""
    echo -e "${YELLOW}7. TODO/FIXME/HACK Count:${NC}"
    local todo_count
    todo_count=$(rg -c "(TODO|FIXME|HACK|XXX)" "$PROJECT_ROOT/lib/" -t dart 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
    echo -e "  Found ${todo_count} items"
    
    echo ""
    echo "═══════════════════════════════════════════"
    echo -e "${CYAN}Audit complete.${NC}"
}

search_debugprint() {
    check_tool rg ripgrep
    echo -e "${CYAN}🔎 DebugPrint/Print Violations Scanner${NC}"
    echo "═══════════════════════════════════════════"
    
    echo -e "\n${YELLOW}debugPrint() calls:${NC}"
    rg --color=always -n "debugPrint\(" "$PROJECT_ROOT/lib/" -t dart 2>/dev/null || echo -e "  ${GREEN}✓ None${NC}"
    
    echo -e "\n${YELLOW}print() calls:${NC}"
    rg --color=always -n "^\s*print\(" "$PROJECT_ROOT/lib/" -t dart 2>/dev/null || echo -e "  ${GREEN}✓ None${NC}"
    
    echo -e "\n${YELLOW}Summary:${NC}"
    local dcount pcount
    dcount=$(rg -c "debugPrint\(" "$PROJECT_ROOT/lib/" -t dart 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
    pcount=$(rg -c "^\s*print\(" "$PROJECT_ROOT/lib/" -t dart 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
    echo -e "  debugPrint: ${dcount} | print: ${pcount} | Total: $((dcount + pcount))"
    
    echo ""
    echo "═══════════════════════════════════════════"
}

search_violations() {
    check_tool rg ripgrep
    echo -e "${CYAN}⚠️  Code Standard Violations Scanner${NC}"
    echo "═══════════════════════════════════════════"
    
    echo -e "\n${YELLOW}1. Logger Violations (print/debugPrint):${NC}"
    rg --color=always -n "^\s*(print|debugPrint)\(" "$PROJECT_ROOT/lib/" -t dart 2>/dev/null || echo -e "  ${GREEN}✓ Clean${NC}"
    
    echo -e "\n${YELLOW}2. Cubits Not Extending BaseCubit:${NC}"
    rg --color=always -n "extends Cubit<" "$PROJECT_ROOT/lib/presentation/" -t dart 2>/dev/null | grep -v "base_cubit.dart" || echo -e "  ${GREEN}✓ Clean${NC}"

    echo -e "\n${YELLOW}3. Flutter Imports in Domain:${NC}"
    rg --color=always -n -l "package:flutter" "$PROJECT_ROOT/lib/domain/" -t dart 2>/dev/null || echo -e "  ${GREEN}✓ Clean${NC}"

    echo -e "\n${YELLOW}4. Missing const constructors:${NC}"
    local non_const
    non_const=$(rg -c "^\s+\w+\(\)," "$PROJECT_ROOT/lib/presentation/" -t dart 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
    echo -e "  ${non_const} potential missing const (review manually)"

    echo -e "\n${YELLOW}5. ListView with children (should use .builder):${NC}"
    rg --color=always -n "ListView\(\s*$" "$PROJECT_ROOT/lib/" -t dart 2>/dev/null || echo -e "  ${GREEN}✓ Clean${NC}"
    rg --color=always -n "children:\s*\[" "$PROJECT_ROOT/lib/presentation/" -t dart --glob '!*widget*' 2>/dev/null | head -10 || true
    
    echo ""
    echo "═══════════════════════════════════════════"
}

# --- Main ---

if [ $# -lt 1 ]; then
    usage
fi

MODE="$1"
PATTERN="${2:-}"
DIR="${3:-}"

case "$MODE" in
    text)
        [ -z "$PATTERN" ] && usage
        search_text "$PATTERN" "$DIR"
        ;;
    ast)
        [ -z "$PATTERN" ] && usage
        search_ast "$PATTERN" "$DIR"
        ;;
    interactive)
        [ -z "$PATTERN" ] && usage
        search_interactive "$PATTERN" "$DIR"
        ;;
    fuzzy)
        [ -z "$PATTERN" ] && usage
        search_fuzzy "$PATTERN" "$DIR"
        ;;
    audit)
        audit_architecture
        ;;
    debugprint)
        search_debugprint
        ;;
    violations)
        search_violations
        ;;
    *)
        echo -e "${RED}Unknown mode: $MODE${NC}"
        usage
        ;;
esac
