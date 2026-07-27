import { LightningElement, api, track } from 'lwc';
import { loadScript }       from 'lightning/platformResourceLoader';
import sheetJS              from '@salesforce/resourceUrl/sheetJS';
import getFileContentBase64 from '@salesforce/apex/embedCustomFilePreviewController.getFileContentBase64';

export default class EmbedPreviewExcel extends LightningElement {
    @api sessionId;
    @api vfRoot;
    @api fileName = '';

    @track isLoading   = false;
    @track errorMsg    = '';
    @track activeSheet = '';

    _workbook         = null;
    _sheetJsLoaded    = false;
    _sheets           = [];
    _contentVersionId = null;

    @api
    get contentVersionId() { return this._contentVersionId; }
    set contentVersionId(value) {
        this._contentVersionId = value;
        if (value && this._sheetJsLoaded) this._loadExcel();
    }

    get sheetTabs() {
        return this._sheets.map(name => ({
            name,
            tabClass: name === this.activeSheet ? 'sheet-tab sheet-tab-active' : 'sheet-tab'
        }));
    }

    connectedCallback() {
        loadScript(this, sheetJS)
            .then(() => {
                this._sheetJsLoaded = true;
                if (this._contentVersionId) this._loadExcel();
            })
            .catch(err => {
                this.errorMsg = 'Failed to load SheetJS: ' + (err && err.message ? err.message : String(err));
            });
    }

    _loadExcel() {
        if (!this._contentVersionId) return;
        this.isLoading   = true;
        this.errorMsg    = '';
        this._workbook   = null;
        this._sheets     = [];
        this.activeSheet = '';

        // Apex returns base64 — no fetch, no LWS binary restriction
        getFileContentBase64({ contentVersionId: this._contentVersionId })
            .then(base64 => {
                const binary = atob(base64);
                const bytes  = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
                // eslint-disable-next-line no-undef
                const wb = XLSX.read(bytes, { type: 'array' });
                this._workbook = wb;
                this._sheets   = wb.SheetNames;
                if (this._sheets.length > 0) {
                    this.activeSheet = this._sheets[0];
                    this._renderSheet(this.activeSheet);
                } else {
                    this.errorMsg = 'No sheets found in the file.';
                }
                this.isLoading = false;
            })
            .catch(err => {
                this.errorMsg  = 'Failed to load file: ' + (err && err.body ? err.body.message : String(err));
                this.isLoading = false;
            });
    }

    switchSheet(event) {
        const name = event.currentTarget.dataset.name;
        if (name && name !== this.activeSheet) {
            this.activeSheet = name;
            this._renderSheet(name);
        }
    }

    _renderSheet(sheetName) {
        if (!this._workbook || !this._workbook.Sheets[sheetName]) return;
        // eslint-disable-next-line no-undef
        const html      = XLSX.utils.sheet_to_html(this._workbook.Sheets[sheetName]);
        const container = this.template.querySelector('[data-id="tableContainer"]');
        if (container) {
            // eslint-disable-next-line lwc/no-inner-html
            container.innerHTML = html;
        }
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
}