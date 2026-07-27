@IsTest
private class RepaymentMandateControllerTest {
  @IsTest
  static void checkRetryCount_returnsSuccess() {
    Test.startTest();
    Map<String, Object> result = RepaymentMandateController.checkRetryCount('{}');
    Test.stopTest();
    System.assertEquals(true, result.get('isSuccess'));
    System.assertEquals(false, result.get('isRetryExhausted'));
  }

  @IsTest
  static void getStagesReachedBeforeRevoke_returnsEmptyList() {
    Test.startTest();
    List<String> stages = RepaymentMandateController.getStagesReachedBeforeRevoke(null);
    Test.stopTest();
    System.assertEquals(0, stages.size());
  }

  @IsTest
  static void getBankMasterData_returnsList() {
    Test.startTest();
    List<Bank_Master__c> banks = RepaymentMandateController.getBankMasterData();
    Test.stopTest();
    System.assertNotEquals(null, banks);
  }

  @IsTest
  static void upsertRepaymentRecord_createsOrFindsRecord() {
    Application__c app = new Application__c(Name = 'RM-Test-App');
    insert app;

    Test.startTest();
    Map<String, Object> first = RepaymentMandateController.upsertRepaymentRecord(app.Id, null);
    Map<String, Object> second = RepaymentMandateController.upsertRepaymentRecord(app.Id, null);
    Test.stopTest();

    System.assertEquals(true, first.get('success'));
    System.assertEquals(true, second.get('success'));
    System.assertEquals('RM-Test-App', first.get('leadNumber'));
    if (first.get('recordId') != null) {
      System.assertEquals(false, second.get('isNewRecord'));
    }
  }

  @IsTest
  static void initializeRepaymentMandate_returnsBootstrapBundle() {
    Application__c app = new Application__c(Name = 'RM-Init-App');
    insert app;

    Test.startTest();
    Map<String, Object> result = RepaymentMandateController.initializeRepaymentMandate(app.Id, null, null);
    Test.stopTest();

    System.assertEquals(true, result.get('success'));
    System.assertNotEquals(null, result.get('repaymentRecord'));
    System.assertNotEquals(null, result.get('bankMasterData'));
    System.assertNotEquals(null, result.get('applicantDetails'));
    System.assertNotEquals(null, result.get('documentIds'));
  }

  @IsTest
  static void displayRepaymentInfo_blankApplication() {
    Application__c app = new Application__c(Name = 'RM-Display-App');
    insert app;

    Test.startTest();
    Repayment_Mandate__c info = RepaymentMandateController.displayRepaymentInfo(app.Id, null);
    Test.stopTest();
    System.assertEquals(null, info);
  }

  @IsTest
  static void getDocumentIds_returnsMap() {
    Application__c app = new Application__c(Name = 'RM-Doc-App');
    insert app;

    Test.startTest();
    Map<String, String> ids = RepaymentMandateController.getDocumentIds(app.Id, null);
    Test.stopTest();
    System.assertNotEquals(null, ids);
  }

  @IsTest
  static void getApplicantDetails_returnsWrapper() {
    Application__c app = new Application__c(Name = 'RM-Applicant-App');
    insert app;

    Test.startTest();
    RepaymentMandateController.ApplicationDetailsWrapper wrapper = RepaymentMandateController.getApplicantDetails(
      app.Id,
      null
    );
    Test.stopTest();
    System.assertNotEquals(null, wrapper);
  }

  @IsTest
  static void getDocumentMetadataForOther_returnsMap() {
    Test.startTest();
    Map<String, Object> meta = RepaymentMandateController.getDocumentMetadataForOther('Bank Statement');
    Test.stopTest();
    System.assertNotEquals(null, meta);
  }

  @IsTest
  static void getRepaymentMethodPicklistValues_returnsList() {
    Test.startTest();
    List<RepaymentMandateController.PicklistOption> options = RepaymentMandateController.getRepaymentMethodPicklistValues();
    Test.stopTest();
    System.assertNotEquals(null, options);
  }

  @IsTest
  static void saveRepaymentDetails_updatesAllowedFieldsOnly() {
    Application__c app = new Application__c(Name = 'RM-Save-App');
    insert app;

    Repayment_Mandate__c repayment = new Repayment_Mandate__c(
      Name = 'Repayment Mandate - ' + app.Id,
      Application__c = app.Id
    );
    insert repayment;

    String fieldsJson =
      '{"Id":"' +
      repayment.Id +
      '","Repayment_Method__c":"N","IFSC_Code__c":"HDFC0001234","Branch_Name__c":"Main","Bank_Branch_City__c":"Mumbai","Repayment_to_be_done_by__c":"Borrower"}';

    Test.startTest();
    Boolean saved = RepaymentMandateController.saveRepaymentDetails(fieldsJson);
    Test.stopTest();

    System.assertEquals(true, saved);
    Repayment_Mandate__c updated = [
      SELECT Repayment_Method__c, IFSC_Code__c, Branch_Name__c, Bank_Branch_City__c, Repayment_to_be_done_by__c
      FROM Repayment_Mandate__c
      WHERE Id = :repayment.Id
    ];
    System.assertEquals('N', updated.Repayment_Method__c);
    System.assertEquals('HDFC0001234', updated.IFSC_Code__c);
  }

  @IsTest
  static void niCvRepaymentOptions_includeEligibleApplicants() {
    Application__c app = new Application__c(Name = 'RM-NI-CV', Product__c = 'CV');
    insert app;

    insert new List<Applicant__c>{
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Borrower',
        Applicant_Tab_Label__c = 'Borrower',
        Type__c = 'Non-Individual',
        Is_Primary__c = true,
        In_Active_Applicant__c = false
      ),
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Guarantor',
        Applicant_Tab_Label__c = 'G1',
        Type__c = 'Individual',
        Is_Primary__c = true,
        In_Active_Applicant__c = false
      ),
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Beneficiary',
        Applicant_Tab_Label__c = 'B1_1',
        Type__c = 'Individual',
        Is_Sub_Applicant__c = true,
        In_Active_Applicant__c = false
      )
    };

    RepaymentMandateController.ApplicationDetailsWrapper wrapper = RepaymentMandateController.getApplicantDetails(
      app.Id,
      null
    );

    System.assertEquals(true, wrapper.isNiApplication);
    System.assertEquals(2, wrapper.repaymentToBeDoneByOptions.size());
  }

  @IsTest
  static void niPvRepaymentOptions_filterByBankFlags() {
    Application__c app = new Application__c(Name = 'RM-NI-PV', Product__c = '4W');
    insert app;

    insert new List<Applicant__c>{
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Borrower',
        Type__c = 'Non-Individual',
        Is_Primary__c = true,
        In_Active_Applicant__c = false
      ),
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Guarantor',
        Applicant_Tab_Label__c = 'G1',
        Type__c = 'Individual',
        Has_Bank_Account__c = 'Yes',
        Is_Primary__c = true,
        In_Active_Applicant__c = false
      ),
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Guarantor',
        Applicant_Tab_Label__c = 'G2',
        Type__c = 'Individual',
        Has_Bank_Account__c = 'No',
        Is_Primary__c = false,
        In_Active_Applicant__c = false
      )
    };

    RepaymentMandateController.ApplicationDetailsWrapper wrapper = RepaymentMandateController.getApplicantDetails(
      app.Id,
      null
    );

    System.assertEquals(true, wrapper.isNiApplication);
    System.assertEquals(2, wrapper.repaymentToBeDoneByOptions.size());
  }

  @IsTest
  static void niRepaymentOptions_excludeNonPrimaryApplicants() {
    Application__c app = new Application__c(Name = 'RM-NI-Primary', Product__c = 'CV');
    insert app;

    insert new List<Applicant__c>{
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Borrower',
        Type__c = 'Non-Individual',
        Is_Primary__c = true,
        In_Active_Applicant__c = false
      ),
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Guarantor',
        Applicant_Tab_Label__c = 'G1',
        Type__c = 'Individual',
        Is_Primary__c = false,
        In_Active_Applicant__c = false
      ),
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Guarantor',
        Applicant_Tab_Label__c = 'G2',
        Type__c = 'Individual',
        Is_Primary__c = true,
        In_Active_Applicant__c = false
      ),
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Co-borrower',
        Applicant_Tab_Label__c = 'C1',
        Type__c = 'Individual',
        Is_Primary__c = true,
        In_Active_Applicant__c = false
      )
    };

    RepaymentMandateController.ApplicationDetailsWrapper wrapper = RepaymentMandateController.getApplicantDetails(
      app.Id,
      null
    );

    System.assertEquals(3, wrapper.repaymentToBeDoneByOptions.size());
    Set<String> optionValues = new Set<String>();
    for (RepaymentMandateController.RepaymentApplicantOption opt : wrapper.repaymentToBeDoneByOptions) {
      optionValues.add(opt.value);
    }
    System.assert(optionValues.contains('Borrower'));
    System.assert(optionValues.contains('Co-borrower'));
    System.assert(optionValues.contains('Guarantor G2'));
    System.assert(!optionValues.contains('Guarantor G1'));
  }

  @IsTest
  static void niRepaymentOptions_includeSoleGuarantorWithoutPrimaryFlag() {
    Application__c app = new Application__c(Name = 'RM-NI-Sole-G', Product__c = 'CV');
    insert app;

    insert new List<Applicant__c>{
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Borrower',
        Type__c = 'Non-Individual',
        Is_Primary__c = true,
        In_Active_Applicant__c = false
      ),
      new Applicant__c(
        Application__c = app.Id,
        Applicant_Type__c = 'Guarantor',
        Applicant_Tab_Label__c = 'G1',
        Type__c = 'Individual',
        Is_Primary__c = false,
        In_Active_Applicant__c = false
      )
    };

    RepaymentMandateController.ApplicationDetailsWrapper wrapper = RepaymentMandateController.getApplicantDetails(
      app.Id,
      null
    );

    Set<String> optionValues = new Set<String>();
    for (RepaymentMandateController.RepaymentApplicantOption opt : wrapper.repaymentToBeDoneByOptions) {
      optionValues.add(opt.value);
    }
    System.assert(optionValues.contains('Guarantor'));
  }
}