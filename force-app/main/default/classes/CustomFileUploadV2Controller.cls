public with sharing class CustomFileUploadV2Controller {

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

    /**
     * Returns all ContentVersion records linked to a given recordId,
     * ordered newest first. Used by CustomFilePreviewAndEdit to list files.
     */
    @AuraEnabled(cacheable=true)
    public static List<ContentVersion> getFilesForRecord(Id recordId) {
        try {
            Set<Id> cdIds = new Set<Id>();
            for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId
                FROM   ContentDocumentLink
                WHERE  LinkedEntityId = :recordId
            ]) {
                cdIds.add(cdl.ContentDocumentId);
            }
            if (cdIds.isEmpty()) return new List<ContentVersion>();
            return [
                SELECT Id, Title, FileExtension, FileType, ContentSize,
                       LastModifiedDate, CreatedDate, VersionNumber,
                       ContentDocumentId, PathOnClient,
                       CreatedBy.Name
                FROM   ContentVersion
                WHERE  ContentDocumentId IN :cdIds
                AND    IsLatest = true
                ORDER BY CreatedDate DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Deletes a ContentDocument (and all its versions) by ContentVersion Id.
     */
    @AuraEnabled
    public static void deleteFile(Id contentVersionId) {
        try {
            ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1];
            delete new ContentDocument(Id = cv.ContentDocumentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Returns file content as base64. Used by previewExcel since LWS
     * blocks binary fetch calls in the browser.
     */
    @AuraEnabled
    public static String getFileContentBase64(Id contentVersionId) {
        try {
            ContentVersion cv = [SELECT VersionData FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1];
            return EncodingUtil.base64Encode(cv.VersionData);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── validators ────────────────────────────────────────────────────────────

    /**
     * Called once before a new upload.
     */
    @AuraEnabled
    public static List<String> runUploadValidator(String validatorClassName, Id recordId) {
        if (String.isBlank(validatorClassName)) return new List<String>();
        try {
            Type t = Type.forName(validatorClassName);
            if (t == null) return new List<String>{ 'Validator class not found: ' + validatorClassName };
            FileValidator validator = (FileValidator) t.newInstance();
            List<String> errors = validator.allownewFileUpload(recordId);
            return errors != null ? errors : new List<String>();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Bulk permission check — called once after the file list loads.
     * Returns a map of ContentVersionId → FilePermissionResult so the UI
     * can enable/disable edit, delete, and download per row in a single call.
     */
    @AuraEnabled
    public static Map<Id, FilePermissionResult> runFilePermissions(
        String validatorClassName,
        List<Id> contentVersionIds,
        Id recordId
    ) {
        Map<Id, FilePermissionResult> result = new Map<Id, FilePermissionResult>();

        // No validator — everything is permitted
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

            // Any Id not returned by the validator is fully permitted
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
}