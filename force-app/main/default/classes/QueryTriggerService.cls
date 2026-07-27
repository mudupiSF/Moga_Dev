public with sharing class QueryTriggerService {

    /**
     * Shares Query__c records with the assigned users' manager groups.
     * This is a service utility so trigger handlers can stay lightweight.
     */
    public static void shareQueriesWithManagers(List<Query__c> newQueries) {
        Set<Id> assignedUserIds = new Set<Id>();
        for (Query__c queryRecord : newQueries) {
            if (queryRecord.Assigned_To__c != null) {
                assignedUserIds.add(queryRecord.Assigned_To__c);
            }
        }

        Map<Id, Id> userToManagerGroupId = new Map<Id, Id>();
        for (Group groupRecord : [
            SELECT Id, RelatedId
            FROM Group
            WHERE RelatedId IN :assignedUserIds
            AND Type = 'Manager'
        ]) {
            userToManagerGroupId.put(groupRecord.RelatedId, groupRecord.Id);
        }

        List<Query__Share> sharesToInsert = new List<Query__Share>();
        for (Query__c queryRecord : newQueries) {
            sharesToInsert.add(new Query__Share(
                ParentId = queryRecord.Id,
                UserOrGroupId = queryRecord.Assigned_To__c,
                AccessLevel = 'Edit',
                RowCause = Schema.Query__Share.RowCause.Manual
            ));
            Id managerGroupId = userToManagerGroupId.get(queryRecord.Assigned_To__c);
            if (managerGroupId != null) {
                sharesToInsert.add(new Query__Share(
                    ParentId = queryRecord.Id,
                    UserOrGroupId = managerGroupId,
                    AccessLevel = 'Edit',
                    RowCause = Schema.Query__Share.RowCause.Manual
                ));
            }
        }
        if(!sharesToInsert.isEmpty()) {
            Database.insert(sharesToInsert, false);
        }
    }

    public static void createTAT(List<Query__c> newQueries, Map<Id, Query__c> oldQueries) {
        List<TATEventRecorder.Input> inputs = new List<TATEventRecorder.Input>();
        TATEventRecorder.Input input;
        for(Query__c newQuery : newQueries) {
            Query__c oldQuery = oldQueries != NULL ? oldQueries.get(newQuery.Id) : NULL;
            input = new TATEventRecorder.Input();
            if(newQuery.Status__c == 'Open' || newQuery.Status__c == 'Re-Open') {
            input.applicationId = newQuery.Application__c;
                input.queryId = newQuery.Id;
                input.stage = newQuery.Status__c;
                input.newValue = newQuery.OwnerId;
                inputs.add(input);
            }
            else if(newQuery.Status__c == 'In Progress') {
                input.applicationId = newQuery.Application__c;
                input.queryId = newQuery.Id;
                input.stage = newQuery.Status__c;
                input.newValue = newQuery.Assigned_To__c;
                input.oldValue = newQuery.OwnerId;
                inputs.add(input);
            }
            else if(newQuery.Status__c == 'Resolved' || newQuery.Status__c == 'Rejected') {
                input.applicationId = newQuery.Application__c;
                input.queryId = newQuery.Id;
                input.stage = newQuery.Status__c;
                input.newValue = newQuery.OwnerId;
                input.oldValue = newQuery.Assigned_To__c;
                inputs.add(input);
            }
            // If the status is changed to closed, then the old value is the old owner
            else if(newQuery.Status__c == 'Closed') {
                input.applicationId = newQuery.Application__c;
                input.queryId = newQuery.Id;
                input.stage = newQuery.Status__c;
                input.oldValue = newQuery.OwnerId;
                inputs.add(input);
            }
            // If the assigned to is changed, then the old value is the old assigned to
            if(oldQuery != NULL && newQuery.Assigned_To__c != oldQuery.Assigned_To__c) {
                input.applicationId = newQuery.Application__c;
                input.queryId = newQuery.Id;
                input.stage = newQuery.Status__c;
                input.newValue = newQuery.Assigned_To__c;
                input.oldValue = oldQuery.Assigned_To__c;
                inputs.add(input);
            }
        }
        System.debug('inputs: ' + inputs);
        // Record TAT events
        TATEventRecorder.record(inputs);
    }
}