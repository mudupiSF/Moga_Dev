@isTest
private class IncomeDetailsCaptureControllerTest {

    private static final String DECLARED_INCOME = 'Declared Income';

    @TestSetup
    static void setup() {
        Application__c app = new Application__c(
            Name = 'Income Details Test App',
            Sub_Stage__c = 'Income Details',
            Stage__c = 'QDE',
            Product__c = '4W'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            Type__c = 'Individual',
            In_Active_Applicant__c = false,
            Declared_income__c = 500000
        );
        insert borrower;

        insert new Asset__c(Applicant__c = borrower.Id, Name = 'Test Asset');

        Applicant_Income__c income = new Applicant_Income__c(
            Applicant__c = borrower.Id,
            Name = DECLARED_INCOME,
            Consolidated_Yearly_Income__c = 500000
        );
        insert income;
    }

    private static Map<String, Object> call(String action, Map<String, Object> args) {
        return (Map<String, Object>) new IncomeDetailsCaptureController().call(action, args);
    }

    private static Application__c app() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Applicant__c borrower() {
        return [SELECT Id FROM Applicant__c WHERE Applicant_Type__c = 'Borrower' LIMIT 1];
    }

    private static ContentVersion uploadFile(String fileName) {
        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = Blob.valueOf('test'),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    }

    private static void ensureBankStatementDocument() {
        Application__c application = app();
        Applicant__c applicant = borrower();
        ContentVersion cv = uploadFile('bank.pdf');
        call('upsertDeclaredIncomeDocument', new Map<String, Object>{
            'recordId' => application.Id,
            'applicantId' => applicant.Id,
            'contentDocumentId' => cv.ContentDocumentId,
            'contentVersionId' => cv.Id,
            'fileName' => 'bank.pdf'
        });
    }

    @isTest
    static void testFetchContextAndGetDeclaredIncome() {
        Application__c application = app();
        Applicant__c applicant = borrower();
        ensureBankStatementDocument();

        Test.startTest();
        Map<String, Object> context = call('fetchIncomeDetailsContext', new Map<String, Object>{
            'recordId' => application.Id,
            'applicantId' => applicant.Id
        });
        Map<String, Object> details = call('getDeclaredIncomeDetails', new Map<String, Object>{
            'applicantId' => applicant.Id
        });
        Test.stopTest();

        System.assertEquals(true, context.get('canEdit'));
        System.assertEquals('Saved', details.get('status'));
        System.assertEquals(500000, details.get('consolidatedYearlyIncome'));
    }

    @isTest
    static void testSaveDeclaredIncome() {
        Application__c application = app();
        Applicant__c applicant = borrower();
        ensureBankStatementDocument();

        Test.startTest();
        Map<String, Object> result = call('saveDeclaredIncomeDetails', new Map<String, Object>{
            'recordId' => application.Id,
            'applicantId' => applicant.Id,
            'data' => JSON.serialize(new Map<String, Object>{ 'consolidatedYearlyIncome' => 750000 })
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
        System.assertEquals(750000, result.get('consolidatedYearlyIncome'));
    }

    @isTest
    static void testDocumentActions() {
        Application__c application = app();
        Applicant__c applicant = borrower();
        Applicant_Income__c income = [
            SELECT Id FROM Applicant_Income__c WHERE Name = :DECLARED_INCOME LIMIT 1
        ];

        ContentVersion cv = new ContentVersion(
            Title = 'new-bank.pdf',
            PathOnClient = 'new-bank.pdf',
            VersionData = Blob.valueOf('test'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        Map<String, Object> upload = call('upsertDeclaredIncomeDocument', new Map<String, Object>{
            'recordId' => application.Id,
            'applicantId' => applicant.Id,
            'contentDocumentId' => cv.ContentDocumentId,
            'contentVersionId' => cv.Id,
            'fileName' => 'new-bank.pdf'
        });
        Map<String, Object> fetched = call('getDeclaredIncomeDocument', new Map<String, Object>{
            'applicantIncomeId' => income.Id
        });
        Map<String, Object> deleted = call('deleteDeclaredIncomeDocument', new Map<String, Object>{
            'applicantId' => applicant.Id
        });
        Test.stopTest();

        System.assertEquals(true, upload.get('isSuccess'));
        System.assertEquals(true, fetched.get('found'));
        System.assertEquals(true, deleted.get('isSuccess'));
    }

    @isTest
    static void testValidationErrors() {
        Application__c application = app();
        Applicant__c applicant = borrower();
        Boolean missingApplicant = false;
        Boolean missingDocument = false;

        Test.startTest();
        try {
            call('getDeclaredIncomeDetails', new Map<String, Object>());
        } catch (AuraHandledException e) {
            missingApplicant = true;
        }

        Applicant__c newApplicant = new Applicant__c(
            Application__c = application.Id,
            Applicant_Type__c = 'Co-Borrower',
            In_Active_Applicant__c = false
        );
        insert newApplicant;

        try {
            call('saveDeclaredIncomeDetails', new Map<String, Object>{
                'recordId' => application.Id,
                'applicantId' => newApplicant.Id,
                'data' => new Map<String, Object>{ 'consolidatedYearlyIncome' => 100000 }
            });
        } catch (AuraHandledException e) {
            missingDocument = true;
        }

        try {
            call('unknownAction', new Map<String, Object>());
        } catch (CalloutException e) {
            System.assert(e.getMessage().contains('Unknown action'));
        }
        Test.stopTest();

        System.assertEquals(true, missingApplicant);
        System.assertEquals(true, missingDocument);
    }

    @isTest
    static void testViaGenericPageLayout() {
        Application__c application = app();
        Applicant__c applicant = borrower();
        ensureBankStatementDocument();

        Test.startTest();
        Map<String, Object> context = GenericPageLayoutController.getFieldConfig(
            'IncomeDetailsCaptureController',
            'fetchIncomeDetailsContext',
            application.Id,
            new Map<String, Object>{ 'applicantId' => applicant.Id }
        );
        Map<String, Object> saved = GenericPageLayoutController.savePageData(
            'IncomeDetailsCaptureController',
            'saveDeclaredIncomeDetails',
            application.Id,
            new Map<String, Object>{
                'applicantId' => applicant.Id,
                'data' => JSON.serialize(new Map<String, Object>{ 'consolidatedYearlyIncome' => 600000 })
            }
        );
        Test.stopTest();

        System.assertEquals(true, context.get('canEdit'));
        System.assertEquals(true, saved.get('isSuccess'));
    }
}