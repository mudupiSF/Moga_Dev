import { LightningElement, api } from 'lwc';
import getFileExtension from '@salesforce/apex/PreviewFileUtility.getFileExtension';

export default class PreviewWord extends LightningElement {
    @api contentVersionId;
    inputContentVersionId = '';
    currentPageNumber = 0;
    showLoader = false;
    isWordFileType = true;
    fileTypeErrorMessage = '';

    async handleContentVersionIdChange(event) {
        this.inputContentVersionId = (event.target.value || '').trim();
        this.currentPageNumber = 0;
        await this.validateWordFileType();
        await this.showLoaderSection();
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
        return (
            this.hasContentVersionId &&
            this.isValidContentVersionId &&
            this.isWordFileType
        );
    }

    get showInvalidIdMessage() {
        return this.hasContentVersionId && !this.isValidContentVersionId;
    }

    get showFileTypeError() {
        return this.hasContentVersionId && this.isValidContentVersionId && !this.isWordFileType;
    }

    get sitePrefix() {
        const path = window.location.pathname || '';
        const firstSegment = path.split('/').filter(Boolean)[0];

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

    async handlePreviousPage() {
        if (this.currentPageNumber > 0) {
            this.currentPageNumber -= 1;
        }
        await this.showLoaderSection();
    }

    async handleNextPage() {
        this.currentPageNumber += 1;
        await this.showLoaderSection();
    }

    async showLoaderSection() {
        this.showLoader = true;
        await new Promise((resolve) => {
            window.setTimeout(resolve, 1000);
        });
        this.showLoader = false;
    }

    async validateWordFileType() {
        this.isWordFileType = true;
        this.fileTypeErrorMessage = '';

        if (!this.hasContentVersionId || !this.isValidContentVersionId) {
            return;
        }

        try {
            const extension = await getFileExtension({
                contentVersionId: this.resolvedContentVersionId
            });
            const normalizedExtension = (extension || '').toLowerCase();
            this.isWordFileType =
                normalizedExtension === 'docx' || normalizedExtension === 'docs';

            if (!this.isWordFileType) {
                this.fileTypeErrorMessage =
                    'Only .docx or .docs files are supported for preview.';
            }
        }
        catch (error) {
            this.isWordFileType = false;
            this.fileTypeErrorMessage =
                'Unable to validate file type. Please check ContentVersion Id and access.';
        }
    }
}