# Commercial Vehicle QDE KYC Details Requirements

## Source Basis

- Live Salesforce inspection on a newly created Commercial Vehicle application through `Application Overview > QDE > KYC Details > Borrower`.
- Live Individual-borrower testing included document-path changes, Aadhaar and alternate verification choices, permanent-address branching, declarations, PEP, cross-sell, customer-image completion, Next, post-save navigation, and completed-stage review.
- Salesforce implementation under `force-app/main/default`, primarily the KYC master pages, extracted-document and office-address components, KYC controllers, verification controllers, stage metadata, and Non-Individual constitution metadata.
- Structure and terminology reference: `Commercial_Vehicle_QDE_Requirements_V2.md`.
- Excel targets: `User Stories_CE.xlsx`, sheets `QDE_KYC Details_Fields` and `QDE_KYC Details_US`.

### Source Interpretation

- The live screen is authoritative for observed labels, visibility, options, state changes, and navigation.
- Repository code and metadata are used for persistence, validation, Non-Individual branches, and failure paths that were unsafe or impractical to complete repeatedly.
- Only user-entered or user-selectable controls are included in the field table. Actions, progress/status messages, masked identifiers, OCR-only values, and other read-only information are covered in the user stories.
- Environment-specific application numbers, record identifiers, test customer values, and mock account numbers are intentionally excluded from client-facing requirements.

## Live Interaction Coverage

### Exercised

- Opened all five Individual Address Document Type options: Aadhaar Card, Passport, Voter ID, Driving License, and Others.
- Confirmed Passport, Voter ID, and Driving License use Full Document or Front and Back Upload, while Aadhaar Card and Others use verification-only paths.
- Opened all Aadhaar methods: eKYC OTP Verification, Biometric Verification, Offline Aadhaar XML, and DigiLocker.
- Opened both Others methods: Video KYC and Digi Locker.
- Completed a DigiLocker verification for Current Address and an eKYC OTP verification for Permanent Address.
- Confirmed eKYC requires the customer to enter a 12-digit Aadhaar number, request a six-digit OTP, accept the Aadhaar consent statement, and verify the OTP. The Sales Officer screen updated to Verified after customer completion.
- Confirmed editable extracted values, masked Aadhaar display, PIN-to-city/state behavior, and POA/POI controls.
- Selected Current Address Same as Permanent = No to open Permanent Address KYC, then Yes to hide the Permanent section.
- Completed both director declarations, exercised PEP = Yes and No, and confirmed Cross-Sell appears only after PEP is answered.
- Exercised both Cross-Sell questions. Selecting interest in a savings account displayed returned repayment-account tiles; closed or suspended accounts were not selectable and Show More displayed account details.
- Confirmed the warning `The applicant has no bank account. Please confirm with the applicant before proceeding.` when both Cross-Sell answers were No.
- Confirmed Customer Photograph is mandatory, accepts a single image, and provides preview/delete before completion. A previously uploaded test image was linked to the test applicant to complete the journey; the native Customer Photograph upload picker itself was not submitted.
- Selected Next, observed duplicate-submit prevention and `Verify Customer Details` processing, and confirmed successful navigation to QDE Occupation Details.
- Reopened completed KYC and confirmed fields were disabled, Delete and Next were hidden, and document Preview remained available.

### Confirmed from Code and Metadata

- Individual Office Address applies only to earning applicants when Office Address Same as Current = No and requires verified Office Email.
- Non-Individual rendering, constitution-driven CIN/GST requirements, registered/office address capture, Darpan rules, and mandatory/additional documents.
- Physical-document OCR, failure/retry behavior, link expiry, upload file rules, face-verification sequence, and save rollback/gating.

### Not Fully Exercised

- Physical Passport, Voter ID, and Driving License uploads and OCR were not submitted.
- Biometric, Offline Aadhaar XML, Video KYC, link-expiry, resend, and integration-failure outcomes were not completed end to end.
- The native Customer Photograph upload event and its immediate Face Liveliness/Face Match processing were not exercised because the test image was linked to the test record after upload.
- The Non-Individual page was not reached in the live newly created application; that branch is documented from current implementation and metadata.

## Excel Field Details Table

| Field Name | Object | Field Type | Drop down values | Display Stage | Display Sub Stage | Display Section | Validation | Error Message | Controlling field | Controlling Expression |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Current Address Document Type | `Document_CheckList__c.Document_Type__c` | Picklist | Aadhaar Card; Passport; Voter ID; Driving License; Others | QDE | KYC Details | Current Address KYC | Required. Changing a completed selection requires the prior proof/verification state to be cleared before another route can be completed. | Complete Current Address verification before continuing. | Customer Type | Visible for Individual applicants. |
| CKYC ID | `Applicant__c.CKYC_ID__c` | Numeric text |  | QDE | KYC Details | Current Address KYC | Optional; digits only; maximum 14 digits. Non-digits are removed. |  | Customer Type | Visible for Individual applicants. |
| Current Document Upload Mode | `Document_CheckList__c.Attached_File_Side__c` | Radio | Full Document; Front and Back Upload | QDE | KYC Details | Current Address KYC | Required for Passport, Voter ID, and Driving License. Changing mode clears files from the previous mode. | Upload the required address proof file(s). | Current Address Document Type | Visible when document type is Passport, Voter ID, or Driving License. |
| Current Aadhaar Verification Method | `Applicant_KYC__c.KYC_Verification_Method__c` | Tile / Radio | eKYC OTP Verification; Biometric Verification; Offline Aadhaar XML; DigiLocker | QDE | KYC Details | Current Address KYC | Required for Aadhaar Card. Verification must complete successfully. | Please complete Aadhaar verification on the Current Address before continuing. | Current Address Document Type | Visible when Current Address Document Type = Aadhaar Card. |
| Current Other Verification Method | `Applicant_KYC__c.KYC_Verification_Method__c` | Picklist | Video KYC; Digi Locker | QDE | KYC Details | Current Address KYC | Required for Others. Verification must complete successfully. | Please complete the selected verification on the Current Address before continuing. | Current Address Document Type | Visible when Current Address Document Type = Others. |
| Current Document Is POA | `Applicant_Address__c.Address_Proof__c` | Toggle | Yes; No | QDE | KYC Details | Current Address KYC | Defaults from extraction when available and remains user-selectable before completion. |  | Current proof/extraction | Displayed after a proof or verification result is available. |
| Current Document Is POI | `Applicant_Address__c.Identity_Proof__c` | Toggle | Yes; No | QDE | KYC Details | Current Address KYC | Defaults from extraction when available and remains user-selectable before completion. |  | Current proof/extraction | Displayed after a proof or verification result is available. |
| Current Full Address Proof File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Current Address KYC | One file required in Full Document mode; upload, preview, delete, and replacement are supported before completion. | Upload Address Proof. | Current Document Upload Mode | Visible for a physical document when Upload Mode = Full Document. |
| Current Address Proof Front File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Current Address KYC | Front and Back files are both required in Front and Back Upload mode. | Upload Front. | Current Document Upload Mode | Visible for a physical document when Upload Mode = Front and Back Upload. |
| Current Address Proof Back File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Current Address KYC | Front and Back files are both required in Front and Back Upload mode. | Upload Back. | Current Document Upload Mode | Visible for a physical document when Upload Mode = Front and Back Upload. |
| Current Extracted First Name | `Document_CheckList__c.First_Name__c` | Text |  | QDE | KYC Details | Current Extracted Document Details | Required when extracted details are shown; editable before completion. | Complete all required extracted details. | Successful verification/OCR | Visible after extraction or verification returns details. |
| Current Extracted Last Name | `Document_CheckList__c.Last_Name__c` | Text |  | QDE | KYC Details | Current Extracted Document Details | Required when extracted details are shown; editable before completion. | Complete all required extracted details. | Successful verification/OCR | Visible after extraction or verification returns details. |
| Current Date of Expiry | `Applicant_KYC__c.KYC_Expiry_Date__c` | Text / Date |  | QDE | KYC Details | Current Extracted Document Details | Required for expiring documents; optional for Aadhaar and Voter ID. | Complete all required extracted details. | Current Address Document Type | Editable after extraction; optional-document rules apply. |
| Current Address Line 1 | `Applicant_Address__c.Address_Line_1__c` | Text |  | QDE | KYC Details | Current Extracted Document Details | Required. | Complete Current Address verification before continuing. | Successful verification/OCR | Visible after extracted details are available. |
| Current Address Line 2 | `Applicant_Address__c.Address_Line_2__c` | Text |  | QDE | KYC Details | Current Extracted Document Details | Required by the extracted-details completion rule. | Complete Current Address verification before continuing. | Successful verification/OCR | Visible after extracted details are available. |
| Current PIN Code | `Applicant_Address__c.PinCode__c` | Numeric text |  | QDE | KYC Details | Current Extracted Document Details | Required; exactly 6 digits. A complete PIN requests city/state resolution. | Complete Current Address verification before continuing. | Successful verification/OCR | Visible after extracted details are available. |
| Current City | `Applicant_Address__c.City__c` | Text |  | QDE | KYC Details | Current Extracted Document Details | Required; populated from PIN when a match is returned, otherwise editable. | Complete Current Address verification before continuing. | Current PIN Code | Auto-populated when PIN lookup succeeds. |
| Current State | `Applicant_Address__c.State__c` | Text |  | QDE | KYC Details | Current Extracted Document Details | Required; populated from PIN when a match is returned, otherwise editable. | Complete Current Address verification before continuing. | Current PIN Code | Auto-populated when PIN lookup succeeds. |
| Is Current Address Same As Permanent Address? | `Applicant_Address__c.Is_Current_Address_Same_As_Permanent__c` | Radio | Yes; No | QDE | KYC Details | Address Verification | Required after Current Address verification. | Answer the Current / Permanent address question. | Current Address completion | Yes hides Permanent Address KYC; No displays it. |
| Is Office Address Same As Current Address? | `Applicant_Address__c.Is_Office_Address_Same_As_Current__c` | Radio | Yes; No | QDE | KYC Details | Address Verification | Required only for an earning Individual when Office Address applies. | Answer the Office address question. | Income Category + Current Address completion | No displays Office Address Details; not applicable for Non-Earning applicants. |
| Permanent Address Document Type | `Document_CheckList__c.Document_Type__c` | Picklist | Aadhaar Card; Passport; Voter ID; Driving License; Others, subject to Current Address route | QDE | KYC Details | Permanent Address KYC | Required when Current Address Same as Permanent = No. Aadhaar is removed when it is already verified or in progress for Current Address. | Complete Permanent Address verification before continuing. | Current Address Same as Permanent + Current document route | If Current Address uses Aadhaar or Others, all otherwise-valid options are available; if Current Address uses a physical document, Permanent Address is restricted to Aadhaar or Others. |
| Permanent Document Upload Mode | `Document_CheckList__c.Attached_File_Side__c` | Radio | Full Document; Front and Back Upload | QDE | KYC Details | Permanent Address KYC | Required for Passport, Voter ID, and Driving License. | Upload the required permanent-address proof file(s). | Permanent Address Document Type | Visible for physical document types. |
| Permanent Aadhaar Verification Method | `Applicant_KYC__c.KYC_Verification_Method__c` | Tile / Radio | eKYC OTP Verification; Biometric Verification; Offline Aadhaar XML; DigiLocker | QDE | KYC Details | Permanent Address KYC | Required for Aadhaar Card. | Please complete Aadhaar verification on the Permanent Address before continuing. | Permanent Address Document Type | Visible when Permanent Address Document Type = Aadhaar Card. |
| Permanent Other Verification Method | `Applicant_KYC__c.KYC_Verification_Method__c` | Picklist | Video KYC; Digi Locker | QDE | KYC Details | Permanent Address KYC | Required for Others. | Please complete the selected verification on the Permanent Address before continuing. | Permanent Address Document Type | Visible when Permanent Address Document Type = Others. |
| Permanent Document Is POA | `Applicant_Address__c.Address_Proof__c` | Toggle | Yes; No | QDE | KYC Details | Permanent Address KYC | User-selectable before completion. |  | Permanent proof/extraction | Displayed after proof/verification. |
| Permanent Document Is POI | `Applicant_Address__c.Identity_Proof__c` | Toggle | Yes; No | QDE | KYC Details | Permanent Address KYC | User-selectable before completion. |  | Permanent proof/extraction | Displayed after proof/verification. |
| Permanent Full Address Proof File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Permanent Address KYC | One file required in Full Document mode. | Upload Address Proof. | Permanent Document Upload Mode | Visible for physical document + Full Document. |
| Permanent Address Proof Front File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Permanent Address KYC | Front and Back files are both required. | Upload Front. | Permanent Document Upload Mode | Visible for Front and Back Upload. |
| Permanent Address Proof Back File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Permanent Address KYC | Front and Back files are both required. | Upload Back. | Permanent Document Upload Mode | Visible for Front and Back Upload. |
| Permanent Extracted First Name | `Document_CheckList__c.First_Name__c` | Text |  | QDE | KYC Details | Permanent Extracted Document Details | Required when extracted details are shown; editable before completion. | Complete all required extracted details. | Permanent verification/OCR | Visible after extraction/verification. |
| Permanent Extracted Last Name | `Document_CheckList__c.Last_Name__c` | Text |  | QDE | KYC Details | Permanent Extracted Document Details | Required when extracted details are shown; editable before completion. | Complete all required extracted details. | Permanent verification/OCR | Visible after extraction/verification. |
| Permanent Date of Expiry | `Applicant_KYC__c.KYC_Expiry_Date__c` | Text / Date |  | QDE | KYC Details | Permanent Extracted Document Details | Required for expiring documents; optional for Aadhaar and Voter ID. | Complete all required extracted details. | Permanent Address Document Type | Editable after extraction. |
| Permanent Address Line 1 | `Applicant_Address__c.Address_Line_1__c` | Text |  | QDE | KYC Details | Permanent Extracted Document Details | Required. | Complete Permanent Address verification before continuing. | Permanent verification/OCR | Visible after extracted details are available. |
| Permanent Address Line 2 | `Applicant_Address__c.Address_Line_2__c` | Text |  | QDE | KYC Details | Permanent Extracted Document Details | Required. | Complete Permanent Address verification before continuing. | Permanent verification/OCR | Visible after extracted details are available. |
| Permanent PIN Code | `Applicant_Address__c.PinCode__c` | Numeric text |  | QDE | KYC Details | Permanent Extracted Document Details | Required; exactly 6 digits. | Complete Permanent Address verification before continuing. | Permanent verification/OCR | A complete PIN requests city/state resolution. |
| Permanent City | `Applicant_Address__c.City__c` | Text |  | QDE | KYC Details | Permanent Extracted Document Details | Required; auto-populated when PIN lookup succeeds, otherwise editable. | Complete Permanent Address verification before continuing. | Permanent PIN Code |  |
| Permanent State | `Applicant_Address__c.State__c` | Text |  | QDE | KYC Details | Permanent Extracted Document Details | Required; auto-populated when PIN lookup succeeds, otherwise editable. | Complete Permanent Address verification before continuing. | Permanent PIN Code |  |
| Office Address Line 1 | `Applicant_Address__c.Address_Line_1__c` | Text |  | QDE | KYC Details | Office Address Details | Required; maximum 255 characters. | Office Address is incomplete. Missing: Address Line 1. | Office Address Same as Current | Visible for earning Individual + answer No. |
| Office Address Line 2 | `Applicant_Address__c.Address_Line_2__c` | Text |  | QDE | KYC Details | Office Address Details | Required; maximum 255 characters. | Office Address is incomplete. Missing: Address Line 2. | Office Address Same as Current | Visible for earning Individual + answer No. |
| Office Address Line 3 | `Applicant_Address__c.Address_Line_3__c` | Text |  | QDE | KYC Details | Office Address Details | Required; maximum 255 characters. | Office Address is incomplete. Missing: Address Line 3. | Office Address Same as Current | Visible for earning Individual + answer No. |
| Office PIN Code | `Applicant_Address__c.PinCode__c` | Numeric text |  | QDE | KYC Details | Office Address Details | Required; exactly 6 digits. Non-digits are removed. | Office Address is incomplete. Missing: Pin Code. | Office Address Same as Current | A valid PIN triggers city/state lookup. |
| Office City | `Applicant_Address__c.City__c` | Text |  | QDE | KYC Details | Office Address Details | Required; read-only when PIN lookup supplies a value, otherwise editable. | Office Address is incomplete. Missing: City. | Office PIN Code |  |
| Office State | `Applicant_Address__c.State__c` | Text |  | QDE | KYC Details | Office Address Details | Required; read-only when PIN lookup supplies a value, otherwise editable. | Office Address is incomplete. Missing: State. | Office PIN Code |  |
| Office Country | `Applicant_Address__c.Country__c` | Text |  | QDE | KYC Details | Office Address Details | Required. | Office Address is incomplete. Missing: Country. | Office Address Same as Current | Visible for earning Individual + answer No. |
| Office Email | `Applicant_Address__c.Email__c` | Email with Verify action |  | QDE | KYC Details | Office Address Details | Required; valid email format; changing a verified value requires re-verification. | Enter a valid email address; Please verify the Office Email before continuing. | Office Address Same as Current | Office Email OTP verification is mandatory. |
| Bank Director Relationship Declaration | `Applicant__c.Is_Applicant_Relative_Of_Director__c` | Radio | Yes; No | QDE | KYC Details | Director Declaration | Required. | Answer both Director Declaration questions before continuing. | Required address answers | Confirms the RBI-related bank-director relationship statement. |
| Other Bank / Senior Officer Relationship Declaration | `Applicant__c.Is_Applicant_Relative_Of_Senior_Officer__c` | Radio | Yes; No | QDE | KYC Details | Director Declaration | Required. | Answer both Director Declaration questions before continuing. | Required address answers | Confirms the second RBI-related relationship statement. |
| Politically Exposed Person | `Applicant__c.Are_you_a_Politically_Exposed_Person__c` | Radio | Yes; No | QDE | KYC Details | Politically Exposed Person | Required. | Answer the PEP screening question before continuing. | Both Director Declarations | Cross-Sell displays after either answer. |
| Has Bank Account | `Applicant__c.Has_Bank_Account__c` | Radio | Yes; No | QDE | KYC Details | Cross-Sell Account | Required. | Answer both Cross-Sell account questions before continuing. | PEP answered | No + Savings Interest No displays a confirmation warning. |
| Interested in Opening Savings Account | `Applicant__c.Interested_In_Opening_Savings_Account__c` | Radio | Yes; No | QDE | KYC Details | Cross-Sell Account | Required. | Answer both Cross-Sell account questions before continuing. | PEP answered | Yes displays eligible returned repayment-account tiles when available. |
| Repayment Account | `Applicant__c.Bank_Account_No__c` | Selectable account tile | Eligible active, non-suspended returned accounts | QDE | KYC Details | Cross-Sell Account | Closed or suspended accounts cannot be selected. The choice is optional unless business policy requires one. |  | Interested in Opening Savings Account | Visible when Savings Interest = Yes and account data is returned. |
| Customer Photograph | `Document_CheckList__c.ContentVersionId__c` | File Upload | JPG; JPEG; PNG; maximum 1 file | QDE | KYC Details | Customer Image | Required after both Cross-Sell questions are answered. Upload is disabled until the existing image is removed. | Upload the customer photograph before continuing. | Both Cross-Sell questions | Upload triggers Face Liveliness and Face Match. |
| CIN Number | `Applicant_KYC__c.KYC_No__c` | Text or Picklist | Integration-returned CIN values when multiple are available | QDE | KYC Details | Upload CIN | Required when the selected entity constitution requires CIN. | Complete the CIN section. | Non-Individual constitution | Editable after CIN upload processing completes. |
| CIN Document | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Upload CIN | Required when CIN is constitution-mandatory; one active file. | Complete the CIN section. | Non-Individual constitution | Upload triggers PAN-to-CIN lookup/extraction. |
| GST Number | `Applicant_KYC__c.KYC_No__c` | Text or Picklist | Integration-returned GST values when multiple are available | QDE | KYC Details | Upload GST | Required when GST is constitution-mandatory. | Complete the GST section. | Non-Individual constitution + CIN completion | Editable after GST upload processing completes. |
| GST Document | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Upload GST | Required when GST is constitution-mandatory; one active file. | Complete the GST section. | Non-Individual constitution + CIN completion | Upload triggers PAN-to-GSTN lookup/extraction. |
| GST Address Line 1 | `Applicant_KYC__c.KYC_Address_Line_1__c` | Text |  | QDE | KYC Details | Upload GST | Required after GST processing. | Complete the GST section. | GST Document |  |
| GST Address Line 2 | `Applicant_KYC__c.KYC_Address_Line_2__c` | Text |  | QDE | KYC Details | Upload GST | Required after GST processing. | Complete the GST section. | GST Document |  |
| GST PIN Code | `Applicant_KYC__c.KYC_Pin_Code__c` | Numeric text |  | QDE | KYC Details | Upload GST | Required; exactly 6 digits. | Complete the GST section. | GST Document | Resolves location options. |
| GST District | `Applicant_KYC__c.KYC_District__c` | Picklist | Districts returned for the resolved state | QDE | KYC Details | Upload GST | Required. | Complete the GST section. | GST PIN Code / State |  |
| Is GST Your Registered Address? | `Applicant_Address__c.Is_Registered_Address_Same_As_GST__c` | Radio | Yes; No | QDE | KYC Details | Upload GST | Required when GST applies. | Select whether GST is the Registered Address. | GST completion | Yes reuses GST address and proof; No requires separate Registered Address proof. |
| Registered Address Proof | `Document_CheckList__c.Document_Type__c` | Picklist | Constitution/document-master options not already used; may include GST and approved address proofs | QDE | KYC Details | Registered Address | Required unless GST is confirmed as the Registered Address. | Complete Registered Address details. | GST Registered Address answer | Selecting a non-GST proof requires upload. |
| Registered Address Proof File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Registered Address | Required for a selected non-GST proof; one active file. | Upload the selected Registered Address proof. | Registered Address Proof |  |
| Registered Address Line 1 | `Applicant_Address__c.Address_Line_1__c` | Text |  | QDE | KYC Details | Registered Address | Required. | Complete Registered Address details. | Registered proof/GST reuse |  |
| Registered Address Line 2 | `Applicant_Address__c.Address_Line_2__c` | Text |  | QDE | KYC Details | Registered Address | Required. | Complete Registered Address details. | Registered proof/GST reuse |  |
| Registered Address PIN Code | `Applicant_Address__c.PinCode__c` | Numeric text |  | QDE | KYC Details | Registered Address | Required; exactly 6 digits. | Complete Registered Address details. | Registered proof/GST reuse | Resolves State, District, and City. |
| Registered Address District | `Applicant_Address__c.District__c` | Picklist | Districts returned for the resolved state | QDE | KYC Details | Registered Address | Required. | Complete Registered Address details. | Registered Address PIN Code | State and City are system-resolved. |
| Office Address Is Same As Registered Address | `Applicant_Address__c.Is_Office_Address_Same_As_Registered__c` | Radio | Yes; No | QDE | KYC Details | Registered Address | Required after Registered Address is complete. | Select whether Office Address is the same as Registered Address. | Registered Address completion | Yes reuses Registered Address; No opens Office Address. |
| Entity Office Address Proof | `Document_CheckList__c.Document_Type__c` | Picklist | Constitution/document-master options not already used | QDE | KYC Details | Office Address | Required when Office differs from Registered. | Complete Office Address details. | Office Same as Registered |  |
| Entity Office Address Proof File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG | QDE | KYC Details | Office Address | Required for a selected proof; one active file. | Upload the selected Office Address proof. | Entity Office Address Proof |  |
| Entity Office Address Line 1 | `Applicant_Address__c.Address_Line_1__c` | Text |  | QDE | KYC Details | Office Address | Required. | Complete Office Address details. | Office Same as Registered | Visible when answer = No. |
| Entity Office Address Line 2 | `Applicant_Address__c.Address_Line_2__c` | Text |  | QDE | KYC Details | Office Address | Required. | Complete Office Address details. | Office Same as Registered | Visible when answer = No. |
| Entity Office Address PIN Code | `Applicant_Address__c.PinCode__c` | Numeric text |  | QDE | KYC Details | Office Address | Required; exactly 6 digits. | Complete Office Address details. | Office Same as Registered | Resolves State, District, and City. |
| Entity Office Address District | `Applicant_Address__c.District__c` | Picklist | Districts returned for the resolved state | QDE | KYC Details | Office Address | Required. | Complete Office Address details. | Entity Office Address PIN Code |  |
| Are You an NPO? | `Applicant__c.NPO__c` | Radio | NPO; Not an NPO | QDE | KYC Details | Darpan Details | Required for configured Trust, Society, and Association entity codes. Changing the answer clears incompatible Darpan values/documents. | Complete mandatory Darpan details. | Non-Individual entity code | Controls Darpan document requirements. |
| Darpan Deferral Approval | `Applicant__c.Deferral_Approval__c` | Radio | Yes; No | QDE | KYC Details | Darpan Details | Required where Darpan applies. Yes forces NPO and disables Darpan ID/date entry. | Complete mandatory Darpan details. | Are You an NPO? | Yes requires Deferral Approval and Acknowledgement Copy documents. |
| Darpan ID | `Applicant__c.Darpan_Id__c` | Text |  | QDE | KYC Details | Darpan Details | Editable for NPO with no deferral; cleared for Not an NPO or approved deferral. | Complete mandatory Darpan details. | NPO + Deferral Approval |  |
| Darpan Date of Registration | `Applicant__c.Darpan_Registration_Date__c` | Date/Time |  | QDE | KYC Details | Darpan Details | Editable for NPO with no deferral; cleared for other paths. | Complete mandatory Darpan details. | NPO + Deferral Approval |  |
| Darpan Certificate | `Document_CheckList__c.ContentVersionId__c` | File Upload | Configured document file types | QDE | KYC Details | Darpan Details | Required for NPO with no deferral. | Please complete mandatory Darpan document uploads. | NPO + Deferral Approval = No |  |
| Darpan Customer Declaration | `Document_CheckList__c.ContentVersionId__c` | File Upload | Configured document file types | QDE | KYC Details | Darpan Details | Required when entity declares Not an NPO. | Please complete mandatory Darpan document uploads. | Are You an NPO? | Visible when Not an NPO. |
| Darpan Deferral Approval Document | `Document_CheckList__c.ContentVersionId__c` | File Upload | Configured document file types | QDE | KYC Details | Darpan Details | Required when Deferral Approval = Yes. | Please complete mandatory Darpan document uploads. | Darpan Deferral Approval |  |
| Darpan Acknowledgement Copy | `Document_CheckList__c.ContentVersionId__c` | File Upload | Configured document file types | QDE | KYC Details | Darpan Details | Required when Deferral Approval = Yes. | Please complete mandatory Darpan document uploads. | Darpan Deferral Approval |  |
| Additional Document Type | `Document_CheckList__c.Document_Type__c` | Picklist | Constitution-required and approved ad-hoc documents not already uploaded | QDE | KYC Details | Additional Documents | Required before an additional upload can begin. Options are constitution-driven and exclude PAN, CIN/GST sections, and Darpan-specific documents as applicable. | Select and upload the missing mandatory document(s). | Non-Individual constitution + prior sections |  |
| Additional Document File | `Document_CheckList__c.ContentVersionId__c` | File Upload | PDF; JPG; JPEG; PNG or document-master configuration | QDE | KYC Details | Additional Documents | Required documents and the configured minimum number of ad-hoc documents must be collected before save. Multiple document types can be added one at a time. | Missing mandatory documents; upload at least the configured number of proof documents. | Additional Document Type | Upload, preview, delete, and repeated add are supported. |

## Validation and Dependency Matrix

| Controlling Condition | Result |
| --- | --- |
| Individual + Aadhaar Card | Four Aadhaar verification methods display; no physical upload mode displays. |
| Individual + Others | Video KYC or Digi Locker is required; no physical upload mode displays. |
| Individual + Passport/Voter ID/Driving License | Full Document or Front and Back Upload is required; successful upload invokes OCR/extraction. |
| Full Document selected | One complete proof file is required. |
| Front and Back Upload selected | Both Front and Back files are required. |
| Verification/OCR incomplete | Address Verification and later sections remain unavailable. |
| Current Address Same as Permanent = Yes | Permanent Address KYC is hidden and Current details are reused. |
| Current Address Same as Permanent = No | Permanent Address KYC is required. If Current uses a physical document, Permanent is restricted to Aadhaar or Others; otherwise all otherwise-valid Permanent options are available. |
| Earning Individual + Office Same as Current = No | All three Office Address lines, PIN, City, State, Country, and verified Office Email are required. |
| Non-Earning Individual | Office Address is not applicable. |
| Both director declarations unanswered | PEP and later sections remain unavailable. |
| PEP unanswered | Cross-Sell remains unavailable. |
| Both Cross-Sell questions = No | A confirmation warning appears; progression is still possible after Customer Photograph. |
| Savings interest = Yes + eligible account response | Repayment-account tiles display; closed/suspended accounts are disabled. |
| Both Cross-Sell questions answered | Customer Photograph becomes mandatory. |
| Non-Individual constitution requires CIN/GST | CIN and GST sections progressively unlock and must complete before Registered Address. |
| GST is Registered Address = Yes | GST proof/address is reused; separate Registered proof entry is locked. |
| Office is Registered Address = Yes | Registered proof/address is reused; separate Office section is hidden. |
| Darpan-applicable entity | NPO/deferral answers determine Darpan ID/date editability and mandatory documents. |
| Any required Non-Individual document missing | Save/Next is blocked and the missing constitution requirement is identified. |
| KYC complete | Next saves, runs required customer checks, marks KYC complete, and opens the configured next QDE sub-stage. |
| Completed KYC revisited | Fields are read-only; document Preview remains available; Delete and Next are hidden. |

## Agile Requirements Hierarchy

### Epic: Commercial Vehicle Loan Origination

Enable Sales Officers to originate Commercial Vehicle loans through a controlled, verified, and auditable QDE journey.

### Feature: CV QDE KYC Details

Capture Individual or Non-Individual KYC evidence, verify identity and addresses, collect regulatory declarations and required documents, and continue only after applicable verification, validation, and customer checks succeed.

## User Stories

### US-QDE-KYC-CV-001: Select the Individual Address-Proof Route

**User Story Description:** As a Sales Officer, I want to select the applicable Current Address KYC route so that the borrower follows the correct verification or document-upload process.

**Acceptance Criteria:**

- **Positive Scenario — Physical document:** Given an Individual borrower, when Passport, Voter ID, or Driving License is selected, then Full Document and Front and Back Upload options are displayed.
- **Positive Scenario — Verification-only document:** Given Aadhaar Card or Others is selected, when the route is displayed, then physical upload mode is hidden and the applicable verification methods are shown.
- **Validation Scenario:** Given Full Document is selected, one complete proof is required; given Front and Back Upload is selected, both files are required.
- **Edge Case Scenario:** Given the user changes document type or upload mode before completion, then incompatible files, extraction, and verification state are cleared so only the active route remains.
- **Persistence Scenario:** Given valid route details are saved, when KYC is revisited, then the selected route and linked documents are displayed.

**Assumptions:**

- The customer has an accepted proof or can complete an approved electronic verification method.

**Integrations:**

- Document Upload service accepts configured PDF/image types and supports preview, delete, and replacement.
- Physical proof upload triggers Address Document OCR. Failure leaves the proof unverified, blocks progression, and allows delete/re-upload or retry.

**In Scope:**

- Document type, upload mode, file-side completeness, route switching, and retained proof state.

### US-QDE-KYC-CV-002: Complete Aadhaar or Alternate Electronic Verification

**User Story Description:** As a Sales Officer, I want to complete the borrower’s approved electronic KYC method so that identity and address information can be verified without a physical document.

**Acceptance Criteria:**

- **Positive Scenario — Aadhaar eKYC OTP:** Given eKYC OTP Verification is selected, when the link is generated, then the customer enters a valid 12-digit Aadhaar number, requests a six-digit OTP, accepts consent, and verifies the OTP.
- **Integration Scenario — Completion:** Given customer verification succeeds, when the Sales Officer screen polls the verification status, then the selected method is marked Verified and extracted details are displayed.
- **Positive Scenario — Other methods:** Given Biometric, Offline Aadhaar XML, DigiLocker, Video KYC, or Digi Locker is selected, when its verification succeeds, then the selected Current or Permanent address route is marked verified.
- **Negative Scenario:** Given initiation, consent, OTP, biometric, XML, video, or vault verification fails, then the route remains unverified, progression is blocked, and a user-readable retry response is displayed.
- **Edge Case Scenario — Expiry:** Given an eKYC link is more than 72 hours old, then it is marked expired and the user can request a new link or switch document route.
- **Edge Case Scenario — Polling timeout:** Given customer completion is not returned within the configured polling window, then the user remains on KYC and can view/retry the link without duplicate verification.

**Assumptions:**

- The customer’s Aadhaar-linked mobile and consent channel are available.
- Production integrations perform real identity validation; test hints or unconditional OTP acceptance are not valid for production sign-off.

**Integrations:**

- Aadhaar/UIDAI eKYC OTP and consent service.
- Biometric capture, Offline Aadhaar XML, DigiLocker, and Video KYC services.
- Trigger: selecting Verify. Success returns verified identity/address details. Failure or timeout blocks progression. Expired links can be regenerated.

**In Scope:**

- Verification selection, consent, OTP, status polling, expiry, retry, and verified-result display.

### US-QDE-KYC-CV-003: Review and Correct Extracted KYC Details

**User Story Description:** As a Sales Officer, I want to review and correct permitted extracted details so that the verified address saved for the borrower is complete and accurate.

**Acceptance Criteria:**

- **Positive Scenario:** Given verification/OCR returns details, then First Name, Last Name, Date of Expiry where applicable, Address Lines, PIN, City, and State are displayed for review and permitted correction.
- **Validation Scenario:** Given a required editable value is blank, or PIN is not six digits, then completion remains blocked and the missing details are highlighted.
- **Integration Scenario — PIN:** Given a valid six-digit PIN is entered, when location lookup succeeds, then City and State are populated; when lookup fails, they remain editable for manual completion.
- **Review Scenario:** Gender, Date of Birth, Date of Issue, document number, Place of Issue, masked Aadhaar, and verification status are displayed as read-only extraction results.
- **Edge Case Scenario:** Aadhaar permits blank Date of Issue, Date of Expiry, and Place of Issue; Voter ID permits blank Date of Expiry.
- **Persistence Scenario:** Given corrected values are saved, when KYC is revisited, then the saved address values are displayed.

**Assumptions:**

- Users may correct only the fields explicitly presented as editable.

**Integrations:**

- OCR/eKYC extraction supplies the initial values.
- PIN Location service supplies City and State. Lookup failure must not discard entered data.

**In Scope:**

- Extracted-detail review, permitted corrections, document-specific optionality, location lookup, and saved-value retrieval.

### US-QDE-KYC-CV-004: Capture Permanent and Office Address Requirements

**User Story Description:** As a Sales Officer, I want to confirm address relationships and capture any separate Permanent or Office address so that all applicable borrower locations are verified.

**Acceptance Criteria:**

- **Positive Scenario — Same address:** Given Current Address is the same as Permanent, when Yes is selected, then Permanent KYC is hidden and Current Address is reused.
- **Positive Scenario — Different permanent address:** Given No is selected, then Permanent Address KYC is required and supports the same approved document and verification routes.
- **Positive Scenario — Office not applicable:** Given the borrower is Non-Earning, then Office Address is not required.
- **Positive Scenario — Different office address:** Given an earning borrower selects Office Address Same as Current = No, then all three Address Lines, PIN, City, State, Country, and Office Email are required.
- **Integration Scenario — Office Email:** Given a valid Office Email, when Verify is selected, then an OTP is generated and sent; successful OTP verification marks the email verified.
- **Negative Scenario:** Given Office Email is invalid, unverified, or OTP fails/expires, then progression is blocked and resend/retry remains available.
- **Edge Case Scenario:** Changing an address relationship from No to Yes clears or ignores the no-longer-applicable separate-address values.
- **Persistence Scenario:** Saved address relationships and applicable address values are retained when KYC is revisited.

**Assumptions:**

- Income Category is available from Basic Details to determine Office applicability.

**Integrations:**

- Aadhaar/OCR and PIN Location services for a separate Permanent Address.
- Office Email OTP service. Delivery failure must be reported; verification cannot complete without a valid generated OTP.

**In Scope:**

- Address relationship answers, Permanent KYC, earning-applicant Office Address, Office Email verification, reset, and persistence.

### US-QDE-KYC-CV-005: Capture Regulatory Declarations and PEP Status

**User Story Description:** As a Sales Officer, I want to capture the required relationship and politically exposed person declarations so that regulatory KYC statements are recorded before progression.

**Acceptance Criteria:**

- **Positive Scenario:** Given applicable address questions are answered, then both RBI-related director/officer declarations are displayed and each requires Yes or No.
- **Dependency Scenario:** Given both declarations are answered, then the PEP question is displayed; given PEP is answered, then Cross-Sell Account is displayed.
- **Negative Scenario:** Given either declaration or PEP is unanswered, then later sections remain unavailable and Next cannot be used.
- **Edge Case Scenario:** Both PEP Yes and No permit the journey to continue to Cross-Sell while retaining the selected regulatory answer for downstream review.
- **Persistence Scenario:** Given declarations are saved, when KYC is revisited, then the answers are displayed read-only.

**Assumptions:**

- The displayed declaration wording is approved by Legal and Compliance.

**Integrations:**

- No external integration is invoked by these declarations.

**In Scope:**

- Progressive declaration display, required answers, gating, and read-only review.

### US-QDE-KYC-CV-006: Capture Banking Preferences and Repayment Account

**User Story Description:** As a Sales Officer, I want to record the borrower’s banking and savings-account preferences so that eligible repayment-account options can be considered.

**Acceptance Criteria:**

- **Positive Scenario:** Given PEP is answered, then Has Bank Account and Interested in Opening a Savings Account are required.
- **Validation Scenario:** Given either answer is missing, then Customer Image remains unavailable and Next is blocked.
- **Edge Case Scenario — No account:** Given both answers are No, then the system displays the no-bank-account confirmation warning without blocking the journey after remaining requirements are complete.
- **Integration Scenario — Account list:** Given Savings Interest is Yes and eligible account data exists, then returned accounts are displayed with summary details and Show More.
- **Validation Scenario — Eligibility:** Closed or suspended accounts are clearly identified and cannot be selected; an eligible account can be selected as the repayment account.
- **Negative Scenario:** Given account data is unavailable or malformed, then no account tiles are displayed and the Sales Officer can continue without inventing an account selection unless business policy mandates one.
- **Persistence Scenario:** A selected eligible repayment account and both preference answers are retained on revisit.

**Assumptions:**

- The upstream customer/account lookup returns accounts belonging to the correct borrower.
- Repayment-account selection is optional in the current implementation.

**Integrations:**

- Existing Customer/CASA Account service supplies account status and details.
- Trigger occurs before or during KYC from the configured customer lookup. Incorrect-customer, closed, suspended, or malformed results must not be selectable; the user can retry the upstream lookup.

**In Scope:**

- Banking preference answers, warning, eligible-account display, detail review, selection, and persistence.

### US-QDE-KYC-CV-007: Upload and Verify the Customer Photograph

**User Story Description:** As a Sales Officer, I want to upload and verify the applicant’s photograph so that KYC completion includes a valid customer image.

**Acceptance Criteria:**

- **Positive Scenario:** Given both Cross-Sell questions are answered, when Customer Image appears, then one JPG, JPEG, or PNG photograph is required.
- **Validation Scenario:** Given no photograph is present, then Next remains blocked with `Upload the customer photograph before continuing.`
- **Positive Scenario — File management:** Given a photograph is uploaded, then Preview and Delete are available before completion; a replacement can be uploaded only after deletion.
- **Integration Scenario:** Given upload completes, then Face Liveliness runs first and Face Match runs second.
- **Negative Scenario:** Given either face check is unavailable, fails validation, or returns an error, then the verification progress shows the failure, KYC must not be treated as successfully image-verified, and the user can retry or replace the image.
- **Edge Case Scenario:** Duplicate images cannot be added while an active photograph exists.
- **Review Scenario:** After KYC completion, Preview remains available while Delete and new upload are disabled.

**Assumptions:**

- The photograph belongs to the applicant and meets approved image-quality standards.

**Integrations:**

- Document Upload service.
- Face Liveliness followed by Face Match. Trigger is upload completion; success closes progress, failure remains visible and retry/replacement is available.

**In Scope:**

- Image file rules, mandatory gating, preview/delete/replacement, verification sequence, failure handling, and review state.

### US-QDE-KYC-CV-008: Capture Non-Individual CIN and GST KYC

**User Story Description:** As a Sales Officer, I want to collect constitution-required CIN and GST evidence so that a Non-Individual borrower’s registration information is verified.

**Acceptance Criteria:**

- **Positive Scenario — Constitution rules:** Given a Non-Individual borrower, when KYC opens, then required CIN and GST sections are determined from the entity constitution and CV product.
- **Positive Scenario — CIN:** Given CIN is required, when a permitted CIN document is uploaded, then the PAN-to-CIN service returns one or more CIN values for selection/confirmation.
- **Dependency Scenario:** GST does not display until a required CIN section is complete.
- **Positive Scenario — GST:** Given GST is required, when the GST document is uploaded, then GST number and required address details are displayed for review and completion.
- **Integration Scenario:** PAN-to-CIN and PAN-to-GSTN are triggered by their respective uploads; successful responses populate the applicable numbers/details.
- **Negative Scenario:** Missing configuration, no result, failed extraction, or incomplete returned address keeps the applicable section incomplete and allows delete/re-upload or retry.
- **Persistence Scenario:** Saved CIN/GST evidence and reviewed values are displayed read-only after completion.

**Assumptions:**

- Entity Type and PAN were captured in Basic Details and constitution metadata is maintained.

**Integrations:**

- Document Upload, PAN-to-CIN, PAN-to-GSTN, and location-master services.
- Each integration is triggered by its document upload; failure blocks the dependent section and supports retry/re-upload.

**In Scope:**

- Constitution-driven visibility, CIN/GST files, returned values, address completion, gating, and persistence.

### US-QDE-KYC-CV-009: Capture Non-Individual Registered and Office Addresses

**User Story Description:** As a Sales Officer, I want to capture registered and office address proofs for a Non-Individual borrower so that entity locations are supported by approved documents.

**Acceptance Criteria:**

- **Positive Scenario — GST reuse:** Given GST is complete, when the user confirms GST is the Registered Address, then GST proof/address is reused and separate Registered editing is locked.
- **Positive Scenario — Separate registered address:** Given GST is not the Registered Address or GST does not apply, then an approved Registered Address proof, file, address lines, PIN, District, City, and State are required.
- **Positive Scenario — Office reuse:** Given Office Address is the same as Registered, then Registered details are reused and the separate Office section is hidden.
- **Positive Scenario — Separate office:** Given No is selected, then approved Office proof, file, and complete Office address details are required.
- **Integration Scenario — Location:** A valid PIN loads permitted location values; State and City are system-resolved and District is selected from the returned list.
- **Negative Scenario:** Missing proof, file, relationship answer, or required address value blocks Additional Documents and Next.
- **Edge Case Scenario:** Changing a same-address answer or selected proof clears/ignores obsolete files and dependent values.
- **Persistence Scenario:** Saved entity addresses and proof relationships display read-only on revisit.

**Assumptions:**

- Address-proof options are maintained through the approved document master/constitution configuration.

**Integrations:**

- Document Upload and Location Master services. Failed location lookup blocks completion until valid location values can be supplied.

**In Scope:**

- GST reuse, registered and office proof/address capture, location dependencies, reset behavior, gating, and review.

### US-QDE-KYC-CV-010: Collect Darpan and Constitution-Mandatory Documents

**User Story Description:** As a Sales Officer, I want the required Darpan and constitution documents to be identified and collected so that Non-Individual KYC satisfies its legal-form requirements.

**Acceptance Criteria:**

- **Positive Scenario — Darpan NPO:** Given a Darpan-applicable entity declares NPO without deferral, then Darpan ID, registration date, and Darpan Certificate are applicable.
- **Positive Scenario — Not an NPO:** Given Not an NPO is selected, then Darpan ID/date are cleared and Customer Declaration is required.
- **Positive Scenario — Deferral:** Given Deferral Approval is Yes, then NPO is enforced, Darpan ID/date are disabled, and both Deferral Approval and Acknowledgement Copy documents are required.
- **Dependency Scenario:** Once a Darpan document is uploaded, controlling status answers are locked until incompatible uploads are removed.
- **Positive Scenario — Constitution documents:** The Mandatory Documents view lists all required files and the configured minimum number of acceptable ad-hoc proofs for the entity constitution.
- **Validation Scenario:** Missing required documents or insufficient ad-hoc proofs block save and identify the outstanding requirements.
- **Edge Case Scenario:** PAN, CIN/GST-section documents, and Darpan-specific files are not duplicated in Additional Documents.
- **Persistence Scenario:** Collected documents and requirement status display read-only after completion.

**Assumptions:**

- Constitution and Darpan applicability metadata is legally approved and maintained.

**Integrations:**

- Document Master/Constitution configuration supplies mandatory and ad-hoc requirements.
- Document Upload supports each file. Configuration or upload failure blocks completion and permits retry after correction.

**In Scope:**

- NPO/deferral dependencies, Darpan fields/files, constitution document list, ad-hoc minimums, validation, and review.

### US-QDE-KYC-CV-011: Save KYC, Run Customer Checks, and Continue QDE

**User Story Description:** As a Sales Officer, I want Next to save complete KYC and run required customer checks so that the borrower can continue to the correct QDE sub-stage.

**Acceptance Criteria:**

- **Positive Scenario — Individual:** Given all applicable address, declaration, PEP, Cross-Sell, photograph, and verification requirements are complete, when Next is selected, then KYC is saved and required customer checks begin.
- **Positive Scenario — Non-Individual:** Given constitution, address, Darpan, and mandatory-document requirements are complete, when Next is selected, then entity KYC is saved and Dedupe and Eligibility is opened.
- **Integration Scenario — Individual:** Customer Dedupe runs first and Validate Recent Lead runs second. Navigation occurs only after both return success.
- **Negative Scenario:** Given save or a required integration fails, then a user-readable error is displayed, the stage is not completed, navigation does not occur, and the user can retry after correction.
- **Edge Case Scenario — Duplicate submit:** Given Next is processing, then the button displays Saving and duplicate submission is prevented.
- **Navigation Scenario:** Successful Individual completion opens QDE Occupation Details; successful Non-Individual completion opens Dedupe and Eligibility.
- **Review Scenario:** Given KYC is complete, when it is revisited, then all controls are read-only, Next/Delete are hidden, and document Preview remains available.
- **Persistence Scenario:** Saved values and selected documents remain available after refresh and revisit.

**Assumptions:**

- KYC Details is an applicant-based mandatory QDE step.
- The next-stage configuration and applicant routing are active.

**Integrations:**

- KYC Save service.
- Customer Dedupe and Validate Recent Lead for the Individual Next path.
- QDE stage-navigation service.
- Trigger is Next; each required service must return success. Failure blocks stage completion and allows a deliberate retry without duplicate submission.

**In Scope:**

- Final validation, save, processing state, rollback/gating, retry, stage completion, navigation, persistence, and read-only review.

## Implementation Discrepancies Requiring Resolution

1. **Test identity mismatch:** The deployed verification response displayed identity/address information that did not match the newly created applicant, and an account-detail response included another customer name. Production must reject cross-customer results and bind every response to the active applicant.
2. **eKYC verification stub:** The current Aadhaar verification implementation accepts a generic six-digit test OTP and includes stub behavior. Production sign-off requires real OTP validation, expiry, attempt limits, and UIDAI response verification.
3. **Proof-toggle default mismatch:** Source comments state POA/POI should default to Yes when extraction first appears, while the exercised screen displayed No. The approved default must be confirmed.
4. **Office-question mismatch:** The live Non-Earning path omitted the Office Address question, which aligns with backend applicability, while the current Individual template contains the question without an explicit rendering condition. The UI and source should use one approved rule.
5. **Editable extraction persistence gap:** First Name, Last Name, and Date of Expiry are editable in the extracted-details component, but the KYC save mapping explicitly persists address corrections and does not clearly persist these edited identity values. The UI should either save them or render them read-only.
6. **Face-check gating:** Customer-image Face Liveliness/Face Match runs after native upload, but final Next gating checks only that an image exists. A failed face check can leave an image present; business must confirm whether successful face verification is mandatory for Next.
7. **Non-Individual Next integration difference:** Individual Next runs Customer Dedupe and Validate Recent Lead, while Non-Individual Next saves and navigates without the same chain. Confirm whether this is intentional.
8. **Repayment-account data quality:** The live mock account list included a closed account and an active account associated with a different customer name. Closed/suspended disabling worked, but applicant ownership validation requires correction.
9. **Reference scope conflict:** The reference requirements include read-only/system-derived KYC values in the field table. This document excludes them in accordance with the approved reusable prompt and covers them in user stories.
10. **Premature completion from account selection:** Selecting a repayment account invokes the full KYC save with a partial payload. That save can mark KYC complete before Next, make an incomplete page read-only after refresh, and bypass intended customer checks.
11. **Weak Individual server validation:** The Individual save path does not independently enforce all UI-mandatory address, declaration, PEP, Cross-Sell, image, and office-verification requirements. A partial or direct save can therefore complete the stage.
12. **Post-save completion ordering:** Individual KYC is marked complete before Customer Dedupe and Validate Recent Lead finish. If a later check fails, navigation stops but the stage can already be locked and browser draft state cleared.
13. **Retry action does not retry:** The integration progress modal's Retry action resets its display state but does not rerun OCR, face checks, CIN/GST extraction, Aadhaar verification, or post-save customer checks. Delete/re-upload or a fresh action is currently required.
14. **Physical OCR and extracted-field gating:** A physical file can satisfy the address gate even when OCR fails, and visually required extracted fields are not included in the final Next or server validation. The approved business requirement must be enforced consistently.
15. **Office OTP exposure:** The generated Office Email OTP is returned to the browser and logged in the console, and attempt throttling is not evidenced. Production must keep the OTP server-side and enforce expiry, attempt, and resend limits.
16. **Face Match payload:** The Face Match handler sends only the customer photograph; no second verified reference image is evidenced. A real face comparison and its success criteria require confirmation.
17. **Non-Individual validation gaps:** Final client validation checks entity PIN values for presence rather than exactly six digits, and Darpan status is not consistently server-required. The server must enforce the signed-off rules.
18. **Duplicate constitution configuration:** More than one CV Private Limited constitution metadata record can match the same entity/product combination while selection uses an unordered first match. Configuration should be unique and deterministic.

## Clarifying Questions

1. Must Face Liveliness and Face Match both succeed before Next, or is successful image upload sufficient?
2. Should Current/Permanent POA and POI default to Yes or No after successful extraction?
3. Should editable extracted First Name, Last Name, and Date of Expiry be persisted, or should they be read-only?
4. Is Repayment Account selection mandatory when eligible CASA accounts are returned?
5. Should the Non-Individual Next path also run Customer Dedupe and Validate Recent Lead?
6. Please confirm the final production OTP expiry, resend limit, attempt limit, and polling timeout for Aadhaar and Office Email.
7. Should CV entity constitutions that list PAN or Form 60 treat those Basic Details files as already satisfied rather than requesting them again in KYC?
8. Should OCR completion and every visually required extracted field be mandatory before Next for physical-document routes?
9. Should repayment-account selection save only the account choice without completing KYC?
10. What operation must the Retry button rerun for each failed integration?
11. Must Darpan status, Darpan ID, and registration date be mandatory for the applicable NPO path?
