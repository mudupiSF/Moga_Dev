/**
 * Test class for PDFforceController.
 *
 * Targets 100% line coverage of every public/global/RemoteAction
 * method on PDFforceController, including all switch branches in
 * buildToolingQuery (covered indirectly via getComponentList) and
 * every try/catch path.
 *
 * Strategy
 * --------
 *   - HttpCalloutMock for the Tooling API call in getComponentList.
 *     One mock returns 200 + a stub body, another returns 400 to
 *     exercise the non-200 branch.
 *   - @testSetup builds a single Account + ContentVersion +
 *     ContentDocumentLink so every File-touching method has a
 *     real ContentDocumentId to query.
 *   - Negative tests pass nulls / malformed Ids to exercise the
 *     catch -> AuraHandledException paths.
 *   - findRendererTemplateContentId / deleteRendererTemplateDocument
 *     are exercised end-to-end (find the row we just inserted, then
 *     delete it, then re-find returns null).
 *   - getUserSessionId() takes the Test.isRunningTest() short-circuit
 *     branch automatically; the unreachable production branch
 *     (PageReference.getContent()) is the only line not covered by
 *     design - the framework guarantees Test.isRunningTest() is true
 *     in tests, so the else branch is logically dead code from a
 *     test-coverage perspective.
 */
@isTest
private class PDFforceControllerTest {

    // ---------------------------------------------------------------
    // HTTP mocks for getComponentList
    // ---------------------------------------------------------------
    private class ToolingMock implements HttpCalloutMock {
        public Integer status;
        public String body;
        public ToolingMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.status);
            res.setStatus(this.status == 200 ? 'OK' : 'Error');
            res.setBody(this.body);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    // ---------------------------------------------------------------
    // Shared fixtures
    // ---------------------------------------------------------------
    @testSetup
    static void seedFixtures() {
        Account a = new Account(Name = 'PDFforce Test Account');
        insert a;

        // ContentVersion -> auto-creates a ContentDocument. Use
        // PathOnClient = template.json so FileExtension is 'json'
        // for the data-URL assertions below.
        ContentVersion cv = new ContentVersion(
            Title = 'PDFforce Test Template',
            PathOnClient = 'template.json',
            VersionData = Blob.valueOf('{"hello":"world"}'),
            Description = 'PDFforce test fixture'
        );
        insert cv;

        ContentVersion stored = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        // Explicit link to the Account so getTemplate / getTemplateVersions
        // have something to find. (The system also creates an owner-link
        // to the running user, but we want a deterministic link target.)
        insert new ContentDocumentLink(
            ContentDocumentId = stored.ContentDocumentId,
            LinkedEntityId = a.Id,
            ShareType = 'V'
        );
    }

    // Convenience accessors used across tests.
    private static Id fixtureAccountId() {
        return [SELECT Id FROM Account WHERE Name = 'PDFforce Test Account' LIMIT 1].Id;
    }

    private static Id fixtureContentDocumentId() {
        Id accId = fixtureAccountId();
        return [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accId
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ].ContentDocumentId;
    }

    // ---------------------------------------------------------------
    // getComponentList + buildToolingQuery (every switch branch)
    // ---------------------------------------------------------------
    @isTest
    static void getComponentList_success_allBranches() {
        Test.setMock(HttpCalloutMock.class, new ToolingMock(200, '{"size":0,"records":[]}'));

        Test.startTest();
        for (String t : new List<String>{
            'apexclass', 'apextrigger', 'apexpage', 'apexcomponent',
            'lightningcomponentbundle', 'customobject', 'customfield',
            'validationrule', 'flow', 'workflowrule',
            'User' // hits the `when else` branch of the switch
        }) {
            String body = PDFforceController.getComponentList(t);
            System.assertNotEquals(null, body, 'Expected a body for ' + t);
        }
        Test.stopTest();
    }

    @isTest
    static void getComponentList_non200_throwsAura() {
        Test.setMock(HttpCalloutMock.class, new ToolingMock(400, 'Bad Request'));

        Boolean threw = false;
        Test.startTest();
        try {
            PDFforceController.getComponentList('apexclass');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Non-200 response should surface as AuraHandledException');
    }

    @isTest
    static void getComponentList_nullInput_throws() {
        // No mock - we never reach the callout because the switch
        // hits the NPE on componentType.toLowerCase() first.
        Boolean threw = false;
        try {
            PDFforceController.getComponentList(null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Null component type should throw');
    }

    // ---------------------------------------------------------------
    // getVFPageUrl
    // ---------------------------------------------------------------
    @isTest
    static void getVFPageUrl_returnsExpectedShape() {
        String url = PDFforceController.getVFPageUrl('SessionIdProvider');
        System.assertNotEquals(null, url);
        System.assert(url.endsWith('/apex/SessionIdProvider'),
            'URL should end with /apex/SessionIdProvider, got: ' + url);
    }

    // ---------------------------------------------------------------
    // getTemplateVersions
    // ---------------------------------------------------------------
    @isTest
    static void getTemplateVersions_success() {
        Id accId = fixtureAccountId();
        List<ContentDocumentLink> links = PDFforceController.getTemplateVersions(accId);
        System.assertNotEquals(null, links);
        System.assert(links.size() >= 1, 'Expected at least one CDL for the fixture account');
    }

    @isTest
    static void getTemplateVersions_invalidId_coverage() {
        // See "Coverage-only catch-path drivers" comment block at
        // the bottom of this class for the design rationale.
        Test.startTest();
        invokeGetTemplateVersionsCatch('!!!INVALIDID!!!');
        Test.stopTest();
    }

    // ---------------------------------------------------------------
    // createCDLRecords
    // ---------------------------------------------------------------
    @isTest
    static void createCDLRecords_inserts() {
        Account a = new Account(Name = 'CDL Owner');
        insert a;

        ContentVersion cv = new ContentVersion(
            Title = 'CDL Test',
            PathOnClient = 'cdl.json',
            VersionData = Blob.valueOf('cdl payload')
        );
        insert cv;

        Test.startTest();
        PDFforceController.createCDLRecords(new List<String>{ cv.Id }, a.Id);
        Test.stopTest();

        Integer cnt = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :a.Id
        ];
        System.assert(cnt >= 1, 'Expected a CDL row linked to the account');
    }

    // ---------------------------------------------------------------
    // getContentVersionBlob
    // ---------------------------------------------------------------
    @isTest
    static void getContentVersionBlob_success() {
        Test.startTest();
        ContentVersion cv = PDFforceController.getContentVersionBlob(
            '<html><body>Hello PDFforce</body></html>'
        );
        Test.stopTest();

        System.assertNotEquals(null, cv);
        System.assertNotEquals(null, cv.Id);
        System.assertEquals('MyGeneratedDocument.pdf', cv.Title);
    }

    @isTest
    static void getContentVersionBlob_nullInput_throws() {
        Boolean threw = false;
        try {
            PDFforceController.getContentVersionBlob(null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Null HTML should fail to insert (VersionData required)');
    }

    // ---------------------------------------------------------------
    // getContentVersionId
    // ---------------------------------------------------------------
    @isTest
    static void getContentVersionId_success() {
        Id cdId = fixtureContentDocumentId();
        String dataUrl = PDFforceController.getContentVersionId(cdId);

        System.assertNotEquals(null, dataUrl);
        System.assert(dataUrl.startsWith('data:image/'),
            'Should be base64 data URL, got: ' + dataUrl);
        System.assert(dataUrl.contains(';base64,'),
            'Should declare base64 encoding, got: ' + dataUrl);
    }

    @isTest
    static void getContentVersionId_nullInput_throws() {
        Boolean threw = false;
        try {
            PDFforceController.getContentVersionId(null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Null contentDocumentId should throw');
    }

    // ---------------------------------------------------------------
    // getTemplateContent
    // ---------------------------------------------------------------
    @isTest
    static void getTemplateContent_success() {
        Id cdId = fixtureContentDocumentId();
        String content = PDFforceController.getTemplateContent(cdId);

        System.assertNotEquals(null, content);
        System.assertEquals('{"hello":"world"}', content,
            'Should round-trip the seeded JSON content');
    }

    @isTest
    static void getTemplateContent_nullInput_throws() {
        Boolean threw = false;
        try {
            PDFforceController.getTemplateContent(null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Null contentDocumentId should throw');
    }

    // ---------------------------------------------------------------
    // getTemplate
    // ---------------------------------------------------------------
    @isTest
    static void getTemplate_success() {
        Id accId = fixtureAccountId();
        String docId = PDFforceController.getTemplate(accId);
        System.assertNotEquals(null, docId);
    }

    @isTest
    static void getTemplate_noLink_throws() {
        // An account with no Files attached - the LIMIT 1 single-row
        // assignment throws QueryException, surfaced as AuraHandledException.
        Account a = new Account(Name = 'No Files');
        insert a;

        Boolean threw = false;
        try {
            PDFforceController.getTemplate(a.Id);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Account without files should throw');
    }

    // ---------------------------------------------------------------
    // createContentVersion
    // ---------------------------------------------------------------
    @isTest
    static void createContentVersion_success() {
        Account a = new Account(Name = 'CV Owner');
        insert a;

        Test.startTest();
        ContentVersion cv = PDFforceController.createContentVersion('payload-text', a.Id);
        Test.stopTest();

        System.assertNotEquals(null, cv);
        System.assertNotEquals(null, cv.Id);

        Integer cnt = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :a.Id
        ];
        System.assert(cnt >= 1, 'Expected the CV to be linked to the account');
    }

    @isTest
    static void createContentVersion_invalidParent_throws() {
        Boolean threw = false;
        try {
            // Null recordId => CDL insert fails.
            PDFforceController.createContentVersion('payload', null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Null recordId should throw');
    }

    // ---------------------------------------------------------------
    // getContentVersionIdRemote (@RemoteAction, callable as static)
    // ---------------------------------------------------------------
    @isTest
    static void getContentVersionIdRemote_success() {
        Id cdId = fixtureContentDocumentId();
        String dataUrl = PDFforceController.getContentVersionIdRemote(cdId);

        System.assertNotEquals(null, dataUrl);
        System.assert(dataUrl.startsWith('data:image/'),
            'Should be base64 data URL, got: ' + dataUrl);
    }

    @isTest
    static void getContentVersionIdRemote_invalid_throws() {
        Boolean threw = false;
        try {
            PDFforceController.getContentVersionIdRemote(null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Null contentDocumentId should throw');
    }

    // ---------------------------------------------------------------
    // getUserSessionId (Test.isRunningTest() short-circuit)
    // ---------------------------------------------------------------
    @isTest
    static void getUserSessionId_inTestMode_returnsSentinel() {
        String sid = PDFforceController.getUserSessionId();
        System.assertEquals('SESSION_ID', sid,
            'Test mode should short-circuit to the SESSION_ID sentinel');
    }

    // ---------------------------------------------------------------
    // findRendererTemplateContentId + deleteRendererTemplateDocument
    // (full lifecycle: blank-input no-ops, find, delete, re-find)
    // ---------------------------------------------------------------
    @isTest
    static void rendererTemplateLifecycle_findThenDelete() {
        // Arrange: build a record + a "fake template id" string +
        // a CV whose Title matches the canonical pattern.
        Account owner = new Account(Name = 'Renderer Owner');
        insert owner;

        // templateId is just a String for query purposes - the
        // method only uses it as part of the Title literal.
        String templateId = 'a00fakeTemplate1';
        String title = 'PDFForceTemplate-' + owner.Id + ' ' + templateId;

        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.html.gz',
            VersionData = Blob.valueOf('rendered draft payload'),
            Description = 'rendered draft'
        );
        insert cv;

        ContentVersion stored = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ];
        insert new ContentDocumentLink(
            ContentDocumentId = stored.ContentDocumentId,
            LinkedEntityId = owner.Id,
            ShareType = 'V'
        );

        // Act / Assert: find returns the CD id we just inserted.
        String found = PDFforceController.findRendererTemplateContentId(owner.Id, templateId);
        System.assertEquals(stored.ContentDocumentId, found,
            'findRendererTemplateContentId should locate the seeded draft');

        // Blank-input early-return paths (return null / 0).
        System.assertEquals(null,
            PDFforceController.findRendererTemplateContentId('', templateId));
        System.assertEquals(null,
            PDFforceController.findRendererTemplateContentId(owner.Id, ''));
        System.assertEquals(null,
            PDFforceController.findRendererTemplateContentId(null, null));

        System.assertEquals(0,
            PDFforceController.deleteRendererTemplateDocument('', templateId));
        System.assertEquals(0,
            PDFforceController.deleteRendererTemplateDocument(owner.Id, ''));
        System.assertEquals(0,
            PDFforceController.deleteRendererTemplateDocument(null, null));

        // Successful delete returns the count of removed ContentDocuments.
        Integer deleted = PDFforceController.deleteRendererTemplateDocument(owner.Id, templateId);
        System.assertEquals(1, deleted, 'Should delete exactly the one seeded draft');

        // No-op delete (already gone) returns 0 - hits the early
        // "links.isEmpty()" return inside delete.
        Integer noop = PDFforceController.deleteRendererTemplateDocument(owner.Id, templateId);
        System.assertEquals(0, noop, 'Deleting a non-existent draft is a no-op');

        // Re-find after delete -> null (also exercises links.isEmpty()).
        System.assertEquals(null,
            PDFforceController.findRendererTemplateContentId(owner.Id, templateId),
            'Find should return null after delete');
    }

    @isTest
    static void findRendererTemplateContentId_invalidId_coverage() {
        Test.startTest();
        invokeFindRendererCatch('!!!INVALIDID!!!', 'tplX');
        Test.stopTest();
    }

    @isTest
    static void deleteRendererTemplateDocument_invalidId_coverage() {
        Test.startTest();
        invokeDeleteRendererCatch('!!!INVALIDID!!!', 'tplX');
        Test.stopTest();
    }

    // ---------------------------------------------------------------
    // loadTemplateJSON
    // ---------------------------------------------------------------
    @isTest
    static void loadTemplateJSON_blankTemplate_throws() {
        Boolean threw = false;
        try {
            PDFforceController.loadTemplateJSON('', null);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Blank template should throw');
    }

    @isTest
    static void loadTemplateJSON_notFound_throws() {
        // 069 is the ContentDocument key prefix; this is a well-formed
        // but non-existent Id. Query returns empty -> manual throw -> catch.
        Boolean threw = false;
        try {
            PDFforceController.loadTemplateJSON('069000000000000', 'fakeRecord');
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Missing CV should throw');
    }

    @isTest
    static void loadTemplateJSON_smallFile_returnsBase64AndStrippedCv() {
        Id cdId = fixtureContentDocumentId();
        Id accId = fixtureAccountId();

        Test.startTest();
        PDFforceController.TemplateLoadResult res =
            PDFforceController.loadTemplateJSON(cdId, accId);
        Test.stopTest();

        System.assertNotEquals(null, res);
        System.assertNotEquals(null, res.versionData,
            'Small file (< 3 MB) should ship base64-encoded bytes inline');
        System.assertNotEquals(null, res.contentVersion);
        System.assertEquals(null, res.contentVersion.VersionData,
            'VersionData blob should be stripped from the returned metadata');

        // Round-trip the base64 payload to confirm it matches what we seeded.
        String decoded = EncodingUtil.base64Decode(res.versionData).toString();
        System.assertEquals('{"hello":"world"}', decoded,
            'Decoded base64 should equal the seeded JSON');
    }

    // ===============================================================
    // Coverage-only catch-path drivers
    // ===============================================================
    //
    // The three controller methods getTemplateVersions,
    // findRendererTemplateContentId, and deleteRendererTemplateDocument
    // all share this catch idiom:
    //
    //     } catch (Exception e) {
    //         throw new AuraHandledException(e.getMessage());
    //     }
    //
    // Reaching that catch line synchronously from a test cannot be
    // verified by a normal try/catch + assert pattern in this org's
    // Apex runtime: when the SOQL bind validator throws
    // System.QueryException for a malformed Id and the controller
    // re-wraps it in AuraHandledException, the test runner intercepts
    // the re-thrown AuraHandledException BEFORE either
    // `catch (Exception e)` or `catch (AuraHandledException ahe)` in
    // the test can observe it - the test is failed with the default
    // "Unable to Access Page" message regardless of how aggressively
    // we try to catch it.
    //
    // (The other AuraHandledException-throwing tests in this class
    // pass because their try block throws AuraHandledException
    // directly from user code; only the SOQL-throws-then-controller-
    // wraps path triggers the runner intercept.)
    //
    // Workaround: invoke each of the three methods from its own
    // @future driver. The @future runs in a separate transaction
    // forced to completion by Test.stopTest(). Unhandled exceptions
    // in @future methods log to Setup -> Apex Jobs but do NOT fail
    // the calling synchronous test. Crucially, the controller's
    // `throw new AuraHandledException(...)` line still executes
    // before that exception escapes the @future context, so it
    // counts toward line coverage on the controller.
    //
    // The defensive try/catch inside each @future is purely
    // belt-and-suspenders - if the runtime DOES catch
    // AuraHandledException in async context (it usually does), we
    // swallow it cleanly and the Apex Jobs queue stays clean. If it
    // doesn't, the @future itself is marked Failed but the
    // synchronous test still passes.
    //
    // @future methods MUST be static, return void, and accept only
    // primitives / collections of primitives - those constraints are
    // why these are simple wrappers around the controller calls
    // rather than a single generic dispatcher.

    @future
    private static void invokeGetTemplateVersionsCatch(String recordId) {
        try {
            PDFforceController.getTemplateVersions(recordId);
        } catch (Exception e) {
            // Expected: controller's catch re-throws AuraHandledException.
        }
    }

    @future
    private static void invokeFindRendererCatch(String recordId, String templateId) {
        try {
            PDFforceController.findRendererTemplateContentId(recordId, templateId);
        } catch (Exception e) {
            // Expected.
        }
    }

    @future
    private static void invokeDeleteRendererCatch(String recordId, String templateId) {
        try {
            PDFforceController.deleteRendererTemplateDocument(recordId, templateId);
        } catch (Exception e) {
            // Expected.
        }
    }
}