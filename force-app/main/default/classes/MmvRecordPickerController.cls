public with sharing class MmvRecordPickerController {

    public class OptionsWrapper{
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String segmentCode;
        @AuraEnabled
        public String assetCategoryCode;
    }

    @AuraEnabled
    public static List<OptionsWrapper> getMakeList(String productType) {
        List<OptionsWrapper> makeList = new List<OptionsWrapper>();	
        List<AggregateResult> Make = [SELECT Parent_Product__r.Name name, Parent_Product__r.Make_Code__c makecode
            FROM MMV_Product_Master__c
            WHERE Product_Type__c =: productType
            AND Type__c = 'Model'
            AND Is_Active__c = true
            AND Parent_Product__c != NULL
            GROUP BY Parent_Product__r.name, Parent_Product__r.Make_Code__c
            ORDER by Parent_Product__r.name];
        for(AggregateResult ag : Make) {
            OptionsWrapper options = new OptionsWrapper();
            options.label = String.valueOf(ag.get('name'));
            options.value = String.valueOf(ag.get('makecode'));
            options.segmentCode = '';
            options.assetCategoryCode = '';
            makeList.add(options);
        }
        return makeList;
    }

    @AuraEnabled
    public static List<OptionsWrapper> getModelList(String productType, String makeCode) {
        List<OptionsWrapper> modelList = new List<OptionsWrapper>();
        List<MMV_Product_Master__c> models = [SELECT Name, Model_Code__c, Segment__c, Asset_Category__c
            FROM MMV_Product_Master__c
            WHERE Product_Type__c =: productType
            AND Parent_Product__r.Make_Code__c =: makeCode
            AND Type__c = 'Model'
            AND Is_Active__c = true
            AND Parent_Product__c != NULL
            ORDER by Name];
        for(MMV_Product_Master__c model : models) {
            OptionsWrapper options = new OptionsWrapper();
            options.label = model.Name;
            options.value = model.Model_Code__c;
            options.segmentCode = model.Segment__c;
            options.assetCategoryCode = model.Asset_Category__c;
            modelList.add(options);
        }
        return modelList;
    }

    @AuraEnabled
    public static List<OptionsWrapper> getVariantList(String productType, String makeCode, String modelCode){
        List<OptionsWrapper> variantList = new List<OptionsWrapper>();
        List<MMV_Product_Master__c> variants = new List<MMV_Product_Master__c>();
        variants = [SELECT Id, Name, Type__c,Variant_Code__c,Model_Code__c
                FROM MMV_Product_Master__c
                WHERE Product_Type__c =: productType
                AND Parent_Product__r.Make_Code__c =: makeCode
                AND Parent_Product__r.Model_Code__c =: modelCode
                AND Type__c = 'Variant'
                AND Is_Active__c = true
                ORDER BY Name ASC];
        for(MMV_Product_Master__c variant : variants) {
            OptionsWrapper options = new OptionsWrapper();
            options.label = variant.Name;
            options.value = variant.Variant_Code__c;
            variantList.add(options);
        }
        return variantList;
    }
}