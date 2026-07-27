import { LightningElement } from 'lwc';
import invokePANTOGSTNAPI from '@salesforce/apex/ExtractPANTOGSTNAPIController.invokePANTOGSTNAPI';
import getGstExtractionResult from '@salesforce/apex/ExtractPANTOGSTNAPIController.getGstExtractionResult';

const STAGES = ['PAN TO GSTN'];
const HEADER = 'PAN TO GSTN';

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
 * PAN TO GSTN orchestrator for Non-Individual GST document upload.
 *   - onFileUpload : runs PAN TO GSTN lookup using the applicant PAN
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename !== 'onFileUpload') {
        return;
    }

    const applicantId = ctx._applicantId || ctx.applicantId || null;
    if (!applicantId) {
        ctx._gstExtractionResponse = {
            isSuccess: false,
            message: 'Applicant id is required for PAN TO GSTN lookup.'
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
        const apiResult = await invokePANTOGSTNAPI({ applicantId });
        const refreshBlocked = isRefreshBlockedError(apiResult);
        if (apiResult?.hasValidationError && !refreshBlocked) {
            const errorMessage = apiResult.displayMessage || apiResult.errorMessage || 'PAN TO GSTN lookup failed.';
            ctx._gstExtractionResponse = { isSuccess: false, message: errorMessage };
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

        const extractionResult = await getGstExtractionResult({ applicantId });
        ctx._gstExtractionResponse = extractionResult;

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
            const errorMessage = extractionResult?.message || 'PAN TO GSTN lookup failed.';
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
        const errorMessage = err?.body?.message || err?.message || 'PAN TO GSTN lookup failed.';
        ctx._gstExtractionResponse = { isSuccess: false, message: errorMessage };
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

export default class ExtractPantogstnApi extends LightningElement {}