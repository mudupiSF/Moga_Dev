public with sharing class EditQueryModalController {

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getQueryDetails(Id queryId) {
        try {
            Query__c query = [SELECT Id, Name, Subject__c, Priority__c, Status__c, Assigned_To__c, Assigned_To__r.Name, OwnerId, Owner.Name, Query_Type__c, Query_Sub_Type__c, Internal_Comments__c, Application_Line_Items__c, Description__c, Re_Open_Reason__c FROM Query__c WHERE Id = :queryId LIMIT 1];
            Map<String, Object> queryDetails = new Map<String, Object>();
            queryDetails.put('Id', query.Id);
            queryDetails.put('Name', query.Name);
            queryDetails.put('Subject', query.Subject__c);
            queryDetails.put('Priority', query.Priority__c);
            queryDetails.put('Status', query.Status__c);
            queryDetails.put('AssignedTo', query.Assigned_To__r.Name);
            queryDetails.put('Owner', query.Owner.Name);
            queryDetails.put('QueryType', query.Query_Type__c);
            queryDetails.put('QuerySubType', query.Query_Sub_Type__c);
            queryDetails.put('Comments', query.Internal_Comments__c);
            queryDetails.put('ReOpenReason', query.Re_Open_Reason__c);
            queryDetails.put('Description', query.Description__c);
            return queryDetails;
        }
        catch (Exception e) {
            throw new AuraHandledException('Error fetching query details: ' + e.getMessage());
        }
    }
}