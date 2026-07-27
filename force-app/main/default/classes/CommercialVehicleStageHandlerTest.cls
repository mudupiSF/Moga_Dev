@isTest
private class CommercialVehicleStageHandlerTest {

    @testSetup
    static void setupData() {
        insert new Application__c(
            Stage__c = 'QDE',
            Sub_Stage__c = 'Basic Details',
            Product__c = 'CV'
        );
    }

    private static Application__c applicationRecord() {
        return [
            SELECT Id, Stage__c, Sub_Stage__c
            FROM Application__c
            LIMIT 1
        ];
    }

    private static Dynamic_Stage_Gate__mdt basicDetailsGate() {
        return new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c = 'Basic Details',
            Main_Stage_Name__c = 'QDE',
            Forward_Main_Stage_Name__c = 'QDE',
            Forward_Steps_Name__c = 'KYC Details'
        );
    }

    private static Dynamic_Stage_Gate__mdt creditProcessingGate() {
        return new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c = 'Exposure Analysis',
            Main_Stage_Name__c = 'Credit Processing',
            Forward_Main_Stage_Name__c = 'Credit Processing',
            Forward_Steps_Name__c = 'Credit Assessment'
        );
    }

    @isTest
    static void execute_routesQdeBasicDetailsToExposureAnalysis() {
        Application__c app = applicationRecord();
        CommercialVehicleStageHandler handler = new CommercialVehicleStageHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            'Basic_Details_QDE',
            'Basic Details',
            app,
            basicDetailsGate(),
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Credit Processing', result.newMainStage);
        System.assertEquals('Exposure Analysis', result.newStep);
    }

    @isTest
    static void execute_returnsFailureWhenSubStageDoesNotMatch() {
        Application__c app = applicationRecord();
        app.Sub_Stage__c = 'KYC Details';
        update app;

        CommercialVehicleStageHandler handler = new CommercialVehicleStageHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            'KYC_Details_QDE',
            'KYC Details',
            app,
            basicDetailsGate(),
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('no routing rule matched'));
        System.assert(result.message.contains('KYC Details'));
    }

    @isTest
    static void execute_returnsFailureWhenMainStageDoesNotMatch() {
        Application__c app = applicationRecord();
        app.Stage__c = 'DDE';
        app.Sub_Stage__c = 'Basic Details';
        update app;

        CommercialVehicleStageHandler handler = new CommercialVehicleStageHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            'Basic_Details_DDE',
            'Basic Details',
            app,
            basicDetailsGate(),
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('no routing rule matched'));
        System.assert(result.message.contains('DDE'));
    }

    @isTest
    static void isVisible_returnsTrueWhenQdeGateAndAppOnQde() {
        Application__c app = applicationRecord();
        CommercialVehicleStageHandler handler = new CommercialVehicleStageHandler();

        Test.startTest();
        Boolean visible = handler.isVisible(app, basicDetailsGate(), 'Wheels');
        Test.stopTest();

        System.assertEquals(true, visible);
    }

    @isTest
    static void isVisible_returnsTrueWhenQdeGateAndAppPastQde() {
        Application__c app = applicationRecord();
        app.Stage__c = 'Credit Processing';
        app.Sub_Stage__c = 'Exposure Analysis';
        update app;

        CommercialVehicleStageHandler handler = new CommercialVehicleStageHandler();

        Test.startTest();
        Boolean visible = handler.isVisible(app, basicDetailsGate(), 'Wheels');
        Test.stopTest();

        System.assertEquals(true, visible);
    }

    @isTest
    static void isVisible_returnsFalseWhenQdeGateAndAppStageBlank() {
        Application__c app = new Application__c(
            Sub_Stage__c = 'Basic Details'
        );
        CommercialVehicleStageHandler handler = new CommercialVehicleStageHandler();

        Test.startTest();
        Boolean visible = handler.isVisible(app, basicDetailsGate(), 'Wheels');
        Test.stopTest();

        System.assertEquals(false, visible);
    }

    @isTest
    static void isVisible_returnsTrueForNonQdeMainStageGate() {
        Application__c app = applicationRecord();
        CommercialVehicleStageHandler handler = new CommercialVehicleStageHandler();

        Test.startTest();
        Boolean visible = handler.isVisible(app, creditProcessingGate(), 'Wheels');
        Test.stopTest();

        System.assertEquals(true, visible);
    }
}