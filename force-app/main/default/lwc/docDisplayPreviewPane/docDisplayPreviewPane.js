import { LightningElement, api, track } from 'lwc';

export default class DocDisplayPreviewPane extends LightningElement {
    @api previewHeight = '600px';
    @api fileType = 'DOCX';

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

    @api documentId;
    @api versionId;
    @api title;

    renderedCallback() {
        if (this.template?.host) {
            this.template.host.style.setProperty('--preview-height', this.normalizedPreviewHeight);
            this.template.host.style.setProperty('--preview-transform', `scale(${this.zoomLevel / 100}) rotate(${this.rotationAngle}deg)`);
        }
    }

    get effectiveDocuments() {
        if (this._documents.length > 0) {
            return this._documents;
        }
        if (this.documentId || this.versionId) {
            return [{
                contentDocumentId: this.documentId,
                contentVersionId: this.versionId,
                title: this.title || 'Document',
                fileType: this.fileType
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

    get modalTitle() {
        return this.currentDocument?.title || 'Document Preview';
    }

    get canRenderPreview() {
        return !!(this.currentDocument?.contentDocumentId || this.currentDocument?.contentVersionId);
    }

    get resolvedFileType() {
        const effectiveType = (this.currentDocument?.fileType || this.fileType || 'DOCX').toUpperCase();
        if (effectiveType.startsWith('DOC') || effectiveType.startsWith('WORD')) {
            // Force filePreview paginated rendition path for Word docs.
            // This improves multi-page navigation behavior without changing filePreview.
            return 'PDF';
        }
        return effectiveType;
    }

    get inlinePreviewImageUrl() {
        const versionId = this.currentDocument?.contentVersionId;
        const documentId = this.currentDocument?.contentDocumentId;
        if (versionId) {
            return `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${versionId}`;
        }
        if (documentId) {
            return `/sfc/servlet.shepherd/document/download/${documentId}`;
        }
        return this.currentDocument?.previewUrl || '';
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
        link.download = this.currentDocument.title || 'document.docx';
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
    handleResetView() {
        this.resetView();
    }


    resetView() {
        this.zoomLevel = 100;
        this.rotationAngle = 0;
    }
}