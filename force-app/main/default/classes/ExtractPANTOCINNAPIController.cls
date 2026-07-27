/**
 * Thin controller for PAN TO CIN integration from Non-Individual KYC.
 */
public with sharing class ExtractPANTOCINNAPIController {

    private static final String INTEGRATION_KEY = PANTOCINNAPIHandler.INTEGRATION_KEY;

    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokePANTOCINNAPI(String applicantId) {
        return ApplicationUtility.invokeIntegrationSync(
            INTEGRATION_KEY,
            applicantId,
            'Applicant__c'
        );
    }

    /**
     * Builds the LWC extraction payload from the latest successful PAN TO CIN response.
     */
    @AuraEnabled
    public static Map<String, Object> getCinExtractionResult(String applicantId) {
        if (String.isBlank(applicantId)) {
            return failureResult('applicantId is required.');
        }

        List<Integration_Checklist__c> rows = [
            SELECT Response__c, Decrypted_Response__c, Status__c, Functional_Status__c
            FROM Integration_Checklist__c
            WHERE Applicant__c = :applicantId
              AND Integration_Master_Name__c = :INTEGRATION_KEY
              AND Status__c = :Constants.CHECKLIST_STATUS_SUCCESS
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            return failureResult('PAN TO CIN integration result was not found.');
        }

        Integration_Checklist__c checklist = rows[0];
        String rawResponse = String.isNotBlank(checklist.Decrypted_Response__c)
            ? checklist.Decrypted_Response__c
            : checklist.Response__c;

        List<String> cinNumbers = PANTOCINNAPIHandler.parseCinNumbersFromResponse(rawResponse);
        if (cinNumbers.isEmpty()) {
            return failureResult('PAN TO CIN response did not contain any CIN values.');
        }

        return new Map<String, Object>{
            'isSuccess'        => true,
            'docType'          => 'CIN',
            'cinNumbers'       => cinNumbers,
            'extractedDetails' => new Map<String, Object>{
                'cinNumber' => cinNumbers.size() == 1 ? cinNumbers[0] : null
            }
        };
    }

    private static Map<String, Object> failureResult(String message) {
        return new Map<String, Object>{
            'isSuccess'        => false,
            'message'          => message,
            'cinNumbers'       => new List<String>(),
            'extractedDetails' => new Map<String, Object>{ 'cinNumber' => null }
        };
    }
}