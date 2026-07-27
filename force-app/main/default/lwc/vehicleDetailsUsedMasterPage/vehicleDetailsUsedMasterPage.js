import { LightningElement, api, track } from 'lwc'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'
import { invokeHandler } from 'c/clientLayerHelper'
import {
  REGISTRATION_FORMAT_NEW,
  REGISTRATION_FORMAT_OLD,
  VEHICLE_DEDUPE_DEFAULTS,
  VEHICLE_SUB_CATEGORY_OPTIONS,
  VEHICLE_DETAILS_DEFAULTS,
  NUMBER_OF_OWNERSHIPS_OPTIONS,
  RC_RETENTION_APPLICABLE_OPTIONS,
  /*getMakeOptions,
  getModelOptions,
  getVariantOptions,*/
  resolveMakeModelVariantFromDealMaster,
  mapVahaanReportToFields,
  isVehicleDedupeProceedAllowed,
  DEALER_REGISTRATION_DEFAULTS,
  DEALER_SUB_DEALER_OPTIONS,
  STATE_OF_UTILIZATION_OPTIONS,
  getDistrictOptionsForState,
  LOAN_INFORMATION_DEFAULTS,
  MAXIMUM_AVAILABLE_TENURE_MONTHS,
  getRequiredTenureOptions
} from './picklistValuesHelper'

const APEX_CLASS = 'VehicleDetailsController'
const APEX_METHOD = 'getVehicleDetailsUsedPageData'
const SAVE_APEX_METHOD = 'saveVehicleDetailsUsedPageData'
const STAGE_VEHICLE_DETAILS = 'Asset Details'
const LOS_NEXT_STAGE_EVENT = 'losnextstage'
const INTEGRATION_PROGRESS_EVENT = 'integrationprogressupdate'
const HIRE_VS_BUY_PRODUCT_TYPES = new Set(['SCV', 'LCV', 'MHCV', 'CE'])

const hasVal = (v) => v != null && String(v).trim() !== ''

function normalizeDateInputValue(rawValue) {
  if (!hasVal(rawValue)) return ''
  const value = String(rawValue).trim()
  const isoDateMatch = value.match(/^(\d{4}-\d{2}-\d{2})/)
  if (isoDateMatch) return isoDateMatch[1]
  const slashDateMatch = value.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/)
  if (slashDateMatch) {
    const day = slashDateMatch[1].padStart(2, '0')
    const month = slashDateMatch[2].padStart(2, '0')
    return `${slashDateMatch[3]}-${month}-${day}`
  }
  return value
}

export default class VehicleDetailsUsedMasterPage extends LightningElement {
  _recordId

  @api get recordId() {
    return this._recordId
  }

  set recordId(v) {
    this._recordId = v
    this._loadPageData()
  }

  @api applicantId
  @api currentViewId
  @api tab = ''
  @api stagePhrase = ''

  _apiSelectedAssetId = ''

  @api
  get selectedAssetId() {
    return this._apiSelectedAssetId
  }

  set selectedAssetId(value) {
    this._apiSelectedAssetId = value || ''
    if (this._recordId) {
      this._loadPageData()
    }
  }

  @api fromAssetList = false

  _applicationLineItemId = ''

  @api
  get applicationLineItemId() {
    return this._applicationLineItemId
  }

  set applicationLineItemId(value) {
    this._applicationLineItemId = value || ''
  }

  @track isLoading = false
  @track isPageReadOnly = false
  @track assetId = null
  @track productType = '';
  @track productTypeFullForm = '';
  @track vehicleDedupeFieldValues = { ...VEHICLE_DEDUPE_DEFAULTS }
  @track vehicleDedupeResponse = null
  @track vehicleDedupeData = null
  @track vehicleDedupeErrorMessage = ''
  @track getVehicleDetailsResponse = null
  @track getVehicleDetailsData = null
  @track getVehicleDetailsErrorMessage = ''
  @track vehicleDetailsFieldValues = { ...VEHICLE_DETAILS_DEFAULTS }
  @track dealerRegistrationFieldValues = { ...DEALER_REGISTRATION_DEFAULTS }
  @track loanInformationFieldValues = { ...LOAN_INFORMATION_DEFAULTS }
  @track hasPersistedLoan = false
  @track showDynamicComponentModal = false
  @track dynamicComponentName = ''
  @track dynamicComponentProps = {}
  @track dynamicModalHeader = ''
  @track hasViabilityCheckSaved = false
  @track hasHireVsBuySaved = false
  @track hasPersistedUsedVehicle = false

  _lastActionFieldKey = ''
  @track _vehicleActionStates = {}

  @track showIntegrationProgressModal = false
  @track integrationProgressModalStatus = 'loading'
  @track integrationProgressModalCurrentStageIdx = 0
  @track integrationProgressModalStages = []
  @track integrationProgressModalErrorMessage = '';
  @track make = '';
  @track model = '';
  @track variant = '';
  @track makeName = '';
  @track modelName = '';
  @track variantName = '';
  @track alreadyLoadedMake = false;

  _integrationProgressHandler

  get vehicleSubCategoryOptions() {
    return VEHICLE_SUB_CATEGORY_OPTIONS
  }

  get vdRegistrationFormat() {
    return this.vehicleDedupeFieldValues.registrationFormat ?? ''
  }

  get vdVehicleSubCategory() {
    return this.vehicleDedupeFieldValues.vehicleSubCategory ?? ''
  }

  get vdRegistrationNumber() {
    return this.vehicleDedupeFieldValues.registrationNumber ?? ''
  }

  get vdParentDealNumber() {
    return this.vehicleDedupeFieldValues.parentDealNumber ?? ''
  }

  get vdInsuranceExpiryDate() {
    return this.vehicleDedupeFieldValues.insuranceExpiryDate ?? ''
  }

  get registrationFormatNewValue() {
    return REGISTRATION_FORMAT_NEW
  }

  get registrationFormatOldValue() {
    return REGISTRATION_FORMAT_OLD
  }

  get isRegistrationFormatNew() {
    return this.vdRegistrationFormat === REGISTRATION_FORMAT_NEW
  }

  get isRegistrationFormatOld() {
    return this.vdRegistrationFormat === REGISTRATION_FORMAT_OLD
  }

  get vdRegistrationFormatDisplay() {
    if (this.isRegistrationFormatNew) {
      return 'New Format (HR55AB1234)'
    }
    if (this.isRegistrationFormatOld) {
      return 'Old Format (HR-05-AB-1234)'
    }
    return ''
  }

  get isMandatoryDedupeFieldsComplete() {
    return this._isVehicleDedupeSectionComplete()
  }

  get isVehicleDedupeDisabled() {
    return (
      this.isPageReadOnly ||
      !this.isMandatoryDedupeFieldsComplete ||
      this.isVehicleDedupeLoading ||
      this.isVehicleDedupeSuccess
    )
  }

  get isGetVehicleDetailsDisabled() {
    return (
      this.isPageReadOnly ||
      !this.isMandatoryDedupeFieldsComplete ||
      !this.isVehicleDedupeSuccess ||
      this.isGetVehicleDetailsLoading ||
      this.isGetVehicleDetailsSuccess
    )
  }

  get isVehicleDedupeLoading() {
    return this._vehicleActionStates.vehicleDedupe === 'loading'
  }

  get isVehicleDedupeSuccess() {
    return this._vehicleActionStates.vehicleDedupe === 'success'
  }

  get isGetVehicleDetailsLoading() {
    return this._vehicleActionStates.getVehicleDetails === 'loading'
  }

  get isGetVehicleDetailsSuccess() {
    return this._vehicleActionStates.getVehicleDetails === 'success'
  }

  get vehicleDedupeButtonClass() {
    return 'p4-primary-btn p4-button-text'
  }

  get getVehicleDetailsButtonClass() {
    return 'p4-primary-btn p4-button-text'
  }

  get vehicleDedupeButtonLabel() {
    if (this.isVehicleDedupeLoading) return 'Checking...'
    return 'Vehicle Dedupe'
  }

  get getVehicleDetailsButtonLabel() {
    if (this.isGetVehicleDetailsLoading) return 'Fetching...'
    return 'Get Vehicle Details'
  }

  get showVehicleDetailsSection() {
    return this.isGetVehicleDetailsSuccess
  }

  get showDealerRegistration() {
    return this.showVehicleDetailsSection && this._isVehicleDetailsSectionComplete()
  }

  get showLoanInformation() {
    if (!this.showDealerRegistration) {
      return false
    }
    return this._isDealerRegistrationSectionComplete() || this.hasPersistedLoan
  }

  get requiredTenureOptions() {
    const max = Number(this.loanInformationFieldValues.maximumAvailableTenure) ||
      MAXIMUM_AVAILABLE_TENURE_MONTHS
    return getRequiredTenureOptions(max)
  }

  get liRequiredLoanAmount() {
    return this.loanInformationFieldValues.requiredLoanAmount ?? ''
  }

  get liRequiredIrr() {
    return this.loanInformationFieldValues.requiredIrr ?? ''
  }

  get liRequiredTenure() {
    return this.loanInformationFieldValues.requiredTenure ?? ''
  }

  get liMaximumAvailableTenureDisplay() {
    return this.loanInformationFieldValues.maximumAvailableTenure ??
      String(MAXIMUM_AVAILABLE_TENURE_MONTHS)
  }

  get isFundingOnRoadPrice() {
    return this.loanInformationFieldValues.fundingBasedOn === 'On-road Price'
  }

  get isFundingExShowroomPrice() {
    return this.loanInformationFieldValues.fundingBasedOn === 'Ex-showroom Price'
  }

  get liFundingBasedOnDisplay() {
    return this.loanInformationFieldValues.fundingBasedOn || '-'
  }

  get dealerSubDealerOptions() {
    return DEALER_SUB_DEALER_OPTIONS
  }

  get stateOfUtilizationOptions() {
    return STATE_OF_UTILIZATION_OPTIONS
  }

  get districtOfUtilizationOptions() {
    return getDistrictOptionsForState(this.drStateOfUtilizationOfAsset)
  }

  get isDistrictDisabled() {
    return this.isPageReadOnly || !hasVal(this.drStateOfUtilizationOfAsset)
  }

  get drDealerSubDealerName() {
    return this.dealerRegistrationFieldValues.dealerSubDealerName ?? ''
  }

  get drRcLimitEnabledDealer() {
    return this.dealerRegistrationFieldValues.rcLimitEnabledDealer === true
  }

  get drRcLimitEnabledDealerDisplay() {
    return this.drRcLimitEnabledDealer ? 'Yes' : 'No'
  }

  get drStateOfUtilizationOfAsset() {
    return this.dealerRegistrationFieldValues.stateOfUtilizationOfAsset ?? ''
  }

  get drDistrictOfUtilizationOfAsset() {
    return this.dealerRegistrationFieldValues.districtOfUtilizationOfAsset ?? ''
  }

  get isNextDisabled() {
    if (this.isLoading) return true
    if (this.isPageReadOnly) return false
    if (!this.hasViabilityCheckSaved) return true
    return !(
      this._isUsedVehicleSaveReady() &&
      (this.isGetVehicleDetailsSuccess || this.hasPersistedUsedVehicle)
    )
  }

  get isViabilityCheckDisabled() {
    return this.isLoading || (!this.showLoanInformation && !this.isPageReadOnly)
  }

  get viabilityCheckButtonClass() {
    return 'p4-primary-btn p4-button-text'
  }

  get viabilityCheckButtonLabel() {
    return 'Viability Check'
  }

  get isReadOnlyMode() {
    return this.isPageReadOnly
  }

  get hireVsBuyButtonLabel() {
    return 'Hire vs buy'
  }

  get hireVsBuyButtonClass() {
    return 'p4-primary-btn p4-button-text'
  }

  get showHireVsBuy() {
    return HIRE_VS_BUY_PRODUCT_TYPES.has(this.productType)
  }

  /*get makeOptions() {
    return getMakeOptions(this.productType)
  }

  get modelOptions() {
    return getModelOptions(this.productType, this.vdMake)
  }

  get variantOptions() {
    return getVariantOptions(this.productType, this.vdMake, this.vdModel)
  }*/

  get numberOfOwnershipsOptions() {
    return NUMBER_OF_OWNERSHIPS_OPTIONS
  }

  get rcRetentionApplicableOptions() {
    return RC_RETENTION_APPLICABLE_OPTIONS
  }

  get isModelDisabled() {
    return this.isPageReadOnly || !hasVal(this.vdMake)
  }

  get isVariantDisabled() {
    return this.isPageReadOnly || !hasVal(this.vdModel)
  }

  /*get vdMake() {
    return this.vehicleDetailsFieldValues.make ?? ''
  }

  get vdModel() {
    return this.vehicleDetailsFieldValues.model ?? ''
  }

  get vdVariant() {
    console.log('vdVariant: ' + this.vehicleDetailsFieldValues.variant);
    return this.vehicleDetailsFieldValues.variant ?? ''
  }*/

  get vdInvoiceInNameOf() {
    return this.vehicleDetailsFieldValues.invoiceInNameOf ?? ''
  }

  get vdManufacturingYearMonth() {
    return this.vehicleDetailsFieldValues.manufacturingYearMonth ?? ''
  }

  get vdLastOwnerName() {
    return this.vehicleDetailsFieldValues.lastOwnerName ?? ''
  }

  get vdEngineNumber() {
    return this.vehicleDetailsFieldValues.engineNumber ?? ''
  }

  get vdChassisNumber() {
    return this.vehicleDetailsFieldValues.chassisNumber ?? ''
  }

  get vdNumberOfOwnerships() {
    return this.vehicleDetailsFieldValues.numberOfOwnerships ?? ''
  }

  get vdRcRetentionApplicable() {
    return this.vehicleDetailsFieldValues.rcRetentionApplicable ?? ''
  }

  connectedCallback() {
    if (!this._recordId) {
      this.isLoading = false
    }
    this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e)
    window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler)
  }

  renderedCallback() {
    if((this.make === '' || this.make === undefined || this.make === null) && !this.alreadyLoadedMake) {
      const makePicker = this.getPickerBySearchField('Make__c');
      if (makePicker) {
        this.alreadyLoadedMake = true;
        makePicker.getMakeList(this.productTypeFullForm);
      }
    }
  }

  disconnectedCallback() {
    if (this._integrationProgressHandler) {
      window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler)
    }
  }

  handleIntegrationProgressUpdate(event) {
    const d = event.detail || {}
    this.showIntegrationProgressModal = d.show !== false
    this.integrationProgressModalStatus = d.status || 'loading'
    this.integrationProgressModalCurrentStageIdx = d.currentStageIndex ?? 0
    this.integrationProgressModalStages = d.stages || []
    this.integrationProgressModalErrorMessage = d.errorMessage || ''
  }

  handleIntegrationProgressModalClose() {
    this.showIntegrationProgressModal = false
  }

  handleIntegrationProgressModalRetry() {
    this.integrationProgressModalStatus = 'loading'
    this.integrationProgressModalCurrentStageIdx = 0
    this.integrationProgressModalErrorMessage = ''
    const key = this._lastActionFieldKey
    if (key === 'vehicleDedupe') {
      this.handleVehicleDedupe()
      return
    }
    if (key === 'getVehicleDetails') {
      this.handleGetVehicleDetails()
    }
  }

  handleIntegrationProgressModalDone() {
    this.showIntegrationProgressModal = false
  }

  handleSectionFieldChange(event) {
    if (this.isPageReadOnly) return
    const el = event.currentTarget
    const key = el?.dataset?.key;
    if (!key) return
    let value
    if (el.type === 'radio') {
      value = el.value
    } else {
      value = event.detail?.value ?? event.target?.value ?? ''
    }
    this.vehicleDedupeFieldValues = {
      ...this.vehicleDedupeFieldValues,
      [key]: value
    };
  }

  async handleVehicleDedupe() {
    if (this.isVehicleDedupeDisabled) return
    this._lastActionFieldKey = 'vehicleDedupe'
    await invokeHandler('clientLayerVehicleDetails', 'onAction', this)
  }

  async handleGetVehicleDetails() {
    if (this.isGetVehicleDetailsDisabled) return
    this._lastActionFieldKey = 'getVehicleDetails'
    await invokeHandler('clientLayerVehicleDetails', 'onAction', this)
  }

  async handleNextButton() {
    if (this.isNextDisabled) return
    if (this.isPageReadOnly) {
      if (this.fromAssetList) {
        this.returnToAssetList(false)
        return
      }
      this._navigateToNextStage()
      return
    }
    this.isLoading = true
    try {
      const response = await savePageData({
        apexClassName: APEX_CLASS,
        apexMethodName: SAVE_APEX_METHOD,
        recordId: this.recordId,
        params: this._buildSaveParams()
      })
      if (response?.isSuccess) {
        this.hasPersistedUsedVehicle = true
        if (this.fromAssetList) {
          this.returnToAssetList(true)
          return
        }
        this._navigateToNextStage()
      } else {
        this._toast('Save Failed', response?.message || 'Failed to save data.', 'error')
      }
    } catch (e) {
      this._toast('Error', e?.message || 'An unexpected error occurred.', 'error')
    } finally {
      this.isLoading = false
    }
  }

  returnToAssetList(saved) {
    this.dispatchEvent(
      new CustomEvent('detailcomplete', {
        detail: {
          assetId: this._apiSelectedAssetId || null,
          lineItemId: this._applicationLineItemId || null,
          saved
        },
        bubbles: true,
        composed: true
      })
    )
  }

  _navigateToNextStage() {
    const currentViewId = this.currentViewId
    if (!currentViewId) {
      this._toast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error')
      return
    }
    window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
      detail: {
        currentViewId,
        id: currentViewId,
        applicantId: this.applicantId,
        currentLoanStageComplete: this.tab || STAGE_VEHICLE_DETAILS,
        currentStagePhrase: this.stagePhrase || ''
      },
      bubbles: true,
      composed: true
    }))
  }

  handleViabilityCheckButton() {
    if (this.isViabilityCheckDisabled) return
    const openReadOnly = this.isReadOnlyMode || this.hasViabilityCheckSaved
    this.openDynamicComponentModal('viabilityCheck', {
      modalHeader: 'Viability',
      recordId: this.recordId,
      assetId: this.selectedAssetId,
      isReadOnly: openReadOnly,
      allowEditWhenExisting: !openReadOnly
    })
  }

  handleHireVsBuyButton() {
    if (this.isViabilityCheckDisabled) return
    const openReadOnly = this.isReadOnlyMode || this.hasHireVsBuySaved
    this.openDynamicComponentModal('hireVsBuy', {
      modalHeader: 'Hire vs Buy',
      recordId: this.recordId,
      assetId: this.selectedAssetId,
      isReadOnly: openReadOnly,
      allowEditWhenExisting: !openReadOnly
    })
  }

  handleDynamicComponentModalClose(event) {
    const closedComponent = this.dynamicComponentName
    const saved = event?.detail?.saved === true

    this.showDynamicComponentModal = false
    this.dynamicComponentName = ''
    this.dynamicComponentProps = {}
    this.dynamicModalHeader = ''

    if (closedComponent === 'viabilityCheck') {
      if (saved) {
        this._refreshViabilityCheckFlag()
      }
    } else if (closedComponent === 'hireVsBuy') {
      if (saved) {
        this._refreshHireVsBuyFlag()
      }
    }
  }

  async _refreshViabilityCheckFlag() {
    if (!this.recordId) {
      return
    }
    try {
      const data = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: APEX_METHOD,
        recordId: this.recordId,
        params: this._buildPageParams()
      })
      this.hasViabilityCheckSaved = data?.hasViabilityData === true
    } catch (e) {
      console.error('[vehicleDetailsUsedMasterPage] _refreshViabilityCheckFlag:', e)
    }
  }

  async _refreshHireVsBuyFlag() {
    if (!this.recordId) {
      return
    }
    try {
      const data = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: APEX_METHOD,
        recordId: this.recordId,
        params: this._buildPageParams()
      })
      this.hasHireVsBuySaved = data?.hasHireVsBuyData === true
    } catch (e) {
      console.error('[vehicleDetailsUsedMasterPage] _refreshHireVsBuyFlag:', e)
    }
  }

  openDynamicComponentModal(componentName, extraProps = {}) {
    this.dynamicModalHeader = extraProps?.modalHeader || ''
    this.dynamicComponentProps = {
      recordId: this.recordId,
      ...extraProps
    }
    this.dynamicComponentName = componentName || ''
    this.showDynamicComponentModal = !!this.dynamicComponentName
  }

  async _loadPageData() {
    if (!this.recordId) {
      this._resetPageState()
      this.isLoading = false
      return
    }
    this.isLoading = true
    try {
      const data = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: APEX_METHOD,
        recordId: this.recordId,
        params: this._buildPageParams()
      })
      const d = data || {}
      this.assetId = d.assetId || null;
      this.productType = d.productType || '';
      this.productTypeFullForm = d.productTypeFullForm || '';
      this.isPageReadOnly = d.isReadOnly === true || this._isStagePast
      if (d.hasVehicleDedupeData) {
        this._hydrateVehicleDedupeFromPageData(d)
        this._vehicleActionStates = {
          ...this._vehicleActionStates,
          vehicleDedupe: 'success'
        }
      } else {
        this.vehicleDedupeFieldValues = { ...VEHICLE_DEDUPE_DEFAULTS }
      }
      if (d.hasVehicleDetailsData) {
        this._hydrateVehicleDetailsFromPageData(d)
        this._vehicleActionStates = {
          ...this._vehicleActionStates,
          getVehicleDetails: 'success'
        }
      } else {
        this.vehicleDetailsFieldValues = { ...VEHICLE_DETAILS_DEFAULTS }
      }
      this._hydrateDealerRegistrationFromPageData(d)
      if (d.hasLoanData) {
        this._hydrateLoanFromPageData(d)
      } else {
        this.hasPersistedLoan = false
        this.loanInformationFieldValues = {
          ...LOAN_INFORMATION_DEFAULTS,
          maximumAvailableTenure: String(d.maximumAvailableTenure ?? MAXIMUM_AVAILABLE_TENURE_MONTHS)
        }
      }
      this.hasViabilityCheckSaved = d.hasViabilityData === true
      this.hasHireVsBuySaved = d.hasHireVsBuyData === true
      this.hasPersistedUsedVehicle = d.hasVehicleDetailsData === true && hasVal(d.dealerSubDealerName);
      this.make = d.make || '';
      this.makeName = d.makeName || '';
      this.model = d.model || '';
      this.modelName = d.modelName || '';
      this.variant = d.variant || '';
      this.variantName = d.variantName || '';
    } catch (e) {
      console.error('[vehicleDetailsUsedMasterPage] _loadPageData:', e)
      this._resetPageState()
    } finally {
      this.isLoading = false
    }
  }

  getPickerBySearchField(searchFieldApiName) {
    const pickers = this.template.querySelectorAll('c-mmv-record-picker');
    return Array.from(pickers).find((picker) => picker.searchFieldApiName === searchFieldApiName);
  }

  _resetPageState() {
    this.assetId = null
    this.vehicleDedupeFieldValues = { ...VEHICLE_DEDUPE_DEFAULTS }
    this.vehicleDetailsFieldValues = { ...VEHICLE_DETAILS_DEFAULTS }
    this.dealerRegistrationFieldValues = { ...DEALER_REGISTRATION_DEFAULTS }
    this.loanInformationFieldValues = { ...LOAN_INFORMATION_DEFAULTS }
    this.hasPersistedLoan = false
    this.hasViabilityCheckSaved = false
    this.hasHireVsBuySaved = false
    this.hasPersistedUsedVehicle = false
    this.isPageReadOnly = false
    this._clearDedupeActionState()
  }

  _clearDedupeActionState() {
    this.vehicleDedupeResponse = null
    this.vehicleDedupeData = null
    this.vehicleDedupeErrorMessage = ''
    this.getVehicleDetailsResponse = null
    this.getVehicleDetailsData = null
    this.getVehicleDetailsErrorMessage = ''
    this.vehicleDetailsFieldValues = { ...VEHICLE_DETAILS_DEFAULTS }
    this.dealerRegistrationFieldValues = { ...DEALER_REGISTRATION_DEFAULTS }
    this._vehicleActionStates = {
      ...this._vehicleActionStates,
      vehicleDedupe: 'idle',
      getVehicleDetails: 'idle'
    }
    this._resetAssetDependentChecksIfSaved()
  }

  handleVehicleDetailsFieldChange(event) {
    if (this.isPageReadOnly) return
    const key = event.currentTarget?.dataset?.key
    if (!key) return
    const value = event.detail?.value ?? event.target?.value ?? '';
    const fieldName = event.currentTarget?.name;
    let nameKey = '';
    let nameValue = '';
    if(fieldName === 'make') {
      this.make = value;
      this.makeName = event.detail?.label || '';
      nameKey = 'makeName';
      nameValue = this.makeName;
    }
    else if(fieldName === 'model') {
      this.model = value;
      this.modelName = event.detail?.label || '';
      nameKey = 'modelName';
      nameValue = this.modelName;
    }
    else if(fieldName === 'variant') {
      this.variant = value;
      this.variantName = event.detail?.label || '';
      nameKey = 'variantName';
      nameValue = this.variantName;
    }
    const next = { ...this.vehicleDetailsFieldValues, [key]: value, [nameKey]: nameValue }
    if (key === 'make') {
      next.model = '';
      next.modelName = '';
      next.variant = '';
      next.variantName = '';
    }
    else if (key === 'model') {
      next.variant = '';
      next.variantName = '';
    }
    if(fieldName === 'make') {
      const modelPicker = this.getPickerBySearchField('Model__c');
      if (modelPicker) {
          modelPicker.getModelList(this.productTypeFullForm, next.make);
      }
      const variantPicker = this.getPickerBySearchField('Variant__c');
      if (variantPicker) {
          variantPicker.getVariantList(this.productTypeFullForm, next.make, next.model);
      }
    }
    else if(fieldName === 'model') {
      const variantPicker = this.getPickerBySearchField('Variant__c');
      if (variantPicker) {
          variantPicker.getVariantList(this.productTypeFullForm, next.make, next.model);
      }
    }
    this.vehicleDetailsFieldValues = next;
    this._resetAssetDependentChecksIfSaved()
  }

  handleDealerRegistrationFieldChange(event) {
    if (this.isPageReadOnly) return
    const el = event.currentTarget
    const key = el?.dataset?.key
    if (!key) return
    let value
    if (el.type === 'checkbox') {
      value = el.checked
    } else if (event.detail?.checked != null) {
      value = event.detail.checked
    } else {
      value = event.detail?.value ?? event.target?.value ?? ''
    }
    if (key === 'stateOfUtilizationOfAsset') {
      this.dealerRegistrationFieldValues = {
        ...this.dealerRegistrationFieldValues,
        stateOfUtilizationOfAsset: value,
        districtOfUtilizationOfAsset: ''
      }
      this._resetAssetDependentChecksIfSaved()
      return
    }
    this.dealerRegistrationFieldValues = {
      ...this.dealerRegistrationFieldValues,
      [key]: value
    }
    this._resetAssetDependentChecksIfSaved()
  }

  handleLoanInformationFieldChange(event) {
    if (this.isPageReadOnly) return
    const el = event.currentTarget
    const key = el?.dataset?.key
    if (!key) return
    let value
    if (el.type === 'radio') {
      value = el.value
    } else {
      value = event.detail?.value ?? event.target?.value ?? ''
    }
    this.loanInformationFieldValues = {
      ...this.loanInformationFieldValues,
      [key]: value
    }
    this._resetAssetDependentChecksIfSaved()
  }

  _resetAssetDependentChecksIfSaved() {
    if (this.hasViabilityCheckSaved) {
      this.hasViabilityCheckSaved = false
    }
    if (this.hasHireVsBuySaved) {
      this.hasHireVsBuySaved = false
    }
  }

  _hydrateVehicleDedupeFromPageData(d) {
    this.vehicleDedupeFieldValues = {
      registrationFormat: d.registrationFormat ?? '',
      vehicleSubCategory: d.vehicleSubCategory ?? '',
      registrationNumber: d.registrationNumber ?? '',
      parentDealNumber: d.parentDealNumber ?? '',
      insuranceExpiryDate: normalizeDateInputValue(d.insuranceExpiryDate)
    }
  }

  _hydrateVehicleDetailsFromPageData(d) {
    this.vehicleDetailsFieldValues = {
      make: d.make ?? '',
      makeName: d.makeName ?? '',
      model: d.model ?? '',
      modelName: d.modelName ?? '',
      variant: d.variant ?? '',
      variantName: d.variantName ?? '',
      invoiceInNameOf: d.invoiceInNameOf ?? '',
      manufacturingYearMonth: d.manufacturingYearMonth ?? '',
      lastOwnerName: d.lastOwnerName ?? '',
      engineNumber: d.engineNumber ?? '',
      chassisNumber: d.chassisNumber ?? '',
      numberOfOwnerships: d.numberOfOwnerships ?? '',
      rcRetentionApplicable: d.rcRetentionApplicable ?? ''
    }
  }

  _isVehicleDedupeSectionComplete() {
    const v = this.vehicleDedupeFieldValues || {}
    return (
      hasVal(v.registrationFormat) &&
      hasVal(v.vehicleSubCategory) &&
      hasVal(v.registrationNumber)
    )
  }

  _isVehicleDetailsSectionComplete() {
    const v = this.vehicleDetailsFieldValues || {}
    return (
      hasVal(v.make) &&
      hasVal(v.model) &&
      hasVal(v.variant) &&
      hasVal(v.invoiceInNameOf) &&
      hasVal(v.manufacturingYearMonth) &&
      hasVal(v.lastOwnerName) &&
      hasVal(v.engineNumber) &&
      hasVal(v.chassisNumber) &&
      hasVal(v.numberOfOwnerships) &&
      hasVal(v.rcRetentionApplicable)
    )
  }

  _hydrateDealerRegistrationFromPageData(d) {
    if (!d) return
    this.dealerRegistrationFieldValues = {
      ...DEALER_REGISTRATION_DEFAULTS,
      dealerSubDealerName: d.dealerSubDealerName ?? '',
      rcLimitEnabledDealer:
        d.rcLimitEnabledDealer === true || d.rcLimitEnabledDealer === 'true',
      stateOfUtilizationOfAsset: d.stateOfUtilizationOfAsset ?? '',
      districtOfUtilizationOfAsset: d.districtOfUtilizationOfAsset ?? ''
    }
  }

  _isDealerRegistrationSectionComplete() {
    const v = this.dealerRegistrationFieldValues || {}
    return (
      hasVal(v.dealerSubDealerName) &&
      hasVal(v.stateOfUtilizationOfAsset) &&
      hasVal(v.districtOfUtilizationOfAsset)
    )
  }

  _isLoanInformationSectionComplete() {
    const v = this.loanInformationFieldValues || {}
    return (
      hasVal(v.requiredLoanAmount) &&
      hasVal(v.requiredIrr) &&
      hasVal(v.requiredTenure) &&
      hasVal(v.fundingBasedOn)
    )
  }

  _hydrateLoanFromPageData(d) {
    let fundingBasedOn = d.fundingBasedOn || ''
    if (!fundingBasedOn && d.fundingOnOrp === true) {
      fundingBasedOn = 'On-road Price'
    } else if (!fundingBasedOn && d.fundingOnExShowroom === true) {
      fundingBasedOn = 'Ex-showroom Price'
    }
    this.loanInformationFieldValues = {
      ...LOAN_INFORMATION_DEFAULTS,
      requiredLoanAmount: d.requiredLoanAmount ?? '',
      requiredIrr: d.requiredIrr ?? '',
      maximumAvailableTenure: String(d.maximumAvailableTenure ?? MAXIMUM_AVAILABLE_TENURE_MONTHS),
      requiredTenure: d.requiredTenure != null ? String(d.requiredTenure) : '',
      fundingBasedOn
    }
    this.hasPersistedLoan = true
  }

  _isUsedVehicleSaveReady() {
    return (
      this._isVehicleDedupeSectionComplete() &&
      this._isVehicleDetailsSectionComplete() &&
      this._isDealerRegistrationSectionComplete() &&
      this.showLoanInformation &&
      this._isLoanInformationSectionComplete()
    )
  }

  _buildPageParams() {
    return {
      applicantId: this.applicantId || null,
      assetId: this._apiSelectedAssetId || null
    }
  }

  _buildSaveParams() {
    const dedupe = this.vehicleDedupeFieldValues || {}
    const details = this.vehicleDetailsFieldValues || {}
    const dealer = this.dealerRegistrationFieldValues || {}
    const loan = this.loanInformationFieldValues || {}
    const fundingBasedOn = loan.fundingBasedOn || ''
    return {
      applicantId: this.applicantId || null,
      assetId: this._apiSelectedAssetId || null,
      registrationFormat: dedupe.registrationFormat,
      vehicleSubCategory: dedupe.vehicleSubCategory,
      registrationNumber: dedupe.registrationNumber,
      parentDealNumber: dedupe.parentDealNumber,
      insuranceExpiryDate: normalizeDateInputValue(dedupe.insuranceExpiryDate),
      make: details.make,
      makeName: details.makeName,
      model: details.model,
      modelName: details.modelName,
      variant: details.variant,
      variantName: details.variantName,
      invoiceInNameOf: details.invoiceInNameOf,
      manufacturingYearMonth: details.manufacturingYearMonth,
      lastOwnerName: details.lastOwnerName,
      engineNumber: details.engineNumber,
      chassisNumber: details.chassisNumber,
      numberOfOwnerships: details.numberOfOwnerships,
      rcRetentionApplicable: details.rcRetentionApplicable,
      dealerSubDealerName: dealer.dealerSubDealerName,
      rcLimitEnabledDealer: dealer.rcLimitEnabledDealer,
      stateOfUtilizationOfAsset: dealer.stateOfUtilizationOfAsset,
      districtOfUtilizationOfAsset: dealer.districtOfUtilizationOfAsset,
      requiredLoanAmount: loan.requiredLoanAmount,
      requiredIrr: loan.requiredIrr,
      requiredTenure: loan.requiredTenure,
      fundingOnOrp: fundingBasedOn === 'On-road Price',
      fundingOnExShowroom: fundingBasedOn === 'Ex-showroom Price'
    }
  }

  get fields() {
    return [
      { key: 'registrationFormat', value: this.vdRegistrationFormat },
      { key: 'vehicleSubCategory', value: this.vdVehicleSubCategory },
      { key: 'registrationNumber', value: this.vdRegistrationNumber },
      { key: 'parentDealNumber', value: this.vdParentDealNumber },
      { key: 'insuranceExpiryDate', value: this.vdInsuranceExpiryDate },
      { key: 'vehicleDedupeResponse', value: this.vehicleDedupeResponse },
      { key: 'vehicleDedupeData', value: this.vehicleDedupeData },
      { key: 'vehicleDedupeErrorMessage', value: this.vehicleDedupeErrorMessage },
      { key: 'getVehicleDetailsResponse', value: this.getVehicleDetailsResponse },
      { key: 'getVehicleDetailsData', value: this.getVehicleDetailsData },
      { key: 'getVehicleDetailsErrorMessage', value: this.getVehicleDetailsErrorMessage },
      { key: 'make', value: this.vdMake },
      { key: 'model', value: this.vdModel },
      { key: 'variant', value: this.vdVariant },
      { key: 'invoiceInNameOf', value: this.vdInvoiceInNameOf },
      { key: 'manufacturingYearMonth', value: this.vdManufacturingYearMonth },
      { key: 'lastOwnerName', value: this.vdLastOwnerName },
      { key: 'engineNumber', value: this.vdEngineNumber },
      { key: 'chassisNumber', value: this.vdChassisNumber },
      { key: 'numberOfOwnerships', value: this.vdNumberOfOwnerships },
      { key: 'rcRetentionApplicable', value: this.vdRcRetentionApplicable },
      { key: 'dealerSubDealerName', value: this.drDealerSubDealerName },
      { key: 'rcLimitEnabledDealer', value: this.drRcLimitEnabledDealer },
      { key: 'stateOfUtilizationOfAsset', value: this.drStateOfUtilizationOfAsset },
      { key: 'districtOfUtilizationOfAsset', value: this.drDistrictOfUtilizationOfAsset }
    ]
  }

  setActionState(key, state) {
    if (!['vehicleDedupe', 'getVehicleDetails'].includes(key)) return
    if (!['idle', 'loading', 'success'].includes(state)) return
    this._vehicleActionStates = { ...this._vehicleActionStates, [key]: state }
    /*if(state === 'success') {
      const makePicker = this.getPickerBySearchField('Make__c');
      if (makePicker) {
          makePicker.getMakeList(this.productTypeFullForm);
      }
    }*/
  }

  updateFieldValue(key, value) {
    if (key === 'vehicleDedupeResponse') {
      this.vehicleDedupeResponse = value
      return
    }
    if (key === 'vehicleDedupeData') {
      this.vehicleDedupeData = value
      if (value && !isVehicleDedupeProceedAllowed(value)) {
        this.vehicleDedupeErrorMessage =
          value?.response?.respDesc || 'Vehicle dedupe did not return proceed flag Y'
      }
      return
    }
    if (key === 'vehicleDedupeErrorMessage') {
      this.vehicleDedupeErrorMessage = value || ''
      if (this.vehicleDedupeErrorMessage) {
        this._toast('Vehicle Dedupe Failed', this.vehicleDedupeErrorMessage, 'error')
      }
      return
    }
    if (key === 'getVehicleDetailsResponse') {
      this.getVehicleDetailsResponse = value
      return
    }
    if (key === 'getVehicleDetailsData') {
      this.getVehicleDetailsData = value
      this._hydrateFromGetVehicleDetailsData(value)
      return
    }
    if (key === 'getVehicleDetailsErrorMessage') {
      this.getVehicleDetailsErrorMessage = value || ''
      if (this.getVehicleDetailsErrorMessage) {
        this._toast('Get Vehicle Details Failed', this.getVehicleDetailsErrorMessage, 'error')
      }
    }
  }

  _hydrateFromGetVehicleDetailsData(data) {
    if (!data) return
    console.log('data123: ' + JSON.stringify(data.vahaan));
    console.log('data123: ' + JSON.stringify(data.dealMaster));
    this.applyUsedVehicleIntegrationData({
      vahaan: data.vahaan || null,
      dealMaster: data.dealMaster || null
    })
  }

  applyUsedVehicleIntegrationData({ vahaan, dealMaster }) {
    const mmv = resolveMakeModelVariantFromDealMaster(dealMaster);
    console.log('mmv123: ' + JSON.stringify(mmv));
    this.makeName = mmv.make;
    this.modelName = mmv.model;
    this.variantName = mmv.variant;
    const vahaanFields = mapVahaanReportToFields(vahaan)

    if (vahaanFields.insuranceExpiryDate) {
      this.vehicleDedupeFieldValues = {
        ...this.vehicleDedupeFieldValues,
        insuranceExpiryDate: normalizeDateInputValue(vahaanFields.insuranceExpiryDate)
      }
    }

    this.vehicleDetailsFieldValues = {
      ...VEHICLE_DETAILS_DEFAULTS,
      make: mmv.make,
      model: mmv.model,
      variant: mmv.variant,
      lastOwnerName: vahaanFields.lastOwnerName || '',
      engineNumber: vahaanFields.engineNumber || '',
      chassisNumber: vahaanFields.chassisNumber || '',
      manufacturingYearMonth: vahaanFields.manufacturingYearMonth || '',
      numberOfOwnerships: vahaanFields.numberOfOwnerships || ''
    }
    this._resetAssetDependentChecksIfSaved()
  }

  _toast(title, message, variant) {
    this.dispatchEvent(new CustomEvent('showtoast', {
      detail: { title, message, variant },
      bubbles: true,
      composed: true
    }))
  }
}