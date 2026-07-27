/**
 * @description Builds PDF merge-field JSON for Insurance_Form templates.
 */
public without sharing class InsuranceFormWrapper implements ICustomerFormWrapper {

    private static final String DOCUMENT_TYPE = 'Insurance Consent';
    private static final String DOCUMENT_NAME = 'Insurance Form';

    public String getDocumentType() {
        return DOCUMENT_TYPE;
    }

    public String getDocumentName() {
        return DOCUMENT_NAME;
    }

    public Map<String, Object> buildInputJson(Id applicationId, Id applicantId) {
        if (applicantId == null) {
            throw new AuraHandledException('Applicant ID is required.');
        }

        List<Applicant__c> applicants = [
            SELECT Id,Name,Customer_First_Name__c,Customer_Last_Name__c,
                   Application__r.Application_number__c,
                   Application__r.CreatedDate
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        if (applicants.isEmpty()) {
            throw new AuraHandledException('Applicant record not found.');
        }

        List<Insurance__c> insurances = [
            SELECT Name, Insurance_Plan__c, Product_Type__c, Amount__c, Funded_Premium__c
            FROM Insurance__c
            WHERE Applicant__c = :applicantId
              AND Is_Active__c = true
            ORDER BY CreatedDate ASC
        ];

        List<Object> insuranceList = new List<Object>();
        for (Insurance__c insurance : insurances) {
            insuranceList.add(new Map<String, Object>{
                'plan' => blankToEmpty(insurance.Insurance_Plan__c),
                'insurer' => blankToEmpty(insurance.Name),
                'product' => blankToEmpty(insurance.Product_Type__c),
                'premium' => formatPremium(insurance)
            });
        }

        Applicant__c applicant = applicants[0];
        String appNumber = applicant.Application__r != null
            ? blankToEmpty(applicant.Application__r.Application_number__c)
            : '';
        Datetime applicationCreatedDate = applicant.Application__r != null
            ? applicant.Application__r.CreatedDate
            : null;

        return new Map<String, Object>{
            'appNumber' => appNumber,
            'applicantName' => formatApplicantName(applicant),
            'applicationDate' => formatDisplayDateTime(applicationCreatedDate),
            'insuranceList' => insuranceList
        };
    }

    private static String formatApplicantName(Applicant__c applicant) {
        if (applicant == null) {
            return '';
        }
        String joined = CustomerFormDataHelper.joinName(
            applicant.Customer_First_Name__c,
            applicant.Customer_Last_Name__c
        );
        return String.isNotBlank(joined) ? joined : safeStr(applicant.Name);
    }

    private static String safeStr(String value) {
        return String.isBlank(value) ? '' : value.trim();
    }

    private static String formatDisplayDateTime(Datetime value) {
        if (value == null) {
            return '';
        }
        return value.format('dd-MMM-yyyy');
    }

    private static String formatPremium(Insurance__c insurance) {
        Decimal value = insurance.Funded_Premium__c != null
            ? insurance.Funded_Premium__c
            : insurance.Amount__c;
        return value == null ? '' : String.valueOf(value.setScale(0));
    }

    private static String blankToEmpty(String value) {
        return String.isBlank(value) ? '' : value;
    }
}