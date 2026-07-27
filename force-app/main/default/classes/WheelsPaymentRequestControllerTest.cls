/**
 * @description Test coverage for WheelsPaymentRequestController — page load,
 *              save (disbursement, asset, beneficiaries, adjustments), stage
 *              rollback, and Callable routing.
 */
@IsTest
private class WheelsPaymentRequestControllerTest {

    private class TestContext {
        Application__c           application;
        Applicant__c             borrower;
        Application_Line_Item__c lineItem;
    }

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c     = 'Post Sanction Sales',
            Sub_Stage__c = 'Payment Request'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c    = app.Id,
            Applicant_Type__c = 'Borrower'
        );
        insert borrower;

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c    = app.Id,
            Loan_Amount__c    = 500000,
            Holiday_period__c = '0',
            First_EMI_Date__c = Date.today().addMonths(1),
            Second_EMI_Date__c = Date.today().addMonths(2)
        );
        insert lineItem;

        insert new Asset__c(
            Applicant__c                     = borrower.Id,
            Vehicle_Type__c                  = 'New',
            Vehicle_Registration_number__c = 'MH01AB1234',
            Engine_number__c                 = 'ENG123',
            Chassis_number__c                = 'CHS456'
        );

        insert new Disbursement_Details__c(
            Application_Line_Items__c  = lineItem.Id,
            Payment_Originated_From__c = 'Branch',
            Are_all_details_correct__c = 'Yes',
            Remarks__c                 = 'Initial disbursement setup'
        );

        insert new Loan_Beneficiary__c(
            Application__c      = app.Id,
            Beneficiary_Name__c = 'Dealer ABC',
            Account_Number__c   = '1234567890',
            IFSC_Code__c        = 'HDFC0001234',
            Amount__c           = 450000
        );

        insert new Payment_Adjustment__c(
            Application__c   = app.Id,
            Deal_Number__c   = 'DEAL-001',
            Customer_Name__c = 'Prior Customer',
            Customer_Code__c = 'CUST001',
            Amount__c        = 10000
        );
    }

    private static TestContext getContext() {
        Application__c app = [
            SELECT Id FROM Application__c ORDER BY CreatedDate DESC LIMIT 1
        ];
        Applicant__c borrower = [
            SELECT Id FROM Applicant__c
            WHERE Application__c = :app.Id AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        Application_Line_Item__c lineItem = [
            SELECT Id FROM Application_Line_Item__c
            WHERE Application__c = :app.Id
            LIMIT 1
        ];
        TestContext ctx = new TestContext();
        ctx.application = app;
        ctx.borrower    = borrower;
        ctx.lineItem    = lineItem;
        return ctx;
    }

    private static String jsonPayload(Map<String, Object> fields) {
        return JSON.serialize(fields);
    }

    // ── getPageData ───────────────────────────────────────────────────────────

    @IsTest
    static void getPageData_nullRecordId_returnsShellResult() {
        WheelsPaymentRequestController.PageDataResult result =
            WheelsPaymentRequestController.getPageData(jsonPayload(new Map<String, Object>()));

        System.assertNotEquals(null, result.currentUserId);
        System.assertEquals(UserInfo.getUserId(), result.currentUserId);
        System.assertEquals(0, result.beneficiaryRows.size());
        System.assertEquals(0, result.adjustmentRows.size());
        System.assertNotEquals(null, result.doIssuanceModeOptions);
    }

    @IsTest
    static void getPageData_withApplication_returnsRelatedRecords() {
        TestContext ctx = getContext();
        String payload = jsonPayload(new Map<String, Object>{ 'recordId' => ctx.application.Id });

        Test.startTest();
        WheelsPaymentRequestController.PageDataResult result =
            WheelsPaymentRequestController.getPageData(payload);
        Test.stopTest();

        System.assertNotEquals(null, result.lineItem);
        System.assertNotEquals(null, result.disbursementDetails);
        System.assertNotEquals(null, result.asset);
        System.assertEquals(1, result.beneficiaryRows.size());
        System.assertEquals(1, result.adjustmentRows.size());
        System.assertEquals('Dealer ABC', result.beneficiaryRows[0].Beneficiary_Name__c);
    }

    // ── savePaymentRequest ────────────────────────────────────────────────────

    @IsTest
    static void savePaymentRequest_applicationNotFound_returnsMessage() {
        Application__c temp = new Application__c(Stage__c = 'DDE');
        insert temp;
        Id tempId = temp.Id;
        delete temp;

        String payload = jsonPayload(new Map<String, Object>{
            'recordId'        => tempId,
            'businessPayment' => new Map<String, Object>(),
            'disbursement'    => new Map<String, Object>(),
            'vehicleDetails'  => new Map<String, Object>(),
            'beneficiaryRows' => new List<Object>(),
            'adjustmentRows'  => new List<Object>(),
            'operationData'   => new Map<String, Object>()
        });

        Map<String, Object> result = WheelsPaymentRequestController.savePaymentRequest(payload);
        System.assertEquals(false, result.get('success'));
        System.assertEquals('Application record not found.', result.get('message'));
    }

    @IsTest
    static void savePaymentRequest_persistsAllSections() {
        TestContext ctx = getContext();
        String payload = jsonPayload(new Map<String, Object>{
            'recordId' => ctx.application.Id,
            'businessPayment' => new Map<String, Object>{
                'paymentOriginatedFrom'   => 'Branch',
                'vehicleSoldBy'           => 'Dealer',
                'collectionExecutive'     => 'Exec-1',
                'doIssuance'              => getFirstPicklistValue('Disbursement_Details__c', 'Do_Issuance_Mode__c'),
                'purchaseDocCategory'     => getFirstPicklistValue('Disbursement_Details__c', 'Purchase_Document_Category__c'),
                'fundEndUse'              => getFirstPicklistValue('Disbursement_Details__c', 'Fund_End_Use__c'),
                'vehicleRegisteredInName' => 'Borrower',
                'balanceTransfer'         => 0,
                'originalPurchaseValue'   => 550000,
                'originalPurchaseDate'    => String.valueOf(Date.today().addYears(-1))
            },
            'disbursement' => new Map<String, Object>{
                'paymentDate'     => String.valueOf(Date.today().addDays(7)),
                'firstEmiDueDate' => '10'
            },
            'vehicleDetails' => new Map<String, Object>{
                'regNumber'           => 'MH02CD5678',
                'engineNumber'        => 'ENG999',
                'chassisNumber'       => 'CHS888',
                'isNameTransferred'   => 'Yes',
                'currentVehicleOwner' => 'Borrower',
                'nowLienInTheNameOf'  => 'Bandhan Bank',
                'lienMarked'          => 'Yes',
                'markedOn'            => String.valueOf(Date.today()),
                'rtaTaxRemittedUpto'  => String.valueOf(Date.today().addMonths(6))
            },
            'beneficiaryRows' => new List<Object>{
                new Map<String, Object>{
                    'name'          => 'New Beneficiary',
                    'accountNumber' => '9988776655',
                    'ifscCode'      => 'SBIN0001234',
                    'amount'        => 480000
                }
            },
            'adjustmentRows' => new List<Object>{
                new Map<String, Object>{
                    'dealNumber'   => 'DEAL-NEW',
                    'customerName' => 'Adjustment Customer',
                    'customerCode' => 'ADJ001',
                    'amount'       => 15000
                }
            },
            'operationData' => new Map<String, Object>{
                'areAllDetailsCorrect' => 'Yes',
                'remarks'              => 'Payment request saved in test'
            }
        });

        Test.startTest();
        Map<String, Object> result = WheelsPaymentRequestController.savePaymentRequest(payload);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), String.valueOf(result.get('message')));

        Disbursement_Details__c dd = [
            SELECT Payment_Originated_From__c, Remarks__c
            FROM Disbursement_Details__c
            WHERE Application_Line_Items__c = :ctx.lineItem.Id
            LIMIT 1
        ];
        System.assertEquals('Branch', dd.Payment_Originated_From__c);
        System.assertEquals('Payment request saved in test', dd.Remarks__c);

        Asset__c asset = [
            SELECT Vehicle_Registration_number__c, Lien_marked_to_bank__c
            FROM Asset__c
            WHERE Applicant__c = :ctx.borrower.Id
            LIMIT 1
        ];
        System.assertEquals('MH02CD5678', asset.Vehicle_Registration_number__c);
        System.assertEquals(true, asset.Lien_marked_to_bank__c);

        Application_Line_Item__c li = [
            SELECT First_EMI_Date__c, Second_EMI_Date__c
            FROM Application_Line_Item__c
            WHERE Id = :ctx.lineItem.Id
        ];
        System.assertNotEquals(null, li.First_EMI_Date__c);
        System.assertEquals(li.First_EMI_Date__c.addMonths(1), li.Second_EMI_Date__c);

        System.assertEquals(1, [
            SELECT COUNT() FROM Loan_Beneficiary__c WHERE Application__c = :ctx.application.Id
        ]);
        System.assertEquals('New Beneficiary', [
            SELECT Beneficiary_Name__c FROM Loan_Beneficiary__c
            WHERE Application__c = :ctx.application.Id LIMIT 1
        ].Beneficiary_Name__c);

        System.assertEquals(1, [
            SELECT COUNT() FROM Payment_Adjustment__c WHERE Application__c = :ctx.application.Id
        ]);
        System.assertEquals('DEAL-NEW', [
            SELECT Deal_Number__c FROM Payment_Adjustment__c
            WHERE Application__c = :ctx.application.Id LIMIT 1
        ].Deal_Number__c);
    }

    // ── moveBackToPssStage ────────────────────────────────────────────────────

    @IsTest
    static void moveBackToPssStage_updatesApplicationAndDisbursement() {
        TestContext ctx = getContext();
        String payload = jsonPayload(new Map<String, Object>{
            'applicationId'        => ctx.application.Id,
            'areAllDetailsCorrect' => 'No',
            'remarks'              => 'Rollback from payment request'
        });

        Test.startTest();
        Map<String, Object> result = WheelsPaymentRequestController.moveBackToPssStage(payload);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), String.valueOf(result.get('message')));
        System.assertEquals('Post Sanction Sales', [
            SELECT Stage__c FROM Application__c WHERE Id = :ctx.application.Id
        ].Stage__c);

        Disbursement_Details__c dd = [
            SELECT Are_all_details_correct__c, Remarks__c
            FROM Disbursement_Details__c
            WHERE Application_Line_Items__c = :ctx.lineItem.Id
            LIMIT 1
        ];
        System.assertEquals('No', dd.Are_all_details_correct__c);
        System.assertEquals('Rollback from payment request', dd.Remarks__c);
    }

    // ── Callable routing ──────────────────────────────────────────────────────

    @IsTest
    static void callable_routesPageLoadAndSave() {
        TestContext ctx = getContext();
        WheelsPaymentRequestController controller = new WheelsPaymentRequestController();

        Map<String, Object> pageData = (Map<String, Object>) controller.call(
            'getPageData',
            new Map<String, Object>{ 'recordId' => ctx.application.Id }
        );
        System.assertNotEquals(null, pageData.get('lineItem'));

        Map<String, Object> saveResult = (Map<String, Object>) controller.call(
            'savePaymentRequest',
            new Map<String, Object>{
                'recordId'        => ctx.application.Id,
                'businessPayment' => new Map<String, Object>{ 'paymentOriginatedFrom' => 'Online' },
                'operationData'   => new Map<String, Object>{ 'remarks' => 'Callable save' }
            }
        );
        System.assertEquals(true, saveResult.get('success'), String.valueOf(saveResult.get('message')));
    }

    @IsTest
    static void callable_moveBackToPssStage_returnsSuccess() {
        TestContext ctx = getContext();
        WheelsPaymentRequestController controller = new WheelsPaymentRequestController();

        Map<String, Object> result = (Map<String, Object>) controller.call(
            'moveBackToPssStage',
            new Map<String, Object>{
                'applicationId'        => ctx.application.Id,
                'areAllDetailsCorrect' => 'Yes',
                'remarks'              => 'Callable rollback'
            }
        );
        System.assertEquals(true, result.get('success'), String.valueOf(result.get('message')));
    }

    @IsTest
    static void callable_unknownAction_throws() {
        WheelsPaymentRequestController controller = new WheelsPaymentRequestController();
        Boolean thrown = false;
        try {
            controller.call('badAction', new Map<String, Object>());
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assertEquals(ex.getMessage(), 'Script-thrown exception');
        }
        System.assert(thrown);
    }

    private static String getFirstPicklistValue(String objectName, String fieldName) {
        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectName);
        if (sObjType == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldName)) {
            return null;
        }
        for (Schema.PicklistEntry entry : fieldMap.get(fieldName).getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }
}