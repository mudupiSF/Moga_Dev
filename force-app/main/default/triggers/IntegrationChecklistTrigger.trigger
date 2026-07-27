trigger IntegrationChecklistTrigger on Integration_Checklist__c (before insert, after insert, before update,after update) {
    TriggerDispatcher.Run(new IntegrationChecklistTriggerHandler());
}