import { LightningElement, api, track, wire } from 'lwc';
import { loadScript }         from 'lightning/platformResourceLoader';
import { refreshApex }        from '@salesforce/apex';
import { publish, MessageContext } from 'lightning/messageService';
import FileVersionRequest     from '@salesforce/messageChannel/FileVersionRequest__c';
import jsforcescript          from '@salesforce/resourceUrl/jsforcescript';
import getUserSessionId       from '@salesforce/apex/CustomFileUploadV2Controller.getUserSessionId';
import getFilesForRecord      from '@salesforce/apex/CustomFileUploadV2Controller.getFilesForRecord';
import deleteFile             from '@salesforce/apex/CustomFileUploadV2Controller.deleteFile';
import runFilePermissions     from '@salesforce/apex/CustomFileUploadV2Controller.runFilePermissions';

const IMAGE_EXTS  = new Set(['jpg','jpeg','png','gif','bmp','webp','svg','tiff','tif']);
const EXCEL_EXTS  = new Set(['xls','xlsx','csv']);
const DOCX_EXTS   = new Set(['doc','docx']);
const VIDEO_EXTS  = new Set(['mp4','webm','mov','avi','mkv','m4v','ogv','3gp']);

export default class CustomFilePreviewAndEdit extends LightningElement {

    @api recordId;
    @api validatorClass  = '';
    @api preventDownload = false;

    @track files         = [];
    @track showPreview   = false;
    @track previewFile   = null;
    @track statusMessage = '';
    @track statusType    = 'info';
    @track isLoading     = false;
    @track isUploading   = false;
    @track uploadProgress = 0;
    @track currentPage   = 1;
    @track deletingId    = null;

    PAGE_SIZE = 10;

    _sessionId       = null;
    _vfRoot          = null;
    _wiredFilesResult;
    // Map<ContentVersionId, { canEdit, canDelete, canDownload, errors }>
    _permissions     = {};

    @wire(MessageContext) _msgCtx;

    // ── session ────────────────────────────────────────────────────────────────
    @wire(getUserSessionId)
    _wiredSession({ data, error }) {
        if (data)  this._sessionId = data;
        if (error) this._setStatus('Could not load session', 'error');
    }

    // ── file list ──────────────────────────────────────────────────────────────
    @wire(getFilesForRecord, { recordId: '$recordId' })
    async _wiredFiles(result) {
        this._wiredFilesResult = result;
        const { data, error } = result;
        if (data) {
            this.files     = data;
            this.isLoading = false;
            await this._loadPermissions();
        }
        if (error) {
            this._setStatus('Could not load files', 'error');
            this.isLoading = false;
        }
    }

    // ── lifecycle ──────────────────────────────────────────────────────────────
    connectedCallback() {
        this.isLoading = true;
        const origin = window.location.origin;
        const isSite = location.pathname.split('/').length >= 2 && location.pathname.split('/')[2] === 's';
        if (isSite) {
            this._vfRoot = origin;
        } else {
            const sandboxSuffix = origin.includes('sandbox') ? '.sandbox' : '';
            this._vfRoot = origin.split('.')[0] + '--c' + sandboxSuffix + '.vf.force.com';
        }
        loadScript(this, jsforcescript).catch(() =>
            this._setStatus('Could not load jsforce — new version upload may fail', 'error')
        );
    }

    // ── bulk permission load ───────────────────────────────────────────────────
    async _loadPermissions() {
        if (!this.validatorClass || this.files.length === 0) {
            this._permissions = {};
            return;
        }
        try {
            const ids = this.files.map(f => f.Id);
            const result = await runFilePermissions({
                validatorClassName: this.validatorClass,
                contentVersionIds:  ids,
                recordId:           this.recordId
            });
            this._permissions = result || {};
        } catch (err) {
            this._setStatus(`Permission check failed: ${err.body ? err.body.message : err.message}`, 'error');
            this._permissions = {};
        }
    }

    _permFor(id) {
        const p = this._permissions[id];
        if (p) return p;
        // No validator or missing key — fully permitted
        return { canEdit: true, canDelete: true, canDownload: true, errors: [] };
    }

    // ── computed ───────────────────────────────────────────────────────────────
    get isEmpty()       { return !this.isLoading && this.files.length === 0; }
    get progressStyle() { return `width:${this.uploadProgress}%`; }
    get progressLabel() { return `${this.uploadProgress}%`; }
    get statusClass()   { return `fpae-status fpae-status-${this.statusType}`; }
    get statusIcon() {
        return { success: 'utility:success', error: 'utility:error', info: 'utility:info' }[this.statusType] || 'utility:info';
    }

    get totalPages()    { return Math.max(1, Math.ceil(this.files.length / this.PAGE_SIZE)); }
    get hasPrev()       { return this.currentPage > 1; }
    get hasNext()       { return this.currentPage < this.totalPages; }
    get pageLabel()     { return `Page ${this.currentPage} of ${this.totalPages} (${this.files.length} file${this.files.length !== 1 ? 's' : ''})`; }
    get showPagination(){ return this.files.length > this.PAGE_SIZE; }
    get isFirstPage()   { return this.currentPage <= 1; }
    get isLastPage()    { return this.currentPage >= this.totalPages; }

    get allFileRows() {
        return this.files.map(f => {
            const ext     = (f.FileExtension || '').toLowerCase();
            const created = f.CreatedDate ? new Date(f.CreatedDate).toLocaleDateString('en-GB', { day:'2-digit', month:'short', year:'numeric' }) : '—';
            const perm    = this._permFor(f.Id);
            return {
                id:                f.Id,
                contentDocumentId: f.ContentDocumentId,
                title:             f.Title,
                fileType:          (f.FileType || ext || '—').toUpperCase(),
                ext,
                size:              this._formatSize(f.ContentSize),
                createdDate:       created,
                uploadedBy:        f.CreatedBy ? f.CreatedBy.Name : '—',
                version:           `v${f.VersionNumber}`,
                iconName:          this._iconForExt(ext),
                canEdit:           perm.canEdit,
                canDelete:         perm.canDelete,
                canDownload:       perm.canDownload,
                isDeleting:        this.deletingId === f.Id
            };
        });
    }

    get fileRows() {
        const start = (this.currentPage - 1) * this.PAGE_SIZE;
        return this.allFileRows.slice(start, start + this.PAGE_SIZE);
    }

    handlePrevPage() { if (this.hasPrev) this.currentPage--; }
    handleNextPage() { if (this.hasNext) this.currentPage++; }

    // ── refresh ────────────────────────────────────────────────────────────────
    async handleRefresh() {
        this.isLoading   = true;
        this.currentPage = 1;
        await refreshApex(this._wiredFilesResult);
        this.isLoading = false;
    }

    // ── file click → preview ───────────────────────────────────────────────────
    handleFileClick(event) {
        const id   = event.currentTarget.dataset.id;
        const file = this.files.find(f => f.Id === id);
        if (!file) return;
        const ext   = (file.FileExtension || '').toLowerCase();
        const isVideo = VIDEO_EXTS.has(ext);
        const perm  = this._permFor(file.Id);
        this.previewFile = {
            id:                file.Id,
            contentDocumentId: file.ContentDocumentId,
            title:             file.Title,
            iconName:          this._iconForExt(ext),
            isPdf:    ext === 'pdf',
            isImage:  IMAGE_EXTS.has(ext),
            isExcel:  EXCEL_EXTS.has(ext),
            isDocx:   DOCX_EXTS.has(ext),
            isVideo,
            isOther:  ext !== 'pdf' && !IMAGE_EXTS.has(ext) && !EXCEL_EXTS.has(ext) && !DOCX_EXTS.has(ext) && !isVideo,
            canDownload: perm.canDownload
        };
        this.showPreview = true;
    }

    closePreview() {
        this.showPreview = false;
        this.previewFile = null;
    }

    handleOverlayClick() { this.closePreview(); }
    stopPropagation(event) { event.stopPropagation(); }

    // ── download ───────────────────────────────────────────────────────────────
    handleDownload() {
        if (!this.previewFile || !this.previewFile.canDownload) return;
        this._downloadFile(this.previewFile.id, this.previewFile.title);
    }

    _downloadFile(contentVersionId, fileName) {
        const a    = document.createElement('a');
        a.href     = `/sfc/servlet.shepherd/version/download/${contentVersionId}`;
        a.download = fileName;
        a.click();
    }

    // ── delete ─────────────────────────────────────────────────────────────────
    async handleDelete(event) {
        event.stopPropagation();
        const id   = event.currentTarget.dataset.id;
        const perm = this._permFor(id);
        if (!perm.canDelete) {
            this._setStatus(perm.errors.length ? perm.errors.join(' | ') : 'Delete not permitted', 'error');
            return;
        }
        this.deletingId = id;
        try {
            await deleteFile({ contentVersionId: id });
            if (this.previewFile && this.previewFile.id === id) this.closePreview();
            await refreshApex(this._wiredFilesResult);
            this._setStatus('File deleted', 'success');
        } catch (err) {
            this._setStatus(`Delete failed: ${err.body ? err.body.message : err.message}`, 'error');
        } finally {
            this.deletingId = null;
        }
    }

    // ── upload new version — publish LMS so customFileUploadV2 opens in version mode ──
    handleUploadNewVersion(event) {
        event.stopPropagation();
        const id   = event.currentTarget.dataset.id;
        const perm = this._permFor(id);
        if (!perm.canEdit) {
            this._setStatus(perm.errors.length ? perm.errors.join(' | ') : 'Edit not permitted', 'error');
            return;
        }
        const file = this.files.find(f => f.Id === id);
        if (!file) return;
        publish(this._msgCtx, FileVersionRequest, {
            contentDocumentId: file.ContentDocumentId,
            fileName:          file.Title
        });
    }

    // ── helpers ────────────────────────────────────────────────────────────────
    _iconForExt(ext) {
        if (ext === 'pdf')                   return 'doctype:pdf';
        if (IMAGE_EXTS.has(ext))             return 'doctype:image';
        if (ext === 'xlsx' || ext === 'xls') return 'doctype:excel';
        if (ext === 'csv')                   return 'doctype:csv';
        if (ext === 'docx' || ext === 'doc') return 'doctype:word';
        if (ext === 'pptx' || ext === 'ppt') return 'doctype:ppt';
        if (ext === 'zip')                   return 'doctype:zip';
        if (ext === 'txt')                   return 'doctype:txt';
        if (VIDEO_EXTS.has(ext))             return 'doctype:video';
        return 'doctype:unknown';
    }

    _formatSize(bytes) {
        if (!bytes)               return '—';
        if (bytes < 1024)         return `${bytes} B`;
        if (bytes < 1024 * 1024)  return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
    }

    _setStatus(msg, type = 'info') {
        this.statusMessage = msg;
        this.statusType    = type;
        if (type === 'success') setTimeout(() => { this.statusMessage = ''; }, 4000);
    }
}