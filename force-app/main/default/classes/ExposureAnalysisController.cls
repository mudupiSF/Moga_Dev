/**
 * Callable controller for Exposure Analysis master page.
 * Actions: getExposureAnalysisData, saveExposureSummary
 */
public with sharing class ExposureAnalysisController implements Callable {

    private static final String ACTION_GET_EXPOSURE_ANALYSIS_DATA = 'getExposureAnalysisData';
    private static final String ACTION_SAVE_EXPOSURE_SUMMARY = 'saveExposureSummary';

    private static final Set<String> EXTERNAL_EXPOSURE_OBLIGATION_TYPES = new Set<String>{ 'External Exposure' };

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_GET_EXPOSURE_ANALYSIS_DATA.equalsIgnoreCase(action)) {
            return getExposureAnalysisDataInternal(safeArgs);
        }
        if (ACTION_SAVE_EXPOSURE_SUMMARY.equalsIgnoreCase(action)) {
            return saveExposureSummaryInternal(safeArgs);
        }

        return failure('Unknown action: ' + action);
    }

    private Map<String, Object> getExposureAnalysisDataInternal(Map<String, Object> args) {
        Id applicantId = resolveApplicantId(args);
        ApplicantContext applicantContext = loadApplicantContext(applicantId);
        return buildPagePayloadFromObligations(applicantId, applicantContext);
    }

    private static Map<String, Object> buildPagePayloadFromObligations(
        Id applicantId,
        ApplicantContext applicantContext
    ) {
        String applicantType = String.isNotBlank(applicantContext.applicantType)
            ? applicantContext.applicantType
            : 'Borrower';

        List<Map<String, Object>> exposures = new List<Map<String, Object>>();
        List<Map<String, Object>> externalExposures = new List<Map<String, Object>>();

        if (applicantId != null) {
            for (Applicant_Obligations__c obligation : queryApplicantObligations(applicantId)) {
                if (isExternalExposureObligation(obligation)) {
                    if (hasExternalExposureFieldsPopulated(obligation)) {
                        externalExposures.add(mapExternalExposureRow(obligation));
                    }
                } else if (hasBankExposureDealData(obligation)) {
                    exposures.add(mapExposureObligationRow(obligation));
                }
            }
        }

        Map<String, Decimal> calculatedSummary = computeSummaryFromObligations(
            exposures,
            externalExposures
        );
        Map<String, Decimal> displaySummary = resolveSummaryDisplayValues(
            applicantContext,
            calculatedSummary
        );

        return new Map<String, Object>{
            'isSuccess' => true,
            'applicantType' => applicantType,
            'exposures' => exposures,
            'externalExposures' => externalExposures,
            'currentExposure' => displaySummary.get('currentExposure'),
            'existingBorrowerExposure' => calculatedSummary.get('existingBorrowerExposure'),
            'existingGuarantorExposure' => calculatedSummary.get('existingGuarantorExposure'),
            'totalExposure' => displaySummary.get('totalExposure'),
            'foirPercent' => 0
        };
    }

    private static List<Applicant_Obligations__c> queryApplicantObligations(Id applicantId) {
        return [
            SELECT Id,
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
                Current_Demand__c,
                Account_Type__c,
                Account_Type_Desc__c,
                Ownership__c,
                High_Credit__c,
                Current_Balance__c,
                Amount_Overdue__c,
                Reason_for_Overdue__c,
                Financier_Name__c,
                Lien_No__c,
                Lien_Type__c,
                Source_Deal_No__c,
                Lien_Marking_Period__c,
                Lien_Maker_Date__c,
                Lien_Request_By__c,
                Lien_Marking_Reason__c
            FROM Applicant_Obligations__c
            WHERE Applicant__c = :applicantId
            WITH SECURITY_ENFORCED
            ORDER BY Type__c ASC, Deal_No__c ASC NULLS LAST, CreatedDate ASC
        ];
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

    private static Map<String, Object> mapExposureObligationRow(Applicant_Obligations__c obligation) {
        Boolean hasLien = hasLienFieldsPopulated(obligation);
        Map<String, Object> row = new Map<String, Object>{
            'id' => obligation.Id,
            'obligationType' => obligation.Type__c,
            'exposureType' => obligation.Exposure_Type__c,
            'dealStage' => obligation.Deal_Stage__c,
            'dealNo' => obligation.Deal_No__c,
            'dealDate' => formatDealDate(obligation.Deal_Date__c),
            'product' => obligation.Type_of_Facility__c,
            'status' => obligation.Status_Flag__c,
            'financeAmt' => obligation.Finance_Amt__c,
            'soh' => obligation.SOH__c,
            'overDue' => obligation.Over_Due__c,
            'currentDemand' => obligation.Current_Demand__c,
            'hasLien' => hasLien
        };

        if (hasLien) {
            row.put('lien', mapObligationToLienRow(obligation));
        }

        return row;
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

    private static Map<String, Object> mapExternalExposureRow(Applicant_Obligations__c obligation) {
        String accountTypeDisplay = String.isNotBlank(obligation.Account_Type_Desc__c)
            ? obligation.Account_Type_Desc__c
            : obligation.Account_Type__c;

        return new Map<String, Object>{
            'id' => obligation.Id,
            'accountType' => accountTypeDisplay,
            'ownership' => obligation.Ownership__c,
            'highCredit' => obligation.High_Credit__c,
            'currentBalance' => obligation.Current_Balance__c,
            'amountOverdue' => obligation.Amount_Overdue__c,
            'reasonForOverdue' => obligation.Reason_for_Overdue__c,
            'financierName' => obligation.Financier_Name__c
        };
    }

    private static String formatDealDate(Datetime dealDate) {
        if (dealDate == null) {
            return '';
        }
        return dealDate.format('yyyy-MM-dd');
    }

    /**
     * Current exposure: Application__c.Total_Loan_Amount__c when populated, else sum from obligations.
     * Total exposure: current + existing borrower + guarantor (stored total used only when it matches).
     */
    private static Map<String, Decimal> resolveSummaryDisplayValues(
        ApplicantContext applicantContext,
        Map<String, Decimal> calculatedSummary
    ) {
        Decimal calculatedCurrent = calculatedSummary.get('currentExposure');
        Decimal existingBorrowerExposure = calculatedSummary.get('existingBorrowerExposure');
        Decimal existingGuarantorExposure = calculatedSummary.get('existingGuarantorExposure');

        Decimal currentExposure = applicantContext.totalLoanAmount != null
            ? applicantContext.totalLoanAmount
            : calculatedCurrent;

        Decimal computedTotal = currentExposure
            + existingBorrowerExposure
            + existingGuarantorExposure;

        Decimal totalExposure = resolveStoredOrCalculatedTotal(
            applicantContext.storedTotalExposure,
            computedTotal
        );

        return new Map<String, Decimal>{
            'currentExposure' => currentExposure,
            'totalExposure' => totalExposure
        };
    }

    private static Decimal resolveStoredOrCalculatedTotal(Decimal storedTotal, Decimal calculatedTotal) {
        if (storedTotal == null) {
            return calculatedTotal;
        }
        if (storedTotal != calculatedTotal) {
            return calculatedTotal;
        }
        return storedTotal;
    }

    private Map<String, Object> saveExposureSummaryInternal(Map<String, Object> args) {
        Id applicantId = resolveApplicantId(args);
        if (applicantId == null) {
            return failure('Applicant Id is required.');
        }

        Decimal totalExposure = toDecimal(args.get('totalExposure'));
        if (totalExposure == null) {
            return failure('Total exposure is required.');
        }

        try {
            Applicant__c applicant = new Applicant__c(
                Id = applicantId,
                Total_Exposure__c = totalExposure
            );

            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<Applicant__c>{ applicant }
            );
            update decision.getRecords();

            return success('Exposure summary saved successfully.');
        } catch (Exception e) {
            return failure('Unable to save exposure summary: ' + e.getMessage());
        }
    }

    private static Map<String, Decimal> computeSummaryFromObligations(
        List<Map<String, Object>> exposures,
        List<Map<String, Object>> externalExposures
    ) {
        Decimal currentExposure = 0;
        Decimal existingBorrowerExposure = 0;
        Decimal existingGuarantorExposure = 0;

        for (Map<String, Object> row : exposures) {
            Decimal soh = toDecimal(row.get('soh'));
            String exposureType = String.valueOf(row.get('exposureType'));

            if ('Current'.equalsIgnoreCase(exposureType)) {
                currentExposure += soh;
                continue;
            }

            if (isGuarantorExposureRow(row)) {
                existingGuarantorExposure += soh;
            } else {
                existingBorrowerExposure += soh;
            }
        }

        for (Map<String, Object> row : externalExposures) {
            existingBorrowerExposure += toDecimal(row.get('currentBalance'));
        }

        Decimal totalExposure = currentExposure
            + existingBorrowerExposure
            + existingGuarantorExposure;

        return new Map<String, Decimal>{
            'currentExposure' => currentExposure,
            'existingBorrowerExposure' => existingBorrowerExposure,
            'existingGuarantorExposure' => existingGuarantorExposure,
            'totalExposure' => totalExposure
        };
    }

    private static Boolean isGuarantorExposureRow(Map<String, Object> row) {
        return row != null && 'Guarantor Exposure'.equalsIgnoreCase(
            String.valueOf(row.get('obligationType'))
        );
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return 0;
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
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return 0;
        }
    }

    private static Map<String, Object> mapObligationToLienRow(Applicant_Obligations__c obligation) {
        return new Map<String, Object>{
            'id' => obligation.Id,
            'lienNo' => obligation.Lien_No__c,
            'lienType' => obligation.Lien_Type__c,
            'sourceDealNo' => obligation.Source_Deal_No__c,
            'lienMarkingPeriod' => formatLienDate(obligation.Lien_Marking_Period__c),
            'lienMakerDate' => formatLienDate(obligation.Lien_Maker_Date__c),
            'lienRequestBy' => obligation.Lien_Request_By__c,
            'lienMarkingReason' => obligation.Lien_Marking_Reason__c
        };
    }

    private static String formatLienDate(Date value) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value);
    }

    private class ApplicantContext {
        public String applicantType { get; set; }
        public Decimal totalLoanAmount { get; set; }
        public Decimal storedTotalExposure { get; set; }
    }

    private static ApplicantContext loadApplicantContext(Id applicantId) {
        ApplicantContext ctx = new ApplicantContext();

        if (applicantId == null) {
            return ctx;
        }

        try {
            List<Applicant__c> applicants = [
                SELECT Id,
                    Applicant_Type__c,
                    Total_Exposure__c,
                    Application__r.Total_Loan_Amount__c
                FROM Applicant__c
                WHERE Id = :applicantId
                AND In_Active_Applicant__c = false
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (!applicants.isEmpty()) {
                Applicant__c applicant = applicants[0];
                ctx.applicantType = applicant.Applicant_Type__c;
                ctx.storedTotalExposure = applicant.Total_Exposure__c;
                ctx.totalLoanAmount = applicant.Application__r.Total_Loan_Amount__c;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'ExposureAnalysisController.loadApplicantContext: ' + e.getMessage());
        }

        return ctx;
    }

    private static Id resolveApplicantId(Map<String, Object> args) {
        return toId(args.get('applicantId'));
    }

    private static String resolveStringArg(Map<String, Object> args, String key) {
        if (args == null || !args.containsKey(key) || args.get(key) == null) {
            return '';
        }
        return String.valueOf(args.get(key)).trim();
    }

    private static Id toId(Object value) {
        if (value == null) {
            return null;
        }
        String s = String.valueOf(value).trim();
        return String.isBlank(s) ? null : (Id) s;
    }

    private static Map<String, Object> success(String message) {
        return new Map<String, Object>{
            'isSuccess' => true,
            'message' => message
        };
    }

    private static Map<String, Object> failure(String message) {
        return new Map<String, Object>{
            'isSuccess' => false,
            'message' => message
        };
    }
}