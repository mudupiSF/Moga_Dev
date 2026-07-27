@isTest
private class CustomerDedupeNavigationOverrideTest {

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

    private static Dynamic_Stage_Gate__mdt dedupeGate() {
        List<Dynamic_Stage_Gate__mdt> gates = [
            SELECT DeveloperName, Forward_Steps_Name__c, Forward_Main_Stage_Name__c,
                   Main_Stage_Name__c, Steps_Sub_Menu_Name__c
            FROM Dynamic_Stage_Gate__mdt
            WHERE DeveloperName = 'Wheels_Dedupe_and_Eligibility'
            LIMIT 1
        ];
        return gates.isEmpty() ? null : gates[0];
    }

    @isTest
    static void execute_advancesWhenNoMoreApplicantSlots() {
        Dynamic_Stage_Gate__mdt gate = dedupeGate();
        if (gate == null) {
            return;
        }

        Application__c app = [SELECT Id, Stage__c FROM Application__c LIMIT 1];
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Customer_Code__c = 'CIF-BORROWER';
        borrower.Check_Eligibility_Message__c = 'Check Eligibility Success';
        borrower.Current_Loan_Stage_Complete__c = 'Dedupe and Eligibility';
        update borrower;

        Integer maxGuarantors = CustomerDedupeController.getMaxGuarantors();
        List<Applicant__c> guarantors = new List<Applicant__c>();
        for (Integer i = 1; i <= maxGuarantors; i++) {
            guarantors.add(new Applicant__c(
                Application__c = app.Id,
                Applicant_Type__c = 'Guarantor',
                Applicant_Tab_Label__c = 'G' + i,
                Loan_Stage__c = 'Dedupe and Eligibility',
                Current_Loan_Stage_Complete__c = 'Dedupe and Eligibility',
                Customer_Code__c = 'CIF-G' + i
            ));
        }
        insert guarantors;

        System.assertEquals(
            false,
            CustomerDedupeController.canAddMoreApplicantsForApplication(app.Id),
            'Guarantor capacity should be exhausted'
        );

        CustomerDedupeNavigationOverride nav = new CustomerDedupeNavigationOverride();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = nav.execute(
            app.Id,
            'QDE->Dedupe and Eligibility',
            'Dedupe and Eligibility',
            app,
            gate,
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals(
            gate.Forward_Steps_Name__c,
            result.newStep,
            'Should forward when add capacity is exhausted for this product'
        );
    }

    @isTest
    static void execute_routesPendingGuarantorToQde() {
        Dynamic_Stage_Gate__mdt gate = dedupeGate();
        if (gate == null) {
            return;
        }

        Application__c app = [SELECT Id, Stage__c FROM Application__c LIMIT 1];
        insert new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Basic Details',
            Current_Loan_Stage_Complete__c = 'Basic Details'
        );

        CustomerDedupeNavigationOverride nav = new CustomerDedupeNavigationOverride();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = nav.execute(
            app.Id,
            'QDE->Dedupe and Eligibility',
            'Dedupe and Eligibility',
            app,
            gate,
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals('G1', result.preferredApplicantTabLabel);
        System.assertNotEquals(gate.Forward_Steps_Name__c, result.newStep);
    }

    @isTest
    static void execute_forwardsWhenBorrowerDedupeJourneyComplete() {
        Dynamic_Stage_Gate__mdt gate = dedupeGate();
        if (gate == null) {
            return;
        }

        Application__c app = [SELECT Id, Stage__c FROM Application__c LIMIT 1];
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Customer_Code__c = 'CIF-BORROWER-01';
        borrower.Check_Eligibility_Message__c = 'Check Eligibility Success';
        borrower.Current_Loan_Stage_Complete__c = 'Dedupe and Eligibility';
        update borrower;

        CustomerDedupeNavigationOverride nav = new CustomerDedupeNavigationOverride();

        Test.startTest();
        dynamicStageNavigatorController.StageNavigationResult result = nav.execute(
            app.Id,
            'QDE->Dedupe and Eligibility',
            'Dedupe and Eligibility',
            app,
            gate,
            'Wheels'
        );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, result.message);
        System.assertEquals(gate.Forward_Steps_Name__c, result.newStep);
    }

    @isTest
    static void isVisible_returnsTrue() {
        Application__c app = [SELECT Id, Stage__c FROM Application__c LIMIT 1];
        CustomerDedupeNavigationOverride nav = new CustomerDedupeNavigationOverride();
        System.assertEquals(true, nav.isVisible(app, dedupeGate(), 'Wheels'));
    }
}