# Project Details

> Central project context consulted by every SpecKit command. Unknown business decisions
> must be raised as clarifying questions rather than inferred.

## Project Information

| Field | Value |
|-------|-------|
| **Project Name** | Moga Dev |
| **Project Code** | MOGA |
| **Solution** | Salesforce Loan Origination System (LOS) |
| **Industry** | Financial Services — Indian lending |
| **Primary Product Focus** | Commercial Vehicle loans; repository also contains Personal Loan, Two Wheeler, and Four Wheeler capabilities |
| **Salesforce Org Alias** | `Moga dev` |
| **Org Type** | Sandbox |
| **Source API Version** | 66.0 |
| **Package Directory** | `force-app` |
| **GitHub Repository** | https://github.com/mudupiSF/Moga_Dev |
| **GitHub Pages Dashboard** | https://mudupiSF.github.io/Moga_Dev/progress-dashboard.html |
| **Jira** | Not configured |

## Delivery Ownership

| Role | Name | Responsibilities |
|------|------|------------------|
| Solution Architect / SpecKit contributor | Manasa Udupi | Architecture, technical governance, specification quality, implementation review |
| Product Owner | To be confirmed | Requirements approval and prioritization |
| Business Analyst | To be confirmed | Requirements traceability and business sign-off |
| QA Lead | To be confirmed | Test strategy, integration testing, and acceptance evidence |
| Salesforce Administrator | To be confirmed | Access, org configuration, and deployment support |

## Environments

| Environment | Alias / Status | Purpose |
|-------------|----------------|---------|
| Development sandbox | `Moga dev` (connected and default at setup) | Development, metadata inspection, and controlled functional validation |
| QA/Test | To be confirmed | Integration and regression testing |
| UAT | To be confirmed | Business acceptance |
| Production | To be confirmed | Live lending operations |

Never place access tokens, passwords, client secrets, customer identifiers, or environment-specific
record IDs in specifications, source files, logs, or dashboard data.

## Scope

### In Scope

- Product-driven application creation for PL, 2W, 4W, and CV products.
- Commercial Vehicle QDE: Basic Details, KYC Details, Occupation Details, Dedupe and Eligibility.
- Individual and Non-Individual borrowers, Guarantors, and applicable Beneficiaries.
- DDE and later LOS stages represented by the existing stage framework and metadata.
- Applicant identity, address, employment, document, consent, dedupe, bureau, eligibility,
  underwriting, deviation, sanction, disbursement, and repayment capabilities present in the repository.
- Apex, LWC, metadata, automated tests, permission sets, deployment validation, and dashboard tracking.

### Explicit Boundaries

- Do not describe stubbed or mock integration adapters as production-ready.
- Do not invent product rules, beneficiary limits, mandatory-document decisions, retention periods,
  integration contracts, or approval thresholds.
- Do not modify or create real Salesforce records during discovery without explicit permission.
- Jira synchronization remains out of scope until a Jira project key and board URL are supplied.

## Connected Systems and Services

| System / Service | Purpose | Current Evidence |
|------------------|---------|------------------|
| PAN verification / OCR | Identity and tax identifier verification | QDE requirements and API handlers |
| UIDAI Aadhaar eKYC | Aadhaar OTP and KYC verification | QDE requirements and `UIDAIAPIHandler` |
| Phone and email OTP | Contact verification | QDE requirements and OTP handlers |
| Customer consent | Application authorization | QDE requirements and consent flow metadata |
| Customer dedupe / CIF | ETB/NTB resolution | Dedupe services and QDE requirements |
| CIBIL / CRIF / NPA / BRE | Credit and eligibility checks | QDE requirements; adapter readiness must be verified per feature |
| AML / ScoreCard / Existing EMI | Forward and eligibility checks | Integration handlers; production status must be confirmed |
| Face liveliness / face match | Customer photograph verification | Integration handlers and QDE requirements |

All external callouts must use approved Named Credentials or External Credentials and must define
timeouts, retries, idempotency, auditability, error handling, and safe logging.

## Authoritative Evidence Order

1. Explicitly approved business requirements and sign-off decisions.
2. Observed deployed behavior when the user authorizes live validation.
3. Repository implementation and Salesforce metadata for persistence and technical behavior.
4. Existing requirement workbooks and Markdown documents.

Material conflicts must be recorded as discrepancies; they must not be silently resolved.

## Known Open Decisions

- Beneficiary minimum and maximum rules for Non-Individual CV borrowers.
- Final mandatory flags in `Occupation Mandatory fields.xlsx`.
- Whether optional occupation documents become mandatory by product, role, profession, or risk.
- Reconciliation of deployed Create Application behavior with the local LWC/Apex implementation.
- Production readiness of stubbed or mock-driven integration adapters.
- QA, UAT, production environment details, delivery milestones, and named business approvers.

## Success Measures

- Complete, traceable requirements and acceptance criteria before implementation.
- No unresolved critical SpecKit analysis findings before build.
- Bulk-safe, secure implementation with meaningful automated tests and at least 75% Apex coverage.
- No partial application graph or stage transition after a failed transaction or integration gate.
- Approved QDE journeys preserve data, enforce applicant-level completion, and provide auditable outcomes.
- Every completed story is reflected in `docs/progress-tracker.json`.

---

**Last Updated**: 2026-07-27  
**Updated By**: Manasa Udupi, Solution Architect
