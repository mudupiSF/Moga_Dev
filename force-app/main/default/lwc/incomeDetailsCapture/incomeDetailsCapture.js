import { LightningElement, api, track } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import { invokeHandler } from 'c/clientLayerHelper'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'

const APEX_CLASS = 'IncomeDetailsCaptureController'
const ACTION_FETCH_INCOME_DETAILS_CONTEXT = 'fetchIncomeDetailsContext'
const ACTION_GET_DECLARED_INCOME_DETAILS = 'getDeclaredIncomeDetails'
const ACTION_SAVE_DECLARED_INCOME_DETAILS = 'saveDeclaredIncomeDetails'
const ACTION_UPSERT_DECLARED_INCOME_DOCUMENT = 'upsertDeclaredIncomeDocument'
const ACTION_DELETE_DECLARED_INCOME_DOCUMENT = 'deleteDeclaredIncomeDocument'

const LOS_NEXT_STAGE_EVENT = 'losnextstage'
const METHOD_MOBILE = 'mobileVerification'
const METHOD_BANK = 'bankStatement'
const METHOD_DECLARED = 'declaredIncome'
const DECLARED_INCOME_ACCEPTED_FORMATS = ['.pdf', '.png', '.jpg', '.jpeg']
const BANK_STATEMENT_ACCEPTED_FORMATS = ['.pdf']
const UPDATE_ON_OFFER_ENGINE = 'updateLineItemOnOfferEngine'
const STAGE_TITLE = 'Income and Banking Details'

const isNonIndividualApplicationType = (value) => {
  const v = (value || '').trim().toLowerCase().replace(/[\s\-_]/g, '')
  return v === 'nonindividual' || v === 'ni'
}

export default class IncomeDetailsCapture extends LightningElement {
  _recordId
  _applicantId

  @api currentViewId
  @api stagePhrase = ''
  @api tab = ''
  @api applicantType = ''

  _applicantName = ''
  _isStagePast = false
  @api
  set isStagePast(value) {
    this._isStagePast = value === true || value === 'true'
  }
  get isStagePast() {
    return this._isStagePast
  }

  @api
  get applicantName() {
    return this._applicantName
  }
  set applicantName(value) {
    this._applicantName = (value || '').trim()
  }

  get isReadOnlyScreen() {
    return this.isStagePast
  }

  selectedMethod = METHOD_MOBILE
  primaryMethod = null
  applicantIncomeId = null

  mobileVerificationForm = {
    mobileNumber: '',
    status: 'Not started'
  }
  bankStatementForm = {
    mobileNumber: '',
    status: 'Not started'
  }
  bankStatementDocument = null

  declaredIncomeForm = {
    consolidatedYearlyIncome: '',
    status: 'Not started'
  }
  declaredIncomeDocument = null

  nextBtnDisabled = false
  disableDeclaredIncomeFields = false
  isMobileVerificationPanelOpen = true
  isBankStatementPanelOpen = true
  isDeclaredIncomePanelOpen = true

  @track isLoading = false
  @track offerEngineConfig
  productType = null
  _loadSeq = 0
  applicationType = null
  showNetworthAndFleetSection = false
  finalTermId = null
  assetId = null

  get isAddIncomeSourceDisabled() {
    return this.isReadOnlyScreen
  }

  get nextButtonClass() {
    if (this.nextBtnDisabled) {
      return 'id-primary-btn id-button-disabled'
    }
    return 'id-primary-btn'
  }

  get isShowOfferButtonDisabled() {
    return this.primaryMethod !== METHOD_DECLARED
  }

  get declaredIncomeAcceptedFormats() {
    return DECLARED_INCOME_ACCEPTED_FORMATS
  }

  get bankStatementAcceptedFormats() {
    return BANK_STATEMENT_ACCEPTED_FORMATS
  }

  get isMobileVerificationSelected() {
    return this.selectedMethod === METHOD_MOBILE
  }

  get isBankStatementSelected() {
    return this.selectedMethod === METHOD_BANK
  }

  get mobileVerificationChevronIcon() {
    return this.isMobileVerificationPanelOpen ? 'utility:chevrondown' : 'utility:chevronright'
  }

  get bankStatementChevronIcon() {
    return this.isBankStatementPanelOpen ? 'utility:chevrondown' : 'utility:chevronright'
  }

  get mobileVerificationPanelClass() {
    return this.isMobileVerificationPanelOpen ? 'id-panel id-panel-open' : 'id-panel'
  }

  get bankStatementPanelClass() {
    return this.isBankStatementPanelOpen ? 'id-panel id-panel-open' : 'id-panel'
  }

  get mobileVerificationPanelTriggerClass() {
    return this.isMobileVerificationPanelOpen
      ? 'id-panel-header id-panel-trigger id-panel-trigger-open'
      : 'id-panel-header id-panel-trigger'
  }

  get bankStatementPanelTriggerClass() {
    return this.isBankStatementPanelOpen
      ? 'id-panel-header id-panel-trigger id-panel-trigger-open'
      : 'id-panel-header id-panel-trigger'
  }

  get mobileStatusClass() {
    return this.getStatusClass(this.mobileVerificationForm.status)
  }

  get bankStatusClass() {
    return this.getStatusClass(this.bankStatementForm.status)
  }

  get isSendMobileLinkDisabled() {
    return this.isReadOnlyScreen || !this.isValidMobileNumber(this.mobileVerificationForm.mobileNumber)
  }

  get isSendBankLinkDisabled() {
    return this.isReadOnlyScreen || !this.isValidMobileNumber(this.bankStatementForm.mobileNumber)
  }

  get hasBankStatementDocument() {
    return !!this.bankStatementDocument?.fileName
  }

  get bankStatementDocumentName() {
    return this.bankStatementDocument?.fileName || ''
  }

  get showBankStatementUploadInput() {
    return !this.hasBankStatementDocument && !this.isReadOnlyScreen
  }

  get showBankStatementDocumentDelete() {
    return this.hasBankStatementDocument && !this.isReadOnlyScreen
  }

  get isDeclaredIncomeLocked() {
    const status = String(this.declaredIncomeForm?.status || '').toLowerCase()
    return this.isReadOnlyScreen || this.disableDeclaredIncomeFields || status.includes('saved')
  }

  get hasDeclaredIncomeDocument() {
    return !!this.declaredIncomeDocument?.fileName
  }

  get declaredIncomeDocumentName() {
    return this.declaredIncomeDocument?.fileName || ''
  }

  get showDeclaredIncomeUploadInput() {
    return !this.hasDeclaredIncomeDocument && !this.isDeclaredIncomeLocked
  }

  get showDeclaredIncomeDocumentDelete() {
    return this.hasDeclaredIncomeDocument && !this.isDeclaredIncomeLocked
  }

  get isSaveDeclaredIncomeDisabled() {
    const val = this.declaredIncomeForm.consolidatedYearlyIncome
    const numVal = typeof val === 'number' ? val : (val !== '' && val != null ? parseFloat(val) : null)
    return this.isDeclaredIncomeLocked
      || numVal == null
      || isNaN(numVal)
      || numVal < 0
      || !this.hasDeclaredIncomeDocument
  }

  get declaredIncomeChevronIcon() {
    return this.isDeclaredIncomePanelOpen ? 'utility:chevrondown' : 'utility:chevronright'
  }

  get declaredIncomePanelClass() {
    return this.isDeclaredIncomePanelOpen ? 'id-panel id-panel-open' : 'id-panel'
  }

  get declaredIncomePanelTriggerClass() {
    return this.isDeclaredIncomePanelOpen ? 'id-panel-header id-panel-trigger id-panel-trigger-open' : 'id-panel-header id-panel-trigger'
  }

  get declaredStatusClass() {
    return this.getStatusClass(this.declaredIncomeForm.status)
  }

  get methodOptions() {
    return [
      {
        key: METHOD_MOBILE,
        label: 'Using mobile number',
        description: 'Fast OTP flow to fetch consent-linked income data.',
        iconName: 'utility:call',
        className: this.getMethodClass(METHOD_MOBILE),
        isPrimary: this.primaryMethod === METHOD_MOBILE,
        isDisabled: false
      },
      {
        key: METHOD_BANK,
        label: 'Using bank statement',
        description: 'Customer uploads a PDF via secure link sent by SMS.',
        iconName: 'utility:file',
        className: this.getMethodClass(METHOD_BANK),
        isPrimary: this.primaryMethod === METHOD_BANK,
        isDisabled: false
      },
      {
        key: METHOD_DECLARED,
        label: 'Declared income',
        description: 'Capture customer declared income and source.',
        iconName: 'utility:lock',
        className: this.getMethodClass(METHOD_DECLARED),
        isPrimary: this.primaryMethod === METHOD_DECLARED,
        isDisabled: false
      }
    ]
  }

  get isDeclaredIncomeSelected() {
    return this.selectedMethod === METHOD_DECLARED
  }

  get showDeclaredIncomeSave() {
    return !this.isReadOnlyScreen
  }

  get showShowOfferButton() {
    return !this.isReadOnlyScreen
  }

  get headerTitle() {
    const base = this.tab || STAGE_TITLE
    const name = (this._applicantName || '').trim()
    return name ? `${base} (${name})` : base
  }

  get headerSubtitle() {
    return (this.applicantType || '').trim()
  }

  @api
  get recordId() {
    return this._recordId
  }
  set recordId(value) {
    this._recordId = value
    this.loadInitialData()
  }

  @api
  get applicantId() {
    return this._applicantId
  }
  set applicantId(value) {
    if(value !== this._applicantId) {
      this._applicantId = value;
      this.loadInitialData();
    }
  }

  connectedCallback() {
    this.loadInitialData()
  }

  async loadInitialData() {
    if (!this.recordId || !this.applicantId) {
      this.showNetworthAndFleetSection = false
      this.isLoading = false
      return
    }

    const loadSeq = ++this._loadSeq
    this.isLoading = true
    try {
      const ctx = await this.invokeReadAction(ACTION_FETCH_INCOME_DETAILS_CONTEXT)
      if (loadSeq !== this._loadSeq) {
        return
      }
      if (ctx?.product) {
        this.productType = ctx.product
      }
      if (ctx?.applicationType) {
        this.applicationType = ctx.applicationType
      }
      if (ctx?.applicantName) {
        this._applicantName = String(ctx.applicantName).trim()
      }
      this.finalTermId = ctx.finalTermId || null
      this.assetId = ctx.assetId || null
      this.disableDeclaredIncomeFields = this.isReadOnlyScreen || !ctx?.canEdit
      this.applyApplicantPhone(ctx?.applicantPhone)
      this.updateNetworthFleetVisibility()
      await this.loadDeclaredIncomeDetails()
      if (loadSeq !== this._loadSeq) {
        return
      }
    } catch (e) {
      if (loadSeq === this._loadSeq) {
        this.showNetworthAndFleetSection = false
      }
    } finally {
      if (loadSeq === this._loadSeq) {
        this.isLoading = false
      }
    }
  }

  async loadDeclaredIncomeDetails() {
    const result = await this.invokeReadAction(ACTION_GET_DECLARED_INCOME_DETAILS)
    if (!result) {
      return
    }

    this.applicantIncomeId = result.applicantIncomeId || result.document?.applicantIncomeId || null
    this.declaredIncomeForm = {
      consolidatedYearlyIncome: result.consolidatedYearlyIncome ?? '',
      status: result.status || 'Not started'
    }

    const document = result.document || {}
    if (document.found) {
      this.declaredIncomeDocument = {
        fileName: document.fileName || '',
        contentDocumentId: document.contentDocumentId || null,
        contentVersionId: document.contentVersionId || null,
        checklistId: document.checklistId || null
      }
    } else {
      this.declaredIncomeDocument = null
    }

    const isSaved = String(this.declaredIncomeForm.status || '').toLowerCase().includes('saved')
    if (isSaved) {
      this.primaryMethod = METHOD_DECLARED
      this.selectedMethod = METHOD_DECLARED
      this.nextBtnDisabled = false
      this.isDeclaredIncomePanelOpen = false
    } else {
      this.isDeclaredIncomePanelOpen = true
    }
  }

  updateNetworthFleetVisibility() {
    this.showNetworthAndFleetSection = isNonIndividualApplicationType(this.applicationType)
  }

  applyApplicantPhone(phone) {
    const applicantPhone = String(phone || '').trim()
    if (!applicantPhone) {
      return
    }
    this.mobileVerificationForm = {
      ...this.mobileVerificationForm,
      mobileNumber: applicantPhone
    }
    this.bankStatementForm = {
      ...this.bankStatementForm,
      mobileNumber: applicantPhone
    }
  }

  handleMethodSelect(event) {
    const method = event.currentTarget?.dataset?.method
    if (!method) {
      return
    }
    this.selectedMethod = method
    if (method === METHOD_MOBILE) {
      this.isMobileVerificationPanelOpen = true
    } else if (method === METHOD_BANK) {
      this.isBankStatementPanelOpen = true
    } else if (method === METHOD_DECLARED) {
      this.isDeclaredIncomePanelOpen = true
    }
  }

  handleMobileVerificationPanelToggle() {
    this.isMobileVerificationPanelOpen = !this.isMobileVerificationPanelOpen
  }

  handleBankStatementPanelToggle() {
    this.isBankStatementPanelOpen = !this.isBankStatementPanelOpen
  }

  handleDeclaredIncomePanelToggle() {
    this.isDeclaredIncomePanelOpen = !this.isDeclaredIncomePanelOpen
  }

  handleSendMobileLink() {
    if (this.isSendMobileLinkDisabled) {
      return
    }
    this.mobileVerificationForm = {
      ...this.mobileVerificationForm,
      status: 'Link sent'
    }
    this.showToast('Success', 'Verification link sent to the customer.', 'success')
  }

  handleSendBankLink() {
    if (this.isSendBankLinkDisabled) {
      return
    }
    this.bankStatementForm = {
      ...this.bankStatementForm,
      status: 'Link sent'
    }
    this.showToast('Success', 'Upload link sent to the customer.', 'success')
  }

  handleBankStatementUploadFinished(event) {
    const file = event.detail?.files?.[0]
    if (!file) {
      return
    }
    this.bankStatementDocument = {
      fileName: file.name || '',
      contentDocumentId: file.documentId || null,
      contentVersionId: file.contentVersionId || null
    }
    this.bankStatementForm = {
      ...this.bankStatementForm,
      status: 'Uploaded'
    }
    this.showToast('Success', 'Bank statement uploaded successfully.', 'success')
  }

  handleBankStatementDocumentDelete() {
    if (this.isReadOnlyScreen) {
      return
    }
    this.bankStatementDocument = null
    this.bankStatementForm = {
      ...this.bankStatementForm,
      status: 'Not started'
    }
  }

  handleAddIncomeSource() {
    if (this.isAddIncomeSourceDisabled) {
      return
    }
    this.template.querySelector('c-income-source-capture')?.addIncomeSource()
  }

  handleInputChange(event) {
    const group = event.target?.dataset?.group
    const field = event.target?.dataset?.field
    const value = event.detail?.value ?? event.target?.value ?? ''
    if (!group || !field) {
      return
    }

    if (group === METHOD_MOBILE) {
      this.mobileVerificationForm = { ...this.mobileVerificationForm, [field]: value }
    } else if (group === METHOD_BANK) {
      this.bankStatementForm = { ...this.bankStatementForm, [field]: value }
    } else if (group === METHOD_DECLARED) {
      const numVal = field === 'consolidatedYearlyIncome' && value !== '' ? parseFloat(value) : value
      this.declaredIncomeForm = { ...this.declaredIncomeForm, [field]: numVal }
    }
  }

  async handleDeclaredIncomeUploadFinished(event) {
    const file = event.detail?.files?.[0]
    if (!file) {
      return
    }

    try {
      const response = await this.invokeSaveAction(ACTION_UPSERT_DECLARED_INCOME_DOCUMENT, {
        contentDocumentId: file.documentId,
        contentVersionId: file.contentVersionId,
        fileName: file.name
      })
      this.applicantIncomeId = response?.applicantIncomeId || this.applicantIncomeId
      this.declaredIncomeDocument = {
        fileName: file.name || '',
        contentDocumentId: file.documentId || null,
        contentVersionId: file.contentVersionId || null,
        checklistId: response?.checklistId || null
      }
      this.showToast('Success', 'Bank statement uploaded successfully.', 'success')
    } catch (error) {
      this.showToast('Error', error?.body?.message || 'Failed to upload document', 'error')
    }
  }

  async handleDeclaredIncomeDocumentDelete() {
    if (this.isDeclaredIncomeLocked) {
      return
    }

    try {
      await this.invokeSaveAction(ACTION_DELETE_DECLARED_INCOME_DOCUMENT, {
        applicantIncomeId: this.applicantIncomeId
      })
      this.declaredIncomeDocument = null
    } catch (error) {
      this.showToast('Error', error?.body?.message || 'Failed to remove document', 'error')
    }
  }

  async handleMethodAction(event) {
    const action = event.currentTarget?.dataset?.action
    if (action !== 'saveDeclaredIncome') {
      return
    }

    const val = this.declaredIncomeForm.consolidatedYearlyIncome
    const numVal = typeof val === 'number' ? val : (val !== '' && val != null ? parseFloat(val) : null)
    if (numVal == null || isNaN(numVal) || numVal < 0) {
      this.showToast('Validation Error', 'Please enter a valid Consolidated Yearly Income.', 'error')
      return
    }
    if (!this.declaredIncomeDocument) {
      this.showToast('Validation Error', 'Please upload declared income document.', 'error')
      return
    }

    try {
      const response = await this.invokeSaveAction(ACTION_SAVE_DECLARED_INCOME_DETAILS, {
        data: JSON.stringify({
          consolidatedYearlyIncome: numVal
        })
      })
      this.applicantIncomeId = response?.applicantIncomeId || this.applicantIncomeId
      this.declaredIncomeForm = {
        ...this.declaredIncomeForm,
        consolidatedYearlyIncome: response?.consolidatedYearlyIncome ?? numVal,
        status: response?.status || 'Saved'
      }
      this.primaryMethod = METHOD_DECLARED
      this.selectedMethod = METHOD_DECLARED
      this.nextBtnDisabled = false
      this.disableDeclaredIncomeFields = true
      this.isDeclaredIncomePanelOpen = false
      this.showToast('Success', 'Declared income saved successfully.', 'success')
    } catch (error) {
      this.showToast('Error', error?.body?.message || 'Failed to save declared income', 'error')
    }
  }

  handleShowOffer() {
    this.handleNextButton()
  }

  async handleNextButton() {
    if (!this.currentViewId) {
      return
    }

    if (this.isReadOnlyScreen) {
      this.dispatchNextStage()
      return
    }

    //if I am have selected mobile number and Link sent, user can proceed with next
    //same if i am on bank statement, and link sent, I can proceed with next
    //If ai am on declared income, and its saved then I can move to next
    if ((this.isMobileVerificationSelected && this.mobileVerificationForm.status != 'Link sent') || (this.isBankStatementSelected && this.bankStatementForm.status != 'Link sent')) {
      this.showToast('Validation Error', 'Please send link to the customer before proceeding.', 'error')
        return
      }
    const isDeclaredIncomeSaved = String(this.declaredIncomeForm?.status || '').toLowerCase().includes('saved')
    if (!isDeclaredIncomeSaved && this.isDeclaredIncomeSelected) {
      this.showToast('Validation Error', 'Declared income must be completed before proceeding.', 'error')
      return
    }

    try {
      this.offerEngineConfig = {
        recordId: this.recordId,
        applicantId: this.applicantId,
        selectedMethod: this.selectedMethod,
        currentScreen: 'Income Verification',
        abbFlag: true,
        abbValue: null,
        productType: this.productType,
        totalFundedPremium: 600000,
        installmentTypeValue: 'Monthly',
        assetId: this.assetId,
        finalTermId: this.finalTermId
      }
      const offerEngineApiResult = await invokeHandler('onOfferEngineApi', 'onOfferEngineApi', this)
      if (offerEngineApiResult && !offerEngineApiResult.isSuccess) {
        this.showToast('Error', offerEngineApiResult.message || 'Failed to invoke Offer Engine API.', 'error')
        return
      }
      await this.invokeSaveAction(UPDATE_ON_OFFER_ENGINE, {
        applicationId: this.recordId,
        applicationLineItemId: this.finalTermId
      })

      setTimeout(() => {
        this.dispatchNextStage()
      }, 1000)
    } catch (e) {
      this.showToast('Error', e?.body?.message || e?.message || 'Failed to invoke Offer Engine API.', 'error')
    }
  }

  dispatchNextStage() {
    window.dispatchEvent(new CustomEvent('losgloballoader', {
      detail: { show: true, message: 'Processing...' }
    }))
    this.dispatchEvent(
      new CustomEvent(LOS_NEXT_STAGE_EVENT, {
        detail: {
          currentViewId: this.currentViewId,
          applicantId: this.applicantId,
          currentLoanStageComplete: this.tab || 'Income and Banking Details',
          currentStagePhrase: this.stagePhrase || ''
        },
        bubbles: true,
        composed: true
      })
    )
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }))
    }, 1500)
  }

  getMethodClass(key) {
    return this.selectedMethod === key ? 'id-method-card id-method-card-active' : 'id-method-card'
  }

  isValidMobileNumber(value) {
    const digits = String(value || '').replace(/\D/g, '')
    return digits.length >= 10
  }

  getStatusClass(status) {
    const normalized = String(status || '').toLowerCase()
    if (normalized.includes('saved')) {
      return 'id-status-pill id-status-success'
    }
    if (normalized.includes('uploaded')) {
      return 'id-status-pill id-status-progress'
    }
    return 'id-status-pill id-status-default'
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }))
  }

  invokeReadAction(apexMethodName, params = {}) {
    return getPageData({
      apexClassName: APEX_CLASS,
      apexMethodName,
      recordId: this.recordId,
      params: {
        applicantId: this.applicantId,
        ...params
      }
    })
  }

  invokeSaveAction(apexMethodName, params = {}) {
    return savePageData({
      apexClassName: APEX_CLASS,
      apexMethodName,
      recordId: this.recordId,
      params: {
        applicantId: this.applicantId,
        ...params
      }
    })
  }
}