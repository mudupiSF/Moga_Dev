/**
 * Reusable mandatory-document detection, tick, and validation engine.
 *
 * Backed by the Document_Manager__mdt dictionary (document name <-> checklist
 * Document_Type <-> aliases <-> Document Master key). Any KYC-screen section
 * (Additional Documents, Darpan, ...) can feed it a required-docs list, an
 * "any N of" adhoc list, and the checklist rows that actually carry a file, and
 * get back per-document collected flags + an overall validation result.
 *
 * Matching is token-based: a required document and an uploaded checklist row
 * resolve to the same canonical token when they refer to the same logical
 * document, whether the row carries a stamped Document_Master_Key__c, a known
 * checklist Document_Type, or a configured alias.
 */
public with sharing class MandatoryDocumentsService {

    // ── Dictionary (Document_Manager__mdt), cached once per module per txn ───
    private class DocEntry {
        String docName;
        String masterKey;
        String checklistType;
    }

    private static Map<String, Map<String, DocEntry>> byName  = new Map<String, Map<String, DocEntry>>();
    private static Map<String, Map<String, DocEntry>> byType  = new Map<String, Map<String, DocEntry>>();
    private static Map<String, Map<String, DocEntry>> byAlias = new Map<String, Map<String, DocEntry>>();
    private static Set<String> loadedModules = new Set<String>();

    private static void ensureDictionary(String module) {
        if (loadedModules.contains(module)) {
            return;
        }
        Map<String, DocEntry> n = new Map<String, DocEntry>();
        Map<String, DocEntry> t = new Map<String, DocEntry>();
        Map<String, DocEntry> a = new Map<String, DocEntry>();
        // getAll() = no SOQL query, all field values populated (this CMDT has no
        // Long Text Area fields, which are the only thing getAll() omits).
        for (Document_Manager__mdt dm : Document_Manager__mdt.getAll().values()) {
            if (String.isBlank(dm.Step_Module__c)
                || !module.equalsIgnoreCase(dm.Step_Module__c.trim())) {
                continue;
            }
            DocEntry e = new DocEntry();
            e.docName       = dm.Document_s__c;
            e.masterKey     = dm.Document_Master_Key__c;
            e.checklistType = dm.Checklist_Document_Type__c;
            if (String.isNotBlank(dm.Document_s__c)) {
                n.put(dm.Document_s__c.trim().toLowerCase(), e);
            }
            if (String.isNotBlank(dm.Checklist_Document_Type__c)) {
                t.put(dm.Checklist_Document_Type__c.trim().toLowerCase(), e);
            }
            if (String.isNotBlank(dm.Aliases__c)) {
                for (String aliasToken : dm.Aliases__c.split(';')) {
                    if (String.isNotBlank(aliasToken)) {
                        a.put(aliasToken.trim().toLowerCase(), e);
                    }
                }
            }
        }
        byName.put(module, n);
        byType.put(module, t);
        byAlias.put(module, a);
        loadedModules.add(module);
    }

    private static DocEntry lookup(String module, String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        ensureDictionary(module);
        String key = raw.trim().toLowerCase();
        DocEntry e = byName.get(module).get(key);
        if (e == null) { e = byType.get(module).get(key); }
        if (e == null) { e = byAlias.get(module).get(key); }
        return e;
    }

    /** Canonical identity token for a configured document name. */
    public static String tokenForName(String module, String name) {
        if (String.isBlank(name)) {
            return null;
        }
        DocEntry e = lookup(module, name);
        if (e != null && String.isNotBlank(e.masterKey)) {
            return 'MK:' + e.masterKey.trim().toUpperCase();
        }
        if (e != null && String.isNotBlank(e.docName)) {
            return 'NM:' + e.docName.trim().toLowerCase();
        }
        return 'RW:' + name.trim().toLowerCase();
    }

    /** Canonical identity token for an uploaded checklist row (prefers stamped master key). */
    public static String tokenForRow(String module, Document_CheckList__c row) {
        if (row == null) {
            return null;
        }
        if (String.isNotBlank(row.Document_Master_Key__c)) {
            return 'MK:' + row.Document_Master_Key__c.trim().toUpperCase();
        }
        return tokenForName(module, row.Document_Type__c);
    }

    /** Master key for a checklist Document_Type/name — use to stamp Document_Master_Key__c on save. */
    public static String masterKeyForType(String module, String docType) {
        DocEntry e = lookup(module, docType);
        return (e != null && String.isNotBlank(e.masterKey)) ? e.masterKey.trim() : null;
    }

    /** Build the token set from rows that already carry a file. */
    public static Set<String> buildUploadedTokens(String module, List<Document_CheckList__c> rowsWithFiles) {
        Set<String> tokens = new Set<String>();
        if (rowsWithFiles != null) {
            for (Document_CheckList__c row : rowsWithFiles) {
                String token = tokenForRow(module, row);
                if (String.isNotBlank(token)) {
                    tokens.add(token);
                }
            }
        }
        return tokens;
    }

    // ── Evaluation result (consumed directly by the LWC) ─────────────────────
    public class DocItem {
        @AuraEnabled public String name;
        @AuraEnabled public String masterKey;
        @AuraEnabled public Boolean isUploaded;
        public DocItem(String name, String masterKey, Boolean isUploaded) {
            this.name = name;
            this.masterKey = masterKey;
            this.isUploaded = isUploaded;
        }
    }

    public class EvalResult {
        @AuraEnabled public List<DocItem> requiredDocItems = new List<DocItem>();
        @AuraEnabled public List<DocItem> adhocDocItems = new List<DocItem>();
        @AuraEnabled public List<String> missingRequiredDocuments = new List<String>();
        @AuraEnabled public Integer adhocDocumentsRemaining = 0;
        @AuraEnabled public Integer adhocDocumentsHits = 0;
        @AuraEnabled public Boolean adhocGroupSatisfied = true;
        @AuraEnabled public Boolean documentsComplete = true;
        @AuraEnabled public String validationMessage;
    }

    /**
     * @param module          Document_Manager__mdt Step_Module to resolve against (e.g. 'KYC Details').
     * @param requiredDocs    must-have document names.
     * @param adhocDocs       "any N of" candidate document names.
     * @param adhocMin        minimum count required from adhocDocs (0 = none).
     * @param uploadedTokens  tokens from buildUploadedTokens() for rows that have a file.
     * @param alwaysCollected doc names to treat as collected regardless (e.g. 'PAN' captured elsewhere); null if none.
     */
    public static EvalResult evaluate(
        String module,
        List<String> requiredDocs,
        List<String> adhocDocs,
        Integer adhocMin,
        Set<String> uploadedTokens,
        Set<String> alwaysCollected
    ) {
        EvalResult res = new EvalResult();
        Set<String> tokens = uploadedTokens != null ? uploadedTokens : new Set<String>();
        Set<String> always = new Set<String>();
        if (alwaysCollected != null) {
            for (String s : alwaysCollected) {
                if (String.isNotBlank(s)) {
                    always.add(s.trim().toLowerCase());
                }
            }
        }
        Integer minN = adhocMin != null ? adhocMin : 0;

        if (requiredDocs != null) {
            for (String docName : requiredDocs) {
                String trimmed = docName != null ? docName.trim() : null;
                if (String.isBlank(trimmed)) {
                    continue;
                }
                Boolean present = always.contains(trimmed.toLowerCase())
                    || tokens.contains(tokenForName(module, trimmed));
                res.requiredDocItems.add(new DocItem(trimmed, masterKeyForType(module, trimmed), present));
                if (!present) {
                    res.missingRequiredDocuments.add(trimmed);
                }
            }
        }

        Integer hits = 0;
        if (adhocDocs != null) {
            for (String docName : adhocDocs) {
                String trimmed = docName != null ? docName.trim() : null;
                if (String.isBlank(trimmed)) {
                    continue;
                }
                Boolean present = tokens.contains(tokenForName(module, trimmed));
                if (present) {
                    hits++;
                }
                res.adhocDocItems.add(new DocItem(trimmed, masterKeyForType(module, trimmed), present));
            }
        }
        res.adhocDocumentsHits = hits;
        res.adhocDocumentsRemaining = minN > hits ? minN - hits : 0;
        res.adhocGroupSatisfied = res.adhocDocItems.isEmpty() || res.adhocDocumentsRemaining == 0;
        res.documentsComplete = res.missingRequiredDocuments.isEmpty() && res.adhocDocumentsRemaining == 0;
        res.validationMessage = buildMessage(res.missingRequiredDocuments, res.adhocDocumentsRemaining);
        return res;
    }

    /** Default validation message. Callers may ignore this and build their own. */
    public static String buildMessage(List<String> missing, Integer adhocRemaining) {
        List<String> parts = new List<String>();
        if (missing != null && !missing.isEmpty()) {
            parts.add('Please upload the following mandatory documents: ' + String.join(missing, ', '));
        }
        if (adhocRemaining != null && adhocRemaining > 0) {
            parts.add('Upload at least ' + adhocRemaining + ' more document(s) from the optional list.');
        }
        return parts.isEmpty() ? null : String.join(parts, ' ');
    }
}