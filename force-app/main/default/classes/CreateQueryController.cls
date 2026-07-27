/**
 * @description Controller for creating a query
 * @author Sourav Sharma
 * @date 2026-05-27
 */
public with sharing class CreateQueryController {
    /**
     * @description Gets the parent record from the record Id
     * @param recordId Record Id
     * @return ParentWrapper Parent record wrapper
     */
    @AuraEnabled(cacheable=true)
    public static ParentWrapper getParentRecord(Id recordId) {
        try {
            ParentWrapper parentWrapper;
            Schema.SObjectType objType = recordId.getSObjectType();
            String objectName = objType.getDescribe().getName();
            if(objectName == 'Application__c') {
                List<Application__c> applications = [SELECT Id FROM Application__c WHERE Id =: recordId LIMIT 1];
                if(applications != NULL && !applications.isEmpty()) {
                    Application__c application = applications[0];
                    String applicationLineItemId = NULL;
                    List<Application_Line_Item__c> applicationLineItems = [SELECT Id FROM Application_Line_Item__c WHERE Application__c =: application.Id];
                    if(applicationLineItems != NULL && applicationLineItems.size() == 1) {
                        applicationLineItemId = applicationLineItems[0].Id;
                    }
                    parentWrapper = new ParentWrapper(application.Id, applicationLineItemId, recordId, objectName);
                }
            }
            else if(objectName == 'Application_Line_Item__c') {
                List<Application_Line_Item__c> applicationLineItems = [SELECT Id, Application__c FROM Application_Line_Item__c WHERE Id =: recordId LIMIT 1];
                if(applicationLineItems != NULL && !applicationLineItems.isEmpty()) {
                    Application_Line_Item__c applicationLineItem = applicationLineItems[0];
                    parentWrapper = new ParentWrapper(applicationLineItem.Application__c, applicationLineItem.Id, recordId, objectName);
                }
            }
            else if(objectName == 'Asset__c') {
                List<Asset__c> assets = [SELECT Id, Application_Line_Items__c, Application_Line_Items__r.Application__c FROM Asset__c WHERE Id =: recordId LIMIT 1];
                if(assets != NULL && !assets.isEmpty()) {
                    Asset__c asset = assets[0];
                    parentWrapper = new ParentWrapper(asset.Application_Line_Items__r.Application__c, asset.Application_Line_Items__c, recordId, objectName);
                }
            }
            else if(objectName == 'Document_CheckList__c') {
                List<Document_Checklist__c> documentChecklists = [SELECT Id, Application__c, Application_Line_Items__c, Applicant__c, Applicant__r.Name FROM Document_Checklist__c WHERE Id =: recordId LIMIT 1];
                if(documentChecklists != NULL && !documentChecklists.isEmpty()) {
                    Document_Checklist__c documentChecklist = documentChecklists[0];
                    parentWrapper = new ParentWrapper(documentChecklist.Application__c, documentChecklist.Application_Line_Items__c, recordId, objectName);
                    parentWrapper.applicantId = documentChecklist.Applicant__c;
                    parentWrapper.applicantName = documentChecklist.Applicant__r.Name;
                }
            }
            return parentWrapper;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching parent record: ' + ex.getMessage());
        }
    }
    
    /**
     * @description Gets applicants for a loan application (for optional Applicant lookup on Case creation)
     * @param applicationId Application Id
     * @return List<Map<String,String>> List of {value: Id, label: Name}
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getApplicants(String applicationId) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            List<Applicant__c> applicants = [
                SELECT Id, Name, Customer_First_Name__c, Customer_Last_Name__c, Company_Name__c
                FROM Applicant__c
                WHERE Application__c =: applicationId
                ORDER BY Id
            ];
            for (Applicant__c aplcnt : applicants) {
                options.add(new Map<String, String>{
                    'value' => aplcnt.Id,
                    'label' => String.isNotBlank(aplcnt.Customer_First_Name__c) && String.isNotBlank(aplcnt.Customer_Last_Name__c) ? aplcnt.Customer_First_Name__c + ' ' + aplcnt.Customer_Last_Name__c : String.isNotBlank(aplcnt.Company_Name__c) ? aplcnt.Company_Name__c : aplcnt.Name
                });
            }
            return options;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching applicants: ' + ex.getMessage());
        }
    }
    
    /**
     * @description Gets distinct query types from Query_Configuration__mdt based on loan application stage
     * @param applicationId Application Id
     * @return List<String> List of distinct query types
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getQueryTypes(String applicationId) {
        try {
            // Get the loan application stage
            Application__c application = [SELECT Id, Stage__c FROM Application__c WHERE Id =: applicationId LIMIT 1];
            String stage = application.Stage__c;
            
            // Query Query_Configuration__mdt where Stage contains the loan application stage
            List<Query_Configuration__mdt> configs = [SELECT Query_Type__c 
                                                      FROM Query_Configuration__mdt 
                                                      WHERE Stage__c LIKE :('%' + stage + '%')
                                                      AND Query_Type__c != null
                                                      ORDER BY Query_Type__c];
            
            // Get distinct query types
            Set<String> queryTypeSet = new Set<String>();
            for (Query_Configuration__mdt config : configs) {
                queryTypeSet.add(config.Query_Type__c);
            }
            
            List<String> queryTypes = new List<String>(queryTypeSet);
            queryTypes.sort();
            return queryTypes;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching query types: ' + ex.getMessage());
        }
    }
    
    /**
    * @description Gets query sub types from Query_Configuration__mdt based on application stage and query type
    * @param applicationId Application Id
    * @param queryType Selected query type
    * @return List<String> List of distinct query sub types
    */
    @AuraEnabled(cacheable=true)
    public static List<String> getQuerySubTypes(String applicationId, String queryType) {
        try {
            // Get the application stage
            Application__c application = [SELECT Stage__c FROM Application__c WHERE Id =: applicationId LIMIT 1];
            String stage = application.Stage__c;
            
            // Query Query_Configuration__mdt where Stage contains the application stage and Query Type matches
            List<Query_Configuration__mdt> configs = [SELECT Query_Sub_Type__c
                                                      FROM Query_Configuration__mdt 
                                                      WHERE Stage__c LIKE :('%' + stage + '%')
                                                      AND Query_Type__c = :queryType
                                                      AND Query_Sub_Type__c != NULL
                                                      ORDER BY Query_Sub_Type__c ];
            
            // Get distinct subcategories
            Set<String> querySubTypeSet = new Set<String>();
            for (Query_Configuration__mdt config : configs) {
                querySubTypeSet.add(config.Query_Sub_Type__c);
            }
            
            List<String> querySubTypes = new List<String>(querySubTypeSet);
            querySubTypes.sort();
            return querySubTypes;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching query sub types: ' + ex.getMessage());
        }
    }
    
    /**
     * @description Gets description from Query_Configuration__mdt based on query type and query sub type
     * @param applicationId Application Id
     * @param queryType Selected query type
     * @param querySubType Selected query sub type
     * @return String Description text
     */
    @AuraEnabled(cacheable=true)
    public static String getQueryDescription(String applicationId, String queryType, String querySubType) {
        try {
            String queryDescription = '';
            // Get the application stage
            List<Application__c> applicationList = [SELECT Stage__c FROM Application__c WHERE Id =: applicationId LIMIT 1];
            if(applicationList != NULL && !applicationList.isEmpty()) {
                String stage = applicationList[0].Stage__c;
                
                // Query Query_Configuration__mdt to get description based on application stage, query type and query sub type
                List<Query_Configuration__mdt> configs = [SELECT Standard_Remarks__c 
                                                          FROM Query_Configuration__mdt 
                                                          WHERE Stage__c LIKE :('%' + stage + '%')
                                                          AND Query_Type__c =: queryType
                                                          AND Query_Sub_Type__c =: querySubType
                                                          LIMIT 1];
                
                if (!configs.isEmpty()) {
                    queryDescription = configs[0].Standard_Remarks__c;
                }
            }
            return queryDescription;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching query description: ' + ex.getMessage());
        }
    }
    
    /**
     * @description Gets applicant document checklists (when applicant is selected)
     * Document_Checklist__c has Applicant__c lookup to Applicant
     * @param applicantId Applicant Id
     * @return List<Map<String,String>> List of {value: Id, label: Name}
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getApplicantDocumentChecklists(String applicantId) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            List<Document_Checklist__c> checklists = [
                SELECT Id, Name
                FROM Document_Checklist__c
                WHERE Applicant__c =: applicantId
                ORDER BY Id
            ];
            for (Document_Checklist__c dc : checklists) {
                options.add(new Map<String, String>{
                    'value' => dc.Id,
                    'label' => dc.Name != null ? dc.Name : dc.Id
                });
            }
            return options;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching document checklists: ' + ex.getMessage());
        }
    }

    /**
     * @description Gets document checklists (when application is selected)
     * Document_Checklist__c has Application__c lookup to Application
     * @param applicationId Application Id
     * @return List<Map<String,String>> List of {value: Id, label: Name}
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getApplicationDocumentChecklists(String applicationId) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            List<Document_Checklist__c> checklists = [
                SELECT Id, Name
                FROM Document_Checklist__c
                WHERE Application__c =: applicationId
                ORDER BY Id
            ];
            for (Document_Checklist__c dc : checklists) {
                options.add(new Map<String, String>{
                    'value' => dc.Id,
                    'label' => dc.Name != null ? dc.Name : dc.Id
                });
            }
            return options;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching document checklists: ' + ex.getMessage());
        }
    }


    /**
     * @description Gets users who acted on the application from Application history
     * @param applicationId Application Id
     * @return List<UserDetailsWrapper> User details
     */
    @AuraEnabled(cacheable=true)
    public static List<UserDetailsWrapper> getApplicationUsers(String applicationId) {
        try {
            Set<Id> userIds = new Set<Id>();
            Id currentUserId = UserInfo.getUserId();
            Id ownerId = [SELECT Id, OwnerId FROM Application__c WHERE Id =: applicationId LIMIT 1].OwnerId;
            for (Application__History historyRow : [
                SELECT CreatedById
                FROM Application__History
                WHERE ParentId = :applicationId
                AND Field = 'Stage__c'
            ])
            {
                userIds.add(historyRow.CreatedById);
            }
            if(!userIds.contains(ownerId)) {
                userIds.add(ownerId);
            }

            List<UserDetailsWrapper> userWrappers = new List<UserDetailsWrapper>();
            if(!userIds.isEmpty())
            {
                for (User userRecord : [
                    SELECT Id, Name, Email, Persona__c, Manager.Name, Product__c
                    FROM User
                    WHERE Id IN :userIds
                    AND IsActive = true
                    AND Profile.Name NOT IN ('Integration User - API Only', 'Integration User')
                    ORDER BY Name
                ]) {
                userWrappers.add(
                    new UserDetailsWrapper(
                        userRecord.Id,
                        userRecord.Name,
                        userRecord.Email,
                        userRecord.Persona__c,
                        userRecord.Manager != NULL ? userRecord.Manager.Name : NULL,
                        userRecord.Product__c,
                        userRecord.Id == currentUserId
                        )
                    );
                }
            }
            return userWrappers;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching application users: ' + ex.getMessage());
        }
    }

    /**
     * @description Creates a query
     * @param queryData Query data
     * @return Id Query Id
     */
    @AuraEnabled
    public static QueryWrapper createQuery(Map<String, Object> queryData) {
        try {
            QueryWrapper qryWrapper = NULL;
            Query__c query = new Query__c();
            query.Status__c = 'Open';
            query.Application__c = (String) queryData.get('Application__c');
            query.Description__c = (String) queryData.get('Description__c');
            query.Query_Type__c = (String) queryData.get('Query_Type__c');
            query.Query_Sub_Type__c = (String) queryData.get('Query_Sub_Type__c');
            query.Assigned_To__c = (String) queryData.get('Assigned_To__c');
            query.Priority__c = (String) queryData.get('Priority__c');
            query.Applicant__c = (String) queryData.get('Applicant__c');
            query.Document_Checklist__c = (String) queryData.get('Document_Checklist__c');
            query.Subject__c = buildQuerySubject(query.Query_Type__c, query.Query_Sub_Type__c);
            if(queryData.get('Application_Line_Items__c') != null) {
                query.Application_Line_Items__c = (String) queryData.get('Application_Line_Items__c');
            }
            if(queryData.get('Asset__c') != NULL) {
                query.Asset__c = (String) queryData.get('Asset__c');
            }
            insert query;
            List<Query__c> queryList = [SELECT Id, Name FROM Query__c WHERE Id =: query.Id LIMIT 1];
            if(queryList != NULL && !queryList.isEmpty()) {
                qryWrapper = new QueryWrapper(queryList[0].Id, queryList[0].Name);
            }
            return qryWrapper;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error creating query: ' + ex.getMessage());
        }
    }

    private static String buildQuerySubject(String primary, String secondary) {
        String first = String.isNotBlank(primary) ? primary.trim() : '';
        String second = String.isNotBlank(secondary) ? secondary.trim() : '';
        if (String.isNotBlank(first) && String.isNotBlank(second)) {
            return first + ' - ' + second;
        }
        if (String.isNotBlank(first)) return first;
        if (String.isNotBlank(second)) return second;
        return 'Query';
    }

    /**
     * @description Gets all active users
     * @return List<UserDetailsWrapper> User details
     */
    @AuraEnabled(cacheable=true)
    public static List<UserDetailsWrapper> getAllUsers() {
        try {
            List<UserDetailsWrapper> userWrappers = new List<UserDetailsWrapper>();
            Id currentUserId = UserInfo.getUserId();
            for (User userRecord : [
                SELECT Id, Name, Email, Persona__c, Manager.Name, Product__c
                FROM User
                WHERE IsActive = true
                AND Persona__c != NULL
                AND Product__c != NULL
                AND ManagerId != NULL
                ORDER BY Name
            ])
            {
                userWrappers.add(
                    new UserDetailsWrapper(
                        userRecord.Id,
                        userRecord.Name,
                        userRecord.Email,
                        userRecord.Persona__c,
                        userRecord.Manager != NULL ? userRecord.Manager.Name : NULL,
                        userRecord.Product__c,
                        userRecord.Id == currentUserId
                    )
                );
            }
            return userWrappers;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching all users: ' + ex.getMessage());
        }
    }

    /**
     * @description Deletes a file from a query
     * @param contentDocumentId Content Document Id
     * @param queryId Query Id
     * @return void
     */
    @AuraEnabled
    public static void deleteFile(String contentDocumentId, String queryId) {
        try {
            List<ContentDocumentLink> contentDocumentLinks = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId =: contentDocumentId AND LinkedEntityId =: queryId LIMIT 1];
            if(contentDocumentLinks != NULL && !contentDocumentLinks.isEmpty()) {
                delete contentDocumentLinks;
            }
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error deleting file: ' + ex.getMessage());
        }
    }

    public class ParentWrapper {
        @AuraEnabled
        public String applicationId;
        @AuraEnabled
        public String applicantId;
        @AuraEnabled
        public String applicantName;
        @AuraEnabled
        public String applicationLineItemId;
        @AuraEnabled
        public String parentId;
        @AuraEnabled
        public String parentType;
        
        public ParentWrapper(String applicationId, String applicationLineItemId, String parentId, String parentType) {
            this.applicationId = applicationId;
            this.applicationLineItemId = applicationLineItemId;
            this.parentId = parentId;
            this.parentType = parentType;
        }
    }

    public class QueryWrapper {
        @AuraEnabled
        public String queryId;
        @AuraEnabled
        public String queryNumber;
        public QueryWrapper(String queryId, String queryNumber) {
            this.queryId = queryId;
            this.queryNumber = queryNumber;
        }
    }

    public class UserDetailsWrapper {
        @AuraEnabled
        public String userId;
        @AuraEnabled
        public String userName;
        @AuraEnabled
        public String userEmail;
        @AuraEnabled
        public String userPersona;
        @AuraEnabled
        public String managerName;
        @AuraEnabled
        public String product;
        @AuraEnabled
        public Boolean isCurrentUser;

        public UserDetailsWrapper(
            Id userId,
            String userName,
            String userEmail,
            String userPersona,
            String managerName,
            String product,
            Boolean isCurrentUser
        )
        {
            this.userId = (String) userId;
            this.userName = userName;
            this.userEmail = userEmail;
            this.userPersona = userPersona;
            this.managerName = managerName;
            this.product = product;
            this.isCurrentUser = isCurrentUser;
        }
    }
}