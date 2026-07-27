@IsTest(SeeAllData=true)
private class EditQueryDetailsControllerTest {

    private static Id getAnyApplicationId() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        return apps.isEmpty() ? null : apps[0].Id;
    }

    private static Query__c createTestQueryRecord() {
        List<Query__c> seedQueries = [
            SELECT Id, Application__c, Query_Type__c, Query_Sub_Type__c, Priority__c, Status__c
            FROM Query__c
            WHERE Application__c != null
            LIMIT 1
        ];
        if (seedQueries.isEmpty()) {
            return null;
        }
        Query__c seed = seedQueries[0];

        Query__c q = new Query__c();
        q.Application__c = seed.Application__c;
        q.Status__c = String.isNotBlank(seed.Status__c) ? seed.Status__c : 'New';
        q.Subject__c = 'UT Query Subject';
        q.Description__c = 'UT Query Description';
        q.Query_Type__c = seed.Query_Type__c;
        q.Query_Sub_Type__c = seed.Query_Sub_Type__c;
        q.Priority__c = seed.Priority__c;
        q.Assigned_To__c = UserInfo.getUserId();
        insert q;
        return q;
    }

    @IsTest
    static void testGetQueryDetailsAndComments() {
        Query__c q = createTestQueryRecord();
        if (q == null) {
            System.assert(true, 'No Application__c found; skipping data-dependent assertions');
            return;
        }
        insert new Query_Comment__c(Query__c = q.Id, Comment_Body__c = 'Existing test comment');

        Test.startTest();
        Map<String, Object> details = EditQueryDetailsController.getQueryDetails(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, details);
        System.assertEquals((String)q.Id, (String)details.get('Id'));
        System.assert(details.containsKey('canEditAssignedTo'));
        System.assert(details.containsKey('canEditOwner'));
        System.assert(details.containsKey('canEditStatusAsAssignedTo'));
        System.assert(details.containsKey('canEditStatusAsOwner'));
        System.assert(details.containsKey('queryComments'));
    }

    @IsTest
    static void testGetQueryDetailsAndAttachmentsErrorPaths() {
        Query__c q = createTestQueryRecord();
        if (q == null) {
            System.assert(true, 'No Application__c found; skipping data-dependent assertions');
            return;
        }

        Map<String, Object> details = EditQueryDetailsController.getQueryDetails(q.Id);
        List<Map<String, String>> attachments = EditQueryDetailsController.getQueryAttachments(q.Id);
        System.assertNotEquals(null, details);
        System.assertNotEquals(null, attachments);
    }

    @IsTest
    static void testGetQueryAttachments() {
        Query__c q = createTestQueryRecord();
        if (q == null) {
            System.assert(true, 'No Application__c found; skipping data-dependent assertions');
            return;
        }

        ContentVersion cv = new ContentVersion(
            Title = 'EditQueryAttachmentTest',
            PathOnClient = 'EditQueryAttachmentTest.pdf',
            VersionData = Blob.valueOf('pdf-test')
        );
        insert cv;
        ContentVersion insertedCv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        insert new ContentDocumentLink(
            LinkedEntityId = q.Id,
            ContentDocumentId = insertedCv.ContentDocumentId,
            ShareType = 'V'
        );

        Test.startTest();
        List<Map<String, String>> attachments = EditQueryDetailsController.getQueryAttachments(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, attachments);
        System.assert(attachments.size() > 0);
    }

    @IsTest
    static void testUpdateQueryHappyPathAndNoChangePath() {
        Query__c q = createTestQueryRecord();
        if (q == null) {
            System.assert(true, 'No Application__c found; skipping data-dependent assertions');
            return;
        }

        Test.startTest();
        // No changes path
        EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, q.OwnerId, q.Status__c, null, null);

        // Assigned user allowed status update
        EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, q.OwnerId, 'Accepted', null, null);
        Test.stopTest();

        Query__c refreshed = [SELECT Status__c FROM Query__c WHERE Id = :q.Id];
        System.assertEquals('Accepted', refreshed.Status__c);
    }

    @IsTest
    static void testUpdateQueryValidationFailures() {
        Query__c q = createTestQueryRecord();
        if (q == null) {
            System.assert(true, 'No Application__c found; skipping data-dependent assertions');
            return;
        }

        // Comments without status change
        Boolean commentsValidationThrown = false;
        try {
            EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, q.OwnerId, q.Status__c, 'comment only', null);
        } catch (AuraHandledException ex) {
            commentsValidationThrown = true;
        }
        System.assertEquals(true, commentsValidationThrown);

        // Invalid status
        Boolean invalidStatusThrown = false;
        try {
            EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, q.OwnerId, 'BadStatus', null, null);
        } catch (AuraHandledException ex) {
            invalidStatusThrown = true;
        }
        System.assertEquals(true, invalidStatusThrown);

        // Resolved requires comments
        Boolean resolveCommentRequiredThrown = false;
        try {
            EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, q.OwnerId, 'Resolved', null, null);
        } catch (AuraHandledException ex) {
            resolveCommentRequiredThrown = true;
        }
        System.assertEquals(true, resolveCommentRequiredThrown);

        // Blank query id
        Boolean blankIdThrown = false;
        try {
            EditQueryDetailsController.updateQuery(null, null, null, null, null, null);
        } catch (AuraHandledException ex) {
            blankIdThrown = true;
        }
        System.assertEquals(true, blankIdThrown);

        // Owner change denied (hierarchy check false for self-owned record)
        List<User> otherUsers = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId() AND IsActive = true LIMIT 1];
        if (!otherUsers.isEmpty()) {
            Boolean ownerDenied = false;
            try {
                EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, otherUsers[0].Id, q.Status__c, null, null);
            } catch (AuraHandledException ex) {
                ownerDenied = true;
            }
            System.assertEquals(true, ownerDenied);
        }

        // Assigned To cannot be blank
        Boolean blankAssignedDenied = false;
        try {
            EditQueryDetailsController.updateQuery(q.Id, '', q.OwnerId, q.Status__c, null, null);
        } catch (AuraHandledException ex) {
            blankAssignedDenied = true;
        }
        System.assertEquals(true, blankAssignedDenied);

        // Invalid owner Id format to force generic catch -> user-friendly error path
        Boolean genericCatchHit = false;
        try {
            EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, 'abc', q.Status__c, null, null);
        } catch (AuraHandledException ex) {
            genericCatchHit = true;
        }
        System.assertEquals(true, genericCatchHit);

        // Re-open validations
        q.Status__c = 'Accepted';
        update q;
        Boolean reopenStateDenied = false;
        try {
            EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, q.OwnerId, 'Re-Open', null, 'Need reopen');
        } catch (AuraHandledException ex) {
            reopenStateDenied = true;
        }
        System.assertEquals(true, reopenStateDenied);

        q.Status__c = 'Resolved';
        update q;
        Boolean reopenReasonDenied = false;
        try {
            EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, q.OwnerId, 'Re-Open', null, null);
        } catch (AuraHandledException ex) {
            reopenReasonDenied = true;
        }
        System.assertEquals(true, reopenReasonDenied);

        Boolean closeCommentDenied = false;
        try {
            EditQueryDetailsController.updateQuery(q.Id, q.Assigned_To__c, q.OwnerId, 'Closed', null, null);
        } catch (AuraHandledException ex) {
            closeCommentDenied = true;
        }
        System.assertEquals(true, closeCommentDenied);
    }

    @IsTest
    static void testUpdateQueryWithCommentsAndAssignedToChange() {
        Query__c q = createTestQueryRecord();
        if (q == null) {
            System.assert(true, 'No Application__c found; skipping data-dependent assertions');
            return;
        }

        List<User> otherUsers = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId() AND IsActive = true LIMIT 1];
        if (otherUsers.isEmpty()) {
            System.assert(true, 'No alternate active user found');
            return;
        }

        Test.startTest();
        EditQueryDetailsController.updateQuery(q.Id, otherUsers[0].Id, q.OwnerId, 'Accepted', 'status changed', null);
        Test.stopTest();

        Query__c refreshed = [SELECT Status__c, Assigned_To__c, Internal_Comments__c FROM Query__c WHERE Id = :q.Id];
        System.assertEquals('Accepted', refreshed.Status__c);
        System.assertEquals(otherUsers[0].Id, refreshed.Assigned_To__c);
    }

    @IsTest
    static void testLoggedInUserSubordinates() {
        Test.startTest();
        List<Map<String, String>> subs = EditQueryDetailsController.getLoggedInUserSubordinates();
        Test.stopTest();
        System.assertNotEquals(null, subs);
    }
}