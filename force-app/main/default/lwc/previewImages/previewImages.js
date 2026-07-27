import { LightningElement, api, track } from 'lwc';

export default class PreviewImages extends LightningElement {
    @api sessionId;
    @api vfRoot;
    @api fileName = '';

    @track isLoading   = false;
    @track errorMsg    = '';
    @track rotation    = 0;
    @track scalePercent = 100;

    _scale             = 1.0;
    _contentVersionId  = null;

    @api
    get contentVersionId() { return this._contentVersionId; }
    set contentVersionId(value) {
        this._contentVersionId = value;
        if (value) Promise.resolve().then(() => this._loadImage());
    }

    _loadImage() {
        if (!this._contentVersionId) return;
        this._scale      = 1.0;
        this.rotation    = 0;
        this.scalePercent = 100;
        this.isLoading   = true;
        this.errorMsg    = '';

        // Shepherd URL uses the browser's cookie session — no fetch/blob/Bearer needed
        const img = this.template.querySelector('[data-id="previewImg"]');
        if (img) {
            img.src = `/sfc/servlet.shepherd/version/download/${this._contentVersionId}`;
        }
    }

    handleImageLoad()  { this.isLoading = false; }
    handleImageError() { this.isLoading = false; this.errorMsg = 'Failed to display image.'; }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }

    rotateLeft()  { this.rotation = (this.rotation - 90 + 360) % 360; this._applyTransform(); }
    rotateRight() { this.rotation = (this.rotation + 90) % 360;        this._applyTransform(); }

    zoomIn() {
        this._scale = Math.min(this._scale + 0.25, 4.0);
        this.scalePercent = Math.round(this._scale * 100);
        this._applyTransform();
    }

    zoomOut() {
        this._scale = Math.max(this._scale - 0.25, 0.25);
        this.scalePercent = Math.round(this._scale * 100);
        this._applyTransform();
    }

    reset() {
        this._scale   = 1.0;
        this.rotation = 0;
        this.scalePercent = 100;
        this._applyTransform();
    }

    _applyTransform() {
        const img = this.template.querySelector('[data-id="previewImg"]');
        if (img) img.style.transform = `rotate(${this.rotation}deg) scale(${this._scale})`;
    }
}