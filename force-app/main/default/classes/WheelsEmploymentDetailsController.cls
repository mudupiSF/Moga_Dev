/**
 * @description Apex controller for Wheels Employment Details LWC.
 * Primary employment = Applicant_Employment__c with Employment_Category__c = Primary.
 * Previous employment = Applicant_Employment__c with Employment_Category__c = Previous.
 */
public with sharing class WheelsEmploymentDetailsController {
    private static final String APPLICANT_TYPE_REFERENCE = 'Reference';
    private static final String INCOME_CATEGORY_SALARIED = 'Salaried';
    private static final String INCOME_CATEGORY_SELF_EMP_PROFESSIONAL = 'Self Employed Professional';
    private static final String INCOME_CATEGORY_SELF_EMP_NON_PROFESSIONAL = 'Self Employed Non Professional';

    private static final String TAB_SALARIED = 'Salaried';
    private static final String TAB_SELF_EMP_PROFESSIONAL = 'Self-Employed Professional';
    private static final String TAB_SELF_EMP_NON_PROFESSIONAL = 'Self-Employed Non-Professional';
    private static final String EMPLOYMENT_STEP_NAME = 'Occupation Details';
    private static final String EMPLOYMENT_CATEGORY_PRIMARY = 'Primary';
    private static final String EMPLOYMENT_CATEGORY_PREVIOUS = 'Previous';

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class EmploymentRecordData {
        @AuraEnabled public Id employmentId;
        @AuraEnabled public String employerName;
        @AuraEnabled public String jobTitle;
        @AuraEnabled public String employmentType;
        @AuraEnabled public String industrySector;
        @AuraEnabled public String employmentStartDate;
        @AuraEnabled public String employmentEndDate;
        @AuraEnabled public String monthlyGrossSalary;
        @AuraEnabled public String workAddress;
        @AuraEnabled public String workEmail;
        @AuraEnabled public String hrPayrollEmail;
        @AuraEnabled public String hrPayrollPhoneNumber;
        @AuraEnabled public String employmentCategory;
        @AuraEnabled public Boolean emailVerified;
        @AuraEnabled public String professionType;
        @AuraEnabled public String practiceFirmName;
        @AuraEnabled public String medicalCouncilRegistrationNumber;
        @AuraEnabled public String icaiMembershipNo;
        @AuraEnabled public String professionalBody;
        @AuraEnabled public String barCouncilEnrollmentNo;
        @AuraEnabled public String barCouncil;
        @AuraEnabled public String councilOfArchitectureRegNo;
        @AuraEnabled public String professionalCertificationLicenceNo;
        @AuraEnabled public String registrationLicenceNo;
        @AuraEnabled public String dateOfRegistration;
        @AuraEnabled public String yearsInPractice;
        @AuraEnabled public String numberOfEmployees;
        @AuraEnabled public String annualProfessionalIncome;
        @AuraEnabled public String panNumber;
        @AuraEnabled public String gstNumber;
        @AuraEnabled public String businessFirmName;
        @AuraEnabled public String natureOfBusiness;
        @AuraEnabled public String businessConstitution;
        @AuraEnabled public String dateOfCommencement;
        @AuraEnabled public String businessVintage;
        @AuraEnabled public String annualTurnover;
        @AuraEnabled public String annualNetIncome;
        @AuraEnabled public String udyamNumber;
        @AuraEnabled public String businessShopAddress;
    }

    public class EmploymentContext {
        @AuraEnabled public Id applicantId;
        @AuraEnabled public Boolean isNonIndividualApplicant;
        @AuraEnabled public String incomeCategory;
        @AuraEnabled public String employmentTab;
        @AuraEnabled public EmploymentRecordData primaryEmployment;
        @AuraEnabled public List<EmploymentRecordData> previousEmployments;
        @AuraEnabled public List<PicklistOption> employmentTypeOptions;
        @AuraEnabled public List<PicklistOption> industrySectorOptions;
        @AuraEnabled public List<PicklistOption> natureOfBusinessOptions;
        @AuraEnabled public List<PicklistOption> businessConstitutionOptions;
    }

    public class SaveResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id employmentId;
        @AuraEnabled public Id primaryEmploymentId;
        @AuraEnabled public EmploymentRecordData primaryEmployment;
        @AuraEnabled public List<EmploymentRecordData> previousEmployments;
    }

    public class EmploymentDocumentData {
        @AuraEnabled public String documentType;
        @AuraEnabled public Id documentChecklistId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String fileName;
    }

    public class LinkEmploymentDocumentResult {
        @AuraEnabled public Id documentChecklistId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String fileName;
    }

    // --- @AuraEnabled: loadEmploymentContext ---
    @AuraEnabled
    public static EmploymentContext loadEmploymentContext(Id recordId, Id applicantId) {
        try {
            Id resolvedApplicantId = resolveApplicantId(recordId, applicantId);
            Applicant__c applicant = queryApplicant(resolvedApplicantId);
            List<Applicant_Employment__c> employments = queryApplicantEmployments(resolvedApplicantId);

            EmploymentContext context = new EmploymentContext();
            context.applicantId = resolvedApplicantId;
            context.isNonIndividualApplicant = isNonIndividualApplicant(applicant);
            context.incomeCategory = applicant.Income_Category__c;
            context.employmentTab = mapIncomeCategoryToTab(applicant.Income_Category__c);
            context.primaryEmployment = mapPrimaryEmployment(employments);
            context.previousEmployments = mapPreviousEmployments(employments);
            context.employmentTypeOptions = getEmploymentPicklistValues('Employment_Type__c');
            context.industrySectorOptions = getEmploymentPicklistValues('Industry_Sector__c');
            context.natureOfBusinessOptions = getEmploymentPicklistValues('Nature_of_Business__c');
            context.businessConstitutionOptions = getEmploymentPicklistValues('Business_Constitution__c');
            return context;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // --- loadEmploymentContext helpers ---
    private static Id resolveApplicantId(Id recordId, Id applicantId) {
        if (applicantId != null) {
            return applicantId;
        }

        if (recordId == null) {
            throw new AuraHandledException('Application or Applicant record Id is required.');
        }

        Schema.SObjectType sobjectType = recordId.getSObjectType();
        if (sobjectType == Applicant__c.SObjectType) {
            return recordId;
        }

        if (sobjectType == Application__c.SObjectType) {
            Id resolvedApplicantId = queryApplicantIdForApplication(recordId);
            if (resolvedApplicantId == null) {
                throw new AuraHandledException('No active applicant found for this Application.');
            }
            return resolvedApplicantId;
        }

        throw new AuraHandledException('Invalid record type.');
    }

    private static Id queryApplicantIdForApplication(Id applicationId) {
        List<Applicant__c> applicants = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND Applicant_Type__c != :APPLICANT_TYPE_REFERENCE
              AND In_Active_Applicant__c = FALSE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return applicants.isEmpty() ? null : applicants[0].Id;
    }

    private static Applicant__c queryApplicant(Id applicantId) {
        List<Applicant__c> applicants = [
            SELECT Id,
                   Application__c,
                   Type__c,
                   Income_Category__c
            FROM Applicant__c
            WHERE Id = :applicantId
              AND In_Active_Applicant__c = FALSE
            LIMIT 1
        ];

        if (applicants.isEmpty()) {
            throw new AuraHandledException('Applicant not found.');
        }

        return applicants[0];
    }

    private static Boolean isNonIndividualApplicant(Applicant__c applicant) {
        if (applicant == null || String.isBlank(applicant.Type__c)) {
            return false;
        }
        String normalizedType = applicant.Type__c.trim().toLowerCase().replace('-', ' ');
        return normalizedType == 'non individual';
    }

    private static final String EMPLOYMENT_FIELDS_SOQL = ''
        + 'Id, Applicant__c, Employer_Name__c, Job_Title_Designation__c, Employment_Type__c,'
        + ' Industry_Sector__c, Employment_Start_Date__c, Employment_End_Date__c,'
        + ' Employment_Category__c, Monthly_Gross_Salary__c, Work_Address__c,'
        + ' Work_Email_Address__c, HR_Payroll_Email__c, HR_Payroll_Phone_Number__c, Email_Verified__c,'
        + ' Profession_Type__c, Practice_Firm_Name__c, Medical_Council_Registration_Number__c,'
        + ' ICAI_Membership_No__c, Professional_Body__c, Bar_Council_Enrollment_No__c, Bar_Council__c,'
        + ' Council_of_Architecture_Reg_No__c, Professional_Certification_Licence_No__c,'
        + ' Registration_Licence_No__c, Date_of_Registration__c, Years_in_Practice__c,'
        + ' Number_of_Employees_Staff__c, Annual_Professional_Income__c, PAN_Number__c,'
        + ' GST_Registration_No__c, Business_Firm_Name__c, Nature_of_Business__c,'
        + ' Business_Constitution__c, Date_of_Commencement__c, Business_Vintage_Years__c,'
        + ' Annual_Turnover__c, Annual_Net_Income__c, Udyam_MSME_Reg_No__c, Business_Shop_Address__c';

    private static List<Applicant_Employment__c> queryApplicantEmployments(Id applicantId) {
        return Database.query(
            'SELECT ' + EMPLOYMENT_FIELDS_SOQL
            + ' FROM Applicant_Employment__c'
            + ' WHERE Applicant__c = :applicantId'
            + ' ORDER BY CreatedDate DESC'
        );
    }

    private static Applicant_Employment__c queryPrimaryEmploymentRecord(Id applicantId) {
        List<Applicant_Employment__c> employments = Database.query(
            'SELECT ' + EMPLOYMENT_FIELDS_SOQL
            + ' FROM Applicant_Employment__c'
            + ' WHERE Applicant__c = :applicantId'
            + ' AND Employment_Category__c = :EMPLOYMENT_CATEGORY_PRIMARY'
            + ' ORDER BY CreatedDate DESC'
            + ' LIMIT 1'
        );
        return employments.isEmpty() ? null : employments[0];
    }

    private static Applicant_Employment__c queryEmploymentRecordById(Id employmentId) {
        List<Applicant_Employment__c> employments = Database.query(
            'SELECT ' + EMPLOYMENT_FIELDS_SOQL
            + ' FROM Applicant_Employment__c'
            + ' WHERE Id = :employmentId'
            + ' LIMIT 1'
        );
        return employments.isEmpty() ? null : employments[0];
    }

    private static EmploymentRecordData mapPrimaryEmployment(List<Applicant_Employment__c> employments) {
        for (Applicant_Employment__c employment : employments) {
            if (isPrimaryEmployment(employment)) {
                return mapEmploymentRecord(employment);
            }
        }
        return new EmploymentRecordData();
    }

    private static List<EmploymentRecordData> mapPreviousEmployments(List<Applicant_Employment__c> employments) {
        List<EmploymentRecordData> previous = new List<EmploymentRecordData>();
        for (Applicant_Employment__c employment : employments) {
            if (isPreviousEmployment(employment)) {
                previous.add(mapEmploymentRecord(employment));
            }
        }
        return previous;
    }

    private static Boolean isPrimaryEmployment(Applicant_Employment__c employment) {
        return employment != null
            && String.isNotBlank(employment.Employment_Category__c)
            && EMPLOYMENT_CATEGORY_PRIMARY.equalsIgnoreCase(employment.Employment_Category__c.trim());
    }

    private static Boolean isPreviousEmployment(Applicant_Employment__c employment) {
        return employment != null
            && String.isNotBlank(employment.Employment_Category__c)
            && EMPLOYMENT_CATEGORY_PREVIOUS.equalsIgnoreCase(employment.Employment_Category__c.trim());
    }

    private static EmploymentRecordData mapEmploymentRecord(Applicant_Employment__c employment) {
        EmploymentRecordData data = new EmploymentRecordData();
        if (employment == null) {
            return data;
        }

        data.employmentId = employment.Id;
        data.employerName = employment.Employer_Name__c;
        data.jobTitle = employment.Job_Title_Designation__c;
        data.employmentType = employment.Employment_Type__c;
        data.industrySector = employment.Industry_Sector__c;
        data.employmentStartDate = employment.Employment_Start_Date__c != null
            ? String.valueOf(employment.Employment_Start_Date__c)
            : null;
        data.employmentEndDate = employment.Employment_End_Date__c != null
            ? String.valueOf(employment.Employment_End_Date__c)
            : null;
        data.monthlyGrossSalary = employment.Monthly_Gross_Salary__c != null
            ? String.valueOf(employment.Monthly_Gross_Salary__c)
            : null;
        data.workAddress = employment.Work_Address__c;
        data.workEmail = employment.Work_Email_Address__c;
        data.hrPayrollEmail = employment.HR_Payroll_Email__c;
        data.hrPayrollPhoneNumber = employment.HR_Payroll_Phone_Number__c;
        data.employmentCategory = employment.Employment_Category__c;
        data.emailVerified = employment.Email_Verified__c == true;
        data.professionType = employment.Profession_Type__c;
        data.practiceFirmName = employment.Practice_Firm_Name__c;
        data.medicalCouncilRegistrationNumber = employment.Medical_Council_Registration_Number__c;
        data.icaiMembershipNo = employment.ICAI_Membership_No__c;
        data.professionalBody = employment.Professional_Body__c;
        data.barCouncilEnrollmentNo = employment.Bar_Council_Enrollment_No__c;
        data.barCouncil = employment.Bar_Council__c;
        data.councilOfArchitectureRegNo = employment.Council_of_Architecture_Reg_No__c;
        data.professionalCertificationLicenceNo = employment.Professional_Certification_Licence_No__c;
        data.registrationLicenceNo = employment.Registration_Licence_No__c;
        data.dateOfRegistration = employment.Date_of_Registration__c != null
            ? String.valueOf(employment.Date_of_Registration__c)
            : null;
        data.yearsInPractice = employment.Years_in_Practice__c != null
            ? String.valueOf(employment.Years_in_Practice__c)
            : null;
        data.numberOfEmployees = employment.Number_of_Employees_Staff__c != null
            ? String.valueOf(employment.Number_of_Employees_Staff__c)
            : null;
        data.annualProfessionalIncome = employment.Annual_Professional_Income__c != null
            ? String.valueOf(employment.Annual_Professional_Income__c)
            : null;
        data.panNumber = employment.PAN_Number__c;
        data.gstNumber = employment.GST_Registration_No__c;
        data.businessFirmName = employment.Business_Firm_Name__c;
        data.natureOfBusiness = employment.Nature_of_Business__c;
        data.businessConstitution = employment.Business_Constitution__c;
        data.dateOfCommencement = employment.Date_of_Commencement__c != null
            ? String.valueOf(employment.Date_of_Commencement__c)
            : null;
        data.businessVintage = employment.Business_Vintage_Years__c != null
            ? String.valueOf(employment.Business_Vintage_Years__c)
            : null;
        data.annualTurnover = employment.Annual_Turnover__c != null
            ? String.valueOf(employment.Annual_Turnover__c)
            : null;
        data.annualNetIncome = employment.Annual_Net_Income__c != null
            ? String.valueOf(employment.Annual_Net_Income__c)
            : null;
        data.udyamNumber = employment.Udyam_MSME_Reg_No__c;
        data.businessShopAddress = employment.Business_Shop_Address__c;
        return data;
    }

    private static String mapIncomeCategoryToTab(String incomeCategory) {
        if (String.isBlank(incomeCategory)) {
            return TAB_SALARIED;
        }

        String normalized = incomeCategory.trim().toLowerCase().replace('-', ' ');

        if (normalized == INCOME_CATEGORY_SALARIED.toLowerCase()) {
            return TAB_SALARIED;
        }
        if (normalized == INCOME_CATEGORY_SELF_EMP_PROFESSIONAL.toLowerCase()) {
            return TAB_SELF_EMP_PROFESSIONAL;
        }
        if (normalized == INCOME_CATEGORY_SELF_EMP_NON_PROFESSIONAL.toLowerCase()) {
            return TAB_SELF_EMP_NON_PROFESSIONAL;
        }

        return TAB_SALARIED;
    }

    private static List<PicklistOption> getEmploymentPicklistValues(String fieldApiName) {
        List<PicklistOption> options = new List<PicklistOption>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Applicant_Employment__c.fields.getMap();
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

    // --- @AuraEnabled: saveEmploymentDetails ---
    @AuraEnabled
    public static SaveResult saveEmploymentDetails(Id applicantId, String employmentJson) {
        SaveResult result = new SaveResult();
        try {
            if (applicantId == null) {
                throw new AuraHandledException('Applicant Id is required.');
            }

            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(employmentJson);
            Map<String, Object> primaryMap = payload.containsKey('primary')
                ? (Map<String, Object>) payload.get('primary')
                : payload;

            Applicant_Employment__c primaryEmployment = buildPrimaryEmploymentRecord(applicantId, primaryMap);
            upsert primaryEmployment;

            List<Applicant_Employment__c> previousToUpsert = buildPreviousEmploymentRecords(
                applicantId,
                payload.containsKey('previousEmployers')
                    ? (List<Object>) payload.get('previousEmployers')
                    : new List<Object>()
            );
            if (!previousToUpsert.isEmpty()) {
                upsert previousToUpsert;
            }

            deletePreviousEmployments(
                applicantId,
                payload.containsKey('deletedPreviousEmploymentIds')
                    ? (List<Object>) payload.get('deletedPreviousEmploymentIds')
                    : new List<Object>()
            );

            List<Applicant_Employment__c> refreshedEmployments = queryApplicantEmployments(applicantId);
            result.success = true;
            result.primaryEmploymentId = primaryEmployment.Id;
            result.employmentId = primaryEmployment.Id;
            result.primaryEmployment = mapPrimaryEmployment(refreshedEmployments);
            result.previousEmployments = mapPreviousEmployments(refreshedEmployments);
            result.message = 'Employment details saved successfully.';
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error saving employment details: ' + e.getMessage();
            return result;
        }
    }

    // --- saveEmploymentDetails helpers ---
    private static Applicant_Employment__c buildPrimaryEmploymentRecord(
        Id applicantId,
        Map<String, Object> dataMap
    ) {
        Id employmentId = getIdValue(dataMap, 'employmentId');
        Applicant_Employment__c existingEmployment = resolvePrimaryEmploymentRecord(applicantId, employmentId);

        Applicant_Employment__c employment = existingEmployment != null
            ? new Applicant_Employment__c(Id = existingEmployment.Id)
            : new Applicant_Employment__c(Applicant__c = applicantId);

        if (dataMap.containsKey('employerName')) {
            employment.Employer_Name__c = getStringValue(dataMap, 'employerName');
        }
        if (dataMap.containsKey('jobTitle')) {
            employment.Job_Title_Designation__c = getStringValue(dataMap, 'jobTitle');
        }
        if (dataMap.containsKey('employmentType')) {
            employment.Employment_Type__c = getStringValue(dataMap, 'employmentType');
        }
        if (dataMap.containsKey('industrySector')) {
            employment.Industry_Sector__c = getStringValue(dataMap, 'industrySector');
        }
        if (dataMap.containsKey('employmentStartDate')) {
            employment.Employment_Start_Date__c = getDateValue(dataMap, 'employmentStartDate');
            validateStartDate(employment.Employment_Start_Date__c);
        }
        employment.Employment_Category__c = resolveEmploymentCategory(
            dataMap,
            EMPLOYMENT_CATEGORY_PRIMARY
        );
        employment.Employment_End_Date__c = null;
        if (dataMap.containsKey('monthlyGrossSalary')) {
            employment.Monthly_Gross_Salary__c = getDecimalValue(dataMap, 'monthlyGrossSalary');
        }
        if (dataMap.containsKey('workAddress')) {
            employment.Work_Address__c = getStringValue(dataMap, 'workAddress');
        }
        if (dataMap.containsKey('hrPayrollEmail')) {
            employment.HR_Payroll_Email__c = getStringValue(dataMap, 'hrPayrollEmail');
        }
        if (dataMap.containsKey('hrPayrollPhoneNumber')) {
            employment.HR_Payroll_Phone_Number__c = getStringValue(dataMap, 'hrPayrollPhoneNumber');
        }

        assignPrimaryProfessionalFields(employment, dataMap);
        assignPrimaryNonProfessionalFields(employment, dataMap);

        if (dataMap.containsKey('workEmail')) {
            String newWorkEmail = getStringValue(dataMap, 'workEmail');
            Boolean emailVerified = dataMap.containsKey('emailVerified') && dataMap.get('emailVerified') == true;
            employment.Work_Email_Address__c = newWorkEmail;

            String existingWorkEmail = existingEmployment != null
                ? existingEmployment.Work_Email_Address__c
                : null;
            if (existingEmployment != null && newWorkEmail != existingWorkEmail) {
                employment.Email_Verified__c = false;
            } else {
                employment.Email_Verified__c = emailVerified;
            }
        }

        return employment;
    }

    private static void assignPrimaryProfessionalFields(
        Applicant_Employment__c employment,
        Map<String, Object> dataMap
    ) {
        if (dataMap == null || employment == null) {
            return;
        }
        if (dataMap.containsKey('professionType')) {
            employment.Profession_Type__c = getStringValue(dataMap, 'professionType');
        }
        if (dataMap.containsKey('practiceFirmName')) {
            employment.Practice_Firm_Name__c = getStringValue(dataMap, 'practiceFirmName');
        }
        if (dataMap.containsKey('medicalCouncilRegistrationNumber')) {
            employment.Medical_Council_Registration_Number__c = getStringValue(
                dataMap,
                'medicalCouncilRegistrationNumber'
            );
        }
        if (dataMap.containsKey('icaiMembershipNo')) {
            employment.ICAI_Membership_No__c = getStringValue(dataMap, 'icaiMembershipNo');
        }
        if (dataMap.containsKey('professionalBody')) {
            employment.Professional_Body__c = getStringValue(dataMap, 'professionalBody');
        }
        if (dataMap.containsKey('barCouncilEnrollmentNo')) {
            employment.Bar_Council_Enrollment_No__c = getStringValue(dataMap, 'barCouncilEnrollmentNo');
        }
        if (dataMap.containsKey('barCouncil')) {
            employment.Bar_Council__c = getStringValue(dataMap, 'barCouncil');
        }
        if (dataMap.containsKey('councilOfArchitectureRegNo')) {
            employment.Council_of_Architecture_Reg_No__c = getStringValue(
                dataMap,
                'councilOfArchitectureRegNo'
            );
        }
        if (dataMap.containsKey('professionalCertificationLicenceNo')) {
            employment.Professional_Certification_Licence_No__c = getStringValue(
                dataMap,
                'professionalCertificationLicenceNo'
            );
        }
        if (dataMap.containsKey('registrationLicenceNo')) {
            employment.Registration_Licence_No__c = getStringValue(dataMap, 'registrationLicenceNo');
        }
        if (dataMap.containsKey('dateOfRegistration')) {
            employment.Date_of_Registration__c = getDateValue(dataMap, 'dateOfRegistration');
        }
        if (dataMap.containsKey('yearsInPractice')) {
            employment.Years_in_Practice__c = getDecimalValue(dataMap, 'yearsInPractice');
        }
        if (dataMap.containsKey('numberOfEmployees')) {
            employment.Number_of_Employees_Staff__c = getDecimalValue(dataMap, 'numberOfEmployees');
        }
        if (dataMap.containsKey('annualProfessionalIncome')) {
            employment.Annual_Professional_Income__c = getDecimalValue(
                dataMap,
                'annualProfessionalIncome'
            );
        }
        if (dataMap.containsKey('panNumber')) {
            employment.PAN_Number__c = getStringValue(dataMap, 'panNumber');
        }
        if (dataMap.containsKey('gstNumber')) {
            employment.GST_Registration_No__c = getStringValue(dataMap, 'gstNumber');
        }
    }

    private static void assignPrimaryNonProfessionalFields(
        Applicant_Employment__c employment,
        Map<String, Object> dataMap
    ) {
        if (dataMap == null || employment == null) {
            return;
        }
        if (dataMap.containsKey('businessFirmName')) {
            employment.Business_Firm_Name__c = getStringValue(dataMap, 'businessFirmName');
        }
        if (dataMap.containsKey('natureOfBusiness')) {
            employment.Nature_of_Business__c = getStringValue(dataMap, 'natureOfBusiness');
        }
        if (dataMap.containsKey('businessConstitution')) {
            employment.Business_Constitution__c = getStringValue(dataMap, 'businessConstitution');
        }
        if (dataMap.containsKey('dateOfCommencement')) {
            employment.Date_of_Commencement__c = getDateValue(dataMap, 'dateOfCommencement');
            validateStartDate(employment.Date_of_Commencement__c);
        }
        if (dataMap.containsKey('businessVintage')) {
            employment.Business_Vintage_Years__c = getDecimalValue(dataMap, 'businessVintage');
        }
        if (dataMap.containsKey('numberOfEmployees')) {
            employment.Number_of_Employees_Staff__c = getDecimalValue(dataMap, 'numberOfEmployees');
        }
        if (dataMap.containsKey('annualTurnover')) {
            employment.Annual_Turnover__c = getDecimalValue(dataMap, 'annualTurnover');
        }
        if (dataMap.containsKey('annualNetIncome')) {
            employment.Annual_Net_Income__c = getDecimalValue(dataMap, 'annualNetIncome');
        }
        if (dataMap.containsKey('panNumber')) {
            employment.PAN_Number__c = getStringValue(dataMap, 'panNumber');
        }
        if (dataMap.containsKey('gstNumber')) {
            employment.GST_Registration_No__c = getStringValue(dataMap, 'gstNumber');
        }
        if (dataMap.containsKey('udyamNumber')) {
            employment.Udyam_MSME_Reg_No__c = getStringValue(dataMap, 'udyamNumber');
        }
        if (dataMap.containsKey('businessShopAddress')) {
            employment.Business_Shop_Address__c = getStringValue(dataMap, 'businessShopAddress');
        }
    }

    private static List<Applicant_Employment__c> buildPreviousEmploymentRecords(
        Id applicantId,
        List<Object> previousEmployers
    ) {
        List<Applicant_Employment__c> records = new List<Applicant_Employment__c>();
        if (previousEmployers == null) {
            return records;
        }

        for (Object item : previousEmployers) {
            Map<String, Object> dataMap = (Map<String, Object>) item;
            if (!hasPreviousEmployerData(dataMap)) {
                continue;
            }

            Id employmentId = getIdValue(dataMap, 'employmentId');
            Applicant_Employment__c employment = employmentId != null
                ? new Applicant_Employment__c(Id = employmentId, Applicant__c = applicantId)
                : new Applicant_Employment__c(Applicant__c = applicantId);

            employment.Employer_Name__c = getStringValue(dataMap, 'employerName');
            employment.Job_Title_Designation__c = getStringValue(dataMap, 'jobTitle');
            employment.Employment_Type__c = getStringValue(dataMap, 'employmentType');
            employment.Industry_Sector__c = getStringValue(dataMap, 'industrySector');
            employment.Employment_Start_Date__c = getDateValue(dataMap, 'employmentStartDate');
            validateStartDate(employment.Employment_Start_Date__c);
            employment.Employment_Category__c = resolveEmploymentCategory(
                dataMap,
                EMPLOYMENT_CATEGORY_PREVIOUS
            );
            employment.Employment_End_Date__c = getDateValue(dataMap, 'employmentEndDate');

            if (employment.Employment_End_Date__c == null) {
                throw new AuraHandledException('Employment End Date is required for previous employment records.');
            }

            employment.Monthly_Gross_Salary__c = null;
            employment.Work_Address__c = null;
            employment.Work_Email_Address__c = getStringValue(dataMap, 'workEmail');
            employment.HR_Payroll_Phone_Number__c = getStringValue(dataMap, 'hrPayrollPhoneNumber');
            employment.Email_Verified__c = false;
            records.add(employment);
        }

        return records;
    }

    private static void deletePreviousEmployments(Id applicantId, List<Object> deletedIds) {
        if (deletedIds == null || deletedIds.isEmpty()) {
            return;
        }

        Set<Id> idsToDelete = new Set<Id>();
        for (Object deletedId : deletedIds) {
            if (deletedId != null && String.isNotBlank(String.valueOf(deletedId))) {
                idsToDelete.add((Id) String.valueOf(deletedId));
            }
        }
        if (idsToDelete.isEmpty()) {
            return;
        }

        List<Applicant_Employment__c> rows = [
            SELECT Id
            FROM Applicant_Employment__c
            WHERE Id IN :idsToDelete
              AND Applicant__c = :applicantId
              AND Employment_Category__c = :EMPLOYMENT_CATEGORY_PREVIOUS
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }
    }

    private static Applicant_Employment__c resolvePrimaryEmploymentRecord(Id applicantId, Id employmentId) {
        if (employmentId != null) {
            Applicant_Employment__c byId = queryEmploymentRecordById(employmentId);
            if (byId != null && byId.Applicant__c == applicantId && isPrimaryEmployment(byId)) {
                return byId;
            }
        }
        return queryPrimaryEmploymentRecord(applicantId);
    }

    private static String resolveEmploymentCategory(
        Map<String, Object> dataMap,
        String defaultCategory
    ) {
        String category = getStringValue(dataMap, 'employmentCategory');
        if (String.isBlank(category)) {
            return defaultCategory;
        }
        if (EMPLOYMENT_CATEGORY_PRIMARY.equalsIgnoreCase(category.trim())
                || EMPLOYMENT_CATEGORY_PREVIOUS.equalsIgnoreCase(category.trim())) {
            return category.trim();
        }
        return defaultCategory;
    }

    private static Boolean hasPreviousEmployerData(Map<String, Object> dataMap) {
        return String.isNotBlank(getStringValue(dataMap, 'employerName'))
            || String.isNotBlank(getStringValue(dataMap, 'jobTitle'))
            || String.isNotBlank(getStringValue(dataMap, 'employmentType'))
            || String.isNotBlank(getStringValue(dataMap, 'industrySector'))
            || getDateValue(dataMap, 'employmentStartDate') != null
            || getDateValue(dataMap, 'employmentEndDate') != null
            || String.isNotBlank(getStringValue(dataMap, 'workEmail'))
            || String.isNotBlank(getStringValue(dataMap, 'hrPayrollPhoneNumber'));
    }

    private static void validateStartDate(Date startDate) {
        if (startDate != null && startDate > Date.today()) {
            throw new AuraHandledException('Employment Start Date cannot be ahead of today.');
        }
    }

    // --- @AuraEnabled: stage and email verification ---
    @AuraEnabled
    public static SaveResult markEmploymentStepComplete(Id applicantId) {
        SaveResult result = new SaveResult();
        try {
            if (applicantId == null) {
                throw new AuraHandledException('Applicant Id is required.');
            }

            List<Applicant__c> applicants = [
                SELECT Id, Current_Loan_Stage_Complete__c, Loan_Stage__c
                FROM Applicant__c
                WHERE Id = :applicantId
                  AND In_Active_Applicant__c = FALSE
                LIMIT 1
            ];
            if (applicants.isEmpty()) {
                throw new AuraHandledException('Applicant not found.');
            }

            Applicant__c applicant = applicants[0];
            if (String.isNotBlank(applicant.Current_Loan_Stage_Complete__c)
                    && EMPLOYMENT_STEP_NAME.equalsIgnoreCase(applicant.Current_Loan_Stage_Complete__c.trim())) {
                result.success = true;
                result.message = 'Employment step already complete.';
                return result;
            }

            applicant.Current_Loan_Stage_Complete__c = EMPLOYMENT_STEP_NAME;
            if (String.isBlank(applicant.Loan_Stage__c)) {
                applicant.Loan_Stage__c = EMPLOYMENT_STEP_NAME;
            }
            update applicant;

            result.success = true;
            result.message = 'Employment step marked complete.';
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error marking employment step complete: ' + e.getMessage();
            return result;
        }
    }

    @AuraEnabled
    public static SaveResult markEmploymentWorkEmailVerified(
        Id applicantId,
        Id employmentId,
        String workEmail
    ) {
        SaveResult result = new SaveResult();
        try {
            if (applicantId == null) {
                throw new AuraHandledException('Applicant Id is required.');
            }
            if (String.isBlank(workEmail)) {
                throw new AuraHandledException('Work email is required.');
            }

            Applicant_Employment__c existingEmployment = resolvePrimaryEmploymentRecord(applicantId, employmentId);
            Applicant_Employment__c employment = existingEmployment != null
                ? new Applicant_Employment__c(Id = existingEmployment.Id)
                : new Applicant_Employment__c(Applicant__c = applicantId);

            employment.Work_Email_Address__c = workEmail.trim();
            employment.Email_Verified__c = true;
            employment.Employment_Category__c = EMPLOYMENT_CATEGORY_PRIMARY;
            employment.Employment_End_Date__c = null;
            upsert employment;

            result.success = true;
            result.employmentId = employment.Id;
            result.primaryEmploymentId = employment.Id;
            result.message = 'Work email verified successfully.';
            return result;
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error verifying work email: ' + e.getMessage();
            return result;
        }
    }

    // --- @AuraEnabled: linkEmploymentDocument ---
    /**
     * @description Links an uploaded ContentVersion to the employment Document_CheckList__c row.
     */
    @AuraEnabled
    public static LinkEmploymentDocumentResult linkEmploymentDocument(
        Id docChecklistId,
        String documentType,
        String contentVersionId,
        Id applicationId,
        Id applicantId
    ) {
        if (String.isBlank(contentVersionId)) {
            throw new AuraHandledException('Uploaded file reference is missing.');
        }
        if (String.isBlank(documentType)) {
            throw new AuraHandledException('Document type is required.');
        }

        Id resolvedChecklistId = docChecklistId;
        if (resolvedChecklistId == null) {
            resolvedChecklistId = resolveEmploymentDocumentChecklistId(
                applicationId,
                applicantId,
                documentType
            );
        }
        if (resolvedChecklistId == null) {
            throw new AuraHandledException('Document checklist could not be resolved.');
        }

        Document_CheckList__c checklistRow = new Document_CheckList__c(
            Id = resolvedChecklistId,
            Document_Type__c = documentType,
            ContentVersionId__c = contentVersionId,
            Is_Active__c = true
        );
        update checklistRow;

        LinkEmploymentDocumentResult result = new LinkEmploymentDocumentResult();
        result.documentChecklistId = resolvedChecklistId;
        result.contentVersionId = contentVersionId;

        List<ContentVersion> versions = [
            SELECT Title, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!versions.isEmpty()) {
            result.fileName = versions[0].Title;
            result.contentDocumentId = versions[0].ContentDocumentId;
        }
        return result;
    }

    // --- Document helpers ---
    private static Id resolveEmploymentDocumentChecklistId(
        Id applicationId,
        Id applicantId,
        String documentType
    ) {
        if (applicationId == null || applicantId == null || String.isBlank(documentType)) {
            return null;
        }

        List<Document_CheckList__c> existingRows = [
            SELECT Id
            FROM Document_CheckList__c
            WHERE Application__c = :applicationId
              AND Applicant__c = :applicantId
              AND Document_Type__c = :documentType
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!existingRows.isEmpty()) {
            return existingRows[0].Id;
        }

        Document_CheckList__c newRow = new Document_CheckList__c(
            Name = documentType + ' - Document',
            Document_Type__c = documentType,
            Application__c = applicationId,
            Applicant__c = applicantId,
            Is_Active__c = true
        );
        insert newRow;
        return newRow.Id;
    }

    // --- @AuraEnabled: loadEmploymentDocuments ---
    /**
     * @description Loads uploaded employment document metadata for the given document types.
     */
    @AuraEnabled
    public static List<EmploymentDocumentData> loadEmploymentDocuments(
        Id applicationId,
        Id applicantId,
        List<String> documentTypes
    ) {
        List<EmploymentDocumentData> results = new List<EmploymentDocumentData>();
        if (
            applicationId == null
            || applicantId == null
            || documentTypes == null
            || documentTypes.isEmpty()
        ) {
            return results;
        }

        Set<String> requestedTypes = new Set<String>();
        for (String documentType : documentTypes) {
            if (String.isNotBlank(documentType)) {
                requestedTypes.add(documentType.trim());
            }
        }
        if (requestedTypes.isEmpty()) {
            return results;
        }

        Map<String, Document_CheckList__c> latestByType = new Map<String, Document_CheckList__c>();
        for (Document_CheckList__c row : [
            SELECT Id, Document_Type__c, ContentVersionId__c
            FROM Document_CheckList__c
            WHERE Application__c = :applicationId
              AND Applicant__c = :applicantId
              AND Document_Type__c IN :requestedTypes
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ]) {
            if (!latestByType.containsKey(row.Document_Type__c)) {
                latestByType.put(row.Document_Type__c, row);
            }
        }

        Set<Id> versionIds = new Set<Id>();
        for (Document_CheckList__c row : latestByType.values()) {
            if (String.isNotBlank(row.ContentVersionId__c)) {
                versionIds.add(row.ContentVersionId__c);
            }
        }

        Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>();
        if (!versionIds.isEmpty()) {
            versionsById = new Map<Id, ContentVersion>([
                SELECT Id, Title, ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :versionIds
                WITH SECURITY_ENFORCED
            ]);
        }

        for (String documentType : requestedTypes) {
            EmploymentDocumentData data = new EmploymentDocumentData();
            data.documentType = documentType;
            Document_CheckList__c row = latestByType.get(documentType);
            if (row == null) {
                results.add(data);
                continue;
            }

            data.documentChecklistId = row.Id;
            data.contentVersionId = row.ContentVersionId__c;
            if (
                String.isNotBlank(row.ContentVersionId__c)
                && versionsById.containsKey(row.ContentVersionId__c)
            ) {
                ContentVersion version = versionsById.get(row.ContentVersionId__c);
                data.contentDocumentId = version.ContentDocumentId;
                data.fileName = version.Title;
            }
            results.add(data);
        }
        return results;
    }

    // --- Shared map/payload utilities ---
    private static Id getIdValue(Map<String, Object> dataMap, String key) {
        if (dataMap == null || !dataMap.containsKey(key) || dataMap.get(key) == null) {
            return null;
        }
        String value = String.valueOf(dataMap.get(key)).trim();
        return String.isBlank(value) ? null : (Id) value;
    }

    private static String getStringValue(Map<String, Object> dataMap, String key) {
        if (dataMap == null || !dataMap.containsKey(key) || dataMap.get(key) == null) {
            return null;
        }
        String value = String.valueOf(dataMap.get(key)).trim();
        return String.isBlank(value) ? null : value;
    }

    private static Date getDateValue(Map<String, Object> dataMap, String key) {
        String value = getStringValue(dataMap, key);
        if (String.isBlank(value)) {
            return null;
        }
        return Date.valueOf(value);
    }

    private static Decimal getDecimalValue(Map<String, Object> dataMap, String key) {
        if (dataMap == null || !dataMap.containsKey(key) || dataMap.get(key) == null) {
            return null;
        }
        String value = String.valueOf(dataMap.get(key)).trim();
        if (String.isBlank(value)) {
            return null;
        }
        return Decimal.valueOf(value.replace(',', ''));
    }

}