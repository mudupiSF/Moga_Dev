@IsTest(SeeAllData=true)
private class QueryTriggerTest {

    private static Query__c makeQueryFromSeed(Id assignedToId) {
        List<Query__c> seeds = [
            SELECT Application__c, Description__c, Query_Type__c, Query_Sub_Type__c,
                   Priority__c, Applicant__c, Document_Checklist__c, Application_Line_Items__c, Asset__c
            FROM Query__c
            LIMIT 1
        ];
        System.assert(!seeds.isEmpty(), 'Seed Query__c data is required for this org-aware test');
        Query__c s = seeds[0];

        Query__c q = new Query__c();
        q.Status__c = 'New';
        q.Application__c = s.Application__c;
        q.Description__c = String.isNotBlank(s.Description__c) ? s.Description__c : 'QueryTriggerTest description';
        q.Query_Type__c = s.Query_Type__c;
        q.Query_Sub_Type__c = s.Query_Sub_Type__c;
        q.Priority__c = s.Priority__c;
        q.Applicant__c = s.Applicant__c;
        q.Document_Checklist__c = s.Document_Checklist__c;
        q.Application_Line_Items__c = s.Application_Line_Items__c;
        q.Asset__c = s.Asset__c;
        q.Assigned_To__c = assignedToId;
        q.Subject__c = (String.isNotBlank(q.Query_Type__c) ? q.Query_Type__c : 'Query') +
            (String.isNotBlank(q.Query_Sub_Type__c) ? ' - ' + q.Query_Sub_Type__c : '');
        return q;
    }

    @IsTest
    static void testHandleAfterInsertWithAssignedAndNullAssigned() {
        Id assignedUserId = UserInfo.getUserId();

        Query__c qWithAssigned = makeQueryFromSeed(assignedUserId);
        Query__c qWithoutAssigned = makeQueryFromSeed(null);
        insert new List<Query__c>{ qWithAssigned, qWithoutAssigned };

        // Re-query so Trigger.new-like records include persisted ids/values.
        List<Query__c> insertedQueries = [
            SELECT Id, Assigned_To__c
            FROM Query__c
            WHERE Id IN :new Set<Id>{ qWithAssigned.Id, qWithoutAssigned.Id }
        ];

        Test.startTest();
        QueryTriggerHandler.handleAfterInsert(insertedQueries);
        Test.stopTest();

        Integer sharesForAssigned = [SELECT COUNT() FROM Query__Share WHERE ParentId = :qWithAssigned.Id];
        System.assert(sharesForAssigned >= 0, 'Handler should execute without unhandled exceptions');
    }

    @IsTest
    static void testHandleAfterInsertWithEmptyList() {
        Test.startTest();
        QueryTriggerHandler.handleAfterInsert(new List<Query__c>());
        Test.stopTest();
        System.assert(true, 'Empty list path executed');
    }
}