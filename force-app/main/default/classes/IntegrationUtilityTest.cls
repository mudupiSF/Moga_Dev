@IsTest
private class IntegrationUtilityTest {

    @TestSetup
    static void setupTestData() {
        Integration_Master__c master = new Integration_Master__c(
            Name = 'Test Class Master',
            Action_Master_Name__c = 'Test Class Action Master',
            Apex_Class_Name__c = 'Test Class Apex Class',
            End_Point_URL__c = 'https://example.org/test',
            Is_Mocking_Service_Enabled__c = true,
            Mocking_Service_Response__c = '{"status":"sent"}',
            Mocking_Service_Status__c = 'OK',
            Mocking_Service_Status_Code__c = 200,
            Encrypt_Request__c = true,
            Decrypt_Response__c = true
        );
        insert master;
    }

    @IsTest
    static void testInitiateCalloutGuards() {
        Test.startTest();
        IntegrationUtility util = new IntegrationUtility();

        // Missing master record guard
        IntegrationUtility.RequestWrapper noMaster = new IntegrationUtility.RequestWrapper();
        noMaster.method = 'POST';
        noMaster.endpointURL = 'https://example.org';
        try {
            util.initiateCallout(noMaster);
            System.assert(false, 'Expected exception for missing master record');
        }
        catch (Exception e) {
            System.assert(e.getMessage().contains('Integration Master details are mandatory'));
        }

        // Missing method guard
        IntegrationUtility.RequestWrapper noMethod = new IntegrationUtility.RequestWrapper();
        Integration_Master__c master = [SELECT Id FROM Integration_Master__c WHERE Name = 'Test Class Master'];
        noMethod.masterRecord = master;
        noMethod.endpointURL = 'https://example.org';
        try {
            util.initiateCallout(noMethod);
            System.assert(false, 'Expected exception for missing method');
        }
        catch (Exception e) {
            System.assert(e.getMessage().contains('Method is mandatory'));
        }

        // Missing endpoint guard (both wrapper + master endpoint blank)
        Integration_Master__c noEndpointMaster = [SELECT Id FROM Integration_Master__c WHERE Name = 'Test Class Master'];
        noEndpointMaster.End_Point_URL__c = null;
        update noEndpointMaster;
        IntegrationUtility.RequestWrapper noEndpoint = new IntegrationUtility.RequestWrapper();
        noEndpoint.masterRecord = noEndpointMaster;
        noEndpoint.method = 'POST';
        noEndpoint.endpointURL = null;
        try {
            util.initiateCallout(noEndpoint);
            System.assert(false, 'Expected exception for missing endpoint');
        }
        catch (Exception e) {
            System.assert(e.getMessage().contains('Endpoint URL is mandatory'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGenerateMockingResponseFallbackAndExplicitValues() {
        Integration_Master__c master = [SELECT Id FROM Integration_Master__c WHERE Name = 'Test Class Master'];
        Integration_Checklist__c ic = new Integration_Checklist__c(
            Integration_Master_ID__c = master.Id
        );
        insert ic;
        Test.startTest();
        HttpResponse mocked1 = IntegrationUtility.generateMockingResponse(ic);
        ic.Mocking_Service_Response__c = '{"status":"success","data":"from file"}';
        ic.Mocking_Service_Status__c = 'OK';
        ic.Mocking_Service_Status_Code__c = 200;
        update ic;
        HttpResponse mocked2 = IntegrationUtility.generateMockingResponse(ic);
        System.assertEquals(200, mocked2.getStatusCode());
        // Create ContentVersion for mock response
        ContentVersion cv = new ContentVersion(
            Title = 'Mock Response',
            PathOnClient = 'mock-response.json',
            VersionData = Blob.valueOf('{"status":"There has been an error}')
        );
        insert cv;
        // Create ContentDocumentLink
        ContentVersion insertedCV = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = master.Id,
            ContentDocumentId = insertedCV.ContentDocumentId,
            ShareType = 'V'
        );
        insert cdl;
        HttpResponse mocked3 = IntegrationUtility.generateMockingResponse(ic);
        System.assertEquals(200, mocked3.getStatusCode());
        Test.stopTest();
    }

    @IsTest
    static void testEncryptionAndDecryption() {
        Test.startTest();
        String encryptedRequest = IntegrationUtility.getEncryptedRequest('{"status":"success","data":"from file"}', 'Keys');
        String decryptedRequest = IntegrationUtility.getDecryptedResponse(encryptedRequest, 'Keys');
        System.assertEquals('{"status":"success","data":"from file"}', decryptedRequest);
        Test.stopTest();
    }

    @IsTest
    static void testInitiateCalloutMocked() {
        Integration_Master__c master = [SELECT Id, Name, Action_Master_Name__c, Is_Auto_Initiated__c, Max_Number_of_Retries_Allowed__c, Encrypt_Request__c, Decrypt_Response__c, End_Point_URL__c FROM Integration_Master__c WHERE Name = 'Test Class Master'];
        //String encryptedRequest = IntegrationUtility.encryptMessage('{"status":"success","data":"from file"}');
        String encryptedRequest = IntegrationUtility.getEncryptedRequest('{"status":"success","data":"from file"}', 'Keys');
        // Create ContentVersion for mock response
        ContentVersion cv = new ContentVersion(
            Title = 'Mock Response',
            PathOnClient = 'mock-response.json',
            VersionData = Blob.valueOf(encryptedRequest)
        );
        insert cv;
        
        // Create ContentDocumentLink
        ContentVersion insertedCV = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = master.Id,
            ContentDocumentId = insertedCV.ContentDocumentId,
            ShareType = 'V'
        );
        insert cdl;
        Integration_Checklist__c checklist = new Integration_Checklist__c(
            Integration_Master_ID__c = master.Id,
            Integration_Master_Name__c = master.Name,
            Action_Master_Name__c = master.Action_Master_Name__c,
            Status__c = 'In Progress',
            Is_Auto_Initiated__c = master.Is_Auto_Initiated__c,
            Max_Number_of_Retries_Allowed__c = master.Max_Number_of_Retries_Allowed__c,
            Encrypt_Request__c = master.Encrypt_Request__c,
            Decrypt_Response__c = master.Decrypt_Response__c,
            Is_Mocking_Service_Enabled__c = true,
            Mocking_Service_Response__c = '{"status":"sent"}',
            Mocking_Service_Status__c = 'OK',
            Mocking_Service_Status_Code__c = 200
        );
        insert checklist;

        IntegrationUtility.RequestWrapper request = new IntegrationUtility.RequestWrapper();
        request.masterRecord = master;
        request.checklistRecord = checklist;
        request.method = 'POST';
        request.endpointURL = 'https://example.org/test';
        request.captureRequestInAttachment = true;
        request.captureResponseInAttachment = true;
        request.endpointURL = master.End_Point_URL__c;
        request.request = '{"sample":"payload"}';
        request.headersMap = new Map<String, String>{ 'x-test' => '1' };
        request.urlParamterMap = new Map<String, String>{ 'a' => 'b' };

        Boolean oldFlag = IntegrationUtility.MULTIPLE_IC;
        IntegrationUtility.MULTIPLE_IC = true;
        Test.startTest();
        IntegrationUtility.ResponseWrapper response = new IntegrationUtility().initiateCallout(request);
        Test.stopTest();
        IntegrationUtility.MULTIPLE_IC = oldFlag;
        System.assertEquals(200, response.statusCode);
    }
}