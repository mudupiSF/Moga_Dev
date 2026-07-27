# Project Taxonomy

> Canonical Moga terminology and naming. Preserve existing API names exactly, including legacy
> capitalization or spelling. New names follow the conventions below.

## Business Glossary

| Term | Definition | Salesforce Mapping |
|------|------------|-------------------|
| Application | A loan-origination case for one selected product configuration | `Application__c` |
| Applicant | A party participating in an Application | `Applicant__c` |
| Borrower | Primary applicant whose loan request drives the Application | `Applicant__c` with borrower role / primary indicator |
| Guarantor | Additional applicant supporting repayment obligations | `Applicant__c` |
| Beneficiary | Beneficial owner/controlling party captured for a Non-Individual borrower | `Applicant__c` |
| Application Line Item | Product/sub-product and requested lending details | `Application_Line_Item__c` |
| Asset | Vehicle or other financed asset | `Asset__c` |
| Document Checklist | Configured document requirement and uploaded-file association | `Document_CheckList__c` |
| QDE | Quick Data Entry: Basic Details, KYC, applicable Occupation, Dedupe and Eligibility | Application stage/sub-stage and dynamic stage metadata |
| DDE | Detailed Data Entry following successful QDE | Application stage/sub-stage and dynamic stage metadata |
| ETB | Existing to Bank | `Applicant__c.Relationship_with_Bank__c` |
| NTB | New to Bank | `Applicant__c.Relationship_with_Bank__c` |
| Dedupe | Match review that resolves an applicant against customer records | Customer Dedupe integration and applicant status |
| Eligibility | Credit/risk gate using configured checks and the BRE | Applicant/Application integration status |
| Current stage complete | Applicant-level marker for the most recently completed loan stage | `Applicant__c.Current_Loan_Stage_Complete__c` |

## Product and Process Acronyms

| Acronym | Meaning |
|---------|---------|
| LOS | Loan Origination System |
| PL | Personal Loan |
| 2W | Two Wheeler |
| 4W | Four Wheeler |
| CV | Commercial Vehicles |
| LCV | Light Commercial Vehicles |
| SCV | Small Commercial Vehicles |
| MHCV | Medium & Heavy Commercial Vehicles |
| CE | Construction Equipment |
| KYC | Know Your Customer |
| CKYC | Central Know Your Customer |
| PAN | Permanent Account Number |
| POA / POI | Proof of Address / Proof of Identity |
| PEP | Politically Exposed Person |
| CIF | Customer Information File identifier |
| CASA | Current Account / Savings Account |
| OTP | One-Time Password |
| AML | Anti-Money Laundering |
| NPA | Non-Performing Asset check |
| CIBIL | Individual credit-bureau check |
| CRIF | Non-Individual/business credit-bureau check |
| BRE | Business Rule Engine |
| FI | Field Investigation |
| TAT | Turnaround Time |
| SEP | Self-Employed Professional |
| SENP | Self-Employed Non-Professional |

## Existing Core Objects

| Category | Objects |
|----------|---------|
| Origination | `Application__c`, `Application_Line_Item__c`, `Applicant__c`, `Asset__c` |
| Applicant detail | `Applicant_Address__c`, `Applicant_KYC__c`, `Applicant_Employment__c`, applicant income and reference objects |
| Documents and verification | `Document_CheckList__c`, `Document_Master__c`, `Verified_Fields__c`, QC verification metadata |
| Integrations | `Integration_Checklist__c`, integration handler/controller classes, platform events and Named Credentials where configured |
| Credit and fulfillment | Deviation, sanction, payment/disbursement, repayment mandate, valuation, and investigation objects represented in metadata |
| Configuration | Dynamic stage, query, committee, document, field-verification, and other custom metadata types |

## Naming Conventions for New Components

### Metadata

| Type | Pattern | Example |
|------|---------|---------|
| Custom object | Descriptive singular `Pascal_Case__c` | `Loan_Beneficiary__c` |
| Custom field | Descriptive `Pascal_Case__c` | `Required_Loan_Amount__c` |
| Custom metadata type | Descriptive `Pascal_Case__mdt` | `Eligibility_Rule__mdt` |
| Custom metadata record | `<Type>.<StableDeveloperName>` | `Eligibility_Rule.CV_Individual` |
| Custom label | `<Domain>_<Purpose>` | `QDE_Phone_Verification_Pending` |

Do not add a namespace-like prefix to new API names unless an approved packaging namespace exists.
Search the current schema before creating any object or field to avoid duplicates.

### Apex

| Type | Pattern | Example |
|------|---------|---------|
| Trigger | `<Object>Trigger` | `ApplicationTrigger` |
| Trigger handler | `<Object>TriggerHandler` | `ApplicationTriggerHandler` |
| Domain/service | `<Domain>Service` | `CustomerDedupeService` |
| Integration handler | `<Capability>APIHandler` | `AMLCheckAPIHandler` |
| Controller | `<Feature>Controller` | `CreateApplicationController` |
| Queueable | `<Process>Queueable` | `EligibilityRetryQueueable` |
| Batch | `<Process>Batch` | `DocumentCleanupBatch` |
| Test class | `<ClassName>Test` | `CreateApplicationControllerTest` |

Preserve established names such as `WheelsEmploymentDetailsController` when extending an existing
feature. Do not rename solely to satisfy a new convention without an approved migration.

### Lightning Web Components

| Item | Convention | Example |
|------|------------|---------|
| Bundle | `camelCase`, feature-oriented | `createApplication`, `customerDedupeMasterPage` |
| Event handler | `handle<EventName>` | `handleProductSelected` |
| Boolean | `is/has/can/should` prefix | `isSubmitting` |
| Apex import | Explicit method import | `@salesforce/apex/CreateApplicationController.createApplication` |
| Custom event | Lowercase semantic name | `stagecomplete` |

Use one bundle for one clear responsibility. Shared picklist, file, spinner, preview, and integration
UI must reuse existing components where suitable.

### Permission Sets

New functional permission sets use `Moga_<Feature>_<AccessLevel>`, for example
`Moga_QDE_Write` or `Moga_Eligibility_Execute`. Access levels are `Read`, `Write`, `Execute`,
or `Admin`. Use permission-set groups for personas. Do not add broad administrative permissions
to functional sets.

## Canonical Status and Role Terms

- Applicant roles: Borrower, Guarantor, Beneficiary. Co-Borrower is product-specific and must not be
  applied to CV without approved requirements. Co-Guarantor is not supported by current CV requirements.
- Customer type: Individual, Non-Individual.
- Income categories: Salaried, Self Employed Professional, Self Employed Non Professional, Non-Earning.
- QDE sub-stages: Basic Details, KYC Details, Occupation Details, Dedupe and Eligibility.
- Use `Commercial Vehicles` for the display label and `CV` for the stored/product code.
- Use `Non-Individual` and `Non-Earning` consistently, including the hyphen.

## Requirement and Test Identifiers

- Epics use a stable business name.
- User stories use `US-<FEATURE-KEY>-<three digits>`, e.g. `US-CV-QDE-001`.
- Functional requirements use `FR-<three digits>` within a feature specification.
- Business rules use `MOGA-<AREA>-<three digits>`.
- Apex tests describe behavior and expected outcome; avoid environment-specific record identifiers.

---

**Version**: 1.0  
**Last Updated**: 2026-07-27  
**Custodian**: Manasa Udupi, Solution Architect
