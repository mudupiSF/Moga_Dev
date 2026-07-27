import { LightningElement, api, track } from 'lwc'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'
import { invokeHandler } from 'c/clientLayerHelper'
import {
  CALCULATION_BASIS_OPTIONS,
  ASSET_DEPLOYMENT_OPTIONS,
  VEHICLE_ROUTE_OPTIONS
} from './picklistValuesHelper'
import {
  PRODUCT_CV,
  CALCULATION_BASIS_HOURLY,
  CALCULATION_BASIS_KMS,
  CV_HOURLY_INCOME_KEYS,
  CV_HOURLY_EXPENSE_KEYS,
  KMS_INCOME_KEYS,
  KMS_EXPENSE_KEYS,
  BASE_VIABILITY_DEFAULTS,
  CV_HOURLY_DEFAULTS,
  KMS_DEFAULTS
} from './viabilityConstants'

const hasVal = (v) => v != null && String(v).trim() !== ''
const APEX_CLASS = 'ViabilityCheckController'
const APEX_METHOD = 'getViabilityCheckData'
const SAVE_APEX_METHOD = 'saveViabilityCheckData'
const CLIENT_LAYER_ACTION_NAME = 'clientLayerViability'
const INTEGRATION_PROGRESS_EVENT = 'integrationprogressupdate'
const COMMERCIAL_PURPOSE = 'Commercial'

export default class ViabilityCheck extends LightningElement {
  _recordId
  _assetId
  _loadDebounce
  _activeLoadToken = 0
  @api isReadOnly = false
  /** When true, existing viability data can still be edited (e.g. asset details changed). */
  @api allowEditWhenExisting = false

  @api
  get recordId() {
    return this._recordId
  }

  set recordId(value) {
    this._recordId = value
    this._scheduleLoad()
  }

  @api
  get assetId() {
    return this._assetId
  }

  set assetId(value) {
    this._assetId = value ? String(value) : null
    this._scheduleLoad()
  }

  @track isLoading = false
  @track formValues = { ...BASE_VIABILITY_DEFAULTS }
  @track errorMessage = ''
  @track hasExistingViabilityData = false
  @track productType = ''
  @track assetPurposeOfPurchase = ''
  @track calculationBasis = ''
  @track cvViabilityId = ''
  @track cvHourlyValues = { ...CV_HOURLY_DEFAULTS }
  @track kmsValues = { ...KMS_DEFAULTS }
  @track showIntegrationProgressModal = false
  @track integrationProgressModalStatus = 'loading'
  @track integrationProgressModalCurrentStageIdx = 0
  @track integrationProgressModalStages = []
  @track integrationProgressModalErrorMessage = ''

  _lastActionFieldKey = ''
  @track _viabilityActionStates = {}
  _integrationProgressHandler
  get isCv() {
    return this.productType === PRODUCT_CV || this.assetPurposeOfPurchase === COMMERCIAL_PURPOSE
  }

  get isHourly() {
    return this.isCv && this.calculationBasis === CALCULATION_BASIS_HOURLY
  }

  get isKms() {
    return this.isCv && this.calculationBasis === CALCULATION_BASIS_KMS
  }

  get showCvBasisHint() {
    return this.isCv && !this.calculationBasis
  }

  get showCvIncome() {
    return this.isHourly
  }

  get showCvExpense() {
    return this.isHourly && this._isCvIncomeComplete()
  }

  get showKmsIncome() {
    return this.isKms
  }

  get showKmsExpense() {
    return this.isKms && this._isKmsIncomeComplete()
  }

  get calculationBasisOptions() {
    return CALCULATION_BASIS_OPTIONS
  }

  get assetDeploymentOptions() {
    return ASSET_DEPLOYMENT_OPTIONS
  }

  get vehicleRouteOptions() {
    return VEHICLE_ROUTE_OPTIONS
  }

  get cvViabilityRatioDisplay() {
    const saved = Number(this.cvHourlyValues.viabilityRatio)
    if (Number.isFinite(saved)) return saved.toFixed(2)
    return '0.00'
  }

  get kmsViabilityRatioDisplay() {
    const saved = Number(this.kmsValues.viabilityRatio)
    if (Number.isFinite(saved)) return saved.toFixed(2)
    return '0.00'
  }

  get distance() {
    return this.formValues.distance ?? ''
  }

  get grossReceiptsMonth() {
    return this.formValues.grossReceiptsMonth ?? ''
  }

  get numberOfVehiclesOwned() {
    return this.formValues.numberOfVehiclesOwned ?? ''
  }

  get expense() {
    return this.formValues.expense ?? ''
  }

  get vehicleRoute() {
    return this.formValues.vehicleRoute ?? ''
  }

  get viabilityRatioDisplay() {
    if (hasVal(this.formValues.viabilityRatio)) {
      const saved = Number(this.formValues.viabilityRatio)
      if (Number.isFinite(saved)) return saved.toFixed(2)
    }
    const ratio = this._calculateViabilityRatio(
      this.formValues.grossReceiptsMonth,
      this.formValues.expense
    )
    if (ratio === '') return '0.00'
    return Number(ratio).toFixed(2)
  }

  get isSaveDisabled() {
    return this.isLoading || !this._isMandatoryFieldsComplete()
  }

  get isCvCheckDisabled() {
    return this.isLoading || !this._isCvMandatoryFieldsComplete()
  }

  get isKmsCheckDisabled() {
    return this.isLoading || !this._isKmsMandatoryFieldsComplete()
  }

  get isReadOnlyMode() {
    if (this.isReadOnly === true) return true
    if (this.allowEditWhenExisting === true) return false
    return this.hasExistingViabilityData
  }

  connectedCallback() {
    this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e)
    window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler)
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

  handleIntegrationProgressModalDone() {
    this.showIntegrationProgressModal = false
  }

  handleIntegrationProgressModalRetry() {
    const key = this._lastActionFieldKey
    if (key === 'cvViabilityCheck') {
      this.handleCvViabilityCheck()
      return
    }
    if (key === 'kmsViabilityCheck') {
      this.handleKmsViabilityCheck()
    }
  }

  handleFieldChange(event) {
    const key = event.target?.dataset?.key
    if (!key || this.isReadOnlyMode) return
    this.formValues = {
      ...this.formValues,
      [key]: event.detail?.value ?? event.target?.value ?? ''
    }
  }

  handleCalculationBasisChange(event) {
    if (this.isReadOnlyMode) return
    this.calculationBasis = event.detail?.value ?? event.target?.value ?? ''
  }

  handleCvHourlyChange(event) {
    if (this.isReadOnlyMode) return
    const key = event.target?.dataset?.key
    if (!key) return
    this.cvHourlyValues = {
      ...this.cvHourlyValues,
      [key]: event.detail?.value ?? event.target?.value ?? ''
    }
  }

  handleKmsChange(event) {
    if (this.isReadOnlyMode) return
    const key = event.target?.dataset?.key
    if (!key) return
    this.kmsValues = {
      ...this.kmsValues,
      [key]: event.detail?.value ?? event.target?.value ?? ''
    }
  }

  async handleCvViabilityCheck() {
    if (this.isReadOnlyMode || this.isCvCheckDisabled) return
    this.errorMessage = ''
    this._lastActionFieldKey = 'cvViabilityCheck'
    await invokeHandler(CLIENT_LAYER_ACTION_NAME, 'onAction', this)
    if (this._viabilityActionStates.cvViabilityCheck === 'success') {
      this._closeModal(true)
    }
  }

  async handleKmsViabilityCheck() {
    if (this.isReadOnlyMode || this.isKmsCheckDisabled) return
    this.errorMessage = ''
    this._lastActionFieldKey = 'kmsViabilityCheck'
    await invokeHandler(CLIENT_LAYER_ACTION_NAME, 'onAction', this)
    if (this._viabilityActionStates.kmsViabilityCheck === 'success') {
      this._closeModal(true)
    }
  }

  handleCancel() {
    this._closeModal(false)
  }

  _scheduleLoad() {
    if (!this._recordId) return
    if (this._loadDebounce) {
      clearTimeout(this._loadDebounce)
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._loadDebounce = setTimeout(() => {
      this.loadViabilityData()
    }, 50)
  }

  async loadViabilityData() {
    if (!this._recordId) return
    const token = ++this._activeLoadToken
    this.isLoading = true
    this.errorMessage = ''
    try {
      const data = await getPageData({
        apexClassName: APEX_CLASS,
        apexMethodName: APEX_METHOD,
        recordId: this._recordId,
        params: { assetId: this._assetId || null }
      })
      if (token !== this._activeLoadToken) return

      const d = data || {}
      if (d.loadError) {
        this.errorMessage = d.loadError
        return
      }
      if (d.assetId) {
        this._assetId = String(d.assetId)
      }
      this.productType = d.productType ?? ''
      this.assetPurposeOfPurchase = d.purposeOfPurchase ?? ''

      if (this.isCv) {
        this.cvViabilityId = d.viabilityId ?? ''
        this.cvHourlyValues = {
          ...this.cvHourlyValues,
          assetDeployment: d.assetDeployment ?? '',
          daysPerMonth: d.daysPerMonth ?? '',
          hoursPerDay: d.hoursPerDay ?? '',
          ratePerHour: d.ratePerHour ?? '',
          estimatedMonthlyIncome: d.estimatedMonthlyIncome ?? '',
          fuelCostPerLitre: d.fuelCostPerLitre ?? '',
          fuelConsumptionPerHour: d.fuelConsumptionPerHour ?? '',
          costFuelPerMonth: d.costFuelPerMonth ?? '',
          operatorSalary: d.operatorSalary ?? '',
          maintenanceParts: d.maintenanceParts ?? '',
          tyreCost: d.tyreCost ?? '',
          taxCess: d.taxCess ?? '',
          others: d.others ?? '',
          totalExpenses: d.totalExpenses ?? '',
          grossSurplus: d.grossSurplus ?? '',
          instalment: d.instalment ?? '',
          netSurplus: d.netSurplus ?? '',
          viabilityRatio: d.viabilityRatio ?? ''
        }
        this.kmsValues = {
          ...this.kmsValues,
          vehicleRoute: d.vehicleRoute ?? '',
          fromLocation: d.fromLocation ?? '',
          toLocation: d.toLocation ?? '',
          tripsPerMonth: d.tripsPerMonth ?? '',
          kilometersPerTrip: d.kilometersPerTrip ?? '',
          averageRatePerTrip: d.averageRatePerTrip ?? '',
          estimatedMonthlyIncome: d.estimatedMonthlyIncome ?? '',
          fuelRatePerLitre: d.fuelCostPerLitre ?? '',
          costFuelPerTrip: d.costFuelPerTrip ?? '',
          costFuelPerMonth: d.costFuelPerMonth ?? '',
          salaries: d.operatorSalary ?? '',
          maintenance: d.maintenanceParts ?? '',
          tyreCost: d.tyreCost ?? '',
          motorTaxPermitCost: d.taxCess ?? '',
          others: d.others ?? '',
          totalExpenses: d.totalExpenses ?? '',
          grossSurplus: d.grossSurplus ?? '',
          instalment: d.instalment ?? '',
          netSurplus: d.netSurplus ?? '',
          viabilityRatio: d.viabilityRatio ?? ''
        }
        this.hasExistingViabilityData = d.hasCompleteViabilityData === true
        if (this.hasExistingViabilityData) {
          // TODO: Persist Calculation_Basis__c on Viability_Check__c so the basis
          // round-trips. Until then we infer: presence of a KMS-only column
          // (vehicleRoute / fromLocation / kilometersPerTrip) flips the form
          // to KMS, otherwise we default to Hourly.
          const looksLikeKms =
            hasVal(d.vehicleRoute) ||
            hasVal(d.fromLocation) ||
            hasVal(d.kilometersPerTrip)
          this.calculationBasis = looksLikeKms && !hasVal(d.assetDeployment)
            ? CALCULATION_BASIS_KMS
            : CALCULATION_BASIS_HOURLY
        }
        this.errorMessage = ''
        return
      }

      this.formValues = {
        distance: d.distance ?? '',
        grossReceiptsMonth: d.grossReceiptsMonth ?? '',
        numberOfVehiclesOwned: d.numberOfVehiclesOwned ?? '',
        expense: d.expense ?? '',
        vehicleRoute: d.vehicleRoute ?? '',
        viabilityRatio: d.viabilityRatio ?? ''
      }
      this.hasExistingViabilityData = d.hasCompleteViabilityData === true
      this.errorMessage = ''
    } catch (e) {
      if (token !== this._activeLoadToken) return
      this.errorMessage = this._extractApexError(e) || 'Unable to load viability details.'
    } finally {
      if (token === this._activeLoadToken) {
        this.isLoading = false
      }
    }
  }

  async handleSave() {
    if (this.isReadOnlyMode || this.isSaveDisabled) return
    if (!this._assetId) {
      this.errorMessage =
        'Asset ID is missing. Close the modal and open Viability Check again from the asset screen.'
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    try {
      const response = await savePageData({
        apexClassName: APEX_CLASS,
        apexMethodName: SAVE_APEX_METHOD,
        recordId: this._recordId,
        params: {
          assetId: this._assetId || null,
          distance: this.formValues.distance,
          grossReceiptsMonth: this.formValues.grossReceiptsMonth,
          numberOfVehiclesOwned: this.formValues.numberOfVehiclesOwned,
          expense: this.formValues.expense,
          vehicleRoute: this.formValues.vehicleRoute
        }
      })
      if (!response?.isSuccess) {
        this.errorMessage = response?.message || 'Unable to save viability details.'
        return
      }
      this._closeModal(true)
    } catch (e) {
      this.errorMessage = this._extractApexError(e) || 'Unable to save viability details.'
    } finally {
      this.isLoading = false
    }
  }

  setActionState(key, state) {
    this._viabilityActionStates = {
      ...this._viabilityActionStates,
      [key]: state
    }
  }

  updateFieldValue(key, value) {
    if (key === 'errorMessage') {
      this.errorMessage = value || ''
      return
    }
    if (key === 'calculationBasis') {
      this.calculationBasis = value || ''
      return
    }
    if (key === 'cvApiResponse') {
      this._applyCvApiResponse(value)
      return
    }
  }

  _applyCvApiResponse(payload) {
    const d = payload || {}
    if (hasVal(d.calculationBasis)) {
      this.calculationBasis = d.calculationBasis
    }
    if (d.cvHourlyValues && typeof d.cvHourlyValues === 'object') {
      this.cvHourlyValues = { ...this.cvHourlyValues, ...d.cvHourlyValues }
    }
    if (d.kmsValues && typeof d.kmsValues === 'object') {
      this.kmsValues = { ...this.kmsValues, ...d.kmsValues }
    }
  }

  _mapValuesToFields(values = {}) {
    return Object.keys(values).map((key) => ({ key, value: values[key] }))
  }

  get fields() {
    const base = [
      { key: 'recordId', value: this._recordId },
      { key: 'assetId', value: this._assetId || null },
      { key: 'productType', value: this.productType },
      { key: 'calculationBasis', value: this.calculationBasis }
    ]

    if (this.isCv) {
      if (this.isKms) {
        return [...base, ...this._mapValuesToFields(this.kmsValues)]
      }
      if (this.isHourly) {
        return [...base, ...this._mapValuesToFields(this.cvHourlyValues)]
      }
      return base
    }

    return [
      ...base,
      { key: 'distance', value: this.formValues.distance },
      { key: 'grossReceiptsMonth', value: this.formValues.grossReceiptsMonth },
      { key: 'numberOfVehiclesOwned', value: this.formValues.numberOfVehiclesOwned },
      { key: 'expense', value: this.formValues.expense },
      { key: 'vehicleRoute', value: this.formValues.vehicleRoute },
      { key: 'viabilityRatio', value: this.formValues.viabilityRatio }
    ]
  }

  _closeModal(saved = false) {
    this.dispatchEvent(
      new CustomEvent('close', {
        detail: { saved },
        bubbles: true,
        composed: true
      })
    )
  }

  _extractApexError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((item) => item?.message).filter(Boolean).join(', ')
    }
    return (
      error?.body?.message ||
      error?.body?.pageErrors?.[0]?.message ||
      error?.message ||
      ''
    )
  }

  _isMandatoryFieldsComplete() {
    return (
      hasVal(this.formValues.distance) &&
      hasVal(this.formValues.grossReceiptsMonth) &&
      hasVal(this.formValues.numberOfVehiclesOwned) &&
      hasVal(this.formValues.expense) &&
      hasVal(this.formValues.vehicleRoute)
    )
  }

  _isCvIncomeComplete() {
    return CV_HOURLY_INCOME_KEYS.every((key) => hasVal(this.cvHourlyValues[key]))
  }

  _isCvMandatoryFieldsComplete() {
    return (
      this._isCvIncomeComplete() &&
      CV_HOURLY_EXPENSE_KEYS.every((key) => hasVal(this.cvHourlyValues[key]))
    )
  }

  _isKmsIncomeComplete() {
    return KMS_INCOME_KEYS.every((key) => hasVal(this.kmsValues[key]))
  }

  _isKmsMandatoryFieldsComplete() {
    return (
      this._isKmsIncomeComplete() &&
      KMS_EXPENSE_KEYS.every((key) => hasVal(this.kmsValues[key]))
    )
  }

  _calculateViabilityRatio(grossReceiptsMonth, expense) {
    const gross = Number(grossReceiptsMonth)
    const exp = Number(expense)
    if (!Number.isFinite(gross) || !Number.isFinite(exp) || exp <= 0) return ''
    return gross / exp
  }
}