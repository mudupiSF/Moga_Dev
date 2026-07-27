public with sharing class FileUploadController {
    @AuraEnabled
    public static map<Id,Id> createCDLRecords(Id cvIdsList, String recordId){
        try {
            map<Id,Id> result = new map<Id,Id>();
            List<ContentDocumentLink> linkedFiles = new List<ContentDocumentLink>();
            ContentVersion cv = [SELECT ID,ContentDocumentId FROM ContentVersion WHERE Id =:cvIdsList WITH SYSTEM_MODE ];
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId=cv.ContentDocumentId;
            cdl.LinkedEntityId=recordId;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            linkedFiles.add(cdl);

            insert as system cdl;
            result.put(cv.ContentDocumentId,cvIdsList);
            return result;
        }catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getUserSessionId(){
        try {
            String sessionId = '';
            // Refer to the Page
            PageReference reportPage = Page.GETSessionId;
            // Get the content of the VF page
            String vfContent;
            if(Test.isRunningTest()){
                vfContent = 'Start_Of_Session_Id'+'SESSION_ID'+'End_Of_Session_Id';
            }else{
                vfContent = reportPage.getContent().toString();
            }
            // Find the position of Start_Of_Session_Id and End_Of_Session_Id
            Integer startP = vfContent.indexOf('Start_Of_Session_Id') + 'Start_Of_Session_Id'.length(),
            endP = vfContent.indexOf('End_Of_Session_Id');
            // Get the Session Id
            sessionId = vfContent.substring(startP, endP);
            // Return Session Id
            return sessionId;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}