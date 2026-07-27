import { LightningElement, api } from 'lwc';

/** Default confirmation config when using componentName="confirmation" */
const DEFAULT_CONFIRM_BUTTONS = [
    { label: 'Cancel', value: 'cancel', variant: 'neutral' },
    { label: 'Confirm', value: 'confirm', variant: 'brand' }
];


export default class DynamicComponentModal extends LightningElement {
    componentCtor = null;
    _componentName = '';
    _propsJson = null;

    @api recordId;
    @api modalHeader;

    /**
     * Props for dynamic component, or for confirmation mode:
     *   { title?: string, message: string, buttons?: [{ label, value, variant }] }
     */
    @api componentProps = {};

    @api
    get componentName() {
        return this._componentName;
    }
    set componentName(value) {
        this._componentName = value || '';
        if (this._componentName !== 'confirmation') {
            this.loadComponent();
        }
    }

    get hasComponent() {
        return !!this.componentCtor;
    }

    /** True when componentName is "confirmation" - renders inline confirmation UI */
    get isConfirmationMode() {
        return this._componentName === 'confirmation';
    }

    get confirmationTitle() {
        return this.componentProps?.title || 'Confirm';
    }

    get confirmationMessage() {
        return this.componentProps?.message || '';
    }

    get confirmationButtons() {
        const btns = this.componentProps?.buttons;
        return Array.isArray(btns) && btns.length > 0 ? btns : DEFAULT_CONFIRM_BUTTONS;
    }

    get confirmationTitleId() {
        return 'confirmation-modal-title';
    }

    /** aria-labelledby only in confirmation mode; component mode has its own heading */
    get ariaLabelledBy() {
        return this.isConfirmationMode ? this.confirmationTitleId : undefined;
    }

    get modalContainerClass() {
        if (this.isConfirmationMode) {
            return 'slds-modal__container modal-container-dynamic modal-container-confirmation';
        }
        // The Advanced File Management hub needs more room - so render it at 80% of the screen.
        if (this._componentName === 'embedCustomFilePreview') {
            return 'slds-modal__container modal-container-dynamic modal-container-wide';
        }
        return 'slds-modal__container modal-container-dynamic';
    }

    /** Prefer record id from component props (e.g. FI investigation id) over the host record id. */
    get childRecordId() {
        return this.componentProps?.recordId || this.recordId;
    }

    /** Bind key modal props as attributes so dynamic children receive them before connectedCallback. */
    get childVerificationId() {
        return this.componentProps?.verificationId || undefined;
    }

    get childApplicationId() {
        return this.componentProps?.applicationId || undefined;
    }

    get childApplicantId() {
        return this.componentProps?.applicantId || undefined;
    }

    get childRenderAsReadOnly() {
        return this.componentProps?.renderAsReadOnly === true;
    }

    async loadComponent() {
        try {
            if (!this._componentName || this._componentName === 'confirmation') {
                this.componentCtor = null;
                return;
            }
            this.modalHeader = this.componentProps?.modalHeader || '';
            this._propsJson = null;
            const module = await import(`c/${this._componentName}`);
            this.componentCtor = module?.default || null;
            this._applyComponentProps();
        } catch (e) {
            console.error(`[sfLOSDynamicComponentModal] Failed to load component: ${this._componentName}`, e);
            this.componentCtor = null;
        }
    }

    renderedCallback() {
        this._applyComponentProps();
    }

    _applyComponentProps() {
        if (!this.componentCtor || !this.componentProps) return;
        const el = this.template.querySelector('[data-id="dynamic-child"]');
        if (!el) return;

        const propsJson = JSON.stringify(this.componentProps);
        if (propsJson === this._propsJson) {
            return;
        }
        this._propsJson = propsJson;

        Object.keys(this.componentProps).forEach((key) => {
            try {
                el[key] = this.componentProps[key];
            } catch (_) {
                /* skip non-api props */
            }
        });

        if (typeof el.loadData === 'function') {
            el.loadData();
        }
    }

    _closing = false;

    handleChildClose(event) {
        const child = this.template.querySelector('[data-id="dynamic-child"]');
        if (!child) {
            return;
        }
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        if (path.length > 0 && path[0] !== child) {
            event?.stopPropagation?.();
            return;
        }

        if (event.target !== child) {
            event?.stopPropagation?.();
            return;
        }
        const saved = event?.detail?.saved === true;
        this._dispatchClose(saved);
    }

    handleClose() {
        this._dispatchClose(false);
    }

    _dispatchClose(saved = false) {
        if (this._closing) return;
        this._closing = true;
        const child = this.template.querySelector('[data-id="dynamic-child"]');
        if (child && typeof child.handleClose === 'function') {
            try { child.handleClose(); } catch (_) { /* child cleanup must not block modal close */ }
        }
        this.dispatchEvent(new CustomEvent('close', { detail: { saved } }));
    }

    handleConfirmationAction(event) {
        const value = event.currentTarget?.dataset?.value ?? '';
        this.dispatchEvent(new CustomEvent('action', { detail: { value } }));
        this.dispatchEvent(new CustomEvent('close'));
    }
}