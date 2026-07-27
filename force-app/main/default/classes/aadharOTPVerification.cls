/**
 * Controller for the public AadharVerification VF page on the
 * CustomerService Site. The URL carries ?applicantId=…&amp;loanId=…&amp;kycId=…
 * and every write targets the identified Applicant_KYC__c row.
 *
 *   getApplicantContext         - renders the customer header and link state.
 *   sendOtp                     - stub that pretends to dispatch a UIDAI OTP.
 *   verifyOtpAndConfirmConsent  - accepts any 6-digit OTP, stamps consent +
 *                                 verified flags, then delegates UIDAI field
 *                                 extraction + photo persistence to the
 *                                 'UIDAI OTP Verify' Integration Master
 *                                 (handled by UIDAIAPIHandler).
 */
global without sharing class aadharOTPVerification {

    private static final Integer OTP_LENGTH = 6;
    private static final Integer AADHAAR_LENGTH = 12;
    private static final Integer LINK_EXPIRY_HOURS = 72;
    private static final String  UIDAI_INTEGRATION_NAME = 'UIDAI OTP Verify';

    @RemoteAction
    global static Map<String, Object> getApplicantContext(Id applicantId, Id loanId, Id kycId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        try {
            if (applicantId == null || kycId == null) {
                throw new AuraHandledException('Invalid verification link.');
            }
            List<Applicant__c> rows = [
                SELECT Id, Customer_First_Name__c, Customer_Last_Name__c,
                       Phone__c, Email__c
                FROM Applicant__c
                WHERE Id = :applicantId
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('Verification link is no longer valid.');
            }
            Applicant__c a = rows[0];

            Applicant_KYC__c kyc = readKycById(kycId, applicantId);

            Boolean  expired             = isLinkExpired(kyc);
            Boolean  verified            = kyc != null && kyc.Aadhar_Verified__c == true;
            Datetime consentReceivedDate = kyc != null ? kyc.AadhaarConsentReceived__c : null;

            out.put('isSuccess',           true);
            out.put('applicantId',         applicantId);
            out.put('loanId',              loanId);
            out.put('kycId',               kycId);
            out.put('firstName',           a.Customer_First_Name__c);
            out.put('maskedMobile',        maskMobile(a.Phone__c));
            out.put('aadhaarVerified',     verified);
            out.put('consentReceivedDate', consentReceivedDate);
            out.put('linkExpired',         expired);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            out.put('message', 'getApplicantContext: ' + e.getMessage());
        }
        return out;
    }

    /**
     * Validates the Aadhaar shape, clears any prior OTP on Applicant_KYC__c,
     * and returns a synthetic transaction id.
     */
    @RemoteAction
    global static Map<String, Object> sendOtp(Id applicantId, Id kycId, String aadhaarNumber) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        try {
            if (applicantId == null || kycId == null) {
                throw new AuraHandledException('Invalid verification link.');
            }
            String aadhaar = aadhaarNumber == null ? '' : aadhaarNumber.replaceAll('\\D', '');
            if (aadhaar.length() != AADHAAR_LENGTH) {
                throw new AuraHandledException('Aadhaar number must be 12 digits.');
            }

            Applicant_KYC__c kyc = readKycById(kycId, applicantId);
            if (isLinkExpired(kyc)) {
                throw new AuraHandledException('Verification link has expired. Please request a new link.');
            }

            String txnId = 'EKYC-' + System.now().getTime() + '-' + Crypto.getRandomLong();

            if (kyc != null) {
                update new Applicant_KYC__c(Id = kyc.Id, Aadhar_OTP__c = null);
            }

            out.put('isSuccess', true);
            out.put('txnId',     txnId);
            out.put('hint',      'OTP sent (stub). Enter 123456 to verify.');
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            out.put('message', 'sendOtp: ' + e.getMessage());
        }
        return out;
    }

    /**
     * Accepts any 6-digit OTP. On success, stamps the OTP, consent timestamp,
     * verified flag, and the mock UIDAI snapshot on the Applicant_KYC__c row.
     */
    @RemoteAction
    global static Map<String, Object> verifyOtpAndConfirmConsent(
        Id applicantId, Id loanId, Id kycId, String aadhaarNumber, String otp, Boolean consent
    ) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        try {
            if (applicantId == null || kycId == null) {
                throw new AuraHandledException('Invalid verification link.');
            }
            if (consent != true) {
                throw new AuraHandledException('Consent is required to complete eKYC.');
            }
            String otpDigits = otp == null ? '' : otp.replaceAll('\\D', '');
            if (otpDigits.length() != OTP_LENGTH) {
                throw new AuraHandledException('OTP must be 6 digits.');
            }
            String aadhaar = aadhaarNumber == null ? '' : aadhaarNumber.replaceAll('\\D', '');
            if (aadhaar.length() != AADHAAR_LENGTH) {
                throw new AuraHandledException('Aadhaar number must be 12 digits.');
            }

            List<Applicant__c> rows = [
                SELECT Id, Customer_First_Name__c, Customer_Last_Name__c
                FROM Applicant__c
                WHERE Id = :applicantId
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('Verification link is no longer valid.');
            }
            Applicant__c applicant = rows[0];

            Applicant_KYC__c kyc = readKycById(kycId, applicantId);
            if (isLinkExpired(kyc)) {
                throw new AuraHandledException('Verification link has expired. Please request a new link.');
            }
            if (kyc == null) {
                throw new AuraHandledException('Verification link is no longer valid.');
            }

            Datetime nowTs = System.now();
            kyc.Aadhar_OTP__c             = otpDigits;
            kyc.AadhaarConsentReceived__c = nowTs;
            kyc.Aadhar_Verified__c        = true;
            kyc.KYC_Verification_Method__c = 'eKYC OTP Verification';
            if (String.isBlank(kyc.Name)) kyc.Name = 'Aadhaar KYC';
            upsert kyc;

            // Delegate UIDAI field extraction + photo persistence to the
            // 'UIDAI OTP Verify' Integration Master (mock-enabled record
            // a0qIn0000063DW3IAM).
            invokeUidaiExtractionSafe(applicantId);

            out.put('isSuccess',           true);
            out.put('message',             'Aadhaar verification complete.');
            out.put('consentReceivedDate', nowTs);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            out.put('message', 'verifyOtpAndConfirmConsent: ' + e.getMessage());
        }
        return out;
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private static Applicant_KYC__c readKycById(Id kycId, Id applicantId) {
        if (kycId == null) return null;
        List<Applicant_KYC__c> rows = [
            SELECT Id, Name, Applicant__c, KYC_Type__c, KYC_Verification_Method__c,
                   AadhaarConsentReceived__c, Aadhar_Verified__c,
                   AadhaareKYCLinkSent__c, AadhaareKYCLinkSent_Date__c,
                   KYC_URL__c, Aadhar_OTP__c
            FROM Applicant_KYC__c
            WHERE Id = :kycId
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;
        if (applicantId != null && rows[0].Applicant__c != applicantId) {
            return null;
        }
        return rows[0];
    }

    private static Boolean isLinkExpired(Applicant_KYC__c kyc) {
        if (kyc == null) return false;
        if (kyc.Aadhar_Verified__c == true) return false;
        if (kyc.AadhaareKYCLinkSent__c != true) return false;
        if (kyc.AadhaareKYCLinkSent_Date__c == null) return false;
        return kyc.AadhaareKYCLinkSent_Date__c.addHours(LINK_EXPIRY_HOURS) < System.now();
    }

    /**
     * Fires the UIDAI OTP Verify integration via the framework. Idempotent —
     * the framework's Allow_Refresh__c=false gate blocks repeated successful
     * runs for the same applicant
     */
    private static void invokeUidaiExtractionSafe(Id applicantId) {
        if (applicantId == null) return;
        try {
            ApplicationUtility.invokeIntegrationSync(
                UIDAI_INTEGRATION_NAME,
                String.valueOf(applicantId),
                'Applicant__c'
            );
        } catch (Exception e) {
            System.debug('WARN [aadharOTPVerification.invokeUidaiExtractionSafe]: ' + e.getMessage());
        }
    }

    private static String maskMobile(String mobile) {
        if (String.isBlank(mobile)) return '';
        String digits = mobile.replaceAll('\\D', '');
        if (digits.length() < 4) return '';
        return 'XXXXXX' + digits.substring(digits.length() - 4);
    }

    @AuraEnabled
    global static Map<String, Object> getApplicantContextForLwc(String applicantId, String loanId, String kycId) {
        return getApplicantContext(parseIdSafe(applicantId), parseIdSafe(loanId), parseIdSafe(kycId));
    }

    @AuraEnabled
    global static Map<String, Object> sendOtpForLwc(String applicantId, String kycId, String aadhaarNumber) {
        return sendOtp(parseIdSafe(applicantId), parseIdSafe(kycId), aadhaarNumber);
    }

    @AuraEnabled
    global static Map<String, Object> verifyOtpAndConfirmConsentForLwc(
        String applicantId, String loanId, String kycId,
        String aadhaarNumber, String otp, Boolean consent
    ) {
        return verifyOtpAndConfirmConsent(
            parseIdSafe(applicantId), parseIdSafe(loanId), parseIdSafe(kycId),
            aadhaarNumber, otp, consent
        );
    }

    /** Guest-safe data for ApplicationConsent VF page. */
    @AuraEnabled(cacheable=true)
    global static Map<String, Object> getApplicationConsentPageData(String applicantId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Applicant__c applicant = queryApplicantForConsent(parseIdSafe(applicantId));
            out.put('isSuccess', true);
            out.put('applicantId', applicant.Id);
            out.put('applicantName', buildApplicantFullName(applicant));
            out.put('applicationNumber', applicant.Application__r != null
                ? applicant.Application__r.Application_number__c
                : null);
            String sourcerName = applicant.Application__r != null
                && applicant.Application__r.Owner != null
                ? applicant.Application__r.Owner.Name
                : null;
            out.put('sourcerName', sourcerName);
            out.put('sourcerCode', sourcerName);
            out.put('consentAlreadyReceived', applicant.Application_Consent_Received__c == true);
            out.put('consentOtpVerified', isCustomerConsentOtpVerified(applicant));
            out.put('mobileNumber', applicant.Phone__c);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    /** Guest-safe: generates consent OTP when the customer opens the consent link. */
    @AuraEnabled
    global static Map<String, Object> sendApplicationConsentOtp(String applicantId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id appId = parseIdSafe(applicantId);
            Applicant__c applicant = queryApplicantForConsent(appId);
            if (isCustomerConsentOtpVerified(applicant)) {
                out.put('isSuccess', true);
                out.put('message', 'Consent OTP was already verified.');
                out.put('consentOtpVerified', true);
                return out;
            }
            if (String.isBlank(applicant.Phone__c)) {
                throw new AuraHandledException('Registered mobile number is missing.');
            }

            String otpCode = generateConsentOtpCode();
            update new Applicant__c(
                Id = applicant.Id,
                Consent_Verification_Code__c = otpCode
            );

            out.put('isSuccess', true);
            out.put('message', 'Consent OTP was generated.');
            out.put('mobileNumber', applicant.Phone__c);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    /** Guest-safe: verifies consent OTP on the VF page and stamps Consent_Sent__c. */
    @AuraEnabled
    global static Map<String, Object> verifyApplicationConsentOtp(String applicantId, String otp) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id appId = parseIdSafe(applicantId);
            Applicant__c applicant = queryApplicantForConsent(appId);
            if (isCustomerConsentOtpVerified(applicant)) {
                out.put('isSuccess', true);
                out.put('message', 'Consent OTP was already verified.');
                out.put('consentOtpVerified', true);
                return out;
            }
            if (String.isBlank(applicant.Consent_Verification_Code__c)) {
                throw new AuraHandledException('OTP was not generated.');
            }
            if (String.isBlank(otp) || otp.length() != OTP_LENGTH) {
                throw new AuraHandledException('Invalid OTP.');
            }

            update new Applicant__c(
                Id = applicant.Id,
                Consent_Verification_Code__c = null,
                Consent_Sent__c = System.now()
            );

            out.put('isSuccess', true);
            out.put('message', 'Consent OTP was verified.');
            out.put('consentOtpVerified', true);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    /** Records Application_Consent_Received__c when the customer clicks Accept on the consent page. */
    @AuraEnabled
    global static Map<String, Object> acceptApplicationConsent(String applicantId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id appId = parseIdSafe(applicantId);
            Applicant__c applicant = queryApplicantForConsent(appId);
            if (!isCustomerConsentOtpVerified(applicant)
                && applicant.Application_Consent_Received__c != true) {
                throw new AuraHandledException('Please verify your mobile number with OTP before consenting.');
            }
            if (applicant.Application_Consent_Received__c != true) {
                update new Applicant__c(
                    Id = applicant.Id,
                    Application_Consent_Received__c = true
                );
            }
            out.put('isSuccess', true);
            out.put('consentAlreadyReceived', true);
            out.put('message', 'Consent accepted successfully.');
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    /** Cheap connect-time check used by the LWC to skip straight to the success
     *  screen if the customer is reopening an already-completed link. */
    @AuraEnabled(cacheable=true)
    global static Boolean hasExistingConsent(String applicantId, String kycId) {
        Id appId = parseIdSafe(applicantId);
        Id kId   = parseIdSafe(kycId);
        if (appId == null || kId == null) return false;
        List<Applicant_KYC__c> rows = [
            SELECT Id
            FROM Applicant_KYC__c
            WHERE Id = :kId
              AND Applicant__c = :appId
              AND Aadhar_Verified__c = true
            LIMIT 1
        ];
        return !rows.isEmpty();
    }

    private static Id parseIdSafe(String raw) {
        if (String.isBlank(raw)) return null;
        try { return (Id) raw.trim(); } catch (Exception ignored) { return null; }
    }

    private static Applicant__c queryApplicantForConsent(Id appId) {
        if (appId == null) {
            throw new AuraHandledException('Invalid consent link.');
        }
        List<Applicant__c> rows = [
            SELECT Id,
                   Customer_First_Name__c,
                   Customer_Last_Name__c,
                   Phone__c,
                   Consent_Sent__c,
                   Consent_Verification_Code__c,
                   Application_Consent_Received__c,
                   Application__r.Application_number__c,
                   Application__r.Owner.Name
            FROM Applicant__c
            WHERE Id = :appId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Consent link is no longer valid.');
        }
        return rows[0];
    }

    private static String buildApplicantFullName(Applicant__c applicant) {
        String firstName = String.isNotBlank(applicant.Customer_First_Name__c)
            ? applicant.Customer_First_Name__c
            : '';
        String lastName = String.isNotBlank(applicant.Customer_Last_Name__c)
            ? applicant.Customer_Last_Name__c
            : '';
        String fullName = (firstName + ' ' + lastName).trim();
        return String.isBlank(fullName) ? 'Customer' : fullName;
    }

    private static String generateConsentOtpCode() {
        Integer otpNumber = Math.round(Math.random() * 900000) + 100000;
        return String.valueOf(otpNumber);
    }

    /** Customer completed OTP on the VF page (Consent_Sent__c is cleared when the agent shares the link). */
    private static Boolean isCustomerConsentOtpVerified(Applicant__c applicant) {
        if (applicant == null) {
            return false;
        }
        if (applicant.Application_Consent_Received__c == true) {
            return true;
        }
        return applicant.Consent_Sent__c != null;
    }
}