import { LightningElement, api, track } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'
import {
  SECTION_EXPOSURE_DETAILS,
  SECTION_EXTERNAL_EXPOSURE,
  SECTION_SUMMARY,
  BTN_VIEW_LIEN,
  BTN_NEXT,
  BTN_CLOSE,
  SUMMARY_CURRENT,
  SUMMARY_BORROWER,
  SUMMARY_GUARANTOR,
  SUMMARY_TOTAL,
  SUMMARY_FOIR,
  EMPTY_EXPOSURE,
  EMPTY_EXTERNAL_EXPOSURE,
  EMPTY_LIEN,
  LIEN_NOT_AVAILABLE,
  MODAL_LIEN_TITLE,
  COL_EXPOSURE_TYPE,
  COL_DEAL_STAGE,
  COL_DEAL_NO,
  COL_DEAL_DATE,
  COL_PRODUCT,
  COL_STATUS,
  COL_FINANCE_AMT,
  COL_SOH,
  COL_OVER_DUE,
  COL_CURRENT_DEMAND,
  COL_LIEN,
  COL_ACCOUNT_TYPE,
  COL_OWNERSHIP,
  COL_HIGH_CREDIT,
  COL_CURRENT_BALANCE,
  COL_AMOUNT_OVERDUE,
  COL_REASON_OVERDUE,
  COL_FINANCIER,
  COL_LIEN_NO,
  COL_LIEN_TYPE,
  COL_SOURCE_DEAL_NO,
  COL_LIEN_MARKING_PERIOD,
  COL_LIEN_MAKER_DATE,
  COL_LIEN_REQUEST_BY,
  COL_LIEN_MARKING_REASON,
  MSG_NAV_VIEW_ID_MISSING,
  MSG_NAV_STAGE_PHRASE_MISSING,
  TOAST_TITLE_ERROR,
  TOAST_TITLE_NAV,
  MSG_LOAD_FAILED,
  MSG_SAVE_EXPOSURE_SUMMARY_FAILED,
  MSG_GENERIC_ERROR
} from './exposureAnalysisConstants'

const APEX_CLASS = 'ExposureAnalysisController'
const APEX_METHOD_GET = 'getExposureAnalysisData'
const APEX_METHOD_SAVE_EXPOSURE_SUMMARY = 'saveExposureSummary'
const LOS_NEXT_STAGE_EVENT = 'losnextstage'
const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader'

export default class ExposureAnalysisMasterPage extends LightningElement {
  labels = {
    sectionExposureDetails: SECTION_EXPOSURE_DETAILS,
    sectionExternalExposure: SECTION_EXTERNAL_EXPOSURE,
    sectionSummary: SECTION_SUMMARY,
    btnViewLien: BTN_VIEW_LIEN,
    btnNext: BTN_NEXT,
    btnClose: BTN_CLOSE,
    summaryCurrent: SUMMARY_CURRENT,
    summaryBorrower: SUMMARY_BORROWER,
    summaryGuarantor: SUMMARY_GUARANTOR,
    summaryTotal: SUMMARY_TOTAL,
    summaryFoir: SUMMARY_FOIR,
    emptyExposure: EMPTY_EXPOSURE,
    emptyExternalExposure: EMPTY_EXTERNAL_EXPOSURE,
    emptyLien: EMPTY_LIEN,
    lienNotAvailable: LIEN_NOT_AVAILABLE,
    modalLienTitle: MODAL_LIEN_TITLE,
    colExposureType: COL_EXPOSURE_TYPE,
    colDealStage: COL_DEAL_STAGE,
    colDealNo: COL_DEAL_NO,
    colDealDate: COL_DEAL_DATE,
    colProduct: COL_PRODUCT,
    colStatus: COL_STATUS,
    colFinanceAmt: COL_FINANCE_AMT,
    colSoh: COL_SOH,
    colOverDue: COL_OVER_DUE,
    colCurrentDemand: COL_CURRENT_DEMAND,
    colLien: COL_LIEN,
    colAccountType: COL_ACCOUNT_TYPE,
    colOwnership: COL_OWNERSHIP,
    colHighCredit: COL_HIGH_CREDIT,
    colCurrentBalance: COL_CURRENT_BALANCE,
    colAmountOverdue: COL_AMOUNT_OVERDUE,
    colReasonOverdue: COL_REASON_OVERDUE,
    colFinancier: COL_FINANCIER,
    colLienNo: COL_LIEN_NO,
    colLienType: COL_LIEN_TYPE,
    colSourceDealNo: COL_SOURCE_DEAL_NO,
    colLienMarkingPeriod: COL_LIEN_MARKING_PERIOD,
    colLienMakerDate: COL_LIEN_MAKER_DATE,
    colLienRequestBy: COL_LIEN_REQUEST_BY,
    colLienMarkingReason: COL_LIEN_MARKING_REASON
  }

  _recordId

  @api
  get recordId() {
    return this._recordId
  }

  set recordId(value) {
    if (value === this._recordId) {
      return
    }
    this._recordId = value
    this._tryLoadPageData()
  }

  _applicantId

  @api
  get applicantId() {
    return this._applicantId
  }

  set applicantId(value) {
    if (value === this._applicantId) {
      return
    }
    this._applicantId = value
    this._tryLoadPageData()
  }

  @api currentViewId
  @api stagePhrase = ''
  @api tab = ''

  _isStagePast = false

  @api
  set isStagePast(value) {
    this._isStagePast = value === true || value === 'true'
  }

  get isStagePast() {
    return this._isStagePast
  }

  get isReadOnlyScreen() {
    return this._isStagePast
  }

  get isNextDisabled() {
    return this.isLoading || !this.currentViewId
  }

  @track isLoading = false
  @track exposureRows = []
  @track externalExposureRows = []
  @track summary = {
    currentExposure: '₹0',
    existingBorrowerExposure: '₹0',
    existingGuarantorExposure: '₹0',
    totalExposure: '₹0',
    foirPercent: '0'
  }

  @track showLienModal = false
  @track lienRows = []

  _totalExposureToSave = 0

  get hasExposureRows() {
    return this.exposureRows?.length > 0
  }

  get hasExternalExposureRows() {
    return this.externalExposureRows?.length > 0
  }

  get hasLienRows() {
    return this.lienRows?.length > 0
  }

  get exposureSectionTitle() {
    const type = this.applicantType || 'Borrower'
    return `${type} ${SECTION_EXPOSURE_DETAILS.toLowerCase()}`
  }

  applicantType = 'Borrower'

  connectedCallback() {
    this._tryLoadPageData()
  }

  _tryLoadPageData() {
    if (!this._recordId || !this._applicantId) {
      return
    }
    this.loadPageData()
  }

  async loadPageData() {
    if (!this._recordId || !this._applicantId) {
      return
    }

    this.isLoading = true
    try {
      const data = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: APEX_METHOD_GET,
        recordId: this._recordId,
        params: this._baseParams()
      })

      if (!this._isResponseOk(data)) {
        this.showToast(TOAST_TITLE_ERROR, data?.message || MSG_LOAD_FAILED, 'error')
        return
      }

      this.applyPagePayload(data)
    } catch (e) {
      console.error('[exposureAnalysisMasterPage] loadPageData', e)
      this.showToast(TOAST_TITLE_ERROR, this.extractError(e), 'error')
    } finally {
      this.isLoading = false
    }
  }

  mapExposureRows(rows) {
    if (!Array.isArray(rows)) {
      return []
    }
    return rows.map((row) => ({
      id: row.id || row.Id,
      exposureType: row.exposureType ?? row.Exposure_Type__c ?? '',
      dealStage: row.dealStage ?? row.Deal_Stage__c ?? '',
      dealNo: row.dealNo ?? row.Deal_No__c ?? '',
      dealDate: this.formatDealDate(row.dealDate ?? row.Deal_Date__c ?? ''),
      product: row.product ?? row.Type_of_Facility__c ?? '',
      status: row.status ?? row.Status_Flag__c ?? '',
      financeAmt: row.financeAmt ?? row.Finance_Amt__c ?? '',
      soh: row.soh ?? row.SOH__c ?? '',
      overDue: row.overDue ?? row.Over_Due__c ?? '',
      currentDemand: row.currentDemand ?? row.Current_Demand__c ?? '',
      hasLien: row.hasLien === true || row.hasLien === 'true',
      lien: row.lien ? this.mapLienRow(row.lien) : null
    }))
  }

  mapExternalExposureRows(rows) {
    if (!Array.isArray(rows)) {
      return []
    }
    return rows.map((row) => ({
      id: row.id || row.Id,
      accountType:
        row.accountType ?? row.Account_Type_Desc__c ?? row.Account_Type__c ?? '',
      ownership: row.ownership ?? row.Ownership__c ?? '',
      highCredit: row.highCredit ?? row.High_Credit__c ?? '',
      currentBalance: row.currentBalance ?? row.Current_Balance__c ?? '',
      amountOverdue: row.amountOverdue ?? row.Amount_Overdue__c ?? '',
      reasonForOverdue: row.reasonForOverdue ?? row.Reason_for_Overdue__c ?? '',
      financierName: row.financierName ?? row.Financier_Name__c ?? ''
    }))
  }

  formatDealDate(value) {
    if (value == null || value === '') {
      return ''
    }
    const text = String(value)
    if (text.includes('T')) {
      return text.split('T')[0]
    }
    return text.length > 10 ? text.substring(0, 10) : text
  }

  formatCurrency(value) {
    if (value == null || value === '') {
      return '₹0'
    }
    const num = Number(value)
    if (!Number.isFinite(num)) {
      return String(value).startsWith('₹') ? String(value) : `₹${value}`
    }
    return `₹${num.toLocaleString('en-IN')}`
  }

  toNumeric(value) {
    if (value == null || value === '') {
      return 0
    }
    const num = Number(value)
    return Number.isFinite(num) ? num : 0
  }

  handleViewLien(event) {
    const exposureId = event.currentTarget.dataset.id
    if (!exposureId) {
      return
    }

    const exposureRow = this.exposureRows.find((row) => row.id === exposureId)
    if (!exposureRow?.hasLien || !exposureRow.lien) {
      return
    }

    this.lienRows = [exposureRow.lien]
    this.showLienModal = true
  }

  handleCloseLienModal() {
    this.showLienModal = false
    this.lienRows = []
  }

  async handleNext() {
    if (this.isReadOnlyScreen) {
      this.dispatchNextStage()
      return
    }

    this.isLoading = true
    try {
      const result = await savePageData({
        apexClassName: APEX_CLASS,
        apexMethodName: APEX_METHOD_SAVE_EXPOSURE_SUMMARY,
        recordId: this._recordId,
        params: {
          ...this._baseParams(),
          totalExposure: this._totalExposureToSave
        }
      })

      if (!this._isResponseOk(result)) {
        this.showToast(
          TOAST_TITLE_ERROR,
          result?.message || MSG_SAVE_EXPOSURE_SUMMARY_FAILED,
          'error'
        )
        return
      }

      this.dispatchNextStage()
    } catch (e) {
      console.error('[exposureAnalysisMasterPage] handleNext', e)
      this.showToast(TOAST_TITLE_ERROR, this.extractError(e), 'error')
    } finally {
      this.isLoading = false
    }
  }

  dispatchNextStage() {
    const viewId = this.currentViewId
    if (!viewId) {
      this.showToast(TOAST_TITLE_NAV, MSG_NAV_VIEW_ID_MISSING, 'error')
      return
    }

    if (!this.stagePhrase) {
      this.showToast(TOAST_TITLE_NAV, MSG_NAV_STAGE_PHRASE_MISSING, 'error')
      return
    }

    window.dispatchEvent(
      new CustomEvent(LOS_GLOBAL_LOADER_EVENT, {
        detail: { show: true, message: 'Processing...' }
      })
    )

    window.dispatchEvent(
      new CustomEvent(LOS_NEXT_STAGE_EVENT, {
        detail: {
          currentViewId: viewId,
          id: viewId,
          applicantId: this._applicantId,
          currentLoanStageComplete: this.tab || '',
          currentStagePhrase: this.stagePhrase || ''
        },
        bubbles: true,
        composed: true
      })
    )
  }

  _baseParams() {
    return { applicantId: this._applicantId }
  }

  _isResponseOk(response) {
    return response?.isSuccess === true
  }

  applyPagePayload(data) {
    this.applicantType = data.applicantType || 'Borrower'
    this.exposureRows = this.mapExposureRows(data.exposures)
    this.externalExposureRows = this.mapExternalExposureRows(
      data.externalExposures || data.nonIBLExposures
    )
    this._totalExposureToSave = this.toNumeric(data.totalExposure)
    this.summary = {
      currentExposure: this.formatCurrency(data.currentExposure),
      existingBorrowerExposure: this.formatCurrency(data.existingBorrowerExposure),
      existingGuarantorExposure: this.formatCurrency(data.existingGuarantorExposure),
      totalExposure: this.formatCurrency(data.totalExposure),
      foirPercent: data.foirPercent != null ? String(data.foirPercent) : '0'
    }
  }

  mapLienRow(row) {
    if (!row) {
      return null
    }
    return {
      id: row.id || row.Id,
      lienNo: row.lienNo ?? row.Lien_No__c ?? '',
      lienType: row.lienType ?? row.Lien_Type__c ?? '',
      sourceDealNo: row.sourceDealNo ?? row.Source_Deal_No__c ?? '',
      lienMarkingPeriod: this.formatDealDate(
        row.lienMarkingPeriod ?? row.Lien_Marking_Period__c ?? ''
      ),
      lienMakerDate: this.formatDealDate(row.lienMakerDate ?? row.Lien_Maker_Date__c ?? ''),
      lienRequestBy: row.lienRequestBy ?? row.Lien_Request_By__c ?? '',
      lienMarkingReason: row.lienMarkingReason ?? row.Lien_Marking_Reason__c ?? ''
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    )
  }

  extractError(error) {
    return error?.body?.message || error?.message || MSG_GENERIC_ERROR
  }
}