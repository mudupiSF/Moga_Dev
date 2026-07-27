/**
 * @description Controller for WheelsPaymentRequest LWC.
 * Uses targeted SOQL per line item, asset, and disbursement to minimise governor usage.
 * Child relationship names assume default Salesforce auto-generation — verify in your org.
 */
public with sharing class WheelsPaymentRequestController implements Callable {

    private static final String PAYMENT_REQUEST_PSS_STAGE = 'Payment_Request_PSS';
    private static final String PAYMENT_REQUEST_OPS_STAGE = 'Payment_Request_OPS';
    private static final String PAYMENT_REQUEST_OPS_VIEW_ID = 'Wheels_Payment_Request_OPS';

    // ── Callable interface — routes via GenericPageLayoutController ───────
    public Object call(String action, Map<String, Object> args) {
        // Bridge: serialize args Map to dataJson string so existing @AuraEnabled methods work unchanged.
        // Note: variable named 'dataJson' (not 'json') — Apex identifiers are case-insensitive,
        // so a local variable named 'json' would shadow the JSON system class and cause compile errors.
        String dataJson = JSON.serialize(args);
        if (action == 'getPageData') {
            // PageDataResult → Map via round-trip so GenericPageLayoutController can return it
            return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(getPageData(dataJson)));
        }
        if (action == 'savePaymentRequest') {
            return savePaymentRequest(dataJson);
        }
        if (action == 'moveBackToPssStage') {
            return moveBackToPssStage(dataJson);
        }
        throw new AuraHandledException('Unknown action: ' + action);
    }

    // ── Inner wrappers ─────────────────────────────────────────────────────
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String l, String v) { label = l; value = v; }
    }

    public class PageDataResult {
        @AuraEnabled public Asset__c                    asset;
        @AuraEnabled public Disbursement_Details__c     disbursementDetails;
        @AuraEnabled public Application_Line_Item__c    lineItem;
        @AuraEnabled public List<Loan_Beneficiary__c>   beneficiaryRows;
        @AuraEnabled public List<Payment_Adjustment__c> adjustmentRows;
        @AuraEnabled public String                      currentUserId;
        @AuraEnabled public String                      currentUserName;
        @AuraEnabled public String                      businessSourcedByName;
        @AuraEnabled public String                      businessDoneByName;
        @AuraEnabled public String                      fiDoneByName;
        @AuraEnabled public List<PicklistOption>        doIssuanceModeOptions;
        @AuraEnabled public List<PicklistOption>        purchaseDocOptions;
        @AuraEnabled public List<PicklistOption>        fundEndUseOptions;
    }

    // ── Load page data — scoped by line item, asset, and disbursement ─────
    @AuraEnabled(cacheable=false)
    public static PageDataResult getPageData(String dataJson) {
        PageDataResult result = new PageDataResult();
        result.beneficiaryRows = new List<Loan_Beneficiary__c>();
        result.adjustmentRows = new List<Payment_Adjustment__c>();
        result.doIssuanceModeOptions = getPicklistOptions('Disbursement_Details__c', 'Do_Issuance_Mode__c');
        result.purchaseDocOptions = getPicklistOptions('Disbursement_Details__c', 'Purchase_Document_Category__c');
        result.fundEndUseOptions = getPicklistOptions('Disbursement_Details__c', 'Fund_End_Use__c');
        result.currentUserId = UserInfo.getUserId();
        result.currentUserName = UserInfo.getName();

        try {
            Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
            Id recordId = (Id) params.get('recordId');
            if (recordId == null) {
                return result;
            }

            Id lineItemId = resolveLineItemId(
                toId((String) params.get('applicationLineItemId')),
                toId((String) params.get('assetId'))
            );
            Id assetId = toId((String) params.get('assetId'));

            // Query 1: Application_Line_Item__c (Disbursement_Details__c is a child of line item, not Application__c)
            Application_Line_Item__c lineItem = queryLineItem(recordId, lineItemId);
            Disbursement_Details__c dd;
            if (lineItem != null) {
                result.lineItem = lineItem;
                dd = queryDisbursement(lineItem.Id, assetId);
                if (dd != null) {
                    result.disbursementDetails = dd;
                    result.businessSourcedByName = dd.Business_Sourced_By__r?.Name;
                    result.businessDoneByName = dd.Business_Done_By__r?.Name;
                    result.fiDoneByName = dd.FI_Done_By__r?.Name;
                    // Beneficiary and adjustment rows are scoped to Disbursement_Details__c
                    result.beneficiaryRows = queryBeneficiaries(dd.Id);
                    result.adjustmentRows = queryAdjustments(dd.Id);
                }
            }

            // Query 2: Asset__c — by assetId when provided, else first asset on line item / borrower
            Asset__c asset = queryAsset(recordId, assetId, lineItem?.Id);
            if (asset != null) {
                result.asset = asset;
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return result;
    }

    // ── Save payment request — upsert disbursement first, then child rows ─
    @AuraEnabled
    public static Map<String, Object> savePaymentRequest(String dataJson) {
        Map<String, Object> result = new Map<String, Object>{ 'success' => false };
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
            Id recordId = (Id) payload.get('recordId');
            Id lineItemId = resolveLineItemId(
                toId((String) payload.get('applicationLineItemId')),
                toId((String) payload.get('assetId'))
            );
            Id assetId = toId((String) payload.get('assetId'));

            Map<String, Object> bp = (Map<String, Object>) payload.get('businessPayment');
            Map<String, Object> dis = (Map<String, Object>) payload.get('disbursement');
            Map<String, Object> veh = (Map<String, Object>) payload.get('vehicleDetails');
            List<Object> beneficiaryData = (List<Object>) payload.get('beneficiaryRows');
            List<Object> adjustmentData = (List<Object>) payload.get('adjustmentRows');
            Map<String, Object> operationData = (Map<String, Object>) payload.get('operationData');

            Application_Line_Item__c li = queryLineItem(recordId, lineItemId);
            Disbursement_Details__c dd;

            // ── 1. Upsert Disbursement_Details__c (per line item + asset) ───
            if (li != null) {
                dd = queryDisbursement(li.Id, assetId);
                if (dd == null) {
                    dd = new Disbursement_Details__c(
                        Application_Line_Items__c = li.Id,
                        Asset__c = assetId
                    );
                }

                if (bp != null) {
                    setIfNotNull(dd, 'Payment_Originated_From__c', bp.get('paymentOriginatedFrom'));
                    setIfNotNull(dd, 'Vehicle_Sold_By__c', bp.get('vehicleSoldBy'));
                    setIdIfNotNull(dd, 'Business_Sourced_By__c', bp.get('businessSourcedBy'));
                    setIdIfNotNull(dd, 'Business_Done_By__c', bp.get('businessDoneBy'));
                    setIdIfNotNull(dd, 'FI_Done_By__c', bp.get('fiDoneBy'));
                    setIfNotNull(dd, 'Collection_Executive__c', bp.get('collectionExecutive'));
                    setIfNotNull(dd, 'Do_Issuance_Mode__c', bp.get('doIssuance'));
                    setIfNotNull(dd, 'Do_To_be_authorized_by__c', bp.get('doToBeAuthorizedBy'));
                    setIfNotNull(dd, 'Vehicle_Registered_in_Name__c', bp.get('vehicleRegisteredInName'));
                    setIfNotNull(dd, 'Purchase_Document_Category__c', bp.get('purchaseDocCategory'));
                    setIfNotNull(dd, 'Fund_End_Use__c', bp.get('fundEndUse'));
                    setDecimalIfNotNull(dd, 'Balance_Transfer_Amount_in_Rs__c', bp.get('balanceTransfer'));
                    setDateIfNotNull(dd, 'DO_Issuance_Date__c', bp.get('doIssuanceDate'));
                    setDecimalIfNotNull(dd, 'Original_Purchase_value_in_Rs__c', bp.get('originalPurchaseValue'));
                    setDateIfNotNull(dd, 'Original_purchase_date__c', bp.get('originalPurchaseDate'));
                }
                if (dis != null) {
                    setDateIfNotNull(dd, 'Payment_to_be_made_on__c', dis.get('paymentDate'));
                    setDecimalIfNotNull(dd, 'Dealer_Payment__c', dis.get('dealerPayment'));
                }
                if (operationData != null) {
                    setIfNotNull(dd, 'Are_all_details_correct__c', operationData.get('areAllDetailsCorrect'));
                    setIfNotNull(dd, 'Remarks__c', operationData.get('remarks'));
                    dd.Payment_Requested_Date__c = Date.today();
                }
                upsert dd;
            }

            // ── 2. Update Asset__c (vehicle details for current asset) ──────
            if (veh != null) {
                Asset__c asset = queryAsset(recordId, assetId, li?.Id);
                if (asset != null) {
                    setIfNotNull(asset, 'Vehicle_Registration_number__c', veh.get('regNumber'));
                    setIfNotNull(asset, 'Engine_number__c', veh.get('engineNumber'));
                    setIfNotNull(asset, 'Chassis_number__c', veh.get('chassisNumber'));
                    setIfNotNull(asset, 'Name_transferred__c', veh.get('isNameTransferred'));
                    setIfNotNull(asset, 'Current_vehicle_owner__c', veh.get('currentVehicleOwner'));
                    setIfNotNull(asset, 'Now_lien_in_the_name_of__c', veh.get('nowLienInTheNameOf'));
                    setDateIfNotNull(asset, 'Marked_on__c', veh.get('markedOn'));
                    setDateIfNotNull(asset, 'RTA_taxes_remitted_upto__c', veh.get('rtaTaxRemittedUpto'));
                    Object lienVal = veh.get('lienMarked');
                    if (lienVal != null) {
                        asset.Lien_marked_to_bank__c = String.valueOf(lienVal).equalsIgnoreCase('Yes');
                    }
                    update asset;
                }
            }

            // ── 3. Update Application_Line_Item__c (EMI dates + holiday period) ─
            if (dis != null && li != null) {
                String emiDayStr = String.valueOf(dis.get('firstEmiDueDate') ?? '');
                if (String.isNotBlank(emiDayStr)) {
                    Integer emiDay = Integer.valueOf(emiDayStr);
                    Integer morDays = li.Holiday_period__c != null ? Integer.valueOf(li.Holiday_period__c) : 0;
                    Date today = Date.today().addDays(morDays);
                    Date firstEmi = today.day() < emiDay
                        ? Date.newInstance(today.year(), today.month(), emiDay)
                        : Date.newInstance(today.addMonths(1).year(), today.addMonths(1).month(), emiDay);
                    li.First_EMI_Date__c = firstEmi;
                    li.Second_EMI_Date__c = firstEmi.addMonths(1);
                    update li;
                }
            }

            // ── 4. Replace Loan_Beneficiary__c rows for this disbursement ─────
            if (beneficiaryData != null && dd != null && dd.Id != null) {
                List<Loan_Beneficiary__c> existingBeneficiaries = [
                    SELECT Id
                    FROM Loan_Beneficiary__c
                    WHERE Disbursement_Details__c = :dd.Id
                    WITH SECURITY_ENFORCED
                ];
                if (!existingBeneficiaries.isEmpty()) {
                    delete existingBeneficiaries;
                }
                List<Loan_Beneficiary__c> toInsert = new List<Loan_Beneficiary__c>();
                for (Object obj : beneficiaryData) {
                    Map<String, Object> row = (Map<String, Object>) obj;
                    String rowName = String.valueOf(row.get('name') ?? '');
                    if (String.isBlank(rowName)) {
                        continue;
                    }
                    Loan_Beneficiary__c lb = new Loan_Beneficiary__c(
                        Application__c = recordId,
                        Disbursement_Details__c = dd.Id,
                        Beneficiary_Name__c = rowName,
                        Type__c = 'Dealer'
                    );
                    setIfNotNull(lb, 'Account_Number__c', row.get('accountNumber'));
                    setIfNotNull(lb, 'IFSC_Code__c', row.get('ifscCode'));
                    setDecimalIfNotNull(lb, 'Amount__c', row.get('amount'));
                    toInsert.add(lb);
                }
                if (!toInsert.isEmpty()) {
                    insert toInsert;
                }
            }

            // ── 5. Replace Payment_Adjustment__c rows for this disbursement ─
            if (adjustmentData != null && dd != null && dd.Id != null) {
                List<Payment_Adjustment__c> existingAdjustments = [
                    SELECT Id
                    FROM Payment_Adjustment__c
                    WHERE Disbursement_Details__c = :dd.Id
                    WITH SECURITY_ENFORCED
                ];
                if (!existingAdjustments.isEmpty()) {
                    delete existingAdjustments;
                }
                List<Payment_Adjustment__c> toInsert = new List<Payment_Adjustment__c>();
                for (Object obj : adjustmentData) {
                    Map<String, Object> row = (Map<String, Object>) obj;
                    String dealNo = String.valueOf(row.get('dealNumber') ?? '');
                    if (String.isBlank(dealNo)) {
                        continue;
                    }
                    Payment_Adjustment__c pa = new Payment_Adjustment__c(
                        Application__c = recordId,
                        Disbursement_Details__c = dd.Id,
                        Deal_Number__c = dealNo
                    );
                    setIfNotNull(pa, 'Customer_Name__c', row.get('customerName'));
                    setIfNotNull(pa, 'Customer_Code__c', row.get('customerCode'));
                    setDecimalIfNotNull(pa, 'Amount__c', row.get('amount'));
                    toInsert.add(pa);
                }
                if (!toInsert.isEmpty()) {
                    insert toInsert;
                }
            }

            result.put('success', true);
            result.put('message', 'Payment request saved successfully');
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', e.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> markPaymentRequestStageComplete(
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
            String stageKey = resolvePaymentRequestStageCompletedValue(currentViewId);
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
                    asset.Stage_Completed__c = appendStageCompleted(asset.Stage_Completed__c, stageKey);
                    update asset;
                    if (areAllAssetsComplete(assetLineItemId, stageKey)) {
                        markLineItemComplete(assetLineItemId, stageKey);
                    }
                } else {
                    markLineItemComplete(assetLineItemId, stageKey);
                }

                result.put('isSuccess', true);
                result.put('applicationLineItemId', String.valueOf(assetLineItemId));
                return result;
            }

            markLineItemComplete(lineItemId, stageKey);
            result.put('isSuccess', true);
            result.put('applicationLineItemId', String.valueOf(lineItemId));
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> moveBackToPssStage(String dataJson) {
        Map<String, Object> result = new Map<String, Object>{ 'success' => false };
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
            Id recordId = (Id) payload.get('applicationId');
            Id lineItemId = resolveLineItemId(
                toId((String) payload.get('applicationLineItemId')),
                toId((String) payload.get('assetId'))
            );
            Id assetId = toId((String) payload.get('assetId'));

            Disbursement_Details__c dd = lineItemId != null ? queryDisbursement(lineItemId, assetId) : null;
            if (dd != null) {
                dd.Are_all_details_correct__c = String.valueOf(payload.get('areAllDetailsCorrect') ?? '');
                dd.Remarks__c = String.valueOf(payload.get('remarks') ?? '');
                update dd;
            }

            List<Application__c> apps = [
                SELECT Id, Stage__c
                FROM Application__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (apps.isEmpty()) {
                result.put('message', 'Application record not found.');
                return result;
            }
            apps[0].Stage__c = 'Post Sanction Sales';
            update apps[0];

            result.put('success', true);
            result.put('message', 'Stage moved back to Post Sanction');
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', e.getMessage());
        }
        return result;
    }

    // ── Private helpers ────────────────────────────────────────────────────
    private static Application_Line_Item__c queryLineItem(Id applicationId, Id lineItemId) {
        if (lineItemId != null) {
            List<Application_Line_Item__c> rows = [
                SELECT Id, First_EMI_Date__c, Second_EMI_Date__c,
                       CRM_IRR__c, EMI_Amount__c, Holiday_period__c, Loan_Amount__c
                FROM Application_Line_Item__c
                WHERE Id = :lineItemId AND Application__c = :applicationId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }
        List<Application_Line_Item__c> rows = [
            SELECT Id, First_EMI_Date__c, Second_EMI_Date__c,
                   CRM_IRR__c, EMI_Amount__c, Holiday_period__c, Loan_Amount__c
            FROM Application_Line_Item__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Disbursement_Details__c queryDisbursement(Id lineItemId, Id assetId) {
        if (lineItemId == null) {
            return null;
        }
        if (assetId != null) {
            List<Disbursement_Details__c> rows = [
                SELECT Id, Payment_Originated_From__c, Vehicle_Sold_By__c,
                       Business_Sourced_By__c, Business_Sourced_By__r.Name,
                       Business_Done_By__c, Business_Done_By__r.Name,
                       FI_Done_By__c, FI_Done_By__r.Name,
                       Collection_Executive__c, Do_Issuance_Mode__c,
                       Purchase_Document_Category__c, Fund_End_Use__c,
                       Vehicle_Registered_in_Name__c, Dealer_Payment__c,
                       Balance_Transfer_Amount_in_Rs__c, Payment_to_be_made_on__c,
                       DO_Issuance_Date__c, Do_To_be_authorized_by__c,
                       Original_Purchase_value_in_Rs__c, Original_purchase_date__c,
                       Are_all_details_correct__c, Remarks__c
                FROM Disbursement_Details__c
                WHERE Application_Line_Items__c = :lineItemId AND Asset__c = :assetId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }
        List<Disbursement_Details__c> rows = [
            SELECT Id, Payment_Originated_From__c, Vehicle_Sold_By__c,
                   Business_Sourced_By__c, Business_Sourced_By__r.Name,
                   Business_Done_By__c, Business_Done_By__r.Name,
                   FI_Done_By__c, FI_Done_By__r.Name,
                   Collection_Executive__c, Do_Issuance_Mode__c,
                   Purchase_Document_Category__c, Fund_End_Use__c,
                   Vehicle_Registered_in_Name__c, Dealer_Payment__c,
                   Balance_Transfer_Amount_in_Rs__c, Payment_to_be_made_on__c,
                   DO_Issuance_Date__c, Do_To_be_authorized_by__c,
                   Original_Purchase_value_in_Rs__c, Original_purchase_date__c,
                   Are_all_details_correct__c, Remarks__c
            FROM Disbursement_Details__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static List<Loan_Beneficiary__c> queryBeneficiaries(Id disbursementId) {
        if (disbursementId == null) {
            return new List<Loan_Beneficiary__c>();
        }
        return [
            SELECT Id, Beneficiary_Name__c, Account_Number__c, IFSC_Code__c, Amount__c
            FROM Loan_Beneficiary__c
            WHERE Disbursement_Details__c = :disbursementId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    private static List<Payment_Adjustment__c> queryAdjustments(Id disbursementId) {
        if (disbursementId == null) {
            return new List<Payment_Adjustment__c>();
        }
        return [
            SELECT Id, Deal_Number__c, Customer_Name__c, Customer_Code__c, Amount__c
            FROM Payment_Adjustment__c
            WHERE Disbursement_Details__c = :disbursementId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    private static Asset__c queryAsset(Id applicationId, Id assetId, Id lineItemId) {
        if (assetId != null) {
            List<Asset__c> rows = [
                SELECT Id, Vehicle_Type__c, Vehicle_Registration_number__c,
                       Engine_number__c, Chassis_number__c, Name_transferred__c,
                       Current_vehicle_owner__c, Lien_marked_to_bank__c,
                       Marked_on__c, RTA_taxes_remitted_upto__c, Now_lien_in_the_name_of__c
                FROM Asset__c
                WHERE Id = :assetId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }
        if (lineItemId != null) {
            List<Asset__c> rows = [
                SELECT Id, Vehicle_Type__c, Vehicle_Registration_number__c,
                       Engine_number__c, Chassis_number__c, Name_transferred__c,
                       Current_vehicle_owner__c, Lien_marked_to_bank__c,
                       Marked_on__c, RTA_taxes_remitted_upto__c, Now_lien_in_the_name_of__c
                FROM Asset__c
                WHERE Application_Line_Items__c = :lineItemId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }
        List<Asset__c> rows = [
            SELECT Id, Vehicle_Type__c, Vehicle_Registration_number__c,
                   Engine_number__c, Chassis_number__c, Name_transferred__c,
                   Current_vehicle_owner__c, Lien_marked_to_bank__c,
                   Marked_on__c, RTA_taxes_remitted_upto__c, Now_lien_in_the_name_of__c
            FROM Asset__c
            WHERE Applicant__r.Application__c = :applicationId
              AND Applicant__r.Applicant_Type__c = 'Borrower'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Id resolveLineItemId(Id lineItemId, Id assetId) {
        if (lineItemId != null || assetId == null) {
            return lineItemId;
        }
        List<Asset__c> rows = [
            SELECT Application_Line_Items__c
            FROM Asset__c
            WHERE Id = :assetId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Application_Line_Items__c;
    }

    private static String resolvePaymentRequestStageCompletedValue(String currentViewId) {
        if (PAYMENT_REQUEST_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
            return PAYMENT_REQUEST_OPS_STAGE;
        }
        return PAYMENT_REQUEST_PSS_STAGE;
    }

    private static void markLineItemComplete(Id lineItemId, String stageKey) {
        Application_Line_Item__c lineItem = [
            SELECT Id, Stage_Completed__c
            FROM Application_Line_Item__c
            WHERE Id = :lineItemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        lineItem.Stage_Completed__c = appendStageCompleted(lineItem.Stage_Completed__c, stageKey);
        update lineItem;
    }

    private static Boolean areAllAssetsComplete(Id lineItemId, String stageKey) {
        for (Asset__c asset : [
            SELECT Stage_Completed__c
            FROM Asset__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
        ]) {
            if (!hasStageCompleted(asset.Stage_Completed__c, stageKey)) {
                return false;
            }
        }
        return true;
    }

    private static Integer countAssetsOnLineItem(Id lineItemId) {
        return lineItemId == null ? 0 : [
            SELECT COUNT()
            FROM Asset__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
        ];
    }

    private static String appendStageCompleted(String currentStages, String stageName) {
        if (String.isBlank(stageName) || hasStageCompleted(currentStages, stageName)) {
            return currentStages;
        }
        return String.isBlank(currentStages) ? stageName.trim() : currentStages + ';' + stageName.trim();
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

    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static List<PicklistOption> getPicklistOptions(String objectName, String fieldName) {
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectName);
        if (sObjType == null) {
            return options;
        }
        Map<String, Schema.SObjectField> fields = sObjType.getDescribe().fields.getMap();
        if (!fields.containsKey(fieldName)) {
            return options;
        }
        for (Schema.PicklistEntry entry : fields.get(fieldName).getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static void setIfNotNull(SObject rec, String field, Object val) {
        if (val != null && String.isNotBlank(String.valueOf(val))) {
            rec.put(field, String.valueOf(val));
        }
    }

    private static void setIdIfNotNull(SObject rec, String field, Object val) {
        if (val != null && String.isNotBlank(String.valueOf(val))) {
            try { rec.put(field, (Id) String.valueOf(val)); } catch (Exception ex) {}
        }
    }

    private static void setDecimalIfNotNull(SObject rec, String field, Object val) {
        if (val != null && String.isNotBlank(String.valueOf(val))) {
            try { rec.put(field, Decimal.valueOf(String.valueOf(val))); } catch (Exception ex) {}
        }
    }

    private static void setDateIfNotNull(SObject rec, String field, Object val) {
        if (val != null && String.isNotBlank(String.valueOf(val))) {
            try { rec.put(field, Date.valueOf(String.valueOf(val))); } catch (Exception ex) {}
        }
    }
}