import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';
import processCustomerDedupeNextRequest from '@salesforce/apex/CustomerDedupeNavigationOverride.processCustomerDedupeNextRequest';
import routeToRoleGrid from '@salesforce/apex/dynamicStageNavigatorController.routeToRoleGrid';
import getMenuForPortfolio from '@salesforce/apex/dynamicStageNavigatorController.getMenuForPortfolio';
import validateNiConstitutionForApplication from '@salesforce/apex/CustomerDedupeController.validateNiConstitutionForApplication';
import {
    buildCheckEligibilityStagePlan,
    getCheckEligibilityStageLabels,
    buildDedupeForwardStagePlan,
    getDedupeForwardStageLabels,
    isDedupeForwardStageLabels
} from './checkEligibilityIntegrationConfig';

const LOS_MENU_REFRESH_EVENT = 'losmenurefresh';
const LOS_NAVIGATION_STATE_EVENT = 'losnavigationstate';
const LOS_MENU_SELECT_EVENT = 'losmenuselect';
const LOS_NEXT_STAGE_EVENT = 'losnextstage';

const APEX_CLASS = 'CustomerDedupeController';
const APEX_METHOD_GET_PAGE_DATA = 'getPageData';
const APEX_METHOD_SAVE_APPLICANT = 'saveApplicantSelections';
const APEX_METHOD_REMOVE_APPLICANT = 'removeApplicant';
const APEX_METHOD_VALIDATE_ALL_APPLICANTS = 'validateAllApplicantsDedupeComplete';

const GET_EMI_API_STAGES = ['Getting existing EMI...'];
const APEX_METHOD_RUN_ELIGIBILITY_STAGE = 'runCheckEligibilityIntegrationStage';
const APEX_METHOD_RUN_DEDUPE_FORWARD_STAGE = 'runDedupeForwardIntegrationStage';
const NEXT_BUTTON_STAGE_MIN_DURATION_MS = 3000;
const INTEGRATION_MODAL_CLOSE_DELAY_MS = 800;
const DEDUPE_STEP_NAME = 'Dedupe and Eligibility';

export default class CustomerDedupeMasterPage extends LightningElement {
    /** Replay when lwc:component mounts after losmenuselect (same pattern as vehicleDetails). */
    static _lastMenuDetail = null;
    static _lastMenuRecordId = null;

    @api recordId;
    @api currentViewId;
    @api stagePhrase = '';
    @api tab = '';
    @api applicantType = '';
    @api currentApplicantTabLabel = 'Borrower';

    _applicantId;
    _menuNavApplicantId = '';
    _menuNavApplicantType = '';
    _menuSelectHandler;

    @api
    get applicantId() {
        return this._applicantId;
    }
    set applicantId(value) {
        const normalized = value || null;
        console.log('normalized' + normalized);
        console.log('this._applicantId' + this._applicantId);
        if (normalized !== this._applicantId) {
            this._applicantId = normalized;
            this.resetApplicantTabUiState();
            this.loadPageData();
        }
    }

    resetApplicantTabUiState() {
        this.customerCode = '';
        this.matchConfirmedInvalid = false;
        this.invalidatedMatchCifId = '';
        this.matchValidated = false;
        this.validInvalidClicked = false;
        this.getEmiClicked = false;
        this.hasAnyRowValidated = false;
        this.applicantHasCustomerCode = false;
        this.isCustomerDedupeCompleteForApplicant = false;
        this.isApplicantLoanStagePastDedupe = false;
        this.isApplicationPastDedupeStep = false;
    }
    _isStagePast = false
    @api
    set isStagePast(value) {
      this._isStagePast = value === true || value === 'true';
    }
    get isStagePast() {
      return this._isStagePast
    }
   
    /**
     * Co-applicant tabs: editable until dedupe + EMI complete on that tab.
     * Borrower: readonly only when menu past view and step truly complete.
     */
    /** Applicant tab label — not the step submenu name carried in `tab`. */
    get activeApplicantTabLabel() {
        return (
            this.currentApplicantTabLabel
            || this._menuNavApplicantType
            || this.applicantType
            || ''
        ).trim();
    }

    /** True only on the Borrower left-nav tab (not G1, CoBo1, etc.). */
    get isBorrowerTabActive() {
        if (this.isBorrowerScreen) {
            return true;
        }
        const label = this.activeApplicantTabLabel.toLowerCase();
        return label === 'borrower';
    }

    /** User navigated back to a green/completed step in the sidebar. */
    get isViewingCompletedPastStage() {
        return this.isStagePast === true;
    }

    /** Borrower dedupe screen is view-only (green sidebar or application stage past dedupe). */
    get isBorrowerDedupeReadOnly() {
        return this.isBorrowerScreen
            && (this.isStagePast || this.isApplicationPastDedupeStep);
    }

    get isReadOnlyScreen() {
        if (!this.isBorrowerTabActive) {
            return this.isCustomerDedupeCompleteForApplicant || this.isViewingCompletedPastStage;
        }
        return this.isBorrowerDedupeReadOnly;
    }

    @track matches = [];
    @track canAddGuarantor = false;
    @track canAddBeneficiary = false;
    @track removableApplicants = [];
    @track applicationType = '';
    @track isNonIndividual = false;
    @track isCurrentApplicantNonIndividual = false;
    @track isTwoWheeler = false;
    @track isBorrowerScreen = false;
    @track lockCurrentApplicantDedupe = false;
    @track customerCode = '';
    @track matchConfirmedInvalid = false;
    @track invalidatedMatchCifId = '';
    @track isLoading = true;
    @track isSaving = false;
    @track isNextNavigationInProgress = false;

    @track hasApplicantsNotAtCustomerDedupe = false;
    @track hasAdditionalApplicantsPendingPriorStages = false;
    @track pendingPriorStageApplicantLabels = [];
    @track requiresBorrowerCombinedEligibilityRecheck = false;
    @track eligibilityRecheckApplicantTabLabel = '';
    @track eligibilityRecheckApplicantIsNonIndividual = false;
    @track hasOtherApplicantsOfSameTypeNotAtStage = false;
    @track hasOtherApplicantsReachedCustomerDedupe = false;
    @track applicantHasCustomerCode = false;
    @track isCustomerDedupeCompleteForApplicant = false;
    @track canAddMoreApplicants = true;
    @track stageIsComplete = false;
    @track isApplicantLoanStagePastDedupe = false;
    @track isApplicationPastDedupeStep = false;
    @track hasAnyRowValidated = false;
    @track borrowerAddGuarantorSelection = 'No';
    @track borrowerAddBeneficiarySelection = 'No';
    // "+ Add Sub-<Role>" selections + whether an NI of each role exists
    @track borrowerAddSubGuarantorSelection = 'No';
    @track borrowerAddSubBeneficiarySelection = 'No';
    @track hasNonIndividualGuarantor = false;
    @track hasNonIndividualBeneficiary = false;
    @track guarantorCount = 0;
    @track coBorrowerCount = 0;
    @track beneficiaryCount = 0;
    @track applicantEntityType = '';
    @track productType = '';
    @track _baseCanAddGuarantor = false;
    @track _baseCanAddBeneficiary = false;

    showConfirmModal = false;
    confirmModalProps = {};
    _confirmModalContext = null;
    _pendingRemoveApplicantId = null;
    
    @track matchValidated = false;
    @track eligibilityChecked = false;
    @track checkEligibilityClicked = false;
    @track checkEligibilityProcessing = false;
    @track validInvalidClicked = false;
    @track getEmiClicked = false;

    // Integration progress modal state
    showIntegrationProgressModal = false;
    integrationProgressModalStatus = 'loading';
    integrationProgressModalCurrentStageIndex = 0;
    integrationProgressModalStages = [];
    integrationProgressModalErrorMessage = '';
    integrationProgressModalSuccessMessage = '';
    integrationProgressModalHeader = '';

    _integrationProgressHandler;

    connectedCallback() {
        this._menuSelectHandler = this._handleMenuSelectForNav.bind(this);
        window.addEventListener(LOS_MENU_SELECT_EVENT, this._menuSelectHandler);
        if (CustomerDedupeMasterPage._lastMenuDetail) {
            const cachedDetail = CustomerDedupeMasterPage._lastMenuDetail;
            const isSameRecord = !CustomerDedupeMasterPage._lastMenuRecordId
                || CustomerDedupeMasterPage._lastMenuRecordId === this.recordId;
            if (
                isSameRecord
                && (cachedDetail.overrideLwc || '').trim() === 'customerDedupeMasterPage'
            ) {
                this._applyMenuNavFromDetail(cachedDetail);
            }
        }

        this.loadPageData();

        this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e);
        window.addEventListener('integrationprogressupdate', this._integrationProgressHandler);

        // checkeligibility is handled via template binding (oncheckeligibility) and footer action.
        // Avoid a global window listener here to prevent stale component instances from invoking
        // eligibility with outdated applicant context.
    }

    disconnectedCallback() {
        if (this._menuSelectHandler) {
            window.removeEventListener(LOS_MENU_SELECT_EVENT, this._menuSelectHandler);
        }
        if (this._integrationProgressHandler) {
            window.removeEventListener('integrationprogressupdate', this._integrationProgressHandler);
        }
    }

    _handleMenuSelectForNav(event) {
        const detail = event?.detail || {};
        const overrideLwc = (detail.overrideLwc || '').trim();
        if (overrideLwc && overrideLwc !== 'customerDedupeMasterPage') {
            return;
        }
        CustomerDedupeMasterPage._lastMenuDetail = detail;
        CustomerDedupeMasterPage._lastMenuRecordId = this.recordId || null;
        this._applyMenuNavFromDetail(detail);

        const nextApplicantId = detail.applicantId || null;
        if (nextApplicantId !== this._applicantId) {
            this.applicantId = nextApplicantId;
            return;
        }
        this.loadPageData({ silent: true });
    }

    _applyMenuNavFromDetail(detail = {}) {
        this._menuNavApplicantId = detail.applicantId || '';
        this._menuNavApplicantType = detail.applicantType || '';
        if (this._menuNavApplicantType) {
            this.currentApplicantTabLabel = this._menuNavApplicantType;
        }
    }

    _resolveApplicantIdForLoad() {
        return (
            this._applicantId
            || this._menuNavApplicantId
            || null
        );
    }

    async loadPageData(options = {}) {
        const silent = options.silent === true;
        if (!this.recordId) {
            this.isLoading = false;
            return;
        }

        if (!silent) {
        this.isLoading = true;
        }
        try {
            const result = await getPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_GET_PAGE_DATA,
                recordId: this.recordId,
                params: { applicantId: this._resolveApplicantIdForLoad() }
            });

            if (result && result.isSuccess) {
                this.matches = result.matches || [];
                this.canAddGuarantor = result.canAddGuarantor || false;
                this.canAddBeneficiary = result.canAddBeneficiary || false;
                this._baseCanAddGuarantor = this.canAddGuarantor;
                this._baseCanAddBeneficiary = this.canAddBeneficiary;
                this.removableApplicants = [...(result.removableApplicants || [])];
                this._applicantId = result.currentApplicantId || '';
                this.applicationType = result.applicationType || '';
                this.isNonIndividual = result.isNonIndividual || false;
                this.isCurrentApplicantNonIndividual = result.isCurrentApplicantNonIndividual === true;
                this.isTwoWheeler = result.isTwoWheeler || false;
                if (result.currentApplicantTabLabel) {
                    this.currentApplicantTabLabel = result.currentApplicantTabLabel;
                } else if (this._menuNavApplicantType || this.applicantType) {
                    this.currentApplicantTabLabel = this._menuNavApplicantType || this.applicantType;
                }
                this.isBorrowerScreen = result.isBorrowerScreen === true;
                if (!this.isBorrowerScreen) {
                    this.canAddGuarantor = false;
                    this.canAddBeneficiary = false;
                }
                this.lockCurrentApplicantDedupe = result.lockCurrentApplicantDedupe === true;
                this.hasApplicantsNotAtCustomerDedupe = !!result.hasApplicantsNotAtCustomerDedupe;
                this.hasAdditionalApplicantsPendingPriorStages =
                    !!result.hasAdditionalApplicantsPendingPriorStages;
                this.pendingPriorStageApplicantLabels = Array.isArray(result.pendingPriorStageApplicantLabels)
                    ? [...result.pendingPriorStageApplicantLabels]
                    : [];
                this.requiresBorrowerCombinedEligibilityRecheck =
                    !!result.requiresBorrowerCombinedEligibilityRecheck;
                this._applyEligibilityRecheckSource(result.isBorrowerScreen === true);
                this.hasOtherApplicantsOfSameTypeNotAtStage = !!result.hasOtherApplicantsOfSameTypeNotAtStage;
                this.hasOtherApplicantsReachedCustomerDedupe = !!result.hasOtherApplicantsReachedCustomerDedupe;
                this.applicantHasCustomerCode = !!result.applicantHasCustomerCode;
                this.isCustomerDedupeCompleteForApplicant = !!result.isCustomerDedupeCompleteForApplicant;
                this.canAddMoreApplicants = result.canAddMoreApplicants !== false;
                this.stageIsComplete = !!result.stageIsComplete;
                this.isApplicantLoanStagePastDedupe = result.isApplicantLoanStagePastDedupe === true;
                this.isApplicationPastDedupeStep = result.isApplicationPastDedupeStep === true;
                this.guarantorCount = Number(result.guarantorCount) || 0;
                this.coBorrowerCount = Number(result.coBorrowerCount) || 0;
                this.beneficiaryCount = Number(result.beneficiaryCount) || 0;
                this.hasNonIndividualGuarantor = result.hasNonIndividualGuarantor === true;
                this.hasNonIndividualBeneficiary = result.hasNonIndividualBeneficiary === true;
                this.applicantEntityType = result.applicantEntityType || '';
                this.productType = result.productType || '';
                this.matchConfirmedInvalid = result.matchConfirmedInvalid === true;
                this.invalidatedMatchCifId = result.invalidatedMatchCifId || '';
                const hasDedupeMatchResolved = result.hasDedupeMatchResolved === true;
                const autoMatchedFromCrossSell = result.autoMatchedFromCrossSell === true;

                if (hasDedupeMatchResolved || this.matchConfirmedInvalid) {
                    if (result.customerCode) {
                        this.customerCode = String(result.customerCode).trim();
                    }
                    this.matchValidated = true;
                    this.validInvalidClicked = true;
                } else if (this.isCustomerDedupeCompleteForApplicant && result.customerCode) {
                    this.customerCode = String(result.customerCode).trim();
                    if (this.applicantHasCustomerCode) {
                        this.matchValidated = true;
                        this.validInvalidClicked = true;
                    }
                } else if (!this.matchConfirmedInvalid) {
                    // A PAN-derived Customer_Code__c (captured at Basic Details) is not a
                    // resolved dedupe match. Leave the rows selectable for manual Valid/Invalid
                    // until the applicant carries an ETB/NTB relationship or the step is complete.
                    this.customerCode = '';
                }

                if (autoMatchedFromCrossSell && hasDedupeMatchResolved) {
                    this.applicantHasCustomerCode = true;
                }
                if (!this.isBorrowerScreen && this.isCustomerDedupeCompleteForApplicant) {
                    if (!this.isCurrentApplicantNonIndividual) {
                        this.getEmiClicked = true;
                    }
                }
                this.hasAnyRowValidated = hasDedupeMatchResolved
                    || this.isCustomerDedupeCompleteForApplicant
                    || this.matchValidated
                    || this.validInvalidClicked;
                if (result.requiresBorrowerCombinedEligibilityRecheck === true) {
                    this.eligibilityChecked = false;
                    this.checkEligibilityClicked = false;
                } else if (result.eligibilityChecked === true) {
                    this.eligibilityChecked = true;
                    this.checkEligibilityClicked = true;
                }
                if (
                    this.isBorrowerScreen
                    && (this.isApplicationPastDedupeStep || this.isStagePast || this.eligibilityChecked)
                ) {
                    if (!this.isCurrentApplicantNonIndividual) {
                        this.getEmiClicked = true;
                    }
                }
                // Existing EMI must never re-run for an applicant that already fetched it,
                // even after navigating away/back or after a borrower eligibility recheck.
                // NI applicants do not use Existing EMI.
                if (this.isCurrentApplicantNonIndividual || result.existingEmiFetched === true) {
                    this.getEmiClicked = true;
                }
            } else {
                this.showToast('Error', result.errorMessage || 'Failed to load data', 'error');
            }
        } catch (error) {
            console.error('Error loading page data:', error);
            this.showToast('Error', error.body?.message || error.message, 'error');
        } finally {
            if (!silent) {
            this.isLoading = false;
            }
            window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
        }
    }

    handleMatchValidated(event) {
        this.handleMatchValidatedEvent(event);
    }

    async handleMatchValidatedEvent(event) {
        if (this.isReadOnlyScreen || this._matchValidationInProgress) {
            return;
        }
        this._matchValidationInProgress = true;

        const d = event.detail || {};
        const cifId = d.cifId;
        const actionType = d.actionType;
        const stages = d.stages || [
            'Validating customer match...',
            'Updating customer records...'
        ];

        const stage1Start = Date.now();
        this.handleIntegrationProgressUpdate({
            detail: {
                show: true,
                status: 'loading',
                currentStageIndex: 0,
                stages,
                errorMessage: ''
            }
        });

        try {
            this.validInvalidClicked = true;
            const apexMethod = actionType === 'valid' ? 'markMatchAsValid' : 'markMatchAsInvalid';
            const result = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: apexMethod,
                recordId: this.recordId,
                params: {
                    recordId: this.recordId,
                    cifId,
                    applicantId: this._resolveApplicantIdForLoad()
                }
            });

            const stage1Elapsed = Date.now() - stage1Start;
            if (stage1Elapsed < NEXT_BUTTON_STAGE_MIN_DURATION_MS) {
                await new Promise((resolve) =>
                    setTimeout(resolve, NEXT_BUTTON_STAGE_MIN_DURATION_MS - stage1Elapsed)
                );
            }

            this.handleIntegrationProgressUpdate({
                detail: {
                    show: true,
                    status: 'loading',
                    currentStageIndex: 1,
                    stages,
                    errorMessage: ''
                }
            });

            const stage2Start = Date.now();
            const stage2Elapsed = Date.now() - stage2Start;
            if (stage2Elapsed < NEXT_BUTTON_STAGE_MIN_DURATION_MS) {
                await new Promise((resolve) =>
                    setTimeout(resolve, NEXT_BUTTON_STAGE_MIN_DURATION_MS - stage2Elapsed)
                );
            }

            if (result?.isSuccess) {
                if (actionType === 'valid' && cifId) {
                    this.matchConfirmedInvalid = false;
                    this.invalidatedMatchCifId = '';
                    this.customerCode = (result.customerCode || cifId).trim();
                } else if (actionType === 'invalid') {
                    this.matchConfirmedInvalid = true;
                    this.invalidatedMatchCifId = (result.invalidatedMatchCifId || cifId || '').trim();
                    if (result.customerCode) {
                        this.customerCode = String(result.customerCode).trim();
                    }
                } else if (result.customerCode) {
                    this.customerCode = String(result.customerCode).trim();
                }
                this.matchValidated = true;
                this.validInvalidClicked = true;
                this.hasAnyRowValidated = true;
                this.checkEligibilityClicked = false;
                this.eligibilityChecked = false;
                this.showToast('Success', result.message || 'Operation completed', 'success');
                // Refresh server-derived state (row highlight, Valid/Invalid confirmation,
                // and the "Additional Applicants" Add/Remove section) so it appears without
                // a manual page reload.
                await this.loadPageData({ silent: true });
            } else {
                this.handleIntegrationProgressUpdate({
                    detail: {
                        show: true,
                        status: 'error',
                        currentStageIndex: 0,
                        stages,
                        errorMessage: result?.message || 'Operation failed'
                    }
                });
                this.showToast('Error', result?.message || 'Operation failed', 'error');
                return;
            }
        } catch (err) {
            console.error('Error in handleMatchValidatedEvent:', err);
            this.handleIntegrationProgressUpdate({
                detail: {
                    show: true,
                    status: 'error',
                    currentStageIndex: 0,
                    stages,
                    errorMessage: err?.body?.message || err?.message || 'Operation failed'
                }
            });
            this.showToast('Error', err?.body?.message || err?.message || 'Operation failed', 'error');
            return;
        } finally {
            this._matchValidationInProgress = false;
            this.matchValidated = true;
            this.validInvalidClicked = true;
            this.checkEligibilityClicked = false;
            setTimeout(() => {
                this.handleIntegrationProgressUpdate({ detail: { show: false, status: 'success' } });
            }, 800);
        }
    }

    async handleIntegrationComplete(event) {
        const response = event.detail || {};
        if (response.customerCode) {
            this.customerCode = String(response.customerCode).trim();
        }
        this.matchValidated = true;
        this.validInvalidClicked = true;
        this.hasAnyRowValidated = true;
        if (response.message) {
            this.showToast('Success', response.message, 'success');
        }
        await this.loadPageData({ silent: true });
    }

    handleSelectionChange() {
        if (this.isReadOnlyScreen) {
            return;
        }
        if (this.customerCode) {
            return;
        }
        this.matchValidated = false;
        this.validInvalidClicked = false;
        this.matchConfirmedInvalid = false;
        this.invalidatedMatchCifId = '';
        this.eligibilityChecked = false;
        this.checkEligibilityClicked = false;
        this.checkEligibilityProcessing = false;
        this.getEmiClicked = false;
        this.borrowerAddGuarantorSelection = 'No';
        this.borrowerAddBeneficiarySelection = 'No';
    }

    handleAddApplicantsSelectionChange(event) {
        const detail = event.detail || {};
        const addGuarantor = detail.addGuarantorCoBorrower || 'No';
        const addBeneficiary = detail.addBeneficiary || 'No';

        this.borrowerAddGuarantorSelection = addGuarantor;
        this.borrowerAddBeneficiarySelection = addBeneficiary;
        //capture "+ Add Sub-<Role>" intent (route to existing role grid on NEXT)
        this.borrowerAddSubGuarantorSelection = detail.addSubGuarantor || 'No';
        this.borrowerAddSubBeneficiarySelection = detail.addSubBeneficiary || 'No';
    }

    async _validateNiConstitutionOnNext(selections = {}) {
        if (!this.isNonIndividual || this.isTwoWheeler) {
            return true;
        }

        const addingApplicant = selections.addGuarantorCoBorrower === 'Yes'
            || selections.addBeneficiary === 'Yes';
        if (addingApplicant) {
            return true;
        }

        try {
            const result = await validateNiConstitutionForApplication({
                applicationId: this.recordId
            });

            if (result?.isValid !== false) {
                return true;
            }

            const violations = Array.isArray(result.violations) ? result.violations : [];
            const firstViolation = violations[0] || {};
            const message = firstViolation.message || result.message || 'Constitution validation failed.';
            this._showNiConstitutionViolationModal(firstViolation, message);
            return false;
        } catch (error) {
            console.error('NI constitution validation failed:', error);
            this.showToast(
                'Error',
                error?.body?.message || error?.message || 'Unable to validate constitution limits.',
                'error'
            );
            return false;
        }
    }

    _showNiConstitutionViolationModal(violation = {}, message) {
        this._openConfirmModal({
            title: 'Constitution Validation',
            message: message || violation.message
        });
    }

    _openConfirmModal(props, context) {
        this.confirmModalProps = props || {};
        this._confirmModalContext = context || null;
        this.showConfirmModal = true;
    }

    _closeConfirmModal() {
        this.showConfirmModal = false;
        this.confirmModalProps = {};
        this._confirmModalContext = null;
        this._pendingRemoveApplicantId = null;
    }

    handleConfirmModalClose() {
        this._closeConfirmModal();
    }

    async handleConfirmModalAction(event) {
        const value = event.detail?.value;
        const context = this._confirmModalContext;
        const applicantId = this._pendingRemoveApplicantId;
        this._closeConfirmModal();

        if (value === 'cancel' || !value) {
            return;
        }

        if (context === 'removeApplicant' && value === 'confirm' && applicantId) {
            await this.handleRemoveApplicant({ detail: { applicantId } });
            return;
        }
    }
    
    // Handler for checkeligibility events — NPA, CIBIL, BRE stages (stub until APIs wired)
    async handleCheckEligibilityEvent(event) {
        if (this.isReadOnlyScreen || !this.isBorrowerScreen) {
            return;
        }
        const d = event.detail || {};
        const stagePlan = d.stagePlan?.length
            ? d.stagePlan
            : this.buildCheckEligibilityStagePlanForRun();
        const stages = d.stages?.length ? d.stages : getCheckEligibilityStageLabels(stagePlan);

        if (this.checkEligibilityClicked) {
            return;
        }

        if (this.isExistingEmiRequired && !this.getEmiClicked) {
            this.showToast(
                'Validation',
                'Click Get Existing EMI before checking eligibility.',
                'warning'
            );
            return;
        }

        this.checkEligibilityProcessing = true;
        try {
            const cifId = this.resolveRequiredCifId(d.cifId);
            if (!cifId) {
                return;
            }

            const integrationResult = await this.runIntegrationStageProgress(stages, {
                onStage: async (stageIndex) => {
                    const stage = stagePlan[stageIndex];
                    return savePageData({
                        apexClassName: APEX_CLASS,
                        apexMethodName: APEX_METHOD_RUN_ELIGIBILITY_STAGE,
                        recordId: this.recordId,
                        params: {
                            stageKey: stage.key,
                            recordId: this.recordId,
                            cifId,
                            applicantId: this._resolveApplicantIdForLoad()
                        }
                    });
                }
            });

            if (integrationResult?.isSuccess !== true) {
                this.showToast(
                    'Error',
                    integrationResult?.message || 'Eligibility check failed',
                    'error'
                );
                return;
            }

            const result = integrationResult.result;
            if (result?.isSuccess === true) {
                this.eligibilityChecked = true;
                this.checkEligibilityClicked = true;
                const successMsg = result.checkEligibilityMessage || result.message || 'Check Eligibility Success';
                this.showToast('Success', successMsg, 'success');
                await this.loadPageData({ silent: true });
            } else {
                this.showToast('Error', result?.message || 'Eligibility check failed', 'error');
            }
        } catch (err) {
            console.error('Error in handleCheckEligibilityEvent:', err);
            this.handleIntegrationProgressUpdate({
                detail: {
                    show: true,
                    status: 'error',
                    currentStageIndex: 0,
                    stages: getCheckEligibilityStageLabels(this.buildCheckEligibilityStagePlanForRun()),
                    errorMessage: err?.body?.message || err?.message || String(err)
                }
            });
            this.showToast('Error', err?.body?.message || err?.message || String(err), 'error');
        } finally {
            this.checkEligibilityProcessing = false;
            setTimeout(() => {
                this.handleIntegrationProgressUpdate({ detail: { show: false, status: 'success' } });
            }, INTEGRATION_MODAL_CLOSE_DELAY_MS);
        }
    }

    handleCheckEligibility(event) {
        this.handleCheckEligibilityEvent(event);
    }

    handleFooterCheckEligibility() {
        const stagePlan = this.buildCheckEligibilityStagePlanForRun();
        this.handleCheckEligibilityEvent({
            detail: {
                cifId: this.resolveRequiredCifId(),
                stagePlan,
                stages: getCheckEligibilityStageLabels(stagePlan)
            }
        });
    }

    getCheckEligibilityApplicantLabel() {
        if (
            this.requiresBorrowerCombinedEligibilityRecheck
            && this.eligibilityRecheckApplicantTabLabel
        ) {
            return this.eligibilityRecheckApplicantTabLabel;
        }
        return 'Borrower';
    }

    buildCheckEligibilityStagePlanForRun() {
        // Bureau stage follows the checked applicant's customer type: NI -> CRIF, IN -> CIBIL.
        const isCheckedApplicantNonIndividual =
            this.requiresBorrowerCombinedEligibilityRecheck && this.eligibilityRecheckApplicantTabLabel
                ? this.eligibilityRecheckApplicantIsNonIndividual
                : this.isNonIndividual;
        return buildCheckEligibilityStagePlan(
            this.getCheckEligibilityApplicantLabel(),
            isCheckedApplicantNonIndividual
        );
    }

    handleCheckEligibilityValidation(event) {
        this.showToast(
            'Validation',
            event.detail?.message || 'Select a customer match or mark Valid before checking eligibility.',
            'warning'
        );
    }

    handleRequestRemoveConfirm(event) {
        if (this.isStagePast) {
            return;
        }
        const applicantId = event.detail?.applicantId;
        if (!applicantId) {
            return;
        }
        this._pendingRemoveApplicantId = applicantId;
        this._openConfirmModal({
            title: 'Remove Applicant',
            message: 'Do you wish to proceed with removing the selected Applicant?',
            buttons: [
                { label: 'Cancel', value: 'cancel', variant: 'neutral' },
                { label: 'Confirm', value: 'confirm', variant: 'brand' }
            ]
        }, 'removeApplicant');
    }

    async handleRemoveApplicant(event) {
        if (this.isStagePast) {
            return;
        }
        const applicantId = event.detail.applicantId;
        if (!applicantId) {
            return;
        }

        this.isSaving = true;
        try {
            const result = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_REMOVE_APPLICANT,
                recordId: this.recordId,
                params: { applicantId }
            });

            if (!result?.isSuccess) {
                this.showToast('Error', result?.message || 'Failed to remove applicant.', 'error');
                return;
            }

            this.showToast('Success', result.message || 'Applicant removed successfully', 'success');

            const addSection = this.template.querySelector('c-add-applicants-section');
            if (addSection?.resetRemoveUi) {
                addSection.resetRemoveUi();
            }

            await this.loadPageData();

            window.dispatchEvent(new CustomEvent(LOS_MENU_REFRESH_EVENT, {
                bubbles: true,
                composed: true
            }));
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    getCurrentApplicantDisplayLabel() {
        const tabLabel = (this.currentApplicantTabLabel || '').trim();
        if (tabLabel) {
            return tabLabel;
        }
        return this.isBorrowerScreen ? 'Borrower' : 'Applicant';
    }

    buildCurrentApplicantPendingMessage() {
        const label = this.getCurrentApplicantDisplayLabel();
        if (this.isBorrowerScreen) {
            return `Dedupe and Eligibility journey is pending for ${label}. Complete match validation and eligibility check before proceeding.`;
        }
        return `Dedupe and Eligibility journey is pending for ${label}. Select a match and click Valid or Invalid before proceeding.`;
    }

    buildIncompleteApplicantsValidationMessage(result) {
        const pendingPrior = Array.isArray(result?.pendingPriorStageApplicants)
            ? result.pendingPriorStageApplicants.filter((item) => !!item)
            : [];
        if (pendingPrior.length > 0) {
            if (pendingPrior.length === 1) {
                return `Complete Lead Details, Basic Details, and KYC Details for ${pendingPrior[0]} before proceeding from the Borrower tab.`;
            }
            return `Complete Lead Details, Basic Details, and KYC Details for the following applicant(s) before proceeding: ${pendingPrior.join(', ')}.`;
        }
        const labels = Array.isArray(result?.incompleteApplicants)
            ? result.incompleteApplicants.filter((item) => !!item)
            : [];
        if (labels.length > 0) {
            if (labels.length === 1) {
                return `Dedupe and Eligibility journey is pending for ${labels[0]}. Please complete it before proceeding.`;
            }
            return `Dedupe and Eligibility journey is pending for the following applicant(s): ${labels.join(', ')}. Please complete them before proceeding.`;
        }
        return result?.message
            || 'Dedupe and Eligibility journey is pending for one or more applicants. Please complete them before proceeding.';
    }

    async validateCurrentApplicantDedupeComplete() {
        if (!this.isCurrentApplicantDedupeComplete) {
            this.showToast('Validation Error', this.buildCurrentApplicantPendingMessage(), 'error');
            return false;
        }
        return true;
    }

    buildPendingPriorStagesMessage() {
        const labels = (this.pendingPriorStageApplicantLabels || []).filter((item) => !!item);
        if (labels.length === 1) {
            return `Complete Lead Details, Basic Details, and KYC Details for ${labels[0]} before proceeding from the Borrower tab.`;
        }
        if (labels.length > 1) {
            return `Complete Lead Details, Basic Details, and KYC Details for the following applicant(s) before proceeding: ${labels.join(', ')}.`;
        }
        return 'Added applicant(s) must complete Lead Details, Basic Details, and KYC Details before you can proceed from the Borrower tab.';
    }

    async validateAllApplicantsDedupeComplete({ persistCompletion = false } = {}) {
        if (!this.recordId) {
            return false;
        }

        if (this.isBorrowerScreen) {
            await this.loadPageData({ silent: true });
        }

        if (!this.isBorrowerScreen) {
            return this.validateCurrentApplicantDedupeComplete();
        }

        if (this.hasAdditionalApplicantsPendingPriorStages) {
            this.showToast(
                'Validation Error',
                this.buildPendingPriorStagesMessage(),
                'error'
            );
            return false;
        }

        if (this.hasApplicantsNotAtCustomerDedupe) {
            this.showToast(
                'Validation Error',
                'Complete Dedupe and Eligibility (Valid/Invalid) for all added applicant(s) before proceeding.',
                'error'
            );
            return false;
        }

        if (!this.isCurrentApplicantDedupeComplete) {
            this.showToast('Validation Error', this.buildCurrentApplicantPendingMessage(), 'error');
            return false;
        }

        try {
            console.log('this.recordId' + this.recordId);
            console.log('this._resolveApplicantIdForLoad()' + this._resolveApplicantIdForLoad());
            console.log('this.isCurrentApplicantDedupeComplete' + this.isCurrentApplicantDedupeComplete);
            console.log('this.isBorrowerScreen' + this.isBorrowerScreen);
            const result = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_VALIDATE_ALL_APPLICANTS,
                recordId: this.recordId,
                params: {
                    applicantId: this._resolveApplicantIdForLoad(),
                    currentApplicantSessionComplete: this.isCurrentApplicantDedupeComplete,
                    isBorrowerScreen: this.isBorrowerScreen,
                    persistCompletion
                }
            });

            if (result?.isSuccess) {
                return true;
            }

            this.showToast(
                'Validation Error',
                this.buildIncompleteApplicantsValidationMessage(result),
                'error'
            );
            return false;
        } catch (error) {
            console.error('Error validating dedupe completion:', error);
            this.showToast(
                'Error',
                error?.body?.message || error?.message || 'Validation failed.',
                'error'
            );
            return false;
        }
    }

    async handleNextButton() {
        if (this.isNextNavigationInProgress) {
            return;
        }

        if (this.isViewingCompletedPastStage) {
            await this.navigateFromCompletedStageView();
            return;
        }

        let createdTabLabel = null;
        let proceedToNavigation = false;

        this.isNextNavigationInProgress = true;
        this.isSaving = true;

        try {
            const addApplicantsSection = this.template.querySelector('c-add-applicants-section');
            const niConstitutionSelections = addApplicantsSection?.getSelections?.() || {
                addGuarantorCoBorrower: this.borrowerAddGuarantorSelection,
                addBeneficiary: this.borrowerAddBeneficiarySelection
            };


            if (!addApplicantsSection || !this.showAddApplicantsSection || this.isReadOnlyScreen) {
                if (this.isBorrowerScreen) {
                    if (this.isNonIndividual && !this.isTwoWheeler) {
                        if (!(await this._validateNiConstitutionOnNext(niConstitutionSelections))) {
                            return;
                        }
                    }
                    if (!(await this.validateAllApplicantsDedupeComplete())) {
                        return;
                    }
                } else if (!(await this.validateCurrentApplicantDedupeComplete())) {
                    return;
                }
                proceedToNavigation = true;
                createdTabLabel = null;
            } else {
                if (!addApplicantsSection.validateSelections()) {
                    return;
                }

                const selections = addApplicantsSection.getSelections();

                // "+ Add Sub-<Role>" picked: do NOT create a new top-level.
                // Route to that role's existing multi-grid so subs can be added against NI tiles.
                const addSubGuarantor = selections.addSubGuarantor === 'Yes';
                const addSubBeneficiary = selections.addSubBeneficiary === 'Yes';
                if (addSubGuarantor || addSubBeneficiary) {
                    const roleLabel = addSubGuarantor
                        ? (this.isTwoWheeler ? 'Co-Borrower' : 'Guarantor')
                        : 'Beneficiary';
                    await this.navigateToRoleGrid(roleLabel);
                    return;
                }

                const hasYesToAdditional =
                    selections.addGuarantorCoBorrower === 'Yes' ||
                    selections.addBeneficiary === 'Yes';

                if (!hasYesToAdditional && this.isBorrowerScreen) {
                    if (this.isNonIndividual && !this.isTwoWheeler) {
                        if (!(await this._validateNiConstitutionOnNext(niConstitutionSelections))) {
                            return;
                        }
                    }
                    if (!(await this.validateAllApplicantsDedupeComplete())) {
                        return;
                    }
                }

                if (this.isNonIndividual && !this.isTwoWheeler && this.isBorrowerScreen && hasYesToAdditional) {
                    if (!(await this._validateNiConstitutionOnNext(niConstitutionSelections))) {
                        return;
                    }
                }

                // Customer Type is captured on Basic Details now, so it is no
                // longer sent here; the Apex create defaults Type__c and Basic Details sets it.
                const result = await savePageData({
                    apexClassName: APEX_CLASS,
                    apexMethodName: APEX_METHOD_SAVE_APPLICANT,
                    recordId: this.recordId,
                    params: {
                        addGuarantorCoBorrower: selections.addGuarantorCoBorrower,
                        addBeneficiary: selections.addBeneficiary,
                        applicationType: this.applicationType
                    }
                });

                if (result?.isSuccess !== true) {
                    this.showToast('Error', result?.message || 'Failed to save.', 'error');
                    return;
                }

                this.showToast('Success', result.message || 'Saved successfully', 'success');
                createdTabLabel = result.createdApplicantTabLabel || null;

                if (hasYesToAdditional && !createdTabLabel) {
                    this.showToast('Error', 'Applicant could not be created. Please try again.', 'error');
                    return;
                }

                await this.loadPageData();
                proceedToNavigation = true;
            }

            if (!proceedToNavigation) {
                return;
            }

            if (this.shouldRunNextForwardIntegrations(createdTabLabel)) {
                const integrationOk = await this.runNextForwardIntegrationChain();
                if (integrationOk?.isSuccess !== true) {
                    this.showToast(
                        'Error',
                        integrationOk?.message || 'Forward integration failed. Applicant stage was not updated.',
                        'error'
                    );
                    return;
                }
            }

            if (!createdTabLabel && this.isBorrowerTabActive) {
                const isValid = await this.validateAllApplicantsDedupeComplete({ persistCompletion: true });
                if (!isValid) {
                    return;
                }
                window.dispatchEvent(new CustomEvent(LOS_MENU_REFRESH_EVENT, {
                    bubbles: true,
                    composed: true
                }));
            }

            await this.navigateAfterCustomerDedupeNext(createdTabLabel);
        } catch (error) {
            console.error('Error in handleNextButton:', error);
            this.showToast('Error', error?.body?.message || error?.message || 'Navigation failed.', 'error');
        } finally {
            this.isNextNavigationInProgress = false;
            this.isSaving = false;
        }
    }

    /**
     * AML + ScoreCard run only when Borrower Next advances the application forward.
     * Skipped for new-applicant Basic Details routing and co-applicant dedupe hops.
     */
    shouldRunNextForwardIntegrations(createdTabLabel) {
        if (createdTabLabel) {
            return false;
        }
        return this.isBorrowerTabActive === true;
    }

    _resolveNiProductTypeFromPage() {
        const pt = (this.productType || '').trim().toLowerCase();
        if (!pt) {
            return null;
        }
        if (pt === 'cv' || pt === 'scv' || pt === 'lcv' || pt === 'mhce' || pt === 'ce'
            || pt.includes('commercial vehicle') || pt.includes('commercial equipment')) {
            return 'CV';
        }
        if (pt === '4w' || pt === 'pv' || pt.includes('passenger vehicle')) {
            return 'PV';
        }
        return null;
    }

    _shouldIncludeCvNiFiOnForward() {
        return this.isNonIndividual === true && this._resolveNiProductTypeFromPage() === 'CV';
    }

    async runNextForwardIntegrationChain() {
        const stagePlan = buildDedupeForwardStagePlan(this._shouldIncludeCvNiFiOnForward());
        const stages = getDedupeForwardStageLabels(stagePlan);

        try {
            return await this.runIntegrationStageProgress(stages, {
                onStage: async (stageIndex) => {
                    const stage = stagePlan[stageIndex];
                    return savePageData({
                        apexClassName: APEX_CLASS,
                        apexMethodName: APEX_METHOD_RUN_DEDUPE_FORWARD_STAGE,
                        recordId: this.recordId,
                        params: {
                            stageKey: stage.key,
                            recordId: this.recordId
                        }
                    });
                }
            });
        } finally {
            setTimeout(() => {
                this.handleIntegrationProgressUpdate({ detail: { show: false, status: 'success' } });
            }, INTEGRATION_MODAL_CLOSE_DELAY_MS);
        }
    }

    async runIntegrationStageProgress(stages, { onStage } = {}) {
        if (!stages?.length) {
            return { isSuccess: true };
        }

        let lastResult = { isSuccess: true };

        for (let stageIndex = 0; stageIndex < stages.length; stageIndex += 1) {
            this.handleIntegrationProgressUpdate({
                detail: {
                    show: true,
                    status: 'loading',
                    currentStageIndex: stageIndex,
                    stages,
                    errorMessage: ''
                }
            });

            const stageStart = Date.now();
            let stageOutcome = { isSuccess: true };

            try {
                if (typeof onStage === 'function') {
                    stageOutcome = await onStage(stageIndex);
                }
            } catch (error) {
                stageOutcome = {
                    isSuccess: false,
                    message: error?.body?.message || error?.message || 'Integration failed.'
                };
            }

            if (stageOutcome?.isSuccess !== true) {
                this.handleIntegrationProgressUpdate({
                    detail: {
                        show: true,
                        status: 'error',
                        currentStageIndex: stageIndex,
                        stages,
                        errorMessage: stageOutcome?.message || 'Integration failed.'
                    }
                });
                return {
                    isSuccess: false,
                    message: stageOutcome?.message || 'Integration failed.'
                };
            }

            lastResult = stageOutcome;
            await this.waitForIntegrationStagePacing(stageStart);
        }

        this.handleIntegrationProgressUpdate({
            detail: {
                show: true,
                status: 'loading',
                currentStageIndex: stages.length,
                stages,
                errorMessage: ''
            }
        });

        return { isSuccess: true, result: lastResult };
    }

    async waitForIntegrationStagePacing(stageStart) {
        const elapsed = Date.now() - stageStart;
        if (elapsed < NEXT_BUTTON_STAGE_MIN_DURATION_MS) {
            await new Promise((resolve) => {
                setTimeout(resolve, NEXT_BUTTON_STAGE_MIN_DURATION_MS - elapsed);
            });
        }
    }

    /**
     * When viewing a completed (green) Dedupe step, Next returns the user to the
     * application's current active stage — not back through dedupe processing.
     */
    async navigateFromCompletedStageView() {
        if (!this.recordId) {
            return;
        }

        this.isSaving = true;
        try {
            const navState = await getMenuForPortfolio({
                portfolio: null,
                applicationId: this.recordId
            });

            if (!navState?.isSuccess || !navState.menuItems?.length) {
                this.showToast(
                    'Navigation Error',
                    navState?.message || 'Could not load the current application stage.',
                    'error'
                );
                this.dispatchLosNextStage();
                return;
            }

            window.dispatchEvent(new CustomEvent(LOS_NAVIGATION_STATE_EVENT, {
                detail: { navigationState: navState },
                bubbles: true,
                composed: true
            }));

            const currentStageItem = this.findCurrentViewItem(navState.menuItems)
                || this.findActiveMenuItem(navState.menuItems);

            if (!currentStageItem) {
                this.showToast(
                    'Navigation Error',
                    'Current application stage could not be resolved. Please select a stage from the menu.',
                    'error'
                );
                return;
            }

            this.dispatchMenuSelectForViewItem(currentStageItem);
        } catch (error) {
            console.error('Error navigating from completed dedupe view:', error);
            this.showToast(
                'Navigation Error',
                error?.body?.message || error?.message || 'Unable to navigate to the current stage.',
                'error'
            );
        } finally {
            this.isSaving = false;
        }
    }

    findActiveMenuItem(items) {
        if (!items?.length) {
            return null;
        }
        for (const item of items) {
            if (item.subItems?.length) {
                const found = this.findActiveMenuItem(item.subItems);
                if (found) {
                    return found;
                }
            }
            if ((item.status || '').toLowerCase() === 'active') {
                return item;
            }
        }
        return null;
    }

    dispatchLosNextStage() {
        if (!this.currentViewId) {
            return;
        }
        window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
            detail: {
                currentViewId: this.currentViewId,
                id: this.currentViewId,
                applicantId: this._resolveApplicantIdForLoad(),
                currentLoanStageComplete: this.tab || DEDUPE_STEP_NAME,
                currentStagePhrase: this.stagePhrase || ''
            },
            bubbles: true,
            composed: true
        }));
    }

    async navigateAfterCustomerDedupeNext(createdTabLabel) {
        if (!this.recordId) {
            return;
        }

        if (createdTabLabel) {
            this.isSaving = true;
            try {
                const navResult = await processCustomerDedupeNextRequest({
                    applicationId: this.recordId,
                    createdApplicantTabLabel: createdTabLabel,
                    currentApplicantTabLabel: this.currentApplicantTabLabel || 'Borrower',
                    currentStagePhrase: this.stagePhrase || '',
                    currentLoanStageName: this.tab || DEDUPE_STEP_NAME
                });

                if (!navResult?.isSuccess) {
                    this.showToast('Error', navResult?.message || 'Navigation failed.', 'error');
                    return;
                }

                this.applyNavigationResult(navResult);
            } catch (error) {
                console.error('Error in navigateAfterCustomerDedupeNext:', error);
                this.showToast('Error', error?.body?.message || error?.message || 'Navigation failed.', 'error');
            } finally {
                this.isSaving = false;
            }
            return;
        }

        // Capture the applicant traversing back so the Borrower can run the combined
        // eligibility recheck (BRE/bureau) for the applicant that just clicked Next,
        // not a query-resolved one. Only a non-Borrower co-applicant triggers this.
        const traversedBackTabLabel = (this.currentApplicantTabLabel || '').trim();
        const traversedBackIsNonBorrower = !!traversedBackTabLabel
            && traversedBackTabLabel.toLowerCase() !== 'borrower';
        const traversedBackIsNonIndividual = this.isCurrentApplicantNonIndividual === true;

        this.isSaving = true;
        try {
            const navResult = await processCustomerDedupeNextRequest({
                applicationId: this.recordId,
                createdApplicantTabLabel: null,
                currentApplicantTabLabel: this.currentApplicantTabLabel || 'Borrower',
                currentStagePhrase: this.stagePhrase || '',
                currentLoanStageName: this.tab || DEDUPE_STEP_NAME
            });
            if (!navResult?.isSuccess) {
                this.showToast('Error', navResult?.message || 'Navigation failed.', 'error');
                return;
            }
            if (traversedBackIsNonBorrower && this._navResultLandsOnBorrower(navResult)) {
                this._storeEligibilityRecheckSource(
                    traversedBackTabLabel,
                    traversedBackIsNonIndividual
                );
            }
            this.applyNavigationResult(navResult);
        } catch (error) {
            console.error('Error advancing from dedupe:', error);
            this.showToast('Error', error?.body?.message || error?.message || 'Navigation failed.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    _navResultLandsOnBorrower(navResult) {
        const preferredTab = (
            navResult?.navigationState?.preferredApplicantTabLabel
            || navResult?.preferredApplicantTabLabel
            || ''
        ).trim();
        return preferredTab.toLowerCase() === 'borrower';
    }

    _recheckSourceKey() {
        return `cdedupe.recheckSource.${this.recordId}`;
    }

    // Persisted in sessionStorage so the traversed-back applicant survives a Borrower
    // page reload/refresh in the window before the combined eligibility recheck completes.
    _storeEligibilityRecheckSource(tabLabel, isNonIndividual) {
        if (!this.recordId || !tabLabel) {
            return;
        }
        try {
            window.sessionStorage.setItem(
                this._recheckSourceKey(),
                JSON.stringify({ tabLabel, isNonIndividual: isNonIndividual === true })
            );
        } catch (e) {
            // sessionStorage may be unavailable; recheck falls back to the in-session value.
        }
    }

    _readEligibilityRecheckSource() {
        if (!this.recordId) {
            return null;
        }
        try {
            const raw = window.sessionStorage.getItem(this._recheckSourceKey());
            return raw ? JSON.parse(raw) : null;
        } catch (e) {
            return null;
        }
    }

    _clearEligibilityRecheckSource() {
        if (!this.recordId) {
            return;
        }
        try {
            window.sessionStorage.removeItem(this._recheckSourceKey());
        } catch (e) {
            // noop
        }
    }

    // Borrower's combined eligibility recheck targets the applicant that just traversed
    // back (captured on their Next), so BRE/bureau runs for that applicant's type.
    _applyEligibilityRecheckSource(isBorrowerScreen) {
        if (isBorrowerScreen && this.requiresBorrowerCombinedEligibilityRecheck) {
            const source = this._readEligibilityRecheckSource();
            if (source && source.tabLabel) {
                this.eligibilityRecheckApplicantTabLabel = source.tabLabel;
                this.eligibilityRecheckApplicantIsNonIndividual = source.isNonIndividual === true;
                return;
            }
        }
        this.eligibilityRecheckApplicantTabLabel = '';
        this.eligibilityRecheckApplicantIsNonIndividual = false;
        if (!this.requiresBorrowerCombinedEligibilityRecheck) {
            this._clearEligibilityRecheckSource();
        }
    }

    // route to an existing role's multi-grid (no new top-level created) so the
    // user can add sub-applicants against NI tiles via the grid's "+ Add Sub Applicant" tile.
    async navigateToRoleGrid(roleLabel) {
        if (!this.recordId || !roleLabel) {
            return;
        }
        this.isSaving = true;
        try {
            const navResult = await routeToRoleGrid({
                applicationId: this.recordId,
                roleLabel,
                stepName: 'Basic Details'
            });
            if (!navResult?.isSuccess) {
                this.showToast('Error', navResult?.message || 'Could not open the applicant group.', 'error');
                return;
            }
            this.applyNavigationResult(navResult);
        } catch (error) {
            console.error('Error in navigateToRoleGrid:', error);
            this.showToast('Error', error?.body?.message || error?.message || 'Navigation failed.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    applyNavigationResult(navResult) {
        const navState = navResult?.navigationState;
        if (navState?.menuItems) {
            window.dispatchEvent(new CustomEvent(LOS_NAVIGATION_STATE_EVENT, {
                detail: { navigationState: navState },
                bubbles: true,
                composed: true
            }));

            const preferredTab = navState.preferredApplicantTabLabel
                || navResult.preferredApplicantTabLabel;
            const preferredApplicantId = navState.preferredApplicantId;
            const preferredViewStep = navState.preferredViewStepName || this.tab || DEDUPE_STEP_NAME;
            const currentViewItem = this.findCurrentViewItem(navState.menuItems);
            const resolvedViewItem = this.resolveNavigationViewItem(
                navState.menuItems,
                currentViewItem,
                preferredTab,
                preferredApplicantId,
                preferredViewStep
            );

            if (resolvedViewItem?.isGroupItem && preferredTab && preferredApplicantId) {
                this.dispatchDrillDownForNewApplicant(resolvedViewItem, navState);
                return;
            }
            if (resolvedViewItem) {
                this.dispatchMenuSelectForViewItem(resolvedViewItem);
            }
            return;
        }
        window.dispatchEvent(new CustomEvent(LOS_MENU_REFRESH_EVENT, {
            bubbles: true,
            composed: true
        }));
    }

    findCurrentViewItem(items) {
        if (!items?.length) {
            return null;
        }
        for (const item of items) {
            if (item.currentView) {
                return item;
            }
            if (item.subItems?.length) {
                const found = this.findCurrentViewItem(item.subItems);
                if (found) {
                    return found;
                }
            }
        }
        return null;
    }

    resolveNavigationViewItem(items, currentViewItem, preferredTab, preferredApplicantId, preferredViewStep) {
        if (currentViewItem && this.viewItemMatchesPreferred(currentViewItem, preferredTab, preferredApplicantId)) {
            return currentViewItem;
        }

        if (preferredViewStep) {
            const stepScopedMatch = this.findApplicantSubMenuItemUnderStep(
                items,
                preferredViewStep,
                preferredTab,
                preferredApplicantId
            );
            if (stepScopedMatch) {
                return stepScopedMatch;
            }
        }

        if (!preferredTab && !preferredApplicantId) {
            return currentViewItem;
        }
        const preferredMatch = this.findApplicantSubMenuItem(
            items,
            preferredTab,
            preferredApplicantId
        );
        if (preferredMatch) {
            return preferredMatch;
        }
        if (currentViewItem?.applicantId) {
            return currentViewItem;
        }
        if (currentViewItem?.subItems?.length) {
            const childMatch = this.findApplicantSubMenuItem(
                currentViewItem.subItems,
                preferredTab,
                preferredApplicantId
            );
            if (childMatch) {
                return childMatch;
            }
        }
        return currentViewItem;
    }

    viewItemMatchesPreferred(item, preferredTab, preferredApplicantId) {
        if (!item) {
            return false;
        }
        if (preferredApplicantId && item.applicantId === preferredApplicantId) {
            return true;
        }
        if (!preferredTab) {
            return false;
        }
        const tab = preferredTab.trim().toLowerCase();
        const labels = [item.label, item.applicantType, item.tab]
            .filter((value) => value != null && String(value).trim())
            .map((value) => String(value).trim().toLowerCase());
        return labels.includes(tab);
    }

    findApplicantSubMenuItemUnderStep(items, stepName, preferredTab, preferredApplicantId) {
        if (!items?.length || !stepName) {
            return null;
        }
        const normalizedStep = stepName.trim().toLowerCase();
        for (const item of items) {
            const itemStep = (item.tab || item.label || '').trim().toLowerCase();
            if (itemStep === normalizedStep && item.subItems?.length) {
                const match = this.findApplicantSubMenuItem(
                    item.subItems,
                    preferredTab,
                    preferredApplicantId
                );
                if (match) {
                    return match;
                }
            }
            if (item.subItems?.length) {
                const nested = this.findApplicantSubMenuItemUnderStep(
                    item.subItems,
                    stepName,
                    preferredTab,
                    preferredApplicantId
                );
                if (nested) {
                    return nested;
                }
            }
        }
        return null;
    }

    findApplicantSubMenuItem(items, preferredTab, preferredApplicantId) {
        if (!items?.length) {
            return null;
        }
        const tab = (preferredTab || '').trim();
        for (const item of items) {
            if (preferredApplicantId && item.applicantId === preferredApplicantId) {
                return item;
            }
            if (tab) {
                const label = (item.label || item.tab || '').trim();
                if (label && label.toLowerCase() === tab.toLowerCase()) {
                    return item;
                }
            }
            if (item.subItems?.length) {
                const found = this.findApplicantSubMenuItem(
                    item.subItems,
                    preferredTab,
                    preferredApplicantId
                );
                if (found) {
                    return found;
                }
            }
        }
        return null;
    }

    dispatchMenuSelectForViewItem(viewItem) {
        const tabLabel = viewItem.tab || viewItem.label;
        const label = viewItem.applicantType && viewItem.applicantType !== tabLabel
            ? `${tabLabel} - ${viewItem.applicantType}`
            : tabLabel;
        const isStagePast = (viewItem.status || '').toLowerCase() === 'completed';
        window.dispatchEvent(new CustomEvent(LOS_MENU_SELECT_EVENT, {
            detail: {
                tab: tabLabel,
                id: viewItem.id,
                label,
                applicantId: viewItem.applicantId,
                applicantType: viewItem.applicantType || tabLabel,
                applicantName: viewItem.applicantName,
                isGroupItem: viewItem.isGroupItem === true,
                applicants: viewItem.applicants || [],
                stagePhrase: viewItem.stagePhrase,
                currentStagePhrase: viewItem.stagePhrase,
                isStagePast,
                overrideLwc: viewItem.overrideLwc || ''
            },
            bubbles: true,
            composed: true
        }));
    }

    dispatchDrillDownForNewApplicant(groupItem, navState) {
        const tabLabel = navState.preferredApplicantTabLabel;
        const applicantId = navState.preferredApplicantId;
        const applicantName = navState.preferredApplicantName || '';
        const basePhrase = (groupItem.stagePhrase || '')
            .replace(/_Guarantor$/, '')
            .replace(/_Co-Borrower$/, '')
            .replace(/_CoBorrower$/, '')
            .replace(/_Beneficiary$/, '');
        const drillStagePhrase = `${basePhrase}_${tabLabel}`;
        const drillId = `${drillStagePhrase.replace(/\s+/g, '_')}_${applicantId}`;
        const tabValue = groupItem.tab || groupItem.label;
        const labelValue = applicantName
            ? `${tabValue} - ${tabLabel} (${applicantName})`
            : `${tabValue} - ${tabLabel}`;
        window.dispatchEvent(new CustomEvent(LOS_MENU_SELECT_EVENT, {
            detail: {
                tab: tabValue,
                id: drillId,
                label: labelValue,
                applicantId,
                applicantType: tabLabel,
                applicantName,
                isGroupItem: false,
                applicants: [],
                stagePhrase: drillStagePhrase,
                currentStagePhrase: drillStagePhrase,
                isStagePast: false,
                overrideLwc: groupItem.overrideLwc || ''
            },
            bubbles: true,
            composed: true
        }));
    }

    get dedupeTableKey() {
        return `dedupe-${this.customerCode || 'none'}-${this.matchValidated}-${this.matches?.length || 0}`;
    }

    get showResultTable() {
        return this.matches && this.matches.length > 0;
    }

    get showCheckEligibilityFooter() {
        return this.isBorrowerTabActive;
    }

    get isGetEmiReady() {
        if (this.isBorrowerScreen) {
            return this.hasAnyRowValidated && !!this.customerCode;
        }
        return this.matchValidated && !!this.customerCode;
    }

    get isExistingEmiRequired() {
        return !this.isCurrentApplicantNonIndividual;
    }

    get showGetExistingEmiButton() {
        return this.isExistingEmiRequired;
    }

    get isCurrentApplicantDedupeComplete() {
        if (this.isBorrowerScreen) {
            return this.eligibilityChecked;
        }
        const dedupeResolved = this.matchValidated && !!this.customerCode;
        return this.isExistingEmiRequired
            ? dedupeResolved && this.getEmiClicked
            : dedupeResolved;
    }

    get showAddApplicantsSection() {
        // Do not surface the Add / Change Applicants section until Check Eligibility has been run. 
        return (
            this.isBorrowerTabActive
            && this.eligibilityChecked
            && this.matches.length > 0
            && (this.canAddGuarantor || this.canAddBeneficiary || this.removableApplicants.length > 0)
        );
    }

    get validationButtonsDisabled() {
        return (
            this.isReadOnlyScreen
            || this.isCustomerDedupeCompleteForApplicant
            || (this.matchValidated && !!this.customerCode)
        );
    }

    get addApplicantsSectionKey() {
        const count = this.removableApplicants?.length || 0;
        return `add-applicants-${count}-${this.canAddGuarantor}-${this.canAddBeneficiary}`;
    }

    get isGetEmiButtonDisabled() {
        return (
            this.isReadOnlyScreen
            || this.isLoading
            || !this.isGetEmiReady
            || this.getEmiClicked
        );
    }

    get isGetEmiConfirmed() {
        return this.getEmiClicked;
    }

    get getEmiButtonClass() {
        let cls = 'p4-primary-btn p4-button-text';
        if (this.isGetEmiButtonDisabled && !this.isGetEmiConfirmed) {
            cls += ' p4-primary-btn-disabled';
        }
        if (this.isGetEmiConfirmed) {
            cls += ' p4-footer-btn--confirmed';
        }
        return cls;
    }

    get isCheckEligibilityButtonDisabled() {
        const emiGateOpen = !this.isExistingEmiRequired || this.getEmiClicked;
        return (
            this.isReadOnlyScreen
            || this.isLoading
            || !emiGateOpen
            || this.checkEligibilityClicked
            || this.checkEligibilityProcessing
            || !this.hasAnyRowValidated
            || !this.customerCode
        );
    }

    get isCheckEligibilityConfirmed() {
        return this.checkEligibilityClicked || this.eligibilityChecked;
    }

    get checkEligibilityButtonClass() {
        let cls = 'p4-primary-btn p4-button-text';
        if (this.isCheckEligibilityButtonDisabled && !this.isCheckEligibilityConfirmed) {
            cls += ' p4-primary-btn-disabled';
        }
        if (this.isCheckEligibilityConfirmed) {
            cls += ' p4-footer-btn--confirmed';
        }
        return cls;
    }

    get isNextButtonDisabled() {
        if (this.isNextNavigationInProgress) {
            return true;
        }
        if (this.isBorrowerDedupeReadOnly) {
            return true;
        }
        if (this.isViewingCompletedPastStage && !this.isBorrowerScreen) {
            return (
                this.isLoading
                || this.isSaving
                || this.stageIsComplete
                || this.isCustomerDedupeCompleteForApplicant
            );
        }
        if (this.stageIsComplete) {
            return true;
        }
        if (this.isReadOnlyScreen) {
            return this.isLoading || this.isSaving;
        }
        if (!this.hasAnyRowValidated) {
            return true;
        }
        if (this.isBorrowerScreen) {
            if (this.isCustomerDedupeCompleteForApplicant && !this.canAddMoreApplicants) {
                return true;
            }
            const emiGateOpen = !this.isExistingEmiRequired || this.getEmiClicked;
            if (!emiGateOpen) {
                return true;
            }
            if (!this.eligibilityChecked) {
                return true;
            }
            const hasYesToAddApplicant =
                this.borrowerAddGuarantorSelection === 'Yes'
                || this.borrowerAddBeneficiarySelection === 'Yes';
            if (hasYesToAddApplicant) {
                return this.isLoading || this.isSaving;
            }
            return this.isLoading || this.isSaving;
        }
        if (this.hasOtherApplicantsOfSameTypeNotAtStage) {
            return true;
        }
        return this.isLoading || this.isSaving || !this.isCurrentApplicantDedupeComplete;
    }

    get showPageFooter() {
        return true;
    }

    get showNextButton() {
        if (this.requiresBorrowerCombinedEligibilityRecheck) {
            return true;
        }
        if (this.isBorrowerScreen) {
            return !this.isApplicationPastDedupeStep && !this.isStagePast;
        }
        // Non-Borrower: NEXT only on the editable screen; hidden once dedupe is complete or on a green re-visit.
        return !this.isReadOnlyScreen;
    }

    get nextButtonClass() {
        return `p4-primary-btn p4-button-text${this.isNextButtonDisabled ? ' p4-primary-btn-disabled' : ''}`;
    }

    async handleGetExistingEmi() {
        if (this.isReadOnlyScreen || this.getEmiClicked || !this.isExistingEmiRequired) {
            return;
        }

        this.getEmiClicked = true;
        const cifId = this.resolveRequiredCifId();
        if (!cifId) {
            this.getEmiClicked = false;
            return;
        }
        const integrationParams = {
            cifId,
            applicantId: this._resolveApplicantIdForLoad()
        };

        this.handleIntegrationProgressUpdate({
            detail: {
                show: true,
                status: 'loading',
                currentStageIndex: 0,
                stages: GET_EMI_API_STAGES,
                errorMessage: ''
            }
        });

        try {
            const stage1Start = Date.now();
            const emiResult = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: 'getExistingEmiDetails',
                recordId: this.recordId,
                params: integrationParams
            });

            const stage1Elapsed = Date.now() - stage1Start;
            if (stage1Elapsed < NEXT_BUTTON_STAGE_MIN_DURATION_MS) {
                await new Promise((resolve) => setTimeout(resolve, NEXT_BUTTON_STAGE_MIN_DURATION_MS - stage1Elapsed));
            }

            if (!emiResult?.isSuccess) {
                this.getEmiClicked = false;
                this.handleIntegrationProgressUpdate({
                    detail: {
                        show: true,
                        status: 'error',
                        currentStageIndex: 0,
                        stages: GET_EMI_API_STAGES,
                        errorMessage: emiResult?.message || 'Get EMI details failed'
                    }
                });
                this.showToast('Error', emiResult?.message || 'Get EMI details failed', 'error');
                return;
            }

            this.showToast('Success', emiResult.message || 'EMI details retrieved', 'success');
            this.handleIntegrationProgressUpdate({
                detail: {
                    show: true,
                    status: 'loading',
                    currentStageIndex: GET_EMI_API_STAGES.length,
                    stages: GET_EMI_API_STAGES,
                    errorMessage: ''
                }
            });
        } catch (error) {
            this.getEmiClicked = false;
            console.error('Error in handleGetExistingEmi:', error);
            this.handleIntegrationProgressUpdate({
                detail: {
                    show: true,
                    status: 'error',
                    currentStageIndex: 0,
                    stages: GET_EMI_API_STAGES,
                    errorMessage: error?.body?.message || error?.message || 'Get EMI details failed'
                }
            });
            this.showToast('Error', error?.body?.message || error?.message || 'Get EMI details failed', 'error');
        } finally {
            setTimeout(() => {
                this.handleIntegrationProgressUpdate({ detail: { show: false, status: 'success' } });
            }, 800);
        }
    }

    handleIntegrationProgressUpdate(event) {
        const d = event.detail || {};
        this.showIntegrationProgressModal = d.show !== false;
        this.integrationProgressModalStatus = d.status || 'loading';
        this.integrationProgressModalCurrentStageIndex = d.currentStageIndex ?? 0;
        this.integrationProgressModalStages = d.stages || [];
        this.integrationProgressModalErrorMessage = d.errorMessage || '';
        this.integrationProgressModalSuccessMessage = d.successMessage || '';
        if (d.header) {
            this.integrationProgressModalHeader = d.header;
        }
    }

    handleIntegrationProgressModalClose() {
        this.showIntegrationProgressModal = false;
    }

    handleIntegrationProgressModalRetry() {
        this.integrationProgressModalStatus = 'loading';
        this.integrationProgressModalCurrentStageIndex = 0;
        this.integrationProgressModalErrorMessage = '';

        const stages = this.integrationProgressModalStages || [];
        if (isDedupeForwardStageLabels(stages)) {
            this.runNextForwardIntegrationChain();
        }
    }

    handleIntegrationProgressModalDone() {
        this.showIntegrationProgressModal = false;
        this.loadPageData({ silent: true });
    }

    resolveRequiredCifId(explicitCifId) {
        const cifId = String(explicitCifId || this.customerCode || '').trim();
        if (!cifId) {
            this.showToast(
                'Validation',
                'Complete customer dedupe (Valid/Invalid) or select a match before continuing.',
                'warning'
            );
            return null;
        }
        return cifId;
    }

    showToast(title, message, variant = 'info') {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}