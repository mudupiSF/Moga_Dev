import { LightningElement, api, track } from 'lwc';

export default class PreviewPDFV2 extends LightningElement {
    @api sessionId;
    @api vfRoot;
    @api fileName = '';

    @track scalePercent = 100;
    @track isLoading    = false;
    @track errorMsg     = '';

    _scale             = 1.0;
    _contentVersionId  = null;

    @api
    get contentVersionId() { return this._contentVersionId; }
    set contentVersionId(value) {
        this._contentVersionId = value;
        if (value) Promise.resolve().then(() => this._loadPdf());
    }

    _loadPdf() {
        if (!this._contentVersionId || !this.vfRoot) return;
        this.isLoading = true;
        this.errorMsg  = '';

        const vfPageUrl = `${this.vfRoot}/apex/PdfViewer?cvId=${encodeURIComponent(this._contentVersionId)}`;

        this.isLoading = false;
        const iframe = this.template.querySelector('[data-id="pdfFrame"]');
        if (iframe) {
            iframe.src = vfPageUrl;
            this._applyZoom();
        }
    }

    handleZoomIn() {
        this._scale = Math.min(parseFloat((this._scale + 0.25).toFixed(2)), 3.0);
        this.scalePercent = Math.round(this._scale * 100);
        this._applyZoom();
    }

    handleZoomOut() {
        this._scale = Math.max(parseFloat((this._scale - 0.25).toFixed(2)), 0.5);
        this.scalePercent = Math.round(this._scale * 100);
        this._applyZoom();
    }

    _applyZoom() {
        const wrapper = this.template.querySelector('[data-id="iframeWrapper"]');
        if (wrapper) {
            wrapper.style.transform       = `scale(${this._scale})`;
            wrapper.style.transformOrigin = 'top left';
            wrapper.style.width           = `${100 / this._scale}%`;
        }
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
}