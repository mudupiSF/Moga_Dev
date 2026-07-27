public with sharing class AdvancedAgingReportsController {

    // Maximum rows to fetch (configurable limit)
    private static final Integer MAX_ROWS = 1000;

    // Hard cap for total-count scan on first page request to stay within governor limits.
    // If matched records exceed this number, UI will display "10,000+" instead of exact total.
    private static final Integer COUNT_SCAN_THRESHOLD = 10000;
    
    // CONFIGURATION FLAG: Choose manager hierarchy retrieval method
    // TRUE = Use direct User.Manager relationship traversal (FASTER - up to 5 levels)
    // FALSE = Use hierarchical query approach (queries all users and builds hierarchy in memory)
    // TODO: Move this to Custom Metadata Type or Custom Setting for runtime configuration
    private static final Boolean USE_DIRECT_MANAGER_TRAVERSAL = true;
    
    // Maximum manager levels to traverse when using direct traversal
    // Level 1: Direct reports (User.ManagerId)
    // Level 2: Reports 2 levels down (User.Manager.Manager.Id)
    // Level 3: Reports 3 levels down (User.Manager.Manager.Manager.Id)
    // ... and so on up to MAX_MANAGER_LEVELS
    private static final Integer MAX_MANAGER_LEVELS = 5;
    
    // Open Investigation Statuses (using IN clause for better performance - indexes work with IN)
    private static final Set<String> OPEN_INVESTIGATION_STATUSES = new Set<String>{
        'FCU Initiation',
        'FCU Query',
        'FCU Screened Ok',
        'FCU Screened ok',
        'FCU Sampled Accept',
        'FCU Sampled Reject-Profile',
        'FCU Sampled Reject-Document',
        'FCU Sampled Credit Refer',
        'FCU Sampled-Verification',
        'FCU CPV',
        'FCU Final',
        'FCU Review',
        'Sampled',
        'Screened',
        'Refer to Credit'
    };
    
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
            Boolean showInvestigations = isAdmin || 
                                        userObject.Persona__c == 'FCU Sampler' || 
                                        userObject.Persona__c == 'FCU Manager';
            
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
            } else {
                response.managerUserIds = new List<Id>();
            }
            
            return response;
            
        } catch(Exception e) {
            system.debug('Error in getReportingUserIds: ' + e.getMessage());
            system.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error getting reporting users: ' + e.getMessage());
        }
    }
    
    // Get all available products (RecordType names) for the product filter dropdown
    /*@AuraEnabled(cacheable=true)
    public static List<String> getAllProducts() {
        try {
            Set<String> products = new Set<String>();
            
            // Query all distinct RecordType names from Application__c
            List<AggregateResult> results = [
                SELECT RecordType.Name productName
                FROM Application__c
                WHERE Application_Closed__c = false
                AND RecordType.Name != null
                GROUP BY RecordType.Name
                ORDER BY RecordType.Name
            ];
            
            for (AggregateResult ar : results) {
                String productName = (String)ar.get('productName');
                if (String.isNotBlank(productName)) {
                    products.add(productName);
                }
            }
            
            return new List<String>(products);
            
        } catch(Exception e) {
            system.debug('Error in getAllProducts: ' + e.getMessage());
            throw new AuraHandledException('Error getting products: ' + e.getMessage());
        }
    }*/
    
    // Cursor-based chunk API for application tabs with all filters server-side.
    // cursorDirection: 'forward' (default) walks toward older records (Next).
    //                  'backward' walks toward newer records (Previous), or fetches the
    //                  oldest page when no cursor is supplied (Last button).
    @AuraEnabled(cacheable=false)
    public static ApplicationChunkResponse getApplicationAgingChunk(
        List<Id> userIds,
        String viewType,
        Boolean showApplicationsIOwn,
        String productFilter,
        String createdDateFilter,
        String stageFilter,
        String regionFilter,
        String applicationAgeFilter,
        String lastStatusAgeFilter,
        String managerFilter,
        String ownerFilter,
        Integer pageSize,
        DateTime cursorCreatedDate,
        Id cursorId,
        String cursorDirection
    ) {
        if (pageSize == null || pageSize <= 0) {
            pageSize = 1000;
        }
        if (showApplicationsIOwn == null) {
            showApplicationsIOwn = true;
        }
        Boolean isBackward = (cursorDirection == 'backward');

        Set<Id> userIdsSet = new Set<Id>(userIds);
        ApplicationChunkResponse response = new ApplicationChunkResponse();
        // Only compute total count on the first fresh forward fetch.
        // Backward fetches (Previous / Last) always reuse the client's existing total.
        if (!isBackward && cursorCreatedDate == null && cursorId == null) {
            countApplicationAgingRecords(
                userIdsSet,
                viewType,
                showApplicationsIOwn,
                productFilter,
                createdDateFilter,
                stageFilter,
                regionFilter,
                applicationAgeFilter,
                lastStatusAgeFilter,
                managerFilter,
                ownerFilter,
                response
            );
        }
        response.records = getApplicationAgingChunkData(
            userIdsSet,
            pageSize,
            viewType,
            showApplicationsIOwn,
            productFilter,
            createdDateFilter,
            stageFilter,
            regionFilter,
            applicationAgeFilter,
            lastStatusAgeFilter,
            managerFilter,
            ownerFilter,
            cursorCreatedDate,
            cursorId,
            isBackward,
            response
        );
        return response;
    }
    
    // cursorDirection: 'forward' (default) walks toward older records (Next).
    //                  'backward' walks toward newer records (Previous), or fetches the
    //                  oldest page when no cursor is supplied (Last button).
    @AuraEnabled(cacheable=false)
    public static InvestigationChunkResponse getInvestigationAgingChunk(
        List<Id> userIds,
        Boolean isAdmin,
        String statusFilter,
        String productFilter,
        String regionFilter,
        String investigationAgeFilter,
        String lastStatusAgeFilter,
        String managerFilter,
        String ownerFilter,
        Integer pageSize,
        DateTime cursorCreatedDate,
        Id cursorId,
        String cursorDirection
    ) {
        if (pageSize == null || pageSize <= 0) {
            pageSize = 1000;
        }
        if (isAdmin == null) {
            isAdmin = false;
        }
        Boolean isBackward = (cursorDirection == 'backward');

        InvestigationChunkResponse response = new InvestigationChunkResponse();
        // Only compute total count on the first fresh forward fetch.
        if (!isBackward && cursorCreatedDate == null && cursorId == null) {
            countInvestigationRecords(
                new Set<Id>(userIds),
                isAdmin,
                statusFilter,
                productFilter,
                regionFilter,
                investigationAgeFilter,
                lastStatusAgeFilter,
                managerFilter,
                ownerFilter,
                response
            );
        }
        response.records = getInvestigationChunkData(
            new Set<Id>(userIds),
            isAdmin,
            statusFilter,
            productFilter,
            regionFilter,
            investigationAgeFilter,
            lastStatusAgeFilter,
            managerFilter,
            ownerFilter,
            pageSize,
            cursorCreatedDate,
            cursorId,
            isBackward,
            response
        );
        return response;
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
    
    // Computes exact total count for the application aging dashboard using a SINGLE SOQL.
    // Trims SELECT to only fields needed for derived (Apex-side) filters.
    // Hard-caps the scan at COUNT_SCAN_THRESHOLD; if exceeded, sets countExceedsThreshold = true
    // and totalCount to the threshold so UI can display "10,000+" style indicator.
    private static void countApplicationAgingRecords(
        Set<Id> userIds,
        String viewType,
        Boolean showApplicationsIOwn,
        String productFilter,
        String createdDateFilter,
        String stageFilter,
        String regionFilter,
        String applicationAgeFilter,
        String lastStatusAgeFilter,
        String managerFilter,
        String ownerFilter,
        ApplicationChunkResponse response
    ) {
        Id currentUserId = UserInfo.getUserId();
        Set<Id> subordinateUserIds = new Set<Id>(userIds);
        subordinateUserIds.remove(currentUserId);

        if (String.isBlank(createdDateFilter)) {
            createdDateFilter = '<30';
        }

        if (viewType == 'manager' && showApplicationsIOwn == true && subordinateUserIds.isEmpty()) {
            response.totalCount = 0;
            response.countExceedsThreshold = false;
            return;
        }

        DateTime date30DaysAgo = DateTime.now().addDays(-30);
        DateTime date60DaysAgo = DateTime.now().addDays(-60);
        DateTime date90DaysAgo = DateTime.now().addDays(-90);
        Integer scanLimit = COUNT_SCAN_THRESHOLD + 1;

        // Trimmed SELECT - only fields needed for derived (Apex-side) filters
        String soql = 'SELECT Id, CreatedDate, LastModifiedDate, ' +
                      'OwnerId ' +
                      'FROM Application__c ' +
                      'WHERE Is_Application_Closed__c = false';

        if (String.isNotBlank(productFilter)) {
            soql += ' AND Product__c = :productFilter';
        }
        if (String.isNotBlank(stageFilter)) {
            soql += ' AND Stage__c = :stageFilter';
        }
        if (String.isNotBlank(ownerFilter)) {
            soql += ' AND Owner.Name = :ownerFilter';
        }

        if (viewType == 'employee') {
            if (showApplicationsIOwn == true) {
                soql += ' AND OwnerId = :currentUserId';
            } else if (!subordinateUserIds.isEmpty()) {
                soql += ' AND OwnerId != :currentUserId AND OwnerId NOT IN :subordinateUserIds';
            } else {
                soql += ' AND OwnerId != :currentUserId';
            }
        } else if (viewType == 'manager') {
            if (showApplicationsIOwn == true) {
                soql += ' AND OwnerId IN :subordinateUserIds';
            } else if (!subordinateUserIds.isEmpty()) {
                soql += ' AND OwnerId != :currentUserId AND OwnerId NOT IN :subordinateUserIds';
            } else {
                soql += ' AND OwnerId != :currentUserId';
            }
        }

        if (createdDateFilter == '<30') {
            soql += ' AND CreatedDate >= LAST_N_DAYS:30';
        } else if (createdDateFilter == '30-60') {
            soql += ' AND CreatedDate >= :date60DaysAgo AND CreatedDate < :date30DaysAgo';
        } else if (createdDateFilter == '60-90') {
            soql += ' AND CreatedDate >= :date90DaysAgo AND CreatedDate < :date60DaysAgo';
        } else if (createdDateFilter == '>90') {
            soql += ' AND CreatedDate < :date90DaysAgo';
        } else {
            soql += ' AND CreatedDate >= LAST_N_DAYS:30';
        }

        soql += ' LIMIT :scanLimit';

        List<Application__c> applications = Database.query(soql);
        Boolean exceedsThreshold = (applications.size() > COUNT_SCAN_THRESHOLD);

        Boolean needsManagerLookup = String.isNotBlank(managerFilter);
        Boolean needsAgeFilter = String.isNotBlank(applicationAgeFilter) || String.isNotBlank(lastStatusAgeFilter);

        if (!needsManagerLookup && !needsAgeFilter) {
            response.totalCount = exceedsThreshold ? COUNT_SCAN_THRESHOLD : applications.size();
            response.countExceedsThreshold = exceedsThreshold;
            return;
        }

        Map<Id, User> ownerUsersMap = new Map<Id, User>();
        if (needsManagerLookup) {
            Set<Id> ownerUserIds = new Set<Id>();
            for (Application__c application : applications) {
                if (application.OwnerId != null && String.valueOf(application.OwnerId).startsWith('005')) {
                    ownerUserIds.add(application.OwnerId);
                }
            }
            if (!ownerUserIds.isEmpty()) {
                for (User u : [SELECT Id, Manager.Name FROM User WHERE Id IN :ownerUserIds]) {
                    ownerUsersMap.put(u.Id, u);
                }
            }
        }

        Integer count = 0;
        Integer scanned = 0;
        for (Application__c application : applications) {
            scanned++;
            if (scanned > COUNT_SCAN_THRESHOLD) {
                break;
            }

            if (needsManagerLookup) {
                User ownerUser = ownerUsersMap.get(application.OwnerId);
                String mgrName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
                if (mgrName != managerFilter) {
                    continue;
                }
            }

            if (needsAgeFilter) {
                DateTime stageChangeDate = application.LastModifiedDate;
                Decimal applicationTotalTATInDays;
                Decimal lastStatusTATInDays;
                applicationTotalTATInDays = calculateCalendarHoursAging(application.CreatedDate) / 24.0;
                lastStatusTATInDays = calculateCalendarHoursAging(stageChangeDate) / 24.0;
                if (!isInAgeRangeApex(applicationTotalTATInDays, applicationAgeFilter)) {
                    continue;
                }
                if (!isInAgeRangeApex(lastStatusTATInDays, lastStatusAgeFilter)) {
                    continue;
                }
            }

            count++;
        }

        response.totalCount = count;
        response.countExceedsThreshold = exceedsThreshold;
    }

    private static List<ApplicationAgingResult> getApplicationAgingChunkData(
        Set<Id> userIds,
        Integer pageSize,
        String viewType,
        Boolean showApplicationsIOwn,
        String productFilter,
        String createdDateFilter,
        String stageFilter,
        String regionFilter,
        String applicationAgeFilter,
        String lastStatusAgeFilter,
        String managerFilter,
        String ownerFilter,
        DateTime cursorCreatedDate,
        Id cursorId,
        Boolean isBackward,
        ApplicationChunkResponse response
    ) {
        Id currentUserId = UserInfo.getUserId();
        Set<Id> subordinateUserIds = new Set<Id>(userIds);
        subordinateUserIds.remove(currentUserId);

        if (String.isBlank(createdDateFilter)) {
            createdDateFilter = '<30';
        }

        Integer batchSize = Math.min(1000, Math.max(200, pageSize));
        List<ApplicationAgingResult> finalResults = new List<ApplicationAgingResult>();
        DateTime queryCursorCreatedDate = cursorCreatedDate;
        Id queryCursorId = cursorId;

        // Backward walks ASC (toward newer records); forward walks DESC (toward older records).
        // After a backward walk we reverse finalResults so the caller always sees DESC display order.
        String orderClause = isBackward
            ? ' ORDER BY CreatedDate ASC, Id ASC LIMIT :batchSize'
            : ' ORDER BY CreatedDate DESC, Id DESC LIMIT :batchSize';

        while (finalResults.size() < pageSize) {
            String baseQuery = 'SELECT Id, Name, Stage__c, CreatedDate, LastModifiedDate, ' +
                              'OwnerId, Owner.Name, ' +
                              'Product__c ' +
                              'FROM Application__c ' +
                              'WHERE Is_Application_Closed__c = false';

            if (String.isNotBlank(productFilter)) {
                baseQuery += ' AND Product__c = :productFilter';
            }
            if (String.isNotBlank(stageFilter)) {
                baseQuery += ' AND Stage__c = :stageFilter';
            }
            if (String.isNotBlank(ownerFilter)) {
                baseQuery += ' AND Owner.Name = :ownerFilter';
            }

            if (viewType == 'employee') {
                if (showApplicationsIOwn == true) {
                    baseQuery += ' AND OwnerId = :currentUserId';
                } else {
                    if (!subordinateUserIds.isEmpty()) {
                        baseQuery += ' AND OwnerId != :currentUserId AND OwnerId NOT IN :subordinateUserIds';
                    } else {
                        baseQuery += ' AND OwnerId != :currentUserId';
                    }
                }
            } else if (viewType == 'manager') {
                if (showApplicationsIOwn == true) {
                    if (subordinateUserIds.isEmpty()) {
                        response.hasMore = false;
                        response.nextCursorCreatedDate = null;
                        response.nextCursorId = null;
                        return finalResults;
                    }
                    baseQuery += ' AND OwnerId IN :subordinateUserIds';
                } else {
                    if (!subordinateUserIds.isEmpty()) {
                        baseQuery += ' AND OwnerId != :currentUserId AND OwnerId NOT IN :subordinateUserIds';
                    } else {
                        baseQuery += ' AND OwnerId != :currentUserId';
                    }
                }
            }

            DateTime date30DaysAgo = DateTime.now().addDays(-30);
            DateTime date60DaysAgo = DateTime.now().addDays(-60);
            DateTime date90DaysAgo = DateTime.now().addDays(-90);
            if (createdDateFilter == '<30') {
                baseQuery += ' AND CreatedDate >= LAST_N_DAYS:30';
            } else if (createdDateFilter == '30-60') {
                baseQuery += ' AND CreatedDate >= :date60DaysAgo AND CreatedDate < :date30DaysAgo';
            } else if (createdDateFilter == '60-90') {
                baseQuery += ' AND CreatedDate >= :date90DaysAgo AND CreatedDate < :date60DaysAgo';
            } else if (createdDateFilter == '>90') {
                baseQuery += ' AND CreatedDate < :date90DaysAgo';
            } else {
                baseQuery += ' AND CreatedDate >= LAST_N_DAYS:30';
            }

            if (queryCursorCreatedDate != null && queryCursorId != null) {
                if (isBackward) {
                    // Walk toward newer records (Previous): strictly greater than cursor in (CreatedDate, Id) tuple
                    baseQuery += ' AND (CreatedDate > :queryCursorCreatedDate OR (CreatedDate = :queryCursorCreatedDate AND Id > :queryCursorId))';
                } else {
                    baseQuery += ' AND (CreatedDate < :queryCursorCreatedDate OR (CreatedDate = :queryCursorCreatedDate AND Id < :queryCursorId))';
                }
            }

            baseQuery += orderClause;
            List<Application__c> applications = Database.query(baseQuery);
            if (applications.isEmpty()) {
                response.hasMore = false;
                response.nextCursorCreatedDate = null;
                response.nextCursorId = null;
                break;
            }

            Set<Id> ownerUserIds = new Set<Id>();
            for (Application__c application : applications) {
                if (application.OwnerId != null && String.valueOf(application.OwnerId).startsWith('005')) {
                    ownerUserIds.add(application.OwnerId);
                }
            }

            Map<Id, User> ownerUsersMap = new Map<Id, User>();
            if (!ownerUserIds.isEmpty()) {
                for (User u : [SELECT Id, ManagerId, Manager.Name FROM User WHERE Id IN :ownerUserIds]) {
                    ownerUsersMap.put(u.Id, u);
                }
            }

            Boolean managerFilterActive = String.isNotBlank(managerFilter);
            Boolean reachedPageSize = false;
            for (Application__c application : applications) {
                // Cheap pre-check: manager filter is just an O(1) map lookup, no compute
                User ownerUser = ownerUsersMap.get(application.OwnerId);
                String ownerManagerName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
                if (managerFilterActive && ownerManagerName != managerFilter) {
                    continue;
                }

                // Compute aging ONCE here so we don't pay BusinessHours.diff twice for survivors
                DateTime stageChangeDate = application.LastModifiedDate;
                Decimal applicationTotalTATInHours = calculateCalendarHoursAging(application.CreatedDate);
                Decimal lastStatusTATInHours = calculateCalendarHoursAging(stageChangeDate);
                Decimal applicationTotalTATInDays = applicationTotalTATInHours / 24.0;
                Decimal lastStatusTATInDays = lastStatusTATInHours / 24.0;

                if (!isInAgeRangeApex(applicationTotalTATInDays, applicationAgeFilter)) {
                    continue;
                }
                if (!isInAgeRangeApex(lastStatusTATInDays, lastStatusAgeFilter)) {
                    continue;
                }

                // Survived all filters → build the heavy result, reusing precomputed values
                ApplicationAgingResult result = buildApplicationAgingResult(
                    application, ownerUser, currentUserId, subordinateUserIds,
                    stageChangeDate, applicationTotalTATInHours, lastStatusTATInHours
                );

                finalResults.add(result);
                if (finalResults.size() >= pageSize) {
                    reachedPageSize = true;
                    break;
                }
            }

            Application__c lastApplicationInBatch = applications[applications.size() - 1];
            queryCursorCreatedDate = lastApplicationInBatch.CreatedDate;
            queryCursorId = lastApplicationInBatch.Id;

            if (reachedPageSize) {
                response.hasMore = true;
                break;
            }

            if (applications.size() < batchSize) {
                response.hasMore = false;
                response.nextCursorCreatedDate = null;
                response.nextCursorId = null;
                break;
            }
        }

        // Backward walk produced records in ASC order; flip to DESC so the LWC always
        // displays newest-first regardless of how the page was reached.
        if (isBackward && !finalResults.isEmpty()) {
            List<ApplicationAgingResult> reversed = new List<ApplicationAgingResult>();
            for (Integer i = finalResults.size() - 1; i >= 0; i--) {
                reversed.add(finalResults[i]);
            }
            finalResults = reversed;
        }

        // nextCursor advertises the boundary for a subsequent FORWARD walk (Next button).
        // That's always the oldest record on this page = the last element after the
        // results are presented in DESC order.
        if (!finalResults.isEmpty()) {
            ApplicationAgingResult oldestOnPage = finalResults[finalResults.size() - 1];
            response.nextCursorCreatedDate = oldestOnPage.applicationCreatedDate;
            response.nextCursorId = oldestOnPage.applicationId;
        }

        // Backward fetch hasMore semantics: a Previous click (cursor present) always
        // leaves at least one forward page to return to; a Last click (no cursor)
        // means we just landed on the final page.
        if (isBackward) {
            response.hasMore = (cursorCreatedDate != null);
        }

        return finalResults;
    }

    // Builds a ApplicationAgingResult using values that the caller has already computed.
    // The caller is responsible for computing aging ONCE (so we never pay BusinessHours.diff twice).
    private static ApplicationAgingResult buildApplicationAgingResult(
        Application__c application,
        User ownerUser,
        Id currentUserId,
        Set<Id> subordinateUserIds,
        DateTime stageChangeDate,
        Decimal applicationTotalTATInHours,
        Decimal lastStatusTATInHours
    ) {
        ApplicationAgingResult result = new ApplicationAgingResult();
        result.applicationId = application.Id;
        result.applicationName = application.Name;
        result.applicationStage = application.Stage__c;
        result.applicationCreatedDate = application.CreatedDate;
        result.latestSLACreatedDate = stageChangeDate;
        result.ownerId = application.OwnerId;
        result.ownerName = application.Owner?.Name;
        result.ownerManagerName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
        result.product = application.Product__c;
        result.isOwner = (application.OwnerId == currentUserId);
        result.isSubordinate = (application.OwnerId != null &&
                                String.valueOf(application.OwnerId).startsWith('005') &&
                                subordinateUserIds.contains(application.OwnerId));

        result.applicationTotalTATInHours = applicationTotalTATInHours;
        result.applicationTotalTATInDays = applicationTotalTATInHours / 24.0;
        result.lastStatusTATInHours = lastStatusTATInHours;
        result.lastStatusTATInDays = lastStatusTATInHours / 24.0;
        result.agingInHours = lastStatusTATInHours;
        result.agingInDays = result.lastStatusTATInDays;
        return result;
    }

    private static Boolean isInAgeRangeApex(Decimal ageInDays, String rangeValue) {
        if (String.isBlank(rangeValue)) {
            return true;
        }
        if (ageInDays == null) {
            return false;
        }

        Decimal age = ageInDays;
        if (rangeValue == '<1') {
            return age < 1;
        } else if (rangeValue == '1-2') {
            return age >= 1 && age < 2;
        } else if (rangeValue == '2-3') {
            return age >= 2 && age < 3;
        } else if (rangeValue == '3-5') {
            return age >= 3 && age < 5;
        } else if (rangeValue == '5-10') {
            return age >= 5 && age < 10;
        } else if (rangeValue == '10-20') {
            return age >= 10 && age < 20;
        } else if (rangeValue == '20-30') {
            return age >= 20 && age < 30;
        } else if (rangeValue == '>30') {
            return age >= 30;
        }
        return true;
    }
    
    // Get all users reporting to the given manager (including manager)
    private static Set<Id> getAllReportingUserIds(Id managerId) {
        if (USE_DIRECT_MANAGER_TRAVERSAL) {
            // NEW APPROACH: Use direct Manager relationship traversal (FASTER)
            return getAllReportingUserIdsDirectTraversal(managerId);
        } else {
            // OLD APPROACH: Use hierarchical query (queries all users)
            return getAllReportingUserIdsHierarchical(managerId);
        }
    }
    
    // NEW APPROACH: Get all reporting users using direct Manager relationship traversal
    // This approach is MUCH FASTER as it only queries users who report up to the given manager
    // It traverses User.Manager, User.Manager.Manager, etc. up to MAX_MANAGER_LEVELS
    // 
    // PERFORMANCE COMPARISON:
    // - OLD METHOD: Queries ALL 50,000 active users, builds hierarchy in memory
    // - NEW METHOD: Only queries users whose manager chain includes the given manager (typically 10-500 users)
    // - Performance gain: 100x-1000x faster for typical org sizes
    //
    // EXAMPLE: For manager with 3 levels of reports (10 direct, 50 indirect, 200 at level 3):
    // - OLD METHOD: Query 50,000 users, process in memory
    // - NEW METHOD: Query ~260 users directly using indexed ManagerId field
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
    
    // OLD APPROACH: Get all reporting users using hierarchical query
    // This approach queries ALL active users and builds hierarchy in memory
    // Kept for backwards compatibility and for cases where unlimited levels are needed
    //
    // HOW IT WORKS:
    // 1. Queries ALL active users with ManagerId (typically 50,000 users)
    // 2. Builds a Map<ManagerId, List<UserId>> in memory
    // 3. Traverses the hierarchy recursively to find all reporting users
    //
    // PROS:
    // - Handles unlimited hierarchy levels
    // - No SOQL in loops (queries once, processes in memory)
    //
    // CONS:
    // - Queries ALL users even if only 100 report to the manager
    // - Higher memory usage
    // - Slower for large orgs with deep hierarchies
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
    
    // Wrapper class for application data
    @TestVisible
    private class ApplicationDataWrapper {
        public Map<Id, Application__c> applicationMap { get; set; }
        public Map<Id, User> ownerUsersMap { get; set; }
    }
    
    // Calculate aging in hours using Business Hours
    private static Decimal calculateBusinessHoursAging(Id businessHoursId, DateTime startDateTime) {
        try {
            DateTime now = DateTime.now();
            
            // Calculate difference in milliseconds
            Long diffInMillis = BusinessHours.diff(businessHoursId, startDateTime, now);
            
            // Convert to hours
            Decimal hours = diffInMillis / (1000.0 * 60.0 * 60.0);
            
            return hours.setScale(2);
            
        } catch(Exception e) {
            system.debug('Error calculating business hours aging: ' + e.getMessage());
            // Fallback to calendar aging
            return calculateCalendarHoursAging(startDateTime);
        }
    }
    
    // Fallback: Calculate aging in calendar hours
    private static Decimal calculateCalendarHoursAging(DateTime startDateTime) {
        DateTime now = DateTime.now();
        Long diffInMillis = now.getTime() - startDateTime.getTime();
        Decimal hours = diffInMillis / (1000.0 * 60.0 * 60.0);
        return hours.setScale(2);
    }
    
    // Wrapper class for results
    public class ApplicationAgingResult {
        @AuraEnabled public Id applicationId { get; set; }
        @AuraEnabled public String applicationName { get; set; }
        @AuraEnabled public String applicationStage { get; set; }
        @AuraEnabled public DateTime applicationCreatedDate { get; set; }
        @AuraEnabled public DateTime latestSLACreatedDate { get; set; }
        // Total Application TAT (from application created date)
        @AuraEnabled public Decimal applicationTotalTATInHours { get; set; }
        @AuraEnabled public Decimal applicationTotalTATInDays { get; set; }
        // Last Status TAT (from latest SLA created date)
        @AuraEnabled public Decimal lastStatusTATInHours { get; set; }
        @AuraEnabled public Decimal lastStatusTATInDays { get; set; }
        // Deprecated - keeping for backwards compatibility
        @AuraEnabled public Decimal agingInHours { get; set; }
        @AuraEnabled public Decimal agingInDays { get; set; }
        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public String ownerName { get; set; }
        @AuraEnabled public String ownerManagerName { get; set; }
        @AuraEnabled public String product { get; set; }
        // Flags for in-memory filtering based on checkbox
        @AuraEnabled public Boolean isOwner { get; set; } // true if owned by logged-in user
        @AuraEnabled public Boolean isSubordinate { get; set; } // true if owned by subordinate
    }
    
    // Computes exact total count for the investigation aging dashboard using a SINGLE SOQL.
    // Trims SELECT to only fields needed for derived (Apex-side) filters.
    // Hard-caps the scan at COUNT_SCAN_THRESHOLD; if exceeded, sets countExceedsThreshold = true
    // and totalCount to the threshold so UI can display "10,000+" style indicator.
    private static void countInvestigationRecords(
        Set<Id> userIds,
        Boolean isAdmin,
        String statusFilter,
        String productFilter,
        String regionFilter,
        String investigationAgeFilter,
        String lastStatusAgeFilter,
        String managerFilter,
        String ownerFilter,
        InvestigationChunkResponse response
    ) {
        Integer scanLimit = COUNT_SCAN_THRESHOLD + 1;

        String soql =
            'SELECT Id, Investigations__c, CreatedDate, ' +
            'Investigations__r.Id, Investigations__r.CreatedDate, ' +
            'Investigations__r.OwnerId ' +
            'FROM Investigations_TAT__c ' +
            'WHERE End_Time__c = null ' +
            'AND Investigations__r.Status__c IN :OPEN_INVESTIGATION_STATUSES';

        if (isAdmin == false) {
            soql += ' AND Investigations__r.OwnerId IN :userIds';
        }
        if (String.isNotBlank(statusFilter)) {
            soql += ' AND Investigations__r.Status__c = :statusFilter';
        }
        if (String.isNotBlank(productFilter)) {
            soql += ' AND Investigations__r.Application__r.Product__c = :productFilter';
        }
        if (String.isNotBlank(ownerFilter)) {
            soql += ' AND Investigations__r.Owner.Name = :ownerFilter';
        }

        soql += ' ORDER BY CreatedDate DESC, Id DESC LIMIT :scanLimit';

        List<Investigations_TAT__c> allTATs = Database.query(soql);
        Boolean exceedsThreshold = (allTATs.size() > COUNT_SCAN_THRESHOLD);

        // Reduce to latest TAT per investigation (matches data path semantics)
        Map<Id, Investigations_TAT__c> latestTATByInvestigation = new Map<Id, Investigations_TAT__c>();
        for (Investigations_TAT__c tat : allTATs) {
            if (!latestTATByInvestigation.containsKey(tat.Investigations__c)) {
                latestTATByInvestigation.put(tat.Investigations__c, tat);
            }
        }

        Boolean needsManagerLookup = String.isNotBlank(managerFilter);
        Boolean needsAgeFilter = String.isNotBlank(investigationAgeFilter) || String.isNotBlank(lastStatusAgeFilter);

        if (!needsManagerLookup && !needsAgeFilter) {
            Integer baseCount = latestTATByInvestigation.size();
            response.totalCount = exceedsThreshold ? COUNT_SCAN_THRESHOLD : baseCount;
            response.countExceedsThreshold = exceedsThreshold;
            return;
        }

        Map<Id, User> ownerUsersMap = new Map<Id, User>();
        if (needsManagerLookup) {
            Set<Id> ownerUserIds = new Set<Id>();
            for (Investigations_TAT__c tat : latestTATByInvestigation.values()) {
                Id ownerId = tat.Investigations__r.OwnerId;
                if (ownerId != null && String.valueOf(ownerId).startsWith('005')) {
                    ownerUserIds.add(ownerId);
                }
            }
            if (!ownerUserIds.isEmpty()) {
                for (User u : [SELECT Id, Manager.Name FROM User WHERE Id IN :ownerUserIds]) {
                    ownerUsersMap.put(u.Id, u);
                }
            }
        }

        Integer count = 0;
        Integer scanned = 0;
        for (Investigations_TAT__c latestTAT : latestTATByInvestigation.values()) {
            scanned++;
            if (scanned > COUNT_SCAN_THRESHOLD) {
                break;
            }
            Investigations__c inv = latestTAT.Investigations__r;

            if (needsManagerLookup) {
                User ownerUser = ownerUsersMap.get(inv.OwnerId);
                String mgrName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
                if (mgrName != managerFilter) {
                    continue;
                }
            }

            if (needsAgeFilter) {
                Decimal investigationTotalTATInDays;
                Decimal lastStatusTATInDays;
                investigationTotalTATInDays = calculateCalendarHoursAging(inv.CreatedDate) / 24.0;
                lastStatusTATInDays = calculateCalendarHoursAging(latestTAT.CreatedDate) / 24.0;
                if (!isInAgeRangeApex(investigationTotalTATInDays, investigationAgeFilter)) {
                    continue;
                }
                if (!isInAgeRangeApex(lastStatusTATInDays, lastStatusAgeFilter)) {
                    continue;
                }
            }

            count++;
        }

        response.totalCount = count;
        response.countExceedsThreshold = exceedsThreshold;
    }

    private static List<InvestigationAgingResult> getInvestigationChunkData(
        Set<Id> userIds,
        Boolean isAdmin,
        String statusFilter,
        String productFilter,
        String regionFilter,
        String investigationAgeFilter,
        String lastStatusAgeFilter,
        String managerFilter,
        String ownerFilter,
        Integer pageSize,
        DateTime cursorCreatedDate,
        Id cursorId,
        Boolean isBackward,
        InvestigationChunkResponse response
    ) {
        List<InvestigationAgingResult> finalResults = new List<InvestigationAgingResult>();
        Integer batchSize = Math.min(1000, Math.max(200, pageSize));
        DateTime queryCursorCreatedDate = cursorCreatedDate;
        Id queryCursorId = cursorId;

        // Backward walks ASC (toward newer records); forward walks DESC (toward older).
        // Results are reversed at the end of a backward walk so the LWC always displays DESC.
        String orderClause = isBackward
            ? ' ORDER BY CreatedDate ASC, Id ASC LIMIT :batchSize'
            : ' ORDER BY CreatedDate DESC, Id DESC LIMIT :batchSize';

        while (finalResults.size() < pageSize) {
            String soql =
                'SELECT Id, Investigations__c, CreatedDate, ' +
                'Investigations__r.Id, Investigations__r.Name, ' +
                'Investigations__r.Status__c, Investigations__r.CreatedDate, ' +
                'Investigations__r.OwnerId, Investigations__r.Owner.Name, ' +
                'Investigations__r.Applicant__r.Application__c, ' +
                'Investigations__r.Applicant__r.Application__r.Name, ' +
                'Investigations__r.Applicant__r.Application__r.Stage__c, ' +
                'Investigations__r.Applicant__r.Application__r.Product__c ' +
                'FROM Investigations_TAT__c ' +
                'WHERE End_Time__c = null ' +
                'AND Investigations__r.Status__c IN :OPEN_INVESTIGATION_STATUSES';

            if (!isAdmin) {
                soql += ' AND Investigations__r.OwnerId IN :userIds';
            }
            if (String.isNotBlank(statusFilter)) {
                soql += ' AND Investigations__r.Status__c =: statusFilter';
            }
            if (String.isNotBlank(productFilter)) {
                soql += ' AND Investigations__r.Applicant__r.Application__r.Product__c =: productFilter';
            }
            if (String.isNotBlank(ownerFilter)) {
                soql += ' AND Investigations__r.Owner.Name =: ownerFilter';
            }
            if (queryCursorCreatedDate != null && queryCursorId != null) {
                if (isBackward) {
                    // Walk toward newer records (Previous): strictly greater than cursor in (CreatedDate, Id) tuple
                    soql += ' AND (CreatedDate > :queryCursorCreatedDate OR (CreatedDate = :queryCursorCreatedDate AND Id > :queryCursorId))';
                }
                else {
                    soql += ' AND (CreatedDate < :queryCursorCreatedDate OR (CreatedDate = :queryCursorCreatedDate AND Id < :queryCursorId))';
                }
            }

            soql += orderClause;
            List<Investigations_TAT__c> allTATs = Database.query(soql);

            if (allTATs.isEmpty()) {
                response.hasMore = false;
                response.nextCursorCreatedDate = null;
                response.nextCursorId = null;
                break;
            }

            Map<Id, Investigations_TAT__c> latestTATByInvestigation = new Map<Id, Investigations_TAT__c>();
            for (Investigations_TAT__c tat : allTATs) {
                if (!latestTATByInvestigation.containsKey(tat.Investigations__c)) {
                    latestTATByInvestigation.put(tat.Investigations__c, tat);
                }
            }

            Set<Id> ownerUserIds = new Set<Id>();
            for (Investigations_TAT__c tat : latestTATByInvestigation.values()) {
                Id ownerId = tat.Investigations__r.OwnerId;
                if (ownerId != null && String.valueOf(ownerId).startsWith('005')) {
                    ownerUserIds.add(ownerId);
                }
            }

            Map<Id, User> ownerUsersMap = new Map<Id, User>();
            if (!ownerUserIds.isEmpty()) {
                for (User u : [SELECT Id, ManagerId, Manager.Name FROM User WHERE Id IN :ownerUserIds]) {
                    ownerUsersMap.put(u.Id, u);
                }
            }

            Boolean managerFilterActive = String.isNotBlank(managerFilter);
            Boolean reachedPageSize = false;
            for (Investigations_TAT__c latestTAT : latestTATByInvestigation.values()) {
                Investigations__c inv = latestTAT.Investigations__r;

                User ownerUser = ownerUsersMap.get(inv.OwnerId);
                String ownerManagerName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
                if (managerFilterActive && ownerManagerName != managerFilter) {
                    continue;
                }

                Decimal investigationTotalTATInHours = calculateCalendarHoursAging(inv.CreatedDate);
                Decimal lastStatusTATInHours = calculateCalendarHoursAging(latestTAT.CreatedDate);
                Decimal investigationTotalTATInDays = investigationTotalTATInHours / 24.0;
                Decimal lastStatusTATInDays = lastStatusTATInHours / 24.0;

                if (!isInAgeRangeApex(investigationTotalTATInDays, investigationAgeFilter)) {
                    continue;
                }
                if (!isInAgeRangeApex(lastStatusTATInDays, lastStatusAgeFilter)) {
                    continue;
                }

                // Survived all filters → build the heavy result, reusing precomputed values
                InvestigationAgingResult result = buildInvestigationAgingResult(
                    latestTAT, ownerUser, investigationTotalTATInHours, lastStatusTATInHours
                );

                finalResults.add(result);
                if (finalResults.size() >= pageSize) {
                    reachedPageSize = true;
                    break;
                }
            }

            Investigations_TAT__c lastTat = allTATs[allTATs.size() - 1];
            queryCursorCreatedDate = lastTat.CreatedDate;
            queryCursorId = lastTat.Id;

            if (reachedPageSize) {
                response.hasMore = true;
                break;
            }

            if (allTATs.size() < batchSize) {
                response.hasMore = false;
                response.nextCursorCreatedDate = null;
                response.nextCursorId = null;
                break;
            }
        }

        // Backward walk produced records in ASC order; flip to DESC so the LWC always
        // displays newest-first regardless of how the page was reached.
        if (isBackward && !finalResults.isEmpty()) {
            List<InvestigationAgingResult> reversed = new List<InvestigationAgingResult>();
            for (Integer i = finalResults.size() - 1; i >= 0; i--) {
                reversed.add(finalResults[i]);
            }
            finalResults = reversed;
        }

        // nextCursor advertises the boundary for a subsequent FORWARD walk (Next button).
        // That's always the oldest record on this page = the last element after the
        // results are presented in DESC order. tatId is the keyset tiebreaker.
        if (!finalResults.isEmpty()) {
            InvestigationAgingResult oldestOnPage = finalResults[finalResults.size() - 1];
            response.nextCursorCreatedDate = oldestOnPage.tatCreatedDate;
            response.nextCursorId = oldestOnPage.tatId;
        }

        // Backward fetch hasMore semantics: a Previous click (cursor present) always
        // leaves at least one forward page to return to; a Last click (no cursor)
        // means we just landed on the final page.
        if (isBackward) {
            response.hasMore = (cursorCreatedDate != null);
        }

        return finalResults;
    }

    // Builds an InvestigationAgingResult using values that the caller has already computed.
    // The caller is responsible for computing aging ONCE (so we never pay BusinessHours.diff twice).
    private static InvestigationAgingResult buildInvestigationAgingResult(
        Investigations_TAT__c latestTAT,
        User ownerUser,
        Decimal investigationTotalTATInHours,
        Decimal lastStatusTATInHours
    )
    {
        Investigations__c inv = latestTAT.Investigations__r;

        InvestigationAgingResult result = new InvestigationAgingResult();
        result.investigationId = inv.Id;
        result.investigationName = inv.Name;
        //result.investigationStatus = inv.Status__c;
        result.investigationCreatedDate = inv.CreatedDate;
        result.tatId = latestTAT.Id;
        result.tatCreatedDate = latestTAT.CreatedDate;
        result.applicationId = inv.Applicant__r.Application__c;
        result.applicationName = inv.Applicant__r.Application__r?.Name;
        result.applicationStage = inv.Applicant__r.Application__r?.Stage__c;
        result.product = inv.Applicant__r.Application__r?.Product__c;
        result.ownerId = inv.OwnerId;
        result.ownerName = inv.Owner?.Name;
        result.ownerManagerName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;

        result.investigationTotalTATInHours = investigationTotalTATInHours;
        result.investigationTotalTATInDays = investigationTotalTATInHours / 24.0;
        result.lastStatusTATInHours = lastStatusTATInHours;
        result.lastStatusTATInDays = lastStatusTATInHours / 24.0;
        result.agingInHours = lastStatusTATInHours;
        result.agingInDays = result.lastStatusTATInDays;
        result.createdDate = latestTAT.CreatedDate;
        return result;
    }
    
    // Wrapper class for investigation results
    public class InvestigationAgingResult {
        @AuraEnabled public Id investigationId { get; set; }
        @AuraEnabled public String investigationName { get; set; }
        //@AuraEnabled public String investigationStatus { get; set; }
        @AuraEnabled public DateTime investigationCreatedDate { get; set; }
        @AuraEnabled public Id tatId { get; set; } // Latest TAT record Id - used as keyset cursor tiebreaker for pagination
        @AuraEnabled public DateTime tatCreatedDate { get; set; } // When current status started
        @AuraEnabled public Id applicationId { get; set; }
        @AuraEnabled public String applicationName { get; set; }
        @AuraEnabled public String applicationStage { get; set; }
        @AuraEnabled public String product { get; set; }
        // Total Investigation TAT (from investigation created date)
        @AuraEnabled public Decimal investigationTotalTATInHours { get; set; }
        @AuraEnabled public Decimal investigationTotalTATInDays { get; set; }
        // Last Status TAT (from latest TAT created date)
        @AuraEnabled public Decimal lastStatusTATInHours { get; set; }
        @AuraEnabled public Decimal lastStatusTATInDays { get; set; }
        // Deprecated - keeping for backwards compatibility
        @AuraEnabled public Decimal agingInHours { get; set; }
        @AuraEnabled public Decimal agingInDays { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public String ownerName { get; set; }
        @AuraEnabled public String ownerManagerName { get; set; }
    }
    
    // Wrapper class for response with employee and manager views (APPLICATIONS)
    public class ApplicationAgingResponse {
        @AuraEnabled public Boolean isManager { get; set; }
        @AuraEnabled public Boolean showInvestigations { get; set; }
        @AuraEnabled public List<ApplicationAgingResult> employeeViewData { get; set; }
        @AuraEnabled public List<ApplicationAgingResult> managerViewData { get; set; }
        @AuraEnabled public List<InvestigationAgingResult> employeeInvestigationData { get; set; }
        @AuraEnabled public List<InvestigationAgingResult> managerInvestigationData { get; set; }
        @AuraEnabled public String warningMessage { get; set; }
        @AuraEnabled public Integer applicationRecordCount { get; set; }
        @AuraEnabled public Integer investigationRecordCount { get; set; }
    }

    public class ApplicationChunkResponse {
        @AuraEnabled public List<ApplicationAgingResult> records { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public DateTime nextCursorCreatedDate { get; set; }
        @AuraEnabled public Id nextCursorId { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Boolean countExceedsThreshold { get; set; }
    }
    
    // Wrapper class for response with employee and manager views (INVESTIGATIONS)
    public class InvestigationAgingResponse {
        @AuraEnabled public Boolean isManager { get; set; }
        @AuraEnabled public Boolean showInvestigations { get; set; }
        @AuraEnabled public List<InvestigationAgingResult> employeeInvestigationData { get; set; }
        @AuraEnabled public List<InvestigationAgingResult> managerInvestigationData { get; set; }
        @AuraEnabled public String warningMessage { get; set; }
        @AuraEnabled public Integer investigationRecordCount { get; set; }
    }

    public class InvestigationChunkResponse {
        @AuraEnabled public List<InvestigationAgingResult> records { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public DateTime nextCursorCreatedDate { get; set; }
        @AuraEnabled public Id nextCursorId { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Boolean countExceedsThreshold { get; set; }
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
    
    // ==================== CASE/QUERY AGING METHODS ====================
    
    // cursorDirection: 'forward' (default) walks toward older records (Next).
    //                  'backward' walks toward newer records (Previous), or fetches the
    //                  oldest page when no cursor is supplied (Last button).
    @AuraEnabled(cacheable=false)
    public static QueryChunkResponse getQueryAgingChunk(
        List<Id> userIds,
        String statusFilter,
        String priorityFilter,
        String typeFilter,
        String ageFilter,
        String managerFilter,
        String ownerFilter,
        Integer pageSize,
        DateTime cursorCreatedDate,
        Id cursorId,
        String cursorDirection
    ) {
        if (pageSize == null || pageSize <= 0) {
            pageSize = 1000;
        }
        Boolean isBackward = (cursorDirection == 'backward');
        QueryChunkResponse response = new QueryChunkResponse();
        // Only compute total count on the first fresh forward fetch.
        if (!isBackward && cursorCreatedDate == null && cursorId == null) {
            countCaseRecords(
                new Set<Id>(userIds),
                statusFilter,
                priorityFilter,
                typeFilter,
                ageFilter,
                managerFilter,
                ownerFilter,
                response
            );
        }
        response.records = getQueryChunkData(
            new Set<Id>(userIds),
            statusFilter,
            priorityFilter,
            typeFilter,
            ageFilter,
            managerFilter,
            ownerFilter,
            pageSize,
            cursorCreatedDate,
            cursorId,
            isBackward,
            response
        );
        return response;
    }
    
    // Computes exact total count for the query aging dashboard using a SINGLE SOQL.
    // Trims SELECT to only fields needed for derived (Apex-side) filters.
    // Hard-caps the scan at COUNT_SCAN_THRESHOLD; if exceeded, sets countExceedsThreshold = true
    // and totalCount to the threshold so UI can display "10,000+" style indicator.
    private static void countCaseRecords(
        Set<Id> userIds,
        String statusFilter,
        String priorityFilter,
        String typeFilter,
        String ageFilter,
        String managerFilter,
        String ownerFilter,
        QueryChunkResponse response
    ) {
        Integer scanLimit = COUNT_SCAN_THRESHOLD + 1;

        String soql =
            'SELECT Id, CreatedDate, OwnerId ' +
            'FROM Case ' +
            'WHERE ((Owner.Type = \'User\' AND OwnerId IN :userIds) OR (Contact.OwnerId IN :userIds)) ' +
            'AND IsClosed = false';

        if (String.isNotBlank(statusFilter)) {
            soql += ' AND Status = :statusFilter';
        }
        if (String.isNotBlank(priorityFilter)) {
            soql += ' AND Priority = :priorityFilter';
        }
        if (String.isNotBlank(typeFilter)) {
            soql += ' AND Type = :typeFilter';
        }
        if (String.isNotBlank(ownerFilter)) {
            soql += ' AND Owner.Name = :ownerFilter';
        }

        soql += ' LIMIT :scanLimit';

        List<Case> cases = Database.query(soql);
        Boolean exceedsThreshold = (cases.size() > COUNT_SCAN_THRESHOLD);

        Boolean needsManagerLookup = String.isNotBlank(managerFilter);
        Boolean needsAgeFilter = String.isNotBlank(ageFilter);

        if (!needsManagerLookup && !needsAgeFilter) {
            response.totalCount = exceedsThreshold ? COUNT_SCAN_THRESHOLD : cases.size();
            response.countExceedsThreshold = exceedsThreshold;
            return;
        }

        Map<Id, User> ownerUsersMap = new Map<Id, User>();
        if (needsManagerLookup) {
            Set<Id> ownerUserIds = new Set<Id>();
            for (Case c : cases) {
                if (c.OwnerId != null && String.valueOf(c.OwnerId).startsWith('005')) {
                    ownerUserIds.add(c.OwnerId);
                }
            }
            if (!ownerUserIds.isEmpty()) {
                for (User u : [SELECT Id, Manager.Name FROM User WHERE Id IN :ownerUserIds]) {
                    ownerUsersMap.put(u.Id, u);
                }
            }
        }

        Integer count = 0;
        Integer scanned = 0;
        for (Case c : cases) {
            scanned++;
            if (scanned > COUNT_SCAN_THRESHOLD) {
                break;
            }

            if (needsManagerLookup) {
                User ownerUser = ownerUsersMap.get(c.OwnerId);
                String mgrName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
                if (mgrName != managerFilter) {
                    continue;
                }
            }

            if (needsAgeFilter) {
                Decimal agingInDays = calculateCalendarHoursAging(c.CreatedDate) / 24.0;
                if (!isInAgeRangeApex(agingInDays, ageFilter)) {
                    continue;
                }
            }

            count++;
        }

        response.totalCount = count;
        response.countExceedsThreshold = exceedsThreshold;
    }

    private static List<QueryAgingResult> getQueryChunkData(
        Set<Id> userIds,
        String statusFilter,
        String priorityFilter,
        String typeFilter,
        String ageFilter,
        String managerFilter,
        String ownerFilter,
        Integer pageSize,
        DateTime cursorCreatedDate,
        Id cursorId,
        Boolean isBackward,
        QueryChunkResponse response
    ) {
        List<QueryAgingResult> finalResults = new List<QueryAgingResult>();
        Integer batchSize = Math.min(1000, Math.max(200, pageSize));
        DateTime queryCursorCreatedDate = cursorCreatedDate;
        Id queryCursorId = cursorId;

        // Backward walks ASC (toward newer records); forward walks DESC (toward older).
        // Results are reversed at the end of a backward walk so the LWC always displays DESC.
        String orderClause = isBackward
            ? ' ORDER BY CreatedDate ASC, Id ASC LIMIT :batchSize'
            : ' ORDER BY CreatedDate DESC, Id DESC LIMIT :batchSize';

        while (finalResults.size() < pageSize) {
            String soql =
                'SELECT Id, Name, Subject__c, Status__c, Priority__c, Query_Type__c, ' +
                'CreatedDate, Date_Time_Closed__c, ' +
                'OwnerId, Owner.Name, Owner.Type, ' +
                'Assigned_To__c, Assigned_To__r.Name, ' +
                'Application__c, ' +
                'Application__r.Name, ' +
                'Application__r.Stage__c, ' +
                'Application__r.Product__c ' +
                'FROM Query__c ' +
                'WHERE ((Owner.Type = \'User\' AND OwnerId IN :userIds) OR (Assigned_To__c IN :userIds)) ' +
                'AND Status__c != \'Closed\'';

            if (String.isNotBlank(statusFilter)) {
                soql += ' AND Status__c = :statusFilter';
            }
            if (String.isNotBlank(priorityFilter)) {
                soql += ' AND Priority__c = :priorityFilter';
            }
            if (String.isNotBlank(typeFilter)) {
                soql += ' AND Query_Type__c = :typeFilter';
            }
            if (String.isNotBlank(ownerFilter)) {
                soql += ' AND Owner.Name = :ownerFilter';
            }
            if (queryCursorCreatedDate != null && queryCursorId != null) {
                if (isBackward) {
                    // Walk toward newer records (Previous): strictly greater than cursor in (CreatedDate, Id) tuple
                    soql += ' AND (CreatedDate > :queryCursorCreatedDate OR (CreatedDate = :queryCursorCreatedDate AND Id > :queryCursorId))';
                } else {
                    soql += ' AND (CreatedDate < :queryCursorCreatedDate OR (CreatedDate = :queryCursorCreatedDate AND Id < :queryCursorId))';
                }
            }
            soql += orderClause;

            List<Query__c> queries = Database.query(soql);
            if (queries.isEmpty()) {
                response.hasMore = false;
                response.nextCursorCreatedDate = null;
                response.nextCursorId = null;
                break;
            }

            Set<Id> ownerIds = new Set<Id>();
            for (Query__c q : queries) {
                ownerIds.add(q.OwnerId);
            }

            Map<Id, User> ownerMap = new Map<Id, User>();
            if (!ownerIds.isEmpty()) {
                ownerMap = new Map<Id, User>([
                    SELECT Id, Name, ManagerId, Manager.Name
                    FROM User
                    WHERE Id IN :ownerIds
                ]);
            }

            Boolean managerFilterActive = String.isNotBlank(managerFilter);
            Boolean reachedPageSize = false;
            for (Query__c q : queries) {
                // Cheap pre-check: manager filter (O(1) map lookup, no compute)
                User ownerUser = ownerMap.get(q.OwnerId);
                String ownerManagerName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
                if (managerFilterActive && ownerManagerName != managerFilter) {
                    continue;
                }

                Decimal agingInHours = calculateCalendarHoursAging(q.CreatedDate);
                Decimal agingInDays = agingInHours / 24.0;

                if (!isInAgeRangeApex(agingInDays, ageFilter)) {
                    continue;
                }

                // Survived all filters → build the heavy result, reusing precomputed values
                QueryAgingResult result = buildQueryAgingResult(q, ownerUser, agingInHours);

                finalResults.add(result);
                if (finalResults.size() >= pageSize) {
                    reachedPageSize = true;
                    break;
                }
            }

            Query__c lastQuery = queries[queries.size() - 1];
            queryCursorCreatedDate = lastQuery.CreatedDate;
            queryCursorId = lastQuery.Id;

            if (reachedPageSize) {
                response.hasMore = true;
                break;
            }
            if (queries.size() < batchSize) {
                response.hasMore = false;
                response.nextCursorCreatedDate = null;
                response.nextCursorId = null;
                break;
            }
        }

        // Backward walk produced records in ASC order; flip to DESC so the LWC always
        // displays newest-first regardless of how the page was reached.
        if (isBackward && !finalResults.isEmpty()) {
            List<QueryAgingResult> reversed = new List<QueryAgingResult>();
            for (Integer i = finalResults.size() - 1; i >= 0; i--) {
                reversed.add(finalResults[i]);
            }
            finalResults = reversed;
        }

        // nextCursor advertises the boundary for a subsequent FORWARD walk (Next button).
        // That's always the oldest record on this page = the last element after the
        // results are presented in DESC order.
        if (!finalResults.isEmpty()) {
            QueryAgingResult oldestOnPage = finalResults[finalResults.size() - 1];
            response.nextCursorCreatedDate = oldestOnPage.createdDate;
            response.nextCursorId = oldestOnPage.queryId;
        }

        // Backward fetch hasMore semantics: a Previous click (cursor present) always
        // leaves at least one forward page to return to; a Last click (no cursor)
        // means we just landed on the final page.
        if (isBackward) {
            response.hasMore = (cursorCreatedDate != null);
        }

        return finalResults;
    }

    // Builds a QueryAgingResult using values that the caller has already computed.
    // The caller is responsible for computing aging ONCE (so we never pay BusinessHours.diff twice).
    private static QueryAgingResult buildQueryAgingResult(Query__c q, User ownerUser, Decimal agingInHours) {
        QueryAgingResult result = new QueryAgingResult();
        result.queryId = q.Id;
        result.queryNumber = q.Name;
        result.subject = q.Subject__c;
        result.status = q.Status__c;
        result.priority = q.Priority__c;
        result.queryType = q.Query_Type__c;
        result.ownerId = q.OwnerId;
        result.ownerName = q.Owner.Name;
        result.createdDate = q.CreatedDate;
        result.closedDate = q.Date_Time_Closed__c;
        result.assignedToId = q.Assigned_To__c;
        result.assignedToName = q.Assigned_To__r != null ? q.Assigned_To__r.Name : null;
        if (ownerUser != null && ownerUser.Manager != null) {
            result.ownerManagerName = ownerUser.Manager.Name;
        }
        result.agingInHours = agingInHours;
        result.agingInDays = agingInHours / 24.0;
        return result;   
    }
    
    // Wrapper class for Query aging results
    public class QueryAgingResult {
        @AuraEnabled public Id queryId { get; set; }
        @AuraEnabled public String queryNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String queryType { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public DateTime closedDate { get; set; }
        @AuraEnabled public Decimal agingInHours { get; set; }
        @AuraEnabled public Decimal agingInDays { get; set; }
        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public String ownerName { get; set; }
        @AuraEnabled public String ownerManagerName { get; set; }
        @AuraEnabled public Id assignedToId { get; set; }
        @AuraEnabled public String assignedToName { get; set; }
        // Application information
        @AuraEnabled public Id applicationId { get; set; }
        @AuraEnabled public String applicationName { get; set; }
        @AuraEnabled public String applicationStage { get; set; }
        @AuraEnabled public String product { get; set; }
    }
    
    // Wrapper class for Query aging response
    public class QueryAgingResponse {
        @AuraEnabled public Boolean isManager { get; set; }
        @AuraEnabled public List<QueryAgingResult> employeeQueryData { get; set; }
        @AuraEnabled public List<QueryAgingResult> managerQueryData { get; set; }
        @AuraEnabled public String warningMessage { get; set; }
        @AuraEnabled public Integer queryRecordCount { get; set; }
    }

    public class QueryChunkResponse {
        @AuraEnabled public List<QueryAgingResult> records { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public DateTime nextCursorCreatedDate { get; set; }
        @AuraEnabled public Id nextCursorId { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Boolean countExceedsThreshold { get; set; }
    }
}