/**
* @author        	  : Ritika Dhandia
* @description        : Trigger Handler for Integration Checklist.
                       1. On before update - we process the response using the Apex Class
                       2. On after insert - we make the old Integration Checklists obsolete
* @date               : 2025-07-23
*/
public with sharing class IntegrationChecklistTriggerHandler extends VTriggerHandler {

    /**
     * @description        : Before Insert Trigger.
     * @param newRecordList: List of Integration Checklists.
     */
    public override void beforeInsert(List<sObject> newRecordList) {
        
    }
    
    /**
     * @description        : Before Update Trigger.
     * @param newItems     : Map of Integration Checklists.
     * @param oldItems     : Map of Integration Checklists.
     */
    public override void beforeUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems) {
        
        List<IntegrationUtility.ResponseWrapper> responseList = new List<IntegrationUtility.ResponseWrapper>();

        // Only when the Status is updated to Success from Pending, then
        // we process the response using the Apex Class

        for(Integration_Checklist__c newIntChk : (List<Integration_Checklist__c>)newItems.values()) {
            
            Integration_Checklist__c oldIntChk = (Integration_Checklist__c)oldItems.get(newIntChk.Id);
            
            if((newIntChk.Status__c != oldIntChk.Status__c)
                && (newIntChk.Status__c == 'Success' || newIntChk.Status__c == 'Failure')
                && (oldIntChk.Status__c == 'In Progress')){
                
                IntegrationUtility.ResponseWrapper response = new IntegrationUtility.ResponseWrapper();
                response.checklistRecord = newIntChk;
                responseList.add(response);
            }
        }

        ApplicationUtility.processIntgerationAsync(responseList);
       

    }
    
    public override void afterInsert(Map<Id, SObject> newItems) {
        Map<Id, Integration_Checklist__c> intChkForObsltMap = new Map<Id, Integration_Checklist__c>();
        for(Integration_Checklist__c newIntChk : (List<Integration_Checklist__c>)newItems.values()) {
            //TODO : Add Actual Lookup Field Names HERE
            if(newIntChk.Applicant__c != NULL) {
                intChkForObsltMap.put(newIntChk.Id, newIntChk);
            }
        }
        if(!intChkForObsltMap.isEmpty()) {
            
            IntegrationChecklistTriggerService.makeOtherChecklistsObsolete(intChkForObsltMap);
        }
    }
    
    public override void afterUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems) {
        
        
        // IntegrationObsoleteService.handleObsoleteChecklists(
        //     (Map<Id, Integration_Checklist__c>)newItems,
        //     (Map<Id, Integration_Checklist__c>)oldItems
        // );
    }
}