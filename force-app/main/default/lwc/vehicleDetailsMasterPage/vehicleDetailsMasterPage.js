import { LightningElement, api, track } from 'lwc'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'
import createAdditionalAssetApex from '@salesforce/apex/VehicleDetailsController.createAdditionalAsset'
import processNextStageRequest from '@salesforce/apex/dynamicStageNavigatorController.processNextStageRequest'
import { invokeHandler } from 'c/clientLayerHelper'
import {
  DEALER_REGISTRATION_DEFAULTS,
  DEALER_SUB_DEALER_OPTIONS,
  LOAN_INFORMATION_DEFAULTS,
  MAXIMUM_AVAILABLE_TENURE_MONTHS,
  STATE_OF_UTILIZATION_OPTIONS,
  getDistrictOptionsForState,
  getRequiredTenureOptions
} from './picklistValuesHelper'

const APEX_CLASS = 'VehicleDetailsController'
const APEX_METHOD = 'getVehicleDetailsPageData'
const SAVE_APEX_METHOD = 'saveVehicleDetailsPageData'
const STAGE_VEHICLE_DETAILS = 'Asset Details'
const LOS_NEXT_STAGE_EVENT = 'losnextstage'
const LOS_NAVIGATION_STATE_EVENT = 'losnavigationstate'
const LOS_MENU_SELECT_EVENT = 'losmenuselect'
const LOG_PREFIX = '[vehicleDetailsMasterPage]'
const HIRE_VS_BUY_PRODUCT_TYPES = new Set(['SCV', 'LCV', 'MHCV', 'CE'])

const hasVal = (v) => v != null && String(v).trim() !== ''

const PRICING_RECALC_FROM_BASIC_KEYS = new Set([
  'basicPrice',
  'discountOnBasicPrice',
  'gstAmount'
])

const PRICING_RECALC_FROM_EX_SHOWROOM_KEYS = new Set(['exShowroomPrice'])

export default class VehicleDetailsMasterPage extends LightningElement {
  /** Last losmenuselect for this stage (menu can fire before lwc:component mounts). */
  static _lastMenuDetail = null

  _recordId

  @api get recordId() {
    return this._recordId
  }

  set recordId(v) {
    this._recordId = v
    this._scheduleLoadPageData()
  }

  _apiApplicantId = ''
  _apiCurrentViewId = ''
  _apiTab = ''
  _apiStagePhrase = ''

  @api
  get applicantId() {
    return this._apiApplicantId
  }
  set applicantId(value) {
    this._apiApplicantId = value || ''
    if (value) {
      this._menuNavContext = { ...this._menuNavContext, applicantId: value }
    }
  }

  @api
  get currentViewId() {
    return this._apiCurrentViewId
  }
  set currentViewId(value) {
    this._apiCurrentViewId = value || ''
    if (value) {
      this._menuNavContext = { ...this._menuNavContext, currentViewId: value }
    }
  }

  @api
  get tab() {
    return this._apiTab
  }
  set tab(value) {
    this._apiTab = value || ''
    if (value) {
      this._menuNavContext = { ...this._menuNavContext, tab: value }
    }
  }

  @api
  get stagePhrase() {
    return this._apiStagePhrase
  }
  set stagePhrase(value) {
    this._apiStagePhrase = value || ''
    if (value) {
      this._menuNavContext = { ...this._menuNavContext, stagePhrase: value }
    }
  }

  _isStagePast = false

  @api
  get isStagePast() {
    return this._isStagePast
  }

  set isStagePast(value) {
    if (typeof value === 'string') {
      this._isStagePast = value.toLowerCase() === 'true'
      return
    }
    this._isStagePast = !!value
  }

  _apiSelectedAssetId = ''

  @api
  get selectedAssetId() {
    return this._apiSelectedAssetId
  }

  set selectedAssetId(value) {
    this._apiSelectedAssetId = value || ''
    this._scheduleLoadPageData()
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
  @track assetId = null
  @track productType = ''
  @track productTypeFullForm = '';
  @track vehicleType = '';
  @track make = '';
  @track makeName = '';
  @track model = '';
  @track modelName = '';
  @track variant = '';
  @track variantName = '';
  @track numberOfVehicles = '1'
  @track fetchPriceResponse = null
  @track fetchPriceData = null
  @track fetchPriceErrorMessage = ''
  @track pricingDetailsFieldValues = {}
  @track hasPersistedPricing = false
  @track loanInformationFieldValues = { ...LOAN_INFORMATION_DEFAULTS }
  @track hasPersistedLoan = false
  @track dealerRegistrationFieldValues = { ...DEALER_REGISTRATION_DEFAULTS }
  @track showDynamicComponentModal = false
  @track dynamicComponentName = ''
  @track dynamicComponentProps = {}
  @track hasViabilityCheckSaved = false
  @track hasHireVsBuySaved = false
  @track dynamicModalHeader = ''
  @track isPageReadOnly = false

  _lastActionFieldKey = ''
  @track _vehicleActionStates = {}
  _onRoadPriceFromFetch = false
  /** Cached from losmenuselect — lwc:component may not always sync @api props. */
  _menuNavContext = {}

  _menuSelectHandler
  _pageDataLoadToken = 0
  _pageDataLoadScheduled = false

  get makeDisplayLabel() {
    return this.makeName || ''
  }

  get modelDisplayLabel() {
    return this.modelName || ''
  }

  get variantDisplayLabel() {
    return this.variantName || ''
  }

  get isNumberOfVehiclesDisabled() {
    return this.isReadOnlyMode || !hasVal(this.variant)
  }

  get isFetchPriceSuccess() {
    return this._vehicleActionStates.fetchPrice === 'success' && !!this.fetchPriceData
  }

  get isFetchPriceDisabled() {
    return (
      this.isReadOnlyMode ||
      !hasVal(this.make) ||
      !hasVal(this.model) ||
      !hasVal(this.variant) ||
      !this._isValidNumberOfVehicles() ||
      this.isFetchPriceLoading ||
      this.isFetchPriceSuccess
    )
  }

  get isReadOnlyMode() {
    return this.isPageReadOnly || this._isStagePast
  }

  get isNextDisabled() {
    if (this.isLoading) return true
    if (this.isReadOnlyMode) return false
    if (!this.hasViabilityCheckSaved) return true
    if (this.showHireVsBuy && !this.hasHireVsBuySaved) return true
    return false
  }

  get nextButtonClass() {
    return `p4-primary-btn p4-button-text${this.isNextDisabled ? ' p4-primary-btn-disabled' : ''}`
  }

  get isViabilityCheckDisabled() {
    if (this.isLoading) return true
    if (this.isReadOnlyMode) return false
    return !this._isLoanInformationSectionComplete()
  }

  get isFetchPriceLoading() {
    return this._vehicleActionStates.fetchPrice === 'loading'
  }

  get fetchPriceButtonClass() {
    return 'p4-primary-btn p4-button-text'
  }

  get viabilityCheckButtonClass() {
    return 'p4-primary-btn p4-button-text'
  }

  get fetchPriceButtonLabel() {
    if (this.isFetchPriceLoading) return 'Fetching...'
    return 'Fetch Price'
  }

  get viabilityCheckButtonLabel() {
    return 'Viability Check'
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

  get showPricingDetails() {
    return (
      (this._vehicleActionStates.fetchPrice === 'success' && !!this.fetchPriceData) ||
      this.hasPersistedPricing
    )
  }

  get showDealerRegistration() {
    return this.showPricingDetails && this._isPricingSectionComplete()
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
    return this.isReadOnlyMode || !hasVal(this.drStateOfUtilizationOfAsset)
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

  get drInvoiceInNameOf() {
    return this.dealerRegistrationFieldValues.invoiceInNameOf ?? ''
  }

  get drVehicleRegisteredInNameOf() {
    return this.dealerRegistrationFieldValues.vehicleRegisteredInNameOf ?? 'Borrower'
  }

  get drStateOfUtilizationOfAsset() {
    return this.dealerRegistrationFieldValues.stateOfUtilizationOfAsset ?? ''
  }

  get drDistrictOfUtilizationOfAsset() {
    return this.dealerRegistrationFieldValues.districtOfUtilizationOfAsset ?? ''
  }

  get pdFirstYearInsurancePremium() {
    return this.pricingDetailsFieldValues.firstYearInsurancePremium ?? ''
  }

  get pdBasicPrice() {
    return this.pricingDetailsFieldValues.basicPrice ?? ''
  }

  get pdGstAmount() {
    return this.pricingDetailsFieldValues.gstAmount ?? ''
  }

  get pdOnRoadPriceDisplay() {
    return this._formatAmount(this.pricingDetailsFieldValues.onRoadPrice)
  }

  get pdMotorInsurancePremium() {
    return this.pricingDetailsFieldValues.motorInsurancePremium ?? ''
  }

  get pdDiscountOnBasicPrice() {
    return this.pricingDetailsFieldValues.discountOnBasicPrice ?? ''
  }

  get pdExShowroomPrice() {
    return this.pricingDetailsFieldValues.exShowroomPrice ?? ''
  }

  connectedCallback() {
    if (!this._recordId) {
      this.isLoading = false
    }
    this._menuSelectHandler = this._handleMenuSelectForNav.bind(this)
    window.addEventListener('losmenuselect', this._menuSelectHandler)
    if (VehicleDetailsMasterPage._lastMenuDetail) {
      this._applyMenuNavFromDetail(VehicleDetailsMasterPage._lastMenuDetail)
    }
  }

  disconnectedCallback() {
    if (this._menuSelectHandler) {
      window.removeEventListener('losmenuselect', this._menuSelectHandler)
    }
  }

  _handleMenuSelectForNav(event) {
    const detail = event?.detail || {}
    const overrideLwc = (detail.overrideLwc || '').trim()
    if (overrideLwc && overrideLwc !== 'vehicleDetailsMasterPage') {
      return
    }
    VehicleDetailsMasterPage._lastMenuDetail = detail
    this._applyMenuNavFromDetail(detail)
  }

  _applyMenuNavFromDetail(detail = {}) {
    this._menuNavContext = {
      currentViewId: detail.id || '',
      stagePhrase: detail.stagePhrase || detail.currentStagePhrase || '',
      tab: detail.tab || detail.label || '',
      applicantId: detail.applicantId || ''
    }
    if (detail.isStagePast != null) {
      this._isStagePast = detail.isStagePast === true
    }
  }

  _resolveNavContext() {
    const currentViewId =
      this.currentViewId ||
      this._menuNavContext.currentViewId ||
      VehicleDetailsMasterPage._lastMenuDetail?.id ||
      ''
    return {
      currentViewId,
      stagePhrase: this._resolveStagePhrase(currentViewId),
      tab:
        this.tab ||
        this._menuNavContext.tab ||
        VehicleDetailsMasterPage._lastMenuDetail?.tab ||
        STAGE_VEHICLE_DETAILS,
      applicantId:
        this.applicantId ||
        this._menuNavContext.applicantId ||
        VehicleDetailsMasterPage._lastMenuDetail?.applicantId ||
        ''
    }
  }

  _resolveStagePhrase(currentViewId = '') {
    const fromApi =
      this.stagePhrase ||
      this._menuNavContext.stagePhrase ||
      VehicleDetailsMasterPage._lastMenuDetail?.stagePhrase ||
      VehicleDetailsMasterPage._lastMenuDetail?.currentStagePhrase ||
      ''
    if (hasVal(fromApi)) {
      return fromApi
    }
    if (!currentViewId) {
      return ''
    }
    const sfIdMatch = String(currentViewId).match(/_([a-zA-Z0-9]{15,18})$/)
    if (sfIdMatch) {
      return currentViewId.slice(0, -sfIdMatch[1].length - 1)
    }
    return ''
  }

  _findCurrentViewMenuItem(items = []) {
    for (const item of items) {
      if (item?.currentView === true) {
        return item
      }
      if (item?.subItems?.length) {
        const found = this._findCurrentViewMenuItem(item.subItems)
        if (found) {
          return found
        }
      }
    }
    return null
  }

  _buildMenuSelectDetail(item = {}) {
    const isStagePast = String(item.status || '').toLowerCase() === 'completed'
    const tab = item.tab || item.label || ''
    const label = item.applicantType
      ? `${tab} - ${item.applicantType}${item.applicantName ? ` (${item.applicantName})` : ''}`
      : tab
    return {
      tab,
      id: item.id,
      label,
      applicantId: item.applicantId,
      applicantType: item.applicantType,
      applicantName: item.applicantName,
      isGroupItem: item.isGroupItem === true,
      applicants: item.applicants || [],
      stagePhrase: item.stagePhrase || '',
      currentStagePhrase: item.stagePhrase || '',
      isStagePast,
      overrideLwc: item.overrideLwc || ''
    }
  }

  handleSectionFieldChange(event) {
    if (this.isReadOnlyMode) return
    const el = event.currentTarget
    const section = el?.dataset?.section
    const key = el?.dataset?.key
    const fieldName = event.currentTarget?.name;
    if (!section || !key) return
    let value
    if (fieldName === 'make' || fieldName === 'model' || fieldName === 'variant') {
      value = event.detail?.value || '';
      if(fieldName === 'make') {
        this.makeName = event.detail?.label || '';
      }
      else if(fieldName === 'model') {
        this.modelName = event.detail?.label || '';
      }
      else if(fieldName === 'variant') {
        this.variantName = event.detail?.label || '';
      }
    }
    else if (el.type === 'checkbox' || el.type === 'radio') {
      value = el.type === 'radio' ? el.value : el.checked
    } else if (event.detail?.checked != null) {
      value = event.detail.checked
    } else {
      value = event.detail?.value ?? event.target?.value ?? ''
    }
    this._updateSectionField(section, key, value)
    if(fieldName === 'make') {
      const modelPicker = this.getPickerBySearchField('Model__c');
      if (modelPicker) {
          modelPicker.getModelList(this.productTypeFullForm, this.make);
      }
      const variantPicker = this.getPickerBySearchField('Variant__c');
      if (variantPicker) {
          variantPicker.getVariantList(this.productTypeFullForm, this.make, this.model);
      }
    }
    else if(fieldName === 'model') {
      const variantPicker = this.getPickerBySearchField('Variant__c');
      if (variantPicker) {
          variantPicker.getVariantList(this.productTypeFullForm, this.make, this.model);
      }
    }
  }

  async createAdditionalAsset() {
    const response = await createAdditionalAssetApex({
      recordId: this.recordId,
      assetId: this._apiSelectedAssetId || null,
      make: this.make,
      makeName: this.makeName,
      model: this.model,
      modelName: this.modelName,
      variant: this.variant,
      variantName: this.variantName,
      numberOfVehicles: this.numberOfVehicles
    })

    if (!response?.isSuccess) {
      throw new Error(response?.message || 'Unable to create additional assets.')
    }

    if (response.assetId) {
      this.assetId = response.assetId
      this._apiSelectedAssetId = response.assetId
    }
  }

  async handleFetchPrice() {
    if (this.isFetchPriceDisabled) return

    try {
      await this.createAdditionalAsset()
    } catch (error) {
      this._toast(
        'Error',
        error?.body?.message || error?.message || 'Unable to create additional assets.',
        'error'
      )
      return
    }

    this._lastActionFieldKey = 'fetchPrice'
    await invokeHandler('clientLayerVehicleDetails', 'onAction', this)
  }

  async handleNextButton() {
    // eslint-disable-next-line no-console
    console.log(`${LOG_PREFIX} Next clicked`, {
      recordId: this.recordId,
      applicantId: this.applicantId,
      currentViewId: this.currentViewId,
      stagePhrase: this.stagePhrase,
      tab: this.tab,
      isReadOnlyMode: this.isReadOnlyMode,
      isStagePast: this._isStagePast,
      menuNavContext: this._menuNavContext,
      resolvedNav: this._resolveNavContext()
    })

    if (!this.recordId) {
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} Next aborted — recordId is missing`)
      return
    }
    if (this.isReadOnlyMode) {
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} Next skipped save — read-only mode, navigating only`)
      if (this.fromAssetList) {
        this.returnToAssetList(false)
        return
      }
      await this.dispatchNextStage()
      return
    }
    const missingRequiredLabels = this.getMissingMandatoryFieldLabels()
    if (missingRequiredLabels.length > 0) {
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} Next aborted — missing required fields`, missingRequiredLabels)
      this._toast(
        'Missing Required Fields',
        `Please fill mandatory fields: ${missingRequiredLabels.join(', ')}`,
        'error'
      )
      return
    }

    const saveRequest = {
      apexClassName: APEX_CLASS,
      apexMethodName: SAVE_APEX_METHOD,
      recordId: this.recordId,
      params: this._buildSaveParams()
    }
    // eslint-disable-next-line no-console
    console.log(`${LOG_PREFIX} savePageData request`, saveRequest)

    this.isLoading = true
    window.dispatchEvent(
      new CustomEvent('losgloballoader', {
        detail: { show: true, message: 'Saving Vehicle Details...' }
      })
    )
    let navigationDispatched = false
    try {
      const response = await savePageData(saveRequest)
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} savePageData response`, response)
      if (response?.isSuccess) {
        this.hasPersistedPricing = true
        // eslint-disable-next-line no-console
        console.log(`${LOG_PREFIX} save succeeded — advancing stage`)
        if (this.fromAssetList) {
          this.returnToAssetList(true)
          return
        }
        navigationDispatched = true
        await this.dispatchNextStage()
      } else {
        // eslint-disable-next-line no-console
        console.log(`${LOG_PREFIX} save failed (isSuccess=false)`, {
          message: response?.message,
          response
        })
        this._toast('Save Failed', response?.message || 'Failed to save data.', 'error')
      }
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(`${LOG_PREFIX} savePageData exception`, {
        message: e?.body?.message || e?.message,
        body: e?.body,
        stack: e?.stack,
        error: e
      })
      const msg = e?.body?.message || e?.message || 'An unexpected error occurred.'
      this._toast('Error', msg, 'error')
    } finally {
      this.isLoading = false
      if (!navigationDispatched) {
        window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }))
      }
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

  async dispatchNextStage() {
    const nav = this._resolveNavContext()
    // eslint-disable-next-line no-console
    console.log(`${LOG_PREFIX} dispatchNextStage`, JSON.parse(JSON.stringify({
      nav,
      menuNavContext: this._menuNavContext,
      lastMenuDetail: VehicleDetailsMasterPage._lastMenuDetail
    })))

    if (!nav.currentViewId) {
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} dispatchNextStage aborted — currentViewId is missing`)
      this._toast(
        'Navigation Error',
        'Current view ID is missing. Please select this stage from the menu and try again.',
        'error'
      )
      return
    }

    if (!nav.stagePhrase) {
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} dispatchNextStage aborted — stagePhrase is missing`, nav)
      this._toast(
        'Navigation Error',
        'Stage phrase is missing. Please re-select Asset Details from the menu and try again.',
        'error'
      )
      return
    }

    const nextStageDetail = {
      currentViewId: nav.currentViewId,
      id: nav.currentViewId,
      applicantId: nav.applicantId,
      currentLoanStageComplete: nav.tab,
      currentStagePhrase: nav.stagePhrase
    }
    // eslint-disable-next-line no-console
    console.log(`${LOG_PREFIX} losnextstage detail`, JSON.parse(JSON.stringify(nextStageDetail)))

    window.dispatchEvent(
      new CustomEvent('losgloballoader', {
        detail: { show: true, message: 'Processing...' }
      })
    )

    window.dispatchEvent(
      new CustomEvent(LOS_NEXT_STAGE_EVENT, {
        detail: nextStageDetail,
        bubbles: true,
        composed: true
      })
    )

    try {
      const result = await processNextStageRequest({
        applicationId: this.recordId,
        currentStagePhrase: nav.stagePhrase,
        currentLoanStageName: nav.tab || STAGE_VEHICLE_DETAILS
      })
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} processNextStageRequest result`, {
        isSuccess: result?.isSuccess,
        message: result?.message,
        menuItemCount: result?.navigationState?.menuItems?.length
      })

      if (!result?.isSuccess) {
        this._toast('Navigation Failed', result?.message || 'Unable to advance to the next stage.', 'error')
        return
      }

      const navState = result.navigationState
      if (!navState?.menuItems?.length) {
        // eslint-disable-next-line no-console
        console.log(`${LOG_PREFIX} processNextStageRequest returned no menuItems`)
        this._toast('Navigation Failed', 'No navigation state returned from the server.', 'error')
        return
      }

      window.dispatchEvent(
        new CustomEvent(LOS_NAVIGATION_STATE_EVENT, {
          detail: { navigationState: navState },
          bubbles: true,
          composed: true
        })
      )

      const nextViewItem = this._findCurrentViewMenuItem(navState.menuItems)
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} next view menu item`, JSON.parse(JSON.stringify(nextViewItem || {})))

      if (!nextViewItem) {
        this._toast('Navigation Failed', 'Next stage could not be resolved. Please refresh the page.', 'error')
        return
      }

      const menuSelectDetail = this._buildMenuSelectDetail(nextViewItem)
      // eslint-disable-next-line no-console
      console.log(`${LOG_PREFIX} dispatching losmenuselect`, JSON.parse(JSON.stringify(menuSelectDetail)))

      window.dispatchEvent(
        new CustomEvent(LOS_MENU_SELECT_EVENT, {
          detail: menuSelectDetail,
          bubbles: true,
          composed: true
        })
      )
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error(`${LOG_PREFIX} processNextStageRequest exception`, {
        message: error?.body?.message || error?.message,
        body: error?.body,
        error
      })
      this._toast(
        'Navigation Error',
        error?.body?.message || error?.message || 'Error while advancing stage.',
        'error'
      )
    } finally {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => {
        window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }))
      }, 1500)
    }
  }

  getMissingMandatoryFieldLabels() {
    const missing = []
    if (!hasVal(this.make)) {
      missing.push('Make')
    }
    if (!hasVal(this.model)) {
      missing.push('Model')
    }
    if (!hasVal(this.variant)) {
      missing.push('Variant')
    }
    if (!this._isValidNumberOfVehicles()) {
      missing.push('Number of Vehicles')
    }
    if (!this.isFetchPriceSuccess && !this.hasPersistedPricing) {
      missing.push('Fetch Price')
      return missing
    }
    if (this.showPricingDetails) {
      const v = this.pricingDetailsFieldValues || {}
      if (!hasVal(v.basicPrice)) missing.push('Basic Price')
      if (!hasVal(v.discountOnBasicPrice)) missing.push('Discount on Basic Price')
      if (!hasVal(v.gstAmount)) missing.push('GST Amount')
      if (!hasVal(v.exShowroomPrice)) missing.push('Ex Showroom Price')
    }
    if (this.showDealerRegistration) {
      if (!hasVal(this.drDealerSubDealerName)) {
        missing.push('Dealer/Sub-Dealer Name')
      }
      if (!hasVal(this.drStateOfUtilizationOfAsset)) {
        missing.push('State Of Utilization Of Asset')
      }
      if (!hasVal(this.drDistrictOfUtilizationOfAsset)) {
        missing.push('District Of Utilization Of Asset')
      }
    }
    if (this.showLoanInformation) {
      const v = this.loanInformationFieldValues || {}
      if (!hasVal(v.requiredLoanAmount)) missing.push('Required Loan Amount')
      if (!hasVal(v.requiredIrr)) missing.push('Required IRR')
      if (!hasVal(v.requiredTenure)) missing.push('Required Tenure')
      if (!hasVal(v.fundingBasedOn)) missing.push('Funding Based On')
    }
    return [...new Set(missing)]
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
      console.error('[vehicleDetailsMasterPage] _refreshViabilityCheckFlag:', e)
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
      console.error('[vehicleDetailsMasterPage] _refreshHireVsBuyFlag:', e)
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

  _scheduleLoadPageData() {
    if (!this._recordId) {
      this._resetVehicleSelection()
      this.isLoading = false
      return
    }
    if (this._pageDataLoadScheduled) {
      return
    }
    this._pageDataLoadScheduled = true
    Promise.resolve().then(() => {
      this._pageDataLoadScheduled = false
      this._loadPageData()
    })
  }

  _resetFetchPriceUiState() {
    this.fetchPriceResponse = null
    this.fetchPriceData = null
    this.fetchPriceErrorMessage = ''
    this._onRoadPriceFromFetch = false
    this._vehicleActionStates = { ...this._vehicleActionStates, fetchPrice: 'idle' }
  }

  _applyPageMetadata(d = {}) {
    this.isPageReadOnly = d.isReadOnly === true
    this.productType = d.productType || ''
    this.productTypeFullForm = d.productTypeFullForm || ''
    if (!this.hasPersistedLoan && d.maximumAvailableTenure != null) {
      this.loanInformationFieldValues = {
        ...this.loanInformationFieldValues,
        maximumAvailableTenure: String(d.maximumAvailableTenure)
      }
    }
  }

  async _loadPageData() {
    if (!this.recordId) {
      this._resetVehicleSelection()
      this.isLoading = false
      return
    }

    const loadToken = ++this._pageDataLoadToken
    const requestedAssetId = this._apiSelectedAssetId || ''
    const isAssetScopedLoad = hasVal(requestedAssetId)

    this.isLoading = true
    try {
      const data = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: APEX_METHOD,
        recordId: this.recordId,
        params: this._buildPageParams()
      })
      if (loadToken !== this._pageDataLoadToken) {
        return
      }

      const d = data || {}
      const hasAssetPayload = d.assetId != null

      this._applyPageMetadata(d)

      if (!isAssetScopedLoad && !hasAssetPayload) {
        return
      }

      this.assetId = d.assetId || null
      this.vehicleType = d.vehicleType || ''
      this.make = d.make || ''
      this.makeName = d.makeName || ''
      this.model = d.model || ''
      this.modelName = d.modelName || ''
      this.variant = d.variant || ''
      this.variantName = d.variantName || ''
      this.numberOfVehicles = d.numberOfVehicles != null && String(d.numberOfVehicles).trim() !== ''
        ? String(d.numberOfVehicles)
        : '1'
      if (d.hasPricingData) {
        this._hydratePricingFromPageData(d)
      } else {
        this.hasPersistedPricing = false
        this.pricingDetailsFieldValues = {}
        this._resetFetchPriceUiState()
      }
      this.hasViabilityCheckSaved = d.hasViabilityData === true
      this.hasHireVsBuySaved = d.hasHireVsBuyData === true
      if (d.hasLoanData) {
        this._hydrateLoanFromPageData(d)
      } else {
        this.hasPersistedLoan = false
        this.loanInformationFieldValues = {
          ...LOAN_INFORMATION_DEFAULTS,
          maximumAvailableTenure: String(d.maximumAvailableTenure ?? MAXIMUM_AVAILABLE_TENURE_MONTHS)
        }
      }
      this._hydrateDealerFromPageData(d)
      if (!hasVal(this.make) && !this.isReadOnlyMode) {
        const makePicker = this.getPickerBySearchField('Make__c')
        if (makePicker) {
          makePicker.getMakeList(this.productTypeFullForm)
        }
      }
    } catch (e) {
      if (loadToken !== this._pageDataLoadToken) {
        return
      }
      console.error('[vehicleDetailsMasterPage] _loadPageData:', e)
      this._resetVehicleSelection()
    } finally {
      if (loadToken === this._pageDataLoadToken) {
        this.isLoading = false
      }
    }
  }

  getPickerBySearchField(searchFieldApiName) {
    const pickers = this.template.querySelectorAll('c-mmv-record-picker');
    return Array.from(pickers).find((picker) => picker.searchFieldApiName === searchFieldApiName);
  }

  _resetVehicleSelection() {
    this.assetId = null;
    this.make = '';
    this.makeName = '';
    this.model = '';
    this.modelName = '';
    this.variant = '';
    this.variantName = '';
    this.numberOfVehicles = '1';
    this.isPageReadOnly = false;
    this._resetPageFormState()
  }

  /** Clears fetch + pricing only (MMV change). Keeps loan, dealer, and viability. */
  _clearPricingAndFetchState() {
    this.fetchPriceResponse = null
    this.fetchPriceData = null
    this.fetchPriceErrorMessage = ''
    this.pricingDetailsFieldValues = {}
    this.hasPersistedPricing = false
    this._onRoadPriceFromFetch = false
    this._vehicleActionStates = { ...this._vehicleActionStates, fetchPrice: 'idle' }
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

  /** Full form reset (load error / empty record). */
  _resetPageFormState() {
    this._clearPricingAndFetchState()
    this.loanInformationFieldValues = { ...LOAN_INFORMATION_DEFAULTS }
    this.hasPersistedLoan = false
    this.dealerRegistrationFieldValues = { ...DEALER_REGISTRATION_DEFAULTS }
    this.hasViabilityCheckSaved = false
    this.hasHireVsBuySaved = false
  }

  _buildPageParams() {
    return {
      assetId: this._apiSelectedAssetId || null
    }
  }

  _buildSaveParams() {
    const loan = this.loanInformationFieldValues || {}
    const fundingBasedOn = loan.fundingBasedOn || ''
    return {
      make: this.make,
      makeName: this.makeName,
      model: this.model,
      modelName: this.modelName,
      variant: this.variant,
      variantName: this.variantName,
      numberOfVehicles: this.numberOfVehicles,
      assetId: this._apiSelectedAssetId || null,
      ...this.pricingDetailsFieldValues,
      requiredLoanAmount: loan.requiredLoanAmount,
      requiredIrr: loan.requiredIrr,
      requiredTenure: loan.requiredTenure,
      fundingOnOrp: fundingBasedOn === 'On-road Price',
      fundingOnExShowroom: fundingBasedOn === 'Ex-showroom Price',
      dealerSubDealerName: this.dealerRegistrationFieldValues.dealerSubDealerName,
      rcLimitEnabledDealer: this.dealerRegistrationFieldValues.rcLimitEnabledDealer,
      invoiceInNameOf: this.dealerRegistrationFieldValues.invoiceInNameOf,
      vehicleRegisteredInNameOf: this.dealerRegistrationFieldValues.vehicleRegisteredInNameOf,
      stateOfUtilizationOfAsset: this.dealerRegistrationFieldValues.stateOfUtilizationOfAsset,
      districtOfUtilizationOfAsset: this.dealerRegistrationFieldValues.districtOfUtilizationOfAsset
    }
  }

  _isPricingSectionComplete() {
    const v = this.pricingDetailsFieldValues || {}
    return (
      hasVal(v.basicPrice) &&
      hasVal(v.discountOnBasicPrice) &&
      hasVal(v.gstAmount) &&
      hasVal(v.exShowroomPrice)
    )
  }

  _isDealerRegistrationSectionComplete() {
    return (
      hasVal(this.drDealerSubDealerName) &&
      hasVal(this.drStateOfUtilizationOfAsset) &&
      hasVal(this.drDistrictOfUtilizationOfAsset)
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

  _hydrateDealerFromPageData(d) {
    this.dealerRegistrationFieldValues = {
      ...DEALER_REGISTRATION_DEFAULTS,
      dealerSubDealerName: d.dealerSubDealerName ?? '',
      rcLimitEnabledDealer: d.rcLimitEnabledDealer === true || d.rcLimitEnabledDealer === 'true',
      invoiceInNameOf: d.invoiceInNameOf ?? '',
      vehicleRegisteredInNameOf: d.vehicleRegisteredInNameOf ?? 'Borrower',
      stateOfUtilizationOfAsset: d.stateOfUtilizationOfAsset ?? '',
      districtOfUtilizationOfAsset: d.districtOfUtilizationOfAsset ?? ''
    }
  }

  _hydratePricingFromPageData(d) {
    if (!d?.hasPricingData) return
    this.pricingDetailsFieldValues = {
      firstYearInsurancePremium: d.firstYearInsurancePremium ?? '',
      motorInsurancePremium: d.motorInsurancePremium ?? '',
      basicPrice: d.basicPrice ?? '',
      gstAmount: d.gstAmount ?? '',
      discountOnBasicPrice: d.discountOnBasicPrice ?? '',
      exShowroomPrice: d.exShowroomPrice ?? '',
      onRoadPrice: d.onRoadPrice ?? ''
    }
    this.hasPersistedPricing = true
    this.fetchPriceData = { ...this.pricingDetailsFieldValues }
    this._vehicleActionStates = { ...this._vehicleActionStates, fetchPrice: 'success' }
  }

  _hydratePricingFromFetchData(data) {
    if (!data) return
    this._onRoadPriceFromFetch = false
    this.pricingDetailsFieldValues = {
      firstYearInsurancePremium: '',
      basicPrice: data.basicPrice ?? '',
      gstAmount: data.cess ?? '',
      motorInsurancePremium: data.insurance ?? '',
      discountOnBasicPrice: data.discountOnBasicPrice ?? '',
      exShowroomPrice: '',
      onRoadPrice: ''
    }
    this._recalculatePricing()
    const apiOnRoad = Number(data.onRoadPrice)
    if (!Number.isNaN(apiOnRoad) && apiOnRoad > 0) {
      this.pricingDetailsFieldValues = {
        ...this.pricingDetailsFieldValues,
        onRoadPrice: apiOnRoad
      }
      this._onRoadPriceFromFetch = true
    }
  }

  _updateSectionField(section, key, value) {
    if (section === 'vehicleSelection') {
      if (key === 'make') {
        this.make = value
        this.model = ''
        this.variant = ''
        this._clearPricingAndFetchState()
        return
      }
      if (key === 'model') {
        this.model = value
        this.variant = ''
        this._clearPricingAndFetchState()
        return
      }
      if (key === 'variant') {
        this.variant = value
        this._clearPricingAndFetchState()
        return
      }
      if (key === 'numberOfVehicles') {
        this.numberOfVehicles = value
        this._clearPricingAndFetchState()
      }
      return
    }

    if (section === 'pricingDetails') {
      this.pricingDetailsFieldValues = {
        ...this.pricingDetailsFieldValues,
        [key]: value
      }
      if (PRICING_RECALC_FROM_BASIC_KEYS.has(key)) {
        this._onRoadPriceFromFetch = false
        this._recalculatePricing()
      } else if (PRICING_RECALC_FROM_EX_SHOWROOM_KEYS.has(key)) {
        this._onRoadPriceFromFetch = false
        this._recalculatePricingFromExShowroom()
      }
      this._resetAssetDependentChecksIfSaved()
      return
    }

    if (section === 'loanInformation') {
      this.loanInformationFieldValues = {
        ...this.loanInformationFieldValues,
        [key]: value
      }
      this._resetAssetDependentChecksIfSaved()
      return
    }

    if (section === 'dealerRegistration') {
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
  }

  _recalculatePricing() {
    const basic = Number(this.pricingDetailsFieldValues.basicPrice) || 0
    const discount = Number(this.pricingDetailsFieldValues.discountOnBasicPrice) || 0
    const gst = Number(this.pricingDetailsFieldValues.gstAmount) || 0
    const exShowroom = basic - discount + gst
    this.pricingDetailsFieldValues = {
      ...this.pricingDetailsFieldValues,
      exShowroomPrice: exShowroom
    }
    this._recalculatePricingFromExShowroom()
  }

  _recalculatePricingFromExShowroom() {
    if (this._onRoadPriceFromFetch) {
      return
    }
    const exShowroom = Number(this.pricingDetailsFieldValues.exShowroomPrice) || 0
    this.pricingDetailsFieldValues = {
      ...this.pricingDetailsFieldValues,
      onRoadPrice: exShowroom
    }
  }

  _formatAmount(value) {
    if (value == null || value === '') return '0'
    const num = Number(value)
    if (Number.isNaN(num)) return String(value)
    return num.toLocaleString('en-IN')
  }

  _isValidNumberOfVehicles() {
    const num = Number(this.numberOfVehicles)
    return Number.isInteger(num) && num >= 1
  }

  get fields() {
    return [
      { key: 'make', value: this.make },
      { key: 'makeName', value: this.makeName },
      { key: 'model', value: this.model },
      { key: 'modelName', value: this.modelName },
      { key: 'variant', value: this.variant },
      { key: 'variantName', value: this.variantName },
      { key: 'numberOfVehicles', value: this.numberOfVehicles },
      { key: 'fetchPriceResponse', value: this.fetchPriceResponse },
      { key: 'fetchPriceData', value: this.fetchPriceData },
      { key: 'fetchPriceErrorMessage', value: this.fetchPriceErrorMessage }
    ]
  }

  setActionState(key, state) {
    if (key !== 'fetchPrice') return
    if (!['idle', 'loading', 'success'].includes(state)) return
    this._vehicleActionStates = { ...this._vehicleActionStates, fetchPrice: state }
  }

  updateFieldValue(key, value) {
    if (key === 'fetchPriceResponse') {
      this.fetchPriceResponse = value
      return
    }
    if (key === 'fetchPriceData') {
      this.fetchPriceData = value
      this._hydratePricingFromFetchData(value)
      return
    }
    if (key === 'fetchPriceErrorMessage') {
      this.fetchPriceErrorMessage = value || ''
      if (this.fetchPriceErrorMessage) {
        this._toast('Fetch Price Failed', this.fetchPriceErrorMessage, 'error')
      }
    }
  }

  _toast(title, message, variant = 'error') {
    this.dispatchEvent(
      new CustomEvent('showtoast', {
        detail: { title, message, variant },
        bubbles: true,
        composed: true
      })
    )
  }
}