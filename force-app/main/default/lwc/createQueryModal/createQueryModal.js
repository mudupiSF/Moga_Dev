import { api, track, wire } from 'lwc';
import getParentRecord from '@salesforce/apex/CreateQueryModalController.getParentRecord';
import getApplicants from '@salesforce/apex/CreateQueryModalController.getApplicants';
import getQueryTypes from '@salesforce/apex/CreateQueryModalController.getQueryTypes';
import getDocumentChecklistsForApplicant from '@salesforce/apex/CreateQueryModalController.getDocumentChecklistsForApplicant';
import getQuerySubTypes from '@salesforce/apex/CreateQueryModalController.getQuerySubTypes';
import getQueryDescription from '@salesforce/apex/CreateQueryModalController.getQueryDescription';
import getApplicationUsers from '@salesforce/apex/CreateQueryModalController.getApplicationUsers';
import getAllUsers from '@salesforce/apex/CreateQueryModalController.getAllUsers';
import createQuery from '@salesforce/apex/CreateQueryModalController.createQuery';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningModal from 'lightning/modal';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import QUERY_OBJECT from '@salesforce/schema/Query__c';
import PRIORITY_FIELD from '@salesforce/schema/Query__c.Priority__c';

export default class CreateQueryModal extends LightningModal {
    @api recordId;
    @track queryTypeOptions = [];
    @track querySubTypeOptions = [];
    @track applicantOptions = [];
    @track documentChecklistOptions = [];
    @track availableUsers = [];
    @track parentRecord = {};
    @track priorityOptions = [];
    isLoading = false;
    managerLookupOpen = false;
    queryTypeLookupOpen = false;
    querySubTypeLookupOpen = false;
    showUserSelection = false;
    showApplicationUsers = false;
    showAllUsers = false;
    showFileUpload = false;
    applicationId = '';
    assignedTo = '';
    assignedToUserName = '';
    managerSearchTerm = '';
    productFilter = '';
    managerFilter = '';
    queryDescription = '';
    queryTypeSearchTerm = '';
    querySubTypeSearchTerm = '';
    selectedQueryType = '';
    selectedQuerySubType = '';
    selectedPriority = '';
    selectedApplicant = '';
    selectedDocumentChecklist = '';

    @wire(getObjectInfo, { objectApiName: QUERY_OBJECT })
    queryObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$queryObjectInfo.data.defaultRecordTypeId',
        fieldApiName: PRIORITY_FIELD
    })
    wiredPriorityValues({ data, error }) {
        if (data) {
            this.priorityOptions = data.values.map((option) => ({
                label: option.label,
                value: option.value
            }));
        }
        else if (error) {
            this.priorityOptions = [];
            this.showToast(
                'Error',
                'Unable to load Priority picklist values.',
                'error'
            );
        }
    }
    
    connectedCallback() {
        this.resetData();
        this.loadParentRecord();
    }

    get filteredQueryTypeOptions() {
        const options = this.queryTypeOptions || [];
        const term = (this.queryTypeSearchTerm || '').trim().toLowerCase();
        if (!term) return options;
        return options.filter(opt => (opt.label || '').toLowerCase().includes(term));
    }

    get filteredQuerySubTypeOptions() {
        const options = this.querySubTypeOptions || [];
        const term = (this.querySubTypeSearchTerm || '').trim().toLowerCase();
        if (!term) return options;
        return options.filter(opt => (opt.label || '').toLowerCase().includes(term));
    }

    get documentChecklistHelpMessage() {
        return this.selectedApplicant
            ? 'Showing document checklists for the selected applicant.'
            : 'Showing document checklists for the application. Select an applicant to filter by applicant.';
    }

    get hasAssignedUser() {
        return this.assignedTo && this.assignedToUserName;
    }

    get hasUserSelectionFilters() {
        return this.productFilter || this.managerFilter || this.managerSearchTerm;
    }

    get productOptions() {
        if (!this.availableUsers || !Array.isArray(this.availableUsers)) {
            return [];
        }
        let products = [];
        for(let user of this.availableUsers) {
            if(user.product !== null && user.product !== undefined && user.product !== '') {
                if(user.product.includes(',')) {
                    let productList = user.product.split(',');
                    for(let product of productList) {
                        if(!products.includes(product.trim())) {
                            products.push(product.trim());
                        }
                    }
                }
                else {
                    if(!products.includes(user.product)) {
                        products.push(user.product);
                    }
                }
            }
        }
        return [{ label: 'All Products', value: '' }, ...products.map(p => ({ label: p, value: p }))];
    }

    get filteredManagerOptions() {
        if (!this.availableUsers || !Array.isArray(this.availableUsers)) {
            return [];
        }
        let managers = [];
        for(let user of this.availableUsers) {
            if(user.managerName !== null && user.managerName !== undefined && user.managerName !== '') {
                if(!managers.includes(user.managerName)) {
                    managers.push(user.managerName);
                }
            }
        }
        return [{ label: 'All Managers', value: '' }, ...managers.map(m => ({ label: m, value: m }))];
    }

    get filteredAvailableUsers() {
        if (!this.availableUsers || !Array.isArray(this.availableUsers)) {
            return [];
        }
        let rows = [];
        console.log('productFilter', this.productFilter);
        console.log('managerFilter', this.managerFilter);
        for(let user of this.availableUsers) {
            if(this.productFilter !== undefined && this.productFilter !== null && this.productFilter !== '') {
                if(this.managerFilter !== undefined && this.managerFilter !== null && this.managerFilter !== '') {
                    if( user.product.includes(this.productFilter)
                        && user.managerName.includes(this.managerFilter))
                    {
                        rows.push(user);
                    }
                }
                else {
                    if(user.product.includes(this.productFilter)) {
                        rows.push(user);
                    }
                }
            }
            else if(this.managerFilter !== undefined && this.managerFilter !== null && this.managerFilter !== '') {
                if(user.managerName.includes(this.managerFilter)) {
                    rows.push(user);
                }
            }
            else {
                rows.push(user);
            }
        }
        return rows;
    }

    loadApplicants() {
        if (!this.recordId) return;
        getApplicants({ applicationId: this.applicationId })
        .then(data => {
            this.applicantOptions = (data || []).map(o => ({ label: o.label, value: o.value }));
        })
        .catch(() => {
            this.applicantOptions = [];
        });
    }

    loadQueryTypes() {
        getQueryTypes({ applicationId : this.applicationId })
            .then(data => {
                if (data && data.length > 0) {
                    this.queryTypeOptions = data.map(queryType => {
                        return { label: queryType, value: queryType };
                    });
                }
                else {
                    this.queryTypeOptions = [];
                    this.showToast('Warning', 'No query types found for the current stage', 'warning');
                }
            })
            .catch(() => {
                this.showToast('Error', 'Error loading query types', 'error');
                this.queryTypeOptions = [];
            });
    }

    loadDocumentChecklists() {
        if (!this.recordId) return;
        this.selectedDocumentChecklist = '';
        if (this.selectedApplicant) {
            getDocumentChecklistsForApplicant({ applicantId: this.selectedApplicant })
                .then(data => {
                    this.documentChecklistOptions = (data || []).map(o => ({ label: o.label, value: o.value }));
                })
                .catch(() => {
                    this.documentChecklistOptions = [];
                });
        }
        /*else {
            getDocumentChecklistsForLoanApplication({ loanApplicationId: this.recordId })
                .then(data => {
                    this.documentChecklistOptions = (data || []).map(o => ({ label: o.label, value: o.value }));
                })
                .catch(() => {
                    this.documentChecklistOptions = [];
                });
        }*/
    }

    async loadParentRecord() {
        await getParentRecord({ recordId: this.recordId })
        .then(data => {
            this.parentRecord = data;
            this.applicationId = this.parentRecord.applicationId;
            this.loadQueryTypes();
            this.loadApplicants();
            this.loadDocumentChecklists();
        })
        .catch(() => {
            this.parentRecord = {};
        });
    }

    handleApplicantChange(event) {
        this.selectedApplicant = event.detail.value || '';
        this.loadDocumentChecklists();
    }

    handleDocumentChecklistChange(event) {
        this.selectedDocumentChecklist = event.detail.value || '';
    }

    handleQueryTypeChange(event) {
        this.selectedQueryType = event.detail.value;
        this.selectedQuerySubType = '';
        this.querySubTypeOptions = [];
        this.querySubTypeSearchTerm = '';
        this.querySubTypeLookupOpen = false;        
        if (this.selectedQueryType) {
            getQuerySubTypes({ 
                applicationId: this.applicationId, 
                queryType: this.selectedQueryType 
            })
            .then(data => {
                if (data && data.length > 0) {
                    this.querySubTypeOptions = data.map(querySubType => {
                        return { label: querySubType, value: querySubType };
                    });
                }
                else {
                    this.querySubTypeOptions = [];
                    this.showToast('Warning', 'No query sub types found for the selected query type', 'warning');
                }
            })
            .catch(() => {
                this.showToast('Error', 'Error loading query sub types', 'error');
                this.querySubTypeOptions = [];
            });
        }
    }

    handleInputChange(event) {
        const field = event.target.name || event.target.fieldName;
        const value = event.detail.value || event.target.value;
        
        if (field === 'description') {
            this.queryDescription = value;
        }
        else if (field === 'priority') {
            this.selectedPriority = value;
        }
    }

    handleProductFilterChange(event) {
        const value = event.detail.value || event.target.value;
        this.productFilter = value;
    }

    handleQuerySubTypeChange(event) {
        this.selectedQuerySubType = event.detail.value;
        
        if (this.selectedQueryType && this.selectedQuerySubType) {
            getQueryDescription({ 
                applicationId: this.applicationId,
                queryType: this.selectedQueryType,
                querySubType: this.selectedQuerySubType
            })
            .then(data => {
                if (data) {
                    this.queryDescription = data;
                }
            });
        }
    }

    handleQueryTypeLookupBlur() {
        setTimeout(() => {
            this.queryTypeLookupOpen = false;
            if (this.selectedQueryType) {
                this.queryTypeSearchTerm = this.selectedQueryType;
            }
        }, 200);
    }

    handleQuerySubTypeLookupBlur() {
        setTimeout(() => {
            this.querySubTypeLookupOpen = false;
            if (this.selectedQuerySubType) {
                this.querySubTypeSearchTerm = this.selectedQuerySubType;
            }
        }, 200);
    }

    handleManagerLookupBlur() {
        setTimeout(() => {
            this.managerLookupOpen = false;
            if (this.managerFilter) {
                this.managerSearchTerm = this.managerFilter;
            }
        }, 200);
    }

    handleQueryTypeLookupFocus() {
        this.queryTypeLookupOpen = true;
    }

    handleQuerySubTypeLookupFocus() {
        this.querySubTypeLookupOpen = true;
    }

    handleManagerLookupFocus() {
        this.managerLookupOpen = true;
    }

    handleQueryTypeSearchInput(event) {
        const value = event.target.value || '';
        this.queryTypeSearchTerm = value;
        this.queryTypeLookupOpen = true;
        if (!value) {
            this.selectedQueryType = '';
            this.selectedQuerySubType = '';
            this.querySubTypeOptions = [];
            this.querySubTypeSearchTerm = '';
            this.querySubTypeLookupOpen = false;
        }
    }

    handleQuerySubTypeSearchInput(event) {
        const value = event.target.value || '';
        this.querySubTypeSearchTerm = value;
        this.querySubTypeLookupOpen = true;
        if (!value) {
            this.selectedQuerySubType = '';
        }
    }

    handleManagerSearchInput(event) {
        const value = event.target.value || '';
        this.managerSearchTerm = value;
        this.managerLookupOpen = true;
        if (!value) {
            this.managerFilter = '';
        }
    }

    handleSelectManager(event) {
        event.preventDefault();
        const value = event.currentTarget.dataset.value || '';
        const label = event.currentTarget.dataset.label || value;
        this.managerSearchTerm = label;
        this.managerFilter = label;
        this.managerLookupOpen = false;
    }

    handleClearFilters() {
        this.managerFilter = '';
        this.productFilter = '';
        this.managerSearchTerm = '';
        this.managerLookupOpen = false;
    }

    handleSelectQueryTypeOption(event) {
        event.preventDefault();
        const value = event.currentTarget.dataset.value || '';
        const label = event.currentTarget.dataset.label || value;
        this.queryTypeSearchTerm = label;
        this.queryTypeLookupOpen = false;
        this.handleQueryTypeChange({ detail: { value } });
    }

    handleSelectQuerySubTypeOption(event) {
        event.preventDefault();
        const value = event.currentTarget.dataset.value || '';
        const label = event.currentTarget.dataset.label || value;
        this.querySubTypeSearchTerm = label;
        this.querySubTypeLookupOpen = false;
        this.handleQuerySubTypeChange({ detail: { value } });
    }

    handleClearApplicant() {
        this.selectedApplicant = '';
        this.loadDocumentChecklists();
    }

    handleClearDocumentChecklist() {
        this.selectedDocumentChecklist = '';
    }

    async handleShowApplicationUsers() {
        this.isLoading = true;
        await getApplicationUsers({ applicationId: this.parentRecord.applicationId })
        .then(data => {
            this.availableUsers = data;
            if(this.availableUsers.length > 0) {
                this.showUserSelection = true;
                this.showApplicationUsers = true;
                this.showAllUsers = false;
            }
            else {
                this.showUserSelection = false;
                this.showApplicationUsers = false;
                this.showAllUsers = false;
                this.showToast('Info', 'No users found for the application', 'info');
            }
            this.isLoading = false;
        })
        .catch(error => {
            this.showUserSelection = false;
            this.showApplicationUsers = false;
            this.showAllUsers = false;
            const errorMessage = error.body?.message || error.message || 'Error fetching users';
            this.showToast('Error', errorMessage, 'error');
            this.isLoading = false;
        });
    }

    async handleShowAllUsers() {
        this.isLoading = true;
        await getAllUsers()
        .then(data => {
            this.availableUsers = data;
            if(this.availableUsers.length > 0) {
                this.showUserSelection = true;
                this.showApplicationUsers = false;
                this.showAllUsers = true;
            }
            else {
                this.showUserSelection = false;
                this.showApplicationUsers = false;
                this.showAllUsers = false;
                this.showToast('Info', 'No users found', 'info');
            }
            this.isLoading = false;
        })
        .catch(error => {
            this.showUserSelection = false;
            this.showApplicationUsers = false;
            this.showAllUsers = false;
            const errorMessage = error.body?.message || error.message || 'Error fetching users';
            this.showToast('Error', errorMessage, 'error');
            this.isLoading = false;
        });
    }

    handleClearAssignedUser() {
        this.assignedTo = '';
        this.assignedToUserName = '';
    }

    handleSelectUser(event) {
        const userId = event.currentTarget.dataset.userId || '';
        this.assignedTo = userId;
        this.assignedToUserName = this.availableUsers.find(user => user.userId === userId)?.userName || '';
        this.showUserSelection = false;
    }

    handleCreateQuery() {
        // Validate required fields
        if (!this.selectedQueryType || !this.selectedQuerySubType) {
            this.showToast('Error', 'Please select Query Type and Query Sub Type', 'error');
            return;
        }
        
        if (this.showAssignedToSection && !this.assignedTo) {
            this.showToast('Error', 'Please select Assigned To', 'error');
            return;
        }
        
        if (!this.selectedPriority) {
            this.showToast('Error', 'Please select Priority', 'error');
            return;
        }
        this.isLoading = true;
        const queryData = {
            Application__c: this.applicationId,
            Description__c: this.queryDescription,
            Query_Type__c: this.selectedQueryType,
            Query_Sub_Type__c: this.selectedQuerySubType,
            Assigned_To__c: this.assignedTo,
            Priority__c: this.selectedPriority,
            Applicant__c: this.selectedApplicant || null,
            Document_Checklist__c: this.selectedDocumentChecklist || null
        };
        if(this.parentRecord.parentType === 'Asset__c') {
            queryData.Application_Line_Items__c = this.parentRecord.applicationLineItemId;
            queryData.Asset__c = this.parentRecord.parentId;
        }
        console.log('queryData', JSON.stringify(queryData));
        createQuery({ queryData: queryData })
        .then(result => {
            this.isLoading = false;
            if (result) {
                this.createdQueryId = result;
                this.showToast('Success', 'Query was created.', 'success');
                this.showFileUpload = true;
            }
            else {
                throw new Error('Failed to create query');
            }
        })
        .catch(error => {
            this.isLoading = false;
            this.showToast('Error', error.body?.message || error.message || 'Error creating query', 'error');
        });
    }

    handleCloseModal() {
        this.resetData();
        this.close();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    resetData() {
        this.showFileUpload = false;
        this.selectedQueryType = '';
        this.selectedQuerySubType = '';
        this.selectedPriority = '';
        this.selectedApplicant = '';
        this.selectedDocumentChecklist = '';
        this.assignedTo = '';
        this.assignedToUserName = '';
        this.queryDescription = '';
        this.queryTypeSearchTerm = '';
        this.querySubTypeSearchTerm = '';
    }
}