/**
* @author              : Sourav Sharma
* @description         : Handler for Send Email OTP API.
*/
public class SendEmailOTPAPIHandler implements IIntegrationHandler {
    /**
     * @description       : Validate Input Data.
     * @param recordList  : List of Applicant records.
     * @return            : List of IntegrationResponseWrapper.
     */
    public List<ApplicationUtility.IntegrationResponseWrapper> validateInputData(List<Object> recordList) {
        try {
            List<ApplicationUtility.IntegrationResponseWrapper> wrapperList = new List<ApplicationUtility.IntegrationResponseWrapper>();
            for(Object record : recordList){
                Applicant__c applicant = (Applicant__c)record;
                ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
                wrapper.recordId = applicant.Id;
                if(applicant.Email__c == null) {
                    wrapper.hasValidationError = true;
                    wrapper.errorMessage = 'Email address is required.';
                }
                else {
                    wrapper.hasValidationError = false;
                }
                wrapperList.add(wrapper);
            }
            return wrapperList;
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
    * @description       : Generate Request for Send Email OTP API.
    * @param recordList  : List of Applicant records.
    * @return            : List of IntegrationRequestWrapper.
    */
    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        Applicant__c applicant = (Applicant__c)recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();

        String message = 'Your one-time password (OTP) is <OTP>.';
        message = message.replace('<OTP>', applicant.Email_Verification_Code__c);

        SendEmailOTPRequestWrapper request = new SendEmailOTPRequestWrapper();
        request.enterpriseid = 'EnterpriseId';
        request.subEnterpriseid = 'Sub_EnterpriseId';
        request.pusheid = 'PusheId';
        request.pushepwd = 'PushePwd';
        request.contenttype = 'ContentType';
        request.sender = 'Sender';
        request.alert = 'Alert';
        request.emailid = applicant.Email__c;
        request.intflag = 'IntFlag';
        request.msgText = message;
        request.selfid = 'SelfId';
        request.dlreq = 'Dlreq';
    
        wrapper.requestBody = JSON.serialize(request);
        
        return new List<ApplicationUtility.IntegrationRequestWrapper>{wrapper};
    }

    /**
    * @description       : Process Response for Send Email OTP API.
    * @param recordList  : List of IntegrationResponseWrapper.
    * @return            : List of IntegrationResponseWrapper.
    */
    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        IntegrationUtility.ResponseWrapper wrapper = (IntegrationUtility.ResponseWrapper)recordList[0];
        
        Integration_Checklist__c checklist = (Integration_Checklist__c)wrapper.checklistRecord;
        try {
            Map<String, String> responseMap = (Map<String, String>)JSON.deserialize(wrapper.response, Map<String, String>.class);
            
            if(responseMap.get('status') == 'sent') {
                result.displayMessage = 'Sent Successfully';
                result.hasValidationError = false;
                checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            }
            else {
                result.displayMessage = 'Error in Sending OTP';
                result.hasValidationError = true;
                checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                checklist.Functional_Failure_Reason__c = 'Error in Sending OTP';
            }
        }
        catch(Exception e) {
            result.displayMessage = 'Error in Sending OTP';
            result.hasValidationError = true;
            result.errorMessage = e.getMessage();
            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
            checklist.Functional_Failure_Reason__c = e.getMessage();
        }
        finally {
            if(!Trigger.isExecuting) {
                checklist.Status__c = Constants.CHECKLIST_STATUS_COMPLETED;
                update checklist;
            }
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{result};
    }

    /**
    * @description       : Prepare Record for Send Email OTP API.
    * @param recordIds   : List of Record IDs.
    * @return            : List of Applicant records.
    */
    public List<sObject> prepareRecordForIntegration(List<Id> recordIds) {
        List<Applicant__c> applicantList = [
            SELECT Id, Email__c, Email_Verification_Code__c, Email_Verification_Code_Generated_Time__c
            FROM Applicant__c
            WHERE Id IN :recordIds
        ];
        return applicantList;
    }

    /* request wrapper for Send Email OTP API */
    public class SendEmailOTPRequestWrapper {
        public String enterpriseid;
        public String subEnterpriseid;
        public String pusheid;
        public String pushepwd;
        public String contenttype;
        public String sender;
        public String alert;
        public String emailid;
        public String msgtext;
        public String selfid;
        public String dlreq;
        public String intflag;
    }

    /* response wrapper for Send Email OTP API */
    public class SendEmailOTPResponseWrapper {
        public String request_id                                                   { get; set; }
        public String status                                                       { get; set; }
        public String message                                                      { get; set; }
        public Boolean success                                                     { get; set; }
    }
}