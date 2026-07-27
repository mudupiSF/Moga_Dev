public with sharing class NetworthAndFleetDetailsController implements Callable {

    private static final String PRODUCT_CV = 'CV';
    private static final String STAGE_INCOME_DETAILS = 'Income and Banking Details';

    private static final String ACTION_FETCH_NETWORTH_AND_FLEET_DETAILS = 'fetchNetworthAndFleetDetails';
    private static final String ACTION_GET_NETWORTH_DETAILS = 'getNetworthDetails';
    private static final String ACTION_SAVE_NETWORTH_DETAILS = 'saveNetworthDetails';
    private static final String ACTION_GET_FLEET_COUNT = 'getFleetCount';
    private static final String ACTION_GET_FLEET_DETAILS = 'getFleetDetails';
    private static final String ACTION_SAVE_FLEET_DETAIL = 'saveFleetDetail';
    private static final String ACTION_DELETE_FLEET_DETAIL = 'deleteFleetDetail';
    private static final String ACTION_GET_MAKE_LIST = 'getMakeList';
    private static final String ACTION_GET_MODEL_LIST = 'getModelList';
    private static final String ACTION_UPSERT_DOCUMENT_CHECKLIST = 'upsertDocumentChecklist';
    private static final String ACTION_GET_DOCUMENT_CHECKLIST = 'getDocumentChecklist';

    private static final String FLEET_OBJECT = 'Fleet_Details__c';
    private static final String FLEET_PRODUCT_FIELD = 'Product__c';

    private static final String NETWORTH_TYPE_IMMOVABLE = 'Total Value of Immovable Property';
    private static final String NETWORTH_TYPE_OTHER_ASSETS = 'Total Value of Other Assets';
    private static final String NETWORTH_TYPE_LIABILITIES = 'Total Liabilities';
    private static final String FLEET_TYPE_FREE = 'Free Fleet';
    private static final String FLEET_TYPE_FINANCED_BY_OTHERS = 'Financed by Others';

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_FETCH_NETWORTH_AND_FLEET_DETAILS.equalsIgnoreCase(action)) {
            return fetchNetworthAndFleetDetailsInternal(args);
        }
        if (ACTION_GET_NETWORTH_DETAILS.equalsIgnoreCase(action)) {
            return getNetworthDetailsInternal(args);
        }
        if (ACTION_SAVE_NETWORTH_DETAILS.equalsIgnoreCase(action)) {
            return saveNetworthDetailsInternal(args);
        }
        if (ACTION_GET_FLEET_COUNT.equalsIgnoreCase(action)) {
            return getFleetCountInternal(args);
        }
        if (ACTION_GET_FLEET_DETAILS.equalsIgnoreCase(action)) {
            return getFleetDetailsInternal(args);
        }
        if (ACTION_SAVE_FLEET_DETAIL.equalsIgnoreCase(action)) {
            return saveFleetDetailInternal(args);
        }
        if (ACTION_DELETE_FLEET_DETAIL.equalsIgnoreCase(action)) {
            return deleteFleetDetailInternal(args);
        }
        if (ACTION_GET_MAKE_LIST.equalsIgnoreCase(action)) {
            return getMakeListInternal(args);
        }
        if (ACTION_GET_MODEL_LIST.equalsIgnoreCase(action)) {
            return getModelListInternal(args);
        }
        if (ACTION_UPSERT_DOCUMENT_CHECKLIST.equalsIgnoreCase(action)) {
            return upsertDocumentChecklistInternal(args);
        }
        if (ACTION_GET_DOCUMENT_CHECKLIST.equalsIgnoreCase(action)) {
            return getDocumentChecklistInternal(args);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    private static Map<String, Object> fetchNetworthAndFleetDetailsInternal(Map<String, Object> args) {
        String applicationId = getStringArg(args, 'recordId');
        if (String.isBlank(applicationId)) {
            applicationId = getStringArg(args, 'applicationId');
        }
        if (String.isBlank(applicationId)) {
            throw new AuraHandledException('Application ID cannot be blank');
        }

        List<Application__c> apps = [
            SELECT Id, Sub_Stage__c, Stage__c, Product__c, OwnerId
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        Map<String, Object> result = new Map<String, Object>();
        if (apps.isEmpty()) {
            return result;
        }

        Application__c app = apps[0];
        Boolean isCvProduct = PRODUCT_CV.equalsIgnoreCase(app.Product__c);
        Boolean isIncomeDetailsStage = STAGE_INCOME_DETAILS.equalsIgnoreCase(app.Sub_Stage__c);
        Boolean isOwner = UserInfo.getUserId() == app.OwnerId;

        List<Applicant__c> borrowers = [
            SELECT Type__c
            FROM Applicant__c
            WHERE Application__c = :applicationId AND Applicant_Type__c = 'Borrower'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        result.put('subStage', app.Sub_Stage__c);
        result.put('stage', app.Stage__c);
        result.put('product', app.Product__c);
        result.put('ownerId', app.OwnerId);
        result.put('applicationType', borrowers.isEmpty() ? null : borrowers[0].Type__c);
        result.put('isCvProduct', isCvProduct);
        result.put('isIncomeDetailsStage', isIncomeDetailsStage);
        result.put('isOwner', isOwner);
        result.put('canEdit', isIncomeDetailsStage);
        result.put('canEditDeleteFleet', isOwner && isIncomeDetailsStage && isCvProduct);
        result.put('productOptions', getFleetProductPicklistOptions());
        return result;
    }

    private static Map<String, Object> getNetworthDetailsInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID cannot be blank');
        }

        List<Networth_Details__c> records = [
            SELECT Id, Networth_Type__c, Address_With_Survey_Number__c, Amount_and_Securities_Offered__c,
                Asset_Type__c, Borrowed_From__c, Extent_sq_ft_acre_cent__c, Market_Value__c,
                Nature_Of_Asset__c, O_s_as_on_date_In_Lacs__c, Particulars_Of_Asset_Complete_Descriptio__c,
                Property_Owner_Name__c, Purpose__c, Quantity__c, Value_at_Cost_lacs__c, Applicant__c,
                Document_Collected__c, Networth_Remarks__c
            FROM Networth_Details__c
            WHERE Applicant__c = :applicantId
            WITH SECURITY_ENFORCED
        ];

        String networthRemarks;
        Decimal immovableTotal = 0;
        Decimal otherAssetsTotal = 0;
        Decimal liabilitiesTotal = 0;
        for (Networth_Details__c record : records) {
            if (networthRemarks == null && String.isNotBlank(record.Networth_Remarks__c)) {
                networthRemarks = record.Networth_Remarks__c;
            }
            if (NETWORTH_TYPE_IMMOVABLE.equals(record.Networth_Type__c)) {
                immovableTotal += record.Market_Value__c != null ? record.Market_Value__c : 0;
            } else if (NETWORTH_TYPE_OTHER_ASSETS.equals(record.Networth_Type__c)) {
                otherAssetsTotal += record.Value_at_Cost_lacs__c != null ? record.Value_at_Cost_lacs__c : 0;
            } else if (NETWORTH_TYPE_LIABILITIES.equals(record.Networth_Type__c)) {
                liabilitiesTotal += record.O_s_as_on_date_In_Lacs__c != null ? record.O_s_as_on_date_In_Lacs__c : 0;
            }
        }

        List<Fleet_Details__c> fleetRemarkRows = [
            SELECT Fleet_Remarks__c
            FROM Fleet_Details__c
            WHERE Applicant__c = :applicantId AND Fleet_Remarks__c != null
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        return new Map<String, Object>{
            'networthDetails' => records,
            'totalNetworth' => immovableTotal + otherAssetsTotal - liabilitiesTotal,
            'networthRemarks' => networthRemarks,
            'fleetRemarks' => fleetRemarkRows.isEmpty() ? null : fleetRemarkRows[0].Fleet_Remarks__c
        };
    }

    private static Map<String, Object> saveNetworthDetailsInternal(Map<String, Object> args) {
        String data = getStringArg(args, 'data');
        if (String.isBlank(data)) {
            throw new AuraHandledException('Invalid request data');
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(data);
        String applicantId = (String) payload.get('applicantId');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID is required');
        }

        List<Object> networthDataRaw = (List<Object>) payload.get('networthData');
        String networthRemarks = (String) payload.get('networthRemarks');

        List<Networth_Details__c> networthRecords = new List<Networth_Details__c>();
        for (Object obj : networthDataRaw) {
            Map<String, Object> record = (Map<String, Object>) obj;
            Networth_Details__c networthRec = new Networth_Details__c();

            Object recordId = record.get('Id');
            if (recordId == null) {
                recordId = record.get('id');
            }
            if (recordId != null && String.valueOf(recordId).startsWith('a')) {
                networthRec.Id = (String) recordId;
            } else {
                networthRec.Applicant__c = applicantId;
            }

            networthRec.Networth_Type__c = (String) record.get('Networth_Type__c');
            networthRec.Address_With_Survey_Number__c = (String) record.get('Address_With_Survey_Number__c');
            networthRec.Amount_and_Securities_Offered__c = getDecimalValue(record.get('Amount_and_Securities_Offered__c'));
            networthRec.Asset_Type__c = (String) record.get('Asset_Type__c');
            networthRec.Borrowed_From__c = (String) record.get('Borrowed_From__c');
            networthRec.Extent_sq_ft_acre_cent__c = (String) record.get('Extent_sq_ft_acre_cent__c');
            networthRec.Market_Value__c = getDecimalValue(record.get('Market_Value__c'));
            networthRec.Nature_Of_Asset__c = (String) record.get('Nature_Of_Asset__c');
            networthRec.Document_Collected__c = (String) record.get('Document_Collected__c');
            networthRec.O_s_as_on_date_In_Lacs__c = getDecimalValue(record.get('O_s_as_on_date_In_Lacs__c'));
            networthRec.Particulars_Of_Asset_Complete_Descriptio__c = (String) record.get('Particulars_Of_Asset_Complete_Descriptio__c');
            networthRec.Property_Owner_Name__c = (String) record.get('Property_Owner_Name__c');
            networthRec.Purpose__c = (String) record.get('Purpose__c');
            networthRec.Quantity__c = getDecimalValue(record.get('Quantity__c'));
            networthRec.Value_at_Cost_lacs__c = getDecimalValue(record.get('Value_at_Cost_lacs__c'));
            networthRecords.add(networthRec);
        }

        if (!networthRecords.isEmpty()) {
            networthRecords[0].Networth_Remarks__c = networthRemarks;
            upsert networthRecords;
        } else if (String.isNotBlank(networthRemarks)) {
            upsert new Networth_Details__c(
                Applicant__c = applicantId,
                Networth_Remarks__c = networthRemarks
            );
        }

        return new Map<String, Object>{ 'isSuccess' => true };
    }

    private static Map<String, Object> getFleetCountInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID is required');
        }

        Integer freeFleet = 0;
        Integer financedByOthers = 0;
        for (AggregateResult aggregateResult : [
            SELECT Fleet_Type__c fleetType, COUNT(Id) recordCount
            FROM Fleet_Details__c
            WHERE Applicant__c = :applicantId
                AND Fleet_Type__c IN (:FLEET_TYPE_FREE, :FLEET_TYPE_FINANCED_BY_OTHERS)
            WITH SECURITY_ENFORCED
            GROUP BY Fleet_Type__c
        ]) {
            if (FLEET_TYPE_FREE.equals(aggregateResult.get('fleetType'))) {
                freeFleet = (Integer) aggregateResult.get('recordCount');
            } else if (FLEET_TYPE_FINANCED_BY_OTHERS.equals(aggregateResult.get('fleetType'))) {
                financedByOthers = (Integer) aggregateResult.get('recordCount');
            }
        }

        return new Map<String, Object>{
            'freeFleet' => freeFleet,
            'financedByOthers' => financedByOthers,
            'totalFleet' => freeFleet + financedByOthers
        };
    }

    private static Map<String, Object> getFleetDetailsInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        String fleetType = getStringArg(args, 'fleetType');
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID is required');
        }

        List<Fleet_Details__c> fleetDetails = [
            SELECT Id, Product__c, Asset_Make__c, Asset_Model__c, Year_of_Manufacture__c,
                Current_Demand__c, Policy_Expire_Date__c, Financiar_Name__c, Fleet_Type__c,
                Seasoning__c, Vehicle_Number__c
            FROM Fleet_Details__c
            WHERE Applicant__c = :applicantId AND Fleet_Type__c = :fleetType
            WITH SECURITY_ENFORCED
        ];

        return new Map<String, Object>{ 'fleetDetails' => fleetDetails };
    }

    private static Map<String, Object> saveFleetDetailInternal(Map<String, Object> args) {
        String data = getStringArg(args, 'data');
        if (String.isNotBlank(data)) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(data);
            String applicantId = (String) payload.get('applicantId');
            if (String.isBlank(applicantId)) {
                throw new AuraHandledException('Applicant ID is required');
            }

            String fleetRemarks = (String) payload.get('fleetRemarks');
            List<Fleet_Details__c> existingFleetRecords = [
                SELECT Id
                FROM Fleet_Details__c
                WHERE Applicant__c = :applicantId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!existingFleetRecords.isEmpty()) {
                update new Fleet_Details__c(
                    Id = existingFleetRecords[0].Id,
                    Fleet_Remarks__c = fleetRemarks
                );
            } else if (String.isNotBlank(fleetRemarks)) {
                insert new Fleet_Details__c(
                    Applicant__c = applicantId,
                    Fleet_Remarks__c = fleetRemarks
                );
            }
            return new Map<String, Object>{ 'isSuccess' => true };
        }

        Map<String, Object> fleetRecord = asStringObjectMap(args.get('fleetRecord'));
        String applicantId = getStringArg(args, 'applicantId');
        String fleetType = getStringArg(args, 'fleetType');

        if (fleetRecord == null) {
            return new Map<String, Object>{ 'fleetDetails' => new List<Fleet_Details__c>() };
        }

        Fleet_Details__c newFleetRecord = new Fleet_Details__c();
        if (fleetRecord.containsKey('Id') && fleetRecord.get('Id') != null
            && String.isNotBlank(String.valueOf(fleetRecord.get('Id')))) {
            newFleetRecord.Id = (String) fleetRecord.get('Id');
        } else {
            newFleetRecord.Applicant__c = applicantId;
        }

        newFleetRecord.Asset_Make__c = String.valueOf(fleetRecord.get('Asset_Make__c'));
        newFleetRecord.Asset_Model__c = String.valueOf(fleetRecord.get('Asset_Model__c'));
        newFleetRecord.Current_Demand__c = Integer.valueOf(fleetRecord.get('Current_Demand__c'));
        newFleetRecord.Financiar_Name__c = String.valueOf(fleetRecord.get('Financiar_Name__c'));
        newFleetRecord.Fleet_Type__c = fleetType;
        newFleetRecord.Policy_Expire_Date__c = getDateTimeValues(String.valueOf(fleetRecord.get('Policy_Expire_Date__c')));
        newFleetRecord.Product__c = String.valueOf(fleetRecord.get('Product__c'));
        newFleetRecord.Seasoning__c = Date.valueOf(String.valueOf(fleetRecord.get('Seasoning__c')));
        newFleetRecord.Vehicle_Number__c = String.valueOf(fleetRecord.get('Vehicle_Number__c'));
        newFleetRecord.Year_of_Manufacture__c = Integer.valueOf(fleetRecord.get('Year_of_Manufacture__c'));

        upsert newFleetRecord;

        Map<String, Object> queryArgs = new Map<String, Object>{
            'applicantId' => applicantId,
            'fleetType' => fleetType
        };
        return getFleetDetailsInternal(queryArgs);
    }

    private static Map<String, Object> deleteFleetDetailInternal(Map<String, Object> args) {
        Id fleetId = (Id) args.get('fleetId');
        delete [SELECT Id FROM Fleet_Details__c WHERE Id = :fleetId];
        return new Map<String, Object>{ 'isSuccess' => true };
    }

    private static Map<String, Object> getMakeListInternal(Map<String, Object> args) {
        String productType = getStringArg(args, 'productType');
        List<Map<String, String>> makeOptions = new List<Map<String, String>>();
        if (String.isBlank(productType)) {
            return new Map<String, Object>{ 'makeOptions' => makeOptions };
        }

        // Demo values for UI testing until live make master is wired.
        makeOptions.add(new Map<String, String>{ 'label' => 'Tata', 'value' => 'TATA' });
        makeOptions.add(new Map<String, String>{ 'label' => 'Mahindra', 'value' => 'MAHINDRA' });
        makeOptions.add(new Map<String, String>{ 'label' => 'Ashok Leyland', 'value' => 'ASHOK_LEYLAND' });
        makeOptions.add(new Map<String, String>{ 'label' => 'Eicher', 'value' => 'EICHER' });
        makeOptions.add(new Map<String, String>{ 'label' => 'BharatBenz', 'value' => 'BHARAT_BENZ' });
        return new Map<String, Object>{ 'makeOptions' => makeOptions };
    }

    private static Map<String, Object> getModelListInternal(Map<String, Object> args) {
        String makeCode = getStringArg(args, 'makeCode');
        List<Map<String, String>> modelOptions = new List<Map<String, String>>();
        if (String.isBlank(makeCode)) {
            return new Map<String, Object>{ 'modelOptions' => modelOptions };
        }

        // Demo values for UI testing until live model master is wired.
        if ('TATA'.equalsIgnoreCase(makeCode)) {
            modelOptions.add(new Map<String, String>{ 'label' => 'Prima', 'value' => 'PRIMA' });
            modelOptions.add(new Map<String, String>{ 'label' => 'Signa', 'value' => 'SIGNA' });
            modelOptions.add(new Map<String, String>{ 'label' => 'Ultra', 'value' => 'ULTRA' });
        } else if ('MAHINDRA'.equalsIgnoreCase(makeCode)) {
            modelOptions.add(new Map<String, String>{ 'label' => 'Blazo', 'value' => 'BLAZO' });
            modelOptions.add(new Map<String, String>{ 'label' => 'Furio', 'value' => 'FURIO' });
            modelOptions.add(new Map<String, String>{ 'label' => 'Jeeto', 'value' => 'JEETO' });
        } else if ('ASHOK_LEYLAND'.equalsIgnoreCase(makeCode)) {
            modelOptions.add(new Map<String, String>{ 'label' => 'Boss', 'value' => 'BOSS' });
            modelOptions.add(new Map<String, String>{ 'label' => 'Partner', 'value' => 'PARTNER' });
            modelOptions.add(new Map<String, String>{ 'label' => 'Dost', 'value' => 'DOST' });
        } else if ('EICHER'.equalsIgnoreCase(makeCode)) {
            modelOptions.add(new Map<String, String>{ 'label' => 'Pro 2049', 'value' => 'PRO_2049' });
            modelOptions.add(new Map<String, String>{ 'label' => 'Pro 3015', 'value' => 'PRO_3015' });
        } else if ('BHARAT_BENZ'.equalsIgnoreCase(makeCode)) {
            modelOptions.add(new Map<String, String>{ 'label' => '914R', 'value' => '914R' });
            modelOptions.add(new Map<String, String>{ 'label' => '1217C', 'value' => '1217C' });
        } else {
            modelOptions.add(new Map<String, String>{ 'label' => 'Demo Model A', 'value' => 'DEMO_MODEL_A' });
            modelOptions.add(new Map<String, String>{ 'label' => 'Demo Model B', 'value' => 'DEMO_MODEL_B' });
        }

        return new Map<String, Object>{ 'modelOptions' => modelOptions };
    }

    private static Map<String, Object> upsertDocumentChecklistInternal(Map<String, Object> args) {
        String applicationId = getStringArg(args, 'recordId');
        if (String.isBlank(applicationId)) {
            applicationId = getStringArg(args, 'applicationId');
        }
        String applicantId = getStringArg(args, 'applicantId');
        String documentType = getStringArg(args, 'documentType');
        Id contentDocumentId = (Id) args.get('contentDocumentId');
        Id contentVersionId = (Id) args.get('contentVersionId');
        String fileName = getStringArg(args, 'fileName');

        Document_Checklist__c checklist = new Document_Checklist__c();
        List<Document_Checklist__c> existing = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Applicant__c = :applicantId AND Document_Type__c = :documentType
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            checklist.Id = existing[0].Id;
        }

        checklist.Application__c = applicationId;
        checklist.Applicant__c = applicantId;
        checklist.Document_Type__c = documentType;
        checklist.ContentVersionId__c = contentVersionId;
        if (String.isNotBlank(fileName)) {
            checklist.Name = fileName;
        }
        upsert checklist;

        return new Map<String, Object>{
            'isSuccess' => true,
            'checklistId' => checklist.Id,
            'contentDocumentId' => contentDocumentId,
            'contentVersionId' => contentVersionId,
            'fileName' => fileName
        };
    }

    private static Map<String, Object> getDocumentChecklistInternal(Map<String, Object> args) {
        String applicantId = getStringArg(args, 'applicantId');
        String documentType = getStringArg(args, 'documentType');

        List<Document_Checklist__c> rows = [
            SELECT Id, Name, ContentVersionId__c
            FROM Document_Checklist__c
            WHERE Applicant__c = :applicantId AND Document_Type__c = :documentType
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new Map<String, Object>{ 'found' => false };
        }

        return new Map<String, Object>{
            'found' => true,
            'checklistId' => rows[0].Id,
            'contentVersionId' => rows[0].ContentVersionId__c,
            'fileName' => rows[0].Name
        };
    }

    private static List<Map<String, String>> getFleetProductPicklistOptions() {
        return GenericUtility.getActivePicklistOptions(FLEET_OBJECT, FLEET_PRODUCT_FIELD);
    }

    private static String getStringArg(Map<String, Object> args, String key) {
        if (args == null || !args.containsKey(key) || args.get(key) == null) {
            return null;
        }
        return String.valueOf(args.get(key));
    }

    private static Map<String, Object> asStringObjectMap(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Map<String, Object>) {
            return (Map<String, Object>) value;
        }
        if (value instanceof Map<Object, Object>) {
            Map<String, Object> converted = new Map<String, Object>();
            Map<Object, Object> rawMap = (Map<Object, Object>) value;
            for (Object key : rawMap.keySet()) {
                converted.put(String.valueOf(key), rawMap.get(key));
            }
            return converted;
        }
        return null;
    }

    private static Decimal getDecimalValue(Object value) {
        return value != null ? Decimal.valueOf(String.valueOf(value)) : null;
    }

    private static DateTime getDateTimeValues(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }
        String normalized = dateTimeStr.replace('T', ' ').replace('Z', '');
        return Datetime.valueOfGmt(normalized);
    }
}