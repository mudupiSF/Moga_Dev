/**
 * External API bridge for Customer Dedupe actions.
 * Stubs return isSuccess=true until live callouts are wired; swap private run* methods only.
 */
public with sharing class CustomerDedupeIntegrationService {

    public static final String INTEGRATION_KEY_VALID_MATCH = 'VALID_MATCH';
    public static final String INTEGRATION_KEY_INVALID_MATCH = 'INVALID_MATCH';
    public static final String INTEGRATION_KEY_CHECK_ELIGIBILITY = 'CHECK_ELIGIBILITY';
    public static final String INTEGRATION_KEY_NPA_CHECK = 'NPA_CHECK';
    public static final String INTEGRATION_KEY_CIBIL_CHECK = 'CIBIL_CHECK';
    public static final String INTEGRATION_KEY_CRIF_CHECK = 'CRIF_CHECK';
    public static final String INTEGRATION_KEY_BRE_CHECK_ELIGIBILITY = 'BRE_CHECK_ELIGIBILITY';
    public static final String INTEGRATION_KEY_GET_EMI_DETAILS = 'GET_EMI_DETAILS';
    public static final String INTEGRATION_KEY_GET_EXPOSURE_DETAILS = 'GET_EXPOSURE_DETAILS';
    public static final String INTEGRATION_KEY_AML_CHECK_FORWARD = 'AML_CHECK_FORWARD';
    public static final String INTEGRATION_KEY_SCORECARD_FORWARD = 'SCORECARD_FORWARD';

    public static Map<String, Object> invokeValidMatchApi(Id recordId, Id applicantId, String cifId) {
        return runValidMatchIntegration(recordId, applicantId, cifId);
    }

    public static Map<String, Object> invokeInvalidMatchApi(Id recordId, Id applicantId) {
        return runInvalidMatchIntegration(recordId, applicantId);
    }

    public static Map<String, Object> invokeCheckEligibilityApi(
            Id recordId,
            Id applicantId,
            String cifId) {
        return invokeBreCheckEligibilityApi(recordId, applicantId, cifId);
    }

    public static Map<String, Object> invokeCheckEligibilityStageApi(
            Id recordId,
            Id applicantId,
            String cifPayload,
            String stageKey) {
        if ('NPA'.equalsIgnoreCase(stageKey)) {
            return invokeNpaCheckApi(recordId, applicantId, cifPayload);
        }
        if ('CIBIL'.equalsIgnoreCase(stageKey)) {
            return invokeCibilCheckApi(recordId, applicantId, cifPayload);
        }
        if ('CRIF'.equalsIgnoreCase(stageKey)) {
            return invokeCrifCheckApi(recordId, applicantId, cifPayload);
        }
        if ('BRE'.equalsIgnoreCase(stageKey)) {
            return invokeBreCheckEligibilityApi(recordId, applicantId, cifPayload);
        }
        return new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unknown eligibility stage: ' + stageKey
        };
    }

    public static Map<String, Object> invokeNpaCheckApi(
            Id recordId,
            Id applicantId,
            String cifPayload) {
        return runNpaCheckIntegration(recordId, applicantId, cifPayload);
    }

    public static Map<String, Object> invokeCibilCheckApi(
            Id recordId,
            Id applicantId,
            String cifPayload) {
        return runCibilCheckIntegration(recordId, applicantId, cifPayload);
    }

    public static Map<String, Object> invokeCrifCheckApi(
            Id recordId,
            Id applicantId,
            String cifPayload) {
        return runCrifCheckIntegration(recordId, applicantId, cifPayload);
    }

    public static Map<String, Object> invokeBreCheckEligibilityApi(
            Id recordId,
            Id applicantId,
            String cifPayload) {
        return runBreCheckEligibilityIntegration(recordId, applicantId, cifPayload);
    }

    public static Map<String, Object> invokeGetEmiDetailsApi(Id recordId, Id applicantId, String cifId) {
        return runGetEmiDetailsIntegration(recordId, applicantId, cifId);
    }

    public static Map<String, Object> invokeGetExposureDetailsApi(
            Id recordId,
            Id applicantId,
            String cifId) {
        return runGetExposureDetailsIntegration(recordId, applicantId, cifId);
    }

    /**
     * Runs one Dedupe Next forward modal stage (AML / ScoreCard).
     * LWC passes stageKey; swap private run* bodies when live endpoints are ready.
     */
    public static Map<String, Object> invokeDedupeForwardStageApi(Id recordId, String stageKey) {
        if ('AML'.equalsIgnoreCase(stageKey)) {
            return invokeAmlCheckForwardApi(recordId);
        }
        if ('SCORECARD'.equalsIgnoreCase(stageKey)) {
            return invokeScorecardForwardApi(recordId);
        }
        if ('FI_CREATION'.equalsIgnoreCase(stageKey)) {
            return invokeFiCreationDedupeForwardApi(recordId);
        }
        return new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unknown forward integration stage: ' + stageKey
        };
    }

    public static Map<String, Object> invokeAmlCheckForwardApi(Id recordId) {
        return runAmlCheckForwardIntegration(recordId);
    }

    public static Map<String, Object> invokeScorecardForwardApi(Id recordId) {
        return runScorecardForwardIntegration(recordId);
    }

    public static Map<String, Object> invokeFiCreationDedupeForwardApi(Id recordId) {
        FIWaiverAPIController.FiWaiverResult flowResult =
            FIWaiverAPIController.runFiWaiverDedupeNextFlow(String.valueOf(recordId));
        Boolean isSuccess = flowResult != null && flowResult.isSuccess == true;
        return new Map<String, Object>{
            'isSuccess' => isSuccess,
            'message' => flowResult != null && String.isNotBlank(flowResult.message)
                ? flowResult.message
                : (isSuccess ? 'FI investigations created successfully.' : 'FI creation failed.')
        };
    }

    // ── Stub integrations (replace bodies when APIs are available) ─────────────

    private static Map<String, Object> runValidMatchIntegration(
            Id recordId,
            Id applicantId,
            String cifId) {
        return buildStubSuccess(
            INTEGRATION_KEY_VALID_MATCH,
            'Valid match integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId,
                'applicantId' => applicantId,
                'cifId' => cifId
            }
        );
    }

    private static Map<String, Object> runInvalidMatchIntegration(Id recordId, Id applicantId) {
        return buildStubSuccess(
            INTEGRATION_KEY_INVALID_MATCH,
            'Invalid match integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId,
                'applicantId' => applicantId
            }
        );
    }

    private static Map<String, Object> runNpaCheckIntegration(
            Id recordId,
            Id applicantId,
            String cifPayload) {
        return buildStubSuccess(
            INTEGRATION_KEY_NPA_CHECK,
            'NPA check integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId,
                'applicantId' => applicantId,
                'cifPayload' => cifPayload
            }
        );
    }

    private static Map<String, Object> runCibilCheckIntegration(
            Id recordId,
            Id applicantId,
            String cifPayload) {
        return buildStubSuccess(
            INTEGRATION_KEY_CIBIL_CHECK,
            'CIBIL check integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId,
                'applicantId' => applicantId,
                'cifPayload' => cifPayload
            }
        );
    }

    private static Map<String, Object> runCrifCheckIntegration(
            Id recordId,
            Id applicantId,
            String cifPayload) {
        return buildStubSuccess(
            INTEGRATION_KEY_CRIF_CHECK,
            'CRIF check integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId,
                'applicantId' => applicantId,
                'cifPayload' => cifPayload
            }
        );
    }

    private static Map<String, Object> runBreCheckEligibilityIntegration(
            Id recordId,
            Id applicantId,
            String cifPayload) {
        return buildStubSuccess(
            INTEGRATION_KEY_BRE_CHECK_ELIGIBILITY,
            'BRE check eligibility integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId,
                'applicantId' => applicantId,
                'cifPayload' => cifPayload
            }
        );
    }

    private static Map<String, Object> runGetEmiDetailsIntegration(
            Id recordId,
            Id applicantId,
            String cifId) {
        return buildStubSuccess(
            INTEGRATION_KEY_GET_EMI_DETAILS,
            'Get existing EMI integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId,
                'applicantId' => applicantId,
                'cifId' => cifId
            }
        );
    }

    private static Map<String, Object> runGetExposureDetailsIntegration(
            Id recordId,
            Id applicantId,
            String cifId) {
        return buildStubSuccess(
            INTEGRATION_KEY_GET_EXPOSURE_DETAILS,
            'Get exposure details integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId,
                'applicantId' => applicantId,
                'cifId' => cifId
            }
        );
    }

    private static Map<String, Object> runAmlCheckForwardIntegration(Id recordId) {
        if (recordId == null) {
            return new Map<String, Object>{
                'isSuccess' => false,
                'message' => 'Application id is required.'
            };
        }

        Map<String, Object> amlResult = AMLCheckAPIController.invokeAMLCheckForApplication(
            String.valueOf(recordId)
        );
        if (amlResult == null) {
            return new Map<String, Object>{
                'isSuccess' => false,
                'message' => 'AML Check failed.'
            };
        }
        if (amlResult.get('isSuccess') == true) {
            amlResult.put('integrationKey', INTEGRATION_KEY_AML_CHECK_FORWARD);
        }
        return amlResult;
    }

    /**
     * Replace this stub with the live ScoreCard callout when the endpoint is available.
     */
    private static Map<String, Object> runScorecardForwardIntegration(Id recordId) {
        return buildStubSuccess(
            INTEGRATION_KEY_SCORECARD_FORWARD,
            'ScoreCard API integration stub passed',
            new Map<String, Object>{
                'recordId' => recordId
            }
        );
    }

    private static Map<String, Object> buildStubSuccess(
            String integrationKey,
            String message,
            Map<String, Object> payload) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => true,
            'success' => true,
            'integrationKey' => integrationKey,
            'message' => message,
            'statusCode' => 200
        };
        if (payload != null) {
            result.put('data', payload);
        }
        return result;
    }

    public static Boolean isIntegrationSuccess(Map<String, Object> integrationResult) {
        if (integrationResult == null || integrationResult.isEmpty()) {
            return false;
        }
        if (integrationResult.containsKey('isSuccess')) {
            return integrationResult.get('isSuccess') == true;
        }
        return integrationResult.get('success') == true;
    }

    public static String getIntegrationErrorMessage(Map<String, Object> integrationResult) {
        if (integrationResult == null) {
            return 'Integration failed.';
        }
        Object message = integrationResult.get('message');
        return message != null ? String.valueOf(message) : 'Integration failed.';
    }
}