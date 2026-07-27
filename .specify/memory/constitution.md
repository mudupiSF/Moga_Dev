<!--
MOGA DEV SALESFORCE DELIVERY CONSTITUTION

This project-specific constitution is grounded in the Moga Dev Salesforce repository and
Financial Services requirements. Run `/speckit-constitution` to review and formally ratify it.

Principle set:
- I.    Architectural Integrity & Platform-First (NON-NEGOTIABLE)
- II.   Security & Access Control (NON-NEGOTIABLE)
- III.  Governor Limits & Bulkification (NON-NEGOTIABLE)
- IV.   Apex Code Quality Standards
- V.    Apex Testing Standards (NON-NEGOTIABLE)
- VI.   Permission Sets & Security Governance (NON-NEGOTIABLE)
- VII.  Lightning Web Components (LWC) Standards
- VIII. Agentforce & Agent Script Standards
- IX.   Industry-First, Minimal Customization
- X.    Industry Data Model Alignment

Added sections: Audit & Anti-Pattern Tooling; Salesforce Platform Constraints;
Development Workflow; Governance.

Command references use the hyphenated Cursor form: /speckit-constitution, /speckit-specify,
/speckit-plan, /speckit-tasks, /speckit-implement, /speckit-analyze.
-->

# Moga Dev Salesforce Delivery Constitution

Governs the **Moga Dev** Salesforce Loan Origination System. This document defines
architecture and process gates; `.cursor/rules/specify-rules.mdc` provides the concise,
always-on agent context and links back to this constitution and the project memory files.

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
produced for every feature, covering: purpose, dependency mapping, role assignment
matrix, and testing checklist.

### VII. Lightning Web Components (LWC) Standards

MCP tools for LWC/Aura/LDS guidance MUST be invoked before implementation begins; do not
rely on training knowledge alone. Components MUST be single-purpose and reusable. SLDS
guidelines MUST be followed; lightning base components MUST be preferred over raw SLDS.
`lightning-record-edit-form` MUST be used for record creation and updates. Wire adapters
MUST be used for reactive data loading; DOM manipulation MUST be minimised. All event
handlers MUST be named `handle<EventName>`. JSDoc comments MUST be added to methods and
complex logic. Mobile / native capability features MUST also invoke the mobile MCP tool
before implementation.

### VIII. Agentforce & Agent Script Standards

`AgentforceEmployeeAgent` MUST be used for internal-facing agents; `default_agent_user`
MUST be omitted. `AgentforceServiceAgent` requires a dedicated Einstein Agent User and
system permission set. Agent Script `apex://ClassName` targets work directly —
`GenAiFunction` metadata is NOT required for Agent Script bundles; it is only needed for
Agent Builder / `GenAiPlannerBundle` paths. Topic descriptions MUST be scenario-based,
specific, and non-overlapping. Business rules and ground truth MUST reside in Flow or
Apex targets — not in free-form prompt prose alone. No fabricated tracking, order,
refund, or inventory data is permitted in reasoning instructions. Deploy order MUST be:
fields/metadata → Apex → Flow → `GenAiPromptTemplate` / `GenAiFunction` / `GenAiPlugin`
→ publish → `sf agent activate`. `@InvocableVariable` wrapper classes (with named
fields) MUST be used; bare `List<T>` parameters are incompatible with Agent Script
actions.

### IX. Industry-First, Minimal Customization

Standard and industry-cloud capabilities MUST be preferred over bespoke build, in this
order: (1) declarative standard features, (2) the relevant Salesforce Industry Cloud /
Revenue Lifecycle Management features for the project's domain, (3) configuration, and only
then (4) custom metadata or code. A custom object, field, Apex class, or LWC MAY be
introduced ONLY when no generally-available standard equivalent exists; the
justification and the rejected simpler alternative MUST be recorded in the spec's
Complexity Tracking. Redundant or duplicate custom objects are prohibited.

Rationale: minimal customization is upgrade-safe, lower-maintenance, and aligned with
the platform roadmap; custom build is a deliberate, documented exception. This principle
operationalizes Principle I.

### X. Industry Data Model Alignment

The solution MUST model entities on the relevant Salesforce industry / standard data
model rather than reinventing it. Align to the canonical objects for the project's domain
(as recorded in `.specify/memory/domain.md`), for example:

- Organizations = `Account`; People = `Contact` (or Person Account where adopted).
- Party relationships MUST use the native relationship model (Account Contact
  Relationship / industry affiliations) rather than ad-hoc custom junctions.
- Reusable execution checklists MUST use standard Action Plans
  (ActionPlan / ActionPlanTemplate) where applicable.
- Product, pricing, and quote-to-cash MUST use Revenue Lifecycle Management
  (Product2 / Pricebook / Selling Models → Opportunity → Quote → Order → Asset).

Deviations from this data model MUST be justified in the spec.

Rationale: the industry data model is proven, interoperable, and reduces bespoke
maintenance; it is the canonical target shape for the solution.

## Audit & Anti-Pattern Tooling

Implementation components MUST be validated against the **Salesforce PS Audit Tool**
while they are being created and before they are considered complete:

- **Location**: the Salesforce PS Audit Tool installed on the delivery machine
  (configure the path for your environment).
- **Scope**: static analysis and 5-tier grading for governor-limit violations
  (SOQL/DML in loops), security (CRUD/FLS, SOQL injection, XSS), performance / SOQL
  selectivity, test coverage, Apex best practices, and LWC anti-patterns — directly
  mirroring Principles II, III, IV, V, and VII.
- **Usage**: authenticate the target org (`sf org login web` / `sfdx auth:web:login`),
  then run `python3 salesforce_audit.py --sfdx <org>` and review the report in
  `audit_reports/`.
- **Gate**: anti-patterns flagged by this tool MUST be remediated. CRITICAL/high-severity
  findings block completion. Findings surfaced via `/speckit-analyze` are automatically
  CRITICAL and MUST be resolved before implementation continues.

## Salesforce Platform Constraints

**CLI**: Always use `sf`; `sfdx` is deprecated. **Metadata files**: Every new object MUST
have `.object-meta.xml`; every Apex class `.cls-meta.xml`; every trigger
`.trigger-meta.xml`. **API version**: Target API 66.0+ for all Agentforce / AI metadata.
**Integration**: Named Credentials MUST be used for callouts; timeout and retry
mechanisms are required; bulk operations for data sync. **Platform Events**: Loose
coupling via events; delivery mode chosen per commit semantics; error handling required;
governor limits considered. **SOQL**: No `SELECT *`; indexed fields in `WHERE` clauses;
`LIMIT` clauses where appropriate.

## Development Workflow

- Run `/speckit-constitution` before starting any new feature stream.
- Run `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-implement` in
  order.
- Constitution Check MUST pass in `/speckit-plan` before implementation begins.
- Every feature MUST include permission set(s) and `Permissions.md`.
- Implementation components MUST be audited with the Salesforce PS Audit Tool (see
  "Audit & Anti-Pattern Tooling"); CRITICAL/high findings block completion.
- Apex classes MUST be deployed before GenAiFunctions; agent bundle deployed last.
- Agent bundles MUST be published (`sf agent publish authoring-bundle`) and then
  explicitly activated (`sf agent activate`) as separate steps.
- `/speckit-analyze` MUST be run after tasks are generated to catch constitution
  violations before code is written.

## XII. Progress Tracking (Mandatory)

**After completing any user story implementation:**

1. **Update Dashboard** - Run `/speckit-dashboard` or manually update `docs/progress-tracker.json`
2. **Mark Story Built** - Set `built: true`, `built_by`, and `built_date` for the story
3. **Record Tokens** - Add a session entry to `token_consumption.by_epic[].sessions`
4. **Commit Tracker** - Commit the updated `progress-tracker.json` with the code changes
5. **Push to Remote** - Ensure dashboard updates are visible to all contributors

**The progress dashboard is the single source of truth for project status.**

Skipping dashboard updates is a constitution violation. If work is completed but not
tracked, it creates confusion for project managers, stakeholders, and other contributors.

## Governance

This constitution supersedes all other development practices within this project.
Amendments require explicit `/speckit-constitution` update and a version bump following
semantic versioning:

- **MAJOR**: backward-incompatible removals or redefinitions of existing principles.
- **MINOR**: new principle or materially expanded guidance.
- **PATCH**: clarifications, wording, non-semantic refinements.

Constitution violations in `/speckit-plan` MUST be documented in the Complexity Tracking
table with justification. Constitution violations flagged by `/speckit-analyze` are
automatically CRITICAL and MUST be resolved before implementation begins. "View All
Data" and "Modify All Data" MUST never be granted in a functional permission set under
any circumstances.

Implementation must also honor `.cursor/rules/*.mdc` and `.specify/memory/*.md`.
This constitution governs architecture and process gates. More specific project rules
may add implementation detail but may not weaken a non-negotiable principle.

**Version**: 1.0.0 | **Status**: Draft pending `/speckit-constitution` review | **Prepared**: 2026-07-27
