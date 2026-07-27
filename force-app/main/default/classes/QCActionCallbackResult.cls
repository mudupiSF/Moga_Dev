public class QCActionCallbackResult {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public Boolean shouldRefresh { get; set; }
    @AuraEnabled public Boolean showConfirmation { get; set; }
    @AuraEnabled public String uiAction { get; set; }
    @AuraEnabled public String uiComponentName { get; set; }
    @AuraEnabled public String uiComponentProps { get; set; }
    @AuraEnabled public String nextMethodName { get; set; }
    @AuraEnabled public String nextInputData { get; set; }
    @AuraEnabled public String confirmationLabel { get; set; }
    @AuraEnabled public String confirmationMessage { get; set; }
    @AuraEnabled public String confirmationTheme { get; set; }
    @AuraEnabled public String message { get; set; }
    @AuraEnabled public String toastVariant { get; set; }
    @AuraEnabled public String outputData { get; set; }

    public QCActionCallbackResult() {
        this.success = true;
        this.shouldRefresh = false;
        this.showConfirmation = false;
        this.uiAction = 'NONE';
        this.uiComponentName = '';
        this.uiComponentProps = '{}';
        this.nextMethodName = '';
        this.nextInputData = '{}';
        this.confirmationLabel = '';
        this.confirmationMessage = '';
        this.confirmationTheme = 'warning';
        this.message = '';
        this.toastVariant = 'success';
        this.outputData = '{}';
    }
}