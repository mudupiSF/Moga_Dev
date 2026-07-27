public with sharing class ApplicantSubService {

    private static final String TYPE_INDIVIDUAL     = 'Individual';
    private static final String TYPE_NON_INDIVIDUAL = 'Non-Individual';
    private static final String ROLE_BORROWER       = 'Borrower';
    private static final String STEP_DEDUPE_AND_ELIGIBILITY = 'Dedupe and Eligibility';

    // Sub-applicant caps per parent role (IN subs under an NI parent only).
    private static final Map<String, Integer> SUB_CAP_BY_ROLE = new Map<String, Integer>{
        'Guarantor'   => 10,
        'Co-Borrower' => 10,
        'Beneficiary' => 25
    };

    /**
     * Single-in-progress lock predicate. A non-borrower journey is "in progress" while any
     * active non-borrower applicant has not yet cleared Dedupe and Eligibility. Untouched
     * inactive sub shells are intentionally NOT counted (so abandoning a sub creation never
     * soft-locks the application); they are cleaned up on navigate-away.
     */
    public static Boolean isJourneyInProgress(List<Applicant__c> applicants) {
        if (applicants == null) return false;
        for (Applicant__c a : applicants) {
            if (a == null || a.In_Active_Applicant__c == true) continue;
            if (ROLE_BORROWER.equalsIgnoreCase(String.valueOf(a.Applicant_Type__c))) continue;
            if (!STEP_DEDUPE_AND_ELIGIBILITY.equalsIgnoreCase(
                    String.valueOf(a.Current_Loan_Stage_Complete__c))) {
                return true;
            }
        }
        return false;
    }

    /**
     * Returns the single active sub-applicant that is mid-edit (in progress) — i.e. an active
     * IN sub that has not yet cleared Dedupe and Eligibility. The single-in-progress lock
     * guarantees at most one such record.
     */
    public static Applicant__c getInProgressSub(List<Applicant__c> applicants) {
        if (applicants == null) return null;
        for (Applicant__c a : applicants) {
            if (a == null || a.In_Active_Applicant__c == true) continue;
            if (a.Is_Sub_Applicant__c != true) continue;
            if (!STEP_DEDUPE_AND_ELIGIBILITY.equalsIgnoreCase(
                    String.valueOf(a.Current_Loan_Stage_Complete__c))) {
                return a;
            }
        }
        return null;
    }

    /** SOQL convenience wrapper for callers that only have the application Id. */
    @AuraEnabled(cacheable=false)
    public static Boolean isAnyJourneyInProgress(Id applicationId) {
        if (applicationId == null) return false;
        return isJourneyInProgress([
            SELECT Id, Applicant_Type__c, In_Active_Applicant__c, Current_Loan_Stage_Complete__c
            FROM Applicant__c
            WHERE Application__c = :applicationId AND In_Active_Applicant__c = false
            WITH SECURITY_ENFORCED
        ]);
    }

    /**
     * Creates an inactive Individual sub-applicant shell under a Non-Individual parent.
     * The shell reserves the G1_1 slot/label and lets the record-driven Basic Details
     * screen load; it is activated on Basic Details NEXT (activateSubApplicantShell) or
     * discarded if the user abandons it (discardSubApplicantShell).
     */
    @AuraEnabled
    public static Map<String, Object> createSubApplicantShell(Id parentApplicantId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        if (parentApplicantId == null) {
            out.put('message', 'parentApplicantId is required.');
            return out;
        }
        try {
            List<Applicant__c> parents = [
                SELECT Id, Application__c, Applicant_Type__c, Applicant_Tab_Label__c,
                       Type__c, Is_Sub_Applicant__c, In_Active_Applicant__c
                FROM Applicant__c
                WHERE Id = :parentApplicantId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (parents.isEmpty()) {
                out.put('message', 'Parent applicant not found.');
                return out;
            }
            Applicant__c parent = parents[0];
            if (parent.In_Active_Applicant__c == true) {
                out.put('message', 'Parent applicant is inactive.');
                return out;
            }
            if (parent.Is_Sub_Applicant__c == true) {
                out.put('message', 'A sub-applicant cannot have its own sub-applicants.');
                return out;
            }
            if (!TYPE_NON_INDIVIDUAL.equalsIgnoreCase(String.valueOf(parent.Type__c))) {
                out.put('message', 'Sub-applicants can only be added under a Non-Individual applicant.');
                return out;
            }
            String role = String.valueOf(parent.Applicant_Type__c);
            if (!SUB_CAP_BY_ROLE.containsKey(role)) {
                out.put('message', 'Sub-applicants are not supported for this role.');
                return out;
            }

            // the active-sub cap, and the label index.
            List<Applicant__c> existingSubs = [
                SELECT Id, Applicant_Tab_Label__c, Applicant_Type__c,
                       In_Active_Applicant__c, Current_Loan_Stage_Complete__c
                FROM Applicant__c
                WHERE Parent_Applicant__c = :parentApplicantId
                AND Is_Sub_Applicant__c = true
                ORDER BY CreatedDate DESC
            ];

            // Reuse an untouched pending shell so repeated toggle / "+" clicks don't pile up records.
            for (Applicant__c s : existingSubs) {
                if (s.In_Active_Applicant__c == true && String.isBlank(s.Current_Loan_Stage_Complete__c)) {
                    out.put('isSuccess', true);
                    out.put('subApplicantId', s.Id);
                    out.put('tabLabel', s.Applicant_Tab_Label__c);
                    out.put('applicantType', s.Applicant_Type__c);
                    out.put('reused', true);
                    return out;
                }
            }

            // Single-in-progress lock: block starting a new sub while another non-borrower
            // journey (top-level applicant or an already-active sub) is still open.
            if (isAnyJourneyInProgress(parent.Application__c)) {
                out.put('message', 'Complete the in-progress applicant before adding another.');
                return out;
            }

            // Cap counts active subs only; label index uses the max existing suffix (collision-safe across deletes).
            Integer activeSubCount = 0;
            Integer maxIndex = 0;
            for (Applicant__c s : existingSubs) {
                if (s.In_Active_Applicant__c == false) activeSubCount++;
                String lbl = s.Applicant_Tab_Label__c;
                if (String.isNotBlank(lbl) && lbl.contains('_')) {
                    String suffix = lbl.substringAfterLast('_');
                    if (suffix.isNumeric() && Integer.valueOf(suffix) > maxIndex) {
                        maxIndex = Integer.valueOf(suffix);
                    }
                }
            }
            if (activeSubCount >= SUB_CAP_BY_ROLE.get(role)) {
                out.put('message', 'Maximum sub-applicants reached for ' + role + '.');
                return out;
            }
            String label = parent.Applicant_Tab_Label__c + '_' + String.valueOf(maxIndex + 1);

            Applicant__c sub = new Applicant__c(
                Application__c         = parent.Application__c,
                Applicant_Type__c      = role,
                Applicant_Tab_Label__c = label,
                Type__c                = TYPE_INDIVIDUAL,
                Parent_Applicant__c    = parentApplicantId,
                Is_Sub_Applicant__c    = true,
                Is_Primary__c          = false,
                In_Active_Applicant__c = true,
                // Backend shell: not surfaced on the UI until Basic Details NEXT activates it.
                Is_Journey_Exposed__c  = false
            );
            insert sub;

            out.put('isSuccess', true);
            out.put('subApplicantId', sub.Id);
            out.put('tabLabel', label);
            out.put('applicantType', role);
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    // =========================================================================
    // ITER 7 — Primary applicant (two levels: one Primary top-level per role,
    // and one Primary IN sub per NI parent that has subs). Mutually exclusive within scope.
    // =========================================================================

    /**
     * Sets the chosen applicant as the single Primary within its scope and clears the rest:
     *  - a sub-applicant   -> scope = the active IN subs of the SAME NI parent.
     *  - a top-level member -> scope = the active top-level members of the SAME role.
     * @param value true to set Primary, false to clear it (only this applicant is changed).
     */
    @AuraEnabled
    public static Map<String, Object> setPrimaryApplicant(Id applicantId, Boolean value) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        if (applicantId == null) {
            out.put('message', 'applicantId is required.');
            return out;
        }
        Boolean desiredOn = (value == null) ? true : value;
        try {
            List<Applicant__c> chosenList = [
                SELECT Id, Application__c, Applicant_Type__c, Is_Sub_Applicant__c, Parent_Applicant__c
                FROM Applicant__c
                WHERE Id = :applicantId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (chosenList.isEmpty()) {
                out.put('message', 'Applicant not found.');
                return out;
            }
            Applicant__c chosen = chosenList[0];

            List<Applicant__c> scopeApps;
            if (chosen.Is_Sub_Applicant__c == true && chosen.Parent_Applicant__c != null) {
                scopeApps = [
                    SELECT Id, Is_Primary__c
                    FROM Applicant__c
                    WHERE Parent_Applicant__c = :chosen.Parent_Applicant__c
                    AND Is_Sub_Applicant__c = true
                    AND In_Active_Applicant__c = false
                    WITH SECURITY_ENFORCED
                ];
            } else {
                String role = String.valueOf(chosen.Applicant_Type__c);
                scopeApps = [
                    SELECT Id, Is_Primary__c
                    FROM Applicant__c
                    WHERE Application__c = :chosen.Application__c
                    AND Applicant_Type__c = :role
                    AND Is_Sub_Applicant__c = false
                    AND In_Active_Applicant__c = false
                    WITH SECURITY_ENFORCED
                ];
            }

            List<Applicant__c> toUpdate = new List<Applicant__c>();
            for (Applicant__c a : scopeApps) {
                // when turning ON: chosen=true, everyone else=false (single Primary per scope).
                // when turning OFF: only the chosen flips to false; siblings untouched.
                Boolean target = (a.Id == applicantId) ? desiredOn
                                 : (desiredOn ? false : a.Is_Primary__c == true);
                if (a.Is_Primary__c != target) {
                    toUpdate.add(new Applicant__c(Id = a.Id, Is_Primary__c = target));
                }
            }
            if (!toUpdate.isEmpty()) update toUpdate;
            out.put('isSuccess', true);
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    /** Activates a filled sub-applicant shell on Basic Details NEXT (In_Active_Applicant__c = false). */
    @AuraEnabled
    public static Map<String, Object> activateSubApplicantShell(Id applicantId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        if (applicantId == null) {
            out.put('message', 'applicantId is required.');
            return out;
        }
        try {
            List<Applicant__c> subs = [
                SELECT Id, Is_Sub_Applicant__c, In_Active_Applicant__c
                FROM Applicant__c
                WHERE Id = :applicantId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (subs.isEmpty()) {
                out.put('message', 'Applicant not found.');
                return out;
            }
            Applicant__c sub = subs[0];
            if (sub.Is_Sub_Applicant__c == true && sub.In_Active_Applicant__c == true) {
                // Expose to the UI now that Basic Details is saved (tile gains View/Edit/Remove).
                update new Applicant__c(Id = applicantId, In_Active_Applicant__c = false, Is_Journey_Exposed__c = true);
            }
            out.put('isSuccess', true);
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    /**
     * Discards an untouched sub-applicant shell when the user abandons it before completing
     * Basic Details (toggle OFF / navigate away). Only deletes an inactive shell whose Basic
     * Details was never saved, so an in-progress or completed sub is never removed.
     */
    @AuraEnabled
    public static Map<String, Object> discardSubApplicantShell(Id applicantId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        if (applicantId == null) {
            out.put('message', 'applicantId is required.');
            return out;
        }
        try {
            List<Applicant__c> subs = [
                SELECT Id, Is_Sub_Applicant__c, In_Active_Applicant__c, Current_Loan_Stage_Complete__c
                FROM Applicant__c
                WHERE Id = :applicantId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (subs.isEmpty()) {
                out.put('isSuccess', true);
                return out;
            }
            Applicant__c sub = subs[0];
            if (sub.Is_Sub_Applicant__c == true
                    && sub.In_Active_Applicant__c == true
                    && String.isBlank(sub.Current_Loan_Stage_Complete__c)) {
                delete sub;
            }
            out.put('isSuccess', true);
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }
}