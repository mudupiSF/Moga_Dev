# Regulatory and Compliance Context

> Moga processes identity, contact, financial, employment, bureau, KYC, and document data for
> Indian lending. This file defines engineering guardrails, not legal advice. Compliance owners
> must confirm exact applicability, retention periods, consent wording, and evidence requirements.

## Regulatory Baseline to Confirm

| Regulation / Standard | Relevance to Moga | Required Confirmation |
|-----------------------|-------------------|-----------------------|
| RBI Know Your Customer (KYC) Master Direction | Customer identification, verification, beneficial ownership, PEP and ongoing due diligence | Regulated entity, product applicability, accepted KYC methods, retention |
| Prevention of Money Laundering Act and Rules | KYC records, beneficial ownership, AML checks, retention and audit evidence | Compliance control mapping and retention |
| Digital Personal Data Protection Act, 2023 and applicable rules | Processing, consent/notice, purpose limitation, security safeguards, rights and breach handling | Effective obligations and organization roles |
| Aadhaar Act, UIDAI regulations and applicable KUA/AUA controls | Aadhaar OTP/eKYC, consent, masking, storage and display restrictions | Approved integration model and data-storage rules |
| RBI Digital Lending Guidelines | Digital lending disclosures, consent, data collection and service-provider controls where applicable | Whether each Moga journey is in scope |
| Credit Information Companies regulation / bureau contracts | CIBIL/CRIF request, response, permissible purpose, access and audit | Contractual controls and retention |
| Information Technology Act and security rules | Electronic records and reasonable security practices | Current legal/security baseline |
| PCI DSS | Only if payment-card data enters scope | Confirm exclusion or approved card-data design |

Do not claim compliance merely because a feature exists. Every feature specification must identify
the applicable control, implementation evidence, owner, and test.

## Data Classification

| Level | Moga Examples | Minimum Handling |
|-------|---------------|------------------|
| Public | Approved product help text | Standard integrity controls |
| Internal | Non-sensitive configuration, generic process documentation | Authenticated access; no public sharing unless approved |
| Confidential | Application status, loan amount, employment, income, addresses, contact details | Least privilege, sharing enforcement, field-level security, encrypted transport, audited access |
| Highly Confidential | PAN, Aadhaar-derived data, KYC documents, photographs, bureau/AML results, bank-account details, OTP/consent evidence | Strict role-based access, masking, encryption where approved, detailed auditing, controlled export, no debug logging |
| Secret | Access tokens, client secrets, private keys, passwords, OTP values | Approved secret store / Named or External Credentials only; never source control, specs, dashboard, or logs |

All new fields must have Salesforce data classification metadata and a documented business owner.

## Privacy and Purpose Limitation

- Collect only data required by an approved lending, KYC, risk, servicing, or regulatory purpose.
- State purpose and consent/notice requirements before designing customer-facing capture.
- Do not reuse PAN, Aadhaar, contact, bureau, financial, employment, or document data for an
  unrelated purpose without explicit approval.
- A customer changing a verified phone/email value must re-enter the applicable verification path.
- Consent records must capture the approved evidence, timestamp, channel, purpose/version, and status.
- Specifications must define cancellation, expiry, resend, retry, revocation, and failure behavior.
- Data-subject/customer request handling and deletion restrictions require compliance approval.

## KYC, Aadhaar, and Identity Controls

- PAN and Aadhaar values must be masked in user interfaces, logs, screenshots, test evidence, and exports
  except where a specifically authorized role and approved use require the full value.
- Never store raw OTP values after verification and never include them in telemetry.
- Aadhaar/eKYC flows require explicit approved consent and must use only approved providers and methods.
- KYC document access must be limited by persona, applicant, and Application sharing.
- Verification status must distinguish pending, successful, failed, expired, and unavailable outcomes.
- OCR/extracted values are untrusted input until validated and associated with the correct applicant.
- Manual overrides of failed KYC, dedupe, AML, bureau, or eligibility checks require an approved,
  auditable exception process; they must not be silently implemented.

## Access Control

- Apex data access uses `with sharing` or a documented stricter model.
- Enforce object, field, and record access with user-mode SOQL/DML or equivalent explicit controls.
- Use permission sets and permission-set groups; do not solve functional access with profiles or
  broad `View All Data` / `Modify All Data`.
- Integration users receive only the API and object/field permissions required for their capability.
- Sensitive documents and integration responses require explicit download/export authorization.
- Access failures must be fail-closed and must not reveal protected values in error messages.

## Integration and Secret Management

- Use Named Credentials / External Credentials for endpoints and secrets.
- Never commit or print access tokens, refresh tokens, client secrets, certificates, or credentials.
- Log correlation IDs, status, duration, and safe error categories—not sensitive request/response bodies.
- Validate endpoint allowlists, TLS, timeouts, retries, idempotency, and response schemas.
- Record auditable business outcomes for mandatory checks without exposing sensitive payloads.
- Mocks and stubs must be visibly non-production and cannot satisfy production-readiness gates.

## Audit Requirements

At minimum, preserve auditable evidence for:

- Application and applicant stage/sub-stage transitions.
- Identity/KYC method and outcome, consent outcome, dedupe resolution, ETB/NTB classification.
- Bureau, AML, NPA, BRE, eligibility, deviation, approval, and override outcomes.
- Sensitive record changes, document upload/replacement/deletion, and access-control changes.
- Integration execution status and retry/terminal-failure outcome.
- Deployment, permission, and configuration changes.

Use standard audit fields, Field History Tracking, Setup Audit Trail, Event Monitoring, platform
events, or approved custom audit records based on the control. Never use `System.debug()` as audit evidence.

## Retention and Deletion

Exact periods are not yet approved. Until compliance supplies a retention schedule:

- Do not hardcode retention durations in Apex, Flow, or metadata.
- Do not purge Applications, Applicants, KYC, documents, bureau/AML results, consent, or audit evidence.
- Design archival/deletion through configurable policy with legal-hold support and auditable execution.
- Ensure deletion covers derived copies, files, integration payload stores, exports, and non-production data.
- Use masked or synthetic test data; production personal data in sandboxes requires explicit approval and controls.

## Secure Development Checklist

- [ ] Applicable regulation/control and owner identified.
- [ ] Data elements classified; minimization and purpose documented.
- [ ] CRUD/FLS/sharing and persona matrix implemented and tested.
- [ ] Sensitive values masked and excluded from logs/errors.
- [ ] Consent, verification, retry, timeout, expiry, and failure states covered.
- [ ] Named/External Credential used; no secret is in source or metadata values.
- [ ] Audit evidence and retention requirements documented.
- [ ] Positive, negative, unauthorized, bulk, and rollback tests included.
- [ ] Security review completed for customer identity, documents, integrations, and public/guest access.
- [ ] Compliance approval recorded for unresolved legal or policy decisions.

## Open Compliance Decisions

- Named Compliance/Privacy owner and Security owner.
- Exact regulatory applicability by lender, product, and channel.
- Approved consent text, versions, evidence, and revocation behavior.
- Aadhaar data storage, masking, and provider obligations.
- Retention/archive/deletion periods and legal-hold process.
- Encryption scope and key-management policy.
- Sandbox data masking and production-data access policy.
- Incident response and regulatory/customer notification requirements.

---

**Compliance Owner**: To be confirmed  
**Technical Custodian**: Manasa Udupi, Solution Architect  
**Last Reviewed**: 2026-07-27
