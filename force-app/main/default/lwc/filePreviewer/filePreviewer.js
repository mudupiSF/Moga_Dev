import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import FORM_FACTOR from '@salesforce/client/formFactor';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPreviewData from '@salesforce/apex/filePreviewController.getPreviewData';

/**
 * sfLOSFilePreviewer
 * Inline file PREVIEW (not download) for PAN, Form 60, KYC documents
 * (Voter ID / Passport / Driving License) and any ContentDocument the LOS
 * user uploads.
 *
 * Working contexts (must all preview, not download):
 *   - Internal Salesforce desktop browser
 *   - Internal Salesforce1 mobile/tablet app
 *   - External Community sites (desktop)
 *   - External Community sites on Salesforce1 mobile/tablet
 *
 * Strategy:
 *   1. Apex `sfLOSFilePreviewController.getPreviewData` returns base64
 *      `VersionData` + `FileExtension` + `Title` + `theme` + size guard.
 *   2. PDF / Office (DOCX/XLSX/CSV) -> Blob -> URL.createObjectURL ->
 *      <iframe src=blob:...>.
 *   3. PNG/JPEG/etc -> data:image/...;base64,<bytes> -> <img src=...>.
 *   4. Community + (PDF | DOCX | XLSX) -> close LWC, NavigationMixin to
 *      `comm__namedPage overlayP4File__c` (desktop) or to the standard
 *      ContentDocument view page (mobile). The Aura overlay
 *      (sfLOSOverlayFile) hosts <lightning:fileCard> which is the only
 *      reliable preview surface for non-image files inside Communities
 *      and Salesforce1.
 *   5. Internal Mobile/Tablet + non-image -> close LWC, navigate to
 *      `standard__component c__sfLOSOverlayFile` so the same Aura overlay
 *      handles the preview natively.
 *
 * Single HTML with isDesktop / isNonDesktop branches (matching backup
 * `p4FilePreviewer.html`) — the desktop and mobile preview surfaces are
 * structurally different (modal vs lightning-card) which makes a single
 * HTML clearer than three near-identical templates. Performance is fine
 * because at most one branch is in the live DOM (the other is a sealed
 * <template if:true=...> not rendered).
 *
 * Lazy-mount: caller only renders <c-sf-l-o-s-file-previewer> while
 * `openPreview = true`, so the heavy Blob/iframe machinery never runs
 * outside an explicit preview action.
 */

export default class FilePreviewer extends NavigationMixin(LightningElement) {
    @api contentDocumentId;
    @api fileType;
    @api recordId;
    @api isCalledFromCase = false;

    @wire(CurrentPageReference)
    currentPageRef;

    @track previewData;
    @track filePreviewData;
    @track isLoading = false;
    @track error;
    @track isFileSizeLarge = false;
    @track showFrame = false;
    @track url = '';
    @track fallbackUrl;
    @track isCommunity = false;
    @track pdfViewerInitialized = false;
    @track useNativeViewer = false;
    @track isPreviewReady = false;
    @track actualFileExtension = '';

    file;
    communityIframeUrl = '';
    savedScrollPosition = 0;
    hasScrolledToTop = false;

    _bodyScrollLocked = false;

    /* ---------- Form factor ---------- */

    get isDesktop() {
        return FORM_FACTOR === 'Large';
    }
    get isNonDesktop() {
        return !this.isDesktop;
    }

    /* ---------- URL parameter resolution (lightning__UrlAddressable mode) ---------- */

    get urlFileType() {
        return this.currentPageRef && this.currentPageRef.state ? this.currentPageRef.state.c__fileType : undefined;
    }
    get urlContentDocumentId() {
        return this.currentPageRef && this.currentPageRef.state ? this.currentPageRef.state.c__contentDocumentId : undefined;
    }
    get urlRecordId() {
        if (this.recordId) return this.recordId;
        if (this.currentPageRef?.attributes?.recordId) return this.currentPageRef.attributes.recordId;
        return this.currentPageRef?.state?.c__recordId;
    }
    get resolvedFileType() {
        return this.isDesktop ? (this.fileType || this.urlFileType) : (this.urlFileType || this.fileType);
    }
    get resolvedContentDocumentId() {
        return this.isDesktop ? (this.contentDocumentId || this.urlContentDocumentId) : (this.urlContentDocumentId || this.contentDocumentId);
    }

    /* ---------- MIME detection ---------- */

    get normalizedFileType() {
        if (this.actualFileExtension) {
            return String(this.actualFileExtension).toLowerCase().replace(/^\./, '');
        }
        const t = this.resolvedFileType;
        return t ? String(t).toLowerCase().replace(/^\./, '') : '';
    }
    get isPdf() {
        return this.normalizedFileType === 'pdf';
    }
    get isImage() {
        return ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg'].includes(this.normalizedFileType);
    }
    get isDocx() {
        return ['doc', 'docx'].includes(this.normalizedFileType);
    }
    get isExcel() {
        return ['xls', 'xlsx', 'csv'].includes(this.normalizedFileType);
    }
    get isUnsupported() {
        return !this.isPdf && !this.isImage && !this.isDocx && !this.isExcel;
    }
    get hasFileId() {
        return Boolean(this.resolvedContentDocumentId);
    }
    get noFileId() {
        return !this.hasFileId;
    }

    get navigationObject() {
        return this.isCalledFromCase ? 'Case' : 'Opportunity';
    }

    /* ---------- Preview URL construction ---------- */

    /**
     * Converts base64 VersionData into a usable preview URL:
     *   PDF / Office -> blob: URL via Blob + URL.createObjectURL
     *   Image        -> data: URL (no blob needed; faster for thumbnails)
     */
    getBlobUrl(previewData) {
        this.file = {
            Title: previewData.Title,
            Extension: previewData.FileExtension,
            ContentDocumentId: previewData.ContentDocumentId,
            CreatedDate: previewData.CreatedDate,
            VersionData: previewData.VersionData,
            theme: previewData.theme,
            ContentVersionId: previewData.VersionID
        };

        try {
            if (this.isPdf) {
                this.showFrame = true;
                const bytes = this._base64ToBytes(this.file.VersionData);
                const blob = new Blob([bytes], { type: 'application/pdf' });
                this.url = window.URL.createObjectURL(blob);
            } else if (this.isImage) {
                this.showFrame = false;
                if (this.normalizedFileType === 'png') {
                    this.url = 'data:image/png;base64,' + this.file.VersionData;
                } else if (this.normalizedFileType === 'jpg' || this.normalizedFileType === 'jpeg') {
                    this.url = 'data:image/jpeg;base64,' + this.file.VersionData;
                } else {
                    this.url = 'data:image/' + this.normalizedFileType + ';base64,' + this.file.VersionData;
                }
            } else if (this.isDocx || this.isExcel) {
                const bytes = this._base64ToBytes(this.file.VersionData);
                const mimeType = this._officeMimeType();
                const blob = new Blob([bytes], { type: mimeType });
                this.url = window.URL.createObjectURL(blob);
            }
            return this.url;
        } catch (err) {
            console.error('sfLOSFilePreviewer.getBlobUrl error:', err);
            return this.fallbackUrl || `/sfc/servlet.shepherd/document/download/${this.file.ContentDocumentId}`;
        }
    }

    _base64ToBytes(b64) {
        const binary = window.atob(b64);
        const len = binary.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        return bytes;
    }

    _officeMimeType() {
        if (this.isDocx) {
            return this.normalizedFileType === 'docx'
                ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                : 'application/msword';
        }
        switch (this.normalizedFileType) {
            case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
            case 'xls':  return 'application/vnd.ms-excel';
            case 'csv':  return 'text/csv';
            default:     return 'application/octet-stream';
        }
    }

    /**
     * Returns the URL the iframe / img tag should use right now.
     * Falls back to the Shepherd download endpoint when the file is too
     * large to inline, when not isDesktop and the type is not image, etc.
     */
    get previewUrl() {
        if (!this.hasFileId || !this.isPreviewReady) return '';
        if (this.isDesktop) {
            if (this.previewData) {
                if (this.previewData.IsFileSizeLarge) {
                    const downloadUrl = `/sfc/servlet.shepherd/document/download/${this.resolvedContentDocumentId}`;
                    return this.isPdf ? `${downloadUrl}#toolbar=0` : downloadUrl;
                }
                if (this.isImage) return this.url;
                if (!this.isCommunity) {
                    return this.isPdf && this.url ? `${this.url}#toolbar=0` : this.url;
                }
            }
        } else if (this.isImage) {
            return this.url;
        }
        const fallbackUrl = `/sfc/servlet.shepherd/document/download/${this.resolvedContentDocumentId}`;
        return this.isPdf ? `${fallbackUrl}#toolbar=0` : fallbackUrl;
    }

    /* ---------- Lifecycle ---------- */

    connectedCallback() {
        // Community detection — used to decide whether inline iframe will be
        // blocked by CSP and whether to navigate to the Aura overlay instead.
        this.isCommunity = window.location.pathname.includes('/s/') ||
                           window.location.pathname.includes('/community/');
        if (!this.isDesktop) {
            this.savedScrollPosition = window.pageYOffset || document.documentElement.scrollTop;
        }
        // Lock the underlying page scroll while the preview modal is open so
        // the user can't accidentally scroll the host page behind the modal.
        // We use a counter on document.body so multiple LWC modals stack
        // safely (each one increments / decrements the same counter).
        this._lockBodyScroll(); 
        this.fetchPreviewData();
    }

    renderedCallback() {
        // Community PDFs / Office docs need the iframe `src` set imperatively
        // because declarative `src={blob:...}` can be blocked by Experience
        // Cloud CSP. Setting via DOM after first render works around this.
        if (this.isCommunity && this.isPreviewReady && this.communityIframeUrl && this.isDesktop) {
            let iframe = null;
            if (this.isPdf) iframe = this.template.querySelector('[data-id="communityPreviewIframe"]');
            else if (this.isDocx) iframe = this.template.querySelector('[data-id="communityDocxIframe"]');
            else if (this.isExcel) iframe = this.template.querySelector('[data-id="communityExcelIframe"]');
            if (iframe && !iframe.src) iframe.src = this.communityIframeUrl;
        }

        // Mobile image preview: scroll to top so the modal image is in view.
        if (!this.isDesktop && !this.hasScrolledToTop && this.isImage && this.isPreviewReady) {
            this.hasScrolledToTop = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => {
                window.scrollTo(0, 0);
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => window.scrollTo({ top: 0, behavior: 'smooth' }), 50);
            });
        }
    }

    disconnectedCallback() {
        // Always restore body scroll, even on hard unmount paths.
        this._unlockBodyScroll();
        // Revoke any object URL we created so the browser can release the
        // file bytes. Without this, a long LOS session previewing several
        // large PDFs accumulates uncollectable Blob memory.
        if (this.url && this.url.startsWith('blob:')) {
            try { window.URL.revokeObjectURL(this.url); } catch (e) { /* noop */ }
        }
    }

    /** Increment a counter on document.body and apply overflow:hidden once.
     *  Counter pattern lets multiple stacked modals share the lock safely. */
    _lockBodyScroll() {
        if (this._bodyScrollLocked) return;
        try {
            const body = document.body;
            const currentCount = parseInt(body.dataset.sflosPreviewLockCount || '0', 10) || 0;
            body.dataset.sflosPreviewLockCount = String(currentCount + 1);
            if (currentCount === 0) {
                body.dataset.sflosPreviewPrevOverflow = body.style.overflow || '';
                body.style.overflow = 'hidden';
            }
            this._bodyScrollLocked = true;
        } catch (e) { /* SSR / non-DOM contexts */ }
    }

    _unlockBodyScroll() {
        if (!this._bodyScrollLocked) return;
        try {
            const body = document.body;
            const currentCount = parseInt(body.dataset.sflosPreviewLockCount || '0', 10) || 0;
            const nextCount = Math.max(0, currentCount - 1);
            body.dataset.sflosPreviewLockCount = String(nextCount);
            if (nextCount === 0) {
                body.style.overflow = body.dataset.sflosPreviewPrevOverflow || '';
                delete body.dataset.sflosPreviewPrevOverflow;
                delete body.dataset.sflosPreviewLockCount;
            }
            this._bodyScrollLocked = false;
        } catch (e) { /* noop */ }
    }

    @api
    async refresh() {
        this.isPreviewReady = false;
        this.communityIframeUrl = '';
        this.actualFileExtension = '';
        this.hasScrolledToTop = false;
        await this.fetchPreviewData();
    }

    /* ---------- Apex fetch + post-fetch routing ---------- */

    async fetchPreviewData() {
        if (!this.resolvedContentDocumentId) return;
        this.isLoading = true;
        this.isPreviewReady = false;
        this.error = undefined;

        try {
            this.filePreviewData = await getPreviewData({ contentDocumentId: this.resolvedContentDocumentId });
            this.previewData = JSON.parse(this.filePreviewData.currentFile);

            if (this.previewData) {
                if (this.previewData.FileExtension) {
                    this.actualFileExtension = this.previewData.FileExtension;
                }
                if (this.previewData.IsFileSizeLarge) {
                    this.isFileSizeLarge = true;
                } else {
                    this.isFileSizeLarge = false;
                    this.url = this.getBlobUrl(this.previewData);
                }

                // ---- Routing: when an inline preview is impossible (community
                //               + non-image, or non-community-mobile + non-image)
                //               navigate to the Aura overlay instead.

                if (this.isCommunity && (this.isPdf || this.isDocx || this.isExcel)) {
                    // Community context can't reliably inline a `blob:` URL inside an
                    // iframe due to CSP. Navigate to Salesforce's standard
                    // ContentDocument preview page which IS allowed inside a Community.
                    // (For organisations that prefer a custom-branded community page
                    // wrapping <lightning:fileCard>, swap the type below to
                    // `comm__namedPage` with name = 'sfLOSOverlayFile__c'.)
                    this._unlockBodyScroll();
                    this.dispatchEvent(new CustomEvent('close'));
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: this.resolvedContentDocumentId,
                            objectApiName: 'ContentDocument',
                            actionName: 'view'
                        }
                    });
                    return;
                }

                if (!this.isCommunity && !this.isDesktop && !this.isImage) {
                    this._unlockBodyScroll();
                    this.dispatchEvent(new CustomEvent('close'));
                    this[NavigationMixin.Navigate]({
                        type: 'standard__component',
                        attributes: { componentName: 'c__sfLOSOverlayFile' },
                        state: {
                            c__documentId: this.resolvedContentDocumentId,
                            c__opptyId: this.urlRecordId,
                            c__theme: this.previewData?.theme || '',
                            c__documentTitle: this.previewData?.Title || '',
                            c__documentType: this.resolvedFileType || ''
                        }
                    });
                    return;
                }

                this.isPreviewReady = true;

                if (!this.isDesktop) {
                    // Force a single layout pass so iOS Safari (Salesforce1 mobile)
                    // reliably shows the modal on first render. The custom CSS now
                    // owns display/visibility, so no further imperative styling.
                    requestAnimationFrame(() => {
                        if (this.template.host) {
                            // eslint-disable-next-line no-unused-expressions
                            this.template.host.offsetHeight;
                        }
                    });
                }
            }
        } catch (err) {
            console.error('sfLOSFilePreviewer.fetchPreviewData error:', err);
            this.error = err;
            this.isPreviewReady = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Preview Error',
                message: 'Could not load file preview: ' + (err.body?.message || err.message || ''),
                variant: 'error'
            }));
            if (!this.isDesktop) {
                this.url = `/sfc/servlet.shepherd/document/download/${this.resolvedContentDocumentId}`;
            }
        } finally {
            this.isLoading = false;
        }
    }

    /* ---------- UI handlers ---------- */

    handleDownload() {
        if (this.previewUrl) window.open(this.previewUrl, '_blank');
    }

    handleDocumentOpen() {
        if (this.previewUrl) window.open(this.previewUrl, '_blank');
    }

    close() {
        if (!this.isDesktop && this.savedScrollPosition > 0) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                window.scrollTo({ top: this.savedScrollPosition, behavior: 'smooth' });
            }, 100);
        }
        this.hasScrolledToTop = false;
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }

    get isMobilePreview() {
        return !this.isDesktop;
    }
    get previewClass() {
        return this.isMobilePreview ? 'mobile-preview' : 'desktop-preview';
    }
}