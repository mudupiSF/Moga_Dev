/**
 * @description Apex controller for financialPerformanceGrid LWC (GST GSTR 3B monthly capture).
 */
public with sharing class FinancialPerformanceGridController {

  private static final String GST_RECORD_TYPE_NAME = 'GSTR 3B';
  private static final List<String> ORDERED_MONTHS = new List<String>{
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  };
  private static final Set<String> VALID_MONTHS = new Set<String>(ORDERED_MONTHS);

  @AuraEnabled
  public static GstPerformanceDataWrapper getGstPerformanceData(Id applicantIncomeId) {
    GstPerformanceDataWrapper response = new GstPerformanceDataWrapper();
    response.records = new List<FinancialYearGstWrapper>();

    if (applicantIncomeId == null) {
      return response;
    }

    List<Financial_Performance__c> performanceRecords = [
      SELECT
        Id,
        Name,
        (
          SELECT Id, Month__c, Amount__c, RecordType.DeveloperName, RecordType.Name
          FROM GST__r
          WHERE RecordType.DeveloperName = 'GSTR_3B'
          ORDER BY CreatedDate ASC
        )
      FROM Financial_Performance__c
      WHERE Applicant_Income__c = :applicantIncomeId
      WITH SECURITY_ENFORCED
      ORDER BY Name ASC
    ];

    for (Financial_Performance__c performanceRecord : performanceRecords) {
      FinancialYearGstWrapper yearWrapper = new FinancialYearGstWrapper();
      yearWrapper.financialYearName = performanceRecord.Name;
      yearWrapper.financialPerformanceId = performanceRecord.Id;
      yearWrapper.months = new List<GstMonthWrapper>();

      Map<String, GST__c> gstByMonth = new Map<String, GST__c>();
      for (GST__c gstRecord : performanceRecord.GST__r) {
        if (String.isNotBlank(gstRecord.Month__c)) {
          gstByMonth.put(gstRecord.Month__c, gstRecord);
        }
      }

      for (String monthName : ORDERED_MONTHS) {
        GstMonthWrapper monthWrapper = new GstMonthWrapper();
        monthWrapper.month = monthName;
        if (gstByMonth.containsKey(monthName)) {
          GST__c gstRecord = gstByMonth.get(monthName);
          monthWrapper.recordId = gstRecord.Id;
          monthWrapper.amount = gstRecord.Amount__c;
        }
        yearWrapper.months.add(monthWrapper);
      }

      response.records.add(yearWrapper);
    }

    return response;
  }

  @AuraEnabled
  public static SaveGstPerformanceResult saveGstPerformanceData(
    Id applicantId,
    Id applicantIncomeId,
    String financialYearName,
    String monthsJson
  ) {
    if (applicantIncomeId == null) {
      Applicant_Income__c applicantIncomeRecord = IncomeSourceCaptureController.resolveIncomeSourceRecord(applicantId, 'GST');
      applicantIncomeId = applicantIncomeRecord.Id;
    }
    if (String.isBlank(financialYearName)) {
      throw new AuraHandledException('Financial year is required.');
    }
    if (String.isBlank(monthsJson)) {
      throw new AuraHandledException('GST month details are required.');
    }

    try {
      List<Applicant_Income__c> incomeRecords = [
        SELECT Id, Applicant__c
        FROM Applicant_Income__c
        WHERE Id = :applicantIncomeId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (incomeRecords.isEmpty()) {
        throw new AuraHandledException('Applicant Income record not found.');
      }

      Applicant_Income__c incomeRecord = incomeRecords[0];
      List<GstMonthInput> monthInputs = (List<GstMonthInput>) JSON.deserialize(
        monthsJson,
        List<GstMonthInput>.class
      );
      if (monthInputs == null || monthInputs.isEmpty()) {
        throw new AuraHandledException('Please enter GST amounts for at least one month.');
      }

      Financial_Performance__c performanceRecord = resolveFinancialPerformanceRecord(
        applicantIncomeId,
        incomeRecord.Applicant__c,
        financialYearName.trim()
      );

      upsert performanceRecord;
      Id financialPerformanceId = performanceRecord.Id;
      Id gstRecordTypeId = resolveGstRecordTypeId();

      List<GST__c> gstRecords = new List<GST__c>();
      for (GstMonthInput monthInput : monthInputs) {
        if (monthInput == null || String.isBlank(monthInput.month)) {
          continue;
        }
        if (!VALID_MONTHS.contains(monthInput.month)) {
          continue;
        }

        GST__c gstRecord = new GST__c();
        if (isSalesforceId(monthInput.recordId)) {
          gstRecord.Id = monthInput.recordId;
        } else {
          gstRecord.RecordTypeId = gstRecordTypeId;
        }
        gstRecord.Financial_Performance__c = financialPerformanceId;
        gstRecord.Month__c = monthInput.month;
        gstRecord.Amount__c = monthInput.amount;
        gstRecords.add(gstRecord);
      }

      if (gstRecords.isEmpty()) {
        throw new AuraHandledException('No valid GST month rows to save.');
      }

      SObjectAccessDecision gstDecision = Security.stripInaccessible(
        AccessType.UPSERTABLE,
        gstRecords
      );
      List<GST__c> upsertableGst = gstDecision.getRecords();
      if (upsertableGst.isEmpty()) {
        throw new AuraHandledException('Insufficient access to save GST records.');
      }

      for (GST__c gstRecord : upsertableGst) {
        if (gstRecord.Id == null) {
          gstRecord.RecordTypeId = gstRecordTypeId;
        }
        gstRecord.Financial_Performance__c = financialPerformanceId;
      }

      upsert upsertableGst;

      SaveGstPerformanceResult result = new SaveGstPerformanceResult();
      result.applicantIncomeId = applicantIncomeId;
      result.financialPerformanceId = financialPerformanceId;
      result.months = new List<GstMonthWrapper>();
      for (GST__c gstRecord : upsertableGst) {
        GstMonthWrapper monthWrapper = new GstMonthWrapper();
        monthWrapper.recordId = gstRecord.Id;
        monthWrapper.month = gstRecord.Month__c;
        monthWrapper.amount = gstRecord.Amount__c;
        result.months.add(monthWrapper);
      }
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  private static Financial_Performance__c resolveFinancialPerformanceRecord(
    Id applicantIncomeId,
    Id applicantId,
    String financialYearName
  ) {
    List<Financial_Performance__c> existingRecords = [
      SELECT Id, Name, Applicant_Income__c, Applicant__c
      FROM Financial_Performance__c
      WHERE Applicant_Income__c = :applicantIncomeId AND Name = :financialYearName AND Applicant__c = :applicantId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    Financial_Performance__c performanceRecord = new Financial_Performance__c();
    if (!existingRecords.isEmpty()) {
      performanceRecord = existingRecords[0];
    }
    else{
      performanceRecord.Name = financialYearName;
      performanceRecord.Applicant_Income__c = applicantIncomeId;
      performanceRecord.Applicant__c = applicantId;
    }
    return performanceRecord;
  }

  private static Id resolveGstRecordTypeId() {
    Map<String, Schema.RecordTypeInfo> recordTypesByName = Schema.SObjectType.GST__c.getRecordTypeInfosByName();
    if (recordTypesByName.containsKey(GST_RECORD_TYPE_NAME)) {
      return recordTypesByName.get(GST_RECORD_TYPE_NAME).getRecordTypeId();
    }

    Map<String, Schema.RecordTypeInfo> recordTypesByDeveloper = Schema.SObjectType.GST__c.getRecordTypeInfosByDeveloperName();
    if (recordTypesByDeveloper.containsKey('GSTR_3B')) {
      return recordTypesByDeveloper.get('GSTR_3B').getRecordTypeId();
    }

    throw new AuraHandledException('GST record type not found: ' + GST_RECORD_TYPE_NAME);
  }

  private static Boolean isSalesforceId(Object value) {
    if (value == null) {
      return false;
    }
    try {
      Id.valueOf(String.valueOf(value));
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  public class GstPerformanceDataWrapper {
    @AuraEnabled
    public List<FinancialYearGstWrapper> records;
  }

  public class FinancialYearGstWrapper {
    @AuraEnabled
    public String financialYearName;
    @AuraEnabled
    public Id financialPerformanceId;
    @AuraEnabled
    public List<GstMonthWrapper> months;
  }

  public class GstMonthWrapper {
    @AuraEnabled
    public String month;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Id recordId;
  }

  public class SaveGstPerformanceResult {
    @AuraEnabled
    public Id applicantIncomeId;
    @AuraEnabled
    public Id financialPerformanceId;
    @AuraEnabled
    public List<GstMonthWrapper> months;
  }

  public class GstMonthInput {
    public String month;
    public Decimal amount;
    public String recordId;
  }
}