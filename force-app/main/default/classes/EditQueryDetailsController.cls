/**
 * @description Controller for editing query details
 * @author Sourav Sharma
 * @date 2026-05-27
 */
public with sharing class EditQueryDetailsController {
    
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getQueryDetails(String queryId) {
        try {
            Id currentUserId = UserInfo.getUserId();
            Map<String, Object> queryDetailsMap = new Map<String, Object>();
            List<Query__c> queryList = [SELECT Id, Name, Subject__c, Priority__c, Status__c,
                                        Assigned_To__c, Assigned_To__r.Name, OwnerId, Owner.Name,
                                        Query_Type__c, Query_Sub_Type__c, Internal_Comments__c, Description__c,
                                        Application__c, Re_Open_Reason__c, Applicant__r.Name,
                                        Applicant__r.Customer_First_Name__c, Applicant__r.Customer_Last_Name__c,
                                        Applicant__r.Company_Name__c, Document_Checklist__r.Name,
                                        Application_Line_Items__r.Name, Asset__r.Name, Applicant_Employment__r.Name
                                        FROM Query__c
                                        WHERE Id =: queryId LIMIT 1];
            if(queryList != NULL && !queryList.isEmpty()) {
                Query__c query = queryList[0];
                queryDetailsMap.putAll(buildQueryMap(query));
                queryDetailsMap.put('canEditAssignedTo', canEditAssignedToInternal(query, currentUserId));
                queryDetailsMap.put('canEditOwner', isManagerInHierarchy(currentUserId, query.OwnerId));
                queryDetailsMap.put('canEditStatusAsAssignedTo', canEditStatusAsAssignedTo(query));
                queryDetailsMap.put('canEditStatusAsOwner', canEditStatusAsOwner(query));
                queryDetailsMap.put('canReopen', canEditStatusAsOwner(query) && query.Status__c == 'Resolved');
                queryDetailsMap.put('applicationId', query.Application__c);
                queryDetailsMap.put('queryComments', getQueryComments(queryId, 20));
            }
            return queryDetailsMap;
        }
        catch (Exception e) {
            throw new AuraHandledException('Error fetching case details: ' + e.getMessage());
        }
    }

    /**
     * @description Gets attachments (ContentDocumentLink) for a case
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getQueryAttachments(String queryId) {
        try {
            List<ContentDocumentLink> links = [SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.ContentSize
                FROM ContentDocumentLink WHERE LinkedEntityId = :queryId AND ContentDocumentId != null];
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : links) docIds.add(link.ContentDocumentId);
            Map<Id, Id> docToVersionId = new Map<Id, Id>();
            for (ContentVersion cv : [SELECT ContentDocumentId FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = true]) {
                docToVersionId.put(cv.ContentDocumentId, cv.Id);
            }
            List<Map<String, String>> result = new List<Map<String, String>>();
            for (ContentDocumentLink link : links) {
                String docId = link.ContentDocumentId;
                Id versionId = docToVersionId.get(docId);
                // Use relative shepherd URLs so links work on internal and Experience Cloud domains.
                String downloadUrl = '/sfc/servlet.shepherd/document/download/' + docId;
                String previewUrl = (versionId != null) ? '/sfc/servlet.shepherd/version/download/' + versionId : downloadUrl;
                String ext = link.ContentDocument.FileExtension != null ? link.ContentDocument.FileExtension.toLowerCase() : '';
                result.add(new Map<String, String>{
                    'Id' => docId,
                    'Title' => link.ContentDocument.Title,
                    'FileExtension' => link.ContentDocument.FileExtension != null ? link.ContentDocument.FileExtension : '',
                    'ContentSize' => link.ContentDocument.ContentSize != null ? String.valueOf(link.ContentDocument.ContentSize) : '0',
                    'DownloadUrl' => downloadUrl,
                    'PreviewUrl' => previewUrl,
                    'IsViewable' => (ext == 'pdf' || ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'gif' || ext == 'webp') ? 'true' : 'false'
                });
            }
            return result;
        }
        catch (Exception e) {
            throw new AuraHandledException('Error fetching attachments: ' + e.getMessage());
        }
    }

    /**
     * @description Updates case - Assigned To, Status, Comments
     */
    @AuraEnabled
    public static void updateQuery(String queryId, String assignedToId, String ownerId, String status, String comments, String reopenReason) {
        try {
            Id currentUserId = UserInfo.getUserId();
            Query__c query = [SELECT Id, Status__c, Internal_Comments__c, Assigned_To__c, OwnerId, Re_Open_Reason__c FROM Query__c WHERE Id = :queryId LIMIT 1];
            Boolean hasChanges = false;
            Boolean statusWillChange = String.isNotBlank(status) && status != query.Status__c;
            Boolean reopenReasonWillChange = reopenReason != null && reopenReason != query.Re_Open_Reason__c;

            if (ownerId != null && (Id)ownerId != query.OwnerId) {
                if (!isManagerInHierarchy(currentUserId, query.OwnerId)) {
                    throw new AuraHandledException('You do not have permission to change Owner.');
                }
                query.OwnerId = (Id)ownerId;
                hasChanges = true;
            }
            if (statusWillChange) {
                query.Status__c = status;
                hasChanges = true;
            }
            if (reopenReasonWillChange) {
                query.Re_Open_Reason__c = reopenReason;
                hasChanges = true;
            }
            if (assignedToId != null && assignedToId != query.Assigned_To__c) {
                if (String.isBlank(assignedToId)) {
                    throw new AuraHandledException('Assigned To cannot be blank.');
                }
                if (!canEditAssignedToInternal(query, currentUserId)) {
                    throw new AuraHandledException('You do not have permission to change Assigned To.');
                }
                Id newAssignedToId = (Id) assignedToId;
                query.Assigned_To__c = newAssignedToId;
                //CaseEditorController.setPersonaFromAssignedUser(c, (Id) assignedToId);
                hasChanges = true;
            }
            if (!hasChanges) {
                return;
            }
            update query;
            insertQueryComments(query, comments, reopenReason);
        }
        catch (AuraHandledException e) {
            throw e;
        }
        catch (Exception e) {
            throw new AuraHandledException('Error updating case: ' + getUserFriendlyDmlMessage(e));
        }
    }
    
    private static Map<String, Object> buildQueryMap(Query__c query) {
        Map<String, Object> m = new Map<String, Object>();
        m.put('Id', query.Id);
        m.put('QueryNumber', query.Name);
        m.put('Subject', query.Subject__c);
        m.put('Priority', query.Priority__c);
        m.put('Status', query.Status__c);
        m.put('AssignedTo', query.Assigned_To__r != null ? query.Assigned_To__r.Name : '');
        m.put('AssignedToId', query.Assigned_To__c);
        m.put('OwnerName', query.Owner != null ? query.Owner.Name : '');
        m.put('OwnerId', query.OwnerId);
        m.put('QueryType', query.Query_Type__c);
        m.put('QuerySubType', query.Query_Sub_Type__c);
        m.put('Comments', query.Internal_Comments__c);
        m.put('ReOpenReason', query.Re_Open_Reason__c);
        m.put('Description', query.Description__c);
        String applicantName = '';
        if(query.Applicant__r != null) {
            if(String.isNotBlank(query.Applicant__r.Customer_First_Name__c) && String.isNotBlank(query.Applicant__r.Customer_Last_Name__c)) {
                applicantName = query.Applicant__r.Customer_First_Name__c + ' ' + query.Applicant__r.Customer_Last_Name__c;
            }
            else if(String.isNotBlank(query.Applicant__r.Company_Name__c)) {
                applicantName = query.Applicant__r.Company_Name__c;
            }
            else {
                applicantName = query.Applicant__r.Name;
            }
        }
        m.put('ApplicantName', applicantName);
        m.put('DocumentChecklistName', query.Document_Checklist__r != null ? query.Document_Checklist__r.Name : '');
        m.put('ApplicationLineItemName', query.Application_Line_Items__r != null ? query.Application_Line_Items__r.Name : '');
        m.put('AssetName', query.Asset__r != null ? query.Asset__r.Name : '');
        m.put('ApplicantEmploymentName', query.Applicant_Employment__r != null ? query.Applicant_Employment__r.Name : '');
        return m;
    }
    
    private static Boolean canEditAssignedToInternal(Query__c query, Id currentUserId) {
        Boolean hasAccess = false;
        if (query.Assigned_To__c == currentUserId) {
            hasAccess = true;
        }
        else {
            hasAccess = isManagerInHierarchy(currentUserId, query.Assigned_To__c);
        }
        return hasAccess;
    }
    
    /**
     * @description Check if current user can set Assigned To statuses: New, Accepted, Resolved, Rejected.
     * True only for Assigned To user. Bulk queries cannot be resolved manually.
     */
    private static Boolean canEditStatusAsAssignedTo(Query__c query) {
        Id currentUserId = UserInfo.getUserId();
        return query.Assigned_To__c == currentUserId;
    }
    
    /**
     * @description Check if current user can set Owner statuses: Re-Open, Closed.
     * True only for Case Owner.
     */
    private static Boolean canEditStatusAsOwner(Query__c query) {
        Id currentUserId = UserInfo.getUserId();
        return query.OwnerId == currentUserId;
    }
    
    private static List<Map<String, Object>> getQueryComments(String queryId, Integer limitSize) {
        List<Map<String, Object>> commentsResult = new List<Map<String, Object>>();
        Integer safeLimit = (limitSize != null && limitSize > 0) ? limitSize : 20;

        for (Query_Comment__c commentRow : [
            SELECT Id, Comment_Body__c, CreatedDate, CreatedById, CreatedBy.Name
            FROM Query_Comment__c
            WHERE Query__c = :queryId
            ORDER BY CreatedDate DESC
            LIMIT :safeLimit
        ])
        {
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', commentRow.Id);
            row.put('CommentBody', commentRow.Comment_Body__c);
            row.put('CreatedDate', commentRow.CreatedDate);
            row.put('CreatedById', commentRow.CreatedById);
            row.put('CreatedByName', commentRow.CreatedBy != null ? commentRow.CreatedBy.Name : null);
            commentsResult.add(row);
        }
        return commentsResult;
    }

    private static String getUserFriendlyDmlMessage(Exception e) {
        if (e instanceof DmlException) {
            DmlException dmlEx = (DmlException) e;
            String dmlMessage = dmlEx.getDmlMessage(0);
            if (String.isNotBlank(dmlMessage)) {
                if (dmlMessage.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION,')) {
                    String cleanedValidationMessage = dmlMessage.substringAfter('FIELD_CUSTOM_VALIDATION_EXCEPTION,').trim();
                    cleanedValidationMessage = cleanedValidationMessage.replace(': []', '').trim();
                    if (String.isNotBlank(cleanedValidationMessage)) {
                        return cleanedValidationMessage;
                    }
                }
                return dmlMessage;
            }
        }
        return String.isNotBlank(e.getMessage()) ? e.getMessage() : 'Unexpected error occurred.';
    }

    /**
    * @description Gets up to 5 levels of direct and indirect reports for the logged-in user
    */
    @AuraEnabled(cacheable=false)
    public static List<UserDetailsWrapper> getLoggedInUserSubordinates() {
        List<UserDetailsWrapper> userWrappers = new List<UserDetailsWrapper>();
        Id currentUserId = UserInfo.getUserId();

        // Query for users where Current User is Manager, or Manager's Manager, etc.
        // This fetches levels 1 through 5 in one pass
        for (User userRecord : [SELECT Id, Name, Email, Persona__c, Manager.Name, Product__c
                    FROM User 
                    WHERE IsActive = true 
                    AND (ManagerId = :currentUserId 
                            OR Manager.ManagerId = :currentUserId 
                            OR Manager.Manager.ManagerId = :currentUserId 
                            OR Manager.Manager.Manager.ManagerId = :currentUserId 
                            OR Manager.Manager.Manager.Manager.ManagerId = :currentUserId)
                    ORDER BY Name ASC])
        {
            userWrappers.add(
            new UserDetailsWrapper(
                userRecord.Id,
                userRecord.Name,
                userRecord.Email,
                userRecord.Persona__c,
                userRecord.Manager != NULL ? userRecord.Manager.Name : NULL,
                userRecord.Product__c,
                userRecord.Id == currentUserId
            ));
        }
        return userWrappers;
    }
    
    /**
     * @description Returns true when managerUserId is in subordinateUserId's manager chain (up to 5 levels).
     */
    private static Boolean isManagerInHierarchy(Id managerUserId, Id subordinateUserId) {
        List<User> users = [
            SELECT Id, ManagerId, Manager.ManagerId, Manager.Manager.ManagerId,
                   Manager.Manager.Manager.ManagerId, Manager.Manager.Manager.Manager.ManagerId
            FROM User
            WHERE Id =: subordinateUserId
            LIMIT 1
        ];
        if (users.isEmpty()) return false;
        User u = users[0];
        if (u.ManagerId == managerUserId) return true;
        if (u.Manager != null && u.Manager.ManagerId == managerUserId) return true;
        if (u.Manager != null && u.Manager.Manager != null && u.Manager.Manager.ManagerId == managerUserId) return true;
        if (u.Manager != null && u.Manager.Manager != null && u.Manager.Manager.Manager != null && u.Manager.Manager.Manager.ManagerId == managerUserId) return true;
        if (u.Manager != null && u.Manager.Manager != null && u.Manager.Manager.Manager != null && u.Manager.Manager.Manager != null && u.Manager.Manager.Manager.Manager.ManagerId == managerUserId) return true;
        return false;
    }

    private static void insertQueryComments(Query__c query, String comments, String reopenReason) {
        Set<String> targetBodies = new Set<String>();
        if (String.isNotBlank(comments)) {
            targetBodies.add(comments.trim());
        }
        if (String.isNotBlank(reopenReason)) {
            targetBodies.add(('Re-Open Reason: ' + reopenReason).trim());
        }
        if (targetBodies.isEmpty()) return;

        // Avoid duplicate comments when another automation already creates the same CaseComment.
        Map<String, Boolean> existingRecentByBody = new Map<String, Boolean>();
        List<Query_Comment__c> commentsToPublish = new List<Query_Comment__c>();
        Id currentUserId = UserInfo.getUserId();
        Datetime recentWindowStart = System.now().addMinutes(-5);
        for (Query_Comment__c existing : [
            SELECT Id, Comment_Body__c
            FROM Query_Comment__c
            WHERE Query__c = :query.Id
              AND CreatedById = :currentUserId
              AND CreatedDate >= :recentWindowStart
        ])
        {
            existingRecentByBody.put(existing.Comment_Body__c, true);
        }

        List<Query_Comment__c> commentsToInsert = new List<Query_Comment__c>();
        if (String.isNotBlank(comments) && !existingRecentByBody.containsKey(comments.trim())) {
            commentsToInsert.add(new Query_Comment__c(
                Query__c = query.Id,
                Comment_Body__c = comments.trim(),
                CreatedById = currentUserId
            ));
        }
        String reopenReasonBody = String.isNotBlank(reopenReason) ? ('Re-Open Reason: ' + reopenReason).trim() : null;
        if (String.isNotBlank(reopenReasonBody) && !existingRecentByBody.containsKey(reopenReasonBody)) {
            commentsToInsert.add(new Query_Comment__c(
                Query__c = query.Id,
                Comment_Body__c = reopenReasonBody,
                CreatedById = currentUserId
            ));
        }
        if (!commentsToInsert.isEmpty()) {
            insert commentsToInsert;
        }
    }

    public class UserDetailsWrapper {
        @AuraEnabled
        public String userId;
        @AuraEnabled
        public String userName;
        @AuraEnabled
        public String userEmail;
        @AuraEnabled
        public String userPersona;
        @AuraEnabled
        public String managerName;
        @AuraEnabled
        public String product;
        @AuraEnabled
        public Boolean isCurrentUser;

        public UserDetailsWrapper(
            Id userId,
            String userName,
            String userEmail,
            String userPersona,
            String managerName,
            String product,
            Boolean isCurrentUser
        )
        {
            this.userId = (String) userId;
            this.userName = userName;
            this.userEmail = userEmail;
            this.userPersona = userPersona;
            this.managerName = managerName;
            this.product = product;
            this.isCurrentUser = isCurrentUser;
        }
    }

}