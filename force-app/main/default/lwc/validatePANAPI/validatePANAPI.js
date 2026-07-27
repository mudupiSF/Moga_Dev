import { LightningElement } from 'lwc';
import invokeValidatePANAPI from '@salesforce/apex/ValidatePANAPIController.invokeValidatePANAPI';
import markPanVerified from '@salesforce/apex/ValidatePANAPIController.markPanVerified';

const STAGES = [
    'Verifying PAN'
];

const HEADER = 'Verify PAN';

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
 * Validate PAN orchestrator.
 *   - onVerify      : Verify the PAN card number
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename === 'onVerify') {
        await runVerifyFlow(ctx);
        return;
    }
}

/** Verify PAN orchestrator. */
async function runVerifyFlow(ctx) {
    const applicantId = ctx.applicantId || null;
    const panCardNumber = (ctx.extractedPanCardNumber || '').trim().toUpperCase();
    if (!applicantId || !panCardNumber) {
        return;
    }
    dispatchIntegrationProgressUpdate(ctx, {
        show: true, status: 'loading', currentStageIndex: 0,
        header: HEADER,
        stages: STAGES, errorMessage: ''
    });
    try {
        const verifyPANCardResult = await invokeValidatePANAPI({ applicantId });
        if (verifyPANCardResult && !verifyPANCardResult.hasValidationError) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'success', currentStageIndex: 0,
                header: HEADER,
                stages: STAGES, errorMessage: ''
            });
            await new Promise((r) => setTimeout(r, 1000));
            await markPanVerified({ applicantId, verified: true }).catch(() => {});
            ctx.updateFieldValue('pancardVerificationErrorMessage', '');
            ctx.updateFieldValue('pancardVerificationStatus', 'success');
        }
        else {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'error', currentStageIndex: 0,
                header: HEADER,
                stages: STAGES, errorMessage: verifyPANCardResult.errorMessage || 'Verification failed'
            });
            await new Promise((r) => setTimeout(r, 1000));
            ctx.updateFieldValue('pancardVerificationErrorMessage', verifyPANCardResult.errorMessage || 'Verification failed');
            ctx.updateFieldValue('pancardVerificationStatus', 'Failed');
        }
    }
    catch (err) {
        ctx.updateFieldValue('pancardVerificationErrorMessage', err?.message || 'Verification failed');
        ctx.updateFieldValue('pancardVerificationStatus', 'Failed');
    }
}

export default class ValidatePANAPI extends LightningElement {}