public with sharing class MNRLAPIController {
    
    /**
     * @description Initiate MNRL verification process for an applicant by invoking the integration
     * @param applicantId The ID of the applicant record to verify MNRL for
     * @return ApplicationUtility.IntegrationResponseWrapper Result containing the verification response
     */
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeMNRLAPI(String applicantId) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync(
            'Mobile Number Revocation List (MNRL) API',
            applicantId,
            'Applicant__c'
        );
        return response;
    }
}