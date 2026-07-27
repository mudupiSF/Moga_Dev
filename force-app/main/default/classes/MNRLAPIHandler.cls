/**
* @author             : Sourav Sharma
* @description        : Handler for MNRL API.
*/
public class MNRLAPIHandler implements IIntegrationHandler {
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
            if(String.isBlank(applicant.Phone__c)) {
                wrapper.hasValidationError = true;
                wrapper.errorMessage = 'Phone number is required.';
                wrapper.displayMessage = 'Phone number is required.';
            }
            if(!applicant.Application_Consent_Received__c) {
                wrapper.hasValidationError = true;
                wrapper.errorMessage += ' Application consent is required to proceed.';
                wrapper.displayMessage = 'Application consent is required to proceed.';
            }
            wrapperList.add(wrapper);
        }
        return wrapperList;
    }

    /**
    * @description       : Generate Request for MNRL API.
    * @param recordList  : List of Applicant records.
    * @return            : List of IntegrationRequestWrapper.
    */
    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant__c applicant = (Applicant__c)recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();

        MNRLRequestWrapper request = new MNRLRequestWrapper();
        request.mobile_number = applicant.Phone__c;
        request.country_code = 'IN';
        request.consent_obtained = applicant.Application_Consent_Received__c;
        request.request_timestamp = DateTime.now().format('dd/MM/yyyy HH:mm:ss');
        
        wrapper.requestBody = JSON.serialize(request);

        return new List<ApplicationUtility.IntegrationRequestWrapper>{wrapper};
    }


    /**
    * @description       : Process Response for MNRL API.
    * @param recordList  : List of IntegrationResponseWrapper.
    * @return            : List of IntegrationResponseWrapper.
    */
    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        IntegrationUtility.ResponseWrapper wrapper = (IntegrationUtility.ResponseWrapper)recordList[0];
        Integration_Checklist__c checklist = (Integration_Checklist__c)wrapper.checklistRecord;

        if(wrapper.statusCode != 200) {
            checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
            update checklist;
            result.hasValidationError = true;
            result.errorMessage = wrapper.response;
            result.displayMessage = 'MNRL API call failed.';
        }
        else {
            try {
                MNRLResponseWrapper response = parseMNRLResponse(wrapper.response);

                if(response == null || response.data == null || response.data.revocation_details == null) {
                    result.displayMessage = 'Invalid response received from MNRL API.';
                    result.hasValidationError = true;
                    checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                    checklist.Functional_Failure_Reason__c = 'Invalid response received from MNRL API.';
                }
                else if(response.status != 'success') {
                    result.displayMessage = 'MNRL verification failed.';
                    result.hasValidationError = true;
                    result.errorMessage = 'status is not success';
                    checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                    checklist.Functional_Failure_Reason__c = 'MNRL verification failed.';
                }
                else if(response.data.revocation_details.flagged_status == 'ACTIVATED') {
                    result.displayMessage = 'Mobile number is activated';
                    result.hasValidationError = false;
                    checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
                }
                else {
                    result.displayMessage = 'Mobile number is not activated';
                    result.hasValidationError = true;
                    checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                    checklist.Functional_Failure_Reason__c = 'Mobile number is not activated.';
                }
                checklist.Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            }
            catch(Exception ex) {
                result.displayMessage = 'Unable to parse MNRL API response.';
                result.hasValidationError = true;
                result.errorMessage = ex.getMessage();
                checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                checklist.Functional_Failure_Reason__c = 'Unable to parse MNRL API response.'+' '+ex.getStackTraceString();
            }
            update checklist;
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{result};
    }

    /**
    * @description       : Prepare Record for MNRL API.
    * @param recordIds   : List of Record IDs.
    * @return            : List of Applicant records.
    */
    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        List<Applicant__c> applicantList = [
            SELECT Id, Phone__c, Application_Consent_Received__c
            FROM Applicant__c
            WHERE Id IN: recordIds
        ];
        return applicantList;
    }
    
    /* request wrapper for MNRL API*/
    public class MNRLRequestWrapper{
        public String mobile_number                                                 {get;set;}
        public String country_code                                                  {get;set;}
        public Boolean consent_obtained                                             {get;set;}
        public String request_timestamp                                             {get;set;}
    }

    /**
     * @description       : Parse raw MNRL response JSON into typed wrapper.
     * @param jsonResponse: MNRL response payload in JSON format.
     * @return            : Parsed MNRLResponseWrapper object.
     */
    public static MNRLResponseWrapper parseMNRLResponse(String jsonResponse) {
        if(String.isBlank(jsonResponse)) {
            return null;
        }
        return (MNRLResponseWrapper) JSON.deserialize(jsonResponse, MNRLResponseWrapper.class);
    }

    /* response wrapper for MNRL API*/
    public class MNRLResponseWrapper{
        public String request_id                                                   {get;set;}
        public String status                                                       {get;set;}
        public Datetime timestamp                                                  {get;set;}
        public MNRLDataWrapper data                                                {get;set;}
    }

    public class MNRLDataWrapper{
        public String mobile_number                                                {get;set;}
        public Boolean is_on_mnrl                                                  {get;set;}
        public Integer risk_score                                                  {get;set;}
        public MNRLRevocationDetailsWrapper revocation_details                     {get;set;}
        public MNRLVerificationMetadataWrapper verification_metadata               {get;set;}
    }

    public class MNRLRevocationDetailsWrapper{
        public String flagged_status                                               {get;set;}
        public String reason_code                                                  {get;set;}
        public Datetime revocation_date                                            {get;set;}
        public String flag_source                                                  {get;set;}
    }

    public class MNRLVerificationMetadataWrapper{
        public Datetime last_checked                                               {get;set;}
        public String telecom_circle                                               {get;set;}
    }
}