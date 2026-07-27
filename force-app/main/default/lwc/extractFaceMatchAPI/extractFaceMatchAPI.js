import { LightningElement } from 'lwc';
import invokeFaceMatchAPI from '@salesforce/apex/ExtractFaceMatchAPIController.invokeFaceMatchAPI';
import getFaceMatchResult from '@salesforce/apex/ExtractFaceMatchAPIController.getFaceMatchResult';

function resolveErrorMessage(err) {
    return err?.body?.message || err?.message || 'Face Match failed.';
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
        const apiResult = await invokeFaceMatchAPI({ applicantId });
        if (apiResult?.hasValidationError) {
            return {
                isSuccess: false,
                hasValidationError: true,
                message: apiResult?.displayMessage || apiResult?.errorMessage || 'Face Match failed.'
            };
        }

        const extractionResult = await getFaceMatchResult({ applicantId });
        if (!extractionResult?.isSuccess) {
            return {
                isSuccess: false,
                hasValidationError: true,
                message: extractionResult?.message || 'Face Match failed.'
            };
        }
        return {
            isSuccess: true,
            message: extractionResult?.message || 'Face Match completed.',
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

export default class ExtractFaceMatchAPI extends LightningElement {}