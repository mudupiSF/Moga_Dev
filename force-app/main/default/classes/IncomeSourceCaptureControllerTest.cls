@isTest
private class IncomeSourceCaptureControllerTest {

    private static final String ITR = 'ITR';
    private static final String FINANCIALS = 'Financials';

    @TestSetup
    static void setup() {
        Application__c app = new Application__c(
            Name = 'Income Source Test App',
            Sub_Stage__c = 'Income and Banking Details',
            Stage__c = 'QDE',
            Product__c = '4W'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            Type__c = 'Individual',
            In_Active_Applicant__c = false
        );
        insert borrower;

        Applicant_Income__c itr = new Applicant_Income__c(
            Applicant__c = borrower.Id,
            Name = ITR,
            Income_Source__c = ITR,
            Primary_Income_Source__c = true,
            Assessment_Year__c = '2023-24',
            Income_Last_Year__c = 600000
        );
        insert itr;
    }

    private static Map<String, Object> call(String action, Map<String, Object> args) {
        return (Map<String, Object>) new IncomeSourceCaptureController().call(action, args);
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

    @isTest
    static void testGetIncomeSources() {
        Test.startTest();
        Map<String, Object> result = call('getIncomeSources', new Map<String, Object>{
            'applicantId' => borrower().Id
        });
        Test.stopTest();

        List<Object> sources = (List<Object>) result.get('incomeSources');
        System.assertEquals(1, sources.size());
        System.assertEquals(ITR, ((Map<String, Object>) sources[0]).get('incomeSource'));
    }

    @isTest
    static void testSaveItrSource() {
        Application__c application = app();
        Applicant__c applicant = new Applicant__c(
            Application__c = application.Id,
            Applicant_Type__c = 'Co-Borrower',
            In_Active_Applicant__c = false
        );
        insert applicant;

        ContentVersion cv = uploadFile('new-itr.pdf');
        Map<String, Object> upload = call('upsertIncomeSourceDocument', new Map<String, Object>{
            'recordId' => application.Id,
            'applicantId' => applicant.Id,
            'incomeSource' => ITR,
            'contentDocumentId' => cv.ContentDocumentId,
            'contentVersionId' => cv.Id,
            'fileName' => 'new-itr.pdf'
        });

        Test.startTest();
        Map<String, Object> result = call('saveIncomeSource', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'data' => new Map<String, Object>{
                'incomeSource' => ITR,
                'primaryIncomeSource' => true,
                'itrSections' => new List<Object>{
                    new Map<String, Object>{
                        'recordId' => upload.get('applicantIncomeId'),
                        'assessmentYear' => '2024-25',
                        'itrLastYearDate' => '2025-03-31',
                        'incomeLastYear' => 750000,
                        'doYouHaveAnotherITR' => false
                    }
                }
            }
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @isTest
    static void testSaveFinancialsSource() {
        Application__c application = app();
        Applicant__c applicant = new Applicant__c(
            Application__c = application.Id,
            Applicant_Type__c = 'Co-Borrower',
            In_Active_Applicant__c = false
        );
        insert applicant;

        ContentVersion cv = uploadFile('financials.pdf');
        Map<String, Object> upload = call('upsertIncomeSourceDocument', new Map<String, Object>{
            'recordId' => application.Id,
            'applicantId' => applicant.Id,
            'incomeSource' => FINANCIALS,
            'contentDocumentId' => cv.ContentDocumentId,
            'contentVersionId' => cv.Id,
            'fileName' => 'financials.pdf'
        });

        Test.startTest();
        Map<String, Object> result = call('saveIncomeSource', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'data' => new Map<String, Object>{
                'incomeSource' => FINANCIALS,
                'recordId' => upload.get('applicantIncomeId'),
                'financialYear' => '2024-25',
                'totalIncome' => 1000000,
                'totalExpense' => 400000,
                'patValue' => 250000
            }
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @isTest
    static void testDeleteIncomeSourceAndDocument() {
        Application__c application = app();
        Applicant__c applicant = borrower();
        Applicant_Income__c itrIncome = [
            SELECT Id FROM Applicant_Income__c WHERE Income_Source__c = :ITR LIMIT 1
        ];
        ContentVersion cv = uploadFile('itr.pdf');
        call('upsertIncomeSourceDocument', new Map<String, Object>{
            'recordId' => application.Id,
            'applicantId' => applicant.Id,
            'incomeSource' => ITR,
            'contentDocumentId' => cv.ContentDocumentId,
            'contentVersionId' => cv.Id,
            'fileName' => 'itr.pdf'
        });

        Test.startTest();
        Map<String, Object> docDeleted = call('deleteIncomeSourceDocument', new Map<String, Object>{
            'applicantIncomeId' => itrIncome.Id,
            'incomeSource' => ITR
        });
        Map<String, Object> sourceDeleted = call('deleteIncomeSource', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'incomeSource' => ITR
        });
        Test.stopTest();

        System.assertEquals(true, docDeleted.get('isSuccess'));
        System.assertEquals(true, sourceDeleted.get('isSuccess'));
        System.assertEquals(0, [
            SELECT COUNT() FROM Applicant_Income__c
            WHERE Applicant__c = :applicant.Id AND Income_Source__c = :ITR
        ]);
    }

    @isTest
    static void testValidationErrors() {
        Boolean missingApplicant = false;
        Boolean missingDocument = false;

        Test.startTest();
        try {
            call('getIncomeSources', new Map<String, Object>());
        } catch (AuraHandledException e) {
            missingApplicant = true;
        }

        Applicant__c applicant = new Applicant__c(
            Application__c = app().Id,
            Applicant_Type__c = 'Co-Borrower',
            In_Active_Applicant__c = false
        );
        insert applicant;

        try {
            call('saveIncomeSource', new Map<String, Object>{
                'applicantId' => applicant.Id,
                'data' => new Map<String, Object>{
                    'incomeSource' => FINANCIALS,
                    'financialYear' => '2024-25'
                }
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
}