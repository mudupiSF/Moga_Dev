/**
 * KYC Details stage controller. Exposes five actions through Callable:
 *   getKYCInfoPageData              — page payload for the KYC LWC.
 *   saveKYCInfoPageData             — persists KYC answers on NEXT.
 *   createCurrentAddressChecklist   — idempotent Current Address proof row.
 *   createPermanentAddressChecklist — idempotent Permanent Address proof row.
 *   createOfficeAddressChecklist    — idempotent Office Address row (Earning only).
 *   deleteCurrentAddressKycFile     — server-side file removal.
 *   getIntegrationMaster              — Integration_Master__c lookup for orchestrator LWCs.
 */
public with sharing class KYCDetailsController implements Callable {

    private static final String STAGE_KYC_DETAILS = 'KYC Details';
    private static final String STAGE_DEDUPE_AND_ELIGIBILITY = 'Dedupe and Eligibility';

    private static final String ADDRESS_TYPE_CURRENT   = 'Current Residential Address';
    private static final String ADDRESS_TYPE_PERMANENT = 'Permanent Residential Address';
    private static final String ADDRESS_TYPE_OFFICE    = 'Office Address';
    private static final String ADDRESS_TYPE_REGISTERED = 'Registered Address';
    private static final String ADDRESS_TYPE_GST        = 'GST Certificate';

    private static final String DOC_TYPE_CURRENT_ADDRESS_PROOF   = 'Current Address Proof';
    private static final String DOC_TYPE_PERMANENT_ADDRESS_PROOF = 'Permanent Address Proof';
    private static final String DOC_TYPE_OFFICE_ADDRESS_PROOF    = 'Office Address Proof';
    private static final String DOC_TYPE_REGISTERED_ADDRESS_PROOF = 'Registered Address Proof';
    private static final String DOC_TYPE_CUSTOMER_IMAGE          = 'Customer Image';
    private static final String DOC_TYPE_CIN                     = 'CIN';
    private static final String DOC_TYPE_GST                     = 'GST';
    // PAN / Form 60 must be excluded from the entity-additional sweep below, or
    // saving KYC would delete the Basic Details PAN/Form 60 checklist (and its
    // file) whenever that doc type is also listed in Non_Individual_Constitution.
    private static final String DOC_TYPE_PAN                     = 'PAN';
    private static final String DOC_TYPE_FORM_60                 = 'Form 60';
    private static final String BUCKET_ENTITY_ADDITIONAL         = 'ENTITY_ADDITIONAL';
    private static final String BUCKET_ENTITY_DARPAN             = 'ENTITY_DARPAN';
    private static final String BUCKET_ENTITY_PAN                = 'ENTITY_PAN';
    private static final String DOC_CATEGORY_ENTITY_ADDITIONAL   = 'KYC - Entity Additional Document';
    private static final String DOC_CATEGORY_ENTITY_DARPAN       = 'Government - DARPAN / NGO';
    private static final Decimal ENTITY_ADDITIONAL_FALLBACK_MAX_FILES = 1;
    private static final String ENTITY_ADDITIONAL_FALLBACK_FILE_TYPES = 'pdf,jpg,jpeg,png';
    private static final String CUSTOMER_TYPE_NON_INDIVIDUAL     = 'Non-Individual';
    private static final String SIDE_FULL                        = 'Full';
    private static final String SIDE_FRONT                       = 'Front';
    private static final String SIDE_BACK                        = 'Back';
    private static final String SIDE_MODE_FULL                   = 'Full';
    private static final String SIDE_MODE_SIDE                   = 'Side';

    private static final String YES = 'Yes';
    private static final String INCOME_CATEGORY_NON_EARNING = 'Non-Earning';

    private static final String ACTION_GET_PAGE_DATA              = 'getKYCInfoPageData';
    private static final String ACTION_GET_NON_INDIVIDUAL_PAGE_DATA = 'getNonIndividualKYCInfoPageData';
    private static final String ACTION_SAVE_PAGE_DATA             = 'saveKYCInfoPageData';
    private static final String ACTION_CREATE_CURRENT_CHECKLIST   = 'createCurrentAddressChecklist';
    private static final String ACTION_CREATE_PERMANENT_CHECKLIST = 'createPermanentAddressChecklist';
    private static final String ACTION_CREATE_OFFICE_CHECKLIST    = 'createOfficeAddressChecklist';
    private static final String ACTION_CREATE_REGISTERED_CHECKLIST = 'createRegisteredAddressChecklist';
    private static final String ACTION_CREATE_ENTITY_OFFICE_CHECKLIST = 'createEntityOfficeAddressChecklist';
    private static final String ACTION_CREATE_CIN_CHECKLIST       = 'createCinChecklist';
    private static final String ACTION_CREATE_GST_CHECKLIST       = 'createGstChecklist';
    private static final String ACTION_DELETE_ADDRESS_FILE        = 'deleteCurrentAddressKycFile';
    private static final String ACTION_GET_INTEGRATION_MASTER     = 'getIntegrationMaster';
    private static final String ACTION_SAVE_NON_INDIVIDUAL_KYC_DOC = 'saveNonIndividualKycDoc';
    private static final String ACTION_GET_ENTITY_DOCUMENT_MASTER = 'getEntityDocumentMasterConfig';
    private static final String ACTION_RESOLVE_CONTENT_DOCUMENT_ID = 'resolveContentDocumentId';
    private static final String ACTION_STAMP_ENTITY_ADDRESS_CHECKLIST = 'stampEntityAddressChecklist';

    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';

    private static final String DOC_NAME_ELECTRICITY_BILL = 'Electricity Bill (within 2 months)';

    private static final String DOC_NAME_CIN_CERTIFICATE = 'CIN Certificate';
    private static final String DOC_NAME_GST_CERTIFICATE = 'GST Certificate';
    private static final String DOC_NAME_DARPAN_CERTIFICATE = 'DARPAN Certificate';
    private static final String DOC_NAME_DARPAN_CUSTOMER_DECLARATION = 'DARPAN Id - Customer Declaration';
    private static final String DOC_NAME_DARPAN_DEFERRAL_APPROVAL = 'DARPAN Id - Deferral Approval';
    private static final String DOC_NAME_DARPAN_ACK_COPY = 'DARPAN Id - Acknowledgement Copy';
    private static final String DARPAN_STATUS_NPO = 'NPO';
    private static final String DARPAN_STATUS_NOT_NPO = 'Not an NPO';
    private static final Set<String> DARPAN_DOC_TYPES = new Set<String>{
        DOC_NAME_DARPAN_CERTIFICATE,
        DOC_NAME_DARPAN_CUSTOMER_DECLARATION,
        DOC_NAME_DARPAN_DEFERRAL_APPROVAL,
        DOC_NAME_DARPAN_ACK_COPY
    };
    private static final Set<String> DARPAN_ENTITY_CODES = new Set<String>{ '50', '60', '70' };

    private static final String APPLICANT_SELECT =
        'Id,Application__c,Applicant_Type__c,Applicant_Tab_Label__c,Type__c,Entity_Type__c,' +
        'Customer_First_Name__c,Customer_Last_Name__c,' +
        'NPO__c,Deferral_Approval__c,Darpan_Id__c,Darpan_Registration_Date__c,' +
        'CKYC_ID__c,Income_Category__c,' +
        'Is_Applicant_Relative_Of_Director__c,Is_Applicant_Relative_Of_Senior_Officer__c,' +
        'Are_you_a_Politically_Exposed_Person__c,' +
        'Has_Bank_Account__c,Interested_In_Opening_Savings_Account__c,' +
        'ETB_CASA_Details__c,Bank_Account_No__c,Customer_Code__c,' +
        'Loan_Stage__c,Current_Loan_Stage_Complete__c';

    private SObject cachedApplicant;
    private SObject cachedBorrowerApplicant;

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_GET_PAGE_DATA.equalsIgnoreCase(action)) {
            return getKYCInfoPageDataInternal(args);
        }
        if (ACTION_GET_NON_INDIVIDUAL_PAGE_DATA.equalsIgnoreCase(action)) {
            return getNonIndividualKYCInfoPageDataInternal(args);
        }
        if (ACTION_SAVE_PAGE_DATA.equalsIgnoreCase(action)) {
            return saveKYCInfoPageDataInternal(args);
        }
        if (ACTION_CREATE_CURRENT_CHECKLIST.equalsIgnoreCase(action)) {
            return createAddressChecklistInternal(args, ADDRESS_TYPE_CURRENT);
        }
        if (ACTION_CREATE_PERMANENT_CHECKLIST.equalsIgnoreCase(action)) {
            return createAddressChecklistInternal(args, ADDRESS_TYPE_PERMANENT);
        }
        if (ACTION_CREATE_OFFICE_CHECKLIST.equalsIgnoreCase(action)) {
            return createAddressChecklistInternal(args, ADDRESS_TYPE_OFFICE);
        }
        if (ACTION_CREATE_REGISTERED_CHECKLIST.equalsIgnoreCase(action)) {
            return createEntityAddressChecklistInternal(args, ADDRESS_TYPE_REGISTERED);
        }
        if (ACTION_CREATE_ENTITY_OFFICE_CHECKLIST.equalsIgnoreCase(action)) {
            return createEntityAddressChecklistInternal(args, ADDRESS_TYPE_OFFICE);
        }
        if (ACTION_CREATE_CIN_CHECKLIST.equalsIgnoreCase(action)) {
            return createEntityChecklistInternal(args, DOC_TYPE_CIN);
        }
        if (ACTION_CREATE_GST_CHECKLIST.equalsIgnoreCase(action)) {
            return createEntityChecklistInternal(args, DOC_TYPE_GST);
        }
        if (ACTION_DELETE_ADDRESS_FILE.equalsIgnoreCase(action)) {
            return deleteCurrentAddressKycFileInternal(args);
        }
        if (ACTION_GET_INTEGRATION_MASTER.equalsIgnoreCase(action)) {
            return getIntegrationMasterInternal(args);
        }
        if (ACTION_SAVE_NON_INDIVIDUAL_KYC_DOC.equalsIgnoreCase(action)) {
            return saveNonIndividualKycDocInternal(args);
        }
        if (ACTION_GET_ENTITY_DOCUMENT_MASTER.equalsIgnoreCase(action)) {
            return getEntityDocumentMasterConfigInternal(args);
        }
        if (ACTION_RESOLVE_CONTENT_DOCUMENT_ID.equalsIgnoreCase(action)) {
            return resolveContentDocumentIdInternal(args);
        }
        if (ACTION_STAMP_ENTITY_ADDRESS_CHECKLIST.equalsIgnoreCase(action)) {
            return stampEntityAddressChecklistInternal(args);
        }
        return new Map<String, Object>{
            'isSuccess' => false,
            'message'   => 'Unknown action: ' + action
        };
    }

    // =========================================================================
    // Page load
    // =========================================================================

    private Map<String, Object> getKYCInfoPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            Id recordId = parseId(args.get('recordId'));
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }
            loadCachedData(recordId, args);

            Id applicantId = cachedApplicant != null ? (Id) cachedApplicant.get('Id') : null;
            String customerType = cachedApplicant != null
                ? stringValue(cachedApplicant.get('Type__c'))
                : null;

            if (CUSTOMER_TYPE_NON_INDIVIDUAL.equalsIgnoreCase(customerType)) {
                return getNonIndividualKYCInfoPageDataInternal(args);
            }

            Boolean stageComplete = isStageCompleteForApplicant(STAGE_KYC_DETAILS);

            // Single SOQL fetches Current + Permanent + Office + Customer
            // Image rows. Current is created on-demand; Permanent / Office
            // are only created when the user opens the respective panel.
            // Customer Image is pre-seeded by Basic Details (KYCInfoController).
            Map<String, Document_CheckList__c> rowsByType = loadAddressChecklistRows(recordId, applicantId);
            Document_CheckList__c currentRow      = rowsByType.get(ADDRESS_TYPE_CURRENT);
            Document_CheckList__c permanentRow    = rowsByType.get(ADDRESS_TYPE_PERMANENT);
            Document_CheckList__c officeRow       = rowsByType.get(ADDRESS_TYPE_OFFICE);
            Document_CheckList__c customerImgRow  = rowsByType.get(DOC_TYPE_CUSTOMER_IMAGE);

            // Single SOQL pulls files for all bucket rows.
            Map<Id, Map<String, Object>> filesByChecklist = queryAddressProofFiles(
                new Set<Id>{
                    currentRow      != null ? currentRow.Id      : null,
                    permanentRow    != null ? permanentRow.Id    : null,
                    officeRow       != null ? officeRow.Id       : null,
                    customerImgRow  != null ? customerImgRow.Id  : null
                }
            );
            Map<String, Object> currentFileMap   = mergeFileMap(currentRow,   filesByChecklist);
            Map<String, Object> permanentFileMap = mergeFileMap(permanentRow, filesByChecklist);

            Map<String, Object> currentExtractedDetails   = buildExtractedDetailsMap(currentRow);
            Map<String, Object> permanentExtractedDetails = buildExtractedDetailsMap(permanentRow);

            String incomeCategory = cachedApplicant != null
                ? stringValue(cachedApplicant.get('Income_Category__c'))
                : null;
            Boolean officeAddressRequired = String.isNotBlank(incomeCategory)
                && !INCOME_CATEGORY_NON_EARNING.equalsIgnoreCase(incomeCategory);

            result.put('isSuccess', true);
            result.put('applicantId', applicantId);
            result.put('customerType', customerType);
            result.put('stageIsComplete', stageComplete);
            result.put('extractedDetailsIsReadOnly', stageComplete);
            result.put('incomeCategory', incomeCategory);
            result.put('officeAddressRequired', officeAddressRequired);

            result.put('kycInfoFileUploadRecordId', currentRow != null ? currentRow.Id : null);
            result.put('kycInfo', getKYCInfoConfig(currentFileMap, stageComplete));
            result.put('aadhaarVerifyState', getAadhaarVerifyState(currentRow));

            result.put('kycInfoPermanentFileUploadRecordId', permanentRow != null ? permanentRow.Id : null);
            result.put('kycInfoPermanent', getKYCInfoConfig(permanentFileMap, stageComplete));
            result.put('aadhaarVerifyStatePermanent', getAadhaarVerifyState(permanentRow));

            result.put('officeAddressChecklistId', officeRow != null ? officeRow.Id : null);
            result.put('officeAddress', buildOfficeAddressPayload(officeRow));

            result.put('extractedDetails', new Map<String, Object>{
                'current'   => currentExtractedDetails,
                'permanent' => permanentExtractedDetails
            });

            result.put('addressVerification',  getAddressVerificationConfig(currentRow));
            result.put('directorDeclaration',  getDirectorDeclarationConfig());
            result.put('pepScreening',         getPepScreeningConfig());
            result.put('bankAccountCheck',     getBankAccountCheckConfig());
            result.put('crossSell',            getCrossSellAccountsConfig());
            result.put('customerImageCapture', getCustomerImageCaptureConfig(customerImgRow, filesByChecklist));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('isSuccess', false);
            result.put('message', 'KYCDetailsController.getKYCInfoPageData: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Non-Individual KYC page payload — CIN, GST, Registered, and Office buckets.
     * Does not load or create Individual address checklist rows.
     */
    private Map<String, Object> getNonIndividualKYCInfoPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        Id applicantId = null;
        String customerType = null;
        try {
            Id recordId = parseId(args.get('recordId'));
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }
            loadCachedData(recordId, args);

            applicantId = cachedApplicant != null ? (Id) cachedApplicant.get('Id') : null;
            customerType = cachedApplicant != null
                ? stringValue(cachedApplicant.get('Type__c'))
                : null;
            Boolean stageComplete = isStageCompleteForApplicant(STAGE_KYC_DETAILS);

            EntityPageChecklistLoadResult entityLoad = loadEntityPageChecklistData(recordId, applicantId);
            Map<String, Document_CheckList__c> entityRows = entityLoad.buckets;
            Document_CheckList__c cinRow        = entityRows.get(DOC_TYPE_CIN);
            Document_CheckList__c gstRow        = entityRows.get(DOC_TYPE_GST);
            Document_CheckList__c panRow        = entityRows.get(BUCKET_ENTITY_PAN);
            Document_CheckList__c registeredRow = entityRows.get(ADDRESS_TYPE_REGISTERED);
            Document_CheckList__c officeRow     = entityRows.get(ADDRESS_TYPE_OFFICE);
            List<Document_CheckList__c> additionalRows = entityLoad.additionalRows;
            List<Document_CheckList__c> darpanRows = entityLoad.darpanRows;
            Set<Id> entityChecklistIds = new Set<Id>{
                cinRow        != null ? cinRow.Id        : null,
                gstRow        != null ? gstRow.Id        : null,
                panRow        != null ? panRow.Id        : null,
                registeredRow != null ? registeredRow.Id : null,
                officeRow     != null ? officeRow.Id     : null
            };
            for (Document_CheckList__c additionalRow : additionalRows) {
                if (additionalRow != null) {
                    entityChecklistIds.add(additionalRow.Id);
                }
            }
            for (Document_CheckList__c darpanRow : darpanRows) {
                if (darpanRow != null) {
                    entityChecklistIds.add(darpanRow.Id);
                }
            }
            Map<Id, Map<String, Object>> entityFiles = queryAddressProofFiles(entityChecklistIds);
            seedEntityFilesFromContentVersionIds(
                entityFiles,
                new List<Document_CheckList__c>{ cinRow, gstRow, panRow, registeredRow, officeRow }
            );
            seedEntityFilesFromContentVersionIds(entityFiles, additionalRows);
            seedEntityFilesFromContentVersionIds(entityFiles, darpanRows);

            Map<String, Object> entityKyc = buildEntityKycPayload(cinRow, gstRow, entityFiles);
            entityKyc.put(
                'additionalDocuments',
                buildEntityAdditionalDocumentsPayload(additionalRows, entityFiles)
            );
            String entityCode = normalizeEntityCode(cachedApplicant != null ? cachedApplicant.get('Entity_Type__c') : null);
            entityKyc.put('entityTypeCode', entityCode);
            entityKyc.put('darpanApplicable', isDarpanApplicableForEntityCode(entityCode));
            entityKyc.put('darpanDocuments', buildEntityAdditionalDocumentsPayload(darpanRows, entityFiles));
            entityKyc.put('darpan', evaluateDarpanMandatoryDocuments(
                darpanRows,
                null,
                entityFiles
            ));
            try {
                entityKyc.putAll(buildEntityAddressHydrationPayload(
                    registeredRow, officeRow, gstRow, entityFiles
                ));
            } catch (Exception hydrateEx) {
                entityKyc.put('hydrationWarning', hydrateEx.getMessage());
            }
            Map<String, Object> constitution = loadEntityConstitutionConfig(recordId);
            entityKyc.putAll(constitution);
            entityKyc.putAll(evaluateEntityMandatoryDocuments(
                constitution,
                cinRow,
                gstRow,
                panRow,
                registeredRow,
                officeRow,
                additionalRows,
                entityFiles
            ));

            result.put('isSuccess', true);
            result.put('applicantId', applicantId);
            result.put('customerType', customerType);
            result.put('stageIsComplete', stageComplete);
            result.put('extractedDetailsIsReadOnly', stageComplete);
            result.put('entityKyc', entityKyc);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('isSuccess', false);
            result.put('message', 'KYCDetailsController.getNonIndividualKYCInfoPageData: ' + e.getMessage());
            if (applicantId != null) {
                result.put('applicantId', applicantId);
            }
            if (String.isNotBlank(customerType)) {
                result.put('customerType', customerType);
            }
        }
        return result;
    }

    /**
     * Returns existing Current / Permanent / Office / Customer Image
     * checklist rows keyed by bucket name from one SOQL query.
     *   Key set: ADDRESS_TYPE_CURRENT, ADDRESS_TYPE_PERMANENT,
     *            ADDRESS_TYPE_OFFICE, DOC_TYPE_CUSTOMER_IMAGE.
     */
    private Map<String, Document_CheckList__c> loadAddressChecklistRows(Id recordId, Id applicantId) {
        Map<String, Document_CheckList__c> out = new Map<String, Document_CheckList__c>();
        if (applicantId == null) {
            return out;
        }
        // When multiple rows exist for the same bucket, we pick
        // the row carrying the most state (linked KYC + concrete doc type)
        for (Document_CheckList__c row : queryChecklistRows(
                applicantId,
                new Set<String>{ ADDRESS_TYPE_CURRENT, ADDRESS_TYPE_PERMANENT, ADDRESS_TYPE_OFFICE },
                new Set<String>{ DOC_TYPE_CUSTOMER_IMAGE })) {
            String bucketKey = resolveBucketType(row);
            Document_CheckList__c existing = out.get(bucketKey);
            if (existing == null || isMorePopulatedChecklistRow(row, existing)) {
                out.put(bucketKey, row);
            }
        }
        return out;
    }

    private static Boolean isMorePopulatedChecklistRow(
        Document_CheckList__c candidate,
        Document_CheckList__c current
    ) {
        Boolean candidateHasConcreteType = hasConcreteDocType(candidate);
        Boolean currentHasConcreteType   = hasConcreteDocType(current);
        if (candidateHasConcreteType && !currentHasConcreteType) return true;
        if (!candidateHasConcreteType && currentHasConcreteType) return false;

        Boolean candidateHasKyc = candidate.Applicant_KYC__c != null;
        Boolean currentHasKyc   = current.Applicant_KYC__c   != null;
        if (candidateHasKyc && !currentHasKyc) return true;
        return false;
    }

    private static Boolean hasConcreteDocType(Document_CheckList__c row) {
        String docType = row != null ? row.Document_Type__c : null;
        if (String.isBlank(docType)) return false;
        if (DOC_TYPE_CURRENT_ADDRESS_PROOF.equalsIgnoreCase(docType))   return false;
        if (DOC_TYPE_PERMANENT_ADDRESS_PROOF.equalsIgnoreCase(docType)) return false;
        if (DOC_TYPE_OFFICE_ADDRESS_PROOF.equalsIgnoreCase(docType))    return false;
        return true;
    }

    /** Classifies a checklist row into one of the four bucket keys. */
    private static String resolveBucketType(Document_CheckList__c row) {
        if (DOC_TYPE_CUSTOMER_IMAGE.equals(row.Document_Type__c)) {
            return DOC_TYPE_CUSTOMER_IMAGE;
        }
        if (ADDRESS_TYPE_OFFICE.equals(row.Address_Type__c)
            || DOC_TYPE_OFFICE_ADDRESS_PROOF.equals(row.Document_Type__c)) {
            return ADDRESS_TYPE_OFFICE;
        }
        if (ADDRESS_TYPE_PERMANENT.equals(row.Address_Type__c)
            || DOC_TYPE_PERMANENT_ADDRESS_PROOF.equals(row.Document_Type__c)) {
            return ADDRESS_TYPE_PERMANENT;
        }
        if (ADDRESS_TYPE_REGISTERED.equals(row.Address_Type__c)
            || DOC_TYPE_REGISTERED_ADDRESS_PROOF.equals(row.Document_Type__c)) {
            return ADDRESS_TYPE_REGISTERED;
        }
        return ADDRESS_TYPE_CURRENT;
    }

    private List<Map<String, Object>> getKYCInfoConfig(
        Map<String, Object> currentFileMap,
        Boolean stageComplete
    ) {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();

        String savedDocType  = (String) currentFileMap.get('uiDocumentType');
        String savedSideMode = String.isNotBlank((String) currentFileMap.get('sideMode'))
            ? (String) currentFileMap.get('sideMode')
            : SIDE_MODE_FULL;
        Object savedCkycId = cachedApplicant != null ? cachedApplicant.get('CKYC_ID__c') : null;
        Boolean savedAddressProof  = (Boolean) currentFileMap.get('addressProofToggle');
        Boolean savedIdentityProof = (Boolean) currentFileMap.get('identityProofToggle');

        fields.add(fieldEntry('addrDocumentType',          savedDocType));
        fields.add(fieldEntry('documentSideMode',          savedSideMode));
        fields.add(fieldEntry('addressProofFile',          currentFileMap.get('fullFile')));
        fields.add(fieldEntry('addressProofFileFront',     currentFileMap.get('frontFile')));
        fields.add(fieldEntry('addressProofFileBack',      currentFileMap.get('backFile')));
        fields.add(fieldEntry('ckycId',                    savedCkycId != null ? String.valueOf(savedCkycId) : null));
        fields.add(fieldEntry('addressProofToggle',        savedAddressProof  != null ? savedAddressProof  : false));
        fields.add(fieldEntry('identityProofToggle',       savedIdentityProof != null ? savedIdentityProof : false));

        return fields;
    }

    /**
     * Returns the Office Address payload for the LWC: address lines,
     * pincode/city/state/country, plus email + email-verified flag from
     * the linked Applicant_Address__c. Returns an empty map when the
     * bucket has no row or no address record yet.
     */
    private Map<String, Object> buildOfficeAddressPayload(Document_CheckList__c row) {
        Map<String, Object> out = new Map<String, Object>{
            'addressLine1'    => null,
            'addressLine2'    => null,
            'addressLine3'    => null,
            'pinCode'         => null,
            'city'            => null,
            'state'           => null,
            'country'         => null,
            'email'           => null,
            'emailVerified'   => false
        };
        if (row == null) {
            return out;
        }
        Applicant_Address__c addr = row.Applicant_Address__r;
        if (addr == null) {
            return out;
        }
        out.put('addressLine1',  addr.Address_Line_1__c);
        out.put('addressLine2',  addr.Address_Line_2__c);
        out.put('addressLine3',  addr.Address_Line_3__c);
        out.put('pinCode',       addr.PinCode__c);
        out.put('city',          addr.City__c);
        out.put('state',         addr.State__c);
        out.put('country',       addr.Country__c);
        out.put('email',         addr.Email__c);
        out.put('emailVerified', addr.Email_Verified__c == true);
        return out;
    }

    /** Yes/No picklist values stored on the Current Applicant_Address__c row. */
    private List<Map<String, Object>> getAddressVerificationConfig(Document_CheckList__c row) {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        Applicant_Address__c addr = row != null ? row.Applicant_Address__r : null;
        String permanent = addr != null ? addr.Is_Current_Address_Same_As_Permanent__c : null;
        String office    = addr != null ? addr.Is_Office_Address_Same_As_Current__c    : null;
        fields.add(fieldEntry('isCurrentAddrSameAsPermanent', permanent));
        fields.add(fieldEntry('isOfficeAddrSameAsCurrent',    office));
        return fields;
    }

    /** Section 6 — Director Declaration. Persisted on Applicant__c. */
    private List<Map<String, Object>> getDirectorDeclarationConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        String director = cachedApplicant != null
            ? stringValue(cachedApplicant.get('Is_Applicant_Relative_Of_Director__c'))
            : null;
        String officer = cachedApplicant != null
            ? stringValue(cachedApplicant.get('Is_Applicant_Relative_Of_Senior_Officer__c'))
            : null;
        fields.add(fieldEntry('isDirectorDeclaration',   director));
        fields.add(fieldEntry('isSeniorOfficerRelative', officer));
        return fields;
    }

    /** Section 7 — PEP screening. Persisted on Applicant__c. */
    private List<Map<String, Object>> getPepScreeningConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        String pep = cachedApplicant != null
            ? stringValue(cachedApplicant.get('Are_you_a_Politically_Exposed_Person__c'))
            : null;
        fields.add(fieldEntry('isPep', pep));
        return fields;
    }

    /** Section 8 — Cross-Sell Account. Persisted on Applicant__c. */
    private List<Map<String, Object>> getBankAccountCheckConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        String hasAcct = cachedApplicant != null
            ? stringValue(cachedApplicant.get('Has_Bank_Account__c'))
            : null;
        String interested = cachedApplicant != null
            ? stringValue(cachedApplicant.get('Interested_In_Opening_Savings_Account__c'))
            : null;
        String bankAccountNo = cachedApplicant != null
            ? stringValue(cachedApplicant.get('Bank_Account_No__c'))
            : null;
        fields.add(fieldEntry('isBankAccountCheck',   hasAcct));
        fields.add(fieldEntry('isOpenSavingsAccount', interested));
        fields.add(fieldEntry('bankAccountNo',        bankAccountNo));
        return fields;
    }

    /**
     * Section 8 — Cross-Sell ETB CASA accounts derived from the
     * Applicant__c.ETB_CASA_Details__c JSON payload stamped by
     * ETBCASAHandlerAPI during the Basic Details NEXT click.
     *
     * Returns a map shaped as:
     *   {
     *     "accounts": [ { ...9 fields per account... }, ... ],
     *     "selectedAccountNo": "<Applicant.Bank_Account_No__c>"
     *   }
     *
     * The LWC reads `accounts` to render the picker tiles and `selectedAccountNo`
     * to highlight the currently selected tile on reload.
     */
    private Map<String, Object> getCrossSellAccountsConfig() {
        Map<String, Object> payload = new Map<String, Object>{
            'accounts'          => new List<Object>(),
            'selectedAccountNo' => null
        };
        if (cachedApplicant == null) return payload;

        String rawJson = stringValue(cachedApplicant.get('ETB_CASA_Details__c'));
        if (String.isNotBlank(rawJson)) {
            try {
                Object parsed = JSON.deserializeUntyped(rawJson);
                if (parsed instanceof List<Object>) {
                    payload.put('accounts', (List<Object>) parsed);
                }
            } catch (Exception ignored) {
                // Malformed payload — leave empty so the UI hides the picker.
            }
        }
        payload.put('selectedAccountNo', stringValue(cachedApplicant.get('Bank_Account_No__c')));
        return payload;
    }

    /**
     * Section 9 — Customer Image. Returns the checklist row id (pre-seeded
     * by Basic Details) and the currently-attached file map so the LWC
     * can render the file-upload preview on reload.
     */
    private Map<String, Object> getCustomerImageCaptureConfig(
        Document_CheckList__c row,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        Map<String, Object> out = new Map<String, Object>{
            'checklistRecordId' => null,
            'customerImageFile' => null
        };
        if (row == null) {
            return out;
        }
        out.put('checklistRecordId', row.Id);
        Map<String, Object> files = filesByChecklist != null ? filesByChecklist.get(row.Id) : null;
        if (files != null && files.get('fullFile') != null) {
            out.put('customerImageFile', files.get('fullFile'));
        }
        return out;
    }

    private class EntityPageChecklistLoadResult {
        public Map<String, Document_CheckList__c> buckets { get; private set; }
        public List<Document_CheckList__c> additionalRows { get; private set; }
        public List<Document_CheckList__c> darpanRows { get; private set; }

        public EntityPageChecklistLoadResult() {
            buckets = new Map<String, Document_CheckList__c>();
            additionalRows = new List<Document_CheckList__c>();
            darpanRows = new List<Document_CheckList__c>();
        }
    }

    /**
     * Returns CIN, GST, Registered, and Office checklist rows.
     * Query-only — rows are created when the user initiates an upload.
     * Single SOQL covers all buckets.
     */
    private EntityPageChecklistLoadResult loadEntityPageChecklistData(Id recordId, Id applicantId) {
        EntityPageChecklistLoadResult loadResult = new EntityPageChecklistLoadResult();
        if (applicantId == null) {
            return loadResult;
        }
        Set<String> constitutionDocTypes = buildEntityConstitutionDocumentTypes(recordId);
        Set<String> extraDocTypes = new Set<String>{ DOC_TYPE_CIN, DOC_TYPE_GST };
        extraDocTypes.addAll(constitutionDocTypes);
        extraDocTypes.addAll(DARPAN_DOC_TYPES);
        extraDocTypes.add(DOC_NAME_ELECTRICITY_BILL);
        for (Document_CheckList__c row : queryChecklistRows(
                applicantId,
                new Set<String>{ ADDRESS_TYPE_REGISTERED, ADDRESS_TYPE_OFFICE },
                extraDocTypes)) {
            String bucketKey = resolveEntityPageBucketKey(row, constitutionDocTypes);
            if (BUCKET_ENTITY_ADDITIONAL.equals(bucketKey)) {
                loadResult.additionalRows.add(row);
            } else if (BUCKET_ENTITY_DARPAN.equals(bucketKey)) {
                loadResult.darpanRows.add(row);
            } else if (bucketKey != null) {
                Document_CheckList__c existing = loadResult.buckets.get(bucketKey);
                if (existing == null || isMorePopulatedChecklistRow(row, existing)) {
                    loadResult.buckets.put(bucketKey, row);
                }
            }
        }
        return loadResult;
    }

    /**
     * Loads Non_Individual_Constitution__mdt for the applicant entity code and
     * application product type. Drives CIN/GST mandatory flags and document lists.
     */
    private Map<String, Object> loadEntityConstitutionConfig(Id recordId) {
        Map<String, Object> out = new Map<String, Object>{
            'cinRequired'         => false,
            'gstRequired'         => false,
            'requiredDocuments'   => new List<String>(),
            'adhocDocuments'      => new List<String>(),
            'adhocDocumentCount'  => 0
        };
        if (cachedApplicant == null) {
            return out;
        }
        String entityCodeRaw = stringValue(cachedApplicant.get('Entity_Type__c'));
        if (String.isBlank(entityCodeRaw)) {
            return out;
        }
        Decimal entityCode;
        try {
            entityCode = Decimal.valueOf(entityCodeRaw.trim());
        } catch (Exception ex) {
            return out;
        }

        String productType = resolveApplicationProductType(recordId);
        if (String.isBlank(productType)) {
            return out;
        }

        List<Non_Individual_Constitution__mdt> rows = [
            SELECT Required_Documents__c, Adhoc_Documents__c, Adhoc_Document_Count__c
            FROM Non_Individual_Constitution__mdt
            WHERE Entity_Code__c = :entityCode
              AND Product_Type__c = :productType
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return out;
        }

        Non_Individual_Constitution__mdt configRow = rows[0];
        List<String> requiredDocs = new List<String>();
        if (String.isNotBlank(configRow.Required_Documents__c)) {
            for (String token : configRow.Required_Documents__c.split(',')) {
                String trimmed = token != null ? token.trim() : null;
                if (String.isNotBlank(trimmed)) {
                    requiredDocs.add(trimmed);
                }
            }
        }
        List<String> adhocDocs = new List<String>();
        if (String.isNotBlank(configRow.Adhoc_Documents__c)) {
            for (String token : configRow.Adhoc_Documents__c.split(',')) {
                String trimmed = token != null ? token.trim() : null;
                if (String.isNotBlank(trimmed)) {
                    adhocDocs.add(trimmed);
                }
            }
        }
        out.put('requiredDocuments', requiredDocs);
        out.put('adhocDocuments', adhocDocs);
        out.put('adhocDocumentCount', configRow.Adhoc_Document_Count__c != null
            ? configRow.Adhoc_Document_Count__c.intValue()
            : 0);
        out.put('cinRequired', requiredDocs.contains(DOC_NAME_CIN_CERTIFICATE));
        out.put('gstRequired', requiredDocs.contains(DOC_NAME_GST_CERTIFICATE));
        return out;
    }

    private Set<String> buildEntityConstitutionDocumentTypes(Id recordId) {
        Set<String> docTypes = new Set<String>();
        Map<String, Object> constitution = loadEntityConstitutionConfig(recordId);
        addDocumentNamesToSet(docTypes, (List<String>) constitution.get('requiredDocuments'));
        addDocumentNamesToSet(docTypes, (List<String>) constitution.get('adhocDocuments'));
        return docTypes;
    }

    private static String normalizeEntityCode(Object rawValue) {
        String raw = stringValue(rawValue);
        if (String.isBlank(raw)) {
            return '';
        }
        String trimmed = raw.trim();
        if (!trimmed.contains('.')) {
            return trimmed;
        }
        try {
            Decimal parsed = Decimal.valueOf(trimmed);
            if (parsed == null) {
                return trimmed;
            }
            return String.valueOf(parsed.setScale(0));
        } catch (Exception ex) {
            return trimmed;
        }
    }

    private Boolean isDarpanApplicableForCurrentApplicant() {
        String entityCode = normalizeEntityCode(cachedApplicant != null ? cachedApplicant.get('Entity_Type__c') : null);
        return isDarpanApplicableForEntityCode(entityCode);
    }

    private static Boolean isDarpanApplicableForEntityCode(String normalizedEntityCode) {
        return DARPAN_ENTITY_CODES.contains(String.isNotBlank(normalizedEntityCode) ? normalizedEntityCode.trim() : '');
    }

    private Set<String> extendEntityQueryableDocumentTypes(Set<String> constitutionDocTypes) {
        Set<String> docTypes = constitutionDocTypes != null
            ? new Set<String>(constitutionDocTypes)
            : new Set<String>();
        docTypes.add(DOC_NAME_ELECTRICITY_BILL);
        return docTypes;
    }

    private static void addDocumentNamesToSet(Set<String> target, List<String> names) {
        if (target == null || names == null) {
            return;
        }
        for (String name : names) {
            if (String.isNotBlank(name)) {
                target.add(name.trim());
            }
        }
    }

    // ───────────────────────────────────────────────────────────────────────
    // Document detection / tick / validation delegate to the reusable
    // MandatoryDocumentsService (Document_Manager__mdt dictionary).
    //
    // ───────────────────────────────────────────────────────────────────────
    // Step_Module key into the Document_Manager__mdt dictionary used for this
    // screen's document detection / tick / validation.
    private static final String DOC_MODULE_KYC = 'KYC Details';

    private String resolveApplicationProductType(Id recordId) {
        if (recordId == null) {
            return null;
        }
        List<Application__c> apps = [
            SELECT Product__c
            FROM Application__c
            WHERE Id = :recordId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (apps.isEmpty() || String.isBlank(apps[0].Product__c)) {
            return null;
        }
        String normalizedProduct = apps[0].Product__c.trim().toUpperCase();
        if (normalizedProduct == '4W'
            || normalizedProduct == 'PV'
            || normalizedProduct == 'PASSENGER VEHICLE'
            || normalizedProduct == 'PASSENGER VEHICLES'
            || normalizedProduct == 'PASSENGER VEHICLES (PV)'
            || normalizedProduct == 'FOUR WHEELER'
            || normalizedProduct == 'FOUR WHEELERS') {
            return 'PV';
        }
        if (normalizedProduct == 'CV'
            || normalizedProduct == 'COMMERCIAL VEHICLE'
            || normalizedProduct == 'COMMERCIAL VEHICLES') {
            return 'CV';
        }
        return normalizedProduct;
    }

    private Map<String, Object> evaluateEntityMandatoryDocuments(
        Map<String, Object> constitution,
        Document_CheckList__c cinRow,
        Document_CheckList__c gstRow,
        Document_CheckList__c panRow,
        Document_CheckList__c registeredRow,
        Document_CheckList__c officeRow,
        List<Document_CheckList__c> additionalRows,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        List<String> requiredDocs = constitution != null
            ? (List<String>) constitution.get('requiredDocuments')
            : new List<String>();
        List<String> adhocDocs = constitution != null
            ? (List<String>) constitution.get('adhocDocuments')
            : new List<String>();
        Integer adhocMin = constitution != null && constitution.containsKey('adhocDocumentCount')
            ? (Integer) constitution.get('adhocDocumentCount')
            : 0;
        if (requiredDocs == null) {
            requiredDocs = new List<String>();
        }
        if (adhocDocs == null) {
            adhocDocs = new List<String>();
        }
        if (adhocMin == null) {
            adhocMin = 0;
        }

        // Legacy name set still surfaced to the LWC for upload tracking.
        Set<String> uploadedTypes = collectUploadedEntityDocumentTypes(
            cinRow, gstRow, panRow, registeredRow, officeRow, additionalRows, filesByChecklist
        );

        // Rows that count as collected: must have a file. CIN additionally
        // requires its KYC number, so a file-only CIN row is intentionally
        // excluded; PAN is captured at Basic Details and forced collected below.
        List<Document_CheckList__c> rowsWithFiles = new List<Document_CheckList__c>();
        if (hasChecklistUploadedFile(cinRow, filesByChecklist) && hasCinKycNumber(cinRow)) {
            rowsWithFiles.add(cinRow);
        }
        for (Document_CheckList__c row : new List<Document_CheckList__c>{
                gstRow, panRow, registeredRow, officeRow }) {
            if (hasChecklistUploadedFile(row, filesByChecklist)) {
                rowsWithFiles.add(row);
            }
        }
        if (additionalRows != null) {
            for (Document_CheckList__c row : additionalRows) {
                if (hasChecklistUploadedFile(row, filesByChecklist)) {
                    rowsWithFiles.add(row);
                }
            }
        }

        Set<String> uploadedTokens =
            MandatoryDocumentsService.buildUploadedTokens(DOC_MODULE_KYC, rowsWithFiles);
        MandatoryDocumentsService.EvalResult eval = MandatoryDocumentsService.evaluate(
            DOC_MODULE_KYC,
            requiredDocs,
            adhocDocs,
            adhocMin,
            uploadedTokens,
            new Set<String>{ DOC_TYPE_PAN }
        );

        return new Map<String, Object>{
            'uploadedDocumentTypes'      => new List<String>(uploadedTypes),
            'missingRequiredDocuments'   => eval.missingRequiredDocuments,
            'adhocDocumentsRemaining'    => eval.adhocDocumentsRemaining,
            'adhocDocumentsHits'         => eval.adhocDocumentsHits,
            'adhocGroupSatisfied'        => eval.adhocGroupSatisfied,
            'requiredDocItems'           => eval.requiredDocItems,
            'adhocDocItems'              => eval.adhocDocItems,
            'documentsComplete'          => eval.documentsComplete,
            'validationMessage'          => buildMandatoryDocumentsMessage(
                                                eval.missingRequiredDocuments, eval.adhocDocumentsRemaining)
        };
    }

    private Map<String, Object> inferDarpanContext(
        Map<String, Object> rawContext,
        List<Document_CheckList__c> darpanRows
    ) {
        Map<String, Object> context = new Map<String, Object>();
        Boolean applicantNpo = cachedApplicant != null
            ? (Boolean) cachedApplicant.get('NPO__c')
            : null;
        Boolean applicantDeferral = cachedApplicant != null
            ? (Boolean) cachedApplicant.get('Deferral_Approval__c')
            : null;
        String status = applicantNpo == true ? DARPAN_STATUS_NPO : null;
        if (rawContext != null && rawContext.containsKey('npoStatus')) {
            String requestedStatus = stringValue(rawContext.get('npoStatus'));
            if (DARPAN_STATUS_NPO.equalsIgnoreCase(requestedStatus)) {
                status = DARPAN_STATUS_NPO;
            } else if (DARPAN_STATUS_NOT_NPO.equalsIgnoreCase(requestedStatus)) {
                status = DARPAN_STATUS_NOT_NPO;
            } else {
                status = String.isNotBlank(requestedStatus) ? requestedStatus.trim() : null;
            }
        }
        Boolean deferralApproval = applicantDeferral == true;
        if (rawContext != null && rawContext.containsKey('deferralApproval')) {
            deferralApproval = booleanValue(rawContext.get('deferralApproval'));
        }

        Boolean hasDeferralDoc = false;
        Boolean hasDarpanCertificate = false;
        Boolean hasCustomerDeclaration = false;
        if (darpanRows != null) {
            for (Document_CheckList__c row : darpanRows) {
                String docType = String.isNotBlank(row.Document_Type__c) ? row.Document_Type__c.trim() : null;
                if (DOC_NAME_DARPAN_DEFERRAL_APPROVAL.equalsIgnoreCase(docType)
                        || DOC_NAME_DARPAN_ACK_COPY.equalsIgnoreCase(docType)) {
                    hasDeferralDoc = true;
                } else if (DOC_NAME_DARPAN_CERTIFICATE.equalsIgnoreCase(docType)) {
                    hasDarpanCertificate = true;
                } else if (DOC_NAME_DARPAN_CUSTOMER_DECLARATION.equalsIgnoreCase(docType)) {
                    hasCustomerDeclaration = true;
                }
            }
        }

        if (hasDeferralDoc || deferralApproval) {
            status = DARPAN_STATUS_NPO;
            deferralApproval = true;
        } else if (String.isBlank(status) && hasCustomerDeclaration) {
            status = DARPAN_STATUS_NOT_NPO;
        } else if (String.isBlank(status) && hasDarpanCertificate) {
            status = DARPAN_STATUS_NPO;
        }
        if (!DARPAN_STATUS_NPO.equalsIgnoreCase(status)) {
            deferralApproval = false;
        }

        String darpanId = cachedApplicant != null ? stringValue(cachedApplicant.get('Darpan_Id__c')) : null;
        if (rawContext != null && rawContext.containsKey('darpanId')) {
            darpanId = stringValue(rawContext.get('darpanId'));
        }
        DateTime registrationDate = cachedApplicant != null
            ? (DateTime) cachedApplicant.get('Darpan_Registration_Date__c')
            : null;
        if (rawContext != null && rawContext.containsKey('registrationDate')) {
            registrationDate = parseDateTimeValue(rawContext.get('registrationDate'));
        }

        context.put('npoStatus', status);
        context.put('deferralApproval', deferralApproval);
        context.put('darpanId', darpanId);
        context.put('registrationDate', registrationDate);
        return context;
    }

    private Map<String, Object> evaluateDarpanMandatoryDocuments(
        List<Document_CheckList__c> darpanRows,
        Map<String, Object> rawContext,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        Map<String, Object> context = inferDarpanContext(rawContext, darpanRows);
        String npoStatus = stringValue(context.get('npoStatus'));
        Boolean deferralApproval = context.get('deferralApproval') == true;
        String darpanId = stringValue(context.get('darpanId'));
        DateTime registrationDate = (DateTime) context.get('registrationDate');

        if (!isDarpanApplicableForCurrentApplicant()) {
            return new Map<String, Object>{
                'npoStatus' => npoStatus,
                'deferralApproval' => deferralApproval,
                'darpanId' => darpanId,
                'registrationDate' => registrationDate,
                'requiredDocItems' => new List<Object>(),
                'adhocDocItems' => new List<Object>(),
                'missingRequiredDocuments' => new List<String>(),
                'adhocGroupSatisfied' => true,
                'documentsComplete' => true,
                'validationMessage' => null
            };
        }

        List<String> requiredDocs = new List<String>();
        if (deferralApproval) {
            requiredDocs.add(DOC_NAME_DARPAN_DEFERRAL_APPROVAL);
            requiredDocs.add(DOC_NAME_DARPAN_ACK_COPY);
        } else if (DARPAN_STATUS_NPO.equalsIgnoreCase(npoStatus)) {
            requiredDocs.add(DOC_NAME_DARPAN_CERTIFICATE);
        } else if (DARPAN_STATUS_NOT_NPO.equalsIgnoreCase(npoStatus)) {
            requiredDocs.add(DOC_NAME_DARPAN_CUSTOMER_DECLARATION);
        }

        List<Document_CheckList__c> rowsWithFiles = new List<Document_CheckList__c>();
        if (darpanRows != null) {
            for (Document_CheckList__c row : darpanRows) {
                if (hasChecklistUploadedFile(row, filesByChecklist)) {
                    rowsWithFiles.add(row);
                }
            }
        }
        Set<String> uploadedTokens =
            MandatoryDocumentsService.buildUploadedTokens(DOC_MODULE_KYC, rowsWithFiles);
        MandatoryDocumentsService.EvalResult eval = MandatoryDocumentsService.evaluate(
            DOC_MODULE_KYC,
            requiredDocs,
            new List<String>(),
            0,
            uploadedTokens,
            null
        );

        String validationMessage = buildMandatoryDocumentsMessage(
            eval.missingRequiredDocuments,
            eval.adhocDocumentsRemaining
        );
        if (String.isBlank(npoStatus)) {
            validationMessage = 'Select NPO status to continue.';
        }

        Boolean documentsComplete = eval.documentsComplete;
        if (String.isBlank(npoStatus)) {
            documentsComplete = false;
        }

        return new Map<String, Object>{
            'npoStatus' => npoStatus,
            'deferralApproval' => deferralApproval,
            'darpanId' => darpanId,
            'registrationDate' => registrationDate,
            'requiredDocItems' => eval.requiredDocItems,
            'adhocDocItems' => eval.adhocDocItems,
            'missingRequiredDocuments' => eval.missingRequiredDocuments,
            'adhocGroupSatisfied' => eval.adhocGroupSatisfied,
            'documentsComplete' => documentsComplete,
            'validationMessage' => validationMessage
        };
    }

    private static Set<String> collectUploadedEntityDocumentTypes(
        Document_CheckList__c cinRow,
        Document_CheckList__c gstRow,
        Document_CheckList__c panRow,
        Document_CheckList__c registeredRow,
        Document_CheckList__c officeRow,
        List<Document_CheckList__c> additionalRows,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        Set<String> uploadedTypes = new Set<String>();
        addUploadedDocumentType(uploadedTypes, cinRow, filesByChecklist);
        addUploadedDocumentType(uploadedTypes, gstRow, filesByChecklist);
        addUploadedDocumentType(uploadedTypes, panRow, filesByChecklist);
        addUploadedDocumentType(uploadedTypes, registeredRow, filesByChecklist);
        addUploadedDocumentType(uploadedTypes, officeRow, filesByChecklist);
        if (additionalRows != null) {
            for (Document_CheckList__c row : additionalRows) {
                addUploadedDocumentType(uploadedTypes, row, filesByChecklist);
            }
        }
        if (uploadedTypes.contains(DOC_TYPE_CIN)) {
            uploadedTypes.add(DOC_NAME_CIN_CERTIFICATE);
        }
        if (uploadedTypes.contains(DOC_TYPE_GST)) {
            uploadedTypes.add(DOC_NAME_GST_CERTIFICATE);
        }
        return uploadedTypes;
    }

    private static void addUploadedDocumentType(
        Set<String> uploadedTypes,
        Document_CheckList__c row,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        if (!hasChecklistUploadedFile(row, filesByChecklist)) {
            return;
        }
        if (String.isNotBlank(row.Document_Type__c)) {
            uploadedTypes.add(row.Document_Type__c.trim());
        }
    }

    private static Boolean hasChecklistUploadedFile(
        Document_CheckList__c row,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        if (row == null) {
            return false;
        }
        if (String.isNotBlank(row.ContentVersionId__c)) {
            return true;
        }
        if (filesByChecklist == null || !filesByChecklist.containsKey(row.Id)) {
            return false;
        }
        Map<String, Object> fileMap = filesByChecklist.get(row.Id);
        return fileMap != null
            && (fileMap.containsKey('fullFile')
                || fileMap.containsKey('frontFile')
                || fileMap.containsKey('backFile'));
    }

    private static Boolean hasCinKycNumber(Document_CheckList__c cinRow) {
        if (cinRow == null || cinRow.Applicant_KYC__r == null) {
            return false;
        }
        return String.isNotBlank(cinRow.Applicant_KYC__r.KYC_No__c)
            || String.isNotBlank(cinRow.Applicant_KYC__r.Masked_KYC_No__c);
    }

    private static String buildMandatoryDocumentsMessage(
        List<String> missingRequired,
        Integer adhocRemaining
    ) {
        List<String> parts = new List<String>();
        if (missingRequired != null && !missingRequired.isEmpty()) {
            parts.add(
                'Please upload the following mandatory documents: '
                + String.join(missingRequired, ', ')
            );
        }
        if (adhocRemaining != null && adhocRemaining > 0) {
            parts.add(
                'Upload at least ' + adhocRemaining + ' more registration/activity proof document(s).'
            );
        }
        return parts.isEmpty() ? null : String.join(parts, ' ');
    }

    private Map<String, Object> loadEntityDocumentValidationContext(Id recordId, Id applicantId) {
        return loadEntityDocumentValidationContext(recordId, applicantId, null);
    }

    private Map<String, Object> loadEntityDocumentValidationContext(
        Id recordId,
        Id applicantId,
        Map<String, Object> darpanContext
    ) {
        EntityPageChecklistLoadResult entityLoad = loadEntityPageChecklistData(recordId, applicantId);
        Document_CheckList__c cinRow = entityLoad.buckets.get(DOC_TYPE_CIN);
        Document_CheckList__c gstRow = entityLoad.buckets.get(DOC_TYPE_GST);
        Document_CheckList__c panRow = entityLoad.buckets.get(BUCKET_ENTITY_PAN);
        Document_CheckList__c registeredRow = entityLoad.buckets.get(ADDRESS_TYPE_REGISTERED);
        Document_CheckList__c officeRow = entityLoad.buckets.get(ADDRESS_TYPE_OFFICE);
        List<Document_CheckList__c> additionalRows = entityLoad.additionalRows;
        List<Document_CheckList__c> darpanRows = entityLoad.darpanRows;

        Set<Id> checklistIds = new Set<Id>();
        addChecklistId(checklistIds, cinRow);
        addChecklistId(checklistIds, gstRow);
        addChecklistId(checklistIds, panRow);
        addChecklistId(checklistIds, registeredRow);
        addChecklistId(checklistIds, officeRow);
        if (additionalRows != null) {
            for (Document_CheckList__c row : additionalRows) {
                addChecklistId(checklistIds, row);
            }
        }
        if (darpanRows != null) {
            for (Document_CheckList__c row : darpanRows) {
                addChecklistId(checklistIds, row);
            }
        }

        Map<Id, Map<String, Object>> filesByChecklist = queryAddressProofFiles(checklistIds);
        seedEntityFilesFromContentVersionIds(
            filesByChecklist,
            new List<Document_CheckList__c>{ cinRow, gstRow, panRow, registeredRow, officeRow }
        );
        seedEntityFilesFromContentVersionIds(filesByChecklist, additionalRows);
        seedEntityFilesFromContentVersionIds(filesByChecklist, darpanRows);

        Map<String, Object> constitution = loadEntityConstitutionConfig(recordId);
        Map<String, Object> validation = evaluateEntityMandatoryDocuments(
            constitution,
            cinRow,
            gstRow,
            panRow,
            registeredRow,
            officeRow,
            additionalRows,
            filesByChecklist
        );
        validation.putAll(constitution);
        validation.put('darpanRows', darpanRows);
        validation.put('darpan', evaluateDarpanMandatoryDocuments(
            darpanRows,
            darpanContext,
            filesByChecklist
        ));
        return validation;
    }

    private static void addChecklistId(Set<Id> checklistIds, Document_CheckList__c row) {
        if (checklistIds != null && row != null && row.Id != null) {
            checklistIds.add(row.Id);
        }
    }

    private static String resolveEntityPageBucketKey(
        Document_CheckList__c row,
        Set<String> constitutionDocTypes
    ) {
        if (row == null) {
            return null;
        }
        if (DOC_TYPE_CIN.equals(row.Document_Type__c)) {
            return DOC_TYPE_CIN;
        }
        if (DOC_TYPE_GST.equals(row.Document_Type__c)) {
            return DOC_TYPE_GST;
        }
        if (DOC_TYPE_PAN.equals(row.Document_Type__c)) {
            return BUCKET_ENTITY_PAN;
        }
        if (ADDRESS_TYPE_REGISTERED.equals(row.Address_Type__c)
            || DOC_TYPE_REGISTERED_ADDRESS_PROOF.equals(row.Document_Type__c)) {
            return ADDRESS_TYPE_REGISTERED;
        }
        if (ADDRESS_TYPE_OFFICE.equals(row.Address_Type__c)
            || DOC_TYPE_OFFICE_ADDRESS_PROOF.equals(row.Document_Type__c)) {
            return ADDRESS_TYPE_OFFICE;
        }
        if (isEntityDarpanDocumentRow(row)) {
            return BUCKET_ENTITY_DARPAN;
        }
        if (isEntityAdditionalDocumentRow(row, constitutionDocTypes)) {
            return BUCKET_ENTITY_ADDITIONAL;
        }
        return null;
    }

    private static Boolean isEntityDarpanDocumentRow(Document_CheckList__c row) {
        if (row == null) {
            return false;
        }
        String docType = String.isNotBlank(row.Document_Type__c) ? row.Document_Type__c.trim() : null;
        if (String.isBlank(docType)) {
            return false;
        }
        return DARPAN_DOC_TYPES.contains(docType);
    }

    private static Boolean isEntityAdditionalDocumentRow(
        Document_CheckList__c row,
        Set<String> constitutionDocTypes
    ) {
        if (row == null || constitutionDocTypes == null || constitutionDocTypes.isEmpty()) {
            return false;
        }
        if (String.isNotBlank(row.Address_Type__c) || row.Applicant_Address__c != null) {
            return false;
        }
        String docType = row.Document_Type__c;
        if (DOC_TYPE_CIN.equals(docType) || DOC_TYPE_GST.equals(docType)
                || DOC_TYPE_PAN.equals(docType) || DOC_TYPE_FORM_60.equals(docType)
                || isEntityDarpanDocumentRow(row)) {
            return false;
        }
        return String.isNotBlank(docType) && constitutionDocTypes.contains(docType.trim());
    }

    private List<Object> buildEntityAdditionalDocumentsPayload(
        List<Document_CheckList__c> rows,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        List<Object> out = new List<Object>();
        if (rows == null || rows.isEmpty()) {
            return out;
        }
        for (Document_CheckList__c row : rows) {
            Map<String, Object> entry = buildEntityAdditionalDocumentPayload(row, filesByChecklist);
            if (entry != null) {
                out.add(entry);
            }
        }
        return out;
    }

    private Map<String, Object> buildEntityAdditionalDocumentPayload(
        Document_CheckList__c row,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        if (row == null) {
            return null;
        }
        Object proofFile = getSingleFileFromChecklist(row, filesByChecklist);
        if (String.isBlank(row.Document_Type__c) && proofFile == null) {
            return null;
        }
        return new Map<String, Object>{
            'checklistRecordId' => row.Id,
            'documentType'      => row.Document_Type__c,
            'proofFile'         => proofFile
        };
    }

    private Map<String, Object> buildEntityKycPayload(
        Document_CheckList__c cinRow,
        Document_CheckList__c gstRow,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        return new Map<String, Object>{
            'cinChecklistRecordId' => cinRow != null ? cinRow.Id : null,
            'cinFile'              => getSingleFileFromChecklist(cinRow, filesByChecklist),
            'cinDetails'           => buildEntityDocDetailsMap(cinRow, DOC_TYPE_CIN),
            'gstChecklistRecordId' => gstRow != null ? gstRow.Id : null,
            'gstFile'              => getSingleFileFromChecklist(gstRow, filesByChecklist),
            'gstDetails'           => buildEntityDocDetailsMap(gstRow, DOC_TYPE_GST)
        };
    }

    /**
     * Entity document detail payload for CIN / GST checklist rows.
     * Reads the linked Applicant_KYC__c snapshot. Returns null when no
     * extracted or user-entered values exist yet.
     */
    private Map<String, Object> buildEntityDocDetailsMap(Document_CheckList__c row, String docType) {
        if (row == null) {
            return null;
        }
        Applicant_KYC__c kyc = row.Applicant_KYC__r;
        Applicant_Address__c gstAddr = row.Applicant_Address__r;
        Boolean gstCertAddress = gstAddr != null
            && ADDRESS_TYPE_GST.equalsIgnoreCase(String.valueOf(gstAddr.Address_Type__c));
        String docNumber = kyc != null
            ? preferString(kyc.Masked_KYC_No__c, kyc.KYC_No__c)
            : null;

        if (DOC_TYPE_CIN.equals(docType)) {
            if (String.isBlank(docNumber)) {
                return null;
            }
            return new Map<String, Object>{
                'cinNumber' => docNumber
            };
        }

        String addr1 = preferString(
            gstCertAddress ? gstAddr.Address_Line_1__c : null,
            kyc != null ? kyc.KYC_Address_Line_1__c : null
        );
        String addr2 = preferString(
            gstCertAddress ? gstAddr.Address_Line_2__c : null,
            kyc != null ? kyc.KYC_Address_Line_2__c : null
        );
        String state = preferString(
            gstCertAddress ? gstAddr.State__c : null,
            kyc != null ? kyc.KYC_State__c : null
        );
        String district = preferString(
            gstCertAddress ? gstAddr.District__c : null,
            kyc != null ? kyc.KYC_District__c : null
        );
        String city = preferString(
            gstCertAddress ? gstAddr.City__c : null,
            kyc != null ? kyc.KYC_City__c : null
        );
        String pin = preferString(
            gstCertAddress ? gstAddr.PinCode__c : null,
            kyc != null ? kyc.KYC_Pin_Code__c : null
        );

        Boolean hasGstData = String.isNotBlank(docNumber)
            || String.isNotBlank(addr1)
            || String.isNotBlank(state)
            || String.isNotBlank(pin);
        if (!hasGstData) {
            return null;
        }

        return new Map<String, Object>{
            'gstNumber'       => docNumber,
            'kycAddressLine1' => addr1,
            'kycAddressLine2' => addr2,
            'state'           => state,
            'district'        => district,
            'city'            => city,
            'kycPinCode'      => pin
        };
    }

    private Map<String, Object> buildEntityAddressHydrationPayload(
        Document_CheckList__c registeredRow,
        Document_CheckList__c officeRow,
        Document_CheckList__c gstRow,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        Map<String, Object> out = new Map<String, Object>();
        Applicant_Address__c registeredAddr = resolveRegisteredAddressForHydration(registeredRow, gstRow);

        String gstSameAsRegistered = registeredAddr != null
            ? stringValue(registeredAddr.Is_Registered_Address_Same_As_GST__c)
            : '';
        String officeSameAsRegistered = registeredAddr != null
            ? stringValue(registeredAddr.Is_Office_Address_Same_As_Registered__c)
            : '';

        out.put('gstIsRegisteredAddress', gstSameAsRegistered);
        out.put('officeSameAsRegistered', officeSameAsRegistered);

        if (YES.equalsIgnoreCase(gstSameAsRegistered)) {
            out.put('registeredChecklistRecordId', null);
            out.put(
                'registeredAddress',
                buildEntityAddressFieldMap(
                    registeredAddr,
                    DOC_TYPE_GST,
                    getSingleFileFromChecklist(gstRow, filesByChecklist)
                )
            );
        } else if (registeredRow != null) {
            out.put('registeredChecklistRecordId', registeredRow.Id);
            out.put(
                'registeredAddress',
                buildEntityAddressFieldMapFromChecklist(registeredRow, filesByChecklist)
            );
        }

        if (YES.equalsIgnoreCase(officeSameAsRegistered)) {
            out.put('officeChecklistRecordId', null);
        } else if (officeRow != null) {
            out.put('officeChecklistRecordId', officeRow.Id);
            out.put(
                'officeAddress',
                buildEntityAddressFieldMapFromChecklist(officeRow, filesByChecklist)
            );
        }

        return out;
    }

    private Applicant_Address__c resolveRegisteredAddressForHydration(
        Document_CheckList__c registeredRow,
        Document_CheckList__c gstRow
    ) {
        if (registeredRow != null && registeredRow.Applicant_Address__r != null) {
            return registeredRow.Applicant_Address__r;
        }
        if (gstRow != null
            && gstRow.Applicant_Address__r != null
            && ADDRESS_TYPE_REGISTERED.equalsIgnoreCase(
                String.valueOf(gstRow.Applicant_Address__r.Address_Type__c)
            )) {
            return gstRow.Applicant_Address__r;
        }
        return null;
    }

    private Map<String, Object> buildEntityAddressFieldMapFromChecklist(
        Document_CheckList__c row,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        if (row == null) {
            return null;
        }
        Object proofFile = getSingleFileFromChecklist(row, filesByChecklist);
        String addressProof = toEntityAddressProofType(row.Document_Type__c);
        if (String.isBlank(addressProof)
            && proofFile != null
            && String.isNotBlank(row.Document_Type__c)
            && !DOC_TYPE_REGISTERED_ADDRESS_PROOF.equalsIgnoreCase(row.Document_Type__c)
            && !DOC_TYPE_OFFICE_ADDRESS_PROOF.equalsIgnoreCase(row.Document_Type__c)) {
            addressProof = row.Document_Type__c.trim();
        }
        Map<String, Object> payload = buildEntityAddressFieldMap(
            row.Applicant_Address__r,
            addressProof,
            proofFile
        );
        if (payload != null && String.isNotBlank(row.Document_Type__c)) {
            payload.put('storedDocumentType', row.Document_Type__c.trim());
        }
        return payload;
    }

    private Map<String, Object> buildEntityAddressFieldMap(
        Applicant_Address__c addr,
        String addressProof,
        Object proofFile
    ) {
        Boolean hasProof = String.isNotBlank(addressProof) || proofFile != null;
        Boolean hasLines = addr != null && (
            String.isNotBlank(addr.Address_Line_1__c)
            || String.isNotBlank(addr.PinCode__c)
            || String.isNotBlank(addr.State__c)
            || String.isNotBlank(addr.City__c)
        );
        if (!hasProof && !hasLines) {
            return null;
        }
        return new Map<String, Object>{
            'addressProof'    => addressProof,
            'proofFile'       => proofFile,
            'kycAddressLine1' => addr != null ? addr.Address_Line_1__c : null,
            'kycAddressLine2' => addr != null ? addr.Address_Line_2__c : null,
            'state'           => addr != null ? addr.State__c          : null,
            'district'        => addr != null ? addr.District__c       : null,
            'city'            => addr != null ? addr.City__c           : null,
            'kycPinCode'      => addr != null ? addr.PinCode__c        : null
        };
    }

    private static String toEntityAddressProofType(String storedDocType) {
        if (String.isBlank(storedDocType)) {
            return '';
        }
        String normalized = storedDocType.trim();
        if (DOC_TYPE_REGISTERED_ADDRESS_PROOF.equalsIgnoreCase(normalized)) {
            return '';
        }
        if (DOC_TYPE_OFFICE_ADDRESS_PROOF.equalsIgnoreCase(normalized)) {
            return '';
        }
        return normalized;
    }

    private Object getSingleFileFromChecklist(
        Document_CheckList__c row,
        Map<Id, Map<String, Object>> filesByChecklist
    ) {
        if (row == null || filesByChecklist == null) {
            return null;
        }
        Map<String, Object> files = filesByChecklist.get(row.Id);
        return files != null ? files.get('fullFile') : null;
    }

    /**
     * Fills fullFile on entity checklist buckets from ContentVersionId__c when
     * ContentDocumentLink hydration did not produce a file map.
     */
    private void seedEntityFilesFromContentVersionIds(
        Map<Id, Map<String, Object>> filesByChecklist,
        List<Document_CheckList__c> rows
    ) {
        if (filesByChecklist == null || rows == null || rows.isEmpty()) {
            return;
        }
        Set<Id> versionIds = new Set<Id>();
        for (Document_CheckList__c row : rows) {
            if (row == null || row.ContentVersionId__c == null) {
                continue;
            }
            Map<String, Object> bucket = filesByChecklist.get(row.Id);
            if (bucket != null && bucket.get('fullFile') != null) {
                continue;
            }
            Id versionId = parseId(row.ContentVersionId__c);
            if (versionId != null) {
                versionIds.add(versionId);
            }
        }
        if (versionIds.isEmpty()) {
            return;
        }
        Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>([
            SELECT Id, Title, FileExtension, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIds
            WITH SECURITY_ENFORCED
        ]);
        for (Document_CheckList__c row : rows) {
            if (row == null || row.ContentVersionId__c == null) {
                continue;
            }
            Map<String, Object> bucket = filesByChecklist.get(row.Id);
            if (bucket == null) {
                bucket = new Map<String, Object>{
                    'frontFile' => null, 'backFile' => null, 'fullFile' => null
                };
                filesByChecklist.put(row.Id, bucket);
            }
            if (bucket.get('fullFile') != null) {
                continue;
            }
            ContentVersion version = versionsById.get(parseId(row.ContentVersionId__c));
            if (version == null) {
                continue;
            }
            bucket.put('fullFile', buildRestoredFileMapFromContentVersion(version));
        }
    }

    private Map<String, Object> buildRestoredFileMapFromContentVersion(ContentVersion version) {
        String title = String.valueOf(version.Title);
        String extension = String.valueOf(version.FileExtension);
        String fileName = String.isNotBlank(title)
            ? (String.isNotBlank(extension) ? title + '.' + extension : title)
            : '';
        return new Map<String, Object>{
            'fileName'          => fileName,
            'contentDocumentId' => version.ContentDocumentId,
            'contentVersionId'  => version.Id
        };
    }

    private Document_CheckList__c insertEntityDocChecklist(Id recordId, Id applicantId, String docType) {
        Applicant__c applicant = loadApplicantForName(applicantId);
        Id applicationId = recordId != null
            ? recordId
            : (applicant != null ? applicant.Application__c : null);
        Document_CheckList__c row = new Document_CheckList__c(
            Applicant__c       = applicantId,
            Application__c     = applicationId,
            Document_Type__c   = docType,
            Document_Master_Key__c = MandatoryDocumentsService.masterKeyForType(DOC_MODULE_KYC, docType),
            Is_Active__c       = true,
            Name               = KYCInfoController.buildChecklistName(applicant, docType)
        );
        if (cachedApplicant != null && String.isBlank(row.Applicant_Type__c)) {
            String applicantPersona = (String) cachedApplicant.get('Applicant_Type__c');
            if (String.isNotBlank(applicantPersona)) {
                row.Applicant_Type__c = applicantPersona;
            }
        }
        insert row;
        return row;
    }

    private Map<String, Object> createEntityChecklistInternal(Map<String, Object> args, String docType) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id recordId = parseId(args.get('recordId'));
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }
            loadCachedData(recordId, args);
            Id applicantId = cachedApplicant != null ? (Id) cachedApplicant.get('Id') : null;
            if (applicantId == null) {
                throw new AuraHandledException('applicantId is required.');
            }
            List<Document_CheckList__c> rows = queryChecklistRows(
                applicantId,
                new Set<String>(),
                new Set<String>{ docType }
            );
            Document_CheckList__c row = rows.isEmpty()
                ? insertEntityDocChecklist(recordId, applicantId, docType)
                : rows[0];
            result.put('isSuccess', true);
            result.put('checklistId', row.Id);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'KYCDetailsController.createEntityChecklist: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Aadhaar eKYC state derived from the row's Applicant_KYC__c. Returns
     * URL, verification flag, link-sent flag, 72hr expiry flag, consent
     * timestamp, verification method, and the kyc record id.
     */
    private Map<String, Object> getAadhaarVerifyState(Document_CheckList__c row) {
        Map<String, Object> out = new Map<String, Object>{
            'kycUrl'              => null,
            'linkSent'            => false,
            'aadhaarVerified'     => false,
            'consentReceivedDate' => null,
            'linkExpired'         => false,
            'verificationMethod'  => null,
            'applicantKycId'      => null
        };
        Applicant_KYC__c kyc = row != null ? row.Applicant_KYC__r : null;
        if (kyc == null) {
            return out;
        }

        Boolean verified    = kyc.Aadhar_Verified__c == true;
        Boolean linkSent    = kyc.AadhaareKYCLinkSent__c == true;
        Boolean linkExpired = !verified
            && linkSent
            && kyc.AadhaareKYCLinkSent_Date__c != null
            && kyc.AadhaareKYCLinkSent_Date__c.addHours(72) < System.now();

        out.put('applicantKycId',      kyc.Id);
        out.put('verificationMethod',  kyc.KYC_Verification_Method__c);
        out.put('aadhaarVerified',     verified);
        out.put('consentReceivedDate', kyc.AadhaarConsentReceived__c);
        out.put('linkSent',            linkSent && !linkExpired);
        out.put('linkExpired',         linkExpired);
        out.put('kycUrl',              linkExpired ? null : kyc.KYC_URL__c);
        return out;
    }

    // =========================================================================
    // Save
    // =========================================================================

    private Map<String, Object> saveKYCInfoPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        Savepoint sp = Database.setSavepoint();
        try {
            Id recordId = parseId(args.get('recordId'));
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }
            loadCachedData(recordId, args);

            if (cachedApplicant == null) {
                throw new AuraHandledException('Applicant not found for the supplied recordId / applicantId.');
            }
            String customerType = stringValue(cachedApplicant.get('Type__c'));
            if (CUSTOMER_TYPE_NON_INDIVIDUAL.equalsIgnoreCase(customerType)) {
                return saveNonIndividualKycPageDataInternal(args);
            }

            Id applicantId = (Id) cachedApplicant.get('Id');

            // CKYC ID (optional)
            Object ckycRaw = args.get('ckycId');
            if (ckycRaw != null) {
                String ckycString = String.valueOf(ckycRaw).trim();
                if (String.isBlank(ckycString)) {
                    cachedApplicant.put('CKYC_ID__c', null);
                } else {
                    try {
                        cachedApplicant.put('CKYC_ID__c', Decimal.valueOf(ckycString));
                    } catch (Exception ignore) {
                    }
                }
            }

            // Sections 6 / 7 / 8 — Yes/No answers persisted on Applicant__c.
            applyApplicantAnswerIfPresent(args, 'isDirectorDeclaration',   'Is_Applicant_Relative_Of_Director__c');
            applyApplicantAnswerIfPresent(args, 'isSeniorOfficerRelative', 'Is_Applicant_Relative_Of_Senior_Officer__c');
            applyApplicantAnswerIfPresent(args, 'isPep',                   'Are_you_a_Politically_Exposed_Person__c');
            applyApplicantAnswerIfPresent(args, 'isBankAccountCheck',      'Has_Bank_Account__c');
            applyApplicantAnswerIfPresent(args, 'isOpenSavingsAccount',    'Interested_In_Opening_Savings_Account__c');
            // Cross-Sell repayment account selection from the ETB CASA picker.
            applyApplicantAnswerIfPresent(args, 'bankAccountNo',           'Bank_Account_No__c');

            // Current Address always persists on NEXT.
            Document_CheckList__c currentRow = getOrCreateAddressChecklist(recordId, applicantId, ADDRESS_TYPE_CURRENT);
            saveAddressDocumentToChecklist(currentRow, args, ADDRESS_TYPE_CURRENT);

            String sameAsPermanent = stringValue(args.get('isCurrentAddrSameAsPermanent'));
            String sameAsOffice    = stringValue(args.get('isOfficeAddrSameAsCurrent'));

            // Permanent persists only when the user kept the panel open
            // (isCurrentAddrSameAsPermanent != Yes). When the final answer is
            // Yes, any prior Permanent records are wiped on this NEXT click.
            if (!YES.equalsIgnoreCase(sameAsPermanent)) {
                Map<String, Object> permArgs = asMap(args.get('permanent'));
                if (!permArgs.isEmpty()) {
                    Document_CheckList__c permanentRow = getOrCreateAddressChecklist(recordId, applicantId, ADDRESS_TYPE_PERMANENT);
                    saveAddressDocumentToChecklist(permanentRow, permArgs, ADDRESS_TYPE_PERMANENT);
                }
            } else {
                deleteAddressBucket(applicantId, ADDRESS_TYPE_PERMANENT);
            }

            // Office Address persists only for Earning applicants whose final
            // answer is "Office Address is not the same as Current". When the
            // answer is "Yes" or the applicant is Non-Earning, any prior
            // Office records for this applicant are wiped on this NEXT click.
            String incomeCategory = stringValue(cachedApplicant.get('Income_Category__c'));
            Boolean officeApplicable = String.isNotBlank(incomeCategory)
                && !INCOME_CATEGORY_NON_EARNING.equalsIgnoreCase(incomeCategory);

            if (officeApplicable && !YES.equalsIgnoreCase(sameAsOffice)) {
                Map<String, Object> officeArgs = asMap(args.get('officeAddress'));
                if (!officeArgs.isEmpty()) {
                    Document_CheckList__c officeRow = getOrCreateAddressChecklist(recordId, applicantId, ADDRESS_TYPE_OFFICE);
                    saveOfficeAddressToChecklist(officeRow, officeArgs);
                }
            } else {
                deleteAddressBucket(applicantId, ADDRESS_TYPE_OFFICE);
            }

            // Stamp stage completion so the journey can advance and so the
            // page re-loads in read-only mode after a successful NEXT click.
            cachedApplicant.put('Current_Loan_Stage_Complete__c', STAGE_KYC_DETAILS);

            update cachedApplicant;

            result.put('isSuccess', true);
            result.put('applicantId', applicantId);
            result.put('checklistId', currentRow != null ? currentRow.Id : null);
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            result.put('message', 'KYCDetailsController.saveKYCInfoPageData: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Persists Non-Individual entity KYC on NEXT: GST KYC address snapshot,
     * Registered / GST Certificate / Office Applicant_Address__c rows, proof
     * checklists, and same-as flags on the Registered address row.
     */
    private Map<String, Object> saveNonIndividualKycPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        Savepoint sp = Database.setSavepoint();
        try {
            Id recordId = parseId(args.get('recordId'));
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }
            loadCachedData(recordId, args);
            if (cachedApplicant == null) {
                throw new AuraHandledException('Applicant not found for the supplied recordId / applicantId.');
            }
            Id applicantId = (Id) cachedApplicant.get('Id');
            Boolean darpanInputProvided = args != null && args.containsKey('darpan');
            Map<String, Object> darpanArgs = darpanInputProvided
                ? asMap(args.get('darpan'))
                : new Map<String, Object>();

            Map<String, Object> documentValidation = loadEntityDocumentValidationContext(
                recordId,
                applicantId,
                darpanInputProvided ? darpanArgs : null
            );
            if (documentValidation.get('documentsComplete') != true) {
                result.put('message', (String) documentValidation.get('validationMessage'));
                result.put('validationMessage', documentValidation.get('validationMessage'));
                result.put('missingRequiredDocuments', documentValidation.get('missingRequiredDocuments'));
                result.put('adhocDocumentsRemaining', documentValidation.get('adhocDocumentsRemaining'));
                return result;
            }
            Map<String, Object> darpanValidation = (Map<String, Object>) documentValidation.get('darpan');
            if (darpanInputProvided && darpanValidation != null
                    && darpanValidation.get('documentsComplete') == false) {
                result.put('darpan', darpanValidation);
                result.put('message', darpanValidation.get('validationMessage'));
                return result;
            }

            String gstSameAsRegistered     = stringValue(args.get('gstIsRegisteredAddress'));
            String officeSameAsRegistered  = stringValue(args.get('officeSameAsRegistered'));
            Map<String, Object> gstArgs        = asMap(args.get('gst'));
            Map<String, Object> registeredArgs = asMap(args.get('registered'));
            Map<String, Object> officeArgs     = asMap(args.get('office'));

            Document_CheckList__c gstRow = findEntityDocumentChecklistRow(applicantId, DOC_TYPE_GST);
            persistGstKycAddressOnChecklist(gstRow, gstArgs);

            if (YES.equalsIgnoreCase(gstSameAsRegistered)) {
                deleteAddressBucket(applicantId, ADDRESS_TYPE_REGISTERED);
                deleteApplicantAddressesByType(applicantId, ADDRESS_TYPE_GST);

                Applicant_Address__c registeredAddr = resolveApplicantAddressForSave(
                    null, applicantId, ADDRESS_TYPE_REGISTERED
                );
                mapEntityAddressPayloadToApplicantAddress(registeredAddr, gstArgs);
                registeredAddr.Address_Type__c = ADDRESS_TYPE_REGISTERED;
                stampEntitySameAsFlags(registeredAddr, gstSameAsRegistered, officeSameAsRegistered);
                upsertEntityApplicantAddress(registeredAddr);
                linkEntityChecklistAddress(gstRow, registeredAddr.Id);
            } else {
                Applicant_Address__c gstCertAddr = resolveApplicantAddressForSave(
                    null, applicantId, ADDRESS_TYPE_GST
                );
                mapEntityAddressPayloadToApplicantAddress(gstCertAddr, gstArgs);
                gstCertAddr.Address_Type__c = ADDRESS_TYPE_GST;
                upsertEntityApplicantAddress(gstCertAddr);
                linkEntityChecklistAddress(gstRow, gstCertAddr.Id);

                Document_CheckList__c registeredRow = getOrCreateAddressChecklist(
                    recordId, applicantId, ADDRESS_TYPE_REGISTERED
                );
                saveEntityAddressBucket(
                    registeredRow,
                    registeredArgs,
                    ADDRESS_TYPE_REGISTERED,
                    DOC_TYPE_REGISTERED_ADDRESS_PROOF,
                    gstSameAsRegistered,
                    officeSameAsRegistered
                );
            }

            if (YES.equalsIgnoreCase(officeSameAsRegistered)) {
                deleteAddressBucket(applicantId, ADDRESS_TYPE_OFFICE);
            } else if (String.isNotBlank(officeSameAsRegistered)) {
                Document_CheckList__c officeRow = getOrCreateAddressChecklist(
                    recordId, applicantId, ADDRESS_TYPE_OFFICE
                );
                saveEntityAddressBucket(
                    officeRow,
                    officeArgs,
                    ADDRESS_TYPE_OFFICE,
                    DOC_TYPE_OFFICE_ADDRESS_PROOF
                );
            }

            persistEntityAdditionalDocuments(
                recordId,
                applicantId,
                asObjectList(args.get('additionalDocuments'))
            );
            if (darpanInputProvided) {
                persistApplicantDarpanFields(darpanArgs);
                persistEntityDarpanDocuments(
                    recordId,
                    applicantId,
                    asObjectList(darpanArgs.get('documents')),
                    (List<Document_CheckList__c>) documentValidation.get('darpanRows')
                );
            }

            cachedApplicant.put('Current_Loan_Stage_Complete__c', STAGE_KYC_DETAILS);
            cachedApplicant.put('Loan_Stage__c', STAGE_DEDUPE_AND_ELIGIBILITY);
            update cachedApplicant;

            result.put('isSuccess', true);
            result.put('applicantId', applicantId);
            if (darpanValidation != null) {
                result.put('darpan', darpanValidation);
            }
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            result.put('message', 'KYCDetailsController.saveNonIndividualKycPageData: ' + e.getMessage());
        }
        return result;
    }

    private Document_CheckList__c findEntityDocumentChecklistRow(Id applicantId, String docType) {
        if (applicantId == null || String.isBlank(docType)) {
            return null;
        }
        Document_CheckList__c best = null;
        for (Document_CheckList__c row : queryChecklistRows(
                applicantId,
                new Set<String>(),
                new Set<String>{ docType })) {
            if (!docType.equalsIgnoreCase(row.Document_Type__c)) {
                continue;
            }
            if (best == null || isMorePopulatedChecklistRow(row, best)) {
                best = row;
            }
        }
        return best;
    }

    private void persistGstKycAddressOnChecklist(Document_CheckList__c gstRow, Map<String, Object> gstArgs) {
        if (gstRow == null || cachedApplicant == null || gstArgs.isEmpty()) {
            return;
        }
        Id applicantId = (Id) cachedApplicant.get('Id');
        Applicant_KYC__c kyc = resolveNonIndividualApplicantKyc(gstRow.Applicant_KYC__c, applicantId);

        String addr1 = stringValue(gstArgs.get('kycAddressLine1'));
        String addr2 = stringValue(gstArgs.get('kycAddressLine2'));
        String state = stringValue(gstArgs.get('state'));
        String district = stringValue(gstArgs.get('district'));
        String city = stringValue(gstArgs.get('city'));
        String pin = stringValue(gstArgs.get('kycPinCode'));

        kyc.KYC_Address_Line_1__c = String.isNotBlank(addr1) ? addr1 : null;
        kyc.KYC_Address_Line_2__c = String.isNotBlank(addr2) ? addr2 : null;
        kyc.KYC_State__c          = String.isNotBlank(state) ? state : kyc.KYC_State__c;
        kyc.KYC_District__c       = String.isNotBlank(district) ? district : null;
        kyc.KYC_City__c           = String.isNotBlank(city) ? city : null;
        kyc.KYC_Pin_Code__c       = String.isNotBlank(pin) ? pin : null;

        upsert kyc;
        if (gstRow.Applicant_KYC__c == null) {
            gstRow.Applicant_KYC__c = kyc.Id;
            update gstRow;
        }
    }

    private void saveEntityAddressBucket(
        Document_CheckList__c row,
        Map<String, Object> args,
        String addressType,
        String fallbackDocType
    ) {
        saveEntityAddressBucket(row, args, addressType, fallbackDocType, null, null);
    }

    private void saveEntityAddressBucket(
        Document_CheckList__c row,
        Map<String, Object> args,
        String addressType,
        String fallbackDocType,
        String gstSameAsRegistered,
        String officeSameAsRegistered
    ) {
        if (row == null || cachedApplicant == null) {
            return;
        }

        String proofDocType = stringValue(args.get('addressProof'));
        row.Document_Type__c = String.isNotBlank(proofDocType) ? proofDocType : fallbackDocType;
        row.Address_Type__c  = addressType;
        row.Is_Active__c     = true;
        row.Attached_File_Side__c = SIDE_MODE_FULL;

        if (String.isBlank(row.Applicant_Type__c)) {
            String applicantPersona = (String) cachedApplicant.get('Applicant_Type__c');
            if (String.isNotBlank(applicantPersona)) {
                row.Applicant_Type__c = applicantPersona;
            }
        }

        Map<String, Object> proofFile = asMap(args.get('proofFile'));
        String contentVersionId = stringValue(proofFile.get('contentVersionId'));
        if (String.isNotBlank(contentVersionId)) {
            row.ContentVersionId__c = contentVersionId;
            stampContentVersionSide(contentVersionId, SIDE_FULL);
        }

        row.Name = KYCInfoController.buildChecklistName(
            loadApplicantForName((Id) row.Applicant__c),
            row.Document_Type__c
        );

        Id applicantId = (Id) cachedApplicant.get('Id');
        Applicant_Address__c addr = resolveApplicantAddressForSave(
            row.Applicant_Address__c, applicantId, addressType
        );
        mapEntityAddressPayloadToApplicantAddress(addr, args);
        addr.Address_Type__c = addressType;
        stampEntitySameAsFlags(addr, gstSameAsRegistered, officeSameAsRegistered);
        upsertEntityApplicantAddress(addr);

        row.Applicant_Address__c = addr.Id;
        update row;
    }

    private void linkEntityChecklistAddress(Document_CheckList__c row, Id addressId) {
        if (row == null || addressId == null || row.Applicant_Address__c == addressId) {
            return;
        }
        row.Applicant_Address__c = addressId;
        update row;
    }

    private Map<String, Object> getEntityDocumentMasterConfigInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            String documentName = stringValue(args.get('documentName'));
            String documentCategory = stringValue(args.get('documentCategory'));
            if (String.isBlank(documentName) || String.isBlank(documentCategory)) {
                throw new AuraHandledException('documentName and documentCategory are required.');
            }

            List<Document_Master__c> masters = [
                SELECT Id, Max_Files_Allowed__c, File_Types_Allowed__c
                FROM Document_Master__c
                WHERE Document_Name__c = :documentName
                  AND Document_Category__c = :documentCategory
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            result.put('isSuccess', true);
            if (!masters.isEmpty()) {
                result.put('maxFilesAllowed', masters[0].Max_Files_Allowed__c);
                result.put('allowedFileTypes', masters[0].File_Types_Allowed__c);
                result.put('fromFallback', false);
            } else {
                result.put('maxFilesAllowed', ENTITY_ADDITIONAL_FALLBACK_MAX_FILES);
                result.put('allowedFileTypes', ENTITY_ADDITIONAL_FALLBACK_FILE_TYPES);
                result.put('fromFallback', true);
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'KYCDetailsController.getEntityDocumentMasterConfig: ' + e.getMessage());
        }
        return result;
    }

    private Map<String, Object> resolveContentDocumentIdInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            String contentVersionId = stringValue(args.get('contentVersionId'));
            if (String.isBlank(contentVersionId)) {
                throw new AuraHandledException('contentVersionId is required.');
            }

            List<ContentVersion> versions = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (versions.isEmpty() || versions[0].ContentDocumentId == null) {
                throw new AuraHandledException('Content document not found for the supplied file.');
            }

            result.put('isSuccess', true);
            result.put('contentDocumentId', versions[0].ContentDocumentId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'KYCDetailsController.resolveContentDocumentId: ' + e.getMessage());
        }
        return result;
    }

    private void persistApplicantDarpanFields(Map<String, Object> darpanArgs) {
        if (cachedApplicant == null) {
            return;
        }
        Map<String, Object> context = darpanArgs != null ? darpanArgs : new Map<String, Object>();
        Boolean applicable = isDarpanApplicableForCurrentApplicant();
        String npoStatus = stringValue(context.get('npoStatus'));
        Boolean isNpo = applicable && DARPAN_STATUS_NPO.equalsIgnoreCase(npoStatus);
        Boolean deferralApproval = applicable && isNpo && booleanValue(context.get('deferralApproval'));
        String darpanId = stringValue(context.get('darpanId'));
        DateTime registrationDate = parseDateTimeValue(context.get('registrationDate'));

        if (!isNpo || deferralApproval) {
            darpanId = null;
            registrationDate = null;
        }
        cachedApplicant.put('NPO__c', isNpo);
        cachedApplicant.put('Deferral_Approval__c', deferralApproval);
        cachedApplicant.put('Darpan_Id__c', String.isNotBlank(darpanId) ? darpanId : null);
        cachedApplicant.put('Darpan_Registration_Date__c', registrationDate);
    }

    private void persistEntityDarpanDocuments(
        Id recordId,
        Id applicantId,
        List<Object> darpanEntries,
        List<Document_CheckList__c> existingRows
    ) {
        if (applicantId == null) {
            return;
        }
        if (existingRows == null) {
            existingRows = findAllEntityDarpanDocumentRows(recordId, applicantId);
        }
        if (!isDarpanApplicableForCurrentApplicant()) {
            for (Document_CheckList__c row : existingRows) {
                deleteEntityAdditionalChecklistById(row.Id);
            }
            return;
        }
        if (darpanEntries == null) {
            darpanEntries = new List<Object>();
        }

        Set<Id> retainedChecklistIds = new Set<Id>();
        for (Object rawEntry : darpanEntries) {
            Map<String, Object> entry = asMap(rawEntry);
            Id savedId = persistEntityDarpanDocumentEntry(recordId, applicantId, entry, existingRows);
            if (savedId != null) {
                retainedChecklistIds.add(savedId);
            }
        }

        for (Document_CheckList__c row : existingRows) {
            if (!retainedChecklistIds.contains(row.Id)) {
                deleteEntityAdditionalChecklistById(row.Id);
            }
        }
    }

    private Id persistEntityDarpanDocumentEntry(
        Id recordId,
        Id applicantId,
        Map<String, Object> entry,
        List<Document_CheckList__c> existingRows
    ) {
        if (entry == null || entry.isEmpty()) {
            return null;
        }
        String docType = stringValue(entry.get('documentType'));
        Map<String, Object> proofFile = asMap(entry.get('proofFile'));
        String contentVersionId = proofFile != null
            ? stringValue(proofFile.get('contentVersionId'))
            : null;
        Id checklistId = parseId(entry.get('checklistRecordId'));
        if (String.isBlank(docType) || !DARPAN_DOC_TYPES.contains(docType.trim())) {
            return null;
        }
        if (String.isBlank(contentVersionId) && checklistId == null) {
            return null;
        }

        Document_CheckList__c row = null;
        if (existingRows != null) {
            for (Document_CheckList__c existing : existingRows) {
                if (checklistId != null && existing.Id == checklistId) {
                    row = existing;
                    break;
                }
            }
            if (row == null) {
                for (Document_CheckList__c existing : existingRows) {
                    if (docType.equalsIgnoreCase(existing.Document_Type__c)) {
                        row = existing;
                        break;
                    }
                }
            }
        }
        if (row == null) {
            Id applicationId = recordId != null
                ? recordId
                : (cachedApplicant != null ? (Id) cachedApplicant.get('Application__c') : null);
            row = new Document_CheckList__c(
                Applicant__c = applicantId,
                Application__c = applicationId,
                Document_Type__c = docType,
                Is_Active__c = true
            );
        }

        row.Document_Type__c = docType;
        row.Document_Master_Key__c = MandatoryDocumentsService.masterKeyForType(DOC_MODULE_KYC, docType);
        row.Is_Active__c = true;
        row.Attached_File_Side__c = SIDE_MODE_FULL;
        row.Address_Type__c = null;
        row.Applicant_Address__c = null;
        if (String.isBlank(row.Applicant_Type__c)) {
            String applicantPersona = (String) cachedApplicant.get('Applicant_Type__c');
            if (String.isNotBlank(applicantPersona)) {
                row.Applicant_Type__c = applicantPersona;
            }
        }
        if (String.isNotBlank(contentVersionId)) {
            row.ContentVersionId__c = contentVersionId;
            stampContentVersionSide(contentVersionId, SIDE_MODE_FULL);
        }

        row.Name = KYCInfoController.buildChecklistName(
            loadApplicantForName(applicantId),
            row.Document_Type__c
        );
        if (row.Id == null) {
            insert row;
            if (existingRows != null) {
                existingRows.add(row);
            }
        } else {
            update row;
        }
        return row.Id;
    }

    private List<Document_CheckList__c> findAllEntityDarpanDocumentRows(Id recordId, Id applicantId) {
        List<Document_CheckList__c> rows = new List<Document_CheckList__c>();
        if (applicantId == null) {
            return rows;
        }
        for (Document_CheckList__c row : queryChecklistRows(
                applicantId,
                new Set<String>(),
                DARPAN_DOC_TYPES)) {
            if (isEntityDarpanDocumentRow(row)) {
                rows.add(row);
            }
        }
        return rows;
    }

    private void persistEntityAdditionalDocuments(
        Id recordId,
        Id applicantId,
        List<Object> additionalEntries
    ) {
        if (applicantId == null || cachedApplicant == null) {
            return;
        }
        if (additionalEntries == null) {
            additionalEntries = new List<Object>();
        }

        Set<Id> retainedChecklistIds = new Set<Id>();
        for (Object rawEntry : additionalEntries) {
            Map<String, Object> entry = asMap(rawEntry);
            Id savedId = persistEntityAdditionalDocumentEntry(recordId, applicantId, entry);
            if (savedId != null) {
                retainedChecklistIds.add(savedId);
            }
        }

        for (Document_CheckList__c row : findAllEntityAdditionalDocumentRows(recordId, applicantId)) {
            if (!retainedChecklistIds.contains(row.Id)) {
                deleteEntityAdditionalChecklistById(row.Id);
            }
        }
    }

    private Id persistEntityAdditionalDocumentEntry(
        Id recordId,
        Id applicantId,
        Map<String, Object> entry
    ) {
        if (entry == null || entry.isEmpty()) {
            return null;
        }

        String docType = stringValue(entry.get('documentType'));
        Map<String, Object> proofFile = asMap(entry.get('proofFile'));
        Id checklistId = parseId(entry.get('checklistRecordId'));
        String contentVersionId = proofFile != null
            ? stringValue(proofFile.get('contentVersionId'))
            : null;

        Boolean hasType = String.isNotBlank(docType);
        Boolean hasFile = String.isNotBlank(contentVersionId);
        if (!hasType && !hasFile) {
            return null;
        }

        Document_CheckList__c row = resolveEntityAdditionalChecklistForSave(
            recordId,
            applicantId,
            checklistId,
            docType
        );
        if (row == null) {
            return null;
        }

        if (hasType) {
            row.Document_Type__c = docType;
            row.Document_Master_Key__c = MandatoryDocumentsService.masterKeyForType(DOC_MODULE_KYC, docType);
        }
        row.Is_Active__c = true;
        row.Attached_File_Side__c = SIDE_MODE_FULL;
        row.Address_Type__c = null;
        row.Applicant_Address__c = null;

        if (String.isBlank(row.Applicant_Type__c)) {
            String applicantPersona = (String) cachedApplicant.get('Applicant_Type__c');
            if (String.isNotBlank(applicantPersona)) {
                row.Applicant_Type__c = applicantPersona;
            }
        }

        if (hasFile) {
            row.ContentVersionId__c = contentVersionId;
            stampContentVersionSide(contentVersionId, SIDE_MODE_FULL);
        }

        row.Name = KYCInfoController.buildChecklistName(
            loadApplicantForName(applicantId),
            row.Document_Type__c
        );

        if (row.Id == null) {
            insert row;
        } else {
            update row;
        }
        return row.Id;
    }

    private Document_CheckList__c resolveEntityAdditionalChecklistForSave(
        Id recordId,
        Id applicantId,
        Id checklistId,
        String docType
    ) {
        if (checklistId != null) {
            List<Document_CheckList__c> rows = [
                SELECT Id, Applicant__c, Application__c, Document_Type__c,
                       Applicant_Type__c, ContentVersionId__c
                FROM Document_CheckList__c
                WHERE Id = :checklistId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                return rows[0];
            }
        }

        if (String.isNotBlank(docType)) {
            Document_CheckList__c existingByType = findEntityAdditionalDocumentRowByType(
                recordId,
                applicantId,
                docType
            );
            if (existingByType != null) {
                return existingByType;
            }
        }

        if (String.isBlank(docType)) {
            return null;
        }

        Id applicationId = recordId != null
            ? recordId
            : (cachedApplicant != null ? (Id) cachedApplicant.get('Application__c') : null);
        Document_CheckList__c row = new Document_CheckList__c(
            Applicant__c     = applicantId,
            Application__c   = applicationId,
            Document_Type__c = docType,
            Is_Active__c     = true
        );
        if (cachedApplicant != null && String.isBlank(row.Applicant_Type__c)) {
            String applicantPersona = (String) cachedApplicant.get('Applicant_Type__c');
            if (String.isNotBlank(applicantPersona)) {
                row.Applicant_Type__c = applicantPersona;
            }
        }
        return row;
    }

    private List<Document_CheckList__c> findAllEntityAdditionalDocumentRows(Id recordId, Id applicantId) {
        List<Document_CheckList__c> rows = new List<Document_CheckList__c>();
        if (applicantId == null) {
            return rows;
        }
        Set<String> constitutionDocTypes = buildEntityConstitutionDocumentTypes(recordId);
        for (Document_CheckList__c row : queryChecklistRows(
                applicantId,
                new Set<String>(),
                extendEntityQueryableDocumentTypes(constitutionDocTypes))) {
            if (isEntityAdditionalDocumentRow(row, constitutionDocTypes)) {
                rows.add(row);
            }
        }
        return rows;
    }

    private Document_CheckList__c findEntityAdditionalDocumentRowByType(
        Id recordId,
        Id applicantId,
        String docType
    ) {
        if (applicantId == null || String.isBlank(docType)) {
            return null;
        }
        for (Document_CheckList__c row : findAllEntityAdditionalDocumentRows(recordId, applicantId)) {
            if (docType.equalsIgnoreCase(row.Document_Type__c)) {
                return row;
            }
        }
        return null;
    }

    private void deleteEntityAdditionalChecklistById(Id checklistId) {
        if (checklistId == null) {
            return;
        }
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :checklistId
            WITH SECURITY_ENFORCED
        ];
        if (!links.isEmpty()) {
            delete links;
        }
        List<Document_CheckList__c> rows = [
            SELECT Id, Is_Active__c, ContentVersionId__c
            FROM Document_CheckList__c
            WHERE Id = :checklistId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            Document_CheckList__c row = rows[0];
            row.Is_Active__c = false;
            row.ContentVersionId__c = null;
            update row;
        }
    }

    private void mapEntityAddressPayloadToApplicantAddress(
        Applicant_Address__c addr,
        Map<String, Object> args
    ) {
        if (addr == null || args == null || args.isEmpty()) {
            return;
        }
        String addr1 = stringValue(args.get('kycAddressLine1'));
        String addr2 = stringValue(args.get('kycAddressLine2'));
        String district = stringValue(args.get('district'));
        String city = stringValue(args.get('city'));
        String state = stringValue(args.get('state'));
        String pin = stringValue(args.get('kycPinCode'));

        addr.Address_Line_1__c = String.isNotBlank(addr1) ? addr1 : null;
        addr.Address_Line_2__c = String.isNotBlank(addr2) ? addr2 : null;
        addr.District__c       = String.isNotBlank(district) ? district : null;
        addr.City__c           = String.isNotBlank(city) ? city : null;
        addr.State__c          = String.isNotBlank(state) ? state : null;
        addr.PinCode__c        = String.isNotBlank(pin) ? pin : null;
    }

    private void stampEntitySameAsFlags(
        Applicant_Address__c addr,
        String gstSameAsRegistered,
        String officeSameAsRegistered
    ) {
        if (addr == null) {
            return;
        }
        if (String.isNotBlank(gstSameAsRegistered)) {
            addr.Is_Registered_Address_Same_As_GST__c = gstSameAsRegistered;
        }
        if (String.isNotBlank(officeSameAsRegistered)) {
            addr.Is_Office_Address_Same_As_Registered__c = officeSameAsRegistered;
        }
    }

    private void upsertEntityApplicantAddress(Applicant_Address__c addr) {
        if (addr == null) {
            return;
        }
        Boolean isNew = (addr.Id == null);
        if (isNew && ADDRESS_TYPE_REGISTERED.equalsIgnoreCase(stringValue(addr.Address_Type__c))) {
            addr.Address_Proof__c = true;
        }
        if (String.isBlank(addr.Name) || isNew) {
            String addrName = String.isNotBlank(addr.Address_Line_1__c)
                ? addr.Address_Line_1__c
                : addr.Address_Type__c;
            addr.Name = addrName.length() > 80 ? addrName.substring(0, 80) : addrName;
        }
        upsert addr;
    }

    private void deleteApplicantAddressesByType(Id applicantId, String addressType) {
        if (applicantId == null || String.isBlank(addressType)) {
            return;
        }
        List<Applicant_Address__c> rows = [
            SELECT Id
            FROM Applicant_Address__c
            WHERE Applicant__c = :applicantId
              AND Address_Type__c = :addressType
            WITH SECURITY_ENFORCED
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }
    }

    /**
     * Writes the user-selected Document Type, side mode, and ContentVersion
     * metadata onto the bucket's Document_CheckList__c, stamps Front/Back/Full
     * on the matching ContentVersion rows, and persists the linked
     * Applicant_Address__c.
     */
    private void saveAddressDocumentToChecklist(Document_CheckList__c row, Map<String, Object> args, String addressType) {
        if (row == null) {
            return;
        }
        String fallbackDocType = ADDRESS_TYPE_PERMANENT.equals(addressType)
            ? DOC_TYPE_PERMANENT_ADDRESS_PROOF
            : DOC_TYPE_CURRENT_ADDRESS_PROOF;

        String addrDocumentType = stringValue(args.get('addrDocumentType'));
        String sideMode         = stringValue(args.get('documentSideMode'));
        if (String.isBlank(sideMode)) {
            sideMode = SIDE_MODE_FULL;
        }

        row.Document_Type__c       = String.isNotBlank(addrDocumentType)
            ? addrDocumentType
            : fallbackDocType;
        row.Address_Type__c        = addressType;
        // Attached_File_Side__c is a restricted picklist whose valid values
        // are concrete sides ('Full', 'Front', 'Back').
        if (SIDE_MODE_SIDE.equalsIgnoreCase(sideMode)) {
            if (String.isBlank(row.Attached_File_Side__c)
                || SIDE_MODE_FULL.equalsIgnoreCase(row.Attached_File_Side__c)) {
                row.Attached_File_Side__c = 'Front';
            }
        } else {
            row.Attached_File_Side__c = SIDE_MODE_FULL;
        }
        row.Is_Active__c           = true;

        if (String.isBlank(row.Applicant_Type__c) && cachedApplicant != null) {
            String applicantPersona = (String) cachedApplicant.get('Applicant_Type__c');
            if (String.isNotBlank(applicantPersona)) {
                row.Applicant_Type__c = applicantPersona;
            }
        }

        mapExtractedDetailsToApplicantAddress(row, args, addressType);

        Map<String, Object> fullFile  = asMap(args.get('addressProofFile'));
        Map<String, Object> frontFile = asMap(args.get('addressProofFileFront'));
        Map<String, Object> backFile  = asMap(args.get('addressProofFileBack'));

        if (SIDE_MODE_SIDE.equalsIgnoreCase(sideMode)) {
            String frontContentVersionId = stringValue(frontFile.get('contentVersionId'));
            String backContentVersionId  = stringValue(backFile.get('contentVersionId'));

            row.ContentVersionId__c = String.isNotBlank(frontContentVersionId)
                ? frontContentVersionId
                : backContentVersionId;

            stampContentVersionSide(frontContentVersionId, SIDE_FRONT);
            stampContentVersionSide(backContentVersionId,  SIDE_BACK);
        } else {
            String fullContentVersionId = stringValue(fullFile.get('contentVersionId'));
            row.ContentVersionId__c = fullContentVersionId;
            stampContentVersionSide(fullContentVersionId, SIDE_FULL);
        }

        // Refresh the Name field to "Applicant Name + ' ' + Document Type"
        // whenever the doc type changes. 
        row.Name = KYCInfoController.buildChecklistName(loadApplicantForName((Id) row.Applicant__c), row.Document_Type__c);

        update row;
    }

    /**
     * Upserts the bucket's Applicant_Address__c from POA/POI toggles + the
     * Extracted Document Details payload, and stamps the lookup on the
     * checklist row. One record per (applicant, addressType).
     */
    private void mapExtractedDetailsToApplicantAddress(Document_CheckList__c row, Map<String, Object> args, String addressType) {
        if (row == null || cachedApplicant == null) {
            return;
        }
        Boolean poaConfirmed = booleanValue(args.get('addressProofToggle'));
        Boolean poiConfirmed = booleanValue(args.get('identityProofToggle'));

        Map<String, Object> extracted = asMap(args.get('extractedDetails'));
        Id applicantId = (Id) cachedApplicant.get('Id');

        Applicant_Address__c addr = resolveApplicantAddressForSave(
            row.Applicant_Address__c, applicantId, addressType
        );
        Boolean isNew = (addr.Id == null);

        addr.Address_Type__c    = addressType;
        addr.Address_Proof__c   = poaConfirmed;
        addr.Identity_Proof__c  = poiConfirmed;

        // Section 3 Yes/No picklists live on the Current row only.
        if (ADDRESS_TYPE_CURRENT.equals(addressType)) {
            if (args.containsKey('isCurrentAddrSameAsPermanent')) {
                String v = stringValue(args.get('isCurrentAddrSameAsPermanent'));
                addr.Is_Current_Address_Same_As_Permanent__c = String.isBlank(v) ? null : v;
            }
            if (args.containsKey('isOfficeAddrSameAsCurrent')) {
                String v = stringValue(args.get('isOfficeAddrSameAsCurrent'));
                addr.Is_Office_Address_Same_As_Current__c = String.isBlank(v) ? null : v;
            }
        }

        String addr1 = stringValue(extracted.get('address1'));
        String addr2 = stringValue(extracted.get('address2'));
        String addr3 = stringValue(extracted.get('address3'));
        String addr4 = stringValue(extracted.get('address4'));
        if (String.isNotBlank(addr1)) addr.Address_Line_1__c = addr1;
        if (String.isNotBlank(addr2)) addr.Address_Line_2__c = addr2;
        if (String.isNotBlank(addr3)) addr.Address_Line_3__c = addr3;
        if (String.isNotBlank(addr4)) addr.Address_Line_4__c = addr4;

        String pin   = stringValue(extracted.get('pin'));
        String city  = stringValue(extracted.get('city'));
        String state = stringValue(extracted.get('state'));
        if (String.isNotBlank(pin))   addr.PinCode__c  = pin;
        if (String.isNotBlank(city))  addr.City__c     = city;
        if (String.isNotBlank(state)) addr.State__c    = state;
        if (String.isNotBlank(addr3)) addr.District__c = addr3;

        if (String.isBlank(addr.Name) || isNew) {
            String addrName = String.isNotBlank(addr1) ? addr1 : addressType;
            addr.Name = addrName.length() > 80 ? addrName.substring(0, 80) : addrName;
        }

        upsert addr;

        if (row.Applicant_Address__c == null) {
            row.Applicant_Address__c = addr.Id;
        }
    }

    /** Returns the existing Applicant_Address__c for this (applicant, type)
     *  or a new in-memory row stamped with the master-detail key. */
    private Applicant_Address__c resolveApplicantAddressForSave(Id existingId, Id applicantId, String addressType) {
        if (existingId != null) {
            List<Applicant_Address__c> rows = [
                SELECT Id, Name, Applicant__c, Address_Type__c, Address_Proof__c, Identity_Proof__c,
                       Address_Line_1__c, Address_Line_2__c, PinCode__c, City__c, State__c, District__c,
                       Is_Registered_Address_Same_As_GST__c, Is_Office_Address_Same_As_Registered__c
                FROM Applicant_Address__c
                WHERE Id = :existingId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                Applicant_Address__c existing = rows[0];
                if (addressType.equalsIgnoreCase(String.valueOf(existing.Address_Type__c))) {
                    return existing;
                }
            }
        }
        List<Applicant_Address__c> matches = [
            SELECT Id, Name, Applicant__c, Address_Type__c, Address_Proof__c, Identity_Proof__c,
                   Address_Line_1__c, Address_Line_2__c, PinCode__c, City__c, State__c, District__c,
                   Is_Registered_Address_Same_As_GST__c, Is_Office_Address_Same_As_Registered__c
            FROM Applicant_Address__c
            WHERE Applicant__c    = :applicantId
              AND Address_Type__c = :addressType
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!matches.isEmpty()) return matches[0];
        return new Applicant_Address__c(
            Applicant__c    = applicantId,
            Address_Type__c = addressType
        );
    }

    private void stampContentVersionSide(String contentVersionId, String side) {
        if (String.isBlank(contentVersionId) || String.isBlank(side)) {
            return;
        }
        List<ContentVersion> versions = [
            SELECT Id, File_Side__c
            FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            return;
        }
        if (!side.equalsIgnoreCase(String.valueOf(versions[0].File_Side__c))) {
            versions[0].File_Side__c = side;
            update versions[0];
        }
    }

    private Map<String, Object> createAddressChecklistInternal(Map<String, Object> args, String addressType) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id recordId = parseId(args.get('recordId'));
            Id applicantId = parseId(args.get('applicantId'));
            if (applicantId == null) {
                throw new AuraHandledException('applicantId is required.');
            }
            if (recordId == null) {

                Applicant__c applicant = loadApplicantForName(applicantId);
                recordId = applicant != null ? applicant.Application__c : null;
            }
            // Office bucket is only valid for Earning applicants.
            if (ADDRESS_TYPE_OFFICE.equals(addressType)) {
                loadCachedData(recordId, args);
                String incomeCategory = cachedApplicant != null
                    ? stringValue(cachedApplicant.get('Income_Category__c'))
                    : null;
                if (String.isBlank(incomeCategory)
                    || INCOME_CATEGORY_NON_EARNING.equalsIgnoreCase(incomeCategory)) {
                    result.put('message', 'Office Address does not apply for Non-Earning applicants.');
                    return result;
                }
            }
            Document_CheckList__c checklistRow = getOrCreateAddressChecklist(recordId, applicantId, addressType);
            result.put('isSuccess', true);
            result.put('checklistRecordId', checklistRow != null ? checklistRow.Id : null);
            result.put('addressType', addressType);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'KYCDetailsController.createAddressChecklist[' + addressType + ']: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Stamps Address_Type__c on an upload-created proof checklist so entity
     * page load can resolve the Registered / Office bucket before NEXT.
     */
    private Map<String, Object> stampEntityAddressChecklistInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id recordId = parseId(args.get('recordId'));
            Id applicantId = parseId(args.get('applicantId'));
            Id checklistId = parseId(args.get('checklistRecordId'));
            String addressType = stringValue(args.get('addressType'));
            String addressProof = stringValue(args.get('addressProof'));

            if (checklistId == null) {
                throw new AuraHandledException('checklistRecordId is required.');
            }
            if (String.isBlank(addressType)) {
                throw new AuraHandledException('addressType is required.');
            }
            if (!ADDRESS_TYPE_REGISTERED.equalsIgnoreCase(addressType)
                && !ADDRESS_TYPE_OFFICE.equalsIgnoreCase(addressType)) {
                throw new AuraHandledException('addressType must be Registered Address or Office Address.');
            }

            loadCachedData(recordId, args);
            if (cachedApplicant == null) {
                throw new AuraHandledException('Applicant not found for the supplied recordId / applicantId.');
            }
            if (applicantId == null) {
                applicantId = (Id) cachedApplicant.get('Id');
            }

            List<Document_CheckList__c> rows = [
                SELECT Id, Applicant__c, Document_Type__c, Address_Type__c,
                       Applicant_Type__c, Applicant_Address__c, Is_Active__c
                FROM Document_CheckList__c
                WHERE Id = :checklistId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('Document checklist not found.');
            }

            Document_CheckList__c row = rows[0];
            if (row.Applicant__c != applicantId) {
                throw new AuraHandledException('Checklist does not belong to the current applicant.');
            }

            row.Address_Type__c = addressType.trim();
            if (String.isNotBlank(addressProof)) {
                row.Document_Type__c = addressProof.trim();
            }
            row.Is_Active__c = true;
            if (String.isBlank(row.Applicant_Type__c)) {
                String applicantPersona = (String) cachedApplicant.get('Applicant_Type__c');
                if (String.isNotBlank(applicantPersona)) {
                    row.Applicant_Type__c = applicantPersona;
                }
            }

            if (!Schema.sObjectType.Document_CheckList__c.isUpdateable()) {
                throw new AuraHandledException('Insufficient access to update the document checklist.');
            }
            update row;

            result.put('isSuccess', true);
            result.put('checklistRecordId', row.Id);
            result.put('addressType', addressType);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'KYCDetailsController.stampEntityAddressChecklist: ' + e.getMessage());
        }
        return result;
    }

    private static Boolean isEntityAddressProofBucket(String addressType) {
        return ADDRESS_TYPE_REGISTERED.equalsIgnoreCase(addressType)
            || ADDRESS_TYPE_OFFICE.equalsIgnoreCase(addressType);
    }

    private Map<String, Object> createEntityAddressChecklistInternal(Map<String, Object> args, String addressType) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id recordId = parseId(args.get('recordId'));
            Id applicantId = parseId(args.get('applicantId'));
            if (applicantId == null) {
                throw new AuraHandledException('applicantId is required.');
            }
            if (recordId == null) {
                Applicant__c applicant = loadApplicantForName(applicantId);
                recordId = applicant != null ? applicant.Application__c : null;
            }
            Document_CheckList__c checklistRow = getOrCreateAddressChecklist(recordId, applicantId, addressType);
            result.put('isSuccess', true);
            result.put('checklistRecordId', checklistRow != null ? checklistRow.Id : null);
            result.put('checklistId', checklistRow != null ? checklistRow.Id : null);
            result.put('addressType', addressType);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'KYCDetailsController.createEntityAddressChecklist[' + addressType + ']: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Persists the Office Address bucket. Writes address lines, pincode,
     * city/state, email, and email-verified flag onto the linked
     * Applicant_Address__c (one row per applicant + Office bucket). No
     * document/file/OCR shape — Office is a plain address-capture form.
     */
    private void saveOfficeAddressToChecklist(Document_CheckList__c row, Map<String, Object> args) {
        if (row == null || cachedApplicant == null) {
            return;
        }
        row.Document_Type__c = DOC_TYPE_OFFICE_ADDRESS_PROOF;
        row.Address_Type__c  = ADDRESS_TYPE_OFFICE;
        row.Is_Active__c     = true;
        if (String.isBlank(row.Applicant_Type__c)) {
            String applicantPersona = (String) cachedApplicant.get('Applicant_Type__c');
            if (String.isNotBlank(applicantPersona)) {
                row.Applicant_Type__c = applicantPersona;
            }
        }

        Id applicantId = (Id) cachedApplicant.get('Id');
        Applicant_Address__c addr = resolveApplicantAddressForSave(
            row.Applicant_Address__c, applicantId, ADDRESS_TYPE_OFFICE
        );
        Boolean isNew = (addr.Id == null);

        addr.Address_Type__c = ADDRESS_TYPE_OFFICE;

        String addr1 = stringValue(args.get('addressLine1'));
        String addr2 = stringValue(args.get('addressLine2'));
        String addr3 = stringValue(args.get('addressLine3'));
        addr.Address_Line_1__c = String.isNotBlank(addr1) ? addr1 : null;
        addr.Address_Line_2__c = String.isNotBlank(addr2) ? addr2 : null;
        addr.Address_Line_3__c = String.isNotBlank(addr3) ? addr3 : null;

        String pin     = stringValue(args.get('pinCode'));
        String city    = stringValue(args.get('city'));
        String state   = stringValue(args.get('state'));
        String country = stringValue(args.get('country'));
        addr.PinCode__c = String.isNotBlank(pin)     ? pin     : null;
        addr.City__c    = String.isNotBlank(city)    ? city    : null;
        addr.State__c   = String.isNotBlank(state)   ? state   : null;
        if (String.isNotBlank(country)) addr.Country__c = country;

        String email = stringValue(args.get('email'));
        addr.Email__c          = String.isNotBlank(email) ? email : null;
        addr.Email_Verified__c = booleanValue(args.get('emailVerified'));

        if (String.isBlank(addr.Name) || isNew) {
            String addrName = String.isNotBlank(addr1) ? addr1 : ADDRESS_TYPE_OFFICE;
            addr.Name = addrName.length() > 80 ? addrName.substring(0, 80) : addrName;
        }

        upsert addr;

        if (row.Applicant_Address__c == null) {
            row.Applicant_Address__c = addr.Id;
        }
        update row;
    }

    /**
     * Removes the address-proof file from a checklist row and clears the
     * OCR snapshot on the linked Applicant_KYC__c so the Extracted Document
     * Details panel reloads empty.
     */
    private Map<String, Object> deleteCurrentAddressKycFileInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id checklistRecordId = parseId(args.get('checklistRecordId'));
            String contentDocumentIdRaw = stringValue(args.get('contentDocumentId'));
            String contentVersionIdRaw  = stringValue(args.get('contentVersionId'));
            Boolean softDeleteRow = booleanValue(args.get('softDeleteRow'));
            if (checklistRecordId == null) {
                throw new AuraHandledException('checklistRecordId is required.');
            }

            List<Document_CheckList__c> rows = [
                SELECT Id, ContentVersionId__c, Address_Type__c, Applicant_Address__c,
                       Applicant_KYC__c, Applicant_KYC__r.Id
                FROM Document_CheckList__c
                WHERE Id = :checklistRecordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('Checklist row not found.');
            }
            Document_CheckList__c row = rows[0];

            Set<Id> targetCdIds = new Set<Id>();
            if (String.isNotBlank(contentDocumentIdRaw)) {
                try { targetCdIds.add((Id) contentDocumentIdRaw); } catch (Exception ignored) {}
            }
            if (targetCdIds.isEmpty() && String.isNotBlank(contentVersionIdRaw)) {
                List<ContentVersion> cvs = [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :contentVersionIdRaw
                    LIMIT 1
                ];
                if (!cvs.isEmpty()) {
                    targetCdIds.add(cvs[0].ContentDocumentId);
                }
            }

            if (!targetCdIds.isEmpty()) {
                List<ContentDocumentLink> linksToDelete = [
                    SELECT Id
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId    = :checklistRecordId
                      AND ContentDocumentId IN :targetCdIds
                ];
                if (!linksToDelete.isEmpty()) {
                    delete linksToDelete;
                }
            }

            row.ContentVersionId__c = null;

            Integer remainingFileLinks = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :checklistRecordId
            ];
            if (softDeleteRow) {
                row.Is_Active__c = false;
            } else if (remainingFileLinks == 0 && isEntityAddressProofBucket(row.Address_Type__c)) {
                row.Is_Active__c = false;
            }

            update row;

            if (row.Applicant_KYC__c != null) {
                Applicant_KYC__c kyc = new Applicant_KYC__c(Id = row.Applicant_KYC__c);
                kyc.KYC_name__c            = null;
                kyc.KYC_DOB__c             = null;
                kyc.KYC_Issuance_Date__c   = null;
                kyc.KYC_Expiry_Date__c     = null;
                kyc.KYC_Place_of_Issue__c  = null;
                kyc.KYC_No__c              = null;
                kyc.Masked_KYC_No__c       = null;
                kyc.KYC_Address_Line_1__c  = null;
                kyc.KYC_Address_Line_2__c  = null;
                kyc.KYC_Address_Line_3__c  = null;
                kyc.KYC_Address_Line_4__c  = null;
                kyc.KYC_City__c            = null;
                kyc.KYC_State__c           = null;
                kyc.KYC_Pin_Code__c        = null;
                kyc.KYC_District__c        = null;
                update kyc;
            }

            result.put('isSuccess', true);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'KYCDetailsController.deleteCurrentAddressKycFile: ' + e.getMessage());
        }
        return result;
    }

    /** Returns the bucket's checklist row, creating it if absent. */
    private Document_CheckList__c getOrCreateAddressChecklist(Id recordId, Id applicantId, String addressType) {
        if (applicantId == null) {
            return null;
        }
        List<Document_CheckList__c> rows = queryAddressChecklistRows(applicantId, new Set<String>{ addressType });
        if (!rows.isEmpty()) {
            return rows[0];
        }
        return insertAddressChecklist(recordId, applicantId, addressType);
    }

    private Document_CheckList__c insertAddressChecklist(Id recordId, Id applicantId, String addressType) {
        String docType = docTypeFor(addressType);
        Applicant__c applicant = loadApplicantForName(applicantId);
        Id applicationId = recordId != null
            ? recordId
            : (applicant != null ? applicant.Application__c : null);
        Document_CheckList__c row = new Document_CheckList__c(
            Applicant__c     = applicantId,
            Application__c   = applicationId,
            Document_Type__c = docType,
            Address_Type__c  = addressType,
            Is_Active__c     = true,
            Name             = KYCInfoController.buildChecklistName(applicant, docType)
        );
        insert row;
        return row;
    }

    /**
     * Returns the Applicant's Name + Application context needed by save /
     * insert paths to build the Document_CheckList__c.Name label and stamp
     * Application__c on a fresh row. 
     */
    private Applicant__c loadApplicantForName(Id applicantId) {
        if (applicantId == null) return null;

        if (cachedApplicant != null && applicantId.equals((Id) cachedApplicant.get('Id'))) {
            return new Applicant__c(
                Id                     = applicantId,
                Application__c         = (Id)     cachedApplicant.get('Application__c'),
                Customer_First_Name__c = (String) cachedApplicant.get('Customer_First_Name__c'),
                Customer_Last_Name__c  = (String) cachedApplicant.get('Customer_Last_Name__c')
            );
        }
        Applicant__c cached = applicantForNameCache.get(applicantId);
        if (cached != null) return cached;

        List<Applicant__c> rows = [
            SELECT Id, Application__c, Customer_First_Name__c, Customer_Last_Name__c
            FROM Applicant__c
            WHERE Id = :applicantId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;
        applicantForNameCache.put(applicantId, rows[0]);
        return rows[0];
    }
    private Map<Id, Applicant__c> applicantForNameCache = new Map<Id, Applicant__c>();

    private static String docTypeFor(String addressType) {
        if (ADDRESS_TYPE_REGISTERED.equals(addressType)) return DOC_TYPE_REGISTERED_ADDRESS_PROOF;
        if (ADDRESS_TYPE_PERMANENT.equals(addressType)) return DOC_TYPE_PERMANENT_ADDRESS_PROOF;
        if (ADDRESS_TYPE_OFFICE.equals(addressType))    return DOC_TYPE_OFFICE_ADDRESS_PROOF;
        return DOC_TYPE_CURRENT_ADDRESS_PROOF;
    }

    /** Bulk SOQL that returns checklist rows for one or more address buckets. */
    private List<Document_CheckList__c> queryAddressChecklistRows(Id applicantId, Set<String> addressTypes) {
        return queryChecklistRows(applicantId, addressTypes, new Set<String>());
    }

    /**
     * Bulk SOQL that returns checklist rows matching either the requested
     * address-type buckets OR any of the supplied extra document types.
     */
    private List<Document_CheckList__c> queryChecklistRows(Id applicantId, Set<String> addressTypes, Set<String> extraDocTypes) {
        Set<String> docTypes = new Set<String>();
        for (String t : addressTypes) {
            docTypes.add(docTypeFor(t));
        }
        if (extraDocTypes != null) {
            docTypes.addAll(extraDocTypes);
        }
        return [
            SELECT Id, Name, Applicant__c, Application__c, Document_Type__c, Address_Type__c,
                   Document_Master_Key__c,
                   Attached_File_Side__c, ContentVersionId__c, Is_Active__c,
                   Applicant_Type__c, Applicant_KYC__c, Applicant_Address__c,
                   First_Name__c, Last_Name__c, KYC_Date_of_Birth__c, Gender__c,
                   Applicant_KYC__r.KYC_name__c, Applicant_KYC__r.KYC_DOB__c,
                   Applicant_KYC__r.KYC_Issuance_Date__c, Applicant_KYC__r.KYC_Expiry_Date__c,
                   Applicant_KYC__r.KYC_Place_of_Issue__c, Applicant_KYC__r.KYC_No__c,
                   Applicant_KYC__r.Masked_KYC_No__c, Applicant_KYC__r.KYC_Type__c,
                   Applicant_KYC__r.KYC_Verification_Method__c,
                   Applicant_KYC__r.KYC_Address_Line_1__c, Applicant_KYC__r.KYC_Address_Line_2__c,
                   Applicant_KYC__r.KYC_Address_Line_3__c, Applicant_KYC__r.KYC_Address_Line_4__c,
                   Applicant_KYC__r.KYC_City__c, Applicant_KYC__r.KYC_State__c,
                   Applicant_KYC__r.KYC_Pin_Code__c, Applicant_KYC__r.KYC_District__c,
                   Applicant_KYC__r.KYC_URL__c, Applicant_KYC__r.AadhaareKYCLinkSent__c,
                   Applicant_KYC__r.AadhaareKYCLinkSent_Date__c,
                   Applicant_KYC__r.AadhaarConsentReceived__c, Applicant_KYC__r.Aadhar_Verified__c,
                   Applicant_KYC__r.Aadhar_OTP__c,
                   Applicant_Address__r.Address_Type__c,
                   Applicant_Address__r.Address_Line_1__c, Applicant_Address__r.Address_Line_2__c,
                   Applicant_Address__r.Address_Line_3__c, Applicant_Address__r.Address_Line_4__c,
                   Applicant_Address__r.PinCode__c, Applicant_Address__r.City__c, Applicant_Address__r.State__c,
                   Applicant_Address__r.Country__c, Applicant_Address__r.District__c,
                   Applicant_Address__r.Address_Proof__c, Applicant_Address__r.Identity_Proof__c,
                   Applicant_Address__r.Email__c, Applicant_Address__r.Email_Verified__c,
                   Applicant_Address__r.Is_Current_Address_Same_As_Permanent__c,
                   Applicant_Address__r.Is_Office_Address_Same_As_Current__c,
                   Applicant_Address__r.Is_Registered_Address_Same_As_GST__c,
                   Applicant_Address__r.Is_Office_Address_Same_As_Registered__c
            FROM Document_CheckList__c
            WHERE Applicant__c = :applicantId
              AND Is_Active__c = true
              AND (Address_Type__c IN :addressTypes
                   OR Document_Type__c IN :docTypes)
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC
        ];
    }

    /**
     * Wipes every row in the given address bucket: checklist + its
     * Applicant_KYC__c + Applicant_Address__c + attached file links.
     * Safe no-op when no rows exist for the bucket.
     */
    private void deleteAddressBucket(Id applicantId, String addressType) {
        if (applicantId == null) {
            return;
        }
        List<Document_CheckList__c> rows = queryAddressChecklistRows(applicantId, new Set<String>{ addressType });
        if (rows.isEmpty()) {
            return;
        }
        Set<Id> checklistIds = new Set<Id>();
        Set<Id> kycIds       = new Set<Id>();
        Set<Id> candidateAddrIds = new Set<Id>();
        for (Document_CheckList__c r : rows) {
            checklistIds.add(r.Id);
            if (r.Applicant_KYC__c     != null) kycIds.add(r.Applicant_KYC__c);
            if (r.Applicant_Address__c != null) candidateAddrIds.add(r.Applicant_Address__c);
        }
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId IN :checklistIds
        ];
        if (!links.isEmpty()) delete links;
        delete rows;
        if (!kycIds.isEmpty()) {
            delete [SELECT Id FROM Applicant_KYC__c WHERE Id IN :kycIds];
        }
        Set<Id> addrIdsToDelete = new Set<Id>();
        if (!candidateAddrIds.isEmpty()) {
            for (Applicant_Address__c addrRow : [
                SELECT Id, Address_Type__c
                FROM Applicant_Address__c
                WHERE Id IN :candidateAddrIds
                WITH SECURITY_ENFORCED
            ]) {
                if (addressType.equalsIgnoreCase(String.valueOf(addrRow.Address_Type__c))) {
                    addrIdsToDelete.add(addrRow.Id);
                }
            }
        }
        if (!addrIdsToDelete.isEmpty()) {
            delete [SELECT Id FROM Applicant_Address__c WHERE Id IN :addrIdsToDelete];
        }
    }

    /**
     * Builds  the Extracted Document Details payload for the LWC. KYC
     * metadata reads from the OCR snapshot on Applicant_KYC__c; address
     * lines prefer the user-confirmed Applicant_Address__c and fall back to
     * the OCR snapshot. Returns null when nothing has been extracted yet.
     */
    private Map<String, Object> buildExtractedDetailsMap(Document_CheckList__c row) {
        if (row == null) {
            return null;
        }
        Applicant_KYC__c     kyc  = row.Applicant_KYC__r;
        Applicant_Address__c addr = row.Applicant_Address__r;

        Boolean hasKycSnapshot = kyc != null && (
               String.isNotBlank(kyc.KYC_name__c)
            || String.isNotBlank(kyc.Masked_KYC_No__c)
            || String.isNotBlank(kyc.KYC_Address_Line_1__c));
        Boolean hasAddrConfirmed = addr != null && (
               String.isNotBlank(addr.Address_Line_1__c)
            || addr.Address_Proof__c == true
            || addr.Identity_Proof__c == true);
        Boolean hasAnyData = hasKycSnapshot || hasAddrConfirmed
            || String.isNotBlank(row.First_Name__c)
            || String.isNotBlank(row.Last_Name__c)
            || row.KYC_Date_of_Birth__c != null;
        if (!hasAnyData) {
            return null;
        }

        return new Map<String, Object>{
            'firstName' => row.First_Name__c,
            'lastName'  => row.Last_Name__c,
            'gender'    => row.Gender__c,
            'dob'       => row.KYC_Date_of_Birth__c == null ? null : String.valueOf(row.KYC_Date_of_Birth__c),
            'fullName'  => kyc != null ? kyc.KYC_name__c : null,
            'doi'       => (kyc != null && kyc.KYC_Issuance_Date__c != null) ? String.valueOf(kyc.KYC_Issuance_Date__c) : null,
            'doe'       => (kyc != null && kyc.KYC_Expiry_Date__c   != null) ? String.valueOf(kyc.KYC_Expiry_Date__c)   : null,
            'poi'       => kyc != null ? kyc.KYC_Place_of_Issue__c : null,
            'docNumber' => kyc != null ? kyc.Masked_KYC_No__c       : null,
            'docType'   => row.Document_Type__c,
            'kycType'   => kyc != null ? kyc.KYC_Type__c            : null,
            'address1'  => preferString(addr != null ? addr.Address_Line_1__c : null, kyc != null ? kyc.KYC_Address_Line_1__c : null),
            'address2'  => preferString(addr != null ? addr.Address_Line_2__c : null, kyc != null ? kyc.KYC_Address_Line_2__c : null),
            'address3'  => preferString(addr != null ? addr.Address_Line_3__c : null, kyc != null ? kyc.KYC_Address_Line_3__c : null),
            'address4'  => preferString(addr != null ? addr.Address_Line_4__c : null, kyc != null ? kyc.KYC_Address_Line_4__c : null),
            'pin'       => preferString(addr != null ? addr.PinCode__c        : null, kyc != null ? kyc.KYC_Pin_Code__c      : null),
            'city'      => preferString(addr != null ? addr.City__c           : null, kyc != null ? kyc.KYC_City__c          : null),
            'state'     => preferString(addr != null ? addr.State__c          : null, kyc != null ? kyc.KYC_State__c         : null)
        };
    }

    /** Returns the first non-blank string, else null. */
    private String preferString(String preferred, String fallback) {
        if (String.isNotBlank(preferred)) return preferred;
        if (String.isNotBlank(fallback))  return fallback;
        return null;
    }

    // =========================================================================
    // File restore on load
    // =========================================================================

    /**
     * Bulk SOQL that pulls ContentDocumentLink rows for the given checklist
     * ids and groups front/back/full file maps + sideMode under each checklist id.
     */
    private Map<Id, Map<String, Object>> queryAddressProofFiles(Set<Id> checklistIds) {
        Map<Id, Map<String, Object>> out = new Map<Id, Map<String, Object>>();
        Set<Id> validIds = new Set<Id>();
        for (Id i : checklistIds) {
            if (i != null) validIds.add(i);
        }
        if (validIds.isEmpty()) {
            return out;
        }
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocumentId,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.LatestPublishedVersion.Title,
                   ContentDocument.LatestPublishedVersion.FileExtension,
                   ContentDocument.LatestPublishedVersion.File_Side__c
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :validIds
            ORDER BY SystemModstamp DESC
        ];
        for (ContentDocumentLink link : links) {
            ContentVersion latestVersion = link.ContentDocument != null
                ? link.ContentDocument.LatestPublishedVersion
                : null;
            if (latestVersion == null) {
                continue;
            }
            Id key = link.LinkedEntityId;
            Map<String, Object> bucket = out.get(key);
            if (bucket == null) {
                bucket = new Map<String, Object>{
                    'frontFile' => null, 'backFile' => null, 'fullFile' => null
                };
                out.put(key, bucket);
            }
            Map<String, Object> fileMap = buildRestoredFileMap(link, latestVersion);
            String side = String.valueOf(latestVersion.File_Side__c);
            if (SIDE_FRONT.equalsIgnoreCase(side) && bucket.get('frontFile') == null) {
                bucket.put('frontFile', fileMap);
            } else if (SIDE_BACK.equalsIgnoreCase(side) && bucket.get('backFile') == null) {
                bucket.put('backFile', fileMap);
            } else if (bucket.get('fullFile') == null) {
                bucket.put('fullFile', fileMap);
            }
        }
        return out;
    }

    /**
     * Reverse-maps the persisted Document_CheckList__c.Document_Type__c back to
     * the Address Document Type dropdown value used by the LWC
     * (ADDR_DOCUMENT_TYPE_OPTIONS in wheelsIndividualKYCMasterPage).
     */
    private static String toUiDocumentType(String storedDocType) {
        if (String.isBlank(storedDocType)) return null;
        String t = storedDocType.trim();
        if ('Driving Licence'.equalsIgnoreCase(t) || 'Driving License'.equalsIgnoreCase(t)) return 'Driving License';
        if ('Voter Id'.equalsIgnoreCase(t)        || 'Voter ID'.equalsIgnoreCase(t))        return 'Voter ID';
        if ('Passport'.equalsIgnoreCase(t))                                                  return 'Passport';
        if ('Aadhaar Card'.equalsIgnoreCase(t)
            || 'Aadhaar'.equalsIgnoreCase(t)
            || 'Aadhar'.equalsIgnoreCase(t)
            || 'Aadhar Card'.equalsIgnoreCase(t))                                            return 'Aadhaar Card';
        if ('Others'.equalsIgnoreCase(t))                                                    return 'Others';
        return null;
    }

    /**
     * Merges the row's document type, toggles, and side mode with the
     * restored file maps so the LWC can rebuild the file-upload UI.
     */
    private Map<String, Object> mergeFileMap(Document_CheckList__c row, Map<Id, Map<String, Object>> filesByChecklist) {
        Map<String, Object> out = new Map<String, Object>{
            'frontFile'           => null, 'backFile' => null, 'fullFile' => null,
            'sideMode'            => null, 'uiDocumentType'      => null,
            'addressProofToggle'  => null, 'identityProofToggle' => null
        };
        if (row == null) {
            return out;
        }
        out.put('uiDocumentType', toUiDocumentType(row.Document_Type__c));
        Applicant_Address__c addrForToggles = row.Applicant_Address__r;
        out.put('addressProofToggle',  addrForToggles != null ? addrForToggles.Address_Proof__c  : null);
        out.put('identityProofToggle', addrForToggles != null ? addrForToggles.Identity_Proof__c : null);
        if (String.isNotBlank(row.Attached_File_Side__c)) {
            // Field stores concrete sides ('Full' / 'Front' / 'Back'). 
            out.put('sideMode',
                SIDE_MODE_FULL.equalsIgnoreCase(row.Attached_File_Side__c)
                    ? SIDE_MODE_FULL
                    : SIDE_MODE_SIDE);
        }
        Map<String, Object> files = filesByChecklist != null ? filesByChecklist.get(row.Id) : null;
        if (files != null) {
            out.put('frontFile', files.get('frontFile'));
            out.put('backFile',  files.get('backFile'));
            out.put('fullFile',  files.get('fullFile'));
        }
        if (String.isBlank((String) out.get('sideMode'))) {
            Boolean hasSideFiles = out.get('frontFile') != null || out.get('backFile') != null;
            out.put('sideMode', hasSideFiles ? SIDE_MODE_SIDE : SIDE_MODE_FULL);
        }
        return out;
    }

    private Map<String, Object> buildRestoredFileMap(ContentDocumentLink link, ContentVersion latestVersion) {
        String title     = String.valueOf(latestVersion.Title);
        String extension = String.valueOf(latestVersion.FileExtension);
        String fileName  = String.isNotBlank(title)
            ? (String.isNotBlank(extension) ? title + '.' + extension : title)
            : '';
        return new Map<String, Object>{
            'fileName'         => fileName,
            'contentDocumentId'=> link.ContentDocumentId,
            'contentVersionId' => latestVersion.Id
        };
    }

    // =========================================================================
    // Cache
    // =========================================================================

    /**
     * Single SOQL caches the explicit applicant (if any) plus the Borrower
     * applicant (Application-level fallback). When no applicantId is supplied
     * the cache defaults the current applicant to the Borrower.
     */
    private void loadCachedData(Id recordId, Map<String, Object> args) {
        if (recordId == null) {
            return;
        }
        Id explicitApplicantId = parseId(args.get('applicantId'));

        List<SObject> rows = Database.query(
            'SELECT ' + APPLICANT_SELECT + ' FROM Applicant__c ' +
            'WHERE Application__c = :recordId AND In_Active_Applicant__c = false ' +
            'WITH SECURITY_ENFORCED'
        );

        for (SObject row : rows) {
            if (APPLICANT_TYPE_BORROWER.equalsIgnoreCase((String) row.get('Applicant_Type__c'))) {
                cachedBorrowerApplicant = row;
            }
            if (explicitApplicantId != null && explicitApplicantId == (Id) row.get('Id')) {
                cachedApplicant = row;
            }
        }
        if (cachedApplicant == null) {
            cachedApplicant = cachedBorrowerApplicant;
        }
    }

    /** Returns true when the applicant has moved past the given stage step. */
    private Boolean isStageCompleteForApplicant(String stageStep) {
        SObject applicant = cachedApplicant != null ? cachedApplicant : cachedBorrowerApplicant;
        if (applicant == null || String.isBlank(stageStep)) {
            return false;
        }
        String completed = (String) applicant.get('Current_Loan_Stage_Complete__c');
        String currentLoanStage = (String) applicant.get('Loan_Stage__c');
        if (String.isNotBlank(completed) && stageStep.equalsIgnoreCase(completed.trim())) {
            return true;
        }
        if (String.isNotBlank(currentLoanStage) && !stageStep.equalsIgnoreCase(currentLoanStage.trim())) {
            return true;
        }
        return false;
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private Map<String, Object> fieldEntry(String key, Object value) {
        return new Map<String, Object>{ 'key' => key, 'value' => value };
    }

    /**
     * Writes the LWC-supplied Yes/No answer onto the cached Applicant when
     * the key is present in args; blanks the SObject field when the LWC sends an empty string.
     */
    private void applyApplicantAnswerIfPresent(Map<String, Object> args, String argKey, String fieldApiName) {
        if (cachedApplicant == null || args == null || !args.containsKey(argKey)) {
            return;
        }
        String value = stringValue(args.get(argKey));
        cachedApplicant.put(fieldApiName, String.isBlank(value) ? null : value);
    }

    private static Id parseId(Object raw) {
        if (raw == null) return null;
        String stringValue = String.valueOf(raw).trim();
        if (String.isBlank(stringValue)) return null;
        try {
            return (Id) stringValue;
        } catch (Exception ex) {
            return null;
        }
    }

    private static String stringValue(Object raw) {
        if (raw == null) return null;
        String value = String.valueOf(raw);
        return value == null ? null : value.trim();
    }

    private static Map<String, Object> asMap(Object raw) {
        if (raw == null) {
            return new Map<String, Object>();
        }
        if (raw instanceof Map<String, Object>) {
            return normalizeNestedMaps((Map<String, Object>) raw);
        }
        if (raw instanceof Map<Object, Object>) {
            Map<String, Object> converted = new Map<String, Object>();
            Map<Object, Object> src = (Map<Object, Object>) raw;
            for (Object key : src.keySet()) {
                converted.put(String.valueOf(key), src.get(key));
            }
            return normalizeNestedMaps(converted);
        }
        if (raw instanceof String) {
            String serialized = String.valueOf(raw).trim();
            if (String.isNotBlank(serialized) && serialized.startsWith('{')) {
                try {
                    return asMap(JSON.deserializeUntyped(serialized));
                } catch (Exception ignore) {
                }
            }
        }
        return new Map<String, Object>();
    }

    private static Map<String, Object> normalizeNestedMaps(Map<String, Object> source) {
        Map<String, Object> normalized = new Map<String, Object>();
        for (String key : source.keySet()) {
            Object value = source.get(key);
            if (value instanceof Map<String, Object>) {
                normalized.put(key, normalizeNestedMaps((Map<String, Object>) value));
            } else if (value instanceof Map<Object, Object>) {
                normalized.put(key, asMap(value));
            } else {
                normalized.put(key, value);
            }
        }
        return normalized;
    }

    private static List<Object> asObjectList(Object raw) {
        if (raw == null) {
            return new List<Object>();
        }
        if (raw instanceof List<Object>) {
            return (List<Object>) raw;
        }
        return new List<Object>();
    }

    /** Coerces LWC-supplied values (Boolean / 'true' / 'false' / 1 / 0) to a Boolean. */
    private static Boolean booleanValue(Object raw) {
        if (raw == null) return false;
        if (raw instanceof Boolean) return (Boolean) raw;
        String s = String.valueOf(raw).trim().toLowerCase();
        return s == 'true' || s == '1';
    }

    private static DateTime parseDateTimeValue(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof DateTime) {
            return (DateTime) raw;
        }
        String text = String.valueOf(raw).trim();
        if (String.isBlank(text)) {
            return null;
        }
        String candidate = text;
        if (candidate.endsWith('Z')) {
            candidate = candidate.substring(0, candidate.length() - 1);
        }
        if (candidate.contains('.')) {
            candidate = candidate.substring(0, candidate.indexOf('.'));
        }
        candidate = candidate.replace('T', ' ');
        if (candidate.length() == 16) {
            candidate += ':00';
        }
        try {
            return DateTime.valueOf(candidate);
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * Persists Applicant_KYC__c for a CIN or GST checklist row when the user
     * selects a document number on the Non-Individual KYC screen.
     */
    private Map<String, Object> saveNonIndividualKycDocInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        try {
            Id applicantId = parseId(args.get('applicantId'));
            String docType = stringValue(args.get('docType'));
            String kycNumber = stringValue(args.get('kycNumber'));
            String kycState = stringValue(args.get('kycState'));
            Id checklistId = parseId(args.get('checklistRecordId'));

            if (applicantId == null) {
                throw new AuraHandledException('applicantId is required.');
            }
            if (String.isBlank(docType)) {
                throw new AuraHandledException('docType is required.');
            }
            if (!DOC_TYPE_CIN.equalsIgnoreCase(docType) && !DOC_TYPE_GST.equalsIgnoreCase(docType)) {
                throw new AuraHandledException('docType must be CIN or GST.');
            }

            Document_CheckList__c checklistRow = resolveNonIndividualDocChecklist(
                applicantId, docType, checklistId
            );
            if (checklistRow == null) {
                throw new AuraHandledException('Document checklist not found for ' + docType + '.');
            }

            Applicant_KYC__c kyc = resolveNonIndividualApplicantKyc(
                checklistRow.Applicant_KYC__c, applicantId
            );

            if (String.isBlank(kycNumber)) {
                kyc.KYC_No__c = null;
                kyc.Masked_KYC_No__c = null;
                kyc.KYC_name__c = null;
                if (DOC_TYPE_GST.equalsIgnoreCase(docType)) {
                    kyc.KYC_State__c = String.isNotBlank(kycState) ? kycState : null;
                }
            } else {
                String trimmed = kycNumber.trim();
                kyc.KYC_No__c = trimmed;
                kyc.Masked_KYC_No__c = KYCAddressExtractionController.maskDocumentNumber(trimmed);
                kyc.KYC_name__c = DOC_TYPE_CIN.equalsIgnoreCase(docType) ? DOC_TYPE_CIN : DOC_TYPE_GST;
                if (DOC_TYPE_GST.equalsIgnoreCase(docType) && String.isNotBlank(kycState)) {
                    kyc.KYC_State__c = kycState;
                }
            }

            upsert kyc;

            if (checklistRow.Applicant_KYC__c == null) {
                checklistRow.Applicant_KYC__c = kyc.Id;
                update checklistRow;
            }

            result.put('isSuccess', true);
            result.put('applicantKycId', kyc.Id);
            result.put('maskedKycNo', kyc.Masked_KYC_No__c);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            result.put('message', 'KYCDetailsController.saveNonIndividualKycDoc: ' + e.getMessage());
        }
        return result;
    }

    private Document_CheckList__c resolveNonIndividualDocChecklist(
        Id applicantId,
        String docType,
        Id checklistId
    ) {
        if (checklistId != null) {
            List<Document_CheckList__c> byId = [
                SELECT Id, Applicant_KYC__c, Document_Type__c
                FROM Document_CheckList__c
                WHERE Id = :checklistId
                  AND Applicant__c = :applicantId
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!byId.isEmpty()) {
                return byId[0];
            }
        }

        List<Document_CheckList__c> rows = queryChecklistRows(
            applicantId,
            new Set<String>(),
            new Set<String>{ docType }
        );
        return rows.isEmpty() ? null : rows[0];
    }

    private Applicant_KYC__c resolveNonIndividualApplicantKyc(Id existingKycId, Id applicantId) {
        if (existingKycId != null) {
            List<Applicant_KYC__c> existing = [
                SELECT Id, Applicant__c, KYC_No__c, Masked_KYC_No__c, KYC_name__c, KYC_State__c
                FROM Applicant_KYC__c
                WHERE Id = :existingKycId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0];
            }
        }
        return new Applicant_KYC__c(Applicant__c = applicantId);
    }

    private Map<String, Object> getIntegrationMasterInternal(Map<String, Object> args) {
        String integrationName = stringValue(args.get('integrationName'));
        if (String.isBlank(integrationName)) {
            return new Map<String, Object>{
                'isSuccess' => false,
                'message'   => 'integrationName is required.'
            };
        }

        List<Integration_Master__c> rows = [
            SELECT Id, Name, Component_Reference__c
            FROM Integration_Master__c
            WHERE Name = :integrationName
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            return new Map<String, Object>{
                'isSuccess' => false,
                'message'   => 'Integration Master record not found for ' + integrationName + '.'
            };
        }

        Integration_Master__c master = rows[0];
        return new Map<String, Object>{
            'isSuccess'              => true,
            'Id'                     => master.Id,
            'Name'                   => master.Name,
            'Component_Reference__c' => master.Component_Reference__c
        };
    }
}