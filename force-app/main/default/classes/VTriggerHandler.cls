/*
 * Base class for all the trigger handlers.
 * Every trigger handler class must extend this class and 
 * implement the required methods only. 
*/
public virtual class VTriggerHandler {

    public virtual void beforeInsert(List<SObject> newItems){

    }
 
    public virtual void beforeUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems){

    }
 
    public virtual void beforeDelete(Map<Id, SObject> oldItems){

    }
 
    public virtual void afterInsert(Map<Id, SObject> newItems){

    }
 
    public virtual void afterUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems){

    }
 
    public virtual void afterDelete(Map<Id, SObject> oldItems){

    }
 
    public virtual void afterUndelete(Map<Id, SObject> oldItems){

    }

    public virtual Boolean isDisabled(){
        return false;
    }

    public Boolean isDisabled(String objectName){
        TriggerDeactivationSettings__c instCS = TriggerDeactivationSettings__c.getInstance(UserInfo.getUserId());
        System.debug('objectName'+objectName);
        return instCS.get('Deactivate_'+objectName+'_Trigger__c')==null?false:(Boolean)instCS.get('Deactivate_'+objectName+'_Trigger__c');
    }
}