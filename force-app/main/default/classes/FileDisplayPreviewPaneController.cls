public with sharing class FileDisplayPreviewPaneController {

    /**
     * @description Returns Excel file bytes as base64 for client-side SheetJS parsing.
     * Browser fetch to shepherd URLs can fail in some org/domain combinations due to redirects/CORS.
     */
    @AuraEnabled(cacheable=false)
    public static String getExcelFileBase64(String contentVersionId, String contentDocumentId) {
        if (String.isBlank(contentVersionId) && String.isBlank(contentDocumentId)) {
            throw new AuraHandledException('File reference is missing.');
        }

        ContentVersion fileVersion;
        try {
            if (!String.isBlank(contentVersionId)) {
                fileVersion = [
                    SELECT Id, VersionData
                    FROM ContentVersion
                    WHERE Id = :contentVersionId
                    LIMIT 1
                ];
            } else {
                fileVersion = [
                    SELECT Id, VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId = :contentDocumentId
                    ORDER BY VersionNumber DESC
                    LIMIT 1
                ];
            }
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load Excel file content.');
        }

        if (fileVersion == null || fileVersion.VersionData == null) {
            throw new AuraHandledException('Excel file content is unavailable.');
        }

        return EncodingUtil.base64Encode(fileVersion.VersionData);
    }
}