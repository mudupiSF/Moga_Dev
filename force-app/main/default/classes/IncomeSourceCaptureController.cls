public with sharing class IncomeSourceCaptureController implements Callable {

    private static final String DECLARED_INCOME_NAME = 'Declared Income';

    private static final String ACTION_GET_INCOME_SOURCES = 'getIncomeSources';
    private static final String ACTION_SAVE_INCOME_SOURCE = 'saveIncomeSource';
    private static final String ACTION_DELETE_INCOME_SOURCE = 'deleteIncomeSource';
    private static final String ACTION_GET_INCOME_SOURCE_DOCUMENT = 'getIncomeSourceDocument';
    private static final String ACTION_UPSERT_INCOME_SOURCE_DOCUMENT = 'upsertIncomeSourceDocument';
    private static final String ACTION_DELETE_INCOME_SOURCE_DOCUMENT = 'deleteIncomeSourceDocument';

    private static final Set<String> VALID_INCOME_SOURCES = new Set<String>{
        'ITR',
        'Financials',
        'Agricultural Income',
        'Property Income',
        'Banking',
        'GST'
    };

    private static final Map<String, String> DOCUMENT_TYPE_BY_INCOME_SOURCE = new Map<String, String>{
        'ITR' => 'ITR or Form 16',
        'Financials' => 'Financial Statements',
        'Banking' => 'Bank Statements',
        'Property Income' => 'Property Documents',
        'Agricultural Income' => 'Agricultural Income Documents',
        'GST' => 'GST Documents'
    };

    private static final String INCOME_SOURCE_QUERY_FIELDS =
        'Id, Name, Applicant__c, Income_Source__c, Primary_Income_Source__c, ' +
        'Assessment_Year__c, ITR_Last_Year_Date__c, Income_Last_Year__c, Do_you_have_another_ITR__c, ' +
        'Financial_Year__c, Total_Income__c, Total_Expense__c, PBT__c, PAT__c, Cash_Profit__c, ' +
        'Shareholder_funds__c, Secured_Loans__c, Working_Capital__c, Unsecured_Loans__c, ' +
        'Current_Liabilities__c, Sundry_Creditors__c, Current_Assets__c, Sundry_Debtors__c, ' +
        'Fixed_Assets__c, Non_Current_Assets__c, Cash_and_Bank_Balances__c, ' +
        'Do_you_have_previous_year_financial_entr__c, Property_Area_Unit__c, Property_Area__c, ' +
        'Agriculture_Unit__c, Crops_Per_Year__c, Yield_Per_Acre__c, Price_Per_Unit__c, ' +
        'Agricultural_Income__c, Type_of_Property__c, Survey_Number_Address__c, Market_Value__c, ' +
        'Ownership__c, Income_from_Property__c, Proof_Given__c, Income_Detail_Bank_Master__c, ' +
        'Bank_Branch__c, Account_Number__c, Account_Opening_Date__c, Last_Month_Day_1__c, ' +
        'Last_Month_Day_10__c, Last_Month_Day_20__c, Last_2nd_Month_Day_1__c, Last_2nd_Month_Day_10__c, ' +
        'Last_2nd_Month_Day_20__c, Last_3rd_Month_Day_1__c, Last_3rd_Month_Day_10__c, Last_3rd_Month_Day_20__c';

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_GET_INCOME_SOURCES.equalsIgnoreCase(action)) {
            return getIncomeSourcesInternal(args);
        }
        if (ACTION_SAVE_INCOME_SOURCE.equalsIgnoreCase(action)) {
            return saveIncomeSourceInternal(args);
        }
        if (ACTION_DELETE_INCOME_SOURCE.equalsIgnoreCase(action)) {
            return deleteIncomeSourceInternal(args);
        }
        if (ACTION_GET_INCOME_SOURCE_DOCUMENT.equalsIgnoreCase(action)) {
            return getIncomeSourceDocumentInternal(args);
        }
        if (ACTION_UPSERT_INCOME_SOURCE_DOCUMENT.equalsIgnoreCase(action)) {
            return upsertIncomeSourceDocumentInternal(args);
        }
        if (ACTION_DELETE_INCOME_SOURCE_DOCUMENT.equalsIgnoreCase(action)) {
            return deleteIncomeSourceDocumentInternal(args);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    private static Map<String, Object> getIncomeSourcesInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID cannot be blank');
        }

        String soql = 'SELECT ' + INCOME_SOURCE_QUERY_FIELDS +
            ' FROM Applicant_Income__c WHERE Applicant__c = :applicantId' +
            ' AND Income_Source__c != null WITH SECURITY_ENFORCED ORDER BY CreatedDate ASC';

        List<Applicant_Income__c> records = Database.query(soql);
        Map<String, List<Applicant_Income__c>> recordsBySource = new Map<String, List<Applicant_Income__c>>();
        for (Applicant_Income__c record : records) {
            if (!recordsBySource.containsKey(record.Income_Source__c)) {
                recordsBySource.put(record.Income_Source__c, new List<Applicant_Income__c>());
            }
            recordsBySource.get(record.Income_Source__c).add(record);
        }

        List<Map<String, Object>> incomeSources = new List<Map<String, Object>>();
        Integer index = 0;
        for (String sourceType : recordsBySource.keySet()) {
            index++;
            List<Applicant_Income__c> sourceRecords = recordsBySource.get(sourceType);
            incomeSources.add(buildIncomeSourceWrapper(index, sourceType, sourceRecords));
        }

        return new Map<String, Object>{ 'incomeSources' => incomeSources };
    }

    private static Map<String, Object> saveIncomeSourceInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID cannot be blank');
        }

        Map<String, Object> payload = parseDataPayload(args);
        String incomeSource = getStringArg(payload, 'incomeSource');
        if (String.isBlank(incomeSource) || !VALID_INCOME_SOURCES.contains(incomeSource)) {
            throw new AuraHandledException('Please select a valid income source.');
        }

        Boolean primaryIncomeSource = getBooleanValue(payload.get('primaryIncomeSource'));
        List<Applicant_Income__c> recordsToUpsert = new List<Applicant_Income__c>();

        if ('ITR'.equals(incomeSource)) {
            List<Object> itrSections = (List<Object>) payload.get('itrSections');
            if (itrSections == null || itrSections.isEmpty()) {
                throw new AuraHandledException('Please enter ITR details.');
            }
            for (Object sectionObj : itrSections) {
                Map<String, Object> section = (Map<String, Object>) sectionObj;
                Applicant_Income__c record = buildBaseRecord(applicantId, incomeSource, primaryIncomeSource);
                Object recordId = section.get('recordId');
                if (isSalesforceId(recordId)) {
                    record.Id = (Id) recordId;
                }
                record.Assessment_Year__c = getStringArg(section, 'assessmentYear');
                record.ITR_Last_Year_Date__c = getDateValue(section.get('itrLastYearDate'));
                record.Income_Last_Year__c = getDecimalValue(section.get('incomeLastYear'));
                record.Do_you_have_another_ITR__c = getBooleanValue(section.get('doYouHaveAnotherITR'));
                recordsToUpsert.add(record);
            }
        } else {
            Applicant_Income__c record = buildBaseRecord(applicantId, incomeSource, primaryIncomeSource);
            Object recordId = payload.get('recordId');
            if (isSalesforceId(recordId)) {
                record.Id = (Id) recordId;
            }
            mapNonItrFields(record, payload);
            recordsToUpsert.add(record);
        }

        if (primaryIncomeSource == true) {
            clearPrimaryIncomeSource(applicantId);
        }

        upsert recordsToUpsert;

        Id documentIncomeId = recordsToUpsert[0].Id;
        Map<String, Object> documentResult = getDocumentByApplicantIncomeId(
            documentIncomeId,
            DOCUMENT_TYPE_BY_INCOME_SOURCE.get(incomeSource)
        );
        if (documentResult == null || !(Boolean) documentResult.get('found')) {
            throw new AuraHandledException(
                'Please upload ' + DOCUMENT_TYPE_BY_INCOME_SOURCE.get(incomeSource) + '.'
            );
        }

        List<Map<String, Object>> refreshedSources = (List<Map<String, Object>>) getIncomeSourcesInternal(
            new Map<String, Object>{ 'applicantId' => applicantId }
        ).get('incomeSources');

        Map<String, Object> savedSource = null;
        for (Map<String, Object> source : refreshedSources) {
            if (incomeSource.equals(source.get('incomeSource'))) {
                savedSource = source;
                break;
            }
        }

        return new Map<String, Object>{
            'isSuccess' => true,
            'incomeSource' => savedSource
        };
    }

    private static Map<String, Object> deleteIncomeSourceInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        String incomeSource = getStringArg(args, 'incomeSource');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID cannot be blank');
        }
        if (String.isBlank(incomeSource) || !VALID_INCOME_SOURCES.contains(incomeSource)) {
            throw new AuraHandledException('Income source is required.');
        }

        List<Applicant_Income__c> records = [
            SELECT Id
            FROM Applicant_Income__c
            WHERE Applicant__c = :applicantId
                AND Income_Source__c = :incomeSource
            WITH SECURITY_ENFORCED
        ];

        if (!records.isEmpty()) {
            delete records;
        }

        String documentType = DOCUMENT_TYPE_BY_INCOME_SOURCE.get(incomeSource);
        List<Document_Checklist__c> documents = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Applicant__c = :applicantId
                AND Document_Type__c = :documentType
            WITH SECURITY_ENFORCED
        ];
        if (!documents.isEmpty()) {
            delete documents;
        }

        return new Map<String, Object>{ 'isSuccess' => true };
    }

    private static Map<String, Object> getIncomeSourceDocumentInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        String incomeSource = getStringArg(args, 'incomeSource');
        String applicantIncomeId = getStringArg(args, 'applicantIncomeId');

        if (String.isNotBlank(applicantIncomeId)) {
            return getDocumentByApplicantIncomeId(
                applicantIncomeId,
                DOCUMENT_TYPE_BY_INCOME_SOURCE.get(incomeSource)
            );
        }

        if (String.isBlank(applicantId) || String.isBlank(incomeSource)) {
            return new Map<String, Object>{ 'found' => false };
        }

        List<Applicant_Income__c> records = [
            SELECT Id
            FROM Applicant_Income__c
            WHERE Applicant__c = :applicantId
                AND Income_Source__c = :incomeSource
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (records.isEmpty()) {
            return new Map<String, Object>{ 'found' => false };
        }

        return getDocumentByApplicantIncomeId(
            records[0].Id,
            DOCUMENT_TYPE_BY_INCOME_SOURCE.get(incomeSource)
        );
    }

    private static Map<String, Object> upsertIncomeSourceDocumentInternal(Map<String, Object> args) {
        String applicationId = getStringArg(args, 'recordId');
        if (String.isBlank(applicationId)) {
            applicationId = getStringArg(args, 'applicationId');
        }
        String applicantId = getStringArg(args, 'applicantId');
        String incomeSource = getStringArg(args, 'incomeSource');
        Id contentDocumentId = (Id) args.get('contentDocumentId');
        Id contentVersionId = (Id) args.get('contentVersionId');
        String fileName = getStringArg(args, 'fileName');

        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID cannot be blank');
        }
        if (String.isBlank(incomeSource) || !VALID_INCOME_SOURCES.contains(incomeSource)) {
            throw new AuraHandledException('Income source is required.');
        }
        if (contentVersionId == null) {
            throw new AuraHandledException('Uploaded document reference is missing.');
        }

        String documentType = DOCUMENT_TYPE_BY_INCOME_SOURCE.get(incomeSource);
        Applicant_Income__c incomeRecord = resolveIncomeSourceRecord(applicantId, incomeSource);

        Document_Checklist__c checklist = new Document_Checklist__c();
        List<Document_Checklist__c> existing = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Applicant_Income__c = :incomeRecord.Id
                AND Document_Type__c = :documentType
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            checklist.Id = existing[0].Id;
        }

        checklist.Application__c = applicationId;
        checklist.Applicant__c = applicantId;
        checklist.Applicant_Income__c = incomeRecord.Id;
        checklist.Document_Type__c = documentType;
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

    private static Map<String, Object> deleteIncomeSourceDocumentInternal(Map<String, Object> args) {
        String applicantIncomeId = getStringArg(args, 'applicantIncomeId');
        String incomeSource = getStringArg(args, 'incomeSource');

        if (String.isBlank(applicantIncomeId) || String.isBlank(incomeSource)) {
            throw new AuraHandledException('Income source record is required.');
        }

        String documentType = DOCUMENT_TYPE_BY_INCOME_SOURCE.get(incomeSource);
        List<Document_Checklist__c> rows = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Applicant_Income__c = :applicantIncomeId
                AND Document_Type__c = :documentType
            WITH SECURITY_ENFORCED
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }

        return new Map<String, Object>{ 'isSuccess' => true };
    }

    public static Applicant_Income__c resolveIncomeSourceRecord(String applicantId, String incomeSource) {
        List<Applicant_Income__c> records = [
            SELECT Id
            FROM Applicant_Income__c
            WHERE Applicant__c = :applicantId
                AND Income_Source__c = :incomeSource
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (!records.isEmpty()) {
            return records[0];
        }

        Applicant_Income__c incomeRecord = buildBaseRecord(applicantId, incomeSource, false);
        insert incomeRecord;
        return incomeRecord;
    }

    private static Applicant_Income__c buildBaseRecord(
        String applicantId,
        String incomeSource,
        Boolean primaryIncomeSource
    ) {
        return new Applicant_Income__c(
            Applicant__c = applicantId,
            Name = incomeSource,
            Income_Source__c = incomeSource,
            Primary_Income_Source__c = primaryIncomeSource == true
        );
    }

    private static void mapNonItrFields(Applicant_Income__c record, Map<String, Object> payload) {
        record.Financial_Year__c = getStringArg(payload, 'financialYear');
        record.Total_Income__c = getDecimalValue(payload.get('totalIncome'));
        record.Total_Expense__c = getDecimalValue(payload.get('totalExpense'));
        record.PBT__c = getDecimalValue(payload.get('pbtValue'));
        record.PAT__c = getDecimalValue(payload.get('patValue'));
        record.Cash_Profit__c = getDecimalValue(payload.get('cashProfit'));
        record.Shareholder_funds__c = getDecimalValue(payload.get('shareholderFunds'));
        record.Secured_Loans__c = getDecimalValue(payload.get('securedLoans'));
        record.Working_Capital__c = getDecimalValue(payload.get('workingCapital'));
        record.Unsecured_Loans__c = getDecimalValue(payload.get('unsecuredLoans'));
        record.Current_Liabilities__c = getDecimalValue(payload.get('currentLiabilities'));
        record.Sundry_Creditors__c = getDecimalValue(payload.get('sundryCreditors'));
        record.Current_Assets__c = getDecimalValue(payload.get('currentAssets'));
        record.Sundry_Debtors__c = getDecimalValue(payload.get('sundryDebtors'));
        record.Fixed_Assets__c = getDecimalValue(payload.get('fixedAssets'));
        record.Non_Current_Assets__c = getDecimalValue(payload.get('nonCurrentAssets'));
        record.Cash_and_Bank_Balances__c = getDecimalValue(payload.get('cashAndBankBalances'));
        record.Do_you_have_previous_year_financial_entr__c = getStringArg(payload, 'financialAnotherEntry');
        record.Property_Area_Unit__c = getStringArg(payload, 'propertyAreaUnit');
        record.Property_Area__c = getDecimalValue(payload.get('propertyArea'));
        record.Agriculture_Unit__c = getDecimalValue(payload.get('acreUnit'));
        record.Crops_Per_Year__c = getStringArg(payload, 'cropsPerYear');
        record.Yield_Per_Acre__c = getDecimalValue(payload.get('yieldPerAcre'));
        record.Price_Per_Unit__c = getDecimalValue(payload.get('pricePerUnit'));
        record.Agricultural_Income__c = getDecimalValue(payload.get('agriculturalIncome'));
        record.Type_of_Property__c = getStringArg(payload, 'typeOfProperty');
        record.Survey_Number_Address__c = getStringArg(payload, 'surveyNumberAddress');
        record.Market_Value__c = getDecimalValue(payload.get('marketValue'));
        record.Ownership__c = getStringArg(payload, 'ownership');
        record.Income_from_Property__c = getDecimalValue(payload.get('incomeFromProperty'));
        record.Proof_Given__c = getStringArg(payload, 'proofGiven');
        record.Income_Detail_Bank_Master__c = isSalesforceId(payload.get('bankName'))
            ? (Id) payload.get('bankName')
            : null;
        record.Bank_Branch__c = getStringArg(payload, 'bankBranch');
        record.Account_Number__c = getStringArg(payload, 'accountNumber');
        record.Account_Opening_Date__c = getDateValue(payload.get('accountOpeningDate'));

        Map<String, Object> last3MonthsValues = (Map<String, Object>) payload.get('last3MonthsValues');
        if (last3MonthsValues != null) {
            record.Last_Month_Day_1__c = getDecimalValue(last3MonthsValues.get('lastMonthDay1'));
            record.Last_Month_Day_10__c = getDecimalValue(last3MonthsValues.get('lastMonthDay10'));
            record.Last_Month_Day_20__c = getDecimalValue(last3MonthsValues.get('lastMonthDay20'));
            record.Last_2nd_Month_Day_1__c = getDecimalValue(last3MonthsValues.get('last2ndMonthDay1'));
            record.Last_2nd_Month_Day_10__c = getDecimalValue(last3MonthsValues.get('last2ndMonthDay10'));
            record.Last_2nd_Month_Day_20__c = getDecimalValue(last3MonthsValues.get('last2ndMonthDay20'));
            record.Last_3rd_Month_Day_1__c = getDecimalValue(last3MonthsValues.get('last3rdMonthDay1'));
            record.Last_3rd_Month_Day_10__c = getDecimalValue(last3MonthsValues.get('last3rdMonthDay10'));
            record.Last_3rd_Month_Day_20__c = getDecimalValue(last3MonthsValues.get('last3rdMonthDay20'));
        }
    }

    private static Map<String, Object> buildIncomeSourceWrapper(
        Integer index,
        String sourceType,
        List<Applicant_Income__c> sourceRecords
    ) {
        Applicant_Income__c primaryRecord = sourceRecords[0];
        Map<String, Object> wrapper = new Map<String, Object>{
            'id' => String.valueOf(index),
            'heading' => 'Income Source ' + index,
            'isOpen' => true,
            'incomeSource' => sourceType,
            'recordId' => primaryRecord.Id,
            'primaryIncomeSource' => primaryRecord.Primary_Income_Source__c == true,
            'documentUploaded' => false
        };

        if ('ITR'.equals(sourceType)) {
            List<Map<String, Object>> itrSections = new List<Map<String, Object>>();
            Integer sectionIndex = 0;
            for (Applicant_Income__c record : sourceRecords) {
                itrSections.add(new Map<String, Object>{
                    'id' => sectionIndex,
                    'recordId' => record.Id,
                    'assessmentYear' => record.Assessment_Year__c,
                    'itrLastYearDate' => formatDate(record.ITR_Last_Year_Date__c),
                    'incomeLastYear' => record.Income_Last_Year__c,
                    'doYouHaveAnotherITR' => record.Do_you_have_another_ITR__c == true
                });
                sectionIndex++;
            }
            wrapper.put('itrSections', itrSections);
        } else {
            mapRecordToWrapper(wrapper, primaryRecord);
        }

        Map<String, Object> documentResult = getDocumentByApplicantIncomeId(
            primaryRecord.Id,
            DOCUMENT_TYPE_BY_INCOME_SOURCE.get(sourceType)
        );
        wrapper.put('documentUploaded', documentResult != null && (Boolean) documentResult.get('found'));
        if (documentResult != null && (Boolean) documentResult.get('found')) {
            wrapper.put('document', documentResult);
        }

        return wrapper;
    }

    private static void mapRecordToWrapper(Map<String, Object> wrapper, Applicant_Income__c record) {
        wrapper.put('financialYear', record.Financial_Year__c);
        wrapper.put('totalIncome', record.Total_Income__c);
        wrapper.put('totalExpense', record.Total_Expense__c);
        wrapper.put('pbtValue', record.PBT__c);
        wrapper.put('patValue', record.PAT__c);
        wrapper.put('cashProfit', record.Cash_Profit__c);
        wrapper.put('shareholderFunds', record.Shareholder_funds__c);
        wrapper.put('securedLoans', record.Secured_Loans__c);
        wrapper.put('workingCapital', record.Working_Capital__c);
        wrapper.put('unsecuredLoans', record.Unsecured_Loans__c);
        wrapper.put('currentLiabilities', record.Current_Liabilities__c);
        wrapper.put('sundryCreditors', record.Sundry_Creditors__c);
        wrapper.put('currentAssets', record.Current_Assets__c);
        wrapper.put('sundryDebtors', record.Sundry_Debtors__c);
        wrapper.put('fixedAssets', record.Fixed_Assets__c);
        wrapper.put('nonCurrentAssets', record.Non_Current_Assets__c);
        wrapper.put('cashAndBankBalances', record.Cash_and_Bank_Balances__c);
        wrapper.put('financialAnotherEntry', record.Do_you_have_previous_year_financial_entr__c);
        wrapper.put('propertyAreaUnit', record.Property_Area_Unit__c);
        wrapper.put('propertyArea', record.Property_Area__c);
        wrapper.put('acreUnit', record.Agriculture_Unit__c);
        wrapper.put('cropsPerYear', record.Crops_Per_Year__c);
        wrapper.put('yieldPerAcre', record.Yield_Per_Acre__c);
        wrapper.put('pricePerUnit', record.Price_Per_Unit__c);
        wrapper.put('agriculturalIncome', record.Agricultural_Income__c);
        wrapper.put('typeOfProperty', record.Type_of_Property__c);
        wrapper.put('surveyNumberAddress', record.Survey_Number_Address__c);
        wrapper.put('marketValue', record.Market_Value__c);
        wrapper.put('ownership', record.Ownership__c);
        wrapper.put('incomeFromProperty', record.Income_from_Property__c);
        wrapper.put('proofGiven', record.Proof_Given__c);
        wrapper.put('bankName', record.Income_Detail_Bank_Master__c);
        wrapper.put('bankBranch', record.Bank_Branch__c);
        wrapper.put('accountNumber', record.Account_Number__c);
        wrapper.put('accountOpeningDate', formatDate(record.Account_Opening_Date__c));
        wrapper.put('last3MonthsValues', new Map<String, Object>{
            'lastMonthDay1' => record.Last_Month_Day_1__c,
            'lastMonthDay10' => record.Last_Month_Day_10__c,
            'lastMonthDay20' => record.Last_Month_Day_20__c,
            'last2ndMonthDay1' => record.Last_2nd_Month_Day_1__c,
            'last2ndMonthDay10' => record.Last_2nd_Month_Day_10__c,
            'last2ndMonthDay20' => record.Last_2nd_Month_Day_20__c,
            'last3rdMonthDay1' => record.Last_3rd_Month_Day_1__c,
            'last3rdMonthDay10' => record.Last_3rd_Month_Day_10__c,
            'last3rdMonthDay20' => record.Last_3rd_Month_Day_20__c
        });
    }

    private static void clearPrimaryIncomeSource(String applicantId) {
        List<Applicant_Income__c> primaryRecords = [
            SELECT Id
            FROM Applicant_Income__c
            WHERE Applicant__c = :applicantId
                AND Primary_Income_Source__c = true
                AND Income_Source__c != null
            WITH SECURITY_ENFORCED
        ];
        for (Applicant_Income__c record : primaryRecords) {
            record.Primary_Income_Source__c = false;
        }
        if (!primaryRecords.isEmpty()) {
            update primaryRecords;
        }
    }

    private static Map<String, Object> getDocumentByApplicantIncomeId(
        Id applicantIncomeId,
        String documentType
    ) {
        if (applicantIncomeId == null || String.isBlank(documentType)) {
            return new Map<String, Object>{ 'found' => false };
        }

        List<Document_Checklist__c> rows = [
            SELECT Id, Name, ContentVersionId__c
            FROM Document_Checklist__c
            WHERE Applicant_Income__c = :applicantIncomeId
                AND Document_Type__c = :documentType
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new Map<String, Object>{ 'found' => false };
        }

        return new Map<String, Object>{
            'found' => true,
            'checklistId' => rows[0].Id,
            'contentVersionId' => rows[0].ContentVersionId__c,
            'fileName' => rows[0].Name,
            'applicantIncomeId' => applicantIncomeId
        };
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
        String value = String.valueOf(args.get(key));
        return String.isBlank(value) ? null : value;
    }

    private static Decimal getDecimalValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    private static Date getDateValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        return Date.valueOf(String.valueOf(value));
    }

    private static Boolean getBooleanValue(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return Boolean.valueOf(String.valueOf(value));
    }

    private static Boolean isSalesforceId(Object value) {
        if (value == null) {
            return false;
        }
        String idValue = String.valueOf(value);
        return idValue.length() == 15 || idValue.length() == 18;
    }

    private static String formatDate(Date value) {
        return value == null ? null : String.valueOf(value);
    }
}