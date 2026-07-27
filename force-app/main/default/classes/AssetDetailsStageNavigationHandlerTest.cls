@IsTest
private class AssetDetailsStageNavigationHandlerTest {

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
            Loan_Amount__c = 500000
        );
        insert lineItem;

        insert new Asset__c(
            Applicant__c = borrower.Id,
            Application_Line_Items__c = lineItem.Id,
            Vehicle_type__c = 'New'
        );
    }

    private static Application__c applicationRecord() {
        return [SELECT Id, Stage__c FROM Application__c LIMIT 1];
    }

    private static Dynamic_Stage_Gate__mdt assetDetailsGate() {
        return new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c = 'Asset Details',
            Main_Stage_Name__c = 'Post Sanction Sales',
            Forward_Main_Stage_Name__c = 'Post Sanction Sales',
            Forward_Steps_Name__c = 'Loan Terms'
        );
    }

    private static Dynamic_Stage_Gate__mdt valuationGate() {
        return new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c = 'Valuation',
            Main_Stage_Name__c = 'Post Sanction Sales',
            Forward_Main_Stage_Name__c = 'Post Sanction Sales',
            Forward_Steps_Name__c = 'Loan Terms'
        );
    }

    private static void updateVehicleType(String vehicleType) {
        Asset__c asset = [SELECT Id FROM Asset__c LIMIT 1];
        asset.Vehicle_type__c = vehicleType;
        update asset;
    }

    @IsTest
    static void execute_assetDetailsRoutesNewVehicleToLoanTerms() {
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            null,
            null,
            app,
            assetDetailsGate(),
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Loan Terms', result.newStep);
    }

    @IsTest
    static void execute_assetDetailsRoutesUsedVehicleToValuation() {
        updateVehicleType('Used');
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            null,
            null,
            app,
            assetDetailsGate(),
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Valuation', result.newStep);
    }

    @IsTest
    static void execute_assetDetailsRoutesRefinanceVehicleToValuation() {
        updateVehicleType('Refinance');
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            null,
            null,
            app,
            assetDetailsGate(),
            'Wheels'
        );

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Valuation', result.newStep);
    }

    @IsTest
    static void execute_valuationAdvancesUsedVehicleToLoanTerms() {
        updateVehicleType('Used');
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            null,
            null,
            app,
            valuationGate(),
            'Wheels'
        );

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Loan Terms', result.newStep);
    }

    @IsTest
    static void execute_valuationBlockedForNewVehicle() {
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            null,
            null,
            app,
            valuationGate(),
            'Wheels'
        );

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('not applicable'));
    }

    @IsTest
    static void execute_requiresStageMetadata() {
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            null,
            null,
            app,
            null,
            'Wheels'
        );

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('metadata record is missing'));
    }

    @IsTest
    static void isVisible_hidesValuationForNewVehicle() {
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        System.assertEquals(false, handler.isVisible(app, valuationGate(), 'Wheels'));
    }

    @IsTest
    static void isVisible_showsValuationForUsedVehicle() {
        updateVehicleType('Used');
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        System.assertEquals(true, handler.isVisible(app, valuationGate(), 'Wheels'));
    }

    @IsTest
    static void isVisible_returnsTrueForNonValuationSteps() {
        Application__c app = applicationRecord();
        AssetDetailsStageNavigationHandler handler = new AssetDetailsStageNavigationHandler();

        System.assertEquals(true, handler.isVisible(app, assetDetailsGate(), 'Wheels'));
    }
}