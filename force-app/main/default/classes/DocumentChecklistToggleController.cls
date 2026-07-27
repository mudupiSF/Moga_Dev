public with sharing class DocumentChecklistToggleController {

    private static final String DOCUMENT_TYPE_PAN = 'PAN';
    private static final String DOCUMENT_TYPE_FORM_60 = 'Form 60';
    private static final Set<String> SUPPORTED_DOCUMENT_TYPES = new Set<String>{ DOCUMENT_TYPE_PAN, DOCUMENT_TYPE_FORM_60 };

    /**
     * Activates the Document_CheckList__c row whose Document_Type__c matches activeDocumentType
     * for the given applicant, and deactivates any sibling row for the opposite document type.
     * Returns true when at least one row was updated.
     */
    @AuraEnabled
    public static Boolean toggleDocumentActivation(Id applicantId, String activeDocumentType) {
        if (applicantId == null || String.isBlank(activeDocumentType)) {
            return false;
        }
        String normalized = activeDocumentType.trim();
        if (!SUPPORTED_DOCUMENT_TYPES.contains(normalized)) {
            return false;
        }
        try {
            List<Document_CheckList__c> rows = [
                SELECT Id, Document_Type__c, Is_Active__c
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicantId
                  AND Document_Type__c IN :SUPPORTED_DOCUMENT_TYPES
                WITH SECURITY_ENFORCED
            ];
            if (rows.isEmpty()) {
                return false;
            }
            List<Document_CheckList__c> updates = new List<Document_CheckList__c>();
            for (Document_CheckList__c row : rows) {
                Boolean desiredActive = normalized.equalsIgnoreCase(row.Document_Type__c);
                if (row.Is_Active__c != desiredActive) {
                    row.Is_Active__c = desiredActive;
                    updates.add(row);
                }
            }
            if (updates.isEmpty()) {
                return false;
            }
            update updates;
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'DocumentChecklistToggleController.toggleDocumentActivation: ' + e.getMessage());
            throw new AuraHandledException('Unable to toggle document activation: ' + e.getMessage());
        }
    }

    /**
     * Marks the specified Document_CheckList__c row inactive and clears its file linkage so a fresh
     * upload can replace it cleanly. Returns true when the row was deactivated.
     */
    @AuraEnabled
    public static Boolean deactivateDocument(Id documentChecklistId) {
        if (documentChecklistId == null) {
            return false;
        }
        try {
            List<Document_CheckList__c> rows = [
                SELECT Id, Is_Active__c, ContentVersionId__c
                FROM Document_CheckList__c
                WHERE Id = :documentChecklistId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                return false;
            }
            Document_CheckList__c row = rows[0];
            Boolean alreadyInactive = row.Is_Active__c == false && String.isBlank(row.ContentVersionId__c);
            if (alreadyInactive) {
                return false;
            }
            row.Is_Active__c = false;
            row.ContentVersionId__c = null;
            update row;
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'DocumentChecklistToggleController.deactivateDocument: ' + e.getMessage());
            throw new AuraHandledException('Unable to deactivate document: ' + e.getMessage());
        }
    }
}