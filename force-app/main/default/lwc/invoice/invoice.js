import { LightningElement, api, track } from 'lwc';
import getInvoiceData from '@salesforce/apex/InvoiceController.getInvoiceData';
import saveInvoiceData from '@salesforce/apex/InvoiceController.saveInvoiceData';
import markInvoiceStageComplete from '@salesforce/apex/InvoiceController.markInvoiceStageComplete';
import initOrGetDocumentWithApplicantId from '@salesforce/apex/RepaymentMandateController.initOrGetDocumentWithApplicantId';
import linkContentDocument from '@salesforce/apex/RepaymentMandateController.linkContentDocument';
import getFileType from '@salesforce/apex/RepaymentMandateController.getFileType';
import deleteContentDocument from '@salesforce/apex/RepaymentMandateController.deleteContentDocument';

const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const INVOICE_DOCUMENT_TYPE = 'Invoice';
const INVOICE_TAB = 'Invoice';
const VIEW_ID_INVOICE_OPS = 'Wheels_Invoice_OPS';
const ACCEPTED_INVOICE_FORMATS = ['.pdf', '.jpg', '.jpeg', '.png'];

const YES_NO_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];

const ASSET_DETAIL_FIELDS = [
    { key: 'make', label: 'Make', type: 'text' },
    { key: 'model', label: 'Model', type: 'text' },
    { key: 'variant', label: 'Variant', type: 'text' },
    { key: 'dealerName', label: 'Dealer Name', type: 'text' }
];

const INVOICE_DETAIL_FIELDS = [
    { key: 'typeOfInvoice', label: 'Type of Invoice', type: 'picklist', picklistKey: 'typeOfInvoice' },
    { key: 'taxCollectedAtSource', label: 'Tax Collected at Source', type: 'number' },
    { key: 'taxInvoiceNo', label: 'Tax Invoice No', type: 'text' },
    { key: 'taxInvoiceDate', label: 'Tax Invoice Date', type: 'date' },
    { key: 'engineNo', label: 'Engine No', type: 'text' },
    { key: 'chassisNo', label: 'Chassis No', type: 'text' },
    { key: 'basicPrice', label: 'Basic Price', type: 'number' },
    { key: 'gstTotal', label: 'GST Total', type: 'number' },
    { key: 'gstType', label: 'GST Type', type: 'picklist', picklistKey: 'gstType' },
    { key: 'sgst', label: 'SGST', type: 'number' },
    { key: 'utgst', label: 'UTGST', type: 'number' },
    { key: 'igst', label: 'IGST', type: 'number' },
    { key: 'discountExShowroom', label: 'Discount on Ex-showroom price', type: 'number' },
    { key: 'exShowroomPrice', label: 'Ex-showroom price', type: 'number' },
    { key: 'rtoRoadTax', label: 'RTO/Road Tax', type: 'number' },
    { key: 'insurancePremium1Yr', label: '1 Year Insurance Premium', type: 'number' },
    { key: 'otherCharges', label: 'Other charges', type: 'number' },
    { key: 'orpAsPerBank', label: 'ORP as per bank', type: 'number' },
    { key: 'invoiceAmountInclDiscount', label: 'Invoice Amount as per ORP (incl discount)', type: 'number' }
];

const ALL_INVOICE_FIELDS = [...ASSET_DETAIL_FIELDS, ...INVOICE_DETAIL_FIELDS];

const OPERATIONS_FIELDS = [
    {
        key: 'isInvoiceLegible',
        label: 'Is Invoice legible?',
        type: 'picklist',
        picklistKey: 'isInvoiceLegible',
        required: true
    },
    {
        key: 'isAmountAsPerUploaded',
        label: 'Is Invoice amount entered above as per Invoice uploaded?',
        type: 'picklist',
        picklistKey: 'isAmountAsPerUploaded',
        required: true
    },
    {
        key: 'acceptUploadedInvoice',
        label: 'Do you accept uploaded invoice?',
        type: 'picklist',
        picklistKey: 'acceptUploadedInvoice',
        required: true
    },
    { key: 'invoiceRemarks', label: 'Remarks', type: 'text', required: true }
];

const OPERATIONS_REQUIRED_FIELD_LABELS = {
    isInvoiceLegible: 'Is Invoice legible?',
    isAmountAsPerUploaded: 'Is Invoice amount entered above as per Invoice uploaded?',
    acceptUploadedInvoice: 'Do you accept uploaded invoice?',
    invoiceRemarks: 'Remarks'
};

const OPERATIONS_SECTION_KEYS = new Set(['isInvoiceLegible', 'invoiceRemarks']);
const OPERATIONS_FIELD_KEYS = new Set(OPERATIONS_FIELDS.map((f) => f.key));
const ORP_INPUT_KEYS = ['exShowroomPrice', 'rtoRoadTax', 'insurancePremium1Yr', 'otherCharges'];
const CALCULATED_READONLY_KEYS = new Set(['gstTotal', 'orpAsPerBank']);

function parseNum(values, key) {
    const raw = values?.[key];
    if (raw == null || String(raw).trim() === '') return 0;
    const num = Number.parseFloat(String(raw).replace(/,/g, ''));
    return Number.isFinite(num) ? num : 0;
}

function computeOrpAsPerBank(values) {
    if (!ORP_INPUT_KEYS.some((k) => String(values?.[k] ?? '').trim() !== '')) return '';
    return String(
        ORP_INPUT_KEYS.reduce((sum, k) => sum + parseNum(values, k), 0)
    );
}

function formatDateOnly(raw) {
    if (raw == null || String(raw).trim() === '') return '';
    const datePart = String(raw).trim().split(/[T\s]/)[0];
    return /^\d{4}-\d{2}-\d{2}$/.test(datePart) ? datePart : String(raw).trim();
}

function computeDerivedInvoiceDetails(details, { syncInvoiceAmountFromOrp = false } = {}) {
    const next = { ...(details || {}) };
    next.orpAsPerBank = computeOrpAsPerBank(next);
    if (syncInvoiceAmountFromOrp) {
        next.invoiceAmountInclDiscount = next.orpAsPerBank || '';
    }
    return next;
}

function isSuccessFlag(value) {
    return value === true || value === 'true';
}

function extractError(error) {
    if (!error) return '';
    const body = error.body;
    if (typeof body === 'string') return body;
    if (body?.message) return body.message;
    if (Array.isArray(body) && body[0]?.message) return body[0].message;
    return error.message || '';
}

function hasFieldValue(value) {
    return value != null && String(value).trim().length > 0;
}

export default class Invoice extends LightningElement {
    isLoading = true;
    isSaving = false;
    isSaved = false;
    lastSavedPayloadJson = '';

    @track invoiceSection = {};
    @track invoiceDetails = {};
    picklistOptions = {};
    readOnlyFieldKeys = new Set();

    primaryApplicantId = '';
    documentUploadRecordId = '';
    invoiceDocumentUploaded = false;
    invoiceContentDocumentId = '';
    invoiceFileName = '';
    invoiceFileType = 'PDF';
    openPreviewModal = false;
    acceptedInvoiceFormats = ACCEPTED_INVOICE_FORMATS;

    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api fromAssetList = false;

    _applicationLineItemId = '';

    @api
    get applicationLineItemId() {
        return this._applicationLineItemId;
    }
    set applicationLineItemId(value) {
        this._applicationLineItemId = value || '';
        if (!this.fromAssetList) {
            this._tryLoadData();
        }
    }

    _assetId = '';

    @api
    get assetId() {
        return this._assetId;
    }
    set assetId(value) {
        this._assetId = value || '';
        this._tryLoadData();
    }

    _apiApplicantId = '';
    _menuNavContext = {};
    _menuSelectHandler;
    _isStagePast = false;
    _recordId;

    @api
    get applicantId() {
        return this._apiApplicantId;
    }
    set applicantId(value) {
        this._apiApplicantId = value || '';
        if (this._recordId) this._tryLoadData();
    }

    @api
    get isStagePast() {
        return this._isStagePast;
    }
    set isStagePast(value) {
        this._isStagePast = typeof value === 'string' ? value.toLowerCase() === 'true' : !!value;
    }

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) this._tryLoadData();
    }

    _tryLoadData() {
        if (!this._recordId) {
            return;
        }
        if (this.fromAssetList && !this._assetId) {
            return;
        }
        void this.loadData();
    }

    get isOperationsInvoiceOpsMode() {
        return this.tab === INVOICE_TAB && this.currentViewId === VIEW_ID_INVOICE_OPS;
    }

    get isInvoiceSectionsReadOnly() {
        return this._isStagePast || this.isOperationsInvoiceOpsMode;
    }

    get isOperationsSectionReadOnly() {
        return this._isStagePast || !this.isOperationsInvoiceOpsMode;
    }

    get effectiveApplicantId() {
        return (this._apiApplicantId || this._menuNavContext.applicantId || '').trim();
    }

    get isDirty() {
        return this.getPayloadJson() !== this.lastSavedPayloadJson;
    }

    get _operationsFieldValues() {
        return { ...this.invoiceSection, ...this.invoiceDetails };
    }

    get allOperationsFieldsFilled() {
        return OPERATIONS_FIELDS.filter((field) => field.required).every((field) => {
            const value = this._operationsFieldValues[field.key];
            return hasFieldValue(value);
        });
    }

    get allInvoiceFieldsFilled() {
        const values = this.invoiceDetails || {};
        return ALL_INVOICE_FIELDS
            .filter((field) => !this.isFieldReadOnly(field.key))
            .every((field) => hasFieldValue(values[field.key]));
    }

    get allRequiredDataFilled() {
        return this.invoiceDocumentUploaded && this.allInvoiceFieldsFilled;
    }

    get showInvoiceDocumentActions() {
        return !this.isInvoiceSectionsReadOnly;
    }

    get isInvoiceUploadDisabled() {
        return this.isInvoiceSectionsReadOnly || this.isLoading || !this.documentUploadRecordId;
    }

    get invoiceDisplayFileName() {
        return this.invoiceFileName || INVOICE_DOCUMENT_TYPE;
    }

    get isNextDisabled() {
        if (this.isLoading || this.isSaving) {
            return true;
        }
        if (this._isStagePast) {
            return false;
        }
        if (this.isOperationsInvoiceOpsMode) {
            return !this.allOperationsFieldsFilled;
        }
        // Require invoice upload + every editable field filled before Next can enable.
        if (!this.invoiceDocumentUploaded || !this.allInvoiceFieldsFilled) {
            return true;
        }
        // Already saved with no edits — allow navigation.
        if (this.isSaved && !this.isDirty) {
            return false;
        }
        // First-time entry: user must change at least one field (via oninput/onchange).
        return !this.isDirty;
    }

    get nextButtonClass() {
        return `p4-primary-btn p4-button-text${this.isNextDisabled ? ' stage-next-btn--disabled' : ''}`;
    }

    get assetDetailFieldRows() {
        return this.buildFieldRows(ASSET_DETAIL_FIELDS, this.invoiceDetails, this.isInvoiceSectionsReadOnly);
    }

    get invoiceDetailFieldRows() {
        return this.buildFieldRows(INVOICE_DETAIL_FIELDS, this.invoiceDetails, this.isInvoiceSectionsReadOnly);
    }

    get operationsFieldRows() {
        const values = { ...this.invoiceSection, ...this.invoiceDetails };
        return this.buildFieldRows(OPERATIONS_FIELDS, values, this.isOperationsSectionReadOnly);
    }

    connectedCallback() {
        this._menuSelectHandler = this.handleMenuSelectForNav.bind(this);
        window.addEventListener('losmenuselect', this._menuSelectHandler);
        if (this._recordId) this._tryLoadData();
    }

    disconnectedCallback() {
        window.removeEventListener('losmenuselect', this._menuSelectHandler);
    }

    handleMenuSelectForNav(event) {
        const detail = event?.detail || {};
        if (detail.overrideLwc && detail.overrideLwc !== 'invoice') return;
        this._menuNavContext = { applicantId: detail.applicantId || '' };
        if (detail.applicantId) this._apiApplicantId = detail.applicantId;
        if (detail.isStagePast != null) this._isStagePast = detail.isStagePast === true;
        if (this._recordId) this._tryLoadData();
    }

    async loadData() {
        if (!this.recordId) {
            this.isLoading = false;
            return;
        }

        const requestedAssetId = this._assetId;
        this.isLoading = true;

        try {
            const data = await getInvoiceData({
                recordId: this.recordId,
                applicantId: this.effectiveApplicantId || null,
                assetId: requestedAssetId || null
            });

            if (requestedAssetId !== this._assetId) {
                return;
            }

            if (!data || !isSuccessFlag(data.isSuccess)) {
                this.showToast('Error', data?.message || 'Unable to load invoice data.', 'error');
                return;
            }

            this.invoiceSection = { ...(data.invoiceSection || {}) };
            this.invoiceDetails = { ...(data.invoiceDetails || {}) };
            this.readOnlyFieldKeys = new Set(data.readOnlyFieldKeys || []);
            this.picklistOptions = { ...(data.picklists || {}) };

            const meta = data.meta || {};
            this.primaryApplicantId = meta.primaryApplicantId || this.effectiveApplicantId || '';
            this.invoiceDocumentUploaded = meta.invoiceDocumentUploaded === true;
            this.documentUploadRecordId = meta.documentChecklistId || '';
            this.invoiceContentDocumentId = meta.invoiceContentDocumentId || '';
            this.invoiceFileName = meta.invoiceFileName || '';
            this.invoiceFileType = meta.invoiceFileType || 'PDF';

            const hasSavedAmount = String(this.invoiceDetails?.invoiceAmountInclDiscount ?? '').trim() !== '';
            this.invoiceDetails = computeDerivedInvoiceDetails(this.invoiceDetails, {
                syncInvoiceAmountFromOrp: !hasSavedAmount
            });

            this.isSaved = meta.hasSavedInvoiceDetails === true;
            this.lastSavedPayloadJson = this.isSaved ? this.getPayloadJson() : '';

            await this.ensureDocumentChecklistId();
        } catch (error) {
            if (requestedAssetId === this._assetId) {
                this.showToast('Error', extractError(error) || 'Unable to load invoice data.', 'error');
            }
        } finally {
            if (requestedAssetId === this._assetId) {
                if (!this.documentUploadRecordId && !this.isInvoiceSectionsReadOnly) {
                    await this.ensureDocumentChecklistId();
                }
                this.isLoading = false;
            }
        }
    }

    getPayloadJson() {
        return JSON.stringify({
            invoiceSection: this.invoiceSection,
            invoiceDetails: this.invoiceDetails
        });
    }

    handleFieldChange(event) {
        if (this._isStagePast) return;
        const key = event.currentTarget?.dataset?.key;
        if (!key) return;
        const value = event.detail?.value ?? event.currentTarget?.value ?? '';
        this.applyEditableFieldValue(key, value);
    }

    handleFieldInput(event) {
        if (this._isStagePast) return;
        const key = event.currentTarget?.dataset?.key;
        if (!key) return;
        const value = event.target?.value ?? event.currentTarget?.value ?? '';
        this.applyEditableFieldValue(key, value);
    }

    applyEditableFieldValue(key, value) {
        this.applyFieldValue(key, value, { recomputeOrp: true });
    }

    applyFieldValue(key, value, { recomputeOrp = false } = {}) {
        if (OPERATIONS_FIELD_KEYS.has(key)) {
            if (this.isOperationsSectionReadOnly) return;
            if (OPERATIONS_SECTION_KEYS.has(key)) {
                this.invoiceSection = { ...this.invoiceSection, [key]: value };
            } else {
                this.invoiceDetails = { ...this.invoiceDetails, [key]: value };
            }
            return;
        }
        if (this.isInvoiceSectionsReadOnly || this.isFieldReadOnly(key)) return;
        this.invoiceDetails = computeDerivedInvoiceDetails(
            { ...this.invoiceDetails, [key]: value },
            { syncInvoiceAmountFromOrp: recomputeOrp && key !== 'invoiceAmountInclDiscount' }
        );
    }

    buildFieldRows(definitions, values, forceReadOnly) {
        return definitions.map((def) => {
            const raw = values?.[def.key] ?? '';
            const value = def.type === 'date' ? formatDateOnly(raw) : raw;
            const displayValue =
                def.type === 'date' ? formatDateOnly(value) || '-' : String(value ?? '').trim() || '-';
            const showAsReadOnly = forceReadOnly || this._isStagePast || this.isFieldReadOnly(def.key);
            const isOperationsField = OPERATIONS_FIELD_KEYS.has(def.key);
            return {
                ...def,
                value,
                displayValue,
                options: this.resolveOptions(def.picklistKey),
                isPicklist: def.type === 'picklist',
                isNumber: def.type === 'number',
                isDate: def.type === 'date',
                isRequired: isOperationsField ? def.required === true : !showAsReadOnly,
                showAsReadOnly,
                wrapClass: def.fullSpan ? 'lt-field-wrap lt-field-wrap-full' : 'lt-field-wrap'
            };
        });
    }

    resolveOptions(picklistKey) {
        const fromServer = picklistKey ? this.picklistOptions?.[picklistKey] : null;
        if (Array.isArray(fromServer) && fromServer.length) return fromServer;
        if (picklistKey === 'typeOfInvoice' || picklistKey === 'gstType') return [];
        return picklistKey ? YES_NO_OPTIONS : [];
    }

    isFieldReadOnly(key) {
        return CALCULATED_READONLY_KEYS.has(key) || this.readOnlyFieldKeys.has(key);
    }

    async ensureDocumentChecklistId() {
        if (this.isInvoiceSectionsReadOnly) {
            return;
        }
        const applicantId = this.effectiveApplicantId || this.primaryApplicantId;
        if (!this.recordId || !applicantId) {
            return;
        }
        const requestedAssetId = this._assetId;
        try {
            const docId = await initOrGetDocumentWithApplicantId({
                applicationId: this.recordId,
                documentType: INVOICE_DOCUMENT_TYPE,
                applicantId,
                applicationLineItemId: this._applicationLineItemId || null,
                assetId: requestedAssetId || null
            });
            if (requestedAssetId !== this._assetId) {
                return;
            }
            this.documentUploadRecordId = docId || '';
        } catch (error) {
            this.showToast('Error', extractError(error) || 'Unable to initialize invoice upload.', 'error');
        }
    }

    async handleInvoiceUploadFinished(event) {
        if (this.isInvoiceSectionsReadOnly) {
            return;
        }
        const files = event.detail?.files || [];
        if (!files.length) {
            return;
        }

        const file = files[0];
        const contentDocumentId = file.documentId || '';
        if (!contentDocumentId) {
            this.showToast('Error', 'Uploaded file reference is missing.', 'error');
            return;
        }

        const applicantId = this.primaryApplicantId || this.effectiveApplicantId;
        this.isLoading = true;
        try {
            await linkContentDocument({
                documentDataJson: JSON.stringify({
                    documentType: INVOICE_DOCUMENT_TYPE,
                    applicationId: this.recordId,
                    applicantId,
                    applicationLineItemId: this._applicationLineItemId || null,
                    assetId: this._assetId || null,
                    contentDocumentId
                })
            });
            const uploadedFileType = await getFileType({ contentDocumentId });
            this.invoiceDocumentUploaded = true;
            this.invoiceContentDocumentId = contentDocumentId;
            this.invoiceFileName = file.name || INVOICE_DOCUMENT_TYPE;
            this.invoiceFileType = uploadedFileType || 'PDF';
            this.showToast('Success', 'Invoice uploaded successfully.', 'success');
        } catch (error) {
            this.showToast('Error', extractError(error) || 'Failed to save uploaded invoice.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleInvoicePreview() {
        if (!this.invoiceContentDocumentId) {
            return;
        }
        this.openPreviewModal = true;
    }

    handlePreviewClose() {
        this.openPreviewModal = false;
    }

    async handleInvoiceDelete() {
        if (
            this.isInvoiceSectionsReadOnly ||
            !this.invoiceDocumentUploaded ||
            !this.invoiceContentDocumentId
        ) {
            return;
        }

        this.isLoading = true;
        try {
            await deleteContentDocument({
                contentDocumentId: this.invoiceContentDocumentId
            });
            this.invoiceDocumentUploaded = false;
            this.invoiceContentDocumentId = '';
            this.invoiceFileName = '';
            this.invoiceFileType = 'PDF';
            this.showToast('Success', 'Invoice removed successfully.', 'success');
        } catch (error) {
            this.showToast('Error', extractError(error) || 'Failed to remove invoice.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async saveInvoiceToBackend() {
        this.isSaving = true;
        window.dispatchEvent(
            new CustomEvent('losgloballoader', { detail: { show: true, message: 'Saving Invoice...' } })
        );
        try {
            const response = await saveInvoiceData({
                recordId: this.recordId,
                applicantId: this.effectiveApplicantId || null,
                payloadJson: this.getPayloadJson(),
                assetId: this._assetId || null
            });
            if (isSuccessFlag(response?.isSuccess)) {
                this.isSaved = true;
                this.lastSavedPayloadJson = this.getPayloadJson();
                return { success: true, message: response.message || 'Invoice saved successfully.' };
            }
            return { success: false, message: response?.message || 'Unable to save invoice.' };
        } catch (error) {
            return { success: false, message: extractError(error) || 'Error while saving invoice.' };
        } finally {
            this.isSaving = false;
            window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
        }
    }

    getMissingOperationsFieldLabels() {
        return OPERATIONS_FIELDS
            .filter((field) => {
                if (!field.required) return false;
                const value = this._operationsFieldValues[field.key];
                return !hasFieldValue(value);
            })
            .map((field) => OPERATIONS_REQUIRED_FIELD_LABELS[field.key] || field.label);
    }

    getMissingInvoiceFieldLabels() {
        const values = this.invoiceDetails || {};
        const missing = [];
        if (!this.invoiceDocumentUploaded) {
            missing.push('Invoice document');
        }
        ALL_INVOICE_FIELDS.forEach((field) => {
            if (this.isFieldReadOnly(field.key)) {
                return;
            }
            if (!hasFieldValue(values[field.key])) {
                missing.push(field.label);
            }
        });
        return missing;
    }

    validateRequiredInvoiceData() {
        const missing = this.getMissingInvoiceFieldLabels();
        if (!missing.length) {
            return { valid: true, message: '' };
        }
        const message = missing.length === 1
            ? `Please complete the required field: ${missing[0]}.`
            : `Please complete all required fields: ${missing.join(', ')}.`;
        return { valid: false, message };
    }

    validateOperationsRequiredFields() {
        const missing = this.getMissingOperationsFieldLabels();
        if (!missing.length) {
            return { valid: true, message: '' };
        }
        const message = missing.length === 1
            ? `Please complete the required field: ${missing[0]}.`
            : `Please complete all required fields: ${missing.join(', ')}.`;
        return { valid: false, message };
    }

    async handleNextButton() {
        if (this.isNextDisabled || !this.recordId) return;
        if (this._isStagePast) {
            if (this.fromAssetList) {
                this.returnToAssetList(false);
                return;
            }
            this.dispatchNextStage();
            return;
        }
        if (this.isOperationsInvoiceOpsMode) {
            const opsValidation = this.validateOperationsRequiredFields();
            if (!opsValidation.valid) {
                this.showToast('Required fields', opsValidation.message, 'error');
                return;
            }
            const result = await this.saveInvoiceToBackend();
            if (!result.success) {
                this.showToast('Error', result.message, 'error');
                return;
            }
            this.showToast('Success', result.message, 'success');
            await this._completeInvoiceNavigation();
            return;
        }
        const invoiceValidation = this.validateRequiredInvoiceData();
        if (!invoiceValidation.valid) {
            this.showToast('Required fields', invoiceValidation.message, 'error');
            return;
        }
        if (!this.isDirty && this.isSaved) {
            await this._completeInvoiceNavigation();
            return;
        }
        const result = await this.saveInvoiceToBackend();
        if (result.success) {
            this.showToast('Success', result.message, 'success');
            await this._completeInvoiceNavigation();
        } else {
            this.showToast('Error', result.message, 'error');
        }
    }

    async _completeInvoiceNavigation() {
        if (this.fromAssetList) {
            await this._completeAssetListInvoice();
            return;
        }
        this.dispatchNextStage();
    }

    async _completeAssetListInvoice() {
        if (!this._applicationLineItemId) {
            this.showToast('Error', 'Application line item is missing. Please go back and reopen the asset.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const result = await markInvoiceStageComplete({
                applicationLineItemId: this._applicationLineItemId,
                currentViewId: this.currentViewId || null,
                assetId: this._assetId || null
            });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.message || 'Unable to complete invoice for this asset.', 'error');
                return;
            }
            this.returnToAssetList(true);
        } catch (error) {
            this.showToast('Error', extractError(error) || 'Unable to complete invoice for this asset.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    returnToAssetList(saved) {
        this.dispatchEvent(
            new CustomEvent('detailcomplete', {
                detail: {
                    lineItemId: this._applicationLineItemId || null,
                    saved
                },
                bubbles: true,
                composed: true
            })
        );
    }

    dispatchNextStage() {
        if (!this.currentViewId) {
            this.showToast('Navigation', 'Current view ID is missing. Please refresh and try again.', 'error');
            return;
        }
        const phrase = (this.stagePhrase || this.currentViewId || '').trim();
        window.dispatchEvent(
            new CustomEvent(LOS_NEXT_STAGE_EVENT, {
                detail: {
                    currentViewId: this.currentViewId,
                    currentStagePhrase: phrase,
                    currentLoanStageComplete: this.tab || INVOICE_TAB
                },
                bubbles: true,
                composed: true
            })
        );
    }

    showToast(title, message, variant = 'error') {
        window.dispatchEvent(
            new CustomEvent('showtoast', {
                detail: { title, message, variant },
                bubbles: true,
                composed: true
            })
        );
    }
}