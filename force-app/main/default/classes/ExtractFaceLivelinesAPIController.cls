/**
 * Thin controller for Face Livelines integration from Individual KYC.
 */
public with sharing class ExtractFaceLivelinesAPIController {

    private static final String INTEGRATION_KEY = FaceLivelinesAPIHandler.INTEGRATION_KEY;

    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeFaceLivelinesAPI(String applicantId) {
        return ApplicationUtility.invokeIntegrationSync(
            INTEGRATION_KEY,
            applicantId,
            'Applicant__c'
        );
    }

    @AuraEnabled
    public static Map<String, Object> getFaceLivelinesResult(String applicantId) {
        if (String.isBlank(applicantId)) {
            return failureResult('applicantId is required.');
        }

        List<Integration_Checklist__c> rows = [
            SELECT Response__c, Decrypted_Response__c, Status__c, Functional_Status__c, Functional_Failure_Reason__c
            FROM Integration_Checklist__c
            WHERE Applicant__c = :applicantId
              AND Integration_Master_Name__c = :INTEGRATION_KEY
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return failureResult('Face Liveliness response is not available.');
        }

        Integration_Checklist__c row = rows[0];
        String responseBody = String.isNotBlank(row.Decrypted_Response__c)
            ? row.Decrypted_Response__c
            : row.Response__c;
        Boolean success = Constants.CHECKLIST_STATUS_SUCCESS.equalsIgnoreCase(row.Status__c)
            || Constants.CHECKLIST_STATUS_SUCCESS.equalsIgnoreCase(row.Functional_Status__c);

        return new Map<String, Object>{
            'isSuccess' => success,
            'message' => success
                ? 'Face Liveliness completed.'
                : (String.isNotBlank(row.Functional_Failure_Reason__c)
                    ? row.Functional_Failure_Reason__c
                    : 'Face Liveliness failed.'),
            'responseBody' => responseBody,
            'status' => row.Status__c,
            'functionalStatus' => row.Functional_Status__c
        };
    }

    private static Map<String, Object> failureResult(String message) {
        return new Map<String, Object>{
            'isSuccess' => false,
            'message' => message,
            'responseBody' => null
        };
    }
}