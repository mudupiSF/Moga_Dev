import { LightningElement } from 'lwc';
//import ocrPANCard from '@salesforce/apex/documentVerificationController.ocrPANCard';
import invokePANOCRAPI from '@salesforce/apex/documentVerificationController.invokePANOCRAPI';
import getApplicant from '@salesforce/apex/documentVerificationController.getApplicant';
//import textMatchPANCard from '@salesforce/apex/documentVerificationController.textMatchPANCard';
//import verifyPANCard from '@salesforce/apex/documentVerificationController.verifyPANCard';
import invokeValidatePANAPI from '@salesforce/apex/documentVerificationController.invokeValidatePANAPI';
import verifyEmail from '@salesforce/apex/documentVerificationController.verifyEmail';
import savePANForReVerify from '@salesforce/apex/documentVerificationController.savePANForReVerify';
import markPanVerified from '@salesforce/apex/documentVerificationController.markPanVerified';

const INTEGRATION_STAGES = [
    'Extracting PAN Data',
    //'Text Match',
    'Verifying PAN'
];

const PAN_VERIFICATION_STAGES = [
    'Verifying PAN'
];

const EMAIL_VERIFICATION_STAGES = [
    'Email Verification'
];

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

function dispatchOpenDynamicComponentModal(ctx, componentName) {
    ctx.dispatchEvent(
        new CustomEvent('opendynamiccomponentmodal', {
            detail: { componentName },
            bubbles: true,
            composed: true
        })
    );
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
 * Document Verification orchestrator.
 *   - onFileUpload    : runs full OCR → Text Match → PAN Verification
 *   - onReVerify      : skips OCR (user edited PAN manually); persists encrypted PAN, then re-runs Text Match → Verify
 *   - onAction        : single Apex action (Verify PAN, Verify Email)
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename === 'onAction') {
        const key = ctx._lastActionFieldKey;
        if (key === 'panCardNumber') {
            const applicantId = ctx.applicantId || null;
            if (applicantId) {
                try {
                    const result = await verifyPANCard({ applicantId });
                    ctx.setActionState(key, result ? 'success' : 'idle');
                } catch (e) {
                    ctx.setActionState(key, 'idle');
                }
            }
        }
        if (key === 'email') {
            const field = ctx.fields?.find((f) => f.key === key);
            const email = field?.value;
            if (email) {
                try {
                    await new Promise((r) => setTimeout(r, 0));
                    const result = await verifyEmail({ email });
                    dispatchIntegrationProgressUpdate(ctx, {
                        show: false,
                        status: result ? 'success' : 'idle',
                        currentStageIndex: 0,
                        stages: EMAIL_VERIFICATION_STAGES,
                        errorMessage: ''
                    });
                    if (result) {
                        dispatchOpenDynamicComponentModal(ctx, 'sfLOSPlaceholderPage');
                    }
                    ctx.updateFieldValue('emailVerificationErrorMessage', '');
                    ctx.updateFieldValue('emailVerificationStatus', result ? 'Success' : 'Failed');
                } catch (e) {
                    ctx.setActionState('email', 'idle');
                    dispatchIntegrationProgressUpdate(ctx, {
                        show: true,
                        status: 'error',
                        currentStageIndex: 0,
                        stages: EMAIL_VERIFICATION_STAGES,
                        errorMessage: e.message
                    });
                }
            }
        }
        return;
    }

    if (submodulename === 'onReVerify') {
        await runReVerifyFlow(ctx);
        return;
    }

    if (submodulename === 'onFileUpload') {
        const hasFiles = ctx._fileMap && Object.keys(ctx._fileMap).length > 0;
        if (!hasFiles) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: false, status: 'loading', currentStageIndex: 0,
                stages: INTEGRATION_STAGES, errorMessage: ''
            });
            return;
        }
        const firstKey = Object.keys(ctx._fileMap)[0];
        if (firstKey !== 'panCardUploadElement') return;

        dispatchIntegrationProgressUpdate(ctx, {
            show: true, status: 'loading', currentStageIndex: 0,
            header: 'Extracting and Validating PAN Data',
            stages: INTEGRATION_STAGES, errorMessage: ''
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
                        header: 'Extracting and Validating PAN Data',
                        stages: INTEGRATION_STAGES, errorMessage: ''
                    });
                    const verifyPANCardResult = await invokeValidatePANAPI({ applicantId });
                    if (verifyPANCardResult && !verifyPANCardResult.hasValidationError) {
                        dispatchIntegrationProgressUpdate(ctx, {
                            show: true, status: 'loading', currentStageIndex: 2,
                            header: 'Extracting and Validating PAN Data',
                            stages: INTEGRATION_STAGES, errorMessage: ''
                        });
                        await new Promise((r) => setTimeout(r, 1000));
                        await markPanVerified({ applicantId, verified: true }).catch(() => {});
                        ctx.updateFieldValue('pancardVerificationErrorMessage', '');
                        ctx.updateFieldValue('pancardVerificationStatus', 'success');
                        ctx.setActionState('extractedPanCardNumber', 'success');
                    }
                    else {
                        dispatchIntegrationProgressUpdate(ctx, {
                            show: true, status: 'error', currentStageIndex: 1,
                            header: 'Extracting and Validating PAN Data',
                            stages: INTEGRATION_STAGES, errorMessage: 'Error happened while invoking Validate PAN API.'
                        });
                        ctx.setActionState('extractedPanCardNumber', 'idle');
                        ctx.updateFieldValue('pancardVerificationStatus', 'Failed');
                    }
                }
                else {
                    dispatchIntegrationProgressUpdate(ctx, {
                        show: true, status: 'error', currentStageIndex: 0,
                        header: 'Extracting and Validating PAN Data',
                        stages: INTEGRATION_STAGES, errorMessage: result.errorMessage || 'Error happened while extracting PAN data.'
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

/** Manual re-verify path: user edited PAN after a failed attempt.
 *  Persists the new PAN (encrypted by Apex) and re-runs Text Match + Verify only.
 *  Modal still shows all three stages; stage 0 represents the encrypted save. */
async function runReVerifyFlow(ctx) {
    const applicantId = ctx.applicantId || null;
    const panCardNumber = (ctx.extractedPanCardNumber || '').trim().toUpperCase();
    if (!applicantId || !panCardNumber) {
        return;
    }
    dispatchIntegrationProgressUpdate(ctx, {
        show: true, status: 'loading', currentStageIndex: 0,
        stages: PAN_VERIFICATION_STAGES, errorMessage: ''
    });
    //ctx.setActionState('extractedPanCardNumber', 'loading');
    try {
        /*await savePANForReVerify({ applicantId, panCardNumber });

        dispatchIntegrationProgressUpdate(ctx, {
            show: true, status: 'loading', currentStageIndex: 1,
            stages: INTEGRATION_STAGES, errorMessage: ''
        });*/
        /*const textMatchResult = await textMatchPANCard({ applicantId });
        if (!textMatchResult) {
            ctx.setActionState('extractedPanCardNumber', 'idle');
            ctx.updateFieldValue('pancardVerificationStatus', 'Failed');
            return;
        }*/

        /*dispatchIntegrationProgressUpdate(ctx, {
            show: true, status: 'loading', currentStageIndex: 2,
            stages: INTEGRATION_STAGES, errorMessage: ''
        });*/
        const verifyPANCardResult = await invokeValidatePANAPI({ applicantId });
        if (verifyPANCardResult && !verifyPANCardResult.hasValidationError) {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'success', currentStageIndex: 0,
                stages: PAN_VERIFICATION_STAGES, errorMessage: ''
            });
            await new Promise((r) => setTimeout(r, 1000));
            await markPanVerified({ applicantId, verified: true }).catch(() => {});
            ctx.updateFieldValue('pancardVerificationErrorMessage', '');
            ctx.updateFieldValue('pancardVerificationStatus', 'success');
            //ctx.setActionState('extractedPanCardNumber', 'success');
        }
        else {
            dispatchIntegrationProgressUpdate(ctx, {
                show: true, status: 'error', currentStageIndex: 1,
                stages: PAN_VERIFICATION_STAGES, errorMessage: verifyPANCardResult.errorMessage || 'Verification failed'
            });
            ctx.updateFieldValue('pancardVerificationErrorMessage', verifyPANCardResult.errorMessage || 'Verification failed');
            ctx.updateFieldValue('pancardVerificationStatus', 'Failed');
            //ctx.setActionState('extractedPanCardNumber', 'idle');
        }
    }
    catch (err) {
        ctx.updateFieldValue('pancardVerificationErrorMessage', err?.message || 'Verification failed');
        ctx.updateFieldValue('pancardVerificationStatus', 'Failed');
        //ctx.setActionState('extractedPanCardNumber', 'idle');
    }
    finally {
        dispatchIntegrationProgressUpdate(ctx, {
            show: false, status: 'success', currentStageIndex: 2,
            stages: PAN_VERIFICATION_STAGES, errorMessage: ''
        });
    }
}

export default class ClientLayerDocumentVerification extends LightningElement {}