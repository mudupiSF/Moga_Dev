/**
 * Invokes FI Waiver through the Integration Master framework.
 * Mirrors MNRLAPIController / AMLCheckAPIController surface for LWC orchestrators.
 */
public with sharing class FIWaiverAPIController {

    public class FiWaiverResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Integer investigationsCreated { get; set; }
        @AuraEnabled public String waiverMessage { get; set; }

        public FiWaiverResult() {
            this.isSuccess = false;
            this.investigationsCreated = 0;
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getFiCreationMode(String applicationId) {
        if (String.isBlank(applicationId)) {
            return FIWaiverAPIHandler.FI_MODE_INDIVIDUAL;
        }
        return FIWaiverAPIHandler.resolveFiCreationMode((Id) applicationId);
    }

    @AuraEnabled
    public static ApplicationUtility.IntegrationResponseWrapper invokeFIWaiverAPI(
        String applicationId
    ) {
        Id borrowerApplicantId = getBorrowerApplicantId(applicationId);
        if (borrowerApplicantId == null) {
            ApplicationUtility.IntegrationResponseWrapper response =
                new ApplicationUtility.IntegrationResponseWrapper();
            response.hasValidationError = true;
            response.errorMessage = 'An active borrower is required for FI Waiver.';
            response.displayMessage = response.errorMessage;
            return response;
        }

        return ApplicationUtility.invokeIntegrationSync(
            FIWaiverAPIHandler.INTEGRATION_KEY,
            borrowerApplicantId,
            'Applicant__c'
        );
    }

    /**
     * Offer Next: Individual + PV NI. CV NI FI is created on Customer Dedupe.
     */
    @AuraEnabled
    public static FiWaiverResult runFiWaiverOfferNextFlow(String applicationId) {
        if (String.isBlank(applicationId)) {
            FiWaiverResult flowResult = new FiWaiverResult();
            flowResult.message = 'Application record Id is missing.';
            return flowResult;
        }

        String mode = FIWaiverAPIHandler.resolveFiCreationMode(applicationId);
        if (FIWaiverAPIHandler.FI_MODE_CV_NI.equals(mode)) {
            return buildSkippedResult(
                'FI investigations are created during Customer Dedupe for CV Non-Individual applications.'
            );
        }

        return runFiWaiverFlow(applicationId);
    }

    /**
     * Customer Dedupe forward: CV NI only.
     */
    @AuraEnabled
    public static FiWaiverResult runFiWaiverDedupeNextFlow(String applicationId) {
        if (String.isBlank(applicationId)) {
            FiWaiverResult flowResult = new FiWaiverResult();
            flowResult.message = 'Application record Id is missing.';
            return flowResult;
        }

        String mode = FIWaiverAPIHandler.resolveFiCreationMode(applicationId);
        if (!FIWaiverAPIHandler.FI_MODE_CV_NI.equals(mode)) {
            return buildSkippedResult('FI creation is not required at Customer Dedupe for this application.');
        }

        return runFiWaiverFlow(applicationId);
    }

    private static FiWaiverResult runFiWaiverFlow(String applicationId) {
        FiWaiverResult flowResult = new FiWaiverResult();
        Id appId = (Id) applicationId;
        String mode = FIWaiverAPIHandler.resolveFiCreationMode(appId);
        Boolean isNiApplication = FIWaiverAPIHandler.FI_MODE_PV_NI.equals(mode)
            || FIWaiverAPIHandler.FI_MODE_CV_NI.equals(mode);

        if (isNiApplication) {
            FIWaiverAPIHandler.seedWaiverPayloadForApplication(appId);
            flowResult.waiverMessage = 'FI Waiver skipped for Non-Individual.';
        } else {
            ApplicationUtility.IntegrationResponseWrapper waiverResult = invokeFIWaiverAPI(applicationId);
            if (waiverResult != null && waiverResult.hasValidationError == true) {
                if (isRefreshBlockedAfterPriorSuccess(waiverResult)) {
                    FIWaiverAPIHandler.seedWaiverPayloadForApplication(appId);
                    flowResult.waiverMessage = 'FI Waiver completed successfully.';
                } else {
                    flowResult.message = String.isNotBlank(waiverResult.displayMessage)
                        ? waiverResult.displayMessage
                        : waiverResult.errorMessage;
                    return flowResult;
                }
            } else {
                flowResult.waiverMessage = waiverResult != null && String.isNotBlank(waiverResult.displayMessage)
                    ? waiverResult.displayMessage
                    : 'FI Waiver completed successfully.';
            }
        }

        FIInvestigationController.CreationResult creationResult =
            FIInvestigationController.createFiInvestigations(appId);

        flowResult.isSuccess = creationResult.isSuccess == true;
        flowResult.message = creationResult.message;
        flowResult.investigationsCreated = creationResult.investigationsCreated;
        return flowResult;
    }

    private static FiWaiverResult buildSkippedResult(String message) {
        FiWaiverResult flowResult = new FiWaiverResult();
        flowResult.isSuccess = true;
        flowResult.message = message;
        flowResult.waiverMessage = message;
        flowResult.investigationsCreated = 0;
        return flowResult;
    }

    private static Boolean isRefreshBlockedAfterPriorSuccess(
        ApplicationUtility.IntegrationResponseWrapper waiverResult
    ) {
        if (waiverResult == null || waiverResult.hasValidationError != true) {
            return false;
        }
        String message = String.isNotBlank(waiverResult.errorMessage)
            ? waiverResult.errorMessage
            : waiverResult.displayMessage;
        return String.isNotBlank(message)
            && message.contains('Refresh is not allowed');
    }

    private static Id getBorrowerApplicantId(String applicationId) {
        if (String.isBlank(applicationId)) {
            return null;
        }
        List<Applicant__c> borrowers = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND Applicant_Type__c = 'Borrower'
              AND In_Active_Applicant__c = false
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return borrowers.isEmpty() ? null : borrowers[0].Id;
    }
}