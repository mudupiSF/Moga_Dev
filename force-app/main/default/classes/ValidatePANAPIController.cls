public with sharing class ValidatePANAPIController {
    
    /**
     * @description Initiate PAN verification process for a applicant by invoking the integration
     * @param applicantId The ID of the applicant record to verify PAN for
     * @param panCardNumber The PAN card number to verify
     * @return ApplicationUtility.IntegrationResponseWrapper Result containing the verification response
     */
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeValidatePANAPI(String applicantId, String panCardNumber) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync('Validate PAN API', applicantId, 'Applicant__c');
        return response;
    }

    /** Mark the PAN card number as verified.
     * @param applicantId The ID of the applicant record to mark PAN as verified
     * @param verified The boolean value to mark the PAN as verified
     * @return void
     */
    @AuraEnabled
    public static void markPanVerified(Id applicantId, Boolean verified) {
        Applicant__c applicant = new Applicant__c(Id = applicantId, PAN_Number_Verified__c = verified);
        update applicant;
        if (verified == true) {
            KYCInfoController.relabelVerifiedChecklist(applicantId, 'PAN');
        }
    }

}