/**
 * Integration Master handler for PAN TO GSTN lookup.
 */
public with sharing class PANTOGSTNAPIHandler implements IIntegrationHandler {

    public static final String INTEGRATION_KEY = 'PAN TO GSTN';
    private static final String DOC_TYPE_GST   = 'GST';
    private static final String STATUS_ACTIVE  = 'ACTIVE';

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
            wrapper.errorMessage = 'Applicant record not found for PAN TO GSTN.';
            wrapper.displayMessage = wrapper.errorMessage;
            return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
        }

        Applicant__c applicant = (Applicant__c) recordList[0];
        wrapper.recordId = applicant.Id;

        if (String.isBlank(applicant.PAN_Number__c)) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage = 'PAN is required before PAN TO GSTN lookup.';
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
            GstExtractionParseResult parsed = parseGstDataFromResponse(rawResponse);
            if (parsed.gstNumbers.isEmpty()) {
                markChecklistFailure(checklist);
                result.hasValidationError = true;
                result.errorMessage = 'PAN TO GSTN response did not contain any active GSTIN values.';
                result.displayMessage = result.errorMessage;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            persistGstExtraction(applicantId, parsed);

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

    public static GstExtractionParseResult parseGstDataFromResponse(String rawResponse) {
        GstExtractionParseResult result = new GstExtractionParseResult();
        result.gstNumbers = new List<String>();
        result.gstStateByNumber = new Map<String, String>();

        if (String.isBlank(rawResponse)) {
            return result;
        }

        List<GstinRow> rows = extractGstinRows(rawResponse);
        List<GstinRow> activeRows = new List<GstinRow>();
        for (GstinRow row : rows) {
            if (row != null && STATUS_ACTIVE.equalsIgnoreCase(row.status)) {
                activeRows.add(row);
            }
        }

        for (GstinRow row : activeRows) {
            if (row == null || String.isBlank(row.gstin)) {
                continue;
            }
            String gstin = row.gstin.trim();
            if (!result.gstNumbers.contains(gstin)) {
                result.gstNumbers.add(gstin);
            }
            String state = normalizeStateName(row.state);
            if (String.isNotBlank(state)) {
                result.gstStateByNumber.put(gstin, state);
            }
        }

        if (!activeRows.isEmpty()) {
            result.defaultState = normalizeStateName(activeRows[0].state);
        }
        return result;
    }

    private static List<GstinRow> extractGstinRows(String rawResponse) {
        List<GstinRow> rows = new List<GstinRow>();
        try {
            GstApiResponse typed = (GstApiResponse) JSON.deserialize(rawResponse, GstApiResponse.class);
            if (typed?.result?.gstinList != null) {
                for (GstinRow row : typed.result.gstinList) {
                    rows.add(row);
                }
            }
        } catch (Exception ignored) {
            // Fall through to untyped parsing.
        }

        if (!rows.isEmpty()) {
            return rows;
        }

        Object parsed = JSON.deserializeUntyped(rawResponse);
        if (!(parsed instanceof Map<String, Object>)) {
            return rows;
        }

        Object resultObj = ((Map<String, Object>) parsed).get('result');
        if (!(resultObj instanceof Map<String, Object>)) {
            return rows;
        }

        Object gstinListObj = ((Map<String, Object>) resultObj).get('gstinList');
        if (!(gstinListObj instanceof List<Object>)) {
            return rows;
        }

        for (Object rowObj : (List<Object>) gstinListObj) {
            if (!(rowObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> rowMap = (Map<String, Object>) rowObj;
            GstinRow row = new GstinRow();
            row.gstin = rowMap.get('gstin') == null ? null : String.valueOf(rowMap.get('gstin'));
            row.status = rowMap.get('status') == null ? null : String.valueOf(rowMap.get('status'));
            row.state = rowMap.get('state') == null ? null : String.valueOf(rowMap.get('state'));
            rows.add(row);
        }
        return rows;
    }

    public static String normalizeStateName(String rawState) {
        if (String.isBlank(rawState)) {
            return null;
        }
        String cleaned = rawState.replace('(NEW)', '').replace('(new)', '').trim();
        if (String.isBlank(cleaned)) {
            return null;
        }
        List<String> words = cleaned.toLowerCase().split('\\s+');
        List<String> titled = new List<String>();
        for (String word : words) {
            if (String.isBlank(word)) {
                continue;
            }
            titled.add(word.substring(0, 1).toUpperCase() + word.substring(1));
        }
        return String.join(titled, ' ');
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

    private static void persistGstExtraction(Id applicantId, GstExtractionParseResult parsed) {
        Document_CheckList__c gstRow = queryGstChecklist(applicantId);
        if (gstRow == null) {
            return;
        }

        Applicant_KYC__c kyc = getOrCreateApplicantKyc(gstRow.Applicant_KYC__c, applicantId);
        if (parsed.gstNumbers.size() == 1) {
            String gstin = parsed.gstNumbers[0];
            kyc.KYC_No__c        = gstin;
            kyc.Masked_KYC_No__c = KYCAddressExtractionController.maskDocumentNumber(gstin);
            kyc.KYC_name__c      = DOC_TYPE_GST;
            String state = parsed.gstStateByNumber.containsKey(gstin)
                ? parsed.gstStateByNumber.get(gstin)
                : parsed.defaultState;
            if (String.isNotBlank(state)) {
                kyc.KYC_State__c = state;
            }
        } else {
            kyc.KYC_No__c        = null;
            kyc.Masked_KYC_No__c = null;
            kyc.KYC_name__c      = null;
            if (String.isNotBlank(parsed.defaultState)) {
                kyc.KYC_State__c = parsed.defaultState;
            }
        }
        upsert kyc;

        if (gstRow.Applicant_KYC__c == null) {
            gstRow.Applicant_KYC__c = kyc.Id;
            update gstRow;
        }
    }

    private static Document_CheckList__c queryGstChecklist(Id applicantId) {
        List<Document_CheckList__c> rows = [
            SELECT Id, Applicant_KYC__c
            FROM Document_CheckList__c
            WHERE Applicant__c = :applicantId
              AND Document_Type__c = :DOC_TYPE_GST
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
                SELECT Id, Applicant__c, KYC_No__c, Masked_KYC_No__c, KYC_State__c, KYC_name__c
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

    public class GstExtractionParseResult {
        public List<String> gstNumbers { get; set; }
        public Map<String, String> gstStateByNumber { get; set; }
        public String defaultState { get; set; }

        public GstExtractionParseResult() {
            gstNumbers = new List<String>();
            gstStateByNumber = new Map<String, String>();
        }
    }

    public class GstApiResponse {
        public GstResultWrapper result { get; set; }
    }

    public class GstResultWrapper {
        public List<GstinRow> gstinList { get; set; }
    }

    public class GstinRow {
        public String gstin { get; set; }
        public String status { get; set; }
        public String state { get; set; }
    }
}