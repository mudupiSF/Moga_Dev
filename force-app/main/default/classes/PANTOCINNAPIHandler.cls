/**
 * Integration Master handler for PAN TO CIN lookup.
 */
public with sharing class PANTOCINNAPIHandler implements IIntegrationHandler {

    public static final String INTEGRATION_KEY = 'PAN TO CIN';
    private static final String DOC_TYPE_CIN   = 'CIN';

    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<sObject>();
        }
        return [
            SELECT Id, PAN_Number__c
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
            wrapper.errorMessage = 'Applicant record not found for PAN TO CIN.';
            wrapper.displayMessage = wrapper.errorMessage;
            return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
        }

        Applicant__c applicant = (Applicant__c) recordList[0];
        wrapper.recordId = applicant.Id;

        if (String.isBlank(applicant.PAN_Number__c)) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage = 'PAN is required before PAN TO CIN lookup.';
            wrapper.displayMessage = wrapper.errorMessage;
        }

        return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant__c applicant = (Applicant__c) recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();
        wrapper.requestBody = JSON.serialize(new Map<String, Object>{
            'pan' => applicant.PAN_Number__c
        });
        return new List<ApplicationUtility.IntegrationRequestWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        try {
            IntegrationUtility.ResponseWrapper wrapper = (IntegrationUtility.ResponseWrapper) recordList[0];
            Integration_Checklist__c checklist = (Integration_Checklist__c) wrapper.checklistRecord;
            Id applicantId = checklist.Applicant__c;

            if (wrapper.statusCode != 200) {
                markChecklistFailure(checklist);
                result.hasValidationError = true;
                result.errorMessage = resolveRawResponse(wrapper);
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            String rawResponse = resolveRawResponse(wrapper);
            List<String> cinNumbers = parseCinNumbersFromResponse(rawResponse);
            if (cinNumbers.isEmpty()) {
                markChecklistFailure(checklist);
                result.hasValidationError = true;
                result.errorMessage = 'PAN TO CIN response did not contain any CIN values.';
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            persistCinExtraction(applicantId, cinNumbers);

            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            checklist.Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            update checklist;

            result.hasValidationError = false;
            result.recordId = applicantId;
        } catch (Exception ex) {
            result.hasValidationError = true;
            result.errorMessage = ex.getMessage();
            result.displayMessage = ex.getMessage();
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
    }

    public static List<String> parseCinNumbersFromResponse(String rawResponse) {
        List<String> cinNumbers = new List<String>();
        if (String.isBlank(rawResponse)) {
            return cinNumbers;
        }

        try {
            CinApiResponse typed = (CinApiResponse) JSON.deserialize(rawResponse, CinApiResponse.class);
            if (typed?.result?.company != null) {
                for (CinCompanyRow row : typed.result.company) {
                    addCinNumber(cinNumbers, row?.companyID);
                }
            }
        } catch (Exception ignored) {
            // Fall through to untyped parsing.
        }

        if (!cinNumbers.isEmpty()) {
            return cinNumbers;
        }

        Object parsed = JSON.deserializeUntyped(rawResponse);
        if (!(parsed instanceof Map<String, Object>)) {
            return cinNumbers;
        }

        Object resultObj = ((Map<String, Object>) parsed).get('result');
        if (!(resultObj instanceof Map<String, Object>)) {
            return cinNumbers;
        }

        Object companyObj = ((Map<String, Object>) resultObj).get('company');
        if (!(companyObj instanceof List<Object>)) {
            return cinNumbers;
        }

        for (Object rowObj : (List<Object>) companyObj) {
            if (rowObj instanceof Map<String, Object>) {
                addCinNumber(cinNumbers, ((Map<String, Object>) rowObj).get('companyID'));
            }
        }
        return cinNumbers;
    }

    private static String resolveRawResponse(IntegrationUtility.ResponseWrapper wrapper) {
        if (wrapper == null) {
            return null;
        }
        if (String.isNotBlank(wrapper.response)) {
            return wrapper.response;
        }
        Integration_Checklist__c checklist = wrapper.checklistRecord;
        if (checklist == null) {
            return null;
        }
        if (String.isNotBlank(checklist.Decrypted_Response__c)) {
            return checklist.Decrypted_Response__c;
        }
        return checklist.Response__c;
    }

    private static void addCinNumber(List<String> cinNumbers, Object rawValue) {
        String value = rawValue == null ? null : String.valueOf(rawValue).trim();
        if (String.isNotBlank(value) && !cinNumbers.contains(value)) {
            cinNumbers.add(value);
        }
    }

    private static void persistCinExtraction(Id applicantId, List<String> cinNumbers) {
        Document_CheckList__c cinRow = queryCinChecklist(applicantId);
        if (cinRow == null) {
            return;
        }

        Applicant_KYC__c kyc = getOrCreateApplicantKyc(cinRow.Applicant_KYC__c, applicantId);
        if (cinNumbers.size() == 1) {
            String cinNumber = cinNumbers[0];
            kyc.KYC_No__c        = cinNumber;
            kyc.Masked_KYC_No__c = KYCAddressExtractionController.maskDocumentNumber(cinNumber);
            kyc.KYC_name__c      = DOC_TYPE_CIN;
        } else {
            kyc.KYC_No__c        = null;
            kyc.Masked_KYC_No__c = null;
            kyc.KYC_name__c      = null;
        }
        upsert kyc;

        if (cinRow.Applicant_KYC__c == null) {
            cinRow.Applicant_KYC__c = kyc.Id;
            update cinRow;
        }
    }

    private static Document_CheckList__c queryCinChecklist(Id applicantId) {
        List<Document_CheckList__c> rows = [
            SELECT Id, Applicant_KYC__c
            FROM Document_CheckList__c
            WHERE Applicant__c = :applicantId
              AND Document_Type__c = :DOC_TYPE_CIN
              AND Is_Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Applicant_KYC__c getOrCreateApplicantKyc(Id existingKycId, Id applicantId) {
        if (existingKycId != null) {
            List<Applicant_KYC__c> existing = [
                SELECT Id, Applicant__c, KYC_No__c, Masked_KYC_No__c, KYC_name__c
                FROM Applicant_KYC__c
                WHERE Id = :existingKycId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0];
            }
        }
        return new Applicant_KYC__c(Applicant__c = applicantId);
    }

    private static void markChecklistFailure(Integration_Checklist__c checklist) {
        if (checklist == null) {
            return;
        }
        checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
        checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
        update checklist;
    }

    public class CinApiResponse {
        public CinResultWrapper result { get; set; }
    }

    public class CinResultWrapper {
        public List<CinCompanyRow> company { get; set; }
    }

    public class CinCompanyRow {
        public String companyName { get; set; }
        public String companyID { get; set; }
    }
}