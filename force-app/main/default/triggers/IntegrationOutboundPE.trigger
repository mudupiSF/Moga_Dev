trigger IntegrationOutboundPE on Integration_Outbound__e (after insert) {

    IntegrationOutboundPEHandler.executeAfterInsert(Trigger.new);

    /*
    List<Integration_Checklist__c> icList = new List<Integration_Checklist__c>();
    for(Integration_Outbound__e peRecord : (List<Integration_Outbound__e>)trigger.new) {
        if(peRecord.Integration_ID__c != NULL) {
            icList.add(
                new Integration_Checklist__c(
                    Id = peRecord.Integration_ID__c,
                    Replay_Id__c = peRecord.ReplayId,
                    Request__c = JSON.serialize(peRecord).length() < 131000 ? JSON.serialize(peRecord) : JSON.serialize(peRecord).substring(1,131000)
                )
            );
        }
    }
    if(!icList.isEmpty()) {
        update icList;
    }
    */
}