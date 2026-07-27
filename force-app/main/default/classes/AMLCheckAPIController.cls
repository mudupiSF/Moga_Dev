public with sharing class AMLCheckAPIController {

    /**
     * Runs AML Check for a single applicant via Integration Master.
     */
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeAMLCheckAPI(String applicantId) {
        return ApplicationUtility.invokeIntegrationSync(
            AMLCheckAPIHandler.INTEGRATION_KEY,
            applicantId,
            'Applicant__c'
        );
    }

    /**
     * Runs AML Check for every active applicant on the application (Dedupe Next forward).
     */
    @AuraEnabled
    public static Map<String, Object> invokeAMLCheckForApplication(String applicationId) {
        if (String.isBlank(applicationId)) {
            return new Map<String, Object>{
                'isSuccess' => false,
                'message' => 'Application id is required.'
            };
        }

        Callable provider = (Callable) Type.forName('AmlCheckController').newInstance();
        return (Map<String, Object>) provider.call(
            'createAmlInvestigationRecords',
            new Map<String, Object>{
                'applicationId' => applicationId,
                'recordId' => applicationId
            }
        );
    }
}