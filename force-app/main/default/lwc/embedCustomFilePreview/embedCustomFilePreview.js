/**
 * embedCustomFilePreview — Iter 3 (FINAL)
 *
 * 3-level hierarchy:
 *   LWC root  →  Document Checklists  →  File Tiles (ContentVersion)
 *
 * Cloud-vs-Rain split: Dock Panel is the cloud — decides which
 * checklist IDs matter and may create ad-hoc ones via embedDocumentChecklist. This LWC is the rain — given `checklistIds`, it renders/manages.
 *
 * Top bar: title + search (resets page to 1) + Expand/Collapse All
 *          + Refresh.
 * Pagination: 5 checklists per page (configurable via @api pageSize).
 * Checklist header (indigo): name + icon | meta sub-row (Doc Category |
 *          Sub Category) | actions (Transfer Ownership, Multi-Upload [always
 *          Advanced Upload], Delete-All, Expand/Collapse [+/-, hidden when no
 *          files]).
 * File tile (mini accordion): name + chevron | actions (Preview eye, Re-Upload,
 *          Delete). Expanded body shows File Type / Size / Created Date /
 *          Uploaded By / Version.
 *
 * Special icons (multi-upload, delete-all, reupload) load from the
 * `special_icons` static resource (zip path special_icons/special_icons/...).
 *
 * Aura video preview path (embedVideoPreviewer + embedVideoPreviewOverlay)
 */

import { LightningElement, api, track, wire } from 'lwc';
import { publish, MessageContext }              from 'lightning/messageService';
import FILE_VERSION_REQUEST                     from '@salesforce/messageChannel/FileVersionRequest__c';
import SPECIAL_ICONS                            from '@salesforce/resourceUrl/special_icons';

import getChecklistsByIds            from '@salesforce/apex/embedCustomFilePreviewController.getChecklistsByIds';
import getChecklistsByApplicationId  from '@salesforce/apex/embedCustomFilePreviewController.getChecklistsByApplicationId';
import getUserSessionId           from '@salesforce/apex/embedCustomFilePreviewController.getUserSessionId';
import deleteFile                 from '@salesforce/apex/embedCustomFilePreviewController.deleteFile';
import deleteAllFilesForChecklist from '@salesforce/apex/embedCustomFilePreviewController.deleteAllFilesForChecklist';
import runFilePermissions         from '@salesforce/apex/embedCustomFilePreviewController.runFilePermissions';
import getAdhocAddOptions         from '@salesforce/apex/embedCustomFilePreviewController.getAdhocAddOptions';
import stampChecklistNameFromLatestFile from '@salesforce/apex/embedDocumentChecklistController.stampChecklistNameFromLatestFile';

/* Note: special_icons SVGs are inlined directly in embedCustomFilePreview.html
   (stroke="currentColor") so we can theme them entirely from CSS — no static
   resource URL plumbing needed at runtime. preview-upload.svg is reserved for
   Iter 5 (Dock Panel combined view+upload icon) and will be imported then. */

const PAGE_SIZE_DEFAULT = 5;
const PREVIEWABLE_TYPES = ['pdf','png','jpg','jpeg','gif','webp','xlsx','xls','csv','docx','mp4','webm','mov'];
const IMAGE_TYPES = ['png','jpg','jpeg','gif','webp','bmp','svg'];
const VIDEO_TYPES = ['mp4','webm','mov','m4v'];

export default class EmbedCustomFilePreview extends LightningElement {

    // ────────────────────────────────── @api props ───────────────────────────
    /**
     * Comma-separated Document_CheckList__c Ids (e.g. "a0X...001,a0X...002").
     * Removed when the Dock Panel becomes the host.
     */
    @api checklistIds;
    @api headerTitle              = 'Advanced File Management';
    @api pageSize                 = PAGE_SIZE_DEFAULT;
    @api preventDownload          = false;
    @api fileValidatorClassName;                       // optional: Apex validator
    @api emptyStateText           = 'No document checklists configured yet.';
    @api defaultExpandedAll       = false;             // start with everything collapsed
    @api enableAdhocAdd           = false;

    _recordId;
    _connected = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const next = value || null;
        if (next === this._recordId) {
            return;
        }
        this._recordId = next;
        // New record context (e.g. a different Application via the Dock Panel): drop
        // any previously loaded checklists immediately so a stale list is never shown.
        this._checklists = [];
        if (this._connected) {
            this._loadChecklists();
        }
    }

    @api applicantId;
    /* 'upload' shows the "+ New Ad-Hoc File" flow; 'preview' shows filters and
       hides the add/multi-upload controls (preview-only). */
    @api mode                     = 'preview';

    /* special_icons SVGs are inlined directly in the HTML template (see
       embedCustomFilePreview.html) so stroke="currentColor" can pick up
       theme colors via CSS — no URL plumbing needed at runtime. */

    // ────────────────────────────────── reactive state ───────────────────────
    @track _checklists = [];                           // raw DTOs from Apex
    @track _searchQuery = '';
    @track _currentPage = 1;

    @track _expandedChecklists = new Set();            // Set<checklistId>
    @track _expandedTiles      = new Set();            // Set<`${checklistId}::${cvId}`>

    // Internal mode override — null defers to @api mode; set to 'preview' after
    // an ad-hoc upload so the surface returns to preview-only.
    @track _modeOverride = null;

    // ── ad-hoc "New Ad-Hoc File" creation tile ───────────────────
    @track _isCreatingAdHoc    = false;                // toggled by "+ New Ad-Hoc File"

    @track _showAdhocPreview   = false;
    @track _adhocPreviewChecklistId = null;            // scope preview to newly uploaded checklist
    @track _adhocDocType       = 'OTHER';              // selected doc type
    @track _adhocApplicantType = '';                   // picklist value
    @track _adhocStatus        = 'idle';               // 'idle' | 'creating' | 'uploading'
    @track _adhocChecklistId   = null;                 // created checklist for inline upload
    @track _adhocMaxFiles      = null;                 // master-driven cap (inline upload)
    @track _adhocAllowedTypes  = '';                   // master-driven allow-list (inline upload)
    @track _applicantTypeRaw   = [];                   // [{label,value}] from Apex
    @track _assetRaw           = [];                   // [{label,value}] from Apex
    @track _isPddTrackingMode  = false;
    @track _adhocDocTypeRaw    = [{ label: 'OTHER', value: 'OTHER' }];
    @track _adhocAssetId       = '';

    // ── Preview-mode filters (Applicant Type + Document Type) ─────
    @track _applicantTypeFilter = 'All';
    @track _documentTypeFilter  = 'All';
    @track _openFilter          = '';                  // '' | 'applicant' | 'document'

    @track _inFlightUploads   = {};                    // {checklistId: [{uid, fileName, pct}]}
    @track _reuploadProgress  = {};                    // {tileKey: pct}
    @track _deletingTiles     = new Set();             // Set<tileKey>
    @track _filePermissions   = {};                    // {cvId: {canEdit,canDelete,canDownload}}

    @track _showPreview            = false;
    @track _previewFile            = {};
    @track _showDeleteAllConfirm   = false;
    @track _deleteAllChecklistId   = null;
    @track _deleteAllChecklistName = '';

    @track _isLoading       = false;
    @track _statusMessage   = '';
    @track _statusVariant   = 'info';                  // 'info' | 'error'

    // Preview-LWC handoff (session for jsforce)
    _sessionId       = '';
    _vfRoot          = '';
    _isInternalApp   = false;

    // Pending interaction state (for native file input + re-upload)
    _pendingTargetChecklistId = null;
    _pendingReuploadTile      = null;                  // {tileKey, cvId, checklistId}

    @api
    get checklists() { return this._checklists; }

    // LMS
    @api flexipageRegionWidth;
    @wire(MessageContext) contextMessageContext;

    // ───────────────── Service plumbing ──────────────────────────────────────
    @api refresh() { this._loadChecklists(); }

    connectedCallback() {
        this._connected     = true;
        this._isInternalApp = !this._isExperienceCloud();
        this._vfRoot        = this._buildVfRoot();
        this._loadSession();
        this._loadChecklists();
        if (this.defaultExpandedAll) this._expandAll();
        if (this.enableAdhocAdd) this._loadAdhocOptions();
        
        if (this.isUploadMode && this.enableAdhocAdd) {
            this._isCreatingAdHoc = true;
            this._adhocStatus     = 'idle';
            this._adhocDocType    = this._defaultAdhocDocType();
        }
    }

    /**
     * Parse the @api checklistIds CSV/array into a clean Id array.
     * Accepts: comma-separated String, JSON array literal, or already-array.
     * Trims whitespace, drops blanks, dedupes.
     */
    _parseChecklistIds() {
        let raw = this.checklistIds;
        if (!raw) return [];
        if (Array.isArray(raw)) {
            return [...new Set(raw.map(s => (s || '').toString().trim()).filter(Boolean))];
        }
        const str = raw.toString().trim();
        if (!str) return [];
        // Tolerate JSON array literal: ["a0X...","a0X..."]
        if (str.startsWith('[') && str.endsWith(']')) {
            try {
                const parsed = JSON.parse(str);
                if (Array.isArray(parsed)) {
                    return [...new Set(parsed.map(s => (s || '').toString().trim()).filter(Boolean))];
                }
            } catch (e) { /* fall through to CSV */ }
        }
        return [...new Set(str.split(',').map(s => s.trim()).filter(Boolean))];
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Loaders
    // ═══════════════════════════════════════════════════════════════════════
    async _loadSession() {
        try {
            this._sessionId = await getUserSessionId();
        } catch (e) {
            // session is only needed for preview — soft-fail
        }
    }

    async _loadChecklists() {
        const ids = this._parseChecklistIds();
        // Dock Panel host: resolve the whole Application's checklists; otherwise
        // render exactly the checklistIds passed in.
        if (!ids.length && !this.recordId) {
            this._checklists = [];
            return;
        }
        this._isLoading = true;
        this._statusMessage = '';
        try {
            const data = ids.length
                ? await getChecklistsByIds({ checklistIds: ids })
                : await getChecklistsByApplicationId({ applicationId: this.recordId });
            this._checklists = Array.isArray(data) ? data : [];

            // Refresh per-file permissions (best-effort)
            this._loadPermissionsForVisibleFiles();
        } catch (e) {
            this._statusMessage = this._extractMsg(e) || 'Unable to load document checklists.';
            this._statusVariant = 'error';
            this._checklists = [];
        } finally {
            this._isLoading = false;
        }
    }

    async _loadPermissionsForVisibleFiles() {
        if (!this.fileValidatorClassName) return;
        const cvIds = [];
        this._checklists.forEach(c => (c.files || []).forEach(f => cvIds.push(f.Id)));
        if (!cvIds.length) return;
        try {
            const result = await runFilePermissions({
                validatorClassName: this.fileValidatorClassName,
                contentVersionIds:  cvIds,
                recordId:           null   // no single recordId scope wires checklist context
            });
            this._filePermissions = result || {};
        } catch (e) {
            // permission check is best-effort
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Computed: filtered + paginated checklists with UI props
    // ═══════════════════════════════════════════════════════════════════════
    get _filteredChecklists() {
        const q   = (this._searchQuery || '').trim().toLowerCase();
        const aT  = this._applicantTypeFilter;
        const dT  = this._documentTypeFilter;
        // In upload flow preview, show only the checklist created for the current
        // upload action so users see just the newly uploaded document(s).
        const scopedUploadChecklistId = this.isUploadMode && this._showAdhocPreview
            ? this._adhocPreviewChecklistId
            : null;
        // Legacy upload mode showed only ad-hoc rows when no explicit checklist
        // scope is available.
        const adhocOnly = this.isUploadMode && !this._isPddTrackingMode;
        return this._checklists.filter(c => {
            if (scopedUploadChecklistId && c.id !== scopedUploadChecklistId) return false;
            if (adhocOnly) {
                if (c.isAdHocBased !== true) return false;
            }
            if (aT && aT !== 'All' && (c.applicantType || '') !== aT) return false;
            if (dT && dT !== 'All' && (c.documentType  || '') !== dT) return false;
            if (!q) return true;
            const nameMatch = (c.name || '').toLowerCase().includes(q);
            if (nameMatch) return true;
            // Search child file names too
            return (c.files || []).some(f => (f.Title || '').toLowerCase().includes(q));
        });
    }

    get _totalPages() {
        const total = this._filteredChecklists.length;
        const size  = Math.max(1, Number(this.pageSize) || PAGE_SIZE_DEFAULT);
        return Math.max(1, Math.ceil(total / size));
    }

    get _safePage() {
        if (this._currentPage < 1) return 1;
        if (this._currentPage > this._totalPages) return this._totalPages;
        return this._currentPage;
    }

    get visibleChecklists() {
        const list = this._filteredChecklists;
        const size = Math.max(1, Number(this.pageSize) || PAGE_SIZE_DEFAULT);
        const start = (this._safePage - 1) * size;
        const slice = list.slice(start, start + size);
        return slice.map(c => this._enrichChecklist(c));
    }

    _enrichChecklist(c) {
        const isExpanded  = this._expandedChecklists.has(c.id);
        const files       = c.files || [];
        const hasFiles    = files.length > 0;

        return {
            id:                  c.id,
            displayName:         c.name || c.documentType || 'Document Checklist',
            displayCategory:     c.documentType    || '—',
            displaySubCategory:  c.applicantType   || '—',
            isExpanded,
            hasFiles,
            showDeleteAll:       hasFiles,
            cardClass:           'ecfp-cl-card',
            expandBtnClass:      isExpanded ? 'ecfp-cl-action ecfp-cl-action-expand is-open' : 'ecfp-cl-action ecfp-cl-action-expand',
            expandBtnIcon:       isExpanded ? 'utility:dash' : 'utility:add',
            expandBtnTitle:      isExpanded ? 'Collapse Checklist' : 'Expand Checklist',
            inFlightUploads:     this._inFlightUploads[c.id] || [],
            fileTiles:           files.map(f => this._enrichTile(c.id, f))
        };
    }

    _enrichTile(checklistId, cv) {
        const tileKey   = `${checklistId}::${cv.Id}`;
        const isExpanded = this._expandedTiles.has(tileKey);
        const reuploadPct = this._reuploadProgress[tileKey];
        const isReuploading = typeof reuploadPct === 'number';
        const perm = this._filePermissions[cv.Id] || {};
        const canDelete = this.fileValidatorClassName ? perm.canDelete !== false : true;

        const ext = (cv.FileExtension || '').toLowerCase();
        const fileTypeLabel = ext ? ext.toUpperCase() : (cv.FileType || '—');
        return {
            id:                cv.Id,
            tileKey,
            title:             cv.Title || 'Untitled',
            chevronClass:      isExpanded
                                  ? 'ecfp-tile-chevron is-open'
                                  : 'ecfp-tile-chevron',
            chevronIcon:       isExpanded ? 'utility:chevronup' : 'utility:chevrondown',
            chevronTitle:      isExpanded ? 'Collapse' : 'Expand',
            isExpanded,
            previewBtnClass:   'ecfp-action-btn ecfp-action-preview',
            reuploadDisabled:  isReuploading || this._deletingTiles.has(tileKey),
            deleteDisabled:    isReuploading || !canDelete,
            isDeleting:        this._deletingTiles.has(tileKey),
            isReuploading,
            reuploadPct:       isReuploading ? Math.round(reuploadPct) : 0,
            reuploadStyle:     `width: ${isReuploading ? Math.round(reuploadPct) : 0}%;`,
            fileType:          fileTypeLabel,
            size:              this._formatBytes(cv.ContentSize),
            createdDate:       this._formatDate(cv.CreatedDate),
            uploadedBy:        cv.CreatedBy && cv.CreatedBy.Name ? cv.CreatedBy.Name : 'System',
            version:           cv.VersionNumber ? `v${cv.VersionNumber}` : 'v1',
            contentDocumentId: cv.ContentDocumentId,
            _ext:              ext
        };
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Top-bar getters
    // ═══════════════════════════════════════════════════════════════════════
    get searchQuery()       { return this._searchQuery; }
    get isLoading()         { return this._isLoading; }
    get showEmptyState()    { return !this._isLoading && this._filteredChecklists.length === 0; }
    get statusMessage()     { return this._statusMessage; }
    get statusClass()       { return this._statusVariant === 'error' ? 'ecfp-status-error' : 'ecfp-status'; }
    get statusIcon()        { return this._statusVariant === 'error' ? 'utility:error' : 'utility:info'; }
    get toggleAllIcon()     { return this._allCurrentlyExpanded() ? 'utility:up' : 'utility:down'; }
    get toggleAllTitle()    { return this._allCurrentlyExpanded() ? 'Collapse All' : 'Expand All'; }

    // ═══════════════════════════════════════════════════════════════════════
    //  Pagination getters
    // ═══════════════════════════════════════════════════════════════════════
    get paginationInfoLabel() {
        return `Showing Page ${this._safePage} of ${this._totalPages}`;
    }
    get isFirstPage() { return this._safePage <= 1; }
    get isLastPage()  { return this._safePage >= this._totalPages; }
    get pageNumbers() {
        const total = this._totalPages;
        const arr   = [];
        for (let i = 1; i <= total; i++) {
            arr.push({
                num:      i,
                btnClass: i === this._safePage ? 'ecfp-page-btn is-active' : 'ecfp-page-btn'
            });
        }
        return arr;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Preview-modal getters (file-type discrimination)
    // ═══════════════════════════════════════════════════════════════════════
    get showPreview()              { return this._showPreview; }
    get previewFile()              { return this._previewFile; }
    get showDeleteAllConfirm()     { return this._showDeleteAllConfirm; }
    get deleteAllChecklistName()   { return this._deleteAllChecklistName; }

    // ── Iter 4: ad-hoc "New Ad-Hoc File" creation getters (Paths B/C) ─────
    get isCreatingAdHoc()    { return this._isCreatingAdHoc; }
    get adhocDocType()       { return this._adhocDocType; }
    get adhocApplicantType() { return this._adhocApplicantType; }
    get adhocAssetId()       { return this._adhocAssetId; }
    get adhocDocTypeOptions() {
        return (this._adhocDocTypeRaw || []).map((o) => ({
            label: o.label,
            value: o.value,
            selected: o.value === this._adhocDocType
        }));
    }
    get showApplicantTypeField() { return !this._isPddTrackingMode; }
    get showAssetField() { return this._isPddTrackingMode; }
    get applicantTypeOptions() {
        return (this._applicantTypeRaw || []).map(o => ({
            label:    o.label,
            value:    o.value,
            selected: o.value === this._adhocApplicantType
        }));
    }
    get assetOptions() {
        return (this._assetRaw || []).map((o) => ({
            label: o.label,
            value: o.value,
            selected: o.value === this._adhocAssetId
        }));
    }
    get adhocReady() {
        if (!this._adhocDocType) return false;
        if (this._isPddTrackingMode) return !!this._adhocAssetId;
        return !!this._adhocApplicantType;
    }
    get adhocNotReady()      { return !this.adhocReady; }
    get adhocStatusIdle()    { return this._adhocStatus === 'idle'; }
    get adhocCreating()      { return this._adhocStatus === 'creating'; }
    get adhocUploading()     { return this._adhocStatus === 'uploading'; }
    get adhocUploadLabel()   { return this.adhocReady ? 'Select Files' : ''; }

    // Inline Advanced Upload (rendered after the checklist is created)
    get adhocChecklistId()   { return this._adhocChecklistId; }
    get adhocMaxFiles()      { return this._adhocMaxFiles; }
    get adhocAllowedTypes()  { return this._adhocAllowedTypes; }

    // Chunky ad-hoc upload icon sourced from the special_icons static resource
    // (zip internal path: special_icons/<file>.svg).
    get adhocUploadIconUrl() { return `${SPECIAL_ICONS}/special_icons/upload-file-icon.svg`; }

    // While the creation tile is open we hide the checklist list, empty state
    // and pagination — only the tile is shown until Complete/Cancel.
    // in upload mode the list/empty-state only appear once the user
    // taps "Show Preview" (the ad-hoc-only view); otherwise just the capture tile.
    get showChecklistList() {
        if (this._isCreatingAdHoc) return false;
        if (this.isUploadMode && !this._showAdhocPreview) return false;
        return !this.showEmptyState;
    }
    get showEmptyStateView() {
        if (this._isCreatingAdHoc) return false;
        if (this.isUploadMode && !this._showAdhocPreview) return false;
        return this.showEmptyState;
    }

    // ── Mode (upload vs preview-only) ─────────────────────────────────────
    get _effectiveMode()  { return (this._modeOverride || this.mode || 'preview').toString().toLowerCase(); }
    get isUploadMode()    { return this._effectiveMode === 'upload'; }
    get isPreviewMode()   { return this._effectiveMode !== 'upload'; }
    // "+ New Ad-Hoc File" only in upload mode; the Filter replaces it in preview.
    get showAdhocNewBtn() { return this.isUploadMode && this.enableAdhocAdd; }
    get showFilter()      { return this.isPreviewMode; }

    // ── Preview-mode filters (Tags-style, options derived from the data) ──
    get applicantTypeFilterOptions() {
        return this._buildFilterOptions('applicantType', this._applicantTypeFilter);
    }
    get documentTypeFilterOptions() {
        return this._buildFilterOptions('documentType', this._documentTypeFilter);
    }
    get applicantTypeFilterLabel() { return this._applicantTypeFilter || 'All'; }
    get documentTypeFilterLabel()  { return this._documentTypeFilter || 'All'; }
    get applicantFilterToggleClass() {
        return this._openFilter === 'applicant' ? 'ecfp-filter-toggle ecfp-filter-toggle-open' : 'ecfp-filter-toggle';
    }
    get documentFilterToggleClass() {
        return this._openFilter === 'document' ? 'ecfp-filter-toggle ecfp-filter-toggle-open' : 'ecfp-filter-toggle';
    }
    get applicantFilterMenuClass() {
        return this._openFilter === 'applicant' ? 'ecfp-filter-menu ecfp-filter-menu-open' : 'ecfp-filter-menu';
    }
    get documentFilterMenuClass() {
        return this._openFilter === 'document' ? 'ecfp-filter-menu ecfp-filter-menu-open' : 'ecfp-filter-menu';
    }

    _buildFilterOptions(field, active) {
        const set = new Set();
        this._checklists.forEach(c => {
            const v = (c[field] || '').trim();
            if (v) set.add(v);
        });
        return ['All', ...Array.from(set)].map(v => ({
            value:    v,
            cssClass: v === active ? 'ecfp-filter-opt ecfp-filter-opt-active' : 'ecfp-filter-opt'
        }));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Top-bar handlers
    // ═══════════════════════════════════════════════════════════════════════
    handleSearchInput(evt) {
        this._searchQuery = evt.target.value || '';
        // Smart reset — back to page 1 on every keystroke
        this._currentPage = 1;
    }

    handleToggleAll() {
        if (this._allCurrentlyExpanded()) {
            this._collapseAll();
        } else {
            this._expandAll();
        }
    }

    handleRefresh() {
        this._loadChecklists();
    }

    // ── Preview-mode filter handlers ──────────────────────────────────────
    toggleApplicantFilter() {
        this._openFilter = this._openFilter === 'applicant' ? '' : 'applicant';
    }
    toggleDocumentFilter() {
        this._openFilter = this._openFilter === 'document' ? '' : 'document';
    }
    selectApplicantFilter(evt) {
        this._applicantTypeFilter = evt.currentTarget.dataset.value || 'All';
        this._openFilter = '';
        this._currentPage = 1;
    }
    selectDocumentFilter(evt) {
        this._documentTypeFilter = evt.currentTarget.dataset.value || 'All';
        this._openFilter = '';
        this._currentPage = 1;
    }

    _allCurrentlyExpanded() {
        const visible = this.visibleChecklists;
        if (!visible.length) return false;
        // "All expanded" = every checklist on the current page is expanded
        // AND every tile under them is also expanded.
        return visible.every(c => {
            if (!c.hasFiles) return c.isExpanded || !c.isExpanded; // ignore tile expansion when no files
            if (!c.isExpanded) return false;
            return c.fileTiles.every(t => t.isExpanded);
        });
    }

    _expandAll() {
        const expC = new Set(this._expandedChecklists);
        const expT = new Set(this._expandedTiles);
        this._checklists.forEach(c => {
            if ((c.files || []).length) {
                expC.add(c.id);
                c.files.forEach(f => expT.add(`${c.id}::${f.Id}`));
            }
        });
        this._expandedChecklists = expC;
        this._expandedTiles      = expT;
    }

    _collapseAll() {
        this._expandedChecklists = new Set();
        this._expandedTiles      = new Set();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Checklist-level handlers
    // ═══════════════════════════════════════════════════════════════════════
    handleToggleChecklist(evt) {
        const id  = evt.currentTarget.dataset.id;
        const set = new Set(this._expandedChecklists);
        const tileSet = new Set(this._expandedTiles);
        if (set.has(id)) {
            // Collapsing the checklist → collapse all its child tiles too
            set.delete(id);
            [...tileSet].forEach(k => { if (k.startsWith(`${id}::`)) tileSet.delete(k); });
        } else {
            // Expanding the checklist → expand all its child tiles too
            set.add(id);
            const cl = this._checklists.find(c => c.id === id);
            if (cl && cl.files) {
                cl.files.forEach(f => tileSet.add(`${id}::${f.Id}`));
            }
        }
        this._expandedChecklists = set;
        this._expandedTiles      = tileSet;
    }

    // ── Iter 4: ad-hoc add (Paths B/C) ────────────────────────────────────
    async _loadAdhocOptions() {
        try {
            const opts = await getAdhocAddOptions({ applicationId: this.recordId });
            this._applicantTypeRaw = (opts && opts.applicantTypeOptions) || [];
            this._assetRaw = (opts && opts.assetOptions) || [];
            this._isPddTrackingMode = !!(opts && opts.isPddTrackingMode);
            this._adhocDocTypeRaw = (opts && opts.documentTypeOptions && opts.documentTypeOptions.length)
                ? opts.documentTypeOptions
                : [{ label: 'OTHER', value: 'OTHER' }];
            this._adhocDocType = this._defaultAdhocDocType();
        } catch (e) {
            this._applicantTypeRaw = [];
            this._assetRaw = [];
            this._isPddTrackingMode = false;
            this._adhocDocTypeRaw = [{ label: 'OTHER', value: 'OTHER' }];
            this._adhocDocType = 'OTHER';
        }
    }

    handleStartAdhoc() {
        if (!this._applicantTypeRaw.length) this._loadAdhocOptions();
        this._showAdhocPreview   = false;   // back to capture-only
        this._adhocPreviewChecklistId = null;
        this._isCreatingAdHoc    = true;
        this._adhocStatus        = 'idle';
        this._adhocDocType       = this._defaultAdhocDocType();
        this._adhocApplicantType = '';
        this._adhocAssetId       = '';
        this._adhocChecklistId   = null;
        this._adhocMaxFiles      = null;
        this._adhocAllowedTypes  = '';
    }

    handleAdhocDocTypeChange(evt) {
        this._adhocDocType = evt.target.value;
    }

    handleAdhocApplicantTypeChange(evt) {
        this._adhocApplicantType = evt.target.value;
    }

    handleAdhocAssetChange(evt) {
        this._adhocAssetId = evt.target.value;
    }

    /**
     * Chunky Multi-File Upload click — first create (idempotently) the
     * Document_CheckList__c via embedDocumentChecklist, then render the Advanced
     * Document Upload (embedCustomFileUpload) INLINE against that checklist.
     */
    async handleAdhocStartUpload() {
        if (!this.adhocReady || this._adhocStatus !== 'idle') return;
        if (!this.recordId) {
            this._statusMessage = 'No Application context — cannot create the checklist.';
            this._statusVariant = 'error';
            return;
        }
        const service = this.template.querySelector('c-embed-document-checklist');
        if (!service) return;
        this._adhocStatus = 'creating';
        this._statusMessage = '';
        try {
            const res = await service.getOrCreateChecklist({
                applicationId: this.recordId,
                applicantId:   this._isPddTrackingMode ? null : this.applicantId,
                applicantType: this._isPddTrackingMode ? null : this._adhocApplicantType,
                assetId:       this._isPddTrackingMode ? this._adhocAssetId : null,
                documentType:  this._adhocDocType || 'OTHER',
                documentName:  '',
                documentCategory: ''
            });
            this._adhocChecklistId  = res && res.checklistId;
            this._adhocMaxFiles     = res && res.maxFilesAllowed;
            this._adhocAllowedTypes = (res && res.allowedFileTypes) || '';
            if (!this._adhocChecklistId) {
                throw new Error('Checklist could not be created.');
            }
            this._adhocStatus = 'uploading';
        } catch (e) {
            this._adhocStatus   = 'idle';
            this._statusMessage = this._extractMsg(e) || 'Unable to create the document checklist.';
            this._statusVariant = 'error';
        }
    }

    // Inline Advanced Upload finished → return to the preview surface so the new
    // checklist + its file tiles render.
    async handleAdhocInlineUploaded(event) {
        // When triggered by an actual upload (filesuploaded event), rename the new
        // checklist to "<Document Type> <File Name>" before returning to preview.
        const uploadedFiles = event && event.detail && event.detail.files;
        const checklistId = this._adhocChecklistId;
        if (checklistId) {
            this._adhocPreviewChecklistId = checklistId;
        }
        if (checklistId && Array.isArray(uploadedFiles) && uploadedFiles.length) {
            try {
                await stampChecklistNameFromLatestFile({ checklistId });
            } catch (e) {
                // Non-blocking: the rename is cosmetic, never fail the upload flow.
            }
        }
        // stay in upload mode and reveal the ad-hoc-only preview
        // (Is_Ad_Hoc_Based__c + OTHER), NOT the full holistic preview surface.
        this._showAdhocPreview = true;
        this.handleAdhocCancel();
        this._loadChecklists();
    }

    handleAdhocCancel() {
        this._isCreatingAdHoc    = false;
        this._adhocStatus        = 'idle';
        this._adhocDocType       = this._defaultAdhocDocType();
        this._adhocApplicantType = '';
        this._adhocAssetId       = '';
        this._adhocChecklistId   = null;
        this._adhocMaxFiles      = null;
        this._adhocAllowedTypes  = '';
    }

    _defaultAdhocDocType() {
        const options = this._adhocDocTypeRaw || [];
        return options.length ? options[0].value : 'OTHER';
    }

    handleTransferOwnership(evt) {
        const id = evt.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('transferownership', {
            detail:   { checklistId: id },
            bubbles:  true,
            composed: true
        }));
    }

    // ── Native file input (basic multi-upload) ────────────────────────────
    handleNativeFilesSelected(evt) {
        const files = Array.from(evt.target.files || []);
        const checklistId = this._pendingTargetChecklistId;
        this._pendingTargetChecklistId = null;
        if (!files.length || !checklistId) return;

        files.forEach(file => this._uploadOneNative(checklistId, file));
    }

    /**
     * Basic browser-picker upload — fetch into Blob → ContentVersion via REST.
     * Optimistic progress bar update.
     */
    async _uploadOneNative(checklistId, file) {
        const uid = `${Date.now()}_${Math.random().toString(36).slice(2,7)}`;
        this._pushInFlight(checklistId, { uid, fileName: file.name, pct: 5 });
        // ensure the checklist is expanded so the progress row is visible
        const expC = new Set(this._expandedChecklists);
        expC.add(checklistId);
        this._expandedChecklists = expC;

        const sid = this._sessionId || await getUserSessionId();
        try {
            const arrayBuf = await file.arrayBuffer();
            this._updateInFlight(checklistId, uid, 35);
            const base64   = this._arrayBufferToBase64(arrayBuf);
            this._updateInFlight(checklistId, uid, 60);

            const body = {
                Title:        file.name.replace(/\.[^/.]+$/, ''),
                PathOnClient: file.name,
                VersionData:  base64,
                FirstPublishLocationId: checklistId
            };

            const url = `${this._vfRoot}/services/data/v60.0/sobjects/ContentVersion/`;
            const resp = await fetch(url, {
                method:  'POST',
                headers: {
                    'Authorization': `Bearer ${sid}`,
                    'Content-Type':  'application/json'
                },
                body: JSON.stringify(body)
            });

            if (!resp.ok) {
                const txt = await resp.text();
                throw new Error(`HTTP ${resp.status}: ${txt}`);
            }
            this._updateInFlight(checklistId, uid, 100);
        } catch (err) {
            this._statusMessage = `Upload failed: ${this._extractMsg(err)}`;
            this._statusVariant = 'error';
        } finally {
            // remove the in-flight row + refresh checklist
            setTimeout(() => {
                this._removeInFlight(checklistId, uid);
                this._loadChecklists();
            }, 350);
        }
    }

    _pushInFlight(checklistId, entry) {
        const next = { ...this._inFlightUploads };
        const list = (next[checklistId] || []).slice();
        list.push({ ...entry, style: `width: ${entry.pct || 0}%;` });
        next[checklistId] = list;
        this._inFlightUploads = next;
    }

    _updateInFlight(checklistId, uid, pct) {
        const next = { ...this._inFlightUploads };
        const list = (next[checklistId] || []).map(e =>
            e.uid === uid ? { ...e, pct, style: `width: ${pct}%;` } : e
        );
        next[checklistId] = list;
        this._inFlightUploads = next;
    }

    _removeInFlight(checklistId, uid) {
        const next = { ...this._inFlightUploads };
        const list = (next[checklistId] || []).filter(e => e.uid !== uid);
        if (list.length) next[checklistId] = list; else delete next[checklistId];
        this._inFlightUploads = next;
    }

    // ── Delete-All ─────────────────────────────────────────────────────────
    handleDeleteAllRequest(evt) {
        const id = evt.currentTarget.dataset.id;
        const cl = this._checklists.find(c => c.id === id);
        if (!cl) return;
        this._deleteAllChecklistId   = id;
        this._deleteAllChecklistName = cl.name || cl.documentType || 'Document Checklist';
        this._showDeleteAllConfirm   = true;
    }

    cancelDeleteAll() {
        this._showDeleteAllConfirm   = false;
        this._deleteAllChecklistId   = null;
        this._deleteAllChecklistName = '';
    }

    async confirmDeleteAll() {
        const id = this._deleteAllChecklistId;
        this._showDeleteAllConfirm = false;
        if (!id) return;
        try {
            this._isLoading = true;
            await deleteAllFilesForChecklist({ checklistId: id });
            this._statusMessage = `All files removed from "${this._deleteAllChecklistName}".`;
            this._statusVariant = 'info';
            await this._loadChecklists();
        } catch (err) {
            this._statusMessage = `Delete failed: ${this._extractMsg(err)}`;
            this._statusVariant = 'error';
        } finally {
            this._isLoading = false;
            this._deleteAllChecklistId   = null;
            this._deleteAllChecklistName = '';
            // Clear messages after 4s for cleanliness
            setTimeout(() => { if (this._statusVariant === 'info') this._statusMessage = ''; }, 4000);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Tile-level handlers
    // ═══════════════════════════════════════════════════════════════════════
    handleToggleTile(evt) {
        const checklistId = evt.currentTarget.dataset.checklistId;
        const tileId      = evt.currentTarget.dataset.tileId;
        const key  = `${checklistId}::${tileId}`;
        const set  = new Set(this._expandedTiles);
        if (set.has(key)) set.delete(key); else set.add(key);
        this._expandedTiles = set;
    }

    handlePreviewClick(evt) {
        const checklistId = evt.currentTarget.dataset.checklistId;
        const tileId      = evt.currentTarget.dataset.tileId;
        const cl = this._checklists.find(c => c.id === checklistId);
        const cv = cl && (cl.files || []).find(f => f.Id === tileId);
        if (!cv) return;

        const ext = (cv.FileExtension || '').toLowerCase();

        const perm = this._filePermissions[cv.Id] || {};
        const canDownload = this.preventDownload
            ? false
            : (this.fileValidatorClassName ? perm.canDownload !== false : true);

        this._previewFile = {
            id:                cv.Id,
            title:             cv.Title || 'Untitled',
            ext,
            iconName:          this._iconForExt(ext),
            contentDocumentId: cv.ContentDocumentId,
            canDownload
        };
        this._showPreview = true;
    }

    closePreview() {
        this._showPreview = false;
        this._previewFile = {};
    }

    async handleDeleteClick(evt) {
        const checklistId = evt.currentTarget.dataset.checklistId;
        const tileId      = evt.currentTarget.dataset.tileId;
        const key  = `${checklistId}::${tileId}`;
        const set  = new Set(this._deletingTiles);
        set.add(key);
        this._deletingTiles = set;
        try {
            await deleteFile({ contentVersionId: tileId });
            await this._loadChecklists();
            this._statusMessage = 'File deleted.';
            this._statusVariant = 'info';
            setTimeout(() => { if (this._statusVariant === 'info') this._statusMessage = ''; }, 3000);
        } catch (err) {
            this._statusMessage = `Delete failed: ${this._extractMsg(err)}`;
            this._statusVariant = 'error';
        } finally {
            const after = new Set(this._deletingTiles);
            after.delete(key);
            this._deletingTiles = after;
        }
    }

    /**
     * Re-Upload (versioning) — publish a FileVersionRequest__c LMS so the
     * host's embedCustomFileUpload listens and opens its versioning flow
     * targeted at this ContentDocumentId.
     * If the host does NOT have an embedCustomFileUpload listener,
     * the action no-ops and we surface a hint.
     */
    handleReuploadClick(evt) {
        const checklistId = evt.currentTarget.dataset.checklistId;
        const tileId      = evt.currentTarget.dataset.tileId;
        const cl = this._checklists.find(c => c.id === checklistId);
        const cv = cl && (cl.files || []).find(f => f.Id === tileId);
        if (!cv) return;

        if (this.contextMessageContext) {
            publish(this.contextMessageContext, FILE_VERSION_REQUEST, {
                contentDocumentId: cv.ContentDocumentId,
                contentVersionId:  cv.Id,
                fileName:          cv.Title,
                recordId:          checklistId,   // scope re-upload to the checklist
                checklistId
            });
        }

        // Optimistic progress bar overlay
        const key = `${checklistId}::${tileId}`;
        const next = { ...this._reuploadProgress };
        next[key] = 5;
        this._reuploadProgress = next;
        let pct = 5;
        const tick = setInterval(() => {
            pct = Math.min(95, pct + Math.random() * 12);
            const cur = { ...this._reuploadProgress };
            cur[key] = pct;
            this._reuploadProgress = cur;
        }, 280);
        // Auto-clear if no listener responds within 6s
        setTimeout(() => {
            clearInterval(tick);
            const cur = { ...this._reuploadProgress };
            delete cur[key];
            this._reuploadProgress = cur;
            this._loadChecklists();
        }, 6000);

        // Forward the request for any external listeners too
        this.dispatchEvent(new CustomEvent('reuploadrequest', {
            detail: { checklistId, contentVersionId: cv.Id, contentDocumentId: cv.ContentDocumentId },
            bubbles: true,
            composed: true
        }));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Pagination handlers
    // ═══════════════════════════════════════════════════════════════════════
    handlePrevPage() {
        if (this._currentPage > 1) this._currentPage = this._currentPage - 1;
    }
    handleNextPage() {
        if (this._currentPage < this._totalPages) this._currentPage = this._currentPage + 1;
    }
    handlePageClick(evt) {
        const n = parseInt(evt.currentTarget.dataset.page, 10);
        if (!isNaN(n)) this._currentPage = n;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Modal helpers
    // ═══════════════════════════════════════════════════════════════════════
    stopPropagation(evt)    { evt.stopPropagation(); }

    // ═══════════════════════════════════════════════════════════════════════
    //  Utility helpers
    // ═══════════════════════════════════════════════════════════════════════
    _iconForExt(ext) {
        if (IMAGE_TYPES.includes(ext)) return 'doctype:image';
        if (VIDEO_TYPES.includes(ext)) return 'doctype:video';
        if (ext === 'pdf')              return 'doctype:pdf';
        if (['xlsx','xls'].includes(ext)) return 'doctype:excel';
        if (ext === 'csv')              return 'doctype:csv';
        if (ext === 'docx')             return 'doctype:word';
        if (ext === 'pptx')             return 'doctype:ppt';
        return 'doctype:unknown';
    }

    _formatBytes(b) {
        const n = Number(b) || 0;
        if (n < 1024)         return `${n} B`;
        if (n < 1024*1024)    return `${(n/1024).toFixed(1)} KB`;
        if (n < 1024*1024*1024) return `${(n/(1024*1024)).toFixed(1)} MB`;
        return `${(n/(1024*1024*1024)).toFixed(2)} GB`;
    }

    _formatDate(d) {
        if (!d) return '—';
        try {
            const dt = new Date(d);
            return dt.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: '2-digit' });
        } catch (e) {
            return '—';
        }
    }

    _buildVfRoot() {
        if (typeof window === 'undefined') return '';
        const host = window.location.hostname || '';
        // Convert lightning.force.com → my.salesforce.com (or community variant)
        if (host.endsWith('.lightning.force.com')) {
            return `https://${host.replace('.lightning.force.com', '.my.salesforce.com')}`;
        }
        if (host.includes('.sandbox.lightning.force.com')) {
            return `https://${host.replace('.sandbox.lightning.force.com', '.sandbox.my.salesforce.com')}`;
        }
        return window.location.origin;
    }

    _isExperienceCloud() {
        if (typeof window === 'undefined') return false;
        return /\.site\.com|\.force\.com\/s(\/|$)|\/sfsites\/c\//i.test(window.location.href);
    }

    _extractMsg(err) {
        if (!err) return '';
        if (typeof err === 'string') return err;
        if (err.body && err.body.message) return err.body.message;
        return err.message || String(err);
    }

    _arrayBufferToBase64(buffer) {
        let binary = '';
        const bytes = new Uint8Array(buffer);
        const len   = bytes.byteLength;
        const chunk = 0x8000;
        for (let i = 0; i < len; i += chunk) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
        }
        return btoa(binary);
    }
}