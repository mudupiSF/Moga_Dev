/**
 * Valuation stage — insurance and vehicle valuation on Asset__c;
 * owner name/contact on Applicant__c.
 */
import { LightningElement, api, track } from 'lwc';
import getValuationData from '@salesforce/apex/ValuationController.getValuationData';
import saveValuationData from '@salesforce/apex/ValuationController.saveValuationData';
import { invokeHandler } from 'c/clientLayerHelper';

const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const INTEGRATION_PROGRESS_EVENT = 'integrationprogressupdate';

const VALUER_CATEGORY_EMPANELLED = 'Empanelled';
const VALUER_CATEGORY_MFC = 'MFC';
const DEFAULT_VALUER_CODE = 'A';
const PRODUCT_TYPE_TRACTOR = 'Tractor';

const PICKLIST_FALLBACK = {
    insuranceType: [
        { label: 'Comprehensive', value: 'Comprehensive' },
        { label: 'Third Party', value: 'Third Party' }
    ],
    valuerCategory: [
        { label: 'Empanelled', value: 'Empanelled' },
        { label: 'MFC', value: 'MFC' },
        { label: 'Adroit', value: 'Adroit' },
        { label: 'TVS Credit', value: 'TVS Credit' },
        { label: 'Car Dekho', value: 'Car Dekho' }
    ]
};

const VALUER_OPTIONS = [
    { label: 'Valuer A', value: 'Valuer A', code: 'A' },
    { label: 'Valuer B', value: 'Valuer B', code: 'B' }
];

const DEFAULT_EXISTING_INSURANCE = {
    insuranceType: '',
    insuranceDeclaredValue: '',
    existingMotorInsurancePremium: '',
    insExpiryDate: ''
};

const DEFAULT_VEHICLE_VALUATION = {
    ownerName: '',
    ownerContactNumber: '',
    vehiclePlaceOfValuation: '',
    valuerCategory: '',
    valuer: '',
    valuerCode: DEFAULT_VALUER_CODE,
    slaNumber: '',
    colorOfVehicle: '',
    kmsRun: ''
};

const EXISTING_INSURANCE_KEYS = new Set(Object.keys(DEFAULT_EXISTING_INSURANCE));

const VALUATION_TEXT_FIELDS = [
    { key: 'ownerName', label: "Owner's Name" },
    { key: 'ownerContactNumber', label: "Owner's Contact Number" },
    { key: 'vehiclePlaceOfValuation', label: "Vehicle's Place of Valuation" },
    { key: 'valuerCode', label: 'Valuer Code' },
    { key: 'slaNumber', label: 'SLA Number' },
    { key: 'kmsRun', label: 'KMS run' }
];

const MONTH_ABBR = {
    jan: '01', feb: '02', mar: '03', apr: '04', may: '05', jun: '06',
    jul: '07', aug: '08', sep: '09', oct: '10', nov: '11', dec: '12'
};

const MFC_UI_IDLE = { isLoading: false, hasErrorMessage: false, errorMessage: '' };

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

function buildValuerOptions(masterOptions, currentValuer) {
    const mapped = normalizeOptions(masterOptions);
    const current = toStr(currentValuer).trim();
    if (!current || mapped.some((o) => o.value === current || o.label === current)) {
        return mapped;
    }
    return [{ label: current, value: current }, ...mapped];
}

function resolvePicklistValue(options, stored) {
    const v = toStr(stored).trim();
    if (!v || !options?.length) {
        return v;
    }
    if (options.some((o) => o.value === v)) {
        return v;
    }
    return options.find((o) => o.label === v)?.value ?? v;
}

function isPresent(type, value) {
    if (value === null || value === undefined) {
        return false;
    }
    if (type === 'currency' || type === 'number') {
        const n = toStr(value).replace(/[^\d.-]/g, '').trim();
        return n !== '' && n !== '-' && n !== '.';
    }
    return toStr(value).trim() !== '';
}

function normalizeDateYmd(val) {
    const s = toStr(val).trim();
    if (!s) {
        return '';
    }
    if (/^\d{4}-\d{2}-\d{2}$/.test(s)) {
        return s;
    }
    const iso = s.match(/^(\d{4}-\d{2}-\d{2})T/);
    if (iso) {
        return iso[1];
    }
    const dmy = s.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/);
    if (dmy) {
        const [, day, month, year] = dmy;
        return `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
    }
    const named = s.match(/^(\d{1,2})[-\s]([A-Za-z]{3,9})[-\s,]*(\d{4})$/i);
    if (named) {
        const month = MONTH_ABBR[named[2].substring(0, 3).toLowerCase()];
        if (month) {
            return `${named[3]}-${month}-${named[1].padStart(2, '0')}`;
        }
    }
    return '';
}

function normalizeLoadedSection(section) {
    if (!section || typeof section !== 'object' || Array.isArray(section)) {
        return {};
    }
    const out = {};
    for (const [key, val] of Object.entries(section)) {
        out[key] = typeof val === 'boolean' ? val : (val == null ? '' : String(val));
    }
    return out;
}

export default class Valuation extends LightningElement {
    @api recordId;
    @api insuranceId;
    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api applicantId;
    @api fromAssetList = false;

    _assetId = '';
    _applicationLineItemId = '';
    _loadSequence = 0;

    @api
    get assetId() {
        return this._assetId;
    }
    set assetId(value) {
        this._assetId = value ? String(value) : '';
        this.tryLoadData();
    }

    @api
    get applicationLineItemId() {
        return this._applicationLineItemId;
    }
    set applicationLineItemId(value) {
        this._applicationLineItemId = value || '';
        this.tryLoadData();
    }

    isLoading = true;
    productType = '';
    mfcRequestId = '';
    oemDealer = false;
    valuerMasterOptions = VALUER_OPTIONS;

    @track insuranceTypeOptions = [];
    @track valuerCategoryOptions = [];
    @track valuerComboboxOptions = [];
    @track existingInsuranceFieldValues = { ...DEFAULT_EXISTING_INSURANCE };
    @track vehicleValuationFieldValues = { ...DEFAULT_VEHICLE_VALUATION };

    showIntegrationProgressModal = false;
    integrationProgressModalStatus = 'loading';
    integrationProgressModalCurrentStageIndex = 0;
    integrationProgressModalStages = [];
    integrationProgressModalSuccessMessage = '';
    integrationProgressModalErrorMessage = '';

    @track mfcValuationSucceeded = false;
    mfcFetchReportSucceeded = false;
    mfcActionInProgress = false;
    @track mfcValuationUi = { ...MFC_UI_IDLE };
    @track mfcFetchReportUi = { ...MFC_UI_IDLE };
    _lastActionFieldKey = '';
    _lastMfcValuationMessage = '';
    @track _mfcActionStates = {};

    /** Set from Apex when parent does not pass asset-id. */
    _resolvedAssetId = '';
    _resolvedApplicantId = '';

    _isStagePast = false;
    _integrationProgressHandler;

    @api
    get isStagePast() {
        return this._isStagePast;
    }
    set isStagePast(value) {
        this._isStagePast = !!value;
    }

    connectedCallback() {
        this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e);
        window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        this.tryLoadData();
    }

    disconnectedCallback() {
        if (this._integrationProgressHandler) {
            window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        }
    }

    tryLoadData() {
        if (!this.recordId && !this._assetId && !this.applicantId) {
            return;
        }
        if (this.fromAssetList && (!this._applicationLineItemId || !this._assetId)) {
            return;
        }
        this._loadPageData();
    }

    get isEditable() {
        return !this.isStagePast;
    }

    get isTractorProduct() {
        return toStr(this.productType).trim().toLowerCase() === PRODUCT_TYPE_TRACTOR.toLowerCase();
    }

    get showColorField() {
        return !this.isTractorProduct;
    }

    get kmsRunLabel() {
        return this.isTractorProduct ? 'HMR (in Hrs)' : 'KMS run';
    }

    get insuranceExpiryYmd() {
        return normalizeDateYmd(this.existingInsuranceFieldValues?.insExpiryDate);
    }

    get valuationSectionVisible() {
        return this.isExistingInsuranceComplete();
    }

    get showMfcActionBar() {
        return toStr(this.vehicleValuationFieldValues?.valuerCategory).trim().toUpperCase() ===
            VALUER_CATEGORY_MFC.toUpperCase();
    }

    get valuationUi() {
        return this.getValuationUiState();
    }

    get valuerCodeReadonly() {
        return this.valuationUi.lockValuerCodeAfterPick;
    }

    get colorKmsReadonly() {
        return this.valuationUi.lockColorKmsMfc;
    }

    get getValuationBtnDisabled() {
        const ui = this.valuationUi;
        return !ui.getValuationEnabled || this.mfcValuationUi.isLoading || this.mfcActionInProgress;
    }

    get fetchReportBtnDisabled() {
        const ui = this.valuationUi;
        return !ui.fetchReportEnabled || this.mfcFetchReportUi.isLoading || this.mfcActionInProgress;
    }

    get getValuationBtnClass() {
        return this.mfcBtnClass(this.getValuationBtnDisabled, this.mfcValuationUi.hasErrorMessage);
    }

    get fetchReportBtnClass() {
        return this.mfcBtnClass(this.fetchReportBtnDisabled, this.mfcFetchReportUi.hasErrorMessage);
    }

    get isGetValuationSuccess() {
        return this.mfcValuationSucceeded === true;
    }

    get isFetchReportSuccess() {
        return this.mfcFetchReportSucceeded === true;
    }

    get isNextDisabled() {
        if (this.isLoading || this.isStagePast) {
            return this.isLoading;
        }
        if (!this.valuationSectionVisible) {
            return true;
        }
        if (!this.areVehicleValuationFieldsComplete()) {
            return true;
        }
        if (this.valuationUi.getValuationMandatoryForSubmit) {
            return true;
        }
        return false;
    }

    get nextButtonClass() {
        return `p4-primary-btn p4-button-text${this.isNextDisabled ? ' stage-next-btn--disabled' : ''}`;
    }

    mfcBtnClass(disabled, hasError) {
        let cls = 'p4-primary-btn p4-button-text';
        if (hasError) cls += ' p4-action-btn-error';
        return cls;
    }

    isExistingInsuranceComplete() {
        const ex = this.existingInsuranceFieldValues || {};
        return (
            isPresent('picklist', ex.insuranceType) &&
            isPresent('currency', ex.insuranceDeclaredValue) &&
            isPresent('currency', ex.existingMotorInsurancePremium) &&
            isPresent('date', this.insuranceExpiryYmd || ex.insExpiryDate)
        );
    }

    get effectiveAssetId() {
        return toStr(this._assetId).trim() || toStr(this._resolvedAssetId).trim();
    }

    get effectiveApplicantId() {
        return toStr(this.applicantId).trim() || toStr(this._resolvedApplicantId).trim();
    }

    async _loadPageData() {
        const loadSequence = ++this._loadSequence;

        if (!this.recordId && !this._assetId && !this.applicantId) {
            this.resetState();
            this.isLoading = false;
            return;
        }
        if (this.fromAssetList && (!this._applicationLineItemId || !this._assetId)) {
            return;
        }

        this.isLoading = true;
        try {
            const data = await getValuationData({
                applicationId: this.recordId,
                assetId: this._assetId,
                insuranceId: this.insuranceId,
                applicantId: this.applicantId
            });
            if (loadSequence !== this._loadSequence) {
                return;
            }

            this._resolvedAssetId = data?.resolvedAssetId ? String(data.resolvedAssetId) : '';
            this._resolvedApplicantId = data?.resolvedApplicantId
                ? String(data.resolvedApplicantId)
                : '';

            if (data?.assetNotFound === true) {
                // Asset not yet linked — form still renders with defaults.
            }

            this.productType = data?.productType ?? '';
            this.valuerMasterOptions =
                Array.isArray(data?.valuerMasterOptions) && data.valuerMasterOptions.length
                    ? data.valuerMasterOptions
                    : VALUER_OPTIONS;

            const ctx = data?.valuationContext || {};
            this.mfcRequestId = ctx.mfcRequestId != null ? String(ctx.mfcRequestId) : '';
            this.oemDealer = ctx.oemDealer === true;
            const hasRequestId = toStr(this.mfcRequestId).trim().length > 0;
            this.mfcValuationSucceeded = hasRequestId;
            this.mfcFetchReportSucceeded = false;

            this.applyPicklists(data?.picklists);

            this.existingInsuranceFieldValues = {
                ...DEFAULT_EXISTING_INSURANCE,
                ...this.normalizeExistingInsurance(
                    normalizeLoadedSection(data?.existingInsurance)
                )
            };
            this.vehicleValuationFieldValues = this.withDefaultValuerCode(
                this.normalizeValuationPicklists(
                    normalizeLoadedSection(data?.vehicleValuation)
                )
            );
            this.syncValuerComboboxOptions();
        } catch (error) {
            if (loadSequence !== this._loadSequence) {
                return;
            }
            console.error('Error loading valuation page:', error);
            this.resetState();
            this._toast('Error', 'Unable to load vehicle insurance and valuation.', 'error');
        } finally {
            if (loadSequence === this._loadSequence) {
                this.isLoading = false;
            }
        }
    }

    applyPicklists(picklists) {
        const p = picklists || {};
        this.insuranceTypeOptions = normalizeOptions(
            p.insuranceType?.length ? p.insuranceType : PICKLIST_FALLBACK.insuranceType
        );
        this.valuerCategoryOptions = normalizeOptions(
            p.valuerCategory?.length ? p.valuerCategory : PICKLIST_FALLBACK.valuerCategory
        );
        this.syncValuerComboboxOptions();
    }

    normalizeExistingInsurance(values) {
        const next = { ...values };
        const ymd = normalizeDateYmd(next.insExpiryDate);
        if (ymd) {
            next.insExpiryDate = ymd;
        }
        next.insuranceType = resolvePicklistValue(this.insuranceTypeOptions, next.insuranceType);
        return next;
    }

    normalizeValuationPicklists(values) {
        const next = { ...values };
        next.valuerCategory = resolvePicklistValue(this.valuerCategoryOptions, next.valuerCategory);
        next.valuer = resolvePicklistValue(this.valuerMasterOptions, next.valuer);
        return next;
    }

    syncValuerComboboxOptions() {
        this.valuerComboboxOptions = buildValuerOptions(
            this.valuerMasterOptions,
            this.vehicleValuationFieldValues?.valuer
        );
    }

    resetState() {
        this._resolvedAssetId = '';
        this._resolvedApplicantId = '';
        this.productType = '';
        this.mfcRequestId = '';
        this.oemDealer = false;
        this.valuerMasterOptions = VALUER_OPTIONS;
        this.insuranceTypeOptions = PICKLIST_FALLBACK.insuranceType;
        this.valuerCategoryOptions = PICKLIST_FALLBACK.valuerCategory;
        this.existingInsuranceFieldValues = { ...DEFAULT_EXISTING_INSURANCE };
        this.vehicleValuationFieldValues = { ...DEFAULT_VEHICLE_VALUATION };
        this.syncValuerComboboxOptions();
        this.mfcValuationSucceeded = false;
        this.mfcFetchReportSucceeded = false;
        this.mfcValuationUi = { ...MFC_UI_IDLE };
        this.mfcFetchReportUi = { ...MFC_UI_IDLE };
    }

    getValuationUiState() {
        const values = this.vehicleValuationFieldValues || {};
        const category = toStr(values.valuerCategory).trim();
        const isEmpanelled = category.toLowerCase() === VALUER_CATEGORY_EMPANELLED.toLowerCase();
        const isMfc = category.toUpperCase() === VALUER_CATEGORY_MFC.toUpperCase();
        const readOnlyStage = this.isStagePast;
        const hasRequestId = toStr(this.mfcRequestId).trim().length > 0;
        const getValuationDoneThisSession = this.mfcValuationSucceeded === true;
        const lockColorKmsMfc = isMfc && getValuationDoneThisSession;
        const valuerSelected = toStr(values.valuer).trim() !== '';
        const valuerCodeFilled = toStr(values.valuerCode).trim() !== '';
        const lockValuerCodeAfterPick = isEmpanelled && valuerSelected && valuerCodeFilled;

        let getValuationEnabled = false;
        let fetchReportEnabled = false;
        if (!readOnlyStage && !this.oemDealer && isMfc) {
            getValuationEnabled = !getValuationDoneThisSession;
            fetchReportEnabled = getValuationDoneThisSession && hasRequestId && !this.mfcFetchReportSucceeded;
        }

        return {
            isMfc,
            lockValuerCodeAfterPick,
            lockColorKmsMfc,
            getValuationEnabled,
            fetchReportEnabled,
            getValuationMandatoryForSubmit: isMfc && getValuationEnabled && !getValuationDoneThisSession
        };
    }

    handleExistingInsuranceChange(event) {
        const field = event.currentTarget?.dataset?.field;
        if (!field || !EXISTING_INSURANCE_KEYS.has(field)) {
            return;
        }
        let value = event.detail?.value ?? event.target?.value ?? '';
        if (field === 'insExpiryDate') {
            const ymd = normalizeDateYmd(value);
            if (ymd) value = ymd;
        } else {
            value = toStr(value);
        }
        this.existingInsuranceFieldValues = {
            ...this.existingInsuranceFieldValues,
            [field]: value
        };
    }

    handleValuationChange(event) {
        const field = event.currentTarget?.dataset?.field;
        if (!field) {
            return;
        }
        const value = toStr(event.detail?.value ?? event.target?.value ?? '');
        this.updateVehicleValuation({ [field]: value });
    }

    handleValuationComboboxChange(event) {
        const field = event.currentTarget?.dataset?.field;
        if (!field) {
            return;
        }
        const value = event.detail?.value ?? event.target?.value ?? '';
        this.updateVehicleValuation({ [field]: value });
    }

    updateVehicleValuation(patch) {
        this.vehicleValuationFieldValues = this.applyValuationSideEffects({
            ...this.vehicleValuationFieldValues,
            ...patch
        });
    }

    resolveValuerCode(valuerName) {
        const name = toStr(valuerName).trim();
        if (!name) {
            return DEFAULT_VALUER_CODE;
        }
        const match = (this.valuerMasterOptions || []).find(
            (opt) => toStr(opt?.value || opt?.label).trim() === name
        );
        const code = match?.code != null ? toStr(match.code).trim() : '';
        return code || DEFAULT_VALUER_CODE;
    }

    withDefaultValuerCode(fieldValues) {
        const next = { ...fieldValues };
        if (toStr(next.valuerCode).trim() === '') {
            next.valuerCode = DEFAULT_VALUER_CODE;
        }
        return next;
    }

    applyValuationSideEffects(fieldValues) {
        const prev = this.vehicleValuationFieldValues || {};
        let next = { ...fieldValues };
        const valuationChanged = Object.keys({ ...prev, ...next }).some(
            (key) => toStr(prev[key]) !== toStr(next[key])
        );
        if (valuationChanged) {
            this.mfcValuationSucceeded = false;
            this.mfcFetchReportSucceeded = false;
            this.mfcValuationUi = { ...MFC_UI_IDLE };
            this.mfcFetchReportUi = { ...MFC_UI_IDLE };
        }
        if (next.valuer !== prev.valuer) {
            next.valuerCode = this.resolveValuerCode(next.valuer);
        }
        return this.withDefaultValuerCode(next);
    }

    getSavePayloadJson() {
        return JSON.stringify({
            existingInsurance: this.existingInsuranceFieldValues,
            vehicleValuation: this.vehicleValuationFieldValues
        });
    }

    async handleNextButton() {
        if (!this.recordId && !this.effectiveAssetId && !this.applicantId) {
            return;
        }
        if (this.isNextDisabled) {
            return;
        }
        if (this.valuationUi.getValuationMandatoryForSubmit) {
            this._toast('Get Valuation required', 'Please complete Get Valuation before proceeding.', 'error');
            return;
        }
        if (this.isStagePast) {
            if (this.fromAssetList) {
                this.returnToAssetList(false);
                return;
            }
            this.emitLosNextStage();
            return;
        }

        const missing = this.getMissingMandatoryFieldLabels();
        if (missing.length > 0) {
            this._toast('Missing Required Fields', `Please fill mandatory fields: ${missing.join(', ')}`, 'error');
            return;
        }

        window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: true, message: 'Saving...' } }));
        this.isLoading = true;
        try {
            const response = await saveValuationData({
                applicationId: this.recordId,
                assetId: this.effectiveAssetId,
                insuranceId: this.insuranceId,
                applicantId: this.effectiveApplicantId,
                applicationLineItemId: this._applicationLineItemId || null,
                payloadJson: this.getSavePayloadJson()
            });

            if (!response?.isSuccess) {
                this._toast('Error', response?.message || 'Unable to save vehicle insurance and valuation.', 'error');
                return;
            }

            if (response.resolvedAssetId) {
                this._resolvedAssetId = String(response.resolvedAssetId);
            }
            if (response.resolvedApplicantId) {
                this._resolvedApplicantId = String(response.resolvedApplicantId);
            }
            if (response.message) {
                this._toast('Saved', response.message, 'success');
            }

            if (this.fromAssetList) {
                this.returnToAssetList(true);
            } else {
                this.emitLosNextStage();
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
                    currentLoanStageComplete: this.tab || 'Valuation',
                    currentStagePhrase: this.stagePhrase || ''
                },
                bubbles: true,
                composed: true
            })
        );
    }

    returnToAssetList(saved) {
        this.dispatchEvent(
            new CustomEvent('detailcomplete', {
                detail: { lineItemId: this._applicationLineItemId || null, saved },
                bubbles: true,
                composed: true
            })
        );
    }

    async handleGetValuationClick() {
        const ui = this.valuationUi;
        if (this.mfcActionInProgress || !this.recordId || !ui.isMfc || !ui.getValuationEnabled) {
            return;
        }
        const missing = this.collectMissingValuationLabels({ includeSla: true });
        if (missing.length > 0) {
            this._toast(
                'Required Fields',
                `Please fill all fields before Get Valuation: ${missing.join(', ')}`,
                'error'
            );
            return;
        }
        this._lastActionFieldKey = 'mfcValuation';
        this.mfcActionInProgress = true;
        try {
            await invokeHandler('clientLayerValuation', 'onAction', this);
            if (this._mfcActionStates.mfcValuation === 'success') {
                this._toast(
                    'Success',
                    this._lastMfcValuationMessage || 'Valuation request submitted successfully.',
                    'success'
                );
            }
        } finally {
            this.mfcActionInProgress = false;
        }
    }

    async handleFetchValuationReportClick() {
        const ui = this.valuationUi;
        if (this.mfcActionInProgress || !ui.isMfc || !ui.fetchReportEnabled || !this.recordId) {
            return;
        }
        this._lastActionFieldKey = 'mfcFetchReport';
        this.mfcActionInProgress = true;
        try {
            await invokeHandler('clientLayerValuation', 'onAction', this);
        } finally {
            this.mfcActionInProgress = false;
        }
    }

    get fields() {
        return [
            { key: 'recordId', value: this.recordId },
            { key: 'assetId', value: this.effectiveAssetId },
            { key: 'applicantId', value: this.effectiveApplicantId }
        ];
    }

    setActionState(key, state) {
        if (!['mfcValuation', 'mfcFetchReport'].includes(key)) {
            return;
        }
        if (!['idle', 'loading', 'success'].includes(state)) {
            return;
        }
        this._mfcActionStates = { ...this._mfcActionStates, [key]: state };
        if (key === 'mfcValuation') {
            if (state === 'loading') {
                this.mfcValuationUi = { isLoading: true, hasErrorMessage: false, errorMessage: '' };
            } else if (state === 'success') {
                this.mfcValuationSucceeded = true;
                this.mfcFetchReportSucceeded = false;
                this.mfcValuationUi = { ...MFC_UI_IDLE };
                this.mfcFetchReportUi = { ...MFC_UI_IDLE };
            } else {
                this.mfcValuationUi = {
                    isLoading: false,
                    hasErrorMessage: this.mfcValuationUi.hasErrorMessage,
                    errorMessage: this.mfcValuationUi.errorMessage
                };
            }
            return;
        }
        if (key === 'mfcFetchReport') {
            if (state === 'loading') {
                this.mfcFetchReportUi = { isLoading: true, hasErrorMessage: false, errorMessage: '' };
            } else if (state === 'success') {
                this.mfcFetchReportSucceeded = true;
                this.mfcFetchReportUi = { ...MFC_UI_IDLE };
            } else {
                this.mfcFetchReportUi = {
                    isLoading: false,
                    hasErrorMessage: this.mfcFetchReportUi.hasErrorMessage,
                    errorMessage: this.mfcFetchReportUi.errorMessage
                };
            }
        }
    }

    updateFieldValue(key, value) {
        if (key === 'mfcRequestId') {
            this.mfcRequestId = toStr(value);
            return;
        }
        if (key === 'mfcValuationResponse') {
            this._lastMfcValuationMessage = value?.message || '';
            return;
        }
        if (key === 'mfcValuationErrorMessage') {
            const message = value || '';
            this.mfcValuationUi = {
                isLoading: false,
                hasErrorMessage: !!message,
                errorMessage: message
            };
            if (message) {
                this._toast('Get Valuation Failed', message, 'error');
            }
            return;
        }
        if (key === 'mfcFetchReportErrorMessage') {
            const message = value || '';
            this.mfcFetchReportUi = {
                isLoading: false,
                hasErrorMessage: !!message,
                errorMessage: message
            };
            if (message) {
                this._toast('Fetch Valuation Report Failed', message, 'error');
            }
        }
    }

    handleIntegrationProgressUpdate(event) {
        const d = event.detail || {};
        if (typeof d.show === 'boolean') {
            this.showIntegrationProgressModal = d.show;
        } else if (d.status === 'loading') {
            this.showIntegrationProgressModal = true;
        }
        this.integrationProgressModalStatus = d.status || 'loading';
        this.integrationProgressModalCurrentStageIndex = d.currentStageIndex ?? 0;
        this.integrationProgressModalStages = d.stages || [];
        this.integrationProgressModalErrorMessage = d.errorMessage || '';
        this.integrationProgressModalSuccessMessage = d.successMessage || '';
    }

    closeIntegrationProgress() {
        this.showIntegrationProgressModal = false;
    }

    handleIntegrationProgressDone() {
        this.showIntegrationProgressModal = false;
    }

    handleIntegrationProgressRetry() {
        this.integrationProgressModalStatus = 'loading';
        this.integrationProgressModalCurrentStageIndex = 0;
        this.integrationProgressModalErrorMessage = '';
        if (this._lastActionFieldKey === 'mfcFetchReport') {
            void this.handleFetchValuationReportClick();
            return;
        }
        void this.handleGetValuationClick();
    }

    getMissingMandatoryFieldLabels() {
        const missing = new Map();
        const ex = this.existingInsuranceFieldValues || {};

        const insuranceFields = [
            { key: 'insuranceType', label: 'Insurance Type', type: 'picklist' },
            { key: 'insuranceDeclaredValue', label: 'Insurance Declared Value', type: 'currency' },
            { key: 'existingMotorInsurancePremium', label: 'Existing Motor Insurance Premium', type: 'currency' },
            { key: 'insExpiryDate', label: 'Insurance Expiry Date', type: 'date' }
        ];
        for (const field of insuranceFields) {
            const val = field.key === 'insExpiryDate'
                ? (this.insuranceExpiryYmd || ex.insExpiryDate)
                : ex[field.key];
            if (!isPresent(field.type, val)) {
                missing.set(field.key, field.label);
            }
        }

        for (const label of this.collectMissingValuationLabels({ includeSla: true })) {
            missing.set(label, label);
        }

        return Array.from(missing.values());
    }

    areVehicleValuationFieldsComplete() {
        return this.collectMissingValuationLabels({ includeSla: true }).length === 0;
    }

    collectMissingValuationLabels({ includeSla = false } = {}) {
        const labels = [];
        const valuation = this.vehicleValuationFieldValues || {};
        for (const field of VALUATION_TEXT_FIELDS) {
            if (!includeSla && field.key === 'slaNumber') {
                continue;
            }
            const label = field.key === 'kmsRun' ? this.kmsRunLabel : field.label;
            if (!isPresent('text', valuation[field.key])) {
                labels.push(label);
            }
        }
        if (!isPresent('picklist', valuation.valuerCategory)) {
            labels.push('Valuer Category');
        }
        if (!isPresent('picklist', valuation.valuer)) {
            labels.push('Valuer Name');
        }
        if (this.showColorField && !isPresent('text', valuation.colorOfVehicle)) {
            labels.push('Color of Vehicle');
        }
        return labels;
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