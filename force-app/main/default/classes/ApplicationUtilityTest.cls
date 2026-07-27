@IsTest
private class ApplicationUtilityTest {

    /**
     * Mock Integration Handler for testing
     */
    public class MockIntegrationHandler implements IIntegrationHandler {
        
        public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
            List<Applicant__c> applicants = new List<Applicant__c>();
            for(Id recordId : recordIds) {
                applicants.add(new Applicant__c(Id = recordId, Name = 'Test Applicant', PAN_Number__c = 'ABCD1234', Date_of_Birth__c = Date.today(), Customer_First_Name__c = 'Test', Customer_Last_Name__c = 'Applicant'));
            }
            return applicants;
        }
        
        public List<Object> validateInputData(List<Object> recordList) {
            List<ApplicationUtility.IntegrationResponseWrapper> responses = new List<ApplicationUtility.IntegrationResponseWrapper>();
            ApplicationUtility.IntegrationResponseWrapper response = new ApplicationUtility.IntegrationResponseWrapper();
            response.hasValidationError = false;
            responses.add(response);
            return responses;
        }
        
        public List<Object> generateRequest(List<Object> recordList) {
            List<ApplicationUtility.IntegrationRequestWrapper> requests = new List<ApplicationUtility.IntegrationRequestWrapper>();
            ApplicationUtility.IntegrationRequestWrapper request = new ApplicationUtility.IntegrationRequestWrapper();
            request.requestBody = '{"test":"request"}';
            requests.add(request);
            return requests;
        }
        
        public List<Object> processResponse(List<Object> recordList) {
            List<ApplicationUtility.IntegrationResponseWrapper> responses = new List<ApplicationUtility.IntegrationResponseWrapper>();
            ApplicationUtility.IntegrationResponseWrapper response = new ApplicationUtility.IntegrationResponseWrapper();
            response.hasValidationError = false;
            response.displayMessage = 'Success';
            responses.add(response);
            return responses;
        }
    }

    private static Integration_Master__c createTestIntegrationMaster(String name, String apexClassName, Boolean isMockingEnabled) {
        Integration_Master__c integMaster = new Integration_Master__c(
            Name = name,
            Max_Number_of_Retries_Allowed__c = 3,
            Maximum_Limit_Exceeded_Error_Message__c = 'Max retries exceeded',
            Is_Auto_Initiated__c = true,
            Is_Mocking_Service_Enabled__c = isMockingEnabled,
            Mocking_Service_Response__c = '{"status":"success"}',
            Mocking_Service_Status__c = 'OK',
            Mocking_Service_Status_Code__c = 200,
            Apex_Class_Name__c = apexClassName,
            End_Point_URL__c = 'https://test.example.com/api'
        );
        insert integMaster;
        return integMaster;
    }
    
    // Test data setup methods
    @TestSetup
    static void setupTestData() {
        Applicant__c applicant = new Applicant__c(
            Name = 'Test Applicant',
            PAN_Number__c = 'ABCD1234',
            Date_of_Birth__c = Date.today(),
            Customer_First_Name__c = 'Test',
            Customer_Last_Name__c = 'Applicant'
        );
        insert applicant;
        Integration_Master__c integMaster1 = new Integration_Master__c(
            Name = 'Test API Sync',
            Action_Master_Name__c = 'Test Action Master',
            Encrypt_Request__c = true,
            Decrypt_Response__c = true,
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
        insert integMaster1;
        Integration_Master__c integMaster2 = new Integration_Master__c(
            Name = 'Test API Async',
            Action_Master_Name__c = 'Test Action Master',
            Encrypt_Request__c = true,
            Decrypt_Response__c = true,
            Allow_Retry__c = true,
            Allow_Refresh__c = true,
            Max_Number_of_Retries_Allowed__c = 3,
            Maximum_Limit_Exceeded_Error_Message__c = 'Max retries exceeded',
            Is_Auto_Initiated__c = true,
            Is_Mocking_Service_Enabled__c = true,
            Mocking_Service_Response__c = '{"status":"success"}',
            Mocking_Service_Status__c = 'OK',
            Mocking_Service_Status_Code__c = 200,
            Apex_Class_Name__c = 'ApplicationUtilityTest.MockIntegrationHandler',
            End_Point_URL__c = 'https://test.example.com/api'
        );
        insert integMaster2;
    }


    @IsTest
    static void testCreateICRecordAndMasterFetchMethods() {
        Applicant__c applicant = [SELECT Id FROM Applicant__c WHERE Name = 'Test Applicant'];
        Integration_Master__c im = [SELECT Id, Name, Apex_Class_Name__c, End_Point_URL__c, Is_Auto_Initiated__c, Is_Mocking_Service_Enabled__c, Mocking_Service_Response__c, Mocking_Service_Status__c, Mocking_Service_Status_Code__c, Max_Number_of_Retries_Allowed__c, Maximum_Limit_Exceeded_Error_Message__c, Encrypt_Request__c, Decrypt_Response__c, Action_Master_Name__c, Allow_Retry__c, Allow_Refresh__c, Encryption_Setting_Name_Encryption__c, Encryption_Setting_Name_Decryption__c FROM Integration_Master__c WHERE Name = 'Test API Sync'];

        Integration_Checklist__c ic = ApplicationUtility.createICRecord(
            applicant.Id,
            im,
            'Applicant__c'
        );
        System.assertEquals(true, ic.Is_Latest__c);

        List<Integration_Master__c> byName = ApplicationUtility.getIMRecordByName(im.Name);
        System.assertEquals(1, byName.size());

        List<Integration_Master__c> byIds = ApplicationUtility.getIMRecordsByIDs(new Set<Id>{ im.Id });
        System.assertEquals(1, byIds.size());
    }

    @IsTest
    static void testInvokeIntegrationSync() {
        Applicant__c applicant = [SELECT Id FROM Applicant__c WHERE Name = 'Test Applicant'];
        Integration_Master__c im = [SELECT Id, Name, Apex_Class_Name__c, End_Point_URL__c, Is_Auto_Initiated__c, Is_Mocking_Service_Enabled__c, Mocking_Service_Response__c, Mocking_Service_Status__c, Mocking_Service_Status_Code__c, Max_Number_of_Retries_Allowed__c, Maximum_Limit_Exceeded_Error_Message__c, Encrypt_Request__c, Decrypt_Response__c, Action_Master_Name__c, Allow_Retry__c, Allow_Refresh__c FROM Integration_Master__c WHERE Name = 'Test API Sync'];

        Test.startTest();
        ApplicationUtility.IntegrationResponseWrapper response1 = ApplicationUtility.invokeIntegrationSync(
            im.Name,
            applicant.Id,
            'Applicant__c'
        );
        Integration_Checklist__c ic = [SELECT Id, Status__c FROM Integration_Checklist__c WHERE Applicant__c = :applicant.Id AND Integration_Master_Name__c = :im.Name];
        ic.Status__c = 'Success';
        update ic;
        ApplicationUtility.IntegrationResponseWrapper response2 = ApplicationUtility.invokeIntegrationSync(
            im.Name,
            applicant.Id,
            'Applicant__c'
        );
        Test.stopTest();

        System.assertNotEquals(null, response1);
        System.assertNotEquals(null, response2);
    }

    @isTest
    static void testInvokeIntegrationASync() {
        Applicant__c applicant = [SELECT Id FROM Applicant__c WHERE Name = 'Test Applicant'];
        Integration_Master__c integMaster = [SELECT Id, Name, Apex_Class_Name__c, End_Point_URL__c, Is_Auto_Initiated__c, Is_Mocking_Service_Enabled__c, Mocking_Service_Response__c, Mocking_Service_Status__c, Mocking_Service_Status_Code__c, Max_Number_of_Retries_Allowed__c, Maximum_Limit_Exceeded_Error_Message__c, Encrypt_Request__c, Decrypt_Response__c, Action_Master_Name__c, Allow_Retry__c, Allow_Refresh__c FROM Integration_Master__c WHERE Name = 'Test API Async'];
        Test.startTest();
        ApplicationUtility.IntegrationResponseWrapper result = ApplicationUtility.invokeIntegrationASync(integMaster.Name, applicant.Id, 'Applicant__c');
        Integration_Checklist__c ic = [SELECT Id, Apex_Class_Name__c, Status__c FROM Integration_Checklist__c WHERE Applicant__c = :applicant.Id AND Integration_Master_Name__c = :integMaster.Name];
        IntegrationUtility.ResponseWrapper rw = new IntegrationUtility.ResponseWrapper();
        rw.checklistRecord = ic;
        rw.response = '{"status":"ok"}';
        rw.statusCode = 200;
        List<ApplicationUtility.IntegrationResponseWrapper> processed = ApplicationUtility.processIntgerationAsync(new List<IntegrationUtility.ResponseWrapper>{ rw });
        Test.stopTest();
    }

    @IsTest
    static void testInvokeIntegrationAsyncRetrigger() {
        Applicant__c applicant = [SELECT Id FROM Applicant__c WHERE Name = 'Test Applicant'];
        Integration_Master__c integMaster = [SELECT Id, Name FROM Integration_Master__c WHERE Name = 'Test API Async'];

        Integration_Checklist__c ic = new Integration_Checklist__c(
            Integration_Master_ID__c = integMaster.Id,
            Integration_Master_Name__c = integMaster.Name,
            Status__c = 'In Progress',
            Applicant__c = applicant.Id,
            Retry_Attempt__c = 0,
            Max_Number_of_Retries_Allowed__c = 1,
            Is_Auto_Initiated__c = true
        );
        insert ic;

        Test.startTest();
        ApplicationUtility.invokeIntegrationASyncRetrigger(new List<String>{ ic.Id });
        Test.stopTest();

        Integration_Checklist__c refreshed = [
            SELECT Status__c, Functional_Status__c
            FROM Integration_Checklist__c
            WHERE Id = :ic.Id
        ];
        System.assertEquals('Obsolete', refreshed.Status__c);
    }

    @IsTest
    static void testGetExistingICRecordCount() {
        Applicant__c applicant = [SELECT Id FROM Applicant__c WHERE Name = 'Test Applicant'];
        Integration_Checklist__c ic = new Integration_Checklist__c(
            Applicant__c = applicant.Id,
            Integration_Master_Name__c = 'Test API',
            Status__c = 'Completed'
        );
        insert ic;

        Integer countValue = ApplicationUtility.getExistingICRecordCount(
            applicant.Id,
            'Test API',
            'Applicant__c',
            'Completed'
        );
        System.assertEquals(1, countValue);
    }

    // Nested fake handler used by dynamic Type.forName(..).newInstance() flows in ApplicationUtility.
    private class FakeIntegrationHandler implements IIntegrationHandler {
        public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
            return new List<sObject>{ new User(Id = UserInfo.getUserId()) };
        }

        public List<Object> validateInputData(List<Object> recordList) {
            ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
            wrapper.hasValidationError = false;
            wrapper.recordId = UserInfo.getUserId();
            return new List<Object>{ wrapper };
        }

        public List<Object> generateRequest(List<Object> recordList) {
            ApplicationUtility.IntegrationRequestWrapper req = new ApplicationUtility.IntegrationRequestWrapper();
            req.requestBody = '{"test":"request"}';
            req.method = 'POST';
            return new List<Object>{ req };
        }

        public List<Object> processResponse(List<Object> recordList) {
            ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
            wrapper.hasValidationError = false;
            wrapper.displayMessage = 'Processed successfully';
            return new List<Object>{ wrapper };
        }
    }
}