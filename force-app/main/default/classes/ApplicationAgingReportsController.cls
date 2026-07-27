public with sharing class ApplicationAgingReportsController {

    // Maximum manager levels to traverse when using direct traversal
    // Level 1: Direct reports (User.ManagerId)
    // Level 2: Reports 2 levels down (User.Manager.Manager.Id)
    // Level 3: Reports 3 levels down (User.Manager.Manager.Manager.Id)
    // ... and so on up to MAX_MANAGER_LEVELS
    private static final Integer MAX_MANAGER_LEVELS = 5;
    // Flag to use direct manager traversal (faster) or hierarchical query (slower)
    private static final Boolean USE_DIRECT_MANAGER_TRAVERSAL = true;

    // NEW: Lightweight method to get reporting user IDs only (called from frontend)
    @AuraEnabled(cacheable=false)
    public static ReportingUsersResponse getReportingUserIds() {
        try {
            Id userId = UserInfo.getUserId();
            
            User userObject = [Select Id, Profile.Name, Persona__c, Product__c from User where Id = :userId limit 1];
            
            // Check if user is a manager
            Boolean isManager = isUserAManager(userId);
            
            // Check if user should see investigations
            // Show if: Admin OR FCU Sampler OR FCU Manager
            Boolean isAdmin = userObject.Profile.Name.toUpperCase().contains('ADMIN');
            Boolean showInvestigations = isAdmin
                                        || userObject.Persona__c == 'FCU Sampler'
                                        || userObject.Persona__c == 'FCU Manager';

            // Extract default product from user's Product__c field
            // If multiple products (comma-separated), use the first one
            String defaultProduct = null;
            if (String.isNotBlank(userObject.Product__c)) {
                List<String> products = userObject.Product__c.split(',');
                if (!products.isEmpty()) {
                    defaultProduct = products[0].trim();
                }
            }
            
            ReportingUsersResponse response = new ReportingUsersResponse();
            response.isManager = isManager;
            response.showInvestigations = showInvestigations;
            response.currentUserId = userId;
            response.employeeUserIds = new List<Id>{ userId };
            response.isAdmin = isAdmin;
            response.defaultProduct = defaultProduct;
            
            // Get all reporting users if manager
            if (isManager) {
                Set<Id> allUserIds = getAllReportingUserIds(userId);
                response.managerUserIds = new List<Id>(allUserIds);
            }
            else {
                response.managerUserIds = new List<Id>();
            }
            return response;
        }
        catch(Exception e) {
            throw new AuraHandledException('Error getting reporting users: ' + e.getMessage());
        }
    }

    // Check if the user is a manager (has anyone reporting to them)
    private static Boolean isUserAManager(Id userId) {
        List<User> reportingUsers = [
            SELECT Id 
            FROM User 
            WHERE ManagerId = :userId 
            AND IsActive = true
            LIMIT 1
        ];
        return !reportingUsers.isEmpty();
    }

    // Get all users reporting to the given manager (including manager)
    private static Set<Id> getAllReportingUserIds(Id managerId) {
        if (USE_DIRECT_MANAGER_TRAVERSAL) {
            // NEW APPROACH: Use direct Manager relationship traversal (FASTER)
            return getAllReportingUserIdsDirectTraversal(managerId);
        }
        else {
            // OLD APPROACH: Use hierarchical query (queries all users)
            return getAllReportingUserIdsHierarchical(managerId);
        }
    }

    // Get all users reporting to the given manager (including manager) using direct manager relationship traversal
    private static Set<Id> getAllReportingUserIdsDirectTraversal(Id managerId) {
        Set<Id> allReportingUsers = new Set<Id>();
        
        // Add the manager itself
        allReportingUsers.add(managerId);
        
        // Build dynamic SOQL query to get all users who report up to this manager (up to MAX_MANAGER_LEVELS)
        // Example generated query for 5 levels:
        // SELECT Id, ManagerId, Manager.Manager.Id, Manager.Manager.Manager.Id, ...
        // FROM User 
        // WHERE IsActive = true AND (
        //   ManagerId = :managerId OR 
        //   Manager.Id = :managerId OR 
        //   Manager.Manager.Id = :managerId OR ...
        // )
        
        String soqlQuery = 'SELECT Id, ManagerId';
        List<String> selectFields = new List<String>();
        List<String> whereConditions = new List<String>();
        
        // Build SELECT and WHERE clauses for each manager level
        whereConditions.add('ManagerId = :managerId'); // Level 1: Direct reports
        
        for (Integer level = 2; level <= MAX_MANAGER_LEVELS; level++) {
            // Build Manager.Manager.Manager...Id path
            String managerPath = 'Manager';
            for (Integer i = 2; i <= level; i++) {
                managerPath += '.Manager';
            }
            
            // Add to SELECT clause (for reference, though we only need Id)
            selectFields.add(managerPath + '.Id');
            
            // Add to WHERE clause
            whereConditions.add(managerPath + '.Id = :managerId');
        }
        
        // Add SELECT fields
        if (!selectFields.isEmpty()) {
            soqlQuery += ', ' + String.join(selectFields, ', ');
        }
        
        // Add WHERE clause
        soqlQuery += ' FROM User WHERE IsActive = true AND (' + String.join(whereConditions, ' OR ') + ')';
        
        system.debug('=== DIRECT TRAVERSAL APPROACH ===');
        system.debug('SOQL Query: ' + soqlQuery);
        
        // Execute query
        List<User> reportingUsers = Database.query(soqlQuery);
        
        // Add all user IDs to the set
        for (User u : reportingUsers) {
            allReportingUsers.add(u.Id);
        }
        
        system.debug('Found ' + reportingUsers.size() + ' reporting users (excluding manager)');
        system.debug('Total user IDs (including manager): ' + allReportingUsers.size());
        
        return allReportingUsers;
    }

    @TestVisible
    private static Set<Id> getAllReportingUserIdsHierarchical(Id managerId) {
        Set<Id> allReportingUsers = new Set<Id>();
        Set<Id> processedManagers = new Set<Id>();
        
        // Add the manager itself
        allReportingUsers.add(managerId);
        
        system.debug('=== HIERARCHICAL QUERY APPROACH ===');
        system.debug('Querying ALL active users to build hierarchy...');
        
        // Get all reporting users recursively
        getReportingUsersRecursive(managerId, allReportingUsers, processedManagers);
        
        system.debug('Found ' + (allReportingUsers.size() - 1) + ' reporting users (excluding manager)');
        system.debug('Total user IDs (including manager): ' + allReportingUsers.size());
        
        return allReportingUsers;
    }

    // HIERARCHICAL APPROACH: Recursive method to get all reporting users - NO SOQL IN LOOPS
    @TestVisible
    private static void getReportingUsersRecursive(Id managerId, Set<Id> allReportingUsers, Set<Id> processedManagers) {
        // Prevent infinite loops
        if (processedManagers.contains(managerId)) {
            return;
        }
        
        processedManagers.add(managerId);
        
        // PERFORMANCE FIX: Query all active users once, then filter in memory
        // This prevents SOQL in loops which causes CPU timeouts
        if (processedManagers.size() == 1) {
            // First call - query all users once and store in static map for this transaction
            List<User> allActiveUsers = [
                SELECT Id, ManagerId
                FROM User 
                WHERE IsActive = true 
                AND ManagerId != null
                LIMIT 50000
            ];
            
            // Build hierarchy in memory
            Map<Id, List<Id>> managerToUsersMap = new Map<Id, List<Id>>();
            for (User u : allActiveUsers) {
                if (!managerToUsersMap.containsKey(u.ManagerId)) {
                    managerToUsersMap.put(u.ManagerId, new List<Id>());
                }
                managerToUsersMap.get(u.ManagerId).add(u.Id);
            }
            // Traverse hierarchy in memory (no more SOQL calls)
            traverseHierarchy(managerId, allReportingUsers, managerToUsersMap, new Set<Id>());
        }
    }

    // Helper method to traverse user hierarchy in memory (no SOQL)
    @TestVisible
    private static void traverseHierarchy(Id managerId, Set<Id> allUsers, Map<Id, List<Id>> managerToUsersMap, Set<Id> visited) {
        if (visited.contains(managerId)) {
            return;
        }
        visited.add(managerId);
        
        List<Id> directReports = managerToUsersMap.get(managerId);
        if (directReports != null) {
            for (Id userId : directReports) {
                allUsers.add(userId);
                traverseHierarchy(userId, allUsers, managerToUsersMap, visited);
            }
        }
    }

    // Wrapper class for reporting users response (returned by getReportingUserIds)
    public class ReportingUsersResponse {
        @AuraEnabled public Boolean isManager { get; set; }
        @AuraEnabled public Boolean showInvestigations { get; set; }
        @AuraEnabled public Boolean isAdmin { get; set; }
        @AuraEnabled public Id currentUserId { get; set; }
        @AuraEnabled public List<Id> employeeUserIds { get; set; }
        @AuraEnabled public List<Id> managerUserIds { get; set; }
        @AuraEnabled public String defaultProduct { get; set; } // Default product from user's Product__c field
    }
}