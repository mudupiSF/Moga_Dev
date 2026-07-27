import { LightningElement, api, track } from 'lwc'
import { NavigationMixin } from 'lightning/navigation'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import { invokeHandler } from 'c/clientLayerHelper'
import {
  APEX_CLASS,
  ACTION_GET_INVESTIGATION_RECORDS,
  CUSTOMER_EXPOSURE_HANDLER,
  DEFAULT_ACTIVE_SECTION_ID,
  EMPTY_CELL_VALUE,
  EMPTY_SECTION_MESSAGE,
  LOS_GLOBAL_LOADER_EVENT,
  LOS_NEXT_STAGE_EVENT,
  PAGE_SIZE,
  STAGE_INVESTIGATION_REPORTS,
  SECTION_DEFINITIONS,
  FI_LABEL_COMPONENT_MAP
} from './investigationDetailsConstants'

export default class InvestigationDetailsMasterPage extends NavigationMixin(LightningElement) {

  @api recordId
  @api applicantId
  @api currentViewId
  @api stagePhrase = ''
  @api tab = ''

  @track activeAccordionSection = ''
  @track sectionRowsById = {}
  @track sectionPageById = {}

  _globalLoaderShown = false

  connectedCallback() {
    this._initializeSections()
    this._loadInvestigationData()
  }

  disconnectedCallback() {
    this._hideGlobalLoaderIfShown()
  }

  get menuSections() {
    return SECTION_DEFINITIONS.map((definition) => {
      const isExpanded = this.activeAccordionSection === definition.id
      const rows = this.sectionRowsById[definition.id] || []
      const count = rows.length
      const tableColumns = definition.tableColumns || []
      const currentPage = this._getSectionPage(definition.id)
      const totalPages = Math.max(1, Math.ceil(count / PAGE_SIZE))
      const startIndex = (currentPage - 1) * PAGE_SIZE
      const pageRows = rows.slice(startIndex, startIndex + PAGE_SIZE)
      const rangeStart = count > 0 ? startIndex + 1 : 0
      const rangeEnd = Math.min(startIndex + PAGE_SIZE, count)

      return {
        ...definition,
        isExpanded,
        count,
        countLabel: `${definition.label} (${count})`,
        accordionItemClass: isExpanded
          ? 'idm-accordion-item idm-accordion-item-open'
          : 'idm-accordion-item',
        accordionTriggerClass: isExpanded
          ? 'idm-accordion-trigger idm-accordion-trigger-open'
          : 'idm-accordion-trigger',
        chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
        iconWrapClass: `idm-accordion-icon-wrap idm-accordion-icon-wrap-${definition.iconVariant}`,
        tableColumns,
        displayRows: pageRows.map((row, index) =>
          this._toDisplayRow(row, tableColumns, startIndex + index)
        ),
        hasRows: count > 0,
        emptyMessage: EMPTY_SECTION_MESSAGE,
        currentPage,
        totalPages,
        isPrevDisabled: count <= PAGE_SIZE || currentPage <= 1,
        isNextDisabled: count <= PAGE_SIZE || currentPage >= totalPages,
        paginationLabel: count > 0
          ? `Showing ${rangeStart} to ${rangeEnd} of ${count} results`
          : '',
        paginationAriaLabel: `${definition.label} table pagination`
      }
    })
  }

  get hasMenuSections() {
    return this.menuSections.length > 0
  }

  handleAccordionToggle(event) {
    const sectionId = event.currentTarget?.dataset?.section
    if (!sectionId) {
      return
    }

    if (this.activeAccordionSection === sectionId) {
      return
    }

    this.activeAccordionSection = sectionId
  }

  handleSectionPrevPage(event) {
    const sectionId = event.currentTarget?.dataset?.section
    if (!sectionId) {
      return
    }

    const currentPage = this._getSectionPage(sectionId)
    if (currentPage <= 1) {
      return
    }

    this._setSectionPage(sectionId, currentPage - 1)
  }

  handleSectionNextPage(event) {
    const sectionId = event.currentTarget?.dataset?.section
    if (!sectionId) {
      return
    }

    const rows = this.sectionRowsById[sectionId] || []
    const totalPages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE))
    const currentPage = this._getSectionPage(sectionId)

    if (currentPage >= totalPages) {
      return
    }

    this._setSectionPage(sectionId, currentPage + 1)
  }

  async handleRecordLinkClick(event) {
    event.preventDefault()

    const { componentName, verificationId, recordId, isFiLink } = event.currentTarget.dataset

    try {
      if (componentName) {
        const state = { c__recordId: recordId || undefined }
        if (isFiLink === 'true' && verificationId) {
          state.c__verificationId = verificationId
        }
        const url = await this[NavigationMixin.GenerateUrl]({
          type: 'standard__component',
          attributes: { componentName },
          state
        })
        window.open(url, '_blank', 'noopener,noreferrer')
        return
      }

      if (recordId) {
        const url = await this[NavigationMixin.GenerateUrl]({
          type: 'standard__recordPage',
          attributes: {
            recordId,
            actionName: 'view'
          }
        })
        window.open(url, '_blank', 'noopener,noreferrer')
      }
    } catch (error) {
      console.error('investigationDetailsMasterPage: navigation failed', error)
      this._toast('Navigation Error', 'Unable to open the record.', 'error')
    }
  }

  async handleNextButton() {
    const currentViewId = this.currentViewId
    if (!currentViewId) {
      this._toast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error')
      return
    }

    if (!this.recordId) {
      this._toast('Customer Exposure', 'Application record Id is missing.', 'error')
      return
    }

    // Temporary test hook — remove when real call site (e.g. dedupe) is wired
    this._showGlobalLoader('Creating customer exposure obligations...')
    try {
      await invokeHandler(CUSTOMER_EXPOSURE_HANDLER, 'onNext', this)
      const exposureResult = this._customerExposureResult

      if (!exposureResult?.isSuccess) {
        this._toast(
          'Customer Exposure',
          exposureResult?.message || 'Customer exposure failed.',
          'error'
        )
        return
      }

      this._toast('Customer Exposure', 'Customer exposure completed.', 'success')
    } catch (error) {
      console.error('investigationDetailsMasterPage: customer exposure failed', error)
      this._toast(
        'Customer Exposure',
        error?.body?.message || error?.message || 'Customer exposure failed.',
        'error'
      )
      return
    } finally {
      this._hideGlobalLoaderIfShown()
    }

    window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
      detail: {
        currentViewId,
        id: currentViewId,
        applicantId: this.applicantId,
        currentLoanStageComplete: this.tab || STAGE_INVESTIGATION_REPORTS,
        currentStagePhrase: this.stagePhrase || ''
      },
      bubbles: true,
      composed: true
    }))
  }

  _initializeSections() {
    this.activeAccordionSection = DEFAULT_ACTIVE_SECTION_ID
    this.sectionPageById = this._createDefaultSectionPages()
    this.sectionRowsById = SECTION_DEFINITIONS.reduce((rowsById, definition) => {
      rowsById[definition.id] = []
      return rowsById
    }, {})
  }

  _createDefaultSectionPages() {
    return SECTION_DEFINITIONS.reduce((pagesById, definition) => {
      pagesById[definition.id] = 1
      return pagesById
    }, {})
  }

  _getSectionPage(sectionId) {
    return this.sectionPageById[sectionId] || 1
  }

  _setSectionPage(sectionId, page) {
    this.sectionPageById = {
      ...this.sectionPageById,
      [sectionId]: page
    }
  }

  _clampSectionPages() {
    const nextPages = { ...this.sectionPageById }

    SECTION_DEFINITIONS.forEach((definition) => {
      const rows = this.sectionRowsById[definition.id] || []
      const totalPages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE))
      const currentPage = nextPages[definition.id] || 1
      nextPages[definition.id] = Math.min(Math.max(1, currentPage), totalPages)
    })

    this.sectionPageById = nextPages
  }

  async _loadInvestigationData() {
    if (!this.recordId) {
      return
    }

    this._showGlobalLoader('Loading investigation records...')
    try {
      const rowsBySection = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: ACTION_GET_INVESTIGATION_RECORDS,
        recordId: this.recordId,
        params: null
      })
      this.sectionRowsById = SECTION_DEFINITIONS.reduce((accumulator, definition) => {
        accumulator[definition.id] = rowsBySection?.[definition.id] || []
        return accumulator
      }, {})
      this.sectionPageById = this._createDefaultSectionPages()
      this._clampSectionPages()
    } catch (error) {
      console.error('investigationDetailsMasterPage: load failed', error)
      this._toast('Error', 'Unable to load investigation records.', 'error')
    } finally {
      this._hideGlobalLoaderIfShown()
    }
  }

  _showGlobalLoader(message) {
    this._globalLoaderShown = true
    window.dispatchEvent(new CustomEvent(LOS_GLOBAL_LOADER_EVENT, {
      detail: { show: true, message: message || 'Loading...' }
    }))
  }

  _hideGlobalLoaderIfShown() {
    if (!this._globalLoaderShown) {
      return
    }
    this._globalLoaderShown = false
    window.dispatchEvent(new CustomEvent(LOS_GLOBAL_LOADER_EVENT, {
      detail: { show: false }
    }))
  }

  _resolveFiComponentName(fiLabel) {
    return FI_LABEL_COMPONENT_MAP[String(fiLabel || '').trim()] || null
  }

  _toDisplayRow(row, tableColumns, index) {
    return {
      id: row.id,
      rowNumber: index + 1,
      cells: (tableColumns || []).map((column) => this._toDisplayCell(row, column))
    }
  }

  _toDisplayCell(row, column) {
    const rawValue = row?.[column.fieldName]
    const value = rawValue ? String(rawValue) : EMPTY_CELL_VALUE
    const baseCell = {
      key: column.key,
      value,
      isEmpty: value === EMPTY_CELL_VALUE,
      isLink: column.type === 'link',
      isStatus: column.type === 'status',
      isText: column.type === 'text'
    }

    if (column.type === 'link') {
      const componentName = this._resolveFiComponentName(row?.name)
      const verificationId = row?.verificationId || ''
      const recordId = row?.id || ''
      const isFiLink = Boolean(verificationId && componentName)
      const isInvestigationComponentLink = Boolean(componentName && recordId && !isFiLink)

      return {
        ...baseCell,
        hasLink: isFiLink || isInvestigationComponentLink || Boolean(recordId && !componentName),
        isFiLink,
        componentName: componentName ? `c__${componentName}` : '',
        verificationId,
        recordId,
        textClass: value === EMPTY_CELL_VALUE ? 'master-cell-empty' : 'master-cell-text'
      }
    }

    if (column.type === 'status') {
      return {
        ...baseCell,
        statusClass: this._resolveStatusClass(rawValue),
        textClass: value === EMPTY_CELL_VALUE ? 'master-cell-empty' : 'master-cell-text'
      }
    }

    return {
      ...baseCell,
      textClass: value === EMPTY_CELL_VALUE ? 'master-cell-empty' : 'master-cell-text'
    }
  }

  _resolveStatusClass(status) {
    const normalizedStatus = String(status || '').trim().toLowerCase()

    if (!normalizedStatus) {
      return 'master-status-badge master-status-badge-neutral'
    }

    if (
      normalizedStatus.includes('complete')
      || normalizedStatus.includes('approved')
      || normalizedStatus.includes('positive')
      || normalizedStatus.includes('success')
    ) {
      return 'master-status-badge master-status-badge-success'
    }

    if (
      normalizedStatus.includes('reject')
      || normalizedStatus.includes('negative')
      || normalizedStatus.includes('fail')
      || normalizedStatus.includes('cancel')
    ) {
      return 'master-status-badge master-status-badge-danger'
    }

    if (
      normalizedStatus.includes('pending')
      || normalizedStatus.includes('progress')
      || normalizedStatus.includes('assigned')
      || normalizedStatus.includes('initiated')
    ) {
      return 'master-status-badge master-status-badge-warning'
    }

    return 'master-status-badge master-status-badge-neutral'
  }

  _toast(title, message, variant) {
    this.dispatchEvent(new CustomEvent('showtoast', {
      detail: { title, message, variant },
      bubbles: true,
      composed: true
    }))
  }
}