import { LightningElement, api, track } from 'lwc';
import getMakeList from '@salesforce/apex/MmvRecordPickerController.getMakeList';
import getModelList from '@salesforce/apex/MmvRecordPickerController.getModelList';
import getVariantList from '@salesforce/apex/MmvRecordPickerController.getVariantList';

export default class MmvRecordPicker extends LightningElement {
    @api searchFieldApiName;
    @api placeholder = 'Select...';
    @api label;
    @api
    get value() {
        return this._value;
    }

    set value(v) {
        console.log('value123: ' + v);
        this._value = v || '';
        console.log('_value123: ' + this._value);
        this.searchTerm = this._value;
        console.log('searchTerm123: ' + this.searchTerm);
        if(this._value !== '' && this._value !== undefined && this._value !== null) {
            this.hasValue = true;
        }
        else {
            this.hasValue = false;
        }
    }

    @api isRequired = false;
    @track searchOptions = [];
    searchTerm = '';
    isOpen = false;
    hasValue = false;
    _value = '';

    @api 
    getMakeList(productType) {
        this.searchTerm = '';
        this.searchOptions = [];
        getMakeList({ productType: productType })
        .then(data => {
            this.searchOptions = data;
        });
    }

    @api
    getModelList(productType, makeCode) {
        this.searchTerm = '';
        this._value = '';
        this.hasValue = false;
        this.searchOptions = [];
        getModelList({ productType: productType, makeCode: makeCode })
        .then(data => {
            this.searchOptions = data;
        });
    }

    @api
    getVariantList(productType, makeCode, modelCode) {
        this.searchTerm = '';
        this._value = '';
        this.hasValue = false;
        this.searchOptions = [];
        getVariantList({ productType: productType, makeCode: makeCode, modelCode: modelCode })
        .then(data => {
            this.searchOptions = data;
        });
    }

    get filteredSearchOptions() {
        const options = this.searchOptions || [];
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term) return options;
        return options.filter(opt => (opt.label || '').toLowerCase().includes(term));
    }

    handleSearchTermInput(event) {
        const value = event.target.value || '';
        this.searchTerm = value;
        this._value = value;
        this.isOpen = true;
    }

    handleLookupFocus() {
        this.isOpen = true;
    }

    handleLookupBlur() {
        setTimeout(() => {
            this.isOpen = false;
        }, 200);
    }

    handleSelectOption(event) {
        event.preventDefault();
        const selectedValue = event.currentTarget.dataset.value || '';
        const selectedLabel = event.currentTarget.dataset.label || selectedValue;
        this.searchTerm = selectedLabel;
        this._value = selectedValue;
        this.hasValue = true;
        this.isOpen = false;
        if(this.searchFieldApiName === 'Make__c') {
            this.dispatchEvent(new CustomEvent('selectmake', { detail: { value: selectedValue, label: selectedLabel } }));
        }
        else if(this.searchFieldApiName === 'Model__c') {
            this.dispatchEvent(new CustomEvent('selectmodel', { detail: { value: selectedValue, label: selectedLabel } }));
        }
        else if(this.searchFieldApiName === 'Variant__c') {
            this.dispatchEvent(new CustomEvent('selectvariant', { detail: { value: selectedValue, label: selectedLabel } }));
        }
    }

    handleClearSelection() {
        this._value = '';
        this.searchTerm = '';
        this.hasValue = false;
        if(this.searchFieldApiName === 'Make__c') {
            this.dispatchEvent(new CustomEvent('selectmake', { detail: { value: '', label: '' } }));
        }
        else if(this.searchFieldApiName === 'Model__c') {
            this.dispatchEvent(new CustomEvent('selectmodel', { detail: { value: '', label: '' } }));
        }
        else if(this.searchFieldApiName === 'Variant__c') {
            this.dispatchEvent(new CustomEvent('selectvariant', { detail: { value: '', label: '' } }));
        }
    }
}