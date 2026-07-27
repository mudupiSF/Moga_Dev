/**
 * Handler for the ETB CASA integration.
 *
 * Trigger : Basic Details NEXT click, immediately after CIF on PAN
 *           (PAN path only — Form 60 skips this stage).
 * Mock    : Integration_Master__c.Is_Mocking_Service_Enabled__c = true →
 *           Mocking_Service_Response__c replays the upstream SOAP+FIXML envelope
 *           where the inner FIXML body is HTML-entity encoded.
 * The JSON shape stored on ETB_CASA_Details__c drives the Cross-Sell
 * repayment-account picker on the KYC Details screen.
 */
public without sharing class ETBCASAHandlerAPI implements IIntegrationHandler {

    /** Fields lifted out of each <AcctDtls> block. Order is preserved into the
     *  JSON output so downstream consumers can rely on a stable key set. */
    private static final List<String> CASA_FIELDS = new List<String>{
        'ACCOUNTID',
        'ACCT_OPN_DATE',
        'SUSPENDED_FLG',
        'CUSTNAME',
        'Account_holder_name',
        'Nature_of_account',
        'SCHEME_CODE',
        'IFSC_CODE',
        'ACCT_CLS_FLG'
    };

    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) return new List<sObject>();
        Id applicantId = recordIds[0];
        List<Applicant__c> rows = [
            SELECT Id, Customer_Code__c, ETB_CASA_Details__c
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
            wrapper.errorMessage  = 'Applicant record not found for ETB CASA integration.';
            wrapper.displayMessage = 'Applicant record missing.';
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant__c applicant = (Applicant__c) recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();
        wrapper.method      = 'POST';
        wrapper.requestBody = '{"applicantId":"' + String.valueOf(applicant.Id) + '","custId":"' + nullSafe(applicant.Customer_Code__c) + '"}';
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
                result.errorMessage = 'ETB CASA returned status ' + wrapper.statusCode;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            List<Map<String, String>> accounts = parseAccounts(wrapper.response);
            String jsonPayload = JSON.serialize(accounts);

            Id applicantId = (Id) checklist.Applicant__c;
            if (applicantId != null) {
                update new Applicant__c(Id = applicantId, ETB_CASA_Details__c = jsonPayload);
            }

            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            checklist.Status__c            = Constants.CHECKLIST_STATUS_SUCCESS;
            update checklist;

            result.hasValidationError = false;
            result.displayMessage = accounts.size() + ' CASA account(s) captured.';
        } catch (Exception ex) {
            result.hasValidationError = true;
            result.errorMessage = 'ETB CASA processResponse error: ' + ex.getMessage();
            if (checklist != null) markChecklistFailure(checklist);
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private static List<Map<String, String>> parseAccounts(String rawResponse) {
        List<Map<String, String>> out = new List<Map<String, String>>();
        if (String.isBlank(rawResponse)) return out;
        String decoded = decodeEntities(rawResponse);
        Matcher blockMatcher = Pattern.compile('(?s)<AcctDtls>(.*?)</AcctDtls>').matcher(decoded);
        while (blockMatcher.find()) {
            String block = blockMatcher.group(1);
            Map<String, String> row = new Map<String, String>();
            for (String fieldName : CASA_FIELDS) {
                row.put(fieldName, extractTag(block, fieldName));
            }
            // Skip empty rows (no ACCOUNTID = nothing to display)
            if (String.isNotBlank(row.get('ACCOUNTID'))) {
                out.add(row);
            }
        }
        return out;
    }

    private static String extractTag(String block, String tagName) {
        Matcher m = Pattern.compile('(?s)<' + tagName + '>(.*?)</' + tagName + '>').matcher(block);
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