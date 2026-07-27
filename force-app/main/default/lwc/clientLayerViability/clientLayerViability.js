import { LightningElement } from 'lwc'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'
import cvViabilityApi from '@salesforce/apex/ViabilityCheckController.cvViabilityApi'

const APEX_CLASS = 'ViabilityCheckController'
const SAVE_CV_APEX_METHOD = 'saveCvViabilityCheckData'
const SAVE_KMS_APEX_METHOD = 'saveKmsViabilityCheckData'
const CV_API_STAGES = ['CV Viability API', 'Normalize Response', 'Save Viability']
const KMS_SAVE_STAGES = ['Save KMS Viability']

function getFieldValue(ctx, key) {
  return ctx?.fields?.find((f) => f.key === key)?.value
}

function getCvPayload(ctx) {
  return {
    recordId: getFieldValue(ctx, 'recordId'),
    assetId: getFieldValue(ctx, 'assetId'),
    calculationBasis: getFieldValue(ctx, 'calculationBasis'),
    assetDeployment: getFieldValue(ctx, 'assetDeployment'),
    daysPerMonth: getFieldValue(ctx, 'daysPerMonth'),
    hoursPerDay: getFieldValue(ctx, 'hoursPerDay'),
    ratePerHour: getFieldValue(ctx, 'ratePerHour'),
    estimatedMonthlyIncome: getFieldValue(ctx, 'estimatedMonthlyIncome'),
    fuelCostPerLitre: getFieldValue(ctx, 'fuelCostPerLitre'),
    fuelConsumptionPerHour: getFieldValue(ctx, 'fuelConsumptionPerHour'),
    costFuelPerMonth: getFieldValue(ctx, 'costFuelPerMonth'),
    operatorSalary: getFieldValue(ctx, 'operatorSalary'),
    maintenanceParts: getFieldValue(ctx, 'maintenanceParts'),
    tyreCost: getFieldValue(ctx, 'tyreCost'),
    taxCess: getFieldValue(ctx, 'taxCess'),
    others: getFieldValue(ctx, 'others'),
    totalExpenses: getFieldValue(ctx, 'totalExpenses'),
    grossSurplus: getFieldValue(ctx, 'grossSurplus'),
    instalment: getFieldValue(ctx, 'instalment'),
    netSurplus: getFieldValue(ctx, 'netSurplus'),
    viabilityRatio: getFieldValue(ctx, 'viabilityRatio')
  }
}

function getKmsPayload(ctx) {
  return {
    recordId: getFieldValue(ctx, 'recordId'),
    assetId: getFieldValue(ctx, 'assetId'),
    vehicleRoute: getFieldValue(ctx, 'vehicleRoute'),
    fromLocation: getFieldValue(ctx, 'fromLocation'),
    toLocation: getFieldValue(ctx, 'toLocation'),
    tripsPerMonth: getFieldValue(ctx, 'tripsPerMonth'),
    kilometersPerTrip: getFieldValue(ctx, 'kilometersPerTrip'),
    averageRatePerTrip: getFieldValue(ctx, 'averageRatePerTrip'),
    estimatedMonthlyIncome: getFieldValue(ctx, 'estimatedMonthlyIncome'),
    fuelRatePerLitre: getFieldValue(ctx, 'fuelRatePerLitre'),
    costFuelPerTrip: getFieldValue(ctx, 'costFuelPerTrip'),
    costFuelPerMonth: getFieldValue(ctx, 'costFuelPerMonth'),
    salaries: getFieldValue(ctx, 'salaries'),
    maintenance: getFieldValue(ctx, 'maintenance'),
    tyreCost: getFieldValue(ctx, 'tyreCost'),
    motorTaxPermitCost: getFieldValue(ctx, 'motorTaxPermitCost'),
    others: getFieldValue(ctx, 'others'),
    totalExpenses: getFieldValue(ctx, 'totalExpenses'),
    grossSurplus: getFieldValue(ctx, 'grossSurplus'),
    instalment: getFieldValue(ctx, 'instalment'),
    netSurplus: getFieldValue(ctx, 'netSurplus')
  }
}

function dispatchIntegrationProgressUpdate(ctx, payload) {
  const ev = new CustomEvent('integrationprogressupdate', {
    detail: payload,
    bubbles: true,
    composed: true
  })
  ctx.dispatchEvent(ev)
  window.dispatchEvent(ev)
}

function showLoading(ctx, stages, currentStageIndex) {
  dispatchIntegrationProgressUpdate(ctx, {
    show: true,
    status: 'loading',
    currentStageIndex,
    stages,
    errorMessage: ''
  })
}

function showError(ctx, stages, currentStageIndex, errorMessage) {
  dispatchIntegrationProgressUpdate(ctx, {
    show: true,
    status: 'error',
    currentStageIndex,
    stages,
    errorMessage: errorMessage || 'Unable to complete viability action'
  })
}

function hideProgress(ctx, stages) {
  dispatchIntegrationProgressUpdate(ctx, {
    show: false,
    status: 'loading',
    currentStageIndex: stages.length,
    stages,
    errorMessage: ''
  })
}

function getErrorMessage(error, fallback) {
  return error?.body?.message || error?.message || fallback
}

function normalizeCvApiResponse(responseData) {
  const d = responseData || {}
  const normalizedViabilityRatio = d.viabilityRatio ?? d.ViabilityRatio ?? ''
  return {
    calculationBasis: d.calculationBasis || d.Calculation_Basis || 'Hourly',
    cvHourlyValues: {
      ...(d.cvHourlyValues || d.hourly || {}),
      viabilityRatio: normalizedViabilityRatio
    },
    kmsValues: d.kmsValues || d.kms || {}
  }
}

async function handleCvViabilityCheck(ctx) {
  const stages = CV_API_STAGES
  try {
    ctx.setActionState('cvViabilityCheck', 'loading')
    showLoading(ctx, stages, 0)
    const cvApiResult = await cvViabilityApi({ payload: getCvPayload(ctx) })
    if (!cvApiResult?.isSuccess) {
      ctx.setActionState('cvViabilityCheck', 'idle')
      const message = cvApiResult?.message || 'CV viability API failed'
      ctx.updateFieldValue('errorMessage', message)
      showError(ctx, stages, 0, message)
      return
    }

    showLoading(ctx, stages, 1)
    ctx.updateFieldValue('cvApiResponse', normalizeCvApiResponse(cvApiResult?.data))

    showLoading(ctx, stages, 2)
    const saveResponse = await savePageData({
      apexClassName: APEX_CLASS,
      apexMethodName: SAVE_CV_APEX_METHOD,
      recordId: getFieldValue(ctx, 'recordId'),
      params: getCvPayload(ctx)
    })
    if (!saveResponse?.isSuccess) {
      ctx.setActionState('cvViabilityCheck', 'idle')
      const message = saveResponse?.message || 'Unable to save CV viability details.'
      ctx.updateFieldValue('errorMessage', message)
      showError(ctx, stages, 2, message)
      return
    }
    ctx.setActionState('cvViabilityCheck', 'success')
    ctx.updateFieldValue('errorMessage', '')
    hideProgress(ctx, stages)
  } catch (error) {
    ctx.setActionState('cvViabilityCheck', 'idle')
    const message = getErrorMessage(error, 'Unable to complete CV viability check.')
    ctx.updateFieldValue('errorMessage', message)
    showError(ctx, stages, 0, message)
  }
}

async function handleKmsViabilityCheck(ctx) {
  const stages = KMS_SAVE_STAGES
  try {
    ctx.setActionState('kmsViabilityCheck', 'loading')
    showLoading(ctx, stages, 0)
    const response = await savePageData({
      apexClassName: APEX_CLASS,
      apexMethodName: SAVE_KMS_APEX_METHOD,
      recordId: getFieldValue(ctx, 'recordId'),
      params: getKmsPayload(ctx)
    })
    if (!response?.isSuccess) {
      ctx.setActionState('kmsViabilityCheck', 'idle')
      const message = response?.message || 'Unable to save KMS viability details.'
      ctx.updateFieldValue('errorMessage', message)
      showError(ctx, stages, 0, message)
      return
    }
    ctx.setActionState('kmsViabilityCheck', 'success')
    ctx.updateFieldValue('errorMessage', '')
    hideProgress(ctx, stages)
  } catch (error) {
    ctx.setActionState('kmsViabilityCheck', 'idle')
    const message = getErrorMessage(error, 'Unable to complete KMS viability check.')
    ctx.updateFieldValue('errorMessage', message)
    showError(ctx, stages, 0, message)
  }
}

export async function onLoad(submodulename, ctx) {
  if (submodulename !== 'onAction') return
  const key = ctx?._lastActionFieldKey
  if (key === 'cvViabilityCheck') {
    await handleCvViabilityCheck(ctx)
    return
  }
  if (key === 'kmsViabilityCheck') {
    await handleKmsViabilityCheck(ctx)
  }
}

export default class ClientLayerViability extends LightningElement {}