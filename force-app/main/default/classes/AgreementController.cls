/**
 * Controller for agreement LWC (IBL P4AgreementController parity).
 * Application__c replaces Opportunity. Child records use Application__c lookup to Application Id.
 */
public with sharing class AgreementController {

  private static final String AGREEMENT_OBJECT = 'Agreement__c';
  private static final List<String> DOCUMENT_CHECKLIST_API_CANDIDATES = new List<String>{
    'Document_Checklist__c',
    'Document_CheckList__c'
  };
  private static final String DOC_TYPE_WRAPPER = 'Agreement Wrapper Booklet';
  private static final String DOC_TYPE_1ST = 'Agreement 1st Schedule';
  private static final String DOC_TYPE_2ND = 'Agreement 2nd Schedule';
  private static final String DOC_TYPE_STAMPING = 'Stamping Page';
  private static final String APPLICANT_BORROWER = 'Borrower';
  private static final String APPLICANT_COBORROWER = 'Co-borrower';
  private static final String STAMP_TOWARDS_AGREEMENT = 'AGREEMENT';
  private static final String STAMP_DETAIL_TYPE = 'Loan Agreement';
  private static final String STAMPING_SERVICE = 'StampingDetailsP4';
  private static final String NO_GEO_STATE = 'NoGeoStateCodeFound';
  private static final String AGREEMENT_PSS_STAGE = 'Agreement_PSS';
  private static final String AGREEMENT_OPS_STAGE = 'Agreement_OPS';
  private static final String AGREEMENT_OPS_VIEW_ID = 'Wheels_Agreement_OPS';

  private static final Set<String> KYC_DOC_TYPES = new Set<String>{
    'Aadhaar Card',
    'Aadhar Card',
    'PAN Card',
    'Passport',
    'Voter ID',
    'Driving Licence',
    'Driving License'
  };

  @AuraEnabled
  public static Boolean isPhysicalAgreement(String applicationId) {
    if (String.isBlank(applicationId)) {
      return true;
    }
    try {
      Application__c app = queryApplication(applicationId);
      if (app == null) {
        return true;
      }

      String storedType = getAgreementType(app);
      if (storedType == 'Physical agreement') {
        return true;
      }
      if (storedType == 'e-agreement') {
        return false;
      }

      Boolean ekycFlow = computeEkycFlow(applicationId);
      Boolean bypassEAgreement = isBypassEAgreementEnabled();
      String agreementType =
        (!bypassEAgreement && ekycFlow) ? 'e-agreement' : 'Physical agreement';

      persistAgreementType(applicationId, agreementType);
      return agreementType == 'Physical agreement';
    } catch (Exception ex) {
      throw new AuraHandledException('Error determining agreement type: ' + ex.getMessage());
    }
  }

  @AuraEnabled
  public static void setAgreementType(String applicationId, String agreementType) {
    if (String.isBlank(applicationId) || String.isBlank(agreementType)) {
      return;
    }
    persistAgreementType(applicationId, agreementType);
  }

  @AuraEnabled
  public static String getGeographicalState(String applicationId) {
    if (String.isBlank(applicationId)) {
      return null;
    }
    try {
      List<String> appFields = filterExistingFields(
        'Application__c',
        new List<String>{
          'Id',
          'Product__c',
          'Product_Type__c',
          'Sub_Product__c',
          'Product_Sub_Type__c',
          'Agent_BL_code__c'
        }
      );
      if (!appFields.contains('Id')) {
        return 'ANDHRA PRADESH_AP';
      }

      String soql = 'SELECT ' + String.join(appFields, ',') + ' FROM Application__c WHERE Id = :applicationId WITH SECURITY_ENFORCED LIMIT 1';
      List<SObject> apps = Database.query(soql);
      if (apps.isEmpty()) {
        return NO_GEO_STATE;
      }
      SObject app = apps[0];

      String productType = firstNonBlank(
        (String) app.get('Product_Type__c'),
        (String) app.get('Product__c')
      );
      String productSubType = firstNonBlank(
        (String) app.get('Product_Sub_Type__c'),
        (String) app.get('Sub_Product__c')
      );
      String blCode = (String) app.get('Agent_BL_code__c');
      String productCode = resolveProductCode(productType, productSubType);

      if (!objectExists('BankBranchDetails__c') || String.isBlank(blCode)) {
        return fallbackGeoState();
      }

      List<String> branchFields = filterExistingFields(
        'BankBranchDetails__c',
        new List<String>{ 'Geo_State_Code__c', 'Geo_State_Master__c', 'Bl_Code__c', 'Product__c' }
      );
      if (!branchFields.contains('Geo_State_Code__c') || !branchFields.contains('Bl_Code__c')) {
        return fallbackGeoState();
      }

      String branchSoql =
        'SELECT Geo_State_Code__c, Geo_State_Master__r.Name FROM BankBranchDetails__c' +
        ' WHERE Bl_Code__c = :blCode AND Geo_State_Code__c != NULL';
      if (branchFields.contains('Product__c') && String.isNotBlank(productCode)) {
        branchSoql += ' AND Product__c = :productCode';
      }
      branchSoql += ' WITH SECURITY_ENFORCED LIMIT 1';

      List<SObject> rows = Database.query(branchSoql);
      if (!rows.isEmpty()) {
        String name = (String) rows[0].getSObject('Geo_State_Master__r')?.get('Name');
        String code = (String) rows[0].get('Geo_State_Code__c');
        if (String.isNotBlank(name) && String.isNotBlank(code)) {
          return name + '_' + code;
        }
      }
      return NO_GEO_STATE;
    } catch (Exception ex) {
      return fallbackGeoState();
    }
  }

  /**
   * @description Loads agreement screen data: applicants, loan agreement, stamping, and document upload state.
   */
  @AuraEnabled
  public static AgreementDetailsWrapper getLoanAgreementDetails(
    String applicationId,
    String applicationLineItemId
  ) {
    AgreementDetailsWrapper wrapper = new AgreementDetailsWrapper();
    wrapper.documentMap = new Map<String, Boolean>{
      'wrapperBooklet' => false,
      'stampingPage' => false,
      'firstSchedule' => false,
      'secondSchedule' => false
    };
    if (String.isBlank(applicationId)) {
      return wrapper;
    }

    try {
      Id lineItemId = parseId(applicationLineItemId);
      loadApplicantIds(applicationId, wrapper);
      loadLoanAgreement(applicationId, lineItemId, wrapper);
      loadStampingFromLineItem(applicationId, lineItemId, wrapper);
      loadDocumentUploadFlags(applicationId, lineItemId, wrapper);
      loadAssetContext(applicationId, applicationLineItemId, wrapper);
      loadStampingLogs(applicationId, wrapper);
      wrapper.isReadOnly = computeAgreementReadOnly(wrapper);
      return wrapper;
    } catch (Exception ex) {
      throw new AuraHandledException('Error loading agreement details: ' + ex.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, Object> markAgreementStageComplete(
    String applicationLineItemId,
    String currentViewId
  ) {
    Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
    Id lineItemId = parseId(applicationLineItemId);
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

      String agreementStageKey = resolveAgreementStageCompletedValue(currentViewId);
      Application_Line_Item__c lineItem = lineItems[0];
      lineItem.Stage_Completed__c = appendStageCompleted(
        lineItem.Stage_Completed__c,
        agreementStageKey
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
  public static Map<String, Object> fetchAgreementBookletDetails(
    String responseStr,
    String loanAgreementId,
    String applicationId,
    String applicationLineItemId,
    String bookletNumber,
    String dealId,
    Decimal stampingCharges,
    Boolean isEStampApplicable,
    String geoStateCode,
    String agreementType
  ) {
    Map<String, Object> result = new Map<String, Object>();
    if (!objectExists(AGREEMENT_OBJECT)) {
      result.put('Id', loanAgreementId);
      result.put('success', true);
      return result;
    }

    Integer totalLoanAgreementStamping = 0;
    List<SObject> stampDetails = new List<SObject>();
    Date stampDate;

    if (String.isNotBlank(responseStr)) {
      try {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseStr);
        Map<String, Object> response = (Map<String, Object>) parsed.get('response');
        if (response == null) {
          response = parsed;
        }
        List<Object> contentList = (List<Object>) response.get('content');
        if (contentList != null && !contentList.isEmpty()) {
          Map<String, Object> firstContent = (Map<String, Object>) contentList[0];
          stampDate = parseStampDate((String) firstContent.get('Stamp_On'));
          for (Object item : contentList) {
            Map<String, Object> con = (Map<String, Object>) item;
            if (STAMP_TOWARDS_AGREEMENT.equals(con.get('Stamp_Towards'))) {
              SObject stmp = buildStampDetail(con, stampDate, null);
              if (stmp != null) {
                stampDetails.add(stmp);
                Object stampValue = con.get('Stamp_Value');
                if (stampValue != null) {
                  totalLoanAgreementStamping += Integer.valueOf(String.valueOf(stampValue));
                }
              }
            }
          }
        }
      } catch (Exception ex) {
        // Keep upsert even if booklet JSON parse fails.
      }
    }

    SObject loanAgr = newSObject(AGREEMENT_OBJECT);
    Id lineItemId = parseId(applicationLineItemId);
    if (String.isBlank(loanAgreementId) && lineItemId != null) {
      loanAgreementId = resolveLoanAgreementIdForLineItem(applicationId, lineItemId);
    }
    if (String.isNotBlank(loanAgreementId)) {
      loanAgr.put('Id', loanAgreementId);
    }
    putIfFieldExists(loanAgr, 'Agreement_Booklet_Num__c', bookletNumber);
    putIfFieldExists(loanAgr, 'Application__c', applicationId);
    putIfFieldExists(loanAgr, 'Application_Line_Items__c', lineItemId);
    putIfFieldExists(loanAgr, 'Required_Loan_Agreement_Stamping_Charges__c', stampingCharges);
    // Deal number is stored on Applicant__c.Deal_Number__c (text).
    // `dealId` param is treated as deal number for backward compatibility.
    putIfFieldExists(loanAgr, 'Deal_Number__c', dealId);
    putIfFieldExists(loanAgr, 'Geo_State_Code__c', geoStateCode);
    putIfFieldExists(loanAgr, 'Agreement_Type__c', agreementType);
    putIfFieldExists(loanAgr, 'AgreementDate__c', Date.today());
    putIfFieldExists(loanAgr, 'Total_Loan_Agreement_Stamping__c', totalLoanAgreementStamping);
    if (isEStampApplicable == true) {
      putIfFieldExists(loanAgr, 'Is_application_eligible_for_e_agreement__c', true);
    }

    applyLineItemDatesToLoanAgreement(loanAgr, applicationId, lineItemId);
    applyTeleVerificationToLoanAgreement(loanAgr, applicationId);

    upsert loanAgr;

    if (!stampDetails.isEmpty() && objectExists('Stamp_Detail__c')) {
      for (SObject stampRecord : stampDetails) {
        putIfFieldExists(stampRecord, 'Agreement__c', (String) loanAgr.get('Id'));
      }
      insert stampDetails;
    }

    result.put('Id', (String) loanAgr.get('Id'));
    result.put('success', true);
    return result;
  }

  @AuraEnabled
  public static Map<String, Object> checkApiExecutionStatus(
    String applicationId,
    String vehicleId,
    String serviceName
  ) {
    Map<String, Object> result = new Map<String, Object>();
    result.put('shouldSkip', false);
    result.put('message', 'API never called before, will execute');

    if (String.isBlank(applicationId) || !objectExists('Integration_Log__c')) {
      return result;
    }

    List<String> fields = filterExistingFields(
      'Integration_Log__c',
      new List<String>{ 'Id', 'Status__c', 'Original_response__c', 'Service_Name__c', 'Application__c' }
    );
    if (!fields.contains('Status__c') || !fields.contains('Original_response__c')) {
      return result;
    }
    if (!fields.contains('Service_Name__c') || !fields.contains('Application__c')) {
      return result;
    }

    String soql =
      'SELECT ' +
      String.join(fields, ',') +
      ' FROM Integration_Log__c WHERE Application__c = :applicationId AND Service_Name__c = :serviceName' +
      ' WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT 1';
    List<SObject> logs = Database.query(soql);

    if (!logs.isEmpty()) {
      SObject log = logs[0];
      String status = (String) log.get('Status__c');
      result.put('status', status);
      if (status == 'SUCCESS' || status == 'Success') {
        result.put('shouldSkip', true);
        result.put('cachedResponse', (String) log.get('Original_response__c'));
        result.put('message', 'API already succeeded, using cached response');
      } else {
        result.put('message', 'API failed previously, will retry');
      }
    }
    return result;
  }

  /**
   * @description Creates or returns Document_CheckList__c row for applicant-scoped uploads.
   */
  @AuraEnabled
  public static String initOrGetDocumentWithApplicantId(
    String applicationId,
    String documentType,
    String applicantId,
    String applicationLineItemId
  ) {
    return initOrGetDocument(
      applicationId,
      documentType,
      applicantId,
      applicationLineItemId
    );
  }

  /**
   * @description Creates or returns Document_CheckList__c row for applicant-scoped uploads.
   */
  @AuraEnabled
  public static String initOrGetDocument(
    String applicationId,
    String documentType,
    String applicantId,
    String applicationLineItemId
  ) {
    if (String.isBlank(applicationId) || String.isBlank(documentType)) {
      throw new AuraHandledException('Application Id and document type are required');
    }

    String checklistObject = getDocumentChecklistObjectApiName();
    if (String.isBlank(checklistObject)) {
      return applicationId;
    }

    List<String> fields = filterExistingFields(
      checklistObject,
      new List<String>{
        'Id',
        'Application__c',
        'Applicant__c',
        'Application_Line_Items__c',
        'Document_Type__c',
        'ContentVersionId__c',
        'Name'
      }
    );
    if (!fields.contains('Id') || !fields.contains('Document_Type__c')) {
      return applicationId;
    }

    Id lineItemId = parseId(applicationLineItemId);

    String whereClause = 'Document_Type__c = :documentType';
    if (fields.contains('Application__c')) {
      whereClause += ' AND Application__c = :applicationId';
    }
    if (fields.contains('Applicant__c') && String.isNotBlank(applicantId)) {
      whereClause += ' AND Applicant__c = :applicantId';
    }
    if (lineItemId != null && fields.contains('Application_Line_Items__c')) {
      whereClause += ' AND Application_Line_Items__c = :lineItemId';
    }

    String soql =
      'SELECT ' +
      String.join(fields, ',') +
      ' FROM ' +
      checklistObject +
      ' WHERE ' +
      whereClause +
      ' ORDER BY CreatedDate DESC LIMIT 1';
    List<SObject> existing = Database.query(soql);

    if (!existing.isEmpty()) {
      return (String) existing[0].get('Id');
    }

    SObject newRow = newSObject(checklistObject);
    putIfFieldExists(newRow, 'Name', documentType + ' - Document');
    putIfFieldExists(newRow, 'Document_Type__c', documentType);
    putIfFieldExists(newRow, 'Application__c', applicationId);
    putIfFieldExists(newRow, 'Applicant__c', applicantId);
    putIfFieldExists(newRow, 'Application_Line_Items__c', lineItemId);
    insert newRow;
    return (String) newRow.get('Id');
  }

  @AuraEnabled
  public static List<Map<String, Object>> getContentDocuments(String documentId, String documentType) {
    List<Map<String, Object>> files = new List<Map<String, Object>>();
    if (String.isBlank(documentId)) {
      return files;
    }

    String checklistObject = getDocumentChecklistObjectApiName();
    if (String.isNotBlank(checklistObject) && fieldExists(checklistObject, 'ContentVersionId__c')) {
      List<String> fields = filterExistingFields(checklistObject, new List<String>{ 'Id', 'ContentVersionId__c', 'Name' });
      if (fields.contains('ContentVersionId__c')) {
        String soql =
          'SELECT ' + String.join(fields, ',') + ' FROM ' + checklistObject + ' WHERE Id = :documentId WITH SECURITY_ENFORCED LIMIT 1';
        List<SObject> rows = Database.query(soql);
        if (!rows.isEmpty()) {
          String versionId = (String) rows[0].get('ContentVersionId__c');
          Map<String, Object> fileMeta = buildFileMetaFromContentVersionId(versionId, (String) rows[0].get('Name'));
          if (fileMeta != null) {
            files.add(fileMeta);
          }
        }
      }
    }

    if (files.isEmpty()) {
      for (ContentDocumentLink link : [
        SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :documentId
        WITH SECURITY_ENFORCED
      ]) {
        files.add(buildFileMetaFromContentDocument(link.ContentDocumentId, link.ContentDocument.Title, link.ContentDocument.FileExtension));
      }
    }
    return files;
  }

  @AuraEnabled
  public static Boolean deleteContentDocument(String contentDocumentId) {
    if (String.isBlank(contentDocumentId)) {
      return false;
    }
    String versionId = resolveLatestContentVersionId(contentDocumentId);
    clearDocumentChecklistContentVersion(versionId);
    delete [SELECT Id FROM ContentDocument WHERE Id = :contentDocumentId WITH SECURITY_ENFORCED];
    return true;
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
      WHERE ContentDocumentId = :contentDocumentId
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (versions.isEmpty() || String.isBlank(versions[0].FileExtension)) {
      return 'PDF';
    }
    return versions[0].FileExtension.toUpperCase();
  }

  /**
   * @description Links uploaded ContentDocument to Document_CheckList__c (or LinkedEntity fallback).
   */
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

    if (String.isBlank(contentDocumentId)) {
      return;
    }

    String checklistId = initOrGetDocument(
      applicationId,
      documentType,
      applicantId,
      applicationLineItemId
    );
    String contentVersionId = resolveLatestContentVersionId(contentDocumentId);
    String checklistObject = getDocumentChecklistObjectApiName();

    if (
      String.isNotBlank(checklistObject) &&
      String.isNotBlank(checklistId) &&
      String.isNotBlank(contentVersionId) &&
      fieldExists(checklistObject, 'ContentVersionId__c')
    ) {
      SObject row = newSObject(checklistObject);
      row.put('Id', checklistId);
      row.put('ContentVersionId__c', contentVersionId);
      update row;
      return;
    }

    if (String.isBlank(checklistId)) {
      checklistId = applicationId;
    }
    List<ContentDocumentLink> links = [
      SELECT Id
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :checklistId AND ContentDocumentId = :contentDocumentId
      LIMIT 1
    ];
    if (links.isEmpty() && String.isNotBlank(checklistId)) {
      insert new ContentDocumentLink(
        LinkedEntityId = checklistId,
        ContentDocumentId = contentDocumentId,
        ShareType = 'V',
        Visibility = 'AllUsers'
      );
    }
  }

  public class AgreementDetailsWrapper {
    @AuraEnabled public Map<String, Boolean> documentMap;
    @AuraEnabled public Map<String, Object> documentFiles;
    @AuraEnabled public Boolean isReadOnly = false;
    @AuraEnabled public Decimal stampingCharges;
    @AuraEnabled public String bookletNumber;
    @AuraEnabled public Boolean isEStampApplicable = false;
    @AuraEnabled public String initiationMethod;
    @AuraEnabled public Boolean initiatedEAgreement = false;
    @AuraEnabled public Boolean checkStatus = false;
    @AuraEnabled public Boolean downloadAgreement = false;
    @AuraEnabled public String vehicleId;
    @AuraEnabled public String borrowerId;
    @AuraEnabled public String coBorrowerId;
    @AuraEnabled public String loanAgreementId;
    @AuraEnabled public String dealId;
    @AuraEnabled public String dealNumber;
    @AuraEnabled public List<Map<String, Object>> stampingLogs;
    @AuraEnabled public String agreementCorrectlyCaptured;
    @AuraEnabled public String remarks;
  }

  private static Application__c queryApplication(String applicationId) {
    List<String> fields = filterExistingFields('Application__c', new List<String>{ 'Id', 'Agreement_Type__c' });
    if (!fields.contains('Id')) {
      return null;
    }
    String soql =
      'SELECT ' + String.join(fields, ',') + ' FROM Application__c WHERE Id = :applicationId WITH SECURITY_ENFORCED LIMIT 1';
    List<Application__c> apps = Database.query(soql);
    return apps.isEmpty() ? null : apps[0];
  }

  private static String getAgreementType(Application__c app) {
    if (app == null) {
      return null;
    }
    if (app.getSObjectType().getDescribe().fields.getMap().containsKey('Agreement_Type__c')) {
      return (String) app.get('Agreement_Type__c');
    }
    return null;
  }

  private static void persistAgreementType(String applicationId, String agreementType) {
    if (!fieldExists('Application__c', 'Agreement_Type__c')) {
      return;
    }
    update new Application__c(Id = applicationId, Agreement_Type__c = agreementType);
  }

  private static Boolean computeEkycFlow(String applicationId) {
    List<Applicant__c> applicants = queryActiveApplicants(applicationId);
    if (applicants.isEmpty()) {
      return false;
    }

    Map<Id, List<String>> applicantVsDocTypes = loadApplicantKycDocTypes(applicants);
    Boolean onlyBorrower =
      applicants.size() == 1 && APPLICANT_BORROWER.equals(normalizeApplicantType(applicants[0].Applicant_Type__c));

    if (onlyBorrower) {
      return applicantMeetsEkycCriteria(applicantVsDocTypes.get(applicants[0].Id));
    }

    for (Applicant__c applicant : applicants) {
      if (!applicantMeetsEkycCriteria(applicantVsDocTypes.get(applicant.Id))) {
        return false;
      }
    }
    return true;
  }

  private static Boolean applicantMeetsEkycCriteria(List<String> docs) {
    if (docs == null || docs.size() <= 1) {
      return false;
    }
    for (String docType : docs) {
      if (docType != null && (docType.containsIgnoreCase('Aadhaar') || docType.containsIgnoreCase('Aadhar'))) {
        return true;
      }
    }
    return false;
  }

  private static List<Applicant__c> queryActiveApplicants(String applicationId) {
    List<String> fields = filterExistingFields(
      'Applicant__c',
      new List<String>{ 'Id', 'Applicant_Type__c', 'Application__c', 'In_Active_Applicant__c' }
    );
    if (!fields.contains('Id') || !fields.contains('Application__c')) {
      return new List<Applicant__c>();
    }
    String soql =
      'SELECT ' +
      String.join(fields, ',') +
      ' FROM Applicant__c WHERE Application__c = :applicationId';
    if (fields.contains('In_Active_Applicant__c')) {
      soql += ' AND In_Active_Applicant__c = FALSE';
    }
    soql += ' WITH SECURITY_ENFORCED';
    return Database.query(soql);
  }

  private static Map<Id, List<String>> loadApplicantKycDocTypes(List<Applicant__c> applicants) {
    Map<Id, List<String>> applicantVsDocTypes = new Map<Id, List<String>>();
    for (Applicant__c applicant : applicants) {
      applicantVsDocTypes.put(applicant.Id, new List<String>());
    }
    String checklistObject = getDocumentChecklistObjectApiName();
    if (String.isBlank(checklistObject)) {
      return applicantVsDocTypes;
    }

    Set<Id> applicantIds = new Map<Id, Applicant__c>(applicants).keySet();
    List<String> fields = filterExistingFields(
      checklistObject,
      new List<String>{ 'Id', 'Document_Type__c', 'Applicant__c', 'ContentVersionId__c' }
    );
    if (!fields.contains('Applicant__c') || !fields.contains('Document_Type__c')) {
      return applicantVsDocTypes;
    }

    String soql =
      'SELECT ' +
      String.join(fields, ',') +
      ' FROM ' +
      checklistObject +
      ' WHERE Applicant__c IN :applicantIds AND Document_Type__c IN :KYC_DOC_TYPES';
    if (fields.contains('ContentVersionId__c')) {
      soql += ' AND ContentVersionId__c != NULL';
    }
    soql += ' WITH SECURITY_ENFORCED';

    for (SObject doc : Database.query(soql)) {
      Id applicantId = (Id) doc.get('Applicant__c');
      if (!applicantVsDocTypes.containsKey(applicantId)) {
        applicantVsDocTypes.put(applicantId, new List<String>());
      }
      applicantVsDocTypes.get(applicantId).add((String) doc.get('Document_Type__c'));
    }
    return applicantVsDocTypes;
  }

  private static Boolean isBypassEAgreementEnabled() {
    // Set to true when org uses custom label BypassEAgreementFlow = Yes (IBL parity).
    return false;
  }

  private static void loadApplicantIds(String applicationId, AgreementDetailsWrapper wrapper) {
    for (Applicant__c app : queryActiveApplicants(applicationId)) {
      String type = normalizeApplicantType(app.Applicant_Type__c);
      if (type == APPLICANT_BORROWER) {
        wrapper.borrowerId = app.Id;
      } else if (type == APPLICANT_COBORROWER) {
        wrapper.coBorrowerId = app.Id;
      }
    }
  }

  private static void loadLoanAgreement(
    String applicationId,
    Id lineItemId,
    AgreementDetailsWrapper wrapper
  ) {
    if (!objectExists(AGREEMENT_OBJECT)) {
      return;
    }
    List<String> fields = filterExistingFields(
      AGREEMENT_OBJECT,
      new List<String>{
        'Id',
        'Application__c',
        'Application_Line_Items__c',
        'Agreement_Booklet_Num__c',
        'Required_Loan_Agreement_Stamping_Charges__c',
        'Is_application_eligible_for_e_agreement__c',
        'Add_POA_SD_Initiation_method__c',
        'Initiated_E_Agreement__c',
        'Check_Status__c',
        'Add_POA_SD_Agreement_signed__c',
        'Agreement_Correctly_Captured__c',
        'Remarks__c'
      }
    );
    if (fields.isEmpty()) {
      return;
    }
    String soql =
      'SELECT ' +
      String.join(fields, ',') +
      ' FROM ' +
      AGREEMENT_OBJECT +
      ' WHERE Application__c = :applicationId';
    if (lineItemId != null && fields.contains('Application_Line_Items__c')) {
      soql += ' AND Application_Line_Items__c = :lineItemId';
    }
    soql += ' WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT 1';
    List<SObject> rows = Database.query(soql);
    if (rows.isEmpty()) {
      return;
    }
    SObject row = rows[0];
    wrapper.loanAgreementId = (String) row.get('Id');
    wrapper.bookletNumber = (String) row.get('Agreement_Booklet_Num__c');
    wrapper.stampingCharges = (Decimal) row.get('Required_Loan_Agreement_Stamping_Charges__c');
    Object eStamp = row.get('Is_application_eligible_for_e_agreement__c');
    wrapper.isEStampApplicable = eStamp == true;
    wrapper.initiationMethod = (String) row.get('Add_POA_SD_Initiation_method__c');
    wrapper.initiatedEAgreement = row.get('Initiated_E_Agreement__c') == true;
    wrapper.checkStatus = row.get('Check_Status__c') == true;
    wrapper.downloadAgreement = row.get('Add_POA_SD_Agreement_signed__c') == true;
    wrapper.agreementCorrectlyCaptured = (String) row.get('Agreement_Correctly_Captured__c');
    wrapper.remarks = (String) row.get('Remarks__c');
  }

  private static void loadStampingFromLineItem(
    String applicationId,
    Id lineItemId,
    AgreementDetailsWrapper wrapper
  ) {
    if (wrapper.stampingCharges != null) {
      return;
    }

    if (!objectExists('Application_Line_Item__c')) {
      wrapper.stampingCharges = 200;
      return;
    }

    List<String> fields = filterExistingFields(
      'Application_Line_Item__c',
      new List<String>{ 'Stamping_Charges_from_API__c', 'Application__c' }
    );
    if (!fields.contains('Stamping_Charges_from_API__c') || !fields.contains('Application__c')) {
      wrapper.stampingCharges = 200;
      return;
    }

    String soql =
      'SELECT ' +
      String.join(fields, ',') +
      ' FROM Application_Line_Item__c WHERE Application__c = :applicationId WITH SECURITY_ENFORCED ORDER BY CreatedDate ASC LIMIT 1';
    List<SObject> items = Database.query(soql);
    if (!items.isEmpty() && items[0].get('Stamping_Charges_from_API__c') != null) {
      wrapper.stampingCharges = Decimal.valueOf(String.valueOf(items[0].get('Stamping_Charges_from_API__c')));
      return;
    }

    wrapper.stampingCharges = 200;
  }

  private static void loadDocumentUploadFlags(
    String applicationId,
    Id lineItemId,
    AgreementDetailsWrapper wrapper
  ) {
    Map<String, Boolean> documentMap = new Map<String, Boolean>{
      'wrapperBooklet' => false,
      'stampingPage' => false,
      'firstSchedule' => false,
      'secondSchedule' => false
    };
    Map<String, Object> documentFiles = new Map<String, Object>{
      'wrapperBooklet' => emptyDocumentFileEntry(),
      'stampingPage' => emptyDocumentFileEntry(),
      'firstSchedule' => emptyDocumentFileEntry(),
      'secondSchedule' => emptyDocumentFileEntry()
    };

    String checklistObject = getDocumentChecklistObjectApiName();
    if (String.isBlank(checklistObject)) {
      wrapper.documentMap = documentMap;
      wrapper.documentFiles = documentFiles;
      return;
    }
    Set<String> types = new Set<String>{ DOC_TYPE_WRAPPER, DOC_TYPE_1ST, DOC_TYPE_2ND, DOC_TYPE_STAMPING };
    List<String> fields = filterExistingFields(
      checklistObject,
      new List<String>{
        'Id',
        'Application__c',
        'Application_Line_Items__c',
        'Document_Type__c',
        'ContentVersionId__c',
        'Name'
      }
    );
    if (!fields.contains('Document_Type__c')) {
      wrapper.documentMap = documentMap;
      wrapper.documentFiles = documentFiles;
      return;
    }

    Set<Id> contentVersionIds = new Set<Id>();
    List<SObject> checklistRows = new List<SObject>();
    String soql =
      'SELECT ' +
      String.join(fields, ',') +
      ' FROM ' +
      checklistObject +
      ' WHERE Document_Type__c IN :types';
    if (fields.contains('Application__c')) {
      soql += ' AND Application__c = :applicationId';
    }
    if (lineItemId != null && fields.contains('Application_Line_Items__c')) {
      soql += ' AND Application_Line_Items__c = :lineItemId';
    }
    soql += ' WITH SECURITY_ENFORCED';
    for (SObject doc : Database.query(soql)) {
      checklistRows.add(doc);
      if (fields.contains('ContentVersionId__c') && String.isNotBlank((String) doc.get('ContentVersionId__c'))) {
        contentVersionIds.add((Id) doc.get('ContentVersionId__c'));
      }
    }

    Map<Id, ContentVersion> versionById = new Map<Id, ContentVersion>();
    if (!contentVersionIds.isEmpty()) {
      versionById = new Map<Id, ContentVersion>([
        SELECT Id, Title, ContentDocumentId, FileExtension
        FROM ContentVersion
        WHERE Id IN :contentVersionIds
        WITH SECURITY_ENFORCED
      ]);
    }

    for (SObject doc : checklistRows) {
      String key = mapDocumentTypeToKey((String) doc.get('Document_Type__c'));
      if (key == null) {
        continue;
      }

      Boolean hasFile = false;
      String fileName = '';
      String contentDocumentId = '';
      String checklistId = (String) doc.get('Id');

      if (fields.contains('ContentVersionId__c')) {
        String versionId = (String) doc.get('ContentVersionId__c');
        if (String.isNotBlank(versionId) && versionById.containsKey(versionId)) {
          ContentVersion version = versionById.get(versionId);
          hasFile = true;
          fileName = version.Title;
          contentDocumentId = version.ContentDocumentId;
        }
      }

      if (!hasFile) {
        Id checklistRowId = (Id) doc.get('Id');
        List<ContentDocumentLink> links = [
          SELECT ContentDocumentId, ContentDocument.Title
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :checklistRowId
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        if (!links.isEmpty()) {
          hasFile = true;
          contentDocumentId = links[0].ContentDocumentId;
          fileName = links[0].ContentDocument.Title;
        }
      }

      documentMap.put(key, hasFile);
      documentFiles.put(
        key,
        new Map<String, Object>{
          'uploaded' => hasFile,
          'documentChecklistId' => checklistId,
          'fileName' => fileName,
          'contentDocumentId' => contentDocumentId
        }
      );
    }

    wrapper.documentMap = documentMap;
    wrapper.documentFiles = documentFiles;
  }

  private static Map<String, Object> emptyDocumentFileEntry() {
    return new Map<String, Object>{
      'uploaded' => false,
      'documentChecklistId' => null,
      'fileName' => '',
      'contentDocumentId' => null
    };
  }

  private static Boolean computeAgreementReadOnly(AgreementDetailsWrapper wrapper) {
    if (wrapper == null) {
      return false;
    }
    if (wrapper.downloadAgreement == true) {
      return true;
    }
    if (wrapper.documentMap == null) {
      return false;
    }
    return wrapper.documentMap.get('wrapperBooklet') == true &&
      wrapper.documentMap.get('stampingPage') == true &&
      wrapper.documentMap.get('firstSchedule') == true &&
      wrapper.documentMap.get('secondSchedule') == true &&
      String.isNotBlank(wrapper.bookletNumber);
  }

  private static void loadAssetContext(
    String applicationId,
    String applicationLineItemId,
    AgreementDetailsWrapper wrapper
  ) {
    // Deal number is now stored on Applicant__c.Deal_Number__c (field),
    // not on the Deal_Number__c custom object.
    loadBorrowerDealNumber(wrapper);

    Id lineItemId = parseId(applicationLineItemId);
    if (objectExists('Asset__c')) {
      List<String> assetFields = filterExistingFields(
        'Asset__c',
        new List<String>{
          'Id',
          'Application__c',
          'Application_Line_Items__c',
          'Deal_Number__c',
          'is_Active__c'
        }
      );
      if (assetFields.contains('Id')) {
        String assetSoql = 'SELECT Id';
        assetSoql += ' FROM Asset__c WHERE ';
        if (lineItemId != null && assetFields.contains('Application_Line_Items__c')) {
          assetSoql += 'Application_Line_Items__c = :lineItemId';
        } else if (assetFields.contains('Application__c')) {
          assetSoql += 'Application__c = :applicationId';
        } else {
          assetSoql = null;
        }
        if (assetSoql != null) {
          if (assetFields.contains('is_Active__c')) {
            assetSoql += ' AND is_Active__c = TRUE';
          }
          assetSoql += ' WITH SECURITY_ENFORCED LIMIT 1';
          List<SObject> assets = Database.query(assetSoql);
          if (!assets.isEmpty()) {
            wrapper.vehicleId = (String) assets[0].get('Id');
          }
        }
      }
    }

    if (objectExists('Vehicle_Detail__c')) {
      List<String> vdFields = filterExistingFields(
        'Vehicle_Detail__c',
        new List<String>{ 'Id', 'Application__c', 'Deal_Number__c', 'is_Active__c' }
      );
      if (vdFields.contains('Application__c')) {
        String vdSoql = 'SELECT Id';
        vdSoql += ' FROM Vehicle_Detail__c WHERE Application__c = :applicationId';
        if (vdFields.contains('is_Active__c')) {
          vdSoql += ' AND is_Active__c = TRUE';
        }
        vdSoql += ' WITH SECURITY_ENFORCED LIMIT 1';
        List<SObject> vehicles = Database.query(vdSoql);
        if (!vehicles.isEmpty()) {
          wrapper.vehicleId = (String) vehicles[0].get('Id');
        }
      }
    }
  }

  private static void loadBorrowerDealNumber(AgreementDetailsWrapper wrapper) {
    if (wrapper == null || String.isBlank(wrapper.borrowerId) || !fieldExists('Applicant__c', 'Deal_Number__c')) {
      return;
    }
    List<Applicant__c> borrowers = [
      SELECT Deal_Number__c
      FROM Applicant__c
      WHERE Id = :wrapper.borrowerId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (!borrowers.isEmpty()) {
      wrapper.dealId = borrowers[0].Deal_Number__c;
      wrapper.dealNumber = borrowers[0].Deal_Number__c;
    }
  }

  private static void loadStampingLogs(String applicationId, AgreementDetailsWrapper wrapper) {
    wrapper.stampingLogs = new List<Map<String, Object>>();
    if (String.isBlank(applicationId) || !objectExists('Integration_Log__c')) {
      return;
    }
    Map<String, Object> statusResult = checkApiExecutionStatus(applicationId, wrapper.vehicleId, STAMPING_SERVICE);
    if (statusResult.containsKey('cachedResponse')) {
      wrapper.stampingLogs.add(
        new Map<String, Object>{
          'Status__c' => statusResult.get('status'),
          'Original_response__c' => statusResult.get('cachedResponse')
        }
      );
    }
  }

  private static void applyLineItemDatesToLoanAgreement(
    SObject loanAgr,
    String applicationId,
    Id lineItemId
  ) {
    if (!objectExists('Application_Line_Item__c')) {
      return;
    }
    List<String> fields = filterExistingFields(
      'Application_Line_Item__c',
      new List<String>{ 'First_EMI_Date__c', 'Second_EMI_Date__c', 'Application__c' }
    );
    if (!fields.contains('First_EMI_Date__c') && !fields.contains('Second_EMI_Date__c')) {
      return;
    }

    List<SObject> rows = new List<SObject>();
    if (lineItemId != null) {
      rows = [
        SELECT First_EMI_Date__c, Second_EMI_Date__c
        FROM Application_Line_Item__c
        WHERE Id = :lineItemId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
    } else if (fields.contains('Application__c')) {
      String soql =
        'SELECT ' +
        String.join(fields, ',') +
        ' FROM Application_Line_Item__c WHERE Application__c = :applicationId WITH SECURITY_ENFORCED ORDER BY CreatedDate ASC LIMIT 1';
      rows = Database.query(soql);
    }
    if (rows.isEmpty()) {
      return;
    }
    SObject li = rows[0];
    putIfFieldExists(loanAgr, 'Ist_EMI_Due_Date__c', li.get('First_EMI_Date__c'));
    putIfFieldExists(loanAgr, 'X2nd_EMI_Due_Date__c', li.get('Second_EMI_Date__c'));
  }

  private static void applyTeleVerificationToLoanAgreement(SObject loanAgr, String applicationId) {
    if (!objectExists('TeleVerification__c')) {
      return;
    }
    List<String> fields = filterExistingFields(
      'TeleVerification__c',
      new List<String>{
        'Is_customer_having_an_Aadhar_Card__c',
        'Is_customer_using_Aadhar_Linked_Mob_No__c',
        'Is_customer_s_Mob_No_linked_to_Aadhar__c',
        'Applicant__c',
        'Application__c'
      }
    );
    if (!fields.contains('Application__c')) {
      return;
    }
    String soql = 'SELECT ' + String.join(fields, ',');
    if (fieldExists('TeleVerification__c', 'Applicant__c')) {
      soql += ', Applicant__r.Applicant_Type__c';
    }
    soql += ' FROM TeleVerification__c WHERE Application__c = :applicationId WITH SECURITY_ENFORCED';
    for (SObject tvr : Database.query(soql)) {
      String applicantType = null;
      if (tvr.getSObject('Applicant__r') != null) {
        applicantType = (String) tvr.getSObject('Applicant__r').get('Applicant_Type__c');
      }
      applicantType = normalizeApplicantType(applicantType);
      if (applicantType == APPLICANT_BORROWER) {
        putIfFieldExists(loanAgr, 'Borrower_Has_Aadharcard__c', tvr.get('Is_customer_having_an_Aadhar_Card__c'));
        putIfFieldExists(loanAgr, 'Borrower_Aadhar_Mobile_In_Use__c', tvr.get('Is_customer_using_Aadhar_Linked_Mob_No__c'));
        putIfFieldExists(loanAgr, 'Borrower_Aadhar_Linked_To_Mobile__c', tvr.get('Is_customer_s_Mob_No_linked_to_Aadhar__c'));
      } else if (applicantType == APPLICANT_COBORROWER) {
        putIfFieldExists(loanAgr, 'CoBorrower_Has_Aadharcard__c', tvr.get('Is_customer_having_an_Aadhar_Card__c'));
        putIfFieldExists(loanAgr, 'CoBorrower_Aadhar_Mobile_In_Use__c', tvr.get('Is_customer_using_Aadhar_Linked_Mob_No__c'));
        putIfFieldExists(loanAgr, 'CoBorrower_Aadhar_Linked_To_Mobile__c', tvr.get('Is_customer_s_Mob_No_linked_to_Aadhar__c'));
      }
    }
  }

  private static SObject buildStampDetail(Map<String, Object> content, Date stampDate, Id loanAgreementId) {
    if (!objectExists('Stamp_Detail__c')) {
      return null;
    }
    SObject stmp = newSObject('Stamp_Detail__c');
    putIfFieldExists(stmp, 'Stamp_S_No__c', content.get('Stamp_S_No'));
    putIfFieldExists(stmp, 'Stamp_Towards__c', content.get('Stamp_Towards'));
    putIfFieldExists(stmp, 'Stamp_Type__c', content.get('Stamp_Type'));
    Object stampValue = content.get('Stamp_Value');
    if (stampValue != null) {
      putIfFieldExists(stmp, 'Stamp_Value__c', Decimal.valueOf(String.valueOf(stampValue)));
    }
    putIfFieldExists(stmp, 'Stamp_Date__c', stampDate);
    putIfFieldExists(stmp, 'Stamp_For__c', content.get('Stamped_For'));
    putIfFieldExists(stmp, 'Stamp_Printed_Location_Blcode__c', content.get('Stamp_Printed_Location_Blcode'));
    putIfFieldExists(stmp, 'Stamp_Printed_Location_BlName__c', content.get('Stamp_Printed_Location_BlName'));
    putIfFieldExists(stmp, 'Type__c', STAMP_DETAIL_TYPE);
    putIfFieldExists(stmp, 'Agreement__c', loanAgreementId);
    return stmp;
  }

  private static Date parseStampDate(String stampOnDate) {
    if (String.isBlank(stampOnDate)) {
      return null;
    }
    List<String> dateList = stampOnDate.split('/');
    if (dateList.size() == 3) {
      try {
        return Date.newInstance(
          Integer.valueOf(dateList[2]),
          Integer.valueOf(dateList[1]),
          Integer.valueOf(dateList[0])
        );
      } catch (Exception ex) {
        return null;
      }
    }
    return null;
  }

  private static String resolveProductCode(String productType, String productSubType) {
    if (String.isBlank(productType)) {
      return '';
    }
    if (productType.equalsIgnoreCase('Two Wheeler')) {
      return 'H';
    }
    if (productType.equalsIgnoreCase('Passenger Vehicles')) {
      return 'C';
    }
    if (productType.equalsIgnoreCase('Tractor')) {
      return 'T';
    }
    if (productType.equalsIgnoreCase('Commercial Vehicle')) {
      if (String.isNotBlank(productSubType)) {
        if (productSubType.equalsIgnoreCase('Small Commercial Vehicle')) {
          return 'G';
        }
        if (productSubType.equalsIgnoreCase('Light Commercial Vehicle')) {
          return 'L';
        }
        if (productSubType.equalsIgnoreCase('Construction Equipment')) {
          return 'E';
        }
        if (productSubType.equalsIgnoreCase('Medium and Heavy Commercial Vehicles')) {
          return 'D';
        }
      }
    }
    return productType.substring(0, 1);
  }

  private static String fallbackGeoState() {
    return 'ANDHRA PRADESH_AP';
  }

  private static String firstNonBlank(String first, String second) {
    return String.isNotBlank(first) ? first : second;
  }

  private static String mapDocumentTypeToKey(String documentType) {
    if (documentType == DOC_TYPE_WRAPPER) {
      return 'wrapperBooklet';
    }
    if (documentType == DOC_TYPE_1ST) {
      return 'firstSchedule';
    }
    if (documentType == DOC_TYPE_2ND) {
      return 'secondSchedule';
    }
    if (documentType == DOC_TYPE_STAMPING) {
      return 'stampingPage';
    }
    return null;
  }

  private static String getDocumentChecklistObjectApiName() {
    for (String apiName : DOCUMENT_CHECKLIST_API_CANDIDATES) {
      if (objectExists(apiName)) {
        return apiName;
      }
    }
    return null;
  }

  private static String resolveLatestContentVersionId(String contentDocumentId) {
    if (String.isBlank(contentDocumentId)) {
      return null;
    }
    List<ContentVersion> versions = [
      SELECT Id
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return versions.isEmpty() ? null : versions[0].Id;
  }

  private static Map<String, Object> buildFileMetaFromContentVersionId(String contentVersionId, String fallbackName) {
    if (String.isBlank(contentVersionId)) {
      return null;
    }
    List<ContentVersion> versions = [
      SELECT Id, Title, FileExtension, ContentDocumentId
      FROM ContentVersion
      WHERE Id = :contentVersionId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (versions.isEmpty()) {
      return null;
    }
    ContentVersion cv = versions[0];
    return buildFileMetaFromContentDocument(
      cv.ContentDocumentId,
      String.isNotBlank(cv.Title) ? cv.Title : fallbackName,
      cv.FileExtension
    );
  }

  private static Map<String, Object> buildFileMetaFromContentDocument(
    Id contentDocumentId,
    String title,
    String fileExtension
  ) {
    if (contentDocumentId == null) {
      return null;
    }
    String ext = fileExtension != null ? fileExtension.toLowerCase() : '';
    return new Map<String, Object>{
      'id' => contentDocumentId,
      'name' => title,
      'contentDocumentId' => contentDocumentId,
      'isImage' => ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'gif',
      'isPdf' => ext == 'pdf'
    };
  }

  private static void clearDocumentChecklistContentVersion(String contentVersionId) {
    if (String.isBlank(contentVersionId)) {
      return;
    }
    String checklistObject = getDocumentChecklistObjectApiName();
    if (String.isBlank(checklistObject) || !fieldExists(checklistObject, 'ContentVersionId__c')) {
      return;
    }
    List<SObject> rows = Database.query(
      'SELECT Id FROM ' +
        checklistObject +
        ' WHERE ContentVersionId__c = :contentVersionId WITH SECURITY_ENFORCED'
    );
    if (rows.isEmpty()) {
      return;
    }
    for (SObject row : rows) {
      row.put('ContentVersionId__c', null);
    }
    update rows;
  }

  private static Boolean objectExists(String apiName) {
    return Schema.getGlobalDescribe().containsKey(apiName);
  }

  private static Boolean fieldExists(String objectApiName, String fieldName) {
    return objectExists(objectApiName) &&
      Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap().containsKey(fieldName);
  }

  private static SObject newSObject(String apiName) {
    return Schema.getGlobalDescribe().get(apiName).newSObject();
  }

  private static List<String> filterExistingFields(String objectApiName, List<String> fieldNames) {
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApiName)
      .getDescribe()
      .fields.getMap();
    List<String> existing = new List<String>();
    for (String fieldName : fieldNames) {
      if (fieldMap.containsKey(fieldName)) {
        existing.add(fieldName);
      }
    }
    return existing;
  }

  private static void putIfFieldExists(SObject record, String fieldName, Object value) {
    if (record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) {
      record.put(fieldName, value);
    }
  }

  private static String normalizeApplicantType(String applicantType) {
    if (String.isBlank(applicantType)) {
      return '';
    }
    String normalized = applicantType.trim();
    if (normalized.equalsIgnoreCase('CoBorrower') || normalized.equalsIgnoreCase('Co Borrower')) {
      return APPLICANT_COBORROWER;
    }
    return normalized;
  }

  private static String resolveAgreementStageCompletedValue(String currentViewId) {
    if (AGREEMENT_OPS_VIEW_ID.equalsIgnoreCase(String.valueOf(currentViewId).trim())) {
      return AGREEMENT_OPS_STAGE;
    }
    return AGREEMENT_PSS_STAGE;
  }

  private static String resolveLoanAgreementIdForLineItem(String applicationId, Id lineItemId) {
    if (String.isBlank(applicationId) || lineItemId == null || !objectExists(AGREEMENT_OBJECT)) {
      return null;
    }
    List<String> fields = filterExistingFields(
      AGREEMENT_OBJECT,
      new List<String>{ 'Id', 'Application__c', 'Application_Line_Items__c' }
    );
    if (!fields.contains('Id') || !fields.contains('Application_Line_Items__c')) {
      return null;
    }
    String soql =
      'SELECT Id FROM ' +
      AGREEMENT_OBJECT +
      ' WHERE Application__c = :applicationId AND Application_Line_Items__c = :lineItemId WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT 1';
    List<SObject> rows = Database.query(soql);
    return rows.isEmpty() ? null : (String) rows[0].get('Id');
  }

  private static Id parseId(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return (Id) value;
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
}