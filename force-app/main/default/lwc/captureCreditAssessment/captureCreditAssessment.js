import { LightningElement, api, track } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import invokeApexMethod from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import getMenuForPortfolio from '@salesforce/apex/dynamicStageNavigatorController.getMenuForPortfolio'
import initOrGetDocumentWithApplicantId from '@salesforce/apex/RepaymentMandateController.initOrGetDocumentWithApplicantId'
import updateDocumentChecklist from '@salesforce/apex/ApplicantBasicDetailsCaptureController.updateDocumentChecklist'
import deactivateDocument from '@salesforce/apex/DocumentChecklistToggleController.deactivateDocument'
import getUserSessionId from '@salesforce/apex/embedCustomFileUploadController.getUserSessionId'
import SPECIAL_ICONS from '@salesforce/resourceUrl/special_icons'
import { invokeHandler } from 'c/clientLayerHelper'
import {
    LOS_NEXT_STAGE_EVENT,
    LOS_GLOBAL_LOADER_EVENT,
    STAGE_CREDIT_ASSESSMENT,
    APEX_CLASS,
    APEX_PD_CLASS,
    ACTION_CREATE_PD_RECORDS,
    ACTION_GET_CREDIT_ASSESSMENT,
    ACTION_SAVE_CREDIT_ASSESSMENT,
    ACTION_FETCH_NIC_MASTER,
    CLIENT_LAYER_DEVIATION,
    DEVIATION_SUBMODULE_FLOW,
    INTEGRATION_PROGRESS_EVENT,
    PARAM_APPLICANT_ID,
    PARAM_REMARKS,
    PARAM_NIC_CODE,
    PARAM_PSL,
    PSL_SUB_TYPE_MSME,
    PSL_SUB_TYPE_AGRI,
    LOAN_CAT_PSL,
    LOAN_CAT_NON_PSL,
    PRODUCT_TYPE_PV,
    PRODUCT_TYPE_CV,
    END_USE_OPTIONS,
    LOAN_CATEGORIZATION_OPTIONS,
    NON_PSL_CATEGORIZATION_OPTIONS,
    PSL_SUB_TYPE_OPTIONS,
    TYPE_OF_ACTIVITY_OPTIONS,
    TYPE_OF_ENTERPRISE_OPTIONS,
    GST_STATUS_OPTIONS,
    AGRI_TYPE_OPTIONS,
    BORROWER_CATEGORY_OPTIONS,
    ACRE_CATEGORY_OPTIONS,
    NIC_GROUP_OPTIONS,
    NIC_CLASS_OPTIONS,
    NIC_SUB_CLASS_OPTIONS,
    buildDefaultInvestmentRows,
    buildDefaultTurnoverRows,
    UDHYAM_DOCUMENT_TYPE,
    UDHYAM_DOCUMENT_CATEGORY,
    UDHYAM_ACCEPTED_FORMATS
} from './captureCreditAssessmentConstants'

const EMPTY_UDHYAM_DOCUMENT = {
    uploaded: false,
    checklistId: '',
    contentVersionId: '',
    fileType: '',
    fileName: ''
}

const normalizeProductType = (productType) => (productType || '').trim().toUpperCase()

export default class CaptureCreditAssessment extends LightningElement {

    @api recordId
    @api currentViewId
    @api stagePhrase = ''
    @api tab = ''

    _renderAsReadOnly = false

    @api
    get renderAsReadOnly() {
        return this._renderAsReadOnly
    }

    set renderAsReadOnly(value) {
        this._renderAsReadOnly = value === true || value === 'true'
        this._showFieldsHandler()
    }

    _applicantId = null
    _isConnected = false

    @api
    get applicantId() {
        return this._applicantId
    }
    set applicantId(value) {
        const next = value || null
        if (next === this._applicantId) return
        this._applicantId = next
        this.remarksValue = ''
        this.udhyamFiles = []
        this.isUdhyamFilesExpanded = false
        this._setUdhyamDocument(EMPTY_UDHYAM_DOCUMENT)
        if (this._isConnected) {
            this._loadCreditAssessmentData()
        }
    }

    _isStagePast = false

    @api
    set isStagePast(value) {
        this._isStagePast = value === true || value === 'true'
        this._showFieldsHandler()
    }
    get isStagePast() {
        return this._isStagePast
    }

    _showFieldsHandler() {
        this.isScreenEditable = !this._isStagePast && !this._renderAsReadOnly
        if (this._pslDataLoaded) {
            this._applyFieldLocks()
        } else {
            this._refreshFieldDisplay()
        }
    }

    @track isScreenEditable = true
    @track fieldDisplay = {}
    @track remarksValue = ''
    @track isLoading = false

    @track productType = ''
    @track isCommercialPurpose = false
    @track showPslForProduct = false

    @track endUseValue = ''
    @track loanCategorizationValue = ''
    @track nonPslCategorizationValue = ''
    @track pslSubTypeValue = ''

    @track typeOfActivityValue = ''
    @track typeOfEnterpriseValue = ''
    @track gstStatusValue = ''
    @track udhyamRegistrationNoValue = ''
    @track udhyamRegistrationDateValue = ''

    @track agriTypeValue = ''
    @track borrowerCategoryValue = ''
    @track acreCategoryValue = ''

    @track nicCode = ''
    @track nicDataResponse = []
    @track showNicSearchPanel = false
    @track nicGroupValue = ''
    @track nicClassValue = ''
    @track nicSubClassValue = ''
    @track udhyamDocument = { ...EMPTY_UDHYAM_DOCUMENT }
    @track showMagicUpload = false
    @track activeUploadChecklistId = ''
    @track activeMaxFiles = null
    @track activeAllowedTypes = ''
    @track udhyamFiles = []
    @track isUdhyamFilesExpanded = false
    @track showFilePreviewer = false
    @track previewContentVersionId = null
    @track previewFileName = ''
    @track previewFileExtension = ''
    _sessionId = null
    _vfRoot = null

    @track investmentTableData = buildDefaultInvestmentRows()
    @track turnOverDataTable = buildDefaultTurnoverRows()

    @track isEndUseLocked = false
    @track isLoanCategorizationLocked = false
    @track isNonPslCategorizationLocked = false
    @track isPslSubTypeLocked = false
    @track isTypeOfActivityLocked = false
    @track isTypeOfEnterpriseLocked = false
    @track isGstStatusLocked = false
    @track isUdhyamLocked = false
    @track isAgriTypeLocked = false
    @track isBorrowerCategoryLocked = false
    @track isAcreCategoryLocked = false
    @track isNicActionLocked = false
    @track isTableInputLocked = false

    @track showIntegrationProgressModal = false
    @track integrationProgressModalStatus = 'loading'
    @track integrationProgressModalCurrentStageIdx = 0
    @track integrationProgressModalStages = []
    @track integrationProgressModalErrorMessage = ''

    _globalLoaderShown = false
    _pslDataLoaded = false
    _integrationProgressHandler

    endUseOptions = END_USE_OPTIONS
    loanCategorizationOptions = LOAN_CATEGORIZATION_OPTIONS
    nonPslCategorizationOptions = NON_PSL_CATEGORIZATION_OPTIONS
    pslSubTypeOptions = PSL_SUB_TYPE_OPTIONS
    typeOfActivityOptions = TYPE_OF_ACTIVITY_OPTIONS
    typeOfEnterpriseOptions = TYPE_OF_ENTERPRISE_OPTIONS
    gstStatusOptions = GST_STATUS_OPTIONS
    agriTypeOptions = AGRI_TYPE_OPTIONS
    borrowerCategoryOptions = BORROWER_CATEGORY_OPTIONS
    acreCategoryOptions = ACRE_CATEGORY_OPTIONS
    nicGroupOptions = NIC_GROUP_OPTIONS
    nicClassOptions = NIC_CLASS_OPTIONS
    nicSubClassOptions = NIC_SUB_CLASS_OPTIONS

    get isBorrowerApplicant() {
        return this.applicantTypeLabel === 'Borrower'
    }

    get isPvProduct() {
        const normalized = normalizeProductType(this.productType)
        return normalized === PRODUCT_TYPE_PV || normalized === '4W'
    }

    get isCvProduct() {
        return normalizeProductType(this.productType) === PRODUCT_TYPE_CV
    }

    get isNiProduct() {
        return this.showPslForProduct && (this.isPvProduct || this.isCvProduct)
    }

    get isPurposeOfPurchaseCommercial() {
        return this.isCommercialPurpose === true
    }

    get showPslSection() {
        return this.isBorrowerApplicant && this.isNiProduct
    }

    get showNonPslCategory() {
        return this.loanCategorizationValue === LOAN_CAT_NON_PSL
    }

    get showPslCategory() {
        return this.loanCategorizationValue === LOAN_CAT_PSL
    }

    get isMsme() {
        return this.pslSubTypeValue === PSL_SUB_TYPE_MSME
    }

    get isAgri() {
        return this.pslSubTypeValue === PSL_SUB_TYPE_AGRI
    }

    get showMsmeBlock() {
        return this.showPslCategory && this.isMsme
    }

    get showAgriBlock() {
        return this.showPslCategory && this.isAgri
    }

    get requiresMsmeExtendedValidation() {
        return this.showMsmeBlock
            && ((this.isPvProduct && this.isPurposeOfPurchaseCommercial) || this.isCvProduct)
    }

    get showNicList() {
        return this.nicDataResponse.length > 0
    }

    get nicSearchBtnLabel() {
        return this.showNicSearchPanel ? 'Hide Search' : 'Search NIC'
    }

    get gstStatusRadioOptions() {
        return (this.gstStatusOptions || []).map((opt) => ({
            ...opt,
            isSelected: this.gstStatusValue === opt.value
        }))
    }

    get investmentTableRows() {
        return this._mapTableRowsForDisplay(this.investmentTableData, 'investment-audit')
    }

    get turnoverTableRows() {
        return this._mapTableRowsForDisplay(this.turnOverDataTable, 'turnover-audit')
    }

    get headerTitle() {
        return this._isStagePast
            ? `${this.applicantTypeLabel} - Credit Assessment Review`
            : this.pageTitle
    }

    get sectionLabel() {
        return this._isStagePast
            ? `Remarks for ${this.applicantTypeLabel}`
            : 'Proposal Justification'
    }

    get applicantTypeLabel() {
        const token = (this.stagePhrase || '').split('_').pop().trim()
        if (!token) return 'Borrower'
        if (/^co.?borrower$/i.test(token)) return 'Co-Borrower'
        return token
    }

    get pageTitle() {
        return `${this.tab || 'Credit Assessment'} - ${this.applicantTypeLabel}`
    }

    get remarksPlaceholder() {
        return `Proposal Justification Approved for ${this.applicantTypeLabel}`
    }

    connectedCallback() {
        this._isConnected = true
        this._initFilePreviewContext()
        this._integrationProgressHandler = (event) => this.handleIntegrationProgressUpdate(event)
        window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler)
    }

    disconnectedCallback() {
        this._isConnected = false
        if (this._integrationProgressHandler) {
            window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler)
        }
        this._hideGlobalLoaderIfShown()
    }

    handleIntegrationProgressUpdate(event) {
        const detail = event.detail || {}
        this.showIntegrationProgressModal = detail.show !== false
        this.integrationProgressModalStatus = detail.status || 'loading'
        this.integrationProgressModalCurrentStageIdx = detail.currentStageIndex ?? 0
        this.integrationProgressModalStages = detail.stages || []
        this.integrationProgressModalErrorMessage = detail.errorMessage || ''
    }

    handleIntegrationProgressModalClose() {
        this.showIntegrationProgressModal = false
    }

    handleRemarksChange(event) {
        this.remarksValue = event.target.value
        this._refreshInputValidity(event.target)
    }

    handleEndUseChange(event) {
        this.endUseValue = event.detail.value
        this._refreshInputValidity(event.target)
    }

    handleLoanCategorizationChange(event) {
        const value = event.detail.value
        this.loanCategorizationValue = value
        this.nonPslCategorizationValue = ''
        this.pslSubTypeValue = ''
        this._refreshInputValidity(event.target)
    }

    handleNonPslCategorizationChange(event) {
        this.nonPslCategorizationValue = event.detail.value
        this.pslSubTypeValue = ''
        this._refreshInputValidity(event.target)
    }

    handlePslSubTypeChange(event) {
        this.pslSubTypeValue = event.detail.value
        this._refreshInputValidity(event.target)
    }

    handleTypeOfActivityChange(event) {
        this.typeOfActivityValue = event.detail.value
        this._refreshInputValidity(event.target)
    }

    handleTypeOfEnterpriseChange(event) {
        this.typeOfEnterpriseValue = event.detail.value
        this._refreshInputValidity(event.target)
    }

    handleGstStatusChange(event) {
        this.gstStatusValue = event.target.value
    }

    handleUdhyamNoChange(event) {
        this.udhyamRegistrationNoValue = event.target.value
    }

    handleUdhyamDateChange(event) {
        this.udhyamRegistrationDateValue = event.target.value
    }

    /** Opens the native date picker on first click (same as PAN DOB in basic details). */
    handleDateInputClick(event) {
        if (!this.isScreenEditable) return
        const el = event.target
        if (el && typeof el.showPicker === 'function') {
            try { el.showPicker() } catch (_) { /* showPicker can throw in iframes / unsupported browsers */ }
        }
    }

    handleAgriTypeChange(event) {
        this.agriTypeValue = event.detail.value
        this._refreshInputValidity(event.target)
    }

    handleBorrowerCategoryChange(event) {
        this.borrowerCategoryValue = event.detail.value
        this._refreshInputValidity(event.target)
    }

    handleAcreCategoryChange(event) {
        this.acreCategoryValue = event.detail.value
        this._refreshInputValidity(event.target)
    }

    handleNicCodeChange(event) {
        this.nicCode = event.target.value
    }

    async handleNicAdd() {
        const code = (this.nicCode || '').trim()
        if (!code || code.length !== 5) {
            this.showToast('Error', 'Please enter valid NIC Code.', 'error')
            return
        }
        if (this.nicDataResponse.some((row) => row.nicCode === code)) {
            this.showToast('Error', 'NIC Code already exists.', 'error')
            this.nicCode = ''
            return
        }

        try {
            const result = await this._invokeController(ACTION_FETCH_NIC_MASTER, {
                [PARAM_NIC_CODE]: code
            })

            if (result?.nicCode) {
                this.nicDataResponse = [
                    ...this.nicDataResponse,
                    {
                        nicCode: result.nicCode,
                        nicGroupDescription: result.nicGroupDescription,
                        nicClassDescription: result.nicClassDescription,
                        nicSubClassDescription: result.nicSubClassDescription
                    }
                ]
                this.nicCode = ''
            } else {
                this.showToast('Error', 'No valid data found with NIC Code', 'error')
            }
        } catch (error) {
            console.error('captureCreditAssessment: NIC lookup failed', error)
            this.showToast('Error', 'No valid data found with NIC Code', 'error')
        }
    }

    handleToggleNicSearch() {
        this.showNicSearchPanel = !this.showNicSearchPanel
    }

    handleNicGroupChange(event) {
        this.nicGroupValue = event.detail.value
        this.nicClassValue = ''
        this.nicSubClassValue = ''
    }

    handleNicClassChange(event) {
        this.nicClassValue = event.detail.value
        this.nicSubClassValue = ''
    }

    handleNicSubClassChange(event) {
        this.nicSubClassValue = event.detail.value
    }

    handleNicSearchAdd() {
        if (!this.nicSubClassValue) {
            this.showToast('NIC', 'Select Group, Class, and Sub Class.', 'warning')
            return
        }
        const code = this.nicSubClassValue
        if (this.nicDataResponse.some((row) => row.nicCode === code)) {
            this.showToast('NIC', 'This NIC code is already in the list.', 'warning')
            return
        }
        const groupLabel = this._optionLabel(this.nicGroupOptions, this.nicGroupValue)
        const classLabel = this._optionLabel(this.nicClassOptions, this.nicClassValue)
        const subClassLabel = this._optionLabel(this.nicSubClassOptions, this.nicSubClassValue)
        this.nicDataResponse = [
            ...this.nicDataResponse,
            {
                nicCode: code,
                nicGroupDescription: groupLabel,
                nicClassDescription: classLabel,
                nicSubClassDescription: subClassLabel
            }
        ]
        this.showNicSearchPanel = false
        this.nicGroupValue = ''
        this.nicClassValue = ''
        this.nicSubClassValue = ''
    }

    handleNicDelete(event) {
        const key = event.currentTarget.dataset.key
        this.nicDataResponse = this.nicDataResponse.filter((row) => row.nicCode !== key)
    }

    handleInvestmentChange(event) {
        const rowId = event.target.dataset.id
        const amount = event.target.value
        this.investmentTableData = this.investmentTableData.map((row) => (
            row.id === rowId ? { ...row, amount } : row
        ))
    }

    handleInvestmentRadioChange(event) {
        const rowId = event.target.dataset.id
        const audited = event.target.value
        this.investmentTableData = this.investmentTableData.map((row) => (
            row.id === rowId ? { ...row, audited } : row
        ))
    }

    handleTurnOverChange(event) {
        const rowId = event.target.dataset.id
        const amount = event.target.value
        this.turnOverDataTable = this.turnOverDataTable.map((row) => (
            row.id === rowId ? { ...row, amount } : row
        ))
    }

    handleTurnoverRadioChange(event) {
        const rowId = event.target.dataset.id
        const audited = event.target.value
        this.turnOverDataTable = this.turnOverDataTable.map((row) => (
            row.id === rowId ? { ...row, audited } : row
        ))
    }

    get showNicEditor() {
        return this.isScreenEditable && !this.isNicActionLocked
    }

    get previewSessionId() {
        return this._sessionId
    }

    get previewVfRoot() {
        return this._vfRoot
    }

    get chunkyUploadIconUrl() {
        return `${SPECIAL_ICONS}/special_icons/upload-file-icon.svg`
    }

    get udhyamFilesView() {
        if (this.udhyamFiles && this.udhyamFiles.length) {
            return this.udhyamFiles
        }
        const doc = this.udhyamDocument
        if (doc?.uploaded && doc.contentVersionId) {
            const name = doc.fileName || UDHYAM_DOCUMENT_TYPE
            return [{
                id: doc.contentVersionId,
                name,
                contentVersionId: doc.contentVersionId,
                extension: doc.fileType || this._extractFileExtension(name)
            }]
        }
        return []
    }

    get udhyamFilesEmpty() {
        return this.udhyamFilesView.length === 0
    }

    get udhyamFilesSingle() {
        return this.udhyamFilesView.length === 1
    }

    get udhyamFilesMulti() {
        return this.udhyamFilesView.length > 1
    }

    get udhyamSingleFile() {
        return this.udhyamFilesView[0]
    }

    get udhyamFilesCountLabel() {
        return `${this.udhyamFilesView.length} files attached`
    }

    get udhyamFilesChevron() {
        return this.isUdhyamFilesExpanded ? 'utility:chevronup' : 'utility:chevrondown'
    }

    get udhyamShowUploadBtn() {
        return this.udhyamFilesEmpty && this.isScreenEditable
    }

    get udhyamShowEmptyPlaceholder() {
        return this.udhyamFilesEmpty && !this.isScreenEditable
    }

    handleUdhyamChunkyUpload() {
        if (!this.isScreenEditable || this.isLoading) {
            return
        }
        this._openAdvancedUpload()
    }

    async _openAdvancedUpload() {
        if (!this.recordId || !this.applicantId) {
            this.showToast('Error', 'Application and applicant context are required to upload the document.', 'error')
            return
        }

        const svc = this.template.querySelector('c-embed-document-checklist')
        const context = {
            applicationId: this.recordId,
            applicantId: this.applicantId,
            applicantType: null,
            documentType: UDHYAM_DOCUMENT_TYPE,
            documentName: UDHYAM_DOCUMENT_TYPE,
            documentCategory: UDHYAM_DOCUMENT_CATEGORY
        }

        this._showGlobalLoader('Preparing document upload...')
        try {
            let checklistId = this.udhyamDocument.checklistId
            let maxFiles = 5
            let allowedTypes = UDHYAM_ACCEPTED_FORMATS

            if (svc) {
                const result = await svc.getOrCreateChecklist(context)
                checklistId = result.checklistId
                maxFiles = result.maxFilesAllowed
                allowedTypes = result.allowedFileTypes || allowedTypes
            } else if (!checklistId) {
                checklistId = await initOrGetDocumentWithApplicantId({
                    applicationId: this.recordId,
                    documentType: UDHYAM_DOCUMENT_TYPE,
                    applicantId: this.applicantId
                })
            }

            if (!checklistId) {
                this.showToast('Upload Error', 'Could not prepare the document checklist. Please retry.', 'error')
                return
            }

            this.activeUploadChecklistId = checklistId
            this.activeMaxFiles = maxFiles
            this.activeAllowedTypes = allowedTypes
            this.showMagicUpload = true
        } catch (error) {
            console.error('captureCreditAssessment: init document failed', error)
            this.showToast('Error', this._extractErrorMessage(error) || 'Unable to open document upload.', 'error')
        } finally {
            this._hideGlobalLoaderIfShown()
        }
    }

    handleMagicUploadClose() {
        this.showMagicUpload = false
    }

    stopPropagationDv(event) {
        event.stopPropagation()
    }

    // Record whether the mouse press began on the backdrop itself, so a text
    // selection started inside the dialog (and released over the backdrop) does
    // not get treated as a backdrop click and close the modal.
    handleOverlayMouseDown(event) {
        this._overlayMouseDownOnSelf = event.target === event.currentTarget
    }

    handleOverlayClick(event) {
        if (event.target === event.currentTarget && this._overlayMouseDownOnSelf) {
            this.handleMagicUploadClose()
        }
        this._overlayMouseDownOnSelf = false
    }

    async handleMagicUploadComplete(event) {
        const files = (event.detail && event.detail.files) || []
        if (!files.length) {
            this.showMagicUpload = false
            return
        }

        const mapped = this._mapUploadedFiles(files)
        const first = files[0]
        if (!first.contentVersionId) {
            this.showToast('Upload Failed', 'Uploaded file reference is missing.', 'error')
            this.showMagicUpload = false
            return
        }

        this._showGlobalLoader('Saving uploaded document...')
        try {
            await updateDocumentChecklist({
                docChecklistId: this.activeUploadChecklistId,
                documentType: UDHYAM_DOCUMENT_TYPE,
                contentVersionId: first.contentVersionId,
                contentDocumentId: null,
                applicantId: this.applicantId
            })

            const resolvedFileName = first.fileName || first.name || UDHYAM_DOCUMENT_TYPE
            this.udhyamFiles = mapped
            this._setUdhyamDocument({
                uploaded: true,
                checklistId: this.activeUploadChecklistId,
                contentVersionId: first.contentVersionId,
                fileType: mapped[0]?.extension || this._extractFileExtension(resolvedFileName) || '',
                fileName: resolvedFileName
            })
            this.showToast('Success', 'Udhyam Registration Certificate uploaded successfully.', 'success')
        } catch (error) {
            console.error('captureCreditAssessment: document link failed', error)
            this.showToast('Error', this._extractErrorMessage(error) || 'Unable to save uploaded document.', 'error')
        } finally {
            this.showMagicUpload = false
            this._hideGlobalLoaderIfShown()
        }
    }

    toggleUdhyamFilesExpand() {
        this.isUdhyamFilesExpanded = !this.isUdhyamFilesExpanded
    }

    handleFilePreviewClick(event) {
        event.preventDefault()
        event.stopPropagation()
        const ds = event.currentTarget?.dataset || {}
        const contentVersionId = ds.contentVersionId || null
        if (!contentVersionId) {
            this.showToast('Info', 'Document preview is not available.', 'info')
            return
        }
        this.previewContentVersionId = contentVersionId
        this.previewFileName = ds.fileName || ''
        this.previewFileExtension = ds.fileExtension || this._extractFileExtension(ds.fileName || '') || ''
        this.showFilePreviewer = true
    }

    handleFilePreviewClose() {
        this.showFilePreviewer = false
        this.previewContentVersionId = null
        this.previewFileName = ''
        this.previewFileExtension = ''
    }

    handleUdhyamFileDelete(event) {
        event?.preventDefault?.()
        event?.stopPropagation?.()
        if (!this.isScreenEditable) {
            return
        }
        const id = event.currentTarget?.dataset?.id || null
        const remaining = this.udhyamFilesView.filter((file) => file.id !== id)
        if (remaining.length) {
            this.udhyamFiles = remaining
            const next = remaining[0]
            this._setUdhyamDocument({
                ...this.udhyamDocument,
                contentVersionId: next.contentVersionId || '',
                fileName: next.name || '',
                fileType: next.extension || ''
            })
            return
        }

        const checklistId = this.udhyamDocument.checklistId
        this.udhyamFiles = []
        this._setUdhyamDocument(EMPTY_UDHYAM_DOCUMENT)
        if (checklistId) {
            deactivateDocument({ documentChecklistId: checklistId }).catch(() => {})
        }
    }

    _mapUploadedFiles(files) {
        return files.map((file, index) => ({
            id: file.contentVersionId || `upl-${index}`,
            name: file.fileName || file.name || 'File attached',
            contentVersionId: file.contentVersionId || null,
            extension: file.extension || this._extractFileExtension(file.fileName || file.name || '')
        }))
    }

    _initFilePreviewContext() {
        const origin = window.location.origin
        const isSite = location.pathname.split('/').length >= 2 && location.pathname.split('/')[2] === 's'
        if (isSite) {
            this._vfRoot = origin
        } else {
            const sandboxSuffix = origin.includes('sandbox') ? '.sandbox' : ''
            this._vfRoot = `${origin.split('.')[0]}--c${sandboxSuffix}.vf.force.com`
        }
        getUserSessionId()
            .then((id) => { this._sessionId = id })
            .catch(() => { /* preview download may fail without a session */ })
    }

    _extractFileExtension(fileName) {
        if (!fileName || typeof fileName !== 'string') {
            return null
        }
        const parts = fileName.split('.')
        return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : null
    }

    async handleNextButton() {
        if (!this.currentViewId) {
            this.showToast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error')
            return
        }

        if (!this.applicantId) {
            this.showToast('Error', 'Applicant context is missing. Please refresh the page.', 'error')
            return
        }

        if (this.showPslSection && !this._validatePslForm()) {
            return
        }

        const saved = await this._saveCreditAssessmentData()
        if (!saved) {
            return
        }

        const shouldRunForwardIntegrations = await this._shouldRunCreditAssessmentForwardIntegrations()
        if (shouldRunForwardIntegrations) {
            const deviationProcessed = await this._runDeviationIntegrationFlow()
            if (!deviationProcessed) {
                return
            }

            const pdCreated = await this._createPdInvestigationRecords()
            if (!pdCreated) {
                return
            }
        }

        this._dispatchNextStage()
    }

    /**
     * FICO deviation callouts and PD record creation run once when the last applicant
     * at Credit Assessment clicks Next — not on every co-applicant/guarantor submit.
     */
    async _shouldRunCreditAssessmentForwardIntegrations() {
        const stepName = this.tab || STAGE_CREDIT_ASSESSMENT
        if (!this.recordId) {
            return true
        }

        try {
            const navState = await getMenuForPortfolio({
                portfolio: null,
                applicationId: this.recordId
            })
            if (!navState?.isSuccess || !navState.menuItems?.length) {
                return true
            }

            const stepItem = this._findStepMenuItem(navState.menuItems, stepName)
            const applicants = this._collectApplicantsForStepMenuItem(stepItem)
            if (applicants.length <= 1) {
                return true
            }

            const othersStillPending = applicants.filter((entry) => {
                if (entry.applicantId === this.applicantId) {
                    return false
                }
                return !this._isApplicantCompleteForStep(entry, stepName)
            })
            return othersStillPending.length === 0
        } catch (error) {
            console.error('captureCreditAssessment: could not resolve applicant navigation scope', error)
            return true
        }
    }

    _findStepMenuItem(items, stepName) {
        const target = (stepName || '').trim().toLowerCase()
        if (!target || !items?.length) {
            return null
        }
        for (const item of items) {
            const label = (item.tab || item.label || '').trim().toLowerCase()
            if (label === target && item.subItems?.length) {
                return item
            }
            if (item.subItems?.length) {
                const found = this._findStepMenuItem(item.subItems, stepName)
                if (found) {
                    return found
                }
            }
        }
        return null
    }

    _collectApplicantsForStepMenuItem(stepItem) {
        if (!stepItem?.subItems?.length) {
            return []
        }
        const applicants = []
        for (const sub of stepItem.subItems) {
            if (sub.isGroupItem === true && Array.isArray(sub.applicants)) {
                for (const entry of sub.applicants) {
                    if (entry?.inActiveApplicant || !entry?.applicantId) {
                        continue
                    }
                    applicants.push(entry)
                }
                continue
            }
            if (sub.applicantId) {
                applicants.push({
                    applicantId: sub.applicantId,
                    tabLabel: sub.applicantType || sub.label,
                    currentLoanStageComplete: null,
                    stepMenuStatus: sub.status
                })
            }
        }
        return applicants
    }

    _isApplicantCompleteForStep(entry, stepName) {
        const step = (stepName || '').trim()
        const complete = (entry?.currentLoanStageComplete || '').trim()
        if (complete && complete === step) {
            return true
        }
        return entry?.stepMenuStatus === 'completed'
    }

    async _createPdInvestigationRecords() {
        if (!this.recordId || !this.isScreenEditable) {
            return true
        }

        this.isLoading = true
        try {
            const result = await invokeApexMethod({
                apexClassName: APEX_PD_CLASS,
                apexMethodName: ACTION_CREATE_PD_RECORDS,
                recordId: this.recordId,
                params: {}
            })

            if (result?.isSuccess !== true) {
                this.showToast(
                    'Error',
                    result?.message || 'Unable to create Personal Discussion records.',
                    'error'
                )
                return false
            }

            return true
        } catch (error) {
            console.error('captureCreditAssessment: PD record creation failed', error)
            this.showToast(
                'Error',
                error?.body?.message || error?.message || 'Unable to create Personal Discussion records.',
                'error'
            )
            return false
        } finally {
            this.isLoading = false
        }
    }

    async _runDeviationIntegrationFlow() {
        if (!this.recordId) {
            this.showToast('Error', 'Application context is missing. Please refresh the page.', 'error')
            return false
        }

        this.isLoading = true
        try {
            await invokeHandler(
                CLIENT_LAYER_DEVIATION,
                DEVIATION_SUBMODULE_FLOW,
                this
            )

            if (this.integrationProgressModalStatus === 'error') {
                return false
            }

            return true
        } catch (error) {
            console.error('captureCreditAssessment: deviation integration failed', error)
            if (!this.showIntegrationProgressModal) {
                this.showToast(
                    'Error',
                    error?.body?.message || error?.message || 'Unable to complete deviation integrations.',
                    'error'
                )
            }
            return false
        } finally {
            this.isLoading = false
        }
    }

    async _invokeController(action, params = {}) {
        return invokeApexMethod({
            apexClassName: APEX_CLASS,
            apexMethodName: action,
            recordId: this.recordId,
            params
        })
    }

    async _loadCreditAssessmentData() {
        if (!this.recordId) {
            return
        }

        this._showGlobalLoader('Loading credit assessment...')
        try {
            const result = await this._invokeController(ACTION_GET_CREDIT_ASSESSMENT, {
                [PARAM_APPLICANT_ID]: this.applicantId
            })

            this.remarksValue = result?.remarks ?? ''
            this.productType = result?.productType ?? ''
            this.isCommercialPurpose = result?.isCommercialPurpose === true
            this.showPslForProduct = result?.showPslForProduct === true

            if (result?.psl) {
                this._applyPslPayload(result.psl)
            } else {
                this._resetPslFields()
            }

            this._setUdhyamDocument(result?.udhyamDocument || EMPTY_UDHYAM_DOCUMENT)

            this._pslDataLoaded = true
            this._applyFieldLocks()
            this._refreshFieldDisplay()
        } catch (error) {
            console.error('captureCreditAssessment: load failed', error)
            this.showToast('Error', 'Unable to load credit assessment data.', 'error')
        } finally {
            this._hideGlobalLoaderIfShown()
        }
    }

    _applyPslPayload(pslPayload) {
        this.endUseValue = pslPayload.endUse || ''
        this.loanCategorizationValue = pslPayload.loanCategorization || ''
        this.nonPslCategorizationValue = pslPayload.nonPslCategorization || ''
        this.pslSubTypeValue = pslPayload.pslSubType || ''
        this.typeOfActivityValue = pslPayload.typeOfActivity || ''
        this.typeOfEnterpriseValue = pslPayload.typeOfEnterprise || ''
        this.gstStatusValue = pslPayload.gstStatus || ''
        this.udhyamRegistrationNoValue = pslPayload.udhyamRegistrationNo || ''
        this.udhyamRegistrationDateValue = pslPayload.udhyamRegistrationDate || ''
        this.agriTypeValue = pslPayload.agriType || ''
        this.borrowerCategoryValue = pslPayload.borrowerCategory || ''
        this.acreCategoryValue = pslPayload.acreCategory || ''
        this.nicDataResponse = Array.isArray(pslPayload.nicRows) ? [...pslPayload.nicRows] : []
        this.investmentTableData = this._mergeTableRows(
            buildDefaultInvestmentRows(),
            pslPayload.investmentRows
        )
        this.turnOverDataTable = this._mergeTableRows(
            buildDefaultTurnoverRows(),
            pslPayload.turnoverRows
        )
    }

    _resetPslFields() {
        this.endUseValue = ''
        this.loanCategorizationValue = ''
        this.nonPslCategorizationValue = ''
        this.pslSubTypeValue = ''
        this.typeOfActivityValue = ''
        this.typeOfEnterpriseValue = ''
        this.gstStatusValue = ''
        this.udhyamRegistrationNoValue = ''
        this.udhyamRegistrationDateValue = ''
        this.agriTypeValue = ''
        this.borrowerCategoryValue = ''
        this.acreCategoryValue = ''
        this.nicDataResponse = []
        this.investmentTableData = buildDefaultInvestmentRows()
        this.turnOverDataTable = buildDefaultTurnoverRows()
    }

    _mergeTableRows(defaultRows, savedRows) {
        if (!Array.isArray(savedRows) || savedRows.length === 0) {
            return defaultRows
        }

        const savedByYear = new Map(
            savedRows
                .filter((row) => row?.yearRange)
                .map((row) => [row.yearRange, row])
        )

        return defaultRows.map((row) => {
            const saved = savedByYear.get(row.yearRange)
            if (!saved) {
                return row
            }
            return {
                ...row,
                id: saved.id || row.id,
                amount: saved.amount ?? row.amount,
                audited: saved.audited ?? row.audited
            }
        })
    }

    _applyFieldLocks() {
        if (!this._pslDataLoaded) {
            return
        }

        const lockFields = this._isStagePast

        this.isEndUseLocked = lockFields && !!this.endUseValue
        this.isLoanCategorizationLocked = lockFields && !!this.loanCategorizationValue
        this.isNonPslCategorizationLocked = lockFields && !!this.nonPslCategorizationValue
        this.isPslSubTypeLocked = lockFields && !!this.pslSubTypeValue

        if (this.isMsme) {
            this.isTypeOfActivityLocked = lockFields && !!this.typeOfActivityValue
            this.isTypeOfEnterpriseLocked = lockFields && !!this.typeOfEnterpriseValue
            this.isGstStatusLocked = lockFields && !!this.gstStatusValue
            this.isUdhyamLocked = lockFields && !!this.udhyamRegistrationNoValue
            this.isNicActionLocked = lockFields && this.nicDataResponse.length > 0
            this.isTableInputLocked = lockFields && this._hasSavedTableData()
        } else {
            this.isTypeOfActivityLocked = false
            this.isTypeOfEnterpriseLocked = false
            this.isGstStatusLocked = false
            this.isUdhyamLocked = false
            this.isNicActionLocked = false
            this.isTableInputLocked = false
        }

        if (this.isAgri) {
            this.isAgriTypeLocked = lockFields && !!this.agriTypeValue
            this.isBorrowerCategoryLocked = lockFields && !!this.borrowerCategoryValue
            this.isAcreCategoryLocked = lockFields && !!this.acreCategoryValue
        } else {
            this.isAgriTypeLocked = false
            this.isBorrowerCategoryLocked = false
            this.isAcreCategoryLocked = false
        }

        if (this.isNicActionLocked) {
            this.showNicSearchPanel = false
        }

        this._refreshFieldDisplay()
    }

    _hasSavedTableData() {
        const hasInvestment = this.investmentTableData.some((row) => row.amount !== '' && row.amount != null)
        const hasTurnover = this.turnOverDataTable.some((row) => row.amount !== '' && row.amount != null)
        return hasInvestment && hasTurnover
    }

    _validatePslForm() {
        const comboboxes = [...this.template.querySelectorAll('lightning-combobox')]

        const comboboxesValid = comboboxes
            .filter((combobox) => !combobox.disabled)
            .reduce((validSoFar, combobox) => combobox.reportValidity() && validSoFar, true)

        if (!comboboxesValid) {
            this.showToast('Validation', 'Please fill all mandatory PSL fields.', 'warning')
            return false
        }

        if (this.requiresMsmeExtendedValidation) {
            if (!this.gstStatusValue) {
                this.showToast('Validation', 'Please select GST Status.', 'warning')
                return false
            }

            if (!this.isUdhyamLocked) {
                if (!(this.udhyamRegistrationNoValue || '').trim()) {
                    this.showToast('Validation', 'Please enter Udhyam Registration No.', 'warning')
                    return false
                }

                if (!this.udhyamRegistrationDateValue) {
                    this.showToast('Validation', 'Please enter Udhyam Registration Date.', 'warning')
                    return false
                }
            }
        }

        if (!this.requiresMsmeExtendedValidation) {
            return true
        }

        if (this.nicDataResponse.length === 0) {
            this.showToast('NIC', 'Please add at least one NIC code.', 'error')
            return false
        }

        const validInvestmentRows = this.investmentTableData.filter((row) => row.amount !== '' && row.amount != null)
        const validTurnoverRows = this.turnOverDataTable.filter((row) => row.amount !== '' && row.amount != null)

        if (validInvestmentRows.length === 0) {
            this.showToast('Investment', 'Please fill at least one row in the Investment table.', 'error')
            return false
        }

        if (validTurnoverRows.length === 0) {
            this.showToast('Turnover', 'Please fill at least one row in the Turnover table.', 'error')
            return false
        }

        if (!this.udhyamDocument.uploaded) {
            this.showToast('Document', 'Please upload the Udhyam Registration Certificate.', 'error')
            return false
        }

        return true
    }

    _buildPslSavePayload() {
        return {
            endUse: this.endUseValue,
            loanCategorization: this.loanCategorizationValue,
            nonPslCategorization: this.nonPslCategorizationValue,
            pslSubType: this.pslSubTypeValue,
            typeOfActivity: this.typeOfActivityValue,
            typeOfEnterprise: this.typeOfEnterpriseValue,
            gstStatus: this.gstStatusValue,
            udhyamRegistrationNo: this.udhyamRegistrationNoValue,
            udhyamRegistrationDate: this.udhyamRegistrationDateValue,
            agriType: this.agriTypeValue,
            borrowerCategory: this.borrowerCategoryValue,
            acreCategory: this.acreCategoryValue,
            nicRows: this.nicDataResponse,
            investmentRows: this.investmentTableData.map((row) => ({
                id: row.id,
                yearRange: row.yearRange,
                amount: row.amount,
                audited: row.audited
            })),
            turnoverRows: this.turnOverDataTable.map((row) => ({
                id: row.id,
                yearRange: row.yearRange,
                amount: row.amount,
                audited: row.audited
            }))
        }
    }

    async _saveCreditAssessmentData() {
        this._showGlobalLoader('Saving credit assessment...')
        try {
            const params = {
                [PARAM_APPLICANT_ID]: this.applicantId,
                [PARAM_REMARKS]: this.remarksValue
            }

            if (this.showPslSection) {
                params[PARAM_PSL] = this._buildPslSavePayload()
            }

            await this._invokeController(ACTION_SAVE_CREDIT_ASSESSMENT, params)
            this._applyFieldLocks()
            return true
        } catch (error) {
            console.error('captureCreditAssessment: save failed', error)
            this.showToast(
                'Error',
                this._extractErrorMessage(error) || 'Unable to save credit assessment data.',
                'error'
            )
            return false
        } finally {
            this._hideGlobalLoaderIfShown()
        }
    }

    _optionLabel(options, value) {
        const match = (options || []).find((opt) => opt.value === value)
        return match ? match.label : value
    }

    _setUdhyamDocument(payload = EMPTY_UDHYAM_DOCUMENT) {
        this.udhyamDocument = {
            uploaded: payload?.uploaded === true,
            checklistId: payload?.checklistId || '',
            contentVersionId: payload?.contentVersionId || '',
            fileType: payload?.fileType || '',
            fileName: payload?.fileName || ''
        }
        if (!this.isScreenEditable) {
            this._refreshFieldDisplay()
        }
    }

    _extractErrorMessage(error) {
        return error?.body?.message || error?.message || ''
    }

    _refreshFieldDisplay() {
        const label = (options, value) => this._optionLabel(options, value) || '—'
        const mapRows = (rows) => rows.map((row) => ({
            ...row,
            amountDisplay: row.amount === '' || row.amount == null ? '—' : String(row.amount),
            auditedDisplay: label(row.options, row.audited)
        }))

        this.fieldDisplay = {
            remarks: this.remarksValue || '—',
            endUse: label(this.endUseOptions, this.endUseValue),
            loanCategorization: label(this.loanCategorizationOptions, this.loanCategorizationValue),
            nonPslCategorization: label(this.nonPslCategorizationOptions, this.nonPslCategorizationValue),
            pslSubType: label(this.pslSubTypeOptions, this.pslSubTypeValue),
            typeOfActivity: label(this.typeOfActivityOptions, this.typeOfActivityValue),
            typeOfEnterprise: label(this.typeOfEnterpriseOptions, this.typeOfEnterpriseValue),
            gstStatus: label(this.gstStatusOptions, this.gstStatusValue),
            udhyamRegistrationNo: this.udhyamRegistrationNoValue || '—',
            udhyamRegistrationDate: this.udhyamRegistrationDateValue || '—',
            agriType: label(this.agriTypeOptions, this.agriTypeValue),
            borrowerCategory: label(this.borrowerCategoryOptions, this.borrowerCategoryValue),
            acreCategory: label(this.acreCategoryOptions, this.acreCategoryValue),
            investmentRows: mapRows(this.investmentTableData),
            turnoverRows: mapRows(this.turnOverDataTable)
        }
    }

    _mapTableRowsForDisplay(rows, radioPrefix) {
        return (rows || []).map((row) => ({
            ...row,
            radioName: `${radioPrefix}-${row.id}`,
            optionsWithState: (row.options || []).map((opt) => ({
                ...opt,
                isSelected: row.audited === opt.value
            }))
        }))
    }

    _refreshInputValidity(input) {
        if (!input?.reportValidity) {
            return
        }
        input.reportValidity()
        Promise.resolve().then(() => {
            if (input.reportValidity) {
                input.reportValidity()
            }
        })
    }

    _dispatchNextStage() {
        window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
            detail: {
                currentViewId: this.currentViewId,
                id: this.currentViewId,
                applicantId: this.applicantId,
                currentLoanStageComplete: this.tab || STAGE_CREDIT_ASSESSMENT,
                currentStagePhrase: this.stagePhrase || ''
            },
            bubbles: true,
            composed: true
        }))
    }

    _showGlobalLoader(message) {
        this.isLoading = true
        this._globalLoaderShown = true
        window.dispatchEvent(new CustomEvent(LOS_GLOBAL_LOADER_EVENT, {
            detail: { show: true, message: message || 'Loading...' }
        }))
    }

    _hideGlobalLoaderIfShown() {
        if (!this._globalLoaderShown) {
            return
        }
        this.isLoading = false
        this._globalLoaderShown = false
        window.dispatchEvent(new CustomEvent(LOS_GLOBAL_LOADER_EVENT, {
            detail: { show: false }
        }))
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }))
    }
}