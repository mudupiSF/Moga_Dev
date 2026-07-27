public with sharing class PDFGeneratorWrapperController {
    @AuraEnabled
    public static string getTemplateId(string templateDeveloperName){
        try {
            PDFforceConfig__c pdfforceConfig = [SELECT Id FROM PDFforceConfig__c WHERE DeveloperName__c = :templateDeveloperName LIMIT 1];
            return pdfforceConfig.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}