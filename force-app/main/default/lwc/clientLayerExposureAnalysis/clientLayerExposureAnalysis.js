import { LightningElement } from 'lwc'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'

const APEX_CLASS = 'ExposureAnalysisController'
const APEX_METHOD_COMPUTE = 'computeTotalExposure'
const ACTION_COMPUTE_TOTAL_EXPOSURE = 'computeTotalExposure'
const COMPUTE_INTEGRATION_STAGES = [
  'Fetching D2K exposure...',
  'Fetching customer exposure...',
  'Calculating FOIR...',
  'Updating exposure summary...'
]
const STUB_INTEGRATION_STAGE_DELAY_MS = 600
const MSG_COMPUTE_INTEGRATION_FAILED = 'Unable to complete exposure computation.'
const MSG_COMPUTE_FAILED = 'Unable to compute total exposure.'

function delay(ms) {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(resolve, ms)
  })
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
    errorMessage: errorMessage || MSG_COMPUTE_INTEGRATION_FAILED
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

function getBaseParams(ctx) {
  return {
    applicantId: ctx.applicantId ?? ctx._applicantId ?? null
  }
}

/**
 * Phase 1: stub delays for D2K / P3 / FOIR stages, then Callable computeTotalExposure.
 * Phase 3: replace simulateStage blocks with real IntegrationUtility callouts.
 */
async function handleComputeTotalExposure(ctx) {
  const stages = COMPUTE_INTEGRATION_STAGES

  try {
    ctx.setComputeActionState('loading')

    for (let i = 0; i < stages.length - 1; i += 1) {
      showLoading(ctx, stages, i)
      await delay(STUB_INTEGRATION_STAGE_DELAY_MS)
    }

    showLoading(ctx, stages, stages.length - 1)
    const result = await savePageData({
      apexClassName: APEX_CLASS,
      apexMethodName: APEX_METHOD_COMPUTE,
      recordId: ctx.recordId ?? ctx._recordId,
      params: getBaseParams(ctx)
    })

    if (!result?.isSuccess) {
      ctx.setComputeActionState('idle')
      const message = result?.message || MSG_COMPUTE_FAILED
      showError(ctx, stages, stages.length - 1, message)
      return
    }

    if (typeof ctx.applyPagePayload === 'function') {
      ctx.applyPagePayload(result)
    }

    ctx.setComputeActionState('success')
    hideProgress(ctx, stages)
  } catch (error) {
    ctx.setComputeActionState('idle')
    const message = getErrorMessage(error, MSG_COMPUTE_INTEGRATION_FAILED)
    showError(ctx, stages, 0, message)
  }
}

export async function onLoad(submodulename, ctx) {
  if (submodulename !== 'onAction') {
    return
  }

  const key = ctx?._lastActionFieldKey
  if (key === ACTION_COMPUTE_TOTAL_EXPOSURE) {
    await handleComputeTotalExposure(ctx)
  }
}

export default class ClientLayerExposureAnalysis extends LightningElement {}