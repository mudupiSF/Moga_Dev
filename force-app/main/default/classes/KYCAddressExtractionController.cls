/**
 * Einstein-powered OCR + persistence controller for the KYC Details page,
 * Section 2 (Extracted Document Details).
 *
 *   Action                              | Purpose
 *   ----------------------------------- | -----------------------------------
 *   extractAndSaveAddressDocumentKyc    | Runs the DocumentExtractionPrompt
 *                                         template against the most recently
 *                                         uploaded address-proof file, parses
 *                                         the response, normalizes / merges,
 *                                         and persists to the active address
 *                                         Document_CheckList__c row.
 *
 * Inputs                                 | Notes
 * -------------------------------------- | ---------------------------------
 * recordId            Id                 | Application__c id (required)
 * applicantId         Id                 | When omitted, falls back to the
 *                                         | active Borrower applicant
 * documentType        String             | UI value — one of:
 *                                         |   Passport / Voter ID / Driving License
 * addressType         String             | Current / Permanent (default Current)
 * checklistRecordId   Id                 | Optional — when supplied skips the
 *                                         | "find existing row" search and writes
 *                                         | directly to this row
 * documentSide        String             | Front / Back / Full
 * addressProofFile    Map<String,Object> | { contentDocumentId, contentVersionId,
 *                                         |   fileName, files: [...] }
 *
 * Side stamp: ContentVersion.File_Side__c is stamped with the documentSide
 * so file-restore on page load can rebuild the Front / Back / Full slots.
 */
public with sharing class KYCAddressExtractionController implements Callable {

    private static final String ACTION_EXTRACT_AND_SAVE = 'extractAndSaveAddressDocumentKyc';

    private static final String DOC_TYPE_PASSPORT_UI         = 'Passport';
    private static final String DOC_TYPE_VOTER_ID_UI         = 'Voter ID';
    private static final String DOC_TYPE_DRIVING_LICENSE_UI  = 'Driving License';
    private static final String DOC_TYPE_VOTER_ID            = 'Voter Id';
    private static final String DOC_TYPE_DRIVING_LICENCE     = 'Driving Licence';

    private static final String ADDRESS_TYPE_CURRENT   = 'Current Residential Address';
    private static final String ADDRESS_TYPE_PERMANENT = 'Permanent Residential Address';

    private static final String SIDE_FRONT = 'Front';
    private static final String SIDE_BACK  = 'Back';
    private static final String SIDE_FULL  = 'Full';

    private static final String PROMPT_TEMPLATE_NAME = 'DocumentExtractionPrompt';

    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_EXTRACT_AND_SAVE.equalsIgnoreCase(action)) {
            return extractAndSaveAddressDocumentKycInternal(args);
        }
        return errorResponse('Unknown action: ' + action);
    }

    // =========================================================================
    // Main entry point
    // =========================================================================

    private Map<String, Object> extractAndSaveAddressDocumentKycInternal(Map<String, Object> args) {
        Id recordId           = parseId(args.get('recordId'));
        Id applicantId        = parseId(args.get('applicantId'));
        String uiDocumentType = toSafeString(args.get('documentType'));
        String addressType    = toSafeString(args.get('addressType'));
        Id checklistRecordId  = parseId(args.get('checklistRecordId'));
        String documentSide   = toSafeString(args.get('documentSide'));
        // Optional persona override from LWC; falls back to the applicant's own type.
        String applicantTypeArg = toSafeString(args.get('applicantType'));

        String effectiveAddressType = ADDRESS_TYPE_PERMANENT.equalsIgnoreCase(addressType)
            ? ADDRESS_TYPE_PERMANENT
            : ADDRESS_TYPE_CURRENT;

        Map<String, Object> filePayload = toStringObjectMap(args.get('addressProofFile'));
        String contentDocumentId = firstNonBlank(new List<String>{
            toSafeString(filePayload.get('contentDocumentId')),
            toSafeString(filePayload.get('documentId'))
        });
        String contentVersionId = firstNonBlank(new List<String>{
            toSafeString(filePayload.get('contentVersionId')),
            toSafeString(filePayload.get('versionId'))
        });
        String fileName = toSafeString(filePayload.get('fileName'));

        if (String.isBlank(contentDocumentId) || String.isBlank(contentVersionId) || String.isBlank(fileName)) {
            Map<String, Object> latestFile = extractLatestFileFromPayload(filePayload.get('files'));
            if (latestFile != null) {
                contentDocumentId = firstNonBlank(new List<String>{
                    contentDocumentId,
                    toSafeString(latestFile.get('contentDocumentId')),
                    toSafeString(latestFile.get('documentId'))
                });
                contentVersionId = firstNonBlank(new List<String>{
                    contentVersionId,
                    toSafeString(latestFile.get('contentVersionId')),
                    toSafeString(latestFile.get('versionId'))
                });
                fileName = firstNonBlank(new List<String>{
                    fileName,
                    toSafeString(latestFile.get('fileName')),
                    toSafeString(latestFile.get('name'))
                });
            }
        }

        if (recordId == null) {
            return errorResponse('recordId is required.');
        }
        if (String.isBlank(uiDocumentType)) {
            return errorResponse('Address document type is required.');
        }

        String checklistDocType = toChecklistDocumentType(uiDocumentType);
        if (String.isBlank(checklistDocType)) {
            return errorResponse('Unsupported document type for OCR: ' + uiDocumentType);
        }

        Applicant__c resolvedApplicant = resolveAndLockApplicant(recordId, applicantId);
        if (resolvedApplicant != null) {
            applicantId = resolvedApplicant.Id;
        }
        if (applicantId == null) {
            return errorResponse('Applicant not found for this application.');
        }
        String resolvedApplicantType = String.isNotBlank(applicantTypeArg)
            ? applicantTypeArg
            : (resolvedApplicant != null ? resolvedApplicant.Applicant_Type__c : null);

        // Resolve the missing half of the file pair (only one of CD/CV may be supplied).
        if (String.isBlank(contentDocumentId) && String.isNotBlank(contentVersionId)) {
            List<ContentVersion> versions = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
            contentDocumentId = versions.isEmpty() ? null : versions[0].ContentDocumentId;
        }
        if (String.isBlank(contentVersionId) && String.isNotBlank(contentDocumentId)) {
            List<ContentVersion> versions = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                  AND IsLatest = true
                LIMIT 1
            ];
            contentVersionId = versions.isEmpty() ? null : versions[0].Id;
        }
        if (String.isBlank(contentDocumentId)) {
            return errorResponse('Uploaded document is required.');
        }

        Savepoint sp;
        try {
            Map<String, Object> extractionResult = callExtractionPrompt(contentDocumentId);
            if (extractionResult == null || extractionResult.isEmpty()) {
                return errorResponse('Could not extract details from the uploaded document.');
            }

            Map<String, Object> normalized = normalizeExtractedDetails(extractionResult);

            String firstName = toSafeString(normalized.get('firstName'));
            String lastName  = toSafeString(normalized.get('lastName'));
            String fullName  = toSafeString(normalized.get('fullName'));
            if (String.isBlank(firstName) && String.isBlank(lastName) && String.isNotBlank(fullName)) {
                List<String> tokens = fullName.split('\\s+');
                if (tokens.size() == 1) {
                    firstName = tokens[0];
                } else if (tokens.size() == 2) {
                    lastName  = tokens[0];
                    firstName = tokens[1];
                } else if (tokens.size() > 2) {
                    lastName = tokens[0];
                    List<String> firstNameTokens = new List<String>();
                    for (Integer idx = 1; idx < tokens.size(); idx++) {
                        firstNameTokens.add(tokens[idx]);
                    }
                    firstName = String.join(firstNameTokens, ' ');
                }
            }
            if (String.isBlank(fullName)) {
                fullName = String.isBlank(lastName) ? firstName : (firstName + ' ' + lastName);
            }

            Date dob = GenericUtility.parseDateFlexible(toSafeString(normalized.get('dob')));
            Date doi = GenericUtility.parseDateFlexible(toSafeString(normalized.get('doi')));
            Date doe = GenericUtility.parseDateFlexible(toSafeString(normalized.get('doe')));

            String documentNumberRaw    = toSafeString(normalized.get('docNumber'));
            String maskedDocumentNumber = maskDocumentNumber(documentNumberRaw);

            String districtOrAddress3 = toSafeString(normalized.get('district'));
            if (String.isBlank(districtOrAddress3)) {
                districtOrAddress3 = toSafeString(normalized.get('address3'));
            }
            String address4     = toSafeString(normalized.get('address4'));
            String placeOfIssue = toSafeString(normalized.get('poi'));
            if (String.isBlank(address4) && String.isNotBlank(placeOfIssue)) {
                address4 = placeOfIssue;
            }

            String gender   = toSafeString(normalized.get('gender'));
            String address1 = toSafeString(normalized.get('address1'));
            String address2 = toSafeString(normalized.get('address2'));
            String pin      = toSafeString(normalized.get('pin'));
            String city     = toSafeString(normalized.get('city'));
            String state    = toSafeString(normalized.get('state'));

            // PinCode fallback for city / state when the document doesn't expose them.
            if (String.isNotBlank(pin) && (String.isBlank(city) || String.isBlank(state))) {
                Map<String, String> lookup = GenericUtility.getCityStateFromPinCode(pin);
                if (String.isBlank(city)  && lookup != null) city  = toSafeString(lookup.get('city'));
                if (String.isBlank(state) && lookup != null) state = toSafeString(lookup.get('state'));
            }

            // DML below — create savepoint only after the callout + parsing have succeeded.
            // The Applicant row is already locked (FOR UPDATE) from resolveAndLockApplicant
            // above, so no separate lock query needed here.
            sp = Database.setSavepoint();

            Document_CheckList__c doc = null;
            if (checklistRecordId != null) {
                List<Document_CheckList__c> targets = [
                    SELECT Id, Document_Type__c, Address_Type__c, Attached_File_Side__c, ContentVersionId__c,
                           Applicant_Type__c, Applicant_KYC__c, Applicant_Address__c,
                           First_Name__c, Last_Name__c, Gender__c, KYC_Date_of_Birth__c,
                           Applicant_KYC__r.Id, Applicant_KYC__r.Name, Applicant_KYC__r.Applicant__c,
                           Applicant_KYC__r.KYC_Type__c, Applicant_KYC__r.KYC_name__c,
                           Applicant_KYC__r.KYC_DOB__c, Applicant_KYC__r.KYC_Issuance_Date__c,
                           Applicant_KYC__r.KYC_Expiry_Date__c, Applicant_KYC__r.KYC_Place_of_Issue__c,
                           Applicant_KYC__r.KYC_No__c, Applicant_KYC__r.Masked_KYC_No__c,
                           Applicant_KYC__r.KYC_Address_Line_1__c, Applicant_KYC__r.KYC_Address_Line_2__c,
                           Applicant_KYC__r.KYC_Address_Line_3__c, Applicant_KYC__r.KYC_Address_Line_4__c,
                           Applicant_KYC__r.KYC_City__c, Applicant_KYC__r.KYC_State__c,
                           Applicant_KYC__r.KYC_Pin_Code__c, Applicant_KYC__r.KYC_District__c
                    FROM Document_CheckList__c
                    WHERE Id = :checklistRecordId
                      AND Applicant__c = :applicantId
                      AND Application__c = :recordId
                    LIMIT 1
                ];
                if (!targets.isEmpty()) {
                    doc = targets[0];
                }
            }
            if (doc == null) {
                List<Document_CheckList__c> existing = queryExistingAddressChecklist(
                    recordId, applicantId, effectiveAddressType
                );
                doc = pickPreferredChecklistRecord(existing, checklistDocType);
                if (doc == null) {
                    doc = new Document_CheckList__c();
                }
            }

            Boolean isExistingRecord     = (doc.Id != null);

            if (doc.Id == null) {
                doc.Applicant__c   = applicantId;
                doc.Application__c = recordId;
            }
            doc.Document_Type__c     = checklistDocType;
            doc.Address_Type__c      = effectiveAddressType;
            doc.Is_Active__c         = true;
            doc.ContentVersionId__c  = contentVersionId;
            doc.Name = KYCInfoController.buildChecklistName(resolvedApplicant, checklistDocType);

            // Persona stamp — auto-set from the applicant unless the row already has a value.
            if (String.isBlank(doc.Applicant_Type__c) && String.isNotBlank(resolvedApplicantType)) {
                doc.Applicant_Type__c = resolvedApplicantType;
            }

            // Attached_File_Side__c is a restricted single-select picklist
            // with three valid values: 'Full', 'Front', 'Back'. 
            if (SIDE_FRONT.equalsIgnoreCase(documentSide)) {
                doc.Attached_File_Side__c = SIDE_FRONT;
            } else if (SIDE_BACK.equalsIgnoreCase(documentSide)) {
                doc.Attached_File_Side__c = SIDE_BACK;
            } else if (String.isBlank(doc.Attached_File_Side__c)) {
                doc.Attached_File_Side__c = SIDE_FULL;
            }

            // Basic Details overlap — Gender / First / Last / DOB / PAN fields are
            // shared with the Basic Details screen and stay on the checklist row.
            // Non-blank-wins merge so a Back upload doesn't blank out values
            // captured from Front.
            if (!isExistingRecord || String.isNotBlank(firstName))            doc.First_Name__c        = firstName;
            if (!isExistingRecord || String.isNotBlank(lastName))             doc.Last_Name__c         = lastName;
            if (!isExistingRecord || dob != null)                             doc.KYC_Date_of_Birth__c = dob;
            if (!isExistingRecord || String.isNotBlank(gender))               doc.Gender__c            = gender.equalsIgnoreCase('m') ? 'Male' : (gender.equalsIgnoreCase('f') ? 'Female' : gender);

            // Applicant_KYC__c reference record — the immutable OCR snapshot.

            Applicant_KYC__c kyc;
            if (doc.Applicant_KYC__c != null && doc.Applicant_KYC__r != null) {
                kyc = doc.Applicant_KYC__r;
            } else {
                kyc = getOrCreateApplicantKyc(doc.Applicant_KYC__c, applicantId);
            }

            // OCR re-run after the user changed Address Document Type.
            String incomingKycType = toApplicantKycType(uiDocumentType);
            Boolean docTypeChanged = String.isNotBlank(incomingKycType)
                && String.isNotBlank(kyc.KYC_Type__c)
                && !incomingKycType.equalsIgnoreCase(kyc.KYC_Type__c);
            if (docTypeChanged) {
                resetApplicantKycExtractedFields(kyc);
            }

            // Non-blank wins (preserves Front-side data on Back-side re-upload).
            if (String.isNotBlank(fullName))             kyc.KYC_name__c            = fullName;
            if (dob != null)                             kyc.KYC_DOB__c             = dob;
            if (doi != null)                             kyc.KYC_Issuance_Date__c   = doi;
            if (doe != null)                             kyc.KYC_Expiry_Date__c     = doe;
            if (String.isNotBlank(placeOfIssue))         kyc.KYC_Place_of_Issue__c  = placeOfIssue;
            if (String.isNotBlank(address1))             kyc.KYC_Address_Line_1__c  = address1;
            if (String.isNotBlank(address2))             kyc.KYC_Address_Line_2__c  = address2;
            if (String.isNotBlank(districtOrAddress3))   kyc.KYC_Address_Line_3__c  = districtOrAddress3;
            if (String.isNotBlank(address4))             kyc.KYC_Address_Line_4__c  = address4;
            if (String.isNotBlank(pin))                  kyc.KYC_Pin_Code__c        = pin;
            if (String.isNotBlank(city))                 kyc.KYC_City__c            = city;
            if (String.isNotBlank(state))                kyc.KYC_State__c           = state;
            if (String.isNotBlank(districtOrAddress3))   kyc.KYC_District__c        = districtOrAddress3;
            if (String.isNotBlank(documentNumberRaw))    kyc.KYC_No__c              = documentNumberRaw;
            if (String.isNotBlank(maskedDocumentNumber)) kyc.Masked_KYC_No__c       = maskedDocumentNumber;
            // KYC_Type__c is restricted picklist (Aadhar / Passport / Voter Id / Driving License).
            // Always overwrite when an incoming value is mapped — it pairs with the
            // docTypeChanged reset above so the snapshot stays consistent.
            if (String.isNotBlank(incomingKycType))      kyc.KYC_Type__c            = incomingKycType;
            // Name (Text 80) — full name preferred, falls back to document type label.
            // Refresh on doc-type change so "Passport KYC" doesn't linger after switching to Voter ID.
            if (String.isBlank(kyc.Name) || docTypeChanged) {
                String kycName = String.isNotBlank(fullName)
                    ? fullName
                    : (String.isNotBlank(uiDocumentType) ? uiDocumentType + ' KYC' : 'Applicant KYC');
                kyc.Name = kycName.length() > 80 ? kycName.substring(0, 80) : kycName;
            }

            upsert kyc;

            // Link the checklist to the KYC reference record. Idempotent stamp.
            if (doc.Applicant_KYC__c == null) {
                doc.Applicant_KYC__c = kyc.Id;
            }

            upsert doc;

            ensureContentDocumentLink(doc.Id, contentDocumentId);

            // Stamp side onto ContentVersion so file-restore can rebuild the slots.
            if (String.isNotBlank(contentVersionId)) {
                String sideToStamp = String.isNotBlank(documentSide) ? documentSide : SIDE_FULL;
                try {
                    update new ContentVersion(Id = contentVersionId, File_Side__c = sideToStamp);
                } catch (Exception cvEx) {
                    System.debug('WARN [KYCAddressExtractionController] ContentVersion side stamp failed: ' + cvEx.getMessage());
                }
            }

            // Sync extracted name to the Applicant so other pages see consistent values.
            if (String.isNotBlank(firstName) || String.isNotBlank(lastName)) {
                syncNameToApplicant(applicantId, firstName, lastName);
            }

            return new Map<String, Object>{
                'isSuccess'             => true,
                'message'               => 'Document details extracted and saved successfully.',
                'documentType'          => uiDocumentType,
                'documentChecklistType' => checklistDocType,
                'documentChecklistId'   => doc.Id,
                'applicantKycId'        => kyc.Id,
                'addressType'           => effectiveAddressType,
                'documentSide'          => String.isNotBlank(documentSide) ? documentSide : SIDE_FULL,
                'applicantType'         => doc.Applicant_Type__c,
                // Response reflects the PERSISTED row state 
                'extractedDetails'      => buildExtractedDetailsPayload(doc, kyc, maskedDocumentNumber)
            };
        } catch (Exception e) {
            if (sp != null) {
                Database.rollback(sp);
            }
            return errorResponse('Failed to extract and save document details: ' + e.getMessage());
        }
    }

    // =========================================================================
    // Einstein prompt template invocation
    // =========================================================================

    private static Map<String, Object> callExtractionPrompt(String contentDocumentId) {
        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        ConnectApi.WrappedValue fileVal = new ConnectApi.WrappedValue();
        fileVal.value = new Map<String, String>{ 'id' => contentDocumentId };
        inputParams.put('Input:file', fileVal);

        String responseText = callPromptTemplate(PROMPT_TEMPLATE_NAME, inputParams);
        if (String.isBlank(responseText)) {
            return null;
        }
        String cleaned = sanitizePromptJson(responseText);
        Object resultObject = JSON.deserializeUntyped(cleaned);
        if (resultObject instanceof Map<String, Object>) {
            return (Map<String, Object>) resultObject;
        }
        return null;
    }

    private static String callPromptTemplate(String templateName, Map<String, ConnectApi.WrappedValue> inputs) {
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.isPreview = false;
            input.inputParams = inputs;
            input.additionalConfig.applicationName = 'PromptBuilderPreview';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, input);
            ConnectApi.EinsteinLLMGenerationItemOutput response = output.generations[0];
            return response != null ? response.text : null;
        } catch (Exception e) {
            System.debug('ERROR [KYCAddressExtractionController.callPromptTemplate]: ' + e.getMessage());
            return null;
        }
    }

    private static String sanitizePromptJson(String input) {
        if (String.isBlank(input)) return input;
        String s = input.replaceAll('[\\u00A0\\u2007\\u202F\\uFEFF]', '').trim();
        if (s.startsWith('```')) {
            Integer objStart = s.indexOf('{');
            Integer objEnd   = s.lastIndexOf('}');
            Integer arrStart = s.indexOf('[');
            Integer arrEnd   = s.lastIndexOf(']');
            if (objStart >= 0 && objEnd > objStart) {
                if (arrStart < 0 || objStart < arrStart) {
                    s = s.substring(objStart, objEnd + 1).trim();
                } else {
                    s = s.substring(arrStart, arrEnd + 1).trim();
                }
            } else if (arrStart >= 0 && arrEnd > arrStart) {
                s = s.substring(arrStart, arrEnd + 1).trim();
            }
        }
        return s;
    }

    // =========================================================================
    // Field normalization
    // =========================================================================

    /**
     * Folds the raw Einstein response into a flat, stable key shape regardless
     * of which document type was uploaded. Picks the first non-blank value
     * from each candidate-key list. surname/given_name take priority over
     * last_name/first_name because Einstein sometimes emits both for Indian
     * passports and the positional keys can be wrong.
     */
    private static Map<String, Object> normalizeExtractedDetails(Map<String, Object> result) {
        Map<String, Object> root = result != null ? result : new Map<String, Object>();
        Map<String, Object> docData = root.get('document_data') instanceof Map<String, Object>
            ? (Map<String, Object>) root.get('document_data')
            : root;

        Map<String, Object> normalized = new Map<String, Object>();
        normalized.put('fullName',  firstString(docData, new List<String>{ 'full_name', 'name', 'applicant_name' }));
        normalized.put('firstName', firstString(docData, new List<String>{ 'given_name', 'given_names', 'first_name' }));
        normalized.put('lastName',  firstString(docData, new List<String>{ 'surname', 'last_name' }));
        normalized.put('dob',       firstString(docData, new List<String>{ 'date_of_birth', 'dob', 'birth_date' }));
        normalized.put('gender',    firstString(docData, new List<String>{ 'gender', 'sex' }));
        normalized.put('doi',       firstString(docData, new List<String>{ 'date_of_issue', 'doi', 'issue_date', 'issued_date', 'date_issued' }));
        normalized.put('doe',       firstString(docData, new List<String>{
            'date_of_expiry', 'doe', 'expiry_date', 'expiration_date', 'date_of_expiration',
            'valid_until', 'valid_upto', 'valid_till', 'valid_thru', 'valid_to',
            'validity', 'date_of_validity', 'validity_date',
            // Driving Licence non-transport / transport validity variants
            'validity_nt', 'valid_upto_nt', 'valid_till_nt', 'non_transport_validity',
            'validity_non_transport', 'date_of_validity_nt', 'expiry'
        }));
        normalized.put('poi',       firstString(docData, new List<String>{ 'place_of_issue', 'poi', 'issuing_authority' }));
        normalized.put('address1',  firstString(docData, new List<String>{ 'address_line_1', 'address1', 'address' }));
        normalized.put('address2',  firstString(docData, new List<String>{ 'address_line_2', 'address2' }));
        normalized.put('address3',  firstString(docData, new List<String>{ 'address_line_3', 'address3', 'district' }));
        normalized.put('address4',  firstString(docData, new List<String>{ 'address_line_4', 'address4' }));
        normalized.put('city',      firstString(docData, new List<String>{ 'city', 'town', 'municipality', 'taluka', 'tehsil' }));
        normalized.put('state',     firstString(docData, new List<String>{ 'state', 'province' }));
        normalized.put('pin',       firstString(docData, new List<String>{ 'pin_code', 'pincode', 'postal_code', 'zip_code', 'pin' }));
        normalized.put('docNumber', firstString(docData, new List<String>{
            'document_number', 'document_no', 'id_number',
            'passport_number', 'voter_id_number',
            'driving_licence_number', 'driving_license_number'
        }));
        return normalized;
    }

    private static String firstString(Map<String, Object> src, List<String> keys) {
        if (src == null || keys == null) return '';
        for (String key : keys) {
            if (!src.containsKey(key)) continue;
            String val = toSafeString(src.get(key));
            if (String.isNotBlank(val)) return val;
        }
        return '';
    }

    /**
     * Builds the extracted-details payload from the persisted DB row state
     * (post-merge), NOT from the current upload's local extraction variables.
     */
    private static Map<String, Object> buildExtractedDetailsPayload(
        Document_CheckList__c doc, Applicant_KYC__c kyc, String maskedDocumentNumber
    ) {
        Map<String, Object> out = new Map<String, Object>{
            'firstName' => doc != null ? doc.First_Name__c : null,
            'lastName'  => doc != null ? doc.Last_Name__c  : null,
            'gender'    => doc != null ? doc.Gender__c     : null,
            'dob'       => (doc != null && doc.KYC_Date_of_Birth__c != null)
                            ? String.valueOf(doc.KYC_Date_of_Birth__c) : null,
            'fullName'  => kyc != null ? kyc.KYC_name__c : null,
            'doi'       => (kyc != null && kyc.KYC_Issuance_Date__c != null)
                            ? String.valueOf(kyc.KYC_Issuance_Date__c) : null,
            'doe'       => (kyc != null && kyc.KYC_Expiry_Date__c != null)
                            ? String.valueOf(kyc.KYC_Expiry_Date__c) : null,
            'poi'       => kyc != null ? kyc.KYC_Place_of_Issue__c : null,
            'address1'  => kyc != null ? kyc.KYC_Address_Line_1__c : null,
            'address2'  => kyc != null ? kyc.KYC_Address_Line_2__c : null,
            'address3'  => kyc != null ? kyc.KYC_Address_Line_3__c : null,
            'address4'  => kyc != null ? kyc.KYC_Address_Line_4__c : null,
            'pin'       => kyc != null ? kyc.KYC_Pin_Code__c       : null,
            'city'      => kyc != null ? kyc.KYC_City__c           : null,
            'state'     => kyc != null ? kyc.KYC_State__c          : null,
            'docNumber' => String.isNotBlank(maskedDocumentNumber)
                            ? maskedDocumentNumber
                            : (kyc != null ? kyc.Masked_KYC_No__c : null)
        };
        return out;
    }

    public static String maskDocumentNumber(String documentNumber) {
        String raw = toSafeString(documentNumber).replaceAll('\\s', '');
        if (String.isBlank(raw)) return '';
        Integer keep      = Math.min(4, raw.length());
        Integer maskedLen = Math.max(0, raw.length() - keep);
        String maskedPrefix = '';
        for (Integer i = 0; i < maskedLen; i++) {
            maskedPrefix += '*';
        }
        return maskedPrefix + raw.right(keep);
    }

    // =========================================================================
    // Persistence helpers
    // =========================================================================

    /**
     * Guarantees a ContentDocumentLink between the file and the checklist row.
     * Idempotent; does not touch links to other entities such as the
     * Application or the User's personal library.
     */
    private static void ensureContentDocumentLink(Id checklistId, String contentDocumentId) {
        if (checklistId == null || String.isBlank(contentDocumentId)) return;
        List<ContentDocumentLink> existing = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
              AND LinkedEntityId    = :checklistId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return;
        }
        insert new ContentDocumentLink(
            LinkedEntityId    = checklistId,
            ContentDocumentId = contentDocumentId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
    }

    /**
     * queryApplicantById + queryBorrowerApplicant + lockApplicantForChecklist.
     */
    private static Applicant__c resolveAndLockApplicant(Id recordId, Id applicantId) {
        if (recordId == null && applicantId == null) {
            return null;
        }

        List<Applicant__c> rows = [
            SELECT Id, Applicant_Type__c, Customer_First_Name__c, Customer_Last_Name__c
            FROM Applicant__c
            WHERE In_Active_Applicant__c = false
              AND (Id = :applicantId
                   OR (Application__c = :recordId AND Applicant_Type__c = :APPLICANT_TYPE_BORROWER))
            LIMIT 5
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            return null;
        }
        Applicant__c byId = null;
        Applicant__c borrower = null;
        for (Applicant__c a : rows) {
            if (applicantId != null && a.Id == applicantId) {
                byId = a;
            } else if (APPLICANT_TYPE_BORROWER.equalsIgnoreCase(a.Applicant_Type__c)) {
                borrower = a;
            }
        }
        return byId != null ? byId : borrower;
    }

    /**
     * Blanks out all OCR-derived fields on the Applicant_KYC__c snapshot.
     * Invoked when the user changes Address Document Type (e.g. switched from Passport → Voter ID).
     */
    private static void resetApplicantKycExtractedFields(Applicant_KYC__c kyc) {
        if (kyc == null) return;
        kyc.KYC_name__c            = null;
        kyc.KYC_DOB__c             = null;
        kyc.KYC_Issuance_Date__c   = null;
        kyc.KYC_Expiry_Date__c     = null;
        kyc.KYC_Place_of_Issue__c  = null;
        kyc.KYC_No__c              = null;
        kyc.Masked_KYC_No__c       = null;
        kyc.KYC_Address_Line_1__c  = null;
        kyc.KYC_Address_Line_2__c  = null;
        kyc.KYC_Address_Line_3__c  = null;
        kyc.KYC_Address_Line_4__c  = null;
        kyc.KYC_City__c            = null;
        kyc.KYC_State__c           = null;
        kyc.KYC_Pin_Code__c        = null;
        kyc.KYC_District__c        = null;
    }

    private static List<Document_CheckList__c> queryExistingAddressChecklist(Id recordId, Id applicantId, String addressType) {
        return [
            SELECT Id, Document_Type__c, Address_Type__c, Attached_File_Side__c, ContentVersionId__c,
                   Applicant_Type__c, Applicant_KYC__c, Applicant_Address__c,
                   First_Name__c, Last_Name__c, Gender__c, KYC_Date_of_Birth__c
            FROM Document_CheckList__c
            WHERE Applicant__c   = :applicantId
              AND Application__c = :recordId
              AND Is_Active__c   = true
              AND Address_Type__c = :addressType
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC
            LIMIT 10
        ];
    }

    /**
     * Returns the Applicant_KYC__c row identified by existingKycId, or a new
     * in-memory row stamped with the master-detail key when no id is given.
     */
    private static Applicant_KYC__c getOrCreateApplicantKyc(Id existingKycId, Id applicantId) {
        if (existingKycId != null) {
            List<Applicant_KYC__c> existing = [
                SELECT Id, Name, Applicant__c, KYC_Type__c,
                       KYC_name__c, KYC_DOB__c, KYC_Issuance_Date__c, KYC_Expiry_Date__c,
                       KYC_Place_of_Issue__c, KYC_No__c, Masked_KYC_No__c,
                       KYC_Address_Line_1__c, KYC_Address_Line_2__c, KYC_Address_Line_3__c, KYC_Address_Line_4__c,
                       KYC_City__c, KYC_State__c, KYC_Pin_Code__c, KYC_District__c
                FROM Applicant_KYC__c
                WHERE Id = :existingKycId
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0];
            }
        }
        return new Applicant_KYC__c(Applicant__c = applicantId);
    }

    /**
     * Maps the UI document type label (Passport / Voter ID / Driving License /
     * Aadhaar Card) to the Applicant_KYC__c.KYC_Type__c restricted picklist
     * values (Aadhar / Passport / Voter Id / Driving License).
     */
    private static String toApplicantKycType(String uiDocumentType) {
        if (String.isBlank(uiDocumentType)) return null;
        String t = uiDocumentType.trim();
        if (DOC_TYPE_PASSPORT_UI.equalsIgnoreCase(t))         return 'Passport';
        if (DOC_TYPE_VOTER_ID_UI.equalsIgnoreCase(t))         return 'Voter Id';
        if (DOC_TYPE_DRIVING_LICENSE_UI.equalsIgnoreCase(t))  return 'Driving License';
        if ('Aadhaar Card'.equalsIgnoreCase(t))               return 'Aadhar';
        return null;
    }

    private static Document_CheckList__c pickPreferredChecklistRecord(List<Document_CheckList__c> records, String checklistDocType) {
        if (records == null || records.isEmpty()) return null;
        for (Document_CheckList__c row : records) {
            if (String.isBlank(row.Document_Type__c)) {
                return row;
            }
        }
        for (Document_CheckList__c row : records) {
            if (checklistDocType.equalsIgnoreCase(row.Document_Type__c)) {
                return row;
            }
        }
        return records[0];
    }

    /**
     * Maps a UI document-type label to the value persisted on the checklist.
     * Normalizes 'Voter ID' → 'Voter Id' and 'Driving License' →
     * 'Driving Licence' to match the picklist values on Document_CheckList__c.
     */
    private static String toChecklistDocumentType(String uiDocumentType) {
        if (DOC_TYPE_PASSPORT_UI.equalsIgnoreCase(uiDocumentType))         return DOC_TYPE_PASSPORT_UI;
        if (DOC_TYPE_VOTER_ID_UI.equalsIgnoreCase(uiDocumentType))         return DOC_TYPE_VOTER_ID;
        if (DOC_TYPE_DRIVING_LICENSE_UI.equalsIgnoreCase(uiDocumentType))  return DOC_TYPE_DRIVING_LICENCE;
        return null;
    }

    /**
     * Copies extracted first/last name onto the Applicant so downstream pages
     * see consistent values. Silently no-ops when the fields are not
     * updateable for the current user.
     */
    private static void syncNameToApplicant(Id applicantId, String firstName, String lastName) {
        if (applicantId == null) return;
        try {
            Applicant__c app = new Applicant__c(Id = applicantId);
            Boolean hasUpdate = false;

            if (String.isNotBlank(firstName)
                && Schema.SObjectType.Applicant__c.fields.Customer_First_Name__c.isUpdateable()) {
                app.Customer_First_Name__c = firstName.trim();
                hasUpdate = true;
            }
            if (String.isNotBlank(lastName)
                && Schema.SObjectType.Applicant__c.fields.Customer_Last_Name__c.isUpdateable()) {
                app.Customer_Last_Name__c = lastName.trim();
                hasUpdate = true;
            }
            if (hasUpdate) {
                update app;
            }
        } catch (Exception e) {
            System.debug('WARN [KYCAddressExtractionController.syncNameToApplicant]: ' + e.getMessage());
        }
    }

    // =========================================================================
    // Coercion helpers
    // =========================================================================

    private static Map<String, Object> errorResponse(String message) {
        return new Map<String, Object>{ 'isSuccess' => false, 'message' => message };
    }

    private static Id parseId(Object raw) {
        if (raw == null) return null;
        String s = String.valueOf(raw).trim();
        if (String.isBlank(s)) return null;
        try {
            return (Id) s;
        } catch (Exception ex) {
            return null;
        }
    }

    private static String toSafeString(Object value) {
        return value == null ? '' : String.valueOf(value).trim();
    }

    private static String firstNonBlank(List<String> values) {
        if (values == null) return '';
        for (String value : values) {
            if (String.isNotBlank(value)) return value;
        }
        return '';
    }

    private static Map<String, Object> toStringObjectMap(Object value) {
        Map<String, Object> out = new Map<String, Object>();
        if (value == null) return out;
        if (value instanceof Map<String, Object>) {
            return (Map<String, Object>) value;
        }
        if (value instanceof Map<Object, Object>) {
            Map<Object, Object> src = (Map<Object, Object>) value;
            for (Object k : src.keySet()) {
                out.put(String.valueOf(k), src.get(k));
            }
            return out;
        }
        if (value instanceof String) {
            String s = String.valueOf(value);
            if (String.isNotBlank(s) && s.startsWith('{')) {
                Object parsed = JSON.deserializeUntyped(s);
                if (parsed instanceof Map<String, Object>) {
                    return (Map<String, Object>) parsed;
                }
                if (parsed instanceof Map<Object, Object>) {
                    Map<Object, Object> src2 = (Map<Object, Object>) parsed;
                    for (Object k2 : src2.keySet()) {
                        out.put(String.valueOf(k2), src2.get(k2));
                    }
                    return out;
                }
            }
        }
        return out;
    }

    private static Map<String, Object> extractLatestFileFromPayload(Object filesObj) {
        if (filesObj == null) return null;
        List<Object> files = new List<Object>();
        if (filesObj instanceof List<Object>) {
            files = (List<Object>) filesObj;
        } else if (filesObj instanceof List<String>) {
            List<String> arr = (List<String>) filesObj;
            for (String item : arr) files.add(item);
        }
        if (files.isEmpty()) return null;
        Object last = files[files.size() - 1];
        Map<String, Object> lastMap = toStringObjectMap(last);
        return lastMap.isEmpty() ? null : lastMap;
    }
}