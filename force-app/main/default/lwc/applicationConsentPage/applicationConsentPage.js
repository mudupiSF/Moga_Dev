/**
 * Application Consent LWC — rendered on ApplicationConsent VF page (CustomerService site).
 * Step 1: OTP verification (customer opens link)
 * Step 2: Consent form (after OTP verified via Consent_Sent__c)
 */
import { LightningElement, wire } from 'lwc';
import getApplicationConsentPageData from '@salesforce/apex/aadharOTPVerification.getApplicationConsentPageData';
import acceptApplicationConsent from '@salesforce/apex/aadharOTPVerification.acceptApplicationConsent';

export default class ApplicationConsentPage extends LightningElement {

    applicantIdForWire = '';
    applicantName = '';
    applicationNumber = '';
    sourcerName = '';
    sourcerCode = '';
    mobileNumber = '';
    consentAlreadyReceived = false;
    consentOtpVerified = false;
    isLoading = true;
    acceptLoading = false;
    errorMessage = '';
    acceptMessage = '';

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this.applicantIdForWire = params.get('applicantId') || params.get('id') || '';
        if (!this.applicantIdForWire) {
            this.isLoading = false;
            this.errorMessage = 'Invalid consent link. Applicant information is missing.';
        }
    }

    @wire(getApplicationConsentPageData, { applicantId: '$applicantIdForWire' })
    wiredConsentData({ data, error }) {
        if (!this.applicantIdForWire) {
            return;
        }
        if (data) {
            if (data.isSuccess) {
                this.applicantName = data.applicantName || 'Customer';
                this.applicationNumber = data.applicationNumber || '';
                this.sourcerName = data.sourcerName || '';
                this.sourcerCode = data.sourcerCode || data.sourcerName || '';
                this.mobileNumber = data.mobileNumber || '';
                this.consentAlreadyReceived = data.consentAlreadyReceived === true;
                this.consentOtpVerified = data.consentOtpVerified === true;
                this.errorMessage = '';
            } else {
                this.errorMessage = data.message || 'Unable to load consent details.';
            }
            this.isLoading = false;
        } else if (error) {
            this.errorMessage = this._extractError(error, 'Unable to load consent details.');
            this.isLoading = false;
        }
    }

    get greetingLine() {
        const appNo = this.applicationNumber ? ` ${this.applicationNumber}` : '';
        return `Dear ${this.applicantName}, we note that you have opted to give consent to the Bank towards your Loan application${appNo} allowing the Bank to go ahead with its verification and validation procedures.`;
    }

    get showContent() {
        return !this.isLoading && !this.errorMessage;
    }

    get showOtpStep() {
        return this.showContent && !this.consentOtpVerified && !this.consentAlreadyReceived;
    }

    get showConsentForm() {
        return this.showContent && (this.consentOtpVerified || this.consentAlreadyReceived);
    }

    get isAcceptDisabled() {
        return this.acceptLoading || this.consentAlreadyReceived;
    }

    get statusMessage() {
        if (this.acceptMessage) return this.acceptMessage;
        if (this.consentAlreadyReceived) {
            return 'Your consent has already been recorded for this application.';
        }
        return '';
    }

    get showStatusMessage() {
        return Boolean(this.statusMessage);
    }

    handleConsentOtpVerified() {
        this.consentOtpVerified = true;
        this.errorMessage = '';
    }

    async handleAcceptConsent() {
        if (this.isAcceptDisabled || !this.applicantIdForWire) {
            return;
        }
        this.acceptLoading = true;
        this.acceptMessage = '';
        try {
            const result = await acceptApplicationConsent({ applicantId: this.applicantIdForWire });
            if (result?.isSuccess) {
                this.consentAlreadyReceived = true;
                this.acceptMessage = result.message || 'Consent accepted successfully.';
                this.errorMessage = '';
            } else {
                this.errorMessage = result?.message || 'Unable to accept consent.';
            }
        } catch (error) {
            this.errorMessage = this._extractError(error, 'Unable to accept consent.');
        } finally {
            this.acceptLoading = false;
        }
    }

    _extractError(error, fallback) {
        return error?.body?.message || error?.message || fallback;
    }
}