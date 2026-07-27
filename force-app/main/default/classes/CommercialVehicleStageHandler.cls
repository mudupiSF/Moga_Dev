/**
 * @description Commercial Vehicle Loan Stage Transition Handler
 * Implements custom business logic for CV loan application stage transitions
 * This class will be dynamically called from Lightning Web Components
 *
 * @author Salesforce Developer
 * @date 2026
 */
public class CommercialVehicleStageHandler implements dynamicStageNavigatorController.IStageOverride {

    public dynamicStageNavigatorController.StageNavigationResult execute(
            Id applicationId, String currentStagePhrase,
            String currentLoanStageName,
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String effectivePortfolio) {

        dynamicStageNavigatorController.StageNavigationResult result =
            new dynamicStageNavigatorController.StageNavigationResult();

        // ── Deviation logic: decide WHERE to go next ─────────────────────────
        // Do NOT update app.Sub_Stage__c / Stage__c — the framework does that.
        // ─────────────────────────────────────────────────────────────────────

        String currentStage    = app.Stage__c;
        String currentSubStage = app.Sub_Stage__c;
        
        if ('QDE'.equalsIgnoreCase(currentStage)
                && 'Basic Details'.equalsIgnoreCase(currentSubStage)) {

            result.newMainStage = 'Credit Processing';
            result.newStep      = 'Exposure Analysis';
            result.isSuccess    = true;

        } else {
            result.isSuccess = false;
            result.message   = 'CommercialVehicleStageHandler: no routing rule matched. '
                             + 'Stage="' + currentStage + '", SubStage="' + currentSubStage + '".';
        }

        // The framework handles everything after this return:
        //   • DML to advance Application__c.Sub_Stage__c and Stage__c
        //   • Bulk-update applicants sitting at the old step
        //   • Detect is_Current_Step_Applicant_based__c on the target step and
        //     auto-route to the first active applicant if needed
        //   • Rebuild the full NavigationPanelState for stageMenu.js

        // Optional: pin a specific applicant when the target step is applicant-based
        // result.preferredApplicantTabLabel = 'CoBo1';

        return result;
    }

    /**
     * Visibility check called by getMenuForPortfolio for completed/active stages.
     *
     * This stage (Basic Details / QDE) is visible in the navigation only when
     * the application actually went through the QDE → Basic Details path.
     * If the journey was routed differently (e.g. a different portfolio skipped
     * this step), return false to hide it from the completed path.
     */
    public Boolean isVisible(
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String effectivePortfolio) {

        // Show this stage only when the application passed through QDE stage
        // i.e. the current or a past stage was QDE.
        // app.Stage__c holds the CURRENT stage; completed stages are already
        // behind the current position, so we check the main stage name on the
        // CMT record matches what was actually traversed.
        if ('QDE'.equalsIgnoreCase(currentRec.Main_Stage_Name__c)) {
            return 'QDE'.equalsIgnoreCase(app.Stage__c)
                || app.Stage__c != null;   // QDE is always behind once passed
        }

        // For all other main stages belonging to this handler, default to visible
        return true;
    }
}