import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';

import {
    APEX_CLASS,
    APEX_METHOD_GET_PAGE_DATA,
    APEX_METHOD_SUBMIT,
    DECISION_OPTIONS,
    LABELS,
    SCROLLBAR_HIDE_DELAY_MS,
    mapApplicant,
    mapVerificationRow
} from './amlCheckScreenConstants';

export default class AmlCheckScreen extends LightningElement {
    @api recordId;

    labels = LABELS;
    decisionOptions = DECISION_OPTIONS;

    verificationRows = [];
    applicants = [];
    applicantTabs = [];
    investigationStatus = '';
    isClosed = false;
    canSubmit = false;
    isLoading = true;
    isSubmitting = false;

    selectedApplicantId = null;
    selectedApplicant = null;
    applyDecisionAllValue = '';

    pageRef;
    _loadedInvestigationId;
    _revealedDocKeys = new Set();

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;
        this.loadPageData();
    }

    connectedCallback() {
        this.loadPageData();
    }

    get hasVerificationRows() {
        return this.verificationRows.length > 0;
    }

    get hasApplicants() {
        return this.applicantTabs.length > 0;
    }

    get isApplyDecisionPositive() {
        return this.applyDecisionAllValue === 'Positive';
    }

    get isApplyDecisionFalsePositive() {
        return this.applyDecisionAllValue === 'False Positive';
    }

    get isReadOnly() {
        return this.isClosed;
    }

    get submitDisabled() {
        return this.isSubmitting || !this.canSubmit || !this.hasVerificationRows || this.isReadOnly;
    }

    get submitButtonClass() {
        return this.submitDisabled
            ? 'form-primary-btn form-primary-btn-disabled p4-button-text'
            : 'form-primary-btn p4-button-text';
    }

    getInvestigationId() {
        return (
            this.recordId ||
            this.pageRef?.state?.c__recordId ||
            this.pageRef?.attributes?.recordId ||
            null
        );
    }

    async loadPageData(forceReload = false) {
        const investigationId = this.getInvestigationId();
        if (!investigationId) {
            this.isLoading = false;
            return;
        }
        if (!forceReload && investigationId === this._loadedInvestigationId) {
            return;
        }
        this._loadedInvestigationId = investigationId;
        this.isLoading = true;
        try {
            const data = await getPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_GET_PAGE_DATA,
                recordId: investigationId,
                params: { investigationId }
            });
            this.applyPageData(data || {});
        } catch (error) {
            this.showToast('Error', this.resolveErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    applyPageData(data) {
        this.investigationStatus = data.investigationStatus || '';
        this.isClosed = Boolean(data.isClosed);
        this.canSubmit = Boolean(data.canSubmit);
        this.applicants = data.applicants || [];
        this.verificationRows = (data.verificationRows || []).map(mapVerificationRow);

        if (!this.selectedApplicantId || !this.applicants.some((applicant) => applicant.applicantId === this.selectedApplicantId)) {
            this.selectedApplicantId = this.applicants[0]?.applicantId || null;
        }
        this.syncApplicantView();
    }

    syncApplicantView() {
        this.applicantTabs = this.applicants.map((applicant) => mapApplicant(
            applicant,
            this.selectedApplicantId,
            this._revealedDocKeys
        ));
        this.selectedApplicant = this.applicantTabs.find(
            (applicant) => applicant.applicantId === this.selectedApplicantId
        ) || null;
    }

    handleApplicantTabClick(event) {
        this.selectedApplicantId = event.currentTarget.dataset.applicantId;
        this.syncApplicantView();
    }

    handleScrollArea(event) {
        const element = event.currentTarget;
        element.classList.add('aml-scroll-active');
        const timerId = element.dataset.scrollTimerId;
        if (timerId) {
            window.clearTimeout(Number(timerId));
        }
        const nextTimerId = window.setTimeout(() => {
            element.classList.remove('aml-scroll-active');
            delete element.dataset.scrollTimerId;
        }, SCROLLBAR_HIDE_DELAY_MS);
        element.dataset.scrollTimerId = String(nextTimerId);
    }

    handleDocumentReveal(event) {
        if (event.currentTarget.disabled) {
            return;
        }
        const revealKey = event.currentTarget.dataset.revealKey;
        if (!revealKey) {
            return;
        }
        if (this._revealedDocKeys.has(revealKey)) {
            this._revealedDocKeys.delete(revealKey);
        } else {
            this._revealedDocKeys.add(revealKey);
        }
        this.syncApplicantView();
    }

    handleDecisionChange(event) {
        if (this.isReadOnly) {
            return;
        }
        this.updateRow(Number(event.target.dataset.index), { decision: event.detail.value });
    }

    handleRemarksChange(event) {
        if (this.isReadOnly) {
            return;
        }
        this.updateRow(Number(event.target.dataset.index), { remarks: event.detail.value });
    }

    handleApplyDecisionToAll(event) {
        if (this.isReadOnly) {
            return;
        }
        const value = event.target.value;
        if (!value) {
            return;
        }
        this.applyDecisionAllValue = value;
        this.verificationRows = this.verificationRows.map((row) => ({ ...row, decision: value }));
    }

    handleCopyRemarks() {
        if (this.isReadOnly) {
            return;
        }
        const sourceRemarks = this.verificationRows.find((row) => row.remarks)?.remarks;
        if (!sourceRemarks) {
            this.showToast('Info', this.labels.remarksCopyError, 'info');
            return;
        }
        this.verificationRows = this.verificationRows.map((row) => ({ ...row, remarks: sourceRemarks }));
        this.showToast('Success', this.labels.remarksCopySuccess, 'success');
    }

    async handleSubmit() {
        if (this.isReadOnly) {
            return;
        }
        if (!this.validateRows()) {
            this.showToast('Error', this.labels.mandatoryDetailsError, 'error');
            return;
        }

        const hasPositiveDecision = this.verificationRows.some((row) => row.decision === 'Positive');
        if (hasPositiveDecision) {
            const confirmed = await LightningConfirm.open({
                message: this.labels.positiveWarning,
                label: this.labels.positiveWarningTitle,
                theme: 'warning'
            });
            if (!confirmed) {
                return;
            }
        }

        const investigationId = this._loadedInvestigationId || this.getInvestigationId();
        this.isSubmitting = true;
        try {
            const payload = this.verificationRows.map((row) => ({
                id: row.id,
                decision: row.decision,
                remarks: row.remarks
            }));
            const result = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_SUBMIT,
                recordId: investigationId,
                params: {
                    investigationId,
                    verificationInputs: payload
                }
            });

            if (!result?.isSuccess) {
                this.showToast('Error', result?.message || this.labels.genericError, 'error');
                return;
            }

            this.showToast('Success', result.message || this.labels.submitSuccess, 'success');
            await this.loadPageData(true);
        } catch (error) {
            this.showToast('Error', this.resolveErrorMessage(error), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    validateRows() {
        return this.verificationRows.length > 0
            && this.verificationRows.every((row) => Boolean(row.decision));
    }

    updateRow(index, patch) {
        this.verificationRows = this.verificationRows.map((row, rowIndex) => (
            rowIndex === index ? { ...row, ...patch } : row
        ));
    }

    resolveErrorMessage(error) {
        if (!error) {
            return this.labels.genericError;
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body?.message) {
            return error.body.message;
        }
        return error.message || this.labels.genericError;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}