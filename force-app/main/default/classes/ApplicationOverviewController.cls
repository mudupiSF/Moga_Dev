/**
 * @description Apex controller for applicationOverview and withdrawApplicationModal (overview flow).
 */
public with sharing class ApplicationOverviewController {

    /**
     * @description Returns application overview fields, withdrawal reason, and picklist options.
     * @param recordId Application__c Id
     * @return ApplicationOverviewWrapper populated from Application__c and related Asset__c
     */
    @AuraEnabled(cacheable=true)
    public static ApplicationOverviewWrapper getApplicationOverview(String recordId) {
        ApplicationOverviewWrapper response = new ApplicationOverviewWrapper();

        if (String.isBlank(recordId)) {
            return response;
        }

        try {
            List<Application__c> applications = [
                SELECT Id, Application_number__c, Application_Source__c, Product__c, Withdrawal_Reason__c
                FROM Application__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (applications.isEmpty()) {
                return response;
            }

            Application__c applicationRecord = applications[0];
            response.applicationNumber = applicationRecord.Application_number__c;
            response.applicationSource = applicationRecord.Application_Source__c;
            response.productType = applicationRecord.Product__c;
            response.withdrawalReason = applicationRecord.Withdrawal_Reason__c;
            response.withdrawalReasonOptions = getWithdrawalReasonOptions();
            response.vehicleType = getFirstVehicleType(recordId);
            return response;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading application overview: ' + e.getMessage());
        }
    }

    /**
     * @description Updates Withdrawal_Reason__c on the application record.
     * @param recordId Application__c Id
     * @param withdrawalReason Selected picklist value for Withdrawal_Reason__c
     */
    @AuraEnabled
    public static void withdrawApplication(String recordId, String withdrawalReason) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Application Id is required.');
        }
        if (String.isBlank(withdrawalReason)) {
            throw new AuraHandledException('Withdrawal Reason is required.');
        }

        try {
            update new Application__c(
                Id = recordId,
                Withdrawal_Reason__c = withdrawalReason
            );
        } catch (Exception e) {
            throw new AuraHandledException('Error updating withdrawal reason: ' + e.getMessage());
        }
    }

    private static List<PicklistOption> getWithdrawalReasonOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : Application__c.Withdrawal_Reason__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static String getFirstVehicleType(String recordId) {
        List<Asset__c> assets = [
            SELECT Vehicle_type__c
            FROM Asset__c
            WHERE Applicant__r.Application__c = :recordId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0].Vehicle_type__c;
    }

    public class ApplicationOverviewWrapper {
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String applicationSource;
        @AuraEnabled public String productType;
        @AuraEnabled public String vehicleType;
        @AuraEnabled public String withdrawalReason;
        @AuraEnabled public List<PicklistOption> withdrawalReasonOptions;

        public ApplicationOverviewWrapper() {
            this.withdrawalReasonOptions = new List<PicklistOption>();
        }
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption() {
        }

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}