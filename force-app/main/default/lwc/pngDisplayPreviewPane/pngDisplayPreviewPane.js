import { LightningElement, api, track } from 'lwc';

export default class PngDisplayPreviewPane extends LightningElement {
    @api previewHeight = '600px';

    @track zoomLevel = 100;
    @track rotationAngle = 0;
    @track currentIndex = 0;
    @track isModalOpen = false;

    _documents = [];

    @api
    get documents() {
        return this._documents;
    }
    set documents(value) {
        const docs = Array.isArray(value) ? value : [];
        this._documents = docs;
        this.currentIndex = Math.min(this.currentIndex, Math.max(0, this._documents.length - 1));
    }

    @api previewUrl;
    @api altText = 'Preview';
    @api title;

    renderedCallback() {
        this.applyPreviewStyles();
    }

    get effectiveDocuments() {
        if (this._documents.length > 0) {
            return this._documents;
        }
        if (this.previewUrl) {
            return [{
                previewUrl: this.previewUrl,
                title: this.title || this.altText || 'Image',
                contentDocumentId: null,
                contentVersionId: null
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

    get previewContainerStyle() {
        return `height: ${this.previewHeight};`;
    }

    get normalizedPreviewHeight() {
        const value = `${this.previewHeight || '600px'}`.trim();
        return /^\d+$/.test(value) ? `${value}px` : value;
    }

    get imageStyle() {
        return `max-width: 100%; height: auto; transform: scale(${this.zoomLevel / 100}) rotate(${this.rotationAngle}deg); transform-origin: top left; transition: transform 0.3s;`;
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
        return this.currentDocument?.title || 'Image Preview';
    }

    handlePrevDoc() {
        if (!this.disablePrevDoc) {
            this.currentIndex -= 1;
            this.resetView();
        }
    }

    handleNextDoc() {
        if (!this.disableNextDoc) {
            this.currentIndex += 1;
            this.resetView();
        }
    }

    handleZoomIn() {
        this.zoomLevel = Math.min(200, this.zoomLevel + 25);
        this.applyPreviewStyles();
    }

    handleZoomOut() {
        this.zoomLevel = Math.max(25, this.zoomLevel - 25);
        this.applyPreviewStyles();
    }

    handleRotateLeft() {
        this.rotationAngle -= 90;
        this.applyPreviewStyles();
    }

    handleRotateRight() {
        this.rotationAngle += 90;
        this.applyPreviewStyles();
    }

    handleResetView() {
        this.resetView();
    }

    handleDownload() {
        const doc = this.currentDocument;
        if (!doc) return;
        const link = document.createElement('a');
        link.href = doc.contentVersionId
            ? `/sfc/servlet.shepherd/version/download/${doc.contentVersionId}`
            : (doc.contentDocumentId
                ? `/sfc/servlet.shepherd/document/download/${doc.contentDocumentId}`
                : doc.previewUrl);
        link.download = doc.title || 'image.png';
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
        this.applyPreviewStyles();
    }

    applyPreviewStyles() {
        if (!this.template?.host) return;
        this.template.host.style.setProperty('--preview-height', this.normalizedPreviewHeight);
        this.template.host.style.setProperty(
            '--preview-transform',
            `scale(${this.zoomLevel / 100}) rotate(${this.rotationAngle}deg)`
        );
    }
}