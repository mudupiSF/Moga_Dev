import { LightningElement, api, track, wire } from 'lwc';
import getQueryDetails from '@salesforce/apex/EditQueryDetailsController.getQueryDetails';
import getQueryAttachments from '@salesforce/apex/EditQueryDetailsController.getQueryAttachments';
import getApplicationUsers from '@salesforce/apex/CreateQueryController.getApplicationUsers';
import getAllUsers from '@salesforce/apex/CreateQueryController.getAllUsers';
import getLoggedInUserSubordinates from '@salesforce/apex/EditQueryDetailsController.getLoggedInUserSubordinates';
import updateQuery from '@salesforce/apex/EditQueryDetailsController.updateQuery';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import QUERY_OBJECT from '@salesforce/schema/Query__c';
import STATUS_FIELD from '@salesforce/schema/Query__c.Status__c';
import CURRENT_USER_ID from '@salesforce/user/Id';

export default class EditQueryDetails extends LightningElement {
    @api recordId;
    @track queryDetails = {};
    @track statusOptions = [];
    @track attachments = [];
    @track availableUsers = [];
    isLoading = false;
    hasEditAccess = false;
    canEditAssignedTo = false;
    canEditOwner = false;
    isCommentEditable = false;
    showUserSelection = false;
    showAllUsers = false;
    showMySubordinates = false;
    managerLookupOpen = false;
    recordEditable = false;
    showReopenReasonField = false;
    editComments = '';
    editStatus = '';
    editAssignedTo = '';
    editAssignedToName = '';
    editReopenReason = '';
    queryComments = [];
    editOwnerId = '';
    editOwnerName = '';
    productFilter = '';
    managerFilter = '';
    managerSearchTerm = '';

    @wire(getObjectInfo, { objectApiName: QUERY_OBJECT })
    queryObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$queryObjectInfo.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wiredStatusValues({ data, error }) {
        if (data) {
            this.statusOptions = data.values.map((option) => ({
                label: option.label,
                value: option.value
            }));
        }
        else if (error) {
            this.statusOptions = [];
            this.showToast('Error', 'Unable to load Status picklist values.', 'error');
        }
    }

    get effectiveApplicationId() {
        return this.queryDetails?.applicationId || this.recordId || null;
    }

    get hasQueryComments() {
        return (this.queryComments || []).length > 0;
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

    connectedCallback() {
        this.loadQueryDetails();
    }

    get editableStatusOptions() {
        const assignedToStatuses = ['In Progress', 'Resolved', 'Rejected'];
        const ownerStatuses = [];
        if (this.queryDetails?.canReopen) ownerStatuses.push('Re-Open');
        if (this.queryDetails?.canEditStatusAsOwner) ownerStatuses.push('Closed');
        const canEditAsAssignedTo = this.queryDetails?.canEditStatusAsAssignedTo;
        const canEditAsOwner = this.queryDetails?.canEditStatusAsOwner;
        const allowed = [];

        // If user is both owner and assigned-to, prioritize owner transitions only.
        if (canEditAsOwner) {
            allowed.push(...ownerStatuses);
        }
        else if (canEditAsAssignedTo) {
            allowed.push(...assignedToStatuses);
        }
        const allowedSet = new Set(allowed);
        console.log('allowedSet: ' + JSON.stringify(allowedSet));
        return this.statusOptions.filter(o => allowedSet.has(o.value));
    }

    loadQueryDetails() {
        if (!this.recordId) return;
        this.isLoading = true;
        Promise.all([
            getQueryDetails({ queryId: this.recordId }),
            getQueryAttachments({ queryId: this.recordId })
        ])
        //getQueryDetails({ queryId: this.recordId })
        .then(([details, atts]) => {
            const status = details?.Status || '';
            this.queryDetails = details;
            this.editComments = details?.Comments || '';
            this.showReopenReasonField = status === 'Re-Open' && details?.canReopen ? true : false;
            this.editAssignedTo = details?.AssignedToId || '';
            this.editAssignedToName = details?.AssignedTo || '';
            this.editReopenReason = details?.ReOpenReason || '';
            this.queryComments = details?.queryComments || [];
            this.attachments = atts || [];
            this.isLoading = false;
            this.editOwnerId = details?.OwnerId || '';
            this.editOwnerName = details?.OwnerName || '';
            if(status === 'Closed') {
                this.canEditAssignedTo = false;
                this.canEditOwner = false;
                this.hasEditAccess = false;
                this.recordEditable = false;
            }
            else {
                this.canEditAssignedTo = details?.canEditAssignedTo;
                this.canEditOwner = details?.canEditOwner;
                this.hasEditAccess = CURRENT_USER_ID === this.editAssignedTo || CURRENT_USER_ID === this.editOwnerId;
                this.recordEditable = this.hasEditAccess || this.canEditAssignedTo || this.canEditOwner;
            }
        })
        .catch(e => {
            this.isLoading = false;
            this.showToast('Error', e.body?.message || e.message, 'error');
        });
    }

    handleCloseUserSelection() {
        this.showUserSelection = false;
        this.showAllUsers = false;
        this.showMySubordinates = false;
    }

    handleCommentsChange(event) {
        this.editComments = event.target.value;
    }

    handleManagerSearchInput(event) {
        const value = event.target.value || '';
        this.managerSearchTerm = value;
        this.managerLookupOpen = true;
        if (!value) {
            this.managerFilter = '';
        }
    }

    handleManagerLookupFocus() {
        this.managerLookupOpen = true;
    }

    handleManagerLookupBlur() {
        setTimeout(() => {
            this.managerLookupOpen = false;
            if (this.managerFilter) {
                this.managerSearchTerm = this.managerFilter;
            }
        }, 200);
    }

    handleProductFilterChange(event) {
        const value = event.detail.value || event.target.value;
        this.productFilter = value;
    }

    handleReopenReasonChange(event) {
        this.editReopenReason = event.target.value || '';
    }

    handleSelectUser(event) {
        const userId = event.currentTarget.dataset.userId || '';
        this.editAssignedTo = userId;
        this.editAssignedToName = this.availableUsers.find(user => user.userId === userId)?.userName || '';
        this.showUserSelection = false;
    }

    handleSelectManager(event) {
        event.preventDefault();
        const value = event.currentTarget.dataset.value || '';
        const label = event.currentTarget.dataset.label || value;
        this.managerSearchTerm = label;
        this.managerFilter = value;
        this.managerLookupOpen = false;
    }

    handleStatusChange(event) {
        this.editStatus = event.detail.value;
        this.showReopenReasonField = this.editStatus === 'Re-Open' && this.queryDetails?.canReopen ? true : false;
        this.editReopenReason = '';
        this.editComments = '';
        this.isCommentEditable = true;
    }

    handleUploadFinished() {
        if (this.queryDetails?.Id) {
            getQueryAttachments({ queryId: this.queryDetails.Id })
            .then(atts => {
                this.attachments = atts || [];
                this.showToast('Success', 'File was uploaded.', 'success');
            });
        }
    }

    async handleShowApplicationUsers() {
        if (!this.effectiveApplicationId) {
            this.showToast('Error', 'Application not found for this query', 'error');
            return;
        }
        this.isLoading = true;
        this.showAllUsers = false;
        await getApplicationUsers({ applicationId: this.effectiveApplicationId })
        .then(data => {
            this.availableUsers = data;
            if(this.availableUsers.length > 0) {
                this.showUserSelection = true;
            }
            else {
                this.showUserSelection = false;
                this.showToast('Info', 'No users found for the application', 'info');
            }
            this.isLoading = false;
        })
        .catch(e => {
            this.isLoading = false;
            this.showToast('Error', e.body?.message || e.message, 'error');
        });
    }

    async handleShowAllUsers() {
        this.isLoading = true;
        await getAllUsers()
        .then(data => {
            this.availableUsers = data;
            if(this.availableUsers.length > 0) {
                this.showUserSelection = true;
                this.showAllUsers = true;
            }
            else {
                this.showUserSelection = false;
                this.showAllUsers = false;
                this.showToast('Info', 'No users found', 'info');
            }
            this.isLoading = false;
        })
        .catch(error => {
            this.showUserSelection = false;
            this.showAllUsers = false;
            const errorMessage = error.body?.message || error.message || 'Error fetching users';
            this.showToast('Error', errorMessage, 'error');
            this.isLoading = false;
        });
    }

    async handleShowMySubordinates() {
        this.isLoading = true;
        this.subordinateSearchTerm = ''; // Reset search on open
        
        await getLoggedInUserSubordinates()
        .then(data => {
            this.availableUsers = data || [];
            if(this.availableUsers.length > 0) {
                this.showUserSelection = true;
                this.showMySubordinates = true;
                this.showAllUsers = false;
            }
            else {
                this.showUserSelection = false;
                this.showAllUsers = false;
                this.showToast('Info', 'No subordinates found', 'info');
            }
            this.isLoading = false;
        })
        .catch(e => {
            this.isLoading = false;
            this.showToast('Error', e.body?.message || e.message, 'error');
        });
    }

    handleClearAssignedTo() {
        this.editAssignedTo = '';
        this.editAssignedToName = '';
    }

    handleClearOwner() {
        this.editOwnerId = '';
        this.editOwnerName = '';
    }

    handleCancel() {
        const event = new CustomEvent('cancel');
        this.dispatchEvent(event);
    }

    handleSaveChanges() {
        let hasErrors = false;
        if(this.hasEditAccess) {
            if (this.editStatus === undefined || this.editStatus === null || this.editStatus === '') {
                hasErrors = true;
                this.showToast('Error', 'Status is required', 'error');
            }
            else if (this.editStatus === 'Re-Open' && (this.editReopenReason === undefined || this.editReopenReason === null || this.editReopenReason === '')) {
                hasErrors = true;
                this.showToast('Error', 'Re-Open Reason is required', 'error');
            }
        }
        if(this.recordEditable && !hasErrors) {
            this.isLoading = true;
            updateQuery({ 
                queryId: this.queryDetails.Id,
                assignedToId: this.editAssignedTo,
                ownerId: this.editOwnerId,
                status: this.editStatus,
                comments: this.editComments,
                reopenReason: this.editReopenReason
            })
            .then(() => {
                this.isLoading = false;
                this.showToast('Success', 'Query was updated.', 'success');
                this.handleCancel();
            })
            .catch(e => {
                this.isLoading = false;
                this.showToast('Error', e.body?.message || e.message, 'error');
            });
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}