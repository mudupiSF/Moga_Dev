public class MyQueriesAgingReportController {

    // Hard cap for total-count scan on first page request to stay within governor limits.
    // If matched records exceed this number, UI will display "10,000+" instead of exact total.
    private static final Integer COUNT_SCAN_THRESHOLD = 10000;

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
    )
    {
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

        soql += ' LIMIT :scanLimit';

        List<Query__c> queries = Database.query(soql);
        Boolean exceedsThreshold = (queries.size() > COUNT_SCAN_THRESHOLD);

        Boolean needsManagerLookup = String.isNotBlank(managerFilter);
        Boolean needsAgeFilter = String.isNotBlank(ageFilter);

        if (!needsManagerLookup && !needsAgeFilter) {
            response.totalCount = exceedsThreshold ? COUNT_SCAN_THRESHOLD : queries.size();
            response.countExceedsThreshold = exceedsThreshold;
            return;
        }

        Map<Id, User> ownerUsersMap = new Map<Id, User>();
        if (needsManagerLookup) {
            Set<Id> ownerUserIds = new Set<Id>();
            for (Query__c qry : queries) {
                if (qry.OwnerId != null && String.valueOf(qry.OwnerId).startsWith('005')) {
                    ownerUserIds.add(qry.OwnerId);
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
        for (Query__c qry : queries) {
            scanned++;
            if (scanned > COUNT_SCAN_THRESHOLD) {
                break;
            }

            if (needsManagerLookup) {
                User ownerUser = ownerUsersMap.get(qry.OwnerId);
                String mgrName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
                if (mgrName != managerFilter) {
                    continue;
                }
            }

            if (needsAgeFilter) {
                Decimal agingInDays = calculateCalendarHoursAging(qry.CreatedDate) / 24.0;
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
                //'AccountId, Account.Name, ' +
                //'Origin, Reason, Description, ' +
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
            for (Query__c qry : queries) {
                ownerIds.add(qry.OwnerId);
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
            for (Query__c qry : queries) {
                // Cheap pre-check: manager filter (O(1) map lookup, no compute)
                User ownerUser = ownerMap.get(qry.OwnerId);
                String ownerManagerName = ownerUser != null && ownerUser.Manager != null ? ownerUser.Manager.Name : null;
                if (managerFilterActive && ownerManagerName != managerFilter) {
                    continue;
                }

                Decimal agingInHours = calculateCalendarHoursAging(qry.CreatedDate);
                Decimal agingInDays = agingInHours / 24.0;

                if (!isInAgeRangeApex(agingInDays, ageFilter)) {
                    continue;
                }

                // Survived all filters → build the heavy result, reusing precomputed values
                QueryAgingResult result = buildQueryAgingResult(qry, ownerUser, agingInHours);

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

    // Fallback: Calculate aging in calendar hours
    private static Decimal calculateCalendarHoursAging(DateTime startDateTime) {
        DateTime now = DateTime.now();
        Long diffInMillis = now.getTime() - startDateTime.getTime();
        Decimal hours = diffInMillis / (1000.0 * 60.0 * 60.0);
        return hours.setScale(2);
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
        }
        else if (rangeValue == '1-2') {
            return age >= 1 && age < 2;
        }
        else if (rangeValue == '2-3') {
            return age >= 2 && age < 3;
        }
        else if (rangeValue == '3-5') {
            return age >= 3 && age < 5;
        }
        else if (rangeValue == '5-10') {
            return age >= 5 && age < 10;
        }
        else if (rangeValue == '10-20') {
            return age >= 10 && age < 20;
        }
        else if (rangeValue == '20-30') {
            return age >= 20 && age < 30;
        }
        else if (rangeValue == '>30') {
            return age >= 30;
        }
        return true;
    }

    // Builds a CaseAgingResult using values that the caller has already computed.
    // The caller is responsible for computing aging ONCE (so we never pay BusinessHours.diff twice).
    private static QueryAgingResult buildQueryAgingResult(Query__c qry, User ownerUser, Decimal agingInHours) {
        QueryAgingResult result = new QueryAgingResult();
        result.queryId = qry.Id;
        result.caseNumber = qry.Name;
        result.subject = qry.Subject__c;
        result.status = qry.Status__c;
        result.priority = qry.Priority__c;
        result.caseType = qry.Query_Type__c;
        //result.origin = qry.Origin;
        //result.reason = qry.Reason;
        result.createdDate = qry.CreatedDate;
        result.closedDate = qry.Date_Time_Closed__c;
        //result.accountName = qry.Account?.Name;
        result.loanApplicationId = qry.Application__c;
        result.loanApplicationName = qry.Application__r.Name;
        result.loanStage = qry.Application__r.Stage__c;
        result.product = qry.Application__r.Product__c;
        result.ownerId = qry.OwnerId;
        result.ownerName = qry.Owner.Name;
        result.assignedToId = qry.Assigned_To__c;
        result.assignedToName = qry.Assigned_To__r != null ? qry.Assigned_To__r.Name : null;
        if (ownerUser != null && ownerUser.Manager != null) {
            result.ownerManagerName = ownerUser.Manager.Name;
        }
        result.agingInHours = agingInHours;
        result.agingInDays = agingInHours / 24.0;
        return result;
    }

    public class QueryChunkResponse {
        @AuraEnabled public List<QueryAgingResult> records { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public DateTime nextCursorCreatedDate { get; set; }
        @AuraEnabled public Id nextCursorId { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Boolean countExceedsThreshold { get; set; }
    }

    // Wrapper class for Case aging results
    public class QueryAgingResult {
        @AuraEnabled public Id queryId { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String caseType { get; set; }
        @AuraEnabled public String origin { get; set; }
        @AuraEnabled public String reason { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public DateTime closedDate { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Decimal agingInHours { get; set; }
        @AuraEnabled public Decimal agingInDays { get; set; }
        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public String ownerName { get; set; }
        @AuraEnabled public String ownerManagerName { get; set; }
        @AuraEnabled public Id assignedToId { get; set; }
        @AuraEnabled public String assignedToName { get; set; }
        // Loan Application and CPC information
        @AuraEnabled public Id loanApplicationId { get; set; }
        @AuraEnabled public String loanApplicationName { get; set; }
        @AuraEnabled public String loanStage { get; set; }
        @AuraEnabled public String cpcName { get; set; }
        @AuraEnabled public String cpcRegion { get; set; }
        @AuraEnabled public String product { get; set; }
    }
}