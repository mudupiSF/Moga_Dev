trigger ApplicationTrigger on Application__c (after insert, after update) {
    TriggerDispatcher.Run(new ApplicationTriggerHandler());
}