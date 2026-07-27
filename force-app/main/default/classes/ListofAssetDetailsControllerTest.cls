@IsTest
private class ListofAssetDetailsControllerTest {

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'Post Sanction Sales',
            Sub_Stage__c = 'Asset Details',
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
            Stage_Completed__c = 'Asset Details'
        );
        insert lineItem;

        insert new Asset__c(
            Applicant__c = borrower.Id,
            Application_Line_Items__c = lineItem.Id,
            Make__c = 'AUDI',
            Model__c = 'Q3',
            Variant__c = 'TDI',
            Vehicle_type__c = 'New',
            Dealer_Sub_dealer_name__c = 'Dealer A'
        );
    }

    private static Application__c application() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Asset__c asset() {
        return [SELECT Id, Application_Line_Items__c FROM Asset__c LIMIT 1];
    }

    @IsTest
    static void testGetApplicationAssets() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = ListofAssetDetailsController.getApplicationAssets(app.Id, null);
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testCreateApplicationAsset() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = ListofAssetDetailsController.createApplicationAsset(app.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testCloneNewVehicleAssets() {
        Asset__c sourceAsset = asset();

        Test.startTest();
        Map<String, Object> result = ListofAssetDetailsController.cloneApplicationAssets(
            null,
            2,
            sourceAsset.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testDeleteApplicationAsset() {
        Asset__c sourceAsset = asset();

        Test.startTest();
        Map<String, Object> result = ListofAssetDetailsController.deleteApplicationAsset(
            sourceAsset.Application_Line_Items__c,
            sourceAsset.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testNullApplicationIdValidation() {
        Test.startTest();
        Map<String, Object> result = ListofAssetDetailsController.getApplicationAssets(null, null);
        Test.stopTest();

        System.assertEquals('Application ID is required.', result.get('message'));
    }

    @IsTest
    static void testCloneUsedVehicleRejected() {
        Asset__c sourceAsset = asset();
        sourceAsset.Vehicle_type__c = 'Used';
        update sourceAsset;

        Test.startTest();
        Map<String, Object> result = ListofAssetDetailsController.cloneApplicationAssets(
            null,
            1,
            sourceAsset.Id
        );
        Test.stopTest();

        System.assertEquals('Cloning is only available for new vehicle assets.', result.get('message'));
    }

    @IsTest
    static void testDeleteAllAssetsOnLineItem() {
        Asset__c sourceAsset = asset();
        Id borrowerId = [SELECT Applicant__c FROM Asset__c WHERE Id = :sourceAsset.Id].Applicant__c;
        insert new Asset__c(
            Applicant__c = borrowerId,
            Application_Line_Items__c = sourceAsset.Application_Line_Items__c,
            Vehicle_type__c = 'New'
        );

        Test.startTest();
        Map<String, Object> result = ListofAssetDetailsController.deleteApplicationAsset(
            sourceAsset.Application_Line_Items__c,
            null
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testDeleteMissingLineItemAndCloneEmptyLineItem() {
        Application__c app = application();
        Application_Line_Item__c emptyLineItem = new Application_Line_Item__c(
            Application__c = app.Id
        );
        insert emptyLineItem;

        Test.startTest();
        Map<String, Object> deleteMissing = ListofAssetDetailsController.deleteApplicationAsset(
            (Id) (String.valueOf(Application_Line_Item__c.SObjectType.getDescribe().getKeyPrefix()) + '000000000AAA'),
            null
        );
        Map<String, Object> cloneEmpty = ListofAssetDetailsController.cloneApplicationAssets(
            emptyLineItem.Id,
            1,
            null
        );
        Test.stopTest();

        System.assertEquals('No asset found for this application line item.', cloneEmpty.get('message'));
    }

    @IsTest
    static void testCompletedStageStatusesAndCloneQuantityValidation() {
        Application__c app = application();
        Application_Line_Item__c lineItem = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Application__c = :app.Id
            LIMIT 1
        ];
        lineItem.Stage_Completed__c = 'Asset Details;Loan Terms;Offer';
        update lineItem;

        Test.startTest();
        Map<String, Object> assetsResult = ListofAssetDetailsController.getApplicationAssets(app.Id, null);
        Map<String, Object> invalidQuantity = ListofAssetDetailsController.cloneApplicationAssets(
            null,
            null,
            asset().Id
        );
        Test.stopTest();

        System.assertEquals(true, assetsResult.get('isSuccess'));
    }

    @IsTest
    static void testCloneByLineItemId() {
        Asset__c sourceAsset = asset();

        Test.startTest();
        Map<String, Object> result = ListofAssetDetailsController.cloneApplicationAssets(
            sourceAsset.Application_Line_Items__c,
            1,
            null
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testUsedRcRetentionFallbackAndRefinanceStatus() {
        Application__c app = application();
        Asset__c sourceAsset = asset();
        sourceAsset.Vehicle_type__c = 'Refinance';
        sourceAsset.Vehicle_Registration_number__c = 'HR11AA1111';
        sourceAsset.Make__c = 'TATA';
        sourceAsset.Model__c = 'Nexon';
        sourceAsset.Required_Total_Loan_Amount__c = 400000;
        update sourceAsset;

        insert new Viability_Check__c(Asset__c = sourceAsset.Id, Distance__c = 20);

        Test.startTest();
        Map<String, Object> assetsResult = ListofAssetDetailsController.getApplicationAssets(app.Id, null);
        Map<String, Object> secondCreate = ListofAssetDetailsController.createApplicationAsset(app.Id);
        Map<String, Object> deleteByAssetId = ListofAssetDetailsController.deleteApplicationAsset(
            null,
            sourceAsset.Id
        );
        Map<String, Object> missingClone = ListofAssetDetailsController.cloneApplicationAssets(
            null,
            1,
            (Id) (String.valueOf(Asset__c.SObjectType.getDescribe().getKeyPrefix()) + '000000000AAA')
        );
        Test.stopTest();

        System.assertEquals(true, assetsResult.get('isSuccess'));
    }

    @IsTest
    static void testCreateAssetWithoutBorrowerAndMissingApplication() {
        Application__c app = application();
        delete [SELECT Id FROM Applicant__c];

        Test.startTest();
        Map<String, Object> missingBorrower = ListofAssetDetailsController.createApplicationAsset(app.Id);
        Map<String, Object> missingApplication = ListofAssetDetailsController.createApplicationAsset(
            (Id) (String.valueOf(Application__c.SObjectType.getDescribe().getKeyPrefix()) + '000000000AAA')
        );
        Test.stopTest();

        System.assertEquals('Borrower applicant not found for this application.', missingBorrower.get('message'));
    }

    @IsTest
    static void testCreateAndDeleteValidationPaths() {
        Test.startTest();
        Map<String, Object> nullCreate = ListofAssetDetailsController.createApplicationAsset(null);
        Map<String, Object> missingDelete = ListofAssetDetailsController.deleteApplicationAsset(null, null);
        Test.stopTest();

        System.assertEquals('Application ID is required.', nullCreate.get('message'));
    }

    @IsTest
    static void testUsedAssetStatusAndEmptyLineItem() {
        Application__c app = application();
        Asset__c sourceAsset = asset();
        sourceAsset.Vehicle_type__c = 'Used';
        sourceAsset.Vehicle_Registration_number__c = 'HR99ZZ9999';
        sourceAsset.Make__c = 'TATA';
        sourceAsset.Model__c = 'Nexon';
        sourceAsset.Required_Total_Loan_Amount__c = 500000;
        update sourceAsset;

        insert new Viability_Check__c(Asset__c = sourceAsset.Id, Distance__c = 50);
        insert new Application_Line_Item__c(Application__c = app.Id);

        Test.startTest();
        Map<String, Object> assetsResult = ListofAssetDetailsController.getApplicationAssets(app.Id, null);
        Map<String, Object> invalidQuantity = ListofAssetDetailsController.cloneApplicationAssets(
            null,
            0,
            sourceAsset.Id
        );
        Test.stopTest();

        System.assertEquals(true, assetsResult.get('isSuccess'));
    }

    @IsTest
    static void testPaymentDisbursementStatusFromBeneficiaryDisbursal() {
        Application__c app = application();
        Application_Line_Item__c lineItem = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Application__c = :app.Id
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        Disbursement_Details__c disbursementDetails = new Disbursement_Details__c(
            Application_Line_Items__c = lineItem.Id,
            Payment_Originated_From__c = 'HUB',
            Payment_to_be_made_on__c = Date.today()
        );
        insert disbursementDetails;

        Loan_Beneficiary__c beneficiary = new Loan_Beneficiary__c(
            Application__c = app.Id,
            Disbursement_Details__c = disbursementDetails.Id,
            Beneficiary_Name__c = 'Dealer Payment',
            Type__c = 'Dealer',
            Account_Number__c = '1234567890',
            IFSC_Code__c = 'HDFC0000123',
            Amount__c = 100000
        );
        insert beneficiary;

        Test.startTest();
        Map<String, Object> beforePayment = ListofAssetDetailsController.getApplicationAssets(
            app.Id,
            'Wheels_Repayment_OPS'
        );
        insert new Beneficiary_Payment__c(
            Loan_Beneficiary__c = beneficiary.Id,
            Tranche_Disbursement_Amount__c = 100000
        );
        Map<String, Object> afterPayment = ListofAssetDetailsController.getApplicationAssets(
            app.Id,
            'Wheels_Repayment_OPS'
        );
        Test.stopTest();

        List<Object> beforeRows = (List<Object>) beforePayment.get('assets');
        List<Object> afterRows = (List<Object>) afterPayment.get('assets');
        Map<String, Object> beforeRow = (Map<String, Object>) beforeRows[0];
        Map<String, Object> afterRow = (Map<String, Object>) afterRows[0];

        System.assertEquals('IN_PROGRESS', beforeRow.get('paymentDisbursementStatus'));
        System.assertEquals('COMPLETED', afterRow.get('paymentDisbursementStatus'));

        List<Object> childAssets = (List<Object>) afterRow.get('childAssets');
        System.assert(!childAssets.isEmpty());
        Map<String, Object> firstChild = (Map<String, Object>) childAssets[0];
        System.assertEquals('COMPLETED', firstChild.get('paymentDisbursementStatus'));
    }
}