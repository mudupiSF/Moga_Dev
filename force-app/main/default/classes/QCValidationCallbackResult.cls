public class QCValidationCallbackResult {
    @AuraEnabled public Boolean hasWErrors { get; set; }
    @AuraEnabled public List<QCValidationMessage> validationMessages { get; set; }

    public QCValidationCallbackResult() {
        this.hasWErrors = false;
        this.validationMessages = new List<QCValidationMessage>();
    }

    public class QCValidationMessage {
        @AuraEnabled public String header { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String errorType { get; set; } // WARNING or ERROR

        public QCValidationMessage(String header, String message, String errorType) {
            this.header = header;
            this.message = message;
            this.errorType = errorType;
        }
    }
}