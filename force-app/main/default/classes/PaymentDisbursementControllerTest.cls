@IsTest
private class PaymentDisbursementControllerTest {
  @TestSetup
  static void testSetupMethod() {
    Application__c application = new Application__c(
      Stage__c = 'Post Disbursement',
      Sub_Stage__c = 'Payment Disbursement'
    );
    insert application;

    Application_Line_Item__c lineItem = new Application_Line_Item__c(
      Application__c = application.Id,
      Loan_Amount__c = 700000,
      Holiday_period__c = '0',
      First_EMI_Date__c = Date.newInstance(2026, 7, 10),
      Second_EMI_Date__c = Date.newInstance(2026, 8, 10)
    );
    insert lineItem;

    Disbursement_Details__c disbursementDetails = new Disbursement_Details__c(
      Application_Line_Items__c = lineItem.Id,
      Payment_Originated_From__c = 'HUB',
      Payment_to_be_made_on__c = Date.newInstance(2026, 5, 28)
    );
    insert disbursementDetails;

    insert new Loan_Beneficiary__c(
      Application__c = application.Id,
      Disbursement_Details__c = disbursementDetails.Id,
      Beneficiary_Name__c = 'Priya Motors',
      Type__c = 'Dealer',
      Account_Number__c = '1234567890',
      IFSC_Code__c = 'HDFC0001234',
      Amount__c = 700000
    );
  }

  @IsTest
  static void getPageData_ok() {
    Application__c application = [SELECT Id FROM Application__c LIMIT 1];

    Test.startTest();
    Map<String, Object> response = (Map<String, Object>) new PaymentDisbursementController()
      .call(
        'getPageData',
        new Map<String, Object>{ 'recordId' => application.Id }
      );
    Test.stopTest();

    System.assertEquals(true, response.get('isSuccess'));
    System.assertEquals('HUB', response.get('paymentOriginatedFrom'));

    List<Object> rows = (List<Object>) response.get('beneficiaryRows');
    System.assertEquals(1, rows.size());

    Map<String, Object> row = (Map<String, Object>) rows[0];
    System.assertEquals('Priya Motors', row.get('beneficiaryName'));
    System.assertEquals('dealer', row.get('beneficiaryType'));
    System.assertEquals(700000, row.get('disbursementAmount'));
    System.assertEquals(700000, row.get('toBePaidNow'));
  }

  @IsTest
  static void getPageData_noRecord() {
    Map<String, Object> response = (Map<String, Object>) new PaymentDisbursementController()
      .call('getPageData', new Map<String, Object>());

    System.assertEquals(false, response.get('isSuccess'));
    List<Object> rows = (List<Object>) response.get('beneficiaryRows');
    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void saveDisbursement_withAdj() {
    Application__c application = [SELECT Id FROM Application__c LIMIT 1];
    Loan_Beneficiary__c dealerBeneficiary = [
      SELECT Id
      FROM Loan_Beneficiary__c
      WHERE Application__c = :application.Id
      LIMIT 1
    ];

    List<Object> payments = new List<Object>{
      new Map<String, Object>{
        'id' => dealerBeneficiary.Id,
        'toBePaidNow' => 200000,
        'adjustedAmount' => 50000,
        'taReferenceNumber' => 'TA-REF-1001'
      }
    };

    Test.startTest();
    Map<String, Object> response = (Map<String, Object>) new PaymentDisbursementController()
      .call(
        'saveDisbursement',
        new Map<String, Object>{
          'recordId' => application.Id,
          'payments' => payments
        }
      );
    Test.stopTest();

    System.assertEquals(true, response.get('isSuccess'));
    Beneficiary_Payment__c payment = [
      SELECT
        Loan_Beneficiary__c,
        Tranche_Disbursement_Amount__c,
        Amount_Paid__c,
        Adjusted_Amount__c,
        TA_Reference_Number__c
      FROM Beneficiary_Payment__c
      WHERE Loan_Beneficiary__c = :dealerBeneficiary.Id
      LIMIT 1
    ];
    System.assertEquals(200000, payment.Tranche_Disbursement_Amount__c);
    System.assertEquals(150000, payment.Amount_Paid__c);
    System.assertEquals(50000, payment.Adjusted_Amount__c);
    System.assertEquals('TA-REF-1001', payment.TA_Reference_Number__c);

    List<Object> rows = (List<Object>) response.get('beneficiaryRows');
    System.assertEquals(1, rows.size());
    Map<String, Object> savedRow = (Map<String, Object>) rows[0];
    System.assertEquals(200000, savedRow.get('paidEarlier'));
    System.assertEquals(500000, savedRow.get('toBePaidNow'));
  }

  @IsTest
  static void saveDisbursement_remaining() {
    Application__c application = [SELECT Id FROM Application__c LIMIT 1];
    Loan_Beneficiary__c dealerBeneficiary = [
      SELECT Id
      FROM Loan_Beneficiary__c
      WHERE Application__c = :application.Id
      LIMIT 1
    ];

    insert new Beneficiary_Payment__c(
      Loan_Beneficiary__c = dealerBeneficiary.Id,
      Tranche_Disbursement_Amount__c = 100000,
      Amount_Paid__c = 100000,
      Adjusted_Amount__c = 0,
      Remaining_Disbursement_Amount__c = 600000,
      Payment_Date__c = DateTime.now().addDays(-1)
    );

    List<Object> payments = new List<Object>{
      new Map<String, Object>{
        'id' => dealerBeneficiary.Id,
        'toBePaidNow' => 200000,
        'adjustedAmount' => 50000,
        'taReferenceNumber' => 'TA-REF-2002'
      }
    };

    Test.startTest();
    Map<String, Object> response = (Map<String, Object>) new PaymentDisbursementController()
      .call(
        'saveDisbursement',
        new Map<String, Object>{
          'recordId' => application.Id,
          'payments' => payments
        }
      );
    Test.stopTest();

    System.assertEquals(true, response.get('isSuccess'));

    Beneficiary_Payment__c latestPayment = [
      SELECT
        Tranche_Disbursement_Amount__c,
        Amount_Paid__c,
        Adjusted_Amount__c,
        Remaining_Disbursement_Amount__c
      FROM Beneficiary_Payment__c
      WHERE
        Loan_Beneficiary__c = :dealerBeneficiary.Id
        AND Adjusted_Amount__c = 50000
      LIMIT 1
    ];
    System.assertEquals(200000, latestPayment.Tranche_Disbursement_Amount__c);
    System.assertEquals(150000, latestPayment.Amount_Paid__c);
    System.assertEquals(50000, latestPayment.Adjusted_Amount__c);
    System.assertEquals(400000, latestPayment.Remaining_Disbursement_Amount__c);
  }

  @IsTest
  static void saveDisbursement_nonDealerErr() {
    Application__c application = [SELECT Id FROM Application__c LIMIT 1];
    Disbursement_Details__c details = [
      SELECT Id
      FROM Disbursement_Details__c
      WHERE Application_Line_Items__r.Application__c = :application.Id
      LIMIT 1
    ];
    Loan_Beneficiary__c sellerBeneficiary = new Loan_Beneficiary__c(
      Application__c = application.Id,
      Disbursement_Details__c = details.Id,
      Beneficiary_Name__c = 'Seller Beneficiary',
      Type__c = 'Seller',
      Account_Number__c = '9999999999',
      IFSC_Code__c = 'HDFC0009999',
      Amount__c = 100000
    );
    insert sellerBeneficiary;

    List<Object> payments = new List<Object>{
      new Map<String, Object>{
        'id' => sellerBeneficiary.Id,
        'toBePaidNow' => 50000,
        'adjustedAmount' => 25000,
        'taReferenceNumber' => 'TA-REF-NEGATIVE'
      }
    };

    Test.startTest();
    Map<String, Object> response = (Map<String, Object>) new PaymentDisbursementController()
      .call(
        'saveDisbursement',
        new Map<String, Object>{
          'recordId' => application.Id,
          'payments' => payments
        }
      );
    Test.stopTest();

    System.assertEquals(false, response.get('isSuccess'));
    System.assertEquals(
      'TA adjustment is applicable only for dealer beneficiary.',
      response.get('loadError')
    );
  }
}