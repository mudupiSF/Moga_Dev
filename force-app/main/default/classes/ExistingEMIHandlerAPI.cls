/**
 * Handler for the Existing EMI integration (Integration_Master__c "Existing EMI Engine").
 *
 * Trigger : Get Existing EMI click on the Dedupe and Eligibility screen.
 * Mock    : Integration_Master__c.Is_Mocking_Service_Enabled__c = true →
 *           Mocking_Service_Response__c replays the emiRanges payload, so no live
 *           endpoint is required while the upstream API is being finalised.
 *
 * The framework creates the Integration_Checklist__c linked to the applicant and a
 * successful checklist is what marks Existing EMI as "already fetched" for that
 * applicant (Allow_Refresh__c = false then blocks a second run).
 */
public without sharing class ExistingEMIHandlerAPI implements IIntegrationHandler {

    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) return new List<sObject>();
        Id applicantId = recordIds[0];
        List<Applicant__c> rows = [
            SELECT Id, Customer_Code__c
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        return rows.isEmpty() ? new List<sObject>{ null } : (List<sObject>) rows;
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> validateInputData(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
        wrapper.hasValidationError = false;
        if (recordList == null || recordList.isEmpty() || recordList[0] == null) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage   = 'Applicant record not found for Existing EMI integration.';
            wrapper.displayMessage = 'Applicant record missing.';
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant__c applicant = (Applicant__c) recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();
        wrapper.method      = 'POST';
        wrapper.requestBody = '{"applicantId":"' + String.valueOf(applicant.Id)
            + '","cif":"' + nullSafe(applicant.Customer_Code__c) + '"}';
        wrapper.captureRequestInAttachment = false;
        return new List<ApplicationUtility.IntegrationRequestWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        IntegrationUtility.ResponseWrapper wrapper = null;
        Integration_Checklist__c checklist = null;
        try {
            wrapper   = (IntegrationUtility.ResponseWrapper) recordList[0];
            checklist = (Integration_Checklist__c) wrapper.checklistRecord;

            if (wrapper.statusCode != 200) {
                markChecklistFailure(checklist);
                result.hasValidationError = true;
                result.errorMessage = 'Existing EMI returned status ' + wrapper.statusCode;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            Integer rangeCount = countEmiRanges(wrapper.response);
            if (rangeCount < 0) {
                markChecklistFailure(checklist);
                result.hasValidationError = true;
                result.errorMessage = 'Existing EMI response did not contain a valid emiRanges payload.';
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            checklist.Status__c            = Constants.CHECKLIST_STATUS_SUCCESS;
            update checklist;

            result.hasValidationError = false;
            result.displayMessage = 'Existing EMI details retrieved (' + rangeCount + ' record(s)).';
        } catch (Exception ex) {
            result.hasValidationError = true;
            result.errorMessage = 'Existing EMI processResponse error: ' + ex.getMessage();
            if (checklist != null) markChecklistFailure(checklist);
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    /** Returns the emiRanges size, or -1 when the payload is missing/invalid. */
    private static Integer countEmiRanges(String rawResponse) {
        if (String.isBlank(rawResponse)) return -1;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(rawResponse);
            Object ranges = parsed.get('emiRanges');
            if (ranges instanceof List<Object>) {
                return ((List<Object>) ranges).size();
            }
        } catch (Exception ignored) {
            // fall through to invalid
        }
        return -1;
    }

    private static void markChecklistFailure(Integration_Checklist__c checklist) {
        if (checklist == null) return;
        try {
            checklist.Status__c            = Constants.CHECKLIST_STATUS_FAILURE;
            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
            update checklist;
        } catch (Exception ignored) {}
    }

    private static String nullSafe(String value) {
        if (value == null) return '';
        String t = value.trim();
        return (String.isBlank(t) || t.equalsIgnoreCase('null')) ? '' : t;
    }
}