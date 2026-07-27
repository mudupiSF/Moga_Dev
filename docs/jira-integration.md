# Jira Integration for Progress Dashboard

This guide explains how to set up automatic synchronization between Jira and the GitHub progress dashboard.

## Overview

```
┌─────────────────┐    Status Change    ┌─────────────────┐    Webhook    ┌─────────────────┐
│     Jira        │───────────────────▶│ Jira Automation │─────────────▶│ GitHub Action   │
│  Story → Done   │                    │    Rule         │              │ Updates JSON    │
└─────────────────┘                    └─────────────────┘              └─────────────────┘
```

## Option 1: Manual Sync (No Admin Required)

If you don't have Jira admin access, use manual sync:

1. Move story to new status in Jira
2. Tell the agent: `Sync dashboard from Jira`
3. Dashboard updates and pushes to GitHub

**Commands:**
- `Sync from Jira` - Full sync of all stories
- `Mark PR1070767-24 as built` - Update specific story
- `Update progress` - Sync and push to GitHub

---

## Option 2: Automated Webhook (Requires Jira Admin)

### Step 1: Create GitHub Personal Access Token

1. Go to: **GitHub → Settings → Developer Settings → Personal Access Tokens**
2. Click **Generate new token (classic)**
3. Name: `Jira Dashboard Sync`
4. Scopes: Select `repo` (full control)
5. Generate and **copy the token**

### Step 2: Create Jira Automation Rule

1. Navigate to: **Jira Project → Project Settings → Automation**
2. Click **Create rule**

#### Configure Trigger

- **When:** Issue transitioned
- **For transitions:** Any status (or select specific: Done, In Progress, etc.)

#### Add Condition

- **Type:** Issue fields condition
- **Field:** Issue Type
- **Condition:** equals `Story`

#### Configure Action

- **Action:** Send web request
- **Web request URL:** 
  ```
  https://api.github.com/repos/{owner}/{repo}/dispatches
  ```
  Replace `{owner}/{repo}` with your repository path.

- **HTTP Method:** POST

- **Web request headers:**
  ```
  Authorization: token YOUR_GITHUB_PAT_HERE
  Accept: application/vnd.github.v3+json
  Content-Type: application/json
  ```

- **Web request body:**
  ```json
  {
    "event_type": "jira-status-change",
    "client_payload": {
      "story_key": "{{issue.key}}",
      "story_summary": "{{issue.summary}}",
      "from_status": "{{changelog.from}}",
      "to_status": "{{issue.status.name}}",
      "status_category": "{{issue.status.statusCategory.name}}",
      "assignee": "{{issue.assignee.displayName}}",
      "epic_key": "{{issue.parent.key}}",
      "updated_at": "{{now.jiraDate}}",
      "transition_by": "{{initiator.displayName}}"
    }
  }
  ```

#### Save and Enable

- Name the rule: `Sync to GitHub Dashboard`
- Turn the rule **ON**

### Step 3: Create GitHub Actions Workflow

Create `.github/workflows/jira-webhook.yml` in your repository:

```yaml
name: Update Dashboard from Jira

on:
  repository_dispatch:
    types: [jira-status-change]

jobs:
  update-dashboard:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Update progress-tracker.json
        run: |
          STORY_KEY="${{ github.event.client_payload.story_key }}"
          TO_STATUS="${{ github.event.client_payload.to_status }}"
          ASSIGNEE="${{ github.event.client_payload.assignee }}"
          DATE=$(date +%Y-%m-%d)
          
          # Map Jira status to dashboard status
          case "$TO_STATUS" in
            "Open"|"To Do") DASH_STATUS="pending" ;;
            "In Progress") DASH_STATUS="in-progress" ;;
            "In Review"|"QA") DASH_STATUS="in-review" ;;
            "Done"|"Closed") DASH_STATUS="built" ;;
            *) DASH_STATUS="pending" ;;
          esac
          
          # Update JSON using jq
          jq --arg key "$STORY_KEY" \
             --arg status "$DASH_STATUS" \
             --arg assignee "$ASSIGNEE" \
             --arg date "$DATE" \
             '(.epics[].stories[] | select(.key == $key)) |= (
                .status = $status |
                .built = ($status == "built") |
                if $status == "built" then .built_by = $assignee | .built_date = $date else . end
              )' docs/progress-tracker.json > tmp.json
          
          mv tmp.json docs/progress-tracker.json
          
          # Update summary counts
          BUILT=$(jq '[.epics[].stories[] | select(.built == true)] | length' docs/progress-tracker.json)
          PROGRESS=$(jq '[.epics[].stories[] | select(.status == "in-progress")] | length' docs/progress-tracker.json)
          REVIEW=$(jq '[.epics[].stories[] | select(.status == "in-review")] | length' docs/progress-tracker.json)
          TOTAL=$(jq '[.epics[].stories[]] | length' docs/progress-tracker.json)
          PENDING=$((TOTAL - BUILT - PROGRESS - REVIEW))
          PCT=$((BUILT * 100 / TOTAL))
          
          jq --argjson built "$BUILT" \
             --argjson progress "$PROGRESS" \
             --argjson review "$REVIEW" \
             --argjson pending "$PENDING" \
             --argjson pct "$PCT" \
             '.summary.stories_built = $built |
              .summary.stories_in_progress = $progress |
              .summary.stories_in_review = $review |
              .summary.stories_pending = $pending |
              .summary.completion_percentage = $pct |
              .project.last_updated = (now | todate)' docs/progress-tracker.json > tmp.json
          
          mv tmp.json docs/progress-tracker.json
      
      - name: Commit and Push
        run: |
          git config user.name "Jira Sync Bot"
          git config user.email "bot@github.com"
          git add docs/progress-tracker.json
          git diff --staged --quiet || git commit -m "Auto-sync: ${{ github.event.client_payload.story_key }} → ${{ github.event.client_payload.to_status }}"
          git push
```

---

## Status Mapping Reference

| Jira Status | Dashboard Status | Visual Indicator |
|-------------|------------------|------------------|
| Open | `pending` | Gray dot |
| To Do | `pending` | Gray dot |
| In Progress | `in-progress` | Blue dot |
| In Review | `in-review` | Yellow dot |
| QA | `in-review` | Yellow dot |
| Done | `built` | Green dot |
| Closed | `built` | Green dot |

---

## Testing the Integration

### Test Jira Automation

1. Move a story to "In Progress" in Jira
2. Check GitHub Actions tab for workflow run
3. Verify `docs/progress-tracker.json` was updated
4. Refresh dashboard to see changes

### Test Manual Sync

1. Make changes in Jira
2. Tell agent: `Sync from Jira`
3. Verify dashboard updates

---

## Troubleshooting

### Webhook Not Triggering

- Check Jira Automation audit log
- Verify GitHub PAT has `repo` scope
- Ensure rule is enabled

### GitHub Action Fails

- Check Actions tab for error logs
- Verify `jq` commands are correct
- Ensure `docs/progress-tracker.json` exists

### Wrong Status Mapping

- Check the `case` statement in workflow
- Add custom Jira statuses as needed

---

## Security Notes

- Store GitHub PAT securely in Jira
- Use repository secrets for sensitive data
- Limit PAT scope to minimum required (`repo`)
- Rotate tokens periodically
