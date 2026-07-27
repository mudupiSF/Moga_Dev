/**
* @description Service class for Application__c trigger operations.
*/
public with sharing class ApplicationTriggerService {

    /**
    * @description Sets the name of the Application__c record.
    * The name is set to the Product__c and Application_Number__c.
    */
    public static void setApplicationName(List<Application__c> newApplications) {
        List<Application__c> applicationsToUpdate = new List<Application__c>();
        for(Application__c newApplication : newApplications) {
            Application__c applicationToUpdate = new Application__c(Id = newApplication.Id);
            applicationToUpdate.Name = newApplication.Product__c + '-' + newApplication.Application_Number__c;
            applicationsToUpdate.add(applicationToUpdate);
        }
        if(!applicationsToUpdate.isEmpty()) {
            update applicationsToUpdate;
        }
    }
}