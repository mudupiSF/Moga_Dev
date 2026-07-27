trigger ApplicantTrigger on Applicant__c (before update, after update) {
    TriggerDispatcher.Run(new ApplicantTriggerHandler());
}