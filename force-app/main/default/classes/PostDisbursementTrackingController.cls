public with sharing class PostDisbursementTrackingController implements Callable {
    private static final String ACTION_GET_PAGE_DATA = 'getPageData';
    private static final String ACTION_SAVE_TRACKING_STATE = 'saveTrackingState';
    private static final String STAGE_LABEL = 'Post-Disbursement Tracking';
    private static final String STAGE_KEY = 'Post_Disbursement_Tracking';
    private static final Integer PDD_EXPECTED_DATE_OFFSET_DAYS = 30;

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> requestArgs = mergeAndNormalizeArgs(args);
        if (action == ACTION_GET_PAGE_DATA) {
            return buildContextResponse(requestArgs);
        }
        if (action == ACTION_SAVE_TRACKING_STATE) {
            return persistTrackingCompletion(requestArgs);
        }
        throw new AuraHandledException('Unknown action: ' + action);
    }

    private static Map<String, Object> buildContextResponse(Map<String, Object> args) {
        Id recordId = parseRecordId(args.get('recordId'));
        if (recordId == null) {
            return buildErrorResponse('Application record ID is required.');
        }

        ScopeContext scopeContext = resolveScopeContext(recordId, args);
        Boolean handoverClosed = isTrackingStageCompletedForScope(
            scopeContext.applicationLineItemId,
            scopeContext.assetId
        );
        Asset__c contextAsset = queryContextAsset(scopeContext.applicationLineItemId, scopeContext.assetId);

        return new Map<String, Object>{
            'isSuccess' => true,
            'applicationLineItemId' => scopeContext.applicationLineItemId,
            'assetId' => scopeContext.assetId,
            'pddDocuments' => buildPddDocuments(scopeContext.applicationLineItemId, scopeContext.assetId),
            'repaymentSetup' => buildRepaymentSetup(scopeContext.applicationLineItemId),
            'hypothecationDetails' => buildHypothecationDetails(contextAsset),
            'insuranceDetails' => buildInsuranceDetails(contextAsset),
            'hypothecationAlert' => buildHypothecationAlert(contextAsset),
            'handoverClosed' => handoverClosed
        };
    }

    private static Map<String, Object> persistTrackingCompletion(Map<String, Object> args) {
        Id recordId = parseRecordId(args.get('recordId'));
        if (recordId == null) {
            return buildErrorResponse('Application record ID is required.');
        }

        Boolean handoverClosed = args.get('handoverClosed') == true;
        if (!handoverClosed) {
            return buildErrorResponse('Handover must be closed before saving.');
        }

        ScopeContext scopeContext = resolveScopeContext(recordId, args);
        if (scopeContext.applicationLineItemId == null) {
            return buildErrorResponse('Application line item context is required.');
        }

        String lineItemStageValue = resolveSupportedStagePicklistValue(
            Application_Line_Item__c.Stage_Completed__c,
            buildTrackingStageCandidates()
        );
        String assetStageValue = resolveSupportedStagePicklistValue(
            Asset__c.Stage_Completed__c,
            buildTrackingStageCandidates()
        );
        if (String.isBlank(lineItemStageValue) && String.isBlank(assetStageValue)) {
            return buildErrorResponse('Stage value not available in picklist.');
        }

        markTrackingStageCompletedForScope(
            scopeContext.applicationLineItemId,
            scopeContext.assetId,
            lineItemStageValue,
            assetStageValue
        );
        return new Map<String, Object>{
            'isSuccess' => true,
            'applicationLineItemId' => scopeContext.applicationLineItemId,
            'assetId' => scopeContext.assetId,
            'handoverClosed' => true
        };
    }

    private static Boolean isTrackingStageCompletedForScope(Id lineItemId, Id assetId) {
        if (lineItemId == null) {
            return false;
        }
        List<String> stageCandidates = buildTrackingStageCandidates();
        List<Application_Line_Item__c> lineItems = [
            SELECT Id, Stage_Completed__c
            FROM Application_Line_Item__c
            WHERE Id = :lineItemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!lineItems.isEmpty() && containsAnyCompletedStage(lineItems[0].Stage_Completed__c, stageCandidates)) {
            return true;
        }
        List<Asset__c> assets = queryScopedAssets(lineItemId, assetId);
        if (assets.isEmpty()) {
            return false;
        }
        for (Asset__c asset : assets) {
            if (!containsAnyCompletedStage(asset.Stage_Completed__c, stageCandidates)) {
                return false;
            }
        }
        return true;
    }

    private static void markTrackingStageCompletedForScope(
        Id lineItemId,
        Id assetId,
        String lineItemStageValue,
        String assetStageValue
    ) {
        Integer totalAssets = countLineItemAssets(lineItemId);
        Boolean allAssetsMarked = true;
        if (totalAssets > 1 && String.isNotBlank(assetStageValue)) {
            allAssetsMarked = markAssetTrackingStageCompleted(lineItemId, assetId, assetStageValue);
        } else if (totalAssets > 1 && String.isBlank(assetStageValue)) {
            allAssetsMarked = false;
        }

        if (String.isNotBlank(lineItemStageValue) && (totalAssets == 0 || allAssetsMarked)) {
            List<Application_Line_Item__c> lineItems = [
                SELECT Id, Stage_Completed__c
                FROM Application_Line_Item__c
                WHERE Id = :lineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!lineItems.isEmpty()) {
                Application_Line_Item__c lineItem = lineItems[0];
                lineItem.Stage_Completed__c = appendStageIfMissing(
                    lineItem.Stage_Completed__c,
                    lineItemStageValue
                );
                update lineItem;
            }
        }
    }

    private static Boolean markAssetTrackingStageCompleted(Id lineItemId, Id assetId, String stageValue) {
        List<Asset__c> assets = queryScopedAssets(lineItemId, assetId);
        if (assets.isEmpty()) {
            return false;
        }
        List<Asset__c> updates = new List<Asset__c>();
        for (Asset__c asset : assets) {
            String updatedStages = appendStageIfMissing(asset.Stage_Completed__c, stageValue);
            if (updatedStages != asset.Stage_Completed__c) {
                updates.add(new Asset__c(Id = asset.Id, Stage_Completed__c = updatedStages));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
        return areAllAssetsComplete(lineItemId, stageValue);
    }

    private static Boolean areAllAssetsComplete(Id lineItemId, String stageValue) {
        List<Asset__c> assets = queryScopedAssets(lineItemId, null);
        if (assets.isEmpty()) {
            return false;
        }
        for (Asset__c asset : assets) {
            if (!containsCompletedStage(asset.Stage_Completed__c, stageValue)) {
                return false;
            }
        }
        return true;
    }

    private static List<Asset__c> queryScopedAssets(Id lineItemId, Id assetId) {
        if (lineItemId == null) {
            return new List<Asset__c>();
        }
        if (assetId != null) {
            return [
                SELECT Id, Stage_Completed__c
                FROM Asset__c
                WHERE Id = :assetId AND Application_Line_Items__c = :lineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }
        return [
            SELECT Id, Stage_Completed__c
            FROM Asset__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
        ];
    }

    private static Asset__c queryContextAsset(Id lineItemId, Id assetId) {
        if (lineItemId == null) {
            return null;
        }
        List<Asset__c> assets;
        if (assetId != null) {
            assets = [
                SELECT
                    Id,
                    Vehicle_Registration_number__c,
                    Lien_marked_to_bank__c,
                    Now_lien_in_the_name_of__c,
                    Marked_on__c,
                    RC_retention_applicable__c,
                    Insurance_type__c,
                    Insurance_declared_value__c,
                    Motor_Insurance_Premium__c,
                    Ins_Expiry_date__c
                FROM Asset__c
                WHERE Id = :assetId
                  AND Application_Line_Items__c = :lineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } else {
            assets = [
                SELECT
                    Id,
                    Vehicle_Registration_number__c,
                    Lien_marked_to_bank__c,
                    Now_lien_in_the_name_of__c,
                    Marked_on__c,
                    RC_retention_applicable__c,
                    Insurance_type__c,
                    Insurance_declared_value__c,
                    Motor_Insurance_Premium__c,
                    Ins_Expiry_date__c
                FROM Asset__c
                WHERE Application_Line_Items__c = :lineItemId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
        }
        return assets.isEmpty() ? null : assets[0];
    }

    private static Map<String, Object> buildHypothecationDetails(Asset__c asset) {
        Map<String, Object> details = new Map<String, Object>();
        if (asset == null) {
            return details;
        }
        Boolean lienMarked = asset.Lien_marked_to_bank__c == true;
        details.put('endorsementStatus', lienMarked ? 'Completed' : 'Pending');
        details.put('registrationNo', asset.Vehicle_Registration_number__c);
        details.put('hypothecatee', asset.Now_lien_in_the_name_of__c);
        details.put('markedOn', asset.Marked_on__c);
        details.put('rcRetentionApplicable', asset.RC_retention_applicable__c);
        return details;
    }

    private static Map<String, Object> buildInsuranceDetails(Asset__c asset) {
        Map<String, Object> details = new Map<String, Object>();
        if (asset == null) {
            return details;
        }
        details.put('policyType', asset.Insurance_type__c);
        details.put('sumInsuredIdv', asset.Insurance_declared_value__c);
        details.put('motorInsurancePremium', asset.Motor_Insurance_Premium__c);
        details.put(
            'bankInterest',
            asset.Lien_marked_to_bank__c == true
                ? 'Hypothecatee / Loss Payee'
                : 'Not Marked'
        );
        details.put('validTill', asset.Ins_Expiry_date__c);
        return details;
    }

    private static String buildHypothecationAlert(Asset__c asset) {
        if (asset == null || asset.Lien_marked_to_bank__c == true) {
            return null;
        }
        return 'RC with HP endorsement awaited from RTO — tracked under PDD.';
    }

    private static Map<String, Object> buildRepaymentSetup(Id lineItemId) {
        Map<String, Object> setup = new Map<String, Object>();
        if (lineItemId == null) {
            return setup;
        }

        List<Application_Line_Item__c> lineItems = [
            SELECT Id, First_EMI_Date__c, Tenure__c, EMI_Amount__c
            FROM Application_Line_Item__c
            WHERE Id = :lineItemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        Application_Line_Item__c lineItem = lineItems.isEmpty() ? null : lineItems[0];

        List<Repayment_Mandate__c> mandates = [
            SELECT
                Id,
                Repayment_Method__c,
                EMI_Amount__c,
                lst_EMI_Due_Date__c,
                E_Nach_Session__c,
                Account_Number__c,
                Bank_Master__r.Name,
                E_NACH_API_Status__c
            FROM Repayment_Mandate__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Repayment_Mandate__c mandate = mandates.isEmpty() ? null : mandates[0];

        Decimal emiAmount = mandate != null && mandate.EMI_Amount__c != null
            ? mandate.EMI_Amount__c
            : (lineItem != null ? lineItem.EMI_Amount__c : null);
        Date firstEmiDate = mandate != null && mandate.lst_EMI_Due_Date__c != null
            ? mandate.lst_EMI_Due_Date__c
            : (lineItem != null ? lineItem.First_EMI_Date__c : null);
        String tenureMonths = lineItem != null && lineItem.Tenure__c != null
            ? String.valueOf(lineItem.Tenure__c)
            : null;

        String bankName = mandate != null && mandate.Bank_Master__r != null
            ? mandate.Bank_Master__r.Name
            : null;
        String debitAccount = mandate != null ? String.valueOf(mandate.Account_Number__c ?? '').trim() : '';
        if (String.isNotBlank(debitAccount) && String.isNotBlank(bankName)) {
            debitAccount = debitAccount + ' (' + bankName + ')';
        }

        String repaymentMode = mandate != null
            ? String.valueOf(mandate.Repayment_Method__c ?? '').trim()
            : '';
        String mandateStatus = String.valueOf(mandate?.E_NACH_API_Status__c ?? '').trim();
        if (String.isBlank(mandateStatus) && String.isNotBlank(repaymentMode)) {
            mandateStatus = repaymentMode + ' Active';
        }

        setup.put('mandate', String.isNotBlank(mandateStatus) ? mandateStatus : null);
        setup.put('emiAmount', emiAmount);
        setup.put('firstEmiDate', firstEmiDate);
        setup.put(
            'tenure',
            String.isNotBlank(tenureMonths) ? tenureMonths + ' months' : null
        );
        setup.put('mandateReference', mandate != null ? String.valueOf(mandate.Id) : null);
        setup.put('debitAccount', String.isNotBlank(debitAccount) ? debitAccount : null);
        setup.put('repaymentMode', String.isNotBlank(repaymentMode) ? repaymentMode : null);
        setup.put('bounceChargeRule', 500);
        return setup;
    }

    private static List<Map<String, Object>> buildPddDocuments(Id lineItemId, Id assetId) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        if (lineItemId == null) {
            return rows;
        }

        Date expectedDate = resolvePddExpectedDate(lineItemId, assetId);
        Set<String> uploadedDocumentTypes = queryUploadedDocumentTypeKeys(lineItemId, assetId);
        for (Map<String, Object> template : buildPddDocumentTemplates()) {
            String templateType = String.valueOf(template.get('documentName'));
            List<String> aliases = (List<String>) template.get('aliases');
            Boolean uploaded = matchesUploadedDocument(uploadedDocumentTypes, aliases);
            Integer ageingDays = 0;
            if (!uploaded && expectedDate != null && Date.today().daysBetween(expectedDate) < 0) {
                ageingDays = expectedDate.daysBetween(Date.today());
            }

            rows.add(
                new Map<String, Object>{
                    'id' => template.get('id'),
                    'documentName' => templateType,
                    'owner' => template.get('owner'),
                    'expectedDate' => expectedDate,
                    'ageingDays' => ageingDays,
                    'status' => uploaded ? 'Received' : 'Pending',
                    'canMarkReceived' => !uploaded
                }
            );
        }
        return rows;
    }

    private static Date resolvePddExpectedDate(Id lineItemId, Id assetId) {
        if (lineItemId == null) {
            return null;
        }
        List<Disbursement_Details__c> disbursementDetails;
        if (assetId != null) {
            disbursementDetails = [
                SELECT Payment_Requested_Date__c
                FROM Disbursement_Details__c
                WHERE Application_Line_Items__c = :lineItemId
                  AND Asset__c = :assetId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!disbursementDetails.isEmpty() && disbursementDetails[0].Payment_Requested_Date__c != null) {
                return disbursementDetails[0].Payment_Requested_Date__c.addDays(PDD_EXPECTED_DATE_OFFSET_DAYS);
            }
        }

        disbursementDetails = [
            SELECT Payment_Requested_Date__c
            FROM Disbursement_Details__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (disbursementDetails.isEmpty() || disbursementDetails[0].Payment_Requested_Date__c == null) {
            return null;
        }
        return disbursementDetails[0].Payment_Requested_Date__c.addDays(PDD_EXPECTED_DATE_OFFSET_DAYS);
    }

    private static Set<String> queryUploadedDocumentTypeKeys(Id lineItemId, Id assetId) {
        Set<String> uploadedKeys = new Set<String>();
        if (lineItemId == null) {
            return uploadedKeys;
        }
        List<Document_CheckList__c> documentRows;
        if (assetId != null) {
            documentRows = [
                SELECT Id, Document_Type__c, ContentVersionId__c
                FROM Document_CheckList__c
                WHERE Application_Line_Items__c = :lineItemId
                  AND Asset__c = :assetId
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
            ];
        } else {
            documentRows = [
                SELECT Id, Document_Type__c, ContentVersionId__c
                FROM Document_CheckList__c
                WHERE Application_Line_Items__c = :lineItemId
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
            ];
        }

        Set<Id> checklistIdsNeedingLinkCheck = new Set<Id>();
        for (Document_CheckList__c row : documentRows) {
            if (String.isBlank(row.ContentVersionId__c)) {
                checklistIdsNeedingLinkCheck.add(row.Id);
            }
        }

        Set<Id> checklistIdsWithFiles = new Set<Id>();
        if (!checklistIdsNeedingLinkCheck.isEmpty()) {
            for (ContentDocumentLink link : [
                SELECT LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :checklistIdsNeedingLinkCheck
            ]) {
                checklistIdsWithFiles.add(link.LinkedEntityId);
            }
        }

        for (Document_CheckList__c row : documentRows) {
            Boolean hasUploadedFile = String.isNotBlank(row.ContentVersionId__c)
                || checklistIdsWithFiles.contains(row.Id);
            if (!hasUploadedFile) {
                continue;
            }
            String normalizedType = normalizeDocumentType(row.Document_Type__c);
            if (String.isNotBlank(normalizedType)) {
                uploadedKeys.add(normalizedType);
            }
        }
        return uploadedKeys;
    }

    private static Boolean matchesUploadedDocument(Set<String> uploadedKeys, List<String> aliases) {
        if (uploadedKeys == null || uploadedKeys.isEmpty() || aliases == null || aliases.isEmpty()) {
            return false;
        }
        for (String alias : aliases) {
            if (uploadedKeys.contains(normalizeDocumentType(alias))) {
                return true;
            }
        }
        return false;
    }

    private static String normalizeDocumentType(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static List<Map<String, Object>> buildPddDocumentTemplates() {
        return new List<Map<String, Object>>{
            new Map<String, Object>{
                'id' => 'rc',
                'documentName' => 'RC copy',
                'owner' => 'Sales Officer',
                'aliases' => new List<String>{ 'RC copy', 'RC', 'Registration Certificate' }
            },
            new Map<String, Object>{
                'id' => 'invoice',
                'documentName' => 'Tax invoice',
                'owner' => 'Dealer',
                'aliases' => new List<String>{ 'Tax invoice', 'Invoice' }
            },
            new Map<String, Object>{
                'id' => 'insurance',
                'documentName' => 'Insurance policy',
                'owner' => 'Operations',
                'aliases' => new List<String>{ 'Insurance policy', 'Insurance' }
            },
            new Map<String, Object>{
                'id' => 'form34',
                'documentName' => 'Form 34 (HP endorsement)',
                'owner' => 'Operations',
                'aliases' => new List<String>{ 'Form 34', 'Form 34 (HP endorsement)', 'HP endorsement' }
            },
            new Map<String, Object>{
                'id' => 'delivery',
                'documentName' => 'Delivery challan',
                'owner' => 'Sales Officer',
                'aliases' => new List<String>{ 'Delivery challan', 'Delivery' }
            }
        };
    }

    private static Integer countLineItemAssets(Id lineItemId) {
        return lineItemId == null
            ? 0
            : [SELECT COUNT() FROM Asset__c WHERE Application_Line_Items__c = :lineItemId WITH SECURITY_ENFORCED];
    }

    private static ScopeContext resolveScopeContext(Id recordId, Map<String, Object> args) {
        ScopeContext scope = new ScopeContext();
        scope.applicationLineItemId = parseRecordId(args.get('applicationLineItemId'));
        scope.assetId = parseRecordId(args.get('assetId'));
        if (scope.applicationLineItemId == null && scope.assetId != null) {
            scope.applicationLineItemId = resolveLineItemIdByAsset(recordId, scope.assetId);
        }
        return scope;
    }

    private static Id resolveLineItemIdByAsset(Id recordId, Id assetId) {
        if (recordId == null || assetId == null) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT Application_Line_Items__c
            FROM Asset__c
            WHERE Id = :assetId
              AND (Applicant__r.Application__c = :recordId OR Application_Line_Items__r.Application__c = :recordId)
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Application_Line_Items__c;
    }

    private static String resolveSupportedStagePicklistValue(
        Schema.SObjectField fieldRef,
        List<String> candidates
    ) {
        if (fieldRef == null || candidates == null || candidates.isEmpty()) {
            return null;
        }
        for (Schema.PicklistEntry entry : fieldRef.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            for (String candidate : candidates) {
                if (candidate != null && (candidate.equalsIgnoreCase(entry.getValue()) || candidate.equalsIgnoreCase(entry.getLabel()))) {
                    return entry.getValue();
                }
            }
        }
        return null;
    }

    private static List<String> buildTrackingStageCandidates() {
        return new List<String>{ STAGE_KEY, STAGE_LABEL };
    }

    private static Map<String, Object> mergeAndNormalizeArgs(Map<String, Object> args) {
        Map<String, Object> normalizedArgs = args == null ? new Map<String, Object>() : new Map<String, Object>(args);
        if (normalizedArgs.containsKey('params') && normalizedArgs.get('params') instanceof Map<String, Object>) {
            normalizedArgs.putAll((Map<String, Object>) normalizedArgs.get('params'));
        }
        return normalizedArgs;
    }

    private static String appendStageIfMissing(String currentStages, String stageName) {
        if (String.isBlank(stageName) || containsCompletedStage(currentStages, stageName)) {
            return currentStages;
        }
        String stage = stageName.trim();
        return String.isBlank(currentStages) ? stage : currentStages + ';' + stage;
    }

    private static Boolean containsAnyCompletedStage(String completedStages, List<String> stageCandidates) {
        for (String candidate : stageCandidates) {
            if (containsCompletedStage(completedStages, candidate)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean containsCompletedStage(String completedStages, String stageName) {
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

    private static Id parseRecordId(Object recordIdValue) {
        if (recordIdValue == null) {
            return null;
        }
        try {
            return (Id) String.valueOf(recordIdValue);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Map<String, Object> buildErrorResponse(String message) {
        return new Map<String, Object>{ 'isSuccess' => false, 'loadError' => message };
    }

    private class ScopeContext {
        Id applicationLineItemId;
        Id assetId;
    }
}