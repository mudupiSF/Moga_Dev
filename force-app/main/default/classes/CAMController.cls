public with sharing class CAMController implements Callable {

    private static final String ACTION_GET_CAM_PAGE_DATA = 'getCamPageData';
    private static final String ACTION_GET_KYC_DETAILS = 'getKycDetails';

    private static final Set<String> PERSONAL_DETAIL_APPLICANT_TYPES = new Set<String>{
        'Borrower',
        'Co-borrower',
        'Guarantor',
        'Beneficiary'
    };

    private static final String VERIFICATION_NAME_SUFFIX = ' Verification';

    private static final String DECLARATION_RBI_DIRECTORS_TEXT =
        'None of the Directors of the Bank or their relatives as defined in the RBI Master Circular - Loans and Advances Statutory and Other Restrictions is a director/partner, manager, managing agent, employee or guarantor of the applicant or a subsidiary of the applicant or of the holding company of the applicant and that none of them hold substantial interest in the applicant or his/ her / their subsidiary or his / her/ their holding company.';

    private static final String DECLARATION_RBI_OTHER_BANKS_TEXT =
        'To the best of the applicant\'s knowledge none of the directors of any other bank or the subsidiaries of the banks or trustees of mutual funds/venture capital funds set up by the banks or their relatives as defined in the RBI Master Circular - Loans and Advances - Statutory and Other Restrictions is a director/partner, manager, managing agent, employee or guarantor of the applicant or his /her/ their subsidiary or his / her/ their holding company and that none of them hold substantial interest in the applicant or his / her/ their subsidiary or his / her/ their holding company.';

    private static final String INCOME_RECORD_DECLARED = 'Declared Income';
    private static final String INCOME_RECORD_BANK_STATEMENT = 'Bank Statement';
    private static final String DOC_TYPE_BANK_STATEMENT = 'Bank Statement';
    private static final String INCOME_FIELD_TEXT = 'text';
    private static final String INCOME_FIELD_BUTTON = 'button';
    private static final String INCOME_FIELD_LINK = 'link';

    private static final String CREDIT_REPORT_CIBIL = 'CIBIL';
    private static final String CREDIT_REPORT_EQUIFAX = 'Equifax';
    private static final String CREDIT_REPORT_CRIF = 'CRIF';
    private static final String APPLICANT_TYPE_BENEFICIARY = 'Beneficiary';
    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';
    private static final Set<String> EXTERNAL_EXPOSURE_OBLIGATION_TYPES = new Set<String>{ 'External Exposure' };
    private static final String TYPE_FI = 'FI';
    private static final String FI_LABEL_CURRENT_RESIDENCE = 'Current Residence FI';
    private static final String FI_LABEL_PERMANENT = 'Permanent Residence FI';
    private static final String FI_LABEL_REGISTERED = 'Registered Address FI';
    private static final String FI_LABEL_OFFICE = 'Office FI';
    private static final String BRIEF_SECTION_TITLE = 'Brief about Applicants (Credit Assessment)';

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();
        if (ACTION_GET_CAM_PAGE_DATA.equalsIgnoreCase(action)) {
            return loadCamPage(safeArgs);
        }
        if (ACTION_GET_KYC_DETAILS.equalsIgnoreCase(action)) {
            return getKycDetailsInternal(safeArgs);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    private static Map<String, Object> loadCamPage(Map<String, Object> args) {
        Map<String, Object> result = emptyCamPageResponse();
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return result;
        }

        try {
            Application__c application = getApplication(applicationId);
            if (application == null) {
                result.put('loadError', 'Application record not found.');
                return result;
            }

            List<Applicant__c> personalApplicants = collectPersonalApplicantsSorted(application.Applicants__r);
            List<Applicant__c> camSectionApplicants = personalApplicants;
            List<Applicant__c> beneficiaryApplicants = filterApplicantsByType(
                personalApplicants, APPLICANT_TYPE_BENEFICIARY, true
            );
            Map<Id, List<Applicant_Income__c>> incomesByApplicant = groupIncomesByApplicant(application.Applicants__r);
            Map<Id, Applicant_Employment__c> employmentByApplicant = groupPrimaryEmploymentByApplicant(
                application.Applicants__r
            );
            ExposureObligationBuckets obligationBuckets = groupExposureObligations(application.Applicants__r);
            Map<String, Map<Id, Verification__c>> fiMaps = groupFiVerificationsByApplicant(application.Applicants__r);
            Set<Id> personalApplicantIds = new Set<Id>();
            for (Applicant__c applicant : personalApplicants) {
                personalApplicantIds.add(applicant.Id);
            }
            DocumentChecklistBuckets documentBuckets = getDocumentChecklists(
                applicationId,
                personalApplicantIds
            );
            Map<Id, Document_CheckList__c> poiIdentityByApplicant = getPoiIdentityDocumentsByApplicant(
                personalApplicantIds
            );

            Applicant__c borrower = resolveBorrower(application.Applicants__r);
            Application_Line_Item__c primaryLineItem = application.Application_Line_Items__r == null || application.Application_Line_Items__r.isEmpty() ? null : application.Application_Line_Items__r[0];

            List<Map<String, Object>> businessDetailSections = buildBusinessDetailSections(
                application,
                camSectionApplicants,
                fiMaps.get('office')
            );
            List<Map<String, Object>> beneficiaryIncomeSections = buildBeneficiaryIncomeSections(
                beneficiaryApplicants,
                incomesByApplicant,
                employmentByApplicant
            );

            List<Map<String, Object>> safeBusinessDetailSections = businessDetailSections != null
                ? businessDetailSections
                : new List<Map<String, Object>>();
            result.put('businessDetailSections', safeBusinessDetailSections);
            result.put('showBusinessDetailsSection', !safeBusinessDetailSections.isEmpty());

            List<Map<String, Object>> safeBeneficiaryIncomeSections = beneficiaryIncomeSections != null
                ? beneficiaryIncomeSections
                : new List<Map<String, Object>>();
            result.put('beneficiaryIncomeSections', safeBeneficiaryIncomeSections);
            result.put('showBeneficiaryIncomeSection', !safeBeneficiaryIncomeSections.isEmpty());
            Document_CheckList__c borrowerPoiDocument = borrower != null
                ? poiIdentityByApplicant.get(borrower.Id)
                : null;
            result.put('basicInfoFields', buildBasicInfoFields(
                application,
                borrower,
                application.Application_Line_Items__r,
                borrowerPoiDocument
            ));
            result.put('applicantColumns', buildApplicantColumns(
                personalApplicants,
                application,
                poiIdentityByApplicant
            ));
            result.put('bankAccountColumns', buildBankAccountColumns(camSectionApplicants));
            result.put('pricingLtvSections', buildAssetWiseSections(application, application.Application_Line_Items__r, borrower, 'pricing'));
            result.put('offerEngineSections', buildAssetWiseSections(application, application.Application_Line_Items__r, borrower, 'offer'));
            result.put('loanDetailSections', buildAssetWiseSections(application, application.Application_Line_Items__r, borrower, 'loan'));
            result.put('exposureSections', buildExposureSections(camSectionApplicants, obligationBuckets));
            populateCreditBureauSections(
                result,
                camSectionApplicants,
                borrower,
                primaryLineItem,
                documentBuckets.creditReportsByApplicant
            );
            result.put('permanentFiDetailSections', buildVerificationDetailSections(camSectionApplicants, fiMaps.get('permanent'), 'fiPermanent'));
            result.put('fiRegisteredDetailSections', buildVerificationDetailSections(camSectionApplicants, fiMaps.get('registered'), 'fiRegistered'));
            result.put('fiResidenceDetailSections', buildVerificationDetailSections(camSectionApplicants, fiMaps.get('residence'), 'fiResidence'));
            result.put('fiOfficeDetailSections', buildVerificationDetailSections(camSectionApplicants, fiMaps.get('office'), 'fiOffice'));
            result.put('briefDetails', buildBriefDetails(application.Applicants__r, application));
            result.put('incomeDetailSections', buildIncomeDetailSections(
                camSectionApplicants,
                incomesByApplicant,
                employmentByApplicant,
                documentBuckets.bankStatementsByApplicant
            ));
            result.put('financialPerformanceSections', buildFinancialPerformanceSections(
                camSectionApplicants,
                primaryLineItem,
                incomesByApplicant
            ));
            result.put('gatingScreeningSection', buildGatingScreeningSection(borrower));
            result.put('riskProfileSections', buildRiskProfileSections(camSectionApplicants));
            result.put('fiWaiverRows', buildFiWaiverRows(camSectionApplicants, application.Id, fiMaps));
            result.put(
                'fiWaiverPermanentColumnLabel',
                isNonIndividualApplicant(borrower) ? 'Permanent/Registered' : 'Permanent FI'
            );
            result.put('declarationSections', buildDeclarationSections(camSectionApplicants));
            result.put('annexureRows', documentBuckets.annexureRows);
            result.put('isSuccess', true);
        } catch (Exception e) {
            result.put('loadError', 'Unable to load CAM page data: ' + e.getMessage());
        }

        return result;
    }

    private static Map<String, Object> emptyCamPageResponse() {
        return new Map<String, Object>{
            'isSuccess' => false,
            'basicInfoFields' => new List<Map<String, Object>>(),
            'applicantColumns' => new List<Map<String, Object>>(),
            'loanDetailSections' => new List<Map<String, Object>>(),
            'bankAccountColumns' => new List<Map<String, Object>>(),
            'pricingLtvSections' => new List<Map<String, Object>>(),
            'offerEngineSections' => new List<Map<String, Object>>(),
            'exposureSections' => new List<Map<String, Object>>(),
            'creditBureauColumns' => new List<Map<String, Object>>(),
            'creditBureauSectionTitle' => 'CIBIL Details',
            'permanentFiDetailSections' => new List<Map<String, Object>>(),
            'fiRegisteredDetailSections' => new List<Map<String, Object>>(),
            'fiResidenceDetailSections' => new List<Map<String, Object>>(),
            'fiOfficeDetailSections' => new List<Map<String, Object>>(),
            'briefDetails' => new Map<String, Object>(),
            'incomeDetailSections' => new List<Map<String, Object>>(),
            'financialPerformanceSections' => new List<Map<String, Object>>(),
            'gatingScreeningSection' => new Map<String, Object>(),
            'riskProfileSections' => new List<Map<String, Object>>(),
            'fiWaiverRows' => new List<Map<String, Object>>(),
            'fiWaiverPermanentColumnLabel' => 'Permanent FI',
            'declarationSections' => new List<Map<String, Object>>(),
            'annexureRows' => new List<Map<String, Object>>(),
            'showBusinessDetailsSection' => false,
            'businessDetailSections' => new List<Map<String, Object>>(),
            'showBeneficiaryIncomeSection' => false,
            'beneficiaryIncomeSections' => new List<Map<String, Object>>()
        };
    }

    private static void populateCreditBureauSections(
        Map<String, Object> result,
        List<Applicant__c> applicants,
        Applicant__c borrower,
        Application_Line_Item__c lineItem,
        Map<Id, Map<String, String>> creditReportsByApplicant
    ) {
        LineItemBureauContext bureauContext = new LineItemBureauContext();
        bureauContext.bureauSurrogate = lineItem != null
            ? formatDecimalDisplay(lineItem.Bureau_Surrogate_Offer__c)
            : null;
        bureauContext.schemeMinCibil = lineItem != null && lineItem.Schemes__r != null
            ? formatDecimalDisplay(lineItem.Schemes__r.MinimumCIBILScore__c)
            : null;
        bureauContext.schemeMaxCibil = lineItem != null && lineItem.Schemes__r != null
            ? formatDecimalDisplay(lineItem.Schemes__r.Maximum_CIBIL_Score__c)
            : null;

        result.put('creditBureauColumns', buildCreditBureauColumns(
            applicants,
            bureauContext,
            creditReportsByApplicant
        ));
        result.put(
            'creditBureauSectionTitle',
            isNonIndividualApplicant(borrower) ? 'CRIF/CIBIL Details' : 'CIBIL Details'
        );
    }

    private class LineItemBureauContext {
        public String bureauSurrogate;
        public String schemeMinCibil;
        public String schemeMaxCibil;
    }

    private static Application__c getApplication(Id applicationId) {
        String residencePattern = '%' + FI_LABEL_CURRENT_RESIDENCE + '%';
        String permanentPattern = '%' + FI_LABEL_PERMANENT + '%';
        String registeredPattern = '%' + FI_LABEL_REGISTERED + '%';
        String officePattern = '%' + FI_LABEL_OFFICE + '%';

        List<Application__c> applications = [
            SELECT Id,
                   Application_number__c,
                   Product__c,
                   Sub_Product__c,
                   Sanction_Status__c,
                   Branch__r.Name,
                   Branch__r.BillingState,
                   Owner.Name,
                   (SELECT Id,
                           Applicant_Type__c,
                           Applicant_Tab_Label__c,
                           Customer_First_Name__c,
                           Customer_Last_Name__c,
                           PAN_Number__c,
                           Date_of_Birth__c,
                           Phone__c,
                           Email__c,
                           Customer_Code__c,
                           Type__c,
                           Gender__c,
                           Marital_status__c,
                           Relationship_with_borrower__c,
                           Relationship_with_Bank__c,
                           Is_Applicant_Relative_Of_Director__c,
                           Is_Applicant_Relative_Of_Senior_Officer__c,
                           Entity_Type__c,
                           Company_Name__c,
                           Major_Industry__c,
                           Minor_Industry__c,
                           Industry_Name__c,
                           Industry_Code__c,
                           Beneficial_Owner_Category__c,
                           Relationship_with_Entity__c,
                           Relationship_Type__c,
                           POA_Holder__c,
                           ShareHolding__c,
                           Evaluation_Type__c,
                           Profile__c,
                           Income_Category__c,
                           Has_Bank_Account__c,
                           Interested_In_Opening_Savings_Account__c,
                           Declared_income__c,
                           Scorecard_Decision__c,
                           Justification_Remark__c,
                           (SELECT Purpose_of_purchase__c
                            FROM Assets__r
                            ORDER BY CreatedDate DESC
                            LIMIT 1),
                           (SELECT Id,
                                   Name,
                                   Income_Source__c,
                                   Primary_Income_Source__c,
                                   Employer_Business_Name__c,
                                   Consolidated_Yearly_Income__c,
                                   Income_Detail_Bank_Master__r.Name
                            FROM Applicant_Income__r
                            ORDER BY CreatedDate ASC),
                           (SELECT Id,
                                   Applicant__c,
                                   Employee_Name__c,
                                   Employer_Name__c,
                                   Employer_Business_Name__c,
                                   Current_years_in_Employment_Business__c,
                                   Years_in_employment_business__c,
                                   Salaried_Self_employed__c
                            FROM Applicant_Employment__r
                            ORDER BY CreatedDate DESC),
                           (SELECT Id,
                                   Applicant__c,
                                   Type__c,
                                   Exposure_Type__c,
                                   Deal_No__c,
                                   Deal_Stage__c,
                                   Deal_Date__c,
                                   Type_of_Facility__c,
                                   Status_Flag__c,
                                   Finance_Amt__c,
                                   SOH__c,
                                   Over_Due__c,
                                   Account_Type__c,
                                   Account_Type_Desc__c,
                                   Ownership__c,
                                   High_Credit__c,
                                   Current_Balance__c,
                                   Amount_Overdue__c,
                                   Reason_for_Overdue__c,
                                   Financier_Name__c
                            FROM Applicant_Obligations__r
                            ORDER BY Type__c ASC,
                                     Exposure_Type__c ASC,
                                     Deal_No__c ASC NULLS LAST,
                                     CreatedDate ASC),
                           (SELECT Id,
                                   Applicant__c,
                                   Name,
                                   Status__c,
                                   Decision__c,
                                   Investigations__c,
                                   Residence_Type__c,
                                   Years_in_Residence__c,
                                   Years_in_City__c,
                                   Coordinates_Distance__c,
                                   Name_of_Person_Met__c,
                                   Same_Address_as_in_Application__c,
                                   Remarks__c,
                                   Office_Business_Type__c,
                                   Employer_Business_Name__c,
                                   Business_Premise__c,
                                   Current_Experience_Years__c
                            FROM Verifications__r
                            WHERE Investigations__r.Type_of_Investigation__c = :TYPE_FI
                              AND (
                                  Name LIKE :residencePattern
                                  OR Name LIKE :permanentPattern
                                  OR Name LIKE :registeredPattern
                                  OR Name LIKE :officePattern
                              )
                            ORDER BY CreatedDate DESC)
                    FROM Applicants__r
                    WHERE In_Active_Applicant__c = false
                    ORDER BY Applicant_Type__c ASC,
                             Applicant_Tab_Label__c ASC NULLS LAST,
                             CreatedDate ASC),
                   (SELECT Id,
                           Loan_Amount__c,
                           Tenure__c,
                           EMI_Amount__c,
                           ROI__c,
                           CRM_IRR__c,
                           Calculated_Gross_LTV__c,
                           Calculated_Net_LTV__c,
                           Bureau_Surrogate_Offer__c,
                           Scheme__c,
                           Schemes__r.Name,
                           Schemes__r.Customer_Type__c,
                           Schemes__r.Scheme_Code__c,
                           Schemes__r.MinimumCIBILScore__c,
                           Schemes__r.Maximum_CIBIL_Score__c,
                           (SELECT Id,
                                   Applicant__c,
                                   Make__c,
                                   Model__c,
                                   Variant__c,
                                   Vehicle_type__c,
                                   Viability_Ratio__c,
                                   Purpose_of_purchase__c,
                                   Required_Total_Loan_Amount__c
                            FROM Assets__r
                            ORDER BY CreatedDate ASC
                            LIMIT 1)
                    FROM Application_Line_Items__r
                            ORDER BY CreatedDate ASC)
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0];
    }

    private class DocumentChecklistBuckets {
        Map<Id, Map<String, Object>> bankStatementsByApplicant = new Map<Id, Map<String, Object>>();
        Map<Id, Map<String, String>> creditReportsByApplicant = new Map<Id, Map<String, String>>();
        List<Map<String, Object>> annexureRows = new List<Map<String, Object>>();
    }

    private static DocumentChecklistBuckets getDocumentChecklists(Id applicationId, Set<Id> applicantIds) {
        DocumentChecklistBuckets buckets = new DocumentChecklistBuckets();
        if (applicationId == null) {
            return buckets;
        }

        Boolean hasApplicantIds = applicantIds != null && !applicantIds.isEmpty();
        List<Document_CheckList__c> documents;
        if (hasApplicantIds) {
            documents = [
                SELECT Id,
                       Name,
                       Applicant__c,
                       Application__c,
                       Document_Type__c,
                       Applicant_Type__c,
                       ContentVersionId__c
                FROM Document_CheckList__c
                WHERE Is_Active__c = true
                  AND (
                      (Application__c = :applicationId AND Document_Type__c != null)
                      OR Applicant__c IN :applicantIds
                  )
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
            ];
        } else {
            documents = [
                SELECT Id,
                       Name,
                       Applicant__c,
                       Application__c,
                       Document_Type__c,
                       Applicant_Type__c,
                       ContentVersionId__c
                FROM Document_CheckList__c
                WHERE Is_Active__c = true
                  AND Application__c = :applicationId
                  AND Document_Type__c != null
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
            ];
        }

        Set<Id> versionIds = new Set<Id>();
        for (Document_CheckList__c document : documents) {
            if (String.isNotBlank(document.ContentVersionId__c)) {
                versionIds.add((Id) document.ContentVersionId__c);
            }
        }
        Map<Id, ContentVersion> versionById = queryContentVersionsById(versionIds);

        for (Document_CheckList__c document : documents) {
            if (document.Application__c == applicationId && String.isNotBlank(document.Document_Type__c)) {
                Map<String, Object> annexureRow = new Map<String, Object>{
                    'id' => String.valueOf(document.Id),
                    'documentType' => formatAnnexureDocumentType(document),
                    'documentName' => document.Name,
                    'hasDocumentLink' => String.isNotBlank(document.ContentVersionId__c)
                };
                applyDocumentPreviewFields(annexureRow, document.ContentVersionId__c, versionById);
                buckets.annexureRows.add(annexureRow);
            }

            if (!hasApplicantIds || document.Applicant__c == null) {
                continue;
            }

            if (DOC_TYPE_BANK_STATEMENT.equals(document.Document_Type__c)
                && !buckets.bankStatementsByApplicant.containsKey(document.Applicant__c)) {
                Map<String, Object> bankStatementDoc = new Map<String, Object>{
                    'fileName' => document.Name,
                    'hasDocumentLink' => String.isNotBlank(document.ContentVersionId__c)
                };
                applyDocumentPreviewFields(bankStatementDoc, document.ContentVersionId__c, versionById);
                buckets.bankStatementsByApplicant.put(document.Applicant__c, bankStatementDoc);
            }

            if (document.Application__c == applicationId
                && String.isNotBlank(document.ContentVersionId__c)) {
                String reportKey = resolveCreditReportKey(document);
                if (reportKey == null) {
                    continue;
                }
                if (!buckets.creditReportsByApplicant.containsKey(document.Applicant__c)) {
                    buckets.creditReportsByApplicant.put(document.Applicant__c, new Map<String, String>());
                }
                Map<String, String> applicantReports = buckets.creditReportsByApplicant.get(document.Applicant__c);
                if (!applicantReports.containsKey(reportKey)) {
                    applicantReports.put(reportKey, document.ContentVersionId__c);
                }
            }
        }

        buckets.annexureRows.sort(new AnnexureRowComparator());
        return buckets;
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

    private static Map<Id, ContentVersion> queryContentVersionsById(Set<Id> versionIds) {
        Map<Id, ContentVersion> versionById = new Map<Id, ContentVersion>();
        if (versionIds == null || versionIds.isEmpty()) {
            return versionById;
        }
        for (ContentVersion version : [
            SELECT Id, ContentDocumentId, FileExtension
            FROM ContentVersion
            WHERE Id IN :versionIds
            WITH SECURITY_ENFORCED
        ]) {
            versionById.put(version.Id, version);
        }
        return versionById;
    }

    private static void applyDocumentPreviewFields(
        Map<String, Object> target,
        Id contentVersionId,
        Map<Id, ContentVersion> versionById
    ) {
        if (target == null || contentVersionId == null) {
            return;
        }
        target.put('contentVersionId', String.valueOf(contentVersionId));
        ContentVersion version = versionById != null ? versionById.get(contentVersionId) : null;
        if (version != null && version.ContentDocumentId != null) {
            target.put('contentDocumentId', String.valueOf(version.ContentDocumentId));
            target.put('fileType', version.FileExtension);
        }
    }

    private class AnnexureRowComparator implements System.Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> left, Map<String, Object> right) {
            String leftType = left.get('documentType') != null ? String.valueOf(left.get('documentType')) : '';
            String leftName = left.get('documentName') != null ? String.valueOf(left.get('documentName')) : '';
            String rightType = right.get('documentType') != null ? String.valueOf(right.get('documentType')) : '';
            String rightName = right.get('documentName') != null ? String.valueOf(right.get('documentName')) : '';
            Integer typeCompare = leftType.compareTo(rightType);
            return typeCompare != 0 ? typeCompare : leftName.compareTo(rightName);
        }
    }

    private static Map<Id, List<Applicant_Income__c>> groupIncomesByApplicant(List<Applicant__c> applicants) {
        Map<Id, List<Applicant_Income__c>> incomesByApplicant = new Map<Id, List<Applicant_Income__c>>();
        if (applicants == null) {
            return incomesByApplicant;
        }
        for (Applicant__c applicant : applicants) {
            if (applicant.Applicant_Income__r != null && !applicant.Applicant_Income__r.isEmpty()) {
                incomesByApplicant.put(applicant.Id, applicant.Applicant_Income__r);
            }
        }
        return incomesByApplicant;
    }

    private static Map<Id, Applicant_Employment__c> groupPrimaryEmploymentByApplicant(List<Applicant__c> applicants) {
        Map<Id, Applicant_Employment__c> employmentByApplicant = new Map<Id, Applicant_Employment__c>();
        if (applicants == null) {
            return employmentByApplicant;
        }
        for (Applicant__c applicant : applicants) {
            if (applicant.Applicant_Employment__r == null || applicant.Applicant_Employment__r.isEmpty()) {
                continue;
            }
            employmentByApplicant.put(applicant.Id, applicant.Applicant_Employment__r[0]);
        }
        return employmentByApplicant;
    }

    private static ExposureObligationBuckets groupExposureObligations(List<Applicant__c> applicants) {
        ExposureObligationBuckets buckets = new ExposureObligationBuckets();
        if (applicants == null) {
            return buckets;
        }
        for (Applicant__c applicant : applicants) {
            if (applicant.Applicant_Obligations__r == null) {
                continue;
            }
            for (Applicant_Obligations__c obligation : applicant.Applicant_Obligations__r) {
                Map<Id, List<Applicant_Obligations__c>> targetMap;
                if (isExternalExposureObligation(obligation)) {
                    if (!hasExternalExposureFieldsPopulated(obligation)) {
                        continue;
                    }
                    targetMap = buckets.externalExposureByApplicant;
                } else if (hasBankExposureDealData(obligation)) {
                    targetMap = buckets.bankExposureByApplicant;
                } else {
                    continue;
                }
                if (!targetMap.containsKey(applicant.Id)) {
                    targetMap.put(applicant.Id, new List<Applicant_Obligations__c>());
                }
                targetMap.get(applicant.Id).add(obligation);
            }
        }
        return buckets;
    }

    private static Map<String, Map<Id, Verification__c>> groupFiVerificationsByApplicant(List<Applicant__c> applicants) {
        Map<Id, Verification__c> residenceByApplicant = new Map<Id, Verification__c>();
        Map<Id, Verification__c> permanentByApplicant = new Map<Id, Verification__c>();
        Map<Id, Verification__c> registeredByApplicant = new Map<Id, Verification__c>();
        Map<Id, Verification__c> officeByApplicant = new Map<Id, Verification__c>();
        Map<String, Map<Id, Verification__c>> result = new Map<String, Map<Id, Verification__c>>{
            'residence' => residenceByApplicant,
            'permanent' => permanentByApplicant,
            'registered' => registeredByApplicant,
            'office' => officeByApplicant
        };
        if (applicants == null) {
            return result;
        }

        for (Applicant__c applicant : applicants) {
            if (applicant.Verifications__r == null) {
                continue;
            }
            for (Verification__c verification : applicant.Verifications__r) {
                String label = extractFiLabelFromVerificationName(verification.Name);
                if (FI_LABEL_CURRENT_RESIDENCE.equalsIgnoreCase(label)
                    && !residenceByApplicant.containsKey(applicant.Id)) {
                    residenceByApplicant.put(applicant.Id, verification);
                } else if (FI_LABEL_PERMANENT.equalsIgnoreCase(label)
                    && !permanentByApplicant.containsKey(applicant.Id)) {
                    permanentByApplicant.put(applicant.Id, verification);
                } else if (FI_LABEL_REGISTERED.equalsIgnoreCase(label)
                    && !registeredByApplicant.containsKey(applicant.Id)) {
                    registeredByApplicant.put(applicant.Id, verification);
                } else if (isOfficeFiLabel(label)
                    && !officeByApplicant.containsKey(applicant.Id)) {
                    officeByApplicant.put(applicant.Id, verification);
                }
            }
        }
        return result;
    }

    private static Boolean isOfficeFiLabel(String label) {
        if (String.isBlank(label)) {
            return false;
        }
        if (FI_LABEL_OFFICE.equalsIgnoreCase(label)) {
            return true;
        }
        String normalized = label.trim().toLowerCase();
        return normalized.contains('office fi');
    }

    private static List<Map<String, Object>> buildBasicInfoFields(
        Application__c application,
        Applicant__c borrower,
        List<Application_Line_Item__c> lineItems,
        Document_CheckList__c borrowerPoiDocument
    ) {
        String branchName = application.Branch__r != null ? application.Branch__r.Name : null;
        String branchState = application.Branch__r != null ? application.Branch__r.BillingState : null;
        String branchDisplay = joinDisplayParts(new List<String>{ branchName, branchState }, ' / ');

        Application_Line_Item__c primaryLineItem = lineItems == null || lineItems.isEmpty() ? null : lineItems[0];
        String custType = borrower != null && String.isNotBlank(borrower.Type__c)
            ? borrower.Type__c
            : (primaryLineItem != null
                && primaryLineItem.Schemes__r != null
                && String.isNotBlank(primaryLineItem.Schemes__r.Customer_Type__c)
                ? primaryLineItem.Schemes__r.Customer_Type__c
                : null);
        String schemeCode = primaryLineItem != null && primaryLineItem.Schemes__r != null
            ? primaryLineItem.Schemes__r.Scheme_Code__c
            : null;
        return new List<Map<String, Object>>{
            fieldRow('branch', 'Branch Name / State Name', branchDisplay),
            fieldRow('exec', 'Executive Name', application.Owner != null ? application.Owner.Name : null),
            fieldRow('appNo', 'Lead Number', application.Application_number__c),
            fieldRow('appName', 'Applicant Name', formatApplicantName(borrower, borrowerPoiDocument)),
            fieldRow('custType', 'Customer Type', custType),
            fieldRow('custCode', 'Customer Code', borrower != null ? borrower.Customer_Code__c : null),
            fieldRow('exposure', 'Current Exposure', formatCurrency(calculateCurrentExposureAmount(lineItems))),
            fieldRow(
                'borrowerExp',
                'Existing Borrower Exposure',
                formatCurrency(calculateExistingBorrowerExposureAmount(borrower))
            ),
            fieldRow('scheme', 'Scheme Name', resolveSchemeName(primaryLineItem, application)),
            fieldRow('schemeCode', 'Scheme Code', schemeCode)
        };
    }

    private static List<Map<String, Object>> buildApplicantColumns(
        List<Applicant__c> personalApplicants,
        Application__c application,
        Map<Id, Document_CheckList__c> poiIdentityByApplicant
    ) {
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        for (Applicant__c applicant : personalApplicants) {
            Document_CheckList__c poiDocument = poiIdentityByApplicant != null
                ? poiIdentityByApplicant.get(applicant.Id)
                : null;
            columns.add(applicantSection(
                applicant,
                buildPersonalDetailFields(applicant, application, poiDocument)
            ));
        }
        return columns;
    }

    private static List<Map<String, Object>> buildAssetWiseSections(
        Application__c application,
        List<Application_Line_Item__c> lineItems,
        Applicant__c borrower,
        String sectionType
    ) {
        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        Integer total = lineItems == null || lineItems.isEmpty() ? 1 : lineItems.size();

        for (Integer i = 0; i < total; i++) {
            Application_Line_Item__c lineItem = (lineItems == null || lineItems.isEmpty()) ? null : lineItems[i];
            Asset__c asset = resolveLineItemAsset(lineItem);
            String sectionKey = resolveAssetSectionKey(application, lineItem, asset);
            List<Map<String, Object>> fields;

            if (sectionType == 'loan') {
                fields = buildLoanDetailFields(application, lineItem, asset, sectionKey);
            } else if (sectionType == 'pricing') {
                fields = buildPricingLtvFields(lineItem, asset);
            } else {
                fields = buildOfferEngineFields(application, lineItem, borrower);
            }

            sections.add(buildAssetSectionEnvelope(
                lineItem,
                asset,
                borrower,
                i + 1,
                total,
                sectionKey,
                fields
            ));
        }
        return sections;
    }

    private static Asset__c resolveLineItemAsset(Application_Line_Item__c lineItem) {
        if (lineItem == null || lineItem.Assets__r == null || lineItem.Assets__r.isEmpty()) {
            return null;
        }
        return lineItem.Assets__r[0];
    }

    private static String resolveAssetSectionKey(
        Application__c application,
        Application_Line_Item__c lineItem,
        Asset__c asset
    ) {
        return lineItem != null
            ? String.valueOf(lineItem.Id) + (asset != null ? '-' + asset.Id : '')
            : 'application-' + String.valueOf(application.Id);
    }

    private static Map<String, Object> buildAssetSectionEnvelope(
        Application_Line_Item__c lineItem,
        Asset__c asset,
        Applicant__c borrower,
        Integer sectionIndex,
        Integer totalSections,
        String sectionKey,
        List<Map<String, Object>> fields
    ) {
        Id viabilityApplicantId = asset != null && asset.Applicant__c != null
            ? asset.Applicant__c
            : (borrower != null ? borrower.Id : null);

        String sectionTitle = null;
        if (totalSections > 1) {
            String assetLabel = asset == null
                ? null
                : joinDisplayParts(
                    new List<String>{ asset.Make__c, asset.Model__c, asset.Variant__c },
                    ' '
                );
            sectionTitle = String.isNotBlank(assetLabel)
                ? 'Asset ' + sectionIndex + ' - ' + assetLabel
                : 'Asset ' + sectionIndex;
        }

        return new Map<String, Object>{
            'id' => sectionKey,
            'title' => sectionTitle,
            'lineItemId' => lineItem != null ? String.valueOf(lineItem.Id) : null,
            'assetId' => asset != null ? String.valueOf(asset.Id) : null,
            'applicantId' => viabilityApplicantId != null ? String.valueOf(viabilityApplicantId) : null,
            'showSubheading' => totalSections > 1,
            'fields' => fields
        };
    }

    private static List<Map<String, Object>> buildLoanDetailFields(
        Application__c application,
        Application_Line_Item__c lineItem,
        Asset__c asset,
        String sectionKey
    ) {
        Decimal netLtv = lineItem != null ? lineItem.Calculated_Net_LTV__c : null;
        return new List<Map<String, Object>>{
            fieldRow(sectionKey + '-amount', 'Loan Amount', formatCurrency(resolveLineItemLoanAmount(lineItem))),
            fieldRow(sectionKey + '-tenure', 'Tenure', formatTenure(lineItem != null ? lineItem.Tenure__c : null)),
            fieldRow(sectionKey + '-roi', 'Rate of Interest', formatPercent(lineItem != null ? lineItem.ROI__c : null)),
            fieldRow(sectionKey + '-emi', 'EMI', formatCurrency(lineItem != null ? lineItem.EMI_Amount__c : null)),
            fieldRow(sectionKey + '-ltv', 'LTV', formatPercent(netLtv != null ? netLtv : (lineItem != null ? lineItem.Calculated_Gross_LTV__c : null))),
            fieldRow(sectionKey + '-viability', 'Viability Ratio', formatPercent(asset != null ? asset.Viability_Ratio__c : null)),
            fieldRow(sectionKey + '-foir', 'FOIR', null),
            fieldRow(sectionKey + '-vehicle', 'Vehicle Type', asset != null ? asset.Vehicle_type__c : null)
        };
    }

    private class ApplicantDisplayOrderComparator implements System.Comparator<Applicant__c> {
        public Integer compare(Applicant__c left, Applicant__c right) {
            Integer leftRank = applicantSortRank(left.Applicant_Type__c);
            Integer rightRank = applicantSortRank(right.Applicant_Type__c);
            if (leftRank != rightRank) {
                return leftRank < rightRank ? -1 : 1;
            }
            String leftTab = left.Applicant_Tab_Label__c != null ? left.Applicant_Tab_Label__c : '';
            String rightTab = right.Applicant_Tab_Label__c != null ? right.Applicant_Tab_Label__c : '';
            return leftTab.compareTo(rightTab);
        }
        private Integer applicantSortRank(String applicantType) {
            if (String.isBlank(applicantType)) return 99;
            if (isApplicantTypeMatch('Borrower', applicantType)) return 0;
            if (isApplicantTypeMatch('Co-borrower', applicantType)) return 1;
            String normalizedType = normalizeApplicantTypeKey(applicantType);
            if (isApplicantTypeMatch('Guarantor', applicantType)
                || (normalizedType != null && normalizedType.startsWith('g'))) return 2;
            if (isApplicantTypeMatch('Beneficiary', applicantType)) return 3;
            return 4;
        }
    }

    private static Map<String, Object> buildGatingScreeningSection(Applicant__c borrower) {
        return new Map<String, Object>{
            'id' => borrower != null ? String.valueOf(borrower.Id) : 'gating-screening',
            'applicantTitle' => borrower != null ? resolveApplicantTitle(borrower) : null,
            'applicantType' => borrower != null ? borrower.Applicant_Type__c : null,
            'fields' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'id' => 'gating-output', 'label' => 'Gating Output', 'value' => 'N/A' },
                new Map<String, Object>{ 'id' => 'screening', 'label' => 'Screening', 'value' => 'N/A' },
                new Map<String, Object>{ 'id' => 'rvg-flag', 'label' => 'RV/G/D Flag', 'value' => 'N/A' },
                new Map<String, Object>{ 'id' => 'fk-flag', 'label' => 'F/K Flag', 'value' => 'N/A' },
                new Map<String, Object>{ 'id' => 'fraud-checks', 'label' => 'Fraud Checks', 'value' => 'N/A' }
            }
        };
    }

    private static List<Map<String, Object>> buildRiskProfileSections(List<Applicant__c> personalApplicants) {
        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        for (Applicant__c applicant : personalApplicants) {
            String riskLevel = applicant.Scorecard_Decision__c;
            sections.add(new Map<String, Object>{
                'id' => String.valueOf(applicant.Id) + '-risk',
                'title' => resolveApplicantTitle(applicant),
                'applicantType' => applicant.Applicant_Type__c,
                'riskLevel' => riskLevel,
                'showRiskBadge' => String.isNotBlank(riskLevel)
            });
        }
        return sections;
    }

    private static List<Map<String, Object>> buildFiWaiverRows(
        List<Applicant__c> personalApplicants,
        Id applicationId,
        Map<String, Map<Id, Verification__c>> fiMaps
    ) {
        if (personalApplicants == null || personalApplicants.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        String fiMode = applicationId != null
            ? FIWaiverAPIHandler.resolveFiCreationMode(applicationId)
            : FIWaiverAPIHandler.FI_MODE_INDIVIDUAL;
        Set<Id> niFiEligibleApplicantIds = FIWaiverAPIHandler.resolveNiFiEligibleApplicantIds(applicationId);
        Boolean isNiFiMode = FIWaiverAPIHandler.FI_MODE_PV_NI.equals(fiMode)
            || FIWaiverAPIHandler.FI_MODE_CV_NI.equals(fiMode);

        Map<Id, Verification__c> residenceByApplicant = fiMaps != null ? fiMaps.get('residence') : null;
        Map<Id, Verification__c> permanentByApplicant = fiMaps != null ? fiMaps.get('permanent') : null;
        Map<Id, Verification__c> registeredByApplicant = fiMaps != null ? fiMaps.get('registered') : null;
        Map<Id, Verification__c> officeByApplicant = fiMaps != null ? fiMaps.get('office') : null;

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Applicant__c applicant : personalApplicants) {
            Map<String, String> waiverDisplay = isNiFiMode
                    && niFiEligibleApplicantIds != null
                    && !niFiEligibleApplicantIds.contains(applicant.Id)
                ? allWaivedFiWaiverDisplay()
                : buildFiWaiverDisplayFromVerifications(
                    applicant,
                    residenceByApplicant,
                    permanentByApplicant,
                    registeredByApplicant,
                    officeByApplicant
                );
            rows.add(new Map<String, Object>{
                'id' => String.valueOf(applicant.Id) + '-fi-waiver',
                'customerTypeDisplay' => resolveApplicantTitle(applicant),
                'currentAddressDisplay' => waiverDisplay.get('currentAddressDisplay'),
                'permanentAddressDisplay' => waiverDisplay.get('permanentAddressDisplay'),
                'officeAddressDisplay' => waiverDisplay.get('officeAddressDisplay')
            });
        }
        return rows;
    }

    private static Map<String, String> buildFiWaiverDisplayFromVerifications(
        Applicant__c applicant,
        Map<Id, Verification__c> residenceByApplicant,
        Map<Id, Verification__c> permanentByApplicant,
        Map<Id, Verification__c> registeredByApplicant,
        Map<Id, Verification__c> officeByApplicant
    ) {
        Id applicantId = applicant.Id;
        Verification__c residenceVerification = residenceByApplicant != null
            ? residenceByApplicant.get(applicantId)
            : null;
        Verification__c permanentVerification = permanentByApplicant != null
            ? permanentByApplicant.get(applicantId)
            : null;
        Verification__c registeredVerification = registeredByApplicant != null
            ? registeredByApplicant.get(applicantId)
            : null;
        Verification__c officeVerification = officeByApplicant != null
            ? officeByApplicant.get(applicantId)
            : null;
        Boolean hasPermanentOrRegisteredFi = isNonIndividualApplicant(applicant)
            ? (registeredVerification != null || permanentVerification != null)
            : permanentVerification != null;

        return new Map<String, String>{
            'currentAddressDisplay' => toFiWaiverDisplay(residenceVerification != null),
            'permanentAddressDisplay' => toFiWaiverDisplay(hasPermanentOrRegisteredFi),
            'officeAddressDisplay' => toFiWaiverDisplay(officeVerification != null)
        };
    }

    private static String toFiWaiverDisplay(Boolean hasFiVerification) {
        return hasFiVerification == true ? 'Not Waived' : 'Waived';
    }

    private static Map<String, String> allWaivedFiWaiverDisplay() {
        return new Map<String, String>{
            'currentAddressDisplay' => 'Waived',
            'permanentAddressDisplay' => 'Waived',
            'officeAddressDisplay' => 'Waived'
        };
    }

    private static String extractFiLabelFromVerificationName(String verificationName) {
        if (String.isBlank(verificationName)) {
            return null;
        }
        String normalized = verificationName.trim();
        if (normalized.endsWithIgnoreCase(VERIFICATION_NAME_SUFFIX)) {
            normalized = normalized.substring(0, normalized.length() - VERIFICATION_NAME_SUFFIX.length()).trim();
        }
        return normalized;
    }

    private static List<Map<String, Object>> buildIncomeDetailSections(
        List<Applicant__c> personalApplicants,
        Map<Id, List<Applicant_Income__c>> incomesByApplicant,
        Map<Id, Applicant_Employment__c> employmentByApplicant,
        Map<Id, Map<String, Object>> bankStatementsByApplicant
    ) {
        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        for (Applicant__c applicant : personalApplicants) {
            String key = String.valueOf(applicant.Id);
            sections.add(applicantSection(applicant, buildIncomeDetailFields(
                applicant,
                key,
                incomesByApplicant.get(applicant.Id),
                employmentByApplicant.get(applicant.Id),
                bankStatementsByApplicant.get(applicant.Id)
            )));
        }
        return sections;
    }

    private static List<Map<String, Object>> buildFinancialPerformanceSections(
        List<Applicant__c> personalApplicants,
        Application_Line_Item__c primaryLineItem,
        Map<Id, List<Applicant_Income__c>> incomesByApplicant
    ) {
        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        if (personalApplicants == null || personalApplicants.isEmpty()) {
            return sections;
        }

        for (Applicant__c applicant : personalApplicants) {
            String key = String.valueOf(applicant.Id);
            List<Applicant_Income__c> incomes = incomesByApplicant != null ? incomesByApplicant.get(applicant.Id) : null;
            Applicant_Income__c declaredIncome = findIncomeByName(incomes, INCOME_RECORD_DECLARED);
            Applicant_Income__c bankStatementIncome = findIncomeByName(incomes, INCOME_RECORD_BANK_STATEMENT);

            Decimal annualIncome = applicant.Declared_income__c;
            if (annualIncome == null && declaredIncome != null) {
                annualIncome = declaredIncome.Consolidated_Yearly_Income__c;
            }
            if (annualIncome == null && bankStatementIncome != null) {
                annualIncome = bankStatementIncome.Consolidated_Yearly_Income__c;
            }

            Decimal emiAmount = primaryLineItem != null ? primaryLineItem.EMI_Amount__c : null;
            String foirDisplay = null;
            if (emiAmount != null && annualIncome != null && annualIncome != 0) {
                Decimal foir = ((emiAmount * 12) / annualIncome) * 100;
                foirDisplay = foir.setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString() + '%';
            }

            sections.add(applicantSection(applicant, new List<Map<String, Object>>{
                incomeDetailField('foir-' + key, 'FOIR', foirDisplay, INCOME_FIELD_TEXT, null, false, null)
            }));
        }
        return sections;
    }

    private static List<Map<String, Object>> buildIncomeDetailFields(
        Applicant__c applicant,
        String applicantKey,
        List<Applicant_Income__c> incomes,
        Applicant_Employment__c employment,
        Map<String, Object> bankStatementDoc
    ) {
        Applicant_Income__c declaredIncome = findIncomeByName(incomes, INCOME_RECORD_DECLARED);
        Applicant_Income__c bankStatementIncome = findIncomeByName(incomes, INCOME_RECORD_BANK_STATEMENT);
        Boolean hasBankingIncome = hasBankingIncomeSource(incomes);
        Map<String, Object> doc = bankStatementDoc != null
            ? bankStatementDoc
            : new Map<String, Object>();

        String employerName = employment != null
            ? employment.Employer_Business_Name__c
            : null;
        if (String.isBlank(employerName) && declaredIncome != null) {
            employerName = declaredIncome.Employer_Business_Name__c;
        }

        String salariedSelfEmployed = String.isNotBlank(applicant.Income_Category__c)
            ? applicant.Income_Category__c
            : (employment != null ? employment.Salaried_Self_employed__c : null);

        String declaredIncomeLinkLabel = null;
        Boolean hasDeclaredIncomeLink = false;
        if (doc.get('hasDocumentLink') == true) {
            hasDeclaredIncomeLink = true;
            declaredIncomeLinkLabel = 'Uploaded Bank Statement';
        }

        String currentYears = employment != null && employment.Current_years_in_Employment_Business__c != null
            ? String.valueOf(employment.Current_years_in_Employment_Business__c) : '';
        String totalYears = employment == null ? null : (employment.Years_in_employment_business__c != null ? String.valueOf(employment.Years_in_employment_business__c) : '');
        String abbConsolidated = bankStatementIncome != null ? formatCurrency(bankStatementIncome.Consolidated_Yearly_Income__c) : null;
        return new List<Map<String, Object>>{
            incomeDetailField('legalEntity-' + applicantKey, 'Legal Entity Identifier', resolveLegalEntityIdentifier(applicant), INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('incomeSource-' + applicantKey, 'Income from Income Source', resolveIncomeFromSources(incomes), INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('recipientBank-' + applicantKey, 'Name of the Recipient Bank', resolveRecipientBankName(incomes), INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('employmentType-' + applicantKey, 'Salaried/Self Employed', salariedSelfEmployed, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('employer-' + applicantKey, 'Employer Business Name', employerName, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('currentYears-' + applicantKey, 'Current years in Employment/Business', currentYears, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('totalYears-' + applicantKey, 'Total years in Employment/Business', totalYears, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('profile-' + applicantKey, 'Profile', applicant.Profile__c, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('bsrOccupation-' + applicantKey, 'BSR Occupation', null, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('verificationMethod-' + applicantKey, 'Income Verification Method', resolveIncomeVerificationMethod(declaredIncome, bankStatementIncome, incomes), INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('abbConsolidated-' + applicantKey, 'ABB (Consolidated)', abbConsolidated, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('abbValues-' + applicantKey, 'ABB Values (Last 6 Months)', null, INCOME_FIELD_BUTTON, 'View ABB Values', hasBankingIncome, null),
            incomeDetailLinkField(
                'bankAnalyzer-' + applicantKey,
                'Bank Statement Analyzer',
                'Download Excel Report',
                bankStatementIncome != null && hasDeclaredIncomeLink,
                doc
            ),
            incomeDetailLinkField(
                'declaredIncome-' + applicantKey,
                'Declared Income',
                declaredIncomeLinkLabel,
                hasDeclaredIncomeLink,
                doc
            )
        };
    }

    private static Map<String, Object> incomeDetailLinkField(
        String id,
        String label,
        String actionLabel,
        Boolean showAction,
        Map<String, Object> doc
    ) {
        Map<String, Object> safeDoc = doc != null ? doc : new Map<String, Object>();
        Map<String, Object> field = incomeDetailField(
            id,
            label,
            null,
            INCOME_FIELD_LINK,
            actionLabel,
            showAction,
            (String) safeDoc.get('contentVersionId')
        );
        field.put('contentDocumentId', safeDoc.get('contentDocumentId'));
        field.put('fileType', safeDoc.get('fileType'));
        return field;
    }

    private static Map<String, Object> incomeDetailField(String id, String label, String value, String displayType, String actionLabel, Boolean showAction, String contentVersionId) {
        return new Map<String, Object>{
            'id' => id, 'label' => label, 'value' => value, 'displayType' => displayType,
            'actionLabel' => actionLabel, 'showAction' => showAction == true, 'contentVersionId' => contentVersionId
        };
    }

    private static Map<String, Object> applicantSection(Applicant__c applicant, List<Map<String, Object>> fields) {
        return new Map<String, Object>{
            'id' => String.valueOf(applicant.Id),
            'title' => resolveApplicantTitle(applicant),
            'applicantType' => applicant.Applicant_Type__c,
            'fields' => fields
        };
    }

    private static Applicant_Income__c findIncomeByName(
        List<Applicant_Income__c> incomes,
        String recordName
    ) {
        if (incomes == null || String.isBlank(recordName)) {
            return null;
        }
        for (Applicant_Income__c income : incomes) {
            if (recordName.equalsIgnoreCase(income.Name)) {
                return income;
            }
        }
        return null;
    }

    private static Boolean hasBankingIncomeSource(List<Applicant_Income__c> incomes) {
        if (incomes == null) {
            return false;
        }
        for (Applicant_Income__c income : incomes) {
            if ('Banking'.equalsIgnoreCase(income.Income_Source__c)
                || INCOME_RECORD_BANK_STATEMENT.equalsIgnoreCase(income.Name)) {
                return true;
            }
        }
        return false;
    }

    private static String resolveLegalEntityIdentifier(Applicant__c applicant) {
        if (applicant == null) {
            return null;
        }
        if (String.isNotBlank(applicant.Company_Name__c)) {
            return applicant.Company_Name__c;
        }
        return applicant.Entity_Type__c;
    }

    private static String resolveIncomeFromSources(List<Applicant_Income__c> incomes) {
        if (incomes == null || incomes.isEmpty()) {
            return null;
        }
        Set<String> sources = new Set<String>();
        for (Applicant_Income__c income : incomes) {
            if (income.Primary_Income_Source__c == true && String.isNotBlank(income.Income_Source__c)) {
                sources.add(income.Income_Source__c);
            }
        }
        if (sources.isEmpty()) {
            for (Applicant_Income__c income : incomes) {
                if (String.isNotBlank(income.Income_Source__c)) {
                    sources.add(income.Income_Source__c);
                }
            }
        }
        return sources.isEmpty() ? null : String.join(new List<String>(sources), ', ');
    }

    private static String resolveRecipientBankName(List<Applicant_Income__c> incomes) {
        if (incomes == null) {
            return null;
        }
        for (Applicant_Income__c income : incomes) {
            if (income.Income_Detail_Bank_Master__r != null
                && String.isNotBlank(income.Income_Detail_Bank_Master__r.Name)) {
                return income.Income_Detail_Bank_Master__r.Name;
            }
        }
        return null;
    }

    private static String resolveIncomeVerificationMethod(
        Applicant_Income__c declaredIncome,
        Applicant_Income__c bankStatementIncome,
        List<Applicant_Income__c> incomes
    ) {
        if (bankStatementIncome != null) {
            return 'Bank Statement';
        }
        if (declaredIncome != null) {
            return 'Declared Annual Income';
        }
        if (incomes != null && !incomes.isEmpty() && String.isNotBlank(incomes[0].Name)) {
            if (INCOME_RECORD_DECLARED.equalsIgnoreCase(incomes[0].Name)) {
                return 'Declared Annual Income';
            }
            return incomes[0].Name;
        }
        return null;
    }

    private static List<Map<String, Object>> buildDeclarationSections(List<Applicant__c> personalApplicants) {
        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        for (Applicant__c applicant : personalApplicants) {
            String key = String.valueOf(applicant.Id);
            Map<String, Object> section = applicantSection(applicant, new List<Map<String, Object>>());
            section.put('items', new List<Map<String, Object>>{
                new Map<String, Object>{
                    'id' => 'dec1-' + key,
                    'kind' => 'declaration',
                    'text' => DECLARATION_RBI_DIRECTORS_TEXT,
                    'answer' => applicant.Is_Applicant_Relative_Of_Director__c,
                    'showAnswer' => String.isNotBlank(applicant.Is_Applicant_Relative_Of_Director__c)
                },
                new Map<String, Object>{
                    'id' => 'dec2-' + key,
                    'kind' => 'declaration',
                    'text' => DECLARATION_RBI_OTHER_BANKS_TEXT,
                    'answer' => applicant.Is_Applicant_Relative_Of_Senior_Officer__c,
                    'showAnswer' => String.isNotBlank(applicant.Is_Applicant_Relative_Of_Senior_Officer__c)
                }
            });
            sections.add(section);
        }
        return sections;
    }

    private static List<Map<String, Object>> buildPersonalDetailFields(
        Applicant__c applicant,
        Application__c application,
        Document_CheckList__c poiDocument
    ) {
        String k = String.valueOf(applicant.Id);
        Boolean isBorrower = 'Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c);
        Boolean isBeneficiary = 'Beneficiary'.equalsIgnoreCase(applicant.Applicant_Type__c);
        Boolean isNonIndividual = isNonIndividualApplicant(applicant);
        Boolean isCv = isCommercialVehicleProduct(application != null ? application.Product__c : null);

        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        if (isNonIndividual && !isBeneficiary) {
            fields.add(fieldRow('entityName-' + k, 'Entity Name', applicant.Company_Name__c));
        } else {
            fields.add(fieldRow('name-' + k, 'Name', formatApplicantName(applicant, poiDocument)));
        }

        if (!isBorrower && !isBeneficiary) {
            fields.add(fieldRow('rel-' + k, 'Relationship with Borrower', applicant.Relationship_with_borrower__c));
        }

        if (isBeneficiary) {
            fields.add(fieldRow('benCat-' + k, 'Beneficial Owner Category', applicant.Beneficial_Owner_Category__c));
            fields.add(fieldRow('relEntity-' + k, 'Relationship with Entity', applicant.Relationship_with_Entity__c));
            fields.add(fieldRow('relType-' + k, 'Relationship Type', applicant.Relationship_Type__c));
            fields.add(fieldRow('share-' + k, 'Shareholding %', formatShareholdingDisplay(applicant.ShareHolding__c)));
            fields.add(fieldRow('poa-' + k, 'POA Holder', formatBooleanDisplay(applicant.POA_Holder__c)));
        }

        fields.add(fieldRow('entityType-' + k, 'Entity Type', resolveEntityTypeDisplay(applicant)));

        if (isNonIndividual && !isBeneficiary) {
            fields.add(fieldRow('eval-' + k, 'Evaluation Type', applicant.Evaluation_Type__c));
            fields.add(fieldRow('incorp-' + k, 'Date of Incorporation', formatDate(applicant.Date_of_Birth__c)));
        } else {
            Date poiDateOfBirth = poiDocument != null && poiDocument.KYC_Date_of_Birth__c != null
                ? poiDocument.KYC_Date_of_Birth__c
                : applicant.Date_of_Birth__c;
            String poiGender = poiDocument != null && String.isNotBlank(poiDocument.Gender__c)
                ? poiDocument.Gender__c
                : applicant.Gender__c;
            fields.add(fieldRow('age-' + k, 'Age', formatAge(poiDateOfBirth)));
            fields.add(fieldRow('dob-' + k, 'Date of Birth', formatDate(poiDateOfBirth)));
            fields.add(fieldRow('gender-' + k, 'Gender', poiGender));
            fields.add(fieldRow('marital-' + k, 'Marital Status', applicant.Marital_status__c));
        }

        if (isNonIndividual && !isBeneficiary && !isCv) {
            fields.add(fieldRow('majorInd-' + k, 'Major Industry', applicant.Major_Industry__c));
            fields.add(fieldRow('minorInd-' + k, 'Minor Industry', applicant.Minor_Industry__c));
        }

        if (isNonIndividual && !isBeneficiary && isCv) {
            fields.add(fieldRow('indName-' + k, 'Industry Name', applicant.Industry_Name__c));
            fields.add(fieldRow('indCode-' + k, 'Industry Code', applicant.Industry_Code__c));
        }

        fields.addAll(new List<Map<String, Object>>{
            fieldRow('profile-' + k, 'Profile', applicant.Profile__c),
            fieldRow('pan-' + k, 'PAN', applicant.PAN_Number__c),
            fieldRow('mobile-' + k, 'Mobile', applicant.Phone__c),
            fieldRow('email-' + k, 'Personal Email', applicant.Email__c)
        });
        return fields;
    }

    private static Applicant__c resolveBorrower(List<Applicant__c> applicants) {
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

    private static Decimal resolveLineItemLoanAmount(Application_Line_Item__c lineItem) {
        if (lineItem == null) {
            return null;
        }
        if (lineItem.Loan_Amount__c != null) {
            return lineItem.Loan_Amount__c;
        }
        Asset__c asset = resolveLineItemAsset(lineItem);
        return asset != null ? asset.Required_Total_Loan_Amount__c : null;
    }

    private static Decimal calculateCurrentExposureAmount(List<Application_Line_Item__c> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return null;
        }
        Decimal total = 0;
        Boolean hasAmount = false;
        for (Application_Line_Item__c lineItem : lineItems) {
            Decimal amount = resolveLineItemLoanAmount(lineItem);
            if (amount != null) {
                total += amount;
                hasAmount = true;
            }
        }
        return hasAmount ? total : null;
    }

    private static Decimal calculateExistingBorrowerExposureAmount(Applicant__c borrower) {
        if (borrower == null || borrower.Applicant_Obligations__r == null) {
            return null;
        }
        Decimal total = 0;
        Boolean hasAmount = false;
        for (Applicant_Obligations__c obligation : borrower.Applicant_Obligations__r) {
            if (isExternalExposureObligation(obligation)) {
                continue;
            }
            if ('Current'.equalsIgnoreCase(obligation.Exposure_Type__c)) {
                continue;
            }
            if (obligation.SOH__c != null) {
                total += obligation.SOH__c;
                hasAmount = true;
            }
        }
        return hasAmount ? total : null;
    }

    private static String resolveApplicantTitle(Applicant__c applicant) {
        return applicant == null ? null : (String.isNotBlank(applicant.Applicant_Tab_Label__c) ? applicant.Applicant_Tab_Label__c : applicant.Applicant_Type__c);
    }

    private static String resolveSchemeName(
        Application_Line_Item__c lineItem,
        Application__c application
    ) {
        if (lineItem != null) {
            if (lineItem.Schemes__r != null && String.isNotBlank(lineItem.Schemes__r.Name)) {
                return lineItem.Schemes__r.Name;
            }
            if (String.isNotBlank(lineItem.Scheme__c)) {
                return lineItem.Scheme__c;
            }
        }
        return joinDisplayParts(
            new List<String>{ application.Product__c, application.Sub_Product__c },
            ' — '
        );
    }

    private static String formatAnnexureDocumentType(Document_CheckList__c document) {
        return joinDisplayParts(
            new List<String>{ document.Document_Type__c, document.Applicant_Type__c },
            ' - '
        );
    }

    private static Map<String, Object> fieldRow(String id, String label, String value) {
        return new Map<String, Object>{ 'id' => id, 'label' => label, 'value' => String.isNotBlank(value) ? value : '—' };
    }

    private static String formatApplicantName(Applicant__c applicant) {
        return formatApplicantName(applicant, null);
    }

    private static String formatApplicantName(Applicant__c applicant, Document_CheckList__c poiDocument) {
        if (applicant == null) {
            return null;
        }
        if (isNonIndividualApplicant(applicant) && String.isNotBlank(applicant.Company_Name__c)) {
            return applicant.Company_Name__c.trim();
        }
        String poiName = formatPoiApplicantName(poiDocument);
        if (String.isNotBlank(poiName)) {
            return poiName;
        }
        return joinDisplayParts(
            new List<String>{ applicant.Customer_First_Name__c, applicant.Customer_Last_Name__c },
            ' '
        );
    }

    private static String formatPoiApplicantName(Document_CheckList__c poiDocument) {
        if (poiDocument == null) {
            return null;
        }
        return joinDisplayParts(
            new List<String>{ poiDocument.First_Name__c, poiDocument.Last_Name__c },
            ' '
        );
    }

    private static Boolean isNonIndividualApplicant(Applicant__c applicant) {
        return applicant != null && GenericUtility.isNonIndividualApplicationType(applicant.Type__c);
    }

    private static Map<String, String> entityTypeLabelByValue;

    private static String resolveEntityTypeDisplay(Applicant__c applicant) {
        if (applicant == null) {
            return null;
        }
        if (String.isBlank(applicant.Entity_Type__c)) {
            return applicant.Type__c;
        }
        if (entityTypeLabelByValue == null) {
            entityTypeLabelByValue = new Map<String, String>();
            Schema.SObjectField entityTypeField = Applicant__c.SObjectType.getDescribe()
                .fields.getMap()
                .get('Entity_Type__c');
            if (entityTypeField != null) {
                for (Schema.PicklistEntry entry : entityTypeField.getDescribe().getPicklistValues()) {
                    entityTypeLabelByValue.put(entry.getValue(), entry.getLabel());
                }
            }
        }
        return entityTypeLabelByValue.containsKey(applicant.Entity_Type__c)
            ? entityTypeLabelByValue.get(applicant.Entity_Type__c)
            : applicant.Entity_Type__c;
    }

    private static Boolean isCommercialVehicleProduct(String product) {
        if (String.isBlank(product)) {
            return false;
        }
        String normalized = product.trim().toLowerCase();
        return normalized == 'cv'
            || normalized == 'scv'
            || normalized == 'lcv'
            || normalized == 'mhce'
            || normalized == 'ce'
            || normalized.contains('commercial vehicle');
    }

    private static Boolean isTwoWheelerProduct(String product) {
        if (String.isBlank(product)) {
            return false;
        }
        String normalized = product.trim().toLowerCase();
        return normalized == '2w' || normalized.contains('two wheeler');
    }

    private static Boolean isTractorProduct(String product) {
        if (String.isBlank(product)) {
            return false;
        }
        return product.trim().equalsIgnoreCase('Tractor');
    }

    private static Boolean isPassengerVehicleProduct(String product) {
        if (String.isBlank(product)) {
            return false;
        }
        String normalized = product.trim().toLowerCase();
        return normalized == '4w' || normalized == 'pv' || normalized.contains('passenger vehicle');
    }

    private static String formatAge(Date dateOfBirth) {
        if (dateOfBirth == null) {
            return null;
        }
        Integer years = Date.today().year() - dateOfBirth.year();
        if (Date.today().dayOfYear() < dateOfBirth.dayOfYear()) {
            years -= 1;
        }
        return years >= 0 ? String.valueOf(years) : null;
    }

    private static String formatShareholdingDisplay(Decimal shareholding) {
        if (shareholding == null) {
            return null;
        }
        return shareholding.setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString() + '%';
    }

    private static String formatBooleanDisplay(Boolean value) {
        if (value == null) {
            return null;
        }
        return value ? 'Yes' : 'No';
    }

    private static List<Applicant__c> filterApplicantsByType(
        List<Applicant__c> applicants,
        String applicantType,
        Boolean includeType
    ) {
        List<Applicant__c> filtered = new List<Applicant__c>();
        if (applicants == null) {
            return filtered;
        }
        for (Applicant__c applicant : applicants) {
            Boolean matchesType = isApplicantTypeMatch(applicantType, applicant.Applicant_Type__c);
            if (includeType == matchesType) {
                filtered.add(applicant);
            }
        }
        filtered.sort(new ApplicantDisplayOrderComparator());
        return filtered;
    }

    private static Boolean isApplicantTypeMatch(String leftType, String rightType) {
        String leftKey = normalizeApplicantTypeKey(leftType);
        String rightKey = normalizeApplicantTypeKey(rightType);
        return leftKey != null && rightKey != null && leftKey == rightKey;
    }

    private static String normalizeApplicantTypeKey(String applicantType) {
        if (String.isBlank(applicantType)) {
            return null;
        }
        return applicantType.trim().toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static List<Map<String, Object>> buildBusinessDetailSections(
        Application__c application,
        List<Applicant__c> applicants,
        Map<Id, Verification__c> officeFiByApplicant
    ) {
        if (application == null || applicants == null || applicants.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        Map<Id, Verification__c> officeByApplicant = officeFiByApplicant != null
            ? officeFiByApplicant
            : new Map<Id, Verification__c>();
        List<Map<String, Object>> sections = new List<Map<String, Object>>();

        for (Applicant__c applicant : applicants) {
            if (!isNonIndividualApplicant(applicant)) {
                continue;
            }
            Verification__c officeFi = officeByApplicant.get(applicant.Id);
            // Business details for NI are sourced from registered/office FI verification.
            if (officeFi == null) {
                continue;
            }

            String key = String.valueOf(applicant.Id);
            sections.add(applicantSection(applicant, buildBusinessDetailFields(applicant, officeFi, application, key)));
        }
        return sections;
    }

    private static List<Map<String, Object>> buildBusinessDetailFields(
        Applicant__c applicant,
        Verification__c officeFi,
        Application__c application,
        String applicantKey
    ) {
        Boolean isNi = isNonIndividualApplicant(applicant);
        Boolean is2w = isTwoWheelerProduct(application != null ? application.Product__c : null);

        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        if (isNi) {
            fields.add(fieldRow('company-' + applicantKey, 'Name of the Company', formatApplicantName(applicant)));
        } else {
            fields.add(fieldRow(
                'company-' + applicantKey,
                'Name of the Company',
                officeFi != null ? officeFi.Employer_Business_Name__c : null
            ));
        }

        if (!isNi || is2w) {
            fields.add(fieldRow(
                'bizType-' + applicantKey,
                'Nature of Business',
                officeFi != null ? officeFi.Office_Business_Type__c : null
            ));
        }

        if (isNi && !is2w) {
            fields.add(fieldRow(
                'majorBiz-' + applicantKey,
                'Nature of Business - Major Industry',
                applicant.Major_Industry__c
            ));
            fields.add(fieldRow(
                'minorBiz-' + applicantKey,
                'Nature of Business - Minor Industry',
                applicant.Minor_Industry__c
            ));
        }

        fields.add(fieldRow(
            'yearsBiz-' + applicantKey,
            'Number of years in current Business',
            officeFi != null ? formatDecimalDisplay(officeFi.Current_Experience_Years__c) : null
        ));
        fields.add(fieldRow(
            'officeOwn-' + applicantKey,
            'Office Owned/rented',
            officeFi != null ? officeFi.Business_Premise__c : null
        ));
        fields.add(fieldRow(
            'kmBranch-' + applicantKey,
            'K.M from Branch',
            formatKmFromBranch(officeFi != null ? officeFi.Coordinates_Distance__c : null)
        ));
        return fields;
    }

    private static List<Map<String, Object>> buildBeneficiaryIncomeSections(
        List<Applicant__c> beneficiaryApplicants,
        Map<Id, List<Applicant_Income__c>> incomesByApplicant,
        Map<Id, Applicant_Employment__c> employmentByApplicant
    ) {
        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        if (beneficiaryApplicants == null || beneficiaryApplicants.isEmpty()) {
            return sections;
        }

        for (Applicant__c applicant : beneficiaryApplicants) {
            String key = String.valueOf(applicant.Id);
            sections.add(applicantSection(
                applicant,
                buildBeneficiaryIncomeFields(
                    applicant,
                    key,
                    incomesByApplicant.get(applicant.Id),
                    employmentByApplicant.get(applicant.Id)
                )
            ));
        }
        return sections;
    }

    private static List<Map<String, Object>> buildBeneficiaryIncomeFields(
        Applicant__c applicant,
        String applicantKey,
        List<Applicant_Income__c> incomes,
        Applicant_Employment__c employment
    ) {
        String employerName = employment != null
            ? employment.Employer_Business_Name__c
            : null;
        Applicant_Income__c declaredIncome = findIncomeByName(incomes, INCOME_RECORD_DECLARED);
        if (String.isBlank(employerName) && declaredIncome != null) {
            employerName = declaredIncome.Employer_Business_Name__c;
        }

        String salariedSelfEmployed = String.isNotBlank(applicant.Income_Category__c)
            ? applicant.Income_Category__c
            : (employment != null ? employment.Salaried_Self_employed__c : null);

        return new List<Map<String, Object>>{
            incomeDetailField('benLegalEntity-' + applicantKey, 'Legal Entity Identifier', resolveLegalEntityIdentifier(applicant), INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('benIncomeSource-' + applicantKey, 'Income from Income Source', resolveIncomeFromSources(incomes), INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('benRecipientBank-' + applicantKey, 'Name of the Recipient Bank', resolveRecipientBankName(incomes), INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('benEmploymentType-' + applicantKey, 'Salaried/Self Employed', salariedSelfEmployed, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('benEmployer-' + applicantKey, 'Employer Business Name', employerName, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('benProfile-' + applicantKey, 'Profile', applicant.Profile__c, INCOME_FIELD_TEXT, null, false, null)
        };
    }

    private static String joinDisplayParts(List<String> parts, String separator) {
        List<String> values = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                values.add(part.trim());
            }
        }
        return values.isEmpty() ? null : String.join(values, separator);
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) {
            return null;
        }
        return '₹' + amount.setScale(0, RoundingMode.HALF_UP).format();
    }

    private static String formatPercent(Decimal value) {
        if (value == null) {
            return null;
        }
        return value.setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString() + '%';
    }

    private static String formatTenure(Decimal tenureMonths) {
        if (tenureMonths == null) {
            return null;
        }
        Integer months = tenureMonths.intValue();
        return months + (months == 1 ? ' month' : ' months');
    }

    private static String formatDate(Date value) {
        if (value == null) {
            return null;
        }
        DateTime dt = DateTime.newInstance(value.year(), value.month(), value.day());
        return dt.format('dd-MMM-yyyy');
    }

    private static Id resolveApplicationId(Map<String, Object> args) {
        Object raw = args != null ? args.get('recordId') : null;
        if (raw == null) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception e) {
            return null;
        }
    }

    private static List<Map<String, Object>> buildBankAccountColumns(List<Applicant__c> applicants) {
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        if (applicants == null) {
            return columns;
        }
        for (Applicant__c applicant : applicants) {
            String k = String.valueOf(applicant.Id);
            columns.add(applicantSection(applicant, new List<Map<String, Object>>{
                fieldRow('bank-' + k, 'Do you have a bank account across any of the banks?', applicant.Has_Bank_Account__c),
                fieldRow('open-' + k, 'Wish to open a savings account with Bank', applicant.Interested_In_Opening_Savings_Account__c)
            }));
        }
        return columns;
    }

    private static List<Map<String, Object>> buildPricingLtvFields(Application_Line_Item__c lineItem, Asset__c asset) {
        return new List<Map<String, Object>>{
            fieldRow('pricing-irr', 'Threshold Net IRR', formatPercent(lineItem != null ? lineItem.CRM_IRR__c : null)),
            fieldRow('pricing-ltv', 'Threshold LTV', formatPercent(lineItem != null ? lineItem.Calculated_Net_LTV__c : null)),
            fieldRow('pricing-variant', 'Vehicle Variant', asset != null ? asset.Variant__c : null)
        };
    }

    private static List<Map<String, Object>> buildOfferEngineFields(
        Application__c application,
        Application_Line_Item__c lineItem,
        Applicant__c borrower
    ) {
        String isStp = application != null && 'STP'.equalsIgnoreCase(application.Sanction_Status__c) ? 'Yes' : 'No';
        return new List<Map<String, Object>>{
            fieldRow('offer-loan', 'Loan Amount', formatCurrency(resolveLineItemLoanAmount(lineItem))),
            fieldRow('offer-irr', 'Threshold Net IRR', formatPercent(lineItem != null ? lineItem.CRM_IRR__c : null)),
            fieldRow('offer-crm', 'Required CRM IRR', formatPercent(lineItem != null ? lineItem.CRM_IRR__c : null)),
            fieldRow('offer-income', 'Net Annual Income', formatCurrency(borrower != null ? borrower.Declared_income__c : null)),
            fieldRow('offer-emi', 'EMI Amount', formatCurrency(lineItem != null ? lineItem.EMI_Amount__c : null)),
            fieldRow('offer-tenure', 'Tenure', formatTenure(lineItem != null ? lineItem.Tenure__c : null)),
            fieldRow('offer-roi', 'Rate of Interest', formatPercent(lineItem != null ? lineItem.ROI__c : null)),
            fieldRow('offer-ltv', 'Net LTV', formatPercent(lineItem != null ? lineItem.Calculated_Net_LTV__c : null)),
            fieldRow('offer-bureau', 'Bureau Surrogate Offer', lineItem != null ? formatDecimalDisplay(lineItem.Bureau_Surrogate_Offer__c) : null),
            fieldRow('offer-stp', 'Is STP', isStp)
        };
    }

    private static List<Map<String, Object>> buildCreditBureauColumns(
        List<Applicant__c> applicants,
        LineItemBureauContext bureauContext,
        Map<Id, Map<String, String>> creditReportsByApplicant
    ) {
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        if (applicants == null || applicants.isEmpty()) {
            return columns;
        }

        Set<Id> reportVersionIds = new Set<Id>();
        for (Applicant__c applicant : applicants) {
            Map<String, String> applicantReports = creditReportsByApplicant != null
                ? creditReportsByApplicant.get(applicant.Id)
                : null;
            Map<String, String> reports = applicantReports != null ? applicantReports : new Map<String, String>();
            collectCreditReportVersionIds(reports, isNonIndividualApplicant(applicant), reportVersionIds);
        }
        Map<Id, ContentVersion> versionById = queryContentVersionsById(reportVersionIds);

        for (Applicant__c applicant : applicants) {
            Boolean isNonIndividual = isNonIndividualApplicant(applicant);
            String applicantKey = String.valueOf(applicant.Id);
            Boolean isBorrower = APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicant.Applicant_Type__c);
            Map<String, String> applicantReports = creditReportsByApplicant != null
                ? creditReportsByApplicant.get(applicant.Id)
                : null;
            String bureauType = isNonIndividual ? CREDIT_REPORT_CRIF : CREDIT_REPORT_CIBIL;
            Map<String, String> reports = applicantReports != null ? applicantReports : new Map<String, String>();
            List<Map<String, Object>> reportButtons = new List<Map<String, Object>>();
            if (isNonIndividual) {
                reportButtons.add(buildCreditReportButton(
                    applicantKey + '-crif-report',
                    'CRIF Report',
                    CREDIT_REPORT_CRIF,
                    reports.get(CREDIT_REPORT_CRIF),
                    versionById
                ));
            } else {
                reportButtons.add(buildCreditReportButton(
                    applicantKey + '-cibil-report',
                    'CIBIL Report',
                    CREDIT_REPORT_CIBIL,
                    reports.get(CREDIT_REPORT_CIBIL),
                    versionById
                ));
                reportButtons.add(buildCreditReportButton(
                    applicantKey + '-equifax-report',
                    'Equifax Report',
                    CREDIT_REPORT_EQUIFAX,
                    reports.get(CREDIT_REPORT_EQUIFAX),
                    versionById
                ));
            }

            columns.add(new Map<String, Object>{
                'id' => applicantKey,
                'title' => resolveApplicantTitle(applicant),
                'applicantType' => applicant.Applicant_Type__c,
                'bureauType' => bureauType,
                'reportButtons' => reportButtons,
                'fields' => buildCreditBureauDetailFields(
                    applicant,
                    applicantKey,
                    isBorrower,
                    bureauContext,
                    isNonIndividual
                )
            });
        }
        return columns;
    }

    private static void collectCreditReportVersionIds(
        Map<String, String> reports,
        Boolean isNonIndividual,
        Set<Id> reportVersionIds
    ) {
        if (reports == null || reportVersionIds == null) {
            return;
        }
        if (isNonIndividual == true) {
            addCreditReportVersionId(reports.get(CREDIT_REPORT_CRIF), reportVersionIds);
            return;
        }
        addCreditReportVersionId(reports.get(CREDIT_REPORT_CIBIL), reportVersionIds);
        addCreditReportVersionId(reports.get(CREDIT_REPORT_EQUIFAX), reportVersionIds);
    }

    private static void addCreditReportVersionId(String versionId, Set<Id> reportVersionIds) {
        if (String.isBlank(versionId) || reportVersionIds == null) {
            return;
        }
        reportVersionIds.add((Id) versionId);
    }

    private static Map<String, Object> buildCreditReportButton(
        String buttonId,
        String label,
        String reportType,
        String contentVersionId,
        Map<Id, ContentVersion> versionById
    ) {
        Map<String, Object> button = new Map<String, Object>{
            'id' => buttonId,
            'label' => label,
            'reportType' => reportType,
            'hasDocumentLink' => false
        };
        if (String.isNotBlank(contentVersionId)) {
            applyDocumentPreviewFields(button, (Id) contentVersionId, versionById);
            button.put('hasDocumentLink', String.isNotBlank(contentVersionId));
        }
        return button;
    }

    private static List<Map<String, Object>> buildCreditBureauDetailFields(
        Applicant__c applicant,
        String applicantKey,
        Boolean isBorrower,
        LineItemBureauContext bureauContext,
        Boolean nonIndividualOnly
    ) {
        String prefix = nonIndividualOnly ? 'crif' : 'cibil';
        String scoreLabel = nonIndividualOnly ? 'CRIF Score' : 'CIBIL Score';
        List<Map<String, Object>> fields = new List<Map<String, Object>>{
            fieldRow(prefix + '-score-' + applicantKey, scoreLabel, applicant.Scorecard_Decision__c),
            fieldRow(
                prefix + '-bureau-' + applicantKey,
                'Bureau Surrogate Offer',
                isBorrower ? bureauContext.bureauSurrogate : null
            )
        };

        if (!nonIndividualOnly) {
            fields.add(fieldRow(prefix + '-min-' + applicantKey, 'Scheme Minimum CIBIL', bureauContext.schemeMinCibil));
            fields.add(fieldRow(prefix + '-max-' + applicantKey, 'Scheme Maximum CIBIL', bureauContext.schemeMaxCibil));
        }

        fields.add(fieldRow(prefix + '-recent-' + applicantKey, 'Recent Date', null));
        fields.add(fieldRow(prefix + '-oldest-' + applicantKey, 'Oldest Date', null));
        fields.add(fieldRow(prefix + '-written-' + applicantKey, 'Written off Amount', null));
        fields.add(fieldRow(prefix + '-enquiries-' + applicantKey, 'No of Enquiries (6 months)', null));
        return fields;
    }

    private static String resolveCreditReportKey(Document_CheckList__c document) {
        String combined = joinDisplayParts(
            new List<String>{ document.Document_Type__c, document.Name },
            ' '
        );
        if (String.isBlank(combined)) {
            return null;
        }
        String normalized = combined.toUpperCase();
        if (normalized.contains('EQUIFAX')) {
            return CREDIT_REPORT_EQUIFAX;
        }
        if (normalized.contains('CRIF')) {
            return CREDIT_REPORT_CRIF;
        }
        if (normalized.contains('CIBIL')) {
            return CREDIT_REPORT_CIBIL;
        }
        return null;
    }

    private static List<Applicant__c> collectPersonalApplicantsSorted(List<Applicant__c> applicants) {
        List<Applicant__c> personalApplicants = new List<Applicant__c>();
        if (applicants == null) {
            return personalApplicants;
        }
        for (Applicant__c applicant : applicants) {
            String applicantType = applicant.Applicant_Type__c;
            Boolean isPersonalApplicant = false;
            if (String.isNotBlank(applicantType)) {
                for (String allowedType : PERSONAL_DETAIL_APPLICANT_TYPES) {
                    if (isApplicantTypeMatch(allowedType, applicantType)) {
                        isPersonalApplicant = true;
                        break;
                    }
                }
                if (!isPersonalApplicant) {
                    String normalizedType = normalizeApplicantTypeKey(applicantType);
                    isPersonalApplicant = normalizedType != null && normalizedType.startsWith('g');
                }
            }
            if (isPersonalApplicant) {
                personalApplicants.add(applicant);
            }
        }
        personalApplicants.sort(new ApplicantDisplayOrderComparator());
        return personalApplicants;
    }

    private static List<Map<String, Object>> buildVerificationDetailSections(
        List<Applicant__c> personalApplicants,
        Map<Id, Verification__c> verificationByApplicant,
        String sectionType
    ) {
        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        Map<Id, Verification__c> byApplicant = verificationByApplicant != null
            ? verificationByApplicant
            : new Map<Id, Verification__c>();

        for (Applicant__c applicant : personalApplicants) {
            Verification__c verification = byApplicant.get(applicant.Id);
            if (verification == null) {
                continue;
            }

            String key = String.valueOf(applicant.Id);
            Map<String, Object> section = applicantSection(
                applicant,
                verificationDetailFields(sectionType, key, verification)
            );

            if ('fiPermanent'.equals(sectionType)) {
                section.put('fiReportAction', buildFiReportAction(key, verification, 'c__permanentFI', 'View Perm FI Report'));
                section.put('fiReportPosition', 'bottom');
            } else if ('fiRegistered'.equals(sectionType)) {
                section.put('fiReportAction', buildFiReportAction(key, verification, 'c__permanentFI', 'View Reg FI Report'));
                section.put('fiReportPosition', 'bottom');
            } else if ('fiResidence'.equals(sectionType)) {
                section.put('fiReportAction', buildFiReportAction(key, verification, 'c__residenceFI', 'View Resi FI Report'));
                section.put('fiReportPosition', 'top');
            } else if ('fiOffice'.equals(sectionType)) {
                section.put('fiReportAction', buildFiReportAction(key, verification, 'c__officeFI', 'View Office FI Report'));
                section.put('fiReportPosition', 'bottom');
            }

            sections.add(section);
        }
        return sections;
    }

    private static List<Map<String, Object>> verificationDetailFields(String sectionType, String key, Verification__c v) {
        if ('fiPermanent'.equals(sectionType) || 'fiRegistered'.equals(sectionType)) {
            return new List<Map<String, Object>>{
                incomeDetailField('perm-fi-type-' + key, 'Own/Rental/Parental', v == null ? null : v.Residence_Type__c, INCOME_FIELD_TEXT, null, false, null),
                incomeDetailField('perm-fi-years-house-' + key, 'Number of years in current house', v == null ? null : formatDecimalDisplay(v.Years_in_Residence__c), INCOME_FIELD_TEXT, null, false, null),
                incomeDetailField('perm-fi-years-city-' + key, 'Number of years in city', v == null ? null : formatDecimalDisplay(v.Years_in_City__c), INCOME_FIELD_TEXT, null, false, null),
                incomeDetailField('perm-fi-km-branch-' + key, 'KM from Branch', formatKmFromBranch(v == null ? null : v.Coordinates_Distance__c), INCOME_FIELD_TEXT, null, false, null)
            };
        }
        if ('fiResidence'.equals(sectionType)) {
            return new List<Map<String, Object>>{
                incomeDetailField('fi-res-person-' + key, 'Person Met', v == null ? null : v.Name_of_Person_Met__c, INCOME_FIELD_TEXT, null, false, null),
                incomeDetailField('fi-res-address-' + key, 'Address tallies with app form', v == null ? null : v.Same_Address_as_in_Application__c, INCOME_FIELD_TEXT, null, false, null),
                incomeDetailField('fi-res-remark-' + key, 'Overall Remark', v == null ? null : v.Remarks__c, INCOME_FIELD_TEXT, null, false, null)
            };
        }
        return new List<Map<String, Object>>{
            incomeDetailField('fi-off-address-' + key, 'Address tallies with app form', v == null ? null : v.Same_Address_as_in_Application__c, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('fi-off-type-' + key, 'Office Type', v == null ? null : v.Office_Business_Type__c, INCOME_FIELD_TEXT, null, false, null),
            incomeDetailField('fi-off-remark-' + key, 'Overall Remark', v == null ? null : v.Remarks__c, INCOME_FIELD_TEXT, null, false, null)
        };
    }

    private static Map<String, Object> buildFiReportAction(String applicantKey, Verification__c verification, String componentName, String labelPrefix) {
        String verificationId = verification != null ? String.valueOf(verification.Id) : null;
        return new Map<String, Object>{
            'id' => 'fi-report-' + applicantKey,
            'label' => labelPrefix,
            'verificationId' => verificationId,
            'investigationId' => verification != null && verification.Investigations__c != null ? String.valueOf(verification.Investigations__c) : null,
            'componentName' => componentName,
            'hasFiLink' => String.isNotBlank(verificationId)
        };
    }

    private static String formatKmFromBranch(Decimal distanceMeters) {
        if (distanceMeters == null) {
            return null;
        }
        Decimal kilometers = distanceMeters / 1000;
        return kilometers.setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString();
    }

    private static Map<String, Object> buildBriefDetails(List<Applicant__c> applicants, Application__c application) {
        Applicant__c borrower = resolveBorrower(applicants);
        Boolean showCreditAssessmentButton = showBriefCreditAssessmentButton(application, borrower);
        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        for (Applicant__c applicant : collectPersonalApplicantsSorted(applicants)) {
            Map<String, Object> section = applicantSection(
                applicant,
                new List<Map<String, Object>>{
                    fieldRow('justificationRemark', 'Justification Remark', applicant.Justification_Remark__c)
                }
            );
            if (showCreditAssessmentButton == true
                && 'Borrower'.equalsIgnoreCase(applicant.Applicant_Type__c)) {
                section.put('showCreditAssessmentButton', true);
            }
            sections.add(section);
        }

        return new Map<String, Object>{
            'sectionTitle' => BRIEF_SECTION_TITLE,
            'sections' => sections
        };
    }

    private static Boolean showBriefCreditAssessmentButton(
        Application__c application,
        Applicant__c borrower
    ) {
        if (application == null || borrower == null || String.isBlank(application.Product__c)) {
            return false;
        }

        String product = application.Product__c.trim();
        Boolean isCv = product.equalsIgnoreCase('CV');
        Boolean isPv = product.equalsIgnoreCase('4W') || product.equalsIgnoreCase('PV');
        if (!isCv && !isPv) {
            return false;
        }
        if (isCv) {
            return true;
        }

        if (borrower.Assets__r == null || borrower.Assets__r.isEmpty()) {
            return false;
        }
        return 'Commercial'.equalsIgnoreCase(borrower.Assets__r[0].Purpose_of_purchase__c);
    }

    private static List<Map<String, Object>> buildExposureSections(
        List<Applicant__c> personalApplicants,
        ExposureObligationBuckets obligationBuckets
    ) {
        if (personalApplicants.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        for (Applicant__c applicant : personalApplicants) {
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            List<Applicant_Obligations__c> bankExposureObligations =
                obligationBuckets.bankExposureByApplicant.get(applicant.Id);
            if (bankExposureObligations != null) {
                for (Applicant_Obligations__c obligation : bankExposureObligations) {
                    rows.add(mapCamExposureRow(obligation));
                }
            }

            List<Map<String, Object>> externalExposureRows = new List<Map<String, Object>>();
            List<Applicant_Obligations__c> externalExposureObligations =
                obligationBuckets.externalExposureByApplicant.get(applicant.Id);
            if (externalExposureObligations != null) {
                for (Applicant_Obligations__c obligation : externalExposureObligations) {
                    externalExposureRows.add(mapCamExternalExposureRow(obligation));
                }
            }

            Map<String, Object> section = applicantSection(applicant, new List<Map<String, Object>>());
            section.put('rows', rows);
            section.put('hasRows', !rows.isEmpty());
            section.put('externalExposureRows', externalExposureRows);
            section.put('hasExternalExposureRows', !externalExposureRows.isEmpty());
            sections.add(section);
        }
        return sections;
    }

    private class ExposureObligationBuckets {
        public Map<Id, List<Applicant_Obligations__c>> bankExposureByApplicant =
            new Map<Id, List<Applicant_Obligations__c>>();
        public Map<Id, List<Applicant_Obligations__c>> externalExposureByApplicant =
            new Map<Id, List<Applicant_Obligations__c>>();
    }

    private static Boolean isExternalExposureObligation(Applicant_Obligations__c obligation) {
        return obligation != null
            && String.isNotBlank(obligation.Type__c)
            && EXTERNAL_EXPOSURE_OBLIGATION_TYPES.contains(obligation.Type__c);
    }

    private static Boolean hasBankExposureDealData(Applicant_Obligations__c obligation) {
        return obligation != null
            && (String.isNotBlank(obligation.Deal_No__c)
                || String.isNotBlank(obligation.Exposure_Type__c)
                || String.isNotBlank(obligation.Deal_Stage__c)
                || String.isNotBlank(obligation.Type_of_Facility__c)
                || String.isNotBlank(obligation.Status_Flag__c)
                || obligation.Deal_Date__c != null
                || obligation.Finance_Amt__c != null
                || obligation.SOH__c != null
                || obligation.Over_Due__c != null);
    }

    private static Boolean hasExternalExposureFieldsPopulated(Applicant_Obligations__c obligation) {
        return obligation != null
            && (String.isNotBlank(obligation.Account_Type__c)
                || String.isNotBlank(obligation.Account_Type_Desc__c)
                || String.isNotBlank(obligation.Financier_Name__c)
                || String.isNotBlank(obligation.Ownership__c)
                || obligation.High_Credit__c != null
                || obligation.Current_Balance__c != null
                || obligation.Amount_Overdue__c != null);
    }

    private static Map<String, Object> mapCamExposureRow(Applicant_Obligations__c obligation) {
        return new Map<String, Object>{
            'id' => String.valueOf(obligation.Id),
            'exposureType' => obligation.Exposure_Type__c,
            'dealStage' => obligation.Deal_Stage__c,
            'dealNo' => obligation.Deal_No__c,
            'dealDate' => obligation.Deal_Date__c == null ? null : obligation.Deal_Date__c.format('yyyy-MM-dd'),
            'product' => obligation.Type_of_Facility__c,
            'statusFlag' => obligation.Status_Flag__c,
            'financeAmountDisplay' => formatCurrency(obligation.Finance_Amt__c),
            'sohDisplay' => formatCurrency(obligation.SOH__c),
            'overDueDisplay' => formatCurrency(obligation.Over_Due__c)
        };
    }

    private static Map<String, Object> mapCamExternalExposureRow(Applicant_Obligations__c obligation) {
        String accountTypeDisplay = String.isNotBlank(obligation.Account_Type_Desc__c)
            ? obligation.Account_Type_Desc__c
            : obligation.Account_Type__c;

        return new Map<String, Object>{
            'id' => String.valueOf(obligation.Id),
            'accountType' => accountTypeDisplay,
            'ownership' => obligation.Ownership__c,
            'highCreditDisplay' => formatCurrency(obligation.High_Credit__c),
            'currentBalanceDisplay' => formatCurrency(obligation.Current_Balance__c),
            'amountOverdueDisplay' => formatCurrency(obligation.Amount_Overdue__c),
            'reasonForOverdue' => obligation.Reason_for_Overdue__c,
            'financierName' => obligation.Financier_Name__c
        };
    }

    private static String formatDecimalDisplay(Decimal value) {
        return value == null ? null : value.stripTrailingZeros().toPlainString();
    }

    private static Map<String, Object> getKycDetailsInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'summary' => new Map<String, Object>(),
            'documents' => new List<Map<String, Object>>(),
            'hasDocuments' => false
        };
        try {
            Id appRecordId = resolveApplicationId(args);
            Id applicantRecordId = null;
            Object applicantRaw = args != null ? args.get('applicantId') : null;
            if (applicantRaw != null) {
                try {
                    applicantRecordId = (Id) applicantRaw;
                } catch (Exception castException) {
                    applicantRecordId = null;
                }
            }
            if (appRecordId == null || applicantRecordId == null) {
                return result;
            }

            List<Applicant__c> applicants = [
                SELECT Id,
                       Customer_First_Name__c,
                       Customer_Last_Name__c,
                       Company_Name__c,
                       Type__c,
                       Applicant_Type__c,
                       Date_of_Birth__c,
                       Phone__c,
                       CKYC_ID__c
                FROM Applicant__c
                WHERE Id = :applicantRecordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (applicants.isEmpty()) {
                return result;
            }
            Applicant__c applicant = applicants[0];

            List<Document_CheckList__c> documents = [
                SELECT Id,
                       Name,
                       Application__c,
                       Applicant_KYC__c,
                       Document_Type__c,
                       PAN_No__c,
                       KYC_Date_of_Birth__c,
                       ContentVersionId__c,
                       Applicant_KYC__r.KYC_No__c,
                       Applicant_KYC__r.Masked_KYC_No__c,
                       Applicant_KYC__r.KYC_DOB__c,
                       Applicant_KYC__r.KYC_Issuance_Date__c,
                       Applicant_KYC__r.KYC_Type__c,
                       (SELECT ContentDocumentId FROM ContentDocumentLinks)
                FROM Document_CheckList__c
                WHERE Application__c = :appRecordId
                  AND Applicant__c = :applicantRecordId
                  AND (Applicant_KYC__c != null OR Document_Type__c = 'PAN')
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
            ];

            Set<Id> orphanVersionIds = new Set<Id>();
            for (Document_CheckList__c document : documents) {
                if (document.ContentDocumentLinks.isEmpty()
                    && String.isNotBlank(document.ContentVersionId__c)) {
                    orphanVersionIds.add((Id) document.ContentVersionId__c);
                }
            }

            Map<Id, ContentVersion> versionById = new Map<Id, ContentVersion>();
            if (!orphanVersionIds.isEmpty()) {
                for (ContentVersion version : [
                    SELECT Id
                    FROM ContentVersion
                    WHERE Id IN :orphanVersionIds
                    WITH SECURITY_ENFORCED
                ]) {
                    versionById.put(version.Id, version);
                }
            }

            Date kycDob = applicant.Date_of_Birth__c;
            for (Document_CheckList__c document : documents) {
                Date rowDob = document.KYC_Date_of_Birth__c;
                if (rowDob == null && document.Applicant_KYC__r != null) {
                    rowDob = document.Applicant_KYC__r.KYC_DOB__c;
                }
                if (kycDob == null && rowDob != null) {
                    kycDob = rowDob;
                    break;
                }
            }

            Integer age = kycDob == null ? null : kycDob.monthsBetween(Date.today()) / 12;
            Map<String, Object> summary = new Map<String, Object>{
                'applicantName' => String.isNotBlank(formatApplicantName(applicant))
                    ? formatApplicantName(applicant)
                    : 'N/A',
                'applicantType' => String.isNotBlank(applicant.Applicant_Type__c)
                    ? applicant.Applicant_Type__c
                    : 'N/A',
                'kycDob' => kycDob != null ? formatDate(kycDob) : 'N/A',
                'age' => age != null ? String.valueOf(age) : 'N/A',
                'mobileNo' => String.isNotBlank(applicant.Phone__c) ? applicant.Phone__c : 'N/A',
                'ckycNumber' => applicant.CKYC_ID__c != null
                    ? String.valueOf(applicant.CKYC_ID__c.longValue())
                    : 'N/A',
                'faceMatchPercentage' => 'N/A',
                'faceLiveliness' => 'N/A'
            };

            List<Map<String, Object>> documentRows = new List<Map<String, Object>>();
            for (Document_CheckList__c document : documents) {
                documentRows.add(buildKycDocumentRow(document, versionById));
            }

            result.put('summary', summary);
            result.put('documents', documentRows);
            result.put('hasDocuments', !documentRows.isEmpty());
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching KYC details: ' + e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> buildKycDocumentRow(
        Document_CheckList__c document,
        Map<Id, ContentVersion> versionById
    ) {
        String docType = String.isNotBlank(document.Document_Type__c)
            ? document.Document_Type__c
            : 'Document';
        if (document.Applicant_KYC__r != null
            && String.isNotBlank(document.Applicant_KYC__r.KYC_Type__c)) {
            docType = document.Applicant_KYC__r.KYC_Type__c;
        }

        String docNumber = 'N/A';
        if (String.isNotBlank(document.PAN_No__c)) {
            docNumber = document.PAN_No__c;
        } else if (document.Applicant_KYC__r != null
            && String.isNotBlank(document.Applicant_KYC__r.Masked_KYC_No__c)) {
            docNumber = document.Applicant_KYC__r.Masked_KYC_No__c;
        } else if (document.Applicant_KYC__r != null
            && String.isNotBlank(document.Applicant_KYC__r.KYC_No__c)) {
            docNumber = document.Applicant_KYC__r.KYC_No__c;
        }

        Date rowDob = document.KYC_Date_of_Birth__c;
        if (rowDob == null && document.Applicant_KYC__r != null) {
            rowDob = document.Applicant_KYC__r.KYC_DOB__c;
        }
        Date issuanceDateValue = document.Applicant_KYC__r != null
            ? document.Applicant_KYC__r.KYC_Issuance_Date__c
            : null;

        String issuanceDate = issuanceDateValue != null ? formatDate(issuanceDateValue) : 'N/A';
        String docDob = rowDob != null ? formatDate(rowDob) : 'N/A';

        Boolean hasFile = !document.ContentDocumentLinks.isEmpty()
            || (String.isNotBlank(document.ContentVersionId__c)
                && versionById.containsKey((Id) document.ContentVersionId__c));

        return new Map<String, Object>{
            'id' => document.Id,
            'documentType' => docType,
            'documentNumber' => docNumber,
            'issuanceDate' => issuanceDate,
            'kycDob' => docDob,
            'hasFile' => hasFile
        };
    }

}