/**
 * Implement this interface in any Apex class and set the component's
 * "Validator Apex Class" property to that class name.
 *
 * allownewFileUpload          — called once before a new upload; return errors to block.
 * allowEditDeleteFileUpload   — called once with all visible ContentVersion IDs + the parent
 *                               record Id; return a map of permissions per file so the UI
 *                               can show/hide edit, delete, and download actions in one call.
 */
public interface FileValidator {

    /**
     * Return a non-empty list to block a new file upload onto recordId.
     */
    List<String> allownewFileUpload(Id recordId);

    /**
     * Bulk permission check — called once after the file list loads.
     *
     * @param contentVersionIds  All ContentVersion Ids currently displayed.
     * @param recordId           The parent record Id.
     * @return  Map keyed by ContentVersion Id.  Missing keys are treated as
     *          fully permitted (all three flags = true, no errors).
     */
    Map<Id, FilePermissionResult> allowEditDeleteFileUpload(
        List<Id> contentVersionIds,
        Id recordId
    );
}