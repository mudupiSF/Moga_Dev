import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getDataUpdateNeededFields from '@salesforce/apex/DataUpdateNeededController.getDataUpdateNeededFields';

const COLUMNS = [
    { 
        label: 'Field Label', 
        fieldName: 'fieldLabel', 
        type: 'text',
        sortable: true,
        wrapText: true
    },
    /*{ 
        label: 'Field Name', 
        fieldName: 'fieldName', 
        type: 'text',
        sortable: true,
        wrapText: true
    },*/
    { 
        label: 'Field Value', 
        fieldName: 'fieldValue', 
        type: 'text',
        wrapText: true
    },
    { 
        label: 'Comments', 
        fieldName: 'comments', 
        type: 'text',
        wrapText: true
    },
    { 
        label: 'Related Record', 
        fieldName: 'recordReferenceUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'lookupFieldName' },
            target: '_blank'
        }
    },
    { 
        label: 'Verified Date', 
        fieldName: 'verifiedDate', 
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        },
        sortable: true
    }
];

export default class DataUpdateNeeded extends NavigationMixin(LightningElement) {
    @api recordId; // Loan Application ID passed as parameter (from page context or URL)
    @track allData = []; // Store all data
    @track displayedData = []; // Data after filters
    @track error;
    @track isLoading = false;
    @track isMobile = false;
    
    // Internal application ID that gets resolved from either recordId or URL parameter
    _applicationId = null;
    
    // Return URL for navigation back to previous page
    returnUrl = null;
    
    // Filter values
    @track selectedApplicant = 'All';
    @track selectedAddress = 'All';
    @track selectedEmployment = 'All';
    @track selectedIncome = 'All';
    @track selectedProduct = 'All';
    @track selectedBank = 'All';
    
    // Filter options
    @track applicantOptions = [];
    @track addressOptions = [];
    @track employmentOptions = [];
    @track incomeOptions = [];
    @track productOptions = [];
    @track bankOptions = [];
    
    columns = COLUMNS;
    
    connectedCallback() {
        this.checkIfMobile();
        
        // Try to get recordId from URL parameters first
        this.parseUrlParameters();
        
        // If recordId is available (either from URL or page context), load data
        if (this.getApplicationId()) {
            this.loadData();
        }
        
        window.addEventListener('resize', this.handleResize.bind(this));
    }
    
    disconnectedCallback() {
        window.removeEventListener('resize', this.handleResize.bind(this));
    }
    
    /**
     * Parse URL parameters to get recordId and returnUrl
     * Supports formats like:
     * - /lightning/n/YourTabName?c__recordId=xxx&returnUrl=xxx
     * - /lightning/cmp/c__dataUpdateNeeded?c__recordId=xxx&returnUrl=xxx
     */
    parseUrlParameters() {
        try {
            const pageUrl = window.location.href;
            const urlParams = new URLSearchParams(window.location.search);
            
            // Check for recordId in different parameter formats
            const paramVariations = [
                'c__recordId',
                'recordId', 
                'c__applicationId',
                'applicationId',
                'id',
                'loanId'
            ];
            
            for (const param of paramVariations) {
                const value = urlParams.get(param);
                if (value) {
                    this._applicationId = value;
                    console.log('Loaded recordId from URL parameter:', param, '=', value);
                    break;
                }
            }
            
            // Parse returnUrl parameter
            const returnUrlParam = urlParams.get('returnUrl');
            if (returnUrlParam) {
                this.returnUrl = decodeURIComponent(returnUrlParam);
                console.log('Loaded returnUrl from URL parameter:', this.returnUrl);
            }
        } catch (error) {
            console.error('Error parsing URL parameters:', error);
        }
    }
    
    /**
     * Get the application ID from either recordId property or URL parameter
     */
    getApplicationId() {
        // Priority: URL parameter > recordId property
        return this._applicationId || this.recordId;
    }
    
    checkIfMobile() {
        const width = window.innerWidth;
        this.isMobile = width <= 768;
    }
    
    handleResize() {
        this.checkIfMobile();
    }
    
    @api
    set applicationId(value) {
        this._applicationId = value;
        if (value) {
            this.loadData();
        }
    }
    
    get applicationId() {
        return this.getApplicationId();
    }
    
    get hasData() {
        return this.displayedData && this.displayedData.length > 0;
    }
    
    get totalRecordCount() {
        return this.allData ? this.allData.length : 0;
    }
    
    get filteredRecordCount() {
        return this.displayedData ? this.displayedData.length : 0;
    }
    
    get showApplicantFilter() {
        return this.applicantOptions.length > 1;
    }
    
    get showAddressFilter() {
        return this.addressOptions.length > 1;
    }
    
    get showEmploymentFilter() {
        return this.employmentOptions.length > 1;
    }
    
    get showIncomeFilter() {
        return this.incomeOptions.length > 1;
    }
    
    get showProductFilter() {
        return this.productOptions.length > 1;
    }
    
    get showBankFilter() {
        return this.bankOptions.length > 1;
    }
    
    get isDesktop() {
        return !this.isMobile;
    }
    
    loadData() {
        this.isLoading = true;
        this.error = undefined;
        
        const appId = this.getApplicationId();
        
        if (!appId) {
            this.error = 'No Application ID provided. Please pass recordId as parameter.';
            this.isLoading = false;
            console.error('No Application ID found');
            return;
        }
        
        console.log('Loading data for Application ID:', appId);
        
        getDataUpdateNeededFields({ loanApplicationId: appId })
            .then(result => {
                console.log('Data received:', result);
                
                // Transform data for display
                this.allData = result.map(record => {
                    return {
                        ...record,
                        recordReferenceUrl: record.recordReference ? `/${record.recordReference}` : null
                    };
                });
                
                // Build filter options for each record type
                this.buildFilterOptions();
                
                // Apply filters
                this.applyFilters();
                
                this.isLoading = false;
                
                if (this.allData.length === 0) {
                    this.showToast('Info', 'No records found with status "Data Update Needed"', 'info');
                }
            })
            .catch(error => {
                console.error('Error loading data:', error);
                this.error = error.body ? error.body.message : error.message;
                this.isLoading = false;
                this.showToast('Error', this.error, 'error');
            });
    }
    
    buildFilterOptions() {
        const applicants = new Set();
        const addresses = new Set();
        const employments = new Set();
        const incomes = new Set();
        const products = new Set();
        const banks = new Set();
        
        this.allData.forEach(record => {
            if (record.applicantName) applicants.add(record.applicantName);
            if (record.addressName) addresses.add(record.addressName);
            if (record.employmentName) employments.add(record.employmentName);
            if (record.incomeName) incomes.add(record.incomeName);
            if (record.productName) products.add(record.productName);
            if (record.bankName) banks.add(record.bankName);
        });
        
        // Build applicant options
        this.applicantOptions = [{ label: 'All Applicants', value: 'All' }];
        Array.from(applicants).sort().forEach(name => {
            this.applicantOptions.push({ label: name, value: name });
        });
        
        // Build address options
        this.addressOptions = [{ label: 'All Addresses', value: 'All' }];
        Array.from(addresses).sort().forEach(name => {
            this.addressOptions.push({ label: name, value: name });
        });
        
        // Build employment options
        this.employmentOptions = [{ label: 'All Employments', value: 'All' }];
        Array.from(employments).sort().forEach(name => {
            this.employmentOptions.push({ label: name, value: name });
        });
        
        // Build income options
        this.incomeOptions = [{ label: 'All Incomes', value: 'All' }];
        Array.from(incomes).sort().forEach(name => {
            this.incomeOptions.push({ label: name, value: name });
        });
        
        // Build product options
        this.productOptions = [{ label: 'All Products', value: 'All' }];
        Array.from(products).sort().forEach(name => {
            this.productOptions.push({ label: name, value: name });
        });
        
        // Build bank options
        this.bankOptions = [{ label: 'All Banks', value: 'All' }];
        Array.from(banks).sort().forEach(name => {
            this.bankOptions.push({ label: name, value: name });
        });
    }
    
    applyFilters() {
        let filteredData = this.allData;
        
        // Apply applicant filter
        if (this.selectedApplicant !== 'All') {
            filteredData = filteredData.filter(record => 
                record.applicantName === this.selectedApplicant
            );
        }
        
        // Apply address filter
        if (this.selectedAddress !== 'All') {
            filteredData = filteredData.filter(record => 
                record.addressName === this.selectedAddress
            );
        }
        
        // Apply employment filter
        if (this.selectedEmployment !== 'All') {
            filteredData = filteredData.filter(record => 
                record.employmentName === this.selectedEmployment
            );
        }
        
        // Apply income filter
        if (this.selectedIncome !== 'All') {
            filteredData = filteredData.filter(record => 
                record.incomeName === this.selectedIncome
            );
        }
        
        // Apply product filter
        if (this.selectedProduct !== 'All') {
            filteredData = filteredData.filter(record => 
                record.productName === this.selectedProduct
            );
        }
        
        // Apply bank filter
        if (this.selectedBank !== 'All') {
            filteredData = filteredData.filter(record => 
                record.bankName === this.selectedBank
            );
        }
        
        // Add displayIndex (1-based) to each record for mobile card view
        this.displayedData = filteredData.map((record, index) => {
            return {
                ...record,
                displayIndex: index + 1
            };
        });
    }
    
    handleApplicantChange(event) {
        this.selectedApplicant = event.detail.value;
        this.applyFilters();
    }
    
    handleAddressChange(event) {
        this.selectedAddress = event.detail.value;
        this.applyFilters();
    }
    
    handleEmploymentChange(event) {
        this.selectedEmployment = event.detail.value;
        this.applyFilters();
    }
    
    handleIncomeChange(event) {
        this.selectedIncome = event.detail.value;
        this.applyFilters();
    }
    
    handleProductChange(event) {
        this.selectedProduct = event.detail.value;
        this.applyFilters();
    }
    
    handleBankChange(event) {
        this.selectedBank = event.detail.value;
        this.applyFilters();
    }
    
    handleRefresh() {
        this.loadData();
    }
    
    /**
     * Handle close/back button click - navigate back to previous page using returnUrl
     */
    handleClose() {
        if (this.returnUrl) {
            // Navigate to the returnUrl from the URL parameter
            const baseUrl = window.location.origin;
            const fullUrl = this.returnUrl.startsWith('http') ? this.returnUrl : `${baseUrl}${this.returnUrl}`;
            window.location.href = fullUrl;
        } else {
            // Fallback: Use browser history if returnUrl is not available
            if (window.history.length > 1) {
                window.history.back();
            }
        }
    }
    
    /**
     * Check if back button should be shown (when returnUrl is present)
     */
    get showBackButton() {
        return this.returnUrl != null && this.returnUrl.length > 0;
    }
    
    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        const cloneData = [...this.displayedData];
        
        cloneData.sort((a, b) => {
            let aVal = a[fieldName] ? a[fieldName] : '';
            let bVal = b[fieldName] ? b[fieldName] : '';
            
            if (sortDirection === 'asc') {
                return aVal > bVal ? 1 : -1;
            } else {
                return aVal < bVal ? 1 : -1;
            }
        });
        
        this.displayedData = cloneData;
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

}