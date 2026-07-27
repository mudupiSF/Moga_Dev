import { LightningElement, api, track } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'
import getOfferData from '@salesforce/apex/OfferPageController.getOfferData'
import createRepaymentSchedule from '@salesforce/apex/OfferPageController.createRepaymentSchedule'
import getFormRenderData from '@salesforce/apex/CustomerFormController.getFormRenderData'
import generatePhoneOTP from '@salesforce/apex/SendPhoneOTPAPIController.generateOTP'
import { invokeHandler } from 'c/clientLayerHelper'
import {
  APEX_CLASS,
  ACTION_GET_APPROVAL_LOGS,
  ACTION_GET_APPROVAL_LOG_USER_CONTEXT,
  ACTION_CREATE_FORWARD_LOG,
  ACTION_GET_LOAN_TERM_GROUPS,
  MSG_LOAD_FAILED,
  MSG_FORWARD_SAVE_SUCCESS,
  MSG_FORWARD_SAVE_FAILED,
  MSG_DEVIATIONS_LOAD_FAILED,
  MSG_DEVIATIONS_NOT_APPROVED,
  MSG_CIBIL_IN_PROGRESS,
  MSG_NAVIGATION_VIEW_MISSING,
  DEVIATION_APEX_CLASS,
  ACTION_GET_DEVIATIONS,
  APPROVAL_STATUS_APPROVED,
  LOS_NEXT_STAGE_EVENT,
  LOS_GLOBAL_LOADER_EVENT,
  STAGE_TAB_DEFAULT,
  YES_NO_OPTIONS,
  GLOBAL_ACTION_BUTTONS,
  ASSET_ACTION_BUTTONS,
  ACTION_ID_INSURANCE,
  ACTION_ID_PAYIN,
  ACTION_ID_SCHEDULE,
  ACTION_ID_DOWNLOAD_CAM,
  FORWARD_LOG_HEADERS,
  APPROVAL_HISTORY_HEADERS,
  FORWARD_PROPOSAL_NO,
  FORWARD_PROPOSAL_YES,
  CIBIL_CONSENT_YES,
  FORWARD_TO_OPTIONS,
  DECISION_OPTIONS,
  DECISION_ACCEPT,
  APPROVAL_CONDITIONS_HEADERS,
  APPROVAL_CONDITION_ACTION_OPTIONS,
  PROPOSAL_STATUS_OPTIONS,
  RS_PREFIX,
  EMPTY_LOAN_TERMS,
  FINAL_LOAN_TERMS_BECVO,
  CVO_BE_ROLES,
  HIGHER_AUTHORITY_ROLES
} from './plCAMApprovalLogPageConstants'

const FORM_CAM = 'CAM_Document'

export default class PlCAMApprovalLogPage extends LightningElement {

  _recordId
  _isConnected = false
  _globalLoaderShown = false

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

  @track userRole = ''
  @track isLeadOwner = false
  @track isHigherAuthority = false

  _isStagePast = false

  @api
  set isStagePast(value) {
    this._isStagePast = value === true || value === 'true'
  }

  get isStagePast() {
    return this._isStagePast
  }

  yesNoOptions = YES_NO_OPTIONS
  forwardToOptions = FORWARD_TO_OPTIONS
  approvalConditionActionOptions = APPROVAL_CONDITION_ACTION_OPTIONS
  assetActionButtons = ASSET_ACTION_BUTTONS
  @track emiDateOptions = []
  proposalStatusOptions = PROPOSAL_STATUS_OPTIONS
  decisionOptions = DECISION_OPTIONS
  forwardLogHeaders = FORWARD_LOG_HEADERS
  approvalHistoryHeaders = APPROVAL_HISTORY_HEADERS
  approvalConditionsHeaders = APPROVAL_CONDITIONS_HEADERS

  forwardLogColspan = FORWARD_LOG_HEADERS.length
  approvalHistoryColspan = APPROVAL_HISTORY_HEADERS.length
  approvalConditionsColspan = APPROVAL_CONDITIONS_HEADERS.length

  @track loanTerms = { ...EMPTY_LOAN_TERMS }
  @track loanTermGroups = []
  @track expandedAssetActionGroupId = null
  @track showLoanTermsModal = false
  @track selectedLoanTermGroupId = null

  @track forwardProposal = FORWARD_PROPOSAL_NO
  @track selectedForwardTo = ''
  @track remarks = ''
  @track decision = DECISION_ACCEPT
  @track decisionRemarks = ''
  @track firstEmiDueDate = ''
  @track approvalConditions = []
  @track proposalStatus = ''
  @track finalRemarkValue = ''
  @track crmIRREditable = ''
  @track loanAmountEditable = ''
  @track cibilValidityOption = FORWARD_PROPOSAL_NO
  cibilVerified = false
  borrowerPhone = ''
  borrowerApplicantId = null

  showDynamicModal = false
  showIntegrationModal = false
  dynamicComponentName = ''
  dynamicComponentProps = {}
  dynamicModalHeader = ''
  integrationStatus = 'loading'
  integrationCurrentStageIndex = 0
  integrationSuccessMessage = ''
  integrationErrorMessage = ''
  integrationStages = []
  _integrationRetryFn = null
  _pendingCibilVerification = false
  _pendingAddInsurance = false
  _cibilOtpFlow = false
  _lastActionFieldKey = ''

  // CAM Document
  showPdfRenderModal = false
  pdfRenderDocumentChecklistId = null
  pdfRenderModalProps = {}

  @track processedForwardLogs = []
  @track processedApprovalHistory = []
  @track isSavingForward = false
  @track isNextDisabled = false
  @track hasNavigatedToNextStage = false

  @api currentViewId = ''
  _passedApplicantId = ''

  @api
  get applicantId() {
    return this.borrowerApplicantId || this._passedApplicantId || ''
  }

  set applicantId(value) {
    this._passedApplicantId = value || ''
  }

  @api stagePhrase = ''
  @api tab = ''

  get pdfRenderModalHeader() {
    return this.pdfRenderModalProps?.fileName || 'CAM Document'
  }

  get globalActionButtons() {
    return GLOBAL_ACTION_BUTTONS
  }

  get showAssetActionsSection() {
    return !this.isStagePast && this.loanTermGroups.length > 0
  }

  get assetActionRows() {
    const expandedId = this.expandedAssetActionGroupId
    return (this.loanTermGroups || []).map((group) => {
      const isExpanded =
        expandedId != null && String(group.id) === String(expandedId)
      return {
        id: group.id,
        listTitle: group.listTitle,
        isExpanded,
        chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
        itemClass: isExpanded
          ? 'alog-asset-accordion-item alog-asset-accordion-item--expanded'
          : 'alog-asset-accordion-item'
      }
    })
  }

  get showForwardForm() {
    return this.forwardProposal === FORWARD_PROPOSAL_YES
  }

  get isForwardProposalYes() {
    return this.forwardProposal === FORWARD_PROPOSAL_YES
  }

  get isForwardProposalNo() {
    return this.forwardProposal === FORWARD_PROPOSAL_NO
  }

  get isForwardDisabled() {
    return (
      this.isStagePast ||
      this.isSavingForward ||
      !this.selectedForwardTo ||
      !this.remarks?.trim()
    )
  }

  get firstEmiDueDateDisplay() {
    const match = this.emiDateOptions.find((opt) => opt.value === this.firstEmiDueDate)
    return match?.label ?? this.firstEmiDueDate
  }

  get selectedLoanTermGroup() {
    return this.loanTermGroups ? this.loanTermGroups[0] : null
  }

  get loanTermsModalTitle() {
    return this.selectedLoanTermGroup?.listTitle || 'Loan Terms'
  }

  get modalLoanTerms() {
    return this.selectedLoanTermGroup?.loanTerms || { ...EMPTY_LOAN_TERMS }
  }

  get modalEmiDateOptions() {
    return this.selectedLoanTermGroup?.emiDateOptions || []
  }

  get modalFirstEmiDueDate() {
    return this.selectedLoanTermGroup?.firstEmiDueDate || ''
  }

  get modalCrmIRREditable() {
    return this.selectedLoanTermGroup?.crmIRREditable ?? ''
  }

  get modalLoanAmountEditable() {
    return this.selectedLoanTermGroup?.loanAmountEditable ?? ''
  }

  get modalFirstEmiDueDateDisplay() {
    const match = this.modalEmiDateOptions.find((opt) => opt.value === this.modalFirstEmiDueDate)
    return match?.label ?? this.modalFirstEmiDueDate
  }

  get finalLoanTermsTableRows() {
    return FINAL_LOAN_TERMS_BECVO.map((field) => this._mapLoanTermField(field, true))
  }

  _mapLoanTermField(field, forModal = false) {
    const terms = forModal ? this.modalLoanTerms : this.loanTerms
    if (field.inputType === 'emiCombobox') {
      return { ...field, isEmiCombobox: true }
    }
    if (field.inputType === 'crmIrr') {
      const crmVal = forModal ? this.modalCrmIRREditable : this.crmIRREditable
      return { ...field, isCrmIrr: true, valueDisplay: `${crmVal ?? ''}` }
    }
    if (field.inputType === 'loanAmount') {
      return {
        ...field,
        isLoanAmount: true,
        valueDisplay: `${RS_PREFIX}${terms.loanAmount ?? ''}`
      }
    }
    const raw = terms[field.termKey]
    const valueDisplay = field.useRsPrefix ? `${RS_PREFIX}${raw ?? ''}` : `${raw ?? ''}`
    return { ...field, valueDisplay }
  }
    

  get isCvoOrBe() {
    const role = (this.userRole || '').trim().toUpperCase()
    return CVO_BE_ROLES.includes(role)
  }

  get isCvoBeLeadOwner() {
    const isOwner = this.isLeadOwner === true || this.isLeadOwner === 'true'
    return this.isCvoOrBe && isOwner
  }

  get isHigherAuthorityUser() {
    if (this.isHigherAuthority === true || this.isHigherAuthority === 'true') {
      return true
    }
    const role = (this.userRole || '').trim().toUpperCase()
    return HIGHER_AUTHORITY_ROLES.includes(role) || this.isCvoBeLeadOwner
  }

  get canEditRestrictedFinalLoanTerms() {
    return !this.isStagePast && this.isCvoBeLeadOwner
  }

  get showCibilSection() {
    return !this.cibilVerified && !this.isStagePast
  }

  get showNextButton() {
    return !this.isStagePast && !this.hasNavigatedToNextStage
  }

  connectedCallback() {
    this._isConnected = true
    this._dynamicModalHandler = (e) => this.handleOpenDynamicComponentModal(e)
    this.addEventListener('opendynamiccomponentmodal', this._dynamicModalHandler)
    this._loadPageData()
  }

  disconnectedCallback() {
    if (this._dynamicModalHandler) {
      this.removeEventListener('opendynamiccomponentmodal', this._dynamicModalHandler)
    }
    try {
      document.documentElement.style.overflow = ''
      document.body.style.overflow = ''
    } catch (e) {
      /* non-DOM contexts */
    }
  }

  @api
  refresh() {
    this._loadPageData()
  }

  _loadPageData() {
    if (!this._isConnected || !this._recordId) {
      return
    }
    this._loadApprovalLogs()
    this._loadApprovalLogUserContext()
    this._loadBorrowerContactData()
    this._loadLoanTermGroups()
  }

  async _loadBorrowerContactData() {
    const applicationId = this._recordId
    if (!applicationId) {
      return
    }

    try {
      const data = await getOfferData({ applicationId })
      this.borrowerApplicantId = data?.borrowerApplicantId || this._passedApplicantId || null
      this.borrowerPhone = data?.borrowerPhone || ''
    } catch (error) {
      console.error('[approvalLogPage] _loadBorrowerContactData', error)
    }
  }

  async _loadApprovalLogUserContext() {
    const applicationId = this._recordId
    if (!applicationId) {
      this._resetUserContext()
      return
    }

    try {
      const result = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: ACTION_GET_APPROVAL_LOG_USER_CONTEXT,
        recordId: applicationId,
        params: {}
      })
      if (result?.isSuccess) {
        this.userRole = result.userRole || ''
        this.isLeadOwner = result.isLeadOwner === true
        this.isHigherAuthority = result.isHigherAuthority === true
        return
      }
    } catch (error) {
      console.error('[approvalLogPage] _loadApprovalLogUserContext', error)
    }

    this._resetUserContext()
  }

  async _loadApprovalLogs() {
    const applicationId = this._recordId
    if (!applicationId) {
      this._clearApprovalLogTables()
      return
    }

    try {
      const result = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: ACTION_GET_APPROVAL_LOGS,
        recordId: applicationId,
        params: {}
      })
      if (result?.isSuccess !== true) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: 'Error',
            message: result?.message || MSG_LOAD_FAILED,
            variant: 'error'
          })
        )
        this._clearApprovalLogTables()
        return
      }
      this.processedForwardLogs = this._buildTableRows(result.forwardLogs, this.forwardLogHeaders)
      this.processedApprovalHistory = this._buildTableRows(
        result.approvalHistory,
        this.approvalHistoryHeaders
      )
      this.approvalConditions = this._mapApprovalConditionRows(result.approvalConditions)
    } catch (error) {
      console.error('[approvalLogPage] _loadApprovalLogs', error)
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Error',
          message: error?.body?.message || error?.message || MSG_LOAD_FAILED,
          variant: 'error'
        })
      )
      this._clearApprovalLogTables()
    }
  }

  _resetUserContext() {
    this.userRole = ''
    this.isLeadOwner = false
    this.isHigherAuthority = false
  }

  _clearApprovalLogTables() {
    this.processedForwardLogs = []
    this.processedApprovalHistory = []
    this.approvalConditions = []
  }

  async _loadLoanTermGroups() {
    if (!this._recordId) {
      this.loanTermGroups = []
      this.expandedAssetActionGroupId = null
      this._syncPrimaryLoanTermsFromGroups()
      return
    }

    try {
      const result = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: ACTION_GET_LOAN_TERM_GROUPS,
        recordId: this._recordId,
        params: {}
      })
      if (result?.isSuccess !== true) {
        this.loanTermGroups = []
        this.expandedAssetActionGroupId = null
        this._syncPrimaryLoanTermsFromGroups()
        return
      }
      this.loanTermGroups = this._mapLoanTermGroups(result.loanTermGroups)
      this.expandedAssetActionGroupId = null
      this._syncPrimaryLoanTermsFromGroups()
    } catch (error) {
      console.error('[approvalLogPage] _loadLoanTermGroups', error)
      this.loanTermGroups = []
      this.expandedAssetActionGroupId = null
      this._syncPrimaryLoanTermsFromGroups()
    }
  }

  _mapLoanTermGroups(groups) {
    if (!Array.isArray(groups)) {
      return []
    }
    return groups.map((group) => {
      const terms = { ...EMPTY_LOAN_TERMS, ...(group.loanTerms || {}) }
      return {
        id: group.id || group.lineItemId,
        lineItemId: group.lineItemId || group.id,
        assetId: group.assetId || null,
        listTitle: group.listTitle || 'Asset',
        loanTerms: terms,
        emiDateOptions: group.emiDateOptions || [],
        firstEmiDueDate: group.firstEmiDueDate || '',
        crmIRREditable: terms.crmIRR ?? '',
        loanAmountEditable: terms.loanAmount ?? ''
      }
    })
  }

  _syncPrimaryLoanTermsFromGroups() {
    const primary = this.loanTermGroups[0]
    if (!primary) {
      this._resetLoanTerms()
      return
    }
    this.loanTerms = { ...EMPTY_LOAN_TERMS, ...(primary.loanTerms || {}) }
    this.emiDateOptions = primary.emiDateOptions || []
    this.firstEmiDueDate = primary.firstEmiDueDate || ''
    this.crmIRREditable = primary.crmIRREditable ?? ''
    this.loanAmountEditable = primary.loanAmountEditable ?? ''
  }

  handleLoanTermsViewClick(event) {
    const groupId = event.currentTarget?.dataset?.groupId
    if (!groupId) {
      return
    }
    this.selectedLoanTermGroupId = groupId
    this.showLoanTermsModal = true
    this._syncBodyScroll()
  }

  handleLoanTermsModalClose() {
    this.showLoanTermsModal = false
    this.selectedLoanTermGroupId = null
    this._syncBodyScroll()
  }

  _syncBodyScroll() {
    const lock = this.showLoanTermsModal
    try {
      const overflow = lock ? 'hidden' : ''
      document.documentElement.style.overflow = overflow
      document.body.style.overflow = overflow
    } catch (e) {
      /* non-DOM contexts */
    }
  }

  _updateSelectedLoanTermGroup(patch) {
    const groupId = this.selectedLoanTermGroupId
    if (!groupId) {
      return
    }

    this.loanTermGroups = this.loanTermGroups.map((group) => {
      if (String(group.id) !== String(groupId)) {
        return group
      }
      const updated = { ...group, ...patch }
      if (patch.crmIRREditable !== undefined) {
        updated.crmIRREditable = patch.crmIRREditable
        updated.loanTerms = { ...group.loanTerms, crmIRR: patch.crmIRREditable }
      }
      if (patch.loanAmountEditable !== undefined) {
        updated.loanAmountEditable = patch.loanAmountEditable
        updated.loanTerms = { ...group.loanTerms, loanAmount: patch.loanAmountEditable }
      }
      if (patch.firstEmiDueDate !== undefined) {
        updated.firstEmiDueDate = patch.firstEmiDueDate
      }
      return updated
    })

    const firstId = this.loanTermGroups[0]?.id
    if (String(firstId) === String(groupId)) {
      this._syncPrimaryLoanTermsFromGroups()
    }
  }

  _resetLoanTerms() {
    this.loanTerms = { ...EMPTY_LOAN_TERMS }
    this.emiDateOptions = []
    this.firstEmiDueDate = ''
    this.crmIRREditable = ''
    this.loanAmountEditable = ''
  }

  _applyLoanTerms(result) {
    const terms = result?.loanTerms || {}
    this.loanTerms = { ...EMPTY_LOAN_TERMS, ...terms }
    this.emiDateOptions = result?.emiDateOptions || []
    this.firstEmiDueDate = result?.firstEmiDueDate || ''
    this.crmIRREditable = terms.crmIRR ?? ''
    this.loanAmountEditable = terms.loanAmount ?? ''
  }

  _mapApprovalConditionRows(rows) {
    return (rows || []).map((row) => {
      const action = (row.action || '').trim()
      const isSubmitted = action.length > 0
      return {
        id: row.id,
        sno: row.sno ?? '',
        approvalCondition: row.approvalCondition ?? '',
        action,
        remarks: row.remarks ?? '',
        isEditable: !this.isStagePast && !isSubmitted,
        isSubmitted
      }
    })
  }

  _buildTableRows(rows, headers) {
    return (rows || []).map((row) => ({
      id: row.id,
      cells: headers.map((header) => ({
        key: header.key,
        value: row[header.key] ?? ''
      }))
    }))
  }

  _updateApprovalCondition(conditionId, patch) {
    this.approvalConditions = this.approvalConditions.map((row) =>
      row.id === conditionId ? { ...row, ...patch } : row
    )
  }

  _readEventValue(event) {
    return event.detail?.value ?? event.target.value
  }

  handlePicklistChange(event) {
    const { field, inModal } = event.currentTarget.dataset
    const value = this._readEventValue(event)
    switch (field) {
      case 'selectedForwardTo':
        this.selectedForwardTo = value
        break
      case 'decision':
        this.decision = value
        break
      case 'firstEmiDueDate':
        if (inModal) {
          this._updateSelectedLoanTermGroup({ firstEmiDueDate: value })
        } else {
          this.firstEmiDueDate = value
        }
        break
      case 'proposalStatus':
        this.proposalStatus = value
        break
      default:
        break
    }
  }

  handleInputChange(event) {
    const { field, inModal } = event.currentTarget.dataset
    const value = event.target.value
    switch (field) {
      case 'remarks':
        this.remarks = value
        break
      case 'decisionRemarks':
        this.decisionRemarks = value
        break
      case 'finalRemarkValue':
        this.finalRemarkValue = value
        break
      case 'crmIRREditable':
        if (inModal) {
          this._updateSelectedLoanTermGroup({ crmIRREditable: value })
        } else {
          this.crmIRREditable = value
        }
        break
      case 'loanAmountEditable':
        if (inModal) {
          this._updateSelectedLoanTermGroup({ loanAmountEditable: value })
        } else {
          this.loanAmountEditable = value
        }
        break
      default:
        break
    }
  }

  handleActionButtonClick(event) {
    const actionId = event.currentTarget.dataset.actionId
    if (actionId === ACTION_ID_DOWNLOAD_CAM) {
      this.handleDownloadCam()
    }
  }

  handleAssetAccordionToggle(event) {
    const groupId = event.currentTarget.dataset.groupId
    if (!groupId) {
      return
    }
    this.expandedAssetActionGroupId =
      String(this.expandedAssetActionGroupId) === String(groupId) ? null : groupId
  }

  handleAssetActionClick(event) {
    const groupId = event.currentTarget.dataset.groupId
    const actionId = event.currentTarget.dataset.actionId
    const group = this._findLoanTermGroup(groupId)
    if (!group) {
      return
    }

    switch (actionId) {
      case ACTION_ID_INSURANCE:
        this.handleInsuranceRecompute(group)
        break
      case ACTION_ID_PAYIN:
        this.handleChangePayinPayout(group)
        break
      case ACTION_ID_SCHEDULE:
        this.handleInstallmentSchedule(group)
        break
      default:
        break
    }
  }

  _findLoanTermGroup(groupId) {
    if (!groupId) {
      return null
    }
    return (
      this.loanTermGroups.find((group) => String(group.id) === String(groupId)) || null
    )
  }

  _buildAssetModalProps(group) {
    return {
      recordId: this._recordId,
      lineItemId: group?.lineItemId || null,
      assetId: group?.assetId || null,
      applicationLineItemId: group?.lineItemId || null
    }
  }

  handleInsuranceRecompute(group) {
    this._pendingAddInsurance = true
    this._openIntegrationModal(['Insurance Recommendation API'], null)
    const modalProps = this._buildAssetModalProps(group)
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.integrationCurrentStageIndex = 1
      this.integrationStatus = 'success'
      this.integrationSuccessMessage = 'Insurance Recommendation completed successfully.'
      this.showIntegrationModal = false
      this.dynamicComponentName = 'addInsuranceModal'
      this.dynamicComponentProps = modalProps
      this.showDynamicModal = true
    }, 2000)
  }

  handleChangePayinPayout(group) {
    this.dynamicComponentName = 'payInPayOutModal'
    this.dynamicComponentProps = this._buildAssetModalProps(group)
    this.showDynamicModal = true
  }

  async handleInstallmentSchedule(group) {
    const interestRate = this._resolveInterestRateForGroup(group)
    if (!interestRate || interestRate <= 0) {
      this._showToast(
        'Missing Interest Rate',
        'Please enter a valid interest rate for this asset before viewing the installment schedule.',
        'warning'
      )
      return
    }
    await this._createRepaymentScheduleRecords(group)
  }

  async handleDownloadCam() {
    const applicantId = this.applicantId
    if (!applicantId) {
      this._showToast('Error', 'Borrower applicant record is required.', 'error')
      return
    }
    try {
      const data = await getFormRenderData({
        applicantId,
        formName: FORM_CAM
      })
      this.pdfRenderDocumentChecklistId = data.documentChecklistId
      this.pdfRenderModalProps = {
        templateId: data.templateId,
        inputJSON: data.inputJSON || {},
        recordId: data.documentChecklistId,
        fileName: data.fileName,
        showPreview: true,
        hideSignButton: true
      }
      this.showPdfRenderModal = true
    } catch (error) {
      this._showToast(
        'Error',
        error?.body?.message || error?.message || 'Failed to initiate CAM document download.',
        'error'
      )
    }
  }

  handlePdfRenderModalClose() {
    this.showPdfRenderModal = false
    this.pdfRenderDocumentChecklistId = null
    this.pdfRenderModalProps = {}
  }

  async _createRepaymentScheduleRecords(group) {
    if (!this.isStagePast) {
      try {
        await createRepaymentSchedule({
          jsonData: JSON.stringify(this._buildRepaymentSchedulePayload(group))
        })
      } catch (error) {
        console.error('[approvalLogPage] _createRepaymentScheduleRecords', error)
        this._showToast('Error', 'Error while creating Repayment Schedule records', 'error')
        return
      }
    }
    this.dynamicComponentName = 'installmentSchedue'
    this.dynamicComponentProps = this._buildAssetModalProps(group)
    this.showDynamicModal = true
  }

  _buildRepaymentSchedulePayload(group) {
    const terms = group?.loanTerms || this.loanTerms
    return {
      applicationId: this._recordId,
      applicationLineItemId: group?.lineItemId || null,
      loanAmount: this._resolveLoanAmountForGroup(group),
      interestRate: this._resolveInterestRateForGroup(group),
      tenure: this._resolveTenureForGroup(group),
      emiAmount: this._toNumber(terms.monthlyEMI),
      installmentType: 'equated',
      firstEmiDate: group?.firstEmiDueDate || this.firstEmiDueDate || ''
    }
  }

  _resolveLoanAmountForGroup(group) {
    const editable = this._toNumber(group?.loanAmountEditable)
    if (editable > 0) {
      return editable
    }
    return this._toNumber(group?.loanTerms?.loanAmount)
  }

  _resolveInterestRateForGroup(group) {
    const editable = this._toNumber(group?.crmIRREditable)
    if (editable > 0) {
      return editable
    }
    return this._toNumber(group?.loanTerms?.crmIRR)
  }

  _resolveTenureForGroup(group) {
    const tenure = parseInt(String(group?.loanTerms?.loanTenure ?? ''), 10)
    return Number.isFinite(tenure) && tenure > 0 ? tenure : 0
  }

  _resolveLoanAmount() {
    return this._resolveLoanAmountForGroup(this.loanTermGroups[0])
  }

  _resolveInterestRate() {
    return this._resolveInterestRateForGroup(this.loanTermGroups[0])
  }

  _resolveTenure() {
    return this._resolveTenureForGroup(this.loanTermGroups[0])
  }

  _toNumber(value) {
    const parsed = parseFloat(String(value ?? '').replace(/,/g, ''))
    return Number.isFinite(parsed) ? parsed : 0
  }

  handleForwardProposalChange(event) {
    this.forwardProposal = this._readEventValue(event)
    if (this.forwardProposal !== FORWARD_PROPOSAL_YES) {
      this.selectedForwardTo = ''
      this.remarks = ''
    }
  }

  async handleForwardClick() {
    if (this.isForwardDisabled || !this._recordId) {
      return
    }

    this.isSavingForward = true
    try {
      const result = await savePageData({
        apexClassName: APEX_CLASS,
        apexMethodName: ACTION_CREATE_FORWARD_LOG,
        recordId: this._recordId,
        params: {
          forwardToRole: this.selectedForwardTo,
          remarks: this.remarks.trim()
        }
      })

      if (result?.isSuccess !== true) {
        this._showToast('Error', result?.message || MSG_FORWARD_SAVE_FAILED, 'error')
        return
      }

      this.selectedForwardTo = ''
      this.remarks = ''
      await this._loadApprovalLogs()
      this._showToast('Success', MSG_FORWARD_SAVE_SUCCESS, 'success')
    } catch (error) {
      console.error('[approvalLogPage] handleForwardClick', error)
      this._showToast(
        'Error',
        error?.body?.message || error?.message || MSG_FORWARD_SAVE_FAILED,
        'error'
      )
    } finally {
      this.isSavingForward = false
    }
  }

  handleConditionFieldChange(event) {
    const conditionId = event.currentTarget.dataset.id
    const { field } = event.currentTarget.dataset
    if (!conditionId || !field) {
      return
    }
    const value = field === 'remarks' ? event.target.value : this._readEventValue(event)
    this._updateApprovalCondition(conditionId, { [field]: value })
  }

  handleSubmitCondition(event) {
    const conditionId = event.currentTarget.dataset.id
    this._updateApprovalCondition(conditionId, {
      isEditable: false,
      isSubmitted: true
    })
  }

  async handleCibilValidityChange(event) {
    const value = this._readEventValue(event)
    this.cibilValidityOption = value
    if (value === CIBIL_CONSENT_YES) {
      const verifyTarget = this._formatVerifyPhone(this.borrowerPhone)
      if (!verifyTarget) {
        this._showToast(
          'Mobile Not Found',
          'Borrower mobile number is not available for CIBIL consent verification.',
          'warning'
        )
        this.cibilValidityOption = FORWARD_PROPOSAL_NO
        return
      }

      this._lastActionFieldKey = 'contactNumber'
      this._cibilOtpFlow = true

      const otpReady = await this.generateMobileOTP()
      if (!otpReady) {
        this._cibilOtpFlow = false
        this.cibilValidityOption = FORWARD_PROPOSAL_NO
      }
    }
  }

  handleOpenDynamicComponentModal(event) {
    const { componentName, ...extraProps } = event.detail || {}
    if (this._cibilOtpFlow) {
      extraProps.modalHeader = 'CIBIL Consent Verification'
      extraProps.headerName = 'CIBIL Consent Verification'
      extraProps.cibilMode = true
      this._cibilOtpFlow = false
    }
    this.dynamicComponentName = componentName || ''
    this.dynamicModalHeader = extraProps?.modalHeader || ''
    this.dynamicComponentProps = extraProps
    this.showDynamicModal = !!this.dynamicComponentName
  }

  /** Aliases used by sendPhoneOTPAPI / otpVerification handlers (ctx interface). */
  get contactNumber() {
    const digits = String(this.borrowerPhone || '').replace(/\D/g, '')
    return digits.length > 10 ? digits.slice(-10) : digits
  }

  get contactInfoFieldValues() {
    return { contactNumber: this._formatVerifyPhone(this.borrowerPhone) }
  }

  updateFieldValue(field, value) {
    if (field === 'phoneOTPErrorMessage' && value) {
      this._showToast('Error', value, 'error')
    }
  }

  setActionState(actionKey, status) {
    if (actionKey === 'contactNumber' && status === 'success') {
      this.cibilVerified = true
    }
  }

  async generateMobileOTP() {
    try {
      this._openIntegrationModal(['Generating OTP'], null)

      const result = await generatePhoneOTP({
        applicantId: this.applicantId,
        phoneNumber: this.contactNumber
      })
      if (!result?.success) {
        this._showToast('Error', result?.message || 'Failed to generate OTP.', 'error')
        this.integrationStatus = 'error'
        this.integrationErrorMessage = result?.message || 'Failed to generate OTP.'
        return false
      }

      await invokeHandler('sendPhoneOTPAPI', 'onAction', this).then(() => {
        this.showIntegrationModal = false
        invokeHandler('otpVerification', 'onAction', this)
      })
      return true
    } catch (err) {
      this.integrationStatus = 'error'
      this.integrationErrorMessage = err?.message || 'Failed to generate OTP.'
      console.error('[approvalLogPage] generateMobileOTP failed:', err)
      this._showToast('Error', err?.message || 'Failed to generate OTP.', 'error')
      return false
    }
  }

  handleModalClose() {
    const wasOtpFlow = this.dynamicComponentName === 'otpVerification'
    const wasPayInPayOut = this.dynamicComponentName === 'payInPayOutModal'
    const cibilModalHeader = this.dynamicModalHeader
    this.showDynamicModal = false
    this.dynamicComponentName = ''
    this.dynamicComponentProps = {}
    this.dynamicModalHeader = ''
    if (wasPayInPayOut) {
      this._loadApprovalLogs()
      this._loadLoanTermGroups()
    }
    if (wasOtpFlow && cibilModalHeader === 'CIBIL Consent Verification') {
      this._pendingCibilVerification = false
      this.cibilValidityOption = FORWARD_PROPOSAL_NO
    }
  }

  handleOtpVerified(event) {
    if (event.detail?.otpType === 'email') {
      this.showDynamicModal = false
      this.dynamicComponentName = ''
      this.dynamicComponentProps = {}
      this.dynamicModalHeader = ''
      return
    }

    const wasOtpFlow = this.dynamicComponentName === 'otpVerification'
    if (wasOtpFlow && event.detail?.otpType === 'mobile') {
      this.showDynamicModal = false
      this.dynamicComponentName = ''
      this.dynamicComponentProps = {}
      this.dynamicModalHeader = ''
      this._pendingCibilVerification = true
      this.cibilVerified = true
      this._openIntegrationModal(['CIBIL Bureau API'], null)
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => {
        this.integrationCurrentStageIndex = 1
        this.integrationStatus = 'success'
        this.integrationSuccessMessage = 'CIBIL Bureau API completed successfully.'
      }, 2000)
    }
  }

  handleInsurancePremiumReceived(event) {
    const totalPremium = event?.detail?.totalPremium
    if (totalPremium && totalPremium > 0) {
      this._loadApprovalLogs()
      this._loadLoanTermGroups()
    }
  }

  handleIntegrationModalClose(event) {
    this.showIntegrationModal = false
    if (this._pendingCibilVerification) {
      this._pendingCibilVerification = false
      this.cibilVerified = true
    }
    if (this._pendingAddInsurance) {
      this._pendingAddInsurance = false
      const totalPremium = event?.detail?.totalPremium
      if (totalPremium && totalPremium > 0) {
        this._loadApprovalLogs()
        this._loadLoanTermGroups()
      }
    }
  }

  handleIntegrationRetry() {
    this.integrationStatus = 'loading'
    this.integrationCurrentStageIndex = 0
    this.integrationErrorMessage = ''
    if (this._integrationRetryFn) {
      this._integrationRetryFn()
    }
  }

  _openIntegrationModal(stages, retryFn) {
    this.integrationStages = stages
    this.integrationStatus = 'loading'
    this.integrationCurrentStageIndex = 0
    this.integrationSuccessMessage = ''
    this.integrationErrorMessage = ''
    this._integrationRetryFn = retryFn
    this.showIntegrationModal = true
  }

  _validateCibilConsent() {
    if (this.showCibilSection) {
      this._showToast(
        'CIBIL Expired',
        'The bureau report has expired. Please retrigger CIBIL consent to move ahead.',
        'warning'
      )
      return false
    }
    return true
  }

  async _validateAllDeviationsApproved() {
    if (!this._recordId) {
      return false
    }

    try {
      const result = await getPageData({
        apexClassName: DEVIATION_APEX_CLASS,
        apexMethodName: ACTION_GET_DEVIATIONS,
        recordId: this._recordId,
        params: {}
      })

      if (result?.isSuccess !== true) {
        this._showToast('Error', result?.message || MSG_DEVIATIONS_LOAD_FAILED, 'error')
        return false
      }

      const deviationRows = [
        ...(result.globalDeviations || []),
        ...(result.assetDeviations || [])
      ]

      if (deviationRows.length === 0) {
        return true
      }

      const hasUnapprovedDeviation = deviationRows.some((row) => {
        const approvalStatus = (row.approvalStatus ?? row.Approval_Status__c ?? '').trim()
        return approvalStatus !== APPROVAL_STATUS_APPROVED
      })

      if (hasUnapprovedDeviation) {
        this._showToast('Deviations Pending', MSG_DEVIATIONS_NOT_APPROVED, 'warning')
        return false
      }

      return true
    } catch (error) {
      console.error('[approvalLogPage] _validateAllDeviationsApproved', error)
      this._showToast(
        'Error',
        error?.body?.message || error?.message || MSG_DEVIATIONS_LOAD_FAILED,
        'error'
      )
      return false
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

  _dispatchLosNextStage() {
    const currentViewId = (this.currentViewId || '').trim()
    if (!currentViewId) {
      this._showToast('Navigation Error', MSG_NAVIGATION_VIEW_MISSING, 'error')
      return false
    }

    this._showGlobalLoader('Processing...')

    window.dispatchEvent(
      new CustomEvent(LOS_NEXT_STAGE_EVENT, {
        detail: {
          currentViewId,
          id: currentViewId,
          applicantId: this.applicantId || '',
          currentLoanStageComplete: this.tab || STAGE_TAB_DEFAULT,
          currentStagePhrase: this.stagePhrase || ''
        },
        bubbles: true,
        composed: true
      })
    )

    this.hasNavigatedToNextStage = true

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this._hideGlobalLoaderIfShown()
    }, 1500)

    return true
  }

  async handleNextButton() {
    if (this.isNextDisabled) {
      return
    }

    if (this.isStagePast) {
      return
    }

    if (!this._validateCibilConsent()) {
      return
    }

    if (this._pendingCibilVerification) {
      this._showToast('CIBIL In Progress', MSG_CIBIL_IN_PROGRESS, 'warning')
      return
    }

    this.isNextDisabled = true
    this._showGlobalLoader('Processing...')
    try {
      const deviationsApproved = await this._validateAllDeviationsApproved()
      if (!deviationsApproved) {
        this._hideGlobalLoaderIfShown()
        return
      }
      this._hideGlobalLoaderIfShown()
      this._dispatchLosNextStage()
    } catch (error) {
      console.error('[approvalLogPage] handleNextButton', error)
      this._hideGlobalLoaderIfShown()
    } finally {
      this.isNextDisabled = false
    }
  }

  /** Formats borrower Phone__c for OTP display (e.g. 9876543210 → +91 98765 43210). */
  _formatVerifyPhone(phone) {
    if (!phone) {
      return ''
    }
    const digits = String(phone).replace(/\D/g, '')
    const ten = digits.length > 10 ? digits.slice(-10) : digits
    if (ten.length !== 10) {
      return String(phone).trim()
    }
    return `+91 ${ten.slice(0, 5)} ${ten.slice(5)}`
  }

  _showToast(title, message, variant = 'info') {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    )
  }

  handleSubmitProposalStatus() {
    if (!this._validateCibilConsent()) {
      return
    }
    // Apex integration pending
  }

  handleApproveOffer() {
    if (!this._validateCibilConsent()) {
      return
    }
    // Apex integration pending
  }
}