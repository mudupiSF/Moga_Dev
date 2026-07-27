/**
 * @description Test coverage for WheelsIhmController — load/save IHM page,
 *              document upload/delete, stage rollback, and Callable routing.
 */
@IsTest
private class WheelsIhmControllerTest {

    private class TestContext {
        Application__c           application;
        Applicant__c             borrower;
        Application_Line_Item__c lineItem;
    }

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c     = 'Post Sanction Sales',
            Sub_Stage__c = 'IHM'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c    = app.Id,
            Applicant_Type__c = 'Borrower'
        );
        insert borrower;

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = app.Id,
            Loan_Amount__c = 500000
        );
        insert lineItem;

        insert new Asset__c(
            Applicant__c    = borrower.Id,
            Vehicle_type__c = 'New'
        );

        insert new Margin_Money_OCR__c(
            Application_Line_Items__c              = lineItem.Id,
            Service_charges__c                     = 5000,
            Documentation_charges__c               = 1500,
            Stamping_charges__c                    = 800,
            Total_Pay_ins__c                       = 7300,
            Total_amount_to_be_paid_by_customer__c = 7300,
            Are_all_details_correct__c             = 'Yes',
            Remarks__c                             = 'Initial IHM setup'
        );

        insert new Document_CheckList__c(
            Applicant__c              = borrower.Id,
            Application__c            = app.Id,
            Application_Line_Items__c = lineItem.Id,
            Document_Type__c          = 'IHM Receipt',
            Is_Active__c              = true,
            Receipt_Number__c         = 'RCP-001',
            Receipt_Date__c           = Date.today(),
            Amount_As_Per_Receipt__c  = 5000,
            Payment_Receipt_Remarks__c = 'Test receipt'
        );
    }

    private static TestContext getContext() {
        Application__c app = [
            SELECT Id FROM Application__c ORDER BY CreatedDate DESC LIMIT 1
        ];
        Applicant__c borrower = [
            SELECT Id FROM Applicant__c
            WHERE Application__c = :app.Id AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        Application_Line_Item__c lineItem = [
            SELECT Id FROM Application_Line_Item__c
            WHERE Application__c = :app.Id
            LIMIT 1
        ];
        TestContext ctx = new TestContext();
        ctx.application = app;
        ctx.borrower    = borrower;
        ctx.lineItem    = lineItem;
        return ctx;
    }

    private static String jsonPayload(Map<String, Object> fields) {
        return JSON.serialize(fields);
    }

    // ── loadIHMPage ───────────────────────────────────────────────────────────

    @IsTest
    static void loadIHMPage_fromApplication_returnsIhmAndReceipts() {
        TestContext ctx = getContext();
        String payload = jsonPayload(new Map<String, Object>{ 'recordId' => ctx.application.Id });

        Test.startTest();
        Map<String, Object> result = WheelsIhmController.loadIHMPage(payload);
        Test.stopTest();

        Map<String, Object> ihmData = (Map<String, Object>) result.get('ihmData');
        System.assertNotEquals(null, ihmData, 'IHM amounts should be loaded.');
        System.assertEquals(5000, ihmData.get('serviceCharges'));

        List<Object> receipts = (List<Object>) result.get('receipts');
        System.assertEquals(1, receipts.size());
    }

    @IsTest
    static void loadIHMPage_fromApplicant_resolvesBorrowerReceipts() {
        TestContext ctx = getContext();
        String payload = jsonPayload(new Map<String, Object>{ 'recordId' => ctx.borrower.Id });

        Map<String, Object> result = WheelsIhmController.loadIHMPage(payload);
        List<Object> receipts = (List<Object>) result.get('receipts');
        System.assertEquals(1, receipts.size());
    }

    // ── saveIHMPage ───────────────────────────────────────────────────────────

   
    @IsTest
    static void saveIHMPage_upsertsIhmAndReceipts() {
        TestContext ctx = getContext();
        Margin_Money_OCR__c existingIhm = [
            SELECT Id FROM Margin_Money_OCR__c
            WHERE Application_Line_Items__c = :ctx.lineItem.Id
            LIMIT 1
        ];
        Document_CheckList__c existingReceipt = [
            SELECT Id FROM Document_CheckList__c
            WHERE Applicant__c = :ctx.borrower.Id AND Document_Type__c = 'IHM Receipt'
            LIMIT 1
        ];

        String payload = jsonPayload(new Map<String, Object>{
            'recordId'              => ctx.application.Id,
            'ihmId'                 => existingIhm.Id,
            'serviceCharges'        => 5500,
            'documentationCharges'  => 1600,
            'stampingCharges'       => 850,
            'totalPayIns'           => 7950,
            'totalAmountToBePaid'   => 7950,
            'doesCustomerNeedToPay' => 'No',
            'areAllDetailsCorrect'  => 'Yes',
            'remarks'               => 'Saved from test',
            'receipts'              => new List<Object>{
                new Map<String, Object>{
                    'documentId'  => existingReceipt.Id,
                    'receiptNo'   => 'RCP-001',
                    'receiptDate' => String.valueOf(Date.today()),
                    'amount'      => 5500,
                    'remarks'     => 'Updated receipt'
                },
                new Map<String, Object>{
                    'receiptNo'   => 'RCP-002',
                    'receiptDate' => String.valueOf(Date.today()),
                    'amount'      => 2450,
                    'remarks'     => 'Second receipt'
                }
            }
        });

        Test.startTest();
        Map<String, Object> result = WheelsIhmController.saveIHMPage(payload);
        Test.stopTest();

        String message = result.containsKey('message') && result.get('message') != null ? String.valueOf(result.get('message')) : 'No message';
        System.assertEquals(true, result.get('success'), message);
        System.assertEquals(existingIhm.Id, result.get('ihmId'));

        Margin_Money_OCR__c persisted = [
            SELECT Service_charges__c, Remarks__c
            FROM Margin_Money_OCR__c
            WHERE Id = :existingIhm.Id
        ];
        System.assertEquals(5500, persisted.Service_charges__c);
        System.assertEquals('Saved from test', persisted.Remarks__c);

        System.assertEquals(2, [
            SELECT COUNT() FROM Document_CheckList__c
            WHERE Applicant__c = :ctx.borrower.Id AND Document_Type__c = 'IHM Receipt'
        ]);
    }

    // ── createContentVersion / deleteDocumentAndContent ───────────────────────

    @IsTest
    static void createContentVersion_linksFileToReceipt() {
        TestContext ctx = getContext();
        Document_CheckList__c receipt = [
            SELECT Id FROM Document_CheckList__c
            WHERE Applicant__c = :ctx.borrower.Id
            LIMIT 1
        ];

        Test.startTest();
        WheelsIhmController.ContentVersionResult result = WheelsIhmController.createContentVersion(
            'Receipt.pdf',
            'Receipt.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('ihm-receipt-content')),
            receipt.Id
        );
        Test.stopTest();

        String message = result.message != null ? String.valueOf(result.message) : 'No message';
        System.assertEquals(true, result.isSuccess, message);
        System.assertNotEquals(null, result.contentDocumentId);
        System.assertNotEquals(null, [
            SELECT ContentVersionId__c FROM Document_CheckList__c WHERE Id = :receipt.Id
        ].ContentVersionId__c);
    }

    @IsTest
    static void deleteDocumentAndContent_clearsFileWithoutDeletingRow() {
        TestContext ctx = getContext();
        Document_CheckList__c receipt = [
            SELECT Id FROM Document_CheckList__c
            WHERE Applicant__c = :ctx.borrower.Id
            LIMIT 1
        ];
        WheelsIhmController.createContentVersion(
            'Temp.pdf', 'Temp.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('temp')),
            receipt.Id
        );

        Test.startTest();
        WheelsIhmController.DeleteResult result =
            WheelsIhmController.deleteDocumentAndContent(receipt.Id, false);
        Test.stopTest();

        String message = result.message != null ? String.valueOf(result.message) : 'No message';
        System.assertEquals(true, result.isSuccess, message);
        System.assertEquals(null, [
            SELECT ContentVersionId__c FROM Document_CheckList__c WHERE Id = :receipt.Id
        ].ContentVersionId__c);
    }

    @IsTest
    static void deleteDocumentAndContent_deleteRow_removesRecord() {
        TestContext ctx = getContext();
        Document_CheckList__c receipt = new Document_CheckList__c(
            Applicant__c              = ctx.borrower.Id,
            Application__c            = ctx.application.Id,
            Application_Line_Items__c = ctx.lineItem.Id,
            Document_Type__c          = 'IHM Receipt',
            Is_Active__c              = true,
            Receipt_Number__c         = 'RCP-DELETE'
        );
        insert receipt;

        Test.startTest();
        WheelsIhmController.DeleteResult result =
            WheelsIhmController.deleteDocumentAndContent(receipt.Id, true);
        Test.stopTest();

        String message = result.message != null ? String.valueOf(result.message) : 'No message';
        System.assertEquals(true, result.isSuccess, message);
        System.assertEquals(0, [SELECT COUNT() FROM Document_CheckList__c WHERE Id = :receipt.Id]);
    }

    @IsTest
    static void deleteDocumentAndContent_missingRecord_returnsMessage() {
        TestContext ctx = getContext();
        Document_CheckList__c receipt = [
            SELECT Id FROM Document_CheckList__c WHERE Applicant__c = :ctx.borrower.Id LIMIT 1
        ];
        Id receiptId = receipt.Id;
        delete receipt;

        WheelsIhmController.DeleteResult result =
            WheelsIhmController.deleteDocumentAndContent(receiptId, true);

        System.assertEquals(false, result.isSuccess);
        System.assertEquals('Record not found', result.message);
    }

    // ── moveBackToPssStage ────────────────────────────────────────────────────

    @IsTest
    static void moveBackToPssStage_updatesApplicationAndIhm() {
        TestContext ctx = getContext();
        String payload = jsonPayload(new Map<String, Object>{
            'applicationId'        => ctx.application.Id,
            'areAllDetailsCorrect' => 'No',
            'remarks'              => 'Sent back to PSS'
        });

        Test.startTest();
        Map<String, Object> result = WheelsIhmController.moveBackToPssStage(payload);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), String.valueOf(result.get('message')));
        System.assertEquals('Post Sanction Sales', [
            SELECT Stage__c FROM Application__c WHERE Id = :ctx.application.Id
        ].Stage__c);

        Margin_Money_OCR__c ihm = [
            SELECT Are_all_details_correct__c, Remarks__c
            FROM Margin_Money_OCR__c
            WHERE Application_Line_Items__c = :ctx.lineItem.Id
            LIMIT 1
        ];
        System.assertEquals('No', ihm.Are_all_details_correct__c);
        System.assertEquals('Sent back to PSS', ihm.Remarks__c);
    }

    // ── Callable routing ──────────────────────────────────────────────────────

    @IsTest
    static void callable_routesLoadSaveAndFileActions() {
        TestContext ctx = getContext();
        WheelsIhmController controller = new WheelsIhmController();

        Map<String, Object> loadResult = (Map<String, Object>) controller.call(
            'loadIHMPage',
            new Map<String, Object>{ 'recordId' => ctx.application.Id }
        );
        System.assertNotEquals(null, loadResult.get('ihmData'));

        Map<String, Object> saveResult = (Map<String, Object>) controller.call(
            'saveIHMPage',
            new Map<String, Object>{
                'recordId'       => ctx.application.Id,
                'serviceCharges' => 5100,
                'receipts'       => new List<Object>()
            }
        );
        String message = saveResult.containsKey('message') && saveResult.get('message') != null ? String.valueOf(saveResult.get('message')) : 'No message';
        System.assertEquals(true, saveResult.get('success'), message);
    }

    @IsTest
    static void callable_createContentVersion_linksFileToReceipt() {
        TestContext ctx = getContext();
        Document_CheckList__c receipt = [
            SELECT Id FROM Document_CheckList__c
            WHERE Applicant__c = :ctx.borrower.Id
            LIMIT 1
        ];
        WheelsIhmController controller = new WheelsIhmController();

        Test.startTest();
        Map<String, Object> result = (Map<String, Object>) controller.call(
            'createContentVersion',
            new Map<String, Object>{
                'title'             => 'Receipt.pdf',
                'pathOnClient'      => 'Receipt.pdf',
                'versionData'       => EncodingUtil.base64Encode(Blob.valueOf('ihm-receipt-content')),
                'documentRecordId'  => receipt.Id
            }
        );
        Test.stopTest();

        String message = result.containsKey('message') && result.get('message') != null
            ? String.valueOf(result.get('message')) : 'No message';
        System.assertEquals(true, result.get('isSuccess'), message);
        System.assertNotEquals(null, result.get('contentDocumentId'));
        System.assertNotEquals(null, [
            SELECT ContentVersionId__c FROM Document_CheckList__c WHERE Id = :receipt.Id
        ].ContentVersionId__c);
    }

    @IsTest
    static void callable_deleteDocumentAndContent_clearsFileWithoutDeletingRow() {
        TestContext ctx = getContext();
        Document_CheckList__c receipt = [
            SELECT Id FROM Document_CheckList__c
            WHERE Applicant__c = :ctx.borrower.Id
            LIMIT 1
        ];
        WheelsIhmController controller = new WheelsIhmController();

        Map<String, Object> uploadResult = (Map<String, Object>) controller.call(
            'createContentVersion',
            new Map<String, Object>{
                'title'            => 'Temp.pdf',
                'pathOnClient'     => 'Temp.pdf',
                'versionData'      => EncodingUtil.base64Encode(Blob.valueOf('temp')),
                'documentRecordId' => receipt.Id
            }
        );
        String message = uploadResult.containsKey('message') && uploadResult.get('message') != null ? String.valueOf(uploadResult.get('message')) : 'No message';
        System.assertEquals(true, uploadResult.get('isSuccess'), message);

        Test.startTest();
        Map<String, Object> result = (Map<String, Object>) controller.call(
            'deleteDocumentAndContent',
            new Map<String, Object>{
                'documentId'  => receipt.Id,
                'isDeleteRow' => false
            }
        );
        Test.stopTest();

        String message2 = result.containsKey('message') && result.get('message') != null ? String.valueOf(result.get('message')) : 'No message';
        System.assertEquals(true, result.get('isSuccess'), message2);
        System.assertEquals(null, [
            SELECT ContentVersionId__c FROM Document_CheckList__c WHERE Id = :receipt.Id
        ].ContentVersionId__c);
    }

    @IsTest
    static void callable_deleteDocumentAndContent_deleteRow_removesRecord() {
        TestContext ctx = getContext();
        Document_CheckList__c receipt = new Document_CheckList__c(
            Applicant__c              = ctx.borrower.Id,
            Application__c            = ctx.application.Id,
            Application_Line_Items__c = ctx.lineItem.Id,
            Document_Type__c          = 'IHM Receipt',
            Is_Active__c              = true,
            Receipt_Number__c         = 'RCP-CALLABLE-DELETE'
        );
        insert receipt;

        WheelsIhmController controller = new WheelsIhmController();

        Test.startTest();
        Map<String, Object> result = (Map<String, Object>) controller.call(
            'deleteDocumentAndContent',
            new Map<String, Object>{
                'documentId'  => receipt.Id,
                'isDeleteRow' => true
            }
        );
        Test.stopTest();

        String message = result.containsKey('message') && result.get('message') != null
            ? String.valueOf(result.get('message')) : 'No message';
        System.assertEquals(true, result.get('isSuccess'), message);
        System.assertEquals(0, [SELECT COUNT() FROM Document_CheckList__c WHERE Id = :receipt.Id]);
    }

}