public with sharing class CommonApplicationCreationController {

    /**
     * Returns the option payload the Aura form needs to render the product tiles
     * and the dependent sub-product radio group.
     *
     * Sub-product visibility is driven by a standard Salesforce field dependency
     * declared at the metadata level:
     *   Controlling field : Application_Line_Item__c.Product__c
     *   Dependent field   : Application_Line_Item__c.Sub_Product__c
     * The dependency mappings (CV→LCV/SCV/MHCV/CE, PL→Balance Transfer/Top Up)
     * are sourced from the picklist describe via
     * GenericUtility.fetchControlledByDependentToSchema so the JS layer never
     * has to hardcode them again.
     *
     * Response shape:
     *   {
     *     productOptions          : [{label, value}],          // Application__c.Product__c values
     *     subProductDependencyMap : { '<Product>': [{label, value}, ...] }   // dependent picklist map
     *   }
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFormOptions() {
        Map<String, Object> result = new Map<String, Object>();
        try {
            result.put('productOptions', getPicklistOptions('Application__c', 'Product__c'));
            result.put('subProductDependencyMap',
                GenericUtility.fetchControlledByDependentToSchema(
                    'Application_Line_Item__c', 'Sub_Product__c'));
        } catch (Exception e) {
            throw new AuraHandledException('Error loading form options: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Creates the full record chain for a new direct loan application:
     *   Application__c (parent)
     *     └── Applicant__c        — Borrower (Customer Type captured on Basic Details screen)
     *     └── Asset__c            — Vehicle Type, Segment, Number of Vehicles
     *     └── Application_Line_Item__c — Sub-Product + Number of Vehicles
     *     └── Document_Checklist__c   — initial PAN doc
     *
     * Field mapping:
     *   Number of Vehicles-> Application_Line_Item__c.Number_of_Vehicles__c
     *                        (single source of truth — owned at LALI level)
     *   Vehicle Type      -> Asset__c.Vehicle_type__c
     *   Segment           -> Asset__c.Product_Segment__c
     *   Sub-Product       -> Application_Line_Item__c.Sub_Product__c
     */
    @AuraEnabled
    public static DirectLoanCreationResponse createDirectLoanApplication(
        String product,
        String subProduct,
        String numberOfVehicles,
        String vehicleType,
        String segment
    ) {
        try {
            DirectLoanCreationResponse response = new DirectLoanCreationResponse();

            // ── 1. Application__c ────────────────────────────────────────
            Map<String, Object> applicationFields = new Map<String, Object>{
                'Name'         => 'TempName',
                'CloseDate'    => System.today().addMonths(1),
                'Sub_Stage__c' => 'Basic Details',
                'Stage__c'     => 'QDE',
                'Product__c'   => product
            };

            Application__c application = new Application__c();
            setFieldsOnRecord((SObject) application, applicationFields);

            if (!Schema.sObjectType.Application__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create Applications.');
            }
            insert application;

            // ── 2. Applicant__c (Borrower) ───────────────────────────────
            // Customer Type (Type__c) is captured on the Basic Details screen,
            // so it is intentionally not set here.
            Map<String, Object> applicantFields = new Map<String, Object>{
                'Application__c'     => application.Id,
                'Loan_Stages__c'     => application.Sub_Stage__c,
                'Applicant_Type__c'  => 'Borrower'
            };
            Applicant__c borrower = new Applicant__c();
            setFieldsOnRecord((SObject) borrower, applicantFields);
            insert borrower;

            // ── 3. Asset__c (Vehicle) ────────────────────────────────────
            Map<String, Object> assetFields = new Map<String, Object>{
                'Applicant__c'        => borrower.Id,
                'Name'                => product + ' - ' + borrower.Id
            };
            if (String.isNotBlank(vehicleType)) {
                assetFields.put('Vehicle_type__c', vehicleType);
            }
            if (String.isNotBlank(segment)) {
                assetFields.put('Product_Segment__c', segment);
            }
            
            if(product == 'CV') {
                assetFields.put('Purpose_of_purchase__c', 'Commercial');
            }

            Asset__c dummyAsset = new Asset__c();
            setFieldsOnRecord((SObject) dummyAsset, assetFields);
            insert dummyAsset;

            // ── 4. Application_Line_Item__c ──────────────────────────────
            // Product__c is mirrored from the parent Application__c.Product__c
            // because the LALI Sub_Product__c field has a same-object dependency
            // on Product__c (Salesforce field dependencies must live on a single
            // object). The Application__c remains the system of record for the
            // primary product; the LALI copy exists only to satisfy the
            // controlling-field contract on the dependent picklist row.
            Map<String, Object> aliFields = new Map<String, Object>{
                'Name'           => product + ' - Line Item',
                'Application__c' => application.Id,
                'Product__c'     => product
            };
            if (String.isNotBlank(subProduct)) {
                aliFields.put('Sub_Product__c', subProduct);
            }
            if (String.isNotBlank(numberOfVehicles)) {
                aliFields.put('Number_of_Vehicles__c', numberOfVehicles);
            }
            Application_Line_Item__c lineItem = new Application_Line_Item__c();
            setFieldsOnRecord((SObject) lineItem, aliFields);
            insert lineItem;
            
            dummyAsset.Application_Line_Items__c = lineItem.Id;
            update dummyAsset;

            response.recordId = application.Id;
            return response;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

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

    public class DirectLoanCreationResponse {
        @AuraEnabled public String recordId;
    }
}