/**
 * @description Controller for LWC/Aura components to handle loan stage transitions
 * This controller will be called dynamically from UI components
 *
 * @author 
 * @date 2026
 */
public with sharing class LoanStageTransitionController {

    /**
     * @description Get next stage for a loan application
     * @param productType Product type (e.g., COMMERCIAL_VEHICLE)
     * @param currentStage Current stage of the application
     * @param currentSubStage Current substage of the application
     * @return StageTransitionResult with next stage information
     */
    @AuraEnabled
    public static StageTransitionResult getNextStage(
        String productType,
        String currentStage,
        String currentSubStage,
        Boolean isNew
    ) {
        try {
            // Validate inputs
            if (String.isBlank(productType) || String.isBlank(currentStage) || String.isBlank(currentSubStage)) {
                throw new IllegalArgumentException('Product type, stage, and substage are required');
            }

            // Get the appropriate handler
            StageTransitionHandler handler = new CommercialVehicleStageHandler();

            // Get next stage
            StageTransitionResult result = handler.getNextStage(currentStage, currentSubStage, isNew);

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error getting next stage: ' + e.getMessage());
        }
    }
}