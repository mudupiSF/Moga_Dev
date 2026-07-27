/**
 * Loan Terms — scheme from Schemes__c; Pay-In / Pay-Out on Application_Line_Item__c.
 *
 * Schemes__c → UI (pay-in only):
 *   ServiceCharges__c → serviceCharges
 *   DocCharges__c → documentationCharges
 *   Stamping_Charges__c → applicableStampingCharges
 * Pay-out fields are not sourced from Schemes__c; user enters on Application Line Item.
 */
public with sharing class LoanTermsController {

    private static final String OBJECT_SCHEMES = 'Schemes__c';
    private static final String OBJECT_ALI = 'Application_Line_Item__c';
    private static final String ALI_SCHEME_FIELD = 'Schemes__c';
    private static final String LOAN_TERMS_STAGE = 'Loan Terms';

    private static final List<String> SCHEME_PAYIN_FIELD_APIS = new List<String>{
        'ServiceCharges__c',
        'DocCharges__c',
        'Stamping_Charges__c'
    };
    private static final Map<String, String> SCHEME_PAYIN_UI_KEYS = new Map<String, String>{
        'ServiceCharges__c' => 'serviceCharges',
        'DocCharges__c' => 'documentationCharges',
        'Stamping_Charges__c' => 'applicableStampingCharges'
    };
    private static final List<String> SCHEME_PAYOUT_FIELD_APIS = new List<String>();
    private static final Map<String, String> SCHEME_PAYOUT_UI_KEYS = new Map<String, String>();

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getLoanTermsData(
        String recordId,
        String applicantId,
        String applicationLineItemId
    ) {
        Id lineItemId = resolveApplicationLineItemId(recordId, applicantId, applicationLineItemId);
        Application_Line_Item__c ali = lineItemId != null ? queryApplicationLineItem(lineItemId) : null;

        List<Map<String, Object>> schemes = queryAllSchemesWithTerms();
        String selectedSchemeId = getLineItemSchemeId(ali);

        Map<String, Object> payIn = buildPayInFromLineItemOrBlank(ali);
        Map<String, Object> payOut = buildPayOutFromLineItemOrBlank(ali);

        if (
            String.isNotBlank(selectedSchemeId)
            && (!hasAnyPayInData(payIn) || !hasAnyPayOutData(payOut))
        ) {
            Map<String, Object> fromScheme = resolveSchemeTermsById(selectedSchemeId, schemes);
            if (fromScheme != null) {
                if (!hasAnyPayInData(payIn)) {
                    payIn = (Map<String, Object>) fromScheme.get('payIn');
                }
                if (!hasAnyPayOutData(payOut)) {
                    payOut = (Map<String, Object>) fromScheme.get('payOut');
                }
            }
        }

        Map<String, Object> applicationContext = loadApplicationContext(
            recordId,
            applicantId,
            applicationLineItemId
        );
        if (String.isNotBlank((String) applicationContext.get('productType'))) {
            schemes = filterSchemesForProduct(schemes, (String) applicationContext.get('productType'));
        }

        return new Map<String, Object>{
            'schemes' => schemes,
            'selectedSchemeId' => selectedSchemeId,
            'payInSection' => buildPayInFieldConfig(payIn),
            'payOutSection' => buildPayOutFieldConfig(payOut),
            'meta' => new Map<String, Object>{
                'recordId' => recordId,
                'applicationLineItemId' => lineItemId != null ? String.valueOf(lineItemId) : '',
                'productType' => applicationContext.get('productType'),
                'finalTermId' => applicationContext.get('finalTermId'),
                'assetId' => applicationContext.get('assetId'),
                'isBorrowerNonIndividual' => applicationContext.get('isBorrowerNonIndividual')
            }
        };
    }

    private static Map<String, Object> loadApplicationContext(
        String recordId,
        String applicantId,
        String applicationLineItemId
    ) {
        Map<String, Object> context = new Map<String, Object>{
            'productType' => '',
            'finalTermId' => '',
            'assetId' => '',
            'isBorrowerNonIndividual' => false
        };
        if (String.isBlank(recordId)) {
            return context;
        }

        try {
            List<Application__c> apps = [
                SELECT Id, Product__c,(SELECT Type__c FROM Applicants__r WHERE Applicant_Type__c = 'Borrower' LIMIT 1)
                FROM Application__c
                WHERE Id = :recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!apps.isEmpty() && String.isNotBlank(apps[0].Product__c)) {
                context.put('productType', apps[0].Product__c);
            }

            Id finalTermId = resolveFinalTermId(recordId);
            if (finalTermId != null) {
                context.put('finalTermId', String.valueOf(finalTermId));
            }

            Id assetId = resolveAssetIdForLineItem(parseId(applicationLineItemId));
            if (assetId == null) {
                assetId = resolveAssetId(applicantId);
            }
            if (assetId != null) {
                context.put('assetId', String.valueOf(assetId));
            }

            context.put(
                'isBorrowerNonIndividual',
                isNonIndividualApplicantType(apps[0].Applicants__r[0].Type__c)
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoanTermsController.loadApplicationContext: ' + e.getMessage());
        }
        return context;
    }

    private static List<Map<String, Object>> filterSchemesForProduct(
        List<Map<String, Object>> schemes,
        String productType
    ) {
        if (schemes == null || schemes.isEmpty() || String.isBlank(productType)) {
            return schemes;
        }
        if (!objectHasField(OBJECT_SCHEMES, 'Product__c')) {
            return schemes;
        }

        Set<String> productMatchers = buildSchemeProductMatchers(productType);
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> scheme : schemes) {
            String schemeProduct = stringVal(scheme.get('product'));
            if (String.isBlank(schemeProduct) || productMatchers.contains(schemeProduct.trim().toLowerCase())) {
                filtered.add(scheme);
            }
        }
        return filtered.isEmpty() ? schemes : filtered;
    }

    private static Set<String> buildSchemeProductMatchers(String productType) {
        Set<String> matchers = new Set<String>();
        String trimmed = productType.trim();
        matchers.add(trimmed.toLowerCase());

        Map<String, String> aliases = new Map<String, String>{
            'tw' => 'two wheeler',
            '2w' => 'two wheeler',
            'pv' => 'passenger vehicles',
            '4w' => 'passenger vehicles',
            'cv' => 'commercial vehicle',
            'scv' => 'small commercial vehicle',
            'lcv' => 'light commercial vehicle',
            'tfe' => 'tractor'
        };
        String lower = trimmed.toLowerCase();
        if (aliases.containsKey(lower)) {
            matchers.add(aliases.get(lower));
        }
        if (lower.contains('two wheeler')) {
            matchers.add('two wheeler');
            matchers.add('tw');
            matchers.add('2w');
        }
        if (lower.contains('passenger')) {
            matchers.add('passenger vehicles');
            matchers.add('pv');
        }
        return matchers;
    }

    private static Id resolveFinalTermId(String applicationId) {
        Schema.SObjectType finalTermType = getObjectType('Final_Term__c');
        if (finalTermType == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap = finalTermType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey('loan_application__c')) {
            return null;
        }
        List<SObject> rows = Database.query(
            'SELECT Id FROM Final_Term__c WHERE Loan_Application__c = :applicationId WITH SYSTEM_MODE LIMIT 1'
        );
        return rows.isEmpty() ? null : (Id) rows[0].get('Id');
    }

    private static Id resolveAssetId(String applicantId) {
        if (String.isBlank(applicantId)) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT Id
            FROM Asset__c
            WHERE Applicant__c = :applicantId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Id;
    }

    private static Boolean isNonIndividualApplicantType(String typeValue) {
        if (String.isBlank(typeValue)) {
            return false;
        }
        String normalized = typeValue.trim().toLowerCase().replace(' ', '').replace('-', '');
        return normalized == 'nonindividual';
    }

    @AuraEnabled
    public static Map<String, Object> saveLoanTermsData(
        String recordId,
        String applicantId,
        String applicationLineItemId,
        String payloadJson
    ) {
        if (String.isBlank(recordId)) {
            return failure('Record Id is required.');
        }

        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
            Map<String, Object> payIn = payload != null && payload.containsKey('payIn')
                ? (Map<String, Object>) payload.get('payIn')
                : new Map<String, Object>();
            Map<String, Object> payOut = payload != null && payload.containsKey('payOut')
                ? (Map<String, Object>) payload.get('payOut')
                : new Map<String, Object>();
            String schemeId = payload != null ? (String) payload.get('schemeId') : null;

            if (String.isBlank(schemeId)) {
                return failure('Scheme is required.');
            }

            Id lineItemId = resolveApplicationLineItemId(recordId, applicantId, applicationLineItemId);
            if (lineItemId == null) {
                return failure(
                    'Could not find an Application Line Item. Ensure an Asset is linked to Application Line Items for this application.',
                    buildSaveDebug(recordId, applicantId, schemeId, payIn, payOut, null)
                );
            }

            Application_Line_Item__c existingLineItem = queryApplicationLineItem(lineItemId);
            Application_Line_Item__c ali = new Application_Line_Item__c(Id = lineItemId);
            setLineItemSchemeId(ali, schemeId);
            applyPayInToLineItem(ali, payIn);
            applyPayOutToLineItem(ali, payOut);
            ali.Stage_Completed__c = appendStageCompleted(
                existingLineItem?.Stage_Completed__c,
                LOAN_TERMS_STAGE
            );

            Database.SaveResult result = Database.update(ali, AccessLevel.SYSTEM_MODE);
            if (!result.isSuccess()) {
                return failure(
                    formatDmlErrors(result.getErrors()),
                    buildSaveDebug(recordId, applicantId, schemeId, payIn, payOut, lineItemId)
                );
            }

            return new Map<String, Object>{
                'isSuccess' => true,
                'message' => 'Loan terms saved successfully.',
                'applicationLineItemId' => String.valueOf(lineItemId),
                'debug' => buildSaveDebug(recordId, applicantId, schemeId, payIn, payOut, lineItemId)
            };
        } catch (Exception e) {
            return failure(
                'Error while saving loan terms: ' + e.getMessage(),
                new Map<String, Object>{ 'exceptionType' => e.getTypeName(), 'stackTrace' => e.getStackTraceString() }
            );
        }
    }

    private static List<Map<String, Object>> queryAllSchemesWithTerms() {
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (SObject scheme : querySchemesRecords()) {
            Map<String, Object> payIn = mapSchemeToPayIn(scheme);
            Map<String, Object> payOut = mapSchemeToPayOut(scheme);
            Map<String, Object> row = new Map<String, Object>{
                'id' => String.valueOf(scheme.get('Id')),
                'name' => stringVal(scheme.get('Name')),
                'schemeCode' => stringVal(scheme.get('Scheme_Code__c')),
                'payIn' => payIn,
                'payOut' => payOut
            };
            if (objectHasField(OBJECT_SCHEMES, 'Product__c')) {
                row.put('product', stringVal(scheme.get('Product__c')));
            }
            results.add(row);
        }
        return results;
    }

    private static List<SObject> querySchemesRecords() {
        List<String> selectFields = new List<String>{ 'Id', 'Name' };
        if (objectHasField(OBJECT_SCHEMES, 'Scheme_Code__c')) {
            selectFields.add('Scheme_Code__c');
        }
        if (objectHasField(OBJECT_SCHEMES, 'Product__c')) {
            selectFields.add('Product__c');
        }
        for (String apiName : SCHEME_PAYIN_FIELD_APIS) {
            if (objectHasField(OBJECT_SCHEMES, apiName)) {
                selectFields.add(apiName);
            }
        }
        for (String apiName : SCHEME_PAYOUT_FIELD_APIS) {
            if (objectHasField(OBJECT_SCHEMES, apiName)) {
                selectFields.add(apiName);
            }
        }
        String soql =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Schemes__c ORDER BY Name LIMIT 500';
        return Database.query(soql);
    }

    private static Map<String, Object> resolveSchemeTermsById(
        String schemeId,
        List<Map<String, Object>> schemes
    ) {
        if (String.isBlank(schemeId) || schemes == null) {
            return null;
        }
        for (Map<String, Object> row : schemes) {
            if (schemeId == String.valueOf(row.get('id'))) {
                return row;
            }
        }
        return null;
    }

    private static Map<String, Object> mapSchemeToPayIn(SObject scheme) {
        Map<String, Object> payIn = emptyPayIn();
        for (String apiName : SCHEME_PAYIN_FIELD_APIS) {
            if (!objectHasField(OBJECT_SCHEMES, apiName)) {
                continue;
            }
            String uiKey = SCHEME_PAYIN_UI_KEYS.get(apiName);
            payIn.put(uiKey, formatSchemeFieldValue(scheme.get(apiName), apiName));
        }
        return payIn;
    }

    private static Map<String, Object> mapSchemeToPayOut(SObject scheme) {
        Map<String, Object> payOut = emptyPayOut();
        for (String apiName : SCHEME_PAYOUT_FIELD_APIS) {
            if (!objectHasField(OBJECT_SCHEMES, apiName)) {
                continue;
            }
            String uiKey = SCHEME_PAYOUT_UI_KEYS.get(apiName);
            payOut.put(uiKey, formatSchemeFieldValue(scheme.get(apiName), apiName));
        }
        return payOut;
    }

    private static String formatSchemeFieldValue(Object value, String apiName) {
        return formatNumber(value);
    }

    private static Map<String, Object> buildPayInFromLineItemOrBlank(Application_Line_Item__c ali) {
        if (ali == null) {
            return emptyPayIn();
        }
        Map<String, Object> fromAli = mapPayInFromLineItem(ali);
        if (!hasAnyPayInData(fromAli)) {
            return emptyPayIn();
        }
        fromAli.put(
            'stampingChargesPaidBy',
            defaultStampingPaidBy((String) fromAli.get('stampingChargesPaidBy'))
        );
        return fromAli;
    }

    private static Map<String, Object> buildPayOutFromLineItemOrBlank(Application_Line_Item__c ali) {
        if (ali == null) {
            return emptyPayOut();
        }
        Map<String, Object> fromAli = mapPayOutFromLineItem(ali);
        return hasAnyPayOutData(fromAli) ? fromAli : emptyPayOut();
    }

    private static Map<String, Object> emptyPayIn() {
        return new Map<String, Object>{
            'serviceCharges' => '',
            'documentationCharges' => '',
            'applicableStampingCharges' => '',
            'cess' => '',
            'stampingChargesPaidBy' => defaultStampingPaidBy(null),
            'tradeCertificate' => ''
        };
    }

    private static Map<String, Object> emptyPayOut() {
        return new Map<String, Object>{
            'mainDealerAmt' => '',
            'subDealerAmt' => '',
            'giftAmt' => '',
            'dsmName' => '',
            'dsmIncentive' => ''
        };
    }

    private static Map<String, Object> mapPayInFromLineItem(Application_Line_Item__c ali) {
        return new Map<String, Object>{
            'serviceCharges' => stringVal(ali.Service_charges__c),
            'documentationCharges' => stringVal(ali.Documentation_charges__c),
            'applicableStampingCharges' => stringVal(ali.Applicable_Stamping_Charges__c),
            'cess' => stringVal(ali.Cess__c),
            'stampingChargesPaidBy' => stringVal(ali.Stamping_Charges_Paid_By__c),
            'tradeCertificate' => stringVal(ali.Trade_certificate__c)
        };
    }

    private static Map<String, Object> mapPayOutFromLineItem(Application_Line_Item__c ali) {
        return new Map<String, Object>{
            'mainDealerAmt' => stringVal(ali.Dealer_incentive_amount_main_dealer__c),
            'subDealerAmt' => stringVal(ali.Dealer_incentive_amount_sub_dealer__c),
            'giftAmt' => stringVal(ali.Gift_through_dealer_amount__c),
            'dsmName' => stringVal(ali.DSM_Name__c),
            'dsmIncentive' => stringVal(ali.DSM_Incentive__c)
        };
    }

    private static void applyPayInToLineItem(Application_Line_Item__c ali, Map<String, Object> payIn) {
        if (payIn == null) {
            return;
        }
        if (payIn.containsKey('serviceCharges')) {
            ali.Service_charges__c = decimalVal(payIn.get('serviceCharges'));
        }
        if (payIn.containsKey('documentationCharges')) {
            ali.Documentation_charges__c = decimalVal(payIn.get('documentationCharges'));
        }
        if (payIn.containsKey('applicableStampingCharges')) {
            ali.Applicable_Stamping_Charges__c = stringVal(payIn.get('applicableStampingCharges'));
        }
        if (payIn.containsKey('cess')) {
            ali.Cess__c = stringVal(payIn.get('cess'));
        }
        if (payIn.containsKey('stampingChargesPaidBy')) {
            ali.Stamping_Charges_Paid_By__c = stringVal(payIn.get('stampingChargesPaidBy'));
        }
        if (payIn.containsKey('tradeCertificate')) {
            ali.Trade_certificate__c = stringVal(payIn.get('tradeCertificate'));
        }
    }

    private static void applyPayOutToLineItem(Application_Line_Item__c ali, Map<String, Object> payOut) {
        if (payOut == null) {
            return;
        }
        if (payOut.containsKey('mainDealerAmt')) {
            ali.Dealer_incentive_amount_main_dealer__c = stringVal(payOut.get('mainDealerAmt'));
        }
        if (payOut.containsKey('subDealerAmt')) {
            ali.Dealer_incentive_amount_sub_dealer__c = stringVal(payOut.get('subDealerAmt'));
        }
        if (payOut.containsKey('giftAmt')) {
            ali.Gift_through_dealer_amount__c = stringVal(payOut.get('giftAmt'));
        }
        if (payOut.containsKey('dsmName')) {
            ali.DSM_Name__c = stringVal(payOut.get('dsmName'));
        }
        if (payOut.containsKey('dsmIncentive')) {
            ali.DSM_Incentive__c = stringVal(payOut.get('dsmIncentive'));
        }
    }

    private static Application_Line_Item__c queryApplicationLineItem(Id lineItemId) {
        List<String> selectFields = new List<String>{
            'Id',
            'Service_charges__c',
            'Documentation_charges__c',
            'Applicable_Stamping_Charges__c',
            'Cess__c',
            'Stamping_Charges_Paid_By__c',
            'Trade_certificate__c',
            'Dealer_incentive_amount_main_dealer__c',
            'Dealer_incentive_amount_sub_dealer__c',
            'Gift_through_dealer_amount__c',
            'DSM_Name__c',
            'DSM_Incentive__c'
        };
        if (objectHasField(OBJECT_ALI, ALI_SCHEME_FIELD)) {
            selectFields.add(ALI_SCHEME_FIELD);
        }
        selectFields.add('Stage_Completed__c');
        String soql =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Application_Line_Item__c WHERE Id = :lineItemId WITH SYSTEM_MODE LIMIT 1';
        List<Application_Line_Item__c> rows = Database.query(soql);
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

    private static String getLineItemSchemeId(Application_Line_Item__c ali) {
        if (ali == null || !objectHasField(OBJECT_ALI, ALI_SCHEME_FIELD)) {
            return null;
        }
        Object value = ali.get(ALI_SCHEME_FIELD);
        return value != null ? String.valueOf(value) : null;
    }

    private static void setLineItemSchemeId(Application_Line_Item__c ali, String schemeId) {
        if (ali == null || !objectHasField(OBJECT_ALI, ALI_SCHEME_FIELD) || String.isBlank(schemeId)) {
            return;
        }
        ali.put(ALI_SCHEME_FIELD, (Id) schemeId);
    }

    private static Map<String, Schema.SObjectType> objectTypeCache;

    private static Schema.SObjectType getObjectType(String objectApiName) {
        if (objectTypeCache == null) {
            objectTypeCache = Schema.getGlobalDescribe();
        }
        return objectTypeCache.get(objectApiName);
    }

    private static Boolean objectHasField(String objectApiName, String fieldApiName) {
        Schema.SObjectType objectType = getObjectType(objectApiName);
        if (objectType == null) {
            return false;
        }
        return objectType.getDescribe().fields.getMap().containsKey(fieldApiName.toLowerCase());
    }

    private static Id resolveApplicationLineItemId(
        String applicationId,
        String applicantId,
        String applicationLineItemId
    ) {
        Id directId = parseId(applicationLineItemId);
        if (directId != null) {
            return directId;
        }

        if (String.isBlank(applicationId)) {
            return null;
        }
        Id appId = parseId(applicationId);
        if (appId == null) {
            return null;
        }

        if (String.isNotBlank(applicantId)) {
            Id fromApplicant = queryLineItemIdByApplicant(parseId(applicantId));
            if (fromApplicant != null) {
                return fromApplicant;
            }
        }

        return queryLineItemIdByApplication(appId);
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    private static Id resolveAssetIdForLineItem(Id lineItemId) {
        if (lineItemId == null) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT Id
            FROM Asset__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Id;
    }

    private static Id queryLineItemIdByApplicant(Id applicantId) {
        List<Asset__c> rows = [
            SELECT Application_Line_Items__c
            FROM Asset__c
            WHERE Applicant__c = :applicantId
            AND Application_Line_Items__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Application_Line_Items__c;
    }

    private static Id queryLineItemIdByApplication(Id applicationId) {
        List<Asset__c> assets = [
            SELECT Application_Line_Items__c, Applicant__r.Application__c
            FROM Asset__c
            WHERE (
                Applicant__r.Application__c = :applicationId
                OR Application_Line_Items__r.Application__c = :applicationId
            )
            AND Application_Line_Items__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        for (Asset__c asset : assets) {
            if (asset.Applicant__r.Application__c == applicationId) {
                return asset.Application_Line_Items__c;
            }
        }
        return assets.isEmpty() ? null : assets[0].Application_Line_Items__c;
    }

    private static Boolean hasAnyPayInData(Map<String, Object> payIn) {
        return isPopulated(payIn.get('serviceCharges'))
            || isPopulated(payIn.get('documentationCharges'))
            || isPopulated(payIn.get('applicableStampingCharges'))
            || isPopulated(payIn.get('cess'))
            || isPopulated(payIn.get('tradeCertificate'));
    }

    private static Boolean hasAnyPayOutData(Map<String, Object> payOut) {
        return isPopulated(payOut.get('mainDealerAmt'))
            || isPopulated(payOut.get('subDealerAmt'))
            || isPopulated(payOut.get('giftAmt'))
            || isPopulated(payOut.get('dsmName'))
            || isPopulated(payOut.get('dsmIncentive'));
    }

    private static Boolean isPopulated(Object value) {
        return String.isNotBlank(stringVal(value));
    }

    private static String defaultStampingPaidBy(String existing) {
        return String.isNotBlank(existing) ? existing : 'Bank';
    }

    private static List<Map<String, Object>> buildPayInFieldConfig(Map<String, Object> payIn) {
        return new List<Map<String, Object>>{
            numberField('serviceCharges', 'Service Charges', payIn, 1),
            numberField('documentationCharges', 'Documentation Charges', payIn, 2),
            numberField('applicableStampingCharges', 'Applicable Stamping Charges', payIn, 3),
            numberField('cess', 'Cess', payIn, 4),
            picklistField(
                'stampingChargesPaidBy',
                'Stamping Charges Paid By',
                payIn,
                5,
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'label' => 'Bank', 'value' => 'Bank' },
                    new Map<String, Object>{ 'label' => 'Customer', 'value' => 'Customer' }
                }
            ),
            numberField('tradeCertificate', 'Trade Certificate', payIn, 6)
        };
    }

    private static List<Map<String, Object>> buildPayOutFieldConfig(Map<String, Object> payOut) {
        return new List<Map<String, Object>>{
            numberField('mainDealerAmt', 'Dealer Incentive Amount (Main Dealer)', payOut, 1),
            numberField('subDealerAmt', 'Dealer Incentive Amount (Sub Dealer)', payOut, 2),
            numberField('giftAmt', 'Gift Through Dealer Amount', payOut, 3),
            textField('dsmName', 'DSM Name', payOut, 4),
            numberField('dsmIncentive', 'DSM Incentive', payOut, 5)
        };
    }

    private static Map<String, Object> numberField(
        String keyName,
        String label,
        Map<String, Object> values,
        Integer sequence
    ) {
        return new Map<String, Object>{
            'key' => keyName,
            'label' => label,
            'type' => 'number',
            'value' => values.get(keyName),
            'mode' => 'editable',
            'sequence' => sequence
        };
    }

    private static Map<String, Object> picklistField(
        String keyName,
        String label,
        Map<String, Object> values,
        Integer sequence,
        List<Map<String, Object>> options
    ) {
        return new Map<String, Object>{
            'key' => keyName,
            'label' => label,
            'type' => 'picklist',
            'value' => values.get(keyName),
            'mode' => 'editable',
            'sequence' => sequence,
            'options' => options
        };
    }

    private static Map<String, Object> textField(
        String keyName,
        String label,
        Map<String, Object> values,
        Integer sequence
    ) {
        return new Map<String, Object>{
            'key' => keyName,
            'label' => label,
            'type' => 'text',
            'value' => values.get(keyName),
            'mode' => 'editable',
            'sequence' => sequence
        };
    }

    private static String formatNumber(Object value) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value);
    }

    private static String stringVal(Object value) {
        if (value == null) {
            return null;
        }
        String s = String.valueOf(value).trim();
        return String.isBlank(s) ? null : s;
    }

    private static Decimal decimalVal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        String s = String.valueOf(value).trim();
        if (String.isBlank(s)) {
            return null;
        }
        return Decimal.valueOf(s);
    }

    private static Map<String, Object> failure(String message) {
        return failure(message, null);
    }

    private static Map<String, Object> failure(String message, Map<String, Object> debug) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => message
        };
        if (debug != null && !debug.isEmpty()) {
            result.put('debug', debug);
        }
        return result;
    }

    private static Map<String, Object> buildSaveDebug(
        String recordId,
        String applicantId,
        String schemeId,
        Map<String, Object> payIn,
        Map<String, Object> payOut,
        Id lineItemId
    ) {
        return new Map<String, Object>{
            'recordId' => recordId,
            'applicantId' => applicantId,
            'schemeId' => schemeId,
            'applicationLineItemId' => lineItemId != null ? String.valueOf(lineItemId) : null,
            'payIn' => payIn,
            'payOut' => payOut
        };
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
}