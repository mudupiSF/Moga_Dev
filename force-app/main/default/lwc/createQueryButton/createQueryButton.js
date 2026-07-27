import { LightningElement, api } from 'lwc';

export default class CreateQueryButton extends LightningElement {
    @api recordId;
    showDynamicModal = false;
    dynamicModalComponentName = '';
    dynamicModalHeader = '';
    dynamicModalComponentProps = {};

    handleCreateQuery() {
        this.showDynamicModal = true;
        this.dynamicModalComponentName = 'createQuery';
        this.dynamicModalHeader = 'Create Query';
        this.dynamicModalComponentProps = {};
    }

    handleDynamicModalClose() {
        this.showDynamicModal = false;
    }
}