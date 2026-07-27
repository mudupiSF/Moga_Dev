import { LightningElement } from 'lwc';
import invokeMNRLAPI from '@salesforce/apex/MNRLAPIController.invokeMNRLAPI';

const STAGES = [
    'Verifying MNRL'
];

const HEADER = 'Verify Mobile Number (MNRL)';

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
 * MNRL API orchestrator.
 *   - onVerify      : Verify mobile number with MNRL.
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename === 'onVerify') {
        await runVerifyFlow(ctx);
        return;
    }
}

/** Verify MNRL orchestrator. */
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
        const verifyMNRLResult = await invokeMNRLAPI({ applicantId });
        if (verifyMNRLResult && !verifyMNRLResult.hasValidationError) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'success', currentStageIndex: 0,
                header: HEADER,
                stages: STAGES, errorMessage: ''
            });
            await new Promise((r) => setTimeout(r, 1000));
            ctx.updateFieldValue('mnrlVerificationErrorMessage', '');
            ctx.updateFieldValue('mnrlVerificationStatus', 'success');
        } else {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'error', currentStageIndex: 0,
                header: HEADER,
                stages: STAGES, errorMessage: verifyMNRLResult?.errorMessage || 'Verification failed'
            });
            await new Promise((r) => setTimeout(r, 1000));
            ctx.updateFieldValue('mnrlVerificationErrorMessage', verifyMNRLResult?.errorMessage || 'Verification failed');
            ctx.updateFieldValue('mnrlVerificationStatus', 'Failed');
        }
    } catch (err) {
        ctx.updateFieldValue('mnrlVerificationErrorMessage', err?.message || 'Verification failed');
        ctx.updateFieldValue('mnrlVerificationStatus', 'Failed');
    }
}

export default class MnrlAPI extends LightningElement {}