import { api, track } from 'lwc';
import LightningModal from 'lightning/modal';
import getQueryDetails from '@salesforce/apex/EditQueryModalController.getQueryDetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class EditQueryModal extends LightningModal {
    @api recordId;
    @track queryDetails = {};
    isLoading = false;
    editComments = '';
    editStatus = '';
    editAssignedTo = '';
    editAssignedToName = '';
    editReopenReason = '';
    queryComments = [];
    attachments = [];
    editOwnerId = '';
    editOwnerName = '';

    connectedCallback() {
        this.loadQueryDetails();
    }

    loadQueryDetails() {
        if (!this.recordId) return;
        this.isLoading = true;
        /*Promise.all([
            getQueryDetails({ queryId: this.recordId })//,
            //getQueryAttachments({ queryId: this.recordId })
        ])*/
        getQueryDetails({ queryId: this.recordId })
        .then(details => {
            this.queryDetails = details;
            this.editComments = details?.Comments || '';
            this.editStatus = details?.Status || '';
            this.editAssignedTo = details?.AssignedToId || '';
            this.editAssignedToName = details?.AssignedTo || '';
            this.editReopenReason = details?.ReOpenReason || '';
            this.queryComments = details?.queryComments || [];
            //this.attachments = atts || [];
            this.isLoading = false;
            this.editOwnerId = details?.OwnerId || '';
            this.editOwnerName = details?.OwnerName || '';
        })
        .catch(e => {
            this.isLoading = false;
            this.showToast('Error', e.body?.message || e.message, 'error');
        });
    }

    handleCloseModal() {
        this.close();
    }

    handleStatusChange(event) {
        this.editStatus = event.detail.value;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}