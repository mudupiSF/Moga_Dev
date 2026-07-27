import { LightningElement, api, track } from 'lwc';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import getFilesForChecklist from '@salesforce/apex/embedCustomFilePreviewController.getFilesForChecklist';

const APEX_CLASS = 'CAMController';
const APEX_METHOD = 'getKycDetails';
const IMAGE_TYPES = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];
const PREVIEW_HEIGHT = '70vh';

export default class KycViewer extends LightningElement {
    _recordId;
    _applicantId;
    _applicantName;
    _applicantType;

    @track isLoading = true;
    @track summary = {};
    @track documents = [];
    @track showDocumentPreview = false;
    @track previewDocumentTitle = 'Document Preview';
    @track previewDocuments = [];
    @track isPreviewLoading = false;

    previewHeight = PREVIEW_HEIGHT;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.loadData();
    }

    @api
    get applicantId() {
        return this._applicantId;
    }
    set applicantId(value) {
        this._applicantId = value;
        this.loadData();
    }

    @api
    get applicantName() {
        return this._applicantName;
    }
    set applicantName(value) {
        this._applicantName = value;
    }

    @api
    get applicantType() {
        return this._applicantType;
    }
    set applicantType(value) {
        this._applicantType = value;
    }

    connectedCallback() {
        this.loadData();
    }

    get title() {
        const name = this.summary?.applicantName || this._applicantName || 'Applicant';
        const type = this.summary?.applicantType || this._applicantType || '';
        return type ? `KYC Details - ${name} (${type})` : `KYC Details - ${name}`;
    }

    get hasDocuments() {
        return this.documents.length > 0;
    }

    get hasPreviewDocuments() {
        return this.previewDocuments.length > 0;
    }

    get previewImageDocuments() {
        return this.previewDocuments.filter((doc) => IMAGE_TYPES.includes(doc.fileExtension));
    }

    get previewPdfDocuments() {
        return this.previewDocuments.filter((doc) => doc.fileExtension === 'pdf');
    }

    get hasPreviewImages() {
        return this.previewImageDocuments.length > 0;
    }

    get hasPreviewPdfs() {
        return this.previewPdfDocuments.length > 0;
    }

    async loadData() {
        if (!this._recordId || !this._applicantId) {
            return;
        }
        this.isLoading = true;
        try {
            const response = await getPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD,
                recordId: this._recordId,
                params: { applicantId: this._applicantId }
            });
            this.summary = response?.summary || {};
            this.documents = response?.documents || [];
        } catch (error) {
            this.summary = {};
            this.documents = [];
            // eslint-disable-next-line no-console
            console.error('Error loading KYC details', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleOpenFile(event) {
        const ds = event.currentTarget?.dataset || {};
        const checklistId = ds.checklistId;
        if (!checklistId) {
            return;
        }

        this.previewDocumentTitle = ds.documentType || 'Document Preview';
        this.previewDocuments = [];
        this.showDocumentPreview = true;
        this.isPreviewLoading = true;

        try {
            const files = await getFilesForChecklist({ checklistId });
            this.previewDocuments = (files || []).map((file) => this.normalizePreviewFile(file));
        } catch (error) {
            this.previewDocuments = [];
            // eslint-disable-next-line no-console
            console.error('Error loading document files', error);
        } finally {
            this.isPreviewLoading = false;
            if (!this.previewDocuments.length) {
                this.handleDocumentPreviewClose();
            }
        }
    }

    normalizePreviewFile(file) {
        const ext = (file?.FileExtension || '').toLowerCase().replace(/^\./, '');
        const contentVersionId = file?.Id || null;
        const contentDocumentId = file?.ContentDocumentId || null;
        return {
            contentVersionId,
            contentDocumentId,
            fileExtension: ext,
            fileType: ext ? ext.toUpperCase() : null,
            title: file?.Title || 'Document',
            previewUrl: contentVersionId
                ? `/sfc/servlet.shepherd/version/download/${contentVersionId}`
                : (contentDocumentId ? `/sfc/servlet.shepherd/document/download/${contentDocumentId}` : null)
        };
    }

    handleDocumentPreviewClose() {
        this.showDocumentPreview = false;
        this.previewDocuments = [];
        this.previewDocumentTitle = 'Document Preview';
        this.isPreviewLoading = false;
    }

    @api
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}