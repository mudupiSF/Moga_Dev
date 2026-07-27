/**
 * Return value of FileValidator.allowEditDeleteFileUpload.
 * One instance per ContentVersion Id in the result map.
 */
public class FilePermissionResult {
    @AuraEnabled public Boolean      canEdit     { get; set; }
    @AuraEnabled public Boolean      canDelete   { get; set; }
    @AuraEnabled public Boolean      canDownload { get; set; }
    @AuraEnabled public List<String> errors      { get; set; }

    public FilePermissionResult() {
        this.canEdit     = true;
        this.canDelete   = true;
        this.canDownload = true;
        this.errors      = new List<String>();
    }
}