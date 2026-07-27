public with sharing class ListofAssetDetailsController {

    private static final String BORROWER = 'Borrower';
    private static final String STATUS_IN_PROGRESS = 'IN_PROGRESS';
    private static final String STATUS_COMPLETED = 'COMPLETED';
    private static final String ASSET_DETAILS_STAGE = 'Asset Details';
    private static final String VALUATION_STAGE = 'Valuation';
    private static final String LOAN_TERMS_STAGE = 'Loan Terms';
    private static final String OFFER_STAGE = 'Offer';
    private static final String AGREEMENT_PSS_STAGE = 'Agreement_PSS';
    private static final String AGREEMENT_OPS_STAGE = 'Agreement_OPS';
    private static final String REPAYMENT_PSS_STAGE = 'Repayment_PSS';
    private static final String REPAYMENT_OPS_STAGE = 'Repayment_OPS';
    private static final String REPAYMENT_OPS_VIEW_ID = 'Wheels_Repayment_OPS';
    private static final String AGREEMENT_OPS_VIEW_ID = 'Wheels_Agreement_OPS';
    private static final String INVOICE_PSS_STAGE = 'Invoice_PSS';
    private static final String INVOICE_OPS_STAGE = 'Invoice_OPS';
    private static final String INVOICE_OPS_VIEW_ID = 'Wheels_Invoice_OPS';
    private static final String IHM_PSS_STAGE = 'IHM_PSS';
    private static final String IHM_OPS_STAGE = 'IHM_OPS';
    private static final String IHM_OPS_VIEW_ID = 'Wheels_IHM_OPS';
    private static final String PAYMENT_REQUEST_PSS_STAGE = 'Payment_Request_PSS';
    private static final String PAYMENT_REQUEST_OPS_STAGE = 'Payment_Request_OPS';
    private static final String PAYMENT_REQUEST_OPS_VIEW_ID = 'Wheels_Payment_Request_OPS';
    private static final String PAYMENT_DISBURSEMENT_STAGE = 'Payment Disbursement';
    private static final String PAYMENT_DISBURSEMENT_STAGE_KEY = 'Payment_Disbursement';
    private static final String POST_DISBURSEMENT_TRACKING_STAGE = 'Post-Disbursement Tracking';
    private static final String POST_DISBURSEMENT_TRACKING_STAGE_KEY = 'Post_Disbursement_Tracking';

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getApplicationAssets(Id applicationId, String currentViewId) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'assets' => new List<Map<String, Object>>()
        };

        if (applicationId == null) {
            result.put('message', 'Application ID is required.');
            return result;
        }

        try {
            String productType = null;
            List<Application_Line_Item__c> lineItems = [
                SELECT Id,
                       Name,
                       Schemes__c,
                       Stage_Completed__c,
                       Product__c,
                       (SELECT Id,
                               Name,
                               Make__c,
                               Make_Name__c,
                               Model__c,
                               Model_Name__c,
                               Variant__c,
                               Variant_Name__c,
                               Vehicle_type__c,
                               Basic_Price__c,
                               Vehicle_Registration_number__c,
                               Required_Total_Loan_Amount__c,
                               Dealer_Sub_dealer_name__c,
                               Stage_Completed__c
                        FROM Assets__r
                        ORDER BY CreatedDate ASC)
                FROM Application_Line_Item__c
                WHERE Application__c = :applicationId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
            ];

            Set<Id> assetIds = new Set<Id>();
            Set<Id> lineItemIds = new Set<Id>();
            for (Application_Line_Item__c lineItem : lineItems) {
                lineItemIds.add(lineItem.Id);
                productType = lineItem.Product__c;
                Asset__c primaryAsset = getPrimaryAsset(lineItem);
                if (primaryAsset != null) {
                    assetIds.add(primaryAsset.Id);
                }
            }
            Set<Id> assetsWithViability = loadAssetsWithViability(assetIds);
            Map<Id, String> paymentDisbursementStatusByLineItem = loadPaymentDisbursementStatusByLineItem(
                lineItemIds
            );
            String repaymentStageKey = resolveRepaymentStageCompletedValue(currentViewId);
            String agreementStageKey = resolveAgreementStageCompletedValue(currentViewId);
            String invoiceStageKey = resolveInvoiceStageCompletedValue(currentViewId);
            String ihmStageKey = resolveIhmStageCompletedValue(currentViewId);
            String paymentRequestStageKey = resolvePaymentRequestStageCompletedValue(currentViewId);
            List<String> paymentDisbursementStageCandidates = buildPaymentDisbursementStageCandidates(
                currentViewId
            );
            List<String> postDisbursementTrackingStageCandidates = buildPostDisbursementTrackingStageCandidates(
                currentViewId
            );

            List<Map<String, Object>> lineItemRows = new List<Map<String, Object>>();
            for (Application_Line_Item__c lineItem : lineItems) {
                Asset__c primaryAsset = getPrimaryAsset(lineItem);
                if (primaryAsset == null) {
                    continue;
                }
                Boolean hasViability = assetsWithViability.contains(primaryAsset.Id);
                lineItemRows.add(
                    toLineItemRow(
                        lineItem,
                        primaryAsset,
                        hasViability,
                        repaymentStageKey,
                        agreementStageKey,
                        invoiceStageKey,
                        ihmStageKey,
                        paymentRequestStageKey,
                        paymentDisbursementStageCandidates,
                        postDisbursementTrackingStageCandidates,
                        paymentDisbursementStatusByLineItem
                    )
                );
            }
            result.put('isSuccess', true);
            result.put('productType', productType);
            result.put('assets', lineItemRows);
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }

        return result;
    }

    @AuraEnabled
    public static Map<String, Object> createApplicationAsset(Id applicationId) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };

        if (applicationId == null) {
            result.put('message', 'Application ID is required.');
            return result;
        }

        if (!Schema.sObjectType.Application_Line_Item__c.isCreateable()
            || !Schema.sObjectType.Asset__c.isCreateable()) {
            result.put('message', 'Insufficient permissions to create application line item records.');
            return result;
        }

        Savepoint savepoint = Database.setSavepoint();

        try {
            List<Application__c> applications = [
                SELECT Id
                FROM Application__c
                WHERE Id = :applicationId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (applications.isEmpty()) {
                result.put('message', 'Application record not found.');
                return result;
            }

            Id borrowerId = resolveBorrowerId(applicationId);
            if (borrowerId == null) {
                result.put('message', 'Borrower applicant not found for this application.');
                return result;
            }

            Application_Line_Item__c lineItem = new Application_Line_Item__c(
                Application__c = applicationId
            );
            insert lineItem;

            Asset__c templateAsset = getFirstApplicationAssetTemplate(applicationId);

            Asset__c asset = new Asset__c(
                Application_Line_Items__c = lineItem.Id,
                Applicant__c = borrowerId
            );
            applyAssetTemplateFields(asset, templateAsset);
            insert asset;

            lineItem = [
                SELECT Id,
                       Name,
                       Schemes__c,
                       Stage_Completed__c,
                       (SELECT Id,
                               Name,
                               Make__c,
                               Make_Name__c,
                               Model__c,
                               Model_Name__c,
                               Variant__c,
                               Variant_Name__c,
                               Vehicle_type__c,
                               Basic_Price__c,
                               Vehicle_Registration_number__c,
                               Required_Total_Loan_Amount__c,
                               Dealer_Sub_dealer_name__c,
                               Stage_Completed__c
                        FROM Assets__r
                        ORDER BY CreatedDate ASC)
                FROM Application_Line_Item__c
                WHERE Id = :lineItem.Id
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            Asset__c primaryAsset = getPrimaryAsset(lineItem);

            result.put('isSuccess', true);
            result.put('message', 'Asset created successfully.');
            result.put('asset', toLineItemRow(lineItem, primaryAsset, false));
            result.put('lineItemId', lineItem.Id);
        } catch (Exception ex) {
            Database.rollback(savepoint);
            result.put('message', ex.getMessage());
        }

        return result;
    }

    @AuraEnabled
    public static Map<String, Object> cloneApplicationAssets(
        Id sourceLineItemId,
        Integer quantity,
        Id sourceAssetId
    ) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'assets' => new List<Map<String, Object>>()
        };

        Id resolvedSourceLineItemId = resolveLineItemId(sourceLineItemId, sourceAssetId);
        if (resolvedSourceLineItemId == null) {
            result.put('message', 'Source asset ID is required.');
            return result;
        }

        if (quantity == null || quantity < 1) {
            result.put('message', 'Quantity must be at least 1.');
            return result;
        }

        if (!Schema.sObjectType.Application_Line_Item__c.isCreateable()
            || !Schema.sObjectType.Asset__c.isCreateable()) {
            result.put('message', 'Insufficient permissions to clone application line item records.');
            return result;
        }

        Savepoint savepoint = Database.setSavepoint();

        try {
            List<Application_Line_Item__c> sourceLineItems = [
                SELECT Id,
                       Application__c,
                       (SELECT Id,
                               Applicant__c,
                               Make__c,
                               Make_Name__c,
                               Model__c,
                               Model_Name__c,
                               Variant__c,
                               Variant_Name__c,
                               Vehicle_type__c,
                               Purpose_of_purchase__c
                        FROM Assets__r
                        ORDER BY CreatedDate ASC)
                FROM Application_Line_Item__c
                WHERE Id = :resolvedSourceLineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (sourceLineItems.isEmpty()) {
                result.put('message', 'Source asset not found.');
                return result;
            }

            Application_Line_Item__c sourceLineItem = sourceLineItems[0];
            Asset__c sourceAsset = getPrimaryAsset(sourceLineItem);

            if (sourceAsset == null) {
                result.put('message', 'No asset found for this application line item.');
                return result;
            }

            if (mapVehicleTypeForUi(sourceAsset.Vehicle_type__c) != 'NEW') {
                result.put('message', 'Cloning is only available for new vehicle assets.');
                return result;
            }

            Id applicationId = sourceLineItem.Application__c;
            if (applicationId == null) {
                result.put('message', 'Application not found for this line item.');
                return result;
            }

            Id borrowerId = sourceAsset.Applicant__c != null
                ? sourceAsset.Applicant__c
                : resolveBorrowerId(applicationId);
            if (borrowerId == null) {
                result.put('message', 'Borrower applicant not found for this application.');
                return result;
            }

            List<Application_Line_Item__c> lineItems = new List<Application_Line_Item__c>();
            for (Integer i = 0; i < quantity; i++) {
                lineItems.add(new Application_Line_Item__c(Application__c = applicationId));
            }
            insert lineItems;

            List<Asset__c> clonedAssets = new List<Asset__c>();
            for (Application_Line_Item__c lineItem : lineItems) {
                clonedAssets.add(buildClonedAsset(sourceAsset, lineItem.Id, borrowerId));
            }
            insert clonedAssets;

            Set<Id> clonedLineItemIds = new Set<Id>();
            for (Application_Line_Item__c lineItem : lineItems) {
                clonedLineItemIds.add(lineItem.Id);
            }

            List<Application_Line_Item__c> insertedLineItems = [
                SELECT Id,
                       Name,
                       Schemes__c,
                       Stage_Completed__c,
                       (SELECT Id,
                               Name,
                               Make__c,
                               Make_Name__c,
                               Model__c,
                               Model_Name__c,
                               Variant__c,
                               Variant_Name__c,
                               Vehicle_type__c,
                               Basic_Price__c,
                               Vehicle_Registration_number__c,
                               Required_Total_Loan_Amount__c,
                               Dealer_Sub_dealer_name__c,
                               Stage_Completed__c
                        FROM Assets__r
                        ORDER BY CreatedDate ASC)
                FROM Application_Line_Item__c
                WHERE Id IN :clonedLineItemIds
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
            ];

            List<Map<String, Object>> lineItemRows = new List<Map<String, Object>>();
            for (Application_Line_Item__c lineItem : insertedLineItems) {
                lineItemRows.add(toLineItemRow(lineItem, getPrimaryAsset(lineItem), false));
            }

            result.put('isSuccess', true);
            result.put(
                'message',
                quantity == 1 ? 'Asset cloned successfully.' : quantity + ' assets cloned successfully.'
            );
            result.put('assets', lineItemRows);
        } catch (Exception ex) {
            Database.rollback(savepoint);
            result.put('message', ex.getMessage());
        }

        return result;
    }

    private static Asset__c buildClonedAsset(Asset__c sourceAsset, Id lineItemId, Id borrowerId) {
        return new Asset__c(
            Application_Line_Items__c = lineItemId,
            Applicant__c = borrowerId,
            Make__c = sourceAsset.Make__c,
            Make_Name__c = sourceAsset.Make_Name__c,
            Model__c = sourceAsset.Model__c,
            Model_Name__c = sourceAsset.Model_Name__c,
            Variant__c = sourceAsset.Variant__c,
            Variant_Name__c = sourceAsset.Variant_Name__c,
            Vehicle_type__c = sourceAsset.Vehicle_type__c,
            Purpose_of_purchase__c = sourceAsset.Purpose_of_purchase__c
        );
    }

    @AuraEnabled
    public static Map<String, Object> deleteApplicationAsset(Id lineItemId, Id assetId) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };

        Id resolvedLineItemId = resolveLineItemId(lineItemId, assetId);
        if (resolvedLineItemId == null) {
            result.put('message', 'Asset ID is required.');
            return result;
        }

        if (!Schema.sObjectType.Asset__c.isDeletable()) {
            result.put('message', 'Insufficient permissions to delete asset records.');
            return result;
        }

        Savepoint savepoint = Database.setSavepoint();

        try {
            List<Application_Line_Item__c> lineItems = [
                SELECT Id,
                       (SELECT Id FROM Assets__r)
                FROM Application_Line_Item__c
                WHERE Id = :resolvedLineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (lineItems.isEmpty()) {
                result.put('message', 'Asset record not found.');
                return result;
            }

            Application_Line_Item__c lineItem = lineItems[0];
            List<Asset__c> relatedAssets = lineItem.Assets__r;

            if (assetId != null && Schema.sObjectType.Asset__c.isDeletable()) {
                List<Asset__c> assetsToDelete = new List<Asset__c>();
                for (Asset__c relatedAsset : relatedAssets) {
                    if (relatedAsset.Id == assetId) {
                        assetsToDelete.add(relatedAsset);
                        break;
                    }
                }
                if (!assetsToDelete.isEmpty()) {
                    delete assetsToDelete;
                }
            } else if (!relatedAssets.isEmpty() && Schema.sObjectType.Asset__c.isDeletable()) {
                delete relatedAssets;
            }

            List<Asset__c> remainingAssets = [
                SELECT Id
                FROM Asset__c
                WHERE Application_Line_Items__c = :resolvedLineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (remainingAssets.isEmpty() && Schema.sObjectType.Application_Line_Item__c.isDeletable()) {
                delete lineItem;
            }

            result.put('isSuccess', true);
            result.put('message', 'Asset deleted successfully.');
        } catch (Exception ex) {
            Database.rollback(savepoint);
            result.put('message', ex.getMessage());
        }

        return result;
    }

    private static Id resolveLineItemId(Id lineItemId, Id assetId) {
        if (lineItemId != null) {
            return lineItemId;
        }
        if (assetId == null) {
            return null;
        }

        List<Asset__c> assets = [
            SELECT Application_Line_Items__c
            FROM Asset__c
            WHERE Id = :assetId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Application_Line_Items__c;
    }

    private static Asset__c getPrimaryAsset(Application_Line_Item__c lineItem) {
        if (lineItem == null || lineItem.Assets__r == null || lineItem.Assets__r.isEmpty()) {
            return null;
        }
        return lineItem.Assets__r[0];
    }

    private static Integer getLineItemAssetCount(Application_Line_Item__c lineItem) {
        if (lineItem == null || lineItem.Assets__r == null) {
            return 0;
        }
        return lineItem.Assets__r.size();
    }

    private static Id resolveBorrowerId(Id applicationId) {
        List<Applicant__c> borrowers = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND Applicant_Type__c = :BORROWER
              AND (In_Active_Applicant__c = false OR In_Active_Applicant__c = null)
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return borrowers.isEmpty() ? null : borrowers[0].Id;
    }

    private static Map<String, Object> toLineItemRow(
        Application_Line_Item__c lineItem,
        Asset__c asset,
        Boolean hasViabilityCheck
    ) {
        return toLineItemRow(
            lineItem,
            asset,
            hasViabilityCheck,
            REPAYMENT_PSS_STAGE,
            AGREEMENT_PSS_STAGE,
            INVOICE_PSS_STAGE,
            IHM_PSS_STAGE,
            PAYMENT_REQUEST_PSS_STAGE,
            null,
            null,
            null
        );
    }

    private static Map<String, Object> toLineItemRow(
        Application_Line_Item__c lineItem,
        Asset__c asset,
        Boolean hasViabilityCheck,
        String repaymentStageKey,
        String agreementStageKey,
        String invoiceStageKey,
        String ihmStageKey,
        String paymentRequestStageKey,
        List<String> paymentDisbursementStageCandidates,
        List<String> postDisbursementTrackingStageCandidates,
        Map<Id, String> paymentDisbursementStatusByLineItem
    ) {
        String displayId;
        if (asset != null && String.isNotBlank(asset.Name)) {
            displayId = asset.Name;
        } else if (lineItem != null && String.isNotBlank(lineItem.Name)) {
            displayId = lineItem.Name;
        } else if (lineItem != null) {
            displayId = String.valueOf(lineItem.Id);
        } else {
            displayId = '';
        }

        return new Map<String, Object>{
            'id' => displayId,
            'lineItemId' => lineItem?.Id,
            'assetId' => asset?.Id,
            'assetCount' => getLineItemAssetCount(lineItem),
            'childAssets' => buildChildAssetRows(
                lineItem,
                invoiceStageKey,
                ihmStageKey,
                paymentRequestStageKey,
                paymentDisbursementStageCandidates,
                resolvePaymentDisbursementStatus(lineItem, paymentDisbursementStatusByLineItem),
                postDisbursementTrackingStageCandidates,
                resolvePostDisbursementTrackingStatus(lineItem, postDisbursementTrackingStageCandidates)
            ),
            'type' => mapVehicleTypeForUi(asset?.Vehicle_type__c),
            'status' => resolveAssetStatus(lineItem, asset, hasViabilityCheck),
            'valuationStatus' => resolveValuationStatus(lineItem, asset),
            'loanTermsStatus' => resolveLoanTermsStatus(lineItem),
            'offerStatus' => resolveOfferStatus(lineItem),
            'repaymentStatus' => resolveRepaymentStatus(lineItem, repaymentStageKey),
            'agreementStatus' => resolveAgreementStatus(lineItem, agreementStageKey),
            'invoiceStatus' => resolveInvoiceStatus(lineItem, invoiceStageKey),
            'ihmStatus' => resolveIhmStatus(lineItem, ihmStageKey),
            'paymentRequestStatus' => resolvePaymentRequestStatus(lineItem, paymentRequestStageKey),
            'paymentDisbursementStatus' => resolvePaymentDisbursementStatus(
                lineItem,
                paymentDisbursementStatusByLineItem
            ),
            'postDisbursementTrackingStatus' => resolvePostDisbursementTrackingStatus(
                lineItem,
                postDisbursementTrackingStageCandidates
            ),
            'make' => asset?.Make_Name__c,
            'model' => asset?.Model_Name__c,
            'variant' => asset?.Variant_Name__c,
            'dealer' => asset?.Dealer_Sub_dealer_name__c,
            'regNo' => asset?.Vehicle_Registration_number__c
        };
    }

    private static List<Map<String, Object>> buildChildAssetRows(
        Application_Line_Item__c lineItem,
        String invoiceStageKey,
        String ihmStageKey,
        String paymentRequestStageKey,
        List<String> paymentDisbursementStageCandidates,
        String paymentDisbursementStatus,
        List<String> postDisbursementTrackingStageCandidates,
        String postDisbursementTrackingStatus
    ) {
        List<Map<String, Object>> childAssets = new List<Map<String, Object>>();
        if (lineItem == null || lineItem.Assets__r == null || lineItem.Assets__r.isEmpty()) {
            return childAssets;
        }

        for (Asset__c relatedAsset : lineItem.Assets__r) {
            childAssets.add(
                toAssetRow(
                    relatedAsset,
                    invoiceStageKey,
                    ihmStageKey,
                    paymentRequestStageKey,
                    paymentDisbursementStageCandidates,
                    paymentDisbursementStatus,
                    postDisbursementTrackingStageCandidates,
                    postDisbursementTrackingStatus
                )
            );
        }

        return childAssets;
    }

    private static Map<String, Object> toAssetRow(
        Asset__c asset,
        String invoiceStageKey,
        String ihmStageKey,
        String paymentRequestStageKey,
        List<String> paymentDisbursementStageCandidates,
        String paymentDisbursementStatus,
        List<String> postDisbursementTrackingStageCandidates,
        String postDisbursementTrackingStatus
    ) {
        String displayId = String.isNotBlank(asset?.Name)
            ? asset.Name
            : (asset?.Id != null ? String.valueOf(asset.Id) : '');

        return new Map<String, Object>{
            'id' => displayId,
            'assetId' => asset?.Id,
            'type' => mapVehicleTypeForUi(asset?.Vehicle_type__c),
            'invoiceStatus' => resolveAssetInvoiceStatus(asset, invoiceStageKey),
            'ihmStatus' => resolveAssetIhmStatus(asset, ihmStageKey),
            'paymentRequestStatus' => resolveAssetPaymentRequestStatus(asset, paymentRequestStageKey),
            'paymentDisbursementStatus' => resolveAssetPaymentDisbursementStatus(
                asset,
                paymentDisbursementStageCandidates,
                paymentDisbursementStatus
            ),
            'postDisbursementTrackingStatus' => resolveAssetPostDisbursementTrackingStatus(
                asset,
                postDisbursementTrackingStageCandidates,
                postDisbursementTrackingStatus
            ),
            'make' => asset?.Make__c,
            'model' => asset?.Model__c,
            'variant' => asset?.Variant__c,
            'dealer' => asset?.Dealer_Sub_dealer_name__c,
            'regNo' => asset?.Vehicle_Registration_number__c
        };
    }

    private static String resolveAssetInvoiceStatus(Asset__c asset, String invoiceStageKey) {
        return hasStageCompleted(asset?.Stage_Completed__c, invoiceStageKey)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveAssetIhmStatus(Asset__c asset, String ihmStageKey) {
        return hasStageCompleted(asset?.Stage_Completed__c, ihmStageKey)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveAssetPaymentRequestStatus(Asset__c asset, String paymentRequestStageKey) {
        return hasStageCompleted(asset?.Stage_Completed__c, paymentRequestStageKey)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveAssetPaymentDisbursementStatus(
        Asset__c asset,
        List<String> paymentDisbursementStageCandidates,
        String lineItemFallbackStatus
    ) {
        if (hasAnyStageCompleted(asset?.Stage_Completed__c, paymentDisbursementStageCandidates)) {
            return STATUS_COMPLETED;
        }
        return STATUS_COMPLETED.equalsIgnoreCase(lineItemFallbackStatus)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveAssetPostDisbursementTrackingStatus(
        Asset__c asset,
        List<String> postDisbursementTrackingStageCandidates,
        String lineItemFallbackStatus
    ) {
        if (hasAnyStageCompleted(asset?.Stage_Completed__c, postDisbursementTrackingStageCandidates)) {
            return STATUS_COMPLETED;
        }
        return STATUS_COMPLETED.equalsIgnoreCase(lineItemFallbackStatus)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveRepaymentStatus(
        Application_Line_Item__c lineItem,
        String repaymentStageKey
    ) {
        return hasStageCompleted(lineItem?.Stage_Completed__c, repaymentStageKey)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveRepaymentStageCompletedValue(String currentViewId) {
        if (REPAYMENT_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
            return REPAYMENT_OPS_STAGE;
        }
        return REPAYMENT_PSS_STAGE;
    }

    private static String resolveAgreementStatus(
        Application_Line_Item__c lineItem,
        String agreementStageKey
    ) {
        return hasStageCompleted(lineItem?.Stage_Completed__c, agreementStageKey)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveAgreementStageCompletedValue(String currentViewId) {
        if (AGREEMENT_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
            return AGREEMENT_OPS_STAGE;
        }
        return AGREEMENT_PSS_STAGE;
    }

    private static String resolveInvoiceStatus(
        Application_Line_Item__c lineItem,
        String invoiceStageKey
    ) {
        if (hasStageCompleted(lineItem?.Stage_Completed__c, invoiceStageKey)) {
            return STATUS_COMPLETED;
        }
        if (getLineItemAssetCount(lineItem) <= 1) {
            return STATUS_IN_PROGRESS;
        }
        for (Asset__c asset : lineItem.Assets__r) {
            if (!hasStageCompleted(asset?.Stage_Completed__c, invoiceStageKey)) {
                return STATUS_IN_PROGRESS;
            }
        }
        return STATUS_COMPLETED;
    }

    private static String resolveInvoiceStageCompletedValue(String currentViewId) {
        if (INVOICE_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
            return INVOICE_OPS_STAGE;
        }
        return INVOICE_PSS_STAGE;
    }

    private static String resolveIhmStatus(
        Application_Line_Item__c lineItem,
        String ihmStageKey
    ) {
        if (hasStageCompleted(lineItem?.Stage_Completed__c, ihmStageKey)) {
            return STATUS_COMPLETED;
        }
        if (getLineItemAssetCount(lineItem) <= 1) {
            return STATUS_IN_PROGRESS;
        }
        for (Asset__c asset : lineItem.Assets__r) {
            if (!hasStageCompleted(asset?.Stage_Completed__c, ihmStageKey)) {
                return STATUS_IN_PROGRESS;
            }
        }
        return STATUS_COMPLETED;
    }

    private static String resolveIhmStageCompletedValue(String currentViewId) {
        if (IHM_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
            return IHM_OPS_STAGE;
        }
        return IHM_PSS_STAGE;
    }

    private static String resolvePaymentRequestStatus(
        Application_Line_Item__c lineItem,
        String paymentRequestStageKey
    ) {
        if (hasStageCompleted(lineItem?.Stage_Completed__c, paymentRequestStageKey)) {
            return STATUS_COMPLETED;
        }
        if (getLineItemAssetCount(lineItem) <= 1) {
            return STATUS_IN_PROGRESS;
        }
        for (Asset__c asset : lineItem.Assets__r) {
            if (!hasStageCompleted(asset?.Stage_Completed__c, paymentRequestStageKey)) {
                return STATUS_IN_PROGRESS;
            }
        }
        return STATUS_COMPLETED;
    }

    private static String resolvePaymentRequestStageCompletedValue(String currentViewId) {
        if (PAYMENT_REQUEST_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
            return PAYMENT_REQUEST_OPS_STAGE;
        }
        return PAYMENT_REQUEST_PSS_STAGE;
    }

    private static List<String> buildPaymentDisbursementStageCandidates(String currentViewId) {
        List<String> stageKeyList = new List<String>();
        stageKeyList.add(PAYMENT_DISBURSEMENT_STAGE_KEY);
        stageKeyList.add(PAYMENT_DISBURSEMENT_STAGE);
        return stageKeyList;
    }

    private static List<String> buildPostDisbursementTrackingStageCandidates(String currentViewId) {
        List<String> stageKeyList = new List<String>();
        stageKeyList.add(POST_DISBURSEMENT_TRACKING_STAGE_KEY);
        stageKeyList.add(POST_DISBURSEMENT_TRACKING_STAGE);
        return stageKeyList;
    }

    private static String resolvePaymentDisbursementStatus(
        Application_Line_Item__c lineItem,
        Map<Id, String> paymentDisbursementStatusByLineItem
    ) {
        if (
            lineItem == null ||
            lineItem.Id == null ||
            paymentDisbursementStatusByLineItem == null ||
            !paymentDisbursementStatusByLineItem.containsKey(lineItem.Id)
        ) {
            return STATUS_IN_PROGRESS;
        }
        String resolvedStatus = paymentDisbursementStatusByLineItem.get(lineItem.Id);
        return STATUS_COMPLETED.equalsIgnoreCase(resolvedStatus)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolvePostDisbursementTrackingStatus(
        Application_Line_Item__c lineItem,
        List<String> postDisbursementTrackingStageCandidates
    ) {
        if (lineItem == null) {
            return STATUS_IN_PROGRESS;
        }

        if (hasAnyStageCompleted(lineItem.Stage_Completed__c, postDisbursementTrackingStageCandidates)) {
            return STATUS_COMPLETED;
        }

        if (getLineItemAssetCount(lineItem) <= 0) {
            return STATUS_IN_PROGRESS;
        }

        for (Asset__c asset : lineItem.Assets__r) {
            if (!hasAnyStageCompleted(asset?.Stage_Completed__c, postDisbursementTrackingStageCandidates)) {
                return STATUS_IN_PROGRESS;
            }
        }
        return STATUS_COMPLETED;
    }

    private static Map<Id, String> loadPaymentDisbursementStatusByLineItem(Set<Id> lineItemIds) {
        Map<Id, String> statusByLineItem = new Map<Id, String>();
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return statusByLineItem;
        }
        try {
            Map<Id, Id> disbursementDetailToLineItem = new Map<Id, Id>();
            for (Disbursement_Details__c disbursementDetails : [
                SELECT Id, Application_Line_Items__c
                FROM Disbursement_Details__c
                WHERE Application_Line_Items__c IN :lineItemIds
                WITH SECURITY_ENFORCED
            ]) {
                if (disbursementDetails.Application_Line_Items__c != null) {
                    disbursementDetailToLineItem.put(
                        disbursementDetails.Id,
                        disbursementDetails.Application_Line_Items__c
                    );
                }
            }

            if (disbursementDetailToLineItem.isEmpty()) {
                return statusByLineItem;
            }

            Set<Id> beneficiaryIds = new Set<Id>();
            Map<Id, Id> beneficiaryToLineItem = new Map<Id, Id>();
            Map<Id, Decimal> totalAmountByLineItem = new Map<Id, Decimal>();
            for (Loan_Beneficiary__c beneficiary : [
                SELECT Id, Amount__c, Disbursement_Details__c
                FROM Loan_Beneficiary__c
                WHERE Disbursement_Details__c IN :disbursementDetailToLineItem.keySet()
                WITH SECURITY_ENFORCED
            ]) {
                Id lineItemId = disbursementDetailToLineItem.get(beneficiary.Disbursement_Details__c);
                if (lineItemId == null) {
                    continue;
                }
                beneficiaryIds.add(beneficiary.Id);
                beneficiaryToLineItem.put(beneficiary.Id, lineItemId);

                Decimal currentTotalAmount = totalAmountByLineItem.containsKey(lineItemId)
                    ? totalAmountByLineItem.get(lineItemId)
                    : 0;
                totalAmountByLineItem.put(lineItemId, currentTotalAmount + toPositiveDecimal(beneficiary.Amount__c));
            }

            if (beneficiaryIds.isEmpty()) {
                return statusByLineItem;
            }

            Map<Id, Decimal> paidAmountByBeneficiary = new Map<Id, Decimal>();
            for (AggregateResult row : [
                SELECT Loan_Beneficiary__c beneficiaryId, SUM(Tranche_Disbursement_Amount__c) paidAmount
                FROM Beneficiary_Payment__c
                WHERE Loan_Beneficiary__c IN :beneficiaryIds
                GROUP BY Loan_Beneficiary__c
            ]) {
                Id beneficiaryId = (Id) row.get('beneficiaryId');
                paidAmountByBeneficiary.put(beneficiaryId, toPositiveDecimal(row.get('paidAmount')));
            }

            Map<Id, Decimal> paidAmountByLineItem = new Map<Id, Decimal>();
            for (Id beneficiaryId : beneficiaryIds) {
                Id lineItemId = beneficiaryToLineItem.get(beneficiaryId);
                if (lineItemId == null) {
                    continue;
                }
                Decimal currentPaidAmount = paidAmountByLineItem.containsKey(lineItemId)
                    ? paidAmountByLineItem.get(lineItemId)
                    : 0;
                Decimal beneficiaryPaidAmount = paidAmountByBeneficiary.containsKey(beneficiaryId)
                    ? paidAmountByBeneficiary.get(beneficiaryId)
                    : 0;
                paidAmountByLineItem.put(lineItemId, currentPaidAmount + beneficiaryPaidAmount);
            }

            for (Id lineItemId : lineItemIds) {
                Decimal totalAmount = totalAmountByLineItem.containsKey(lineItemId)
                    ? totalAmountByLineItem.get(lineItemId)
                    : 0;
                Decimal paidAmount = paidAmountByLineItem.containsKey(lineItemId)
                    ? paidAmountByLineItem.get(lineItemId)
                    : 0;
                if (totalAmount > 0 && paidAmount >= totalAmount) {
                    statusByLineItem.put(lineItemId, STATUS_COMPLETED);
                } else if (totalAmount > 0 || paidAmount > 0) {
                    statusByLineItem.put(lineItemId, STATUS_IN_PROGRESS);
                }
            }
        } catch (Exception ex) {
            return statusByLineItem;
        }

        return statusByLineItem;
    }

    private static Decimal toPositiveDecimal(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Decimal) {
            return Math.max(0, (Decimal) value);
        }
        if (value instanceof Integer) {
            return Math.max(0, Decimal.valueOf((Integer) value));
        }
        if (value instanceof Long) {
            return Math.max(0, Decimal.valueOf((Long) value));
        }
        try {
            return Math.max(0, Decimal.valueOf(String.valueOf(value)));
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Set<Id> loadAssetsWithViability(Set<Id> assetIds) {
        Set<Id> assetsWithViability = new Set<Id>();
        if (assetIds == null || assetIds.isEmpty()) {
            return assetsWithViability;
        }

        for (AggregateResult row : [
            SELECT Asset__c assetId
            FROM Viability_Check__c
            WHERE Asset__c IN :assetIds
            WITH SECURITY_ENFORCED
            GROUP BY Asset__c
        ]) {
            assetsWithViability.add((Id) row.get('assetId'));
        }

        return assetsWithViability;
    }

    private static String resolveAssetStatus(
        Application_Line_Item__c lineItem,
        Asset__c asset,
        Boolean hasViabilityCheck
    ) {
        String vehicleType = mapVehicleTypeForUi(asset?.Vehicle_type__c);

        if (vehicleType == 'NEW') {
            return hasStageCompleted(lineItem?.Stage_Completed__c, ASSET_DETAILS_STAGE)
                ? STATUS_COMPLETED
                : STATUS_IN_PROGRESS;
        }

        if (asset == null || hasViabilityCheck != true) {
            return STATUS_IN_PROGRESS;
        }

        return isUsedAssetComplete(asset) ? STATUS_COMPLETED : STATUS_IN_PROGRESS;
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

    private static Boolean hasAnyStageCompleted(
        String completedStages,
        List<String> stageCandidates
    ) {
        if (stageCandidates == null || stageCandidates.isEmpty()) {
            return false;
        }
        for (String stageCandidate : stageCandidates) {
            if (hasStageCompleted(completedStages, stageCandidate)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isUsedAssetComplete(Asset__c asset) {
        return String.isNotBlank(asset.Make__c)
            && String.isNotBlank(asset.Model__c)
            && String.isNotBlank(asset.Vehicle_Registration_number__c)
            && asset.Required_Total_Loan_Amount__c != null;
    }

    private static String resolveLoanTermsStatus(Application_Line_Item__c lineItem) {
        return hasStageCompleted(lineItem?.Stage_Completed__c, LOAN_TERMS_STAGE)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveValuationStatus(
        Application_Line_Item__c lineItem,
        Asset__c asset
    ) {
        if (mapVehicleTypeForUi(asset?.Vehicle_type__c) == 'NEW') {
            return STATUS_COMPLETED;
        }
        return hasStageCompleted(lineItem?.Stage_Completed__c, VALUATION_STAGE)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static String resolveOfferStatus(Application_Line_Item__c lineItem) {
        return hasStageCompleted(lineItem?.Stage_Completed__c, OFFER_STAGE)
            ? STATUS_COMPLETED
            : STATUS_IN_PROGRESS;
    }

    private static Asset__c getFirstApplicationAssetTemplate(Id applicationId) {
        List<Asset__c> existingAssets = [
            SELECT Vehicle_type__c,
                   Purpose_of_purchase__c
            FROM Asset__c
            WHERE Application_Line_Items__r.Application__c = :applicationId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        return existingAssets.isEmpty() ? null : existingAssets[0];
    }

    private static void applyAssetTemplateFields(Asset__c asset, Asset__c templateAsset) {
        if (asset == null || templateAsset == null) {
            return;
        }
        if (String.isNotBlank(templateAsset.Vehicle_type__c)) {
            asset.Vehicle_type__c = templateAsset.Vehicle_type__c.trim();
        }
        if (String.isNotBlank(templateAsset.Purpose_of_purchase__c)) {
            asset.Purpose_of_purchase__c = templateAsset.Purpose_of_purchase__c;
        }
    }

    private static String mapVehicleTypeForUi(String vehicleType) {
        if (String.isBlank(vehicleType)) {
            return 'NEW';
        }

        String normalized = vehicleType.trim().toUpperCase();
        if (normalized == 'USED') {
            return 'USED';
        }
        if (normalized == 'REFINANCE') {
            return 'REFINANCE';
        }
        return 'NEW';
    }
}