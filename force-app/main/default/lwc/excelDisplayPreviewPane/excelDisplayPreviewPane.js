import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/sheetJS';
import getExcelFileBase64 from '@salesforce/apex/FileDisplayPreviewPaneController.getExcelFileBase64';

export default class ExcelDisplayPreviewPane extends LightningElement {
    @api previewHeight = '600px';

    @track isLoading = false;
    @track errorMessage = '';
    @track sheetOptions = [];
    @track selectedSheet = '';
    @track selectedSheetHtml = '';
    @track zoomLevel = 100;
    @track rotationAngle = 0;
    @track currentIndex = 0;
    @track isModalOpen = false;

    _sheetData = [];
    _documents = [];
    _lastLoadedKey = null;
    _sheetJsLoadPromise = null;

    @api
    get documents() {
        return this._documents;
    }
    set documents(value) {
        const docs = Array.isArray(value) ? value : [];
        this._documents = docs;
        this.currentIndex = Math.min(this.currentIndex, Math.max(0, this._documents.length - 1));
    }

    @api documentId;
    @api versionId;
    @api title;

    renderedCallback() {
        if (this.template?.host) {
            this.template.host.style.setProperty('--preview-height', this.normalizedPreviewHeight);
            this.template.host.style.setProperty('--preview-transform', `scale(${this.zoomLevel / 100}) rotate(${this.rotationAngle}deg)`);
        }
        const currentKey = this.fileIdentityKey;
        if (!currentKey || this._lastLoadedKey === currentKey) {
            return;
        }
        this._lastLoadedKey = currentKey;
        this.loadWorkbookPreview();
    }

    get effectiveDocuments() {
        if (this._documents.length > 0) {
            return this._documents;
        }
        if (this.documentId || this.versionId) {
            return [{
                contentDocumentId: this.documentId,
                contentVersionId: this.versionId,
                title: this.title || 'Document'
            }];
        }
        return [];
    }

    get hasDocuments() {
        return this.effectiveDocuments.length > 0;
    }

    get hasMultipleDocuments() {
        return this.effectiveDocuments.length > 1;
    }

    get currentDocument() {
        return this.hasDocuments ? this.effectiveDocuments[this.currentIndex] : null;
    }

    get fileIdentityKey() {
        return this.currentDocument?.contentVersionId || this.currentDocument?.contentDocumentId || null;
    }

    get previewTransformStyle() {
        return `transform: scale(${this.zoomLevel / 100}) rotate(${this.rotationAngle}deg); transform-origin: top center; transition: transform 0.3s;`;
    }

    get previewContainerStyle() {
        return `height: ${this.previewHeight};`;
    }

    get normalizedPreviewHeight() {
        const value = `${this.previewHeight || '600px'}`.trim();
        return /^\d+$/.test(value) ? `${value}px` : value;
    }

    get currentZoomLabel() {
        return `${this.zoomLevel}%`;
    }

    get disablePrevDoc() {
        return this.currentIndex <= 0;
    }

    get disableNextDoc() {
        return this.currentIndex >= this.effectiveDocuments.length - 1;
    }

    get documentCounterLabel() {
        return `${this.currentIndex + 1} / ${this.effectiveDocuments.length}`;
    }

    get modalTitle() {
        return this.currentDocument?.title || 'Excel Preview';
    }

    get hasSheetContent() {
        return !!this.selectedSheetHtml;
    }

    async ensureSheetJsLoaded() {
        if (window.XLSX) {
            return;
        }
        if (!this._sheetJsLoadPromise) {
            this._sheetJsLoadPromise = (async () => {
                try {
                    await loadScript(this, `${SHEETJS}/xlsx.full.min.js`);
                } catch (fullLoadError) {
                    await loadScript(this, `${SHEETJS}/xlsx.core.min.js`);
                }
                if (!window.XLSX) {
                    throw new Error('SheetJS library not available.');
                }
            })();
        }
        await this._sheetJsLoadPromise;
    }

    async loadWorkbookPreview() {
        this.isLoading = true;
        this.errorMessage = '';
        this.sheetOptions = [];
        this.selectedSheet = '';
        this.selectedSheetHtml = '';
        this._sheetData = [];

        try {
            await this.ensureSheetJsLoaded();
            const fileBuffer = await this.fetchWorkbookArrayBuffer();
            const workbook = window.XLSX.read(new Uint8Array(fileBuffer), { type: 'array' });
            const sheetNames = workbook.SheetNames || [];
            if (!sheetNames.length) {
                throw new Error('No worksheet found in the file.');
            }

            this._sheetData = sheetNames.map((name) => ({
                name,
                html: window.XLSX.utils.sheet_to_html(workbook.Sheets[name])
            }));
            this.sheetOptions = this._sheetData.map((sheet) => ({ label: sheet.name, value: sheet.name }));
            this.selectedSheet = this.sheetOptions[0].value;
            this.selectedSheetHtml = this._sheetData[0].html;
        } catch (error) {
            this.errorMessage = error?.message || 'Unable to preview Excel file.';
        } finally {
            this.isLoading = false;
        }
    }

    async fetchWorkbookArrayBuffer() {
        const downloadUrl = this.currentDocument?.contentVersionId
            ? `/sfc/servlet.shepherd/version/download/${this.currentDocument.contentVersionId}`
            : `/sfc/servlet.shepherd/document/download/${this.currentDocument?.contentDocumentId}`;
        try {
            const response = await fetch(downloadUrl, { credentials: 'same-origin' });
            if (!response.ok) {
                throw new Error(`Unable to fetch Excel file (${response.status}).`);
            }
            return response.arrayBuffer();
        } catch (fetchError) {
            const base64Data = await getExcelFileBase64({
                contentVersionId: this.currentDocument?.contentVersionId || null,
                contentDocumentId: this.currentDocument?.contentDocumentId || null
            });
            if (!base64Data) {
                throw new Error(fetchError?.message || 'Unable to fetch Excel file.');
            }
            return this.base64ToArrayBuffer(base64Data);
        }
    }

    handleSheetChange(event) {
        this.selectedSheet = event.detail.value;
        const selected = this._sheetData.find((sheet) => sheet.name === this.selectedSheet);
        this.selectedSheetHtml = selected?.html || '';
    }

    base64ToArrayBuffer(base64Data) {
        const binaryString = atob(base64Data);
        const bytes = new Uint8Array(binaryString.length);
        for (let index = 0; index < binaryString.length; index += 1) {
            bytes[index] = binaryString.charCodeAt(index);
        }
        return bytes.buffer;
    }

    handlePrevDoc() {
        if (!this.disablePrevDoc) {
            this.currentIndex -= 1;
            this.resetView();
            this._lastLoadedKey = null;
        }
    }

    handleNextDoc() {
        if (!this.disableNextDoc) {
            this.currentIndex += 1;
            this.resetView();
            this._lastLoadedKey = null;
        }
    }

    handleZoomIn() {
        this.zoomLevel = Math.min(200, this.zoomLevel + 25);
    }

    handleZoomOut() {
        this.zoomLevel = Math.max(25, this.zoomLevel - 25);
    }

    handleDownload() {
        if (!this.currentDocument) return;
        const link = document.createElement('a');
        link.href = this.currentDocument.contentVersionId
            ? `/sfc/servlet.shepherd/version/download/${this.currentDocument.contentVersionId}`
            : `/sfc/servlet.shepherd/document/download/${this.currentDocument.contentDocumentId}`;
        link.download = this.currentDocument.title || 'workbook.xlsx';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    handleOpenFullScreen() {
        this.isModalOpen = true;
    }

    handleCloseFullScreen() {
        this.isModalOpen = false;
    }

    resetView() {
        this.zoomLevel = 100;
        this.rotationAngle = 0;
    }
}