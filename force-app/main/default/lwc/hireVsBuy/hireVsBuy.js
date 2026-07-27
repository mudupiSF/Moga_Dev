import { LightningElement, api, track } from 'lwc';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';
import { getModelLabel } from 'c/mmvMasterData';

const APEX_CLASS = 'HireVsBuyController';
const APEX_GET_METHOD = 'getHireVsBuyData';
const APEX_SAVE_METHOD = 'saveHireVsBuyData';

const FAVOURABLE = 'FAVOURABLE';
const NON_FAVOURABLE = 'NON FAVOURABLE';
const MAX_HOURS_PER_DAY = 24;
const MAX_WORKING_DAYS_PER_MONTH = 31;

const CALCULATED_READONLY_KEYS = new Set([
    'vehicleModel',
    'monthlyRunningHours',
    'monthlyChargesForHire',
    'fuelCost',
    'totalEmi',
    'totalExpensesOwnership',
    'hireVsBuyDifference',
    'hireVsBuyFavourable'
]);

const FORM_RESPONSE_KEYS = [
    'typeOfWork',
    'hoursPerDay',
    'workingDaysPerMonth',
    'monthlyRunningHours',
    'ratePerHour',
    'monthlyChargesForHire',
    'fuelAverageLitrePerHour',
    'costPerLitreFuel',
    'fuelCost',
    'driversSalaryAllowances',
    'insuranceTaxesEtc',
    'repairServicingMisc',
    'emi',
    'existingEmi',
    'totalEmi',
    'totalExpensesOwnership',
    'hireVsBuyDifference',
    'hireVsBuyFavourable'
];

const DEFAULT_FORM_VALUES = Object.freeze({
    vehicleModel: '',
    typeOfWork: '',
    hoursPerDay: '',
    workingDaysPerMonth: '',
    monthlyRunningHours: '',
    ratePerHour: '',
    monthlyChargesForHire: '',
    fuelAverageLitrePerHour: '',
    costPerLitreFuel: '',
    fuelCost: '',
    driversSalaryAllowances: '',
    insuranceTaxesEtc: '',
    repairServicingMisc: '',
    emi: '',
    existingEmi: '',
    totalEmi: '',
    totalExpensesOwnership: '',
    hireVsBuyDifference: '',
    hireVsBuyFavourable: NON_FAVOURABLE
});

const SECTION_CONFIG = [
    {
        key: 'details',
        icon: 'utility:record',
        title: 'Details Part',
        subtitle: 'Update application information',
        fields: [
            { key: 'vehicleModel', label: 'Vehicle Model', type: 'text' },
            { key: 'typeOfWork', label: 'Type of Work', type: 'text' }
        ]
    },
    {
        key: 'hire',
        icon: 'utility:money',
        title: 'Hire Part',
        subtitle: 'Monthly hiring charges',
        fields: [
            { key: 'hoursPerDay', label: 'No of Hours / Day', type: 'number' },
            { key: 'workingDaysPerMonth', label: 'Working Days / Month', type: 'number' },
            { key: 'monthlyRunningHours', label: 'Monthly Running in Hours', type: 'number' },
            { key: 'ratePerHour', label: 'Rate / Hour', type: 'number' },
            { key: 'monthlyChargesForHire', label: 'Monthly Charges for Hire', type: 'number' }
        ]
    },
    {
        key: 'buy',
        icon: 'utility:fuel',
        title: 'Buy Part',
        subtitle: 'Fuel and operating inputs',
        fields: [
            { key: 'fuelAverageLitrePerHour', label: 'Fuel Average / Hour', type: 'number' },
            { key: 'costPerLitreFuel', label: 'Cost per Litre', type: 'number' },
            { key: 'fuelCost', label: 'Fuel Cost', type: 'number' }
        ]
    },
    {
        key: 'ownership',
        icon: 'utility:summary',
        title: 'Cost of Ownership',
        subtitle: 'Ownership expenses and comparison',
        fields: [
            { key: 'driversSalaryAllowances', label: 'Drivers Salary & Allowances', type: 'number' },
            { key: 'insuranceTaxesEtc', label: 'Insurance/Taxes etc', type: 'number' },
            { key: 'repairServicingMisc', label: 'Repair/Servicing/Misc', type: 'number' },
            { key: 'emi', label: 'EMI', type: 'number' },
            { key: 'existingEmi', label: 'Existing EMI', type: 'number' },
            { key: 'totalEmi', label: 'Total EMI', type: 'number' },
            { key: 'totalExpensesOwnership', label: 'Total Expenses', type: 'number' },
            { key: 'hireVsBuyDifference', label: 'HIRE Vs BUY Difference', type: 'number' },
            { key: 'hireVsBuyFavourable', label: 'HIRE Vs BUY is Favourable', type: 'text' }
        ]
    }
];

const toNumber = (value) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
};

const computeHireVsBuyValues = (formValues) => {
    const source = formValues || {};
    const hoursPerDay = toNumber(source.hoursPerDay);
    const workingDaysPerMonth = toNumber(source.workingDaysPerMonth);
    const monthlyRunningHours = hoursPerDay * workingDaysPerMonth;
    const ratePerHour = toNumber(source.ratePerHour);
    const monthlyChargesForHire = ratePerHour * monthlyRunningHours;
    const fuelAverageLitrePerHour = toNumber(source.fuelAverageLitrePerHour);
    const costPerLitreFuel = toNumber(source.costPerLitreFuel);
    const fuelCost = monthlyRunningHours * fuelAverageLitrePerHour * costPerLitreFuel;
    const emi = toNumber(source.emi);
    const existingEmi = toNumber(source.existingEmi);
    const totalEmi = emi + existingEmi;
    const driversSalaryAllowances = toNumber(source.driversSalaryAllowances);
    const insuranceTaxesEtc = toNumber(source.insuranceTaxesEtc);
    const repairServicingMisc = toNumber(source.repairServicingMisc);
    const totalExpensesOwnership =
        fuelCost + driversSalaryAllowances + insuranceTaxesEtc + repairServicingMisc + totalEmi;
    const hireVsBuyDifference = monthlyChargesForHire - totalExpensesOwnership;

    return {
        ...source,
        monthlyRunningHours,
        monthlyChargesForHire,
        fuelCost,
        totalEmi,
        totalExpensesOwnership,
        hireVsBuyDifference,
        hireVsBuyFavourable: hireVsBuyDifference > 0 ? FAVOURABLE : NON_FAVOURABLE
    };
};

const formatDisplayValue = (def, raw) => {
    const text = String(raw ?? '').trim();
    if (!text) {
        return '-';
    }
    if (def.type === 'number') {
        const parsed = Number(text);
        return Number.isFinite(parsed) ? parsed.toLocaleString('en-IN', { maximumFractionDigits: 2 }) : text;
    }
    return text;
};

const extractApexError = (error) => {
    if (Array.isArray(error?.body)) {
        return error.body.map((item) => item?.message).filter(Boolean).join(', ');
    }
    return error?.body?.message || error?.message || '';
};

const validateHireVsBuyForm = (formValues) => {
    const fieldErrors = {};
    const hoursText = String(formValues?.hoursPerDay ?? '').trim();
    const daysText = String(formValues?.workingDaysPerMonth ?? '').trim();

    if (hoursText) {
        const hoursPerDay = Number(hoursText);
        if (Number.isFinite(hoursPerDay) && hoursPerDay >= MAX_HOURS_PER_DAY) {
            fieldErrors.hoursPerDay = 'No of Hours / Day must be less than 24.';
        }
    }

    if (daysText) {
        const workingDaysPerMonth = Number(daysText);
        if (Number.isFinite(workingDaysPerMonth) && workingDaysPerMonth > MAX_WORKING_DAYS_PER_MONTH) {
            fieldErrors.workingDaysPerMonth = 'Working Days / Month must be less than or equal to 31.';
        }
    }

    if (!Object.keys(fieldErrors).length) {
        return null;
    }

    return fieldErrors;
};

export default class HireVsBuy extends LightningElement {
    _recordId;
    _assetId;
    _loadDebounce;
    _activeLoadToken = 0;
    _productType = '';
    _assetMake = '';
    _assetModelCode = '';

    @track formValues = { ...DEFAULT_FORM_VALUES };
    @track isLoading = false;
    @track errorMessage = '';
    @track fieldErrors = {};
    @track hasExistingData = false;
    @track _savedThisSession = false;

    @api isReadOnly = false;
    @api allowEditWhenExisting = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        this._scheduleLoad();
    }

    @api
    get assetId() {
        return this._assetId;
    }

    set assetId(value) {
        this._assetId = value ? String(value) : null;
        this._scheduleLoad();
    }

    get isReadOnlyMode() {
        if (this.isReadOnly === true) {
            return true;
        }
        if (this._savedThisSession) {
            return true;
        }
        if (this.allowEditWhenExisting === true) {
            return false;
        }
        return this.hasExistingData;
    }

    get isSaveDisabled() {
        return this.isLoading || this.isReadOnlyMode;
    }

    get sections() {
        const readOnly = this.isReadOnlyMode;
        return SECTION_CONFIG.map((section) => ({
            ...section,
            fields: section.fields.map((def) => {
                const raw =
                    def.key === 'vehicleModel'
                        ? this._resolveVehicleModelLabel()
                        : (this.formValues?.[def.key] ?? '');
                const value = raw != null && raw !== '' ? String(raw) : '';
                const showAsReadOnly = readOnly || CALCULATED_READONLY_KEYS.has(def.key);
                return {
                    ...def,
                    value,
                    displayValue: formatDisplayValue(def, raw),
                    isNumber: def.type === 'number',
                    showAsReadOnly,
                    wrapClass: this.fieldErrors?.[def.key]
                        ? 'lt-field-wrap lt-field-wrap-error'
                        : 'lt-field-wrap',
                    fieldError: this.fieldErrors?.[def.key] || '',
                    hasInputMax: def.key === 'hoursPerDay' || def.key === 'workingDaysPerMonth',
                    inputMax: def.key === 'hoursPerDay' ? '23.99' : def.key === 'workingDaysPerMonth' ? '31' : ''
                };
            })
        }));
    }

    @api
    loadData() {
        this.loadHireVsBuyData();
    }

    handleFieldUpdate(event) {
        if (this.isReadOnlyMode) {
            return;
        }
        const key = event.currentTarget?.dataset?.key;
        if (!key || CALCULATED_READONLY_KEYS.has(key)) {
            return;
        }
        const value = event.detail?.value ?? event.target?.value ?? event.currentTarget?.value ?? '';
        const nextValues = computeHireVsBuyValues({
            ...this.formValues,
            [key]: value
        });
        this.formValues = nextValues;
        this._clearFieldError(key);
    }

    _clearFieldError(key) {
        if (!key || !this.fieldErrors?.[key]) {
            return;
        }
        const nextErrors = { ...this.fieldErrors };
        delete nextErrors[key];
        this.fieldErrors = nextErrors;
    }

    _applyFormValidation() {
        const fieldErrors = validateHireVsBuyForm(this.formValues);
        if (!fieldErrors) {
            this.fieldErrors = {};
            return true;
        }
        this.fieldErrors = fieldErrors;
        return false;
    }

    handleCancel() {
        this._closeModal(false);
    }

    async handleSave() {
        if (this.isReadOnlyMode || this.isSaveDisabled || !this._assetId) {
            if (!this._assetId) {
                this.errorMessage =
                    'Asset ID is missing. Close the modal and open Hire vs Buy again from the asset screen.';
            }
            return;
        }

        if (!this._applyFormValidation()) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        try {
            const { vehicleModel: _ignored, ...payload } = computeHireVsBuyValues(this.formValues);
            const response = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_SAVE_METHOD,
                recordId: this._recordId,
                params: { assetId: this._assetId, ...payload }
            });
            if (!response?.isSuccess) {
                this.errorMessage = response?.message || 'Unable to save Hire vs Buy details.';
                return;
            }
            this._closeModal(true);
        } catch (error) {
            this.errorMessage = extractApexError(error) || 'Unable to save Hire vs Buy details.';
        } finally {
            this.isLoading = false;
        }
    }

    _scheduleLoad() {
        if (!this._recordId) {
            return;
        }
        if (this._loadDebounce) {
            clearTimeout(this._loadDebounce);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._loadDebounce = setTimeout(() => this.loadHireVsBuyData(), 50);
    }

    async loadHireVsBuyData() {
        if (!this._recordId) {
            return;
        }
        const token = ++this._activeLoadToken;
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const data = await getPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_GET_METHOD,
                recordId: this._recordId,
                params: { assetId: this._assetId || null }
            });
            if (token !== this._activeLoadToken) {
                return;
            }
            if (data?.loadError) {
                this.errorMessage = data.loadError;
                return;
            }
            this._applyLoadedData(data);
        } catch (error) {
            if (token !== this._activeLoadToken) {
                return;
            }
            this.errorMessage = extractApexError(error) || 'Unable to load Hire vs Buy details.';
        } finally {
            if (token === this._activeLoadToken) {
                this.isLoading = false;
            }
        }
    }

    _applyLoadedData(data) {
        const d = data || {};
        if (d.assetId) {
            this._assetId = String(d.assetId);
        }
        this._productType = d.productType ?? '';
        this._assetMake = d.assetMake ?? '';
        this._assetModelCode = d.vehicleModelCode ?? d.assetModel ?? '';
        const values = {
            ...DEFAULT_FORM_VALUES,
            vehicleModel: this._resolveVehicleModelLabel()
        };
        FORM_RESPONSE_KEYS.forEach((key) => {
            values[key] = d[key] ?? values[key] ?? '';
        });
        this.formValues = computeHireVsBuyValues(values);
        this.hasExistingData = d.hasExistingData === true;
        this.fieldErrors = {};
        this.errorMessage = '';
    }

    _resolveVehicleModelLabel() {
        const modelCode = this._assetModelCode || '';
        if (!modelCode) {
            return '';
        }
        return getModelLabel(this._productType, this._assetMake, modelCode) || modelCode;
    }

    _closeModal(saved = false) {
        this.dispatchEvent(
            new CustomEvent('close', {
                detail: { saved },
                bubbles: true,
                composed: true
            })
        );
    }

    @api
    handleClose() {
        this.isLoading = false;
    }
}