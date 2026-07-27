#!/bin/bash
# SpecKit Dashboard Setup Script
# Sets up progress tracking dashboard for GitHub Pages

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECKIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SPECKIT_ROOT/.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/../docs"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📊 Setting up Progress Dashboard...${NC}"

# Create docs directory at repo root (for GitHub Pages)
mkdir -p "$DOCS_DIR"

# Check if progress-tracker.json already exists
if [ -f "$DOCS_DIR/progress-tracker.json" ]; then
    echo -e "${YELLOW}⚠️  progress-tracker.json already exists. Skipping template copy.${NC}"
else
    # Copy template and prompt for customization
    if [ -f "$SPECKIT_ROOT/.specify/templates/progress-tracker-template.json" ]; then
        cp "$SPECKIT_ROOT/.specify/templates/progress-tracker-template.json" "$DOCS_DIR/progress-tracker.json"
        echo -e "${GREEN}✅ Created progress-tracker.json${NC}"
        echo -e "${YELLOW}📝 Edit docs/progress-tracker.json to customize project details${NC}"
    fi
fi

# Check if dashboard HTML exists
if [ -f "$DOCS_DIR/progress-dashboard.html" ]; then
    echo -e "${YELLOW}⚠️  progress-dashboard.html already exists.${NC}"
else
    echo -e "${BLUE}📄 Dashboard HTML will be created by the agent.${NC}"
    echo -e "   Run: /speckit-dashboard to generate the full dashboard"
fi

# Activate the auto-sync git hook (runs sync on every commit). Requires .githooks/ at repo root.
GIT_ROOT="$(cd "$PROJECT_ROOT/.." && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$GIT_ROOT" ] && [ -f "$GIT_ROOT/.githooks/pre-commit" ]; then
    ( cd "$GIT_ROOT" && git config core.hooksPath .githooks ) \
        && echo -e "${GREEN}✅ Enabled auto-sync git hook (core.hooksPath=.githooks)${NC}" \
        || echo -e "${YELLOW}⚠️  Could not set core.hooksPath — run: git config core.hooksPath .githooks${NC}"
fi

# Sync the embedded offline-fallback data from progress-tracker.json (single source of truth).
# Keeps the dashboard correct even when opened directly via file://.
SYNC_SCRIPT="$SPECKIT_ROOT/scripts/sync-dashboard-data.py"
if [ -f "$DOCS_DIR/progress-dashboard.html" ] && [ -f "$DOCS_DIR/progress-tracker.json" ] && [ -f "$SYNC_SCRIPT" ]; then
    if command -v python3 >/dev/null 2>&1; then
        ( cd "$PROJECT_ROOT/.." && python3 "$SYNC_SCRIPT" ) \
            && echo -e "${GREEN}✅ Synced embedded dashboard data from progress-tracker.json${NC}" \
            || echo -e "${YELLOW}⚠️  Could not sync embedded dashboard data (run python3 .specify/scripts/sync-dashboard-data.py manually)${NC}"
    else
        echo -e "${YELLOW}⚠️  python3 not found — skipping embedded-data sync${NC}"
    fi
fi

# Create README for docs folder
if [ ! -f "$DOCS_DIR/README.md" ]; then
    cat > "$DOCS_DIR/README.md" << 'EOF'
# Progress Dashboard

This directory contains the progress tracking dashboard for GitHub Pages.

## Files

| File | Purpose |
|------|---------|
| `progress-dashboard.html` | Interactive dashboard UI |
| `progress-tracker.json` | Data source for all metrics |

## Setup GitHub Pages

1. Go to repository **Settings → Pages**
2. Source: `main` branch, `/docs` folder
3. Save and wait for deployment

## Tracking Metrics

- **Epics & Stories**: Synced from Jira
- **Token Consumption**: Tracked per contributor/session
- **Built Stories**: Updated when Jira status = Done

## Sync Commands

Tell the agent:
- `Sync from Jira` - Pull latest status
- `Mark PR-XXX as built` - Update specific story
- `Add contributor John` - Add team member

## Updating the data (single source of truth)

All values render from `progress-tracker.json`. Never hand-edit the HTML.

- Refresh offline fallback:  `python3 .specify/scripts/sync-dashboard-data.py`
- Sync + commit + push:      `bash .specify/scripts/publish-dashboard.sh "message"`

EOF
    echo -e "${GREEN}✅ Created docs/README.md${NC}"
fi

echo ""
echo -e "${GREEN}✅ Dashboard setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Run /speckit-dashboard to generate the full HTML dashboard"
echo "  2. Configure GitHub Pages in repository settings"
echo "  3. Set up Jira integration (see docs/jira-integration.md)"
echo "  4. Publish updates anytime with: bash .specify/scripts/publish-dashboard.sh"
echo ""
