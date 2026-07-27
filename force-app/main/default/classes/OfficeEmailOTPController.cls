/**
 * @description Office Email OTP generation + verification, keyed on the
 *              Applicant_Address__c (Office Address) record. 
 */
public with sharing class OfficeEmailOTPController {

    private static final Integer OTP_EXPIRY_MINUTES = 5;
    private static final String ADDRESS_TYPE_OFFICE = 'Office Address';
    private static final String INTEGRATION_NAME    = 'Send Office Email OTP API';

    /**
     * @description Generate an OTP for the office email and store it on the
     *              Office Applicant_Address__c row (creating the row if needed).
     * @param applicantId  Applicant__c Id the office address belongs to
     * @param emailAddress Office email address to verify
     * @return OfficeOTPWrapper success flag, message, and the resolved addressId
     */
    @AuraEnabled
    public static OfficeOTPWrapper generateOTP(String applicantId, String emailAddress) {
        OfficeOTPWrapper result = new OfficeOTPWrapper();
        try {
            if (String.isBlank(applicantId)) {
                return buildResponse(false, 'Applicant Id is required.', null);
            }
            if (String.isBlank(emailAddress)) {
                return buildResponse(false, 'Email address is required.', null);
            }

            Applicant_Address__c addr = resolveOfficeAddress((Id) applicantId);
            addr.Email__c                                = emailAddress;
            addr.Email_Verification_Code__c              = generateOTPCode();
            addr.Email_Verification_Code_Generated_Time__c = Datetime.now();
            addr.Email_Verified__c                       = false;
            if (String.isBlank(addr.Name)) {
                addr.Name = ADDRESS_TYPE_OFFICE;
            }
            upsert addr;

            result = buildResponse(true, 'OTP was generated.', addr.Id);
            result.otpCode = addr.Email_Verification_Code__c;
        }
        catch (Exception e) {
            result = buildResponse(false, e.getMessage(), null);
        }
        return result;
    }

    /**
     * @description Verify the OTP entered against the Office address row.
     * @param addressId Applicant_Address__c Id (Office) holding the code
     * @param otp       OTP entered by the user
     * @return OfficeOTPWrapper success flag + message
     */
    @AuraEnabled
    public static OfficeOTPWrapper verifyOTP(String addressId, String otp) {
        OfficeOTPWrapper result = new OfficeOTPWrapper();
        Applicant_Address__c addr;
        Boolean hasValidationError = false;
        Boolean hasRecordChanged   = false;
        try {
            if (String.isBlank(addressId)) {
                return buildResponse(false, 'OTP was not generated.', null);
            }
            List<Applicant_Address__c> rows = [
                SELECT Id, Email_Verification_Code__c, Email_Verification_Code_Generated_Time__c, Email_Verified__c
                FROM Applicant_Address__c
                WHERE Id = :addressId
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                return buildResponse(false, 'OTP was not generated.', null);
            }
            addr = rows[0];

            if (String.isBlank(addr.Email_Verification_Code__c)) {
                hasValidationError = true;
                result = buildResponse(false, 'OTP was not generated.', addressId);
            }
            if (!hasValidationError && addr.Email_Verification_Code_Generated_Time__c != null) {
                Long minutesSinceOTP = Datetime.now().getTime() - addr.Email_Verification_Code_Generated_Time__c.getTime();
                minutesSinceOTP = minutesSinceOTP / (1000 * 60);
                if (minutesSinceOTP > OTP_EXPIRY_MINUTES) {
                    addr.Email_Verification_Code__c = null;
                    addr.Email_Verification_Code_Generated_Time__c = null;
                    hasValidationError = true;
                    hasRecordChanged   = true;
                    result = buildResponse(false, 'OTP has expired.', addressId);
                }
            }
            if (!hasValidationError) {
                if (addr.Email_Verification_Code__c == otp) {
                    addr.Email_Verified__c = true;
                    addr.Email_Verification_Code__c = null;
                    addr.Email_Verification_Code_Generated_Time__c = null;
                    hasRecordChanged = true;
                    result = buildResponse(true, 'OTP was verified.', addressId);
                }
                else {
                    result = buildResponse(false, 'Invalid OTP.', addressId);
                }
            }
        }
        catch (Exception e) {
            result = buildResponse(false, e.getMessage(), addressId);
        }
        finally {
            if (hasRecordChanged && addr != null) {
                update addr;
            }
        }
        return result;
    }

    /**
     * @description Trigger the office-email OTP delivery integration.
     *              Requires an Integration_Master__c record named
     *              'Send Office Email OTP API' bound to SendOfficeEmailOTPAPIHandler.
     * @param addressId Office Applicant_Address__c Id
     * @return ApplicationUtility.IntegrationResponseWrapper integration result
     */
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeSendOfficeEmailOTPAPI(String addressId) {
        return ApplicationUtility.invokeIntegrationSync(
            INTEGRATION_NAME,
            addressId,
            'Applicant_Address__c'
        );
    }

    /** Resolve the Office address row for an applicant, or stage a new one. */
    private static Applicant_Address__c resolveOfficeAddress(Id applicantId) {
        List<Applicant_Address__c> matches = [
            SELECT Id, Name, Applicant__c, Address_Type__c, Email__c, Email_Verified__c,
                   Email_Verification_Code__c, Email_Verification_Code_Generated_Time__c
            FROM Applicant_Address__c
            WHERE Applicant__c    = :applicantId
              AND Address_Type__c = :ADDRESS_TYPE_OFFICE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!matches.isEmpty()) {
            return matches[0];
        }
        return new Applicant_Address__c(
            Applicant__c    = applicantId,
            Address_Type__c = ADDRESS_TYPE_OFFICE
        );
    }

    private static OfficeOTPWrapper buildResponse(Boolean success, String message, Id addressId) {
        OfficeOTPWrapper result = new OfficeOTPWrapper();
        result.success   = success;
        result.message   = message;
        result.addressId = addressId;
        return result;
    }

    private static String generateOTPCode() {
        Integer otpNumber = Math.round(Math.random() * 900000) + 100000;
        return String.valueOf(otpNumber);
    }

    public class OfficeOTPWrapper {
        @AuraEnabled public Boolean success   { get; set; }
        @AuraEnabled public String  message   { get; set; }
        @AuraEnabled public Id      addressId { get; set; }
        @AuraEnabled public String  otpCode   { get; set; }
    }
}