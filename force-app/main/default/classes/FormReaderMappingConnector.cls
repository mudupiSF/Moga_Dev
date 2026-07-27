public class FormReaderMappingConnector {
    
    private OCRTemplate getTemplateFromMasterLabel(String masterLabel){
        return [select id, DocumentTypeId, MasterLabel from OCRTemplate where MasterLabel = :masterLabel limit 1][0];
    }

    private OCRTargetObject getTargetObjectFromTemplate(OCRTemplate template) {
        return [select id, TargetObject from OCRTargetObject where OcrTemplateId = :template.id limit 1][0]; // Error
    }

    private List<OcrTargetObjFieldMapping> getFieldMappingsFromTargetObject(OCRTargetObject targetObject) {
        return [select id, OcrSampleDocFieldId, TargetField from OcrTargetObjFieldMapping where OcrTargetObjectId = :targetObject.id];
    }

    private Schema.sObjectType getObjectTypeFromName(String objName) {
        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
        return globalMap.get(objName);
    }

    public TemplateDescribe createTemplateDescribe(String templateFromMasterLabel) {
        OCRTemplate template = getTemplateFromMasterLabel(templateFromMasterLabel);
        OCRTargetObject targObj = getTargetObjectFromTemplate(template);
        List<OcrTargetObjFieldMapping> maps = getFieldMappingsFromTargetObject(targObj);
        Map<String, String> docToObjMapping = new Map<String, String>();

        for (OcrTargetObjFieldMapping mapping : maps) {
            OCRSampleDocumentField sourceField = [select id, FieldValueName, OcrSampleDocumentId from OCRSampleDocumentField where id = :mapping.OcrSampleDocFieldId limit 1][0];
            docToObjMapping.put(sourceField.FieldValueName, mapping.TargetField); 
        }

        Schema.sObjectType targetObjectType = getObjectTypeFromName(targObj.TargetObject);

        TemplateDescribe templateDescribe = new TemplateDescribe(template.masterLabel, targetObjectType, docToObjMapping);
        return templateDescribe;
    }

    public class TemplateDescribe {
        public String templateName;
        public Map<String, String> docToObjMapping;//key = field on document, value = field on Sobject
        public Schema.sObjectType targetObjectType;

        public TemplateDescribe(String templateName, Schema.sObjectType targetObjectType, Map<String, String> docToObjMapping) {
            this.templateName = templateName;
            this.targetObjectType = targetObjectType;
            this.docToObjMapping = docToObjMapping;
        }
    }

    public class KeyValuePair{
        private Schema.DescribeSObjectResult sObjectDescribe;
        private Schema.DescribeSObjectResult targetSObjectFieldDescribe;
        private String targetSObjectFieldName;
        private String targetFieldValue;//value found in document
        private String sourceFieldKey;//name of the field on the document

        public KeyValuePair(Schema.DescribeSObjectResult sObjectDescribe, 
            Schema.DescribeSObjectResult targetSObjectFieldDescribe, 
            String targetFieldValue,
            String sourceFieldKey) {
            this.sObjectDescribe = sObjectDescribe;
            this.targetSObjectFieldDescribe = targetSObjectFieldDescribe;
            this.targetFieldValue = targetFieldValue;
            this.sourceFieldKey = sourceFieldKey;
        }

        public String getTargetFieldValue(){
            return targetFieldValue;
        }

        public String getObjectName() {
            return sObjectDescribe.getName();
        }

        public String getFieldName() {
            return targetSObjectFieldDescribe.getName();
        }
    }

}