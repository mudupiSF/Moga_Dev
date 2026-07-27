/**
 * Customer Exposure — mock API response (Phase A1), persists Applicant_Obligations__c.
 * Invoked via GenericPageLayoutController.savePageData (Callable), not direct @AuraEnabled from LWC.
 */
public with sharing class CustomerExposureServiceController implements Callable {

    public static final String SOURCE_CUSTOMER_EXPOSURE_API = 'Customer Exposure API';
    private static final String ACTION_INVOKE_CUSTOMER_EXPOSURE = 'invokeCustomerExposure';
    private static final String MOCK_CUSTOMER_CODE = 'CU5658609';
    private static final Set<String> EXTERNAL_EXPOSURE_OBLIGATION_TYPES = new Set<String>{ 'External Exposure' };

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_INVOKE_CUSTOMER_EXPOSURE.equalsIgnoreCase(action)) {
            return invokeCustomerExposureInternal(safeArgs);
        }

        return buildResult(false, 'Unknown action: ' + action);
    }

    private static Map<String, Object> invokeCustomerExposureInternal(Map<String, Object> args) {
        String recordId = resolveStringArg(args, 'recordId');
        if (String.isBlank(recordId)) {
            recordId = resolveStringArg(args, 'applicationId');
        }
        if (String.isBlank(recordId)) {
            return buildResult(false, 'Application Id is required.');
        }

        Id applicationId = (Id) recordId.trim();
        String applicantId = resolveStringArg(args, 'applicantId');
        Id checklistApplicantId = String.isNotBlank(applicantId) ? (Id) applicantId.trim() : null;

        try {
            ApplicantResolutionContext applicantContext = loadApplicantResolutionContext(
                applicationId,
                checklistApplicantId
            );
            if (applicantContext.defaultApplicant == null) {
                return buildResult(false, 'No active applicants found on this application.');
            }

            seedMockCustomerCodeMapping(applicantContext);

            Map<String, Object> mockApiResponse = buildMockCustomerExposureResponse();
            List<Applicant_Obligations__c> obligations = buildObligationsFromMockResponse(
                applicationId,
                applicantContext.applicantsByCode,
                mockApiResponse
            );

            replaceObligationsForApplication(applicationId, obligations);
            return buildResult(true, null);
        } catch (Exception e) {
            return buildResult(false, e.getMessage());
        }
    }

    private static String resolveStringArg(Map<String, Object> args, String key) {
        if (args == null || !args.containsKey(key) || args.get(key) == null) {
            return null;
        }
        return String.valueOf(args.get(key)).trim();
    }

    private static Map<String, Object> buildMockCustomerExposureResponse() {
        List<Object> customerExposure = new List<Object>{
            new Map<String, Object>{
                'Deal_No' => 'TLN00348E',
                'Product' => 'E',
                'used' => 'N',
                'Finance_Amt' => 25000000,
                'Deal_Date' => '2018-07-10T00:00:00',
                'Status_Flag' => 'L',
                'SOH' => 793803.32,
                'Deal_Stage' => 'OLD',
                'Sanctioned_Amt' => 25000000,
                'Current_Demand' => 819082.86,
                'Over_Due' => -25279.54
            },
            new Map<String, Object>{
                'Deal_No' => 'TLN00460E',
                'Product' => 'E',
                'used' => 'R',
                'Finance_Amt' => 2000000,
                'Deal_Date' => '2019-11-06T00:00:00',
                'Status_Flag' => 'L',
                'SOH' => 1171490.05,
                'Deal_Stage' => 'OLD',
                'Current_Demand' => 12000
            }
        };

        List<Object> externalExposureSamples = new List<Object>{
            new Map<String, Object>{
                'Account_Type' => 'AL',
                'Account_Type_Desc' => 'Auto Loan',
                'Ownership' => 'Individual',
                'HighCredit' => 400000,
                'CurrentBalance' => 180000,
                'AmountOverdue' => 5000,
                'ReasonforOverdue' => 'Payment delay',
                'FinancierCode' => 'HDFC01',
                'FinanicerName' => 'HDFC Bank'
            },
            new Map<String, Object>{
                'Account_Type' => 'PL',
                'Account_Type_Desc' => 'Personal Loan',
                'Ownership' => 'Joint',
                'HighCredit' => 250000,
                'CurrentBalance' => 95000,
                'AmountOverdue' => 2500,
                'FinancierCode' => 'ICICI01',
                'FinanicerName' => 'ICICI Bank'
            }
        };

        List<Object> lienTable = new List<Object>{
            new Map<String, Object>{
                'Deal_No' => 'TLN00348E',
                'Lien_No' => 'LN-TLN00348E-01',
                'Lien_Type' => 'Vehicle',
                'Source_Deal_No' => 'TLN00348E',
                'Lien_Marking_Period' => '2018-07-10T00:00:00',
                'Lien_Maker_Date' => '2018-07-15T00:00:00',
                'Lien_Request_By' => 'Credit Ops',
                'Lien_Marking_Reason' => 'Existing finance'
            },
            new Map<String, Object>{
                'Deal_No' => 'TLN00460E',
                'Lien_No' => 'LN-TLN00460E-01',
                'Lien_Type' => 'Asset',
                'Source_Deal_No' => 'TLN00460E',
                'Lien_Marking_Period' => '2019-11-06T00:00:00',
                'Lien_Maker_Date' => '2019-11-12T00:00:00',
                'Lien_Request_By' => 'System',
                'Lien_Marking_Reason' => 'Finance'
            }
        };

        Map<String, Object> contentItem = new Map<String, Object>{
            'Customer_Code' => MOCK_CUSTOMER_CODE,
            'Customer_Exposure' => customerExposure,
            'Non_IBL_Exposure' => externalExposureSamples,
            'Lien' => new List<Object>{
                new Map<String, Object>{ 'Table' => lienTable }
            }
        };

        return new Map<String, Object>{
            'status' => 'SUCCESS',
            'respDesc' => 'Customer Exposure',
            'content' => new List<Object>{ contentItem }
        };
    }

    private static ApplicantResolutionContext loadApplicantResolutionContext(
        Id applicationId,
        Id checklistApplicantId
    ) {
        ApplicantResolutionContext context = new ApplicantResolutionContext();
        List<Applicant__c> applicants = [
            SELECT Id, Customer_Code__c, Applicant_Type__c
            FROM Applicant__c
            WHERE Application__c = :applicationId
            AND In_Active_Applicant__c = false
            WITH SECURITY_ENFORCED
        ];

        for (Applicant__c applicant : applicants) {
            if (checklistApplicantId != null && applicant.Id == checklistApplicantId) {
                context.defaultApplicant = applicant;
            }
            if (String.isNotBlank(applicant.Customer_Code__c)) {
                context.applicantsByCode.put(applicant.Customer_Code__c.trim(), applicant);
            }
        }

        if (context.defaultApplicant == null) {
            for (Applicant__c applicant : applicants) {
                if (applicant.Applicant_Type__c == 'Borrower') {
                    context.defaultApplicant = applicant;
                    break;
                }
            }
        }

        if (context.defaultApplicant == null && !applicants.isEmpty()) {
            context.defaultApplicant = applicants[0];
        }

        return context;
    }

    /**
     * Mock API uses CU5658609 — map that code to the checklist/borrower applicant when CIF is not set yet.
     */
    private static void seedMockCustomerCodeMapping(ApplicantResolutionContext context) {
        if (context.defaultApplicant == null) {
            return;
        }
        if (!context.applicantsByCode.containsKey(MOCK_CUSTOMER_CODE)) {
            context.applicantsByCode.put(MOCK_CUSTOMER_CODE, context.defaultApplicant);
        }
    }

    private class ApplicantResolutionContext {
        public Applicant__c defaultApplicant;
        public Map<String, Applicant__c> applicantsByCode = new Map<String, Applicant__c>();
    }

    private static List<Applicant_Obligations__c> buildObligationsFromMockResponse(
        Id applicationId,
        Map<String, Applicant__c> applicantsByCode,
        Map<String, Object> mockApiResponse
    ) {
        List<Applicant_Obligations__c> obligations = new List<Applicant_Obligations__c>();
        List<Object> content = (List<Object>) mockApiResponse.get('content');

        if (content == null) {
            return obligations;
        }

        for (Object contentObject : content) {
            Map<String, Object> contentMap = (Map<String, Object>) contentObject;
            String customerCode = (String) contentMap.get('Customer_Code');
            Applicant__c applicant = applicantsByCode.get(customerCode);
            String typeLabel = resolveTypeLabel(applicant);

            if (applicant != null && String.isNotBlank(typeLabel)) {
                List<Object> customerExposureDeals = (List<Object>) contentMap.get('Customer_Exposure');
                if (customerExposureDeals != null) {
                    for (Object deal : customerExposureDeals) {
                        obligations.add(
                            mapCustomerExposureObligation(
                                applicationId,
                                applicant.Id,
                                customerCode,
                                typeLabel,
                                (Map<String, Object>) deal
                            )
                        );
                    }
                }
            }

            List<Object> externalExposureDeals = (List<Object>) contentMap.get('Non_IBL_Exposure');
            if (externalExposureDeals != null) {
                for (Object deal : externalExposureDeals) {
                    obligations.add(
                        mapExternalExposureObligation(
                            applicationId,
                            applicant != null ? applicant.Id : null,
                            customerCode,
                            (Map<String, Object>) deal
                        )
                    );
                }
            }

            applyLienDetailsFromApiResponse(obligations, contentMap);
        }

        return obligations;
    }

    /**
     * Matches lien Table rows to customer-exposure obligations by Deal_No.
     * Saves the first matching lien row per deal onto the same obligation record.
     */
    private static void applyLienDetailsFromApiResponse(
        List<Applicant_Obligations__c> obligations,
        Map<String, Object> contentMap
    ) {
        Map<String, Applicant_Obligations__c> obligationsByDealNo =
            buildCustomerExposureObligationsByDealNo(obligations);

        List<Object> lienGroups = (List<Object>) contentMap.get('Lien');
        if (lienGroups == null) {
            return;
        }

        for (Object lienGroup : lienGroups) {
            Map<String, Object> lienMap = (Map<String, Object>) lienGroup;
            List<Object> table = (List<Object>) lienMap.get('Table');
            if (table == null) {
                continue;
            }

            for (Object tableRow : table) {
                Map<String, Object> row = (Map<String, Object>) tableRow;
                String dealNo = (String) row.get('Deal_No');
                if (String.isBlank(dealNo)) {
                    continue;
                }

                Applicant_Obligations__c obligation = obligationsByDealNo.get(dealNo.trim());
                if (obligation == null || hasLienFieldsPopulated(obligation)) {
                    continue;
                }

                applyLienTableRowToObligation(obligation, row);
            }
        }
    }

    private static Map<String, Applicant_Obligations__c> buildCustomerExposureObligationsByDealNo(
        List<Applicant_Obligations__c> obligations
    ) {
        Map<String, Applicant_Obligations__c> obligationsByDealNo =
            new Map<String, Applicant_Obligations__c>();

        for (Applicant_Obligations__c obligation : obligations) {
            if (isExternalExposureObligationType(obligation.Type__c)) {
                continue;
            }
            if (String.isBlank(obligation.Deal_No__c)) {
                continue;
            }
            String dealNo = obligation.Deal_No__c.trim();
            if (!obligationsByDealNo.containsKey(dealNo)) {
                obligationsByDealNo.put(dealNo, obligation);
            }
        }

        return obligationsByDealNo;
    }

    private static void applyLienTableRowToObligation(
        Applicant_Obligations__c obligation,
        Map<String, Object> lienRow
    ) {
        String dealNo = (String) lienRow.get('Deal_No');
        String sourceDealNo = (String) lienRow.get('Source_Deal_No');

        obligation.Lien_No__c = (String) lienRow.get('Lien_No');
        obligation.Lien_Type__c = (String) lienRow.get('Lien_Type');
        obligation.Source_Deal_No__c = resolveSourceDealNo(dealNo, sourceDealNo);
        obligation.Lien_Request_By__c = (String) lienRow.get('Lien_Request_By');
        obligation.Lien_Marking_Reason__c = (String) lienRow.get('Lien_Marking_Reason');
        obligation.Lien_Marking_Period__c = parseLienDate((String) lienRow.get('Lien_Marking_Period'));
        obligation.Lien_Maker_Date__c = parseLienDate((String) lienRow.get('Lien_Maker_Date'));
    }

    private static Boolean hasLienFieldsPopulated(Applicant_Obligations__c obligation) {
        return String.isNotBlank(obligation.Lien_No__c)
            || String.isNotBlank(obligation.Lien_Type__c)
            || String.isNotBlank(obligation.Source_Deal_No__c)
            || String.isNotBlank(obligation.Lien_Request_By__c)
            || String.isNotBlank(obligation.Lien_Marking_Reason__c)
            || obligation.Lien_Marking_Period__c != null
            || obligation.Lien_Maker_Date__c != null;
    }

    private static Boolean isExternalExposureObligationType(String obligationType) {
        return String.isNotBlank(obligationType)
            && EXTERNAL_EXPOSURE_OBLIGATION_TYPES.contains(obligationType);
    }

    /** Source deal no matches deal no; cap at Source_Deal_No__c max length (12). */
    private static String resolveSourceDealNo(String dealNo, String sourceDealNo) {
        String resolved = String.isNotBlank(sourceDealNo) ? sourceDealNo.trim() : dealNo;
        if (String.isBlank(resolved)) {
            return null;
        }
        if (resolved.length() > 12) {
            resolved = String.isNotBlank(dealNo) ? dealNo.trim() : resolved.substring(0, 12);
        }
        return resolved;
    }

    private static Date parseLienDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String datePart = value.contains('T') ? value.substringBefore('T') : value.trim();
        return Date.valueOf(datePart);
    }

    private static Applicant_Obligations__c mapCustomerExposureObligation(
        Id applicationId,
        Id applicantId,
        String customerCode,
        String typeLabel,
        Map<String, Object> deal
    ) {
        Applicant_Obligations__c row = new Applicant_Obligations__c(
            Loan_Application__c = applicationId,
            Applicant__c = applicantId,
            Customer_Code__c = customerCode,
            Type__c = typeLabel,
            Obligation_Type__c = 'Obligation',
            Exposure_Header__c = 'Customer Exposure',
            Source__c = SOURCE_CUSTOMER_EXPOSURE_API,
            Deal_No__c = (String) deal.get('Deal_No'),
            Deal_Stage__c = (String) deal.get('Deal_Stage'),
            Status_Flag__c = (String) deal.get('Status_Flag'),
            Type_of_Facility__c = (String) deal.get('Product'),
            Finance_Amt__c = toDecimal(deal.get('Finance_Amt')),
            SOH__c = toDecimal(deal.get('SOH')),
            Sanctioned_Amt__c = toDecimal(deal.get('Sanctioned_Amt')),
            Current_Demand__c = toDecimal(deal.get('Current_Demand')),
            Over_Due__c = toDecimal(deal.get('Over_Due')),
            Exposure_Type__c = resolveExposureType((String) deal.get('Status_Flag'))
        );

        String dealDate = (String) deal.get('Deal_Date');
        if (String.isNotBlank(dealDate)) {
            row.Deal_Date__c = Datetime.valueOf(dealDate.replace('T', ' '));
        }

        return row;
    }

    private static Applicant_Obligations__c mapExternalExposureObligation(
        Id applicationId,
        Id applicantId,
        String customerCode,
        Map<String, Object> deal
    ) {
        String accountTypeCode = resolveAccountTypeCode(deal);
        String accountTypeDesc = resolveAccountTypeDesc(deal, accountTypeCode);

        return new Applicant_Obligations__c(
            Loan_Application__c = applicationId,
            Applicant__c = applicantId,
            Customer_Code__c = customerCode,
            Type__c = 'External Exposure',
            Obligation_Type__c = 'Liability',
            Exposure_Header__c = 'External Exposure',
            Source__c = SOURCE_CUSTOMER_EXPOSURE_API,
            Account_Type__c = accountTypeCode,
            Account_Type_Desc__c = accountTypeDesc,
            Ownership__c = (String) deal.get('Ownership'),
            Financier_Code__c = (String) deal.get('FinancierCode'),
            Financier_Name__c = (String) deal.get('FinanicerName'),
            Reason_for_Overdue__c = (String) deal.get('ReasonforOverdue'),
            High_Credit__c = toDecimal(deal.get('HighCredit')),
            Current_Balance__c = toDecimal(deal.get('CurrentBalance')),
            Amount_Overdue__c = toDecimal(deal.get('AmountOverdue'))
        );
    }

    /** Account_Type__c allows max 3 characters; longer API values go to Account_Type_Desc__c. */
    private static String resolveAccountTypeCode(Map<String, Object> deal) {
        String accountType = (String) deal.get('Account_Type');
        if (String.isBlank(accountType)) {
            return null;
        }
        accountType = accountType.trim();
        if (accountType.length() <= 3) {
            return accountType;
        }
        return accountType.substring(0, 3);
    }

    private static String resolveAccountTypeDesc(
        Map<String, Object> deal,
        String accountTypeCode
    ) {
        String accountTypeDesc = (String) deal.get('Account_Type_Desc');
        if (String.isNotBlank(accountTypeDesc)) {
            return accountTypeDesc.trim();
        }

        String accountType = (String) deal.get('Account_Type');
        if (String.isNotBlank(accountType) && accountType.trim().length() > 3) {
            return accountType.trim();
        }

        return null;
    }

    private static String resolveTypeLabel(Applicant__c applicant) {
        if (applicant == null || String.isBlank(applicant.Applicant_Type__c)) {
            return null;
        }
        if (applicant.Applicant_Type__c == 'Borrower') {
            return 'Borrower Exposure';
        }
        if (applicant.Applicant_Type__c == 'Co-borrower') {
            return 'Co-Borrower Exposure';
        }
        if (applicant.Applicant_Type__c == 'Guarantor') {
            return 'Guarantor Exposure';
        }
        if (applicant.Applicant_Type__c == 'Beneficiary') {
            return 'Existing Beneficiary Exposure';
        }
        return null;
    }

    private static String resolveExposureType(String statusFlag) {
        if (statusFlag == 'L') {
            return 'Existing';
        }
        if (statusFlag == 'Z') {
            return 'Closed';
        }
        return null;
    }

    private static Integer replaceObligationsForApplication(
        Id applicationId,
        List<Applicant_Obligations__c> obligations
    ) {
        delete [
            SELECT Id
            FROM Applicant_Obligations__c
            WHERE Loan_Application__c = :applicationId
            AND Source__c = :SOURCE_CUSTOMER_EXPOSURE_API
        ];

        if (obligations.isEmpty()) {
            return 0;
        }

        insert obligations;
        return obligations.size();
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    private static Map<String, Object> buildResult(Boolean isSuccess, String message) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => isSuccess
        };
        if (!isSuccess && String.isNotBlank(message)) {
            result.put('message', message);
        }
        return result;
    }
}