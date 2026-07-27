/**
 * Valuation stage — persists insurance and valuation fields on Asset__c;
 * owner name/contact on Applicant__c (Customer_First_Name__c, Contact_number__c).
 *
 * Asset__c field map (UI key → API):
 *   insuranceType → Insurance_type__c
 *   insuranceDeclaredValue → Insurance_declared_value__c
 *   existingMotorInsurancePremium → Existing_Motor_Insurance_Premium__c
 *   insExpiryDate → Ins_Expiry_date__c
 *   vehiclePlaceOfValuation → Vehicle_Place_Of_Valuation__c
 *   valuerCategory → Valuer_category__c
 *   valuer → Valuer__c
 *   valuerCode → Valuer_code__c
 *   slaNumber → SLA_Number__c
 *   colorOfVehicle → Color_of_Vehicle__c
 *   kmsRun → KMS_Run__c
 *
 * Vehicle Inspection (Asset__c) UI key → API:
 *   engineNumber → Engine_number__c
 *   engineNumberCapturedInitially → Engine_number_captured_Initially__c
 *   chassisNumber → Chassis_number__c
 *   chassisNumberCapturedInitially → Chassis_number_captured_Initially__c
 *   vehicleRegistrationNumber → Vehicle_Registration_number__c
 *   vehicleRegistrationNumberCapturedInitially → Vehicle_Reg_Number_Captured_Initially__c
 *   locationOfVehicleInspection → Location_of_Vehicle_Inspection__c
 *
 * Vehicle Inspection Operations (Asset__c) UI key → API:
 *   remarks → Remark__c
 *   vehicleInspectionApprovedByCvo → Vehicle_inspection_approved_by_CVO__c
 *   cvoRemarks → CVO_remarks__c
 */
public with sharing class ValuationController {
    private static final String DEFAULT_VALUER_CODE = 'A';
    private static final String VALUATION_STAGE = 'Valuation';
    private static final String VALUER_BENEFICIARY_VAL = 'VAL';
    private static final String MSG_VALUATION_REQUEST_SUBMITTED = 'Valuation request submitted successfully';
    private static final String MSG_VALUATION_REPORT_FETCHED = 'Valuation report fetched successfully';
    private static final String OBJECT_ASSET = 'Asset__c';
    private static final String VEHICLE_INSPECTION_DOCUMENT_TYPE = 'Vehicle Inspection';

    private static final Map<String, String> VEHICLE_INSPECTION_FIELD_MAP = new Map<String, String>{
        'engineNumber' => 'Engine_number__c',
        'engineNumberCapturedInitially' => 'Engine_number_captured_Initially__c',
        'chassisNumber' => 'Chassis_number__c',
        'chassisNumberCapturedInitially' => 'Chassis_number_captured_Initially__c',
        'vehicleRegistrationNumber' => 'Vehicle_Registration_number__c',
        'vehicleRegistrationNumberCapturedInitially' => 'Vehicle_Reg_Number_Captured_Initially__c',
        'locationOfVehicleInspection' => 'Location_of_Vehicle_Inspection__c'
    };

    private static final Map<String, String> VEHICLE_INSPECTION_PICKLIST_MAP = new Map<String, String>{
        'locationOfVehicleInspection' => 'Location_of_Vehicle_Inspection__c'
    };

    private static final Map<String, String> VEHICLE_INSPECTION_OPERATIONS_FIELD_MAP = new Map<String, String>{
        'remarks' => 'Remark__c',
        'vehicleInspectionApprovedByCvo' => 'Vehicle_inspection_approved_by_CVO__c',
        'cvoRemarks' => 'CVO_remarks__c'
    };

    private static final Map<String, String> VEHICLE_INSPECTION_OPERATIONS_PICKLIST_MAP = new Map<String, String>{
        'vehicleInspectionApprovedByCvo' => 'Vehicle_inspection_approved_by_CVO__c'
    };

    /** Session MFC state until MFC fields exist on Asset__c. */
    private static Map<String, Map<String, Object>> mfcSessionByKey = new Map<String, Map<String, Object>>();

    private static Map<String, Schema.SObjectField> assetFieldMapCache;

    @TestVisible
    private static void clearMfcSessionForTests() {
        mfcSessionByKey.clear();
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getValuationData(
        String applicationId,
        String assetId,
        String insuranceId,
        String applicantId
    ) {
        Id resolvedAssetId = resolveAssetId(assetId, applicationId, applicantId);
        if (resolvedAssetId == null) {
            return emptyLoadResponse(applicationId, assetId, insuranceId, applicantId);
        }

        Asset__c asset = queryAsset(resolvedAssetId);
        if (asset == null) {
            return emptyLoadResponse(applicationId, assetId, insuranceId, applicantId);
        }

        String productType = nullToEmpty(asset.Product_Segment__c);

        Id resolvedApplicantId = resolveApplicantId(applicantId, asset.Applicant__c);
        Applicant__c applicant = resolvedApplicantId != null ? queryApplicant(resolvedApplicantId) : null;

        String sessionKey = buildSessionKey(applicationId, String.valueOf(resolvedAssetId), insuranceId);
        if (!mfcSessionByKey.containsKey(sessionKey)) {
            mfcSessionByKey.put(sessionKey, new Map<String, Object>());
        }
        Map<String, Object> session = mfcSessionByKey.get(sessionKey);

        return new Map<String, Object>{
            'isSuccess' => true,
            'productType' => productType,
            'resolvedAssetId' => String.valueOf(resolvedAssetId),
            'resolvedApplicantId' => resolvedApplicantId != null ? String.valueOf(resolvedApplicantId) : '',
            'existingInsurance' => buildExistingInsuranceMap(asset),
            'vehicleValuation' => buildVehicleValuationMap(asset, applicant),
            'valuationContext' => new Map<String, Object>{
                'mfcRequestId' => session != null && session.containsKey('mfcRequestId')
                    ? String.valueOf(session.get('mfcRequestId'))
                    : '',
                'oemDealer' => session != null && session.get('oemDealer') == true
            },
            'valuerMasterOptions' => getValuerMasterOptions(),
            'picklists' => buildPicklists()
        };
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> saveValuationData(
        String applicationId,
        String assetId,
        String insuranceId,
        String applicantId,
        String applicationLineItemId,
        String payloadJson
    ) {
        Id resolvedAssetId = resolveAssetId(assetId, applicationId, applicantId);
        if (resolvedAssetId == null) {
            return failure(
                'Could not find an Asset for this application. Ensure an Asset is linked to the applicant or application line item.'
            );
        }
        if (String.isBlank(payloadJson)) {
            return failure('Nothing to save.');
        }

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
            Map<String, Object> ex = root != null && root.containsKey('existingInsurance')
                ? (Map<String, Object>) root.get('existingInsurance')
                : new Map<String, Object>();
            Map<String, Object> val = root != null && root.containsKey('vehicleValuation')
                ? (Map<String, Object>) root.get('vehicleValuation')
                : new Map<String, Object>();

            Asset__c asset = new Asset__c(Id = resolvedAssetId);
            applyExistingInsurance(asset, ex);
            applyVehicleValuation(asset, val);
            Database.SaveResult assetResult = Database.update(asset, AccessLevel.SYSTEM_MODE);
            if (!assetResult.isSuccess()) {
                return failure(formatDmlErrors(assetResult.getErrors()));
            }

            Id resolvedApplicantId = resolveApplicantId(applicantId, queryAssetApplicantId(resolvedAssetId));
            if (resolvedApplicantId != null) {
                Applicant__c applicant = new Applicant__c(Id = resolvedApplicantId);
                if (val.containsKey('ownerName')) {
                    applicant.Customer_First_Name__c = stringVal(val.get('ownerName'));
                }
                if (val.containsKey('ownerContactNumber')) {
                    applicant.Contact_number__c = stringVal(val.get('ownerContactNumber'));
                }
                Database.SaveResult applicantResult = Database.update(applicant, AccessLevel.SYSTEM_MODE);
                if (!applicantResult.isSuccess()) {
                    return failure(formatDmlErrors(applicantResult.getErrors()));
                }
            }

            Id lineItemId = resolveApplicationLineItemId(applicationLineItemId, resolvedAssetId);
            if (lineItemId != null) {
                Application_Line_Item__c existingLineItem = queryApplicationLineItem(lineItemId);
                Application_Line_Item__c lineItem = new Application_Line_Item__c(Id = lineItemId);
                lineItem.Stage_Completed__c = appendStageCompleted(
                    existingLineItem?.Stage_Completed__c,
                    VALUATION_STAGE
                );
                Database.SaveResult lineItemResult = Database.update(lineItem, AccessLevel.SYSTEM_MODE);
                if (!lineItemResult.isSuccess()) {
                    return failure(formatDmlErrors(lineItemResult.getErrors()));
                }
            }

            return new Map<String, Object>{
                'isSuccess' => true,
                'message' => 'Valuation saved successfully.',
                'resolvedAssetId' => String.valueOf(resolvedAssetId),
                'resolvedApplicantId' => resolvedApplicantId != null ? String.valueOf(resolvedApplicantId) : '',
                'applicationLineItemId' => lineItemId != null ? String.valueOf(lineItemId) : ''
            };
        } catch (Exception e) {
            return failure(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> mfcValuation(String recordId) {
        if (String.isNotBlank(recordId)) {
            for (String key : mfcSessionByKey.keySet()) {
                if (key.startsWith(recordId + '|')) {
                    Map<String, Object> session = mfcSessionByKey.get(key);
                    session.put('mfcRequestId', 'MFC-' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
                    session.put('oemDealer', false);
                }
            }
        }
        return integrationSuccess(MSG_VALUATION_REQUEST_SUBMITTED, true);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> mfcFetchValuationReport(String recordId) {
        return integrationSuccess(MSG_VALUATION_REPORT_FETCHED, false);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getVehicleInspectionData(
        String applicationId,
        String assetId,
        String applicantId
    ) {
        Id resolvedAssetId = resolveAssetId(assetId, applicationId, applicantId);
        if (resolvedAssetId == null) {
            return emptyVehicleInspectionResponse(applicationId, assetId, applicantId);
        }

        SObject asset = queryVehicleInspectionAsset(resolvedAssetId);
        if (asset == null) {
            return emptyVehicleInspectionResponse(applicationId, assetId, applicantId);
        }

        Id resolvedApplicantId = resolveApplicantId(applicantId, (Id) asset.get('Applicant__c'));
        Id appId = String.isNotBlank(applicationId) ? (Id) applicationId : null;
        Map<String, Object> docInfo = queryVehicleInspectionDocument(appId, resolvedApplicantId);
        Boolean imageUploaded = docInfo.get('uploaded') == true;

        return new Map<String, Object>{
            'isSuccess' => true,
            'resolvedAssetId' => String.valueOf(resolvedAssetId),
            'resolvedApplicantId' => resolvedApplicantId != null ? String.valueOf(resolvedApplicantId) : '',
            'assetNotFound' => false,
            'vehicleInspection' => buildVehicleInspectionMap(asset),
            'operationsSection' => buildVehicleInspectionOperationsMap(asset),
            'picklists' => buildVehicleInspectionPicklists(),
            'operationsPicklists' => buildVehicleInspectionOperationsPicklists(),
            'vehicleInspectionImageCount' => imageUploaded ? 1 : 0,
            'vehicleInspectionImageUploaded' => imageUploaded,
            'documentChecklistId' => docInfo.get('documentChecklistId'),
            'vehicleImageContentDocumentId' => docInfo.get('contentDocumentId'),
            'vehicleImageFileName' => docInfo.get('fileName'),
            'vehicleImageFileType' => docInfo.get('fileType')
        };
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> saveVehicleInspectionData(
        String applicationId,
        String assetId,
        String applicantId,
        String payloadJson
    ) {
        Id resolvedAssetId = resolveAssetId(assetId, applicationId, applicantId);
        if (resolvedAssetId == null) {
            return failure(
                'Could not find an Asset for this application. Ensure an Asset is linked to the applicant or application line item.'
            );
        }
        if (String.isBlank(payloadJson)) {
            return failure('Nothing to save.');
        }

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
            Map<String, Object> inspection = root != null && root.containsKey('vehicleInspection')
                ? (Map<String, Object>) root.get('vehicleInspection')
                : new Map<String, Object>();
            Map<String, Object> operations = root != null && root.containsKey('operationsSection')
                ? (Map<String, Object>) root.get('operationsSection')
                : new Map<String, Object>();

            Asset__c asset = new Asset__c(Id = resolvedAssetId);
            applyVehicleInspection(asset, inspection);
            applyVehicleInspectionOperations(asset, operations);
            Database.SaveResult assetResult = Database.update(asset, AccessLevel.SYSTEM_MODE);
            if (!assetResult.isSuccess()) {
                return failure(formatDmlErrors(assetResult.getErrors()));
            }

            Id resolvedApplicantId = resolveApplicantId(
                applicantId,
                queryAssetApplicantId(resolvedAssetId)
            );

            return new Map<String, Object>{
                'isSuccess' => true,
                'message' => 'Vehicle inspection saved successfully.',
                'resolvedAssetId' => String.valueOf(resolvedAssetId),
                'resolvedApplicantId' => resolvedApplicantId != null ? String.valueOf(resolvedApplicantId) : ''
            };
        } catch (Exception e) {
            return failure(e.getMessage());
        }
    }

    private static Map<String, Object> buildExistingInsuranceMap(Asset__c asset) {
        return new Map<String, Object>{
            'insuranceType' => nullToEmpty(asset.Insurance_type__c),
            'insuranceDeclaredValue' => decimalToUi(asset.Insurance_declared_value__c),
            'existingMotorInsurancePremium' => decimalToUi(asset.Existing_Motor_Insurance_Premium__c),
            'insExpiryDate' => formatYmd(asset.Ins_Expiry_date__c)
        };
    }

    private static Map<String, Object> buildVehicleValuationMap(Asset__c asset, Applicant__c applicant) {
        String ownerName = applicant != null ? nullToEmpty(applicant.Customer_First_Name__c) : '';
        String ownerContact = applicant != null ? nullToEmpty(applicant.Contact_number__c) : '';
        return new Map<String, Object>{
            'ownerName' => ownerName,
            'ownerContactNumber' => ownerContact,
            'vehiclePlaceOfValuation' => nullToEmpty(asset.Vehicle_Place_Of_Valuation__c),
            'valuerCategory' => nullToEmpty(asset.Valuer_category__c),
            'valuer' => nullToEmpty(asset.Valuer__c),
            'valuerCode' => String.isBlank(asset.Valuer_code__c) ? DEFAULT_VALUER_CODE : asset.Valuer_code__c,
            'slaNumber' => nullToEmpty(asset.SLA_Number__c),
            'colorOfVehicle' => nullToEmpty(asset.Color_of_Vehicle__c),
            'kmsRun' => nullToEmpty(asset.KMS_Run__c)
        };
    }

    private static void applyExistingInsurance(Asset__c asset, Map<String, Object> m) {
        if (m == null) {
            return;
        }
        if (m.containsKey('insuranceType')) {
            asset.Insurance_type__c = stringVal(m.get('insuranceType'));
        }
        if (m.containsKey('insuranceDeclaredValue')) {
            asset.Insurance_declared_value__c = decimalVal(m.get('insuranceDeclaredValue'));
        }
        if (m.containsKey('existingMotorInsurancePremium')) {
            asset.Existing_Motor_Insurance_Premium__c = decimalVal(m.get('existingMotorInsurancePremium'));
        }
        if (m.containsKey('insExpiryDate')) {
            asset.Ins_Expiry_date__c = dateVal(m.get('insExpiryDate'));
        }
    }

    private static void applyVehicleValuation(Asset__c asset, Map<String, Object> m) {
        if (m == null) {
            return;
        }
        if (m.containsKey('vehiclePlaceOfValuation')) {
            asset.Vehicle_Place_Of_Valuation__c = stringVal(m.get('vehiclePlaceOfValuation'));
        }
        if (m.containsKey('valuerCategory')) {
            String category = stringVal(m.get('valuerCategory'));
            asset.Valuer_category__c = category;
        }
        if (m.containsKey('valuer')) {
            asset.Valuer__c = stringVal(m.get('valuer'));
        }
        if (m.containsKey('valuerCode')) {
            asset.Valuer_code__c = stringVal(m.get('valuerCode'));
        }
        if (m.containsKey('slaNumber')) {
            asset.SLA_Number__c = stringVal(m.get('slaNumber'));
        }
        if (m.containsKey('colorOfVehicle')) {
            asset.Color_of_Vehicle__c = stringVal(m.get('colorOfVehicle'));
        }
        if (m.containsKey('kmsRun')) {
            asset.KMS_Run__c = stringVal(m.get('kmsRun'));
        }
    }

    private static Asset__c queryAsset(Id assetId) {
        List<Asset__c> rows = [
            SELECT
                Id,
                Applicant__c,
                Insurance_type__c,
                Insurance_declared_value__c,
                Existing_Motor_Insurance_Premium__c,
                Ins_Expiry_date__c,
                Vehicle_Place_Of_Valuation__c,
                Valuer_category__c,
                Valuer__c,
                Valuer_code__c,
                SLA_Number__c,
                Color_of_Vehicle__c,
                KMS_Run__c,
                Product_Segment__c
            FROM Asset__c
            WHERE Id = :assetId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Applicant__c queryApplicant(Id applicantId) {
        List<Applicant__c> rows = [
            SELECT Id, Customer_First_Name__c, Contact_number__c
            FROM Applicant__c
            WHERE Id = :applicantId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Id resolveAssetId(String assetId, String applicationId, String applicantId) {
        if (String.isNotBlank(assetId)) {
            try {
                return (Id) assetId;
            } catch (Exception e) {
                // Invalid id string — fall through to lookup strategies.
            }
        }
        if (String.isNotBlank(applicantId)) {
            Id fromApplicant = queryAssetIdByApplicant((Id) applicantId);
            if (fromApplicant != null) {
                return fromApplicant;
            }
        }
        if (String.isNotBlank(applicationId)) {
            Id fromApplication = queryAssetIdByApplication((Id) applicationId);
            if (fromApplication != null) {
                return fromApplication;
            }
        }
        return null;
    }

    private static Id queryAssetIdByApplicant(Id applicantId) {
        List<Asset__c> rows = [
            SELECT Id
            FROM Asset__c
            WHERE Applicant__c = :applicantId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Id queryAssetIdByApplication(Id applicationId) {
        List<Asset__c> byApplicantOnApp = [
            SELECT Id
            FROM Asset__c
            WHERE Applicant__r.Application__c = :applicationId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!byApplicantOnApp.isEmpty()) {
            return byApplicantOnApp[0].Id;
        }
        List<Asset__c> byLineItem = [
            SELECT Id
            FROM Asset__c
            WHERE Application_Line_Items__r.Application__c = :applicationId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return byLineItem.isEmpty() ? null : byLineItem[0].Id;
    }

    private static Id queryAssetApplicantId(Id assetId) {
        List<Asset__c> rows = [
            SELECT Applicant__c
            FROM Asset__c
            WHERE Id = :assetId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Applicant__c;
    }

    private static String formatDmlErrors(List<Database.Error> errors) {
        if (errors == null || errors.isEmpty()) {
            return 'Update failed.';
        }
        List<String> messages = new List<String>();
        for (Database.Error err : errors) {
            messages.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return String.join(messages, ' ');
    }

    private static Id resolveApplicantId(String applicantId, Id assetApplicantId) {
        if (String.isNotBlank(applicantId)) {
            return (Id) applicantId;
        }
        return assetApplicantId;
    }

    private static Id resolveApplicationLineItemId(String applicationLineItemId, Id assetId) {
        if (String.isNotBlank(applicationLineItemId)) {
            try {
                return (Id) applicationLineItemId;
            } catch (Exception e) {
                // Invalid id string — fall through to asset lookup.
            }
        }
        if (assetId == null) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT Application_Line_Items__c
            FROM Asset__c
            WHERE Id = :assetId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Application_Line_Items__c;
    }

    private static Application_Line_Item__c queryApplicationLineItem(Id lineItemId) {
        List<Application_Line_Item__c> rows = [
            SELECT Id, Stage_Completed__c
            FROM Application_Line_Item__c
            WHERE Id = :lineItemId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static String appendStageCompleted(String currentStages, String stageName) {
        if (String.isBlank(stageName) || hasStageCompleted(currentStages, stageName)) {
            return currentStages;
        }
        String stage = stageName.trim();
        return String.isBlank(currentStages) ? stage : currentStages + ';' + stage;
    }

    private static Boolean hasStageCompleted(String completedStages, String stageName) {
        if (String.isBlank(completedStages) || String.isBlank(stageName)) {
            return false;
        }
        for (String stage : completedStages.split(';')) {
            if (stageName.equalsIgnoreCase(stage.trim())) {
                return true;
            }
        }
        return false;
    }

    private static SObject queryVehicleInspectionAsset(Id assetId) {
        List<String> selectFields = getVehicleInspectionSelectFields();
        if (selectFields.isEmpty()) {
            return null;
        }
        String soql =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Asset__c WHERE Id = :assetId WITH SYSTEM_MODE LIMIT 1';
        List<SObject> rows = Database.query(soql);
        return rows.isEmpty() ? null : rows[0];
    }

    private static Map<String, Schema.SObjectField> getAssetFieldMap() {
        if (assetFieldMapCache == null) {
            assetFieldMapCache = Asset__c.SObjectType.getDescribe().fields.getMap();
        }
        return assetFieldMapCache;
    }

    private static List<String> getVehicleInspectionSelectFields() {
        Map<String, Schema.SObjectField> fieldMap = getAssetFieldMap();
        List<String> fields = new List<String>{ 'Id', 'Applicant__c' };
        Set<String> seen = new Set<String>(fields);
        for (String apiName : VEHICLE_INSPECTION_FIELD_MAP.values()) {
            if (fieldMap.containsKey(apiName) && !seen.contains(apiName)) {
                fields.add(apiName);
                seen.add(apiName);
            }
        }
        for (String apiName : VEHICLE_INSPECTION_OPERATIONS_FIELD_MAP.values()) {
            if (fieldMap.containsKey(apiName) && !seen.contains(apiName)) {
                fields.add(apiName);
                seen.add(apiName);
            }
        }
        return fields;
    }

    private static Map<String, Object> mapUiFieldsFromRecord(
        SObject record,
        Map<String, String> uiToApi,
        Map<String, Object> defaults
    ) {
        Map<String, Object> result = defaults != null
            ? new Map<String, Object>(defaults)
            : new Map<String, Object>();
        if (record == null) {
            return result;
        }
        Map<String, Schema.SObjectField> fieldMap = getAssetFieldMap();
        for (String uiKey : uiToApi.keySet()) {
            String apiName = uiToApi.get(uiKey);
            if (!fieldMap.containsKey(apiName)) {
                continue;
            }
            Object raw = record.get(apiName);
            result.put(uiKey, raw == null ? '' : String.valueOf(raw));
        }
        return result;
    }

    private static void applyUiFieldsToRecord(
        Asset__c asset,
        Map<String, Object> payload,
        Map<String, String> uiToApi
    ) {
        if (asset == null || payload == null || payload.isEmpty()) {
            return;
        }
        Map<String, Schema.SObjectField> fieldMap = getAssetFieldMap();
        for (String uiKey : payload.keySet()) {
            if (!uiToApi.containsKey(uiKey)) {
                continue;
            }
            String apiName = uiToApi.get(uiKey);
            if (!fieldMap.containsKey(apiName)) {
                continue;
            }
            asset.put(apiName, stringVal(payload.get(uiKey)));
        }
    }

    private static Map<String, Object> buildVehicleInspectionMap(SObject asset) {
        return mapUiFieldsFromRecord(asset, VEHICLE_INSPECTION_FIELD_MAP, defaultVehicleInspection());
    }

    private static void applyVehicleInspection(Asset__c asset, Map<String, Object> payload) {
        applyUiFieldsToRecord(asset, payload, VEHICLE_INSPECTION_FIELD_MAP);
    }

    private static Map<String, Object> buildVehicleInspectionOperationsMap(SObject asset) {
        return mapUiFieldsFromRecord(
            asset,
            VEHICLE_INSPECTION_OPERATIONS_FIELD_MAP,
            defaultVehicleInspectionOperations()
        );
    }

    private static void applyVehicleInspectionOperations(Asset__c asset, Map<String, Object> payload) {
        applyUiFieldsToRecord(asset, payload, VEHICLE_INSPECTION_OPERATIONS_FIELD_MAP);
    }

    private static Map<String, Object> buildVehicleInspectionPicklists() {
        Map<String, Object> picklists = new Map<String, Object>();
        for (String uiKey : VEHICLE_INSPECTION_PICKLIST_MAP.keySet()) {
            String apiName = VEHICLE_INSPECTION_PICKLIST_MAP.get(uiKey);
            List<Map<String, Object>> options = getPicklistOptions(OBJECT_ASSET, apiName);
            if (options.isEmpty()) {
                options = fallbackVehicleInspectionPicklist(uiKey);
            }
            picklists.put(uiKey, options);
        }
        return picklists;
    }

    private static Map<String, Object> buildVehicleInspectionOperationsPicklists() {
        Map<String, Object> picklists = new Map<String, Object>();
        for (String uiKey : VEHICLE_INSPECTION_OPERATIONS_PICKLIST_MAP.keySet()) {
            String apiName = VEHICLE_INSPECTION_OPERATIONS_PICKLIST_MAP.get(uiKey);
            List<Map<String, Object>> options = getPicklistOptions(OBJECT_ASSET, apiName);
            picklists.put(uiKey, options);
        }
        return picklists;
    }

    private static List<Map<String, Object>> fallbackVehicleInspectionPicklist(String uiKey) {
        return new List<Map<String, Object>>();
    }

    private static Map<String, Object> emptyVehicleInspectionResponse(
        String applicationId,
        String assetId,
        String applicantId
    ) {
        Id resolvedAssetId = resolveAssetId(assetId, applicationId, applicantId);
        Id resolvedApplicantId = String.isNotBlank(applicantId) ? (Id) applicantId : null;
        Id appId = String.isNotBlank(applicationId) ? (Id) applicationId : null;
        Map<String, Object> docInfo = queryVehicleInspectionDocument(appId, resolvedApplicantId);
        Boolean imageUploaded = docInfo.get('uploaded') == true;
        return new Map<String, Object>{
            'isSuccess' => true,
            'resolvedAssetId' => resolvedAssetId != null ? String.valueOf(resolvedAssetId) : '',
            'resolvedApplicantId' => resolvedApplicantId != null ? String.valueOf(resolvedApplicantId) : applicantId,
            'assetNotFound' => resolvedAssetId == null,
            'vehicleInspection' => defaultVehicleInspection(),
            'operationsSection' => defaultVehicleInspectionOperations(),
            'picklists' => buildVehicleInspectionPicklists(),
            'operationsPicklists' => buildVehicleInspectionOperationsPicklists(),
            'vehicleInspectionImageCount' => imageUploaded ? 1 : 0,
            'vehicleInspectionImageUploaded' => imageUploaded,
            'documentChecklistId' => docInfo.get('documentChecklistId'),
            'vehicleImageContentDocumentId' => docInfo.get('contentDocumentId'),
            'vehicleImageFileName' => docInfo.get('fileName'),
            'vehicleImageFileType' => docInfo.get('fileType')
        };
    }

    private static Map<String, Object> queryVehicleInspectionDocument(Id applicationId, Id applicantId) {
        Map<String, Object> result = new Map<String, Object>{
            'uploaded' => false,
            'documentChecklistId' => '',
            'contentDocumentId' => '',
            'fileName' => '',
            'fileType' => 'PNG'
        };
        if (applicationId == null || applicantId == null) {
            return result;
        }
        Schema.SObjectType checklistType = getObjectType('Document_CheckList__c');
        if (checklistType == null) {
            return result;
        }
        Map<String, Schema.SObjectField> fm = checklistType.getDescribe().fields.getMap();
        if (!fm.containsKey('Application__c') || !fm.containsKey('Applicant__c') || !fm.containsKey('Document_Type__c')) {
            return result;
        }

        String docType = VEHICLE_INSPECTION_DOCUMENT_TYPE;
        String extra = fm.containsKey('ContentVersionId__c') ? ', ContentVersionId__c' : '';
        List<SObject> rows = Database.query(
            'SELECT Id' +
            extra +
            ' FROM Document_CheckList__c WHERE Application__c = :applicationId AND Applicant__c = :applicantId' +
            ' AND Document_Type__c = :docType WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1'
        );
        if (rows.isEmpty()) {
            return result;
        }

        SObject checklist = rows[0];
        result.put('documentChecklistId', String.valueOf(checklist.get('Id')));

        if (!fm.containsKey('ContentVersionId__c')) {
            result.put('uploaded', true);
            return result;
        }

        String contentVersionId = (String) checklist.get('ContentVersionId__c');
        if (String.isBlank(contentVersionId)) {
            return result;
        }

        List<ContentVersion> versions = [
            SELECT Title, FileExtension, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (versions.isEmpty() || versions[0].ContentDocumentId == null) {
            return result;
        }

        ContentVersion version = versions[0];
        result.put('uploaded', true);
        result.put('contentDocumentId', String.valueOf(version.ContentDocumentId));
        result.put('fileName', String.isNotBlank(version.Title) ? version.Title : 'Vehicle Image');
        if (String.isNotBlank(version.FileExtension)) {
            result.put('fileType', version.FileExtension.toUpperCase());
        }
        return result;
    }

    private static Map<String, Object> defaultVehicleInspection() {
        Map<String, Object> defaults = new Map<String, Object>();
        for (String uiKey : VEHICLE_INSPECTION_FIELD_MAP.keySet()) {
            defaults.put(uiKey, '');
        }
        return defaults;
    }

    private static Map<String, Object> defaultVehicleInspectionOperations() {
        Map<String, Object> defaults = new Map<String, Object>();
        for (String uiKey : VEHICLE_INSPECTION_OPERATIONS_FIELD_MAP.keySet()) {
            defaults.put(uiKey, '');
        }
        return defaults;
    }

    private static Map<String, Object> buildPicklists() {
        List<Map<String, Object>> insuranceType = getPicklistOptions(OBJECT_ASSET, 'Insurance_type__c');
        List<Map<String, Object>> valuerCategory = getPicklistOptions(OBJECT_ASSET, 'Valuer_category__c');
        if (insuranceType.isEmpty()) {
            insuranceType = fallbackInsuranceTypeOptions();
        }
        if (valuerCategory.isEmpty()) {
            valuerCategory = fallbackValuerCategoryOptions();
        }
        return new Map<String, Object>{
            'insuranceType' => insuranceType,
            'valuerCategory' => valuerCategory
        };
    }

    private static Map<String, Schema.SObjectType> objectTypeCache;

    private static Schema.SObjectType getObjectType(String objectApiName) {
        if (objectTypeCache == null) {
            objectTypeCache = Schema.getGlobalDescribe();
        }
        return objectTypeCache.get(objectApiName);
    }

    private static List<Map<String, Object>> getPicklistOptions(String objectApiName, String fieldApiName) {
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        try {
            Schema.SObjectType objectType = getObjectType(objectApiName);
            if (objectType == null) {
                return options;
            }
            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            String fieldKey = fieldApiName.toLowerCase();
            if (!fieldMap.containsKey(fieldKey)) {
                return options;
            }
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldKey).getDescribe();
            if (fieldDescribe.getType() != Schema.DisplayType.PICKLIST) {
                return options;
            }
            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive()) {
                    options.add(
                        new Map<String, Object>{
                            'label' => entry.getLabel(),
                            'value' => entry.getValue()
                        }
                    );
                }
            }
        } catch (Exception e) {
            // Picklists fall back to static options when describe is unavailable.
        }
        return options;
    }

    private static List<Map<String, Object>> fallbackInsuranceTypeOptions() {
        return new List<Map<String, Object>>{
            new Map<String, Object>{ 'label' => 'Comprehensive', 'value' => 'Comprehensive' },
            new Map<String, Object>{ 'label' => 'Third Party', 'value' => 'Third Party' }
        };
    }

    private static List<Map<String, Object>> fallbackValuerCategoryOptions() {
        return new List<Map<String, Object>>{
            new Map<String, Object>{ 'label' => 'Empanelled', 'value' => 'Empanelled' },
            new Map<String, Object>{ 'label' => 'MFC', 'value' => 'MFC' },
            new Map<String, Object>{ 'label' => 'Adroit', 'value' => 'Adroit' },
            new Map<String, Object>{ 'label' => 'TVS Credit', 'value' => 'TVS Credit' },
            new Map<String, Object>{ 'label' => 'Car Dekho', 'value' => 'Car Dekho' }
        };
    }

    private static List<Map<String, Object>> getValuerMasterOptions() {
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        Set<String> seenNames = new Set<String>();
        try {
            if (getObjectType('Benefi__c') != null) {
                String benefiQuery =
                    'SELECT Name, Ben_code__c FROM Benefi__c WHERE Status_Flag__c = \'L\' AND Beneficiary__c = \'' +
                    String.escapeSingleQuotes(VALUER_BENEFICIARY_VAL) +
                    '\' ORDER BY Name LIMIT 500';
                for (SObject row : Database.query(benefiQuery)) {
                    String name = (String) row.get('Name');
                    if (String.isBlank(name) || seenNames.contains(name)) {
                        continue;
                    }
                    seenNames.add(name);
                    options.add(
                        new Map<String, Object>{
                            'label' => name,
                            'value' => name,
                            'code' => (String) row.get('Ben_code__c')
                        }
                    );
                }
            }
        } catch (Exception e) {
            // Benefi master unavailable — use static valuer list below.
        }
        if (options.isEmpty()) {
            options.add(new Map<String, Object>{ 'label' => 'Valuer A', 'value' => 'Valuer A', 'code' => 'A' });
            options.add(new Map<String, Object>{ 'label' => 'Valuer B', 'value' => 'Valuer B', 'code' => 'B' });
        }
        return options;
    }

    private static Map<String, Object> emptyLoadResponse(
        String applicationId,
        String assetId,
        String insuranceId,
        String applicantId
    ) {
        Id resolvedAssetId = resolveAssetId(assetId, applicationId, applicantId);
        String sessionKey = buildSessionKey(
            applicationId,
            resolvedAssetId != null ? String.valueOf(resolvedAssetId) : assetId,
            insuranceId
        );
        if (!mfcSessionByKey.containsKey(sessionKey)) {
            mfcSessionByKey.put(sessionKey, new Map<String, Object>());
        }
        return new Map<String, Object>{
            'isSuccess' => true,
            'productType' => '',
            'resolvedAssetId' => resolvedAssetId != null ? String.valueOf(resolvedAssetId) : '',
            'resolvedApplicantId' => String.isNotBlank(applicantId) ? applicantId : '',
            'assetNotFound' => resolvedAssetId == null,
            'existingInsurance' => defaultExistingInsurance(),
            'vehicleValuation' => defaultVehicleValuation(),
            'valuationContext' => new Map<String, Object>{ 'mfcRequestId' => '', 'oemDealer' => false },
            'valuerMasterOptions' => getValuerMasterOptions(),
            'picklists' => buildPicklists()
        };
    }

    private static Map<String, Object> defaultExistingInsurance() {
        return new Map<String, Object>{
            'insuranceType' => '',
            'insuranceDeclaredValue' => '',
            'existingMotorInsurancePremium' => '',
            'insExpiryDate' => ''
        };
    }

    private static Map<String, Object> defaultVehicleValuation() {
        return new Map<String, Object>{
            'ownerName' => '',
            'ownerContactNumber' => '',
            'vehiclePlaceOfValuation' => '',
            'valuerCategory' => '',
            'valuer' => '',
            'valuerCode' => DEFAULT_VALUER_CODE,
            'slaNumber' => '',
            'colorOfVehicle' => '',
            'kmsRun' => ''
        };
    }

    private static String buildSessionKey(String applicationId, String assetId, String insuranceId) {
        return String.valueOf(applicationId) + '|' + String.valueOf(assetId) + '|' + String.valueOf(insuranceId);
    }

    private static String formatYmd(Date d) {
        if (d == null) {
            return '';
        }
        String m = d.month() < 10 ? '0' + String.valueOf(d.month()) : String.valueOf(d.month());
        String day = d.day() < 10 ? '0' + String.valueOf(d.day()) : String.valueOf(d.day());
        return String.valueOf(d.year()) + '-' + m + '-' + day;
    }

    private static String nullToEmpty(String s) {
        return s == null ? '' : s;
    }

    private static String decimalToUi(Decimal d) {
        return d == null ? '' : String.valueOf(d);
    }

    private static String stringVal(Object o) {
        if (o == null) {
            return null;
        }
        String s = String.valueOf(o).trim();
        return String.isBlank(s) ? null : s;
    }

    private static Decimal decimalVal(Object o) {
        if (o == null || String.valueOf(o).trim() == '') {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(o).replaceAll(',', '').trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Date dateVal(Object o) {
        if (o == null || String.valueOf(o).trim() == '') {
            return null;
        }
        try {
            return Date.valueOf(String.valueOf(o).trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, Object> integrationSuccess(String message, Boolean markRequestSubmitted) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => true, 'message' => message };
        if (markRequestSubmitted == true) {
            result.put('mfcRequestId', 'MFC-' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            result.put('mfcGetValuationDone', true);
        }
        return result;
    }

    private static Map<String, Object> failure(String message) {
        return new Map<String, Object>{ 'isSuccess' => false, 'message' => message };
    }
}