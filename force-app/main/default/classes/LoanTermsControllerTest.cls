@IsTest
private class LoanTermsControllerTest {

    private class TestContext {
        Application__c application;
        Applicant__c borrower;
        Application_Line_Item__c lineItem;
        Schemes__c scheme;
    }

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'Post Sanction Sales',
            Sub_Stage__c = 'Loan Terms',
            Product__c = '4W'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower'
        );
        insert borrower;

        Schemes__c scheme = new Schemes__c(
            Name = 'Test Scheme',
            Scheme_Code__c = 'SCH-001',
            ServiceCharges__c = 2500,
            Stamping_Charges__c = 800
        );
        insert scheme;

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = app.Id,
            Loan_Amount__c = 500000,
            Schemes__c = scheme.Id
        );
        insert lineItem;

        insert new Asset__c(
            Applicant__c = borrower.Id,
            Application_Line_Items__c = lineItem.Id,
            Vehicle_type__c = 'New'
        );
    }

    private static TestContext getContext() {
        TestContext ctx = new TestContext();
        ctx.application = [SELECT Id, Product__c FROM Application__c ORDER BY CreatedDate DESC LIMIT 1];
        ctx.borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :ctx.application.Id
            AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        ctx.lineItem = [
            SELECT Id, Schemes__c
            FROM Application_Line_Item__c
            WHERE Application__c = :ctx.application.Id
            LIMIT 1
        ];
        ctx.scheme = [SELECT Id FROM Schemes__c LIMIT 1];
        return ctx;
    }

    @IsTest
    static void getLoanTermsData_loadsSchemeAndPaySections() {
        TestContext ctx = getContext();

        Test.startTest();
        Map<String, Object> result = LoanTermsController.getLoanTermsData(
            ctx.application.Id,
            ctx.borrower.Id
        );
        Test.stopTest();

        List<Object> schemes = (List<Object>) result.get('schemes');
        System.assert(schemes.size() > 0, 'Expected at least one scheme.');
        System.assertEquals(String.valueOf(ctx.scheme.Id), result.get('selectedSchemeId'));

        List<Object> payInSection = (List<Object>) result.get('payInSection');
        List<Object> payOutSection = (List<Object>) result.get('payOutSection');
        System.assertEquals(6, payInSection.size());
        System.assertEquals(5, payOutSection.size());

        Map<String, Object> meta = (Map<String, Object>) result.get('meta');
        System.assertEquals(String.valueOf(ctx.lineItem.Id), meta.get('applicationLineItemId'));
        System.assertEquals('4W', meta.get('productType'));
    }

    @IsTest
    static void getLoanTermsData_fallsBackToSchemePayInWhenLineItemBlank() {
        TestContext ctx = getContext();
        Application_Line_Item__c ali = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Id = :ctx.lineItem.Id
        ];
        ali.Service_charges__c = null;
        ali.Documentation_charges__c = null;
        ali.Applicable_Stamping_Charges__c = null;
        update ali;

        Test.startTest();
        Map<String, Object> result = LoanTermsController.getLoanTermsData(
            ctx.application.Id,
            ctx.borrower.Id
        );
        Test.stopTest();

        List<Object> payInSection = (List<Object>) result.get('payInSection');
        Boolean foundServiceCharges = false;
        for (Object rowObj : payInSection) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            if (row.get('key') == 'serviceCharges') {
                System.assert(
                    String.valueOf(row.get('value')).startsWith('2500'),
                    String.valueOf(row.get('value'))
                );
                foundServiceCharges = true;
            }
        }
        System.assertEquals(true, foundServiceCharges);
    }

    @IsTest
    static void saveLoanTermsData_requiresRecordId() {
        Map<String, Object> result = LoanTermsController.saveLoanTermsData(null, null, '{}');
        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void saveLoanTermsData_requiresScheme() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(
            new Map<String, Object>{
                'payIn' => new Map<String, Object>{ 'serviceCharges' => '3000' },
                'payOut' => new Map<String, Object>{ 'mainDealerAmt' => '1000' }
            }
        );

        Map<String, Object> result = LoanTermsController.saveLoanTermsData(
            ctx.application.Id,
            ctx.borrower.Id,
            payload
        );

        System.assertEquals(false, result.get('isSuccess'));
        System.assertEquals('Scheme is required.', result.get('message'));
    }

    @IsTest
    static void saveLoanTermsData_persistsPayInAndPayOut() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(
            new Map<String, Object>{
                'schemeId' => String.valueOf(ctx.scheme.Id),
                'payIn' => new Map<String, Object>{
                    'serviceCharges' => '3100',
                    'documentationCharges' => '1400',
                    'applicableStampingCharges' => '900',
                    'cess' => '50',
                    'stampingChargesPaidBy' => 'Customer',
                    'tradeCertificate' => '100'
                },
                'payOut' => new Map<String, Object>{
                    'mainDealerAmt' => '5000',
                    'subDealerAmt' => '2000',
                    'giftAmt' => '1500',
                    'dsmName' => 'DSM Test',
                    'dsmIncentive' => '750'
                }
            }
        );

        Test.startTest();
        Map<String, Object> result = LoanTermsController.saveLoanTermsData(
            ctx.application.Id,
            ctx.borrower.Id,
            payload
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), result.get('message'));

        Application_Line_Item__c ali = [
            SELECT
                Service_charges__c,
                Documentation_charges__c,
                Applicable_Stamping_Charges__c,
                Cess__c,
                Stamping_Charges_Paid_By__c,
                Trade_certificate__c,
                Dealer_incentive_amount_main_dealer__c,
                Dealer_incentive_amount_sub_dealer__c,
                Gift_through_dealer_amount__c,
                DSM_Name__c,
                DSM_Incentive__c,
                Schemes__c
            FROM Application_Line_Item__c
            WHERE Id = :ctx.lineItem.Id
        ];
        System.assertEquals(3100, ali.Service_charges__c);
        System.assertEquals(1400, ali.Documentation_charges__c);
        System.assertEquals('900', ali.Applicable_Stamping_Charges__c);
        System.assertEquals('Customer', ali.Stamping_Charges_Paid_By__c);
        System.assertEquals('5000', ali.Dealer_incentive_amount_main_dealer__c);
        System.assertEquals(ctx.scheme.Id, ali.Schemes__c);
    }

    @IsTest
    static void saveLoanTermsData_failsWhenLineItemMissing() {
        Application__c app = new Application__c(
            Stage__c = 'Post Sanction Sales',
            Sub_Stage__c = 'Loan Terms'
        );
        insert app;

        Schemes__c scheme = [SELECT Id FROM Schemes__c LIMIT 1];
        String payload = JSON.serialize(
            new Map<String, Object>{
                'schemeId' => String.valueOf(scheme.Id),
                'payIn' => new Map<String, Object>{ 'serviceCharges' => '1000' },
                'payOut' => new Map<String, Object>()
            }
        );

        Map<String, Object> result = LoanTermsController.saveLoanTermsData(app.Id, null, payload);
        System.assertEquals(false, result.get('isSuccess'));
        System.assert(
            String.valueOf(result.get('message')).contains('Application Line Item'),
            result.get('message')
        );
    }
}