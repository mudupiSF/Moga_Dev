import { LightningElement, api } from 'lwc';
import getFormRenderData from '@salesforce/apex/CustomerFormController.getFormRenderData';
import markApplicationConsentReceived from '@salesforce/apex/CustomerFormController.markApplicationConsentReceived';

const LOG = '[CustomerFormHost]';
const FORM_APPLICATION = 'Application_Form';
const FORM_INSURANCE   = 'Insurance_Form';
const CONSENT_ALREADY_RECEIVED_MSG =
    'Application consent has already been received. No further action is required.';

export default class CustomerFormHost extends LightningElement {
    @api applicantId;
    @api formName;
    @api callingFromVf;
    loading = true;
    errorMessage;
    templateId;
    documentChecklistId;
    fileName;
    inputJSON;
    consentAlreadyReceived = false;
    consentMessage;
    consentSubmitted = false;

    connectedCallback() {
        console.log(LOG, 'Component mounted on page', {
            applicantId: this.applicantId,
            formName: this.formName
        });
        this.loadFormData();
    }

    get showRenderer() {
        return (
            !this.loading &&
            !this.errorMessage &&
            !this.consentAlreadyReceived &&
            this.templateId
        );
    }

    get showConsentMessage() {
        return !this.loading && !this.errorMessage && this.consentAlreadyReceived;
    }

    get showLoading() {
        return this.loading;
    }

    get showError() {
        return !this.loading && this.errorMessage;
    }

    get showDataSummary() {
        return !this.loading && !this.errorMessage && this.templateId;
    }

    async loadFormData() {
        if (!this.applicantId) {
            this.errorMessage = 'Applicant ID (applicantId) is required.';
            this.loading = false;
            console.error(LOG, this.errorMessage);
            return;
        }

        console.log(LOG, 'Loading form data', {
            applicantId: this.applicantId,
            formName: this.formName
        });

        try {
            const data = await getFormRenderData({
                applicantId: this.applicantId,
                formName: this.formName
            });

            this.templateId = data.templateId;
            this.documentChecklistId = data.documentChecklistId;
            this.fileName = data.fileName;
            this.inputJSON = data.inputJSON || {};
            this.consentAlreadyReceived =
                this._isApplicationForm() && data.applicationConsentReceived === true;
            this.consentMessage = this.consentAlreadyReceived
                ? CONSENT_ALREADY_RECEIVED_MSG
                : null;
            this.loading = false;

            console.log(LOG, 'Form data loaded', {
                templateId: this.templateId,
                documentChecklistId: this.documentChecklistId,
                fileName: this.fileName,
                inputJsonKeyCount: Object.keys(this.inputJSON).length,
                consentAlreadyReceived: this.consentAlreadyReceived
            });
        } catch (error) {
            this.errorMessage = this._formatError(error);
            this.loading = false;
            console.error(LOG, 'Failed to load form data:', this.errorMessage, error);
        }
    }

    _isApplicationForm() {
        return FORM_APPLICATION === this.formName;
    }

    async handleFormSubmitted() {
        console.log(LOG, 'Form submitted', { formName: this.formName });
        if (this._isApplicationForm()) {
            await this.submitApplicationConsent();
        }
        else if (this._isInsuranceForm()) {
            await this.submitInsuranceConsent();
        }
    }

    _isInsuranceForm() {
        return FORM_INSURANCE === this.formName;
    }

    async submitInsuranceConsent() {
        try {
            // await markInsuranceConsentReceived({ applicantId: this.applicantId });
            this.consentAlreadyReceived = true;
            this.consentMessage = CONSENT_ALREADY_RECEIVED_MSG;
        } catch (error) {
            this.errorMessage = this._formatError(error);
            console.error(LOG, 'Failed to record insurance consent:', this.errorMessage, error);
        }
    }

    async submitApplicationConsent() {
        try {
            await markApplicationConsentReceived({ applicantId: this.applicantId });
            this.consentAlreadyReceived = true;
            this.consentMessage = CONSENT_ALREADY_RECEIVED_MSG;
        } catch (error) {
            this.errorMessage = this._formatError(error);
            console.error(LOG, 'Failed to record application consent:', this.errorMessage, error);
        }
    }

    _formatError(error) {
        const raw = error?.body?.message || error?.message || 'Failed to load form data.';
        if (/unexpected token\s+'<'|not valid json|<!doctype/i.test(raw)) {
            return (
                'Server returned an HTML page instead of JSON. Grant the site guest profile ' +
                'Apex access to CustomerFormController and PDFforceController.'
            );
        }
        return raw;
    }
}