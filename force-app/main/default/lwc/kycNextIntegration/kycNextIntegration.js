import { LightningElement } from 'lwc';
import runNextClickIntegration from '@salesforce/apex/BorrowerNextIntegrationController.runNextClickIntegration';

const INTEGRATION_STAGES    = ['Customer Dedupe', 'Validate Recent Lead'];
const INTEGRATION_KEYS      = ['CUSTOMER_DEDUPE', 'VALIDATE_RECENT_LEAD'];
const HEADER = 'Verify Customer Details';
const STAGE_MIN_DURATION_MS = 3000;

/**
 * Dispatches integration progress modal state to the parent.
 * Fires on both ctx (bubbles up the LWC tree) and window (reliable delivery
 * when the parent listens at the window level).
 */
function dispatchProgress(ctx, payload) {
    const ev = new CustomEvent('integrationprogressupdate', {
        detail: payload,
        bubbles: true,
        composed: true
    });
    ctx.dispatchEvent(ev);
    window.dispatchEvent(ev);
}

/**
 * Next-button integration handler for wheelsIndividualKYCMasterPage.
 *
 * Invoked via:
 *   invokeHandler('kycNextIntegration', 'onNextButton', this)
 *
 * ctx expected properties:
 *   ctx.recordId      – Opportunity / Loan record Id
 *   ctx._applicantId  – Borrower Applicant Id (canonical) — passed as applicantId
 *
 * Stages:
 *   0 – Customer Dedupe        (CUSTOMER_DEDUPE)
 *   1 – Validate Recent Lead   (VALIDATE_RECENT_LEAD)
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename !== 'onNextButton') return;

    const recordId    = ctx.recordId;
    const applicantId = ctx._applicantId || ctx.applicantId;

    const stage1Start = Date.now();
    dispatchProgress(ctx, {
        show: true, status: 'loading',
        header: HEADER,
        currentStageIndex: 0, stages: INTEGRATION_STAGES, errorMessage: ''
    });

    try {
        await runNextClickIntegration({
            recordId,
            applicantId,
            integrationName: INTEGRATION_KEYS[0]
        });
        const stage1Elapsed = Date.now() - stage1Start;
        if (stage1Elapsed < STAGE_MIN_DURATION_MS) {
            await new Promise((resolve) => setTimeout(resolve, STAGE_MIN_DURATION_MS - stage1Elapsed));
        }

        const stage2Start = Date.now();
        dispatchProgress(ctx, {
            show: true, status: 'loading',
            header: HEADER,
            currentStageIndex: 1, stages: INTEGRATION_STAGES, errorMessage: ''
        });
        await runNextClickIntegration({
            recordId,
            applicantId,
            integrationName: INTEGRATION_KEYS[1]
        });
        const stage2Elapsed = Date.now() - stage2Start;
        if (stage2Elapsed < STAGE_MIN_DURATION_MS) {
            await new Promise((resolve) => setTimeout(resolve, STAGE_MIN_DURATION_MS - stage2Elapsed));
        }

        // Advance past the last stage and close the modal.
        dispatchProgress(ctx, {
            show: true, status: 'loading',
            header: HEADER,
            currentStageIndex: INTEGRATION_STAGES.length, stages: INTEGRATION_STAGES, errorMessage: ''
        });
        dispatchProgress(ctx, {
            show: false, status: 'loading',
            header: HEADER,
            currentStageIndex: INTEGRATION_STAGES.length, stages: INTEGRATION_STAGES, errorMessage: ''
        });

    } catch (error) {
        dispatchProgress(ctx, {
            show: true, status: 'error',
            header: HEADER,
            currentStageIndex: 0, stages: INTEGRATION_STAGES,
            errorMessage: error?.body?.message || error?.message || 'KYC next integrations failed'
        });
        throw error;
    }
}

export default class KycNextIntegration extends LightningElement {}