public with sharing class CaptureCreditAssessmentController implements Callable {

    private static final String ACTION_GET_CREDIT_ASSESSMENT = 'getCreditAssessment';
    private static final String ACTION_SAVE_CREDIT_ASSESSMENT = 'saveCreditAssessment';
    private static final String ACTION_FETCH_NIC_MASTER = 'fetchNicMasterData';

    private static final String PRODUCT_PV = '4W';
    private static final String PRODUCT_CV = 'CV';
    private static final String PURPOSE_COMMERCIAL = 'Commercial';
    private static final String PSL_SUB_TYPE_MSME = 'MSME';
    private static final String PSL_SUB_TYPE_AGRI = 'Agri';
    private static final String INVESTMENT_TYPE = 'Investment in P&M (Other than Lands & Buildings) In INR';
    private static final String TURNOVER_TYPE = 'Turnover in INR';
    private static final String UDHYAM_DOCUMENT_TYPE = 'Udhyam Registration Certificate';

    public Object call(String action, Map<String, Object> params) {
        Map<String, Object> safeParams = params != null ? params : new Map<String, Object>();

        if (ACTION_GET_CREDIT_ASSESSMENT.equalsIgnoreCase(action)) {
            return loadAssessment(safeParams);
        }
        if (ACTION_SAVE_CREDIT_ASSESSMENT.equalsIgnoreCase(action)) {
            return persistAssessment(safeParams);
        }
        if (ACTION_FETCH_NIC_MASTER.equalsIgnoreCase(action)) {
            return lookupNicMaster(safeParams);
        }
        throw new IllegalArgumentException(
            'CaptureCreditAssessmentController: unknown action — ' + action
        );
    }

    private static Map<String, Object> loadAssessment(Map<String, Object> params) {
        String applicationId = getStringValue(params, 'recordId');
        if (String.isBlank(applicationId)) {
            return emptyAssessmentResponse();
        }
        Id applicantId = parseIdValue(params.get('applicantId'));
        if (applicantId == null) {
            throw new AuraHandledException('Applicant ID is required to load credit assessment data.');
        }
        if (!isApplicantOfApplication(applicantId, (Id) applicationId)) {
            throw new AuraHandledException('Applicant not found for the supplied application.');
        }

        List<Application__c> applications = [
            SELECT Id, Product__c,
                (
                    SELECT Id, End_Use__c, Loan_Categorization__c, Non_PSL_Categorization__c,
                        PSL_Sub_Type__c, Sub_Sector_Type__c, Borrower_Category_Type__c,
                        Borrower_Category__c, Acre_Category__c, GST_Status__c,
                        Udhyam_Registration_Number__c, Udhyam_Registration_Date__c,
                        (
                            SELECT Id, NIC_Code__c, NIC_Group_Description__c,
                                NIC_Class_Description__c, NIC_Sub_Class_Description__c
                            FROM NIC_Details__r
                        ),
                        (
                            SELECT Id, Type__c, Loan_Range__c, Amount__c, Audited__c, Projected__c
                            FROM Investment_Turnover_Details__r
                        )
                    FROM PSL_Informations__r
                    LIMIT 1
                )
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (applications.isEmpty()) {
            return emptyAssessmentResponse();
        }

        Application__c application = applications[0];
        String productCategory = toProductCategory(application.Product__c);
        ApplicantContext applicantContext = loadApplicantContext(applicationId);
        Boolean isCommercialPurpose = applicantContext.isCommercialPurpose;

        Map<String, Object> response = new Map<String, Object>{
            'remarks' => applicantContext.remarkFor(applicantId),
            'productType' => productCategory,
            'isCommercialPurpose' => isCommercialPurpose,
            'showPslForProduct' => productCategory == 'CV'
                || (productCategory == 'PV' && isCommercialPurpose)
        };

        if (!application.PSL_Informations__r.isEmpty()) {
            response.put('psl', serializePslRecord(application.PSL_Informations__r[0]));
        }

        response.put('udhyamDocument', loadUdhyamDocument(applicationId, applicantId));
        return response;
    }

    private static Map<String, Object> persistAssessment(Map<String, Object> params) {
        String applicationId = getStringValue(params, 'recordId');
        if (String.isBlank(applicationId)) {
            throw new AuraHandledException('Application ID is required to save credit assessment data.');
        }

        Id applicantId = parseIdValue(params.get('applicantId'));
        if (applicantId == null) {
            throw new AuraHandledException('Applicant ID is required to save credit assessment data.');
        }
        if (!isApplicantOfApplication(applicantId, (Id) applicationId)) {
            throw new AuraHandledException('Applicant not found for the supplied application.');
        }

        updateApplicantRemark(applicationId, applicantId, getStringValue(params, 'remarks'));

        Map<String, Object> pslData = asMap(params.get('psl'));
        Id pslId = pslData.isEmpty() ? null : savePslRecord((Id) applicationId, pslData);

        return new Map<String, Object>{
            'success' => true,
            'pslId' => pslId
        };
    }

    private static Map<String, Object> lookupNicMaster(Map<String, Object> params) {
        String nicCode = getStringValue(params, 'nicCode');
        if (String.isBlank(nicCode) || nicCode.length() != 5) {
            return new Map<String, Object>();
        }

        Integer nicGroup = Integer.valueOf(nicCode.substring(0, 3));
        Integer nicClass = Integer.valueOf(nicCode.substring(0, 4));
        Integer nicSubClass = Integer.valueOf(nicCode);

        List<NIC_Master__c> masterRows = [
            SELECT NIC_Group__c, NIC_Class__c, NIC_Sub_Class__c, NIC_Description__c
            FROM NIC_Master__c
            WHERE NIC_Group__c = :nicGroup
            WITH SECURITY_ENFORCED
        ];

        if (masterRows.isEmpty()) {
            return new Map<String, Object>();
        }

        String groupDescription = '';
        String classDescription = '';
        String subClassDescription = '';

        for (NIC_Master__c row : masterRows) {
            if (row.NIC_Group__c == nicGroup
                && row.NIC_Class__c == null
                && row.NIC_Sub_Class__c == null) {
                groupDescription = row.NIC_Description__c;
            } else if (row.NIC_Group__c == nicGroup
                && row.NIC_Class__c == nicClass
                && row.NIC_Sub_Class__c == null) {
                classDescription = row.NIC_Description__c;
            } else if (row.NIC_Group__c == nicGroup
                && row.NIC_Class__c == nicClass
                && row.NIC_Sub_Class__c == nicSubClass) {
                subClassDescription = row.NIC_Description__c;
            }
        }

        if (String.isBlank(subClassDescription)
            || String.isBlank(classDescription)
            || String.isBlank(groupDescription)) {
            return new Map<String, Object>();
        }

        return new Map<String, Object>{
            'nicCode' => nicCode,
            'nicGroupDescription' => groupDescription,
            'nicClassDescription' => classDescription,
            'nicSubClassDescription' => subClassDescription
        };
    }

    private static Map<String, Object> emptyAssessmentResponse() {
        return new Map<String, Object>{
            'remarks' => '',
            'productType' => '',
            'isCommercialPurpose' => false,
            'showPslForProduct' => false,
            'udhyamDocument' => emptyUdhyamDocument()
        };
    }

    private static Map<String, Object> emptyUdhyamDocument() {
        return new Map<String, Object>{
            'uploaded' => false,
            'checklistId' => '',
            'contentVersionId' => '',
            'fileType' => '',
            'fileName' => ''
        };
    }

    private static Map<String, Object> loadUdhyamDocument(String applicationId, Id applicantId) {
        Map<String, Object> document = emptyUdhyamDocument();

        if (String.isBlank(applicationId) || applicantId == null) {
            return document;
        }

        List<Document_CheckList__c> checklistRows = [
            SELECT Id, ContentVersionId__c
            FROM Document_CheckList__c
            WHERE Application__c = :applicationId
                AND Applicant__c = :applicantId
                AND Document_Type__c = :UDHYAM_DOCUMENT_TYPE
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (checklistRows.isEmpty() || checklistRows[0].ContentVersionId__c == null) {
            return document;
        }

        Document_CheckList__c checklist = checklistRows[0];
        document.put('checklistId', String.valueOf(checklist.Id));

        List<ContentVersion> versions = [
            SELECT FileExtension, Title
            FROM ContentVersion
            WHERE Id = :checklist.ContentVersionId__c
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            return document;
        }

        ContentVersion version = versions[0];
        document.put('uploaded', true);
        document.put('contentVersionId', String.valueOf(checklist.ContentVersionId__c));
        document.put('fileType', version.FileExtension);
        document.put('fileName', String.isNotBlank(version.Title) ? version.Title : UDHYAM_DOCUMENT_TYPE);
        return document;
    }

    private static String toProductCategory(String productType) {
        if (String.isBlank(productType)) {
            return '';
        }

        String normalized = productType.trim();
        if (PRODUCT_PV.equalsIgnoreCase(normalized)) {
            return 'PV';
        }
        if (PRODUCT_CV.equalsIgnoreCase(normalized)) {
            return 'CV';
        }

        String lower = normalized.toLowerCase();
        if (lower.contains('passenger') || lower == 'pv') {
            return 'PV';
        }
        if (lower.contains('commercial') || lower == 'cv') {
            return 'CV';
        }
        return normalized;
    }

    private class ApplicantContext {
        Boolean isCommercialPurpose = false;
        Map<Id, String> applicantIdToRemark = new Map<Id, String>();

        String remarkFor(Id applicantId) {
            return applicantId == null || !applicantIdToRemark.containsKey(applicantId)
                ? ''
                : applicantIdToRemark.get(applicantId);
        }
    }

    private static ApplicantContext loadApplicantContext(Id applicationId) {
        ApplicantContext context = new ApplicantContext();

        for (Applicant__c applicant : [
            SELECT Id, Justification_Remark__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
                AND In_Active_Applicant__c = false
            WITH SECURITY_ENFORCED
        ]) {
            context.applicantIdToRemark.put(
                applicant.Id,
                applicant.Justification_Remark__c != null ? applicant.Justification_Remark__c : ''
            );
        }

        context.isCommercialPurpose = ![
            SELECT Id
            FROM Asset__c
            WHERE Applicant__r.Application__c = :applicationId
                AND Applicant__r.In_Active_Applicant__c = false
                AND Purpose_of_purchase__c = :PURPOSE_COMMERCIAL
            WITH SECURITY_ENFORCED
            LIMIT 1
        ].isEmpty();

        return context;
    }

    private static void updateApplicantRemark(Id applicationId, Id applicantId, String remarks) {
        if (!Schema.sObjectType.Applicant__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient access to save applicant remarks.');
        }

        List<Applicant__c> applicants = [
            SELECT Id
            FROM Applicant__c
            WHERE Id = :applicantId
                AND Application__c = :applicationId
                AND In_Active_Applicant__c = false
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (applicants.isEmpty()) {
            throw new AuraHandledException('Applicant not found for the supplied application.');
        }

        Applicant__c applicant = applicants[0];
        applicant.Justification_Remark__c = remarks;
        update applicant;
    }
    private static Boolean isApplicantOfApplication(Id applicantId, Id applicationId) {
        if (applicantId == null || applicationId == null) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM Applicant__c
            WHERE Id = :applicantId
                AND Application__c = :applicationId
                AND In_Active_Applicant__c = false
        ] > 0;
    }

    private static Map<String, Object> serializePslRecord(PSL_Information__c pslRecord) {
        Map<String, Object> payload = new Map<String, Object>{
            'pslId' => pslRecord.Id,
            'endUse' => pslRecord.End_Use__c,
            'loanCategorization' => pslRecord.Loan_Categorization__c,
            'nonPslCategorization' => pslRecord.Non_PSL_Categorization__c,
            'pslSubType' => pslRecord.PSL_Sub_Type__c,
            'typeOfActivity' => '',
            'typeOfEnterprise' => '',
            'gstStatus' => pslRecord.GST_Status__c,
            'udhyamRegistrationNo' => pslRecord.Udhyam_Registration_Number__c,
            'udhyamRegistrationDate' => pslRecord.Udhyam_Registration_Date__c,
            'agriType' => '',
            'borrowerCategory' => '',
            'acreCategory' => pslRecord.Acre_Category__c,
            'nicRows' => new List<Map<String, Object>>(),
            'investmentRows' => new List<Map<String, Object>>(),
            'turnoverRows' => new List<Map<String, Object>>()
        };

        if (PSL_SUB_TYPE_MSME.equalsIgnoreCase(pslRecord.PSL_Sub_Type__c)) {
            payload.put('typeOfActivity', pslRecord.Sub_Sector_Type__c);
            payload.put('typeOfEnterprise', pslRecord.Borrower_Category_Type__c);
        } else if (PSL_SUB_TYPE_AGRI.equalsIgnoreCase(pslRecord.PSL_Sub_Type__c)) {
            payload.put('agriType', pslRecord.Sub_Sector_Type__c);
            payload.put('borrowerCategory', pslRecord.Borrower_Category_Type__c);
        }

        for (NIC_Details__c nicRow : pslRecord.NIC_Details__r) {
            ((List<Map<String, Object>>) payload.get('nicRows')).add(new Map<String, Object>{
                'id' => nicRow.Id,
                'nicCode' => nicRow.NIC_Code__c,
                'nicGroupDescription' => nicRow.NIC_Group_Description__c,
                'nicClassDescription' => nicRow.NIC_Class_Description__c,
                'nicSubClassDescription' => nicRow.NIC_Sub_Class_Description__c
            });
        }

        for (Investment_Turnover_Detail__c row : pslRecord.Investment_Turnover_Details__r) {
            String auditStatus = '';
            if (row.Projected__c == true) {
                auditStatus = 'Projected';
            } else if (row.Audited__c == true) {
                auditStatus = 'Audited';
            } else if (row.Audited__c == false && row.Amount__c != null) {
                auditStatus = 'Unaudited';
            }

            Map<String, Object> rowPayload = new Map<String, Object>{
                'id' => row.Id,
                'yearRange' => row.Loan_Range__c,
                'amount' => row.Amount__c,
                'audited' => auditStatus
            };

            if (INVESTMENT_TYPE.equalsIgnoreCase(row.Type__c)) {
                ((List<Map<String, Object>>) payload.get('investmentRows')).add(rowPayload);
            } else if (TURNOVER_TYPE.equalsIgnoreCase(row.Type__c)) {
                ((List<Map<String, Object>>) payload.get('turnoverRows')).add(rowPayload);
            }
        }

        return payload;
    }

    private static Id savePslRecord(Id applicationId, Map<String, Object> pslData) {
        if (!Schema.sObjectType.PSL_Information__c.isCreateable()) {
            throw new AuraHandledException('Insufficient access to save PSL information.');
        }

        List<PSL_Information__c> existingRecords = [
            SELECT Id
            FROM PSL_Information__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
        ];

        if (!existingRecords.isEmpty() && Schema.sObjectType.PSL_Information__c.isDeletable()) {
            delete existingRecords;
        }

        String pslSubType = getStringValue(pslData, 'pslSubType');
        PSL_Information__c pslRecord = new PSL_Information__c(
            Application__c = applicationId,
            End_Use__c = getStringValue(pslData, 'endUse'),
            Loan_Categorization__c = getStringValue(pslData, 'loanCategorization'),
            Non_PSL_Categorization__c = getStringValue(pslData, 'nonPslCategorization'),
            PSL_Sub_Type__c = pslSubType,
            GST_Status__c = getStringValue(pslData, 'gstStatus'),
            Udhyam_Registration_Number__c = getStringValue(pslData, 'udhyamRegistrationNo'),
            Udhyam_Registration_Date__c = parseDateValue(pslData.get('udhyamRegistrationDate')),
            Acre_Category__c = getStringValue(pslData, 'acreCategory')
        );

        if (PSL_SUB_TYPE_MSME.equalsIgnoreCase(pslSubType)) {
            pslRecord.Sub_Sector_Type__c = getStringValue(pslData, 'typeOfActivity');
            pslRecord.Borrower_Category_Type__c = getStringValue(pslData, 'typeOfEnterprise');
        } else if (PSL_SUB_TYPE_AGRI.equalsIgnoreCase(pslSubType)) {
            pslRecord.Sub_Sector_Type__c = getStringValue(pslData, 'agriType');
            pslRecord.Borrower_Category_Type__c = getStringValue(pslData, 'borrowerCategory');
        }

        insert pslRecord;

        List<NIC_Details__c> nicRows = new List<NIC_Details__c>();
        for (Object rawRow : asObjectList(pslData, 'nicRows')) {
            if (!(rawRow instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) rawRow;
            String nicCode = getStringValue(row, 'nicCode');
            if (String.isBlank(nicCode)) {
                continue;
            }

            nicRows.add(new NIC_Details__c(
                PSL_Information__c = pslRecord.Id,
                NIC_Code__c = nicCode,
                NIC_Group_Description__c = getStringValue(row, 'nicGroupDescription'),
                NIC_Class_Description__c = getStringValue(row, 'nicClassDescription'),
                NIC_Sub_Class_Description__c = getStringValue(row, 'nicSubClassDescription')
            ));
        }
        if (!nicRows.isEmpty()) {
            insert nicRows;
        }

        List<Investment_Turnover_Detail__c> detailRows = new List<Investment_Turnover_Detail__c>();
        for (String rowType : new List<String>{ INVESTMENT_TYPE, TURNOVER_TYPE }) {
            String payloadKey = INVESTMENT_TYPE.equals(rowType) ? 'investmentRows' : 'turnoverRows';

            for (Object rawRow : asObjectList(pslData, payloadKey)) {
                if (!(rawRow instanceof Map<String, Object>)) {
                    continue;
                }

                Map<String, Object> row = (Map<String, Object>) rawRow;
                String yearRange = getStringValue(row, 'yearRange');
                if (String.isBlank(yearRange)) {
                    continue;
                }

                String auditStatus = getStringValue(row, 'audited').trim().toLowerCase();
                detailRows.add(new Investment_Turnover_Detail__c(
                    PSL_Information__c = pslRecord.Id,
                    Type__c = rowType,
                    Loan_Range__c = yearRange,
                    Amount__c = parseDecimalValue(row.get('amount')),
                    Audited__c = auditStatus == 'audited',
                    Projected__c = auditStatus == 'projected'
                ));
            }
        }
        if (!detailRows.isEmpty()) {
            insert detailRows;
        }

        return pslRecord.Id;
    }

    private static Map<String, Object> asMap(Object rawValue) {
        if (rawValue == null) {
            return new Map<String, Object>();
        }
        if (rawValue instanceof Map<String, Object>) {
            return (Map<String, Object>) rawValue;
        }
        try {
            Object reparsed = JSON.deserializeUntyped(JSON.serialize(rawValue));
            if (reparsed instanceof Map<String, Object>) {
                return (Map<String, Object>) reparsed;
            }
        } catch (Exception ex) {
            throw new AuraHandledException('Could not parse PSL payload: ' + ex.getMessage());
        }
        return new Map<String, Object>();
    }

    private static String getStringValue(Map<String, Object> source, String key) {
        if (source == null || !source.containsKey(key) || source.get(key) == null) {
            return '';
        }
        return String.valueOf(source.get(key)).trim();
    }

    private static List<Object> asObjectList(Map<String, Object> source, String key) {
        Object rawValue = source != null ? source.get(key) : null;
        if (rawValue == null) {
            return new List<Object>();
        }
        if (rawValue instanceof List<Object>) {
            return (List<Object>) rawValue;
        }
        try {
            Object reparsed = JSON.deserializeUntyped(JSON.serialize(rawValue));
            if (reparsed instanceof List<Object>) {
                return (List<Object>) reparsed;
            }
        } catch (Exception ex) {
            return new List<Object>();
        }
        return new List<Object>();
    }

    private static Id parseIdValue(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        if (String.isBlank(value) || (value.length() != 15 && value.length() != 18)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date parseDateValue(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        if (rawValue instanceof Date) {
            return (Date) rawValue;
        }
        String value = String.valueOf(rawValue).trim();
        return String.isBlank(value) ? null : Date.valueOf(value);
    }

    private static Decimal parseDecimalValue(Object rawValue) {
        if (rawValue == null || String.isBlank(String.valueOf(rawValue))) {
            return null;
        }
        return Decimal.valueOf(String.valueOf(rawValue));
    }
}