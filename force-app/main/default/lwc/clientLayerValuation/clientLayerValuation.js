import { LightningElement } from 'lwc'
import mfcValuation from '@salesforce/apex/ValuationController.mfcValuation'
import mfcFetchValuationReport from '@salesforce/apex/ValuationController.mfcFetchValuationReport'

const MFC_VALUATION_STAGES = ['MFC Valuation']
const MFC_FETCH_REPORT_STAGES = ['MFC Fetch Valuation Report']
/** Minimum dwell on the active stage so the spinner/tick transition is readable. */
const STAGE_ACTIVE_MIN_MS = 1000
/** Hold all-green ticks on the loading view before switching to the success screen. */
const STAGE_COMPLETE_HOLD_MS = 1000

const isApiSuccess = (response) => {
  if (response?.isSuccess === true) {
    return true
  }
  const statusCode = Number(response?.statusCode || 0)
  return statusCode === 200 && response?.status === 'SUCCESS'
}

function getFieldValue(ctx, key) {
  return ctx?.fields?.find((f) => f.key === key)?.value ?? ''
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

function showIntegrationSuccess(ctx, stages, successMessage) {
  dispatchIntegrationProgressUpdate(ctx, {
    show: true,
    status: 'success',
    currentStageIndex: stages.length,
    stages,
    errorMessage: '',
    successMessage: successMessage || 'Completed successfully.'
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

function getApiErrorMessage(response, fallback) {
  return response?.message || fallback
}

function getCatchErrorMessage(error, fallback) {
  return error?.body?.message || error?.message || fallback
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function waitForMinStageDuration(startedAt, minMs = STAGE_ACTIVE_MIN_MS) {
  const elapsed = Date.now() - startedAt
  if (elapsed < minMs) {
    await delay(minMs - elapsed)
  }
}

async function showCompletedLoadingThenSuccess(ctx, stages, successMessage) {
  showIntegrationLoading(ctx, stages, stages.length)
  await delay(STAGE_COMPLETE_HOLD_MS)
  showIntegrationSuccess(ctx, stages, successMessage)
}

async function handleMfcValuation(ctx) {
  const recordId = getFieldValue(ctx, 'recordId')
  if (!recordId) {
    return
  }

  const stages = MFC_VALUATION_STAGES

  try {
    ctx.setActionState('mfcValuation', 'loading')
    const startedAt = Date.now()
    showIntegrationLoading(ctx, stages, 0)
    const response = await mfcValuation({ recordId })
    await waitForMinStageDuration(startedAt)
    if (isApiSuccess(response)) {
      ctx.updateFieldValue('mfcValuationResponse', response || null)
      if (response?.mfcRequestId) {
        ctx.updateFieldValue('mfcRequestId', response.mfcRequestId)
      }
      ctx.updateFieldValue('mfcValuationErrorMessage', '')
      ctx.setActionState('mfcValuation', 'success')
      await showCompletedLoadingThenSuccess(
        ctx,
        stages,
        response?.message || 'Valuation request submitted successfully.'
      )
      return
    }

    ctx.setActionState('mfcValuation', 'idle')
    const message = getApiErrorMessage(response, 'MFC Valuation failed.')
    ctx.updateFieldValue('mfcValuationErrorMessage', message)
    showIntegrationError(ctx, stages, 0, message)
  } catch (error) {
    ctx.setActionState('mfcValuation', 'idle')
    const message = getCatchErrorMessage(error, 'MFC Valuation failed.')
    ctx.updateFieldValue('mfcValuationErrorMessage', message)
    showIntegrationError(ctx, stages, 0, message)
  }
}

async function handleMfcFetchReport(ctx) {
  const recordId = getFieldValue(ctx, 'recordId')
  if (!recordId) {
    return
  }

  const stages = MFC_FETCH_REPORT_STAGES

  try {
    ctx.setActionState('mfcFetchReport', 'loading')
    const startedAt = Date.now()
    showIntegrationLoading(ctx, stages, 0)
    const response = await mfcFetchValuationReport({ recordId })
    await waitForMinStageDuration(startedAt)
    if (isApiSuccess(response)) {
      ctx.updateFieldValue('mfcFetchReportResponse', response || null)
      ctx.updateFieldValue('mfcFetchReportErrorMessage', '')
      ctx.setActionState('mfcFetchReport', 'success')
      await showCompletedLoadingThenSuccess(
        ctx,
        stages,
        response?.message || 'Valuation report fetched successfully.'
      )
      return
    }

    ctx.setActionState('mfcFetchReport', 'idle')
    const message = getApiErrorMessage(response, 'MFC Fetch Valuation Report failed.')
    ctx.updateFieldValue('mfcFetchReportErrorMessage', message)
    showIntegrationError(ctx, stages, 0, message)
  } catch (error) {
    ctx.setActionState('mfcFetchReport', 'idle')
    const message = getCatchErrorMessage(error, 'MFC Fetch Valuation Report failed.')
    ctx.updateFieldValue('mfcFetchReportErrorMessage', message)
    showIntegrationError(ctx, stages, 0, message)
  }
}

export async function onLoad(submodulename, ctx) {
  if (submodulename !== 'onAction') {
    return
  }
  const key = ctx?._lastActionFieldKey
  if (key === 'mfcValuation') {
    await handleMfcValuation(ctx)
    return
  }
  if (key === 'mfcFetchReport') {
    await handleMfcFetchReport(ctx)
  }
}

export default class ClientLayerValuation extends LightningElement {}