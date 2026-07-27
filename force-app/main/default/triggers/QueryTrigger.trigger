trigger QueryTrigger on Query__c (after insert, after update) {
    TriggerDispatcher.Run(new QueryTriggerHandler());
}