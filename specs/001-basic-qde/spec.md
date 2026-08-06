# Feature Specification: Basic QDE

**Feature Branch**: `001-basic-qde`

**Created**: 2026-08-06

**Status**: Draft — clarified and ready for wireframe

**Input**: User description: "Create the Basic QDE specification using `User stories_Basic_QDE_Final.xlsx` as the reconciled source. Treat Final Fields as the final screen inventory and Final User Stories as approved requirements."

**Authoritative requirement source**: `User stories_Basic_QDE_Final.xlsx`

## User Scenarios & Testing

### User Story US-QDE-BASIC-CV-002 — Capture Individual or Non-Individual Application Details (Priority: P1)

As a Sales Officer, I want to select the Borrower Customer Type and complete the applicable details so that the correct Commercial Vehicle Borrower branch is used.

**Why this priority**: Customer Type controls the remainder of Basic Details and determines which applicant data is applicable.

**Independent Test**: Open Basic Details with a Borrower whose downstream sections are not yet complete, select each Customer Type, and verify the corresponding Application Details without relying on later QDE stages.

**Acceptance Scenarios**:

1. **Given** Customer Type is Individual, **When** Application Details is displayed, **Then** Non-Individual entity, industry, and evaluation fields are not displayed.
2. **Given** Customer Type is Non-Individual, **When** Application Details is displayed, **Then** Applicant Type (Entity Type), Entity Name, Industry Name, and Evaluation Type are required.
3. **Given** a Non-Individual Industry Name is selected, **When** the selection is accepted, **Then** its corresponding Industry Code is derived.
4. **Given** a required Non-Individual field is missing, **When** section completion is evaluated, **Then** the next section remains unavailable and the missing information is identified.
5. **Given** the Sales Officer changes Customer Type, **When** the applicable branch refreshes, **Then** values that no longer apply are cleared or hidden while Branch and Required Loan Amount are retained.
6. **Given** valid Application Details were saved, **When** the Sales Officer revisits Basic Details, **Then** the saved applicable customer and entity details are displayed.
7. **Given** Customer Type is Non-Individual, **When** Applicant Type options are displayed, **Then** Proprietorship is not available for selection.

---

### User Story US-QDE-BASIC-CV-003 — Capture CV Loan Basic Information (Priority: P1)

As a Sales Officer, I want to select the Branch and enter the Required Loan Amount so that the Application contains its basic commercial loan request.

**Why this priority**: Branch and loan amount are required inputs for progression and the mandatory-PAN decision.

**Independent Test**: Start with completed Application Details, capture Branch and Required Loan Amount, and verify section progression and persistence without completing document or consent activities.

**Acceptance Scenarios**:

1. **Given** Application Details is complete, **When** Loan Basic Info is displayed, **Then** the Sales Officer can select a Branch and Purpose of Purchase is displayed as Commercial for a CV Application.
2. **Given** Branch is incomplete, **When** progression is evaluated, **Then** Loan Detail remains unavailable.
3. **Given** Loan Detail is available, **When** the Sales Officer enters Required Loan Amount, **Then** it accepts numbers with up to two decimal places and displays Indian digit grouping.
4. **Given** Required Loan Amount is blank or invalid, **When** the Sales Officer leaves the field, **Then** section progression remains blocked.
5. **Given** Required Loan Amount exceeds ₹10,00,000, **When** document rules are evaluated, **Then** PAN becomes mandatory.
6. **Given** Branch and Required Loan Amount were saved, **When** Basic Details is revisited, **Then** the saved values are displayed.

---

### User Story US-QDE-BASIC-CV-004 — Capture Individual Professional Details (Priority: P2)

As a Sales Officer, I want to capture an Individual Borrower’s profile and income category so that the applicable Occupation Details journey can be determined.

**Why this priority**: These details determine Individual occupation routing but do not apply to Non-Individual Borrowers.

**Independent Test**: Use an Individual Borrower with completed Loan Detail and verify both Income Available paths through completion of Professional Detail.

**Acceptance Scenarios**:

1. **Given** the Borrower is Individual and Loan Detail is complete, **When** Income Available is Yes, **Then** Profile Type, Annual Income, and Occupation Category are required.
2. **Given** Income Available is Yes, **When** Occupation Category is selected, **Then** the applicable earning categories are available.
3. **Given** the Borrower is Individual, **When** Income Available changes to No, **Then** Annual Income is cleared and hidden and Occupation Category becomes locked as Non-Earning.
4. **Given** a required professional or income value is missing, **When** section completion is evaluated, **Then** Document Verification remains unavailable and the missing information is identified.
5. **Given** Income Available changes from No to Yes, **When** the section refreshes, **Then** Non-Earning is cleared, Annual Income becomes required, and an earning category can be selected.
6. **Given** Annual Income exceeds ₹4,00,000, **When** document rules are evaluated, **Then** PAN becomes mandatory.
7. **Given** Professional Detail was saved, **When** Basic Details is revisited, **Then** applicable values are displayed and hidden inapplicable values are not restored.

---

### User Story US-QDE-BASIC-CV-005 — Apply PAN Availability and Mandatory-PAN Rules (Priority: P1)

As a Sales Officer, I want the permitted PAN or Form 60 path to be selected according to approved rules so that regulatory document requirements cannot be bypassed.

**Why this priority**: The selected document path gates identity capture, verification, consent, and progression.

**Independent Test**: Exercise threshold and Customer Type combinations and verify the resulting PAN/Form 60 choice before uploading a document.

**Acceptance Scenarios**:

1. **Given** an Individual has Annual Income at or below ₹4,00,000 and Required Loan Amount at or below ₹10,00,000, **When** Document Verification is displayed, **Then** Is PAN Available defaults to Yes and can be changed between Yes and No.
2. **Given** Annual Income exceeds ₹4,00,000, Required Loan Amount exceeds ₹10,00,000, or Customer Type is Non-Individual, **When** document rules are evaluated, **Then** PAN is mandatory and Is PAN Available cannot be changed to No.
3. **Given** PAN is mandatory, **When** the Sales Officer attempts to select the Form 60 path, **Then** the selection is prevented and the mandatory-PAN message is displayed.
4. **Given** the Sales Officer changes between PAN and Form 60, **When** the document path refreshes, **Then** data from the previous path is cleared or deactivated so only one path remains active.
5. **Given** PAN was previously verified, **When** Basic Details is revisited, **Then** PAN availability and verified identity information remain read-only.

---

### User Story US-QDE-BASIC-CV-006 — Upload and Verify PAN Identity (Priority: P1)

As a Sales Officer, I want to upload and verify PAN identity details so that the Borrower’s identity is validated before contact capture.

**Why this priority**: Successful PAN identity verification is a mandatory gate for the PAN path.

**Independent Test**: Use a Borrower on the PAN path, provide permitted PAN document input and controlled verification outcomes, and validate the complete PAN flow without progressing to KYC.

**Acceptance Scenarios**:

1. **Given** Is PAN Available is Yes, **When** an allowed PAN document is uploaded, **Then** PAN number and applicable identity information are extracted and displayed for review.
2. **Given** reviewed PAN information is complete and valid, **When** Verify is selected, **Then** the PAN and applicable Individual or Non-Individual identity details are verified.
3. **Given** PAN verification succeeds, **When** the result is accepted, **Then** verified PAN information is locked against further editing.
4. **Given** the PAN number has an invalid format or constitution character, **When** validation runs, **Then** an applicable error is displayed and verification is not requested.
5. **Given** extraction or PAN verification fails or is unavailable, **When** the failure is received, **Then** a safe, user-readable failure is displayed, retry or correction remains available, and progression is blocked.
6. **Given** Customer Type is Non-Individual, **When** PAN information is reviewed or re-verified, **Then** Entity Name and Date of Incorporation are used instead of Individual name and Date of Birth.
7. **Given** a PAN document exists, **When** the Sales Officer previews, deletes, or replaces it, **Then** the action applies to the correct document and section completion is recalculated.
8. **Given** PAN verification has not succeeded, **When** progression is evaluated, **Then** Contact Info and Next remain unavailable.

---

### User Story US-QDE-BASIC-CV-007 — Capture the Individual Form 60 Identity Path (Priority: P2)

As a Sales Officer, I want to capture Form 60 details when PAN is not available so that an eligible Individual can continue through the permitted non-PAN route.

**Why this priority**: This is the approved alternative identity path for eligible Individuals.

**Independent Test**: Use an Individual below both mandatory-PAN thresholds, select PAN unavailable, and complete Form 60 identity capture without invoking PAN-dependent verification.

**Acceptance Scenarios**:

1. **Given** an eligible Individual selects Is PAN Available as No, **When** Document Verification refreshes, **Then** First Name, Last Name, and Form 60 upload are displayed.
2. **Given** Form 60 is uploaded, **When** identity fields are displayed, **Then** Date of Birth and PAN Acknowledgement Number are required.
3. **Given** PAN Acknowledgement Number is entered, **When** it is processed, **Then** only digits are accepted and the value is limited to 18 digits.
4. **Given** Date of Birth is entered or populated, **When** age is evaluated, **Then** the Individual must be between 18 and 80 years old and an applicable error prevents progression otherwise.
5. **Given** Form 60, First Name, Last Name, Date of Birth, or PAN Acknowledgement Number is missing, **When** section completion is evaluated, **Then** Contact Info and Next remain unavailable and the missing information is identified.
6. **Given** income or loan amount subsequently makes PAN mandatory, **When** document rules refresh, **Then** the Form 60 path is cleared and the PAN path becomes mandatory.
7. **Given** the Form 60 path is complete, **When** the Sales Officer continues, **Then** PAN-dependent verification and forward checks are not requested.
8. **Given** a Form 60 document was uploaded, **When** the Sales Officer chooses View, Delete, or Re-upload, **Then** the corresponding action is available for that document.

---

### User Story US-QDE-BASIC-CV-008 — Verify Contact Details and Obtain Application Consent (Priority: P1)

As a Sales Officer, I want to verify the Borrower’s contact details and obtain Application consent so that the customer can authorize the loan Application.

**Why this priority**: Verified contact channels and accepted consent are mandatory gates for Basic Details completion.

**Independent Test**: Begin with completed Document Verification, exercise contact validation, verification, contact changes, and consent outcomes, and verify the progression state.

**Acceptance Scenarios**:

1. **Given** Document Verification is complete, **When** Contact Info is displayed, **Then** applicable Individual or Non-Individual contact fields are shown and Mobile Number and Email Address are required.
2. **Given** Mobile Number is entered, **When** format validation runs, **Then** it must contain exactly 10 digits and begin with 6, 7, 8, or 9.
3. **Given** Email Address is entered, **When** format validation runs, **Then** it must satisfy the approved email format.
4. **Given** a valid Mobile Number or Email Address, **When** Verify is selected, **Then** the applicable verification challenge is sent and only a valid, unexpired result marks the value verified.
5. **Given** verification is incorrect, expired, or unavailable, **When** verification is attempted, **Then** an applicable error is displayed, the value remains unverified, and approved resend or retry behavior is available.
6. **Given** a verified Mobile Number or Email Address changes, **When** the change is accepted, **Then** prior verification is cancelled and the changed value must be verified again.
7. **Given** phone and email are verified, **When** Consent is selected, **Then** a customer consent link is generated and the sent status is recorded.
8. **Given** the customer completes the consent interaction, **When** the Sales Officer screen refreshes, **Then** accepted consent is displayed.
9. **Given** contact verification or consent is incomplete, **When** progression is evaluated, **Then** Next remains unavailable.

---

### User Story US-QDE-BASIC-CV-009 — Save Basic Details and Navigate to KYC (Priority: P1)

As a Sales Officer, I want Save and Next to retain completed Basic Details and continue to KYC so that the Borrower can progress through QDE safely.

**Why this priority**: This story delivers durable capture and controlled progression to the next configured QDE sub-stage.

**Independent Test**: Exercise Save and Next with complete, incomplete, successful, failed, and duplicate-submission conditions while observing persistence and stage state.

**Acceptance Scenarios**:

1. **Given** valid Basic Details were entered, **When** Save is selected, **Then** current values are retained without advancing to KYC.
2. **Given** saved Basic Details, **When** the sub-stage is revisited, **Then** the saved values are displayed.
3. **Given** a required field, validation, verification, or consent is incomplete, **When** progression is evaluated, **Then** Next remains unavailable and the unresolved section or validation is identified.
4. **Given** all required sections, contact verification, document verification, and consent are complete, **When** Next is selected, **Then** Basic Details is saved and applicable forward checks run.
5. **Given** all mandatory save and forward checks succeed, **When** processing completes, **Then** QDE KYC Details opens.
6. **Given** the Borrower uses the PAN path, **When** Next is selected, **Then** CIF-on-PAN, ETB/CASA, Customer Dedupe, and Recent Lead validation run in the configured sequence and progression requires successful mandatory outcomes.
7. **Given** the Borrower uses Form 60, **When** Next is selected, **Then** PAN-dependent forward checks are skipped and remaining applicable checks continue.
8. **Given** save or a required check fails, **When** failure is returned, **Then** a safe error is displayed, Basic Details is not marked complete, navigation does not occur, and retry remains possible.
9. **Given** Save or Next is already processing, **When** it is selected again, **Then** duplicate submission is prevented.
10. **Given** Basic Details completed successfully, **When** it is later revisited, **Then** completed information is displayed read-only.

---

### User Story US-QDE-BASIC-CV-010 — Display Automatically Calculated Age (Priority: P3)

As a Sales Officer, I want Age to be calculated from the applicable birth or incorporation date so that I can view applicant or entity age without entering it manually.

**Why this priority**: Age is explicitly non-mandatory and does not independently gate Basic Details completion.

**Independent Test**: Supply and change an applicable source date for each Customer Type and verify Age display and non-blocking behavior.

**Acceptance Scenarios**:

1. **Given** a valid Date of Birth is available for an Individual, **When** identity details are displayed, **Then** Age is automatically calculated from Date of Birth and displayed.
2. **Given** a valid Date of Incorporation is available for a Non-Individual, **When** entity identity details are displayed, **Then** Age is automatically calculated from Date of Incorporation and displayed.
3. **Given** the applicable source date is blank, **When** Age is evaluated, **Then** Age remains blank and does not independently block section completion.
4. **Given** the applicable source date changes before identity verification is locked, **When** the changed date is accepted, **Then** Age is recalculated.

### Edge Cases

- Customer Type changes after customer-type-specific fields have values.
- Income Available changes after Annual Income and Occupation Category have values.
- Income or loan amount crosses a mandatory-PAN threshold after Form 60 data was entered.
- PAN or Form 60 upload is deleted or replaced after identity fields were populated.
- PAN extraction succeeds but PAN verification fails.
- Mobile Number or Email Address changes after successful verification.
- Consent remains pending, fails, or cannot be refreshed.
- Save or Next is selected repeatedly while processing.
- A mandatory forward check is unavailable or returns an indeterminate result.
- The applicable source date for Age is blank or changes.

## Requirements

### Functional Requirements

- **FR-001**: Basic Details MUST support Individual and Non-Individual Borrower paths controlled by Customer Type.
- **FR-002**: Changing Customer Type MUST clear or hide no-longer-applicable entity, industry, identity, professional, and contact values while retaining Branch and Required Loan Amount.
- **FR-003**: For a Non-Individual, Applicant Type MUST exclude Proprietorship and use the exact Final Fields value set: Partnership & Limited Liability; Partnership; Company (Private Ltd & Public Ltd); Hindu Undivided Family; Trust (Charitable, Non-Charitable); Society, school (a unit of Trust/Society); Joint Venture; One Person Company; and Association Of Person.
- **FR-004**: Entity Name, Industry Name, and Evaluation Type MUST be required for a Non-Individual.
- **FR-005**: Selecting Industry Name MUST derive the corresponding Industry Code from active master data.
- **FR-006**: Loan Basic Info MUST become available only after required Application Details are complete.
- **FR-007**: Branch MUST be required before Loan Detail becomes available.
- **FR-008**: Required Loan Amount MUST accept numeric input with up to two decimal places and display Indian digit grouping.
- **FR-009**: For an Individual with Income Available as Yes, Profile Type, Annual Income, and Occupation Category MUST be required.
- **FR-010**: When Income Available changes to No, Annual Income MUST be cleared and hidden and Occupation Category MUST be set to locked Non-Earning.
- **FR-011**: PAN MUST be mandatory when Annual Income exceeds ₹4,00,000, Required Loan Amount exceeds ₹10,00,000, or Customer Type is Non-Individual.
- **FR-012**: An eligible Individual at or below both mandatory-PAN thresholds MUST be able to select either PAN or Form 60.
- **FR-013**: Changing between PAN and Form 60 MUST clear or deactivate data from the prior path.
- **FR-014**: The PAN path MUST require an allowed PAN document, valid PAN format, applicable identity details, and successful PAN verification before contact capture.
- **FR-015**: Successful PAN verification MUST lock verified PAN identity details.
- **FR-016**: Failed or unavailable PAN extraction or verification MUST not mark PAN verified or permit progression.
- **FR-017**: The Form 60 path MUST be available only to an eligible Individual and MUST require Form 60, First Name, Last Name, Date of Birth, and PAN Acknowledgement Number.
- **FR-018**: PAN Acknowledgement Number MUST contain only digits and MUST be limited to 18 digits.
- **FR-019**: Individual Date of Birth MUST represent an age from 18 through 80 years.
- **FR-020**: Uploaded PAN and Form 60 documents MUST support the approved View, Delete, Replace, and Re-upload actions.
- **FR-021**: Age MUST be a non-mandatory, display-only value calculated in completed whole years from Date of Birth for an Individual or Date of Incorporation for a Non-Individual. Age MUST NOT be persisted in a new field, and the Individual 18–80 age rule MUST NOT be applied to a Non-Individual entity.
- **FR-022**: Contact Info MUST remain unavailable until the applicable document verification path is complete.
- **FR-023**: Mobile Number MUST contain exactly 10 digits and begin with 6, 7, 8, or 9.
- **FR-024**: Email Address MUST satisfy the approved email format and be limited to 80 characters.
- **FR-025**: Changing a verified Mobile Number or Email Address MUST invalidate its prior verification.
- **FR-026**: Next MUST remain unavailable until required contact verification and customer consent are complete. Exact consent verbiage, version, validity period, resend limits, expiry behavior, and evidence requirements MUST remain a separately customer-approved dependency and MUST NOT be invented in this specification.
- **FR-027**: Save MUST retain valid Basic Details without advancing the QDE sub-stage.
- **FR-028**: Next MUST save Basic Details and run only the applicable mandatory forward checks.
- **FR-029**: The PAN path MUST run CIF-on-PAN, ETB/CASA, Customer Dedupe, and Recent Lead validation in the configured sequence.
- **FR-030**: The Form 60 path MUST skip PAN-dependent forward checks.
- **FR-031**: A failed save or mandatory forward check MUST leave Basic Details incomplete, prevent navigation, display a safe error, and permit an applicable retry.
- **FR-032**: Duplicate Save or Next submissions MUST be prevented while processing is already underway.
- **FR-033**: Successful completion MUST navigate to the configured QDE KYC Details sub-stage.
- **FR-034**: Completed Basic Details MUST be displayed read-only when revisited.
- **FR-035**: Purpose of Purchase MUST be displayed as Commercial for a CV Application, as required by US-QDE-BASIC-CV-003; it is treated as fixed screen content because it is not included in the Final Fields inventory.

### Key Entities

- **Application (`Application__c`)**: The lending Application containing Branch, Required Loan Amount, and QDE stage state.
- **Applicant (`Applicant__c`)**: The Borrower whose Customer Type, identity, professional, and contact details are captured.
- **Document Checklist (`Document_CheckList__c`)**: The PAN or Form 60 document record and extracted identity details associated with the correct Applicant and Application.
- **Industry master (`Industry_Code_and_Type__c`)**: Active controlled values used to select Industry Name and derive Industry Code.

### Panel / Screen Content — fields & data visible

#### Basic Details: Application Details

| Field | Salesforce mapping | Business purpose | Trace |
|-------|--------------------|------------------|-------|
| Customer Type | `Applicant__c.Type__c` | Selects the Individual or Non-Individual Basic Details path. | US-QDE-BASIC-CV-002 |
| Applicant Type (Entity Type) | `Applicant__c.Entity_Type__c` | Captures the approved Non-Individual constitution; Proprietorship is excluded. | US-QDE-BASIC-CV-002, CL-002 |
| Entity Name | `Applicant__c.Company_Name__c` | Identifies the Non-Individual Borrower and supports PAN identity review. | US-QDE-BASIC-CV-002, US-QDE-BASIC-CV-006 |
| Industry Name | `Applicant__c.Industry_Name__c` | Selects active industry master data and derives Industry Code. | US-QDE-BASIC-CV-002 |
| Evaluation Type | `Applicant__c.Evaluation_Type__c` | Captures the applicable Non-Individual evaluation category. | US-QDE-BASIC-CV-002 |

#### Basic Details: Loan Basic Info and Loan Detail

| Field | Salesforce mapping | Business purpose | Trace |
|-------|--------------------|------------------|-------|
| Branch | `Application__c.Branch__c` | Associates the Application with an available Branch. | US-QDE-BASIC-CV-003 |
| Required Loan Amount | `Application__c.Total_Loan_Amount__c` | Captures the commercial loan request and participates in mandatory-PAN rules. | US-QDE-BASIC-CV-003, US-QDE-BASIC-CV-005 |

#### Basic Details: Professional Detail

| Field | Salesforce mapping | Business purpose | Trace |
|-------|--------------------|------------------|-------|
| Profile Type | `Applicant__c.Profile__c` | Captures the Individual professional profile. | US-QDE-BASIC-CV-004 |
| Income Available | `Applicant__c.Is_Income_Available__c` | Selects earning or Non-Earning behavior. | US-QDE-BASIC-CV-004 |
| Annual Income | `Applicant__c.Declared_income__c` | Captures declared income and participates in mandatory-PAN rules. | US-QDE-BASIC-CV-004, US-QDE-BASIC-CV-005 |
| Occupation Category | `Applicant__c.Income_Category__c` | Determines the applicable Occupation Details journey. | US-QDE-BASIC-CV-004 |

#### Basic Details: Document Verification

| Field | Salesforce mapping | Business purpose | Trace |
|-------|--------------------|------------------|-------|
| Is PAN Available | `Applicant__c.Is_PAN_Available__c` | Selects the permitted PAN or Form 60 path. | US-QDE-BASIC-CV-005 |
| PAN Card File | `Document_CheckList__c.ContentVersionId__c` where document type is PAN | Stores the PAN document association. | US-QDE-BASIC-CV-006 |
| Form 60 File | `Document_CheckList__c.ContentVersionId__c` where document type is Form 60 | Stores the permitted Form 60 document association. | US-QDE-BASIC-CV-007 |
| First Name | `Applicant__c.Customer_First_Name__c`; `Document_CheckList__c.First_Name__c` | Captures or reviews Individual identity. | US-QDE-BASIC-CV-006, US-QDE-BASIC-CV-007 |
| Last Name | `Applicant__c.Customer_Last_Name__c`; `Document_CheckList__c.Last_Name__c` | Captures or reviews Individual identity. | US-QDE-BASIC-CV-006, US-QDE-BASIC-CV-007 |
| Date of Birth | `Applicant__c.Date_of_Birth__c`; `Document_CheckList__c.KYC_Date_of_Birth__c` | Captures Individual birth date and supports age validation. | US-QDE-BASIC-CV-006, US-QDE-BASIC-CV-007, US-QDE-BASIC-CV-010 |
| Date of Incorporation | Current workbook mapping: `Applicant__c.Date_of_Birth__c` | Captures Non-Individual incorporation date for PAN identity and Age. | US-QDE-BASIC-CV-006, US-QDE-BASIC-CV-010, CL-001 |
| Age | No approved field API name; derived from the applicable source date | Displays non-mandatory calculated applicant or entity age. | US-QDE-BASIC-CV-010, CL-001 |
| PAN Card Number | `Applicant__c.PAN_Number__c`; `Document_CheckList__c.PAN_No__c` | Captures and verifies PAN identity. | US-QDE-BASIC-CV-006 |
| PAN Acknowledgement Number | `Document_CheckList__c.PAN_ACK_No__c` | Captures Form 60 acknowledgement evidence. | US-QDE-BASIC-CV-007 |

#### Basic Details: Contact Info

| Field | Salesforce mapping | Business purpose | Trace |
|-------|--------------------|------------------|-------|
| Marital Status | `Applicant__c.Marital_status__c` | Captures optional Individual marital status. | US-QDE-BASIC-CV-008 |
| Residence Country | `Applicant__c.Residence_Country__c` | Captures optional residence classification. | US-QDE-BASIC-CV-008 |
| Contact Person Name | `Applicant__c.Contact_Person_Name__c` | Identifies the required Non-Individual contact person. | US-QDE-BASIC-CV-008 |
| Landline Number | `Applicant__c.Landline_Number__c` | Captures optional Non-Individual landline contact. | US-QDE-BASIC-CV-008 |
| Mobile Number | `Applicant__c.Phone__c` | Captures and verifies the required mobile contact channel. | US-QDE-BASIC-CV-008 |
| Email Address | `Applicant__c.Email__c` | Captures and verifies the required email contact channel. | US-QDE-BASIC-CV-008 |

## Navigation & Interactions

- **Entry point**: The Sales Officer opens the active Borrower’s QDE Basic Details sub-stage.
- **Progressive sections**: Application Details unlocks Loan Basic Info; Branch unlocks Loan Detail; applicable professional details lead to Document Verification; completed document verification unlocks Contact Info.
- **Customer Type**: Selecting Individual or Non-Individual changes visible and required fields and clears values that no longer apply.
- **Document path**: Is PAN Available selects PAN or Form 60 where permitted; mandatory-PAN rules override the Form 60 choice.
- **Document actions**: PAN and Form 60 support approved upload, preview, delete, replace, and re-upload behavior.
- **Verification actions**: PAN, Mobile Number, and Email Address expose Verify only when their prerequisite format and data conditions are met.
- **Consent**: Consent becomes available after required contact verification; accepted consent is reflected on the Sales Officer screen.
- **Save**: Retains valid Basic Details without navigation.
- **Next**: Becomes available only after all required fields, documents, verification, and consent are complete; it performs applicable forward checks and opens KYC Details only on success.

## Persona Capabilities

| Capability | Sales Officer |
|------------|:-------------:|
| View Basic Details | V |
| Create and edit incomplete Basic Details | C/E |
| Upload, view, delete, and replace applicable documents | C/E/V |
| Request PAN/contact verification and consent | E |
| Save without progression | E |
| Continue to KYC after all gates complete | E |
| View completed Basic Details | V |

All capabilities remain bounded by Salesforce sharing, object access, field access, and the assigned permission-set model.

## Discrepancies and Clarifications

| ID | Sources | Discrepancy | Current specification treatment | Resolution |
|----|---------|-------------|---------------------------------|------------|
| CL-001 | Final Fields, US-QDE-BASIC-CV-010, metadata | Age has no approved API field or calculation/persistence definition. Date of Incorporation currently maps to `Applicant__c.Date_of_Birth__c` and carries person-age errors. | Age is display-only, calculated in completed whole years, and is not persisted. Entity Age does not use the Individual 18–80 rule. | Resolved 2026-08-06 — FR-021 |
| CL-002 | Final Fields and `Applicant__c.Entity_Type__c` metadata | The approved workbook list differs from active metadata and removes Proprietorship while metadata retains it. | The exact Final Fields list governs the requirement; Proprietorship is excluded. | Resolved 2026-08-06 — FR-003 |
| CL-003 | US-QDE-BASIC-CV-008 and regulatory memory | Consent is mandatory, but approved verbiage, version, validity, expiry, resend limits, and evidence requirements are absent. | Consent remains mandatory; exact wording and policy are a separate customer-approved dependency and are not invented here. | Resolved as external dependency 2026-08-06 — FR-026 |
| DISC-004 | Delta and current repository behavior | Gender is removed from the Basic Details field inventory and Form 60 story, while shared metadata and current screen behavior still reference it. | This specification removes Gender only from Basic Details; it does not authorize deletion of shared Gender fields elsewhere. | Implementation must reconcile Basic Details display and completion logic. |
| DISC-005 | US-QDE-BASIC-CV-003 and Final Fields | Purpose of Purchase is required as fixed Commercial display content but is absent from the Final Fields sheet. | Retained as fixed screen behavior under FR-035, not added to the final field inventory. | Confirm during clarification if it should become an inventoried field. |

## Success Criteria

### Measurable Outcomes

- **SC-001**: A Sales Officer can complete both the Individual PAN path and the eligible Individual Form 60 path using only the applicable fields and gates.
- **SC-002**: A Sales Officer can complete the Non-Individual PAN path without seeing Individual professional fields.
- **SC-003**: All 27 fields in the reconciled Final Fields sheet are represented once in the screen inventory and traced to at least one approved user story.
- **SC-004**: In 100% of acceptance tests, Next remains unavailable while any required field, document, verification, consent, or mandatory forward check is incomplete or failed.
- **SC-005**: In 100% of Customer Type and PAN/Form 60 path-switch tests, inapplicable data is cleared or deactivated and applicable retained values remain available.
- **SC-006**: In 100% of duplicate-submission tests, only one Save or Next operation is accepted while processing is active.
- **SC-007**: No failed save, verification, consent, or mandatory forward check marks Basic Details complete or advances to KYC.

## Wireframes

| Screen | Figma Link | User Story | Status | Approved By |
|--------|------------|------------|--------|-------------|
| Basic Details | — | US-QDE-BASIC-CV-002 through US-QDE-BASIC-CV-010 | ⏳ Pending | — |

**Sign-off Status**: ⏳ Pending wireframe generation

➡️ **Next Step**: Run `/speckit-wireframe`. The separate customer-approved consent artifact remains required before implementation sign-off.

## Assumptions

- The reconciled workbook is the approved business-requirement source for Basic Details.
- Clarifications resolved on 2026-08-06: Age is display-only in completed whole years; the exact Final Fields Entity Type list governs; consent wording and policy remain a separate customer-approved dependency.
- Scope is the Commercial Vehicle Basic Details sub-stage for Borrowers; applicability columns in the workbook remain unchanged.
- Gender removal applies to the Basic Details screen and its completion criteria, not to unrelated KYC or shared data without separate approval.
- Industry and Branch master data are maintained by authorized administrators.
- Document file types and maximum counts come from approved Document Checklist configuration.
- PAN extraction, PAN verification, phone verification, email verification, consent, CIF-on-PAN, ETB/CASA, Customer Dedupe, and Recent Lead validation are dependencies; their presence does not by itself prove production readiness.
- KYC Details is the next configured QDE sub-stage after successful Basic Details completion.
- Exact business SLAs and customer-facing consent text are not assumed.
