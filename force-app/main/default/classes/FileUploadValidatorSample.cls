/**
 * Sample / reference implementation of FileValidator.
 * Set the component's "Validator Apex Class" property to: FileUploadValidatorSample
 */
public with sharing class FileUploadValidatorSample implements FileValidator {

    public List<String> allownewFileUpload(Id recordId) {
        // Allow all new uploads — override with your own logic
        return new List<String>();
    }

    public Map<Id, FilePermissionResult> allowEditDeleteFileUpload(
        List<Id> contentVersionIds,
        Id recordId
    ) {
        Map<Id, FilePermissionResult> result = new Map<Id, FilePermissionResult>();
        // Default: fully permit every file
        for (Id cvId : contentVersionIds) {
            result.put(cvId, new FilePermissionResult());
        }
        return result;
    }
}