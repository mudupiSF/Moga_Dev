import { LightningElement, api, track } from 'lwc'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import {
  TAB_CAM,
  TAB_DEVIATIONS,
  TAB_APPROVAL_LOG_PAGE,
  WORKSPACE_TABS,
  EMPTY_PROPOSAL_SECTION,
  APEX_CLASS,
  ACTION_GET_PROPOSAL_SECTION
} from './camAndApprovalLogMasterPageConstants'

const ALLOWED_TABS = new Set(WORKSPACE_TABS.map((tab) => tab.value))

export default class CamAndApprovalLogMasterPage extends LightningElement {

  _recordId
  @api applicantId
  @api currentViewId
  @api stagePhrase = ''

  _isStagePast = false
  _tabParam = ''
  _isConnected = false

  @api
  get recordId() {
    return this._recordId
  }

  set recordId(value) {
    if (value === this._recordId) {
      return
    }
    this._recordId = value
    this._loadProposalSectionIfReady()
  }

  @api
  set isStagePast(value) {
    this._isStagePast = value === true || value === 'true'
  }

  get isStagePast() {
    return this._isStagePast
  }

  @track activeTab = TAB_CAM
  @track tabs = {
    [TAB_CAM]: true,
    [TAB_DEVIATIONS]: false,
    [TAB_APPROVAL_LOG_PAGE]: false
  }
  @track proposalSection = { ...EMPTY_PROPOSAL_SECTION }
  @track _camData = null
  offerAccepted = true

  connectedCallback() {
    this._isConnected = true
    this._loadProposalSectionIfReady()
  }

  _loadProposalSectionIfReady() {
    if (!this._isConnected || !this._recordId) {
      return
    }
    this._loadProposalSection()
  }

  async _loadProposalSection() {
    try {
      const result = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: ACTION_GET_PROPOSAL_SECTION,
        recordId: this._recordId,
        params: {}
      })

      if (result?.isSuccess !== true) {
        this.proposalSection = { ...EMPTY_PROPOSAL_SECTION }
        return
      }

      this.proposalSection = {
        statusLabel: result.statusLabel ?? EMPTY_PROPOSAL_SECTION.statusLabel
      }
    } catch (error) {
      console.error('[camAndApprovalLogMasterPage] _loadProposalSection', error)
      this.proposalSection = { ...EMPTY_PROPOSAL_SECTION }
    }
  }

  @api
  get tab() {
    return this._tabParam
  }

  set tab(value) {
    this._tabParam = value ?? ''
    this._applyInitialTab()
  }

  _applyInitialTab() {
    const tabValue = (this._tabParam || '').trim().toLowerCase()
    if (!tabValue) {
      return
    }
    this._activateTab(tabValue)
  }

  _activateTab(tabValue) {
    if (!tabValue || !ALLOWED_TABS.has(tabValue)) {
      return
    }
    if (!this.tabs[tabValue]) {
      this.tabs = { ...this.tabs, [tabValue]: true }
    }
    this.activeTab = tabValue
  }

  get workspaceTabs() {
    return WORKSPACE_TABS.map((tab) => {
      const isActive = this.activeTab === tab.value
      return {
        ...tab,
        isActive,
        tabClass: isActive ? 'camal-tab-btn camal-tab-btn-active' : 'camal-tab-btn'
      }
    })
  }

  get camPanelClass() {
    return this.activeTab === TAB_CAM
      ? 'camal-tab-panel'
      : 'camal-tab-panel camal-tab-panel--hidden'
  }

  get deviationsPanelClass() {
    return this.activeTab === TAB_DEVIATIONS
      ? 'camal-tab-panel'
      : 'camal-tab-panel camal-tab-panel--hidden'
  }

  get approvalLogPanelClass() {
    return this.activeTab === TAB_APPROVAL_LOG_PAGE
      ? 'camal-tab-panel'
      : 'camal-tab-panel camal-tab-panel--hidden'
  }

  get isCamPanelHidden() {
    return this.activeTab !== TAB_CAM
  }

  get isDeviationsPanelHidden() {
    return this.activeTab !== TAB_DEVIATIONS
  }

  get isApprovalLogPanelHidden() {
    return this.activeTab !== TAB_APPROVAL_LOG_PAGE
  }

  get camPanelTabindex() {
    return this.activeTab === TAB_CAM ? '0' : '-1'
  }

  get deviationsPanelTabindex() {
    return this.activeTab === TAB_DEVIATIONS ? '0' : '-1'
  }

  get approvalLogPanelTabindex() {
    return this.activeTab === TAB_APPROVAL_LOG_PAGE ? '0' : '-1'
  }

  get highlightPanelData() {
    if (!this._recordId) {
      return undefined
    }
    return { opportunityId: this._recordId }
  }

  handleTabSelect(event) {
    const tabValue = event.currentTarget?.dataset?.value
    if (tabValue) {
      this._activateTab(tabValue)
      if (tabValue === TAB_APPROVAL_LOG_PAGE && this.tabs[TAB_APPROVAL_LOG_PAGE]) {
        this._refreshApprovalLogPage()
      }
    }
  }

  _refreshApprovalLogPage() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    Promise.resolve().then(() => {
      this.template.querySelector('c-approval-log-page')?.refresh?.()
    })
  }

  handleCamDataLoaded(event) {
    this._camData = event.detail?.camData ?? null
  }

  handleRefreshClick() {
    this._loadProposalSection()
  }

  handleSpinner() {}
}