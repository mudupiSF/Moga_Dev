import { LightningElement, api } from 'lwc';

const DEFAULT_STAGES = [
    'Validating application data...',
    'Encrypting sensitive information...',
    'Syncing with financial gateway...',
    'Finalizing background updates...'
];

// Default UX pacing for the generic runProgress() orchestrator. Tuned so each
// API stage's spinner-to-tick transition is clearly perceivable (300 ms) and
// the all-green-ticks success state holds long enough for the user to
// register the completion (700 ms) before the caller swaps in the next
// surface (e.g. eKYC link modal, OTP entry modal, etc.).
const DEFAULT_PER_STAGE_MS    = 300;
const DEFAULT_SUCCESS_HOLD_MS = 700;

export default class IntegrationProgressModal extends LightningElement {
    /** Status: 'loading' | 'success' | 'error' */
    @api status = 'loading';
    @api header = '';
    @api successMessage = '';

    /** Current stage index (0-based). Used when status is 'loading'. */
    @api currentStageIndex = 0;

    /** Array of stage labels. Defaults to standard integration stages. */
    _stages = [];
    @api
    get stages() {
        return this._stages?.length > 0 ? this._stages : DEFAULT_STAGES;
    }
    set stages(value) {
        this._stages = Array.isArray(value) ? value : [];
    }

    /** Error message shown when status is 'error'. */
    @api errorMessage = 'We encountered an issue while processing. Please check your connection and try again.';

    // Guards against concurrent runProgress() invocations (e.g. user
    // double-tapping Verify).
    _orchestrationLock = false;

    get isLoading() {
        return this.status === 'loading';
    }

    get isSuccess() {
        return this.status === 'success';
    }

    get isError() {
        return this.status === 'error';
    }

    get canClose() {
        return this.isSuccess || this.isError;
    }

    /** Show header with close button only when modal can be closed (success/error) */
    get showHeader() {
        return this.header !== '' && this.header !== null && this.header !== undefined;
    }

    get stagesWithStatus() {
        const list = this.stages;
        const current = this.currentStageIndex;
        return list.map((label, index) => {
            const isComplete = index < current;
            const isCurrent = index === current;
            return {
                key: `stage-${index}`,
                label,
                number: index + 1,
                isComplete,
                isCurrent,
                stageClass: `progress-stage-item ${isCurrent ? 'progress-stage-current' : ''} ${isComplete ? 'progress-stage-complete' : ''} ${!isComplete && !isCurrent ? 'progress-stage-pending' : ''}`,
                badgeClass: `progress-stage-badge ${isComplete ? 'progress-badge-complete' : ''} ${isCurrent ? 'progress-badge-current' : ''} ${!isComplete && !isCurrent ? 'progress-badge-pending' : ''}`,
                labelClass: `progress-stage-label ${isCurrent ? 'progress-label-current' : ''}`
            };
        });
    }

    handleClose() {
        if (this.canClose) {
            this.dispatchEvent(new CustomEvent('close'));
        }
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry', {
            detail: {
                header: this.header
            }
        }));
    }

    handleDone() {
        this.dispatchEvent(new CustomEvent('done'));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Generic orchestrator API
    // ─────────────────────────────────────────────────────────────────────
    //
    // The two surface options below are :
    //   - Attribute binding (existing pattern) — caller drives status,
    //     stages, currentStageIndex via @api props. Useful when the work
    //     is itself stage-aware (e.g. streamed progress events).
    //   - runProgress() (new pattern) — caller hands over a list of stages
    //     and lets the modal animate it for them. Useful for single-shot
    //     API calls that nominally cover several backend stages.

    /**
     * Designed to be reusable across screens that share the same UX:
     * Aadhaar eKYC OTP, Mobile OTP, Email OTP, dedupe checks, anything
     * that fires an integration call and wants a clear "progressing →
     * complete" visual punctuation before the next pop-up.
     *
     * @param {Object}   [opts]
     * @param {string[]} [opts.stages]         Stage labels to walk through.
     *                                         Falls back to the currently-bound
     *                                         `stages` property when omitted,
     *                                         so callers that already pre-bound
     *                                         stages via attribute can just
     *                                         call `runProgress()` with no args.
     * @param {number}   [opts.perStageMs=300] Per-stage spinner-to-tick dwell.
     * @param {number}   [opts.successHoldMs=700] Hold time on all-green-ticks
     *                                         before resolving.
     * @returns {Promise<void>} Resolves once the success-hold completes.
     */
    @api
    async runProgress(opts) {
        if (this._orchestrationLock) {
            return;
        }
        const passedStages    = opts && Array.isArray(opts.stages) ? opts.stages : null;
        const perStageMs      = (opts && Number.isFinite(opts.perStageMs))     ? opts.perStageMs     : DEFAULT_PER_STAGE_MS;
        const successHoldMs   = (opts && Number.isFinite(opts.successHoldMs))  ? opts.successHoldMs  : DEFAULT_SUCCESS_HOLD_MS;
        const effectiveStages = (passedStages && passedStages.length > 0) ? passedStages : this._stages;

        if (!Array.isArray(effectiveStages) || effectiveStages.length === 0) {
            return;
        }

        this._orchestrationLock = true;
        try {
            if (passedStages) {
                this.stages = passedStages;
            }
            this.status            = 'loading';
            this.errorMessage      = '';
            this.currentStageIndex = 0;

            // Walk through the stages. The render layer treats any stage with
            // `index < currentStageIndex` as complete (green tick), so we just
            // bump the pointer after each pacing pause.
            for (let i = 1; i <= effectiveStages.length; i++) {
                await this._sleep(perStageMs);
                this.currentStageIndex = i;
            }
            // Hold the all-green-ticks state so the user can visually register
            // every stage completing before the caller swaps to the next view.
            await this._sleep(successHoldMs);
        } finally {
            this._orchestrationLock = false;
        }
    }

    /**
     * Snaps the modal into the error view with the supplied message.
     * @param {string} message Human-readable failure message.
     */
    @api
    fail(message) {
        this.status       = 'error';
        this.errorMessage = message || 'We encountered an issue while processing. Please check your connection and try again.';
    }

    _sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
}