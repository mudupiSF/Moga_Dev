/**
 * withdrawApplicationModal — Lightning modal to capture Withdrawal_Reason__c.
 * Picklist options and current value are passed from the host LWC (no Apex wire here).
 */

import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import withdrawApplication from '@salesforce/apex/ApplicationInformationController.withdrawApplication';
import withdrawApplicationOverview from '@salesforce/apex/ApplicationOverviewController.withdrawApplication';

export default class WithdrawApplicationModal extends LightningModal {
    @api recordId;
    @api withdrawalReason = '';
    @api withdrawalReasonOptions = [];
    /** When true, persists via ApplicationOverviewController (applicationOverview LWC). */
    @api useOverviewController = false;

    isLoading = false;

    // ── Field handlers ──────────────────────────────────────────────────────

    handleWithdrawalReasonChange(event) {
        this.withdrawalReason = event.detail.value || '';
    }

    // ── Modal actions ───────────────────────────────────────────────────────

    handleCancel() {
        this.close();
    }

    /** Persists Withdrawal_Reason__c on Application__c and closes with success payload. */
    async handleSubmit() {
        if (!this.recordId) {
            this.showToast('Error', 'Application record is not available.', 'error');
            return;
        }

        if (!this.withdrawalReason) {
            this.showToast('Error', 'Please select a Withdrawal Reason.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            const persistWithdrawal = this.useOverviewController
                ? withdrawApplicationOverview
                : withdrawApplication;
            await persistWithdrawal({
                recordId: this.recordId,
                withdrawalReason: this.withdrawalReason
            });
            this.showToast('Success', 'Application withdrawal reason updated successfully.', 'success');
            this.close({
                status: 'success',
                withdrawalReason: this.withdrawalReason
            });
        } catch (error) {
            this.showToast(
                'Error',
                error?.body?.message || error?.message || 'Failed to update withdrawal reason.',
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    // ── Toast notifications ─────────────────────────────────────────────────

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}