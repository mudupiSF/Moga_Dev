public with sharing class QCActionCallback1 implements QCActionCallbackInterface {

    public String executeOnClickAction(String methodName, String inputData, String outputData) {
        QCActionCallbackResult result = new QCActionCallbackResult();
        Map<String, Object> inputMap = parseJsonMap(inputData);

        try {
            if (String.isBlank(methodName)) {
                throw new AuraHandledException('Action methodName is required.');
            }

            String normalizedMethod = methodName.trim().toLowerCase();
            if (normalizedMethod == 'submit') {
                executeSubmit(inputMap, result);
            } else if (normalizedMethod == 'back') {
                executeBack(inputMap, result);
            } else {
                throw new AuraHandledException('Unsupported action: ' + methodName);
            }
        } catch (Exception ex) {
            result.success = false;
            result.message = ex.getMessage();
        }

        return JSON.serialize(result);
    }

    public String executeHandleEventAction(String methodName, String inputData, String outputData) {
        // Keep this extensible for future event-driven callbacks.
        return executeOnClickAction(methodName, inputData, outputData);
    }

    private static void executeSubmit(Map<String, Object> inputMap, QCActionCallbackResult result) {
        Id recordId = toId(inputMap.get('recordId'));
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required for Submit.');
        }

        Application__c loanToUpdate = new Application__c(
            Id = recordId,
            Stage__c = 'Post Sanction Sales'
        );
        update loanToUpdate;

        result.message = 'Application moved to Financial Sanction / IW Initiated successfully.';
        result.toastVariant = 'success';
        result.shouldRefresh = true;
    }

    private static void executeBack(Map<String, Object> inputMap, QCActionCallbackResult result) {
        Id recordId = toId(inputMap.get('recordId'));
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required for Back.');
        }

        Application__c loanToUpdate = new Application__c(
            Id = recordId,
            Stage__c = 'DDE'
        );
        update loanToUpdate;

        result.message = 'Application moved to ' +loanToUpdate.Stage__c+ ' successfully.';
        result.toastVariant = 'success';
        result.shouldRefresh = true;
    }

    private static Map<String, Object> parseJsonMap(String inputData) {
        if (String.isBlank(inputData)) {
            return new Map<String, Object>();
        }
        Object payload = JSON.deserializeUntyped(inputData);
        if (payload instanceof Map<String, Object>) {
            return (Map<String, Object>) payload;
        }
        return new Map<String, Object>();
    }

    private static Id toId(Object rawValue) {
        if (rawValue == null || String.isBlank(String.valueOf(rawValue))) {
            return null;
        }
        return (Id) String.valueOf(rawValue);
    }
}