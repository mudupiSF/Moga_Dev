import { LightningElement, api, track, wire } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import { refreshApex } from '@salesforce/apex'
import getApplicationAssets from '@salesforce/apex/ListofAssetDetailsController.getApplicationAssets'
import createApplicationAsset from '@salesforce/apex/ListofAssetDetailsController.createApplicationAsset'
import cloneApplicationAssets from '@salesforce/apex/ListofAssetDetailsController.cloneApplicationAssets'
import deleteApplicationAsset from '@salesforce/apex/ListofAssetDetailsController.deleteApplicationAsset'
import getIntegrationMaster from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getIntegrationMaster'
import getFiCreationMode from '@salesforce/apex/FIWaiverAPIController.getFiCreationMode'
import { invokeHandler } from 'c/clientLayerHelper'

const LINE_ITEMS_PER_PAGE = 4
const LOS_NEXT_STAGE_EVENT = 'losnextstage'
const LOS_MENU_SELECT_EVENT = 'losmenuselect'
const NAV_LOADER_DELAY_MS = 1000
const STAGE_ASSET_DETAILS = 'Asset Details'
const STAGE_VALUATION = 'Valuation'
const STAGE_LOAN_TERMS = 'Loan Terms'
const STAGE_OFFER = 'Offer'
const STAGE_REPAYMENT = 'Repayment'
const STAGE_AGREEMENT = 'Agreement'
const STAGE_INVOICE = 'Invoice'
const STAGE_IHM = 'IHM'
const STAGE_PAYMENT_REQUEST = 'Payment Request'
const STAGE_PAYMENT_DISBURSEMENT = 'Payment Disbursement'
const STAGE_POST_DISBURSEMENT_TRACKING = 'Post-Disbursement Tracking'

const COMPONENT_BY_ASSET_TYPE = {
  NEW: 'vehicleDetailsMasterPage',
  USED: 'vehicleDetailsUsedMasterPage',
  REFINANCE: 'vehicleDetailsUsedMasterPage'
}

const COMPONENT_BY_STAGE = {
  [STAGE_VALUATION]: 'valuation',
  [STAGE_LOAN_TERMS]: 'loanTerms',
  [STAGE_OFFER]: 'offerPage',
  [STAGE_REPAYMENT]: 'repaymentMandate',
  [STAGE_AGREEMENT]: 'agreement',
  [STAGE_INVOICE]: 'invoice',
  [STAGE_IHM]: 'wheelsIhmPage',
  [STAGE_PAYMENT_REQUEST]: 'wheelsPaymentRequest',
  [STAGE_PAYMENT_DISBURSEMENT]: 'paymentDisbursementScreen',
  [STAGE_POST_DISBURSEMENT_TRACKING]: 'postDisbursementTrackingScreen'
}

const HEADER_TITLE_BY_STAGE = {
  [STAGE_ASSET_DETAILS]: 'Multi Asset Information',
  [STAGE_VALUATION]: 'Valuation',
  [STAGE_LOAN_TERMS]: 'Loan Terms',
  [STAGE_OFFER]: 'Offer',
  [STAGE_REPAYMENT]: 'Repayment',
  [STAGE_AGREEMENT]: 'Agreement',
  [STAGE_INVOICE]: 'Invoice',
  [STAGE_IHM]: 'IHM',
  [STAGE_PAYMENT_REQUEST]: 'Payment Request',
  [STAGE_PAYMENT_DISBURSEMENT]: 'Payment Disbursement',
  [STAGE_POST_DISBURSEMENT_TRACKING]: 'Post-Disbursement Tracking'
}

const FI_WAIVER_INTEGRATION_LABEL = 'FI Waiver'
const FI_STAGE_CREATION = 'Creating FI Investigations'
const FI_MODE_INDIVIDUAL = 'INDIVIDUAL'
const FI_MODE_PV_NI = 'PV_NI'
const FI_MODE_CV_NI = 'CV_NI'
const FI_INTEGRATION_STAGES = [
  FI_WAIVER_INTEGRATION_LABEL,
  FI_STAGE_CREATION
]

const COMPONENT_LOADERS = {
  vehicleDetailsMasterPage: () => import('c/vehicleDetailsMasterPage'),
  vehicleDetailsUsedMasterPage: () => import('c/vehicleDetailsUsedMasterPage'),
  valuation: () => import('c/valuation'),
  loanTerms: () => import('c/loanTerms'),
  offerPage: () => import('c/offerPage'),
  repaymentMandate: () => import('c/repaymentMandate'),
  agreement: () => import('c/agreement'),
  invoice: () => import('c/invoice'),
  wheelsIhmPage: () => import('c/wheelsIhmPage'),
  wheelsPaymentRequest: () => import('c/wheelsPaymentRequest'),
  paymentDisbursementScreen: () => import('c/paymentDisbursementScreen'),
  postDisbursementTrackingScreen: () => import('c/postDisbursementTrackingScreen')
}

const MOCK_LINE_ITEMS = [
  { id: 'VD-2258624', lineItemId: 'LI-2258624', assetId: 'VD-2258624', type: 'NEW', status: 'IN_PROGRESS', make: 'PIAGGIO', model: 'APE CITY+ METRO CNG OBD2A BS6', variant: 'APE CITY+ METRO CNG OBD2A BS6' },
  { id: 'VD-2258625', lineItemId: 'LI-2258625', assetId: 'VD-2258625', type: 'USED', status: 'COMPLETED', make: 'PIAGGIO', model: 'APE CITY+ METRO CNG OBD2A BS6', variant: 'APE CITY+ METRO CNG OBD2A BS6' },
  { id: 'VD-2258626', lineItemId: 'LI-2258626', assetId: 'VD-2258626', type: 'USED', status: 'IN_PROGRESS', make: 'PIAGGIO', model: 'APE CITY+ METRO CNG OBD2A BS6', variant: 'APE CITY+ METRO CNG OBD2A BS6' },
  { id: 'VD-2258627', lineItemId: 'LI-2258627', assetId: 'VD-2258627', type: 'REFINANCE', status: 'COMPLETED', make: 'PIAGGIO', model: 'APE CITY+ METRO CNG OBD2A BS6', variant: 'APE CITY+ METRO CNG OBD2A BS6' }
]

function normalizeType(type) {
  const value = (type || '').toUpperCase()
  if (value === 'NEW' || value === 'USED' || value === 'REFINANCE') {
    return value
  }
  return 'NEW'
}

function normalizeStatus(status) {
  return (status || '').toUpperCase() === 'COMPLETED' ? 'COMPLETED' : 'IN_PROGRESS'
}

function typeBadgeClass(type) {
  const map = {
    NEW: 'type-badge type-new',
    USED: 'type-badge type-used',
    REFINANCE: 'type-badge type-refinance'
  }
  return map[normalizeType(type)] || map.NEW
}

function statusIconClass(status) {
  return normalizeStatus(status) === 'COMPLETED'
    ? 'status-icon completed'
    : 'status-icon in-progress'
}

function resolveLineItemKey(lineItem) {
  return lineItem?.lineItemId || lineItem?.assetId || ''
}

function resolveLineItemStatus(lineItem) {
  return normalizeStatus(lineItem?.status)
}

function isValuationApplicableType(type) {
  const t = normalizeType(type)
  return t === 'USED' || t === 'REFINANCE'
}

/** Stage → status field on each line item row from Apex. */
const STAGE_STATUS_FIELD = {
  [STAGE_VALUATION]: 'valuationStatus',
  [STAGE_LOAN_TERMS]: 'loanTermsStatus',
  [STAGE_OFFER]: 'offerStatus',
  [STAGE_REPAYMENT]: 'repaymentStatus',
  [STAGE_AGREEMENT]: 'agreementStatus',
  [STAGE_INVOICE]: 'invoiceStatus',
  [STAGE_IHM]: 'ihmStatus',
  [STAGE_PAYMENT_REQUEST]: 'paymentRequestStatus',
  [STAGE_PAYMENT_DISBURSEMENT]: 'paymentDisbursementStatus',
  [STAGE_POST_DISBURSEMENT_TRACKING]: 'postDisbursementTrackingStatus'
}

const DETAIL_LOADING_LABEL = {
  [STAGE_VALUATION]: 'Loading valuation',
  [STAGE_LOAN_TERMS]: 'Loading loan terms',
  [STAGE_OFFER]: 'Loading offer',
  [STAGE_REPAYMENT]: 'Loading repayment',
  [STAGE_AGREEMENT]: 'Loading agreement',
  [STAGE_INVOICE]: 'Loading invoice',
  [STAGE_IHM]: 'Loading IHM',
  [STAGE_PAYMENT_REQUEST]: 'Loading payment request',
  [STAGE_PAYMENT_DISBURSEMENT]: 'Loading payment disbursement',
  [STAGE_POST_DISBURSEMENT_TRACKING]: 'Loading post-disbursement tracking'
}

function getLineItemStageStatus(lineItem, stage) {
  if (stage === STAGE_VALUATION) {
    return isValuationApplicableType(lineItem.type)
      ? normalizeStatus(lineItem.valuationStatus)
      : 'COMPLETED'
  }
  const field = STAGE_STATUS_FIELD[stage]
  if (field) {
    return normalizeStatus(lineItem[field])
  }
  return resolveLineItemStatus(lineItem)
}

const MULTI_ASSET_DETAIL_STAGES = new Set([
  STAGE_INVOICE,
  STAGE_IHM,
  STAGE_PAYMENT_REQUEST,
  STAGE_PAYMENT_DISBURSEMENT,
  STAGE_POST_DISBURSEMENT_TRACKING
])

function requiresChildAssetPicker(stage, lineItem) {
  return MULTI_ASSET_DETAIL_STAGES.has(stage) && (lineItem?.assetCount ?? 1) > 1
}

function resolveDetailComponentName(tab, assetType) {
  const stageComponent = COMPONENT_BY_STAGE[(tab || '').trim()]
  if (stageComponent) {
    return stageComponent
  }
  const type = normalizeType(assetType)
  return COMPONENT_BY_ASSET_TYPE[type] || COMPONENT_BY_ASSET_TYPE.NEW
}

export default class ListofAssetDetails extends LightningElement {
  @api recordId;
  @api currentViewId;
  @api stagePhrase;
  @api tab;
  @api applicantId;
  @api isStagePast = false;
  @api applicationStatus;

  _lineItems = []
  @api
  get assets() {
    return this._lineItems
  }
  set assets(value) {
    this._lineItems = Array.isArray(value) ? value : []
  }

  @track currentPage = 1
  @track clonePanelLineItemId = null
  @track cloneQuantities = {}
  @track isAddingLineItem = false
  @track isCloningLineItem = false
  @track showVehicleDetails = false
  @track showInvoiceAssetPicker = false
  @track selectedLineItemId = ''
  @track selectedAssetId = ''
  @track fromAssetList = false
  @track activeComponentCtor = null
  @track componentProps = {}
  @track isLoadingVehicleDetail = false
  @track isUnknownComponent = false
  @track unknownComponentName = ''
  @track showDeleteModal = false
  @track pendingDeleteLineItemId = null
  @track pendingDeleteAssetId = null
  @track pendingDeleteDisplayId = ''
  @track isDeletingLineItem = false
  @track detailInstanceKey = ''
  @track isNavigating = false
  @track showIntegrationModal = false
  @track integrationStatus = 'loading'
  @track integrationCurrentStageIndex = 0
  @track integrationSuccessMessage = ''
  @track integrationErrorMessage = ''
  @track integrationStages = [];
  @track productType = '';

  _integrationRetryFn = null
  _fiWaiverIntegrationResult = null

  wiredAssetsResult

  connectedCallback() {
    this._onMenuSelect = (event) => {
      const nextViewId = event.detail?.id || ''
      const isStageChange = nextViewId && nextViewId !== this.currentViewId

      if (!isStageChange && !this.showVehicleDetails && !this.showInvoiceAssetPicker) {
        return
      }

      if (this.showVehicleDetails || this.showInvoiceAssetPicker) {
        this.clonePanelLineItemId = null
        this.closeVehicleDetails()
      }

      if (!isStageChange) {
        return
      }

      this.isNavigating = true
      setTimeout(() => {
        this.isNavigating = false
      }, NAV_LOADER_DELAY_MS)
    }
    window.addEventListener(LOS_MENU_SELECT_EVENT, this._onMenuSelect)
  }

  disconnectedCallback() {
    if (this._onMenuSelect) {
      window.removeEventListener(LOS_MENU_SELECT_EVENT, this._onMenuSelect)
      this._onMenuSelect = null
    }
  }

  @wire(getApplicationAssets, { applicationId: '$recordId', currentViewId: '$currentViewId' })
  wiredAssets(result) {
    this.wiredAssetsResult = result
    const { data, error } = result

    if (!this.recordId) {
      return
    }

    if (data?.isSuccess) {
      this._lineItems = Array.isArray(data.assets) ? data.assets : [];
      this.productType = data.productType || '';
      if (this.productType === 'PL') {
        this.fromAssetList = false;
        this.openVehicleDetails(this._lineItems[0].lineItemId, '', false);
      }
      else {
        this.fromAssetList = true;
      }
      return
    }

    if (error) {
      this.showToast('Error', this.getErrorMessage(error), 'error')
    } else if (data?.message) {
      this.showToast('Error', data.message, 'error')
    }
  }

  get useMockData() {
    return !this.recordId && this._lineItems.length === 0
  }

  get sourceLineItems() {
    if (this.useMockData) {
      return MOCK_LINE_ITEMS
    }
    return this._lineItems
  }

  get hasAssets() {
    return this.sourceLineItems.length > 0
  }

  get isAddAssetDisabled() {
    return !this.recordId || this.isAddingLineItem || this.showVehicleDetails
  }

  get isConfirmDeleteDisabled() {
    return this.isDeletingLineItem || (!this.pendingDeleteLineItemId && !this.pendingDeleteAssetId)
  }

  get isReadOnlyScreen() {
    return this.isStagePast === true || this.isStagePast === 'true'
  }

  get allAssetsCompleted() {
    if (!this.hasAssets) {
      return false
    }

    const stage = this.currentStage
    const lineItems = stage === STAGE_VALUATION
      ? this.sourceLineItems.filter((item) => isValuationApplicableType(item.type))
      : this.sourceLineItems

    if (lineItems.length === 0) {
      return true
    }

    return lineItems.every((item) => getLineItemStageStatus(item, stage) === 'COMPLETED')
  }

  get isNextDisabled() {
    if (!this.currentViewId || this.useMockData) {
      return true
    }
    if (this.isReadOnlyScreen) {
      return true
    }
    return !this.allAssetsCompleted
  }

  get nextButtonClass() {
    return `next-stage-btn${this.isNextDisabled ? ' next-stage-btn-disabled' : ''}`
  }

  get activeAssetType() {
    const lineItem = this.sourceLineItems.find(
      (item) => resolveLineItemKey(item) === this.selectedLineItemId
    )
    return normalizeType(lineItem?.type)
  }

  get hasActiveComponent() {
    return this.activeComponentCtor !== null
  }

  /** Live props for nested detail LWC — keeps applicationStatus in sync with parent. */
  get detailComponentProps() {
    const base = this.componentProps
    if (!this.activeComponentCtor || !base?.recordId) {
      return base
    }
    const rowLevelReadOnly = base?.isStagePast === true || base?.isStagePast === 'true'
    return {
      ...base,
      applicationStatus: { ...(this.applicationStatus || {}) },
      isStagePast: this.isReadOnlyScreen || rowLevelReadOnly
    }
  }

  get currentStage() {
    return (this.tab || '').trim()
  }

  get isValuationStage() {
    return this.currentStage === STAGE_VALUATION
  }

  get isLoanTermsStage() {
    return this.currentStage === STAGE_LOAN_TERMS
  }

  get isOfferStage() {
    return this.currentStage === STAGE_OFFER
  }

  get isPerAssetDetailStage() {
    return Boolean(STAGE_STATUS_FIELD[this.currentStage])
  }

  get headerTitle() {
    return HEADER_TITLE_BY_STAGE[this.currentStage] || 'Multi Asset Information'
  }

  get showAssetActions() {
    return !this.isPerAssetDetailStage && !this.isReadOnlyScreen
  }

  get detailLoadingLabel() {
    return DETAIL_LOADING_LABEL[this.currentStage] || 'Loading vehicle details'
  }

  get detailBackButtonLabel() {
    return this.shouldShowChildAssetPicker(this.selectedLineItemId)
      ? 'Back to Assets'
      : 'Back to Line Items'
  }

  get navigationLoadingLabel() {
    return 'Loading...'
  }

  get showAssetList() {
    return this.productType !== 'PL' && !this.showVehicleDetails && !this.showInvoiceAssetPicker
  }

  get showInvoiceAssetsTable() {
    return this.showInvoiceAssetPicker && !this.showVehicleDetails
  }

  get selectedLineItem() {
    return this.findLineItemById(this.selectedLineItemId)
  }

  get childAssetSectionTitle() {
    const count = this.selectedLineItem?.assetCount ?? 0
    const labels = {
      [STAGE_IHM]: 'IHM Assets',
      [STAGE_INVOICE]: 'Invoice Assets',
      [STAGE_PAYMENT_REQUEST]: 'Payment Request Assets',
      [STAGE_PAYMENT_DISBURSEMENT]: 'Disbursement Assets',
      [STAGE_POST_DISBURSEMENT_TRACKING]: 'Post-Disbursement Assets'
    }
    return `${labels[this.currentStage] || 'Assets'} (${count})`
  }

  get childAssetPickerDescription() {
    const descriptions = {
      [STAGE_IHM]: 'Select an asset to open IHM',
      [STAGE_INVOICE]: 'Select an asset to open invoice',
      [STAGE_PAYMENT_REQUEST]: 'Select an asset to open payment request',
      [STAGE_PAYMENT_DISBURSEMENT]: 'Select an asset to open payment disbursement',
      [STAGE_POST_DISBURSEMENT_TRACKING]: 'Select an asset to open post-disbursement tracking'
    }
    return descriptions[this.currentStage] || 'Select an asset'
  }

  get childAssetTableAriaLabel() {
    const labels = {
      [STAGE_IHM]: 'IHM assets',
      [STAGE_INVOICE]: 'Invoice assets',
      [STAGE_PAYMENT_REQUEST]: 'Payment request assets',
      [STAGE_PAYMENT_DISBURSEMENT]: 'Payment disbursement assets',
      [STAGE_POST_DISBURSEMENT_TRACKING]: 'Post-disbursement tracking assets'
    }
    return labels[this.currentStage] || 'Assets'
  }

  get childAssetRows() {
    const lineItem = this.selectedLineItem
    if (!lineItem || !Array.isArray(lineItem.childAssets)) {
      return []
    }

    const statusField = STAGE_STATUS_FIELD[this.currentStage] || 'invoiceStatus'

    return lineItem.childAssets.map((childAsset) => {
      const assetId = childAsset.assetId || ''
      const displayId = childAsset.id || assetId
      const childCompleted = normalizeStatus(childAsset[statusField]) === 'COMPLETED'
      const rowViewOnly = this.isReadOnlyScreen || childCompleted

      return {
        rowKey: assetId || displayId,
        lineItemId: this.selectedLineItemId,
        assetId,
        id: displayId,
        type: normalizeType(childAsset.type),
        make: childAsset.make || '—',
        model: childAsset.model || '—',
        variant: childAsset.variant || '—',
        typeBadgeClass: typeBadgeClass(childAsset.type),
        statusIconClass: statusIconClass(childCompleted ? 'COMPLETED' : 'IN_PROGRESS'),
        statusTitle: childCompleted ? 'Completed' : 'In Progress',
        statusIconName: childCompleted ? 'utility:success' : 'utility:clock',
        actionTitle: rowViewOnly ? 'View' : 'Edit',
        actionIconName: rowViewOnly ? 'utility:preview' : 'utility:edit',
        isViewOnly: rowViewOnly,
        isOpenDisabled: false
      }
    })
  }

  get hasChildAssetRows() {
    return this.childAssetRows.length > 0
  }

  get newAssetsCount() {
    return this.sourceLineItems.filter((lineItem) => normalizeType(lineItem.type) === 'NEW').length
  }

  get usedAssetsCount() {
    return this.sourceLineItems.filter((lineItem) => normalizeType(lineItem.type) === 'USED').length
  }

  get refinanceAssetsCount() {
    return this.sourceLineItems.filter((lineItem) => normalizeType(lineItem.type) === 'REFINANCE').length
  }

  get totalAssetsCount() {
    return this.sourceLineItems.length
  }

  get totalPages() {
    return Math.ceil(this.sourceLineItems.length / LINE_ITEMS_PER_PAGE) || 0
  }

  get showPagination() {
    return this.totalPages > 0
  }

  get isFirstPage() {
    return this.currentPage <= 1
  }

  get isLastPage() {
    return this.currentPage >= this.totalPages
  }

  get pageNumbers() {
    return Array.from({ length: this.totalPages }, (_, index) => {
      const page = index + 1
      return {
        page,
        buttonClass: page === this.currentPage ? 'page-btn active' : 'page-btn'
      }
    })
  }

  get paginatedAssets() {
    const start = (this.currentPage - 1) * LINE_ITEMS_PER_PAGE
    const end = start + LINE_ITEMS_PER_PAGE

    return this.sourceLineItems.slice(start, end).map((lineItem) => {
      const type = normalizeType(lineItem.type)
      const stage = this.currentStage
      const valuationApplicable = isValuationApplicableType(type)
      const valuationSkipped = stage === STAGE_VALUATION && !valuationApplicable
      const status = getLineItemStageStatus(lineItem, stage)
      const isCompleted = status === 'COMPLETED'
      const lineItemId = resolveLineItemKey(lineItem)
      const assetId = lineItem.assetId || ''
      const isClonePanelOpen = this.clonePanelLineItemId === lineItemId
      const isViewOnly = this.isReadOnlyScreen || isCompleted || valuationSkipped

      return {
        id: lineItem.id || lineItemId,
        lineItemId,
        assetId,
        type,
        status,
        make: lineItem.make || '—',
        model: lineItem.model || '—',
        variant: lineItem.variant || '—',
        assetCount: lineItem.assetCount ?? 1,
        typeBadgeClass: typeBadgeClass(type),
        statusIconClass: statusIconClass(status),
        statusTitle: isCompleted ? 'Completed' : 'In Progress',
        statusIconName: isCompleted ? 'utility:success' : 'utility:clock',
        showCloneButton: type === 'NEW' && this.showAssetActions,
        showClonePanel: isClonePanelOpen,
        cloneButtonClass: isClonePanelOpen
          ? 'footer-action-btn clone-btn active'
          : 'footer-action-btn clone-btn',
        cloneQuantity: this.cloneQuantities[lineItemId] || '',
        cloneInputId: `clone-qty-${lineItemId}`,
        isCloneSubmitDisabled: this.isCloningLineItem,
        actionTitle: valuationSkipped ? 'Not Applicable' : (isViewOnly ? 'View' : 'Edit'),
        actionIconName: isViewOnly ? 'utility:preview' : 'utility:edit',
        isViewOnly,
        isOpenDisabled: valuationSkipped,
        isDeleteDisabled: (!lineItemId && !assetId) || this.useMockData
      }
    })
  }

  get showBackToLineItemsButton() {
    return this.productType !== 'PL';
  }

  findLineItemById(lineItemId) {
    if (!lineItemId) {
      return null
    }
    return this.sourceLineItems.find(
      (lineItem) =>
        lineItem.lineItemId === lineItemId
        || lineItem.assetId === lineItemId
        || resolveLineItemKey(lineItem) === lineItemId
    )
  }

  findLineItemByAssetId(assetId) {
    if (!assetId) {
      return null
    }
    return this.sourceLineItems.find((lineItem) => lineItem.assetId === assetId) || null
  }

  shouldShowChildAssetPicker(lineItemId) {
    const lineItem = this.findLineItemById(lineItemId)
    return requiresChildAssetPicker(this.currentStage, lineItem)
  }

  async handleAddAsset() {
    if (this.isReadOnlyScreen || !this.recordId || this.isAddingLineItem) {
      return
    }

    this.isAddingLineItem = true
    try {
      const result = await createApplicationAsset({ applicationId: this.recordId })

      if (!result?.isSuccess) {
        this.showToast('Error', result?.message || 'Failed to create asset.', 'error')
        return
      }

      this.clonePanelLineItemId = null
      const createdRow = result?.asset || {}
      const lineItemId = result?.lineItemId || createdRow.lineItemId
      const assetId = createdRow.assetId
      await refreshApex(this.wiredAssetsResult)
      this.openVehicleDetails(lineItemId, assetId, false)
    } catch (error) {
      this.showToast('Error', this.getErrorMessage(error), 'error')
    } finally {
      this.isAddingLineItem = false
    }
  }

  async openVehicleDetails(lineItemId, fallbackAssetId = '', isViewOnly = false) {
    if (!lineItemId && !fallbackAssetId) {
      return
    }

    const lineItem = this.findLineItemById(lineItemId) || this.findLineItemByAssetId(fallbackAssetId)
    const resolvedLineItemId = resolveLineItemKey(lineItem) || lineItemId
    const assetId = fallbackAssetId || lineItem?.assetId || ''

    this.detailInstanceKey = assetId || resolvedLineItemId || `${Date.now()}`
    this.selectedLineItemId = resolvedLineItemId
    this.selectedAssetId = assetId
    this.showInvoiceAssetPicker = false
    this.showVehicleDetails = true
    this.activeComponentCtor = null
    this.componentProps = {}
    this.isUnknownComponent = false
    this.unknownComponentName = ''
    this.isLoadingVehicleDetail = true

    const componentName = resolveDetailComponentName(this.tab, lineItem?.type)

    const baseProps = {
      recordId: this.recordId,
      currentViewId: this.currentViewId,
      stagePhrase: this.stagePhrase,
      tab: this.tab,
      applicantId: this.applicantId,
      isStagePast: this.isReadOnlyScreen || isViewOnly,
      applicationLineItemId: resolvedLineItemId,
      fromAssetList: this.fromAssetList
    }

    if (
      this.isValuationStage
      || this.currentStage === STAGE_INVOICE
      || this.currentStage === STAGE_IHM
      || this.currentStage === STAGE_PAYMENT_REQUEST
      || this.currentStage === STAGE_PAYMENT_DISBURSEMENT
      || this.currentStage === STAGE_POST_DISBURSEMENT_TRACKING
    ) {
      baseProps.assetId = assetId
    } else if (!this.isPerAssetDetailStage) {
      baseProps.selectedAssetId = assetId
    }

    try {
      const loader = COMPONENT_LOADERS[componentName]
      if (!loader) {
        throw new Error(`Unknown detail component: ${componentName}`)
      }

      // Props must be set before the child mounts (connectedCallback reads them).
      this.componentProps = baseProps
      const module = await loader()
      if (this.selectedAssetId !== assetId) {
        return
      }
      this.activeComponentCtor = module.default
    } catch (error) {
      this.activeComponentCtor = null
      this.componentProps = {}
      this.isUnknownComponent = true
      this.unknownComponentName = componentName
      console.error(`[listofAssetDetails] Could not load component "c/${componentName}":`, error)
    } finally {
      this.isLoadingVehicleDetail = false
    }
  }

  closeVehicleDetails() {
    this.detailInstanceKey = ''
    this.showVehicleDetails = false
    this.selectedLineItemId = ''
    this.selectedAssetId = ''
    this.showInvoiceAssetPicker = false
    this.fromAssetList = false
    this.activeComponentCtor = null
    this.componentProps = {}
    this.isUnknownComponent = false
    this.unknownComponentName = ''
    this.isLoadingVehicleDetail = false
  }

  handleOpenAsset(event) {
    const lineItemId = event.currentTarget.dataset.lineItemId
    const assetId = event.currentTarget.dataset.assetId
    const isViewOnly = event.currentTarget.dataset.isViewOnly === 'true'
    const isOpenDisabled = event.currentTarget.dataset.isOpenDisabled === 'true'
    if (isOpenDisabled) {
      return
    }
    if (!lineItemId && !assetId) {
      return
    }
    this.clonePanelLineItemId = null

    if (this.showInvoiceAssetPicker) {
      if (!lineItemId || !assetId) {
        return
      }
      this.openVehicleDetails(lineItemId, assetId, isViewOnly)
      return
    }

    if (this.shouldShowChildAssetPicker(lineItemId)) {
      this.selectedLineItemId = lineItemId
      this.showInvoiceAssetPicker = true
      return
    }

    this.openVehicleDetails(lineItemId, assetId, isViewOnly)
  }

  handleBackToLineItems() {
    this.showInvoiceAssetPicker = false
    this.selectedLineItemId = ''
  }

  async handleBackToAssets() {
    if (this.shouldShowChildAssetPicker(this.selectedLineItemId)) {
      this.showVehicleDetails = false
      this.activeComponentCtor = null
      this.componentProps = {}
      this.detailInstanceKey = ''
      this.isLoadingVehicleDetail = false
      this.isUnknownComponent = false
      this.unknownComponentName = ''
      this.showInvoiceAssetPicker = true
    } else {
      this.closeVehicleDetails()
    }

    if (this.wiredAssetsResult) {
      await refreshApex(this.wiredAssetsResult)
    }
  }

  async handleDetailComplete() {
    await this.handleBackToAssets()
  }

  handleToggleClonePanel(event) {
    const lineItemId = event.currentTarget.dataset.lineItemId
    if (!lineItemId) return

    if (this.clonePanelLineItemId === lineItemId) {
      this.clonePanelLineItemId = null
      return
    }

    this.clonePanelLineItemId = lineItemId
  }

  handleCloneQuantityChange(event) {
    const lineItemId = event.currentTarget.dataset.lineItemId
    if (!lineItemId) return

    this.cloneQuantities = {
      ...this.cloneQuantities,
      [lineItemId]: event.target.value
    }
  }

  async handleCloneSubmit(event) {
    const lineItemId = event.currentTarget.dataset.lineItemId
    if (!lineItemId || !this.recordId || this.isCloningLineItem) {
      return
    }

    const sourceLineItem = this.findLineItemById(lineItemId)
    if (normalizeType(sourceLineItem?.type) !== 'NEW') {
      this.showToast('Validation Error', 'Cloning is only available for new vehicle assets.', 'error')
      return
    }

    const quantity = Number.parseInt(this.cloneQuantities[lineItemId], 10)
    if (!Number.isInteger(quantity) || quantity < 1) {
      this.showToast('Validation Error', 'Enter a valid quantity of at least 1.', 'error')
      return
    }

    this.isCloningLineItem = true
    try {
      const result = await cloneApplicationAssets({
        sourceLineItemId: lineItemId,
        sourceAssetId: sourceLineItem?.assetId || null,
        quantity
      })

      if (!result?.isSuccess) {
        this.showToast('Error', result?.message || 'Failed to clone assets.', 'error')
        return
      }

      this.showToast('Success', result.message || 'Assets cloned successfully.', 'success')
      this.clonePanelLineItemId = null
      this.cloneQuantities = { ...this.cloneQuantities, [lineItemId]: '' }

      await refreshApex(this.wiredAssetsResult)

      const totalPages = Math.ceil(this.sourceLineItems.length / LINE_ITEMS_PER_PAGE) || 1
      this.currentPage = totalPages
    } catch (error) {
      this.showToast('Error', this.getErrorMessage(error), 'error')
    } finally {
      this.isCloningLineItem = false
    }
  }

  handleDeleteAssetClick(event) {
    const lineItemId = event.currentTarget.dataset.lineItemId
    const assetId = event.currentTarget.dataset.assetId
    const displayId = event.currentTarget.dataset.displayId
    if (!lineItemId && !assetId) return

    this.pendingDeleteLineItemId = lineItemId || null
    this.pendingDeleteAssetId = assetId || null
    this.pendingDeleteDisplayId = displayId || assetId || lineItemId
    this.showDeleteModal = true
  }

  handleCloseDeleteModal() {
    if (this.isDeletingLineItem) return
    this.showDeleteModal = false
    this.pendingDeleteLineItemId = null
    this.pendingDeleteAssetId = null
    this.pendingDeleteDisplayId = ''
  }

  async handleConfirmDelete() {
    if ((!this.pendingDeleteLineItemId && !this.pendingDeleteAssetId) || this.isDeletingLineItem) return

    this.isDeletingLineItem = true
    try {
      const result = await deleteApplicationAsset({
        lineItemId: this.pendingDeleteLineItemId,
        assetId: this.pendingDeleteAssetId
      })

      if (!result?.isSuccess) {
        this.showToast('Error', result?.message || 'Failed to delete asset.', 'error')
        return
      }

      this.showToast('Success', result.message || 'Asset deleted successfully.', 'success')

      const deletedLineItemId = this.pendingDeleteLineItemId
      const deletedAssetId = this.pendingDeleteAssetId
      this.showDeleteModal = false
      this.pendingDeleteLineItemId = null
      this.pendingDeleteAssetId = null
      this.pendingDeleteDisplayId = ''
      this.clonePanelLineItemId = null

      await refreshApex(this.wiredAssetsResult)

      if (this.currentPage > this.totalPages && this.totalPages > 0) {
        this.currentPage = this.totalPages
      }
    } catch (error) {
      this.showToast('Error', this.getErrorMessage(error), 'error')
    } finally {
      this.isDeletingLineItem = false
    }
  }

  handlePreviousPage() {
    if (this.isFirstPage) return
    this.currentPage -= 1
    this.clonePanelLineItemId = null
    if (this.showInvoiceAssetPicker) {
      this.handleBackToLineItems()
    }
  }

  handleNextPage() {
    if (this.isLastPage) return
    this.currentPage += 1
    this.clonePanelLineItemId = null
    if (this.showInvoiceAssetPicker) {
      this.handleBackToLineItems()
    }
  }

  handlePageClick(event) {
    const page = Number(event.currentTarget.dataset.page)
    if (!page || page === this.currentPage) return
    this.currentPage = page
    this.clonePanelLineItemId = null
    if (this.showInvoiceAssetPicker) {
      this.handleBackToLineItems()
    }
  }

  handleNextButton() {
    if (this.isNextDisabled) {
      return
    }

    if (!this.isReadOnlyScreen && !this.allAssetsCompleted) {
      this.showToast('Validation Error', 'Please complete all assets before proceeding.', 'error')
      return
    }

    if (!this.currentViewId) {
      this.showToast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error')
      return
    }

    if (this.isOfferStage && !this.isReadOnlyScreen) {
      if (!this.recordId) {
        this.showToast('Navigation Error', 'Application record Id is missing.', 'error')
        return
      }
      this._processOfferStageFiAndAdvance()
      return
    }

    this._dispatchNextStage()
  }

  _dispatchNextStage() {
    this.isNavigating = true

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.isNavigating = false
      window.dispatchEvent(
        new CustomEvent(LOS_NEXT_STAGE_EVENT, {
          detail: {
            currentViewId: this.currentViewId,
            id: this.currentViewId,
            applicantId: this.applicantId,
            currentLoanStageComplete: this.tab || STAGE_ASSET_DETAILS,
            currentStagePhrase: this.stagePhrase || ''
          },
          bubbles: true,
          composed: true
        })
      )
    }, NAV_LOADER_DELAY_MS)
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

  handleIntegrationModalClose() {
    this.showIntegrationModal = false
  }

  handleIntegrationRetry() {
    this.integrationStatus = 'loading'
    this.integrationCurrentStageIndex = 0
    this.integrationErrorMessage = ''
    if (this._integrationRetryFn) {
      this._integrationRetryFn()
    }
  }

  async _processOfferStageFiAndAdvance() {
    let fiMode = FI_MODE_INDIVIDUAL
    try {
      fiMode = await getFiCreationMode({ applicationId: this.recordId }) || FI_MODE_INDIVIDUAL
    } catch (error) {
      this.showToast('Error', error?.body?.message || error?.message || 'Unable to resolve FI flow.', 'error')
      return
    }

    // NI – CV: skip FI on Offer (runs on Customer Dedupe)
    if (fiMode === FI_MODE_CV_NI) {
      this._dispatchNextStage()
      return
    }

    const fiStages = fiMode === FI_MODE_PV_NI ? [FI_STAGE_CREATION] : [...FI_INTEGRATION_STAGES]
    this._fiIntegrationStages = fiStages
    this._openIntegrationModal(fiStages, () => this._processOfferStageFiAndAdvance())

    try {
      const integrationMaster = await getIntegrationMaster({
        integrationName: FI_WAIVER_INTEGRATION_LABEL
      })
      const componentReference = integrationMaster?.Component_Reference__c
      if (!componentReference) {
        this.integrationStatus = 'error'
        this.integrationErrorMessage = 'FI Waiver integration is not configured.'
        return
      }

      await invokeHandler(componentReference, 'onNextButton', this)

      const integrationResult = this._fiWaiverIntegrationResult
      if (!integrationResult?.isSuccess) {
        this.integrationStatus = 'error'
        this.integrationErrorMessage = integrationResult?.message || 'FI Waiver failed.'
        return
      }

      this.integrationCurrentStageIndex = fiStages.length
      this.integrationStatus = 'success'
      this.integrationSuccessMessage = integrationResult.message
        || 'FI investigation creation completed successfully.'

      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => {
        this.showIntegrationModal = false
        this._dispatchNextStage()
      }, 1500)
    } catch (error) {
      this.integrationStatus = 'error'
      this.integrationErrorMessage = error?.body?.message || error?.message || 'FI Waiver failed.'
    }
  }

  handleShowToast(event) {
    const { title, message, variant } = event.detail || {}
    if (title || message) {
      this.showToast(title, message, variant || 'info')
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }))
  }

  getErrorMessage(error) {
    return error?.body?.message || error?.message || 'Unexpected error occurred.'
  }
}