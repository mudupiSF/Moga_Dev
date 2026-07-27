public with sharing class FormReaderDriver {
	public class FormReaderException extends Exception {}

	@InvocableMethod(label='Read Form' description='Reads the given formType from the image in the given Content.')
    public static List<SObject> execute(List<Request> requestList) {

		// Unwrap parameters
		String templateName = requestList[0].templateName;
		String contentDocumentId = requestList[0].contentDocumentId;
		String formType = requestList[0].formType;
		SObject newObj = requestList[0].newObj;

		// Verify parameter
		if (String.isBlank(contentDocumentId)) {
			throw new AuraHandledException('Uploaded image file not found for ContentDocumentId ' + contentDocumentId);
		}

		ContentVersion cv = [select id, Title, VersionData from ContentVersion where ContentDocumentId =: contentDocumentId and isLatest = true];

		// Verify we have an image to test
		if (cv == null) {
			throw new AuraHandledException('Uploaded image file not found for ContentDocumentId ' + contentDocumentId);
		}

		// Perform OCR predictions
		einsteinplay.Einstein_PredictionService service = new einsteinplay.Einstein_PredictionService(einsteinplay.Einstein_PredictionService.Types.OCR);
		einsteinplay.Einstein_PredictionResult ocrResults = service.predictOcrBase64('tabulateV2', EncodingUtil.base64Encode(cv.VersionData), 'form', formType, null);

		// Retrieve the mapping template information
		FormReaderMappingConnector connector = new FormReaderMappingConnector();
		FormReaderMappingConnector.TemplateDescribe template = connector.createTemplateDescribe(templateName);
		Map<String, Schema.SObjectField> fieldMap = template.targetObjectType.getDescribe().fields.getMap(); 


		// For each mapped field, populate it with the value from the image
		for (String docFieldName : template.docToObjMapping.keySet()) { // Error in https://salesforce.quip.com/r2zhApUMCWkv
			// docToObjMapping prefaces the field name with the object name (i.e. Account.Name)
			String targetSObjectFieldName = template.docToObjMapping.get(docFieldName).removeStart(template.targetObjectType.getDescribe().getName() + '.');

			for (einsteinplay.Einstein_Probability prob : ocrResults.probabilities) {
				if (prob.attributes.key.entity.equals(docFieldName)) {
					newObj.put (targetSObjectFieldName, prob.attributes.value?.text );
				}
			}
		}

		List<SObject> retList = new List<SObject>();
		retList.add(newObj);
		return retList;
	}

	public class Request {
		@InvocableVariable(label='Template Name' required=true)
		public String templateName;

		@InvocableVariable(label='Uploaded Image contentDocumentId' required=true)
		public String contentDocumentId;

		@InvocableVariable(label='OCR formType' required=true)
		public String formType;

		@InvocableVariable(label='Record to populate' required=true)
		public sObject newObj;
	}

}