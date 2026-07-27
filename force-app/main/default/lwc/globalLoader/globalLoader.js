import { LightningElement, api, track } from 'lwc';

/**
 * globalLoader
 * --------------------------------------------------------------------------
 * Single app-level backdrop + spinner used during long Next-click flows
 * (save, integrations, navigation to next stage). Replaces multiple
 * per-card spinners that would otherwise stack on top of each other.
 *
 * Activation contract - TWO ways to drive it:
 *
 *   (A) Imperative @api setters - for direct parent->loader control:
 *           <c-global-loader visible={loaderVisible} message={loaderMessage}>
 *           </c-global-loader>
 *
 *   (B) Window CustomEvent 'losgloballoader' - for fire-and-forget from any
 *       descendant component anywhere in the LOS app surface:
 *           window.dispatchEvent(new CustomEvent('losgloballoader',
 *               { detail: { show: true, message: 'Saving Basic Details...' } }));
 *           window.dispatchEvent(new CustomEvent('losgloballoader',
 *               { detail: { show: false } }));
 *
 *       Show requests are reference-counted so overlapping flows don't
 *       prematurely hide the loader: each show increments the counter, each
 *       hide decrements; backdrop visible while counter > 0.
 *       A safety timeout (default 60s) auto-resets the counter to avoid
 *       sticky overlays if a hide event is ever lost.
 *
 * Mirrors MOGA DEMO's sfLOSGlobalLoader contract verbatim.
 */

const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader';
const SAFETY_TIMEOUT_MS = 60000;

export default class GlobalLoader extends LightningElement {
    @api defaultMessage = 'Processing...';

    @track _explicitVisible = false;
    @track _eventCounter = 0;
    @track _eventMessage = '';

    _windowHandler;
    _safetyTimer;

    @api
    get visible() {
        return this._explicitVisible || this._eventCounter > 0;
    }
    set visible(v) {
        this._explicitVisible = !!v;
    }

    @api message;

    get resolvedMessage() {
        return this.message || this._eventMessage || this.defaultMessage;
    }

    connectedCallback() {
        this._windowHandler = this._handleWindowEvent.bind(this);
        window.addEventListener(LOS_GLOBAL_LOADER_EVENT, this._windowHandler);
    }

    disconnectedCallback() {
        if (this._windowHandler) {
            window.removeEventListener(LOS_GLOBAL_LOADER_EVENT, this._windowHandler);
        }
        this._clearSafetyTimer();
    }

    _handleWindowEvent(event) {
        const detail = event?.detail || {};
        const show = !!detail.show;
        if (show) {
            this._eventCounter += 1;
            if (typeof detail.message === 'string' && detail.message.trim()) {
                this._eventMessage = detail.message;
            }
            this._armSafetyTimer();
        } else {
            if (this._eventCounter > 0) {
                this._eventCounter -= 1;
            }
            if (this._eventCounter === 0) {
                this._eventMessage = '';
                this._clearSafetyTimer();
            }
        }
    }

    _armSafetyTimer() {
        this._clearSafetyTimer();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._safetyTimer = setTimeout(() => {
            this._eventCounter = 0;
            this._eventMessage = '';
        }, SAFETY_TIMEOUT_MS);
    }

    _clearSafetyTimer() {
        if (this._safetyTimer) {
            clearTimeout(this._safetyTimer);
            this._safetyTimer = null;
        }
    }
}