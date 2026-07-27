import { LightningElement, api, track } from 'lwc';

export default class PreviewVideo extends LightningElement {
    @api sessionId        = '';
    @api vfRoot           = '';
    @api fileName         = '';
    @api contentVersionId = '';

    @track videoUrl  = '';
    @track errorMsg  = '';

    _contentDocumentId = null;

    @api
    get contentDocumentId() { return this._contentDocumentId; }
    set contentDocumentId(value) {
        this._contentDocumentId = value;
        if (value) {
            this.videoUrl = '/sfc/servlet.shepherd/document/download/' + value;
        }
    }

    handleDownload() {
        const a    = document.createElement('a');
        a.href     = this.videoUrl;
        a.download = this.fileName || 'video';
        a.click();
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
}