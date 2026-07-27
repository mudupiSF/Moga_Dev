public with sharing class SendEmailOTPAPIController {

    // OTP expiry time in minutes
    private static final Integer OTP_EXPIRY_MINUTES = 5;

    /**
     * @description Generate OTP to applicant's email
     * @param applicantId The ID of the applicant record
     * @param emailAddress The email address of the applicant
     * @return OTPVerificationWrapper Result containing success status and message
     */
    @AuraEnabled
    public static OTPVerificationWrapper generateOTP(String applicantId, String emailAddress) {
        OTPVerificationWrapper result = new OTPVerificationWrapper();
        Applicant__c applicantRecord = new Applicant__c(Id = applicantId);
        try {
            String otpCode = generateOTP();

            applicantRecord.Email__c = emailAddress;
            applicantRecord.Email_Verification_Code__c = otpCode;
            applicantRecord.Email_Verification_Code_Generated_Time__c = Datetime.now();
            update applicantRecord;

            result = generateVerificationResponse(true, 'OTP was generated.');
        }
        catch (Exception e) {
            result = generateVerificationResponse(false, e.getMessage());
        }
        return result;
    }

    /**
    * @description Verify OTP entered by user
    * @param applicantId The ID of the applicant record
    * @param verificationType The type of verification (phone or email)
    * @param otp The OTP entered by user
    * @return OTPVerificationWrapper Result containing success status and message
    */
    /*@AuraEnabled
    public static OTPVerificationWrapper verifyOTP(String applicantId, String verificationType, String otp) {
        OTPVerificationWrapper result = new OTPVerificationWrapper();
        Applicant__c applicant = new Applicant__c();
        Boolean hasValidationError = false;
        Boolean hasApplicantChanged = false;

        try {
            List<Applicant__c> applicants = [
                SELECT Id, Phone_Verification_Code__c, Phone_Verification_Code_Generated_Time__c, Phone_Verified__c,
                    Email_Verification_Code__c, Email_Verification_Code_Generated_Time__c, Email_Verified__c
                FROM Applicant__c
                WHERE Id = :applicantId
            ];
            if (!applicants.isEmpty()) {
                applicant = applicants[0];
                if (verificationType == 'mobile') {
                    if (String.isBlank(applicant.Phone_Verification_Code__c) && !hasValidationError) {
                        hasValidationError = true;
                        result = generateVerificationResponse(false, 'OTP was not generated.');
                    }
                    if (applicant.Phone_Verification_Code_Generated_Time__c != null && !hasValidationError) {
                        Long minutesSinceOTP = Datetime.now().getTime() - applicant.Phone_Verification_Code_Generated_Time__c.getTime();
                        minutesSinceOTP = minutesSinceOTP / (1000 * 60);
                        if (minutesSinceOTP > OTP_EXPIRY_MINUTES) {
                            applicant.Phone_Verification_Code__c = null;
                            applicant.Phone_Verification_Code_Generated_Time__c = null;
                            hasValidationError = true;
                            hasApplicantChanged = true;
                            result = generateVerificationResponse(false, 'OTP has expired.');
                        }
                    }
                    if (!hasValidationError) {
                        if (applicant.Phone_Verification_Code__c == otp) {
                            applicant.Phone_Verified__c = true;
                            applicant.Phone_Verification_Code__c = null;
                            applicant.Phone_Verification_Code_Generated_Time__c = null;
                            hasApplicantChanged = true;
                            result = generateVerificationResponse(true, 'OTP was verified.');
                        }
                        else {
                            result = generateVerificationResponse(false, 'Invalid OTP.');
                        }
                    }
                }
                else if (verificationType == 'email') {
                    if (String.isBlank(applicant.Email_Verification_Code__c) && !hasValidationError) {
                        hasValidationError = true;
                        result = generateVerificationResponse(false, 'OTP was not generated.');
                    }
                    if (applicant.Email_Verification_Code_Generated_Time__c != null && !hasValidationError) {
                        Long minutesSinceOTP = Datetime.now().getTime() - applicant.Email_Verification_Code_Generated_Time__c.getTime();
                        minutesSinceOTP = minutesSinceOTP / (1000 * 60);
                        if (minutesSinceOTP > OTP_EXPIRY_MINUTES) {
                            applicant.Email_Verification_Code__c = null;
                            applicant.Email_Verification_Code_Generated_Time__c = null;
                            hasValidationError = true;
                            hasApplicantChanged = true;
                            result = generateVerificationResponse(false, 'OTP has expired.');
                        }
                    }
                    if (!hasValidationError) {
                        if (applicant.Email_Verification_Code__c == otp) {
                            applicant.Email_Verified__c = true;
                            applicant.Email_Verification_Code__c = null;
                            applicant.Email_Verification_Code_Generated_Time__c = null;
                            hasApplicantChanged = true;
                            result = generateVerificationResponse(true, 'OTP was verified.');
                        }
                        else {
                            result = generateVerificationResponse(false, 'Invalid OTP.');
                        }
                    }
                }
            }
        }
        catch (Exception e) {
            result = generateVerificationResponse(false, e.getMessage());
        }
        finally {
            if (hasApplicantChanged) {
                update applicant;
            }
        }
        return result;
    }*/

    private static OTPVerificationWrapper generateVerificationResponse(Boolean success, String message) {
        OTPVerificationWrapper result = new OTPVerificationWrapper();
        result.success = success;
        result.message = message;
        return result;
    }

    /**
     * @description Generate a random 6-digit OTP
     * @return String 6-digit OTP
     */
    private static String generateOTP() {
        Integer otpNumber = Math.round(Math.random() * 900000) + 100000;
        return String.valueOf(otpNumber);
    }

    /**
     * @description Initiate email OTP send process for an applicant by invoking the integration
     * @param applicantId The ID of the applicant record to send email OTP for
     * @return ApplicationUtility.IntegrationResponseWrapper Result containing the integration response
     */
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeSendEmailOTPAPI(String applicantId) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync(
            'Send Email OTP API',
            applicantId,
            'Applicant__c'
        );
        return response;
    }

    public class OTPVerificationWrapper {
        @AuraEnabled
        public Boolean success                     {get;set;}
        @AuraEnabled
        public String message                      {get;set;}
        @AuraEnabled
        public String emailAddress                 {get;set;}
        @AuraEnabled
        public Boolean emailVerified               {get;set;}
        @AuraEnabled
        public Datetime otpGeneratedTime           {get;set;}
        @AuraEnabled
        public Boolean canRetry                    {get;set;}
        @AuraEnabled
        public Long remainingSeconds               {get;set;}
    }
}