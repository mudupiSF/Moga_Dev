@IsTest
private class MyDeviationHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Helper: minimal Application__c sObject (not inserted – handler never
    // performs DML or reads fields from the app record).
    // ─────────────────────────────────────────────────────────────────────────
    private static Application__c buildApp() {
        return new Application__c();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper: minimal Dynamic_Stage_Gate__mdt sObject (not inserted – CMT
    // records cannot be inserted in unit tests; the handler ignores it anyway).
    // ─────────────────────────────────────────────────────────────────────────
    private static Dynamic_Stage_Gate__mdt buildMdt() {
        return new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c    = 'Deviation',
            Main_Stage_Name__c        = 'Credit Processing',
            Forward_Steps_Name__c     = 'Exposure Analysis',
            Forward_Main_Stage_Name__c = 'Credit Processing'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Framework runtime resolution: Type.forName() must locate the class
    //    and the resulting instance must satisfy IStageOverride.
    //    This mirrors resolveOverrideInstance() in dynamicStageNavigatorController
    //    and catches any class-name mismatch stored in a CMT Override_Apex__c field.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testFrameworkCanResolveClassByName() {
        Type t = Type.forName('MyDeviationHandler');
        System.assertNotEquals(null, t,
            'Type.forName must resolve MyDeviationHandler – check the class is deployed and the name matches Override_Apex__c');

        Object obj = t.newInstance();
        System.assert(
            obj instanceof dynamicStageNavigatorController.IStageOverride,
            'MyDeviationHandler resolved via Type.forName must implement IStageOverride'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Happy-path: execute() returns the hardcoded navigation decision.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testExecuteReturnsExpectedNavigationResult() {
        MyDeviationHandler handler = new MyDeviationHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            handler.execute(
                null,
                'Deviation_Credit Processing',
                'Credit Processing',
                buildApp(),
                buildMdt(),
                'PersonalLoans'
            );
        Test.stopTest();

        System.assertNotEquals(null, result,
            'execute() must return a non-null StageNavigationResult');
        System.assertEquals(true, result.isSuccess,
            'isSuccess must be true');
        System.assertEquals('Exposure Analysis', result.newStep,
            'newStep must equal the hardcoded target step');
        System.assertEquals('Credit Processing', result.newMainStage,
            'newMainStage must equal the hardcoded main stage');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. execute() is deterministic regardless of which inputs are passed –
    //    verifies the handler does not throw when all optional params are null.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testExecuteWithNullInputsIsStable() {
        MyDeviationHandler handler = new MyDeviationHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            handler.execute(null, null, null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'execute() must not return null even when all arguments are null');
        System.assertEquals(true, result.isSuccess,
            'isSuccess must be true regardless of input');
        System.assertEquals('Exposure Analysis', result.newStep,
            'newStep must be Exposure Analysis regardless of input');
        System.assertEquals('Credit Processing', result.newMainStage,
            'newMainStage must be Credit Processing regardless of input');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. execute() called via the IStageOverride interface (as the framework
    //    does at runtime) produces the same result.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testExecuteViaInterfaceReference() {
        dynamicStageNavigatorController.IStageOverride handler =
            new MyDeviationHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            handler.execute(
                null,
                'Deviation_Credit Processing',
                'Credit Processing',
                buildApp(),
                buildMdt(),
                'Wheels'
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess,
            'Interface-typed call must succeed');
        System.assertEquals('Exposure Analysis', result.newStep,
            'newStep must be Exposure Analysis when called via IStageOverride');
        System.assertEquals('Credit Processing', result.newMainStage,
            'newMainStage must be Credit Processing when called via IStageOverride');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. isVisible() always returns true – this handler is a deviation router,
    //    not a visibility filter, so the step must never be hidden from the menu.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testIsVisibleAlwaysReturnsTrue() {
        MyDeviationHandler handler = new MyDeviationHandler();

        Test.startTest();
        Boolean visibleWithValues = handler.isVisible(buildApp(), buildMdt(), 'PersonalLoans');
        Boolean visibleWithNulls  = handler.isVisible(null, null, null);
        Test.stopTest();

        System.assertEquals(true, visibleWithValues,
            'isVisible must return true for valid inputs');
        System.assertEquals(true, visibleWithNulls,
            'isVisible must return true even when all arguments are null');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. The result's optional fields (message, preferredApplicantTabLabel,
    //    navigationState) are at their default / null state – the handler is
    //    intentionally minimal and must not set anything beyond isSuccess,
    //    newStep, and newMainStage.
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testOptionalResultFieldsAreNotSet() {
        MyDeviationHandler handler = new MyDeviationHandler();

        dynamicStageNavigatorController.StageNavigationResult result =
            handler.execute(null, null, null, buildApp(), buildMdt(), null);

        System.assert(String.isBlank(result.message),
            'message should be blank; handler does not set it');
        System.assertEquals(null, result.preferredApplicantTabLabel,
            'preferredApplicantTabLabel should remain null');
        System.assertEquals(null, result.navigationState,
            'navigationState should remain null; framework rebuilds it');
    }
}