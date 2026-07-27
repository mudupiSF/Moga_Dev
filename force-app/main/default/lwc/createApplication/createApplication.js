import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFormOptions from '@salesforce/apex/CreateApplicationController.getFormOptions';
import createApplication from '@salesforce/apex/CreateApplicationController.createApplication';
import CreateApplicationIcons from '@salesforce/resourceUrl/CreateApplicationIcons';

const VEHICLE_TYPE_OPTIONS = [
    { label: 'New', value: 'New' },
    { label: 'Refinance', value: 'Refinance' }
];

const SEGMENT_OPTIONS = [
    { label: 'Motorcycle', value: 'MOTORCYC' },
    { label: 'Scooter', value: 'SCOOTER' },
    { label: 'Moped', value: 'MOPEDS' },
    { label: 'E-Scooter', value: 'ESCOOTER' },
    { label: 'Hi-Street', value: 'HISTREET' },
    { label: 'Hi-End', value: 'HIENDBIKE' }
];

const friendlyNameFor = (value, label) => {
    switch ((value || '').toUpperCase()) {
        case 'PL':
            return 'Personal Loan';
        case '2W':
            return 'Two Wheeler';
        case '4W':
            return 'Four Wheeler';
        case 'CV':
            return 'Commercial Vehicles';
        default:
            return label || value;
    }
};

const iconResourcePathFor = (value) => {
    switch ((value || '').toUpperCase()) {
        case '2W':
            return `${CreateApplicationIcons}/two-wheeler-vehicle.svg`;
        case '4W':
            return `${CreateApplicationIcons}/four-wheeler-vehicle.svg`;
        case 'CV':
            return `${CreateApplicationIcons}/commercial-vehicle.svg`;
        case 'PL':
            return `${CreateApplicationIcons}/personal-loan.svg`;
        default:
            return '';
    }
};

export default class CreateApplication extends NavigationMixin(LightningElement) {
    @track selectedProduct = '';
    @track selectedProductLabel = '';
    @track selectedVehicleType = '';
    @track selectedSegment = '';
    @track selectedSubProduct = '';

    @track productOptions = [];
    @track vehicleTypeOptions = [];
    @track segmentOptions = SEGMENT_OPTIONS;
    @track subProductDependencyMap = {};
    @track subProductOptions = [];
    @track showSubProduct = false;

    isLoadingOptions = true;
    isSubmitting = false;
    isFormValid = false;
    showVehicleType = false;
    @track errorMessage = '';

    connectedCallback() {
        this.loadFormOptions();
    }

    get showForm() {
        return !this.isLoadingOptions;
    }

    get showCascadingFields() {
        return !!this.selectedProduct;
    }

    get showSegmentSection() {
        return this.selectedProduct === '2W' && this.selectedVehicleType === 'New';
    }

    get resetButtonClass() {
        return this.selectedProduct ? 'ca-reset-btn' : 'ca-reset-btn ca-reset-hidden';
    }

    get confirmButtonClass() {
        return this.isFormValid ? 'ca-confirm-btn ca-confirm-active' : 'ca-confirm-btn';
    }

    get isConfirmDisabled() {
        return this.isSubmitting || !this.isFormValid;
    }

    get mappedProductOptions() {
        return (this.productOptions || []).map((opt) => ({
            ...opt,
            tileClass: this.selectedProduct === opt.value ? 'ca-rx-tile ca-rx-tile-selected' : 'ca-rx-tile',
            isSelected: this.selectedProduct === opt.value,
            imageUrl: iconResourcePathFor(opt.value),
            hasImageIcon: !!iconResourcePathFor(opt.value)
        }));
    }

    get mappedVehicleTypeOptions() {
        return this.vehicleTypeOptions.map((opt) => ({
            ...opt,
            itemClass: this.selectedVehicleType === opt.value ? 'ca-radio-card ca-radio-card-selected' : 'ca-radio-card',
            dotClass: this.selectedVehicleType === opt.value ? 'ca-radio-dot ca-radio-dot-on' : 'ca-radio-dot'
        }));
    }

    get mappedSegmentOptions() {
        return this.segmentOptions.map((opt) => ({
            ...opt,
            itemClass: this.selectedSegment === opt.value ? 'ca-radio-card ca-radio-card-selected' : 'ca-radio-card',
            dotClass: this.selectedSegment === opt.value ? 'ca-radio-dot ca-radio-dot-on' : 'ca-radio-dot'
        }));
    }

    get mappedSubProductOptions() {
        return this.subProductOptions.map((opt) => ({
            ...opt,
            itemClass: this.selectedSubProduct === opt.value ? 'ca-radio-card ca-radio-card-selected' : 'ca-radio-card',
            dotClass: this.selectedSubProduct === opt.value ? 'ca-radio-dot ca-radio-dot-on' : 'ca-radio-dot'
        }));
    }

    async loadFormOptions() {
        this.isLoadingOptions = true;
        this.errorMessage = '';
        try {
            const data = await getFormOptions();
            this.productOptions = (data?.productOptions || []).map((opt) => ({
                value: opt.value,
                label: friendlyNameFor(opt.value, opt.label),
                code: opt.value
            }));
            this.subProductDependencyMap = data?.subProductDependencyMap || {};
        }
        catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Failed to load form options. Please refresh and try again.';
        }
        finally {
            this.isLoadingOptions = false;
        }
    }

    handleProductSelect(event) {
        const { value, label } = event.currentTarget.dataset;
        this.selectedProduct = value;
        this.selectedProductLabel = label;
        this.selectedSubProduct = '';
        this.selectedVehicleType = '';
        this.selectedSegment = '';
        this.errorMessage = '';
        this.vehicleTypeOptions = [];
        this.applyProductRules(value);
        this.resolveSubProduct(value);
        this.validateForm();
    }

    handleVehicleTypeChange(event) {
        this.selectedVehicleType = event.currentTarget.dataset.value;
        if (this.selectedVehicleType !== 'New') {
            this.selectedSegment = '';
        }
        this.validateForm();
    }

    handleSegmentChange(event) {
        this.selectedSegment = event.currentTarget.dataset.value;
        this.validateForm();
    }

    handleSubProductSelect(event) {
        this.selectedSubProduct = event.currentTarget.dataset.value;
        this.errorMessage = '';
        this.validateForm();
    }

    handleReset() {
        this.selectedProduct = '';
        this.selectedProductLabel = '';
        this.selectedVehicleType = '';
        this.selectedSegment = '';
        this.selectedSubProduct = '';
        this.showSubProduct = false;
        this.subProductOptions = [];
        this.errorMessage = '';
        this.isFormValid = false;
    }

    handleCancel() {
        this.navigate({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Application__c',
                actionName: 'list'
            },
            state: { filterName: 'Recent' }
        });
    }

    async handleSubmit() {
        if (!this.validateForm()) {
            this.errorMessage = 'Please complete all required selections to continue.';
            return;
        }
        this.isSubmitting = true;
        this.errorMessage = '';
        try {
            await createApplication({
                product: this.selectedProduct,
                subProduct: this.selectedSubProduct || '',
                vehicleType: this.selectedVehicleType || '',
                segment: this.selectedSegment || ''
            })
            .then((result) => {
                if (result) {
                    this.isSubmitting = false;
                    this.navigate({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: result,
                            objectApiName: 'Application__c',
                            actionName: 'view'
                        }
                    });
                }
            })
            .catch((error) => {
                this.isSubmitting = false;
                this.errorMessage = error?.body?.message || error?.message || 'An unexpected error occurred. Please try again.';
            });
        }
        catch (error) {
            this.isSubmitting = false;
            this.errorMessage = error?.body?.message || error?.message || 'An unexpected error occurred. Please try again.';
        }
    }

    applyProductRules(productValue) {
        this.vehicleTypeOptions = [...VEHICLE_TYPE_OPTIONS];
        if(productValue === '2W' || productValue === '4W' || productValue === 'CV') {
            this.showVehicleType = true;
            this.selectedVehicleType = 'New';
            if(productValue === '4W' || productValue === 'CV') {
                const hasUsed = this.vehicleTypeOptions.some((opt) => opt.value === 'Used');
                if (!hasUsed) {
                    this.vehicleTypeOptions.push({ label: 'Used', value: 'Used' });
                }
            }
        }
        else {
            this.showVehicleType = false;
        }
    }

    resolveSubProduct(productValue) {
        const opts = this.subProductDependencyMap?.[productValue] || [];
        this.subProductOptions = opts;
        this.showSubProduct = opts.length > 0;
    }

    validateForm() {
        let valid = false;
        if (!this.selectedProduct) {
            valid = false;
        }
        else if (this.selectedProduct === 'PL') {
            valid = true;
        }
        else if (this.selectedProduct === '2W') {
            if (!this.selectedVehicleType) {
                valid = false;
            }
            else if (this.selectedVehicleType === 'New') {
                valid = !!this.selectedSegment;
            }
            else if (this.selectedVehicleType === 'Refinance') {
                valid = true;
            }
        }
        else {
            valid = true;
        }
        if (valid && this.showSubProduct && !this.selectedSubProduct) {
            valid = false;
        }
        this.isFormValid = valid;
        return valid;
    }

    navigate(pageRef) {
        this[NavigationMixin.Navigate](pageRef);
    }
}