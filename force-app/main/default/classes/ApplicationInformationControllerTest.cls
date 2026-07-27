@IsTest
private class ApplicationInformationControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data
    // ─────────────────────────────────────────────────────────────────────────
    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c     = 'QDE',
            Sub_Stage__c = 'Basic Details',
            Product__c   = 'CV'
            //Application_Source__c = 'Direct',
            //Withdrawal_Reason__c  = 'Elapse of time'
        );
        insert app;

        Applicant__c applicant = new Applicant__c(
            Application__c        = app.Id,
            Applicant_Type__c     = 'Borrower',
            Applicant_Tab_Label__c = 'Borrower',
            Customer_First_Name__c = 'Test',
            Customer_Last_Name__c  = 'User'
        );
        insert applicant;

        insert new Asset__c(
            Applicant__c   = applicant.Id,
            Vehicle_type__c = 'Truck'
        );
    }

    private static Id appId() {
        return [SELECT Id FROM Application__c LIMIT 1].Id;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getApplicationInformation
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void getApplicationInformation_blankId_returnsEmptyWrapper() {
        Test.startTest();
        ApplicationInformationController.ApplicationInformationWrapper result =
            ApplicationInformationController.getApplicationInformation('');
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Wrapper must never be null');
        System.assertEquals(null, result.applicationNumber,
            'applicationNumber must be null for blank Id');
        System.assertNotEquals(null, result.withdrawalReasonOptions,
            'withdrawalReasonOptions list must be initialised');
        System.assertEquals(0, result.withdrawalReasonOptions.size(),
            'withdrawalReasonOptions must be empty for blank Id');
    }

    @IsTest
    static void getApplicationInformation_validId_returnsApplicationFields() {
        Id id = appId();

        Test.startTest();
        ApplicationInformationController.ApplicationInformationWrapper result =
            ApplicationInformationController.getApplicationInformation(id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Wrapper must not be null');
        //System.assertEquals('Direct', result.applicationSource,
        //    'applicationSource must match Application_Source__c');
        System.assertEquals('CV', result.productType,
            'productType must match Product__c');
        //System.assertEquals('Elapse of time', result.withdrawalReason,
        //    'withdrawalReason must match Withdrawal_Reason__c');
    }

    @IsTest
    static void getApplicationInformation_validId_populatesWithdrawalReasonOptions() {
        Test.startTest();
        ApplicationInformationController.ApplicationInformationWrapper result =
            ApplicationInformationController.getApplicationInformation(appId());
        Test.stopTest();

        System.assertNotEquals(null, result.withdrawalReasonOptions,
            'withdrawalReasonOptions must not be null');
        System.assert(result.withdrawalReasonOptions.size() > 0,
            'At least one active picklist option must be returned');

        ApplicationInformationController.PicklistOption first = result.withdrawalReasonOptions[0];
        System.assertNotEquals(null, first.label, 'Option label must not be null');
        System.assertNotEquals(null, first.value, 'Option value must not be null');
    }

    @IsTest
    static void getApplicationInformation_validId_returnsVehicleType() {
        Test.startTest();
        ApplicationInformationController.ApplicationInformationWrapper result =
            ApplicationInformationController.getApplicationInformation(appId());
        Test.stopTest();

        System.assertEquals('Truck', result.vehicleType,
            'vehicleType must be populated from the related Asset__c');
    }

    @IsTest
    static void getApplicationInformation_noAsset_vehicleTypeIsNull() {
        // Create a second application with no related asset
        Application__c app2 = new Application__c(
            Stage__c     = 'QDE',
            Sub_Stage__c = 'Basic Details',
            Product__c   = 'PL'
        );
        insert app2;

        Test.startTest();
        ApplicationInformationController.ApplicationInformationWrapper result =
            ApplicationInformationController.getApplicationInformation(app2.Id);
        Test.stopTest();

        System.assertEquals(null, result.vehicleType,
            'vehicleType must be null when no Asset__c exists for the application');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // withdrawApplication
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void withdrawApplication_blankId_throwsAuraHandledException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ApplicationInformationController.withdrawApplication('', 'Elapse of time');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('required') || String.isNotBlank(e.getMessage()),
                'Exception message must be descriptive');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException must be thrown for blank recordId');
    }

    @IsTest
    static void withdrawApplication_blankReason_throwsAuraHandledException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ApplicationInformationController.withdrawApplication(appId(), '');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(String.isNotBlank(e.getMessage()),
                'Exception message must not be blank');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException must be thrown for blank withdrawalReason');
    }

    @IsTest
    static void withdrawApplication_validInputs_updatesWithdrawalReason() {
        Id id = appId();
        String newReason = 'Customer withdrew the loan application';

        Test.startTest();
        ApplicationInformationController.withdrawApplication(id, newReason);
        Test.stopTest();

        Application__c updated = [SELECT Withdrawal_Reason__c FROM Application__c WHERE Id = :id];
        System.assertEquals(newReason, updated.Withdrawal_Reason__c,
            'Withdrawal_Reason__c must be updated to the supplied value');
    }

    @IsTest
    static void withdrawApplication_replacesExistingReason() {
        Id id = appId();

        // Application starts with 'Elapse of time' from @TestSetup
        ApplicationInformationController.withdrawApplication(id, 'Financial terms not agreed to');
        Application__c updated = [SELECT Withdrawal_Reason__c FROM Application__c WHERE Id = :id];

        System.assertEquals('Financial terms not agreed to', updated.Withdrawal_Reason__c,
            'Withdrawal_Reason__c must be overwritten when called a second time');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PicklistOption inner class
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void picklistOption_noArgConstructor_fieldsAreNull() {
        ApplicationInformationController.PicklistOption opt =
            new ApplicationInformationController.PicklistOption();

        System.assertEquals(null, opt.label, 'No-arg constructor: label must be null');
        System.assertEquals(null, opt.value, 'No-arg constructor: value must be null');
    }

    @IsTest
    static void picklistOption_labelValueConstructor_setsFields() {
        ApplicationInformationController.PicklistOption opt =
            new ApplicationInformationController.PicklistOption('My Label', 'my_value');

        System.assertEquals('My Label', opt.label, 'label must match constructor argument');
        System.assertEquals('my_value', opt.value,  'value must match constructor argument');
    }
}