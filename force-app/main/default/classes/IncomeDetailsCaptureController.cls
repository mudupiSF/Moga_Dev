public with sharing class IncomeDetailsCaptureController implements Callable {

    private static final String STAGE_INCOME_DETAILS = 'Income and Banking Details';
    private static final String INCOME_RECORD_NAME = 'Declared Income';
    private static final String STATUS_NOT_STARTED = 'Not started';
    private static final String STATUS_SAVED = 'Saved';
    private static final String DOC_TYPE_BANK_STATEMENT = 'Bank Statement';

    private static final String ACTION_FETCH_INCOME_DETAILS_CONTEXT = 'fetchIncomeDetailsContext';
    private static final String ACTION_GET_DECLARED_INCOME_DETAILS = 'getDeclaredIncomeDetails';
    private static final String ACTION_SAVE_DECLARED_INCOME_DETAILS = 'saveDeclaredIncomeDetails';
    private static final String ACTION_UPSERT_DECLARED_INCOME_DOCUMENT = 'upsertDeclaredIncomeDocument';
    private static final String ACTION_GET_DECLARED_INCOME_DOCUMENT = 'getDeclaredIncomeDocument';
    private static final String ACTION_DELETE_DECLARED_INCOME_DOCUMENT = 'deleteDeclaredIncomeDocument';
    private static final String UPDATE_ON_OFFER_ENGINE = 'updateLineItemOnOfferEngine';

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_FETCH_INCOME_DETAILS_CONTEXT.equalsIgnoreCase(action)) {
            return fetchIncomeDetailsContextInternal(args);
        }
        if (ACTION_GET_DECLARED_INCOME_DETAILS.equalsIgnoreCase(action)) {
            return getDeclaredIncomeDetailsInternal(args);
        }
        if (ACTION_SAVE_DECLARED_INCOME_DETAILS.equalsIgnoreCase(action)) {
            return saveDeclaredIncomeDetailsInternal(args);
        }
        if (ACTION_UPSERT_DECLARED_INCOME_DOCUMENT.equalsIgnoreCase(action)) {
            return upsertDeclaredIncomeDocumentInternal(args);
        }
        if (ACTION_GET_DECLARED_INCOME_DOCUMENT.equalsIgnoreCase(action)) {
            return getDeclaredIncomeDocumentInternal(args);
        }
        if (ACTION_DELETE_DECLARED_INCOME_DOCUMENT.equalsIgnoreCase(action)) {
            return deleteDeclaredIncomeDocumentInternal(args);
        }
        if (UPDATE_ON_OFFER_ENGINE.equalsIgnoreCase(action)) {
            return updateLineItemOnOfferEngine(args);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    private static Map<String, Object> fetchIncomeDetailsContextInternal(Map<String, Object> args) {
        String applicationId = getStringArg(args, 'recordId');
        if (String.isBlank(applicationId)) {
            applicationId = getStringArg(args, 'applicationId');
        }
        String applicantId = getStringArg(args, 'applicantId');

        Map<String, Object> result = new Map<String, Object>();
        if (String.isBlank(applicationId)) {
            return result;
        }

        List<Application__c> apps = [
            SELECT Id, Sub_Stage__c, Stage__c, Product__c, OwnerId, (SELECT Id FROM Application_Line_Items__r LIMIT 1)
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return result;
        }

        Application__c app = apps[0];
        Boolean isIncomeDetailsStage = STAGE_INCOME_DETAILS.equalsIgnoreCase(app.Sub_Stage__c);

        String applicationType;
        List<Applicant__c> currentApplicant = new List<Applicant__c>([
            SELECT Type__c, Phone__c, Contact_number__c
            FROM Applicant__c
                WHERE Application__c = :applicationId AND Id = :applicantId AND in_active_applicant__c = false
                WITH SECURITY_ENFORCED
                LIMIT 1
            ]
        );
        applicationType = currentApplicant.isEmpty() ? null : currentApplicant[0].Type__c;

        result.put('subStage', app.Sub_Stage__c);
        result.put('stage', app.Stage__c);
        result.put('product', app.Product__c);
        result.put('applicationType', applicationType);
        result.put('canEdit', isIncomeDetailsStage);
        result.put('assetId', resolveAssetId(applicantId));
        result.put('applicantPhone', currentApplicant.isEmpty() ? null : currentApplicant[0].Phone__c != null ? currentApplicant[0].Phone__c : currentApplicant[0].Contact_number__c);
        result.put('applicantName', resolveApplicantName(applicantId));
        result.put('finalTermId', app.Application_Line_Items__r.isEmpty() ? null : app.Application_Line_Items__r[0].Id);
        return result;
    }
    
    private static Map<String, Object> getDeclaredIncomeDetailsInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID cannot be blank');
        }

        List<Applicant__c> applicants = [
            SELECT Declared_income__c
            FROM Applicant__c
            WHERE Id = :applicantId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (applicants.isEmpty()) {
            throw new AuraHandledException('Applicant not found.');
        }

        Applicant__c applicant = applicants[0];
        Applicant_Income__c incomeRecord = queryDeclaredIncomeRecord(applicantId);
        Map<String, Object> documentResult = resolveDeclaredIncomeDocument(applicantId, incomeRecord);

        Boolean hasDocument = documentResult != null && (Boolean) documentResult.get('found');
        Decimal consolidatedYearlyIncome = resolveConsolidatedYearlyIncome(incomeRecord, applicant);

        Map<String, Object> result = new Map<String, Object>{
            'status' => resolveDeclaredIncomeStatus(consolidatedYearlyIncome, hasDocument),
            'incomeMethod' => INCOME_RECORD_NAME,
            'consolidatedYearlyIncome' => consolidatedYearlyIncome
        };

        if (incomeRecord != null) {
            result.put('applicantIncomeId', incomeRecord.Id);
        }
        result.put('document', documentResult);
        return result;
    }

    private static Map<String, Object> saveDeclaredIncomeDetailsInternal(Map<String, Object> args) {
        String applicationId = getStringArg(args, 'recordId');
        if (String.isBlank(applicationId)) {
            applicationId = getStringArg(args, 'applicationId');
        }
        String applicantId = getStringArg(args, 'applicantId');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID cannot be blank');
        }

        Map<String, Object> payload = parseDataPayload(args);
        Decimal consolidatedYearlyIncome = getDecimalValue(payload.get('consolidatedYearlyIncome'));
        if (consolidatedYearlyIncome == null || consolidatedYearlyIncome < 0) {
            throw new AuraHandledException('Please enter a valid Consolidated Yearly Income.');
        }

        Applicant_Income__c incomeRecord = resolveDeclaredIncomeRecord(applicantId);
        incomeRecord.Consolidated_Yearly_Income__c = consolidatedYearlyIncome;
        upsert incomeRecord;

        Applicant__c applicant = new Applicant__c(
            Id = applicantId,
            Declared_income__c = consolidatedYearlyIncome
        );
        update applicant;

        Map<String, Object> documentResult = resolveDeclaredIncomeDocument(applicantId, incomeRecord);
        if (documentResult == null || !(Boolean) documentResult.get('found')) {
            throw new AuraHandledException('Please upload declared income document.');
        }

        return new Map<String, Object>{
            'isSuccess' => true,
            'applicantIncomeId' => incomeRecord.Id,
            'status' => STATUS_SAVED,
            'consolidatedYearlyIncome' => consolidatedYearlyIncome
        };
    }

    private static Map<String, Object> upsertDeclaredIncomeDocumentInternal(Map<String, Object> args) {
        String applicationId = getStringArg(args, 'recordId');
        if (String.isBlank(applicationId)) {
            applicationId = getStringArg(args, 'applicationId');
        }
        String applicantId = getStringArg(args, 'applicantId');
        Id contentDocumentId = (Id) args.get('contentDocumentId');
        Id contentVersionId = (Id) args.get('contentVersionId');
        String fileName = getStringArg(args, 'fileName');

        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID cannot be blank');
        }
        if (contentVersionId == null) {
            throw new AuraHandledException('Uploaded document reference is missing.');
        }

        Applicant_Income__c incomeRecord = resolveDeclaredIncomeRecord(applicantId);

        Document_Checklist__c checklist = new Document_Checklist__c();
        List<Document_Checklist__c> existing = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Applicant_Income__c = :incomeRecord.Id
                AND Document_Type__c = :DOC_TYPE_BANK_STATEMENT
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            checklist.Id = existing[0].Id;
        }

        checklist.Application__c = applicationId;
        checklist.Applicant__c = applicantId;
        checklist.Applicant_Income__c = incomeRecord.Id;
        checklist.Document_Type__c = DOC_TYPE_BANK_STATEMENT;
        checklist.ContentVersionId__c = contentVersionId;
        if (String.isNotBlank(fileName)) {
            checklist.Name = fileName;
        }
        upsert checklist;

        return new Map<String, Object>{
            'isSuccess' => true,
            'applicantIncomeId' => incomeRecord.Id,
            'checklistId' => checklist.Id,
            'contentDocumentId' => contentDocumentId,
            'contentVersionId' => contentVersionId,
            'fileName' => fileName
        };
    }

    private static Map<String, Object> getDeclaredIncomeDocumentInternal(Map<String, Object> args) {
        String applicantIncomeId = getStringArg(args, 'applicantIncomeId');
        String applicantId = getStringArg(args, 'applicantId');

        if (String.isNotBlank(applicantIncomeId)) {
            return getDocumentByApplicantIncomeId(applicantIncomeId);
        }
        if (String.isNotBlank(applicantId)) {
            Applicant_Income__c incomeRecord = queryDeclaredIncomeRecord(applicantId);
            return resolveDeclaredIncomeDocument(applicantId, incomeRecord);
        }
        return new Map<String, Object>{ 'found' => false };
    }

    private static Map<String, Object> deleteDeclaredIncomeDocumentInternal(Map<String, Object> args) {
        String applicantIncomeId = getStringArg(args, 'applicantIncomeId');
        String applicantId = getStringArg(args, 'applicantId');

        List<Document_Checklist__c> rows = new List<Document_Checklist__c>();
        if (String.isNotBlank(applicantIncomeId)) {
            rows = [
                SELECT Id
                FROM Document_Checklist__c
                WHERE Applicant_Income__c = :applicantIncomeId
                    AND Document_Type__c = :DOC_TYPE_BANK_STATEMENT
                WITH SECURITY_ENFORCED
            ];
        } else if (String.isNotBlank(applicantId)) {
            rows = [
                SELECT Id
                FROM Document_Checklist__c
                WHERE Applicant__c = :applicantId
                    AND Document_Type__c = :DOC_TYPE_BANK_STATEMENT
                WITH SECURITY_ENFORCED
            ];
        }

        if (!rows.isEmpty()) {
            delete rows;
        }
        return new Map<String, Object>{ 'isSuccess' => true };
    }

    private static Applicant_Income__c queryDeclaredIncomeRecord(String applicantId) {
        List<Applicant_Income__c> records = [
            SELECT Id, Name, Applicant__c, Consolidated_Yearly_Income__c
            FROM Applicant_Income__c
            WHERE Applicant__c = :applicantId
                AND Name = :INCOME_RECORD_NAME
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    private static Decimal resolveConsolidatedYearlyIncome(
        Applicant_Income__c incomeRecord,
        Applicant__c applicant
    ) {
        if (incomeRecord != null && incomeRecord.Consolidated_Yearly_Income__c != null) {
            return incomeRecord.Consolidated_Yearly_Income__c;
        }
        return applicant != null ? applicant.Declared_income__c : null;
    }

    private static Applicant_Income__c resolveDeclaredIncomeRecord(String applicantId) {
        Applicant_Income__c incomeRecord = queryDeclaredIncomeRecord(applicantId);
        if (incomeRecord != null) {
            return incomeRecord;
        }
        incomeRecord = new Applicant_Income__c(
            Applicant__c = applicantId,
            Name = INCOME_RECORD_NAME
        );
        insert incomeRecord;
        return incomeRecord;
    }

    private static Map<String, Object> resolveDeclaredIncomeDocument(
        String applicantId,
        Applicant_Income__c incomeRecord
    ) {
        if (incomeRecord != null) {
            Map<String, Object> byIncome = getDocumentByApplicantIncomeId(incomeRecord.Id);
            if ((Boolean) byIncome.get('found')) {
                return byIncome;
            }
        }
        return getDocumentByApplicantId(applicantId);
    }

    private static Map<String, Object> getDocumentByApplicantIncomeId(Id applicantIncomeId) {
        List<Document_Checklist__c> rows = [
            SELECT Id, Name, ContentVersionId__c
            FROM Document_Checklist__c
            WHERE Applicant_Income__c = :applicantIncomeId
                AND Document_Type__c = :DOC_TYPE_BANK_STATEMENT
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new Map<String, Object>{ 'found' => false };
        }
        return buildDocumentResult(rows[0]);
    }

    private static Map<String, Object> getDocumentByApplicantId(String applicantId) {
        List<Document_Checklist__c> rows = [
            SELECT Id, Name, ContentVersionId__c, Applicant_Income__c
            FROM Document_Checklist__c
            WHERE Applicant__c = :applicantId
                AND Document_Type__c = :DOC_TYPE_BANK_STATEMENT
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new Map<String, Object>{ 'found' => false };
        }
        Map<String, Object> result = buildDocumentResult(rows[0]);
        if (rows[0].Applicant_Income__c != null) {
            result.put('applicantIncomeId', rows[0].Applicant_Income__c);
        }
        return result;
    }

    private static Map<String, Object> buildDocumentResult(Document_Checklist__c row) {
        return new Map<String, Object>{
            'found' => true,
            'checklistId' => row.Id,
            'contentVersionId' => row.ContentVersionId__c,
            'fileName' => row.Name
        };
    }

    private static String resolveDeclaredIncomeStatus(Decimal declaredIncome, Boolean hasDocument) {
        if (declaredIncome != null && hasDocument) {
            return STATUS_SAVED;
        }
        return STATUS_NOT_STARTED;
    }

    private static Id resolveAssetId(String applicantId) {
        if (String.isBlank(applicantId)) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT Id
            FROM Asset__c
            WHERE Applicant__c = :applicantId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Id;
    }

    private static String resolveApplicantName(String applicantId) {
        if (String.isBlank(applicantId)) {
            return null;
        }
        List<Applicant__c> applicants = [
            SELECT Customer_First_Name__c,
            Customer_Last_Name__c
            FROM Applicant__c
            WHERE Id = :applicantId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return applicants.isEmpty() || String.isBlank(applicants[0].Customer_First_Name__c)
            ? null
            : applicants[0].Customer_First_Name__c + ' ' + applicants[0].Customer_Last_Name__c;
    }

    private static Map<String, Object> parseDataPayload(Map<String, Object> args) {
        Object rawData = args != null ? args.get('data') : null;
        if (rawData instanceof Map<String, Object>) {
            return (Map<String, Object>) rawData;
        }
        if (rawData == null) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(String.valueOf(rawData));
    }

    private static String getStringArg(Map<String, Object> args, String key) {
        if (args == null || !args.containsKey(key) || args.get(key) == null) {
            return null;
        }
        return String.valueOf(args.get(key));
    }

    private static Decimal getDecimalValue(Object value) {
        if (value == null) {
            return null;
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    @AuraEnabled
    public static Map<String, Object> updateLineItemOnOfferEngine(Map<String, Object> args) {
        String applicationId = getStringArg(args, 'applicationId');
        String applicationLineItemId = getStringArg(args, 'applicationLineItemId');

       //Take loan amount, tenure and IRR from vehicle and update on line item
       List<Asset__c> assets = [
        SELECT Id, Required_EMI__c, Required_Tenure__c, Required_CRM_IRR__c, Required_Total_Loan_Amount__c
        FROM Asset__c
        WHERE Applicant__r.Application__c = :applicationId
        WITH SECURITY_ENFORCED
        LIMIT 1
       ];
       if (assets.isEmpty()) {
        return new Map<String, Object>{ 'isSuccess' => false, 'message' => 'Asset not found.' };
       }
       Asset__c asset = assets[0];
       Application_Line_Item__c lineItem = [
        SELECT Id, Loan_Amount__c, Tenure__c, CRM_IRR__c
        FROM Application_Line_Item__c
        WHERE Id = :applicationLineItemId
        WITH SECURITY_ENFORCED
        LIMIT 1
       ];
       if (lineItem == null) {
        return new Map<String, Object>{ 'isSuccess' => false, 'message' => 'Line item not found.' };
       }
       lineItem.Loan_Amount__c = lineItem.Loan_Amount__c != null ? lineItem.Loan_Amount__c : asset.Required_Total_Loan_Amount__c;
       lineItem.Tenure__c = lineItem.Tenure__c != null ? lineItem.Tenure__c : asset.Required_Tenure__c;
       lineItem.CRM_IRR__c = lineItem.CRM_IRR__c != null ? lineItem.CRM_IRR__c : asset.Required_CRM_IRR__c;
       update lineItem;
       return new Map<String, Object>{
        'isSuccess' => true,
        'lineItemId' => lineItem.Id
       };
    }
        
}