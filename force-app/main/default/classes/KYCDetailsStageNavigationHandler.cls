/**
 * @description Applicant-type routing and menu visibility for KYC / Occupation steps.
 *
 * Wire Override_Apex__c = KYCDetailsStageNavigationHandler on:
 *   • KYC Details        (Wheels_KYC_Details) — execute routing
 *   • Occupation Details (Wheels_Occupation_Details) — isVisible only
 *
 * KYC Details → Next:
 *   Non-Individual → Dedupe and Eligibility
 *   Individual     → Occupation Details
 */
public with sharing class KYCDetailsStageNavigationHandler implements dynamicStageNavigatorController.IStageOverride {

    private static final String STEP_KYC_DETAILS = 'KYC Details';
    private static final String STEP_OCCUPATION_DETAILS = 'Occupation Details';
    private static final String STEP_DEDUPE_AND_ELIGIBILITY = 'Dedupe and Eligibility';

    public dynamicStageNavigatorController.StageNavigationResult execute(
        Id applicationId,
        String currentStagePhrase,
        String currentLoanStageName,
        Application__c app,
        Dynamic_Stage_Gate__mdt currentRec,
        String effectivePortfolio
    ) {
        dynamicStageNavigatorController.StageNavigationResult result =
            new dynamicStageNavigatorController.StageNavigationResult();

        if (currentRec == null) {
            result.isSuccess = false;
            result.message = 'KYCDetailsStageNavigationHandler: stage metadata record is missing.';
            return result;
        }

        String stepName = currentRec.Steps_Sub_Menu_Name__c;
        String targetMainStage = String.isNotBlank(currentRec.Forward_Main_Stage_Name__c)
            ? currentRec.Forward_Main_Stage_Name__c
            : currentRec.Main_Stage_Name__c;

        if (STEP_OCCUPATION_DETAILS.equalsIgnoreCase(stepName)) {
            result.newStep = String.isNotBlank(currentRec.Forward_Steps_Name__c)
                ? currentRec.Forward_Steps_Name__c
                : STEP_DEDUPE_AND_ELIGIBILITY;
            result.newMainStage = targetMainStage;
            result.isSuccess = true;
            result.message = 'Routing to ' + result.newStep + ' after Occupation Details.';
            return result;
        }

        if (!STEP_KYC_DETAILS.equalsIgnoreCase(stepName)) {
            result.isSuccess = false;
            result.message = 'KYCDetailsStageNavigationHandler: unsupported stage "' + stepName + '".';
            return result;
        }

        Applicant__c currentApplicant = resolveCurrentApplicant(
            app, applicationId, currentStagePhrase, currentRec
        );
        String applicantType = currentApplicant != null ? currentApplicant.Type__c : null;

        if (GenericUtility.isNonIndividualApplicationType(applicantType)) {
            result.newStep = STEP_DEDUPE_AND_ELIGIBILITY;
        } else {
            result.newStep = String.isNotBlank(currentRec.Forward_Steps_Name__c)
                ? currentRec.Forward_Steps_Name__c
                : STEP_OCCUPATION_DETAILS;
        }

        result.newMainStage = targetMainStage;
        result.preferredApplicantTabLabel = resolveApplicantTabLabel(currentApplicant);
        result.isSuccess = true;
        result.message = 'Routing to ' + result.newStep + '.';
        return result;
    }

    public Boolean isVisible(
        Application__c app,
        Dynamic_Stage_Gate__mdt currentRec,
        String effectivePortfolio
    ) {
        if (currentRec == null || app == null) {
            return true;
        }

        if (STEP_OCCUPATION_DETAILS.equalsIgnoreCase(currentRec.Steps_Sub_Menu_Name__c)) {
            return hasIndividualApplicant(app, app.Id);
        }

        return true;
    }

    private static Boolean hasIndividualApplicant(Application__c app, Id applicationId) {
        // A sub defaults to Individual and needs the Occupation Details step, so the menu must surface even when every top-level applicant is Non-Individual.
        for (Applicant__c applicant : loadAllActiveApplicants(app, applicationId)) {
            if (isExplicitIndividualType(applicant.Type__c)) {
                return true; // Found an Individual sub.
            }
        }
        return false; // No Individual sub found.
    }

    private static Boolean isExplicitIndividualType(String typeValue) {
        return String.isNotBlank(typeValue)
            && !GenericUtility.isNonIndividualApplicationType(typeValue);
    }

    private static Applicant__c resolveCurrentApplicant(
        Application__c app,
        Id applicationId,
        String currentStagePhrase,
        Dynamic_Stage_Gate__mdt currentRec
    ) {
        String applicantToken = resolveApplicantTokenFromStagePhrase(currentStagePhrase, currentRec);

        // Match the token (e.g. "B1_1") against ALL active applicants, INCLUDING
        // sub-applicants. A sub-applicant's KYC -> Next must route off the SUB's
        // own Type__c (Individual -> Occupation Details)
        if (String.isNotBlank(applicantToken)) {
            for (Applicant__c applicant : loadAllActiveApplicants(app, applicationId)) {
                if (applicantMatchesToken(applicant, applicantToken)) {
                    return applicant;
                }
            }
        }

        // Fallback: pin to the top-level Borrower applicant.
        List<Applicant__c> topLevel = loadTopLevelApplicants(app, applicationId);
        for (Applicant__c applicant : topLevel) {
            if ('Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c)) {
                return applicant;
            }
        }

        return topLevel.size() == 1 ? topLevel[0] : null;
    }

    private static List<Applicant__c> loadTopLevelApplicants(Application__c app, Id applicationId) {
        List<Applicant__c> applicants = new List<Applicant__c>();

        if (app != null && app.Applicants__r != null) {
            for (Applicant__c applicant : app.Applicants__r) {
                if (applicant.In_Active_Applicant__c == true || applicant.Is_Sub_Applicant__c == true) {
                    continue;
                }
                applicants.add(applicant);
            }
            return applicants;
        }

        if (applicationId == null) {
            return applicants;
        }

        return [
            SELECT Type__c, Applicant_Tab_Label__c, Applicant_Type__c, Is_Sub_Applicant__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
            AND In_Active_Applicant__c = false
            AND Is_Sub_Applicant__c = false
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * Active applicants INCLUDING sub-applicants. Used to resolve the applicant
     * currently in context (by tab-label token) and to decide Occupation Details
     * visibility, both of which must account for Individual sub-applicants.
     */
    private static List<Applicant__c> loadAllActiveApplicants(Application__c app, Id applicationId) {
        List<Applicant__c> applicants = new List<Applicant__c>();

        if (app != null && app.Applicants__r != null) {
            for (Applicant__c applicant : app.Applicants__r) {
                if (applicant.In_Active_Applicant__c == true) {
                    continue;
                }
                applicants.add(applicant);
            }
            return applicants;
        }

        if (applicationId == null) {
            return applicants;
        }

        return [
            SELECT Type__c, Applicant_Tab_Label__c, Applicant_Type__c, Is_Sub_Applicant__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
            AND In_Active_Applicant__c = false
            WITH SECURITY_ENFORCED
        ];
    }

    private static String resolveApplicantTabLabel(Applicant__c applicant) {
        if (applicant == null) {
            return null;
        }
        if (String.isNotBlank(applicant.Applicant_Tab_Label__c)) {
            return applicant.Applicant_Tab_Label__c.trim();
        }
        return 'Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c) ? 'Borrower' : null;
    }

    private static Boolean applicantMatchesToken(Applicant__c applicant, String applicantToken) {
        if (applicant == null || String.isBlank(applicantToken)) {
            return false;
        }
        if (String.isNotBlank(applicant.Applicant_Tab_Label__c)
                && applicant.Applicant_Tab_Label__c.equalsIgnoreCase(applicantToken.trim())) {
            return true;
        }
        return 'Borrower'.equalsIgnoreCase(applicantToken.trim())
            && 'Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c);
    }

    private static String resolveApplicantTokenFromStagePhrase(
        String currentStagePhrase,
        Dynamic_Stage_Gate__mdt currentRec
    ) {
        if (String.isBlank(currentStagePhrase) || currentRec == null) {
            return null;
        }

        String recPhrase = buildStagePhrase(
            currentRec.Steps_Sub_Menu_Name__c,
            currentRec.Main_Stage_Name__c
        );
        if (currentStagePhrase.startsWith(recPhrase + '_')) {
            return currentStagePhrase.substring(recPhrase.length() + 1);
        }
        return null;
    }

    private static String buildStagePhrase(String stepName, String mainStageName) {
        if (String.isBlank(stepName) || String.isBlank(mainStageName)) {
            return '';
        }
        return stepName.replaceAll('\\s+', '_') + '_' + mainStageName.replaceAll('\\s+', '_');
    }
}