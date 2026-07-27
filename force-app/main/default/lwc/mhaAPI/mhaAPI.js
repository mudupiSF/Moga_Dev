import { LightningElement } from 'lwc';
import invokeMHAAPI from '@salesforce/apex/MHAAPIController.invokeMHAAPI';

const STAGES = [
    'Verifying MHA'
];

const HEADER = 'Verify MHA';

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
 * MHA API orchestrator.
 *   - onVerify      : Verify MHA details.
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename === 'onVerify') {
        await runVerifyFlow(ctx);
        return;
    }
}

/** Verify MHA orchestrator. */
async function runVerifyFlow(ctx) {
    const applicantId = ctx.applicantId || null;
    if (!applicantId) {
        return;
    }

    dispatchIntegrationProgressUpdate(ctx, {
        show: true, status: 'loading', currentStageIndex: 0,
        header: HEADER,
        stages: STAGES, errorMessage: ''
    });

    try {
        const verifyMHAResult = await invokeMHAAPI({ applicantId });
        if (verifyMHAResult && !verifyMHAResult.hasValidationError) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'success', currentStageIndex: 0,
                header: HEADER,
                stages: STAGES, errorMessage: ''
            });
            await new Promise((r) => setTimeout(r, 1000));
            ctx.updateFieldValue('mhaVerificationErrorMessage', '');
            ctx.updateFieldValue('mhaVerificationStatus', 'success');
        } else {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'error', currentStageIndex: 0,
                header: HEADER,
                stages: STAGES, errorMessage: verifyMHAResult?.errorMessage || 'Verification failed'
            });
            await new Promise((r) => setTimeout(r, 1000));
            ctx.updateFieldValue('mhaVerificationErrorMessage', verifyMHAResult?.errorMessage || 'Verification failed');
            ctx.updateFieldValue('mhaVerificationStatus', 'Failed');
        }
    } catch (err) {
        ctx.updateFieldValue('mhaVerificationErrorMessage', err?.message || 'Verification failed');
        ctx.updateFieldValue('mhaVerificationStatus', 'Failed');
    }
}

export default class MhaAPI extends LightningElement {}