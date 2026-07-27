/**
 * additionalDocuments — Additional Documents stage for loan applications.
 * Sections: Lifecycle → Data load → Handlers → Next/Save → UI getters → Utilities.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import SPECIAL_ICONS from '@salesforce/resourceUrl/special_icons';
import getApplicableSections from '@salesforce/apex/AdditionalDocumentsController.getApplicableSections';
import initOrGetDocumentWithApplicantId from '@salesforce/apex/AdditionalDocumentsController.initOrGetDocumentWithApplicantId';
import linkContentDocument from '@salesforce/apex/AdditionalDocumentsController.linkContentDocument';
import getFileType from '@salesforce/apex/AdditionalDocumentsController.getFileType';
import submitAdditionalDocuments from '@salesforce/apex/AdditionalDocumentsController.submitAdditionalDocuments';
import saveDocumentChecklistVerificationFields from '@salesforce/apex/AdditionalDocumentsController.saveDocumentChecklistVerificationFields';
import createDocumentChecklistRow from '@salesforce/apex/AdditionalDocumentsController.createDocumentChecklistRow';
import deleteSecurityMandateRow from '@salesforce/apex/AdditionalDocumentsController.deleteSecurityMandateRow';
import getCancelledChequeUploadConfig from '@salesforce/apex/AdditionalDocumentsController.getCancelledChequeUploadConfig';
import upsertSectionFields from '@salesforce/apex/AdditionalDocumentsController.upsertSectionFields';

const DOC_STATUS_PENDING = 'Pending';
const DOC_STATUS_UPLOADED = 'Uploaded';
const DOCUMENT_NAME_CANCELLED_CHEQUE = 'Cancelled Cheque';
const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const STAGE_ADDITIONAL_DOCUMENTS = 'Additional Documents';
const ACCEPTED_FILE_FORMATS = ['.pdf', '.jpg', '.png', '.jpeg'];
const ADDITIONAL_DOCS_OPS_VIEW_TOKEN = 'Additional_Documents_Operations';
const MAX_SECURITY_MANDATE_ROWS = 5;

export default class AdditionalDocuments extends LightningElement {
    /** Application__c record Id (passed from applicationMasterPage). */
    @api recordId;
    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api applicantId;
    @api isStagePast = false;
    @api applicationStatus;

    /** Passed when loaded via listOfApplicants group flow; unused on direct stage load. */
    @api applicants;
    @api applicantCompletionOverrides;
    @api groupLabel;
    @api overrideLwc;
    
    @api screenType = '';
    @api isReadOnly = false;
    @api isCompletedView = false;

    @track sections = [];
    @track isPageLoading = false;
    @track openPreviewModal = false;
    @track previewContentDocumentId;
    @track previewFileType;

    @track securityMandateRows = [];

    @track showMagicUpload = false;

    resolvedApplicantId = '';
    isDataUpdated = false;

    activeUploadChecklistId = '';
    activeSecurityRowIndex = -1;
    activeMaxFiles = 1;
    activeAllowedTypes = 'JPEG,JPG,PDF,PNG';
    _overlayMouseDownOnSelf = false;

    _isApplicantStageComplete = false;
    _serverReadOnly = false;
    _hasLoadedData = false;
    _prevStagePastView;
    _prevCurrentViewId = '';

    pendingSelections = new Set();
    acceptedFormats = ACCEPTED_FILE_FORMATS;

    documentVerifiedOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    // ── Lifecycle ─────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadData();
    }

    renderedCallback() {
        if (!this._hasLoadedData) {
            return;
        }

        const stagePastView = this.isStagePastView;
        const viewId = this.currentViewId || '';

        if (
            stagePastView === this._prevStagePastView &&
            viewId === this._prevCurrentViewId
        ) {
            return;
        }

        this._prevStagePastView = stagePastView;
        this._prevCurrentViewId = viewId;
        this.applyCurrentStageEditableUi();
    }

    // ── Data loading (connectedCallback → loadData → mapDataToFields) ───────

    loadData() {
        if (!this.recordId && !this.applicantId) {
            this.isPageLoading = false;
            return;
        }

        this.isPageLoading = true;

        getApplicableSections({
            recordId: this.recordId,
            applicantId: this.applicantId || null,
            screenType: this.screenType || ''
        })
            .then(async (cfg) => {
                this.mapDataToFields(cfg);
                await this.applyCurrentStageEditableUi();
                this._prevStagePastView = this.isStagePastView;
                this._prevCurrentViewId = this.currentViewId || '';
                this._hasLoadedData = true;
            })
            .catch((error) => {
                this.showError('Error loading documents', error);
            })
            .finally(() => {
                this.isPageLoading = false;
            });
    }

    mapDataToFields(cfg) {
        if (!cfg) {
            return;
        }

        this.resolvedApplicantId = cfg.applicantId || this.applicantId || '';
        this._serverReadOnly = cfg.isReadOnly === true;

        const normalized = this.normalizeSections(cfg.sections || []);
        this.sections = normalized;
        this.securityMandateRows = this._mapSecurityMandateRowsFromServer(
            cfg.securityMandateRows || []
        );
    }

    _mapSecurityMandateRowsFromServer(rows) {
        return (rows || []).map((row, index) =>
            this._decorateSecurityMandateRow({
                id: row.documentChecklistId || `loaded-${index}`,
                chequeNumber: row.chequeNumber ?? '',
                bankName: row.bankName ?? '',
                micrCode: row.micrCode ?? '',
                documentChecklistId: row.documentChecklistId || '',
                contentDocumentId: row.contentDocumentId || '',
                contentVersionId: row.contentVersionId || '',
                fileName: row.fileName || '',
                fileType: row.fileType || '',
                isUploaded: !!row.isUploaded,
                documentVerified: row.documentVerified ?? '',
                remarks: row.remarks ?? '',
                rowClass: 'ad-table-row'
            })
        );
    }

    _buildNewSecurityRow(documentChecklistId) {
        return this._decorateSecurityMandateRow({
            id: documentChecklistId || `new-${Date.now()}`,
            chequeNumber: '',
            bankName: '',
            micrCode: '',
            documentChecklistId: documentChecklistId || '',
            contentDocumentId: '',
            contentVersionId: '',
            fileName: '',
            fileType: '',
            isUploaded: false,
            documentVerified: '',
            remarks: '',
            rowClass: 'ad-table-row'
        });
    }

    _decorateSecurityMandateRow(row) {
        const readonly = this.isDocumentsDisabled || !this.isFieldEditable;
        const isUploaded = !!row.isUploaded;
        return {
            ...row,
            showUploadBtn: !isUploaded && !readonly,
            showEmptyPlaceholder: !isUploaded && readonly,
            fileExtension: this.extractFileExtension(row.fileName || ''),
            canDeleteFile: !this.isDocumentsDisabled
        };
    }

    extractFileExtension(fileName) {
        if (!fileName || typeof fileName !== 'string') {
            return '';
        }
        const parts = fileName.split('.');
        return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : '';
    }

    normalizeSections(rawSections) {
        this.pendingSelections = new Set();
        const mapped = (rawSections || []).map((s) => {
            const fields = (s.fields || []).map((field) => ({
                api: field.api,
                label: field.label,
                type: field.type || 'text',
                required: !!field.required,
                value: field.value ?? '',
                options: field.options || [],
                typeIsPicklist: !!field.typeIsPicklist,
                isRadioGroup: !!field.isRadioGroup,
                isCVOVerificationField: !!field.isCVOVerificationField
            }));

            const userSelected =
                !!s.userSelected || (!!s.hasFile && !!s.userSelectable);
            if (userSelected) {
                this.pendingSelections.add(s.key);
            }

            return {
                key: s.key,
                label: s.label,
                docType: s.docType,
                required: !!s.required,
                conditional: !!s.conditional,
                enabled: userSelected || !!s.isAlwaysVisible,
                hasFile: !!s.hasFile,
                documentId: s.documentId,
                documentChecklistId: s.documentChecklistId || '',
                contentDocumentId: s.contentDocumentId,
                fileName: s.fileName || '',
                borrowerType: s.borrowerType,
                fileType: s.fileType,
                fields,
                hasFields: fields.length > 0,
                userSelected,
                isAlwaysVisible: !!s.isAlwaysVisible,
                userSelectable: !!s.userSelectable,
                isSecurityMandateSection: !!s.isSecurityMandateSection,
                isCAM: s.key === 'CAM',
                status: s.status || DOC_STATUS_PENDING,
                isUploaded: (s.status || DOC_STATUS_PENDING) === DOC_STATUS_UPLOADED,
                documentVerified: s.documentVerified ?? '',
                remarks: s.remarks ?? ''
            };
        });

        return this._decorateSectionsWithEditState(mapped);
    }

    /**
     * On the current applicant stage (not past, not OPS), keep fields editable and
     * show upload/delete actions even when server data is already complete.
     */
    async applyCurrentStageEditableUi() {
        if (this.isStagePastView || this.applicationStatus?.isWithdrawn === true) {
            return;
        }

        if (!this.isAdditionalDocsOpsView) {
            this._isApplicantStageComplete = false;
            this._refreshSectionsEditState();
            await this.ensureDocumentChecklistIds();
        }
    }

    async ensureDocumentChecklistIds() {
        if (!this.recordId || !this.resolvedApplicantId) {
            return;
        }

        const sectionsNeedingChecklist = (this.sections || []).filter(
            (s) =>
                (s.userSelected || s.isAlwaysVisible) &&
                !s.documentChecklistId
        );

        if (sectionsNeedingChecklist.length === 0) {
            return;
        }

        try {
            const updates = await Promise.all(
                sectionsNeedingChecklist.map(async (sec) => {
                    const checklistId = await initOrGetDocumentWithApplicantId({
                        applicationId: this.recordId,
                        documentType: sec.docType,
                        applicantId: this.resolvedApplicantId
                    });
                    return { key: sec.key, checklistId };
                })
            );

            this.sections = this.sections.map((sec) => {
                const match = updates.find((u) => u.key === sec.key);
                if (!match) {
                    return { ...sec };
                }
                return {
                    ...sec,
                    documentChecklistId: match.checklistId,
                    documentId: match.checklistId
                };
            });

        } catch (error) {
            console.error('Error initializing document checklists:', error);
        }
    }

    async ensureSectionDocumentChecklistId(sectionKey) {
        const sec = this.sections.find((s) => s.key === sectionKey);
        if (!sec || sec.documentChecklistId || !this.recordId || !this.resolvedApplicantId) {
            return sec?.documentChecklistId || '';
        }

        const checklistId = await initOrGetDocumentWithApplicantId({
            applicationId: this.recordId,
            documentType: sec.docType,
            applicantId: this.resolvedApplicantId
        });

        this.sections = this.sections.map((s) => {
            if (s.key !== sectionKey) {
                return { ...s };
            }
            return {
                ...s,
                documentChecklistId: checklistId,
                documentId: checklistId
            };
        });

        return checklistId;
    }

    // ── Section selection ───────────────────────────────────────────────────

    handleCheckboxChange(event) {
        const key = event.currentTarget.dataset.key;
        const checked = event.detail.checked;

        if (checked) {
            this.pendingSelections.add(key);
        } else {
            this.pendingSelections.delete(key);
        }

        this.sections = this.sections.map((s) => {
            if (s.key === key) {
                return {
                    ...s,
                    userSelected: checked,
                    enabled: checked
                };
            }
            return { ...s };
        });

        this.isDataUpdated = true;

        if (checked) {
            this.ensureSectionDocumentChecklistId(key);
        }
    }

    // ── File upload (Document_CheckList__c) ───────────────────────────────

    async handleUploadFinished(event) {
        if (this.isDocumentsDisabled || !this.isFieldEditable) {
            return;
        }

        const key = event.currentTarget.dataset.key;
        const uploadedFiles = event.detail?.files || [];
        if (!uploadedFiles.length) {
            return;
        }

        const sec = this.sections.find((s) => s.key === key);
        if (!sec) {
            return;
        }

        const contentDocumentId = uploadedFiles[0].documentId;
        const fileName = uploadedFiles[0].name || '';

        try {
            if (!this.recordId || !this.resolvedApplicantId) {
                this.showError('Upload Failed', 'Missing application or applicant details.');
                return;
            }

            await this.ensureSectionDocumentChecklistId(key);
            const checklistId =
                this.sections.find((item) => item.key === key)?.documentChecklistId || '';

            await linkContentDocument({
                documentDataJson: JSON.stringify({
                    documentType: sec.docType,
                    applicationId: this.recordId,
                    applicantId: this.resolvedApplicantId,
                    contentDocumentId
                })
            });

            const uploadedFileType = await getFileType({ contentDocumentId });

            this.sections = this._decorateSectionsWithEditState(
                this.sections.map((s) => {
                    if (s.key !== key) {
                        return { ...s };
                    }
                    return {
                        ...s,
                        hasFile: true,
                        contentDocumentId,
                        fileName,
                        fileType: uploadedFileType,
                        status: DOC_STATUS_UPLOADED,
                        isUploaded: true,
                        documentChecklistId: checklistId || s.documentChecklistId,
                        documentId: checklistId || s.documentId
                    };
                })
            );

            this.isDataUpdated = true;
            this.showSuccess('File uploaded successfully');
        } catch (error) {
            this.showError('Upload Failed', error);
        }
    }

    handleDeleteClick(event) {
        if (this.isDocumentsDisabled) {
            return;
        }

        const key = event.currentTarget.dataset.key;
        const sec = this.sections.find((s) => s.key === key);
        if (!sec || !sec.hasFile) {
            return;
        }

        this.sections = this._decorateSectionsWithEditState(
            this.sections.map((s) => {
                if (s.key !== key) {
                    return { ...s };
                }
                return {
                    ...s,
                    hasFile: false,
                    contentDocumentId: null,
                    fileName: '',
                    status: DOC_STATUS_PENDING,
                    isUploaded: false,
                    documentVerified: '',
                    remarks: '',
                    fields: (s.fields || []).map((f) => ({
                        ...f,
                        value: ''
                    }))
                };
            })
        );

        this.isDataUpdated = true;
        this.showSuccess('Document removed');
    }

    handlePreviewClick(event) {
        const key = event.currentTarget.dataset.key;
        const sec = this.sections.find((s) => s.key === key);
        if (!sec?.contentDocumentId) {
            this.showWarning('No file to preview.');
            return;
        }
        this.previewFileType = sec.fileType || 'PDF';
        this.previewContentDocumentId = sec.contentDocumentId;
        this.openPreviewModal = true;
    }

    handleFilePreviewClose() {
        this.openPreviewModal = false;
        this.previewContentDocumentId = null;
    }

    // ── Section field changes ───────────────────────────────────────────────

    handleFieldChange(event) {
        const sectionKey = event.target.dataset.section;
        const fieldApi = event.target.dataset.api;
        const newVal =
            event.detail?.value !== undefined
                ? event.detail.value
                : event.target.value;

        if (!sectionKey || !fieldApi) {
            return;
        }

        this.sections = this._decorateSectionsWithEditState(
            this.sections.map((s) => {
                if (s.key !== sectionKey) {
                    return { ...s };
                }
                return {
                    ...s,
                    fields: (s.fields || []).map((f) =>
                        f.api === fieldApi ? { ...f, value: newVal } : { ...f }
                    )
                };
            })
        );

        this.isDataUpdated = true;
    }

    // ── Security mandate table ──────────────────────────────────────────────

    get showSecurityMandateTable() {
        return (this.securityMandateRows || []).length > 0;
    }

    async handleAddSecurityRow() {
        if (this.isReadOnly) {
            return;
        }

        if (this.securityMandateRows.length >= MAX_SECURITY_MANDATE_ROWS) {
            this.showWarning(`You can't add more than ${MAX_SECURITY_MANDATE_ROWS} rows`);
            return;
        }

        if (!this.recordId || !this.resolvedApplicantId) {
            this.showWarning('Missing application or applicant details.');
            return;
        }

        try {
            const checklistId = await createDocumentChecklistRow({
                applicationId: this.recordId,
                documentType: DOCUMENT_NAME_CANCELLED_CHEQUE,
                applicantId: this.resolvedApplicantId
            });
            this.securityMandateRows = [
                ...this.securityMandateRows,
                this._buildNewSecurityRow(checklistId)
            ];
            this.isDataUpdated = true;
        } catch (error) {
            this.showError('Error adding row', error);
        }
    }

    async handleDeleteSecurityRow(event) {
        if (this.isReadOnly) {
            return;
        }

        const index = parseInt(event.currentTarget.dataset.index, 10);
        const row = this.securityMandateRows[index];
        if (!row) {
            return;
        }

        if (row.documentChecklistId) {
            try {
                this.isPageLoading = true;
                const res = await deleteSecurityMandateRow({
                    documentChecklistId: row.documentChecklistId
                });
                if (!res?.success) {
                    this.showError('Delete Failed', res?.message || 'Delete failed');
                    return;
                }
            } catch (error) {
                this.showError('Error deleting row', error);
                return;
            } finally {
                this.isPageLoading = false;
            }
        }

        this.securityMandateRows = this.securityMandateRows.filter((_, i) => i !== index);
        this.isDataUpdated = true;
        this.showSuccess('Security mandate row removed');
    }

    handleSecurityRowFieldChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const fieldName = event.target.name;
        const value =
            event.detail?.value !== undefined
                ? event.detail.value
                : event.target.value;

        const updated = [...this.securityMandateRows];
        if (!updated[index]) {
            return;
        }

        updated[index] = this._decorateSecurityMandateRow({
            ...updated[index],
            [fieldName]: value,
            rowClass: 'ad-table-row'
        });
        this.securityMandateRows = updated;
        this.isDataUpdated = true;
        this._persistSecurityMandateRow(updated[index]);
    }

    handleSecurityOpsFieldChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.name;
        const value =
            event.detail?.value !== undefined ? event.detail.value : event.target.value;

        const updated = [...this.securityMandateRows];
        if (!updated[index]) {
            return;
        }

        updated[index] = this._decorateSecurityMandateRow({
            ...updated[index],
            [field]: value,
            rowClass: 'ad-table-row'
        });
        this.securityMandateRows = updated;
        this.isDataUpdated = true;
    }

    async handleSecurityRowChunkyUpload(event) {
        if (this.isDocumentsDisabled || !this.isFieldEditable) {
            return;
        }

        const index = parseInt(event.currentTarget.dataset.index, 10);
        const row = this.securityMandateRows[index];
        if (!row) {
            return;
        }

        if (!row.documentChecklistId) {
            this.showError('Upload Failed', 'Document checklist is missing for this row.');
            return;
        }

        try {
            const config = await getCancelledChequeUploadConfig();
            this.activeMaxFiles = config?.maxFilesAllowed ?? 1;
            this.activeAllowedTypes = config?.allowedFileTypes || 'JPEG,JPG,PDF,PNG';
        } catch (error) {
            this.activeMaxFiles = 1;
            this.activeAllowedTypes = 'JPEG,JPG,PDF,PNG';
        }

        this.activeUploadChecklistId = row.documentChecklistId;
        this.activeSecurityRowIndex = index;
        this.showMagicUpload = true;
    }

    handleMagicUploadClose() {
        this.showMagicUpload = false;
        this.activeSecurityRowIndex = -1;
    }

    stopPropagationDv(event) {
        event.stopPropagation();
    }

    handleOverlayMouseDown(event) {
        this._overlayMouseDownOnSelf = event.target === event.currentTarget;
    }

    handleOverlayClick(event) {
        if (event.target === event.currentTarget && this._overlayMouseDownOnSelf) {
            this.handleMagicUploadClose();
        }
        this._overlayMouseDownOnSelf = false;
    }

    async handleSecurityMagicUploadComplete(event) {
        const files = event.detail?.files || [];
        if (!files.length) {
            this.handleMagicUploadClose();
            return;
        }

        const index = this.activeSecurityRowIndex;
        const row = this.securityMandateRows[index];
        if (!row) {
            this.handleMagicUploadClose();
            return;
        }

        const first = files[0];
        const contentVersionId = first.contentVersionId || null;
        const fileName = first.fileName || first.name || '';

        if (!contentVersionId) {
            this.showError('Upload Failed', 'Uploaded file reference is missing.');
            this.handleMagicUploadClose();
            return;
        }

        try {
            if (!this.recordId || !this.resolvedApplicantId) {
                this.showError('Upload Failed', 'Missing application or applicant details.');
                return;
            }

            const linkResult = await linkContentDocument({
                documentDataJson: JSON.stringify({
                    documentType: DOCUMENT_NAME_CANCELLED_CHEQUE,
                    applicationId: this.recordId,
                    applicantId: this.resolvedApplicantId,
                    contentVersionId,
                    documentChecklistId: row.documentChecklistId
                })
            });

            const contentDocumentId = linkResult?.contentDocumentId;
            if (!contentDocumentId) {
                this.showError('Upload Failed', 'Uploaded file reference is missing.');
                return;
            }

            const uploadedFileType = linkResult?.fileType || 'PDF';
            const resolvedFileName = linkResult?.fileName || fileName;
            const updated = [...this.securityMandateRows];
            updated[index] = this._decorateSecurityMandateRow({
                ...updated[index],
                isUploaded: true,
                contentDocumentId,
                contentVersionId: linkResult?.contentVersionId || contentVersionId,
                fileName: resolvedFileName,
                fileType: uploadedFileType,
                rowClass: 'ad-table-row'
            });
            this.securityMandateRows = updated;
            await this._persistSecurityMandateRow(updated[index]);
            this.isDataUpdated = true;
            this.showSuccess('Security cheque uploaded successfully');
        } catch (error) {
            this.showError('Upload Failed', error);
        } finally {
            this.handleMagicUploadClose();
        }
    }

    handleSecurityRowPreviewClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const row = this.securityMandateRows[index];
        if (!row?.contentDocumentId) {
            this.showWarning('No file to preview.');
            return;
        }
        this.previewFileType = row.fileType || 'PDF';
        this.previewContentDocumentId = row.contentDocumentId;
        this.openPreviewModal = true;
    }

    handleSecurityRowDeleteFile(event) {
        if (this.isDocumentsDisabled) {
            return;
        }

        const index = parseInt(event.currentTarget.dataset.index, 10);
        const row = this.securityMandateRows[index];
        if (!row?.isUploaded) {
            return;
        }

        const updated = [...this.securityMandateRows];
        updated[index] = this._decorateSecurityMandateRow({
            ...updated[index],
            isUploaded: false,
            contentDocumentId: '',
            contentVersionId: '',
            fileName: '',
            fileType: '',
            documentVerified: '',
            remarks: '',
            rowClass: 'ad-table-row'
        });
        this.securityMandateRows = updated;
        this.isDataUpdated = true;
        this.showSuccess('Security cheque removed');
    }

    _buildSecurityMandateSavePayload() {
        return (this.securityMandateRows || []).map((row) => ({
            documentChecklistId: row.documentChecklistId || '',
            chequeNumber: row.chequeNumber || '',
            bankName: row.bankName || '',
            micrCode: row.micrCode || '',
            documentVerified: row.documentVerified || '',
            remarks: row.remarks || ''
        })).filter((row) => this.hasFieldValue(row.documentChecklistId));
    }

    _buildSecurityMandateFieldMap(row) {
        return {
            Cheque_Number__c: row.chequeNumber || '',
            Bank_Name__c: row.bankName || '',
            MICR_Code__c: row.micrCode || ''
        };
    }

    async _persistSecurityMandateRow(row) {
        if (!row?.documentChecklistId || !this.recordId) {
            return;
        }

        const fieldMap = this._buildSecurityMandateFieldMap(row);
        const hasAnyValue =
            this.hasFieldValue(fieldMap.Cheque_Number__c) ||
            this.hasFieldValue(fieldMap.Bank_Name__c) ||
            this.hasFieldValue(fieldMap.MICR_Code__c);

        if (!hasAnyValue) {
            return;
        }

        try {
            await upsertSectionFields({
                recordId: this.recordId,
                documentId: row.documentChecklistId,
                sectionKey: 'SECURITY_MANDATE',
                fieldsJson: JSON.stringify(fieldMap)
            });
        } catch (error) {
            console.error('Error saving security mandate row fields:', error);
            this.showError('Save Failed', error);
        }
    }

    // ── Next / Save (handleNextButton → validateFields → save when needed → requestNextStage) ──

    /**
     * Footer Next: navigate when read-only, save when dirty, otherwise validate and advance.
     */
    async handleNextButton() {
        if (this.applicationStatus?.isWithdrawn === true) {
            return;
        }

        if (this.isStagePastView) {
            return;
        }

        if (this.isAdditionalDocsOpsView) {
            if (!this.isAdditionalDocsOpsRemarksEditable) {
                await this.markStepAndNavigate();
                return;
            }

            if (!this.validateFields()) {
                return;
            }

            this.isPageLoading = true;
            try {
                await this.ensureDocumentChecklistIds();

                const res = await saveDocumentChecklistVerificationFields({
                    verificationJson: JSON.stringify(this._buildVerificationSavePayload())
                });
                if (!res?.success) {
                    this.showError('Save Failed', res?.message || 'Submit failed');
                    return;
                }

                this.showSuccess(res.message || 'Document verification saved successfully');
                this.isDataUpdated = false;
                await this.markStepAndNavigate();
            } catch (error) {
                this.showError('Error saving document verification', error);
            } finally {
                this.isPageLoading = false;
            }
            return;
        }

        if (this.isReadOnlyScreen) {
            await this.markStepAndNavigate();
            return;
        }

        if (this.isNextDisabled) {
            return;
        }

        if (!this.isDataUpdated) {
            if (!this.validateFields()) {
                return;
            }
            await this.markStepAndNavigate();
            return;
        }

        if (!this.validateFields()) {
            return;
        }

        this.isPageLoading = true;
        try {
            await this.ensureDocumentChecklistIds();

            const res = await submitAdditionalDocuments({
                recordId: this.recordId,
                applicantId: this.resolvedApplicantId,
                sectionsJson: JSON.stringify(this.sections),
                paymentRowsJson: JSON.stringify(this._buildSecurityMandateSavePayload())
            });
            if (!res?.success) {
                this.showError('Save Failed', res?.message || 'Submit failed');
                return;
            }

            this.showSuccess(res.message || 'Additional documents saved successfully');
            this.isDataUpdated = false;
            this._markSubmittedReadOnly();
            this._refreshSectionsEditState();
            this.dispatchEvent(
                new CustomEvent('submitted', {
                    detail: { sections: this.sections }
                })
            );
            await this.markStepAndNavigate();
        } catch (error) {
            this.showError('Error saving documents', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async markStepAndNavigate() {
        if (!this.resolvedApplicantId) {
            this.showWarning('Applicant is required to continue.');
            return;
        }

        this.requestNextStage();
    }

    validateFields() {
        return this._validateFieldsInternal(true);
    }

    _validateFieldsInternal(showWarnings = true) {
        if (this.isAdditionalDocsOpsView && this.isAdditionalDocsOpsRemarksEditable) {
            const uploadedSections = this._getOpsVerificationSections();
            for (const sec of uploadedSections) {
                if (!this.hasFieldValue(sec.documentChecklistId || sec.documentId)) {
                    if (showWarnings) {
                        this.showWarning(
                            `Document checklist record is missing for ${sec.label}. Please refresh and try again.`
                        );
                    }
                    return false;
                }
                if (!this.hasFieldValue(sec.documentVerified)) {
                    if (showWarnings) {
                        this.showWarning(`Please select Document Verified for ${sec.label}`);
                    }
                    return false;
                }
                if (!this.hasFieldValue(sec.remarks)) {
                    if (showWarnings) {
                        this.showWarning(`Please enter Remarks for ${sec.label}`);
                    }
                    return false;
                }
            }
            return true;
        }

        if (!this.sections || this.sections.length === 0) {
            if (showWarnings) {
                this.showWarning('No document sections are available.');
            }
            return false;
        }

        // Only enforce Security Mandate when the user selected it (or when explicitly configured as required).
        if (this.requiresSecurityMandate && !this.isSecurityMandateComplete) {
            if (showWarnings) {
                this.showWarning('Please complete security mandate details before proceeding.');
            }
            return false;
        }

        // Only enforce uploads for user-selected sections (plus explicitly required ones).
        const missingUpload = (this.sections || []).some((sec) => {
            if (sec.isSecurityMandateSection) {
                return false;
            }
            const isRequiredByUser =
                sec.userSelected === true || (sec.required === true && sec.isAlwaysVisible === true);
            if (!isRequiredByUser) {
                return false;
            }
            if (sec.enabled === false) {
                return false;
            }
            return !sec.hasFile;
        });
        if (missingUpload) {
            if (showWarnings) {
                this.showWarning('Please upload all required documents before proceeding.');
            }
            return false;
        }

        // Only enforce required fields for user-selected sections (plus explicitly required ones) once a file exists.
        const missingField = (this.sections || []).some((sec) => {
            if (!sec.enabled || !sec.fields || sec.fields.length === 0) {
                return false;
            }
            const isRequiredByUser =
                sec.userSelected === true || (sec.required === true && sec.isAlwaysVisible === true);
            if (!isRequiredByUser) {
                return false;
            }
            if (!sec.hasFile) {
                return false;
            }
            return sec.fields.some(
                (field) => field.required && this._isFieldValueEmpty(field.value)
            );
        });
        if (missingField) {
            if (showWarnings) {
                this.showWarning('Please complete all required fields before proceeding.');
            }
            return false;
        }
        return true;
    }

    _markSubmittedReadOnly() {
        this._isApplicantStageComplete = true;
    }

    /**
     * Builds one verification payload row per uploaded document, keyed by Document_CheckList__c Id.
     */
    _buildVerificationSavePayload() {
        return this._getOpsVerificationSections().map((sec) => ({
                documentChecklistId: sec.documentChecklistId || sec.documentId || '',
                documentVerified: sec.documentVerified || '',
                remarks: sec.remarks || ''
            }))
            .filter((row) => this.hasFieldValue(row.documentChecklistId));
    }

    requestNextStage() {
        const currentViewId = this.currentViewId;
        if (!currentViewId) {
            this.showError('Navigation Error', 'Current view ID is missing. Please refresh the page.');
            return;
        }

        window.dispatchEvent(
            new CustomEvent(LOS_NEXT_STAGE_EVENT, {
                detail: {
                    currentViewId,
                    id: currentViewId,
                    applicantId: this.resolvedApplicantId,
                    currentLoanStageComplete: this.tab || STAGE_ADDITIONAL_DOCUMENTS,
                    currentStagePhrase: this.stagePhrase || ''
                },
                bubbles: true,
                composed: true
            })
        );
    }

    // ── UI state getters ────────────────────────────────────────────────────

    get chunkyUploadIconUrl() {
        return `${SPECIAL_ICONS}/special_icons/upload-file-icon.svg`;
    }

    get isStagePastView() {
        return this.isStagePast === true || this.isStagePast === 'true';
    }

    get isAdditionalDocsOpsView() {
        return (this.currentViewId || '').includes(ADDITIONAL_DOCS_OPS_VIEW_TOKEN);
    }

    get isReadOnlyScreen() {
        return (
            this.isStagePastView ||
            this._isApplicantStageComplete ||
            this.applicationStatus?.isWithdrawn === true
        );
    }

    get isAdditionalDocsOpsRemarksEditable() {
        return this.isAdditionalDocsOpsView && !this.isStagePastView;
    }

    get isReadOnly() {
        return this.isReadOnlyScreen || this.isAdditionalDocsOpsView;
    }

    get isFieldEditable() {
        return !this.isReadOnlyScreen && !this.isAdditionalDocsOpsView;
    }

    /** Hides document upload and delete in OPS view or read-only stage. Preview remains visible. */
    get isDocumentsDisabled() {
        return this.isAdditionalDocsOpsView || this.isReadOnlyScreen;
    }

    get showDocumentActions() {
        return !this.isDocumentsDisabled;
    }

    get showDocumentDelete() {
        return !this.isDocumentsDisabled;
    }

    get showSecurityMandateOpsColumns() {
        return this.isAdditionalDocsOpsView;
    }

    get showStandaloneOperationsHeader() {
        return this.isAdditionalDocsOpsView && !this.showSecurityMandateSection;
    }

    get hasConditionalSections() {
        return this.conditionalSections.length > 0;
    }

    get hasUploadSections() {
        return this.uploadSections.length > 0;
    }

    get conditionalSections() {
        return (this.sections || []).filter(
            (s) => s.userSelectable && !s.isAlwaysVisible
        );
    }

    get uploadSections() {
        return (this.sections || []).filter(
            (s) =>
                (s.userSelected || s.isAlwaysVisible) &&
                !s.isSecurityMandateSection
        );
    }

    get showSecurityMandateSection() {
        return (this.sections || []).some((s) => s.isSecurityMandateSection);
    }

    get requiresSecurityMandate() {
        const sec = (this.sections || []).find((s) => s.isSecurityMandateSection);
        if (!sec) {
            return false;
        }
        return sec.userSelected === true || (sec.required === true && sec.isAlwaysVisible === true);
    }

    get isSecurityMandateComplete() {
        if (!this.showSecurityMandateSection) {
            return true;
        }
        if (!this.securityMandateRows || this.securityMandateRows.length === 0) {
            return false;
        }
        return this.securityMandateRows.every(
            (row) =>
                this.hasFieldValue(row.chequeNumber) &&
                this.hasFieldValue(row.bankName) &&
                row.isUploaded
        );
    }

    /** True when Next should be disabled (loading, withdrawn, past stage, or OPS rules). */
    get isNextDisabled() {
        if (
            this.isPageLoading ||
            this.isStagePastView ||
            this.applicationStatus?.isWithdrawn === true
        ) {
            return true;
        }

        if (this.isAdditionalDocsOpsRemarksEditable) {
            return this._getOpsVerificationSections().some(
                (sec) =>
                    !this.hasFieldValue(sec.documentVerified) ||
                    !this.hasFieldValue(sec.remarks)
            );
        }

        if (this._isApplicantStageComplete) {
            return false;
        }

        // Disable Next until selected checkbox documents (and any explicitly required ones) are complete.
        if (!this.isAdditionalDocsOpsView && !this.isReadOnlyScreen) {
            return !this._validateFieldsInternal(false);
        }

        return false;
    }

    hasFieldValue(value) {
        return value != null && String(value).trim() !== '';
    }

    // ── Section decoration helpers ──────────────────────────────────────────

    /** Ops Document Verified / Remarks apply to uploaded Security Mandate rows. */
    _getOpsVerificationSections() {
        return (this.securityMandateRows || [])
            .filter((row) => row.isUploaded && this.hasFieldValue(row.documentChecklistId))
            .map((row) => ({
                label: 'Security Mandate',
                documentChecklistId: row.documentChecklistId,
                documentVerified: row.documentVerified || '',
                remarks: row.remarks || ''
            }));
    }

    _refreshSectionsEditState() {
        this.sections = this._decorateSectionsWithEditState(this.sections);
    }

    _decorateSectionsWithEditState(sections) {
        return (sections || []).map((section) => this._decorateSection(section));
    }

    _decorateSection(section) {
        return {
            ...section,
            fields: (section.fields || []).map((field) => ({
                ...field,
                displayValue: this._getFieldDisplayValue(field)
            }))
        };
    }

    _getFieldDisplayValue(field) {
        if (this._isFieldValueEmpty(field.value)) {
            return '—';
        }
        if (field.typeIsPicklist && field.options?.length) {
            const match = field.options.find(
                (opt) => opt.value === field.value || opt.label === field.value
            );
            return match?.label || field.value;
        }
        return String(field.value);
    }

    _isFieldValueEmpty(value) {
        return value === null || value === undefined || String(value).trim() === '';
    }

    // ── Toast notifications ─────────────────────────────────────────────────

    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({ title: 'Success', message, variant: 'success' })
        );
    }

    showError(title, error) {
        let message = 'An error occurred';
        if (error?.body?.message) {
            message = error.body.message;
        } else if (error?.message) {
            message = error.message;
        } else if (typeof error === 'string') {
            message = error;
        }

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    showWarning(message) {
        this.dispatchEvent(
            new ShowToastEvent({ title: 'Warning', message, variant: 'warning' })
        );
    }
}