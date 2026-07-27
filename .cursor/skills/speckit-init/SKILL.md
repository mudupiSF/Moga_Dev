# /speckit-init

Bootstrap SpecKit structure in a new Salesforce project.

## User Input

```text
$ARGUMENTS
```

## Purpose

Initialize the SpecKit directory structure in the current project. This skill is used after installing SpecKit via the symlink method, allowing you to quickly set up any Salesforce project for spec-driven development.

## Prerequisites

- SpecKit skills are available in this project's `.cursor/skills/` (installed via `install.sh`)
- Current directory is a Salesforce project (or will become one)

> Note: The one-command install (`bash ~/.speckit-salesforce/install.sh .`) already copies
> `.specify/`, `docs/`, and `specs/` into the project. Use `/speckit-init` only when you need
> to re-scaffold or reconfigure an existing project.

## Outline

1. **Check if already initialized**: Look for `.specify/` directory
   - If exists, ask user if they want to reinitialize

2. **Create directory structure**:
   ```
   .specify/
   ├── memory/
   │   ├── constitution.md
   │   ├── project-details.md
   │   ├── taxonomy.md
   │   ├── domain.md
   │   └── regulatory.md
   ├── templates/
   │   ├── spec-template.md
   │   ├── plan-template.md
   │   ├── tasks-template.md
   │   └── checklist-template.md
   └── scripts/
       └── bash/
   
   docs/
   ├── progress-dashboard.html
   ├── progress-tracker.json
   └── jira-integration.md
   
   specs/
   ```

3. **Interactive configuration** (if not skipped):
   - Project name
   - Salesforce org alias
   - Industry (dropdown)
   - GitHub repository URL (optional)
   - Jira project key (optional)
   - Contributor name and role

4. **Copy template files**: 
   - Get templates from the symlinked toolkit location
   - Copy to project's `.specify/templates/`

5. **Initialize constitution**:
   - Copy default constitution to `.specify/memory/constitution.md`
   - Replace placeholders with project-specific values

6. **Initialize progress tracker**:
   - Create `docs/progress-tracker.json` with project configuration
   - Create `docs/progress-dashboard.html`

7. **Initialize git** (if not already):
   - Offer to run `git init`
   - Add `.specify/` to tracking

## Configuration Prompts

### Required
| Field | Description | Example |
|-------|-------------|---------|
| Project Name | Display name for the project | "Customer Portal" |

### Optional
| Field | Description | Example |
|-------|-------------|---------|
| SF Org Alias | Salesforce CLI org alias | "my-dev-org" |
| Industry | Business domain | "Healthcare", "Financial Services" |
| GitHub URL | Repository URL for dashboard | "https://github.com/org/repo" |
| Jira Key | Jira project key | "PROJ" |
| Your Name | Contributor name | "Jane Smith" |
| Your Role | Job title | "Lead Developer" |

## Completion Report

Output:
- Summary of created directories and files
- Next steps:
  1. Review constitution at `.specify/memory/constitution.md`
  2. Create first spec: `/speckit-specify -EPIC "Feature Name"`
  3. Set up GitHub Pages for dashboard (optional)

## Example Usage

```
/speckit-init

# Or with project name
/speckit-init Customer Portal

# Skip interactive prompts (use defaults)
/speckit-init --quick
```

## Done When

- [ ] `.specify/` directory structure created
- [ ] Memory files initialized with placeholders or user values
- [ ] Templates copied to project
- [ ] `docs/` directory with dashboard files created
- [ ] `specs/` directory created
- [ ] Progress tracker initialized with project config
- [ ] Git repository initialized (if requested)
