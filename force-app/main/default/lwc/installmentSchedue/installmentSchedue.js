import { LightningElement, track, api } from 'lwc';
import getRepaymentSchedule from '@salesforce/apex/OfferPageController.getRepaymentSchedule';

export default class InstallmentSchedue extends LightningElement {
    _recordId;

    @track schedules    = [];
    @track hasSchedules = false;
    @track isLoading    = true;
    @track scheduleData = { loanAmount: 0, tenure: 0, monthlyEmi: 0, interestRate: 0, totalInterest: 0, totalAmount: 0 };
    isLoaded = false;

    // ── Trigger Deviation — only when opened from WheelsPaymentRequest ─────
    @api  fromPaymentRequest        = false;
    @track showDeviationBtn         = true;
    @track showIntegrationModal     = false;
    integrationStages               = [];
    integrationStatus               = 'loading';
    integrationCurrentStageIndex    = 0;

    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (!this.isLoaded) this.loadScheduleData();
    }

    // Show button only when opened from payment request and not yet triggered
    get showTriggerDeviationBtn() {
        return this.fromPaymentRequest && this.showDeviationBtn;
    }

    // ── Summary card formatted getters ────────────────────────────────────
    get formattedLoanAmount()    { return `₹${(this.scheduleData.loanAmount   || 0).toLocaleString('en-IN')}`; }
    get formattedTenure()        { return `${this.scheduleData.tenure         || 0} months`; }
    get formattedMonthlyEmi()    { return `₹${(this.scheduleData.monthlyEmi   || 0).toLocaleString('en-IN')}`; }
    get formattedInterestRate()  { return `${this.scheduleData.interestRate   || 0}%`; }
    get formattedTotalInterest() {
        const v = this.scheduleData.totalInterest || 0;
        return v < 0 ? `-₹${Math.abs(v).toLocaleString('en-IN')}` : `₹${v.toLocaleString('en-IN')}`;
    }
    get formattedTotalAmount()   { return `₹${(this.scheduleData.totalAmount  || 0).toLocaleString('en-IN')}`; }

    // ── Lifecycle ─────────────────────────────────────────────────────────
    connectedCallback() {
        if (!this.isLoaded) this.loadScheduleData();
    }

    async loadScheduleData() {
        if (!this._recordId) return;
        this.isLoading = true;
        try {
            const data = await getRepaymentSchedule({ applicationId: this._recordId });
            if (data && data.hasData) {
                const rows      = data.schedules || [];
                const totalEmi  = rows.reduce((s, r) => s + (r.EMI_Amount__c          || 0), 0);
                const totalInt  = rows.reduce((s, r) => s + (r.Interest_Component__c  || 0), 0);
                this.scheduleData = {
                    loanAmount:   data.loanAmount   || 0,
                    tenure:       data.tenure       || 0,
                    monthlyEmi:   data.monthlyEmi   || 0,
                    interestRate: data.interestRate || 0,
                    totalInterest: Math.round(totalInt),
                    totalAmount:   Math.round(totalEmi)
                };
                this.schedules = rows.map(r => ({
                    id:                 r.Id,
                    installmentNo:      r.Number_of_Installments__c,
                    dueDate:            r.EMI_Due_Date__c,
                    openingPrincipal:   this._fmt(r.Opening_Principal__c),
                    installmentAmount:  this._fmt(r.EMI_Amount__c),
                    principalComponent: this._fmt(r.Principal_Component__c),
                    interestComponent:  this._fmt(r.Interest_Component__c),
                    closingPrincipal:   this._fmt(r.Closing_Principal__c)
                }));
                this.hasSchedules = this.schedules.length > 0;
            } else {
                this.hasSchedules = false;
            }
            this.isLoaded = true;
        } catch (error) {
            console.error('Error loading installment schedule:', error);
            this.hasSchedules = false;
        } finally {
            this.isLoading = false;
        }
    }

    _fmt(val) {
        if (val == null) return '0';
        return Number(val).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    // ── Trigger Deviation handler ─────────────────────────────────────────
    handleTriggerDeviation() {
        this.integrationStages            = ['Trigger Deviation API Calling'];
        this.integrationStatus            = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.showIntegrationModal         = true;

        setTimeout(() => {
            this.integrationCurrentStageIndex = 1;
            setTimeout(() => {
                this.showIntegrationModal = false;  // close integration modal only
                this.showDeviationBtn     = false;  // remove the Trigger Deviation button
            }, 600);
        }, 1500);
    }

    handleIntegrationModalClose() {
        this.showIntegrationModal = false;
    }
}