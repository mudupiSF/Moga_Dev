public with sharing class QueryTriggerHandler extends VTriggerHandler {
    
    public override void afterInsert(Map<Id, SObject> newItems) {
        List<Query__c> queriesToShare = new List<Query__c>();
        List<Query__c> queriesToCreateTAT = new List<Query__c>();
        for(Query__c newQuery : (List<Query__c>)newItems.values()) {
            if(newQuery.Assigned_To__c != NULL) {
                queriesToShare.add(newQuery);
            }
            if(String.isNotBlank(newQuery.Status__c) && String.isNotBlank(newQuery.Assigned_To__c)) {
                queriesToCreateTAT.add(newQuery);
            }
        }
        // Share queries with managers
        if(!queriesToShare.isEmpty()) {
            QueryTriggerService.shareQueriesWithManagers(queriesToShare);
        }
        // Create TAT
        /*if(!queriesToCreateTAT.isEmpty()) {
            QueryTriggerService.createTAT(queriesToCreateTAT, NULL);
        }*/
    }


    public override void afterUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems) {
        List<Query__c> queriesToShare = new List<Query__c>();
        List<Query__c> queriesToCreateTAT = new List<Query__c>();
        Map<Id, Query__c> oldQueries = (Map<Id, Query__c>)oldItems;
        for(Query__c newQuery : (List<Query__c>)newItems.values()) {
            Query__c oldQuery = oldQueries.get(newQuery.Id);
            if(newQuery.Assigned_To__c != oldQuery.Assigned_To__c) {
                queriesToShare.add(newQuery);
                queriesToCreateTAT.add(newQuery);
            }
            if(newQuery.Status__c != oldQuery.Status__c) {
                queriesToCreateTAT.add(newQuery);
            }
        }
        // Share queries with managers
        if(!queriesToShare.isEmpty()) {
            QueryTriggerService.shareQueriesWithManagers(queriesToShare);
        }
        // Create TAT
        /*if(!queriesToCreateTAT.isEmpty()) {
            QueryTriggerService.createTAT(queriesToCreateTAT, oldQueries);
        }*/
    }
}