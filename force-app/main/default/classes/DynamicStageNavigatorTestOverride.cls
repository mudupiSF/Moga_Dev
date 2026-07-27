/**
 * Test helper implementing IStageOverride for unit tests.
 * Instantiate directly in test classes; not wired to CMT.
 */
public class DynamicStageNavigatorTestOverride implements dynamicStageNavigatorController.IStageOverride {

    public static Boolean hideFromMenu = false;
    public static Boolean executeSuccess = true;
    public static String targetStep = 'Investigation Reports';
    public static String targetMainStage = 'Credit Processing';

    public dynamicStageNavigatorController.StageNavigationResult execute(
            Id applicationId,
            String currentStagePhrase,
            String currentLoanStageName,
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String effectivePortfolio) {

        dynamicStageNavigatorController.StageNavigationResult result =
            new dynamicStageNavigatorController.StageNavigationResult();

        if (executeSuccess != true) {
            result.message = 'Test override failure';
            return result;
        }

        result.isSuccess = true;
        result.newStep = targetStep;
        result.newMainStage = targetMainStage;
        result.preferredApplicantTabLabel = 'Borrower';
        return result;
    }

    public Boolean isVisible(
            Application__c app,
            Dynamic_Stage_Gate__mdt currentRec,
            String effectivePortfolio) {
        return hideFromMenu != true;
    }
}