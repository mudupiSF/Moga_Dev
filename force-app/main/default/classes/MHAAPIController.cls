public with sharing class MHAAPIController {
    
    /**
     * @description Initiate MHA verification process for an applicant by invoking the integration
     * @param applicantId The ID of the applicant record to verify MHA for
     * @return ApplicationUtility.IntegrationResponseWrapper Result containing the verification response
     */
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeMHAAPI(String applicantId) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync(
            'MHA API',
            applicantId,
            'Applicant__c'
        );
        return response;
    }
}