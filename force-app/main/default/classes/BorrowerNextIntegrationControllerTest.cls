/**
 * @description Test coverage for BorrowerNextIntegrationController.
 */
@IsTest
private class BorrowerNextIntegrationControllerTest {

    public class ValidationErrorHandler implements IIntegrationHandler {
        public List<SObject> prepareRecordForIntegration(List<Id> recordIds) {
            return new List<SObject>{ new Applicant__c(Id = recordIds[0]) };
        }
        public List<Object> validateInputData(List<Object> recordList) {
            ApplicationUtility.IntegrationResponseWrapper wrapper =
                new ApplicationUtility.IntegrationResponseWrapper();
            wrapper.hasValidationError = true;
            wrapper.displayMessage = 'Validation failed for test';
            return new List<Object>{ wrapper };
        }
        public List<Object> generateRequest(List<Object> recordList) {
            return new List<Object>();
        }
        public List<Object> processResponse(List<Object> recordList) {
            return new List<Object>();
        }
    }

    @TestSetup
    static void setupData() {
        Applicant__c applicant = new Applicant__c(
            Name = 'Next Click Applicant',
            PAN_Number__c = 'ABCDE1234F',
            Date_of_Birth__c = Date.today(),
            Customer_First_Name__c = 'Next',
            Customer_Last_Name__c = 'Click'
        );
        insert applicant;

        List<Integration_Master__c> masters = new List<Integration_Master__c>{
            buildIntegrationMaster('CIF on PAN'),
            buildIntegrationMaster('ETB CASA')
        };
        insert masters;
    }

    private static Integration_Master__c buildIntegrationMaster(String masterName) {
        return new Integration_Master__c(
            Name = masterName,
            Action_Master_Name__c = 'Test Action',
            Encrypt_Request__c = false,
            Decrypt_Response__c = false,
            Allow_Retry__c = false,
            Allow_Refresh__c = false,
            Max_Number_of_Retries_Allowed__c = 1,
            Maximum_Limit_Exceeded_Error_Message__c = 'Max retries exceeded',
            Is_Auto_Initiated__c = false,
            Is_Mocking_Service_Enabled__c = true,
            Mocking_Service_Response__c = '{"status":"success"}',
            Mocking_Service_Status__c = 'OK',
            Mocking_Service_Status_Code__c = 200,
            Apex_Class_Name__c = 'ApplicationUtilityTest.MockIntegrationHandler',
            End_Point_URL__c = 'https://test.example.com/api'
        );
    }

    private static Applicant__c applicant() {
        return [SELECT Id FROM Applicant__c WHERE Name = 'Next Click Applicant' LIMIT 1];
    }

    @IsTest
    static void runNextClickIntegration_blankName_throws() {
        Boolean thrown = false;
        try {
            BorrowerNextIntegrationController.runNextClickIntegration(null, null, '');
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void runNextClickIntegration_unsupportedName_throws() {
        Boolean thrown = false;
        try {
            BorrowerNextIntegrationController.runNextClickIntegration(null, null, 'UNKNOWN_INTEGRATION');
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void runNextClickIntegration_customerDedupe_stubSuccess() {
        Test.startTest();
        Map<String, Object> result = BorrowerNextIntegrationController.runNextClickIntegration(
            null,
            null,
            'CUSTOMER_DEDUPE'
        );
        Test.stopTest();

        System.assertEquals('CUSTOMER_DEDUPE', result.get('integrationName'));
        System.assertEquals('CUSTOMER_DEDUPE_SUCCESS', result.get('staticResourceName'));
        Map<String, Object> response = (Map<String, Object>) result.get('response');
        System.assertEquals(true, response.get('success'));
    }

    @IsTest
    static void runNextClickIntegration_validateRecentLead_stubSuccess() {
        Test.startTest();
        Map<String, Object> result = BorrowerNextIntegrationController.runNextClickIntegration(
            null,
            null,
            ' validate_recent_lead '
        );
        Test.stopTest();

        System.assertEquals('VALIDATE_RECENT_LEAD', result.get('integrationName'));
        System.assertEquals('VALIDATE_RECENT_LEAD_SUCCESS', result.get('staticResourceName'));
    }

    @IsTest
    static void runNextClickIntegration_cifOnPan_missingApplicant_throws() {
        Boolean thrown = false;
        try {
            BorrowerNextIntegrationController.runNextClickIntegration(null, null, 'CIF_ON_PAN');
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void runNextClickIntegration_cifOnPan_success() {
        Applicant__c app = applicant();

        Test.startTest();
        Map<String, Object> result = BorrowerNextIntegrationController.runNextClickIntegration(
            null,
            app.Id,
            'cif_on_pan'
        );
        Test.stopTest();

        System.assertEquals('CIF_ON_PAN', result.get('integrationName'));
        System.assertEquals('CIF on PAN', result.get('masterName'));
        System.assertEquals(true, result.get('success'));
    }

    @IsTest
    static void runNextClickIntegration_etbCasa_success() {
        Applicant__c app = applicant();

        Test.startTest();
        Map<String, Object> result = BorrowerNextIntegrationController.runNextClickIntegration(
            null,
            app.Id,
            'ETB_CASA'
        );
        Test.stopTest();

        System.assertEquals('ETB_CASA', result.get('integrationName'));
        System.assertEquals('ETB CASA', result.get('masterName'));
        System.assertEquals(true, result.get('success'));
    }

    @IsTest
    static void runNextClickIntegration_frameworkValidationError_throws() {
        Applicant__c app = applicant();
        Integration_Master__c master = [
            SELECT Id
            FROM Integration_Master__c
            WHERE Name = 'CIF on PAN'
            LIMIT 1
        ];
        master.Apex_Class_Name__c = 'BorrowerNextIntegrationControllerTest.ValidationErrorHandler';
        update master;

        Boolean thrown = false;
        Test.startTest();
        try {
            BorrowerNextIntegrationController.runNextClickIntegration(null, app.Id, 'CIF_ON_PAN');
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }
}