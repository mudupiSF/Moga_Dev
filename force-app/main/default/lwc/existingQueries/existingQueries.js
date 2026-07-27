import { LightningElement, api, track } from 'lwc';
import getExistingQueries from '@salesforce/apex/ExistingQueriesController.getExistingQueries';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';
import ID_FIELD from '@salesforce/schema/Query__c.Id';
import STATUS_FIELD from '@salesforce/schema/Query__c.Status__c';
import CURRENT_USER_ID from '@salesforce/user/Id';

export default class ExistingQueries extends LightningElement {
    
    @api recordId;
    @track queries = [];
    hasQueries = false;
    isLoading = false;
    showQueryDetails = false;
    selectedQueryId = '';

    connectedCallback() {
        this.selectedQueryId = '';
        this.loadQueries();
    }

    loadQueries() {
        this.isLoading = true;
        getExistingQueries({ recordId: this.recordId })
        .then(data => {
            this.queries = data || [];
            this.hasQueries = this.queries.length > 0;
            this.isLoading = false;
        })
        .catch(e => {
            this.hasQueries = false;
            this.isLoading = false;
            this.showToast('Error', e.body?.message || e.message, 'error');
        });
    }

    async handleQueryClick(event) {
        this.selectedQueryId = event.currentTarget.dataset.id;
        const query = this.queries.find(q => q.Id === this.selectedQueryId);
        if(query.AssignedToId === CURRENT_USER_ID && (query.Status === 'Open' || query.Status === 'Re-Open')) {
            const fields = {};
            fields[ID_FIELD.fieldApiName] = this.selectedQueryId;
            fields[STATUS_FIELD.fieldApiName] = 'In Progress';
            const recordInput = { fields };
            try {
                await updateRecord(recordInput);
                this.showQueryDetails = true;
            }
            catch (error) {
                this.showToast('Error', error.body?.message || error.message, 'error');
            }
        }
        else {
            this.showQueryDetails = true;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleCancel() {
        this.showQueryDetails = false;
        this.selectedQueryId = '';
        this.loadQueries();
    }
}