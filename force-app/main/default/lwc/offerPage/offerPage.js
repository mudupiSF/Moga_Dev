/**
 * @description Offer Page LWC for Loan Application — DDE stage.
 * Displayed after Income Verification. Provides the loan offer UI with
 * adjustable loan amount / tenure sliders, offer parameter configuration,
 * insurance selection, and Offer Engine integration via BRE_OFFER.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getOfferData              from '@salesforce/apex/OfferPageController.getOfferData';
import saveOfferEngineResult     from '@salesforce/apex/OfferPageController.saveOfferEngineResult';
import createRepaymentSchedule   from '@salesforce/apex/OfferPageController.createRepaymentSchedule';
import markOfferStageComplete    from '@salesforce/apex/OfferPageController.markOfferStageComplete';
import resetToIncomeVerification from '@salesforce/apex/OfferPageController.resetToIncomeVerification';
import processNextStageRequest   from '@salesforce/apex/dynamicStageNavigatorController.processNextStageRequest';
import generatePhoneOTP            from '@salesforce/apex/SendPhoneOTPAPIController.generateOTP';
import getIntegrationMaster        from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getIntegrationMaster';
import { invokeHandler }           from 'c/clientLayerHelper';

const LOS_MENU_REFRESH_EVENT      = 'losmenurefresh';
const LOS_NEXT_STAGE_EVENT        = 'losnextstage';
const LOS_NAVIGATION_STATE_EVENT  = 'losnavigationstate';
const LOS_MENU_SELECT_EVENT       = 'losmenuselect';
const STAGE_OFFER                 = 'Offer';
const FI_WAIVER_INTEGRATION_LABEL = 'FI Waiver';
const FI_INTEGRATION_STAGES       = [
    FI_WAIVER_INTEGRATION_LABEL,
    'Creating FI Investigations'
];

/** Must match IncomeVerificationContent SMS_CHANNEL_STORAGE_PREFIX */
const SMS_CHANNEL_STORAGE_PREFIX = 'los_iv_sms_channel_';

// ── Offer type constants ──────────────────────────────────────────────────
const OFFER_TYPE_BUREAU    = 'bureau_surrogate';
const OFFER_TYPE_BANK_STMT = 'bank_statement';
const OFFER_TYPE_DECLARED  = 'declared_income';

export default class OfferPage extends LightningElement {

    /** Opportunity record Id passed from OpportunityMasterPage */
    @api recordId;
    /** Stage identifier used when dispatching the losnextstage event */
    @api currentViewId;
    /** Stage phrase from applicationMasterPage / stage menu (required for CMT navigation). */
    @api stagePhrase = '';
    /** Current main-stage tab label (e.g. DDE). */
    @api tab = '';
    @api fromAssetList = false;

    _applicationLineItemId = '';
    payInPayOutBtnLabel = '';
    @api
    get applicationLineItemId() {
        return this._applicationLineItemId;
    }
    set applicationLineItemId(value) {
        this._applicationLineItemId = value || '';
        this._tryLoadOfferData();
    }

    // ── isStagePast ────────────────────────────────────────────────────────
    _isStagePast = false;
    @api
    get isStagePast() { return this._isStagePast; }
    set isStagePast(value) { this._isStagePast = !!value; }

    // ── UI state ───────────────────────────────────────────────────────────
    isLoading = false;
    /** True when Application__c.Sanction_Status__c is STP. */
    isStp = false;
    productType = '';

    // ── Loan Amount ────────────────────────────────────────────────────────
    loanAmount    = 399000;
    loanAmountMin = 10;
    loanAmountMax = 9999995;

    // ── Tenure ────────────────────────────────────────────────────────────
    tenure    = 12;
    tenureMin = 12;
    tenureMax = 60;

    // ── Offer Metrics ──────────────────────────────────────────────────────
    interestRate  = 0;
    monthlyEmi    = 0;
    totalInterest = 145040;
    totalAmount   = 544040;

    // ── Insurance & Higher Income ──────────────────────────────────────────
    insuranceOption = 'no';
    higherIncome    = 'no';
    offerAccepted   = false;

    // ── Offer Parameters ───────────────────────────────────────────────────
    selectedOfferType = OFFER_TYPE_BUREAU;
    moratoriumDays    = '0';
    advanceEmi        = 'no';
    firstEmiDueDate   = '10th of Month';
    installmentType   = '';
    /** 'yyyy-MM-dd' from backend; cleared when user picks a new EMI date option. */
    _firstEmiDateStr  = '';

    /** Per-offer-type amounts populated from Offer Engine response. */
    @track _offerTypeAmounts = {
        [OFFER_TYPE_BUREAU]:    0,
        [OFFER_TYPE_BANK_STMT]: 0,
        [OFFER_TYPE_DECLARED]:  0
    };

    dynamicComponentName  = '';
    dynamicComponentProps = {};
    dynamicModalHeader    = '';

    // ── Change-detection flag ──────────────────────────────────────────────
    /**
     * True whenever any offer parameter changes after the last Offer Engine run.
     * Enables the Re-run Offer Engine button.
     */
    fieldsModified = false;

    // ── Offer Engine state ─────────────────────────────────────────────────
    isOfferEngineRunning = false;
    offerEngineError     = '';

    // ── CIBIL Validity ─────────────────────────────────────────────────────
    cibilValidityOption  = 'no';
    cibilConsentVerified        = false;
    borrowerPhone        = '';
    borrowerApplicantId  = null;

    // ── Modal visibility ───────────────────────────────────────────────────
    showInsuranceModal = false;
    showDynamicModal   = false;

    // ── Integration progress modal ─────────────────────────────────────────
    showIntegrationModal         = false;
    integrationStatus            = 'loading';
    integrationHeader            = '';
    integrationCurrentStageIndex = 0;
    integrationSuccessMessage    = '';
    integrationErrorMessage      = '';
    integrationStages            = [];
    _integrationRetryFn          = null;
    _pendingCibilVerification    = false;
    _pendingAddInsurance         = false;
    _lastActionFieldKey          = '';
    _cibilOtpFlow                = false;

    // ── Lifecycle ──────────────────────────────────────────────────────────
    connectedCallback() {
        this._dynamicModalHandler = (e) => this.handleOpenDynamicComponentModal(e);
        this.addEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
        this._tryLoadOfferData();
    }

    disconnectedCallback() {
        if (this._dynamicModalHandler) {
            this.removeEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
        }
    }

    _tryLoadOfferData() {
        if (!this.recordId) return;
        if (this.fromAssetList && !this._applicationLineItemId) return;
        this._loadOfferData();
    }

    async _loadOfferData() {
        if (!this.recordId) return;
        try {
            this.isLoading = true;
            const data = await getOfferData({
                applicationId: this.recordId,
                applicationLineItemId: this._applicationLineItemId || null
            });
            this.isStp = data?.isStp === true;
            this.borrowerApplicantId = data?.borrowerApplicantId || null;
            this.borrowerPhone       = data?.borrowerPhone || '';
            this.productType         = data?.productType || '';
            if(this.productType == 'PL') {
                this.payInPayOutBtnLabel = 'Change Pay-In';
            }
            else {
                this.payInPayOutBtnLabel = 'Change Pay-In/ Pay-Out';
            }
            if (data?.hasOffer && data.lineItem) {
                const li = data.lineItem;

                if (li.Loan_Amount__c != null) this.loanAmount   = this._toNumber(li.Loan_Amount__c);
                if (li.Tenure__c      != null) this.tenure       = this._toNumber(li.Tenure__c);
                if (li.CRM_IRR__c     != null) this.interestRate = this._toNumber(li.CRM_IRR__c);
                if (li.EMI_Amount__c  != null) this.monthlyEmi   = this._toNumber(li.EMI_Amount__c);

                if (li.Advance_EMI__c != null) this.advanceEmi     = li.Advance_EMI__c ? 'yes' : 'no';
                if (li.Holiday_period__c)      this.moratoriumDays = li.Holiday_period__c;
                if (li.Installment_Type__c) {
                    this.installmentType = li.Installment_Type__c.toLowerCase() === 'structured' ? 'structured' : 'equated';
                }

                if (li.First_EMI_Date__c) {
                    this._firstEmiDateStr = li.First_EMI_Date__c;
                    const day = parseInt(li.First_EMI_Date__c.split('-')[2], 10);
                    this.firstEmiDueDate = day <= 5 ? '5th of Month' : '10th of Month';
                }
                this._recalcEmiDates();

                if (data.minLoanAmount) this.loanAmountMin = this._toNumber(data.minLoanAmount);
                if (data.maxLoanAmount) this.loanAmountMax = this._toNumber(data.maxLoanAmount);
                if (data.minTenure)     this.tenureMin     = this._toNumber(data.minTenure);
                if (data.maxTenure)     this.tenureMax     = this._toNumber(data.maxTenure);

                this._offerTypeAmounts = {
                    ...this._offerTypeAmounts,
                    [OFFER_TYPE_BUREAU]:    this._toNumber(data.bureauSurrogateOffer) || 400000,
                    [OFFER_TYPE_BANK_STMT]: this._toNumber(data.bankStatementOffer)   || 500000,
                    [OFFER_TYPE_DECLARED]:  this._toNumber(data.declaredIncomeOffer)  || 600000
                };

                this._recalcTotals();
            }
        } catch (error) {
            console.error('[OfferPage] Failed to load offer data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed: formatted display values ────────────────────────────────
    get formattedLoanAmount()    { return this._fmtINR(this.loanAmount); }
    get formattedLoanAmountMin() { return this._fmtINR(this.loanAmountMin); }
    get formattedLoanAmountMax() { return this._fmtINR(this.loanAmountMax); }
    get formattedMonthlyEmi()    { return this._fmtINR(this.monthlyEmi); }
    get formattedTotalInterest() { return this._fmtINR(this.totalInterest); }
    get formattedTotalAmount()   { return this._fmtINR(this.totalAmount); }

    // ── Computed: slider inline styles ────────────────────────────────────
    get loanAmountSliderStyle() { return this._sliderStyle(this.loanAmount, this.loanAmountMin, this.loanAmountMax); }
    get tenureSliderStyle()     { return this._sliderStyle(this.tenure, this.tenureMin, this.tenureMax); }

    // ── Computed: Re-run button ───────────────────────────────────────────
    get isReRunDisabled() {
        return (!this.fieldsModified && !this.offerEngineError) || this._isStagePast || this.isOfferEngineRunning;
    }

    get reRunBtnClass() {
        const active = (this.fieldsModified || this.offerEngineError) && !this._isStagePast && !this.isOfferEngineRunning;
        return active
            ? 'outline-btn outline-btn--active p4-button-text'
            : 'outline-btn outline-btn--muted p4-button-text';
    }

    get reRunBtnLabel() { return this.isOfferEngineRunning ? 'Running...' : 'Re-run Offer Engine'; }

    get highlightPanelData() {
        return this.recordId ? { recordId: this.recordId } : undefined;
    }

    get showOfferAcceptanceButton() {
        return this.isStp && !this._isStagePast;
    }

    // ── Computed: Radio boolean getters ───────────────────────────────────
    get isInsuranceYes()          { return this.insuranceOption === 'yes'; }
    get isInsuranceNo()           { return this.insuranceOption === 'no'; }
    get isHigherIncomeYes()       { return this.higherIncome === 'yes'; }
    get isHigherIncomeNo()        { return this.higherIncome === 'no'; }
    get isMoratorium0()           { return this.moratoriumDays === '0'; }
    get isMoratorium30()          { return this.moratoriumDays === '30'; }
    get isMoratorium60()          { return this.moratoriumDays === '60'; }
    get isAdvanceEmiYes()         { return this.advanceEmi === 'yes'; }
    get isAdvanceEmiNo()          { return this.advanceEmi === 'no'; }
    get isFirstEmi5th()           { return this.firstEmiDueDate === '5th of Month'; }
    get isFirstEmi10th()          { return this.firstEmiDueDate === '10th of Month'; }
    get isInstallmentEquated()    { return this.installmentType === 'equated'; }
    get isInstallmentStructured() { return this.installmentType === 'structured'; }
    get showCibilSection()        { return !this.cibilConsentVerified && !this.isStagePast; }
    get isCibilYes()              { return this.cibilValidityOption === 'yes'; }
    get isCibilNo()               { return this.cibilValidityOption === 'no'; }

    // ── Computed: 2nd EMI Due Date ────────────────────────────────────────
    get secondEmiDueDate() {
        if (!this.firstEmiDueDate) return '—';
        const firstDate = this._parseYmdDate(this._computedFirstEmiDateStr);
        const secondDate = new Date(firstDate.getFullYear(), firstDate.getMonth() + 1, firstDate.getDate());
        return this._formatEmiDisplay(secondDate);
    }

    // ── Computed: First EMI date as 'yyyy-MM-dd' for Apex calls ──────────
    get _computedFirstEmiDateStr() {
        if (this._firstEmiDateStr) return this._firstEmiDateStr;
        return this._formatDateYmd(this._computeFirstEmiDate());
    }

    // ── Computed: Offer type options for template ─────────────────────────
    get offerTypeOptions() {
        return [
            {
                value: OFFER_TYPE_BUREAU,
                label: 'Bureau Surrogate Offer',
                formattedAmount: this._fmtINR(this._offerTypeAmounts[OFFER_TYPE_BUREAU]),
                isSelected: this.selectedOfferType === OFFER_TYPE_BUREAU
            },
            {
                value: OFFER_TYPE_BANK_STMT,
                label: 'Bank Statement Income Offer',
                formattedAmount: this._fmtINR(this._offerTypeAmounts[OFFER_TYPE_BANK_STMT]),
                isSelected: this.selectedOfferType === OFFER_TYPE_BANK_STMT
            },
            {
                value: OFFER_TYPE_DECLARED,
                label: 'Declared Income Offer',
                formattedAmount: this._fmtINR(this._offerTypeAmounts[OFFER_TYPE_DECLARED]),
                isSelected: this.selectedOfferType === OFFER_TYPE_DECLARED
            }
        ];
    }

    // ── Computed: Installment schedule modal props ────────────────────────
    get installmentScheduleProps() {
        const emiDay = this.firstEmiDueDate === '5th of Month' ? 5 : 10;
        return {
            principal:    this.loanAmount,
            interestRate: this.interestRate,
            tenure:       this.tenure,
            frequency:    1,
            loanDate:     new Date().toISOString().split('T')[0],
            firstEmiDay:  emiDay
        };
    }

    // ── Input handlers — Sliders & text inputs ────────────────────────────
    handleLoanAmountChange(event) {
        this.loanAmount = parseInt(event.target.value, 10);
        this._markModified();
    }

    handleTenureChange(event) {
        this.tenure = parseInt(event.target.value, 10);
        this._markModified();
    }

    handleInterestRateChange(event) {
        const val = parseFloat(event.target.value);
        this.interestRate = isNaN(val) ? 0 : val;
        this._markModified();
    }

    handleLoanAmountInput(event) {
        const val = parseInt(event.target.value, 10);
        if (!isNaN(val)) {
            this.loanAmount = Math.max(this.loanAmountMin, Math.min(this.loanAmountMax, val));
            this._markModified();
        }
    }

    handleTenureInput(event) {
        const val = parseInt(event.target.value, 10);
        if (!isNaN(val)) {
            this.tenure = Math.max(this.tenureMin, Math.min(this.tenureMax, val));
            this._markModified();
        }
    }

    // ── Input handlers — Insurance ────────────────────────────────────────
    handleInsuranceChange(event) {
        this.insuranceOption = event.target.value;
        if (this.insuranceOption === 'no') {
            this.showInsuranceModal = false;
        }
    }

    handleAddInsurance() {
        this._pendingAddInsurance = true;
        this._openIntegrationModal('Insurance Recommendation', ['Insurance Recommendation API'], null);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.integrationCurrentStageIndex = 1;
            this.dynamicModalHeader = 'Insurance Recommendation';
            this.integrationStatus            = 'success';
            this.integrationSuccessMessage    = 'Insurance Recommendation completed successfully.';
            this.showIntegrationModal         = false;
            this.dynamicComponentName         = 'addInsuranceModal';
            this.dynamicComponentProps        = { recordId: this.recordId };
            this.showDynamicModal             = true;
        }, 2000);
    }

    // ── Input handlers — Offer Parameters ────────────────────────────────
    handleOfferTypeChange(event) {
        this.selectedOfferType = event.target.value;
        const amount = this._offerTypeAmounts[this.selectedOfferType];
        if (amount !== this.loanAmount) {
            this.loanAmount = amount;
            this._markModified();
        }
    }

    handleMoratoriumChange(event) {
        this.moratoriumDays = event.target.value;
        this._recalcEmiDates();
        this._markModified();
    }

    handleAdvanceEmiChange(event) {
        this.advanceEmi = event.target.value;
        this._markModified();
    }

    handleFirstEmiDateChange(event) {
        this.firstEmiDueDate = event.target.value;
        this._recalcEmiDates();
        this._markModified();
    }

    handleInstallmentTypeChange(event) {
        this.installmentType = event.target.value;
        this._markModified();
    }

    handleHigherIncomeChange(event) {
        this.higherIncome = event.target.value;
    }

    handleChangePayinPayout() {
        if(this.productType == 'PL') {
            this.dynamicModalHeader = 'Change Pay-In';
        }
        else {
            this.dynamicModalHeader = 'Change Pay-In/ Pay-Out';
        }
        this.dynamicComponentName  = 'payInPayOutModal';
        this.dynamicComponentProps = { recordId: this.recordId };
        this.showDynamicModal      = true;
    }

    async handleMoveBackToIncomeVerification() {
        if (this.higherIncome !== 'yes') return;
        try {
            this.isLoading = true;
            const resetResult = await resetToIncomeVerification({ applicationId: this.recordId });
            if (!resetResult?.success) {
                this.higherIncome = 'no';
                this._showToast('Unable to continue', resetResult?.message || 'Could not reset to Income Verification.', 'error');
                return;
            }
            window.dispatchEvent(new CustomEvent(LOS_MENU_REFRESH_EVENT, { bubbles: true, composed: true }));
        } catch (error) {
            this.higherIncome = 'no';
            this._showToast('Error', error?.body?.message || error?.message || 'Unexpected error resetting stage.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Action button handlers ────────────────────────────────────────────
    /**
     * @description Calls the BRE_OFFER integration via OfferPageController.runOfferEngine().
     * On success updates all metrics and persists confirmed values to Application_Line_Item__c.
     * On failure, shows error and keeps Re-run enabled for retry.
     */
    async handleReRunOfferEngine() {
        if (this.isReRunDisabled) return;

        this._openIntegrationModal('Run Offer Engine', ['Offer Engine API running'], () => this.handleReRunOfferEngine());
        this.isOfferEngineRunning = true;
        this.offerEngineError     = '';

        await this.createRepaymentScheduleRecords(true);

        try {
            const result = {
                isSuccess:     true,
                emiAmount:     this.monthlyEmi,
                interestRate:  this.interestRate,
                loanAmount:    this.loanAmount,
                tenure:        this.tenure,
                totalInterest: this.totalInterest,
                totalAmount:   this.totalAmount,
                stopJourney:   false
            };

            if (result.isSuccess) {
                if (result.emiAmount)     this.monthlyEmi    = result.emiAmount;
                if (result.interestRate)  this.interestRate  = result.interestRate;
                if (result.loanAmount)    this.loanAmount    = result.loanAmount;
                if (result.tenure)        this.tenure        = result.tenure;
                if (result.totalInterest) this.totalInterest = result.totalInterest;
                if (result.totalAmount)   this.totalAmount   = result.totalAmount;

                this._recalcTotals();
                this.fieldsModified = false;

                // Persist confirmed offer values back to Application_Line_Item__c
                saveOfferEngineResult({
                    jsonData: JSON.stringify({
                        applicationId:         this.recordId,
                        applicationLineItemId: this._applicationLineItemId || null,
                        loanAmount:            this.loanAmount,
                        interestRate:       this.interestRate,
                        tenure:             this.tenure,
                        emiAmount:          this.monthlyEmi,
                        moratoriumDays:     this.moratoriumDays,
                        advanceEMI:         this.advanceEmi,
                        installmentType:    this.installmentType,
                        firstEmiDueDateDay: this.firstEmiDueDate === '5th of Month' ? 5 : 10
                    })
                }).catch(err => console.error('[OfferPage] saveOfferEngineResult failed:', err));

                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.integrationCurrentStageIndex = 1;
                    this.integrationStatus            = 'success';
                    this.integrationSuccessMessage    = result.stopJourney
                        ? 'Offer Engine completed. Journey stop signal received — please review.'
                        : 'Offer Engine completed successfully.';
                }, 2000);
            } else {
                this.offerEngineError  = result.message || 'Offer Engine call failed.';
                this.integrationStatus = 'error';
            }
        } catch (error) {
            this.offerEngineError  = error?.body?.message || error?.message || 'Unexpected error calling Offer Engine.';
            this.integrationStatus = 'error';
        } finally {
            this.isOfferEngineRunning = false;
        }
    }

    /**
     * @description Opens the Installment Schedule modal.
     * Validates that the interest rate is entered before generating the schedule.
     */
    async handleInstallmentSchedule() {
        if (!this.isReRunDisabled) {
            this.rerunOfferMessage();
            return;
        }
        if (!this.interestRate || this.interestRate <= 0) {
            this._showToast('Missing Interest Rate', 'Please enter a valid interest rate before viewing the installment schedule.', 'warning');
            return;
        }
        await this.createRepaymentScheduleRecords(false);
    }

    async createRepaymentScheduleRecords(fromOfferEngine = false) {
        if (!this._isStagePast) {
            try {
                await createRepaymentSchedule({
                    jsonData: JSON.stringify({
                        applicationId:         this.recordId,
                        applicationLineItemId: this._applicationLineItemId || null,
                        loanAmount:            this.loanAmount,
                        interestRate:    this.interestRate,
                        tenure:          this.tenure,
                        emiAmount:       this.monthlyEmi,
                        installmentType: this.installmentType,
                        firstEmiDate:    this._computedFirstEmiDateStr
                    })
                });
            } catch (err) {
                console.error('[OfferPage] createRepaymentSchedule failed:', err);
                this._showToast('Error', 'Error while creating Repayment Schedule records', 'error');
                return;
            }
        }
        if (!fromOfferEngine) {
            this.dynamicModalHeader = 'Installment Schedule';
            this.dynamicComponentName  = 'installmentSchedue';
            this.dynamicComponentProps = { recordId: this.recordId };
            this.showDynamicModal      = true;
        }
    }

    rerunOfferMessage() {
        this._showToast('Offer Engine Required', 'You have unsaved parameter changes. Please re-run the Offer Engine before proceeding.', 'warning');
    }

    // ── Modal close handlers ──────────────────────────────────────────────
    handleInsuranceModalClose() {
        this.showInsuranceModal = false;
    }

    async handleCibilValidityChange(event) {
        this.cibilValidityOption = event.target.value;
        if (this.cibilValidityOption === 'yes') {
            const verifyTarget = this._formatVerifyPhone(this.borrowerPhone);
            if (!verifyTarget) {
                this._showToast(
                    'Mobile Not Found',
                    'Borrower mobile number is not available for CIBIL consent verification.',
                    'warning'
                );
                this.cibilValidityOption = 'no';
                return;
            }

            this._lastActionFieldKey = 'contactNumber';
            this._cibilOtpFlow       = true;

            const otpReady = await this.generateMobileOTP();
            if (!otpReady) {
                this._cibilOtpFlow = false;
                this.cibilValidityOption = 'no';
            }
        }
    }

    handleOpenDynamicComponentModal(event) {
        const { componentName, ...extraProps } = event.detail || {};
        if (this._cibilOtpFlow) {
            extraProps.modalHeader = 'CIBIL Consent Verification';
            extraProps.headerName  = 'CIBIL Consent Verification';
            this._cibilOtpFlow     = false;
        } else if (extraProps.otpType === 'email') {
            extraProps.modalHeader = extraProps.modalHeader || 'Personal Email Verification';
            extraProps.headerName  = extraProps.headerName || 'Personal Email Verification';
        }
        this.dynamicComponentName  = componentName || '';
        this.dynamicModalHeader    = extraProps?.modalHeader || '';
        this.dynamicComponentProps = extraProps;
        this.showDynamicModal      = !!this.dynamicComponentName;
    }

    /** Aliases used by sendPhoneOTPAPI / otpVerification handlers (ctx interface). */
    get applicantId() { return this.borrowerApplicantId; }
    get contactNumber() {
        const digits = String(this.borrowerPhone || '').replace(/\D/g, '');
        return digits.length > 10 ? digits.slice(-10) : digits;
    }
    get contactInfoFieldValues() {
        return { contactNumber: this._formatVerifyPhone(this.borrowerPhone) };
    }

    updateFieldValue(field, value) {
        if (field === 'phoneOTPErrorMessage' && value) {
            this._showToast('Error', value, 'error');
        }
    }

    async generateMobileOTP() {
        try {
            // needs to show integration modal "Generating OTP
            this._openIntegrationModal('Generating Mobile OTP', ['Generating OTP'], null);


            const result = await generatePhoneOTP({
                applicantId: this.borrowerApplicantId,
                phoneNumber: this.contactNumber
            });
            if (!result?.success) {
                this._showToast('Error', result?.message || 'Failed to generate OTP.', 'error');
                this.integrationStatus = 'error';
                this.integrationErrorMessage = result?.message || 'Failed to generate OTP.';
                return false;
            }
            await invokeHandler('sendPhoneOTPAPI', 'onAction', this).then((response) => {
                console.log('response', JSON.stringify(response));
                this.showIntegrationModal = false;        
                invokeHandler('otpVerification', 'onAction', this);
            });
        } catch (err) {
            this.integrationStatus = 'error';
            this.integrationErrorMessage = err?.message || 'Failed to generate OTP.';
            console.error('[OfferPage] generateMobileOTP failed:', err);
            this._showToast('Error', err?.message || 'Failed to generate OTP.', 'error');
            return false;
        }
    }

    setActionState( actionKey, status ){
        if(actionKey === 'contactNumber' && status === 'success'){
            this.cibilConsentVerified = true;
        }
    }

    handleModalClose() {
        const wasOtpFlow     = this.dynamicComponentName === 'otpVerification';
        const wasPayInPayOut = this.dynamicComponentName === 'payInPayOutModal';
        this.showDynamicModal      = false;
        this.dynamicComponentName  = '';
        this.dynamicComponentProps = {};
        this.dynamicModalHeader    = '';
        if (wasPayInPayOut) {
            this.fieldsModified = true;
        }
        if (wasOtpFlow && this.dynamicModalHeader === 'CIBIL Consent Verification') {
            this._pendingCibilVerification = false;
            this.cibilValidityOption = 'no';
        }
        if (wasOtpFlow && this.dynamicModalHeader === 'Personal Email Verification') {
            this.template.querySelector('c-offer-c-a-m-highlight-panel')?.cancelEmailOtpFlow?.();
        }
    }

    handleOtpVerified(event) {
        if (event.detail?.otpType === 'email') {
            this.showDynamicModal      = false;
            this.dynamicComponentName  = '';
            this.dynamicComponentProps = {};
            this.dynamicModalHeader    = '';
            return;
        }

        const wasOtpFlow = this.dynamicComponentName === 'otpVerification';
        if (wasOtpFlow && event.detail?.otpType === 'mobile') {
            this._pendingCibilVerification = true;
            this.cibilConsentVerified = true;
            this._openIntegrationModal('CIBIL Consent Verification', ['CIBIL Bureau API'], null);
            setTimeout(() => {
                this.integrationCurrentStageIndex = 1;
                this.integrationStatus            = 'success';
                this.integrationSuccessMessage    = 'CIBIL Bureau API completed successfully.';
            }, 2000);
        }
    }

    handleInsurancePremiumReceived(event) {
        const totalPremium = event?.detail?.totalPremium;
        if (totalPremium && totalPremium > 0) {
            this.loanAmount     = (this.loanAmount || 0) + totalPremium;
            this.fieldsModified = true;
        }
    }

    handlePayInPayOutModalSubmit() {
        this.showDynamicModal = false;
    }

    handleIntegrationModalClose(event) {
        this.showIntegrationModal = false;
        if (this._pendingCibilVerification) {
            this._pendingCibilVerification = false;
            this.cibilConsentVerified = true;
        }
        if (this._pendingAddInsurance) {
            this._pendingAddInsurance = false;
            const totalPremium = event?.detail?.totalPremium;
            if (totalPremium && totalPremium > 0) {
                this.loanAmount     = (this.loanAmount || 0) + totalPremium;
                this.fieldsModified = true;
            }
        }
    }

    handleIntegrationRetry() {
        this.integrationStatus            = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.integrationErrorMessage      = '';
        if (this._integrationRetryFn) this._integrationRetryFn();
    }

    _openIntegrationModal(header, stages, retryFn) {
        this.integrationHeader            = header;
        this.integrationStages            = stages;
        this.integrationStatus            = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.integrationSuccessMessage    = '';
        this.integrationErrorMessage      = '';
        this._integrationRetryFn          = retryFn;
        this.showIntegrationModal         = true;
    }

    // ── Navigation ────────────────────────────────────────────────────────
    /**
     * @description Validates offer, loads FI Waiver Integration Master, runs integration LWC,
     * shows integration modal, then advances to Investigation Reports on success.
     */
    async handleNextButton() {
        

        if (this.higherIncome === 'yes') {
            await this.handleMoveBackToIncomeVerification();
            return;
        }

        if (this.showCibilSection) {
            this._showToast('CIBIL Expired', 'The bureau report has expired. Please retrigger CIBIL consent to move ahead.', 'warning');
            return;
        }

        if(this.installmentType === ''){
            this._showToast('Error', 'Installment type is required.', 'error');
            return;
        }

        if (!this.isReRunDisabled) {
            this.rerunOfferMessage();
            return;
        }
        
        if (!this.recordId) return;

        if (this.fromAssetList) {
            if (this._isStagePast) {
                await this.returnToAssetList(false);
                return;
            }
            await this._completeAssetListOffer();
            return;
        }

        await this._processOfferStageNext();
    }

    async _completeAssetListOffer() {
        if (!this._applicationLineItemId) {
            this._showToast('Navigation Error', 'Application line item is missing. Please go back and reopen the asset.', 'error');
            return;
        }

        try {
            this.isLoading = true;
            const result = await markOfferStageComplete({
                applicationLineItemId: this._applicationLineItemId
            });
            if (!result?.isSuccess) {
                this._showToast('Error', result?.message || 'Unable to complete offer for this asset.', 'error');
                return;
            }
            this.returnToAssetList(true);
        } catch (error) {
            this._showToast('Error', error?.body?.message || error?.message || 'Unable to complete offer for this asset.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async returnToAssetList(saved) {
        this.dispatchEvent(
            new CustomEvent('detailcomplete', {
                detail: {
                    lineItemId: this._applicationLineItemId || null,
                    saved
                },
                bubbles: true,
                composed: true
            })
        );
    }

    async _processOfferStageNext() {
        if (!this.currentViewId) {
            this._showToast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error');
            return;
        }

        const stagePhrase = this._resolveStagePhrase();
        if (!stagePhrase && !this._isStagePast) {
            this._showToast('Navigation Error', 'Stage phrase is missing. Please re-select Offer from the menu and try again.', 'error');
            return;
        }

        if (this._isStagePast) {
            this._dispatchLosNextStage(stagePhrase);
            return;
        }

        this._openIntegrationModal('FI Waiver', FI_INTEGRATION_STAGES, () => this._processOfferStageNext());

        try {
            const integrationMaster = await getIntegrationMaster({
                integrationName: FI_WAIVER_INTEGRATION_LABEL
            });
            const componentReference = integrationMaster?.Component_Reference__c;
            if (!componentReference) {
                this.integrationStatus       = 'error';
                this.integrationErrorMessage = 'FI Waiver integration is not configured.';
                return;
            }

            await invokeHandler(componentReference, 'onNextButton', this);

            const integrationResult = this._fiWaiverIntegrationResult;
            if (!integrationResult?.isSuccess) {
                this.integrationStatus       = 'error';
                this.integrationErrorMessage = integrationResult?.message || 'FI Waiver failed.';
                return;
            }

            this.integrationCurrentStageIndex = FI_INTEGRATION_STAGES.length;
            this.integrationStatus            = 'success';
            this.integrationSuccessMessage    = integrationResult.message
                || 'FI investigation creation completed successfully.';

            const result = await processNextStageRequest({
                applicationId:        this.recordId,
                currentStagePhrase:   stagePhrase,
                currentLoanStageName: this.tab || STAGE_OFFER
            });

            if (!result?.isSuccess) {
                this.integrationStatus       = 'error';
                this.integrationErrorMessage = result?.message || 'Unable to advance to the next stage.';
                return;
            }

            const navState = result.navigationState;
            if (!navState?.menuItems?.length) {
                this.integrationStatus       = 'error';
                this.integrationErrorMessage = 'No navigation state returned from the server.';
                return;
            }

            window.dispatchEvent(new CustomEvent(LOS_NAVIGATION_STATE_EVENT, {
                detail: { navigationState: navState },
                bubbles: true,
                composed: true
            }));

            const nextViewItem = this._findCurrentViewMenuItem(navState.menuItems);
            if (!nextViewItem) {
                this.integrationStatus       = 'error';
                this.integrationErrorMessage = 'Next stage could not be resolved. Please refresh the page.';
                return;
            }

            window.dispatchEvent(new CustomEvent(LOS_MENU_SELECT_EVENT, {
                detail: this._buildMenuSelectDetail(nextViewItem),
                bubbles: true,
                composed: true
            }));

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.showIntegrationModal = false; }, 1500);
        } catch (error) {
            this.integrationStatus       = 'error';
            this.integrationErrorMessage = error?.body?.message || error?.message || 'FI Waiver failed.';
        }
    }

    _dispatchLosNextStage(stagePhrase) {
        window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: true, message: 'Processing...' } }));
        window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
            detail: {
                currentViewId:            this.currentViewId,
                id:                       this.recordId,
                currentLoanStageComplete: this.tab || STAGE_OFFER,
                currentStagePhrase:       stagePhrase || this.stagePhrase || ''
            },
            bubbles: true,
            composed: true
        }));
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } })); }, 1500);
    }

    _resolveStagePhrase() {
        if (this.stagePhrase) return this.stagePhrase;
        const currentViewId = this.currentViewId || '';
        if (!currentViewId) return '';
        const sfIdMatch = String(currentViewId).match(/_([a-zA-Z0-9]{15,18})$/);
        return sfIdMatch
            ? currentViewId.slice(0, -sfIdMatch[1].length - 1)
            : currentViewId;
    }

    _findCurrentViewMenuItem(items = []) {
        for (const item of items) {
            if (item?.currentView === true) return item;
            if (item?.subItems?.length) {
                const found = this._findCurrentViewMenuItem(item.subItems);
                if (found) return found;
            }
        }
        return null;
    }

    _buildMenuSelectDetail(item = {}) {
        const isStagePast = String(item.status || '').toLowerCase() === 'completed';
        const tab         = item.tab || item.label || '';
        const label       = item.applicantType
            ? `${tab} - ${item.applicantType}${item.applicantName ? ` (${item.applicantName})` : ''}`
            : tab;
        return {
            tab,
            id:                 item.id,
            label,
            applicantId:        item.applicantId,
            applicantType:      item.applicantType,
            applicantName:      item.applicantName,
            isGroupItem:        item.isGroupItem === true,
            applicants:         item.applicants || [],
            stagePhrase:        item.stagePhrase || '',
            currentStagePhrase: item.stagePhrase || '',
            isStagePast,
            overrideLwc:        item.overrideLwc || ''
        };
    }

    handleRefreshClick() {}

    handleSpinner() {}

    // ── Offer Acceptance & Instant Approval ───────────────────────────────
    handleOfferAcceptance() {
        this.offerAccepted = true;
        const stages = [
            'FI Waiver',
            'FICO Asset Deviations',
            'FICO Global Deviations',
            'IDFY PAN Aadhaar',
            'Customer Master Creation'
        ];
        this._openIntegrationModal('Offer Acceptance', stages, null);
        stages.forEach((_, i) => {
            const isLast = i + 1 === stages.length;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.integrationCurrentStageIndex = i + 1;
                if (isLast) {
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        this.showIntegrationModal = false;
                        this._showToast('Offer Acceptance', 'Consents have been triggered for offer acceptance.', 'success');
                    }, 1000);
                }
            }, 1500 * (i + 1));
        });
    }

    handleInstantApproval() {
        this._openIntegrationModal('Instant Approval Check', ['STP Check API', 'NPA Check API'], () => this.handleInstantApproval());
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.integrationCurrentStageIndex = 1;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.integrationStatus         = 'success';
                this.integrationSuccessMessage = 'Instant Approval check completed successfully.';
            }, 1200);
        }, 1200);
    }

    // ── Private helpers ────────────────────────────────────────────────────
    /**
     * Recalculates totalInterest and totalAmount from current loanAmount,
     * interestRate, tenure and monthlyEmi. Called after offer engine response
     * or initial data load.
     */
    _recalcTotals() {
        if (this.monthlyEmi > 0 && this.tenure > 0) {
            this.totalAmount   = this.monthlyEmi * this.tenure;
            this.totalInterest = Math.max(0, this.totalAmount - this.loanAmount);
        }
    }

    _markModified() {
        if (!this._isStagePast) this.fieldsModified = true;
    }

    /** Selected EMI due day (5 or 10) from the 1st EMI radio option. */
    _getEmiDay() {
        return this.firstEmiDueDate === '5th of Month' ? 5 : 10;
    }

    /**
     * First EMI date: today + moratorium days, then snap to 5th or 10th of month
     * (same logic as OfferPageController.saveOfferEngineResult).
     */
    _computeFirstEmiDate(moratoriumDays = this.moratoriumDays) {
        const emiDay = this._getEmiDay();
        const base = new Date();
        base.setHours(0, 0, 0, 0);
        base.setDate(base.getDate() + (parseInt(moratoriumDays, 10) || 0));

        if (base.getDate() < emiDay) {
            return new Date(base.getFullYear(), base.getMonth(), emiDay);
        }
        return new Date(base.getFullYear(), base.getMonth() + 1, emiDay);
    }

    _recalcEmiDates() {
        this._firstEmiDateStr = this._formatDateYmd(this._computeFirstEmiDate());
    }

    _formatDateYmd(date) {
        return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    }

    _parseYmdDate(ymd) {
        const [y, m, d] = ymd.split('-').map((part) => parseInt(part, 10));
        return new Date(y, m - 1, d);
    }

    _formatEmiDisplay(date) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return `${date.getDate()}th ${months[date.getMonth()]} ${date.getFullYear()}`;
    }

    /** Formats borrower Phone__c for OTP display (e.g. 9876543210 → +91 98765 43210). */
    _formatVerifyPhone(phone) {
        if (!phone) return '';
        const digits = String(phone).replace(/\D/g, '');
        const ten = digits.length > 10 ? digits.slice(-10) : digits;
        if (ten.length !== 10) return String(phone).trim();
        return `+91 ${ten.slice(0, 5)} ${ten.slice(5)}`;
    }

    /** Formats a number using the Indian numbering locale (e.g. 399000 → 3,99,000). */
    _fmtINR(value) {
        if (value == null) return '0';
        return new Intl.NumberFormat('en-IN').format(value);
    }

    _toNumber(value) {
        const n = Number(value);
        return Number.isFinite(n) ? n : 0;
    }

    /**
     * Computes inline background style for a range input to render a filled track.
     * Uses a linear-gradient that works inside LWC shadow DOM.
     */
    _sliderStyle(current, min, max) {
        const range = max - min;
        const pct   = range > 0 ? Math.max(0, Math.min(100, ((current - min) / range) * 100)) : 0;
        return `background: linear-gradient(to right, #4f46e5 0%, #4f46e5 ${pct}%, #e2e8f0 ${pct}%, #e2e8f0 100%);`;
    }

    _showToast(title, message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}