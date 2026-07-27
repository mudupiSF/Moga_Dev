import { LightningElement } from 'lwc';
import getApplicant from '@salesforce/apex/ExtractPANOCRAPIController.getApplicant';
import invokePANOCRAPI from '@salesforce/apex/ExtractPANOCRAPIController.invokePANOCRAPI';
import invokeValidatePANAPI from '@salesforce/apex/ExtractPANOCRAPIController.invokeValidatePANAPI';
import markPanVerified from '@salesforce/apex/ExtractPANOCRAPIController.markPanVerified';

const STAGES = [
    'Extracting PAN Data',
    'Verifying PAN'
];

const HEADER = 'Extracting and Validating PAN Data';

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

function formatApplicantDateForInput(rawDate) {
    if (rawDate == null || rawDate === '') {
        return '';
    }
    const value = String(rawDate);
    if (/^\d{4}-\d{2}-\d{2}/.test(value)) {
        return value.substring(0, 10);
    }
    return value;
}

function applyPanOcrExtractedDates(ctx, applicant) {
    const dateValue = formatApplicantDateForInput(applicant?.Date_of_Birth__c);
    if (ctx.isNonIndividualApplicant) {
        ctx.updateFieldValue('dateOfIncorporation', dateValue);
        return;
    }
    ctx.updateFieldValue('extractedDateOfBirth', dateValue);
}

/**
 * Extract PAN OCR orchestrator.
 *   - onFileUpload    : runs OCR and extracts PAN data
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename === 'onFileUpload') {
        const hasFiles = ctx._fileMap && Object.keys(ctx._fileMap).length > 0;
        if (!hasFiles) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: false, status: 'loading', currentStageIndex: 0,
                stages: STAGES, errorMessage: ''
            });
            return;
        }
        const firstKey = Object.keys(ctx._fileMap)[0];
        if (firstKey !== 'panCardUploadElement') return;

        dispatchIntegrationProgressUpdate(ctx, {
            show: true, status: 'loading', currentStageIndex: 0,
            header: HEADER,
            stages: STAGES, errorMessage: ''
        });

        const fileData = ctx._fileMap[firstKey];
        const contentDocumentId = fileData?.contentDocumentId;
        const contentVersionId = fileData?.contentVersionId;
        const applicantId = ctx.applicantId || null;
        try {
            if (contentDocumentId || contentVersionId) {
                const result = await invokePANOCRAPI({ applicantId });
                if (result && !result.hasValidationError) {
                    const applicant = await getApplicant({ applicantId });
                    const firstName = applicant.Customer_First_Name__c;
                    const lastName = applicant.Customer_Last_Name__c;
                    const panCardNumber = applicant.PAN_Number__c;
                    const dateOfBirth = applicant.Date_of_Birth__c;
                    ctx.panData = { firstName, lastName, panCardNumber, dateOfBirth };

                    ctx.updateFieldValue('extractedFirstName', firstName);
                    ctx.updateFieldValue('extractedLastName', lastName);
                    ctx.updateFieldValue('extractedPanCardNumber', panCardNumber);
                    applyPanOcrExtractedDates(ctx, applicant);
                    ctx.setActionState('extractedPanCardNumber', 'loading');

                    dispatchIntegrationProgressUpdate(ctx, {
                        show: true, status: 'loading', currentStageIndex: 1,
                        header: HEADER,
                        stages: STAGES, errorMessage: ''
                    });
                    const verifyPANCardResult = await invokeValidatePANAPI({ applicantId });
                    if (verifyPANCardResult && !verifyPANCardResult.hasValidationError) {
                        dispatchIntegrationProgressUpdate(ctx, {
                            show: true, status: 'success', currentStageIndex: 1,
                            header: HEADER,
                            stages: STAGES, errorMessage: ''
                        });
                        //await new Promise((r) => setTimeout(r, 2000));
                        await markPanVerified({ applicantId, verified: true }).catch(() => {});
                        ctx.updateFieldValue('pancardVerificationErrorMessage', '');
                        ctx.updateFieldValue('pancardVerificationStatus', 'success');
                        ctx.setActionState('extractedPanCardNumber', 'success');
                    }
                    else {
                        dispatchIntegrationProgressUpdate(ctx, {
                            show: true, status: 'error', currentStageIndex: 1,
                            header: HEADER,
                            stages: STAGES, errorMessage: 'Error happened while invoking Validate PAN API.'
                        });
                        ctx.setActionState('extractedPanCardNumber', 'idle');
                        ctx.updateFieldValue('pancardVerificationStatus', 'Failed');
                    }
                }
                else {
                    dispatchIntegrationProgressUpdate(ctx, {
                        show: true, status: 'error', currentStageIndex: 0,
                        header: HEADER,
                        stages: STAGES, errorMessage: result.errorMessage || 'Error happened while extracting PAN data.'
                    });
                }
            }
        }
        catch (err) {
            ctx.updateFieldValue('pancardVerificationErrorMessage', err?.message || 'Verification failed');
            ctx.updateFieldValue('pancardVerificationStatus', 'Failed');
            ctx.setActionState('extractedPanCardNumber', 'idle');
        }
    }
}

export default class ExtractPANOCRAPI extends LightningElement {}