/**
 * applicationMasterPage
 * ─────────────────────────────────────────────────────────────────────────────
 * Listens to the `losmenuselect` window event published by stageMenu.
 * Reads the `overrideLwc` field (populated from Dynamic_Stage_Gate__mdt.Override_LWC__c)
 * and dynamically renders the matching LWC via import(`c/${name}`).
 *
 * No registry. No hardcoded imports. Any deployed LWC in the org
 * whose API name matches Override_LWC__c is loaded automatically.
 *
 * Multi-applicant group rows (Guarantor / Co-Borrower with 2+ applicants) load
 * listOfApplicants first; card selection drills into the step Override_LWC.
 *
 * Prerequisites (org-level, one-time):
 *   • Lightning Web Security must be enabled  (Setup → Session Settings)
 *   • lightning__dynamicComponent capability is declared in the .js-meta.xml
 * ─────────────────────────────────────────────────────────────────────────────
 */

import { LightningElement, api, track } from 'lwc';
import discardSubApplicantShell from '@salesforce/apex/ApplicantSubService.discardSubApplicantShell';

const LOS_MENU_SELECT_EVENT = 'losmenuselect';
const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const APPLICATION_STATUS_EVENT = 'applicationStatusChanged';

const DEFAULT_APPLICATION_STATUS = {
    isRevoked: false,
    isWithdrawn: false
};

export default class ApplicationMasterPage extends LightningElement {

    /** Cached losmenuselect — dynamic import can finish after the event fires. */
    static _lastMenuSelectDetail = null;

    /** Record Id from the page context (Application__c). */
    @api recordId;

    // ── Reactive state ────────────────────────────────────────────────────────
    @track activeComponentCtor = null;
    @track componentProps = {};

    @track activeStageTab       = '';
    @track activeStageLabel     = '';
    @track activeStagePhrase    = '';
    @track isStagePast          = false;

    /** Passed through to the child so it can dispatch losnextstage correctly. */
    @track activeCurrentViewId  = '';
    @track activeApplicantId    = '';

    /** Set when the import() call fails (component not found / not deployed). */
    @track isUnknownComponent   = false;
    @track unknownComponentName = '';


    @track isLoadingStage = false;

    /** Per-applicant step completion from losnextstage (listOfApplicants SUBMITTED state). */
    applicantCompletionMap = {};

    @track applicationStatus = { ...DEFAULT_APPLICATION_STATUS };

    // ── Computed ──────────────────────────────────────────────────────────────
    get hasActiveComponent() { return this.activeComponentCtor !== null; }
    get showPlaceholder()    { return !this.hasActiveComponent && !this.isUnknownComponent; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    _menuSelectHandler;
    _nextStageHandler;
    _applicationStatusHandler;

    connectedCallback() {
        this._menuSelectHandler = this._handleMenuSelect.bind(this);
        this._nextStageHandler = this._handleNextStage.bind(this);
        this._applicationStatusHandler = this.handleApplicationStatusChanged.bind(this);
        window.addEventListener(LOS_MENU_SELECT_EVENT, this._menuSelectHandler);
        window.addEventListener(LOS_NEXT_STAGE_EVENT, this._nextStageHandler);
        window.addEventListener(APPLICATION_STATUS_EVENT, this._applicationStatusHandler);
    }

    disconnectedCallback() {
        window.removeEventListener(LOS_MENU_SELECT_EVENT, this._menuSelectHandler);
        window.removeEventListener(LOS_NEXT_STAGE_EVENT, this._nextStageHandler);
        window.removeEventListener(APPLICATION_STATUS_EVENT, this._applicationStatusHandler);
    }

    // ── Event handler ─────────────────────────────────────────────────────────
    _handleNextStage(event) {
        const { applicantId, currentLoanStageComplete } = event.detail || {};
        if (applicantId && currentLoanStageComplete) {
            this.applicantCompletionMap = {
                ...this.applicantCompletionMap,
                [applicantId]: currentLoanStageComplete
            };
        }
    }

    /** Listens for applicationStatusChanged from applicationOverview. */
    handleApplicationStatusChanged(event) {
        const { applicationStatus, recordId } = event?.detail || {};
        if (!applicationStatus?.isWithdrawn) {
            return;
        }
        if (recordId && this.recordId && recordId !== this.recordId) {
            return;
        }

        this.applicationStatus = {
            ...this.applicationStatus,
            ...applicationStatus
        };
        this.syncApplicationStatusToActiveChild();
    }

    syncApplicationStatusToActiveChild() {
        if (!this.activeComponentCtor) {
            return;
        }
        this.componentProps = {
            ...this.componentProps,
            applicationStatus: { ...this.applicationStatus }
        };
    }

    /** Discards an untouched sub-applicant shell when the user navigates away from it. */
    _maybeDiscardPendingSubShell(nextApplicantId) {
        const pendingId = window.__mogaPendingSubShellId;
        if (!pendingId || pendingId === nextApplicantId) {
            return;
        }
        window.__mogaPendingSubShellId = null;
        // Best-effort, idempotent: server only deletes a shell whose Basic Details was never saved.
        discardSubApplicantShell({ applicantId: pendingId })
            .then((res) => {
                if (res?.isSuccess) {
                    window.dispatchEvent(new CustomEvent('losmenurefresh', { bubbles: true, composed: true }));
                }
            })
            .catch(() => {
                /* abandoned-shell cleanup is best-effort */
            });
    }

    buildStageComponentProps(overrides = {}) {
        return {
            recordId: this.recordId,
            applicationStatus: { ...this.applicationStatus },
            ...overrides
        };
    }

    async _handleMenuSelect(event) {
        console.log('@@@@ _handleMenuSelect', JSON.stringify(event.detail));
        const {
            tab         = '',
            label       = '',
            stagePhrase = '',
            overrideLwc = '',
            isStagePast = false,
            id          = '',
            applicantId = '',
            applicantType = '',
            isGroupItem = false,
            applicants = [],
            subCreationLocked = false,
        } = event.detail || {};

        ApplicationMasterPage._lastMenuSelectDetail = event.detail || {};

        // Single-in-progress cleanup: if an untouched sub shell was created (toggle/"+"), but the
        // user navigates to a different applicant before Basic Details NEXT, discard the empty shell.
        this._maybeDiscardPendingSubShell(applicantId);

        this.activeStageTab      = tab;
        this.activeStageLabel    = label || tab;
        this.activeStagePhrase   = stagePhrase;
        this.isStagePast         = isStagePast;
        this.activeCurrentViewId = id;
        this.activeApplicantId   = applicantId || '';

        // Multi-Grid group (2+ guarantors/co-borrowers) → listOfApplicants card picker
        if (isGroupItem === true && Array.isArray(applicants) && applicants.length > 0) {
            this.isLoadingStage = true;
            try {
                const module = await import('c/listOfApplicants');
                this.activeComponentCtor  = module.default;
                this.componentProps = this.buildStageComponentProps({
                    applicants,
                    applicantCompletionOverrides: this.applicantCompletionMap,
                    groupLabel: applicantType || tab,
                    tab: tab || '',
                    stagePhrase: stagePhrase || '',
                    currentViewId: id,
                    overrideLwc: overrideLwc || '',
                    subCreationLocked
                });
                this.isUnknownComponent   = false;
                this.unknownComponentName = '';
            } catch (err) {
                this.activeComponentCtor  = null;
                this.isUnknownComponent   = true;
                this.unknownComponentName = 'listOfApplicants';
                console.error('[applicationMasterPage] Could not load listOfApplicants:', err);
            } finally {
                this.isLoadingStage = false;
            }
            return;
        }

        const ctorName = overrideLwc?.trim();

        if (!ctorName) {
            this.activeComponentCtor  = null;
            this.componentProps = {};
            this.isUnknownComponent   = false;
            this.unknownComponentName = '';
            return;
        }

        this.isLoadingStage = true;
        try {
            // ── Dynamic import driven entirely by Override_LWC__c ─────────────
            // Template-literal imports are supported by the LWC runtime when
            // lightning__dynamicComponent capability is declared and LWS is on.
            // The strict-mode lint rule is relaxed for this file in eslint.config.js.
            const module = await import(`c/${ctorName}`);
            const cachedDetail = ApplicationMasterPage._lastMenuSelectDetail || {};
            if (ctorName === 'wheelsIndividualKYCMasterPage') {
                module.default._lastMenuDetail = cachedDetail;
            }
            this.activeComponentCtor  = module.default;
            this.componentProps = this.buildStageComponentProps({
                currentViewId: id || cachedDetail.id || '',
                stagePhrase: stagePhrase || cachedDetail.stagePhrase || cachedDetail.currentStagePhrase || '',
                tab: tab || cachedDetail.tab || '',
                applicantId: applicantId || cachedDetail.applicantId || '',
                applicantType: applicantType || cachedDetail.applicantType || '',
                isStagePast: isStagePast
            });
            this.isUnknownComponent   = false;
            this.unknownComponentName = '';
        } catch (err) {
            this.activeComponentCtor  = null;
            this.componentProps = {};
            this.isUnknownComponent   = true;
            this.unknownComponentName = ctorName;
            console.error(`[applicationMasterPage] Could not load component "c/${ctorName}":`, err);
        } finally {
            this.isLoadingStage = false;
        }
    }
}