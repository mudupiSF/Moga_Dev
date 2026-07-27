/**
 * Handler for the UIDAI OTP Verify integration.
 *
 * Lifecycle (driven by ApplicationUtility.invokeIntegrationSync):
 *   prepareRecordForIntegration : locate the just-verified Applicant_KYC__c for
 *                                 the supplied applicant.
 *   validateInputData           : ensure that row exists.
 *   generateRequest             : produce a request body (empty for the mock
 *                                 path; real impl would assemble UIDAI verify).
 *   processResponse             : parse the JSON envelope, extract <UidData>
 *                                 from the embedded XML, stamp the KYC row,
 *                                 and persist the Aadhaar photo (<Pht> base64)
 *                                 as a ContentVersion on the matching
 *                                 Document_CheckList__c bucket.
 *
 * Mock activation: when Integration_Master__c.Is_Mocking_Service_Enabled__c
 * is true, IntegrationUtility short-circuits the HTTP callout and replays
 * Mocking_Service_Response__c — no domain-specific code needed here.
 */
public without sharing class UIDAIAPIHandler implements IIntegrationHandler {

    private static final String VERIFICATION_METHOD = 'eKYC OTP Verification';
    private static final String KYC_TYPE_AADHAR     = 'Aadhar';
    private static final String PHOTO_TITLE         = 'Aadhaar Photo';
    private static final String PHOTO_PATH          = 'Aadhaar_Photo.jpg';

    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) return new List<sObject>();
        Id applicantId = recordIds[0];
        return new List<sObject>{ findVerifiedKyc(applicantId) };
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> validateInputData(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
        wrapper.hasValidationError = false;
        if (recordList == null || recordList.isEmpty() || recordList[0] == null) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage  = 'No verified Aadhaar KYC record found for the applicant.';
            wrapper.displayMessage = 'Aadhaar verification record missing.';
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant_KYC__c kyc = (Applicant_KYC__c) recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();
        wrapper.method      = 'POST';
        wrapper.requestBody = '{"aadhaarKycId":"' + String.valueOf(kyc.Id) + '"}';
        wrapper.captureRequestInAttachment = false;
        return new List<ApplicationUtility.IntegrationRequestWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        IntegrationUtility.ResponseWrapper wrapper = null;
        Integration_Checklist__c checklist = null;
        try {
            wrapper   = (IntegrationUtility.ResponseWrapper) recordList[0];
            checklist = (Integration_Checklist__c) wrapper.checklistRecord;

            if (wrapper.statusCode != 200) {
                markChecklistFailure(checklist);
                result.hasValidationError = true;
                result.errorMessage = 'UIDAI verify returned status ' + wrapper.statusCode;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(wrapper.response);
            Map<String, Object> respMap = (Map<String, Object>) envelope.get('response');
            if (respMap == null) {
                throw new HandledException('UIDAI response envelope missing "response" key.');
            }
            String status = (String) respMap.get('status');
            List<Object> content = (List<Object>) respMap.get('content');
            if (status != 'SUCCESS' || content == null || content.isEmpty()) {
                markChecklistFailure(checklist);
                result.hasValidationError = true;
                result.errorMessage = 'UIDAI verification failed: status=' + status;
                return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
            }

            String xmlContent = String.valueOf(content[0]);
            Map<String, String> uid = parseUidData(xmlContent);

            Id applicantId = (Id) checklist.Applicant__c;
            Applicant_KYC__c kyc = findVerifiedKyc(applicantId);
            if (kyc == null) {
                throw new HandledException('Verified Applicant_KYC__c not found for applicant ' + applicantId);
            }
            stampKyc(kyc, uid);
            update kyc;

            
            Document_CheckList__c bucketRow = findChecklistRowForKyc(kyc.Id);
            if (bucketRow != null) {
                stampChecklist(bucketRow, uid);
                update bucketRow;

                // Photo attach on the bucket where Aadhaar was verified
                // (only one bucket per q2 from earlier alignment).
                String photoB64 = nullSafe(uid.get('Pht'));
                if (String.isNotBlank(photoB64)) {
                    attachPhotoIfMissing(bucketRow.Id, photoB64);
                }
            }

            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            checklist.Status__c            = Constants.CHECKLIST_STATUS_SUCCESS;
            update checklist;

            result.hasValidationError = false;
            result.displayMessage = 'UIDAI verification details applied.';
        } catch (Exception ex) {
            result.hasValidationError = true;
            result.errorMessage = 'UIDAI processResponse error: ' + ex.getMessage();
            if (checklist != null) {
                markChecklistFailure(checklist);
            }
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static Map<String, String> parseUidData(String xmlContent) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(xmlContent)) return out;
        Dom.Document doc = new Dom.Document();
        doc.load(xmlContent);
        Dom.XmlNode root = doc.getRootElement();
        if (root == null) return out;
        Dom.XmlNode uidData = root.getChildElement('UidData', null);
        if (uidData == null) return out;
        for (Dom.XmlNode child : uidData.getChildElements()) {
            out.put(child.getName(), child.getText());
        }
        return out;
    }

    private static void stampKyc(Applicant_KYC__c kyc, Map<String, String> uid) {
        String fullName     = nullSafe(uid.get('name'));
        String aadhaar      = nullSafe(uid.get('uid'));
        Date   dob          = parseDob(uid.get('dob'));
        String maskedNo     = (String.isNotBlank(aadhaar) && aadhaar.length() >= 4)
                              ? 'XXXXXXXX' + aadhaar.right(4)
                              : '';
        String city         = String.isNotBlank(nullSafe(uid.get('dist')))
                              ? nullSafe(uid.get('dist'))
                              : nullSafe(uid.get('vtc'));

        if (String.isNotBlank(fullName))                  kyc.KYC_name__c           = fullName;
        if (dob != null)                                   kyc.KYC_DOB__c            = dob;
        if (String.isNotBlank(nullSafe(uid.get('house')))) kyc.KYC_Address_Line_1__c = nullSafe(uid.get('house'));
        String line2 = buildLine2(uid);
        if (String.isNotBlank(line2))                      kyc.KYC_Address_Line_2__c = line2;
        String line3 = buildLine3(uid);
        if (String.isNotBlank(line3))                      kyc.KYC_Address_Line_3__c = line3;
        if (String.isNotBlank(city))                       kyc.KYC_City__c           = city;
        if (String.isNotBlank(nullSafe(uid.get('state')))) kyc.KYC_State__c          = nullSafe(uid.get('state'));
        if (String.isNotBlank(nullSafe(uid.get('pc'))))    kyc.KYC_Pin_Code__c       = nullSafe(uid.get('pc'));
        if (String.isNotBlank(nullSafe(uid.get('dist'))))  kyc.KYC_District__c       = nullSafe(uid.get('dist'));
        if (String.isNotBlank(maskedNo))                   kyc.Masked_KYC_No__c      = maskedNo;
        if (String.isNotBlank(nullSafe(uid.get('tkn'))))   kyc.Aadhar_Vault_Code__c  = nullSafe(uid.get('tkn'));
        kyc.KYC_Type__c                = KYC_TYPE_AADHAR;
        kyc.KYC_Verification_Method__c = VERIFICATION_METHOD;
        kyc.Aadhar_Verified__c         = true;
        if (kyc.AadhaarConsentReceived__c == null) kyc.AadhaarConsentReceived__c = System.now();
        if (String.isBlank(kyc.Name)) kyc.Name = 'Aadhaar KYC';
    }

    private static Applicant_KYC__c findVerifiedKyc(Id applicantId) {
        if (applicantId == null) return null;
        List<Applicant_KYC__c> rows = [
            SELECT Id, Name, Applicant__c, KYC_Type__c, KYC_Verification_Method__c,
                   AadhaarConsentReceived__c, Aadhar_Verified__c,
                   KYC_name__c, KYC_DOB__c, KYC_Address_Line_1__c, KYC_Address_Line_2__c,
                   KYC_Address_Line_3__c, KYC_City__c, KYC_State__c, KYC_Pin_Code__c,
                   KYC_District__c, Masked_KYC_No__c, Aadhar_Vault_Code__c
            FROM Applicant_KYC__c
            WHERE Applicant__c = :applicantId
              AND Aadhar_Verified__c = true
              AND KYC_Verification_Method__c = :VERIFICATION_METHOD
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Document_CheckList__c findChecklistRowForKyc(Id kycId) {
        if (kycId == null) return null;
        List<Document_CheckList__c> rows = [
            SELECT Id, Name, Applicant__c, Address_Type__c, Document_Type__c,
                   First_Name__c, Last_Name__c, Gender__c, KYC_Date_of_Birth__c,
                   Applicant__r.Customer_First_Name__c, Applicant__r.Customer_Last_Name__c
            FROM Document_CheckList__c
            WHERE Applicant_KYC__c = :kycId
              AND Is_Active__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static void stampChecklist(Document_CheckList__c row, Map<String, String> uid) {
        String fullName = nullSafe(uid.get('name'));
        if (String.isNotBlank(fullName)) {
            List<String> parts = fullName.split('\\s+');
            row.First_Name__c = parts[0];
            if (parts.size() > 1) {
                List<String> tail = new List<String>();
                for (Integer i = 1; i < parts.size(); i++) tail.add(parts[i]);
                row.Last_Name__c = String.join(tail, ' ');
            } else {
                row.Last_Name__c = '';
            }
        }
        
        String genderRaw = nullSafe(uid.get('gender'));
        if (String.isNotBlank(genderRaw)) {
            String g = genderRaw.toUpperCase();
            row.Gender__c = (g == 'M' || g == 'MALE')   ? 'MALE'
                          : (g == 'F' || g == 'FEMALE') ? 'FEMALE'
                          : g;
        }
        Date dob = parseDob(uid.get('dob'));
        if (dob != null) row.KYC_Date_of_Birth__c = dob;

        row.Name = KYCInfoController.buildChecklistName(row.Applicant__r, row.Document_Type__c);
    }

    private static void attachPhotoIfMissing(Id checklistRowId, String base64Photo) {
        List<ContentDocumentLink> existing = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :checklistRowId
              AND ContentDocument.LatestPublishedVersion.Title = :PHOTO_TITLE
            LIMIT 1
        ];
        if (!existing.isEmpty()) return;
        insert new ContentVersion(
            Title                  = PHOTO_TITLE,
            PathOnClient           = PHOTO_PATH,
            VersionData            = EncodingUtil.base64Decode(base64Photo),
            FirstPublishLocationId = checklistRowId
        );
    }

    private static void markChecklistFailure(Integration_Checklist__c checklist) {
        try {
            checklist.Status__c            = Constants.CHECKLIST_STATUS_FAILURE;
            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
            update checklist;
        } catch (Exception ignored) {}
    }

    private static String nullSafe(String value) {
        if (value == null) return '';
        String t = value.trim();
        if (String.isBlank(t) || t.equalsIgnoreCase('null')) return '';
        return t;
    }

    private static String buildLine2(Map<String, String> uid) {
        List<String> parts = new List<String>();
        String street = nullSafe(uid.get('street'));
        String lm     = nullSafe(uid.get('lm'));
        if (String.isNotBlank(street)) parts.add(street);
        if (String.isNotBlank(lm))     parts.add(lm);
        return String.join(parts, ', ');
    }

    private static String buildLine3(Map<String, String> uid) {
        List<String> parts = new List<String>();
        String vtc     = nullSafe(uid.get('vtc'));
        String po      = nullSafe(uid.get('po'));
        String subdist = nullSafe(uid.get('subdist'));
        if (String.isNotBlank(vtc))     parts.add(vtc);
        if (String.isNotBlank(po))      parts.add(po);
        if (String.isNotBlank(subdist)) parts.add(subdist);
        return String.join(parts, ', ');
    }

    /**
     * Handles UIDAI's dd-MM-yyyy and dd/MM/yyyy formats, and falls back to
     * Date.valueOf(s) for yyyy-MM-dd if upstream changes.
     */
    private static Date parseDob(String raw) {
        String s = nullSafe(raw);
        if (String.isBlank(s)) return null;
        try {
            if (s.contains('-') && Pattern.matches('^\\d{1,2}-\\d{1,2}-\\d{4}$', s)) {
                List<String> parts = s.split('-');
                return Date.newInstance(Integer.valueOf(parts[2]), Integer.valueOf(parts[1]), Integer.valueOf(parts[0]));
            }
            if (s.contains('/') && Pattern.matches('^\\d{1,2}/\\d{1,2}/\\d{4}$', s)) {
                List<String> parts = s.split('/');
                return Date.newInstance(Integer.valueOf(parts[2]), Integer.valueOf(parts[1]), Integer.valueOf(parts[0]));
            }
            return Date.valueOf(s);
        } catch (Exception ignored) {
            return null;
        }
    }
}