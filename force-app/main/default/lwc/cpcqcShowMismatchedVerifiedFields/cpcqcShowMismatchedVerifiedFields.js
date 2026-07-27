import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

const COLUMNS = [
    
    { 
        label: 'Record Name', 
        fieldName: 'recordNameLink', 
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'recordLabel' },
            target: '_self',
            tooltip: 'Click to view record'
        },
        sortable: true,
        wrapText: true
    },
    { 
        label: 'Field Label', 
        fieldName: 'fieldLabel', 
        type: 'text',
        cellAttributes: {
            class: { fieldName: 'fieldHighlightClass' }
        },
        sortable: true,
        wrapText: true
    },
    { 
        label: 'Field Value on Record', 
        fieldName: 'fieldValueOnRecord', 
        type: 'text',
        wrapText: true
    },
    { 
        label: 'Verified Value', 
        fieldName: 'verifiedValue', 
        type: 'text',
        wrapText: true
    },
    {
        label: 'Document Mismatch',
        fieldName: 'documentMismatchIndicator',
        type: 'text',
        initialWidth: 160,
        cellAttributes: {
            class: { fieldName: 'documentMismatchClass' },
            alignment: 'center'
        }
    },
    { 
        label: 'Timestamp of Verification', 
        fieldName: 'timestampOfVerification', 
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        },
        sortable: true
    },
    { 
        label: 'Related Record', 
        fieldName: 'lookupFieldName',
        type: 'text',
        sortable: true,
        wrapText: true
    }
];

export default class CpcqcShowMismatchedVerifiedFields extends NavigationMixin(LightningElement) {
    @api recordId; // Loan Application ID passed as parameter (from page context or URL)
    @track allData = []; // Store all data
    @track displayedData = []; // Data after filters
    @track error;
    @track isLoading = false;
    @track isMobile = false;
    
    // Internal application ID that gets resolved from either recordId or URL parameter
    _applicationId = null;
    
    // Mismatch data passed as JSON from parent component
    _mismatchDataJson = null;
    
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
        
        // Try to get recordId and mismatchData from URL parameters first
        this.parseUrlParameters();
        
        // If mismatchData is available, use it directly (no need to call Apex)
        if (this._mismatchDataJson) {
            this.processMismatchData();
        } else if (this.getApplicationId()) {
            // Fallback: If no mismatch data provided, try to load from Apex (for backward compatibility)
            this.loadData();
        }
        
        window.addEventListener('resize', this.handleResize.bind(this));
    }
    
    disconnectedCallback() {
        window.removeEventListener('resize', this.handleResize.bind(this));
    }
    
    /**
     * Parse URL parameters to get recordId, mismatchData, and returnUrl
     */
    parseUrlParameters() {
        try {
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
            
            // Parse mismatchData JSON parameter
            const mismatchDataParam = urlParams.get('c__mismatchData') || urlParams.get('mismatchData');
            if (mismatchDataParam) {
                try {
                    this._mismatchDataJson = decodeURIComponent(mismatchDataParam);
                    console.log('Loaded mismatch data from URL parameter');
                } catch (jsonError) {
                    console.error('Error parsing mismatch data JSON:', jsonError);
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
    
    /**
     * Process mismatch data from JSON parameter
     */
    processMismatchData() {
        this.isLoading = true;
        this.error = undefined;
        
        try {
            console.log('Processing mismatch data from JSON parameter');
            
            // Parse JSON string
            const mismatchData = JSON.parse(this._mismatchDataJson);
            
            console.log('Parsed mismatch data:', mismatchData.length, 'records');
            
            // Transform data for display
            this.allData = mismatchData.map(record => {
                const recordId = record.recordId;
                const recordLabel = record.recordLabel || 'Unnamed Record';
                
                // Build record URL for navigation - using NavigationMixin format
                // We'll use a relative URL that NavigationMixin can handle
                let recordNameLink = '#';
                if (recordId) {
                    const objectApiName = this.getObjectApiName(record.objectName);
                    // Use relative path that will be handled by NavigationMixin
                    recordNameLink = `/lightning/r/${objectApiName}/${recordId}/view`;
                }
                
                return {
                    id: record.id,
                    objectName: record.objectName,
                    recordId: recordId,
                    recordLabel: recordLabel,
                    recordNameLink: recordNameLink,
                    fieldLabel: record.fieldLabel,
                    fieldName: record.fieldName,
                    fieldValueOnRecord: record.fieldValueOnRecord || '',
                    verifiedValue: record.verifiedValue || '',
                    timestampOfVerification: record.timestampOfVerification || null, // May not be available
                    lookupFieldName: record.lookupFieldName || '',
                    recordReference: record.recordId,
                    hasMismatch: record.hasMismatch === true,
                    hasDocumentMismatch: record.hasDocumentMismatch === true,
                    documentMismatchIndicator: record.hasDocumentMismatch ? '⚠️' : '',
                    documentMismatchClass: record.hasDocumentMismatch ? 'slds-text-color_error slds-text-title_bold' : '',
                    fieldHighlightClass: record.hasMismatch ? 'slds-text-color_error slds-text-title_bold' : '',
                    fieldLabelClass: record.hasMismatch ? 'field-value slds-text-title_bold slds-text-color_error' : 'field-value slds-text-title_bold',
                    applicantName: record.sectionName && record.sectionName.includes('Applicant') ? record.recordLabel : null,
                    addressName: record.sectionName && record.sectionName.includes('Address') ? record.recordLabel : null,
                    employmentName: record.sectionName && record.sectionName.includes('Employment') ? record.recordLabel : null,
                    incomeName: record.sectionName && record.sectionName.includes('Income') ? record.recordLabel : null,
                    productName: record.sectionName && record.sectionName.includes('Product') ? record.recordLabel : null,
                    bankName: record.sectionName && record.sectionName.includes('Bank') ? record.recordLabel : null
                };
            });
            
            // Build filter options for each record type
            this.buildFilterOptions();
            
            // Apply filters
            this.applyFilters();
            
            this.isLoading = false;
            
            if (this.allData.length === 0) {
                this.showToast('Info', 'No mismatched fields found', 'info');
            }
        } catch (error) {
            console.error('Error processing mismatch data:', error);
            this.error = 'Error parsing mismatch data: ' + error.message;
            this.isLoading = false;
            this.showToast('Error', this.error, 'error');
        }
    }
    
    /**
     * Load data from Apex (fallback method for backward compatibility)
     */
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
        
        console.log('Loading mismatched fields for Application ID:', appId);
        this.showToast('Info', 'Please use the mismatch link from the Quality View page', 'info');
        this.isLoading = false;
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
    
    /**
     * Get object API name from object name (handles common object names)
     * This is used to build the correct record URL
     */
    getObjectApiName(objectName) {
        // Map common object names to their API names
        // Note: Most custom objects already have __c suffix, so we return as-is
        // Standard objects don't have __c suffix
        const objectMap = {
            'ResidentialLoanApplication': 'ResidentialLoanApplication__c',
            'LoanApplicant': 'LoanApplicant__c',
            'LoanApplicantAddress': 'LoanApplicantAddress__c',
            'LoanApplicantEmployment': 'LoanApplicantEmployment__c',
            'LoanApplicantIncome': 'LoanApplicantIncome__c',
            'LoanApplicationProperty': 'LoanApplicationProperty__c',
            'Bank_Detail__c': 'Bank_Detail__c',
            'LoanApplicationLiability': 'LoanApplicationLiability__c'
        };
        
        // Return mapped name or use the objectName as-is (it might already be the API name)
        return objectMap[objectName] || objectName;
    }
    
    /**
     * Handle record name click in mobile view
     */
    handleRecordNameClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const recordId = event.currentTarget.dataset.recordId;
        const objectName = event.currentTarget.dataset.objectName;
        
        if (recordId) {
            this.navigateToRecord(recordId, objectName);
        }
    }
    
    /**
     * Navigate to record page using NavigationMixin
     */
    navigateToRecord(recordId, objectName) {
        if (!recordId) {
            this.showToast('Error', 'Record ID not available', 'error');
            return;
        }
        
        const objectApiName = this.getObjectApiName(objectName);
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: objectApiName,
                actionName: 'view'
            }
        });
    }
}