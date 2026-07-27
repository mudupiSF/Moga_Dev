import { LightningElement, api } from 'lwc';

export default class StageMenuItems extends LightningElement {
    @api recordId;
    @api activeTab;
    @api activeTabId;
    @api isCollapsed = false;
    @api menuSections = [];

    get menuContainerClass() {
        return 'menu-container';
    }

    handleMenuSelect(event) {
        event.preventDefault();
        event.stopPropagation();
        // Bubble up the event with its detail (bubbles/composed for shadow DOM)
        this.dispatchEvent(new CustomEvent('menuselect', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    handleToggle(event) {
        event.preventDefault();
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('toggle', {
            detail: event.detail
        }));
    }

    handleGroupHeaderClick(event) {
        const groupName = event.currentTarget.dataset.groupName;
        if (groupName) {
            this.dispatchEvent(new CustomEvent('grouptoggle', {
                detail: { groupName },
                bubbles: true,
                composed: true
            }));
        }
    }
}