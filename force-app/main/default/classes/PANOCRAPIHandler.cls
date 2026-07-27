/**
* @author        	  : Sourav Sharma
* @description        : Handler for PAN OCR API.
*/
public class PANOCRAPIHandler implements IIntegrationHandler {
    
    /* validate input data for PAN OCR API
    * @param recordList : List of ContentVersion objects
    * @return : List of IntegrationResponseWrapper objects
    */
    public List<ApplicationUtility.IntegrationResponseWrapper> validateInputData(List<Object> recordList) {
        List<ApplicationUtility.IntegrationResponseWrapper> wrapperList = new List<ApplicationUtility.IntegrationResponseWrapper>();
        ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
        wrapper.hasValidationError = false;
        if(recordList.isEmpty()) {
            wrapper.errorMessage = 'PAN card was not uploaded';
            wrapper.displayMessage = 'PAN card was not uploaded';
            wrapper.hasValidationError = true;
        }
        wrapperList.add(wrapper);
        return wrapperList;
    }
    
    /* generate request for PAN OCR API
    * @param recordList : List of ContentVersion objects
    * @return : List of IntegrationRequestWrapper objects
    */
    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        ContentVersion panContentVersion = (ContentVersion)recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();
        Blob blobData = panContentVersion.VersionData;
        String base64Data = EncodingUtil.base64Encode(blobData);
        wrapper.requestBody = base64Data;
        wrapper.captureRequestInAttachment = true;
        return new List<ApplicationUtility.IntegrationRequestWrapper>{wrapper};
    }
    
    /* process response for PAN OCR API
    * @param recordList : List of IntegrationUtility.ResponseWrapper objects
    * @return : List of IntegrationResponseWrapper objects
    */
    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        try {
            IntegrationUtility.ResponseWrapper wrapper = (IntegrationUtility.ResponseWrapper)recordList[0];
            System.debug('statusCode: ' + wrapper);
            System.debug('response: ' + wrapper.response);
            if(wrapper.statusCode != 200) {
                Integration_Checklist__c checklist = (Integration_Checklist__c)wrapper.checklistRecord;
                checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                update checklist;
                result.hasValidationError = true;
                result.errorMessage = wrapper.response;
            }
            else {
                PANOCRAPIResponseWrapper response = (PANOCRAPIResponseWrapper)JSON.deserialize(wrapper.response, PANOCRAPIResponseWrapper.class);
                Integration_Checklist__c checklist = (Integration_Checklist__c)wrapper.checklistRecord;

                DocumentDataWrapper documentData = response.document_data;
                String panCardNumber = documentData.document_number;
                String dateOfBirth = documentData.date_of_birth;
                String dateOfIncorporation = documentData.date_of_incorporation;
                String fullName = documentData.full_name;
                List<String> fullNameList = fullName.split(' ');
                String firstName = '';
                String lastName = '';
                if(!fullNameList.isEmpty()) {
                    firstName = fullNameList[0];
                    lastName = fullName.substringAfterLast(firstName+' ');
                }
                Applicant__c applicant = new Applicant__c(Id = checklist.Applicant__c);
                applicant.PAN_Number__c = panCardNumber;
                applicant.Date_of_Birth__c = parseDateMonthYear(dateOfBirth);
                applicant.Customer_First_Name__c = firstName;
                applicant.Customer_Last_Name__c = lastName;
                update applicant;
                result.hasValidationError = false;
                checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
                checklist.Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
                update checklist;
            }
        }
        catch (Exception ex) {
            result.hasValidationError = true;
            result.errorMessage = ex.getMessage();
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{result};
    }
    
    /* prepare record for PAN OCR API
    * @param recordIds : List of Applicant__c objects
    * @return : List of sObject objects
    */
    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        Id applicantId = recordIds[0];
        List<sObject> sObjectList = NULL;
        List<Document_Checklist__c> documentChecklist = [SELECT Id, Name, ContentVersionId__c FROM Document_Checklist__c WHERE Applicant__c =: applicantId AND Document_Type__c = 'PAN' LIMIT 1];
        if(!documentChecklist.isEmpty()) {
            sObjectList = [SELECT Id, Title, VersionData FROM ContentVersion WHERE Id =: documentChecklist[0].ContentVersionId__c LIMIT 1];
        }
        return sObjectList;
    }

    /* response wrapper for PAN OCR API*/
    public class PANOCRAPIResponseWrapper {
        public String correlationId { get; set; }
        public String document_type { get; set; }
        public String classification { get; set; }
        public String confidence { get; set; }
        public MetadataWrapper metadata { get; set; }
        public DocumentDataWrapper document_data { get; set; }
    }

    /* metadata wrapper for PAN OCR API*/
    public class MetadataWrapper {
        public String expiry_date { get; set; }
    }

    /* document data wrapper for PAN OCR API*/
    public class DocumentDataWrapper {
        public String document_number { get; set; }
        public String date_of_birth { get; set; }
        public String full_name { get; set; }
        public String father_name { get; set; }
        public String issuing_authority { get; set; }
        public String date_of_incorporation { get; set; }
    }

    private static Date parseDateMonthYear(String dobText) {
        List<String> parts = dobText.trim().split('-');
        Integer day = Integer.valueOf(parts[0].trim());
        Integer year = Integer.valueOf(parts[2].trim());
        Integer month = Integer.valueOf(parts[1].trim());
        return Date.newInstance(year, month, day);
    }
}