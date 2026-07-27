import { LightningElement, api } from 'lwc';

export default class StageMenuItem extends LightningElement {
    @api item;
    @api isTopLevel = false;
    @api activeTabId;
    @api index;

    get childIndex(){
        return parseInt(this.index) + 1;
    }
    get activeClass() {
        return this.parentItemStyle + ' ' + this.childIndentationClass;
    }

    get parentItemStyle() {
        const status = (this.item?.status || '').toLowerCase();
        const isCurrentView = this.item?.id === this.activeTabId;
        const isSubMenuItem = !!this.item?.applicantType;
        const isEnabled = status !== 'disabled' && !isCurrentView;

        // Sub-menu items (Borrower, Guarantor, Co-Borrower): completed, active, enabled, or disabled
        if (isSubMenuItem) {
            if (status === 'disabled') return 'disabled';
            if (status === 'completed') return isCurrentView ? 'completed active' : 'completed enabled';
            if (isCurrentView) return 'active';
            if (isEnabled) return 'enabled';
            return '';
        }

        // Main menu items
        if (status === 'active') return isCurrentView ? 'active' : 'enabled';
        if (status === 'disabled') return 'disabled';
        if (isCurrentView && !status) return 'active';
        if (isCurrentView) return 'visited';
        if (status === 'completed') return isCurrentView ? 'completed active' : 'completed enabled';
        if (isEnabled) return 'enabled';
        return '';
    }

    get isCompleted() {
        return this.item?.isCompleted === true;
    }

    get isCurrentStage() {
        return (this.item?.status || '').toLowerCase() === 'active';
    }

    /** True when item is enabled (clickable, not disabled) but not the active/current view */
    get isEnabled() {
        const status = (this.item?.status || '').toLowerCase();
        const isCurrentView = this.item?.id === this.activeTabId;
        return status !== 'disabled' && !isCurrentView && (status === 'active' || status === 'completed');
    }

    get childIndentationClass() {
        return `child-level-${this.index}`;
    }


    get subMenuItemClass() {
        return `sub-menu-item${this.item.subItems ? '' : ' third-level'}`;
    }

    get menuItemClass() {
        return this.isDisabled
            ? 'menu-item menu-item-disabled'
            : 'menu-item';
    }

    get isDisabled() {
        return this.item?.isDisabled === true;
    }

    get isMultiApplicantGroup() {
        // A group can legitimately hold a single applicant (e.g. one Non-Individual
        // co-applicant that owns Individual sub-applicants), so any grid-backed item
        // with at least one applicant qualifies for the back-to-grid (home) icon.
        return this.item?.isGroupItem === true && Array.isArray(this.item?.applicants) && this.item.applicants.length >= 1;
    }

    /** SUB toggle: add an IN sub-applicant under a single NI role applicant. */
    get showSubToggle() {
        return this.item?.showSubToggle === true;
    }
    get subToggleEnabled() {
        return this.item?.subToggleEnabled === true;
    }
    get subToggleClass() {
        return this.subToggleEnabled ? 'sub-toggle-btn on' : 'sub-toggle-btn off';
    }

    handleSubToggleClick(event) {
        event.preventDefault();
        event.stopPropagation();
        if (!this.subToggleEnabled) return;
        this.dispatchEvent(new CustomEvent('subtoggle', {
            detail: {
                parentApplicantId: this.item?.subParentApplicantId,
                baseStagePhrase: this.item?.subBaseStagePhrase || '',
                stagePhrase: this.item?.stagePhrase || '',
                tab: this.item?.tab || this.item?.label || '',
                label: this.item?.label || '',
                overrideLwc: this.item?.overrideLwc || '',
                // When set, the toggle jumps straight to this mid-edit sub instead of adding a new one.
                subInProgressId: this.item?.subInProgressId || null,
                subInProgressTabLabel: this.item?.subInProgressTabLabel || ''
            },
            bubbles: true,
            composed: true
        }));
    }

    get showHomeIcon() {
        if (!this.isMultiApplicantGroup) return false;
        const activeId = this.activeTabId || '';
        if (!activeId || activeId === this.item?.id) return false;
        return (this.item.applicants || []).some((a) => {
            const tabLabel = a?.tabLabel || '';
            return tabLabel ? activeId.includes(`_${tabLabel}_`) : false;
        });
    }

    connectedCallback() {
        if (this.item?.currentView === true && (!this.item.subItems || this.item.subItems.length === 0)) {
            this.dispatchEvent(new CustomEvent('menuselect', {
                detail: { item: this.item },
                bubbles: true,
                composed: true
            }));
        }
    }

    handleItemClick(event) {
        event.stopPropagation();
        if (this.isDisabled) return;

        // Leaf item (top-level with no submenu, or submenu item): fire menuselect and losmenuselect
        if (!this.item.subItems || this.item.subItems.length === 0) {
            this.dispatchEvent(new CustomEvent('menuselect', {
                detail: { item: this.item },
                bubbles: false,
                composed: true
            }));
        }
        // Parent with sub-items: dispatch toggle to expand/collapse
        else {
            this.dispatchEvent(new CustomEvent('toggle', {
                detail: { itemId: this.item.id, isTextClick: true },
                bubbles: true,
                composed: true
            }));
        }
    }


    handleChevronClick(event) {
        event.preventDefault();
        event.stopPropagation();

        // Dispatch toggle event for chevron click
        this.dispatchEvent(new CustomEvent('toggle', {
            detail: { itemId: this.item.id, isChevronClick: true },
            bubbles: true,
            composed: true
        }));
    }

    handleHomeClick(event) {
        event.preventDefault();
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('menuselect', {
            detail: { item: this.item },
            bubbles: true,
            composed: true
        }));
    }

    // These handlers just pass the events up from children
    handleMenuSelect(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('menuselect', { detail: event.detail, bubbles: false, composed: true }));
    }

    handleToggle(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('toggle', { detail: event.detail, bubbles: true, composed: true }));
    }
}