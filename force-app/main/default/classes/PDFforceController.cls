global without sharing class PDFforceController {//Updated to without sharing for testing purpose - Akash Kandwal
    @AuraEnabled
    public static string getComponentList(string componentType){
        try {
            // Construct the Tooling API endpoint URL
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            String endpoint = baseUrl + '/services/data/v62.0/tooling/query/?q=';
            
            // Build the SOQL query based on component type
            String query = buildToolingQuery(componentType);
            String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
            
            // Make the HTTP callout to Tooling API
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint + encodedQuery);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if(res.getStatusCode() == 200) {
                return res.getBody();
            } else {
                throw new AuraHandledException('Error querying Tooling API: ' + res.getStatus() + ' - ' + res.getBody());
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // Helper method to build the appropriate SOQL query based on component type
    private static String buildToolingQuery(String componentType) {
        String query = '';
        
        switch on componentType.toLowerCase() {
            when 'apexclass' {
                query = 'SELECT Id, Name, ApiVersion, Status, NamespacePrefix FROM ApexClass ORDER BY Name';
            }
            when 'apextrigger' {
                query = 'SELECT Id, Name, ApiVersion, Status, TableEnumOrId FROM ApexTrigger ORDER BY Name';
            }
            when 'apexpage' {
                query = 'SELECT Id, Name, ApiVersion, MasterLabel FROM ApexPage ORDER BY Name';
            }
            when 'apexcomponent' {
                query = 'SELECT Id, Name, ApiVersion, MasterLabel FROM ApexComponent ORDER BY Name';
            }
            when 'lightningcomponentbundle' {
                query = 'SELECT Id, DeveloperName, ApiVersion, MasterLabel, NamespacePrefix FROM LightningComponentBundle ORDER BY DeveloperName';
            }
            when 'customobject' {
                query = 'SELECT Id, DeveloperName, NamespacePrefix, ManageableState FROM CustomObject ORDER BY DeveloperName';
            }
            when 'customfield' {
                query = 'SELECT Id, DeveloperName, TableEnumOrId, NamespacePrefix FROM CustomField ORDER BY DeveloperName';
            }
            when 'validationrule' {
                query = 'SELECT Id, ValidationName, EntityDefinition.QualifiedApiName, Active FROM ValidationRule ORDER BY ValidationName';
            }
            when 'flow' {
                query = 'SELECT Id, MasterLabel, DefinitionId, VersionNumber, ProcessType FROM Flow ORDER BY MasterLabel';
            }
            when 'workflowrule' {
                query = 'SELECT Id, Name, TableEnumOrId FROM WorkflowRule ORDER BY Name';
            }
            when else {
                // Generic query if specific type is not defined
                query = 'SELECT Id, Name FROM ' + componentType + ' ORDER BY Name LIMIT 100';
            }
        }
        
        return query;
    }


    // In your Apex controller
@AuraEnabled(cacheable=true)
public static String getVFPageUrl(String pageName) {
    // Returns the full VF page URL for the current org
    String baseUrl = URL.getOrgDomainUrl().toExternalForm();
    return baseUrl + '/apex/' + pageName;
}

/**
 * Returns the most recently created PDFforce TEMPLATE file attached to
 * `recordId`. Filtered by extension so the LWC builder never loads a
 * file that isn't a saveable template -- which matters because the
 * server-side render pipeline (PdfRenderEmailHandler) drops its own
 * output back onto the same record:
 *   - Handlebars_rendered_PDF_<recordId>_<ts>.pdf   (the actual PDF)
 *   - PDFforce_failed_<recordId>_<ts>.html          (debug HTML on fail)
 * Without the filter, ORDER BY CreatedDate DESC would pick whichever
 * of those landed last and the builder would try to JSZip-decompress
 * a PDF (or just-rendered HTML), which throws an opaque error.
 *
 * Accepted extensions (only what the LWC's saveTemplate emits):
 *   - .json.zip   : current default (JSZip-compressed payload.json)
 *   - .json       : small templates saved uncompressed (< 3 MB)
 *   - .json.gz    : legacy (pre-JSZip-cutover); kept for back-compat
 */
@AuraEnabled
public static list<ContentDocumentLink> getTemplateVersions(string recordId){
    list<ContentDocumentLink> existingFiles = new list<ContentDocumentLink>();
    try {
        existingFiles = [
            SELECT Id, ContentDocumentId,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.LatestPublishedVersion.Title,
                   ContentDocument.LatestPublishedVersion.PathOnClient,
                   ContentDocument.FileType,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
              AND (   ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json.zip'
                   OR ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json.gz'
                   OR ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json')
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }

    return existingFiles;
}

@AuraEnabled
public static void createCDLRecords(List<string> cvIdsList, String recordId){
    List<ContentDocumentLink> linkedFiles = new List<ContentDocumentLink>();
     for (ContentVersion cv : [SELECT ID,ContentDocumentId FROM ContentVersion WHERE Id IN :cvIdsList]) {
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId=cv.ContentDocumentId;
        cdl.LinkedEntityId=recordId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        linkedFiles.add(cdl);
    }
    
    insert linkedFiles;
}

    /**
     * Creates a ContentVersion from a base64 payload (optionally a new version
     * on an existing ContentDocument). Used by pDFforceRenderer Save/Submit on VF.
     */
    @AuraEnabled
    public static String createContentVersionFromBase64(
        String title,
        String pathOnClient,
        String base64Payload,
        String description,
        String contentDocumentId
    ) {
        if (String.isBlank(base64Payload)) {
            throw new AuraHandledException('base64Payload is required.');
        }
        try {
            ContentVersion cv = new ContentVersion(
                Title = String.isNotBlank(title) ? title : 'PDFForceDocument',
                PathOnClient = String.isNotBlank(pathOnClient) ? pathOnClient : 'PDFForceDocument.pdf',
                VersionData = EncodingUtil.base64Decode(normalizeBase64Payload(base64Payload)),
                Description = description
            );
            if (String.isNotBlank(contentDocumentId)) {
                cv.ContentDocumentId = contentDocumentId;
            }
            insert cv;
            return cv.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Submit flow: creates a PDF ContentVersion and links it to recordId.
     */
    @AuraEnabled
    public static void attachGeneratedPdf(String recordId, String fileName, String base64Pdf) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('recordId is required.');
        }
        if (String.isBlank(base64Pdf)) {
            throw new AuraHandledException('PDF data is required.');
        }
        try {
            String pathOnClient = String.isNotBlank(fileName) && fileName.toLowerCase().endsWith('.pdf')
                ? fileName
                : (String.isNotBlank(fileName) ? fileName : 'PDFForceDocument') + '.pdf';
            String title = pathOnClient.replaceAll('(?i)\\.pdf$', '');

            String cvId = createContentVersionFromBase64(
                title,
                pathOnClient,
                base64Pdf,
                'PDFForce generated PDF',
                null
            );
            createCDLRecords(new List<String>{ cvId }, recordId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String normalizeBase64Payload(String payload) {
        if (String.isBlank(payload)) {
            return payload;
        }
        Integer commaIdx = payload.indexOf(',');
        return commaIdx >= 0 ? payload.substring(commaIdx + 1) : payload;
    }

@AuraEnabled
public static ContentVersion getContentVersionBlob(string html){
    try {
        Blob htmlBlob = Blob.valueOf(html);
        Blob pdfBlob = Blob.toPdf(html);
        ContentVersion cv = new ContentVersion();
        cv.Title = 'MyGeneratedDocument.pdf';
        cv.PathOnClient = 'MyGeneratedDocument.pdf';
        cv.VersionData = htmlBlob;
        insert cv;
        return cv;
        
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}

@AuraEnabled
public static string getContentVersionId(string contentDocumentId){
    try {
        ContentVersion cv = [SELECT VersionData, FileExtension 
                         FROM ContentVersion 
                         WHERE ContentDocumentId = :contentDocumentId 
                         AND IsLatest = true LIMIT 1];
    
    return 'data:image/' + cv.FileExtension + ';base64,' + EncodingUtil.base64Encode(cv.VersionData);
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}


// Returns the latest ContentVersion's binary VersionData decoded as a
// UTF-8 string. We use this instead of having the LWC pull
// /services/data/.../VersionData (slow API gateway path, 30-60s for
// non-trivial bodies) or /sfc/servlet.shepherd/... (fast but
// CORS-blocked from *.lightning.force.com because it redirects to
// *.file.force.com). Apex reads the blob server-side in a single
// SOQL hop and ships the bytes back through the standard
// AuraEnabled channel, which is typically sub-second for files
// under a couple of MB.
@AuraEnabled
public static string getTemplateContent(string contentDocumentId){
    try {
        ContentVersion cv = [SELECT VersionData
                             FROM ContentVersion
                             WHERE ContentDocumentId = :contentDocumentId
                             AND IsLatest = true LIMIT 1];
        return cv.VersionData.toString();
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}

/**
 * Returns the ContentDocumentId of the most recently created PDFforce
 * TEMPLATE file attached to `templateId`. Same extension filter as
 * getTemplateVersions -- see that method's header for why. Without
 * the filter we can return the ContentDocumentId of a rendered PDF
 * or debug HTML that PdfRenderEmailHandler dropped on the record,
 * and the renderer will then fail to decompress it.
 */
@AuraEnabled
public static string getTemplate(string templateId){
    try {

        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.ContentSizeLong,
                   ContentDocument.LatestPublishedVersion.Title,
                   ContentDocument.LatestPublishedVersion.PathOnClient,
                   ContentDocument.FileType,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :templateId
              AND (   ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json.zip'
                   OR ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json.gz'
                   OR ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json')
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        if (links.isEmpty()) {
            return null;
        }
        return links[0].ContentDocumentId;
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}


@AuraEnabled
//create a method to ccreate contentVersion and return the id with argument being base64 encoded string
public static ContentVersion createContentVersion(string base64String, string recordId){
    
    ContentVersion contentVersionId = null;
    try {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'MyGeneratedDocument.json';
        cv.PathOnClient = 'MyGeneratedDocument.json';
        cv.VersionData = Blob.valueOf(base64String);
        insert cv;

        list<id> contentVersionIds = new list<id>();
        contentVersionIds.add(cv.Id);
        
        createCDLRecords(contentVersionIds, recordId);
        contentVersionId = cv;
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
 return contentVersionId;
}


@RemoteAction
global static string getContentVersionIdRemote(string contentDocumentId){
    try {
        ContentVersion cv = [SELECT VersionData, FileExtension 
                         FROM ContentVersion 
                         WHERE ContentDocumentId = :contentDocumentId 
                         AND IsLatest = true LIMIT 1];
    
        return 'data:image/' + cv.FileExtension + ';base64,' + EncodingUtil.base64Encode(cv.VersionData);
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}


@AuraEnabled
	public static String getUserSessionId() {
		try {
			String sessionId = '';
			// Refer to the Page
			PageReference reportPage = Page.GETSessionId;
			// Get the content of the VF page
			String vfContent;
			if (Test.isRunningTest()) {
				vfContent = 'Start_Of_Session_Id' + 'SESSION_ID' + 'End_Of_Session_Id';
			} else {
				vfContent = reportPage.getContent().toString();
			}
			System.debug('vfContent is ' + vfContent);
			// Find the position of Start_Of_Session_Id and End_Of_Session_Id
			Integer startP = vfContent.indexOf('Start_Of_Session_Id') + 'Start_Of_Session_Id'.length(), endP = vfContent.indexOf('End_Of_Session_Id');
			// Get the Session Id
			sessionId = vfContent.substring(startP, endP);
			// Return Session Id
			return sessionId;
		} catch (Exception e) {

			throw new AuraHandledException(e.getMessage() + e.getStackTraceString());
		}
	}


    /**
     * Wrapper returned by loadTemplateJSON so the LWC gets the file bytes
     * AND the ContentVersion metadata in a single round-trip. Without the
     * metadata the LWC can't populate `currentContentVersion`, and a
     * subsequent save would create a brand-new ContentDocument instead of
     * a new version on the existing one.
     */
    public class TemplateLoadResult {
        @AuraEnabled public String versionData;        // base64 of gzip bytes (null if file >= 3 MB)
        @AuraEnabled public ContentVersion contentVersion; // Id, Title, ContentDocumentId, etc. (no blob)
    }

    /**
     * Returns the latest ContentVersion for a template file together with
     * its bytes (base64-encoded) when the file is small enough to fit in
     * Apex heap. For files >= 3 MB `versionData` is left null and the LWC
     * is expected to fall back to fetching VersionData directly via jsforce
     * (see pDFforceUtils.loadTemplateFromSalesforce).
     *
     * `template` is the ContentDocumentId of the template file (as returned
     * by getTemplate / stored on the PDFforceConfig__c record). `recordId`
     * is kept in the signature for backward compatibility but is not used
     * for the lookup - querying by ContentDocumentId is unambiguous, while
     * querying by LinkedEntityId would pick up unrelated files attached to
     * the same record (which broke the renderer with "incorrect header
     * check" when the most recent ContentDocumentLink on the user's record
     * was not the template).
     */
    /**
     * Looks up a previously-saved renderer payload attached to `recordId`
     * by Title. The renderer (handleSaveDocument) writes ContentVersions
     * with the canonical Title `PDFForceTemplate-<recordId> <templateId>`
     * and one of these PathOnClient extensions:
     *
     *   .html      - current default, raw compiled HTML (<= 3 MB)
     *   .html.gz   - current default, gzipped compiled HTML (> 3 MB)
     *   .json      - legacy renderer save, raw `{htmlContent,...}` JSON
     *   .json.gz   - legacy renderer save, gzipped JSON
     *   .json.zip  - legacy renderer save, JSZip-wrapped JSON
     *
     * The Title filter alone is normally sufficient (the title is unique
     * per recordId+templateId), but the extension filter is defensive --
     * mirrors getTemplate / getTemplateVersions so we never hand the LWC
     * a ContentDocumentId for an unrelated file someone manually attached
     * to the record under a clashing title (or a PdfRenderEmailHandler
     * artifact like Handlebars_rendered_PDF_<recordId>_<ts>.pdf or
     * PDFforce_failed_<recordId>_<ts>.html that happened to land first).
     *
     * Note: the extensions list here is intentionally a SUPERSET of
     * getTemplate's filter (which is .json* only). The renderer writes
     * .html* today, so excluding those extensions would make this method
     * always return null and break load-saved-state on every reopen.
     *
     * Returns the ContentDocumentId of the matching file, or null if the
     * record doesn't have a saved renderer payload yet. The renderer uses
     * the result both to decide between "load from saved doc" vs "load
     * from templateId" on init AND to attach a new version on subsequent
     * saves (so we don't pile up duplicate ContentDocuments per record).
     */
    @AuraEnabled
    public static String findRendererTemplateContentId(String recordId, String templateId) {
        try {
            if (String.isBlank(recordId) || String.isBlank(templateId)) {
                return null;
            }
            String title = 'PDFForceTemplate-' + recordId + ' ' + templateId;
            List<ContentDocumentLink> links = [
                SELECT Id, ContentDocumentId,
                       ContentDocument.LatestPublishedVersionId,
                       ContentDocument.ContentSizeLong,
                       ContentDocument.LatestPublishedVersion.Title,
                       ContentDocument.LatestPublishedVersion.PathOnClient,
                       ContentDocument.FileType,
                       ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :recordId
                  AND ContentDocument.Title = :title
                  AND (
                        ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json.zip'
                       OR ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json.gz'
                       OR ContentDocument.LatestPublishedVersion.PathOnClient LIKE '%.json')
                ORDER BY ContentDocument.CreatedDate DESC
                LIMIT 1
            ];
            return links.isEmpty() ? null : (String) links[0].ContentDocumentId;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Deletes the renderer's saved compiled-HTML payload for this
     * recordId+templateId pair. Called by the LWC right after a
     * successful Submit so the in-progress draft is cleaned up once
     * the final PDF has been attached to the record.
     *
     * Identifies the doc by Title (`PDFForceTemplate-<recordId> <templateId>`),
     * extension-agnostic - matches both `.html` and `.html.gz` saves
     * (and any legacy `.json` / `.json.gz` payloads under the same
     * Title). Deleting the ContentDocument cascades to ContentVersions
     * and ContentDocumentLinks, so the file disappears from the
     * record's Files list and from any other linked entity in one hop.
     *
     * No-op (does not throw) when:
     *   - recordId or templateId is blank
     *   - no matching ContentDocumentLink exists for this record
     * so callers can fire-and-forget without first checking existence.
     *
     * Returns the number of ContentDocument rows actually deleted, in
     * case the caller wants to log it.
     */
    @AuraEnabled
    public static Integer deleteRendererTemplateDocument(String recordId, String templateId) {
        try {
            if (String.isBlank(recordId) || String.isBlank(templateId)) {
                return 0;
            }
            String title = 'PDFForceTemplate-' + recordId + ' ' + templateId;
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :recordId
                  AND ContentDocument.Title = :title
            ];
            if (links.isEmpty()) {
                return 0;
            }
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink l : links) {
                docIds.add(l.ContentDocumentId);
            }
            List<ContentDocument> docs = [
                SELECT Id FROM ContentDocument WHERE Id IN :docIds
            ];
            if (docs.isEmpty()) {
                return 0;
            }
            delete docs;
            return docs.size();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static TemplateLoadResult loadTemplateJSON(String template, String recordId) {
        try {
            if (String.isBlank(template)) {
                throw new AuraHandledException('loadTemplateJSON: template (ContentDocumentId) is required');
            }
            List<ContentVersion> cvs = [
                SELECT Id, Title, FileExtension, ContentSize, PathOnClient, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId = :template AND IsLatest = true
                LIMIT 1
            ];
            if (cvs.isEmpty()) {
                throw new AuraHandledException('No ContentVersion found for ContentDocumentId ' + template);
            }
            ContentVersion cv = cvs[0];

            TemplateLoadResult res = new TemplateLoadResult();
            if (cv.ContentSize < 3000000) {
                res.versionData = EncodingUtil.base64Encode(cv.VersionData);
            }
            // Strip the blob from the metadata payload so we don't double-ship
            // multi-MB of data over the wire. The bytes are already in
            // `versionData` for the small-file path; large files will be
            // fetched by the LWC via jsforce.
            cv.VersionData = null;
            res.contentVersion = cv;
            return res;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}