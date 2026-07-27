/**
 * Cloned from CustomFileUploadV2Controller per the project rule
 *
 *   stampFileTags(cvId, tags)
 *     Writes a list of file-provenance / transformation tags
 *     (Uploaded, Compressed, Masked, Merged, Watermarked, Rotated,
 *      Live Image Capture, Live Video Capture) into
 *     ContentVersion.CV_File_Tags__c (a restricted multi-select
 *     picklist). Called by the LWC immediately after each successful
 *     ContentVersion insert.
 */
public with sharing class embedCustomFileUploadController {

    private static final Map<String, String> TAG_LOOKUP = new Map<String, String>{
        'uploaded'           => 'Uploaded',
        'live image capture' => 'Live Image Capture',
        'live video capture' => 'Live Video Capture',
        'compressed'         => 'Compressed',
        'masked'             => 'Masked',
        'merged'             => 'Merged',
        'rotated'            => 'Rotated',
        'watermarked'        => 'Watermarked'
    };

    // VF-page session bridge — copy of CustomFileUploadV2Controller.getUserSessionId
    // for the embed clone, so the LWC import surface points only at this class.
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

    // Pre-upload validator hook — copy of the base method for the embed clone.
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
     * stamps CV_File_Tags__c on a single ContentVersion.
     *
     * `tags` is a list of free-form strings (the LWC sends per-file flag
     * names like "uploaded", "merged", "live image capture").
     */
    @AuraEnabled
    public static void stampFileTags(Id contentVersionId, List<String> tags) {
        if (contentVersionId == null) return;
        if (tags == null || tags.isEmpty()) return;

        List<String> canonical = new List<String>();
        Set<String>  seen      = new Set<String>();
        for (String raw : tags) {
            if (String.isBlank(raw)) continue;
            String key = raw.trim().toLowerCase();
            String canon = TAG_LOOKUP.get(key);
            if (canon == null) continue;
            if (seen.contains(canon)) continue;
            seen.add(canon);
            canonical.add(canon);
        }
        if (canonical.isEmpty()) return;

        try {
            // Multi-select picklist DML format is a ';' joined string.
            update new ContentVersion(
                Id              = contentVersionId,
                CV_File_Tags__c = String.join(canonical, ';')
            );
        } catch (Exception e) {
            throw new AuraHandledException(
                'Could not stamp file tags on ContentVersion ' + contentVersionId
                + ': ' + e.getMessage()
            );
        }
    }
}