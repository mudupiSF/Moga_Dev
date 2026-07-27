---
name: speckit-dashboard
description: Generate and manage the project progress dashboard with Jira sync, token tracking, and GitHub Pages publishing.
version: 1.1.0
---

# SpecKit Dashboard

Generate and manage the project progress tracking dashboard.

## ⚠️ Single source of truth: `progress-tracker.json`

The dashboard (`progress-dashboard.html`) is **100% data-driven** — every value (summary
stats, charts, contributors, epics, stories, token sessions) is rendered at runtime from
JSON. **Never hand-edit numbers in the HTML.** Only edit `docs/progress-tracker.json`.

The HTML reads data in two ways:
1. **Live:** `fetch('./progress-tracker.json')` — used on GitHub Pages / any http server.
2. **Offline fallback:** an embedded `<script id="embedded-data">` JSON island — used when
   the file is opened directly via `file://` (where `fetch` is blocked by the browser).

### MANDATORY final step after ANY tracker change

Whenever you modify `docs/progress-tracker.json` (sync from Jira, mark a story built, add a
contributor, log token sessions, add an epic), you MUST regenerate the embedded fallback so
the offline view never goes stale:

```bash
python3 .specify/scripts/sync-dashboard-data.py
```

This copies `progress-tracker.json` into the embedded island of every
`progress-dashboard.html` in the project (skips `.sk-test`). Do this **before** committing.
Do not consider a dashboard update complete until this script has run.

### Fully automatic: sync on commit (recommended)

Token/progress data lives **only** in `progress-tracker.json` and is edited locally as you
work. A git `pre-commit` hook then keeps the shared dashboard in sync with zero manual steps:

- On every `git commit`, the hook runs `sync-dashboard-data.py` and folds the refreshed
  `progress-dashboard.html` into the **same commit**.
- `git push` then shares it — teammates see it on their next page refresh (GitHub Pages
  live-fetches `progress-tracker.json`).

Enable once per clone (also done automatically by `setup-dashboard.sh`):

```bash
git config core.hooksPath .githooks
```

The hook lives at `.githooks/pre-commit` (committed, so it travels with the repo) and is
non-fatal — if `python3` is unavailable the commit still succeeds.

**Your only job:** edit `progress-tracker.json`, then `git commit` + `git push`. Everything
else is automatic.

### One-step publish (sync + commit + push)

To sync the embedded data and push in a single step, use the publish helper:

```bash
bash .specify/scripts/publish-dashboard.sh ["optional commit message"]
```

It runs `sync-dashboard-data.py`, stages every `progress-tracker.json` /
`progress-dashboard.html`, commits, and pushes. On GitHub Pages the dashboard refreshes
automatically after the push.

## Commands

### `/speckit-dashboard`

Generate or update the progress dashboard.

**Usage:**
```
/speckit-dashboard              # Generate full dashboard
/speckit-dashboard sync         # Sync from Jira
/speckit-dashboard add-epic     # Add new epic to tracker
/speckit-dashboard add-contrib  # Add contributor
```

## Dashboard Features

1. **Overview Tab** - Summary stats, progress bars, charts
2. **Built Stories Tab** - What's deployed to Salesforce org
3. **Contributors Tab** - Multi-person token tracking
4. **Epics & Stories Tab** - Full story list by epic
5. **Token Details Tab** - Session-level breakdown

## File Locations

| File | Location | Purpose |
|------|----------|---------|
| Dashboard HTML | `docs/progress-dashboard.html` | GitHub Pages UI |
| Tracker JSON | `docs/progress-tracker.json` | Data source |
| Template | `.specify/templates/progress-tracker-template.json` | Initial setup |

## Workflow

### Initial Setup

1. Run setup script:
   ```bash
   bash .specify/scripts/bash/setup-dashboard.sh
   ```

2. Generate dashboard:
   ```
   /speckit-dashboard
   ```

3. Configure GitHub Pages:
   - Repository Settings → Pages
   - Source: `main` branch, `/docs` folder

### Syncing from Jira

When stories change status in Jira:

```
/speckit-dashboard sync
```

Or tell the agent:
- "Sync dashboard from Jira"
- "Mark PR1070767-24 as built"
- "Update progress tracker"

### Adding Contributors

When a new team member starts working:

```json
{
  "id": "john",
  "name": "John Doe",
  "role": "Developer",
  "total_tokens": 0,
  "sessions_count": 0
}
```

### Adding Token Sessions

After each working session, add to `token_consumption.by_epic[].sessions`:

```json
{
  "date": "2026-06-12",
  "contributor": "john",
  "activity": "Implemented US1: KPI Header Bar",
  "tokens": 45000
}
```

## Jira Integration

### Option 1: Manual Sync (No Admin Required)

Tell the agent: "Sync from Jira"

### Option 2: Automated Webhook (Requires Jira Admin)

See `docs/jira-integration.md` for setup instructions.

**Jira Automation Rule:**
- Trigger: Issue transitioned
- Action: Send webhook to GitHub
- Updates dashboard automatically

### Status Mapping

| Jira Status | Dashboard Status |
|-------------|------------------|
| Open / To Do | `pending` |
| In Progress | `in-progress` |
| In Review / QA | `in-review` |
| Done / Closed | `built` |

## Dashboard Generation

The agent will:

1. Query Jira for all epics and stories
2. Extract status, priority, and metadata
3. Calculate token consumption totals
4. Update `progress-tracker.json` (the only file that holds data)
5. Run `python3 .specify/scripts/sync-dashboard-data.py` to refresh the embedded fallback
6. Commit and push to GitHub (`progress-tracker.json` + `progress-dashboard.html`)

> Steps 5 + 6 can be done in one shot with `bash .specify/scripts/publish-dashboard.sh`.
> Step 4 alone is enough for the live GitHub Pages dashboard. Step 5 is required so the
> dashboard also shows correct data when opened locally as a file.

## Customization

### Adding Custom Metrics

Edit `progress-tracker.json` to add project-specific tracking:

```json
{
  "custom_metrics": {
    "code_coverage": 0,
    "test_cases_passed": 0,
    "deployment_count": 0
  }
}
```

### Styling

The dashboard uses CSS variables. Override in the HTML:

```css
:root {
  --accent-blue: #58a6ff;
  --accent-green: #3fb950;
}
```

## Troubleshooting

### GitHub Pages 404
- Ensure `docs/` folder exists at repo root (not inside subdirectory)
- Check Pages settings: source = `main`, folder = `/docs`

### Jira Sync Fails
- Verify Jira project key is correct
- Check MCP authentication status

### Dashboard Not Updating
- Run `/speckit-dashboard sync` to force refresh
- Check `progress-tracker.json` for data integrity
- **Opened as a file and still see old numbers?** The embedded fallback is stale. Run
  `python3 .specify/scripts/sync-dashboard-data.py`, then hard-refresh (Cmd+Shift+R).
- **Viewing on GitHub Pages and see old numbers?** Hard-refresh; Pages caches briefly.

### Values look hardcoded / won't change
- They are not. All display values render from `progress-tracker.json`. If you edited the
  HTML directly, your changes will be overwritten on load — edit the JSON instead.
