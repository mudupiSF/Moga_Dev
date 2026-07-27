/**
 * ─────────────────────────────────────────────────────────────────────────────
 * the leadInformation LWC on MOGA DEV's Application Record Page. 
 * Sources the data from MOGA DEV's Application__c chain (Application__c, Asset__c).
 * ─────────────────────────────────────────────────────────────────────────────
 */
public with sharing class LeadInformationController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLeadInformation(Id recordId) {
        Map<String, Object> response = new Map<String, Object>{
            'leadNumber'  => null,
            'leadSource'  => null,
            'productType' => null,
            'vehicleType' => null
        };

        if (recordId == null) {
            return response;
        }

        try {
            // ── Application__c — 3 of the 4 fields live here ─────────────
            List<Application__c> applications = [
                SELECT Id, Application_number__c//, Lead_Source__c, Product__c
                FROM Application__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (applications.isEmpty()) {
                return response;
            }
            Application__c application = applications[0];
            response.put('leadNumber',  application.Application_number__c);
            //response.put('leadSource',  application.Lead_Source__c);
            response.put('productType', application.Product__c);

            List<Asset__c> assets = [
                SELECT Id, Vehicle_type__c
                FROM Asset__c
                WHERE Applicant__r.Application__c = :recordId
                  AND Applicant__r.Applicant_Type__c = 'Borrower'
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!assets.isEmpty()) {
                response.put('vehicleType', assets[0].Vehicle_type__c);
            }

        } catch (Exception e) {
            throw new AuraHandledException('Unable to load Lead Information: ' + e.getMessage());
        }

        return response;
    }
}