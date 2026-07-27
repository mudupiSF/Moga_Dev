/**
 * @description Shared query and formatting helpers for CustomerForm wrapper classes.
 */
public without sharing class CustomerFormDataHelper {

    public static Application__c queryApplication(Id applicationId) {
        List<Application__c> applications = [
            SELECT Id,
                   Application_number__c,
                   Total_Loan_Amount__c,
                   Product__c,
                   Sub_Product__c,
                   Sanction_Status__c,
                   Branch__r.Name,
                   Branch__r.BillingState,
                   (SELECT Id,
                           Applicant_Type__c,
                           Customer_First_Name__c,
                           Customer_Last_Name__c,
                           Date_of_Birth__c,
                           PAN_Number__c,
                           Phone__c,
                           Email__c,
                           Declared_income__c,
                           Relationship_with_borrower__c
                    FROM Applicants__r
                    WHERE In_Active_Applicant__c = false
                    ORDER BY Applicant_Type__c ASC, CreatedDate ASC),
                   (SELECT Id,
                           Loan_Amount__c,
                           Tenure__c,
                           EMI_Amount__c,
                           ROI__c,
                           CRM_IRR__c,
                           (SELECT Id, Make__c, Model__c, Variant__c
                            FROM Assets__r
                            ORDER BY CreatedDate ASC
                            LIMIT 1)
                    FROM Application_Line_Items__r
                    ORDER BY CreatedDate ASC)
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0];
    }

    public static Applicant__c resolveBorrower(List<Applicant__c> applicants) {
        if (applicants == null) {
            return null;
        }
        for (Applicant__c applicant : applicants) {
            if ('Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c)) {
                return applicant;
            }
        }
        return applicants.isEmpty() ? null : applicants[0];
    }

    public static Applicant__c resolveCoBorrower(List<Applicant__c> applicants) {
        if (applicants == null) {
            return null;
        }
        for (Applicant__c applicant : applicants) {
            if ('Co-Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c)) {
                return applicant;
            }
        }
        return null;
    }

    public static Id resolveApplicationId(Id applicantId) {
        List<Applicant__c> applicants = [
            SELECT Id, Application__c
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        if (applicants.isEmpty() || applicants[0].Application__c == null) {
            throw new AuraHandledException('Applicant record not found.');
        }
        return applicants[0].Application__c;
    }

    public static Id resolveBorrowerApplicantId(Id applicationId) {
        List<Applicant__c> borrowers = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :applicationId
              AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        if (borrowers.isEmpty()) {
            throw new AuraHandledException('Borrower applicant not found.');
        }
        return borrowers[0].Id;
    }

    public static Id resolveDocumentChecklistId(
        Id applicationId,
        Id applicantId,
        String documentType,
        String documentName
    ) {
        List<Document_CheckList__c> existingDocs = [
            SELECT Id,Applicant__r.Application_Consent_Received__c
            FROM Document_CheckList__c
            WHERE Application__c = :applicationId
              AND Applicant__c = :applicantId
              AND Document_Type__c = :documentType
            LIMIT 1
        ];
        if (!existingDocs.isEmpty()) {
            if (documentType == 'Application Form' && existingDocs[0].Applicant__r.Application_Consent_Received__c == true) {
                return existingDocs[0].Id;
            }
            delete [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :existingDocs[0].Id
            ];
            return existingDocs[0].Id;
        }

        Document_CheckList__c doc = new Document_CheckList__c(
            Application__c   = applicationId,
            Applicant__c     = applicantId,
            Document_Type__c = documentType,
            Is_Active__c     = true,
            Name             = documentName
        );
        insert doc;
        return doc.Id;
    }

    public static ICustomerFormWrapper getWrapperDetails(String formName) {
        List<PDFforceConfig__c> configs = [SELECT Id, DeveloperName__c, Wrapper_Class__c FROM PDFforceConfig__c WHERE DeveloperName__c = :formName LIMIT 1];
        if (configs.isEmpty()) {
            throw new AuraHandledException('Unsupported form name: ' + formName);
        }
        String className = configs[0].Wrapper_Class__c;
        return (ICustomerFormWrapper) Type.forName(className).newInstance();
    }

    public static String joinName(String firstName, String lastName) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(firstName)) {
            parts.add(firstName.trim());
        }
        if (String.isNotBlank(lastName)) {
            parts.add(lastName.trim());
        }
        return String.join(parts, ' ');
    }

    public static String joinVehicleLabel(String make, String model, String variant) {
        return String.join(new List<String>{
            String.isNotBlank(make) ? make : '',
            String.isNotBlank(model) ? model : '',
            String.isNotBlank(variant) ? variant : ''
        }, ' ').trim();
    }

    public static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        DateTime dt = DateTime.newInstance(value.year(), value.month(), value.day());
        return dt.format('dd-MMM-yyyy');
    }

    public static String formatDecimal(Decimal value) {
        return value == null ? '' : String.valueOf(value);
    }

    public static String formatTenure(Decimal tenureMonths) {
        return tenureMonths == null ? '' : String.valueOf(tenureMonths.intValue()) + ' Months';
    }

    public static String formatPercent(Decimal value) {
        return value == null ? '' : String.valueOf(value.setScale(2)) + '%';
    }

    public static String blankToEmpty(String value) {
        return String.isBlank(value) ? '' : value;
    }
}