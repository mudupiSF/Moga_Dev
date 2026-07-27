/**
 * TATSummaryService — owns the per-Application TAT_Summary__c lifecycle.
 *
 * Two entry points:
 *
 *   ensureSummariesExist(Set<Id> applicationIds)
 *       Returns Map<applicationId, summaryId>. Creates blank TAT_Summary__c
 *       rows for any Application Id that doesn't already have one. Called by
 *       TATEventRecorder during insert so every event row is linked to a
 *       parent summary.
 *
 *   updateSummaries(Set<Id> applicationIds)
 *       Recomputes the per-stage duration fields on each summary from
 *       SUM(TAT_Event__c.TAT_Minutes__c) and SUM(TAT_Event__c.TAT_Business_Minutes__c)
 *       grouped by Stage__c. Also populates the application-wide rollups
 *       Total_TAT_Mins__c / Total_BH_Mins__c. Call whenever you want the
 *       summary refreshed (after every event write, at LA disbursal, on a
 *       schedule, etc.).
 *
 * Field-name convention on TAT_Summary__c (kept compact for SFDC's 40-char limit):
 *
 *     <prefix>_TAT_Mins__c        Number   — total wall-clock minutes for this stage
 *     <prefix>_BH_Mins__c         Number   — total business-hours minutes for this stage
 *     <prefix>_TAT_Display__c     Formula  — "2d 14h 30m" derived from _TAT_Mins__c
 *     <prefix>_BH_Display__c      Formula  — "2d 14h 30m" derived from _BH_Mins__c
 *
 *     Total_TAT_Mins__c           Number   — SUM of all <prefix>_TAT_Mins__c per app
 *     Total_BH_Mins__c            Number   — SUM of all <prefix>_BH_Mins__c per app
 *     Total_TAT_Display__c        Formula  — "2d 14h 30m" derived from Total_TAT_Mins__c
 *     Total_BH_Display__c         Formula  — "2d 14h 30m" derived from Total_BH_Mins__c
 *
 * <prefix> is the stage label with spaces replaced by underscores
 * (e.g. Stage__c = "Financial Sanction Hold" → prefix "Financial_Sanction_Hold").
 * Events whose Stage__c doesn't map to an existing field prefix are still
 * counted in Total_*_Mins__c (so the grand total never under-reports), but
 * their per-stage breakdown is skipped.
 */
public with sharing class TATSummaryService {
    public static Map<String, Map<String, String>> objectStagePrefixMap = new Map<String, Map<String, String>>();
    static {
        objectStagePrefixMap.put('Query__c', new Map<String, String>{ 'Open' => 'open_', 'Closed' => 'closed_', 'In Progress' => 'in_progress_', 'Resolved' => 'resolved_', 'Rejected' => 'rejected_', 'Re-Open' => 're_open_' });
        objectStagePrefixMap.put('Application__c', new Map<String, String>{ 'QDE' => 'qde_', 'DDE' => 'dde_', 'Credit Processing' => 'credit_processing_', 'Post Sanction Sales' => 'post_sanction_sales_', 'Operations' => 'operations_' });
    }

    //public static Map<String, Map<String, FieldAPINameWrapper>> objectStatusFieldsMap = new Map<String, Map<String, FieldAPINameWrapper>>();

    /**
     * Find-or-create a TAT_Summary__c row for every applicationId in the set.
     * Bulk-safe: one SOQL, one insert at most.
     *
     * Returns a map keyed by Application Id → matching Summary Id.
     */
    public static Map<Id, Id> ensureSummariesExist(Set<Id> applicationIds) {
        Map<Id, Id> summaryByApp = new Map<Id, Id>();
        if (applicationIds == null || applicationIds.isEmpty()) {
            return summaryByApp;
        }

        for (TAT_Summary__c s : [
            SELECT Id, Application__c
            FROM TAT_Summary__c
            WHERE Application__c IN :applicationIds
        ]) {
            summaryByApp.put(s.Application__c, s.Id);
        }

        List<TAT_Summary__c> toCreate = new List<TAT_Summary__c>();
        for (Id appId : applicationIds) {
            if (!summaryByApp.containsKey(appId)) {
                toCreate.add(new TAT_Summary__c(Application__c = appId));
            }
        }
        if (!toCreate.isEmpty()) {
            insert toCreate;
            for (TAT_Summary__c s : toCreate) {
                summaryByApp.put(s.Application__c, s.Id);
            }
        }
        return summaryByApp;
    }

    public static void updateSummaries(Id applicationId) {
        updateSummaries(new Set<Id>{ applicationId });
    }

    /**
     * Recompute the per-stage TAT minutes (wall-clock + business hours) on
     * the matching TAT_Summary__c rows.
     *
     * Behaviour:
     *   1. Create missing TAT_Summary__c rows for these Application Ids.
     *   2. Reset every <prefix>_TAT_Mins__c / <prefix>_BH_Mins__c field on
     *      those summaries back to zero — so a deleted/closed event doesn't
     *      leave stale numbers around.
     *   3. SUM TAT_Minutes__c / TAT_Business_Minutes__c on TAT_Event__c
     *      grouped by Application + Stage, write each total into the matching
     *      summary field.
     *   4. Update the summaries.
     *
     * The Display formula fields recompute automatically on read.
     */
    public static void updateSummaries(Set<Id> applicationIds) {
        if (applicationIds == null || applicationIds.isEmpty()) { return; }
        List<Id> applicationIdsList = new List<Id>(applicationIds);

        Map<Id, Id> summaryByApp = ensureSummariesExist(applicationIds);

        Schema.SObjectType objType = applicationIdsList[0].getSObjectType();
        String objectName = objType.getDescribe().getName();

        // Build update objects, zero every stage min field so deletions/edits
        // don't leave a phantom number behind.
        Map<String, Schema.SObjectField> summaryFields =
            Schema.SObjectType.TAT_Summary__c.fields.getMap();
        Set<String> resettableFields = new Set<String>();
        for (String fname : summaryFields.keySet()) {
            String lower = fname.toLowerCase();
            if (lower.endsWith('_tat_mins__c') || lower.endsWith('_bh_mins__c')) {
                resettableFields.add(fname);
            }
        }

        Map<Id, TAT_Summary__c> summariesToUpdate = new Map<Id, TAT_Summary__c>();
        for (Id appId : applicationIds) {
            Id summaryId = summaryByApp.get(appId);
            if (summaryId == null) { continue; }
            TAT_Summary__c s = new TAT_Summary__c(Id = summaryId);
            for (String fname : resettableFields) {
                s.put(fname, 0);
            }
            summariesToUpdate.put(summaryId, s);
        }

        // Running grand totals per Application, populated alongside the
        // per-stage writes so we don't need a second aggregate query.
        Map<Id, Integer> totalTatMinsByApp = new Map<Id, Integer>();
        Map<Id, Integer> totalBhMinsByApp  = new Map<Id, Integer>();

        // Aggregate events by (Application, Stage).
        for (AggregateResult ar : [
            SELECT Application__c app, Stage__c stage,
                   SUM(TAT_Minutes__c)         totalMins,
                   SUM(TAT_Business_Minutes__c) totalBizMins
            FROM TAT_Event__c
            WHERE Application__c IN :applicationIds
              AND Stage__c != null
            GROUP BY Application__c, Stage__c
        ])
        {
            Id appId = (Id) ar.get('app');
            String stage = (String) ar.get('stage');
            Decimal mins    = (Decimal) ar.get('totalMins');
            Decimal bizMins = (Decimal) ar.get('totalBizMins');

            Integer minsInt    = (mins    == null) ? 0 : mins.intValue();
            Integer bizMinsInt = (bizMins == null) ? 0 : bizMins.intValue();

            // Grand totals first — every event counts, even if its stage has
            // no matching per-stage field.
            totalTatMinsByApp.put(appId,
                (totalTatMinsByApp.containsKey(appId) ? totalTatMinsByApp.get(appId) : 0) + minsInt);
            totalBhMinsByApp.put(appId,
                (totalBhMinsByApp.containsKey(appId) ? totalBhMinsByApp.get(appId) : 0) + bizMinsInt);

            Id summaryId = summaryByApp.get(appId);
            if (summaryId == null) { continue; }
            TAT_Summary__c s = summariesToUpdate.get(summaryId);
            if (s == null) { continue; }

            String prefix = stageToFieldPrefix(objectName, stage);

            String tatField = prefix + '_TAT_Mins__c';
            String bhField  = prefix + '_BH_Mins__c';

            if (summaryFields.containsKey(tatField.toLowerCase())) {
                s.put(tatField, minsInt);
            }
            if (summaryFields.containsKey(bhField.toLowerCase())) {
                s.put(bhField, bizMinsInt);
            }
        }

        // Stamp the grand totals onto each summary row.
        for (Id appId : applicationIds) {
            Id summaryId = summaryByApp.get(appId);
            if (summaryId == null) { continue; }
            TAT_Summary__c s = summariesToUpdate.get(summaryId);
            if (s == null) { continue; }
            s.put('Total_TAT_Mins__c',
                totalTatMinsByApp.containsKey(appId) ? totalTatMinsByApp.get(appId) : 0);
            s.put('Total_BH_Mins__c',
                totalBhMinsByApp.containsKey(appId)  ? totalBhMinsByApp.get(appId)  : 0);
        }

        if (!summariesToUpdate.isEmpty()) {
            update summariesToUpdate.values();
        }
    }

    /*private static void initializeObjectStatusFieldsMap() {
        Schema.SObjectType tatSummaryObjectType = TAT_Summary__c.SObjectType;
        Map<String, SObjectField> fieldMap = tatSummaryObjectType.getDescribe().fields.getMap();
        objectStatusFieldsMap.put('Query__c', new Map<String, FieldAPINameWrapper>());
        objectStatusFieldsMap.put('Application__c', new Map<String, FieldAPINameWrapper>());
        Schema.DescribeFieldResult fieldDescribe;
        for (SObjectField fieldToken : fieldMap.values()) {
            fieldDescribe = fieldToken.getDescribe();
            if (fieldDescribe.isCustom()) {
                String lower = fieldDescribe.getName().toLowerCase();
                // Application__c status fields starts here
                if(lower == 'qde_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('QDE')) {
                        objectStatusFieldsMap.get('Application__c').get('QDE').tatFieldName = 'qde_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('QDE', new FieldAPINameWrapper('qde_tat_mins__c', ''));
                    }
                }
                if(lower == 'qde_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('QDE')) {
                        objectStatusFieldsMap.get('Application__c').get('QDE').bhFieldName = 'qde_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('QDE', new FieldAPINameWrapper('', 'qde_bh_mins__c'));
                    }
                }
                if(lower == 'dde_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('DDE')) {
                        objectStatusFieldsMap.get('Application__c').get('DDE').tatFieldName = 'dde_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('DDE', new FieldAPINameWrapper('dde_tat_mins__c', ''));
                    }
                }
                if(lower == 'dde_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('DDE')) {
                        objectStatusFieldsMap.get('Application__c').get('DDE').bhFieldName = 'dde_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('DDE', new FieldAPINameWrapper('', 'dde_bh_mins__c'));
                    }
                }
                if(lower == 'credit_processing_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('Credit Processing')) {
                        objectStatusFieldsMap.get('Application__c').get('Credit Processing').tatFieldName = 'credit_processing_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('Credit Processing', new FieldAPINameWrapper('credit_processing_tat_mins__c', ''));
                    }
                }
                if(lower == 'credit_processing_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('Credit Processing')) {
                        objectStatusFieldsMap.get('Application__c').get('Credit Processing').bhFieldName = 'credit_processing_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('Credit Processing', new FieldAPINameWrapper('', 'credit_processing_bh_mins__c'));
                    }
                }
                if(lower == 'post_sanction_sales_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('Post Sanction Sales')) {
                        objectStatusFieldsMap.get('Application__c').get('Post Sanction Sales').tatFieldName = 'post_sanction_sales_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('Post Sanction Sales', new FieldAPINameWrapper('post_sanction_sales_tat_mins__c', ''));
                    }
                }
                if(lower == 'post_sanction_sales_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('Post Sanction Sales')) {
                        objectStatusFieldsMap.get('Application__c').get('Post Sanction Sales').bhFieldName = 'post_sanction_sales_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('Post Sanction Sales', new FieldAPINameWrapper('', 'post_sanction_sales_bh_mins__c'));
                    }
                }
                if(lower == 'operations_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('Operations')) {
                        objectStatusFieldsMap.get('Application__c').get('Operations').tatFieldName = 'operations_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('Operations', new FieldAPINameWrapper('operations_tat_mins__c', ''));
                    }
                }
                if(lower == 'operations_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Application__c').containsKey('Operations')) {
                        objectStatusFieldsMap.get('Application__c').get('Operations').bhFieldName = 'operations_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Application__c').put('Operations', new FieldAPINameWrapper('', 'operations_bh_mins__c'));
                    }
                }
                // Application__c status fields ends here
                // Query__c status fields starts here
                if(lower == 'open_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Open')) {
                        objectStatusFieldsMap.get('Query__c').get('Open').tatFieldName = 'open_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Open', new FieldAPINameWrapper('open_tat_mins__c', ''));
                    }
                }
                if(lower == 'open_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Open')) {
                        objectStatusFieldsMap.get('Query__c').get('Open').bhFieldName = 'open_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Open', new FieldAPINameWrapper('', 'open_bh_mins__c'));
                    }
                }
                if(lower == 'closed_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Closed')) {
                        objectStatusFieldsMap.get('Query__c').get('Closed').tatFieldName = 'closed_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Closed', new FieldAPINameWrapper('closed_tat_mins__c', ''));
                    }
                }
                if(lower == 'closed_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Closed')) {
                        objectStatusFieldsMap.get('Query__c').get('Closed').bhFieldName = 'closed_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Closed', new FieldAPINameWrapper('', 'closed_bh_mins__c'));
                    }
                }
                if(lower == 'in_progress_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('In Progress')) {
                        objectStatusFieldsMap.get('Query__c').get('In Progress').tatFieldName = 'in_progress_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('In Progress', new FieldAPINameWrapper('in_progress_tat_mins__c', ''));
                    }
                }
                if(lower == 'in_progress_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('In Progress')) {
                        objectStatusFieldsMap.get('Query__c').get('In Progress').bhFieldName = 'in_progress_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('In Progress', new FieldAPINameWrapper('', 'in_progress_bh_mins__c'));
                    }
                }
                if(lower == 'resolved_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Resolved')) {
                        objectStatusFieldsMap.get('Query__c').get('Resolved').tatFieldName = 'resolved_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Resolved', new FieldAPINameWrapper('resolved_tat_mins__c', ''));
                    }
                }
                if(lower == 'resolved_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Resolved')) {
                        objectStatusFieldsMap.get('Query__c').get('Resolved').bhFieldName = 'resolved_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Resolved', new FieldAPINameWrapper('', 'resolved_bh_mins__c'));
                    }
                }
                if(lower == 'rejected_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Rejected')) {
                        objectStatusFieldsMap.get('Query__c').get('Rejected').tatFieldName = 'rejected_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Rejected', new FieldAPINameWrapper('rejected_tat_mins__c', ''));
                    }
                }
                if(lower == 'rejected_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Rejected')) {
                        objectStatusFieldsMap.get('Query__c').get('Rejected').bhFieldName = 'rejected_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Rejected', new FieldAPINameWrapper('', 'rejected_bh_mins__c'));
                    }
                }
                if(lower == 're_open_tat_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Re-Open')) {
                        objectStatusFieldsMap.get('Query__c').get('Re-Open').tatFieldName = 're_open_tat_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Re-Open', new FieldAPINameWrapper('re_open_tat_mins__c', ''));
                    }
                }
                if(lower == 're_open_bh_mins__c') {
                    if(objectStatusFieldsMap.get('Query__c').containsKey('Re-Open')) {
                        objectStatusFieldsMap.get('Query__c').get('Re-Open').bhFieldName = 're_open_bh_mins__c';
                    }
                    else {
                        objectStatusFieldsMap.get('Query__c').put('Re-Open', new FieldAPINameWrapper('', 're_open_bh_mins__c'));
                    }
                }
                // Query__c status fields ends here
            }
        }
    }*/

    /*private static FieldAPINameWrapper getFieldAPINameWrapper(String objectName, String status) {
        if(objectStatusFieldsMap.isEmpty()) {
            initializeObjectStatusFieldsMap();
        }
        if(objectName == 'Query__c') {
            return objectStatusFieldsMap.get('Query__c').get(status);
        }
        if(objectName == 'Application__c') {
            return objectStatusFieldsMap.get('Application__c').get(status);
        }
        return null;
    }*/

    /*public class FieldAPINameWrapper {
        public String tatFieldName;
        public String bhFieldName;
        public FieldAPINameWrapper(String tatFieldName, String bhFieldName) {
            this.tatFieldName = tatFieldName;
            this.bhFieldName = bhFieldName;
        }
    }*/

    /**
     * "Financial Sanction Hold" → "Financial_Sanction_Hold"
     * Leading/trailing whitespace trimmed; internal runs of whitespace
     * collapsed to single underscore.
     */
    /*private static String stageToFieldPrefix(String stage) {
        if (String.isBlank(stage)) { return null; }
        return stage.trim().replaceAll('\\s+', '_');
    }*/

    private static String stageToFieldPrefix(String objectName, String stage) {
        return objectStagePrefixMap.get(objectName).get(stage);
    }
}