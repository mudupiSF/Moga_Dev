import { LightningElement } from 'lwc';
import invokePANTOCINNAPI from '@salesforce/apex/ExtractPANTOCINNAPIController.invokePANTOCINNAPI';
import getCinExtractionResult from '@salesforce/apex/ExtractPANTOCINNAPIController.getCinExtractionResult';

const STAGES = ['PAN TO CIN'];
const HEADER = 'PAN TO CIN';

function isRefreshBlockedError(apiResult) {
    const message = apiResult?.errorMessage || apiResult?.displayMessage || '';
    return Boolean(apiResult?.hasValidationError)
        && message.includes('Refresh is not allowed');
}

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
 * PAN TO CIN orchestrator for Non-Individual CIN document upload.
 *   - onFileUpload : runs PAN TO CIN lookup using the applicant PAN
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename !== 'onFileUpload') {
        return;
    }

    const applicantId = ctx._applicantId || ctx.applicantId || null;
    if (!applicantId) {
        ctx._cinExtractionResponse = {
            isSuccess: false,
            message: 'Applicant id is required for PAN TO CIN lookup.'
        };
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
        const apiResult = await invokePANTOCINNAPI({ applicantId });
        const refreshBlocked = isRefreshBlockedError(apiResult);
        if (apiResult?.hasValidationError && !refreshBlocked) {
            const errorMessage = apiResult.displayMessage || apiResult.errorMessage || 'PAN TO CIN lookup failed.';
            ctx._cinExtractionResponse = { isSuccess: false, message: errorMessage };
            dispatchIntegrationProgressUpdate(ctx, {
                show: true,
                status: 'error',
                currentStageIndex: 0,
                header: HEADER,
                stages: STAGES,
                errorMessage
            });
            await new Promise((resolve) => setTimeout(resolve, 1000));
            return;
        }

        const extractionResult = await getCinExtractionResult({ applicantId });
        ctx._cinExtractionResponse = extractionResult;

        if (extractionResult?.isSuccess) {
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
            const errorMessage = extractionResult?.message || 'PAN TO CIN lookup failed.';
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
        const errorMessage = err?.body?.message || err?.message || 'PAN TO CIN lookup failed.';
        ctx._cinExtractionResponse = { isSuccess: false, message: errorMessage };
        dispatchIntegrationProgressUpdate(ctx, {
            show: true,
            status: 'error',
            currentStageIndex: 0,
            header: HEADER,
            stages: STAGES,
            errorMessage
        });
    }
}

export default class ExtractPantocinnApi extends LightningElement {}