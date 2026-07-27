# Commercial Vehicle QDE Basic Details Requirements

## Source Basis

- Live Salesforce inspection on a newly created Commercial Vehicle application.
- Creation route: Applications > New > Commercial Vehicles (CV) > New > Light Commercial Vehicles (LCV) > Create.
- Live QDE route: Application Overview > QDE > Basic Details > Borrower.
- Salesforce implementation under `force-app/main/default`, primarily:
  - `lwc/applicantBasicDetailsCapture`
  - `classes/ApplicantBasicDetailsCaptureController.cls`
  - `customMetadata/Dynamic_Stage_Gate.Wheels_Basic_Details.md-meta.xml`
  - Applicant, Application, Asset, Application Line Item, and Document Checklist field metadata.
- Structure and terminology reference: `Commercial_Vehicle_QDE_Requirements_V2.md`.
- Excel targets: `User Stories_CE.xlsx`, sheets `QDE_BD_Fields` and `QDE_BD_US`.

### Source Interpretation

- The live screen is authoritative for observed labels, defaults, field placement, visibility, and interaction behavior.
- Repository code and metadata are authoritative for persistence mappings, validations, integration calls, and branches that could not be reached without uploading documents or saving QDE data.
- Only user-entered or user-selectable fields are included in the field table. Read-only Purpose of Purchase, Industry Code, verification statuses, consent status, progress, actions, and generated records are covered in user stories.
- A new Commercial Vehicle application was created with user authorization. No Basic Details data was saved, no PAN/Form 60 file was uploaded, no OTP was sent, and no consent or Next action was submitted.

## Live Interaction Coverage

### Exercised on the Newly Created CV Application

- Confirmed the initial Basic Details screen defaults Customer Type to Individual.
- Opened and captured both Customer Type options: Individual and Non-Individual.
- Confirmed progressive section unlocking in this order:
  1. Application Details
  2. Loan Basic Info
  3. Loan Detail
  4. Professional Detail for Individual
  5. Document Verification
  6. Contact Info after document completion
- Selected Branch One from the Branch lookup and confirmed Purpose of Purchase displays as read-only Commercial.
- Entered Required Loan Amount values below and above the ₹10 lakh PAN threshold and confirmed Indian digit grouping.
- Opened and captured all Profile Type and Occupation Category options.
- Exercised Income Available = Yes and No. No clears Annual Income and locks Occupation Category to Non-Earning.
- Exercised Is PAN Available = Yes and No below the mandatory threshold.
- Confirmed the Individual Form 60 branch immediately shows Gender, First Name, Last Name, and Form 60 upload.
- Confirmed a loan amount above ₹10 lakh forces read-only Is PAN Available = Yes, hides the Yes/No selector, shows the PAN upload, and displays the mandatory-PAN warning.
- Exercised the Non-Individual branch and captured Entity Type, Entity Name, Industry Name, Evaluation Type, Date of Incorporation, PAN Number, and PAN upload behavior.
- Confirmed Branch and Required Loan Amount retain their unsaved values when Customer Type changes, while customer-type-specific entity, industry, identity, professional, and contact values are cleared or hidden.

### Enumerated Without Selecting Every Value

- Entity Type, Profile Type, Evaluation Type, Occupation Category, and Gender lists were fully opened and enumerated. Representative values were selected where the selected value has no Basic Details-specific dependency.
- Industry Name is a searchable, dynamic master-data list sourced from `Industry_Code_and_Type__c`; the UI displayed the alphabetically ordered matching values rather than a finite metadata picklist.
- Branch is a dynamic Account lookup. Branch One was selected for the test path.

### Not Exercised

- PAN/Form 60 file upload, OCR, PAN verification, OTP generation/verification, customer consent, save, Next, rollback, and post-save navigation were not exercised because they create or modify QDE records or invoke integrations.
- Contact Info and identity fields that appear only after successful upload were confirmed from the current component and Apex implementation.

## Excel Field Details Table

| Field Name | Object | Field Type | Drop down values | Display Stage | Display Sub Stage | Display Section | Validation | Error Message | Controlling field | Controlling Expression |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Customer Type | `Applicant__c.Type__c` | Picklist | Individual; Non-Individual | QDE | Basic Details | Application Details | Required. Defaults to Individual on a new borrower. Changing the value clears customer-type-specific entity, industry, identity, professional, and contact values. | Select Customer Type. |  | Individual and Non-Individual branches are available for a CV Borrower. |
| Applicant Type (Entity Type) | `Applicant__c.Entity_Type__c` | Picklist | Pvt Ltd; Public Ltd; Proprietorship; Partnership; Trust; HUF; Co-Operative Society; Association of Persons | QDE | Basic Details | Application Details | Required for Non-Individual. Options are active Salesforce picklist values. | Select Entity Type. | Customer Type | Visible and required when Customer Type = Non-Individual. |
| Entity Name | `Applicant__c.Company_Name__c` | Text |  | QDE | Basic Details | Application Details / Document Verification | Required for Non-Individual; maximum 255 characters in the document rendering. The same value is shown as Entity / Company Name in Document Verification and is cleared when Customer Type changes to Individual. | Enter Entity Name. | Customer Type | Visible when Customer Type = Non-Individual; reused on the mandatory PAN path. |
| Industry Name | `Applicant__c.Industry_Name__c` | Searchable master-data picklist | Active `Industry_Code_and_Type__c` records, ordered by Name; up to 5,000 records loaded | QDE | Basic Details | Application Details | Required for a CV Non-Individual applicant. Selecting a value derives Industry Code. | Select Industry Name. | Product + Customer Type | Visible when product is CV/SCV/LCV/MHCE/CE and Customer Type = Non-Individual. |
| Evaluation Type | `Applicant__c.Evaluation_Type__c` | Picklist | Captive Retail; Captive strategic; Hiring FTU; Hiring Retail; Hiring Strategic; Not Applicable | QDE | Basic Details | Application Details | Required by progressive section completion for Non-Individual, although the live control has no required asterisk. Cleared for Individual. | Select Evaluation Type. | Customer Type | Visible when Customer Type = Non-Individual. |
| Branch | `Application__c.Branch__c` | Lookup (Account) | Dynamic matching Account records; Branch One observed | QDE | Basic Details | Loan Basic Info | Required. A selected Branch is retained when Customer Type changes. | Select Branch. | Application Details completion | Section appears only after required Application Details are complete. |
| Required Loan Amount | `Application__c.Total_Loan_Amount__c` | Currency |  | QDE | Basic Details | Loan Detail | Required; digits with optional decimal up to two places. Non-numeric characters are removed and the display uses Indian grouping. A value above ₹10,00,000 forces PAN availability to Yes. | Invalid Required Loan Amount — Enter a valid amount with up to two decimal places. | Branch + PAN rule | Section appears after Loan Basic Info is complete; amount > 1000000 forces PAN. |
| Profile Type | `Applicant__c.Profile__c` | Picklist | BANK EMPLOYEE; CONTRACT WORKER; DAILY WAGES; DOCK AND MINE WORKER; EDITOR; GARAGE MECHANIC; GARDENER; GOVERNMENT SERVANT; INTELLIGENCE PERSONNEL; JOB WORKER; LAB TECHNICIAN; MEDICAL - REP; POLICE; SOFTWARE ENGINEER | QDE | Basic Details | Professional Detail | Required by progressive section completion for Individual, although the live label has no required asterisk. | Select Profile Type. | Customer Type | Visible when Customer Type = Individual. |
| Income Available | `Applicant__c.Is_Income_Available__c` | Radio / Picklist | Yes; No | QDE | Basic Details | Professional Detail | Required for Individual. Defaults to Yes on the live new-borrower path. Selecting No clears Annual Income and sets Occupation Category to Non-Earning. | Select Income Available. | Customer Type | Editable for Individual; hidden and forced to Yes for Non-Individual. |
| Annual Income | `Applicant__c.Declared_income__c` | Currency |  | QDE | Basic Details | Professional Detail | Required when Individual and Income Available = Yes. Non-numeric characters are removed and the display uses Indian grouping. A value above ₹4,00,000 forces PAN availability to Yes. | Enter Annual Income. | Customer Type + Income Available | Visible when Customer Type = Individual and Income Available = Yes; income > 400000 forces PAN. |
| Occupation Category | `Applicant__c.Income_Category__c` | Picklist | Income Available = Yes: Salaried; Self Employed Professional; Self Employed Non Professional. Income Available = No: Non-Earning | QDE | Basic Details | Professional Detail | Required for Individual. When Income Available = No, the value is auto-set to Non-Earning and the control is disabled. | Select Occupation Category. | Income Available | Yes enables the three earning categories; No clears prior category and locks Non-Earning. |
| Is PAN Available | `Applicant__c.Is_PAN_Available__c` | Radio / Picklist | Yes; No | QDE | Basic Details | Document Verification | Required. Defaults to Yes. Read-only and forced to Yes when Annual Income > ₹4 lakh, Required Loan Amount > ₹10 lakh, Customer Type = Non-Individual, PAN is already verified, or the screen is read-only. Switching paths clears the opposite upload state. | PAN is mandatory when Annual Income exceeds ₹4 Lakhs or Required Loan Amount exceeds ₹10 Lakhs or Non-individual applicant | Annual Income + Required Loan Amount + Customer Type + PAN verification | Editable only for an unverified Individual at or below both thresholds. |
| PAN Card File | `Document_CheckList__c.ContentVersionId__c` (`Document_Type__c = PAN`) | File Upload | File types and maximum count from Document Checklist configuration | QDE | Basic Details | Document Verification | Required when Is PAN Available = Yes. A real linked ContentDocument/ContentVersion is required; placeholder checklist data does not complete the section. | Upload PAN Card File. | Is PAN Available | Visible and required when Is PAN Available = Yes. |
| Form 60 File | `Document_CheckList__c.ContentVersionId__c` (`Document_Type__c = Form 60`) | File Upload | File types and maximum count from Document Checklist configuration | QDE | Basic Details | Document Verification | Required when an Individual selects Is PAN Available = No. A real linked ContentDocument/ContentVersion is required. | Upload Form 60 File. | Customer Type + Is PAN Available | Visible when Customer Type = Individual and Is PAN Available = No. |
| First Name | `Applicant__c.Customer_First_Name__c`; `Document_CheckList__c.First_Name__c` | Text |  | QDE | Basic Details | Document Verification | Required for an Individual. On the Form 60 path it is entered directly; on the PAN path it appears after upload/OCR and remains editable until PAN verification. | Enter First Name. | Customer Type + PAN/Form 60 path | Visible for Individual identity capture. |
| Last Name | `Applicant__c.Customer_Last_Name__c`; `Document_CheckList__c.Last_Name__c` | Text |  | QDE | Basic Details | Document Verification | Required for an Individual. On the Form 60 path it is entered directly; on the PAN path it appears after upload/OCR and remains editable until PAN verification. | Enter Last Name. | Customer Type + PAN/Form 60 path | Visible for Individual identity capture. |
| Date of Birth | `Applicant__c.Date_of_Birth__c`; `Document_CheckList__c.KYC_Date_of_Birth__c` | Date |  | QDE | Basic Details | Document Verification | Required for an Individual after PAN upload and after Form 60 upload. Applicant age must be 18 through 80 years. The picker prevents dates younger than 18. | Invalid date format; Applicant must be at least 18 years old; Applicant cannot be older than 80 years | Customer Type + document upload | Visible for Individual identity capture after the applicable document state is available. |
| Date of Incorporation | `Applicant__c.Date_of_Birth__c` | Date |  | QDE | Basic Details | Document Verification | Optional editable incorporation date for Non-Individual; becomes read-only after PAN verification. |  | Customer Type | Visible when Customer Type = Non-Individual and PAN identity fields are shown. |
| PAN Card Number | `Applicant__c.PAN_Number__c`; `Document_CheckList__c.PAN_No__c` | Text with Verify action |  | QDE | Basic Details | Document Verification | Required on the PAN path; exactly 10 characters matching five letters, four digits, and one letter. Converted to uppercase. Verification also checks the configured fourth-character/entity rule. Locked after successful verification. | PAN Card Number is not valid. | Is PAN Available + PAN upload / Non-Individual identity | Visible when Is PAN Available = Yes and PAN identity fields are shown. |
| PAN Acknowledgement Number | `Document_CheckList__c.PAN_ACK_No__c` | Text / Numeric |  | QDE | Basic Details | Document Verification | Required for an Individual only after a Form 60 file is uploaded. Digits only; maximum 18 digits. | Enter PAN Acknowledgement Number. | Customer Type + Is PAN Available + Form 60 File | Visible when Individual, Is PAN Available = No, and Form 60 has been uploaded. |
| Gender | `Applicant__c.Gender__c`; `Document_CheckList__c.Gender__c` | Picklist | MALE; FEMALE; OTHERS MALE; OTHERS FEMALE; OTHERS PREFER NOT TO DISCLOSE | QDE | Basic Details | Document Verification | Required for an Individual on the Form 60 path. | Select Gender. | Customer Type + Is PAN Available | Visible when Customer Type = Individual and Is PAN Available = No. |
| Marital Status | `Applicant__c.Marital_status__c` | Picklist | Married; Unmarried; Divorced; Widowed | QDE | Basic Details | Contact Info | Optional in the current UI. |  | Customer Type | Visible for Individual only. |
| Residence Country | `Applicant__c.Residence_Country__c` | Picklist | India; Non-India Resident | QDE | Basic Details | Contact Info | Optional in the current UI. |  | Document Verification completion | Visible for both Individual and Non-Individual when Contact Info is unlocked. |
| Contact Person Name | `Applicant__c.Contact_Person_Name__c` | Text |  | QDE | Basic Details | Contact Info | Required for Non-Individual; maximum 100 characters. Cleared when Customer Type changes to Individual. | Enter Contact Person Name. | Customer Type | Visible and required when Customer Type = Non-Individual. |
| Landline Number | `Applicant__c.Landline_Number__c` | Phone |  | QDE | Basic Details | Contact Info | Optional; non-digits are removed, maximum 11 digits, displayed in `(STD) - subscriber` format. Cleared when Customer Type changes to Individual. |  | Customer Type | Visible when Customer Type = Non-Individual. |
| Mobile Number | `Applicant__c.Phone__c` | Phone with Verify action |  | QDE | Basic Details | Contact Info | Required; exactly 10 digits starting with 6, 7, 8, or 9. Non-digits are removed and input is limited to 10 digits. Changing the number invalidates prior verification. | Enter a valid 10-digit Indian mobile number starting with 6-9 | Document Verification completion | Verify is enabled only for a valid number; successful phone OTP verification is required before Consent and Next. |
| Email Address | `Applicant__c.Email__c` | Email with Verify action |  | QDE | Basic Details | Contact Info | Required; must match the implemented email pattern and is limited to 80 characters. Changing the address invalidates prior verification. | Enter a valid email address | Document Verification completion | Verify is enabled only for a valid email; successful email OTP verification is required before Consent and Next. |

## Validation and Dependency Matrix

| Controlling Condition | Result |
| --- | --- |
| Application Details incomplete | Loan Basic Info and every later section remain hidden. |
| Branch missing | Loan Detail and later sections remain hidden. |
| Required Loan Amount missing/invalid | Professional/Document section progression and Next remain blocked. |
| Individual + Income Available = Yes | Annual Income is required; Occupation Category permits the three earning categories. |
| Individual + Income Available = No | Annual Income is cleared/hidden; Occupation Category becomes locked Non-Earning. |
| Annual Income > 400000 OR Required Loan Amount > 1000000 OR Non-Individual | Is PAN Available is forced to read-only Yes and the mandatory-PAN message appears. |
| Individual + PAN available | PAN upload is required; extracted identity fields and PAN Verify appear after upload/OCR. |
| Individual + PAN unavailable | Gender, First Name, Last Name, and Form 60 upload appear; DOB and PAN Acknowledgement Number appear after upload. |
| Non-Individual | Entity Type, Entity Name, Industry Name, and Evaluation Type are required; PAN is mandatory; Profile/Income/Occupation fields are hidden. |
| PAN/Form 60 document incomplete | Contact Info remains hidden. |
| Mobile or email format invalid | Corresponding Verify action and Next remain disabled. |
| Mobile or email not verified | Consent and Next remain disabled. |
| Customer consent not accepted | Next remains disabled. |
| Basic Details already complete or stage is past | All sections render in read-only mode; editable Next is hidden. |

## Agile Requirements Hierarchy

### Epic: Commercial Vehicle Loan Origination

Enable Sales Officers to originate Commercial Vehicle loans through a controlled Salesforce LOS journey.

### Feature: CV QDE Basic Details

Capture and verify borrower, loan, professional, identity, and contact information through progressive sections before moving the applicant to QDE KYC Details.

## User Stories

### US-QDE-BASIC-CV-002: Capture Individual or Non-Individual Application Details

**User Story Description:** As a Sales Officer, I want to select the borrower customer type and complete its applicable details so that the correct CV borrower branch is used.

**Acceptance Criteria:**

- **Positive Scenario — Individual borrower**
  - Given Customer Type is Individual
  - When Application Details is displayed
  - Then Non-Individual entity, industry, and evaluation fields are not displayed
- **Positive Scenario — Non-Individual borrower**
  - Given Customer Type is Non-Individual
  - When Application Details is displayed
  - Then Entity Type, Entity Name, Industry Name, and Evaluation Type are required
  - And selecting an Industry Name displays its corresponding Industry Code
- **Negative Scenario**
  - Given a required Non-Individual field is missing
  - When the system evaluates section completion
  - Then the next section remains unavailable and the missing information is identified
- **Edge Case Scenario**
  - Given the Sales Officer changes Customer Type
  - When the applicable branch is refreshed
  - Then values that no longer apply are cleared or hidden
  - And previously entered Branch and Required Loan Amount values are retained
- **Persistence Scenario**
  - Given valid Application Details are saved
  - When the Sales Officer revisits Basic Details
  - Then the saved customer and entity details are displayed

**Assumptions:**

- Industry master data and active picklist metadata are maintained by authorized administrators.

**Integrations:**

- Industry master data is required to provide Industry Name and Industry Code values.
- No external API is invoked by this story.

**In Scope:**

- Individual and Non-Individual borrower selection.
- Conditional fields, requiredness, dependent value clearing, and saved-value retrieval.

### US-QDE-BASIC-CV-003: Capture CV Loan Basic Information

**User Story Description:** As a Sales Officer, I want to select the Branch and enter the required loan amount so that the application contains its basic commercial loan request.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given Application Details is complete
  - When Loan Basic Info is displayed
  - Then the Sales Officer can select a Branch
  - And Purpose of Purchase is displayed as Commercial for a CV application
  - And completing Branch makes Loan Detail available
- **Positive Scenario — Required loan amount**
  - Given Loan Detail is available
  - When the Sales Officer enters Required Loan Amount
  - Then the value accepts numbers with up to two decimal places and displays Indian digit grouping
- **Negative Scenario**
  - Given Required Loan Amount is blank or invalid
  - When the Sales Officer leaves the field
  - Then the system displays `Invalid Required Loan Amount` and `Enter a valid amount with up to two decimal places.`
  - And progression remains blocked
- **Edge Case Scenario**
  - Given Required Loan Amount exceeds ₹10,00,000
  - When document rules are evaluated
  - Then PAN becomes mandatory
- **Persistence Scenario**
  - Given Branch and Required Loan Amount are saved
  - When the Sales Officer revisits Basic Details
  - Then the saved values are displayed

**Assumptions:**

- The Branch list contains only branches available to the Sales Officer.

**Integrations:**

- Branch master data is required for Branch selection.
- No external API is invoked by this story.

**In Scope:**

- Branch selection, Commercial purpose display, amount validation and formatting, and saved-value retrieval.

### US-QDE-BASIC-CV-004: Capture Individual Professional Details

**User Story Description:** As a Sales Officer, I want to capture the Individual borrower’s profile and income category so that the applicable occupation journey can be determined.

**Acceptance Criteria:**

- **Positive Scenario — Income available**
  - Given the borrower is Individual and Loan Detail is complete
  - When Professional Detail is displayed and Income Available is Yes
  - Then Profile Type, Annual Income, and Occupation Category are required
  - And Occupation Category allows the applicable earning categories
- **Positive Scenario — Income unavailable**
  - Given the borrower is Individual
  - When Income Available is changed to No
  - Then Annual Income is cleared and hidden
  - And Occupation Category is set to Non-Earning and cannot be changed
- **Negative Scenario**
  - Given a required professional or income value is missing
  - When the system evaluates section completion
  - Then Document Verification remains unavailable and the missing information is identified
- **Edge Case Scenario**
  - Given Income Available changes from No to Yes
  - When the section refreshes
  - Then Non-Earning is cleared before an earning category is selected
  - And Annual Income becomes required
- **Edge Case Scenario — PAN threshold**
  - Given Annual Income exceeds ₹4,00,000
  - When document rules are evaluated
  - Then PAN becomes mandatory
- **Persistence Scenario**
  - Given Professional Detail is saved
  - When the Sales Officer revisits Basic Details
  - Then the saved applicable values are displayed and hidden inapplicable values are not restored

**Assumptions:**

- The selected Income Category controls the separate Occupation Details sub-stage.

**Integrations:**

- Configured profile and occupation-category values are available.
- No external API is invoked by this story.

**In Scope:**

- Basic Details profile, income, and occupation-category selection.

### US-QDE-BASIC-CV-005: Apply PAN Availability and Mandatory-PAN Rules

**User Story Description:** As a Sales Officer, I want the screen to select the permitted PAN/Form 60 path automatically so that regulatory document requirements cannot be bypassed.

**Acceptance Criteria:**

- **Positive Scenario — PAN or Form 60 choice**
  - Given an Individual borrower has Annual Income at or below ₹4,00,000 and Required Loan Amount at or below ₹10,00,000
  - When Document Verification is displayed
  - Then Is PAN Available defaults to Yes and can be changed between Yes and No
- **Positive Scenario — Mandatory PAN**
  - Given Annual Income exceeds ₹4,00,000, Required Loan Amount exceeds ₹10,00,000, or the borrower is Non-Individual
  - When document rules are evaluated
  - Then PAN is mandatory and Is PAN Available cannot be changed to No
  - And the system displays `PAN is mandatory when Annual Income exceeds ₹4 Lakhs or Required Loan Amount exceeds ₹10 Lakhs or Non-individual applicant`
- **Negative Scenario**
  - Given PAN is mandatory
  - When the Sales Officer attempts to use the Form 60 path
  - Then the system prevents the selection and requires PAN
- **Edge Case Scenario — Path change**
  - Given the Sales Officer changes between PAN and Form 60
  - When the document path refreshes
  - Then document data from the previous path is cleared or deactivated so that only one path remains active
- **Edge Case Scenario — Previously verified PAN**
  - Given PAN was previously verified
  - When Basic Details is revisited
  - Then PAN availability and verified identity information remain read-only

**Assumptions:**

- The threshold comparison is strictly greater than, not greater than or equal to.

**Integrations:**

- Document configuration is required to activate the applicable PAN or Form 60 requirement.
- No external verification API is invoked until a PAN document is uploaded and PAN verification is requested.

**In Scope:**

- PAN threshold logic and path switching.

### US-QDE-BASIC-CV-006: Upload and Verify PAN Identity

**User Story Description:** As a Sales Officer, I want to upload and verify PAN identity details so that the borrower’s identity is validated before contact capture.

**Acceptance Criteria:**

- **Positive Scenario — PAN upload and extraction**
  - Given Is PAN Available is Yes
  - When the Sales Officer uploads an allowed PAN document
  - Then the PAN OCR service extracts the PAN number and applicable name and date information
  - And the extracted values are displayed for review
- **Positive Scenario — PAN verification**
  - Given the extracted PAN information is complete and valid
  - When the Sales Officer selects Verify
  - Then the PAN validation service verifies the PAN against the applicable Individual or Non-Individual details
  - And successful verification locks the verified PAN information against further editing
- **Negative Scenario — Invalid PAN format**
  - Given the PAN number does not follow the required five-letter, four-digit, one-letter format or has an invalid constitution character
  - When validation runs
  - Then the system displays the applicable error and does not call PAN verification
- **Negative Scenario — OCR or PAN service failure**
  - Given PAN OCR or PAN verification fails or is unavailable
  - When the integration response is received
  - Then the system displays the failure, permits an applicable retry or correction, and prevents progression
- **Edge Case Scenario — Non-Individual borrower**
  - Given the borrower is Non-Individual
  - When PAN information is reviewed or re-verified
  - Then Entity Name and Date of Incorporation are used instead of Individual name and Date of Birth
- **Edge Case Scenario — File management**
  - Given a PAN document has been uploaded
  - When the Sales Officer previews, deletes, or replaces it
  - Then the action applies to the correct document and section completion is recalculated
- **Integration Scenario**
  - Given PAN OCR succeeds
  - When extracted information is submitted for PAN verification
  - Then the validation request uses the reviewed PAN and identity values
  - And only a successful validation result marks PAN as verified
- **Progression Scenario**
  - Given PAN verification has not succeeded
  - When progression is evaluated
  - Then Contact Info and Next remain unavailable

**Assumptions:**

- Allowed file types and maximum file count are supplied by Document Checklist configuration.
- The PAN OCR and PAN validation services are available through approved integration endpoints.
- The business-approved matching rules differ appropriately for Individual and Non-Individual borrowers.

**Integrations:**

- Document Upload service for upload, preview, delete, and replacement.
- PAN OCR service for extracting PAN and identity information.
- PAN Validation service for PAN and identity verification.
- Integration failures must be returned to the screen with a user-readable message and must not mark PAN as verified.

**In Scope:**

- PAN upload, extracted identity, format validation, verification, preview, and delete/replace behavior.

### US-QDE-BASIC-CV-007: Capture the Individual Form 60 Identity Path

**User Story Description:** As a Sales Officer, I want to capture Form 60 details when PAN is not available so that an eligible Individual can continue through the permitted non-PAN route.

**Acceptance Criteria:**

- **Positive Scenario**
  - Given an eligible Individual borrower selects Is PAN Available as No
  - When Document Verification refreshes
  - Then Gender, First Name, Last Name, and Form 60 upload are displayed
  - And Date of Birth and PAN Acknowledgement Number become required after Form 60 is uploaded
- **Validation Scenario**
  - Given the Sales Officer enters PAN Acknowledgement Number
  - When the value is processed
  - Then only digits are accepted and the value is limited to 18 digits
- **Validation Scenario — Date of Birth**
  - Given Date of Birth is entered
  - When age is calculated
  - Then the applicant must be between 18 and 80 years old
  - And an applicable age error prevents progression
- **Negative Scenario**
  - Given Form 60 upload, Gender, First Name, Last Name, Date of Birth, or PAN Acknowledgement Number is missing
  - When section completion is evaluated
  - Then Contact Info and Next remain unavailable and the missing information is identified
- **Edge Case Scenario**
  - Given the income or loan threshold subsequently makes PAN mandatory
  - When document rules refresh
  - Then the Form 60 path is cleared and the PAN path becomes mandatory
- **Integration Scenario**
  - Given the Form 60 path is complete
  - When the Sales Officer continues
  - Then PAN-dependent verification and PAN-dependent forward integrations are not called

**Assumptions:**

- Form 60 is available only where mandatory-PAN rules do not force Yes.

**Integrations:**

- Document Upload service for Form 60 upload, preview, delete, and replacement.
- No PAN OCR or PAN Validation service is invoked for the Form 60 path.

**In Scope:**

- Form 60 upload and required Individual identity details.

### US-QDE-BASIC-CV-008: Verify Contact Details and Obtain Application Consent

**User Story Description:** As a Sales Officer, I want to verify the borrower’s contact details and obtain application consent so that the customer can authorize the loan application.

**Acceptance Criteria:**

- **Positive Scenario — Contact details**
  - Given Document Verification is complete
  - When Contact Info is displayed
  - Then an Individual borrower sees personal contact fields
  - And a Non-Individual borrower sees Contact Person Name and applicable organization contact fields
  - And Mobile Number and Email Address are required for both borrower types
- **Validation Scenario**
  - Given Mobile Number or Email Address is entered
  - When format validation runs
  - Then Mobile Number must be a valid 10-digit Indian number beginning with 6, 7, 8, or 9
  - And Email Address must be in a valid email format
- **Integration Scenario — Phone and email verification**
  - Given a valid Mobile Number or Email Address is entered
  - When the Sales Officer selects Verify
  - Then the applicable OTP service sends a one-time password to that contact channel
  - And only the generated, unexpired OTP can mark the contact detail as verified
- **Negative Scenario — OTP failure**
  - Given an OTP is incorrect, expired, or the OTP service fails
  - When verification is attempted
  - Then the system displays the applicable error, does not mark the value as verified, and permits an applicable resend or retry
- **Edge Case Scenario — Contact change**
  - Given Mobile Number or Email Address was verified
  - When the Sales Officer changes that value
  - Then the previous verification is cancelled and the changed value must be verified again
- **Integration Scenario — Customer consent**
  - Given phone and email are verified
  - When the Sales Officer selects Consent
  - Then the system generates a customer consent link and records that it was sent
  - And the customer must verify the generated consent OTP and accept the consent
  - And the Sales Officer screen updates when acceptance is received
- **Negative Scenario — Consent pending or failed**
  - Given OTP verification or customer consent is incomplete
  - When progression is evaluated
  - Then Next remains unavailable
- **Completion Scenario**
  - Given customer consent is accepted
  - When the Sales Officer screen refreshes
  - Then the consent status is shown as completed and Next may become available when all other requirements are complete

**Assumptions:**

- The customer can access the generated consent URL.
- The registered mobile number and email address belong to the borrower or authorized contact.
- OTP validity period and resend limits are approved by the business.

**Integrations:**

- Phone OTP service for sending and verifying mobile OTP.
- Email OTP service for sending and verifying email OTP.
- Customer Application Consent site for consent OTP verification and acceptance.
- Consent status polling or refresh to return the customer’s acceptance to the Sales Officer screen.

**In Scope:**

- Contact format validation, OTP actions, consent link generation, polling, and gating.

### US-QDE-BASIC-CV-009: Save Basic Details and Navigate to KYC

**User Story Description:** As a Sales Officer, I want Next to save completed Basic Details and navigate to KYC so that the borrower can continue the QDE journey.

**Acceptance Criteria:**

- **Positive Scenario — Save without progression**
  - Given valid Basic Details have been entered
  - When the Sales Officer selects Save
  - Then the current values are retained without advancing to KYC
  - And the saved values are displayed when Basic Details is revisited
- **Negative Scenario — Incomplete page**
  - Given a required field, validation, verification, or consent is incomplete
  - When the Sales Officer reviews the blocked progression state
  - Then Next remains unavailable and the screen identifies the section or validation that must be resolved
- **Positive Scenario — Continue to KYC**
  - Given every required section, contact verification, document verification, and customer consent is complete
  - When the Sales Officer selects Next
  - Then Basic Details is saved and the applicable forward checks are run
  - And successful completion opens QDE KYC Details
- **Integration Scenario — PAN path**
  - Given the borrower follows the PAN path
  - When Next is selected
  - Then CIF-on-PAN, ETB/CASA, Customer Dedupe, and Recent Lead validation run in the configured sequence
  - And progression occurs only when each required result is successful
- **Edge Case Scenario — Form 60 path**
  - Given the borrower follows the Form 60 path
  - When Next is selected
  - Then PAN-dependent forward checks are skipped
  - And the remaining applicable save and navigation checks continue
- **Negative Scenario — Save or integration failure**
  - Given save or a required forward check fails
  - When the failure is returned
  - Then the system displays a user-readable error, does not mark Basic Details complete, and does not navigate to KYC
  - And the Sales Officer can retry after the issue is resolved
- **Edge Case Scenario — Duplicate submission**
  - Given Save or Next is already processing
  - When the Sales Officer attempts the action again
  - Then duplicate submission is prevented
- **Review Scenario**
  - Given Basic Details was completed successfully
  - When the Sales Officer later revisits the sub-stage
  - Then the completed information is displayed in read-only mode

**Assumptions:**

- All mandatory borrower data and customer consent are available before Next is selected.
- KYC Details is the next configured QDE sub-stage after Basic Details.

**Integrations:**

- Basic Details save service.
- CIF-on-PAN check.
- ETB/CASA check.
- Customer Dedupe check.
- Recent Lead validation.
- QDE stage navigation.
- Each required forward check must return a definitive success or failure; a placeholder success response is not acceptable for production sign-off.

**In Scope:**

- Save, validation feedback, failure handling, duplicate-submit prevention, forward checks, stage completion, navigation, and read-only review.

## Implementation Discrepancies Requiring Resolution

1. **OTP comparison is not enforced:** The current phone, email, and customer-consent flows accept any nonblank six-digit value instead of comparing it with the generated OTP. Phone and email expiry are checked, but consent OTP expiry is not implemented.
2. **PAN verification does not gate progression:** The current completion rule checks that a PAN document was uploaded but does not require successful PAN verification before progression.
3. **Non-Individual PAN re-verification uses the wrong identity inputs:** The current re-verification flow uses Individual name and Date of Birth values instead of Entity Name and Date of Incorporation, which can cause Non-Individual verification to fail.
4. **No visible Save action:** The current screen provides Consent and Next but no Save action, so users cannot save Basic Details without advancing.
5. **Incomplete sections are not identified to the user:** Next remains disabled while incomplete. The detailed disabled reasons are written only to the browser console, so the Sales Officer is not shown which section or rule is blocking progression.
6. **Two Next integrations are unconditional success stubs:** Customer Dedupe and Validate Recent Lead return `success = true` without executing real handlers. They cannot currently reject or stop progression.
7. **Evaluation Type placement:** The live Non-Individual CV screen displayed Evaluation Type within the Application Details card before Loan Basic Info. The repository template places it in Professional Detail. The field table follows the live placement.
8. **Missing required indicators:** Profile Type and Evaluation Type had no required asterisk in the live UI, but repository completion markers treat both as required and block later sections. The UI should show requiredness consistently.
9. **Purpose of Purchase editability:** The live CV screen displayed Commercial as read-only. The reference requirements state it may be editable when shown. Current CV code intentionally prevents editing when the product label is CV.
10. **Marital Status option mismatch:** The current component hardcodes Married, Unmarried, Divorced, and Widowed. The reference table lists a larger Salesforce value set. Business should confirm which list is required.
11. **Post-upload live coverage:** Identity fields after PAN/Form 60 upload, Contact Info, OTP, consent, save, integration failure, and KYC navigation were not exercised because QDE mutation/integration permission was not granted. These requirements are confirmed from the deployed component structure and repository implementation.
12. **Excel applicability header:** `QDE_BD_US` contains CE and CV applicability headers but no Auto header, although the supplied mapping includes Auto = No. The workbook update adds Auto in the next blank applicability column and expands the Applicability merged header to cover it.

## Clarifying Questions

1. Should Evaluation Type remain in live Application Details, or should the deployed UI be aligned to the repository’s Professional Detail placement?
2. Should Profile Type and Evaluation Type display required asterisks to match their current gating behavior?
3. Should the Basic Details Marital Status list remain the current four UI values or use the broader Salesforce picklist values?
4. Should OTP comparison, PAN verification gating, and Non-Individual PAN re-verification be treated as release-blocking defects before CV Basic Details is enabled for production?

