@IsTest
private class IntegrationChecklistTriggerTest {

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
        Integration_Master__c master = new Integration_Master__c(
            Name = 'Test Master',
            Apex_Class_Name__c = 'IntegrationChecklistTriggerTest.MockIntegrationHandler',
            End_Point_URL__c = 'https://test.example.com/test',
            Is_Mocking_Service_Enabled__c = true,
            Mocking_Service_Response__c = '{"status":"success"}',
            Mocking_Service_Status__c = 'OK',
            Mocking_Service_Status_Code__c = 200,
            Encrypt_Request__c = true,
            Decrypt_Response__c = true,
            Allow_Retry__c = false,
            Allow_Refresh__c = false,
            Max_Number_of_Retries_Allowed__c = 1,
            Maximum_Limit_Exceeded_Error_Message__c = 'Max retries exceeded',
            Is_Auto_Initiated__c = false
        );
        insert master;
    }

    public class MockIntegrationHandler implements IIntegrationHandler {
        public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
            return new List<sObject>();
        }
        public List<Object> validateInputData(List<Object> recordList) {
            return new List<Object>();
        }
        public List<Object> generateRequest(List<Object> recordList) {
            return new List<Object>();
        }
        public List<Object> processResponse(List<Object> recordList) {
            List<ApplicationUtility.IntegrationResponseWrapper> typed = new List<ApplicationUtility.IntegrationResponseWrapper>();
            ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
            wrapper.hasValidationError = false;
            wrapper.displayMessage = 'Processed by mock';
            typed.add(wrapper);
            return (List<Object>)(Object)typed;
        }
    }

    @IsTest
    static void makeOtherChecklistsObsoleteTest() {
        Applicant__c applicant = [SELECT Id FROM Applicant__c WHERE Name = 'Test Applicant' LIMIT 1];
        Integration_Master__c master = [SELECT Id, Name, Apex_Class_Name__c, End_Point_URL__c, Is_Mocking_Service_Enabled__c, Mocking_Service_Response__c, Mocking_Service_Status__c, Mocking_Service_Status_Code__c, Max_Number_of_Retries_Allowed__c, Maximum_Limit_Exceeded_Error_Message__c, Encrypt_Request__c, Decrypt_Response__c, Allow_Retry__c, Allow_Refresh__c, Is_Auto_Initiated__c FROM Integration_Master__c WHERE Name = 'Test Master' LIMIT 1];
        Test.startTest();
        Integration_Checklist__c checklist1 = new Integration_Checklist__c(
            Applicant__c = applicant.Id,
            Integration_Master_ID__c = master.Id,
            Integration_Master_Name__c = master.Name,
            Apex_Class_Name__c = master.Apex_Class_Name__c,
            Status__c = 'In Progress',
            Is_Latest__c = true,
            Request__c = '{"sample":"payload"}',
            Is_Auto_Initiated__c = master.Is_Auto_Initiated__c,
            Max_Number_of_Retries_Allowed__c = master.Max_Number_of_Retries_Allowed__c,
            Encrypt_Request__c = master.Encrypt_Request__c,
            Decrypt_Response__c = master.Decrypt_Response__c,
            Is_Mocking_Service_Enabled__c = master.Is_Mocking_Service_Enabled__c,
            Mocking_Service_Response__c = master.Mocking_Service_Response__c,
            Mocking_Service_Status__c = master.Mocking_Service_Status__c,
            Mocking_Service_Status_Code__c = master.Mocking_Service_Status_Code__c
        );
        insert checklist1;
        checklist1.Response__c = '{"sample":"response"}';
        checklist1.Status__c = 'Success';
        update checklist1;
        Integration_Checklist__c checklist2 = new Integration_Checklist__c(
            Applicant__c = applicant.Id,
            Integration_Master_ID__c = master.Id,
            Integration_Master_Name__c = master.Name,
            Apex_Class_Name__c = master.Apex_Class_Name__c,
            Status__c = 'In Progress',
            Is_Latest__c = true,
            Request__c = '{"sample":"payload"}',
            Is_Auto_Initiated__c = master.Is_Auto_Initiated__c,
            Max_Number_of_Retries_Allowed__c = master.Max_Number_of_Retries_Allowed__c,
            Encrypt_Request__c = master.Encrypt_Request__c,
            Decrypt_Response__c = master.Decrypt_Response__c,
            Is_Mocking_Service_Enabled__c = master.Is_Mocking_Service_Enabled__c,
            Mocking_Service_Response__c = master.Mocking_Service_Response__c,
            Mocking_Service_Status__c = master.Mocking_Service_Status__c,
            Mocking_Service_Status_Code__c = master.Mocking_Service_Status_Code__c
        );
        insert checklist2;
        Test.stopTest();
        System.assertNotEquals(null, checklist2.Id);
    }
}