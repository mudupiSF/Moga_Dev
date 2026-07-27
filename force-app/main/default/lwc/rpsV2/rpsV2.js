import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import emiRepaymentScheduleHlEnhanced from '@salesforce/apex/RPSV2Helper.emiRepaymentScheduleHlEnhanced';
import SHEETJS from '@salesforce/resourceUrl/sheetJS';

export default class RpsV2 extends LightningElement {    
    @track principal = 100000;
    @track irr = '11'; 
    @track loanDate = new Date().toISOString().split('T')[0]; 
    @track tenure = 36;
    @track day = 1;
    @track frequency = '1';
    @track repaymentDate = new Date(new Date().setMonth(new Date().getMonth() + 1)).toISOString().split('T')[0];
    @track repaymentType = 'EQUATED_EMI';    
    @track moratoriumMonths = 0;
    @track moratoriumInterestPayment = 'NO_PAYMENT';
    @track moratoriumPartialAmount = 0;
    @track calculationMode = 'FLOATING';
    @track daysInYearMethod = '365';
    @track daysInMonthMethod = 'ACTUAL';
    
    @track preEmiType = 'NONE';
    @track preEmiStartDate = null;
    @track preEmiEndDate = null;
    @track preEmiMonths = 0;
    
    @track capitalizationType = 'MONTHLY';
    
    @track overrideProrateInterest = false;
    @track accurateInterest = false;
    @track firstMonthPreEmi30days = false;
    @track treatFirstMonthAsPreEmi = false;
    
    @track scheduleData = [];
    @track isLoading = false;
    @track showResults = false;
    @track sheetJSInitialized = false;

    @track disabledFieldsMap = {};
    @api disableFields;
    @api overrideDefaultFlow;
    @api defaultValues;
    @api removeResetButton;
    @api dayOfMonthOptionsOverride;
    @api tableColumns;

    handleLoadDateForOverrideDefaultFlow(){
        if(this.overrideDefaultFlow){
            this.disabledFieldsMap = {};
            if(this.disableFields && typeof this.disableFields === 'string'){
                const fields = this.disableFields.split(',').map(field => field.trim());
                for(let field of fields){
                    if(field){
                        this.disabledFieldsMap[field] = true;
                    }
                }
            }

            if(this.defaultValues){
                let defaultValuesObj = {};
                
                if(typeof this.defaultValues === 'string'){
                    try {
                        defaultValuesObj = JSON.parse(this.defaultValues);
                    } catch(e) {
                        console.error('Error parsing defaultValues JSON:', e);
                    }
                } else if(typeof this.defaultValues === 'object'){
                    defaultValuesObj = this.defaultValues;
                }
                
                const fieldMapping = {
                    'principal': 'principal',
                    'loanAmount': 'principal',
                    'interestRate': 'irr',
                    'irr': 'irr',
                    'roi': 'irr',
                    'tenure': 'tenure',
                    'loanDate': 'loanDate',
                    'day': 'day',
                    'frequency': 'frequency',
                    'repaymentDate': 'repaymentDate',
                    'firstEMIDate': 'repaymentDate',
                    'repaymentType': 'repaymentType',
                    'moratoriumMonths': 'moratoriumMonths',
                    'moratorium': 'moratoriumMonths',
                    'moratoriumInterestPayment': 'moratoriumInterestPayment',
                    'moratoriumPartialAmount': 'moratoriumPartialAmount',
                    'calculationMode': 'calculationMode',
                    'daysInYearMethod': 'daysInYearMethod',
                    'daysInYear': 'daysInYearMethod',
                    'daysInMonthMethod': 'daysInMonthMethod',
                    'daysInMonth': 'daysInMonthMethod',
                    'preEmiType': 'preEmiType',
                    'preEmiStartDate': 'preEmiStartDate',
                    'preEmiEndDate': 'preEmiEndDate',
                    'preEmiMonths': 'preEmiMonths',
                    'capitalizationType': 'capitalizationType',
                    'overrideProrateInterest': 'overrideProrateInterest',
                    'accurateInterest': 'accurateInterest',
                    'firstMonthPreEmi30days': 'firstMonthPreEmi30days',
                    'treatFirstMonthAsPreEmi': 'treatFirstMonthAsPreEmi'
                };
                
                for(let key in defaultValuesObj){
                    if(defaultValuesObj.hasOwnProperty(key) && fieldMapping[key]){
                        const internalProperty = fieldMapping[key];
                        this[internalProperty] = defaultValuesObj[key];
                    }
                }

                if(defaultValuesObj.scheduleData){
                    try {
                        if(typeof defaultValuesObj.scheduleData === 'string'){
                            const parsedScheduleData = JSON.parse(defaultValuesObj.scheduleData);
                            if(parsedScheduleData && Array.isArray(parsedScheduleData)){
                                const formatDate = this.formatDateToUserFriendly.bind(this);
                                this.scheduleData = parsedScheduleData.map(row => {
                                    return {
                                        ...row,
                                        dueDate: row.dueDate ? formatDate(row.dueDate) : row.dueDate
                                    };
                                });
                                if(parsedScheduleData.length > 0){
                                    this.showResults = true;
                                }
                            }
                        } else if(Array.isArray(defaultValuesObj.scheduleData)){
                            const formatDate = this.formatDateToUserFriendly.bind(this);
                            this.scheduleData = defaultValuesObj.scheduleData.map(row => {
                                return {
                                    ...row,
                                    dueDate: row.dueDate ? formatDate(row.dueDate) : row.dueDate
                                };
                            });
                            if(defaultValuesObj.scheduleData.length > 0){
                                this.showResults = true;
                            }
                        }
                    } catch(e) {
                        console.error('Error parsing scheduleData:', e);
                        this.scheduleData = [];
                    }
                }
            }
            
            if(this.dayOfMonthOptionsOverride){
                const options = this.dayOfMonthOptionsOverrideValue;
                if(options && options.length > 0){
                    this.day = options[0].value;
                }
            } else {
                this.day = '1';
            }
            
            if(this.scheduleData.length === 0){
                this.autoCalculateFirstEMIDate();
            }
        }
    }
  
    get daysInYearDisabledCombined() {
        return this.daysCalculationDisabled || this.disabledFieldsMap['daysInYear'] || false;
    }

    get daysInMonthDisabledCombined() {
        return this.daysCalculationDisabled || this.disabledFieldsMap['daysInMonth'] || false;
    }

    get principalDisabled() {
        return this.disabledFieldsMap['principal'] || false;
    }

    get interestRateDisabled() {
        return this.disabledFieldsMap['interestRate'] || false;
    }

    get tenureDisabled() {
        return this.disabledFieldsMap['tenure'] || false;
    }

    get loanDateDisabled() {
        return this.disabledFieldsMap['loanDate'] || false;
    }

    get dayDisabled() {
        return this.disabledFieldsMap['day'] || false;
    }

    get firstEMIDateDisabled() {
        return this.disabledFieldsMap['firstEMIDate'] || false;
    }

    get repaymentTypeDisabled() {
        return this.disabledFieldsMap['repaymentType'] || false;
    }

    get frequencyDisabled() {
        return this.disabledFieldsMap['frequency'] || false;
    }

    get calculationModeDisabled() {
        return this.disabledFieldsMap['calculationMode'] || false;
    }

    get daysInYearDisabled() {
        return this.disabledFieldsMap['daysInYear'] || false;
    }

    get daysInMonthDisabled() {
        return this.disabledFieldsMap['daysInMonth'] || false;
    }

    get preEmiTypeDisabled() {
        return this.disabledFieldsMap['preEmiType'] || false;
    }

    get preEmiMonthsDisabled() {
        return this.disabledFieldsMap['preEmiMonths'] || false;
    }

    get moratoriumMonthsDisabled() {
        return this.disabledFieldsMap['moratoriumMonths'] || false;
    }

    get moratoriumInterestPaymentDisabled() {
        return this.disabledFieldsMap['moratoriumInterestPayment'] || false;
    }

    get capitalizationTypeDisabled() {
        return this.disabledFieldsMap['capitalizationType'] || false;
    }

    get moratoriumPartialAmountDisabled() {
        return this.disabledFieldsMap['moratoriumPartialAmount'] || false;
    }

    handleSave() {
        const formData = {
            principal: this.principal,
            irr: this.irr,
            loanDate: this.loanDate,
            tenure: this.tenure,
            day: this.day,
            frequency: this.frequency,
            repaymentDate: this.repaymentDate,
            repaymentType: this.repaymentType,
            moratoriumMonths: this.moratoriumMonths,
            moratoriumInterestPayment: this.moratoriumInterestPayment,
            moratoriumPartialAmount: this.moratoriumPartialAmount,
            calculationMode: this.calculationMode,
            daysInYearMethod: this.daysInYearMethod,
            daysInMonthMethod: this.daysInMonthMethod,
            preEmiType: this.preEmiType,
            preEmiStartDate: this.preEmiStartDate,
            preEmiEndDate: this.preEmiEndDate,
            preEmiMonths: this.preEmiMonths,
            capitalizationType: this.capitalizationType,
            overrideProrateInterest: this.overrideProrateInterest,
            accurateInterest: this.accurateInterest,
            firstMonthPreEmi30days: this.firstMonthPreEmi30days,
            treatFirstMonthAsPreEmi: this.treatFirstMonthAsPreEmi,
            scheduleData: this.scheduleData
        };

        const saveEvent = new CustomEvent('save', {
            detail: formData,
            bubbles: true,
            composed: true
        });
        this.dispatchEvent(saveEvent);
    }

    get dayOfMonthOptionsOverrideValue() {
        if(this.overrideDefaultFlow && this.dayOfMonthOptionsOverride){
            const days = this.dayOfMonthOptionsOverride.split(',').map(day => day.trim());
            return days.map(day => {
                const dayNum = parseInt(day);
                let suffix = 'th';
                if(dayNum === 1 || dayNum === 21 || dayNum === 31) suffix = 'st';
                else if(dayNum === 2 || dayNum === 22) suffix = 'nd';
                else if(dayNum === 3 || dayNum === 23) suffix = 'rd';
                
                return {
                    label: `${dayNum}${suffix}`,
                    value: dayNum + ''
                };
            });
        }
    }

    get defaultTableColumns() {
        const cols = [
            { label: 'Installment #', key: 'instalmentNo', align: 'center' },
            { label: 'Due Date', key: 'dueDate', align: 'center' },
            { label: 'Payment Amount', key: 'instalmentAmount', align: 'right' },
            { label: 'Principal Paid', key: 'principalComp', align: 'right' }
        ];
        if (this.accurateInterest) {
            cols.push(
                { label: 'Interest Calculated', key: 'interestRaw', align: 'right' },
                { label: 'Interest Paid', key: 'interestComp', align: 'right' },
                { label: 'Carry Forward', key: 'carryForward', align: 'right' }
            );
        } else {
            cols.push({ label: 'Interest Paid', key: 'interestComp', align: 'right' });
        }
        cols.push(
            { label: 'EMI Days Considered', key: 'emiDenominator', align: 'center' },
            { label: 'Interest Days', key: 'interestCalculationDays', align: 'center' },
            { label: 'Principal Days', key: 'principalDays', align: 'center' },
            { label: 'Opening Balance', key: 'openingPrinciple2', align: 'right' },
            { label: 'Closing Balance', key: 'closingPrinciple', align: 'right' }
        );
        return cols;
    }

    get emiFormulaText() {
        const P = this.principal ? Number(this.principal).toLocaleString('en-IN') : '0';
        const r = this.irr || '0';
        const n = this.tenure || '0';
        const freq = this.frequency || '1';
        const installments = Math.floor((this.tenure || 0) / (parseInt(this.frequency) || 1));

        let formula = `EMI = P × r × (1+r)ⁿ / [(1+r)ⁿ − 1]`;
        formula += `\nWhere: P = ₹${P}, Annual Rate = ${r}%, r (monthly) = ${r}/1200`;
        formula += `, n = ${installments} installments`;

        if (this.firstMonthPreEmi30days) {
            formula += `\n\nFirst Month Pre-EMI Prorate: Base EMI calculated using 30/360 convention.`;
            formula += `\nFirst EMI = (Base EMI / Actual Days in Month) × Actual Days in Period`;
            formula += `\nSubsequent EMIs = Base EMI (30/360)`;
        }

        if (this.daysInMonthMethod === 'ACTUAL') {
            formula += `\nDays in Month: ACTUAL`;
        } else {
            formula += `\nDays in Month: ${this.daysInMonthMethod || '30'} (Fixed)`;
        }
        formula += `, Days in Year: ${this.daysInYearMethod || '365'}`;

        return formula;
    }

    _alignToClass(align) {
        const map = { center: 'slds-text-align_center', right: 'slds-text-align_right', left: 'slds-text-align_left' };
        return map[align] || 'slds-text-align_left';
    }

    get displayTableColumns() {
        let cols = this.defaultTableColumns;
        if (this.tableColumns) {
            try {
                const parsed = typeof this.tableColumns === 'string' ? JSON.parse(this.tableColumns) : this.tableColumns;
                if (Array.isArray(parsed) && parsed.length > 0) cols = parsed;
            } catch (e) {
                console.warn('Invalid tableColumns, using default:', e);
            }
        }
        return cols.map(c => ({
            ...c,
            alignClass: this._alignToClass(c.align)
        }));
    }

    get tableRowsWithCells() {
        const columns = this.displayTableColumns;
        const data = this.scheduleData;
        return data.map((row, idx) => ({
            rowKey: row.instalmentNo || idx,
            cells: columns.map(col => ({
                key: col.key,
                value: row[col.key] ?? '',
                alignClass: col.alignClass
            }))
        }));
    }

    get frequencyOptions() {
        return [
            { label: 'Monthly', value: '1' },
            { label: 'Quarterly', value: '3' },
            { label: 'Half-Yearly', value: '6' },
            { label: 'Yearly', value: '12' }
        ];
    }

    get dayOfMonthOptions() {
        return [
            { label: '1st', value: '1' },
            { label: '5th', value: '5' },
            { label: '10th', value: '10' },
            { label: '15th', value: '15' },
            { label: '20th', value: '20' },
            { label: '25th', value: '25' }
        ];
    }

    get repaymentTypeOptions() {
        return [
            { label: 'Equated EMI', value: 'EQUATED_EMI' },
            { label: 'Equated Principal', value: 'EQUATED_PRINCIPAL' }
        ];
    }

    get preEmiTypeOptions() {
        return [
            { label: 'None', value: 'NONE' },
            { label: 'Pre-EMI Period', value: 'SIMPLE' }
        ];
    }

    get capitalizationTypeOptions() {
        return [
            { label: 'Monthly', value: 'MONTHLY' },
            { label: 'Quarterly', value: 'QUARTERLY' },
            { label: 'Yearly', value: 'YEARLY' },
            { label: 'At End of Moratorium', value: 'END_OF_MORATORIUM' }
        ];
    }

    get moratoriumPaymentOptions() {
        return [
            { label: 'No Payment (Full Interest Capitalizes)', value: 'NO_PAYMENT' },
            { label: 'Partial Interest Payment', value: 'PARTIAL_INTEREST' },
            { label: 'Interest Only (No Capitalization)', value: 'INTEREST_ONLY' }
        ];
    }

    get calculationModeOptions() {
        return [
            { label: 'Fixed (30/360)', value: 'FIXED' },
            { label: 'Floating (Actual/365)', value: 'FLOATING' }
        ];
    }

    get daysInYearOptions() {
        return [
            { label: 'Actual (Leap Year Detection)', value: 'ACTUAL' },
            { label: 'Always 360 Days', value: '360' },
            { label: 'Always 365 Days', value: '365' }
        ];
    }

    get daysInMonthOptions() {
        return [
            { label: 'Actual Days (28/29/30/31)', value: 'ACTUAL' },
            { label: 'Always 30 Days', value: '30' },
            { label: 'Always 31 Days', value: '31' }
        ];
    }

    get showPartialAmount() {
        return this.moratoriumInterestPayment === 'PARTIAL_INTEREST';
    }

    get showMoratoriumFields() {
        return this.moratoriumMonths > 0;
    }

    get showPreEmiCustomDates() {
        return this.preEmiType === 'CUSTOM';
    }

    get showPreEmiMonthsInput() {
        return this.preEmiType === 'SIMPLE';
    }

    get showPreEmiCalculatedMonths() {
        return this.preEmiType === 'CUSTOM';
    }

    get showPreEmiFields() {
        return this.preEmiType !== 'NONE';
    }

    get showCapitalizationField() {
        return this.showPreEmiFields || this.showMoratoriumFields;
    }

    get preEmiMessage() {
        if (this.preEmiType === 'NONE') return '';
        return 'Note: During Pre-EMI period, only interest is calculated. No principal repayment occurs during this period.';
    }

    get daysCalculationDisabled() {
        return true;
    }

    get showProrateMessage() {
        if (this.loanDate && this.repaymentDate) {
            const loanDateObj = new Date(this.loanDate);
            const repaymentDateObj = new Date(this.repaymentDate);
            const diffTime = Math.abs(repaymentDateObj - loanDateObj);
            const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
            return diffDays < 30;
        }
        return false;
    }

    get prorateInterestMessage() {
        if (this.overrideProrateInterest) {
            return 'Note: Complete EMI will be calculated for the first installment (prorate override is enabled).';
        }
        return 'Note: Prorated interest will be calculated for the first EMI since the period between loan start date and first EMI date is less than 30 days.';
    }

    connectedCallback() {
        this.loadLibraries();
        this.handleLoadDateForOverrideDefaultFlow();
    }

    async loadLibraries() {
        try {
            await loadScript(this, SHEETJS);
            this.sheetJSInitialized = true;
        } catch (error) {
            console.error('Error loading libraries:', error);
            this.showToast('Error', 'Failed to load required libraries: ' + error.message, 'error');
        }
    }

    handlePrincipalChange(event) {
        this.principal = parseInt(event.target.value) || 0;
    }

    handleIRRChange(event) {
        this.irr = event.target.value;
    }

    handleLoanDateChange(event) {
        this.loanDate = event.target.value;
        this.autoCalculateFirstEMIDate();
    }

    handleTenureChange(event) {
        this.tenure = parseInt(event.target.value) || 0;
    }

    handleDayChange(event) {
        this.day = parseInt(event.target.value);
        this.autoCalculateFirstEMIDate();
    }

    handleFrequencyChange(event) {
        this.frequency = event.target.value;
    }

    handleRepaymentDateChange(event) {
        this.repaymentDate = event.target.value;
    }

    handleRepaymentTypeChange(event) {
        this.repaymentType = event.target.value;
    }

    handleMoratoriumMonthsChange(event) {
        this.moratoriumMonths = parseInt(event.target.value) || 0;
    }

    handleMoratoriumPaymentChange(event) {
        this.moratoriumInterestPayment = event.target.value;
    }

    handleMoratoriumPartialAmountChange(event) {
        this.moratoriumPartialAmount = parseInt(event.target.value) || 0;
    }

    handleCalculationModeChange(event) {
        this.calculationMode = event.target.value;
        if (this.calculationMode === 'FIXED') {
            this.daysInMonthMethod = '30';
            this.daysInYearMethod = '360';
        } else if (this.calculationMode === 'FLOATING') {
            this.daysInMonthMethod = 'ACTUAL';
            this.daysInYearMethod = '365';
        }
    }

    handleDaysInYearMethodChange(event) {
        this.daysInYearMethod = event.target.value;
    }

    handleDaysInMonthMethodChange(event) {
        this.daysInMonthMethod = event.target.value;
    }

    handlePreEmiTypeChange(event) {
        this.preEmiType = event.target.value;
        if (this.preEmiType === 'NONE') {
            this.preEmiMonths = 0;
            this.preEmiStartDate = null;
            this.preEmiEndDate = null;
        } else if (this.preEmiType === 'SIMPLE') {
            this.preEmiStartDate = null;
            this.preEmiEndDate = null;
            if (!this.preEmiMonths) {
                this.preEmiMonths = 0;
            }
        }
    }

    handlePreEmiStartDateChange(event) {
        this.preEmiStartDate = event.target.value;
        this.calculateCustomPreEmiMonths();
    }

    handlePreEmiEndDateChange(event) {
        this.preEmiEndDate = event.target.value;
        this.calculateCustomPreEmiMonths();
    }

    handlePreEmiMonthsChange(event) {
        this.preEmiMonths = parseInt(event.target.value) || 0;
    }

    handleCapitalizationTypeChange(event) {
        this.capitalizationType = event.target.value;
    }

    handleOverrideProrateChange(event) {
        this.overrideProrateInterest = event.target.checked;
    }

    handleAccurateInterestChange(event) {
        this.accurateInterest = event.target.checked;
    }

    handleFirstMonthPreEmi30daysChange(event) {
        this.firstMonthPreEmi30days = event.target.checked;
    }

    handleTreatFirstMonthAsPreEmiChange(event) {
        this.treatFirstMonthAsPreEmi = event.target.checked;
    }

    calculateCustomPreEmiMonths() {
        if (this.preEmiStartDate && this.preEmiEndDate) {
            const startDate = new Date(this.preEmiStartDate);
            const endDate = new Date(this.preEmiEndDate);
            
            const diffTime = endDate - startDate;
            if (diffTime > 0) {
                const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
                if (diffDays < 30) {
                    this.preEmiMonths = 1;
                } else {
                    const diffMonths = (endDate.getFullYear() - startDate.getFullYear()) * 12 + 
                                       (endDate.getMonth() - startDate.getMonth());
                    this.preEmiMonths = diffMonths > 0 ? diffMonths : 1;
                }
            } else {
                this.preEmiMonths = 0;
            }
        }
    }

    autoCalculateFirstEMIDate() {
        if (this.loanDate && this.day) {
            if(this.overrideDefaultFlow){
                const loanDateParts = this.loanDate.split('-');
                const loanYear = parseInt(loanDateParts[0]);
                const loanMonth = parseInt(loanDateParts[1]) - 1;
                const loanDay = parseInt(loanDateParts[2]);
                
                let targetYear = loanYear;
                let targetMonth = loanMonth;
                
                let monthsToAdd = 0;
                if(loanDay >= 1 && loanDay <= 15){
                    monthsToAdd = 1;
                } else {
                    monthsToAdd = 2;
                }
                
                targetMonth += monthsToAdd;
                while(targetMonth > 11){
                    targetYear += 1;
                    targetMonth -= 12;
                }
                
                const selectedDay = parseInt(this.day);
                const maxDayInMonth = new Date(targetYear, targetMonth + 1, 0).getDate();
                const finalDay = Math.min(selectedDay, maxDayInMonth);
                
                const emiDate = new Date(targetYear, targetMonth, finalDay);
                const year = emiDate.getFullYear();
                const month = String(emiDate.getMonth() + 1).padStart(2, '0');
                const day = String(emiDate.getDate()).padStart(2, '0');
                this.repaymentDate = `${year}-${month}-${day}`;
                return;
            }
            
            const loanDateObj = new Date(this.loanDate);
            let emiDate = new Date(loanDateObj);
            emiDate.setMonth(emiDate.getMonth() + 1);
            emiDate.setDate(this.day);
            
            const maxDayInMonth = new Date(emiDate.getFullYear(), emiDate.getMonth() + 1, 0).getDate();
            if (this.day > maxDayInMonth) {
                emiDate.setDate(maxDayInMonth);
            }
            
            this.repaymentDate = emiDate.toISOString().split('T')[0];
        }
    }

    formatDateToUserFriendly(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString + 'T00:00:00');
        const day = date.getDate();
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                           'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const month = monthNames[date.getMonth()];
        const year = date.getFullYear();
        return `${day.toString().padStart(2, '0')}-${month}-${year}`;
    }

    async handleCalculate() {
        this.isLoading = true;
        this.showResults = false;

        try {
            if(this.overrideDefaultFlow){
                const allInputs = Array.from(this.template.querySelectorAll('lightning-input, lightning-combobox'));
                const requiredInputs = allInputs.filter(input => input.required === true);
                
                const allValid = requiredInputs.length > 0 ? requiredInputs.reduce((validSoFar, inputCmp) => {
                    if (inputCmp.disabled) return validSoFar;
                    
                    let isValid = true;
                    if (inputCmp.tagName === 'LIGHTNING-INPUT' && inputCmp.type === 'date') {
                        const value = inputCmp.value;
                        if (!value || (typeof value === 'string' && value.trim() === '')) {
                            inputCmp.setCustomValidity('This field is required');
                            isValid = false;
                        } else {
                            inputCmp.setCustomValidity('');
                        }
                    }
                    
                    if (isValid) {
                        inputCmp.reportValidity();
                        isValid = inputCmp.checkValidity();
                    } else {
                        inputCmp.reportValidity();
                    }
                    
                    return validSoFar && isValid;
                }, true) : true;

                if (!allValid) {
                    this.showToast('Validation Error', 'Please fill in all required fields.', 'error');
                    this.isLoading = false;
                    return;
                }
            }
            
            if (this.preEmiType === 'SIMPLE' && this.preEmiMonths > 0 && this.moratoriumMonths > 0) {
                this.showToast('Validation Error', 
                    'Pre-EMI Period and Moratorium Period cannot exist together. Please select only one.', 
                    'error');
                this.isLoading = false;
                return;
            }

            if(this.overrideDefaultFlow){
                if(this.moratoriumMonths >= this.tenure){
                    this.showToast('Validation Error', 
                        'Moratorium period cannot exceed tenure. Please reduce moratorium period.', 
                        'error');
                    this.isLoading = false;
                    return;
                }
            }

            const result = await emiRepaymentScheduleHlEnhanced({
                principal: this.principal,
                irr: this.irr,
                loanDate: this.loanDate,
                tenure: this.tenure,
                day: this.day,
                frequency: this.frequency,
                repaymentDate: this.repaymentDate,
                repaymentType: this.repaymentType,
                moratoriumMonths: this.moratoriumMonths,
                moratoriumInterestPayment: this.moratoriumInterestPayment,
                moratoriumPartialAmount: this.moratoriumPartialAmount,
                calculationMode: this.calculationMode,
                daysInYearMethod: this.daysInYearMethod,
                daysInMonthMethod: this.daysInMonthMethod,
                preEmiType: this.preEmiType,
                preEmiMonths: this.preEmiMonths,
                preEmiStartDate: this.preEmiStartDate || null,
                preEmiEndDate: this.preEmiEndDate || null,
                capitalizationType: this.capitalizationType,
                overrideProrateInterest: this.overrideProrateInterest,
                accurateInterest: this.accurateInterest,
                firstMonthPreEmi30days: this.firstMonthPreEmi30days,
                treatFirstMonthAsPreEmi: this.treatFirstMonthAsPreEmi
            });

            const formatDate = this.formatDateToUserFriendly.bind(this);
            
            this.scheduleData = result.map(row => {
                return {
                    instalmentNo: row.instalmentNo,
                    dueDate: formatDate(row.dueDate),
                    days: row.days,
                    interestCalculationDays: row.interestCalculationDays || row.days,
                    principalDays: row.principalDays != null ? row.principalDays : row.days,
                    fullEmiDays: row.fullEmiDays || row.days,
                    openingPrinciple2: row.openingPrinciple2,
                    instalmentAmount: row.instalmentAmount,
                    principalComp: row.principalComp,
                    interestRaw: row.interestRaw,
                    interestComp: row.interestCompExact != null ? row.interestCompExact : row.interestComp,
                    carryForward: row.carryForward,
                    closingPrinciple: row.closingPrinciple,
                    irr: row.irr,
                    emiDenominator: row.emiDenominator
                };
            });
            
            this.showResults = true;
            this.showToast('Success', `Generated ${result.length} installments`, 'success');
        } catch (error) {
            console.error('Error:', error);
            this.showToast('Error', error.body?.message || error.message || 'Failed to calculate repayment schedule', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleExportToExcel() {
        if (!this.sheetJSInitialized) {
            this.showToast('Error', 'Excel library not loaded yet. Please wait and try again.', 'error');
            return;
        }

        if (!this.scheduleData || this.scheduleData.length === 0) {
            this.showToast('Warning', 'No data to export. Please calculate schedule first.', 'warning');
            return;
        }

        try {
            const columns = this.displayTableColumns;
            const excelData = this.scheduleData.map(row => {
                const excelRow = {};
                columns.forEach(col => {
                    const val = row[col.key];
                    excelRow[col.label] = val !== undefined && val !== null ? val : '';
                });
                return excelRow;
            });

            const wb = window.XLSX.utils.book_new();
            const ws = window.XLSX.utils.json_to_sheet(excelData);

            ws['!cols'] = columns.map(col => ({
                wch: Math.min(Math.max(col.label.length + 2, 12), 30)
            }));

            window.XLSX.utils.book_append_sheet(wb, ws, 'Repayment Schedule');

            const filename = `RPSV2_Schedule_${this.repaymentType}_${new Date().getTime()}.xlsx`;
            window.XLSX.writeFile(wb, filename);

            this.showToast('Success', 'Excel file downloaded successfully', 'success');
        } catch (error) {
            console.error('Error generating Excel:', error);
            this.showToast('Error', 'Failed to generate Excel file', 'error');
        }
    }

    handleReset() {
        this.principal = 500000;
        this.irr = '10';
        this.loanDate = new Date().toISOString().split('T')[0];
        this.tenure = 36;
        this.day = 1;
        this.frequency = '1';
        this.repaymentDate = new Date(new Date().setMonth(new Date().getMonth() + 1)).toISOString().split('T')[0];
        this.repaymentType = 'EQUATED_EMI';
        this.moratoriumMonths = 0;
        this.moratoriumInterestPayment = 'NO_PAYMENT';
        this.moratoriumPartialAmount = 0;
        this.calculationMode = 'FLOATING';
        this.daysInYearMethod = '365';
        this.daysInMonthMethod = 'ACTUAL';
        this.preEmiType = 'NONE';
        this.preEmiStartDate = null;
        this.preEmiEndDate = null;
        this.preEmiMonths = 0;
        this.capitalizationType = 'MONTHLY';  
        this.overrideProrateInterest = false;
        this.accurateInterest = false;
        this.firstMonthPreEmi30days = false;
        this.treatFirstMonthAsPreEmi = false;
        this.scheduleData = [];
        this.showResults = false;
    }

    formatNumber(value) {
        return new Intl.NumberFormat('en-IN').format(value || 0);
    }

    formatDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        return date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
    }

    formatCurrency(value) {
        return new Intl.NumberFormat('en-IN', { 
            style: 'currency',
            currency: 'INR',
            minimumFractionDigits: 0
        }).format(value || 0);
    }

    showToast(title, message, variant) { 
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}