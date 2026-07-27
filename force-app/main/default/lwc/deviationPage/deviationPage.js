import { LightningElement, api, track } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'
import {
  APEX_CLASS,
  ACTION_GET_DEVIATIONS,
  ACTION_SAVE_DEVIATION_APPROVALS,
  APPROVAL_OPTIONS,
  APPROVAL_STATUS_APPROVED,
  APPROVAL_STATUS_REJECTED,
  DEVIATION_LABEL,
  MSG_LOAD_FAILED,
  MSG_SAVE_FAILED,
  MSG_SAVE_SUCCESS,
  LOS_GLOBAL_LOADER_EVENT
} from './deviationPageConstants'

const DEVIATION_TABLE_CLASS = 'master-table-scroll master-table-scroll--interactive'

export default class DeviationPage extends LightningElement {

  _recordId
  _isStagePast = false
  _globalLoaderShown = false
  _savedDeviationById = {}

  @api
  get recordId() {
    return this._recordId
  }

  set recordId(value) {
    if (value === this._recordId) {
      return
    }
    this._recordId = value
  }

  @api
  set isStagePast(value) {
    this._isStagePast = value === true || value === 'true'
  }

  get isStagePast() {
    return this._isStagePast
  }

  get showSaveButton() {
    return !this.isStagePast && this.pendingChangeCount > 0
  }

  deviationLabel = DEVIATION_LABEL
  deviationApprovalOptions = APPROVAL_OPTIONS

  @track normalDeviations = []
  @track assetDeviationGroups = []
  @track isSaveDisabled = false
  @track pendingChangeCount = 0
  @track normalDeviationTableClass = DEVIATION_TABLE_CLASS
  @track expandedAssetDeviationGroupId = null

  get assetDeviationAccordionRows() {
    const expandedId = this.expandedAssetDeviationGroupId
    return (this.assetDeviationGroups || []).map((group) => {
      const isExpanded =
        expandedId != null && String(group.id) === String(expandedId)
      return {
        ...group,
        isExpanded,
        chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
        itemClass: isExpanded
          ? 'dev-asset-accordion-item dev-asset-accordion-item--expanded'
          : 'dev-asset-accordion-item'
      }
    })
  }

  connectedCallback() {
    this._loadPageData()
  }

  async _loadPageData() {
    if (!this._recordId) {
      this.normalDeviations = []
      this.assetDeviationGroups = []
      this._syncPendingChanges()
      return
    }

    this._showGlobalLoader('Loading deviation details...')
    try {
      const result = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: ACTION_GET_DEVIATIONS,
        recordId: this._recordId,
        params: {}
      })

      if (result?.isSuccess !== true) {
        this.showToast('Error', result?.message || MSG_LOAD_FAILED, 'error')
        this.normalDeviations = []
        this.assetDeviationGroups = []
        this._syncPendingChanges()
        return
      }

      this.normalDeviations = this._mapDeviationRows(result.globalDeviations, 'normal')
      this.assetDeviationGroups = this._mapAssetDeviationGroups(result.assetDeviationGroups)
      this.expandedAssetDeviationGroupId = null
      this._setOpenDeviationCombobox(null)
      this._refreshSavedDeviations()
      this._syncPendingChanges()
    } catch (error) {
      console.error('[deviationPage] _loadPageData', error)
      this.showToast(
        'Error',
        error?.body?.message || error?.message || MSG_LOAD_FAILED,
        'error'
      )
      this.normalDeviations = []
      this.assetDeviationGroups = []
      this._syncPendingChanges()
    } finally {
      this._hideGlobalLoaderIfShown()
    }
  }

  _showGlobalLoader(message) {
    if (this._globalLoaderShown) {
      return
    }
    this._globalLoaderShown = true
    window.dispatchEvent(
      new CustomEvent(LOS_GLOBAL_LOADER_EVENT, {
        detail: { show: true, message: message || 'Processing...' }
      })
    )
  }

  _hideGlobalLoaderIfShown() {
    if (!this._globalLoaderShown) {
      return
    }
    this._globalLoaderShown = false
    window.dispatchEvent(
      new CustomEvent(LOS_GLOBAL_LOADER_EVENT, { detail: { show: false } })
    )
  }

  _setOpenDeviationCombobox(comboboxKey) {
    this.normalDeviations = this.normalDeviations.map((deviationRow) => ({
      ...deviationRow,
      trClass: comboboxKey === `normal-${deviationRow.id}` ? 'master-table-row dev-row-active' : 'master-table-row'
    }))
    const assetTableClass = this._deviationTableClass('asset', comboboxKey)
    this.assetDeviationGroups = this.assetDeviationGroups.map((group) => ({
      ...group,
      tableClass: assetTableClass,
      deviations: (group.deviations || []).map((deviationRow) => ({
        ...deviationRow,
        trClass: comboboxKey === `asset-${deviationRow.id}` ? 'master-table-row dev-row-active' : 'master-table-row'
      }))
    }))
    this.normalDeviationTableClass = this._deviationTableClass('normal', comboboxKey)
  }

  _deviationTableClass(section, openComboboxKey) {
    if (openComboboxKey?.startsWith(`${section}-`)) {
      return `${DEVIATION_TABLE_CLASS} dev-has-open-combobox`
    }
    return DEVIATION_TABLE_CLASS
  }

  _mapDeviationRows(rows, section) {
    if (!Array.isArray(rows)) {
      return []
    }
    return rows.map((row) => {
      const deviationId = row.id || row.Id
      return {
        id: deviationId,
        description: row.description ?? row.Deviation_Description__c ?? '',
        level: row.level ?? row.Deviation_Level__c ?? '',
        role: row.role ?? row.Role__c ?? '',
        approvalStatus: row.approvalStatus ?? row.Approval_Status__c ?? '',
        remarks: row.remarks ?? '',
        comboboxName: `deviation-approval-${section}-${deviationId}`,
        trClass: 'master-table-row'
      }
    })
  }

  _mapAssetDeviationGroups(groups) {
    if (!Array.isArray(groups)) {
      return []
    }
    return groups.map((group) => ({
      id: group.id || group.lineItemId,
      lineItemId: group.lineItemId || group.id,
      assetId: group.assetId || null,
      listTitle: group.listTitle || 'Asset',
      tableClass: DEVIATION_TABLE_CLASS,
      deviations: this._mapDeviationRows(group.deviations, 'asset')
    }))
  }

  _getAllAssetDeviations() {
    return this.assetDeviationGroups.flatMap((group) => group.deviations || [])
  }

  handleAssetAccordionToggle(event) {
    const groupId = event.currentTarget?.dataset?.groupId
    if (!groupId) {
      return
    }
    this.expandedAssetDeviationGroupId =
      String(this.expandedAssetDeviationGroupId) === String(groupId) ? null : groupId
    this._setOpenDeviationCombobox(null)
  }

  handleDeviationRemarksChange(event) {
    const { id: deviationId, section } = event.currentTarget.dataset
    this._updateDeviationRow(section, deviationId, { remarks: event.target.value })
  }

  handleComboboxFocus(event) {
    const { id: deviationId, section } = event.currentTarget.dataset
    this._setOpenDeviationCombobox(`${section}-${deviationId}`)
  }

  handleComboboxBlur() {
    this._setOpenDeviationCombobox(null)
  }

  handleApprovalChange(event) {
    const { id: deviationId, section } = event.currentTarget.dataset
    const approvalStatus = event.detail?.value ?? event.target.value
    this._updateDeviationRow(section, deviationId, { approvalStatus })
    this._setOpenDeviationCombobox(null)
  }

  _updateDeviationRow(section, deviationId, fields) {
    if (!deviationId) {
      return
    }

    if (section === 'asset') {
      this.assetDeviationGroups = this.assetDeviationGroups.map((group) => ({
        ...group,
        deviations: (group.deviations || []).map((deviationRow) =>
          String(deviationRow.id) === String(deviationId)
            ? { ...deviationRow, ...fields }
            : deviationRow
        )
      }))
    } else {
      this.normalDeviations = this.normalDeviations.map((deviationRow) =>
        String(deviationRow.id) === String(deviationId) ? { ...deviationRow, ...fields } : deviationRow
      )
    }

    this._syncPendingChanges()
  }

  _refreshSavedDeviations() {
    const savedDeviations = {}
    ;[...this.normalDeviations, ...this._getAllAssetDeviations()].forEach((deviationRow) => {
      savedDeviations[deviationRow.id] = {
        approvalStatus: deviationRow.approvalStatus || '',
        remarks: deviationRow.remarks || ''
      }
    })
    this._savedDeviationById = savedDeviations
  }

  _syncPendingChanges() {
    this.pendingChangeCount = this._hasUnsavedChanges() ? 1 : 0
  }

  _hasUnsavedChanges() {
    return [...this.normalDeviations, ...this._getAllAssetDeviations()].some((deviationRow) => {
      const savedDeviation = this._savedDeviationById[deviationRow.id] || {
        approvalStatus: '',
        remarks: ''
      }
      const approvalStatus = deviationRow.approvalStatus || ''
      const remarks = deviationRow.remarks || ''
      return (
        approvalStatus !== savedDeviation.approvalStatus ||
        remarks !== savedDeviation.remarks
      )
    })
  }

  _getDeviationChanges() {
    const deviationChanges = []
    ;[...this.normalDeviations, ...this._getAllAssetDeviations()].forEach((deviationRow) => {
      const savedDeviation = this._savedDeviationById[deviationRow.id] || {
        approvalStatus: '',
        remarks: ''
      }
      const approvalStatus = deviationRow.approvalStatus || ''
      const remarks = deviationRow.remarks || ''
      const hasApprovalStatus =
        approvalStatus === APPROVAL_STATUS_APPROVED ||
        approvalStatus === APPROVAL_STATUS_REJECTED
      const isDeviationModified =
        approvalStatus !== savedDeviation.approvalStatus ||
        remarks !== savedDeviation.remarks
      if (hasApprovalStatus && isDeviationModified) {
        deviationChanges.push({ id: deviationRow.id, approvalStatus, remarks })
      }
    })
    return deviationChanges
  }

  async handleSaveButton() {
    if (this.isSaveDisabled || this.isStagePast) {
      return
    }

    const deviationChanges = this._getDeviationChanges()
    if (deviationChanges.length === 0) {
      return
    }

    this.isSaveDisabled = true
    this._showGlobalLoader('Saving deviation approvals...')
    try {
      const result = await savePageData({
        apexClassName: APEX_CLASS,
        apexMethodName: ACTION_SAVE_DEVIATION_APPROVALS,
        recordId: this._recordId,
        params: { updatedDeviations: deviationChanges }
      })

      if (result?.isSuccess !== true) {
        this.showToast('Error', result?.message || MSG_SAVE_FAILED, 'error')
        return
      }

      if (!result?.savedCount) {
        this.showToast('Error', MSG_SAVE_FAILED, 'error')
        return
      }

      this._refreshSavedDeviations()
      this._syncPendingChanges()
      this.showToast('Success', MSG_SAVE_SUCCESS, 'success')
    } catch (error) {
      console.error('[deviationPage] handleSaveButton', error)
      this.showToast(
        'Error',
        error?.body?.message || error?.message || MSG_SAVE_FAILED,
        'error'
      )
    } finally {
      this.isSaveDisabled = false
      this._hideGlobalLoaderIfShown()
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }))
  }
}