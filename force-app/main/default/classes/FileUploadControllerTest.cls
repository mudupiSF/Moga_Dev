@isTest
public with sharing class FileUploadControllerTest {
    @isTest
    static void createCDLRecordsTest() {
        Document_Checklist__c dclItem = new Document_Checklist__c(Name= 'Test');
        insert dclItem;
        
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Test Document';
        cv.PathOnClient = 'TestDocument.pdf';
        cv.VersionData = Blob.valueOf('Test Content');
        cv.IsMajorVersion = true;
        Insert cv;

        map<Id,Id> result= FileUploadController.createCDLRecords(cv.Id,dclItem.Id);
        List<ContentDocumentLink> linkedFiles = [Select Id from ContentDocumentLink where LinkedEntityId=:dclItem.Id];
        System.assertEquals(1, linkedFiles.size(), 'Document Link Not created');
        //In EXception
        try{
            FileUploadController.createCDLRecords(dclItem.Id,cv.Id);
        }catch(Exception ex){
            System.assertEquals('Script-thrown exception',ex.getMessage(),'Exception Not Thrown');
        }
    }

    @isTest
    static void getUserSessionIdTest() {
        String sessionId = FileUploadController.getUserSessionId();
        Assert.isNotNull(sessionId, 'The sessionId is null');
    }
}