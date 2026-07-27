@IsTest
private class PostDisbursementTrackingControllerTest {
    @TestSetup
    static void testSetupMethod() {
        Application__c application = new Application__c(
            Stage__c = 'Post Disbursement',
            Sub_Stage__c = 'Post-Disbursement Tracking'
        );
        insert application;

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = application.Id,
            Loan_Amount__c = 500000,
            Holiday_period__c = '0',
            First_EMI_Date__c = Date.today().addDays(10),
            Second_EMI_Date__c = Date.today().addDays(40),
            EMI_Amount__c = 27850,
            Tenure__c = 36
        );
        insert lineItem;

        insert new Disbursement_Details__c(
            Application_Line_Items__c = lineItem.Id,
            Payment_Originated_From__c = 'HUB',
            Payment_to_be_made_on__c = Date.today().addDays(-35)
        );

        insert new Repayment_Mandate__c(
            Name = 'Repayment Mandate - Test',
            Application__c = application.Id,
            Application_Line_Items__c = lineItem.Id,
            Repayment_Method__c = 'e-NACH',
            EMI_Amount__c = 27850,
            lst_EMI_Due_Date__c = Date.today().addDays(15),
            E_Nach_Session__c = 'NACH-TEST-SESSION',
            Account_Number__c = '50200987654321',
            E_NACH_API_Status__c = 'NACH Active'
        );

        insert new List<Document_CheckList__c>{
            new Document_CheckList__c(
                Application__c = application.Id,
                Application_Line_Items__c = lineItem.Id,
                Document_Type__c = 'RC copy',
                ContentVersionId__c = '068000000000001AAA',
                Is_Active__c = true
            ),
            new Document_CheckList__c(
                Application__c = application.Id,
                Application_Line_Items__c = lineItem.Id,
                Document_Type__c = 'Insurance policy',
                ContentVersionId__c = '068000000000002AAA',
                Is_Active__c = true
            )
        };
    }

    @IsTest
    static void getPageData_noRecord() {
        Test.startTest();
        Map<String, Object> response = (Map<String, Object>) new PostDisbursementTrackingController()
            .call('getPageData', new Map<String, Object>());
        Test.stopTest();

        System.assertEquals(false, response.get('isSuccess'));
        System.assertEquals('Application record ID is required.', response.get('loadError'));
    }

    @IsTest
    static void getPageData_scope() {
        Application__c application = [SELECT Id FROM Application__c LIMIT 1];
        Application_Line_Item__c lineItem = [
            SELECT Id, Stage_Completed__c
            FROM Application_Line_Item__c
            WHERE Application__c = :application.Id
            LIMIT 1
        ];
        Repayment_Mandate__c mandate = [
            SELECT Id
            FROM Repayment_Mandate__c
            WHERE Application_Line_Items__c = :lineItem.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Test.startTest();
        Map<String, Object> response = (Map<String, Object>) new PostDisbursementTrackingController()
            .call(
                'getPageData',
                new Map<String, Object>{
                    'recordId' => application.Id,
                    'applicationLineItemId' => lineItem.Id
                }
            );
        Test.stopTest();

        System.assertEquals(true, response.get('isSuccess'));
        System.assertEquals(lineItem.Id, response.get('applicationLineItemId'));
        System.assertEquals(false, response.get('handoverClosed'));

        Map<String, Object> repaymentSetup = (Map<String, Object>) response.get('repaymentSetup');
        System.assertNotEquals(null, repaymentSetup);
        System.assertEquals('NACH Active', repaymentSetup.get('mandate'));
        System.assertEquals(mandate.Id, repaymentSetup.get('mandateReference'));
        System.assertEquals('e-NACH', repaymentSetup.get('repaymentMode'));
        System.assertEquals(500, repaymentSetup.get('bounceChargeRule'));

        List<Object> pddDocuments = (List<Object>) response.get('pddDocuments');
        System.assertEquals(5, pddDocuments.size());

        Integer receivedCount = 0;
        Integer pendingCount = 0;
        Integer maxAgeingDays = 0;
        Date expectedDate = null;
        for (Object rowObj : pddDocuments) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            String status = String.valueOf(row.get('status'));
            if (status == 'Received') {
                receivedCount++;
            }
            if (status == 'Pending') {
                pendingCount++;
            }
            Integer ageing = Integer.valueOf(String.valueOf(row.get('ageingDays')));
            if (ageing > maxAgeingDays) {
                maxAgeingDays = ageing;
            }
            if (String.valueOf(row.get('id')) == 'invoice') {
                expectedDate = (Date) row.get('expectedDate');
            }
        }
        System.assertEquals(2, receivedCount);
        System.assertEquals(3, pendingCount);
        System.assert(maxAgeingDays > 0);
        System.assertEquals(Date.today().addDays(-5), expectedDate);
    }

    @IsTest
    static void saveTrackingState_notClosed() {
        Application__c application = [SELECT Id FROM Application__c LIMIT 1];
        Application_Line_Item__c lineItem = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Application__c = :application.Id
            LIMIT 1
        ];

        Test.startTest();
        Map<String, Object> response = (Map<String, Object>) new PostDisbursementTrackingController()
            .call(
                'saveTrackingState',
                new Map<String, Object>{
                    'recordId' => application.Id,
                    'applicationLineItemId' => lineItem.Id,
                    'handoverClosed' => false
                }
            );
        Test.stopTest();

        System.assertEquals(false, response.get('isSuccess'));
        System.assertEquals('Handover must be closed before saving.', response.get('loadError'));
    }

    @IsTest
    static void saveTrackingState_marksStage() {
        Application__c application = [SELECT Id FROM Application__c LIMIT 1];
        Application_Line_Item__c lineItem = [
            SELECT Id, Stage_Completed__c
            FROM Application_Line_Item__c
            WHERE Application__c = :application.Id
            LIMIT 1
        ];

        Test.startTest();
        Map<String, Object> response = (Map<String, Object>) new PostDisbursementTrackingController()
            .call(
                'saveTrackingState',
                new Map<String, Object>{
                    'recordId' => application.Id,
                    'applicationLineItemId' => lineItem.Id,
                    'handoverClosed' => true
                }
            );
        Test.stopTest();

        System.assertEquals(true, response.get('isSuccess'));
        System.assertEquals(true, response.get('handoverClosed'));

        Application_Line_Item__c updatedLineItem = [
            SELECT Stage_Completed__c
            FROM Application_Line_Item__c
            WHERE Id = :lineItem.Id
            LIMIT 1
        ];

        String stageValue = String.valueOf(updatedLineItem.Stage_Completed__c);
        Boolean containsTrackingStage = stageValue != null &&
            (
                stageValue.contains('Post_Disbursement_Tracking') ||
                stageValue.contains('Post-Disbursement Tracking')
            );
        System.assertEquals(true, containsTrackingStage);
    }

    @IsTest
    static void getPageData_marksUploadedWhenOnlyContentDocumentLinkExists() {
        Application__c application = [SELECT Id FROM Application__c LIMIT 1];
        Application_Line_Item__c lineItem = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Application__c = :application.Id
            LIMIT 1
        ];

        Document_CheckList__c deliveryChecklist = new Document_CheckList__c(
            Application__c = application.Id,
            Application_Line_Items__c = lineItem.Id,
            Document_Type__c = 'Delivery challan',
            Is_Active__c = true
        );
        insert deliveryChecklist;

        ContentVersion version = new ContentVersion(
            Title = 'Delivery challan file',
            PathOnClient = 'delivery-challan.pdf',
            VersionData = Blob.valueOf('test delivery challan')
        );
        insert version;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            LinkedEntityId = deliveryChecklist.Id,
            ContentDocumentId = insertedVersion.ContentDocumentId,
            ShareType = 'V'
        );

        Test.startTest();
        Map<String, Object> response = (Map<String, Object>) new PostDisbursementTrackingController()
            .call(
                'getPageData',
                new Map<String, Object>{
                    'recordId' => application.Id,
                    'applicationLineItemId' => lineItem.Id
                }
            );
        Test.stopTest();

        List<Object> pddDocuments = (List<Object>) response.get('pddDocuments');
        String deliveryStatus = null;
        for (Object rowObj : pddDocuments) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            if (String.valueOf(row.get('id')) == 'delivery') {
                deliveryStatus = String.valueOf(row.get('status'));
                break;
            }
        }

        System.assertEquals('Received', deliveryStatus);
    }
}