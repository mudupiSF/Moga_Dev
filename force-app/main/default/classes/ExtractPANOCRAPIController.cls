public with sharing class ExtractPANOCRAPIController {
    
    @AuraEnabled
    public static Applicant__c getApplicant(Id applicantId) {
        return [SELECT Id, PAN_Number__c, Date_of_Birth__c, Customer_First_Name__c, Customer_Last_Name__c FROM Applicant__c WHERE Id = :applicantId LIMIT 1];
    }
    
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokePANOCRAPI(String applicantId, String panCardNumber) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync('PAN OCR API', applicantId, 'Applicant__c');
        return response;
    }

    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeValidatePANAPI(String applicantId, String panCardNumber) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync('Validate PAN API', applicantId, 'Applicant__c');
        return response;
    }
    
    /** Flips Applicant__c.PAN_Number_Verified__c so the UI status survives a page reload. */
    @AuraEnabled
    public static void markPanVerified(Id applicantId, Boolean verified) {
        if (applicantId == null) return;
        setPanVerifiedFlag(applicantId, verified == true);
    }

    private static void setPanVerifiedFlag(Id applicantId, Boolean verified) {
        try {
            Applicant__c applicant = new Applicant__c(Id = applicantId, PAN_Number_Verified__c = verified);
            update applicant;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'documentVerificationController.setPanVerifiedFlag: ' + e.getMessage());
        }
    }

}