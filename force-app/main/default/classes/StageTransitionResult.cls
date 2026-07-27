/**
 * @description Wrapper class for stage transition results
 * @author 
 * @date 2026
 */
public class StageTransitionResult {
    @AuraEnabled public String nextStage { get; set; }
    @AuraEnabled public String nextSubStage { get; set; }
    @AuraEnabled public String owner { get; set; }
    @AuraEnabled public String message { get; set; }

    /**
     * @description Constructor
     * @param nextStage Next stage name
     * @param nextSubStage Next substage name
     * @param owner Owner role for the next stage
     */
    public StageTransitionResult(String nextStage, String nextSubStage, String owner) {
        this.nextStage = nextStage;
        this.nextSubStage = nextSubStage;
        this.owner = owner;
    }

    /**
     * @description Constructor with message
     * @param nextStage Next stage name
     * @param nextSubStage Next substage name
     * @param owner Owner role for the next stage
     * @param message Descriptive message
     */
    public StageTransitionResult(String nextStage, String nextSubStage, String owner, String message) {
        this.nextStage = nextStage;
        this.nextSubStage = nextSubStage;
        this.owner = owner;
        this.message = message;
    }
}