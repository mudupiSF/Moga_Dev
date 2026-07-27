@isTest
private class FinanceGridControllerTest {

    @TestSetup
    static void setup() {
        Application__c app = new Application__c(
            Name = 'Finance Grid Test App',
            Sub_Stage__c = 'Income and Banking Details',
            Stage__c = 'QDE',
            Product__c = 'CV'
        );
        insert app;

        insert new Financial_Performance__c(
            Name = '2023-24',
            Application__c = app.Id,
            Profit_and_Loss_Account__c = 'Audited',
            Revenue_from_operations__c = 1000000,
            Profit_after_tax__c = 200000
        );
    }

    private static Map<String, Object> call(String action, Map<String, Object> args) {
        return (Map<String, Object>) new FinanceGridController().call(action, args);
    }

    private static Application__c app() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Financial_Performance__c fp() {
        return [SELECT Id FROM Financial_Performance__c LIMIT 1];
    }

    @isTest
    static void testFetchAndSaveFinancialPerformance() {
        Application__c application = app();
        Financial_Performance__c record = fp();
        record.Revenue_from_operations__c = 1200000;
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('excel content'));
        call('uploadFinancialPerformanceExcel', new Map<String, Object>{
            'recordId' => application.Id,
            'fileName' => 'finance.xlsx',
            'base64Body' => base64
        });

        Test.startTest();
        Map<String, Object> fetched = call('fetchFinancialPerformanceRecords', new Map<String, Object>{
            'recordId' => application.Id
        });
        Map<String, Object> saved = call('saveFinancialPerformanceRecords', new Map<String, Object>{
            'recordId' => application.Id,
            'data' => JSON.serialize(new List<Financial_Performance__c>{ record })
        });
        Test.stopTest();

        List<Financial_Performance__c> records = (List<Financial_Performance__c>) fetched.get('records');
        System.assertEquals(1, records.size());
        System.assertEquals(true, ((Map<String, Object>) fetched.get('excelDocument')).get('found'));
        System.assertEquals(true, saved.get('isSuccess'));
    }

    @isTest
    static void testSaveGstRecords() {
        Financial_Performance__c record = fp();

        Test.startTest();
        Map<String, Object> result = call('saveGstRecords', new Map<String, Object>{
            'financialPerformanceId' => record.Id,
            'recordType' => 'GSTR 3B',
            'data' => JSON.serialize(new List<GST__c>{
                new GST__c(Name_of_the_Client__c = 'Client A', Amount__c = 10000, Month__c = 'January')
            })
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
        System.assertEquals(1, [SELECT COUNT() FROM GST__c WHERE Financial_Performance__c = :record.Id]);
    }

    @isTest
    static void testExcelUploadAndDelete() {
        Application__c application = app();
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('excel content'));

        Test.startTest();
        Map<String, Object> uploaded = call('uploadFinancialPerformanceExcel', new Map<String, Object>{
            'recordId' => application.Id,
            'fileName' => 'uploaded.xlsx',
            'base64Body' => base64
        });
        Map<String, Object> deleted = call('deleteFinancialPerformanceExcel', new Map<String, Object>{
            'recordId' => application.Id
        });
        Test.stopTest();

        System.assertEquals(true, uploaded.get('isSuccess'));
        System.assertEquals(true, deleted.get('isSuccess'));
    }

    @isTest
    static void testValidationErrors() {
        Boolean missingApp = false;

        Test.startTest();
        try {
            call('fetchFinancialPerformanceRecords', new Map<String, Object>());
        } catch (AuraHandledException e) {
            missingApp = true;
        }

        try {
            call('unknownAction', new Map<String, Object>());
        } catch (CalloutException e) {
            System.assert(e.getMessage().contains('Unknown action'));
        }
        Test.stopTest();

        System.assertEquals(true, missingApp);
    }

    @isTest
    static void testViaGenericPageLayout() {
        Application__c application = app();

        Test.startTest();
        Map<String, Object> fetched = GenericPageLayoutController.getFieldConfig(
            'FinanceGridController',
            'fetchFinancialPerformanceRecords',
            application.Id,
            new Map<String, Object>()
        );
        Test.stopTest();

        System.assertEquals(1, ((List<Financial_Performance__c>) fetched.get('records')).size());
    }
}