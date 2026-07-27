/**
 * TATEventRecorder — single entry point for writing TAT_Event__c rows.
 *
 * Data model (per call):
 *   - Application__c lookup is ALWAYS supplied by the caller.
 *   - Investigations__c / Query__c / Verification__c are optional; whichever
 *     are populated participate in identifying "which TAT row are we
 *     talking about" alongside Application__c.
 *   - User__c is contextual (the actor) and never used as a search key.
 *
 * State-transition semantics:
 *   - newValue set, oldValue null  → INSERT a fresh row (state entered).
 *   - oldValue set, newValue null  → SEARCH for the open row matching the
 *                                    caller's lookups (and whose
 *                                    New_Value__c equals the caller's
 *                                    oldValue) and close it (set End_Time).
 *   - both set                     → both: close the matching open row AND
 *                                    insert a new row carrying the new value.
 *                                    This is the standard "transition" call.
 *   - both null                    → rejected as invalid input.
 *
 * If a FINISH (close) request can't find an open row matching the lookup
 * combination, the recorder throws TATEventException so the caller fails
 * loudly rather than silently no-op'ing.
 *
 * Bulk-safe: one SOQL for all closes in a batch, one update DML, one insert
 * DML. Mix any number of insert-only, close-only, and transition inputs in
 * a single record(...) call.
 *
 * Duration fields (TAT_Minutes__c, TAT_Business_Minutes__c) are filled in
 * automatically on close — total minutes between Start_Time__c and the
 * close eventTime, wall-clock and against the org's default Business Hours
 * respectively.
 */
public with sharing class TATEventRecorder {

    public class TATEventException extends Exception {}

    /**
     * Input wrapper. All fields are public so callers can construct it
     * inline or via JSON.
     *
     *   applicationId      required — Application__c lookup target
     *   investigationsId   optional — Investigations__c lookup target
     *   queryId            optional — Query__c lookup target
     *   verificationId     optional — Verification__c lookup target
     *   userId             optional — defaults to current user
     *   stage              optional — descriptive category (Stage__c)
     *   substage           optional — descriptive subcategory (Substage__c)
     *   oldValue           optional — set to close the open row whose
     *                                 New_Value__c equals this
     *   newValue           optional — set to insert a new row with this
     *                                 value as its New_Value__c
     *   eventTime          optional — defaults to System.now()
     *
     * At least one of oldValue / newValue must be set.
     */
    public class Input {
        public Id       applicationId;
        public Id       investigationsId;
        public Id       queryId;
        public Id       verificationId;
        public Id       userId;
        public String   stage;
        public String   substage;
        public String   oldValue;
        public String   newValue;
        public Datetime eventTime;

        public Input() {}
    }

    /**
     * Per-input outcome. Either field can be null depending on the call:
     *   - Insert-only call  → opened set, closed null.
     *   - Close-only call   → closed set, opened null.
     *   - Transition call   → both set.
     */
    public class Result {
        public TAT_Event__c closed;
        public TAT_Event__c opened;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Public API
    // ──────────────────────────────────────────────────────────────────────

    public static Result record(Input inp) {
        return record(new List<Input>{ inp })[0];
    }

    public static List<Result> record(List<Input> inputs) {
        validate(inputs);

        // Phase 1 — for inputs that have an oldValue, locate the matching
        // open rows in a single SOQL pass.
        Map<Integer, TAT_Event__c> matchByIndex = locateOpenRows(inputs);

        Id bhId = resolveDefaultBusinessHoursId();

        // Phase 2 — make sure every Application about to get a new row has
        // a parent TAT_Summary__c to link to. Find-or-create in bulk.
        Set<Id> appIdsNeedingSummary = new Set<Id>();
        for (Input inp : inputs) {
            if (String.isNotBlank(inp.newValue)) {
                appIdsNeedingSummary.add(inp.applicationId);
            }
        }
        Map<Id, Id> summaryByApp = TATSummaryService.ensureSummariesExist(appIdsNeedingSummary);

        List<TAT_Event__c> toUpdate = new List<TAT_Event__c>();
        List<TAT_Event__c> toInsert = new List<TAT_Event__c>();

        // Phase 3 — apply close + build inserts, remember which input
        // produced which row(s) so we can return results in order.
        Map<Integer, TAT_Event__c> insertedByIndex = new Map<Integer, TAT_Event__c>();
        Map<Integer, TAT_Event__c> closedByIndex   = new Map<Integer, TAT_Event__c>();

        for (Integer i = 0; i < inputs.size(); i++) {
            Input inp = inputs[i];

            if (String.isNotBlank(inp.oldValue)) {
                TAT_Event__c open = matchByIndex.get(i);
                if (open == null) {
                    throw new TATEventException(
                        'No open TAT_Event__c found to close at index ' + i
                        + ' for Application__c=' + inp.applicationId
                        + ' / Investigations__c=' + inp.investigationsId
                        + ' / Query__c=' + inp.queryId
                        + ' / Verification__c=' + inp.verificationId
                        + '. No open row matches that lookup combination.'
                    );
                }
                applyClose(open, inp.eventTime, bhId);
                toUpdate.add(open);
                closedByIndex.put(i, open);
            }

            if (String.isNotBlank(inp.newValue)) {
                TAT_Event__c fresh = buildNewRow(inp, summaryByApp.get(inp.applicationId));
                toInsert.add(fresh);
                insertedByIndex.put(i, fresh);
            }
        }

        if (!toUpdate.isEmpty()) { update toUpdate; }
        if (!toInsert.isEmpty()) { insert toInsert; }

        List<Result> results = new List<Result>();
        for (Integer i = 0; i < inputs.size(); i++) {
            Result r = new Result();
            r.closed = closedByIndex.get(i);
            r.opened = insertedByIndex.get(i);
            results.add(r);
        }
        return results;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Internals
    // ──────────────────────────────────────────────────────────────────────

    private static void validate(List<Input> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            throw new TATEventException('inputs list is null or empty.');
        }
        for (Integer i = 0; i < inputs.size(); i++) {
            Input inp = inputs[i];
            if (inp == null) {
                throw new TATEventException('inputs[' + i + '] is null.');
            }
            if (inp.applicationId == null) {
                throw new TATEventException(
                    'inputs[' + i + '].applicationId is required (Application__c lookup).'
                );
            }
            if (String.isBlank(inp.oldValue) && String.isBlank(inp.newValue)) {
                throw new TATEventException(
                    'inputs[' + i + '] must set at least one of oldValue or newValue.'
                );
            }
            if (inp.eventTime == null) {
                inp.eventTime = System.now();
            }
            if (inp.userId == null) {
                inp.userId = UserInfo.getUserId();
            }
        }
    }

    /**
     * One SOQL covering every input that needs to find an open row.
     * Query is filtered by Application__c (always set) and End_Time__c = null,
     * then bucketed in memory by the lookup combination alone — Old_Value__c /
     * New_Value__c are payload on the row, not part of the identity.
     *
     * If multiple open rows share the same lookup combo (shouldn't happen in
     * a well-behaved workflow), the most recent (latest Start_Time__c) wins.
     */
    private static Map<Integer, TAT_Event__c> locateOpenRows(List<Input> inputs) {
        Set<Id> appIds = new Set<Id>();
        for (Input inp : inputs) {
            if (String.isNotBlank(inp.oldValue)) {
                appIds.add(inp.applicationId);
            }
        }

        Map<Integer, TAT_Event__c> matchByIndex = new Map<Integer, TAT_Event__c>();
        if (appIds.isEmpty()) {
            return matchByIndex;
        }

        List<TAT_Event__c> candidates = [
            SELECT Id,
                   Application__c, Investigations__c, Query__c, Verification__c,
                   Stage__c, Substage__c,
                   Old_Value__c, New_Value__c,
                   Start_Time__c, End_Time__c,
                   User__c
            FROM TAT_Event__c
            WHERE Application__c IN :appIds
              AND End_Time__c = null
            ORDER BY Start_Time__c ASC NULLS FIRST
        ];

        // ASC order means the newest open row for a given lookup combo
        // overwrites older ones in the map, so duplicates settle on the most recent.
        Map<String, TAT_Event__c> openByKey = new Map<String, TAT_Event__c>();
        for (TAT_Event__c e : candidates) {
            String key = compositeKey(
                e.Application__c, e.Investigations__c, e.Query__c, e.Verification__c
            );
            openByKey.put(key, e);
        }

        // Map each close-input to its row, removing from the map so two close
        // inputs in the same batch can't both bind to the same row.
        for (Integer i = 0; i < inputs.size(); i++) {
            Input inp = inputs[i];
            if (String.isBlank(inp.oldValue)) { continue; }
            String key = compositeKey(
                inp.applicationId, inp.investigationsId, inp.queryId, inp.verificationId
            );
            TAT_Event__c match = openByKey.get(key);
            if (match != null) {
                matchByIndex.put(i, match);
                openByKey.remove(key);
            }
        }
        return matchByIndex;
    }

    private static String compositeKey(Id appId, Id invId, Id qId, Id verId) {
        return String.valueOf(appId)
            + '|' + (invId == null ? '' : String.valueOf(invId))
            + '|' + (qId   == null ? '' : String.valueOf(qId))
            + '|' + (verId == null ? '' : String.valueOf(verId));
    }

    private static TAT_Event__c buildNewRow(Input inp, Id summaryId) {
        TAT_Event__c e = new TAT_Event__c();
        e.Application__c     = inp.applicationId;
        e.Investigations__c  = inp.investigationsId;
        e.Query__c           = inp.queryId;
        e.Verification__c    = inp.verificationId;
        e.User__c            = inp.userId;
        e.Stage__c           = inp.stage;
        e.Substage__c        = inp.substage;
        e.Old_Value__c       = inp.oldValue;
        e.New_Value__c       = inp.newValue;
        e.Start_Time__c      = inp.eventTime;
        e.TAT_Summary__c     = summaryId;
        return e;
    }

    /**
     * Close an open row: set End_Time__c and fill the kept duration fields
     * (TAT_Minutes__c, TAT_Business_Minutes__c) as TOTAL minutes between
     * Start_Time__c and the close time. The Days/Hours/Seconds component
     * fields are no longer persisted (callers can derive them from minutes
     * if needed).
     */
    private static void applyClose(TAT_Event__c open, Datetime endDt, Id bhId) {
        open.End_Time__c = endDt;

        Long elapsedSec = TATDurationCalculator.elapsedSeconds(open.Start_Time__c, endDt);
        open.TAT_Minutes__c = elapsedSec / 60L;

        Long bizSec = (bhId == null)
            ? 0L
            : TATDurationCalculator.elapsedBusinessSeconds(bhId, open.Start_Time__c, endDt);
        open.TAT_Business_Minutes__c = bizSec / 60L;
    }

    private static Id resolveDefaultBusinessHoursId() {
        List<BusinessHours> defaultBh = [
            SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1
        ];
        return defaultBh.isEmpty() ? null : defaultBh[0].Id;
    }
}