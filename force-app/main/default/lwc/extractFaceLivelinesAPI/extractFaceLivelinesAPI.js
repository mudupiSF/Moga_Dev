import { LightningElement } from 'lwc';
import invokeFaceLivelinesAPI from '@salesforce/apex/ExtractFaceLivelinesAPIController.invokeFaceLivelinesAPI';
import getFaceLivelinesResult from '@salesforce/apex/ExtractFaceLivelinesAPIController.getFaceLivelinesResult';

function resolveErrorMessage(err) {
    return err?.body?.message || err?.message || 'Face Liveliness failed.';
}

export async function onLoad(submodulename, ctx) {
    if (submodulename !== 'onFileUpload') {
        return;
    }

    const applicantId = ctx._applicantId || ctx.applicantId || null;
    if (!applicantId) {
        return { isSuccess: false, message: 'Applicant id is required.' };
    }

    try {
        const apiResult = await invokeFaceLivelinesAPI({ applicantId });
        if (apiResult?.hasValidationError) {
            return {
                isSuccess: false,
                hasValidationError: true,
                message: apiResult?.displayMessage || apiResult?.errorMessage || 'Face Liveliness failed.'
            };
        }

        const extractionResult = await getFaceLivelinesResult({ applicantId });
        if (!extractionResult?.isSuccess) {
            return {
                isSuccess: false,
                hasValidationError: true,
                message: extractionResult?.message || 'Face Liveliness failed.'
            };
        }
        return {
            isSuccess: true,
            message: extractionResult?.message || 'Face Liveliness completed.',
            responseBody: extractionResult?.responseBody || ''
        };
    } catch (err) {
        return {
            isSuccess: false,
            hasValidationError: true,
            message: resolveErrorMessage(err)
        };
    }
}

export default class ExtractFaceLivelinesAPI extends LightningElement {}