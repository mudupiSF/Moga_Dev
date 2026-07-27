import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';

import {
    APEX_CLASS,
    APEX_METHOD_GET_PAGE_DATA,
    APEX_METHOD_SAVE,
    LABELS,
    PD_TYPE_OPTIONS,
    PD_MODE_OPTIONS,
    VERIFICATION_STATUS_OPTIONS,
    RECOMMENDATION_OPTIONS,
    mapParticipant,
    mapSummaryCard,
    mapVerificationChecklistItems,
    buildEmptyForm,
    hasChecklistFlag,
    normalizeVerificationChecklist,
    resolvePdReadOnly,
    buildDisplayValues,
    sanitizeContactNumber,
    getContactNumberValidationError,
    sortPdParticipantsByBusinessOrder,
    sortPdVerificationFormsByParticipantOrder
} from './pdScreenConstants';

export default class PdScreen extends LightningElement {
    @api recordId;

    labels = LABELS;
    pdTypeOptions = PD_TYPE_OPTIONS;
    pdModeOptions = PD_MODE_OPTIONS;
    verificationStatusOptions = VERIFICATION_STATUS_OPTIONS;
    recommendationOptions = RECOMMENDATION_OPTIONS;

    investigationId = null;
    applicationId = null;
    investigationStatus = '';
    isClosed = false;
    isLoading = true;
    isSaving = false;

    summaryCounts = {
        pendingCount: 0,
        inProgressCount: 0,
        completedCount: 0,
        flagsRaisedCount: 0
    };

    participants = [];
    verificationForms = [];
    selectedVerificationId = null;
    activeForm = buildEmptyForm();

    @track isReadOnly = false;
    @track checklistItems = [];
    @track displayValues = buildDisplayValues();

    pageRef;
    _loadedRecordId;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.pageRef = pageRef;
        this.loadPageData();
    }

    connectedCallback() {
        this.loadPageData();
    }

    get summaryCards() {
        return [
            mapSummaryCard('pending', this.labels.pdPending, this.summaryCounts.pendingCount, 'pending'),
            mapSummaryCard('inProgress', this.labels.inProgress, this.summaryCounts.inProgressCount, 'progress'),
            mapSummaryCard('completed', this.labels.completed, this.summaryCounts.completedCount, 'completed'),
            mapSummaryCard('flags', this.labels.flagsRaised, this.summaryCounts.flagsRaisedCount, 'danger')
        ];
    }

    get participantItems() {
        return this.participants.map((participant) =>
            mapParticipant(participant, this.selectedVerificationId)
        );
    }

    get hasParticipants() {
        return this.participants.length > 0;
    }

    get selectedParticipantName() {
        return this.activeForm.applicantName || '';
    }

    get hasSelectedParticipant() {
        return Boolean(this.selectedVerificationId);
    }

    get selectedParticipantRole() {
        const participant = this.participants.find(
            (item) => item.verificationId === this.selectedVerificationId
        );
        return participant?.roleLabel || '';
    }

    get discussionTitle() {
        return this.selectedParticipantName
            ? `${this.labels.personalDiscussionPrefix} – ${this.selectedParticipantName}`
            : this.labels.personalDiscussionPrefix;
    }

    get discussionSubtitle() {
        return this.selectedParticipantRole || this.labels.pageSubtitle;
    }

    get saveDisabled() {
        return this.isSaving || this.isReadOnly || !this.selectedVerificationId;
    }

    get contactNumberError() {
        const value = this.activeForm.contactNumber;
        return String(value || '').trim() ? getContactNumberValidationError(value) : '';
    }

    syncReadOnlyState() {
        this.isReadOnly = resolvePdReadOnly(this.activeForm, this.isClosed);
    }

    refreshChecklistItems() {
        this.checklistItems = mapVerificationChecklistItems(
            this.activeForm.verificationChecklist,
            this.isReadOnly
        );
    }

    refreshDisplayValues() {
        this.displayValues = buildDisplayValues(this.activeForm);
    }

    refreshFormViewState({ syncReadOnly = false } = {}) {
        if (syncReadOnly) {
            this.syncReadOnlyState();
        }
        this.refreshChecklistItems();
        this.refreshDisplayValues();
    }

    getRecordId() {
        return this.recordId || this.pageRef?.state?.c__recordId || null;
    }

    async loadPageData(forceReload = false) {
        const contextRecordId = this.getRecordId();
        if (!contextRecordId) {
            this.isLoading = false;
            return;
        }
        if (!forceReload && contextRecordId === this._loadedRecordId && this.investigationId) {
            return;
        }
        this._loadedRecordId = contextRecordId;
        this.isLoading = true;

        try {
            const data = await getPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_GET_PAGE_DATA,
                recordId: contextRecordId,
                params: {}
            });
            this.applyPageData(data || {});
        } catch (error) {
            this.showToast('Error', this.resolveErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    applyPageData(data) {
        this.investigationId = data.investigationId || null;
        this.applicationId = data.applicationId || null;
        this.investigationStatus = data.investigationStatus || '';
        this.isClosed = Boolean(data.isClosed);
        this.summaryCounts = data.summaryCounts || {
            pendingCount: 0,
            inProgressCount: 0,
            completedCount: 0,
            flagsRaisedCount: 0
        };
        const rawParticipants = Array.isArray(data.participants) ? data.participants : [];
        const rawVerificationForms = Array.isArray(data.verificationForms) ? data.verificationForms : [];
        const verificationIds = new Set(rawVerificationForms.map((form) => form.verificationId));
        this.participants = sortPdParticipantsByBusinessOrder(
            rawParticipants.filter((participant) => verificationIds.has(participant.verificationId))
        );
        this.verificationForms = sortPdVerificationFormsByParticipantOrder(
            rawVerificationForms,
            this.participants
        );

        if (
            !this.selectedVerificationId
            || !this.verificationForms.some((form) => form.verificationId === this.selectedVerificationId)
        ) {
            this.selectedVerificationId = this.verificationForms[0]?.verificationId || null;
        }
        this.syncActiveForm();
    }

    syncActiveForm() {
        const selectedForm = this.verificationForms.find(
            (form) => form.verificationId === this.selectedVerificationId
        );
        if (selectedForm) {
            const verificationChecklist = normalizeVerificationChecklist(
                selectedForm.verificationChecklist || {}
            );
            this.activeForm = {
                ...selectedForm,
                verificationChecklist,
                flagRaised: hasChecklistFlag(verificationChecklist)
            };
            this.refreshFormViewState({ syncReadOnly: true });
            return;
        }
        this.activeForm = buildEmptyForm();
        this.refreshFormViewState({ syncReadOnly: true });
    }

    handleParticipantSelect(event) {
        const verificationId = event.currentTarget.dataset.verificationId;
        if (!verificationId || verificationId === this.selectedVerificationId) {
            return;
        }
        this.persistActiveFormToCache();
        this.selectedVerificationId = verificationId;
        this.syncActiveForm();
    }

    persistActiveFormToCache() {
        if (!this.selectedVerificationId) {
            return;
        }
        this.verificationForms = this.verificationForms.map((form) => (
            form.verificationId === this.selectedVerificationId
                ? { ...this.activeForm }
                : form
        ));
    }

    handleFieldChange(event) {
        if (this.isReadOnly) {
            return;
        }
        const fieldName = event.target.dataset.field;
        if (!fieldName) {
            return;
        }
        let value = event.target.type === 'checkbox'
            ? event.target.checked
            : event.detail?.value ?? event.target.value;
        if (fieldName === 'contactNumber') {
            value = sanitizeContactNumber(value);
            if (event.target.value !== undefined && event.target.value !== value) {
                event.target.value = value;
            }
        }
        this.activeForm = { ...this.activeForm, [fieldName]: value };
        this.refreshDisplayValues();
    }

    handleContactNumberBlur() {
        this.reportContactNumberValidity();
    }

    reportContactNumberValidity() {
        const error = getContactNumberValidationError(this.activeForm.contactNumber);
        const input = this.template.querySelector('lightning-input[name="contactNumber"]');
        if (input?.setCustomValidity) {
            input.setCustomValidity(error);
            input.reportValidity();
        }
        return !error;
    }

    validateContactNumberBeforeSave() {
        const error = getContactNumberValidationError(this.activeForm.contactNumber);
        if (!error) {
            return true;
        }
        this.reportContactNumberValidity();
        this.showToast('Error', error, 'error');
        return false;
    }

    buildSaveFormData() {
        const form = this.activeForm;
        return {
            pdType: form.pdType || '',
            pdMode: form.pdMode || '',
            verificationWith: form.verificationWith || '',
            contactNumber: form.contactNumber || '',
            applicantProfileObservations: form.applicantProfileObservations || '',
            overallRemarks: form.overallRemarks || '',
            additionalRemarks: form.additionalRemarks || '',
            verificationStatus: form.verificationStatus || '',
            recommendation: form.recommendation || '',
            finalRemarks: form.finalRemarks || '',
            verificationChecklist: normalizeVerificationChecklist(form.verificationChecklist || {})
        };
    }

    handleChecklistAnswer(event) {
        if (this.isReadOnly) {
            return;
        }
        const itemKey = event.currentTarget.dataset.checklistKey;
        const answer = event.currentTarget.dataset.answer;
        if (!itemKey || !answer || !['Yes', 'No'].includes(answer)) {
            return;
        }
        const verificationChecklist = normalizeVerificationChecklist({
            ...(this.activeForm.verificationChecklist || {}),
            [itemKey]: answer
        });
        this.activeForm = {
            ...this.activeForm,
            verificationChecklist,
            flagRaised: hasChecklistFlag(verificationChecklist)
        };
        if (this.activeForm.flagRaised) {
            this.isReadOnly = false;
        }
        this.refreshChecklistItems();
    }

    async handleSave() {
        if (this.saveDisabled) {
            return;
        }
        if (!this.activeForm.verificationStatus) {
            this.showToast('Error', this.labels.verificationStatusRequired, 'error');
            return;
        }
        if (!this.validateContactNumberBeforeSave()) {
            return;
        }

        this.isSaving = true;
        try {
            this.persistActiveFormToCache();
            const result = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_SAVE,
                recordId: this.activeForm.verificationId,
                params: {
                    formData: this.buildSaveFormData()
                }
            });

            if (!result?.isSuccess) {
                this.showToast('Error', result?.message || this.labels.saveError, 'error');
                return;
            }

            this.showToast('Success', result.message || this.labels.saveSuccess, 'success');
            const verificationChecklist = normalizeVerificationChecklist(
                this.activeForm.verificationChecklist || {}
            );
            const flagRaised = hasChecklistFlag(verificationChecklist);
            this.activeForm = {
                ...this.activeForm,
                verificationChecklist,
                isSubmitted: true,
                flagRaised,
                verificationStatus: flagRaised && ['Completed', 'Accepted'].includes(this.activeForm.verificationStatus)
                    ? 'In Progress'
                    : this.activeForm.verificationStatus,
                pdDateTime: this.activeForm.pdDateTime || new Date().toISOString()
            };
            this.persistActiveFormToCache();
            this.refreshFormViewState({ syncReadOnly: true });
            await this.loadPageData(true);
        } catch (error) {
            this.showToast('Error', this.resolveErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
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