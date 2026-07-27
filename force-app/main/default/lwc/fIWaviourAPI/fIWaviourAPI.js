import { LightningElement } from 'lwc';
import runFiWaiverOfferNextFlow from '@salesforce/apex/FIWaiverAPIController.runFiWaiverOfferNextFlow';

const DEFAULT_INTEGRATION_STAGES = ['FI Waiver', 'Creating FI Investigations'];
const STAGE_MIN_DURATION_MS = 1500;

function dispatchProgress(ctx, payload) {
    const ev = new CustomEvent('integrationprogressupdate', {
        detail: payload,
        bubbles: true,
        composed: true
    });
    ctx.dispatchEvent(ev);
    window.dispatchEvent(ev);
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function resolveIntegrationStages(ctx) {
    const customStages = ctx?._fiIntegrationStages;
    if (Array.isArray(customStages) && customStages.length > 0) {
        return customStages;
    }
    return DEFAULT_INTEGRATION_STAGES;
}

async function waitForStagePacing(stageStart) {
    const elapsed = Date.now() - stageStart;
    if (elapsed < STAGE_MIN_DURATION_MS) {
        await sleep(STAGE_MIN_DURATION_MS - elapsed);
    }
}

/**
 * FI Waiver orchestrator for offerPage Next.
 *
 * Invoked via:
 *   invokeHandler('fIWaviourAPI', 'onNextButton', this)
 *
 * ctx expected properties:
 *   ctx.recordId – Application__c Id
 *   ctx._fiIntegrationStages – optional stage labels from offerPage
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename !== 'onNextButton' || !ctx) {
        return;
    }

    ctx._fiWaiverIntegrationResult = {
        isSuccess: false,
        message: 'FI Waiver failed.'
    };

    if (!ctx.recordId) {
        ctx._fiWaiverIntegrationResult = {
            isSuccess: false,
            message: 'Application record Id is missing.'
        };
        return;
    }

    const stages = resolveIntegrationStages(ctx);
    const hasWaiverStage = stages.length > 1;
    const stageStart = Date.now();

    dispatchProgress(ctx, {
        show: true,
        status: 'loading',
        currentStageIndex: 0,
        stages,
        errorMessage: ''
    });

    try {
        const flowResult = await runFiWaiverOfferNextFlow({ applicationId: ctx.recordId });
        if (!flowResult?.isSuccess) {
            const message = flowResult?.message || 'FI investigation creation failed.';
            ctx._fiWaiverIntegrationResult = { isSuccess: false, message };
            dispatchProgress(ctx, {
                show: true,
                status: 'error',
                currentStageIndex: hasWaiverStage && flowResult?.waiverMessage ? 1 : 0,
                stages,
                errorMessage: message
            });
            throw new Error(message);
        }

        if (hasWaiverStage) {
            await waitForStagePacing(stageStart);

            dispatchProgress(ctx, {
                show: true,
                status: 'loading',
                currentStageIndex: 1,
                stages,
                errorMessage: ''
            });

            const creationStageStart = Date.now();
            await waitForStagePacing(creationStageStart);
        } else {
            await waitForStagePacing(stageStart);
        }

        ctx._fiWaiverIntegrationResult = {
            isSuccess: true,
            message: flowResult.message || 'FI investigation creation completed successfully.',
            investigationsCreated: flowResult.investigationsCreated
        };

        dispatchProgress(ctx, {
            show: true,
            status: 'loading',
            currentStageIndex: stages.length,
            stages,
            errorMessage: ''
        });
        dispatchProgress(ctx, {
            show: false,
            status: 'loading',
            currentStageIndex: stages.length,
            stages,
            errorMessage: ''
        });
    } catch (error) {
        if (!ctx._fiWaiverIntegrationResult?.message) {
            ctx._fiWaiverIntegrationResult = {
                isSuccess: false,
                message: error?.body?.message || error?.message || 'FI Waiver failed.'
            };
        }
        dispatchProgress(ctx, {
            show: true,
            status: 'error',
            currentStageIndex: 0,
            stages,
            errorMessage: ctx._fiWaiverIntegrationResult.message
        });
        throw error;
    }
}

export default class FIWaviourAPI extends LightningElement {}