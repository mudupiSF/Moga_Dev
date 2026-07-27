/**
 * Office FI — Investigations__c / Verification__c via FIInvestigationController.
 */
import { LightningElement, api, track, wire } from 'lwc'
import { CurrentPageReference } from 'lightning/navigation'
import {
  FI_LABEL,
  FI_DECISION_OPTIONS,
  FI_OBSERVATION_OPTIONS,
  SAME_ADDRESS_OPTIONS,
  YES_NO_OPTIONS,
  TOTAL_BUSINESS_STABILITY_OPTIONS,
  BUSINESS_PREMISE_NI_OPTIONS,
  OFFICE_BUSINESS_TYPE_OPTIONS,
  LOCATION_OPTIONS,
  POLITICAL_PHOTO_OPTIONS,
  OFFICE_BUSINESS_SIZE_OPTIONS,
  NAME_TEXT_PATTERN,
  NAME_TEXT_PATTERN_MESSAGE,
  DOC_TYPE_FI_SIGNATURE,
  ACCEPTED_UPLOAD_FORMATS,
  CHUNKY_UPLOAD_ICON_URL,
  MAGIC_UPLOAD_MAX_FILES,
  buildEmptyForm,
  parseFormDataJson,
  resolveProfileFlags,
  getErrorMessage,
  showGlobalLoader,
  hideGlobalLoader,
  dispatchToast,
  readFieldValue,
  applyDecisionFieldChange,
  resolveReadOnly,
  resolveDecisionReadOnly,
  isFiDecisionFinal,
  buildHeaderData,
  loadOfficeFiRecord,
  loadApplicantProfile,
  saveOfficeFi,
  captureFiLocation,
  loadFiDocumentPreviewMap,
  initOrGetFiDocument,
  saveFiSignature,
  parseAddressProofDocuments,
  validateContactFields,
  reportContactFieldValidity,
  sanitizeContactFieldValue,
  buildOfficeDisplayValues,
  buildOfficeContactErrors,
  buildOfficeUiFlags,
  buildOfficeDocumentUi,
  initFilePreviewContext,
  openFiMagicUpload,
  closeFiMagicUpload,
  completeFiMagicUpload,
  applyFiDocumentPreview,
  deleteFiDocument,
  closeEmbedPreview,
  openAddressProofPreview,
  closeFilePreview
} from './officeFIHelper'

export default class OfficeFI extends LightningElement {
  @api recordId
  @api verificationId
  @api applicantId
  @api applicationId
  _renderAsReadOnly = false

  @api
  get renderAsReadOnly() {
    return this._renderAsReadOnly
  }

  set renderAsReadOnly(value) {
    this._renderAsReadOnly = value === true
    this._renderUIAsReadOnly()
  }

  @wire(CurrentPageReference)
  pageRef

  @track isLoading = false
  @track isReadOnly = true
  @track isDecisionReadOnly = true
  @track isNonIndividual = false
  @track isFiLocationCaptured = false
  @track isFiSubmitted = false

  @track headerData = {
    fiStatus: '',
    applicantName: '',
    productType: '',
    fiLabel: FI_LABEL,
    investigationCaseName: ''
  }

  @track fiDecision = ''
  @track remarks = ''
  @track formData = buildEmptyForm()

  @track profileFlags = {
    isGuarantorNonEarning: false,
    isSalaried: false,
    isSEP: false,
    profileOther: false,
    profileAgriculture: false,
    profileRental: false,
    profilePension: false
  }

  @track documentPreviewMap = {}
  @track addressProofDocuments = []
  @track isAddressProofUploaded = false

  @track showMagicUpload = false
  @track showSignatureModal = false
  @track activeUploadChecklistId = ''
  @track signatureDocumentId = ''

  @track showPreviewModal = false
  @track previewContentDocumentId = ''
  @track previewFileType = ''
  @track showFilePreviewer = false
  @track previewContentVersionId = null
  @track previewFileName = ''
  @track previewFileExtension = ''
  @track sessionId = null
  @track vfRoot = null

  investigationId
  activeUploadDocumentType = ''
  _loadSeq = 0

  fiDecisionOptions = FI_DECISION_OPTIONS
  fiObservationOptions = FI_OBSERVATION_OPTIONS
  sameAddressOptions = SAME_ADDRESS_OPTIONS
  yesNoOptions = YES_NO_OPTIONS
  totalBusinessStabilityOptions = TOTAL_BUSINESS_STABILITY_OPTIONS
  businessPremiseNiOptions = BUSINESS_PREMISE_NI_OPTIONS
  officeBusinessTypeOptions = OFFICE_BUSINESS_TYPE_OPTIONS
  locationOptions = LOCATION_OPTIONS
  politicalPhotoOptions = POLITICAL_PHOTO_OPTIONS
  officeBusinessSizeOptions = OFFICE_BUSINESS_SIZE_OPTIONS
  nameTextPattern = NAME_TEXT_PATTERN
  nameTextPatternMessage = NAME_TEXT_PATTERN_MESSAGE
  chunkyUploadIconUrl = CHUNKY_UPLOAD_ICON_URL
  activeMaxFiles = MAGIC_UPLOAD_MAX_FILES
  activeAllowedTypes = ACCEPTED_UPLOAD_FORMATS.join(',')

  get displayValues() {
    return buildOfficeDisplayValues(this.formData, this.fiDecision)
  }

  get contactErrors() {
    return buildOfficeContactErrors(this.formData)
  }

  get isEditable() {
    return !this.isReadOnly
  }

  get showRejectReason() {
    return this.formData.fiObservation !== 'Positive'
  }

  get formLayoutClass() {
    const isFullyDisabled = this.isReadOnly && this.isDecisionReadOnly
    return `form-layout${isFullyDisabled ? ' rfi-page--disabled' : ''}`
  }

  get headerSubtitle() {
    return this.isNonIndividual
      ? 'Field investigation — office / business (non-individual)'
      : 'Field investigation — office / business'
  }

  get isIndividual() {
    return !this.isNonIndividual
  }

  get uiFlags() {
    return buildOfficeUiFlags({
      isReadOnly: this.isReadOnly,
      isDecisionReadOnly: this.isDecisionReadOnly,
      documentPreviewMap: this.documentPreviewMap,
      renderAsReadOnly: this.renderAsReadOnly,
      isNonIndividual: this.isNonIndividual,
      isFiLocationCaptured: this.isFiLocationCaptured,
      isFiSubmitted: this.isFiSubmitted
    })
  }

  get documentUi() {
    return buildOfficeDocumentUi(this.documentPreviewMap, this.isEditable, this.isNonIndividual)
  }

  connectedCallback() {
    initFilePreviewContext(this)
    this.loadData()
  }

  async loadData() {
    const loadSeq = ++this._loadSeq
    this.isLoading = true
    showGlobalLoader('Loading office FI...')
    try {
      const { recordId, verificationId } = this._resolveLoadIds()
      const { result } = await loadOfficeFiRecord({
        recordId,
        verificationId,
        applicantId: this.applicantId,
        applicationId: this.applicationId
      })

      if (loadSeq !== this._loadSeq) {
        return
      }

      if (!result) {
        dispatchToast(this, 'Info', 'No office FI investigation found.', 'info')
        return
      }

      this._applyLoadResult(result)
      await this._loadDocumentPreviewInfo()

      if (this.applicantId) {
        const profile = await loadApplicantProfile(this.applicantId)
        if (loadSeq !== this._loadSeq) {
          return
        }
        this.profileFlags = resolveProfileFlags(profile?.category, profile?.subBucket)
      }
    } catch (error) {
      if (loadSeq !== this._loadSeq) {
        return
      }
      dispatchToast(this, 'Error', getErrorMessage(error), 'error')
    } finally {
      if (loadSeq === this._loadSeq) {
        this._renderUIAsReadOnly()
        this.isLoading = false
        hideGlobalLoader()
      }
    }
  }

  _renderUIAsReadOnly() {
    if (this.renderAsReadOnly === true) {
      this.isReadOnly = true
    }
  }

  _applyLoadResult(result) {
    this.investigationId = result.investigationId
    this.verificationId = result.verificationId
    this.applicantId = result.applicantId || this.applicantId
    this.applicationId = result.applicationId || this.applicationId
    this.formData = { ...buildEmptyForm(), ...parseFormDataJson(result.formDataJson) }
    if (result.isNonIndividual === true) {
      this.formData = {
        ...this.formData,
        applicantDisplayName: result.applicantName || this.formData.applicantDisplayName || '',
        productTypeDisplay: result.productType || this.formData.productTypeDisplay || '',
        investigationCaseName: result.investigationCaseName || this.formData.investigationCaseName || '',
        fiStatusDisplay: result.fiStatus || this.formData.fiStatusDisplay || ''
      }
    }
    this.fiDecision = result.fiDecision || ''
    this.remarks = result.remarks || ''
    this.headerData = buildHeaderData(result)
    this.isNonIndividual = result.isNonIndividual === true
    this.isReadOnly = this.renderAsReadOnly === true || resolveReadOnly(result)
    this.isDecisionReadOnly = this.renderAsReadOnly === true || resolveDecisionReadOnly(result)
    this.isFiLocationCaptured = Boolean(this.formData.fiLatitude && this.formData.fiLongitude)
    this.isFiSubmitted = result?.isSubmitted === true
    this.profileFlags = resolveProfileFlags(result.category, result.profile)
    this.addressProofDocuments = parseAddressProofDocuments(result)
    this.isAddressProofUploaded = result?.isAddressProofUploaded === true
  }

  async _loadDocumentPreviewInfo() {
    try {
      this.documentPreviewMap = await loadFiDocumentPreviewMap(this)
    } catch (error) {
      this.documentPreviewMap = {}
    }
  }

  _resolveLoadIds() {
    return {
      recordId: this.recordId || this.pageRef?.state?.c__recordId || null,
      verificationId: this.verificationId || this.pageRef?.state?.c__verificationId || null
    }
  }

  handleFieldChange(event) {
    if (this.isReadOnly) {
      return
    }
    const { name, value: rawValue } = readFieldValue(event)
    if (!name) {
      return
    }
    const value = sanitizeContactFieldValue(name, rawValue)
    if (event.target?.value !== undefined && event.target.value !== value) {
      event.target.value = value
    }
    this.formData = name === 'fiObservation' && value === 'Positive'
      ? { ...this.formData, [name]: value, rejectReason: '' }
      : { ...this.formData, [name]: value }
  }

  handleContactFieldBlur(event) {
    const { name } = readFieldValue(event)
    if (name !== 'phoneNumber' && name !== 'mobile') {
      return
    }
    const validation = validateContactFields(this.formData)
    reportContactFieldValidity(this.template, validation)
  }

  _validateContactFieldsBeforeSave() {
    const validation = validateContactFields(this.formData)
    reportContactFieldValidity(this.template, validation)
    if (!validation.ok) {
      dispatchToast(this, 'Error', validation.message, 'error')
      return false
    }
    return true
  }

  handleDecisionFieldChange(event) {
    applyDecisionFieldChange(this, event)
  }

  async handleSave(submittedByFiUser) {
    await saveOfficeFi(this, submittedByFiUser)
    dispatchToast(this, 'Success', 'Office FI saved successfully.', 'success')
    await this.loadData()
  }

  async handleSaveClick() {
    if (!this._validateContactFieldsBeforeSave()) {
      return
    }
    try {
      this.isLoading = true
      await this.handleSave(false)
    } catch (error) {
      dispatchToast(this, 'Error', getErrorMessage(error), 'error')
    } finally {
      this.isLoading = false
    }
  }

  async handleSubmitClick() {
    if (!this._validateContactFieldsBeforeSave()) {
      return
    }
    try {
      this.isLoading = true
      await this.handleSave(true)
    } catch (error) {
      dispatchToast(this, 'Error', getErrorMessage(error), 'error')
    } finally {
      this.isLoading = false
    }
  }

  async handleSaveDecisionClick() {
    if (!isFiDecisionFinal(this.fiDecision)) {
      dispatchToast(this, 'Error', 'Select Accepted or Rejected before submitting.', 'error')
      return
    }
    try {
      this.isLoading = true
      await saveOfficeFi(this, false)
      dispatchToast(this, 'Success', 'FI decision saved.', 'success')
      await this.loadData()
    } catch (error) {
      dispatchToast(this, 'Error', getErrorMessage(error), 'error')
    } finally {
      this.isLoading = false
    }
  }

  async handleCaptureFiLocation() {
    if (this.uiFlags.captureLocationDisabled) {
      return
    }
    this.isLoading = true
    await captureFiLocation(this, (latitude, longitude, saveResult) => {
      if (this.isNonIndividual) {
        this.formData = {
          ...this.formData,
          fiLatitude: String(latitude),
          fiLongitude: String(longitude)
        }
      } else {
        this.formData = {
          ...this.formData,
          kycLatitude: saveResult?.kycLatitude || String(latitude),
          kycLongitude: saveResult?.kycLongitude || String(longitude),
          fiLatitude: String(latitude),
          fiLongitude: String(longitude),
          coordinatesDistance: saveResult?.coordinatesDistance ?? this.formData.coordinatesDistance,
          coordinatesVerified: saveResult?.coordinatesVerified ?? this.formData.coordinatesVerified
        }
      }
      this.isFiLocationCaptured = true
    })
    this.isLoading = false
  }

  async handleSignatureUploadClick() {
    if (this.isReadOnly || !this.applicationId || !this.applicantId) {
      dispatchToast(this, 'Error', 'Applicant and application are required before capturing signature.', 'error')
      return
    }

    this.isLoading = true
    try {
      const documentId = await initOrGetFiDocument(this, DOC_TYPE_FI_SIGNATURE)
      if (!documentId) {
        dispatchToast(this, 'Error', 'Unable to prepare signature capture.', 'error')
        return
      }
      this.signatureDocumentId = documentId
      this.showSignatureModal = true
    } catch (error) {
      dispatchToast(this, 'Error', getErrorMessage(error), 'error')
    } finally {
      this.isLoading = false
    }
  }

  handleCloseSignatureModal() {
    this.showSignatureModal = false
  }

  handleSignatureSave() {
    this.template.querySelector('c-capture-signature')?.handleSaveClick()
  }

  handleSignatureClear() {
    this.template.querySelector('c-capture-signature')?.handleClearClick()
  }

  async handleSignatureCapture(event) {
    const { documentId, base64Data, fileName } = event.detail || {}
    if (!documentId || !base64Data) {
      dispatchToast(this, 'Error', 'Signature data is missing.', 'error')
      return
    }

    this.showSignatureModal = false
    this.isLoading = true
    try {
      await saveFiSignature(documentId, base64Data, fileName, this.investigationId)
      await this._loadDocumentPreviewInfo()
      dispatchToast(this, 'Success', 'Signature saved successfully.', 'success')
    } catch (error) {
      dispatchToast(this, 'Error', getErrorMessage(error), 'error')
    } finally {
      this.isLoading = false
    }
  }

  handleDocumentUploadClick(event) {
    openFiMagicUpload(this, event.currentTarget.dataset.documentType)
  }

  handleMagicUploadClose() {
    closeFiMagicUpload(this)
  }

  stopPropagationDv(event) {
    event.stopPropagation()
  }

  // Record whether the mouse press began on the backdrop itself, so a text
  // selection started inside the dialog (and released over the backdrop) does
  // not get treated as a backdrop click and close the modal.
  handleOverlayMouseDown(event) {
    this._overlayMouseDownOnSelf = event.target === event.currentTarget
  }

  handleOverlayClick(event) {
    if (event.target === event.currentTarget && this._overlayMouseDownOnSelf) {
      this.handleMagicUploadClose()
    }
    this._overlayMouseDownOnSelf = false
  }

  async handleMagicUploadComplete(event) {
    await completeFiMagicUpload(this, event, () => this._loadDocumentPreviewInfo())
  }

  handleDocumentPreviewClick(event) {
    applyFiDocumentPreview(this, event.currentTarget.dataset.documentType)
  }

  async handleDocumentDeleteClick(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    await deleteFiDocument(this, event.currentTarget?.dataset?.documentType, () => this._loadDocumentPreviewInfo())
  }

  handleEmbedPreviewClose() {
    closeEmbedPreview(this)
  }

  handleAddressProofPreview(event) {
    openAddressProofPreview(this, event.currentTarget.dataset.docid)
  }

  handleFilePreviewClose(event) {
    closeFilePreview(this, event)
  }
}