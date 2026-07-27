public class IntegrationUtility {
    
    public static Boolean MULTIPLE_IC = false;
    
    public ResponseWrapper initiateCallout(RequestWrapper requestInstance) {

        if (requestInstance.masterRecord == NULL) {
            throw new HandledException('Integration Master details are mandatory for initiating an interface');
        }
        if (String.isBlank(requestInstance.method)) {
            throw new HandledException('Method is mandatory for initiating an interface');
        }
        if (String.isBlank(requestInstance.endpointURL) && String.isBlank(requestInstance.masterRecord.End_Point_URL__c)) {
            throw new HandledException('Endpoint URL is mandatory. Update these details in master or in the input parameters');
        }
        
        List<ContentVersion> calloutDetails = new List<ContentVersion>();
        ResponseWrapper responseInstance = new ResponseWrapper();
        HTTPResponse response;
        Boolean isBlobRequest = false;
        Integration_Checklist__c checklistRecord = requestInstance.checklistRecord ?? new Integration_Checklist__c();
        checklistRecord.Is_Latest__c = true;
        checklistRecord.Integration_Master_ID__c = requestInstance.masterRecord.Id;
        
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod(requestInstance.method);
            request.setTimeout(requestInstance.timeOut);

            // Get Access Token
            //String accessToken = GlobalCacheManager.getAWSAccessToken();
            //request.setHeader('Authorization', 'Bearer ' + accessToken);

            if(requestInstance.urlParamterMap != NULL && !requestInstance.urlParamterMap.isEmpty()) {

                String query = '';
                for(String key : requestInstance.urlParamterMap.keySet()) {

                    String value = requestInstance.urlParamterMap.get(key);
                    query += '&' + key + '=' + value;
                }
                checklistRecord.URL_Parameters__c = query.substring(1);
                query = '?' + query.substring(1);
                String endPoint = requestInstance.masterRecord.End_Point_URL__c + query;
                request.setEndPoint(endPoint);
            }
            else {
                request.setEndPoint(requestInstance.endpointURL);
            }
            if (String.isNotBlank(requestInstance.contentType)) {

                request.setHeader('Content-Type', requestInstance.contentType);
            }
           if(requestInstance.headersMap != NULL && !requestInstance.headersMap.isEmpty()) {

                for(String header : requestInstance.headersMap.keySet()) {

                    if(requestInstance.headersMap.get(header) != '' && requestInstance.headersMap.get(header) != null) {

                        request.setHeader( header, requestInstance.headersMap.get(header));
                    }    
                }
            }
            if(requestInstance.request != null) {
                // Encrypt the request if the encrypt request flag is true
                if(checklistRecord.Encrypt_Request__c) {
                    if(String.isNotBlank(checklistRecord.Encryption_Setting_Name_Encryption__c)) {
                        request.setBody(getEncryptedRequest(requestInstance.request, checklistRecord.Encryption_Setting_Name_Encryption__c));
                    }
                    else {
                        request.setBody(requestInstance.request);
                    }
                }
                else {
                    request.setBody(requestInstance.request); 
                }
            }
            if(requestInstance.requestBlob != null) {

                request.setBodyAsBlob(requestInstance.requestBlob);
                isBlobRequest = true;
            }
            checklistRecord.Request_Initiated_At__c = System.now();
            if (requestInstance.captureRequestInAttachment || checklistRecord.Is_Request_in_Attachment__c) {
                checklistRecord.Is_Request_in_Attachment__c = true;
            }
            else {
                checklistRecord.Request__c = requestInstance.request;
                // Encrypt the request if the encrypt request flag is true
                if(checklistRecord.Encrypt_Request__c) {
                    if(String.isNotBlank(checklistRecord.Encryption_Setting_Name_Encryption__c)) {
                        checklistRecord.Encrypted_Request__c = getEncryptedRequest(requestInstance.request, checklistRecord.Encryption_Setting_Name_Encryption__c);
                    }
                    else {
                        checklistRecord.Encrypted_Request__c = requestInstance.request;
                    }
                }
            }
            Http http = new Http();
            if(!checklistRecord.Is_Mocking_Service_Enabled__c) {
                response = http.send(request);
                system.debug('API response ---'+response);
            }
            else {
                response = generateMockingResponse(checklistRecord);
                system.debug('Mock response ---'+response);
                System.debug('Mock response body: ' + response.getBody());
            }
            //Rahul Adding logic for mocking service end
            checklistRecord.Status__c = 'Success'; // trigger layer uses callback service to set this to failed if response is not intact
            checklistRecord.Response_Received_At__c = System.now();
            
            if (requestInstance.captureResponseInAttachment) {
                checklistRecord.Is_Response_In_Attachment__c = true;
            }
            else {
                if(checklistRecord.Decrypt_Response__c) {
                    if(String.isNotBlank(checklistRecord.Encryption_Setting_Name_Decryption__c)) {
                        checklistRecord.Decrypted_Response__c = getDecryptedResponse(response.getBody(), checklistRecord.Encryption_Setting_Name_Decryption__c);
                        responseInstance.response = getDecryptedResponse(response.getBody(), checklistRecord.Encryption_Setting_Name_Decryption__c);
                    }
                    else {
                        checklistRecord.Decrypted_Response__c = response.getBody();
                        responseInstance.response = response.getBody();
                    }
                }
                else {
                    checklistRecord.Response__c = response.getBody();
                    responseInstance.response = response.getBody();
                }
            }
            responseInstance.checklistRecord = checklistRecord;
            responseInstance.statusCode = response.getStatusCode();
            if(requestInstance.getResponseAsBlob ){
                responseInstance.blobResponse = response?.getBodyAsBlob();
            }
            responseInstance.responsebody = response;
            if (requestInstance.captureRequestInAttachment || requestInstance.captureResponseInAttachment || checklistRecord.Is_Request_in_Attachment__c) {
                if (requestInstance.captureRequestInAttachment || checklistRecord.Is_Request_in_Attachment__c) {
                    ContentVersion cvObj = new ContentVersion(VersionData = (isBlobRequest ? requestInstance.requestBlob : Blob.valueOf(requestInstance.request)), Title = 'Request', PathOnClient = 'Request.txt');                
                    calloutDetails.add(cvobj);
                    // Add the encrypted request if the encrypt request flag is true
                    if(checklistRecord.Encrypt_Request__c) {
                        ContentVersion cvObjEncrypted;
                        if(String.isNotBlank(checklistRecord.Encryption_Setting_Name_Encryption__c)) {
                            cvObjEncrypted = new ContentVersion(VersionData = Blob.valueOf(getEncryptedRequest(requestInstance.request, checklistRecord.Encryption_Setting_Name_Encryption__c)), Title = 'Encrypted Request', PathOnClient = 'Encrypted Request.txt');
                        }
                        else {
                            cvObjEncrypted = new ContentVersion(VersionData = Blob.valueOf(requestInstance.request), Title = 'Encrypted Request', PathOnClient = 'Encrypted Request.txt');
                        }
                        calloutDetails.add(cvObjEncrypted);
                    }
                }
                if (requestInstance.captureResponseInAttachment) {
                    ContentVersion cvObj = new ContentVersion(VersionData = Blob.valueOf(response.getBody()), Title = 'Response', PathOnClient = 'Response.txt');
                    calloutDetails.add(cvobj);
                    // Add the decrypted response if the decrypt response flag is true
                    if(checklistRecord.Decrypt_Response__c) {
                        ContentVersion cvObjDecrypted;
                        if(String.isNotBlank(checklistRecord.Encryption_Setting_Name_Decryption__c)) {
                            cvObjDecrypted = new ContentVersion(VersionData = Blob.valueOf(getDecryptedResponse(response.getBody(), checklistRecord.Encryption_Setting_Name_Decryption__c)), Title = 'Decrypted Response', PathOnClient = 'Decrypted Response.txt');
                        }
                        else {
                            cvObjDecrypted = new ContentVersion(VersionData = Blob.valueOf(response.getBody()), Title = 'Decrypted Response', PathOnClient = 'Decrypted Response.txt');
                        }
                        calloutDetails.add(cvObjDecrypted);
                    }
                }
                if(MULTIPLE_IC) {
                    responseInstance.calloutDetails = calloutDetails;
                }
            }
            //Yashdeep adding logic for adding blob as attachment
            if(requestInstance.getResponseAsBlob) {
                ContentVersion cvObj = new ContentVersion(VersionData = responseInstance.blobResponse, Title = 'Digio Signed Document', PathOnClient = 'Signed.pdf');
                calloutDetails.add(cvobj);
            }

        }
        catch(CalloutException ex) {
            System.debug('*** Exception 1 --> ' + ex.getMessage() + '  Line No ---> ' + ex.getLineNumber());
            checklistRecord.Status__c = 'Failure';
            responseInstance.response = ex.getMessage();
        }
        catch (Exception ex) {
            System.debug('*** Exception 2 --> ' + ex.getMessage() + '  Line No ---> ' + ex.getLineNumber());
            checklistRecord.Status__c = 'Failure';
            responseInstance.response = ex.getMessage();
        }
        if(!MULTIPLE_IC) {
            upsert checklistRecord;
            if(!calloutDetails.isEmpty()){
                for(ContentVersion cv: calloutDetails){
                    cv.FirstPublishLocationId = checklistRecord.Id;
                }
                upsert calloutDetails;
            }
        }
        return responseInstance;
    }
    
    /*
    @InvocableMethod(label='Retry Integrations' description='Retry the failed or pending integrations.')
    public static void retryIntegrations(List<Integration_Checklist__c> intgChcklstList) {

        List<Integration_Checklist__c> icToUpdateList = new List<Integration_Checklist__c>();
        List<Integration_Checklist__c> icToRetryList = new List<Integration_Checklist__c>();
        List<Integration_Checklist__c> icToInsertList = new List<Integration_Checklist__c>();
        Map<String, Integration_Master__c> imIDMap = new Map<String, Integration_Master__c>();
        Map<Integer, Integer> integrationsAttemptMap = new Map<Integer, Integer>();
        Map<Integer,Integer> leadIntgIdVsAttemptMap = new Map<Integer,Integer>();
        Set<String> icIDSet = new Set<String>();
        Set<Id> imIDSet = new Set<Id>();
        Set<String> leadIDSet = new Set<String>();
        String retryEnabledStatus = ApplicationUtility.getApplIntgConfigMdtValue('Retry_Enabled_Statuses', true);
        for(Integration_Checklist__c icRecord : intgChcklstList) {
            if(retryEnabledStatus.split(',').contains(icRecord.Status__c)) {
                icIDSet.add(icRecord.ID);
                imIDSet.add(icRecord.Integration_Master__c);
                if(String.isNotBlank(icRecord.Lead__c)) {
                    leadIDSet.add(icRecord.Lead__c);
                } 
            }
        }
        if(!imIDSet.isEmpty()) {

            for(Integration_Checklist__c icRecord : [SELECT
                                                    ID,
                                                    Lead__c,
                                                    Lead__r.Status,
                                                    Integration_Master__c
                                                    FROM Integration_Checklist__c
                                                    WHERE Lead__c IN : leadIDSet
                                                    AND ID NOT IN : icIDSet
                                                    WITH USER_MODE])
            {

                if(String.isNotBlank(icRecord.Lead__c)) {

                    if(icRecord.Lead__r.Status == 'New') {

                        String tempKey = icRecord.Lead__c+'_'+icRecord.Integration_Master__c;
                        Integer ihashKey = tempKey.hashCode();
                        if(!integrationsAttemptMap.containsKey(ihashKey)) {

                            integrationsAttemptMap.put(ihashKey, 0);
                        }
                        Integer iTempCounter = integrationsAttemptMap.get(ihashKey);
                        iTempCounter++;
                        integrationsAttemptMap.put(ihashKey, iTempCounter);
                    }
                }
            }
            for(Integration_Master__c imRecord : ApplicationUtility.getIMRecordsByIDs(imIDSet)) {

                imIDMap.put(imRecord.ID, imRecord);
            }
            for(Integration_Checklist__c icRecord : intgChcklstList) {

                if(imIDMap.containsKey(icRecord.Integration_Master__c)) {

                    if(String.isNotBlank(icRecord.Lead__c)) {

                        String tempKey = icRecord.Lead__c+'_'+icRecord.Integration_Master__c;
                        Integer ihashKey = tempKey.hashCode();
                        integer iAttempts = 0;
                        if(integrationsAttemptMap.containsKey(ihashKey)){

                            iAttempts = integrationsAttemptMap.get(ihashKey);
                        }
                        if(iAttempts <= imIDMap.get(icRecord.Integration_Master__c).Max_Number_of_Retries_Allowed__c) {
                            icToRetryList.add(icRecord);
                            // /*retry(icRecord);
                            // String tempCompositeKey = icRecord.Lead__c+'_'+icRecord.Integration_Master__c;
                            // Integer tempCompositeKeyInt = tempCompositeKey.hashCode();
                            // leadIntgIdVsAttemptMap.put(tempCompositeKeyInt, iAttempts);
                            // leadIDSet.add(icRecord.Lead__c);
                            // imIDSet.add(icRecord.Integration_Master__c);
                        }
                    }
                }
            }
            if(!icToRetryList.isEmpty()) {

                for(Integration_Checklist__c icRecord : icToRetryList) {
                    icRecord.ID = NULL;
                    icToInsertList.add(icRecord);
                }
            }
            if(!icToInsertList.isEmpty()) {

                insert icToInsertList;
            }


            // /*if(!leadIntgIdVsAttemptMap.isEmpty()) {

            //     for(Integration_Checklist__c icRecord : [SELECT
            //                                             ID,
            //                                             Integration_Master__c,
            //                                             Lead__c,
            //                                             Next_Retry__c,
            //                                             Is_Auto_Initiated__c
            //                                             FROM Integration_Checklist__c
            //                                             WHERE Status__c = 'Pending'
            //                                             AND Lead__c IN : leadIDSet
            //                                             AND Integration_Master__c IN :imIDSet])
            //     {

            //         String tempCompositeKey = icRecord.Lead__c+'_'+icRecord.Integration_Master__c;
            //         Integer tempCompositeKeyInt = tempCompositeKey.hashCode();
            //         if(leadIntgIdVsAttemptMap.containsKey(tempCompositeKeyInt)) {

            //             icRecord.Retry_Attempt__c = leadIntgIdVsAttemptMap.get(tempCompositeKeyInt);
            //             if(leadIntgIdVsAttemptMap.get(tempCompositeKeyInt) <= imIDMap.get(icRecord.Integration_Master__c).Max_Number_of_Retries_Allowed__c) {

            //                 if(leadIntgIdVsAttemptMap.get(tempCompositeKeyInt) == imIDMap.get(icRecord.Integration_Master__c).Max_Number_of_Retries_Allowed__c) {

            //                     icRecord.Next_Retry__c = NULL;
            //                     icRecord.Is_Auto_Initiated__c = false;
            //                 }
            //                 icToUpdateList.add(icRecord);
            //             }
            //         }
            //     }
            // }
            // if(!icToUpdateList.isEmpty()) {

            //     Database.update(icToUpdateList,false);
            // }
        }
    }
    */
    
    public static HttpResponse generateMockingResponse(Integration_Checklist__c icRec) {
        
        //Create a local variable for returning the response
        HTTPResponse mockResponse = new HTTPResponse();
        //Check if the response is present on the checklist else return default response
        System.debug('icRec: ' + icRec.Mocking_Service_Response__c);
        List<ContentDocumentLink> link = [
            SELECT Id, ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId =: icRec.Integration_Master_ID__c
            LIMIT 1
        ];
        
        if(link.size() == 1) {
            List<ContentVersion> response = [
                SELECT Id, VersionData 
                FROM ContentVersion 
                WHERE ContentDocumentId = :link[0].ContentDocumentId
            ];
            if(response != NULL && !response.isEmpty() && response[0].VersionData != NULL) {
                mockResponse.setBody(response[0].VersionData.toString());
            }
        }
        else if(String.isNotBlank(icRec.Mocking_Service_Response__c)) {
            mockResponse.setBody(icRec.Mocking_Service_Response__c);
        }
        else {
            mockResponse.setBody('{"status":"There has been an error}');
        }
        //Check if the status is present on the checklist else return default status as "Service Unavailable"
        if(String.isNotBlank(icRec.Mocking_Service_Status__c)) {
            mockResponse.setStatus(icRec.Mocking_Service_Status__c);
        }
        else {
            mockResponse.setStatus('Service unavailable');
        }
        //Check if the statuscode is present on the checklist else return default statuscode as 500
        if(icRec.Mocking_Service_Status_Code__c != NULL) {
            mockResponse.setStatusCode(Integer.valueof(icRec.Mocking_Service_Status_Code__c));
        }
        else {
            mockResponse.setStatusCode(500);
        }
        return mockResponse;
    }

    /*
    * @Method:      getEncryptedRequest
    * @Created by:  Ajay
    * @Description: Method to return Encrypted Request
    * @Param:       String - JSON Request
    * @Param:       String - metadataName
    * @Return:      String - encryptedString
    */
    public static String getEncryptedRequest(String requestJSON,String metadataName) {
        Blob privateKey = Blob.valueOf(getAPIKeys(metadataName, 'pkey'));
        Blob ivkey = Blob.valueOf(getAPIKeys(metadataName, 'iv')); 
        Blob data = Blob.valueOf(requestJSON);  
        Blob encrypted = Crypto.encrypt('AES256', privateKey, ivkey, data); 
        String encryptedString = EncodingUtil.base64Encode(encrypted);  
        return encryptedString;
    }
    
    /*
    * @Method:      getDecryptedResponse
    * @Created by:  Ajay
    * @Description: Method to return Decrypted Response
    * @Param:       String - JSON Response
    * @Param:       String - metadataName
    * @Return:      String - decryptedString
    */
    public static String getDecryptedResponse(String responseJSON,String metadataName) {
        Blob privateKey = Blob.valueOf(getAPIKeys(metadataName, 'pkey'));
        Blob ivkey = Blob.valueOf(getAPIKeys(metadataName, 'iv'));
        Blob data = EncodingUtil.base64Decode(responseJSON);
        Blob decrypted = Crypto.decrypt('AES256', privateKey, ivkey, data);   
        String decryptedString = decrypted.toString();  
        return decryptedString;
    }

    /*
    * @Method:      getAPIKeys
    * @Created by:  Ajay
    * @Description: Method used to get keys for encryption and decryption without managed iv
    * @Param:      String - metadataName
    * @Param:      String - keyType
    * @Return:     String
	*/
    public static String getAPIKeys(String metadataName, String keyType) {
        Encryption_Setting__mdt metadataApi = Encryption_Setting__mdt.getInstance(metadataName);
        
        if('pkey'.equals(keyType)){
            return metadataApi?.Private_Key__c;
        }
        if('iv'.equals(keyType)){
            return metadataApi?.IV_Key__c;
        }
        
        return '';
    }
    
    public class RequestWrapper {
        public String request;
        public Blob requestBlob;
        public Map<String,String> headersMap;        
        public String contentType;
        public Id applicantId;
        public Id obligationId;
        public Id loanApplicationId;
        public Id tataCardsLeadId;
        public Integer timeOut = 120000;
        public String method;
        public Integration_Master__c masterRecord;
        public Boolean captureResponseInAttachment = false;
        public Boolean captureRequestInAttachment = false;
        // use this when URL should include request parameters. If this is not set, the method will use URL in master
        public String endpointURL;
        public Integration_Checklist__c checklistRecord;
        public map<String,String> urlParamterMap;
        public Boolean getResponseAsBlob = false;
        public Boolean useDynamicURL = false;
    }
    
    public class ResponseWrapper {
        
        public HttpResponse responsebody;
        public String response;
        public Blob blobResponse;
        public Integer statusCode;
        public Integration_Checklist__c checklistRecord;
        public List<ContentVersion> calloutDetails;
    }

}