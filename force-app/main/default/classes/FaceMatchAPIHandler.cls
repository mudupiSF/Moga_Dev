/**
 * Integration Master handler for Face Match.
 */
public with sharing class FaceMatchAPIHandler implements IIntegrationHandler {

    public static final String INTEGRATION_KEY = 'Face Match';
    private static final String DOC_TYPE_CUSTOMER_IMAGE = 'Customer Image';

    public List<SObject> prepareRecordForIntegration(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<SObject>();
        }
        Id applicantId = recordIds[0];

        List<Document_CheckList__c> checklistRows = [
            SELECT Id, ContentVersionId__c
            FROM Document_CheckList__c
            WHERE Applicant__c = :applicantId
              AND Document_Type__c = :DOC_TYPE_CUSTOMER_IMAGE
              AND Is_Active__c = true
              AND ContentVersionId__c != null
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (checklistRows.isEmpty()) {
            return new List<SObject>();
        }

        return [
            SELECT Id, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE Id = :checklistRows[0].ContentVersionId__c
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> validateInputData(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper wrapper = new ApplicationUtility.IntegrationResponseWrapper();
        wrapper.hasValidationError = false;
        if (recordList == null || recordList.isEmpty() || recordList[0] == null) {
            wrapper.hasValidationError = true;
            wrapper.errorMessage = 'Customer Image is required before Face Match.';
            wrapper.displayMessage = wrapper.errorMessage;
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationRequestWrapper> generateRequest(List<Object> recordList) {
        ContentVersion imageVersion = (ContentVersion) recordList[0];
        ApplicationUtility.IntegrationRequestWrapper wrapper = new ApplicationUtility.IntegrationRequestWrapper();
        wrapper.method = 'POST';
        wrapper.requestBody = JSON.serialize(new Map<String, Object>{
            'fileName' => imageVersion.Title,
            'fileExtension' => imageVersion.FileExtension,
            'imageBase64' => EncodingUtil.base64Encode(imageVersion.VersionData)
        });
        return new List<ApplicationUtility.IntegrationRequestWrapper>{ wrapper };
    }

    public List<ApplicationUtility.IntegrationResponseWrapper> processResponse(List<Object> recordList) {
        ApplicationUtility.IntegrationResponseWrapper result = new ApplicationUtility.IntegrationResponseWrapper();
        IntegrationUtility.ResponseWrapper wrapper = (IntegrationUtility.ResponseWrapper) recordList[0];
        Integration_Checklist__c checklist = (Integration_Checklist__c) wrapper.checklistRecord;

        try {
            Integer statusCode = wrapper == null ? 0 : wrapper.statusCode;
            if (statusCode >= 200 && statusCode < 300) {
                result.hasValidationError = false;
                result.displayMessage = 'Face Match completed.';
                checklist.Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
                checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_SUCCESS;
            } else {
                result.hasValidationError = true;
                result.errorMessage = String.isNotBlank(wrapper.response)
                    ? wrapper.response
                    : 'Face Match failed.';
                result.displayMessage = result.errorMessage;
                checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
                checklist.Functional_Failure_Reason__c = String.isNotBlank(result.errorMessage)
                    ? result.errorMessage.left(255)
                    : 'Face Match failed.';
            }
        } catch (Exception ex) {
            result.hasValidationError = true;
            result.errorMessage = ex.getMessage();
            result.displayMessage = ex.getMessage();
            checklist.Status__c = Constants.CHECKLIST_STATUS_FAILURE;
            checklist.Functional_Status__c = Constants.CHECKLIST_STATUS_FAILURE;
            checklist.Functional_Failure_Reason__c = ex.getMessage() == null
                ? 'Face Match failed.'
                : ex.getMessage().left(255);
        } finally {
            if (!Trigger.isExecuting) {
                update checklist;
            }
        }
        return new List<ApplicationUtility.IntegrationResponseWrapper>{ result };
    }
}