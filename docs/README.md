# Project Progress Dashboard

This directory contains the progress-tracking dashboard for your SpecKit Salesforce project.

## Files

| File | Purpose |
|------|---------|
| `progress-dashboard.html` | Static HTML dashboard for GitHub Pages |
| `progress-tracker.json` | Single source of truth for all metrics |

## Viewing the Dashboard

### Option 1: GitHub Pages (Recommended)

1. Enable GitHub Pages in repository settings
2. Set source to `main` branch, `/docs` folder
3. Access at: `https://<org>.github.io/<repo>/progress-dashboard.html`

### Option 2: Local Viewing

Open `progress-dashboard.html` directly in a browser. The dashboard works offline with embedded data.

## Tracked Metrics

### 1. Token Consumption (per Epic)

Token estimates based on conversation session length and complexity.

### 2. Epics & Stories Created

Counts of epics and user stories, grouped by epic.

### 3. Build Progress

Track story implementation status:
- **Pending**: Not started
- **In Progress**: Currently being built
- **Built**: Deployed to Salesforce org

## Updating the Dashboard

### Automated (Recommended)

Run `/speckit-dashboard` after completing work to update `progress-tracker.json`, or let the
`dashboard-enforcement` rule prompt you after each implementation.

### Manual Update

Edit `progress-tracker.json` to update story status (`built: true/false`), token consumption,
and build counts.

## Data Structure

```json
{
  "project": {
    "name": "[Your Project Name]",
    "industry": "[Industry]",
    "jira_project": "[KEY]",
    "github_repo": "[repo URL]"
  },
  "summary": {
    "total_epics": 0,
    "total_stories": 0,
    "stories_built": 0,
    "completion_percentage": 0
  },
  "token_consumption": {
    "by_epic": [
      { "epic_name": "[Epic]", "total_tokens": 0, "sessions": [] }
    ]
  },
  "epics": [
    {
      "jira_key": "[KEY]-1",
      "stories": [ { "key": "[KEY]-24", "built": false } ]
    }
  ]
}
```
