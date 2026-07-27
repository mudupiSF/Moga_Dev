/**
 * @description Builds PDF merge-field JSON for Cam_Form templates.
 *              Queries application data directly and maps fields to Handlebars keys.
 */
public without sharing class CamPageWrapper implements ICustomerFormWrapper {

    private static final String DOCUMENT_TYPE = 'CAM';
    private static final String DOCUMENT_NAME = 'CAM Document';

    private static final Set<String> PERSONAL_DETAIL_APPLICANT_TYPES = new Set<String>{
        'Borrower',
        'Co-borrower',
        'Guarantor',
        'Beneficiary'
    };
    private static final String VERIFICATION_NAME_SUFFIX = ' Verification';
    private static final String INCOME_RECORD_DECLARED = 'Declared Income';
    private static final String INCOME_RECORD_BANK_STATEMENT = 'Bank Statement';
    private static final String APPLICANT_TYPE_BENEFICIARY = 'Beneficiary';
    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';
    private static final Set<String> EXTERNAL_EXPOSURE_OBLIGATION_TYPES = new Set<String>{ 'External Exposure' };
    private static final String TYPE_FI = 'FI';
    private static final String FI_LABEL_CURRENT_RESIDENCE = 'Current Residence FI';
    private static final String FI_LABEL_PERMANENT = 'Permanent Residence FI';
    private static final String FI_LABEL_OFFICE = 'Office FI';

    private static final String DECLARATION_RBI_DIRECTORS_TEXT =
        'None of the Directors of the Bank or their relatives as defined in the RBI Master Circular - Loans and Advances Statutory and Other Restrictions is a director/partner, manager, managing agent, employee or guarantor of the applicant or a subsidiary of the applicant or of the holding company of the applicant and that none of them hold substantial interest in the applicant or his/ her / their subsidiary or his / her/ their holding company.';

    private static final String DECLARATION_RBI_OTHER_BANKS_TEXT =
        'To the best of the applicant\'s knowledge none of the directors of any other bank or the subsidiaries of the banks or trustees of mutual funds/venture capital funds set up by the banks or their relatives as defined in the RBI Master Circular - Loans and Advances - Statutory and Other Restrictions is a director/partner, manager, managing agent, employee or guarantor of the applicant or his /her/ their subsidiary or his / her/ their holding company and that none of them hold substantial interest in the applicant or his / her/ their subsidiary or his / her/ their holding company.';

    public String getDocumentType() {
        return DOCUMENT_TYPE;
    }

    public String getDocumentName() {
        return DOCUMENT_NAME;
    }

    public Map<String, Object> buildInputJson(Id applicationId, Id applicantId) {
        if (applicationId == null) {
            throw new AuraHandledException('Application ID is required.');
        }
        Application__c application = queryApplication(applicationId);
        if (application == null) {
            throw new AuraHandledException('Application record not found.');
        }
        return buildPayload(application);
    }

    private static Map<String, Object> buildPayload(Application__c application) {
        List<Applicant__c> personalApplicants = collectPersonalApplicantsSorted(application.Applicants__r);
        List<Applicant__c> nonBeneficiaryApplicants = filterApplicantsByType(
            application.Applicants__r,
            APPLICANT_TYPE_BENEFICIARY,
            false
        );
        Applicant__c borrower = resolveBorrower(application.Applicants__r);
        Application_Line_Item__c primaryLineItem = application.Application_Line_Items__r == null
            || application.Application_Line_Items__r.isEmpty()
            ? null
            : application.Application_Line_Items__r[0];
        Asset__c primaryAsset = resolveLineItemAsset(primaryLineItem);

        Set<Id> personalApplicantIds = new Set<Id>();
        for (Applicant__c applicant : personalApplicants) {
            personalApplicantIds.add(applicant.Id);
        }
        Map<Id, Document_CheckList__c> poiByApplicant = getPoiIdentityDocumentsByApplicant(personalApplicantIds);
        Document_CheckList__c borrowerPoi = borrower != null ? poiByApplicant.get(borrower.Id) : null;

        Map<Id, List<Applicant_Income__c>> incomesByApplicant = groupIncomesByApplicant(application.Applicants__r);
        Map<Id, Applicant_Employment__c> employmentByApplicant = groupPrimaryEmploymentByApplicant(
            application.Applicants__r
        );
        ExposureObligationBuckets obligationBuckets = groupExposureObligations(application.Applicants__r);
        Map<String, Map<Id, Verification__c>> fiMaps = groupFiVerificationsByApplicant(application.Applicants__r);
        List<Map<String, Object>> annexureRows = queryAnnexureRows(application.Id);

        Map<String, Object> pdf = new Map<String, Object>();
        putBasicInfo(pdf, application, borrower, application.Application_Line_Items__r, borrowerPoi);
        putPricing(pdf, primaryLineItem, primaryAsset);
        putOfferEngine(pdf, application, primaryLineItem, borrower);
        putLoanDetails(pdf, primaryLineItem, primaryAsset);
        putGatingScreening(pdf);
        putAnnexures(pdf, annexureRows);
        putApplicants(
            pdf,
            personalApplicants,
            nonBeneficiaryApplicants,
            application,
            poiByApplicant,
            primaryLineItem,
            incomesByApplicant,
            employmentByApplicant,
            obligationBuckets,
            fiMaps
        );
        return pdf;
    }

    private static void putBasicInfo(
        Map<String, Object> pdf,
        Application__c application,
        Applicant__c borrower,
        List<Application_Line_Item__c> lineItems,
        Document_CheckList__c borrowerPoi
    ) {
        String branchName = application.Branch__r != null ? application.Branch__r.Name : null;
        String branchState = application.Branch__r != null ? application.Branch__r.BillingState : null;
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

        pdf.put('BasicInfo_BranchName', normalize(joinDisplayParts(new List<String>{ branchName, branchState }, ' / ')));
        pdf.put('BasicInfo_ExecutiveName', normalize(application.Owner != null ? application.Owner.Name : null));
        pdf.put('BasicInfo_LeadNumber', normalize(application.Application_number__c));
        pdf.put('BasicInfo_ApplicantName', normalize(formatApplicantName(borrower, borrowerPoi)));
        pdf.put('BasicInfo_CustomerType', normalize(custType));
        pdf.put('BasicInfo_CustomerCode', normalize(borrower != null ? borrower.Customer_Code__c : null));
        pdf.put('BasicInfo_CurrentExposure', normalize(formatCurrency(calculateCurrentExposureAmount(lineItems))));
        pdf.put(
            'BasicInfo_ExistingBorrowerExposure',
            normalize(formatCurrency(calculateExistingBorrowerExposureAmount(borrower)))
        );
        pdf.put('BasicInfo_SchemeName', normalize(resolveSchemeName(primaryLineItem, application)));
        pdf.put('BasicInfo_SchemeCode', normalize(schemeCode));
    }

    private static void putPricing(
        Map<String, Object> pdf,
        Application_Line_Item__c lineItem,
        Asset__c asset
    ) {
        pdf.put('Pricing_ThresholdNetIRR', normalize(formatPercent(lineItem != null ? lineItem.CRM_IRR__c : null)));
        pdf.put('Pricing_ThresholdLTV', normalize(formatPercent(lineItem != null ? lineItem.Calculated_Net_LTV__c : null)));
        pdf.put('Pricing_VehicleVariant', normalize(asset != null ? asset.Variant__c : null));
    }

    private static void putOfferEngine(
        Map<String, Object> pdf,
        Application__c application,
        Application_Line_Item__c lineItem,
        Applicant__c borrower
    ) {
        String isStp = application != null && 'STP'.equalsIgnoreCase(application.Sanction_Status__c) ? 'Yes' : 'No';
        pdf.put('OE_LoanAmount', normalize(formatCurrency(resolveLineItemLoanAmount(lineItem))));
        pdf.put('OE_ThresholdNetIRR', normalize(formatPercent(lineItem != null ? lineItem.CRM_IRR__c : null)));
        pdf.put('OE_RequiredCRMIRR', normalize(formatPercent(lineItem != null ? lineItem.CRM_IRR__c : null)));
        pdf.put('OE_NetAnnualIncome', normalize(formatCurrency(borrower != null ? borrower.Declared_income__c : null)));
        pdf.put('OE_EMIAmount', normalize(formatCurrency(lineItem != null ? lineItem.EMI_Amount__c : null)));
        pdf.put('OE_Tenure', normalize(formatTenure(lineItem != null ? lineItem.Tenure__c : null)));
        pdf.put('OE_RateOfInterest', normalize(formatPercent(lineItem != null ? lineItem.ROI__c : null)));
        pdf.put('OE_NetLTV', normalize(formatPercent(lineItem != null ? lineItem.Calculated_Net_LTV__c : null)));
        pdf.put(
            'OE_BureauSurrogateOffer',
            normalize(lineItem != null ? formatDecimalDisplay(lineItem.Bureau_Surrogate_Offer__c) : null)
        );
        pdf.put('OE_IsSTP', normalize(isStp));
    }

    private static void putLoanDetails(
        Map<String, Object> pdf,
        Application_Line_Item__c lineItem,
        Asset__c asset
    ) {
        Decimal netLtv = lineItem != null ? lineItem.Calculated_Net_LTV__c : null;
        pdf.put('LD_LoanAmount', normalize(formatCurrency(resolveLineItemLoanAmount(lineItem))));
        pdf.put('LD_Tenure', normalize(formatTenure(lineItem != null ? lineItem.Tenure__c : null)));
        pdf.put('LD_RateOfInterest', normalize(formatPercent(lineItem != null ? lineItem.ROI__c : null)));
        pdf.put('LD_EMI', normalize(formatCurrency(lineItem != null ? lineItem.EMI_Amount__c : null)));
        pdf.put(
            'LD_LTV',
            normalize(formatPercent(netLtv != null ? netLtv : (lineItem != null ? lineItem.Calculated_Gross_LTV__c : null)))
        );
        pdf.put('LD_ViabilityRatio', normalize(formatPercent(asset != null ? asset.Viability_Ratio__c : null)));
        pdf.put('LD_FOIR', '');
        pdf.put('LD_VehicleType', normalize(asset != null ? asset.Vehicle_type__c : null));
    }

    private static void putGatingScreening(Map<String, Object> pdf) {
        pdf.put('GS_GatingOutput', '');
        pdf.put('GS_Screening', '');
        pdf.put('GS_RVGDFlag', '');
        pdf.put('GS_FKFlag', '');
        pdf.put('GS_FraudChecks', '');
    }

    private static void putAnnexures(Map<String, Object> pdf, List<Map<String, Object>> annexureRows) {
        List<Object> annexures = new List<Object>();
        for (Map<String, Object> row : annexureRows) {
            annexures.add(new Map<String, Object>{
                'ANN_DocumentType' => stringValue(row.get('documentType')),
                'ANN_DocumentName' => stringValue(row.get('documentName'))
            });
        }
        pdf.put('Annexures', annexures);
    }

    private static void putApplicants(
        Map<String, Object> pdf,
        List<Applicant__c> personalApplicants,
        List<Applicant__c> nonBeneficiaryApplicants,
        Application__c application,
        Map<Id, Document_CheckList__c> poiByApplicant,
        Application_Line_Item__c primaryLineItem,
        Map<Id, List<Applicant_Income__c>> incomesByApplicant,
        Map<Id, Applicant_Employment__c> employmentByApplicant,
        ExposureObligationBuckets obligationBuckets,
        Map<String, Map<Id, Verification__c>> fiMaps
    ) {
        Set<Id> nonBeneficiaryIds = new Set<Id>();
        for (Applicant__c applicant : nonBeneficiaryApplicants) {
            nonBeneficiaryIds.add(applicant.Id);
        }

        String bureauSurrogate = primaryLineItem != null
            ? formatDecimalDisplay(primaryLineItem.Bureau_Surrogate_Offer__c)
            : null;
        String schemeMinCibil = primaryLineItem != null && primaryLineItem.Schemes__r != null
            ? formatDecimalDisplay(primaryLineItem.Schemes__r.MinimumCIBILScore__c)
            : null;
        String schemeMaxCibil = primaryLineItem != null && primaryLineItem.Schemes__r != null
            ? formatDecimalDisplay(primaryLineItem.Schemes__r.Maximum_CIBIL_Score__c)
            : null;

        Map<Id, Verification__c> residenceByApplicant = fiMaps.get('residence');
        Map<Id, Verification__c> permanentByApplicant = fiMaps.get('permanent');
        Map<Id, Verification__c> officeByApplicant = fiMaps.get('office');

        List<Object> applicants = new List<Object>();
        for (Applicant__c applicant : personalApplicants) {
            Document_CheckList__c poiDocument = poiByApplicant.get(applicant.Id);
            Map<String, Object> appl = new Map<String, Object>();
            appl.put('Applicant_Role', stringValue(applicant.Applicant_Type__c));
            putPersonalDetails(appl, applicant, application, poiDocument);
            if (nonBeneficiaryIds.contains(applicant.Id)) {
                putBankAccountDetails(appl, applicant);
                putIncomeDetails(
                    appl,
                    applicant,
                    incomesByApplicant.get(applicant.Id),
                    employmentByApplicant.get(applicant.Id)
                );
                putFinancialDetails(
                    appl,
                    applicant,
                    primaryLineItem,
                    incomesByApplicant.get(applicant.Id)
                );
                putExposureDetails(appl, applicant, obligationBuckets);
                putCreditBureauDetails(
                    appl,
                    applicant,
                    APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicant.Applicant_Type__c),
                    bureauSurrogate,
                    schemeMinCibil,
                    schemeMaxCibil
                );
                putFiWaiverDetails(
                    appl,
                    applicant,
                    residenceByApplicant,
                    permanentByApplicant,
                    officeByApplicant
                );
                appl.put('RP_RiskProfile', normalize(applicant.Scorecard_Decision__c));
                putDeclarationDetails(appl, applicant);
            }
            appl.put('CA_JustificationRemark', normalize(applicant.Justification_Remark__c));
            applicants.add(appl);
        }
        pdf.put('Applicants', applicants);
    }

    private static void putPersonalDetails(
        Map<String, Object> appl,
        Applicant__c applicant,
        Application__c application,
        Document_CheckList__c poiDocument
    ) {
        Boolean isBorrower = APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicant.Applicant_Type__c);
        Boolean isBeneficiary = APPLICANT_TYPE_BENEFICIARY.equalsIgnoreCase(applicant.Applicant_Type__c);
        Boolean isNonIndividual = isNonIndividualApplicant(applicant);

        if (isNonIndividual && !isBeneficiary) {
            appl.put('PD_Name', normalize(applicant.Company_Name__c));
        } else {
            appl.put('PD_Name', normalize(formatApplicantName(applicant, poiDocument)));
        }
        if (!isBorrower && !isBeneficiary) {
            appl.put('PD_RelationshipWithBorrower', normalize(applicant.Relationship_with_borrower__c));
        } else {
            appl.put('PD_RelationshipWithBorrower', '');
        }
        appl.put('PD_EntityType', normalize(resolveEntityTypeDisplay(applicant)));

        if (isNonIndividual && !isBeneficiary) {
            appl.put('PD_Age', '');
            appl.put('PD_DateOfBirth', normalize(formatDate(applicant.Date_of_Birth__c)));
            appl.put('PD_Gender', '');
            appl.put('PD_MaritalStatus', '');
        } else {
            Date poiDateOfBirth = poiDocument != null && poiDocument.KYC_Date_of_Birth__c != null
                ? poiDocument.KYC_Date_of_Birth__c
                : applicant.Date_of_Birth__c;
            String poiGender = poiDocument != null && String.isNotBlank(poiDocument.Gender__c)
                ? poiDocument.Gender__c
                : applicant.Gender__c;
            appl.put('PD_Age', normalize(formatAge(poiDateOfBirth)));
            appl.put('PD_DateOfBirth', normalize(formatDate(poiDateOfBirth)));
            appl.put('PD_Gender', normalize(poiGender));
            appl.put('PD_MaritalStatus', normalize(applicant.Marital_status__c));
        }

        appl.put('PD_Profile', normalize(applicant.Profile__c));
        appl.put('PD_PAN', normalize(applicant.PAN_Number__c));
        appl.put('PD_Mobile', normalize(applicant.Phone__c));
        appl.put('PD_PersonalEmail', normalize(applicant.Email__c));
    }

    private static void putBankAccountDetails(Map<String, Object> appl, Applicant__c applicant) {
        appl.put('BAD_HasBankAccount', normalize(applicant.Has_Bank_Account__c));
        appl.put('BAD_WishToOpenSavingsAccount', normalize(applicant.Interested_In_Opening_Savings_Account__c));
    }

    private static void putIncomeDetails(
        Map<String, Object> appl,
        Applicant__c applicant,
        List<Applicant_Income__c> incomes,
        Applicant_Employment__c employment
    ) {
        Applicant_Income__c declaredIncome = findIncomeByName(incomes, INCOME_RECORD_DECLARED);
        Applicant_Income__c bankStatementIncome = findIncomeByName(incomes, INCOME_RECORD_BANK_STATEMENT);

        String employerName = employment != null ? employment.Employer_Business_Name__c : null;
        if (String.isBlank(employerName) && declaredIncome != null) {
            employerName = declaredIncome.Employer_Business_Name__c;
        }

        String salariedSelfEmployed = String.isNotBlank(applicant.Income_Category__c)
            ? applicant.Income_Category__c
            : (employment != null ? employment.Salaried_Self_employed__c : null);

        appl.put('INC_LegalEntityIdentifier', normalize(resolveLegalEntityIdentifier(applicant)));
        appl.put('INC_IncomeFromSource', normalize(resolveIncomeFromSources(incomes)));
        appl.put('INC_RecipientBankName', normalize(resolveRecipientBankName(incomes)));
        appl.put('INC_SalariedSelfEmployed', normalize(salariedSelfEmployed));
        appl.put('INC_EmployerBusinessName', normalize(employerName));
        appl.put(
            'INC_CurrentYearsEmployment',
            normalize(
                employment != null && employment.Current_years_in_Employment_Business__c != null
                    ? String.valueOf(employment.Current_years_in_Employment_Business__c)
                    : null
            )
        );
        appl.put(
            'INC_TotalYearsEmployment',
            normalize(
                employment != null && employment.Years_in_employment_business__c != null
                    ? String.valueOf(employment.Years_in_employment_business__c)
                    : null
            )
        );
        appl.put('INC_Profile', normalize(applicant.Profile__c));
        appl.put('INC_BSROccupation', '');
        appl.put(
            'INC_IncomeVerificationMethod',
            normalize(resolveIncomeVerificationMethod(declaredIncome, bankStatementIncome, incomes))
        );
        appl.put(
            'INC_ABBConsolidated',
            normalize(
                bankStatementIncome != null
                    ? formatCurrency(bankStatementIncome.Consolidated_Yearly_Income__c)
                    : null
            )
        );
        appl.put(
            'INC_DeclaredIncome',
            normalize(
                declaredIncome != null
                    ? formatCurrency(declaredIncome.Consolidated_Yearly_Income__c)
                    : formatCurrency(applicant.Declared_income__c)
            )
        );
    }

    private static void putFinancialDetails(
        Map<String, Object> appl,
        Applicant__c applicant,
        Application_Line_Item__c primaryLineItem,
        List<Applicant_Income__c> incomes
    ) {
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

        appl.put('FIN_FOIR', normalize(foirDisplay));
        appl.put('FIN_EMIABBRatio', '');
    }

    private static void putExposureDetails(
        Map<String, Object> appl,
        Applicant__c applicant,
        ExposureObligationBuckets obligationBuckets
    ) {
        List<Object> exposureRows = new List<Object>();
        List<Applicant_Obligations__c> bankExposureObligations =
            obligationBuckets.bankExposureByApplicant.get(applicant.Id);
        if (bankExposureObligations != null) {
            for (Applicant_Obligations__c obligation : bankExposureObligations) {
                exposureRows.add(mapExposureRow(obligation));
            }
        }

        List<Object> externalExposureRows = new List<Object>();
        List<Applicant_Obligations__c> externalExposureObligations =
            obligationBuckets.externalExposureByApplicant.get(applicant.Id);
        if (externalExposureObligations != null) {
            for (Applicant_Obligations__c obligation : externalExposureObligations) {
                externalExposureRows.add(mapExternalExposureRow(obligation));
            }
        }

        appl.put('Exposure_Records', exposureRows);
        appl.put('ExternalExposure_Records', externalExposureRows);
    }

    private static void putCreditBureauDetails(
        Map<String, Object> appl,
        Applicant__c applicant,
        Boolean isBorrower,
        String bureauSurrogate,
        String schemeMinCibil,
        String schemeMaxCibil
    ) {
        Boolean nonIndividual = isNonIndividualApplicant(applicant);
        appl.put('CIBIL_Score', normalize(applicant.Scorecard_Decision__c));
        appl.put('CIBIL_BureauSurrogateOffer', normalize(isBorrower ? bureauSurrogate : null));
        if (!nonIndividual) {
            appl.put('CIBIL_SchemeMinimum', normalize(schemeMinCibil));
            appl.put('CIBIL_SchemeMaximum', normalize(schemeMaxCibil));
        } else {
            appl.put('CIBIL_SchemeMinimum', '');
            appl.put('CIBIL_SchemeMaximum', '');
        }
        appl.put('CIBIL_RecentDate', '');
        appl.put('CIBIL_OldestDate', '');
        appl.put('CIBIL_WrittenOffAmount', '');
        appl.put('CIBIL_NoOfEnquiries', '');
    }

    private static void putFiWaiverDetails(
        Map<String, Object> appl,
        Applicant__c applicant,
        Map<Id, Verification__c> residenceByApplicant,
        Map<Id, Verification__c> permanentByApplicant,
        Map<Id, Verification__c> officeByApplicant
    ) {
        Id applicantId = applicant.Id;
        Verification__c residenceVerification = residenceByApplicant != null
            ? residenceByApplicant.get(applicantId)
            : null;
        Verification__c permanentVerification = permanentByApplicant != null
            ? permanentByApplicant.get(applicantId)
            : null;
        Verification__c officeVerification = officeByApplicant != null
            ? officeByApplicant.get(applicantId)
            : null;

        appl.put('FI_CustomerType', normalize(resolveApplicantTitle(applicant)));
        appl.put(
            'FI_CurrentFI',
            normalize(residenceVerification == null ? 'Waived' : 'Not Waived')
        );
        appl.put(
            'FI_PermanentFI',
            normalize(permanentVerification == null ? 'Waived' : 'Not Waived')
        );
        appl.put(
            'FI_OfficeFI',
            normalize(officeVerification == null ? 'Waived' : 'Not Waived')
        );
    }

    private static void putDeclarationDetails(Map<String, Object> appl, Applicant__c applicant) {
        appl.put('DECL_DeclarationText1', DECLARATION_RBI_DIRECTORS_TEXT);
        appl.put('DECL_DeclarationText2', DECLARATION_RBI_OTHER_BANKS_TEXT);
    }

    private static Application__c queryApplication(Id applicationId) {
        String residencePattern = '%' + FI_LABEL_CURRENT_RESIDENCE + '%';
        String permanentPattern = '%' + FI_LABEL_PERMANENT + '%';
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
                           Entity_Type__c,
                           Company_Name__c,
                           Profile__c,
                           Income_Category__c,
                           Has_Bank_Account__c,
                           Interested_In_Opening_Savings_Account__c,
                           Declared_income__c,
                           Scorecard_Decision__c,
                           Justification_Remark__c,
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
                                   Name
                            FROM Verifications__r
                            WHERE Investigations__r.Type_of_Investigation__c = :TYPE_FI
                              AND (
                                  Name LIKE :residencePattern
                                  OR Name LIKE :permanentPattern
                                  OR Name LIKE :officePattern
                              )
                            ORDER BY CreatedDate DESC)
                    FROM Applicants__r
                    WHERE In_Active_Applicant__c = false
                      AND Applicant_Type__c IN :PERSONAL_DETAIL_APPLICANT_TYPES
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
                                   Required_Total_Loan_Amount__c
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

    private static List<Map<String, Object>> queryAnnexureRows(Id applicationId) {
        List<Map<String, Object>> annexureRows = new List<Map<String, Object>>();
        if (applicationId == null) {
            return annexureRows;
        }

        for (Document_CheckList__c document : [
            SELECT Id,
                   Name,
                   Document_Type__c,
                   Applicant_Type__c
            FROM Document_CheckList__c
            WHERE Is_Active__c = true
              AND Application__c = :applicationId
              AND Document_Type__c != null
            ORDER BY Document_Type__c ASC, Name ASC
        ]) {
            annexureRows.add(new Map<String, Object>{
                'documentType' => joinDisplayParts(
                    new List<String>{ document.Document_Type__c, document.Applicant_Type__c },
                    ' - '
                ),
                'documentName' => document.Name
            });
        }
        return annexureRows;
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
                   Last_Name__c
            FROM Document_CheckList__c
            WHERE Applicant__c IN :applicantIds
              AND Applicant_Address__r.Identity_Proof__c = true
              AND Is_Active__c = true
            ORDER BY CreatedDate DESC
        ]) {
            if (!poiByApplicant.containsKey(document.Applicant__c)) {
                poiByApplicant.put(document.Applicant__c, document);
            }
        }
        return poiByApplicant;
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
        Map<Id, Verification__c> officeByApplicant = new Map<Id, Verification__c>();
        Map<String, Map<Id, Verification__c>> result = new Map<String, Map<Id, Verification__c>>{
            'residence' => residenceByApplicant,
            'permanent' => permanentByApplicant,
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
                } else if (FI_LABEL_OFFICE.equalsIgnoreCase(label)
                    && !officeByApplicant.containsKey(applicant.Id)) {
                    officeByApplicant.put(applicant.Id, verification);
                }
            }
        }
        return result;
    }

    private class ExposureObligationBuckets {
        public Map<Id, List<Applicant_Obligations__c>> bankExposureByApplicant =
            new Map<Id, List<Applicant_Obligations__c>>();
        public Map<Id, List<Applicant_Obligations__c>> externalExposureByApplicant =
            new Map<Id, List<Applicant_Obligations__c>>();
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
            if (String.isBlank(applicantType)) {
                return 99;
            }
            if ('Borrower'.equalsIgnoreCase(applicantType)) {
                return 0;
            }
            if ('Co-borrower'.equalsIgnoreCase(applicantType)) {
                return 1;
            }
            if ('Guarantor'.equalsIgnoreCase(applicantType) || applicantType.startsWith('G')) {
                return 2;
            }
            if ('Beneficiary'.equalsIgnoreCase(applicantType)) {
                return 3;
            }
            return 4;
        }
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
                    if (allowedType.equalsIgnoreCase(applicantType)) {
                        isPersonalApplicant = true;
                        break;
                    }
                }
                if (!isPersonalApplicant) {
                    isPersonalApplicant = applicantType.startsWith('G');
                }
            }
            if (isPersonalApplicant) {
                personalApplicants.add(applicant);
            }
        }
        personalApplicants.sort(new ApplicantDisplayOrderComparator());
        return personalApplicants;
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
            Boolean matchesType = applicantType.equalsIgnoreCase(applicant.Applicant_Type__c);
            if (includeType == matchesType) {
                filtered.add(applicant);
            }
        }
        filtered.sort(new ApplicantDisplayOrderComparator());
        return filtered;
    }

    private static Applicant__c resolveBorrower(List<Applicant__c> applicants) {
        if (applicants == null) {
            return null;
        }
        for (Applicant__c applicant : applicants) {
            if (APPLICANT_TYPE_BORROWER.equalsIgnoreCase(applicant.Applicant_Type__c)) {
                return applicant;
            }
        }
        return applicants.isEmpty() ? null : applicants[0];
    }

    private static Asset__c resolveLineItemAsset(Application_Line_Item__c lineItem) {
        if (lineItem == null || lineItem.Assets__r == null || lineItem.Assets__r.isEmpty()) {
            return null;
        }
        return lineItem.Assets__r[0];
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

    private static String resolveSchemeName(Application_Line_Item__c lineItem, Application__c application) {
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

    private static Applicant_Income__c findIncomeByName(List<Applicant_Income__c> incomes, String recordName) {
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

    private static String resolveApplicantTitle(Applicant__c applicant) {
        return applicant == null
            ? null
            : (String.isNotBlank(applicant.Applicant_Tab_Label__c)
                ? applicant.Applicant_Tab_Label__c
                : applicant.Applicant_Type__c);
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

    private static Map<String, Object> mapExposureRow(Applicant_Obligations__c obligation) {
        return new Map<String, Object>{
            'ED_ExposureType' => stringValue(obligation.Exposure_Type__c),
            'ED_DealStage' => stringValue(obligation.Deal_Stage__c),
            'ED_DealNo' => stringValue(obligation.Deal_No__c),
            'ED_DealDate' => obligation.Deal_Date__c == null ? '' : obligation.Deal_Date__c.format('yyyy-MM-dd'),
            'ED_Product' => stringValue(obligation.Type_of_Facility__c),
            'ED_Status' => stringValue(obligation.Status_Flag__c),
            'ED_FinanceAmount' => normalize(formatCurrency(obligation.Finance_Amt__c)),
            'ED_SOH' => normalize(formatCurrency(obligation.SOH__c)),
            'ED_OverDue' => normalize(formatCurrency(obligation.Over_Due__c))
        };
    }

    private static Map<String, Object> mapExternalExposureRow(Applicant_Obligations__c obligation) {
        return new Map<String, Object>{
            'ED_ExposureType' => '',
            'ED_DealStage' => '',
            'ED_DealNo' => '',
            'ED_DealDate' => '',
            'ED_Product' => '',
            'ED_Status' => '',
            'ED_FinanceAmount' => '',
            'ED_SOH' => '',
            'ED_OverDue' => ''
        };
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

    private static String formatApplicantName(Applicant__c applicant, Document_CheckList__c poiDocument) {
        if (applicant == null) {
            return null;
        }
        if (isNonIndividualApplicant(applicant) && String.isNotBlank(applicant.Company_Name__c)) {
            return applicant.Company_Name__c.trim();
        }
        String poiName = joinDisplayParts(
            new List<String>{ poiDocument != null ? poiDocument.First_Name__c : null,
                poiDocument != null ? poiDocument.Last_Name__c : null },
            ' '
        );
        if (String.isNotBlank(poiName)) {
            return poiName;
        }
        return joinDisplayParts(
            new List<String>{ applicant.Customer_First_Name__c, applicant.Customer_Last_Name__c },
            ' '
        );
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

    private static String formatDecimalDisplay(Decimal value) {
        return value == null ? null : value.stripTrailingZeros().toPlainString();
    }

    private static String normalize(String value) {
        if (value == '\u2014' || value == 'N/A') {
            return '';
        }
        return String.isBlank(value) ? '' : value;
    }

    private static String stringValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }
}