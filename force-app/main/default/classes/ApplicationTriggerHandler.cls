/**
* @description Trigger handler for Application__c.
* Extend this class with Application-specific trigger logic.
*/
public with sharing class ApplicationTriggerHandler extends VTriggerHandler {

    public override void afterInsert(Map<Id, SObject> newItems) {
        List<Application__c> applicationsToSetName = new List<Application__c>();
        for(Application__c newApplication : (List<Application__c>)newItems.values()) {
            applicationsToSetName.add(newApplication);
        }
        if(!applicationsToSetName.isEmpty()) {
            ApplicationTriggerService.setApplicationName(applicationsToSetName);
        }
    }
}