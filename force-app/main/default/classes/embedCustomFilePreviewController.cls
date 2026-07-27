/**
 *   The LWC renders a 3-level hierarchy
 *     LWC (root) → Document Checklists → File Tiles (ContentVersions).
 *
 *   Cloud-vs-Rain split (user metaphor):
 *     Dock Panel = "the cloud" — decides WHICH checklists matter for the
 *       Application + Applicant (it may also create ad-hoc checklists via
 *       `embedDocumentChecklist` orchestrator).
 *     embedCustomFilePreview = "the rain" — given a list of Checklist IDs,
 *       it renders, manages files, and emits events. No discovery query.
 *
 *   File linking (1:N): EXCLUSIVELY via ContentDocumentLink.
 *   
 *
 * Methods:
 *   getChecklistsByIds(List<Id> checklistIds)

 *       (1) Document_CheckList__c WHERE Id IN :ids AND Is_Active__c = true
 *       (2) ContentDocumentLink   WHERE LinkedEntityId IN :ids
 *       (3) ContentVersion        WHERE ContentDocumentId IN :allDocIds
 *                                 AND IsLatest = true
 *     Returns ChecklistDTOs with their files[] in CDL-link order
 *     (most-recently-created file first per checklist).
 *
 *   getFilesForChecklist(checklistId)
 *     Per-checklist refresh.
 *
 *   deleteAllFilesForChecklist(checklistId)
 *     Deletes every ContentDocument linked to a single checklist. CDL-only.
 *
 *   deleteFile(contentVersionId)         single-tile delete
 *   getFileContentBase64(contentVersionId) excel preview support
 *   runFilePermissions(...)              optional Apex validator hook
 *   getUserSessionId()                   VF bridge for jsforce in preview LWCs
 */
public with sharing class embedCustomFilePreviewController {
    private static final String STAGE_POST_DISBURSEMENT = 'Post Disbursement';
    private static final String SUB_STAGE_POST_DISBURSEMENT_TRACKING = 'Post-Disbursement Tracking';
    private static final List<String> PDD_DOCUMENT_TYPES = new List<String>{
        'RC copy',
        'Tax invoice',
        'Insurance policy',
        'Form 34 (HP endorsement)',
        'Delivery challan'
    };

    // =========================================================================
    // ── DTO ──────────────────────────────────────────────────────────────────
    // =========================================================================
    public class ChecklistDTO {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String documentType;
        @AuraEnabled public String applicantType;
        @AuraEnabled public String documentCategory;       // from Document_Master__c lookup
        @AuraEnabled public String documentSubCategory;    // from Document_Master__c lookup
        @AuraEnabled public Id     applicantId;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isAdHocBased;        // dock ad-hoc (OTHER) capture flag
        @AuraEnabled public List<ContentVersion> files;
    }

    // =========================================================================
    // ── session (VF bridge for jsforce in child preview LWCs) ────────────────
    // =========================================================================
    @AuraEnabled(cacheable=true)
    public static String getUserSessionId() {
        try {
            String vfContent = Test.isRunningTest()
                ? 'Start_Of_Session_IdSESSION_IDEnd_Of_Session_Id'
                : Page.GETSessionId.getContent().toString();
            Integer startIdx = vfContent.indexOf('Start_Of_Session_Id') + 'Start_Of_Session_Id'.length();
            Integer endIdx   = vfContent.indexOf('End_Of_Session_Id');
            return vfContent.substring(startIdx, endIdx);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // ── PRIMARY DRIVER — bulk checklists + files by IDs ──────────────────────
    // =========================================================================

    @AuraEnabled
    public static List<ChecklistDTO> getChecklistsByIds(List<Id> checklistIds) {
        if (checklistIds == null || checklistIds.isEmpty()) {
            return new List<ChecklistDTO>();
        }
        try {
            // 1) Active checklists (preserve caller's input order — the Dock
            //    Panel will pass them in display order).
            Map<Id, Document_CheckList__c> checklistMap = new Map<Id, Document_CheckList__c>([
                SELECT Id, Name, Document_Type__c, Applicant_Type__c, Applicant__c,
                       Is_Active__c, Is_Ad_Hoc_Based__c
                FROM   Document_CheckList__c
                WHERE  Id IN :checklistIds
                AND    Is_Active__c = true
            ]);

            // 2) ContentDocumentLinks for ALL checklists in one query.
            Map<Id, List<Id>> checklistToCdIds = new Map<Id, List<Id>>();
            Set<Id>          allCdIds         = new Set<Id>();
            for (ContentDocumentLink cdl : [
                SELECT LinkedEntityId, ContentDocumentId
                FROM   ContentDocumentLink
                WHERE  LinkedEntityId IN :checklistIds
            ]) {
                if (!checklistToCdIds.containsKey(cdl.LinkedEntityId)) {
                    checklistToCdIds.put(cdl.LinkedEntityId, new List<Id>());
                }
                checklistToCdIds.get(cdl.LinkedEntityId).add(cdl.ContentDocumentId);
                allCdIds.add(cdl.ContentDocumentId);
            }

            // 3) All latest ContentVersions for all the CDL-linked documents.
            Map<Id, ContentVersion> cvByContentDoc = new Map<Id, ContentVersion>();
            if (!allCdIds.isEmpty()) {
                for (ContentVersion cv : [
                    SELECT Id, Title, FileExtension, FileType, ContentSize,
                           LastModifiedDate, CreatedDate, VersionNumber,
                           ContentDocumentId, PathOnClient,
                           CreatedBy.Name
                    FROM   ContentVersion
                    WHERE  ContentDocumentId IN :allCdIds
                    AND    IsLatest = true
                    ORDER BY CreatedDate DESC
                ]) {
                    cvByContentDoc.put(cv.ContentDocumentId, cv);
                }
            }

            // 4) Compose DTOs in the SAME ORDER the caller asked for.
            List<ChecklistDTO> out = new List<ChecklistDTO>();
            for (Id cid : checklistIds) {
                if (!checklistMap.containsKey(cid)) continue;
                Document_CheckList__c c = checklistMap.get(cid);
                ChecklistDTO dto         = new ChecklistDTO();
                dto.id                   = c.Id;
                dto.name                 = String.isBlank(c.Name) ? c.Document_Type__c : c.Name;
                dto.documentType         = c.Document_Type__c;
                dto.applicantType        = c.Applicant_Type__c;
                dto.documentCategory     = '';    // Document_Master__c lookup
                dto.documentSubCategory  = '';    // Document_Master__c lookup
                dto.applicantId          = c.Applicant__c;
                dto.isActive             = c.Is_Active__c;
                dto.isAdHocBased         = c.Is_Ad_Hoc_Based__c == true;

                List<ContentVersion> files = new List<ContentVersion>();
                if (checklistToCdIds.containsKey(c.Id)) {
                    for (Id cdId : checklistToCdIds.get(c.Id)) {
                        ContentVersion cv = cvByContentDoc.get(cdId);
                        if (cv != null) files.add(cv);
                    }
                }
                dto.files = files;
                out.add(dto);
            }
            return out;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // ── Dock Panel entry — resolve a whole Application's active checklists ────
    // =========================================================================

    @AuraEnabled
    public static List<ChecklistDTO> getChecklistsByApplicationId(Id applicationId) {
        if (applicationId == null) {
            return new List<ChecklistDTO>();
        }
        List<Id> ids = new List<Id>();
        for (Document_CheckList__c c : [
            SELECT Id
            FROM   Document_CheckList__c
            WHERE  Application__c = :applicationId
            AND    Is_Active__c = true
            ORDER BY LastModifiedDate DESC
        ]) {
            ids.add(c.Id);
        }
        return getChecklistsByIds(ids);
    }

    // =========================================================================
    // ── files-only refresh (per-checklist round trip) ────────────────────────
    // =========================================================================
    @AuraEnabled
    public static List<ContentVersion> getFilesForChecklist(Id checklistId) {
        if (checklistId == null) return new List<ContentVersion>();
        try {
            Set<Id> cdIds = new Set<Id>();
            for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId
                FROM   ContentDocumentLink
                WHERE  LinkedEntityId = :checklistId
            ]) {
                cdIds.add(cdl.ContentDocumentId);
            }
            if (cdIds.isEmpty()) return new List<ContentVersion>();
            return [
                SELECT Id, Title, FileExtension, FileType, ContentSize,
                       LastModifiedDate, CreatedDate, VersionNumber,
                       ContentDocumentId, PathOnClient, CreatedBy.Name
                FROM   ContentVersion
                WHERE  ContentDocumentId IN :cdIds
                AND    IsLatest = true
                ORDER BY CreatedDate DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // ── delete single file (file-tile action) ────────────────────────────────
    // =========================================================================
    @AuraEnabled
    public static void deleteFile(Id contentVersionId) {
        try {
            ContentVersion cv = [
                SELECT ContentDocumentId
                FROM   ContentVersion
                WHERE  Id = :contentVersionId LIMIT 1
            ];
            delete new ContentDocument(Id = cv.ContentDocumentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // ── delete all files for a checklist (header action) ─────────────────────
    // =========================================================================
    @AuraEnabled
    public static Integer deleteAllFilesForChecklist(Id checklistId) {
        if (checklistId == null) return 0;
        try {
            Set<Id> cdIds = new Set<Id>();
            for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId
                FROM   ContentDocumentLink
                WHERE  LinkedEntityId = :checklistId
            ]) {
                cdIds.add(cdl.ContentDocumentId);
            }
            if (cdIds.isEmpty()) return 0;

            List<ContentDocument> docs = new List<ContentDocument>();
            for (Id cd : cdIds) docs.add(new ContentDocument(Id = cd));
            delete docs;
            return docs.size();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // ── base64 read (excel child) ────────────────────────────────────────────
    // =========================================================================
    @AuraEnabled
    public static String getFileContentBase64(Id contentVersionId) {
        try {
            ContentVersion cv = [
                SELECT VersionData FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1
            ];
            return EncodingUtil.base64Encode(cv.VersionData);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // ── bulk permission check (file-tile validator hook) ─────────────────────
    // =========================================================================
    @AuraEnabled
    public static Map<Id, FilePermissionResult> runFilePermissions(
        String validatorClassName,
        List<Id> contentVersionIds,
        Id recordId
    ) {
        Map<Id, FilePermissionResult> result = new Map<Id, FilePermissionResult>();

        if (String.isBlank(validatorClassName)) {
            for (Id cvId : contentVersionIds) {
                result.put(cvId, new FilePermissionResult());
            }
            return result;
        }

        try {
            Type t = Type.forName(validatorClassName);
            if (t == null) {
                for (Id cvId : contentVersionIds) {
                    FilePermissionResult r = new FilePermissionResult();
                    r.canEdit     = false;
                    r.canDelete   = false;
                    r.canDownload = false;
                    r.errors      = new List<String>{ 'Validator class not found: ' + validatorClassName };
                    result.put(cvId, r);
                }
                return result;
            }

            FileValidator validator = (FileValidator) t.newInstance();
            Map<Id, FilePermissionResult> validatorResult =
                validator.allowEditDeleteFileUpload(contentVersionIds, recordId);

            for (Id cvId : contentVersionIds) {
                if (validatorResult != null && validatorResult.containsKey(cvId)) {
                    FilePermissionResult r = validatorResult.get(cvId);
                    result.put(cvId, r != null ? r : new FilePermissionResult());
                } else {
                    result.put(cvId, new FilePermissionResult());
                }
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // ── ad-hoc add options ───────────────────────────────
    //   Document Type is fixed to "OTHER" for ad-hoc documents; Applicant Type
    //   comes from the live Document_CheckList__c
    // =========================================================================
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAdhocAddOptions(Id applicationId) {
        Boolean isPddTrackingMode = isPostDisbursementTrackingStage(applicationId);
        List<Map<String, String>> applicantTypes = new List<Map<String, String>>();
        if (!isPddTrackingMode) {
            Schema.DescribeFieldResult dfr =
                Document_CheckList__c.Applicant_Type__c.getDescribe();
            for (Schema.PicklistEntry ple : dfr.getPicklistValues()) {
                if (ple.isActive()) {
                    applicantTypes.add(new Map<String, String>{
                        'label' => ple.getLabel(),
                        'value' => ple.getValue()
                    });
                }
            }
        }

        List<Map<String, String>> documentTypeOptions = new List<Map<String, String>>();
        if (isPddTrackingMode) {
            for (String pddType : PDD_DOCUMENT_TYPES) {
                documentTypeOptions.add(new Map<String, String>{ 'label' => pddType, 'value' => pddType });
            }
        } else {
            documentTypeOptions.add(new Map<String, String>{ 'label' => 'OTHER', 'value' => 'OTHER' });
        }

        List<Map<String, String>> assetOptions = new List<Map<String, String>>();
        if (isPddTrackingMode && applicationId != null) {
            Integer assetSequence = 0;
            for (Asset__c assetRow : [
                SELECT Id, Name
                FROM Asset__c
                WHERE Applicant__r.Application__c = :applicationId
                   OR Application_Line_Items__r.Application__c = :applicationId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
            ]) {
                assetSequence++;
                String assetLabel;
                if (String.isNotBlank(assetRow.Name)) {
                    assetLabel = assetRow.Name;
                } else {
                    String assetIdValue = String.valueOf(assetRow.Id);
                    String shortSuffix = assetIdValue.length() > 6
                        ? assetIdValue.substring(assetIdValue.length() - 6)
                        : assetIdValue;
                    assetLabel = 'Asset ' + String.valueOf(assetSequence) + ' - ' + shortSuffix;
                }
                assetOptions.add(new Map<String, String>{
                    'label' => assetLabel,
                    'value' => String.valueOf(assetRow.Id)
                });
            }
        }

        return new Map<String, Object>{
            'isPddTrackingMode' => isPddTrackingMode,
            'documentTypeOptions' => documentTypeOptions,
            'applicantTypeOptions' => applicantTypes,
            'assetOptions' => assetOptions
        };
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