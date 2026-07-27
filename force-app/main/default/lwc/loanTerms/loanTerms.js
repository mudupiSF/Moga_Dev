import { LightningElement, api, track } from 'lwc';
import getLoanTermsData from '@salesforce/apex/LoanTermsController.getLoanTermsData';
import saveLoanTermsData from '@salesforce/apex/LoanTermsController.saveLoanTermsData';

const STAMPING_PAID_BY_OPTIONS = [
    { label: 'Bank', value: 'Bank' },
    { label: 'Customer', value: 'Customer' }
];

const IN_INTEGRATION_STAGES = [
    'LTV API',
    'Pricing Engine API',
    'Offer Engine API'
];
const NI_INTEGRATION_STAGES = ['Offer Engine API'];
const PL_INTEGRATION_STAGES = ['Offer Engine API'];
const INTEGRATION_STAGE_MIN_DURATION_MS = 1000;
const LOG_PREFIX = '[loanTerms]';

const PAY_IN_FIELDS = [
    { key: 'serviceCharges', label: 'Service Charges', inputType: 'number' },
    { key: 'documentationCharges', label: 'Documentation Charges', inputType: 'number' },
    { key: 'applicableStampingCharges', label: 'Applicable Stamping Charges', inputType: 'number' },
    { key: 'cess', label: 'Cess', inputType: 'number' },
    { key: 'stampingChargesPaidBy', label: 'Stamping Charges Paid By', inputType: 'picklist' },
    { key: 'tradeCertificate', label: 'Trade Certificate', inputType: 'number' }
];

const PAY_OUT_FIELDS = [
    { key: 'mainDealerAmt', label: 'Dealer Incentive Amount (Main Dealer)', inputType: 'number' },
    { key: 'subDealerAmt', label: 'Dealer Incentive Amount (Sub Dealer)', inputType: 'number' },
    { key: 'giftAmt', label: 'Gift Through Dealer Amount', inputType: 'number' },
    { key: 'dsmName', label: 'DSM Name', inputType: 'text' },
    { key: 'dsmIncentive', label: 'DSM Incentive', inputType: 'number' }
];

function formatDisplayValue(value) {
    if (value === null || value === undefined || String(value).trim() === '') {
        return '-';
    }
    return String(value);
}

function getEffectiveFieldValue(def, values) {
    const raw = values?.[def.key];
    if (raw == null || raw === '') {
        return def.inputType === 'picklist' ? 'Bank' : '';
    }
    return raw;
}

function isFieldValuePresent(def, values) {
    const value = getEffectiveFieldValue(def, values);
    if (def.inputType === 'number') {
        const n = String(value).replace(/[^\d.-]/g, '').trim();
        return n !== '' && n !== '-' && n !== '.';
    }
    return String(value).trim() !== '';
}

const isTwoWheelerProduct = (productType) => {
    const pt = (productType || '').trim().toLowerCase();
    if (!pt) {
        return false;
    }
    return pt === '2W' || pt === '2w';
};

export default class LoanTerms extends LightningElement {
    isLoading = true;
    selectedSchemeId = '';
    @track schemeOptions = [];
    schemesById = {};
    @track payInFieldValues = {};
    @track payOutFieldValues = {};
    productType = '';
    isBorrowerNonIndividual = false;
    showPayOut = false;
    finalTermId = null;
    assetId = null;

    @track showIntegrationModal = false;
    @track integrationStatus = 'loading';
    @track integrationCurrentStageIndex = 0;
    @track integrationStages = [];

    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api applicantId;
    @api fromAssetList = false;

    _applicationLineItemId = '';
    _isStagePast = false;
    _recordId;
    _loadSequence = 0;

    @api
    get applicationLineItemId() {
        return this._applicationLineItemId;
    }
    set applicationLineItemId(value) {
        this._applicationLineItemId = value || '';
        this.tryLoadData();
    }

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

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
    }

    connectedCallback() {
        this.tryLoadData();
    }

    tryLoadData() {
        if (!this._recordId) {
            return;
        }
        if (this.fromAssetList && !this._applicationLineItemId) {
            return;
        }
        this.loadData();
    }

    get isReadOnlyMode() {
        return this._isStagePast;
    }

    get stampingPaidByOptions() {
        return STAMPING_PAID_BY_OPTIONS;
    }

    get selectedSchemeLabel() {
        if (!this.selectedSchemeId) {
            return '-';
        }
        const opt = (this.schemeOptions || []).find((o) => o.value === this.selectedSchemeId);
        if (opt?.label) {
            return opt.label;
        }
        const scheme = this.schemesById?.[this.selectedSchemeId];
        if (scheme?.name) {
            const code = scheme.schemeCode || '';
            return code && code !== scheme.name ? `${scheme.name} (${code})` : scheme.name;
        }
        return this.selectedSchemeId;
    }

    get payInFieldRows() {
        return this.buildFieldRows(PAY_IN_FIELDS, this.payInFieldValues);
    }

    get payOutFieldRows() {
        return this.buildFieldRows(PAY_OUT_FIELDS, this.payOutFieldValues);
    }

    buildFieldRows(definitions, values) {
        let fieldRows = [];
        for (let def of definitions) {
            if(this.productType === 'PL' && def.key === 'tradeCertificate') {
                continue;
            }
            const raw = values?.[def.key];
            const value = raw == null || raw === '' ? (def.inputType === 'picklist' ? 'Bank' : '') : raw;
            fieldRows.push({
                ...def,
                value,
                displayValue: formatDisplayValue(value),
                isPicklist: def.inputType === 'picklist'
            });
        }
        return fieldRows;
    }

    get isNextDisabled() {
        if (this.isLoading) {
            return true;
        }
        if (this.isReadOnlyMode) {
            return false;
        }
        return this.getMissingMandatoryFieldLabels().length > 0;
    }

    get nextButtonClass() {
        return `p4-primary-btn p4-button-text${this.isNextDisabled ? ' stage-next-btn--disabled' : ''}`;
    }

    get isTwoWheelerApplication() {
        return isTwoWheelerProduct(this.productType);
    }

    logDebug(label, data) {
        // eslint-disable-next-line no-console
        console.log(`${LOG_PREFIX} ${label}`, data !== undefined ? data : '');
    }

    logError(label, error) {
        // eslint-disable-next-line no-console
        console.error(`${LOG_PREFIX} ${label}`, {
            message: error?.body?.message || error?.message,
            body: error?.body,
            stack: error?.stack,
            error
        });
    }

    buildSavePayload() {
        return {
            schemeId: this.selectedSchemeId || '',
            payIn: { ...this.payInFieldValues },
            payOut: { ...this.payOutFieldValues }
        };
    }

    async loadData() {
        if (!this.recordId) {
            this.logDebug('loadData skipped — no recordId');
            this.resetState();
            this.isLoading = false;
            return;
        }
        if (this.fromAssetList && !this._applicationLineItemId) {
            this.logDebug('loadData skipped — waiting for applicationLineItemId');
            return;
        }

        const loadSequence = ++this._loadSequence;
        this.resetState();
        this.isLoading = true;
        const request = {
            recordId: this.recordId,
            applicantId: this.applicantId || null,
            applicationLineItemId: this._applicationLineItemId || null
        };
        this.logDebug('loadData request', request);
        try {
            const response = await getLoanTermsData(request);
            if (loadSequence !== this._loadSequence) {
                this.logDebug('loadData ignored — stale response', { loadSequence });
                return;
            }
            this.logDebug('loadData response', response);
            this.applyServerResponse(response || {});
            const meta = response?.meta || {};
            this.productType = meta.productType || '';
            this.showPayOut = this.productType !== 'PL';
            this.isBorrowerNonIndividual = meta.isBorrowerNonIndividual === true;
            this.finalTermId = meta.finalTermId || null;
            this.assetId = meta.assetId || null;
            const schemeCount = this.schemeOptions.length;
            this.logDebug('loadData applied state', {
                applicationLineItemId: meta.applicationLineItemId,
                productType: this.productType,
                isTwoWheeler: this.isTwoWheelerApplication,
                selectedSchemeId: this.selectedSchemeId,
                schemeCount,
                payInFieldValues: this.payInFieldValues,
                payOutFieldValues: this.payOutFieldValues
            });
            if (schemeCount === 0) {
                this.showToast(
                    'No Schemes Available',
                    'No active schemes were found for this application. Please verify Schemes__c data in the org.'
                );
            }
        } catch (error) {
            if (loadSequence !== this._loadSequence) {
                return;
            }
            this.logError('loadData failed', error);
            const msg = error?.body?.message || error?.message || 'Unable to load loan terms data';
            this.showToast('Error', msg);
        } finally {
            if (loadSequence === this._loadSequence) {
                this.isLoading = false;
            }
        }
    }

    resetState() {
        this.selectedSchemeId = '';
        this.schemeOptions = [];
        this.schemesById = {};
        this.payInFieldValues = {};
        this.payOutFieldValues = {};
        this.productType = '';
        this.isBorrowerNonIndividual = false;
        this.finalTermId = null;
        this.assetId = null;
        this.showPayOut = false;
    }

    buildSchemeOptions(schemes = []) {
        return schemes
            .filter((scheme) => scheme?.id)
            .map((scheme) => {
                const name = scheme.name || '';
                const code = scheme.schemeCode || '';
                const label = code && code !== name ? `${name} (${code})` : name || code || scheme.id;
                return { label, value: scheme.id };
            })
            .sort((a, b) => a.label.localeCompare(b.label));
    }

    applyServerResponse(response) {
        const schemes = Array.isArray(response.schemes) ? response.schemes : [];
        this.schemesById = schemes.reduce((acc, scheme) => {
            if (scheme?.id) {
                acc[scheme.id] = scheme;
            }
            return acc;
        }, {});
        this.schemeOptions = this.buildSchemeOptions(schemes);

        this.selectedSchemeId = response.selectedSchemeId || '';

        const payIn = Array.isArray(response.payInSection) ? response.payInSection : [];
        const payOut = Array.isArray(response.payOutSection) ? response.payOutSection : [];
        this.payInFieldValues = this.extractFieldValues(payIn);
        this.payOutFieldValues = this.extractFieldValues(payOut);
    }

    extractFieldValues(fieldConfig = []) {
        return (fieldConfig || []).reduce((acc, field) => {
            acc[field.key] = field.value;
            return acc;
        }, {});
    }

    applySchemeTermsToForm(schemeId) {
        const scheme = this.schemesById[schemeId];
        if (!scheme) {
            this.logDebug('applySchemeTermsToForm — scheme not in cache', { schemeId });
            return;
        }
        this.payInFieldValues = {
            ...(scheme.payIn || {})
        };
        this.logDebug('applySchemeTermsToForm', {
            schemeId,
            schemeName: scheme.name,
            payInFieldValues: this.payInFieldValues
        });
    }

    handleSchemeChange(event) {
        if (this.isReadOnlyMode) {
            return;
        }
        const nextSchemeId = event.detail.value || '';
        const isChanged = String(nextSchemeId) !== String(this.selectedSchemeId || '');
        this.selectedSchemeId = nextSchemeId;
        this.logDebug('scheme changed', { nextSchemeId, isChanged });
        if (isChanged && nextSchemeId) {
            this.applySchemeTermsToForm(nextSchemeId);
        }
    }

    handlePayInFieldChange(event) {
        if (this.isReadOnlyMode) {
            return;
        }
        const key = event.currentTarget?.dataset?.key;
        if (!key) {
            return;
        }
        const value = event.detail?.value ?? event.currentTarget?.value ?? '';
        this.payInFieldValues = {
            ...this.payInFieldValues,
            [key]: value
        };
        this.logDebug(`payIn changed: ${key}`, value);
    }

    handlePayOutFieldChange(event) {
        if (this.isReadOnlyMode) {
            return;
        }
        const key = event.currentTarget?.dataset?.key;
        if (!key) {
            return;
        }
        const value = event.detail?.value ?? event.currentTarget?.value ?? '';
        this.payOutFieldValues = {
            ...this.payOutFieldValues,
            [key]: value
        };
        this.logDebug(`payOut changed: ${key}`, value);
    }

    async handleNextButton() {
        this.logDebug('Next clicked', {
            recordId: this.recordId,
            applicantId: this.applicantId,
            isReadOnlyMode: this.isReadOnlyMode,
            selectedSchemeId: this.selectedSchemeId,
            payInFieldValues: this.payInFieldValues,
            payOutFieldValues: this.payOutFieldValues
        });

        if (!this.recordId) {
            this.logDebug('Next aborted — recordId is missing');
            return;
        }
        if (this.isNextDisabled) {
            this.logDebug('Next aborted — validation not complete');
            return;
        }
        if (this.isReadOnlyMode) {
            this.logDebug('Next skipped save — read-only mode, navigating only');
            if (this.fromAssetList) {
                this.returnToAssetList(false);
                return;
            }
            this.dispatchNextStage();
            return;
        }

        const missingRequiredLabels = this.getMissingMandatoryFieldLabels();
        if (missingRequiredLabels.length > 0) {
            this.logDebug('Next aborted — missing required fields', missingRequiredLabels);
            this.showToast(
                'Missing Required Fields',
                `Please fill mandatory fields: ${missingRequiredLabels.join(', ')}`
            );
            return;
        }

        const payload = this.buildSavePayload();
        const saveRequest = {
            recordId: this.recordId,
            applicantId: this.applicantId || null,
            applicationLineItemId: this._applicationLineItemId || null,
            payloadJson: JSON.stringify(payload)
        };
        this.logDebug('saveLoanTermsData request', {
            ...saveRequest,
            payload
        });

        this.isLoading = true;
        window.dispatchEvent(
            new CustomEvent('losgloballoader', {
                detail: { show: true, message: 'Saving Loan Terms...' }
            })
        );
        let navigationDispatched = false;
        try {
            const response = await saveLoanTermsData(saveRequest);
            this.logDebug('saveLoanTermsData response', response);
            if (response?.isSuccess) {
                this.logDebug('save succeeded', {
                    applicationLineItemId: response.applicationLineItemId,
                    message: response.message
                });
                navigationDispatched = await this.invokeLoanTermsIntegrationsAndNavigate();
            } else {
                this.logDebug('save failed (server returned isSuccess=false)', {
                    message: response?.message,
                    response
                });
                this.showToast('Error', response?.message || 'Unable to save loan terms.');
            }
        } catch (error) {
            this.logError('saveLoanTermsData exception', error);
            const msg = error?.body?.message || error?.message || 'Error while saving loan terms';
            this.showToast('Error', msg);
        } finally {
            this.isLoading = false;
            if (navigationDispatched) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
                }, 1500);
            } else {
                window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
            }
        }
    }

    getIntegrationStagesForBorrower() {
        return this.isBorrowerNonIndividual
            ? NI_INTEGRATION_STAGES
            : this.productType === 'PL' ? PL_INTEGRATION_STAGES : IN_INTEGRATION_STAGES;
    }

    async invokeLoanTermsIntegrationsAndNavigate() {
        this._hideGlobalLoader();
        const stages = this.getIntegrationStagesForBorrower();
        this._openIntegrationModal(stages);
        for (let stageIndex = 0; stageIndex < stages.length; stageIndex += 1) {
            this.integrationCurrentStageIndex = stageIndex;
            await this._delay(INTEGRATION_STAGE_MIN_DURATION_MS);
        }

        this.integrationCurrentStageIndex = stages.length;
        await this._delay(INTEGRATION_STAGE_MIN_DURATION_MS);
        this.showIntegrationModal = false;

        if (this.fromAssetList) {
            this.returnToAssetList(true);
            return;
        }
        else{
            this.dispatchNextStage();
        }
        return true;
    }

    
    async _runOfferEngineApi() {
        this.offerEngineConfig = {
            recordId: this.recordId,
            applicantId: this.applicantId,
            selectedMethod: METHOD_DECLARED,
            currentScreen: 'Loan Terms',
            abbFlag: true,
            abbValue: null,
            productType: this.productType,
            totalFundedPremium: 0,
            installmentTypeValue: 'Monthly',
            assetId: this.assetId,
            finalTermId: this.finalTermId
        };

        try {
            return await invokeHandler('onOfferEngineApi', 'onOfferEngineApi', this);
        } catch (error) {
            return {
                isSuccess: false,
                message: error?.body?.message || error?.message || 'Failed to invoke Offer Engine API.'
            };
        }
    }

    _logOfferEngineResult(offerEngineApiResult) {
        this.logDebug('offerEngineApiResult', offerEngineApiResult);
        if (!offerEngineApiResult?.isSuccess) {
            this.logDebug('Offer Engine API failed (suppressed from UI)', {
                message: offerEngineApiResult?.message || 'Failed to invoke Offer Engine API.'
            });
        }
    }

    _openIntegrationModal(stages) {
        this.integrationStages = stages;
        this.integrationStatus = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.showIntegrationModal = true;
    }

    _hideGlobalLoader() {
        window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
    }

    _delay(ms) {
        return new Promise((resolve) => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(resolve, ms);
        });
    }

    dispatchNextStage() {
        window.dispatchEvent(
            new CustomEvent('losgloballoader', {
                detail: { show: true, message: 'Processing...' }
            })
        );
        this.dispatchEvent(
            new CustomEvent('losnextstage', {
                detail: {
                    currentViewId: this.currentViewId,
                    id: this.currentViewId,
                    applicantId: this.applicantId,
                    currentLoanStageComplete: this.tab || 'Loan Terms',
                    currentStagePhrase: this.stagePhrase || ''
                },
                bubbles: true,
                composed: true
            })
        );
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
        }, 1500);
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

    getMissingMandatoryFieldLabels() {
        const missing = [];
        if (!this.selectedSchemeId) {
            missing.push('Scheme');
        }
        if (!this.isReadOnlyMode) {
            for (const field of PAY_IN_FIELDS) {
                if(this.productType === 'PL' && field.key === 'tradeCertificate') {
                    continue;
                }
                if (!isFieldValuePresent(field, this.payInFieldValues)) {
                    missing.push(field.label);
                }
            }
            if(this.productType !== 'PL') {
                for (const field of PAY_OUT_FIELDS) {
                    if (!isFieldValuePresent(field, this.payOutFieldValues)) {
                        missing.push(field.label);
                    }
                }
            }
        }
        return missing;
    }

    showToast(title, message) {
        this.dispatchEvent(
            new CustomEvent('showtoast', {
                detail: { title, message },
                bubbles: true,
                composed: true
            })
        );
    }
}