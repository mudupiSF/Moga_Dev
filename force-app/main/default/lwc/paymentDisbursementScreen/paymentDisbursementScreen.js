import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';

import {
    LABELS,
    SUMMARY_COUNTS,
    PRE_DISBURSEMENT_CONTROLS_MAPPED,
    PRE_DISBURSEMENT_DEFERRALS,
    ALL_DEFERRALS_CLEARED,
    LOS_GLOBAL_LOADER_EVENT,
    PRIMARY_BTN_CLASS,
    ACTION_BAR_CLASS,
    ACTION_BAR_CLASS_SPLIT,
    DISABLED_BENEFICIARY_ROW_CLASS,
    APEX_CLASS,
    APEX_METHOD_GET_PAGE_DATA,
    APEX_METHOD_SAVE_DISBURSEMENT,
    PAYMENT_ORIGIN_TA,
    PAYMENT_ORIGIN_TRADE_ADVANCE,
    WORKSPACE_TAB_DIRECT,
    WORKSPACE_TAB_ADJUSTMENT,
    LOADER_MESSAGE_SAVING_DISBURSEMENT,
    LOADER_MESSAGE_PROCESSING,
    INR_FORMAT,
    mapSummaryCard,
    mapSummaryCountsFromApi,
    mapDeferralItem,
    mapBeneficiaryRow,
    cloneTaReferenceRows,
    mapTaReferenceRow,
    mapAdjustmentDetailFields,
    mapBeneficiaryRowsFromApi
} from './paymentDisbursementScreenConstants';

export default class PaymentDisbursementScreen extends LightningElement {
    @api recordId;
    @api currentViewId = '';
    @api applicationLineItemId = '';
    @api assetId = '';
    @api fromAssetList = false;

    _isStagePast = false;
    @api
    get isStagePast() {
        return this._isStagePast;
    }
    set isStagePast(value) {
        this._isStagePast = value === true || value === 'true';
    }

    labels = LABELS;
    allDeferralsCleared = ALL_DEFERRALS_CLEARED;
    primaryBtnClass = PRIMARY_BTN_CLASS;
    mappedControls = PRE_DISBURSEMENT_CONTROLS_MAPPED;
    mappedDeferrals = PRE_DISBURSEMENT_DEFERRALS.map(mapDeferralItem);

    @track summaryCards = [
        mapSummaryCard('pending', LABELS.pendingLabel, SUMMARY_COUNTS.pendingCount, 'pending'),
        mapSummaryCard('completed', LABELS.completedLabel, SUMMARY_COUNTS.completedCount, 'completed')
    ];
    @track beneficiaryRows = [];
    @track displayBeneficiaryRows = [];
    @track taReferenceRows = cloneTaReferenceRows();
    @track displayTaReferenceRows = [];
    @track adjustmentDetailFields = [];
    @track isLoading = false;
    @track hasBeneficiaryData = false;
    @track isTaOrigin = false;
    @track selectedTaReferenceLabel = '';
    @track formattedPendingToAdjust = INR_FORMAT.format(0);
    @track activeWorkspaceTab = WORKSPACE_TAB_DIRECT;

    connectedCallback() {
        this.refreshTaDisplayState();
        this.fetchPageData();
    }

    get isSectionDisabled() {
        return this._isStagePast;
    }

    get isDirectTabActive() {
        return !this.isTaOrigin || this.activeWorkspaceTab === WORKSPACE_TAB_DIRECT;
    }

    get isAdjustmentTabActive() {
        return this.isTaOrigin && this.activeWorkspaceTab === WORKSPACE_TAB_ADJUSTMENT;
    }

    get directTabClass() {
        return `pds-tab${this.isDirectTabActive ? ' pds-tab--active' : ''}`;
    }

    get adjustmentTabClass() {
        return `pds-tab${this.isAdjustmentTabActive ? ' pds-tab--active' : ''}`;
    }

    get actionBarClass() {
        return this.isAdjustmentTabActive ? ACTION_BAR_CLASS_SPLIT : ACTION_BAR_CLASS;
    }

    get showPendingToAdjustStatus() {
        return this.isAdjustmentTabActive && !!this.selectedTaReferenceLabel;
    }

    get isSubmitDisabled() {
        if (this.isSectionDisabled) {
            return true;
        }
        return !this.beneficiaryRows.some((row) => row.selected && !row.disbursed);
    }

    async fetchPageData() {
        if (!this.recordId) {
            return;
        }
        this.isLoading = true;
        try {
            const data = await getPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_GET_PAGE_DATA,
                recordId: this.recordId,
                params: this.buildScopeParams()
            });

            if (data?.loadError) {
                this.showToast('Error', data.loadError, 'error');
            }

            this.updateSummaryCards(data?.summaryCounts);

            const paymentOrigin = String(data?.paymentOriginatedFrom || '').trim().toUpperCase();
            this.isTaOrigin =
                paymentOrigin === PAYMENT_ORIGIN_TA || paymentOrigin === PAYMENT_ORIGIN_TRADE_ADVANCE;
            this.activeWorkspaceTab = WORKSPACE_TAB_DIRECT;
            this.syncTaReferenceRowsFromServer(data?.taAdjustedByReference);

            const mappedRows = mapBeneficiaryRowsFromApi(data?.beneficiaryRows || []);
            this.beneficiaryRows = mappedRows;
            this.hasBeneficiaryData = this.beneficiaryRows.length > 0;
            this.refreshBeneficiaryDisplay();
            this.refreshTaDisplayState();

            if (!this.hasBeneficiaryData && !data?.loadError && !this.isTaOrigin) {
                this.showToast('Info', LABELS.noBeneficiaries, 'info');
            }
        } catch (error) {
            this.beneficiaryRows = [];
            this.hasBeneficiaryData = false;
            this.refreshBeneficiaryDisplay();
            this.updateSummaryCards(SUMMARY_COUNTS);
            this.showToast('Error', LABELS.loadError, 'error');
            // eslint-disable-next-line no-console
            console.error('[PaymentDisbursementScreen] fetchPageData:', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleRowSelection(event) {
        if (this.isSectionDisabled) {
            return;
        }
        const rowId = event.currentTarget.dataset.rowId;
        const checked = event.target.checked;
        this.beneficiaryRows = this.beneficiaryRows.map((row) =>
            this.isSameBeneficiaryRow(row, rowId) ? { ...row, selected: checked } : row
        );
        this.refreshBeneficiaryDisplay();
        // Keep TA adjustment field states in sync with dealer selection changes.
        this.refreshTaDisplayState();
    }

    handleToBePaidChange(event) {
        if (this.isSectionDisabled) {
            return;
        }
        const rowId = event.currentTarget.dataset.rowId;
        const value = event.target.value;
        this.beneficiaryRows = this.beneficiaryRows.map((row) =>
            this.isSameBeneficiaryRow(row, rowId) ? { ...row, toBePaidNow: value } : row
        );
        this.refreshBeneficiaryDisplay();
    }

    handleTaReferenceSelect(event) {
        if (this.isSectionDisabled) {
            return;
        }
        if (!this.hasSelectedAdjustmentDealerRow()) {
            this.showToast(
                'Validation',
                this.labels.selectDealerBeforeTaReferenceValidation,
                'warning'
            );
            return;
        }
        const rowKey = event.currentTarget.dataset.rowKey;
        this.taReferenceRows = this.taReferenceRows.map((row) => ({
            ...row,
            selected: row.id === rowKey
        }));
        this.refreshTaDisplayState();
    }

    handleWorkspaceTabSelect(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab === WORKSPACE_TAB_DIRECT || tab === WORKSPACE_TAB_ADJUSTMENT) {
            this.activeWorkspaceTab = tab;
        }
    }

    handleToBeAdjustedChange(event) {
        if (
            this.isSectionDisabled ||
            !this.selectedTaReferenceLabel ||
            !this.getSelectedAdjustmentDealerRows().length
        ) {
            return;
        }
        const selected = this.taReferenceRows.find((row) => row.selected);
        const pendingToAdjust = Number(selected?.pending) || 0;
        if (!selected || pendingToAdjust <= 0) {
            return;
        }
        const value = event.target.value;
        this.taReferenceRows = this.taReferenceRows.map((row) =>
            row.id === selected.id ? { ...row, toBeAdjustedNow: value } : row
        );
        this.refreshTaDisplayState();
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) {
            return;
        }
        if (this.isAdjustmentTabActive) {
            await this.submitAdjustment();
            return;
        }

        const selectedRows = this.beneficiaryRows.filter((row) => row.selected && !row.disbursed);
        if (!selectedRows.length) {
            this.showToast('Validation', this.labels.selectRowValidation, 'warning');
            return;
        }

        for (const row of selectedRows) {
            const amount = Number(row.toBePaidNow) || 0;
            const remainingAmount = Number(row.disbursementAmount) - Number(row.paidEarlier) || 0;
            if (!amount || amount <= 0 || amount > remainingAmount) {
                this.showToast('Validation', this.labels.toBePaidValidation, 'warning');
                return;
            }
        }

        try {
            const data = await this.saveDisbursement(
                selectedRows.map((row) => ({
                    id: row.id,
                    toBePaidNow: Number(row.toBePaidNow) || 0
                }))
            );

            if (data?.loadError || !data?.isSuccess) {
                this.showToast('Error', data?.loadError || this.labels.loadError, 'error');
                return;
            }

            this.applySavedData(data);
            this.showToast('Success', this.labels.submitSuccess, 'success');
            if (this.fromAssetList && this.isAssetLineItemFullyDisbursed(data)) {
                this.notifyAssetListComplete(true);
            }
        } catch (error) {
            this.showToast('Error', this.labels.loadError, 'error');
            // eslint-disable-next-line no-console
            console.error('[PaymentDisbursementScreen] handleSubmit:', error);
        } finally {
            this.hideGlobalLoader();
        }
    }

    async submitAdjustment() {
        const dealerRows = this.getSelectedAdjustmentDealerRows();
        if (!dealerRows.length) {
            this.showToast('Validation', this.labels.selectRowValidation, 'warning');
            return;
        }
        const selected = this.taReferenceRows.find((row) => row.selected);
        if (!selected) {
            this.showToast('Validation', this.labels.selectTaReferenceValidation, 'warning');
            return;
        }
        const payments = [];
        let totalDealerTrancheAmount = 0;
        for (const dealerRow of dealerRows) {
            const trancheAmount = Number(dealerRow.toBePaidNow) || 0;
            const remainingDealerAmount =
                Number(dealerRow.disbursementAmount) - Number(dealerRow.paidEarlier) || 0;
            if (!trancheAmount || trancheAmount <= 0 || trancheAmount > remainingDealerAmount) {
                this.showToast('Validation', this.labels.toBePaidValidation, 'warning');
                return;
            }
            totalDealerTrancheAmount += trancheAmount;
            payments.push({
                id: dealerRow.id,
                toBePaidNow: trancheAmount,
                adjustedAmount: 0,
                toBeAdjustedNow: 0
            });
        }
        const amount = Number(selected.toBeAdjustedNow) || 0;
        const pending = Number(selected.pending) || 0;
        if (!amount || amount <= 0 || amount > pending || amount > totalDealerTrancheAmount) {
            this.showToast('Validation', this.labels.adjustmentAmountValidation, 'warning');
            return;
        }

        let remainingAdjustment = amount;
        const paymentsWithAdjustment = payments.map((payment) => {
            const rowAdjustment = Math.min(remainingAdjustment, payment.toBePaidNow);
            remainingAdjustment -= rowAdjustment;
            return rowAdjustment > 0
                ? {
                      ...payment,
                      adjustedAmount: rowAdjustment,
                      toBeAdjustedNow: rowAdjustment,
                      taReferenceNumber: selected.referenceNumber
                  }
                : payment;
        });

        try {
            const data = await this.saveDisbursement(paymentsWithAdjustment);
            if (data?.loadError || !data?.isSuccess) {
                this.showToast('Error', data?.loadError || this.labels.loadError, 'error');
                return;
            }
            this.applySavedData(data);
            this.showToast('Success', this.labels.submitAdjustmentSuccess, 'success');
            if (this.fromAssetList && this.isAssetLineItemFullyDisbursed(data)) {
                this.notifyAssetListComplete(true);
            }
        } catch (error) {
            this.showToast('Error', this.labels.loadError, 'error');
            // eslint-disable-next-line no-console
            console.error('[PaymentDisbursementScreen] submitAdjustment:', error);
        } finally {
            this.hideGlobalLoader();
        }
    }

    isSameBeneficiaryRow(row, rowId) {
        return row != null && rowId != null && String(row.id) === String(rowId);
    }

    refreshBeneficiaryDisplay() {
        if (this.isSectionDisabled) {
            this.displayBeneficiaryRows = this.beneficiaryRows.map((row, index) => ({
                ...mapBeneficiaryRow(row, index),
                checkboxDisabled: true,
                toBePaidInputDisabled: true,
                rowClass: DISABLED_BENEFICIARY_ROW_CLASS
            }));
            return;
        }
        this.displayBeneficiaryRows = this.beneficiaryRows.map(mapBeneficiaryRow);
    }

    refreshTaDisplayState() {
        const dealerRows = this.getSelectedAdjustmentDealerRows();
        const isTaSelectionBlockedByDealerSelection = !dealerRows.length;
        if (isTaSelectionBlockedByDealerSelection && this.taReferenceRows.some((row) => row.selected)) {
            this.taReferenceRows = this.taReferenceRows.map((row) =>
                row.selected ? { ...row, selected: false, toBeAdjustedNow: '' } : row
            );
        }
        const selected = this.taReferenceRows.find((row) => row.selected) || null;
        const dealerRow = dealerRows[0] || null;
        const dealerRowForDetails = dealerRows.length > 1
            ? { ...dealerRow, beneficiaryName: `${dealerRows.length} dealers selected` }
            : dealerRow;
        const totalDealerTrancheAmount = dealerRows.reduce(
            (sum, row) => sum + (Number(row.toBePaidNow) || 0),
            0
        );
        const pendingToAdjust = Number(selected?.pending) || 0;
        const enteredAdjustmentAmount = Number(selected?.toBeAdjustedNow) || 0;
        const calculatedDisbursementAmount = Math.max(
            totalDealerTrancheAmount - enteredAdjustmentAmount,
            0
        );
        const shouldDisableAdjustmentInput = !dealerRows.length || pendingToAdjust <= 0;
        this.selectedTaReferenceLabel = selected?.referenceNumber || '';
        this.formattedPendingToAdjust = INR_FORMAT.format(pendingToAdjust);
        this.displayTaReferenceRows = this.taReferenceRows.map((row, index) =>
            mapTaReferenceRow(
                row,
                index,
                this.isSectionDisabled,
                isTaSelectionBlockedByDealerSelection
            )
        );
        this.adjustmentDetailFields = mapAdjustmentDetailFields(
            selected,
            dealerRowForDetails,
            calculatedDisbursementAmount
        ).map((field) => ({
            ...field,
            inputDisabled:
                this.isSectionDisabled || (field.editable && shouldDisableAdjustmentInput)
        }));
    }

    syncTaReferenceRowsFromServer(taAdjustedByReference) {
        const adjustedByReference = {};
        if (taAdjustedByReference && typeof taAdjustedByReference === 'object') {
            Object.entries(taAdjustedByReference).forEach(([referenceNumber, adjustedAmount]) => {
                const normalizedReference = String(referenceNumber || '').trim().toUpperCase();
                if (normalizedReference) {
                    adjustedByReference[normalizedReference] = Number(adjustedAmount) || 0;
                }
            });
        }

        this.taReferenceRows = this.taReferenceRows.map((row) => {
            const normalizedReference = String(row.referenceNumber || '').trim().toUpperCase();
            const adjustedAmount = adjustedByReference[normalizedReference] || 0;
            const totalApprovedValue = Number(row.totalApprovedValue) || 0;
            const pendingAmount = Math.max(totalApprovedValue - adjustedAmount, 0);

            return {
                ...row,
                adjustedSoFar: adjustedAmount,
                alreadyAdjustedAmount: adjustedAmount,
                pending: pendingAmount,
                // Always reset adjustment input and selection after data sync/load.
                toBeAdjustedNow: '',
                selected: false
            };
        });
    }

    getSelectedAdjustmentDealerRows() {
        return this.beneficiaryRows.filter(
            (row) =>
                row.selected &&
                !row.disbursed &&
                String(row.beneficiaryType || '').trim().toLowerCase() === 'dealer'
        );
    }

    hasSelectedAdjustmentDealerRow() {
        return this.getSelectedAdjustmentDealerRows().length > 0;
    }

    async saveDisbursement(payments) {
        this.showGlobalLoader(LOADER_MESSAGE_SAVING_DISBURSEMENT);
        return savePageData({
            apexClassName: APEX_CLASS,
            apexMethodName: APEX_METHOD_SAVE_DISBURSEMENT,
            recordId: this.recordId,
            params: {
                ...this.buildScopeParams(),
                payments
            }
        });
    }

    buildScopeParams() {
        const params = {};
        const lineItemId = String(this.applicationLineItemId || '').trim();
        const selectedAssetId = String(this.assetId || '').trim();
        if (lineItemId) {
            params.applicationLineItemId = lineItemId;
        }
        if (selectedAssetId) {
            params.assetId = selectedAssetId;
        }
        const currentViewId = String(this.currentViewId || '').trim();
        if (currentViewId) {
            params.currentViewId = currentViewId;
        }
        return params;
    }

    applySavedData(data) {
        this.updateSummaryCards(data?.summaryCounts);
        this.beneficiaryRows = mapBeneficiaryRowsFromApi(data?.beneficiaryRows || []);
        this.hasBeneficiaryData = this.beneficiaryRows.length > 0;
        this.syncTaReferenceRowsFromServer(data?.taAdjustedByReference);
        this.refreshBeneficiaryDisplay();
        this.refreshTaDisplayState();
    }

    isAssetLineItemFullyDisbursed(data) {
        const counts = mapSummaryCountsFromApi(data?.summaryCounts || SUMMARY_COUNTS);
        if (counts.pendingCount <= 0) {
            return true;
        }
        const latestRows = mapBeneficiaryRowsFromApi(data?.beneficiaryRows || []);
        return latestRows.length > 0 && latestRows.every((row) => row.disbursed);
    }

    updateSummaryCards(summaryCounts) {
        const counts = mapSummaryCountsFromApi(summaryCounts || SUMMARY_COUNTS);
        this.summaryCards = [
            mapSummaryCard('pending', LABELS.pendingLabel, counts.pendingCount, 'pending'),
            mapSummaryCard('completed', LABELS.completedLabel, counts.completedCount, 'completed')
        ];
    }

    showGlobalLoader(message = LOADER_MESSAGE_PROCESSING) {
        window.dispatchEvent(
            new CustomEvent(LOS_GLOBAL_LOADER_EVENT, { detail: { show: true, message } })
        );
    }

    hideGlobalLoader() {
        window.dispatchEvent(
            new CustomEvent(LOS_GLOBAL_LOADER_EVENT, { detail: { show: false } })
        );
    }

    notifyAssetListComplete(saved) {
        this.dispatchEvent(
            new CustomEvent('detailcomplete', {
                detail: {
                    lineItemId: this.applicationLineItemId || null,
                    saved
                },
                bubbles: true,
                composed: true
            })
        );
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}