/**
 * sfLOSFilePreviewController
 * --------------------------------------------------------------------------
 * Returns base64 file bytes + metadata for the in-LOS file previewer
 * (sfLOSFilePreviewer LWC and sfLOSOverlayFile Aura cmp).
 *
 * Why does this exist?
 *   The default Shepherd download endpoint (`/sfc/servlet.shepherd/document/...`)
 *   serves an HTML preview wrapper on Lightning Desktop, but returns
 *   `Content-Disposition: attachment` (= force download) on Salesforce1
 *   mobile, on the Salesforce mobile/tablet app, and on Experience Cloud
 *   community-mobile. To preview consistently across all four target
 *   contexts (Internal Desktop, Internal Mobile/Tablet, Community Desktop,
 *   Community Mobile/Tablet), the LWC needs to hold the file bytes itself
 *   so it can construct a `blob:` URL for an inline iframe (PDF/Office) or
 *   a `data:` URL for an inline img (image).
 *
 * Heap-size guard:
 *   ContentVersion.VersionData can be very large (DOCX/PDF up to 38 MB on
 *   the Files Connect tier). We compare current heap to the limit BEFORE
 *   reading VersionData; if we are already close to the heap limit we
 *   return `IsFileSizeLarge = true` and skip VersionData. The LWC then
 *   falls back to the Shepherd download URL on desktop and shows a
 *   "file too large to inline-preview" message on mobile.
 *
 */
public with sharing class filePreviewController {

    public class FilePreviewWrapper {
        @AuraEnabled public String Title;
        @AuraEnabled public String FileExtension;
        @AuraEnabled public String ContentDocumentId;
        @AuraEnabled public String VersionID;
        @AuraEnabled public Long ContentSize;
        @AuraEnabled public Blob VersionData;
        @AuraEnabled public String theme;
        @AuraEnabled public Boolean IsFileSizeLarge = false;
    }

    /**
     * Returns file bytes + metadata for inline preview.
     * @param contentDocumentId Id of the ContentDocument whose latest version we want to preview.
     * @return Map with key `currentFile` -> JSON string of FilePreviewWrapper, identical
     *         shape to the legacy P4DocumentHandler so the LWC parsing logic stays unchanged.
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getPreviewData(String contentDocumentId) {
        Map<String, Object> mapData = new Map<String, Object>();
        if (String.isBlank(contentDocumentId)) {
            return null;
        }

        FilePreviewWrapper fpw = new FilePreviewWrapper();
        // SYSTEM_MODE so ContentVersion.VersionData is readable regardless of
        // the running user's profile FLS on that field. The user must still
        // have access to the ContentDocument itself via standard sharing.
        for (ContentVersion cv : [
            SELECT Id, VersionData, ContentSize,
                   ContentDocument.FileExtension, ContentDocument.Title
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
              AND IsLatest = true
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            // Heap-size guard: if reading the file would push us past the heap limit,
            // skip the bytes and signal the LWC to fall back to download.
            if (Limits.getHeapSize() > Limits.getLimitHeapSize()) {
                fpw.IsFileSizeLarge = true;
            } else {
                fpw.VersionData = cv.VersionData;
                fpw.IsFileSizeLarge = false;
            }
            fpw.VersionID = cv.Id;
            fpw.ContentDocumentId = contentDocumentId;
            fpw.Title = cv.ContentDocument.Title;
            fpw.FileExtension = cv.ContentDocument.FileExtension;
            fpw.ContentSize = cv.ContentSize;
            fpw.theme = UserInfo.getUiThemeDisplayed();
        }

        mapData.put('currentFile', JSON.serialize(fpw));
        return mapData;
    }
}