/**
 * Loads Investigations__c records for the Investigation Details master page,
 * grouped by verification type (FI, FCU, AML).
 *
 * FI: one Investigations__c per applicant; each FI subtype is a separate row
 * from child Verification__c (identified by Verification__c.Name).
 */
public with sharing class InvestigationDetailsController implements Callable {

    private static final String ACTION_GET_INVESTIGATION_RECORDS = 'getInvestigationRecords';
    private static final String TYPE_FI = 'FI';
    private static final String VERIFICATION_NAME_SUFFIX = ' Verification';

    private static final Map<String, String> TYPE_TO_SECTION = new Map<String, String>{
        'FI' => 'fi',
        'FCU' => 'fcu',
        'AML' => 'aml'
    };

    public class InvestigationRow {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String applicantName { get; set; }
        @AuraEnabled public String applicantType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String verificationId { get; set; }
    }

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_GET_INVESTIGATION_RECORDS.equalsIgnoreCase(action)) {
            return getInvestigationRecordsInternal(args != null ? args : new Map<String, Object>());
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    private static Map<String, List<InvestigationRow>> getInvestigationRecordsInternal(Map<String, Object> args) {
        Map<String, List<InvestigationRow>> rowsBySection = buildEmptySectionMap();
        Id applicationId = getApplicationId(args);
        if (applicationId == null) {
            return rowsBySection;
        }

        try {
            List<Investigations__c> investigations = [
                SELECT Id,
                       Name,
                       Status__c,
                       Type_of_Investigation__c,
                       (SELECT Id,
                               Name,
                               Status__c,
                               Applicant__c,
                               Applicant__r.Company_Name__c,
                               Applicant__r.Customer_First_Name__c,
                               Applicant__r.Customer_Last_Name__c,
                               Applicant__r.Applicant_Type__c
                        FROM Verifications__r
                        ORDER BY CreatedDate DESC, Name ASC)
                FROM Investigations__c
                WHERE Application__c = :applicationId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
            ];
            Map<Id, Document_CheckList__c> poiByApplicantId = getPoiIdentityDocumentsByApplicant(
                collectApplicantIds(investigations)
            );

            for (Investigations__c investigation : investigations) {
                String sectionId = resolveSectionId(investigation.Type_of_Investigation__c);
                if (String.isBlank(sectionId) || !rowsBySection.containsKey(sectionId)) {
                    continue;
                }

                List<InvestigationRow> rows = TYPE_FI.equalsIgnoreCase(investigation.Type_of_Investigation__c)
                    ? toFiVerificationRows(investigation, poiByApplicantId)
                    : new List<InvestigationRow>{ toInvestigationRow(investigation, null, poiByApplicantId) };
                rowsBySection.get(sectionId).addAll(rows);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load investigation records: ' + e.getMessage());
        }

        return rowsBySection;
    }

    private static List<InvestigationRow> toFiVerificationRows(
            Investigations__c investigation,
            Map<Id, Document_CheckList__c> poiByApplicantId) {
        if (investigation.Verifications__r == null || investigation.Verifications__r.isEmpty()) {
            return new List<InvestigationRow>{ toInvestigationRow(investigation, null, poiByApplicantId) };
        }

        List<InvestigationRow> rows = new List<InvestigationRow>();
        for (Verification__c verification : investigation.Verifications__r) {
            rows.add(toInvestigationRow(investigation, verification, poiByApplicantId));
        }
        return rows;
    }

    private static Set<Id> collectApplicantIds(List<Investigations__c> investigations) {
        Set<Id> applicantIds = new Set<Id>();
        if (investigations == null) {
            return applicantIds;
        }

        for (Investigations__c investigation : investigations) {
            if (investigation.Verifications__r == null) {
                continue;
            }
            for (Verification__c verification : investigation.Verifications__r) {
                if (verification.Applicant__c != null) {
                    applicantIds.add(verification.Applicant__c);
                }
            }
        }
        return applicantIds;
    }

    private static String resolveStringArg(Map<String, Object> args, String key) {
        if (args == null || !args.containsKey(key) || args.get(key) == null) {
            return null;
        }
        return String.valueOf(args.get(key));
    }

    private static Id getApplicationId(Map<String, Object> args) {
        String recordId = resolveStringArg(args, 'recordId');
        if (String.isBlank(recordId)) {
            recordId = resolveStringArg(args, 'applicationId');
        }
        return String.isBlank(recordId) ? null : (Id) recordId;
    }

    private static Map<String, List<InvestigationRow>> buildEmptySectionMap() {
        return new Map<String, List<InvestigationRow>>{
            'fi' => new List<InvestigationRow>(),
            'fcu' => new List<InvestigationRow>(),
            'aml' => new List<InvestigationRow>()
        };
    }

    private static String resolveSectionId(String investigationType) {
        if (String.isBlank(investigationType)) {
            return null;
        }
        return TYPE_TO_SECTION.get(investigationType.trim());
    }

    private static InvestigationRow toInvestigationRow(
            Investigations__c investigation,
            Verification__c verification,
            Map<Id, Document_CheckList__c> poiByApplicantId) {
        InvestigationRow row = new InvestigationRow();
        row.id = investigation.Id;
        row.verificationId = verification != null ? verification.Id : null;
        row.name = getFiLabelFromVerification(
            verification != null ? verification.Name : null,
            investigation.Name
        );
        row.applicantName = getApplicantName(investigation, verification, poiByApplicantId);
        row.applicantType = getApplicantType(investigation, verification);
        row.status = verification != null
            ? verification.Status__c
            : investigation.Status__c;
        return row;
    }

    private static String getApplicantName(
            Investigations__c investigation,
            Verification__c verification,
            Map<Id, Document_CheckList__c> poiByApplicantId) {
        if (verification != null) {
            Document_CheckList__c poiDocument = poiByApplicantId != null
                ? poiByApplicantId.get(verification.Applicant__c)
                : null;
            return resolveApplicantName(verification.Applicant__r, poiDocument);
        }
        return resolveApplicantNamesFromVerifications(investigation.Verifications__r, poiByApplicantId);
    }

    private static String getApplicantType(
            Investigations__c investigation,
            Verification__c verification) {
        if (verification != null) {
            return resolveApplicantType(verification.Applicant__r);
        }
        return resolveApplicantTypesFromVerifications(investigation.Verifications__r);
    }

    private static String resolveApplicantNamesFromVerifications(
            List<Verification__c> verifications,
            Map<Id, Document_CheckList__c> poiByApplicantId) {
        if (verifications == null || verifications.isEmpty()) {
            return '';
        }

        Set<String> applicantNames = new Set<String>();
        for (Verification__c childVerification : verifications) {
            Document_CheckList__c poiDocument = poiByApplicantId != null
                ? poiByApplicantId.get(childVerification.Applicant__c)
                : null;
            String applicantName = resolveApplicantName(childVerification.Applicant__r, poiDocument);
            if (String.isNotBlank(applicantName)) {
                applicantNames.add(applicantName);
            }
        }

        List<String> sortedNames = new List<String>(applicantNames);
        sortedNames.sort();
        return String.join(sortedNames, ', ');
    }

    private static String resolveApplicantTypesFromVerifications(List<Verification__c> verifications) {
        if (verifications == null || verifications.isEmpty()) {
            return '';
        }

        Set<String> applicantTypes = new Set<String>();
        for (Verification__c childVerification : verifications) {
            String applicantType = resolveApplicantType(childVerification.Applicant__r);
            if (String.isNotBlank(applicantType)) {
                applicantTypes.add(applicantType);
            }
        }

        List<String> sortedTypes = new List<String>(applicantTypes);
        sortedTypes.sort();
        return String.join(sortedTypes, ', ');
    }

    private static String resolveApplicantName(
            Applicant__c applicant,
            Document_CheckList__c poiDocument) {
        if (applicant == null) {
            return '';
        }
        if (String.isNotBlank(applicant.Company_Name__c)) {
            return applicant.Company_Name__c;
        }
        if (poiDocument != null) {
            List<String> poiParts = new List<String>();
            if (String.isNotBlank(poiDocument.First_Name__c)) {
                poiParts.add(poiDocument.First_Name__c);
            }
            if (String.isNotBlank(poiDocument.Last_Name__c)) {
                poiParts.add(poiDocument.Last_Name__c);
            }
            String poiName = String.join(poiParts, ' ').trim();
            if (String.isNotBlank(poiName)) {
                return poiName;
            }
        }

        List<String> nameParts = new List<String>();
        if (String.isNotBlank(applicant.Customer_First_Name__c)) {
            nameParts.add(applicant.Customer_First_Name__c);
        }
        if (String.isNotBlank(applicant.Customer_Last_Name__c)) {
            nameParts.add(applicant.Customer_Last_Name__c);
        }
        return String.join(nameParts, ' ').trim();
    }

    private static Map<Id, Document_CheckList__c> getPoiIdentityDocumentsByApplicant(Set<Id> applicantIds) {
        Map<Id, Document_CheckList__c> poiByApplicant = new Map<Id, Document_CheckList__c>();
        if (applicantIds == null || applicantIds.isEmpty()) {
            return poiByApplicant;
        }

        for (Document_CheckList__c document : [
            SELECT Id,
                   Applicant__c,
                   KYC_Date_of_Birth__c,
                   Gender__c,
                   First_Name__c,
                   Last_Name__c,
                   Applicant_Address__r.Address_Proof__c,
                   Applicant_Address__r.Identity_Proof__c
            FROM Document_CheckList__c
            WHERE Applicant__c IN :applicantIds
              AND Applicant_Address__r.Identity_Proof__c = true
              AND Is_Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ]) {
            if (!poiByApplicant.containsKey(document.Applicant__c)) {
                poiByApplicant.put(document.Applicant__c, document);
            }
        }
        return poiByApplicant;
    }

    private static String resolveApplicantType(Applicant__c applicant) {
        return applicant != null && String.isNotBlank(applicant.Applicant_Type__c)
            ? applicant.Applicant_Type__c
            : '';
    }

    private static String getFiLabelFromVerification(
            String verificationName,
            String fallbackName) {
        if (String.isBlank(verificationName)) {
            return fallbackName;
        }

        String normalized = verificationName.trim();
        if (normalized.endsWithIgnoreCase(VERIFICATION_NAME_SUFFIX)) {
            normalized = normalized.substring(
                0,
                normalized.length() - VERIFICATION_NAME_SUFFIX.length()
            ).trim();
        }
        return normalized;
    }
}