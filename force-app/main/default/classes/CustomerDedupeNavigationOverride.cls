/**
 * Stage override for Dedupe and Eligibility NEXT when advancing the application.
 * Wire on Dynamic_Stage_Gate__mdt.Override_Apex__c for the Dedupe and Eligibility step.
 */
public with sharing class CustomerDedupeNavigationOverride implements dynamicStageNavigatorController.IStageOverride {

    private static final String DEDUPE_STEP = 'Dedupe and Eligibility';

    public dynamicStageNavigatorController.StageNavigationResult execute(
            Id applicationId,
            String currentStagePhrase,
            String currentLoanStageName,
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String effectivePortfolio) {

        dynamicStageNavigatorController.StageNavigationResult result =
            new dynamicStageNavigatorController.StageNavigationResult();

        if (applicationId == null || currentRec == null) {
            result.message = 'Application and stage configuration are required.';
            return result;
        }

        List<Applicant__c> additionalApplicants = [
            SELECT Id, Applicant_Tab_Label__c, Applicant_Type__c,
                   Current_Loan_Stage_Complete__c, Loan_Stage__c,
                   Customer_Code__c, Invalid_Customer_Code__c, Relationship_with_Bank__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
            AND In_Active_Applicant__c = false
            AND Applicant_Type__c IN ('Guarantor', 'Co-Borrower', 'Beneficiary')
            ORDER BY Applicant_Tab_Label__c
        ];

        for (Applicant__c pendingPrior : additionalApplicants) {
            if (!CustomerDedupeController.hasApplicantCompletedPriorStagesForDedupe(pendingPrior)) {
                Map<String, String> qdeStep =
                    dynamicStageNavigatorController.getInitialQdeStepForApplication(applicationId);
                result.isSuccess = true;
                result.newStep = qdeStep.get('targetStep');
                result.newMainStage = String.isNotBlank(qdeStep.get('targetMainStage'))
                    ? qdeStep.get('targetMainStage')
                    : currentRec.Main_Stage_Name__c;
                result.preferredApplicantTabLabel = pendingPrior.Applicant_Tab_Label__c;
                result.message = 'Complete prior stages for the added applicant before proceeding.';
                return result;
            }
        }

        for (Applicant__c pendingDedupe : additionalApplicants) {
            if (!CustomerDedupeController.hasApplicantTrulyResolvedDedupe(pendingDedupe)) {
                result.isSuccess = true;
                result.newStep = DEDUPE_STEP;
                result.newMainStage = currentRec.Main_Stage_Name__c;
                result.preferredApplicantTabLabel = pendingDedupe.Applicant_Tab_Label__c;
                result.message = 'Complete Dedupe and Eligibility for the next applicant.';
                return result;
            }
        }

        if (!CustomerDedupeController.isBorrowerCombinedEligibilitySatisfied(applicationId)) {
            result.isSuccess = true;
            result.newStep = DEDUPE_STEP;
            result.newMainStage = currentRec.Main_Stage_Name__c;
            result.preferredApplicantTabLabel = 'Borrower';
            result.message = 'Run combined eligibility check on the Borrower tab before proceeding.';
            return result;
        }

        if (CustomerDedupeController.areAllApplicantsDedupeJourneyComplete(applicationId)
                || !CustomerDedupeController.canAddMoreApplicantsForApplication(applicationId)) {
            CustomerDedupeController.markAllApplicantsDedupeStepComplete(applicationId);
            result.isSuccess = true;
            result.newStep = currentRec.Forward_Steps_Name__c;
            result.newMainStage = String.isNotBlank(currentRec.Forward_Main_Stage_Name__c)
                ? currentRec.Forward_Main_Stage_Name__c
                : app.Stage__c;
            result.message = 'Advance to next step.';
            return result;
        }

        result.isSuccess = true;
        result.newStep = DEDUPE_STEP;
        result.newMainStage = currentRec.Main_Stage_Name__c;
        result.preferredApplicantTabLabel = 'Borrower';
        result.message = 'Return to Borrower dedupe to add more applicants.';
        return result;
    }

    public Boolean isVisible(
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String effectivePortfolio) {
        return true;
    }

    /**
     * Called from LWC after a dedupe action to advance navigation.
     *   - New applicant just created  → build menu hint + navigate to their Basic Details.
     *   - Non-Borrower on Dedupe step → route to the next applicant in sequence.
     *   - Otherwise                   → delegate to the standard processNextStageRequest.
     *
     * Moved from dynamicStageNavigatorController.processCustomerDedupeNextRequest.
     */
    @AuraEnabled(cacheable=false)
    public static dynamicStageNavigatorController.StageNavigationResult processCustomerDedupeNextRequest(
            Id applicationId,
            String createdApplicantTabLabel,
            String currentApplicantTabLabel,
            String currentStagePhrase,
            String currentLoanStageName) {

        dynamicStageNavigatorController.StageNavigationResult result =
            new dynamicStageNavigatorController.StageNavigationResult();
        if (applicationId == null) {
            result.message = 'applicationId is required.';
            return result;
        }

        try {
            if (String.isNotBlank(createdApplicantTabLabel)) {
                Map<String, String> qdeStep =
                    dynamicStageNavigatorController.getInitialQdeStepForApplication(applicationId);
                String targetStep = qdeStep.get('targetStep');

                dynamicStageNavigatorController.NavigationPanelState navState =
                    dynamicStageNavigatorController.buildNavStateWithApplicantAndStepHint(
                        applicationId, createdApplicantTabLabel, targetStep);
                if (navState == null || navState.isSuccess != true) {
                    result.message = (navState != null && String.isNotBlank(navState.message))
                        ? navState.message
                        : 'Could not build navigation for ' + createdApplicantTabLabel + '.';
                    return result;
                }

                result.isSuccess                  = true;
                result.renderGuarantorScreen      = true;
                result.preferredApplicantTabLabel = createdApplicantTabLabel;
                result.message                    = 'Proceed to ' + targetStep + ' for ' + createdApplicantTabLabel + '.';
                result.navigationState            = navState;
                return result;
            }

            if (String.isNotBlank(currentApplicantTabLabel)
                    && !'Borrower'.equalsIgnoreCase(currentApplicantTabLabel.trim())
                    && isDedupeContext(currentStagePhrase, currentLoanStageName)) {

                // NEXT marks the current non-Borrower applicant's dedupe complete, then always
                // returns to the Borrower's Dedupe & Eligibility page (combined eligibility hub).
                CustomerDedupeController.markApplicantDedupeCompleteByTabLabel(
                    applicationId, currentApplicantTabLabel.trim());
                // Beneficiary clearing dedupe → deep-clone + activate its Guarantor clone-shell (best-effort).
                ApplicantCloneService.activateGuarantorCloneForBeneficiaryByTabLabel(
                    applicationId, currentApplicantTabLabel.trim());
                CustomerDedupeController.clearBorrowerEligibilityForRecheck(applicationId);

                String nextTabLabel = 'Borrower';
                dynamicStageNavigatorController.NavigationPanelState navState =
                    dynamicStageNavigatorController.buildNavStateWithApplicantAndStepHint(
                        applicationId, nextTabLabel, DEDUPE_STEP);
                if (navState == null || navState.isSuccess != true) {
                    result.message = (navState != null && String.isNotBlank(navState.message))
                        ? navState.message
                        : 'Could not build navigation for ' + nextTabLabel + '.';
                    return result;
                }

                result.isSuccess                  = true;
                result.renderGuarantorScreen      = true;
                result.preferredApplicantTabLabel = nextTabLabel;
                result.message                    = 'Return to Borrower Dedupe and Eligibility.';
                result.navigationState            = navState;
                return result;
            }

            if (String.isNotBlank(currentStagePhrase)) {
                return dynamicStageNavigatorController.processNextStageRequest(
                    applicationId, currentStagePhrase, currentLoanStageName);
            }

            result.message = 'currentStagePhrase is required when no new applicant was created.';
        } catch (Exception e) {
            result.isSuccess = false;
            result.message   = 'processCustomerDedupeNextRequest: ' + e.getMessage();
        }
        return result;
    }

    /** Returns true when the current navigation context is the Dedupe and Eligibility step. */
    private static Boolean isDedupeContext(String stagePhrase, String loanStageName) {
        if (String.isNotBlank(loanStageName)
                && DEDUPE_STEP.equalsIgnoreCase(loanStageName.trim())) {
            return true;
        }
        if (String.isBlank(stagePhrase)) return false;
        String dedupePhrase = 'Dedupe_and_Eligibility_QDE';
        return stagePhrase.equalsIgnoreCase(dedupePhrase)
            || stagePhrase.startsWithIgnoreCase(dedupePhrase + '_');
    }
}