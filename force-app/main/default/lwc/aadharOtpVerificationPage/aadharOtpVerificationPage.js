/**
 * aadharOtpVerificationPage
 *
 * Customer-facing Aadhaar eKYC LWC rendered on the public CustomerService Site
 * via the AadharVerification VF page (Lightning Out). 
 */
import { LightningElement } from 'lwc';
import sendOtpApex            from '@salesforce/apex/aadharOTPVerification.sendOtpForLwc';
import verifyOtpApex          from '@salesforce/apex/aadharOTPVerification.verifyOtpAndConfirmConsentForLwc';
import hasExistingConsentApex from '@salesforce/apex/aadharOTPVerification.hasExistingConsent';

const STEP = { AADHAAR: 'aadhaar', OTP: 'otp', SUCCESS: 'success', ERROR: 'error' };

export default class AadharOtpVerificationPage extends LightningElement {

    currentStep = STEP.AADHAAR;

    aadhaarNumber    = '';
    formattedAadhaar = '';
    sendOtpLoading   = false;

    otpDigits        = ['', '', '', '', '', ''];
    verifyLoading    = false;
    isOtpVerified    = false;
    isTermsAccepted  = false;
    resendTimer      = 45;
    _resendInterval;
    _successNavigateTimer;

    errorMessage = '';
    generalError = '';

    _applicantId = '';
    _loanId      = '';
    _kycId       = '';

    /* ═══════════════════════════════
       COMPUTED
    ═══════════════════════════════ */

    get isAadhaarStep() { return this.currentStep === STEP.AADHAAR; }
    get isOtpStep()     { return this.currentStep === STEP.OTP; }
    get isSuccessStep() { return this.currentStep === STEP.SUCCESS; }
    get isErrorStep()   { return this.currentStep === STEP.ERROR; }

    get sendOtpDisabled() {
        return this.sendOtpLoading || this.aadhaarNumber.length !== 12;
    }

    get otpSlots() {
        return this.otpDigits.map((digit, i) => ({
            key: `otp-${i}`,
            index: String(i),
            value: digit
        }));
    }

    get isOtpComplete() {
        return this.otpDigits.join('').length === 6;
    }

    get isVerifyDisabled() {
        return this.verifyLoading || !this.isTermsAccepted || this.isOtpVerified;
    }

    get verifyButtonClass() {
        return this.isOtpVerified ? 'primary-btn primary-btn-verified' : 'primary-btn';
    }

    get resendTimerDisplay() {
        if (this.resendTimer === 0) return 'Resend Code';
        const s = this.resendTimer;
        return `Resend Code in 00:${s < 10 ? '0' + s : s}`;
    }

    get canResend() { return this.resendTimer === 0; }

    get resendClass() {
        return this.canResend ? 'resend-link resend-link-active' : 'resend-link';
    }

    /* ═══════════════════════════════
       LIFECYCLE
    ═══════════════════════════════ */

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this._applicantId = params.get('applicantId') || '';
        this._loanId      = params.get('loanId')      || '';
        // MOGA DEV adds kycId on every generated link — it identifies the
        // specific Applicant_KYC__c row the controller should mutate.
        this._kycId       = params.get('kycId') || params.get('kycid') || '';
        this._loadExistingConsentStatus();
    }

    disconnectedCallback() {
        this._clearResendTimer();
        this._clearSuccessNavigateTimer();
    }

    /* ═══════════════════════════════
       AADHAAR INPUT
    ═══════════════════════════════ */

    handleAadhaarInput(event) {
        const raw = event.target.value.replace(/\D/g, '').slice(0, 12);
        this.aadhaarNumber = raw;

        let formatted = raw;
        if (raw.length > 8) {
            formatted = raw.slice(0, 4) + ' ' + raw.slice(4, 8) + ' ' + raw.slice(8);
        } else if (raw.length > 4) {
            formatted = raw.slice(0, 4) + ' ' + raw.slice(4);
        }
        this.formattedAadhaar = formatted;
        event.target.value    = formatted;
        this.errorMessage     = '';
    }

    /* ═══════════════════════════════
       SEND OTP
    ═══════════════════════════════ */

    handleSendOtp() {
        if (this.aadhaarNumber.length !== 12 || !/^\d{12}$/.test(this.aadhaarNumber)) {
            this.errorMessage = 'Please enter a valid 12-digit Aadhaar number';
            return;
        }
        if (/^(\d)\1{11}$/.test(this.aadhaarNumber)) {
            this.errorMessage = 'Invalid Aadhaar number pattern';
            return;
        }

        this.sendOtpLoading = true;
        this.errorMessage   = '';

        sendOtpApex({
            applicantId   : this._applicantId,
            kycId         : this._kycId,
            aadhaarNumber : this.aadhaarNumber
        })
            .then(result => {
                this.sendOtpLoading = false;
                if (result && result.isSuccess) {
                    this.currentStep = STEP.OTP;
                    this._startResendTimer();
                } else {
                    this.errorMessage = (result && result.message) || 'Failed to send OTP';
                }
            })
            .catch(error => {
                this.sendOtpLoading = false;
                this.errorMessage   = (error && error.body && error.body.message)
                    || (error && error.message)
                    || 'An error occurred. Please try again.';
            });
    }

    /* ═══════════════════════════════
       OTP INPUT HANDLERS
    ═══════════════════════════════ */

    handleOtpInput(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = event.target.value.replace(/\D/g, '');
        const next  = [...this.otpDigits];

        if (value.length === 1) {
            next[index] = value;
            this.otpDigits = next;
            if (index < 5) {
                const el = this.template.querySelector(`input[data-index="${index + 1}"]`);
                if (el) el.focus();
            }
        } else {
            next[index] = '';
            this.otpDigits = next;
            event.target.value = '';
        }
        if (this.isOtpVerified) {
            this.isOtpVerified = false;
            this._clearSuccessNavigateTimer();
        }
        this.errorMessage = '';
    }

    handleOtpKeydown(event) {
        const index = parseInt(event.target.dataset.index, 10);
        if (event.key === 'Backspace') {
            const next = [...this.otpDigits];
            if (!event.target.value && index > 0) {
                next[index - 1] = '';
                this.otpDigits = next;
                const el = this.template.querySelector(`input[data-index="${index - 1}"]`);
                if (el) el.focus();
            } else {
                next[index] = '';
                this.otpDigits = next;
            }
        }
    }

    handleOtpPaste(event) {
        event.preventDefault();
        const paste = (event.clipboardData || window.clipboardData).getData('text').trim();
        if (paste.length <= 6 && /^\d+$/.test(paste)) {
            const next = ['', '', '', '', '', ''];
            for (let i = 0; i < paste.length; i++) next[i] = paste[i];
            this.otpDigits = next;
            const focusIdx = Math.min(paste.length, 5);
            const el = this.template.querySelector(`input[data-index="${focusIdx}"]`);
            if (el) el.focus();
        }
    }

    /* ═══════════════════════════════
       VERIFY OTP
    ═══════════════════════════════ */

    handleVerifyOtp() {
        const otp = this.otpDigits.join('');
        if (otp.length < 6) {
            this.errorMessage = 'Please enter all 6 digits';
            return;
        }

        this.verifyLoading = true;
        this.errorMessage  = '';

        verifyOtpApex({
            applicantId   : this._applicantId,
            loanId        : this._loanId,
            kycId         : this._kycId,
            aadhaarNumber : this.aadhaarNumber,
            otp,
            consent       : this.isTermsAccepted === true
        })
            .then(result => {
                this.verifyLoading = false;
                if (result && result.isSuccess) {
                    this._clearResendTimer();
                    this.isOtpVerified = true;
                    this._scheduleSuccessStep();
                } else {
                    this.errorMessage = (result && result.message) || 'Verification failed. Please try again.';
                }
            })
            .catch(error => {
                this.verifyLoading = false;
                this.errorMessage  = (error && error.body && error.body.message)
                    || (error && error.message)
                    || 'An error occurred. Please try again.';
            });
    }

    /* ═══════════════════════════════
       RESEND OTP
    ═══════════════════════════════ */

    handleResendOtp() {
        if (!this.canResend) return;
        this.isOtpVerified = false;
        this._clearSuccessNavigateTimer();
        this._startResendTimer();
        this.errorMessage = '';

        sendOtpApex({
            applicantId   : this._applicantId,
            kycId         : this._kycId,
            aadhaarNumber : this.aadhaarNumber
        })
            .then(result => {
                if (!result || !result.isSuccess) {
                    this.errorMessage = (result && result.message) || 'Failed to resend OTP';
                }
            })
            .catch(error => {
                this.errorMessage = (error && error.body && error.body.message)
                    || (error && error.message)
                    || 'Failed to resend OTP';
            });
    }

    /* ═══════════════════════════════
       MISC HANDLERS
    ═══════════════════════════════ */

    handleTermsChange(event) {
        this.isTermsAccepted = event.target.checked;
    }

    handleTermsClick(event) {
        event.preventDefault();
    }

    handleTryAgain() {
        this.currentStep     = STEP.AADHAAR;
        this.errorMessage    = '';
        this.generalError    = '';
        this.otpDigits       = ['', '', '', '', '', ''];
        this.isOtpVerified   = false;
        this.isTermsAccepted = false;
        this._clearSuccessNavigateTimer();
    }

    /* ═══════════════════════════════
       PRIVATE HELPERS
    ═══════════════════════════════ */

    _loadExistingConsentStatus() {
        if (!this._applicantId || !this._kycId) return;
        hasExistingConsentApex({
            applicantId : this._applicantId,
            kycId       : this._kycId
        })
            .then(alreadyConsented => {
                if (alreadyConsented === true) {
                    this.currentStep = STEP.SUCCESS;
                }
            })
            .catch(() => {
                // Silent — the connect-time check is informational only.
            });
    }

    _startResendTimer() {
        this.resendTimer = 45;
        this._clearResendTimer();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._resendInterval = setInterval(() => {
            if (this.resendTimer > 0) {
                this.resendTimer--;
            } else {
                this._clearResendTimer();
            }
        }, 1000);
    }

    _clearResendTimer() {
        if (this._resendInterval) {
            clearInterval(this._resendInterval);
            this._resendInterval = null;
        }
    }

    _scheduleSuccessStep() {
        this._clearSuccessNavigateTimer();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._successNavigateTimer = setTimeout(() => {
            this.currentStep = STEP.SUCCESS;
        }, 800);
    }

    _clearSuccessNavigateTimer() {
        if (this._successNavigateTimer) {
            clearTimeout(this._successNavigateTimer);
            this._successNavigateTimer = null;
        }
    }
}