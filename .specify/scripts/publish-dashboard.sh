#!/bin/bash
# Publish the progress dashboard.
#
# 1. Regenerates the embedded offline-fallback data from progress-tracker.json
#    (the single source of truth) for every dashboard in the repo.
# 2. Stages the dashboard files, commits, and pushes.
#
# Usage:
#   bash .specify/scripts/publish-dashboard.sh ["commit message"]
#
# The commit message is optional; a sensible default is used when omitted.

set -e

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repo root (prefer git, fall back to cwd)
if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then :; else REPO_ROOT="$(pwd)"; fi
cd "$REPO_ROOT"

MSG="${1:-chore(dashboard): update progress tracker and dashboard}"

# 1. Sync embedded fallback data
SYNC_SCRIPT=""
for cand in "$SCRIPT_DIR/sync-dashboard-data.py" "$REPO_ROOT/scripts/sync-dashboard-data.py"; do
    [ -f "$cand" ] && SYNC_SCRIPT="$cand" && break
done
if [ -n "$SYNC_SCRIPT" ] && command -v python3 >/dev/null 2>&1; then
    echo -e "${BLUE}🔄 Syncing embedded dashboard data...${NC}"
    python3 "$SYNC_SCRIPT" "$REPO_ROOT"
else
    echo -e "${YELLOW}⚠️  sync-dashboard-data.py or python3 not found — skipping embed sync${NC}"
fi

# 2. Stage dashboard files (tracker + html, anywhere in the repo)
echo -e "${BLUE}📦 Staging dashboard files...${NC}"
git ls-files --modified --others --exclude-standard \
    | grep -E '(progress-tracker\.json|progress-dashboard\.html)$' \
    | while read -r f; do git add "$f"; done || true

if git diff --cached --quiet; then
    echo -e "${YELLOW}ℹ️  No dashboard changes to commit.${NC}"
    exit 0
fi

# 3. Commit
echo -e "${BLUE}📝 Committing...${NC}"
git commit -m "$MSG"

# 4. Push
echo -e "${BLUE}🚀 Pushing...${NC}"
if git push; then
    echo -e "${GREEN}✅ Dashboard published. GitHub Pages will refresh shortly.${NC}"
else
    echo -e "${RED}✗ Push failed. Commit is saved locally — push manually when ready.${NC}"
    exit 1
fi
