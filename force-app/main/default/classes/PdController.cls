/**
 * Personal Discussion investigation screen orchestration.
 * One Investigations__c per application; one Verification__c per active applicant.
 * Applicant-level PD data is stored on Verification__c fields.
 */
public with sharing class PdController implements Callable {

    private static final String ACTION_GET_PAGE_DATA = 'getPageData';
    private static final String ACTION_CREATE_PD_INVESTIGATION_RECORDS = 'createPdRecords';
    private static final String ACTION_SAVE_PD_INVESTIGATION_DETAILS = 'savePdDetails';

    private static final String TYPE_PD = 'PD';
    private static final String STATUS_INITIATED = 'Initiated';
    private static final String STATUS_IN_PROGRESS = 'In Progress';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final String STATUS_ACCEPTED = 'Accepted';
    private static final String INVESTIGATION_STATUS_IN_PROGRESS = 'In-Progress';
    private static final String INVESTIGATION_STATUS_CLOSED = 'Closed';
    private static final String INVESTIGATION_NAME = 'PD';
    private static final String VERIFICATION_NAME_PREFIX = 'Personal Discussion';
    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';
    private static final String APPLICANT_TYPE_CO_BORROWER = 'Co-borrower';
    private static final String APPLICANT_TYPE_GUARANTOR = 'Guarantor';
    private static final String APPLICANT_TYPE_BENEFICIARY = 'Beneficiary';
    private static final String PD_TYPE_BORROWER = 'Borrower';
    private static final String PD_TYPE_CO_APPLICANT_GUARANTOR = 'Co-Applicant / Guarantor';
    private static final String PD_MODE_RESIDENCE = 'Physical - Residence';
    private static final String UI_STATUS_PENDING = 'Pending';
    private static final String CHECKLIST_ANSWER_NO = 'No';

    private static final String FB_PD_TYPE = 'pdType';
    private static final String FB_PD_MODE = 'pdMode';
    private static final String FB_APPLICANT_PROFILE = 'applicantProfileObservations';
    private static final String FB_OVERALL_REMARKS = 'overallRemarks';
    private static final String FB_ADDITIONAL_REMARKS = 'additionalRemarks';
    private static final String FB_FINAL_REMARKS = 'finalRemarks';
    private static final String FB_RECOMMENDATION = 'recommendation';
    private static final String FB_VERIFICATION_CHECKLIST = 'verificationChecklist';

    private static final Map<String, String> CHECKLIST_KEY_TO_FIELD = new Map<String, String>{
        'applicantIdentityKyc' => 'Applicant_Identity_KYC_Confirmed__c',
        'residenceAddressStability' => 'Residence_Address_Stability_Verified__c',
        'occupationIncomeSource' => 'Occupation_Income_Source_Confirmed__c',
        'endUsePurposeGenuine' => 'End_Use_Purpose_Genuine__c',
        'obligationsRepaymentIntent' => 'Obligations_Repayment_Intent_Assessed__c',
        'noAdverseProfile' => 'No_Adverse_Profile_Observed__c'
    };

    private static final Map<String, String> FORM_KEY_TO_VERIFICATION_FIELD = new Map<String, String>{
        'pdType' => 'PD_Type__c',
        'pdMode' => 'PD_Mode__c',
        'verificationWith' => 'Verification_With__c',
        'contactNumber' => 'Mobile__c',
        'applicantProfileObservations' => 'Applicant_Profile_Observations__c',
        'overallRemarks' => 'Remarks__c',
        'additionalRemarks' => 'Additional_Remarks__c',
        'finalRemarks' => 'Final_Remarks__c',
        'verificationStatus' => 'Status__c',
        'recommendation' => 'Recommendation__c'
    };

    private static final String PD_VERIFICATION_FIELDS =
        'Verification_With__c, Applicant_Profile_Observations__c, Recommendation__c, ' +
        'PD_Type__c, PD_Mode__c, Additional_Remarks__c, Final_Remarks__c, Remarks__c, ' +
        'Applicant_Identity_KYC_Confirmed__c, Residence_Address_Stability_Verified__c, ' +
        'Occupation_Income_Source_Confirmed__c, End_Use_Purpose_Genuine__c, ' +
        'Obligations_Repayment_Intent_Assessed__c, No_Adverse_Profile_Observed__c';

    private static final String VERIFICATION_READ_SUBQUERY =
        '(SELECT Id, Name, Applicant__c, Status__c, Feedback__c, ' +
        'Mobile__c, Submitted_Date__c, Submitted_By__c, ' +
        'Submitted_By__r.Name, ' +
        PD_VERIFICATION_FIELDS + ', ' +
        'Applicant__r.Name, Applicant__r.Applicant_Type__c, Applicant__r.Company_Name__c, ' +
        'Applicant__r.Customer_First_Name__c, Applicant__r.Customer_Last_Name__c, ' +
        'Applicant__r.Contact_number__c FROM Verifications__r ORDER BY CreatedDate ASC)';

    private static final String APPLICATION_PAGE_SOQL =
        'SELECT Id, ' +
        '(SELECT Id, Name, Applicant_Type__c, Company_Name__c, ' +
        'Customer_First_Name__c, Customer_Last_Name__c, Contact_number__c ' +
        'FROM Applicants__r WHERE In_Active_Applicant__c = false ' +
        'AND Applicant_Type__c IN (:APPLICANT_TYPE_BORROWER, :APPLICANT_TYPE_CO_BORROWER, :APPLICANT_TYPE_GUARANTOR) ' +
        'ORDER BY CreatedDate ASC), ' +
        '(SELECT Id, Application__c, Status__c, ' + VERIFICATION_READ_SUBQUERY + ' ' +
        'FROM Application_Investigations__r WHERE Type_of_Investigation__c = :TYPE_PD LIMIT 1) ' +
        'FROM Application__c';

    private static final String SAVE_INVESTIGATION_SOQL =
        'SELECT Id, Status__c, ' +
        '(SELECT Id, Status__c, Feedback__c, Mobile__c, Submitted_Date__c, Submitted_By__c, ' +
        PD_VERIFICATION_FIELDS + ' FROM Verifications__r) ' +
        'FROM Investigations__c WHERE Type_of_Investigation__c = :TYPE_PD ' +
        'AND Id IN (SELECT Investigations__c FROM Verification__c WHERE Id = :verificationId)';

    public class PdSummaryCounts {
        @AuraEnabled public Integer pendingCount { get; set; }
        @AuraEnabled public Integer inProgressCount { get; set; }
        @AuraEnabled public Integer completedCount { get; set; }
        @AuraEnabled public Integer flagsRaisedCount { get; set; }
    }

    public class PdParticipant {
        @AuraEnabled public String verificationId { get; set; }
        @AuraEnabled public String applicantId { get; set; }
        @AuraEnabled public String applicantName { get; set; }
        @AuraEnabled public String roleLabel { get; set; }
        @AuraEnabled public String statusLabel { get; set; }
        @AuraEnabled public String initials { get; set; }
        @AuraEnabled public Integer avatarToneIndex { get; set; }
        @AuraEnabled public Boolean flagRaised { get; set; }
        @AuraEnabled public Boolean isSubmitted { get; set; }
    }

    public class PdVerificationForm {
        @AuraEnabled public String verificationId { get; set; }
        @AuraEnabled public String applicantId { get; set; }
        @AuraEnabled public String applicantName { get; set; }
        @AuraEnabled public String pdType { get; set; }
        @AuraEnabled public String pdMode { get; set; }
        @AuraEnabled public String verificationWith { get; set; }
        @AuraEnabled public String contactNumber { get; set; }
        @AuraEnabled public String pdDateTime { get; set; }
        @AuraEnabled public String conductedBy { get; set; }
        @AuraEnabled public String applicantProfileObservations { get; set; }
        @AuraEnabled public String overallRemarks { get; set; }
        @AuraEnabled public String additionalRemarks { get; set; }
        @AuraEnabled public String verificationStatus { get; set; }
        @AuraEnabled public String recommendation { get; set; }
        @AuraEnabled public String finalRemarks { get; set; }
        @AuraEnabled public Boolean flagRaised { get; set; }
        @AuraEnabled public Boolean isSubmitted { get; set; }
        @AuraEnabled public Map<String, String> verificationChecklist { get; set; }
    }

    public class PdInvestigationPageData {
        @AuraEnabled public String investigationId { get; set; }
        @AuraEnabled public String applicationId { get; set; }
        @AuraEnabled public String investigationStatus { get; set; }
        @AuraEnabled public Boolean isClosed { get; set; }
        @AuraEnabled public PdSummaryCounts summaryCounts { get; set; }
        @AuraEnabled public List<PdParticipant> participants { get; set; }
        @AuraEnabled public List<PdVerificationForm> verificationForms { get; set; }
    }

    public class CreateResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String investigationId { get; set; }
        @AuraEnabled public Integer verificationsCreated { get; set; }
    }

    public class SaveResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();
        try {
            if (ACTION_GET_PAGE_DATA.equalsIgnoreCase(action)) {
                return toResultMap(getPageData(safeArgs));
            }
            if (ACTION_CREATE_PD_INVESTIGATION_RECORDS.equalsIgnoreCase(action)) {
                return toResultMap(createPdRecords(safeArgs));
            }
            if (ACTION_SAVE_PD_INVESTIGATION_DETAILS.equalsIgnoreCase(action)) {
                return toResultMap(savePdDetails(safeArgs));
            }
            throw new CalloutException('Unknown action: ' + action);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static PdInvestigationPageData getPageData(Map<String, Object> args) {
        PdInvestigationPageData pageData = new PdInvestigationPageData();
        pageData.summaryCounts = new PdSummaryCounts();
        pageData.summaryCounts.pendingCount = 0;
        pageData.summaryCounts.inProgressCount = 0;
        pageData.summaryCounts.completedCount = 0;
        pageData.summaryCounts.flagsRaisedCount = 0;
        pageData.participants = new List<PdParticipant>();
        pageData.verificationForms = new List<PdVerificationForm>();

        if (args.get('recordId') == null) {
            return pageData;
        }
        Id recordId = (Id) String.valueOf(args.get('recordId')).trim();

        Application__c application = queryApplicationContext(recordId);
        if (application == null
            || application.Application_Investigations__r == null
            || application.Application_Investigations__r.isEmpty()) {
            return pageData;
        }

        Investigations__c investigation = application.Application_Investigations__r[0];
        List<Verification__c> verificationRows = sortPdVerificationsByApplicantType(
            investigation.Verifications__r != null
                ? investigation.Verifications__r
                : new List<Verification__c>()
        );

        pageData.investigationId = investigation.Id;
        pageData.applicationId = investigation.Application__c;
        pageData.investigationStatus = investigation.Status__c;
        pageData.isClosed = investigation.Status__c == INVESTIGATION_STATUS_CLOSED;

        String currentUserDisplay = UserInfo.getName();
        Integer toneIndex = 0;

        Set<Id> applicantIds = new Set<Id>();
        for (Verification__c verification : verificationRows) {
            if (verification.Applicant__c != null) {
                applicantIds.add(verification.Applicant__c);
            }
        }
        Map<Id, Document_CheckList__c> poiByApplicant = getPoiIdentityDocumentsByApplicant(applicantIds);

        for (Verification__c verification : verificationRows) {
            Applicant__c applicant = verification.Applicant__r;
            Map<String, Object> legacyFeedback = parseFeedback(verification.Feedback__c);
            Map<String, String> checklist = buildChecklistFromVerification(verification, legacyFeedback);
            Boolean flagRaised = hasChecklistFlag(checklist);
            Boolean isStatusComplete = verification.Status__c == STATUS_COMPLETED
                || verification.Status__c == STATUS_ACCEPTED;
            Boolean isPdComplete = isStatusComplete && !flagRaised;

            if (flagRaised) {
                pageData.summaryCounts.flagsRaisedCount++;
            }
            if (isPdComplete) {
                pageData.summaryCounts.completedCount++;
            } else if (verification.Status__c == STATUS_IN_PROGRESS || flagRaised) {
                pageData.summaryCounts.inProgressCount++;
            } else {
                pageData.summaryCounts.pendingCount++;
            }

            String applicantName = getApplicantDisplayName(
                applicant,
                poiByApplicant.get(verification.Applicant__c)
            );
            String applicantType = applicant?.Applicant_Type__c;
            String roleLabel;
            if (APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicantType)) {
                roleLabel = 'Primary Applicant';
            } else if (APPLICANT_TYPE_CO_BORROWER.equalsIgnoreCase(applicantType)) {
                roleLabel = 'Co-Applicant';
            } else if (APPLICANT_TYPE_GUARANTOR.equalsIgnoreCase(applicantType)) {
                roleLabel = 'Guarantor';
            } else if (APPLICANT_TYPE_BENEFICIARY.equalsIgnoreCase(applicantType)) {
                roleLabel = 'Beneficiary';
            } else {
                roleLabel = applicantType != null ? applicantType : '';
            }
            String statusLabel = String.isBlank(verification.Status__c)
                || STATUS_INITIATED.equalsIgnoreCase(verification.Status__c)
                ? UI_STATUS_PENDING : verification.Status__c;

            String initials = 'NA';
            if (String.isNotBlank(applicantName)) {
                initials = '';
                for (String part : applicantName.trim().split('\\s+')) {
                    if (String.isNotBlank(part)) {
                        initials += part.substring(0, 1).toUpperCase();
                    }
                    if (initials.length() >= 2) {
                        break;
                    }
                }
                if (String.isBlank(initials)) {
                    initials = 'NA';
                }
            }

            PdParticipant participant = new PdParticipant();
            participant.verificationId = verification.Id;
            participant.applicantId = verification.Applicant__c;
            participant.applicantName = applicantName;
            participant.roleLabel = roleLabel;
            participant.statusLabel = statusLabel;
            participant.initials = initials;
            participant.avatarToneIndex = toneIndex++;
            participant.flagRaised = flagRaised;
            participant.isSubmitted = verification.Submitted_Date__c != null;
            pageData.participants.add(participant);

            String conductedBy = currentUserDisplay;
            if (verification.Submitted_By__r != null && String.isNotBlank(verification.Submitted_By__r.Name)) {
                conductedBy = verification.Submitted_By__r.Name;
            }

            PdVerificationForm form = new PdVerificationForm();
            form.verificationId = verification.Id;
            form.applicantId = verification.Applicant__c;
            form.applicantName = applicantName;
            form.pdType = resolveFieldWithLegacy(verification.PD_Type__c, legacyFeedback, FB_PD_TYPE);
            form.pdMode = resolveFieldWithLegacy(verification.PD_Mode__c, legacyFeedback, FB_PD_MODE);
            form.verificationWith = verification.Verification_With__c;
            form.contactNumber = verification.Mobile__c;
            form.pdDateTime = verification.Submitted_Date__c == null ? null
                : verification.Submitted_Date__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            form.conductedBy = conductedBy;
            form.applicantProfileObservations = resolveFieldWithLegacy(
                verification.Applicant_Profile_Observations__c,
                legacyFeedback,
                FB_APPLICANT_PROFILE
            );
            form.overallRemarks = resolveFieldWithLegacy(
                verification.Remarks__c,
                legacyFeedback,
                FB_OVERALL_REMARKS
            );
            form.additionalRemarks = resolveFieldWithLegacy(
                verification.Additional_Remarks__c,
                legacyFeedback,
                FB_ADDITIONAL_REMARKS
            );
            form.verificationStatus = verification.Status__c;
            form.recommendation = resolveFieldWithLegacy(
                verification.Recommendation__c,
                legacyFeedback,
                FB_RECOMMENDATION
            );
            form.finalRemarks = resolveFieldWithLegacy(
                verification.Final_Remarks__c,
                legacyFeedback,
                FB_FINAL_REMARKS
            );
            form.flagRaised = flagRaised;
            form.isSubmitted = verification.Submitted_Date__c != null;
            form.verificationChecklist = checklist;
            pageData.verificationForms.add(form);
        }

        return pageData;
    }

    private static CreateResult createPdRecords(Map<String, Object> args) {
        CreateResult result = new CreateResult();
        result.isSuccess = false;
        result.verificationsCreated = 0;

        if (args.get('recordId') == null) {
            result.message = 'Record Id is required.';
            return result;
        }
        Id recordId = (Id) String.valueOf(args.get('recordId')).trim();

        Application__c application = queryApplicationContext(recordId);
        if (application == null) {
            result.message = 'Unable to create PD investigation records.';
            return result;
        }

        List<Applicant__c> applicants = application.Applicants__r != null
            ? application.Applicants__r
            : new List<Applicant__c>();

        Investigations__c investigation;
        if (application.Application_Investigations__r != null && !application.Application_Investigations__r.isEmpty()) {
            investigation = application.Application_Investigations__r[0];
        } else if (recordId.getSobjectType() == Application__c.SObjectType) {
            investigation = new Investigations__c(
                Application__c = application.Id,
                Type_of_Investigation__c = TYPE_PD,
                Status__c = INVESTIGATION_STATUS_IN_PROGRESS,
                Name = INVESTIGATION_NAME
            );
            insert investigation;
        } else {
            result.message = 'Unable to create PD investigation records.';
            return result;
        }

        Set<Id> applicantIdsWithVerification = new Set<Id>();
        List<Verification__c> verificationRows = investigation.Verifications__r != null
            ? investigation.Verifications__r
            : new List<Verification__c>();

        for (Verification__c verification : verificationRows) {
            if (verification.Applicant__c != null) {
                applicantIdsWithVerification.add(verification.Applicant__c);
            }
        }

        Set<Id> applicantIds = new Set<Id>();
        for (Applicant__c applicant : applicants) {
            applicantIds.add(applicant.Id);
        }
        Map<Id, Document_CheckList__c> poiByApplicant = getPoiIdentityDocumentsByApplicant(applicantIds);

        List<Verification__c> verificationsToInsert = new List<Verification__c>();
        for (Applicant__c applicant : applicants) {
            if (applicantIdsWithVerification.contains(applicant.Id)) {
                continue;
            }
            String applicantName = getApplicantDisplayName(applicant, poiByApplicant.get(applicant.Id));
            String defaultPdType = APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicant.Applicant_Type__c)
                ? PD_TYPE_BORROWER
                : PD_TYPE_CO_APPLICANT_GUARANTOR;
            verificationsToInsert.add(new Verification__c(
                Investigations__c = investigation.Id,
                Applicant__c = applicant.Id,
                Name = VERIFICATION_NAME_PREFIX + ' - ' + applicantName,
                Status__c = STATUS_INITIATED,
                Verification_With__c = applicantName,
                Mobile__c = applicant.Contact_number__c,
                PD_Type__c = defaultPdType,
                PD_Mode__c = PD_MODE_RESIDENCE
            ));
        }
        if (!verificationsToInsert.isEmpty()) {
            insert verificationsToInsert;
            result.verificationsCreated = verificationsToInsert.size();
        }

        result.isSuccess = true;
        result.investigationId = investigation.Id;
        result.message = 'PD investigation records are ready.';
        return result;
    }

    private static Application__c queryApplicationContext(Id recordId) {
        Schema.SObjectType recordType = recordId.getSobjectType();
        String whereClause;

        if (recordType == Application__c.SObjectType) {
            whereClause = 'Id = :recordId';
        } else if (recordType == Investigations__c.SObjectType) {
            whereClause =
                'Id IN (SELECT Application__c FROM Investigations__c ' +
                'WHERE Id = :recordId AND Type_of_Investigation__c = :TYPE_PD)';
        } else {
            return null;
        }

        List<Application__c> applications = (List<Application__c>) Database.query(
            APPLICATION_PAGE_SOQL + ' WHERE ' + whereClause + ' WITH SECURITY_ENFORCED LIMIT 1'
        );
        return applications.isEmpty() ? null : applications[0];
    }

    private static SaveResult savePdDetails(Map<String, Object> args) {
        SaveResult result = new SaveResult();
        result.isSuccess = false;

        if (args.get('recordId') == null) {
            result.message = 'Record Id is required.';
            return result;
        }
        Id verificationId = (Id) String.valueOf(args.get('recordId')).trim();

        Map<String, Object> formData = parseObjectToMap(args.get('formData'));
        if (formData == null || formData.isEmpty()) {
            result.message = 'No form data supplied.';
            return result;
        }

        List<Investigations__c> investigations = (List<Investigations__c>) Database.query(
            SAVE_INVESTIGATION_SOQL + ' WITH SECURITY_ENFORCED LIMIT 1'
        );
        if (investigations.isEmpty() || investigations[0].Verifications__r == null) {
            result.message = 'PD verification record not found.';
            return result;
        }

        Investigations__c investigation = investigations[0];
        Verification__c verification;
        for (Verification__c row : investigation.Verifications__r) {
            if (row.Id == verificationId) {
                verification = row;
                break;
            }
        }
        if (verification == null) {
            result.message = 'PD verification record not found.';
            return result;
        }

        for (String formKey : FORM_KEY_TO_VERIFICATION_FIELD.keySet()) {
            if (!formData.containsKey(formKey)) {
                continue;
            }
            Object rawValue = formData.get(formKey);
            String value = null;
            if (rawValue != null) {
                String trimmed = String.valueOf(rawValue).trim();
                value = String.isBlank(trimmed) ? null : trimmed;
            }
            verification.put(FORM_KEY_TO_VERIFICATION_FIELD.get(formKey), value);
        }

        Map<String, Object> checklist = parseObjectToMap(formData.get('verificationChecklist'));
        if (checklist != null) {
            for (String checklistKey : CHECKLIST_KEY_TO_FIELD.keySet()) {
                if (!checklist.containsKey(checklistKey)) {
                    continue;
                }
                String fieldApiName = CHECKLIST_KEY_TO_FIELD.get(checklistKey);
                Object rawValue = checklist.get(checklistKey);
                if (rawValue == null) {
                    verification.put(fieldApiName, null);
                    continue;
                }
                String value = String.valueOf(rawValue).trim();
                if (String.isNotBlank(value) && !'N/A'.equalsIgnoreCase(value)) {
                    verification.put(fieldApiName, value);
                } else {
                    verification.put(fieldApiName, null);
                }
            }
        }

        Map<String, String> savedChecklist = buildChecklistFromVerification(
            verification,
            parseFeedback(verification.Feedback__c)
        );
        if (hasChecklistFlag(savedChecklist)
            && (verification.Status__c == STATUS_COMPLETED
                || verification.Status__c == STATUS_ACCEPTED)) {
            verification.Status__c = STATUS_IN_PROGRESS;
        }

        if (verification.Submitted_Date__c == null) {
            verification.Submitted_Date__c = Datetime.now();
        }
        if (verification.Submitted_By__c == null) {
            verification.Submitted_By__c = UserInfo.getUserId();
        }

        Boolean allCompleted = true;
        for (Verification__c child : investigation.Verifications__r) {
            Verification__c workingRow = child.Id == verification.Id ? verification : child;
            Boolean isComplete = workingRow != null
                && (workingRow.Status__c == STATUS_COMPLETED
                    || workingRow.Status__c == STATUS_ACCEPTED);
            if (isComplete) {
                Map<String, String> rowChecklist = buildChecklistFromVerification(
                    workingRow,
                    parseFeedback(workingRow.Feedback__c)
                );
                isComplete = !hasChecklistFlag(rowChecklist);
            }
            if (!isComplete) {
                allCompleted = false;
            }
        }
        investigation.Status__c = allCompleted
            ? INVESTIGATION_STATUS_CLOSED
            : INVESTIGATION_STATUS_IN_PROGRESS;

        update new List<SObject>{ verification, investigation };

        result.isSuccess = true;
        result.message = 'Personal Discussion saved successfully.';
        return result;
    }

    private static Map<String, String> buildChecklistFromVerification(
            Verification__c verification,
            Map<String, Object> legacyFeedback) {
        Map<String, String> checklist = new Map<String, String>();
        if (legacyFeedback != null
            && legacyFeedback.containsKey(FB_VERIFICATION_CHECKLIST)
            && legacyFeedback.get(FB_VERIFICATION_CHECKLIST) instanceof Map<String, Object>) {
            Map<String, Object> rawChecklist =
                (Map<String, Object>) legacyFeedback.get(FB_VERIFICATION_CHECKLIST);
            for (String key : rawChecklist.keySet()) {
                if (rawChecklist.get(key) == null) {
                    continue;
                }
                String value = String.valueOf(rawChecklist.get(key)).trim();
                if (String.isNotBlank(value) && !'N/A'.equalsIgnoreCase(value)) {
                    checklist.put(key, value);
                }
            }
        }
        for (String checklistKey : CHECKLIST_KEY_TO_FIELD.keySet()) {
            String fieldApiName = CHECKLIST_KEY_TO_FIELD.get(checklistKey);
            String fieldValue = (String) verification.get(fieldApiName);
            if (String.isNotBlank(fieldValue) && !'N/A'.equalsIgnoreCase(fieldValue)) {
                checklist.put(checklistKey, fieldValue);
            }
        }
        return checklist;
    }

    private static Boolean hasChecklistFlag(Map<String, String> checklist) {
        if (checklist == null || checklist.isEmpty()) {
            return false;
        }
        for (String answer : checklist.values()) {
            if (CHECKLIST_ANSWER_NO.equalsIgnoreCase(answer)) {
                return true;
            }
        }
        return false;
    }

    private static Map<String, Object> toResultMap(Object data) {
        if (data == null) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(data));
    }

    private static Map<String, Object> parseObjectToMap(Object rawValue) {
        if (rawValue instanceof Map<String, Object>) {
            return (Map<String, Object>) rawValue;
        }
        if (rawValue == null) {
            return null;
        }
        try {
            Object reparsed = JSON.deserializeUntyped(JSON.serialize(rawValue));
            if (reparsed instanceof Map<String, Object>) {
                return (Map<String, Object>) reparsed;
            }
        } catch (Exception ex) {
            return null;
        }
        return null;
    }

    private static Map<String, Object> parseFeedback(String feedbackJson) {
        if (String.isBlank(feedbackJson)) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(feedbackJson);
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private static String resolveFieldWithLegacy(
            String fieldValue,
            Map<String, Object> feedback,
            String feedbackKey) {
        if (String.isNotBlank(fieldValue)) {
            return fieldValue;
        }
        if (feedback == null || !feedback.containsKey(feedbackKey) || feedback.get(feedbackKey) == null) {
            return null;
        }
        String legacyValue = String.valueOf(feedback.get(feedbackKey)).trim();
        return String.isBlank(legacyValue) ? null : legacyValue;
    }

    private static Integer getPdApplicantTypeSortRank(String applicantType) {
        if (String.isBlank(applicantType)) {
            return 99;
        }
        if (APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicantType)) {
            return 0;
        }
        if (APPLICANT_TYPE_GUARANTOR.equalsIgnoreCase(applicantType)) {
            return 1;
        }
        if (APPLICANT_TYPE_CO_BORROWER.equalsIgnoreCase(applicantType)) {
            return 2;
        }
        if (APPLICANT_TYPE_BENEFICIARY.equalsIgnoreCase(applicantType)) {
            return 3;
        }
        return 4;
    }

    private static List<Verification__c> sortPdVerificationsByApplicantType(List<Verification__c> verificationRows) {
        List<Verification__c> eligibleRows = new List<Verification__c>();
        if (verificationRows == null || verificationRows.isEmpty()) {
            return eligibleRows;
        }
        for (Verification__c verification : verificationRows) {
            if (verification.Applicant__c != null) {
                eligibleRows.add(verification);
            }
        }
        if (eligibleRows.size() > 1) {
            eligibleRows.sort(new PdVerificationApplicantTypeComparator());
        }
        return eligibleRows;
    }

    private class PdVerificationApplicantTypeComparator implements System.Comparator<Verification__c> {
        public Integer compare(Verification__c left, Verification__c right) {
            String leftType = left?.Applicant__r?.Applicant_Type__c;
            String rightType = right?.Applicant__r?.Applicant_Type__c;
            Integer leftRank = getPdApplicantTypeSortRank(leftType);
            Integer rightRank = getPdApplicantTypeSortRank(rightType);
            if (leftRank != rightRank) {
                return leftRank < rightRank ? -1 : 1;
            }
            String leftName = left?.Applicant__r?.Name != null ? left.Applicant__r.Name : '';
            String rightName = right?.Applicant__r?.Name != null ? right.Applicant__r.Name : '';
            return leftName.compareTo(rightName);
        }
    }

    private static Map<Id, Document_CheckList__c> getPoiIdentityDocumentsByApplicant(Set<Id> applicantIds) {
        Map<Id, Document_CheckList__c> poiByApplicant = new Map<Id, Document_CheckList__c>();
        if (applicantIds == null || applicantIds.isEmpty()) {
            return poiByApplicant;
        }

        for (Document_CheckList__c document : [
            SELECT Id,
                   Applicant__c,
                   KYC_Date_of_Birth__c,
                   Gender__c,
                   First_Name__c,
                   Last_Name__c,
                   Applicant_Address__r.Address_Proof__c,
                   Applicant_Address__r.Identity_Proof__c
            FROM Document_CheckList__c
            WHERE Applicant__c IN :applicantIds
              AND Applicant_Address__r.Identity_Proof__c = true
              AND Is_Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ]) {
            if (!poiByApplicant.containsKey(document.Applicant__c)) {
                poiByApplicant.put(document.Applicant__c, document);
            }
        }
        return poiByApplicant;
    }

    private static String getApplicantDisplayName(
            Applicant__c applicant,
            Document_CheckList__c poiDocument) {
        if (applicant == null) {
            return '';
        }
        if (String.isNotBlank(applicant.Company_Name__c)) {
            return applicant.Company_Name__c;
        }
        if (poiDocument != null) {
            List<String> poiParts = new List<String>();
            if (String.isNotBlank(poiDocument.First_Name__c)) {
                poiParts.add(poiDocument.First_Name__c);
            }
            if (String.isNotBlank(poiDocument.Last_Name__c)) {
                poiParts.add(poiDocument.Last_Name__c);
            }
            String poiName = String.join(poiParts, ' ').trim();
            if (String.isNotBlank(poiName)) {
                return poiName;
            }
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(applicant.Customer_First_Name__c)) {
            parts.add(applicant.Customer_First_Name__c);
        }
        if (String.isNotBlank(applicant.Customer_Last_Name__c)) {
            parts.add(applicant.Customer_Last_Name__c);
        }
        String joined = String.join(parts, ' ').trim();
        return String.isNotBlank(joined) ? joined : (applicant.Name != null ? applicant.Name : '');
    }
}