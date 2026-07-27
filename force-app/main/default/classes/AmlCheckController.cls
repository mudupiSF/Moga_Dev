/**
 * AML investigation review UI and application-level AML Check orchestration.
 * Outbound callouts are handled by AMLCheckAPIHandler via Integration Master.
 */
public with sharing class AmlCheckController implements Callable {

    private static final String ACTION_GET_PAGE_DATA = 'getPageData';
    private static final String ACTION_SUBMIT_INVESTIGATION = 'submitInvestigation';
    private static final String ACTION_CREATE_AML_INVESTIGATION_RECORDS = 'createAmlInvestigationRecords';

    private static final String TYPE_AML = 'AML';
    private static final String STATUS_CLOSED = 'Closed';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String DECISION_POSITIVE = 'Positive';
    private static final String DECISION_FALSE_POSITIVE = 'False Positive';
    private static final String ADMIN_PROFILE = 'System Administrator';
    private static final String OBJECT_APPLICANT = 'Applicant__c';
    private static final Set<String> AML_APPLICANT_TYPES = new Set<String>{
        'Borrower',
        'Co-borrower',
        'Guarantor',
        'Beneficiary'
    };
    private static final String DOC_TYPE_PAN = 'PAN';
    private static final String ADDRESS_TYPE_CURRENT = 'Current Residential Address';
    private static final String ADDRESS_TYPE_OFFICE = 'Office Address';
    private static final String ADDRESS_TYPE_PERMANENT = 'Permanent Residential Address';
    private static final Set<String> KNOWN_ADDRESS_TYPES = new Set<String>{
        ADDRESS_TYPE_CURRENT, ADDRESS_TYPE_OFFICE, ADDRESS_TYPE_PERMANENT
    };

    private static final Map<String, String> KYC_TYPE_TO_DOC_KEY = new Map<String, String>{
        'Aadhar' => 'aadhaar',
        'Voter Id' => 'voterId',
        'Driving License' => 'drivingLicense',
        'Passport' => 'passport'
    };

    private static final List<Map<String, String>> IDENTITY_DOC_DEFINITIONS = new List<Map<String, String>>{
        new Map<String, String>{ 'docKey' => 'pan', 'label' => 'PAN', 'iconName' => 'doctype:xml', 'tone' => 'orange' },
        new Map<String, String>{ 'docKey' => 'voterId', 'label' => 'Voter ID', 'iconName' => 'doctype:word', 'tone' => 'blue' },
        new Map<String, String>{ 'docKey' => 'drivingLicense', 'label' => 'Driving License', 'iconName' => 'doctype:ppt', 'tone' => 'purple' },
        new Map<String, String>{ 'docKey' => 'aadhaar', 'label' => 'Aadhaar', 'iconName' => 'doctype:image', 'tone' => 'teal' },
        new Map<String, String>{ 'docKey' => 'passport', 'label' => 'Passport', 'iconName' => 'doctype:pdf', 'tone' => 'maroon' }
    };

    public class AmlInvestigationAddress {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String iconName { get; set; }
    }

    public class AmlInvestigationDocument {
        @AuraEnabled public String docKey { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String maskedValue { get; set; }
        @AuraEnabled public Boolean hasValue { get; set; }
        @AuraEnabled public String iconName { get; set; }
        @AuraEnabled public String tone { get; set; }
    }

    public class AmlInvestigationApplicant {
        @AuraEnabled public String applicantId { get; set; }
        @AuraEnabled public String applicantName { get; set; }
        @AuraEnabled public String applicantType { get; set; }
        @AuraEnabled public String dob { get; set; }
        @AuraEnabled public String tabLabel { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public List<AmlInvestigationAddress> addresses { get; set; }
        @AuraEnabled public List<AmlInvestigationDocument> identityDocuments { get; set; }
    }

    public class AmlInvestigationMatch {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Integer serialNo { get; set; }
        @AuraEnabled public String listName { get; set; }
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public Decimal nameScore { get; set; }
        @AuraEnabled public String nationality { get; set; }
        @AuraEnabled public Decimal nationalityScore { get; set; }
        @AuraEnabled public String mlCity { get; set; }
        @AuraEnabled public String mlAddress { get; set; }
        @AuraEnabled public String mlDateOfBirth { get; set; }
        @AuraEnabled public String mlDescription { get; set; }
        @AuraEnabled public Boolean partialKycFlag { get; set; }
        @AuraEnabled public String decision { get; set; }
        @AuraEnabled public String remarks { get; set; }
    }

    public class AmlInvestigationPageData {
        @AuraEnabled public Id investigationId { get; set; }
        @AuraEnabled public Id applicationId { get; set; }
        @AuraEnabled public String investigationStatus { get; set; }
        @AuraEnabled public Boolean isClosed { get; set; }
        @AuraEnabled public Boolean canSubmit { get; set; }
        @AuraEnabled public List<AmlInvestigationMatch> verificationRows { get; set; }
        @AuraEnabled public List<AmlInvestigationApplicant> applicants { get; set; }
    }

    public class AmlInvestigationDecisionInput {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String decision { get; set; }
        @AuraEnabled public String remarks { get; set; }
    }

    private class AmlAddressWrapper {
        private String line1;
        private String line2;
        private String line3;
        private String line4;
        private String city;
        private String district;
        private String state;
        private String pinCode;
    }

    private class AmlApplicantAddressBundle {
        private Map<Id, Map<String, AmlAddressWrapper>> byApplicant =
            new Map<Id, Map<String, AmlAddressWrapper>>();
        private Map<Id, Applicant_Address__c> currentRowByApplicant =
            new Map<Id, Applicant_Address__c>();
    }

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();
        Id investigationId = resolveArgId(safeArgs, 'investigationId', 'recordId');
        try {
            if (ACTION_GET_PAGE_DATA.equalsIgnoreCase(action)) {
                AmlInvestigationPageData pageData = getInvestigationPageData(investigationId);
                return pageData == null
                    ? new Map<String, Object>()
                    : (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(pageData));
            }
            if (ACTION_SUBMIT_INVESTIGATION.equalsIgnoreCase(action)) {
                return submitInvestigation(safeArgs);
            }
            if (ACTION_CREATE_AML_INVESTIGATION_RECORDS.equalsIgnoreCase(action)) {
                return createAmlInvestigationRecords(safeArgs);
            }
            throw new CalloutException('Unknown action: ' + action);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static AmlInvestigationPageData getInvestigationPageData(Id investigationId) {
        AmlInvestigationPageData pageData = new AmlInvestigationPageData();
        pageData.verificationRows = new List<AmlInvestigationMatch>();
        pageData.applicants = new List<AmlInvestigationApplicant>();

        if (investigationId == null) {
            return pageData;
        }

        List<Investigations__c> investigations = [
            SELECT Id,
                   Status__c,
                   Application__c,
                   (SELECT Id,
                           Name,
                           Remarks__c,
                           Decision__c,
                           AML_Match_Id__c,
                           AML_List_Name__c,
                           AML_Customer_Name__c,
                           AML_Name_Score__c,
                           AML_Nationality__c,
                           AML_Nationality_Score__c,
                           AML_City__c,
                           AML_Address__c,
                           AML_Date_of_Birth__c,
                           AML_Description__c,
                           AML_Partial_KYC_Flag__c,
                           Applicant__c,
                           Applicant__r.Name,
                           Applicant__r.Applicant_Type__c,
                           Applicant__r.Company_Name__c,
                           Applicant__r.Customer_First_Name__c,
                           Applicant__r.Customer_Last_Name__c
                    FROM Verifications__r
                    ORDER BY CreatedDate ASC)
            FROM Investigations__c
            WHERE Id = :investigationId
              AND Type_of_Investigation__c = :TYPE_AML
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (investigations.isEmpty()) {
            return pageData;
        }

        Investigations__c investigation = investigations[0];
        pageData.investigationId = investigation.Id;
        pageData.applicationId = investigation.Application__c;
        pageData.investigationStatus = investigation.Status__c;
        pageData.isClosed = investigation.Status__c == STATUS_CLOSED;
        pageData.canSubmit = !pageData.isClosed && isAdminUser();

        Set<Id> verificationApplicantIds = new Set<Id>();
        for (Verification__c verification : investigation.Verifications__r) {
            if (verification.Applicant__c != null) {
                verificationApplicantIds.add(verification.Applicant__c);
            }
        }
        Map<Id, Document_CheckList__c> poiByApplicantId = getPoiIdentityDocumentsByApplicant(verificationApplicantIds);

        Integer serialNo = 1;
        for (Verification__c verification : investigation.Verifications__r) {
            AmlInvestigationMatch matchRow = buildMatchRowFromVerification(
                verification,
                serialNo++,
                poiByApplicantId
            );
            pageData.verificationRows.add(matchRow);
        }

        if (investigation.Application__c != null) {
            pageData.applicants = buildApplicantSummaries(
                investigation.Application__c,
                investigation.Verifications__r,
                pageData.investigationStatus
            );
        }

        return pageData;
    }

    private static AmlInvestigationMatch buildMatchRowFromVerification(
        Verification__c verification,
        Integer serialNo,
        Map<Id, Document_CheckList__c> poiByApplicantId
    ) {
        AmlInvestigationMatch matchRow = new AmlInvestigationMatch();
        matchRow.id = verification.Id;
        matchRow.serialNo = serialNo;
        matchRow.listName = verification.AML_List_Name__c == null ? '' : verification.AML_List_Name__c;
        matchRow.customerName = verification.AML_Customer_Name__c == null ? '' : verification.AML_Customer_Name__c;
        matchRow.nationality = verification.AML_Nationality__c == null ? '' : verification.AML_Nationality__c;
        matchRow.mlCity = verification.AML_City__c == null ? '' : verification.AML_City__c;
        matchRow.mlAddress = verification.AML_Address__c == null ? '' : verification.AML_Address__c;
        matchRow.mlDateOfBirth = verification.AML_Date_of_Birth__c == null ? '' : verification.AML_Date_of_Birth__c;
        matchRow.mlDescription = verification.AML_Description__c == null ? '' : verification.AML_Description__c;
        matchRow.nameScore = verification.AML_Name_Score__c;
        matchRow.nationalityScore = verification.AML_Nationality_Score__c;
        matchRow.partialKycFlag = verification.AML_Partial_KYC_Flag__c == true;
        matchRow.decision = verification.Decision__c;
        matchRow.remarks = verification.Remarks__c;

        if (String.isBlank(matchRow.customerName) && verification.Applicant__r != null) {
            Document_CheckList__c poiDocument = poiByApplicantId != null
                ? poiByApplicantId.get(verification.Applicant__c)
                : null;
            matchRow.customerName = toApplicantDisplayName(verification.Applicant__r, poiDocument);
        }
        if (String.isBlank(matchRow.listName)) {
            matchRow.listName = verification.Name;
        }
        return matchRow;
    }

    private static List<AmlInvestigationApplicant> buildApplicantSummaries(
        Id applicationId,
        List<Verification__c> verifications,
        String investigationStatus
    ) {
        List<AmlInvestigationApplicant> summaries = new List<AmlInvestigationApplicant>();
        Map<Id, Integer> matchCountByApplicantId = new Map<Id, Integer>();
        if (verifications != null) {
            for (Verification__c verification : verifications) {
                if (verification.Applicant__c == null) {
                    continue;
                }
                matchCountByApplicantId.put(
                    verification.Applicant__c,
                    (matchCountByApplicantId.containsKey(verification.Applicant__c)
                        ? matchCountByApplicantId.get(verification.Applicant__c)
                        : 0) + 1
                );
            }
        }

        List<Applicant__c> applicants = [
            SELECT Id,
                   Name,
                   Applicant_Type__c,
                   Company_Name__c,
                   Customer_First_Name__c,
                   Customer_Last_Name__c,
                   PAN_Number__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND In_Active_Applicant__c = false
              AND Applicant_Type__c IN :AML_APPLICANT_TYPES
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];

        if (applicants.isEmpty()) {
            return summaries;
        }

        Set<Id> applicantIds = new Set<Id>();
        for (Applicant__c applicant : applicants) {
            applicantIds.add(applicant.Id);
        }

        AmlApplicantAddressBundle addressBundle = fetchApplicantAddressBundle(applicationId);

        Map<Id, List<Document_CheckList__c>> checklistsByApplicantId = new Map<Id, List<Document_CheckList__c>>();
        for (Document_CheckList__c row : [
            SELECT Applicant__c,
                   Address_Type__c,
                   Document_Type__c,
                   PAN_No__c,
                   Applicant_KYC__r.KYC_Type__c,
                   Applicant_KYC__r.KYC_DOB__c,
                   Applicant_KYC__r.Masked_KYC_No__c,
                   Applicant_KYC__r.KYC_No__c,
                   Applicant_KYC__r.KYC_Address_Line_1__c,
                   Applicant_KYC__r.KYC_Address_Line_2__c,
                   Applicant_KYC__r.KYC_Address_Line_3__c,
                   Applicant_KYC__r.KYC_Address_Line_4__c,
                   Applicant_KYC__r.KYC_City__c,
                   Applicant_KYC__r.KYC_District__c,
                   Applicant_KYC__r.KYC_State__c,
                   Applicant_KYC__r.KYC_Pin_Code__c,
                   Applicant_Address__r.Address_Line_1__c,
                   Applicant_Address__r.Address_Line_2__c,
                   Applicant_Address__r.Address_Line_3__c,
                   Applicant_Address__r.Address_Line_4__c,
                   Applicant_Address__r.City__c,
                   Applicant_Address__r.District__c,
                   Applicant_Address__r.State__c,
                   Applicant_Address__r.PinCode__c,
                   Applicant_Address__r.Is_Current_Address_Same_As_Permanent__c,
                   Applicant_Address__r.Is_Office_Address_Same_As_Current__c
            FROM Document_CheckList__c
            WHERE Application__c = :applicationId
              AND Applicant__c IN :applicantIds
              AND Is_Active__c = true
              AND (Document_Type__c = :DOC_TYPE_PAN
                   OR Applicant_KYC__c != null
                   OR Address_Type__c IN :KNOWN_ADDRESS_TYPES)
            WITH SECURITY_ENFORCED
            ORDER BY Applicant__c, LastModifiedDate DESC
        ]) {
            if (!checklistsByApplicantId.containsKey(row.Applicant__c)) {
                checklistsByApplicantId.put(row.Applicant__c, new List<Document_CheckList__c>());
            }
            checklistsByApplicantId.get(row.Applicant__c).add(row);
        }

        applyChecklistAddressFallback(addressBundle, checklistsByApplicantId);

        Map<Id, Document_CheckList__c> poiByApplicantId = getPoiIdentityDocumentsByApplicant(applicantIds);

        Map<String, Integer> tabLabelCounts = new Map<String, Integer>();
        for (Applicant__c applicant : applicants) {
            String applicantType = applicant.Applicant_Type__c;
            String tabBaseLabel = String.isBlank(applicantType)
                ? 'Applicant'
                : (applicantType == 'Guarantor'
                    ? 'Guarantor'
                    : (applicantType == 'Co-Borrower' || applicantType == 'Co-borrower' || applicantType == 'CoBorrower'
                        ? 'Co-borrower'
                        : applicantType));
            Integer labelCount = (tabLabelCounts.containsKey(tabBaseLabel) ? tabLabelCounts.get(tabBaseLabel) : 0) + 1;
            tabLabelCounts.put(tabBaseLabel, labelCount);

            Integer matchCount = matchCountByApplicantId.containsKey(applicant.Id)
                ? matchCountByApplicantId.get(applicant.Id)
                : 0;
            String priority = matchCount >= 4 ? 'High' : (matchCount >= 1 ? 'Medium' : 'Low');

            List<Document_CheckList__c> checklistRows = checklistsByApplicantId.get(applicant.Id);
            if (checklistRows == null) {
                checklistRows = new List<Document_CheckList__c>();
            }

            Map<String, String> maskedValueByDocKey = new Map<String, String>();
            String dob = '';

            for (Document_CheckList__c row : checklistRows) {
                if (row.Applicant_KYC__r?.KYC_DOB__c != null && String.isBlank(dob)) {
                    dob = String.valueOf(row.Applicant_KYC__r.KYC_DOB__c);
                }

                if (row.Document_Type__c == DOC_TYPE_PAN) {
                    String panMasked = maskValue(row.PAN_No__c, applicant.PAN_Number__c);
                    if (String.isNotBlank(panMasked)) {
                        maskedValueByDocKey.put('pan', panMasked);
                    }
                    continue;
                }

                if (row.Applicant_KYC__r == null) {
                    continue;
                }

                String docKey = null;
                String kycType = row.Applicant_KYC__r.KYC_Type__c;
                if (String.isNotBlank(kycType) && KYC_TYPE_TO_DOC_KEY.containsKey(kycType)) {
                    docKey = KYC_TYPE_TO_DOC_KEY.get(kycType);
                } else if (String.isNotBlank(row.Document_Type__c)) {
                    String normalizedType = row.Document_Type__c.trim();
                    if ('Aadhaar Card'.equalsIgnoreCase(normalizedType)
                        || normalizedType.containsIgnoreCase('Aadhaar')
                        || normalizedType.containsIgnoreCase('Aadhar')) {
                        docKey = 'aadhaar';
                    } else if (normalizedType.containsIgnoreCase('Voter')) {
                        docKey = 'voterId';
                    } else if (normalizedType.containsIgnoreCase('Driving')) {
                        docKey = 'drivingLicense';
                    } else if (normalizedType.containsIgnoreCase('Passport')) {
                        docKey = 'passport';
                    }
                }

                if (String.isBlank(docKey) || maskedValueByDocKey.containsKey(docKey)) {
                    continue;
                }
                String maskedValue = maskValue(
                    row.Applicant_KYC__r.Masked_KYC_No__c,
                    row.Applicant_KYC__r.KYC_No__c
                );
                if (String.isNotBlank(maskedValue)) {
                    maskedValueByDocKey.put(docKey, maskedValue);
                }
            }

            if (!maskedValueByDocKey.containsKey('pan')) {
                String panMasked = maskValue(null, applicant.PAN_Number__c);
                if (String.isNotBlank(panMasked)) {
                    maskedValueByDocKey.put('pan', panMasked);
                }
            }

            Map<String, AmlAddressWrapper> applicantAddresses = addressBundle.byApplicant.containsKey(applicant.Id)
                ? addressBundle.byApplicant.get(applicant.Id)
                : new Map<String, AmlAddressWrapper>();
            String currentAddress = toDisplayAddress(applicantAddresses.get(ADDRESS_TYPE_CURRENT));
            String officeAddress = toDisplayAddress(applicantAddresses.get(ADDRESS_TYPE_OFFICE));
            String permanentAddress = toDisplayAddress(applicantAddresses.get(ADDRESS_TYPE_PERMANENT));

            AmlInvestigationApplicant summary = new AmlInvestigationApplicant();
            summary.applicantId = applicant.Id;
            summary.applicantName = toApplicantDisplayName(applicant, poiByApplicantId.get(applicant.Id));
            summary.applicantType = applicant.Applicant_Type__c;
            summary.dob = dob;
            summary.tabLabel = labelCount > 1 ? tabBaseLabel + ' ' + labelCount : tabBaseLabel;
            summary.priority = priority;
            summary.status = String.isNotBlank(investigationStatus) ? investigationStatus : '';

            AmlInvestigationAddress residential = new AmlInvestigationAddress();
            residential.label = 'Residential Address';
            residential.value = currentAddress;
            residential.iconName = 'utility:home';
            AmlInvestigationAddress office = new AmlInvestigationAddress();
            office.label = 'Office Address';
            office.value = officeAddress;
            AmlInvestigationAddress permanent = new AmlInvestigationAddress();
            permanent.label = 'Permanent Address';
            permanent.value = permanentAddress;
            permanent.iconName = 'utility:company';
            summary.addresses = new List<AmlInvestigationAddress>{ residential, office, permanent };

            summary.identityDocuments = new List<AmlInvestigationDocument>();
            for (Map<String, String> definition : IDENTITY_DOC_DEFINITIONS) {
                String maskedValue = maskedValueByDocKey.get(definition.get('docKey'));
                AmlInvestigationDocument document = new AmlInvestigationDocument();
                document.docKey = definition.get('docKey');
                document.label = definition.get('label');
                document.maskedValue = maskedValue;
                document.hasValue = String.isNotBlank(maskedValue);
                document.iconName = definition.get('iconName');
                document.tone = definition.get('tone');
                summary.identityDocuments.add(document);
            }

            summaries.add(summary);
        }
        return summaries;
    }

    private static Map<String, Object> submitInvestigation(Map<String, Object> args) {
        Id investigationId = resolveArgId(args, 'investigationId', 'recordId');
        if (investigationId == null) {
            throw new AuraHandledException('Investigation id is required.');
        }
        if (!isAdminUser()) {
            throw new AuraHandledException('Only admin users can submit AML Check at this time.');
        }

        Map<Id, AmlInvestigationDecisionInput> inputById = new Map<Id, AmlInvestigationDecisionInput>();
        if (args != null && args.containsKey('verificationInputs') && args.get('verificationInputs') != null) {
            Object rawInputs = args.get('verificationInputs');
            if (rawInputs instanceof List<AmlInvestigationDecisionInput>) {
                for (AmlInvestigationDecisionInput input : (List<AmlInvestigationDecisionInput>) rawInputs) {
                    if (input?.id != null) {
                        inputById.put(input.id, input);
                    }
                }
            } else {
                List<Object> parsedRows = (List<Object>) JSON.deserializeUntyped(JSON.serialize(rawInputs));
                for (Object row : parsedRows) {
                    if (!(row instanceof Map<String, Object>)) {
                        continue;
                    }
                    Map<String, Object> rowMap = (Map<String, Object>) row;
                    AmlInvestigationDecisionInput input = new AmlInvestigationDecisionInput();
                    if (rowMap.get('id') != null) {
                        input.id = (Id) String.valueOf(rowMap.get('id'));
                    }
                    input.decision = rowMap.get('decision') != null ? String.valueOf(rowMap.get('decision')) : null;
                    input.remarks = rowMap.get('remarks') != null ? String.valueOf(rowMap.get('remarks')) : null;
                    if (input.id != null) {
                        inputById.put(input.id, input);
                    }
                }
            }
        }

        List<Verification__c> updates = new List<Verification__c>();
        for (Verification__c verification : [
            SELECT Id
            FROM Verification__c
            WHERE Investigations__c = :investigationId
            WITH SECURITY_ENFORCED
        ]) {
            AmlInvestigationDecisionInput input = inputById.get(verification.Id);
            if (input == null) {
                continue;
            }
            Verification__c updateRow = new Verification__c(Id = verification.Id);
            if (input.decision == DECISION_FALSE_POSITIVE) {
                updateRow.Decision__c = DECISION_FALSE_POSITIVE;
            } else if (input.decision == DECISION_POSITIVE) {
                updateRow.Decision__c = DECISION_POSITIVE;
            }
            updateRow.Remarks__c = input.remarks;
            updateRow.Status__c = STATUS_COMPLETED;
            updates.add(updateRow);
        }

        if (!updates.isEmpty()) {
            update updates;
        }

        update new Investigations__c(Id = investigationId, Status__c = STATUS_CLOSED);
        return new Map<String, Object>{
            'isSuccess' => true,
            'message' => 'AML Check submitted successfully.'
        };
    }

    private static Map<String, Object> createAmlInvestigationRecords(Map<String, Object> args) {
        Id applicationId = resolveArgId(args, 'applicationId', 'recordId');
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'AML Check could not be completed.',
            'matchCount' => 0,
            'investigationId' => null,
            'applicantCount' => 0
        };

        if (applicationId == null) {
            result.put('message', 'Application id is required.');
            return result;
        }

        List<Applicant__c> applicants = [
            SELECT Id, Applicant_Type__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND In_Active_Applicant__c = false
              AND Applicant_Type__c IN :AML_APPLICANT_TYPES
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];

        if (applicants.isEmpty()) {
            result.put('message', 'No active applicants found for AML Check.');
            return result;
        }

        AMLCheckAPIHandler.clearSessionCache();
        List<String> errorMessages = new List<String>();

        for (Applicant__c applicant : applicants) {
            String applicantLabel = String.isNotBlank(applicant.Applicant_Type__c)
                ? applicant.Applicant_Type__c
                : 'Applicant';
            try {
                ApplicationUtility.IntegrationResponseWrapper integrationResult =
                    ApplicationUtility.invokeIntegrationSync(
                        AMLCheckAPIHandler.INTEGRATION_KEY,
                        applicant.Id,
                        OBJECT_APPLICANT
                    );

                if (integrationResult == null || integrationResult.hasValidationError) {
                    String errorMessage = integrationResult != null && String.isNotBlank(integrationResult.displayMessage)
                        ? integrationResult.displayMessage
                        : (integrationResult != null ? integrationResult.errorMessage : 'AML Check failed.');
                    errorMessages.add(applicantLabel + ': ' + errorMessage);
                }
            } catch (Exception ex) {
                errorMessages.add(applicantLabel + ': ' + ex.getMessage());
            }
        }

        Integer totalMatches = AMLCheckAPIHandler.getSessionTotalMatchCount(applicationId);
        result.put('applicantCount', applicants.size());
        result.put('matchCount', totalMatches);
        result.put('investigationId', AMLCheckAPIHandler.getSessionInvestigationId(applicationId));

        if (!errorMessages.isEmpty()) {
            result.put('message', String.join(errorMessages, ' '));
            return result;
        }

        result.put('isSuccess', true);
        result.put(
            'message',
            totalMatches > 0
                ? 'AML Check completed with ' + totalMatches + ' match(es).'
                : 'AML Check completed with no matches.'
        );
        return result;
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

    private static String toApplicantDisplayName(Applicant__c applicant) {
        return toApplicantDisplayName(applicant, null);
    }

    private static String toApplicantDisplayName(
        Applicant__c applicant,
        Document_CheckList__c poiDocument
    ) {
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
        List<String> nameParts = new List<String>();
        if (String.isNotBlank(applicant.Customer_First_Name__c)) {
            nameParts.add(applicant.Customer_First_Name__c);
        }
        if (String.isNotBlank(applicant.Customer_Last_Name__c)) {
            nameParts.add(applicant.Customer_Last_Name__c);
        }
        return !nameParts.isEmpty() ? String.join(nameParts, ' ') : applicant.Name;
    }

    private static AmlApplicantAddressBundle fetchApplicantAddressBundle(Id applicationId) {
        AmlApplicantAddressBundle bundle = new AmlApplicantAddressBundle();
        if (applicationId == null) {
            return bundle;
        }

        for (Applicant_Address__c row : [
            SELECT Applicant__c,
                   Address_Type__c,
                   Address_Line_1__c,
                   Address_Line_2__c,
                   Address_Line_3__c,
                   Address_Line_4__c,
                   City__c,
                   District__c,
                   State__c,
                   PinCode__c,
                   Is_Current_Address_Same_As_Permanent__c,
                   Is_Office_Address_Same_As_Current__c
            FROM Applicant_Address__c
            WHERE Applicant__r.Application__c = :applicationId
              AND Applicant__r.In_Active_Applicant__c = false
              AND Address_Type__c IN :KNOWN_ADDRESS_TYPES
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC
        ]) {
            if (row == null || row.Applicant__c == null || String.isBlank(row.Address_Type__c)) {
                continue;
            }
            Id rowApplicantId = row.Applicant__c;
            if (!bundle.byApplicant.containsKey(rowApplicantId)) {
                bundle.byApplicant.put(rowApplicantId, new Map<String, AmlAddressWrapper>());
            }
            if (ADDRESS_TYPE_CURRENT.equals(row.Address_Type__c)
                    && !bundle.currentRowByApplicant.containsKey(rowApplicantId)) {
                bundle.currentRowByApplicant.put(rowApplicantId, row);
            }

            Map<String, AmlAddressWrapper> applicantAddresses = bundle.byApplicant.get(rowApplicantId);
            if (applicantAddresses.containsKey(row.Address_Type__c)) {
                continue;
            }
            AmlAddressWrapper address = buildAddressFromApplicantAddress(row);
            if (address != null) {
                applicantAddresses.put(row.Address_Type__c, address);
            }
        }

        applySameAsAddressRules(bundle);
        return bundle;
    }

    private static void applyChecklistAddressFallback(
        AmlApplicantAddressBundle bundle,
        Map<Id, List<Document_CheckList__c>> checklistsByApplicantId
    ) {
        if (bundle == null || checklistsByApplicantId == null) {
            return;
        }

        for (Id applicantId : checklistsByApplicantId.keySet()) {
            for (Document_CheckList__c row : checklistsByApplicantId.get(applicantId)) {
                if (row == null || String.isBlank(row.Address_Type__c)) {
                    continue;
                }
                if (!KNOWN_ADDRESS_TYPES.contains(row.Address_Type__c)) {
                    continue;
                }

                if (ADDRESS_TYPE_CURRENT.equals(row.Address_Type__c)
                        && row.Applicant_Address__r != null
                        && !bundle.currentRowByApplicant.containsKey(applicantId)) {
                    bundle.currentRowByApplicant.put(applicantId, row.Applicant_Address__r);
                }

                if (!bundle.byApplicant.containsKey(applicantId)) {
                    bundle.byApplicant.put(applicantId, new Map<String, AmlAddressWrapper>());
                }
                Map<String, AmlAddressWrapper> applicantAddresses = bundle.byApplicant.get(applicantId);
                if (hasAddressContent(applicantAddresses.get(row.Address_Type__c))) {
                    continue;
                }

                AmlAddressWrapper address = buildAddressFromApplicantAddress(row.Applicant_Address__r);
                if (address == null) {
                    address = buildAddressFromKyc(row.Applicant_KYC__r);
                }
                if (address != null) {
                    applicantAddresses.put(row.Address_Type__c, address);
                }
            }
        }

        applySameAsAddressRules(bundle);
    }

    private static void applySameAsAddressRules(AmlApplicantAddressBundle bundle) {
        for (Id rowApplicantId : bundle.currentRowByApplicant.keySet()) {
            Applicant_Address__c currentRow = bundle.currentRowByApplicant.get(rowApplicantId);
            Map<String, AmlAddressWrapper> applicantAddresses = bundle.byApplicant.get(rowApplicantId);
            if (applicantAddresses == null) {
                applicantAddresses = new Map<String, AmlAddressWrapper>();
                bundle.byApplicant.put(rowApplicantId, applicantAddresses);
            }
            AmlAddressWrapper currentAddress = applicantAddresses.get(ADDRESS_TYPE_CURRENT);
            if (!hasAddressContent(currentAddress)) {
                continue;
            }
            if (isSameAsPermanent(currentRow) && !applicantAddresses.containsKey(ADDRESS_TYPE_PERMANENT)) {
                applicantAddresses.put(ADDRESS_TYPE_PERMANENT, copyAddress(currentAddress));
            }
            if (isSameAsCurrent(currentRow) && !applicantAddresses.containsKey(ADDRESS_TYPE_OFFICE)) {
                applicantAddresses.put(ADDRESS_TYPE_OFFICE, copyAddress(currentAddress));
            }
        }
    }

    private static Boolean isSameAsPermanent(Applicant_Address__c currentRow) {
        return currentRow != null
            && 'Yes'.equalsIgnoreCase(currentRow.Is_Current_Address_Same_As_Permanent__c);
    }

    private static Boolean isSameAsCurrent(Applicant_Address__c currentRow) {
        return currentRow != null
            && 'Yes'.equalsIgnoreCase(currentRow.Is_Office_Address_Same_As_Current__c);
    }

    private static AmlAddressWrapper copyAddress(AmlAddressWrapper source) {
        if (source == null) {
            return null;
        }
        AmlAddressWrapper copy = new AmlAddressWrapper();
        copy.line1 = source.line1;
        copy.line2 = source.line2;
        copy.line3 = source.line3;
        copy.line4 = source.line4;
        copy.city = source.city;
        copy.district = source.district;
        copy.state = source.state;
        copy.pinCode = source.pinCode;
        return copy;
    }

    private static AmlAddressWrapper buildAddressFromApplicantAddress(Applicant_Address__c row) {
        if (row == null) {
            return null;
        }
        AmlAddressWrapper address = new AmlAddressWrapper();
        address.line1 = row.Address_Line_1__c;
        address.line2 = row.Address_Line_2__c;
        address.line3 = row.Address_Line_3__c;
        address.line4 = row.Address_Line_4__c;
        address.city = row.City__c;
        address.district = row.District__c;
        address.state = row.State__c;
        address.pinCode = row.PinCode__c;
        return hasAddressContent(address) ? address : null;
    }

    private static AmlAddressWrapper buildAddressFromKyc(Applicant_KYC__c kyc) {
        if (kyc == null) {
            return null;
        }
        AmlAddressWrapper address = new AmlAddressWrapper();
        address.line1 = kyc.KYC_Address_Line_1__c;
        address.line2 = kyc.KYC_Address_Line_2__c;
        address.line3 = kyc.KYC_Address_Line_3__c;
        address.line4 = kyc.KYC_Address_Line_4__c;
        address.city = kyc.KYC_City__c;
        address.district = kyc.KYC_District__c;
        address.state = kyc.KYC_State__c;
        address.pinCode = kyc.KYC_Pin_Code__c;
        return hasAddressContent(address) ? address : null;
    }

    private static Boolean hasAddressContent(AmlAddressWrapper address) {
        if (address == null) {
            return false;
        }
        for (String value : new List<String>{
            address.line1,
            address.line2,
            address.line3,
            address.line4,
            address.city,
            address.district,
            address.state,
            address.pinCode
        }) {
            if (String.isNotBlank(value)) {
                return true;
            }
        }
        return false;
    }

    private static String toDisplayAddress(AmlAddressWrapper address) {
        if (!hasAddressContent(address)) {
            return '';
        }
        List<String> parts = new List<String>();
        for (String value : new List<String>{
            address.line1,
            address.line2,
            address.line3,
            address.line4,
            address.city,
            address.district,
            address.state,
            address.pinCode
        }) {
            if (String.isNotBlank(value)) {
                parts.add(value.trim());
            }
        }
        return String.join(parts, ' , ');
    }

    private static String maskValue(String preferredMaskedValue, String rawValue) {
        if (String.isNotBlank(preferredMaskedValue)) {
            return preferredMaskedValue;
        }
        String raw = rawValue == null ? '' : String.valueOf(rawValue).replaceAll('\\s', '');
        if (String.isBlank(raw)) {
            return '';
        }
        Integer keep = Math.min(4, raw.length());
        Integer maskedLen = Math.max(0, raw.length() - keep);
        String maskedPrefix = '';
        for (Integer i = 0; i < maskedLen; i++) {
            maskedPrefix += '*';
        }
        return maskedPrefix + raw.right(keep);
    }

    private static Boolean isAdminUser() {
        return [
            SELECT Name
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            WITH SECURITY_ENFORCED
            LIMIT 1
        ].Name == ADMIN_PROFILE;
    }

    private static Id resolveArgId(Map<String, Object> args, String primaryKey, String fallbackKey) {
        if (args == null) {
            return null;
        }
        for (String key : new List<String>{ primaryKey, fallbackKey }) {
            if (args.containsKey(key) && args.get(key) != null) {
                return (Id) String.valueOf(args.get(key));
            }
        }
        return null;
    }
}