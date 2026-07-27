import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';

import {
    LABELS,
    SUMMARY_STATS,
    HYPOTHECATION_ALERT,
    HYPOTHECATION_FIELDS,
    INSURANCE_FIELDS,
    REPAYMENT_FIELDS,
    BUREAU_FIELDS,
    STAGE_POST_DISBURSEMENT_TRACKING,
    APEX_CLASS,
    APEX_METHOD_GET_PAGE_DATA,
    APEX_METHOD_SAVE_TRACKING,
    LOS_NEXT_STAGE_EVENT,
    mapSummaryStat,
    mapPddRow,
    mapDetailFields,
    mapCommunicationItem,
    mapQcChecklistItem,
    clonePddDocuments,
    cloneCommunications,
    cloneQcChecklist,
    computeSummaryStats
} from './postDisbursementTrackingScreenConstants';

const PRIMARY_BTN_CLASS = 'form-primary-btn p4-button-text';
const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader';
const INR_NO_DECIMALS = new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    maximumFractionDigits: 0
});

export default class PostDisbursementTrackingScreen extends LightningElement {
    @api recordId;
    @api currentViewId;
    @api stagePhrase = '';
    @api tab = '';
    _applicationLineItemId = '';
    _assetId = '';
    @api fromAssetList = false;
    _hasConnected = false;
    _currentContextKey = '';
    _stateByContextKey = {};
    _latestLoadRequestToken = 0;

    @api
    get applicationLineItemId() {
        return this._applicationLineItemId;
    }
    set applicationLineItemId(value) {
        this._applicationLineItemId = this._normalizeContextId(value);
        this._syncContextState();
    }

    @api
    get assetId() {
        return this._assetId;
    }
    set assetId(value) {
        this._assetId = this._normalizeContextId(value);
        this._syncContextState();
    }

    _isStagePast = false;
    @api
    get isStagePast() {
        return this._isStagePast;
    }
    set isStagePast(value) {
        this._isStagePast = value === true || value === 'true';
    }

    labels = LABELS;
    hypothecationAlert = HYPOTHECATION_ALERT;
    primaryBtnClass = PRIMARY_BTN_CLASS;
    @track mappedHypothecationFields = mapDetailFields(HYPOTHECATION_FIELDS);
    @track mappedInsuranceFields = mapDetailFields(INSURANCE_FIELDS);
    @track mappedRepaymentFields = mapDetailFields(REPAYMENT_FIELDS);
    mappedBureauFields = mapDetailFields(BUREAU_FIELDS);

    @track summaryStats = { ...SUMMARY_STATS };
    @track pddDocuments = clonePddDocuments();
    @track communications = cloneCommunications();
    @track qcChecklist = cloneQcChecklist();
    @track bureauFlagged = false;
    @track qcSignedOff = false;
    @track handoverClosed = false;

    connectedCallback() {
        this._hasConnected = true;
        this._syncContextState();
    }

    get summaryCards() {
        const stats = this.summaryStats;
        return [
            mapSummaryStat(
                'received',
                this.labels.documentsReceived,
                `${stats.documentsReceived}/${stats.documentsTotal}`,
                'success'
            ),
            mapSummaryStat('pending', this.labels.pending, stats.pendingCount, 'pending'),
            mapSummaryStat('overdue', this.labels.overdue, stats.overdueCount, 'overdue'),
            mapSummaryStat(
                'completion',
                this.labels.pddCompletion,
                `${stats.pddCompletionPercent}%`,
                'completion'
            )
        ];
    }

    get mappedPddDocuments() {
        return this.pddDocuments.map(mapPddRow);
    }

    get mappedCommunications() {
        return this.communications.map(mapCommunicationItem);
    }

    get mappedQcChecklist() {
        return this.qcChecklist.map(mapQcChecklistItem);
    }

    get isScreenDisabled() {
        return this._isStagePast || this.handoverClosed;
    }

    get showFlagForReporting() {
        return !this.bureauFlagged;
    }

    get signOffDisabled() {
        return this.isScreenDisabled || this.qcSignedOff;
    }

    get closeHandoverDisabled() {
        return this.isScreenDisabled || !this.qcChecklist.every((item) => item.complete);
    }

    get showPddRefresh() {
        return !this.handoverClosed;
    }

    async handleRefreshPddDocuments() {
        const activeContextKey = this._currentContextKey || this._buildContextKey();
        if (!this.recordId || !activeContextKey) {
            return;
        }
        this._showGlobalLoaderIndicator('Refreshing PDD documents...');
        try {
            await this.fetchContextData(activeContextKey);
        } finally {
            this._hideGlobalLoaderIndicator();
        }
    }

    handleDispatch(event) {
        this._syncContextState();
        const communicationId = event.currentTarget.dataset.communicationId;
        if (!communicationId || this.isScreenDisabled) {
            return;
        }
        this.communications = this.communications.map((item) =>
            item.id === communicationId
                ? { ...item, status: 'Dispatched', canDispatch: false }
                : item
        );
        this.setQcChecklistItemCompletion(
            'communication',
            this.communications.every((item) => item.status === 'Dispatched')
        );
        this._cacheCurrentContextState();
        this.showToast('Success', this.labels.dispatchSuccess, 'success');
    }

    handleFlagForReporting() {
        this._syncContextState();
        if (this.isScreenDisabled || this.bureauFlagged) {
            return;
        }
        this.bureauFlagged = true;
        this.setQcChecklistItemCompletion('bureau', true);
        this._cacheCurrentContextState();
        this.showToast('Success', this.labels.flagForReportingSuccess, 'success');
    }

    handleSignOff() {
        this._syncContextState();
        if (this.signOffDisabled) {
            return;
        }
        this.qcSignedOff = true;
        this._cacheCurrentContextState();
        this.showToast('Success', this.labels.signOffSuccess, 'success');
    }

    async handleCloseHandover() {
        this._syncContextState();
        if (this.closeHandoverDisabled) {
            return;
        }
        const saveSucceeded = await this.persistTrackingCompletion(true);
        if (!saveSucceeded) {
            return;
        }
        this.handoverClosed = true;
        this._cacheCurrentContextState();
        this.showToast('Success', this.labels.closeHandoverSuccess, 'success');
        if (this.fromAssetList) {
            this.emitDetailComplete(true);
            return;
        }
        this.emitNextStageEvent();
    }

    emitNextStageEvent() {
        const viewId = (this.currentViewId || '').trim();
        if (!viewId) {
            return;
        }

        this._showGlobalLoaderIndicator('Processing...');
        window.dispatchEvent(
            new CustomEvent(LOS_NEXT_STAGE_EVENT, {
                detail: {
                    currentViewId: viewId,
                    id: viewId,
                    applicationLineItemId: this.applicationLineItemId || null,
                    assetId: this.assetId || null,
                    currentLoanStageComplete: this.tab || STAGE_POST_DISBURSEMENT_TRACKING,
                    currentStagePhrase: this.stagePhrase || ''
                },
                bubbles: true,
                composed: true
            })
        );
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this._hideGlobalLoaderIndicator(), 1500);
    }

    _showGlobalLoaderIndicator(message = 'Processing...') {
        window.dispatchEvent(
            new CustomEvent(LOS_GLOBAL_LOADER_EVENT, { detail: { show: true, message } })
        );
    }

    _hideGlobalLoaderIndicator() {
        window.dispatchEvent(
            new CustomEvent(LOS_GLOBAL_LOADER_EVENT, { detail: { show: false } })
        );
    }

    emitDetailComplete(saved) {
        this.dispatchEvent(
            new CustomEvent('detailcomplete', {
                detail: {
                    lineItemId: this.applicationLineItemId || null,
                    assetId: this.assetId || null,
                    saved
                },
                bubbles: true,
                composed: true
            })
        );
    }

    setQcChecklistItemCompletion(id, complete) {
        this.qcChecklist = this.qcChecklist.map((item) =>
            item.id === id ? { ...item, complete } : item
        );
    }

    _normalizeContextId(value) {
        return value ? String(value).trim() : '';
    }

    _buildContextKey() {
        const lineItemId = this.applicationLineItemId || 'NO_LINE_ITEM';
        const assetId = this.assetId || 'NO_ASSET';
        return `${lineItemId}::${assetId}`;
    }

    _syncContextState() {
        if (!this._hasConnected) {
            return;
        }
        const nextContextKey = this._buildContextKey();
        if (nextContextKey === this._currentContextKey) {
            return;
        }

        if (this._currentContextKey) {
            this._cacheContextState(this._currentContextKey);
        }

        const cachedState = this._stateByContextKey[nextContextKey];
        if (cachedState) {
            this._restoreContextState(cachedState);
        } else {
            this._resetToDefaultState();
            this._cacheContextState(nextContextKey);
        }
        this._currentContextKey = nextContextKey;
        this.fetchContextData(nextContextKey);
    }

    _cacheCurrentContextState() {
        if (!this._currentContextKey) {
            return;
        }
        this._cacheContextState(this._currentContextKey);
    }

    _cacheContextState(contextKey) {
        this._stateByContextKey = {
            ...this._stateByContextKey,
            [contextKey]: {
                summaryStats: { ...this.summaryStats },
                pddDocuments: this.pddDocuments.map((doc) => ({ ...doc })),
                communications: this.communications.map((item) => ({ ...item })),
                qcChecklist: this.qcChecklist.map((item) => ({ ...item })),
                bureauFlagged: this.bureauFlagged,
                qcSignedOff: this.qcSignedOff,
                handoverClosed: this.handoverClosed
            }
        };
    }

    _restoreContextState(state) {
        this.summaryStats = { ...(state.summaryStats || SUMMARY_STATS) };
        this.pddDocuments = (state.pddDocuments || []).map((doc) => ({ ...doc }));
        this.communications = (state.communications || []).map((item) => ({ ...item }));
        this.qcChecklist = (state.qcChecklist || []).map((item) => ({ ...item }));
        this.bureauFlagged = Boolean(state.bureauFlagged);
        this.qcSignedOff = Boolean(state.qcSignedOff);
        this.handoverClosed = Boolean(state.handoverClosed);
    }

    _resetToDefaultState() {
        this.pddDocuments = clonePddDocuments();
        this.summaryStats = computeSummaryStats(this.pddDocuments);
        this.communications = cloneCommunications();
        this.qcChecklist = cloneQcChecklist();
        this.bureauFlagged = false;
        this.qcSignedOff = false;
        this.handoverClosed = false;
    }

    _applyFullyCompletedState() {
        this.pddDocuments = this.pddDocuments.map((doc) => ({
            ...doc,
            status: 'Received',
            canMarkReceived: false,
            ageingDays: 0
        }));
        this.summaryStats = computeSummaryStats(this.pddDocuments);
        this.communications = this.communications.map((item) => ({
            ...item,
            status: 'Dispatched',
            canDispatch: false
        }));
        this.bureauFlagged = true;
        this.qcSignedOff = true;
        this.handoverClosed = true;
        this.qcChecklist = this.qcChecklist.map((item) => ({ ...item, complete: true }));
    }

    _buildRequestScope() {
        const params = {};
        if (this.applicationLineItemId) {
            params.applicationLineItemId = this.applicationLineItemId;
        }
        if (this.assetId) {
            params.assetId = this.assetId;
        }
        const viewId = String(this.currentViewId || '').trim();
        if (viewId) {
            params.currentViewId = viewId;
        }
        return params;
    }

    async fetchContextData(contextKey) {
        if (!this.recordId) {
            return;
        }
        const requestToken = ++this._latestLoadRequestToken;
        try {
            const data = await getPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_GET_PAGE_DATA,
                recordId: this.recordId,
                params: this._buildRequestScope()
            });
            if (requestToken !== this._latestLoadRequestToken || contextKey !== this._currentContextKey) {
                return;
            }
            if (data?.loadError) {
                this.showToast('Error', data.loadError, 'error');
                return;
            }

            const resolvedLineItemId = this._normalizeContextId(data?.applicationLineItemId);
            const resolvedAssetId = this._normalizeContextId(data?.assetId);
            if (!this.applicationLineItemId && resolvedLineItemId) {
                this._applicationLineItemId = resolvedLineItemId;
            }
            if (!this.assetId && resolvedAssetId) {
                this._assetId = resolvedAssetId;
            }

            this._applyPddDocuments(data?.pddDocuments);
            if (data?.handoverClosed === true) {
                this._applyFullyCompletedState();
                this._cacheCurrentContextState();
            }
            this._applyRepaymentSetup(data?.repaymentSetup);
            this._applySecuritySections(data);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('[PostDisbursementTrackingScreen] fetchContextData:', error);
            this.showToast('Error', this.labels.loadError, 'error');
        }
    }

    async persistTrackingCompletion(markHandoverClosed = false) {
        if (!this.recordId) {
            return false;
        }
        this._showGlobalLoaderIndicator('Saving...');
        try {
            const response = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_SAVE_TRACKING,
                recordId: this.recordId,
                params: {
                    ...this._buildRequestScope(),
                    handoverClosed: markHandoverClosed || this.handoverClosed
                }
            });
            if (!response?.isSuccess) {
                this.showToast('Error', response?.loadError || this.labels.saveError, 'error');
                return false;
            }
            return true;
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('[PostDisbursementTrackingScreen] persistTrackingCompletion:', error);
            this.showToast('Error', this.labels.saveError, 'error');
            return false;
        } finally {
            this._hideGlobalLoaderIndicator();
        }
    }

    _applyRepaymentSetup(repaymentSetup) {
        if (!repaymentSetup || typeof repaymentSetup !== 'object') {
            this.mappedRepaymentFields = mapDetailFields(
                REPAYMENT_FIELDS.map((field) => ({
                    ...field,
                    value: '—'
                }))
            );
            return;
        }

        const overridesByLabel = {
            Mandate: repaymentSetup.mandate,
            'EMI Amount': this._formatInr(repaymentSetup.emiAmount),
            'First EMI Date': this._formatDate(repaymentSetup.firstEmiDate),
            Tenure: repaymentSetup.tenure,
            'Mandate Reference': repaymentSetup.mandateReference,
            'Debit Account': repaymentSetup.debitAccount,
            'Repayment Mode': repaymentSetup.repaymentMode,
            'Bounce Charge Rule': repaymentSetup.bounceChargeRule
        };

        const mergedFields = REPAYMENT_FIELDS.map((field) => ({
            ...field,
            value:
                overridesByLabel[field.label] !== undefined &&
                overridesByLabel[field.label] !== null &&
                String(overridesByLabel[field.label]).trim() !== ''
                    ? overridesByLabel[field.label]
                    : '—',
            badgeLabel:
                field.label === 'Mandate' &&
                overridesByLabel.Mandate !== undefined &&
                overridesByLabel.Mandate !== null &&
                String(overridesByLabel.Mandate).trim() !== ''
                    ? String(overridesByLabel.Mandate).trim()
                    : null,
            badgeTone:
                field.label === 'Mandate' &&
                overridesByLabel.Mandate !== undefined &&
                overridesByLabel.Mandate !== null &&
                String(overridesByLabel.Mandate).trim() !== ''
                    ? 'success'
                    : null
        }));
        this.mappedRepaymentFields = mapDetailFields(mergedFields);
    }

    _applySecuritySections(data) {
        this._applyHypothecationDetails(data?.hypothecationDetails, data?.hypothecationAlert);
        this._applyInsuranceDetails(data?.insuranceDetails);
    }

    _applyPddDocuments(pddDocuments) {
        if (!Array.isArray(pddDocuments) || pddDocuments.length === 0) {
            this.summaryStats = computeSummaryStats(this.pddDocuments);
            return;
        }

        const defaultsById = new Map(clonePddDocuments().map((doc) => [doc.id, doc]));
        const mergedRows = pddDocuments.map((row) => {
            const rowId = String(row?.id || '').trim();
            const defaults = defaultsById.get(rowId) || {};
            const status = String(row?.status || '').trim() || defaults.status || 'Pending';
            const canMarkReceived = row?.canMarkReceived === false ? false : status !== 'Received';
            const parsedAgeing = Number(row?.ageingDays);
            return {
                ...defaults,
                ...row,
                id: rowId || defaults.id,
                documentName: row?.documentName || defaults.documentName,
                owner: row?.owner || defaults.owner,
                expectedDate: this._resolveDisplayValue(this._formatDate(row?.expectedDate)),
                ageingDays: Number.isNaN(parsedAgeing) ? 0 : Math.max(0, parsedAgeing),
                status,
                canMarkReceived
            };
        });

        this.pddDocuments = mergedRows;
        this.summaryStats = computeSummaryStats(this.pddDocuments);
        this.setQcChecklistItemCompletion(
            'pdds',
            this.pddDocuments.every((doc) => doc.status === 'Received')
        );
        this._cacheCurrentContextState();
    }

    _applyHypothecationDetails(hypothecationDetails, hypothecationAlert) {
        const details = hypothecationDetails && typeof hypothecationDetails === 'object'
            ? hypothecationDetails
            : {};

        const endorsement = this._resolveDisplayValue(details.endorsementStatus);
        const mergedFields = HYPOTHECATION_FIELDS.map((field) => {
            if (field.label === 'Endorsement') {
                return {
                    ...field,
                    value: endorsement,
                    badgeLabel: endorsement !== '—' ? endorsement : null,
                    badgeTone: endorsement !== '—' && endorsement.toLowerCase() === 'completed'
                        ? 'success'
                        : endorsement !== '—'
                            ? 'warning'
                            : null
                };
            }

            if (field.label === 'Registration No.') {
                return { ...field, value: this._resolveDisplayValue(details.registrationNo) };
            }

            if (field.label === 'Hypothecatee') {
                return { ...field, value: this._resolveDisplayValue(details.hypothecatee) };
            }

            if (field.label === 'Marked On') {
                return { ...field, value: this._resolveDisplayValue(this._formatDate(details.markedOn)) };
            }

            if (field.label === 'RC Retention Applicable') {
                return { ...field, value: this._resolveDisplayValue(details.rcRetentionApplicable) };
            }

            return { ...field, value: '—' };
        });

        this.mappedHypothecationFields = mapDetailFields(mergedFields);
        this.hypothecationAlert = this._resolveDisplayValue(hypothecationAlert) === '—'
            ? null
            : String(hypothecationAlert).trim();
    }

    _applyInsuranceDetails(insuranceDetails) {
        const details = insuranceDetails && typeof insuranceDetails === 'object'
            ? insuranceDetails
            : {};

        const bankInterest = this._resolveDisplayValue(details.bankInterest);
        const mergedFields = INSURANCE_FIELDS.map((field) => {
            if (field.label === 'Policy Type') {
                return { ...field, value: this._resolveDisplayValue(details.policyType) };
            }
            if (field.label === 'Sum Insured (IDV)') {
                return { ...field, value: this._resolveDisplayValue(this._formatInr(details.sumInsuredIdv)) };
            }
            if (field.label === 'Motor Insurance Premium') {
                return { ...field, value: this._resolveDisplayValue(this._formatInr(details.motorInsurancePremium)) };
            }
            if (field.label === 'Bank Interest') {
                return {
                    ...field,
                    value: bankInterest,
                    badgeLabel: bankInterest !== '—' ? bankInterest : null,
                    badgeTone:
                        bankInterest !== '—' && bankInterest.toLowerCase().includes('hypothecatee')
                            ? 'success'
                            : bankInterest !== '—'
                                ? 'warning'
                                : null
                };
            }
            if (field.label === 'Valid Till') {
                return { ...field, value: this._resolveDisplayValue(this._formatDate(details.validTill)) };
            }
            return { ...field, value: '—' };
        });

        this.mappedInsuranceFields = mapDetailFields(mergedFields);
    }

    _resolveDisplayValue(value) {
        if (value === undefined || value === null) {
            return '—';
        }
        const text = String(value).trim();
        return text ? text : '—';
    }

    _formatInr(value) {
        const amount = Number(value);
        if (Number.isNaN(amount)) {
            return null;
        }
        return INR_NO_DECIMALS.format(amount);
    }

    _formatDate(value) {
        if (!value) {
            return null;
        }
        const dateValue = new Date(value);
        if (Number.isNaN(dateValue.getTime())) {
            return null;
        }
        const day = String(dateValue.getDate()).padStart(2, '0');
        const month = dateValue.toLocaleString('en-US', { month: 'short' });
        const year = dateValue.getFullYear();
        return `${day}-${month}-${year}`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}