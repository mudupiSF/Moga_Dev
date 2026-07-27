import { LightningElement } from 'lwc';
import invokeSendPhoneOTPAPI from '@salesforce/apex/SendPhoneOTPAPIController.invokeSendPhoneOTPAPI';

const STAGES = [
    'Sending Phone OTP', 'Verifying OTP'
];

const HEADER = 'Send Phone OTP';

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
 * Send phone OTP orchestrator.
 *   - onAction      : Send OTP to the applicant phone number
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename === 'onAction') {
        await runSendOTPFlow(ctx);
        return;
    }
}

/** Send OTP orchestrator. */
async function runSendOTPFlow(ctx) {
    const applicantId = ctx.applicantId || null;
    const phoneNumber = (ctx.contactNumber || '').trim();
    if (!applicantId || !phoneNumber) {
        return;
    }

    dispatchIntegrationProgressUpdate(ctx, {
        show: true, status: 'loading', currentStageIndex: 0,
        header: HEADER,
        stages: STAGES, errorMessage: ''
    });

    try {
        const sendOTPResult = await invokeSendPhoneOTPAPI({ applicantId });
        if (sendOTPResult && !sendOTPResult.hasValidationError) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'loading', currentStageIndex: 1,
                header: HEADER,
                stages: STAGES, errorMessage: ''
            });
            await new Promise((r) => setTimeout(r, 1000));
            dispatchIntegrationProgressUpdate(ctx, {
                show: false, status: 'loading', currentStageIndex: 1,
                header: HEADER,
                stages: STAGES, errorMessage: ''
            });
            /*ctx.updateFieldValue('phoneOTPErrorMessage', '');
            ctx.updateFieldValue('phoneOTPStatus', 'success');*/
        }
        else {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'error', currentStageIndex: 0,
                header: HEADER,
                stages: STAGES, errorMessage: sendOTPResult?.errorMessage || 'Failed to send OTP'
            });
            await new Promise((r) => setTimeout(r, 10000));
            ctx.updateFieldValue('phoneOTPErrorMessage', sendOTPResult?.errorMessage || 'Failed to send OTP');
            ctx.updateFieldValue('phoneOTPStatus', 'Failed');
        }
    }
    catch (err) {
        ctx.updateFieldValue('phoneOTPErrorMessage', err?.message || 'Failed to send OTP');
        ctx.updateFieldValue('phoneOTPStatus', 'Failed');
    }
}

export default class SendPhoneOTPAPI extends LightningElement {}