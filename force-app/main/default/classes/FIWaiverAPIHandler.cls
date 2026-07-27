/**
 * Integration Master handler for FI Waiver.
 * Registered on Integration_Master__c.Name = FI Waiver (Apex_Class_Name__c = FIWaiverAPIHandler).
 *
 * processResponse stores the normalised fiDetails payload in a transaction-scoped cache so
 * FIInvestigationController.createFiInvestigations can create FI records in the same Apex
 * request (see FIWaiverAPIController.runFiWaiverOfferNextFlow).
 */
public with sharing class FIWaiverAPIHandler implements IIntegrationHandler {

    public static final String INTEGRATION_KEY = 'FI Waiver';

    public static final String FI_MODE_INDIVIDUAL = 'INDIVIDUAL';
    public static final String FI_MODE_PV_NI = 'PV_NI';
    public static final String FI_MODE_CV_NI = 'CV_NI';

    /** Mocking_Service_Response__c payload for Integration_Master__c when mocking is enabled. */
    public static final String STUB_MOCKING_SERVICE_RESPONSE_JSON =
        '{"isSuccess":true,"success":true,"message":"FI Waiver integration stub passed",' +
        '"statusCode":200,"data":{"fiDetails":[{"ApplicantType":"Borrower","Decision":[' +
        '{"fiType":"C","fiStatus":"Not Waived"},' +
        '{"fiType":"O","fiStatus":"Not Waived"},' +
        '{"fiType":"P","fiStatus":"Not Waived"}]}]}}';

    private static final String WAIVER_STATUS_NOT_WAIVED = 'Not Waived';
    private static final String WAIVER_STATUS_WAIVED = 'Waived';
    private static final String WAIVER_APPLICANT_KEY_BORROWER = 'Borrower';
    private static final String WAIVER_FI_TYPE_CODE_CURRENT = 'C';
    private static final String WAIVER_FI_TYPE_CODE_OFFICE = 'O';
    private static final String WAIVER_FI_TYPE_CODE_PERMANENT = 'P';
    private static final String WAIVER_FI_TYPE_CODE_REGISTERED = 'R';
    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';
    private static final String APPLICANT_TYPE_CO_BORROWER = 'Co-borrower';
    private static final String APPLICANT_TYPE_GUARANTOR = 'Guarantor';
    private static final String APPLICANT_TYPE_BENEFICIARY = 'Beneficiary';
    private static final String ADDR_REGISTERED = 'Registered Address';

    private static Id currentApplicationId;
    private static Map<Id, Map<String, Object>> waiverPayloadByApplicationId =
        new Map<Id, Map<String, Object>>();
    private static Map<Id, String> fiCreationModeByApplicationId = new Map<Id, String>();

    @TestVisible
    private static void clearSessionCache() {
        currentApplicationId = null;
        waiverPayloadByApplicationId.clear();
        fiCreationModeByApplicationId.clear();
    }

    public static Map<String, Object> consumeWaiverPayload(Id applicationId) {
        return waiverPayloadByApplicationId.remove(applicationId);
    }

    public static String consumeFiCreationMode(Id applicationId) {
        return fiCreationModeByApplicationId.remove(applicationId);
    }

    /**
     * CAM FI Waiver grid — mirrors buildNiFiDecisionsForApplicant / buildIndividualFiDecisions.
     */
    public static Map<String, String> resolveFiWaiverDisplayForApplicant(
            Applicant__c applicant,
            Applicant_Address__c currentAddressRow,
            Applicant_Address__c registeredAddressRow) {
        if (applicant != null && GenericUtility.isNonIndividualApplicationType(applicant.Type__c)) {
            Boolean officeSameAsRegistered = isOfficeSameAsRegistered(registeredAddressRow);
            return new Map<String, String>{
                'currentAddressDisplay' => 'Waived',
                'permanentAddressDisplay' => officeSameAsRegistered ? 'Waived' : 'Not Waived',
                'officeAddressDisplay' => 'Not Waived'
            };
        }

        return new Map<String, String>{
            'currentAddressDisplay' => 'Not Waived',
            'permanentAddressDisplay' => isSameAsPermanent(currentAddressRow)
                ? 'Waived'
                : 'Not Waived',
            'officeAddressDisplay' => isSameAsCurrent(currentAddressRow)
                ? 'Waived'
                : 'Not Waived'
        };
    }

    public static Map<Id, Applicant_Address__c> loadCurrentAddressRowsForApplicants(Set<Id> applicantIds) {
        Map<Id, Applicant_Address__c> currentAddressByApplicant = new Map<Id, Applicant_Address__c>();
        if (applicantIds == null || applicantIds.isEmpty()) {
            return currentAddressByApplicant;
        }
        for (Applicant_Address__c row : [
            SELECT Applicant__c,
                   Is_Current_Address_Same_As_Permanent__c,
                   Is_Office_Address_Same_As_Current__c
            FROM Applicant_Address__c
            WHERE Applicant__c IN :applicantIds
              AND Address_Type__c = 'Current Residential Address'
        ]) {
            if (!currentAddressByApplicant.containsKey(row.Applicant__c)) {
                currentAddressByApplicant.put(row.Applicant__c, row);
            }
        }
        return currentAddressByApplicant;
    }

    public static Map<Id, Applicant_Address__c> loadRegisteredAddressRowsForApplicants(Set<Id> applicantIds) {
        Map<Id, Applicant_Address__c> registeredAddressByApplicant = new Map<Id, Applicant_Address__c>();
        if (applicantIds == null || applicantIds.isEmpty()) {
            return registeredAddressByApplicant;
        }
        for (Applicant_Address__c row : [
            SELECT Applicant__c,
                   Is_Office_Address_Same_As_Registered__c
            FROM Applicant_Address__c
            WHERE Applicant__c IN :applicantIds
              AND Address_Type__c = :ADDR_REGISTERED
        ]) {
            if (!registeredAddressByApplicant.containsKey(row.Applicant__c)) {
                registeredAddressByApplicant.put(row.Applicant__c, row);
            }
        }
        return registeredAddressByApplicant;
    }

    public static Set<Id> resolveNiFiEligibleApplicantIds(Id applicationId) {
        if (applicationId == null) {
            return null;
        }
        String mode = resolveFiCreationMode(applicationId);
        if (!FI_MODE_PV_NI.equals(mode) && !FI_MODE_CV_NI.equals(mode)) {
            return null;
        }
        Boolean includePrimaryBeneficiary = FI_MODE_CV_NI.equals(mode);
        List<Applicant__c> applicants = [
            SELECT Id, Applicant_Type__c, Type__c, Beneficiary_Owner__c, CreatedDate
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND In_Active_Applicant__c = false
            ORDER BY Applicant_Type__c ASC, CreatedDate ASC
        ];
        Set<Id> eligibleIds = new Set<Id>();
        for (Applicant__c applicant : getNiFiEligibleApplicants(applicants, includePrimaryBeneficiary)) {
            eligibleIds.add(applicant.Id);
        }
        return eligibleIds;
    }

    public static String resolveFiCreationMode(Id applicationId) {
        if (applicationId == null) {
            return FI_MODE_INDIVIDUAL;
        }

        List<Application__c> applications = [
            SELECT Product__c, Sub_Product__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return FI_MODE_INDIVIDUAL;
        }

        List<Applicant__c> borrowers = [
            SELECT Type__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND Applicant_Type__c = :WAIVER_APPLICANT_KEY_BORROWER
              AND In_Active_Applicant__c = false
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (borrowers.isEmpty()
                || !GenericUtility.isNonIndividualApplicationType(borrowers[0].Type__c)) {
            return FI_MODE_INDIVIDUAL;
        }

        if (isPassengerVehicleProduct(applications[0])) {
            return FI_MODE_PV_NI;
        }
        if (isCommercialVehicleProduct(applications[0])) {
            return FI_MODE_CV_NI;
        }
        return FI_MODE_INDIVIDUAL;
    }

    /**
     * Seeds waiver cache when FI Waiver already succeeded and refresh is blocked.
     */
    public static void seedWaiverPayloadForApplication(Id applicationId) {
        if (applicationId == null) {
            return;
        }
        String mode = resolveFiCreationMode(applicationId);
        cacheFiCreationMode(applicationId, mode);
        waiverPayloadByApplicationId.put(
            applicationId,
            buildStubWaiverPayloadForMode(applicationId, mode)
        );
    }

    public List<SObject> prepareRecordForIntegration(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<SObject>();
        }
        return [
            SELECT Id, Application__c
            FROM Applicant__c
            WHERE Id IN :recordIds
              AND Applicant_Type__c = :WAIVER_APPLICANT_KEY_BORROWER
              AND In_Active_Applicant__c = false
        ];
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> validateInputData(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper wrapper =
            new ApplicationUtility.IntegrationResponseWrapper();
        wrapper.hasValidationError = false;

        if (recordList == null || recordList.isEmpty()) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage = 'Borrower applicant record is required.';
            wrapper.displayMessage = wrapper.errorMessage;
            return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
        }

        Applicant__c borrower = (Applicant__c) recordList[0];
        if (borrower.Application__c == null) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage = 'Application context is missing for FI Waiver.';
            wrapper.displayMessage = wrapper.errorMessage;
            return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
        }

        wrapper.recordId = borrower.Application__c;
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant__c borrower = (Applicant__c) recordList[0];
        currentApplicationId = borrower.Application__c;

        ApplicationUtility.IntegrationRequestWrapper wrapper =
            new ApplicationUtility.IntegrationRequestWrapper();
        wrapper.requestBody = JSON.serialize(buildStubWaiverPayload(borrower.Application__c));
        wrapper.method = 'POST';

        return new List<ApplicationUtility.IntegrationRequestWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result =
            new ApplicationUtility.IntegrationResponseWrapper();

        IntegrationUtility.ResponseWrapper wrapper =
            (IntegrationUtility.ResponseWrapper) recordList[0];
        Integration_Checklist__c checklist = (Integration_Checklist__c) wrapper.checklistRecord;
        Id applicationId = currentApplicationId;

        if (applicationId == null && checklist != null && checklist.Applicant__c != null) {
            List<Applicant__c> applicants = [
                SELECT Application__c
                FROM Applicant__c
                WHERE Id = :checklist.Applicant__c
                LIMIT 1
            ];
            if (!applicants.isEmpty()) {
                applicationId = applicants[0].Application__c;
            }
        }

        if (applicationId == null) {
            result.hasValidationError = true;
            result.displayMessage = 'Application context is missing for FI Waiver.';
            result.errorMessage = result.displayMessage;
            return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
        }

        Map<String, Object> waiverPayload = extractWaiverPayload(wrapper.response, applicationId);
        if (!hasFiDetails(waiverPayload)) {
        if (checklist != null) {
            if (checklist.Applicant__c == null) {
                Id borrowerApplicantId = getBorrowerApplicantId(applicationId);
                if (borrowerApplicantId != null) {
                    checklist.Applicant__c = borrowerApplicantId;
                }
            }
            checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                checklist.Functional_Failure_Reason__c = 'FI Waiver returned no fiDetails.';
                update checklist;
            }
            result.hasValidationError = true;
            result.displayMessage = 'FI Waiver returned no fiDetails.';
            result.errorMessage = result.displayMessage;
            return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
        }

        cacheFiCreationMode(applicationId, resolveFiCreationMode(applicationId));
        waiverPayloadByApplicationId.put(applicationId, waiverPayload);

        if (checklist != null) {
            if (checklist.Applicant__c == null) {
                Id borrowerApplicantId = getBorrowerApplicantId(applicationId);
                if (borrowerApplicantId != null) {
                    checklist.Applicant__c = borrowerApplicantId;
                }
            }
            checklist.Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            update checklist;
        }

        result.hasValidationError = false;
        result.displayMessage = 'FI Waiver completed successfully.';
        result.recordId = applicationId;
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
    }

    private static void cacheFiCreationMode(Id applicationId, String mode) {
        if (applicationId != null && String.isNotBlank(mode)) {
            fiCreationModeByApplicationId.put(applicationId, mode);
        }
    }

    private static Map<String, Object> extractWaiverPayload(String rawResponse, Id applicationId) {
        if (String.isNotBlank(rawResponse)) {
            try {
                Object parsed = JSON.deserializeUntyped(rawResponse);
                Map<String, Object> payload = coerceWaiverPayload(parsed);
                if (hasFiDetails(payload)) {
                    return payload;
                }
            } catch (Exception ex) {
                // Fall through to stub payload for mock / transitional integrations.
            }
        }
        return buildStubWaiverPayload(applicationId);
    }

    private static Boolean hasFiDetails(Map<String, Object> payload) {
        if (payload == null || payload.isEmpty() || !payload.containsKey('fiDetails')) {
            return false;
        }
        Object rawFiDetails = payload.get('fiDetails');
        return rawFiDetails instanceof List<Object> && !((List<Object>) rawFiDetails).isEmpty();
    }

    private static Map<String, Object> coerceWaiverPayload(Object parsed) {
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> root = (Map<String, Object>) parsed;
            if (root.containsKey('data') && root.get('data') instanceof Map<String, Object>) {
                return (Map<String, Object>) root.get('data');
            }
            if (root.containsKey('response') && root.get('response') instanceof Map<String, Object>) {
                return (Map<String, Object>) root.get('response');
            }
            if (root.containsKey('fiDetails')) {
                return root;
            }
        }
        return null;
    }

    @TestVisible
    private static Map<String, Object> buildStubWaiverPayload(Id applicationId) {
        String mode = resolveFiCreationMode(applicationId);
        cacheFiCreationMode(applicationId, mode);
        return buildStubWaiverPayloadForMode(applicationId, mode);
    }

    private static Map<String, Object> buildStubWaiverPayloadForMode(Id applicationId, String mode) {
        if (FI_MODE_PV_NI.equals(mode)) {
            return buildPvNiStubWaiverPayload(applicationId);
        }
        if (FI_MODE_CV_NI.equals(mode)) {
            return buildCvNiStubWaiverPayload(applicationId);
        }
        return buildIndividualStubWaiverPayload(applicationId);
    }

    /** Original Individual stub — unchanged payload shape and rules. */
    @TestVisible
    private static Map<String, Object> buildIndividualStubWaiverPayload(Id applicationId) {
        List<Map<String, Object>> fiDetails = new List<Map<String, Object>>();
        Map<Id, Applicant_Address__c> currentAddressByApplicant = loadCurrentAddressRows(applicationId);

        for (Applicant__c applicant : [
            SELECT Id, Applicant_Type__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND In_Active_Applicant__c = false
            ORDER BY Applicant_Type__c ASC, CreatedDate ASC
        ]) {
            Applicant_Address__c currentAddressRow = currentAddressByApplicant.get(applicant.Id);
            fiDetails.add(new Map<String, Object>{
                'ApplicantType' => resolveWaiverApplicantType(applicant.Applicant_Type__c),
                'Decision' => buildIndividualFiDecisions(currentAddressRow)
            });
        }

        return new Map<String, Object>{ 'fiDetails' => fiDetails };
    }

    /** PV NI: Borrower + all Guarantors/Co-Borrowers. */
    @TestVisible
    private static Map<String, Object> buildPvNiStubWaiverPayload(Id applicationId) {
        return buildNiStubWaiverPayload(applicationId, false);
    }

    /** CV NI: Borrower + all Guarantors/Co-Borrowers + primary Beneficiary. */
    @TestVisible
    private static Map<String, Object> buildCvNiStubWaiverPayload(Id applicationId) {
        return buildNiStubWaiverPayload(applicationId, true);
    }

    private static Map<String, Object> buildNiStubWaiverPayload(
            Id applicationId,
            Boolean includePrimaryBeneficiary) {
        List<Map<String, Object>> fiDetails = new List<Map<String, Object>>();
        List<Applicant__c> applicants = [
            SELECT Id, Applicant_Type__c, Type__c, Beneficiary_Owner__c, CreatedDate
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND In_Active_Applicant__c = false
            ORDER BY Applicant_Type__c ASC, CreatedDate ASC
        ];

        Map<Id, Applicant_Address__c> currentAddressByApplicant = loadCurrentAddressRows(applicationId);
        Map<Id, Applicant_Address__c> registeredAddressByApplicant = loadRegisteredAddressRows(applicationId);
        for (Applicant__c applicant : getNiFiEligibleApplicants(applicants, includePrimaryBeneficiary)) {
            Applicant_Address__c currentAddressRow = currentAddressByApplicant.get(applicant.Id);
            Applicant_Address__c registeredAddressRow = registeredAddressByApplicant.get(applicant.Id);
            fiDetails.add(new Map<String, Object>{
                'applicantId' => String.valueOf(applicant.Id),
                'ApplicantType' => resolveWaiverApplicantType(applicant.Applicant_Type__c),
                'Decision' => buildNiFiDecisionsForApplicant(
                    applicant,
                    currentAddressRow,
                    registeredAddressRow
                )
            });
        }

        return new Map<String, Object>{ 'fiDetails' => fiDetails };
    }

    private static List<Applicant__c> getNiFiEligibleApplicants(
            List<Applicant__c> applicants,
            Boolean includePrimaryBeneficiary) {
        List<Applicant__c> eligible = new List<Applicant__c>();
        if (applicants == null || applicants.isEmpty()) {
            return eligible;
        }

        Applicant__c primaryBeneficiary = null;
        Integer beneficiaryIndex = 0;

        for (Applicant__c applicant : applicants) {
            String applicantType = applicant.Applicant_Type__c;
            if (APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicantType)) {
                eligible.add(applicant);
            } else if (isGuarantorOrCoBorrower(applicantType)) {
                eligible.add(applicant);
            } else if (APPLICANT_TYPE_BENEFICIARY.equalsIgnoreCase(applicantType)) {
                if (includePrimaryBeneficiary && isPrimaryBeneficiary(applicant, beneficiaryIndex)) {
                    primaryBeneficiary = applicant;
                }
                beneficiaryIndex++;
            }
        }

        if (primaryBeneficiary != null) {
            eligible.add(primaryBeneficiary);
        }
        return eligible;
    }

    private static Boolean isGuarantorOrCoBorrower(String applicantType) {
        return APPLICANT_TYPE_GUARANTOR.equalsIgnoreCase(applicantType)
            || APPLICANT_TYPE_CO_BORROWER.equalsIgnoreCase(applicantType)
            || 'Co Borrower'.equalsIgnoreCase(applicantType)
            || 'Co-Borrower'.equalsIgnoreCase(applicantType);
    }

    private static Boolean isPrimaryBeneficiary(Applicant__c beneficiary, Integer beneficiaryIndex) {
        if (beneficiary == null) {
            return false;
        }
        if (beneficiary.Beneficiary_Owner__c == true) {
            return true;
        }
        return beneficiaryIndex == 0;
    }

    private static String resolveWaiverApplicantType(String applicantType) {
        if (String.isBlank(applicantType)) {
            return WAIVER_APPLICANT_KEY_BORROWER;
        }
        if (APPLICANT_TYPE_CO_BORROWER.equalsIgnoreCase(applicantType)
                || 'Co-Borrower'.equalsIgnoreCase(applicantType)) {
            return 'Co Borrower';
        }
        return applicantType;
    }

    private static List<Map<String, Object>> buildIndividualFiDecisions(Applicant_Address__c currentAddressRow) {
        return new List<Map<String, Object>>{
            new Map<String, Object>{
                'fiType' => WAIVER_FI_TYPE_CODE_CURRENT,
                'fiStatus' => WAIVER_STATUS_NOT_WAIVED
            },
            new Map<String, Object>{
                'fiType' => WAIVER_FI_TYPE_CODE_OFFICE,
                'fiStatus' => isSameAsCurrent(currentAddressRow)
                    ? WAIVER_STATUS_WAIVED
                    : WAIVER_STATUS_NOT_WAIVED
            },
            new Map<String, Object>{
                'fiType' => WAIVER_FI_TYPE_CODE_PERMANENT,
                'fiStatus' => isSameAsPermanent(currentAddressRow)
                    ? WAIVER_STATUS_WAIVED
                    : WAIVER_STATUS_NOT_WAIVED
            }
        };
    }

    private static List<Map<String, Object>> buildNiFiDecisionsForApplicant(
            Applicant__c applicant,
            Applicant_Address__c currentAddressRow,
            Applicant_Address__c registeredAddressRow) {
        if (applicant != null && GenericUtility.isNonIndividualApplicationType(applicant.Type__c)) {
            Boolean officeSameAsRegistered = isOfficeSameAsRegistered(registeredAddressRow);
            return new List<Map<String, Object>>{
                new Map<String, Object>{
                    'fiType' => WAIVER_FI_TYPE_CODE_REGISTERED,
                    'fiStatus' => officeSameAsRegistered
                        ? WAIVER_STATUS_WAIVED
                        : WAIVER_STATUS_NOT_WAIVED
                },
                new Map<String, Object>{
                    'fiType' => WAIVER_FI_TYPE_CODE_OFFICE,
                    'fiStatus' => WAIVER_STATUS_NOT_WAIVED
                }
            };
        }

        return buildIndividualFiDecisions(currentAddressRow);
    }

    private static Map<Id, Applicant_Address__c> loadCurrentAddressRows(Id applicationId) {
        Map<Id, Applicant_Address__c> currentAddressByApplicant = new Map<Id, Applicant_Address__c>();
        for (Applicant_Address__c row : [
            SELECT Applicant__c,
                   Is_Current_Address_Same_As_Permanent__c,
                   Is_Office_Address_Same_As_Current__c
            FROM Applicant_Address__c
            WHERE Applicant__r.Application__c = :applicationId
              AND Applicant__r.In_Active_Applicant__c = false
              AND Address_Type__c = 'Current Residential Address'
        ]) {
            currentAddressByApplicant.put(row.Applicant__c, row);
        }
        return currentAddressByApplicant;
    }

    private static Map<Id, Applicant_Address__c> loadRegisteredAddressRows(Id applicationId) {
        Map<Id, Applicant_Address__c> registeredAddressByApplicant = new Map<Id, Applicant_Address__c>();
        for (Applicant_Address__c row : [
            SELECT Applicant__c,
                   Is_Office_Address_Same_As_Registered__c
            FROM Applicant_Address__c
            WHERE Applicant__r.Application__c = :applicationId
              AND Applicant__r.In_Active_Applicant__c = false
              AND Address_Type__c = :ADDR_REGISTERED
        ]) {
            registeredAddressByApplicant.put(row.Applicant__c, row);
        }
        return registeredAddressByApplicant;
    }

    private static Boolean isPassengerVehicleProduct(Application__c application) {
        if (application == null) {
            return false;
        }
        String token = GenericUtility.resolveProductTypeToken(
            application.Product__c,
            application.Sub_Product__c
        );
        if ('PV'.equalsIgnoreCase(token)) {
            return true;
        }
        return application.Product__c != null
            && '4W'.equalsIgnoreCase(application.Product__c.trim());
    }

    private static Boolean isCommercialVehicleProduct(Application__c application) {
        if (application == null) {
            return false;
        }
        String token = GenericUtility.resolveProductTypeToken(
            application.Product__c,
            application.Sub_Product__c
        );
        if (String.isNotBlank(token)
                && ('SCV'.equalsIgnoreCase(token)
                    || 'LCV'.equalsIgnoreCase(token)
                    || 'MHCV'.equalsIgnoreCase(token)
                    || 'CE'.equalsIgnoreCase(token))) {
            return true;
        }
        return application.Product__c != null
            && 'CV'.equalsIgnoreCase(application.Product__c.trim());
    }

    private static Boolean isSameAsPermanent(Applicant_Address__c currentRow) {
        return currentRow != null
            && 'Yes'.equalsIgnoreCase(currentRow.Is_Current_Address_Same_As_Permanent__c);
    }

    private static Boolean isSameAsCurrent(Applicant_Address__c currentRow) {
        return currentRow != null
            && 'Yes'.equalsIgnoreCase(currentRow.Is_Office_Address_Same_As_Current__c);
    }

    private static Boolean isOfficeSameAsRegistered(Applicant_Address__c registeredRow) {
        return registeredRow != null
            && 'Yes'.equalsIgnoreCase(registeredRow.Is_Office_Address_Same_As_Registered__c);
    }

    private static Id getBorrowerApplicantId(Id applicationId) {
        if (applicationId == null) {
            return null;
        }
        List<Applicant__c> borrowers = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND Applicant_Type__c = :WAIVER_APPLICANT_KEY_BORROWER
              AND In_Active_Applicant__c = false
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return borrowers.isEmpty() ? null : borrowers[0].Id;
    }
}