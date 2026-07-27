import { LightningElement, api } from 'lwc';

export default class SearchableLookupDemo extends LightningElement {
    productOptions = [{'label': 'Select Product', 'value': ''}, { label: 'Two Wheeler', value: 'Two Wheeler' }, { label: 'Commercial Vehicle', value: 'Commercial Vehicle' }, { label: 'Passenger Vehicle', value: 'Passenger Vehicle' }];
    vehicleTypeOptions = [{'label': 'Select Vehicle Type', 'value': ''}, { label: 'New', value: 'New' }, { label: 'Refinance', value: 'Refinance' }, { label: 'Used', value: 'Used' }];
    selectedProduct = '';
    selectedVehicleType = '';
    selectedMakeCode = '';
    selectedModelCode = '';
    selectedVariantCode = '';

    handleProductChange(event) {
        this.selectedProduct = event.target.value;
        this.selectedMakeCode = '';
        const makePicker = this.getPickerBySearchField('Make__c');
        if (makePicker) {
            makePicker.getMakeList(this.selectedProduct);
        }
    }

    handleVehicleTypeChange(event) {
        this.selectedVehicleType = event.target.value;
    }

    handleSelectMake(event) {
        this.selectedMakeCode = event.detail?.value || '';
        this.selectedModelCode = '';
        this.selectedVariantCode = '';
        const modelPicker = this.getPickerBySearchField('Model__c');
        if (modelPicker) {
            modelPicker.getModelList(this.selectedProduct, this.selectedMakeCode);
        }
        const variantPicker = this.getPickerBySearchField('Variant__c');
        if (variantPicker) {
            variantPicker.getVariantList(this.selectedProduct, this.selectedMakeCode, this.selectedModelCode, this.selectedVehicleType);
        }
    }

    handleSelectModel(event) {
        this.selectedModelCode = event.detail?.value || '';
        this.selectedVariantCode = '';
        const variantPicker = this.getPickerBySearchField('Variant__c');
        if (variantPicker) {
            variantPicker.getVariantList(this.selectedProduct, this.selectedMakeCode, this.selectedModelCode, this.selectedVehicleType);
        }
    }

    handleSelectVariant(event) {
        this.selectedVariantCode = event.detail?.value || '';
    }

    getPickerBySearchField(searchFieldApiName) {
        const pickers = this.template.querySelectorAll('c-mmv-record-picker');
        return Array.from(pickers).find((picker) => picker.searchFieldApiName === searchFieldApiName);
    }
}