/**
 * Pre-creates the placeholder Document_CheckList__c rows the KYC Details stage
 * expects to find when it loads.
 *
 * The Current/Permanent Address bucket rows are uniquely identified by
 * (Applicant__c, Address_Type__c) — NOT by Document_Type__c.
 * 
 * Customer Image is a single-doc-type bucket (no Address_Type__c) and is
 * identified by Document_Type__c = 'Customer Image'.
 *
 * The Name field is populated as "Applicant Name + ' ' + Document Type" so
 * each row carries a human-readable label in list views.
 */
public with sharing class KYCInfoController {

    private static final String DOC_TYPE_CURRENT_ADDRESS_PROOF   = 'Current Address Proof';
    private static final String DOC_TYPE_PERMANENT_ADDRESS_PROOF = 'Permanent Address Proof';
    private static final String DOC_TYPE_CUSTOMER_IMAGE          = 'Customer Image';

    private static final String ADDRESS_TYPE_CURRENT   = 'Current Residential Address';
    private static final String ADDRESS_TYPE_PERMANENT = 'Permanent Residential Address';

    private static final Integer NAME_MAX_LENGTH = 80;

    @AuraEnabled
    public static Id createCurrentAddressChecklist(Id applicantId) {
        return ensureAddressBucketRow(applicantId, ADDRESS_TYPE_CURRENT, DOC_TYPE_CURRENT_ADDRESS_PROOF);
    }

    @AuraEnabled
    public static Id createPermanentAddressChecklist(Id applicantId) {
        return ensureAddressBucketRow(applicantId, ADDRESS_TYPE_PERMANENT, DOC_TYPE_PERMANENT_ADDRESS_PROOF);
    }

    @AuraEnabled
    public static Id createCustomerImageChecklist(Id applicantId) {
        return ensureCustomerImageRow(applicantId);
    }

    @TestVisible private static Map<Id, Applicant__c> applicantCache = new Map<Id, Applicant__c>();

    /**
     * Returns the existing active row for the (applicant, addressType)
     * bucket regardless of its current Document_Type__c value, so picking
     * Aadhaar / Passport / Voter ID / Driving License updates the SAME row.
     * Inserts a new row only when no active bucket row exists.
     */
    private static Id ensureAddressBucketRow(Id applicantId, String addressType, String placeholderDocType) {
        if (applicantId == null || String.isBlank(addressType)) {
            return null;
        }
        try {
            List<Document_CheckList__c> existing = [
                SELECT Id
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicantId
                  AND Address_Type__c = :addressType
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }
            Applicant__c applicant = resolveApplicant(applicantId);
            Document_CheckList__c row = new Document_CheckList__c(
                Applicant__c     = applicantId,
                Application__c   = applicant != null ? applicant.Application__c : null,
                Address_Type__c  = addressType,
                Document_Type__c = placeholderDocType,
                Is_Active__c     = true,
                Name             = buildChecklistName(applicant, placeholderDocType)
            );
            insert row;
            return row.Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'KYCInfoController.ensureAddressBucketRow ' + addressType + ': ' + e.getMessage());
            throw new AuraHandledException('Unable to pre-create ' + addressType + ' checklist: ' + e.getMessage());
        }
    }

    /** Same SOQL profile as {@link #ensureAddressBucketRow}. */
    private static Id ensureCustomerImageRow(Id applicantId) {
        if (applicantId == null) {
            return null;
        }
        try {
            List<Document_CheckList__c> existing = [
                SELECT Id
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicantId
                  AND Document_Type__c = :DOC_TYPE_CUSTOMER_IMAGE
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }
            Applicant__c applicant = resolveApplicant(applicantId);
            Document_CheckList__c row = new Document_CheckList__c(
                Applicant__c     = applicantId,
                Application__c   = applicant != null ? applicant.Application__c : null,
                Document_Type__c = DOC_TYPE_CUSTOMER_IMAGE,
                Is_Active__c     = true,
                Name             = buildChecklistName(applicant, DOC_TYPE_CUSTOMER_IMAGE)
            );
            insert row;
            return row.Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'KYCInfoController.ensureCustomerImageRow: ' + e.getMessage());
            throw new AuraHandledException('Unable to pre-create Customer Image checklist: ' + e.getMessage());
        }
    }

    /**
     * Cache-aware Applicant lookup. Issues at most ONE SOQL per
     * transaction, regardless of how many ensure*ChecklistRow calls land.
     * Returns null when the Applicant isn't readable (e.g. FLS).
     */
    private static Applicant__c resolveApplicant(Id applicantId) {
        if (applicantId == null) return null;
        Applicant__c cached = applicantCache.get(applicantId);
        if (cached != null) return cached;

        List<Applicant__c> rows = [
            SELECT Id, Application__c, Customer_First_Name__c, Customer_Last_Name__c
            FROM Applicant__c
            WHERE Id = :applicantId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;
        applicantCache.put(applicantId, rows[0]);
        return rows[0];
    }

    /**
     * Returns "Applicant Name + ' ' + Document Type" capped at 80 chars.
     */
    public static String buildChecklistName(Applicant__c applicant, String docType) {
        String docPart = String.isNotBlank(docType) ? docType : 'Document';
        String namePart = applicant == null ? '' : buildApplicantNamePart(applicant);
        String combined = String.isBlank(namePart) ? docPart : (namePart + ' ' + docPart);
        return combined.length() > NAME_MAX_LENGTH ? combined.substring(0, NAME_MAX_LENGTH) : combined;
    }

    /**
     * Renames the active checklist of the given document type to
     * "Applicant Name + Document Type" once that document is verified.
     * Runs for every verification path; a no-op when no row or name resolves.
     */
    public static void relabelVerifiedChecklist(Id applicantId, String documentType) {
        if (applicantId == null || String.isBlank(documentType)) {
            return;
        }
        try {
            List<Document_CheckList__c> rows = [
                SELECT Id, Name, Applicant__r.Customer_First_Name__c, Applicant__r.Customer_Last_Name__c
                FROM Document_CheckList__c
                WHERE Applicant__c = :applicantId
                  AND Document_Type__c = :documentType
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                return;
            }
            String label = buildChecklistName(rows[0].Applicant__r, documentType);
            if (String.isNotBlank(label) && label != rows[0].Name) {
                rows[0].Name = label;
                update rows[0];
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'KYCInfoController.relabelVerifiedChecklist: ' + e.getMessage());
        }
    }

    private static String buildApplicantNamePart(Applicant__c applicant) {
        String first = String.isNotBlank(applicant.Customer_First_Name__c) ? applicant.Customer_First_Name__c.trim() : '';
        String last  = String.isNotBlank(applicant.Customer_Last_Name__c)  ? applicant.Customer_Last_Name__c.trim()  : '';
        if (String.isBlank(first) && String.isBlank(last)) return '';
        if (String.isBlank(first)) return last;
        if (String.isBlank(last))  return first;
        return first + ' ' + last;
    }
}