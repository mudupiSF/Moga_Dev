import { LightningElement, api, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { wire } from 'lwc';
import getMenuForPortfolio      from '@salesforce/apex/dynamicStageNavigatorController.getMenuForPortfolio';
import processNextStageRequest  from '@salesforce/apex/dynamicStageNavigatorController.processNextStageRequest';

// #region agent log
function debugStageMenuLog(location, message, data, hypothesisId) {
    fetch('http://127.0.0.1:7938/ingest/4be970d2-c130-4bf4-a57b-c7fb436b25c2', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Debug-Session-Id': '61f25c' },
        body: JSON.stringify({
            sessionId: '61f25c',
            runId: 'pre-fix',
            hypothesisId,
            location,
            message,
            data,
            timestamp: Date.now()
        })
    }).catch(() => {});
}
// #endregion
import createSubApplicantShell  from '@salesforce/apex/ApplicantSubService.createSubApplicantShell';

const STATUS_ACTIVE    = 'active';
const STATUS_DISABLED  = 'disabled';
const STATUS_COMPLETED = 'completed';

const LOS_NEXT_STAGE_EVENT       = 'losnextstage';
const LOS_MENU_REFRESH_EVENT     = 'losmenurefresh';
const LOS_NAVIGATION_STATE_EVENT = 'losnavigationstate';

export default class StageMenu extends LightningElement {
    /** Record Id passed from the page (Application__c). */
    @api recordId;

    /** Explicit application Id override (takes precedence over recordId). */
    @api applicationId;

    /** Portfolio value used to filter Stage_Navigator__mdt records.
     *  e.g. 'Wheels', 'Personal Loan' */
    @api portfolio;

    @track menuItems    = [];
    @track menuSections = [];
    @track expandedMenuIds   = new Set();
    @track expandedGroupNames = new Set();
    @track activeTabId  = '';
    @track activeTab    = '';
    @track activeApplicantId  = '';
    @track selectedTabTitle   = '';

    isSpinner = false;
    @track isMenuCollapsed = false;

    _initialized = false;
    pageRef;

    // ── Computed helpers ──────────────────────────────────────────────────────

    get menuColumnClass() {
        return `slds-col slds-m-around_none ${this.isMenuCollapsed ? 'collapsed' : ''}`;
    }

    /** The Application__c Id to query.  Resolves through four fallbacks. */
    get effectiveAppId() {
        return (
            this.applicationId ||
            this.recordId      ||
            this.pageRef?.attributes?.recordId ||
            this.pageRef?.state?.recordId      ||
            this._recordIdFromUrl()
        );
    }

    _recordIdFromUrl() {
        try {
            const path  = window.location.pathname || '';
            const match = path.match(/\/r\/[^/]+\/([a-zA-Z0-9]{15,18})(?:\/|$)/);
            return match ? match[1] : null;
        } catch {
            return null;
        }
    }

    // ── Wire ──────────────────────────────────────────────────────────────────

    @wire(CurrentPageReference)
    wiredPageRef({ data }) {
        this.pageRef = data;
        if (data) {
            this.loadNavigationState();
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    _nextStageHandler;
    _menuRefreshHandler;
    _navigationStateHandler;

    async connectedCallback() {
        this.isMenuCollapsed = false;

        this._nextStageHandler       = this.handleNextStageRequest.bind(this);
        this._menuRefreshHandler     = this.handleMenuRefresh.bind(this);
        this._navigationStateHandler = this.handleNavigationState.bind(this);

        window.addEventListener(LOS_NEXT_STAGE_EVENT,       this._nextStageHandler);
        window.addEventListener(LOS_MENU_REFRESH_EVENT,     this._menuRefreshHandler);
        window.addEventListener(LOS_NAVIGATION_STATE_EVENT, this._navigationStateHandler);

        await this.loadNavigationState();
    }

    disconnectedCallback() {
        window.removeEventListener(LOS_NEXT_STAGE_EVENT,       this._nextStageHandler);
        window.removeEventListener(LOS_MENU_REFRESH_EVENT,     this._menuRefreshHandler);
        window.removeEventListener(LOS_NAVIGATION_STATE_EVENT, this._navigationStateHandler);
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    /** Applies navigation state dispatched by an external component (e.g. after dedupe). */
    handleNavigationState(event) {
        const { navigationState } = event.detail || {};
        if (navigationState?.menuItems) {
            this.applyNavigationState(navigationState);
        }
    }

    async handleMenuRefresh() {
        this._initialized = false;
        await this.loadNavigationState();
    }

    handleNextStageRequest(event) {
        const { currentViewId, currentStagePhrase, currentLoanStageComplete } = event.detail || {};
        const targetId = currentViewId;
        if (!targetId) return;

        let currentItem = this.findItemById(this.menuItems, targetId);
        if (!currentItem) {
            currentItem = this.buildItemFromDetailId(targetId);
        }
        if (!currentItem) {
            return;
        }

        // A found item with no usable status is treated as the active step rather than
        // silently swallowed — otherwise NEXT does nothing on a direct applicant switch.
        const effectiveStatus = this.getEffectiveStatus(currentItem) || STATUS_ACTIVE;
        if (effectiveStatus === STATUS_COMPLETED) {
            this.handlePastStageNext(targetId);
        } else {
            this.handleCurrentStageNext(targetId, currentItem, currentStagePhrase, currentLoanStageComplete);
        }
    }

    handlePastStageNext(currentId) {
        const nextItem = this.findNextSelectableItem(this.menuItems, currentId);
        if (nextItem) {
            this.navigateToItem(nextItem);
        }
    }

    async handleCurrentStageNext(id, currentItem, currentStagePhraseFromEvent, currentLoanStageComplete) {
        const appId = this.effectiveAppId;
        const stagePhrase = currentStagePhraseFromEvent
            || currentItem.stagePhrase
            || this.buildStagePhraseFromItem(currentItem);
        if (!appId || !stagePhrase) {
            return;
        }

        try {
            const result = await processNextStageRequest({
                applicationId       : appId,
                currentStagePhrase  : stagePhrase,
                currentLoanStageName: currentLoanStageComplete || null,
            });
            // #region agent log
            debugStageMenuLog('stageMenu.js:handleCurrentStageNext', 'processNextStageRequest result', {
                isSuccess: result?.isSuccess,
                message: result?.message,
                newStep: result?.newStep,
                preferredApplicantTabLabel: result?.preferredApplicantTabLabel,
                stagePhrase,
                currentLoanStageComplete
            }, 'D');
            // #endregion
            if (!result?.isSuccess || !result?.navigationState?.menuItems) return;

            const navState      = result.navigationState;
            const rawItems      = navState.menuItems;
            const nextViewItem  = this.findCurrentViewItem(rawItems);
            this.applyNavigationState(navState);

            // When Apex prefers a specific applicant tab (hint) and the resolved
            // currentView is a Multi-Grid container, dispatch a synthetic drill-down
            // so the content area loads the specific applicant immediately.
            if (this.shouldDispatchDrillDownForHint(nextViewItem, navState)) {
                this.dispatchDrillDownForHint(nextViewItem, navState);
                return;
            }
            if (nextViewItem) {
                this.dispatchMenuSelectEvent(nextViewItem);
            }
        } catch (error) {
            // Stage advancement failed silently; UI stays on current step.
        }
    }

    /** Returns true when Apex sent a preferred-applicant hint AND the resolved
     *  currentView item is a Multi-Grid group container. */
    shouldDispatchDrillDownForHint(currentViewItem, navState) {
        if (!currentViewItem || !navState?.preferredApplicantTabLabel) return false;
        if (!navState.preferredApplicantId) return false;
        return currentViewItem.isGroupItem === true;
    }

    /** Builds a synthetic drill-down losmenuselect event so the content area
     *  loads the specific applicant's component rather than the Multi-Grid default. */
    dispatchDrillDownForHint(groupItem, navState) {
        const tabLabel     = navState.preferredApplicantTabLabel;
        const applicantId  = navState.preferredApplicantId;
        const applicantName = navState.preferredApplicantName || '';
        const basePhrase   = (groupItem.stagePhrase || '')
            .replace(/_Guarantor$/, '')
            .replace(/_Co-Borrower$/, '')
            .replace(/_CoBorrower$/, '')
            .replace(/_Beneficiary$/, '');
        const drillStagePhrase = `${basePhrase}_${tabLabel}`;
        const drillId          = `${drillStagePhrase.replace(/\s+/g, '_')}_${applicantId}`;
        const tabValue         = groupItem.tab || groupItem.label;
        const labelValue       = applicantName
            ? `${tabValue} - ${tabLabel} (${applicantName})`
            : `${tabValue} - ${tabLabel}`;
        const applicantInfo = this._findApplicantInfo(groupItem.applicants, applicantId);
        const stepName = groupItem.tab || groupItem.label || '';
        const isStagePast = !!(
            applicantInfo?.currentLoanStageComplete
            && stepName
            && applicantInfo.currentLoanStageComplete.trim() === stepName.trim()
        );
        window.dispatchEvent(
            new CustomEvent('losmenuselect', {
                detail: {
                    tab               : tabValue,
                    id                : drillId,
                    label             : labelValue,
                    applicantId,
                    applicantType     : tabLabel,
                    applicantName,
                    isGroupItem       : false,
                    applicants        : [],
                    stagePhrase       : drillStagePhrase,
                    currentStagePhrase: drillStagePhrase,
                    isStagePast,
                    overrideLwc       : groupItem.overrideLwc || '',
                },
                bubbles : true,
                composed: true,
            })
        );
    }

    /** Finds an applicant info by id, recursing into nested IN sub-applicants. */
    _findApplicantInfo(applicants, applicantId) {
        for (const a of applicants || []) {
            if (a?.applicantId === applicantId) return a;
            const nested = this._findApplicantInfo(a?.subApplicants, applicantId);
            if (nested) return nested;
        }
        return null;
    }

    buildStagePhraseFromItem(item) {
        if (item?.stagePhrase) return item.stagePhrase;
        const parts = [item?.tab || item?.label];
        if (item?.applicantType) parts.push(item.applicantType);
        return parts.filter(Boolean).join('_');
    }

    handleMenuSelect(event) {
        const item = event.detail?.item ?? event.detail;
        if (!item || item.isDisabled) return;

        this.activeTabId       = item.id;
        this.activeTab         = item.tab || item.label;
        this.activeApplicantId = item.applicantId || '';
        this.selectedTabTitle  = this.buildSelectedTitle(item);

        this.menuItems    = this.processMenuItems(this.menuItems);
        this.menuSections = this.buildMenuSections(this.menuItems);
        this.dispatchMenuSelectEvent(item);
    }

    /** SUB toggle ON : jump to the mid-edit sub if one exists; otherwise create/reuse an IN sub shell. */
    async handleSubToggle(event) {
        const detail = event.detail || {};
        // A sub is already mid-edit → drill straight into it (no new shell, no pending tracking).
        if (detail.subInProgressId) {
            this.drillIntoSubBasicDetails(detail, detail.subInProgressId, detail.subInProgressTabLabel);
            return;
        }
        const parentApplicantId = detail.parentApplicantId;
        if (!parentApplicantId || this._creatingSub) return;
        this._creatingSub = true;
        try {
            const res = await createSubApplicantShell({ parentApplicantId });
            if (res?.isSuccess && res.subApplicantId) {
                await this.handleMenuRefresh();
                // Track the untouched shell only after the refresh (whose own menu-select would
                // otherwise look like a navigate-away) so it is discarded if abandoned later.
                window.__mogaPendingSubShellId = res.subApplicantId;
                this.drillIntoSubBasicDetails(detail, res.subApplicantId, res.tabLabel);
            }
        } catch (error) {
            // Sub-applicant creation failed silently; UI stays on the current view.
        } finally {
            this._creatingSub = false;
        }
    }

    /** Dispatches a synthetic drill-down so the content area opens the sub-applicant's Basic Details. */
    drillIntoSubBasicDetails(detail, subApplicantId, tabLabel) {
        const base = detail.baseStagePhrase
            || (detail.stagePhrase || '')
                .replace(/_Guarantor$/, '')
                .replace(/_Co-Borrower$/, '')
                .replace(/_CoBorrower$/, '')
                .replace(/_Beneficiary$/, '');
        const drillStagePhrase = `${base}_${tabLabel}`;
        const drillId          = `${drillStagePhrase}_${subApplicantId}`;
        const tabValue         = detail.tab || detail.label || '';

        this.activeTabId       = drillId;
        this.activeTab         = tabValue;
        this.activeApplicantId = subApplicantId;
        this.selectedTabTitle  = `${tabValue} - ${tabLabel}`;

        window.dispatchEvent(
            new CustomEvent('losmenuselect', {
                detail: {
                    id                : drillId,
                    tab               : tabValue,
                    label             : `${tabValue} - ${tabLabel}`,
                    applicantId       : subApplicantId,
                    applicantType     : tabLabel,
                    stagePhrase       : drillStagePhrase,
                    currentStagePhrase: drillStagePhrase,
                    isGroupItem       : false,
                    applicants        : [],
                    isStagePast       : false,
                    overrideLwc       : detail.overrideLwc || '',
                },
                bubbles : true,
                composed: true,
            })
        );
    }

    handleMenuToggle(event) {
        const { itemId } = event.detail;
        if (!itemId) return;

        if (this.expandedMenuIds.has(itemId)) {
            this.expandedMenuIds.delete(itemId);
        } else {
            this.expandedMenuIds = new Set([itemId]);
            const groupName = this.findGroupNameForItem(this.menuItems, itemId);
            this.expandedGroupNames = groupName ? new Set([groupName]) : new Set();
        }
        this.expandedMenuIds  = new Set(this.expandedMenuIds);
        this.menuItems        = this.processMenuItems(this.menuItems);
        this.menuSections     = this.buildMenuSections(this.menuItems);
    }

    handleGroupToggle(event) {
        const { groupName } = event.detail;
        if (!groupName) return;

        if (this.expandedGroupNames.has(groupName)) {
            this.expandedGroupNames.delete(groupName);
        } else {
            this.expandedGroupNames = new Set([groupName]);
            this.expandedMenuIds    = new Set();
        }
        this.expandedGroupNames = new Set(this.expandedGroupNames);
        this.menuSections = this.buildMenuSections(this.menuItems);
    }

    // ── Data loading ──────────────────────────────────────────────────────────

    async loadNavigationState() {
        const appId = this.effectiveAppId;

        if (!appId || this._initialized) return;

        this._initialized = true;
        this.isSpinner    = true;

        try {
            // portfolio is optional here – Apex derives it from Application__c.Product__c
            // when this.portfolio is not explicitly set on the component.
            const state = await getMenuForPortfolio({ portfolio: this.portfolio || null, applicationId: appId });
            if (state && state.isSuccess && state.menuItems) {
                this.applyNavigationState(state);
                const currentViewItem = this.findCurrentViewItem(state.menuItems || []);
                if (currentViewItem) {
                    this.dispatchMenuSelectEvent(currentViewItem);
                }
            }
        } catch (error) {
            console.error('Error loading navigation state:', error);
            // Navigation state load failed silently
        } finally {
            this.isSpinner = false;
        }
    }

    // ── Navigation state helpers ──────────────────────────────────────────────

    applyNavigationState(state) {
        const rawItems        = state.menuItems || [];
        const currentViewItem = this.findCurrentViewItem(rawItems);

        if (currentViewItem) {
            this.activeTabId       = currentViewItem.id;
            this.activeTab         = currentViewItem.tab || currentViewItem.label;
            this.activeApplicantId = currentViewItem.applicantId || '';
            this.selectedTabTitle  = this.buildSelectedTitle(currentViewItem);
        }

        this.expandedMenuIds    = this.collectExpandedIds(rawItems, currentViewItem);
        this.expandedGroupNames = this.collectExpandedGroupNames(rawItems, currentViewItem);
        this.menuItems          = this.processMenuItems(rawItems);
        this.menuSections       = this.buildMenuSections(this.menuItems);
    }

    findCurrentViewItem(items) {
        for (const item of items) {
            if (item.currentView) return item;
            if (item.subItems?.length) {
                const found = this.findCurrentViewItem(item.subItems);
                if (found) return found;
            }
        }
        return null;
    }

    navigateToItem(item) {
        this.activeTabId       = item.id;
        this.activeTab         = item.tab || item.label;
        this.activeApplicantId = item.applicantId || '';
        this.selectedTabTitle  = this.buildSelectedTitle(item);

        this.expandedMenuIds    = this.collectExpandedIds(this.menuItems, item);
        const groupName = this.findGroupNameForItem(this.menuItems, item.id);
        this.expandedGroupNames = groupName ? new Set([groupName]) : new Set();

        this.menuItems    = this.processMenuItems(this.menuItems);
        this.menuSections = this.buildMenuSections(this.menuItems);
        this.dispatchMenuSelectEvent(item);
    }

    // ── Menu processing ───────────────────────────────────────────────────────

    processMenuItems(items) {
        if (!items?.length) return [];

        return items.map((item) => {
            const isExpanded  = this.expandedMenuIds.has(item.id);
            const isDisabled  = item.status === STATUS_DISABLED;
            const isCompleted = item.status === STATUS_COMPLETED;
            const currentView = item.id === this.activeTabId;

            return {
                ...item,
                key: item.id,
                isHidden: false,
                isDisabled,
                isCompleted,
                currentView,
                expandIconName : item.subItems?.length ? (isExpanded ? 'utility:dash' : 'utility:add') : 'utility:add',
                isExpanded     : item.subItems?.length ? isExpanded : false,
                submenuClass   : item.subItems?.length ? `sub-menu ${isExpanded ? 'expanded' : 'collapsed'}` : null,
                subItems       : item.subItems?.length ? this.processMenuItems(item.subItems) : null,
            };
        });
    }

    buildMenuSections(processedItems) {
        if (!processedItems?.length) return [];

        const sections = [];
        let currentGroup = null;

        for (const item of processedItems) {
            const groupName = item.groupName?.trim() || null;

            if (!groupName) {
                if (currentGroup) {
                    sections.push(this._buildGroupSection(currentGroup));
                    currentGroup = null;
                }
                sections.push({ type: 'item', item, sectionKey: item.key, isItemSection: true, isGroupSection: false });
            } else {
                if (!currentGroup || currentGroup.name !== groupName) {
                    if (currentGroup) sections.push(this._buildGroupSection(currentGroup));
                    currentGroup = {
                        name      : groupName,
                        items     : [item],
                        isExpanded: this.expandedGroupNames.has(groupName),
                    };
                } else {
                    currentGroup.items.push(item);
                }
            }
        }
        if (currentGroup) sections.push(this._buildGroupSection(currentGroup));
        return sections;
    }

    _buildGroupSection(group) {
        const isExpanded      = group.isExpanded;
        const items           = group.items || [];
        const isActiveGroup   = items.some((it) => this._hasActiveStageInTree(it));
        const isGroupCompleted = items.length > 0 && items.every((it) => this._isFullyCompletedTree(it));

        const headerClasses = ['group-header'];
        if (isActiveGroup)    headerClasses.push('group-header-active');
        if (isGroupCompleted) headerClasses.push('group-header-completed');

        return {
            type             : 'group',
            sectionKey       : 'group-' + group.name,
            groupKey         : group.name,
            name             : group.name,
            items,
            isExpanded,
            isActiveGroup,
            isGroupCompleted,
            isItemSection    : false,
            isGroupSection   : true,
            groupHeaderClass : headerClasses.join(' '),
            groupChevronIcon : 'utility:chevronright',
            groupChevronClass: isExpanded ? 'group-chevron group-chevron-expanded' : 'group-chevron',
            groupContentClass: `group-content sub-menu ${isExpanded ? 'expanded' : 'collapsed'}`,
        };
    }

    _hasActiveStageInTree(item) {
        if (!item) return false;
        const status = (item.status || '').toLowerCase();
        if (status === STATUS_ACTIVE || status === STATUS_COMPLETED) return true;
        if (item.subItems?.length) {
            return item.subItems.some((s) => this._hasActiveStageInTree(s));
        }
        return false;
    }

    _isFullyCompletedTree(item) {
        if (!item) return false;
        if (item.subItems?.length) {
            return item.subItems.every((s) => this._isFullyCompletedTree(s));
        }
        return (item.status || '').toLowerCase() === STATUS_COMPLETED;
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    findItemById(items, targetId) {
        for (const item of items || []) {
            if (item.id === targetId) return item;
            const found = this.findItemById(item.subItems, targetId);
            if (found) return found;
        }
        return null;
    }

    getEffectiveStatus(item) {
        if (item.status) return item.status;
        const parent = this._findParentOfItem(this.menuItems, item.id);
        return parent ? parent.status : null;
    }

    _findParentOfItem(items, targetId, parent = null) {
        for (const item of items || []) {
            if (item.id === targetId) return parent;
            if (item.subItems?.length) {
                const found = this._findParentOfItem(item.subItems, targetId, item);
                if (found !== undefined) return found;
            }
        }
        return undefined;
    }

    buildItemFromDetailId(detailId) {
        if (!detailId || typeof detailId !== 'string') return null;
        const sfIdMatch  = detailId.match(/_([a-zA-Z0-9]{15,18})$/);
        const stagePhrase = sfIdMatch ? detailId.slice(0, -sfIdMatch[1].length - 1) : detailId;
        return { id: detailId, stagePhrase };
    }

    _buildSelectableItemsList(items, acc = []) {
        for (const item of items || []) {
            if (item.subItems?.length > 0) {
                for (const sub of item.subItems) {
                    if (sub.status !== STATUS_DISABLED) acc.push(sub);
                }
            } else {
                if (item.status !== STATUS_DISABLED) acc.push(item);
            }
        }
        return acc;
    }

    findNextSelectableItem(items, currentId) {
        const flat = this._buildSelectableItemsList(items);
        const idx  = flat.findIndex((it) => it.id === currentId);
        if (idx < 0 || idx >= flat.length - 1) return null;
        return flat[idx + 1];
    }

    collectExpandedIds(items, currentViewItem) {
        const ids = new Set();
        if (!currentViewItem) return ids;

        const expandAncestorsOf = (list, targetId) => {
            for (const item of list) {
                if (item.id === targetId) return true;
                if (item.subItems?.length) {
                    if (expandAncestorsOf(item.subItems, targetId)) {
                        ids.add(item.id);
                        return true;
                    }
                }
            }
            return false;
        };

        expandAncestorsOf(items, currentViewItem.id);
        ids.add(currentViewItem.id);
        return ids;
    }

    collectExpandedGroupNames(items, currentViewItem) {
        const names = new Set();
        if (!currentViewItem) return names;
        for (const item of items) {
            if (item.groupName?.trim() && this._itemContainsId(item, currentViewItem.id)) {
                names.add(item.groupName.trim());
            }
        }
        return names;
    }

    _itemContainsId(item, targetId) {
        if (item.id === targetId) return true;
        if (item.subItems?.length) {
            return item.subItems.some((s) => this._itemContainsId(s, targetId));
        }
        return false;
    }

    findGroupNameForItem(items, targetId, parentGroupName = null) {
        for (const item of items || []) {
            const groupName = item.groupName?.trim() || parentGroupName;
            if (item.id === targetId) return groupName;
            const found = this.findGroupNameForItem(item.subItems, targetId, groupName);
            if (found !== null) return found;
        }
        return null;
    }

    buildSelectedTitle(item) {
        const base = item.tab || item.label;
        return item.applicantType ? `${base} - ${item.applicantType}` : base;
    }

    // ── Event dispatch ────────────────────────────────────────────────────────

    dispatchMenuSelectEvent(item) {
        const effectiveStatus = this.getEffectiveStatus(item);
        const isStagePast     = (effectiveStatus || '').toLowerCase() === STATUS_COMPLETED;
        window.dispatchEvent(
            new CustomEvent('losmenuselect', {
                detail: {
                    tab               : item.tab || item.label,
                    id                : item.id,
                    label             : this.selectedTabTitle,
                    applicantId       : item.applicantId,
                    applicantType     : item.applicantType,
                    applicantName     : item.applicantName,
                    isGroupItem       : item.isGroupItem === true,
                    applicants        : item.applicants || [],
                    stagePhrase       : item.stagePhrase || '',
                    currentStagePhrase: item.stagePhrase || '',
                    isStagePast,
                    subCreationLocked : item.subCreationLocked === true,
                    // LWC component name to load in the content area (from Override_LWC__c)
                    overrideLwc       : item.overrideLwc || '',
                },
                bubbles : true,
                composed: true,
            })
        );
    }
}