import { LightningElement, api } from 'lwc';
import searchRecords from '@salesforce/apex/MasterRecordSearchController.searchRecords';
import getDisplayLabelByValue from '@salesforce/apex/MasterRecordSearchController.getDisplayLabelByValue';
import {
    filterOptions,
    findOptionByValue,
    shouldShowMinLengthHint,
    isRemoteMode,
    MODE_STATIC
} from './picklistUtils';

const BLUR_DELAY_MS = 200;
const DEFAULT_DEBOUNCE_MS = 300;

export default class DynamicSearchablePicklist extends LightningElement {
    @api name;
    @api label;
    @api placeholder = 'Search...';
    @api disabled = false;
    @api mode = MODE_STATIC;
    @api searchConfigKey;
    @api searchContextJson;
    @api minSearchLength = 3;
    @api debounceMs = DEFAULT_DEBOUNCE_MS;
    @api noResultsMessage = 'No matching options found';
    @api minLengthHintMessage = 'Type at least 3 characters to search';
    @api loadingMessage = 'Searching...';
    @api customClass = '';
    @api trackSectionProgress = false;
    @api sectionRequired = false;
    @api sectionEditable = false;

    _value = '';
    _options = [];
    _remoteOptions = [];
    _selectedLabel = '';
    searchTerm = '';
    debouncedSearchTerm = '';
    isOpen = false;
    isLoading = false;
    activeIndex = -1;

    _blurTimer;
    _debounceTimer;
    _searchSequence = 0;

    @api
    get value() {
        return this._value;
    }

    set value(v) {
        const nextValue = v || '';
        const valueChanged = nextValue !== this._value;
        this._value = nextValue;

        if (!this.isOpen) {
            this.searchTerm = '';
            this.debouncedSearchTerm = '';
        }

        if (valueChanged && this.isRemote && nextValue && !this._selectedLabel) {
            this._resolveRemoteDisplayLabel();
        }
    }

    @api
    get options() {
        return this._options;
    }

    set options(v) {
        this._options = Array.isArray(v) ? v : [];
    }

    @api
    get selectedLabel() {
        return this._selectedLabel;
    }

    set selectedLabel(v) {
        this._selectedLabel = v || '';
    }

    get isRemote() {
        return isRemoteMode(this.mode);
    }

    get displayText() {
        if (this.isOpen) {
            return this.searchTerm;
        }
        if (this._selectedLabel) {
            return this._selectedLabel;
        }
        const match = findOptionByValue(this.activeOptionSource, this._value);
        return match ? match.label : '';
    }

    get activeOptionSource() {
        return this.isRemote ? this._remoteOptions : this._options;
    }

    get filteredOptions() {
        const source = this.isRemote
            ? this._remoteOptions
            : filterOptions(this._options, this.debouncedSearchTerm, this.minSearchLength);

        return source.map((opt, index) => ({
            ...opt,
            index,
            optionId: `dsp-option-${index}`,
            isSelected: opt.value === this._value,
            optionClass: this._optionClass(opt.value === this._value, index)
        }));
    }

    get hasNoResults() {
        if (!this.isOpen || this.isLoading || this.showMinLengthHint) {
            return false;
        }

        const term = (this.debouncedSearchTerm || '').trim();
        if (term.length < this.minSearchLength) {
            return false;
        }

        return this.filteredOptions.length === 0;
    }

    get showMinLengthHint() {
        if (!this.isOpen) {
            return false;
        }

        const term = this.isRemote ? this.searchTerm : this.debouncedSearchTerm;
        return shouldShowMinLengthHint(term, this.minSearchLength);
    }

    get showClearButton() {
        return !this.disabled && (!!this._value || !!this.searchTerm);
    }

    get rootClass() {
        return ['dsp-root', this.customClass].filter(Boolean).join(' ');
    }

    get sectionRequiredAttr() {
        return this.sectionRequired ? 'true' : 'false';
    }

    get sectionEditableAttr() {
        return this.sectionEditable ? 'true' : 'false';
    }

    get comboboxAriaActiveDescendant() {
        if (this.activeIndex < 0) {
            return null;
        }
        return `dsp-option-${this.activeIndex}`;
    }

    connectedCallback() {
        if (this.isRemote && this._value && !this._selectedLabel) {
            this._resolveRemoteDisplayLabel();
        }
    }

    _optionClass(isSelected, index) {
        const classes = ['dsp-option'];
        if (isSelected) {
            classes.push('dsp-option_selected');
        }
        if (index === this.activeIndex) {
            classes.push('dsp-option_active');
        }
        return classes.join(' ');
    }

    handleInput(event) {
        this.searchTerm = event.target.value || '';
        this.isOpen = true;
        this.activeIndex = -1;
        this._scheduleDebouncedSearch(this.searchTerm);
    }

    handleFocus() {
        this.isOpen = true;
        this.searchTerm = this.displayText;
        this.debouncedSearchTerm = this.searchTerm;
        this.activeIndex = -1;

        if (this.isRemote) {
            this._remoteOptions = [];
        }
    }

    handleBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._blurTimer = setTimeout(() => {
            this.isOpen = false;
            this.searchTerm = '';
            this.debouncedSearchTerm = '';
            this.activeIndex = -1;
            if (this.isRemote) {
                this._remoteOptions = [];
            }
        }, BLUR_DELAY_MS);
    }

    handleClear(event) {
        event.preventDefault();
        event.stopPropagation();
        this._clearBlurTimer();
        this.searchTerm = '';
        this.debouncedSearchTerm = '';
        this.isOpen = false;
        this.activeIndex = -1;
        this._selectedLabel = '';
        this._remoteOptions = [];
        this._emitChange('', '');
    }

    handleSelect(event) {
        event.preventDefault();
        const optionValue = event.currentTarget.dataset.value || '';
        const optionLabel = event.currentTarget.dataset.label || optionValue;
        this._clearBlurTimer();
        this.isOpen = false;
        this.searchTerm = '';
        this.debouncedSearchTerm = '';
        this.activeIndex = -1;
        this._selectedLabel = optionLabel;
        this._emitChange(optionValue, optionLabel);
    }

    handleKeydown(event) {
        if (this.disabled) {
            return;
        }

        const options = this.filteredOptions;

        if (event.key === 'ArrowDown') {
            event.preventDefault();
            this.isOpen = true;
            this.activeIndex = this._nextIndex(this.activeIndex, options.length);
            return;
        }

        if (event.key === 'ArrowUp') {
            event.preventDefault();
            this.isOpen = true;
            this.activeIndex = this._prevIndex(this.activeIndex, options.length);
            return;
        }

        if (event.key === 'Enter' && this.isOpen && this.activeIndex >= 0) {
            event.preventDefault();
            const selected = options[this.activeIndex];
            if (selected) {
                this._clearBlurTimer();
                this.isOpen = false;
                this.searchTerm = '';
                this.debouncedSearchTerm = '';
                this.activeIndex = -1;
                this._selectedLabel = selected.label;
                this._emitChange(selected.value, selected.label);
            }
            return;
        }

        if (event.key === 'Escape') {
            event.preventDefault();
            this._clearBlurTimer();
            this.isOpen = false;
            this.searchTerm = '';
            this.debouncedSearchTerm = '';
            this.activeIndex = -1;
            if (this.isRemote) {
                this._remoteOptions = [];
            }
        }
    }

    _scheduleDebouncedSearch(term) {
        if (this._debounceTimer) {
            clearTimeout(this._debounceTimer);
        }

        const delay = Number(this.debounceMs) || DEFAULT_DEBOUNCE_MS;

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => {
            this.debouncedSearchTerm = term;
            if (this.isRemote) {
                this._runRemoteSearch(term);
            }
        }, delay);
    }

    async _runRemoteSearch(term) {
        const normalized = (term || '').trim();
        if (normalized.length < this.minSearchLength) {
            this._remoteOptions = [];
            this.isLoading = false;
            return;
        }

        if (!this.searchConfigKey) {
            this._remoteOptions = [];
            return;
        }

        const requestId = ++this._searchSequence;
        this.isLoading = true;

        try {
            const results = await searchRecords({
                searchConfigKey: this.searchConfigKey,
                searchTerm: normalized,
                searchContextJson: this.searchContextJson || null
            });

            if (requestId !== this._searchSequence) {
                return;
            }

            this._remoteOptions = Array.isArray(results) ? results : [];
            this.dispatchEvent(
                new CustomEvent('searchcomplete', {
                    detail: {
                        searchTerm: normalized,
                        resultCount: this._remoteOptions.length,
                        name: this.name,
                        searchConfigKey: this.searchConfigKey
                    },
                    bubbles: true,
                    composed: true
                })
            );
        } catch (error) {
            if (requestId !== this._searchSequence) {
                return;
            }
            this._remoteOptions = [];
            this.dispatchEvent(
                new CustomEvent('searcherror', {
                    detail: {
                        message: error?.body?.message || error?.message || 'Search failed.',
                        name: this.name,
                        searchConfigKey: this.searchConfigKey
                    },
                    bubbles: true,
                    composed: true
                })
            );
        } finally {
            if (requestId === this._searchSequence) {
                this.isLoading = false;
            }
        }
    }

    async _resolveRemoteDisplayLabel() {
        if (!this.isRemote || !this._value || !this.searchConfigKey) {
            return;
        }

        try {
            const label = await getDisplayLabelByValue({
                searchConfigKey: this.searchConfigKey,
                fieldValue: this._value,
                searchContextJson: this.searchContextJson || null
            });
            if (label) {
                this._selectedLabel = label;
            }
        } catch (error) {
            // Parent may pass selectedLabel explicitly on edit screens.
        }
    }

    _nextIndex(current, length) {
        if (!length) {
            return -1;
        }
        if (current < 0) {
            return 0;
        }
        return current >= length - 1 ? 0 : current + 1;
    }

    _prevIndex(current, length) {
        if (!length) {
            return -1;
        }
        if (current < 0) {
            return length - 1;
        }
        return current <= 0 ? length - 1 : current - 1;
    }

    _emitChange(optionValue, optionLabel) {
        this._value = optionValue;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: {
                    value: optionValue,
                    label: optionLabel,
                    name: this.name
                },
                bubbles: true,
                composed: true
            })
        );
    }

    _clearBlurTimer() {
        if (this._blurTimer) {
            clearTimeout(this._blurTimer);
            this._blurTimer = null;
        }
    }

    disconnectedCallback() {
        this._clearBlurTimer();
        if (this._debounceTimer) {
            clearTimeout(this._debounceTimer);
        }
    }
}