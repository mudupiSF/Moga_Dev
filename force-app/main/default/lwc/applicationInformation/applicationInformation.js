/**
 * applicationInformation — read-only Application Overview card on the Application Master Page.
 * Loads overview fields via wire, opens withdraw modal, and broadcasts applicationStatusChanged.
 */

import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getApplicationInformation from '@salesforce/apex/ApplicationInformationController.getApplicationInformation';
import WithdrawApplicationModal from 'c/withdrawApplicationModal';

/** Read-only overview fields rendered in display order. */
const FIELD_CONFIG = [
    { key: 'applicationNumber', label: 'Application Number', sequence: 1 },
    { key: 'applicationSource', label: 'Application Source', sequence: 2 },
    { key: 'productType', label: 'Product Type', sequence: 3 },
    { key: 'vehicleType', label: 'Vehicle Type', sequence: 4 }
];

/** UI-only status label when Withdrawal_Reason__c is populated. */
const APPLICATION_STATUS_WITHDRAWN = 'Withdrawn';

const APPLICATION_ACTION = {
    REVOKE: 'revoke',
    WITHDRAW: 'withdraw',
    TRANSFER: 'transfer'
};

/** Window event consumed by applicationMasterPage and stage LWCs. */
const APPLICATION_STATUS_EVENT = 'applicationStatusChanged';

const DEFAULT_APPLICATION_STATUS = {
    isRevoked: false,
    isWithdrawn: false
};

export default class ApplicationInformation extends LightningElement {
    @api recordId;

    @track isCollapsed = false;

    _wiredData;

    // ── Data loading ────────────────────────────────────────────────────────

    @wire(getApplicationInformation, { recordId: '$recordId' })
    wiredApplicationInfo(result) {
        this._wiredData = result;
        if (result.error) {
            this.showError('Error loading application overview', result.error);
            return;
        }
        console.log('@@@@ result.data?.withdrawalReason', result.data?.withdrawalReason);
        if (result.data?.withdrawalReason) {
            this.fireApplicationWithdrawnEvent(result.data.withdrawalReason);
        }
    }

    // ── UI state getters ────────────────────────────────────────────────────

    get isExpanded() {
        return !this.isCollapsed;
    }

    get cardClass() {
        return this.isCollapsed ? 'form-card app-info-card--collapsed' : 'form-card';
    }

    get headerClass() {
        return this.isCollapsed ? 'form-header app-info-header--collapsed' : 'form-header';
    }

    get collapseIconName() {
        return this.isCollapsed ? 'utility:chevrondown' : 'utility:chevronup';
    }

    get collapseIconTitle() {
        return this.isCollapsed ? 'Expand Application Overview' : 'Collapse Application Overview';
    }

    get isLoading() {
        return !!(this.recordId && this._wiredData?.loading);
    }

    get hasError() {
        return !!(this.recordId && this._wiredData?.error);
    }

    get applicationData() {
        return this._wiredData?.data || {};
    }

    get withdrawalReason() {
        return this.applicationData.withdrawalReason || '';
    }

    get withdrawalReasonOptions() {
        return this.applicationData.withdrawalReasonOptions || [];
    }

    get isApplicationWithdrawn() {
        return this.hasWithdrawalReason(this.withdrawalReason);
    }

    /** Overview fields plus UI-only Application Status when withdrawn. */
    get displayFields() {
        const data = this.applicationData;
        const fields = FIELD_CONFIG.map((field) => ({
            ...field,
            displayValue: this.formatDisplayValue(data ? data[field.key] : null)
        }));

        if (this.isApplicationWithdrawn) {
            fields.push({
                key: 'applicationStatus',
                label: 'Application Status',
                sequence: 5,
                displayValue: APPLICATION_STATUS_WITHDRAWN
            });
        }

        return fields.sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0));
    }

    // ── Collapse / header actions ───────────────────────────────────────────

    handleToggleCollapse() {
        this.isCollapsed = !this.isCollapsed;
    }

    /** Routes Revoke / Withdraw / Transfer header buttons by data-action. */
    handleButtonClick(event) {
        const action = event.currentTarget?.dataset?.action;
        if (!action) {
            return;
        }

        switch (action) {
            case APPLICATION_ACTION.REVOKE:
                this.handleRevoke();
                break;
            case APPLICATION_ACTION.WITHDRAW:
                this.handleWithdraw();
                break;
            case APPLICATION_ACTION.TRANSFER:
                this.handleTransfer();
                break;
            default:
                break;
        }
    }

    handleRevoke() {
        /* TODO: wire Revoke flow for MOGA DEV */
    }

    /** Opens withdrawApplicationModal; refreshes data and fires withdrawal event on success. */
    async handleWithdraw() {
        if (!this.recordId) {
            this.showError('Error', 'Application record is not available.');
            return;
        }

        const result = await WithdrawApplicationModal.open({
            size: 'small',
            recordId: this.recordId,
            withdrawalReason: this.withdrawalReason,
            withdrawalReasonOptions: this.withdrawalReasonOptions
        });

        if (result?.status === 'success' && this._wiredData) {
            await refreshApex(this._wiredData);
            this.fireApplicationWithdrawnEvent(result.withdrawalReason);
        }
    }

    handleTransfer() {
        /* TODO: wire Transfer flow for MOGA DEV */
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    formatDisplayValue(value) {
        if (value === null || value === undefined || String(value).trim() === '') {
            return '—';
        }
        return String(value);
    }

    hasWithdrawalReason(value) {
        return value !== null && value !== undefined && String(value).trim() !== '';
    }

    /** Notifies listeners that the application status changed (withdrawn; revoke later). */
    fireApplicationWithdrawnEvent(withdrawalReason) {
        if (!this.hasWithdrawalReason(withdrawalReason)) {
            return;
        }

        const applicationStatus = {
            ...DEFAULT_APPLICATION_STATUS,
            isWithdrawn: true
        };

        window.dispatchEvent(
            new CustomEvent(APPLICATION_STATUS_EVENT, {
                detail: {
                    recordId: this.recordId,
                    applicationStatus: applicationStatus
                },
                bubbles: true,
                composed: true
            })
        );
    }

    // ── Toast notifications ─────────────────────────────────────────────────

    showError(title, error) {
        const message =
            error?.body?.message ||
            error?.message ||
            (typeof error === 'string' ? error : 'An unexpected error occurred.');
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error'
            })
        );
    }
}