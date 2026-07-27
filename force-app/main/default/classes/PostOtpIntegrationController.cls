public with sharing class PostOtpIntegrationController {

    public static final String INTEGRATION_KEY_MHA = 'MHA';
    public static final String INTEGRATION_KEY_MNRL = 'MRL';

    public static final String STAGE_MHA = 'MHA Integration';
    public static final String STAGE_MNRL = 'MNRL Integration';

    /** Full chain ordering when PAN is the active KYC path. */
    public static final List<String> POST_MOBILE_OTP_INTEGRATION_STAGES = new List<String>{ STAGE_MHA, STAGE_MNRL };
    public static final List<String> POST_MOBILE_OTP_INTEGRATION_KEYS = new List<String>{ INTEGRATION_KEY_MHA, INTEGRATION_KEY_MNRL };

    /** Form 60 path skips MHA - only MNRL runs. */
    public static final List<String> POST_MOBILE_OTP_INTEGRATION_STAGES_FORM60 = new List<String>{ STAGE_MNRL };
    public static final List<String> POST_MOBILE_OTP_INTEGRATION_KEYS_FORM60 = new List<String>{ INTEGRATION_KEY_MNRL };

    /**
     * Runs the MHA + MNRL integrations after a successful mobile OTP verification.
     * isPanPath = true  -> MHA Integration then MNRL Integration.
     * isPanPath = false -> MNRL Integration only (Form 60 flow).
     * Real callouts are stubbed until live mocks are wired into the named static resources.
     */
    @AuraEnabled
    public static Map<String, Object> executePostMobileOtpIntegrations(Id applicantId, Boolean isPanPath) {
        Boolean panPath = isPanPath == null ? true : isPanPath;
        List<String> stages = panPath ? POST_MOBILE_OTP_INTEGRATION_STAGES : POST_MOBILE_OTP_INTEGRATION_STAGES_FORM60;
        List<String> keys = panPath ? POST_MOBILE_OTP_INTEGRATION_KEYS : POST_MOBILE_OTP_INTEGRATION_KEYS_FORM60;

        Map<String, Object> result = new Map<String, Object>{
            'stages' => stages,
            'keys' => keys,
            'success' => false
        };
        if (applicantId == null) {
            result.put('errorMessage', 'Applicant Id is required');
            return result;
        }
        Map<String, Object> stageResults = new Map<String, Object>();
        try {
            for (Integer i = 0; i < keys.size(); i++) {
                String key = keys[i];
                String stageLabel = stages[i];
                Map<String, Object> stageResult = runStubbedIntegration(applicantId, key);
                stageResults.put(key, stageResult);
                if (!(Boolean) stageResult.get('success')) {
                    result.put('stageResults', stageResults);
                    result.put('failedStage', stageLabel);
                    result.put('failedKey', key);
                    result.put('errorMessage', stageResult.get('message'));
                    return result;
                }
            }
            result.put('stageResults', stageResults);
            result.put('success', true);
            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PostOtpIntegrationController.executePostMobileOtpIntegrations: ' + e.getMessage());
            result.put('stageResults', stageResults);
            result.put('errorMessage', e.getMessage());
            return result;
        }
    }

    /** Maps each integration key to the static resource that holds its mock success payload.
     *  Static resources are not yet present in DEV - they will be created when the live mock JSON is provided. */
    public static String getPostOtpStaticResourceName(String integrationKey) {
        if (INTEGRATION_KEY_MHA.equals(integrationKey)) {
            return 'MHA_INTEGRATION_MOCK_SUCCESS';
        }
        if (INTEGRATION_KEY_MNRL.equals(integrationKey)) {
            return 'MNRL_INTEGRATION_MOCK_SUCCESS';
        }
        throw new AuraHandledException('Unsupported post OTP integration: ' + integrationKey);
    }

    /** Placeholder for the real integration callout. Returns a success payload tagged with the
     *  intended mock static resource name so the LWC progress modal can advance through stages. */
    private static Map<String, Object> runStubbedIntegration(Id applicantId, String integrationKey) {
        String resourceName;
        try {
            resourceName = getPostOtpStaticResourceName(integrationKey);
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => e.getMessage(),
                'integrationKey' => integrationKey
            };
        }
        return new Map<String, Object>{
            'success' => true,
            'message' => integrationKey + ' stub passed',
            'integrationKey' => integrationKey,
            'mockResourceName' => resourceName,
            'applicantId' => applicantId
        };
    }

    /**
     * @description Initiate MHA verification process for a applicant by invoking the integration
     * @param applicantId The ID of the applicant record to verify MHA for
     * @return ApplicationUtility.IntegrationResponseWrapper Result containing the verification response
     */
    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeMHAAPI(String applicantId) {
        ApplicationUtility.IntegrationResponseWrapper response = ApplicationUtility.invokeIntegrationSync('MHA API', applicantId, 'Applicant__c');
        return response;
    }
}