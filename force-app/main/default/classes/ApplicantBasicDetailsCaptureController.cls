public with sharing class ApplicantBasicDetailsCaptureController implements Callable {

    private static final String ACTION_GET_APPLICANT_PAGE = 'getApplicantPageData';
    private static final String ACTION_SAVE_APPLICANT_PAGE = 'saveApplicantPageData';

    private SObject cachedApplication;
    private SObject cachedApplicant;
    private SObject cachedBorrowerApplicant;
    private SObject cachedAsset;
    private SObject cachedDocumentChecklist;
    private SObject cachedPanDocumentChecklist;
    private SObject cachedForm60DocumentChecklist;
    private SObject cachedPrimaryLineItem;
    private Boolean isBeneficiaryApplicantContext = false;

    private static final String DOC_TYPE_PAN = 'PAN';
    private static final String DOC_TYPE_FORM_60 = 'Form 60';
    private static final String DOC_TYPE_LEGACY_INITIAL = 'Initial_DOC_Verification';

    private static final String APPLICATION_SELECT = 'Id,Name,Stage__c,Product__c,Application_number__c,' +
        'Sub_Stage__c,Loan_Source__c,Sub_Product__c,Branch__c,' +
        'Branch__r.Name,Total_Loan_Amount__c,Sanction_Date__c,Sanction_Status__c';
    private static final String APPLICANT_SELECT = 'Id,Applicant_Type__c,Applicant_Tab_Label__c,Entity_Type__c,Profile__c,Company_Name__c,' +
        'Major_Industry__c,Minor_Industry__c,Industry_Name__c,Industry_Code__c,Evaluation_Type__c,' +
        'Is_Income_Available__c,Declared_income__c,Is_PAN_Available__c,Income_Category__c,' +
        'Customer_First_Name__c,Customer_Last_Name__c,PAN_Number__c,PAN_Number_Verified__c,Date_of_Birth__c,Gender__c,Marital_status__c,' +
        'Phone__c,Email__c,Phone_Verified__c,Email_Verified__c,Phone_Verification_Code__c,Email_Verification_Code__c,' +
        'Application_Consent_Received__c,Consent_Sent__c,Applicant_Consent_Received_Date__c,' +
        'Type__c,Residence_country__c,' +
        'Contact_Person_Name__c,Landline_Number__c,' +
        'Beneficial_Owner_Category__c,Relationship_with_Entity__c,Relationship_Type__c,POA_Holder__c,ShareHolding__c,' +
        'Is_Sub_Applicant__c,Parent_Applicant__c,Is_Primary__c,Application__c,' +
        'Loan_Stage__c,Current_Loan_Stage_Complete__c,Is_Journey_Exposed__c';

    private static final String STAGE_BASIC_DETAILS = 'Basic Details';
    private static final String VEHICLE_SELECT = 'Id,Vehicle_type__c,Variant__c,Purpose_of_purchase__c,Product_Segment__c,' +
        'Application_Line_Items__c,Applicant__c';
    private static final String LINE_ITEM_SELECT = 'Id,Number_of_Vehicles__c,Customer_Requested_Loan_Amount__c';

    private static final Map<String, String> APPLICATION_FIELD_MAP = new Map<String, String>{
        'productType' => 'Product__c',
        'applicationNumber' => 'Application_number__c',
        'requiredLoanAmount' => 'Total_Loan_Amount__c',
        'sanctionDate' => 'Sanction_Date__c',
        'sanctionStatus' => 'Sanction_Status__c',
        'accountId' => 'Branch__c'
    };

    private static final Map<String, String> APPLICANT_FIELD_MAP = new Map<String, String>{
        'profileType' => 'Profile__c',
        'entityName' => 'Company_Name__c',
        'applicantEntityType' => 'Entity_Type__c',
        'incomeAvailable' => 'Is_Income_Available__c',
        'annualIncome' => 'Declared_income__c',
        'occupationCategory' => 'Income_Category__c',
        'isPanAvailable' => 'Is_PAN_Available__c',
        'extractedFirstName' => 'Customer_First_Name__c',
        'extractedLastName' => 'Customer_Last_Name__c',
        'extractedDateOfBirth' => 'Date_of_Birth__c',
        'dateOfIncorporation' => 'Date_of_Birth__c',
        'applicationType' => 'Type__c',
        'maritalStatus' => 'Marital_status__c',
        'gender' => 'Gender__c',
        'residenceCountry' => 'Residence_Country__c',
        'contactNumber' => 'Phone__c',
        'email' => 'Email__c',
        'contactPersonName' => 'Contact_Person_Name__c',
        'landlineNumber' => 'Landline_Number__c',
        'phoneVerified' => 'Phone_Verified__c',
        'emailVerified' => 'Email_Verified__c',
        'phoneVerificationCode' => 'Phone_Verification_Code__c',
        'emailVerificationCode' => 'Email_Verification_Code__c',
        'majorIndustry' => 'Major_Industry__c',
        'minorIndustry' => 'Minor_Industry__c',
        'industryName' => 'Industry_Name__c',
        'industryCode' => 'Industry_Code__c',
        'evaluationType' => 'Evaluation_Type__c'
    };

    private static final Map<String, String> BENEFICIARY_FIELD_MAP = new Map<String, String>{
        'beneficialOwnerCategory' => 'Beneficial_Owner_Category__c',
        'relationshipWithEntity' => 'Relationship_with_Entity__c',
        'relationshipType' => 'Relationship_Type__c',
        'poaHolder' => 'POA_Holder__c',
        'shareHolding' => 'ShareHolding__c'
    };

    private static final Map<String, String> ASSET_FIELD_MAP = new Map<String, String>{
        'assetType' => 'Vehicle_type__c',
        'segment' => 'Product_Segment__c',
        'purposeOfPurchase' => 'Purpose_of_purchase__c'
    };

    private static final Map<String, String> DOCUMENT_CHECKLIST_MAP = new Map<String, String>{
        'contentVersionId' => 'ContentVersionId__c',
        'documentName' => 'Name'
    };

    private static final Map<String, String> PAN_CHECKLIST_FIELD_MAP = new Map<String, String>{
        'contentVersionId' => 'ContentVersionId__c',
        'documentName' => 'Name',
        'extractedFirstName' => 'First_Name__c',
        'extractedLastName' => 'Last_Name__c',
        'extractedDateOfBirth' => 'KYC_Date_of_Birth__c'
    };

    private static final Map<String, String> FORM60_CHECKLIST_FIELD_MAP = new Map<String, String>{
        'form60ContentVersionId' => 'ContentVersionId__c',
        'form60DocumentName' => 'Name',
        'extractedFirstName' => 'First_Name__c',
        'extractedLastName' => 'Last_Name__c',
        'extractedDateOfBirth' => 'KYC_Date_of_Birth__c',
        'panAckNo' => 'PAN_ACK_No__c',
        'gender' => 'Gender__c'
    };

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_GET_APPLICANT_PAGE.equalsIgnoreCase(action)) {
            return getApplicantPageDataInternal(args);
        }
        if (ACTION_SAVE_APPLICANT_PAGE.equalsIgnoreCase(action)) {
            return saveApplicantPageDataInternal(args);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    @AuraEnabled(cacheable=false)
    public static String getAgentBranchName(String recordId, String accountId, String productType) {
        if (String.isBlank(recordId) || String.isBlank(accountId)) {
            return 'N/A';
        }
        try {
            ApplicantBasicDetailsCaptureController instance = new ApplicantBasicDetailsCaptureController();
            String derived = instance.deriveAgentBranchName(productType, accountId);
            return String.isNotBlank(derived) ? derived : 'N/A';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ApplicantBasicDetailsCaptureController.getAgentBranchName: ' + e.getMessage());
            return 'N/A';
        }
    }

    /** Returns the Account.Name for the supplied accountId, used when the record picker
     *  display name isn't available (e.g. initial load before user interaction). */
    @AuraEnabled(cacheable=true)
    public static String getAccountName(String accountId) {
        if (String.isBlank(accountId)) {
            return '';
        }
        try {
            List<Account> accounts = [SELECT Name FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1];
            return accounts.isEmpty() ? '' : accounts[0].Name;
        } catch (Exception e) {
            return '';
        }
    }

    private Map<String, Object> getApplicantPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return result;
        }
        try {
            loadCachedData(recordId, args);
            flattenFields(result, getApplicationDetailsConfig());
            flattenFields(result, getLoanBasicInfoConfig());
            flattenFields(result, getLoanDetailConfig());
            flattenFields(result, getProfessionalDetailConfig());
            flattenFields(result, getDocumentVerificationConfig());
            System.debug('document verification config: ' + result);
            System.debug('document verification config: ' + result.get('panCardUploadElement'));
            flattenFields(result, getContactInfoConfig());
            result.put('isBeneficiaryApplicant', isBeneficiaryApplicantContext);
            SObject entitySource = cachedApplicant != null ? cachedApplicant : cachedBorrowerApplicant;
            if (entitySource != null && cachedApplication != null) {
                String appType = (String) entitySource.get('Type__c');
                Boolean isNonIndividualApplicant = isNonIndividualApplicantType(appType);
                String companyName = (String) entitySource.get('Company_Name__c');
                if (isNonIndividualApplicant && String.isNotBlank(companyName)) {
                    result.put('entityName', companyName);
                }
            }
            putIndustryPicklistMetadata(result);
            putEntityTypePicklistMetadata(result);
            putEvaluationTypePicklistMetadata(result);
            putBeneficiaryPicklistMetadata(result);
            putCustomerTypePicklistMetadata(result);
            putIncomeCategoryPicklistMetadata(result);
            putGenderPicklistMetadata(result);
            result.put('isApplicantStageComplete', isApplicantCompletedForStageOrLater(STAGE_BASIC_DETAILS));
            result.put('hasGuarantorClone', cachedApplicantHasGuarantorClone());
            result.put('isSubApplicant', cachedApplicant != null && cachedApplicant.get('Is_Sub_Applicant__c') == true);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ApplicantBasicDetailsCaptureController.getApplicantPageDataInternal: ' + e.getMessage());
            throw new AuraHandledException('Error loading applicant basic details page data: ' + e.getMessage());
        }
        return result;
    }

    /** True when the cached (Beneficiary) applicant already has a Guarantor clone-shell, so the
     *  Basic Details copy-to-Guarantor question pre-selects Yes and stops re-prompting. */
    private Boolean cachedApplicantHasGuarantorClone() {
        if (!isBeneficiaryApplicantContext || cachedApplicant == null) {
            return false;
        }
        Id beneId = (Id) cachedApplicant.get('Id');
        if (beneId == null) {
            return false;
        }
        List<Applicant__c> clones = [
            SELECT Id
            FROM Applicant__c
            WHERE Parent_Applicant__c = :beneId
            AND Is_Sub_Applicant__c = false
            AND Applicant_Type__c = 'Guarantor'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return !clones.isEmpty();
    }

    /** True when the cached applicant has finished the named step or progressed past it.
     *  Lets the controller force the LWC into read-only mode regardless of the parent's
     *  isStagePast contract, so a returning user can review but not edit completed work. */
    private Boolean isApplicantCompletedForStageOrLater(String stageStep) {
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

    private static void flattenFields(Map<String, Object> result, List<Map<String, Object>> fields) {
        if (fields == null) {
            return;
        }
        for (Map<String, Object> field : fields) {
            String key = (String) field.get('key');
            if (String.isNotBlank(key)) {
                result.put(key, field.get('value'));
            }
        }
    }

    private List<Map<String, Object>> getApplicationDetailsConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        if (cachedApplication == null) {
            return fields;
        }
        SObject borrowerApplicant = cachedBorrowerApplicant != null ? cachedBorrowerApplicant : cachedApplicant;
        SObject entitySource = cachedApplicant != null ? cachedApplicant : borrowerApplicant;
        SObject beneficiarySource = isBeneficiaryApplicantContext ? cachedApplicant : null;

        fields.add(fieldEntry('productType', cachedApplication.get('Product__c')));
        fields.add(fieldEntry('assetType', cachedAsset != null ? cachedAsset.get('Vehicle_type__c') : null));
        String productType = (String) cachedApplication.get('Product__c');
        String applicationTypeValue = resolveApplicationTypeValue(borrowerApplicant);
        // Return the applicant's actual Type__c (blank for a newly added applicant) 
        String customerType = cachedApplicant != null ? (String) cachedApplicant.get('Type__c') : '';
        fields.add(fieldEntry('applicationType', applicationTypeValue));
        fields.add(fieldEntry('customerType', customerType));
        Object applicantEntityTypeVal = '';
        if (isBeneficiaryApplicantContext && borrowerApplicant != null) {
            applicantEntityTypeVal = borrowerApplicant.get('Entity_Type__c');
        } else if (entitySource != null) {
            applicantEntityTypeVal = entitySource.get('Entity_Type__c');
        }
        fields.add(fieldEntry('applicantEntityType', applicantEntityTypeVal));
        fields.add(fieldEntry('isPrimary', cachedApplicant != null ? cachedApplicant.get('Is_Primary__c') : false));
        fields.add(fieldEntry('entityName', entitySource != null ? entitySource.get('Company_Name__c') : ''));
        fields.add(fieldEntry('majorIndustry', entitySource != null ? entitySource.get('Major_Industry__c') : ''));
        fields.add(fieldEntry('minorIndustry', entitySource != null ? entitySource.get('Minor_Industry__c') : ''));
        fields.add(fieldEntry('industryName', entitySource != null ? entitySource.get('Industry_Name__c') : ''));
        fields.add(fieldEntry('industryCode', entitySource != null ? entitySource.get('Industry_Code__c') : ''));
        fields.add(fieldEntry('evaluationType', entitySource != null ? entitySource.get('Evaluation_Type__c') : ''));
        fields.add(fieldEntry('segment', cachedAsset != null ? cachedAsset.get('Product_Segment__c') : null));
        fields.add(fieldEntry('loanStage', cachedApplication.get('Sub_Stage__c')));
        fields.add(fieldEntry('numberOfVehicles', cachedPrimaryLineItem != null ? cachedPrimaryLineItem.get('Number_of_Vehicles__c') : null));

        if (beneficiarySource != null) {
            fields.add(fieldEntry('beneficialOwnerCategory', beneficiarySource.get('Beneficial_Owner_Category__c')));
            fields.add(fieldEntry('relationshipWithEntity', beneficiarySource.get('Relationship_with_Entity__c')));
            fields.add(fieldEntry('relationshipType', beneficiarySource.get('Relationship_Type__c')));
            fields.add(fieldEntry('poaHolder', beneficiarySource.get('POA_Holder__c')));
            Object shareHoldingObj = beneficiarySource.get('ShareHolding__c');
            fields.add(fieldEntry('shareHolding', shareHoldingObj != null ? String.valueOf(shareHoldingObj) : ''));
        }

        // Primary applicant question: top-level non-borrower applicants only
        // (sub-applicants set their Primary via the tile switch, not this question).
        if (cachedApplicant != null) {
            String roleType = (String) cachedApplicant.get('Applicant_Type__c');
            Boolean isSubApp = cachedApplicant.get('Is_Sub_Applicant__c') == true;
            Boolean showPrimary = String.isNotBlank(roleType)
                && !'Borrower'.equalsIgnoreCase(roleType) && !isSubApp;
            fields.add(fieldEntry('showPrimaryQuestion', showPrimary));
            if (showPrimary) {
                fields.add(fieldEntry('primaryRoleLabel', roleType));
                Boolean primaryVal = cachedApplicant.get('Is_Primary__c') == true;
                if (!primaryVal) {
                    Integer roleCount = [
                        SELECT COUNT()
                        FROM Applicant__c
                        WHERE Application__c = :(Id) cachedApplicant.get('Application__c')
                        AND Applicant_Type__c = :roleType
                        AND Is_Sub_Applicant__c = false
                        AND In_Active_Applicant__c = false
                    ];
                    if (roleCount <= 1) primaryVal = true;   // sole member is implicitly Primary
                }
                fields.add(fieldEntry('isPrimary', primaryVal));
            }
        }
        return fields;
    }

    private static String resolveApplicationTypeValue(SObject applicant) {
        if (applicant != null) {
            String typeVal = (String) applicant.get('Type__c');
            if (String.isNotBlank(typeVal)) {
                return typeVal;
            }
        }
        return 'Individual';
    }

    private static Boolean isNonIndividualApplicantType(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String normalized = value.trim();
        return 'Non Individual'.equalsIgnoreCase(normalized)
            || 'Non-Individual'.equalsIgnoreCase(normalized)
            || 'NI'.equalsIgnoreCase(normalized);
    }

    private static Boolean isTwoWheelerProduct(String productType) {
        if (String.isBlank(productType)) {
            return false;
        }
        String pt = productType.trim().toLowerCase();
        return pt == '2w'
            || pt == 'tw'
            || pt.contains('two wheeler');
    }

    private static Boolean isCvProductType(String productType) {
        if (String.isBlank(productType)) {
            return false;
        }
        String pt = productType.trim().toLowerCase();
        // 'cv' is the umbrella Product__c code emitted by the Intermediate Page;
        // SCV/LCV/MHCE/CE are the specific sub-types. Must stay in sync with the
        // LWC isCvProductType() in applicantBasicDetailsCapture.js — a mismatch makes
        // the UI show Industry Name/Code while the save nulls them (or vice-versa).
        return pt == 'cv'
            || pt == 'scv'
            || pt == 'lcv'
            || pt == 'mhce'
            || pt == 'ce'
            || pt.contains('commercial vehicle')
            || pt.contains('commercial equipment');
    }

    private static Boolean isNonCvProductType(String productType) {
        return !isCvProductType(productType) && String.isNotBlank(productType);
    }

    private static void putEvaluationTypePicklistMetadata(Map<String, Object> result) {
        result.put('evaluationTypeOptions', GenericUtility.getActivePicklistOptions('Applicant__c', 'Evaluation_Type__c'));
    }

    private static void putBeneficiaryPicklistMetadata(Map<String, Object> result) {
        result.put('beneficialOwnerCategoryOptions', GenericUtility.getActivePicklistOptions('Applicant__c', 'Beneficial_Owner_Category__c'));
        result.put('relationshipWithEntityOptions', GenericUtility.getActivePicklistOptions('Applicant__c', 'Relationship_with_Entity__c'));
        result.put('relationshipTypeOptions', GenericUtility.getActivePicklistOptions('Applicant__c', 'Relationship_Type__c'));
    }

    private static void putEntityTypePicklistMetadata(Map<String, Object> result) {
        result.put('entityTypeOptions', GenericUtility.getActivePicklistOptions('Applicant__c', 'Entity_Type__c'));
    }

    /** Returns schema-active values for the Customer Type combobox (Applicant__c.Type__c). */
    private static void putCustomerTypePicklistMetadata(Map<String, Object> result) {
        result.put('customerTypeOptions', GenericUtility.getActivePicklistOptions('Applicant__c', 'Type__c'));
    }

    /** Returns schema-active values for the Occupation Category combobox (Applicant__c.Income_Category__c). */
    private static void putIncomeCategoryPicklistMetadata(Map<String, Object> result) {
        result.put('incomeCategoryOptions', GenericUtility.getActivePicklistOptions('Applicant__c', 'Income_Category__c'));
    }

    /** Returns schema-active values for the Gender combobox (Applicant__c.Gender__c). */
    private static void putGenderPicklistMetadata(Map<String, Object> result) {
        result.put('genderOptions', GenericUtility.getActivePicklistOptions('Applicant__c', 'Gender__c'));
    }

    private static void putIndustryPicklistMetadata(Map<String, Object> result) {
        result.put('majorIndustryOptions', buildMajorIndustryOptionsList());
        result.put('minorIndustryOptionsMap', buildMinorIndustryOptionsMap());
        Map<String, Object> industryCodeMasterData = buildIndustryCodeMasterData();
        result.put('industryNameOptions', industryCodeMasterData.get('options'));
        result.put('industryNameToCodeMap', industryCodeMasterData.get('nameToCode'));
    }

    private static List<Map<String, String>> buildMajorIndustryOptionsList() {
        return GenericUtility.getActivePicklistOptions('Applicant__c', 'Major_Industry__c');
    }

    private static Map<String, Object> buildMinorIndustryOptionsMap() {
        Map<String, Object> result = new Map<String, Object>();
        Map<String, List<Map<String, String>>> rawOptions = GenericUtility.fetchControlledByDependentToSchema(
            'Applicant__c',
            'Minor_Industry__c'
        );
        for (String majorValue : rawOptions.keySet()) {
            List<Map<String, String>> opts = rawOptions.get(majorValue);
            if (opts != null && !opts.isEmpty()) {
                result.put(majorValue, opts);
            }
        }
        return result;
    }

    private static Map<String, Object> buildIndustryCodeMasterData() {
        List<Map<String, String>> opts = new List<Map<String, String>>();
        Map<String, String> nameToCode = new Map<String, String>();
        try {
            for (SObject rec : Database.query(
                'SELECT Name, Industry_Code__c FROM Industry_Code_and_Type__c WHERE Name != NULL WITH SECURITY_ENFORCED ORDER BY Name ASC LIMIT 5000'
            )) {
                String name = (String) rec.get('Name');
                opts.add(new Map<String, String>{ 'label' => name, 'value' => name });
                nameToCode.put(name, rec.get('Industry_Code__c') == null ? '' : (String) rec.get('Industry_Code__c'));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ApplicantBasicDetailsCaptureController.buildIndustryCodeMasterData: ' + e.getMessage());
        }
        return new Map<String, Object>{
            'options' => opts,
            'nameToCode' => nameToCode
        };
    }

    private static void applyNonIndividualDocumentVerificationFieldRules(Map<String, Object> args, Boolean isNonIndividualApplicationType) {
        if (isNonIndividualApplicationType) {
            args.put('extractedFirstName', String.valueOf(args.get('entityName')));
            args.put('extractedLastName', null);
            args.put('extractedDateOfBirth', null);
        } else {
            args.put('dateOfIncorporation', null);
        }
    }

    private static void applyNonIndividualIncomeFieldRules(Map<String, Object> args, Boolean isNonIndividualApplicationType) {
        if (isNonIndividualApplicationType) {
            args.put('incomeAvailable', 'Yes');
        }
    }

    /** Forces Income_Category__c to NE when Income Available = No, and clears it for Non-Individual applicants. */
    private static void applyIncomeCategoryFieldRules(Map<String, Object> args, Boolean isNonIndividualApplicationType) {
        if (isNonIndividualApplicationType) {
            args.put('occupationCategory', null);
            return;
        }
        Object incomeAvailRaw = args.get('incomeAvailable');
        String incomeAvail = incomeAvailRaw == null ? '' : String.valueOf(incomeAvailRaw).trim();
        if ('No'.equalsIgnoreCase(incomeAvail)) {
            args.put('occupationCategory', 'Non-Earning');
        }
    }

    private static void applyNonIndividualContactInfoFieldRules(Map<String, Object> args, Boolean isNonIndividualApplicationType) {
        if (!isNonIndividualApplicationType) {
            args.put('contactPersonName', null);
            args.put('landlineNumber', null);
        }
    }

    private static void applyEvaluationTypeFieldRules(Map<String, Object> args, Boolean isNonIndividualApplicationType) {
        if (!isNonIndividualApplicationType) {
            args.put('evaluationType', null);
        }
    }

    private static void applyEntityTypeFieldRules(Map<String, Object> args, Boolean isNonIndividualApplicationType) {
        if (!isNonIndividualApplicationType) {
            args.put('applicantEntityType', null);
        }
    }

    private static void applyIndustryFieldRules(Map<String, Object> args, String productType, Boolean isNonIndividualApplicationType) {
        if (!isNonIndividualApplicationType) {
            args.put('majorIndustry', null);
            args.put('minorIndustry', null);
            args.put('industryName', null);
            args.put('industryCode', null);
            return;
        }
        if (isCvProductType(productType)) {
            args.put('majorIndustry', null);
            args.put('minorIndustry', null);
        } else if (isNonCvProductType(productType)) {
            args.put('industryName', null);
            args.put('industryCode', null);
        }
    }

    private List<Map<String, Object>> getContactInfoConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        if (cachedApplicant == null) {
            return fields;
        }
        fields.add(fieldEntry('maritalStatus', cachedApplicant.get('Marital_status__c')));
        fields.add(fieldEntry('residenceCountry', cachedApplicant.get('Residence_Country__c')));
        fields.add(fieldEntry('contactNumber', cachedApplicant.get('Phone__c')));
        fields.add(fieldEntry('email', cachedApplicant.get('Email__c')));
        fields.add(fieldEntry('contactPersonName', cachedApplicant.get('Contact_Person_Name__c')));
        fields.add(fieldEntry('landlineNumber', cachedApplicant.get('Landline_Number__c')));
        fields.add(fieldEntry('contactVerificationStatus', verificationStatus(cachedApplicant.get('Phone_Verified__c'))));
        fields.add(fieldEntry('emailVerificationStatus', verificationStatus(cachedApplicant.get('Email_Verified__c'))));
        fields.add(fieldEntry('applicationConsentReceived', cachedApplicant.get('Application_Consent_Received__c') == true));
        fields.add(fieldEntry('consentOtpVerified', isConsentOtpVerifiedMarker(cachedApplicant)));
        fields.add(fieldEntry('consentSent', isConsentLinkSharedMarker(cachedApplicant)));
        return fields;
    }

    private List<Map<String, Object>> getLoanBasicInfoConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        if (cachedApplication == null) {
            return fields;
        }
        String productType = (String) cachedApplication.get('Product__c');
        Object accountIdObj = cachedApplication.get('Branch__c');
        String accountId = accountIdObj != null ? String.valueOf(accountIdObj) : null;
        SObject relatedAccount = cachedApplication.getSObject('Branch__r');
        String accountName = relatedAccount != null ? (String) relatedAccount.get('Name') : null;
        String agentBranchName = deriveAgentBranchName(productType, accountId);
        String assetType = cachedAsset != null ? (String) cachedAsset.get('Vehicle_type__c') : null;
        String purposeOfPurchase = cachedAsset != null ? (String) cachedAsset.get('Purpose_of_purchase__c') : null;
        String leadNumber = (String) cachedApplication.get('Application_number__c');

        fields.add(fieldEntry('accountId', accountId));
        fields.add(fieldEntry('accountName', accountName));
        fields.add(fieldEntry('leadNumber', leadNumber));
        fields.add(fieldEntry('assetType', assetType));
        fields.add(fieldEntry('agentBranchName', String.isNotBlank(agentBranchName) ? agentBranchName : 'N/A'));
        fields.add(fieldEntry('purposeOfPurchase', purposeOfPurchase));
        return fields;
    }

    private List<Map<String, Object>> getLoanDetailConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        Object segmentObj = cachedAsset != null ? cachedAsset.get('Product_Segment__c') : null;
        String segment = segmentObj != null && String.isNotBlank(String.valueOf(segmentObj))
            ? String.valueOf(segmentObj) : '';
        Object reqLoanObj = cachedApplication != null ? cachedApplication.get('Total_Loan_Amount__c') : null;
        String requiredLoanAmount = reqLoanObj != null ? String.valueOf(reqLoanObj) : '';
        fields.add(fieldEntry('segment', segment));
        fields.add(fieldEntry('requiredLoanAmount', requiredLoanAmount));
        return fields;
    }

    private List<Map<String, Object>> getProfessionalDetailConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        if (cachedApplicant == null) {
            return fields;
        }
        Object annualIncomeObj = cachedApplicant.get('Declared_income__c');
        fields.add(fieldEntry('profileType', cachedApplicant.get('Profile__c')));
        fields.add(fieldEntry('incomeAvailable', cachedApplicant.get('Is_Income_Available__c')));
        fields.add(fieldEntry('annualIncome', annualIncomeObj != null ? String.valueOf(annualIncomeObj) : ''));
        fields.add(fieldEntry('occupationCategory', cachedApplicant.get('Income_Category__c')));
        return fields;
    }

    private List<Map<String, Object>> getDocumentVerificationConfig() {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        if (cachedApplication == null) {
            return fields;
        }
        loadLatestFileInfoForChecklists(new List<SObject>{
            cachedPanDocumentChecklist, cachedDocumentChecklist, cachedForm60DocumentChecklist
        });

        Map<String, Object> panUpload = buildUploadElement(cachedPanDocumentChecklist);
        if (panUpload == null) {
            panUpload = buildUploadElement(cachedDocumentChecklist);
        }
        Map<String, Object> form60Upload = buildUploadElement(cachedForm60DocumentChecklist);

        String storedPanCipher = cachedApplicant != null ? (String) cachedApplicant.get('PAN_Number__c') : '';
        if (String.isBlank(storedPanCipher) && cachedPanDocumentChecklist != null) {
            storedPanCipher = (String) cachedPanDocumentChecklist.get('PAN_No__c');
        }
        Boolean hasPanStored = String.isNotBlank(storedPanCipher);
        Object dobObj = cachedApplicant != null ? cachedApplicant.get('Date_of_Birth__c') : null;
        Object kycDobObj = cachedPanDocumentChecklist != null ? cachedPanDocumentChecklist.get('KYC_Date_of_Birth__c') : null;
        if (kycDobObj == null && cachedForm60DocumentChecklist != null) {
            kycDobObj = cachedForm60DocumentChecklist.get('KYC_Date_of_Birth__c');
        }
        Object effectiveDob = dobObj != null ? dobObj : kycDobObj;

        fields.add(fieldEntry('isPanAvailable', cachedApplicant != null ? cachedApplicant.get('Is_PAN_Available__c') : null));
        fields.add(fieldEntry('panCardUploadElement', panUpload));
        fields.add(fieldEntry('form60UploadElement', form60Upload));
        fields.add(fieldEntry('extractedFirstName', resolveExtractedFirstName()));
        fields.add(fieldEntry('extractedLastName', resolveExtractedLastName()));
        // Sourav Commented this block of code to fix the issue of pan card number not being displayed in the UI
        //fields.add(fieldEntry('extractedPanCardNumber', resolveDecryptedPan(storedPanCipher)));
        fields.add(fieldEntry('extractedPanCardNumber', storedPanCipher));
        fields.add(fieldEntry('extractedDateOfBirth', effectiveDob != null ? GenericUtility.parseDateValue(String.valueOf(effectiveDob)) : null));
        fields.add(fieldEntry('dateOfIncorporation', dobObj != null ? GenericUtility.parseDateValue(String.valueOf(dobObj)) : null));
        fields.add(fieldEntry('panAckNo', cachedForm60DocumentChecklist != null ? cachedForm60DocumentChecklist.get('PAN_ACK_No__c') : null));
        fields.add(fieldEntry('gender', resolveGenderValue()));
        Object panVerifiedObj = cachedApplicant != null ? cachedApplicant.get('PAN_Number_Verified__c') : null;
        Boolean panVerifiedFlag = panVerifiedObj instanceof Boolean && (Boolean) panVerifiedObj;
        fields.add(fieldEntry('pancardVerificationStatus', panVerifiedFlag ? 'success' : 'idle'));
        return fields;
    }

    /** Cache populated by loadLatestFileInfoForChecklists — keyed by Document_CheckList__c Id. */
    private Map<Id, Map<String, Object>> latestFileInfoByChecklistId;

    /**
     * Fetches the latest uploaded file (by SystemModstamp on ContentDocumentLink)
     * for every supplied Document_CheckList__c so buildUploadElement can render
     * the actual file name instead of the checklist record name. One SOQL covers
     * all checklists; safe to call with null entries in the list.
     */
    private void loadLatestFileInfoForChecklists(List<SObject> checklistRows) {
        latestFileInfoByChecklistId = new Map<Id, Map<String, Object>>();
        Set<Id> checklistIds = new Set<Id>();
        for (SObject row : checklistRows) {
            if (row != null && row.get('Id') != null) {
                checklistIds.add((Id) row.get('Id'));
            }
        }
        if (checklistIds.isEmpty()) return;

        // ContentDocumentLink ordered by most recent first; first hit per
        // LinkedEntityId wins so each checklist resolves to its latest file.
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId,
                   ContentDocumentId,
                   ContentDocument.LatestPublishedVersion.Id,
                   ContentDocument.LatestPublishedVersion.Title,
                   ContentDocument.LatestPublishedVersion.FileExtension,
                   ContentDocument.LatestPublishedVersion.PathOnClient
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :checklistIds
            ORDER BY SystemModstamp DESC
        ]) {
            if (latestFileInfoByChecklistId.containsKey(cdl.LinkedEntityId)) continue;
            String title = (String) cdl.ContentDocument?.LatestPublishedVersion?.Title;
            String ext   = (String) cdl.ContentDocument?.LatestPublishedVersion?.FileExtension;
            String path  = (String) cdl.ContentDocument?.LatestPublishedVersion?.PathOnClient;
            // Prefer PathOnClient (already has extension); otherwise compose title.ext.
            String fileName;
            if (String.isNotBlank(path)) {
                fileName = path;
            } else if (String.isNotBlank(title)) {
                fileName = String.isNotBlank(ext) ? (title + '.' + ext) : title;
            }
            if (String.isBlank(fileName)) continue;
            latestFileInfoByChecklistId.put(cdl.LinkedEntityId, new Map<String, Object>{
                'fileName' => fileName,
                'contentVersionId' => (String) cdl.ContentDocument?.LatestPublishedVersion?.Id,
                'contentDocumentId' => (String) cdl.ContentDocumentId
            });
        }
    }

    /** Builds the UI upload element payload from a Document_CheckList__c row. */
    private Map<String, Object> buildUploadElement(SObject row) {
        if (row == null) {
            return null;
        }
        Id checklistId = (Id) row.get('Id');
        Map<String, Object> latest = latestFileInfoByChecklistId != null
            ? latestFileInfoByChecklistId.get(checklistId)
            : null;

        String fileName = (latest != null) ? (String) latest.get('fileName') : null;
        String contentVersionId = (latest != null)
            ? (String) latest.get('contentVersionId')
            : (String) row.get('ContentVersionId__c');
        // Surface contentDocumentId so the LWC preview button (eye icon) renders
        // on read-only / past-stage views too, not only after a fresh upload.
        String contentDocumentId = (latest != null) ? (String) latest.get('contentDocumentId') : null;
        if (String.isBlank(fileName)) {
            fileName = (String) row.get('Name');
        }
        return new Map<String, Object>{
            'fileName' => fileName,
            'contentVersionId' => contentVersionId,
            'contentDocumentId' => contentDocumentId,
            'documentChecklistId' => checklistId
        };
    }

    private String resolveExtractedFirstName() {
        String fromApplicant = cachedApplicant != null ? (String) cachedApplicant.get('Customer_First_Name__c') : null;
        if (String.isNotBlank(fromApplicant)) {
            return fromApplicant;
        }
        if (cachedPanDocumentChecklist != null) {
            return (String) cachedPanDocumentChecklist.get('First_Name__c');
        }
        if (cachedForm60DocumentChecklist != null) {
            return (String) cachedForm60DocumentChecklist.get('First_Name__c');
        }
        return null;
    }

    private String resolveExtractedLastName() {
        String fromApplicant = cachedApplicant != null ? (String) cachedApplicant.get('Customer_Last_Name__c') : null;
        if (String.isNotBlank(fromApplicant)) {
            return fromApplicant;
        }
        if (cachedPanDocumentChecklist != null) {
            return (String) cachedPanDocumentChecklist.get('Last_Name__c');
        }
        if (cachedForm60DocumentChecklist != null) {
            return (String) cachedForm60DocumentChecklist.get('Last_Name__c');
        }
        return null;
    }

    /** Decrypts the stored PAN cipher for UI display. Falls back gracefully when blank or undecryptable. */
    // private static String resolveDecryptedPan(String cipher) {
    //     if (String.isBlank(cipher)) {
    //         return '';
    //     }
    //     try {
    //         String plain = IntegrationUtility.decryptMessage(cipher);
    //         return plain == null ? '' : plain.trim().toUpperCase();
    //     } catch (Exception e) {
    //         System.debug(LoggingLevel.WARN, 'ApplicantBasicDetailsCaptureController.resolveDecryptedPan: ' + e.getMessage());
    //         return '';
    //     }
    // }

    private String resolveGenderValue() {
        String fromApplicant = cachedApplicant != null ? (String) cachedApplicant.get('Gender__c') : null;
        if (String.isNotBlank(fromApplicant)) {
            return fromApplicant;
        }
        if (cachedForm60DocumentChecklist != null) {
            return (String) cachedForm60DocumentChecklist.get('Gender__c');
        }
        if (cachedPanDocumentChecklist != null) {
            return (String) cachedPanDocumentChecklist.get('Gender__c');
        }
        return null;
    }

    private static Map<String, Object> fieldEntry(String key, Object value) {
        return new Map<String, Object>{ 'key' => key, 'value' => value };
    }

    private static String verificationStatus(Object verifiedField) {
        if (verifiedField instanceof Boolean && (Boolean) verifiedField) {
            return 'success';
        }
        return 'idle';
    }

    private void loadCachedData(Id recordId, Map<String, Object> args) {
        cachedApplication = queryApplication(recordId);
        cachedBorrowerApplicant = queryBorrowerApplicant(recordId);
        Id applicantId = parseApplicantId(args);
        if (applicantId != null) {
            cachedApplicant = queryApplicantById(applicantId, recordId);
            isBeneficiaryApplicantContext = isBeneficiaryApplicant(cachedApplicant);
        } else if (countActiveApplicants(recordId) <= 1) {
            // Genuine single-applicant case (initial Borrower load) — Borrower is the only context.
            cachedApplicant = cachedBorrowerApplicant;
            isBeneficiaryApplicantContext = false;
        } else {
            // Multiple applicants exist but the LWC did not pass an applicantId. 
            throw new AuraHandledException(
                'Applicant context is missing. Please reselect the applicant from the menu and try again.');
        }
        if (cachedAsset == null) {
            cachedAsset = getPrimaryAsset(recordId, cachedBorrowerApplicant != null ? cachedBorrowerApplicant.Id : null);
        }
        cachedPrimaryLineItem = queryPrimaryLineItem(recordId);
        Id documentApplicantId = cachedApplicant != null ? (Id) cachedApplicant.get('Id') : null;
        cachedDocumentChecklist = documentApplicantId != null ? queryDocumentChecklist(documentApplicantId) : null;
        cachedPanDocumentChecklist = documentApplicantId != null ? queryDocumentChecklistByType(documentApplicantId, DOC_TYPE_PAN) : null;
        cachedForm60DocumentChecklist = documentApplicantId != null ? queryDocumentChecklistByType(documentApplicantId, DOC_TYPE_FORM_60) : null;
    }

    /** Reads the first Application_Line_Item__c row for read-side display (Number of Vehicles, etc.). */
    private SObject queryPrimaryLineItem(Id applicationId) {
        if (applicationId == null) {
            return null;
        }
        List<SObject> rows = Database.query(
            'SELECT ' + LINE_ITEM_SELECT + ' FROM Application_Line_Item__c WHERE Application__c = :applicationId WITH SECURITY_ENFORCED ORDER BY CreatedDate ASC LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0];
    }

    private static Id parseApplicantId(Map<String, Object> args) {
        if (args == null || !args.containsKey('applicantId')) {
            return null;
        }
        Object raw = args.get('applicantId');
        if (raw == null) {
            return null;
        }
        String str = String.valueOf(raw).trim();
        if (String.isBlank(str)) {
            return null;
        }
        try {
            return (Id) str;
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean isBeneficiaryApplicant(SObject applicant) {
        if (applicant == null) {
            return false;
        }
        String tabLabel = (String) applicant.get('Applicant_Tab_Label__c');
        if (String.isNotBlank(tabLabel) && tabLabel.trim().toLowerCase().startsWith('b')) {
            return true;
        }
        String applicantType = (String) applicant.get('Applicant_Type__c');
        return 'Beneficiary'.equalsIgnoreCase(applicantType);
    }

    private SObject queryApplication(Id recordId) {
        List<SObject> listApplication = Database.query(
            'SELECT ' + APPLICATION_SELECT + ' FROM Application__c WHERE Id = :recordId WITH SECURITY_ENFORCED LIMIT 1'
        );
        return listApplication.isEmpty() ? null : listApplication[0];
    }

    /** Active applicant count for the application */
    private Integer countActiveApplicants(Id recordId) {
        return [
            SELECT COUNT()
            FROM Applicant__c
            WHERE Application__c = :recordId AND In_Active_Applicant__c = false
            WITH SECURITY_ENFORCED
        ];
    }

    private SObject queryBorrowerApplicant(Id recordId) {
        List<SObject> listApplicant = Database.query(
            'SELECT ' + APPLICANT_SELECT + ' FROM Applicant__c WHERE Applicant_Type__c = \'Borrower\' AND Application__c = :recordId AND In_Active_Applicant__c = false WITH SECURITY_ENFORCED LIMIT 1'
        );
        return listApplicant.isEmpty() ? null : listApplicant[0];
    }

    private SObject queryApplicantById(Id applicantId, Id recordId) {
        // Load active applicants normally, PLUS a not-yet-exposed backend shell (a freshly
        // created sub-applicant shell being filled on Basic Details, before NEXT activates it).
        // Without this, the inactive shell returned nothing -> cachedApplicant was null -> the
        // code fell back to the Borrower/top-level applicant, pre-filling the sub's Basic Details
        // with the parent's (NI) data and locking it read-only.
        //
        // Is_Journey_Exposed__c cleanly separates a backend shell from a soft-deleted applicant:
        //   - shell (sub or clone, pre-activation): In_Active = true,  Is_Journey_Exposed = false  -> load
        //   - soft-deleted (Remove Applicant):      In_Active = true,  Is_Journey_Exposed = true   -> skip
        //   - normal/active:                        In_Active = false, Is_Journey_Exposed = true   -> load
        List<SObject> listApplicant = Database.query(
            'SELECT ' + APPLICANT_SELECT + ' FROM Applicant__c ' +
            'WHERE Id = :applicantId AND Application__c = :recordId ' +
            'AND ( In_Active_Applicant__c = false OR Is_Journey_Exposed__c = false ) ' +
            'WITH SECURITY_ENFORCED LIMIT 1'
        );
        return listApplicant.isEmpty() ? null : listApplicant[0];
    }

    private SObject queryDocumentChecklist(Id recordId) {
        List<SObject> listDoc = Database.query(
            'SELECT Id, ContentVersionId__c, Name FROM Document_Checklist__c WHERE Applicant__c = :recordId AND Document_Type__c = \'PAN\' LIMIT 1'
        );
        return listDoc.isEmpty() ? null : listDoc[0];
    }

    /** Reads the active (or most recent) Document_CheckList__c row for a specific document type. */
    private SObject queryDocumentChecklistByType(Id applicantId, String documentType) {
        if (applicantId == null || String.isBlank(documentType)) {
            return null;
        }
        List<SObject> rows = Database.query(
            'SELECT Id, Name, ContentVersionId__c, Document_Type__c, Is_Active__c, First_Name__c, Last_Name__c, PAN_No__c, PAN_ACK_No__c, Gender__c, KYC_Date_of_Birth__c ' +
            'FROM Document_Checklist__c ' +
            'WHERE Applicant__c = :applicantId AND Document_Type__c = :documentType ' +
            'WITH SECURITY_ENFORCED ' +
            'ORDER BY Is_Active__c DESC, LastModifiedDate DESC LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0];
    }

    /** Composes the Agent Branch Name from the Account's Branch_Code__c + State__c.
     *  Falls back gracefully when either field is missing on the running org. */
    private String deriveAgentBranchName(String productType, String accountId) {
        if (String.isBlank(accountId)) {
            return 'N/A';
        }
        Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
        List<String> selectFields = new List<String>();
        if (accountFields.containsKey('branch_code__c')) selectFields.add('Branch_Code__c');
        if (accountFields.containsKey('state__c'))       selectFields.add('State__c');
        if (selectFields.isEmpty()) {
            return 'N/A';
        }
        try {
            String soql = 'SELECT ' + String.join(selectFields, ', ')
                + ' FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1';
            List<SObject> accounts = Database.query(soql);
            if (accounts.isEmpty()) {
                return 'N/A';
            }
            SObject acc = accounts[0];
            String branchCode = accountFields.containsKey('branch_code__c')
                ? (String) acc.get('Branch_Code__c') : null;
            String state = accountFields.containsKey('state__c')
                ? (String) acc.get('State__c') : null;
            List<String> parts = new List<String>();
            if (String.isNotBlank(branchCode)) parts.add(branchCode);
            if (String.isNotBlank(state))      parts.add(state);
            return parts.isEmpty() ? 'N/A' : String.join(parts, ' - ');
        } catch (Exception e) {
            return 'N/A';
        }
    }

    private Map<String, Object> saveApplicantPageDataInternal(Map<String, Object> args) {
        Id recordId = (Id) args.get('recordId');
        if (recordId == null) {
            return new Map<String, Object>{ 'isSuccess' => false, 'message' => 'Record ID is required' };
        }
        Id applicationLineItemId = null;
        Id assetRecordId = null;
        try {
            loadCachedData(recordId, args);
            List<SObject> toUpdate = new List<SObject>();

            String productType = cachedApplication != null ? (String) cachedApplication.get('Product__c') : null;
            String applicationType = args.containsKey('applicationType') ? String.valueOf(args.get('applicationType')) : null;
            if (String.isBlank(applicationType)) {
                applicationType = 'Individual';
            }
            if (isTwoWheelerProduct(productType)) {
                applicationType = 'Individual';
                args.put('customerType', 'Individual');
            }
            // Sub-applicants are always Individual; lock it regardless of the inbound value.
            if (cachedApplicant != null && cachedApplicant.get('Is_Sub_Applicant__c') == true) {
                applicationType = 'Individual';
                args.put('customerType', 'Individual');
            }
            args.put('applicationType', applicationType);
            Boolean isNonIndividualApplicationType = isNonIndividualApplicantType(applicationType);
            if (!isNonIndividualApplicationType) {
                args.put('customerType', 'Individual');
            } else {
                String customerType = args.containsKey('customerType') ? String.valueOf(args.get('customerType')) : null;
                if (String.isBlank(customerType)) {
                    customerType = 'Non-Individual';
                }
                args.put('customerType', customerType);
            }
            applyIndustryFieldRules(args, productType, isNonIndividualApplicationType);
            applyEntityTypeFieldRules(args, isNonIndividualApplicationType);
            applyEvaluationTypeFieldRules(args, isNonIndividualApplicationType);
            applyNonIndividualIncomeFieldRules(args, isNonIndividualApplicationType);
            applyIncomeCategoryFieldRules(args, isNonIndividualApplicationType);
            applyNonIndividualDocumentVerificationFieldRules(args, isNonIndividualApplicationType);
            applyNonIndividualContactInfoFieldRules(args, isNonIndividualApplicationType);

            if (cachedApplication != null) {
                applyFieldValues(cachedApplication, args, APPLICATION_FIELD_MAP, 'Application__c');
                toUpdate.add(cachedApplication);
            }
            if (cachedApplicant != null) {
                if (isNonIndividualApplicationType && args.containsKey('entityName') && String.isNotBlank(String.valueOf(args.get('entityName')))) {
                    cachedApplicant.put('Company_Name__c', String.valueOf(args.get('entityName')));
                }
                if (isBeneficiaryApplicantContext) {
                    applyFieldValues(cachedApplicant, args, BENEFICIARY_FIELD_MAP, 'Applicant__c');
                }
                applyFieldValues(cachedApplicant, args, APPLICANT_FIELD_MAP, 'Applicant__c');
                if (isBorrowerSaveContext()) {
                    cachedApplicant.put('Applicant_Type__c', 'Borrower');
                }
                toUpdate.add(cachedApplicant);
            }

            if (isBorrowerSaveContext()) {
                Id borrowerId = cachedBorrowerApplicant != null ? (Id) cachedBorrowerApplicant.get('Id') : null;
                Map<String, Id> assetLineItemResult = upsertPrimaryAssetAndLineItem(recordId, borrowerId, args);
                applicationLineItemId = assetLineItemResult.get('lineItemId');
                assetRecordId = assetLineItemResult.get('assetId');
            } else if (cachedAsset != null) {
                applyFieldValues(cachedAsset, args, ASSET_FIELD_MAP, 'Asset__c');
                toUpdate.add(cachedAsset);
            }
            if (cachedDocumentChecklist != null) {
                extractFileFieldsToArgs(args, 'panCardUploadElement');
                applyFieldValues(cachedDocumentChecklist, args, DOCUMENT_CHECKLIST_MAP, 'Document_Checklist__c');
                toUpdate.add(cachedDocumentChecklist);
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
            upsertDocumentChecklistRows(args, recordId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ApplicantBasicDetailsCaptureController.saveApplicantPageDataInternal: ' + e.getMessage());
            return new Map<String, Object>{ 'isSuccess' => false, 'message' => e.getMessage() };
        }
        Map<String, Object> successResult = new Map<String, Object>{
            'isSuccess' => true,
            'message' => 'APPLICANT page data saved successfully'
        };
        if (applicationLineItemId != null) {
            successResult.put('applicationLineItemId', applicationLineItemId);
        }
        if (assetRecordId != null) {
            successResult.put('assetId', assetRecordId);
        }
        return successResult;
    }

    private Boolean isBorrowerSaveContext() {
        if ((cachedBorrowerApplicant == null) || (cachedApplicant != null && cachedApplicant.get('Applicant_Type__c') != 'Borrower') || (cachedBorrowerApplicant != null && cachedBorrowerApplicant.get('Applicant_Type__c') != 'Borrower')) {
            return false;
        }
        return true;
    }

    private Map<String, Id> upsertPrimaryAssetAndLineItem(Id applicationId, Id borrowerId, Map<String, Object> args) {
        Application_Line_Item__c primaryLineItem = getPrimaryLineItem(applicationId);
        Asset__c primaryAsset = getPrimaryAsset(applicationId, borrowerId, primaryLineItem);
        Id lineItemId = savePrimaryLineItem(applicationId, primaryLineItem, primaryAsset, args);
        primaryAsset = savePrimaryAsset(primaryAsset, lineItemId, borrowerId, args);

        cachedAsset = primaryAsset;
        return new Map<String, Id>{
            'lineItemId' => lineItemId,
            'assetId' => primaryAsset.Id
        };
    }

    private Asset__c getPrimaryAsset(Id applicationId, Id borrowerId) {
        return getPrimaryAsset(applicationId, borrowerId, getPrimaryLineItem(applicationId));
    }

    private Asset__c getPrimaryAsset(Id applicationId, Id borrowerId, Application_Line_Item__c primaryLineItem) {
        if (cachedAsset != null && cachedAsset.get('Id') != null) {
            return (Asset__c) cachedAsset;
        }
        if (applicationId == null) {
            return null;
        }

        String primaryLineItemId = (primaryLineItem != null && primaryLineItem.Id != null)
            ? String.valueOf(primaryLineItem.Id)
            : null;
        if (String.isNotBlank(primaryLineItemId)) {
            List<Asset__c> linkedAssets = Database.query(
                'SELECT ' + VEHICLE_SELECT + ' FROM Asset__c WHERE Application_Line_Items__c = :primaryLineItemId WITH SECURITY_ENFORCED LIMIT 1'
            );
            if (!linkedAssets.isEmpty()) {
                return linkedAssets[0];
            }
        }

        if (borrowerId != null) {
            List<Asset__c> unlinkedAssets = Database.query(
                'SELECT ' + VEHICLE_SELECT + ' FROM Asset__c WHERE Applicant__c = :borrowerId AND Application_Line_Items__c = null WITH SECURITY_ENFORCED ORDER BY CreatedDate ASC LIMIT 1'
            );
            if (!unlinkedAssets.isEmpty()) {
                return unlinkedAssets[0];
            }
        }

        return null;
    }

    private Application_Line_Item__c getPrimaryLineItem(Id applicationId) {
        List<Application_Line_Item__c> lineItems = [
            SELECT Id, Customer_Requested_Loan_Amount__c
            FROM Application_Line_Item__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return lineItems.isEmpty() ? null : lineItems[0];
    }

    private Id savePrimaryLineItem(
        Id applicationId,
        Application_Line_Item__c primaryLineItem,
        Asset__c primaryAsset,
        Map<String, Object> args
    ) {
        Application_Line_Item__c lineItem = primaryLineItem;
        if (lineItem == null && primaryAsset != null && primaryAsset.Application_Line_Items__c != null) {
            List<Application_Line_Item__c> linkedLineItems = [
                SELECT Id, Customer_Requested_Loan_Amount__c
                FROM Application_Line_Item__c
                WHERE Id = :primaryAsset.Application_Line_Items__c
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            lineItem = linkedLineItems.isEmpty() ? null : linkedLineItems[0];
        }

        if (lineItem == null) {
            lineItem = new Application_Line_Item__c(Application__c = applicationId);
            applyApplicationLineItemFields(lineItem, args);
            insert lineItem;
            return lineItem.Id;
        }

        applyApplicationLineItemFields(lineItem, args);
        update lineItem;
        return lineItem.Id;
    }

    private Asset__c savePrimaryAsset(Asset__c primaryAsset, Id lineItemId, Id borrowerId, Map<String, Object> args) {
        if (primaryAsset != null && primaryAsset.Id != null) {
            linkAssetToBorrower(primaryAsset, lineItemId, borrowerId);
            applyFieldValues(primaryAsset, args, ASSET_FIELD_MAP, 'Asset__c');
            update primaryAsset;
            return primaryAsset;
        }

        Asset__c newAsset = new Asset__c();
        linkAssetToBorrower(newAsset, lineItemId, borrowerId);
        applyFieldValues(newAsset, args, ASSET_FIELD_MAP, 'Asset__c');
        insert newAsset;
        return newAsset;
    }

    private void applyApplicationLineItemFields(Application_Line_Item__c lineItem, Map<String, Object> args) {
        if (lineItem == null || args == null || !args.containsKey('requiredLoanAmount')) {
            return;
        }
        Object rawAmount = args.get('requiredLoanAmount');
        if (rawAmount == null || String.isBlank(String.valueOf(rawAmount))) {
            return;
        }
        lineItem.Customer_Requested_Loan_Amount__c = Decimal.valueOf(String.valueOf(rawAmount));
    }

    private void linkAssetToBorrower(Asset__c asset, Id applicationLineItemId, Id borrowerId) {
        if (asset == null) {
            return;
        }
        if (applicationLineItemId != null) {
            asset.Application_Line_Items__c = applicationLineItemId;
        }
        if (borrowerId != null) {
            asset.Applicant__c = borrowerId;
        }
    }

    /** Inserts or updates the PAN + Form 60 Document_CheckList__c rows. Either path can be active per applicant. */
    private void upsertDocumentChecklistRows(Map<String, Object> args, Id applicationId) {
        Id applicantId = cachedApplicant != null ? (Id) cachedApplicant.get('Id') : null;
        if (applicantId == null) {
            return;
        }
        extractFileFieldsToArgs(args, 'panCardUploadElement');
        extractFileFieldsToArgsAs(args, 'form60UploadElement', 'form60ContentVersionId', 'form60DocumentName');

        if (cachedPanDocumentChecklist == null) {
            cachedPanDocumentChecklist = queryDocumentChecklistByType(applicantId, DOC_TYPE_PAN);
        }
        if (cachedForm60DocumentChecklist == null) {
            cachedForm60DocumentChecklist = queryDocumentChecklistByType(applicantId, DOC_TYPE_FORM_60);
        }

        String isPanAvailable = args.containsKey('isPanAvailable') ? String.valueOf(args.get('isPanAvailable')) : null;
        Boolean panActive = isPanAvailable == null || 'Yes'.equalsIgnoreCase(isPanAvailable);

        if (panActive) {
            persistDocumentChecklistRow(cachedPanDocumentChecklist, args, PAN_CHECKLIST_FIELD_MAP, applicantId, applicationId, DOC_TYPE_PAN, true);
            if (cachedForm60DocumentChecklist != null) {
                deactivateExistingRow(cachedForm60DocumentChecklist);
            }
        } else {
            persistDocumentChecklistRow(cachedForm60DocumentChecklist, args, FORM60_CHECKLIST_FIELD_MAP, applicantId, applicationId, DOC_TYPE_FORM_60, true);
            if (cachedPanDocumentChecklist != null) {
                deactivateExistingRow(cachedPanDocumentChecklist);
            }
        }
    }

    private void persistDocumentChecklistRow(SObject existing, Map<String, Object> args, Map<String, String> fieldMap,
            Id applicantId, Id applicationId, String documentType, Boolean markActive) {
        Boolean isInsert = existing == null;
        SObject row = isInsert ? Schema.getGlobalDescribe().get('Document_Checklist__c').newSObject() : existing;
        if (isInsert) {
            row.put('Applicant__c', applicantId);
            row.put('Application__c', applicationId);
            row.put('Document_Type__c', documentType);
        }
        if (markActive) {
            row.put('Is_Active__c', true);
        }
        applyFieldValues(row, args, fieldMap, 'Document_Checklist__c');
        if (isInsert) {
            insert row;
            if (documentType == DOC_TYPE_PAN) {
                cachedPanDocumentChecklist = row;
            } else if (documentType == DOC_TYPE_FORM_60) {
                cachedForm60DocumentChecklist = row;
            }
        } else {
            update row;
        }
    }

    private static void deactivateExistingRow(SObject row) {
        if (row == null) {
            return;
        }
        Boolean current = row.get('Is_Active__c') instanceof Boolean && (Boolean) row.get('Is_Active__c');
        if (!current) {
            return;
        }
        row.put('Is_Active__c', false);
        update row;
    }

    /** Variant of extractFileFieldsToArgs that lets the caller choose alternate destination keys. */
    private void extractFileFieldsToArgsAs(Map<String, Object> args, String fileFieldKey, String cvKeyOut, String nameKeyOut) {
        Object fileVal = args.get(fileFieldKey);
        if (fileVal == null) {
            return;
        }
        Map<String, Object> fileMap = null;
        if (fileVal instanceof Map<String, Object>) {
            fileMap = (Map<String, Object>) fileVal;
        } else {
            try {
                String jsonStr = fileVal instanceof String ? (String) fileVal : JSON.serialize(fileVal);
                fileMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
            } catch (Exception e) {
                return;
            }
        }
        if (fileMap == null) {
            return;
        }
        Object cvId = fileMap.get('contentVersionId');
        if (cvId != null && String.isNotBlank(String.valueOf(cvId))) {
            args.put(cvKeyOut, String.valueOf(cvId));
        }
        Object fName = fileMap.get('fileName');
        if (fName != null && String.isNotBlank(String.valueOf(fName))) {
            args.put(nameKeyOut, String.valueOf(fName));
        }
    }

    private void extractFileFieldsToArgs(Map<String, Object> args, String fileFieldKey) {
        Object fileVal = args.get(fileFieldKey);
        if (fileVal == null) {
            return;
        }
        Map<String, Object> fileMap = null;
        if (fileVal instanceof Map<String, Object>) {
            fileMap = (Map<String, Object>) fileVal;
        } else {
            try {
                String jsonStr = fileVal instanceof String ? (String) fileVal : JSON.serialize(fileVal);
                fileMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
            } catch (Exception e) {
                return;
            }
        }
        if (fileMap != null) {
            Object cvId = fileMap.get('contentVersionId');
            if (cvId != null && String.isNotBlank(String.valueOf(cvId))) {
                args.put('contentVersionId', String.valueOf(cvId));
            }
            Object fName = fileMap.get('fileName');
            if (fName != null && String.isNotBlank(String.valueOf(fName))) {
                args.put('documentName', String.valueOf(fName));
            }
        }
    }

    private void applyFieldValues(SObject record, Map<String, Object> args, Map<String, String> fieldMap, String objectName) {
        if (record == null || args == null || fieldMap == null) {
            return;
        }
        Map<String, Schema.SObjectField> schemaFields = Schema.getGlobalDescribe()
            .get(objectName).getDescribe().fields.getMap();

        for (String jsonKey : fieldMap.keySet()) {
            if (!args.containsKey(jsonKey)) {
                continue;
            }
            String fieldApiName = fieldMap.get(jsonKey);
            Schema.SObjectField sField = schemaFields.get(fieldApiName.toLowerCase());
            if (sField == null) {
                continue;
            }
            Schema.DescribeFieldResult dfr = sField.getDescribe();
            Boolean isInsert = record.get('Id') == null;
            if (isInsert ? !dfr.isCreateable() : !dfr.isUpdateable()) {
                continue;
            }
            record.put(dfr.getName(), convertValue(args.get(jsonKey), dfr.getType()));
        }
    }

    private Object convertValue(Object rawValue, Schema.DisplayType fieldType) {
        if (rawValue == null) {
            return null;
        }
        String strValue = String.valueOf(rawValue);
        if (String.isBlank(strValue)) {
            return null;
        }
        switch on fieldType {
            when CURRENCY, DOUBLE, PERCENT {
                return Decimal.valueOf(strValue);
            }
            when INTEGER {
                return Integer.valueOf(strValue);
            }
            when DATE {
                return GenericUtility.parseDateValue(strValue);
            }
            when DATETIME {
                return Datetime.valueOf(strValue);
            }
            when BOOLEAN {
                return Boolean.valueOf(strValue);
            }
            when else {
                return strValue;
            }
        }
    }

    /**
     * Updates (or creates) the Document_Checklist__c row for a PAN/Form 60 upload.
     * When docChecklistId is blank, applicantId is used to find or insert the row.
     */
    @AuraEnabled
    public static Map<String, Object> updateDocumentChecklist(
            Id docChecklistId,
            String documentType,
            String contentVersionId,
            String contentDocumentId,
            Id applicantId) {
        try {
            Id resolvedId = docChecklistId;
            if (resolvedId == null) {
                resolvedId = resolveOrCreateDocumentChecklistId(applicantId, documentType);
            }
            if (resolvedId == null) {
                throw new AuraHandledException('Document checklist Id or applicant Id is required');
            }
            Document_Checklist__c docChecklist = new Document_Checklist__c(
                Id = resolvedId,
                Document_Type__c = documentType,
                ContentVersionId__c = contentVersionId,
                Is_Active__c = true
            );
            update docChecklist;
            return new Map<String, Object>{
                'isSuccess' => true,
                'documentChecklistId' => resolvedId
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    private static Id resolveOrCreateDocumentChecklistId(Id applicantId, String documentType) {
        if (applicantId == null || String.isBlank(documentType)) {
            return null;
        }
        List<Document_Checklist__c> rows = [
            SELECT Id
            FROM Document_Checklist__c
            WHERE Applicant__c = :applicantId AND Document_Type__c = :documentType
            WITH SECURITY_ENFORCED
            ORDER BY Is_Active__c DESC, LastModifiedDate DESC
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            return rows[0].Id;
        }
        List<Applicant__c> apps = [
            SELECT Application__c
            FROM Applicant__c
            WHERE Id = :applicantId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return null;
        }
        Document_Checklist__c row = new Document_Checklist__c(
            Applicant__c = applicantId,
            Application__c = apps[0].Application__c,
            Document_Type__c = documentType,
            Is_Active__c = true
        );
        insert row;
        return row.Id;
    }

    /**
     * Saves the PAN details for the applicant.
     * @param applicantId - The ID of the applicant.
     * @param panCardNumber - The PAN number of the applicant.
     * @param dateOfBirth - The date of birth of the applicant.
     * @param firstName - The first name of the applicant.
     * @param lastName - The last name of the applicant.
     * @return - A map containing the status of the operation and the message.
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> savePANDetails(String applicantId, String panCardNumber, String dateOfBirth, String firstName, String lastName) {
        try {
            Applicant__c applicant = new Applicant__c(Id = applicantId, PAN_Number__c = panCardNumber, Date_of_Birth__c = Date.valueOf(dateOfBirth), Customer_First_Name__c = firstName, Customer_Last_Name__c = lastName);
            // Stamp a readable applicant Name from the PAN-section first/last name in the same DML.
            String stampedName = ((String.isNotBlank(firstName) ? firstName.trim() : '') + ' ' + (String.isNotBlank(lastName) ? lastName.trim() : '')).trim();
            if (String.isNotBlank(stampedName)) {
                applicant.Name = stampedName.length() > 80 ? stampedName.substring(0, 80) : stampedName;
            }
            update applicant;
            return new Map<String, Object>{ 'isSuccess' => true, 'message' => 'PAN details saved successfully' };
        }
        catch (Exception e) {
            return new Map<String, Object>{ 'isSuccess' => false, 'message' => e.getMessage()};
        }
    }

    /**
     * Gets the integration master record for the given integration name.
     * @param integrationName - The name of the integration.
     * @return - The component reference for the given integration name.
     */
    @AuraEnabled
    public static Integration_Master__c getIntegrationMaster(String integrationName) {
        return [SELECT Id, Name, Component_Reference__c FROM Integration_Master__c WHERE Name =: integrationName LIMIT 1];
    }

    private static final String CONSENT_SITE_NAME = 'CustomerService';
    private static final String CONSENT_VF_PAGE = 'ApplicationConsent';

    private static Boolean isConsentOtpVerifiedMarker(SObject applicant) {
        if (applicant == null) {
            return false;
        }
        if (applicant.get('Consent_Sent__c') != null) {
            return true;
        }
        return applicant.get('Application_Consent_Received__c') == true;
    }

    /** Agent shared the consent link (distinct from customer OTP verified via Consent_Sent__c). */
    private static Boolean isConsentLinkSharedMarker(SObject applicant) {
        if (applicant == null) {
            return false;
        }
        if (applicant.get('Applicant_Consent_Received_Date__c') != null) {
            return true;
        }
        return applicant.get('Application_Consent_Received__c') == true;
    }

    /** Builds the customer-facing ApplicationConsent VF page URL. */
    @AuraEnabled
    public static String getConsentSiteUrl(String applicantId, String loanId) {
        if (String.isBlank(applicantId)) {
            return null;
        }
        Map<String, Object> resolved = resolveConsentSiteBase();
        String baseUrl = (String) resolved.get('baseUrl');
        Boolean isSite = (Boolean) resolved.get('isSiteUrl');
        String pagePath = isSite
            ? '/' + CONSENT_VF_PAGE
            : '/apex/' + CONSENT_VF_PAGE;

        String params = '?applicantId=' + EncodingUtil.urlEncode(applicantId, 'UTF-8');
        if (String.isNotBlank(loanId)) {
            params += '&loanId=' + EncodingUtil.urlEncode(loanId, 'UTF-8');
        }
        params += '&v=' + EncodingUtil.urlEncode(String.valueOf(System.now().getTime()), 'UTF-8');
        return baseUrl + pagePath + params;
    }

    /** Stamps link-shared date and resets stale Consent_Sent__c so customer OTP is required on VF. */
    @AuraEnabled
    public static Map<String, Object> recordConsentFormSent(String applicantId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        try {
            if (String.isBlank(applicantId)) {
                throw new AuraHandledException('Applicant context is missing.');
            }
            List<Applicant__c> rows = [
                SELECT Id,
                       Applicant_Consent_Received_Date__c,
                       Application_Consent_Received__c,
                       Consent_Sent__c
                FROM Applicant__c
                WHERE Id = :applicantId
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('Applicant record was not found.');
            }
            Datetime nowTs = System.now();
            Applicant__c updateRow = new Applicant__c(Id = rows[0].Id);
            if (rows[0].Applicant_Consent_Received_Date__c == null) {
                updateRow.Applicant_Consent_Received_Date__c = nowTs;
            }
            // Clear legacy Consent_Sent__c (old flow stamped it when agent opened the link).
            if (rows[0].Application_Consent_Received__c != true) {
                updateRow.Consent_Sent__c = null;
                updateRow.Consent_Verification_Code__c = null;
            }
            update updateRow;
            out.put('isSuccess', true);
            out.put('consentSent', true);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            out.put('message', e.getMessage());
        }
        return out;
    }

    /** Lightweight refresh of consent flags after customer accepts on the VF page. */
    @AuraEnabled
    public static Map<String, Object> getApplicantConsentFlags(String applicantId) {
        Map<String, Object> out = new Map<String, Object>{ 'isSuccess' => false };
        if (String.isBlank(applicantId)) {
            return out;
        }
        List<Applicant__c> rows = [
            SELECT Application_Consent_Received__c,
                   Consent_Sent__c,
                   Applicant_Consent_Received_Date__c
            FROM Applicant__c
            WHERE Id = :applicantId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return out;
        }
        Applicant__c a = rows[0];
        out.put('isSuccess', true);
        out.put('consentOtpVerified', isConsentOtpVerifiedMarker(a));
        out.put('consentSent', isConsentLinkSharedMarker(a));
        out.put('applicationConsentReceived', a.Application_Consent_Received__c == true);
        return out;
    }

    private static Map<String, Object> resolveConsentSiteBase() {
        try {
            List<Site> sites = [
                SELECT Id, UrlPathPrefix
                FROM Site
                WHERE Name = :CONSENT_SITE_NAME
                  AND Status = 'Active'
                LIMIT 1
            ];
            if (!sites.isEmpty()) {
                Site siteRow = sites[0];
                List<DomainSite> domainSites = [
                    SELECT Domain.Domain
                    FROM DomainSite
                    WHERE SiteId = :siteRow.Id
                    ORDER BY Domain.DomainType ASC
                    LIMIT 1
                ];
                if (!domainSites.isEmpty()
                    && domainSites[0].Domain != null
                    && String.isNotBlank(domainSites[0].Domain.Domain)) {
                    String path = String.isNotBlank(siteRow.UrlPathPrefix)
                        ? '/' + siteRow.UrlPathPrefix
                        : '';
                    return new Map<String, Object>{
                        'baseUrl' => 'https://' + domainSites[0].Domain.Domain + path,
                        'isSiteUrl' => true
                    };
                }
            }
        } catch (Exception ignored) {
        }

        String siteBase = Site.getBaseUrl();
        if (String.isNotBlank(siteBase)) {
            return new Map<String, Object>{
                'baseUrl' => siteBase,
                'isSiteUrl' => true
            };
        }

        String orgDomain = Url.getOrgDomainUrl() != null
            ? Url.getOrgDomainUrl().toExternalForm()
            : '';
        return new Map<String, Object>{
            'baseUrl' => orgDomain,
            'isSiteUrl' => false
        };
    }

    @AuraEnabled
    public static Decimal getBeneficiaryShareholdingTotal(String applicantId, String applicationId) {
        if (String.isBlank(applicantId)) {
            return null;
        }

        List<Applicant__c> currentApplicants = [
            SELECT Id, Parent_Applicant__c, Application__c
            FROM Applicant__c
            WHERE Id = :applicantId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (currentApplicants.isEmpty()) {
            return 0;
        }

        Applicant__c currentApplicant = currentApplicants[0];
        Id resolvedApplicationId = String.isNotBlank(applicationId)
            ? applicationId
            : currentApplicant.Application__c;
        if (resolvedApplicationId == null) {
            return 0;
        }

        Id parentApplicantId = currentApplicant.Parent_Applicant__c;
        List<Applicant__c> relatedBeneficiaries;

        if (parentApplicantId == null) {
            relatedBeneficiaries = [
                SELECT ShareHolding__c
                FROM Applicant__c
                WHERE Application__c = :resolvedApplicationId
                    AND Applicant_Type__c = 'Beneficiary'
                    AND Parent_Applicant__c = null
                    AND Id != :applicantId
                    AND ShareHolding__c != null
                    AND In_Active_Applicant__c = false
                WITH SECURITY_ENFORCED
            ];
        } else {
            relatedBeneficiaries = [
                SELECT ShareHolding__c
                FROM Applicant__c
                WHERE Application__c = :resolvedApplicationId
                    AND Applicant_Type__c = 'Beneficiary'
                    AND Parent_Applicant__c = :parentApplicantId
                    AND Id != :applicantId
                    AND ShareHolding__c != null
                    AND In_Active_Applicant__c = false
                WITH SECURITY_ENFORCED
            ];
        }

        Decimal total = 0;
        for (Applicant__c beneficiary : relatedBeneficiaries) {
            total += beneficiary.ShareHolding__c;
        }
        return total;
    }

    /**
     * Returns the configured minimum shareholding percentage from Non_Individual_Constitution__mdt
     * for the given entity code (Applicant__c.Entity_Type__c) and product type (PV / CV).
     */
    @AuraEnabled(cacheable=true)
    public static Non_Individual_Constitution__mdt getNiConstitution(String applicantEntityType, String productType) {
        if (String.isBlank(applicantEntityType) || String.isBlank(productType)) {
            return null;
        }
        Decimal entityCode;
        try {
            entityCode = Decimal.valueOf(applicantEntityType.trim());
        } catch (Exception e) {
            return null;
        }
        String normalizedProduct = productType.trim().toUpperCase();
        List<Non_Individual_Constitution__mdt> rows = [
            SELECT Min_Shareholding__c, PAN_Fourth_Char__c, Min_Beneficiary_Count__c, Max_Beneficiary_Count__c, Max_Guarantor_Count__c
            FROM Non_Individual_Constitution__mdt
            WHERE Entity_Code__c = :entityCode
              AND Product_Type__c = :normalizedProduct
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }
        return rows[0];
    }

    @AuraEnabled
    public static Non_Individual_Constitution__mdt getNiMinShareHoldings(String productType, String applicantId, String applicationId) {
        Decimal entityCode;

        if (String.isBlank(applicantId) || String.isBlank(productType)) {
            return null;
        }
        List<Applicant__c> applicants = [
            SELECT Entity_Type__c,Type__c,Parent_Applicant__c,Parent_Applicant__r.Type__c,Parent_Applicant__r.Entity_Type__c FROM Applicant__c
            WHERE Id = :applicantId
        ];
        Applicant__c borrowerApplicant = [SELECT Id,Type__c,Entity_Type__c FROM Applicant__c WHERE Application__c = :applicationId AND Applicant_Type__c = 'Borrower' LIMIT 1];
        if (applicants.isEmpty()) {
            return null;
        }
        if(applicants[0].Parent_Applicant__c == null){
            entityCode = borrowerApplicant.Type__c == 'Non-Individual' ? Decimal.valueOf(borrowerApplicant.Entity_Type__c.trim()) : null;
        } else {
            entityCode = Decimal.valueOf(applicants[0].Parent_Applicant__r.Entity_Type__c.trim());
        }

        String normalizedProduct = productType.trim().toUpperCase();
        List<Non_Individual_Constitution__mdt> rows = [
            SELECT Min_Shareholding__c, PAN_Fourth_Char__c, Min_Beneficiary_Count__c, Max_Beneficiary_Count__c, Max_Guarantor_Count__c
            FROM Non_Individual_Constitution__mdt
            WHERE Entity_Code__c = :entityCode
              AND Product_Type__c = :normalizedProduct
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }
        return rows[0];
    }
}