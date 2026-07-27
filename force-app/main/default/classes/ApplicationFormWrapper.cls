/**
 * @description Builds PDF merge-field JSON for Application Form templates.
 *              Payload shape matches applicationFormTemplateDummyData.json.
 */
public without sharing class ApplicationFormWrapper implements ICustomerFormWrapper {

    private static final String DOCUMENT_TYPE = 'Application Form';
    private static final String DOCUMENT_NAME = 'Application Form';
    private static final String APPLICANT_TYPE_BORROWER = 'Borrower';
    private static final String APPLICANT_TYPE_CO_BORROWER = 'Co-Borrower';
    private static final String ADDRESS_CURRENT = 'Current Residential Address';
    private static final String ADDRESS_PERMANENT = 'Permanent Residential Address';
    private static final String ADDRESS_OFFICE = 'Office Address';
    private static final Integer MAX_CO_APPS = 3;

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

    private static Application__c queryApplication(Id applicationId) {
        List<Application__c> applications = [
            SELECT Id,
                   Application_number__c,
                   Product__c,
                   Sub_Product__c,
                   (SELECT Id,
                           Applicant_Type__c,
                           Customer_First_Name__c,
                           Customer_Last_Name__c,
                           Name,
                           Customer_Code__c,
                           Bank_Account_No__c,
                           Has_Bank_Account__c,
                           ETB_CASA_Details__c,
                           Relationship_with_borrower__c,
                           Date_of_Birth__c,
                           Gender__c,
                           Phone__c,
                           Contact_number__c,
                           Email__c,
                           Type__c,
                           Entity_Type__c,
                           Residence_country__c,
                           Religion__c,
                           Caste__c,
                           Father_s_name__c,
                           Mother_s_name__c,
                           Spouse_Name__c,
                           PAN_Number__c,
                           Is_PAN_Available__c,
                           CKYC_ID__c,
                           Customer_Qualification__c,
                           Marital_status__c,
                           Are_you_a_Politically_Exposed_Person__c,
                           Profile__c,
                           Company_Name__c,
                           Major_Industry__c,
                           Minor_Industry__c,
                           Industry_Name__c,
                           Income_Category__c,
                           (SELECT Id,
                                   Address_Type__c,
                                   Address_Line_1__c,
                                   Address_Line_2__c,
                                   Address_Line_3__c,
                                   Address_Line_4__c,
                                   City__c,
                                   State__c,
                                   PinCode__c,
                                   District__c,
                                   Country__c,
                                   Email__c
                            FROM Applicant_Address__r
                            ORDER BY CreatedDate ASC),
                           (SELECT Id,
                                   Salaried_Self_employed__c,
                                   Employer_Type__c,
                                   Employer_Name__c,
                                   Employer_Business_Name__c,
                                   Employee_Name__c,
                                   Current_years_in_Employment_Business__c,
                                   Years_in_employment_business__c
                            FROM Applicant_Employment__r
                            ORDER BY CreatedDate DESC
                            LIMIT 1),
                           (SELECT Id,
                                   Income__c,
                                   Income_Source__c,
                                   Income_Detail_Bank_Master__r.Name
                            FROM Applicant_Income__r
                            ORDER BY CreatedDate ASC),
                           (SELECT Id,
                                   Document_Type__c,
                                   First_Name__c,
                                   Last_Name__c,
                                   PAN_No__c,
                                   Applicant_KYC__r.KYC_Type__c,
                                   Applicant_KYC__r.KYC_No__c,
                                   Applicant_KYC__r.Masked_KYC_No__c,
                                   Applicant_KYC__r.KYC_Expiry_Date__c
                            FROM Document_CheckLists__r
                            WHERE Is_Active__c = true
                            ORDER BY CreatedDate DESC),
                           (SELECT Id,
                                   Type_of_Facility__c,
                                   Account_Type__c,
                                   Account_Type_Desc__c,
                                   Sanctioned_Amt__c,
                                   Finance_Amt__c,
                                   High_Credit__c,
                                   Current_Balance__c,
                                   SOH__c,
                                   Over_Due__c,
                                   Obligation_Type__c
                            FROM Applicant_Obligations__r
                            ORDER BY CreatedDate ASC),
                           (SELECT Id,
                                   Product_Type__c,
                                   Insurance_Plan__c
                            FROM Insurances__r
                            WHERE Is_Active__c = true
                            ORDER BY CreatedDate DESC
                            LIMIT 1)
                    FROM Applicants__r
                    WHERE In_Active_Applicant__c = false
                    ORDER BY Applicant_Type__c ASC, CreatedDate ASC),
                   (SELECT Id,
                           Loan_Amount__c,
                           Tenure__c,
                           EMI_Amount__c,
                           ROI__c,
                           CRM_IRR__c,
                           Product__c,
                           Sub_Product__c,
                           Installment_Type__c,
                           Documentation_charges__c,
                           Applicable_Stamping_Charges__c,
                           Schemes__r.Name,
                           (SELECT Id,
                                   Make__c,
                                   Model__c,
                                   Variant__c,
                                   Vehicle_type__c,
                                   Purpose_of_purchase__c,
                                   On_Road_price__c,
                                   Ex_showroom_price__c,
                                   District__c,
                                   Number_of_ownerships__c
                            FROM Assets__r
                            ORDER BY CreatedDate ASC
                            LIMIT 1)
                    FROM Application_Line_Items__r
                    ORDER BY CreatedDate ASC
                    LIMIT 1)
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0];
    }

    private static Map<String, Object> buildPayload(Application__c application) {
        ApplicantContext borrower = null;
        List<ApplicantContext> coApplicants = new List<ApplicantContext>();

        if (application.Applicants__r != null) {
            for (Applicant__c applicant : application.Applicants__r) {
                if (applicant == null) {
                    continue;
                }
                ApplicantContext ctx = new ApplicantContext(applicant);
                if (equalsIgnoreCase(applicant.Applicant_Type__c, APPLICANT_TYPE_BORROWER)) {
                    borrower = ctx;
                } else {
                    coApplicants.add(ctx);
                }
            }
            if (borrower == null && !application.Applicants__r.isEmpty()) {
                borrower = new ApplicantContext(application.Applicants__r[0]);
            }
        }

        Application_Line_Item__c lineItem = (application.Application_Line_Items__r != null
            && !application.Application_Line_Items__r.isEmpty())
            ? application.Application_Line_Items__r[0]
            : null;
        Asset__c asset = (lineItem != null
            && lineItem.Assets__r != null
            && !lineItem.Assets__r.isEmpty())
            ? lineItem.Assets__r[0]
            : null;

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('applicationDate', formatDisplayDate(Date.today()));
        payload.put('appNumber', val(application.Application_number__c));

        if (borrower != null) {
            payload.putAll(buildBorrowerFields(borrower));
            payload.putAll(buildOccupationFields(borrower));
        } else {
            payload.putAll(emptyBorrowerFields());
            payload.putAll(emptyOccupationFields());
        }

        payload.put('coAppGroups', buildCoAppGroups(coApplicants));
        if (coApplicants != null && !coApplicants.isEmpty()) {
            payload.put('coApplicantPresent', true);
        } else {
            payload.put('coApplicantPresent', false);
        }

        List<Object> incomeSourceList = buildIncomeSourceList(application.Applicants__r);
        payload.put('incomeSourceList', incomeSourceList);
        payload.put('totalIncome', calculateTotalIncome(incomeSourceList));
        payload.put('obligationsList', buildObligationsList(application.Applicants__r));
        payload.put('bankDetailsList', buildBankDetailsList(application.Applicants__r));
        payload.putAll(buildLoanFields(application, lineItem, asset));
        payload.putAll(buildPropertyFields(asset));
        payload.put('applicantInsuranceList', buildApplicantInsuranceList(application.Applicants__r));

        return payload;
    }

    private static Map<String, Object> buildBorrowerFields(ApplicantContext borrower) {
        if (borrower == null) {
            return emptyBorrowerFields();
        }
        Applicant__c a = borrower.applicant;
        Map<String, Object> fields = new Map<String, Object>();
        fields.put('appName', val(formatApplicantName(a)));
        fields.put('customerId', val(a.Customer_Code__c));
        fields.put('appDob', val(formatIsoDate(a.Date_of_Birth__c)));
        fields.put('appEmail', val(a.Email__c));
        fields.put('appGender', val(a.Gender__c));
        fields.put('appPhone', val(firstNonBlank(a.Phone__c, a.Contact_number__c)));
        fields.put('customerType', val(firstNonBlank(a.Type__c, a.Entity_Type__c)));
        fields.put('nationality', val(a.Residence_country__c));
        fields.put('religion', val(a.Religion__c));
        fields.put('category', val(a.Caste__c));
        fields.put('fatherName', val(a.Father_s_name__c));
        fields.put('motherName', val(a.Mother_s_name__c));
        fields.put('spouseName', val(a.Spouse_Name__c));
        fields.put('maritalStatus', val(a.Marital_status__c));
        fields.put('currentAddress', val(borrower.formatAddress(ADDRESS_CURRENT)));
        fields.put('permanentAddress', val(borrower.formatAddress(ADDRESS_PERMANENT)));
        fields.put('appPan', val(a.PAN_Number__c));
        fields.put('form60', borrower.form60Value());
        fields.put('passportNumber', val(borrower.kycNumber('Passport')));
        fields.put('expiryDate', val(borrower.kycExpiry('Passport')));
        fields.put('drivingLicence', val(borrower.kycNumber('Driving License')));
        fields.put('dlExpiry', val(borrower.kycExpiry('Driving License')));
        fields.put('voterIdNum', val(borrower.kycNumber('Voter Id')));
        fields.put('aadhaarNum', val(borrower.kycNumber('Aadhar')));
        fields.put('ckycNum', val(formatCkyc(a.CKYC_ID__c)));
        fields.put('isDisabled', '');
        fields.put('qualification', val(a.Customer_Qualification__c));
        fields.put('isPoliticallyExposed', val(formatYesNoPicklist(a.Are_you_a_Politically_Exposed_Person__c)));
        return fields;
    }

    private static Map<String, Object> emptyBorrowerFields() {
        return new Map<String, Object>{
            'appName' => '', 'customerId' => '', 'appDob' => '', 'appEmail' => '',
            'appGender' => '', 'appPhone' => '', 'customerType' => '', 'nationality' => '',
            'religion' => '', 'category' => '', 'fatherName' => '', 'motherName' => '',
            'spouseName' => '', 'maritalStatus' => '', 'currentAddress' => '',
            'permanentAddress' => '', 'appPan' => '', 'form60' => '', 'passportNumber' => '',
            'expiryDate' => '', 'drivingLicence' => '', 'dlExpiry' => '', 'voterIdNum' => '',
            'aadhaarNum' => '', 'ckycNum' => '', 'isDisabled' => '', 'qualification' => '',
            'isPoliticallyExposed' => ''
        };
    }

    private static Map<String, Object> buildOccupationFields(ApplicantContext borrower) {
        if (borrower == null) {
            return emptyOccupationFields();
        }
        Applicant__c a = borrower.applicant;
        return new Map<String, Object>{
            'occupation' => val(firstNonBlank(a.Profile__c, a.Income_Category__c)),
            'orgName' => val(borrower.organizationName()),
            'officeAddress' => val(borrower.formatAddress(ADDRESS_OFFICE)),
            'natureOfEmp' => val(borrower.employmentType()),
            'industryType' => val(firstNonBlank(a.Industry_Name__c, a.Major_Industry__c, a.Minor_Industry__c)),
            'officialEmail' => val(borrower.officeEmail()),
            'workExp' => val(borrower.formatWorkExp(borrower.currentWorkYears())),
            'salaryBankNum' => val(borrower.salaryBankName()),
            'empNumber' => val(borrower.employeeNumber())
        };
    }

    private static Map<String, Object> emptyOccupationFields() {
        return new Map<String, Object>{
            'occupation' => '', 'orgName' => '', 'officeAddress' => '', 'natureOfEmp' => '',
            'industryType' => '', 'officialEmail' => '', 'workExp' => '', 'salaryBankNum' => '',
            'empNumber' => ''
        };
    }

    private static List<Object> buildCoAppGroups(List<ApplicantContext> coApplicants) {
        if (coApplicants == null || coApplicants.isEmpty()) {
            return new List<Object>();
        }

        List<ApplicantContext> limited = sliceCoApplicants(coApplicants);
        Integer count = limited.size();

        Map<String, Object> grouped = new Map<String, Object>();
        grouped.put('coAppList', buildCoAppList(limited));
        grouped.put('showAll', count >= 3);
        grouped.put('hideCol3', count == 1);
        grouped.put('hideCol4', count == 2);
        return new List<Object>{ grouped };
    }

    private static List<Object> buildCoAppList(List<ApplicantContext> coApplicants) {
        List<Object> rows = new List<Object>();
        rows.add(coAppRow('Name', valuesForCoApps(coApplicants, 'name')));
        rows.add(coAppRow('Customer ID', valuesForCoApps(coApplicants, 'customerId')));
        rows.add(coAppRow('Relationship with applicant', valuesForCoApps(coApplicants, 'relationship')));
        rows.add(coAppRow('Date of birth', valuesForCoApps(coApplicants, 'dob')));
        rows.add(coAppRow('Gender', valuesForCoApps(coApplicants, 'gender')));
        rows.add(coAppRow('Email ID', valuesForCoApps(coApplicants, 'email')));
        rows.add(coAppRow('Mobile number', valuesForCoApps(coApplicants, 'mobile')));
        rows.add(coAppRow('PAN', valuesForCoApps(coApplicants, 'pan')));
        rows.add(coAppRow('Form 60', valuesForCoApps(coApplicants, 'form60')));
        rows.add(coAppRow('Occupation', valuesForCoApps(coApplicants, 'occupation')));
        rows.add(coAppRow('Passport number', valuesForCoApps(coApplicants, 'passport')));
        rows.add(coAppRow('Driving license', valuesForCoApps(coApplicants, 'drivingLicence')));
        rows.add(coAppRow('Voter ID card', valuesForCoApps(coApplicants, 'voterId')));
        rows.add(coAppRow('CKYC number', valuesForCoApps(coApplicants, 'ckyc')));
        rows.add(coAppRow('Person with disability', valuesForCoApps(coApplicants, 'disability')));
        rows.add(coAppRow('Education qualification', valuesForCoApps(coApplicants, 'qualification')));
        rows.add(coAppRow('Marital status', valuesForCoApps(coApplicants, 'maritalStatus')));
        rows.add(coAppRow('Name of the organization', valuesForCoApps(coApplicants, 'organization')));
        rows.add(coAppRow('Total work experience', valuesForCoApps(coApplicants, 'totalWorkExp')));
        return rows;
    }

    private static List<Object> buildIncomeSourceList(List<Applicant__c> applicants) {
        List<Object> rows = new List<Object>();
        if (applicants == null) {
            return rows;
        }
        for (Applicant__c applicant : applicants) {
            if (applicant == null) {
                continue;
            }
            if (applicant.Applicant_Income__r == null) {
                continue;
            }
            String appName = formatApplicantName(applicant);
            String appType = val(applicant.Applicant_Type__c);
            for (Applicant_Income__c income : applicant.Applicant_Income__r) {
                if (income == null) {
                    continue;
                }
                if (income.Income__c == null && String.isBlank(income.Income_Source__c)) {
                    continue;
                }
                rows.add(new Map<String, Object>{
                    'appName' => appName,
                    'appType' => appType,
                    'incomeSource' => val(income.Income_Source__c),
                    'amount' => income.Income__c
                });
            }
        }
        return rows;
    }

    private static Decimal calculateTotalIncome(List<Object> incomeSourceList) {
        Decimal total = 0;
        if (incomeSourceList == null) {
            return total;
        }
        for (Object rowObj : incomeSourceList) {
            if (rowObj == null) {
                continue;
            }
            Map<String, Object> row = (Map<String, Object>) rowObj;
            Object amountValue = row.get('amount');
            if (amountValue != null) {
                total += (Decimal) amountValue;
            }
        }
        return total;
    }

    private static List<Object> buildObligationsList(List<Applicant__c> applicants) {
        List<Object> rows = new List<Object>();
        if (applicants == null) {
            return rows;
        }
        for (Applicant__c applicant : applicants) {
            if (applicant == null) {
                continue;
            }
            if (applicant.Applicant_Obligations__r == null) {
                continue;
            }
            String appName = formatApplicantName(applicant);
            String appType = val(applicant.Applicant_Type__c);
            for (Applicant_Obligations__c obligation : applicant.Applicant_Obligations__r) {
                if (obligation == null) {
                    continue;
                }
                rows.add(new Map<String, Object>{
                    'appName' => appName,
                    'appType' => appType,
                    'loanType' => val(firstNonBlank(
                        obligation.Account_Type_Desc__c,
                        obligation.Type_of_Facility__c,
                        obligation.Account_Type__c
                    )),
                    'sanctionAmt' => firstNonNullDecimal(
                        obligation.Sanctioned_Amt__c,
                        obligation.Finance_Amt__c,
                        obligation.High_Credit__c
                    ),
                    'outStandingAmt' => firstNonNullDecimal(
                        obligation.Current_Balance__c,
                        obligation.SOH__c,
                        0
                    ),
                    'monthlyInterest' => obligation.Over_Due__c,
                    'isObligation' => equalsIgnoreCase(obligation.Obligation_Type__c, 'Obligation') ? 'Yes' : 'No'
                });
            }
        }
        return rows;
    }

    private static List<Object> buildBankDetailsList(List<Applicant__c> applicants) {
        List<Object> rows = new List<Object>();
        if (applicants == null) {
            return rows;
        }
        for (Applicant__c applicant : applicants) {
            if (applicant == null) {
                continue;
            }
            String bankName = '';
            if (applicant.Applicant_Income__r != null) {
                for (Applicant_Income__c income : applicant.Applicant_Income__r) {
                    if (income == null) {
                        continue;
                    }
                    if (income.Income_Detail_Bank_Master__r != null
                        && String.isNotBlank(income.Income_Detail_Bank_Master__r.Name)) {
                        bankName = income.Income_Detail_Bank_Master__r.Name;
                        break;
                    }
                }
            }
            if (String.isBlank(bankName)) {
                bankName = safeStr(applicant.ETB_CASA_Details__c);
            }
            rows.add(new Map<String, Object>{
                'appName' => formatApplicantName(applicant),
                'appType' => val(applicant.Applicant_Type__c),
                'bankName' => val(bankName),
                'accountType' => equalsIgnoreCase(applicant.Has_Bank_Account__c, 'Yes') ? 'Savings Account' : '',
                'accountNum' => val(firstNonBlank(applicant.Bank_Account_No__c, applicant.ETB_CASA_Details__c))
            });
        }
        return rows;
    }

    private static List<Object> buildApplicantInsuranceList(List<Applicant__c> applicants) {
        List<Object> rows = new List<Object>();
        if (applicants == null) {
            return rows;
        }
        for (Applicant__c applicant : applicants) {
            if (applicant == null) {
                continue;
            }
            Insurance__c insurance = (applicant.Insurances__r != null && !applicant.Insurances__r.isEmpty())
                ? applicant.Insurances__r[0]
                : null;
            rows.add(new Map<String, Object>{
                'appName' => formatApplicantName(applicant),
                'applicantInsuranceType' => insurance != null ? val(insurance.Product_Type__c) : '',
                'applicantInsuranceProvider' => insurance != null ? val(insurance.Insurance_Plan__c) : ''
            });
        }
        return rows;
    }

    private static Map<String, Object> buildLoanFields(
        Application__c application,
        Application_Line_Item__c lineItem,
        Asset__c asset
    ) {
        if (application == null) {
            application = new Application__c();
        }
        Decimal roi = lineItem != null
            ? (lineItem.ROI__c != null ? lineItem.ROI__c : lineItem.CRM_IRR__c)
            : null;

        return new Map<String, Object>{
            'loanAmount' => formatIndianCurrency(lineItem != null ? lineItem.Loan_Amount__c : null),
            'loanTenure' => lineItem != null && lineItem.Tenure__c != null
                ? String.valueOf(lineItem.Tenure__c.intValue())
                : '',
            'loanInterest' => roi != null ? String.valueOf(roi.setScale(2)) : '',
            'loanInterestType' => 'FLOATING',
            'loanPurpose' => asset != null ? val(asset.Purpose_of_purchase__c) : '',
            'loanProduct' => val(firstNonBlank(
                lineItem != null ? lineItem.Product__c : null,
                application.Product__c
            )),
            'typeOfLoan' => lineItem != null ? val(lineItem.Installment_Type__c) : '',
            'loanScheme' => (lineItem != null && lineItem.Schemes__r != null)
                ? val(lineItem.Schemes__r.Name)
                : '',
            'productVariant' => asset != null ? val(asset.Variant__c) : '',
            'montlyEMI' => formatIndianCurrency(lineItem != null ? lineItem.EMI_Amount__c : null),
            'loanInstallmentType' => lineItem != null ? val(lineItem.Installment_Type__c) : '',
            'installmentNumberOfLoan' => lineItem != null && lineItem.Tenure__c != null
                ? String.valueOf(lineItem.Tenure__c.intValue())
                : '',
            'loginFeeDetails' => formatIndianCurrency(
                lineItem != null ? parseDecimalValue(lineItem.Applicable_Stamping_Charges__c) : null
            ),
            'processingCharges' => formatIndianCurrency(
                lineItem != null ? lineItem.Documentation_charges__c : null
            )
        };
    }

    private static Map<String, Object> buildPropertyFields(Asset__c asset) {
        if (asset == null) {
            return new Map<String, Object>{
                'propertyIdentified' => 'No',
                'make' => '',
                'model' => '',
                'variant' => '',
                'name' => '',
                'cost' => '',
                'location' => '',
                'coOwnerNumber' => '',
                'type' => ''
            };
        }
        return new Map<String, Object>{
            'propertyIdentified' => 'Yes',
            'make' => val(asset.Make__c),
            'model' => val(CustomerFormDataHelper.joinVehicleLabel(
                asset.Make__c, asset.Model__c, asset.Variant__c
            )),
            'variant' => val(asset.Variant__c),
            'name' => val(asset.Model__c),
            'cost' => formatIndianCurrency(
                asset.On_Road_price__c != null ? asset.On_Road_price__c : asset.Ex_showroom_price__c
            ),
            'location' => val(asset.District__c),
            'coOwnerNumber' => val(asset.Number_of_ownerships__c),
            'type' => val(firstNonBlank(asset.Vehicle_type__c, asset.Purpose_of_purchase__c))
        };
    }

    private static List<ApplicantContext> sliceCoApplicants(List<ApplicantContext> coApplicants) {
        List<ApplicantContext> limited = new List<ApplicantContext>();
        for (Integer i = 0; i < coApplicants.size() && i < MAX_CO_APPS; i++) {
            limited.add(coApplicants[i]);
        }
        return limited;
    }

    private static Map<String, Object> coAppRow(String label, List<String> values) {
        Map<String, Object> row = new Map<String, Object>{ 'col1' => safeStr(label) };
        if (values != null && !values.isEmpty()) {
            row.put('col2', safeStr(values[0]));
        }
        if (values != null && values.size() > 1) {
            row.put('col3', safeStr(values[1]));
        }
        if (values != null && values.size() > 2) {
            row.put('col4', safeStr(values[2]));
        }
        return row;
    }

    private static List<String> valuesForCoApps(List<ApplicantContext> coApplicants, String fieldKey) {
        List<String> values = new List<String>();
        if (coApplicants == null) {
            return values;
        }
        for (ApplicantContext ctx : coApplicants) {
            if (ctx == null) {
                values.add('');
                continue;
            }
            values.add(safeStr(ctx.coAppTableValue(fieldKey)));
        }
        return values;
    }

    private class ApplicantContext {
        public Applicant__c applicant { get; private set; }
        private Map<String, Applicant_Address__c> addressesByType = new Map<String, Applicant_Address__c>();
        private Applicant_Employment__c employment;
        private List<Applicant_Income__c> incomes = new List<Applicant_Income__c>();
        private Map<String, Document_CheckList__c> kycDocsByType = new Map<String, Document_CheckList__c>();
        private Document_CheckList__c panDocument;

        ApplicantContext(Applicant__c record) {
            applicant = record != null ? record : new Applicant__c();
            if (record != null && record.Applicant_Address__r != null) {
                for (Applicant_Address__c address : record.Applicant_Address__r) {
                    if (address == null || String.isBlank(address.Address_Type__c)) {
                        continue;
                    }
                    if (!addressesByType.containsKey(address.Address_Type__c)) {
                        addressesByType.put(address.Address_Type__c, address);
                    }
                }
            }
            if (record != null
                && record.Applicant_Employment__r != null
                && !record.Applicant_Employment__r.isEmpty()) {
                employment = record.Applicant_Employment__r[0];
            }
            if (record != null && record.Applicant_Income__r != null) {
                incomes.addAll(record.Applicant_Income__r);
            }
            if (record != null && record.Document_CheckLists__r != null) {
                for (Document_CheckList__c document : record.Document_CheckLists__r) {
                    if (document == null) {
                        continue;
                    }
                    String docKey = resolveKycKey(document);
                    if (String.isBlank(docKey)) {
                        continue;
                    }
                    if (equalsIgnoreCase(docKey, 'PAN')) {
                        panDocument = document;
                    }
                    if (!kycDocsByType.containsKey(docKey)) {
                        kycDocsByType.put(docKey, document);
                    }
                }
            }
        }

        String coAppTableValue(String fieldKey) {
            Applicant__c a = applicant;
            if ('name'.equals(fieldKey)) {
                return val(formatApplicantName(a));
            }
            if ('customerId'.equals(fieldKey)) {
                return val(a.Customer_Code__c);
            }
            if ('relationship'.equals(fieldKey)) {
                return val(a.Relationship_with_borrower__c);
            }
            if ('dob'.equals(fieldKey)) {
                return val(formatIsoDate(a.Date_of_Birth__c));
            }
            if ('gender'.equals(fieldKey)) {
                return val(a.Gender__c);
            }
            if ('email'.equals(fieldKey)) {
                return val(a.Email__c);
            }
            if ('mobile'.equals(fieldKey)) {
                return val(firstNonBlank(a.Phone__c, a.Contact_number__c));
            }
            if ('pan'.equals(fieldKey)) {
                return val(a.PAN_Number__c);
            }
            if ('form60'.equals(fieldKey)) {
                return form60Value();
            }
            if ('occupation'.equals(fieldKey)) {
                return val(firstNonBlank(a.Profile__c, a.Income_Category__c));
            }
            if ('passport'.equals(fieldKey)) {
                return val(kycNumber('Passport'));
            }
            if ('drivingLicence'.equals(fieldKey)) {
                return val(kycNumber('Driving License'));
            }
            if ('voterId'.equals(fieldKey)) {
                return val(kycNumber('Voter Id'));
            }
            if ('ckyc'.equals(fieldKey)) {
                return val(formatCkyc(a.CKYC_ID__c));
            }
            if ('disability'.equals(fieldKey)) {
                return '';
            }
            if ('qualification'.equals(fieldKey)) {
                return val(a.Customer_Qualification__c);
            }
            if ('maritalStatus'.equals(fieldKey)) {
                return val(a.Marital_status__c);
            }
            if ('organization'.equals(fieldKey)) {
                return val(organizationName());
            }
            if ('totalWorkExp'.equals(fieldKey)) {
                return val(formatWorkExp(totalWorkYears()));
            }
            return '';
        }

        String form60Value() {
            if (equalsIgnoreCase(applicant.Is_PAN_Available__c, 'No')) {
                return 'Yes';
            }
            if (kycDocsByType.containsKey('Form 60')) {
                return 'Yes';
            }
            return 'No';
        }

        String organizationName() {
            if (employment != null) {
                return firstNonBlank(
                    employment.Employer_Business_Name__c,
                    employment.Employer_Name__c,
                    ''
                );
            }
            return safeStr(applicant.Company_Name__c);
        }

        String employmentType() {
            return employment != null ? safeStr(employment.Employer_Type__c) : '';
        }

        String officeEmail() {
            Applicant_Address__c office = addressesByType.get(ADDRESS_OFFICE);
            return office != null ? safeStr(office.Email__c) : '';
        }

        Decimal currentWorkYears() {
            return parseDecimal(employment != null ? employment.Current_years_in_Employment_Business__c : null);
        }

        Decimal totalWorkYears() {
            return parseDecimal(employment != null ? employment.Years_in_employment_business__c : null);
        }

        String formatWorkExp(Decimal years) {
            if (years == null) {
                return '';
            }
            Integer wholeYears = years.intValue();
            return wholeYears == 1 ? '1 Year' : String.valueOf(wholeYears) + ' Years';
        }

        String employeeNumber() {
            return employment != null ? safeStr(employment.Employee_Name__c) : '';
        }

        String salaryBankName() {
            for (Applicant_Income__c income : incomes) {
                if (income != null
                    && income.Income_Detail_Bank_Master__r != null
                    && String.isNotBlank(income.Income_Detail_Bank_Master__r.Name)) {
                    return safeStr(income.Income_Detail_Bank_Master__r.Name);
                }
            }
            return '';
        }

        String formatAddress(String addressType) {
            if (String.isBlank(addressType)) {
                return '';
            }
            Applicant_Address__c address = addressesByType.get(addressType);
            if (address == null) {
                return '';
            }
            List<String> parts = new List<String>();
            addIfPresent(parts, address.Address_Line_1__c);
            addIfPresent(parts, address.Address_Line_2__c);
            addIfPresent(parts, address.Address_Line_3__c);
            addIfPresent(parts, address.Address_Line_4__c);
            addIfPresent(parts, address.City__c);
            addIfPresent(parts, address.District__c);
            addIfPresent(parts, address.State__c);
            addIfPresent(parts, address.PinCode__c);
            addIfPresent(parts, address.Country__c);
            return String.join(parts, ', ');
        }

        String kycNumber(String kycType) {
            if (String.isBlank(kycType)) {
                return '';
            }
            Document_CheckList__c document = kycDocsByType.get(kycType);
            if (document == null) {
                return '';
            }
            if (String.isNotBlank(document.PAN_No__c)) {
                return safeStr(document.PAN_No__c);
            }
            if (document.Applicant_KYC__r != null) {
                if (String.isNotBlank(document.Applicant_KYC__r.Masked_KYC_No__c)) {
                    return safeStr(document.Applicant_KYC__r.Masked_KYC_No__c);
                }
                return safeStr(document.Applicant_KYC__r.KYC_No__c);
            }
            return '';
        }

        String kycExpiry(String kycType) {
            if (String.isBlank(kycType)) {
                return '';
            }
            Document_CheckList__c document = kycDocsByType.get(kycType);
            if (document != null
                && document.Applicant_KYC__r != null
                && document.Applicant_KYC__r.KYC_Expiry_Date__c != null) {
                return formatIsoDate(document.Applicant_KYC__r.KYC_Expiry_Date__c);
            }
            return '';
        }
    }

    private static String resolveKycKey(Document_CheckList__c document) {
        if (document == null) {
            return '';
        }
        if (document.Applicant_KYC__r != null
            && String.isNotBlank(document.Applicant_KYC__r.KYC_Type__c)) {
            return document.Applicant_KYC__r.KYC_Type__c;
        }
        return safeStr(document.Document_Type__c);
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

    private static String formatDisplayDate(Date value) {
        if (value == null) {
            return '';
        }
        DateTime dt = DateTime.newInstance(value.year(), value.month(), value.day());
        return dt.format('dd-MMM-yyyy');
    }

    private static String formatIsoDate(Date value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static String formatCkyc(Decimal ckycId) {
        return ckycId == null ? '' : String.valueOf(ckycId.longValue());
    }

    private static String formatYesNoPicklist(String value) {
        return equalsIgnoreCase(value, 'Yes') ? 'Yes' : 'No';
    }

    private static String formatIndianCurrency(Decimal value) {
        if (value == null) {
            return '';
        }
        String numStr = String.valueOf(value.setScale(0, RoundingMode.HALF_UP).longValue());
        if (numStr.length() <= 3) {
            return numStr;
        }
        String result = numStr.substring(numStr.length() - 3);
        String remaining = numStr.substring(0, numStr.length() - 3);
        while (remaining.length() > 0) {
            Integer take = remaining.length() >= 2 ? 2 : remaining.length();
            result = remaining.substring(remaining.length() - take) + ',' + result;
            remaining = remaining.substring(0, remaining.length() - take);
        }
        return result;
    }

    private static Decimal parseDecimal(String value) {
        return parseDecimalValue(value);
    }

    private static Decimal parseDecimalValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        String text = String.valueOf(value);
        if (String.isBlank(text)) {
            return null;
        }
        try {
            return Decimal.valueOf(text.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean equalsIgnoreCase(String left, String right) {
        if (left == null && right == null) {
            return true;
        }
        if (left == null || right == null) {
            return false;
        }
        return left.equalsIgnoreCase(right);
    }

    private static String safeStr(String value) {
        return String.isBlank(value) ? '' : value.trim();
    }

    private static Decimal firstNonNullDecimal(Decimal first, Decimal second, Decimal third) {
        if (first != null) {
            return first;
        }
        if (second != null) {
            return second;
        }
        return third;
    }

    private static String firstNonBlank(String first, String second) {
        return String.isNotBlank(first) ? first : safeStr(second);
    }

    private static String firstNonBlank(String first, String second, String third) {
        String result = firstNonBlank(first, second);
        return String.isNotBlank(result) ? result : safeStr(third);
    }

    private static String val(String value) {
        return safeStr(value);
    }

    private static void addIfPresent(List<String> parts, String value) {
        if (String.isNotBlank(value)) {
            parts.add(value.trim());
        }
    }
}