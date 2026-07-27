@IsTest
private class InvoiceControllerTest {

    private class TestContext {
        Application__c application;
        Applicant__c borrower;
        Application_Line_Item__c lineItem;
        Asset__c asset;
    }

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'Post Sanction Sales',
            Sub_Stage__c = 'Invoice',
            Product__c = '4W'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower'
        );
        insert borrower;

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = app.Id,
            Loan_Amount__c = 500000
        );
        insert lineItem;

        insert new Asset__c(
            Applicant__c = borrower.Id,
            Application_Line_Items__c = lineItem.Id,
            Make__c = 'Honda',
            Model__c = 'City',
            Variant__c = 'VX',
            Dealer_Sub_dealer_name__c = 'Test Dealer',
            Basic_Price__c = 900000,
            Ex_showroom_price__c = 950000,
            GST_Amount__c = 50000,
            Engine_number__c = 'ENG-001',
            Chassis_number__c = 'CHS-001'
        );
    }

    private static TestContext getContext() {
        TestContext ctx = new TestContext();
        ctx.application = [SELECT Id FROM Application__c ORDER BY CreatedDate DESC LIMIT 1];
        ctx.borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :ctx.application.Id
            AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        ctx.lineItem = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Application__c = :ctx.application.Id
            LIMIT 1
        ];
        ctx.asset = [
            SELECT Id
            FROM Asset__c
            WHERE Applicant__c = :ctx.borrower.Id
            LIMIT 1
        ];
        return ctx;
    }

    @IsTest
    static void getInvoiceData_requiresRecordId() {
        Map<String, Object> result = InvoiceController.getInvoiceData(null, null);
        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void getInvoiceData_invalidRecordId() {
        Map<String, Object> result = InvoiceController.getInvoiceData('not-an-id', null);
        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void getInvoiceData_loadsAssetAndPicklists() {
        TestContext ctx = getContext();

        Test.startTest();
        Map<String, Object> result = InvoiceController.getInvoiceData(
            ctx.application.Id,
            ctx.borrower.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
        Map<String, Object> details = (Map<String, Object>) result.get('invoiceDetails');
        System.assertEquals('Honda', details.get('make'));
        System.assertEquals('Test Dealer', details.get('dealerName'));
        System.assertNotEquals(null, result.get('picklists'));
        Map<String, Object> meta = (Map<String, Object>) result.get('meta');
        System.assertEquals(String.valueOf(ctx.asset.Id), meta.get('assetId'));
    }

    @IsTest
    static void saveInvoiceData_requiresRecordId() {
        Map<String, Object> result = InvoiceController.saveInvoiceData(null, null, '{}');
        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void saveInvoiceData_requiresPayload() {
        TestContext ctx = getContext();
        Map<String, Object> result = InvoiceController.saveInvoiceData(
            ctx.application.Id,
            ctx.borrower.Id,
            ''
        );
        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void saveInvoiceData_requiresAsset() {
        String payload =
            '{"invoiceSection":{"isInvoiceLegible":"Yes"},"invoiceDetails":{"taxInvoiceNo":"INV-1"}}';

        Map<String, Object> result = InvoiceController.saveInvoiceData(
            UserInfo.getUserId(),
            null,
            payload
        );

        System.assertEquals(false, result.get('isSuccess'));
        System.assert(
            String.valueOf(result.get('message')).contains('Asset'),
            String.valueOf(result.get('message'))
        );
    }

    @IsTest
    static void saveInvoiceData_insertsAndReloadsInvoiceDetails() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(
            new Map<String, Object>{
                'invoiceSection' => new Map<String, Object>{
                    'isInvoiceLegible' => 'Yes',
                    'invoiceRemarks' => 'Legible invoice'
                },
                'invoiceDetails' => new Map<String, Object>{
                    'typeOfInvoice' => 'Tax Invoice',
                    'taxInvoiceNo' => 'TAX-1001',
                    'taxInvoiceDate' => '2026-01-15',
                    'orpAsPerBank' => '980000',
                    'invoiceAmountInclDiscount' => '975000'
                }
            }
        );

        Test.startTest();
        Map<String, Object> saveResult = InvoiceController.saveInvoiceData(
            ctx.application.Id,
            ctx.borrower.Id,
            payload
        );
        Map<String, Object> loadResult = InvoiceController.getInvoiceData(
            ctx.application.Id,
            ctx.borrower.Id
        );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('isSuccess'), saveResult.get('message'));
        System.assertNotEquals(null, saveResult.get('invoiceDetailsId'));

        Map<String, Object> section = (Map<String, Object>) loadResult.get('invoiceSection');
        Map<String, Object> details = (Map<String, Object>) loadResult.get('invoiceDetails');
        System.assertEquals('Yes', section.get('isInvoiceLegible'));
        System.assertEquals('TAX-1001', details.get('taxInvoiceNo'));
        Map<String, Object> meta = (Map<String, Object>) loadResult.get('meta');
        System.assertEquals(true, meta.get('hasSavedInvoiceDetails'));
    }

    @IsTest
    static void saveInvoiceData_updatesExistingInvoiceRecord() {
        TestContext ctx = getContext();
        String firstPayload = JSON.serialize(
            new Map<String, Object>{
                'invoiceSection' => new Map<String, Object>{ 'isInvoiceLegible' => 'Yes' },
                'invoiceDetails' => new Map<String, Object>{ 'taxInvoiceNo' => 'INV-OLD' }
            }
        );
        String secondPayload = JSON.serialize(
            new Map<String, Object>{
                'invoiceSection' => new Map<String, Object>{ 'isInvoiceLegible' => 'No' },
                'invoiceDetails' => new Map<String, Object>{ 'taxInvoiceNo' => 'INV-NEW' }
            }
        );

        InvoiceController.saveInvoiceData(ctx.application.Id, ctx.borrower.Id, firstPayload);

        Test.startTest();
        Map<String, Object> saveResult = InvoiceController.saveInvoiceData(
            ctx.application.Id,
            ctx.borrower.Id,
            secondPayload
        );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('isSuccess'), saveResult.get('message'));
        List<Invoice_Details__c> rows = [
            SELECT Tax_Invoice_No__c, Is_Invoice_legible__c
            FROM Invoice_Details__c
            WHERE Asset_Details__c = :ctx.asset.Id
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals('INV-NEW', rows[0].Tax_Invoice_No__c);
        System.assertEquals('No', rows[0].Is_Invoice_legible__c);
    }

    @IsTest
    static void saveInvoiceData_syncsEngineAndAssetFieldsOnNext() {
        TestContext ctx = getContext();
        ctx.asset.Engine_number__c = null;
        ctx.asset.Chassis_number__c = null;
        ctx.asset.RTO_Road_Tax_New__c = null;
        ctx.asset.Other_charges__c = null;
        update ctx.asset;

        String payload = JSON.serialize(
            new Map<String, Object>{
                'invoiceSection' => new Map<String, Object>(),
                'invoiceDetails' => new Map<String, Object>{
                    'typeOfInvoice' => 'Tax Invoice',
                    'taxInvoiceNo' => 'TAX-SYNC',
                    'engineNo' => 'ENG-SAVE-1',
                    'chassisNo' => 'CHS-SAVE-1',
                    'rtoRoadTax' => '15000',
                    'otherCharges' => '5000'
                }
            }
        );

        Test.startTest();
        Map<String, Object> saveResult = InvoiceController.saveInvoiceData(
            ctx.application.Id,
            ctx.borrower.Id,
            payload
        );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('isSuccess'), saveResult.get('message'));

        Asset__c asset = [
            SELECT Engine_number__c, Chassis_number__c, RTO_Road_Tax_New__c, Other_charges__c
            FROM Asset__c
            WHERE Id = :ctx.asset.Id
        ];
        System.assertEquals('ENG-SAVE-1', asset.Engine_number__c);
        System.assertEquals('CHS-SAVE-1', asset.Chassis_number__c);
        System.assertEquals(15000, asset.RTO_Road_Tax_New__c);
        System.assertEquals(5000, asset.Other_charges__c);

        Invoice_Details__c invoice = [
            SELECT Engine_No__c
            FROM Invoice_Details__c
            WHERE Asset_Details__c = :ctx.asset.Id
            LIMIT 1
        ];
        System.assertEquals('ENG-SAVE-1', invoice.Engine_No__c);
    }
}