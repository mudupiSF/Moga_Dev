/**
 * FI investigation orchestration for Offer stage navigation.
 *
 * FI creation consumes the FI Waiver payload produced by
 * FIWaiverAPIHandler after the offer-page LWC invokes the API.
 *
 * Investigations__c are linked to Application__c only (one FI investigation per applicant).
 * Multiple FI types (Current Residence / Permanent / Office) are child Verification__c rows
 * on the same investigation; FI type is identified from Verification__c.Name.
 */
public with sharing class FIInvestigationController implements Callable {

    public static final String INTEGRATION_KEY = 'FI_WAIVER';
    public static final String STATUS_COMPLETED = 'Completed';

    private static final String ACTION_GET_RESIDENCE_FI = 'getResidenceFiData';
    private static final String ACTION_GET_PERMANENT_FI = 'getPermanentFiData';
    private static final String ACTION_GET_OFFICE_FI = 'getOfficeFiData';
    private static final String ACTION_GET_FI_BY_INVESTIGATION = 'getFiDataByInvestigation';
    private static final String ACTION_SAVE_FI_DATA = 'saveFiData';
    private static final String ACTION_UPDATE_FI_LOCATION = 'updateFiLocation';
    private static final String ACTION_GET_APPLICANT_PROFILE = 'getApplicantProfile';
    private static final String ACTION_INIT_OR_GET_FI_DOCUMENT = 'initOrGetFiDocument';
    private static final String ACTION_LINK_FI_DOCUMENT = 'linkFiDocument';
    private static final String ACTION_GET_FI_DOCUMENT_PREVIEW = 'getFiDocumentPreviewInfo';
    private static final String ACTION_SAVE_FI_SIGNATURE = 'saveFiSignature';
    private static final String ACTION_CREATE_FI_INVESTIGATIONS = 'createFiInvestigations';

    private static final String DOC_TYPE_FI_SIGNATURE = 'FI Signature';
    private static final String DOC_TYPE_RESIDENCE_FRONT = 'Residence Front View';
    private static final String DOC_TYPE_FI_KYC = 'FI KYC Document';
    private static final String DOC_TYPE_OFFICE_BUILDING_FRONT = 'Office Building Front View';
    private static final String DOC_TYPE_OFFICE_APPROACH_ROAD = 'Office Approach Road';
    private static final String DOC_TYPE_OFFICE_BUILDING_INNER = 'Office Building Inner View';
    private static final String DOC_TYPE_LAND_PHOTO = 'Land Photo';
    private static final String DOC_TYPE_PATTA = 'Patta Document';
    private static final String DOC_TYPE_RENT_AGREEMENT = 'Rent Agreement';
    private static final String DOC_TYPE_PENSION_DOCUMENT = 'Pension Document';
    private static final String DOC_TYPE_CURRENT_ADDRESS_PROOF = 'Current Address Proof';
    private static final String DOC_TYPE_PERMANENT_ADDRESS_PROOF = 'Permanent Address Proof';
    private static final String DOC_TYPE_OFFICE_ADDRESS_PROOF = 'Office Address Proof';

    private static final String TYPE_FI = 'FI';
    private static final String STATUS_INITIATED = 'Initiated';
    private static final String WAIVER_STATUS_NOT_WAIVED = 'Not Waived';
    private static final String WAIVER_STATUS_WAIVED = 'Waived';

    private static final String FI_LABEL_CURRENT = 'Current Residence FI';
    private static final String FI_LABEL_OFFICE = 'Office FI';
    private static final String FI_LABEL_PERMANENT = 'Permanent Residence FI';
    private static final String FI_LABEL_REGISTERED = 'Registered Address FI';

    private static final String ADDR_CURRENT = 'Current Residential Address';
    private static final String ADDR_OFFICE = 'Office Address';
    private static final String ADDR_PERMANENT = 'Permanent Residential Address';
    private static final String ADDR_REGISTERED = 'Registered Address';
    private static final Set<String> KNOWN_ADDRESS_TYPES = new Set<String>{
        ADDR_CURRENT, ADDR_OFFICE, ADDR_PERMANENT
    };

    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';
    private static final String APPLICANT_TYPE_CO_BORROWER = 'Co-borrower';
    private static final String APPLICANT_TYPE_GUARANTOR = 'Guarantor';
    private static final String WAIVER_APPLICANT_KEY_BORROWER = 'Borrower';
    private static final String WAIVER_APPLICANT_KEY_G1 = 'G1';
    private static final String WAIVER_APPLICANT_KEY_G2 = 'G2';

    private static final String WAIVER_FI_TYPE_CODE_CURRENT = 'C';
    private static final String WAIVER_FI_TYPE_CODE_OFFICE = 'O';
    private static final String WAIVER_FI_TYPE_CODE_PERMANENT = 'P';
    private static final String WAIVER_FI_TYPE_CODE_REGISTERED = 'R';

    private static final String ADDR_TYPE_CURRENT = 'Current';
    private static final String ADDR_TYPE_OFFICE = 'Office';
    private static final String ADDR_TYPE_PERMANENT = 'Permanent';
    private static final String ADDR_TYPE_REGISTERED = 'Registered';

    private static final String INVESTIGATION_NAME_SEPARATOR = ' - ';
    private static final String INVESTIGATION_NAME_PREFIX = 'FI';
    private static final String VERIFICATION_NAME_SUFFIX = ' Verification';

    private static final String VERIFICATION_CONTEXT_FIELDS =
        'Id, Name, Applicant__c, Investigations__c, Investigations__r.Application__c';

    private static final String APPLICANT_ADDRESS_FIELDS =
        'Applicant__c, Address_Type__c, ' +
        'Address_Line_1__c, Address_Line_2__c, City__c, State__c, PinCode__c, ' +
        'Is_Current_Address_Same_As_Permanent__c, Is_Office_Address_Same_As_Current__c, ' +
        'Is_Office_Address_Same_As_Registered__c';

    private static final String KYC_ADDRESS_CHECKLIST_FIELDS =
        'Applicant__c, Address_Type__c, ' +
        'Applicant_KYC__r.KYC_Address_Line_1__c, Applicant_KYC__r.KYC_Address_Line_2__c, ' +
        'Applicant_KYC__r.KYC_City__c, Applicant_KYC__r.KYC_State__c, Applicant_KYC__r.KYC_Pin_Code__c';

    private static final String FI_VERIFICATION_SOQL_FIELDS =
        'Id, Name, Applicant__c, Applicant__r.Name, Applicant__r.Company_Name__c, ' +
        'Applicant__r.Type__c, Applicant__r.Free_Fleet__c, ' +
        'Applicant__r.Financed_by_Others__c, Applicant__r.Total_Fleet__c, ' +
        'Applicant__r.Customer_First_Name__c, Applicant__r.Customer_Last_Name__c, ' +
        'Applicant__r.Income_Category__c, Applicant__r.Profile__c, ' +
        'Additional_Remarks__c, Recommendation__c, ' +
        'Investigations__r.Id, Investigations__r.Name, Investigations__r.Status__c, ' +
        'Investigations__r.Application__c, Investigations__r.Application__r.Product__c, ' +
        'Investigations__r.Application__r.Sub_Product__c, Investigations__r.Application__r.CreatedDate, ' +
        'Status__c, Address_Type__c, Decision__c, Remarks__c, Submitted_Date__c, Submitted_By__c, CreatedDate, ' +
        'Residence_Type__c, Landmark__c, Phone_Number__c, Mobile__c, Customer_House_Same__c, ' +
        'Number_of_Dependent__c, Number_of_Earning_Member__c, Name_of_Person_Met__c, Relationship__c, ' +
        'Years_in_City__c, Years_in_Residence__c, KYC_Latitude__c, KYC_Longitude__c, Latitude__c, Longitude__c, ' +
        'Coordinates_Verified__c, Coordinates_Distance__c, Same_Address_as_in_Application__c, ' +
        'Employer_Business_Name__c, Office_Business_Type__c, Business_Premise__c, ' +
        'Current_Experience_Years__c, Monthly_Income__c, Applicant_Recognized__c, Total_Income__c, ' +
        'Profile_to_Product_Match__c, No_of_Attempts__c, Observation__c, Feedback__c, ' +
        'FI_Address_Line_1__c, FI_Address_Line_2__c, FI_City__c, FI_State__c, FI_Pin_Code__c, ' +
        'Resi_Cum_Off__c, KM_from_Branch__c, Lead_Gen_Time__c, Office_BP_FI__c, Resi_FI__c, ' +
        'Frontside__c, Leftside__c, Rearside__c, Rightside__c, Request_Gen_Time__c, ' +
        'Office_Verified_Time__c, Resi_Verified_Time__c, Company_Name__c, SENPName__c, ' +
        'Total_Business_Stability__c, Org_Type__c, Business_Nature__c, Current_Business_Stability__c, ' +
        'Business_Premises_Owned_Rental__c, If_Rental_Premises_Rent_per_month__c, No_of_Emp_Seen__c, ' +
        'Office_Board__c, Location__c, Activity_at_office__c, Locatability__c, ' +
        'Touring_or_Transferrable_job__c, How_many_Employees_in_Office__c, Political_Photo__c, ' +
        'Office_Business_Size_Sqft__c, Locality__c, Office_Approach__c, Behaviour__c, ' +
        'Photo_Not_Allowed__c, FI_Recommendation__c, Reject_Reason__c, Fleet_Count__c, ' +
        'Free_Fleet__c, Bank_Fleet__c, Financed_by_Others__c, Fleet_Total__c';

    private static final String STATUS_IN_PROGRESS = 'In Progress';
    private static final String STATUS_ACCEPTED = 'Accepted';
    private static final String DECISION_ACCEPTED = 'Accepted';
    private static final String DECISION_REJECTED = 'Rejected';
    private static final String INVESTIGATION_STATUS_IN_PROGRESS = 'In-Progress';
    private static final Decimal FI_COORDINATE_VERIFY_THRESHOLD_METERS = 500;

    private static final Map<String, String> WAIVER_FI_TYPE_CODE_TO_LABEL = new Map<String, String>{
        WAIVER_FI_TYPE_CODE_CURRENT => FI_LABEL_CURRENT,
        WAIVER_FI_TYPE_CODE_OFFICE => FI_LABEL_OFFICE,
        WAIVER_FI_TYPE_CODE_PERMANENT => FI_LABEL_PERMANENT,
        WAIVER_FI_TYPE_CODE_REGISTERED => FI_LABEL_REGISTERED
    };
    private static final Map<String, String> FI_LABEL_TO_ADDRESS_TYPE = new Map<String, String>{
        FI_LABEL_CURRENT => ADDR_CURRENT,
        FI_LABEL_OFFICE => ADDR_OFFICE,
        FI_LABEL_PERMANENT => ADDR_PERMANENT,
        FI_LABEL_REGISTERED => ADDR_REGISTERED
    };
    private static final Map<String, String> FI_LABEL_TO_ADDR_TYPE = new Map<String, String>{
        FI_LABEL_CURRENT => ADDR_TYPE_CURRENT,
        FI_LABEL_OFFICE => ADDR_TYPE_OFFICE,
        FI_LABEL_PERMANENT => ADDR_TYPE_PERMANENT,
        FI_LABEL_REGISTERED => ADDR_TYPE_REGISTERED
    };
    private static final Map<String, String> FI_LABEL_TO_ADDRESS_PROOF = new Map<String, String>{
        FI_LABEL_CURRENT => DOC_TYPE_CURRENT_ADDRESS_PROOF,
        FI_LABEL_REGISTERED => DOC_TYPE_CURRENT_ADDRESS_PROOF,
        FI_LABEL_PERMANENT => DOC_TYPE_PERMANENT_ADDRESS_PROOF,
        FI_LABEL_OFFICE => DOC_TYPE_OFFICE_ADDRESS_PROOF
    };
    private static final Set<String> RESIDENCE_FI_LABELS = new Set<String>{
        FI_LABEL_CURRENT, FI_LABEL_PERMANENT, FI_LABEL_REGISTERED
    };
    private static final Set<String> NI_OFFICE_ADDRESS_FI_LABELS = new Set<String>{
        FI_LABEL_CURRENT, FI_LABEL_OFFICE, FI_LABEL_PERMANENT, FI_LABEL_REGISTERED
    };
    private static final Set<String> KNOWN_FI_LABELS = new Set<String>{
        FI_LABEL_CURRENT, FI_LABEL_OFFICE, FI_LABEL_PERMANENT, FI_LABEL_REGISTERED
    };

    private class FiVerificationCandidate {
        private Id applicantId;
        private String fiLabel;

        private FiVerificationCandidate(Id applicantId, String fiLabel) {
            this.applicantId = applicantId;
            this.fiLabel = fiLabel;
        }
    }

    private class AddressWrapper {
        private String line1;
        private String line2;
        private String city;
        private String state;
        private String pinCode;
    }

    private class ApplicantAddressBundle {
        private Map<Id, Map<String, AddressWrapper>> byApplicant =
            new Map<Id, Map<String, AddressWrapper>>();
        private Map<Id, Applicant_Address__c> currentRowByApplicant =
            new Map<Id, Applicant_Address__c>();
        private Map<Id, Applicant_Address__c> registeredRowByApplicant =
            new Map<Id, Applicant_Address__c>();
    }

    private class DocumentContext {
        private Id applicationId;
        private Id applicantId;
        private Id verificationId;
        private String fiLabel;
    }

    private class FiCreationContext {
        private Boolean isNiFiApplication = false;
        private List<Applicant__c> applicants = new List<Applicant__c>();
        private Map<Id, Applicant__c> applicantById = new Map<Id, Applicant__c>();
        private Map<String, Applicant__c> applicantsByWaiverKey = new Map<String, Applicant__c>();
        private Map<String, Id> applicantIdByDisplayName = new Map<String, Id>();
        private Map<Id, Map<String, AddressWrapper>> addressesByApplicant =
            new Map<Id, Map<String, AddressWrapper>>();
        private Map<Id, Applicant_Address__c> currentAddressRowByApplicant =
            new Map<Id, Applicant_Address__c>();
        private Map<Id, Applicant_Address__c> registeredAddressRowByApplicant =
            new Map<Id, Applicant_Address__c>();
        private Map<Id, Investigations__c> existingInvestigationsByApplicant =
            new Map<Id, Investigations__c>();
        private Map<String, Verification__c> existingVerificationsByKey = new Map<String, Verification__c>();
    }

    public class CreationResult {
        public Boolean isSuccess { get; set; }
        public String message { get; set; }
        public Integer investigationsCreated { get; set; }

        public CreationResult() {
            this.isSuccess = false;
            this.investigationsCreated = 0;
        }
    }

    public class FIDataWrapper {
        @AuraEnabled public String investigationId { get; set; }
        @AuraEnabled public String verificationId { get; set; }
        @AuraEnabled public String applicantId { get; set; }
        @AuraEnabled public String applicationId { get; set; }
        @AuraEnabled public String fiLabel { get; set; }
        @AuraEnabled public String fiStatus { get; set; }
        @AuraEnabled public String applicantName { get; set; }
        @AuraEnabled public String productType { get; set; }
        @AuraEnabled public String formDataJson { get; set; }
        @AuraEnabled public String fiDecision { get; set; }
        @AuraEnabled public String remarks { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String profile { get; set; }
        @AuraEnabled public Boolean isCompleted { get; set; }
        @AuraEnabled public Boolean isRejected { get; set; }
        @AuraEnabled public Boolean isLocked { get; set; }
        @AuraEnabled public Boolean isSubmitted { get; set; }
        @AuraEnabled public Boolean isAddressProofUploaded { get; set; }
        @AuraEnabled public List<Map<String, String>> addressProofDocuments { get; set; }
        @AuraEnabled public Boolean isNonIndividual { get; set; }
        @AuraEnabled public String investigationCaseName { get; set; }
    }

    public class ApplicantProfileWrapper {
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String subBucket { get; set; }
        @AuraEnabled public String applicantType { get; set; }
        @AuraEnabled public String isIncomeAvailable { get; set; }
    }

    /**
     * Creates FI Investigations__c records for the application from the FI Waiver stub.
     */
    public static CreationResult createFiInvestigations(Id applicationId) {
        CreationResult result = new CreationResult();

        if (applicationId == null) {
            result.message = 'Application Id is required.';
            return result;
        }

        List<Application__c> applications = [
            SELECT Id
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        if (applications.isEmpty()) {
            result.message = 'Application not found.';
            return result;
        }

        String fiMode = FIWaiverAPIHandler.consumeFiCreationMode(applicationId);
        if (String.isBlank(fiMode)) {
            fiMode = FIWaiverAPIHandler.resolveFiCreationMode(applicationId);
        }
        Boolean isNiFiApplication = FIWaiverAPIHandler.FI_MODE_PV_NI.equals(fiMode)
            || FIWaiverAPIHandler.FI_MODE_CV_NI.equals(fiMode);

        FiCreationContext ctx = getCreationContext(applicationId, isNiFiApplication);
        Map<String, Object> waiverPayload = FIWaiverAPIHandler.consumeWaiverPayload(applicationId);
        if (waiverPayload == null || waiverPayload.isEmpty()) {
            result.message = 'FI Waiver payload is missing. Invoke the waiver API before creating FI investigations.';
            return result;
        }
        List<Map<String, Object>> fiDetails = new List<Map<String, Object>>();
        Object rawFiDetails = waiverPayload.get('fiDetails');
        if (rawFiDetails instanceof List<Object>) {
            for (Object item : (List<Object>) rawFiDetails) {
                if (item instanceof Map<String, Object>) {
                    fiDetails.add((Map<String, Object>) item);
                }
            }
        }
        if (fiDetails.isEmpty()) {
            result.message = 'FI Waiver stub returned no fiDetails.';
            return result;
        }

        Map<Id, Investigations__c> investigationsToInsertByApplicant = new Map<Id, Investigations__c>();
        List<FiVerificationCandidate> verificationCandidates = new List<FiVerificationCandidate>();
        Set<String> pendingVerificationKeys = new Set<String>();
        String previousWaiverApplicantKey = '';

        for (Map<String, Object> fiDetail : fiDetails) {
            List<Map<String, Object>> decisions = new List<Map<String, Object>>();
            if (fiDetail != null && fiDetail.containsKey('Decision')) {
                Object rawDecisions = fiDetail.get('Decision');
                if (rawDecisions instanceof List<Object>) {
                    for (Object item : (List<Object>) rawDecisions) {
                        if (item instanceof Map<String, Object>) {
                            decisions.add((Map<String, Object>) item);
                        }
                    }
                }
            }
            if (decisions.isEmpty()) {
                continue;
            }

            String waiverApplicantType = fiDetail.containsKey('ApplicantType')
                ? String.valueOf(fiDetail.get('ApplicantType'))
                : null;
            Applicant__c applicant = ctx.isNiFiApplication
                ? resolveNiApplicantFromFiDetail(fiDetail, ctx)
                : resolveIndividualApplicantFromFiDetail(
                    waiverApplicantType,
                    ctx,
                    previousWaiverApplicantKey
                );
            if (applicant == null) {
                continue;
            }
            if (!ctx.isNiFiApplication) {
                if (String.isBlank(waiverApplicantType)) {
                    previousWaiverApplicantKey = WAIVER_APPLICANT_KEY_BORROWER;
                } else if (WAIVER_APPLICANT_KEY_BORROWER.equalsIgnoreCase(waiverApplicantType)) {
                    previousWaiverApplicantKey = WAIVER_APPLICANT_KEY_BORROWER;
                } else {
                    Boolean isSecondaryApplicant = waiverApplicantType.equalsIgnoreCase('Co Borrower')
                        || waiverApplicantType.equalsIgnoreCase('Co-Borrower')
                        || waiverApplicantType.equalsIgnoreCase(APPLICANT_TYPE_CO_BORROWER)
                        || waiverApplicantType.equalsIgnoreCase(APPLICANT_TYPE_GUARANTOR);
                    if (isSecondaryApplicant && previousWaiverApplicantKey != WAIVER_APPLICANT_KEY_G1) {
                        previousWaiverApplicantKey = WAIVER_APPLICANT_KEY_G1;
                    } else if (isSecondaryApplicant && previousWaiverApplicantKey == WAIVER_APPLICANT_KEY_G1) {
                        previousWaiverApplicantKey = WAIVER_APPLICANT_KEY_G2;
                    } else {
                        previousWaiverApplicantKey = waiverApplicantType;
                    }
                }
            }

            Map<String, AddressWrapper> applicantAddresses = ctx.addressesByApplicant.containsKey(applicant.Id)
                ? ctx.addressesByApplicant.get(applicant.Id)
                : new Map<String, AddressWrapper>();

            for (Map<String, Object> decision : decisions) {
                String fiTypeCode = decision.containsKey('fiType')
                    ? String.valueOf(decision.get('fiType'))
                    : null;
                String fiStatus = decision.containsKey('fiStatus')
                    ? String.valueOf(decision.get('fiStatus'))
                    : null;
                String fiLabel = String.isBlank(fiTypeCode)
                    ? null
                    : WAIVER_FI_TYPE_CODE_TO_LABEL.get(fiTypeCode.toUpperCase());
                if (String.isBlank(fiLabel) || !WAIVER_STATUS_NOT_WAIVED.equalsIgnoreCase(fiStatus)) {
                    continue;
                }

                Applicant_Address__c currentAddressRow = ctx.currentAddressRowByApplicant.get(applicant.Id);
                Applicant_Address__c registeredAddressRow = ctx.registeredAddressRowByApplicant.get(applicant.Id);
                if (!shouldCreateVerificationForFiLabel(
                        fiLabel,
                        currentAddressRow,
                        registeredAddressRow,
                        applicantAddresses,
                        ctx.isNiFiApplication
                    )) {
                    continue;
                }

                String verificationKey = buildVerificationDedupeKey(applicant.Id, fiLabel);
                if (ctx.existingVerificationsByKey.containsKey(verificationKey)
                        || pendingVerificationKeys.contains(verificationKey)) {
                    continue;
                }

                if (!ctx.existingInvestigationsByApplicant.containsKey(applicant.Id)
                        && !investigationsToInsertByApplicant.containsKey(applicant.Id)) {
                    investigationsToInsertByApplicant.put(
                        applicant.Id,
                        buildInvestigation(applicationId, applicant, STATUS_INITIATED)
                    );
                }

                verificationCandidates.add(new FiVerificationCandidate(applicant.Id, fiLabel));
                pendingVerificationKeys.add(verificationKey);
            }
        }

        Integer createdCount = saveInvestigationsAndVerifications(
            applicationId,
            investigationsToInsertByApplicant,
            verificationCandidates,
            ctx
        );

        result.isSuccess = true;
        result.investigationsCreated = createdCount;
        result.message = createdCount > 0
            ? 'Created FI investigation and verification record(s) from FI Waiver response.'
            : 'FI investigation and verification record(s) already exist — no duplicates created.';
        return result;
    }

    /**
     * Loads applicants, addresses, and existing FI investigations with verifications in minimal SOQL.
     */
    private static Applicant__c resolveNiApplicantFromFiDetail(
            Map<String, Object> fiDetail,
            FiCreationContext ctx) {
        if (fiDetail != null && fiDetail.containsKey('applicantId') && fiDetail.get('applicantId') != null) {
            try {
                Id applicantId = (Id) String.valueOf(fiDetail.get('applicantId'));
                if (ctx.applicantById.containsKey(applicantId)) {
                    return ctx.applicantById.get(applicantId);
                }
            } catch (Exception ex) {
                return null;
            }
        }
        return null;
    }

    private static Applicant__c resolveIndividualApplicantFromFiDetail(
            String waiverApplicantType,
            FiCreationContext ctx,
            String previousWaiverApplicantKey) {
        String waiverKey;
        if (String.isBlank(waiverApplicantType)) {
            waiverKey = WAIVER_APPLICANT_KEY_BORROWER;
        } else if (WAIVER_APPLICANT_KEY_BORROWER.equalsIgnoreCase(waiverApplicantType)) {
            waiverKey = WAIVER_APPLICANT_KEY_BORROWER;
        } else {
            Boolean isSecondaryApplicant = waiverApplicantType.equalsIgnoreCase('Co Borrower')
                || waiverApplicantType.equalsIgnoreCase('Co-Borrower')
                || waiverApplicantType.equalsIgnoreCase(APPLICANT_TYPE_CO_BORROWER)
                || waiverApplicantType.equalsIgnoreCase(APPLICANT_TYPE_GUARANTOR);
            if (isSecondaryApplicant && previousWaiverApplicantKey != WAIVER_APPLICANT_KEY_G1) {
                waiverKey = WAIVER_APPLICANT_KEY_G1;
            } else if (isSecondaryApplicant && previousWaiverApplicantKey == WAIVER_APPLICANT_KEY_G1) {
                waiverKey = WAIVER_APPLICANT_KEY_G2;
            } else {
                waiverKey = waiverApplicantType;
            }
        }
        return ctx.applicantsByWaiverKey.get(waiverKey);
    }

    private static Boolean shouldCreateVerificationForFiLabel(
            String fiLabel,
            Applicant_Address__c currentAddressRow,
            Applicant_Address__c registeredAddressRow,
            Map<String, AddressWrapper> applicantAddresses,
            Boolean isNiFiApplication) {
        if (isNiFiApplication == true && FI_LABEL_REGISTERED.equals(fiLabel)) {
            if (isOfficeSameAsRegistered(registeredAddressRow)) {
                return false;
            }
            return applicantAddresses != null && applicantAddresses.containsKey(ADDR_REGISTERED);
        }
        if (FI_LABEL_PERMANENT.equals(fiLabel) || FI_LABEL_REGISTERED.equals(fiLabel)) {
            return !isSameAsPermanent(currentAddressRow);
        }
        if (FI_LABEL_OFFICE.equals(fiLabel)) {
            if (isNiFiApplication == true) {
                return hasNiOfficeAddressAvailable(applicantAddresses, registeredAddressRow);
            }
            return !isSameAsCurrent(currentAddressRow);
        }
        String addressType = FI_LABEL_TO_ADDRESS_TYPE.get(fiLabel);
        if (String.isNotBlank(addressType)
                && (applicantAddresses == null || !applicantAddresses.containsKey(addressType))) {
            return false;
        }
        return true;
    }

    private static FiCreationContext getCreationContext(Id applicationId, Boolean isNiFiApplication) {
        FiCreationContext ctx = new FiCreationContext();
        ctx.isNiFiApplication = isNiFiApplication == true;
        Integer coBorrowerIndex = 0;
        Set<Id> applicantIds = new Set<Id>();

        for (Applicant__c applicant : [
            SELECT Id, Name, Applicant_Type__c, Company_Name__c,
                   Customer_First_Name__c, Customer_Last_Name__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND In_Active_Applicant__c = false
            ORDER BY Applicant_Type__c ASC, CreatedDate ASC
        ]) {
            applicantIds.add(applicant.Id);
            ctx.applicants.add(applicant);
            if (ctx.isNiFiApplication) {
                ctx.applicantById.put(applicant.Id, applicant);
            }
            if (String.isNotBlank(applicant.Name)) {
                ctx.applicantIdByDisplayName.put(applicant.Name.trim().toLowerCase(), applicant.Id);
            }
        }

        Map<Id, Document_CheckList__c> poiByApplicantId = getPoiIdentityDocumentsByApplicant(applicantIds);
        for (Applicant__c applicant : ctx.applicants) {
            String displayName = getApplicantName(applicant, poiByApplicantId.get(applicant.Id));
            if (String.isNotBlank(displayName)) {
                ctx.applicantIdByDisplayName.put(displayName.trim().toLowerCase(), applicant.Id);
            }

            if (APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicant.Applicant_Type__c)) {
                ctx.applicantsByWaiverKey.put(WAIVER_APPLICANT_KEY_BORROWER, applicant);
            } else if (APPLICANT_TYPE_CO_BORROWER.equalsIgnoreCase(applicant.Applicant_Type__c)
                    || APPLICANT_TYPE_GUARANTOR.equalsIgnoreCase(applicant.Applicant_Type__c)) {
                coBorrowerIndex++;
                String waiverKey = coBorrowerIndex == 1 ? WAIVER_APPLICANT_KEY_G1 : WAIVER_APPLICANT_KEY_G2;
                if (!ctx.applicantsByWaiverKey.containsKey(waiverKey)) {
                    ctx.applicantsByWaiverKey.put(waiverKey, applicant);
                }
            }
        }

        ApplicantAddressBundle addressBundle = fetchAddressBundle(
            applicationId,
            null,
            ctx.isNiFiApplication
        );
        ctx.addressesByApplicant = addressBundle.byApplicant;
        ctx.currentAddressRowByApplicant = addressBundle.currentRowByApplicant;
        ctx.registeredAddressRowByApplicant = addressBundle.registeredRowByApplicant;

        for (Investigations__c investigation : [
            SELECT Id, Name, Status__c, Type_of_Investigation__c,
                   (SELECT Id, Name, Applicant__c, Investigations__c FROM Verifications__r)
            FROM Investigations__c
            WHERE Application__c = :applicationId
              AND Type_of_Investigation__c = :TYPE_FI
        ]) {
            Id applicantId = getApplicantIdFromName(
                investigation.Name,
                ctx.applicantIdByDisplayName
            );
            if (applicantId != null && !ctx.existingInvestigationsByApplicant.containsKey(applicantId)) {
                ctx.existingInvestigationsByApplicant.put(applicantId, investigation);
            }

            for (Verification__c verification : investigation.Verifications__r) {
                if (verification.Applicant__c != null
                        && !ctx.existingInvestigationsByApplicant.containsKey(verification.Applicant__c)) {
                    ctx.existingInvestigationsByApplicant.put(verification.Applicant__c, investigation);
                }
                String fiLabel = getFiLabel(verification.Name, true);
                if (String.isNotBlank(fiLabel) && verification.Applicant__c != null) {
                    ctx.existingVerificationsByKey.put(
                        buildVerificationDedupeKey(verification.Applicant__c, fiLabel),
                        verification
                    );
                }
            }
        }

        return ctx;
    }

    private static Integer saveInvestigationsAndVerifications(
            Id applicationId,
            Map<Id, Investigations__c> investigationsToInsertByApplicant,
            List<FiVerificationCandidate> verificationCandidates,
            FiCreationContext ctx) {
        if (applicationId == null || ctx == null) {
            return 0;
        }

        Integer createdCount = 0;
        Map<Id, Investigations__c> investigationsByApplicant =
            new Map<Id, Investigations__c>(ctx.existingInvestigationsByApplicant);
        Map<String, Verification__c> verificationsByKey =
            new Map<String, Verification__c>(ctx.existingVerificationsByKey);

        if (investigationsToInsertByApplicant != null && !investigationsToInsertByApplicant.isEmpty()) {
            List<Investigations__c> investigationsToInsert = new List<Investigations__c>();
            List<Id> applicantIdsForInsert = new List<Id>();

            for (Id applicantId : investigationsToInsertByApplicant.keySet()) {
                if (investigationsByApplicant.containsKey(applicantId)) {
                    continue;
                }
                investigationsToInsert.add(investigationsToInsertByApplicant.get(applicantId));
                applicantIdsForInsert.add(applicantId);
            }

            if (!investigationsToInsert.isEmpty()) {
                insert investigationsToInsert;
                createdCount += investigationsToInsert.size();
                for (Integer i = 0; i < investigationsToInsert.size(); i++) {
                    investigationsByApplicant.put(applicantIdsForInsert[i], investigationsToInsert[i]);
                }
            }
        }

        List<Verification__c> verificationsToInsert = new List<Verification__c>();
        if (verificationCandidates != null) {
            for (FiVerificationCandidate candidate : verificationCandidates) {
                String verificationKey = buildVerificationDedupeKey(candidate.applicantId, candidate.fiLabel);
                if (verificationsByKey.containsKey(verificationKey)) {
                    continue;
                }
                Investigations__c investigation = investigationsByApplicant.get(candidate.applicantId);
                if (investigation == null || investigation.Id == null) {
                    continue;
                }
                verificationsToInsert.add(
                    buildVerificationRecord(investigation, candidate.applicantId, candidate.fiLabel)
                );
                verificationsByKey.put(verificationKey, verificationsToInsert[verificationsToInsert.size() - 1]);
            }
        }

        if (!verificationsToInsert.isEmpty()) {
            insert verificationsToInsert;
            createdCount += verificationsToInsert.size();
        }

        return createdCount;
    }

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_GET_RESIDENCE_FI.equalsIgnoreCase(action)
                || ACTION_GET_PERMANENT_FI.equalsIgnoreCase(action)
                || ACTION_GET_OFFICE_FI.equalsIgnoreCase(action)
                || ACTION_GET_FI_BY_INVESTIGATION.equalsIgnoreCase(action)) {
            return getFiData(safeArgs, action);
        }
        if (ACTION_SAVE_FI_DATA.equalsIgnoreCase(action)) {
            return saveFiData(safeArgs);
        }
        if (ACTION_UPDATE_FI_LOCATION.equalsIgnoreCase(action)) {
            return updateFiLocation(safeArgs);
        }
        if (ACTION_GET_APPLICANT_PROFILE.equalsIgnoreCase(action)) {
            return getApplicantProfile(safeArgs);
        }
        if (ACTION_SAVE_FI_SIGNATURE.equalsIgnoreCase(action)) {
            return saveFiSignature(safeArgs);
        }
        if (ACTION_GET_FI_DOCUMENT_PREVIEW.equalsIgnoreCase(action)) {
            return getDocumentPreview(safeArgs);
        }
        if (ACTION_INIT_OR_GET_FI_DOCUMENT.equalsIgnoreCase(action)
                || ACTION_LINK_FI_DOCUMENT.equalsIgnoreCase(action)) {
            return saveDocument(safeArgs, action);
        }
        if (ACTION_CREATE_FI_INVESTIGATIONS.equalsIgnoreCase(action)) {
            CreationResult result = createFiInvestigations(argId(safeArgs, 'recordId'));
            CreationResult safeResult = result != null ? result : new CreationResult();
            return new Map<String, Object>{
                'isSuccess' => safeResult.isSuccess == true,
                'message' => safeResult.message,
                'investigationsCreated' => safeResult.investigationsCreated
            };
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    private static Map<String, Object> getFiData(Map<String, Object> args, String action) {
        String fiLabel = null;
        if (ACTION_GET_RESIDENCE_FI.equalsIgnoreCase(action)) {
            fiLabel = FI_LABEL_CURRENT;
        } else if (ACTION_GET_PERMANENT_FI.equalsIgnoreCase(action)) {
            fiLabel = FI_LABEL_PERMANENT;
        } else if (ACTION_GET_OFFICE_FI.equalsIgnoreCase(action)) {
            fiLabel = FI_LABEL_OFFICE;
        }

        if (String.isNotBlank(fiLabel)) {
            String applicantId = argStr(args, 'applicantId');
            if (String.isBlank(applicantId)) {
                return mapResponse(null);
            }
            Id applicantRecordId = (Id) applicantId;
            List<Verification__c> verificationsForApplicant = fetchVerifications(
                'Applicant__c = :applicantId AND Investigations__r.Type_of_Investigation__c = :typeFi',
                new Map<String, Object>{ 'applicantId' => applicantRecordId, 'typeFi' => TYPE_FI },
                'CreatedDate DESC',
                null
            );
            Verification__c selectedVerification = selectVerificationForFiLabel(
                verificationsForApplicant,
                fiLabel
            );
            if (selectedVerification != null) {
                return mapResponse(buildFiDataWrapper(
                    selectedVerification.Investigations__r,
                    selectedVerification
                ));
            }
            return mapResponse(null);
        }

        Id verificationId = argId(args, 'verificationId');
        if (verificationId != null) {
            List<Verification__c> results = fetchVerifications(
                'Id = :verificationId AND Investigations__r.Type_of_Investigation__c = :typeFi',
                new Map<String, Object>{ 'verificationId' => verificationId, 'typeFi' => TYPE_FI },
                null,
                1
            );
            if (!results.isEmpty()) {
                return mapResponse(buildFiDataWrapper(results[0].Investigations__r, results[0]));
            }
        }

        Id investigationId = argId(args, 'investigationId');
        if (investigationId == null) {
            investigationId = argId(args, 'recordId');
        }
        if (investigationId == null) {
            return null;
        }

        fiLabel = argStr(args, 'fiLabel');
        if (String.isNotBlank(fiLabel)) {
            List<Verification__c> byLabel = fetchVerifications(
                'Investigations__c = :investigationId AND Investigations__r.Type_of_Investigation__c = :typeFi',
                new Map<String, Object>{
                    'investigationId' => investigationId,
                    'typeFi' => TYPE_FI
                },
                'CreatedDate DESC',
                null
            );
            Verification__c selectedVerification = selectVerificationForFiLabel(byLabel, fiLabel);
            return mapResponse(selectedVerification == null
                ? null
                : buildFiDataWrapper(selectedVerification.Investigations__r, selectedVerification));
        }

        List<Verification__c> firstVerification = fetchVerifications(
            'Investigations__c = :investigationId AND Investigations__r.Type_of_Investigation__c = :typeFi',
            new Map<String, Object>{ 'investigationId' => investigationId, 'typeFi' => TYPE_FI },
            'CreatedDate ASC',
            1
        );
        if (!firstVerification.isEmpty()) {
            return mapResponse(buildFiDataWrapper(
                firstVerification[0].Investigations__r,
                firstVerification[0]
            ));
        }

        List<Investigations__c> investigations = [
            SELECT Id, Name, Status__c,
                   Application__c,
                   Application__r.Product__c,
                   Application__r.Sub_Product__c,
                   Application__r.CreatedDate
            FROM Investigations__c
            WHERE Id = :investigationId
              AND Type_of_Investigation__c = :TYPE_FI
            LIMIT 1
        ];
        return investigations.isEmpty()
            ? null
            : mapResponse(buildFiDataWrapper(investigations[0], null));
    }

    private static Map<String, Object> saveFiData(Map<String, Object> args) {
        String dataJson = argStr(args, 'dataJson');
        if (String.isBlank(dataJson)) {
            throw new AuraHandledException('Nothing to save.');
        }
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
            Id investigationId = payload.containsKey('investigationId')
                ? (Id) String.valueOf(payload.get('investigationId'))
                : null;
            Id verificationId = payload.containsKey('verificationId')
                ? (Id) String.valueOf(payload.get('verificationId'))
                : null;
            String fiLabel = payload.containsKey('fiLabel')
                ? String.valueOf(payload.get('fiLabel'))
                : null;
            if (investigationId == null) {
                throw new AuraHandledException('Investigation Id is required.');
            }

            Id payloadApplicantId = payload.containsKey('applicantId')
                ? (Id) String.valueOf(payload.get('applicantId'))
                : null;
            Verification__c verification;
            if (verificationId != null) {
                List<Verification__c> verifications = fetchVerifications(
                    'Id = :verificationId AND Investigations__r.Type_of_Investigation__c = :typeFi',
                    new Map<String, Object>{ 'verificationId' => verificationId, 'typeFi' => TYPE_FI },
                    null,
                    1
                );
                if (verifications.isEmpty()) {
                    throw new AuraHandledException('Verification record not found.');
                }
                verification = verifications[0];
            } else {
                verification = getOrCreateVerification(investigationId, fiLabel, payloadApplicantId);
                if (verification == null) {
                    throw new AuraHandledException('Verification record not found.');
                }
                verificationId = verification.Id;
            }

            Boolean submittedByFiUser = payload.get('submittedByFiUser') == true;

            Map<String, Object> formData = new Map<String, Object>();
            if (payload.containsKey('formData') && payload.get('formData') instanceof Map<String, Object>) {
                formData = (Map<String, Object>) payload.get('formData');
            }

            Boolean isNiOfficeAddressFi = payload.get('isNonIndividual') == true
                && NI_OFFICE_ADDRESS_FI_LABELS.contains(fiLabel);

            if (!formData.isEmpty()) {
                if (isNiOfficeAddressFi) {
                    persistNiVerificationFormData(verification, formData);
                } else if (RESIDENCE_FI_LABELS.contains(fiLabel)) {
                    verification.Residence_Type__c = parseString(formData, 'residenceType');
                    verification.Landmark__c = parseString(formData, 'landmark');
                    verification.Phone_Number__c = parseString(formData, 'phoneNumber');
                    verification.Mobile__c = parseString(formData, 'mobile');
                    verification.Customer_House_Same__c = parseBoolean(formData, 'customerHouseSame');
                    verification.Number_of_Dependent__c = parseDecimal(formData, 'numberOfDependent');
                    verification.Number_of_Earning_Member__c = parseDecimal(formData, 'numberOfEarningMember');
                    verification.Name_of_Person_Met__c = parseString(formData, 'nameOfPersonMet');
                    verification.Relationship__c = parseString(formData, 'relationship');
                    verification.Years_in_City__c = parseDecimal(formData, 'yearsInCity');
                    verification.Years_in_Residence__c = parseDecimal(formData, 'yearsInResidence');
                    verification.KYC_Latitude__c = parseDecimal(formData, 'kycLatitude');
                    verification.KYC_Longitude__c = parseDecimal(formData, 'kycLongitude');
                    verification.Latitude__c = parseDecimal(formData, 'fiLatitude');
                    verification.Longitude__c = parseDecimal(formData, 'fiLongitude');
                    verification.Coordinates_Verified__c = parseString(formData, 'coordinatesVerified');
                    verification.Coordinates_Distance__c = parseDecimal(formData, 'coordinatesDistance');
                    verification.Profile_to_Product_Match__c = parseString(formData, 'profileToProductMatch');
                    verification.No_of_Attempts__c = parseDecimal(formData, 'noOfAttempts');
                    verification.Observation__c = parseString(formData, 'fiObservation');
                    verification.Feedback__c = parseString(formData, 'fiFeedback');
                } else if (FI_LABEL_OFFICE.equals(fiLabel)) {
                    verification.Landmark__c = parseString(formData, 'landmark');
                    verification.Phone_Number__c = parseString(formData, 'phoneNumber');
                    verification.Mobile__c = parseString(formData, 'mobile');
                    verification.Same_Address_as_in_Application__c = parseString(formData, 'sameAddressAsInApplication');
                    verification.Employer_Business_Name__c = parseString(formData, 'employerBusinessName');
                    verification.Office_Business_Type__c = parseString(formData, 'officeBusinessType');
                    verification.Business_Premise__c = parseString(formData, 'businessPremise');
                    verification.Name_of_Person_Met__c = parseString(formData, 'nameOfPersonMet');
                    verification.No_of_Attempts__c = parseDecimal(formData, 'noOfAttempts');
                    verification.Observation__c = parseString(formData, 'fiObservation');
                    verification.Feedback__c = parseString(formData, 'fiFeedback');
                    verification.Current_Experience_Years__c = parseDecimal(formData, 'currentExperienceYears');
                    verification.Monthly_Income__c = parseDecimal(formData, 'monthlyIncomeAsPerFI');
                    verification.Applicant_Recognized__c = parseString(formData, 'applicantRecognized');
                    verification.Total_Income__c = parseDecimal(formData, 'incomeAsPerFI');
                }
            }

            if (payload.containsKey('fiDecision') && payload.get('fiDecision') != null) {
                verification.Decision__c = String.valueOf(payload.get('fiDecision'));
            }
            if (payload.containsKey('remarks')) {
                verification.Remarks__c = String.valueOf(payload.get('remarks'));
            }
            if (String.isBlank(verification.Address_Type__c)) {
                verification.Address_Type__c = FI_LABEL_TO_ADDR_TYPE.get(fiLabel);
            }

            if (isNiOfficeAddressFi) {
                applyNiVerificationTimestamps(verification, investigationId, fiLabel, submittedByFiUser);
            }

            if (submittedByFiUser) {
                verification.Submitted_Date__c = System.now();
                verification.Submitted_By__c = UserInfo.getUserId();
                if (DECISION_ACCEPTED.equalsIgnoreCase(verification.Decision__c)
                        || DECISION_REJECTED.equalsIgnoreCase(verification.Decision__c)) {
                    verification.Status__c = verification.Decision__c;
                } else {
                    verification.Status__c = STATUS_COMPLETED;
                }
            } else if (DECISION_ACCEPTED.equalsIgnoreCase(verification.Decision__c)
                    || DECISION_REJECTED.equalsIgnoreCase(verification.Decision__c)) {
                verification.Status__c = verification.Decision__c;
            } else if (!(STATUS_COMPLETED.equalsIgnoreCase(verification.Status__c)
                    || STATUS_ACCEPTED.equalsIgnoreCase(verification.Status__c)
                    || DECISION_REJECTED.equalsIgnoreCase(verification.Status__c))) {
                verification.Status__c = STATUS_IN_PROGRESS;
            }

            update verification;

            if (DECISION_REJECTED.equalsIgnoreCase(verification.Decision__c)) {
                createReFiVerificationIfNeeded(
                    verification,
                    investigationId,
                    fiLabel,
                    payloadApplicantId
                );
            }

            if (submittedByFiUser
                    || DECISION_ACCEPTED.equalsIgnoreCase(verification.Decision__c)
                    || DECISION_REJECTED.equalsIgnoreCase(verification.Decision__c)) {
                List<Verification__c> childVerifications = [
                    SELECT Status__c
                    FROM Verification__c
                    WHERE Investigations__c = :investigationId
                    WITH SECURITY_ENFORCED
                ];
                if (!childVerifications.isEmpty()) {
                    Boolean allCompleted = true;
                    Boolean anyStarted = false;
                    for (Verification__c child : childVerifications) {
                        String status = child.Status__c;
                        Boolean isFinalStatus = STATUS_COMPLETED.equalsIgnoreCase(status)
                            || STATUS_ACCEPTED.equalsIgnoreCase(status)
                            || DECISION_REJECTED.equalsIgnoreCase(status);
                        if (!isFinalStatus) {
                            allCompleted = false;
                        }
                        if (isFinalStatus || STATUS_IN_PROGRESS.equalsIgnoreCase(status)) {
                            anyStarted = true;
                        }
                    }
                    String newStatus = allCompleted
                        ? STATUS_COMPLETED
                        : (anyStarted ? INVESTIGATION_STATUS_IN_PROGRESS : STATUS_INITIATED);
                    update new Investigations__c(Id = investigationId, Status__c = newStatus);
                }
            }

            return new Map<String, Object>{
                'isSuccess' => true,
                'result' => 'Success',
                'message' => 'FI data saved successfully',
                'verificationId' => String.valueOf(verificationId)
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error saving FI data: ' + e.getMessage());
        }
    }

    private static Map<String, Object> updateFiLocation(Map<String, Object> args) {
        Id investigationId = argId(args, 'investigationId');
        if (investigationId == null) {
            investigationId = argId(args, 'recordId');
        }
        Decimal latitude = argDecimal(args, 'latitude');
        Decimal longitude = argDecimal(args, 'longitude');

        if (investigationId == null || latitude == null || longitude == null) {
            throw new AuraHandledException('Investigation Id and coordinates are required.');
        }

        String fiLabel = argStr(args, 'fiLabel');
        Id applicantId = argId(args, 'applicantId');
        Verification__c verification = getOrCreateVerification(investigationId, fiLabel, applicantId);
        if (verification == null) {
            throw new AuraHandledException('Verification record not found.');
        }
        verification.Latitude__c = latitude;
        verification.Longitude__c = longitude;
        verification.KYC_Latitude__c = latitude;
        verification.KYC_Longitude__c = longitude;

        Double earthRadiusMeters = 6371000;
        Double lat1Rad = (Double.valueOf(String.valueOf(verification.KYC_Latitude__c)) * Math.PI) / 180;
        Double lat2Rad = (Double.valueOf(String.valueOf(latitude)) * Math.PI) / 180;
        Double deltaLat = (Double.valueOf(String.valueOf(latitude - verification.KYC_Latitude__c)) * Math.PI) / 180;
        Double deltaLon = (Double.valueOf(String.valueOf(longitude - verification.KYC_Longitude__c)) * Math.PI) / 180;
        Double a = Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2)
            + Math.cos(lat1Rad) * Math.cos(lat2Rad)
            * Math.sin(deltaLon / 2) * Math.sin(deltaLon / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        Decimal distanceMeters = Decimal.valueOf(earthRadiusMeters * c).setScale(2);
        verification.Coordinates_Distance__c = distanceMeters;
        verification.Coordinates_Verified__c = distanceMeters <= FI_COORDINATE_VERIFY_THRESHOLD_METERS ? 'Yes' : 'No';

        update verification;

        Map<String, Object> response = new Map<String, Object>{
            'isSuccess' => true,
            'result' => 'Success',
            'fiLatitude' => String.valueOf(latitude),
            'fiLongitude' => String.valueOf(longitude),
            'kycLatitude' => String.valueOf(latitude),
            'kycLongitude' => String.valueOf(longitude)
        };
        if (verification.Coordinates_Distance__c != null) {
            response.put('coordinatesDistance', String.valueOf(verification.Coordinates_Distance__c));
        }
        if (String.isNotBlank(verification.Coordinates_Verified__c)) {
            response.put('coordinatesVerified', verification.Coordinates_Verified__c);
        }
        return response;
    }

    private static Map<String, Object> getApplicantProfile(Map<String, Object> args) {
        ApplicantProfileWrapper wrapper = new ApplicantProfileWrapper();
        String applicantId = argStr(args, 'applicantId');
        if (String.isBlank(applicantId)) {
            return mapResponse(wrapper);
        }
        List<Applicant__c> applicants = [
            SELECT Income_Category__c, Profile__c, Applicant_Type__c, Is_Income_Available__c
            FROM Applicant__c
            WHERE Id = :((Id) applicantId)
            LIMIT 1
        ];
        if (applicants.isEmpty()) {
            return mapResponse(wrapper);
        }
        Applicant__c applicant = applicants[0];
        wrapper.category = applicant.Income_Category__c;
        wrapper.subBucket = applicant.Profile__c;
        wrapper.applicantType = applicant.Applicant_Type__c;
        wrapper.isIncomeAvailable = applicant.Is_Income_Available__c;
        return mapResponse(wrapper);
    }

    private static Map<String, Object> saveFiSignature(Map<String, Object> args) {
        Id checklistId = argId(args, 'documentId');
        String base64Data = argStr(args, 'base64Data');
        String fileName = argStr(args, 'fileName');

        if (checklistId == null || String.isBlank(base64Data)) {
            throw new AuraHandledException('Document Id and signature data are required.');
        }

        List<Document_Checklist__c> rows = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Id = :checklistId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Document checklist record not found.');
        }

        String pathOnClient = String.isNotBlank(fileName) ? fileName : 'Signature.png';
        ContentVersion version = new ContentVersion();
        version.Title = 'Signature';
        version.PathOnClient = pathOnClient;
        version.VersionData = EncodingUtil.base64Decode(base64Data);
        version.FirstPublishLocationId = checklistId;
        insert version;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        update new Document_Checklist__c(
            Id = checklistId,
            ContentVersionId__c = insertedVersion.Id
        );

        return new Map<String, Object>{
            'isSuccess' => true,
            'documentId' => String.valueOf(checklistId),
            'contentDocumentId' => String.valueOf(insertedVersion.ContentDocumentId)
        };
    }

    private static Map<String, Object> getDocumentPreview(Map<String, Object> args) {
        DocumentContext docCtx = resolveDocumentContext(args);
        Id applicationId = docCtx.applicationId;
        Id applicantId = docCtx.applicantId;
        Id verificationId = docCtx.verificationId;
        String fiLabel = docCtx.fiLabel;

        Map<String, Object> previewMap = new Map<String, Object>();
        if (verificationId == null
                && (applicationId == null || applicantId == null || String.isBlank(fiLabel))) {
            return previewMap;
        }

        Set<String> scopedDocumentTypes = buildFiDocumentTypes(fiLabel);
        List<Document_Checklist__c> rows = fetchDocumentChecklists(
            verificationId,
            applicationId,
            applicantId,
            scopedDocumentTypes,
            null
        );

        Set<Id> versionIds = new Set<Id>();
        for (Document_Checklist__c row : rows) {
            if (row.ContentVersionId__c != null) {
                versionIds.add(row.ContentVersionId__c);
            }
        }

        Map<Id, ContentVersion> versionsById = getContentVersionsById(versionIds);
        Map<String, Document_Checklist__c> latestByBaseType = new Map<String, Document_Checklist__c>();
        String fiLabelSuffix = ' - ' + String.valueOf(fiLabel).trim();
        for (Document_Checklist__c row : rows) {
            String scopedType = row.Document_Type__c;
            String baseType = String.isBlank(scopedType)
                ? scopedType
                : (scopedType.endsWith(fiLabelSuffix)
                    ? scopedType.substring(0, scopedType.length() - fiLabelSuffix.length()).trim()
                    : scopedType);
            if (String.isBlank(baseType) || latestByBaseType.containsKey(baseType)) {
                continue;
            }
            latestByBaseType.put(baseType, row);
        }

        for (String baseType : latestByBaseType.keySet()) {
            Document_Checklist__c row = latestByBaseType.get(baseType);
            ContentVersion version = row.ContentVersionId__c != null
                ? versionsById.get(row.ContentVersionId__c)
                : null;
            if (version == null || version.ContentDocumentId == null) {
                continue;
            }
            previewMap.put(baseType, new Map<String, Object>{
                'documentId' => String.valueOf(row.Id),
                'contentVersionId' => row.ContentVersionId__c != null
                    ? String.valueOf(row.ContentVersionId__c)
                    : '',
                'contentDocumentId' => String.valueOf(version.ContentDocumentId),
                'fileType' => version.FileExtension,
                'fileName' => String.isNotBlank(version.Title) ? version.Title : row.Name,
                'documentType' => baseType,
                'timeStamp' => version.CreatedDate != null ? version.CreatedDate.format() : null
            });
        }
        return previewMap;
    }

    private static Map<String, Object> saveDocument(Map<String, Object> args, String action) {
        DocumentContext docCtx = resolveDocumentContext(args);
        Id applicationId = docCtx.applicationId;
        Id applicantId = docCtx.applicantId;
        Id verificationId = docCtx.verificationId;
        String fiLabel = docCtx.fiLabel;

        if (ACTION_INIT_OR_GET_FI_DOCUMENT.equalsIgnoreCase(action)) {
            String documentType = argStr(args, 'documentType');
            if (applicationId == null || applicantId == null || String.isBlank(documentType)) {
                throw new AuraHandledException('Application Id, Applicant Id, and document type are required.');
            }

            String scopedDocumentType = getDocumentType(documentType, fiLabel);
            Id checklistId = findOrCreateDocumentChecklist(
                verificationId,
                applicationId,
                applicantId,
                scopedDocumentType
            );
            return new Map<String, Object>{
                'isSuccess' => true,
                'documentId' => String.valueOf(checklistId),
                'documentType' => scopedDocumentType
            };
        }

        if (ACTION_LINK_FI_DOCUMENT.equalsIgnoreCase(action)) {
            String contentDocumentId = argStr(args, 'contentDocumentId');
            String contentVersionId = argStr(args, 'contentVersionId');
            if (String.isBlank(contentDocumentId) && String.isBlank(contentVersionId)) {
                throw new AuraHandledException('Uploaded document reference is missing.');
            }

            Id checklistId = argId(args, 'documentId');
            if (checklistId == null) {
                String documentType = argStr(args, 'documentType');
                if (String.isBlank(fiLabel)) {
                    fiLabel = argStr(args, 'fiLabel');
                }
                if (applicationId == null || applicantId == null || String.isBlank(documentType)) {
                    throw new AuraHandledException('Application Id, Applicant Id, and document type are required.');
                }
                checklistId = findOrCreateDocumentChecklist(
                    verificationId,
                    applicationId,
                    applicantId,
                    getDocumentType(documentType, fiLabel)
                );
            }

            if (String.isNotBlank(contentVersionId)) {
                linkDocumentToChecklist(checklistId, contentVersionId, null, verificationId);
            } else {
                linkDocumentToChecklist(checklistId, null, contentDocumentId, verificationId);
            }
            return new Map<String, Object>{
                'isSuccess' => true,
                'documentId' => String.valueOf(checklistId),
                'contentDocumentId' => contentDocumentId,
                'contentVersionId' => contentVersionId
            };
        }

        throw new CalloutException('Unknown document action: ' + action);
    }

    private static Id findOrCreateDocumentChecklist(
            Id verificationId,
            Id applicationId,
            Id applicantId,
            String scopedDocumentType) {
        List<Document_Checklist__c> existingRows = fetchDocumentChecklists(
            verificationId,
            applicationId,
            applicantId,
            new Set<String>{ scopedDocumentType },
            1
        );
        if (!existingRows.isEmpty()) {
            return existingRows[0].Id;
        }

        Document_Checklist__c checklist = buildFiDocumentChecklist(
            scopedDocumentType,
            applicationId,
            applicantId,
            verificationId
        );
        insert checklist;
        return checklist.Id;
    }

    private static void linkDocumentToChecklist(
            Id checklistId,
            String contentVersionId,
            String contentDocumentId,
            Id verificationId) {
        String resolvedVersionId = contentVersionId;
        if (String.isBlank(resolvedVersionId) && String.isNotBlank(contentDocumentId)) {
            List<ContentVersion> versions = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
                LIMIT 1
            ];
            resolvedVersionId = versions.isEmpty() ? null : versions[0].Id;
        }

        if (String.isNotBlank(resolvedVersionId)) {
            Document_Checklist__c checklistUpdate = new Document_Checklist__c(
                Id = checklistId,
                ContentVersionId__c = resolvedVersionId
            );
            if (verificationId != null) {
                checklistUpdate.Verification__c = verificationId;
            }
            update checklistUpdate;
            return;
        }

        if (String.isBlank(contentDocumentId)) {
            return;
        }

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :checklistId
              AND ContentDocumentId = :contentDocumentId
            LIMIT 1
        ];
        if (links.isEmpty()) {
            insert new ContentDocumentLink(
                LinkedEntityId = checklistId,
                ContentDocumentId = contentDocumentId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        }
        if (verificationId != null) {
            update new Document_Checklist__c(
                Id = checklistId,
                Verification__c = verificationId
            );
        }
    }

    private static DocumentContext resolveDocumentContext(Map<String, Object> args) {
        DocumentContext docCtx = new DocumentContext();
        docCtx.applicationId = argId(args, 'applicationId');
        docCtx.applicantId = argId(args, 'applicantId');
        docCtx.fiLabel = argStr(args, 'fiLabel');
        docCtx.verificationId = argId(args, 'verificationId');

        Verification__c verification = null;
        if (docCtx.verificationId != null) {
            List<Verification__c> rows = fetchVerifications(
                VERIFICATION_CONTEXT_FIELDS,
                'Id = :verificationId AND Investigations__r.Type_of_Investigation__c = :typeFi',
                new Map<String, Object>{ 'verificationId' => docCtx.verificationId, 'typeFi' => TYPE_FI },
                null,
                1
            );
            verification = rows.isEmpty() ? null : rows[0];
        } else {
            Id investigationId = argId(args, 'investigationId');
            if (investigationId == null) {
                investigationId = argId(args, 'recordId');
            }
            if (investigationId != null && String.isNotBlank(docCtx.fiLabel)) {
                verification = getOrCreateVerification(investigationId, docCtx.fiLabel, docCtx.applicantId);
                if (verification != null) {
                    docCtx.verificationId = verification.Id;
                }
            }
        }

        if (verification != null) {
            if (docCtx.applicationId == null && verification.Investigations__r != null) {
                docCtx.applicationId = verification.Investigations__r.Application__c;
            }
            if (docCtx.applicantId == null) {
                docCtx.applicantId = verification.Applicant__c;
            }
            if (String.isBlank(docCtx.fiLabel)) {
                docCtx.fiLabel = getFiLabel(verification.Name, true);
            }
        }

        if (docCtx.applicationId == null || docCtx.applicantId == null) {
            Id investigationId = argId(args, 'investigationId');
            if (investigationId == null) {
                investigationId = argId(args, 'recordId');
            }
            if (investigationId != null) {
                List<Investigations__c> investigations = [
                    SELECT Id, Name, Application__c,
                        (SELECT Applicant__c FROM Verifications__r ORDER BY CreatedDate ASC LIMIT 1)
                    FROM Investigations__c
                    WHERE Id = :investigationId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                if (!investigations.isEmpty()) {
                    Investigations__c investigation = investigations[0];
                    if (docCtx.applicationId == null) {
                        docCtx.applicationId = investigation.Application__c;
                    }
                    if (docCtx.applicantId == null) {
                        if (!investigation.Verifications__r.isEmpty()) {
                            docCtx.applicantId = investigation.Verifications__r[0].Applicant__c;
                        } else {
                            docCtx.applicantId = getApplicantId(investigation);
                        }
                    }
                }
            }
        }

        if (docCtx.applicationId != null) {
            args.put('applicationId', String.valueOf(docCtx.applicationId));
        }
        if (docCtx.applicantId != null) {
            args.put('applicantId', String.valueOf(docCtx.applicantId));
        }
        return docCtx;
    }

    private static List<Document_Checklist__c> fetchDocumentChecklists(
            Id verificationId,
            Id applicationId,
            Id applicantId,
            Set<String> documentTypes,
            Integer limitSize) {
        if (verificationId != null) {
            String soql = 'SELECT Id, Name, Document_Type__c, ContentVersionId__c ' +
                'FROM Document_Checklist__c ' +
                'WHERE Verification__c = :verificationId ' +
                'AND Document_Type__c IN :documentTypes ' +
                'AND Is_Active__c = true ' +
                'ORDER BY CreatedDate DESC';
            if (limitSize != null) {
                soql += ' LIMIT ' + limitSize;
            }
            return Database.queryWithBinds(
                soql,
                new Map<String, Object>{
                    'verificationId' => verificationId,
                    'documentTypes' => documentTypes
                },
                AccessLevel.USER_MODE
            );
        }

        String soql = 'SELECT Id, Name, Document_Type__c, ContentVersionId__c ' +
            'FROM Document_Checklist__c ' +
            'WHERE Application__c = :applicationId ' +
            'AND Applicant__c = :applicantId ' +
            'AND Document_Type__c IN :documentTypes ' +
            'AND Is_Active__c = true ' +
            'ORDER BY CreatedDate DESC';
        if (limitSize != null) {
            soql += ' LIMIT ' + limitSize;
        }
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'applicationId' => applicationId,
                'applicantId' => applicantId,
                'documentTypes' => documentTypes
            },
            AccessLevel.USER_MODE
        );
    }

    private static Document_Checklist__c buildFiDocumentChecklist(
            String documentType,
            Id applicationId,
            Id applicantId,
            Id verificationId) {
        Document_Checklist__c checklist = new Document_Checklist__c();
        checklist.Name = documentType + ' - Document';
        checklist.Document_Type__c = documentType;
        checklist.Application__c = applicationId;
        checklist.Applicant__c = applicantId;
        checklist.Is_Active__c = true;
        if (verificationId != null) {
            checklist.Verification__c = verificationId;
        }
        return checklist;
    }

    private static List<Verification__c> fetchVerifications(
            String whereClause,
            Map<String, Object> bindVars,
            String orderBy,
            Integer limitSize) {
        return fetchVerifications(FI_VERIFICATION_SOQL_FIELDS, whereClause, bindVars, orderBy, limitSize);
    }

    private static List<Verification__c> fetchVerifications(
            String selectFields,
            String whereClause,
            Map<String, Object> bindVars,
            String orderBy,
            Integer limitSize) {
        String soql = 'SELECT ' + selectFields + ' FROM Verification__c WHERE ' + whereClause;
        if (String.isNotBlank(orderBy)) {
            soql += ' ORDER BY ' + orderBy;
        }
        if (limitSize != null) {
            soql += ' LIMIT ' + limitSize;
        }
        return Database.queryWithBinds(soql, bindVars, AccessLevel.USER_MODE);
    }

    private static FIDataWrapper buildFiDataWrapper(
            Investigations__c investigation,
            Verification__c verification) {
        String fiLabel = verification != null
            ? getFiLabel(verification.Name, true)
            : getFiLabel(investigation.Name, false);
        Id applicantId = verification != null ? verification.Applicant__c : null;
        Applicant__c applicant = verification != null ? verification.Applicant__r : null;

        Map<String, Object> formData = new Map<String, Object>();
        if (applicantId != null) {
            String addressType = FI_LABEL_TO_ADDRESS_TYPE.get(fiLabel);
            if (String.isNotBlank(addressType)) {
                ApplicantAddressBundle addressBundle = fetchAddressBundle(
                    null,
                    applicantId,
                    FI_LABEL_REGISTERED.equals(fiLabel)
                );
                Map<String, AddressWrapper> addresses = addressBundle.byApplicant.containsKey(applicantId)
                    ? addressBundle.byApplicant.get(applicantId)
                    : null;
                AddressWrapper address = addresses != null ? addresses.get(addressType) : null;
                if (address != null && String.isNotBlank(address.line1)) {
                    putFormValue(formData, 'addressLine1', address.line1);
                    putFormValue(formData, 'addressLine2', address.line2);
                    putFormValue(formData, 'city', address.city);
                    putFormValue(formData, 'state', address.state);
                    putFormValue(formData, 'pinCode', address.pinCode);
                }
            }
        }

        if (verification == null) {
            verification = getOrCreateVerification(investigation.Id, fiLabel, applicantId);
        }
        Id verificationId = verification != null ? verification.Id : null;

        if (verification != null) {
            putFormValue(formData, 'residenceType', verification.Residence_Type__c);
            putFormValue(formData, 'landmark', verification.Landmark__c);
            putFormValue(formData, 'phoneNumber', verification.Phone_Number__c);
            putFormValue(formData, 'mobile', verification.Mobile__c);
            putFormValue(formData, 'customerHouseSame', verification.Customer_House_Same__c);
            putFormValue(formData, 'numberOfDependent', verification.Number_of_Dependent__c);
            putFormValue(formData, 'numberOfEarningMember', verification.Number_of_Earning_Member__c);
            putFormValue(formData, 'nameOfPersonMet', verification.Name_of_Person_Met__c);
            putFormValue(formData, 'relationship', verification.Relationship__c);
            putFormValue(formData, 'yearsInCity', verification.Years_in_City__c);
            putFormValue(formData, 'yearsInResidence', verification.Years_in_Residence__c);
            putFormValue(formData, 'kycLatitude', verification.KYC_Latitude__c);
            putFormValue(formData, 'kycLongitude', verification.KYC_Longitude__c);
            putFormValue(formData, 'fiLatitude', verification.Latitude__c);
            putFormValue(formData, 'fiLongitude', verification.Longitude__c);
            putFormValue(formData, 'coordinatesVerified', verification.Coordinates_Verified__c);
            putFormValue(formData, 'coordinatesDistance', verification.Coordinates_Distance__c);
            putFormValue(formData, 'sameAddressAsInApplication', verification.Same_Address_as_in_Application__c);
            putFormValue(formData, 'employerBusinessName', verification.Employer_Business_Name__c);
            putFormValue(formData, 'officeBusinessType', verification.Office_Business_Type__c);
            putFormValue(formData, 'businessPremise', verification.Business_Premise__c);
            putFormValue(formData, 'currentExperienceYears', verification.Current_Experience_Years__c);
            putFormValue(formData, 'monthlyIncomeAsPerFI', verification.Monthly_Income__c);
            putFormValue(formData, 'applicantRecognized', verification.Applicant_Recognized__c);
            putFormValue(formData, 'incomeAsPerFI', verification.Total_Income__c);
            putFormValue(formData, 'profileToProductMatch', verification.Profile_to_Product_Match__c);
            putFormValue(formData, 'noOfAttempts', verification.No_of_Attempts__c);
            putFormValue(formData, 'fiObservation', verification.Observation__c);
            putFormValue(formData, 'fiFeedback', verification.Feedback__c);
        }

        String verificationStatus = verification != null && String.isNotBlank(verification.Status__c)
            ? verification.Status__c
            : STATUS_INITIATED;

        Document_CheckList__c poiDocument = applicantId != null
            ? getPoiIdentityDocumentsByApplicant(new Set<Id>{ applicantId }).get(applicantId)
            : null;

        FIDataWrapper wrapper = new FIDataWrapper();
        wrapper.investigationId = investigation.Id;
        wrapper.verificationId = verificationId;
        wrapper.applicationId = investigation.Application__c;
        wrapper.applicantId = applicantId != null ? String.valueOf(applicantId) : '';
        wrapper.fiLabel = fiLabel;
        wrapper.fiStatus = verificationStatus;
        wrapper.fiDecision = verification != null ? verification.Decision__c : '';
        wrapper.remarks = verification != null ? verification.Remarks__c : '';
        wrapper.applicantName = getApplicantName(applicant, poiDocument);
        Application__c productSource = new Application__c(
            Product__c = investigation.Application__r.Product__c,
            Sub_Product__c = investigation.Application__r.Sub_Product__c
        );
        wrapper.productType = String.isNotBlank(productSource.Sub_Product__c)
                && !'Null'.equalsIgnoreCase(productSource.Sub_Product__c)
            ? productSource.Sub_Product__c.trim()
            : (productSource.Product__c != null ? productSource.Product__c.trim() : '');
        wrapper.isCompleted = STATUS_COMPLETED.equalsIgnoreCase(verificationStatus)
            || STATUS_ACCEPTED.equalsIgnoreCase(verificationStatus)
            || DECISION_REJECTED.equalsIgnoreCase(verificationStatus)
            || DECISION_ACCEPTED.equalsIgnoreCase(wrapper.fiDecision)
            || DECISION_REJECTED.equalsIgnoreCase(wrapper.fiDecision);
        wrapper.isRejected = DECISION_REJECTED.equalsIgnoreCase(verificationStatus)
            || DECISION_REJECTED.equalsIgnoreCase(wrapper.fiDecision);
        wrapper.isLocked = wrapper.isCompleted == true;
        wrapper.isSubmitted = verification != null && verification.Submitted_Date__c != null;
        wrapper.isNonIndividual = resolveIsNonIndividualFi(investigation.Application__c);
        wrapper.investigationCaseName = investigation.Name;
        if (wrapper.isNonIndividual == true && NI_OFFICE_ADDRESS_FI_LABELS.contains(fiLabel)) {
            enrichNiOfficeFormData(formData, verification, applicant, investigation, fiLabel);
            if (verification != null
                    && (verification.Lead_Gen_Time__c == null || verification.Request_Gen_Time__c == null)) {
                applyNiVerificationTimestamps(
                    verification,
                    investigation != null ? investigation.Id : null,
                    fiLabel,
                    false
                );
                update verification;
                putFormValue(formData, 'leadGenTime', formatDateTimeLocal(verification.Lead_Gen_Time__c));
                putFormValue(formData, 'requestGenTime', formatDateTimeLocal(verification.Request_Gen_Time__c));
            }
        }
        wrapper.formDataJson = JSON.serialize(formData);
        wrapper.category = applicant != null ? applicant.Income_Category__c : '';
        wrapper.profile = applicant != null ? applicant.Profile__c : '';

        String addressProofType = FI_LABEL_TO_ADDRESS_PROOF.get(fiLabel);
        if (String.isBlank(addressProofType) || applicantId == null || investigation.Application__c == null) {
            wrapper.isAddressProofUploaded = false;
            wrapper.addressProofDocuments = new List<Map<String, String>>();
        } else {
            List<Document_Checklist__c> rows;
            if (verificationId != null) {
                rows = [
                    SELECT Id, Name, ContentVersionId__c
                    FROM Document_Checklist__c
                    WHERE Verification__c = :verificationId
                      AND Document_Type__c = :addressProofType
                      AND Is_Active__c = true
                      AND ContentVersionId__c != null
                    WITH SECURITY_ENFORCED
                    ORDER BY CreatedDate DESC
                ];
            } else {
                rows = [
                    SELECT Id, Name, ContentVersionId__c
                    FROM Document_Checklist__c
                    WHERE Applicant__c = :applicantId
                      AND Application__c = :investigation.Application__c
                      AND Document_Type__c = :addressProofType
                      AND Is_Active__c = true
                      AND ContentVersionId__c != null
                    WITH SECURITY_ENFORCED
                    ORDER BY CreatedDate DESC
                ];
            }
            wrapper.addressProofDocuments = new List<Map<String, String>>();
            if (!rows.isEmpty()) {
                Set<Id> versionIds = new Set<Id>();
                for (Document_Checklist__c row : rows) {
                    versionIds.add(row.ContentVersionId__c);
                }
                Map<Id, ContentVersion> versionsById = getContentVersionsById(versionIds);
                for (Document_Checklist__c row : rows) {
                    ContentVersion version = versionsById.get(row.ContentVersionId__c);
                    if (version == null || version.ContentDocumentId == null) {
                        continue;
                    }
                    wrapper.addressProofDocuments.add(new Map<String, String>{
                        'ID' => String.valueOf(version.ContentDocumentId),
                        'Name' => String.isNotBlank(row.Name) ? row.Name : 'Address proof'
                    });
                }
            }
            wrapper.isAddressProofUploaded = !wrapper.addressProofDocuments.isEmpty();
        }

        return wrapper;
    }

    private static Verification__c getOrCreateVerification(
            Id investigationId,
            String fiLabel,
            Id applicantId) {
        if (investigationId == null) {
            return null;
        }

        List<Verification__c> verifications = fetchVerifications(
            'Investigations__c = :investigationId AND Investigations__r.Type_of_Investigation__c = :typeFi',
            new Map<String, Object>{ 'investigationId' => investigationId, 'typeFi' => TYPE_FI },
            'CreatedDate DESC',
            null
        );
        Verification__c activeVerification = selectVerificationForFiLabel(verifications, fiLabel);
        if (activeVerification != null && isOpenVerification(activeVerification)) {
            return activeVerification;
        }
        if (String.isBlank(fiLabel) && !verifications.isEmpty()) {
            Verification__c latestVerification = verifications[0];
            if (isOpenVerification(latestVerification)) {
                return latestVerification;
            }
        }

        List<Investigations__c> investigations = [
            SELECT Id, Name, Application__c, Application__r.CreatedDate,
                (SELECT Applicant__c FROM Verifications__r ORDER BY CreatedDate ASC LIMIT 1)
            FROM Investigations__c
            WHERE Id = :investigationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (investigations.isEmpty()) {
            return null;
        }
        Investigations__c investigation = investigations[0];
        if (applicantId == null) {
            if (!investigation.Verifications__r.isEmpty()) {
                applicantId = investigation.Verifications__r[0].Applicant__c;
            } else {
                applicantId = getApplicantId(investigation);
            }
        }
        if (String.isBlank(fiLabel)) {
            fiLabel = getFiLabel(investigation.Name, false);
            if (!KNOWN_FI_LABELS.contains(fiLabel)) {
                fiLabel = FI_LABEL_CURRENT;
            }
        }
        Verification__c verification = buildVerificationRecord(investigation, applicantId, fiLabel);
        insert verification;
        return verification;
    }

    private static Map<Id, ContentVersion> getContentVersionsById(Set<Id> versionIds) {
        Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>();
        if (versionIds == null || versionIds.isEmpty()) {
            return versionsById;
        }
        for (ContentVersion version : [
            SELECT Id, ContentDocumentId, FileExtension, Title, CreatedDate
            FROM ContentVersion
            WHERE Id IN :versionIds
        ]) {
            versionsById.put(version.Id, version);
        }
        return versionsById;
    }

    private static String argStr(Map<String, Object> args, String key) {
        if (args == null || !args.containsKey(key) || args.get(key) == null) {
            return null;
        }
        return String.valueOf(args.get(key));
    }

    private static Id argId(Map<String, Object> args, String key) {
        String value = argStr(args, key);
        return String.isNotBlank(value) ? (Id) value : null;
    }

    private static Decimal argDecimal(Map<String, Object> args, String key) {
        if (args == null || !args.containsKey(key) || args.get(key) == null) {
            return null;
        }
        Object value = args.get(key);
        return value instanceof Decimal ? (Decimal) value : Decimal.valueOf(String.valueOf(value));
    }

    private static String parseString(Map<String, Object> formData, String key) {
        if (formData == null || !formData.containsKey(key) || formData.get(key) == null) {
            return null;
        }
        String value = String.valueOf(formData.get(key)).trim();
        return String.isBlank(value) ? null : value;
    }

    private static Decimal parseDecimal(Map<String, Object> formData, String key) {
        String value = parseString(formData, key);
        return String.isBlank(value) ? null : Decimal.valueOf(value);
    }

    private static Boolean parseBoolean(Map<String, Object> formData, String key) {
        if (formData == null || !formData.containsKey(key) || formData.get(key) == null) {
            return false;
        }
        Object raw = formData.get(key);
        return raw instanceof Boolean ? (Boolean) raw : Boolean.valueOf(String.valueOf(raw));
    }

    private static DateTime parseDateTime(Map<String, Object> formData, String key) {
        String value = parseString(formData, key);
        if (String.isBlank(value)) {
            return null;
        }
        String normalized = value.replace('T', ' ');
        if (normalized.length() == 16) {
            normalized += ':00';
        }
        try {
            return DateTime.valueOf(normalized);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String formatDateTimeLocal(DateTime value) {
        if (value == null) {
            return null;
        }
        return value.format('yyyy-MM-dd HH:mm', UserInfo.getTimeZone().getID()).replace(' ', 'T');
    }

    private static Map<String, Object> mapResponse(Object data) {
        return data == null ? null : (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(data));
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

    private static String getApplicantName(Applicant__c applicant, Document_CheckList__c poiDocument) {
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

    private static Boolean isOpenVerification(Verification__c verification) {
        if (verification == null) {
            return false;
        }
        String status = verification.Status__c;
        if (String.isNotBlank(status)) {
            String normalizedStatus = status.trim();
            if (STATUS_COMPLETED.equalsIgnoreCase(normalizedStatus)
                || STATUS_ACCEPTED.equalsIgnoreCase(normalizedStatus)
                || DECISION_REJECTED.equalsIgnoreCase(normalizedStatus)) {
                return false;
            }
        }
        String decision = verification.Decision__c;
        if (String.isNotBlank(decision)) {
            String normalizedDecision = decision.trim();
            if (DECISION_ACCEPTED.equalsIgnoreCase(normalizedDecision)
                || DECISION_REJECTED.equalsIgnoreCase(normalizedDecision)) {
                return false;
            }
        }
        return true;
    }

    private static Boolean matchesFiLabel(Verification__c verification, String fiLabel) {
        if (verification == null || String.isBlank(fiLabel)) {
            return false;
        }
        String verificationName = buildVerificationName(fiLabel);
        return verificationName.equalsIgnoreCase(verification.Name)
            || fiLabel.equalsIgnoreCase(getFiLabel(verification.Name, true));
    }

    private static Verification__c selectVerificationForFiLabel(
            List<Verification__c> verifications,
            String fiLabel) {
        if (verifications == null || verifications.isEmpty() || String.isBlank(fiLabel)) {
            return null;
        }

        List<Verification__c> matching = new List<Verification__c>();
        for (Verification__c candidate : verifications) {
            if (matchesFiLabel(candidate, fiLabel)) {
                matching.add(candidate);
            }
        }
        if (matching.isEmpty()) {
            return null;
        }

        for (Verification__c candidate : matching) {
            if (isOpenVerification(candidate)) {
                return candidate;
            }
        }
        return matching[0];
    }

    private static void createReFiVerificationIfNeeded(
            Verification__c rejectedVerification,
            Id investigationId,
            String fiLabel,
            Id applicantId) {
        if (rejectedVerification == null || investigationId == null) {
            return;
        }

        List<Verification__c> siblings = fetchVerifications(
            'Investigations__c = :investigationId AND Investigations__r.Type_of_Investigation__c = :typeFi',
            new Map<String, Object>{ 'investigationId' => investigationId, 'typeFi' => TYPE_FI },
            'CreatedDate DESC',
            null
        );
        String resolvedFiLabel = String.isNotBlank(fiLabel)
            ? fiLabel
            : getFiLabel(rejectedVerification.Name, true);
        Verification__c activeVerification = selectVerificationForFiLabel(siblings, resolvedFiLabel);
        if (activeVerification != null
                && activeVerification.Id != rejectedVerification.Id
                && isOpenVerification(activeVerification)) {
            return;
        }

        List<Investigations__c> investigations = [
            SELECT Id
            FROM Investigations__c
            WHERE Id = :investigationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (investigations.isEmpty()) {
            return;
        }

        Id resolvedApplicantId = applicantId != null
            ? applicantId
            : rejectedVerification.Applicant__c;
        if (String.isBlank(resolvedFiLabel)) {
            resolvedFiLabel = FI_LABEL_CURRENT;
        }
        insert buildVerificationRecord(investigations[0], resolvedApplicantId, resolvedFiLabel);
    }

    private static Verification__c buildVerificationRecord(
            Investigations__c investigation,
            Id applicantId,
            String fiLabel) {
        Verification__c verification = new Verification__c();
        verification.Investigations__c = investigation.Id;
        verification.Applicant__c = applicantId;
        verification.Name = buildVerificationName(fiLabel);
        verification.Address_Type__c = FI_LABEL_TO_ADDR_TYPE.get(fiLabel);
        verification.Status__c = STATUS_INITIATED;
        return verification;
    }

    private static Investigations__c buildInvestigation(
            Id applicationId,
            Applicant__c applicant,
            String status) {
        Investigations__c investigation = new Investigations__c();
        investigation.Application__c = applicationId;
        investigation.Type_of_Investigation__c = TYPE_FI;
        investigation.Status__c = status;
        String applicantName = String.isNotBlank(applicant.Name)
            ? applicant.Name.trim()
            : (String.isBlank(applicant.Applicant_Type__c) ? APPLICANT_TYPE_BORROWER : applicant.Applicant_Type__c);
        investigation.Name = INVESTIGATION_NAME_PREFIX + INVESTIGATION_NAME_SEPARATOR + applicantName;
        return investigation;
    }

    private static String buildVerificationName(String fiLabel) {
        return String.isNotBlank(fiLabel) ? fiLabel + VERIFICATION_NAME_SUFFIX : 'FI' + VERIFICATION_NAME_SUFFIX;
    }

    private static String buildVerificationDedupeKey(Id applicantId, String fiLabel) {
        return String.valueOf(applicantId) + '|' + fiLabel.trim().toLowerCase();
    }

    private static String getFiLabel(String recordName, Boolean fromVerification) {
        if (String.isBlank(recordName)) {
            return '';
        }
        String normalized = recordName.trim();
        if (fromVerification == true && normalized.endsWithIgnoreCase(VERIFICATION_NAME_SUFFIX)) {
            return normalized.substring(0, normalized.length() - VERIFICATION_NAME_SUFFIX.length()).trim();
        }
        Integer separatorIndex = normalized.indexOf(INVESTIGATION_NAME_SEPARATOR);
        return separatorIndex < 0 ? normalized : normalized.substring(0, separatorIndex).trim();
    }

    private static Id getApplicantIdFromName(
            String investigationName,
            Map<String, Id> applicantIdByDisplayName) {
        if (String.isBlank(investigationName) || applicantIdByDisplayName == null || applicantIdByDisplayName.isEmpty()) {
            return null;
        }
        Integer separatorIndex = investigationName.indexOf(INVESTIGATION_NAME_SEPARATOR);
        if (separatorIndex < 0) {
            return null;
        }
        return applicantIdByDisplayName.get(
            investigationName.substring(separatorIndex + INVESTIGATION_NAME_SEPARATOR.length()).trim().toLowerCase()
        );
    }

    private static Id getApplicantId(Investigations__c investigation) {
        if (investigation == null || investigation.Application__c == null) {
            return null;
        }
        Map<String, Id> applicantIdByDisplayName = new Map<String, Id>();
        List<Applicant__c> applicants = [
            SELECT Id, Name, Company_Name__c, Customer_First_Name__c, Customer_Last_Name__c
            FROM Applicant__c
            WHERE Application__c = :investigation.Application__c
              AND In_Active_Applicant__c = false
        ];
        Set<Id> applicantIds = new Set<Id>();
        for (Applicant__c applicant : applicants) {
            applicantIds.add(applicant.Id);
        }
        Map<Id, Document_CheckList__c> poiByApplicantId = getPoiIdentityDocumentsByApplicant(applicantIds);
        for (Applicant__c applicant : applicants) {
            if (String.isNotBlank(applicant.Name)) {
                applicantIdByDisplayName.put(applicant.Name.trim().toLowerCase(), applicant.Id);
            }
            String displayName = getApplicantName(applicant, poiByApplicantId.get(applicant.Id));
            if (String.isNotBlank(displayName)) {
                applicantIdByDisplayName.put(displayName.trim().toLowerCase(), applicant.Id);
            }
        }
        return getApplicantIdFromName(investigation.Name, applicantIdByDisplayName);
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

    private static Boolean hasNiOfficeAddressAvailable(
            Map<String, AddressWrapper> applicantAddresses,
            Applicant_Address__c registeredAddressRow) {
        if (applicantAddresses == null || applicantAddresses.isEmpty()) {
            return false;
        }
        if (applicantAddresses.containsKey(ADDR_OFFICE)) {
            return true;
        }
        return isOfficeSameAsRegistered(registeredAddressRow)
            && applicantAddresses.containsKey(ADDR_REGISTERED);
    }

    private static AddressWrapper copyAddress(AddressWrapper source) {
        if (source == null) {
            return null;
        }
        AddressWrapper copy = new AddressWrapper();
        copy.line1 = source.line1;
        copy.line2 = source.line2;
        copy.city = source.city;
        copy.state = source.state;
        copy.pinCode = source.pinCode;
        return copy;
    }

    private static AddressWrapper buildAddressFromApplicantAddress(Applicant_Address__c row) {
        if (row == null || String.isBlank(row.Address_Line_1__c)) {
            return null;
        }
        AddressWrapper address = new AddressWrapper();
        address.line1 = row.Address_Line_1__c;
        address.line2 = row.Address_Line_2__c;
        address.city = row.City__c;
        address.state = row.State__c;
        address.pinCode = row.PinCode__c;
        return address;
    }

    private static AddressWrapper buildAddressFromKyc(Applicant_KYC__c kyc) {
        if (kyc == null || String.isBlank(kyc.KYC_Address_Line_1__c)) {
            return null;
        }
        AddressWrapper address = new AddressWrapper();
        address.line1 = kyc.KYC_Address_Line_1__c;
        address.line2 = kyc.KYC_Address_Line_2__c;
        address.city = kyc.KYC_City__c;
        address.state = kyc.KYC_State__c;
        address.pinCode = kyc.KYC_Pin_Code__c;
        return address;
    }

    private static void applySameAsAddressRules(ApplicantAddressBundle bundle) {
        for (Id rowApplicantId : bundle.currentRowByApplicant.keySet()) {
            Applicant_Address__c currentRow = bundle.currentRowByApplicant.get(rowApplicantId);
            Map<String, AddressWrapper> applicantAddresses = bundle.byApplicant.get(rowApplicantId);
            if (applicantAddresses == null) {
                applicantAddresses = new Map<String, AddressWrapper>();
                bundle.byApplicant.put(rowApplicantId, applicantAddresses);
            }
            AddressWrapper currentAddress = applicantAddresses.get(ADDR_CURRENT);
            if (currentAddress == null || String.isBlank(currentAddress.line1)) {
                continue;
            }
            if (isSameAsPermanent(currentRow) && !applicantAddresses.containsKey(ADDR_PERMANENT)) {
                applicantAddresses.put(ADDR_PERMANENT, copyAddress(currentAddress));
            }
            if (isSameAsCurrent(currentRow) && !applicantAddresses.containsKey(ADDR_OFFICE)) {
                applicantAddresses.put(ADDR_OFFICE, copyAddress(currentAddress));
            }
        }
    }

    private static void applyNiRegisteredOfficeSameAsRules(ApplicantAddressBundle bundle) {
        for (Id rowApplicantId : bundle.registeredRowByApplicant.keySet()) {
            Applicant_Address__c registeredRow = bundle.registeredRowByApplicant.get(rowApplicantId);
            if (!isOfficeSameAsRegistered(registeredRow)) {
                continue;
            }
            Map<String, AddressWrapper> applicantAddresses = bundle.byApplicant.get(rowApplicantId);
            if (applicantAddresses == null) {
                applicantAddresses = new Map<String, AddressWrapper>();
                bundle.byApplicant.put(rowApplicantId, applicantAddresses);
            }
            if (applicantAddresses.containsKey(ADDR_OFFICE)) {
                continue;
            }
            AddressWrapper registeredAddress = applicantAddresses.get(ADDR_REGISTERED);
            if (registeredAddress != null && String.isNotBlank(registeredAddress.line1)) {
                applicantAddresses.put(ADDR_OFFICE, copyAddress(registeredAddress));
            }
        }
    }

    private static void applyKycAddressFallback(
            ApplicantAddressBundle bundle,
            Id applicationId,
            Id applicantId,
            Set<String> addressTypes) {
        Set<String> resolvedAddressTypes = addressTypes == null || addressTypes.isEmpty()
            ? new Set<String>(KNOWN_ADDRESS_TYPES)
            : addressTypes;
        String kycSoql = 'SELECT ' + KYC_ADDRESS_CHECKLIST_FIELDS +
            ' FROM Document_CheckList__c WHERE Is_Active__c = true AND Address_Type__c IN :addressTypes';
        Map<String, Object> kycBinds = new Map<String, Object>{ 'addressTypes' => resolvedAddressTypes };
        if (applicantId != null) {
            kycSoql += ' AND Applicant__c = :applicantId';
            kycBinds.put('applicantId', applicantId);
        } else {
            kycSoql += ' AND Application__c = :applicationId AND Applicant__c != null';
            kycBinds.put('applicationId', applicationId);
        }
        kycSoql += ' ORDER BY LastModifiedDate DESC';
        List<Document_CheckList__c> kycRows = Database.queryWithBinds(
            kycSoql,
            kycBinds,
            AccessLevel.USER_MODE
        );

        for (Document_CheckList__c row : kycRows) {
            if (row == null || row.Applicant__c == null || String.isBlank(row.Address_Type__c)) {
                continue;
            }
            Id rowApplicantId = row.Applicant__c;
            if (!bundle.byApplicant.containsKey(rowApplicantId)) {
                bundle.byApplicant.put(rowApplicantId, new Map<String, AddressWrapper>());
            }
            Map<String, AddressWrapper> applicantAddresses = bundle.byApplicant.get(rowApplicantId);
            if (applicantAddresses.containsKey(row.Address_Type__c)) {
                AddressWrapper existing = applicantAddresses.get(row.Address_Type__c);
                if (existing != null && String.isNotBlank(existing.line1)) {
                    continue;
                }
            }
            AddressWrapper address = buildAddressFromKyc(row.Applicant_KYC__r);
            if (address != null) {
                applicantAddresses.put(row.Address_Type__c, address);
            }
        }
    }

    private static Map<Id, Map<String, AddressWrapper>> fetchAddresses(Id applicationId, Id applicantId) {
        return fetchAddressBundle(applicationId, applicantId, false).byApplicant;
    }

    private static ApplicantAddressBundle fetchAddressBundle(Id applicationId, Id applicantId) {
        return fetchAddressBundle(applicationId, applicantId, false);
    }

    private static ApplicantAddressBundle fetchAddressBundle(
            Id applicationId,
            Id applicantId,
            Boolean includeRegisteredAddress) {
        ApplicantAddressBundle bundle = new ApplicantAddressBundle();
        if (applicantId == null && applicationId == null) {
            return bundle;
        }

        Set<String> addressTypes = new Set<String>(KNOWN_ADDRESS_TYPES);
        if (includeRegisteredAddress == true) {
            addressTypes.add(ADDR_REGISTERED);
        }

        String addressSoql = 'SELECT ' + APPLICANT_ADDRESS_FIELDS +
            ' FROM Applicant_Address__c WHERE Address_Type__c IN :addressTypes';
        Map<String, Object> addressBinds = new Map<String, Object>{ 'addressTypes' => addressTypes };
        if (applicantId != null) {
            addressSoql += ' AND Applicant__c = :applicantId';
            addressBinds.put('applicantId', applicantId);
        } else {
            addressSoql += ' AND Applicant__r.Application__c = :applicationId AND Applicant__r.In_Active_Applicant__c = false';
            addressBinds.put('applicationId', applicationId);
        }
        addressSoql += ' ORDER BY LastModifiedDate DESC';
        List<Applicant_Address__c> rows = Database.queryWithBinds(
            addressSoql,
            addressBinds,
            AccessLevel.USER_MODE
        );

        for (Applicant_Address__c row : rows) {
            if (row == null || row.Applicant__c == null || String.isBlank(row.Address_Type__c)) {
                continue;
            }
            Id rowApplicantId = row.Applicant__c;
            if (!bundle.byApplicant.containsKey(rowApplicantId)) {
                bundle.byApplicant.put(rowApplicantId, new Map<String, AddressWrapper>());
            }
            if (ADDR_CURRENT.equals(row.Address_Type__c) && !bundle.currentRowByApplicant.containsKey(rowApplicantId)) {
                bundle.currentRowByApplicant.put(rowApplicantId, row);
            }
            if (ADDR_REGISTERED.equals(row.Address_Type__c) && !bundle.registeredRowByApplicant.containsKey(rowApplicantId)) {
                bundle.registeredRowByApplicant.put(rowApplicantId, row);
            }

            Map<String, AddressWrapper> applicantAddresses = bundle.byApplicant.get(rowApplicantId);
            if (applicantAddresses.containsKey(row.Address_Type__c)) {
                continue;
            }
            AddressWrapper address = buildAddressFromApplicantAddress(row);
            if (address != null) {
                applicantAddresses.put(row.Address_Type__c, address);
            }
        }

        applyKycAddressFallback(bundle, applicationId, applicantId, addressTypes);
        applySameAsAddressRules(bundle);
        applyNiRegisteredOfficeSameAsRules(bundle);
        return bundle;
    }

    private static Boolean resolveIsNonIndividualFi(Id applicationId) {
        if (applicationId == null) {
            return false;
        }
        List<Applicant__c> borrowers = [
            SELECT Type__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND Applicant_Type__c = :APPLICANT_TYPE_BORROWER
              AND In_Active_Applicant__c = false
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return !borrowers.isEmpty()
            && GenericUtility.isNonIndividualApplicationType(borrowers[0].Type__c);
    }

    private static void persistNiVerificationFormData(
            Verification__c verification,
            Map<String, Object> formData) {
        if (verification == null || formData == null || formData.isEmpty()) {
            return;
        }

        verification.FI_Address_Line_1__c = parseString(formData, 'addressLine1');
        verification.FI_Address_Line_2__c = parseString(formData, 'addressLine2');
        verification.FI_City__c = parseString(formData, 'city');
        verification.FI_State__c = parseString(formData, 'state');
        verification.FI_Pin_Code__c = parseString(formData, 'pinCode');
        verification.Landmark__c = parseString(formData, 'landmark');
        verification.Phone_Number__c = parseString(formData, 'phoneNumber');
        verification.Mobile__c = parseString(formData, 'mobile');
        verification.Employer_Business_Name__c = parseString(formData, 'employerBusinessName');
        verification.Years_in_Residence__c = parseDecimal(formData, 'yearsInThisAddress');
        verification.Resi_Cum_Off__c = parseString(formData, 'resiCumOff');
        verification.KM_from_Branch__c = parseString(formData, 'kmFromBranch');
        verification.Lead_Gen_Time__c = parseDateTime(formData, 'leadGenTime');
        verification.Request_Gen_Time__c = parseDateTime(formData, 'requestGenTime');
        verification.Office_BP_FI__c = parseString(formData, 'officeBpFi');
        verification.Resi_FI__c = parseString(formData, 'resiFi');
        verification.Latitude__c = parseDecimal(formData, 'fiLatitude');
        verification.Longitude__c = parseDecimal(formData, 'fiLongitude');
        verification.Frontside__c = parseString(formData, 'frontside');
        verification.Leftside__c = parseString(formData, 'leftside');
        verification.Rearside__c = parseString(formData, 'rearside');
        verification.Rightside__c = parseString(formData, 'rightside');

        verification.Company_Name__c = parseString(formData, 'companyName');
        verification.SENPName__c = parseString(formData, 'senpContactName');
        verification.Total_Business_Stability__c = parseString(formData, 'totalBusinessStability');
        verification.Business_Premise__c = parseString(formData, 'businessPremise');
        verification.Org_Type__c = parseString(formData, 'orgType');
        verification.Business_Nature__c = parseString(formData, 'businessNature');
        verification.Current_Business_Stability__c = parseString(formData, 'currentBusinessStability');
        verification.Business_Premises_Owned_Rental__c = parseString(formData, 'businessPremisesOwnedRental');
        verification.If_Rental_Premises_Rent_per_month__c = parseDecimal(formData, 'rentalPremisesRentPerMonth');

        verification.Office_Business_Type__c = parseString(formData, 'officeBusinessType');
        verification.No_of_Emp_Seen__c = parseString(formData, 'numberOfEmployeesSeen');
        verification.Office_Board__c = parseString(formData, 'officeBoard');
        verification.Location__c = parseString(formData, 'location');
        verification.Activity_at_office__c = parseString(formData, 'activityAtOffice');
        verification.Locatability__c = parseString(formData, 'locatability');
        verification.Touring_or_Transferrable_job__c = parseString(formData, 'touringOrTransferableJob');
        verification.How_many_Employees_in_Office__c = parseDecimal(formData, 'howManyEmployeesInOffice');
        verification.Political_Photo__c = parseString(formData, 'politicalPhoto');
        verification.Office_Business_Size_Sqft__c = parseString(formData, 'officeBusinessSiteSqft');
        verification.Locality__c = parseString(formData, 'locality');
        verification.Office_Approach__c = parseString(formData, 'officeApproach');
        verification.Behaviour__c = parseString(formData, 'behaviour');
        verification.Photo_Not_Allowed__c = parseString(formData, 'photoNotAllowed');

        verification.No_of_Attempts__c = parseDecimal(formData, 'noOfAttempts');
        verification.Observation__c = parseString(formData, 'fiObservation');
        verification.FI_Recommendation__c = parseString(formData, 'fiRecommendation');
        verification.Additional_Remarks__c = parseString(formData, 'verifierRemarks');
        verification.Reject_Reason__c = parseString(formData, 'rejectReason');

        verification.Fleet_Count__c = parseDecimal(formData, 'fleetCount');
        verification.Free_Fleet__c = parseDecimal(formData, 'freeFleet');
        verification.Bank_Fleet__c = parseDecimal(formData, 'iblFleet');
        verification.Financed_by_Others__c = parseDecimal(formData, 'financedByOthers');
        verification.Fleet_Total__c = parseDecimal(formData, 'fleetTotal');
    }

    private static void enrichNiOfficeFormData(
            Map<String, Object> formData,
            Verification__c verification,
            Applicant__c applicant,
            Investigations__c investigation,
            String fiLabel) {
        if (formData == null) {
            return;
        }

        if (verification != null) {
            DateTime applicationCreatedDate = resolveApplicationCreatedDate(verification, investigation);
            putFormValue(formData, 'addressLine1', verification.FI_Address_Line_1__c);
            putFormValue(formData, 'addressLine2', verification.FI_Address_Line_2__c);
            putFormValue(formData, 'city', verification.FI_City__c);
            putFormValue(formData, 'state', verification.FI_State__c);
            putFormValue(formData, 'pinCode', verification.FI_Pin_Code__c);
            putFormValue(formData, 'yearsInThisAddress', verification.Years_in_Residence__c);
            putFormValue(formData, 'resiCumOff', verification.Resi_Cum_Off__c);
            putFormValue(formData, 'kmFromBranch', verification.KM_from_Branch__c);
            putFormValue(formData, 'leadGenTime', formatDateTimeLocal(verification.Lead_Gen_Time__c));
            putFormValue(formData, 'requestGenTime', formatDateTimeLocal(verification.Request_Gen_Time__c));
            putFormValueIfBlank(formData, 'leadGenTime', formatDateTimeLocal(applicationCreatedDate));
            putFormValueIfBlank(formData, 'requestGenTime', formatDateTimeLocal(verification.CreatedDate));
            if (FI_LABEL_OFFICE.equals(fiLabel)) {
                DateTime officeVerifiedTime = verification.Office_Verified_Time__c != null
                    ? verification.Office_Verified_Time__c
                    : verification.Submitted_Date__c;
                putFormValue(formData, 'officeVerifiedTime', formatDateTimeLocal(officeVerifiedTime));
            }
            if (RESIDENCE_FI_LABELS.contains(fiLabel)) {
                DateTime resiVerifiedTime = verification.Resi_Verified_Time__c != null
                    ? verification.Resi_Verified_Time__c
                    : verification.Submitted_Date__c;
                putFormValue(formData, 'resiVerifiedTime', formatDateTimeLocal(resiVerifiedTime));
            }
            putFormValue(formData, 'officeBpFi', verification.Office_BP_FI__c);
            putFormValue(formData, 'resiFi', verification.Resi_FI__c);
            putFormValue(formData, 'frontside', verification.Frontside__c);
            putFormValue(formData, 'leftside', verification.Leftside__c);
            putFormValue(formData, 'rearside', verification.Rearside__c);
            putFormValue(formData, 'rightside', verification.Rightside__c);

            putFormValue(formData, 'companyName', verification.Company_Name__c);
            putFormValue(formData, 'senpContactName', verification.SENPName__c);
            putFormValue(formData, 'totalBusinessStability', verification.Total_Business_Stability__c);
            putFormValue(formData, 'orgType', verification.Org_Type__c);
            putFormValue(formData, 'businessNature', verification.Business_Nature__c);
            putFormValue(formData, 'currentBusinessStability', verification.Current_Business_Stability__c);
            putFormValue(formData, 'businessPremisesOwnedRental', verification.Business_Premises_Owned_Rental__c);
            putFormValue(formData, 'rentalPremisesRentPerMonth', verification.If_Rental_Premises_Rent_per_month__c);

            putFormValue(formData, 'numberOfEmployeesSeen', verification.No_of_Emp_Seen__c);
            putFormValue(formData, 'officeBoard', verification.Office_Board__c);
            putFormValue(formData, 'location', verification.Location__c);
            putFormValue(formData, 'activityAtOffice', verification.Activity_at_office__c);
            putFormValue(formData, 'locatability', verification.Locatability__c);
            putFormValue(formData, 'touringOrTransferableJob', verification.Touring_or_Transferrable_job__c);
            putFormValue(formData, 'howManyEmployeesInOffice', verification.How_many_Employees_in_Office__c);
            putFormValue(formData, 'politicalPhoto', verification.Political_Photo__c);
            putFormValue(formData, 'officeBusinessSiteSqft', verification.Office_Business_Size_Sqft__c);
            putFormValue(formData, 'locality', verification.Locality__c);
            putFormValue(formData, 'officeApproach', verification.Office_Approach__c);
            putFormValue(formData, 'behaviour', verification.Behaviour__c);
            putFormValue(formData, 'photoNotAllowed', verification.Photo_Not_Allowed__c);

            putFormValue(formData, 'fiRecommendation', verification.FI_Recommendation__c);
            putFormValue(formData, 'verifierRemarks', verification.Additional_Remarks__c);
            putFormValue(formData, 'rejectReason', verification.Reject_Reason__c);

            putFormValue(formData, 'fleetCount', verification.Fleet_Count__c);
            putFormValue(formData, 'freeFleet', verification.Free_Fleet__c);
            putFormValue(formData, 'iblFleet', verification.Bank_Fleet__c);
            putFormValue(formData, 'financedByOthers', verification.Financed_by_Others__c);
            putFormValue(formData, 'fleetTotal', verification.Fleet_Total__c);
        }

        if (applicant == null) {
            return;
        }

        putFormValueIfBlank(formData, 'companyName', applicant.Company_Name__c);
    }

    private static void applyNiVerificationTimestamps(
            Verification__c verification,
            Id investigationId,
            String fiLabel,
            Boolean submittedByFiUser) {
        if (verification == null) {
            return;
        }

        DateTime applicationCreatedDate = resolveApplicationCreatedDate(verification, investigationId);
        if (verification.Lead_Gen_Time__c == null && applicationCreatedDate != null) {
            verification.Lead_Gen_Time__c = applicationCreatedDate;
        }
        if (verification.Request_Gen_Time__c == null && verification.CreatedDate != null) {
            verification.Request_Gen_Time__c = verification.CreatedDate;
        }

        if (submittedByFiUser != true) {
            return;
        }

        DateTime submittedAt = System.now();
        if (FI_LABEL_OFFICE.equals(fiLabel)) {
            verification.Office_Verified_Time__c = submittedAt;
        } else if (RESIDENCE_FI_LABELS.contains(fiLabel)) {
            verification.Resi_Verified_Time__c = submittedAt;
        }
    }

    private static DateTime resolveApplicationCreatedDate(
            Verification__c verification,
            Investigations__c investigation) {
        if (investigation != null && investigation.Application__r != null) {
            return investigation.Application__r.CreatedDate;
        }
        if (verification != null
                && verification.Investigations__r != null
                && verification.Investigations__r.Application__r != null) {
            return verification.Investigations__r.Application__r.CreatedDate;
        }

        Id applicationId = investigation != null
            ? investigation.Application__c
            : (verification != null && verification.Investigations__r != null
                ? verification.Investigations__r.Application__c
                : null);
        return resolveApplicationCreatedDateById(applicationId);
    }

    private static DateTime resolveApplicationCreatedDate(
            Verification__c verification,
            Id investigationId) {
        if (verification != null
                && verification.Investigations__r != null
                && verification.Investigations__r.Application__r != null) {
            return verification.Investigations__r.Application__r.CreatedDate;
        }

        Id applicationId = verification != null && verification.Investigations__r != null
            ? verification.Investigations__r.Application__c
            : null;
        if (applicationId == null && investigationId != null) {
            List<Investigations__c> investigations = [
                SELECT Application__c, Application__r.CreatedDate
                FROM Investigations__c
                WHERE Id = :investigationId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!investigations.isEmpty()) {
                if (investigations[0].Application__r != null) {
                    return investigations[0].Application__r.CreatedDate;
                }
                applicationId = investigations[0].Application__c;
            }
        }
        return resolveApplicationCreatedDateById(applicationId);
    }

    private static DateTime resolveApplicationCreatedDateById(Id applicationId) {
        if (applicationId == null) {
            return null;
        }
        List<Application__c> applications = [
            SELECT CreatedDate
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0].CreatedDate;
    }

    private static void putFormValueIfBlank(Map<String, Object> formData, String key, Object value) {
        if (formData == null) {
            return;
        }
        if (formData.containsKey(key)) {
            Object existing = formData.get(key);
            if (existing != null && String.isNotBlank(String.valueOf(existing))) {
                return;
            }
        }
        putFormValue(formData, key, value);
    }

    private static void putFormValue(Map<String, Object> formData, String key, Object value) {
        if (formData == null || value == null) {
            return;
        }
        if (value instanceof Boolean) {
            if (value == true) {
                formData.put(key, true);
            }
            return;
        }
        if (value instanceof Decimal) {
            formData.put(key, String.valueOf(value));
            return;
        }
        String text = String.valueOf(value).trim();
        if (String.isNotBlank(text)) {
            formData.put(key, text);
        }
    }

    private static Set<String> buildFiDocumentTypes(String fiLabel) {
        Set<String> documentTypes = new Set<String>{ DOC_TYPE_FI_SIGNATURE };
        if (FI_LABEL_OFFICE.equals(fiLabel)) {
            documentTypes.add(DOC_TYPE_OFFICE_BUILDING_FRONT);
            documentTypes.add(DOC_TYPE_OFFICE_APPROACH_ROAD);
            documentTypes.add(DOC_TYPE_OFFICE_BUILDING_INNER);
            documentTypes.add(DOC_TYPE_LAND_PHOTO);
            documentTypes.add(DOC_TYPE_PATTA);
            documentTypes.add(DOC_TYPE_RENT_AGREEMENT);
            documentTypes.add(DOC_TYPE_PENSION_DOCUMENT);
        } else if (RESIDENCE_FI_LABELS.contains(fiLabel)) {
            documentTypes.add(DOC_TYPE_RESIDENCE_FRONT);
            documentTypes.add(DOC_TYPE_FI_KYC);
            documentTypes.add(DOC_TYPE_OFFICE_APPROACH_ROAD);
            documentTypes.add(DOC_TYPE_OFFICE_BUILDING_INNER);
            documentTypes.add(DOC_TYPE_OFFICE_BUILDING_FRONT);
        }
        Set<String> newDocumentTypes = new Set<String>();
        for (String documentType : documentTypes) {
            newDocumentTypes.add(getDocumentType(documentType, fiLabel));
        }
        return newDocumentTypes;
    }

    private static String getDocumentType(String documentType, String fiLabel) {
        if (String.isBlank(documentType)) {
            return documentType;
        }
        return String.isBlank(fiLabel) ? documentType.trim() : documentType.trim() + ' - ' + fiLabel.trim();
    }

}