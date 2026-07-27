/**
* @description Controller for creating an application
* @author Sourav Sharma
* @date 2026-06-17
*/
public with sharing class CreateApplicationController {

    /**
    * Description: Gets the form options for the product and sub product
    * @return Map<String, Object> Form options
    */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFormOptions() {
        Map<String, Object> result = new Map<String, Object>();
        try {
            result.put('productOptions', getPicklistOptions('Application__c', 'Product__c'));
            result.put(
                'subProductDependencyMap',
                GenericUtility.fetchControlledByDependentToSchema('Application_Line_Item__c', 'Sub_Product__c')
            );
        }
        catch (Exception e) {
            throw new AuraHandledException('Error loading form options: ' + e.getMessage());
        }
        return result;
    }

    /**
    * Description: Creates a new application record with the following fields:
    * @param product Product
    * @param subProduct Sub Product
    * @param vehicleType Vehicle Type
    * @param segment Segment
    * @return String Application Id
    */
    @AuraEnabled
    public static String createApplication(
        String product,
        String subProduct,
        String vehicleType,
        String segment
    )
    {
        try {
            String applicationId = '';

            Map<String, Object> applicationFields = new Map<String, Object>{
                'Name'         => 'TempName',
                'CloseDate'    => System.today().addMonths(1),
                'Sub_Stage__c' => 'Basic Details',
                'Stage__c'     => 'QDE',
                'Product__c'   => product
            };

            // Application creation starts here
            Application__c application = new Application__c();
            setFieldsOnRecord((SObject) application, applicationFields);

            if (!Schema.sObjectType.Application__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create Applications.');
            }
            insert application;
            // Application creation ends here
            // Applicant creation starts here
            Map<String, Object> applicantFields = new Map<String, Object>{
                'Application__c'    => application.Id,
                'Loan_Stages__c'    => application.Sub_Stage__c,
                'Applicant_Type__c' => 'Borrower'
            };
            Applicant__c borrower = new Applicant__c();
            if(product == 'PL') {
                applicantFields.put('Is_Primary__c', true);
            }
            setFieldsOnRecord((SObject) borrower, applicantFields);
            insert borrower;
            // Applicant creation ends here
            // Application Line Item creation starts here
            Map<String, Object> aliFields = new Map<String, Object>{
                'Name'           => product + ' - Line Item',
                'Application__c' => application.Id,
                'Product__c'     => product
            };
            if (String.isNotBlank(subProduct)) {
                aliFields.put('Sub_Product__c', subProduct);
            }
            Application_Line_Item__c lineItem = new Application_Line_Item__c();
            setFieldsOnRecord((SObject) lineItem, aliFields);
            insert lineItem;
            // Application Line Item creation ends here
            if(product != 'PL') {
                // Asset creation starts here
                Map<String, Object> assetFields = new Map<String, Object>{
                    'Applicant__c' => borrower.Id,
                    'Application_Line_Items__c' => lineItem.Id,
                    'Name'         => product + ' - ' + borrower.Id
                };
                if (String.isNotBlank(vehicleType)) {
                    assetFields.put('Vehicle_type__c', vehicleType);
                }
                if (String.isNotBlank(segment)) {
                    assetFields.put('Product_Segment__c', segment);
                }
                Asset__c dummyAsset = new Asset__c();
                setFieldsOnRecord((SObject) dummyAsset, assetFields);
                insert dummyAsset;
                // Asset creation ends here
            }
            return application.Id;
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
    * Description: Gets the picklist options for the given object and field
    * @param objectApiName Object API Name
    * @param fieldApiName Field API Name
    * @return List<Map<String, String>> Picklist options
    */
    private static List<Map<String, String>> getPicklistOptions(String objectApiName, String fieldApiName) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.SObjectField field = Schema.getGlobalDescribe()
            .get(objectApiName)?.getDescribe().fields.getMap().get(fieldApiName.toLowerCase());
        if (field == null) return options;
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                });
            }
        }
        return options;
    }

    /**
    * Description: Sets the fields on the record
    * @param record Record
    * @param fieldNameToValue Field Name to Value
    */
    private static void setFieldsOnRecord(SObject record, Map<String, Object> fieldNameToValue) {
        if (record == null || fieldNameToValue == null || fieldNameToValue.isEmpty()) return;
        Schema.DescribeSObjectResult describeResult = record.getSObjectType().getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        for (String fieldApiName : fieldNameToValue.keySet()) {
            if (String.isBlank(fieldApiName)) continue;
            Schema.SObjectField fieldToken = fieldMap.get(fieldApiName);
            String resolvedFieldName = fieldApiName;
            if (fieldToken == null) {
                fieldToken = fieldMap.get(fieldApiName + '__c');
                if (fieldToken != null) resolvedFieldName = fieldApiName + '__c';
            }
            if (fieldToken != null && fieldToken.getDescribe().isCreateable()) {
                record.put(resolvedFieldName, fieldNameToValue.get(fieldApiName));
            }
        }
    }
}