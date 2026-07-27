/**
 * @description Controller for existing queries
 * @author Sourav Sharma
 * @date 2026-05-27
 */
public with sharing class ExistingQueriesController {
    
    /**
     * @description Gets the existing queries for a record
     * @param recordId Record Id
     * @return List<Map<String, Object>> List of query maps
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getExistingQueries(Id recordId) {
        try {
            Id currentUserId = UserInfo.getUserId();
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            User currentUser = [SELECT Id, Profile.Name, ManagerId FROM User WHERE Id = :currentUserId LIMIT 1];
            Boolean isSystemAdmin = currentUser.Profile.Name == 'System Administrator';
            
            Set<Id> allowedQueryIds = new Set<Id>();
            Schema.SObjectType objType = recordId.getSObjectType();
            String objectName = objType.getDescribe().getName();
            String soqlQuery = 'SELECT Id, Name, Subject__c, Priority__c, Status__c, Assigned_To__c, Assigned_To__r.Name, OwnerId, Owner.Name, Query_Type__c, Query_Sub_Type__c, Internal_Comments__c, Application_Line_Items__c, Description__c, Re_Open_Reason__c FROM Query__c WHERE ';
            if(objectName == 'Application__c') {
                soqlQuery += 'Application__c = :recordId';
            }
            else if(objectName == 'Asset__c') {
                soqlQuery += 'Asset__c = :recordId';
            }
            else if(objectName == 'Application_Line_Item__c') {
                soqlQuery += 'Application_Line_Item__c = :recordId';
            }
            soqlQuery += ' ORDER BY CreatedDate DESC LIMIT 200';
            
            for (Query__c qry : Database.query(soqlQuery)) {
                result.add(buildQueryMap(qry));
            }
            return result;
        }
        catch (Exception e) {
            throw new AuraHandledException('Error fetching queries: ' + e.getMessage());
        }
    }
    
    /**
     * @description Builds a query map
     * @param qry Query record
     * @return Map<String, Object> Query map
     */
    private static Map<String, Object> buildQueryMap(Query__c qry) {
        Map<String, Object> m = new Map<String, Object>();
        m.put('Id', qry.Id);
        m.put('QueryNumber', qry.Name);
        m.put('Subject', qry.Subject__c);
        m.put('Priority', qry.Priority__c);
        m.put('Status', qry.Status__c);
        m.put('AssignedTo', qry.Assigned_To__r != NULL ? qry.Assigned_To__r.Name : '');
        m.put('AssignedToId', qry.Assigned_To__c);
        m.put('OwnerName', qry.Owner != null ? qry.Owner.Name : '');
        m.put('OwnerId', qry.OwnerId);
        m.put('QueryType', qry.Query_Type__c);
        m.put('QuerySubType', qry.Query_Sub_Type__c);
        m.put('Comments', qry.Internal_Comments__c);
        m.put('ReOpenReason', qry.Re_Open_Reason__c);
        m.put('Description', qry.Description__c);
        return m;
    }

}