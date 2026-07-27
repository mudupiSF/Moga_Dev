import { LightningElement, api, track } from 'lwc';

const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader';
const SAFETY_TIMEOUT_MS = 60000;

export default class GlobalSpinner extends LightningElement {
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