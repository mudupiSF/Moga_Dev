import { LightningElement, api, track } from 'lwc';
import { loadScript }       from 'lightning/platformResourceLoader';
import mammothResource      from '@salesforce/resourceUrl/mammoth';
import getFileContentBase64 from '@salesforce/apex/CustomFileUploadV2Controller.getFileContentBase64';

export default class PreviewDocx extends LightningElement {
    @api sessionId;
    @api vfRoot;
    @api fileName = '';

    @track isLoading    = false;
    @track errorMsg     = '';
    @track scalePercent = 100;

    _scale            = 1.0;
    _contentVersionId = null;
    _mammothLoaded    = false;
    _shepherdUrl      = null;

    @api
    get contentVersionId() { return this._contentVersionId; }
    set contentVersionId(value) {
        this._contentVersionId = value;
        this._shepherdUrl = value ? `/sfc/servlet.shepherd/version/download/${value}` : null;
        if (value && this._mammothLoaded) this._loadDocx();
    }

    get contentStyle() {
        return `font-size: ${this._scale}rem; line-height: 1.6;`;
    }

    connectedCallback() {
        loadScript(this, mammothResource)
            .then(() => {
                this._mammothLoaded = true;
                if (this._contentVersionId) this._loadDocx();
            })
            .catch(err => {
                this.errorMsg = 'Failed to load mammoth.js: ' + (err && err.message ? err.message : String(err));
            });
    }

    _loadDocx() {
        if (!this._contentVersionId) return;
        this.isLoading = true;
        this.errorMsg  = '';

        // Apex returns base64 — avoids LWS binary fetch restriction
        getFileContentBase64({ contentVersionId: this._contentVersionId })
            .then(base64 => {
                const binary = atob(base64);
                const bytes  = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
                // loadScript puts mammoth on window — do NOT use the import as a value
                return window.mammoth.convertToHtml({ arrayBuffer: bytes.buffer });
            })
            .then(result => {
                this.isLoading = false;
                return Promise.resolve().then(() => {
                    const container = this.template.querySelector('[data-id="docxContent"]');
                    if (container) {
                        // eslint-disable-next-line lwc/no-inner-html
                        container.innerHTML = result.value;
                    }
                });
            })
            .catch(err => {
                this.isLoading = false;
                this.errorMsg  = 'Failed to render DOCX: ' + (err && err.body ? err.body.message : String(err));
            });
    }

    handleZoomIn() {
        this._scale = Math.min(parseFloat((this._scale + 0.1).toFixed(1)), 3.0);
        this.scalePercent = Math.round(this._scale * 100);
    }

    handleZoomOut() {
        this._scale = Math.max(parseFloat((this._scale - 0.1).toFixed(1)), 0.5);
        this.scalePercent = Math.round(this._scale * 100);
    }

    handleDownload() {
        if (!this._shepherdUrl) return;
        const a    = document.createElement('a');
        a.href     = this._shepherdUrl;
        a.download = this.fileName || 'document.docx';
        a.click();
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
}