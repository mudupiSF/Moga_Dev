@IsTest
private class ExistingQueriesControllerTest {

    @TestSetup
    static void setupData() {
        Application__c testApplication = new Application__c();
        testApplication.Product__c = 'CV';
        testApplication.Name = 'Application for Test class';
        insert testApplication;
        Application_Line_Item__c testAli = new Application_Line_Item__c();
        testAli.Name = 'Application Line Item for Test class';
        testAli.Application__c = testApplication.Id;
        insert testAli;
        Asset__c testAsset = new Asset__c();
        testAsset.Name = 'Asset for Test class';
        testAsset.Application_Line_Items__c = testAli.Id;
        insert testAsset;
        Query__c testQuery = new Query__c();
        testQuery.Application__c = testApplication.Id;
        testQuery.Asset__c = testAsset.Id;
        testQuery.Application_Line_Items__c = testAli.Id;
        testQuery.Status__c = 'Open';
        testQuery.Subject__c = 'Subject for Test class';
        insert testQuery;
    }

    @IsTest
    static void testGetExistingQueriesForApplicationContext() {
        Application__c testApplication = [SELECT Id FROM Application__c WHERE Product__c =: 'CV' LIMIT 1];

        Test.startTest();
        List<Map<String, Object>> rows = ExistingQueriesController.getExistingQueries(testApplication.Id);
        System.assertNotEquals(null, rows, 'Result should never be null');
        Test.stopTest();
    }
}