/**
 * @description Apex service for CustomerForm — builds site URLs and form render
 *              payloads for customerFormHost LWC.
 */
public without sharing class CustomerFormController {

    private static final String SITE_NAME    = 'CustomerService';
    private static final String VF_PAGE_PATH = '/CustomerForm';

    public class FormRenderData {
        @AuraEnabled public String templateId;
        @AuraEnabled public String documentChecklistId;
        @AuraEnabled public String fileName;
        @AuraEnabled public Map<String, Object> inputJSON;
        @AuraEnabled public Boolean applicationConsentReceived;
    }

    @AuraEnabled
    public static FormRenderData getFormRenderData(String applicantId, String formName) {
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID (applicantId) is required.');
        }

        String templateId = resolveTemplateId(formName);
        if (String.isBlank(templateId)) {
            throw new AuraHandledException('PDF template not found for form name: ' + formName);
        }

        try {
            Id applicationId = CustomerFormDataHelper.resolveApplicationId(applicantId);
            ICustomerFormWrapper formWrapper = CustomerFormDataHelper.getWrapperDetails(formName);

            FormRenderData data = new FormRenderData();
            data.templateId = templateId;
            data.fileName = formWrapper.getDocumentName();
            data.inputJSON = formWrapper.buildInputJson(applicationId, applicantId);
            data.documentChecklistId = CustomerFormDataHelper.resolveDocumentChecklistId(
                applicationId,
                applicantId,
                formWrapper.getDocumentType(),
                formWrapper.getDocumentName()
            );
            data.applicationConsentReceived = isApplicationConsentAlreadyReceived(
                applicantId,
                formName
            );
            return data;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void markApplicationConsentReceived(String applicantId) {
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID is required.');
        }
        List<Applicant__c> applicants = [
            SELECT Id, Application_Consent_Received__c
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        if (applicants.isEmpty()) {
            throw new AuraHandledException('Applicant record was not found.');
        }
        Applicant__c applicant = applicants[0];
        if (applicant.Application_Consent_Received__c != true) {
            applicant.Application_Consent_Received__c = true;
            update applicant;
        }
    }

    @AuraEnabled
    public static void markInsuranceConsentReceived(String applicantId) {
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID is required.');
        }
        List<Applicant__c> applicants = [
            SELECT Id
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        // if (applicants.isEmpty()) {
        //     throw new AuraHandledException('Applicant record was not found.');
        // }
        // Applicant__c applicant = applicants[0];
        // if (applicant.Insurance_Consent_Received__c != true) {
        //     applicant.Insurance_Consent_Received__c = true;
        //     update applicant;
        // }
    }

    private static Boolean isApplicationConsentAlreadyReceived(
        String applicantId,
        String normalizedFormName
    ) {
        if (normalizedFormName != 'Application_Form') {
            return false;
        }
        List<Applicant__c> applicants = [
            SELECT Application_Consent_Received__c
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        return !applicants.isEmpty() && applicants[0].Application_Consent_Received__c == true;
    }

    @AuraEnabled
    public static String getCustomerFormUrl(String applicantId, String formName) {
        if (String.isBlank(applicantId)) {
            throw new AuraHandledException('Applicant ID is required.');
        }
        String baseUrl = resolveSiteBaseUrl();
        return baseUrl
            + VF_PAGE_PATH
            + '?applicantId=' + EncodingUtil.urlEncode(applicantId, 'UTF-8')
            + '&formname=' + EncodingUtil.urlEncode(formName, 'UTF-8');
    }

    private static String resolveTemplateId(String developerName) {
        List<PDFforceConfig__c> configs = [
            SELECT Id
            FROM PDFforceConfig__c
            WHERE DeveloperName__c = :developerName
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0].Id;
    }

    private static String resolveSiteBaseUrl() {
        List<Site> sites = [
            SELECT Id, Subdomain, UrlPathPrefix
            FROM Site
            WHERE Name = :SITE_NAME
              AND Status = 'Active'
            LIMIT 1
        ];
        if (sites.isEmpty()) {
            throw new AuraHandledException('Active CustomerService site was not found.');
        }

        Site siteRecord = sites[0];

        List<SiteDetail> siteDetails = [
            SELECT SecureUrl
            FROM SiteDetail
            WHERE DurableId = :siteRecord.Id
            LIMIT 1
        ];
        if (!siteDetails.isEmpty() && String.isNotBlank(siteDetails[0].SecureUrl)) {
            return siteDetails[0].SecureUrl.removeEnd('/');
        }

        String siteBase = Site.getBaseUrl();
        if (String.isNotBlank(siteBase) && siteBase.contains('salesforce-sites.com')) {
            return siteBase.removeEnd('/');
        }

        String pathPrefix = String.isNotBlank(siteRecord.UrlPathPrefix)
            ? '/' + siteRecord.UrlPathPrefix
            : '';
        if (String.isNotBlank(siteRecord.Subdomain)) {
            Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
            String host = org.IsSandbox
                ? 'https://' + siteRecord.Subdomain + '.sandbox.my.salesforce-sites.com'
                : 'https://' + siteRecord.Subdomain + '.my.salesforce-sites.com';
            return host + pathPrefix;
        }

        throw new AuraHandledException(
            'Unable to resolve CustomerService public site URL. Verify the site is active and has a subdomain configured.'
        );
    }
}