/**
* @author             : Sourav Sharma
* @description        : Handler for MHA API.
*/
public class MHAAPIHandler implements IIntegrationHandler {
    /**
     * @description       : Validate Input Data.
     * @param recordList  : List of Applicant records.
     * @return            : List of IntegrationResponseWrapper.
     */
    public List<ApplicationUtility.IntegrationResponseWrapper> validateInputData(List<Object> recordList) {
        List<ApplicationUtility.IntegrationResponseWrapper> wrapperList = new List<ApplicationUtility.IntegrationResponseWrapper>();
        for(Object record : recordList) {
            Applicant__c applicant = (Applicant__c)record;
            ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
            wrapper.hasValidationError = false;
            wrapper.recordId = applicant.Id;
            if(applicant.PAN_Number__c == null) {
                wrapper.hasValidationError = true;
                wrapper.errorMessage = 'PAN is required.';
                wrapper.displayMessage = 'PAN is required.';
            }
            if(applicant.Date_of_Birth__c == null) {
                wrapper.hasValidationError = true;
                wrapper.errorMessage += ' Date of birth is required.';
                wrapper.displayMessage = 'Date of birth is required.';
            }
            if(applicant.Customer_First_Name__c == null || applicant.Customer_Last_Name__c == null) {
                wrapper.hasValidationError = true;
                wrapper.errorMessage += ' First name and last name are required';
                wrapper.displayMessage = 'First name and last name are required';
            }
            wrapperList.add(wrapper);
        }
        return wrapperList;
    }

    /**
    * @description       : Generate Request for MHA API.
    * @param recordList  : List of Applicant records.
    * @return            : List of IntegrationRequestWrapper.
    */
    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant__c applicant = (Applicant__c)recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();

        MHARequestWrapper request = new MHARequestWrapper();
        request.pan = applicant.PAN_Number__c;
        request.name = applicant.Customer_First_Name__c + ' ' + applicant.Customer_Last_Name__c;
        DateTime dob = applicant.Date_of_Birth__c;
        request.dob = dob.format('dd/MM/yyyy');
        request.fathername = applicant.Father_s_name__c;
        
        wrapper.requestBody = JSON.serialize(request);

        return new List<ApplicationUtility.IntegrationRequestWrapper>{wrapper};
    }


    /**
    * @description       : Process Response for MHA API.
    * @param recordList  : List of IntegrationResponseWrapper.
    * @return            : List of IntegrationResponseWrapper.
    */
    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        IntegrationUtility.ResponseWrapper wrapper = (IntegrationUtility.ResponseWrapper)recordList[0];

        if(wrapper.statusCode != 200) {
            Integration_Checklist__c checklist = (Integration_Checklist__c)wrapper.checklistRecord;
            checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
            update checklist;
            result.hasValidationError = true;
            result.errorMessage = wrapper.response;
        }
        else {
            MHAResponseWrapper response = (MHAResponseWrapper)JSON.deserialize(wrapper.response, MHAResponseWrapper.class);
            Integration_Checklist__c checklist = (Integration_Checklist__c)wrapper.checklistRecord;
        
            if(response.response_Code == '1') {
                Applicant__c applicantRecord = new Applicant__c(Id = checklist.Applicant__c);
                // Check if PAN is Existing and Valid
                result.hasValidationError = false;
                if(response.outputData[0].pan_status == 'E') {
                    result.displayMessage = 'PAN Status is existing';
                    // Check name and DOB 
                    if(response.outputData[0].name != 'Y') {
                        result.displayMessage += ' , ' + 'Name does not match with PAN database';
                        result.hasValidationError = true;
                    }
                    if(response.outputData[0].dob != 'Y') {
                        result.displayMessage += ' , ' + 'Date of birth does not match with PAN database';
                        result.hasValidationError = true;
                    }
                }
                else {
                    result.displayMessage = 'PAN is not valid as per records.';
                    result.hasValidationError = true;
                }
                if(result.hasValidationError) {
                    checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                    applicantRecord.PAN_Number_Verified__c = false;
                }
                else {
                    checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
                    applicantRecord.PAN_Number_Verified__c = true;
                }
                update applicantRecord;
            }
            else {
                result.displayMessage = 'Request is Invalid';
                result.hasValidationError = true;
                checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
            }
            checklist.Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            update checklist;
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{result};
    }

    /**
    * @description       : Prepare Record for MHA API.
    * @param recordIds   : List of Record IDs.
    * @return            : List of Applicant records.
    */
    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        List<Applicant__c> applicantList = [
            SELECT Id, Customer_First_Name__c, Customer_Last_Name__c, PAN_Number__c,
            Date_of_Birth__c, Father_s_name__c
            FROM Applicant__c
            WHERE Id IN: recordIds
        ];
        return applicantList;
    }
    
    /* request wrapper for MHA API*/
    public class MHARequestWrapper{
        public String pan                                                           {get;set;}
        public String name                                                          {get;set;}
        public String dob                                                           {get;set;}
        public String fathername                                                    {get;set;}
    }

    /* response wrapper for MHA API*/
    public class MHAResponseWrapper{
        public String response_Code                                                 {get;set;}
        public MHAOutputWrapper[] outputData                                        {get;set;}
    }

    /* output wrapper for MHA API*/
    public class MHAOutputWrapper{
        public String pan                                                           {get;set;}
        public String pan_status                                                    {get;set;}
        public String name                                                          {get;set;}
        public String fathername                                                    {get;set;}
        public String dob                                                           {get;set;}
    }
}