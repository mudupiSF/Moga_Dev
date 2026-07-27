import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { updateRecord, createRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import isPhysicalAgreement from '@salesforce/apex/AgreementController.isPhysicalAgreement';
import setAgreementType from '@salesforce/apex/AgreementController.setAgreementType';
import getGeographicalState from '@salesforce/apex/AgreementController.getGeographicalState';
import getLoanAgreementDetails from '@salesforce/apex/AgreementController.getLoanAgreementDetails';
import fetchAgreementBookletDetails from '@salesforce/apex/AgreementController.fetchAgreementBookletDetails';
import checkApiExecutionStatus from '@salesforce/apex/AgreementController.checkApiExecutionStatus';
import initOrGetDocumentWithApplicantId from '@salesforce/apex/AgreementController.initOrGetDocumentWithApplicantId';
import getFileType from '@salesforce/apex/AgreementController.getFileType';
import deleteContentDocument from '@salesforce/apex/AgreementController.deleteContentDocument';
import linkContentDocument from '@salesforce/apex/AgreementController.linkContentDocument';
import markAgreementStageComplete from '@salesforce/apex/AgreementController.markAgreementStageComplete';

const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const STAGE_AGREEMENT = 'Agreement';
const STAMPING_SERVICE = 'StampingDetailsP4';
const NO_GEO_STATE = 'NoGeoStateCodeFound';
const AGREEMENT_TYPE_PHYSICAL = 'Physical agreement';
const AGREEMENT_OBJECT = 'Agreement__c';
const AGREEMENT_TYPE_E = 'e-agreement';
const INITIATION_FACE_TO_FACE = 'Face to Face';
const INITIATION_CUSTOMER_JOURNEY = 'Customer Journey';
const ACCEPTED_FILE_FORMATS = ['.pdf', '.jpg', '.jpeg', '.png'];
const ESIGN_DOC_TYPE = 'Agreement Copy';
const AGREEMENT_OPS_VIEW_ID = 'Wheels_Agreement_OPS';
const FIELD_AGREEMENT_CORRECTLY_CAPTURED = 'Agreement_Correctly_Captured__c';
const FIELD_REMARKS = 'Remarks__c';

const AGREEMENT_CORRECTLY_CAPTURED_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];

const INITIATION_METHOD_OPTIONS = [
    { label: 'Face to Face', value: INITIATION_FACE_TO_FACE },
    { label: 'Customer Journey', value: INITIATION_CUSTOMER_JOURNEY }
];

const PHYSICAL_DOCUMENT_SLOTS = [
    { key: 'wrapperBooklet', docType: 'Agreement Wrapper Booklet', label: 'Wrapper Booklet' },
    { key: 'stampingPage', docType: 'Stamping Page', label: 'Stamping Page' },
    { key: 'firstSchedule', docType: 'Agreement 1st Schedule', label: '1st Schedule' },
    { key: 'secondSchedule', docType: 'Agreement 2nd Schedule', label: '2nd Schedule' }
];

/** Demo mode: stub initiation/status APIs and enable Next for Customer Journey without integrations. */
const USE_DEMO_STUBS = true;

/**
 * Physical and e-agreement stage for loan applications.
 * Sections: Lifecycle, Initialization, Field handlers, Stamping, E-agreement,
 * Document upload, Next/Save, UI getters, Toasts, Demo stubs.
 */
export default class Agreement extends NavigationMixin(LightningElement) {

    /** Application__c record Id (passed from applicationMasterPage). */
    @api recordId;
    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api applicantId;
    @api isStagePast = false;
    @api applicationStatus;
    @api fromAssetList = false;

    /** Passed when loaded via listOfApplicants group flow; unused on direct stage load. */
    @api applicants;
    @api applicantCompletionOverrides;
    @api groupLabel;
    @api overrideLwc;

    _applicationLineItemId = '';

    @api
    get applicationLineItemId() {
        return this._applicationLineItemId;
    }
    set applicationLineItemId(value) {
        this._applicationLineItemId = value || '';
        this._tryLoadAgreementData();
    }

    @track isPhysicalAgreementMode = true;
    @track isPageLoading = false;
    @track showFetchDetailBtn = false;
    @track showDocumentUploadSection = false;
    @track showInitiationMethod = false;
    @track showNextButton = false;
    @track isButtonDisabled = false;
    @track isBookletNumberDisabled = false;
    @track isStampingChargesDisabled = true;
    @track hideInitiateAgreementBtn = false;
    @track showCheckStatusButton = false;
    @track disableDownloadAgreement = true;
    @track showUploadButton = false;
    @track initiationMethod = '';
    @track agreementDownloadCompleted = false;
    @track physicalDocuments = [];
    @track openPreviewModal = false;
    @track previewContentDocumentId;
    @track previewFileType;

    @track agreementData = {
        geoStateCode: '',
        geographicalState: '',
        stampingCharges: '',
        agreementBookletNo: '',
        agreementCorrectlyCaptured: '',
        remarks: ''
    };

    @track esignAgreement = {
        uploaded: false,
        fileName: '',
        contentDocumentId: '',
        documentChecklistId: ''
    };

    @track checkStatus = {
        kfs: true,
        processInitiated: false,
        borrowerSigned: false,
        guarantorSigned: false,
        lenderSigned: false
    };

    borrowerId;
    coBorrowerId;
    loanAgreementId;
    dealId;
    vehicleId;
    initiatedEAgreement = false;
    isEStampApplicable = false;
    isStampingAPISuccess = false;
    checkAgreementEligibility = false;
    stampingLogs = [];
    isDataUpdated = false;

    _isApplicantStageComplete = false;
    _serverReadOnly = false;

    acceptedFormats = ACCEPTED_FILE_FORMATS;
    agreementCorrectlyCapturedOptions = AGREEMENT_CORRECTLY_CAPTURED_OPTIONS;

    // ── Lifecycle ─────────────────────────────────────────────────────────

    connectedCallback() {

        console.log('repaymentMandate recordId:', JSON.stringify(this.recordId));
        console.log('repaymentMandate currentViewId:', JSON.stringify(this.currentViewId));
        console.log('repaymentMandate stagePhrase:', JSON.stringify(this.stagePhrase));
        console.log('repaymentMandate tab:', JSON.stringify(this.tab));
        console.log('repaymentMandate applicantId:', JSON.stringify(this.applicantId));
        console.log('repaymentMandate isStagePast:', JSON.stringify(this.isStagePast));
        console.log('repaymentMandate applicants:', JSON.stringify(this.applicants));
        console.log('repaymentMandate applicantCompletionOverrides:', JSON.stringify(this.applicantCompletionOverrides));
        console.log('repaymentMandate groupLabel:', JSON.stringify(this.groupLabel));
        console.log('repaymentMandate overrideLwc:', JSON.stringify(this.overrideLwc));
        
        this.physicalDocuments = this.buildEmptyPhysicalDocuments();
        this._tryLoadAgreementData();
    }

    _tryLoadAgreementData() {
        if (!this.recordId) {
            return;
        }
        if (this.fromAssetList && !this._applicationLineItemId) {
            return;
        }
        this.loadData();
    }

    _documentScopeParams() {
        return {
            applicationLineItemId: this._applicationLineItemId || null
        };
    }

    buildEmptyPhysicalDocuments() {
        return PHYSICAL_DOCUMENT_SLOTS.map((slot) => ({
            ...slot,
            uploaded: false,
            fileName: '',
            contentDocumentId: '',
            documentChecklistId: ''
        }));
    }

    // ── Data loading ──────────────────────────────────────────────────────

    loadData() {
        if (!this.recordId) {
            return;
        }

        this.isPageLoading = true;
        Promise.resolve()
            .then(() => this.resolveAgreementType())
            .then(() => this.loadGeographicalState())
            .then(() => this.loadAgreementDetails())
            .catch((error) => {
                this.showError('Error loading agreement', error);
            })
            .finally(() => {
                this.isPageLoading = false;
            });
    }

    async resolveAgreementType() {
        this.isPhysicalAgreementMode = await isPhysicalAgreement({
            applicationId: this.recordId
        });
    }

    async loadGeographicalState() {
        const response = await getGeographicalState({ applicationId: this.recordId });
        if (!response) {
            this.showWarning('No geographical state code found');
            return;
        }
        if (response.includes(NO_GEO_STATE)) {
            this.showWarning('No geographical state code found');
            return;
        }
        const parts = response.split('_');
        this.agreementData.geographicalState = parts[0] || response;
        this.agreementData.geoStateCode = parts.length > 1 ? parts[1] : '';
    }

    async loadAgreementDetails() {
        const response = await getLoanAgreementDetails({
            applicationId: this.recordId,
            applicationLineItemId: this._applicationLineItemId || null
        });
        if (!response) {
            return;
        }

        this._serverReadOnly = response.isReadOnly === true;
        this.applyDocumentFilesFromResponse(response);

        this.agreementData.stampingCharges = response.stampingCharges ?? '';
        this.agreementData.agreementBookletNo = response.bookletNumber ?? '';
        this.agreementData.agreementCorrectlyCaptured = response.agreementCorrectlyCaptured || '';
        this.agreementData.remarks = response.remarks || '';
        this.vehicleId = response.vehicleId;
        this.borrowerId = response.borrowerId;
        this.coBorrowerId = response.coBorrowerId;
        this.loanAgreementId = response.loanAgreementId;
        this.dealId = response.dealId;
        this.isEStampApplicable = !!response.isEStampApplicable;
        this.initiationMethod = response.initiationMethod || '';
        this.initiatedEAgreement = !!response.initiatedEAgreement;
        this.isStampingChargesDisabled = this.isEStampApplicable || this.isPhysicalView;
        this.stampingLogs = response.stampingLogs || [];

        if (!this.isPhysicalView) {
            this.processStampingLogsFromWrapper();
            if (this.checkAgreementEligibility) {
                await this.switchToPhysicalAgreement();
                return;
            }
        }

        if (this.isPhysicalView) {
            if (response.bookletNumber) {
                this.showDocumentUploadSection = true;
                this.showFetchDetailBtn = true;
                this.showNextButton = true;
                await this.ensurePhysicalDocumentChecklistIds();
            } else {
                this.showDocumentUploadSection = false;
                this.showNextButton = false;
            }
            await this.applyCurrentStageEditableUi();
            return;
        }

        if (response.bookletNumber) {
            this.showFetchDetailBtn = true;
        } else {
            this.isBookletNumberDisabled = false;
        }

        if (this.loanAgreementId) {
            this.showInitiationMethod = true;
        }

        if (this.initiatedEAgreement) {
            this.checkStatus.processInitiated = true;
            this.hideInitiateAgreementBtn = true;
            this.showCheckStatusButton = true;
        }

        if (response.checkStatus) {
            this.checkStatus = {
                kfs: true,
                processInitiated: true,
                borrowerSigned: true,
                guarantorSigned: true,
                lenderSigned: false
            };
            this.showCheckStatusButton = false;
            this.disableDownloadAgreement = false;
        }

        if (response.downloadAgreement) {
            this.agreementDownloadCompleted = true;
            this.applyDownloadCompleteState();
        } else if (USE_DEMO_STUBS && !this.isPhysicalView && this.initiatedEAgreement) {
            this.applyDownloadCompleteState();
        } else if (!this.isPhysicalView && this.initiationMethod) {
            this.applyInitiationMethodUiState();
        }

        await this.applyCurrentStageEditableUi();

        if (
            !this.isPhysicalView &&
            !this.isEStampApplicable &&
            !this.initiatedEAgreement &&
            !this._serverReadOnly &&
            !this.isStampingAPISuccess
        ) {
            await this.runStampingDetailsStub();
        }
    }

    /**
     * On the current applicant stage (not past, not OPS), keep fields editable and
     * show upload/delete actions even when server data is already complete.
     */
    async applyCurrentStageEditableUi() {
        if (
            this.isStagePastView ||
            this.isAgreementOpsView ||
            this.isApplicationWithdrawn
        ) {
            return;
        }

        this.isBookletNumberDisabled = false;
        this.isButtonDisabled = false;

        if (this.hasFieldValue(this.agreementData.agreementBookletNo)) {
            this.showFetchDetailBtn = true;
        }

        if (this.isPhysicalView && this.agreementData.agreementBookletNo) {
            this.showDocumentUploadSection = true;
            this.showNextButton = this.allDocumentsUploaded;
            await this.ensurePhysicalDocumentChecklistIds();
            return;
        }

        if (!this.isPhysicalView && this.agreementDownloadCompleted) {
            this.showUploadButton = true;
            await this.ensureEsignDocumentChecklistId();
        }
    }

    applyDocumentFilesFromResponse(response) {
        const documentFiles = response.documentFiles || {};
        this.physicalDocuments = PHYSICAL_DOCUMENT_SLOTS.map((slot) => {
            const fileMeta = documentFiles[slot.key] || {};
            return {
                ...slot,
                uploaded: !!fileMeta.uploaded,
                fileName: fileMeta.fileName || '',
                contentDocumentId: fileMeta.contentDocumentId || '',
                documentChecklistId: fileMeta.documentChecklistId || ''
            };
        });
    }

    processStampingLogsFromWrapper() {
        if (!this.stampingLogs?.length) {
            return;
        }
        for (const log of this.stampingLogs) {
            if (!log?.Original_response__c) {
                continue;
            }
            try {
                const parsedJson = JSON.parse(log.Original_response__c);
                const responseObj = parsedJson?.response;
                if (
                    responseObj?.status !== 'SUCCESS' ||
                    !Array.isArray(responseObj?.content) ||
                    !responseObj.content.length
                ) {
                    continue;
                }
                const stampingList = responseObj.content[0]?.Dt_Stamping_Agree_Master;
                if (!Array.isArray(stampingList)) {
                    continue;
                }
                let totalStamping = 0;
                for (const row of stampingList) {
                    if (row.Document_Type === 'AGREEMENT') {
                        totalStamping += Number(row.StampDuty_Amount || 0);
                        this.isEStampApplicable = row.NESL_EStamp_Applicable_Flag === 'Y';
                        this.isStampingAPISuccess = true;
                        this.isStampingChargesDisabled = this.isEStampApplicable;
                        if (this.isNeslIneligible(row)) {
                            this.checkAgreementEligibility = true;
                            break;
                        }
                    }
                }
                if (totalStamping > 0) {
                    this.agreementData.stampingCharges = totalStamping;
                }
                break;
            } catch (error) {
                // Ignore malformed cache payloads.
            }
        }
    }

    isNeslIneligible(row) {
        return (
            row.NESL_ESigning_Applicable_Flag === 'N' ||
            row.NESL_ESigning_Applicable_Flag === '' ||
            row.NESL_EStamp_Applicable_Flag === '' ||
            row.NESL_EStamp_Applicable_Flag === 'N'
        );
    }

    async switchToPhysicalAgreement() {
        this.isPageLoading = true;
        try {
            await setAgreementType({
                applicationId: this.recordId,
                agreementType: AGREEMENT_TYPE_PHYSICAL
            });
            this.isPhysicalAgreementMode = true;
            this.checkAgreementEligibility = false;
            await this.loadAgreementDetails();
            this.showWarning(
                'Application is not eligible for e-agreement. Switched to physical agreement.'
            );
        } catch (error) {
            this.showError('Failed to switch agreement type', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    // ── Field handlers ────────────────────────────────────────────────────

    handleFieldChange(event) {
        const name = event.target.name;
        const value =
            event.detail?.value !== undefined ? event.detail.value : event.target.value;
        this.agreementData = { ...this.agreementData, [name]: value };
        this.isDataUpdated = true;
        if (name === 'agreementBookletNo') {
            this.showFetchDetailBtn = !!(value && String(value).trim());
        }
    }

    handleInitiationMethodChange(event) {
        this.initiationMethod = event.detail.value;
        this.isDataUpdated = true;
        this.applyInitiationMethodUiState();
    }

    applyInitiationMethodUiState() {
        if (this.isPhysicalView || !this.initiationMethod) {
            return;
        }

        const isCustomerJourney = this.initiationMethod === INITIATION_CUSTOMER_JOURNEY;
        this.hideInitiateAgreementBtn = isCustomerJourney;

        if (!this.agreementDownloadCompleted) {
            this.disableDownloadAgreement = !isCustomerJourney;
        }
    }

    // ── Stamping / booklet fetch ──────────────────────────────────────────

    async handleFetchAgreementDetails() {
        const bookletNo = this.agreementData.agreementBookletNo;
        if (!bookletNo || Number(bookletNo) <= 0) {
            this.showWarning('Please enter a valid Agreement Booklet Number');
            return;
        }

        this.isButtonDisabled = true;
        this.isPageLoading = true;
        try {
            if (this.isPhysicalView) {
                await this.runStampingDetailsStub(bookletNo);
            } else {
                await this.runAgreementBookletStub(bookletNo);
            }
        } catch (error) {
            this.resetButtonState();
            this.showError('Failed to fetch agreement booklet details', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async runStampingDetailsStub(bookletNo) {
        const check = await checkApiExecutionStatus({
            applicationId: this.recordId,
            vehicleId: this.vehicleId,
            serviceName: STAMPING_SERVICE
        });

        if (check?.shouldSkip && check.cachedResponse) {
            await this.processStampingResponse(check.cachedResponse, bookletNo, true);
        } else {
            const stubResponse = JSON.stringify({
                response: {
                    status: 'SUCCESS',
                    content: [{
                        Dt_Stamping_Agree_Master: [{
                            Document_Type: 'AGREEMENT',
                            StampDuty_Amount: '200',
                            NESL_EStamp_Applicable_Flag: 'Y',
                            NESL_ESigning_Applicable_Flag: 'Y'
                        }]
                    }]
                }
            });
            await this.processStampingResponse(stubResponse, bookletNo, false);
        }
    }

    async processStampingResponse(responseData, agreementBookletNo, isCached) {
        const parsed = JSON.parse(responseData);
        const response = parsed.response || parsed;
        const masters = response?.content?.[0]?.Dt_Stamping_Agree_Master || [];
        if (!masters.length) {
            this.showError('Stamping Details fetch failed', 'Stamping Details fetch failed');
            this.resetButtonState();
            return;
        }

        let total = 0;
        for (const row of masters) {
            if (row.Document_Type === 'AGREEMENT') {
                total += parseFloat(row.StampDuty_Amount || 0);
                if (!this.isPhysicalView) {
                    this.isEStampApplicable = row.NESL_EStamp_Applicable_Flag === 'Y';
                    this.isStampingChargesDisabled = this.isEStampApplicable;
                    this.isStampingAPISuccess = true;
                    if (this.isNeslIneligible(row)) {
                        this.checkAgreementEligibility = true;
                    }
                }
            }
        }
        this.agreementData.stampingCharges = total || 200;
        this.showSuccess(
            isCached ? 'Stamping Details fetched successfully (cached)' : 'Stamping Details fetched successfully'
        );

        if (this.checkAgreementEligibility && !this.isPhysicalView) {
            await this.switchToPhysicalAgreement();
            return;
        }

        if (agreementBookletNo) {
            await this.runAgreementBookletStub(agreementBookletNo);
        }
    }

    async runAgreementBookletStub(agreementBookletNo) {
        const stubResult = JSON.stringify({
            response: {
                status: 'SUCCESS',
                content: [{ Stamp_Towards: 'AGREEMENT', Stamp_Value: '200' }]
            }
        });

        const agreementType = this.isPhysicalView ? AGREEMENT_TYPE_PHYSICAL : AGREEMENT_TYPE_E;
        const saved = await fetchAgreementBookletDetails({
            responseStr: stubResult,
            loanAgreementId: this.loanAgreementId,
            applicationId: this.recordId,
            applicationLineItemId: this._applicationLineItemId || null,
            bookletNumber: agreementBookletNo,
            dealId: this.dealId,
            stampingCharges: this.agreementData.stampingCharges,
            isEStampApplicable: this.isEStampApplicable,
            geoStateCode: this.agreementData.geoStateCode || this.agreementData.geographicalState,
            agreementType
        });

        if (!saved?.success) {
            throw new Error('Failed to save agreement booklet details');
        }

        this.showSuccess('Agreement Booklet fetched successfully');

        if (this.isPhysicalView) {
            this.showDocumentUploadSection = true;
            this.showNextButton = true;
            await this.ensurePhysicalDocumentChecklistIds();
            await this.refreshPhysicalDocumentsFromServer();
        } else {
            this.showInitiationMethod = true;
            this.disableDownloadAgreement = true;
        }

        if (saved?.Id) {
            this.loanAgreementId = saved.Id;
        }

        this.applyBookletFetchSuccessState();
        this.isDataUpdated = true;
    }

    /** Locks booklet number and fetch button for the current session after a successful fetch. */
    applyBookletFetchSuccessState() {
        this.isBookletNumberDisabled = true;
        this.isButtonDisabled = true;
    }

    resetButtonState() {
        if (this.isBookletNumberDisabled) {
            return;
        }
        this.isButtonDisabled = false;
    }

    // ── E-agreement actions ─────────────────────────────────────────────────

    async handleInitiateAgreement() {
        if (!this.initiationMethod) {
            this.showWarning('Please select an initiation method');
            return;
        }
        this.isPageLoading = true;
        try {
            const stubResult = await this.stubInitiateNesl(this.initiationMethod);
            if (!stubResult?.success) {
                throw new Error('Agreement initiation failed');
            }

            this.initiatedEAgreement = true;
            this.checkStatus = {
                ...this.checkStatus,
                processInitiated: true,
                borrowerSigned:
                    this.initiationMethod === INITIATION_CUSTOMER_JOURNEY && USE_DEMO_STUBS
                        ? true
                        : this.checkStatus.borrowerSigned
            };
            this.hideInitiateAgreementBtn = this.initiationMethod === INITIATION_CUSTOMER_JOURNEY;
            this.showCheckStatusButton =
                this.initiationMethod !== INITIATION_CUSTOMER_JOURNEY || !USE_DEMO_STUBS;
            this.isBookletNumberDisabled = true;
            this.isButtonDisabled = true;

            const fields = {
                Id: this.loanAgreementId,
                Initiated_E_Agreement__c: true,
                Add_POA_SD_Initiation_method__c: this.initiationMethod
            };
            if (USE_DEMO_STUBS) {
                fields.Add_POA_SD_Agreement_signed__c = true;
            }
            await this.updateRecordDetails(fields);

            if (USE_DEMO_STUBS) {
                this.hideInitiateAgreementBtn = true;
                this.applyDownloadCompleteState();
                this.showSuccess('Agreement initiation completed successfully');
            } else if (this.initiationMethod === INITIATION_CUSTOMER_JOURNEY) {
                this.showSuccess('E-agreement initiation started. SMS would be sent in production.');
            } else {
                this.showSuccess('Agreement initiation started');
            }
            this.isDataUpdated = true;
        } catch (error) {
            if (!USE_DEMO_STUBS) {
                this.initiationMethod = '';
            }
            this.showError('Failed to initiate agreement', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async handleCheckStatus() {
        this.isPageLoading = true;
        try {
            const stubResult = await this.stubNeslStatus();
            if (stubResult?.pendingRelationship === 'DEBTOR') {
                this.checkStatus = { ...this.checkStatus, borrowerSigned: false };
                this.showWarning('Borrower sign pending');
                if (stubResult.esignLink) {
                    this.navigateToExternalUrl(stubResult.esignLink);
                }
                return;
            }
            if (stubResult?.pendingRelationship === 'CO-OBLIGANT') {
                this.checkStatus = {
                    ...this.checkStatus,
                    borrowerSigned: true,
                    guarantorSigned: false
                };
                this.showWarning('Co-borrower sign pending');
                if (stubResult.esignLink) {
                    this.navigateToExternalUrl(stubResult.esignLink);
                }
                return;
            }

            this.checkStatus = {
                ...this.checkStatus,
                borrowerSigned: true,
                guarantorSigned: this.coBorrowerId ? true : this.checkStatus.guarantorSigned
            };
            this.showCheckStatusButton = false;
            this.disableDownloadAgreement = false;
            await this.updateRecordDetails({ Id: this.loanAgreementId, Check_Status__c: true });
            this.showSuccess('Agreement signed successfully');
            this.isDataUpdated = true;
        } catch (error) {
            this.showError('Failed to check agreement status', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async handleDownloadAgreement() {
        if (!this.initiationMethod) {
            this.showWarning('Please select an initiation method');
            return;
        }

        this.isPageLoading = true;
        try {
            if (USE_DEMO_STUBS) {
                const initResult = await this.stubInitiateNesl(this.initiationMethod);
                if (!initResult?.success) {
                    throw new Error('Agreement initiation failed');
                }
                this.initiatedEAgreement = true;
                this.checkStatus = {
                    ...this.checkStatus,
                    processInitiated: true,
                    borrowerSigned: true,
                    guarantorSigned: this.coBorrowerId
                        ? true
                        : this.checkStatus.guarantorSigned
                };
            }

            const stubResult = await this.stubDownloadAgreement();
            if (!stubResult?.success) {
                throw new Error('Agreement download failed');
            }

            const fields = {
                Id: this.loanAgreementId,
                Add_POA_SD_Agreement_signed__c: true,
                Add_POA_SD_Initiation_method__c: this.initiationMethod,
                Initiated_E_Agreement__c: true
            };
            await this.updateRecordDetails(fields);
            this.agreementDownloadCompleted = true;
            this.applyDownloadCompleteState();
            this.showSuccess('Agreement downloaded successfully');
            this.isDataUpdated = true;
        } catch (error) {
            this.disableDownloadAgreement = false;
            this.showError('Failed to download agreement', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    applyDownloadCompleteState() {
        this.agreementDownloadCompleted = true;
        this.disableDownloadAgreement = true;
        this.checkStatus = {
            ...this.checkStatus,
            processInitiated: true,
            borrowerSigned: true,
            guarantorSigned: this.coBorrowerId ? true : this.checkStatus.guarantorSigned,
            lenderSigned: true
        };
        this.showCheckStatusButton = false;
        this.showUploadButton = false;
        this.showNextButton = true;
    }

    navigateToExternalUrl(url) {
        if (!url) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url }
        });
    }

    // ── Document upload ─────────────────────────────────────────────────────

    async ensurePhysicalDocumentChecklistIds() {
        if (!this.borrowerId || !this.recordId) {
            return;
        }

        const updated = [];
        for (const doc of this.physicalDocuments) {
            let checklistId = doc.documentChecklistId;
            if (!checklistId) {
                checklistId = await initOrGetDocumentWithApplicantId({
                    applicationId: this.recordId,
                    documentType: doc.docType,
                    applicantId: this.borrowerId,
                    ...this._documentScopeParams()
                });
            }
            updated.push({ ...doc, documentChecklistId: checklistId || doc.documentChecklistId });
        }
        this.physicalDocuments = updated;
    }

    async ensureEsignDocumentChecklistId() {
        if (!this.borrowerId || !this.recordId) {
            return;
        }
        if (this.esignAgreement.documentChecklistId) {
            return;
        }
        const checklistId = await initOrGetDocumentWithApplicantId({
            applicationId: this.recordId,
            documentType: ESIGN_DOC_TYPE,
            applicantId: this.borrowerId,
            ...this._documentScopeParams()
        });
        this.esignAgreement = {
            ...this.esignAgreement,
            documentChecklistId: checklistId || ''
        };
    }

    async handlePhysicalUploadFinished(event) {
        if (this.isDocumentsDisabled || !this.isFieldEditable) {
            return;
        }

        const slotKey = event.currentTarget.dataset.key;
        const uploadedFiles = event.detail?.files || [];
        if (!slotKey || !uploadedFiles.length) {
            return;
        }

        const doc = this.physicalDocuments.find((d) => d.key === slotKey);
        if (!doc) {
            return;
        }

        const file = uploadedFiles[0];
        const contentDocumentId = file.documentId || '';

        this.isPageLoading = true;
        try {
            if (!this.borrowerId) {
                this.showError('Upload Failed', 'Borrower is required before uploading documents');
                return;
            }

            let checklistId = doc.documentChecklistId;
            if (!checklistId) {
                checklistId = await initOrGetDocumentWithApplicantId({
                    applicationId: this.recordId,
                    documentType: doc.docType,
                    applicantId: this.borrowerId,
                    ...this._documentScopeParams()
                });
            }

            await linkContentDocument({
                documentDataJson: JSON.stringify({
                    documentType: doc.docType,
                    applicationId: this.recordId,
                    applicantId: this.borrowerId,
                    contentDocumentId,
                    ...this._documentScopeParams()
                })
            });

            const uploadedFileType = await getFileType({ contentDocumentId });
            this.physicalDocuments = this.physicalDocuments.map((d) => {
                if (d.key !== slotKey) {
                    return d;
                }
                return {
                    ...d,
                    uploaded: true,
                    fileName: file.name || '',
                    contentDocumentId,
                    documentChecklistId: checklistId,
                    fileType: uploadedFileType
                };
            });
            this.isDataUpdated = true;
            this.showSuccess('File uploaded successfully');
        } catch (error) {
            this.showError('Upload Failed', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async handlePhysicalDelete(event) {
        const slotKey = event.currentTarget.dataset.key;
        const doc = this.physicalDocuments.find((d) => d.key === slotKey);
        if (
            this.isDocumentsDisabled ||
            !this.isFieldEditable ||
            !doc?.contentDocumentId
        ) {
            return;
        }

        this.isPageLoading = true;
        try {
            await deleteContentDocument({ contentDocumentId: doc.contentDocumentId });
            this.physicalDocuments = this.physicalDocuments.map((d) => {
                if (d.key !== slotKey) {
                    return d;
                }
                return {
                    ...d,
                    uploaded: false,
                    fileName: '',
                    contentDocumentId: ''
                };
            });
            this.isDataUpdated = true;
            this.showSuccess('Document removed');
        } catch (error) {
            this.showError('Failed to remove document', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    handlePhysicalPreview(event) {
        const slotKey = event.currentTarget.dataset.key;
        const doc = this.physicalDocuments.find((d) => d.key === slotKey);
        if (!doc?.contentDocumentId) {
            this.showWarning('No file to preview.');
            return;
        }
        this.previewFileType = doc.fileType || 'PDF';
        this.previewContentDocumentId = doc.contentDocumentId;
        this.openPreviewModal = true;
    }

    async handleEsignUploadFinished(event) {
        if (this.isDocumentsDisabled || !this.isFieldEditable) {
            return;
        }

        const uploadedFiles = event.detail?.files || [];
        if (!uploadedFiles.length) {
            return;
        }

        const file = uploadedFiles[0];
        const contentDocumentId = file.documentId || '';

        this.isPageLoading = true;
        try {
            await this.ensureEsignDocumentChecklistId();
            await linkContentDocument({
                documentDataJson: JSON.stringify({
                    documentType: ESIGN_DOC_TYPE,
                    applicationId: this.recordId,
                    applicantId: this.borrowerId,
                    contentDocumentId,
                    ...this._documentScopeParams()
                })
            });

            const uploadedFileType = await getFileType({ contentDocumentId });
            this.esignAgreement = {
                ...this.esignAgreement,
                uploaded: true,
                fileName: file.name || '',
                contentDocumentId,
                fileType: uploadedFileType
            };
            this.showNextButton = true;
            this.isDataUpdated = true;
            this.showSuccess('E-sign agreement uploaded successfully');
        } catch (error) {
            this.showError('Upload Failed', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async handleEsignDelete() {
        if (
            this.isDocumentsDisabled ||
            !this.isFieldEditable ||
            !this.esignAgreement.contentDocumentId
        ) {
            return;
        }

        this.isPageLoading = true;
        try {
            await deleteContentDocument({
                contentDocumentId: this.esignAgreement.contentDocumentId
            });
            this.esignAgreement = {
                ...this.esignAgreement,
                uploaded: false,
                fileName: '',
                contentDocumentId: ''
            };
            this.isDataUpdated = true;
            this.showSuccess('Document removed');
        } catch (error) {
            this.showError('Failed to remove document', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    handleEsignPreview() {
        if (!this.esignAgreement.contentDocumentId) {
            this.showWarning('No file to preview.');
            return;
        }
        this.previewFileType = this.esignAgreement.fileType || 'PDF';
        this.previewContentDocumentId = this.esignAgreement.contentDocumentId;
        this.openPreviewModal = true;
    }

    handleFilePreviewClose() {
        this.openPreviewModal = false;
        this.previewContentDocumentId = null;
    }

    async refreshPhysicalDocumentsFromServer() {
        try {
            const response = await getLoanAgreementDetails({
                applicationId: this.recordId,
                applicationLineItemId: this._applicationLineItemId || null
            });
            this.applyDocumentFilesFromResponse(response);
        } catch (error) {
            // Keep local upload flags if server refresh fails.
        }
    }

    // ── Next / save ─────────────────────────────────────────────────────────

    async handleNext() {
        if (this.isApplicationWithdrawn) {
            return;
        }

        if (this.isStagePastView) {
            if (this.fromAssetList) {
                await this.returnToAssetList(false);
            }
            return;
        }

        if (this.isAgreementOpsView) {
            if (this.isReadOnlyScreen) {
                await this._completeAgreementNavigation();
                return;
            }

            if (!this.validateFields()) {
                return;
            }

            this.isPageLoading = true;
            try {
                await this.updateRecordDetails({
                    Id: this.loanAgreementId,
                    [FIELD_AGREEMENT_CORRECTLY_CAPTURED]:
                        this.agreementData.agreementCorrectlyCaptured,
                    [FIELD_REMARKS]: this.agreementData.remarks
                });
                this.showSuccess('Agreement remarks saved successfully');
                this.isDataUpdated = false;
                await this._completeAgreementNavigation();
            } catch (error) {
                this.showError('Error saving agreement remarks', error);
            } finally {
                this.isPageLoading = false;
            }
            return;
        }

        if (this.isReadOnlyScreen) {
            await this._completeAgreementNavigation();
            return;
        }

        if (!this.validateFields()) {
            return;
        }

        const needsPhysicalPersist = this.isPhysicalView && this.allDocumentsUploaded;
        if (!needsPhysicalPersist && !this.isDataUpdated) {
            await this._completeAgreementNavigation();
            return;
        }

        this.isPageLoading = true;
        try {
            if (needsPhysicalPersist) {
                await setAgreementType({
                    applicationId: this.recordId,
                    agreementType: AGREEMENT_TYPE_PHYSICAL
                });

                const fields = { Agreement_Type__c: AGREEMENT_TYPE_PHYSICAL };
                if (this.loanAgreementId) {
                    fields.Id = this.loanAgreementId;
                }
                await this.updateRecordDetails(fields);
            }

            this.isDataUpdated = false;
            this._markSubmittedReadOnly();
            this.showSuccess('Agreement saved successfully');
            await this._completeAgreementNavigation();
        } catch (error) {
            this.showError('Error saving agreement', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async _completeAgreementNavigation() {
        if (this.fromAssetList) {
            await this._completeAssetListAgreement();
            return;
        }
        await this.markStepAndNavigate();
    }

    async _completeAssetListAgreement() {
        if (!this._applicationLineItemId) {
            this.showWarning('Application line item is missing. Please go back and reopen the asset.');
            return;
        }

        try {
            this.isPageLoading = true;
            const result = await markAgreementStageComplete({
                applicationLineItemId: this._applicationLineItemId,
                currentViewId: this.currentViewId || null
            });
            if (!result?.isSuccess) {
                this.showError(
                    'Error',
                    result?.message || 'Unable to complete agreement for this asset.'
                );
                return;
            }
            await this.returnToAssetList(true);
        } catch (error) {
            this.showError(
                'Error',
                error?.body?.message || error?.message || 'Unable to complete agreement for this asset.'
            );
        } finally {
            this.isPageLoading = false;
        }
    }

    returnToAssetList(saved) {
        this.dispatchEvent(
            new CustomEvent('detailcomplete', {
                detail: {
                    lineItemId: this._applicationLineItemId || null,
                    saved
                },
                bubbles: true,
                composed: true
            })
        );
    }

    async markStepAndNavigate() {
        const applicantId = this.applicantId || this.borrowerId;
        if (!applicantId) {
            this.showWarning('Applicant is required to continue.');
            return;
        }

        this.requestNextStage();
    }

    validateFields() {
        if (this.isAgreementOpsView && this.isAgreementRemarksEditable) {
            if (!this.hasFieldValue(this.agreementData.agreementCorrectlyCaptured)) {
                this.showWarning('Please select Agreement Correctly Captured');
                return false;
            }
            if (!this.hasFieldValue(this.agreementData.remarks)) {
                this.showWarning('Please enter Remarks');
                return false;
            }
            return true;
        }

        if (this.isPhysicalView) {
            if (!this.allDocumentsUploaded) {
                this.showWarning('Please upload all required documents before proceeding.');
                return false;
            }
            return true;
        }
        if (!this.showNextButton) {
            this.showWarning('Please complete agreement steps before proceeding.');
            return false;
        }
        return true;
    }

    _markSubmittedReadOnly() {
        this._isApplicantStageComplete = true;
    }

    async updateRecordDetails(fields) {
        const recordId = fields?.Id || this.loanAgreementId || null;
        const fieldValues = { ...fields };
        delete fieldValues.Id;

        if (recordId) {
            await updateRecord({ fields: { Id: recordId, ...fieldValues } });
        } else {
            const createFields = {
                Application__c: this.recordId,
                ...fieldValues
            };
            if (this._applicationLineItemId) {
                createFields.Application_Line_Items__c = this._applicationLineItemId;
            }
            const result = await createRecord({
                apiName: AGREEMENT_OBJECT,
                fields: createFields
            });
            this.loanAgreementId = result.id;
        }
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
                    applicantId: this.applicantId,
                    currentLoanStageComplete: this.tab || STAGE_AGREEMENT,
                    currentStagePhrase: this.stagePhrase || ''
                },
                bubbles: true,
                composed: true
            })
        );
    }

    // ── UI state getters ────────────────────────────────────────────────────

    get isPhysicalView() {
        return this.isPhysicalAgreementMode;
    }

    get isEAgreementView() {
        return !this.isPhysicalAgreementMode;
    }

    get isStagePastView() {
        return this.isStagePast === true || this.isStagePast === 'true';
    }

    get isApplicationWithdrawn() {
        return this.applicationStatus?.isWithdrawn === true;
    }

    get isAgreementOpsView() {
        return this.currentViewId === AGREEMENT_OPS_VIEW_ID;
    }

    get isAgreementRemarksEditable() {
        return this.isAgreementOpsView && !this.isReadOnlyScreen;
    }

    get isReadOnlyScreen() {
        return (
            this.isStagePastView ||
            this._isApplicantStageComplete ||
            this.isApplicationWithdrawn
        );
    }

    /** Hides document upload and delete in OPS view or read-only stage. Preview remains visible. */
    get isDocumentsDisabled() {
        return this.isAgreementOpsView || this.isReadOnlyScreen;
    }

    get isFieldEditable() {
        return !this.isReadOnlyScreen && !this.isAgreementOpsView;
    }

    get isBookletNumberEditable() {
        return this.isFieldEditable && !this.isBookletNumberDisabled;
    }

    get isFetchButtonDisabled() {
        return this.isReadOnlyScreen || this.isButtonDisabled;
    }

    get isInitiationMethodDisabled() {
        return this.isReadOnlyScreen || this.agreementDownloadCompleted;
    }

    get isInitiateAgreementButtonDisabled() {
        return (
            this.isReadOnlyScreen ||
            !this.initiationMethod ||
            (this.initiatedEAgreement && this.agreementDownloadCompleted)
        );
    }

    get isDownloadAgreementDisabled() {
        return this.isReadOnlyScreen || this.disableDownloadAgreement;
    }

    get showGuarantor() {
        return !!this.coBorrowerId;
    }

    get showUploadButtonField() {
        if (!this.isFieldEditable) {
            return false;
        }
        return (
            this.showUploadButton ||
            (this.agreementDownloadCompleted && !this.isStagePastView && !this.isAgreementOpsView)
        );
    }

    get allDocumentsUploaded() {
        return this.physicalDocuments.every((doc) => doc.uploaded);
    }

    get showDocumentActions() {
        return !this.isDocumentsDisabled;
    }

    get isOpsRemarksComplete() {
        return (
            this.hasFieldValue(this.agreementData.agreementCorrectlyCaptured) &&
            this.hasFieldValue(this.agreementData.remarks)
        );
    }

    /** True when Next should be disabled (loading, withdrawn, past stage, or stage rules). */
    get isNextDisabled() {
        if (this.isPageLoading || this.isApplicationWithdrawn || this.isStagePastView) {
            return true;
        }
        if (this.isAgreementOpsView && this.isReadOnlyScreen) {
            return false;
        }
        if (this.isAgreementRemarksEditable) {
            return !this.isOpsRemarksComplete;
        }
        if (this._isApplicantStageComplete) {
            return false;
        }
        if (this.isPhysicalView) {
            return !this.allDocumentsUploaded;
        }
        return !this.showNextButton;
    }

    get initiationMethodOptions() {
        return INITIATION_METHOD_OPTIONS;
    }

    get stampingChargesDisplay() {
        return this.agreementData.stampingCharges ?? '—';
    }

    // ── Toast notifications ─────────────────────────────────────────────────

    hasFieldValue(value) {
        return value != null && String(value).trim() !== '';
    }

    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({ title: 'Success', message, variant: 'success' })
        );
    }

    showWarning(message) {
        this.dispatchEvent(
            new ShowToastEvent({ title: 'Warning', message, variant: 'warning' })
        );
    }

    showError(title, error) {
        let message = 'An unexpected error occurred';
        if (typeof error === 'string') {
            message = error;
        } else if (error?.body?.message) {
            message = error.body.message;
        } else if (error?.message) {
            message = error.message;
        }
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant: 'error', mode: 'sticky' })
        );
    }

    // ── Demo stubs ────────────────────────────────────────────────────────────

    async stubInitiateNesl() {
        return {
            success: true,
            status: 'SUCCESS',
            message: 'Initiation completed successfully'
        };
    }

    async stubNeslStatus() {
        if (USE_DEMO_STUBS) {
            return {
                success: true,
                statusCode: 'S002',
                pendingRelationship: null
            };
        }
        return { success: true, statusCode: 'S002' };
    }

    async stubDownloadAgreement() {
        return { success: true, iWorksId: 'STUB-IWORKS-001' };
    }
}