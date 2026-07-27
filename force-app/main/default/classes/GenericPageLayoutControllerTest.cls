/**
 * @description Test coverage for GenericPageLayoutController.
 */
@IsTest
private class GenericPageLayoutControllerTest {

    public class NonMapCallable implements Callable {
        public Object call(String action, Map<String, Object> args) {
            return 'not-a-map';
        }
    }

    public class AuraErrorCallable implements Callable {
        public Object call(String action, Map<String, Object> args) {
            throw new AuraHandledException('Callable boom');
        }
    }

    @TestSetup
    static void setupData() {
        Application__c application = new Application__c(
            Name = 'Generic Layout Test App',
            Stage__c = 'DDE',
            Sub_Stage__c = 'Offer',
            Product__c = '2W'
        );
        insert application;

        insert new Applicant__c(
            Application__c = application.Id,
            Applicant_Type__c = 'Borrower',
            Type__c = 'Individual',
            Customer_First_Name__c = 'GPL',
            Customer_Last_Name__c = 'Tester',
            In_Active_Applicant__c = false
        );
    }

    private static Application__c application() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    @IsTest
    static void getFieldConfig_missingParams_throws() {
        Boolean thrown = false;
        try {
            GenericPageLayoutController.getFieldConfig('', 'getBorrowerPageData', null, null);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void getFieldConfig_borrowerMaster_success() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = GenericPageLayoutController.getFieldConfig(
            'sampleMasterPageController',
            'getPageData',
            app.Id,
            new Map<String, Object>()
        );
        Test.stopTest();

        System.assertEquals('2W', result.get('productType'));
        System.assertEquals('Borrower', result.get('applicantType'));
    }

    @IsTest
    static void getFieldConfig_nonMapResult_returnsDefaultShape() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = GenericPageLayoutController.getFieldConfig(
            'GenericPageLayoutControllerTest.NonMapCallable',
            'anyAction',
            app.Id,
            new Map<String, Object>()
        );
        Test.stopTest();

        System.assertEquals(0, ((List<Object>) result.get('loanBasicInfo')).size());
        System.assertEquals(0, ((List<Object>) result.get('loanDetail')).size());
        System.assertEquals(0, ((List<Object>) result.get('professionalDetail')).size());
    }

    @IsTest
    static void getFieldConfig_invalidClass_throws() {
        Boolean thrown = false;
        try {
            GenericPageLayoutController.getFieldConfig(
                'DefinitelyMissingCallableClass',
                'anyAction',
                null,
                null
            );
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void getFieldConfig_auraHandledException_rethrows() {
        Boolean thrown = false;
        try {
            GenericPageLayoutController.getFieldConfig(
                'GenericPageLayoutControllerTest.AuraErrorCallable',
                'anyAction',
                null,
                null
            );
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assertEquals('Script-thrown exception', ex.getMessage());
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void savePageData_missingParams_throws() {
        Boolean thrown = false;
        try {
            GenericPageLayoutController.savePageData(null, 'saveBorrowerPageData', null, null);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void savePageData_borrowerMaster_success() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = GenericPageLayoutController.savePageData(
            'sampleMasterPageController',
            'savePageData',
            app.Id,
            new Map<String, Object>{
                'requiredLoanAmount' => '650000',
                'profileType' => 'Salaried'
            }
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void savePageData_nonMapResult_returnsFailure() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = GenericPageLayoutController.savePageData(
            'GenericPageLayoutControllerTest.NonMapCallable',
            'anyAction',
            app.Id,
            new Map<String, Object>()
        );
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
        System.assert(((String) result.get('message')).contains('Error saving data'));
    }

    @IsTest
    static void savePageData_invalidClass_throws() {
        Boolean thrown = false;
        try {
            GenericPageLayoutController.savePageData(
            'DefinitelyMissingCallableClass',
                'saveBorrowerPageData',
                null,
                null
            );
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }
}