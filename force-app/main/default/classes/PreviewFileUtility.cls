public with sharing class PreviewFileUtility {
    @AuraEnabled(cacheable=true)
    public static String getFileExtension(String contentVersionId) {
        if (String.isBlank(contentVersionId)) {
            return null;
        }

        List<ContentVersion> versions = [
            SELECT FileExtension
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            return null;
        }

        return versions[0].FileExtension;
    }
}