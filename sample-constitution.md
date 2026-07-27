# Sample Salesforce Constitution

> **Note**: Copy this file to `.specify/memory/constitution.md` and customize for your project.

---

# AgenticDev Salesforce Constitution

Governs the `[YOUR-PROJECT]` spec workspace and the [Your Organization] Salesforce solution. 
This document holds the principle-level summary; the authoritative source for detailed 
implementation rules is `.cursor/rules/specify-rules.mdc`.

## Core Principles

### I. Architectural Integrity & Platform-First (NON-NEGOTIABLE)

Every solution MUST align with the existing enterprise architecture and avoid technical
debt. Native Salesforce features MUST be used wherever possible; custom code is only
permitted when no native capability exists or is inadequate. Solutions MUST be scalable,
maintainable, secure, and performant for the long term.

### II. Security & Access Control (NON-NEGOTIABLE)

All database operations MUST run in user mode, not system mode:
`[SELECT … WITH USER_MODE]` and `Database.insert(records, AccessLevel.USER_MODE)`.
Classes that access data MUST use `with sharing`. `WITH SECURITY_ENFORCED` MUST be
applied on all SOQL queries executed in a user context. Hardcoded IDs and URLs are
prohibited. User inputs MUST be sanitised before use in queries or DML.

### III. Governor Limits & Bulkification (NON-NEGOTIABLE)

SOQL and DML operations MUST NOT appear inside loops. All code MUST be bulkified to
handle large data volumes using collections. SOQL queries per transaction MUST stay
≤ 100; DML statements ≤ 150. `@future` methods are prohibited for async processing —
use Queueables and always implement `System.Finalizer`. `Database.Stateful` MUST only be
used when strictly necessary in batch jobs.

### IV. Apex Code Quality Standards

One trigger per object; trigger handler class pattern is mandatory for all triggers.
Recursive trigger prevention MUST use a static boolean flag. Enums MUST be used over
string constants and follow `ALL_CAPS_SNAKE_CASE`. Database Methods with exception
handling MUST be used for all DML. Return Early pattern MUST be applied to reduce
nesting. `System.debug()` statements are prohibited in production code. Builder,
Factory, Dependency Injection, and Command patterns MUST be applied where appropriate.
All classes and methods MUST be documented with ApexDocs comments.

### V. Apex Testing Standards (NON-NEGOTIABLE)

Minimum 75% code coverage is required; meaningful assertions are mandatory — not just
coverage lines. `@TestSetup` MUST be used to create test data. `SeeAllData=true` is
prohibited. External services and callouts MUST be mocked. Bulk trigger functionality
MUST be tested. `Test.startTest()` / `Test.stopTest()` MUST wrap async or
governor-limit-sensitive test logic. `System.runAs()` MUST be used to test different
user contexts. Test isolation is mandatory — no dependencies between test methods.

### VI. Permission Sets & Security Governance (NON-NEGOTIABLE)

Every new feature MUST have at least one permission set. Format:
`[AppPrefix]_[Component]_[AccessLevel]` (e.g. `OrderMgmt_Product_Write`). Access levels:
Read | Write | Full | Execute | Admin. No permission set MUST grant "View All Data" or
"Modify All Data". No single permission set MUST grant more than 10 object permissions.
Read and delete permissions MUST NOT be combined in the same permission set. Individual
field permissions MUST be specified rather than object-level access where possible. A
permission set group MUST be created when an application has more than 3 related
permission sets or clear user personas are defined. A `Permissions.md` file MUST be
produced for every feature.

### VII. Lightning Web Components (LWC) Standards

Components MUST be single-purpose and reusable. SLDS guidelines MUST be followed; 
lightning base components MUST be preferred over raw SLDS. `lightning-record-edit-form` 
MUST be used for record creation and updates. Wire adapters MUST be used for reactive 
data loading; DOM manipulation MUST be minimised. All event handlers MUST be named 
`handle<EventName>`. JSDoc comments MUST be added to methods and complex logic.

### VIII. Agentforce & Agent Script Standards (If Applicable)

`AgentforceEmployeeAgent` MUST be used for internal-facing agents. Agent Script 
`apex://ClassName` targets work directly — `GenAiFunction` metadata is NOT required for 
Agent Script bundles. Topic descriptions MUST be scenario-based, specific, and 
non-overlapping. Business rules MUST reside in Flow or Apex targets — not in free-form 
prompt prose alone.

---

## Audit & Anti-Pattern Tooling

Implementation components MUST be validated against the **Salesforce PS Audit Tool**
while they are being created and before they are considered complete:

### Audit Tool Configuration

| Setting | Value |
|---------|-------|
| **Tool Location** | `~/Documents/Sf PS Audit Tool/salesforce-audit-tool-v1.2.17` |
| **Target Org** | `[YOUR-ORG-ALIAS]` |
| **Run Command** | `python3 salesforce_audit.py --sfdx [org-alias]` |
| **Reports** | `audit_reports/` |

### Audit Scope

The tool performs static analysis and 5-tier grading for:

| Category | Principles Covered |
|----------|-------------------|
| Governor Limits | SOQL/DML in loops (Principle III) |
| Security | CRUD/FLS, SOQL injection, XSS (Principle II) |
| Performance | SOQL selectivity |
| Test Coverage | Minimum 75% + assertions (Principle V) |
| Apex Best Practices | Patterns, documentation (Principle IV) |
| LWC Anti-patterns | Component standards (Principle VII) |

### Audit Gates

- **CRITICAL/High findings**: Block completion — MUST be remediated
- **Medium findings**: Should be addressed before PR
- **Low findings**: Address in future iterations

### Running an Audit

```bash
# 1. Navigate to audit tool
cd ~/Documents/Sf\ PS\ Audit\ Tool/salesforce-audit-tool-v1.2.17

# 2. Authenticate target org
sf org login web --alias my-org

# 3. Run audit
python3 salesforce_audit.py --sfdx my-org

# 4. Review report
open audit_reports/latest_report.html
```

---

## Salesforce Platform Constraints

| Constraint | Rule |
|------------|------|
| **CLI** | Always use `sf`; `sfdx` is deprecated |
| **Metadata** | Every object needs `.object-meta.xml`; every Apex class `.cls-meta.xml` |
| **API Version** | Target API 66.0+ for Agentforce / AI metadata |
| **Named Credentials** | MUST be used for all callouts |
| **Platform Events** | Loose coupling via events; error handling required |
| **SOQL** | No `SELECT *`; indexed fields in `WHERE`; use `LIMIT` |

---

## Development Workflow

1. Run `/speckit-constitution` before starting any new feature stream
2. Run `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-implement`
3. Constitution Check MUST pass in `/speckit-plan` before implementation
4. Every feature MUST include permission set(s) and `Permissions.md`
5. Run Salesforce PS Audit Tool; CRITICAL/high findings block completion
6. Run `/speckit-analyze` after tasks to catch violations before coding

---

## Governance

This constitution supersedes all other development practices within this project.
Amendments require explicit `/speckit-constitution` update and a version bump:

- **MAJOR**: Backward-incompatible removals or redefinitions
- **MINOR**: New principle or materially expanded guidance
- **PATCH**: Clarifications, wording, non-semantic refinements

---

## Customization Checklist

Before using this constitution, update:

- [ ] Replace `[YOUR-PROJECT]` with your project name
- [ ] Replace `[Your Organization]` with your org name
- [ ] Update Audit Tool location if different
- [ ] Add industry-specific principles (e.g., Health Cloud, Financial Services)
- [ ] Define your org alias in Audit Tool Configuration
- [ ] Review and adjust permission set naming conventions

---

**Version**: 1.0.0 | **Template Based On**: AgenticDev Constitution 2.1.0
