/**
 * Thin controller for PAN TO GSTN integration from Non-Individual KYC.
 */
public with sharing class ExtractPANTOGSTNAPIController {

    private static final String INTEGRATION_KEY = PANTOGSTNAPIHandler.INTEGRATION_KEY;

    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokePANTOGSTNAPI(String applicantId) {
        return ApplicationUtility.invokeIntegrationSync(
            INTEGRATION_KEY,
            applicantId,
            'Applicant__c'
        );
    }

    /**
     * Builds the LWC extraction payload from the latest successful PAN TO GSTN response.
     */
    @AuraEnabled
    public static Map<String, Object> getGstExtractionResult(String applicantId) {
        if (String.isBlank(applicantId)) {
            return failureResult('applicantId is required.');
        }

        List<Integration_Checklist__c> rows = [
            SELECT Response__c, Decrypted_Response__c, Status__c, Functional_Status__c
            FROM Integration_Checklist__c
            WHERE Applicant__c = :applicantId
              AND Integration_Master_Name__c = :INTEGRATION_KEY
              AND Status__c = :Constants.CHECKLIST_STATUS_SUCCESS
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            return failureResult('PAN TO GSTN integration result was not found.');
        }

        Integration_Checklist__c checklist = rows[0];
        String rawResponse = String.isNotBlank(checklist.Decrypted_Response__c)
            ? checklist.Decrypted_Response__c
            : checklist.Response__c;

        PANTOGSTNAPIHandler.GstExtractionParseResult parsed =
            PANTOGSTNAPIHandler.parseGstDataFromResponse(rawResponse);
        if (parsed.gstNumbers.isEmpty()) {
            return failureResult('PAN TO GSTN response did not contain any active GSTIN values.');
        }

        String singleGst = parsed.gstNumbers.size() == 1 ? parsed.gstNumbers[0] : null;
        String state = null;
        if (singleGst != null && parsed.gstStateByNumber.containsKey(singleGst)) {
            state = parsed.gstStateByNumber.get(singleGst);
        }

        Map<String, Object> gstStateByNumber = new Map<String, Object>();
        for (String gstin : parsed.gstStateByNumber.keySet()) {
            gstStateByNumber.put(gstin, parsed.gstStateByNumber.get(gstin));
        }

        return new Map<String, Object>{
            'isSuccess'        => true,
            'docType'          => 'GST',
            'gstNumbers'       => parsed.gstNumbers,
            'gstStateByNumber' => gstStateByNumber,
            'extractedDetails' => new Map<String, Object>{
                'gstNumber'       => singleGst,
                'state'           => state,
                'kycAddressLine1' => null,
                'kycAddressLine2' => null,
                'district'        => null,
                'city'            => null,
                'kycPinCode'      => null
            }
        };
    }

    private static Map<String, Object> failureResult(String message) {
        return new Map<String, Object>{
            'isSuccess'        => false,
            'message'          => message,
            'gstNumbers'       => new List<String>(),
            'gstStateByNumber' => new Map<String, Object>(),
            'extractedDetails' => emptyGstDetails()
        };
    }

    private static Map<String, Object> emptyGstDetails() {
        return new Map<String, Object>{
            'gstNumber'       => null,
            'kycAddressLine1' => null,
            'kycAddressLine2' => null,
            'state'           => null,
            'district'        => null,
            'city'            => null,
            'kycPinCode'      => null
        };
    }
}