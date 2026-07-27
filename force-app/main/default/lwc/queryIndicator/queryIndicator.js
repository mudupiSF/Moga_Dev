import { LightningElement, api, wire } from 'lwc';
import getExistingQueries from '@salesforce/apex/ExistingQueriesController.getExistingQueries';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import APPLICATION_STAGE_FIELD from '@salesforce/schema/Application__c.Stage__c';

export default class QueryIndicator extends LightningElement {
    @api recordId;
    /** 'fab' (default) for dock panel; 'header' for applicationOverview action bar */
    @api variant = 'fab';
    noOfQueries = 0;
    showQueriesNumber = false;
    showCreateQueryButton = false;

    @wire(getRecord, { recordId: '$recordId', fields: [APPLICATION_STAGE_FIELD] })
    wiredApplication({ data }) {
        if (data) {
            const applicationStatus = getFieldValue(data, APPLICATION_STAGE_FIELD) || '';
            this.showCreateQueryButton = applicationStatus === 'Credit Processing' || applicationStatus === 'Post Sanction Sales' || applicationStatus === 'Operations';
        }
    }

    async connectedCallback() {
        try {
            this.noOfQueries = 0;
            this.showQueriesNumber = false;
            const data = await getExistingQueries({ recordId: this.recordId });
            for(const query of data) {
                if(query.Status !== 'Closed') {
                    this.noOfQueries++;
                }
            }
            if(this.noOfQueries > 0) {
                this.showQueriesNumber = true;
            }
            else {
                this.showQueriesNumber = false;
            }
        }
        catch(e) {
            this.noOfQueries = 0;
            this.showQueriesNumber = false;
        }
    }

    handleViewQueriesClick() {
        this.dispatchEvent(new CustomEvent('viewqueries', { detail: { modalHeader: 'Existing Queries', componentName: 'existingQueries', componentProps: {} } }));
    }

    handleCreateQuery() {
        /*this.showDynamicModal = true;
        this.dynamicModalComponentName = 'createQuery';
        this.dynamicModalHeader = 'Create Query';
        this.dynamicModalComponentProps = {};*/
        this.dispatchEvent(new CustomEvent('createquery', {
            detail: {
                modalHeader: 'Create Query',
                componentName: 'createQuery',
                componentProps: {
                    applicationStatus: this.applicationStatus
                }
            }
        }));
    }

    get queriesIndicatorLabel() {
        return this.noOfQueries > 10 ? '10+' : String(this.noOfQueries);
    }

    get isHeaderVariant() {
        return this.variant === 'header';
    }

    get rootClass() {
        return this.isHeaderVariant ? 'query-indicator-actions' : 'query-indicator-root--fab';
    }

    get buttonClass() {
        return this.isHeaderVariant ? 'app-overview-icon-btn' : 'fab fab-queries';
    }

    get iconClass() {
        return this.isHeaderVariant ? 'app-overview-icon-btn-icon' : 'fab-icon';
    }

    get badgeClass() {
        return this.isHeaderVariant ? 'queries-indicator queries-indicator--header' : 'queries-indicator';
    }
}