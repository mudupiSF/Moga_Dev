/**
 * @description Controller for WheelsIhmPage LWC.
 * Two entry-points: loadIHMPage (load everything) and saveIHMPage (save everything).
 */
public with sharing class WheelsIhmController implements Callable {

    // ── Callable interface — routes via GenericPageLayoutController ───────
    public Object call(String action, Map<String, Object> args) {
        String dataJson = JSON.serialize(args);  // 'dataJson' not 'json' — Apex is case-insensitive; 'json' shadows JSON class
        if (action == 'loadIHMPage')     return loadIHMPage(dataJson);
        if (action == 'saveIHMPage')     return saveIHMPage(dataJson);
        if (action == 'createContentVersion') {
            ContentVersionResult r = createContentVersion(
                (String) args.get('title'),
                (String) args.get('pathOnClient'),
                (String) args.get('versionData'),
                (Id)     String.valueOf(args.get('documentRecordId'))
            );
            return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(r));
        }
        if (action == 'deleteDocumentAndContent') {
            Id      docId       = (Id) String.valueOf(args.get('documentId'));
            Boolean deleteRow   = args.get('isDeleteRow') != null ? (Boolean) args.get('isDeleteRow') : false;
            DeleteResult r = deleteDocumentAndContent(docId, deleteRow);
            return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(r));
        }
        if (action == 'moveBackToPssStage') {
            return moveBackToPssStage(dataJson);
        }
        throw new AuraHandledException('Unknown action: ' + action);
    }

    private static final String DOCUMENT_TYPE_IHM = 'IHM Receipt';
    private static final String IHM_PSS_STAGE = 'IHM_PSS';
    private static final String IHM_OPS_STAGE = 'IHM_OPS';
    private static final String IHM_OPS_VIEW_ID = 'Wheels_IHM_OPS';

    // ── LOAD ──────────────────────────────────────────────────────────────
    /**
     * Returns ihmData (from Margin_Money_OCR__c) and receipt rows
     * (from Document_CheckList__c) in one call.
     *
     * Response shape:
     * {
     *   "ihmData" : { "ihmId": "...", "serviceCharges": 5000, ... } | null,
     *   "receipts": [ { "documentId": "...", "receiptNo": "...", ... } ]
     * }
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> loadIHMPage(String dataJson) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
            Id recordId = (Id) data.get('recordId');
            IhmScope scope = resolveScope(
                recordId,
                toId((String) data.get('assetId')),
                toId((String) data.get('applicationLineItemId'))
            );

            result.put('ihmData', loadIHMAmounts(scope));
            result.put('receipts', loadReceipts(scope.applicantId, scope.assetId));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return result;
    }

    // ── SAVE ──────────────────────────────────────────────────────────────
    /**
     * Upserts Margin_Money_OCR__c and all Document_CheckList__c receipt rows
     * in one call. Returns ihmId and the saved documentId per row (for file upload).
     *
     * Input JSON:
     * {
     *   "recordId"    : "...",
     *   "ihmId"       : "opt",
     *   "serviceCharges": 5000, ...all IHM numeric/text fields...,
     *   "receipts"    : [
     *     { "rowIndex": 0, "documentId": "opt", "receiptNo": "...",
     *       "receiptDate": "YYYY-MM-DD", "amount": 1000, "remarks": "..." }
     *   ]
     * }
     */
    @AuraEnabled
    public static Map<String, Object> saveIHMPage(String dataJson) {
        Map<String, Object> result = new Map<String, Object>{ 'success' => false };
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
            Id recordId = (Id) data.get('recordId');
            String ihmIdStr = (String) data.get('ihmId');
            IhmScope scope = resolveScope(
                recordId,
                toId((String) data.get('assetId')),
                toId((String) data.get('applicationLineItemId'))
            );

            if (scope.lineItem == null) {
                result.put('message', 'No Application Line Item found for this application');
                return result;
            }

            // ── 1. Upsert Margin_Money_OCR__c ─────────────────────────────
            Margin_Money_OCR__c ihm = String.isNotBlank(ihmIdStr)
                ? new Margin_Money_OCR__c(Id = (Id) ihmIdStr)
                : new Margin_Money_OCR__c(
                    Application_Line_Items__c = scope.lineItem.Id,
                    Asset__c = scope.assetId
                );

            
            ihm.Service_charges__c                          = decVal(data.get('serviceCharges'));
            ihm.Trade_certificate_fee__c                    = decVal(data.get('tradeCertificate'));
            ihm.Documentation_charges__c                    = decVal(data.get('documentationCharges'));
            ihm.Due_date_shift_charges__c                   = decVal(data.get('dueDateShiftCharges'));
            ihm.Stamping_charges__c                         = decVal(data.get('stampingCharges'));
            ihm.Total_Pay_ins__c                            = decVal(data.get('totalPayIns'));
            ihm.Total_amount_to_be_paid_by_customer__c      = decVal(data.get('totalAmountToBePaid'));
            ihm.Total_amount_paid_to_bank__c                = decVal(data.get('totalAmountPaidToBank'));
            ihm.Total_amount_paid_to_dealer__c              = decVal(data.get('totalAmountPaidToDealer'));
            ihm.Customer_need_to_pay_additional_amount__c   = (String) data.get('doesCustomerNeedToPay');
            ihm.Additional_amount_to_be_paid__c             = decVal(data.get('additionalIhmAmount'));
            ihm.Remarks__c                                  = (String) data.get('remarks');
            ihm.Total_EMI_to_be_considered__c               = decVal(data.get('totalEmiToBeConsideredForIhm'));
            ihm.Valuation_charges__c                        = decVal(data.get('valuationCharge'));
            ihm.Valuation_Charges_Paid_By__c                = (String) data.get('valuationChargePaidBy');
            ihm.Margin_money_to_be_deducted_from_disburs__c = decVal(data.get('totalMarginMoneyToBeDeductedForIhm'));
            ihm.Are_all_details_correct__c                   = (String) data.get('areAllDetailsCorrect');
            upsert ihm;

            // ── 2. Upsert Document_CheckList__c receipt rows ───────────────
            List<Object> receipts = (List<Object>) data.get('receipts');
            List<Map<String, Object>> savedReceipts = new List<Map<String, Object>>();

            Id applicantId = scope.applicantId;
            Id assetId = scope.assetId;

            if (receipts != null) {
                for (Integer i = 0; i < receipts.size(); i++) {
                    Map<String, Object> receipt   = (Map<String, Object>) receipts[i];
                    String  receiptNo             = (String) receipt.get('receiptNo');
                    String  documentIdStr         = (String) receipt.get('documentId');
                    Boolean isExistingRow         = String.isNotBlank(documentIdStr);

                    // New row: delete duplicates by receipt number
                    if (!isExistingRow && String.isNotBlank(receiptNo) && applicantId != null) {
                        List<Document_CheckList__c> dupes;
                        if (assetId != null) {
                            dupes = [
                                SELECT Id FROM Document_CheckList__c
                                WHERE Applicant__c = :applicantId
                                  AND Receipt_Number__c = :receiptNo
                                  AND Document_Type__c = :DOCUMENT_TYPE_IHM
                                  AND Asset__c = :assetId
                            ];
                        } else {
                            dupes = [
                                SELECT Id FROM Document_CheckList__c
                                WHERE Applicant__c = :applicantId
                                  AND Receipt_Number__c = :receiptNo
                                  AND Document_Type__c = :DOCUMENT_TYPE_IHM
                            ];
                        }
                        if (!dupes.isEmpty()) {
                            delete dupes;
                        }
                    }

                    Document_CheckList__c doc = isExistingRow
                        ? new Document_CheckList__c(Id = (Id) documentIdStr)
                        : new Document_CheckList__c(
                            Name = 'IHM Receipt ' + receiptNo,
                            Document_Type__c = DOCUMENT_TYPE_IHM,
                            Is_Active__c = true,
                            Applicant__c = scope.applicantId,
                            Application__c = recordId,
                            Application_Line_Items__c = scope.lineItem.Id,
                            Asset__c = scope.assetId
                        );

                    doc.Receipt_Number__c          = receiptNo;
                    doc.Payment_Receipt_Remarks__c = (String) receipt.get('remarks');

                    String dateStr = (String) receipt.get('receiptDate');
                    if (String.isNotBlank(dateStr)) doc.Receipt_Date__c = Date.valueOf(dateStr);

                    Object amountObj = receipt.get('amount');
                    if (amountObj != null && String.isNotBlank(String.valueOf(amountObj))) {
                        doc.Amount_As_Per_Receipt__c = Decimal.valueOf(String.valueOf(amountObj));
                    }

                    upsert doc;

                    savedReceipts.add(new Map<String, Object>{
                        'rowIndex'   => i,
                        'documentId' => doc.Id
                    });
                }
            }

            result.put('success',  true);
            result.put('ihmId',    ihm.Id);
            result.put('receipts', savedReceipts);
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', e.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> markIhmStageComplete(
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
            String ihmStageKey = resolveIhmStageCompletedValue(currentViewId);
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
                        ihmStageKey
                    );
                    update asset;

                    if (areAllLineItemAssetsIhmComplete(assetLineItemId, ihmStageKey)) {
                        markLineItemIhmStageComplete(assetLineItemId, ihmStageKey);
                    }
                } else {
                    markLineItemIhmStageComplete(assetLineItemId, ihmStageKey);
                }

                result.put('isSuccess', true);
                result.put('applicationLineItemId', String.valueOf(assetLineItemId));
                return result;
            }

            markLineItemIhmStageComplete(lineItemId, ihmStageKey);

            result.put('isSuccess', true);
            result.put('applicationLineItemId', String.valueOf(lineItemId));
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }

        return result;
    }

    // ── FILE UPLOAD ────────────────────────────────────────────────────────
    @AuraEnabled
    public static ContentVersionResult createContentVersion(
        String title, String pathOnClient, String versionData, Id documentRecordId
    ) {
        ContentVersionResult result = new ContentVersionResult();
        try {
            ContentVersion cv = new ContentVersion(
                Title = title, PathOnClient = pathOnClient,
                VersionData = EncodingUtil.base64Decode(versionData), IsMajorVersion = true
            );
            insert cv;
            cv = [SELECT Id, ContentDocumentId, FileType FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            insert new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId, LinkedEntityId = documentRecordId,
                ShareType = 'V', Visibility = 'AllUsers'
            );
            update new Document_CheckList__c(Id = documentRecordId, ContentVersionId__c = cv.Id);
            result.isSuccess = true; result.contentDocumentId = cv.ContentDocumentId;
            result.contentVersionId = cv.Id; result.documentId = documentRecordId; result.fileType = cv.FileType;
        } catch (Exception e) { result.isSuccess = false; result.message = e.getMessage(); }
        return result;
    }

    // ── DELETE ─────────────────────────────────────────────────────────────
    @AuraEnabled
    public static DeleteResult deleteDocumentAndContent(Id documentId, Boolean isDeleteRow) {
        DeleteResult result = new DeleteResult();
        try {
            List<Document_CheckList__c> docs = [
                SELECT Id, ContentVersionId__c FROM Document_CheckList__c WHERE Id = :documentId LIMIT 1
            ];
            if (docs.isEmpty()) { result.isSuccess = false; result.message = 'Record not found'; return result; }
            Document_CheckList__c doc = docs[0];
            if (String.isNotBlank(doc.ContentVersionId__c)) {
                List<ContentVersion> cvs = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :doc.ContentVersionId__c LIMIT 1];
                if (!cvs.isEmpty()) delete new ContentDocument(Id = cvs[0].ContentDocumentId);
            }
            if (isDeleteRow) { delete doc; } else { doc.ContentVersionId__c = null; update doc; }
            result.isSuccess = true;
        } catch (Exception e) { result.isSuccess = false; result.message = e.getMessage(); }
        return result;
    }

    // ── PRIVATE ────────────────────────────────────────────────────────────
    private class IhmScope {
        Id applicantId;
        Id assetId;
        String vehicleType;
        Application_Line_Item__c lineItem;
    }

    private static IhmScope resolveScope(Id recordId, Id assetId, Id lineItemId) {
        IhmScope scope = new IhmScope();
        scope.applicantId = resolveApplicantId(recordId);
        scope.assetId = assetId;

        if (assetId != null) {
            List<Asset__c> assets = [
                SELECT Vehicle_type__c, Application_Line_Items__c
                FROM Asset__c
                WHERE Id = :assetId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!assets.isEmpty()) {
                scope.vehicleType = assets[0].Vehicle_type__c;
                if (assets[0].Application_Line_Items__c != null) {
                    lineItemId = assets[0].Application_Line_Items__c;
                }
            }
        }

        scope.lineItem = queryLineItem(recordId, lineItemId);

        if (scope.assetId == null && scope.lineItem != null) {
            List<Asset__c> assets = [
                SELECT Id, Vehicle_type__c
                FROM Asset__c
                WHERE Application_Line_Items__c = :scope.lineItem.Id
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!assets.isEmpty()) {
                scope.assetId = assets[0].Id;
                scope.vehicleType = assets[0].Vehicle_type__c;
            }
        }

        return scope;
    }

    private static Application_Line_Item__c queryLineItem(Id applicationId, Id lineItemId) {
        if (lineItemId != null) {
            List<Application_Line_Item__c> lineItems = [
                SELECT Id,
                       Service_charges__c,
                       Documentation_charges__c,
                       Trade_certificate__c,
                       Stamping_charges__c,
                       Loan_Amount__c
                FROM Application_Line_Item__c
                WHERE Id = :lineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return lineItems.isEmpty() ? null : lineItems[0];
        }

        if (applicationId == null) {
            return null;
        }

        List<Application_Line_Item__c> lineItems = [
            SELECT Id,
                   Service_charges__c,
                   Documentation_charges__c,
                   Trade_certificate__c,
                   Stamping_charges__c,
                   Loan_Amount__c
            FROM Application_Line_Item__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return lineItems.isEmpty() ? null : lineItems[0];
    }

    private static Margin_Money_OCR__c queryMarginMoney(Id lineItemId, Id assetId) {
        if (lineItemId == null) {
            return null;
        }

        List<Margin_Money_OCR__c> records;
        if (assetId != null) {
            records = [
                SELECT Id, Service_charges__c, Trade_certificate_fee__c,
                       Documentation_charges__c, Due_date_shift_charges__c,
                       Stamping_charges__c, Total_Pay_ins__c,
                       Total_amount_to_be_paid_by_customer__c, Total_amount_paid_to_bank__c,
                       Total_amount_paid_to_dealer__c, Customer_need_to_pay_additional_amount__c,
                       Additional_amount_to_be_paid__c, Remarks__c, Total_EMI_to_be_considered__c,
                       Valuation_charges__c, Valuation_Charges_Paid_By__c,
                       Margin_money_to_be_deducted_from_disburs__c,
                       Are_all_details_correct__c
                FROM Margin_Money_OCR__c
                WHERE Application_Line_Items__c = :lineItemId
                  AND Asset__c = :assetId
                LIMIT 1
            ];
        } else {
            records = [
                SELECT Id, Service_charges__c, Trade_certificate_fee__c,
                       Documentation_charges__c, Due_date_shift_charges__c,
                       Stamping_charges__c, Total_Pay_ins__c,
                       Total_amount_to_be_paid_by_customer__c, Total_amount_paid_to_bank__c,
                       Total_amount_paid_to_dealer__c, Customer_need_to_pay_additional_amount__c,
                       Additional_amount_to_be_paid__c, Remarks__c, Total_EMI_to_be_considered__c,
                       Valuation_charges__c, Valuation_Charges_Paid_By__c,
                       Margin_money_to_be_deducted_from_disburs__c,
                       Are_all_details_correct__c
                FROM Margin_Money_OCR__c
                WHERE Application_Line_Items__c = :lineItemId
                LIMIT 1
            ];
        }

        return records.isEmpty() ? null : records[0];
    }

    private static Map<String, Object> loadIHMAmounts(IhmScope scope) {
        Application_Line_Item__c ali = scope.lineItem;
        if (ali == null) {
            return null;
        }

        Margin_Money_OCR__c m = queryMarginMoney(ali.Id, scope.assetId);
        if (m == null) {
            m = new Margin_Money_OCR__c();
        }

        return new Map<String, Object>{
            'ihmId'                              => m.Id,
            'assetId'                            => scope.assetId,
            'applicationLineItemId'              => ali.Id,
            'serviceCharges'                     => m.Service_charges__c != null ? m.Service_charges__c : ali.Service_charges__c,
            'tradeCertificate'                   => m.Trade_certificate_fee__c != null ? m.Trade_certificate_fee__c : ali.Trade_certificate__c != null ? Decimal.valueOf(String.valueOf(ali.Trade_certificate__c)) : null,
            'documentationCharges'               => m.Documentation_charges__c != null ? m.Documentation_charges__c : ali.Documentation_charges__c != null ? Decimal.valueOf(String.valueOf(ali.Documentation_charges__c)) : null,
            'dueDateShiftCharges'                => m.Due_date_shift_charges__c,
            'stampingCharges'                    => m.Stamping_charges__c != null ? m.Stamping_charges__c : ali.Stamping_charges__c != null ? Decimal.valueOf(String.valueOf(ali.Stamping_charges__c)) : null,
            'totalPayIns'                        => m.Total_Pay_ins__c != null ? m.Total_Pay_ins__c : (ali.Service_charges__c != null ? Decimal.valueOf(String.valueOf(ali.Service_charges__c)) : null) + (ali.Trade_certificate__c != null ? Decimal.valueOf(String.valueOf(ali.Trade_certificate__c)) : 0) + (ali.Documentation_charges__c != null ? Decimal.valueOf(String.valueOf(ali.Documentation_charges__c)) : 0) + (ali.Stamping_charges__c != null ? Decimal.valueOf(String.valueOf(ali.Stamping_charges__c)) : 0) + (m.Due_date_shift_charges__c != null ? Decimal.valueOf(String.valueOf(m.Due_date_shift_charges__c)) : 0),
            'totalAmountToBePaid'                => m.Total_amount_to_be_paid_by_customer__c != null ? m.Total_amount_to_be_paid_by_customer__c : (ali.Service_charges__c != null ? Decimal.valueOf(String.valueOf(ali.Service_charges__c)) : null) + (ali.Trade_certificate__c != null ? Decimal.valueOf(String.valueOf(ali.Trade_certificate__c)) : 0) + (ali.Documentation_charges__c != null ? Decimal.valueOf(String.valueOf(ali.Documentation_charges__c)) : 0) + (ali.Stamping_charges__c != null ? Decimal.valueOf(String.valueOf(ali.Stamping_charges__c)) : 0) + (m.Due_date_shift_charges__c != null ? Decimal.valueOf(String.valueOf(m.Due_date_shift_charges__c)) : 0) + (ali.Loan_Amount__c != null ? Decimal.valueOf(String.valueOf(ali.Loan_Amount__c)) : 0),
            'totalAmountPaidToBank'              => m.Total_amount_paid_to_bank__c,
            'totalAmountPaidToDealer'            => m.Total_amount_paid_to_dealer__c,
            'doesCustomerNeedToPay'              => m.Customer_need_to_pay_additional_amount__c != null ? m.Customer_need_to_pay_additional_amount__c : 'No',
            'additionalIhmAmount'                => m.Additional_amount_to_be_paid__c,
            'remarks'                            => m.Remarks__c,
            'totalEmiToBeConsideredForIhm'       => m.Total_EMI_to_be_considered__c,
            'valuationCharge'                    => m.Valuation_charges__c != null ? m.Valuation_charges__c : ali.Loan_Amount__c != null ? Decimal.valueOf(String.valueOf(ali.Loan_Amount__c)) : null,
            'valuationChargePaidBy'              => m.Valuation_Charges_Paid_By__c,
            'totalMarginMoneyToBeDeductedForIhm' => m.Margin_money_to_be_deducted_from_disburs__c,
            'vehicleType'                        => scope.vehicleType,
            'areAllDetailsCorrect'               => m.Are_all_details_correct__c,
            'loanAmtSanctionedFexclFundInsu' => ali.Loan_Amount__c != null ? Decimal.valueOf(String.valueOf(ali.Loan_Amount__c)) : 0
        };
    }

    private static List<Map<String, Object>> loadReceipts(Id applicantId, Id assetId) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (applicantId == null) {
            return result;
        }

        List<Document_CheckList__c> docs;
        if (assetId != null) {
            docs = [
                SELECT Id, Receipt_Number__c, Receipt_Date__c, Amount_As_Per_Receipt__c,
                       Payment_Receipt_Remarks__c, ContentVersionId__c
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicantId
                  AND Document_Type__c = :DOCUMENT_TYPE_IHM
                  AND Is_Active__c = true
                  AND Asset__c = :assetId
                ORDER BY CreatedDate ASC
            ];
        } else {
            docs = [
                SELECT Id, Receipt_Number__c, Receipt_Date__c, Amount_As_Per_Receipt__c,
                       Payment_Receipt_Remarks__c, ContentVersionId__c
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicantId
                  AND Document_Type__c = :DOCUMENT_TYPE_IHM
                  AND Is_Active__c = true
                ORDER BY CreatedDate ASC
            ];
        }
        Set<Id> cvIds = new Set<Id>();
        for (Document_CheckList__c d : docs) {
            if (String.isNotBlank(d.ContentVersionId__c)) cvIds.add((Id) d.ContentVersionId__c);
        }
        Map<Id, ContentVersion> cvMap = new Map<Id, ContentVersion>();
        if (!cvIds.isEmpty()) {
            for (ContentVersion cv : [SELECT Id, ContentDocumentId, FileType FROM ContentVersion WHERE Id IN :cvIds])
                cvMap.put(cv.Id, cv);
        }
        for (Document_CheckList__c d : docs) {
            Map<String, Object> row = new Map<String, Object>{
                'documentId' => d.Id, 'receiptNo' => d.Receipt_Number__c,
                'receiptDate' => d.Receipt_Date__c != null ? String.valueOf(d.Receipt_Date__c) : '',
                'amount' => d.Amount_As_Per_Receipt__c != null ? d.Amount_As_Per_Receipt__c : 0,
                'remarks' => d.Payment_Receipt_Remarks__c,
                'isUploaded' => false, 'contentDocumentId' => '', 'fileType' => ''
            };
            if (String.isNotBlank(d.ContentVersionId__c)) {
                Id cvId = (Id) d.ContentVersionId__c;
                if (cvMap.containsKey(cvId)) {
                    ContentVersion cv = cvMap.get(cvId);
                    row.put('isUploaded', true); row.put('contentDocumentId', cv.ContentDocumentId); row.put('fileType', cv.FileType);
                }
            }
            result.add(row);
        }
        return result;
    }

    private static Id resolveApplicantId(Id recordId) {
        String sType = recordId.getSObjectType().getDescribe().getName();
        if (sType == 'Applicant__c') return recordId;
        if (sType == 'Application__c') {
            List<Applicant__c> aps = [SELECT Id FROM Applicant__c WHERE Application__c = :recordId AND Applicant_Type__c = 'Borrower' LIMIT 1];
            return aps.isEmpty() ? null : aps[0].Id;
        }
        return null;
    }

    private static Decimal decVal(Object raw) {
        if (raw == null) return null;
        String s = String.valueOf(raw).trim();
        if (String.isBlank(s)) return null;
        try { return Decimal.valueOf(s); } catch (Exception e) { return null; }
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

    private static String resolveIhmStageCompletedValue(String currentViewId) {
        if (IHM_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
            return IHM_OPS_STAGE;
        }
        return IHM_PSS_STAGE;
    }

    private static void markLineItemIhmStageComplete(Id lineItemId, String ihmStageKey) {
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
            ihmStageKey
        );
        update lineItem;
    }

    private static Boolean areAllLineItemAssetsIhmComplete(Id lineItemId, String ihmStageKey) {
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
            if (!hasStageCompleted(asset.Stage_Completed__c, ihmStageKey)) {
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

    @AuraEnabled
    public static Map<String, Object> moveBackToPssStage(String dataJson) {
        Map<String, Object> result = new Map<String, Object>{ 'success' => false };
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
            Id recordId = (Id) payload.get('applicationId');
            List<Application__c> apps = [
                SELECT Id, Stage__c, Sub_Stage__c
                FROM Application__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            String areAllDetailsCorrect = String.valueOf(payload.get('areAllDetailsCorrect') ?? '');
            String remarks = String.valueOf(payload.get('remarks') ?? '');
            IhmScope scope = resolveScope(
                recordId,
                toId((String) payload.get('assetId')),
                toId((String) payload.get('applicationLineItemId'))
            );
            Margin_Money_OCR__c ihmRecord = scope.lineItem == null
                ? null
                : queryMarginMoney(scope.lineItem.Id, scope.assetId);
            if (ihmRecord != null) {
                ihmRecord.Are_all_details_correct__c = areAllDetailsCorrect;
                ihmRecord.Remarks__c = remarks;
                update ihmRecord;
            }
            if (apps.isEmpty()) {
                result.put('message', 'Application record not found.');
                return result;
            }
            Application__c app = apps[0];
            app.Stage__c = 'Post Sanction Sales';
            update app;
            result.put('success', true);
            result.put('message', 'Stage moved back to Post Sanction');
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', e.getMessage());
        }
        return result;
    }   
    // ── Wrappers ───────────────────────────────────────────────────────────
    public class ContentVersionResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public Id      contentDocumentId;
        @AuraEnabled public Id      contentVersionId;
        @AuraEnabled public Id      documentId;
        @AuraEnabled public String  fileType;
        @AuraEnabled public String  message;
    }
    public class DeleteResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String  message;
    }
}