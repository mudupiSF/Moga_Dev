/* Description: This class is used to get the data for the overall loan dashboard.
* Author: Salesforce
*/
public class OverallLoanDashboardController {

    /* Description: This method is used to get the data for the overall loan dashboard.
    * Author: Salesforce
    * Parameters: soql - The SOQL query to execute
    * Returns: DashboardWrapper - A wrapper object containing the data and report
    */
    @AuraEnabled(cacheable=true)
    public static DashboardWrapper getData(String soql) {
        /*
		Logged in user - Take Products 
		Go to persona to stage Mapping
		*/
        try {
            DateTime currentDateTime = DateTime.now();
            // AggregateResult[] dataList = Database.query(String.escapeSingleQuotes(soql));
            AggregateResult[] dataList = Database.query(soql);
            Report report = new Report();
            DashboardWrapper dw = new DashboardWrapper(dataList,report);
            return dw;
        }
        catch(Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /* Description: This method is used to get the records for the overall loan dashboard.
    * Author: Salesforce
    * Parameters: soql - The SOQL query to execute
    * Returns: List<SObject> - A list of records
    */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getRecords(String soql) {
        try {
            // Execute the query and return actual records (not aggregated)
            List<SObject> records = Database.query(soql);
            return records;
        }
        catch(Exception e) {
            throw new AuraHandledException('Error fetching records: ' + e.getMessage());
        }
    }
    
    /* Description: This method is used to get the dashboard configurations for the overall loan dashboard.
    * Author: Salesforce
    * Parameters: widgetTab - The widget area to filter by
    * Returns: List<DashboardConfig> - A list of dashboard configurations
    */
    @AuraEnabled(cacheable=true)
    public static List<DashboardConfig> getDashboardConfigurations(String widgetTab) {
        try {
            // Get logged-in user's Persona
            Id userId = UserInfo.getUserId();
            User currentUser = [
                SELECT Id, Persona__c, Product__c 
                FROM User 
                WHERE Id = :userId 
                LIMIT 1
            ];
            List<DashboardConfig> configs = new List<DashboardConfig>();
            List<Dashboard_Configuration__c> configRecords;
            Map<String, String> reportDevIdMap = new Map<String, String>();
            Set<String> reportDevNameSet = new Set<String>();
            
            // Simple query - filter by WidgetArea if provided, otherwise return all
            if (String.isNotBlank(widgetTab)) {
                configRecords = [
                    SELECT Id, Name, SOQL_Query__c, Report_Description__c, 
                    Report_Label__c, Color__c, sObjectType__c, List_View_Developer_Name__c,
                    Layout_Item_Size__c, Order__c, Persona__c, Widget_Area__c,
                    Query_Type__c, Report_Developer_Name__c
                    FROM Dashboard_Configuration__c 
                    WHERE Active__c = true 
                    AND (Persona__c = :currentUser.Persona__c or Persona__c = null)
                    AND Widget_Area__c = :widgetTab
                    ORDER BY Order__c ASC NULLS LAST, Name ASC
                ];
            }
            else {
                configRecords = [
                    SELECT Id, Name, SOQL_Query__c, Report_Description__c, 
                    Report_Label__c, Color__c, sObjectType__c, List_View_Developer_Name__c,
                    Layout_Item_Size__c, Order__c, Persona__c, Widget_Area__c,
                    Query_Type__c, Report_Developer_Name__c
                    FROM Dashboard_Configuration__c 
                    WHERE Active__c = true 
                    AND Persona__c = :currentUser.Persona__c
                    ORDER BY Order__c ASC NULLS LAST, Name ASC
                ];
            }
            // Build map of report developer name to ID
            for(Dashboard_Configuration__c record : configRecords) {
                reportDevNameSet.add(record.Report_Developer_Name__c);
            }
            // Build map of report developer name to ID
            for(Report record : [SELECT Id, DeveloperName FROM Report WHERE DeveloperName IN :reportDevNameSet]) {
                reportDevIdMap.put(record.DeveloperName, record.Id);
            }
            for(Dashboard_Configuration__c record : configRecords) {
                DashboardConfig config = new DashboardConfig();
                config.id = record.Id;
                config.name = record.Name;
                
                // Process dynamic query replacements
                String processedQuery = processDynamicQuery(record.SOQL_Query__c, currentUser);
                config.soql = processedQuery;
                config.reportDescription = record.Report_Description__c;
                config.reportLabel = record.Report_Label__c;
                config.color = record.Color__c;
                config.reportId = reportDevIdMap.get(record.Report_Developer_Name__c);
                config.layoutItemSize = String.valueOf(record.Layout_Item_Size__c);
                config.isCommunityContext = isCommunityUser();
                config.queryType = record.Query_Type__c;
                config.sObjectType = record.sObjectType__c;
                config.developerName = record.List_View_Developer_Name__c;
                
                configs.add(config);
            }
            
            return configs;
        }
        catch(Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
    /* Description: This method is used to check if the current user is in a community context.
    * Author: Salesforce
    * Returns: Boolean - True if the current user is in a community context, false otherwise
    */
    private static Boolean isCommunityUser() {
        try {
            // Check if Site.getSiteId() returns a value (indicates community context)
            Id siteId = Site.getSiteId();
            return siteId != null;
        }
        catch (Exception e) {
            // If Site class is not available or throws exception, assume internal user
            return false;
        }
    }
    
    /* Description: This method is used to process dynamic merge fields in a query.
    * Author: Salesforce
    * Parameters: query - The query to process
    * Parameters: currentUser - The current user
    * Returns: String - The processed query
    */
    private static String processDynamicQuery(String query, User currentUser) {
        if (String.isBlank(query)) {
            return query;
        }
        
        String processedQuery = query;
        
        // Replace replaceWithuserProductRecordTypeMapings
        if (processedQuery.contains('replaceWithuserProductRecordTypeMapings')) {
            String recordTypes = getRecordTypesForUserProducts(currentUser.Product__c);
            processedQuery = processedQuery.replace('replaceWithuserProductRecordTypeMapings', recordTypes);
        }
        
        // Replace replaceWithOwnerids
        if (processedQuery.contains('replaceWithOwnerids')) {
            String ownerIds = getAllReportingUserIds(currentUser.Id);
            processedQuery = processedQuery.replace('replaceWithOwnerids', ownerIds);
        }
        
        // Replace replaceWithOwnerids
        if (processedQuery.contains('loggedInUserId')) {
            processedQuery = processedQuery.replace('loggedInUserId', currentUser.Id);
        }
        
        //SELECT Count(Id) value FROM Case where isClosed= false AND ownerId = :loggedInUserId
        
        return processedQuery;
    }
    
    /* Description: This method is used to get the record types from metadata based on the user's products.
    * Author: Salesforce
    * Parameters: userProducts - The user's products
    * Returns: String - The record types
    */
    private static String getRecordTypesForUserProducts(String userProducts) {
        if (String.isBlank(userProducts)) {
            return '\'\'';
        }
        
        // Parse products - handle multiple separators (semicolon, comma, colon)
        // Replace all possible separators with semicolon first
        String normalizedProducts = userProducts.replace(',', ';').replace(':', ';');
        List<String> productsList = normalizedProducts.split(';');
        
        // Trim and collect unique products
        Set<String> products = new Set<String>();
        for (String product : productsList) {
            String trimmedProduct = product.trim();
            if (String.isNotBlank(trimmedProduct)) {
                products.add(trimmedProduct);
            }
        }
        
        if (products.isEmpty()) {
            return '\'\'';
        }
        
        Set<String> recordTypeSet = new Set<String>();
        
        // Query existing metadata for product to record type mappings
        List<User_Product_Record_Tyoe_Mapping__mdt> mappings = [
            SELECT Product__c, RecordTypeName__c 
            FROM User_Product_Record_Tyoe_Mapping__mdt 
            WHERE Product__c IN :products
        ];
        
        for (User_Product_Record_Tyoe_Mapping__mdt mapping : mappings) {
            recordTypeSet.add(mapping.RecordTypeName__c);
        }
        
        // Build comma-separated quoted string for SOQL IN clause
        List<String> recordTypeList = new List<String>(recordTypeSet);
        if (recordTypeList.isEmpty()) {
            return '\'\'';
        }
        
        String result = '\'';
        for (Integer i = 0; i < recordTypeList.size(); i++) {
            result += recordTypeList[i];
            if (i < recordTypeList.size() - 1) {
                result += '\',\'';
            }
        }
        result += '\'';
        
        return result;
    }
    
    /* Description: This method is used to get all user IDs reporting to the current user (recursively).
    * Author: Salesforce
    * Parameters: managerId - The manager ID
    * Returns: String - The user IDs
    */
    private static String getAllReportingUserIds(Id managerId) {
        Set<Id> allReportingUsers = new Set<Id>();
        Set<Id> processedManagers = new Set<Id>();
        
        // Add the manager itself
        allReportingUsers.add(managerId);
        
        // Get all reporting users recursively
        getReportingUsersRecursive(managerId, allReportingUsers, processedManagers);
        
        // Build comma-separated quoted string for SOQL IN clause
        List<Id> userIdList = new List<Id>(allReportingUsers);
        if (userIdList.isEmpty()) {
            return '\'\'';
        }
        
        String result = '\'';
        for (Integer i = 0; i < userIdList.size(); i++) {
            result += userIdList[i];
            if (i < userIdList.size() - 1) {
                result += '\',\'';
            }
        }
        result += '\'';
        
        return result;
    }
    
    /* Description: This method is used to get all reporting users recursively.
    * Author: Salesforce
    * Parameters: managerId - The manager ID
    * Parameters: allReportingUsers - The set of all reporting users
    * Parameters: processedManagers - The set of processed managers
    */
    private static void getReportingUsersRecursive(Id managerId, Set<Id> allReportingUsers, Set<Id> processedManagers) {
        // Prevent infinite loops
        if (processedManagers.contains(managerId)) {
            return;
        }
        processedManagers.add(managerId);
        
        // Query direct reports
        List<User> directReports = [
            SELECT Id, ManagerId 
            FROM User 
            WHERE ManagerId = :managerId 
            AND IsActive = true
        ];
        
        for (User user : directReports) {
            allReportingUsers.add(user.Id);
            // Recursively get their reports
            getReportingUsersRecursive(user.Id, allReportingUsers, processedManagers);
        }
    }
    
    /* Description: This class is used to wrap the data and report for the overall loan dashboard.
    * Author: Salesforce
    * Parameters: data - The data
    * Parameters: report - The report
    */
    public class DashboardWrapper {
        @AuraEnabled
        public List<Object> data;
        @AuraEnabled
        public Report report;
        DashboardWrapper(List<Object> data,Report report){
            this.data = data;
            this.report = report;
        }
    }
    
    public class DashboardConfig {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String soql;
        @AuraEnabled
        public String reportDescription;
        @AuraEnabled
        public String reportLabel;
        @AuraEnabled
        public String color;
        @AuraEnabled
        public String reportId;
        @AuraEnabled
        public String layoutItemSize;
        @AuraEnabled
        public Boolean isCommunityContext;
        @AuraEnabled
        public String queryType;
        @AuraEnabled
        public String sObjectType;
        @AuraEnabled
        public String developerName;
    }
}