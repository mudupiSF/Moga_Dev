/**
 * @description Enhanced Loan Repayment Helper with support for:
 *              - Equated EMI (Equal Installments)
 *              - Equated Principal (Equal Principal, Varying Interest)
 *              - Equated Interest (Equal Interest, Varying Principal)
 *              - Moratorium Period (Education Loans)
 *              - Moratorium Interest Payment Options
 * @author      Salesforce Development Team
 * @date        2025
 */
public class RPSV2Helper {
    
    /**
     * @description Enhanced EMI Repayment Schedule with multiple repayment types and moratorium support
     * @param principal - Loan amount
     * @param irr - Interest rate (annual percentage)
     * @param loanDate - Loan sanction date
     * @param tenure - Loan tenure in months
     * @param day - Day of month for EMI deduction (5, 10, etc.)
     * @param frequency - Payment frequency (1=Monthly, 3=Quarterly, etc.)
     * @param repaymentDate - First installment date

     * @param repaymentType - Type of repayment: 'EQUATED_EMI', 'EQUATED_PRINCIPAL', 'EQUATED_INTEREST'
     * @param moratoriumMonths - Number of months for moratorium period (0 if no moratorium)
     * @param moratoriumInterestPayment - How to handle interest during moratorium:
     *                                     'NO_PAYMENT' - No payment, full interest capitalizes
     *                                     'PARTIAL_INTEREST' - Pay partial interest, rest capitalizes
     *                                     'INTEREST_ONLY' - Pay full interest during moratorium
     *                                     'CAPITALIZE' - Same as NO_PAYMENT (for backward compatibility)
     * @param moratoriumPartialAmount - Amount to pay during moratorium (for PARTIAL_INTEREST option)
     *                                   If null or 0, treated as NO_PAYMENT
     * @param daysInYearMethod - Method to calculate days in year:
     *                           'ACTUAL' or null - Use actual leap year detection (366 for leap years, 365 for others)
     *                           '360' - Always use 360 days (30/360 day count convention)
     *                           '365' - Always use 365 days
     *                           '366' - Always use 366 days
     * @param daysInMonthMethod - Method to calculate days in month:
     *                            'ACTUAL' or null - Use actual days in month (28/29 for Feb, 30/31 for others)
     *                            '30' - Always use 30 days per month
     *                            '31' - Always use 31 days per month
     * @return List<RepaymentWrapper> - Repayment schedule
     */
    public static List<RepaymentWrapper> emiRepaymentScheduleHlEnhanced(
        Integer principal, 
        String irr, 
        Date loanDate, 
        Integer tenure, 
        Integer day, 
        String frequency, 
        Date repaymentDate,
        String repaymentType,
        Integer moratoriumMonths,
        String moratoriumInterestPayment,
        Integer moratoriumPartialAmount,
        String calculationMode,
        String daysInYearMethod,
        String daysInMonthMethod,
        String preEmiType,
        Integer preEmiMonths,
        Date preEmiStartDate,
        Date preEmiEndDate,
        String capitalizationType,
        Boolean overrideProrateInterest
    ) {
        return emiRepaymentScheduleHlEnhanced(
            principal, irr, loanDate, tenure, day, frequency, repaymentDate,
            repaymentType, moratoriumMonths, moratoriumInterestPayment, moratoriumPartialAmount,
            calculationMode, daysInYearMethod, daysInMonthMethod,
            preEmiType, preEmiMonths, preEmiStartDate, preEmiEndDate,
            capitalizationType, overrideProrateInterest,
            false, false, false
        );
    }
    
    @AuraEnabled
    public static List<RepaymentWrapper> emiRepaymentScheduleHlEnhanced(
        Integer principal, 
        String irr, 
        Date loanDate, 
        Integer tenure, 
        Integer day, 
        String frequency, 
        Date repaymentDate,
        String repaymentType,
        Integer moratoriumMonths,
        String moratoriumInterestPayment,
        Integer moratoriumPartialAmount,
        String calculationMode,
        String daysInYearMethod,
        String daysInMonthMethod,
        String preEmiType,
        Integer preEmiMonths,
        Date preEmiStartDate,
        Date preEmiEndDate,
        String capitalizationType,
        Boolean overrideProrateInterest,
        Boolean accurateInterest,
        Boolean firstMonthPreEmi30days,
        Boolean treatFirstMonthAsPreEmi
    ) {
        try { 
            // Validate inputs
            if (String.isBlank(repaymentType)) { 
                repaymentType = 'EQUATED_EMI'; // Default to equated EMI
            }
            if (moratoriumMonths == null) {    
                moratoriumMonths = 0;      
            }
            if (String.isBlank(moratoriumInterestPayment)) {
                moratoriumInterestPayment = 'NO_PAYMENT'; // Default behavior
            }
            if (moratoriumPartialAmount == null) {
                moratoriumPartialAmount = 0;
            }
            
            // Handle Calculation Mode - overrides individual day settings
            if (String.isBlank(calculationMode)) {
                calculationMode = 'FLOATING'; // Default
            }
            if (calculationMode == 'FIXED') {
                daysInMonthMethod = '30';
                daysInYearMethod = '360';
            } else if (calculationMode == 'FLOATING') {
                daysInMonthMethod = 'ACTUAL';
                daysInYearMethod = '365';
            }
            
            if (String.isBlank(daysInYearMethod)) {
                daysInYearMethod = '365'; // Default to 365
            }
            if (String.isBlank(daysInMonthMethod)) {
                daysInMonthMethod = 'ACTUAL'; // Default to actual days in month
            }
            
            // Pre-EMI parameters
            if (String.isBlank(preEmiType)) {
                preEmiType = 'NONE';
            } 
            if (preEmiMonths == null) {
                preEmiMonths = 0;
            }
            if (String.isBlank(capitalizationType)) {
                capitalizationType = 'MONTHLY';
            }
            if (overrideProrateInterest == null) { 
                overrideProrateInterest = false;
            }
            if (accurateInterest == null) {
                accurateInterest = false;
            }
            if (firstMonthPreEmi30days == null) {
                firstMonthPreEmi30days = false;
            }
            if (treatFirstMonthAsPreEmi == null) {
                treatFirstMonthAsPreEmi = false;
            }
            
            Decimal interestCarryForward = 0;
            
            // Backward compatibility: CAPITALIZE is same as NO_PAYMENT
            if (moratoriumInterestPayment == 'CAPITALIZE') {
                moratoriumInterestPayment = 'NO_PAYMENT';
            }
            
            // Calculate pre-EMI days using appropriate day count convention
            Integer preEmiDays = calculateDaysBetween(loanDate, repaymentDate, daysInMonthMethod);
            List<RepaymentWrapper> lstCom = new List<RepaymentWrapper>();
            
            Decimal iRRInterest = Decimal.valueOf(irr);
            Integer frequencyInt = Integer.valueOf(frequency);
            Integer totalInstallments = tenure / frequencyInt;
            
            // Track principal for capitalization
            Integer workingPrincipal = principal;
            Integer originalPrincipal = principal;
            Date actualEmiStartDate = repaymentDate;
            
            // Handle override prorate: when enabled, use full month days for everything
            Integer actualFirstInstallmentDays = preEmiDays; // Actual days (respects calculation mode)
            Integer emiCalculationDays = preEmiDays; // Days to use for calculation (defaults to actual days)
            
            if (overrideProrateInterest && preEmiDays > 0 & preEmiDays < 30) {
                // When override is enabled, use full month days based on calculation mode
                if (daysInMonthMethod == 'ACTUAL') {
                    // ACTUAL mode: use actual days in the month
                    emiCalculationDays = Date.daysInMonth(repaymentDate.year(), repaymentDate.month());
                } else {
                    // Fixed mode (30/360): always 30 days
                    emiCalculationDays = 30;
                }
            }
            
            // Handle Simple Pre-EMI Period (user provides months directly)
            if (preEmiType == 'SIMPLE' && preEmiMonths > 0) {
                Date currentDate = loanDate;
                Date nextDueDate = repaymentDate;
                Integer installmentNum = 1;
                
                // Generate simple Pre-EMI schedule for specified months
                for (Integer i = 0; i < preEmiMonths; i++) {
                    Integer daysInYear = getDaysInYear(currentDate, daysInYearMethod);
                    Integer daysForPeriod;
                    
                    // Calculate days between current date and next due date
                    if (daysInMonthMethod == 'ACTUAL') {
                        // For actual mode, use daysBetween
                        daysForPeriod = currentDate.daysBetween(nextDueDate);
                    } else {
                        // For fixed mode (30/360), use calculateDaysBetween
                        daysForPeriod = calculateDaysBetween(currentDate, nextDueDate, daysInMonthMethod);
                    }
                    
                    Decimal interestCalc = (iRRInterest * workingPrincipal * daysForPeriod) / (daysInYear * 100);
                    
                    RepaymentWrapper preEmiInstallment = new RepaymentWrapper();
                    Decimal[] carryRef = new Decimal[]{ interestCarryForward };
                    applyInterestWithCarry(preEmiInstallment, interestCalc, carryRef, accurateInterest);
                    interestCarryForward = carryRef[0];
                    
                    preEmiInstallment.instalmentNo = installmentNum++;
                    preEmiInstallment.dueDate = nextDueDate;
                    preEmiInstallment.openingPrinciple2 = workingPrincipal;
                    preEmiInstallment.principalComp = 0;
                    preEmiInstallment.instalmentAmount = String.valueOf(preEmiInstallment.interestComp);
                    preEmiInstallment.closingPrinciple = workingPrincipal;
                    preEmiInstallment.irr = iRRInterest;
                    preEmiInstallment.days = daysForPeriod;
                    preEmiInstallment.principalDays = 0;
                    preEmiInstallment.emiDenominator = firstMonthPreEmi30days 
                        ? Date.daysInMonth(nextDueDate.year(), nextDueDate.month()) 
                        : getDaysInMonth(currentDate, daysInMonthMethod);
                    
                    lstCom.add(preEmiInstallment);
                    
                    // Move to next period
                    currentDate = nextDueDate;
                    nextDueDate = currentDate.addMonths(frequencyInt);
                }
                
                // Set the actual EMI start date to the next month after last pre-EMI due date
                // currentDate now holds the last pre-EMI due date (e.g., Sep 10, 2026)
                // Regular EMI should start one month after that (e.g., Oct 10, 2026)
                actualEmiStartDate = currentDate.addMonths(frequencyInt);
            }
            // Handle Under Construction / Pre-EMI Period (date-based)
            else if (preEmiType == 'CUSTOM' && preEmiStartDate != null && preEmiEndDate != null) {
                Date currentDate = preEmiStartDate;
                Integer installmentNum = 1;
                
                // First check if first month is partial
                Date monthEndDate = Date.newInstance(preEmiStartDate.year(), preEmiStartDate.month(), 
                    Date.daysInMonth(preEmiStartDate.year(), preEmiStartDate.month()));
                Integer firstMonthDays = calculateDaysBetween(preEmiStartDate, monthEndDate, daysInMonthMethod);
                
                // If first period is less than a full month, create prorated first installment
                if (firstMonthDays < getDaysInMonth(preEmiStartDate, daysInMonthMethod) && !overrideProrateInterest) {
                    Integer daysInYear = getDaysInYear(preEmiStartDate, daysInYearMethod);
                    Decimal proratedInterestCalc = (iRRInterest * workingPrincipal * firstMonthDays) / (daysInYear * 100);
                    
                    RepaymentWrapper preEmiFirst = new RepaymentWrapper();
                    Decimal[] carryRef = new Decimal[]{ interestCarryForward };
                    applyInterestWithCarry(preEmiFirst, proratedInterestCalc, carryRef, accurateInterest);
                    interestCarryForward = carryRef[0];
                    
                    preEmiFirst.instalmentNo = installmentNum++;
                    Date nextMonth = preEmiStartDate.addMonths(1);
                    Integer daysInNextMonth = Date.daysInMonth(nextMonth.year(), nextMonth.month());
                    Integer targetDay = day < daysInNextMonth ? day : daysInNextMonth;
                    preEmiFirst.dueDate = Date.newInstance(nextMonth.year(), nextMonth.month(), targetDay);
                    preEmiFirst.openingPrinciple2 = workingPrincipal;
                    preEmiFirst.principalComp = 0;
                    preEmiFirst.instalmentAmount = String.valueOf(preEmiFirst.interestComp);
                    preEmiFirst.closingPrinciple = workingPrincipal;
                    preEmiFirst.irr = iRRInterest;
                    preEmiFirst.days = firstMonthDays;
                    preEmiFirst.emiDenominator = firstMonthPreEmi30days 
                        ? Date.daysInMonth(preEmiStartDate.year(), preEmiStartDate.month()) 
                        : getDaysInMonth(preEmiStartDate, daysInMonthMethod);
                    lstCom.add(preEmiFirst);
                    
                    currentDate = preEmiFirst.dueDate;
                }
                
                // Generate full Pre-EMI installments (Interest Only)
                while (currentDate < preEmiEndDate) {
                    Integer daysInMonth = getDaysInMonth(currentDate, daysInMonthMethod);
                    Integer daysInYear = getDaysInYear(currentDate, daysInYearMethod);
                    Decimal monthlyInterestCalc = (iRRInterest * workingPrincipal * daysInMonth) / (daysInYear * 100);
                    
                    RepaymentWrapper preEmiInstallment = new RepaymentWrapper();
                    Decimal[] carryRef = new Decimal[]{ interestCarryForward };
                    applyInterestWithCarry(preEmiInstallment, monthlyInterestCalc, carryRef, accurateInterest);
                    interestCarryForward = carryRef[0];
                    
                    preEmiInstallment.instalmentNo = installmentNum++;
                    Date nextPaymentMonth = currentDate.addMonths(frequencyInt);
                    Integer daysInPaymentMonth = Date.daysInMonth(nextPaymentMonth.year(), nextPaymentMonth.month());
                    Integer targetDay = day < daysInPaymentMonth ? day : daysInPaymentMonth;
                    preEmiInstallment.dueDate = Date.newInstance(nextPaymentMonth.year(), nextPaymentMonth.month(), targetDay);
                    if (preEmiInstallment.dueDate > preEmiEndDate) {
                        preEmiInstallment.dueDate = preEmiEndDate;
                    }
                    preEmiInstallment.openingPrinciple2 = workingPrincipal;
                    preEmiInstallment.principalComp = 0;
                    preEmiInstallment.instalmentAmount = String.valueOf(preEmiInstallment.interestComp);
                    preEmiInstallment.closingPrinciple = workingPrincipal;
                    preEmiInstallment.irr = iRRInterest;
                    preEmiInstallment.days = daysInMonth;
                    preEmiInstallment.emiDenominator = firstMonthPreEmi30days 
                        ? Date.daysInMonth(currentDate.year(), currentDate.month()) 
                        : daysInMonth;
                    // Note: This is a Pre-EMI installment (Interest Only)
                    lstCom.add(preEmiInstallment);
                    
                    currentDate = preEmiInstallment.dueDate;
                }
                
                // Set the actual EMI start date after Pre-EMI period
                actualEmiStartDate = preEmiEndDate;
            }
            // Handle simple prorated first EMI (< 30 days between loan and first EMI)
            else if (preEmiDays > 0 && preEmiDays < 30 && !overrideProrateInterest) {
                Decimal proratedInterestCalc;
                Integer daysForDisplay;
                
                if (firstMonthPreEmi30days) {
                    // Use actual days in disbursement month for proration instead of 30-day convention
                    // Customer pays for the disbursement month (e.g., Jan 20→Feb 5 = paying for January)
                    // Formula: (P × R / 12 / 100) × (actualDays / actualDaysInMonth)
                    Integer actualDaysInMonth = Date.daysInMonth(loanDate.year(), loanDate.month());
                    Integer actualDays = loanDate.daysBetween(repaymentDate);
                    proratedInterestCalc = (iRRInterest * workingPrincipal * actualDays) / (Decimal.valueOf(actualDaysInMonth) * 12 * 100);
                    daysForDisplay = actualDays;
                } else {
                    // Standard: use 30-day convention days and daysInYear (360 for Fixed)
                    Integer daysInYear = getDaysInYear(loanDate, daysInYearMethod);
                    proratedInterestCalc = (iRRInterest * workingPrincipal * preEmiDays) / (daysInYear * 100);
                    daysForDisplay = preEmiDays;
                }
                
                RepaymentWrapper proratedEmi = new RepaymentWrapper();
                Decimal[] carryRef = new Decimal[]{ interestCarryForward };
                applyInterestWithCarry(proratedEmi, proratedInterestCalc, carryRef, accurateInterest);
                interestCarryForward = carryRef[0];
                
                proratedEmi.instalmentNo = 1;
                proratedEmi.dueDate = repaymentDate;
                proratedEmi.openingPrinciple2 = workingPrincipal;
                proratedEmi.principalComp = 0;
                proratedEmi.instalmentAmount = String.valueOf(proratedEmi.interestComp);
                proratedEmi.closingPrinciple = workingPrincipal;
                proratedEmi.irr = iRRInterest;
                proratedEmi.days = daysForDisplay;
                proratedEmi.principalDays = 0;
                proratedEmi.emiDenominator = firstMonthPreEmi30days 
                    ? Date.daysInMonth(loanDate.year(), loanDate.month()) 
                    : getDaysInMonth(loanDate, daysInMonthMethod);
                // Note: This is a prorated first EMI (interest only)
                lstCom.add(proratedEmi);
                
                actualEmiStartDate = repaymentDate.addMonths(frequencyInt);
            }
            // Treat first month as Pre-EMI irrespective of days difference
            else if (treatFirstMonthAsPreEmi && preEmiDays > 0) {
                Integer daysInYear = getDaysInYear(loanDate, daysInYearMethod);
                Decimal preEmiInterestCalc;
                Integer daysForDisplay;
                
                if (firstMonthPreEmi30days) {
                    Integer actualDaysInMonth = Date.daysInMonth(loanDate.year(), loanDate.month());
                    Integer actualDays = loanDate.daysBetween(repaymentDate);
                    preEmiInterestCalc = (iRRInterest * workingPrincipal * actualDays) / (Decimal.valueOf(actualDaysInMonth) * 12 * 100);
                    daysForDisplay = actualDays;
                } else {
                    preEmiInterestCalc = (iRRInterest * workingPrincipal * preEmiDays) / (daysInYear * 100);
                    daysForDisplay = preEmiDays;
                }
                
                RepaymentWrapper preEmiInstallment = new RepaymentWrapper();
                Decimal[] carryRef = new Decimal[]{ interestCarryForward };
                applyInterestWithCarry(preEmiInstallment, preEmiInterestCalc, carryRef, accurateInterest);
                interestCarryForward = carryRef[0];
                
                preEmiInstallment.instalmentNo = 1;
                preEmiInstallment.dueDate = repaymentDate;
                preEmiInstallment.openingPrinciple2 = workingPrincipal;
                preEmiInstallment.principalComp = 0;
                preEmiInstallment.instalmentAmount = String.valueOf(preEmiInstallment.interestComp);
                preEmiInstallment.closingPrinciple = workingPrincipal;
                preEmiInstallment.irr = iRRInterest;
                preEmiInstallment.days = daysForDisplay;
                preEmiInstallment.principalDays = 0;
                preEmiInstallment.interestCalculationDays = daysForDisplay;
                preEmiInstallment.emiDenominator = firstMonthPreEmi30days 
                    ? Date.daysInMonth(loanDate.year(), loanDate.month()) 
                    : getDaysInMonth(loanDate, daysInMonthMethod);
                lstCom.add(preEmiInstallment);
                
                actualEmiStartDate = repaymentDate.addMonths(frequencyInt);
            }
            // When disbursement day falls before EMI due day in the same month
            // (e.g., Disbursement May 15, Due day 20th, First EMI June 20)
            // The full period (May 15 to June 20) is handled as a single combined entry
            // in the first regular EMI with both interest and principal.
            
            // Update repayment date to actual EMI start date
            repaymentDate = actualEmiStartDate;
            
            // Calculate how many months of Pre-EMI were handled
            Integer preEmiMonthsProcessed = lstCom.size() * frequencyInt;
            
            // When firstMonthPreEmi30days is enabled and pre-EMI exists, force first regular EMI to 30 days
            Boolean forceFirstEmi30 = firstMonthPreEmi30days && lstCom.size() > 0;
            
            // Generate repayment schedule based on type
            if (repaymentType == 'EQUATED_EMI') {
                lstCom.addAll(generateEquatedEMISchedule(
                    workingPrincipal, 
                    iRRInterest, 
                    tenure, 
                    frequencyInt, 
                    repaymentDate,
                    moratoriumMonths,
                    moratoriumInterestPayment,
                    moratoriumPartialAmount,
                    lstCom.size(),
                    daysInYearMethod,
                    daysInMonthMethod,
                    capitalizationType,
                    actualFirstInstallmentDays,
                    loanDate,
                    emiCalculationDays,
                    accurateInterest,
                    interestCarryForward,
                    forceFirstEmi30
                ));
            } else if (repaymentType == 'EQUATED_PRINCIPAL') {
                lstCom.addAll(generateEquatedPrincipalSchedule(
                    workingPrincipal, 
                    iRRInterest, 
                    tenure, 
                    frequencyInt, 
                    repaymentDate,
                    moratoriumMonths,
                    moratoriumInterestPayment,
                    moratoriumPartialAmount,
                    lstCom.size(),
                    daysInYearMethod,
                    daysInMonthMethod,
                    capitalizationType,
                    actualFirstInstallmentDays,
                    loanDate,
                    emiCalculationDays,
                    accurateInterest,
                    interestCarryForward,
                    forceFirstEmi30
                ));
            } else if (repaymentType == 'EQUATED_INTEREST') {
                lstCom.addAll(generateEquatedInterestSchedule(
                    workingPrincipal, 
                    iRRInterest, 
                    tenure, 
                    frequencyInt, 
                    repaymentDate,
                    moratoriumMonths,
                    moratoriumInterestPayment,
                    moratoriumPartialAmount,
                    lstCom.size(),
                    daysInYearMethod,
                    daysInMonthMethod,
                    capitalizationType,
                    accurateInterest,
                    interestCarryForward,
                    forceFirstEmi30
                ));
            }
            
            return lstCom;
        } catch (Exception e) {
            throw new AuraHandledException('Error generating repayment schedule: ' + e.getMessage());
        }
    }
    
    /**
     * @description Generate Equated EMI Schedule (Equal Installments)
     * This is the standard EMI calculation where each installment is equal
     */
    private static List<RepaymentWrapper> generateEquatedEMISchedule(
        Integer principal,
        Decimal iRRInterest,
        Integer tenure,
        Integer frequency,
        Date repaymentDate,
        Integer moratoriumMonths,
        String moratoriumInterestPayment,
        Integer moratoriumPartialAmount,
        Integer startingInstallmentNo,
        String daysInYearMethod,
        String daysInMonthMethod,
        String capitalizationType,
        Integer firstInstallmentDays,
        Date loanDate,
        Integer emiCalculationDays,
        Boolean accurateInterest,
        Decimal initialCarryForward,
        Boolean forceFirstEmi30
    ) {
        List<RepaymentWrapper> schedule = new List<RepaymentWrapper>();
        Integer workingPrincipal = principal;
        Decimal[] carryRef = new Decimal[]{ initialCarryForward != null ? initialCarryForward : 0 };
        Integer totalInstallments = tenure / frequency;
        Integer moratoriumInstallments = moratoriumMonths / frequency;
        Integer secondLastClosingBalance = 0;
        
        // Calculate effective tenure after moratorium
        Integer effectiveTenure = tenure - moratoriumMonths;
        Integer effectiveInstallments = effectiveTenure / frequency;
        
        // Handle moratorium period with proper capitalization frequency
        Integer accumulatedInterest = 0; // Track accumulated unpaid interest
        
        if (moratoriumInstallments > 0) {
            for (Integer i = 0; i < moratoriumInstallments; i++) {
                RepaymentWrapper ap = new RepaymentWrapper();
                Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
                
                // Calculate days for this moratorium installment
                Integer daysForInterestCalc; // Days to use for interest calculation (ALWAYS actual days)
                if (i == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0) {
                    // IMPORTANT: Interest should ALWAYS be calculated for actual days
                    // Display days: Show full month when override enabled, actual days when disabled
                    // During moratorium, ALL goes to interest - NO principal payment ever
                    if (emiCalculationDays != null && emiCalculationDays != firstInstallmentDays) {
                        // OVERRIDE ENABLED: Display full month days, but interest uses actual days
                        ap.days = emiCalculationDays; // Display full month days (kept for backward compatibility)
                        daysForInterestCalc = firstInstallmentDays; // Interest ALWAYS uses actual days
                        ap.interestCalculationDays = firstInstallmentDays;
                        ap.fullEmiDays = emiCalculationDays; // Full EMI uses full month days
                    } else {
                        // OVERRIDE DISABLED: Display and interest both use actual days
                        ap.days = firstInstallmentDays;
                        daysForInterestCalc = firstInstallmentDays;
                        ap.interestCalculationDays = firstInstallmentDays;
                        ap.fullEmiDays = firstInstallmentDays; // Same as interest when no override
                    }
                } else if (daysInMonthMethod == 'ACTUAL') {
                    // ACTUAL mode: use actual days in the PREVIOUS month (the interest period)
                    Date previousMonth = repaymentDate.addMonths(-1);
                    ap.days = Date.daysInMonth(previousMonth.year(), previousMonth.month());
                    daysForInterestCalc = ap.days;
                    ap.interestCalculationDays = ap.days;
                    ap.fullEmiDays = ap.days; // Same as interest for regular installments
                } else {
                    // Fixed mode (30/360): always 30 days
                    ap.days = 30;
                    daysForInterestCalc = 30;
                    ap.interestCalculationDays = 30;
                    ap.fullEmiDays = 30; // Same as interest for regular installments
                }
                
                // IMPORTANT: Capture opening principal BEFORE any modifications
                ap.openingPrinciple2 = workingPrincipal;
                
                
                // Calculate interest on the current working principal (using appropriate days based on override)
                Decimal interest = (iRRInterest * workingPrincipal * daysForInterestCalc) / (daysInYear * 100);
                applyInterestWithCarry(ap, interest, carryRef, accurateInterest);
                
                
                if (moratoriumInterestPayment == 'INTEREST_ONLY') {
                    // Pay full interest only during moratorium - no capitalization
                    ap.instalmentAmount = String.valueOf(ap.interestComp);
                    ap.principalComp = 0;
                    ap.closingPrinciple = workingPrincipal; // No change to principal
                } else if (moratoriumInterestPayment == 'PARTIAL_INTEREST') {
                    // Pay partial interest - rest accumulates
                    ap.instalmentAmount = String.valueOf(moratoriumPartialAmount);
                    ap.principalComp = 0;
                    
                    // Calculate unpaid interest
                    Integer unpaidInterest = ap.interestComp - moratoriumPartialAmount;
                    if (unpaidInterest > 0) {
                        accumulatedInterest += unpaidInterest;
                    }
                    
                    
                    // Check if we should capitalize at this installment
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallments)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal; // Show capitalized principal
                        accumulatedInterest = 0; // Reset accumulated interest
                } else {
                        ap.closingPrinciple = workingPrincipal; // No change to principal yet
                    }
                } else {
                    // NO_PAYMENT - Full interest accumulates
                    ap.instalmentAmount = '0';
                    ap.principalComp = 0;
                    accumulatedInterest += ap.interestComp;
                    
                    // Check if we should capitalize at this installment
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallments)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal; // Show capitalized principal
                        accumulatedInterest = 0; // Reset accumulated interest
                    } else {
                        ap.closingPrinciple = workingPrincipal; // No change to principal yet
                    }
                }
                
                ap.irr = iRRInterest;
                ap.dueDate = repaymentDate;
                ap.instalmentNo = startingInstallmentNo + i + 1;
                ap.emiDenominator = ap.days;
                ap.principalDays = 0;
                
                schedule.add(ap);
                repaymentDate = repaymentDate.addMonths(frequency);
            }
        }
        
        // Calculate EMI for remaining tenure AFTER moratorium (using updated principal after capitalization)
        
        // Use Decimal for precision throughout, calculate power term with high precision
        // Round monthly rate to 8 decimal places for consistency with standard financial calculators
        Decimal monthlyRate = (iRRInterest / Decimal.valueOf(1200)).setScale(8, RoundingMode.HALF_UP);
        
        // Calculate (1+r)^n using Decimal for maximum precision
        Decimal onePlusRate = Decimal.valueOf(1) + monthlyRate;
        Decimal powerTerm = Decimal.valueOf(1);
        for (Integer p = 0; p < effectiveInstallments; p++) {
            powerTerm = powerTerm * onePlusRate;
        }
        
        // Use Decimal for numerator/denominator to maintain precision
        Decimal numerator = Decimal.valueOf(workingPrincipal) * monthlyRate * powerTerm;
        Decimal denominator = powerTerm - Decimal.valueOf(1);
        
        // Convert final EMI result to Decimal for precision
        Decimal emiAmount = numerator / denominator;
        
        // Use HALF_UP rounding (standard banking practice - rounds 0.5 and above up)
        Integer roundedEMI = Integer.valueOf(emiAmount.round(System.RoundingMode.HALF_UP));
        
        // Keep the unrounded EMI for precise principal calculation
        Decimal unroundedEMI = emiAmount;
        
        // Generate regular EMI schedule
        for (Integer i = 0; i < effectiveInstallments; i++) {
            RepaymentWrapper ap = new RepaymentWrapper();
            Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
            Boolean isFirstInstallment = (i == 0 && moratoriumInstallments == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0);
            
            // Calculate days for this installment
            Integer daysForInterestCalculation; // Days to use for interest calculation (ALWAYS actual days for first installment)
            Integer daysForFullEMI; // Days used for full EMI calculation
            if (isFirstInstallment) {
                // IMPORTANT: Interest should ALWAYS be calculated for actual days (respects calculation mode)
                // Display days: Show full month when override enabled, actual days when disabled
                // EMI amount: Uses full month when override enabled (calculated separately)
                if (emiCalculationDays != null && emiCalculationDays != firstInstallmentDays) {
                    // OVERRIDE ENABLED: Display full month days, but interest uses actual days
                    ap.days = emiCalculationDays; // Display full month days (kept for backward compatibility)
                    daysForInterestCalculation = firstInstallmentDays; // Interest ALWAYS uses actual days
                    daysForFullEMI = emiCalculationDays; // Full EMI uses full month days
                    ap.interestCalculationDays = firstInstallmentDays;
                    ap.fullEmiDays = emiCalculationDays;
                } else {
                    // OVERRIDE DISABLED: Display and interest both use actual days
                    ap.days = firstInstallmentDays;
                    daysForInterestCalculation = firstInstallmentDays;
                    daysForFullEMI = firstInstallmentDays; // Same as interest when no override
                    ap.interestCalculationDays = firstInstallmentDays;
                    ap.fullEmiDays = firstInstallmentDays;
                }
            } else if (daysInMonthMethod == 'ACTUAL') {
                // ACTUAL mode: use actual days in the PREVIOUS month (the interest period)
                Date previousMonth = repaymentDate.addMonths(-1);
                ap.days = Date.daysInMonth(previousMonth.year(), previousMonth.month());
                daysForInterestCalculation = ap.days;
                daysForFullEMI = ap.days; // Same as interest for regular installments
                ap.interestCalculationDays = ap.days;
                ap.fullEmiDays = ap.days;
            } else {
                // Fixed mode (30/360): always 30 days
                ap.days = 30;
                daysForInterestCalculation = 30;
                daysForFullEMI = 30; // Same as interest for regular installments
                ap.interestCalculationDays = 30;
                ap.fullEmiDays = 30;
            }
            
            // Calculate principal days for this installment
            if (isFirstInstallment && loanDate.day() < repaymentDate.day()) {
                Integer daysInLoanMonth = Date.daysInMonth(loanDate.year(), loanDate.month());
                Integer targetDay = Math.min(repaymentDate.day(), daysInLoanMonth);
                Date sameMonthDueDate = Date.newInstance(loanDate.year(), loanDate.month(), targetDay);
                if (sameMonthDueDate > loanDate && sameMonthDueDate < repaymentDate) {
                    if (daysInMonthMethod == 'ACTUAL') {
                        ap.principalDays = sameMonthDueDate.daysBetween(repaymentDate);
                    } else {
                        ap.principalDays = calculateDaysBetween(sameMonthDueDate, repaymentDate, daysInMonthMethod);
                    }
                } else {
                    ap.principalDays = daysForInterestCalculation;
                }
            } else {
                ap.principalDays = daysForInterestCalculation;
            }
            
            // Safeguard: If principal is already zero or negative, stop
            if (workingPrincipal <= 0) {
                break;
            }
            
            // Calculate and round interest for this month (using appropriate days based on override)
            Decimal interest = (iRRInterest * workingPrincipal * daysForInterestCalculation) / (daysInYear * 100);
            applyInterestWithCarry(ap, interest, carryRef, accurateInterest);
            
            // Determine installment EMI for this period
            Integer currentEmi = roundedEMI;
            ap.emiNumerator = emiAmount.setScale(4, RoundingMode.HALF_UP);
            ap.emiDenominator = daysForFullEMI;
            
            ap.instalmentAmount = String.valueOf(currentEmi);
            
            // Handle last installment - always close with exact remaining balance
            if (i == effectiveInstallments - 1) {
                ap.principalComp = workingPrincipal;
                ap.instalmentAmount = String.valueOf(ap.interestComp + ap.principalComp);
                ap.closingPrinciple = 0;
            } else {
                Integer calculatedPrincipal = currentEmi - ap.interestComp;
                
                if (calculatedPrincipal < 0) {
                    calculatedPrincipal = 0;
                }
                
                if (calculatedPrincipal >= workingPrincipal) {
                    Integer remainingInstallments = effectiveInstallments - i;
                    calculatedPrincipal = workingPrincipal / remainingInstallments;
                    if (calculatedPrincipal <= 0 && workingPrincipal > 0) {
                        calculatedPrincipal = 1;
                    }
                    ap.instalmentAmount = String.valueOf(ap.interestComp + calculatedPrincipal);
                }
                
                ap.principalComp = calculatedPrincipal;
                ap.closingPrinciple = workingPrincipal - ap.principalComp;
                
                if (i == effectiveInstallments - 2) {
                    secondLastClosingBalance = ap.closingPrinciple;
                }
            }
            
            ap.irr = iRRInterest;
            ap.dueDate = repaymentDate;
            ap.instalmentNo = startingInstallmentNo + moratoriumInstallments + i + 1;
            ap.openingPrinciple2 = workingPrincipal;
            
            workingPrincipal = ap.closingPrinciple;
            schedule.add(ap);
            
            repaymentDate = repaymentDate.addMonths(frequency);
        }
        
        return schedule;
    }
    
    /**
     * @description Generate Equated Principal Schedule (Equal Principal, Varying Interest)
     * Each installment pays the same principal amount, but interest varies based on outstanding balance
     */
    private static List<RepaymentWrapper> generateEquatedPrincipalSchedule(
        Integer principal,
        Decimal iRRInterest,
        Integer tenure,
        Integer frequency,
        Date repaymentDate,
        Integer moratoriumMonths,
        String moratoriumInterestPayment,
        Integer moratoriumPartialAmount,
        Integer startingInstallmentNo,
        String daysInYearMethod,
        String daysInMonthMethod,
        String capitalizationType,
        Integer firstInstallmentDays,
        Date loanDate,
        Integer emiCalculationDays,
        Boolean accurateInterest,
        Decimal initialCarryForward,
        Boolean forceFirstEmi30
    ) {
        List<RepaymentWrapper> schedule = new List<RepaymentWrapper>();
        Integer workingPrincipal = principal;
        Decimal[] carryRef = new Decimal[]{ initialCarryForward != null ? initialCarryForward : 0 };
        Integer moratoriumInstallments = moratoriumMonths / frequency;
        Integer effectiveTenure = tenure - moratoriumMonths;
        Integer effectiveInstallments = effectiveTenure / frequency;
        
        // Handle moratorium period with proper capitalization frequency
        Integer accumulatedInterest = 0; // Track accumulated unpaid interest
        
        if (moratoriumInstallments > 0) {
            for (Integer i = 0; i < moratoriumInstallments; i++) {
                RepaymentWrapper ap = new RepaymentWrapper();
                Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
                
                // Calculate days for this moratorium installment
                if (i == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0) {
                    // FIRST installment: use days from loan date to first EMI date
                    ap.days = firstInstallmentDays;
                    
                    // MORATORIUM OVERRIDE LOGIC: If override is enabled and days < 30
                    // Calculate interest for FULL MONTH (30 days), not actual days
                    // During moratorium, ALL goes to interest - NO principal payment ever
                    if (emiCalculationDays != null && emiCalculationDays != firstInstallmentDays) {
                        ap.days = emiCalculationDays; // Use full month days for interest calculation
                    }
                } else if (daysInMonthMethod == 'ACTUAL') {
                    // ACTUAL mode: use actual days in the PREVIOUS month (the interest period)
                    Date previousMonth = repaymentDate.addMonths(-1);
                    ap.days = Date.daysInMonth(previousMonth.year(), previousMonth.month());
                } else {
                    // Fixed mode (30/360): always 30 days
                    ap.days = 30;
                }
                
                // IMPORTANT: Capture opening principal BEFORE any modifications
                ap.openingPrinciple2 = workingPrincipal;
                
                
                // Calculate interest on the current working principal (includes previous capitalizations)
                Decimal interest = (iRRInterest * workingPrincipal * ap.days) / (daysInYear * 100);
                applyInterestWithCarry(ap, interest, carryRef, accurateInterest);
                
                
                if (moratoriumInterestPayment == 'INTEREST_ONLY') {
                    ap.instalmentAmount = String.valueOf(ap.interestComp);
                    ap.principalComp = 0;
                    ap.closingPrinciple = workingPrincipal;
                } else if (moratoriumInterestPayment == 'PARTIAL_INTEREST') {
                    ap.instalmentAmount = String.valueOf(moratoriumPartialAmount);
                    ap.principalComp = 0;
                    
                    Integer unpaidInterest = ap.interestComp - moratoriumPartialAmount;
                    if (unpaidInterest > 0) {
                        accumulatedInterest += unpaidInterest;
                    }
                    
                    
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallments)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal;
                        accumulatedInterest = 0;
                } else {
                        ap.closingPrinciple = workingPrincipal;
                    }
                } else {
                    ap.instalmentAmount = '0';
                    ap.principalComp = 0;
                    accumulatedInterest += ap.interestComp;
                    
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallments)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal;
                        accumulatedInterest = 0;
                    } else {
                        ap.closingPrinciple = workingPrincipal;
                    }
                }
                
                ap.irr = iRRInterest;
                ap.dueDate = repaymentDate;
                ap.instalmentNo = startingInstallmentNo + i + 1;
                ap.emiDenominator = ap.days;
                
                schedule.add(ap);
                repaymentDate = repaymentDate.addMonths(frequency);
            }
        }
        
        Integer equalPrincipal = workingPrincipal / effectiveInstallments;
        
        
        // Generate schedule with equal principal
        for (Integer i = 0; i < effectiveInstallments; i++) {
            RepaymentWrapper ap = new RepaymentWrapper();
            Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
            Boolean isFirstInstallment = (i == 0 && moratoriumInstallments == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0);
            
            // Calculate days for this installment
            Integer daysForInterestCalc; // Days to use for interest calculation (ALWAYS actual days for first installment)
            if (isFirstInstallment) {
                // IMPORTANT: Interest should ALWAYS be calculated for actual days (respects calculation mode)
                // Display days: Show full month when override enabled, actual days when disabled
                if (emiCalculationDays != null && emiCalculationDays != firstInstallmentDays) {
                    // OVERRIDE ENABLED: Display full month days, but interest uses actual days
                    ap.days = emiCalculationDays; // Display full month days (kept for backward compatibility)
                    daysForInterestCalc = firstInstallmentDays; // Interest ALWAYS uses actual days
                    ap.interestCalculationDays = firstInstallmentDays;
                    ap.fullEmiDays = emiCalculationDays; // Full EMI uses full month days
                } else {
                    // OVERRIDE DISABLED: Display and interest both use actual days
                    ap.days = firstInstallmentDays;
                    daysForInterestCalc = firstInstallmentDays;
                    ap.interestCalculationDays = firstInstallmentDays;
                    ap.fullEmiDays = firstInstallmentDays; // Same as interest when no override
                }
            } else if (daysInMonthMethod == 'ACTUAL') {
                // ACTUAL mode: use actual days in the PREVIOUS month (the interest period)
                Date previousMonth = repaymentDate.addMonths(-1);
                ap.days = Date.daysInMonth(previousMonth.year(), previousMonth.month());
                daysForInterestCalc = ap.days;
                ap.interestCalculationDays = ap.days;
                ap.fullEmiDays = ap.days; // Same as interest for regular installments
            } else {
                // Fixed mode (30/360): always 30 days
                ap.days = 30;
                daysForInterestCalc = 30;
                ap.interestCalculationDays = 30;
                ap.fullEmiDays = 30; // Same as interest for regular installments
            }
            
            // Calculate principal days for this installment
            if (isFirstInstallment && loanDate.day() < repaymentDate.day()) {
                Integer daysInLoanMonth = Date.daysInMonth(loanDate.year(), loanDate.month());
                Integer targetDay = Math.min(repaymentDate.day(), daysInLoanMonth);
                Date sameMonthDueDate = Date.newInstance(loanDate.year(), loanDate.month(), targetDay);
                if (sameMonthDueDate > loanDate && sameMonthDueDate < repaymentDate) {
                    if (daysInMonthMethod == 'ACTUAL') {
                        ap.principalDays = sameMonthDueDate.daysBetween(repaymentDate);
                    } else {
                        ap.principalDays = calculateDaysBetween(sameMonthDueDate, repaymentDate, daysInMonthMethod);
                    }
                } else {
                    ap.principalDays = daysForInterestCalc;
                }
            } else {
                ap.principalDays = daysForInterestCalc;
            }
            
            // Safeguard: If principal is already zero or negative, stop
            if (workingPrincipal <= 0) {
                break;
            }
            
            // Calculate interest using ACTUAL days (always for first installment)
            Decimal interest = (iRRInterest * workingPrincipal * daysForInterestCalc) / (daysInYear * 100);
            applyInterestWithCarry(ap, interest, carryRef, accurateInterest);
            
            // Handle first installment with override logic
            if (isFirstInstallment && emiCalculationDays != null && emiCalculationDays != firstInstallmentDays) {
                // OVERRIDE ENABLED: Fix principal first, then calculate payment amount
                // Principal = equalPrincipal (fixed)
                // Interest = calculated for actual days (already done above)
                // Payment Amount = Principal + Interest
                Integer calculatedPrincipal = equalPrincipal;
                
                // Ensure principal doesn't exceed remaining balance
                if (calculatedPrincipal > workingPrincipal) {
                    calculatedPrincipal = workingPrincipal;
                }
                
                ap.principalComp = calculatedPrincipal;
                ap.closingPrinciple = workingPrincipal - ap.principalComp;
                ap.instalmentAmount = String.valueOf(ap.principalComp + ap.interestComp);
            } else if (isFirstInstallment && (emiCalculationDays == null || emiCalculationDays == firstInstallmentDays)) {
                // OVERRIDE DISABLED: Prorated EMI (interest only, principal = 0)
                ap.principalComp = 0;
                ap.closingPrinciple = workingPrincipal; // No principal payment
                ap.instalmentAmount = String.valueOf(ap.interestComp);
                
            } else {
                // Regular installments: Only the actual last installment closes out remaining balance
                if (i == effectiveInstallments - 1) {
                    ap.principalComp = workingPrincipal;
                    ap.closingPrinciple = 0;
                } else {
                    Integer principalForThisInstallment = equalPrincipal;
                    
                    // If paying full equalPrincipal would wipe out the balance before the last installment,
                    // redistribute remaining principal across remaining installments
                    if (principalForThisInstallment >= workingPrincipal) {
                        Integer remainingInstallments = effectiveInstallments - i;
                        principalForThisInstallment = workingPrincipal / remainingInstallments;
                        if (principalForThisInstallment <= 0 && workingPrincipal > 0) {
                            principalForThisInstallment = 1;
                        }
                    }
                    
                    ap.principalComp = principalForThisInstallment;
                    ap.closingPrinciple = workingPrincipal - ap.principalComp;
                }
                
                ap.instalmentAmount = String.valueOf(ap.principalComp + ap.interestComp);
            }
            ap.irr = iRRInterest;
            ap.dueDate = repaymentDate;
            ap.instalmentNo = startingInstallmentNo + moratoriumInstallments + i + 1;
            ap.openingPrinciple2 = workingPrincipal;
            ap.emiDenominator = ap.days;
            
            workingPrincipal = ap.closingPrinciple;
            schedule.add(ap);
            
            repaymentDate = repaymentDate.addMonths(frequency);
        }
        
        return schedule;
    }
    
    /**
     * @description Generate Equated Interest Schedule (Equal Interest, Varying Principal)
     * Each installment pays the same interest amount, principal varies
     * Note: This is less common and may not fully amortize the loan
     */
    private static List<RepaymentWrapper> generateEquatedInterestSchedule(
        Integer principal,
        Decimal iRRInterest,
        Integer tenure,
        Integer frequency,
        Date repaymentDate,
        Integer moratoriumMonths,
        String moratoriumInterestPayment,
        Integer moratoriumPartialAmount,
        Integer startingInstallmentNo,
        String daysInYearMethod,
        String daysInMonthMethod,
        String capitalizationType,
        Boolean accurateInterest,
        Decimal initialCarryForward,
        Boolean forceFirstEmi30
    ) {
        List<RepaymentWrapper> schedule = new List<RepaymentWrapper>();
        Integer workingPrincipal = principal;
        Decimal[] carryRef = new Decimal[]{ initialCarryForward != null ? initialCarryForward : 0 };
        Integer moratoriumInstallments = moratoriumMonths / frequency;
        Integer effectiveTenure = tenure - moratoriumMonths;
        Integer effectiveInstallments = effectiveTenure / frequency;
        
        // Handle moratorium period with proper capitalization frequency
        Integer accumulatedInterest = 0; // Track accumulated unpaid interest
        
        if (moratoriumInstallments > 0) {
            for (Integer i = 0; i < moratoriumInstallments; i++) {
                RepaymentWrapper ap = new RepaymentWrapper();
                Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
                ap.days = getDaysInMonth(repaymentDate, daysInMonthMethod);
                
                // IMPORTANT: Capture opening principal BEFORE any modifications
                ap.openingPrinciple2 = workingPrincipal;
                
                
                Decimal interest = (iRRInterest * workingPrincipal * ap.days) / (daysInYear * 100);
                applyInterestWithCarry(ap, interest, carryRef, accurateInterest);
                
                
                if (moratoriumInterestPayment == 'INTEREST_ONLY') {
                    ap.instalmentAmount = String.valueOf(ap.interestComp);
                    ap.principalComp = 0;
                    ap.closingPrinciple = workingPrincipal;
                } else if (moratoriumInterestPayment == 'PARTIAL_INTEREST') {
                    ap.instalmentAmount = String.valueOf(moratoriumPartialAmount);
                    ap.principalComp = 0;
                    
                    Integer unpaidInterest = ap.interestComp - moratoriumPartialAmount;
                    if (unpaidInterest > 0) {
                        accumulatedInterest += unpaidInterest;
                    }
                    
                    
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallments)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal;
                        accumulatedInterest = 0;
                } else {
                        ap.closingPrinciple = workingPrincipal;
                    }
                } else {
                    ap.instalmentAmount = '0';
                    ap.principalComp = 0;
                    accumulatedInterest += ap.interestComp;
                    
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallments)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal;
                        accumulatedInterest = 0;
                    } else {
                        ap.closingPrinciple = workingPrincipal;
                    }
                }
                
                ap.irr = iRRInterest;
                ap.dueDate = repaymentDate;
                ap.instalmentNo = startingInstallmentNo + i + 1;
                ap.emiDenominator = ap.days;
                
                schedule.add(ap);
                repaymentDate = repaymentDate.addMonths(frequency);
            }
        }
        
        Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
        Integer avgDays = 30; // Approximate days per month
        Decimal avgInterest = (iRRInterest * workingPrincipal * avgDays) / (daysInYear * 100);
        Integer equalInterest = Integer.valueOf(avgInterest.round(RoundingMode.HALF_UP));
        
        // Calculate equal principal to ensure loan is paid off (rounded to integer)
        Integer equalPrincipal = workingPrincipal / effectiveInstallments;
        
        // Generate schedule with equal interest
        for (Integer i = 0; i < effectiveInstallments; i++) {
            RepaymentWrapper ap = new RepaymentWrapper();
            ap.days = getDaysInMonth(repaymentDate, daysInMonthMethod);
            
            // Safeguard: If principal is already zero or negative, stop
            if (workingPrincipal <= 0) {
                break;
            }
            
            if (accurateInterest) {
                applyInterestWithCarry(ap, avgInterest, carryRef, true);
            } else {
                ap.interestComp = equalInterest;
            }
            
            // Only the actual last installment closes out remaining balance
            if (i == effectiveInstallments - 1) {
                ap.principalComp = workingPrincipal;
                ap.closingPrinciple = 0;
            } else {
                Integer principalForThisInstallment = equalPrincipal;
                
                // If paying full equalPrincipal would wipe out the balance before the last installment,
                // redistribute remaining principal across remaining installments
                if (principalForThisInstallment >= workingPrincipal) {
                    Integer remainingInstallments = effectiveInstallments - i;
                    principalForThisInstallment = workingPrincipal / remainingInstallments;
                    if (principalForThisInstallment <= 0 && workingPrincipal > 0) {
                        principalForThisInstallment = 1;
                    }
                }
                
                ap.principalComp = principalForThisInstallment;
                ap.closingPrinciple = workingPrincipal - ap.principalComp;
            }
            
            ap.instalmentAmount = String.valueOf(ap.principalComp + ap.interestComp);
            ap.irr = iRRInterest;
            ap.dueDate = repaymentDate;
            ap.instalmentNo = startingInstallmentNo + moratoriumInstallments + i + 1;
            ap.openingPrinciple2 = workingPrincipal;
            ap.emiDenominator = ap.days;
            
            workingPrincipal = ap.closingPrinciple;
            schedule.add(ap);
            repaymentDate = repaymentDate.addMonths(frequency);
        }
        
        return schedule;
    }
    
    /**
     * @description Generate Step Up EMI Schedule
     * Note: Pre-EMI (Interest Only) is already handled in main method
     * This method handles:
     * 1. Moratorium period (if applicable)
     * 2. Regular EMI schedule with yearly step-up
     * 
     * Step-up logic:
     * - Starts with base EMI calculated on remaining principal
     * - Every 12 months, multiplies EMI by stepUpRate (default 1.02 = 2% increase)
     * - Applies only AFTER Pre-EMI and Moratorium periods are complete
     */
    private static List<RepaymentWrapper> generateStepUpEMISchedule(
        Integer principal,
        Decimal iRRInterest,
        Integer tenure,
        Integer frequency,
        Date repaymentDate,
        Integer moratoriumMonths,
        String moratoriumInterestPayment,
        Integer moratoriumPartialAmount,
        Integer startingInstallmentNo,
        String daysInYearMethod,
        String daysInMonthMethod,
        Decimal stepUpRate,
        String capitalizationType,
        Integer firstInstallmentDays,
        Date loanDate,
        Integer emiCalculationDays
    ) {
        List<RepaymentWrapper> schedule = new List<RepaymentWrapper>();
        Integer workingPrincipal = principal;
        Integer totalInstallments = tenure / frequency;
        Decimal monthlyRate = iRRInterest / (12 * 100);
        
        // Handle Moratorium Period first with proper capitalization frequency
        Integer moratoriumInstallments = 0;  
        Integer accumulatedInterest = 0; // Track accumulated unpaid interest
        Integer principalForInterestCalc = workingPrincipal; // Store base principal for interest calculation
        
        if (moratoriumMonths > 0) { 
            Integer moratoriumInstallmentsCount = moratoriumMonths / frequency;
            for (Integer i = 0; i < moratoriumInstallmentsCount; i++) {
                RepaymentWrapper ap = new RepaymentWrapper();
                Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
                
                // Calculate days for this moratorium installment
                if (i == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0) {
                    // FIRST installment: use days from loan date to first EMI date
                    ap.days = firstInstallmentDays;
                    
                    // MORATORIUM OVERRIDE LOGIC: If override is enabled and days < 30
                    // Calculate interest for FULL MONTH (30 days), not actual days
                    // During moratorium, ALL goes to interest - NO principal payment ever
                    if (emiCalculationDays != null && emiCalculationDays != firstInstallmentDays) {
                        ap.days = emiCalculationDays; // Use full month days for interest calculation
                    }
                } else if (daysInMonthMethod == 'ACTUAL') {
                    // ACTUAL mode: use actual days in the PREVIOUS month (the interest period)
                    Date previousMonth = repaymentDate.addMonths(-1);
                    ap.days = Date.daysInMonth(previousMonth.year(), previousMonth.month());
                } else {
                    // Fixed mode (30/360): always 30 days
                    ap.days = 30;
                }  
                 
                // IMPORTANT: Capture opening principal BEFORE any modifications
                ap.openingPrinciple2 = workingPrincipal;
                
                
                // Calculate interest on the current working principal (includes previous capitalizations)
                Decimal interest = (iRRInterest * workingPrincipal * ap.days) / (daysInYear * 100);
                ap.interestComp = Integer.valueOf(interest.round(RoundingMode.HALF_UP));
                
                
                if (moratoriumInterestPayment == 'INTEREST_ONLY') {
                    // Pay full interest only during moratorium - no capitalization
                    ap.instalmentAmount = String.valueOf(ap.interestComp);
                    ap.principalComp = 0;
                    ap.closingPrinciple = workingPrincipal; // No change to principal
                } else if (moratoriumInterestPayment == 'PARTIAL_INTEREST') {
                    // Pay partial interest - rest accumulates
                    ap.instalmentAmount = String.valueOf(moratoriumPartialAmount);
                    ap.principalComp = 0;
                    
                    // Calculate unpaid interest
                    Integer unpaidInterest = ap.interestComp - moratoriumPartialAmount;
                    if (unpaidInterest > 0) {
                        accumulatedInterest += unpaidInterest;
                    }
                    
                    // Check if we should capitalize at this installment
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallmentsCount)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal; // Show capitalized principal
                        accumulatedInterest = 0; // Reset accumulated interest
                    } else {
                        ap.closingPrinciple = workingPrincipal; // No change to principal yet
                    }
                } else {
                    // NO_PAYMENT - Full interest accumulates
                    ap.instalmentAmount = '0';
                    ap.principalComp = 0;
                    accumulatedInterest += ap.interestComp;
                    
                    // Check if we should capitalize at this installment
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallmentsCount)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal; // Show capitalized principal
                        accumulatedInterest = 0; // Reset accumulated interest
                    } else {
                        ap.closingPrinciple = workingPrincipal; // No change to principal yet
                    }
                }
                
                ap.irr = iRRInterest;
                ap.dueDate = repaymentDate;
                ap.instalmentNo = startingInstallmentNo + i + 1;
                ap.emiDenominator = ap.days;
                
                schedule.add(ap);
                repaymentDate = repaymentDate.addMonths(frequency);
                moratoriumInstallments++;
            }
        }
        
        // Calculate initial EMI using standard formula
        Double monthlyRateDouble = monthlyRate;
        // Calculate EMI for ENTIRE remaining tenure (not just first year)
        Integer remainingInstallments = totalInstallments - moratoriumInstallments;
        
        Decimal currentEMI = (workingPrincipal * monthlyRate * Math.pow((1 + monthlyRateDouble), remainingInstallments)) /
                             (Math.pow((1 + monthlyRateDouble), remainingInstallments) - 1);
        
        Integer monthsInCurrentYear = 0;
        Decimal stepUpMultiplier = 1.0;
        
        // Generate regular EMI schedule with step-up
        for (Integer i = 0; i < totalInstallments; i++) {
            if (workingPrincipal <= 0) break;
            
            // Recalculate EMI at the start of each year based on remaining principal and tenure
            if (monthsInCurrentYear >= 12) {
                stepUpMultiplier = stepUpMultiplier * stepUpRate; // Accumulate step-up factor
                monthsInCurrentYear = 0;
                
                // Recalculate EMI for ENTIRE remaining tenure (not just next year)
                Integer remainingTenure = totalInstallments - i;
                
                if (remainingTenure > 0 && workingPrincipal > 0) {
                    Decimal baseEMI = (workingPrincipal * monthlyRate * Math.pow((1 + monthlyRateDouble), remainingTenure)) /
                                      (Math.pow((1 + monthlyRateDouble), remainingTenure) - 1);
                    currentEMI = baseEMI * stepUpMultiplier;
                }
            }
            
            RepaymentWrapper ap = new RepaymentWrapper();
            Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
            
            // Calculate days for this installment
            if (i == 0 && moratoriumInstallments == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0) {
                // FIRST installment (no moratorium/pre-EMI): use days from loan date to first EMI date
                ap.days = firstInstallmentDays;
            } else if (daysInMonthMethod == 'ACTUAL') { 
                // ACTUAL mode: calculate actual days to NEXT EMI date
                Date nextEmiDate = repaymentDate.addMonths(frequency);
                ap.days = repaymentDate.daysBetween(nextEmiDate);
            } else {
                // Fixed mode (30/360): always 30 days
                ap.days = 30;
            }
            
            Decimal interest = (iRRInterest * workingPrincipal * ap.days) / (daysInYear * 100);
            ap.interestComp = Integer.valueOf(interest.round(RoundingMode.HALF_UP));
            
            Integer principalComponent = Integer.valueOf(currentEMI.round(RoundingMode.HALF_UP)) - ap.interestComp;
            
            if (principalComponent > workingPrincipal) {
                ap.principalComp = workingPrincipal;
                ap.closingPrinciple = 0;
            } else {
                ap.principalComp = principalComponent;
                ap.closingPrinciple = workingPrincipal - principalComponent;
            }
            
            ap.instalmentAmount = String.valueOf(ap.principalComp + ap.interestComp);
            ap.irr = iRRInterest;
            ap.dueDate = repaymentDate;
            ap.instalmentNo = startingInstallmentNo + moratoriumInstallments + i + 1;
            ap.openingPrinciple2 = workingPrincipal;
            ap.emiDenominator = ap.days;
            
            workingPrincipal = ap.closingPrinciple;
            schedule.add(ap);
            
            repaymentDate = repaymentDate.addMonths(frequency);
            monthsInCurrentYear += frequency;
            
            if (ap.closingPrinciple == 0) break;
        }
        
        return schedule;
    }
    
    /**
     * @description Generate Step Down EMI Schedule
     * With Pre-EMI: Three phases
     * Phase 1: Pre-EMI (Interest Only) - Already handled in main method
     * Phase 2: Calculate EMI to reach target principal at target tenure (adjusted for Pre-EMI)
     * Phase 3: Calculate different EMI for remaining balance
     * 
     * Without Pre-EMI: Two phases
     * Phase 1: Calculate EMI to reach target principal at target tenure
     * Phase 2: Calculate different EMI for remaining balance
     */
    private static List<RepaymentWrapper> generateStepDownEMISchedule(
        Integer principal,
        Decimal iRRInterest,
        Integer tenure,
        Integer frequency,
        Date repaymentDate, 
        Integer moratoriumMonths,
        String moratoriumInterestPayment,
        Integer moratoriumPartialAmount,
        Integer startingInstallmentNo,
        String daysInYearMethod,
        String daysInMonthMethod,
        Integer stepDownTargetTenure,
        Integer stepDownTargetPrincipal,
        String capitalizationType,
        Integer preEmiMonthsProcessed,
        Integer firstInstallmentDays,
        Date loanDate,
        Integer emiCalculationDays
    ) {
        List<RepaymentWrapper> schedule = new List<RepaymentWrapper>();
        Integer workingPrincipal = principal;
        Integer totalInstallments = tenure / frequency;
        Decimal monthlyRate = iRRInterest / (12 * 100);
        
        // Handle Moratorium Period first with proper capitalization frequency
        Integer moratoriumInstallments = 0;
        Integer accumulatedInterest = 0; // Track accumulated unpaid interest
        Integer principalForInterestCalc = workingPrincipal; // Store base principal for interest calculation
        
        if (moratoriumMonths > 0) {
            Integer moratoriumInstallmentsCount = moratoriumMonths / frequency;
            for (Integer i = 0; i < moratoriumInstallmentsCount; i++) {
                RepaymentWrapper ap = new RepaymentWrapper();
                Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod); 
                
                // Calculate days for this moratorium installment
                if (i == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0) {
                    // FIRST installment: use days from loan date to first EMI date
                    ap.days = firstInstallmentDays;
                    
                    // MORATORIUM OVERRIDE LOGIC: If override is enabled and days < 30
                    // Calculate interest for FULL MONTH (30 days), not actual days
                    // During moratorium, ALL goes to interest - NO principal payment ever
                    if (emiCalculationDays != null && emiCalculationDays != firstInstallmentDays) {
                        ap.days = emiCalculationDays; // Use full month days for interest calculation
                    }
                } else if (daysInMonthMethod == 'ACTUAL') {
                    // ACTUAL mode: use actual days in the PREVIOUS month (the interest period)
                    Date previousMonth = repaymentDate.addMonths(-1);
                    ap.days = Date.daysInMonth(previousMonth.year(), previousMonth.month());
                } else {
                    // Fixed mode (30/360): always 30 days
                    ap.days = 30;
                }
                
                // IMPORTANT: Capture opening principal BEFORE any modifications
                ap.openingPrinciple2 = workingPrincipal;
                
                
                // Calculate interest on the current working principal (includes previous capitalizations)
                Decimal interest = (iRRInterest * workingPrincipal * ap.days) / (daysInYear * 100);
                ap.interestComp = Integer.valueOf(interest.round(RoundingMode.HALF_UP));
                
                
                if (moratoriumInterestPayment == 'INTEREST_ONLY') {
                    // Pay full interest only during moratorium - no capitalization
                    ap.instalmentAmount = String.valueOf(ap.interestComp);
                    ap.principalComp = 0;
                    ap.closingPrinciple = workingPrincipal; // No change to principal
                } else if (moratoriumInterestPayment == 'PARTIAL_INTEREST') {
                    // Pay partial interest - rest accumulates
                    ap.instalmentAmount = String.valueOf(moratoriumPartialAmount);
                    ap.principalComp = 0;
                    
                    // Calculate unpaid interest
                    Integer unpaidInterest = ap.interestComp - moratoriumPartialAmount;
                    if (unpaidInterest > 0) {
                        accumulatedInterest += unpaidInterest;
                    }
                    
                    // Check if we should capitalize at this installment
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallmentsCount)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal; // Show capitalized principal
                        accumulatedInterest = 0; // Reset accumulated interest
                    } else {
                        ap.closingPrinciple = workingPrincipal; // No change to principal yet
                    }
                } else {
                    // NO_PAYMENT - Full interest accumulates
                    ap.instalmentAmount = '0';
                    ap.principalComp = 0;
                    accumulatedInterest += ap.interestComp;
                    
                    // Check if we should capitalize at this installment
                    if (shouldCapitalizeInterest(i, frequency, capitalizationType, moratoriumInstallmentsCount)) {
                        workingPrincipal += accumulatedInterest;
                        ap.closingPrinciple = workingPrincipal; // Show capitalized principal
                        accumulatedInterest = 0; // Reset accumulated interest
                    } else {
                        ap.closingPrinciple = workingPrincipal; // No change to principal yet
                    }
                }
                
                ap.irr = iRRInterest;
                ap.dueDate = repaymentDate;
                ap.instalmentNo = startingInstallmentNo + i + 1;
                ap.emiDenominator = ap.days;
                
                schedule.add(ap);
                repaymentDate = repaymentDate.addMonths(frequency);
                moratoriumInstallments++;
            }
        }
        
        // Calculate Phase 1 (reach target) and Phase 2 (remaining balance) installments
        // Note: Pre-EMI and Moratorium are already handled, so we work with remaining tenure
        Integer remainingTenure = tenure - preEmiMonthsProcessed - moratoriumMonths;
        Integer remainingInstallments = remainingTenure / frequency;
        
        // Adjust target tenure for Pre-EMI months already processed
        Integer adjustedTargetTenure = stepDownTargetTenure - preEmiMonthsProcessed - moratoriumMonths;
        
        // Phase 1: From now until target tenure (adjusted for Pre-EMI already processed)
        Integer phase1Installments = adjustedTargetTenure / frequency;
        
        // Phase 2: From target tenure to end of loan
        Integer phase2Installments = remainingInstallments - phase1Installments;
        
        // If target tenure is already passed or reached, skip Phase 1
        if (phase1Installments <= 0) {
            phase1Installments = 0;
            phase2Installments = remainingInstallments;   
        }
        
        // Phase 1: Calculate EMI to reach target principal (if applicable)
        // Using formula: EMI = (P - FV) * r * (1+r)^n / ((1+r)^n - 1)
        // Where P = Current Principal, FV = Future Value (target principal) 
        Decimal phase1EMI = 0;
        if (phase1Installments > 0 && workingPrincipal > stepDownTargetPrincipal) { 
            Double monthlyRateDouble = monthlyRate;
            Decimal numerator = (workingPrincipal - stepDownTargetPrincipal) * monthlyRate * Math.pow((1 + monthlyRateDouble), phase1Installments);
            Decimal denominator = Math.pow((1 + monthlyRateDouble), phase1Installments) - 1;
            phase1EMI = numerator / denominator;
        }
        
        
        // Generate Phase 1 schedule (if needed)
        for (Integer i = 0; i < phase1Installments; i++) {
            if (workingPrincipal <= stepDownTargetPrincipal) break;
            
            RepaymentWrapper ap = new RepaymentWrapper();
            Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod);
            
            // Calculate days for this installment
            if (i == 0 && moratoriumInstallments == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0) {
                // FIRST installment (no moratorium/pre-EMI): use days from loan date to first EMI date
                ap.days = firstInstallmentDays;
            } else if (daysInMonthMethod == 'ACTUAL') {
                // ACTUAL mode: use actual days in the PREVIOUS month (the interest period)
                Date previousMonth = repaymentDate.addMonths(-1);
                ap.days = Date.daysInMonth(previousMonth.year(), previousMonth.month());
            } else {
                // Fixed mode (30/360): always 30 days
                ap.days = 30;
            }
            
            Decimal interest = (iRRInterest * workingPrincipal * ap.days) / (daysInYear * 100);
            ap.interestComp = Integer.valueOf(interest.round(RoundingMode.HALF_UP));
            
            Integer principalComponent = Integer.valueOf(phase1EMI.round(RoundingMode.HALF_UP)) - ap.interestComp;
            
            if (principalComponent > workingPrincipal - stepDownTargetPrincipal) {
                ap.principalComp = workingPrincipal - stepDownTargetPrincipal;
                ap.closingPrinciple = stepDownTargetPrincipal;
            } else {
                ap.principalComp = principalComponent;
                ap.closingPrinciple = workingPrincipal - principalComponent;
            } 
            
            ap.instalmentAmount = String.valueOf(ap.principalComp + ap.interestComp);
            ap.irr = iRRInterest;
            ap.dueDate = repaymentDate; 
            ap.instalmentNo = startingInstallmentNo + moratoriumInstallments + i + 1;

            ap.openingPrinciple2 = workingPrincipal;
            ap.emiDenominator = ap.days;
            
            workingPrincipal = ap.closingPrinciple;
            schedule.add(ap);
            
            repaymentDate = repaymentDate.addMonths(frequency);
        }
        
        // Phase 2: Calculate new EMI for remaining balance
        Decimal phase2EMI = 0;
        if (phase2Installments > 0 && workingPrincipal > 0) {
            Double monthlyRateDouble = monthlyRate;
            Decimal numerator = workingPrincipal * monthlyRate * Math.pow((1 + monthlyRateDouble), phase2Installments);
            Decimal denominator = Math.pow((1 + monthlyRateDouble), phase2Installments) - 1;
            phase2EMI = numerator / denominator;
        }
        
        // Generate Phase 2 schedule
        for (Integer i = 0; i < phase2Installments; i++) {
            if (workingPrincipal <= 0) break;
            
            RepaymentWrapper ap = new RepaymentWrapper();
            Integer daysInYear = getDaysInYear(repaymentDate, daysInYearMethod); 
            
            // Calculate days for this installment
            if (i == 0 && phase1Installments == 0 && startingInstallmentNo == 0 && firstInstallmentDays > 0) {
                // First installment with Pre-EMI and no Phase 1: use calculated days from loan date to first EMI
                ap.days = firstInstallmentDays;
            } else if (daysInMonthMethod == 'ACTUAL') {
                // ACTUAL mode: use actual days in the PREVIOUS month (the interest period)
                Date previousMonth = repaymentDate.addMonths(-1);
                ap.days = Date.daysInMonth(previousMonth.year(), previousMonth.month());
            } else {
                // Fixed mode (30/360): always 30 days
                ap.days = 30;
            }
            
            Decimal interest = (iRRInterest * workingPrincipal * ap.days) / (daysInYear * 100);
            ap.interestComp = Integer.valueOf(interest.round(RoundingMode.HALF_UP));
            
            Integer principalComponent = Integer.valueOf(phase2EMI.round(RoundingMode.HALF_UP)) - ap.interestComp;
            
            if (principalComponent > workingPrincipal) {
                ap.principalComp = workingPrincipal;
                ap.closingPrinciple = 0;
            } else {
                ap.principalComp = principalComponent;
                ap.closingPrinciple = workingPrincipal - principalComponent;
            }
            
            ap.instalmentAmount = String.valueOf(ap.principalComp + ap.interestComp);
            ap.irr = iRRInterest;
            ap.dueDate = repaymentDate;
            ap.instalmentNo = startingInstallmentNo + moratoriumInstallments + phase1Installments + i + 1;

            ap.openingPrinciple2 = workingPrincipal;
            ap.emiDenominator = ap.days;
            
            workingPrincipal = ap.closingPrinciple;
            schedule.add(ap);
            
            repaymentDate = repaymentDate.addMonths(frequency);
            
            if (ap.closingPrinciple == 0) break;
        }
        
        return schedule;
    }
    
    /**
     * @description Check if interest should be capitalized at this installment
     * @param installmentIndex - Current installment index (0-based)
     * @param frequency - Payment frequency in months
     * @param capitalizationType - MONTHLY, QUARTERLY, YEARLY, or END_OF_MORATORIUM
     * @param totalMoratoriumInstallments - Total moratorium installments
     * @return Boolean - True if capitalization should occur
     */
    private static Boolean shouldCapitalizeInterest(
        Integer installmentIndex,
        Integer frequency,
        String capitalizationType,
        Integer totalMoratoriumInstallments
    ) {
        
        if (capitalizationType == 'MONTHLY') {
            return true; // Capitalize every installment
        } else if (capitalizationType == 'QUARTERLY') {
            // Capitalize every 3 months (or 1 quarter)
            Integer monthsPassed = (installmentIndex + 1) * frequency;
            Boolean shouldCap = Math.mod(monthsPassed, 3) == 0;
            return shouldCap;
        } else if (capitalizationType == 'YEARLY') {
            // Capitalize every 12 months (or 1 year)
            Integer monthsPassed = (installmentIndex + 1) * frequency;
            Boolean shouldCap = Math.mod(monthsPassed, 12) == 0;
            return shouldCap;
        } else if (capitalizationType == 'END_OF_MORATORIUM') {
            // Capitalize only at the end (last installment)
            Boolean shouldCap = (installmentIndex == totalMoratoriumInstallments - 1);
            return shouldCap;
        }
        return true; // Default to monthly
    }
    
    /**
     * @description Helper method to calculate days in year based on the selected method
     * @param currentDate - Date to check for leap year (if using ACTUAL method)
     * @param daysInYearMethod - Method: 'ACTUAL', '360', '365', or '366'
     * @return Integer - Number of days in year
     */
    private static Integer getDaysInYear(Date currentDate, String daysInYearMethod) {
        if (daysInYearMethod == '360') {
            return 360;
        } else if (daysInYearMethod == '365') {
            return 365;
        } else if (daysInYearMethod == '366') {
            return 366;
        } else {
            // ACTUAL - Use leap year detection
            return Date.isLeapYear(currentDate.year()) ? 366 : 365;
        }
    }
    
    /**
     * @description Get days in month based on the selected method
     * @param currentDate - Date to check
     * @param daysInMonthMethod - Method: 'ACTUAL', '30', or '31'
     * @return Integer - Number of days in the month
     */
    private static Integer getDaysInMonth(Date currentDate, String daysInMonthMethod) { 
        if (daysInMonthMethod == '30') {
            return 30;
        } else if (daysInMonthMethod == '31') {
            return 31;
        } else {
            // ACTUAL - Use actual days in month (28/29 for Feb, 30/31 for others)
            return Date.daysInMonth(currentDate.year(), currentDate.month());
        }
    }
    
    /**
     * @description Calculate EMI using 30/360 day count convention (FinOne method).
     *              Always uses 30 days per month and 360 days per year regardless of
     *              the user's selected calculation mode.
     * @param principal - Loan principal amount
     * @param annualRate - Annual interest rate (percentage, e.g. 10 for 10%)
     * @param totalInstallments - Total number of installments
     * @return Decimal - The calculated EMI amount (unrounded)
     */
    private static Decimal calculateFinoneEmi(Integer principal, Decimal annualRate, Integer totalInstallments) {
        // Monthly rate using 30/360: rate% / 12 / 100
        Decimal monthlyRate = (annualRate / Decimal.valueOf(1200)).setScale(8, RoundingMode.HALF_UP);
        
        Decimal onePlusRate = Decimal.valueOf(1) + monthlyRate;
        Decimal powerTerm = Decimal.valueOf(1);
        for (Integer p = 0; p < totalInstallments; p++) {
            powerTerm = powerTerm * onePlusRate;
        }
        
        Decimal numerator = Decimal.valueOf(principal) * monthlyRate * powerTerm;
        Decimal denominator = powerTerm - Decimal.valueOf(1);
        
        return numerator / denominator;
    }
    
    /**
     * @description Apply interest calculation with optional carry-forward logic.
     *              When accurateInterest is true, the raw interest is combined with the
     *              previous carry-forward, rounded to integer (HALF_UP), and the decimal
     *              remainder is carried forward. Carry can be positive (rounded down)
     *              or negative (rounded up).
     * @param ap - The RepaymentWrapper to set interest fields on
     * @param rawInterest - The raw calculated interest (P * R * T)
     * @param carryRef - Single-element Decimal array holding the carry-forward value (mutable)
     * @param useAccurateInterest - Whether to apply carry-forward logic
     */
    private static void applyInterestWithCarry(
        RepaymentWrapper ap,
        Decimal rawInterest,
        Decimal[] carryRef,
        Boolean useAccurateInterest
    ) {
        if (useAccurateInterest) {
            ap.interestRaw = rawInterest.setScale(4, RoundingMode.HALF_UP);
            Decimal totalWithCarry = rawInterest + carryRef[0];
            Integer billedInterest = Integer.valueOf(totalWithCarry.round(RoundingMode.HALF_UP));
            carryRef[0] = totalWithCarry - billedInterest;
            ap.interestCompExact = Decimal.valueOf(billedInterest);
            ap.carryForward = carryRef[0].setScale(4, RoundingMode.HALF_UP);
            ap.interestComp = billedInterest;
        } else {
            ap.interestComp = Integer.valueOf(rawInterest.round(RoundingMode.HALF_UP));
        }
    }
    
    /**
     * @description Calculate days between two dates using appropriate day count convention
     * @param startDate - Start date
     * @param endDate - End date
     * @param daysInMonthMethod - Method: '30' for Fixed (30/360), 'ACTUAL' for actual days
     * @return Integer - Number of days between dates
     */
    private static Integer calculateDaysBetween(Date startDate, Date endDate, String daysInMonthMethod) {
        if (daysInMonthMethod == '30') {
            // Fixed (30/360) day count convention
            // Formula: Days = 360*(Y2-Y1) + 30*(M2-M1) + (D2-D1)
            Integer y1 = startDate.year();
            Integer m1 = startDate.month();
            Integer d1 = startDate.day();
            Integer y2 = endDate.year();
            Integer m2 = endDate.month();
            Integer d2 = endDate.day();
            
            // Adjust day values for 30/360 convention
            // If day is 31, treat it as 30
            if (d1 > 30) d1 = 30;
            if (d2 > 30) d2 = 30;
            
            Integer days = 360 * (y2 - y1) + 30 * (m2 - m1) + (d2 - d1);
            return days;
        } else {
            // ACTUAL - Use actual days between dates
            return startDate.daysBetween(endDate);
        }
    }
    
    public Class RepaymentWrapper {
        @AuraEnabled
        public Boolean inputError { get; set; }
        @AuraEnabled
        public Integer instalmentNo { get; set; }
        @AuraEnabled
        public String instalmentAmount { get; set; }
        @AuraEnabled
        public Integer principalComp { get; set; }
        @AuraEnabled
        public Integer interestComp { get; set; }
        @AuraEnabled
        public Decimal irr { get; set; }
        @AuraEnabled
        public Integer openingPrinciple2 { get; set; }
        @AuraEnabled
        public Integer closingPrinciple { get; set; }
        @AuraEnabled
        public Date dueDate { get; set; }
        @AuraEnabled
        public Integer days { get; set; }
        @AuraEnabled
        public Integer interestCalculationDays { get; set; }
        @AuraEnabled
        public Integer fullEmiDays { get; set; }
        @AuraEnabled
        public Decimal interestRaw { get; set; }
        @AuraEnabled
        public Decimal interestCompExact { get; set; }
        @AuraEnabled
        public Decimal carryForward { get; set; }
        @AuraEnabled
        public Integer principalDays { get; set; }
        @AuraEnabled
        public Decimal emiNumerator { get; set; }
        @AuraEnabled
        public Decimal emiDenominator { get; set; }
    }
}