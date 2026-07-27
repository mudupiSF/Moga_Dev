# Domain Context

> Moga is a Salesforce Loan Origination System for Indian retail and commercial lending.
> Requirements must use the terminology and process boundaries below.

## Industry Overview

- **Industry**: Financial Services
- **Sub-sector**: Lending / vehicle and personal finance
- **Primary current focus**: Commercial Vehicle lending
- **Operating model**: Assisted origination by internal users, with customer verification and consent interactions through integrated services
- **Primary persona**: Sales Officer
- **Additional personas**: Credit/underwriting users, operations users, verification users, approvers, quality-control users, administrators, and applicants

## Loan Origination Lifecycle

1. **Create Application** — select Product and its valid dependent configuration; create the initial Application, Borrower, Application Line Item, and Asset where applicable.
2. **QDE (Quick Data Entry)** — capture applicant Basic Details, KYC, applicable Occupation Details, Dedupe, and Eligibility.
3. **DDE (Detailed Data Entry)** — capture Asset Details and the later detailed lending data configured in the dynamic stage framework.
4. **Credit and verification** — bureau, policy, document, field verification, deviation, underwriting, and approval activities as configured.
5. **Sanction and fulfillment** — sanction conditions, documents, disbursement, mandates, repayment, and downstream servicing handoff.

Stage and sub-stage order is metadata-driven. Specifications must inspect `Dynamic_Stage_Gate`
metadata and the relevant implementation before asserting transitions.

## QDE Routing

- QDE begins with the primary Borrower.
- Standard CV order: Basic Details → KYC Details → Occupation Details when applicable → Dedupe and Eligibility.
- Individual earning applicants use Salaried, Self-Employed Professional, or Self-Employed Non-Professional occupation forms.
- Individual Non-Earning applicants receive an explicit not-applicable Occupation state.
- Non-Individual applicants skip Occupation Details and proceed from KYC to Dedupe and Eligibility.
- CV Guarantors are optional up to the configured limit; Beneficiaries apply to Non-Individual borrowers under configured constitution rules.
- Every active applicant must complete applicable QDE stages and dedupe before QDE can complete.
- Successful QDE completion moves the Application to DDE / Asset Details.

## Core Business Rules

| Rule ID | Rule |
|---------|------|
| MOGA-APP-001 | Create is allowed only for a complete, valid product configuration. |
| MOGA-APP-002 | Product changes clear stale dependent selections; transaction-specific defaults and dependencies must be preserved exactly. |
| MOGA-QDE-001 | Customer Type controls Individual and Non-Individual field visibility and routing. |
| MOGA-QDE-002 | Phone OTP, email OTP, and application consent gate completion of Basic Details. |
| MOGA-QDE-003 | PAN is mandatory when annual income exceeds ₹4 lakh, requested loan amount exceeds ₹10 lakh, or the applicant is Non-Individual. |
| MOGA-QDE-004 | Individual applicants must be between 18 and 80 years old where date-of-birth validation applies. |
| MOGA-QDE-005 | Mobile numbers contain 10 digits and begin with 6, 7, 8, or 9. |
| MOGA-QDE-006 | Dedupe Valid requires exactly one selected match and establishes ETB; Invalid represents no acceptable match and establishes NTB. |
| MOGA-QDE-007 | Individual eligibility follows NPA → CIBIL → BRE; Non-Individual follows NPA → CRIF → BRE, subject to verified integration configuration. |
| MOGA-QDE-008 | No application or applicant may advance while a required prior stage, verification, consent, dedupe, or eligibility gate is incomplete. |
| MOGA-DOC-001 | Documents must be associated with the correct Application, Applicant, checklist item, document type, and file side. |
| MOGA-AUD-001 | Material discrepancies among approved requirements, live behavior, code, and metadata are documented and resolved explicitly. |

The detailed field and validation catalog lives in the project requirement Markdown and approved
workbooks. Do not duplicate or generalize those rules without reading the relevant source.

## Domain Entities

| Business Entity | Salesforce Mapping | Meaning |
|-----------------|--------------------|---------|
| Loan Application | `Application__c` | Root lending case containing product, amount, stage, and sub-stage |
| Applicant | `Applicant__c` | Borrower, Guarantor, Beneficiary, or other configured party |
| Product line | `Application_Line_Item__c` | Product/sub-product and requested loan details |
| Financed asset | `Asset__c` | Vehicle or financed asset details |
| Applicant address | `Applicant_Address__c` | Current, permanent, office, and proof-backed addresses |
| Applicant KYC | `Applicant_KYC__c` | KYC method, document identity, dates, and verification state |
| Employment | `Applicant_Employment__c` | Primary/previous employment or self-employment details |
| Document checklist | `Document_CheckList__c` | Required/optional document slot and uploaded file association |
| Integration checklist | `Integration_Checklist__c` | External check execution and status evidence |
| Stage configuration | Dynamic stage custom metadata | Product/persona-specific stage navigation and gating |
| Master/configuration data | `Document_Master__c`, `Industry_Code_and_Type__c`, custom metadata | Controlled values and business configuration |

## Product Taxonomy

| Code | Product |
|------|---------|
| `PL` | Personal Loan |
| `2W` | Two Wheeler |
| `4W` | Four Wheeler |
| `CV` | Commercial Vehicles |

Commercial Vehicle sub-products are LCV, SCV, MHCV, and CE. Vehicle transaction types include
New, Refinance, and Used where allowed. Never infer a valid combination; use approved product
dependencies and the Create Application requirements.

## Integration Principles

- Integration names in requirements describe business capabilities, not proof of production readiness.
- Inspect the current handler, Named Credential configuration, mocks/stubs, timeout behavior, and failure path before planning implementation.
- A failed mandatory integration blocks progression and presents an actionable, non-sensitive error.
- Retries must be idempotent and must not create duplicate applications, applicants, documents, checklist rows, or external requests.
- Sensitive request/response content must not be written to debug logs or user-facing errors.

## Operational Measures

- Application and applicant completion by stage/sub-stage.
- Verification, consent, dedupe, bureau, and eligibility success/failure rates.
- Turnaround time between configured lending stages.
- Rework caused by incomplete or invalid field/document capture.
- Integration retry and terminal-failure rates.
- Requirements-to-test and story-to-deployment traceability.

Business targets and SLAs are not yet approved and must be confirmed per feature.

## Known Domain Decisions Still Required

- CV-specific beneficiary limits versus general constitution configuration.
- Final occupation mandatory-field decisions.
- Product/role/risk-based mandatory occupation documents.
- Exact data-retention and archival policy.
- Production integration endpoints and adapter readiness.
- Business approval for discrepancies listed in the CV QDE and Application Creation requirements.

---

**Domain Owner**: To be confirmed  
**Technical Custodian**: Manasa Udupi, Solution Architect  
**Last Validated**: 2026-07-27
