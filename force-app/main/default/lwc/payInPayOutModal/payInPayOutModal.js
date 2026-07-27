/**
 * @description Pay In / Pay Out Modal — Modal for changing payment charges
 * Displayed from Offer Page. Provides UI for modifying service charges,
 * documentation charges, stamping charges, and other payment-related fields.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFieldConfig from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData   from '@salesforce/apex/GenericPageLayoutController.savePageData';

const APEX_CLASS          = 'OfferPageController';
const GET_APEX_METHOD     = 'getPayinPayout';
const SAVE_APEX_METHOD    = 'updatePayinPayout';

export default class PayInPayOutModal extends LightningElement {
    /** Opportunity record Id */
    @api recordId;
    @api applicationLineItemId;
    @api lineItemId;

    // ── Pay In Fields ─────────────────────────────────────────────────────
    @track serviceCharges = 1700;
    @track documentationCharges = 200;
    @track applicableStampingCharges = 200;
    @track cess = 0;
    @track totalApplicableStampingCharges = 200;
    @track stampingChargesPaidBy = 'Bank';
    @track stampingChargesCollected = 200;

    // ── Loading state ─────────────────────────────────────────────────────
    @track isLoading = false;

    // ── Computed: Radio checked states ────────────────────────────────────
    get isStampingPaidByBank() { return this.stampingChargesPaidBy === 'Bank'; }
    get isStampingPaidByCustomer() { return this.stampingChargesPaidBy === 'Customer'; }

    // ── Lifecycle ─────────────────────────────────────────────────────────
    connectedCallback() {
        // dynamicComponentModal applies asset props after connect.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this._loadData(), 0);
    }

    _getLineItemParams() {
        const lineItemId = this.applicationLineItemId || this.lineItemId || null;
        return lineItemId ? { applicationLineItemId: lineItemId } : {};
    }

    async _loadData() {
        if (!this.recordId) return;
        try {
            this.isLoading = true;
            const data = await getFieldConfig({
                apexClassName:  APEX_CLASS,
                apexMethodName: GET_APEX_METHOD,
                recordId:       this.recordId,
                params:         this._getLineItemParams()
            });
            console.log('Get details '+JSON.stringify(data));
            if (data?.isSuccess) {
                if (data.serviceCharges               != null) this.serviceCharges               = data.serviceCharges;
                if (data.documentationCharges         != null) this.documentationCharges         = data.documentationCharges;
                if (data.totalApplicableStampingCharges != null) {
                    this.totalApplicableStampingCharges = data.totalApplicableStampingCharges;
                    this.applicableStampingCharges      = data.totalApplicableStampingCharges;
                }
                if (data.stampingDoneBy)  this.stampingChargesPaidBy = data.stampingDoneBy;
                if (data.cessCharges != null) {
                    this.cess = data.cessCharges;
                    this._recalculateTotalStampingCharges();
                }
            }
        } catch (error) {
            this._showToast('Error', error?.body?.message || 'Failed to load existing data.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Input handlers ────────────────────────────────────────────────────
    handleServiceChargesChange(event) {
        this.serviceCharges = parseFloat(event.target.value) || 0;
    }

    handleDocumentationChargesChange(event) {
        this.documentationCharges = parseFloat(event.target.value) || 0;
    }

    handleApplicableStampingChargesChange(event) {
        this.applicableStampingCharges = parseFloat(event.target.value) || 0;
        this._recalculateTotalStampingCharges();
    }

    handleCessChange(event) {
        this.cess = parseFloat(event.target.value) || 0;
        this._recalculateTotalStampingCharges();
    }

    handleTotalApplicableStampingChargesChange(event) {
        this.totalApplicableStampingCharges = parseFloat(event.target.value) || 0;
    }

    handleStampingChargesPaidByChange(event) {
        this.stampingChargesPaidBy = event.target.value;
    }

    handleStampingChargesCollectedChange(event) {
        this.stampingChargesCollected = parseFloat(event.target.value) || 0;
    }

    // ── Calculations ──────────────────────────────────────────────────────
    _recalculateTotalStampingCharges() {
        this.totalApplicableStampingCharges = this.applicableStampingCharges + this.cess;
    }

    // ── Action handlers ───────────────────────────────────────────────────
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSubmit() {
        if (!this._validateFields()) return;

        try {
            this.isLoading = true;

            // Build payload
            const jsonString = {
                recordId: this.recordId,
                serviceCharges: this.serviceCharges,
                documentationCharges: this.documentationCharges,
                applicableStampingCharges: this.applicableStampingCharges,
                cess: this.cess,
                totalApplicableStampingCharges: this.totalApplicableStampingCharges,
                stampingChargesPaidBy: this.stampingChargesPaidBy,
                stampingChargesCollected: this.stampingChargesCollected
            };

            const result = await savePageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: SAVE_APEX_METHOD,
                recordId:       this.recordId,
                params: {
                    ...this._getLineItemParams(),
                    serviceCharges:                 this.serviceCharges,
                    documentationCharges:           this.documentationCharges,
                    totalApplicableStampingCharges: this.totalApplicableStampingCharges,
                    stampingDoneBy:                 this.stampingChargesPaidBy,
                    cessCharges:                    this.cess
                }
            });

            console.log('Response '+JSON.stringify(result));
            if (!result?.isSuccess) {
                this._showToast('Error', result?.message || 'Failed to save details.', 'error');
                return;
            }

            this._showToast('Success', 'Pay In / Pay Out details updated successfully.', 'success');
            this.handleClose();

        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Failed to save pay in/pay out details.';
            this._showToast('Error', msg, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Validation ────────────────────────────────────────────────────────
    _validateFields() {
        const requiredFields = [
            { value: this.serviceCharges, label: 'Service Charges' },
            { value: this.documentationCharges, label: 'Documentation Charges' },
            { value: this.applicableStampingCharges, label: 'Applicable Stamping Charges' },
            { value: this.totalApplicableStampingCharges, label: 'Total Applicable Stamping Charges' },
            { value: this.stampingChargesCollected, label: 'Stamping Charges Collected' }
        ];

        for (const field of requiredFields) {
            if (field.value === null || field.value === undefined || field.value === '') {
                this._showToast('Validation Error', `Please enter ${field.label}.`, 'error');
                return false;
            }
        }

        return true;
    }

    // ── Toast helper ──────────────────────────────────────────────────────
    _showToast(title, message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}