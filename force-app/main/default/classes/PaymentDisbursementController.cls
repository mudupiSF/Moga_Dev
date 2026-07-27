/**
 * @description Controller for paymentDisbursementScreen LWC.
 * Loads Loan_Beneficiary__c rows and beneficiary-payment aggregates.
 */
public with sharing class PaymentDisbursementController implements Callable {

    private static final String ACTION_GET_PAGE_DATA = 'getPageData';
    private static final String ACTION_SAVE_DISBURSEMENT = 'saveDisbursement';
    private static final String PAYMENT_DISBURSEMENT_STAGE_LABEL = 'Payment Disbursement';
    private static final String PAYMENT_DISBURSEMENT_STAGE_KEY = 'Payment_Disbursement';

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> requestArgs = args != null ? args : new Map<String, Object>();
        if (action == ACTION_GET_PAGE_DATA) {
            return loadPageData(requestArgs);
        }
        if (action == ACTION_SAVE_DISBURSEMENT) {
            return saveDisbursementData(requestArgs);
        }
        throw new AuraHandledException('Unknown action: ' + action);
    }

    private static Map<String, Object> loadPageData(Map<String, Object> args) {
        Map<String, Object> normalizedArgs = mergeRequestArgs(args);
        Id recordId = parseId(normalizedArgs.get('recordId'));
        Map<String, Object> result = buildEmptyPageResult();
        if (recordId == null) {
            return result;
        }

        try {
            ScopeContext scope = resolveScopeContext(recordId, normalizedArgs);
            DisbursementPageContext context = buildPageContextForApplication(
                recordId,
                scope.applicationLineItemId,
                scope.assetId
            );
            List<Loan_Beneficiary__c> beneficiariesList = queryBeneficiariesForApplication(
                recordId,
                context.disbursementDetails != null ? context.disbursementDetails.Id : null
            );
            Set<Id> beneficiaryIds = new Set<Id>();
            for (Loan_Beneficiary__c beneficiary : beneficiariesList) {
                beneficiaryIds.add(beneficiary.Id);
            }
            Map<Id, Decimal> paidByBeneficiaryId = queryPaidAmountsByBeneficiaryId(beneficiaryIds);

            result.put('isSuccess', true);
            result.put('summaryCounts', buildSummaryCardCounts(beneficiariesList, paidByBeneficiaryId));
            result.put(
                'beneficiaryRows',
                buildBeneficiaryRowsForDisplay(context, beneficiariesList, paidByBeneficiaryId)
            );
            result.put('paymentOriginatedFrom', context.paymentOriginatedFrom);
            result.put(
                'taAdjustedByReference',
                queryTaAdjustedAmountsByReference(beneficiaryIds)
            );
        } catch (Exception e) {
            result.put('loadError', e.getMessage());
        }

        return result;
    }

    private static Map<String, Object> saveDisbursementData(Map<String, Object> args) {
        Map<String, Object> normalizedArgs = mergeRequestArgs(args);
        Id recordId = parseId(normalizedArgs.get('recordId'));
        String currentViewId = String.valueOf(normalizedArgs.get('currentViewId') ?? '').trim();
        if (recordId == null) {
            return buildErrorResult('Application record ID is required.');
        }

        ScopeContext scope = resolveScopeContext(recordId, normalizedArgs);
        DisbursementPageContext context = buildPageContextForApplication(
            recordId,
            scope.applicationLineItemId,
            scope.assetId
        );

        Map<String, Object> paymentParseResult = parsePaymentRows(normalizedArgs.get('payments'));
        if (!(Boolean) paymentParseResult.get('isValid')) {
            return buildErrorResult((String) paymentParseResult.get('errorMessage'));
        }
        Map<Id, PaymentEntry> paymentByBeneficiaryId = (Map<Id, PaymentEntry>) paymentParseResult.get(
            'payments'
        );

        List<Loan_Beneficiary__c> beneficiaries = [
            SELECT Id, Amount__c, Application__c, Type__c, Disbursement_Details__c
            FROM Loan_Beneficiary__c
            WHERE Id IN :paymentByBeneficiaryId.keySet()
            WITH SECURITY_ENFORCED
        ];
        Map<Id, Decimal> paidByBeneficiaryId = queryPaidAmountsByBeneficiaryId(paymentByBeneficiaryId.keySet());

        List<Beneficiary_Payment__c> paymentsToInsert = new List<Beneficiary_Payment__c>();
        for (Loan_Beneficiary__c beneficiary : beneficiaries) {
            if (beneficiary.Application__c != recordId) {
            return buildErrorResult('Selected beneficiary does not belong to this application.');
            }
            if (
                context.disbursementDetails != null &&
                beneficiary.Disbursement_Details__c != context.disbursementDetails.Id
            ) {
                return buildErrorResult('Selected beneficiary does not belong to the current line item scope.');
            }

            Decimal disbursementAmount = toDecimalSafe(beneficiary.Amount__c);
            Decimal paidEarlier = paidByBeneficiaryId.containsKey(beneficiary.Id)
                ? paidByBeneficiaryId.get(beneficiary.Id)
                : 0;
            PaymentEntry paymentEntry = paymentByBeneficiaryId.get(beneficiary.Id);
            Decimal toBePaidNow = paymentEntry.toBePaidNow;
            Decimal adjustedAmount = paymentEntry.adjustedAmount;
            Decimal amountPaid = Math.max(0, toBePaidNow - adjustedAmount);
            String taReferenceNumber = paymentEntry.taReferenceNumber;
            Decimal remainingAmount = disbursementAmount - paidEarlier;
            Decimal remainingDisbursementAmount = disbursementAmount - paidEarlier - toBePaidNow;
            DateTime paymentDate = DateTime.now();

            if (disbursementAmount <= 0) {
                return buildErrorResult('Disbursement amount is not set for the selected beneficiary.');
            }
            if (paidEarlier >= disbursementAmount) {
                return buildErrorResult('Selected beneficiary is already fully disbursed.');
            }
            if (toBePaidNow > remainingAmount) {
                return buildErrorResult(
                    'Payment amount cannot exceed the remaining balance of ' + remainingAmount + '.'
                );
            }
            if (adjustedAmount < 0 || adjustedAmount > toBePaidNow) {
                return buildErrorResult('Adjusted amount cannot exceed the tranche disbursement amount.');
            }
            String normalizedBeneficiaryType = String.valueOf(beneficiary.Type__c ?? '').trim().toLowerCase();
            if (adjustedAmount > 0 && !normalizedBeneficiaryType.contains('dealer')) {
                return buildErrorResult('TA adjustment is applicable only for dealer beneficiary.');
            }
            if (remainingDisbursementAmount < 0) {
                return buildErrorResult('Remaining disbursement amount cannot be negative.');
            }

            paymentsToInsert.add(
                new Beneficiary_Payment__c(
                    Loan_Beneficiary__c = beneficiary.Id,
                    Tranche_Disbursement_Amount__c = toBePaidNow,
                    Amount_Paid__c = amountPaid,
                    Adjusted_Amount__c = adjustedAmount,
                    TA_Reference_Number__c = taReferenceNumber,
                    Remaining_Disbursement_Amount__c = remainingDisbursementAmount,
                    Payment_Date__c = paymentDate
                )
            );
        }

        insert paymentsToInsert;

        List<Loan_Beneficiary__c> beneficiariesList = queryBeneficiariesForApplication(
            recordId,
            context.disbursementDetails != null ? context.disbursementDetails.Id : null
        );
        Set<Id> allBeneficiaryIds = new Set<Id>();
        for (Loan_Beneficiary__c beneficiary : beneficiariesList) {
            allBeneficiaryIds.add(beneficiary.Id);
        }
        Map<Id, Decimal> latestPaidByBeneficiaryId = queryPaidAmountsByBeneficiaryId(allBeneficiaryIds);
        if (isScopeFullyDisbursed(beneficiariesList, latestPaidByBeneficiaryId)) {
            markPaymentDisbursementStageCompleteForScope(
                context.lineItemId,
                scope.assetId,
                currentViewId
            );
        }
        return new Map<String, Object>{
            'isSuccess' => true,
            'summaryCounts' => buildSummaryCardCounts(beneficiariesList, latestPaidByBeneficiaryId),
            'beneficiaryRows' => buildBeneficiaryRowsForDisplay(context, beneficiariesList, latestPaidByBeneficiaryId),
            'taAdjustedByReference' => queryTaAdjustedAmountsByReference(allBeneficiaryIds)
        };
    }

    private static Map<String, Object> parsePaymentRows(Object rawPayments) {
        if (!(rawPayments instanceof List<Object>)) {
            return new Map<String, Object>{
                'isValid' => false,
                'errorMessage' => 'Select at least one beneficiary row to submit.'
            };
        }

        Map<Id, PaymentEntry> paymentByBeneficiaryId = new Map<Id, PaymentEntry>();
        for (Object rawPayment : (List<Object>) rawPayments) {
            Map<String, Object> payment;
            if (rawPayment instanceof Map<String, Object>) {
                payment = (Map<String, Object>) rawPayment;
            } else if (rawPayment != null) {
                try {
                    Object reparsed = JSON.deserializeUntyped(JSON.serialize(rawPayment));
                    payment = reparsed instanceof Map<String, Object> ? (Map<String, Object>) reparsed : null;
                } catch (Exception ex) {
                    payment = null;
                }
            }
            if (payment == null) {
                continue;
            }

            Id beneficiaryId = parseId(payment.get('id'));
            if (beneficiaryId == null) {
                return new Map<String, Object>{
                    'isValid' => false,
                    'errorMessage' => 'Invalid beneficiary row selected.'
                };
            }

            Decimal toBePaidNow = toDecimalSafe(payment.get('toBePaidNow'));
            if (toBePaidNow <= 0) {
                return new Map<String, Object>{
                    'isValid' => false,
                    'errorMessage' => 'Enter a payment amount greater than zero.'
                };
            }
            Decimal adjustedAmount = parseAdjustedAmount(payment);
            String taReferenceNumber = String.valueOf(payment.get('taReferenceNumber') ?? '').trim();
            if (adjustedAmount > 0 && String.isBlank(taReferenceNumber)) {
                return new Map<String, Object>{
                    'isValid' => false,
                    'errorMessage' => 'TA reference number is required when adjustment amount is entered.'
                };
            }
            if (String.isNotBlank(taReferenceNumber) && adjustedAmount <= 0) {
                return new Map<String, Object>{
                    'isValid' => false,
                    'errorMessage' => 'Enter an adjustment amount greater than zero and not exceeding the pending balance.'
                };
            }
            paymentByBeneficiaryId.put(
                beneficiaryId,
                new PaymentEntry(
                    toBePaidNow,
                    adjustedAmount,
                    taReferenceNumber
                )
            );
        }

        if (paymentByBeneficiaryId.isEmpty()) {
            return new Map<String, Object>{
                'isValid' => false,
                'errorMessage' => 'Select at least one beneficiary row to submit.'
            };
        }

        return new Map<String, Object>{
            'isValid' => true,
            'payments' => paymentByBeneficiaryId
        };
    }

    private static DisbursementPageContext buildPageContextForApplication(
        Id recordId,
        Id applicationLineItemId,
        Id assetId
    ) {
        DisbursementPageContext context = new DisbursementPageContext();
        if (recordId == null) {
            return context;
        }

        Id resolvedLineItemId = applicationLineItemId;
        if (resolvedLineItemId == null && assetId != null) {
            resolvedLineItemId = resolveLineItemIdByAsset(recordId, assetId);
        }

        Application_Line_Item__c lineItem = resolvedLineItemId != null
            ? queryScopedLineItem(recordId, resolvedLineItemId)
            : null;
        if (lineItem == null) {
            lineItem = queryFirstApplicationLineItem(recordId);
        }
        applyLineItemToContext(context, lineItem);
        if (context.lineItemId != null) {
            Disbursement_Details__c scopedDisbursementDetails = queryScopedDisbursementDetails(
                context.lineItemId,
                assetId
            );
            if (scopedDisbursementDetails != null) {
                context.disbursementDetails = scopedDisbursementDetails;
                context.paymentOriginatedFrom = scopedDisbursementDetails.Payment_Originated_From__c;
                context.dealDate = scopedDisbursementDetails.Payment_to_be_made_on__c != null
                    ? scopedDisbursementDetails.Payment_to_be_made_on__c
                    : Date.today();
            }
        }

        return context;
    }

    private static Disbursement_Details__c queryScopedDisbursementDetails(Id lineItemId, Id assetId) {
        if (lineItemId == null) {
            return null;
        }
        if (assetId != null) {
            List<Disbursement_Details__c> scopedDetails = [
                SELECT Id, Payment_to_be_made_on__c, Payment_Originated_From__c
                FROM Disbursement_Details__c
                WHERE Application_Line_Items__c = :lineItemId
                    AND Asset__c = :assetId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!scopedDetails.isEmpty()) {
                return scopedDetails[0];
            }
        }
        List<Disbursement_Details__c> lineItemDetails = [
            SELECT Id, Payment_to_be_made_on__c, Payment_Originated_From__c
            FROM Disbursement_Details__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return lineItemDetails.isEmpty() ? null : lineItemDetails[0];
    }

    private static Application_Line_Item__c queryScopedLineItem(Id recordId, Id lineItemId) {
        List<Application_Line_Item__c> lineItems = [
            SELECT
                Id,
                First_EMI_Date__c,
                Second_EMI_Date__c,
                (
                    SELECT
                        Id,
                        Payment_to_be_made_on__c,
                        Payment_Originated_From__c
                    FROM Disbursement_Details__r
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                )
            FROM Application_Line_Item__c
            WHERE Id = :lineItemId AND Application__c = :recordId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return lineItems.isEmpty() ? null : lineItems[0];
    }

    private static Application_Line_Item__c queryFirstApplicationLineItem(Id recordId) {
        List<Application_Line_Item__c> lineItems = [
            SELECT
                Id,
                First_EMI_Date__c,
                Second_EMI_Date__c,
                (
                    SELECT
                        Id,
                        Payment_to_be_made_on__c,
                        Payment_Originated_From__c
                    FROM Disbursement_Details__r
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                )
            FROM Application_Line_Item__c
            WHERE Application__c = :recordId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return lineItems.isEmpty() ? null : lineItems[0];
    }

    private static void applyLineItemToContext(
        DisbursementPageContext context,
        Application_Line_Item__c lineItem
    ) {
        if (context == null || lineItem == null) {
            return;
        }
        context.lineItemId = lineItem.Id;
        context.firstEmiDate = lineItem.First_EMI_Date__c;
        context.secondEmiDate = lineItem.Second_EMI_Date__c;
        if (
            lineItem.Disbursement_Details__r != null &&
            !lineItem.Disbursement_Details__r.isEmpty()
        ) {
            context.disbursementDetails = lineItem.Disbursement_Details__r[0];
            context.paymentOriginatedFrom = context.disbursementDetails.Payment_Originated_From__c;
            context.dealDate = context.disbursementDetails.Payment_to_be_made_on__c != null
                ? context.disbursementDetails.Payment_to_be_made_on__c
                : Date.today();
        }
    }

    private static Id resolveLineItemIdByAsset(Id recordId, Id assetId) {
        if (recordId == null || assetId == null) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT Id, Application_Line_Items__c
            FROM Asset__c
            WHERE Id = :assetId
              AND (
                  Applicant__r.Application__c = :recordId
                  OR Application_Line_Items__r.Application__c = :recordId
              )
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Application_Line_Items__c;
    }

    private static ScopeContext resolveScopeContext(Id recordId, Map<String, Object> args) {
        ScopeContext scope = new ScopeContext();
        scope.applicationLineItemId = parseId(args.get('applicationLineItemId'));
        scope.assetId = parseId(args.get('assetId'));
        if (scope.applicationLineItemId == null && scope.assetId != null) {
            scope.applicationLineItemId = resolveLineItemIdByAsset(recordId, scope.assetId);
        }
        return scope;
    }

    private static Map<String, Object> mergeRequestArgs(Map<String, Object> args) {
        if (args == null) {
            return new Map<String, Object>();
        }
        if (args.containsKey('params') && args.get('params') instanceof Map<String, Object>) {
            Map<String, Object> merged = new Map<String, Object>(args);
            merged.putAll((Map<String, Object>) args.get('params'));
            return merged;
        }
        return args;
    }

    private static Map<String, Object> buildSummaryCardCounts(
        List<Loan_Beneficiary__c> beneficiaries,
        Map<Id, Decimal> paidByBeneficiaryId
    ) {
        Integer pendingCount = 0;
        Integer completedCount = 0;

        for (Loan_Beneficiary__c beneficiary : beneficiaries) {
            Decimal paidAmount = paidByBeneficiaryId.containsKey(beneficiary.Id)
                ? paidByBeneficiaryId.get(beneficiary.Id)
                : 0;
            if (isBeneficiaryFullyPaid(beneficiary, paidAmount)) {
                completedCount++;
            } else {
                pendingCount++;
            }
        }

        return new Map<String, Object>{
            'pendingCount' => pendingCount,
            'completedCount' => completedCount
        };
    }

    private static List<Loan_Beneficiary__c> queryBeneficiariesForApplication(
        Id applicationId,
        Id disbursementDetailsId
    ) {
        if (applicationId == null) {
            return new List<Loan_Beneficiary__c>();
        }
        if (disbursementDetailsId != null) {
            return [
                SELECT
                    Id,
                    Beneficiary_Name__c,
                    Account_Number__c,
                    IFSC_Code__c,
                    Amount__c,
                    Type__c,
                    Disbursement_Details__c,
                    CreatedDate
                FROM Loan_Beneficiary__c
                WHERE Application__c = :applicationId
                    AND Disbursement_Details__c = :disbursementDetailsId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
            ];
        }
        return [
            SELECT
                Id,
                Beneficiary_Name__c,
                Account_Number__c,
                IFSC_Code__c,
                Amount__c,
                Type__c,
                Disbursement_Details__c,
                CreatedDate
            FROM Loan_Beneficiary__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    private static List<Map<String, Object>> buildBeneficiaryRowsForDisplay(
        DisbursementPageContext context,
        List<Loan_Beneficiary__c> beneficiariesList,
        Map<Id, Decimal> paidByBeneficiaryId
    ) {
        List<Loan_Beneficiary__c> workspaceBeneficiaries = beneficiariesList;
        if (context.disbursementDetails != null) {
            List<Loan_Beneficiary__c> linkedBeneficiaries = new List<Loan_Beneficiary__c>();
            for (Loan_Beneficiary__c beneficiary : beneficiariesList) {
                if (beneficiary.Disbursement_Details__c == context.disbursementDetails.Id) {
                    linkedBeneficiaries.add(beneficiary);
                }
            }
            if (!linkedBeneficiaries.isEmpty()) {
                workspaceBeneficiaries = linkedBeneficiaries;
            }
        }

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Loan_Beneficiary__c beneficiary : workspaceBeneficiaries) {
            Decimal disbursementAmount = toDecimalSafe(beneficiary.Amount__c);
            Decimal paidAmount = paidByBeneficiaryId.containsKey(beneficiary.Id)
                ? paidByBeneficiaryId.get(beneficiary.Id)
                : 0;
            Boolean disbursed = isBeneficiaryFullyPaid(beneficiary, paidAmount);
            Decimal remainingAmount = Math.max(0, disbursementAmount - paidAmount);
            String normalizedType = String.valueOf(beneficiary.Type__c ?? '').trim().toLowerCase();
            String beneficiaryType;
            if (normalizedType.contains('financier')) {
                beneficiaryType = 'financier';
            } else if (normalizedType.contains('customer')) {
                beneficiaryType = 'customer';
            } else if (normalizedType.contains('dealer') || normalizedType.contains('seller')) {
                beneficiaryType = 'dealer';
            } else {
                beneficiaryType = String.isNotBlank(beneficiary.Type__c)
                    ? beneficiary.Type__c.toLowerCase()
                    : 'dealer';
            }
            String beneficiaryTypeLabel = beneficiaryType == 'financier'
                ? 'FINANCIER'
                : beneficiaryType == 'customer'
                    ? 'CUSTOMER'
                    : 'DEALER / SELLER';

            rows.add(
                new Map<String, Object>{
                    'id' => beneficiary.Id,
                    'beneficiaryType' => beneficiaryType,
                    'beneficiaryTypeLabel' => beneficiaryTypeLabel,
                    'beneficiaryName' => beneficiary.Beneficiary_Name__c,
                    'beneficiarySubLabel' => beneficiaryType == 'financier'
                        ? '(existing loan payoff)'
                        : '',
                    'dealDate' => context.dealDate != null ? context.dealDate.format() : null,
                    'firstEmiDate' => context.firstEmiDate != null ? context.firstEmiDate.format() : null,
                    'secondEmiDate' => context.secondEmiDate != null
                        ? context.secondEmiDate.format()
                        : null,
                    'disbursementAmount' => disbursementAmount,
                    'paidEarlier' => paidAmount,
                    'toBePaidNow' => disbursed ? 0 : remainingAmount,
                    'accountNumber' => beneficiary.Account_Number__c,
                    'ifscCode' => beneficiary.IFSC_Code__c,
                    'bankName' => '',
                    'disbursed' => disbursed
                }
            );
        }
        return rows;
    }

    private static Boolean isScopeFullyDisbursed(
        List<Loan_Beneficiary__c> beneficiaries,
        Map<Id, Decimal> paidByBeneficiaryId
    ) {
        if (beneficiaries == null || beneficiaries.isEmpty()) {
            return false;
        }
        for (Loan_Beneficiary__c beneficiary : beneficiaries) {
            Decimal paidAmount = paidByBeneficiaryId.containsKey(beneficiary.Id)
                ? paidByBeneficiaryId.get(beneficiary.Id)
                : 0;
            if (!isBeneficiaryFullyPaid(beneficiary, paidAmount)) {
                return false;
            }
        }
        return true;
    }

    private static void markPaymentDisbursementStageCompleteForScope(
        Id lineItemId,
        Id assetId,
        String currentViewId
    ) {
        if (lineItemId == null) {
            return;
        }

        String lineItemStageKey = resolveSupportedStagePicklistValue(
            Application_Line_Item__c.Stage_Completed__c,
            buildPaymentDisbursementStageCandidates(currentViewId)
        );
        String assetStageKey = resolveSupportedStagePicklistValue(
            Asset__c.Stage_Completed__c,
            buildPaymentDisbursementStageCandidates(currentViewId)
        );

        if (String.isBlank(lineItemStageKey) && String.isBlank(assetStageKey)) {
            return;
        }

        Boolean allAssetsMarked = true;
        Integer totalAssets = countAssetsForLineItem(lineItemId);

        // For single-asset line items, keep payment disbursement stage tracking at line-item level.
        // Asset stage is updated only when a line item has multiple assets.
        if (totalAssets > 1 && String.isNotBlank(assetStageKey)) {
            allAssetsMarked = markAssetStageAsComplete(lineItemId, assetId, assetStageKey);
        } else if (totalAssets > 1 && String.isBlank(assetStageKey)) {
            allAssetsMarked = false;
        }

        if (String.isNotBlank(lineItemStageKey) && (totalAssets == 0 || allAssetsMarked)) {
            List<Application_Line_Item__c> lineItems = [
                SELECT Id, Stage_Completed__c
                FROM Application_Line_Item__c
                WHERE Id = :lineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!lineItems.isEmpty()) {
                Application_Line_Item__c lineItemToUpdate = lineItems[0];
                lineItemToUpdate.Stage_Completed__c = appendStageIfMissing(
                    lineItemToUpdate.Stage_Completed__c,
                    lineItemStageKey
                );
                update lineItemToUpdate;
            }
        }
    }

    private static Boolean markAssetStageAsComplete(Id lineItemId, Id assetId, String stageKey) {
        if (String.isBlank(stageKey) || lineItemId == null) {
            return false;
        }

        List<Asset__c> assetsToEvaluate;
        if (assetId != null) {
            assetsToEvaluate = [
                SELECT Id, Stage_Completed__c
                FROM Asset__c
                WHERE Id = :assetId AND Application_Line_Items__c = :lineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } else {
            assetsToEvaluate = [
                SELECT Id, Stage_Completed__c
                FROM Asset__c
                WHERE Application_Line_Items__c = :lineItemId
                WITH SECURITY_ENFORCED
            ];
        }

        if (assetsToEvaluate.isEmpty()) {
            return false;
        }

        List<Asset__c> assetsToUpdate = new List<Asset__c>();
        for (Asset__c asset : assetsToEvaluate) {
            String updatedStages = appendStageIfMissing(asset.Stage_Completed__c, stageKey);
            if (updatedStages != asset.Stage_Completed__c) {
                assetsToUpdate.add(
                    new Asset__c(
                        Id = asset.Id,
                        Stage_Completed__c = updatedStages
                    )
                );
            }
        }
        if (!assetsToUpdate.isEmpty()) {
            update assetsToUpdate;
        }

        return areAllAssetsComplete(lineItemId, stageKey);
    }

    private static Boolean areAllAssetsComplete(Id lineItemId, String stageKey) {
        if (lineItemId == null || String.isBlank(stageKey)) {
            return false;
        }
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
            if (!containsStage(asset.Stage_Completed__c, stageKey)) {
                return false;
            }
        }
        return true;
    }

    private static Integer countAssetsForLineItem(Id lineItemId) {
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

    private static String resolveSupportedStagePicklistValue(
        Schema.SObjectField stageCompletedField,
        List<String> candidates
    ) {
        if (stageCompletedField == null || candidates == null || candidates.isEmpty()) {
            return null;
        }
        List<Schema.PicklistEntry> entries = stageCompletedField.getDescribe().getPicklistValues();
        for (String candidate : candidates) {
            String normalizedCandidate = String.valueOf(candidate ?? '').trim();
            if (String.isBlank(normalizedCandidate)) {
                continue;
            }
            for (Schema.PicklistEntry entry : entries) {
                if (
                    entry.isActive() &&
                    (
                        normalizedCandidate.equalsIgnoreCase(entry.getValue()) ||
                        normalizedCandidate.equalsIgnoreCase(entry.getLabel())
                    )
                ) {
                    return entry.getValue();
                }
            }
        }
        return null;
    }

    private static List<String> buildPaymentDisbursementStageCandidates(String currentViewId) {
        List<String> candidates = new List<String>();
        candidates.add(PAYMENT_DISBURSEMENT_STAGE_KEY);
        candidates.add(PAYMENT_DISBURSEMENT_STAGE_LABEL);
        return candidates;
    }

    private static String appendStageIfMissing(String currentStages, String stageName) {
        if (String.isBlank(stageName) || containsStage(currentStages, stageName)) {
            return currentStages;
        }
        String stage = stageName.trim();
        return String.isBlank(currentStages) ? stage : currentStages + ';' + stage;
    }

    private static Boolean containsStage(String completedStages, String stageName) {
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

    private static Boolean isBeneficiaryFullyPaid(Loan_Beneficiary__c beneficiary, Decimal paidAmount) {
        if (beneficiary == null) {
            return false;
        }
        Decimal disbursementAmount = toDecimalSafe(beneficiary.Amount__c);
        return disbursementAmount > 0 && toDecimalSafe(paidAmount) >= disbursementAmount;
    }

    private static Map<Id, Decimal> queryPaidAmountsByBeneficiaryId(Set<Id> beneficiaryIds) {
        Map<Id, Decimal> paidByBeneficiaryId = new Map<Id, Decimal>();
        if (beneficiaryIds == null || beneficiaryIds.isEmpty()) {
            return paidByBeneficiaryId;
        }

        for (AggregateResult row : [
            SELECT
                Loan_Beneficiary__c beneficiaryId,
                SUM(Tranche_Disbursement_Amount__c) trancheTotal
            FROM Beneficiary_Payment__c
            WHERE Loan_Beneficiary__c IN :beneficiaryIds
            GROUP BY Loan_Beneficiary__c
        ]) {
            Id beneficiaryId = (Id) row.get('beneficiaryId');
            Decimal trancheTotal = toDecimalSafe(row.get('trancheTotal'));
            paidByBeneficiaryId.put(beneficiaryId, Math.max(0, trancheTotal));
        }

        return paidByBeneficiaryId;
    }

    private static Map<String, Decimal> queryTaAdjustedAmountsByReference(Set<Id> beneficiaryIds) {
        Map<String, Decimal> adjustedByReference = new Map<String, Decimal>();
        if (beneficiaryIds == null || beneficiaryIds.isEmpty()) {
            return adjustedByReference;
        }

        for (AggregateResult row : [
            SELECT
                TA_Reference_Number__c taReferenceNumber,
                SUM(Adjusted_Amount__c) adjustedAmountTotal
            FROM Beneficiary_Payment__c
            WHERE Loan_Beneficiary__c IN :beneficiaryIds AND TA_Reference_Number__c != null
            GROUP BY TA_Reference_Number__c
        ]) {
            String taReferenceNumber = String.valueOf(row.get('taReferenceNumber')).trim();
            if (String.isNotBlank(taReferenceNumber)) {
                adjustedByReference.put(taReferenceNumber, toDecimalSafe(row.get('adjustedAmountTotal')));
            }
        }

        return adjustedByReference;
    }

    private static Decimal toDecimalSafe(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Decimal parseAdjustedAmount(Map<String, Object> payment) {
        if (payment == null) {
            return 0;
        }
        List<String> adjustedAmountKeys = new List<String>{
            'adjustedAmount',
            'toBeAdjustedNow',
            'adjustedAmt',
            'adjusted_amount'
        };
        for (String key : adjustedAmountKeys) {
            if (payment.containsKey(key) && payment.get(key) != null) {
                Decimal parsedValue = toDecimalSafe(payment.get(key));
                if (parsedValue > 0) {
                    return parsedValue;
                }
            }
        }
        return 0;
    }

    private static Map<String, Object> buildEmptyPageResult() {
        return new Map<String, Object>{
            'isSuccess' => false,
            'summaryCounts' => new Map<String, Object>{
                'pendingCount' => 0,
                'completedCount' => 0
            },
            'beneficiaryRows' => new List<Map<String, Object>>(),
            'paymentOriginatedFrom' => '',
            'taAdjustedByReference' => new Map<String, Decimal>()
        };
    }

    private static Map<String, Object> buildErrorResult(String message) {
        return new Map<String, Object>{
            'isSuccess' => false,
            'loadError' => message
        };
    }

    private static Id parseId(Object recordIdValue) {
        if (recordIdValue == null) {
            return null;
        }
        try {
            return (Id) String.valueOf(recordIdValue);
        } catch (Exception ex) {
            return null;
        }
    }

    private class DisbursementPageContext {
        Id lineItemId;
        Disbursement_Details__c disbursementDetails;
        String paymentOriginatedFrom = '';
        Date dealDate;
        Date firstEmiDate;
        Date secondEmiDate;
    }

    private class PaymentEntry {
        Decimal toBePaidNow;
        Decimal adjustedAmount;
        String taReferenceNumber;

        PaymentEntry(
            Decimal toBePaidNow,
            Decimal adjustedAmount,
            String taReferenceNumber
        ) {
            this.toBePaidNow = toDecimalSafe(toBePaidNow);
            this.adjustedAmount = toDecimalSafe(adjustedAmount);
            this.taReferenceNumber = String.isNotBlank(taReferenceNumber)
                ? taReferenceNumber.trim()
                : null;
        }
    }

    private class ScopeContext {
        Id applicationLineItemId;
        Id assetId;
    }
}