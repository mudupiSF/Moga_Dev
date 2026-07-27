import { LightningElement, api } from 'lwc';

export default class PreviewPdf extends LightningElement {
    @api contentVersionId;
    inputContentVersionId = '';
    currentPageNumber = 0;

    handleContentVersionIdChange(event) {
        this.inputContentVersionId = (event.target.value || '').trim();
        this.currentPageNumber = 0;
    }

    get resolvedContentVersionId() {
        return this.inputContentVersionId || this.contentVersionId;
    }

    get hasContentVersionId() {
        return Boolean(this.resolvedContentVersionId);
    }

    get isValidContentVersionId() {
        return /^068[a-zA-Z0-9]{12,15}$/.test(this.resolvedContentVersionId || '');
    }

    get pageNumber() {
        return this.currentPageNumber + 1;
    }

    get showPreview() {
        return this.hasContentVersionId && this.isValidContentVersionId;
    }

    get showInvalidIdMessage() {
        return this.hasContentVersionId && !this.isValidContentVersionId;
    }

    get sitePrefix() {
        const path = window.location.pathname || '';
        const firstSegment = path.split('/').filter(Boolean)[0];

        // Experience Cloud commonly uses a top-level path such as /ex.
        if (firstSegment && firstSegment !== 'lightning') {
            return `/${firstSegment}`;
        }

        return '';
    }

    get previewUrl() {
        if (!this.showPreview) {
            return '';
        }

        const versionId = encodeURIComponent(this.resolvedContentVersionId);
        return `${this.sitePrefix}/sfc/servlet.shepherd/version/renditionDownload?rendition=SVGZ&versionId=${versionId}&page=${this.currentPageNumber}&operationContext=S1`;
    }

    get isPreviousDisabled() {
        return this.currentPageNumber <= 0;
    }

    handlePreviousPage() {
        if (this.currentPageNumber > 0) {
            this.currentPageNumber -= 1;
        }
    }

    handleNextPage() {
        this.currentPageNumber += 1;
    }
}