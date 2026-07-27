/**
 * applicationOverview — compact application header bar on the Application Master Page.
 * Shows application summary title and icon actions (revoke, withdraw, transfer, documents, queries).
 */

import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getApplicationOverview from '@salesforce/apex/ApplicationOverviewController.getApplicationOverview';
import WithdrawApplicationModal from 'c/withdrawApplicationModal';

const APPLICATION_ACTION = {
    REVOKE: 'revoke',
    WITHDRAW: 'withdraw',
    TRANSFER: 'transfer',
    UPLOAD: 'upload',
    VIEW: 'view'
};

const APPLICATION_STATUS_EVENT = 'applicationStatusChanged';

const DEFAULT_APPLICATION_STATUS = {
    isRevoked: false,
    isWithdrawn: false
};

export default class ApplicationOverview extends LightningElement {
    @api recordId;

    @track showDynamicModal = false;
    @track dynamicModalComponentName = '';
    @track dynamicModalComponentProps = {};
    @track dynamicModalHeader = '';

    _wiredData;

    @wire(getApplicationOverview, { recordId: '$recordId' })
    wiredApplicationInfo(result) {
        this._wiredData = result;
        if (result.error) {
            this.showError('Error loading application overview', result.error);
            return;
        }
        if (result.data?.withdrawalReason) {
            this.fireApplicationWithdrawnEvent(result.data.withdrawalReason);
        }
    }

    get isLoading() {
        return !!(this.recordId && this._wiredData?.loading);
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

    /** Application # {Application Number} | {Product Type} | {Vehicle Type} */
    get headerTitle() {
        const data = this.applicationData;
        const segments = [];

        const appNumber = this.formatSegment(data.applicationNumber);
        segments.push(appNumber ? `Application # ${appNumber}` : 'Application');

        const productType = this.formatSegment(data.productType);
        if (productType) {
            segments.push(productType);
        }

        const vehicleType = this.formatSegment(data.vehicleType);
        if (vehicleType) {
            segments.push(vehicleType);
        }

        return segments.join(' | ');
    }

    /** # {Application Number} | {Product Type} | {Vehicle Type} */
    get headerSubtitle() {
        const data = this.applicationData;
        const segments = [];

        const appNumber = this.formatSegment(data.applicationNumber);
        segments.push(appNumber ? `# ${appNumber}` : '');

        const productType = this.formatSegment(data.productType);
        if (productType) {
            segments.push(productType);
        }

        const vehicleType = this.formatSegment(data.vehicleType);
        if (vehicleType) {
            segments.push(vehicleType);
        }

        return segments.join(' | ');
    }

    handleIconClick(event) {
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
            case APPLICATION_ACTION.UPLOAD:
                this.handleUploadClick();
                break;
            case APPLICATION_ACTION.VIEW:
                this.handleViewClick();
                break;
            default:
                break;
        }
    }

    handleRevoke() {
        /* TODO: wire Revoke flow for MOGA DEV */
    }

    async handleWithdraw() {
        if (!this.recordId) {
            this.showError('Error', 'Application record is not available.');
            return;
        }

        const result = await WithdrawApplicationModal.open({
            size: 'small',
            recordId: this.recordId,
            withdrawalReason: this.withdrawalReason,
            withdrawalReasonOptions: this.withdrawalReasonOptions,
            useOverviewController: true
        });

        if (result?.status === 'success' && this._wiredData) {
            await refreshApex(this._wiredData);
            this.fireApplicationWithdrawnEvent(result.withdrawalReason);
        }
    }

    handleTransfer() {
        /* TODO: wire Transfer flow for MOGA DEV */
    }

    handleUploadClick() {
        this.dynamicModalComponentName = 'embedCustomFilePreview';
        this.dynamicModalComponentProps = { mode: 'upload', enableAdhocAdd: true };
        this.dynamicModalHeader = 'Upload Documents';
        this.showDynamicModal = true;
    }

    handleViewClick() {
        this.dynamicModalComponentName = 'embedCustomFilePreview';
        this.dynamicModalComponentProps = { mode: 'preview' };
        this.dynamicModalHeader = 'View Documents';
        this.showDynamicModal = true;
    }

    handleCreateQueryClick(event) {
        const { modalHeader, componentName, componentProps } = event.detail;
        this.dynamicModalComponentName = componentName;
        this.dynamicModalComponentProps = componentProps;
        this.dynamicModalHeader = modalHeader;
        this.showDynamicModal = true;
    }

    handleViewQueriesClick(event) {
        const { modalHeader, componentName, componentProps } = event.detail;
        this.dynamicModalComponentName = componentName;
        this.dynamicModalComponentProps = componentProps;
        this.dynamicModalHeader = modalHeader;
        this.showDynamicModal = true;
    }

    handleDynamicModalClose() {
        this.showDynamicModal = false;
        this.dynamicModalComponentName = '';
        this.dynamicModalComponentProps = {};
        this.dynamicModalHeader = '';
    }

    formatSegment(value) {
        if (value === null || value === undefined || String(value).trim() === '') {
            return '';
        }
        return String(value).trim();
    }

    hasWithdrawalReason(value) {
        return value !== null && value !== undefined && String(value).trim() !== '';
    }

    fireApplicationWithdrawnEvent(withdrawalReason) {
        if (!this.hasWithdrawalReason(withdrawalReason)) {
            return;
        }

        window.dispatchEvent(
            new CustomEvent(APPLICATION_STATUS_EVENT, {
                detail: {
                    recordId: this.recordId,
                    applicationStatus: {
                        ...DEFAULT_APPLICATION_STATUS,
                        isWithdrawn: true
                    }
                },
                bubbles: true,
                composed: true
            })
        );
    }

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