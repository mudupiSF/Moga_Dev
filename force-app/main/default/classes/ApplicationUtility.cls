/*******************************************************************************************
* @Name         ApplicationUtility
* @Author       Sourav Sharma
* @Description  This Utility class will be used to write all the helper or Utility methods, used
				in application.
*******************************************************************************************/
/* MODIFICATION LOG
* Version          Developer           Date               Description
*-------------------------------------------------------------------------------------------
*  1.0             Sourav Sharma       11/07/2025         Initial Creation 
*******************************************************************************************/
public without sharing class ApplicationUtility {
    

    public static Integer retryCount = 0;
    
    /**
    * @author        	  : Sourav Sharma
    * @description        : Create integration checklist record.
    * @param leadID		  : ID of the current lead record.
    * @param intgMasterRec: Integration master record.
    * @return             : Created integration checklist record.
    */
    @AuraEnabled
    public static Integration_Checklist__c createICRecord(String recordId, Integration_Master__c intgMasterRec, String objectAPIName) {

        Integration_Checklist__c icRec = new Integration_Checklist__c();

        if(objectAPIName == 'Applicant__c') {
            icRec.Applicant__c = recordId;
        }

        // TODO : Add Actual Lookup Field Names HERE
        /*
        if(objectAPIName == 'Lead') {
            icRec.Lead__c = recordId;
        }
        else if(objectAPIName == 'Applicant__c') {
            icRec.Applicant__c = recordId;
        }
        else if(objectAPIName == 'Opportunity') {
            icRec.Loan_Application__c = recordId;
        }
        else if(objectAPIName == 'Event') {
            icRec.Event_Id__c = recordId;
        }  else if(objectAPIName == 'Documents_Checklist__c') {
            icRec.Documents_Checklist_ID__c = recordId;
        }
            */

        icRec.Integration_Master_ID__c = intgMasterRec.ID;
        icRec.Integration_Master_Name__c = intgMasterRec.Name;
        icRec.Action_Master_Name__c = intgMasterRec.Action_Master_Name__c;
        icRec.Status__c = 'In Progress';
        // Use this field for Retry Allowed or Not
        icRec.Is_Auto_Initiated__c = intgMasterRec.Is_Auto_Initiated__c;
        icRec.Max_Number_of_Retries_Allowed__c = intgMasterRec.Max_Number_of_Retries_Allowed__c;
        icRec.Is_Latest__c = true;
        // Encryption and Decryption related fields
        icRec.Encrypt_Request__c = intgMasterRec.Encrypt_Request__c;
        icRec.Decrypt_Response__c = intgMasterRec.Decrypt_Response__c;
        icRec.Encryption_Setting_Name_Encryption__c = intgMasterRec.Encryption_Setting_Name_Encryption__c;
        icRec.Encryption_Setting_Name_Decryption__c = intgMasterRec.Encryption_Setting_Name_Decryption__c;
        icRec.Is_Mocking_Service_Enabled__c = intgMasterRec.Is_Mocking_Service_Enabled__c;
        icRec.Mocking_Service_Response__c = intgMasterRec.Mocking_Service_Response__c;
        icRec.Mocking_Service_Status__c = intgMasterRec.Mocking_Service_Status__c;
        icRec.Mocking_Service_Status_Code__c = intgMasterRec.Mocking_Service_Status_Code__c;
        icRec.Apex_Class_Name__c = intgMasterRec.Apex_Class_Name__c;
        
        return icRec;
    }
    
    /**
	* @author        	  : Sourav Sharma
    * @description        : Get integration master record by providing master record name.
    * @param masterName   : master record name.
    * @return             : List of integration master records.
    */
    @AuraEnabled
    public static List<Integration_Master__c> getIMRecordByName(String masterName) {

        return [SELECT
                ID,
                Name,
                Allow_Retry__c,
                Allow_Refresh__c,
                Encrypt_Request__c,
                Encryption_Setting_Name_Encryption__c,
                Decrypt_Response__c,
                Encryption_Setting_Name_Decryption__c,
                Max_Number_of_Retries_Allowed__c,
                Maximum_Limit_Exceeded_Error_Message__c,
                Is_Auto_Initiated__c,
                Is_Mocking_Service_Enabled__c,
                Mocking_Service_Response__c,
                Mocking_Service_Status__c,
                Action_Master_Name__c,
                Mocking_Service_Status_Code__c,
                Apex_Class_Name__c,
                End_Point_URL__c
                FROM Integration_Master__c
                WHERE Name =: masterName
                
                LIMIt 1];
    }

    

    /**
	* @author        	  : Sourav Sharma
    * @description        : Get integration master records by providing IDs.
    * @param imIDSet      : ID set.
    * @return             : List of integration master records.
    */
    public static List<Integration_Master__c> getIMRecordsByIDs(Set<Id> imIDSet) {

        return [SELECT
                ID,
                Name,
                Allow_Retry__c,
                Allow_Refresh__c,
                Encrypt_Request__c,
                Encryption_Setting_Name_Encryption__c,
                Decrypt_Response__c,
                Encryption_Setting_Name_Decryption__c,
                Max_Number_of_Retries_Allowed__c,
                Maximum_Limit_Exceeded_Error_Message__c,
                Is_Auto_Initiated__c,
                Is_Mocking_Service_Enabled__c,
                Mocking_Service_Response__c,
                Mocking_Service_Status__c,
                Mocking_Service_Status_Code__c,
                Apex_Class_Name__c,
                End_Point_URL__c
                FROM Integration_Master__c
                WHERE ID IN : imIDSet
                WITH USER_MODE];
    }
    
    
    /**
    * @author        	  : Ritika Dhandia
    * @description        : Invoke Integration Sync - for One Record only from UI
    * @param masterName   : Master Name.
    * @param recordId     : Record ID.
    * @param objectAPIName: Object API Name (Lead / Applicant__c / Loan_Application__c)
    * @return             : Integration Response Wrapper.
    */
    @AuraEnabled
    public static IntegrationResponseWrapper invokeIntegrationSync(String masterName, String recordId, String objectAPIName) {

        IntegrationResponseWrapper response = new IntegrationResponseWrapper();
        try{
            // Get IM Record BY Name
            List<Integration_Master__c> integMasterList = getIMRecordByName(masterName);
            if (integMasterList.isEmpty()) {
                response.hasValidationError = true;
                response.errorMessage = 'Integration Master record with name "' + masterName + '" not found';
                return response;
            }
            Integration_Master__c integMaster = integMasterList[0];

            Boolean isRetryAllowed = false;
            Boolean isRefreshAllowed = false;
            Integer existingICRecordCountFailure = getExistingICRecordCount(recordId, integMaster.Name, objectAPIName, 'Failure');
            Integer existingICRecordCountSuccess = getExistingICRecordCount(recordId, integMaster.Name, objectAPIName, 'Success');
            isRefreshAllowed = integMaster.Allow_Refresh__c ? true : (existingICRecordCountSuccess == 0 ? true : false);
            if(integMaster.Allow_Retry__c) {
                if(existingICRecordCountFailure >= integMaster.Max_Number_of_Retries_Allowed__c) {
                    response.hasValidationError = true;
                    response.errorMessage = 'Maximum number of retries allowed were reached.';
                    return response;
                }
                else {
                    isRetryAllowed = true;
                }
            }
            else {
                if(existingICRecordCountFailure == 0) {
                    isRetryAllowed = true;
                }
                else {
                    isRetryAllowed = false;
                    response.hasValidationError = true;
                    response.errorMessage = 'Retry is not allowed as it has already been attempted and failed.';
                    return response;
                }
            }
            if(!isRefreshAllowed) {
                response.hasValidationError = true;
                response.errorMessage = 'Refresh is not allowed as it has already been attempted and successful.';
                return response;
            }
            
            if(isRetryAllowed && isRefreshAllowed) {
                // Get Integration Handler Instance
                IIntegrationHandler integHandler = (IIntegrationHandler)Type.forName(integMaster.Apex_Class_Name__c).newInstance();
                // Prepare Record for Integration Request
                List<sObject> request = integHandler.prepareRecordForIntegration(new List<Id>{recordId});
                // Validate Request
                List<IntegrationResponseWrapper> validationResponse = (List<IntegrationResponseWrapper>)integHandler.validateInputData(request);
                
                if(validationResponse[0].hasValidationError) {
                    response = validationResponse[0];
                }
                else {
                    // Generate Request
                    List<IntegrationRequestWrapper> calloutRequestList = (List<IntegrationRequestWrapper>)integHandler.generateRequest(request);
                    IntegrationUtility.RequestWrapper reqWrapper = new IntegrationUtility.RequestWrapper();
                    IntegrationRequestWrapper calloutRequest = calloutRequestList[0];
                    reqWrapper.masterRecord = integMaster;
                    reqWrapper.endpointURL = calloutRequest.urlEndPoint != null ? calloutRequest.urlEndPoint : integMaster.End_Point_URL__c;
                    reqWrapper.captureRequestInAttachment = calloutRequest.captureRequestInAttachment;
                    if(calloutRequest.urlParameter != null){
                        reqWrapper.endpointURL += calloutRequest.urlParameter;
                    }
                    if(calloutRequest.urlParamterMap != null){
                        reqWrapper.urlParamterMap = calloutRequest.urlParamterMap;
                    }
                    reqWrapper.method = calloutRequest.method != null ? calloutRequest.method : 'POST';
                    reqWrapper.request = calloutRequest.requestBody;
                    reqWrapper.headersMap = calloutRequest.headersMap;
                    // Callout using IntegrationUtility class

                    // We do not insert the Integration Checklist Record here, as it will be inserted in the initiateCallout method
                    Integration_Checklist__c icRec = createICRecord(recordId, integMaster, objectAPIName);
                    reqWrapper.checklistRecord = icRec;


                    IntegrationUtility utilityInstance = new IntegrationUtility();
                    IntegrationUtility.ResponseWrapper calloutResponse = utilityInstance.initiateCallout(reqWrapper);
                    response.calloutResponse = calloutResponse;

                    // Process the response
                    List<IntegrationResponseWrapper> processedResponse = (List<IntegrationResponseWrapper>)integHandler.processResponse(new List<IntegrationUtility.ResponseWrapper>{calloutResponse});
                    return processedResponse[0];
                }
            }
        }
        catch(Exception e){
            response.errorMessage = e.getMessage();
            response.hasValidationError = true;
        }
        return response;
    }

    /**
    * @author        	  : Ritika Dhandia
    * @description        : Invoke Integration Async - for One Record only from UI or Trigger
    * @param masterName   : Master Name.
    * @param recordId     : Record ID.
    * @param objectAPIName: Object API Name (Lead / Applicant__c / Communication_Log__c / Loan_Application__c)
    * @return             : Integration Response Wrapper.
    */
    @AuraEnabled
    public static IntegrationResponseWrapper invokeIntegrationASync(String masterName, String recordId, String objectAPIName) {

        IntegrationResponseWrapper response = new IntegrationResponseWrapper();
        try{
            // Get IM Record BY Name
            List<Integration_Master__c> integMasterList = getIMRecordByName(masterName);
            if (integMasterList.isEmpty()) {
                response.hasValidationError = true;
                response.errorMessage = 'Integration Master record with name "' + masterName + '" not found';
                return response;
            }
            Integration_Master__c integMaster = integMasterList[0];

            // Get Integration Handler Instance
            IIntegrationHandler integHandler = (IIntegrationHandler)Type.forName(integMaster.Apex_Class_Name__c).newInstance();
            // Prepare Record for Integration Request
            List<sObject> request = integHandler.prepareRecordForIntegration(new List<Id>{recordId});
            // Validate Request
            List<IntegrationResponseWrapper> validationResponse = (List<IntegrationResponseWrapper>)integHandler.validateInputData(request);
            if(validationResponse[0].hasValidationError) {
                response = validationResponse[0];
            }
            else {
                // Generate Request
                List<IntegrationRequestWrapper> calloutRequest = (List<IntegrationRequestWrapper>)integHandler.generateRequest(request);

                Integer retryInterval = 3;

                // Create Integration Checklist Record, so the Id can be used in the Integration Outbound Event
                Integration_Checklist__c icRec = createICRecord(recordId, integMaster, objectAPIName);
                icRec.Request__c = calloutRequest[0].requestBody;
                icRec.Status__c = 'In Progress';
                icRec.Next_Retry__c = DateTime.now().addMinutes(retryInterval);
                icRec.Retry_Attempt__c = retryCount;
                insert icRec;
                
                Database.SaveResult sr;
                // Create Integration Outbound Event
                Integration_Outbound__e event = new Integration_Outbound__e();
                event.Integration_Id__c = icRec.Id;
                event.Integration_Name__c = integMaster.Name.split('_')[0];
                if(icRec != null && icRec.Id != null) {
                    calloutRequest[0].requestBody = updateIntegIdInRequest(calloutRequest[0].requestBody, icRec.Id);
                }
                event.Request_Payload__c = calloutRequest[0].requestBody;
                event.Service_Name__c = integMaster.Name.split('_')[0];
                sr = EventBus.publish(event);
            
                // Inspect publishing result
                if(sr != null) {
                    if (sr.isSuccess()) {
                        response.displayMessage = 'Integration Request Published Successfully';
                        response.hasValidationError = false;
                    }
                    else {
                        Database.Error err = sr.getErrors()[0];
                        response.errorMessage = err.getMessage();
                        response.hasValidationError = true;
                    }
                }
            }
        }
        catch(Exception e){
            response.errorMessage = e.getMessage();
            response.hasValidationError = false;
        }
        return response;
    }

    private static String updateIntegIdInRequest(String requestBody, String requestId) {
        return requestBody.replace('<INTEG_ID_PLACEHOLDER>', requestId);
    }

   
    /**
    * @author        	  : Ritika Dhandia
    * @description        : Process Integration Async - for Bulk Records from Trigger
    * @param calloutResponse: Callout Response.
    * @return             : Integration Response Wrapper.
    */
    public static List<IntegrationResponseWrapper> processIntgerationAsync(List<IntegrationUtility.ResponseWrapper> calloutResponseList) {
    
        List<IntegrationResponseWrapper> responseList = new List<IntegrationResponseWrapper>();
        Map<String, List<IntegrationUtility.ResponseWrapper>> calloutResponseMap = new Map<String, List<IntegrationUtility.ResponseWrapper>>();
        // Group the callout responses by the Integration Master Record
        for(IntegrationUtility.ResponseWrapper calloutResponse : calloutResponseList) {
            Integration_Checklist__c checklistRecord = calloutResponse.checklistRecord;
        
            if(!calloutResponseMap.containsKey(checklistRecord.Apex_Class_Name__c)) {
                calloutResponseMap.put(checklistRecord.Apex_Class_Name__c, new List<IntegrationUtility.ResponseWrapper>{calloutResponse});
            }
            else {
                calloutResponseMap.get(checklistRecord.Apex_Class_Name__c).add(calloutResponse);
            }
        }
        for(String calloutResponseMapKey : calloutResponseMap.keySet()) {
            IIntegrationHandler integHandler = (IIntegrationHandler)Type.forName(calloutResponseMapKey).newInstance();
            List<IntegrationResponseWrapper> processedResponse = (List<IntegrationResponseWrapper>)integHandler.processResponse(calloutResponseMap.get(calloutResponseMapKey));
            responseList.add(processedResponse[0]);
        }
        return responseList;
    }


    @InvocableMethod(label='Invoke Integration Sync' description='Invoke Integration Sync')
    public static void invokeIntegrationASyncRetrigger(List<String> recordId) {
        
        // Only run for one record at a time
        Integration_Checklist__c icRec = [
                                            SELECT Id, Status__c, Next_Retry__c ,Retry_Attempt__c,
                                            Applicant__c,
                                            Integration_Master_Name__c,
                                            Max_Number_of_Retries_Allowed__c,
                                            Is_Auto_Initiated__c
                                            FROM Integration_Checklist__c 
                                            WHERE Id =: recordId[0]];
        
        // Only if is Auto Initiated is True (Retry is Allowed) and Max Number of Retries
        // have not reached, we create a new one

        retryCount = Integer.valueOf(icRec.Retry_Attempt__c) + 1;
        if(retryCount <= icRec.Max_Number_of_Retries_Allowed__c) {

            if(icRec.Applicant__c != null) {
                IntegrationResponseWrapper response = invokeIntegrationASync(icRec.Integration_Master_Name__c, icRec.Applicant__c, 'Applicant__c');
            }
            // TODO : Add Actual Lookup Field Names HERE
            /*
            if(icRec.Lead__c != null){
                IntegrationResponseWrapper response = invokeIntegrationASync(icRec.Integration_Master_Name__c, icRec.Lead__c, 'Lead');
            }
            else if(icRec.Applicant__c != null){
                IntegrationResponseWrapper response = invokeIntegrationASync(icRec.Integration_Master_Name__c, icRec.Applicant__c, 'Applicant__c');
            }
            else if(icRec.Loan_Application__c != null){
                IntegrationResponseWrapper response = invokeIntegrationASync(icRec.Integration_Master_Name__c, icRec.Loan_Application__c, 'Opportunity');
            }
            else if(icRec.Documents_Checklist_ID__c != null){
                IntegrationResponseWrapper response = invokeIntegrationASync(icRec.Integration_Master_Name__c, icRec.Documents_Checklist_ID__c, 'Documents_Checklist_ID__c');
            }
            else if(icRec.Event_Id__c != null){
                IntegrationResponseWrapper response = invokeIntegrationASync(icRec.Integration_Master_Name__c, icRec.Event_Id__c, 'Event');
            }
            */
        }
        else {
            // Mark the Integrations as Failed
            // With this, the integration handlers should also mark the AC as Failed
            icRec.Status__c = 'Failure';
            icRec.Functional_Status__c = 'Failure';
            update icRec;

            /*
            Integration_Master__c intgMaster = [
                SELECT Id, Action_Master_Name__c
                FROM Integration_Master__c
                WHERE Name =: icRec.Integration_Master_Name__c
            ];

            List<Action_Checklist__c> actionChecklistList = 
                [
                    SELECT Id, Status__c 
                    FROM Action_Checklist__c 
                    WHERE Action_Master_Name__c =: intgMaster.Action_Master_Name__c 
                    AND Loan_Application__c =: icRec.Loan_Application__c
                    AND Status__c = 'In Progress'
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];

            if(!actionChecklistList.isEmpty()) {
                actionChecklistList[0].Status__c = Constants.ACTION_CHECKLIST_STATUS_FAILED;
                update actionChecklistList[0];
            }*/
        }
    }

    /**
    * @author        	  : Sourav Sharma
    * @description        : Get existing integration checklist record.
    * @param recordId     : Record ID.
    * @param integrationMasterName: Integration Master Name.
    * @param objectAPIName: Object API Name.
    * @return             : Existing integration checklist record count.
    */
    public static Integer getExistingICRecordCount(String recordId, String integrationMasterName, String objectAPIName, String status) {
        String query = 'SELECT COUNT() FROM Integration_Checklist__c WHERE Integration_Master_Name__c =: integrationMasterName AND Status__c =: status';   
        if(objectAPIName == 'Applicant__c') {
            query += ' AND Applicant__c =: recordId';
        }
        return Database.countQuery(query);
    }

    public class IntegrationResponseWrapper {
    
        @AuraEnabled
        public Boolean hasValidationError											{get;set;}
        @AuraEnabled
        public String errorMessage													{get;set;}
        @AuraEnabled
        public String recordId														{get;set;}
        @AuraEnabled
        public IntegrationUtility.ResponseWrapper calloutResponse					{get;set;}
        @AuraEnabled
        public String displayMessage				                                {get;set;}
    }

    public class IntegrationRequestWrapper {
        
        public Boolean captureRequestInAttachment = false;
        public Boolean captureResponseInAttachment = false;
        @AuraEnabled
        public String requestBody											        {get;set;}
        @AuraEnabled
        public Map<String,String> headersMap										{get;set;}
        @AuraEnabled
        public String urlParameter											        {get;set;}
        @AuraEnabled
        public Map<String,String> urlParamterMap									{get;set;}
        @AuraEnabled
        public String method											            {get;set;}
        @AuraEnabled
        public String urlEndPoint											        {get;set;}
        @AuraEnabled
        public String recordId													    {get;set;}

    }
}