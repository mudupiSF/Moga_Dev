import { LightningElement } from 'lwc'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'

const CALLOUT_APEX_CLASS = 'DeviationController'
const CALLOUT_APEX_METHOD = 'runDeviationCallout'
const TRIGGER_APEX_CLASS = 'TriggerDeviationController'
const TRIGGER_APEX_METHOD = 'triggerDeviationMail'

const PARAM_APPLICATION_ID = 'applicationId'
const PARAM_APPLICANT_ID = 'applicantId'
const PARAM_TYPE = 'type'

const TYPE_GLOBAL = 'global'
const TYPE_ASSET = 'asset'

const SUBMODULE_FLOW = 'onCreditAssessmentDeviationFlow'

const INTEGRATION_STAGES = [
    'Fetching global deviations...',
    'Fetching asset deviations...',
    'Triggering deviation...'
]

const MSG_CALLOUT_FAILED = 'Unable to fetch and create deviations.'
const MSG_TRIGGER_FAILED = 'Unable to trigger deviation notification.'
const MSG_INTEGRATION_FAILED = 'Unable to complete deviation integrations.'

function getErrorMessage(error, fallback) {
    return error?.body?.message || error?.message || fallback
}

function getRecordId(ctx) {
    return ctx?.recordId ?? ctx?._recordId ?? null
}

function getApplicantId(ctx) {
    return ctx?.applicantId ?? ctx?._applicantId ?? null
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
        errorMessage: errorMessage || MSG_INTEGRATION_FAILED
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

async function runDeviationCallout(ctx, callType) {
    const recordId = getRecordId(ctx)
    if (!recordId) {
        return { isSuccess: false, message: 'Application context is missing.' }
    }

    try {
        const result = await savePageData({
            apexClassName: CALLOUT_APEX_CLASS,
            apexMethodName: CALLOUT_APEX_METHOD,
            recordId,
            params: {
                [PARAM_APPLICATION_ID]: recordId,
                [PARAM_APPLICANT_ID]: getApplicantId(ctx),
                [PARAM_TYPE]: callType
            }
        })

        if (result?.isSuccess !== true) {
            return {
                isSuccess: false,
                message: result?.message || MSG_CALLOUT_FAILED
            }
        }

        return { isSuccess: true, result }
    } catch (error) {
        return {
            isSuccess: false,
            message: getErrorMessage(error, MSG_CALLOUT_FAILED)
        }
    }
}

async function runTriggerDeviationMail(ctx) {
    const recordId = getRecordId(ctx)
    if (!recordId) {
        return { isSuccess: false, message: 'Application context is missing.' }
    }

    try {
        const result = await savePageData({
            apexClassName: TRIGGER_APEX_CLASS,
            apexMethodName: TRIGGER_APEX_METHOD,
            recordId,
            params: {
                [PARAM_APPLICATION_ID]: recordId,
                [PARAM_APPLICANT_ID]: getApplicantId(ctx)
            }
        })

        if (result?.isSuccess !== true) {
            return {
                isSuccess: false,
                message: result?.message || MSG_TRIGGER_FAILED
            }
        }

        return { isSuccess: true, result }
    } catch (error) {
        return {
            isSuccess: false,
            message: getErrorMessage(error, MSG_TRIGGER_FAILED)
        }
    }
}

async function handleCreditAssessmentDeviationFlow(ctx) {
    const stages = INTEGRATION_STAGES

    try {
        showLoading(ctx, stages, 0)
        const globalResult = await runDeviationCallout(ctx, TYPE_GLOBAL)
        if (globalResult?.isSuccess !== true) {
            showError(ctx, stages, 0, globalResult?.message || MSG_CALLOUT_FAILED)
            return { isSuccess: false, message: globalResult?.message || MSG_CALLOUT_FAILED }
        }

        showLoading(ctx, stages, 1)
        const assetResult = await runDeviationCallout(ctx, TYPE_ASSET)
        if (assetResult?.isSuccess !== true) {
            showError(ctx, stages, 1, assetResult?.message || MSG_CALLOUT_FAILED)
            return { isSuccess: false, message: assetResult?.message || MSG_CALLOUT_FAILED }
        }

        showLoading(ctx, stages, 2)
        const triggerResult = await runTriggerDeviationMail(ctx)
        if (triggerResult?.isSuccess !== true) {
            showError(ctx, stages, 2, triggerResult?.message || MSG_TRIGGER_FAILED)
            return { isSuccess: false, message: triggerResult?.message || MSG_TRIGGER_FAILED }
        }

        showLoading(ctx, stages, stages.length)
        hideProgress(ctx, stages)

        return {
            isSuccess: true,
            result: {
                global: globalResult.result,
                asset: assetResult.result,
                trigger: triggerResult.result
            }
        }
    } catch (error) {
        const message = getErrorMessage(error, MSG_INTEGRATION_FAILED)
        showError(ctx, stages, 0, message)
        return { isSuccess: false, message }
    }
}

/**
 * Deviation client layer for Credit Assessment Next integration flow.
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename === SUBMODULE_FLOW) {
        return handleCreditAssessmentDeviationFlow(ctx)
    }

    return { isSuccess: true }
}

export default class ClientLayerDeviation extends LightningElement {}