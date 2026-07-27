@isTest
private class dynamicStageNavigatorControllerTest {

    @testSetup
    static void setupData() {
        Application__c app = new Application__c(
            Sub_Stage__c = 'Dedupe and Eligibility',
            Stage__c = 'QDE',
            Product__c = '4W'
        );
        insert app;

        insert new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            Applicant_Tab_Label__c = 'Borrower',
            Loan_Stage__c = 'Dedupe and Eligibility'
        );
    }

    private static Id applicationId() {
        return [SELECT Id FROM Application__c LIMIT 1].Id;
    }

    private static String stagePhrase(String stepName, String mainStageName) {
        return stepName.replaceAll('\\s+', '_') + '_' + mainStageName.replaceAll('\\s+', '_');
    }

    private static String applicantStagePhrase(String stepName, String mainStageName, String token) {
        return stagePhrase(stepName, mainStageName) + '_' + token;
    }

    private static void setApplicationStage(Id appId, String mainStage, String stepName) {
        Application__c app = new Application__c(
            Id = appId,
            Stage__c = mainStage,
            Sub_Stage__c = stepName
        );
        update app;
    }

    private static void createAssetForApplication(Id appId, String vehicleType) {
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = appId,
            Loan_Amount__c = 500000
        );
        insert lineItem;
        insert new Asset__c(
            Applicant__c = borrower.Id,
            Application_Line_Items__c = lineItem.Id,
            Vehicle_type__c = vehicleType
        );
    }

    @isTest
    static void softDeleteApplicant_requiresId() {
        Test.startTest();
        Map<String, Object> result = dynamicStageNavigatorController.softDeleteApplicant(null);
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
        System.assertEquals('applicantId is required.', result.get('message'));
    }

    @isTest
    static void softDeleteApplicant_marksInactive() {
        Id appId = applicationId();
        Applicant__c guarantor = new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Basic Details'
        );
        insert guarantor;

        Test.startTest();
        Map<String, Object> result = dynamicStageNavigatorController.softDeleteApplicant(guarantor.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), result.get('message'));
        guarantor = [
            SELECT In_Active_Applicant__c
            FROM Applicant__c
            WHERE Id = :guarantor.Id
        ];
        System.assertEquals(true, guarantor.In_Active_Applicant__c);
    }

    @isTest
    static void getInitialQdeStepForApplication_returnsQdeTarget() {
        Id appId = applicationId();

        Test.startTest();
        Map<String, String> step = dynamicStageNavigatorController.getInitialQdeStepForApplication(appId);
        Test.stopTest();

        System.assertEquals('QDE', step.get('targetMainStage'));
        System.assert(String.isNotBlank(step.get('targetStep')));
    }

    @isTest
    static void getMenuForPortfolio_buildsMenuForWheelsApp() {
        Id appId = applicationId();

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio('Wheels', appId);
        Test.stopTest();

        System.assertEquals(true, state.isSuccess, state.message);
        System.assert(state.menuItems != null && !state.menuItems.isEmpty());
    }

    @isTest
    static void getMenuForPortfolio_groupsMultipleGuarantorsOnApplicantStep() {
        Id appId = applicationId();
        Application__c app = [
            SELECT Id
            FROM Application__c
            WHERE Id = :appId
        ];
        app.Sub_Stage__c = 'KYC Details';
        update app;

        insert new List<Applicant__c>{
            new Applicant__c(
                Application__c = appId,
                Applicant_Type__c = 'Guarantor',
                Applicant_Tab_Label__c = 'G1',
                Loan_Stage__c = 'KYC Details',
                Current_Loan_Stage_Complete__c = 'KYC Details'
            ),
            new Applicant__c(
                Application__c = appId,
                Applicant_Type__c = 'Guarantor',
                Applicant_Tab_Label__c = 'G2',
                Loan_Stage__c = 'KYC Details',
                Current_Loan_Stage_Complete__c = 'KYC Details'
            )
        };

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio('Wheels', appId);
        Test.stopTest();

        System.assertEquals(true, state.isSuccess, state.message);
        System.assertEquals(
            true,
            menuContainsGroupedApplicants(state.menuItems),
            'Expected grouped guarantor menu item when 2+ guarantors share an applicant-based step'
        );
    }

    private static Boolean menuContainsGroupedApplicants(
            List<dynamicStageNavigatorController.NavigationMenuItem> items) {
        if (items == null) {
            return false;
        }
        for (dynamicStageNavigatorController.NavigationMenuItem item : items) {
            if (item.isGroupItem == true
                    && item.applicants != null
                    && item.applicants.size() >= 2) {
                return true;
            }
            if (item.subItems != null && menuContainsGroupedApplicants(item.subItems)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean menuContainsStepLabel(
            List<dynamicStageNavigatorController.NavigationMenuItem> items,
            String stepLabel) {
        if (items == null || String.isBlank(stepLabel)) {
            return false;
        }
        for (dynamicStageNavigatorController.NavigationMenuItem item : items) {
            if (stepLabel.equalsIgnoreCase(item.label) || stepLabel.equalsIgnoreCase(item.tab)) {
                return true;
            }
            if (item.subItems != null && menuContainsStepLabel(item.subItems, stepLabel)) {
                return true;
            }
        }
        return false;
    }

    @isTest
    static void getMenuForPortfolio_requiresApplicationId() {
        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio('Wheels', null);
        Test.stopTest();

        System.assertEquals(false, state.isSuccess);
        System.assertEquals('applicationId is required.', state.message);
    }

    @isTest
    static void getMenuForPortfolio_derivesPortfolioFromProduct() {
        Id appId = applicationId();

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio(null, appId);
        Test.stopTest();

        System.assertEquals(true, state.isSuccess, state.message);
        System.assert(state.menuItems != null && !state.menuItems.isEmpty());
    }

    @isTest
    static void getMenuForPortfolio_rejectsMissingPortfolio() {
        Application__c app = new Application__c(
            Stage__c = 'QDE',
            Sub_Stage__c = 'Basic Details'
        );
        insert app;

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio(null, app.Id);
        Test.stopTest();

        System.assertEquals(false, state.isSuccess);
        System.assert(state.message.contains('Portfolio could not be determined'));
    }

    @isTest
    static void getInitialQdeStepForApplication_nullApplicationId() {
        Test.startTest();
        Map<String, String> step =
            dynamicStageNavigatorController.getInitialQdeStepForApplication(null);
        Test.stopTest();

        System.assertEquals('Basic Details', step.get('targetStep'));
        System.assertEquals('QDE', step.get('targetMainStage'));
    }

    @isTest
    static void softDeleteApplicant_notFound() {
        String prefix = Applicant__c.SObjectType.getDescribe().getKeyPrefix();
        Id missingId = (Id) (prefix + '000000000001');

        Test.startTest();
        Map<String, Object> result = dynamicStageNavigatorController.softDeleteApplicant(missingId);
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
        System.assertEquals('Applicant not found.', result.get('message'));
    }

    @isTest
    static void testOverrideHandler_executeAndIsVisible() {
        Id appId = applicationId();
        Application__c app = [
            SELECT Id, Stage__c, Sub_Stage__c
            FROM Application__c
            WHERE Id = :appId
        ];
        Dynamic_Stage_Gate__mdt gate = new Dynamic_Stage_Gate__mdt(
            Steps_Sub_Menu_Name__c = 'Investigation Reports',
            Main_Stage_Name__c = 'Credit Processing',
            Forward_Main_Stage_Name__c = 'Credit Processing',
            Forward_Steps_Name__c = 'Exposure Analysis'
        );

        DynamicStageNavigatorTestOverride handler = new DynamicStageNavigatorTestOverride();
        DynamicStageNavigatorTestOverride.hideFromMenu = false;
        DynamicStageNavigatorTestOverride.executeSuccess = true;
        DynamicStageNavigatorTestOverride.targetStep = 'Exposure Analysis';
        DynamicStageNavigatorTestOverride.targetMainStage = 'Credit Processing';

        Test.startTest();
        Boolean visible = handler.isVisible(app, gate, 'Wheels');
        dynamicStageNavigatorController.StageNavigationResult result = handler.execute(
            appId,
            'Investigation_Reports_Credit_Processing',
            null,
            app,
            gate,
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(true, visible);
        System.assertEquals(true, result.isSuccess);
        System.assertEquals('Exposure Analysis', result.newStep);
        System.assertEquals('Credit Processing', result.newMainStage);

        DynamicStageNavigatorTestOverride.hideFromMenu = true;
        System.assertEquals(false, handler.isVisible(app, gate, 'Wheels'));

        DynamicStageNavigatorTestOverride.executeSuccess = false;
        dynamicStageNavigatorController.StageNavigationResult failure = handler.execute(
            appId,
            'Investigation_Reports_Credit_Processing',
            null,
            app,
            gate,
            'Wheels'
        );
        System.assertEquals(false, failure.isSuccess);
    }

    @isTest
    static void processNextStageRequest_requiresApplicationIdAndStagePhrase() {
        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult missingApp =
            dynamicStageNavigatorController.processNextStageRequest(null, 'Basic_Details_QDE', null);
        dynamicStageNavigatorController.StageNavigationResult missingPhrase =
            dynamicStageNavigatorController.processNextStageRequest(applicationId(), null, null);
        Test.stopTest();

        System.assertEquals(false, missingApp.isSuccess);
        System.assert(missingApp.message.contains('required'));
        System.assertEquals(false, missingPhrase.isSuccess);
    }

    @isTest
    static void processNextStageRequest_unknownStagePhrase() {
        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                applicationId(),
                'Unknown_Step_QDE',
                null
            );
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('No CMT record matched'));
    }

    @isTest
    static void processNextStageRequest_requiresApplicantTokenOnApplicantStep() {
        Id appId = applicationId();
        setApplicationStage(appId, 'QDE', 'Basic Details');

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                stagePhrase('Basic Details', 'QDE'),
                'Basic Details'
            );
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('Applicant token required'));
    }

    @isTest
    static void processNextStageRequest_advancesBasicDetailsBorrower() {
        Id appId = applicationId();
        setApplicationStage(appId, 'QDE', 'Basic Details');
        Applicant__c borrower = [
            SELECT Id, Loan_Stage__c, Current_Loan_Stage_Complete__c
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Loan_Stage__c = 'Basic Details';
        update borrower;

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                applicantStagePhrase('Basic Details', 'QDE', 'Borrower'),
                'Basic Details'
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertNotEquals(null, result.navigationState);
        System.assertEquals(true, result.navigationState.isSuccess, result.navigationState.message);

        borrower = [
            SELECT Current_Loan_Stage_Complete__c, Loan_Stage__c
            FROM Applicant__c
            WHERE Id = :borrower.Id
        ];
        System.assertEquals('Basic Details', borrower.Current_Loan_Stage_Complete__c);
    }

    @isTest
    static void processNextStageRequest_routesToNextApplicantOnBasicDetails() {
        Id appId = applicationId();
        setApplicationStage(appId, 'QDE', 'Basic Details');

        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Loan_Stage__c = 'Basic Details';
        update borrower;

        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Basic Details'
        );

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                applicantStagePhrase('Basic Details', 'QDE', 'Borrower'),
                'Basic Details'
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals(true, result.renderGuarantorScreen);
        System.assert(
            'G1'.equals(result.preferredApplicantTabLabel)
                || (result.navigationState != null
                    && 'G1'.equals(result.navigationState.preferredApplicantTabLabel)),
            'Expected routing hint for G1'
        );
    }

    @isTest
    static void processNextStageRequest_advancesNonApplicantInvestigationReports() {
        Id appId = applicationId();
        setApplicationStage(appId, 'Credit Processing', 'Investigation Reports');

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                stagePhrase('Investigation Reports', 'Credit Processing'),
                null
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Exposure Analysis', result.newStep);
        System.assertNotEquals(null, result.navigationState);
        System.assertEquals(true, result.navigationState.isSuccess, result.navigationState.message);

        Application__c app = [
            SELECT Sub_Stage__c, Stage__c
            FROM Application__c
            WHERE Id = :appId
        ];
        System.assertEquals('Exposure Analysis', app.Sub_Stage__c);
        System.assertEquals('Credit Processing', app.Stage__c);
    }

    @isTest
    static void processNextStageRequest_pinsBorrowerWhenLeavingLoanTermsWithGuarantor() {
        Id appId = applicationId();
        setApplicationStage(appId, 'DDE', 'Loan Terms');
        createAssetForApplication(appId, 'New');

        Applicant__c borrower = [
            SELECT Id, Loan_Stage__c
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Loan_Stage__c = 'Offer';
        update borrower;

        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Basic Details',
            Current_Loan_Stage_Complete__c = 'KYC Details',
            Customer_Code__c = 'GTEST001'
        );

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                stagePhrase('Loan Terms', 'DDE'),
                null
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Income and Banking Details', result.newStep);
        System.assertEquals(true, result.renderGuarantorScreen);
        System.assertEquals('Borrower', result.preferredApplicantTabLabel);
        System.assertNotEquals(null, result.navigationState, result.message);
        System.assertEquals('Borrower', result.navigationState.preferredApplicantTabLabel);
        System.assertEquals('Income and Banking Details', result.navigationState.preferredViewStepName);

        dynamicStageNavigatorController.NavigationMenuItem currentView =
            findCurrentViewItem(result.navigationState.menuItems);
        System.assertNotEquals(null, currentView, 'Expected a currentView menu item');
        System.assertEquals('Borrower', currentView.label,
            'Application-level NEXT should open Borrower, not a co-applicant');
    }

    @isTest
    static void processNextStageRequest_invokesAssetDetailsOverrideForNewVehicle() {
        Id appId = applicationId();
        setApplicationStage(appId, 'DDE', 'Asset Details');
        createAssetForApplication(appId, 'New');

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                stagePhrase('Asset Details', 'DDE'),
                null
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('Loan Terms', result.newStep);
        System.assertEquals('DDE', result.newMainStage);
    }

    @isTest
    static void processNextStageRequest_invokesDedupeOverrideForBorrower() {
        Id appId = applicationId();
        setApplicationStage(appId, 'QDE', 'Dedupe and Eligibility');
        Applicant__c borrower = [
            SELECT Id, Loan_Stage__c
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Loan_Stage__c = 'Dedupe and Eligibility';
        update borrower;

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                applicantStagePhrase('Dedupe and Eligibility', 'QDE', 'Borrower'),
                'Dedupe and Eligibility'
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertNotEquals(null, result.navigationState);
    }

    @isTest
    static void getMenuForPortfolio_hidesValuationForNewVehicle() {
        Id appId = applicationId();
        setApplicationStage(appId, 'DDE', 'Loan Terms');
        createAssetForApplication(appId, 'New');

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio('Wheels', appId);
        Test.stopTest();

        System.assertEquals(true, state.isSuccess, state.message);
        System.assertEquals(
            false,
            menuContainsStepLabel(state.menuItems, 'Valuation'),
            'Valuation should be hidden for New vehicle type'
        );
    }

    @isTest
    static void getMenuForPortfolio_indexesBorrowerWithoutTabLabel() {
        Id appId = applicationId();
        delete [SELECT Id FROM Applicant__c WHERE Application__c = :appId];
        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Borrower',
            Loan_Stage__c = 'Dedupe and Eligibility'
        );

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio('Wheels', appId);
        Test.stopTest();

        System.assertEquals(true, state.isSuccess, state.message);
        System.assert(state.menuItems != null && !state.menuItems.isEmpty());
    }

    @isTest
    static void getMenuForPortfolio_showsQueuedGuarantorOnKycStep() {
        Id appId = applicationId();
        setApplicationStage(appId, 'QDE', 'KYC Details');

        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Loan_Stage__c = 'KYC Details';
        borrower.Current_Loan_Stage_Complete__c = 'KYC Details';
        update borrower;

        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Basic Details',
            Current_Loan_Stage_Complete__c = 'Basic Details'
        );

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio('Wheels', appId);
        Test.stopTest();

        System.assertEquals(true, state.isSuccess, state.message);
        System.assert(
            menuContainsStepLabel(state.menuItems, 'KYC Details'),
            'KYC menu should include queued guarantor context'
        );
    }

    @isTest
    static void getMenuForPortfolio_returnsMessageWhenNoStagesForPortfolio() {
        Id appId = applicationId();

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.getMenuForPortfolio('NonExistentPortfolio', appId);
        Test.stopTest();

        System.assertEquals(true, state.isSuccess);
        System.assert(state.message.contains('No active stages found'));
    }

    @isTest
    static void buildNavStateWithApplicantAndStepHint_pinsApplicantAndStep() {
        Id appId = applicationId();

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.buildNavStateWithApplicantAndStepHint(
                appId, 'Borrower', 'Basic Details');
        Test.stopTest();

        System.assertEquals(true, state.isSuccess, state.message);
        System.assertEquals('Borrower', state.preferredApplicantTabLabel);
        System.assertEquals('Basic Details', state.preferredViewStepName);
    }

    private static dynamicStageNavigatorController.NavigationMenuItem findCurrentViewItem(
            List<dynamicStageNavigatorController.NavigationMenuItem> items) {
        if (items == null) {
            return null;
        }
        for (dynamicStageNavigatorController.NavigationMenuItem item : items) {
            if (item.currentView == true) {
                return item;
            }
            if (item.subItems != null) {
                dynamicStageNavigatorController.NavigationMenuItem found = findCurrentViewItem(item.subItems);
                if (found != null) {
                    return found;
                }
            }
        }
        return null;
    }

    @isTest
    static void processNextStageRequest_routesToGuarantorGroupGridOnCreditAssessment() {
        Id appId = applicationId();
        setApplicationStage(appId, 'Credit Processing', 'Credit Assessment');

        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Loan_Stage__c = 'Credit Assessment';
        update borrower;

        insert new List<Applicant__c>{
            new Applicant__c(
                Application__c = appId,
                Applicant_Type__c = 'Guarantor',
                Applicant_Tab_Label__c = 'G1',
                Loan_Stage__c = 'Credit Assessment',
                Current_Loan_Stage_Complete__c = 'Offer'
            ),
            new Applicant__c(
                Application__c = appId,
                Applicant_Type__c = 'Guarantor',
                Applicant_Tab_Label__c = 'G2',
                Loan_Stage__c = 'Credit Assessment',
                Current_Loan_Stage_Complete__c = 'Offer'
            )
        };

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                applicantStagePhrase('Credit Assessment', 'Credit Processing', 'Borrower'),
                'Credit Assessment'
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals(false, result.renderGuarantorScreen);
        System.assertNotEquals(null, result.navigationState, result.message);
        System.assertEquals(null, result.navigationState.preferredApplicantId,
            'Group grid routing must not set an applicant drill-down id');
        dynamicStageNavigatorController.NavigationMenuItem currentView =
            findCurrentViewItem(result.navigationState.menuItems);
        System.assertEquals(true, currentView != null && currentView.isGroupItem == true,
            'Expected currentView on grouped Guarantor menu item');
        System.assertEquals('Guarantor', currentView.label);
    }

    @isTest
    static void buildNavStateWithApplicantAndStepHint_skipsStepPinWhenStepIsBlank() {
        Id appId = applicationId();

        Test.startTest();
        dynamicStageNavigatorController.NavigationPanelState state =
            dynamicStageNavigatorController.buildNavStateWithApplicantAndStepHint(
                appId, 'Borrower', null);
        Test.stopTest();

        System.assertEquals(true, state.isSuccess, state.message);
        System.assertEquals('Borrower', state.preferredApplicantTabLabel);
    }

    @isTest
    static void processNextStageRequest_kycIndividualBeneficiaryKeepsApplicationOnDedupe() {
        Id appId = applicationId();
        setApplicationStage(appId, 'QDE', 'Dedupe and Eligibility');

        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Type__c = 'Non-Individual';
        borrower.Loan_Stage__c = 'Dedupe and Eligibility';
        borrower.Current_Loan_Stage_Complete__c = 'KYC Details';
        update borrower;

        Applicant__c beneficiary = new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Beneficiary',
            Applicant_Tab_Label__c = 'B1',
            Type__c = 'Individual',
            Loan_Stage__c = 'KYC Details'
        );
        insert beneficiary;

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                applicantStagePhrase('KYC Details', 'QDE', 'B1'),
                'KYC Details'
            );
        Test.stopTest();

        Application__c appAfter = [
            SELECT Sub_Stage__c
            FROM Application__c
            WHERE Id = :appId
        ];
        Applicant__c beneficiaryAfter = [
            SELECT Loan_Stage__c, Current_Loan_Stage_Complete__c
            FROM Applicant__c
            WHERE Id = :beneficiary.Id
        ];

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals(
            'Dedupe and Eligibility',
            appAfter.Sub_Stage__c,
            'Application stage must not regress when a late-added beneficiary routes to Occupation'
        );
        System.assertEquals('KYC Details', beneficiaryAfter.Current_Loan_Stage_Complete__c);
        System.assertEquals(
            'Occupation Details',
            beneficiaryAfter.Loan_Stage__c,
            'Beneficiary Loan_Stage__c should advance to Occupation Details'
        );
    }

    @isTest
    static void processNextStageRequest_occupationBeneficiaryAdvancesApplicantWhenAppOnDedupe() {
        Id appId = applicationId();
        setApplicationStage(appId, 'QDE', 'Dedupe and Eligibility');

        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Type__c = 'Non-Individual';
        borrower.Loan_Stage__c = 'Dedupe and Eligibility';
        borrower.Current_Loan_Stage_Complete__c = 'KYC Details';
        update borrower;

        Applicant__c beneficiary = new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Beneficiary',
            Applicant_Tab_Label__c = 'B1',
            Type__c = 'Individual',
            Loan_Stage__c = 'Occupation Details',
            Current_Loan_Stage_Complete__c = 'KYC Details'
        );
        insert beneficiary;

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                applicantStagePhrase('Occupation Details', 'QDE', 'B1'),
                'Occupation Details'
            );
        Test.stopTest();

        Application__c appAfter = [
            SELECT Sub_Stage__c
            FROM Application__c
            WHERE Id = :appId
        ];
        Applicant__c beneficiaryAfter = [
            SELECT Loan_Stage__c, Current_Loan_Stage_Complete__c
            FROM Applicant__c
            WHERE Id = :beneficiary.Id
        ];

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals(
            'Dedupe and Eligibility',
            appAfter.Sub_Stage__c,
            'Application must stay on Dedupe when beneficiary completes Occupation'
        );
        System.assertEquals(
            'Occupation Details',
            beneficiaryAfter.Current_Loan_Stage_Complete__c,
            'Beneficiary Current_Loan_Stage_Complete__c must reflect Occupation completion'
        );
        System.assertEquals(
            'Dedupe and Eligibility',
            beneficiaryAfter.Loan_Stage__c,
            'Beneficiary Loan_Stage__c should advance to Dedupe'
        );
    }

    @isTest
    static void processNextStageRequest_kycNonIndividualBorrowerSkipsOccupationToDedupe() {
        Id appId = applicationId();
        setApplicationStage(appId, 'QDE', 'KYC Details');

        Applicant__c borrower = [
            SELECT Id, Loan_Stage__c
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Type__c = 'Non-Individual';
        borrower.Loan_Stage__c = 'KYC Details';
        update borrower;

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result =
            dynamicStageNavigatorController.processNextStageRequest(
                appId,
                applicantStagePhrase('KYC Details', 'QDE', 'Borrower'),
                null
            );
        dynamicStageNavigatorController.NavigationPanelState menu =
            dynamicStageNavigatorController.getMenuForPortfolio('Wheels', appId);
        Test.stopTest();

        Application__c appAfter = [
            SELECT Sub_Stage__c
            FROM Application__c
            WHERE Id = :appId
        ];

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals(
            'Dedupe and Eligibility',
            appAfter.Sub_Stage__c,
            'NI borrower KYC Next should advance the application to Dedupe, not Occupation'
        );
        System.assertEquals(true, menu.isSuccess, menu.message);
        System.assertEquals(
            false,
            menuContainsStepLabel(menu.menuItems, 'Occupation Details'),
            'Occupation Details must stay hidden when only a Non-Individual borrower exists'
        );
    }
}