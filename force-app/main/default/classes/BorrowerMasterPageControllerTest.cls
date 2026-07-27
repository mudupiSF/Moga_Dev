/**
 * @description Test coverage for BorrowerMasterPageController.
 */
@IsTest
private class BorrowerMasterPageControllerTest {

    @TestSetup
    static void setupData() {
        Account branch = new Account(
            Name = 'Borrower Test Branch'
        );
        insert branch;

        Application__c application = new Application__c(
            Name = 'Borrower Test Application',
            Stage__c = 'DDE',
            Sub_Stage__c = 'Offer',
            Product__c = '2W',
            Branch__c = branch.Id,
            Total_Loan_Amount__c = 500000,
            Sanction_Date__c = Date.today(),
            Sanction_Status__c = 'STP'
        );
        insert application;

        Applicant__c borrower = new Applicant__c(
            Application__c = application.Id,
            Applicant_Type__c = 'Borrower',
            Type__c = 'Individual',
            Profile__c = 'Salaried',
            Is_Income_Available__c = 'Yes',
            Declared_income__c = 600000,
            Is_PAN_Available__c = 'Yes',
            Customer_First_Name__c = 'John',
            Customer_Last_Name__c = 'Doe',
            PAN_Number__c = 'ABCDE1234F',
            Date_of_Birth__c = Date.newInstance(1990, 1, 15),
            Phone__c = '9876543210',
            Email__c = 'john.doe@example.com',
            Phone_Verified__c = true,
            Email_Verified__c = false,
            In_Active_Applicant__c = false
        );
        insert borrower;

        insert new Asset__c(
            Applicant__c = borrower.Id,
            Name = 'Borrower Vehicle',
            Vehicle_type__c = 'New',
            Product_Segment__c = 'Motorcycle',
            Purpose_of_purchase__c = 'Personal'
        );

        ContentVersion cv = new ContentVersion(
            Title = 'PAN Upload',
            PathOnClient = 'pan.pdf',
            VersionData = Blob.valueOf('test-pdf'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id];

        insert new Document_Checklist__c(
            Applicant__c = borrower.Id,
            Document_Type__c = 'Initial_DOC_Verification',
            Name = 'PAN Card',
            Application__c = application.Id,
            ContentVersionId__c = cv.Id
        );
    }

    private static Application__c application() {
        return [SELECT Id, Branch__c FROM Application__c LIMIT 1];
    }

    private static Applicant__c borrower() {
        return [SELECT Id FROM Applicant__c WHERE Applicant_Type__c = 'Borrower' LIMIT 1];
    }

    private static Map<String, Object> call(String action, Map<String, Object> args) {
        return (Map<String, Object>) new BorrowerMasterPageController().call(action, args);
    }

    @IsTest
    static void getBorrowerPageData_blankRecordId_returnsEmptySections() {
        Test.startTest();
        Map<String, Object> result = BorrowerMasterPageController.getBorrowerPageData('');
        Test.stopTest();

        System.assertEquals(0, ((List<Object>) result.get('loanBasicInfo')).size());
        System.assertEquals(0, ((List<Object>) result.get('loanDetail')).size());
        System.assertEquals(0, ((List<Object>) result.get('professionalDetail')).size());
    }

    @IsTest
    static void getBorrowerPageData_returnsFlattenedFields() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = BorrowerMasterPageController.getBorrowerPageData(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.get('applicantTypeOptionsMap'));
        System.assertEquals('2W', result.get('productType'));
        System.assertEquals('Borrower', result.get('applicantType'));
        System.assertEquals('John', result.get('extractedFirstName'));
        System.assertEquals('ABCDE1234F', result.get('extractedPanCardNumber'));
        System.assertEquals('success', result.get('pancardVerificationStatus'));
        System.assertEquals('Motorcycle', result.get('segment'));
        System.assertEquals('Salaried', result.get('profileType'));
        System.assertEquals('9876543210', result.get('contactNumber'));
    }

    @IsTest
    static void getBorrowerPageData_nonIndividual_setsEntityName() {
        Application__c app = application();
        Applicant__c borrowerRec = borrower();
        borrowerRec.Applicant_Type__c = 'Borrower';
        borrowerRec.Company_Name__c = 'Acme Corp';
        update borrowerRec;

        Test.startTest();
        Map<String, Object> result = BorrowerMasterPageController.getBorrowerPageData(app.Id);
        Test.stopTest();

        System.assertEquals('Acme Corp', result.get('entityName'));
    }

    @IsTest
    static void getBorrowerPageData_viaCallable() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = call('getBorrowerPageData', new Map<String, Object>{ 'recordId' => app.Id });
        Test.stopTest();

        System.assertEquals('2W', result.get('productType'));
    }

    @IsTest
    static void saveBorrowerPageData_success() {
        Application__c app = application();
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];

        Test.startTest();
        Map<String, Object> result = call('saveBorrowerPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'requiredLoanAmount' => '750000',
            'profileType' => 'Self Employed',
            'annualIncome' => '800000',
            'incomeAvailable' => 'Yes',
            'contactNumber' => '9998887776',
            'email' => 'updated@example.com',
            'phoneVerified' => 'true',
            'sanctionStatus' => 'Approved',
            'purposeOfPurchase' => 'Commercial',
            'segment' => 'Scooter',
            'panCardUploadElement' => new Map<String, Object>{
                'contentVersionId' => cv.Id,
                'fileName' => 'updated-pan.pdf'
            }
        });
        Test.stopTest();

        Application__c updatedApp = [
            SELECT Total_Loan_Amount__c, Sanction_Status__c
            FROM Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals(500000, updatedApp.Total_Loan_Amount__c);
        System.assertEquals('STP', updatedApp.Sanction_Status__c);

        Applicant__c updatedBorrower = [
            SELECT Profile__c, Phone__c, Declared_income__c
            FROM Applicant__c
            WHERE Id = :borrower().Id
        ];
        System.assertEquals('Salaried', updatedBorrower.Profile__c);
        System.assertEquals('9876543210', updatedBorrower.Phone__c);
    }

    @IsTest
    static void saveBorrowerPageData_nonIndividualEntity() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = call('saveBorrowerPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'applicationType' => 'Non Individual',
            'entityName' => 'Global Traders LLP'
        });
        Test.stopTest();

        Applicant__c updatedBorrower = [
            SELECT Company_Name__c
            FROM Applicant__c
            WHERE Id = :borrower().Id
        ];
    }

    @IsTest
    static void saveBorrowerPageData_jsonFileField() {
        Application__c app = application();
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];
        String fileJson = JSON.serialize(new Map<String, Object>{
            'contentVersionId' => cv.Id,
            'fileName' => 'json-pan.pdf'
        });

        Test.startTest();
        Map<String, Object> result = call('saveBorrowerPageData', new Map<String, Object>{
            'recordId' => app.Id,
            'panCardUploadElement' => fileJson
        });
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void saveBorrowerPageData_missingRecordId() {
        Test.startTest();
        Map<String, Object> result = call('saveBorrowerPageData', new Map<String, Object>());
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
        System.assert(((String) result.get('message')).contains('Record ID is required'));
    }

    @IsTest
    static void savePANDetails_success() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = BorrowerMasterPageController.savePANDetails(
            app.Id,
            'FGHIJ5678K',
            '1985-06-20',
            'Jane',
            'Smith'
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
        Applicant__c updated = [
            SELECT PAN_Number__c, Customer_First_Name__c, Customer_Last_Name__c, Date_of_Birth__c
            FROM Applicant__c
            WHERE Id = :borrower().Id
        ];
        System.assertEquals('FGHIJ5678K', updated.PAN_Number__c);
        System.assertEquals('Jane', updated.Customer_First_Name__c);
        System.assertEquals(Date.newInstance(1985, 6, 20), updated.Date_of_Birth__c);
    }

    @IsTest
    static void savePANDetails_borrowerNotFound() {
        Application__c app = new Application__c(
            Name = 'No Borrower App',
            Stage__c = 'DDE',
            Sub_Stage__c = 'Offer',
            Product__c = '2W'
        );
        insert app;

        Test.startTest();
        Map<String, Object> result = BorrowerMasterPageController.savePANDetails(
            app.Id,
            'FGHIJ5678K',
            '1985-06-20',
            'Jane',
            'Smith'
        );
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
        System.assert(((String) result.get('message')).contains('Borrower not found'));
    }

    @IsTest
    static void savePANDetails_invalidDate_returnsError() {
        Application__c app = application();

        Test.startTest();
        Map<String, Object> result = BorrowerMasterPageController.savePANDetails(
            app.Id,
            'FGHIJ5678K',
            'not-a-date',
            'Jane',
            'Smith'
        );
        Test.stopTest();

        System.assertEquals(false, result.get('isSuccess'));
        System.assertNotEquals(null, result.get('message'));
    }

    @IsTest
    static void getAgentBranchName_blankInputs_returnNA() {
        System.assertEquals('N/A', BorrowerMasterPageController.getAgentBranchName('', null, null));
        System.assertEquals('N/A', BorrowerMasterPageController.getAgentBranchName('001000000000000', '', '2W'));
    }

    @IsTest
    static void getAgentBranchName_derivesBranchName() {
        Application__c app = application();

        Test.startTest();
        String branchName = BorrowerMasterPageController.getAgentBranchName(
            app.Id,
            app.Branch__c,
            '2W'
        );
        String invalidAccountName = BorrowerMasterPageController.getAgentBranchName(
            app.Id,
            '001000000000000AAA',
            '2W'
        );
        Test.stopTest();

        System.assertEquals('N/A', invalidAccountName);
    }

    @IsTest
    static void call_unknownAction_throws() {
        Boolean thrown = false;
        try {
            call('unknownAction', new Map<String, Object>());
        } catch (CalloutException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Unknown action'));
        }
        System.assertEquals(true, thrown);
    }
}