import { LightningElement, api } from 'lwc';
import getExistingQueries from '@salesforce/apex/ExistingQueriesController.getExistingQueries';

export default class ApplicationDockPanel extends LightningElement {
    @api recordId;
    /** embedded-top-right: in parent layout. top-right or bottom-right: fixed to browser viewport. */
    @api dockVariant = 'bottom-right';

    showDynamicModal = false;
    dynamicModalComponentName = '';
    dynamicModalComponentProps = {};
    dynamicModalHeader = '';
    noOfQueries = 0;
    showQueriesNumberInFab = false;
    
    get isEmbeddedDock() {
        const v = String(this.dockVariant || 'bottom-right')
            .toLowerCase()
            .replace(/\s+/g, '');
        return v === 'embedded-top-right' || v === 'embeddedtopright';
    }

    get dockActionsClass() {
        return this.isEmbeddedDock
            ? 'dock-actions-right dock-actions-right_embedded-fixed'
            : 'dock-actions-right';
    }

    async connectedCallback() {
        try {
            this.noOfQueries = 0;
            this.showQueriesNumberInFab = false;
            const data = await getExistingQueries({ recordId: this.recordId });
            this.noOfQueries = data.length;
            if(this.noOfQueries > 0) {
                this.showQueriesNumberInFab = true;
            }
            else {
                this.showQueriesNumberInFab = false;
            }
        }
        catch(e) {
            this.noOfQueries = 0;
            this.showQueriesNumberInFab = false;
        }
    }

    handleUploadClick() {
        this.dynamicModalComponentName = 'embedCustomFilePreview';
        this.dynamicModalComponentProps = { mode: 'upload', enableAdhocAdd: true };
        this.dynamicModalHeader = 'Upload Documents';
        this.showDynamicModal = true;
    }

    handleViewClick() {
        this.dynamicModalComponentName = 'embedCustomFilePreview';
        this.dynamicModalComponentProps = { mode: 'preview' };
        this.dynamicModalHeader = 'View Documents';
        this.showDynamicModal = true;
    }


    handleCreateQueryClick(event) {
        const { modalHeader, componentName, componentProps } = event.detail;
        this.dynamicModalComponentName = componentName;
        this.dynamicModalComponentProps = componentProps;
        this.dynamicModalHeader = modalHeader;
        this.showDynamicModal = true;
    }

    handleViewQueriesClick(event) {
        const { modalHeader, componentName, componentProps } = event.detail;
        this.dynamicModalComponentName = componentName;
        this.dynamicModalComponentProps = componentProps;
        this.dynamicModalHeader = modalHeader;
        this.showDynamicModal = true;
    }

    handleDynamicModalClose() {
        this.showDynamicModal = false;
        this.dynamicModalComponentName = '';
        this.dynamicModalComponentProps = {};
    }

    handleDocumentUploadRequest(event) {
        this.dispatchEvent(
            new CustomEvent('documentuploadrequest', {
                detail: event.detail,
                bubbles: true,
                composed: true,
            }),
        );
    }

    get fabHostClass() {
        const v = String(this.dockVariant || 'bottom-right')
            .toLowerCase()
            .replace(/\s+/g, '');
        if (v === 'embedded-top-right' || v === 'embeddedtopright') {
            return 'fab-host fab-host_embedded-top-right';
        }
        if (v === 'top-right' || v === 'topright') {
            return 'fab-host fab-host_top-right';
        }
        return 'fab-host fab-host_bottom-right';
    }

    get queriesIndicatorLabel() {
        return this.noOfQueries > 10 ? '10+' : String(this.noOfQueries);
    }
}