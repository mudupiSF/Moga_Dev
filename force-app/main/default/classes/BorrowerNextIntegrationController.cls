/**
 * Runs the integrations triggered when the user clicks Next on the Basic Details screen.
 *   - CIF_ON_PAN       (real handler: CIFONPANHandlerAPI)
 *   - ETB_CASA         (real handler: ETBCASAHandlerAPI)
 *   - CUSTOMER_DEDUPE  (still stubbed pending handler)
 *   - VALIDATE_RECENT_LEAD (still stubbed pending handler)
 *
 * CIF on PAN + ETB CASA route through the Integration Master / IIntegrationHandler
 * framework via ApplicationUtility.invokeIntegrationSync, exactly like UIDAI OTP
 * Verify. When the matching Integration_Master__c record has
 * Is_Mocking_Service_Enabled__c = true, IntegrationUtility short-circuits the
 * HTTP callout and replays Mocking_Service_Response__c — so no live endpoint
 * is required while contracts are still being finalised upstream.
 *
 * The remaining stubbed integrations preserve the original placeholder payload
 * so the LWC orchestrator can keep advancing through its progress modal until
 * dedicated handlers land.
 */
public without sharing class BorrowerNextIntegrationController {

    private static final String INT_CIF_ON_PAN           = 'CIF_ON_PAN';
    private static final String INT_ETB_CASA             = 'ETB_CASA';
    private static final String INT_CUSTOMER_DEDUPE      = 'CUSTOMER_DEDUPE';
    private static final String INT_VALIDATE_RECENT_LEAD = 'VALIDATE_RECENT_LEAD';

    /** Mapping from the LWC-supplied integration key to the actual
     *  Integration_Master__c.Name value the framework expects. */
    private static final Map<String, String> INTEGRATION_MASTER_NAME = new Map<String, String>{
        INT_CIF_ON_PAN => 'CIF on PAN',
        INT_ETB_CASA   => 'ETB CASA'
    };

    private static final Set<String> SUPPORTED_INTEGRATIONS = new Set<String>{
        INT_CIF_ON_PAN,
        INT_ETB_CASA,
        INT_CUSTOMER_DEDUPE,
        INT_VALIDATE_RECENT_LEAD
    };

    @AuraEnabled
    public static Map<String, Object> runNextClickIntegration(String recordId, String applicantId, String integrationName) {
        if (String.isBlank(integrationName)) {
            throw new AuraHandledException('integrationName is required');
        }
        String resolvedIntegration = integrationName.trim().toUpperCase();
        if (!SUPPORTED_INTEGRATIONS.contains(resolvedIntegration)) {
            throw new AuraHandledException('Unsupported next-click integration: ' + resolvedIntegration);
        }

        // Real Integration Master / mock-driven integrations route through ApplicationUtility.
        if (INTEGRATION_MASTER_NAME.containsKey(resolvedIntegration)) {
            return runFrameworkIntegration(resolvedIntegration, applicantId);
        }

        // Fallback for integrations whose handlers are still being built —
        // keep the original stub-pass behaviour so the UI can still progress.
        Map<String, Object> stubResponse = runStubbedIntegration(resolvedIntegration);
        return new Map<String, Object>{
            'integrationName'    => resolvedIntegration,
            'staticResourceName' => stubResponse.get('mockResourceName'),
            'response'           => stubResponse
        };
    }

    /**
     * Invokes the Integration Master pipeline for handlers that are fully built
     */
    private static Map<String, Object> runFrameworkIntegration(String integrationKey, String applicantId) {
        String masterName = INTEGRATION_MASTER_NAME.get(integrationKey);
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException(integrationKey + ' requires an applicantId.');
        }

        ApplicationUtility.IntegrationResponseWrapper response =
            ApplicationUtility.invokeIntegrationSync(masterName, applicantId, 'Applicant__c');

        if (response != null && response.hasValidationError) {
            // Surface a single concise message; the LWC catches and displays it.
            throw new AuraHandledException(
                (String.isNotBlank(response.displayMessage) ? response.displayMessage : response.errorMessage)
                + ' (' + integrationKey + ')'
            );
        }

        return new Map<String, Object>{
            'integrationName' => integrationKey,
            'masterName'      => masterName,
            'displayMessage'  => response != null ? response.displayMessage : null,
            'success'         => true
        };
    }

    /** Placeholder for not-yet-built integration handlers. */
    private static Map<String, Object> runStubbedIntegration(String integrationName) {
        return new Map<String, Object>{
            'success'          => true,
            'message'          => integrationName + ' stub passed',
            'integrationKey'   => integrationName,
            'mockResourceName' => getMockResourceName(integrationName)
        };
    }

    /** Static-resource names retained for traceability on stubbed integrations only. */
    private static String getMockResourceName(String integrationName) {
        if (integrationName == INT_CUSTOMER_DEDUPE)      return 'CUSTOMER_DEDUPE_SUCCESS';
        if (integrationName == INT_VALIDATE_RECENT_LEAD) return 'VALIDATE_RECENT_LEAD_SUCCESS';
        return '';
    }
}