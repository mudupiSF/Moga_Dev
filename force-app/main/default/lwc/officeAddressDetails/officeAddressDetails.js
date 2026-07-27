import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCityStateFromPinCode from '@salesforce/apex/GenericUtility.getCityStateFromPinCode';
import generateOfficeOTP from '@salesforce/apex/OfficeEmailOTPController.generateOTP';
import invokeSendOfficeEmailOTPAPI from '@salesforce/apex/OfficeEmailOTPController.invokeSendOfficeEmailOTPAPI';
import { invokeHandler } from 'c/clientLayerHelper';

const EMAIL_REGEX = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i;
const PINCODE_REGEX = /^\d{6}$/;

/**
 * Office Address capture for KYC Section 5. UI mirrors the Vehicle Details
 * layout (stacked editable cards); the email Verify button + post-verify
 * read-only chip mirror the Basic Details pattern. Email Verify dispatches
 * the same `opendynamiccomponentmodal` event used by Basic Details so the
 * shared otpVerification + dynamicComponentModal pair is reused as-is.
 *
 * The parent wires this child via @api setters and consumes change events
 * (officechange / officeemailverify) plus the final getOfficePayload() call
 * at NEXT time.
 */
export default class OfficeAddressDetails extends LightningElement {

    @api recordId;
    @api applicantId;

    /** When true: render the read-only display variant (post-stage). */
    @api forceReadOnly = false;

    @track _addressLine1 = '';
    @track _addressLine2 = '';
    @track _addressLine3 = '';
    @track _pinCode = '';
    @track _city = '';
    @track _state = '';
    @track _country = '';
    @track _email = '';
    @track _emailVerified = false;
    @track _isPincodeLookupRunning = false;
    /** True when city/state were populated by pincode lookup (lock field). */
    _cityAutoFilled = false;
    _stateAutoFilled = false;

    /** Server-supplied snapshot — written once on first paint. */
    _existingApplied = false;
    @api
    get existingOfficeAddressData() {
        return {
            addressLine1: this._addressLine1,
            addressLine2: this._addressLine2,
            addressLine3: this._addressLine3,
            pinCode:      this._pinCode,
            city:         this._city,
            state:        this._state,
            country:      this._country,
            email:        this._email,
            emailVerified: this._emailVerified
        };
    }
    set existingOfficeAddressData(data) {
        if (!data || typeof data !== 'object') return;
        if (this._existingApplied) return;
        this._addressLine1  = data.addressLine1  || '';
        this._addressLine2  = data.addressLine2  || '';
        this._addressLine3  = data.addressLine3  || '';
        this._pinCode       = data.pinCode       || '';
        this._city          = data.city          || '';
        this._state         = data.state         || '';
        this._country       = data.country       || '';
        this._email         = data.email         || '';
        this._emailVerified = data.emailVerified === true;
        this._cityAutoFilled  = !!String(this._city || '').trim();
        this._stateAutoFilled = !!String(this._state || '').trim();
        this._existingApplied = true;
        if (PINCODE_REGEX.test(this._pinCode || '') && (!this._city || !this._state)) {
            this._resolvePinCode(this._pinCode);
        }
    }

    // ── Public API used by the parent on NEXT ────────────────────────────────
    /** Snapshot consumed by wheelsIndividualKYCMasterPage.handleNextButton. */
    @api
    getOfficePayload() {
        return {
            addressLine1:  this._addressLine1,
            addressLine2:  this._addressLine2,
            addressLine3:  this._addressLine3,
            pinCode:       this._pinCode,
            city:          this._city,
            state:         this._state,
            country:       this._country,
            email:         this._email,
            emailVerified: this._emailVerified
        };
    }

    /** Validation entry-point called by the parent on NEXT. */
    @api
    validate() {
        if (this._isPincodeLookupRunning) {
            return { ok: false, message: 'Please wait — looking up city and state for the pin code.' };
        }
        const missing = [];
        if (!this._addressLine1) missing.push('Address Line 1');
        if (!PINCODE_REGEX.test(this._pinCode || '')) missing.push('Pin Code');
        if (!this._city)  missing.push('City');
        if (!this._state) missing.push('State');
        if (!this._email) missing.push('Email');
        else if (!EMAIL_REGEX.test(this._email)) {
            return { ok: false, message: 'Please enter a valid Office Email address.' };
        }
        if (this._email && !this._emailVerified) {
            return { ok: false, message: 'Please verify the Office Email before continuing.' };
        }
        if (missing.length) {
            return {
                ok: false,
                message: `Office Address is incomplete. Missing: ${missing.join(', ')}.`
            };
        }
        return { ok: true };
    }

    // ── Field getters ───────────────────────────────────────────────────────
    get addressLine1() { return this._addressLine1; }
    get addressLine2() { return this._addressLine2; }
    get addressLine3() { return this._addressLine3; }
    get pinCode()      { return this._pinCode; }
    get city()         { return this._city; }
    get state()        { return this._state; }
    get email()        { return this._email; }
    get emailVerified() { return this._emailVerified; }

    get isReadOnlyScreen() { return this.forceReadOnly === true; }
    get isPincodeBusy() { return this._isPincodeLookupRunning; }
    get isCityReadOnly() {
        return this.isReadOnlyScreen || this.isPincodeBusy || this._cityAutoFilled;
    }
    get isStateReadOnly() {
        return this.isReadOnlyScreen || this.isPincodeBusy || this._stateAutoFilled;
    }
    get cityInputClass() {
        return 'office-input' + (this.isCityReadOnly ? ' office-input--readonly' : '');
    }
    get stateInputClass() {
        return 'office-input' + (this.isStateReadOnly ? ' office-input--readonly' : '');
    }

    get isEmailFormatInvalid() {
        return !!this._email && !EMAIL_REGEX.test(this._email);
    }
    get emailValidationError() {
        return this.isEmailFormatInvalid ? 'Enter a valid email address' : '';
    }

    // ── Verify button computed state (mirrors Basic Details pattern) ────────
    get _emailActionState() { return this._contactActionStates?.email || 'idle'; }
    get emailVerifyLoading() { return this._emailActionState === 'loading'; }
    get emailVerifyLabel() {
        if (this._emailVerified) return 'Verified';
        return this.emailVerifyLoading ? '...' : 'Verify';
    }
    get emailVerifyActionBtnClass() {
        return this._emailVerified
            ? 'office-action-btn office-action-btn--verified'
            : 'office-action-btn';
    }
    get emailVerifyDisabled() {
        return this.isReadOnlyScreen
            || this._emailVerified
            || this.emailVerifyLoading
            || !EMAIL_REGEX.test(this._email || '');
    }
    get emailVerifyInfoLabelClass() {
        return this._emailVerified
            ? 'office-info-action-label office-info-action-label--verified'
            : 'office-info-action-label';
    }

    // ── ctx interface required by otpVerification.onLoad('onAction', ctx) ──
    // The shared otpVerification module reads ctx._lastActionFieldKey and
    // ctx.contactInfoFieldValues.email, then dispatches
    // opendynamiccomponentmodal on ctx. We expose the minimum surface needed.
    _lastActionFieldKey = '';
    @track _contactActionStates = {};
    documentVerificationFieldValues = { isPanAvailable: 'Yes' };

    // Office-email OTP verifies against the Office Applicant_Address__c row
    // (not Applicant__c). otpVerification reads these off ctx and threads them
    // into the modal so verify runs OfficeEmailOTPController.verifyOTP.
    otpVerifyMode = 'officeAddress';
    officeAddressId = null;
    get contactInfoFieldValues() {
        return { email: this._email, contactNumber: '' };
    }
    setActionState(key, state) {
        if (key !== 'email') return;
        this._contactActionStates = { ...this._contactActionStates, email: state };
        if (state === 'success') {
            this._emailVerified = true;
            this._emitChange();
            this._emitEmailVerified();
        }
    }
    updateFieldValue(key, value) {
        if (key === 'email') {
            this._email = value || '';
            this._emitChange();
        }
    }

    // ── Field input handlers ────────────────────────────────────────────────
    handleAddressLine1Input(event) {
        if (this.isReadOnlyScreen) return;
        this._addressLine1 = event.target.value || '';
        this._emitChange();
    }
    handleAddressLine2Input(event) {
        if (this.isReadOnlyScreen) return;
        this._addressLine2 = event.target.value || '';
        this._emitChange();
    }
    handleAddressLine3Input(event) {
        if (this.isReadOnlyScreen) return;
        this._addressLine3 = event.target.value || '';
        this._emitChange();
    }

    handlePinCodeInput(event) {
        if (this.isReadOnlyScreen) return;
        const next = (event.target.value || '').replace(/\D/g, '').slice(0, 6);
        event.target.value = next;
        this._pinCode = next;
        // Re-typing the pincode invalidates the prior auto-fill so the user
        // sees a fresh blank city/state until the new lookup resolves.
        this._city = '';
        this._state = '';
        this._country = '';
        this._cityAutoFilled = false;
        this._stateAutoFilled = false;
        this._emitChange();
        if (PINCODE_REGEX.test(next)) {
            this._resolvePinCode(next);
        }
    }

    handleCityInput(event) {
        if (this.isReadOnlyScreen || this._cityAutoFilled) return;
        this._city = event.target.value || '';
        this._emitChange();
    }

    handleStateInput(event) {
        if (this.isReadOnlyScreen || this._stateAutoFilled) return;
        this._state = event.target.value || '';
        this._emitChange();
    }

    handleEmailInput(event) {
        if (this.isReadOnlyScreen) return;
        const next = event.target.value || '';
        this._email = next;
        if (this._emailVerified) {
            // Manual edit invalidates a prior verification.
            this._emailVerified = false;
            this._contactActionStates = { ...this._contactActionStates, email: 'idle' };
            this._emitEmailVerified();
        }
        this._emitChange();
    }

    async handleEmailVerifyClick(event) {
        event?.preventDefault?.();
        event?.stopPropagation?.();
        if (this.emailVerifyDisabled) return;
        this._contactActionStates = { ...this._contactActionStates, email: 'loading' };
        this._lastActionFieldKey = 'email';
        try {
            // Generate + persist the OTP on the Office address row first
            // (mirrors Basic Details generate -> send -> open modal).
            const result = await generateOfficeOTP({
                applicantId: this.applicantId,
                emailAddress: this._email
            });
            if (!result || !result.success) {
                this._contactActionStates = { ...this._contactActionStates, email: 'idle' };
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: (result && result.message) || 'Failed to generate OTP.',
                    variant: 'error'
                }));
                return;
            }
            this.officeAddressId = result.addressId;
            this.otpVerifyMode = 'officeAddress';
            console.log('[OfficeEmailOTP] Generated OTP:', result?.otpCode || '');
            // Best-effort delivery — don't block the modal if the gateway /
            // integration master is not configured in this org.
            try {
                await invokeSendOfficeEmailOTPAPI({ addressId: result.addressId });
            } catch (sendError) {
                // Swallow: code is already generated; verification can proceed.
            }
            invokeHandler('otpVerification', 'onAction', this);
        } catch (error) {
            this._contactActionStates = { ...this._contactActionStates, email: 'idle' };
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error?.body?.message || error?.message || 'Failed to generate OTP.',
                variant: 'error'
            }));
        }
    }

    // ── Pincode → City / State auto-fill ────────────────────────────────────
    _resolvePinCode(pin) {
        this._isPincodeLookupRunning = true;
        getCityStateFromPinCode({ pinCode: pin })
            .then((result) => {
                const data = result || {};
                const city  = String(data.city  || '').trim();
                const state = String(data.state || '').trim();
                if (city) {
                    this._city = city;
                    this._cityAutoFilled = true;
                }
                if (state) {
                    this._state = state;
                    this._stateAutoFilled = true;
                }
                this._country = data.country || '';
                this._emitChange();
            })
            .catch(() => {
                // Lookup failed — city/state stay editable for manual entry.
            })
            .finally(() => {
                this._isPincodeLookupRunning = false;
            });
    }

    // ── Change events bubbling to the parent ────────────────────────────────
    _emitChange() {
        this.dispatchEvent(new CustomEvent('officechange', {
            detail: this.getOfficePayload(),
            bubbles: true,
            composed: true
        }));
    }
    _emitEmailVerified() {
        this.dispatchEvent(new CustomEvent('officeemailverify', {
            detail: { emailVerified: this._emailVerified },
            bubbles: true,
            composed: true
        }));
    }
}