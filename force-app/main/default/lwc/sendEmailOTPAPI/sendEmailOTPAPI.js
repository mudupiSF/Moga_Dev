import { LightningElement } from 'lwc';
import invokeSendEmailOTPAPI from '@salesforce/apex/SendEmailOTPAPIController.invokeSendEmailOTPAPI';

const STAGES = [
    'Sending Email OTP', 'Verifying OTP'
];

const HEADER = 'Send Email OTP';

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
 * Send email OTP orchestrator.
 *   - onAction      : Send OTP to the applicant email address
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
    const emailAddress = (ctx.emailAddress || ctx.email || '').trim();
    if (!applicantId || !emailAddress) {
        return;
    }

    dispatchIntegrationProgressUpdate(ctx, {
        show: true, status: 'loading', currentStageIndex: 0,
        header: HEADER,
        stages: STAGES, errorMessage: ''
    });

    try {
        const sendOTPResult = await invokeSendEmailOTPAPI({ applicantId });
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
        }
        else {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'error', currentStageIndex: 0,
                header: HEADER,
                stages: STAGES, errorMessage: sendOTPResult?.errorMessage || 'Failed to send OTP'
            });
            await new Promise((r) => setTimeout(r, 10000));
            ctx.updateFieldValue('emailOTPErrorMessage', sendOTPResult?.errorMessage || 'Failed to send OTP');
            ctx.updateFieldValue('emailOTPStatus', 'Failed');
        }
    }
    catch (err) {
        ctx.updateFieldValue('emailOTPErrorMessage', err?.message || 'Failed to send OTP');
        ctx.updateFieldValue('emailOTPStatus', 'Failed');
    }
}

export default class SendEmailOTPAPI extends LightningElement {}