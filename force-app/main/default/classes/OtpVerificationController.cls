public with sharing class OtpVerificationController {

    /**
     * Persists OTP verification details on Applicant__c for mobile/email flows.
     *
     * @param applicantId Applicant__c Id.
     * @param otpType     Supported values: 'mobile' or 'email'.
     * @param otp         Verified OTP value.
     * @param ipAddress   Client IP address (reserved for audit usage).
     * @return            True when save succeeds, otherwise false.
     */
    @AuraEnabled
    public static Boolean saveApplicantOtpVerification(Id applicantId, String otpType, String otp, String ipAddress) {
        if (applicantId == null || String.isBlank(otpType) || String.isBlank(otp)) {
            return false;
        }

        String normalizedType = otpType.trim().toLowerCase();
        Applicant__c applicant = new Applicant__c(Id = applicantId);

        if (normalizedType == 'mobile') {
            applicant.Phone_Verification_Code__c = otp;
            applicant.Phone_Verified__c = true;
        } else if (normalizedType == 'email') {
            applicant.Email_Verification_Code__c = otp;
            applicant.Email_Verified__c = true;
        } else {
            return false;
        }

        try {
            update applicant;
            return true;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'OtpVerificationController.saveApplicantOtpVerification: ' + ex.getMessage());
            return false;
        }
    }
}