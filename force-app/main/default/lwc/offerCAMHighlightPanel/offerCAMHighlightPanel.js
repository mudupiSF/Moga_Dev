import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHighlightPanelData from '@salesforce/apex/OfferPageController.getHighlightPanelData';
import getCustomerFormUrl from '@salesforce/apex/CustomerFormController.getCustomerFormUrl';
import generateEmailOTP from '@salesforce/apex/SendEmailOTPAPIController.generateOTP';
import { invokeHandler } from 'c/clientLayerHelper';

const INTEGRATION_PROGRESS_EVENT = 'integrationprogressupdate';
const APPLICATION_FORM = 'Application_Form';
const INSURANCE_FORM = 'Insurance_Form';

export default class OfferCAMHighlightPanel extends LightningElement {

    @api recordId;
   
    @track customerFormName = APPLICATION_FORM;

    @track currentUserRoleName    = '';
    @track allApplicants          = [];
    @track activeSection          = 'borrower';
    @track activeGuarantorIndex   = 0;
    @track activeBeneficiaryIndex = 0;

    @track borrowerApplicant     = null;
    @track guarantorApplicants   = [];
    @track beneficiaryApplicants = [];

    @track showPdfRenderModal       = false;
    @track pdfRenderDocumentChecklistId = null;
    pdfRenderModalHeader            = 'Test App Form';
    _pdfRenderInputJson = {
        Applicant_Name: 'Rajesh Kumar Sharma',
        DOB: '15-Aug-1988',
        PAN: 'ABCDE1234F',
        AADHAAR: 'XXXX-XXXX-4321',
        Mobile: '9876543210',
        Email: 'rajesh.sharma@email.com',
        Address: '12 Shivaji Nagar, Near Post Office',
        City: 'Pune',
        State: 'Maharashtra',
        CoApplicant_Name: 'Priya Sharma',
        Relationship: 'Spouse',
        CoApplicant_Mobile: '9876511111',
        Employment_Type: 'Salaried',
        Employer_Name: 'ABC Technologies Pvt Ltd',
        Monthly_Income: '45000',
        Annual_Income: '540000',
        Bank_Name: 'Bandhan Bank',
        Account_Number: '123456789012',
        IFSC_Code: 'BDBL0001234',
        Vehicle_Model: 'Tata Nexon EV',
        Vehicle_Model_2: 'Mahindra XUV 3XO',
        Loan_Amount: '1200000',
        Loan_Amount_2: '1400000',
        Tenure: '60 Months',
        Tenure_2: '72 Months',
        ROI: '9.25%',
        ROI_2: '9.75%'
    };

    _pendingEmailApplicantId = '';
    _pendingEmailAddress     = '';
    _lastActionFieldKey      = '';
    _offerAccepted           = false;
    _integrationProgressHandler = null;
    _integrationRetryFn         = null;

    @track showIntegrationModal         = false;
    @track integrationStatus            = 'loading';
    @track integrationCurrentStageIndex = 0;
    @track integrationSuccessMessage    = '';
    @track integrationErrorMessage      = '';
    @track integrationStages            = [];

    initialData   = {};
    highPanelData = {};

    pendingIcon  = 'utility:clock';
    rejectedIcon = 'utility:error';

    highlightPanelIcon = {
        insConsent:      'utility:shield',
        appsFormConsent: 'utility:form',
        kfs:             'utility:success',
        personalEmail:   'utility:email',
        ekyc:            'utility:slack_user'
    };

    // ── API: offerAccepted ────────────────────────────────────────────────
    @api
    set offerAccepted(value) {
        this._offerAccepted = !!value;
        if (this.allApplicants.length > 0) {
            this.buildAllApplicants();
        }
    }
    get offerAccepted() {
        return this._offerAccepted;
    }

    // ── API: highlightPanelData ───────────────────────────────────────────
    @api
    set highlightPanelData(value) {
        if (value) {
            this.highPanelData = value;
            this.recordId = value.recordId;
        }
    }
    get highlightPanelData() {
        return this.highPanelData;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────
    connectedCallback() {
        this._integrationProgressHandler = (event) => this.handleIntegrationProgressUpdate(event);
        window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        this._loadData();
    }

    disconnectedCallback() {
        if (this._integrationProgressHandler) {
            window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
            this._integrationProgressHandler = null;
        }
    }

    async _loadData() {
        try {
            const result = await getHighlightPanelData({ applicationId: this.recordId });
            if (result && result.success) {
                this.initialData = {
                    applicants: result.applicants || [],
                    statusKFS:  result.statusKFS  || 'Pending',
                };
                this.currentUserRoleName = result.teamMemberRole || '';
            }
        } catch (error) {
            console.error('getHighlightPanelData failed:', error);
        }
        this.buildAllApplicants();
    }

    // ── Tab getters ───────────────────────────────────────────────────────
    get activeApplicant() {
        if (this.activeSection === 'borrower')    return this.borrowerApplicant;
        if (this.activeSection === 'guarantor')   return this.guarantorApplicants[this.activeGuarantorIndex]   || null;
        if (this.activeSection === 'beneficiary') return this.beneficiaryApplicants[this.activeBeneficiaryIndex] || null;
        return null;
    }

    get hasGuarantors()    { return this.guarantorApplicants.length > 0; }
    get hasBeneficiaries() { return this.beneficiaryApplicants.length > 0; }

    get activeGuarantorApplicant() {
        return this.guarantorApplicants[this.activeGuarantorIndex] || null;
    }

    get activeBeneficiaryApplicant() {
        return this.beneficiaryApplicants[this.activeBeneficiaryIndex] || null;
    }

    get guarantorOptions() {
        return this.guarantorApplicants.map(a => ({ label: a.displayLabel, value: a.id }));
    }

    get beneficiaryOptions() {
        return this.beneficiaryApplicants.map(a => ({ label: a.displayLabel, value: a.id }));
    }

    get guarantorValue() {
        return (this.guarantorApplicants[this.activeGuarantorIndex] || {}).id || '';
    }

    get beneficiaryValue() {
        return (this.beneficiaryApplicants[this.activeBeneficiaryIndex] || {}).id || '';
    }

    get borrowerTabClass() {
        return 'applicant-tab' + (this.activeSection === 'borrower' ? ' applicant-tab-active' : '');
    }
    get guarantorTabClass() {
        return 'applicant-tab applicant-tab-combo' + (this.activeSection === 'guarantor' ? ' applicant-tab-active' : '');
    }
    get beneficiaryTabClass() {
        return 'applicant-tab applicant-tab-combo' + (this.activeSection === 'beneficiary' ? ' applicant-tab-active' : '');
    }

    get isAllowedUserRole() {
        return ['BE', 'CVO', 'MA', 'MO'].includes(this.currentUserRoleName);
    }

    // ── Tab interaction ───────────────────────────────────────────────────
    handleSectionSwitch(event) {
        this.activeSection = event.currentTarget.dataset.section;
    }

    handleGuarantorChange(event) {
        event.stopPropagation();
        this.activeSection = 'guarantor';
        const id  = event.detail.value;
        const idx = this.guarantorApplicants.findIndex(a => a.id === id);
        this.activeGuarantorIndex = idx >= 0 ? idx : 0;
    }

    handleBeneficiaryChange(event) {
        event.stopPropagation();
        this.activeSection = 'beneficiary';
        const id  = event.detail.value;
        const idx = this.beneficiaryApplicants.findIndex(a => a.id === id);
        this.activeBeneficiaryIndex = idx >= 0 ? idx : 0;
    }

    // ── Build applicant list ──────────────────────────────────────────────
    buildAllApplicants() {
        // When offer is accepted: pending chips turn blue and become clickable.
        // When not accepted: pending chips are yellow and non-interactive.
        const clickable  = this._offerAccepted;
        const applicants = this.initialData.applicants || [];

        // Counters kept outside map so they accumulate across iterations
        let gIdx = 0;
        let bIdx = 0;

        this.allApplicants = applicants.map(app => {
            const rawType       = (app.applicantType || '').toLowerCase();
            const isBorrower    = rawType === 'borrower';
            const isBeneficiary = rawType === 'beneficiary';

            // Increment the appropriate counter BEFORE computing display values
            if (!isBorrower && isBeneficiary)  bIdx += 1;
            if (!isBorrower && !isBeneficiary) gIdx += 1;

            // All computed as const — no reassignment
            const displayType    = isBorrower ? 'borrower' : (isBeneficiary ? 'b' + bIdx : 'g' + gIdx);
            const displayLabel   = isBorrower ? 'Borrower' : (isBeneficiary ? 'B' + bIdx : 'G' + gIdx);
            const typeBadgeClass = isBorrower
                ? 'type-badge type-badge-borrower'
                : 'type-badge type-badge-coborrower';
            const name = isBorrower
                ? ((app.customerFullName || '').trim() || displayLabel)
                : (app.applicantName || displayLabel);

            let initials = '';
            if(isBorrower){
                initials = name.split(' ').filter(Boolean).map(w => w[0]).join('').substring(0, 2).toUpperCase();
            }else if(isBeneficiary){
                initials = 'B';
            }else{
                initials = 'G';
            }

            // Personal Email: Validated (green) or Pending.
            // Pending → blue when offer accepted; yellow otherwise. Never cursor-pointer when not clickable.
            const emailStatus      = app.emailVerified ? 'Validated' : 'Pending';
            const emailChip        = this._buildChip(emailStatus, 'personalEmail', clickable);
            const personalEmailClass = (emailStatus === 'Pending' && clickable)
                ? emailChip.cssClass + ' chip-clickable'
                : emailChip.cssClass;

            if (!isBorrower) {
                return {
                    id: app.id, name, initials, displayType, displayLabel, typeBadgeClass,
                    isBorrower: false,
                    email: app.email || '',
                    panelData: { personalEmail: emailChip },
                    personalEmailClass,
                };
            }

            // Borrower tiles — all pending by default, all turn blue + clickable after offer acceptance
            const insStatus  = app.insuranceConsentReceived   ? 'Accepted'  : 'Pending';
            const appStatus  = app.applicationConsentReceived ? 'Accepted'  : 'Pending';
            const kfsStatus  = this.initialData.statusKFS     || 'Pending';
            const ekycStatus = app.eKYCAccepted               ? 'Validated' : 'Pending';

            const insChip  = this._buildChip(insStatus,  'insConsent',      clickable);
            const appChip  = this._buildChip(appStatus,  'appsFormConsent', clickable);
            const kfsChip  = this._buildChip(kfsStatus,  'kfs',             clickable);
            const ekycChip = this._buildChip(ekycStatus, 'ekyc',            clickable);

            // chip-clickable (cursor:pointer) only on tiles that have click handlers
            const insConsentClass = (insChip.status === 'Pending' && clickable)
                ? insChip.cssClass + ' chip-clickable'
                : insChip.cssClass;
            const appFormClass = (appChip.status === 'Pending' && clickable)
                ? appChip.cssClass + ' chip-clickable'
                : appChip.cssClass;

            return {
                id: app.id, name, initials, displayType, displayLabel, typeBadgeClass,
                isBorrower: true,
                email: app.email || '',
                panelData: { insConsent: insChip, appsFormConsent: appChip, personalEmail: emailChip, kfs: kfsChip, ekyc: ekycChip },
                personalEmailClass,
                insConsentClass,
                appFormClass,
            };
        });

        this._syncApplicantGroups();
    }

    _syncApplicantGroups() {
        this.borrowerApplicant     = this.allApplicants.find(a => a.isBorrower) || null;
        this.guarantorApplicants   = this.allApplicants.filter(a => !a.isBorrower && a.displayType.startsWith('g'));
        this.beneficiaryApplicants = this.allApplicants.filter(a => !a.isBorrower && a.displayType.startsWith('b'));
    }

    // Builds a chip. Pending is yellow by default; blue when offerAccepted=true (actionable state).
    _buildChip(status, key, offerAccepted) {
        if (status === 'Accepted' || status === 'Validated') {
            return { status, iconName: this.highlightPanelIcon[key], cssClass: 'highlight-panel-element highlight-panel-green',  iconCss: 'icon-green'  };
        }
        if (status === 'Rejected') {
            return { status, iconName: this.rejectedIcon,            cssClass: 'highlight-panel-element highlight-panel-orange', iconCss: 'icon-orange' };
        }
        if (offerAccepted) {
            return { status, iconName: this.pendingIcon,             cssClass: 'highlight-panel-element highlight-panel-blue',   iconCss: 'icon-blue'   };
        }
        return     { status, iconName: this.pendingIcon,             cssClass: 'highlight-panel-element highlight-panel-yellow', iconCss: 'icon-yellow' };
    }

    // ── Chip click handlers ───────────────────────────────────────────────
    async handleInsConsentClick() {
        if (!this._offerAccepted) return;
        const app = this.activeApplicant;
        if (!app || app.panelData.insConsent.status !== 'Pending') return;
        this.customerFormName = INSURANCE_FORM;
        await this.openCustomerForm();
    }

    async handleAppConsentClick() {
        if (!this._offerAccepted) return;
        const app = this.activeApplicant;
        if (!app || app.panelData.appsFormConsent.status !== 'Pending') return;
        const applicantId = app.id || app.Id;
        if (!applicantId) {
            this.showToast('Error', 'Applicant record is required.', 'error');
            return;
        }
        this.customerFormName = APPLICATION_FORM;
        await this.openCustomerForm();
    }

    async openCustomerForm(){
        try {
            const applicantId = this.activeApplicant?.id || this.activeApplicant?.Id || null;
            console.log('appid '+applicantId);
            const url = await getCustomerFormUrl({
                applicantId,
                formName: this.customerFormName || APPLICATION_FORM
            });
            window.open(url, '_blank');
        } catch (error) {
            this.showToast(
                'Error',
                error?.body?.message || error?.message || `Unable to open ${this.customerFormName}.`,
                'error'
            );
        }
    }

    // ── Email OTP (same flow as contact mobile OTP) ───────────────────────
    get applicantId() {
        return this._pendingEmailApplicantId;
    }

    get emailAddress() {
        return this._pendingEmailAddress;
    }

    get contactInfoFieldValues() {
        return { email: this._pendingEmailAddress };
    }

    updateFieldValue(field, value) {
        if (field === 'emailOTPErrorMessage' && value) {
            this.showToast('Error', value, 'error');
            this.integrationStatus = 'error';
            this.integrationErrorMessage = value;
            this.showIntegrationModal = true;
        }
    }

    setActionState(actionKey, status) {
        if (actionKey === 'email' && status === 'success') {
            this._applyEmailVerifiedChip(this._pendingEmailApplicantId);
            this._resetEmailOtpFlow();
        }
    }

    @api
    cancelEmailOtpFlow() {
        this._resetEmailOtpFlow();
    }

    _resetEmailOtpFlow() {
        this._pendingEmailApplicantId = '';
        this._pendingEmailAddress     = '';
        this._lastActionFieldKey      = '';
        this.showIntegrationModal     = false;
        this._integrationRetryFn       = null;
    }

    _applyEmailVerifiedChip(applicantId) {
        if (!applicantId) return;
        const validatedChip = this._buildChip('Validated', 'personalEmail', false);
        this.allApplicants = this.allApplicants.map((app) => {
            if (app.id !== applicantId) return app;
            return {
                ...app,
                panelData:          { ...app.panelData, personalEmail: validatedChip },
                personalEmailClass: validatedChip.cssClass
            };
        });
        this._syncApplicantGroups();
    }

    async handlePersonalEmailClick() {
        if (!this._offerAccepted) return;
        const app = this.activeApplicant;
        if (!app || app.panelData.personalEmail.status !== 'Pending') return;

        const email = (app.email || '').trim();
        if (!email) {
            this.showToast(
                'Email Not Found',
                'Personal email is not available for this applicant.',
                'warning'
            );
            return;
        }

        this._pendingEmailApplicantId = app.id;
        this._pendingEmailAddress     = email;
        this._lastActionFieldKey      = 'email';

        try {
            this._openIntegrationModal(
                ['Generating Email OTP', 'Sending Email OTP'],
                () => this.handlePersonalEmailClick()
            );

            const result = await generateEmailOTP({
                applicantId: app.id,
                emailAddress: email
            });
            if (!result?.success) {
                const message = result?.message || 'Failed to generate OTP.';
                this.showToast('Error', message, 'error');
                this.integrationStatus = 'error';
                this.integrationErrorMessage = message;
                return;
            }

            this.integrationCurrentStageIndex = 1;
            await invokeHandler('sendEmailOTPAPI', 'onAction', this);
            this.showIntegrationModal = false;
            await invokeHandler('otpVerification', 'onAction', this);
        } catch (error) {
            console.error('[OfferCAMHighlightPanel] email OTP failed:', error);
            const message = error?.body?.message || error?.message || 'Failed to send email OTP.';
            this.showToast('Error', message, 'error');
            this.integrationStatus = 'error';
            this.integrationErrorMessage = message;
        }
    }

    handleIntegrationProgressUpdate(event) {
        if (!this._pendingEmailApplicantId) return;

        const detail = event.detail || {};
        if (detail.show === false) {
            this.showIntegrationModal = false;
            return;
        }

        this.showIntegrationModal = true;
        this.integrationStatus = detail.status || 'loading';
        this.integrationCurrentStageIndex = detail.currentStageIndex ?? this.integrationCurrentStageIndex;
        if (detail.stages?.length) {
            this.integrationStages = detail.stages;
        }
        this.integrationErrorMessage = detail.errorMessage || '';
    }

    handleIntegrationModalClose() {
        this.showIntegrationModal = false;
        if (this.integrationStatus === 'error') {
            this._resetEmailOtpFlow();
        }
    }

    handleIntegrationRetry() {
        this.integrationStatus = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.integrationErrorMessage = '';
        if (this._integrationRetryFn) {
            this._integrationRetryFn();
        }
    }

    _openIntegrationModal(stages, retryFn) {
        this.integrationStages = stages;
        this.integrationStatus = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.integrationSuccessMessage = '';
        this.integrationErrorMessage = '';
        this._integrationRetryFn = retryFn;
        this.showIntegrationModal = true;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

}