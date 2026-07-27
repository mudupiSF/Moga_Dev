public with sharing class CreateQueryModalController {
    
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
            String applicationId = '';
            if(objectName == 'Application_Line_Item__c') {
                List<Application_Line_Item__c> applicationLineItems = [SELECT Id, Application__c FROM Application_Line_Item__c WHERE Id =: recordId LIMIT 1];
                if(applicationLineItems != NULL && !applicationLineItems.isEmpty()) {
                    applicationId = applicationLineItems[0].Application__c;
                    parentWrapper = new ParentWrapper(applicationId, applicationLineItems[0].Id, recordId, objectName);
                }
            }
            else if(objectName == 'Asset__c') {
                List<Asset__c> assets = [SELECT Id, Application_Line_Items__c, Application_Line_Items__r.Application__c FROM Asset__c WHERE Id =: recordId LIMIT 1];
                if(assets != NULL && !assets.isEmpty()) {
                    applicationId = assets[0].Application_Line_Items__r.Application__c;
                    parentWrapper = new ParentWrapper(applicationId, assets[0].Application_Line_Items__c, recordId, objectName);
                }
            }
            return parentWrapper;
        }
        catch (Exception ex) {
            System.debug('Error fetching parent record: ' + ex.getMessage());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Error fetching parent record: ' + ex.getMessage());
        }
    }
    
    /**
     * @description Gets applicants for a loan application (for optional Applicant lookup on Case creation)
     * @param loanApplicationId ResidentialLoanApplication Id
     * @return List<Map<String,String>> List of {value: Id, label: Name}
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getApplicants(String applicationId) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();
            List<Applicant__c> applicants = [
                SELECT Id, Name
                FROM Applicant__c
                WHERE Application__c =: applicationId
                ORDER BY Id
            ];
            for (Applicant__c aplcnt : applicants) {
                options.add(new Map<String, String>{
                    'value' => aplcnt.Id,
                    'label' => aplcnt.Name != null ? aplcnt.Name : aplcnt.Id
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
     * @description Gets query sub types from Query_Configuration__mdt based on loan application stage and query type
     * @param loanApplicationId Loan Application Id
     * @param queryType Selected query type
     * @return List<String> List of distinct query sub types
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getQuerySubTypes(String applicationId, String queryType) {
        try {
            // Get the loan application stage
            Application__c application = [SELECT Stage__c FROM Application__c WHERE Id =: applicationId LIMIT 1];
            String stage = application.Stage__c;
            
            // Query Query_Configuration__mdt where Stage contains the loan application stage and Query Type matches
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
            // Get the loan application stage
            List<Application__c> applicationList = [SELECT Stage__c FROM Application__c WHERE Id =: applicationId LIMIT 1];
            if(applicationList != NULL && !applicationList.isEmpty()) {
                String stage = applicationList[0].Stage__c;
                
                // Query Query_Configuration__mdt to get description
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
     * @description Gets document checklists for an applicant (when applicant is selected)
     * Document_Checklist__c has axisltd_Loan_Applicant__c lookup to Loan Applicant
     * @param applicantId LoanApplicant Id
     * @return List<Map<String,String>> List of {value: Id, label: Name}
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getDocumentChecklistsForApplicant(String applicantId) {
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
     * @description Gets users who acted on the application from Application history
     * @param applicationId Application Id
     * @return List<UserDetailsWrapper> User details
     */
    @AuraEnabled(cacheable=true)
    public static List<UserDetailsWrapper> getApplicationUsers(String applicationId) {
        try {
            Set<Id> userIds = new Set<Id>();
            for (Application__History historyRow : [
                SELECT CreatedById
                FROM Application__History
                WHERE ParentId = :applicationId
                AND Field = 'Stage__c'
            ])
            {
                userIds.add(historyRow.CreatedById);
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
                        userRecord.Product__c
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
    public static Id createQuery(Map<String, Object> queryData) {
        try {
            Query__c query = new Query__c();
            query.Status__c = 'New';
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
            return query.Id;
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
                        userRecord.Product__c
                    )
                );
            }
            return userWrappers;
        }
        catch (Exception ex) {
            throw new AuraHandledException('Error fetching all users: ' + ex.getMessage());
        }
    }

    public class ParentWrapper {
        @AuraEnabled
        public String applicationId;
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

        public UserDetailsWrapper(
            Id userId,
            String userName,
            String userEmail,
            String userPersona,
            String managerName,
            String product
        )
        {
            this.userId = (String) userId;
            this.userName = userName;
            this.userEmail = userEmail;
            this.userPersona = userPersona;
            this.managerName = managerName;
            this.product = product;
        }
    }

}