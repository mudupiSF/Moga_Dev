import { LightningElement } from 'lwc';
import runNextClickIntegration from '@salesforce/apex/BorrowerNextIntegrationController.runNextClickIntegration';

const INTEGRATION_STAGES       = ['CIF on PAN Integration', 'ETB CASA Integration'];
const INTEGRATION_KEYS         = ['CIF_ON_PAN', 'ETB_CASA'];
const STAGE_MIN_DURATION_MS    = 3000;

/**
 * Dispatches integration progress modal state to the parent component.
 * Fires both on ctx (bubbles up the LWC tree) and on window (reliable delivery
 * when nested inside lwc:component / dynamic component slots).
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
 * Next-button integration handler for BorrowerMasterPage.
 *
 * Invoked via:
 *   invokeHandler('borrowerNextIntegration', 'onNextButton', this)
 *
 * ctx expected properties:
 *   ctx.recordId                         – Opportunity / Loan record Id
 *   ctx.effectiveApplicantId             – Borrower Applicant Id
 *   ctx.documentVerificationFieldValues  – Section field-value map (isPanAvailable)
 *
 * Stages:
 *   0 – CIF on PAN Integration  (CIF_ON_PAN)
 *   1 – ETB CASA Integration    (ETB_CASA)
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename !== 'onNextButton') return;

    // Form 60 path: skip CIF-on-PAN and ETB-CASA entirely.
    if ((ctx.documentVerificationFieldValues || {}).isPanAvailable === 'No') {
        return;
    }

    const stage1Start = Date.now();
    dispatchProgress(ctx, {
        show: true, status: 'loading',
        header: 'Verifying ETB CASA...',
        currentStageIndex: 0, stages: INTEGRATION_STAGES, errorMessage: ''
    });

    try {
        // Stage 1 — CIF on PAN
        await runNextClickIntegration({
            recordId: ctx.recordId,
            applicantId: ctx.effectiveApplicantId,
            integrationName: INTEGRATION_KEYS[0]
        });
        const stage1Elapsed = Date.now() - stage1Start;
        if (stage1Elapsed < STAGE_MIN_DURATION_MS) {
            await new Promise((resolve) => setTimeout(resolve, STAGE_MIN_DURATION_MS - stage1Elapsed));
        }

        // Stage 2 — ETB CASA
        const stage2Start = Date.now();
        dispatchProgress(ctx, {
            show: true, status: 'loading',
            header: 'Verifying ETB CASA...',
            currentStageIndex: 1, stages: INTEGRATION_STAGES, errorMessage: ''
        });
        await runNextClickIntegration({
            recordId: ctx.recordId,
            applicantId: ctx.effectiveApplicantId,
            integrationName: INTEGRATION_KEYS[1]
        });
        const stage2Elapsed = Date.now() - stage2Start;
        if (stage2Elapsed < STAGE_MIN_DURATION_MS) {
            await new Promise((resolve) => setTimeout(resolve, STAGE_MIN_DURATION_MS - stage2Elapsed));
        }

        // All stages complete — advance index past the last stage then close modal
        dispatchProgress(ctx, {
            show: true, status: 'loading',
            header: 'Verifying ETB CASA...',
            currentStageIndex: INTEGRATION_STAGES.length, stages: INTEGRATION_STAGES, errorMessage: ''
        });
        dispatchProgress(ctx, {
            show: false, status: 'loading',
            currentStageIndex: INTEGRATION_STAGES.length, stages: INTEGRATION_STAGES, errorMessage: ''
        });

    } catch (error) {
        dispatchProgress(ctx, {
            show: true, status: 'error',
            currentStageIndex: 0, stages: INTEGRATION_STAGES,
            errorMessage: error?.body?.message || error?.message || 'Next integrations failed'
        });
        throw error;
    }
}

export default class BorrowerNextIntegration extends LightningElement {}