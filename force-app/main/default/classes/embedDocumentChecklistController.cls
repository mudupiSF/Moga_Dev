/**
 * Creates or returns a Document_CheckList__c on demand.
 *
 * Idempotent: an existing active checklist for the same Application + Applicant
 * (Applicant optional for application-level checklists) + Applicant Type is reused
 * (matched by Document Master Key when a master is resolved, otherwise by Document
 * Type) instead of inserting a duplicate.
 *
 * The Document Master is resolved by Document_Name__c + Document_Category__c. Its
 * Master_Key__c is stamped onto Document_CheckList__c.Document_Master_Key__c and its
 * Max_Files_Allowed__c + File_Types_Allowed__c are returned so the caller can drive
 * upload limits. When no master matches, the file-rule values come back null.
 */
public with sharing class embedDocumentChecklistController {
    private static final String STAGE_POST_DISBURSEMENT = 'Post Disbursement';
    private static final String SUB_STAGE_POST_DISBURSEMENT_TRACKING = 'Post-Disbursement Tracking';

    public class ChecklistResult {
        @AuraEnabled public Id checklistId;
        @AuraEnabled public Decimal maxFilesAllowed;
        @AuraEnabled public String allowedFileTypes;
    }

    @AuraEnabled
    public static ChecklistResult getOrCreateChecklist(
        String applicationId,
        String applicantId,
        String applicantType,
        String assetId,
        String documentType,
        String documentName,
        String documentCategory
    ) {
        if (String.isBlank(applicationId)) {
            throw new AuraHandledException('Application is required to create a document checklist.');
        }
        try {
            return resolveOrCreate(
                applicationId,
                applicantId,
                applicantType,
                assetId,
                documentType,
                documentName,
                documentCategory
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (System.QueryException e) {
            // WITH SECURITY_ENFORCED surfaces missing object/field read access here.
            throw new AuraHandledException('Read access error (check field-level security): ' + e.getMessage());
        } catch (System.DmlException e) {
            throw new AuraHandledException('Could not save the document checklist (check field-level security): ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static ChecklistResult resolveOrCreate(
        String applicationIdStr,
        String applicantIdStr,
        String applicantType,
        String assetIdStr,
        String documentType,
        String documentName,
        String documentCategory
    ) {
        assertFieldsReadable(Document_Master__c.SObjectType,
            new List<String>{ 'Master_Key__c', 'Max_Files_Allowed__c', 'File_Types_Allowed__c' });
        assertFieldsReadable(Document_CheckList__c.SObjectType,
            new List<String>{ 'Document_Master_Key__c', 'Is_Ad_Hoc_Based__c' });

        Id applicationId = parseId(applicationIdStr, 'Application');
        Id applicantId   = String.isBlank(applicantIdStr) ? null : parseId(applicantIdStr, 'Applicant');
        Id requestedAssetId = String.isBlank(assetIdStr) ? null : parseId(assetIdStr, 'Asset');
        Id assetId = requestedAssetId;
        Id applicationLineItemId = getApplicationLineItemId(assetId, applicationId);

        // Only explicit OTHER uploads are ad-hoc. PDD checklist types such as
        // RC copy/Tax invoice must keep their own Document_Type__c buckets.
        Boolean isAdHoc =
            (String.isNotBlank(documentType) && documentType.equalsIgnoreCase('OTHER'));

        Document_Master__c master = resolveMaster(documentName, documentCategory);
        String masterKey = master == null ? null : master.Master_Key__c;

        // When the static Name+Category lookup yields nothing for an OTHER doc,
        // resolve the master from the Document Manager CMDT (OTHER -> DM-00074).
        if (String.isBlank(masterKey) && isAdHoc) {
            masterKey = resolveAdHocMasterKey();
        }

        ChecklistResult result = new ChecklistResult();
        result.maxFilesAllowed  = master == null ? null : master.Max_Files_Allowed__c;
        result.allowedFileTypes = master == null ? null : master.File_Types_Allowed__c;

        Id existingId = findExistingChecklist(
            applicationId,
            applicantId,
            applicantType,
            assetId,
            documentType,
            masterKey
        );
        if (existingId != null) {
            // Backfill the ad-hoc flag (+ master key) on a reused OTHER checklist
            // so the upload pop-up's "Show Preview" filter stays accurate.
            if (isAdHoc) {
                ensureAdHocFlag(existingId, masterKey);
            }
            if (assetId != null) {
                ensureScopeLinks(existingId, assetId, applicationLineItemId);
            } else if (applicationLineItemId != null) {
                ensureScopeLinks(existingId, null, applicationLineItemId);
            }
            result.checklistId = existingId;
            return result;
        }

        if (!Schema.sObjectType.Document_CheckList__c.isCreateable()) {
            throw new AuraHandledException('Insufficient access to create a document checklist.');
        }

        Document_CheckList__c row = new Document_CheckList__c(
            Application__c         = applicationId,
            Applicant__c           = applicantId,
            Applicant_Type__c      = applicantType,
            Asset__c               = assetId,
            Application_Line_Items__c = applicationLineItemId,
            Document_Type__c       = documentType,
            Document_Master_Key__c = masterKey,
            Is_Ad_Hoc_Based__c     = isAdHoc,
            Name                   = documentType,
            Is_Active__c           = true
        );
        insert row;
        result.checklistId = row.Id;
        return result;
    }

    /**
     * Master key for ad-hoc OTHER documents, resolved from the Document Manager
     * CMDT (Checklist_Document_Type__c = OTHER & Ad_Hoc_Based__c = true). Future
     * OTHER-type variations are mapped to their masters through this same field.
     */
    private static String resolveAdHocMasterKey() {
        for (Document_Manager__mdt dm : Document_Manager__mdt.getAll().values()) {
            if (dm.Ad_Hoc_Based__c == true
                    && String.isNotBlank(dm.Checklist_Document_Type__c)
                    && dm.Checklist_Document_Type__c.equalsIgnoreCase('OTHER')) {
                return dm.Document_Master_Key__c;
            }
        }
        return null;
    }

    private static void ensureAdHocFlag(Id checklistId, String masterKey) {
        if (!Schema.sObjectType.Document_CheckList__c.fields.Is_Ad_Hoc_Based__c.isUpdateable()) {
            return;
        }
        Document_CheckList__c upd = new Document_CheckList__c(
            Id = checklistId,
            Is_Ad_Hoc_Based__c = true
        );
        if (String.isNotBlank(masterKey)
                && Schema.sObjectType.Document_CheckList__c.fields.Document_Master_Key__c.isUpdateable()) {
            upd.Document_Master_Key__c = masterKey;
        }
        update upd;
    }

    private static void ensureScopeLinks(Id checklistId, Id assetId, Id applicationLineItemId) {
        if (assetId == null && applicationLineItemId == null) {
            return;
        }
        Document_CheckList__c upd = new Document_CheckList__c(Id = checklistId);
        Boolean shouldUpdate = false;
        if (Schema.sObjectType.Document_CheckList__c.fields.Asset__c.isUpdateable()) {
            upd.Asset__c = assetId;
            shouldUpdate = true;
        }
        if (applicationLineItemId != null
                && Schema.sObjectType.Document_CheckList__c.fields.Application_Line_Items__c.isUpdateable()) {
            upd.Application_Line_Items__c = applicationLineItemId;
            shouldUpdate = true;
        }
        if (shouldUpdate) {
            update upd;
        }
    }

    @AuraEnabled
    public static void stampChecklistNameFromLatestFile(String checklistId) {
        if (String.isBlank(checklistId)) {
            return;
        }
        try {
            Id clId = Id.valueOf(checklistId);
            List<Document_CheckList__c> cls = [
                SELECT Id, Name, Document_Type__c
                FROM Document_CheckList__c
                WHERE Id = :clId
                LIMIT 1
            ];
            if (cls.isEmpty()) {
                return;
            }

            Set<Id> cdIds = new Set<Id>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :clId
            ]) {
                cdIds.add(link.ContentDocumentId);
            }
            if (cdIds.isEmpty()) {
                return;
            }

            List<ContentVersion> cvs = [
                SELECT Title
                FROM ContentVersion
                WHERE ContentDocumentId IN :cdIds AND IsLatest = true
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (cvs.isEmpty()) {
                return;
            }

            String docType = cls[0].Document_Type__c == null ? '' : cls[0].Document_Type__c.trim();
            String title   = cvs[0].Title == null ? '' : cvs[0].Title.trim();
            String newName = (docType + '-' + title).trim();
            if (String.isBlank(newName)) {
                return;
            }
            // Document_CheckList__c.Name is an 80-char text field.
            if (newName.length() > 80) {
                newName = newName.substring(0, 80);
            }

            if (newName != cls[0].Name
                    && Schema.sObjectType.Document_CheckList__c.fields.Name.isUpdateable()) {
                cls[0].Name = newName;
                update cls[0];
            }
        } catch (Exception e) {
            // Best-effort rename — never block the upload flow.
        }
    }

    private static Id parseId(String value, String label) {
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid ' + label + ' Id received: "' + value + '"');
        }
    }

    private static void assertFieldsReadable(SObjectType sobjType, List<String> fieldApiNames) {
        Map<String, SObjectField> fieldMap = sobjType.getDescribe().fields.getMap();
        List<String> missing = new List<String>();
        for (String apiName : fieldApiNames) {
            SObjectField field = fieldMap.get(apiName);
            if (field == null || !field.getDescribe().isAccessible()) {
                missing.add(apiName);
            }
        }
        if (!missing.isEmpty()) {
            throw new AuraHandledException(
                'You are missing read access (field-level security) on ' +
                sobjType.getDescribe().getName() + ': ' + String.join(missing, ', ') +
                '. Ask your administrator to enable these fields for your profile.'
            );
        }
    }

    private static Document_Master__c resolveMaster(String documentName, String documentCategory) {
        if (String.isBlank(documentName) || String.isBlank(documentCategory)) {
            return null;
        }
        List<Document_Master__c> masters = [
            SELECT Id, Name, Master_Key__c, Max_Files_Allowed__c, File_Types_Allowed__c
            FROM Document_Master__c
            WHERE Document_Name__c = :documentName
              AND Document_Category__c = :documentCategory
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return masters.isEmpty() ? null : masters[0];
    }

    private static Id findExistingChecklist(
        Id applicationId,
        Id applicantId,
        String applicantType,
        Id assetId,
        String documentType,
        String masterKey
    ) {
        String normalizedApplicantType = String.isBlank(applicantType) ? null : applicantType.trim();
        List<Document_CheckList__c> rows;
        if (assetId != null) {
            rows = [
                SELECT Id, Document_Master_Key__c, Document_Type__c, Applicant_Type__c, Application_Line_Items__c
                FROM Document_CheckList__c
                WHERE Application__c = :applicationId
                  AND Asset__c = :assetId
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
            ];
        } else {
            rows = [
                SELECT Id, Document_Master_Key__c, Document_Type__c, Applicant_Type__c, Application_Line_Items__c
                FROM Document_CheckList__c
                WHERE Application__c = :applicationId
                  AND Applicant__c = :applicantId
                  AND Asset__c = null
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
            ];
        }
        List<Document_CheckList__c> candidateRows = new List<Document_CheckList__c>();
        for (Document_CheckList__c row : rows) {
            if (String.isBlank(normalizedApplicantType)) {
                candidateRows.add(row);
            } else {
                String existingApplicantType = String.isBlank(row.Applicant_Type__c)
                    ? null
                    : row.Applicant_Type__c.trim();
                if (String.isNotBlank(existingApplicantType)
                    && existingApplicantType.equalsIgnoreCase(normalizedApplicantType)) {
                    candidateRows.add(row);
                }
            }
        }
        if (String.isNotBlank(masterKey)) {
            for (Document_CheckList__c row : candidateRows) {
                if (row.Document_Master_Key__c == masterKey) {
                    return row.Id;
                }
            }
            for (Document_CheckList__c row : candidateRows) {
                if (String.isBlank(row.Document_Master_Key__c) && row.Document_Type__c == documentType) {
                    if (Schema.sObjectType.Document_CheckList__c.fields.Document_Master_Key__c.isUpdateable()) {
                        update new Document_CheckList__c(Id = row.Id, Document_Master_Key__c = masterKey);
                    }
                    return row.Id;
                }
            }
            return null;
        }
        for (Document_CheckList__c row : candidateRows) {
            if (row.Document_Type__c == documentType) {
                return row.Id;
            }
        }
        return null;
    }

    private static Id getApplicationLineItemId(Id assetId, Id applicationId) {
        if (assetId == null || applicationId == null) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT Application_Line_Items__c
            FROM Asset__c
            WHERE Id = :assetId
              AND (Applicant__r.Application__c = :applicationId OR Application_Line_Items__r.Application__c = :applicationId)
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Application_Line_Items__c;
    }

    private static Boolean isPostDisbursementTrackingStage(Id applicationId) {
        if (applicationId == null) {
            return false;
        }
        List<Application__c> applications = [
            SELECT Stage__c, Sub_Stage__c
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return false;
        }
        Application__c app = applications[0];
        String stage = String.isNotBlank(app.Stage__c) ? app.Stage__c.trim() : '';
        String subStage = String.isNotBlank(app.Sub_Stage__c) ? app.Sub_Stage__c.trim() : '';
        return stage.equalsIgnoreCase(STAGE_POST_DISBURSEMENT)
            && subStage.equalsIgnoreCase(SUB_STAGE_POST_DISBURSEMENT_TRACKING);
    }
}