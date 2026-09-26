#!/bin/bash
#
# Asset size auditor for Kuron.
# Usage: ./scripts/optimize_assets.sh [--limit-kb 200]
#
# Non-interactive: prints the largest bundled assets and flags anything
# above the repo budget (AGENTS.md: compress <200KB, prefer WebP, declare
# in pubspec). Exits 1 when over-budget assets exist (CI-friendly).
#
# History: this script once targeted assets/json/tags.json (4.9MB). That file
# no longer exists — tags now live in assets/configs/tags-config.json (~4KB)
# — so the script audits whatever is actually bundled.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

LIMIT_KB=200
if [ "${1:-}" = "--limit-kb" ]; then
    LIMIT_KB="${2:-200}"
fi

echo "Asset size audit (budget: ${LIMIT_KB}KB per file)"
echo ""

if [ ! -d "assets" ]; then
    echo "No assets/ directory — nothing to audit."
    exit 0
fi

OVER=0
while IFS= read -r line; do
    size_kb=$(echo "$line" | awk '{print $1}')
    file=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')
    if [ "$size_kb" -gt "$LIMIT_KB" ]; then
        echo "  OVER  ${size_kb}KB  $file"
        OVER=$((OVER + 1))
    fi
done < <(find assets/ -type f -exec du -k {} + | sort -rn)

echo ""
echo "Largest 10 assets:"
find assets/ -type f -exec du -h {} + | sort -hr | head -10 | sed 's/^/  /'

echo ""
if [ "$OVER" -gt 0 ]; then
    echo "Result: $OVER file(s) over budget — compress (<${LIMIT_KB}KB), use WebP, multi-res."
    exit 1
fi
echo "Result: all assets within budget."
