import { LightningElement, api, track } from 'lwc';

const VALID_INVALID_STAGES = [
    'Validating customer match...',
    'Updating customer records...'
];

const INVALID_STAGES = [
    'Marking customer as New-to-Bank...',
    'Generating customer code...'
];

export default class CustomerDedupeResultTable extends LightningElement {
    @api cardTitle = 'Customer Dedupe';
    @api cardSubtitle = 'Matching customer records';
    @api headerIcon = 'standard:people';
    @api isDedupChecking = false;
    @api recordId = '';
    @api applicantId = '';
    @api successMessage = '';
    @api isReadOnlyScreen = false;
    @api showCheckEligibility = false;
    @api handlerName = 'customerDedupeCheck';
    @api validationCompleteFromServer = false;

    @api checkEligibilityProcessing = false;
    @api checkEligibilityClicked = false;

    @track matchDisplayRows = [];

    _validInvalidClicked = false;
    _matches = [];
    _customerCode = '';
    _matchValidated = false;
    _validatedCifId = null;
    _confirmedValidCifId = null;
    _confirmedInvalid = false;
    _matchConfirmedInvalidProp = false;
    _invalidatedMatchCifIdProp = '';
    _integrationInProgress = false;
    _selectedCifId = null;

    @api
    get matchConfirmedInvalid() {
        return this._matchConfirmedInvalidProp;
    }
    set matchConfirmedInvalid(value) {
        this._matchConfirmedInvalidProp = !!value;
        if (this._matchConfirmedInvalidProp) {
            this._confirmedInvalid = true;
            this._confirmedValidCifId = null;
            this._validatedCifId = null;
        }
        this.refreshDisplayRows();
    }

    @api
    get invalidatedMatchCifId() {
        return this._invalidatedMatchCifIdProp;
    }
    set invalidatedMatchCifId(value) {
        this._invalidatedMatchCifIdProp = this.normalizeCif(value);
        if (this._invalidatedMatchCifIdProp) {
            this._confirmedInvalid = true;
            this._confirmedValidCifId = null;
            this._validatedCifId = null;
        }
        this.refreshDisplayRows();
    }

    @api
    get validInvalidClicked() {
        return this._validInvalidClicked;
    }
    set validInvalidClicked(value) {
        const wasClicked = this._validInvalidClicked;
        this._validInvalidClicked = !!value;
        if (wasClicked && !this._validInvalidClicked && !this.isValidationComplete) {
            this._validatedCifId = null;
            this._confirmedValidCifId = null;
            if (!this._matchConfirmedInvalidProp) {
                this._confirmedInvalid = false;
            }
        }
        this.refreshDisplayRows();
    }

    @api
    get matches() {
        return this._matches;
    }
    set matches(value) {
        this._matches = Array.isArray(value) ? [...value] : [];

        if (this.isInvalidConfirmedState()) {
            this.refreshDisplayRows();
            return;
        }

        if (this._customerCode) {
            const matched = this._matches.find(
                (m) => this.rowMatchesValidIdentifier(m, this._customerCode)
            );
            if (matched) {
                this._validatedCifId = this.resolveRowValidIdentifier(matched);
            }
        }

        this.refreshDisplayRows();
    }

    @api
    get customerCode() {
        return this._customerCode;
    }
    set customerCode(value) {
        this._customerCode = this.normalizeCif(value);

        if (this.isInvalidConfirmedState()) {
            this._confirmedValidCifId = null;
            this._validatedCifId = null;
            this.refreshDisplayRows();
            return;
        }

        if (!this._customerCode) {
            if (!this._matchValidated && !this._confirmedValidCifId) {
                this._validatedCifId = null;
            }
        } else {
            const matched = (this._matches || []).find(
                (m) => this.rowMatchesValidIdentifier(m, this._customerCode)
            );
            if (matched) {
                this._validatedCifId = this.resolveRowValidIdentifier(matched);
                this._confirmedValidCifId = this._validatedCifId;
                this._confirmedInvalid = false;
            }
        }

        this.refreshDisplayRows();
    }

    @api
    get matchValidated() {
        return this._matchValidated;
    }
    set matchValidated(value) {
        this._matchValidated = !!value;

        if (!this._matchValidated) {
            this._validatedCifId = null;
            this._confirmedValidCifId = null;
            this._confirmedInvalid = false;
        } else if (!this._validatedCifId && !this.isInvalidConfirmedState()) {
            if (this._confirmedValidCifId) {
                this._validatedCifId = this.normalizeCif(this._confirmedValidCifId);
            } else if (this._customerCode) {
                const matched = (this._matches || []).find(
                    (m) => this.rowMatchesValidIdentifier(m, this._customerCode)
                );
                if (matched) {
                    this._validatedCifId = this.resolveRowValidIdentifier(matched);
                }
            } else if (this._selectedCifId) {
                this._validatedCifId = this.normalizeCif(this._selectedCifId);
            }
        }

        this.refreshDisplayRows();
    }

    connectedCallback() {
        this.refreshDisplayRows();
    }

    get hasMatches() {
        return !this.isDedupChecking && this._matches.length > 0;
    }

    get noResults() {
        return !this.isDedupChecking && this._matches.length === 0;
    }

    get isValidationComplete() {
        return (
            this._matchValidated ||
            !!this._customerCode ||
            !!this._confirmedValidCifId ||
            this.isInvalidConfirmedState()
        );
    }

    get hasSelection() {
        if (this.isValidationComplete) {
            return !!this.resolveValidCifId(this._matches) || this.isInvalidConfirmedState();
        }
        return !!this._selectedCifId;
    }

    get isValidInvalidDisabled() {
        return (
            this.isReadOnlyScreen ||
            this.validationCompleteFromServer ||
            !this.hasSelection ||
            this.isValidationComplete ||
            this.isDedupChecking ||
            this._integrationInProgress
        );
    }

    /** Shared lock independent of selection state (read-only, complete, in-flight). */
    get isActionBaseDisabled() {
        return (
            this.isReadOnlyScreen ||
            this.validationCompleteFromServer ||
            this.isValidationComplete ||
            this.isDedupChecking ||
            this._integrationInProgress
        );
    }

    /** Radio model: Valid is available only when exactly one row is selected. */
    get isValidDisabled() {
        return this.isActionBaseDisabled || !this._selectedCifId;
    }

    /** Radio model: Invalid is available only when no row is selected. */
    get isInvalidDisabled() {
        return this.isActionBaseDisabled || !!this._selectedCifId;
    }

    @api
    get lastValidatedMatch() {
        return this._lastValidatedMatch;
    }

    @track _lastValidatedMatch = null;

    get validationButtonsDisabled() {
        return this.isValidInvalidDisabled;
    }

    get isCheckEligibilityDisabled() {
        return (
            this.isReadOnlyScreen ||
            !this.isValidationComplete ||
            this.checkEligibilityClicked ||
            this.checkEligibilityProcessing ||
            this.isDedupChecking ||
            this._integrationInProgress
        );
    }

    get isValidConfirmed() {
        return this.isValidationComplete
            && !this.isInvalidConfirmedState()
            && !!this.resolveValidCifId(this._matches);
    }

    get isInvalidConfirmed() {
        return this.isValidationComplete && this.isInvalidConfirmedState();
    }

    isInvalidConfirmedState() {
        return this._confirmedInvalid || this._matchConfirmedInvalidProp;
    }

    get validButtonClass() {
        let cls = 'action-btn action-valid';
        if (this.isValidDisabled && !this.isValidConfirmed) {
            cls += ' p4-primary-btn-disabled';
        }
        if (this.isValidConfirmed) {
            cls += ' action-valid--confirmed';
        }
        return cls;
    }

    get invalidButtonClass() {
        let cls = 'action-btn action-invalid';
        if (this.isInvalidDisabled && !this.isInvalidConfirmed) {
            cls += ' p4-primary-btn-disabled';
        }
        if (this.isInvalidConfirmed) {
            cls += ' action-invalid--confirmed';
        }
        return cls;
    }

    get checkEligibilityButtonClass() {
        return `p4-primary-btn p4-button-text${this.isCheckEligibilityDisabled ? ' p4-primary-btn-disabled' : ''}`;
    }

    normalizeCif(value) {
        return value == null ? '' : String(value).trim();
    }

    extractCifId(match) {
        if (!match || typeof match !== 'object') {
            return '';
        }
        return this.normalizeCif(
            match.cifId
            ?? match.CIFId
            ?? match.cifID
            ?? match.custId
            ?? match.customerId
            ?? ''
        );
    }

    extractCustomerCode(match) {
        if (!match || typeof match !== 'object') {
            return '';
        }
        return this.normalizeCif(
            match.customer_code__c
            ?? match.customerCode
            ?? match.Customer_Code__c
            ?? match.customer_code
            ?? ''
        );
    }

    resolveRowValidIdentifier(match) {
        const cifId = this.extractCifId(match);
        if (cifId) {
            return cifId;
        }
        return this.extractCustomerCode(match);
    }

    rowMatchesValidIdentifier(match, validId) {
        if (!validId) {
            return false;
        }
        return this.cifEquals(this.extractCustomerCode(match), validId)
            || this.cifEquals(this.extractCifId(match), validId);
    }

    cifEquals(a, b) {
        const left = this.normalizeCifForCompare(a);
        const right = this.normalizeCifForCompare(b);
        if (!left || !right) {
            return false;
        }
        return left === right;
    }

    normalizeCifForCompare(value) {
        const normalized = this.normalizeCif(value);
        if (!normalized) {
            return '';
        }
        const compact = normalized.replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
        if (compact.startsWith('CIF') && compact.length > 3) {
            return compact.substring(3);
        }
        return compact;
    }

    resolveValidCifId(sourceMatches) {
        if (this.isInvalidConfirmedState()) {
            return null;
        }

        if (this._validatedCifId) {
            return this.normalizeCif(this._validatedCifId);
        }

        const code = this.normalizeCif(this._customerCode);
        if (code) {
            const matched = (sourceMatches || []).find((m) => this.rowMatchesValidIdentifier(m, code));
            if (matched) {
                return this.resolveRowValidIdentifier(matched);
            }
            return null;
        }

        if (this._confirmedValidCifId) {
            return this.normalizeCif(this._confirmedValidCifId);
        }

        return null;
    }

    applyValidIntegrationSuccess(cifId, response) {
        this._integrationInProgress = false;
        this._confirmedValidCifId = cifId;
        this._confirmedInvalid = false;
        this._validatedCifId = cifId;
        this.refreshDisplayRows();
        this.dispatchEvent(
            new CustomEvent('matchvalidated', {
                detail: { cifId, actionType: 'valid' },
                bubbles: true,
                composed: true
            })
        );
        this.dispatchEvent(
            new CustomEvent('integrationcomplete', {
                detail: { ...(response || {}), actionType: 'valid' },
                bubbles: true,
                composed: true
            })
        );
    }

    applyInvalidIntegrationSuccess(cifId, response) {
        this._integrationInProgress = false;
        this._confirmedValidCifId = null;
        this._confirmedInvalid = true;
        this._validatedCifId = null;
        this._selectedCifId = null;
        this.refreshDisplayRows();
        this.dispatchEvent(
            new CustomEvent('matchvalidated', {
                detail: { cifId, actionType: 'invalid' },
                bubbles: true,
                composed: true
            })
        );
        this.dispatchEvent(
            new CustomEvent('integrationcomplete', {
                detail: { ...(response || {}), actionType: 'invalid' },
                bubbles: true,
                composed: true
            })
        );
    }

    resetIntegrationFailure() {
        this._integrationInProgress = false;
        this.refreshDisplayRows();
    }

    refreshDisplayRows() {
        const validated = this.isValidationComplete;
        const invalidConfirmed = this.isInvalidConfirmedState();
        const validCif = invalidConfirmed ? null : this.resolveValidCifId(this._matches);

        this.matchDisplayRows = this._matches.map((m, idx) => {
            const rowCif = this.extractCifId(m);
            const isValidMatch = !invalidConfirmed
                && !!(validCif && this.rowMatchesValidIdentifier(m, validCif));
            const isInvalidMatch = validated
                && (invalidConfirmed || (!!validCif && !isValidMatch));
            const isExact = Number(m.matchPercent) === 100;

            return {
                ...m,
                key: rowCif || `row-${idx}`,
                cifId: rowCif,
                isCheckboxMode: !validated,
                isValidMode: validated && isValidMatch,
                isInvalidMode: isInvalidMatch,
                selected: validated ? isValidMatch : this.cifEquals(rowCif, this._selectedCifId),
                matchBadgeClass: isExact
                    ? 'match-badge match-badge-exact'
                    : 'match-badge match-badge-partial',
                flagList: this._buildFlagList(m.flags)
            };
        });
    }

    _buildFlagList(flags) {
        if (!flags || typeof flags !== 'object') return [];
        return Object.keys(flags).map((label) => {
            const active = !!flags[label];
            return {
                key: label,
                label,
                active,
                className: active ? 'flag-chip flag-active' : 'flag-chip flag-inactive'
            };
        });
    }

    getSelectedCifId() {
        return this._selectedCifId;
    }

    toggleSelect(event) {
        if (this.isReadOnlyScreen || this.isValidationComplete) {
            return;
        }

        const id = this.normalizeCif(event.currentTarget.dataset.id);
        const shouldSelect = !!event.currentTarget.checked;
        this._selectedCifId = shouldSelect ? id : null;
        this.refreshDisplayRows();

        this.dispatchEvent(new CustomEvent('selectionchange', {
            detail: { selectedId: id, selected: shouldSelect },
            bubbles: true,
            composed: true
        }));
    }

    handleValidClick() {
        if (this.isValidDisabled) {
            return;
        }
        const cifId = this.getSelectedCifId();
        if (!cifId) {
            this.dispatchEvent(
                new CustomEvent('checkeligibilityvalidation', {
                    detail: { message: 'Select a customer match before marking Valid.' },
                    bubbles: true,
                    composed: true
                })
            );
            return;
        }
        this._confirmedInvalid = false;
        this._confirmedValidCifId = cifId;
        this._validatedCifId = cifId;
        this.refreshDisplayRows();
        this.dispatchEvent(
            new CustomEvent('matchvalidated', {
                detail: { cifId, actionType: 'valid', stages: VALID_INVALID_STAGES },
                bubbles: true,
                composed: true
            })
        );
    }

    handleInvalidClick() {
        if (this.isInvalidDisabled) {
            return;
        }
        const cifId = this.getSelectedCifId() || '';
        this._confirmedInvalid = true;
        this._confirmedValidCifId = null;
        this._validatedCifId = null;
        this.refreshDisplayRows();
        this.dispatchEvent(
            new CustomEvent('matchvalidated', {
                detail: { cifId, actionType: 'invalid', stages: INVALID_STAGES },
                bubbles: true,
                composed: true
            })
        );
    }

    handleCheckEligibility() {
        if (this.isCheckEligibilityDisabled) return;

        const cifId = (this.resolveValidCifId(this._matches) || this.getSelectedCifId() || '').trim();
        if (!cifId) {
            this.dispatchEvent(new CustomEvent('checkeligibilityvalidation', {
                detail: {
                    message: 'Select a customer match or mark Valid before checking eligibility.'
                },
                bubbles: true,
                composed: true
            }));
            return;
        }
        const stages = [
            'NPA Check',
            'Get CIBIL API',
            'BRE Check Eligibility API'
        ];
        this.dispatchEvent(new CustomEvent('checkeligibility', {
            detail: { cifId, stages },
            bubbles: true,
            composed: true
        }));
    }
}