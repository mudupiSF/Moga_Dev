/**
 * @description Controller for WheelsIndividualDemographicDetailsPage LWC
 * Handles loading and saving of applicant demographic details, references, and signatures
 *
 * @author Salesforce Developer
 * @date 2026
 */
public with sharing class WheelsIndividualDemographicController {

    private static final String APPLICANT_TYPE_REFERENCE = 'Reference';
    private static final String STAGE_DEMOGRAPHIC_DETAILS = 'Demographic Details';
    private static final String DOCUMENT_TYPE_CUSTOMER_SIGNATURE = 'Customer Signature';

    // ──────────────────────────────────────────────────────────────────────
    // LOAD
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @description Load demographic data for the current applicant and related records
     * @param recordId Application__c or Applicant__c record ID
     * @param applicantId Optional Applicant__c Id from parent; skips applicant lookup when provided
     */
    @AuraEnabled(cacheable=false)
    public static DemographicData loadDemographicData(Id recordId, Id applicantId) {
        try {
            return fetchDemographicDataForApplicant(resolveApplicantId(recordId, applicantId));
        } catch (Exception e) {
            throw new AuraHandledException('Error loading demographic data: ' + e.getMessage());
        }
    }

    private static Id resolveApplicantId(Id recordId, Id applicantId) {
        if (applicantId != null) {
            return applicantId;
        }
        return resolveApplicantIdFromRecordId(recordId);
    }

    private static Id resolveApplicantIdFromRecordId(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Missing recordId.');
        }

        String sobjectType = recordId.getSObjectType().getDescribe().getName();
        if (sobjectType == 'Applicant__c') {
            return recordId;
        }

        if (sobjectType == 'Application__c') {
            Id applicantId = queryApplicantIdForApplication(recordId);
            if (applicantId == null) {
                throw new AuraHandledException('No active applicant found for this Application.');
            }
            return applicantId;
        }

        throw new AuraHandledException('Invalid record type.');
    }

    private static Id queryApplicantIdForApplication(Id applicationId) {
        List<Applicant__c> applicants = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :applicationId
            AND Applicant_Type__c != :APPLICANT_TYPE_REFERENCE
            AND In_Active_Applicant__c = FALSE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return applicants.isEmpty() ? null : applicants[0].Id;
    }

    /**
     * @description Load current applicant, references, and addresses
     */
    private static DemographicData fetchDemographicDataForApplicant(Id applicantId) {
        Applicant__c primaryApplicant = queryPrimaryApplicant(applicantId);
        if (primaryApplicant == null) {
            throw new AuraHandledException('Applicant not found.');
        }

        List<Applicant__c> referenceApplicants = primaryApplicant.Application__c != null
            ? queryReferenceApplicantsWithAddresses(primaryApplicant.Application__c)
            : new List<Applicant__c>();

        return mapToDemographicData(primaryApplicant, referenceApplicants);
    }

    /**
     * @description Load the active primary applicant with address child records
     */
    private static Applicant__c queryPrimaryApplicant(Id applicantId) {
        List<Applicant__c> applicants = [
            SELECT Id,
                   Application__c,
                   Applicant_Type__c,
                   Name,
                   Father_s_name__c,
                   Mother_s_name__c,
                   Customer_Qualification__c,
                   Company_Name__c,
                   Relationship_with_borrower__c,
                   Preferred_Address_for_Communication__c,
                   Contact_number__c,
                   Religion__c,
                   Caste__c,
                   Communication_Language__c,
                   Demographic_Details_Correctly_Captured__c,
                   Remarks__c,
                   Application__r.Sub_Stage__c,
                   (
                       SELECT Id,
                              Address_Line_1__c,
                              Address_Line_2__c,
                              City__c,
                              State__c,
                              PinCode__c,
                              Country__c,
                              District__c,
                              Address_Type__c
                       FROM Applicant_Address__r
                       ORDER BY CreatedDate ASC
                       LIMIT 1
                   )
            FROM Applicant__c
            WHERE Id = :applicantId
            AND In_Active_Applicant__c = FALSE
            LIMIT 1
        ];
        return applicants.isEmpty() ? null : applicants[0];
    }

    /**
     * @description Map queried Applicant__c and Applicant_Address__c into wrapper
     */
    private static DemographicData mapToDemographicData(
        Applicant__c primaryApplicant,
        List<Applicant__c> referenceApplicants
    ) {
        DemographicData data = new DemographicData();
        data.applicant = mapApplicantInfo(primaryApplicant);

        data.references = new List<ReferenceInfo>();
        if (referenceApplicants != null) {
            for (Applicant__c referenceApplicant : referenceApplicants) {
                data.references.add(mapReferenceInfo(referenceApplicant));
            }
        }

        if (primaryApplicant.Application__r != null
            && primaryApplicant.Application__r.Sub_Stage__c != STAGE_DEMOGRAPHIC_DETAILS) {
            data.isReadOnly = true;
        }

        data.signature = getCustomerSignatureInfo(
            primaryApplicant.Application__c,
            primaryApplicant.Id
        );

        return data;
    }

    private static ApplicantInfo mapApplicantInfo(Applicant__c applicant) {
        ApplicantInfo info = new ApplicantInfo();
        info.id = applicant.Id;
        info.applicationId = applicant.Application__c;
        info.applicantType = applicant.Applicant_Type__c;
        info.name = applicant.Name;
        info.contactNumber = applicant.Contact_number__c;
        info.fatherName = applicant.Father_s_name__c;
        info.motherName = applicant.Mother_s_name__c;
        info.qualification = applicant.Customer_Qualification__c;
        info.companyName = applicant.Company_Name__c;
        info.relationshipWithBorrower = applicant.Relationship_with_borrower__c;
        info.religion = applicant.Religion__c;
        info.caste = applicant.Caste__c;
        info.communicationLanguage = applicant.Communication_Language__c;
        info.preferredAddressForCommunication = applicant.Preferred_Address_for_Communication__c;
        info.demographicDetailsCorrectlyCaptured = applicant.Demographic_Details_Correctly_Captured__c;
        info.remarks = applicant.Remarks__c;
        return info;
    }

    private static AddressInfo mapAddressInfo(Applicant_Address__c address) {
        AddressInfo info = new AddressInfo();
        info.id = address.Id;
        info.addressLine1 = address.Address_Line_1__c;
        info.addressLine2 = address.Address_Line_2__c;
        info.city = address.City__c;
        info.state = address.State__c;
        info.pinCode = address.PinCode__c;
        info.country = address.Country__c;
        info.district = address.District__c;
        info.addressType = address.Address_Type__c;
        return info;
    }

    private static ReferenceInfo mapReferenceInfo(Applicant__c referenceApplicant) {
        ReferenceInfo info = new ReferenceInfo();
        info.applicant = new ApplicantInfo();
        info.applicant.id = referenceApplicant.Id;
        info.applicant.applicantType = referenceApplicant.Applicant_Type__c;
        info.applicant.name = referenceApplicant.Name;
        info.applicant.contactNumber = referenceApplicant.Contact_number__c;
        info.applicant.relationshipWithBorrower = referenceApplicant.Relationship_with_borrower__c;

        List<Applicant_Address__c> addresses = referenceApplicant.getSObjects('Applicant_Address__r');
        if (addresses != null && !addresses.isEmpty()) {
            info.address = mapAddressInfo(addresses[0]);
        }

        return info;
    }

    // ──────────────────────────────────────────────────────────────────────
    // SAVE
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @description Save demographic data for the current applicant and related records
     * @param recordId Application__c or Applicant__c record ID
     * @param applicantId Optional Applicant__c Id from parent; skips applicant lookup when provided
     * @param dataJson JSON payload from LWC
     */
    @AuraEnabled
    public static SaveResult saveDemographicData(Id recordId, Id applicantId, String dataJson) {
        try {
            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(dataJson);

            SaveResult result = persistDemographicDataForApplicant(
                resolveApplicantId(recordId, applicantId),
                dataMap
            );
            result.success = true;
            result.message = 'Demographic details saved successfully';
            return result;
        } catch (Exception e) {
            SaveResult errorResult = new SaveResult();
            errorResult.success = false;
            errorResult.message = 'Error saving demographic data: ' + e.getMessage();
            return errorResult;
        }
    }

    /**
     * @description Persist demographic data to Applicant__c and reference applicants
     */
    private static SaveResult persistDemographicDataForApplicant(Id applicantId, Map<String, Object> dataMap) {
        SaveResult result = new SaveResult();

        saveApplicantDemographics(applicantId, dataMap);

        Id applicationId = queryApplicationIdForApplicant(applicantId);
        if (applicationId != null) {
            saveReferenceRecords(applicationId, dataMap);
        }

        return result;
    }

    private static void saveApplicantDemographics(Id applicantId, Map<String, Object> dataMap) {
        Applicant__c applicant = new Applicant__c(Id = applicantId);

        if (dataMap.containsKey('preferredAddressForCommunication')) {
            applicant.Preferred_Address_for_Communication__c = getStringValue(dataMap, 'preferredAddressForCommunication');
        }
        if (dataMap.containsKey('communicationLanguage')) {
            applicant.Communication_Language__c = getStringValue(dataMap, 'communicationLanguage');
        }
        if (dataMap.containsKey('fatherName')) {
            applicant.Father_s_name__c = getStringValue(dataMap, 'fatherName');
        }
        if (dataMap.containsKey('motherName')) {
            applicant.Mother_s_name__c = getStringValue(dataMap, 'motherName');
        }
        if (dataMap.containsKey('religion')) {
            applicant.Religion__c = getStringValue(dataMap, 'religion');
        }
        if (dataMap.containsKey('caste')) {
            applicant.Caste__c = getStringValue(dataMap, 'caste');
        }
        if (dataMap.containsKey('qualification')) {
            applicant.Customer_Qualification__c = getStringValue(dataMap, 'qualification');
        }
        if (dataMap.containsKey('relationshipWithBorrower')) {
            applicant.Relationship_with_borrower__c = getStringValue(dataMap, 'relationshipWithBorrower');
        }
        if (dataMap.containsKey('demographicDetailsCorrectlyCaptured')) {
            applicant.Demographic_Details_Correctly_Captured__c =
                getStringValue(dataMap, 'demographicDetailsCorrectlyCaptured');
        }
        if (dataMap.containsKey('remarks')) {
            applicant.Remarks__c = getStringValue(dataMap, 'remarks');
        }

        update applicant;
    }

    private static Id queryApplicationIdForApplicant(Id applicantId) {
        List<Applicant__c> applicants = [
            SELECT Application__c
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        return applicants.isEmpty() ? null : applicants[0].Application__c;
    }

    private static void saveReferenceRecords(Id applicationId, Map<String, Object> dataMap) {
        List<Applicant__c> existingReferences = queryReferenceApplicantsWithAddresses(applicationId);

        if (dataMap.containsKey('reference1')) {
            Map<String, Object> ref1Data = (Map<String, Object>) dataMap.get('reference1');
            Id ref1Id = getExistingReferenceApplicantId(ref1Data, existingReferences, 0);
            upsertReferenceApplicant(applicationId, ref1Data, ref1Id, existingReferences);
        }

        if (dataMap.containsKey('reference2')) {
            Map<String, Object> ref2Data = (Map<String, Object>) dataMap.get('reference2');
            Id ref2Id = getExistingReferenceApplicantId(ref2Data, existingReferences, 1);
            upsertReferenceApplicant(applicationId, ref2Data, ref2Id, existingReferences);
        }
    }

    private static List<Applicant__c> queryReferenceApplicantsWithAddresses(Id applicationId) {
        return [
            SELECT Id,
                   Applicant_Type__c,
                   Name,
                   Contact_number__c,
                   Relationship_with_borrower__c,
                   (
                       SELECT Id,
                              Address_Line_1__c,
                              Address_Line_2__c,
                              City__c,
                              State__c,
                              PinCode__c,
                              Country__c,
                              District__c,
                              Address_Type__c
                       FROM Applicant_Address__r
                       ORDER BY CreatedDate ASC
                       LIMIT 1
                   )
            FROM Applicant__c
            WHERE Application__c = :applicationId
            AND Applicant_Type__c = :APPLICANT_TYPE_REFERENCE
            AND In_Active_Applicant__c = FALSE
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
    }

    private static void upsertReferenceApplicant(
        Id applicationId,
        Map<String, Object> refData,
        Id existingReferenceApplicantId,
        List<Applicant__c> existingReferences
    ) {
        if (refData == null || !hasReferencePayload(refData)) {
            return;
        }

        Applicant__c referenceApplicant = buildReferenceApplicant(
            applicationId,
            refData,
            existingReferenceApplicantId
        );
        upsert referenceApplicant;

        if (!hasReferenceAddressPayload(refData)) {
            return;
        }

        Id existingAddressId = getExistingReferenceAddressId(
            refData,
            existingReferenceApplicantId,
            existingReferences
        );
        Applicant_Address__c referenceAddress = buildReferenceAddress(
            referenceApplicant.Id,
            refData,
            existingAddressId
        );
        upsert referenceAddress;
    }

    private static Applicant__c buildReferenceApplicant(
        Id applicationId,
        Map<String, Object> refData,
        Id existingReferenceApplicantId
    ) {
        Applicant__c referenceApplicant = existingReferenceApplicantId != null
            ? new Applicant__c(Id = existingReferenceApplicantId)
            : new Applicant__c();

        if (existingReferenceApplicantId == null) {
            referenceApplicant.Application__c = applicationId;
            referenceApplicant.Applicant_Type__c = APPLICANT_TYPE_REFERENCE;
            referenceApplicant.In_Active_Applicant__c = false;
        }

        if (refData.containsKey('referenceName')) {
            referenceApplicant.Name = getStringValue(refData, 'referenceName');
        } else if (refData.containsKey('name')) {
            referenceApplicant.Name = getStringValue(refData, 'name');
        }
        if (refData.containsKey('relationship')) {
            referenceApplicant.Relationship_with_borrower__c = getStringValue(refData, 'relationship');
        }
        if (refData.containsKey('phone')) {
            referenceApplicant.Contact_number__c = getStringValue(refData, 'phone');
        }

        return referenceApplicant;
    }

    private static Applicant_Address__c buildReferenceAddress(
        Id referenceApplicantId,
        Map<String, Object> refData,
        Id existingAddressId
    ) {
        Applicant_Address__c referenceAddress = existingAddressId != null
            ? new Applicant_Address__c(Id = existingAddressId)
            : new Applicant_Address__c();

        referenceAddress.Applicant__c = referenceApplicantId;

        if (refData.containsKey('addressLine1')) {
            referenceAddress.Address_Line_1__c = getStringValue(refData, 'addressLine1');
        }
        if (refData.containsKey('addressLine2')) {
            referenceAddress.Address_Line_2__c = getStringValue(refData, 'addressLine2');
        }
        if (refData.containsKey('city')) {
            referenceAddress.City__c = getStringValue(refData, 'city');
        }
        if (refData.containsKey('state')) {
            referenceAddress.State__c = getStringValue(refData, 'state');
        }
        if (refData.containsKey('pincode')) {
            referenceAddress.PinCode__c = getStringValue(refData, 'pincode');
        }

        return referenceAddress;
    }

    // ──────────────────────────────────────────────────────────────────────
    // SHARED HELPERS
    // ──────────────────────────────────────────────────────────────────────

    private static Id getExistingReferenceApplicantId(
        Map<String, Object> refData,
        List<Applicant__c> existingReferences,
        Integer fallbackIndex
    ) {
        if (refData != null && refData.containsKey('referenceId') && refData.get('referenceId') != null) {
            return (Id) String.valueOf(refData.get('referenceId'));
        }
        return existingReferences.size() > fallbackIndex ? existingReferences[fallbackIndex].Id : null;
    }

    private static Id getExistingReferenceAddressId(
        Map<String, Object> refData,
        Id existingReferenceApplicantId,
        List<Applicant__c> existingReferences
    ) {
        if (refData != null && refData.containsKey('addressId') && refData.get('addressId') != null) {
            return (Id) String.valueOf(refData.get('addressId'));
        }

        if (existingReferenceApplicantId == null || existingReferences == null) {
            return null;
        }

        for (Applicant__c existingReference : existingReferences) {
            if (existingReference.Id != existingReferenceApplicantId) {
                continue;
            }
            List<Applicant_Address__c> addresses = existingReference.getSObjects('Applicant_Address__r');
            return (addresses != null && !addresses.isEmpty()) ? addresses[0].Id : null;
        }

        return null;
    }

    private static Boolean hasReferencePayload(Map<String, Object> refData) {
        return hasReferenceApplicantPayload(refData) || hasReferenceAddressPayload(refData);
    }

    private static Boolean hasReferenceApplicantPayload(Map<String, Object> refData) {
        return refData.containsKey('referenceName')
            || refData.containsKey('name')
            || refData.containsKey('relationship')
            || refData.containsKey('phone');
    }

    private static Boolean hasReferenceAddressPayload(Map<String, Object> refData) {
        return refData.containsKey('addressLine1')
            || refData.containsKey('addressLine2')
            || refData.containsKey('city')
            || refData.containsKey('state')
            || refData.containsKey('pincode');
    }

    private static String getStringValue(Map<String, Object> dataMap, String key) {
        if (dataMap == null || !dataMap.containsKey(key) || dataMap.get(key) == null) {
            return null;
        }
        return String.valueOf(dataMap.get(key));
    }

    // ──────────────────────────────────────────────────────────────────────
    // SIGNATURE UPLOAD (Document_CheckList__c)
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @description Returns an existing Document_CheckList__c row for the customer signature,
     * or creates one when none exists for the application + applicant combination.
     */
    @AuraEnabled
    public static String initOrGetDocumentWithApplicantId(
        String applicationId,
        String documentType,
        String applicantId
    ) {
        try {
            String resolvedDocumentType = String.isBlank(documentType)
                ? DOCUMENT_TYPE_CUSTOMER_SIGNATURE
                : documentType;

            List<Document_CheckList__c> existingDocs = [
                SELECT Id
                FROM Document_CheckList__c
                WHERE Application__c = :applicationId
                  AND Applicant__c = :applicantId
                  AND Document_Type__c = :resolvedDocumentType
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (!existingDocs.isEmpty()) {
                return existingDocs[0].Id;
            }

            Document_CheckList__c newDoc = new Document_CheckList__c();
            newDoc.Name = resolvedDocumentType + ' - Document';
            newDoc.Document_Type__c = resolvedDocumentType;
            newDoc.Application__c = applicationId;
            newDoc.Applicant__c = applicantId;
            insert newDoc;
            return newDoc.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error initializing document: ' + e.getMessage());
        }
    }

    /**
     * @description Links an uploaded ContentDocument to the Document_CheckList__c row.
     */
    @AuraEnabled
    public static void linkContentDocument(String documentDataJson) {
        if (String.isBlank(documentDataJson)) {
            return;
        }

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(documentDataJson);
        String contentDocumentId = (String) data.get('contentDocumentId');
        String applicationId = (String) data.get('applicationId');
        String applicantId = (String) data.get('applicantId');
        String documentType = (String) data.get('documentType');

        if (String.isBlank(contentDocumentId)) {
            return;
        }

        String documentId = initOrGetDocumentWithApplicantId(applicationId, documentType, applicantId);
        if (String.isBlank(documentId)) {
            documentId = applicationId;
        }

        String contentVersionId = getLatestContentVersionId(contentDocumentId);
        if (String.isNotBlank(documentId) && String.isNotBlank(contentVersionId)) {
            update new Document_CheckList__c(
                Id = documentId,
                ContentVersionId__c = contentVersionId
            );
            return;
        }

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :documentId AND ContentDocumentId = :contentDocumentId
            LIMIT 1
        ];
        if (links.isEmpty()) {
            insert new ContentDocumentLink(
                LinkedEntityId = documentId,
                ContentDocumentId = contentDocumentId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        }
    }

    private static SignatureInfo getCustomerSignatureInfo(Id applicationId, Id applicantId) {
        SignatureInfo info = new SignatureInfo();
        if (applicationId == null || applicantId == null) {
            return info;
        }

        List<Document_CheckList__c> documentList = [
            SELECT Id, ContentVersionId__c
            FROM Document_CheckList__c
            WHERE Application__c = :applicationId
              AND Applicant__c = :applicantId
              AND Document_Type__c = :DOCUMENT_TYPE_CUSTOMER_SIGNATURE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (documentList.isEmpty()) {
            return info;
        }

        Document_CheckList__c checklistRow = documentList[0];
        info.documentChecklistId = checklistRow.Id;
        info.uploaded = String.isNotBlank(checklistRow.ContentVersionId__c);

        if (!info.uploaded) {
            return info;
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, ContentDocumentId, CreatedDate
            FROM ContentVersion
            WHERE Id = :checklistRow.ContentVersionId__c
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            return info;
        }

        info.contentDocumentId = versions[0].ContentDocumentId;
        info.fileName = versions[0].Title;
        info.uploadedAt = versions[0].CreatedDate != null
            ? versions[0].CreatedDate.format()
            : null;
        return info;
    }

    private static String getLatestContentVersionId(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            return null;
        }
        List<ContentVersion> versions = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0].Id;
    }

    // ──────────────────────────────────────────────────────────────────────
    // WRAPPER CLASSES
    // ──────────────────────────────────────────────────────────────────────

    public class DemographicData {
        @AuraEnabled public ApplicantInfo applicant;
        @AuraEnabled public List<ReferenceInfo> references;
        @AuraEnabled public SignatureInfo signature;
        @AuraEnabled public Boolean isReadOnly;

        public DemographicData() {
            this.references = new List<ReferenceInfo>();
            this.isReadOnly = false;
        }
    }

    public class SignatureInfo {
        @AuraEnabled public Id documentChecklistId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String uploadedAt;
        @AuraEnabled public Boolean uploaded;

        public SignatureInfo() {
            this.uploaded = false;
        }
    }

    /** Applicant__c demographic fields for the current applicant or a reference applicant */
    public class ApplicantInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public Id applicationId;
        @AuraEnabled public String applicantType;
        @AuraEnabled public String name;
        @AuraEnabled public String contactNumber;
        @AuraEnabled public String fatherName;
        @AuraEnabled public String motherName;
        @AuraEnabled public String qualification;
        @AuraEnabled public String companyName;
        @AuraEnabled public String relationshipWithBorrower;
        @AuraEnabled public String religion;
        @AuraEnabled public String caste;
        @AuraEnabled public String communicationLanguage;
        @AuraEnabled public String preferredAddressForCommunication;
        @AuraEnabled public String demographicDetailsCorrectlyCaptured;
        @AuraEnabled public String remarks;
    }

    /** Applicant_Address__c fields */
    public class AddressInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String addressLine1;
        @AuraEnabled public String addressLine2;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String pinCode;
        @AuraEnabled public String country;
        @AuraEnabled public String district;
        @AuraEnabled public String addressType;
    }

    /** Reference applicant (Applicant__c) with linked Applicant_Address__c */
    public class ReferenceInfo {
        @AuraEnabled public ApplicantInfo applicant;
        @AuraEnabled public AddressInfo address;

        public ReferenceInfo() {
            this.applicant = new ApplicantInfo();
        }
    }

    public class SaveResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String errorDetails;
    }
}