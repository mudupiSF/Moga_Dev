@IsTest
private class KYCDetailsStageNavigationHandlerTest {

    private static final String KYC_STAGE_PHRASE_BORROWER = 'KYC_Details_QDE_Borrower';
    private static final String KYC_STAGE_PHRASE_COBO1 = 'KYC_Details_QDE_CoBo1';

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'QDE',
            Sub_Stage__c = 'KYC Details',
            Product__c = '4W'
        );
        insert app;

        insert new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            Applicant_Tab_Label__c = 'Borrower',
            Type__c = 'Individual'
        );
    }

    private static Application__c applicationWithApplicants() {
        return [
            SELECT Id, Stage__c,
                (SELECT Id, Applicant_Tab_Label__c, Type__c, In_Active_Applicant__c, Is_Sub_Applicant__c
                 FROM Applicants__r)
            FROM Application__c
            LIMIT 1
        ];
    }

    private static Dynamic_Stage_Gate__mdt kycDetailsGate() {
        return new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c = 'KYC Details',
            Main_Stage_Name__c = 'QDE',
            Forward_Main_Stage_Name__c = 'QDE',
            Forward_Steps_Name__c = 'Occupation Details'
        );
    }

    private static Dynamic_Stage_Gate__mdt occupationDetailsGate() {
        return new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c = 'Occupation Details',
            Main_Stage_Name__c = 'QDE',
            Forward_Main_Stage_Name__c = 'QDE',
            Forward_Steps_Name__c = 'Dedupe and Eligibility'
        );
    }

    private static void updateBorrowerType(String applicantType) {
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Applicant_Tab_Label__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Type__c = applicantType;
        update borrower;
    }

    private static void insertCoBorrower(String applicantType) {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        insert new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Co-Borrower',
            Applicant_Tab_Label__c = 'CoBo1',
            Type__c = applicantType
        );
    }

    @IsTest
    static void execute_routesIndividualApplicantToOccupationDetails() {
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            KYC_STAGE_PHRASE_BORROWER,
            null,
            app,
            kycDetailsGate(),
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Occupation Details', result.newStep);
        System.assertEquals('QDE', result.newMainStage);
    }

    @IsTest
    static void execute_routesNonIndividualApplicantToDedupe() {
        updateBorrowerType('Non-Individual');
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            KYC_STAGE_PHRASE_BORROWER,
            null,
            app,
            kycDetailsGate(),
            'Wheels'
        );

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Dedupe and Eligibility', result.newStep);
        System.assertEquals('QDE', result.newMainStage);
    }

    @IsTest
    static void execute_usesCurrentApplicantTypeFromStagePhrase() {
        updateBorrowerType('Individual');
        insertCoBorrower('Non-Individual');
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            KYC_STAGE_PHRASE_COBO1,
            null,
            app,
            kycDetailsGate(),
            'Wheels'
        );

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Dedupe and Eligibility', result.newStep);
    }

    @IsTest
    static void execute_occupationDetailsRoutesToDedupe() {
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            'Occupation_Details_QDE_Borrower',
            null,
            app,
            occupationDetailsGate(),
            'Wheels'
        );

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Dedupe and Eligibility', result.newStep);
    }

    @IsTest
    static void execute_requiresStageMetadata() {
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            KYC_STAGE_PHRASE_BORROWER,
            null,
            app,
            null,
            'Wheels'
        );

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('metadata record is missing'));
    }

    @IsTest
    static void execute_unsupportedStageReturnsFailure() {
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();
        Dynamic_Stage_Gate__mdt unsupportedGate = new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c = 'Basic Details'
        );

        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            app.Id,
            KYC_STAGE_PHRASE_BORROWER,
            null,
            app,
            unsupportedGate,
            'Wheels'
        );

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('unsupported stage'));
    }

    @IsTest
    static void isVisible_showsKycDetails() {
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        System.assertEquals(true, handler.isVisible(app, kycDetailsGate(), 'Wheels'));
    }

    @IsTest
    static void isVisible_hidesOccupationDetailsWhenAllApplicantsAreNonIndividual() {
        updateBorrowerType('Non-Individual');
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        System.assertEquals(false, handler.isVisible(app, occupationDetailsGate(), 'Wheels'));
    }

    @IsTest
    static void isVisible_hidesOccupationDetailsWhenNiBorrowerHasIndividualSubApplicants() {
        updateBorrowerType('Non-Individual');
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Applicant_Tab_Label__c = 'Borrower'
            LIMIT 1
        ];
        insert new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Co-Borrower',
            Applicant_Tab_Label__c = 'D1',
            Type__c = 'Individual',
            Parent_Applicant__c = borrower.Id,
            Is_Sub_Applicant__c = true
        );

        Application__c appWithApplicants = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        System.assertEquals(false, handler.isVisible(appWithApplicants, occupationDetailsGate(), 'Wheels'));
    }

    @IsTest
    static void isVisible_showsOccupationDetailsWhenTopLevelIndividualExists() {
        updateBorrowerType('Non-Individual');
        insertCoBorrower('Individual');
        Application__c app = applicationWithApplicants();
        KYCDetailsStageNavigationHandler handler = new KYCDetailsStageNavigationHandler();

        System.assertEquals(true, handler.isVisible(app, occupationDetailsGate(), 'Wheels'));
    }
}