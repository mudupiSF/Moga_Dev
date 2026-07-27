public without sharing class IntegrationChecklistTriggerService {

    
    // Make other Integration Checklists Obsolte and Non Latest
    public static void makeOtherChecklistsObsolete(Map<Id, Integration_Checklist__c> intChkForObsltMap) {
        
        List<Integration_Checklist__c> otherChecklists = new List<Integration_Checklist__c>();
        Set<Id> parentIds = new Set<Id>();
        Set<Id> masterIds = new Set<Id>();
        Set<String> mappingIds = new Set<String>();
        
        for(Integration_Checklist__c intCheck : intChkForObsltMap.values()) {

            masterIds.add(intCheck.Integration_Master_ID__c);
            if(intCheck.Applicant__c != NULL) {
                parentIds.add(intCheck.Applicant__c);
                mappingIds.add(intCheck.Applicant__c + '_' + intCheck.Integration_Master_ID__c);
            }
            // TODO : Add Other Lookup Field Names HERE
        }
        for(Integration_Checklist__c ch : [SELECT Id, Status__c, Is_Latest__c, Applicant__c, Integration_Master_ID__c
                                           FROM Integration_Checklist__c
                                           WHERE Integration_Master_ID__c IN: masterIds
                                           AND (Applicant__c IN: parentIds )
                                           AND (
                                               Is_Latest__c != TRUE
                                               OR
                                               Status__c != 'Obsolete'
                                           )
                                           AND Id NOT IN: intChkForObsltMap.keySet()])
        {
            String uniqueKey;
            if(ch.Applicant__c != NULL) {
                uniqueKey = ch.Applicant__c + '_' + ch.Integration_Master_ID__c;
            }
            // TODO : Add Other Lookup Field Names HERE
            // If the unique key is not in the mappingIds, then add it to the otherChecklists
            if(mappingIds.contains(uniqueKey)) {
                ch.Status__c = 'Obsolete';
                ch.Is_Latest__c = false;
                otherChecklists.add(ch);
            }
        }
        if(!otherChecklists.isEmpty()) {
            update otherChecklists;
        }
    }   
}