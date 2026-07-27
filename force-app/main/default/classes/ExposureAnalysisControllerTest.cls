@IsTest
private class ExposureAnalysisControllerTest {

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'QDE',
            Sub_Stage__c = 'Exposure Analysis',
            Product__c = '4W',
            Total_Loan_Amount__c = 1000000
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            In_Active_Applicant__c = false,
            Total_Exposure__c = 2500000
        );
        insert borrower;

        List<Applicant_Obligations__c> obligations = new List<Applicant_Obligations__c>{
            new Applicant_Obligations__c(
                Loan_Application__c = app.Id,
                Applicant__c = borrower.Id,
                Type__c = 'Borrower Exposure',
                Exposure_Type__c = 'Existing',
                Deal_No__c = 'TLN00348E',
                Deal_Stage__c = 'OLD',
                Deal_Date__c = Datetime.newInstance(2018, 7, 10),
                Type_of_Facility__c = 'E',
                Status_Flag__c = 'L',
                Finance_Amt__c = 25000000,
                SOH__c = 793803.32,
                Over_Due__c = -25279.54,
                Current_Demand__c = 819082.86,
                Lien_No__c = 'LN-TLN00348E-01',
                Lien_Type__c = 'Vehicle',
                Source_Deal_No__c = 'TLN00348E',
                Lien_Marking_Period__c = Date.newInstance(2018, 7, 10),
                Lien_Maker_Date__c = Date.newInstance(2018, 7, 15),
                Lien_Request_By__c = 'Credit Ops',
                Lien_Marking_Reason__c = 'Existing finance'
            ),
            new Applicant_Obligations__c(
                Loan_Application__c = app.Id,
                Applicant__c = borrower.Id,
                Type__c = 'Guarantor Exposure',
                Exposure_Type__c = 'Existing',
                Deal_No__c = 'TLN00460E',
                SOH__c = 1171490.05
            ),
            new Applicant_Obligations__c(
                Loan_Application__c = app.Id,
                Applicant__c = borrower.Id,
                Type__c = 'Borrower Exposure',
                Exposure_Type__c = 'Current',
                Deal_No__c = 'CURR001',
                SOH__c = 50000
            ),
            new Applicant_Obligations__c(
                Loan_Application__c = app.Id,
                Applicant__c = borrower.Id,
                Type__c = 'External Exposure',
                Account_Type__c = 'AL',
                Account_Type_Desc__c = 'Auto Loan',
                Ownership__c = 'Individual',
                High_Credit__c = 400000,
                Current_Balance__c = 180000,
                Amount_Overdue__c = 5000,
                Financier_Name__c = 'HDFC Bank'
            )
        };
        insert obligations;
    }

    private static Map<String, Object> call(String action, Map<String, Object> args) {
        return (Map<String, Object>) new ExposureAnalysisController().call(action, args);
    }

    private static Applicant__c borrower() {
        return [
            SELECT Id
            FROM Applicant__c
            WHERE Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
    }

    @IsTest
    static void testGetExposureAnalysisData() {
        Applicant__c applicant = borrower();

        Test.startTest();
        Map<String, Object> result = call('getExposureAnalysisData', new Map<String, Object>{
            'applicantId' => applicant.Id
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testExposurePayloadIncludesLien() {
        Applicant__c applicant = borrower();

        Test.startTest();
        Map<String, Object> result = call('getExposureAnalysisData', new Map<String, Object>{
            'applicantId' => applicant.Id
        });
        Test.stopTest();

        List<Object> exposures = (List<Object>) result.get('exposures');
        Map<String, Object> lienRow = null;
        for (Object rowObject : exposures) {
            Map<String, Object> row = (Map<String, Object>) rowObject;
            if (row.get('lien') != null) {
                lienRow = (Map<String, Object>) row.get('lien');
                break;
            }
        }

        System.assertEquals('LN-TLN00348E-01', lienRow.get('lienNo'));
    }

    @IsTest
    static void testExternalExposureRowsReturned() {
        Applicant__c applicant = borrower();

        Test.startTest();
        Map<String, Object> result = call('getExposureAnalysisData', new Map<String, Object>{
            'applicantId' => applicant.Id
        });
        Test.stopTest();

        System.assertEquals(1, ((List<Object>) result.get('externalExposures')).size());
    }

    @IsTest
    static void testSaveExposureSummary() {
        Applicant__c applicant = borrower();

        Test.startTest();
        Map<String, Object> result = call('saveExposureSummary', new Map<String, Object>{
            'applicantId' => applicant.Id,
            'totalExposure' => 2750000
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void testUnknownActionReturnsFailure() {
        Test.startTest();
        Map<String, Object> result = call('unsupportedAction', new Map<String, Object>());
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void testSaveExposureSummaryRequiresApplicant() {
        Test.startTest();
        Map<String, Object> result = call('saveExposureSummary', new Map<String, Object>{
            'totalExposure' => 100
        });
        Test.stopTest();

        System.assertEquals('Applicant Id is required.', result.get('message'));
    }

    @IsTest
    static void testGetExposureWithNullApplicant() {
        Test.startTest();
        Map<String, Object> result = call('getExposureAnalysisData', new Map<String, Object>());
        Test.stopTest();

        System.assertEquals(0, ((List<Object>) result.get('exposures')).size());
    }
}