/**
 * @description Interface for handling loan application stage transitions
 * @author Salesforce Developer
 * @date 2026
 */
public interface StageTransitionHandler {
    /**
     * @description Get the next stage, substage, and owner based on current stage
     * @param currentStage Current stage of the loan application
     * @param currentSubStage Current substage of the loan application
     * @return StageTransitionResult containing next stage, substage, and owner
     */
    StageTransitionResult getNextStage(String currentStage, String currentSubStage, Boolean isNew);
}