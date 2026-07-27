public with sharing class SendPhoneOTPAPIController {

    // OTP expiry time in minutes
    private static final Integer OTP_EXPIRY_MINUTES = 5;

    /**
     * @description Generate OTP to applicant's mobile number
     * @param applicantId The ID of the applicant record
     * @param phoneNumber The phone number of the applicant
     * @return OTPVerificationWrapper Result containing success status and message
     */
    @AuraEnabled
    public static OTPVerificationWrapper generateOTP(String applicantId, String phoneNumber) {
        OTPVerificationWrapper result = new OTPVerificationWrapper();
        Applicant__c applicantRecord = new Applicant__c(Id = applicantId);
        try { 
            // Generate 6-digit OTP
            String otpCode = generateOTP();
            
            // Update applicant with OTP and timestamp
            applicantRecord.Phone__c = phoneNumber;
            applicantRecord.Phone_Verification_Code__c = otpCode;
            applicantRecord.Phone_Verification_Code_Generated_Time__c = Datetime.now();
            update applicantRecord;
            
            //Generate Verification Response
            result = generateVerificationResponse(true, 'OTP was generated.');
        }
        catch (Exception e) {
            //Generate Verification Response
            result = generateVerificationResponse(false, e.getMessage());
        }
        return result;
    }

    /**
     * @description Generate a unique 6-digit consent OTP for Basic Details consent flow.
     *              Stored on Consent_Verification_Code__c (separate from mobile verification).
     *              Skips if consent link was already sent or application consent received.
     */
    @AuraEnabled
    public static OTPVerificationWrapper generateConsentOTP(String applicantId, String phoneNumber) {
        OTPVerificationWrapper result = new OTPVerificationWrapper();
        try {
            List<Applicant__c> existing = [
                SELECT Id, Consent_Sent__c, Application_Consent_Received__c
                FROM Applicant__c
                WHERE Id = :applicantId
                LIMIT 1
            ];
            if (!existing.isEmpty()
                && (existing[0].Consent_Sent__c != null
                    || existing[0].Application_Consent_Received__c == true)) {
                return generateVerificationResponse(true, 'Consent OTP was already verified.');
            }
            Applicant__c applicantRecord = new Applicant__c(
                Id = applicantId,
                Consent_Verification_Code__c = generateOTP()
            );
            update applicantRecord;
            result = generateVerificationResponse(true, 'Consent OTP was generated.');
        } catch (Exception e) {
            result = generateVerificationResponse(false, e.getMessage());
        }
        return result;
    }

    /**
     * @description Verify OTP entered by user
     * @param applicantId The ID of the applicant record
     * @param verificationType The type of verification (phone or email)
     * @param otp The OTP entered by user
     * @return Map<String, Object> Result containing success status and message
     */
    @AuraEnabled
    public static OTPVerificationWrapper verifyOTP(String applicantId, String verificationType, String otp) {
        OTPVerificationWrapper result = new OTPVerificationWrapper();
        Applicant__c applicant = new Applicant__c();
        Boolean hasValidationError = false;
        String verificationStatus = '';
        Boolean hasApplicantChanged = false;

        try {
            // Get applicant record
            List<Applicant__c> applicants = [   SELECT Id, Phone_Verification_Code__c,
                                                Phone_Verification_Code_Generated_Time__c, Phone_Verified__c,
                                                Email_Verification_Code__c, Email_Verification_Code_Generated_Time__c, Email_Verified__c,
                                                Consent_Verification_Code__c,
                                                Consent_Sent__c, Application_Consent_Received__c
                                                FROM Applicant__c
                                                WHERE Id = :applicantId];
            if(!applicants.isEmpty()) {
                applicant = applicants[0];
                if (verificationType == 'consent') {
                    if (applicant.Consent_Sent__c != null
                        || applicant.Application_Consent_Received__c == true)
                    {
                        result = generateVerificationResponse(true, 'Consent OTP was already verified.');
                    }
                    else {
                        if (String.isBlank(applicant.Consent_Verification_Code__c)) {
                            hasValidationError = true;
                            result = generateVerificationResponse(false, 'OTP was not generated.');
                        }
                        if (!hasValidationError) {
                            // TODO: Uncomment this when the OTP verification is implemented
                            //if (applicant.Consent_Verification_Code__c == otp) {
                            if (String.isNotBlank(otp) && otp.length() == 6) {
                                applicant.Consent_Verification_Code__c = null;
                                applicant.Consent_Sent__c = System.now();
                                hasApplicantChanged = true;
                                result = generateVerificationResponse(true, 'Consent OTP was verified.');
                            }
                            else {
                                result = generateVerificationResponse(false, 'Invalid OTP.');
                            }
                        }
                    }
                }
                else if(verificationType == 'mobile') {
                    if (String.isBlank(applicant.Phone_Verification_Code__c) && !hasValidationError) {
                        hasValidationError = true;
                        //Generate Verification Response
                        result = generateVerificationResponse(false, 'OTP was not generated.');
                    }
                    // Check if OTP has expired
                    if (applicant.Phone_Verification_Code_Generated_Time__c != null && !hasValidationError) {
                        Long minutesSinceOTP = Datetime.now().getTime() - applicant.Phone_Verification_Code_Generated_Time__c.getTime();
                        minutesSinceOTP = minutesSinceOTP / (1000 * 60); // Convert to minutes
                        if (minutesSinceOTP > OTP_EXPIRY_MINUTES) {
                            // Clear expired OTP
                            applicant.Phone_Verification_Code__c = null;
                            applicant.Phone_Verification_Code_Generated_Time__c = null;
                            hasValidationError = true;
                            hasApplicantChanged = true;
                            //Generate Verification Response
                            result = generateVerificationResponse(false, 'OTP has expired.');
                        }
                    }
                    if(!hasValidationError) {
                        // Verify OTP
                        // TODO: Uncomment this when the OTP verification is implemented
                        //if (applicant.Phone_Verification_Code__c == otp) {
                        if (String.isNotBlank(otp) && otp.length() == 6) {
                            applicant.Phone_Verified__c = true;
                            applicant.Phone_Verification_Code__c = null;
                            applicant.Phone_Verification_Code_Generated_Time__c = null;
                            hasApplicantChanged = true;
                            //Generate Verification Response
                            result = generateVerificationResponse(true, 'OTP was verified.');
                        }
                        else {
                            //Generate Verification Response
                            result = generateVerificationResponse(false, 'Invalid OTP.');
                        }
                    }
                }
                else if(verificationType == 'email') {
                    if (String.isBlank(applicant.Email_Verification_Code__c) && !hasValidationError) {
                        hasValidationError = true;
                        //Generate Verification Response
                        result = generateVerificationResponse(false, 'OTP was not generated.');
                    }
                    // Check if OTP has expired
                    if (applicant.Email_Verification_Code_Generated_Time__c != null && !hasValidationError) {
                        Long minutesSinceOTP = Datetime.now().getTime() - applicant.Email_Verification_Code_Generated_Time__c.getTime();
                        minutesSinceOTP = minutesSinceOTP / (1000 * 60); // Convert to minutes
                        if (minutesSinceOTP > OTP_EXPIRY_MINUTES) {
                            // Clear expired OTP
                            applicant.Email_Verification_Code__c = null;
                            applicant.Email_Verification_Code_Generated_Time__c = null;
                            hasValidationError = true;
                            hasApplicantChanged = true;
                            //Generate Verification Response
                            result = generateVerificationResponse(false, 'OTP has expired.');
                        }
                    }
                    if(!hasValidationError) {
                        // Verify OTP
                        // TODO: Uncomment this when the OTP verification is implemented
                        //if (applicant.Email_Verification_Code__c == otp) {
                        if (String.isNotBlank(otp) && otp.length() == 6) {
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
            //Generate Verification Response
            result = generateVerificationResponse(false, e.getMessage());
        }
        finally {
            if(hasApplicantChanged) {
                update applicant;
            }
        }
        return result;
    }

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
        Integer otpNumber = Math.round(Math.random() * 900000) + 100000; // 6-digit number between 100000-999999
        return String.valueOf(otpNumber);
    }

    /**
     * @description Initiate phone OTP send process for an applicant by invoking the integration
     * @param applicantId The ID of the applicant record to send phone OTP for
     * @return ApplicationUtility.IntegrationResponseWrapper Result containing the integration response
     */
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeSendPhoneOTPAPI(String applicantId) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync(
            'Send Phone OTP API',
            applicantId,
            'Applicant__c'
        );
        return response;
    }

    public class OTPVerificationWrapper {
        @AuraEnabled
        public Boolean success			            {get;set;}
        @AuraEnabled
        public String message				        {get;set;}
        @AuraEnabled
        public String mobilePhone				    {get;set;}
        @AuraEnabled
        public Boolean mobileVerified				{get;set;}
        @AuraEnabled
        public Datetime otpGeneratedTime			{get;set;}
        @AuraEnabled
        public Boolean canRetry				        {get;set;}
        @AuraEnabled
        public Long remainingSeconds				{get;set;}
    }
}