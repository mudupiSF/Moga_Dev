public with sharing class ApplicantCloneService {

    private static final String ROLE_BENEFICIARY    = 'Beneficiary';
    private static final String ROLE_GUARANTOR      = 'Guarantor';
    private static final String TYPE_NON_INDIVIDUAL = 'Non-Individual';
    private static final String GUARANTOR_PREFIX    = 'G';

    // Direct children -> API name of the lookup/master-detail field pointing to Applicant__c.
    private static final Map<String, String> DIRECT_CHILD_APPLICANT_FIELD = new Map<String, String>{
        'Applicant_KYC__c'         => 'Applicant__c',
        'Applicant_Address__c'     => 'Applicant__c',
        'Applicant_Employment__c'  => 'Applicant__c',
        'Applicant_Income__c'      => 'Applicant__c',
        'Applicant_Obligations__c' => 'Applicant__c',
        'Networth_Details__c'      => 'Applicant__c',
        'Fleet_Details__c'         => 'Applicant__c',
        'Reference__c'             => 'Applicant__c'
    };

    // Secondary child-record lookups on the checklist objects that must follow the clone.
    private static final List<String> CHECKLIST_CHILD_LOOKUPS = new List<String>{
        'Applicant_KYC__c', 'Applicant_Income__c', 'Applicant_Employment__c', 'Applicant_Address__c'
    };

    /**
     * idempotently create an inactive Guarantor clone-shell for a Non-Individual
     * Beneficiary. The shell reserves the G# slot/label; child records are deep-cloned later
     * when the Beneficiary clears Dedupe & Eligibility (see activateGuarantorClone...).
     */
    @AuraEnabled
    public static Map<String, Object> ensureGuarantorCloneShell(Id beneficiaryId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        if (beneficiaryId == null) {
            out.put('message', 'beneficiaryId is required.');
            return out;
        }
        try {
            List<Applicant__c> benes = [
                SELECT Id, Application__c, Type__c, Applicant_Type__c
                FROM Applicant__c
                WHERE Id = :beneficiaryId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (benes.isEmpty()) {
                out.put('message', 'Beneficiary not found.');
                return out;
            }
            Applicant__c bene = benes[0];
            if (!ROLE_BENEFICIARY.equalsIgnoreCase(String.valueOf(bene.Applicant_Type__c))
                    || !TYPE_NON_INDIVIDUAL.equalsIgnoreCase(String.valueOf(bene.Type__c))) {
                out.put('message', 'Clone is only available for Non-Individual Beneficiaries.');
                return out;
            }

            List<Applicant__c> existing = [
                SELECT Id
                FROM Applicant__c
                WHERE Parent_Applicant__c = :beneficiaryId
                AND Is_Sub_Applicant__c = false
                AND Applicant_Type__c = :ROLE_GUARANTOR
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                out.put('isSuccess', true);
                out.put('cloneId', existing[0].Id);
                out.put('message', 'Guarantor clone already exists.');
                return out;
            }

            // Cap + next label across active guarantors and pending clone-shells.
            Integer guarantorCount = [
                SELECT COUNT()
                FROM Applicant__c
                WHERE Application__c = :bene.Application__c
                AND Applicant_Type__c = :ROLE_GUARANTOR
                AND Is_Sub_Applicant__c = false
            ];
            if (guarantorCount >= CustomerDedupeController.getMaxGuarantors()) {
                out.put('message', 'Maximum guarantors reached.');
                return out;
            }

            Applicant__c shell = new Applicant__c(
                Application__c = bene.Application__c,
                Applicant_Type__c = ROLE_GUARANTOR,
                Applicant_Tab_Label__c = GUARANTOR_PREFIX + String.valueOf(guarantorCount + 1),
                Type__c = TYPE_NON_INDIVIDUAL,
                Parent_Applicant__c = beneficiaryId,
                Is_Sub_Applicant__c = false,
                Is_Primary__c = false,
                In_Active_Applicant__c = true,
                // Backend clone shell: never surfaced on the UI until it is deep-cloned + activated.
                Is_Journey_Exposed__c = false
            );
            insert shell;
            out.put('isSuccess', true);
            out.put('cloneId', shell.Id);
            out.put('message', 'Guarantor clone created.');
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    /**
     * resolves the Beneficiary by tab label and, when a clone-shell
     * exists, deep-clones and activates it. Best-effort: never blocks the caller's navigation.
     */
    public static void activateGuarantorCloneForBeneficiaryByTabLabel(Id applicationId, String tabLabel) {
        if (applicationId == null || String.isBlank(tabLabel)) {
            return;
        }
        List<Applicant__c> benes = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :applicationId
            AND In_Active_Applicant__c = false
            AND Applicant_Type__c = :ROLE_BENEFICIARY
            AND Applicant_Tab_Label__c = :tabLabel.trim()
            LIMIT 1
        ];
        if (!benes.isEmpty()) {
            activateGuarantorCloneForBeneficiary(benes[0].Id);
        }
    }

    /** deep-clone the Beneficiary's QDE records into its Guarantor clone-shell and activate it. */
    public static void activateGuarantorCloneForBeneficiary(Id beneficiaryId) {
        if (beneficiaryId == null) {
            return;
        }
        List<Applicant__c> shells = [
            SELECT Id
            FROM Applicant__c
            WHERE Parent_Applicant__c = :beneficiaryId
            AND Is_Sub_Applicant__c = false
            AND Applicant_Type__c = :ROLE_GUARANTOR
            AND In_Active_Applicant__c = true
            LIMIT 1
        ];
        if (shells.isEmpty()) {
            return;
        }
        Id guarantorId = shells[0].Id;
        System.Savepoint sp = Database.setSavepoint();
        try {
            copyApplicantFields(beneficiaryId, guarantorId);
            Map<String, Map<Id, Id>> childIdMaps = cloneDirectChildren(beneficiaryId, guarantorId);
            Map<Id, Id> checklistIdMap = cloneChecklists(beneficiaryId, guarantorId, childIdMaps);
            duplicateChecklistFiles(checklistIdMap);
            cloneIntegrationChecklists(beneficiaryId, guarantorId, childIdMaps);
            // Expose the activated Guarantor clone on the UI (becomes removable like any active applicant).
            update new Applicant__c(Id = guarantorId, In_Active_Applicant__c = false, Is_Journey_Exposed__c = true);
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'ApplicantCloneService.activateGuarantorCloneForBeneficiary: ' + e.getMessage());
        }
    }

    private static void copyApplicantFields(Id sourceId, Id targetId) {
        List<Applicant__c> sources = Database.query(
            'SELECT FIELDS(ALL) FROM Applicant__c WHERE Id = :sourceId LIMIT 1'
        );
        if (sources.isEmpty()) {
            return;
        }
        Set<String> skip = new Set<String>{
            'id', 'applicant_type__c', 'applicant_tab_label__c', 'parent_applicant__c',
            'is_sub_applicant__c', 'is_primary__c', 'in_active_applicant__c', 'application__c'
        };
        Applicant__c target = (Applicant__c) copyFields(sources[0], Applicant__c.SObjectType, skip, true);
        target.Id = targetId;
        update target;
    }

    private static Map<String, Map<Id, Id>> cloneDirectChildren(Id sourceId, Id targetId) {
        Map<String, Map<Id, Id>> idMaps = new Map<String, Map<Id, Id>>();
        for (String objName : DIRECT_CHILD_APPLICANT_FIELD.keySet()) {
            String applicantField = DIRECT_CHILD_APPLICANT_FIELD.get(objName);
            Schema.SObjectType sot = Schema.getGlobalDescribe().get(objName);
            Map<Id, Id> idMap = new Map<Id, Id>();
            idMaps.put(objName, idMap);
            if (sot == null) {
                continue;
            }
            List<SObject> sources = Database.query(
                'SELECT FIELDS(ALL) FROM ' + objName + ' WHERE ' + applicantField + ' = :sourceId LIMIT 200'
            );
            if (sources.isEmpty()) {
                continue;
            }
            Set<String> skip = new Set<String>{ 'id', applicantField.toLowerCase() };
            List<SObject> clones = new List<SObject>();
            List<Id> order = new List<Id>();
            for (SObject s : sources) {
                SObject c = copyFields(s, sot, skip, false);
                c.put(applicantField, targetId);
                clones.add(c);
                order.add((Id) s.get('Id'));
            }
            insert clones;
            for (Integer i = 0; i < clones.size(); i++) {
                idMap.put(order[i], (Id) clones[i].get('Id'));
            }
        }
        return idMaps;
    }

    private static Map<Id, Id> cloneChecklists(Id sourceId, Id targetId, Map<String, Map<Id, Id>> childIdMaps) {
        Map<Id, Id> idMap = new Map<Id, Id>();
        List<Document_CheckList__c> sources = Database.query(
            'SELECT FIELDS(ALL) FROM Document_CheckList__c WHERE Applicant__c = :sourceId LIMIT 200'
        );
        if (sources.isEmpty()) {
            return idMap;
        }
        Set<String> skip = new Set<String>{ 'id', 'applicant__c' };
        for (String lk : CHECKLIST_CHILD_LOOKUPS) {
            skip.add(lk.toLowerCase());
        }
        List<Document_CheckList__c> clones = new List<Document_CheckList__c>();
        List<Id> order = new List<Id>();
        for (Document_CheckList__c s : sources) {
            Document_CheckList__c c = (Document_CheckList__c) copyFields(s, Document_CheckList__c.SObjectType, skip, false);
            c.Applicant__c = targetId;
            remapChildLookups(s, c, childIdMaps);
            clones.add(c);
            order.add(s.Id);
        }
        insert clones;
        for (Integer i = 0; i < clones.size(); i++) {
            idMap.put(order[i], clones[i].Id);
        }
        return idMap;
    }

    private static void cloneIntegrationChecklists(Id sourceId, Id targetId, Map<String, Map<Id, Id>> childIdMaps) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get('Integration_Checklist__c');
        if (sot == null) {
            return;
        }
        List<SObject> sources = Database.query(
            'SELECT FIELDS(ALL) FROM Integration_Checklist__c WHERE Applicant__c = :sourceId LIMIT 200'
        );
        if (sources.isEmpty()) {
            return;
        }
        Set<String> skip = new Set<String>{ 'id', 'applicant__c' };
        for (String lk : CHECKLIST_CHILD_LOOKUPS) {
            skip.add(lk.toLowerCase());
        }
        List<SObject> clones = new List<SObject>();
        for (SObject s : sources) {
            SObject c = copyFields(s, sot, skip, false);
            c.put('Applicant__c', targetId);
            remapChildLookups(s, c, childIdMaps);
            clones.add(c);
        }
        insert clones;
    }

    /** Re-points the checklist's secondary child lookups to the freshly-cloned child records. */
    private static void remapChildLookups(SObject source, SObject clone, Map<String, Map<Id, Id>> childIdMaps) {
        for (String lk : CHECKLIST_CHILD_LOOKUPS) {
            Id oldChild = (Id) source.get(lk);
            if (oldChild == null) {
                continue;
            }
            Map<Id, Id> m = childIdMaps.get(lk);
            if (m != null && m.containsKey(oldChild)) {
                clone.put(lk, m.get(oldChild));
            }
        }
    }

    /** Duplicates the file binaries attached to each source checklist onto its clone. */
    private static void duplicateChecklistFiles(Map<Id, Id> checklistIdMap) {
        if (checklistIdMap == null || checklistIdMap.isEmpty()) {
            return;
        }
        Set<Id> sourceIds = checklistIdMap.keySet();
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :sourceIds
        ];
        if (links.isEmpty()) {
            return;
        }
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) {
            docIds.add(l.ContentDocumentId);
        }
        Map<Id, ContentVersion> latestByDoc = new Map<Id, ContentVersion>();
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId, Title, PathOnClient, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
        ]) {
            latestByDoc.put(cv.ContentDocumentId, cv);
        }
        List<ContentVersion> newCvs = new List<ContentVersion>();
        List<Id> targetOrder = new List<Id>();
        for (ContentDocumentLink l : links) {
            ContentVersion src = latestByDoc.get(l.ContentDocumentId);
            Id newChecklistId = checklistIdMap.get(l.LinkedEntityId);
            if (src == null || newChecklistId == null) {
                continue;
            }
            newCvs.add(new ContentVersion(
                Title = src.Title,
                PathOnClient = String.isNotBlank(src.PathOnClient) ? src.PathOnClient : (String.isNotBlank(src.Title) ? src.Title : 'file'),
                VersionData = src.VersionData
            ));
            targetOrder.add(newChecklistId);
        }
        if (newCvs.isEmpty()) {
            return;
        }
        insert newCvs;
        Set<Id> newCvIds = new Set<Id>();
        for (ContentVersion cv : newCvs) {
            newCvIds.add(cv.Id);
        }
        Map<Id, Id> docByCv = new Map<Id, Id>();
        for (ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :newCvIds]) {
            docByCv.put(cv.Id, cv.ContentDocumentId);
        }
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        for (Integer i = 0; i < newCvs.size(); i++) {
            Id docId = docByCv.get(newCvs[i].Id);
            if (docId == null) {
                continue;
            }
            newLinks.add(new ContentDocumentLink(
                ContentDocumentId = docId,
                LinkedEntityId = targetOrder[i],
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }
        if (!newLinks.isEmpty()) {
            insert newLinks;
        }
    }

    /** Copies writable, non-skipped, populated fields from source into a new SObject of the same type. */
    private static SObject copyFields(SObject source, Schema.SObjectType sot, Set<String> skipLower, Boolean forUpdate) {
        Map<String, Schema.SObjectField> fieldMap = sot.getDescribe().fields.getMap();
        SObject dest = sot.newSObject();
        for (String fld : source.getPopulatedFieldsAsMap().keySet()) {
            if (skipLower.contains(fld.toLowerCase())) {
                continue;
            }
            Schema.SObjectField f = fieldMap.get(fld);
            if (f == null) {
                continue;
            }
            Schema.DescribeFieldResult dfr = f.getDescribe();
            if (dfr.isCalculated() || dfr.isAutoNumber()) {
                continue;
            }
            Boolean writable = forUpdate ? dfr.isUpdateable() : dfr.isCreateable();
            if (!writable) {
                continue;
            }
            dest.put(fld, source.get(fld));
        }
        return dest;
    }
}