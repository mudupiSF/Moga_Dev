/**
 * Controller for repaymentMandate LWC (P4RepaymentMandateController parity).
 * Application__c replaces Opportunity. Repayment_Mandate__c replaces Repayments__c.
 * Child records use Application__c lookup to Application Id.
 */
public with sharing class RepaymentMandateController {

  private static final String DOCUMENT_CHECKLIST_OBJECT = 'Document_CheckList__c';
  private static final String REPAYMENT_PSS_STAGE = 'Repayment_PSS';
  private static final String REPAYMENT_OPS_STAGE = 'Repayment_OPS';
  private static final String REPAYMENT_OPS_VIEW_ID = 'Wheels_Repayment_OPS';
  private static final Set<String> ENACH_HISTORY_SERVICES = new Set<String>{
    'ENACH Registration Journey',
    'E-Sign Registration Journey',
    'SIStatus',
    'P4_UPI_CREATE_MANDATE'
  };

  /** Repayment_Mandate__c fields used by repaymentMandate.buildRepaymentUpdateFields. */
  private static final Set<String> REPAYMENT_MANDATE_FORM_FIELDS = new Set<String>{
    'Id',
    'Bank_Master__c',
    'Repayment_Method__c',
    'Account_Number__c',
    'IFSC_Code__c',
    'Branch_Name__c',
    'Bank_Branch_City__c',
    'Repayment_to_be_done_by__c',
    'eSIGNType__c',
    'Type_Of_Account__c',
    'UPI_Id__c',
    'Initiation_Method__c',
    'All_Mandate_Details_Correctly_Entered__c',
    'Remarks__c'
  };

  private static final String REPAYMENT_MANDATE_FORM_SOQL =
    'SELECT Id, Bank_Master__c, Repayment_Method__c, Account_Number__c, IFSC_Code__c, ' +
    'Branch_Name__c, Bank_Branch_City__c, Repayment_to_be_done_by__c, ' +
    'eSIGNType__c, Type_Of_Account__c, UPI_Id__c, Initiation_Method__c, ' +
    'All_Mandate_Details_Correctly_Entered__c, Remarks__c ' +
    'FROM Repayment_Mandate__c WHERE Application__c = :applicationId WITH SECURITY_ENFORCED LIMIT 1';

  @AuraEnabled
  public static Repayment_Mandate__c displayRepaymentInfo(
    String applicationId,
    String applicationLineItemId
  ) {
    try {
      List<Repayment_Mandate__c> repaymentDetails = queryRepaymentMandates(
        applicationId,
        parseLineItemId(applicationLineItemId)
      );
      return repaymentDetails.isEmpty() ? null : repaymentDetails[0];
    } catch (Exception ex) {
      throw new AuraHandledException('Error fetching repayment info: ' + ex.getMessage());
    }
  }

  @AuraEnabled
  public static Boolean saveRepaymentDetails(String repaymentFieldsJson) {
    if (String.isBlank(repaymentFieldsJson)) {
      throw new AuraHandledException('Repayment fields are required.');
    }

    try {
      Map<String, Object> fieldMap = (Map<String, Object>) JSON.deserializeUntyped(repaymentFieldsJson);
      Repayment_Mandate__c repaymentRecord = buildRepaymentRecordFromAllowedFields(fieldMap);
      if (repaymentRecord.Id == null) {
        throw new AuraHandledException('Repayment record Id is required.');
      }
      update repaymentRecord;
      return true;
    } catch (Exception ex) {
      System.debug('Error saving repayment details: ' + ex.getMessage() + ' at line ' + ex.getLineNumber());
      throw new AuraHandledException('Error saving repayment details: ' + ex.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, Object> markRepaymentStageComplete(
    String applicationLineItemId,
    String currentViewId
  ) {
    Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
    Id lineItemId = parseLineItemId(applicationLineItemId);
    if (lineItemId == null) {
      result.put('message', 'Application Line Item ID is required.');
      return result;
    }

    try {
      List<Application_Line_Item__c> lineItems = [
        SELECT Id, Stage_Completed__c
        FROM Application_Line_Item__c
        WHERE Id = :lineItemId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (lineItems.isEmpty()) {
        result.put('message', 'Application Line Item not found.');
        return result;
      }

      Application_Line_Item__c lineItem = lineItems[0];
      lineItem.Stage_Completed__c = appendStageCompleted(
        lineItem.Stage_Completed__c,
        resolveRepaymentStageCompletedValue(currentViewId)
      );
      update lineItem;

      result.put('isSuccess', true);
      result.put('applicationLineItemId', String.valueOf(lineItemId));
    } catch (Exception ex) {
      result.put('message', ex.getMessage());
    }

    return result;
  }

  @AuraEnabled
  public static String initOrGetDocumentWithApplicantId(
    String applicationId,
    String documentType,
    String applicantId,
    String applicationLineItemId,
    String assetId
  ) {
    try {
      Id lineItemId = toId(applicationLineItemId);
      Id resolvedAssetId = toId(assetId);
      Map<String, Schema.SObjectField> checklistFieldMap = Document_CheckList__c.SObjectType.getDescribe().fields.getMap();
      String lineItemFilter = '';
      if (lineItemId != null && checklistFieldMap.containsKey('Application_Line_Items__c')) {
        lineItemFilter = ' AND Application_Line_Items__c = :lineItemId';
      }
      String assetFilter = '';
      if (resolvedAssetId != null && checklistFieldMap.containsKey('Asset__c')) {
        assetFilter = ' AND Asset__c = :resolvedAssetId';
      }

      List<SObject> existingDocs = Database.query(
        'SELECT Id' +
        ' FROM Document_CheckList__c' +
        ' WHERE Application__c = :applicationId' +
        ' AND Applicant__c = :applicantId' +
        lineItemFilter +
        assetFilter +
        ' AND Document_Type__c = :documentType' +
        ' ORDER BY CreatedDate DESC LIMIT 1'
      );

      if (!existingDocs.isEmpty()) {
        return String.valueOf(existingDocs[0].get('Id'));
      }

      Document_CheckList__c newDoc = new Document_CheckList__c();
      newDoc.Name = documentType + ' - Document';
      newDoc.Document_Type__c = documentType;
      newDoc.Application__c = applicationId;
      newDoc.Applicant__c = applicantId;
      if (lineItemId != null && checklistFieldMap.containsKey('Application_Line_Items__c')) {
        newDoc.Application_Line_Items__c = lineItemId;
      }
      if (resolvedAssetId != null && checklistFieldMap.containsKey('Asset__c')) {
        newDoc.Asset__c = resolvedAssetId;
      }
      insert newDoc;
      return newDoc.Id;
    } catch (Exception e) {
      throw new AuraHandledException('Error initializing document: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, Object> getDocumentMetadataForOther(String documentType) {
    try {
      Map<String, Object> metadata = new Map<String, Object>();
      String recordTypeId = '';

      List<RecordType> otherRecordTypes = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = :DOCUMENT_CHECKLIST_OBJECT AND DeveloperName = 'Other_Documents'
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!otherRecordTypes.isEmpty()) {
        recordTypeId = otherRecordTypes[0].Id;
      }

      metadata.put('recordTypeId', recordTypeId);
      return metadata;
    } catch (Exception e) {
      throw new AuraHandledException('Error fetching document metadata: ' + e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static String getBankIdByBankName(String bankName) {
    List<Bank_Master__c> banks = [
      SELECT Id
      FROM Bank_Master__c
      WHERE Name = :bankName
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    return banks.isEmpty() ? null : banks[0].Id;
  }

  @AuraEnabled(cacheable=true)
  public static List<Bank_Master__c> getBankMasterData() {
    return [SELECT Id, Name FROM Bank_Master__c WITH SECURITY_ENFORCED ORDER BY Name ASC LIMIT 500];
  }

  @AuraEnabled
  public static Map<String, Object> upsertRepaymentRecord(
    String applicationId,
    String applicationLineItemId
  ) {
    try {
      Map<String, Object> result = new Map<String, Object>();
      Id lineItemId = parseLineItemId(applicationLineItemId);

      Application__c app = [
        SELECT Id, Name
        FROM Application__c
        WHERE Id = :applicationId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      String leadNumber = app.Name != null ? app.Name : '';

      List<Repayment_Mandate__c> existingRepayments = queryRepaymentMandates(
        applicationId,
        lineItemId
      );

      if (!existingRepayments.isEmpty()) {
        result.put('recordId', existingRepayments[0].Id);
        result.put('leadNumber', leadNumber);
        result.put('isNewRecord', false);
        result.put('success', true);
        result.put('message', 'Existing repayment record found');
        return result;
      }

      Repayment_Mandate__c repaymentRecord = new Repayment_Mandate__c();
      repaymentRecord.Application__c = applicationId;
      if (lineItemId != null) {
        repaymentRecord.Application_Line_Items__c = lineItemId;
        repaymentRecord.Name = 'Repayment Mandate - ' + lineItemId;
      } else {
        repaymentRecord.Name = 'Repayment Mandate - ' + applicationId;
        repaymentRecord.Application_Line_Items__c = [
          SELECT Id
          FROM Application_Line_Item__c
          WHERE Application__c = :applicationId
          WITH SECURITY_ENFORCED
          ORDER BY CreatedDate ASC
          LIMIT 1
        ]?.Id;
      }
      insert repaymentRecord;

      result.put('recordId', repaymentRecord.Id);
      result.put('leadNumber', leadNumber);
      result.put('isNewRecord', true);
      result.put('success', true);
      result.put('message', 'New repayment record created');
      return result;
    } catch (Exception ex) {
      System.debug('Error creating or fetching repayment record: ' + ex.getMessage() + ' at line ' + ex.getLineNumber());
      throw new AuraHandledException('Error creating or fetching repayment record: ' + ex.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, Object> checkApiExecutionStatus(String applicationId, List<String> serviceNames) {
    try {
      Map<String, Object> result = new Map<String, Object>();
      Map<String, Object> apiStatusMap = new Map<String, Object>();

      if (serviceNames == null) {
        serviceNames = new List<String>();
      }

      List<Integration_Log__c> integrationLogs = [
        SELECT Id, Service_Name__c, Status__c, Original_response__c, Created_DateTime__c
        FROM Integration_Log__c
        WHERE Application__c = :applicationId AND Service_Name__c IN :serviceNames
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
      ];

      Map<String, Integration_Log__c> latestServiceStatus = new Map<String, Integration_Log__c>();
      for (Integration_Log__c log : integrationLogs) {
        if (!latestServiceStatus.containsKey(log.Service_Name__c)) {
          latestServiceStatus.put(log.Service_Name__c, log);
        }
      }

      for (String serviceName : serviceNames) {
        Map<String, Object> serviceResult = new Map<String, Object>();

        if (latestServiceStatus.containsKey(serviceName)) {
          Integration_Log__c latestLog = latestServiceStatus.get(serviceName);
          serviceResult.put('hasBeenCalled', true);
          serviceResult.put('status', latestLog.Status__c);
          serviceResult.put('lastExecuted', latestLog.Created_DateTime__c);

          if (latestLog.Status__c == 'SUCCESS' || latestLog.Status__c == 'Success') {
            serviceResult.put('shouldSkip', true);
            serviceResult.put('cachedResponse', latestLog.Original_response__c);
            serviceResult.put('message', 'API already succeeded, using cached response');
          } else {
            serviceResult.put('shouldSkip', false);
            serviceResult.put('message', 'API failed previously, will retry');
          }
        } else {
          serviceResult.put('hasBeenCalled', false);
          serviceResult.put('shouldSkip', false);
          serviceResult.put('message', 'API never called before, will execute');
        }

        apiStatusMap.put(serviceName, serviceResult);
      }

      result.put('success', true);
      result.put('apiStatusMap', apiStatusMap);
      result.put('message', 'API status check completed');
      return result;
    } catch (Exception ex) {
      throw new AuraHandledException('Error checking API execution status: ' + ex.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, Object> checkRetryCount(String requestJson) {
    return new Map<String, Object>{
      'isSuccess' => true,
      'isRetryExhausted' => false,
      'message' => 'Retry check passed'
    };
  }

  @AuraEnabled
  public static List<Integration_Log__c> enachJournyStatusHistory(String applicationId, String dealId) {
    try {
      List<Integration_Log__c> enachJournyStatusHistory = new List<Integration_Log__c>();
      List<Integration_Log__c> enachStatusData = [
        SELECT
          Id,
          Service_Name__c,
          Created_DateTime__c,
          Application__c,
          Original_response__c,
          Original_request__c,
          Status__c
        FROM Integration_Log__c
        WHERE Service_Name__c IN :ENACH_HISTORY_SERVICES AND Application__c = :applicationId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
      ];

      for (Integration_Log__c intList : enachStatusData) {
        if (intList.Original_response__c != null && intList.Original_response__c != '') {
          enachJournyStatusHistory.add(intList);
        }
      }

      return enachJournyStatusHistory.isEmpty() ? null : enachJournyStatusHistory;
    } catch (Exception e) {
      throw new AuraHandledException('Error fetching e-NACH journey status history: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, String> enachStatusHistory(String applicationId) {
    try {
      List<Integration_Log__c> enachStatusHistory = [
        SELECT
          Id,
          Service_Name__c,
          Created_DateTime__c,
          Application__c,
          Original_response__c,
          Original_request__c,
          Status__c
        FROM Integration_Log__c
        WHERE Service_Name__c = 'ENACH Registration Status' AND Application__c = :applicationId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
      ];

      Map<String, String> sessionIdVsNpciStatusMap = new Map<String, String>();

      for (Integration_Log__c log : enachStatusHistory) {
        String sessionId = null;
        String status = 'In Progress';

        if (log.Original_request__c != null) {
          Map<String, Object> request = (Map<String, Object>) JSON.deserializeUntyped(log.Original_request__c);
          sessionId = (String) request.get('session');
        }

        if (log.Original_response__c != null) {
          Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(log.Original_response__c);
          String npciStatus = response.containsKey('npcistatus') ? (String) response.get('npcistatus') : null;
          String errorCodeCheck = response.containsKey('error_code') ? (String) response.get('error_code') : null;

          if (String.isNotBlank(npciStatus) && npciStatus == 'failed') {
            status = 'ENACH Registration Failed';
          } else if (String.isNotBlank(errorCodeCheck) && errorCodeCheck == 'E0005') {
            status = 'Customer Action On ENACH Pending';
          } else if (String.isBlank(npciStatus) && String.isBlank(errorCodeCheck)) {
            status = 'Response From NPCI Pending';
          } else {
            status = 'ENACH Registration Success';
          }
        }

        if (String.isNotBlank(sessionId)) {
          sessionIdVsNpciStatusMap.put(sessionId, status);
        }
      }

      return sessionIdVsNpciStatusMap;
    } catch (Exception e) {
      throw new AuraHandledException('Error fetching e-NACH status history: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static List<Integration_Log__c> getETBResponse(String applicationId) {
    try {
      List<Integration_Log__c> etbResponse = [
        SELECT
          Id,
          Service_Name__c,
          Original_response__c,
          Original_request__c,
          Status__c,
          Processed_Response__c
        FROM Integration_Log__c
        WHERE Service_Name__c = 'ETBCASA' AND Application__c = :applicationId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      return etbResponse.isEmpty() ? null : etbResponse;
    } catch (Exception e) {
      throw new AuraHandledException('Error fetching ETB response: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static ApplicationDetailsWrapper getApplicantDetails(
    String applicationId,
    String applicationLineItemId
  ) {
    try {
      ApplicationDetailsWrapper wrapper = new ApplicationDetailsWrapper();
      wrapper.isNiApplication = false;

      List<Application_Line_Item__c> applicationLineItems = [
        SELECT Tenure__c, First_EMI_Date__c, EMI_Amount__c
        FROM Application_Line_Item__c
        WHERE Application__c = :applicationId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!applicationLineItems.isEmpty()) {
        wrapper.emiAmount = applicationLineItems[0].EMI_Amount__c;
        Date firstEmiDate = applicationLineItems[0].First_EMI_Date__c;
        Integer tenureMonths = applicationLineItems[0].Tenure__c != null
          ? Integer.valueOf(applicationLineItems[0].Tenure__c)
          : 0;
        if (firstEmiDate != null && tenureMonths > 0) {
          wrapper.endDate = String.valueOf(firstEmiDate.addMonths(tenureMonths + 6));
        }
      }

      List<Applicant__c> applicantList = [
        SELECT
          Id,
          Name,
          Customer_Code__c,
          Contact_number__c,
          Applicant_Type__c,
          Applicant_Tab_Label__c,
          Type__c,
          Email__c,
          Deal_Number__c,
          Has_Bank_Account__c,
          Interested_In_Opening_Savings_Account__c,
          Is_Sub_Applicant__c,
          Parent_Applicant__c,
          Is_Primary__c
        FROM Applicant__c
        WHERE Application__c = :applicationId AND In_Active_Applicant__c = FALSE
        WITH USER_MODE
      ];

      if (applicantList.isEmpty()) {
        return wrapper;
      }

      Applicant__c borrowerApplicant;
      Applicant__c coBorrowerApplicant;
      Applicant__c beneficiaryApplicant;

      for (Applicant__c applicant : applicantList) {
        if ('Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c)) {
          borrowerApplicant = applicant;
        } else if ('Co-borrower'.equalsIgnoreCase(applicant.Applicant_Type__c)) {
          coBorrowerApplicant = applicant;
        } else if ('Beneficiary'.equalsIgnoreCase(applicant.Applicant_Type__c)) {
          beneficiaryApplicant = applicant;
        }
      }

      if (borrowerApplicant == null) {
        return wrapper;
      }

      wrapper.borrowerApplicant = borrowerApplicant;
      wrapper.coBorrowerApplicant = coBorrowerApplicant;
      wrapper.beneficiaryApplicant = beneficiaryApplicant;

      if (GenericUtility.isNonIndividualApplicationType(borrowerApplicant.Type__c)) {
        populateNiRepaymentOptions(wrapper, applicantList, applicationId);
      }

      String repaymentDoneBy = resolveSavedRepaymentToBeDoneBy(
        applicationId,
        parseLineItemId(applicationLineItemId)
      );
      wrapper.repaymentToBeDoneBy = repaymentDoneBy;

      Applicant__c selectedApplicant = borrowerApplicant;
      if (wrapper.isNiApplication == true) {
        selectedApplicant = resolveNiRepaymentApplicant(
          wrapper.repaymentToBeDoneByOptions,
          wrapper.repaymentEligibleApplicants,
          repaymentDoneBy,
          getDefaultNiRepaymentApplicant(wrapper.repaymentEligibleApplicants, borrowerApplicant)
        );
      } else if (repaymentDoneBy == 'Co-borrower' && coBorrowerApplicant != null) {
        selectedApplicant = coBorrowerApplicant;
      } else if (repaymentDoneBy == 'Beneficiary' && beneficiaryApplicant != null) {
        selectedApplicant = beneficiaryApplicant;
      }

      wrapper.repaymentDoneBy = selectedApplicant.Name;
      wrapper.applicantPhone = selectedApplicant.Contact_number__c;
      wrapper.applicantEmail = selectedApplicant.Email__c;
      wrapper.applicantId = selectedApplicant.Id;
      wrapper.repayApplicantDetail = selectedApplicant;
      wrapper.customerCode = selectedApplicant.Customer_Code__c;
      wrapper.dealId = selectedApplicant.Deal_Number__c;
      wrapper.dealNumber = selectedApplicant.Deal_Number__c;
      return wrapper;
    } catch (Exception e) {
      throw new AuraHandledException('Error fetching applicant details: ' + e.getMessage());
    }
  }

  /**
   * @description Returns Document_CheckList__c ids and uploaded file metadata for ACH documents.
   */
  @AuraEnabled
  public static Map<String, String> getDocumentIds(String applicationId, String applicantId) {
    Map<String, String> documentIds = new Map<String, String>();
    Set<String> documentTypes = new Set<String>{ 'Bank Statement', 'ACH Mandate Form' };

    String soql =
      'SELECT Id, Name, Document_Type__c, ContentVersionId__c ' +
      'FROM Document_CheckList__c ' +
      'WHERE Application__c = :applicationId AND Document_Type__c IN :documentTypes';
    if (String.isNotBlank(applicantId)) {
      soql += ' AND Applicant__c = :applicantId';
    }
    soql += ' WITH SECURITY_ENFORCED ORDER BY Document_Type__c, CreatedDate DESC';

    for (Document_CheckList__c doc : Database.query(soql)) {
      String contentDocumentId = getContentDocumentIdFromVersion(doc.ContentVersionId__c);
      String fileName = '';
      String fileType = 'PDF';
      if (String.isNotBlank(doc.ContentVersionId__c)) {
        List<ContentVersion> versions = [
          SELECT Title, FileExtension
          FROM ContentVersion
          WHERE Id = :doc.ContentVersionId__c
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        if (!versions.isEmpty()) {
          fileName = versions[0].Title;
          if (String.isNotBlank(versions[0].FileExtension)) {
            fileType = versions[0].FileExtension.toUpperCase();
          }
        }
      }

      if (doc.Document_Type__c == 'ACH Mandate Form' && !documentIds.containsKey('achMandateDocumentId')) {
        documentIds.put('achMandateDocumentId', doc.Id);
        if (String.isNotBlank(contentDocumentId)) {
          documentIds.put('achMandateContentDocumentId', contentDocumentId);
          documentIds.put('achMandateFileName', fileName);
          documentIds.put('achMandateFileType', fileType);
        }
      } else if (
        doc.Document_Type__c == 'Bank Statement' &&
        !documentIds.containsKey('bankStatementDocumentId')
      ) {
        documentIds.put('bankStatementDocumentId', doc.Id);
        if (String.isNotBlank(contentDocumentId)) {
          documentIds.put('bankStatementContentDocumentId', contentDocumentId);
          documentIds.put('bankStatementFileName', fileName);
          documentIds.put('bankStatementFileType', fileType);
        }
      }
    }

    return documentIds;
  }

  /**
   * @description Returns file extension for preview (PDF default).
   */
  @AuraEnabled
  public static String getFileType(String contentDocumentId) {
    if (String.isBlank(contentDocumentId)) {
      return 'PDF';
    }
    List<ContentVersion> versions = [
      SELECT FileExtension
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (versions.isEmpty() || String.isBlank(versions[0].FileExtension)) {
      return 'PDF';
    }
    return versions[0].FileExtension.toUpperCase();
  }

  /**
   * @description Deletes uploaded content and clears Document_CheckList__c link.
   */
  @AuraEnabled
  public static Boolean deleteContentDocument(String contentDocumentId) {
    if (String.isBlank(contentDocumentId)) {
      return false;
    }

    String versionId = getLatestContentVersionId(contentDocumentId);
    if (String.isNotBlank(versionId)) {
      List<Document_CheckList__c> rows = [
        SELECT Id
        FROM Document_CheckList__c
        WHERE ContentVersionId__c = :versionId
        WITH SECURITY_ENFORCED
      ];
      for (Document_CheckList__c row : rows) {
        row.ContentVersionId__c = null;
      }
      if (!rows.isEmpty()) {
        update rows;
      }
    }

    delete [SELECT Id FROM ContentDocument WHERE Id = :contentDocumentId WITH SECURITY_ENFORCED];
    return true;
  }

  @AuraEnabled(cacheable=true)
  public static List<PicklistOption> getRepaymentMethodPicklistValues() {
    return getRepaymentMandatePicklistValues('Repayment_Method__c');
  }

  private static List<PicklistOption> getRepaymentMandatePicklistValues(String fieldApiName) {
    List<PicklistOption> options = new List<PicklistOption>();
    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Repayment_Mandate__c.fields.getMap();
    if (!fieldMap.containsKey(fieldApiName)) {
      return options;
    }

    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
    for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
      if (!entry.isActive()) {
        continue;
      }
      PicklistOption option = new PicklistOption();
      option.label = entry.getLabel();
      option.value = entry.getValue();
      options.add(option);
    }

    return options;
  }

  @AuraEnabled
  public static Map<String, String> getRepaymentRecordType() {
    try {
      Map<String, String> repaymentRecordType = new Map<String, String>();
      Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Repayment_Mandate__c.getRecordTypeInfosByDeveloperName();

      putRecordType(repaymentRecordType, rtMap, 'E_NACH', 'E_NACH');
      putRecordType(repaymentRecordType, rtMap, 'E_SIGN', 'E_SIGN');
      putRecordType(repaymentRecordType, rtMap, 'SI_Online', 'SI_Online');
      putRecordType(repaymentRecordType, rtMap, 'SI_Offline', 'SI_Offline');
      putRecordType(repaymentRecordType, rtMap, 'UPI', 'UPI');
      putRecordType(repaymentRecordType, rtMap, 'CASH', 'CASH');
      putRecordType(repaymentRecordType, rtMap, 'IndusEasySavings', 'Indus_Easy_Savings');

      return repaymentRecordType;
    } catch (Exception ex) {
      throw new AuraHandledException('Error fetching repayment record types: ' + ex.getMessage());
    }
  }

  @AuraEnabled
  public static List<String> getStagesReachedBeforeRevoke(String applicationId) {
    return new List<String>();
  }

  @AuraEnabled
  public static void linkContentDocument(String documentDataJson) {
    if (String.isBlank(documentDataJson)) {
      return;
    }

    Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(documentDataJson);
    String contentDocumentId = (String) data.get('contentDocumentId');
    String applicationId = (String) data.get('applicationId');
    String applicantId = (String) data.get('applicantId');
    String documentType = (String) data.get('documentType');
    String applicationLineItemId = (String) data.get('applicationLineItemId');
    String assetId = (String) data.get('assetId');

    if (String.isBlank(contentDocumentId)) {
      return;
    }

    String documentId = initOrGetDocumentWithApplicantId(
      applicationId,
      documentType,
      applicantId,
      applicationLineItemId,
      assetId
    );
    if (String.isBlank(documentId)) {
      documentId = applicationId;
    }

    String contentVersionId = getLatestContentVersionId(contentDocumentId);
    if (String.isNotBlank(documentId) && String.isNotBlank(contentVersionId)) {
      Document_CheckList__c checklistRow = new Document_CheckList__c(
        Id = documentId,
        ContentVersionId__c = contentVersionId
      );
      update checklistRow;
      return;
    }

    List<ContentDocumentLink> links = [
      SELECT Id
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :documentId AND ContentDocumentId = :contentDocumentId
      LIMIT 1
    ];
    if (links.isEmpty()) {
      insert new ContentDocumentLink(
        LinkedEntityId = documentId,
        ContentDocumentId = contentDocumentId,
        ShareType = 'V',
        Visibility = 'AllUsers'
      );
    }
  }

  @AuraEnabled
  public static Map<String, Object> initializeRepaymentMandate(
    String applicationId,
    String dealId,
    String applicationLineItemId
  ) {
    try {
      Map<String, Object> result = new Map<String, Object>();

      ApplicationDetailsWrapper applicantDetails = getApplicantDetails(
        applicationId,
        applicationLineItemId
      );
      result.put('applicantDetails', applicantDetails);

      result.put('sandboxStatus', true);
      result.put('pennyDropValidations', new List<String>());
      result.put('bankMasterData', getBankMasterData());
      result.put('repaymentMethodOptions', getRepaymentMethodPicklistValues());
      result.put('stagesReached', getStagesReachedBeforeRevoke(applicationId));
      result.put('repaymentRecordType', getRepaymentRecordType());

      try {
        result.put('repaymentRecord', upsertRepaymentRecord(applicationId, applicationLineItemId));
      } catch (Exception ex) {
        result.put(
          'repaymentRecord',
          new Map<String, Object>{ 'success' => false, 'message' => ex.getMessage() }
        );
      }
      try {
        result.put('repaymentInfo', displayRepaymentInfo(applicationId, applicationLineItemId));
      } catch (Exception ex) {
        result.put('repaymentInfo', null);
      }
      try {
        result.put('enachStatusHistory', enachJournyStatusHistory(applicationId, dealId));
      } catch (Exception ex) {
        result.put('enachStatusHistory', null);
      }
      try {
        result.put(
          'documentIds',
          getDocumentIds(applicationId, applicantDetails != null ? applicantDetails.applicantId : null)
        );
      } catch (Exception ex) {
        result.put('documentIds', new Map<String, String>());
      }

      result.put('success', true);
      return result;
    } catch (Exception ex) {
      throw new AuraHandledException('Error initializing repayment mandate: ' + ex.getMessage());
    }
  }

  public class PicklistOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
  }

  public class RepaymentApplicantOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
    @AuraEnabled public String applicantId;
  }

  public class ApplicationDetailsWrapper {
    @AuraEnabled public String dealNumber;
    @AuraEnabled public String dealId;
    @AuraEnabled public String customerCode;
    @AuraEnabled public Decimal emiAmount;
    @AuraEnabled public String endDate;
    @AuraEnabled public String repaymentToBeDoneBy;
    @AuraEnabled public Boolean isNiApplication;
    @AuraEnabled public List<RepaymentApplicantOption> repaymentToBeDoneByOptions;
    @AuraEnabled public List<Applicant__c> repaymentEligibleApplicants;
    @AuraEnabled public Applicant__c borrowerApplicant;
    @AuraEnabled public Applicant__c coBorrowerApplicant;
    @AuraEnabled public Applicant__c beneficiaryApplicant;
    @AuraEnabled public Applicant__c repayApplicantDetail;
    @AuraEnabled public String repaymentDoneBy;
    @AuraEnabled public String applicantPhone;
    @AuraEnabled public String applicantEmail;
    @AuraEnabled public String applicantId;
  }

  private static void populateNiRepaymentOptions(
    ApplicationDetailsWrapper wrapper,
    List<Applicant__c> applicantList,
    Id applicationId
  ) {
    Boolean isPv = isPvRepaymentApplication(applicationId);
    Map<String, Integer> typeCounts = new Map<String, Integer>();
    List<Applicant__c> eligible = new List<Applicant__c>();

    for (Applicant__c applicant : applicantList) {
      if (isExcludedNiRepaymentApplicant(applicant) || applicant.Is_Primary__c != true) {
        continue;
      }
      Boolean isBorrower = 'Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c);
      if (!isBorrower && isPv && !hasRepaymentBankOptIn(applicant)) {
        continue;
      }
      String applicantType = String.isNotBlank(applicant.Applicant_Type__c)
        ? applicant.Applicant_Type__c
        : 'Applicant';
      typeCounts.put(
        applicantType,
        (typeCounts.containsKey(applicantType) ? typeCounts.get(applicantType) : 0) + 1
      );
      eligible.add(applicant);
    }

    wrapper.isNiApplication = true;
    wrapper.repaymentEligibleApplicants = eligible;
    wrapper.repaymentToBeDoneByOptions = new List<RepaymentApplicantOption>();
    for (Applicant__c applicant : eligible) {
      RepaymentApplicantOption opt = new RepaymentApplicantOption();
      opt.applicantId = applicant.Id;
      String applicantType = String.isNotBlank(applicant.Applicant_Type__c)
        ? applicant.Applicant_Type__c
        : 'Applicant';
      Integer typeCount = typeCounts.get(applicantType);
      opt.label = opt.value =
        typeCount != null &&
        typeCount > 1 &&
        String.isNotBlank(applicant.Applicant_Tab_Label__c)
          ? applicantType + ' ' + applicant.Applicant_Tab_Label__c
          : applicantType;
      wrapper.repaymentToBeDoneByOptions.add(opt);
    }
  }

  private static Boolean isPvRepaymentApplication(Id applicationId) {
    List<Application__c> apps = [
      SELECT Product__c, Sub_Product__c
      FROM Application__c
      WHERE Id = :applicationId
      WITH USER_MODE
      LIMIT 1
    ];
    return !apps.isEmpty() &&
      ('PV'.equalsIgnoreCase(
        GenericUtility.resolveProductTypeToken(apps[0].Product__c, apps[0].Sub_Product__c)
      ) ||
      '4W'.equalsIgnoreCase(apps[0].Product__c));
  }

  private static Boolean isExcludedNiRepaymentApplicant(Applicant__c applicant) {
    return applicant.Is_Sub_Applicant__c == true ||
      (applicant.Parent_Applicant__c != null && applicant.Applicant_Type__c == 'Guarantor');
  }

  private static Boolean hasRepaymentBankOptIn(Applicant__c applicant) {
    return applicant.Has_Bank_Account__c == 'Yes' ||
      applicant.Interested_In_Opening_Savings_Account__c == 'Yes';
  }

  private static Applicant__c getDefaultNiRepaymentApplicant(
    List<Applicant__c> eligibleApplicants,
    Applicant__c borrowerApplicant
  ) {
    return eligibleApplicants != null && !eligibleApplicants.isEmpty()
      ? eligibleApplicants[0]
      : borrowerApplicant;
  }

  private static Applicant__c resolveNiRepaymentApplicant(
    List<RepaymentApplicantOption> options,
    List<Applicant__c> eligibleApplicants,
    String repaymentDoneBy,
    Applicant__c defaultApplicant
  ) {
    if (options == null || String.isBlank(repaymentDoneBy)) {
      return defaultApplicant;
    }
    Map<Id, Applicant__c> applicantsById = new Map<Id, Applicant__c>(eligibleApplicants);
    for (RepaymentApplicantOption opt : options) {
      if (opt.value == repaymentDoneBy && applicantsById.containsKey(opt.applicantId)) {
        return applicantsById.get(opt.applicantId);
      }
    }
    return defaultApplicant;
  }

  private static String resolveRepaymentStageCompletedValue(String currentViewId) {
    if (REPAYMENT_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
      return REPAYMENT_OPS_STAGE;
    }
    return REPAYMENT_PSS_STAGE;
  }

  private static Id parseLineItemId(String applicationLineItemId) {
    if (String.isBlank(applicationLineItemId)) {
      return null;
    }
    try {
      return (Id) applicationLineItemId;
    } catch (Exception ex) {
      return null;
    }
  }

  private static String appendStageCompleted(String currentStages, String stageName) {
    if (String.isBlank(stageName) || hasStageCompleted(currentStages, stageName)) {
      return currentStages;
    }
    String stage = stageName.trim();
    return String.isBlank(currentStages) ? stage : currentStages + ';' + stage;
  }

  private static Boolean hasStageCompleted(String completedStages, String stageName) {
    if (String.isBlank(completedStages) || String.isBlank(stageName)) {
      return false;
    }
    for (String stage : completedStages.split(';')) {
      if (stageName.equalsIgnoreCase(stage.trim())) {
        return true;
      }
    }
    return false;
  }

  private static String resolveSavedRepaymentToBeDoneBy(String applicationId, Id lineItemId) {
    try {
      List<Repayment_Mandate__c> repaymentMandates = queryRepaymentMandates(applicationId, lineItemId);
      if (
        !repaymentMandates.isEmpty() &&
        String.isNotBlank(repaymentMandates[0].Repayment_to_be_done_by__c)
      ) {
        return repaymentMandates[0].Repayment_to_be_done_by__c;
      }
    } catch (Exception ex) {
      // Continue with default when mandate fields are unavailable.
    }
    return 'Borrower';
  }

  private static List<Repayment_Mandate__c> queryRepaymentMandates(
    String applicationId,
    Id lineItemId
  ) {
    if (lineItemId != null) {
      return [
        SELECT Id,
               Bank_Master__c,
               Repayment_Method__c,
               Account_Number__c,
               IFSC_Code__c,
               Branch_Name__c,
               Bank_Branch_City__c,
               Repayment_to_be_done_by__c,
               eSIGNType__c,
               Type_Of_Account__c,
               UPI_Id__c,
               Initiation_Method__c,
               All_Mandate_Details_Correctly_Entered__c,
               Remarks__c
        FROM Repayment_Mandate__c
        WHERE Application_Line_Items__c = :lineItemId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate ASC
        LIMIT 1
      ];
    }

    return Database.query(REPAYMENT_MANDATE_FORM_SOQL);
  }

  private static Repayment_Mandate__c buildRepaymentRecordFromAllowedFields(Map<String, Object> fieldMap) {
    Repayment_Mandate__c repaymentRecord = new Repayment_Mandate__c();

    for (String fieldName : fieldMap.keySet()) {
      if (!REPAYMENT_MANDATE_FORM_FIELDS.contains(fieldName)) {
        continue;
      }

      Object rawValue = fieldMap.get(fieldName);
      if (rawValue == null || String.valueOf(rawValue) == '') {
        continue;
      }

      if (fieldName == 'Id') {
        repaymentRecord.Id = toId(rawValue);
      } else if (fieldName == 'Bank_Master__c') {
        repaymentRecord.Bank_Master__c = resolveBankMasterId(rawValue);
      } else {
        repaymentRecord.put(fieldName, String.valueOf(rawValue));
      }
    }

    return repaymentRecord;
  }

  private static Id toId(Object value) {
    return value == null ? null : (Id) String.valueOf(value);
  }

  private static Id resolveBankMasterId(Object bankValue) {
    if (bankValue == null) {
      return null;
    }
    String bankValueStr = String.valueOf(bankValue);
    if (bankValueStr.length() == 15 || bankValueStr.length() == 18) {
      return (Id) bankValue;
    }
    return getBankIdByBankName(bankValueStr);
  }

  private static void putRecordType(
    Map<String, String> target,
    Map<String, Schema.RecordTypeInfo> rtMap,
    String key,
    String developerName
  ) {
    if (rtMap.containsKey(developerName) && rtMap.get(developerName).isAvailable()) {
      target.put(key, rtMap.get(developerName).getRecordTypeId());
    }
  }

  private static String getLatestContentVersionId(String contentDocumentId) {
    if (String.isBlank(contentDocumentId)) {
      return null;
    }
    List<ContentVersion> versions = [
      SELECT Id
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    return versions.isEmpty() ? null : versions[0].Id;
  }

  private static String getContentDocumentIdFromVersion(String contentVersionId) {
    if (String.isBlank(contentVersionId)) {
      return null;
    }
    List<ContentVersion> versions = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :contentVersionId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    return versions.isEmpty() ? null : versions[0].ContentDocumentId;
  }

}