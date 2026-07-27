public with sharing class documentVerificationController {

    private static final String DOC_TYPE_PAN = 'PAN';

    @TestVisible
    private static String testPromptResponseOverride;

    @AuraEnabled
    public static Applicant__c getApplicant(Id applicantId) {
        return [SELECT Id, PAN_Number__c, Date_of_Birth__c, Customer_First_Name__c, Customer_Last_Name__c FROM Applicant__c WHERE Id = :applicantId LIMIT 1];
    }

    /**
     * Einstein OCR for the uploaded PAN card.
     * Side effects: encrypts the extracted PAN and persists it to Applicant__c.PAN_Number__c plus
     * the active Document_CheckList__c row.
     * Returns the cleartext PAN and ISO-normalized DOB so the LWC can render them; the cleartext
     * is never written back to storage from the LWC.
     */
    @AuraEnabled
    public static Map<String, Object> ocrPANCard(Id applicantId, String contentDocumentId, String contentVersionId) {
        String fileId = contentDocumentId;
        if (String.isBlank(fileId) && String.isNotBlank(contentVersionId)) {
            List<ContentVersion> cvs = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1];
            fileId = cvs.isEmpty() ? null : cvs[0].ContentDocumentId;
        }
        if (String.isBlank(fileId)) {
            return null;
        }
        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        ConnectApi.WrappedValue fileVal = new ConnectApi.WrappedValue();
        fileVal.value = new Map<String, String>{ 'id' => fileId };
        inputParams.put('Input:file', fileVal);

        String responseText = String.isNotBlank(testPromptResponseOverride)
            ? testPromptResponseOverride
            : callPromptTemplate('DocumentExtractionPrompt', inputParams);
        if (String.isBlank(responseText)) {
            return null;
        }
        String cleaned = sanitizePromptJson(responseText);
        System.debug('111111 - '+cleaned);

        Map<String, Object> parsed;
        try {
            Object resultObject = JSON.deserializeUntyped(cleaned);
            if (!(resultObject instanceof Map<String, Object>)) {
                return null;
            }
            parsed = parseDocumentExtractionResult((Map<String, Object>) resultObject);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'documentVerificationController.ocrPANCard parse error: ' + ex.getMessage());
            return null;
        }

        if (parsed == null) {
            return null;
        }

        String extractedPan = parsed.get('panCardNumber') != null
            ? String.valueOf(parsed.get('panCardNumber')).trim().toUpperCase() : null;
        if (String.isNotBlank(extractedPan) && applicantId != null) {
            persistEncryptedPan(applicantId, contentVersionId, extractedPan);
            parsed.put('panCardNumber', extractedPan);
        }

        Object rawDob = parsed.get('date_of_birth');
        if (rawDob != null) {
            String normalized = normalizeDobToIso(String.valueOf(rawDob));
            parsed.put('date_of_birth', normalized);
        }

        Object rawIncorporation = parsed.get('date_of_incorporation');
        if (rawIncorporation != null) {
            String normalized = normalizeDobToIso(String.valueOf(rawIncorporation));
            parsed.put('date_of_incorporation', normalized);
        }

        return parsed;
    }

    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokePANOCRAPI(String applicantId, String panCardNumber) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync('PAN OCR API', applicantId, 'Applicant__c');
        return response;
    }

    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeValidatePANAPI(String applicantId, String panCardNumber) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync('Validate PAN API', applicantId, 'Applicant__c');
        return response;
    }

    /** Encrypts the PAN and writes it to Applicant__c.PAN_Number__c plus the active PAN Document_CheckList row.
     *  Creates a new row when none exists so subsequent saves treat the PAN as already persisted. */
    private static void persistEncryptedPan(Id applicantId, String contentVersionId, String panCleartext) {
        String encrypted = encryptPan(panCleartext);
        try {
            Applicant__c applicant = [
                SELECT Id, Application__c, PAN_Number__c
                FROM Applicant__c
                WHERE Id = :applicantId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            applicant.PAN_Number__c = encrypted;
            update applicant;

            List<Document_CheckList__c> existing = [
                SELECT Id, ContentVersionId__c, Is_Active__c, PAN_No__c
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicantId AND Document_Type__c = :DOC_TYPE_PAN
                WITH SECURITY_ENFORCED
                ORDER BY Is_Active__c DESC, LastModifiedDate DESC LIMIT 1
            ];
            Document_CheckList__c row;
            if (existing.isEmpty()) {
                row = new Document_CheckList__c(
                    Applicant__c = applicantId,
                    Application__c = applicant.Application__c,
                    Document_Type__c = DOC_TYPE_PAN
                );
            } else {
                row = existing[0];
            }
            row.PAN_No__c = encrypted;
            row.Is_Active__c = true;
            if (String.isNotBlank(contentVersionId)) {
                row.ContentVersionId__c = contentVersionId;
            }
            upsert row;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'documentVerificationController.persistEncryptedPan write failed: ' + e.getMessage());
            throw new AuraHandledException('Unable to persist PAN: ' + e.getMessage());
        }
    }

    private static String encryptPan(String cleartext) {
        try {
            return IntegrationUtility.getEncryptedRequest(cleartext, 'Keys');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'documentVerificationController.encryptPan: ' + e.getMessage());
            throw new AuraHandledException('Unable to encrypt PAN: ' + e.getMessage());
        }
    }

    /** Manual re-verify entry: encrypts the user-edited PAN, persists it, then lets the LWC
     *  re-run textMatch + verify against the freshly persisted value. Resets the verified flag
     *  because the cipher just changed. */
    @AuraEnabled
    public static void savePANForReVerify(Id applicantId, String panCardNumber) {
        if (applicantId == null || String.isBlank(panCardNumber)) {
            throw new AuraHandledException('applicantId and panCardNumber are required');
        }
        String normalised = panCardNumber.trim().toUpperCase();
        persistEncryptedPan(applicantId, null, normalised);
        setPanVerifiedFlag(applicantId, false);
    }

    /** Flips Applicant__c.PAN_Number_Verified__c so the UI status survives a page reload. */
    @AuraEnabled
    public static void markPanVerified(Id applicantId, Boolean verified) {
        if (applicantId == null) return;
        setPanVerifiedFlag(applicantId, verified == true);
        if (verified == true) {
            KYCInfoController.relabelVerifiedChecklist(applicantId, 'PAN');
        }
    }

    private static void setPanVerifiedFlag(Id applicantId, Boolean verified) {
        try {
            Applicant__c applicant = new Applicant__c(Id = applicantId, PAN_Number_Verified__c = verified);
            update applicant;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'documentVerificationController.setPanVerifiedFlag: ' + e.getMessage());
        }
    }

    /*@AuraEnabled
    public static boolean textMatchPANCard(Id applicantId) {
        for(integer i = 0; i < 100000; i++) {
            // simulated latency placeholder until the live text-match callout is wired
        }
        return true;
    }*/

    @AuraEnabled
    public static boolean verifyPANCard(Id applicantId) {
        for(integer i = 0; i < 100000; i++) {
            // simulated latency placeholder until the live verification callout is wired
        }
        return true;
    }
    @AuraEnabled
    public static void verifyForm60(String form60Number) {
        // Implement the logic to verify the Form 60
    }

    @AuraEnabled
    public static Boolean verifyEmail(String email) {
        return true;
    }


    @TestVisible
    private static String sanitizePromptJson(String input) {
        if (String.isBlank(input)) return input;
        // Strip invisible unicode characters that cause JSON parser errors:
        // NBSP \u00A0, FIGURE SPACE \u2007, NARROW NBSP \u202F, BOM \uFEFF
        String s = input.replaceAll('[\\u00A0\\u2007\\u202F\\uFEFF]', '').trim();
        if (s.startsWith('```')) {
            Integer objStart = s.indexOf('{');
            Integer objEnd = s.lastIndexOf('}');
            Integer arrStart = s.indexOf('[');
            Integer arrEnd = s.lastIndexOf(']');
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

    @TestVisible
    private static Map<String, Object> parseDocumentExtractionResult(Map<String, Object> result) {
        Map<String, Object> documentExtractionResult = new Map<String, Object>();
        documentExtractionResult.put('document_type', result.get('document_type'));
        documentExtractionResult.put('classification', result.get('classification'));
        documentExtractionResult.put('confidence', result.get('confidence'));
        documentExtractionResult.put('metadata', result.get('metadata'));

        Object documentDataObj = result.get('document_data');
        if (documentDataObj instanceof Map<String, Object>) {
            Map<String, Object> documentData = (Map<String, Object>) documentDataObj;
            documentExtractionResult.put('full_name', documentData.get('full_name'));
            documentExtractionResult.put('father_name', documentData.get('father_name'));
            documentExtractionResult.put('panCardNumber', documentData.get('document_number'));
            documentExtractionResult.put('date_of_birth', documentData.get('date_of_birth'));
            documentExtractionResult.put('date_of_incorporation', documentData.get('date_of_incorporation'));
            documentExtractionResult.put('issuing_authority', documentData.get('issuing_authority'));
        }
        return documentExtractionResult;
    }

      /** Converts any DD/MM/YYYY, DD-MM-YYYY, '12 January 1990', etc. into ISO YYYY-MM-DD so the LWC date input accepts it. */
    @TestVisible
    private static String normalizeDobToIso(String raw) {
        if (String.isBlank(raw)) return null;
        try {
            Date parsed = GenericUtility.parseEinsteinDateOfBirth(raw);
            return parsed == null ? null : String.valueOf(parsed);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'documentVerificationController.normalizeDobToIso failed for "' + raw + '": ' + e.getMessage());
            return null;
        }
    }

    private static String callPromptTemplate(String templateName,  Map<String, ConnectApi.WrappedValue> inputs) {
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput executeTemplateInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            executeTemplateInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            executeTemplateInput.isPreview = false;
            executeTemplateInput.inputParams = inputs;
            executeTemplateInput.additionalConfig.applicationName = 'PromptBuilderPreview';


            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    templateName,
                    executeTemplateInput
                );
            ConnectApi.EinsteinLLMGenerationItemOutput response = generationsOutput.generations[0];
            if (response != null) {
                return response.text;
            }
        } catch (Exception e) {
            // null lets caller fall back gracefully
        }
        return null;
    }
    @AuraEnabled
    public static Boolean verifyMobile(String mobile) {
        return true;
    }
}