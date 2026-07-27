import { LightningElement, api } from 'lwc';
import searchRecords from '@salesforce/apex/SearchableLookupController.searchRecords';
export default class SearchableLookup extends LightningElement {
    @api searchObjectApiName;
    @api searchFieldApiName;
    @api returnFieldApiNameAsLabel;
    @api returnFieldApiNameAsValue;
    @api additionalFilter;
    @api isRequired = false;
    @api label;
    @api placeholder = 'Search...';

    searchTerm = '';
    searchOptions = [];
    isOpen = false;
    selectedOption = '';

    connectedCallback() {
        this.searchTerm = '';
        searchRecords({
            searchObjectApiName: this.searchObjectApiName,
            searchFieldApiName: this.searchFieldApiName,
            searchTerm: '',
            returnFieldApiNameAsLabel: this.returnFieldApiNameAsLabel,
            returnFieldApiNameAsValue: this.returnFieldApiNameAsValue,
            additionalFilter: this.additionalFilter
        })
        .then(data => {
            this.searchOptions = data;
            this.isOpen = true;
        })
        .catch(error => {
            console.error('Error searching records:', error);
        });
    }


    handleSearchTermInput(event) {
        const value = event.target.value;
        this.searchTerm = value;
        console.log('value', value);
        if(value !== undefined && value !== null && value !== '' && value.length > 3) {
            searchRecords({
                searchObjectApiName: this.searchObjectApiName,
                searchFieldApiName: this.searchFieldApiName,
                searchTerm: value,
                returnFieldApiNameAsLabel: this.returnFieldApiNameAsLabel,
                returnFieldApiNameAsValue: this.returnFieldApiNameAsValue,
                additionalFilter: this.additionalFilter
            })
            .then(data => {
                this.searchOptions = data;
                this.isOpen = true;
            })
            .catch(error => {
                console.error('Error searching records:', error);
            });
        }
        else {
            this.searchOptions = [];
            this.isOpen = true;
        }
    }

    handleLookupFocus() {
        this.isOpen = true;
    }

    handleQueryTypeLookupBlur() {
        setTimeout(() => {
            this.isOpen = false;
            if (this.selectedOption) {
                this.searchTerm = this.selectedOption;
            }
        }, 200);
    }

    handleSelectOption(event) {
        event.preventDefault();
        const value = event.currentTarget.dataset.value || '';
        const label = event.currentTarget.dataset.label || value;
        this.selectedOption = label;
        this.searchTerm = label;
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('select', { detail: { value, label } }));
    }

    handleLookupBlur() {
        this.handleQueryTypeLookupBlur();
    }
}