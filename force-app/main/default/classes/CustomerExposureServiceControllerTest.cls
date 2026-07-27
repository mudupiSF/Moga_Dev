@IsTest
private class CustomerExposureServiceControllerTest {

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'QDE',
            Sub_Stage__c = 'Exposure Analysis',
            Product__c = '4W'
        );
        insert app;

        insert new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            In_Active_Applicant__c = false
        );
    }

    private static Map<String, Object> call(String action, Map<String, Object> args) {
        return (Map<String, Object>) new CustomerExposureServiceController().call(action, args);
    }

    private static Application__c application() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Applicant__c borrower() {
        return [
            SELECT Id
            FROM Applicant__c
            WHERE Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
    }

    @IsTest
    static void testInvokeCustomerExposureSuccess() {
        Application__c app = application();
        Applicant__c applicant = borrower();

        Test.startTest();
        Map<String, Object> result = call('invokeCustomerExposure', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testInvokeCustomerExposurePersistsLienOnDeal() {
        Application__c app = application();
        Applicant__c applicant = borrower();

        Test.startTest();
        call('invokeCustomerExposure', new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id
        });
        Test.stopTest();

        Applicant_Obligations__c obligation = [
            SELECT Lien_No__c
            FROM Applicant_Obligations__c
            WHERE Deal_No__c = 'TLN00348E'
            AND Source__c = :CustomerExposureServiceController.SOURCE_CUSTOMER_EXPOSURE_API
            LIMIT 1
        ];

        System.assertEquals('LN-TLN00348E-01', obligation.Lien_No__c);
    }

    @IsTest
    static void testInvokeCustomerExposureReplacesExistingRows() {
        Application__c app = application();
        Applicant__c applicant = borrower();
        Map<String, Object> args = new Map<String, Object>{
            'recordId' => app.Id,
            'applicantId' => applicant.Id
        };

        Test.startTest();
        call('invokeCustomerExposure', args);
        call('invokeCustomerExposure', args);
        Test.stopTest();

        System.assertEquals(
            4,
            [
                SELECT COUNT()
                FROM Applicant_Obligations__c
                WHERE Loan_Application__c = :app.Id
                AND Source__c = :CustomerExposureServiceController.SOURCE_CUSTOMER_EXPOSURE_API
            ]
        );
    }

    @IsTest
    static void testUnknownActionReturnsFailure() {
        Test.startTest();
        Map<String, Object> result = call('unsupportedAction', new Map<String, Object>());
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void testInvokeRequiresApplicationId() {
        Test.startTest();
        Map<String, Object> result = call('invokeCustomerExposure', new Map<String, Object>());
        Test.stopTest();

        System.assertEquals('Application Id is required.', result.get('message'));
    }

    @IsTest
    static void testInvokeFailsWhenNoActiveApplicants() {
        Application__c app = new Application__c(
            Stage__c = 'QDE',
            Sub_Stage__c = 'Exposure Analysis',
            Product__c = '4W'
        );
        insert app;

        Test.startTest();
        Map<String, Object> result = call('invokeCustomerExposure', new Map<String, Object>{
            'recordId' => app.Id
        });
        Test.stopTest();

        System.assertEquals('No active applicants found on this application.', result.get('message'));
    }
}