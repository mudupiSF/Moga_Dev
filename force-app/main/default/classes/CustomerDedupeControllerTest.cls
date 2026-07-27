@isTest
private class CustomerDedupeControllerTest {

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

    private static Id borrowerId() {
        return [
            SELECT Id
            FROM Applicant__c
            WHERE Applicant_Type__c = 'Borrower'
            LIMIT 1
        ].Id;
    }

    @isTest
    static void getPageData_returnsMatchesAndFlags() {
        Id appId = applicationId();
        Id borrower = borrowerId();

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> args = new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => borrower
        };

        Test.startTest();
        Object raw = controller.call('getPageData', args);
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) raw;
        System.assertEquals(true, result.get('isSuccess'), 'Page data should load');
        System.assertNotEquals(null, result.get('matches'), 'Matches should be returned');
        System.assertEquals(true, result.get('isBorrowerScreen'), 'Current applicant is borrower');
    }

    @isTest
    static void markValid_setsEtbCustomerCode() {
        Id appId = applicationId();
        Id borrower = borrowerId();
        String cifId = 'CIF-TEST-001';

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> args = new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => borrower,
            'cifId' => cifId
        };

        Test.startTest();
        Map<String, Object> result = (Map<String, Object>) controller.call('markMatchAsValid', args);
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), result.get('message'));
        Applicant__c updated = [
            SELECT Customer_Code__c, Relationship_with_Bank__c
            FROM Applicant__c
            WHERE Id = :borrower
        ];
        System.assertEquals(cifId, updated.Customer_Code__c);
        System.assertEquals('ETB', updated.Relationship_with_Bank__c);
    }

    @isTest
    static void markInvalid_generatesNtbCode() {
        Id appId = applicationId();
        Id borrower = borrowerId();

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> args = new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => borrower,
            'cifId' => 'CIF-REJECTED'
        };

        Test.startTest();
        Map<String, Object> result = (Map<String, Object>) controller.call('markMatchAsInvalid', args);
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), result.get('message'));
        Applicant__c updated = [
            SELECT Customer_Code__c, Invalid_Customer_Code__c, Relationship_with_Bank__c
            FROM Applicant__c
            WHERE Id = :borrower
        ];
        System.assertEquals('NTB', updated.Relationship_with_Bank__c);
        System.assertEquals('CIF-REJECTED', updated.Invalid_Customer_Code__c);
        System.assert(String.isNotBlank(updated.Customer_Code__c), 'NTB code should be generated');
    }

    @isTest
    static void canAddMoreApplicantsForApplication_defaultsTrueForNewApp() {
        Id appId = applicationId();

        Test.startTest();
        Boolean canAdd = CustomerDedupeController.canAddMoreApplicantsForApplication(appId);
        Test.stopTest();

        System.assertEquals(true, canAdd, 'Fresh app should allow adding applicants');
    }

    @isTest
    static void resolveNextDedupeTabLabel_returnsBorrowerWhenGuarantorDone() {
        Id appId = applicationId();
        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Customer_Code__c = 'CIF-G1',
            Loan_Stage__c = 'Dedupe and Eligibility',
            Current_Loan_Stage_Complete__c = 'Dedupe and Eligibility'
        );

        Test.startTest();
        String nextTab = CustomerDedupeController.resolveNextDedupeTabLabel(appId, 'G1');
        Test.stopTest();

        System.assertEquals('Borrower', nextTab);
    }

    @isTest
    static void getEmiDetails_requiresCustomerCode() {
        Id appId = applicationId();
        Id borrower = borrowerId();

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> args = new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => borrower
        };

        Test.startTest();
        Map<String, Object> result = (Map<String, Object>) controller.call('getExistingEmiDetails', args);
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
        System.assert(result.get('message').toString().contains('CIF'), 'Should require customer code');
    }

    @isTest
    static void hasApplicantCompletedPriorStagesForDedupe_excludesBasicDetails() {
        Applicant__c guarantor = new Applicant__c(
            Applicant_Type__c = 'Guarantor',
            Current_Loan_Stage_Complete__c = 'Basic Details'
        );

        System.assertEquals(
            false,
            CustomerDedupeController.hasApplicantCompletedPriorStagesForDedupe(guarantor)
        );
    }

    @isTest
    static void hasApplicantCompletedPriorStagesForDedupe_includesKycComplete() {
        Applicant__c guarantor = new Applicant__c(
            Applicant_Type__c = 'Guarantor',
            Current_Loan_Stage_Complete__c = 'KYC Details'
        );

        System.assertEquals(
            true,
            CustomerDedupeController.hasApplicantCompletedPriorStagesForDedupe(guarantor)
        );
    }

    @isTest
    static void hasApplicantDedupeMatchResolved_detectsCustomerCode() {
        Applicant__c app = new Applicant__c(Customer_Code__c = 'CIF-001');
        System.assertEquals(true, CustomerDedupeController.hasApplicantDedupeMatchResolved(app));
    }

    @isTest
    static void hasAdditionalApplicantsPendingPriorStages_trueWhenGuarantorOnBasic() {
        Id appId = applicationId();
        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Basic Details',
            Current_Loan_Stage_Complete__c = 'Basic Details'
        );

        Test.startTest();
        Boolean pending = CustomerDedupeController.hasAdditionalApplicantsPendingPriorStages(appId);
        List<String> labels = CustomerDedupeController.getAdditionalApplicantsPendingPriorStageLabels(appId);
        Test.stopTest();

        System.assertEquals(true, pending);
        System.assertEquals(1, labels.size());
        System.assert(labels[0].contains('G1'));
    }

    @isTest
    static void hasAdditionalApplicantsPendingPriorStages_trueWhenGuarantorLoanStageOnly() {
        Id appId = applicationId();
        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Basic Details'
        );

        Test.startTest();
        Boolean pending = CustomerDedupeController.hasAdditionalApplicantsPendingPriorStages(appId);
        Test.stopTest();

        System.assertEquals(true, pending, 'Guarantor on Basic Details with no complete step should block Borrower Next');
    }

    @isTest
    static void clearBorrowerEligibilityForRecheck_clearsBorrowerMessage() {
        Id appId = applicationId();
        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Dedupe and Eligibility',
            Customer_Code__c = 'CIF-G1'
        );

        Applicant__c borrower = [
            SELECT Id, Check_Eligibility_Message__c
            FROM Applicant__c
            WHERE Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Check_Eligibility_Message__c = 'Check Eligibility Success';
        update borrower;

        Test.startTest();
        CustomerDedupeController.clearBorrowerEligibilityForRecheck(appId);
        Test.stopTest();

        borrower = [
            SELECT Check_Eligibility_Message__c
            FROM Applicant__c
            WHERE Id = :borrower.Id
        ];
        System.assertEquals(null, borrower.Check_Eligibility_Message__c);
    }

    @isTest
    static void areAllApplicantsDedupeJourneyComplete_falseUntilGuarantorResolved() {
        Id appId = applicationId();
        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Dedupe and Eligibility'
        );

        System.assertEquals(
            false,
            CustomerDedupeController.areAllApplicantsDedupeJourneyComplete(appId)
        );
    }

    @isTest
    static void canAddMoreApplicantsForApplication_falseWhenGuarantorDedupePending() {
        Id appId = applicationId();
        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Dedupe and Eligibility',
            Current_Loan_Stage_Complete__c = 'KYC Details'
        );

        Test.startTest();
        Boolean canAdd = CustomerDedupeController.canAddMoreApplicantsForApplication(appId);
        Test.stopTest();

        System.assertEquals(false, canAdd, 'Should not allow add-more while G1 dedupe is pending');
    }

    @isTest
    static void canAddMoreApplicantsForApplication_trueWhenGuarantorDedupeResolved() {
        Id appId = applicationId();
        insert new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Dedupe and Eligibility',
            Current_Loan_Stage_Complete__c = 'Dedupe and Eligibility',
            Customer_Code__c = 'CIF-G1'
        );

        Test.startTest();
        Boolean canAdd = CustomerDedupeController.canAddMoreApplicantsForApplication(appId);
        Test.stopTest();

        System.assertEquals(true, canAdd, 'Should allow add-more after G1 completes dedupe');
    }

    @isTest
    static void getPageData_flagsTwoWheelerWhenProductIs2W() {
        Application__c twApp = new Application__c(
            Sub_Stage__c = 'Dedupe and Eligibility',
            Stage__c = 'QDE',
            Product__c = '2W'
        );
        insert twApp;

        Applicant__c borrower = new Applicant__c(
            Application__c = twApp.Id,
            Applicant_Type__c = 'Borrower',
            Applicant_Tab_Label__c = 'Borrower',
            Loan_Stage__c = 'Dedupe and Eligibility'
        );
        insert borrower;

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> result = (Map<String, Object>) controller.call('getPageData', new Map<String, Object>{
            'recordId' => twApp.Id,
            'applicantId' => borrower.Id
        });

        System.assertEquals(true, result.get('isTwoWheeler'), 'Product__c 2W should flag two-wheeler');
    }

    @isTest
    static void saveApplicantSelections_createsCoBorrowerForTwoWheelerProduct2W() {
        Application__c twApp = new Application__c(
            Sub_Stage__c = 'Dedupe and Eligibility',
            Stage__c = 'QDE',
            Product__c = '2W'
        );
        insert twApp;

        insert new Applicant__c(
            Application__c = twApp.Id,
            Applicant_Type__c = 'Borrower',
            Applicant_Tab_Label__c = 'Borrower',
            Loan_Stage__c = 'Dedupe and Eligibility',
            Current_Loan_Stage_Complete__c = 'Dedupe and Eligibility',
            Customer_Code__c = 'CIF-BORROWER'
        );

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> result = (Map<String, Object>) controller.call('saveApplicantSelections', new Map<String, Object>{
            'recordId' => twApp.Id,
            'addGuarantorCoBorrower' => 'Yes',
            'addBeneficiary' => 'No'
        });

        System.assertEquals(true, result.get('isSuccess'), String.valueOf(result.get('message')));
        System.assertEquals('CoBo1', result.get('createdApplicantTabLabel'));

        Applicant__c coBorrower = [
            SELECT Applicant_Type__c, Applicant_Tab_Label__c
            FROM Applicant__c
            WHERE Application__c = :twApp.Id AND Applicant_Type__c = 'Co-borrower'
            LIMIT 1
        ];
        System.assertEquals('CoBo1', coBorrower.Applicant_Tab_Label__c);
    }

    @isTest
    static void getApplicantManagementData_countsExistingCoBorrowerPicklistValue() {
        Application__c twApp = new Application__c(
            Sub_Stage__c = 'Dedupe and Eligibility',
            Stage__c = 'QDE',
            Product__c = '2W'
        );
        insert twApp;

        insert new Applicant__c(
            Application__c = twApp.Id,
            Applicant_Type__c = 'Borrower',
            Applicant_Tab_Label__c = 'Borrower',
            Loan_Stage__c = 'Dedupe and Eligibility'
        );
        insert new Applicant__c(
            Application__c = twApp.Id,
            Applicant_Type__c = 'Co-borrower',
            Applicant_Tab_Label__c = 'CoBo1',
            Loan_Stage__c = 'Basic Details'
        );

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> result = (Map<String, Object>) controller.call('getApplicantManagementData', new Map<String, Object>{
            'recordId' => twApp.Id,
            'applicantId' => [
                SELECT Id FROM Applicant__c
                WHERE Application__c = :twApp.Id AND Applicant_Type__c = 'Borrower'
                LIMIT 1
            ][0].Id
        });

        System.assertEquals(true, result.get('isTwoWheeler'));
        List<Object> removable = (List<Object>) result.get('removableApplicants');
        System.assertEquals(1, removable.size(), 'Co-borrower CoBo1 should appear in removable list');
    }

    @isTest
    static void getPageData_borrowerStubDoesNotExposeApplicantCodeWithoutCrossSell() {
        Id appId = applicationId();
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Customer_Code__c = '36609355';
        update borrower;

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> result = (Map<String, Object>) controller.call('getPageData', new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => borrower.Id
        });

        List<Object> matches = (List<Object>) result.get('matches');
        System.assertEquals(3, matches.size());
        for (Object rowObj : matches) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            System.assertNotEquals(
                'CIF-36609355',
                row.get('cifId'),
                'No stub row should expose applicant CIF until KYC repayment card is selected'
            );
        }
        System.assertEquals(false, result.get('autoMatchedFromCrossSell'));
        System.assertEquals(false, result.get('hasDedupeMatchResolved'));
    }

    @isTest
    static void getPageData_autoMatchesWhenKycRepaymentAccountSelected() {
        Id appId = applicationId();
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Customer_Code__c = '36609355';
        borrower.Bank_Account_No__c = '156620178118';
        update borrower;

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> result = (Map<String, Object>) controller.call('getPageData', new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => borrower.Id
        });

        System.assertEquals(true, result.get('autoMatchedFromCrossSell'));
        System.assertEquals(true, result.get('hasDedupeMatchResolved'));
        System.assertEquals(true, result.get('applicantHasCustomerCode'));

        List<Object> matches = (List<Object>) result.get('matches');
        Map<String, Object> partialMatch = (Map<String, Object>) matches[1];
        System.assertEquals('CIF-36609355', partialMatch.get('cifId'));

        borrower = [
            SELECT Relationship_with_Bank__c, Customer_Code__c
            FROM Applicant__c
            WHERE Id = :borrower.Id
        ];
        System.assertEquals('ETB', borrower.Relationship_with_Bank__c);
        System.assertEquals('36609355', borrower.Customer_Code__c);
    }

    @isTest
    static void getPageData_hasDedupeMatchResolvedAfterMarkValid() {
        Id appId = applicationId();
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Customer_Code__c = '35609155';
        borrower.Relationship_with_Bank__c = 'ETB';
        update borrower;

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> result = (Map<String, Object>) controller.call('getPageData', new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => borrower.Id
        });

        System.assertEquals(true, result.get('hasDedupeMatchResolved'));
        System.assertEquals('35609155', result.get('customerCode'));
    }

    @isTest
    static void getPageData_borrowerStubDoesNotAutoMatchApplicantCifFromPan() {
        Id appId = applicationId();
        Applicant__c borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :appId AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        borrower.Customer_Code__c = '36609355';
        update borrower;

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> result = (Map<String, Object>) controller.call('getPageData', new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => borrower.Id
        });

        System.assertEquals(
            false,
            result.get('hasDedupeMatchResolved'),
            'CIF on PAN alone should not restore dedupe valid state before manual Valid/Invalid'
        );
    }

    @isTest
    static void getPageData_additionalApplicantStubDoesNotReuseBorrowerPrimaryCode() {
        Id appId = applicationId();
        Applicant__c coBo = new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Co-Borrower',
            Applicant_Tab_Label__c = 'CoBo1',
            Loan_Stage__c = 'Dedupe and Eligibility'
        );
        insert coBo;

        CustomerDedupeController controller = new CustomerDedupeController();
        Map<String, Object> result = (Map<String, Object>) controller.call('getPageData', new Map<String, Object>{
            'recordId' => appId,
            'applicantId' => coBo.Id
        });

        List<Object> matches = (List<Object>) result.get('matches');
        System.assertEquals(3, matches.size());
        for (Object rowObj : matches) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            System.assertNotEquals(
                'CIF-36609355',
                row.get('cifId'),
                'CoBo stub rows must not reuse Borrower primary customer code'
            );
            System.assertEquals(false, row.containsKey('customer_code__c'));
        }
    }

    @isTest
    static void normalizeCifForCompare_stripsCifPrefixForIntegrationCodes() {
        System.assertEquals(
            '36609355',
            CustomerDedupeController.normalizeCifForComparePublic('CIF-36609355')
        );
        System.assertEquals(
            '36609355',
            CustomerDedupeController.normalizeCifForComparePublic('36609355')
        );
    }

    @isTest
    static void hasApplicantClearedQdeJourney_coBorrowerWithEmploymentAndCode() {
        Id appId = applicationId();
        Applicant__c coBo = new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Co-borrower',
            Applicant_Tab_Label__c = 'CoBo1',
            Loan_Stage__c = 'Employment Details',
            Current_Loan_Stage_Complete__c = 'Employment Details',
            Customer_Code__c = '48291736'
        );
        insert coBo;

        System.assertEquals(
            true,
            CustomerDedupeController.hasApplicantClearedQdeJourney(coBo),
            'Co-borrower on Employment with dedupe code should clear QDE for post-QDE menu steps'
        );
    }

    @isTest
    static void hasApplicantClearedQdeJourney_coBorrowerStillOnDedupeWithoutCode() {
        Id appId = applicationId();
        Applicant__c coBo = new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Co-borrower',
            Applicant_Tab_Label__c = 'CoBo1',
            Loan_Stage__c = 'Dedupe and Eligibility',
            Current_Loan_Stage_Complete__c = 'KYC Details'
        );
        insert coBo;

        System.assertEquals(
            false,
            CustomerDedupeController.hasApplicantClearedQdeJourney(coBo),
            'Co-borrower still on Dedupe without a match should not clear QDE'
        );
    }

    @isTest
    static void hasApplicantClearedQdeJourney_guarantorWithEmploymentAndCode() {
        Id appId = applicationId();
        Applicant__c guarantor = new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Guarantor',
            Applicant_Tab_Label__c = 'G1',
            Loan_Stage__c = 'Employment Details',
            Current_Loan_Stage_Complete__c = 'Employment Details',
            Customer_Code__c = '71930482'
        );
        insert guarantor;

        System.assertEquals(true, CustomerDedupeController.hasApplicantClearedQdeJourney(guarantor));
    }

    @isTest
    static void hasApplicantClearedQdeJourney_beneficiaryWithEmploymentAndCode() {
        Id appId = applicationId();
        Applicant__c beneficiary = new Applicant__c(
            Application__c = appId,
            Applicant_Type__c = 'Beneficiary',
            Applicant_Tab_Label__c = 'B1',
            Loan_Stage__c = 'Employment Details',
            Current_Loan_Stage_Complete__c = 'Employment Details',
            Customer_Code__c = '58392017'
        );
        insert beneficiary;

        System.assertEquals(true, CustomerDedupeController.hasApplicantClearedQdeJourney(beneficiary));
    }

    @isTest
    static void isApplicantTypeMatch_treatsCoBorrowerPicklistVariantsAsEqual() {
        System.assertEquals(
            true,
            CustomerDedupeController.isApplicantTypeMatch('Co-borrower', 'Co-Borrower')
        );
        System.assertEquals(
            false,
            CustomerDedupeController.isApplicantTypeMatch('Guarantor', 'Co-Borrower')
        );
    }
}