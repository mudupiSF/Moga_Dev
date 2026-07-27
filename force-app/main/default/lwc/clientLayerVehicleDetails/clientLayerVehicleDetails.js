import { LightningElement } from 'lwc'
import fetchVehiclePrice from '@salesforce/apex/VehicleDetailsController.fetchVehiclePrice'
import vehicleDedupe from '@salesforce/apex/VehicleDetailsController.vehicleDedupe'
import vahaanReportApi from '@salesforce/apex/VehicleDetailsController.vahaanReportApi'
import dealMasterApi from '@salesforce/apex/VehicleDetailsController.dealMasterApi'
import getVehicleDetails from '@salesforce/apex/VehicleDetailsController.getVehicleDetails'

const VEHICLE_DEDUPE_STAGES = ['Vehicle Dedupe']
const GET_VEHICLE_DETAILS_STAGES = [
  'Vahaan Report API',
  'DealMaster API',
  'Vehicle Details'
]

const PROGRESS_CLOSE_DELAY_MS = 600

const isApiSuccess = (response) => {
  const statusCode = Number(response?.statusCode || 0)
  return statusCode === 200 && (response?.isSuccess === true || response?.status === 'SUCCESS')
}

function getFieldValue(ctx, key) {
  return ctx?.fields?.find((f) => f.key === key)?.value ?? ''
}

function getUsedDedupeParams(ctx) {
  return {
    recordId: ctx.recordId,
    registrationFormat: getFieldValue(ctx, 'registrationFormat'),
    vehicleSubCategory: getFieldValue(ctx, 'vehicleSubCategory'),
    registrationNumber: getFieldValue(ctx, 'registrationNumber'),
    parentDealNumber: getFieldValue(ctx, 'parentDealNumber'),
    insuranceExpiryDate: getFieldValue(ctx, 'insuranceExpiryDate')
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

function showIntegrationLoading(ctx, stages, currentStageIndex) {
  dispatchIntegrationProgressUpdate(ctx, {
    show: true,
    status: 'loading',
    currentStageIndex,
    stages,
    errorMessage: ''
  })
}

function hideIntegrationProgress(ctx, stages) {
  dispatchIntegrationProgressUpdate(ctx, {
    show: false,
    status: 'loading',
    currentStageIndex: stages.length,
    stages,
    errorMessage: ''
  })
}

function showIntegrationError(ctx, stages, currentStageIndex, errorMessage) {
  dispatchIntegrationProgressUpdate(ctx, {
    show: true,
    status: 'error',
    currentStageIndex,
    stages,
    errorMessage: errorMessage || 'Unable to complete the request'
  })
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function getApiErrorMessage(response, fallback) {
  return response?.message || fallback
}

function getCatchErrorMessage(error, fallback) {
  return error?.body?.message || error?.message || fallback
}

function isVehicleDedupeProceedAllowed(dedupeData) {
  const content = dedupeData?.response?.content
  if (!Array.isArray(content) || content.length === 0) return false
  return content[0]?.Proceed_Flag === 'Y'
}

async function handleFetchPrice(ctx) {
  const make = getFieldValue(ctx, 'make')
  const model = getFieldValue(ctx, 'model')
  const variant = getFieldValue(ctx, 'variant')

  if (!make || !model || !variant) return

  try {
    ctx.setActionState('fetchPrice', 'loading')
    const response = await fetchVehiclePrice({
      recordId: ctx.recordId,
      make,
      model,
      variant
    })
    if (isApiSuccess(response)) {
      ctx.updateFieldValue('fetchPriceResponse', response || null)
      ctx.updateFieldValue('fetchPriceData', response?.data || null)
      ctx.updateFieldValue('fetchPriceErrorMessage', '')
      ctx.setActionState('fetchPrice', 'success')
      return
    }

    ctx.setActionState('fetchPrice', 'idle')
    ctx.updateFieldValue(
      'fetchPriceErrorMessage',
      getApiErrorMessage(response, 'Unable to fetch vehicle price')
    )
  } catch (error) {
    ctx.setActionState('fetchPrice', 'idle')
    ctx.updateFieldValue('fetchPriceErrorMessage', getCatchErrorMessage(error, 'Unable to fetch price'))
  }
}

async function handleVehicleDedupe(ctx) {
  if (ctx.isVehicleDedupeDisabled) return
  const params = getUsedDedupeParams(ctx)
  if (!params.registrationFormat || !params.vehicleSubCategory || !params.registrationNumber) {
    return
  }

  const stages = VEHICLE_DEDUPE_STAGES

  try {
    showIntegrationLoading(ctx, stages, 0)
    ctx.setActionState('vehicleDedupe', 'loading')
    const response = await vehicleDedupe(params)
    if (isApiSuccess(response)) {
      const dedupeData = response?.data || null
      if (!isVehicleDedupeProceedAllowed(dedupeData)) {
        ctx.setActionState('vehicleDedupe', 'idle')
        const message =
          dedupeData?.response?.respDesc || 'Vehicle dedupe did not return proceed flag Y'
        ctx.updateFieldValue('vehicleDedupeErrorMessage', message)
        showIntegrationError(ctx, stages, 0, message)
        return
      }
      showIntegrationLoading(ctx, stages, stages.length)
      await delay(PROGRESS_CLOSE_DELAY_MS)
      ctx.updateFieldValue('vehicleDedupeResponse', response || null)
      ctx.updateFieldValue('vehicleDedupeData', dedupeData)
      ctx.updateFieldValue('vehicleDedupeErrorMessage', '')
      ctx.setActionState('vehicleDedupe', 'success')
      hideIntegrationProgress(ctx, stages)
      return
    }

    ctx.setActionState('vehicleDedupe', 'idle')
    const message = getApiErrorMessage(response, 'Unable to complete vehicle dedupe')
    ctx.updateFieldValue('vehicleDedupeErrorMessage', message)
    showIntegrationError(ctx, stages, 0, message)
  } catch (error) {
    ctx.setActionState('vehicleDedupe', 'idle')
    const message = getCatchErrorMessage(error, 'Unable to complete vehicle dedupe')
    ctx.updateFieldValue('vehicleDedupeErrorMessage', message)
    showIntegrationError(ctx, stages, 0, message)
  }
}

async function handleGetVehicleDetails(ctx) {
  if (ctx.isGetVehicleDetailsDisabled) return
  const params = getUsedDedupeParams(ctx)
  if (!params.registrationFormat || !params.vehicleSubCategory || !params.registrationNumber) {
    return
  }

  const stages = GET_VEHICLE_DETAILS_STAGES

  try {
    showIntegrationLoading(ctx, stages, 0)
    ctx.setActionState('getVehicleDetails', 'loading')

    const vahaanResponse = await vahaanReportApi(params)
    if (!isApiSuccess(vahaanResponse)) {
      ctx.setActionState('getVehicleDetails', 'idle')
      const message = getApiErrorMessage(vahaanResponse, 'Vahaan Report API failed')
      ctx.updateFieldValue('getVehicleDetailsErrorMessage', message)
      showIntegrationError(ctx, stages, 0, message)
      return
    }

    showIntegrationLoading(ctx, stages, 1)
    const dealMasterResponse = await dealMasterApi(params)
    if (!isApiSuccess(dealMasterResponse)) {
      ctx.setActionState('getVehicleDetails', 'idle')
      const message = getApiErrorMessage(dealMasterResponse, 'DealMaster API failed')
      ctx.updateFieldValue('getVehicleDetailsErrorMessage', message)
      showIntegrationError(ctx, stages, 1, message)
      return
    }

    showIntegrationLoading(ctx, stages, 2)
    const vehicleDetailsResponse = await getVehicleDetails(params)
    if (!isApiSuccess(vehicleDetailsResponse)) {
      ctx.setActionState('getVehicleDetails', 'idle')
      const message = getApiErrorMessage(vehicleDetailsResponse, 'Unable to fetch vehicle details')
      ctx.updateFieldValue('getVehicleDetailsErrorMessage', message)
      showIntegrationError(ctx, stages, 2, message)
      return
    }

    showIntegrationLoading(ctx, stages, stages.length)
    await delay(PROGRESS_CLOSE_DELAY_MS)
    const integrationPayload = {
      vahaan: vahaanResponse?.data || null,
      dealMaster: dealMasterResponse?.data || null,
      vehicleDetails: vehicleDetailsResponse?.data || null
    }
    ctx.updateFieldValue('getVehicleDetailsResponse', vehicleDetailsResponse || null)
    ctx.updateFieldValue('getVehicleDetailsData', integrationPayload)
    ctx.updateFieldValue('getVehicleDetailsErrorMessage', '')
    ctx.setActionState('getVehicleDetails', 'success')
    hideIntegrationProgress(ctx, stages)
  } catch (error) {
    ctx.setActionState('getVehicleDetails', 'idle')
    const message = getCatchErrorMessage(error, 'Unable to fetch vehicle details')
    ctx.updateFieldValue('getVehicleDetailsErrorMessage', message)
    showIntegrationError(ctx, stages, 0, message)
  }
}

export async function onLoad(submodulename, ctx) {
  if (submodulename !== 'onAction') return
  const key = ctx?._lastActionFieldKey

  if (key === 'fetchPrice') {
    await handleFetchPrice(ctx)
    return
  }
  if (key === 'vehicleDedupe') {
    await handleVehicleDedupe(ctx)
    return
  }
  if (key === 'getVehicleDetails') {
    await handleGetVehicleDetails(ctx)
  }
}

export default class ClientLayerVehicleDetails extends LightningElement {}