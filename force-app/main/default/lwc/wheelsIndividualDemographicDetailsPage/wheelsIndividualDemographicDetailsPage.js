/**
 * wheelsIndividualDemographicDetailsPage — Demographic Details stage for loan applications.
 * Sections: Lifecycle, Data loading, Field handlers, Signature upload, Next/Save, UI getters, Utilities.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';
import loadDemographicData from '@salesforce/apex/WheelsIndividualDemographicController.loadDemographicData';
import saveDemographicData from '@salesforce/apex/WheelsIndividualDemographicController.saveDemographicData';
import initOrGetDocumentWithApplicantId from '@salesforce/apex/WheelsIndividualDemographicController.initOrGetDocumentWithApplicantId';
import linkContentDocument from '@salesforce/apex/WheelsIndividualDemographicController.linkContentDocument';
import getFileType from '@salesforce/apex/RepaymentMandateController.getFileType';
import deleteContentDocument from '@salesforce/apex/RepaymentMandateController.deleteContentDocument';

const DOCUMENT_TYPE_CUSTOMER_SIGNATURE = 'Customer Signature';
const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const STAGE_DEMOGRAPHIC_DETAILS = 'Demographic Details';
const DEMOGRAPHIC_OPS_VIEW_TOKEN = 'Demographic_Details_Operations';
const FIELD_DEMOGRAPHIC_CORRECTLY_CAPTURED = 'Demographic_Details_Correctly_Captured__c';
const FIELD_REMARKS = 'Remarks__c';

const REQUIRED_APPLICANT_FIELDS = [
    { label: 'Preferred address for communication', prop: 'preferredAddressForCommunication' },
    { label: 'Communication Language', prop: 'communicationLanguage' },
    { label: "Father's Name", prop: 'fatherName' },
    { label: "Mother's Name", prop: 'motherName' },
    { label: 'Religion', prop: 'religion' },
    { label: 'Caste', prop: 'caste' },
    { label: 'Customer Qualification', prop: 'qualification' },
    { label: 'Relationship with borrower', prop: 'relationshipWithBorrower' }
];

const REQUIRED_REFERENCE_FIELDS = [
    { label: 'Name', suffix: 'Name' },
    { label: 'Relationship with borrower', suffix: 'Relationship' },
    { label: 'Phone number', suffix: 'Phone' },
    { label: 'Address line 1', suffix: 'AddressLine1' },
    { label: 'Address line 2', suffix: 'AddressLine2' },
    { label: 'Pin code', suffix: 'Pincode' },
    { label: 'City', suffix: 'City' },
    { label: 'State', suffix: 'State' }
];

export default class WheelsIndividualDemographicDetailsPage extends LightningElement {
    /** Application__c record Id (passed from applicationMasterPage). */
    @api recordId;
    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api applicantId;
    @api isStagePast = false;
    @api applicationStatus;

    /** Passed when loaded via listOfApplicants group flow; unused on direct stage load. */
    @api applicants;
    @api applicantCompletionOverrides;
    @api groupLabel;
    @api overrideLwc;

    @track isPageLoading = false;
    isDataUpdated = false;

    @track _isApplicantStageComplete = false;
    _serverReadOnly = false;
    _hasLoadedData = false;
    _prevStagePastView;
    _prevCurrentViewId = '';

    @track signatureUploaded = false;
    @track signatureFileName = '';
    @track signatureDocumentId = '';
    @track signatureUploadedAt = '';
    @track signatureDocumentChecklistId = '';
    @track signatureFileType = 'PNG';
    @track openPreviewModal = false;
    @track contentDocumentId;
    @track fileType;

    signatureAcceptedFormats = ['.png', '.jpg', '.jpeg'];

    demographicCorrectlyCapturedOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    preferredAddressOptions = [
        { label: 'Permanent Residential Address', value: 'Permanent Residential Address' },
        { label: 'Current Residential Address', value: 'Current Residential Address' },
        { label: 'Office Address', value: 'Office Address' },
    ];

    communicationLanguageOptions = [
        { label: 'Hindi', value: 'Hindi' },
        { label: 'English', value: 'English' },
        { label: 'Tamil', value: 'Tamil' },
        { label: 'Telugu', value: 'Telugu' },
        { label: 'Kannada', value: 'Kannada' },
        { label: 'Malayalam', value: 'Malayalam' },
        { label: 'Bengali', value: 'Bengali' },
        { label: 'Marathi', value: 'Marathi' },
        { label: 'Gujarati', value: 'Gujarati' },
        { label: 'Punjabi', value: 'Punjabi' },
        { label: 'Odia', value: 'Odia' },
        { label: 'Other', value: 'Other' }
    ];

    religionOptions = [
        { label: 'Hindu', value: 'Hindu' },
        { label: 'Muslim', value: 'Muslim' },
        { label: 'Christian', value: 'Christian' },
        { label: 'Sikh', value: 'Sikh' },
        { label: 'Buddhist', value: 'Buddhist' },
        { label: 'Jain', value: 'Jain' },
        { label: 'Other', value: 'Other' }
    ];

    casteOptions = [
        { label: 'General', value: 'General' },
        { label: 'OBC', value: 'OBC' },
        { label: 'SC', value: 'SC' },
        { label: 'ST', value: 'ST' },
        { label: 'Other', value: 'Other' }
    ];

    qualificationOptions = [
        { label: 'Post Graduate', value: 'Post Graduate' },
        { label: 'Graduate', value: 'Graduate' },
        { label: 'HSC/Diploma', value: 'HSC/Diploma' },
        { label: 'SSC', value: 'SSC' },
        { label: 'Below SSC', value: 'Below SSC' },
        { label: 'Professional', value: 'Professional' },
        { label: 'Other', value: 'Other' }
    ];

    relationshipOptions = [
        { label: 'Self', value: 'Self' },
        { label: 'Father', value: 'Father' },
        { label: 'Mother', value: 'Mother' },
        { label: 'Spouse', value: 'Spouse' },
        { label: 'Son', value: 'Son' },
        { label: 'Daughter', value: 'Daughter' },
        { label: 'Brother', value: 'Brother' },
        { label: 'Sister', value: 'Sister' },
        { label: 'Friend', value: 'Friend' },
        { label: 'Relative', value: 'Relative' },
        { label: 'Colleague', value: 'Colleague' },
        { label: 'Other', value: 'Other' }
    ];

    @track preferredAddressForCommunication = '';
    @track communicationLanguage = '';
    @track fatherName = '';
    @track motherName = '';
    @track religion = '';
    @track caste = '';
    @track qualification = '';
    @track applicantType = '';
    @track relationshipWithBorrower = '';
    @track demographicDetailsCorrectlyCaptured = '';
    @track remarks = '';

    @track reference1Id = '';
    @track reference1AddressId = '';
    @track reference1Name = '';
    @track reference1Relationship = '';
    @track reference1Phone = '';
    @track reference1AddressLine1 = '';
    @track reference1AddressLine2 = '';
    @track reference1Pincode = '';
    @track reference1City = '';
    @track reference1State = '';

    @track reference2Id = '';
    @track reference2AddressId = '';
    @track reference2Name = '';
    @track reference2Relationship = '';
    @track reference2Phone = '';
    @track reference2AddressLine1 = '';
    @track reference2AddressLine2 = '';
    @track reference2Pincode = '';
    @track reference2City = '';
    @track reference2State = '';

    // ── Lifecycle ─────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadData();
    }

    renderedCallback() {
        if (!this._hasLoadedData) {
            return;
        }

        const stagePastView = this.isStagePastView;
        const viewId = this.currentViewId || '';

        if (
            stagePastView === this._prevStagePastView &&
            viewId === this._prevCurrentViewId
        ) {
            return;
        }

        this._prevStagePastView = stagePastView;
        this._prevCurrentViewId = viewId;
        this.applyCurrentStageEditableUi();
    }

    // ── Data loading (connectedCallback → loadData → mapDataToFields) ───────

    loadData() {
        if (!this.recordId) {
            this.isPageLoading = false;
            return;
        }

        this.isPageLoading = true;

        loadDemographicData({
            recordId: this.recordId,
            applicantId: this.applicantId || null
        })
        .then(async (result) => {
            this.mapDataToFields(result);
            await this.applyCurrentStageEditableUi();
            this._prevStagePastView = this.isStagePastView;
            this._prevCurrentViewId = this.currentViewId || '';
            this._hasLoadedData = true;
        })
        .catch((error) => {
            this.showError('Error loading data', error);
        })
        .finally(() => {
            this.isPageLoading = false;
        });
    }

    mapDataToFields(data) {
        if (!data) {
            return;
        }

        this._serverReadOnly = data.isReadOnly === true;

        const applicant = data.applicant || {};
        const signature = data.signature || {};

        this.applicantId = this.applicantId || applicant.id || '';
        this.applicantType = applicant.applicantType || '';

        this.preferredAddressForCommunication = applicant.preferredAddressForCommunication || '';
        this.communicationLanguage = applicant.communicationLanguage || '';
        this.fatherName = applicant.fatherName || '';
        this.motherName = applicant.motherName || '';
        this.religion = applicant.religion || '';
        this.caste = applicant.caste || '';
        this.qualification = applicant.qualification || '';
        this.relationshipWithBorrower = applicant.relationshipWithBorrower || '';
        this.demographicDetailsCorrectlyCaptured = applicant.demographicDetailsCorrectlyCaptured || '';
        this.remarks = applicant.remarks || '';

        const references = data.references || [];
        if (references[0]) {
            this.mapReferenceToFields(references[0], 1);
        }
        if (references[1]) {
            this.mapReferenceToFields(references[1], 2);
        }

        this.signatureDocumentChecklistId = signature.documentChecklistId || '';
        if (signature.uploaded) {
            this.signatureUploaded = true;
            this.signatureFileName = signature.fileName || '';
            this.signatureDocumentId = signature.contentDocumentId || '';
            this.signatureUploadedAt = signature.uploadedAt || '';
        }
    }

    mapReferenceToFields(ref, index) {
        if (!ref || (index !== 1 && index !== 2)) {
            return;
        }

        const refApplicant = ref.applicant || {};
        const addr = ref.address || {};
        const prefix = `reference${index}`;

        this[`${prefix}Id`] = refApplicant.id || '';
        this[`${prefix}AddressId`] = addr.id || '';
        this[`${prefix}Name`] = refApplicant.name || '';
        this[`${prefix}Relationship`] = refApplicant.relationshipWithBorrower || '';
        this[`${prefix}Phone`] = refApplicant.contactNumber || '';
        this[`${prefix}AddressLine1`] = addr.addressLine1 || '';
        this[`${prefix}AddressLine2`] = addr.addressLine2 || '';
        this[`${prefix}City`] = addr.city || '';
        this[`${prefix}State`] = addr.state || '';
        this[`${prefix}Pincode`] = addr.pinCode || '';
    }

    /**
     * On the current applicant stage (not past, not externally disabled), keep fields editable and
     * show upload/delete actions even when server data is already complete.
     */
    async applyCurrentStageEditableUi() {
        if (this.isStagePastView || this.applicationStatus?.isWithdrawn === true) {
            return;
        }

        if (!this.isDemographicOpsView) {
            this._isApplicantStageComplete = false;
            await this.ensureSignatureDocumentId();
        }
    }

    async ensureSignatureDocumentId() {
        if (!this.recordId || !this.applicantId) {
            return;
        }

        try {
            this.signatureDocumentChecklistId = await initOrGetDocumentWithApplicantId({
                applicationId: this.recordId,
                documentType: DOCUMENT_TYPE_CUSTOMER_SIGNATURE,
                applicantId: this.applicantId
            });
        } catch (error) {
            console.error('Error initializing customer signature document checklist:', error);
        }
    }

    // ── Field change handler ────────────────────────────────────────────────

    handleFieldChange(event) {
        const field = event.target.name;
        const value =
            event.detail?.value !== undefined ? event.detail.value : event.target.value;
        if (field) {
            this[field] = value;
            this.isDataUpdated = true;
        }
    }

    // ── Signature upload ────────────────────────────────────────────────────

    async handleSignatureUploadFinished(event) {
        if (this.isDocumentsDisabled || !this.isFieldEditable) {
            return;
        }

        const uploadedFiles = event.detail?.files || [];
        if (!uploadedFiles.length) {
            return;
        }

        const file = uploadedFiles[0];
        const contentDocumentId = file.documentId || '';

        try {
            if (!this.recordId || !this.applicantId) {
                this.showError('Upload Failed', 'Missing application or applicant details.');
                return;
            }

            await this.ensureSignatureDocumentId();

            await linkContentDocument({
                documentDataJson: JSON.stringify({
                    documentType: DOCUMENT_TYPE_CUSTOMER_SIGNATURE,
                    applicationId: this.recordId,
                    applicantId: this.applicantId,
                    contentDocumentId
                })
            });

            const uploadedFileType = await getFileType({ contentDocumentId });
            this.signatureUploaded = true;
            this.signatureFileName = file.name || '';
            this.signatureDocumentId = contentDocumentId;
            this.signatureFileType = uploadedFileType;
            this.signatureUploadedAt = new Date().toLocaleString();
            this.isDataUpdated = true;

            this.showSuccess('Customer signature uploaded successfully');
        } catch (error) {
            this.showError('Upload Failed', error);
        }
    }

    async handleSignatureDelete() {
        if (
            this.isDocumentsDisabled ||
            !this.isFieldEditable ||
            !this.signatureUploaded ||
            !this.signatureDocumentId
        ) {
            return;
        }

        try {
            await deleteContentDocument({
                contentDocumentId: this.signatureDocumentId
            });
            this.signatureUploaded = false;
            this.signatureDocumentId = '';
            this.signatureFileName = '';
            this.signatureUploadedAt = '';
            this.signatureFileType = 'PNG';
            this.isDataUpdated = true;
            this.showSuccess('Customer signature removed');
        } catch (error) {
            this.showError('Delete Failed', error);
        }
    }

    handleSignaturePreview() {
        if (!this.signatureDocumentId) {
            return;
        }
        this.contentDocumentId = this.signatureDocumentId;
        this.fileType = this.signatureFileType || 'PNG';
        this.openPreviewModal = true;
    }

    handleFilePreviewClose() {
        this.openPreviewModal = false;
        this.contentDocumentId = null;
        this.fileType = null;
    }

    // ── Next / Save (handleNextButton → validateFields → save → requestNextStage) ──

    /**
     * Footer Next: navigate when read-only, save when dirty, otherwise validate and advance.
     */
    async handleNextButton() {
        if (this.applicationStatus?.isWithdrawn === true) {
            return;
        }

        if (this.isStagePastView) {
            return;
        }

        if (this.isDemographicOpsView) {
            if (!this.isDemographicRemarksEditable) {
                await this.markStepAndNavigate();
                return;
            }

            if (!this.validateFields()) {
                return;
            }

            this.isPageLoading = true;
            try {
                await this.updateRecordDetails({
                    Id: this.applicantId,
                    [FIELD_DEMOGRAPHIC_CORRECTLY_CAPTURED]: this.demographicDetailsCorrectlyCaptured,
                    [FIELD_REMARKS]: this.remarks
                });
                this.showSuccess('Demographic remarks saved successfully');
                this.isDataUpdated = false;
                await this.markStepAndNavigate();
            } catch (error) {
                this.showError('Error saving demographic remarks', error);
            } finally {
                this.isPageLoading = false;
            }
            return;
        }

        if (this.isReadOnlyScreen) {
            await this.markStepAndNavigate();
            return;
        }

        if (this.isNextDisabled) {
            return;
        }

        if (!this.isDataUpdated) {
            if (!this.validateFields()) {
                return;
            }
            await this.markStepAndNavigate();
            return;
        }

        if (!this.validateFields()) {
            return;
        }

        this.isPageLoading = true;
        const dataJson = JSON.stringify(this.prepareDataForSave());

        try {
            const result = await saveDemographicData({
                recordId: this.recordId,
                applicantId: this.applicantId || null,
                dataJson
            });
            if (!result.success) {
                this.showError('Save Failed', result.message);
                return;
            }

            this.showSuccess(result.message || 'Details saved successfully');
            this.isDataUpdated = false;
            this._markSubmittedReadOnly();
            this.dispatchSaveEvent();
            await this.markStepAndNavigate();
        } catch (error) {
            this.showError('Error saving details', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async markStepAndNavigate() {
        if (!this.applicantId) {
            this.showWarning('Applicant is required to continue.');
            return;
        }

        this.requestNextStage();
    }

    requestNextStage() {
        const currentViewId = this.currentViewId;
        if (!currentViewId) {
            this.showError('Navigation Error', 'Current view ID is missing. Please refresh the page.');
            return;
        }

        window.dispatchEvent(
            new CustomEvent(LOS_NEXT_STAGE_EVENT, {
                detail: {
                    currentViewId,
                    id: currentViewId,
                    applicantId: this.applicantId,
                    currentLoanStageComplete: this.tab || STAGE_DEMOGRAPHIC_DETAILS,
                    currentStagePhrase: this.stagePhrase || ''
                },
                bubbles: true,
                composed: true
            })
        );
    }

    validateFields() {
        if (this.isDemographicOpsView && this.isDemographicRemarksEditable) {
            if (!this.hasFieldValue(this.demographicDetailsCorrectlyCaptured)) {
                this.showWarning('Please select Demographic Details Correctly Captured');
                return false;
            }
            if (!this.hasFieldValue(this.remarks)) {
                this.showWarning('Please enter Remarks');
                return false;
            }
            return true;
        }

        return this.validateApplicantStageFields(true);
    }

    validateApplicantStageFields(showWarnings = false) {
        for (const field of REQUIRED_APPLICANT_FIELDS) {
            if (!this.hasFieldValue(this[field.prop])) {
                if (showWarnings) {
                    this.showWarning(`Please enter ${field.label}`);
                }
                return false;
            }
        }

        if (this.showReferenceSection) {
            if (!this.validateReferenceFields('Reference 1', 'reference1', showWarnings)) {
                return false;
            }

            if (!this.validateReferenceFields('Reference 2', 'reference2', showWarnings)) {
                return false;
            }
        }

        if (!this.signatureUploaded) {
            if (showWarnings) {
                this.showWarning('Please upload customer signature before proceeding.');
            }
            return false;
        }

        return true;
    }

    validateReferenceFields(referenceLabel, prefix, showWarnings = false) {
        for (const field of REQUIRED_REFERENCE_FIELDS) {
            const prop = `${prefix}${field.suffix}`;
            if (!this.hasFieldValue(this[prop])) {
                if (showWarnings) {
                    this.showWarning(`Please enter ${field.label} for ${referenceLabel}`);
                }
                return false;
            }
        }
        return true;
    }

    prepareDataForSave() {
        const payload = {
            preferredAddressForCommunication: this.preferredAddressForCommunication,
            communicationLanguage: this.communicationLanguage,
            fatherName: this.fatherName,
            motherName: this.motherName,
            religion: this.religion,
            caste: this.caste,
            qualification: this.qualification,
            relationshipWithBorrower: this.relationshipWithBorrower,
            demographicDetailsCorrectlyCaptured: this.demographicDetailsCorrectlyCaptured,
            remarks: this.remarks,
            signature: {
                documentId: this.signatureDocumentId,
                fileName: this.signatureFileName,
                uploadedAt: this.signatureUploadedAt
            }
        };

        if (this.showReferenceSection) {
            payload.reference1 = this.buildReferencePayload('reference1');
            payload.reference2 = this.buildReferencePayload('reference2');
        }

        return payload;
    }

    buildReferencePayload(prefix) {
        const payload = {
            referenceName: this[`${prefix}Name`],
            relationship: this[`${prefix}Relationship`],
            phone: this[`${prefix}Phone`],
            addressLine1: this[`${prefix}AddressLine1`],
            addressLine2: this[`${prefix}AddressLine2`],
            pincode: this[`${prefix}Pincode`],
            city: this[`${prefix}City`],
            state: this[`${prefix}State`]
        };

        const referenceId = this[`${prefix}Id`];
        const addressId = this[`${prefix}AddressId`];
        if (referenceId) {
            payload.referenceId = referenceId;
        }
        if (addressId) {
            payload.addressId = addressId;
        }
        return payload;
    }

    _markSubmittedReadOnly() {
        this._isApplicantStageComplete = true;
    }

    dispatchSaveEvent() {
        this.dispatchEvent(
            new CustomEvent('detailssaved', {
                detail: {
                    message: 'Demographic details saved successfully',
                    data: this.prepareDataForSave()
                }
            })
        );
    }

    // ── UI state getters ────────────────────────────────────────────────────

    get isStagePastView() {
        return this.isStagePast === true || this.isStagePast === 'true';
    }

    get isDemographicOpsView() {
        return (this.currentViewId || '').includes(DEMOGRAPHIC_OPS_VIEW_TOKEN);
    }

    get isReadOnlyScreen() {
        return (
            this.isStagePastView ||
            this._isApplicantStageComplete ||
            this.applicationStatus?.isWithdrawn === true
        );
    }

    get isDemographicRemarksEditable() {
        return this.isDemographicOpsView && !this.isStagePastView;
    }

    get isDocumentsDisabled() {
        return this.isDemographicOpsView || this.isReadOnlyScreen;
    }

    get isFieldEditable() {
        return !this.isReadOnlyScreen && !this.isDemographicOpsView;
    }

    get showReferenceSection() {
        return this.applicantType === 'Borrower';
    }

    get showDocumentActions() {
        return !this.isDocumentsDisabled;
    }

    get showDocumentDelete() {
        return !this.isDocumentsDisabled;
    }

    get isNextDisabled() {
        if (
            this.isPageLoading ||
            this.isStagePastView ||
            this.applicationStatus?.isWithdrawn === true
        ) {
            return true;
        }

        if (this.isDemographicRemarksEditable) {
            return (
                !this.hasFieldValue(this.demographicDetailsCorrectlyCaptured) ||
                !this.hasFieldValue(this.remarks)
            );
        }

        if (this._isApplicantStageComplete) {
            return false;
        }

        if (!this.isDemographicOpsView && !this.isReadOnlyScreen) {
            return !this.validateApplicantStageFields(false);
        }

        return false;
    }

    // ── Record update helper ────────────────────────────────────────────────

    async updateRecordDetails(fields) {
        const recordId = fields?.Id || this.applicantId || null;
        const fieldValues = { ...fields };
        delete fieldValues.Id;

        if (recordId) {
            fieldValues.Id = recordId;
        }

        await updateRecord({ fields: fieldValues });
    }

    hasFieldValue(value) {
        return value != null && String(value).trim() !== '';
    }

    // ── Toast notifications ─────────────────────────────────────────────────

    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message,
                variant: 'success'
            })
        );
    }

    showError(title, error) {
        let message = 'An error occurred';
        if (error?.body?.message) {
            message = error.body.message;
        } else if (error?.message) {
            message = error.message;
        } else if (typeof error === 'string') {
            message = error;
        }

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    showWarning(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Warning',
                message,
                variant: 'warning'
            })
        );
    }
}