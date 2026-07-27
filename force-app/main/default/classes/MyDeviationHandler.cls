public class MyDeviationHandler
        implements dynamicStageNavigatorController.IStageOverride {

    public dynamicStageNavigatorController.StageNavigationResult execute(
            Id applicationId, String currentStagePhrase,
            String currentLoanStageName,
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String effectivePortfolio) {

        dynamicStageNavigatorController.StageNavigationResult result =
            new dynamicStageNavigatorController.StageNavigationResult();

        // ── Deviation logic only: decide WHERE to go next ─────────────────────
        // Do NOT update app.Sub_Stage__c / Stage__c here — the framework does that.
        // Add any custom evaluations, callouts, or related-record DML here.
        // ─────────────────────────────────────────────────────────────────────

        result.newStep      = 'Exposure Analysis';   // Steps_Sub_Menu_Name__c of the target
        result.newMainStage = 'Credit Processing';             // Main_Stage_Name__c of the target
        result.isSuccess    = true;

        // The framework handles everything after this return:
        //   • DML to advance Application__c.Sub_Stage__c and Stage__c
        //   • Bulk-update applicants sitting at the old step
        //   • Detect is_Current_Step_Applicant_based__c on 'Asset Details' and
        //     auto-route to the first active applicant if needed
        //   • Rebuild the full NavigationPanelState for stageMenu.js

        // Optional: pin a specific applicant when the target step is applicant-based
        // result.preferredApplicantTabLabel = 'CoBo1';

        return result;
    }

    public Boolean isVisible(
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String effectivePortfolio) {

        // This handler is purely a deviation router; the step should always
        // remain visible in the navigation panel.
        return true;
    }
}