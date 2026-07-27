import { LightningElement, api } from 'lwc';

export default class KycEntityDocumentPanel extends LightningElement {
    @api sectionKey = '';
    @api legendLabel = '';
    @api fileTitle = 'Upload document';
    @api required = false;
    @api isReadOnly = false;
    @api uploadDisabled = false;
    @api uploadIconUrl = '';
    @api files = [];
    /** When true, upload stays visible after files exist; uploaded rows render below. */
    @api persistentUpload = false;
    /** Hides the left slot column (readonly additional-documents layout). */
    @api suppressLeftColumn = false;
    /** Hides the upload column until the user selects a document type. */
    @api hideRightColumn = false;
    /**
     * When true, the LEFT (fields) pane gets comfortable padding and top-aligned
     * content so a dense stack of fields reads cleanly beside the RIGHT (upload)
     * pane. Intentionally does NOT impose an internal height cap / overflow
     * scroll — that clips native dropdown overlays (e.g. the District
     * lightning-combobox) and forces janky focus workarounds.
     */
    @api scrollableLeftPane = false;

    get showLeftColumn() {
        return !this.suppressLeftColumn;
    }

    get leftColumnClass() {
        return this.scrollableLeftPane ? 'dv-left dv-left--scroll' : 'dv-left';
    }

    get resolvedLegendLabel() {
        return this.legendLabel || 'Document';
    }

    get filesEmpty() {
        return !Array.isArray(this.files) || this.files.length === 0;
    }

    get showUploadBtn() {
        if (this.isReadOnly) {
            return false;
        }
        if (this.persistentUpload) {
            return !this.uploadDisabled;
        }
        return this.filesEmpty && !this.uploadDisabled;
    }

    get showEmptyPlaceholder() {
        if (this.isReadOnly || this.persistentUpload) {
            return false;
        }
        return this.filesEmpty && this.uploadDisabled;
    }

    get showFileTitle() {
        return !this.isReadOnly;
    }

    get showRightColumn() {
        if (this.hideRightColumn) {
            return false;
        }
        if (this.isReadOnly && this.filesEmpty) {
            return false;
        }
        if (this.isReadOnly && this.persistentUpload) {
            return false;
        }
        return true;
    }

    get splitClass() {
        if (!this.showLeftColumn && !this.showRightColumn) {
            return 'dv-split dv-split--files-only';
        }
        if (!this.showLeftColumn && this.showRightColumn) {
            return 'dv-split dv-split--right-only';
        }
        return this.showRightColumn ? 'dv-split' : 'dv-split dv-split--left-only';
    }

    get showFileRow() {
        return !this.persistentUpload && !this.filesEmpty;
    }

    get showUploadedFilesBelow() {
        return this.persistentUpload && !this.filesEmpty;
    }

    get singleFile() {
        if (this.filesEmpty) {
            return null;
        }
        return this.files[0];
    }

    get canDelete() {
        return !this.isReadOnly;
    }

    handleUploadClick() {
        this.dispatchEvent(new CustomEvent('uploadrequest', {
            detail: { sectionKey: this.sectionKey },
            bubbles: true,
            composed: true
        }));
    }

    handleFilePreviewClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const ds = event.currentTarget?.dataset || {};
        this.dispatchEvent(new CustomEvent('filepreview', {
            detail: {
                sectionKey: this.sectionKey,
                fileId: ds.fileId || null,
                contentDocumentId: ds.contentDocumentId || null,
                contentVersionId: ds.contentVersionId || null,
                fileType: ds.fileExtension || null,
                fileName: ds.fileName || null
            },
            bubbles: true,
            composed: true
        }));
    }

    handleFileDeleteClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const ds = event.currentTarget?.dataset || {};
        this.dispatchEvent(new CustomEvent('filedelete', {
            detail: {
                sectionKey: this.sectionKey,
                fileId: ds.fileId || null
            },
            bubbles: true,
            composed: true
        }));
    }
}