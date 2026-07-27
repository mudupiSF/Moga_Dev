public without sharing class IntegrationOutboundPEHandler {

    public static void executeAfterInsert(List<Integration_Outbound__e> newEvents) {
        if(newEvents == null || newEvents.isEmpty()) {
            return;
        }

        List<Integration_Checklist__c> icList = new List<Integration_Checklist__c>();
        for(Integration_Outbound__e peRecord : newEvents) {
            if(peRecord.Integration_ID__c != NULL) {
                String serializedPayload = JSON.serialize(peRecord);
                icList.add(
                    new Integration_Checklist__c(
                        Id = peRecord.Integration_ID__c,
                        Replay_Id__c = peRecord.ReplayId,
                        Request__c = serializedPayload.length() < 131000
                            ? serializedPayload
                            : serializedPayload.substring(1, 131000)
                    )
                );
            }
        }

        if(!icList.isEmpty()) {
            update icList;
        }
    }
}