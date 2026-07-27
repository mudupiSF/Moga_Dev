/**
 * Vehicle Inspection stage — inspection fields persisted on Asset__c.
 */
import { LightningElement, api, track } from 'lwc';
import getVehicleInspectionData from '@salesforce/apex/ValuationController.getVehicleInspectionData';
import saveVehicleInspectionData from '@salesforce/apex/ValuationController.saveVehicleInspectionData';
import initOrGetDocumentWithApplicantId from '@salesforce/apex/RepaymentMandateController.initOrGetDocumentWithApplicantId';
import linkContentDocument from '@salesforce/apex/RepaymentMandateController.linkContentDocument';
import getFileType from '@salesforce/apex/RepaymentMandateController.getFileType';
import deleteContentDocument from '@salesforce/apex/RepaymentMandateController.deleteContentDocument';

const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const VEHICLE_INSPECTION_DOCUMENT_TYPE = 'Vehicle Inspection';
const VEHICLE_INSPECTION_TAB = 'Vehicle Inspection';
const VIEW_ID_VEHICLE_INSPECTION_OPS = 'Wheels_Vehicle_Inspection_OPS';
const ACCEPTED_VEHICLE_IMAGE_FORMATS = ['.jpg', '.jpeg', '.png'];

const DEFAULT_VEHICLE_INSPECTION = {
    engineNumber: '',
    engineNumberCapturedInitially: '',
    chassisNumber: '',
    chassisNumberCapturedInitially: '',
    vehicleRegistrationNumber: '',
    vehicleRegistrationNumberCapturedInitially: '',
    locationOfVehicleInspection: ''
};

const INSPECTION_FIELD_KEYS = Object.keys(DEFAULT_VEHICLE_INSPECTION);

const OPERATIONS_FIELDS = [
    { key: 'remarks', label: 'Remarks', type: 'text', required: true },
    {
        key: 'vehicleInspectionApprovedByCvo',
        label: 'Vehicle inspection approved by CVO',
        type: 'picklist',
        picklistKey: 'vehicleInspectionApprovedByCvo',
        required: true
    },
    { key: 'cvoRemarks', label: 'CVO remarks', type: 'text', required: true }
];

const OPERATIONS_REQUIRED_FIELD_LABELS = {
    remarks: 'Remarks',
    vehicleInspectionApprovedByCvo: 'Vehicle inspection approved by CVO',
    cvoRemarks: 'CVO remarks'
};

const YES_NO_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];

const OPERATIONS_FIELD_KEYS = new Set(OPERATIONS_FIELDS.map((field) => field.key));

/** Populated on Asset__c before inspection; displayed read-only on this screen. */
const ASSET_SOURCED_INSPECTION_FIELDS = new Set([
    'engineNumber',
    'chassisNumber',
    'vehicleRegistrationNumber'
]);

const REQUIRED_FIELD_LABELS = {
    engineNumber: 'Engine number',
    engineNumberCapturedInitially: 'Engine number captured Initially',
    chassisNumber: 'Chassis number',
    chassisNumberCapturedInitially: 'Chassis number captured Initially',
    vehicleRegistrationNumber: 'Vehicle registration number',
    vehicleRegistrationNumberCapturedInitially: 'Vehicle registration Number Captured Initially',
    locationOfVehicleInspection: 'Location of Vehicle Inspection'
};

function toStr(value) {
    return value === null || value === undefined ? '' : String(value);
}

function normalizeOptions(options) {
    return (options || [])
        .map((o) => ({
            label: toStr(o?.label ?? o?.value).trim(),
            value: toStr(o?.value ?? o?.label).trim()
        }))
        .filter((o) => o.value);
}

function normalizeLoadedSection(section) {
    if (!section || typeof section !== 'object' || Array.isArray(section)) {
        return {};
    }
    const out = {};
    for (const key of INSPECTION_FIELD_KEYS) {
        const val = section[key];
        out[key] = val == null ? '' : String(val);
    }
    return out;
}

export default class VehicleInspection extends LightningElement {
    @api recordId;
    @api assetId;
    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api applicantId;

    isLoading = true;
    documentUploadRecordId = '';
    assetImageDocumentUploaded = false;
    assetImageContentDocumentId = '';
    assetImageFileName = '';
    assetImageFileType = 'PNG';
    openPreviewModal = false;
    acceptedVehicleImageFormats = ACCEPTED_VEHICLE_IMAGE_FORMATS;

    @track locationOptions = [];
    @track fieldValues = { ...DEFAULT_VEHICLE_INSPECTION };
    @track operationsSection = {};
    @track operationsPicklistOptions = {};

    lastSavedPayloadJson = '';

    _resolvedAssetId = '';
    _resolvedApplicantId = '';
    _isStagePast = false;

    @api
    get isStagePast() {
        return this._isStagePast;
    }
    set isStagePast(value) {
        if (typeof value === 'string') {
            this._isStagePast = value.toLowerCase() === 'true';
            return;
        }
        this._isStagePast = !!value;
    }

    connectedCallback() {
        this._loadPageData();
    }

    get isOperationsVehicleInspectionOpsMode() {
        return this.tab === VEHICLE_INSPECTION_TAB && this.currentViewId === VIEW_ID_VEHICLE_INSPECTION_OPS;
    }

    get isInspectionSectionsReadOnly() {
        return this._isStagePast || this.isOperationsVehicleInspectionOpsMode;
    }

    get isEditable() {
        return !this.isInspectionSectionsReadOnly;
    }

    get isOperationsSectionReadOnly() {
        return this._isStagePast || !this.isOperationsVehicleInspectionOpsMode;
    }

    get operationsFieldRows() {
        return this._buildFieldRows(OPERATIONS_FIELDS, this.operationsSection, this.isOperationsSectionReadOnly);
    }

    get effectiveAssetId() {
        return toStr(this.assetId).trim() || toStr(this._resolvedAssetId).trim();
    }

    get effectiveApplicantId() {
        return toStr(this.applicantId).trim() || toStr(this._resolvedApplicantId).trim();
    }

    get allRequiredFieldsFilled() {
        return (
            this.assetImageDocumentUploaded &&
            INSPECTION_FIELD_KEYS.every((key) => toStr(this.fieldValues[key]).trim().length > 0)
        );
    }

    get showAssetImageDocumentActions() {
        return this.isEditable;
    }

    get isAssetImageUploadDisabled() {
        return !this.isEditable || !this.documentUploadRecordId || this.isLoading;
    }

    get assetImageDisplayFileName() {
        return this.assetImageFileName || 'Vehicle Image';
    }

    get allOperationsFieldsFilled() {
        return [...OPERATIONS_FIELD_KEYS].every(
            (key) => toStr(this.operationsSection[key]).trim().length > 0
        );
    }

    get isNextDisabled() {
        if (this.isLoading) {
            return true;
        }
        if (this.isOperationsVehicleInspectionOpsMode && !this._isStagePast) {
            return !this.allOperationsFieldsFilled;
        }
        if (this._isStagePast) {
            return false;
        }
        return !this.allRequiredFieldsFilled;
    }

    get nextButtonClass() {
        return `p4-primary-btn p4-button-text${this.isNextDisabled ? ' stage-next-btn--disabled' : ''}`;
    }

    async _loadPageData() {
        if (!this.recordId && !this.assetId && !this.applicantId) {
            this.resetState();
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        try {
            const data = await getVehicleInspectionData({
                applicationId: this.recordId,
                assetId: this.assetId,
                applicantId: this.applicantId
            });

            this._resolvedAssetId = data?.resolvedAssetId ? String(data.resolvedAssetId) : '';
            this._resolvedApplicantId = data?.resolvedApplicantId
                ? String(data.resolvedApplicantId)
                : '';

            this.locationOptions = normalizeOptions(data?.picklists?.locationOfVehicleInspection);
            this.fieldValues = {
                ...DEFAULT_VEHICLE_INSPECTION,
                ...normalizeLoadedSection(data?.vehicleInspection)
            };
            this.assetImageDocumentUploaded = data?.vehicleInspectionImageUploaded === true;
            this.documentUploadRecordId = data?.documentChecklistId || '';
            this.assetImageContentDocumentId = data?.vehicleImageContentDocumentId || '';
            this.assetImageFileName = data?.vehicleImageFileName || '';
            this.assetImageFileType = data?.vehicleImageFileType || 'PNG';
            this.operationsSection = this._normalizeLoadedSection(
                data?.operationsSection,
                OPERATIONS_FIELD_KEYS
            );
            this.operationsPicklistOptions = data?.operationsPicklists || {};
            this.lastSavedPayloadJson = this.getSavePayloadJson();

            await this.ensureDocumentChecklistId();
        } catch (error) {
            console.error('Error loading vehicle inspection:', error);
            this.resetState();
            this._toast('Error', 'Unable to load vehicle inspection details.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    resetState() {
        this._resolvedAssetId = '';
        this._resolvedApplicantId = '';
        this.locationOptions = [];
        this.fieldValues = { ...DEFAULT_VEHICLE_INSPECTION };
        this.operationsSection = {};
        this.operationsPicklistOptions = {};
        this.lastSavedPayloadJson = '';
        this.assetImageDocumentUploaded = false;
        this.documentUploadRecordId = '';
        this.assetImageContentDocumentId = '';
        this.assetImageFileName = '';
        this.assetImageFileType = 'PNG';
    }

    _normalizeLoadedSection(section, keys) {
        const out = {};
        for (const key of keys) {
            const val = section?.[key];
            out[key] = val == null ? '' : String(val);
        }
        return out;
    }

    _buildFieldRows(definitions, values, forceReadOnly) {
        return definitions.map((def) => {
            const raw = values?.[def.key] ?? '';
            const value = String(raw ?? '');
            const displayValue = value.trim() || '-';
            return {
                ...def,
                value,
                displayValue,
                options: this._resolveOperationsOptions(def.picklistKey),
                isPicklist: def.type === 'picklist',
                isRequired: def.required === true,
                showAsReadOnly: forceReadOnly || this._isStagePast,
                wrapClass: def.fullSpan ? 'bmp-field-wrap bmp-field-wrap-full' : 'bmp-field-wrap'
            };
        });
    }

    _resolveOperationsOptions(picklistKey) {
        const fromServer = picklistKey ? this.operationsPicklistOptions?.[picklistKey] : null;
        if (Array.isArray(fromServer) && fromServer.length) {
            return normalizeOptions(fromServer);
        }
        return picklistKey ? YES_NO_OPTIONS : [];
    }

    async ensureDocumentChecklistId() {
        if (!this.isEditable || this.documentUploadRecordId) {
            return;
        }
        if (!this.recordId || !this.effectiveApplicantId) {
            return;
        }
        try {
            const docId = await initOrGetDocumentWithApplicantId({
                applicationId: this.recordId,
                documentType: VEHICLE_INSPECTION_DOCUMENT_TYPE,
                applicantId: this.effectiveApplicantId
            });
            this.documentUploadRecordId = docId || '';
        } catch (error) {
            this._toast('Error', this.extractError(error) || 'Unable to initialize vehicle image upload.', 'error');
        }
    }

    async handleAssetImageUploadFinished(event) {
        if (!this.isEditable) {
            return;
        }
        const files = event.detail?.files || [];
        if (!files.length) {
            return;
        }

        const file = files[0];
        const contentDocumentId = file.documentId || '';
        if (!contentDocumentId) {
            this._toast('Error', 'Uploaded file reference is missing.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            await linkContentDocument({
                documentDataJson: JSON.stringify({
                    documentType: VEHICLE_INSPECTION_DOCUMENT_TYPE,
                    applicationId: this.recordId,
                    applicantId: this.effectiveApplicantId,
                    contentDocumentId
                })
            });
            const uploadedFileType = await getFileType({ contentDocumentId });
            this.assetImageDocumentUploaded = true;
            this.assetImageContentDocumentId = contentDocumentId;
            this.assetImageFileName = file.name || 'Vehicle Image';
            this.assetImageFileType = uploadedFileType || 'PNG';
            this._toast('Success', 'Vehicle image uploaded successfully.', 'success');
        } catch (error) {
            this._toast('Error', this.extractError(error) || 'Failed to save uploaded vehicle image.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleAssetImagePreview() {
        if (!this.assetImageContentDocumentId) {
            return;
        }
        this.openPreviewModal = true;
    }

    handlePreviewClose() {
        this.openPreviewModal = false;
    }

    async handleAssetImageDelete() {
        if (
            !this.isEditable ||
            !this.assetImageDocumentUploaded ||
            !this.assetImageContentDocumentId
        ) {
            return;
        }

        this.isLoading = true;
        try {
            await deleteContentDocument({
                contentDocumentId: this.assetImageContentDocumentId
            });
            this.assetImageDocumentUploaded = false;
            this.assetImageContentDocumentId = '';
            this.assetImageFileName = '';
            this.assetImageFileType = 'PNG';
            this._toast('Success', 'Vehicle image removed successfully.', 'success');
        } catch (error) {
            this._toast('Error', this.extractError(error) || 'Failed to remove vehicle image.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    extractError(error) {
        return error?.body?.message || error?.message || '';
    }

    isAssetSourcedField(fieldKey) {
        return ASSET_SOURCED_INSPECTION_FIELDS.has(fieldKey);
    }

    handleFieldChange(event) {
        const field = event.currentTarget?.dataset?.field;
        if (!this.isEditable || !field || this.isAssetSourcedField(field)) {
            return;
        }
        const value = toStr(event.detail?.value ?? event.target?.value ?? '');
        this.fieldValues = { ...this.fieldValues, [field]: value };
    }

    handleComboboxChange(event) {
        const field = event.currentTarget?.dataset?.field;
        if (!this.isEditable || !field) {
            return;
        }
        const value = event.detail?.value ?? event.target?.value ?? '';
        this.fieldValues = { ...this.fieldValues, [field]: toStr(value) };
    }

    handleOperationsFieldChange(event) {
        if (this.isOperationsSectionReadOnly) {
            return;
        }
        const key = event.currentTarget?.dataset?.key;
        if (!key || !OPERATIONS_FIELD_KEYS.has(key)) {
            return;
        }
        const value = toStr(event.detail?.value ?? event.target?.value ?? '');
        this.operationsSection = { ...this.operationsSection, [key]: value };
    }

    getSavePayloadJson({ operationsOnly = false } = {}) {
        const payload = {
            operationsSection: { ...this.operationsSection }
        };
        if (!operationsOnly) {
            const vehicleInspection = {};
            for (const key of INSPECTION_FIELD_KEYS) {
                vehicleInspection[key] = this.fieldValues[key];
            }
            payload.vehicleInspection = vehicleInspection;
        }
        return JSON.stringify(payload);
    }

    getMissingRequiredFieldLabels() {
        const missing = [];
        if (!this.assetImageDocumentUploaded) {
            missing.push('Vehicle image');
        }
        INSPECTION_FIELD_KEYS
            .filter((key) => !toStr(this.fieldValues[key]).trim())
            .forEach((key) => missing.push(REQUIRED_FIELD_LABELS[key] || key));
        return missing;
    }

    validateRequiredFields() {
        const missing = this.getMissingRequiredFieldLabels();
        if (!missing.length) {
            return { valid: true, message: '' };
        }
        const message = missing.length === 1
            ? `Please complete the required field: ${missing[0]}.`
            : `Please complete all required fields: ${missing.join(', ')}.`;
        return { valid: false, message };
    }

    getMissingOperationsFieldLabels() {
        return OPERATIONS_FIELDS
            .filter((field) => field.required && !toStr(this.operationsSection[field.key]).trim())
            .map((field) => OPERATIONS_REQUIRED_FIELD_LABELS[field.key] || field.label);
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
        if (!this.recordId && !this.effectiveAssetId && !this.applicantId) {
            return;
        }
        if (this.isNextDisabled || this.isLoading) {
            return;
        }
        if (this._isStagePast) {
            this.emitLosNextStage();
            return;
        }
        if (this.isOperationsVehicleInspectionOpsMode) {
            const opsValidation = this.validateOperationsRequiredFields();
            if (!opsValidation.valid) {
                this._toast('Required fields', opsValidation.message, 'error');
                return;
            }
            await this._saveOperationsAndNavigate();
            return;
        }

        const validation = this.validateRequiredFields();
        if (!validation.valid) {
            this._toast('Required fields', validation.message, 'error');
            return;
        }

        const saveParams = {
            applicationId: this.recordId,
            assetId: this.effectiveAssetId,
            applicantId: this.effectiveApplicantId,
            payloadJson: this.getSavePayloadJson()
        };

        window.dispatchEvent(
            new CustomEvent('losgloballoader', { detail: { show: true, message: 'Saving...' } })
        );
        this.isLoading = true;
        try {
            const response = await saveVehicleInspectionData(saveParams);
            if (response?.isSuccess) {
                if (response?.resolvedAssetId) {
                    this._resolvedAssetId = String(response.resolvedAssetId);
                }
                if (response?.resolvedApplicantId) {
                    this._resolvedApplicantId = String(response.resolvedApplicantId);
                }
                if (response?.message) {
                    this._toast('Saved', response.message, 'success');
                }
                this.lastSavedPayloadJson = this.getSavePayloadJson();
                this.emitLosNextStage();
            } else {
                this._toast(
                    'Error',
                    response?.message || 'Unable to save vehicle inspection.',
                    'error'
                );
            }
        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Error while saving.';
            this._toast('Error', msg, 'error');
        } finally {
            this.isLoading = false;
            window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
        }
    }

    async _saveOperationsAndNavigate() {
        const saveParams = {
            applicationId: this.recordId,
            assetId: this.effectiveAssetId,
            applicantId: this.effectiveApplicantId,
            payloadJson: this.getSavePayloadJson({ operationsOnly: true })
        };

        window.dispatchEvent(
            new CustomEvent('losgloballoader', { detail: { show: true, message: 'Saving...' } })
        );
        this.isLoading = true;
        try {
            const response = await saveVehicleInspectionData(saveParams);
            if (response?.isSuccess) {
                this.lastSavedPayloadJson = this.getSavePayloadJson();
                if (response?.message) {
                    this._toast('Saved', response.message, 'success');
                }
                this.emitLosNextStage();
            } else {
                this._toast(
                    'Error',
                    response?.message || 'Unable to save vehicle inspection operations.',
                    'error'
                );
            }
        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Error while saving.';
            this._toast('Error', msg, 'error');
        } finally {
            this.isLoading = false;
            window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
        }
    }

    emitLosNextStage() {
        if (!this.currentViewId) {
            this._toast(
                'Navigation',
                'Current view ID is missing. Please refresh the page and try again.',
                'warning'
            );
            return;
        }
        window.dispatchEvent(
            new CustomEvent(LOS_NEXT_STAGE_EVENT, {
                detail: {
                    currentViewId: this.currentViewId,
                    id: this.currentViewId,
                    applicantId: this.applicantId,
                    currentLoanStageComplete: this.tab || 'Vehicle Inspection',
                    currentStagePhrase: this.stagePhrase || ''
                },
                bubbles: true,
                composed: true
            })
        );
    }

    _toast(title, message, variant = 'info') {
        this.dispatchEvent(
            new CustomEvent('showtoast', {
                detail: { title, message, variant },
                bubbles: true,
                composed: true
            })
        );
    }
}