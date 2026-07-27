/*
@author: Akash Kandwal
@description : Controller for OfferPage
*/
public with sharing class OfferPageController implements Callable {

    private static final String OFFER_STAGE = 'Offer';

    // ── Callable interface ────────────────────────────────────────────────────
    public Object call(String action, Map<String, Object> args) {
        if (action == 'getPayinPayout')    return doGetPayinPayout(args);
        if (action == 'updatePayinPayout') return doUpdatePayinPayout(args);
        throw new System.AuraHandledException('Unknown action: ' + action);
    }

    // ── Reset to Income Verification ──────────────────────────────────────────
    @AuraEnabled
    public static Map<String, Object> resetToIncomeVerification(String applicationId) {
        Map<String, Object> result = new Map<String, Object>{
            'success' => false,
            'message' => ''
        };
        if (String.isBlank(applicationId)) {
            result.put('message', 'Application ID is required.');
            return result;
        }
        try {
            List<Application__c> apps = [
                SELECT Id, Stage__c, Sub_Stage__c,(SELECT Id, Current_Loan_Stage_Complete__c FROM Applicants__r)
                FROM Application__c
                WHERE Id = :applicationId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (apps.isEmpty() || apps[0].Applicants__r.isEmpty()) {
                result.put('message', 'Application or applicant record not found.');
                return result;
            }
            for(Applicant__c applicant : apps[0].Applicants__r) {
                applicant.Current_Loan_Stage_Complete__c = 'Loan Terms';
            }
            update apps[0].Applicants__r;

            Application__c app = apps[0];
            app.Stage__c     = 'DDE';
            app.Sub_Stage__c = 'Income and Banking Details';
            update app;
            result.put('success', true);
            result.put('message', 'Application reset to Income Verification.');
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> getProductType(String applicationId) {
        Map<String, Object> result = new Map<String, Object>{ 'productType' => '' };
        if (String.isBlank(applicationId)) return result;
        List<Application__c> apps = [
            SELECT Id, Product__c
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!apps.isEmpty()) {
            result.put('productType', apps[0].Product__c);
        }
        return result;
    }

    // ── Fetch Offer Data from Application_Line_Item__c ───────────────────────
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getOfferData(String applicationId, String applicationLineItemId) {
        Map<String, Object> result = new Map<String, Object>{ 'hasOffer' => false, 'isStp' => false };
        if (String.isBlank(applicationId)) return result;
        try {
            List<Applicant__c> borrowers = [
                SELECT Id, Phone__c
                FROM Applicant__c
                WHERE Application__c = :applicationId
                  AND Applicant_Type__c = 'Borrower'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!borrowers.isEmpty()) {
                result.put('borrowerApplicantId', borrowers[0].Id);
                result.put('borrowerPhone', borrowers[0].Phone__c);
            }

            Id lineItemId = resolveApplicationLineItemId(applicationId, null, applicationLineItemId);
            List<Application_Line_Item__c> items;
            if (lineItemId != null) {
                items = [
                    SELECT Id, Loan_Amount__c, CRM_IRR__c, Tenure__c, EMI_Amount__c,
                           Advance_EMI__c, Holiday_period__c, Installment_Type__c,
                           First_EMI_Date__c, Second_EMI_Date__c, Application__r.Sanction_Status__c,
                           Product__c
                    FROM Application_Line_Item__c
                    WHERE Id = :lineItemId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            } else {
                items = [
                    SELECT Id, Loan_Amount__c, CRM_IRR__c, Tenure__c, EMI_Amount__c,
                           Advance_EMI__c, Holiday_period__c, Installment_Type__c,
                           First_EMI_Date__c, Second_EMI_Date__c, Application__r.Sanction_Status__c,
                           Product__c
                    FROM Application_Line_Item__c
                    WHERE Application__c = :applicationId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            }

            for (Applicant_Income__c income : [
                SELECT Id,Name, Consolidated_Yearly_Income__c
                FROM Applicant_Income__c
                WHERE Applicant__r.Application__c = :applicationId AND Applicant__r.Applicant_Type__c = 'Borrower'
            ]) {
                if (income.Name == 'Declared Income') result.put('declaredIncomeOffer', income.Consolidated_Yearly_Income__c);
                if (income.Name == 'Bank Statement') result.put('bankStatementOffer', income.Consolidated_Yearly_Income__c);
                if (income.Name == 'Mobile Number') result.put('bureauSurrogateOffer', income.Consolidated_Yearly_Income__c);
            }

            if (!items.isEmpty()) {
                Application_Line_Item__c li = items[0];
                result.put('hasOffer', true);
                result.put('lineItem',   li);
                result.put('applicationLineItemId', li.Id);
                result.put('minLoanAmount', 50000);
                result.put('maxLoanAmount', 200000000);
                result.put('minTenure', 12);
                result.put('maxTenure', 60);
                result.put('isStp', li.Application__r.Sanction_Status__c == 'STP');
                result.put('sanctionStatus', li.Application__r.Sanction_Status__c);
                result.put('productType', li.Product__c);
            }
        } catch (Exception ex) {
            result.put('error', ex.getMessage());
        }
        return result;
    }

    // ── Save Offer Engine Result to Application_Line_Item__c ─────────────────
    @AuraEnabled
    public static Map<String, Object> saveOfferEngineResult(String jsonData) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        if (String.isBlank(jsonData)) {
            result.put('message', 'Data is required.');
            return result;
        }
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(jsonData);
            String applicationId = (String) data.get('applicationId');
            String applicationLineItemId = (String) data.get('applicationLineItemId');
            if (String.isBlank(applicationId)) {
                result.put('message', 'Application ID is required.');
                return result;
            }
            Id lineItemId = resolveApplicationLineItemId(applicationId, null, applicationLineItemId);
            List<Application_Line_Item__c> items;
            if (lineItemId != null) {
                items = [
                    SELECT Id, Loan_Amount__c, CRM_IRR__c, Tenure__c, EMI_Amount__c
                    FROM Application_Line_Item__c
                    WHERE Id = :lineItemId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            } else {
                items = [
                    SELECT Id, Loan_Amount__c, CRM_IRR__c, Tenure__c, EMI_Amount__c
                    FROM Application_Line_Item__c
                    WHERE Application__c = :applicationId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            }
            Application_Line_Item__c li = items.isEmpty()
                ? new Application_Line_Item__c(Application__c = applicationId)
                : items[0];
            if (data.get('loanAmount')   != null) li.Loan_Amount__c = Decimal.valueOf(String.valueOf(data.get('loanAmount')));
            if (data.get('interestRate') != null) li.CRM_IRR__c     = Decimal.valueOf(String.valueOf(data.get('interestRate')));
            if (data.get('tenure')       != null) li.Tenure__c      = Decimal.valueOf(String.valueOf(data.get('tenure')));
            if (data.get('emiAmount')    != null) li.EMI_Amount__c  = Decimal.valueOf(String.valueOf(data.get('emiAmount')));
            if (data.get('installmentType') != null) li.Installment_Type__c = String.valueOf(data.get('installmentType')) == 'equated' ? 'Equated' : 'Structured';
            if (data.get('advanceEMI')      != null) li.Advance_EMI__c      = String.valueOf(data.get('advanceEMI')) == 'yes';
            if (data.get('moratoriumDays')  != null) li.Holiday_period__c   = String.valueOf(data.get('moratoriumDays'));
            // First EMI Date: if today's day < selected day use current month, else next month
            if (data.get('firstEmiDueDateDay') != null) {
                Integer emiDay = Integer.valueOf(String.valueOf(data.get('firstEmiDueDateDay')));
                Date today = Date.today().addDays(Integer.valueOf(li.Holiday_period__c));
                Date firstEmiDate = today.day() < emiDay
                    ? Date.newInstance(today.year(), today.month(), emiDay)
                    : Date.newInstance(today.addMonths(1).year(), today.addMonths(1).month(), emiDay);
                li.First_EMI_Date__c = firstEmiDate;
            }
            // Second EMI Date — passed as 'yyyy-MM-dd' string from LWC
            li.Second_EMI_Date__c = li.First_EMI_Date__c.addMonths(1);
               
            upsert li;
            result.put('isSuccess', true);
            result.put('applicationLineItemId', li.Id);
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> markOfferStageComplete(String applicationLineItemId) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        Id lineItemId = parseId(applicationLineItemId);
        if (lineItemId == null) {
            result.put('message', 'Application Line Item ID is required.');
            return result;
        }
        try {
            List<Application_Line_Item__c> lineItems = [
                SELECT Id, Stage_Completed__c
                FROM Application_Line_Item__c
                WHERE Id = :lineItemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (lineItems.isEmpty()) {
                result.put('message', 'Application Line Item not found.');
                return result;
            }
            Application_Line_Item__c li = lineItems[0];
            li.Stage_Completed__c = appendStageCompleted(li.Stage_Completed__c, OFFER_STAGE);
            update li;
            result.put('isSuccess', true);
            result.put('applicationLineItemId', String.valueOf(lineItemId));
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    // ── Create Repayment Schedule records after Offer Engine ─────────────────
    @AuraEnabled
    public static Map<String, Object> createRepaymentSchedule(String jsonData) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        if (String.isBlank(jsonData)) {
            result.put('message', 'Data is required.');
            return result;
        }
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(jsonData);
            String applicationId = (String) data.get('applicationId');
            if (String.isBlank(applicationId)) {
                result.put('message', 'Application ID is required.');
                return result;
            }

            List<Application_Line_Item__c> lineItems = [
                SELECT Id, Loan_Amount__c, CRM_IRR__c, Tenure__c, EMI_Amount__c,
                       Installment_Type__c, First_EMI_Date__c, Holiday_period__c
                FROM Application_Line_Item__c
                WHERE Application__c = :applicationId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (lineItems.isEmpty()) {
                result.put('message', 'Application Line Item not found.');
                return result;
            }

            Application_Line_Item__c lineItem = lineItems[0];
            Id lineItemId = lineItem.Id;

            Decimal loanAmount = lineItem.Loan_Amount__c != null ? lineItem.Loan_Amount__c : 0;
            if (data.get('loanAmount') != null && String.isNotBlank(String.valueOf(data.get('loanAmount')))) {
                loanAmount = Decimal.valueOf(String.valueOf(data.get('loanAmount')));
            }

            Decimal annualRate = lineItem.CRM_IRR__c != null ? lineItem.CRM_IRR__c : 0;
            if (data.get('interestRate') != null && String.isNotBlank(String.valueOf(data.get('interestRate')))) {
                annualRate = Decimal.valueOf(String.valueOf(data.get('interestRate')));
            }

            Integer tenureMonths = lineItem.Tenure__c != null ? Integer.valueOf(lineItem.Tenure__c) : 12;
            if (data.get('tenure') != null && String.isNotBlank(String.valueOf(data.get('tenure')))) {
                tenureMonths = Integer.valueOf(String.valueOf(data.get('tenure')));
            }

            Decimal emiAmount = lineItem.EMI_Amount__c != null ? lineItem.EMI_Amount__c : 0;
            if (data.get('emiAmount') != null && String.isNotBlank(String.valueOf(data.get('emiAmount')))) {
                emiAmount = Decimal.valueOf(String.valueOf(data.get('emiAmount')));
            }

            String installType = lineItem.Installment_Type__c;
            if (data.get('installmentType') != null && String.isNotBlank(String.valueOf(data.get('installmentType')))) {
                installType = String.valueOf(data.get('installmentType'));
            }
            Boolean isEquatedInstallment = String.isBlank(installType)
                || installType.equalsIgnoreCase('equated');

            Date emiDate = lineItem.First_EMI_Date__c;
            if (data.get('firstEmiDate') != null && String.isNotBlank(String.valueOf(data.get('firstEmiDate')))) {
                String firstEmiDateStr = String.valueOf(data.get('firstEmiDate')).trim();
                if (firstEmiDateStr.contains('-') && firstEmiDateStr.length() >= 10) {
                    emiDate = Date.valueOf(firstEmiDateStr.left(10));
                } else {
                    Integer emiDay = Integer.valueOf(firstEmiDateStr);
                    Integer morDays = lineItem.Holiday_period__c != null
                        ? Integer.valueOf(lineItem.Holiday_period__c) : 0;
                    Date today = Date.today().addDays(morDays);
                    emiDate = today.day() < emiDay
                        ? Date.newInstance(today.year(), today.month(), emiDay)
                        : Date.newInstance(today.addMonths(1).year(), today.addMonths(1).month(), emiDay);
                }
            }
            if (emiDate == null) {
                result.put('message', 'First EMI date is required to create repayment schedule.');
                return result;
            }

            List<Repayment_Schedule__c> existing = [
                SELECT Id FROM Repayment_Schedule__c
                WHERE Application_Line_Items__c = :lineItemId
                WITH SECURITY_ENFORCED
            ];
            if (!existing.isEmpty()) {
                delete existing;
            }

            Double mr = annualRate > 0 ? (Double)(annualRate / 12 / 100) : 0;
            Decimal emi = emiAmount;
            if (emi == 0 && mr > 0 && tenureMonths > 0) {
                Double power = Math.pow(1 + mr, tenureMonths);
                emi = ((Decimal)((Double)loanAmount * mr * power / (power - 1))).setScale(2, System.RoundingMode.HALF_UP);
            }

            List<Repayment_Schedule__c> schedules = new List<Repayment_Schedule__c>();
            Decimal balance = loanAmount;
            for (Integer i = 1; i <= tenureMonths; i++) {
                Decimal interest = mr > 0
                    ? (balance * Decimal.valueOf(mr)).setScale(2, System.RoundingMode.HALF_UP) : 0;
                Decimal principal = i < tenureMonths
                    ? (emi - interest).setScale(2, System.RoundingMode.HALF_UP) : balance;
                if (principal < 0) {
                    principal = 0;
                }
                Decimal closing = (balance - principal).setScale(2, System.RoundingMode.HALF_UP);
                if (closing < 0) {
                    closing = 0;
                }
                schedules.add(new Repayment_Schedule__c(
                    Application_Line_Items__c  = lineItemId,
                    Number_of_Installments__c = i,
                    Installment_Type__c       = isEquatedInstallment ? 'Equated' : 'Structured',
                    EMI_Due_Date__c           = emiDate,
                    Opening_Principal__c      = balance.setScale(2, System.RoundingMode.HALF_UP),
                    EMI_Amount__c             = (i < tenureMonths ? emi : principal + interest).setScale(2, System.RoundingMode.HALF_UP),
                    Principal_Component__c    = principal,
                    Interest_Component__c     = interest,
                    Closing_Principal__c      = closing
                ));
                balance = closing;
                emiDate = emiDate.addMonths(1);
            }
            insert schedules;
            result.put('isSuccess', true);
            result.put('count', schedules.size());
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    // ── Fetch Repayment Schedule for display ──────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getRepaymentSchedule(String applicationId) {
        Map<String, Object> result = new Map<String, Object>{ 'hasData' => false };
        if (String.isBlank(applicationId)) return result;
        try {
            List<Application_Line_Item__c> lineItems = [
                SELECT Id, Loan_Amount__c, CRM_IRR__c, Tenure__c, EMI_Amount__c
                FROM Application_Line_Item__c
                WHERE Application__c = :applicationId
                WITH SECURITY_ENFORCED LIMIT 1
            ];
            if (lineItems.isEmpty()) return result;
            Application_Line_Item__c li = lineItems[0];
            List<Repayment_Schedule__c> schedules = [
                SELECT Id, Number_of_Installments__c, Installment_Type__c, EMI_Due_Date__c,
                       Opening_Principal__c, Closing_Principal__c, EMI_Amount__c,
                       Principal_Component__c, Interest_Component__c
                FROM Repayment_Schedule__c
                WHERE Application_Line_Items__c = :li.Id
                WITH SECURITY_ENFORCED
                ORDER BY Number_of_Installments__c ASC
            ];
            result.put('hasData',     !schedules.isEmpty());
            result.put('schedules',   schedules);
            result.put('loanAmount',  li.Loan_Amount__c);
            result.put('tenure',      li.Tenure__c);
            result.put('monthlyEmi',  li.EMI_Amount__c);
            result.put('interestRate',li.CRM_IRR__c);
        } catch (Exception ex) {
            result.put('error', ex.getMessage());
        }
        return result;
    }

    private Map<String, Object> doGetPayinPayout(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        String opportunityId = (String) args.get('recordId');
        if (String.isBlank(opportunityId)) {
            result.put('message', 'Opportunity ID is required.');
            return result;
        }
        try {
            String applicationLineItemId = getApplicationLineItemIdFromArgs(args);
            Id lineItemId = resolveApplicationLineItemId(opportunityId, null, applicationLineItemId);
            List<Application_Line_Item__c> lineItems;
            if (lineItemId != null) {
                lineItems = [
                    SELECT Id, Service_charges__c, Documentation_charges__c, Stamping_charges__c,
                           Stamping_Done_By__c, Cess_Charges__c
                    FROM Application_Line_Item__c
                    WHERE Id = :lineItemId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            } else {
                lineItems = [
                    SELECT Id, Service_charges__c, Documentation_charges__c, Stamping_charges__c,
                           Stamping_Done_By__c, Cess_Charges__c
                    FROM Application_Line_Item__c
                    WHERE Application__c = :opportunityId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            }
            if (!lineItems.isEmpty()) {
                Application_Line_Item__c li = lineItems[0];
                result.put('serviceCharges',                 li.Service_charges__c);
                result.put('documentationCharges',           li.Documentation_charges__c);
                result.put('totalApplicableStampingCharges', li.Stamping_charges__c);
                result.put('stampingDoneBy',                 li.Stamping_Done_By__c);
                result.put('cessCharges',                    li.Cess_Charges__c);
            }
            result.put('isSuccess', true);
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    private Map<String, Object> doUpdatePayinPayout(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{ 'isSuccess' => false };
        String opportunityId = (String) args.get('recordId');
        if (String.isBlank(opportunityId)) {
            result.put('message', 'Record ID is required.');
            return result;
        }
        try {
            String applicationLineItemId = getApplicationLineItemIdFromArgs(args);
            Id lineItemId = resolveApplicationLineItemId(opportunityId, null, applicationLineItemId);
            List<Application_Line_Item__c> lineItems;
            if (lineItemId != null) {
                lineItems = [
                    SELECT Id, Service_charges__c, Documentation_charges__c, Stamping_charges__c,
                           Stamping_Done_By__c, Cess_Charges__c
                    FROM Application_Line_Item__c
                    WHERE Id = :lineItemId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            } else {
                lineItems = [
                    SELECT Id, Service_charges__c, Documentation_charges__c, Stamping_charges__c,
                           Stamping_Done_By__c, Cess_Charges__c
                    FROM Application_Line_Item__c
                    WHERE Application__c = :opportunityId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            }
            Application_Line_Item__c lineItem = lineItems.isEmpty()
                ? new Application_Line_Item__c(Application__c = opportunityId)
                : lineItems[0];
            if (args.containsKey('serviceCharges') && args.get('serviceCharges') != null)
                lineItem.Service_charges__c = Decimal.valueOf(String.valueOf(args.get('serviceCharges')));
            if (args.containsKey('documentationCharges') && args.get('documentationCharges') != null)
                lineItem.Documentation_charges__c = Decimal.valueOf(String.valueOf(args.get('documentationCharges')));
            if (args.containsKey('totalApplicableStampingCharges') && args.get('totalApplicableStampingCharges') != null)
                lineItem.Stamping_charges__c = Decimal.valueOf(String.valueOf(args.get('totalApplicableStampingCharges')));
            if (args.containsKey('stampingDoneBy') && args.get('stampingDoneBy') != null)
                lineItem.Stamping_Done_By__c = String.valueOf(args.get('stampingDoneBy'));
            if (args.containsKey('cessCharges') && args.get('cessCharges') != null)
                lineItem.Cess_Charges__c = Decimal.valueOf(String.valueOf(args.get('cessCharges')));
            upsert lineItem;
            result.put('isSuccess', true);
            result.put('message', 'Pay In / Pay Out details updated successfully.');
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    private static String getApplicationLineItemIdFromArgs(Map<String, Object> args) {
        if (args == null) {
            return null;
        }
        Object applicationLineItemId = args.get('applicationLineItemId');
        if (applicationLineItemId != null && String.isNotBlank(String.valueOf(applicationLineItemId))) {
            return String.valueOf(applicationLineItemId);
        }
        Object lineItemId = args.get('lineItemId');
        if (lineItemId != null && String.isNotBlank(String.valueOf(lineItemId))) {
            return String.valueOf(lineItemId);
        }
        return null;
    }

    @AuraEnabled
    public static Map<String, Object> saveInsuranceRecord(String dataJson) {
        Map<String, Object> result = new Map<String, Object>{ 'success' => false };
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(dataJson);

            Id     applicationId = (Id)     data.get('applicationId');
            String customerType  = (String) data.get('customerType');
            List<Object> plans   = (List<Object>) data.get('plans');
            Id lineItemId = parseId((String) data.get('applicationLineItemId'));
            if (lineItemId == null) {
                lineItemId = parseId((String) data.get('lineItemId'));
            }

            if (plans == null || plans.isEmpty()) {
                result.put('message', 'No plans provided');
                return result;
            }

            // Resolve applicant
            String apType = customerType == 'borrower' ? 'Borrower' : 'Co-Borrower';
            List<Applicant__c> aps = [
                SELECT Id FROM Applicant__c
                WHERE  Application__c   = :applicationId
                AND    Applicant_Type__c = :apType
                LIMIT  1
            ];
            Id applicantId = aps.isEmpty() ? null : aps[0].Id;

            // Replace existing records for the same plan types (avoid duplicate inserts).
            Set<String> planTypes = new Set<String>();
            for (Object planObj : plans) {
                Map<String, Object> p = (Map<String, Object>) planObj;
                String planType = resolveInsurancePlanType(p);
                if (String.isNotBlank(planType)) {
                    planTypes.add(planType);
                }
            }

            if (!planTypes.isEmpty()) {
                if (lineItemId != null) {
                    delete [
                        SELECT Id FROM Insurance__c
                        WHERE Application_Line_Items__c = :lineItemId
                        AND Insurance_Plan__c IN :planTypes
                    ];
                } else if (applicantId != null) {
                    delete [
                        SELECT Id FROM Insurance__c
                        WHERE Applicant__c = :applicantId
                        AND Insurance_Plan__c IN :planTypes
                    ];
                }
            }

            // Build insert list
            List<Insurance__c> toInsert = new List<Insurance__c>();
            for (Object planObj : plans) {
                Map<String, Object> p = (Map<String, Object>) planObj;
                String planType = resolveInsurancePlanType(p);
                String planName = resolveInsurancePlanName(p);
                Decimal premium = p.get('premium') != null ? Decimal.valueOf(String.valueOf(p.get('premium'))) : 0;
                Decimal amount  = p.get('amount')  != null ? Decimal.valueOf(String.valueOf(p.get('amount')))  : 0;
                String fundedNonFunded = resolveFundedNonFunded(p);

                Insurance__c ins = new Insurance__c(
                    Name                 = planName,
                    Insurance_Plan__c    = planType,
                    Amount__c            = amount,
                    Funded_Non_funded__c = fundedNonFunded,
                    Funded_Premium__c    = fundedNonFunded == 'Funded' ? premium : null,
                    Is_Active__c         = true
                );
                if (applicantId != null) {
                    ins.Applicant__c = applicantId;
                }
                if (lineItemId != null) {
                    ins.Application_Line_Items__c = lineItemId;
                }
                toInsert.add(ins);
            }

            insert toInsert;

            result.put('success', true);
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', e.getMessage());
        }
        return result;
    }

    private static String resolveInsurancePlanType(Map<String, Object> planData) {
        Object planType = planData.get('insurancePlanType');
        if (planType == null) {
            planType = planData.get('type');
        }
        return planType != null ? String.valueOf(planType) : null;
    }

    private static String resolveInsurancePlanName(Map<String, Object> planData) {
        Object planName = planData.get('insurancePlanName');
        if (planName == null) {
            planName = planData.get('planName');
        }
        return planName != null ? String.valueOf(planName) : null;
    }

    private static String resolveFundedNonFunded(Map<String, Object> planData) {
        Object fundedValue = planData.get('fundedNonFunded');
        if (fundedValue != null) {
            return String.valueOf(fundedValue);
        }
        Object isFunded = planData.get('isFunded');
        if (isFunded == null) {
            return 'Non-Funded';
        }
        return Boolean.valueOf(String.valueOf(isFunded)) ? 'Funded' : 'Non-Funded';
    }

    /**
     * Accepts a single JSON string. Parses it, resolves the applicant, and
     * returns all active Insurance__c records for pre-populating the modal.
     * Expected JSON keys: applicationId, customerType
     */
    @AuraEnabled(cacheable=false)
    public static List<Insurance__c> getInsuranceRecords(String dataJson) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(dataJson);
            Id     applicationId = (Id)     data.get('applicationId');
            String customerType  = (String) data.get('customerType');

            String apType = customerType == 'borrower' ? 'Borrower' : 'Co-Borrower';
            List<Applicant__c> aps = [
                SELECT Id FROM Applicant__c
                WHERE  Application__c   = :applicationId
                AND    Applicant_Type__c = :apType
                LIMIT  1
            ];
            if (aps.isEmpty()) return new List<Insurance__c>();
            return [
                SELECT Id, Name, Insurance_Plan__c, Amount__c,
                       Funded_Non_funded__c, Funded_Premium__c, Is_Active__c
                FROM   Insurance__c
                WHERE  Applicant__c = :aps[0].Id
                AND    Is_Active__c = true
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class ApplicantHighlightWrapper {
        @AuraEnabled public String  id                         { get; set; }
        @AuraEnabled public String  applicantName              { get; set; }
        @AuraEnabled public String  customerFullName          { get; set; }
        @AuraEnabled public String  applicantType              { get; set; }
        @AuraEnabled public Boolean insuranceConsentReceived   { get; set; }
        @AuraEnabled public Boolean applicationConsentReceived { get; set; }
        @AuraEnabled public Boolean eKYCAccepted               { get; set; }
        @AuraEnabled public String  email                      { get; set; }
        @AuraEnabled public Boolean emailVerified              { get; set; }
    }

    public class HighlightPanelResult {
        @AuraEnabled public List<ApplicantHighlightWrapper> applicants     { get; set; }
        @AuraEnabled public String                          statusKFS      { get; set; }
        @AuraEnabled public String                          teamMemberRole { get; set; }
        @AuraEnabled public Boolean                         success        { get; set; }
        @AuraEnabled public String                          message        { get; set; }
    }

    /**
     * Returns all active Applicant__c records for the given Application__c,
     * plus KFS status and the current user's team-member role.
     * Applicant_Type__c values: 'Borrower', 'Co-Borrower', 'Guarantor', 'Beneficiary'
     */
    @AuraEnabled(cacheable=false)
    public static HighlightPanelResult getHighlightPanelData(String applicationId) {
        HighlightPanelResult result = new HighlightPanelResult();
        result.applicants     = new List<ApplicantHighlightWrapper>();
        result.statusKFS      = 'Pending';
        result.teamMemberRole = '';
        result.success        = false;

        if (String.isBlank(applicationId)) {
            result.message = 'Application ID is required.';
            return result;
        }

        try {
            for (Applicant__c app : [
                SELECT Id, Name, Customer_First_Name__c, Customer_Last_Name__c, Applicant_Type__c,
                       Email__c,
                       Email_Verified__c
                FROM   Applicant__c
                WHERE  Application__c = :applicationId AND Applicant_Type__c != 'Reference' AND In_Active_Applicant__c = false
                WITH   SECURITY_ENFORCED
                ORDER  BY Applicant_Type__c ASC, CreatedDate ASC
            ]) {
                ApplicantHighlightWrapper w    = new ApplicantHighlightWrapper();
                w.id                           = app.Id;
                w.applicantName                = app.Name;
                w.customerFullName            = app.Customer_First_Name__c + ' ' + (String.isNotBlank(app.Customer_Last_Name__c) ? app.Customer_Last_Name__c : '');
                w.applicantType                = app.Applicant_Type__c;
                w.insuranceConsentReceived     = false;
                w.applicationConsentReceived   = false;
                w.eKYCAccepted                 = false;
                w.email                        = app.Email__c;
                w.emailVerified                = app.Email_Verified__c               == true;
                result.applicants.add(w);
            }

            result.success = true;
        } catch (Exception ex) {
            result.message = ex.getMessage();
        }

        return result;
    }

    /**
     * Sets Email_Verified__c = true on the given Applicant__c record
     * after a successful OTP verification on the Offer page.
     */
    @AuraEnabled
    public static Map<String, Object> updateApplicantEmailVerified(String applicantId) {
        Map<String, Object> result = new Map<String, Object>{ 'success' => false };
        if (String.isBlank(applicantId)) {
            result.put('message', 'Applicant ID is required.');
            return result;
        }
        try {
            update new Applicant__c(Id = applicantId, Email_Verified__c = true);
            result.put('success', true);
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    private static final String APPLICATION_FORM_DOC_TYPE = 'Application Form';

    /**
     * Creates (or reuses) a Document_CheckList__c row for Application Form PDF rendering.
     *
     * @param applicationId  Application__c Id
     * @param applicantId    Applicant__c Id (optional — defaults to Borrower)
     * @param documentName   Value for Document_CheckList__c.Name
     * @return               documentChecklistId only
     */
    @AuraEnabled
    public static String createApplicationFormDocumentChecklist(
        String applicationId,
        String applicantId,
        String documentName
    ) {
        if (String.isBlank(applicationId)) {
            throw new AuraHandledException('Application ID is required.');
        }
        if (String.isBlank(documentName)) {
            throw new AuraHandledException('Document name is required.');
        }
        try {
            Id appId      = applicationId;
            Id borrowerId = resolveBorrowerApplicantId(applicationId, applicantId);

            //Check existing if present just return existing doc id
            List<Document_CheckList__c> existingDocs = [
                SELECT Id
                FROM Document_CheckList__c
                WHERE Application__c = :appId AND Applicant__c = :borrowerId AND Document_Type__c = 'Application Form'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!existingDocs.isEmpty()) {
                //delete all files from this doc
                delete [
                    SELECT Id
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :existingDocs[0].Id
                ];
                return existingDocs[0].Id;
            }

            Document_CheckList__c doc = new Document_CheckList__c(
                Application__c   = appId,
                Applicant__c     = borrowerId,
                Document_Type__c = APPLICATION_FORM_DOC_TYPE,
                Is_Active__c     = true,
                Name             = documentName
            );
            insert doc;
            return doc.Id;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    private static Id resolveBorrowerApplicantId(String applicationId, String applicantId) {
        if (String.isNotBlank(applicantId)) {
            return applicantId;
        }
        List<Applicant__c> borrowers = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :applicationId AND Applicant_Type__c = 'Borrower'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (borrowers.isEmpty()) {
            throw new AuraHandledException('Borrower applicant not found.');
        }
        return borrowers[0].Id;
    }

    private static Id resolveApplicationLineItemId(
        String applicationId,
        String applicantId,
        String applicationLineItemId
    ) {
        Id directId = parseId(applicationLineItemId);
        if (directId != null) {
            return directId;
        }
        if (String.isBlank(applicationId)) {
            return null;
        }
        Id appId = parseId(applicationId);
        if (appId == null) {
            return null;
        }
        return queryLineItemIdByApplication(appId);
    }

    private static Id queryLineItemIdByApplication(Id applicationId) {
        if (applicationId == null) {
            return null;
        }
        List<Application_Line_Item__c> rows = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static String appendStageCompleted(String currentStages, String stageName) {
        if (String.isBlank(stageName) || hasStageCompleted(currentStages, stageName)) {
            return currentStages;
        }
        String stage = stageName.trim();
        return String.isBlank(currentStages) ? stage : currentStages + ';' + stage;
    }

    private static Boolean hasStageCompleted(String completedStages, String stageName) {
        if (String.isBlank(completedStages) || String.isBlank(stageName)) {
            return false;
        }
        for (String stage : completedStages.split(';')) {
            if (stageName.equalsIgnoreCase(stage.trim())) {
                return true;
            }
        }
        return false;
    }
}