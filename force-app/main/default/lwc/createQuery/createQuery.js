import { LightningElement, api, track, wire } from 'lwc';
import getParentRecord from '@salesforce/apex/CreateQueryController.getParentRecord';
import getApplicants from '@salesforce/apex/CreateQueryController.getApplicants';
import getQueryTypes from '@salesforce/apex/CreateQueryController.getQueryTypes';
import getApplicantDocumentChecklists from '@salesforce/apex/CreateQueryController.getApplicantDocumentChecklists';
import getApplicationDocumentChecklists from '@salesforce/apex/CreateQueryController.getApplicationDocumentChecklists';
import getQueryAttachments from '@salesforce/apex/EditQueryDetailsController.getQueryAttachments';
import deleteFile from '@salesforce/apex/CreateQueryController.deleteFile';
import getQuerySubTypes from '@salesforce/apex/CreateQueryController.getQuerySubTypes';
import getQueryDescription from '@salesforce/apex/CreateQueryController.getQueryDescription';
import getApplicationUsers from '@salesforce/apex/CreateQueryController.getApplicationUsers';
import getAllUsers from '@salesforce/apex/CreateQueryController.getAllUsers';
import createQuery from '@salesforce/apex/CreateQueryController.createQuery';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import QUERY_OBJECT from '@salesforce/schema/Query__c';
import PRIORITY_FIELD from '@salesforce/schema/Query__c.Priority__c';

export default class CreateQuery extends LightningElement {
    @api recordId;
    @track queryTypeOptions = [];
    @track querySubTypeOptions = [];
    @track applicantOptions = [];
    @track documentChecklistOptions = [];
    @track availableUsers = [];
    @track parentRecord = {};
    @track priorityOptions = [];
    @track attachments = [];
    isLoading = false;
    isApplicantPopulated = false;
    isDocumentChecklistPopulated = false;
    managerLookupOpen = false;
    queryTypeLookupOpen = false;
    querySubTypeLookupOpen = false;
    showUserSelection = false;
    showApplicationUsers = false;
    showAllUsers = false;
    showDocumentChecklists = false;
    hasQueryCreated = false;
    applicationId = '';
    assignedTo = '';
    assignedToUserName = '';
    managerSearchTerm = '';
    productFilter = '';
    managerFilter = '';
    queryId = '';
    queryNumber = '';
    queryDescription = '';
    queryTypeSearchTerm = '';
    querySubTypeSearchTerm = '';
    selectedQueryType = '';
    selectedQuerySubType = '';
    selectedPriority = '';
    selectedApplicant = '';
    selectedApplicantName = '';
    selectedDocumentChecklist = '';
    selectedDocumentChecklistName = '';

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
        const term = (this.managerSearchTerm || '').trim().toLowerCase();
        if (!term) return [{ label: 'All Managers', value: '' }, ...managers.map(m => ({ label: m, value: m }))];
        return [{ label: 'All Managers', value: '' }, ...managers.filter(m => m.toLowerCase().includes(term)).map(m => ({ label: m, value: m }))];
    }

    get filteredAvailableUsers() {
        if (!this.availableUsers || !Array.isArray(this.availableUsers)) {
            return [];
        }
        let rows = [];
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
        this.selectedDocumentChecklist = '';
        this.selectedDocumentChecklistName = '';
        if (this.selectedApplicant) {
            getApplicantDocumentChecklists({ applicantId: this.selectedApplicant })
            .then(data => {
                this.documentChecklistOptions = (data || []).map(o => ({ label: o.label, value: o.value }));
            })
            .catch(() => {
                this.documentChecklistOptions = [];
            });
        }
        else {
            getApplicationDocumentChecklists({ applicationId: this.applicationId })
            .then(data => {
                this.documentChecklistOptions = (data || []).map(o => ({ label: o.label, value: o.value }));
            })
            .catch(() => {
                this.documentChecklistOptions = [];
            });
        }
    }

    async loadParentRecord() {
        await getParentRecord({ recordId: this.recordId })
        .then(data => {
            this.parentRecord = data;
            console.log('parentRecord', JSON.stringify(this.parentRecord));
            if(this.parentRecord.parentType === 'Document_CheckList__c') {
                this.selectedDocumentChecklist = this.parentRecord.parentId;
                if(this.parentRecord.applicantId !== undefined && this.parentRecord.applicantId !== null && this.parentRecord.applicantId !== '') {
                    this.selectedApplicant = this.parentRecord.applicantId;
                    this.selectedApplicantName = this.parentRecord.applicantName;
                    this.isApplicantPopulated = true;
                }
                else {
                    this.selectedApplicant = '';
                    this.selectedApplicantName = '';
                    this.isApplicantPopulated = false;
                    this.loadApplicants();
                }
                this.isDocumentChecklistPopulated = true;
            }
            else {
                this.applicationId = this.parentRecord.applicationId;
                this.isDocumentChecklistPopulated = false;
                this.loadApplicants();
                this.loadDocumentChecklists();
            }
            this.applicationId = this.parentRecord.applicationId;
            this.loadQueryTypes();
        })
        .catch(() => {
            this.parentRecord = {};
        });
    }

    handleApplicantChange(event) {
        console.log('handleApplicantChange', JSON.stringify(event.detail.value));
        this.selectedApplicant = event.detail.value || '';
        this.selectedApplicantName = this.applicantOptions.find(o => o.value === this.selectedApplicant)?.label || '';
        console.log('selectedApplicantName', this.selectedApplicantName);
        if(this.selectedApplicant !== undefined && this.selectedApplicant !== null && this.selectedApplicant !== '') {
            this.showDocumentChecklists = true;
            this.loadDocumentChecklists();
        }
        else {
            this.showDocumentChecklists = false;
        }
    }

    handleDocumentChecklistChange(event) {
        this.selectedDocumentChecklist = event.detail.value || '';
        this.selectedDocumentChecklistName = this.documentChecklistOptions.find(o => o.value === this.selectedDocumentChecklist)?.label || '';
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
        this.managerFilter = value;
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
        this.showDocumentChecklists = false;
        this.selectedDocumentChecklist = '';
        this.selectedDocumentChecklistName = '';
    }

    handleClearDocumentChecklist() {
        this.selectedDocumentChecklist = '';
        this.selectedDocumentChecklistName = '';
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

    handleCloseUserSelection() {
        this.showUserSelection = false;
        this.showApplicationUsers = false;
        this.showAllUsers = false;
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
            this.showToast('Error', 'Select query type and query sub type', 'error');
            return;
        }
        
        if (this.assignedTo === undefined || this.assignedTo === null || this.assignedTo === '') {
            this.showToast('Error', 'Select assigned to', 'error');
            return;
        }
        
        if (!this.selectedPriority) {
            this.showToast('Error', 'Select priority', 'error');
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
        if(this.parentRecord.applicationLineItemId !== undefined && this.parentRecord.applicationLineItemId !== null && this.parentRecord.applicationLineItemId !== '') {
            queryData.Application_Line_Items__c = this.parentRecord.applicationLineItemId;
        }
        if(this.parentRecord.parentType === 'Asset__c') {
            queryData.Asset__c = this.parentRecord.parentId;
        }
        else if(this.parentRecord.parentType === 'Applicant_Employment__c') {
            queryData.Applicant_Employment__c = this.parentRecord.parentId;
        }
        else if(this.parentRecord.parentType === 'Applicant_Income__c') {
            queryData.Applicant_Income__c = this.parentRecord.parentId;
        }
        createQuery({ queryData: queryData })
        .then(result => {
            this.isLoading = false;
            if (result) {
                this.queryId = result.queryId;
                this.queryNumber = result.queryNumber;
                this.showToast('Success', 'Query was created.', 'success');
                this.hasQueryCreated = true;
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

    handleUploadFinished() {
        if (this.queryId) {
            getQueryAttachments({ queryId: this.queryId })
            .then(atts => {
                this.attachments = atts || [];
                this.showToast('Success', 'File was uploaded.', 'success');
            });
        }
    }

    handleDeleteFile(event) {
        const documentId = event.currentTarget.dataset.documentId;
        deleteFile({ contentDocumentId: documentId, queryId: this.queryId })
        .then(() => {
            this.attachments = this.attachments.filter(f => f.Id !== documentId);
            this.showToast('Success', 'File was deleted.', 'success');
        })
        .catch(error => {
            this.showToast('Error', error.body?.message || error.message || 'Error deleting file', 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    resetData() {
        this.hasQueryCreated = false;
        this.selectedQueryType = '';
        this.selectedQuerySubType = '';
        this.selectedPriority = '';
        this.selectedApplicant = '';
        this.selectedApplicantName = '';
        this.selectedDocumentChecklist = '';
        this.selectedDocumentChecklistName = '';
        this.showDocumentChecklists = false;
        this.assignedTo = '';
        this.assignedToUserName = '';
        this.queryDescription = '';
        this.queryTypeSearchTerm = '';
        this.querySubTypeSearchTerm = '';
    }
}