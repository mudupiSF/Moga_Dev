import { LightningElement, api, track } from 'lwc'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import { LOS_GLOBAL_LOADER_EVENT } from './camPageDevConstants'
import {
  buildCarouselState,
  createInitialOffsets,
  handlePaginationNext as paginateNext,
  handlePaginationPrev as paginatePrev,
  resetPagination
} from './paginationHelper'
import {
  normalizeAnnexureRows,
  normalizeApplicantColumns,
  normalizeApplicantDetailSections,
  normalizeApplicantFieldSection,
  normalizeBasicInfoFields,
  normalizeBriefColumns,
  normalizeCreditBureauColumns,
  normalizeDeclarationSections,
  normalizeExposureSections,
  normalizeFieldRows,
  normalizeFiDetailSections,
  normalizeFiWaiverRows,
  normalizeLoanDetailSections,
  normalizeRiskProfileSections
} from './camPageDevHelper'

const APEX_CLASS = 'CAMController'
const APEX_METHOD = 'getCamPageData'
const HARD_CODED_RECORD_ID = 'a0OIn00000CX7j8MAD'
const FI_MODAL_COMPONENTS = new Set(['residenceFI', 'permanentFI', 'officeFI'])

const EMPTY_SECTION_STATE = {
  basicInfoFields: [],
  applicantColumns: [],
  bankAccountColumns: [],
  businessDetailSections: [],
  showBusinessDetailsSection: false,
  beneficiaryIncomeSections: [],
  showBeneficiaryIncomeSection: false,
  pricingLtvFields: [],
  offerEngineFields: [],
  loanDetailSections: [],
  exposureSections: [],
  creditBureauColumns: [],
  creditBureauSectionTitle: 'CIBIL Details',
  permanentFiDetailSections: [],
  fiResidenceDetailSections: [],
  fiOfficeDetailSections: [],
  briefDetails: {},
  briefColumns: [],
  incomeDetailSections: [],
  financialPerformanceSections: [],
  gatingScreeningSection: { fields: [] },
  riskProfileSections: [],
  fiWaiverRows: [],
  declarationSections: [],
  annexureRows: []
}

export default class CamPageDev extends LightningElement {

  _isStagePast = false
  _globalLoaderShown = false

  @track errorMessage = ''
  @track basicInfoFields = []
  @track applicantColumns = []
  @track bankAccountColumns = []
  @track businessDetailSections = []
  @track showBusinessDetailsSection = false
  @track beneficiaryIncomeSections = []
  @track showBeneficiaryIncomeSection = false
  @track pricingLtvFields = []
  @track offerEngineFields = []
  @track loanDetailSections = []
  @track exposureSections = []
  @track creditBureauColumns = []
  @track creditBureauSectionTitle = 'CIBIL Details'
  @track permanentFiDetailSections = []
  @track fiResidenceDetailSections = []
  @track fiOfficeDetailSections = []
  @track briefDetails = {}
  @track briefColumns = []
  @track gatingScreeningSection = { fields: [] }
  @track riskProfileSections = []
  @track fiWaiverRows = []
  @track incomeDetailSections = []
  @track financialPerformanceSections = []
  @track declarationSections = []
  @track annexureRows = []
  @track carouselOffsets = createInitialOffsets()
  @track carouselState = {}

  @track showDynamicComponentModal = false
  @track dynamicComponentName = ''
  @track dynamicComponentProps = {}
  @track dynamicModalHeader = ''

  @track showFilePreviewer = false
  @track previewContentDocumentId = null
  @track previewFileType = null

  @track showLoanAssetModal = false
  @track selectedLoanAsset = null

  get recordId() {
    return HARD_CODED_RECORD_ID
  }

  connectedCallback() {
    this._loadPageData()
    this.carouselState = buildCarouselState(this)
  }

  disconnectedCallback() {
    try {
      document.documentElement.style.overflow = ''
      document.body.style.overflow = ''
    } catch (e) {
      /* non-DOM contexts */
    }
  }

  @api
  set isStagePast(value) {
    this._isStagePast = value === true || value === 'true'
  }

  get isStagePast() {
    return this._isStagePast
  }

  get devBannerLabel() {
    return `DEV MODE — Record ID: ${HARD_CODED_RECORD_ID}`
  }

  get briefSectionTitle() {
    return this.briefDetails?.sectionTitle || 'Brief Details'
  }

  get loanSectionCountLabel() {
    const count = this.loanDetailSections.length
    return count > 1 ? `${count} assets` : ''
  }

  get loanAssetModalTitle() {
    return this.selectedLoanAsset?.listTitle || 'Asset Details'
  }

  get showLoanAssetViabilityButton() {
    return !!this.selectedLoanAsset?.assetId
  }

  get annexureCountLabel() {
    return this.annexureRows.length ? `${this.annexureRows.length}` : ''
  }

  get showFiCurrentSection() {
    return this.fiResidenceDetailSections.length > 0
  }

  get showFiPermanentSection() {
    return this.permanentFiDetailSections.length > 0
  }

  get showFiOfficeSection() {
    return this.fiOfficeDetailSections.length > 0
  }

  get creditBureauSectionAriaLabel() {
    return this.creditBureauSectionTitle || 'Credit bureau details'
  }

  handlePaginationPrev(event) {
    paginatePrev(this, event)
  }

  handlePaginationNext(event) {
    paginateNext(this, event)
  }

  handleLoanAssetViewClick(event) {
    const asset = this._findLoanAsset(event.currentTarget?.dataset?.sectionId)
    if (!asset) {
      return
    }

    this.selectedLoanAsset = asset
    this.showLoanAssetModal = true
    this._syncBodyScroll()
  }

  handleLoanAssetModalClose() {
    this.showLoanAssetModal = false
    this.selectedLoanAsset = null
    this._syncBodyScroll()
  }

  handleLoanAssetViabilityClick() {
    const assetId = this.selectedLoanAsset?.assetId
    if (!assetId) {
      return
    }

    this.showLoanAssetModal = false
    this._openDynamicModal('viabilityCheck', {
      recordId: HARD_CODED_RECORD_ID,
      assetId,
      modalHeader: 'Viability',
      isReadOnly: true,
      allowEditWhenExisting: false
    })
  }

  _findLoanAsset(sectionId) {
    if (!sectionId) {
      return null
    }
    return (this.loanDetailSections || []).find((section) => section.id === sectionId) || null
  }

  async _loadPageData() {
    if (!HARD_CODED_RECORD_ID) {
      this._resetSections()
      return
    }

    this._showGlobalLoader('Loading CAM details...')
    this.errorMessage = ''

    try {
      const data = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: APEX_METHOD,
        recordId: HARD_CODED_RECORD_ID,
        params: {}
      })

      const payload = data || {}
      if (payload.loadError) {
        this.errorMessage = payload.loadError
        this._resetSections()
        return
      }

      this._applyPagePayload(payload)
      this.showLoanAssetModal = false
      this.selectedLoanAsset = null
      this._syncBodyScroll()
      resetPagination(this)
      this.errorMessage = ''
    } catch (error) {
      this.errorMessage = error?.body?.message || error?.message || 'Unable to load CAM page data.'
      this._resetSections()
    } finally {
      this._hideGlobalLoaderIfShown()
    }
  }

  _applyPagePayload(payload) {
    this.basicInfoFields = normalizeBasicInfoFields(payload.basicInfoFields)
    this.applicantColumns = normalizeApplicantColumns(payload.applicantColumns)
    this.bankAccountColumns = normalizeApplicantColumns(payload.bankAccountColumns)
    this.businessDetailSections = normalizeApplicantDetailSections(payload.businessDetailSections)
    this.showBusinessDetailsSection = payload.showBusinessDetailsSection === true
    this.beneficiaryIncomeSections = normalizeApplicantDetailSections(payload.beneficiaryIncomeSections, true)
    this.showBeneficiaryIncomeSection = payload.showBeneficiaryIncomeSection === true
    this.pricingLtvFields = normalizeFieldRows(payload.pricingLtvFields)
    this.offerEngineFields = normalizeFieldRows(payload.offerEngineFields)
    this.loanDetailSections = normalizeLoanDetailSections(payload.loanDetailSections)
    this.exposureSections = normalizeExposureSections(payload.exposureSections)
    this.creditBureauColumns = normalizeCreditBureauColumns(payload.creditBureauColumns)
    this.creditBureauSectionTitle = payload.creditBureauSectionTitle || 'CIBIL Details'
    this.permanentFiDetailSections = normalizeFiDetailSections(payload.permanentFiDetailSections)
    this.fiResidenceDetailSections = normalizeFiDetailSections(payload.fiResidenceDetailSections)
    this.fiOfficeDetailSections = normalizeFiDetailSections(payload.fiOfficeDetailSections)
    this.briefDetails = payload.briefDetails || {}
    this.briefColumns = normalizeBriefColumns(this.briefDetails)
    this.incomeDetailSections = normalizeApplicantDetailSections(payload.incomeDetailSections, true)
    this.financialPerformanceSections = normalizeApplicantDetailSections(
      payload.financialPerformanceSections,
      true
    )
    this.gatingScreeningSection = normalizeApplicantFieldSection(payload.gatingScreeningSection)
    this.riskProfileSections = normalizeRiskProfileSections(payload.riskProfileSections)
    this.fiWaiverRows = normalizeFiWaiverRows(payload.fiWaiverRows)
    this.declarationSections = normalizeDeclarationSections(payload.declarationSections)
    this.annexureRows = normalizeAnnexureRows(payload.annexureRows)

    this.dispatchEvent(new CustomEvent('camdataloaded', { detail: { camData: payload } }))
  }

  _resetSections() {
    Object.assign(this, EMPTY_SECTION_STATE)
    resetPagination(this)
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

  handleViewAbbClick(event) {
    this._openDynamicModal('incomeSourceCapture', {
      recordId: HARD_CODED_RECORD_ID,
      applicantId: event.currentTarget?.dataset?.applicantId || null,
      modalHeader: 'ABB Values',
      isStagePast: true
    })
  }

  handleViewCreditAssessmentClick(event) {
    const applicantId = event.currentTarget?.dataset?.applicantId
    if (!HARD_CODED_RECORD_ID || !applicantId) {
      return
    }

    this._openDynamicModal('captureCreditAssessment', {
      recordId: HARD_CODED_RECORD_ID,
      applicantId,
      isStagePast: true,
      stagePhrase: 'Credit_Assessment_Borrower',
      tab: 'PSL',
      modalHeader: 'PSL',
      renderAsReadOnly: true
    })
  }

  handleViabilityClick(event) {
    if (!HARD_CODED_RECORD_ID) {
      return
    }
    const assetId = event.currentTarget?.dataset?.assetId
    this._openDynamicModal('viabilityCheck', {
      recordId: HARD_CODED_RECORD_ID,
      assetId: assetId || undefined,
      modalHeader: 'Viability',
      isReadOnly: true,
      allowEditWhenExisting: false
    })
  }

  handleCreditReportClick(event) {
    const {
      applicantId,
      reportType,
      reportLabel,
      contentVersionId,
      contentDocumentId,
      fileType
    } = event.currentTarget?.dataset || {}

    if (!HARD_CODED_RECORD_ID || !reportType) {
      return
    }

    if (contentDocumentId) {
      this.previewContentDocumentId = contentDocumentId
      this.previewFileType = fileType || null
      this.showFilePreviewer = true
      return
    }

    this._openDynamicModal('bureauReportViewer', {
      recordId: HARD_CODED_RECORD_ID,
      applicantId: applicantId || undefined,
      reportType,
      contentVersionId: contentVersionId || undefined,
      modalHeader: reportLabel || reportType,
      isReadOnly: true
    })
  }

  _openDynamicModal(componentName, props) {
    if (!HARD_CODED_RECORD_ID) {
      return
    }
    if ((componentName === 'incomeSourceCapture' || componentName === 'kycViewer') && !props?.applicantId) {
      return
    }
    if (FI_MODAL_COMPONENTS.has(componentName)) {
      if (!props?.verificationId) {
        return
      }
    } else if (!props?.recordId) {
      return
    }

    const { modalHeader, ...componentProps } = props || {}
    this.dynamicComponentName = componentName
    this.dynamicComponentProps = componentProps
    this.dynamicModalHeader = modalHeader || ''
    this.showDynamicComponentModal = true
    this._syncBodyScroll()
  }

  handleDynamicComponentModalClose() {
    if (this.dynamicComponentName === 'viabilityCheck' && this.selectedLoanAsset) {
      this.showLoanAssetModal = true
    }

    this.showDynamicComponentModal = false
    this.dynamicComponentName = ''
    this.dynamicComponentProps = {}
    this.dynamicModalHeader = ''
    this._syncBodyScroll()
  }

  handleViewKycClick(event) {
    const applicantId = event.currentTarget?.dataset?.applicantId
    if (!applicantId || !HARD_CODED_RECORD_ID) {
      return
    }

    const applicant = (this.applicantColumns || []).find((row) => row.id === applicantId)
    const nameField = (applicant?.fields || []).find((field) =>
      String(field?.id || '').startsWith('name-')
    )

    this._openDynamicModal('kycViewer', {
      recordId: HARD_CODED_RECORD_ID,
      applicantId,
      applicantName: nameField?.valueDisplay || applicant?.title || '',
      applicantType: applicant?.applicantType || '',
      modalHeader: 'KYC Details'
    })
  }

  handleAnnexureDocumentClick(event) {
    event.preventDefault()
    event.stopPropagation()

    const ds = event.currentTarget?.dataset || {}
    if (ds.hasDocumentLink !== 'true') {
      return
    }

    const contentDocumentId = ds.contentDocumentId || null
    if (!contentDocumentId) {
      return
    }

    this.previewContentDocumentId = contentDocumentId
    this.previewFileType = ds.fileType || null
    this.showFilePreviewer = true
  }

  handleFilePreviewClose(event) {
    event?.stopPropagation?.()
    this.showFilePreviewer = false
    this.previewContentDocumentId = null
    this.previewFileType = null
  }

  handleFiInvestigationTypeClick(event) {
    event.preventDefault()

    const {
      componentName,
      verificationId,
      investigationId,
      isFiLink,
      modalHeader,
      applicantId
    } = event.currentTarget.dataset

    if (isFiLink !== 'true' || !componentName || !verificationId) {
      return
    }

    const lwcName = this._resolveFiComponentName(componentName)
    if (!lwcName || !FI_MODAL_COMPONENTS.has(lwcName)) {
      return
    }

    this._openDynamicModal(lwcName, {
      recordId: investigationId || undefined,
      verificationId,
      applicationId: HARD_CODED_RECORD_ID,
      applicantId: applicantId || undefined,
      modalHeader: modalHeader || 'FI Report',
      renderAsReadOnly: true
    })
  }

  _resolveFiComponentName(componentName) {
    const name = String(componentName || '').trim()
    if (!name) {
      return ''
    }
    return name.startsWith('c__') ? name.slice(3) : name
  }

  _syncBodyScroll() {
    const lock = this.showLoanAssetModal || this.showDynamicComponentModal

    try {
      const overflow = lock ? 'hidden' : ''
      document.documentElement.style.overflow = overflow
      document.body.style.overflow = overflow
    } catch (e) {
      /* non-DOM contexts */
    }
  }
}