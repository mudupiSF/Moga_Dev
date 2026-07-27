/**
 * @description Test coverage for OfferPageController — offer engine, repayment,
 *              insurance, highlight panel, pay-in/payout, and Callable routing.
 */
@IsTest
private class OfferPageControllerTest {

    private class TestContext {
        Application__c           application;
        Applicant__c             borrower;
        Application_Line_Item__c lineItem;
    }

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c     = 'DDE',
            Sub_Stage__c = 'Offer'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c    = app.Id,
            Applicant_Type__c = 'Borrower',
            Email__c          = 'borrower@test.com',
            Email_Verified__c = false
        );
        Applicant__c coBorrower = new Applicant__c(
            Application__c    = app.Id,
            Applicant_Type__c = 'Co-Borrower'
        );
        insert new List<Applicant__c>{ borrower, coBorrower };

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c           = app.Id,
            Loan_Amount__c           = 500000,
            CRM_IRR__c               = 12,
            Tenure__c                = 12,
            EMI_Amount__c            = 44424.89,
            Holiday_period__c        = '0',
            First_EMI_Date__c        = Date.today().addMonths(1).toStartOfMonth().addDays(4),
            Second_EMI_Date__c       = Date.today().addMonths(2).toStartOfMonth().addDays(4),
            Service_charges__c       = 5000,
            Documentation_charges__c = 1500,
            Stamping_charges__c      = 800,
            Stamping_Done_By__c      = 'Customer',
            Cess_Charges__c          = 200
        );
        insert lineItem;

        insert new List<Applicant_Income__c>{
            new Applicant_Income__c(
                Applicant__c                  = borrower.Id,
                Name                          = 'Declared Income',
                Consolidated_Yearly_Income__c = 600000
            ),
            new Applicant_Income__c(
                Applicant__c                  = borrower.Id,
                Name                          = 'Bank Statement',
                Consolidated_Yearly_Income__c = 550000
            ),
            new Applicant_Income__c(
                Applicant__c                  = borrower.Id,
                Name                          = 'Mobile Number',
                Consolidated_Yearly_Income__c = 520000
            )
        };

        insert new Insurance__c(
            Applicant__c         = borrower.Id,
            Name                 = 'Life Cover',
            Insurance_Plan__c    = 'Life',
            Amount__c            = 500000,
            Funded_Non_funded__c = 'Funded',
            Funded_Premium__c    = 2500,
            Is_Active__c         = true
        );

        insert new Repayment_Schedule__c(
            Application_Line_Items__c = lineItem.Id,
            Number_of_Installments__c = 1,
            Installment_Type__c       = 'Equated',
            EMI_Due_Date__c           = lineItem.First_EMI_Date__c,
            Opening_Principal__c      = 500000,
            EMI_Amount__c             = 44424.89,
            Principal_Component__c    = 40000,
            Interest_Component__c     = 4424.89,
            Closing_Principal__c      = 460000
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
            SELECT Id, First_EMI_Date__c, Holiday_period__c, Loan_Amount__c,
                   CRM_IRR__c, Tenure__c, EMI_Amount__c
            FROM Application_Line_Item__c
            WHERE Application__c = :app.Id
            LIMIT 1
        ];
        TestContext ctx = new TestContext();
        ctx.application = app;
        ctx.borrower    = borrower;
        ctx.lineItem    = lineItem;
        return ctx;
    }

    // ── resetToIncomeVerification ───────────────────────────────────────────

    @IsTest
    static void resetToIncomeVerification_blankId_returnsMessage() {
        Map<String, Object> result = OfferPageController.resetToIncomeVerification(null);
        System.assertEquals(false, result.get('success'));
        System.assertEquals('Application ID is required.', result.get('message'));
    }

    @IsTest
    static void resetToIncomeVerification_success_updatesStage() {
        TestContext ctx = getContext();

        Test.startTest();
        Map<String, Object> result = OfferPageController.resetToIncomeVerification(ctx.application.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), String.valueOf(result.get('message')));
        Application__c updated = [
            SELECT Stage__c, Sub_Stage__c FROM Application__c WHERE Id = :ctx.application.Id
        ];
        System.assertEquals('DDE', updated.Stage__c);
        System.assertEquals('Income Details', updated.Sub_Stage__c);
    }

    // ── getOfferData ──────────────────────────────────────────────────────────

    @IsTest
    static void getOfferData_blankId_returnsNoOffer() {
        Map<String, Object> result = OfferPageController.getOfferData('');
        System.assertEquals(false, result.get('hasOffer'));
    }

    @IsTest
    static void getOfferData_withLineItem_returnsOfferAndIncome() {
        TestContext ctx = getContext();

        Map<String, Object> result = OfferPageController.getOfferData(ctx.application.Id);

        System.assertEquals(true, result.get('hasOffer'));
        System.assertEquals(50000, result.get('minLoanAmount'));
        System.assertEquals(200000000, result.get('maxLoanAmount'));
        System.assertEquals(600000, result.get('declaredIncomeOffer'));
        System.assertEquals(550000, result.get('bankStatementOffer'));
        System.assertEquals(520000, result.get('bureauSurrogateOffer'));
        System.assertNotEquals(null, result.get('lineItem'));
    }

    // ── saveOfferEngineResult ─────────────────────────────────────────────────

    @IsTest
    static void saveOfferEngineResult_blankJson_returnsMessage() {
        Map<String, Object> result = OfferPageController.saveOfferEngineResult(null);
        System.assertEquals(false, result.get('isSuccess'));
        System.assertEquals('Data is required.', result.get('message'));
    }

    @IsTest
    static void saveOfferEngineResult_missingApplicationId_returnsMessage() {
        String payload = JSON.serialize(new Map<String, Object>{ 'loanAmount' => 600000 });
        Map<String, Object> result = OfferPageController.saveOfferEngineResult(payload);
        System.assertEquals(false, result.get('isSuccess'));
        System.assertEquals('Application ID is required.', result.get('message'));
    }

    @IsTest
    static void saveOfferEngineResult_updatesLineItemAndEmiDates() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(new Map<String, Object>{
            'applicationId'      => ctx.application.Id,
            'loanAmount'         => 600000,
            'interestRate'       => 11.5,
            'tenure'             => 24,
            'emiAmount'          => 28000,
            'installmentType'    => 'equated',
            'advanceEMI'         => 'yes',
            'moratoriumDays'     => '0',
            'firstEmiDueDateDay' => 5
        });

        Test.startTest();
        Map<String, Object> result = OfferPageController.saveOfferEngineResult(payload);
        Test.stopTest();

        String message = result.containsKey('message') && result.get('message') != null ? String.valueOf(result.get('message')) : 'No message';
        System.assertEquals(true, result.get('isSuccess'), message);
        Application_Line_Item__c li = [
            SELECT Loan_Amount__c, CRM_IRR__c, Tenure__c, EMI_Amount__c,
                   Installment_Type__c, Advance_EMI__c, First_EMI_Date__c, Second_EMI_Date__c
            FROM Application_Line_Item__c
            WHERE Application__c = :ctx.application.Id
            LIMIT 1
        ];
        System.assertEquals(600000, li.Loan_Amount__c);
        System.assertEquals(11.5, li.CRM_IRR__c);
        System.assertEquals(24, li.Tenure__c);
        System.assertEquals(28000, li.EMI_Amount__c);
        System.assertEquals('Equated', li.Installment_Type__c);
        System.assertEquals(true, li.Advance_EMI__c);
        System.assertNotEquals(null, li.First_EMI_Date__c);
        System.assertEquals(li.First_EMI_Date__c.addMonths(1), li.Second_EMI_Date__c);
    }

    // ── createRepaymentSchedule / getRepaymentSchedule ────────────────────────

    @IsTest
    static void createRepaymentSchedule_missingApplicationId_returnsMessage() {
        String payload = JSON.serialize(new Map<String, Object>{ 'tenure' => 12 });
        Map<String, Object> result = OfferPageController.createRepaymentSchedule(payload);
        System.assertEquals(false, result.get('isSuccess'));
        System.assertEquals('Application ID is required.', result.get('message'));
    }

    @IsTest
    static void createRepaymentSchedule_buildsScheduleAndReplacesExisting() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(new Map<String, Object>{
            'applicationId'   => ctx.application.Id,
            'loanAmount'      => ctx.lineItem.Loan_Amount__c,
            'interestRate'    => ctx.lineItem.CRM_IRR__c,
            'tenure'          => 6,
            'emiAmount'       => 0,
            'installmentType' => 'equated'
        });

        Test.startTest();
        Map<String, Object> result = OfferPageController.createRepaymentSchedule(payload);
        Test.stopTest();

        String message = result.containsKey('message') && result.get('message') != null ? String.valueOf(result.get('message')) : 'No message';
        System.assertEquals(true, result.get('isSuccess'), message);
        System.assertEquals(6, result.get('count'));
        System.assertEquals(6, [
            SELECT COUNT() FROM Repayment_Schedule__c
            WHERE Application_Line_Items__c = :ctx.lineItem.Id
        ]);
    }

    @IsTest
    static void getRepaymentSchedule_returnsPersistedRows() {
        TestContext ctx = getContext();

        Map<String, Object> result = OfferPageController.getRepaymentSchedule(ctx.application.Id);

        System.assertEquals(true, result.get('hasData'));
        List<Repayment_Schedule__c> schedules = (List<Repayment_Schedule__c>) result.get('schedules');
        System.assert(!schedules.isEmpty(), 'Expected at least one schedule row.');
        System.assertEquals(ctx.lineItem.Loan_Amount__c, result.get('loanAmount'));
    }

    // ── Callable pay-in / pay-out ─────────────────────────────────────────────

    @IsTest
    static void callable_getPayinPayout_returnsCharges() {
        TestContext ctx = getContext();
        OfferPageController controller = new OfferPageController();

        Map<String, Object> result = (Map<String, Object>) controller.call(
            'getPayinPayout',
            new Map<String, Object>{ 'recordId' => ctx.application.Id }
        );

        System.assertEquals(true, result.get('isSuccess'));
        System.assertEquals(5000, result.get('serviceCharges'));
        System.assertEquals(1500, result.get('documentationCharges'));
    }

    @IsTest
    static void callable_updatePayinPayout_persistsChanges() {
        TestContext ctx = getContext();
        OfferPageController controller = new OfferPageController();

        Test.startTest();
        Map<String, Object> result = (Map<String, Object>) controller.call(
            'updatePayinPayout',
            new Map<String, Object>{
                'recordId'                       => ctx.application.Id,
                'serviceCharges'                 => 6000,
                'documentationCharges'           => 2000,
                'totalApplicableStampingCharges' => 900,
                'stampingDoneBy'                 => 'Bank',
                'cessCharges'                    => 250
            }
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), String.valueOf(result.get('message')));
        Application_Line_Item__c li = [
            SELECT Service_charges__c, Documentation_charges__c, Stamping_charges__c, Cess_Charges__c
            FROM Application_Line_Item__c
            WHERE Application__c = :ctx.application.Id
            LIMIT 1
        ];
        System.assertEquals(6000, li.Service_charges__c);
        System.assertEquals(2000, li.Documentation_charges__c);
        System.assertEquals(900, li.Stamping_charges__c);
        System.assertEquals(250, li.Cess_Charges__c);
    }

    // ── Insurance ─────────────────────────────────────────────────────────────

    @IsTest
    static void saveInsuranceRecord_noPlans_returnsMessage() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(new Map<String, Object>{
            'applicationId' => ctx.application.Id,
            'customerType'  => 'borrower',
            'plans'         => new List<Object>()
        });

        Map<String, Object> result = OfferPageController.saveInsuranceRecord(payload);
        System.assertEquals(false, result.get('success'));
        System.assertEquals('No plans provided', result.get('message'));
    }

    @IsTest
    static void saveInsuranceRecord_replacesAndInsertsPlans() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(new Map<String, Object>{
            'applicationId' => ctx.application.Id,
            'customerType'  => 'borrower',
            'plans'         => new List<Object>{
                new Map<String, Object>{
                    'insurancePlanType' => 'Life',
                    'insurancePlanName' => 'Updated Life',
                    'premium'           => 3000,
                    'amount'            => 700000,
                    'fundedNonFunded'   => 'Funded'
                },
                new Map<String, Object>{
                    'insurancePlanType' => 'Health',
                    'insurancePlanName' => 'Health Shield',
                    'premium'           => 1200,
                    'amount'            => 200000,
                    'fundedNonFunded'   => 'Non-Funded'
                }
            }
        });

        Test.startTest();
        Map<String, Object> result = OfferPageController.saveInsuranceRecord(payload);
        Test.stopTest();

        String message = result.containsKey('message') && result.get('message') != null ? String.valueOf(result.get('message')) : 'No message';
        System.assertEquals(true, result.get('success'), message);
        List<Insurance__c> records = [
            SELECT Insurance_Plan__c, Name, Funded_Premium__c
            FROM Insurance__c
            WHERE Applicant__c = :ctx.borrower.Id
            ORDER BY Insurance_Plan__c
        ];
        System.assertEquals(2, records.size());
        System.assertEquals('Health Shield', records[0].Name);
        System.assertEquals(null, records[0].Funded_Premium__c);
        System.assertEquals(3000, records[1].Funded_Premium__c);
    }

    @IsTest
    static void getInsuranceRecords_returnsActivePlans() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(new Map<String, Object>{
            'applicationId' => ctx.application.Id,
            'customerType'  => 'borrower'
        });

        List<Insurance__c> records = OfferPageController.getInsuranceRecords(payload);
        System.assertEquals(1, records.size());
        System.assertEquals('Life', records[0].Insurance_Plan__c);
    }

    // ── Highlight panel + email verification ──────────────────────────────────

    @IsTest
    static void getHighlightPanelData_returnsApplicants() {
        TestContext ctx = getContext();

        OfferPageController.HighlightPanelResult result =
            OfferPageController.getHighlightPanelData(ctx.application.Id);

        String message = result.message != null ? String.valueOf(result.message) : 'No message';
        System.assertEquals(true, result.success, message);
        System.assertEquals(2, result.applicants.size());
        System.assertEquals('borrower@test.com', result.applicants[0].email);
    }

    @IsTest
    static void getHighlightPanelData_blankId_returnsMessage() {
        OfferPageController.HighlightPanelResult result =
            OfferPageController.getHighlightPanelData(null);
        System.assertEquals(false, result.success);
        System.assertEquals('Application ID is required.', result.message);
    }

    @IsTest
    static void updateApplicantEmailVerified_setsFlag() {
        TestContext ctx = getContext();

        Test.startTest();
        Map<String, Object> result =
            OfferPageController.updateApplicantEmailVerified(ctx.borrower.Id);
        Test.stopTest();

        String message = result.containsKey('message') && result.get('message') != null ? String.valueOf(result.get('message')) : 'No message';
        System.assertEquals(true, result.get('success'), message);
        Applicant__c applicant = [
            SELECT Email_Verified__c FROM Applicant__c WHERE Id = :ctx.borrower.Id
        ];
        System.assertEquals(true, applicant.Email_Verified__c);
    }

    @IsTest
    static void updateApplicantEmailVerified_blankId_returnsMessage() {
        Map<String, Object> result = OfferPageController.updateApplicantEmailVerified('');
        System.assertEquals(false, result.get('success'));
        System.assertEquals('Applicant ID is required.', result.get('message'));
    }
}