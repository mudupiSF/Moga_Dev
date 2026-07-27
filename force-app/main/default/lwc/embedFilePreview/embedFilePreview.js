import { LightningElement, api } from 'lwc';

const IMAGE_TYPES = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'];
const VIDEO_TYPES = ['mp4', 'webm', 'mov', 'm4v'];
const EXCEL_TYPES = ['xlsx', 'xls', 'csv'];

/**
 * Standalone preview modal. Resolves a file's type from its extension and
 * delegates rendering to the matching embedPreview* child. The host supplies
 * the file identity and chrome flags; this component owns the modal shell.
 */
export default class EmbedFilePreview extends LightningElement {
    @api contentVersionId;
    @api contentDocumentId;
    @api fileName = '';
    @api fileExtension = '';
    @api iconName;
    @api sessionId;
    @api vfRoot;
    @api preventDownload = false;
    @api canDownload = false;

    get _ext()    { return (this.fileExtension || '').toLowerCase(); }
    get isImage() { return IMAGE_TYPES.includes(this._ext); }
    get isVideo() { return VIDEO_TYPES.includes(this._ext); }
    get isExcel() { return EXCEL_TYPES.includes(this._ext); }
    get isPdf()   { return this._ext === 'pdf'; }
    get isDocx()  { return this._ext === 'docx'; }
    get isOther() {
        return !this.isImage && !this.isVideo && !this.isPdf && !this.isExcel && !this.isDocx;
    }

    handleOverlayClick() { this.handleClose(); }
    stopPropagation(evt) { evt.stopPropagation(); }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }

    handleDownload() {
        if (!this.contentVersionId) return;
        const url = `${this.vfRoot}/sfc/servlet.shepherd/version/download/${this.contentVersionId}`;
        window.open(url, '_blank', 'noopener');
    }
}