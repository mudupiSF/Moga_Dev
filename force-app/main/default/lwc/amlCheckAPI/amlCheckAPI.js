import { LightningElement } from 'lwc';
import invokeAMLCheckAPI from '@salesforce/apex/AMLCheckAPIController.invokeAMLCheckAPI';
import invokeAMLCheckForApplication from '@salesforce/apex/AMLCheckAPIController.invokeAMLCheckForApplication';

const STAGES = [
    'AML Check'
];

const HEADER = 'AML Check';

/** Dispatches integration-progress events to the parent (window + ctx for nested-component reliability). */
function dispatchIntegrationProgressUpdate(ctx, payload) {
    const ev = new CustomEvent('integrationprogressupdate', {
        detail: payload,
        bubbles: true,
        composed: true
    });
    ctx.dispatchEvent(ev);
    window.dispatchEvent(ev);
}

/**
 * AML Check orchestrator.
 *   - onVerify            : AML Check for the current applicant
 *   - onApplicationForward: AML Check for all active applicants on the application
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename === 'onVerify') {
        await runVerifyFlow(ctx);
        return;
    }
    if (submodulename === 'onApplicationForward') {
        return runApplicationForwardFlow(ctx);
    }
}

/** Application-level AML Check (Borrower Dedupe Next). Returns outcome for staged progress UIs. */
export async function runApplicationAMLCheck(applicationId) {
    if (!applicationId) {
        return { isSuccess: false, message: 'Application id is required.' };
    }

    const result = await invokeAMLCheckForApplication({ applicationId });
    return {
        isSuccess: result?.isSuccess === true,
        message: result?.message || 'AML Check failed.'
    };
}

async function runVerifyFlow(ctx) {
    const applicantId = ctx.applicantId || null;
    if (!applicantId) {
        return;
    }

    dispatchIntegrationProgressUpdate(ctx, {
        show: true,
        status: 'loading',
        currentStageIndex: 0,
        header: HEADER,
        stages: STAGES,
        errorMessage: ''
    });

    try {
        const amlResult = await invokeAMLCheckAPI({ applicantId });
        if (amlResult && !amlResult.hasValidationError) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true,
                status: 'success',
                currentStageIndex: 0,
                header: HEADER,
                stages: STAGES,
                errorMessage: ''
            });
            await new Promise((resolve) => setTimeout(resolve, 1000));
            dispatchIntegrationProgressUpdate(ctx, {
                show: false,
                status: 'loading',
                currentStageIndex: 0,
                header: HEADER,
                stages: STAGES,
                errorMessage: ''
            });
        } else {
            const errorMessage = amlResult?.displayMessage || amlResult?.errorMessage || 'AML Check failed.';
            dispatchIntegrationProgressUpdate(ctx, {
                show: true,
                status: 'error',
                currentStageIndex: 0,
                header: HEADER,
                stages: STAGES,
                errorMessage
            });
            await new Promise((resolve) => setTimeout(resolve, 1000));
        }
    } catch (err) {
        dispatchIntegrationProgressUpdate(ctx, {
            show: true,
            status: 'error',
            currentStageIndex: 0,
            header: HEADER,
            stages: STAGES,
            errorMessage: err?.body?.message || err?.message || 'AML Check failed.'
        });
    }
}

async function runApplicationForwardFlow(ctx) {
    const applicationId = ctx.recordId || null;
    ctx._amlForwardIntegrationResult = {
        isSuccess: false,
        message: 'AML Check failed.'
    };

    if (!applicationId) {
        ctx._amlForwardIntegrationResult = {
            isSuccess: false,
            message: 'Application id is required.'
        };
        return ctx._amlForwardIntegrationResult;
    }

    dispatchIntegrationProgressUpdate(ctx, {
        show: true,
        status: 'loading',
        currentStageIndex: 0,
        header: HEADER,
        stages: STAGES,
        errorMessage: ''
    });

    try {
        const outcome = await runApplicationAMLCheck(applicationId);
        ctx._amlForwardIntegrationResult = outcome;
        if (outcome.isSuccess) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true,
                status: 'success',
                currentStageIndex: 0,
                header: HEADER,
                stages: STAGES,
                errorMessage: ''
            });
            await new Promise((resolve) => setTimeout(resolve, 1000));
            dispatchIntegrationProgressUpdate(ctx, {
                show: false,
                status: 'loading',
                currentStageIndex: 0,
                header: HEADER,
                stages: STAGES,
                errorMessage: ''
            });
        } else {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true,
                status: 'error',
                currentStageIndex: 0,
                header: HEADER,
                stages: STAGES,
                errorMessage: outcome.message || 'AML Check failed.'
            });
            await new Promise((resolve) => setTimeout(resolve, 1000));
        }
        return ctx._amlForwardIntegrationResult;
    } catch (err) {
        ctx._amlForwardIntegrationResult = {
            isSuccess: false,
            message: err?.body?.message || err?.message || 'AML Check failed.'
        };
        dispatchIntegrationProgressUpdate(ctx, {
            show: true,
            status: 'error',
            currentStageIndex: 0,
            header: HEADER,
            stages: STAGES,
            errorMessage: ctx._amlForwardIntegrationResult.message
        });
        return ctx._amlForwardIntegrationResult;
    }
}

export default class AmlCheckAPI extends LightningElement {}