---
description: Enforce dashboard updates after completing work
globs: ["**/*.cls", "**/*.js", "**/*.html", "**/*.xml"]
---

# Dashboard Update Enforcement

After completing any user story implementation, ALWAYS prompt to update the progress dashboard.

## Trigger Conditions

Prompt for dashboard update when any of these are completed:

1. **Apex class implementation** - When a `.cls` file is created or significantly modified
2. **LWC component completion** - When a component's JS, HTML, and CSS are done
3. **Permission set creation** - When `.permissionset-meta.xml` is created
4. **FlexiPage update** - When `.flexipage-meta.xml` is modified
5. **Custom object/field** - When `.object-meta.xml` or `.field-meta.xml` is created
6. **Flow deployment** - When `.flow-meta.xml` is created

## Required Action

After committing code changes, ask:

> "Would you like me to update the progress dashboard to mark this work as complete?"

If user agrees:

1. **Identify the related user story** from:
   - Commit message (e.g., "US1:", "PROJ-123")
   - File names matching `components` in progress-tracker.json
   - Recent `/speckit-tasks` context

2. **Update `docs/progress-tracker.json`**:
   ```json
   {
     "key": "PROJ-123",
     "status": "completed",
     "built": true,
     "built_by": "contributor-id",
     "built_date": "2026-06-13"
   }
   ```

3. **Add token session entry**:
   ```json
   {
     "date": "2026-06-13",
     "contributor": "contributor-id",
     "activity": "Implemented US1: Feature Name",
     "tokens": 45000
   }
   ```

4. **Update summary totals**:
   - Increment `stories_built`
   - Decrement `stories_pending` or `stories_in_progress`
   - Recalculate `completion_percentage`

5. **Commit the tracker update**:
   ```bash
   git add docs/progress-tracker.json
   git commit -m "Dashboard: Mark [story key] as built"
   ```

## Story-to-Component Mapping

Use the `components` field in progress-tracker.json to match files to stories:

```json
{
  "key": "PROJ-24",
  "summary": "US1: KPI Header",
  "components": ["kpiHeader LWC", "KpiController.cls"]
}
```

When `kpiHeader.js` is committed → suggest marking PROJ-24 as built.

## Token Estimation Guidelines

| Work Type | Estimated Tokens |
|-----------|------------------|
| Simple bug fix | 5,000 - 15,000 |
| Single LWC component | 15,000 - 30,000 |
| Apex service + tests | 30,000 - 50,000 |
| Full user story | 40,000 - 80,000 |
| Complex feature/epic | 80,000 - 150,000 |

## Skip Conditions

Don't prompt for dashboard update when:
- Commit is only documentation/README changes
- Commit is configuration/setup files only
- User explicitly says "skip dashboard"
- Same story was already marked as built today
