import { LightningElement, api } from 'lwc';

const EXCEL_TYPES = ['xls', 'xlsx', 'csv'];
const IMAGE_TYPES = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];
const DOC_TYPES = ['doc', 'docx'];

export default class FileDisplayPreviewPane extends LightningElement {
    @api previewHeight = '600px';

    _documents = [];
    currentIndex = 0;

    @api
    get documents() {
        return this._documents;
    }
    set documents(value) {
        const docs = Array.isArray(value) ? value : [];
        this._documents = docs.map((doc) => this.normalizeDocument(doc));
        this.currentIndex = Math.min(this.currentIndex, Math.max(0, this._documents.length - 1));
    }

    // Single-document API for ease of adoption.
    @api documentType;
    @api documentId;
    @api versionId;
    @api fileName;
    @api previewUrl;

    get normalizedDocuments() {
        if (this._documents.length > 0) {
            return this._documents;
        }
        if (this.documentType || this.documentId || this.versionId) {
            return [this.normalizeDocument({
                fileType: this.documentType,
                contentDocumentId: this.documentId,
                contentVersionId: this.versionId,
                title: this.fileName,
                previewUrl: this.previewUrl
            })];
        }
        return [];
    }

    get hasDocuments() {
        return this.normalizedDocuments.length > 0;
    }

    get hasMultipleDocuments() {
        return this.normalizedDocuments.length > 1;
    }

    get currentDocument() {
        return this.hasDocuments ? this.normalizedDocuments[this.currentIndex] : null;
    }

    get currentDocumentOnly() {
        return this.currentDocument ? [this.currentDocument] : [];
    }

    get disablePrevDoc() {
        return this.currentIndex <= 0;
    }

    get disableNextDoc() {
        return this.currentIndex >= this.normalizedDocuments.length - 1;
    }

    get documentCounterLabel() {
        return `${this.currentIndex + 1} / ${this.normalizedDocuments.length}`;
    }


    get childPreviewHeight() {
        const value = `${this.previewHeight || '600px'}`.trim();
        const numeric = parseInt(value.replace('px', ''), 10);
        if (!Number.isFinite(numeric)) {
            return value;
        }
        // Reserve additional room when router toolbar is visible for multi-doc buckets.
        const adjusted = this.hasMultipleDocuments ? Math.floor(numeric * 0.85) : numeric;
        return `${Math.max(220, adjusted)}px`;
    }

    get isPdf() {
        return this.currentDocument?.isPdf === true;
    }

    get isExcel() {
        return this.currentDocument?.isExcel === true;
    }

    get isImage() {
        return this.currentDocument?.isImage === true;
    }

    get isDoc() {
        return this.currentDocument?.isDoc === true;
    }

    get unsupportedType() {
        return this.currentDocument && !this.isPdf && !this.isExcel && !this.isImage && !this.isDoc;
    }

    handlePrevDoc() {
        if (this.disablePrevDoc) return;
        this.currentIndex -= 1;
    }

    handleNextDoc() {
        if (this.disableNextDoc) return;
        this.currentIndex += 1;
    }

    normalizeDocument(doc) {
        const extension = this.resolveExtension(doc);
        const isImage = IMAGE_TYPES.includes(extension);
        const isExcel = EXCEL_TYPES.includes(extension);
        const isDoc = DOC_TYPES.includes(extension);
        const isPdf = extension === 'pdf';

        const contentVersionId = doc?.contentVersionId || doc?.versionId || this.versionId;
        const contentDocumentId = doc?.contentDocumentId || doc?.documentId || this.documentId;
        const effectivePreviewUrl = doc?.previewUrl ||
            (contentVersionId ? `/sfc/servlet.shepherd/version/download/${contentVersionId}` : null) ||
            (contentDocumentId ? `/sfc/servlet.shepherd/document/download/${contentDocumentId}` : null);

        return {
            ...doc,
            contentVersionId,
            contentDocumentId,
            extension,
            fileType: extension ? extension.toUpperCase() : null,
            title: doc?.title || doc?.fileName || this.fileName || 'Document',
            previewUrl: effectivePreviewUrl,
            downloadUrl: contentVersionId
                ? `/sfc/servlet.shepherd/version/download/${contentVersionId}`
                : (contentDocumentId ? `/sfc/servlet.shepherd/document/download/${contentDocumentId}` : null),
            isImage,
            isExcel,
            isDoc,
            isPdf
        };
    }

    resolveExtension(doc) {
        const normalize = (value) => {
            if (!value) return '';
            let normalized = String(value).trim().toLowerCase();
            if (!normalized) return '';
            // Handle mime types like "application/pdf".
            if (normalized.includes('/')) {
                normalized = normalized.split('/').pop();
            }
            // Handle values like ".pdf" or "file.pdf".
            if (normalized.includes('.')) {
                normalized = normalized.split('.').pop();
            }
            return normalized.trim();
        };

        let extension = normalize(doc?.fileExtension || doc?.extension || doc?.fileType || this.documentType);
        if (extension) {
            return extension;
        }

        // Fall back to file name/title when extension metadata is absent.
        const fileName = String(doc?.fileName || doc?.title || '').trim();
        if (!fileName || !fileName.includes('.')) {
            return '';
        }
        return normalize(fileName.split('.').pop());
    }
}