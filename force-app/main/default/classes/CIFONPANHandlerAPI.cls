/**
 * Handler for the CIF on PAN integration.
 *
 * Trigger : Basic Details NEXT click (PAN path only).
 * Mock    : Integration_Master__c.Is_Mocking_Service_Enabled__c = true →
 *           Mocking_Service_Response__c replays the upstream SOAP+FIXML envelope.
 * The CIF Id stamped here is the input the ETB CASA integration reads from
 * Applicant__c.Customer_Code__c on the next stage of borrowerNextIntegration.js.
 */
public without sharing class CIFONPANHandlerAPI implements IIntegrationHandler {

    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) return new List<sObject>();
        Id applicantId = recordIds[0];
        List<Applicant__c> rows = [
            SELECT Id, PAN_Number__c, Customer_Code__c
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
            wrapper.errorMessage  = 'Applicant record not found for CIF on PAN integration.';
            wrapper.displayMessage = 'Applicant record missing.';
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant__c applicant = (Applicant__c) recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();
        wrapper.method      = 'POST';
        wrapper.requestBody = '{"applicantId":"' + String.valueOf(applicant.Id) + '","pan":"' + nullSafe(applicant.PAN_Number__c) + '"}';
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
                result.errorMessage = 'CIF on PAN returned status ' + wrapper.statusCode;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            String custId = extractCustId(wrapper.response);
            if (String.isBlank(custId)) {
                markChecklistFailure(checklist);
                result.hasValidationError = true;
                result.errorMessage = 'CIF on PAN response did not contain a <CUST_ID> value.';
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            Id applicantId = (Id) checklist.Applicant__c;
            if (applicantId != null) {
                update new Applicant__c(Id = applicantId, Customer_Code__c = custId);
            }

            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            checklist.Status__c            = Constants.CHECKLIST_STATUS_SUCCESS;
            update checklist;

            result.hasValidationError = false;
            result.displayMessage = 'Customer code ' + custId + ' captured.';
        } catch (Exception ex) {
            result.hasValidationError = true;
            result.errorMessage = 'CIF on PAN processResponse error: ' + ex.getMessage();
            if (checklist != null) markChecklistFailure(checklist);
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static String extractCustId(String rawResponse) {
        if (String.isBlank(rawResponse)) return '';
        String decoded = decodeEntities(rawResponse);
        Matcher m = Pattern.compile('<CUST_ID>(.*?)</CUST_ID>').matcher(decoded);
        return m.find() ? m.group(1).trim() : '';
    }

    private static String decodeEntities(String input) {
        if (String.isBlank(input)) return input;
        return input
            .replace('&lt;', '<')
            .replace('&gt;', '>')
            .replace('&quot;', '"')
            .replace('&apos;', '\'')
            .replace('&amp;', '&');
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