/**
 * documentUpload — Generic document upload card for Document_CheckList__c flows.
 * Parent passes checklist / application / applicant / document type via @api.
 * Emits upload, delete, and preview events for parent state sync.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import linkContentDocument from '@salesforce/apex/AdditionalDocumentsController.linkContentDocument';
import getFileType from '@salesforce/apex/AdditionalDocumentsController.getFileType';
import deleteContentDocument from '@salesforce/apex/RepaymentMandateController.deleteContentDocument';

const DEFAULT_ACCEPTED_FORMATS = '.pdf,.jpg,.png,.jpeg';
const DEFAULT_SUBTITLE = 'PDF, JPG up to 10MB';
const DEFAULT_VERIFIED_LABEL = 'ASSET VERIFIED';

export default class DocumentUpload extends LightningElement {
    /** Unique key echoed in custom events (e.g. salaried-pay-slip-1). */
    @api name = '';

    /** Card title shown in the header. */
    @api label = '';

    /** Helper text shown before a file is uploaded. */
    @api subtitle = DEFAULT_SUBTITLE;

    /** SLDS icon for the pending state. */
    @api iconName = 'utility:attach';

    /** Shows a required asterisk on the title. */
    @api required = false;

    /** Disables upload, preview, and delete actions. */
    @api disabled = false;

    /** Hides upload and delete; preview may still show when uploaded. */
    @api readOnly = false;

    /** Document_CheckList__c Id — used as lightning-file-upload record-id. */
    @api documentChecklistId = '';

    /** Application__c Id — used when autoLink is true. */
    @api applicationId = '';

    /** Applicant__c Id — used when autoLink is true. */
    @api applicantId = '';

    /** Document_Type__c value — used when autoLink is true. */
    @api documentType = '';

    /** Comma-separated extensions for lightning-file-upload accept. */
    @api acceptedFormats = DEFAULT_ACCEPTED_FORMATS;

    /** Whether a file is already linked. */
    @api uploaded = false;

    /** Uploaded file display name. */
    @api fileName = '';

    /** Pre-formatted file size label (e.g. 0.01 MB). */
    @api fileSizeLabel = '';

    /** Raw byte size — formatted when fileSizeLabel is empty. */
    @api fileSizeBytes = 0;

    /** ContentDocument Id for preview / delete. */
    @api contentDocumentId = '';

    /** File type for preview (PNG, PDF, etc.). */
    @api fileType = 'PNG';

    /** Shows the verified badge in the uploaded footer. */
    @api verified = false;

    /** Footer badge text when verified is true. */
    @api verifiedLabel = DEFAULT_VERIFIED_LABEL;

    /** When false, skips Apex link even if application/applicant/document type are set. */
    @api autoLink;

    /** When true, deletes ContentDocument on delete action. */
    @api autoDelete;

    /** Set false to hide Preview when uploaded. */
    @api showPreview;

    /** Set false to hide Delete when uploaded. */
    @api showDelete;

    /** Allows selecting more than one file (defaults to single upload). */
    @api multipleUpload = false;

    @track isLinking = false;
    @track isDeleting = false;
    @track openPreviewModal = false;
    @track previewContentDocumentId;
    @track previewFileType;

    _localUploaded = false;
    _localFileName = '';
    _localFileSizeLabel = '';
    _localContentDocumentId = '';
    _localFileType = 'PNG';

    get uploadInputName() {
        return this.name || this.label || 'documentUpload';
    }

    get showUploadedState() {
        return this.uploaded || this._localUploaded;
    }

    get displayFileName() {
        return this.fileName || this._localFileName || '';
    }

    get displayFileSize() {
        if (this.fileSizeLabel) {
            return this.fileSizeLabel;
        }
        if (this._localFileSizeLabel) {
            return this._localFileSizeLabel;
        }
        if (this.fileSizeBytes > 0) {
            return this.formatFileSize(this.fileSizeBytes);
        }
        return '';
    }

    get displayContentDocumentId() {
        return this.contentDocumentId || this._localContentDocumentId || '';
    }

    get displayFileType() {
        return this.fileType || this._localFileType || 'PNG';
    }

    get isInteractionDisabled() {
        return this.disabled || this.isLinking || this.isDeleting;
    }

    get isUploadDisabled() {
        return (
            this.isInteractionDisabled ||
            this.readOnly ||
            !this.documentChecklistId ||
            this.showUploadedState
        );
    }

    get isDeleteDisabled() {
        return this.isInteractionDisabled || !this.displayContentDocumentId;
    }

    get showUploadZone() {
        return !this.showUploadedState && !this.readOnly;
    }

    get showVerifiedBadge() {
        return this.verified === true || this.verified === 'true';
    }

    get showPreviewAction() {
        if (this.showPreview === false || this.showPreview === 'false') {
            return false;
        }
        return !!this.displayContentDocumentId;
    }

    get showDeleteAction() {
        if (this.showDelete === false || this.showDelete === 'false') {
            return false;
        }
        return !this.readOnly;
    }

    get cardClass() {
        const classes = ['doc-upload-card'];
        if (this.showUploadedState) {
            classes.push('doc-upload-card--uploaded');
        }
        if (this.isInteractionDisabled) {
            classes.push('doc-upload-card--disabled');
        }
        return classes.join(' ');
    }

    get iconWrapClass() {
        return this.showUploadedState
            ? 'doc-upload-card__icon-wrap doc-upload-card__icon-wrap--success'
            : 'doc-upload-card__icon-wrap';
    }

    /**
     * Resets optimistic local upload state — call from parent after delete or reload.
     */
    @api
    resetLocalState() {
        this._localUploaded = false;
        this._localFileName = '';
        this._localFileSizeLabel = '';
        this._localContentDocumentId = '';
        this._localFileType = 'PNG';
    }

    async handleUploadFinished(event) {
        if (this.readOnly || this.disabled) {
            return;
        }

        const uploadedFiles = event.detail?.files || [];
        if (!uploadedFiles.length) {
            return;
        }

        if (!this.documentChecklistId) {
            this.showWarning('Document checklist record is missing. Initialize the checklist before uploading.');
            return;
        }

        const file = uploadedFiles[0];
        const contentDocumentId = file.documentId || '';
        const nextFileName = file.name || '';
        const nextFileSizeLabel = this.formatFileSize(file.size);

        if (!contentDocumentId) {
            this.showError('Upload Failed', 'Uploaded file reference is missing.');
            return;
        }

        this.isLinking = true;
        try {
            if (this.shouldAutoLink()) {
                await linkContentDocument({
                    documentDataJson: JSON.stringify({
                        documentType: this.documentType,
                        applicationId: this.applicationId,
                        applicantId: this.applicantId,
                        contentDocumentId
                    })
                });
            }

            const resolvedFileType = await getFileType({ contentDocumentId });

            this._localUploaded = true;
            this._localFileName = nextFileName;
            this._localFileSizeLabel = nextFileSizeLabel;
            this._localContentDocumentId = contentDocumentId;
            this._localFileType = resolvedFileType || this.displayFileType;

            this.dispatchUploadEvent({
                contentDocumentId,
                fileName: nextFileName,
                fileType: this._localFileType,
                fileSizeLabel: nextFileSizeLabel,
                fileSizeBytes: file.size || 0
            });
        } catch (error) {
            this.showError('Upload Failed', error);
            this.dispatchErrorEvent('Upload Failed', error);
        } finally {
            this.isLinking = false;
        }
    }

    handlePreview() {
        if (!this.displayContentDocumentId) {
            return;
        }

        this.previewContentDocumentId = this.displayContentDocumentId;
        this.previewFileType = this.displayFileType;
        this.openPreviewModal = true;

        this.dispatchEvent(
            new CustomEvent('preview', {
                detail: this.buildEventDetail({
                    contentDocumentId: this.displayContentDocumentId,
                    fileType: this.displayFileType
                }),
                bubbles: true,
                composed: true
            })
        );
    }

    handlePreviewClose() {
        this.openPreviewModal = false;
        this.previewContentDocumentId = null;
        this.previewFileType = null;
    }

    async handleDelete() {
        if (this.readOnly || this.disabled || !this.displayContentDocumentId) {
            return;
        }

        this.isDeleting = true;
        try {
            if (this.shouldAutoDelete()) {
                await deleteContentDocument({
                    contentDocumentId: this.displayContentDocumentId
                });
            }

            const deletedId = this.displayContentDocumentId;
            this.resetLocalState();

            this.dispatchEvent(
                new CustomEvent('delete', {
                    detail: this.buildEventDetail({
                        contentDocumentId: deletedId
                    }),
                    bubbles: true,
                    composed: true
                })
            );
        } catch (error) {
            this.showError('Delete Failed', error);
            this.dispatchErrorEvent('Delete Failed', error);
        } finally {
            this.isDeleting = false;
        }
    }

    shouldAutoLink() {
        if (this.autoLink === false || this.autoLink === 'false') {
            return false;
        }
        return (
            !!this.applicationId &&
            !!this.applicantId &&
            !!this.documentType
        );
    }

    shouldAutoDelete() {
        return this.autoDelete === true || this.autoDelete === 'true';
    }

    dispatchUploadEvent(payload) {
        this.dispatchEvent(
            new CustomEvent('upload', {
                detail: this.buildEventDetail(payload),
                bubbles: true,
                composed: true
            })
        );
    }

    buildEventDetail(extra = {}) {
        return {
            name: this.name,
            label: this.label,
            documentType: this.documentType,
            documentChecklistId: this.documentChecklistId,
            applicationId: this.applicationId,
            applicantId: this.applicantId,
            ...extra
        };
    }

    dispatchErrorEvent(title, error) {
        this.dispatchEvent(
            new CustomEvent('error', {
                detail: {
                    ...this.buildEventDetail(),
                    title,
                    message: this.resolveErrorMessage(error)
                },
                bubbles: true,
                composed: true
            })
        );
    }

    formatFileSize(bytes) {
        const size = Number(bytes) || 0;
        if (size <= 0) {
            return '';
        }
        if (size < 1024) {
            return `${size} B`;
        }
        if (size < 1024 * 1024) {
            return `${(size / 1024).toFixed(2)} KB`;
        }
        return `${(size / (1024 * 1024)).toFixed(2)} MB`;
    }

    resolveErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        if (typeof error === 'string') {
            return error;
        }
        return 'An unexpected error occurred';
    }

    showWarning(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Warning',
                message,
                variant: 'warning'
            })
        );
    }

    showError(title, error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: this.resolveErrorMessage(error),
                variant: 'error'
            })
        );
    }
}