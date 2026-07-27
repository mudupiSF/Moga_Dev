/**
 * @description Callable controller for finance grid (Financial Performance + GST).
 */
public with sharing class FinanceGridController implements Callable {

    private static final String ACTION_FETCH_FINANCIAL_PERFORMANCE_RECORDS = 'fetchFinancialPerformanceRecords';
    private static final String ACTION_SAVE_FINANCIAL_PERFORMANCE_RECORDS = 'saveFinancialPerformanceRecords';
    private static final String ACTION_SAVE_GST_RECORDS = 'saveGstRecords';
    private static final String ACTION_UPLOAD_FINANCIAL_PERFORMANCE_EXCEL = 'uploadFinancialPerformanceExcel';
    private static final String ACTION_DELETE_FINANCIAL_PERFORMANCE_EXCEL = 'deleteFinancialPerformanceExcel';

    private static final String DOC_TYPE_FINANCIAL_PERFORMANCE_EXCEL = 'Financial Performance Excel';
    private static final Integer MAX_EXCEL_BYTES = 6 * 1024 * 1024;

    private static final String FINANCIAL_PERFORMANCE_QUERY_FIELDS =
        'Id, Name, Application__c, CreatedDate, Profit_and_Loss_Account__c, Signing_CA_Member_No__c, ' +
        'UDIN_No__c, Revenue_from_operations__c, Other_Income__c, Cost_of_goods__c, Direct_Expenses__c, ' +
        'Employee_costs__c, Administration_Expenses__c, Selling_and_Distribution_Expenses__c, ' +
        'Financial_Expenses__c, Depreciation__c, Provision_for_tax__c, Preference_dividend_including_tax__c, ' +
        'Income__c, Expenses__c, Profit_before_tax__c, Profit_after_tax__c, ' +
        'Profit_available_for_equity_shareholders__c, Cash_profit__c, Equity_Capital__c, ' +
        'Share_Application_Money__c, Reserves_Surplus__c, Secured_loan__c, ' +
        'Secured_loans_OD_CC_Working_Capital__c, Unsecured_loans__c, Deffered_tax_liability__c, ' +
        'Other_long_term_liabilities__c, Current_Liabilities_and_Provision__c, Sundry_creditors__c, ' +
        'Other_current_liabilities_and_provisions__c, Fixed_Assets__c, Capital_WIP__c, Investments__c, ' +
        'Long_term_loans_and_advances__c, other_non_current_assets__c, Current_assets__c, Sundry_debtors__c, ' +
        'Closing_stock__c, Cash_and_bank_balances__c, Other_current_assets__c, Liabilities_Total__c, ' +
        'Assets_Total__c, Return_on_Capital_Employed__c, Return_On_Share_Holders_Fund__c, PAT_Income__c, ' +
        'PAT_Assets_employed__c, Interest_Coverage__c, Debt_Ratio__c, Debt_Equity__c, Current_Ratio__c, ' +
        'Quick_Asset_Ratio__c, Cash_Ratio__c, TOL_TNW__c, DSCR__c, Debtors_TO__c, Debtors_TO_Ratio__c, ' +
        'Debtor_days__c, Face_Value_of_Shares__c, EPS__c, Increase_in_TO__c, Increase_in_Cash_Profit__c';

    private static final String FP_CHILD_GST_SUBQUERY =
        ', (SELECT Id, RecordType.Name, RecordType.DeveloperName, RecordTypeId, Name_of_the_Client__c, Amount__c, Month__c ' +
        'FROM GST__r ORDER BY CreatedDate ASC)';

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_FETCH_FINANCIAL_PERFORMANCE_RECORDS.equalsIgnoreCase(action)) {
            return fetchFinancialPerformanceRecordsInternal(args);
        }
        if (ACTION_SAVE_FINANCIAL_PERFORMANCE_RECORDS.equalsIgnoreCase(action)) {
            return saveFinancialPerformanceRecordsInternal(args);
        }
        if (ACTION_SAVE_GST_RECORDS.equalsIgnoreCase(action)) {
            return saveGstRecordsInternal(args);
        }
        if (ACTION_UPLOAD_FINANCIAL_PERFORMANCE_EXCEL.equalsIgnoreCase(action)) {
            return uploadFinancialPerformanceExcelInternal(args);
        }
        if (ACTION_DELETE_FINANCIAL_PERFORMANCE_EXCEL.equalsIgnoreCase(action)) {
            return deleteFinancialPerformanceExcelInternal(args);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    private static Map<String, Object> fetchFinancialPerformanceRecordsInternal(Map<String, Object> args) {
        String applicationId = resolveApplicationId(args);
        if (String.isBlank(applicationId)) {
            throw new AuraHandledException('Application Id is required.');
        }

        if (!Financial_Performance__c.SObjectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Insufficient access to Financial Performance.');
        }

        String query =
            'SELECT ' +
            FINANCIAL_PERFORMANCE_QUERY_FIELDS +
            FP_CHILD_GST_SUBQUERY +
            ' FROM Financial_Performance__c WHERE Application__c = :applicationId' +
            ' ORDER BY CreatedDate ASC';

        List<Financial_Performance__c> rows = Database.query(query);
        SObjectAccessDecision readDecision = Security.stripInaccessible(AccessType.READABLE, rows);
        return new Map<String, Object>{
            'records' => readDecision.getRecords(),
            'excelDocument' => getFinancialPerformanceExcelDocument(applicationId)
        };
    }

    private static Map<String, Object> saveFinancialPerformanceRecordsInternal(Map<String, Object> args) {
        String recordsJson = getStringArg(args, 'data');
        if (String.isBlank(recordsJson)) {
            throw new AuraHandledException('No records to save.');
        }

        try {
            String applicationId = resolveApplicationId(args);
            if (String.isBlank(applicationId)) {
                throw new AuraHandledException('Application Id is required.');
            }

            List<Financial_Performance__c> records = (List<Financial_Performance__c>) JSON.deserialize(
                recordsJson,
                List<Financial_Performance__c>.class
            );
            List<Financial_Performance__c> validRecords = new List<Financial_Performance__c>();

            for (Financial_Performance__c fpRecord : records) {
                if (fpRecord != null) {
                    fpRecord.Application__c = applicationId;
                    validRecords.add(fpRecord);
                }
            }

            if (validRecords.isEmpty()) {
                throw new AuraHandledException('No records to save.');
            }

            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPSERTABLE,
                validRecords
            );
            upsert decision.getRecords();

            return new Map<String, Object>{ 'isSuccess' => true };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Map<String, Object> saveGstRecordsInternal(Map<String, Object> args) {
        String gstRecordsJson = getStringArg(args, 'data');
        String recordType = getStringArg(args, 'recordType');
        String financialPerformanceId = getStringArg(args, 'financialPerformanceId');

        if (String.isBlank(gstRecordsJson)) {
            throw new AuraHandledException('No GST records to save.');
        }
        if (String.isBlank(recordType)) {
            throw new AuraHandledException('GST record type is required.');
        }
        if (String.isBlank(financialPerformanceId)) {
            throw new AuraHandledException('Financial Performance record is required for GST.');
        }

        try {
            List<GST__c> records = (List<GST__c>) JSON.deserialize(gstRecordsJson, List<GST__c>.class);
            Id recordTypeId = resolveGstRecordTypeId(recordType);
            List<GST__c> preparedRecords = new List<GST__c>();

            for (GST__c record : records) {
                if (record == null) {
                    continue;
                }
                record.Financial_Performance__c = financialPerformanceId;
                if (record.Id == null) {
                    record.RecordTypeId = recordTypeId;
                }
                preparedRecords.add(record);
            }

            if (preparedRecords.isEmpty()) {
                throw new AuraHandledException('No valid GST records to save.');
            }

            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPSERTABLE, preparedRecords);
            List<GST__c> upsertRows = decision.getRecords();
            if (upsertRows.isEmpty()) {
                throw new AuraHandledException(
                    'Insufficient field access to save GST records. Check GST__c field permissions.'
                );
            }

            for (GST__c row : upsertRows) {
                if (row.Id == null) {
                    row.RecordTypeId = recordTypeId;
                }
                row.Financial_Performance__c = financialPerformanceId;
            }

            upsert upsertRows;

            return new Map<String, Object>{
                'isSuccess' => true,
                'gstRecords' => upsertRows
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Map<String, Object> uploadFinancialPerformanceExcelInternal(Map<String, Object> args) {
        String applicationId = resolveApplicationId(args);
        if (String.isBlank(applicationId)) {
            throw new AuraHandledException('Application Id is required.');
        }

        String fileName = getStringArg(args, 'fileName');
        String base64Body = getStringArg(args, 'base64Body');
        if (String.isBlank(base64Body)) {
            throw new AuraHandledException('Excel file data is missing.');
        }

        String normalizedBase64 = base64Body.contains(',') ? base64Body.substringAfterLast(',') : base64Body;
        Blob fileBody;
        try {
            fileBody = EncodingUtil.base64Decode(normalizedBase64);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid Excel file encoding.');
        }
        if (fileBody == null || fileBody.size() == 0) {
            throw new AuraHandledException('Excel file is empty.');
        }
        if (fileBody.size() > MAX_EXCEL_BYTES) {
            throw new AuraHandledException('Excel file is too large (maximum 6 MB).');
        }

        String safeName = String.isBlank(fileName) ? 'Financial_Performance.xlsx' : fileName.trim();
        Integer slash = safeName.lastIndexOf('/');
        Integer backslash = safeName.lastIndexOf('\\');
        Integer cut = slash > backslash ? slash : backslash;
        if (cut >= 0) {
            safeName = safeName.substring(cut + 1);
        }
        if (safeName.length() > 255) {
            safeName = safeName.substring(0, 255);
        }

        String titleBase = safeName;
        Integer dotIndex = safeName.lastIndexOf('.');
        if (dotIndex > 0) {
            titleBase = safeName.substring(0, dotIndex);
        }
        if (titleBase.length() > 255) {
            titleBase = titleBase.substring(0, 255);
        }

        ContentVersion version = new ContentVersion();
        version.Title = titleBase;
        version.PathOnClient = safeName;
        version.VersionData = fileBody;
        insert version;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        ContentDocumentLink documentLink = new ContentDocumentLink(
            LinkedEntityId = applicationId,
            ContentDocumentId = insertedVersion.ContentDocumentId,
            ShareType = 'V'
        );
        insert documentLink;

        Document_Checklist__c checklist = new Document_Checklist__c();
        List<Document_Checklist__c> existing = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Application__c = :applicationId
                AND Document_Type__c = :DOC_TYPE_FINANCIAL_PERFORMANCE_EXCEL
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            checklist.Id = existing[0].Id;
        }

        checklist.Application__c = applicationId;
        checklist.Document_Type__c = DOC_TYPE_FINANCIAL_PERFORMANCE_EXCEL;
        checklist.ContentVersionId__c = insertedVersion.Id;
        checklist.Name = safeName;
        upsert checklist;

        return new Map<String, Object>{
            'isSuccess' => true,
            'excelDocument' => new Map<String, Object>{
                'found' => true,
                'checklistId' => checklist.Id,
                'contentVersionId' => insertedVersion.Id,
                'contentDocumentId' => insertedVersion.ContentDocumentId,
                'fileName' => safeName
            }
        };
    }

    private static Map<String, Object> deleteFinancialPerformanceExcelInternal(Map<String, Object> args) {
        String applicationId = resolveApplicationId(args);
        if (String.isBlank(applicationId)) {
            throw new AuraHandledException('Application Id is required.');
        }

        List<Document_Checklist__c> rows = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Application__c = :applicationId
                AND Document_Type__c = :DOC_TYPE_FINANCIAL_PERFORMANCE_EXCEL
            WITH SECURITY_ENFORCED
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }

        return new Map<String, Object>{ 'isSuccess' => true };
    }

    private static Map<String, Object> getFinancialPerformanceExcelDocument(String applicationId) {
        if (String.isBlank(applicationId)) {
            return new Map<String, Object>{ 'found' => false };
        }

        List<Document_Checklist__c> rows = [
            SELECT Id, Name, ContentVersionId__c
            FROM Document_Checklist__c
            WHERE Application__c = :applicationId
                AND Document_Type__c = :DOC_TYPE_FINANCIAL_PERFORMANCE_EXCEL
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new Map<String, Object>{ 'found' => false };
        }

        Id contentVersionId = rows[0].ContentVersionId__c;
        Id contentDocumentId = null;
        if (contentVersionId != null) {
            List<ContentVersion> versions = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
            if (!versions.isEmpty()) {
                contentDocumentId = versions[0].ContentDocumentId;
            }
        }

        return new Map<String, Object>{
            'found' => true,
            'checklistId' => rows[0].Id,
            'contentVersionId' => contentVersionId,
            'contentDocumentId' => contentDocumentId,
            'fileName' => rows[0].Name
        };
    }

    private static String resolveApplicationId(Map<String, Object> args) {
        String applicationId = getStringArg(args, 'recordId');
        if (String.isBlank(applicationId)) {
            applicationId = getStringArg(args, 'applicationId');
        }
        if (String.isBlank(applicationId)) {
            applicationId = getStringArg(args, 'loanId');
        }
        return applicationId;
    }

    private static Id resolveGstRecordTypeId(String recordTypeLabel) {
        Map<String, Schema.RecordTypeInfo> rtByName = Schema.SObjectType.GST__c.getRecordTypeInfosByName();
        if (rtByName.containsKey(recordTypeLabel)) {
            return rtByName.get(recordTypeLabel).getRecordTypeId();
        }

        String developerName = recordTypeLabel == 'GSTR 3B'
            ? 'GSTR_3B'
            : recordTypeLabel == 'Form 26 AS Credits' ? 'Form_26_AS_Credits' : null;
        if (String.isNotBlank(developerName)) {
            Map<String, Schema.RecordTypeInfo> rtByDeveloper = Schema.SObjectType.GST__c.getRecordTypeInfosByDeveloperName();
            if (rtByDeveloper.containsKey(developerName)) {
                return rtByDeveloper.get(developerName).getRecordTypeId();
            }
        }

        throw new AuraHandledException('GST record type not found: ' + recordTypeLabel);
    }

    private static String getStringArg(Map<String, Object> args, String key) {
        if (args == null || !args.containsKey(key) || args.get(key) == null) {
            return null;
        }
        String value = String.valueOf(args.get(key));
        return String.isBlank(value) ? null : value;
    }
}