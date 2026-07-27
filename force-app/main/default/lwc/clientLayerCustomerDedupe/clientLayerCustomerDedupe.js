/**
 * Client layer for Customer Dedupe — used via invokeHandler('customerDedupeCheck', ...).
 */

import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';

const APEX_CLASS = 'CustomerDedupeController';
const APEX_METHOD_MARK_VALID = 'markMatchAsValid';
const APEX_METHOD_MARK_INVALID = 'markMatchAsInvalid';

const INTEGRATION_STAGES = [
    'Validating customer match...',
    'Updating customer records...'
];

function dispatchIntegrationProgressUpdate(ctx, payload) {
    const ev = new CustomEvent('integrationprogressupdate', {
        detail: payload,
        bubbles: true,
        composed: true
    });
    if (ctx && typeof ctx.dispatchEvent === 'function') {
        ctx.dispatchEvent(ev);
    }
    window.dispatchEvent(ev);
}

async function runValidationFlow(ctx, apexMethodName) {
    const match = ctx._lastValidatedMatch || ctx.lastValidatedMatch;
    const cifId = (match?.cifId || ctx.getSelectedCifId?.() || '').trim();

    dispatchIntegrationProgressUpdate(ctx, {
        show: true,
        status: 'loading',
        currentStageIndex: 0,
        stages: INTEGRATION_STAGES,
        errorMessage: ''
    });

    let response;
    try {
        response = await savePageData({
            apexClassName: APEX_CLASS,
            apexMethodName: apexMethodName,
            recordId: ctx.recordId,
            params: {
                recordId: ctx.recordId,
                applicantId: ctx.applicantId || null,
                cifId
            }
        });
    } catch (err) {
        const message = err?.body?.message || err?.message || 'Operation failed.';
        dispatchIntegrationProgressUpdate(ctx, {
            show: true,
            status: 'error',
            currentStageIndex: 0,
            stages: INTEGRATION_STAGES,
            errorMessage: message
        });
        if (typeof ctx.onIntegrationFailure === 'function') {
            ctx.onIntegrationFailure({ isSuccess: false, message });
        }
        return { isSuccess: false, message };
    }

    if (response && response.isSuccess !== false) {
        dispatchIntegrationProgressUpdate(ctx, {
            show: true,
            status: 'loading',
            currentStageIndex: 1,
            stages: INTEGRATION_STAGES,
            errorMessage: ''
        });

        window.setTimeout(() => {
            dispatchIntegrationProgressUpdate(ctx, { show: false, status: 'success' });
            if (typeof ctx.onIntegrationSuccess === 'function') {
                ctx.onIntegrationSuccess(response);
            }
        }, 800);
        return response;
    }

    const message = response?.message || 'Operation failed.';
    dispatchIntegrationProgressUpdate(ctx, {
        show: true,
        status: 'error',
        currentStageIndex: 0,
        stages: INTEGRATION_STAGES,
        errorMessage: message
    });
    if (typeof ctx.onIntegrationFailure === 'function') {
        ctx.onIntegrationFailure({ isSuccess: false, message });
    }
    return { isSuccess: false, message };
}

export async function onLoad(submodulename, ctx) {
    if (submodulename === 'onValidClick') {
        return runValidationFlow(ctx, APEX_METHOD_MARK_VALID);
    }
    if (submodulename === 'onInvalidClick') {
        return runValidationFlow(ctx, APEX_METHOD_MARK_INVALID);
    }
    return { isSuccess: false, message: 'Unknown action: ' + submodulename };
}