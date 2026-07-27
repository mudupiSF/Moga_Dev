import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateEmailOTP from '@salesforce/apex/SendEmailOTPAPIController.generateOTP';
import generatePhoneOTP from '@salesforce/apex/SendPhoneOTPAPIController.generateOTP';
import verifyOTP from '@salesforce/apex/SendPhoneOTPAPIController.verifyOTP';
import verifyOfficeOTP from '@salesforce/apex/OfficeEmailOTPController.verifyOTP';
import sendApplicationConsentOtp from '@salesforce/apex/aadharOTPVerification.sendApplicationConsentOtp';
import verifyApplicationConsentOtp from '@salesforce/apex/aadharOTPVerification.verifyApplicationConsentOtp';
import { invokeHandler } from 'c/clientLayerHelper';

/** Module-level reference to the parent card context, set by onLoad */
let _ctx = null;
let _pendingFieldKey = null;
let _verified = false;
const INTEGRATION_PROGRESS_EVENT = 'integrationprogressupdate';

export function getCtx() {
    return _ctx;
}

/**
 * Contact-info section handler.
 * Invoked by sfLOSClientLayerHelper when handler-name="contactInfoCheck".
 *
 * @param {string} submodulename - 'onAction' when a field action button is clicked
 * @param {object} ctx - sfLOSTwoColumnCardLayoutEdit instance
 */
export async function onLoad(submodulename, ctx) {
    if (submodulename !== 'onAction') return;

    const key = ctx._lastActionFieldKey;
    if (!key) return;

    const phonevalue = ctx.contactInfoFieldValues?.contactNumber;
    const emailvalue = ctx.contactInfoFieldValues?.email;
    const value = (key === 'contactNumber' || key === 'phone') ? phonevalue : emailvalue;
    if (!value) return;

    if (key === 'contactNumber' || key === 'phone' || key === 'emailAddress' || key === 'email') {
        _ctx = ctx;
        _pendingFieldKey = (key === 'phone') ? 'contactNumber' : (key === 'emailAddress' ? 'email' : key);
        _verified = false;
        const otpType = (key === 'contactNumber' || key === 'phone') ? 'mobile' : 'email';
        const isPanAvailable = ctx.documentVerificationFieldValues?.isPanAvailable || 'Yes';
        // Office-email path: verify against the Office Applicant_Address__c row
        // instead of Applicant__c. Default (undefined) keeps the personal flow.
        const verifyMode = ctx.otpVerifyMode || null;
        const addressId  = ctx.officeAddressId || null;
        ctx.dispatchEvent(
            new CustomEvent('opendynamiccomponentmodal', {
                detail: {
                    componentName: 'otpVerification',
                    modalHeader: key === 'contactNumber' ? 'Verify Mobile' : 'Verify Email',
                    recordId: ctx.recordId,
                    applicantId: ctx.applicantId || null,
                    otpType,
                    verifyTarget: value,
                    isPanPath: isPanAvailable !== 'No',
                    verifyMode,
                    addressId
                },
                bubbles: true,
                composed: true
            })
        );
    }
}

export default class OtpVerification extends LightningElement {

    @api recordId;

    /** Applicant__c Id used to persist verification codes + run the post-OTP integration chain. */
    @api applicantId;

    @api headerName = 'OTP Verification';

    /** 'mobile' or 'email' — controls icon and description text */
    _otpType = 'mobile';
    @api
    get otpType() { return this._otpType; }
    set otpType(val) { this._otpType = val || 'mobile'; }

    /** The phone number or email address being verified (display only) */
    @api verifyTarget = '';

    /** When 'consent', OTP success closes the modal without updating contact verify UI state. */
    @api otpContext = '';

    /** When true, uses guest-safe Apex on the ApplicationConsent VF page. */
    @api guestSiteMode = false;

    /** When 'officeAddress', verify against Applicant_Address__c via OfficeEmailOTPController. */
    @api verifyMode = null;

    /** Office Applicant_Address__c Id used when verifyMode === 'officeAddress'. */
    @api addressId = null;

    /* ── OTP State ── */
    @track _contactActionStates = {};
    otpLoading = false;
    otpDigits = ['', '', '', '', '', ''];
    isTermsAccepted = false;
    resendTimer = 45;
    inlineErrorMessage = '';
    _lastActionFieldKey = '';
    _resendInterval;
    _integrationProgressHandler;
    _guestOtpInitDone = false;
    @track guestOtpSending = false;
    showIntegrationProgressModal = false;
    integrationProgressModalStatus = 'loading';
    integrationProgressModalHeader = '';
    integrationProgressModalCurrentStageIdx = 0;
    integrationProgressModalStages = [];
    integrationProgressModalErrorMessage = '';

    /* ═══════════════════════════════
       COMPUTED
    ═══════════════════════════════ */

    get isMobileOtp() { return this._otpType === 'mobile'; }
    get isEmailOtp()  { return this._otpType === 'email'; }

    get otpTitle() {
        return this._otpType === 'mobile' ? 'Verify Mobile' : 'Verify Email';
    }

    get displayTitle() {
        return this.headerName || this.otpTitle;
    }

    get otpDescription() {
        const target = this.verifyTarget
            ? ` (${this.verifyTarget})`
            : '';
        return this._otpType === 'mobile'
            ? `A 6-digit verification code has been sent to your registered mobile number${target}.`
            : `A 6-digit verification code has been sent to your email address${target}.`;
    }

    get otpSlots() {
        return this.otpDigits.map((digit, i) => ({
            key: `otp-${i}`,
            index: String(i),
            value: digit
        }));
    }

    get isOTPEntered() {
        const otp = this.otpDigits.join('');
        return otp.length === 6;
    }

    get isVerifyDisabled() {
        return !this.isTermsAccepted || !this.isOTPEntered || this.otpLoading;
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

    get showGuestOtpSpinner() {
        return this.guestSiteMode && this.otpContext === 'consent' && this.guestOtpSending;
    }

    get showOtpInputs() {
        return !this.showGuestOtpSpinner;
    }

    /* ═══════════════════════════════
       LIFECYCLE
    ═══════════════════════════════ */

    connectedCallback() {
        _verified = false;
        this._startResendTimer();
        this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e);
        window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
    }

    renderedCallback() {
        if (this._guestOtpInitDone || !this.guestSiteMode || this.otpContext !== 'consent' || !this.applicantId) {
            return;
        }
        this._guestOtpInitDone = true;
        this._sendGuestConsentOtp();
    }

    disconnectedCallback() {
        this._clearResendTimer();
        if (this._integrationProgressHandler) {
            window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        }
    }

    // ── Integration Progress Modal handlers ───────────────────────────────────
    handleIntegrationProgressUpdate(event) {
        const d = event.detail || {};
        this.showIntegrationProgressModal            = d.show !== false;
        this.integrationProgressModalStatus          = d.status || 'loading';
        this.integrationProgressModalHeader          = d.header || '';
        this.integrationProgressModalCurrentStageIdx = d.currentStageIndex ?? 0;
        this.integrationProgressModalStages          = d.stages || [];
        this.integrationProgressModalErrorMessage    = d.errorMessage || '';
    }

    /* ═══════════════════════════════
       OTP INPUT HANDLERS
    ═══════════════════════════════ */

    handleOtpInput(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = event.target.value.replace(/\D/g, '');
        const next = [...this.otpDigits];
        if (value.length === 1) {
            next[index] = value;
            this.otpDigits = next;
            if (index < 5) {
                const el = this.template.querySelector(`input[data-index="${index + 1}"]`);
                if (el) el.focus();
            }
        }
        else {
            next[index] = '';
            this.otpDigits = next;
            event.target.value = '';
        }
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

    handleVerifyOtp() {
        const otp = this.otpDigits.join('');
        if (otp.length < 6) return;
        if (!this.isTermsAccepted) {
            this.inlineErrorMessage = 'Please accept the Terms & Conditions to continue';
            return;
        }
        this.otpLoading = true;
        this.inlineErrorMessage = '';
        if (this.guestSiteMode && this.otpContext === 'consent') {
            this._verifyGuestConsentOtp(otp);
            return;
        }
        const ctx = getCtx();
        const otpType = this._otpType;
        const actionKey = this.isMobileOtp ? 'contactNumber' : 'email';
        const verificationType = this.otpContext === 'consent' ? 'consent' : otpType;
        const verifyPromise = (this.verifyMode === 'officeAddress')
            ? verifyOfficeOTP({ addressId: this.addressId, otp: otp })
            : verifyOTP({ applicantId: this.applicantId, verificationType, otp: otp });
        verifyPromise
        .then((result) => {
            if(result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: result.message,
                    variant: 'success'
                }));
                _verified = true;
                if (ctx && this.otpContext !== 'consent') {
                    ctx.setActionState(actionKey, 'success');
                }
                this.dispatchEvent(new CustomEvent('otpverified', {
                    detail: { otpType, otp, otpContext: this.otpContext },
                    bubbles: true,
                    composed: true
                }));
                this.dispatchEvent(new CustomEvent('close'));
            }
            else {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: result.message,
                    variant: 'error'
                }));
                this.dispatchEvent(new CustomEvent('otpverificationerror', {
                    detail: { error: result.message },
                    bubbles: true,
                    composed: true
                }));
            }
            this.otpLoading = false;
        })
        .catch((error) => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.message,
                variant: 'error'
            }));
            this.otpLoading = false;
            if (ctx && this.otpContext !== 'consent') {
                ctx.setActionState(actionKey, 'idle');
            }
            this.dispatchEvent(new CustomEvent('otpverificationerror', {
                detail: { error: error.message },
                bubbles: true,
                composed: true
            }));
        });
    }

    async handleResendOtp() {
        if (!this.canResend) return;
        this._startResendTimer();
        this.inlineErrorMessage = '';

        if (this.guestSiteMode && this.otpContext === 'consent') {
            await this._sendGuestConsentOtp();
            return;
        }

        const parentCtx = getCtx() || this;
        const actionKey = this.isMobileOtp ? 'contactNumber' : 'email';
        if (parentCtx?.setActionState) {
            parentCtx.setActionState(actionKey, 'loading');
        }
        try {
            if (this.isMobileOtp) {
                const result = await generatePhoneOTP({ applicantId: this.applicantId, phoneNumber: this.verifyTarget });
                if (!result?.success) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: result?.message || 'Failed to generate OTP.',
                        variant: 'error'
                    }));
                    if (parentCtx?.setActionState) parentCtx.setActionState(actionKey, 'idle');
                    return;
                }
                await invokeHandler('sendPhoneOTPAPI', 'onAction', parentCtx);
            }
            else {
            const result = await generateEmailOTP({ applicantId: this.applicantId, emailAddress: this.verifyTarget });
                if (!result?.success) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: result?.message || 'Failed to generate OTP.',
                        variant: 'error'
                    }));
                    if (parentCtx?.setActionState) parentCtx.setActionState(actionKey, 'idle');
                    return;
                }
                await invokeHandler('sendEmailOTPAPI', 'onAction', parentCtx);
            }
        }
        catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error?.body?.message || error?.message || 'Failed to resend OTP.',
                variant: 'error'
            }));
            if (parentCtx?.setActionState) parentCtx.setActionState(actionKey, 'idle');
        }
    }

    handleTermsChange(event) {
        this.isTermsAccepted = event.target.checked;
    }

    handleTermsClick(event) {
        event.preventDefault();
        // TODO: open terms & conditions page or modal
    }

    @api
    handleClose() {
        if (!_verified && _ctx && _pendingFieldKey && this.otpContext !== 'consent') {
            _ctx.setActionState(_pendingFieldKey, 'idle');
        }
        _ctx = null;
        _pendingFieldKey = null;
        _verified = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    /* ═══════════════════════════════
       PRIVATE HELPERS
    ═══════════════════════════════ */

    _startResendTimer() {
        this.resendTimer = 15;
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

    async _sendGuestConsentOtp() {
        if (!this.applicantId) {
            this.inlineErrorMessage = 'Applicant context is missing.';
            return;
        }
        this.guestOtpSending = true;
        this.inlineErrorMessage = '';
        try {
            const result = await sendApplicationConsentOtp({ applicantId: this.applicantId });
            if (result?.isSuccess) {
                if (result?.consentOtpVerified) {
                    _verified = true;
                    this.dispatchEvent(new CustomEvent('otpverified', {
                        detail: { otpType: 'mobile', otpContext: 'consent' },
                        bubbles: true,
                        composed: true
                    }));
                }
            } else {
                this.inlineErrorMessage = result?.message || 'Failed to send OTP.';
            }
        } catch (error) {
            this.inlineErrorMessage = error?.body?.message || error?.message || 'Failed to send OTP.';
        } finally {
            this.guestOtpSending = false;
        }
    }

    async _verifyGuestConsentOtp(otp) {
        try {
            const result = await verifyApplicationConsentOtp({
                applicantId: this.applicantId,
                otp
            });
            if (result?.isSuccess) {
                _verified = true;
                this.dispatchEvent(new CustomEvent('otpverified', {
                    detail: { otpType: 'mobile', otp, otpContext: 'consent' },
                    bubbles: true,
                    composed: true
                }));
            } else {
                this.inlineErrorMessage = result?.message || 'Invalid OTP.';
            }
        } catch (error) {
            this.inlineErrorMessage = error?.body?.message || error?.message || 'Unable to verify OTP.';
        } finally {
            this.otpLoading = false;
        }
    }
}