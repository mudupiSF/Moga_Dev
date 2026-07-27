/**
 * Integration Master handler for AML Check outbound callouts.
 * Registered on Integration_Master__c.Apex_Class_Name__c for Name = AML Check.
 */
public with sharing class AMLCheckAPIHandler implements IIntegrationHandler {

    public static final String INTEGRATION_KEY = 'AML Check';

    private static final String TYPE_AML = 'AML';
    private static final String INVESTIGATION_STATUS_IN_PROGRESS = 'In-Progress';
    private static final String STATUS_INITIATED = 'Initiated';
    private static final String RULE_NAME = 'BRANCH_CUSTOMER_WL';
    private static final String INVESTIGATION_NAME_PREFIX = 'AML Investigation';

    private static Map<Id, AmlSessionData> sessionDataByApplicationId = new Map<Id, AmlSessionData>();

    private class AmlSessionData {
        Investigations__c investigation;
        Map<String, Verification__c> verificationByMlId = new Map<String, Verification__c>();
        Integer totalMatchCount = 0;
    }

    private class AmlProcessingResult {
        Integer matchCount = 0;
        Boolean hasMatches = false;
    }

    private class AmlRequestPayload {
        public String Application_No;
        public String ruleName;
        public List<AmlRequestField> fields;
    }

    private class AmlRequestField {
        public String name;
        public String value;

        AmlRequestField(String fieldName, String fieldValue) {
            name = fieldName;
            value = fieldValue;
        }
    }

    private class AmlMatchRecord {
        String mlId;
        String listName;
        String customerName;
        Decimal nameScore;
        String nationality;
        Decimal nationalityScore;
        String mlCity;
        String mlAddress;
        String mlDateOfBirth;
        String mlDescription;
        Boolean partialKycFlag;
    }

    public static void clearSessionCache() {
        sessionDataByApplicationId.clear();
    }

    public static Integer getSessionTotalMatchCount(Id applicationId) {
        AmlSessionData sessionData = sessionDataByApplicationId.get(applicationId);
        return sessionData == null ? 0 : sessionData.totalMatchCount;
    }

    public static Id getSessionInvestigationId(Id applicationId) {
        AmlSessionData sessionData = sessionDataByApplicationId.get(applicationId);
        return sessionData?.investigation?.Id;
    }

    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<sObject>();
        }

        return [
            SELECT Id,
                   Name,
                   Application__c,
                   Applicant_Type__c,
                   Company_Name__c,
                   Customer_First_Name__c,
                   Customer_Last_Name__c,
                   Date_of_Birth__c,
                   Application__r.Application_number__c,
                   (SELECT Id,
                           KYC_Date_of_Birth__c,
                           Applicant_KYC__r.KYC_DOB__c,
                           Applicant_KYC__r.KYC_City__c
                    FROM Document_CheckLists__r
                    ORDER BY CreatedDate ASC)
            FROM Applicant__c
            WHERE Id IN :recordIds
            WITH SECURITY_ENFORCED
        ];
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> validateInputData(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
        wrapper.hasValidationError = false;

        if (recordList == null || recordList.isEmpty() || recordList[0] == null) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage = 'Applicant record not found for AML Check.';
            wrapper.displayMessage = wrapper.errorMessage;
            return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
        }

        Applicant__c applicant = (Applicant__c) recordList[0];
        wrapper.recordId = applicant.Id;

        if (applicant.Application__c == null) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage = 'Application is required before AML Check.';
            wrapper.displayMessage = wrapper.errorMessage;
        } else if (String.isBlank(getApplicantDisplayName(applicant))) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage = 'Applicant name is required before AML Check.';
            wrapper.displayMessage = wrapper.errorMessage;
        }

        return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        if (recordList == null || recordList.isEmpty() || recordList[0] == null) {
            throw new CalloutException('Applicant record not found for AML Check.');
        }
        Applicant__c applicant = (Applicant__c) recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();
        wrapper.method = 'POST';
        wrapper.requestBody = buildRequestBody(applicant);
        wrapper.captureRequestInAttachment = false;
        return new List<ApplicationUtility.IntegrationRequestWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        Integration_Checklist__c checklist = null;

        try {
            if (recordList == null || recordList.isEmpty() || recordList[0] == null) {
                result.hasValidationError = true;
                result.errorMessage = 'AML Check response payload is missing.';
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            IntegrationUtility.ResponseWrapper wrapper = (IntegrationUtility.ResponseWrapper) recordList[0];
            if (wrapper == null) {
                result.hasValidationError = true;
                result.errorMessage = 'AML Check response wrapper is missing.';
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            checklist = wrapper.checklistRecord;

            if (wrapper.statusCode == null || wrapper.statusCode != 200) {
                markChecklistFailure(checklist, 'AML Check returned status ' + wrapper.statusCode);
                result.hasValidationError = true;
                result.errorMessage = 'AML Check API call failed.';
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            if (checklist == null) {
                result.hasValidationError = true;
                result.errorMessage = 'AML Check integration checklist is missing.';
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            Id applicantId = checklist.Applicant__c;
            if (applicantId == null) {
                markChecklistFailure(checklist, 'Applicant is missing on AML Check integration checklist.');
                result.hasValidationError = true;
                result.errorMessage = 'Applicant record not found for AML Check.';
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            Id applicationId = getApplicationIdByApplicantId(applicantId);
            if (applicationId == null) {
                markChecklistFailure(checklist, 'Application not found for AML Check.');
                result.hasValidationError = true;
                result.errorMessage = 'Application not found for AML Check.';
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            AmlProcessingResult processingResult = saveMatchedRecords(
                applicationId,
                applicantId,
                resolveResponseBody(wrapper)
            );
            checklist.Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            update checklist;

            result.hasValidationError = false;
            result.recordId = applicantId;
            result.displayMessage = processingResult.hasMatches
                ? processingResult.matchCount + ' AML match(es) recorded.'
                : 'No AML matches found.';
        } catch (Exception ex) {
            result.hasValidationError = true;
            result.errorMessage = 'AML Check response processing failed: ' + ex.getMessage();
            result.displayMessage = result.errorMessage;
            if (checklist != null) {
                markChecklistFailure(checklist, ex.getMessage());
            }
        }

        return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
    }

    private static AmlProcessingResult saveMatchedRecords(
        Id applicationId,
        Id applicantId,
        String responseBody
    ) {
        AmlProcessingResult processingResult = new AmlProcessingResult();
        if (applicationId == null || applicantId == null) {
            return processingResult;
        }

        List<AmlMatchRecord> matchedRecords = extractMatchedRecords(responseBody);
        processingResult.matchCount = matchedRecords.size();
        processingResult.hasMatches = !matchedRecords.isEmpty();

        AmlSessionData sessionData = loadSessionData(applicationId);
        sessionData.totalMatchCount += processingResult.matchCount;

        if (!processingResult.hasMatches) {
            return processingResult;
        }

        Investigations__c investigation = getOrCreateInvestigation(sessionData, applicationId);
        List<Verification__c> verificationsToInsert = new List<Verification__c>();
        List<Verification__c> verificationsToUpdate = new List<Verification__c>();

        for (AmlMatchRecord matchRecord : matchedRecords) {
            String dedupKey = resolveAmlDedupKey(matchRecord);
            if (String.isBlank(dedupKey)) {
                continue;
            }

            Verification__c existing = sessionData.verificationByMlId.get(dedupKey);

            if (existing != null && existing.Id != null) {
                Verification__c verificationUpdate = new Verification__c(
                    Id = existing.Id,
                    Applicant__c = applicantId
                );
                applyAmlFieldsToVerification(verificationUpdate, matchRecord);
                verificationsToUpdate.add(verificationUpdate);
                continue;
            }

            Verification__c verification = new Verification__c();
            verification.Investigations__c = investigation.Id;
            verification.Applicant__c = applicantId;
            verification.Name = buildVerificationRecordName(matchRecord.listName, dedupKey);
            verification.Status__c = STATUS_INITIATED;
            applyAmlFieldsToVerification(verification, matchRecord);
            verificationsToInsert.add(verification);
            sessionData.verificationByMlId.put(dedupKey, verification);
        }

        if (!verificationsToInsert.isEmpty()) {
            Database.insert(verificationsToInsert, AccessLevel.SYSTEM_MODE);
        }
        if (!verificationsToUpdate.isEmpty()) {
            Database.update(verificationsToUpdate, AccessLevel.SYSTEM_MODE);
        }

        if (investigation.Status__c != INVESTIGATION_STATUS_IN_PROGRESS) {
            Database.update(
                new Investigations__c(
                    Id = investigation.Id,
                    Status__c = INVESTIGATION_STATUS_IN_PROGRESS
                ),
                AccessLevel.SYSTEM_MODE
            );
            sessionData.investigation.Status__c = INVESTIGATION_STATUS_IN_PROGRESS;
        }

        return processingResult;
    }

    private static AmlSessionData loadSessionData(Id applicationId) {
        if (sessionDataByApplicationId.containsKey(applicationId)) {
            return sessionDataByApplicationId.get(applicationId);
        }

        AmlSessionData sessionData = new AmlSessionData();
        List<Investigations__c> investigations = [
            SELECT Id, Name, Status__c, Application__c, Type_of_Investigation__c
            FROM Investigations__c
            WHERE Application__c = :applicationId
              AND Type_of_Investigation__c = :TYPE_AML
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (!investigations.isEmpty()) {
            sessionData.investigation = investigations[0];
            for (Verification__c verification : [
                SELECT Id,
                       Name,
                       Applicant__c,
                       AML_Match_Id__c,
                       AML_List_Name__c
                FROM Verification__c
                WHERE Investigations__c = :sessionData.investigation.Id
                WITH SECURITY_ENFORCED
            ]) {
                String dedupKey = resolveAmlDedupKeyFromVerification(verification);
                if (String.isNotBlank(dedupKey)) {
                    sessionData.verificationByMlId.put(dedupKey, verification);
                }
            }
        }

        sessionDataByApplicationId.put(applicationId, sessionData);
        return sessionData;
    }

    private static Investigations__c getOrCreateInvestigation(
        AmlSessionData sessionData,
        Id applicationId
    ) {
        if (sessionData.investigation != null && sessionData.investigation.Id != null) {
            return sessionData.investigation;
        }

        Investigations__c investigation = new Investigations__c();
        investigation.Application__c = applicationId;
        investigation.Type_of_Investigation__c = TYPE_AML;
        investigation.Status__c = INVESTIGATION_STATUS_IN_PROGRESS;
        investigation.Name = INVESTIGATION_NAME_PREFIX;
        Database.insert(investigation, AccessLevel.SYSTEM_MODE);
        sessionData.investigation = investigation;
        return investigation;
    }

    private static String resolveResponseBody(IntegrationUtility.ResponseWrapper wrapper) {
        if (wrapper == null) {
            return '';
        }
        if (String.isNotBlank(wrapper.response)) {
            return wrapper.response;
        }
        if (wrapper.responsebody != null && String.isNotBlank(wrapper.responsebody.getBody())) {
            return wrapper.responsebody.getBody();
        }
        if (wrapper.checklistRecord != null && String.isNotBlank(wrapper.checklistRecord.Response__c)) {
            return wrapper.checklistRecord.Response__c;
        }
        if (wrapper.checklistRecord != null && String.isNotBlank(wrapper.checklistRecord.Decrypted_Response__c)) {
            return wrapper.checklistRecord.Decrypted_Response__c;
        }
        return '';
    }

    private static String buildRequestBody(Applicant__c applicant) {
        AmlRequestPayload requestPayload = new AmlRequestPayload();
        requestPayload.Application_No = generateReferenceNumber(applicant);
        requestPayload.ruleName = RULE_NAME;
        requestPayload.fields = new List<AmlRequestField>{
            new AmlRequestField('name', getApplicantDisplayName(applicant)),
            new AmlRequestField('nationality', 'India'),
            new AmlRequestField('dob', getApplicantDateOfBirth(applicant)),
            new AmlRequestField('resAddrCity', getApplicantResidenceCity(applicant))
        };
        return JSON.serialize(requestPayload);
    }

    private static String generateReferenceNumber(Applicant__c applicant) {
        String applicationNumber = applicant.Application__r?.Application_number__c;
        if (String.isBlank(applicationNumber)) {
            applicationNumber = String.valueOf(applicant.Application__c);
        }
        return applicationNumber + '_' + String.valueOf(applicant.Id).right(6);
    }

    private static List<AmlMatchRecord> extractMatchedRecords(String responseBody) {
        List<AmlMatchRecord> matchedRecords = new List<AmlMatchRecord>();
        if (String.isBlank(responseBody)) {
            return matchedRecords;
        }

        Map<String, Object> root;
        try {
            root = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        } catch (Exception e) {
            return matchedRecords;
        }

        Map<String, Object> wlMatch = firstAsMap(root, new List<String>{ 'wlMatch', 'WlMatch' });
        if (wlMatch == null) {
            return matchedRecords;
        }

        Map<String, Object> matchedResults = firstAsMap(wlMatch, new List<String>{ 'matchedResults', 'MatchedResults' });
        if (matchedResults == null) {
            return matchedRecords;
        }

        Object matchedRecordsRaw = matchedResults.containsKey('matchedRecords')
            ? matchedResults.get('matchedRecords')
            : matchedResults.get('MatchedRecords');
        if (!(matchedRecordsRaw instanceof List<Object>)) {
            return matchedRecords;
        }

        for (Object recordObject : (List<Object>) matchedRecordsRaw) {
            Map<String, Object> recordMap = asMap(recordObject);
            if (recordMap != null) {
                matchedRecords.add(mapToMatchRecord(recordMap));
            }
        }
        return matchedRecords;
    }

    private static AmlMatchRecord mapToMatchRecord(Map<String, Object> recordMap) {
        AmlMatchRecord matchRecord = new AmlMatchRecord();
        matchRecord.mlId = stringValue(recordMap.get('id'));
        matchRecord.listName = stringValue(recordMap.get('listName'));
        matchRecord.mlCity = stringValue(recordMap.get('city'));
        matchRecord.mlAddress = stringValue(recordMap.get('address'));
        matchRecord.mlDateOfBirth = stringValue(recordMap.get('DateOfBirth'));
        matchRecord.mlDescription = stringValue(recordMap.get('description'));
        matchRecord.partialKycFlag = parseBoolean(recordMap.get('partialKycFlag'));
        matchRecord.nameScore = toPercentScore(recordMap.get('score'));

        if (recordMap.get('fields') instanceof List<Object>) {
            for (Object fieldObject : (List<Object>) recordMap.get('fields')) {
                Map<String, Object> fieldMap = asMap(fieldObject);
                if (fieldMap == null) {
                    continue;
                }
                String fieldName = stringValue(fieldMap.get('name'));
                if (fieldName == 'name') {
                    matchRecord.customerName = stringValue(fieldMap.get('value'));
                    if (fieldMap.get('score') != null) {
                        matchRecord.nameScore = toPercentScore(fieldMap.get('score'));
                    }
                } else if (fieldName == 'nationality') {
                    matchRecord.nationality = stringValue(fieldMap.get('value'));
                    if (fieldMap.get('score') != null) {
                        matchRecord.nationalityScore = toPercentScore(fieldMap.get('score'));
                    }
                }
            }
        }

        if (String.isBlank(matchRecord.customerName)) {
            matchRecord.customerName = matchRecord.listName;
        }
        return matchRecord;
    }

    private static String getApplicantDisplayName(Applicant__c applicant) {
        if (applicant == null) {
            return '';
        }
        if (String.isNotBlank(applicant.Company_Name__c)) {
            return applicant.Company_Name__c;
        }
        List<String> nameParts = new List<String>();
        if (String.isNotBlank(applicant.Customer_First_Name__c)) {
            nameParts.add(applicant.Customer_First_Name__c);
        }
        if (String.isNotBlank(applicant.Customer_Last_Name__c)) {
            nameParts.add(applicant.Customer_Last_Name__c);
        }
        if (!nameParts.isEmpty()) {
            return String.join(nameParts, ' ');
        }
        return applicant.Name;
    }

    private static String getApplicantDateOfBirth(Applicant__c applicant) {
        Date dateOfBirth = applicant.Date_of_Birth__c;
        if (dateOfBirth == null && applicant.Document_CheckLists__r != null) {
            for (Document_CheckList__c document : applicant.Document_CheckLists__r) {
                if (document.KYC_Date_of_Birth__c != null) {
                    dateOfBirth = document.KYC_Date_of_Birth__c;
                    break;
                }
                if (document.Applicant_KYC__r?.KYC_DOB__c != null) {
                    dateOfBirth = document.Applicant_KYC__r.KYC_DOB__c;
                    break;
                }
            }
        }
        return dateOfBirth == null
            ? ''
            : DateTime.newInstance(dateOfBirth, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
    }

    private static String getApplicantResidenceCity(Applicant__c applicant) {
        if (applicant.Document_CheckLists__r == null) {
            return '';
        }
        for (Document_CheckList__c document : applicant.Document_CheckLists__r) {
            if (document.Applicant_KYC__r != null && String.isNotBlank(document.Applicant_KYC__r.KYC_City__c)) {
                return document.Applicant_KYC__r.KYC_City__c;
            }
        }
        return '';
    }

    private static void markChecklistFailure(Integration_Checklist__c checklist, String reason) {
        if (checklist == null) {
            return;
        }
        checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
        checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
        checklist.Functional_Failure_Reason__c = reason;
        update checklist;
    }

    private static Id getApplicationIdByApplicantId(Id applicantId) {
        if (applicantId == null) {
            return null;
        }
        List<Applicant__c> applicants = [
            SELECT Application__c
            FROM Applicant__c
            WHERE Id = :applicantId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return applicants.isEmpty() ? null : applicants[0].Application__c;
    }

    private static String buildVerificationRecordName(String listName, String mlId) {
        return String.isNotBlank(listName) ? listName.left(80) : 'AML Match ' + mlId.left(60);
    }

    private static String resolveAmlDedupKey(AmlMatchRecord matchRecord) {
        if (matchRecord == null) {
            return '';
        }
        return String.isNotBlank(matchRecord.mlId) ? matchRecord.mlId : matchRecord.listName;
    }

    private static String resolveAmlDedupKeyFromVerification(Verification__c verification) {
        if (verification == null) {
            return '';
        }
        if (String.isNotBlank(verification.AML_Match_Id__c)) {
            return verification.AML_Match_Id__c;
        }
        return verification.AML_List_Name__c;
    }

    private static void applyAmlFieldsToVerification(
        Verification__c verification,
        AmlMatchRecord matchRecord
    ) {
        if (verification == null || matchRecord == null) {
            return;
        }
        verification.AML_Match_Id__c = matchRecord.mlId;
        verification.AML_List_Name__c = matchRecord.listName;
        verification.AML_Customer_Name__c = matchRecord.customerName;
        verification.AML_Name_Score__c = matchRecord.nameScore;
        verification.AML_Nationality__c = matchRecord.nationality;
        verification.AML_Nationality_Score__c = matchRecord.nationalityScore;
        verification.AML_City__c = matchRecord.mlCity;
        verification.AML_Address__c = matchRecord.mlAddress;
        verification.AML_Date_of_Birth__c = matchRecord.mlDateOfBirth;
        verification.AML_Description__c = matchRecord.mlDescription;
        verification.AML_Partial_KYC_Flag__c = matchRecord.partialKycFlag == true;
    }

    private static Boolean parseBoolean(Object value) {
        if (value == null) {
            return false;
        }
        String normalizedValue = String.valueOf(value).trim().toLowerCase();
        return normalizedValue == 'true' || normalizedValue == '1' || normalizedValue == 'yes';
    }

    private static Decimal toPercentScore(Object rawScore) {
        if (rawScore == null) {
            return null;
        }
        try {
            Decimal score = Decimal.valueOf(String.valueOf(rawScore));
            return score <= 1 ? (score * 100).setScale(2) : score.setScale(2);
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, Object> firstAsMap(Map<String, Object> parent, List<String> keys) {
        for (String key : keys) {
            Map<String, Object> child = asMap(parent.get(key));
            if (child != null) {
                return child;
            }
        }
        return null;
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static String stringValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }
}