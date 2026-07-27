/**
 * @description Controller for AdditionalDocuments LWC.
 *              Document uploads use Document_CheckList__c (init + link pattern).
 */
public with sharing class AdditionalDocumentsController {

    private static final String STAGE_ADDITIONAL_DOCUMENTS = 'Additional Documents';

    public class PickOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PickOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class SectionField {
        @AuraEnabled public String api;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean required;
        @AuraEnabled public String value;
        @AuraEnabled public List<PickOption> options;
        @AuraEnabled public Boolean typeIsPicklist;
        @AuraEnabled public Boolean isRadioGroup;
        @AuraEnabled public Boolean isCVOVerificationField;
        @AuraEnabled public Boolean isFieldDisabled;
        @AuraEnabled public Boolean isBankLookup;
    }

    public class Section {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String docType;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean conditional;
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public Boolean hasFile;
        @AuraEnabled public String documentId;
        @AuraEnabled public String documentChecklistId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String fileName;
        @AuraEnabled public Boolean isPaymentReceipt;
        @AuraEnabled public List<SectionField> fields;
        @AuraEnabled public String status;
        @AuraEnabled public String borrowerType;
        @AuraEnabled public String fileType;
        @AuraEnabled public Boolean isAlwaysVisible;
        @AuraEnabled public Boolean userSelectable;
        @AuraEnabled public Boolean userSelected;
        @AuraEnabled public Boolean isSecurityMandateSection;
        @AuraEnabled public Boolean isCAM;
        @AuraEnabled public Boolean isReadOnly;
        @AuraEnabled public String documentVerified;
        @AuraEnabled public String remarks;
    }

    public class SecurityMandateRow {
        @AuraEnabled public String documentChecklistId;
        @AuraEnabled public String chequeNumber;
        @AuraEnabled public String bankName;
        @AuraEnabled public String micrCode;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileType;
        @AuraEnabled public Boolean isUploaded;
        @AuraEnabled public String documentVerified;
        @AuraEnabled public String remarks;
    }

    public class ConfigResponse {
        @AuraEnabled public List<Section> sections;
        @AuraEnabled public List<SecurityMandateRow> securityMandateRows;
        @AuraEnabled public String applicationId;
        @AuraEnabled public String applicantId;
        @AuraEnabled public String productType;
        @AuraEnabled public String vehicleType;
        @AuraEnabled public String camRecId;
        @AuraEnabled public String repaymentId;
        @AuraEnabled public String loanAgreementId;
        @AuraEnabled public Boolean isReadOnly;
    }

    public class SaveResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_UPLOADED = 'Uploaded';
    private static final String DOCUMENT_TYPE_CANCELLED_CHEQUE = 'Cancelled Cheque';
    private static final String DOCUMENT_CATEGORY_CHEQUES_SECURITY = 'Additional Documents - Cheques & Security';
    private static final String LEGACY_DOCUMENT_TYPE_SECURITY_MANDATE = 'Security Mandate';

    /** Document_CheckList__c field API names persisted per upload section. */
    private static final Set<String> CHECKLIST_FIELD_APIS = new Set<String>{
        'Bank_Name__c',
        'Account_Number__c',
        'RTO_Verified__c',
        'DPN_Reference_Number__c',
        'Cheque_Number__c',
        'MICR_Code__c',
        'Document_Verified__c',
        'Remarks__c'
    };

    private static final List<String> BORROWER_BANK_OPTIONS = new List<String>{
        'STATE BANK OF INDIA',
        'BANK OF BARODA',
        'BANK OF INDIA',
        'BANK OF MAHARASHTRA',
        'CANARA BANK',
        'CENTRAL BANK OF INDIA',
        'INDIAN BANK',
        'INDIAN OVERSEAS BANK',
        'PUNJAB AND SIND BANK',
        'PUNJAB NATIONAL BANK',
        'UNION BANK OF INDIA'
    };

    /**
     * @description Returns applicable document sections and resolves application/applicant context.
     */
    @AuraEnabled(cacheable=false)
    public static ConfigResponse getApplicableSections(
        Id recordId,
        Id applicantId,
        String screenType
    ) {
        ConfigResponse response = new ConfigResponse();
        response.productType = 'TW';
        response.vehicleType = 'Used';
        response.camRecId = '';
        response.repaymentId = '';
        response.loanAgreementId = '';
        response.isReadOnly = false;
        response.sections = buildSampleSections();
        response.securityMandateRows = new List<SecurityMandateRow>();

        ApplicantContext ctx = resolveApplicantContext(recordId, applicantId);
        if (ctx != null) {
            response.applicationId = ctx.applicationId;
            response.applicantId = ctx.applicantId;
            enrichSectionsWithDocumentChecklist(response.sections, ctx);
            response.securityMandateRows = loadSecurityMandateRows(ctx);
        } else {
            response.securityMandateRows = new List<SecurityMandateRow>();
        }

        /*
        // --- Production: load from Opportunity / product rules ---
        Opportunity opp = [...];
        response.productType = String.valueOf(opp.Product_Type__c);
        response.vehicleType = String.valueOf(opp.Vehicle_Type__c);
        response.sections = buildSectionsFromProduct(opp, screenType);
        enrichSectionsWithDocumentChecklist(response.sections, ctx);
        */
        return response;
    }

    /**
     * @description Ensures a Document_CheckList__c row exists for the application + applicant combination.
     */
    @AuraEnabled
    public static String initOrGetDocumentWithApplicantId(
        String applicationId,
        String documentType,
        String applicantId
    ) {
        try {
            return upsertDocumentChecklistRow(applicationId, applicantId, documentType, null);
        } catch (Exception e) {
            throw new AuraHandledException('Error initializing document: ' + e.getMessage());
        }
    }

    /**
     * @description Returns upload limits from the Cancelled Cheque document master.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCancelledChequeUploadConfig() {
        Document_Master__c master = resolveCancelledChequeMaster();
        Map<String, Object> config = new Map<String, Object>();
        config.put(
            'maxFilesAllowed',
            master != null && master.Max_Files_Allowed__c != null ? master.Max_Files_Allowed__c : 1
        );
        config.put(
            'allowedFileTypes',
            master != null && String.isNotBlank(master.File_Types_Allowed__c)
                ? master.File_Types_Allowed__c
                : 'JPEG,JPG,PDF,PNG'
        );
        return config;
    }

    /**
     * @description Creates a new Document_CheckList__c row (used for each Security Mandate table row).
     */
    @AuraEnabled
    public static String createDocumentChecklistRow(
        String applicationId,
        String documentType,
        String applicantId
    ) {
        try {
            if (String.isBlank(applicationId) || String.isBlank(applicantId) || String.isBlank(documentType)) {
                throw new AuraHandledException('Missing application, applicant, or document type.');
            }

            String resolvedDocumentType = normalizeCancelledChequeDocumentType(documentType);
            Document_Master__c master = resolveCancelledChequeMaster();

            Document_CheckList__c row = new Document_CheckList__c(
                Name = resolvedDocumentType + ' - Document',
                Document_Type__c = resolvedDocumentType,
                Application__c = applicationId,
                Applicant__c = applicantId,
                Is_Active__c = true
            );
            if (master != null) {
                row.Document_Master_Key__c = master.Master_Key__c;
            }
            insert row;
            return row.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating document checklist: ' + e.getMessage());
        }
    }

    /**
     * @description Deletes a Security Mandate Document_CheckList__c row.
     */
    @AuraEnabled
    public static SaveResult deleteSecurityMandateRow(Id documentChecklistId) {
        SaveResult result = new SaveResult();
        try {
            if (documentChecklistId == null) {
                result.success = false;
                result.message = 'Document checklist Id is required.';
                return result;
            }
            delete new Document_CheckList__c(Id = documentChecklistId);
            result.success = true;
            result.message = 'Security mandate row deleted.';
        } catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
        }
        return result;
    }

    /**
     * @description Links an uploaded ContentDocument to the Document_CheckList__c row via upsert.
     */
    @AuraEnabled
    public static Map<String, String> linkContentDocument(String documentDataJson) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(documentDataJson)) {
            return result;
        }

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(documentDataJson);
        String contentDocumentId = (String) data.get('contentDocumentId');
        String contentVersionId = (String) data.get('contentVersionId');
        String applicationId = (String) data.get('applicationId');
        String applicantId = (String) data.get('applicantId');
        String documentType = (String) data.get('documentType');

        ContentVersion versionRow = resolveUploadedContentVersion(contentDocumentId, contentVersionId);
        if (versionRow == null) {
            return result;
        }

        contentVersionId = versionRow.Id;
        contentDocumentId = versionRow.ContentDocumentId;

        String documentChecklistId = (String) data.get('documentChecklistId');
        if (String.isNotBlank(documentChecklistId)) {
            update new Document_CheckList__c(
                Id = documentChecklistId,
                ContentVersionId__c = contentVersionId
            );
        } else {
            upsertDocumentChecklistRow(applicationId, applicantId, documentType, contentVersionId);
        }

        result.put('contentDocumentId', contentDocumentId);
        result.put('contentVersionId', contentVersionId);
        result.put('fileName', versionRow.Title);
        result.put(
            'fileType',
            String.isNotBlank(versionRow.FileExtension)
                ? versionRow.FileExtension.toUpperCase()
                : 'PDF'
        );
        return result;
    }

    private static ContentVersion resolveUploadedContentVersion(
        String contentDocumentId,
        String contentVersionId
    ) {
        if (String.isNotBlank(contentVersionId)) {
            List<ContentVersion> versions = [
                SELECT Id, Title, ContentDocumentId, FileExtension
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
            return versions.isEmpty() ? null : versions[0];
        }

        if (String.isBlank(contentDocumentId)) {
            return null;
        }

        String resolvedVersionId = getLatestContentVersionId(contentDocumentId);
        if (String.isBlank(resolvedVersionId)) {
            return null;
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, ContentDocumentId, FileExtension
            FROM ContentVersion
            WHERE Id = :resolvedVersionId
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0];
    }

    /**
     * @description Sample stub — resolve file type for preview.
     */
    @AuraEnabled
    public static String getFileType(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            return 'PDF';
        }
        List<ContentVersion> versions = [
            SELECT FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
            LIMIT 1
        ];
        if (versions.isEmpty() || String.isBlank(versions[0].FileExtension)) {
            return 'PDF';
        }
        return versions[0].FileExtension.toUpperCase();
    }

    /**
     * @description Persists section field values on the section's Document_CheckList__c row.
     */
    @AuraEnabled
    public static Boolean upsertSectionFields(
        Id recordId,
        String documentId,
        String sectionKey,
        String fieldsJson
    ) {
        if (String.isBlank(documentId) || String.isBlank(fieldsJson)) {
            return false;
        }

        try {
            Map<String, Object> fieldMap = (Map<String, Object>) JSON.deserializeUntyped(fieldsJson);
            if (fieldMap.isEmpty()) {
                return true;
            }

            Document_CheckList__c row = new Document_CheckList__c(Id = documentId);
            for (String fieldApi : fieldMap.keySet()) {
                if (!CHECKLIST_FIELD_APIS.contains(fieldApi)) {
                    continue;
                }
                row.put(fieldApi, convertValueForChecklistField(fieldApi, fieldMap.get(fieldApi)));
            }

            update row;
            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving document fields: ' + e.getMessage());
        }
    }

    /**
     * @description Submits additional documents and persists all section fields to Document_CheckList__c.
     */
    @AuraEnabled
    public static SaveResult submitAdditionalDocuments(
        Id recordId,
        Id applicantId,
        String sectionsJson,
        String paymentRowsJson
    ) {
        SaveResult result = new SaveResult();
        try {
            if (String.isNotBlank(sectionsJson)) {
                persistAllSectionFieldsFromJson(sectionsJson);
            }
            if (String.isNotBlank(paymentRowsJson)) {
                persistSecurityMandateRowsFromJson(paymentRowsJson);
            }
            result.success = true;
            result.message = 'Additional documents saved successfully.';
        } catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
        }
        return result;
    }

    /**
     * @description Persists Document_Verified__c and Remarks__c on each uploaded Document_CheckList__c row.
     */
    @AuraEnabled
    public static SaveResult saveDocumentChecklistVerificationFields(String verificationJson) {
        SaveResult result = new SaveResult();
        try {
            if (String.isBlank(verificationJson)) {
                result.success = true;
                result.message = 'No document verification data to save.';
                return result;
            }

            List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(verificationJson);
            List<Document_CheckList__c> rowsToUpdate = new List<Document_CheckList__c>();

            for (Object rawRow : rawRows) {
                Map<String, Object> rowMap = (Map<String, Object>) rawRow;
                String checklistId = (String) rowMap.get('documentChecklistId');
                if (String.isBlank(checklistId)) {
                    continue;
                }

                Document_CheckList__c row = new Document_CheckList__c(Id = checklistId);
                if (rowMap.containsKey('documentVerified')) {
                    row.Document_Verified__c = convertDocumentVerifiedValue(
                        rowMap.get('documentVerified')
                    );
                }
                if (rowMap.containsKey('remarks')) {
                    row.Remarks__c = convertRemarksValue(rowMap.get('remarks'));
                }
                rowsToUpdate.add(row);
            }

            if (rowsToUpdate.isEmpty()) {
                result.success = false;
                result.message = 'No Document Checklist records found to update.';
                return result;
            }

            update rowsToUpdate;
            result.success = true;
            result.message = 'Document verification saved successfully.';
        } catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
        }
        return result;
    }

    private static String convertDocumentVerifiedValue(Object value) {
        if (value == null) {
            return null;
        }
        String strValue = String.valueOf(value).trim();
        return String.isBlank(strValue) ? null : strValue;
    }

    private static String convertRemarksValue(Object value) {
        if (value == null) {
            return null;
        }
        String strValue = String.valueOf(value).trim();
        return String.isBlank(strValue) ? null : strValue;
    }

    private class ApplicantContext {
        String applicationId;
        String applicantId;
    }

    private static ApplicantContext resolveApplicantContext(Id recordId, Id applicantId) {
        if (applicantId != null) {
            List<Applicant__c> applicants = [
                SELECT Id, Application__c
                FROM Applicant__c
                WHERE Id = :applicantId
                LIMIT 1
            ];
            if (!applicants.isEmpty() && applicants[0].Application__c != null) {
                ApplicantContext ctx = new ApplicantContext();
                ctx.applicantId = applicants[0].Id;
                ctx.applicationId = applicants[0].Application__c;
                return ctx;
            }
        }

        if (recordId == null) {
            return null;
        }

        String sobjectType = recordId.getSObjectType().getDescribe().getName();
        if (sobjectType == 'Applicant__c') {
            List<Applicant__c> applicants = [
                SELECT Id, Application__c
                FROM Applicant__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (!applicants.isEmpty() && applicants[0].Application__c != null) {
                ApplicantContext ctx = new ApplicantContext();
                ctx.applicantId = applicants[0].Id;
                ctx.applicationId = applicants[0].Application__c;
                return ctx;
            }
        }

        if (sobjectType == 'Application__c') {
            List<Applicant__c> applicants = [
                SELECT Id, Application__c
                FROM Applicant__c
                WHERE Application__c = :recordId
                  AND Applicant_Type__c = 'Borrower'
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!applicants.isEmpty()) {
                ApplicantContext ctx = new ApplicantContext();
                ctx.applicantId = applicants[0].Id;
                ctx.applicationId = applicants[0].Application__c;
                return ctx;
            }
        }

        return null;
    }

    private static void enrichSectionsWithDocumentChecklist(
        List<Section> sections,
        ApplicantContext ctx
    ) {
        if (sections == null || sections.isEmpty() || ctx == null) {
            return;
        }

        Set<String> documentTypes = new Set<String>();
        for (Section sec : sections) {
            if (String.isNotBlank(sec.docType)) {
                documentTypes.add(sec.docType);
            }
        }

        if (documentTypes.isEmpty()) {
            return;
        }

        Map<String, Document_CheckList__c> checklistByType = new Map<String, Document_CheckList__c>();
        for (Document_CheckList__c row : [
            SELECT Id,
                Document_Type__c,
                ContentVersionId__c,
                Bank_Name__c,
                Account_Number__c,
                RTO_Verified__c,
                DPN_Reference_Number__c,
                Cheque_Number__c,
                MICR_Code__c,
                Document_Verified__c,
                Remarks__c
            FROM Document_CheckList__c
            WHERE Application__c = :ctx.applicationId
              AND Applicant__c = :ctx.applicantId
              AND Document_Type__c IN :documentTypes
            ORDER BY CreatedDate DESC
        ]) {
            if (!checklistByType.containsKey(row.Document_Type__c)) {
                checklistByType.put(row.Document_Type__c, row);
            }
        }

        Set<Id> contentVersionIds = new Set<Id>();
        for (Document_CheckList__c row : checklistByType.values()) {
            if (String.isNotBlank(row.ContentVersionId__c)) {
                contentVersionIds.add(row.ContentVersionId__c);
            }
        }

        Map<Id, ContentVersion> versionById = new Map<Id, ContentVersion>();
        if (!contentVersionIds.isEmpty()) {
            for (ContentVersion version : [
                SELECT Id, Title, ContentDocumentId, FileExtension
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
            ]) {
                versionById.put(version.Id, version);
            }
        }

        for (Section sec : sections) {
            if (sec.isSecurityMandateSection == true) {
                continue;
            }

            Document_CheckList__c checklistRow = checklistByType.get(sec.docType);
            if (checklistRow == null) {
                continue;
            }

            sec.documentChecklistId = checklistRow.Id;
            sec.documentId = checklistRow.Id;
            sec.documentVerified = checklistRow.Document_Verified__c;
            sec.remarks = checklistRow.Remarks__c;
            enrichSectionFieldsFromChecklistRow(sec, checklistRow);

            if (String.isNotBlank(checklistRow.ContentVersionId__c)) {
                ContentVersion version = versionById.get(checklistRow.ContentVersionId__c);
                if (version != null) {
                    sec.hasFile = true;
                    sec.status = STATUS_UPLOADED;
                    sec.contentDocumentId = version.ContentDocumentId;
                    sec.fileName = version.Title;
                    sec.fileType = String.isNotBlank(version.FileExtension)
                        ? version.FileExtension.toUpperCase()
                        : 'PDF';
                }
            }

            if (sec.hasFile == true && sec.userSelectable == true) {
                sec.userSelected = true;
                sec.enabled = true;
            }
        }
    }

    private static Id upsertDocumentChecklistRow(
        String applicationId,
        String applicantId,
        String documentType,
        String contentVersionId
    ) {
        if (String.isBlank(applicationId) || String.isBlank(applicantId) || String.isBlank(documentType)) {
            throw new AuraHandledException('Missing application, applicant, or document type.');
        }

        List<Document_CheckList__c> existingDocs = [
            SELECT Id, ContentVersionId__c
            FROM Document_CheckList__c
            WHERE Application__c = :applicationId
              AND Applicant__c = :applicantId
              AND Document_Type__c = :documentType
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Document_CheckList__c row;
        if (existingDocs.isEmpty()) {
            row = new Document_CheckList__c(
                Name = documentType + ' - Document',
                Document_Type__c = documentType,
                Application__c = applicationId,
                Applicant__c = applicantId
            );
        } else {
            row = existingDocs[0];
        }

        if (String.isNotBlank(contentVersionId)) {
            row.ContentVersionId__c = contentVersionId;
        }

        upsert row;
        return row.Id;
    }

    private static String getLatestContentVersionId(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            return null;
        }
        List<ContentVersion> versions = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0].Id;
    }

    private static List<Section> buildSampleSections() {
        List<Section> sections = new List<Section>();

        sections.add(buildSelectableSection(
            'RC_DOC',
            'Updated RC Document',
            'RC Document',
            false,
            false,
            false
        ));
        sections.add(buildSelectableSection(
            'SELLER_BANK',
            'Bank Statement — Seller Bank Account',
            'Seller Bank Statement',
            false,
            false,
            false
        ));
        sections.add(buildSelectableSection(
            'TAX_INVOICE',
            'Tax Invoice',
            'Tax Invoice',
            false,
            false,
            false
        ));
        sections.add(buildSelectableSection(
            'BWR_BANK',
            'Bank Statement — Borrower Bank Account',
            'Borrower Bank Statement',
            true,
            false,
            false
        ));

        Section rto = buildSelectableSection(
            'RTO',
            'RTO Documents',
            'RTO Documents',
            true,
            false,
            true
        );
        rto.fields = new List<SectionField>{
            buildPicklistField(
                'RTO_Verified__c',
                'RTO Verified',
                true,
                new List<String>{ 'Yes', 'No' },
                null
            )
        };
        sections.add(rto);

        Section dpn = buildSelectableSection(
            'DPN',
            'DPN Documents',
            'DPN Documents',
            true,
            false,
            true
        );
        dpn.fields = new List<SectionField>{
            buildTextField('DPN_Reference_Number__c', 'DPN Reference Number', true, null)
        };
        sections.add(dpn);

        Section security = buildSelectableSection(
            'SECURITY_MANDATE',
            'Security Mandate',
            DOCUMENT_TYPE_CANCELLED_CHEQUE,
            true,
            false,
            true
        );
        security.isSecurityMandateSection = true;
        security.userSelectable = false;
        security.userSelected = true;
        security.fields = new List<SectionField>();
        sections.add(security);

        return sections;
    }

    private static Section buildSelectableSection(
        String key,
        String label,
        String docType,
        Boolean required,
        Boolean conditional,
        Boolean alwaysVisible
    ) {
        Section sec = new Section();
        sec.key = key;
        sec.label = label;
        sec.docType = docType;
        sec.required = required;
        sec.conditional = conditional;
        sec.enabled = alwaysVisible;
        sec.hasFile = false;
        sec.status = STATUS_PENDING;
        sec.borrowerType = 'Borrower';
        sec.isAlwaysVisible = alwaysVisible;
        sec.userSelectable = !alwaysVisible;
        sec.userSelected = alwaysVisible;
        sec.isSecurityMandateSection = false;
        sec.isCAM = false;
        sec.isReadOnly = false;
        sec.fields = new List<SectionField>();
        if (key == 'BWR_BANK') {
            sec.fields.add(buildPicklistField(
                'Bank_Name__c',
                'Borrower Bank Name',
                true,
                BORROWER_BANK_OPTIONS,
                null
            ));
            sec.fields.add(buildTextField('Account_Number__c', 'Account Number', true, null));
        }
        return sec;
    }

    private static SectionField buildPicklistField(
        String api,
        String label,
        Boolean required,
        List<String> optionLabels,
        String value
    ) {
        SectionField field = new SectionField();
        field.api = api;
        field.label = label;
        field.type = 'picklist';
        field.required = required;
        field.value = value;
        field.typeIsPicklist = true;
        field.isRadioGroup = false;
        field.isCVOVerificationField = false;
        field.isBankLookup = false;
        field.isFieldDisabled = true;
        field.options = new List<PickOption>();
        for (String opt : optionLabels) {
            field.options.add(new PickOption(opt, opt));
        }
        return field;
    }

    private static SectionField buildTextField(String api, String label, Boolean required, String value) {
        SectionField field = new SectionField();
        field.api = api;
        field.label = label;
        field.type = 'text';
        field.required = required;
        field.value = value;
        field.typeIsPicklist = false;
        field.isRadioGroup = false;
        field.isCVOVerificationField = false;
        field.isBankLookup = false;
        field.isFieldDisabled = true;
        field.options = new List<PickOption>();
        return field;
    }

    private static void enrichSectionFieldsFromChecklistRow(
        Section sec,
        Document_CheckList__c checklistRow
    ) {
        if (sec == null || checklistRow == null || sec.fields == null) {
            return;
        }

        for (SectionField field : sec.fields) {
            field.value = readChecklistFieldValueAsString(checklistRow, field.api);
            field.isFieldDisabled = sec.isSecurityMandateSection
                ? sec.isReadOnly
                : !sec.hasFile;
        }
    }

    private static String readChecklistFieldValueAsString(
        Document_CheckList__c row,
        String fieldApi
    ) {
        if (row == null || String.isBlank(fieldApi) || !CHECKLIST_FIELD_APIS.contains(fieldApi)) {
            return '';
        }

        if ('RTO_Verified__c'.equals(fieldApi)) {
            Object rawValue = row.get(fieldApi);
            if (rawValue == null) {
                return '';
            }
            if (rawValue instanceof Boolean) {
                return (Boolean) rawValue ? 'Yes' : 'No';
            }
            String strValue = String.valueOf(rawValue);
            if ('true'.equalsIgnoreCase(strValue)) {
                return 'Yes';
            }
            if ('false'.equalsIgnoreCase(strValue)) {
                return 'No';
            }
            return strValue;
        }

        Object value = row.get(fieldApi);
        return value == null ? '' : String.valueOf(value);
    }

    private static Object convertValueForChecklistField(String fieldApi, Object value) {
        if (value == null) {
            return null;
        }

        if ('RTO_Verified__c'.equals(fieldApi)) {
            if (value instanceof Boolean) {
                return value;
            }
            String rtoValue = String.valueOf(value).trim();
            if (String.isBlank(rtoValue)) {
                return null;
            }
            if ('Yes'.equalsIgnoreCase(rtoValue) || 'true'.equalsIgnoreCase(rtoValue)) {
                return true;
            }
            if ('No'.equalsIgnoreCase(rtoValue) || 'false'.equalsIgnoreCase(rtoValue)) {
                return false;
            }
            return null;
        }

        String strValue = String.valueOf(value).trim();
        return String.isBlank(strValue) ? null : strValue;
    }

    private static void persistAllSectionFieldsFromJson(String sectionsJson) {
        List<Object> rawSections = (List<Object>) JSON.deserializeUntyped(sectionsJson);
        Map<Id, Map<String, Object>> fieldsByChecklistId = new Map<Id, Map<String, Object>>();

        for (Object rawSection : rawSections) {
            Map<String, Object> sectionMap = (Map<String, Object>) rawSection;
            String documentId = (String) sectionMap.get('documentChecklistId');
            if (String.isBlank(documentId)) {
                documentId = (String) sectionMap.get('documentId');
            }
            if (String.isBlank(documentId)) {
                continue;
            }

            List<Object> rawFields = (List<Object>) sectionMap.get('fields');
            Boolean isUploadedSection = sectionMap.get('hasFile') == true;
            Boolean hasSectionFields = rawFields != null && !rawFields.isEmpty();
            Boolean hasOpsFields =
                isUploadedSection
                && (sectionMap.containsKey('documentVerified') || sectionMap.containsKey('remarks'));
            if (!hasSectionFields && !hasOpsFields) {
                continue;
            }

            Id checklistId = (Id) documentId;
            if (!fieldsByChecklistId.containsKey(checklistId)) {
                fieldsByChecklistId.put(checklistId, new Map<String, Object>());
            }
            Map<String, Object> mergedFields = fieldsByChecklistId.get(checklistId);

            if (hasSectionFields) {
                for (Object rawField : rawFields) {
                    Map<String, Object> fieldMap = (Map<String, Object>) rawField;
                    String fieldApi = (String) fieldMap.get('api');
                    if (String.isBlank(fieldApi) || !CHECKLIST_FIELD_APIS.contains(fieldApi)) {
                        continue;
                    }
                    mergedFields.put(fieldApi, fieldMap.get('value'));
                }
            }

            if (sectionMap.containsKey('documentVerified')) {
                Object verifiedValue = sectionMap.get('documentVerified');
                if (isUploadedSection) {
                    mergedFields.put('Document_Verified__c', verifiedValue);
                }
            }
            if (sectionMap.containsKey('remarks')) {
                Object remarksValue = sectionMap.get('remarks');
                if (isUploadedSection) {
                    mergedFields.put('Remarks__c', remarksValue);
                }
            }
        }

        if (fieldsByChecklistId.isEmpty()) {
            return;
        }

        List<Document_CheckList__c> rowsToUpdate = new List<Document_CheckList__c>();
        for (Id checklistId : fieldsByChecklistId.keySet()) {
            Document_CheckList__c row = new Document_CheckList__c(Id = checklistId);
            for (String fieldApi : fieldsByChecklistId.get(checklistId).keySet()) {
                row.put(
                    fieldApi,
                    convertValueForChecklistField(
                        fieldApi,
                        fieldsByChecklistId.get(checklistId).get(fieldApi)
                    )
                );
            }
            rowsToUpdate.add(row);
        }

        if (!rowsToUpdate.isEmpty()) {
            update rowsToUpdate;
        }
    }

    private static List<SecurityMandateRow> loadSecurityMandateRows(ApplicantContext ctx) {
        List<SecurityMandateRow> rows = new List<SecurityMandateRow>();
        if (ctx == null) {
            return rows;
        }

        List<Document_CheckList__c> checklistRows = [
            SELECT Id,
                ContentVersionId__c,
                Cheque_Number__c,
                Bank_Name__c,
                MICR_Code__c,
                Document_Verified__c,
                Remarks__c
            FROM Document_CheckList__c
            WHERE Application__c = :ctx.applicationId
              AND Applicant__c = :ctx.applicantId
              AND Document_Type__c IN (
                  :DOCUMENT_TYPE_CANCELLED_CHEQUE,
                  :LEGACY_DOCUMENT_TYPE_SECURITY_MANDATE
              )
            ORDER BY CreatedDate ASC
        ];

        Set<Id> contentVersionIds = new Set<Id>();
        for (Document_CheckList__c checklistRow : checklistRows) {
            if (String.isNotBlank(checklistRow.ContentVersionId__c)) {
                contentVersionIds.add(checklistRow.ContentVersionId__c);
            }
        }

        Map<Id, ContentVersion> versionById = new Map<Id, ContentVersion>();
        if (!contentVersionIds.isEmpty()) {
            for (ContentVersion version : [
                SELECT Id, Title, ContentDocumentId, FileExtension
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
            ]) {
                versionById.put(version.Id, version);
            }
        }

        for (Document_CheckList__c checklistRow : checklistRows) {
            SecurityMandateRow row = new SecurityMandateRow();
            row.documentChecklistId = checklistRow.Id;
            row.chequeNumber = checklistRow.Cheque_Number__c;
            row.bankName = checklistRow.Bank_Name__c;
            row.micrCode = checklistRow.MICR_Code__c;
            row.documentVerified = checklistRow.Document_Verified__c;
            row.remarks = checklistRow.Remarks__c;
            row.isUploaded = false;

            if (String.isNotBlank(checklistRow.ContentVersionId__c)) {
                ContentVersion version = versionById.get(checklistRow.ContentVersionId__c);
                if (version != null) {
                    row.isUploaded = true;
                    row.contentVersionId = version.Id;
                    row.contentDocumentId = version.ContentDocumentId;
                    row.fileName = version.Title;
                    row.fileType = String.isNotBlank(version.FileExtension)
                        ? version.FileExtension.toUpperCase()
                        : 'PDF';
                }
            }

            rows.add(row);
        }

        return rows;
    }

    private static void persistSecurityMandateRowsFromJson(String paymentRowsJson) {
        List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(paymentRowsJson);
        List<Document_CheckList__c> rowsToUpdate = new List<Document_CheckList__c>();

        for (Object rawRow : rawRows) {
            Map<String, Object> rowMap = (Map<String, Object>) rawRow;
            String checklistId = (String) rowMap.get('documentChecklistId');
            if (String.isBlank(checklistId)) {
                continue;
            }

            Document_CheckList__c row = new Document_CheckList__c(Id = checklistId);
            if (rowMap.containsKey('chequeNumber')) {
                row.Cheque_Number__c = (String) convertValueForChecklistField(
                    'Cheque_Number__c',
                    rowMap.get('chequeNumber')
                );
            }
            if (rowMap.containsKey('bankName')) {
                row.Bank_Name__c = (String) convertValueForChecklistField(
                    'Bank_Name__c',
                    rowMap.get('bankName')
                );
            }
            if (rowMap.containsKey('micrCode')) {
                row.MICR_Code__c = (String) convertValueForChecklistField(
                    'MICR_Code__c',
                    rowMap.get('micrCode')
                );
            }
            if (rowMap.containsKey('documentVerified')) {
                row.Document_Verified__c = convertDocumentVerifiedValue(
                    rowMap.get('documentVerified')
                );
            }
            if (rowMap.containsKey('remarks')) {
                row.Remarks__c = convertRemarksValue(rowMap.get('remarks'));
            }
            rowsToUpdate.add(row);
        }

        if (!rowsToUpdate.isEmpty()) {
            update rowsToUpdate;
        }
    }

    private static String normalizeCancelledChequeDocumentType(String documentType) {
        if (
            String.isBlank(documentType)
            || documentType == LEGACY_DOCUMENT_TYPE_SECURITY_MANDATE
            || documentType == DOCUMENT_TYPE_CANCELLED_CHEQUE
        ) {
            return DOCUMENT_TYPE_CANCELLED_CHEQUE;
        }
        return documentType;
    }

    private static Document_Master__c resolveCancelledChequeMaster() {
        List<Document_Master__c> masters = [
            SELECT Master_Key__c, Max_Files_Allowed__c, File_Types_Allowed__c
            FROM Document_Master__c
            WHERE Document_Name__c = :DOCUMENT_TYPE_CANCELLED_CHEQUE
              AND Document_Category__c = :DOCUMENT_CATEGORY_CHEQUES_SECURITY
              AND Is_Active__c = TRUE
            LIMIT 1
        ];
        return masters.isEmpty() ? null : masters[0];
    }
}