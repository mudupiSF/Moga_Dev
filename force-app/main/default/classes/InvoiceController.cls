/**
 * Invoice stage — load from Asset__c; save to Invoice_Details__c (Asset_Details__c → Asset__c).
 */
public with sharing class InvoiceController {
    private static final String OBJECT_INVOICE = 'Invoice_Details__c';
    private static final String OBJECT_ASSET = 'Asset__c';
    private static final String FIELD_INVOICE_ASSET = 'Asset_Details__c';
    private static final String DOCUMENT_TYPE = 'Invoice';
    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';
    private static final String INVOICE_PSS_STAGE = 'Invoice_PSS';
    private static final String INVOICE_OPS_STAGE = 'Invoice_OPS';
    private static final String INVOICE_OPS_VIEW_ID = 'Wheels_Invoice_OPS';

    private static final Map<String, String> UI_TO_INVOICE = new Map<String, String>{
        'isInvoiceLegible' => 'Is_Invoice_legible__c',
        'invoiceRemarks' => 'Invoice_Remark__c',
        'typeOfInvoice' => 'Type_of_Invoice__c',
        'taxCollectedAtSource' => 'Tax_Collected_at_Source__c',
        'taxInvoiceNo' => 'Tax_Invoice_No__c',
        'taxInvoiceDate' => 'Tax_Invoice_Date__c',
        'engineNo' => 'Engine_No__c',
        'gstType' => 'GST_Type__c',
        'sgst' => 'SGST__c',
        'utgst' => 'UTGST__c',
        'igst' => 'IGST__c',
        'gstTotal' => 'GST_Total__c',
        'exShowroomPrice' => 'Ex_showroom_price__c',
        'orpAsPerBank' => 'On_road_price__c',
        'invoiceAmountInclDiscount' => 'Invoice_Amount_incl_discounts__c',
        'isAmountAsPerUploaded' => 'Invoice_amount_as_per_Invoice_uploaded__c',
        'acceptUploadedInvoice' => 'Do_you_accept_uploaded_invoice__c'
    };

    private static final Set<String> SECTION_UI_KEYS = new Set<String>{ 'isInvoiceLegible', 'invoiceRemarks' };

    private static final Set<String> ASSET_READONLY_UI_KEYS = new Set<String>{
        'make',
        'model',
        'variant',
        'dealerName',
        'basicPrice',
        'discountExShowroom',
        'rtoRoadTax',
        'insurancePremium1Yr',
        'otherCharges',
        'exShowroomPrice',
        'gstTotal'
    };

    private static final Set<String> NUMERIC_UI_KEYS = new Set<String>{
        'taxCollectedAtSource',
        'sgst',
        'utgst',
        'igst',
        'gstTotal',
        'exShowroomPrice',
        'invoiceAmountInclDiscount'
    };

    private static Map<String, Schema.SObjectType> objectTypeCache;

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getInvoiceData(
        String recordId,
        String applicantId,
        String assetId
    ) {
        if (String.isBlank(recordId)) {
            return fail('Application Id is required.');
        }
        Id appId = toId(recordId);
        if (appId == null) {
            return fail('Invalid Application Id.');
        }

        Map<String, Object> loaded = retrieveInvoiceData(appId, applicantId, assetId);
        Set<String> readOnly = (Set<String>) loaded.get('readOnlyKeys');
        readOnly.remove('orpAsPerBank');
        readOnly.remove('invoiceAmountInclDiscount');
        Map<String, Object> docInfo = (Map<String, Object>) loaded.get('documentInfo');

        return new Map<String, Object>{
            'isSuccess' => true,
            'invoiceSection' => loaded.get('invoiceSection'),
            'invoiceDetails' => loaded.get('invoiceDetails'),
            'readOnlyFieldKeys' => new List<String>(readOnly),
            'picklists' => getInvoicePicklists(),
            'meta' => new Map<String, Object>{
                'recordId' => recordId,
                'assetId' => loaded.get('assetId') != null ? String.valueOf(loaded.get('assetId')) : '',
                'primaryApplicantId' => loaded.get('primaryApplicantId') != null
                    ? String.valueOf(loaded.get('primaryApplicantId'))
                    : '',
                'invoiceDocumentUploaded' => docInfo.get('uploaded'),
                'documentChecklistId' => docInfo.get('documentChecklistId'),
                'invoiceContentDocumentId' => docInfo.get('contentDocumentId'),
                'invoiceFileName' => docInfo.get('fileName'),
                'invoiceFileType' => docInfo.get('fileType'),
                'hasSavedInvoiceDetails' => loaded.get('hasSaved')
            }
        };
    }

    @AuraEnabled
    public static Map<String, Object> saveInvoiceData(
        String recordId,
        String applicantId,
        String payloadJson,
        String assetId
    ) {
        if (String.isBlank(recordId)) {
            return fail('Application Id is required.');
        }
        if (String.isBlank(payloadJson)) {
            return fail('Nothing to save.');
        }

        Id appId = toId(recordId);
        if (appId == null) {
            return fail('Invalid Application Id.');
        }

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
            Map<String, Object> section = (Map<String, Object>) root.get('invoiceSection');
            Map<String, Object> details = (Map<String, Object>) root.get('invoiceDetails');
            if (section == null) {
                section = new Map<String, Object>();
            }
            if (details == null) {
                details = new Map<String, Object>();
            }

            Id primaryApplicantId = resolveApplicantId(appId, applicantId);
            Asset__c asset = queryAssetForInvoice(primaryApplicantId, assetId);
            if (asset == null) {
                return fail('Asset is required. Complete vehicle details first.');
            }

            Id lineItemId = asset.Application_Line_Items__c;
            Id invoiceId = saveToInvoiceObject(asset.Id, lineItemId, section, details);

            Asset__c assetUpdate = new Asset__c(Id = asset.Id);
            if (!isBlank(details.get('engineNo'))) {
                assetUpdate.Engine_number__c = String.valueOf(details.get('engineNo')).trim();
            }
            if (!isBlank(details.get('chassisNo'))) {
                assetUpdate.Chassis_number__c = String.valueOf(details.get('chassisNo')).trim();
            }
            if (!isBlank(details.get('rtoRoadTax'))) {
                assetUpdate.RTO_Road_Tax_New__c = Decimal.valueOf(
                    String.valueOf(details.get('rtoRoadTax')).replace(',', '').trim()
                );
            }
            if (!isBlank(details.get('otherCharges'))) {
                assetUpdate.Other_charges__c = Decimal.valueOf(
                    String.valueOf(details.get('otherCharges')).replace(',', '').trim()
                );
            }
            update assetUpdate;

            return new Map<String, Object>{
                'isSuccess' => true,
                'message' => 'Invoice saved successfully.',
                'invoiceDetailsId' => String.valueOf(invoiceId)
            };
        } catch (Exception e) {
            return fail('Error while saving invoice: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> markInvoiceStageComplete(
        String applicationLineItemId,
        String currentViewId,
        String assetId
    ) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        Id lineItemId = toId(applicationLineItemId);
        if (lineItemId == null) {
            result.put('message', 'Application Line Item ID is required.');
            return result;
        }

        try {
            String invoiceStageKey = resolveInvoiceStageCompletedValue(currentViewId);
            Id resolvedAssetId = toId(assetId);

            if (resolvedAssetId != null) {
                List<Asset__c> assets = [
                    SELECT Id, Stage_Completed__c, Application_Line_Items__c
                    FROM Asset__c
                    WHERE Id = :resolvedAssetId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                if (assets.isEmpty()) {
                    result.put('message', 'Asset not found.');
                    return result;
                }
                Asset__c asset = assets[0];

                Id assetLineItemId = asset.Application_Line_Items__c != null
                    ? asset.Application_Line_Items__c
                    : lineItemId;

                if (countAssetsOnLineItem(assetLineItemId) > 1) {
                    asset.Stage_Completed__c = appendStageCompleted(
                        asset.Stage_Completed__c,
                        invoiceStageKey
                    );
                    update asset;

                    if (areAllLineItemAssetsInvoiced(assetLineItemId, invoiceStageKey)) {
                        markLineItemInvoiceStageComplete(assetLineItemId, invoiceStageKey);
                    }
                } else {
                    markLineItemInvoiceStageComplete(assetLineItemId, invoiceStageKey);
                }

                result.put('isSuccess', true);
                result.put('applicationLineItemId', String.valueOf(assetLineItemId));
                return result;
            }

            markLineItemInvoiceStageComplete(lineItemId, invoiceStageKey);

            result.put('isSuccess', true);
            result.put('applicationLineItemId', String.valueOf(lineItemId));
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }

        return result;
    }

    private static void markLineItemInvoiceStageComplete(Id lineItemId, String invoiceStageKey) {
        List<Application_Line_Item__c> lineItems = [
            SELECT Id, Stage_Completed__c
            FROM Application_Line_Item__c
            WHERE Id = :lineItemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (lineItems.isEmpty()) {
            throw new AuraHandledException('Application Line Item not found.');
        }

        Application_Line_Item__c lineItem = lineItems[0];
        lineItem.Stage_Completed__c = appendStageCompleted(
            lineItem.Stage_Completed__c,
            invoiceStageKey
        );
        update lineItem;
    }

    private static Boolean areAllLineItemAssetsInvoiced(Id lineItemId, String invoiceStageKey) {
        List<Asset__c> assets = [
            SELECT Stage_Completed__c
            FROM Asset__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
        ];
        if (assets.isEmpty()) {
            return false;
        }
        for (Asset__c asset : assets) {
            if (!hasStageCompleted(asset.Stage_Completed__c, invoiceStageKey)) {
                return false;
            }
        }
        return true;
    }

    private static Integer countAssetsOnLineItem(Id lineItemId) {
        if (lineItemId == null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM Asset__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
        ];
    }

    private static Map<String, Object> retrieveInvoiceData(
        Id appId,
        String applicantId,
        String assetId
    ) {
        Map<String, Object> section = new Map<String, Object>();
        Map<String, Object> details = new Map<String, Object>();
        Set<String> readOnly = new Set<String>();

        Id primaryApplicantId = resolveApplicantId(appId, applicantId);
        Asset__c asset = queryAssetForInvoice(primaryApplicantId, assetId);
        Id resolvedAssetId = asset != null ? asset.Id : null;

        if (asset != null) {
            mergeFromAsset(details, readOnly, asset);
        }

        Boolean hasSaved = false;
        if (resolvedAssetId != null) {
            Map<String, Object> saved = querySavedInvoiceFields(resolvedAssetId);
            if (!saved.isEmpty()) {
                hasSaved = true;
                mergeSavedInvoice(details, section, saved);
            }
        }
        Id lineItemId = asset != null ? asset.Application_Line_Items__c : null;
        Map<String, Object> docInfo = queryInvoiceDocument(
            appId,
            primaryApplicantId,
            resolvedAssetId,
            lineItemId
        );
        return new Map<String, Object>{
            'invoiceSection' => section,
            'invoiceDetails' => details,
            'readOnlyKeys' => readOnly,
            'assetId' => resolvedAssetId,
            'primaryApplicantId' => primaryApplicantId,
            'hasSaved' => hasSaved,
            'documentInfo' => docInfo
        };
    }

    private static void mergeFromAsset(Map<String, Object> details, Set<String> readOnly, Asset__c asset) {
        putUi(details, readOnly, 'dealerName', asset.Dealer_Sub_dealer_name__c);
        putUi(details, readOnly, 'make', asset.Make__c);
        putUi(details, readOnly, 'model', asset.Model__c);
        putUi(details, readOnly, 'variant', asset.Variant__c);
        putUi(details, readOnly, 'basicPrice', asset.Basic_Price__c);
        putUi(details, readOnly, 'discountExShowroom', asset.Discount_on_Basic_Price__c);
        putUi(details, readOnly, 'exShowroomPrice', asset.Ex_showroom_price__c);
        putUi(details, readOnly, 'insurancePremium1Yr', asset.X1st_yr_Insurance_Premium__c);
        Boolean usedVehicle = 'Used'.equalsIgnoreCase(asset.Vehicle_type__c)
            || 'Refinance'.equalsIgnoreCase(asset.Vehicle_type__c);
        Set<String> engineChassisReadOnly = usedVehicle ? readOnly : null;
        putUi(details, engineChassisReadOnly, 'engineNo', asset.Engine_number__c);
        putUi(details, engineChassisReadOnly, 'chassisNo', asset.Chassis_number__c);
        putUi(details, readOnly, 'rtoRoadTax', asset.RTO_Road_Tax_New__c);
        putUi(details, readOnly, 'otherCharges', asset.Other_charges__c);
        putUi(details, readOnly, 'gstTotal', asset.GST_Amount__c);
    }

    private static void mergeSavedInvoice(
        Map<String, Object> details,
        Map<String, Object> section,
        Map<String, Object> saved
    ) {
        for (String key : saved.keySet()) {
            if (ASSET_READONLY_UI_KEYS.contains(key)) {
                continue;
            }
            Object val = saved.get(key);
            if (SECTION_UI_KEYS.contains(key)) {
                section.put(key, val);
            } else {
                details.put(key, val);
            }
        }
    }

    private static Id saveToInvoiceObject(
        Id assetId,
        Id lineItemId,
        Map<String, Object> section,
        Map<String, Object> details
    ) {
        Schema.SObjectType invoiceType = getObjectType(OBJECT_INVOICE);
        if (invoiceType == null) {
            throw new AuraHandledException('Invoice_Details__c is not available in this org.');
        }

        SObject record = queryInvoiceByAsset(assetId);
        if (record == null) {
            record = invoiceType.newSObject();
            record.put(FIELD_INVOICE_ASSET, assetId);
        }
        if (lineItemId != null && hasField(OBJECT_INVOICE, 'Application_Line_Item__c')) {
            record.put('Application_Line_Item__c', lineItemId);
        }

        Set<String> appliedApis = new Set<String>();
        applyUiFields(record, section, appliedApis);
        applyUiFields(record, details, appliedApis);
        applyGstTotalFromAsset(record, assetId, appliedApis);

        if (appliedApis.isEmpty()) {
            throw new AuraHandledException('No invoice fields to save. Enter invoice details and try again.');
        }

        Boolean isInsert = record.get('Id') == null;
        Database.SaveResult sr = isInsert
            ? Database.insert(record, AccessLevel.SYSTEM_MODE)
            : Database.update(record, AccessLevel.SYSTEM_MODE);
        if (!sr.isSuccess()) {
            throw new AuraHandledException(formatDmlErrors(sr.getErrors()));
        }
        return sr.getId();
    }

    private static Map<String, Object> getInvoicePicklists() {
        List<Map<String, Object>> yesNo = picklistFromValues(new List<String>{ 'Yes', 'No' });
        return new Map<String, Object>{
            'isInvoiceLegible' => yesNo,
            'isAmountAsPerUploaded' => yesNo,
            'acceptUploadedInvoice' => yesNo,
            'gstType' => picklistFromField(
                OBJECT_INVOICE,
                'GST_Type__c',
                new List<String>{ 'Inter State', 'Intra State', 'UT' }
            ),
            'typeOfInvoice' => picklistFromField(
                OBJECT_INVOICE,
                'Type_of_Invoice__c',
                new List<String>{ 'Tax Invoice', 'Performa Invoice' }
            )
        };
    }

    private static List<Map<String, Object>> picklistFromField(
        String objectApi,
        String fieldApi,
        List<String> fallbacks
    ) {
        List<Map<String, Object>> fromOrg = picklistFromFieldDescribe(objectApi, fieldApi);
        return fromOrg.isEmpty() ? picklistFromValues(fallbacks) : fromOrg;
    }

    private static List<Map<String, Object>> picklistFromFieldDescribe(String objectApi, String fieldApi) {
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectApi);
        if (fieldMap == null) {
            return options;
        }
        Schema.SObjectField token = fieldMap.get(fieldApi.toLowerCase());
        if (token == null) {
            return options;
        }
        for (Schema.PicklistEntry e : token.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                options.add(new Map<String, Object>{ 'label' => e.getLabel(), 'value' => e.getValue() });
            }
        }
        return options;
    }

    private static List<Map<String, Object>> picklistFromValues(List<String> values) {
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        for (String v : values) {
            options.add(new Map<String, Object>{ 'label' => v, 'value' => v });
        }
        return options;
    }

    private static Asset__c queryAssetForInvoice(Id applicantId, String assetId) {
        if (getObjectType(OBJECT_ASSET) == null) {
            return null;
        }

        Id resolvedAssetId = toId(assetId);
        if (resolvedAssetId != null) {
            List<Asset__c> assetsById = [
                SELECT
                    Id,
                    Application_Line_Items__c,
                    Make__c,
                    Model__c,
                    Variant__c,
                    Basic_Price__c,
                    Discount_on_Basic_Price__c,
                    Ex_showroom_price__c,
                    X1st_yr_Insurance_Premium__c,
                    Dealer_Sub_dealer_name__c,
                    Vehicle_type__c,
                    Engine_number__c,
                    Chassis_number__c,
                    RTO_Road_Tax_New__c,
                    Other_charges__c,
                    GST_Amount__c
                FROM Asset__c
                WHERE Id = :resolvedAssetId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return assetsById.isEmpty() ? null : assetsById[0];
        }

        if (applicantId == null) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT
                Id,
                Application_Line_Items__c,
                Make__c,
                Model__c,
                Variant__c,
                Basic_Price__c,
                Discount_on_Basic_Price__c,
                Ex_showroom_price__c,
                X1st_yr_Insurance_Premium__c,
                Dealer_Sub_dealer_name__c,
                Vehicle_type__c,
                Engine_number__c,
                Chassis_number__c,
                RTO_Road_Tax_New__c,
                Other_charges__c,
                GST_Amount__c
            FROM Asset__c
            WHERE Applicant__c = :applicantId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0];
    }

    private static Map<String, Object> querySavedInvoiceFields(Id assetId) {
        Map<String, Object> out = new Map<String, Object>();
        if (assetId == null || !hasField(OBJECT_INVOICE, FIELD_INVOICE_ASSET)) {
            return out;
        }

        Map<String, Schema.SObjectField> fieldMap = getFieldMap(OBJECT_INVOICE);
        List<String> selectFields = new List<String>{ 'Id' };
        for (String api : UI_TO_INVOICE.values()) {
            if (fieldMap.containsKey(api.toLowerCase()) && !selectFields.contains(api)) {
                selectFields.add(api);
            }
        }

        List<SObject> rows = Database.query(
            'SELECT ' +
            String.join(selectFields, ',') +
            ' FROM ' +
            OBJECT_INVOICE +
            ' WHERE ' +
            FIELD_INVOICE_ASSET +
            ' = :assetId WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT 1'
        );
        if (rows.isEmpty()) {
            return out;
        }

        SObject rec = rows[0];
        for (String uiKey : UI_TO_INVOICE.keySet()) {
            String api = UI_TO_INVOICE.get(uiKey);
            if (!selectFields.contains(api)) {
                continue;
            }
            Object val = rec.get(api);
            if (!isBlank(val)) {
                out.put(uiKey, toUiString(uiKey, val));
            }
        }
        return out;
    }

    private static SObject queryInvoiceByAsset(Id assetId) {
        if (assetId == null || !hasField(OBJECT_INVOICE, FIELD_INVOICE_ASSET)) {
            return null;
        }
        List<SObject> rows = Database.query(
            'SELECT Id FROM ' +
            OBJECT_INVOICE +
            ' WHERE ' +
            FIELD_INVOICE_ASSET +
            ' = :assetId WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0];
    }

    private static void applyGstTotalFromAsset(SObject record, Id assetId, Set<String> appliedApis) {
        if (record == null || assetId == null || appliedApis.contains('GST_Total__c')) {
            return;
        }
        if (!hasField(OBJECT_INVOICE, 'GST_Total__c') || !hasField(OBJECT_ASSET, 'GST_Amount__c')) {
            return;
        }
        List<Asset__c> assets = [
            SELECT GST_Amount__c
            FROM Asset__c
            WHERE Id = :assetId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (assets.isEmpty() || assets[0].GST_Amount__c == null) {
            return;
        }
        record.put('GST_Total__c', assets[0].GST_Amount__c);
        appliedApis.add('GST_Total__c');
    }

    private static void applyUiFields(SObject record, Map<String, Object> values, Set<String> appliedApis) {
        if (record == null || values == null) {
            return;
        }
        for (String uiKey : values.keySet()) {
            String api = UI_TO_INVOICE.get(uiKey);
            if (api == null || !hasField(OBJECT_INVOICE, api) || appliedApis.contains(api)) {
                continue;
            }
            Object raw = values.get(uiKey);
            if (isBlank(raw)) {
                continue;
            }
            Object converted = toSObjectValue(uiKey, api, raw, getDescribe(OBJECT_INVOICE, api));
            if (converted != null) {
                record.put(api, converted);
                appliedApis.add(api);
            }
        }
    }

    private static Object toSObjectValue(
        String uiKey,
        String fieldApi,
        Object raw,
        Schema.DescribeFieldResult fd
    ) {
        String text = String.valueOf(raw).replace(',', '').trim();
        if (fd == null) {
            return text;
        }
        Schema.DisplayType t = fd.getType();
        if (
            uiKey == 'orpAsPerBank' ||
            fieldApi == 'On_road_price__c' ||
            t == Schema.DisplayType.STRING ||
            t == Schema.DisplayType.TEXTAREA
        ) {
            return String.isBlank(text) ? null : text;
        }
        if (t == Schema.DisplayType.PICKLIST || t == Schema.DisplayType.MULTIPICKLIST) {
            for (Schema.PicklistEntry e : fd.getPicklistValues()) {
                if (e.isActive() && (e.getValue().equalsIgnoreCase(text) || e.getLabel().equalsIgnoreCase(text))) {
                    return e.getValue();
                }
            }
            throw new AuraHandledException(
                'Invalid value for ' + fieldApi + ': "' + text + '". Select a valid option.'
            );
        }
        if (NUMERIC_UI_KEYS.contains(uiKey) || t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.DOUBLE) {
            return String.isBlank(text) ? null : Decimal.valueOf(text);
        }
        if (uiKey == 'taxInvoiceDate' || t == Schema.DisplayType.DATE) {
            try {
                return Date.valueOf(text);
            } catch (Exception e) {
                return null;
            }
        }
        if (t == Schema.DisplayType.BOOLEAN) {
            return text.equalsIgnoreCase('true') || text.equalsIgnoreCase('yes');
        }
        return text;
    }

    private static Id resolveApplicantId(Id appId, String applicantId) {
        if (String.isNotBlank(applicantId)) {
            Id parsed = toId(applicantId);
            if (parsed != null) {
                return parsed;
            }
        }
        Map<String, Schema.SObjectField> fm = getFieldMap('Applicant__c');
        if (fm == null) {
            return null;
        }
        if (!fm.containsKey('Application__c')) {
            return null;
        }
        String borrowerFilter = fm.containsKey('Applicant_Type__c')
            ? ' AND Applicant_Type__c = :APPLICANT_TYPE_BORROWER'
            : '';
        String inactiveFilter = fm.containsKey('In_Active_Applicant__c') ? ' AND In_Active_Applicant__c = FALSE' : '';
        List<Applicant__c> rows = Database.query(
            'SELECT Id FROM Applicant__c WHERE Application__c = :appId' +
            borrowerFilter +
            inactiveFilter +
            ' WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Map<String, Object> queryInvoiceDocument(
        Id appId,
        Id applicantId,
        Id assetId,
        Id lineItemId
    ) {
        Map<String, Object> result = new Map<String, Object>{
            'uploaded' => false,
            'documentChecklistId' => '',
            'contentDocumentId' => '',
            'fileName' => '',
            'fileType' => 'PDF'
        };
        if (appId == null || applicantId == null) {
            return result;
        }
        Map<String, Schema.SObjectField> fm = getFieldMap('Document_CheckList__c');
        if (fm == null || !fm.containsKey('Application__c') || !fm.containsKey('Document_Type__c')) {
            return result;
        }
        String lineItemFilter = '';
        if (lineItemId != null && fm.containsKey('Application_Line_Items__c')) {
            lineItemFilter = ' AND Application_Line_Items__c = :lineItemId';
        }
        String assetFilter = '';
        if (assetId != null && fm.containsKey('Asset__c')) {
            assetFilter = ' AND Asset__c = :assetId';
        }
        String extra = fm.containsKey('ContentVersionId__c') ? ', ContentVersionId__c' : '';
        List<SObject> rows = Database.query(
            'SELECT Id' +
            extra +
            ' FROM Document_CheckList__c WHERE Application__c = :appId AND Applicant__c = :applicantId' +
            lineItemFilter +
            assetFilter +
            ' AND Document_Type__c = :DOCUMENT_TYPE WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1'
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
        result.put('fileName', String.isNotBlank(version.Title) ? version.Title : DOCUMENT_TYPE);
        if (String.isNotBlank(version.FileExtension)) {
            result.put('fileType', version.FileExtension.toUpperCase());
        }
        return result;
    }

    private static void putUi(Map<String, Object> details, Set<String> readOnly, String uiKey, Object value) {
        if (isBlank(value)) {
            return;
        }
        details.put(uiKey, toUiString(uiKey, value));
        if (readOnly != null) {
            readOnly.add(uiKey);
        }
    }

    private static String toUiString(String uiKey, Object value) {
        if (value instanceof Date) {
            return formatDateOnly((Date) value);
        }
        if (value instanceof Datetime) {
            return formatDateOnly(((Datetime) value).date());
        }
        if (value instanceof Decimal || value instanceof Integer || value instanceof Long) {
            return String.valueOf(value);
        }
        if (value instanceof Boolean) {
            return ((Boolean) value) ? 'true' : 'false';
        }
        String text = String.valueOf(value).trim();
        if (uiKey == 'taxInvoiceDate') {
            Integer spaceIdx = text.indexOf(' ');
            if (spaceIdx > 0) {
                return text.substring(0, spaceIdx);
            }
            Integer tIdx = text.indexOf('T');
            if (tIdx > 0) {
                return text.substring(0, tIdx);
            }
        }
        return text;
    }

    private static String formatDateOnly(Date d) {
        if (d == null) {
            return '';
        }
        return String.valueOf(d.year()) +
            '-' +
            String.valueOf(d.month()).leftPad(2, '0') +
            '-' +
            String.valueOf(d.day()).leftPad(2, '0');
    }

    private static Boolean isBlank(Object value) {
        return value == null || String.isBlank(String.valueOf(value).trim());
    }

    private static Schema.SObjectType getObjectType(String objectApi) {
        if (objectTypeCache == null) {
            objectTypeCache = Schema.getGlobalDescribe();
        }
        return objectTypeCache.get(objectApi);
    }

    private static Map<String, Schema.SObjectField> getFieldMap(String objectApi) {
        Schema.SObjectType objectType = getObjectType(objectApi);
        return objectType == null ? null : objectType.getDescribe().fields.getMap();
    }

    private static Boolean hasField(String objectApi, String fieldApi) {
        Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectApi);
        return fieldMap != null && fieldMap.containsKey(fieldApi.toLowerCase());
    }

    private static Schema.DescribeFieldResult getDescribe(String objectApi, String fieldApi) {
        Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectApi);
        if (fieldMap == null) {
            return null;
        }
        Schema.SObjectField token = fieldMap.get(fieldApi.toLowerCase());
        return token == null ? null : token.getDescribe();
    }

    private static Id toId(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception e) {
            return null;
        }
    }

    private static String formatDmlErrors(List<Database.Error> errors) {
        List<String> msgs = new List<String>();
        for (Database.Error err : errors) {
            msgs.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return String.join(msgs, '; ');
    }

    private static String resolveInvoiceStageCompletedValue(String currentViewId) {
        if (INVOICE_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
            return INVOICE_OPS_STAGE;
        }
        return INVOICE_PSS_STAGE;
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

    private static Map<String, Object> fail(String message) {
        return new Map<String, Object>{ 'isSuccess' => false, 'message' => message };
    }
}