@isTest
private class NetworthAndFleetDetailsControllerTest {

    private static final String TYPE_IMMOVABLE = 'Total Value of Immovable Property';
    private static final String TYPE_OTHER = 'Total Value of Other Assets';
    private static final String TYPE_LIABILITY = 'Total Liabilities';
    private static final String FLEET_FREE = 'Free Fleet';
    private static final String FLEET_FINANCED = 'Financed by Others';

    @TestSetup
    static void setup() {
        Application__c app = new Application__c(
            Name = 'Networth Fleet Test App',
            Sub_Stage__c = 'Income and Banking Details',
            Stage__c = 'QDE',
            Product__c = 'CV',
            OwnerId = UserInfo.getUserId()
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            Type__c = 'Non-Individual',
            In_Active_Applicant__c = false
        );
        insert borrower;

        insert new List<Networth_Details__c>{
            new Networth_Details__c(
                Applicant__c = borrower.Id,
                Networth_Type__c = TYPE_IMMOVABLE,
                Market_Value__c = 100,
                Networth_Remarks__c = 'Test remarks'
            ),
            new Networth_Details__c(
                Applicant__c = borrower.Id,
                Networth_Type__c = TYPE_OTHER,
                Value_at_Cost_lacs__c = 50
            ),
            new Networth_Details__c(
                Applicant__c = borrower.Id,
                Networth_Type__c = TYPE_LIABILITY,
                O_s_as_on_date_In_Lacs__c = 30
            )
        };

        insert new Fleet_Details__c(
            Applicant__c = borrower.Id,
            Fleet_Type__c = FLEET_FREE,
            Product__c = 'SCV',
            Asset_Make__c = 'TATA',
            Asset_Model__c = 'PRIMA',
            Vehicle_Number__c = 'MH12AB1234',
            Year_of_Manufacture__c = 2020,
            Current_Demand__c = 50000,
            Seasoning__c = Date.newInstance(2024, 1, 1),
            Fleet_Remarks__c = 'Fleet remarks'
        );
    }

    private static Map<String, Object> call(String action, Map<String, Object> args) {
        return (Map<String, Object>) new NetworthAndFleetDetailsController().call(action, args);
    }

    private static Application__c app() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Applicant__c borrower() {
        return [SELECT Id FROM Applicant__c WHERE Applicant_Type__c = 'Borrower' LIMIT 1];
    }

    @isTest
    static void testFetchContext() {
        Test.startTest();
        Map<String, Object> result = call('fetchNetworthAndFleetDetails', new Map<String, Object>{
            'recordId' => app().Id,
            'applicantId' => borrower().Id
        });
        Test.stopTest();

        System.assertEquals(true, result.get('canEdit'));
        System.assertEquals(true, result.get('isCvProduct'));
        System.assertEquals(true, result.get('canEditDeleteFleet'));
    }

    @isTest
    static void testNetworthGetAndSave() {
        Applicant__c applicant = borrower();
        Networth_Details__c existing = [
            SELECT Id FROM Networth_Details__c
            WHERE Applicant__c = :applicant.Id AND Networth_Type__c = :TYPE_IMMOVABLE
            LIMIT 1
        ];

        Test.startTest();
        Map<String, Object> fetched = call('getNetworthDetails', new Map<String, Object>{
            'applicantId' => applicant.Id
        });
        Map<String, Object> saved = call('saveNetworthDetails', new Map<String, Object>{
            'data' => JSON.serialize(new Map<String, Object>{
                'applicantId' => applicant.Id,
                'networthRemarks' => 'Updated remarks',
                'networthData' => new List<Object>{
                    new Map<String, Object>{
                        'Id' => existing.Id,
                        'Networth_Type__c' => TYPE_IMMOVABLE,
                        'Market_Value__c' => 150
                    }
                }
            })
        });
        Test.stopTest();

        System.assertEquals(120, fetched.get('totalNetworth'));
        System.assertEquals(true, saved.get('isSuccess'));
    }

    @isTest
    static void testFleetActions() {
        Applicant__c applicant = borrower();

        Test.startTest();
        Map<String, Object> count = call('getFleetCount', new Map<String, Object>{
            'applicantId' => applicant.Id
        });
        Map<String, Object> details = call('getFleetDetails', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'fleetType' => FLEET_FREE
        });
        Map<String, Object> saved = call('saveFleetDetail', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'fleetType' => FLEET_FREE,
            'fleetRecord' => new Map<String, Object>{
                'Asset_Make__c' => 'TATA',
                'Asset_Model__c' => 'SIGNA',
                'Current_Demand__c' => 55000,
                'Financiar_Name__c' => '',
                'Policy_Expire_Date__c' => '2025-12-31 00:00:00',
                'Product__c' => 'SCV',
                'Seasoning__c' => '2024-02-01',
                'Vehicle_Number__c' => 'MH12EF9012',
                'Year_of_Manufacture__c' => 2021
            }
        });

        Fleet_Details__c toDelete = [
            SELECT Id FROM Fleet_Details__c
            WHERE Vehicle_Number__c = 'MH12AB1234' LIMIT 1
        ];
        Map<String, Object> deleted = call('deleteFleetDetail', new Map<String, Object>{
            'fleetId' => toDelete.Id
        });
        Test.stopTest();

        System.assertEquals(1, count.get('totalFleet'));
        System.assertEquals(1, ((List<Fleet_Details__c>) details.get('fleetDetails')).size());
        System.assertEquals(2, ((List<Fleet_Details__c>) saved.get('fleetDetails')).size());
        System.assertEquals(true, deleted.get('isSuccess'));
    }

    @isTest
    static void testMakeModelAndDocument() {
        Application__c application = app();
        Applicant__c applicant = borrower();

        ContentVersion cv = new ContentVersion(
            Title = 'networth.pdf',
            PathOnClient = 'networth.pdf',
            VersionData = Blob.valueOf('test'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        Map<String, Object> makes = call('getMakeList', new Map<String, Object>{ 'productType' => 'SCV' });
        Map<String, Object> models = call('getModelList', new Map<String, Object>{ 'makeCode' => 'TATA' });
        Map<String, Object> uploaded = call('upsertDocumentChecklist', new Map<String, Object>{
            'recordId' => application.Id,
            'applicantId' => applicant.Id,
            'documentType' => 'Networth Detail Document',
            'contentDocumentId' => cv.ContentDocumentId,
            'contentVersionId' => cv.Id,
            'fileName' => 'networth.pdf'
        });
        Map<String, Object> fetched = call('getDocumentChecklist', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'documentType' => 'Networth Detail Document'
        });
        Test.stopTest();

        System.assert(((List<Object>) makes.get('makeOptions')).size() > 0);
        System.assert(((List<Object>) models.get('modelOptions')).size() > 0);
        System.assertEquals(true, uploaded.get('isSuccess'));
        System.assertEquals(true, fetched.get('found'));
    }

    @isTest
    static void testValidationErrors() {
        Boolean missingApp = false;

        Test.startTest();
        try {
            call('fetchNetworthAndFleetDetails', new Map<String, Object>());
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
}