import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProductType from '@salesforce/apex/OfferPageController.getProductType';
import saveInsuranceRecord  from '@salesforce/apex/OfferPageController.saveInsuranceRecord';
import getInsuranceRecords  from '@salesforce/apex/OfferPageController.getInsuranceRecords';

const INSURANCE_PLANS = [
    {
        id: 'combo',
        name: 'COMBO',
        description: 'Combined life and health insurance',
        isSelected: false,
        selectedPlan: '',
        isFunded: 'no',
        premium: '2000',
        coverage: '1000',
        planOptions: [
            { label: 'Group +Hospital Cash Daily+ GPA+AME Combo', value: 'Group +Hospital Cash Daily+ GPA+AME Combo' }
        ]
    },
    {
        id: 'flexi',
        name: 'FLEXI',
        description: 'Flexible life insurance plan',
        isSelected: false,
        selectedPlan: '',
        isFunded: 'no',
        premium: '4000',
        coverage: '3000',
        planOptions: [
            { label: 'Flexi Term Plan',        value: 'Flexi Term Plan' },
            { label: 'Flexi Endowment Plan',   value: 'Flexi Endowment Plan' }
        ]
    }
];

export default class AddInsuranceModal extends LightningElement {
    @api recordId;
    @api applicationLineItemId;
    @api lineItemId;

    @track customerType   = 'borrower';
    @track insurancePlans = INSURANCE_PLANS.map(p => ({ ...p, planOptions: [...p.planOptions] }));
    @track isLoading      = false;

    // ── Integration progress modal ────────────────────────────────────────
    @track showIntegrationModal         = false;
    @track integrationHeader            = '';
    @track integrationStatus            = 'loading';
    @track integrationCurrentStageIndex = 0;
    @track integrationSuccessMessage    = '';
    integrationStages = ['Insurance Premium API'];

    // ── Lifecycle ─────────────────────────────────────────────────────────
    async connectedCallback() {
        // dynamicComponentModal applies asset props after connect.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.loadExistingInsurance(), 0);
        const data = await getProductType({ applicationId: this.recordId });
        if(data.productType !== 'PL') {
            INSURANCE_PLANS.push({
                id: 'motor',
                name: 'MOTOR',
                description: 'Motor vehicle insurance coverage',
                isSelected: false,
                selectedPlan: '',
                isFunded: 'no',
                premium: '5000',
                coverage: '4000',
                planOptions: [
                    { label: 'Comprehensive Motor Plan', value: 'Comprehensive Motor Plan' },
                    { label: 'Third Party Motor Plan',   value: 'Third Party Motor Plan' }
                ]
            });
        }
    }

    _getRequestPayload() {
        const payload = {
            applicationId: this.recordId,
            customerType:  this.customerType
        };
        const lineItemId = this.applicationLineItemId || this.lineItemId || null;
        if (lineItemId) {
            payload.applicationLineItemId = lineItemId;
        }
        return payload;
    }

    // ── Customer type options ─────────────────────────────────────────────
    get customerTypeOptions() {
        return [
            { label: 'Borrower',    value: 'borrower',    isSelected: this.customerType === 'borrower' },
            { label: 'Co-Borrower', value: 'co_borrower', isSelected: this.customerType === 'co_borrower' }
        ];
    }

    // ── Enriched plans for template (adds computed flags) ─────────────────
    get computedPlans() {
        return this.insurancePlans.map(plan => ({
            ...plan,
            planOptionsWithSelected: plan.planOptions.map(opt => ({
                ...opt,
                isSelected: opt.value === plan.selectedPlan
            })),
            isFundedYes: plan.isFunded === 'yes',
            isFundedNo:  plan.isFunded === 'no'
        }));
    }

    // ── Load existing insurance records on modal open ─────────────────────
    async loadExistingInsurance() {
        if (!this.recordId) return;
        try {
            this.isLoading = true;
            const records = await getInsuranceRecords({
                dataJson: JSON.stringify(this._getRequestPayload())
            });

            if (records && records.length > 0) {
                this.insurancePlans = this.insurancePlans.map(plan => {
                    // Insurance_Plan__c stores plan TYPE (COMBO / FLEXI / MOTOR)
                    const match = records.find(r =>
                        r.Insurance_Plan__c === plan.id.toUpperCase()
                    );
                    if (match) {
                        return {
                            ...plan,
                            isSelected:   true,
                            selectedPlan: match.Name,   // Name stores the specific plan value
                            isFunded:     match.Funded_Non_funded__c === 'Funded' ? 'yes' : 'no'
                        };
                    }
                    return plan;
                });
            }
        } catch (error) {
            console.error('Error loading insurance records:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // ── Handlers ──────────────────────────────────────────────────────────
    handleCustomerTypeChange(event) {
        this.customerType = event.target.value;
        // Reset plans then reload for the newly selected customer type
        this.insurancePlans = INSURANCE_PLANS.map(p => ({ ...p, planOptions: [...p.planOptions] }));
        this.loadExistingInsurance();
    }

    handlePlanToggle(event) {
        const planId  = event.target.dataset.planId;
        const checked = event.target.checked;
        this.insurancePlans = this.insurancePlans.map(p =>
            p.id === planId
                ? { ...p, isSelected: checked, selectedPlan: checked ? p.selectedPlan : '', isFunded: checked ? p.isFunded : 'no' }
                : p
        );
    }

    handlePlanChange(event) {
        const planId = event.target.dataset.planId;
        this.insurancePlans = this.insurancePlans.map(p =>
            p.id === planId ? { ...p, selectedPlan: event.target.value } : p
        );
    }

    handleFundedChange(event) {
        const planId = event.target.dataset.planId;
        this.insurancePlans = this.insurancePlans.map(p =>
            p.id === planId ? { ...p, isFunded: event.target.value } : p
        );
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ── Compute Premium — saves Insurance__c records then fires event ──────
    async handleComputePremium() {
        const selectedPlans = this.insurancePlans.filter(p => p.isSelected);
        if (selectedPlans.length === 0) {
            this._showToast('Validation', 'Please select at least one insurance plan.', 'warning');
            return;
        }
        for (const plan of selectedPlans) {
            if (!plan.selectedPlan) {
                this._showToast('Validation', `Please select a plan for ${plan.name} insurance.`, 'warning');
                return;
            }
        }

        // Show integration progress modal
        this.integrationStatus            = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.integrationSuccessMessage    = '';
        this.integrationHeader            = 'Compute Premium';
        this.showIntegrationModal         = true;

        try {
            // Send all selected plans in a single Apex call
            const result = await saveInsuranceRecord({
                dataJson: JSON.stringify({
                    ...this._getRequestPayload(),
                    plans: selectedPlans.map(plan => ({
                        insurancePlanType: plan.id.toUpperCase(),
                        insurancePlanName: plan.selectedPlan,
                        premium:           parseFloat(plan.premium)  || 0,
                        amount:            parseFloat(plan.coverage) || 0,
                        fundedNonFunded:   plan.isFunded === 'yes' ? 'Funded' : 'Non-Funded'
                    }))
                })
            });

            if (!result.success) {
                throw new Error(result.message || 'Failed to save insurance records');
            }

            // Mark stage complete
            this.integrationCurrentStageIndex = 1;
            this.integrationStatus            = 'success';
            this.integrationSuccessMessage    = 'Premium computed successfully.';

            // Brief pause so user sees the success state before modal closes
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.handleIntegrationDone(), 1200);

        } catch (error) {
            this.integrationStatus = 'error';
            this._showToast('Error', error.message || 'Failed to compute premium', 'error');
        }
    }

    handleIntegrationModalClose() {
        this.showIntegrationModal = false;
    }

    handleIntegrationDone() {
        this.showIntegrationModal = false;
        const totalPremium = this.insurancePlans
            .filter(p => p.isSelected)
            .reduce((sum, p) => sum + (parseFloat(p.premium) || 0), 0);

        // bubbles+composed so it pierces dynamicComponentModal's shadow DOM
        this.dispatchEvent(new CustomEvent('insurancepremium', {
            detail:   { totalPremium },
            bubbles:  true,
            composed: true
        }));
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ── Toast helper ──────────────────────────────────────────────────────
    _showToast(title, message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}