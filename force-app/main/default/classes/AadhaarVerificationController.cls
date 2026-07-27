/**
 * Callable dispatcher for the 5 Aadhaar verification flavours used by the
 * KYC Details visual picker.
 *
 *   initiateEkycOtpVerification     - generates the customer-facing Site URL
 *                                     and stamps link state on Applicant_KYC__c.
 *                                     Customer completes verification on the
 *                                     AadharVerification VF page which writes
 *                                     AadhaarConsentReceived__c and flips
 *                                     Aadhar_Verified__c.
 *   initiateBiometricVerification   - stub; stamps verification method.
 *   initiateVideoKYCVerification    - stub.
 *   initiateDigilockerVerification  - stub.
 *   initiateOfflineXMLVerification  - stub.
 *   pollAadhaarConsent              - returns current verify state and a
 *                                     72-hour link expiry flag.
 *
 * Every action operates on the Applicant_KYC__c row linked from the supplied
 * Document_CheckList__c (Current or Permanent bucket).
 */
public with sharing class AadhaarVerificationController implements Callable {

    private static final String ACTION_INIT_EKYC_OTP     = 'initiateEkycOtpVerification';
    private static final String ACTION_INIT_BIOMETRIC    = 'initiateBiometricVerification';
    private static final String ACTION_INIT_VIDEO_KYC    = 'initiateVideoKYCVerification';
    private static final String ACTION_INIT_DIGILOCKER   = 'initiateDigilockerVerification';
    private static final String ACTION_INIT_OFFLINE_XML  = 'initiateOfflineXMLVerification';
    private static final String ACTION_POLL_CONSENT      = 'pollAadhaarConsent';

    private static final String METHOD_EKYC_OTP     = 'eKYC OTP Verification';
    private static final String METHOD_BIOMETRIC    = 'Biometric Verification';
    private static final String METHOD_VIDEO_KYC    = 'Video KYC Verification';
    private static final String METHOD_DIGILOCKER   = 'Digilocker Verification';
    private static final String METHOD_OFFLINE_XML  = 'Offline Aadhaar XML';

    private static final String KYC_TYPE_AADHAR = 'Aadhar';

    private static final String ADDRESS_TYPE_CURRENT   = 'Current Residential Address';
    private static final String ADDRESS_TYPE_PERMANENT = 'Permanent Residential Address';

    private static final String SITE_NAME    = 'CustomerService';

    private static final String VF_PAGE_PATH_SITE     = '/AadharVerification';
    private static final String VF_PAGE_PATH_INTERNAL = '/apex/AadharVerification';

    private static final Integer LINK_EXPIRY_HOURS = 72;

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_INIT_EKYC_OTP.equalsIgnoreCase(action))    return initiateEkycOtp(args);
        if (ACTION_INIT_BIOMETRIC.equalsIgnoreCase(action))   return initiateMethodStub(args, METHOD_BIOMETRIC);
        if (ACTION_INIT_VIDEO_KYC.equalsIgnoreCase(action))   return initiateMethodStub(args, METHOD_VIDEO_KYC);
        if (ACTION_INIT_DIGILOCKER.equalsIgnoreCase(action))  return initiateMethodStub(args, METHOD_DIGILOCKER);
        if (ACTION_INIT_OFFLINE_XML.equalsIgnoreCase(action)) return initiateMethodStub(args, METHOD_OFFLINE_XML);
        if (ACTION_POLL_CONSENT.equalsIgnoreCase(action))     return pollAadhaarConsent(args);
        return new Map<String, Object>{
            'isSuccess' => false,
            'message'   => 'Unknown action: ' + action
        };
    }

    // =========================================================================
    // eKYC OTP Verification — REAL (customer-facing link flow)
    // =========================================================================
    private Map<String, Object> initiateEkycOtp(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id applicantId        = parseId(args.get('applicantId'));
            Id loanId             = parseId(args.get('recordId'));
            Id checklistRecordId  = parseId(args.get('checklistRecordId'));
            String addressType    = normalizeAddressType(args.get('addressType'));
            if (applicantId == null) {
                throw new AuraHandledException('applicantId is required.');
            }
            if (checklistRecordId == null) {
                throw new AuraHandledException('checklistRecordId is required.');
            }

            Applicant_KYC__c kyc = resolveOrCreateApplicantKyc(applicantId, checklistRecordId);
            kyc.KYC_Type__c                = KYC_TYPE_AADHAR;
            kyc.KYC_Verification_Method__c = METHOD_EKYC_OTP;
            kyc.AadhaarConsentReceived__c       = null;
            kyc.Aadhar_Verified__c              = false;
            kyc.Aadhar_OTP__c                   = null;
            kyc.AadhaareKYCLinkSent__c          = true;
            kyc.AadhaareKYCLinkSent_Date__c     = System.now();
            if (String.isBlank(kyc.Name)) {
                kyc.Name = 'Aadhaar KYC';
            }
            upsert kyc;

            String kycUrl = buildAadhaarVerificationUrl(applicantId, loanId, kyc.Id);
            kyc.KYC_URL__c = kycUrl;
            update kyc;

            stampChecklistAsAadhaar(checklistRecordId, kyc.Id, addressType);

            result.put('isSuccess',           true);
            result.put('kycUrl',              kycUrl);
            result.put('applicantKycId',      kyc.Id);
            result.put('consentReceivedDate', null);
            result.put('aadhaarVerified',     false);
            result.put('linkSent',            true);
            result.put('linkSentDate',        kyc.AadhaareKYCLinkSent_Date__c);
            result.put('addressType',         addressType);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'AadhaarVerificationController.initiateEkycOtp: ' + e.getMessage());
        }
        return result;
    }

    // =========================================================================
    // 4 Stub Methods — Biometric / Video KYC / Digilocker / Offline XML
    // =========================================================================
    private Map<String, Object> initiateMethodStub(Map<String, Object> args, String methodLabel) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id applicantId       = parseId(args.get('applicantId'));
            Id checklistRecordId = parseId(args.get('checklistRecordId'));
            String addressType   = normalizeAddressType(args.get('addressType'));
            if (applicantId == null) {
                throw new AuraHandledException('applicantId is required.');
            }
            if (checklistRecordId == null) {
                throw new AuraHandledException('checklistRecordId is required.');
            }
            Applicant_KYC__c kyc = resolveOrCreateApplicantKyc(applicantId, checklistRecordId);
            kyc.KYC_Type__c                = KYC_TYPE_AADHAR;
            kyc.KYC_Verification_Method__c = methodLabel;
            // Stub flows complete immediately; consent timestamp doubles as
            // the verification timestamp.
            Datetime nowTs = System.now();
            kyc.Aadhar_Verified__c        = true;
            kyc.AadhaarConsentReceived__c = nowTs;
            if (String.isBlank(kyc.Name)) {
                kyc.Name = 'Aadhaar KYC';
            }
            upsert kyc;
            stampChecklistAsAadhaar(checklistRecordId, kyc.Id, addressType);
            result.put('isSuccess',           true);
            result.put('method',              methodLabel);
            result.put('stub',                true);
            result.put('consentReceivedDate', nowTs);
            result.put('aadhaarVerified',     true);
            result.put('applicantKycId',      kyc.Id);
            result.put('addressType',         addressType);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'AadhaarVerificationController.' + methodLabel + ': ' + e.getMessage());
        }
        return result;
    }

    // =========================================================================
    // Consent Poll — used by the LWC to detect customer-side completion + expiry
    // =========================================================================
    private Map<String, Object> pollAadhaarConsent(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id applicantId       = parseId(args.get('applicantId'));
            Id loanId            = parseId(args.get('recordId'));
            Id checklistRecordId = parseId(args.get('checklistRecordId'));
            String addressType   = normalizeAddressType(args.get('addressType'));
            if (applicantId == null) {
                throw new AuraHandledException('applicantId is required.');
            }
            if (checklistRecordId == null) {
                throw new AuraHandledException('checklistRecordId is required.');
            }

            Applicant_KYC__c kyc = readApplicantKyc(applicantId, checklistRecordId);
            if (kyc == null) {
                result.put('isSuccess',           true);
                result.put('aadhaarVerified',     false);
                result.put('consentReceivedDate', null);
                result.put('linkSent',            false);
                result.put('linkExpired',         false);
                return result;
            }

            Boolean linkSent     = kyc.AadhaareKYCLinkSent__c == true;
            Boolean verified     = kyc.Aadhar_Verified__c     == true;
            Boolean linkExpired  = !verified
                && linkSent
                && kyc.AadhaareKYCLinkSent_Date__c != null
                && kyc.AadhaareKYCLinkSent_Date__c.addHours(LINK_EXPIRY_HOURS) < System.now();

            if (linkExpired) {
                kyc.AadhaareKYCLinkSent__c      = false;
                kyc.AadhaareKYCLinkSent_Date__c = null;
                kyc.KYC_URL__c                  = null;
                update kyc;
            }

            
            String kycUrlToReturn = linkExpired ? null : kyc.KYC_URL__c;
            if (!linkExpired && linkSent && kyc.Id != null) {
                Map<String, Object> resolved = resolveAadhaarVerificationBase();
                String currentBase = (String) resolved.get('baseUrl');
                if (String.isNotBlank(currentBase)
                    && (String.isBlank(kycUrlToReturn) || !kycUrlToReturn.startsWith(currentBase))) {
                    String healedUrl = buildAadhaarVerificationUrl(applicantId, loanId, kyc.Id);
                    if (String.isNotBlank(healedUrl) && healedUrl != kyc.KYC_URL__c) {
                        try {
                            kyc.KYC_URL__c = healedUrl;
                            update kyc;
                        } catch (Exception ignored) {
                            // Best-effort heal; surface the rebuilt URL even if persist fails.
                        }
                    }
                    kycUrlToReturn = healedUrl;
                }
            }

            result.put('isSuccess',           true);
            result.put('aadhaarVerified',     verified);
            result.put('consentReceivedDate', kyc.AadhaarConsentReceived__c);
            result.put('linkSent',            linkSent && !linkExpired);
            result.put('linkExpired',         linkExpired);
            result.put('kycUrl',              kycUrlToReturn);
            result.put('linkSentDate',        kyc.AadhaareKYCLinkSent_Date__c);
            result.put('applicantKycId',      kyc.Id);
            result.put('addressType',         addressType);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'AadhaarVerificationController.pollAadhaarConsent: ' + e.getMessage());
        }
        return result;
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /**
     * Builds the customer-facing eKYC URL with applicantId, loanId, and kycId
     * encoded as query parameters. Picks /apex/<page> vs Site-prefixed path
     * based on the resolved base URL — see resolveAadhaarVerificationBase().
     */
    private String buildAadhaarVerificationUrl(Id applicantId, Id loanId, Id kycId) {
        Map<String, Object> resolved = resolveAadhaarVerificationBase();
        String baseUrl  = (String)  resolved.get('baseUrl');
        Boolean isSite  = (Boolean) resolved.get('isSiteUrl');
        String pagePath = isSite ? VF_PAGE_PATH_SITE : VF_PAGE_PATH_INTERNAL;

        String params = '?applicantId=' + EncodingUtil.urlEncode((String) applicantId, 'UTF-8');
        if (loanId != null) {
            params += '&loanId=' + EncodingUtil.urlEncode((String) loanId, 'UTF-8');
        }
        if (kycId != null) {
            params += '&kycId=' + EncodingUtil.urlEncode((String) kycId, 'UTF-8');
        }
        return baseUrl + pagePath + params;
    }


    private Map<String, Object> resolveAadhaarVerificationBase() {
        try {
            List<Site> sites = [
                SELECT Id, UrlPathPrefix
                FROM Site
                WHERE Name = :SITE_NAME
                  AND Status = 'Active'
                LIMIT 1
            ];
            if (!sites.isEmpty()) {
                Site s = sites[0];
                List<DomainSite> ds = [
                    SELECT Domain.Domain
                    FROM DomainSite
                    WHERE SiteId = :s.Id
                    ORDER BY Domain.DomainType ASC
                    LIMIT 1
                ];
                if (!ds.isEmpty() && ds[0].Domain != null && String.isNotBlank(ds[0].Domain.Domain)) {
                    String path = String.isNotBlank(s.UrlPathPrefix) ? '/' + s.UrlPathPrefix : '';
                    return new Map<String, Object>{
                        'baseUrl'   => 'https://' + ds[0].Domain.Domain + path,
                        'isSiteUrl' => true
                    };
                }
            }
        } catch (Exception ignored) {
        }

        // (2) Site request context (only true when this runs inside a Site).
        String siteBase = Site.getBaseUrl();
        if (String.isNotBlank(siteBase)) {
            return new Map<String, Object>{
                'baseUrl'   => siteBase,
                'isSiteUrl' => true
            };
        }

        // (3) Internal org domain fallback
        String orgDomain = Url.getOrgDomainUrl() != null
            ? Url.getOrgDomainUrl().toExternalForm()
            : '';
        return new Map<String, Object>{
            'baseUrl'   => orgDomain,
            'isSiteUrl' => false
        };
    }

    private Applicant_KYC__c resolveOrCreateApplicantKyc(Id applicantId, Id checklistRecordId) {
        List<Document_CheckList__c> rows = [
            SELECT Id, Applicant_KYC__c,
                   Applicant__r.Id, Applicant__r.Customer_First_Name__c, Applicant__r.Customer_Last_Name__c,
                   Applicant_KYC__r.Id, Applicant_KYC__r.Name,
                   Applicant_KYC__r.KYC_Type__c, Applicant_KYC__r.KYC_Verification_Method__c,
                   Applicant_KYC__r.AadhaarConsentReceived__c, Applicant_KYC__r.Aadhar_Verified__c,
                   Applicant_KYC__r.AadhaareKYCLinkSent__c, Applicant_KYC__r.AadhaareKYCLinkSent_Date__c,
                   Applicant_KYC__r.KYC_URL__c, Applicant_KYC__r.Aadhar_OTP__c
            FROM Document_CheckList__c
            WHERE Id = :checklistRecordId
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            cachedApplicantForName = rows[0].Applicant__r;   // populated even when KYC link is null
            if (rows[0].Applicant_KYC__c != null && rows[0].Applicant_KYC__r != null) {
                return rows[0].Applicant_KYC__r;
            }
        }
        return new Applicant_KYC__c(Applicant__c = applicantId);
    }

    private Applicant__c cachedApplicantForName;

    /** Read-only fetch of the checklist's Applicant_KYC__c. Returns null
     *  when the lookup is unset. */
    private Applicant_KYC__c readApplicantKyc(Id applicantId, Id checklistRecordId) {
        List<Document_CheckList__c> rows = [
            SELECT Id, Applicant_KYC__c,
                   Applicant_KYC__r.Id,
                   Applicant_KYC__r.AadhaarConsentReceived__c, Applicant_KYC__r.Aadhar_Verified__c,
                   Applicant_KYC__r.AadhaareKYCLinkSent__c, Applicant_KYC__r.AadhaareKYCLinkSent_Date__c,
                   Applicant_KYC__r.KYC_URL__c
            FROM Document_CheckList__c
            WHERE Id = :checklistRecordId
            LIMIT 1
        ];
        if (!rows.isEmpty() && rows[0].Applicant_KYC__c != null && rows[0].Applicant_KYC__r != null) {
            return rows[0].Applicant_KYC__r;
        }
        return null;
    }

    private void stampChecklistAsAadhaar(Id checklistRecordId, Id kycId, String addressType) {
        if (checklistRecordId == null) return;
        update new Document_CheckList__c(
            Id               = checklistRecordId,
            Applicant_KYC__c = kycId,
            Document_Type__c = 'Aadhaar Card',
            Address_Type__c  = addressType,
            Is_Active__c     = true,
            Name             = KYCInfoController.buildChecklistName(cachedApplicantForName, 'Aadhaar Card')
        );
    }

    private static String normalizeAddressType(Object raw) {
        if (raw == null) return ADDRESS_TYPE_CURRENT;
        String s = String.valueOf(raw).trim();
        if (ADDRESS_TYPE_PERMANENT.equalsIgnoreCase(s)) return ADDRESS_TYPE_PERMANENT;
        return ADDRESS_TYPE_CURRENT;
    }

    private static Id parseId(Object raw) {
        if (raw == null) return null;
        String s = String.valueOf(raw).trim();
        if (String.isBlank(s)) return null;
        try { return (Id) s; } catch (Exception ignored) { return null; }
    }
}