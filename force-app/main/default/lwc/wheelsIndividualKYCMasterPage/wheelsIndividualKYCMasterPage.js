import { LightningElement, api, track } from 'lwc';
import { invokeHandler }     from 'c/clientLayerHelper';
import getKYCInfoPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData       from '@salesforce/apex/GenericPageLayoutController.savePageData';
import SPECIAL_ICONS      from '@salesforce/resourceUrl/special_icons';
import getUserSessionId   from '@salesforce/apex/embedCustomFileUploadController.getUserSessionId';
import getCityStateFromPinCode from '@salesforce/apex/GenericUtility.getCityStateFromPinCode';
import individualTemplate    from './wheelsIndividualKYCMasterPage.html';
import nonIndividualTemplate from './wheelsNonIndividualKYCMasterPage.html';
import './wheelsNonIndividualKYCMasterPage.css';

const CUSTOMER_TYPE_NON_INDIVIDUAL = 'Non-Individual';

const EMPTY_ENTITY_ADDRESS = {
    addressProof: '',
    proofFile: null,
    kycAddressLine1: '',
    kycAddressLine2: '',
    state: '',
    district: '',
    city: '',
    kycPinCode: ''
};

// ── Apex routing ─────────────────────────────────────────────────────────────
const APEX_CLASS                    = 'KYCDetailsController';
const APEX_METHOD_GET               = 'getKYCInfoPageData';
const APEX_METHOD_SAVE              = 'saveKYCInfoPageData';
const APEX_METHOD_CREATE_CURRENT    = 'createCurrentAddressChecklist';
const APEX_METHOD_CREATE_PERMANENT  = 'createPermanentAddressChecklist';
const APEX_METHOD_CREATE_OFFICE     = 'createOfficeAddressChecklist';
const APEX_METHOD_SAVE_NON_INDIVIDUAL_KYC_DOC = 'saveNonIndividualKycDoc';
const APEX_METHOD_DELETE_FILE       = 'deleteCurrentAddressKycFile';
const APEX_METHOD_GET_INTEGRATION_MASTER = 'getIntegrationMaster';
const APEX_METHOD_GET_ENTITY_DOCUMENT_MASTER = 'getEntityDocumentMasterConfig';
const APEX_METHOD_RESOLVE_CONTENT_DOCUMENT_ID = 'resolveContentDocumentId';
const APEX_METHOD_STAMP_ENTITY_ADDRESS_CHECKLIST = 'stampEntityAddressChecklist';

const ENTITY_DV_FALLBACK_MAX_FILES = 1;
const ENTITY_DV_FALLBACK_FILE_TYPES = 'pdf,jpg,jpeg,png';
const ENTITY_PINCODE_REGEX = /^\d{6}$/;

const ENTITY_DV_SECTIONS = Object.freeze({
    cin: {
        documentCategory: 'KYC - Entity CIN',
        documentName: 'CIN',
        documentType: 'CIN',
        integration: 'PAN TO CIN'
    },
    gst: {
        documentCategory: 'KYC - Entity GST',
        documentName: 'GST',
        documentType: 'GST',
        integration: 'PAN TO GSTN'
    },
    additional: {
        documentCategory: 'KYC - Entity Additional Document',
        integration: null
    },
    darpan: {
        documentCategory: 'Government - DARPAN / NGO',
        integration: null
    },
    registered: {
        documentCategory: 'KYC - Entity Registered Address',
        integration: null
    },
    office: {
        documentCategory: 'KYC - Entity Office Address',
        integration: null
    }
});

/** CIN / GST document checklist + KYC config for Non-Individual KYC. */
const NON_INDIVIDUAL_KYC_DOC = Object.freeze({
    CIN: {
        docType: 'CIN',
        checklistIdKey: '_cinChecklistRecordId'
    },
    GST: {
        docType: 'GST',
        checklistIdKey: '_gstChecklistRecordId'
    }
});

const INCOME_CATEGORY_NON_EARNING   = 'Non-Earning';
const DARPAN_DOC_TYPE_CERTIFICATE = 'DARPAN Certificate';
const DARPAN_DOC_TYPE_CUSTOMER_DECLARATION = 'DARPAN Id - Customer Declaration';
const DARPAN_DOC_TYPE_DEFERRAL_APPROVAL = 'DARPAN Id - Deferral Approval';
const DARPAN_DOC_TYPE_ACK_COPY = 'DARPAN Id - Acknowledgement Copy';
const DARPAN_DOC_TYPES = new Set([
    DARPAN_DOC_TYPE_CERTIFICATE,
    DARPAN_DOC_TYPE_CUSTOMER_DECLARATION,
    DARPAN_DOC_TYPE_DEFERRAL_APPROVAL,
    DARPAN_DOC_TYPE_ACK_COPY
]);
const DARPAN_ENTITY_CODES = new Set(['50', '60', '70']);
const DARPAN_NPO_STATUS_NPO = 'NPO';
const DARPAN_NPO_STATUS_NOT_NPO = 'Not an NPO';
const DARPAN_DEFERRAL_YES = 'Yes';
const DARPAN_DEFERRAL_NO = 'No';

// Aadhaar verification dispatcher
const APEX_AADHAAR_CLASS                = 'AadhaarVerificationController';
const APEX_AADHAAR_INIT_EKYC_OTP        = 'initiateEkycOtpVerification';
const APEX_AADHAAR_INIT_BIOMETRIC       = 'initiateBiometricVerification';
const APEX_AADHAAR_INIT_VIDEO_KYC       = 'initiateVideoKYCVerification';
const APEX_AADHAAR_INIT_DIGILOCKER      = 'initiateDigilockerVerification';
const APEX_AADHAAR_INIT_OFFLINE_XML     = 'initiateOfflineXMLVerification';
const APEX_AADHAAR_POLL_CONSENT         = 'pollAadhaarConsent';

// Maps tile-id → dispatcher action
const AADHAAR_METHOD_TO_ACTION = {
    eKYC_OTP  : APEX_AADHAAR_INIT_EKYC_OTP,
    Biometric : APEX_AADHAAR_INIT_BIOMETRIC,
    VideoKYC  : APEX_AADHAAR_INIT_VIDEO_KYC,
    Digilocker: APEX_AADHAAR_INIT_DIGILOCKER,
    OfflineXML: APEX_AADHAAR_INIT_OFFLINE_XML
};

// eKYC OTP polling — 5 s interval × 60 ticks = 5 minute max wait.
const EKYC_POLL_INTERVAL_MS = 5000;
const EKYC_POLL_MAX_ATTEMPTS = 60;
const APEX_EXTRACT_CLASS          = 'KYCAddressExtractionController';
const APEX_EXTRACT_METHOD         = 'extractAndSaveAddressDocumentKyc';
const INTEGRATION_NAME_PAN_TO_CIN = 'PAN TO CIN';
const INTEGRATION_NAME_PAN_TO_GSTN = 'PAN TO GSTN';
const INTEGRATION_NAME_FACE_LIVELINES = 'Face Livelines';
const INTEGRATION_NAME_FACE_MATCH = 'Face Match';
const APEX_LOCATION_CLASS         = 'LocationMasterController';
const APEX_LOCATION_OPTIONS       = 'getLocationOptions';
const STAGE_KYC                   = 'KYC Details';
const LOS_MENU_SELECT_EVENT       = 'losmenuselect';
const LOS_NEXT_STAGE_EVENT        = 'losnextstage';
const INTEGRATION_PROGRESS_EVENT  = 'integrationprogressupdate';
const HANDLER_KYC_NEXT_INTEGRATION = 'kycNextIntegration';
const ADDR_TYPE_CURRENT           = 'Current Residential Address';
const ADDR_TYPE_PERMANENT         = 'Permanent Residential Address';

// ── Static option lists ───────────────────────────────────────────────────────
// 'Others' is a non-document verification path (no file upload, no OCR);
// it surfaces a Verification Method dropdown (Video KYC / Digi Locker).
const ADDR_DOCUMENT_TYPE_OPTIONS = [
    { label: 'Aadhaar Card',    value: 'Aadhaar Card'    },
    { label: 'Passport',        value: 'Passport'        },
    { label: 'Voter ID',        value: 'Voter ID'        },
    { label: 'Driving License', value: 'Driving License' },
    { label: 'Others',          value: 'Others'          },
];

const ENTITY_ADDRESS_PROOF_ELECTRICITY = 'Electricity Bill (within 2 months)';

const ENTITY_DOC_PICKLIST_EXCLUDED = new Set([
    'PAN',
    'CIN Certificate',
    'GST Certificate',
    'CIN',
    'GST'
]);

const ENTITY_ADDRESS_PROOF_GST = 'GST';

// Doc types that surface verification (no file upload) — Aadhaar visual picker
// or Others dropdown. Used to gate side-mode picker + file-upload blocks.
const VERIFICATION_ONLY_DOC_TYPES = new Set(['Aadhaar Card', 'Others']);

// Doc types that trigger Einstein OCR extraction; Aadhaar is handled separately
const OCR_SUPPORTED_DOC_TYPES = new Set(['Passport', 'Voter ID', 'Driving License']);

const SIDE_MODE_FULL = 'Full';
const SIDE_MODE_SIDE = 'Side';

const CKYC_DIGIT_LIMIT = 14;
const CUSTOMER_IMAGE_DOC_TYPE = 'Customer Image';
const CUSTOMER_IMAGE_POST_UPLOAD_INTEGRATIONS = Object.freeze([
    {
        label: 'Face Liveliness',
        integrationNames: [INTEGRATION_NAME_FACE_LIVELINES]
    },
    {
        label: 'Face Match',
        integrationNames: [INTEGRATION_NAME_FACE_MATCH]
    }
]);

const OCR_STAGES = [
    'OCR TEXT MATCH',
    'KYC VALIDATION API',
    'SAVING EXTRACTED DETAILS'
];

// Aadhaar verification methods — visual-picker tiles (Aadhaar Card path only).

const AADHAAR_VERIFICATION_METHODS = [
    { id: 'eKYC_OTP',   label: 'eKYC OTP Verification', icon: 'utility:phone_portrait', description: 'OTP link sent to the customer\u2019s mobile' },
    { id: 'Biometric',  label: 'Biometric Verification', icon: 'utility:identity',      description: 'UIDAI fingerprint device capture' },
    { id: 'OfflineXML', label: 'Offline Aadhaar XML',    icon: 'utility:file',          description: 'Upload signed UIDAI offline XML' },
    { id: 'Digilocker', label: 'DigiLocker',             icon: 'utility:lock',          description: 'Pull eKYC from DigiLocker vault' }
];

// Verification methods surfaced when Address Document Type = 'Others'.
// Backed by the same AADHAAR_METHOD_TO_ACTION dispatcher and _isAadhaarVerified
// state, so the existing verify pipeline is reused without duplication.
const OTHER_VERIFICATION_METHOD_OPTIONS = [
    { label: 'Video KYC',  value: 'VideoKYC'   },
    { label: 'Digi Locker', value: 'Digilocker' }
];

// Stub Aadhaar eKYC OTP generation and OTP send callouts.
const AADHAAR_STUB_STAGES = [
    'UIDAI Verification API',
    'UIDAI Fetch Aadhaar API'
];

export default class WheelsIndividualKYCMasterPage extends LightningElement {
    /** Replay when lwc:component mounts after losmenuselect (vehicleDetails pattern). */
    static _lastMenuDetail = null;

    render() {
        return this.isNonIndividualApplicant ? nonIndividualTemplate : individualTemplate;
    }

    // ── @api props ────────────────────────────────────────────────────────────
    _recordId;
    _menuNavApplicantId = '';
    _menuNavContext = { currentViewId: '', stagePhrase: '', tab: '', applicantId: '' };
    _menuSelectHandler;
    _pageLoadScheduled = false;

    @api get recordId()     { return this._recordId; }
    set recordId(v)         {
        this._recordId = v;
        this._schedulePageDataLoad();
    }

    _applicantId;
    @api get applicantId()  { return this._applicantId; }
    set applicantId(v) {
        const next = v || null;
        if (next === this._applicantId) return;
        this._applicantId = next;
        this._customerType = '';
        this._entityTypeCode = '';
        this._darpanNpoStatus = '';
        this._darpanDeferralApproval = DARPAN_DEFERRAL_NO;
        this._darpanId = '';
        this._darpanRegistrationDate = '';
        this._darpanDocumentType = '';
        this._darpanDocuments = [];
        this._darpanRequiredItems = [];
        this._darpanAdhocItems = [];
        this._darpanAdhocGroupSatisfied = false;
        this._darpanError = '';
        this.showDarpanMandatoryDocsModal = false;
        this._initialized = false;
        this.connectedCallback();
    }

    @api currentViewId;
    @api stagePhrase = '';
    @api tab         = '';

    _isStagePast = false;
    @api
    set isStagePast(value) { this._isStagePast = value === true || value === 'true'; }
    get isStagePast()      { return this._isStagePast; }

    @track _customerType = '';

    get isIndividualApplicant() {
        return this._customerType !== CUSTOMER_TYPE_NON_INDIVIDUAL;
    }
    get isNonIndividualApplicant() {
        return this._customerType === CUSTOMER_TYPE_NON_INDIVIDUAL;
    }

    // ════════════════════════════════════════════════════════════════════════════
    // Non-Individual — CIN / GST document upload
    // ════════════════════════════════════════════════════════════════════════════
    @track cinFieldValues = {};
    @track gstFieldValues = {};
    @track _cinChecklistRecordId = null;
    @track _gstChecklistRecordId = null;
    @track _cinApiState = 'idle';
    @track _gstApiState = 'idle';
    @track _cinNumberOptions = [];
    @track _gstNumberOptions = [];
    @track _entityLocOptions = {
        gst: { state: [], district: [], city: [] },
        registered: { state: [], district: [], city: [] },
        office: { state: [], district: [], city: [] }
    };

    _cinProcessedVersionIds = new Set();
    _gstProcessedVersionIds = new Set();
    _gstStateByNumber = {};

    @track registeredAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
    @track officeAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
    @track _gstIsRegisteredAddress = '';
    @track _officeSameAsRegistered = '';
    @track _entityTypeCode = '';
    @track _entityRegisteredChecklistId = null;
    @track _entityOfficeChecklistId = null;
    @track _entityAdditionalDocumentType = '';
    @track _entityAdditionalDocuments = [];
    @track _darpanNpoStatus = '';
    @track _darpanDeferralApproval = DARPAN_DEFERRAL_NO;
    @track _darpanId = '';
    @track _darpanRegistrationDate = '';
    @track _darpanDocumentType = '';
    @track _darpanDocuments = [];
    @track _darpanRequiredItems = [];
    @track _darpanAdhocItems = [];
    @track _darpanAdhocGroupSatisfied = false;
    @track _darpanError = '';
    @track showDarpanMandatoryDocsModal = false;
    @track _cinRequired = false;
    @track _gstRequired = false;
    @track _entityRequiredDocuments = [];
    @track _entityAdhocDocuments = [];
    @track _entityAdhocDocumentCount = 0;
    @track _entityUploadedDocumentTypes = [];
    @track _entityRequiredDocItems = [];
    @track _entityAdhocDocItems = [];
    @track _entityAdhocGroupSatisfied = false;
    @track _entityMandatoryDocsError = '';
    @track showEntityMandatoryDocsModal = false;
    @track showEntityMagicUpload = false;
    @track entityActiveUploadChecklistId = null;
    @track entityActiveMaxFiles = ENTITY_DV_FALLBACK_MAX_FILES;
    @track entityActiveAllowedTypes = ENTITY_DV_FALLBACK_FILE_TYPES;
    @track entityActiveUploadSectionKey = null;
    @track entityActiveUploadDocumentType = '';
    _entityOverlayMouseDownOnSelf = false;

    // ── CIN getters ──────────────────────────────────────────────────────────
    get showCinSection()           { return this._cinRequired; }
    get showGstSection() {
        if (!this._gstRequired) {
            return false;
        }
        // Gate GST behind a fully-completed CIN section (file + ready + CIN #).
        if (this._cinRequired && !this._isCinSectionComplete()) {
            return false;
        }
        return true;
    }
    get hasCinFile()               { return !!this._fileLabel(this.cinFieldValues.cinFile); }
    get cinPanelFiles()            { return this._entityDocPanelFilesView(this.cinFieldValues.cinFile, this._cinChecklistRecordId, 'cin', 'CIN'); }
    get cinUploadDisabled()        { return this.isReadOnlyScreen || this.hasCinFile; }
    get cinFieldsEditable() {
        return this.hasCinFile && !this.isReadOnlyScreen && this.cinDetailSectionReady;
    }
    get cinFieldReadOnly()         { return !this.cinFieldsEditable; }
    get cinDetailSectionReady()    { return this._cinApiState === 'success' || this._cinApiState === 'failure'; }
    get cinNumberIsPicklist()      { return this.cinFieldsEditable && this._cinNumberOptions.length > 1; }
    get cinNumber()                { return this.cinFieldValues.cinNumber || ''; }
    get cinNumberDisplay()         { return this._displayFieldValue(this.cinNumber); }
    get cinNumberOptions()         { return this._cinNumberOptions; }

    // ── GST getters ──────────────────────────────────────────────────────────
    get hasGstFile()               { return !!this._fileLabel(this.gstFieldValues.gstFile); }
    get gstPanelFiles()            { return this._entityDocPanelFilesView(this.gstFieldValues.gstFile, this._gstChecklistRecordId, 'gst', 'GST'); }
    get gstUploadDisabled()        { return this.isReadOnlyScreen || this.hasGstFile; }
    get gstFieldsEditable() {
        return this.hasGstFile && !this.isReadOnlyScreen && this.gstDetailSectionReady;
    }
    get gstFieldReadOnly()         { return !this.gstFieldsEditable; }
    get gstDetailSectionReady()    { return this._gstApiState === 'success' || this._gstApiState === 'failure'; }
    get gstNumberIsPicklist()      { return this.gstFieldsEditable && this._gstNumberOptions.length > 1; }
    get gstNumber()                { return this.gstFieldValues.gstNumber || ''; }
    get gstNumberDisplay()         { return this._displayFieldValue(this.gstNumber); }
    get gstNumberOptions()         { return this._gstNumberOptions; }
    get gstDistrictOptions()       { return this._entityLocOptions.gst.district; }
    get gstAddressLine1Display()   { return this._displayFieldValue(this.gstFieldValues.kycAddressLine1); }
    get gstAddressLine2Display()   { return this._displayFieldValue(this.gstFieldValues.kycAddressLine2); }
    get gstPinCodeDisplay()        { return this._displayFieldValue(this.gstFieldValues.kycPinCode); }
    get gstStateDisplay()          { return this._displayFieldValue(this.gstFieldValues.state); }
    get gstDistrictDisplay()       { return this._displayFieldValue(this.gstFieldValues.district); }
    get gstCityDisplay()           { return this._displayFieldValue(this.gstFieldValues.city); }

    get entityAddressProofOptions() {
        return this._buildEntityDocumentPicklistOptions('address');
    }
    get registeredAddressProofOptions() {
        return this._buildEntityAddressProofOptionsForScope('registered');
    }
    get officeAddressProofOptions() {
        return this._buildEntityAddressProofOptionsForScope('office');
    }
    get registeredAddressProofLocked() {
        return this.hasRegisteredProofFile && !this.isReadOnlyScreen && !this.isRegisteredAddressReadOnly;
    }
    get officeAddressProofLocked() {
        return this.hasOfficeProofFile && !this.isReadOnlyScreen && !this.isOfficeAddressReadOnly;
    }
    get entityAdditionalDocumentType() { return this._entityAdditionalDocumentType; }
    get entityAdditionalDocumentTypeOptions() {
        return this._buildEntityDocumentPicklistOptions('additional');
    }
    get isDarpanApplicableEntity() {
        const normalizedCode = this._normalizeEntityTypeCode(this._entityTypeCode);
        return this.isNonIndividualApplicant && DARPAN_ENTITY_CODES.has(normalizedCode);
    }
    get showDarpanSection() {
        if (!this.isDarpanApplicableEntity) {
            return false;
        }
        if (!this.isReadOnlyScreen) {
            return true;
        }
        return this._activeDarpanDocuments().some((entry) => entry?.proofFile)
            || String(this._darpanId || '').trim().length > 0
            || String(this._darpanRegistrationDate || '').trim().length > 0;
    }
    get darpanNpoYes() {
        return this._darpanNpoStatus === DARPAN_NPO_STATUS_NPO;
    }
    get darpanNotNpoYes() {
        return this._darpanNpoStatus === DARPAN_NPO_STATUS_NOT_NPO;
    }
    get darpanDeferralYes() {
        return this._darpanDeferralApproval === DARPAN_DEFERRAL_YES;
    }
    get darpanDeferralNo() {
        return this._darpanDeferralApproval !== DARPAN_DEFERRAL_YES;
    }
    get darpanNpoStatusDisplay() {
        if (this._darpanNpoStatus === DARPAN_NPO_STATUS_NPO) {
            return 'Yes';
        }
        if (this._darpanNpoStatus === DARPAN_NPO_STATUS_NOT_NPO) {
            return 'No';
        }
        return this._displayFieldValue('');
    }
    get darpanDeferralApprovalDisplay() {
        return this._displayFieldValue(this._darpanDeferralApproval);
    }
    get darpanIdValue() {
        return this._darpanId || '';
    }
    get darpanIdDisplay() {
        return this._displayFieldValue(this._darpanId);
    }
    get darpanRegistrationDateValue() {
        return this._darpanRegistrationDate || '';
    }
    get darpanRegistrationDateDisplay() {
        return this._displayDateTimeFieldValue(this._darpanRegistrationDate);
    }
    get darpanIdInputDisabled() {
        return this.isReadOnlyScreen || !this._canEditDarpanIdFields();
    }
    get darpanRegistrationDateDisabled() {
        return this.isReadOnlyScreen || !this._canEditDarpanIdFields();
    }
    get darpanStatusLockedByUploads() {
        return this._activeDarpanDocuments().some((entry) => entry?.proofFile);
    }
    get showEditableDarpanStatusFields() {
        return !this.isReadOnlyScreen && !this.darpanStatusLockedByUploads;
    }
    get darpanUploadCards() {
        const entries = this._activeDarpanDocuments();
        return this._getRequiredDarpanDocumentTypes().map((documentType, index) => {
            const entry = entries.find(
                (item) => String(item?.documentType || '').trim() === documentType
            ) || null;
            const files = entry?.proofFile
                ? [{
                    id: entry.checklistRecordId || documentType,
                    name: documentType,
                    fileName: this._fileLabel(entry.proofFile) || documentType,
                    checklistRecordId: entry.checklistRecordId || null,
                    contentVersionId: entry.proofFile?.contentVersionId || null,
                    contentDocumentId: entry.proofFile?.contentDocumentId || null,
                    extension: this._fileExtension(entry.proofFile)
                }]
                : [];
            return {
                id: `darpan-upload-${index}`,
                sectionKey: this._darpanSectionKeyForDocType(documentType),
                documentType,
                legendLabel: documentType,
                fileTitle: `Upload ${documentType}`,
                files,
                uploadDisabled: this.isReadOnlyScreen || files.length > 0,
                hideFileTitle: files.length > 0
            };
        });
    }
    get darpanUploadGridClass() {
        const base = 'darpan-upload-grid';
        return this.darpanUploadCards.length > 1
            ? `${base} darpan-upload-grid--two`
            : `${base} darpan-upload-grid--one`;
    }
    get darpanDocumentType() {
        return this._darpanDocumentType;
    }
    get darpanDocumentTypeOptions() {
        const uploadedTypes = new Set(
            this._activeDarpanDocuments()
                .map((entry) => String(entry?.documentType || '').trim())
                .filter(Boolean)
        );
        return this._getAllowedDarpanDocumentTypes()
            .filter((docType) => !uploadedTypes.has(docType))
            .map((docType) => ({ label: docType, value: docType }));
    }
    get darpanUploadDisabled() {
        if (this.isReadOnlyScreen) {
            return true;
        }
        const selectedType = String(this._darpanDocumentType || '').trim();
        if (!selectedType) {
            return true;
        }
        return this._activeDarpanDocuments().some(
            (entry) => String(entry?.documentType || '').trim() === selectedType
        );
    }
    get darpanHideUploadPanel() {
        if (this.isReadOnlyScreen) {
            return false;
        }
        return !String(this._darpanDocumentType || '').trim();
    }
    get darpanPanelFiles() {
        return this._darpanPanelFilesView();
    }
    get darpanLegendLabel() {
        return this._darpanDocumentType || 'Darpan Document';
    }
    get darpanFileTitle() {
        return this._darpanDocumentType
            ? `Upload ${this._darpanDocumentType}`
            : 'Upload Darpan document';
    }
    get darpanError() {
        return this._darpanError;
    }
    get showDarpanMandatoryDocsButton() {
        return this._getRequiredDarpanDocumentTypes().length > 0;
    }
    get darpanRequiredListItems() {
        const source = Array.isArray(this._darpanRequiredItems) && this._darpanRequiredItems.length
            ? this._darpanRequiredItems
            : this._buildLocalDarpanRequiredItems();
        return source
            .map((item, index) => {
                const name = String(item?.name || '').trim();
                if (!name) {
                    return null;
                }
                return {
                    id: `darpan-req-${index}`,
                    name,
                    isUploaded: item?.isUploaded === true
                };
            })
            .filter(Boolean);
    }
    get darpanAdhocItems() {
        return (this._darpanAdhocItems || [])
            .map((item, index) => {
                const name = String(item?.name || '').trim();
                if (!name) {
                    return null;
                }
                return {
                    id: `darpan-adhoc-${index}`,
                    name,
                    isUploaded: item?.isUploaded === true
                };
            })
            .filter(Boolean);
    }
    get showDarpanAdhocDocumentsRow() {
        return this.darpanAdhocItems.length > 0;
    }
    get darpanAdhocGroupSatisfied() {
        return this._darpanAdhocGroupSatisfied === true;
    }
    get entityMandatoryDocsError() { return this._entityMandatoryDocsError; }
    get showEntityMandatoryDocsButton() {
        return (this._entityRequiredDocuments || []).length > 0
            || (this._entityAdhocDocuments || []).length > 0;
    }
    get entityMandatoryDocListItems() {
        // Prefer the server's dictionary-resolved items (master key / checklist
        // type / alias aware). Fall back to a local name match only if the
        // server payload is unavailable.
        if (Array.isArray(this._entityRequiredDocItems) && this._entityRequiredDocItems.length) {
            return this._entityRequiredDocItems.map((item, index) => ({
                id: `mandatory-doc-${index}`,
                name: String(item.name || '').trim(),
                isUploaded: item.isUploaded === true
            }));
        }
        const uploaded = new Set(
            (this._entityUploadedDocumentTypes || [])
                .map((docName) => String(docName || '').trim().toLowerCase())
                .filter(Boolean)
        );
        return (this._entityRequiredDocuments || [])
            .map((docName, index) => {
                const name = String(docName || '').trim();
                if (!name) {
                    return null;
                }
                const normalizedName = name.toLowerCase();
                const isUploaded = uploaded.has(normalizedName)
                    || (normalizedName === 'cin certificate' && (uploaded.has('cin') || uploaded.has('cin certificate')))
                    || (normalizedName === 'gst certificate' && (uploaded.has('gst') || uploaded.has('gst certificate')));
                return {
                    id: `mandatory-doc-${index}`,
                    name,
                    isUploaded
                };
            })
            .filter(Boolean);
    }
    get showEntityAdhocDocumentsRow() {
        return (this._entityAdhocDocuments || []).length > 0;
    }
    get entityAdhocDocItems() {
        const source = Array.isArray(this._entityAdhocDocItems) && this._entityAdhocDocItems.length
            ? this._entityAdhocDocItems
            : (this._entityAdhocDocuments || []).map((name) => ({ name, isUploaded: false }));
        return source
            .map((item, index) => {
                const name = String(item.name || '').trim();
                if (!name) {
                    return null;
                }
                return {
                    id: `adhoc-doc-${index}`,
                    name,
                    isUploaded: item.isUploaded === true
                };
            })
            .filter(Boolean);
    }
    get entityAdhocGroupSatisfied() {
        return this._entityAdhocGroupSatisfied === true;
    }
    get entityAdhocDocumentsIntro() {
        const minCount = Number(this._entityAdhocDocumentCount) || 0;
        if (minCount > 0) {
            return `Upload at least ${minCount} proof document from:`;
        }
        return 'Upload registration/activity proof document from:';
    }
    get entityAdhocDocumentsList() {
        return (this._entityAdhocDocuments || [])
            .map((docName) => String(docName || '').trim())
            .filter(Boolean)
            .join(', ');
    }
    get entityAdditionalUploadDisabled() {
        if (this.isReadOnlyScreen) return true;
        const selectedType = String(this._entityAdditionalDocumentType || '').trim();
        if (!selectedType) return true;
        return (this._entityAdditionalDocuments || []).some(
            (entry) => entry.documentType === selectedType
        );
    }
    get entityAdditionalHideUploadPanel() {
        if (this.isReadOnlyScreen) {
            return false;
        }
        return !String(this._entityAdditionalDocumentType || '').trim();
    }
    get entityAdditionalPanelFiles() { return this._entityAdditionalPanelFilesView(); }
    get showEntityAdditionalSection() {
        if (this.isReadOnlyScreen) {
            return (this._entityAdditionalDocuments || []).some((entry) => entry.proofFile);
        }
        // Gate behind every mandatory section above it (CIN #, GST, addresses).
        // Reset-aware: if a mandatory value is cleared, this re-hides the section.
        return !this._isNonIndividualNextDisabled;
    }
    get entityAdditionalLegendLabel() {
        return this._entityAdditionalDocumentType || 'Additional Document';
    }
    get entityAdditionalFileTitle() {
        return this._entityAdditionalDocumentType
            ? `Upload ${this._entityAdditionalDocumentType}`
            : 'Upload additional document';
    }
    get chunkyUploadIconUrl() { return `${SPECIAL_ICONS}/special_icons/upload-file-icon.svg`; }

    get isRegisteredSectionDisabled() {
        return this.isReadOnlyScreen || this.isRegisteredAddressReadOnly;
    }

    /** GST-as-registered-address applies only when GST is mandatory or already uploaded. */
    get _entityGstRegisteredQuestionApplies() {
        return this._gstRequired || this.hasGstFile;
    }

    get gstRegisteredAddressDisplay() {
        return this._entityYesNoDisplay(this._gstIsRegisteredAddress);
    }
    get gstIsRegisteredAddressYes()        { return this._gstIsRegisteredAddress === 'Yes'; }
    get gstIsRegisteredAddressNo()         { return this._gstIsRegisteredAddress === 'No'; }
    get isRegisteredAddressReadOnly()      { return this._gstIsRegisteredAddress === 'Yes'; }

    get officeSameAsRegisteredYes()        { return this._officeSameAsRegistered === 'Yes'; }
    get officeSameAsRegisteredNo()         { return this._officeSameAsRegistered === 'No'; }
    get officeSameAsRegisteredDisplay() {
        return this._entityYesNoDisplay(this._officeSameAsRegistered);
    }
    get isOfficeAddressReadOnly()          { return this._officeSameAsRegistered === 'Yes'; }
    get isOfficeSectionDisabled()          { return this.isReadOnlyScreen || this.isOfficeAddressReadOnly; }

    get registeredDistrictOptions() { return this._entityLocOptions.registered.district; }
    get officeLocationOptions()     { return this._entityLocOptions.office; }

    get registeredShowAddressDetailFields() {
        return this._entityAddressShowDetailFields('registered');
    }
    get hasRegisteredProofFile() {
        return !!this._fileLabel(this.registeredAddressFieldValues.proofFile);
    }
    get registeredPanelUsesGstDocument() {
        if (this.isRegisteredAddressReadOnly) {
            return true;
        }
        const proof = String(this.registeredAddressFieldValues.addressProof || '').trim();
        return proof === ENTITY_ADDRESS_PROOF_GST;
    }
    get registeredHideUploadPanel() {
        if (this.isReadOnlyScreen || this.isRegisteredAddressReadOnly || this.registeredPanelUsesGstDocument) {
            return false;
        }
        return !String(this.registeredAddressFieldValues.addressProof || '').trim();
    }
    get registeredPanelFiles()       { return this._entityAddressPanelConfig('registered').files; }
    get registeredUploadDisabled()   { return this._entityAddressPanelConfig('registered').uploadDisabled; }
    get registeredPanelLegendLabel() { return this._entityAddressPanelConfig('registered').legendLabel; }
    get registeredPanelFileTitle()   { return this._entityAddressPanelConfig('registered').fileTitle; }
    get registeredPanelReadOnly()    { return this._entityAddressPanelConfig('registered').readOnly; }
    get registeredAddressFieldsEditable() {
        return this.registeredShowAddressDetailFields
            && !this.isReadOnlyScreen
            && !this.isRegisteredAddressReadOnly;
    }
    get registeredAddressFieldReadOnly() { return !this.registeredAddressFieldsEditable; }
    get registeredAddressLine1Display() {
        return this._entityAddressDisplay('registered', 'kycAddressLine1');
    }
    get registeredAddressLine2Display() {
        return this._entityAddressDisplay('registered', 'kycAddressLine2');
    }
    get registeredPinCodeDisplay() {
        return this._entityAddressDisplay('registered', 'kycPinCode');
    }
    get registeredStateDisplay() {
        return this._entityAddressDisplay('registered', 'state');
    }
    get registeredDistrictDisplay() {
        return this._entityAddressDisplay('registered', 'district');
    }
    get registeredCityDisplay() {
        return this._entityAddressDisplay('registered', 'city');
    }
    get registeredAddressProofDisplay() {
        return this._entityAddressDisplay('registered', 'addressProof');
    }

    get officeShowOwnProofSelector() { return this._officeSameAsRegistered !== 'Yes'; }
    get officeHideUploadPanel() {
        if (this.isReadOnlyScreen || this.isOfficeAddressReadOnly || !this.officeShowOwnProofSelector) {
            return false;
        }
        return !String(this.officeAddressFieldValues.addressProof || '').trim();
    }
    get officeShowAddressDetailFields() {
        return this._entityAddressShowDetailFields('office');
    }
    get hasOfficeProofFile() {
        return !!this._fileLabel(this.officeAddressFieldValues.proofFile);
    }
    get officePanelFiles()           { return this._entityAddressPanelConfig('office').files; }
    get officeUploadDisabled()       { return this._entityAddressPanelConfig('office').uploadDisabled; }
    get officePanelLegendLabel()     { return this._entityAddressPanelConfig('office').legendLabel; }
    get officePanelFileTitle()       { return this._entityAddressPanelConfig('office').fileTitle; }
    get officePanelReadOnly()        { return this._entityAddressPanelConfig('office').readOnly; }
    get officeAddressFieldsEditable() {
        return this.officeShowAddressDetailFields
            && !this.isReadOnlyScreen
            && !this.isOfficeAddressReadOnly;
    }
    get officeAddressFieldReadOnly() { return !this.officeAddressFieldsEditable; }
    get officeAddressLine1Display() {
        return this._entityAddressDisplay('office', 'kycAddressLine1');
    }
    get officeAddressLine2Display() {
        return this._entityAddressDisplay('office', 'kycAddressLine2');
    }
    get officePinCodeDisplay() {
        return this._entityAddressDisplay('office', 'kycPinCode');
    }
    get officeStateDisplay() {
        return this._entityAddressDisplay('office', 'state');
    }
    get officeDistrictDisplay() {
        return this._entityAddressDisplay('office', 'district');
    }
    get officeCityDisplay() {
        return this._entityAddressDisplay('office', 'city');
    }
    get officeAddressProofDisplay() {
        return this._entityAddressDisplay('office', 'addressProof');
    }

    _entityYesNoDisplay(value) {
        if (value === 'Yes') return 'Yes';
        if (value === 'No') return 'No';
        return this._displayFieldValue('');
    }

    _entityAddressDisplay(scope, field) {
        return this._displayFieldValue(this._getEntityAddressValues(scope)[field]);
    }

    _entityAddressPanelConfig(scope) {
        const isRegistered = scope === 'registered';
        const values = isRegistered
            ? this.registeredAddressFieldValues
            : this.officeAddressFieldValues;
        const fallbackLabel = isRegistered ? 'Registered Address Proof' : 'Office Address Proof';
        const proof = String(values.addressProof || '').trim();
        const usesGst = isRegistered
            ? this.registeredPanelUsesGstDocument
            : (this._officeSameAsRegistered === 'Yes' && this.registeredPanelUsesGstDocument);
        const checklistId = this._getEntityChecklistId(scope);

        let files;
        if (usesGst && this.hasGstFile) {
            files = this._entityDocPanelFilesView(
                this.gstFieldValues.gstFile,
                this._gstChecklistRecordId,
                isRegistered ? 'registered-gst' : 'office-gst',
                'GST'
            );
        } else if (!isRegistered && this._officeSameAsRegistered === 'Yes') {
            const regValues = this.registeredAddressFieldValues;
            files = this._entityDocPanelFilesView(
                regValues.proofFile,
                this._entityRegisteredChecklistId,
                'office-from-registered',
                regValues.addressProof || fallbackLabel
            );
        } else {
            files = this._entityDocPanelFilesView(
                values.proofFile,
                checklistId,
                scope,
                values.addressProof || fallbackLabel
            );
        }

        const sectionDisabled = isRegistered
            ? this.isRegisteredSectionDisabled
            : this.isOfficeSectionDisabled;
        let uploadDisabled = sectionDisabled || usesGst;
        if (!uploadDisabled) {
            if (!proof || proof === ENTITY_ADDRESS_PROOF_GST) {
                uploadDisabled = true;
            } else if (!isRegistered && this._officeSameAsRegistered === 'Yes') {
                uploadDisabled = true;
            } else {
                uploadDisabled = !!this._fileLabel(values.proofFile);
            }
        }

        let legendLabel = values.addressProof || fallbackLabel;
        let fileTitle = proof ? `Upload ${proof}` : 'Upload address proof';
        if (usesGst) {
            legendLabel = 'GST';
            fileTitle = 'GST Document';
        }

        const readOnly = isRegistered
            ? (this.isReadOnlyScreen || usesGst)
            : (this.isReadOnlyScreen || this.isOfficeAddressReadOnly);

        return { files, legendLabel, fileTitle, uploadDisabled, readOnly };
    }

    _entityAddressShowDetailFields(scope) {
        if (scope === 'office' && this._officeSameAsRegistered === 'Yes') {
            return this.registeredShowAddressDetailFields;
        }
        if (scope === 'registered'
            && this._entityGstRegisteredQuestionApplies
            && this._gstIsRegisteredAddress === 'Yes') {
            return this.isGstMandatoryComplete;
        }
        const values = this._getEntityAddressValues(scope);
        const proof = String(values.addressProof || '').trim();
        if (!proof) return false;
        if (proof === ENTITY_ADDRESS_PROOF_GST) return this.isGstMandatoryComplete;
        return !!this._fileLabel(values.proofFile);
    }

    get isGstMandatoryComplete() {
        if (!this.hasGstFile) {
            return false;
        }
        if (this._gstApiState !== 'success' && this._gstApiState !== 'failure') {
            return false;
        }
        const g = this.gstFieldValues;
        return !!(
            String(g.gstNumber || '').trim()
            && String(g.kycAddressLine1 || '').trim()
            && String(g.kycAddressLine2 || '').trim()
            && String(g.state || '').trim()
            && String(g.district || '').trim()
            && String(g.city || '').trim()
            && String(g.kycPinCode || '').trim()
        );
    }

    get showRegisteredAddressSection() {
        if (this._cinRequired) {
            if (!this.hasCinFile || !this.cinDetailSectionReady || !String(this.cinNumber || '').trim()) {
                return false;
            }
        }
        if (this._gstRequired && !this.isGstMandatoryComplete) {
            return false;
        }
        
        if (this._entityGstRegisteredQuestionApplies && !this._gstIsRegisteredAddress) {
            return false;
        }
        return true;
    }


    get registeredAddressDetailsComplete() {
        if (this._entityGstRegisteredQuestionApplies && this._gstIsRegisteredAddress === 'Yes') {
            return this.isGstMandatoryComplete;
        }
        return this._isEntityAddressSectionComplete(
            this.registeredAddressFieldValues,
            this.registeredShowAddressDetailFields,
            this.hasRegisteredProofFile
        );
    }


    get showOfficeSameAsRegisteredQuestion() {
        if (this.isReadOnlyScreen) {
            return true;
        }
        return this.registeredAddressDetailsComplete;
    }

    get isRegisteredAddressComplete() {
        // The "Office same as Registered?" answer is the last mandatory input of
        // the Registered section; gate Office Address behind an actual answer.
        if (!this._officeSameAsRegistered) {
            return false;
        }
        return this.registeredAddressDetailsComplete;
    }

    get showEntityOfficeAddressSection() {
        if (this._officeSameAsRegistered !== 'No') {
            return false;
        }
        if (this.isReadOnlyScreen) {
            return true;
        }
        return this.isRegisteredAddressComplete;
    }

    _getEntityAddressValues(scope) {
        return scope === 'office' ? this.officeAddressFieldValues : this.registeredAddressFieldValues;
    }

    async _removeEntityAddressProofFile(scope) {
        if (this.isReadOnlyScreen) return;
        const current = this._getEntityAddressValues(scope);
        const removed = current.proofFile;
        const addressProof = String(current.addressProof || '').trim();
        const checklistId = this._getEntityChecklistId(scope);
        this._setEntityAddressValues(scope, { ...current, proofFile: null });
        this._clearEntityAddressDetailFields(scope);
        if (addressProof) {
            this._untrackEntityUploadedDocumentType(addressProof);
        }
        await this._deleteEntityKycFile(checklistId, removed);
        if (scope === 'office') {
            this._entityOfficeChecklistId = null;
        } else {
            this._entityRegisteredChecklistId = null;
        }
    }

    _setEntityAddressValues(scope, nextValues) {
        if (scope === 'office') {
            this.officeAddressFieldValues = nextValues;
        } else {
            this.registeredAddressFieldValues = nextValues;
        }
    }

    _getEntityChecklistId(scope) {
        return scope === 'office' ? this._entityOfficeChecklistId : this._entityRegisteredChecklistId;
    }

    _setEntityLocOptions(scope, level, options) {
        this._entityLocOptions = {
            ...this._entityLocOptions,
            [scope]: { ...this._entityLocOptions[scope], [level]: options }
        };
    }

    _clearEntityLocLevels(scope, levels) {
        const patch = {};
        levels.forEach((level) => { patch[level] = []; });
        this._entityLocOptions = {
            ...this._entityLocOptions,
            [scope]: { ...this._entityLocOptions[scope], ...patch }
        };
    }

    _handleEntityDocFileRemove(docType) {
        if (this.isReadOnlyScreen) return;
        if (docType === 'cin') {
            const removed = this.cinFieldValues.cinFile;
            if (removed?.contentVersionId) {
                this._cinProcessedVersionIds.delete(removed.contentVersionId);
            }
            this.cinFieldValues = { cinFile: null };
            this._resetCinDetailFields();
            this._untrackEntityUploadedDocumentType('CIN Certificate');
            this._deleteEntityKycFile(this._cinChecklistRecordId, removed);
            return;
        }
        const removed = this.gstFieldValues.gstFile;
        if (removed?.contentVersionId) {
            this._gstProcessedVersionIds.delete(removed.contentVersionId);
        }
        this.gstFieldValues = { gstFile: null };
        this._resetGstDetailFields();
        this._untrackEntityUploadedDocumentType('GST Certificate');
        this._deleteEntityKycFile(this._gstChecklistRecordId, removed);
    }

    handleEntityDocNumberChange(event) {
        if (this.isReadOnlyScreen) return;
        const docType = event.currentTarget?.dataset?.doc;
        if (!docType) return;
        const value = event.detail?.value !== undefined ? event.detail.value : (event.target?.value || '');
        if (docType === 'cin') {
            this.cinFieldValues = { ...this.cinFieldValues, cinNumber: value };
            if (String(value || '').trim()) {
                this._saveNonIndividualKycDocNumber('CIN', value);
            }
            return;
        }
        this.gstFieldValues = { ...this.gstFieldValues, gstNumber: value };
        this._maybeLoadRegisteredLocationOptions();
        if (event.detail?.value !== undefined) {
            this._applyGstSelection(value);
        }
    }

    async handleGstFieldChange(event) {
        if (this.isReadOnlyScreen) return;
        const field = event.currentTarget?.dataset?.field;
        if (!field) return;
        const value = event.detail?.value !== undefined ? event.detail.value : (event.target?.value || '');

        if (field === 'gstNumber') {
            await this._applyGstSelection(value);
            return;
        }

        if (field === 'district') {
            this.gstFieldValues = { ...this.gstFieldValues, district: value };
        } else if (field === 'kycPinCode') {
            this.gstFieldValues = { ...this.gstFieldValues, kycPinCode: value };
            if (ENTITY_PINCODE_REGEX.test(String(value || '').trim())) {
                await this._resolveEntityPinCode('gst', String(value).trim());
            }
        } else {
            this.gstFieldValues = { ...this.gstFieldValues, [field]: value };
        }
        this._maybeLoadRegisteredLocationOptions();
        this._maybeSyncGstProofAddressSections();
    }

    async handleEntityAddressChange(event) {
        if (this.isReadOnlyScreen) return;
        const scope = event.currentTarget?.dataset?.scope;
        const field = event.currentTarget?.dataset?.field;
        if (!scope || !field) return;
        if (scope === 'registered' && this.registeredPanelUsesGstDocument) return;
        if (scope === 'office' && this.isOfficeAddressReadOnly) return;
        await this._applyEntityAddressFieldChange(scope, field, event);
    }

    async _applyEntityAddressFieldChange(scope, field, event) {
        const value = event.detail?.value !== undefined ? event.detail.value : (event.target?.value || '');
        const current = this._getEntityAddressValues(scope);

        if (field === 'addressProof') {
            if (current.addressProof !== value && current.proofFile) {
                this._removeEntityAddressProofFile(scope);
            }
            if (value === ENTITY_ADDRESS_PROOF_GST) {
                this._setEntityAddressValues(scope, { ...current, addressProof: value, proofFile: null });
                await this._copyGstDetailsToAddressSection(scope);
            } else {
                this._setEntityAddressValues(scope, { ...current, addressProof: value, proofFile: null });
                this._clearEntityAddressDetailFields(scope);
            }
            if (scope === 'registered') {
                this._maybePrepareEntityOfficeSection();
            }
            return;
        }

        if (field === 'district') {
            this._setEntityAddressValues(scope, { ...current, district: value });
            if (scope === 'registered') {
                this._maybePrepareEntityOfficeSection();
            }
            return;
        }

        if (field === 'kycPinCode') {
            this._setEntityAddressValues(scope, { ...current, kycPinCode: value });
            if (ENTITY_PINCODE_REGEX.test(String(value || '').trim())) {
                await this._resolveEntityPinCode(scope, String(value).trim());
            } else if (scope === 'registered') {
                if (this._officeSameAsRegistered === 'Yes') {
                    this._syncOfficeAddressFromRegistered();
                }
                this._maybePrepareEntityOfficeSection();
            }
            return;
        }

        this._setEntityAddressValues(scope, { ...current, [field]: value });
        if (scope === 'registered') {
            if (this._officeSameAsRegistered === 'Yes') {
                this._syncOfficeAddressFromRegistered();
            }
            this._maybePrepareEntityOfficeSection();
        }
    }

    async _applyGstSelection(gstNumber) {
        const state = gstNumber ? (this._gstStateByNumber[gstNumber] || '') : '';
        this.gstFieldValues = {
            ...this.gstFieldValues,
            gstNumber,
            state,
            district: '',
            city: ''
        };
        this._clearEntityLocLevels('gst', ['district']);
        if (state) {
            await this._loadLocationOptions('gst', 'district', state, null);
        }
        this._maybeLoadRegisteredLocationOptions();
        this._maybeSyncGstProofAddressSections();
        if (String(gstNumber || '').trim()) {
            await this._saveNonIndividualKycDocNumber('GST', gstNumber, state);
        }
    }

    async handleGstIsRegisteredAddressChange(event) {
        if (this.isReadOnlyScreen) return;
        const value = event.target.value;
        if (value === this._gstIsRegisteredAddress) return;

        if (this.registeredAddressFieldValues.proofFile) {
            this._removeEntityAddressProofFile('registered');
        }
        this._gstIsRegisteredAddress = value;

        if (value === 'Yes') {
            this.registeredAddressFieldValues = { ...this._gstAddressFieldSnapshot() };
            await this._ensureEntityLocationOptionsLoaded('registered');
        } else {
            this.registeredAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
            this._clearEntityLocLevels('registered', ['district']);
        }
        this._resetEntityOfficeFromRegisteredChange();
    }

    async handleOfficeSameAsRegisteredChange(event) {
        if (this.isReadOnlyScreen) return;
        const value = event.target.value;
        if (value === this._officeSameAsRegistered) return;
        this._officeSameAsRegistered = value;

        if (value === 'Yes') {
            if (this.officeAddressFieldValues.proofFile) {
                this._removeEntityAddressProofFile('office');
            }
            this._syncOfficeAddressFromRegistered();
        } else {
            if (this.officeAddressFieldValues.proofFile) {
                this._removeEntityAddressProofFile('office');
            }
            this.officeAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
            this._clearEntityLocLevels('office', ['district']);
        }
        await this._ensureEntityLocationOptionsLoaded('office');
        this._maybePrepareEntityOfficeSection();
    }

    _resetEntityOfficeFromRegisteredChange() {
        this._officeSameAsRegistered = '';
        if (this.officeAddressFieldValues.proofFile) {
            this._removeEntityAddressProofFile('office');
        }
        this.officeAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
        this._clearEntityLocLevels('office', ['district']);
    }

    _gstAddressFieldSnapshot() {
        return {
            addressProof: ENTITY_ADDRESS_PROOF_GST,
            kycAddressLine1: this.gstFieldValues.kycAddressLine1 || '',
            kycAddressLine2: this.gstFieldValues.kycAddressLine2 || '',
            state: this.gstFieldValues.state || '',
            district: this.gstFieldValues.district || '',
            city: this.gstFieldValues.city || '',
            kycPinCode: this.gstFieldValues.kycPinCode || ''
        };
    }

    async _copyGstDetailsToAddressSection(scope) {
        if (!this.isGstMandatoryComplete) return;
        const snapshot = this._gstAddressFieldSnapshot();
        if (scope === 'registered') {
            this.registeredAddressFieldValues = { ...this.registeredAddressFieldValues, ...snapshot };
            await this._ensureEntityLocationOptionsLoaded('registered');
            this._maybePrepareEntityOfficeSection();
            return;
        }
        this._setEntityAddressValues(scope, { ...this._getEntityAddressValues(scope), ...snapshot });
        await this._ensureEntityLocationOptionsLoaded('office');
    }

    _maybeSyncGstProofAddressSections() {
        if (this._gstIsRegisteredAddress === 'Yes') {
            if (this.isGstMandatoryComplete) {
                this.registeredAddressFieldValues = { ...this._gstAddressFieldSnapshot() };
                this._ensureEntityLocationOptionsLoaded('registered');
            }
            if (this._officeSameAsRegistered === 'Yes') {
                this._syncOfficeAddressFromRegistered();
            }
            this._maybePrepareEntityOfficeSection();
            return;
        }
        if (!this.isGstMandatoryComplete) return;
        const regProof = String(this.registeredAddressFieldValues.addressProof || '').trim();
        if (regProof === ENTITY_ADDRESS_PROOF_GST) {
            this.registeredAddressFieldValues = { ...this._gstAddressFieldSnapshot() };
            this._ensureEntityLocationOptionsLoaded('registered');
        }
        if (this._officeSameAsRegistered === 'Yes') {
            this._syncOfficeAddressFromRegistered();
        } else if (this.officeAddressFieldValues.addressProof === ENTITY_ADDRESS_PROOF_GST) {
            this.officeAddressFieldValues = {
                ...this.officeAddressFieldValues,
                ...this._gstAddressFieldSnapshot()
            };
            this._ensureEntityLocationOptionsLoaded('office');
        }
        this._maybePrepareEntityOfficeSection();
    }

    async _deleteEntityKycFile(checklistRecordId, removed) {
        if (!checklistRecordId || !removed) return;
        try {
            await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_DELETE_FILE,
                recordId      : this._recordId,
                params        : {
                    checklistRecordId,
                    contentDocumentId : removed.contentDocumentId,
                    contentVersionId  : removed.contentVersionId
                }
            });
        } catch (error) {
            console.error('wheelsIndividualKYCMasterPage: _deleteEntityKycFile', error);
        }
    }

    _normalizeNonIndividualKycDocType(docType) {
        const normalized = String(docType || '').trim().toUpperCase();
        return NON_INDIVIDUAL_KYC_DOC[normalized] ? normalized : null;
    }

    _getNonIndividualKycDocConfig(docType) {
        const key = this._normalizeNonIndividualKycDocType(docType);
        return key ? NON_INDIVIDUAL_KYC_DOC[key] : null;
    }

    async _invokeNonIndividualKycDocApex(apexMethodName, params = {}) {
        return savePageData({
            apexClassName : APEX_CLASS,
            apexMethodName,
            recordId      : this._recordId,
            params        : {
                applicantId: this._applicantId,
                ...params
            }
        });
    }

    _applyEntityConstitutionFromResponse(entityKyc) {
        this._entityTypeCode = this._normalizeEntityTypeCode(entityKyc?.entityTypeCode);
        this._cinRequired = entityKyc.cinRequired === true;
        this._gstRequired = entityKyc.gstRequired === true;
        this._entityRequiredDocuments = Array.isArray(entityKyc.requiredDocuments)
            ? [...entityKyc.requiredDocuments]
            : [];
        this._entityAdhocDocuments = Array.isArray(entityKyc.adhocDocuments)
            ? [...entityKyc.adhocDocuments]
            : [];
        this._entityAdhocDocumentCount = Number(entityKyc.adhocDocumentCount) || 0;
        this._entityUploadedDocumentTypes = Array.isArray(entityKyc.uploadedDocumentTypes)
            ? [...entityKyc.uploadedDocumentTypes]
            : [];
        this._entityRequiredDocItems = Array.isArray(entityKyc.requiredDocItems)
            ? entityKyc.requiredDocItems.map((item) => ({ ...item }))
            : [];
        this._entityAdhocDocItems = Array.isArray(entityKyc.adhocDocItems)
            ? entityKyc.adhocDocItems.map((item) => ({ ...item }))
            : [];
        this._entityAdhocGroupSatisfied = entityKyc.adhocGroupSatisfied === true;
        this._applyDarpan(entityKyc?.darpan);
    }

    _normalizeEntityTypeCode(value) {
        return String(value ?? '').trim();
    }

    _applyDarpan(payload) {
        const darpan = payload && typeof payload === 'object' ? payload : {};
        const inferred = this._inferDarpanStateFromDocuments(
            this._darpanDocuments,
            darpan.npoStatus,
            darpan.deferralApproval
        );
        let nextStatus = String(darpan.npoStatus || '').trim();
        const deferralFromPayload = darpan.deferralApproval === true
            || String(darpan.deferralApproval || '').trim().toLowerCase() === 'yes';
        const nextDeferral = deferralFromPayload || inferred.deferralApproval
            ? DARPAN_DEFERRAL_YES
            : DARPAN_DEFERRAL_NO;
        if (nextDeferral === DARPAN_DEFERRAL_YES) {
            // Deferral flow is valid only for NPO, so keep status aligned.
            nextStatus = DARPAN_NPO_STATUS_NPO;
        } else if (!nextStatus) {
            nextStatus = String(inferred.npoStatus || '').trim();
        }

        this._darpanNpoStatus = nextStatus;
        this._darpanDeferralApproval = nextDeferral;
        this._darpanId = String(darpan.darpanId || '').trim();
        this._darpanRegistrationDate = this._toDateTimeInputValue(
            darpan.registrationDate || darpan.darpanRegistrationDate
        );
        this._darpanRequiredItems = this._buildLocalDarpanRequiredItems();
        this._darpanAdhocItems = Array.isArray(darpan.adhocDocItems)
            ? darpan.adhocDocItems.map((item) => ({ ...item }))
            : [];
        this._darpanAdhocGroupSatisfied = darpan.adhocGroupSatisfied === true;
        if (darpan.documentsComplete === true) {
            this._darpanError = '';
        }
        if (!this._canEditDarpanIdFields()) {
            this._clearDarpanIdFields();
        }
    }

    _canEditDarpanIdFields() {
        if (this._darpanNpoStatus !== DARPAN_NPO_STATUS_NPO) {
            return false;
        }
        return this._darpanDeferralApproval !== DARPAN_DEFERRAL_YES;
    }

    _getRequiredDarpanDocumentTypes() {
        if (!this.isDarpanApplicableEntity) {
            return [];
        }
        if (this._darpanDeferralApproval === DARPAN_DEFERRAL_YES) {
            return [DARPAN_DOC_TYPE_DEFERRAL_APPROVAL, DARPAN_DOC_TYPE_ACK_COPY];
        }
        if (this._darpanNpoStatus === DARPAN_NPO_STATUS_NPO) {
            return [DARPAN_DOC_TYPE_CERTIFICATE];
        }
        if (this._darpanNpoStatus === DARPAN_NPO_STATUS_NOT_NPO) {
            return [DARPAN_DOC_TYPE_CUSTOMER_DECLARATION];
        }
        return [];
    }

    _getAllowedDarpanDocumentTypes() {
        return this._getRequiredDarpanDocumentTypes();
    }

    _activeDarpanDocuments() {
        return (this._darpanDocuments || []).filter((entry) => {
            const documentType = String(entry?.documentType || '').trim();
            return documentType && DARPAN_DOC_TYPES.has(documentType);
        });
    }

    _darpanPanelFilesView() {
        return this._activeDarpanDocuments()
            .filter((entry) => entry.proofFile)
            .map((entry) => ({
                id: entry.checklistRecordId || entry.documentType,
                name: entry.documentType,
                fileName: this._fileLabel(entry.proofFile) || entry.documentType,
                checklistRecordId: entry.checklistRecordId || null,
                contentVersionId: entry.proofFile?.contentVersionId || null,
                contentDocumentId: entry.proofFile?.contentDocumentId || null,
                extension: this._fileExtension(entry.proofFile)
            }));
    }

    _buildLocalDarpanRequiredItems() {
        const uploaded = new Set(
            this._activeDarpanDocuments()
                .filter((entry) => entry?.proofFile)
                .map((entry) => String(entry?.documentType || '').trim())
                .filter(Boolean)
        );
        return this._getRequiredDarpanDocumentTypes().map((name) => ({
            name,
            isUploaded: uploaded.has(name)
        }));
    }

    _findDarpanDocumentEntry(fileId) {
        if (!fileId) return null;
        return this._activeDarpanDocuments().find(
            (entry) => (entry.checklistRecordId || entry.documentType) === fileId
        ) || null;
    }

    _findDarpanDocumentEntryByType(documentType) {
        const type = String(documentType || '').trim();
        if (!type) return null;
        return this._activeDarpanDocuments().find(
            (entry) => String(entry?.documentType || '').trim() === type
        ) || null;
    }

    _darpanSectionKeyForDocType(documentType) {
        return `darpan::${String(documentType || '').trim()}`;
    }

    _darpanDocTypeFromSectionKey(sectionKey) {
        const key = String(sectionKey || '').trim();
        if (!key.startsWith('darpan::')) {
            return '';
        }
        return key.substring('darpan::'.length).trim();
    }

    _clearDarpanIdFields() {
        this._darpanId = '';
        this._darpanRegistrationDate = '';
    }

    _hydrateDarpanDocumentsFromResponse(payload) {
        let entries = [];
        if (Array.isArray(payload)) {
            entries = payload;
        } else if (payload && typeof payload === 'object' && payload.documentType) {
            entries = [payload];
        }
        this._darpanDocuments = entries
            .filter((entry) => entry && typeof entry === 'object')
            .map((entry) => ({
                documentType: String(entry.documentType || '').trim(),
                checklistRecordId: entry.checklistRecordId || null,
                proofFile: entry.proofFile || null
            }))
            .filter((entry) => entry.documentType && DARPAN_DOC_TYPES.has(entry.documentType));
    }

    _inferDarpanStateFromDocuments(documents, currentStatus, currentDeferralApproval) {
        const rawDocs = Array.isArray(documents) ? documents : [];
        const hasDeferralDocs = rawDocs.some((entry) => {
            const docType = String(entry?.documentType || '').trim();
            return docType === DARPAN_DOC_TYPE_DEFERRAL_APPROVAL || docType === DARPAN_DOC_TYPE_ACK_COPY;
        });
        const hasDarpanCertificate = rawDocs.some(
            (entry) => String(entry?.documentType || '').trim() === DARPAN_DOC_TYPE_CERTIFICATE
        );
        const hasCustomerDeclaration = rawDocs.some(
            (entry) => String(entry?.documentType || '').trim() === DARPAN_DOC_TYPE_CUSTOMER_DECLARATION
        );
        const normalizedStatus = String(currentStatus || '').trim();
        let npoStatus = normalizedStatus;
        if (!npoStatus) {
            if (hasCustomerDeclaration) {
                npoStatus = DARPAN_NPO_STATUS_NOT_NPO;
            } else if (hasDeferralDocs || hasDarpanCertificate) {
                npoStatus = DARPAN_NPO_STATUS_NPO;
            }
        }

        const deferralIsTrue = currentDeferralApproval === true
            || String(currentDeferralApproval || '').trim().toLowerCase() === 'yes';
        const deferralApproval = deferralIsTrue || hasDeferralDocs;
        return {
            npoStatus,
            deferralApproval
        };
    }

    _getEntityAddressProofTypesInUse() {
        const inUse = new Set();
        const regProof = String(this.registeredAddressFieldValues.addressProof || '').trim();
        if (regProof) {
            if (this.hasRegisteredProofFile || regProof === ENTITY_ADDRESS_PROOF_GST) {
                inUse.add(regProof);
            }
            if (regProof === ENTITY_ADDRESS_PROOF_GST) {
                inUse.add('GST Certificate');
                inUse.add('GST');
            }
        }
        const officeProof = String(this.officeAddressFieldValues.addressProof || '').trim();
        if (officeProof && this.hasOfficeProofFile) {
            inUse.add(officeProof);
        }
        return inUse;
    }

    _isExcludedFromAdditionalDocumentsSection(documentType) {
        const trimmed = String(documentType || '').trim();
        if (DARPAN_DOC_TYPES.has(trimmed)) {
            return true;
        }
        const isGstType = trimmed === 'GST' || trimmed === 'GST Certificate';
        if (!trimmed || (ENTITY_DOC_PICKLIST_EXCLUDED.has(trimmed) && !(isGstType && !this._gstRequired))) {
            return true;
        }
        if ((trimmed === 'CIN' || trimmed === 'CIN Certificate') && this.hasCinFile) {
            return true;
        }
        if ((trimmed === 'GST' || trimmed === 'GST Certificate') && this.hasGstFile) {
            return true;
        }
        return this._getEntityAddressProofTypesInUse().has(trimmed);
    }

    _formatEntityMandatoryDocsError(missingRequired, adhocRemaining) {
        const missing = Array.isArray(missingRequired)
            ? missingRequired.map((doc) => String(doc || '').trim()).filter(Boolean)
            : [];
        const adhocCount = Number(adhocRemaining) || 0;
        if (!missing.length && adhocCount <= 0) {
            return '';
        }

        const lines = ['Please upload the following mandatory documents:'];
        // Show each missing document on its own line only (no comma-joined summary).
        missing.forEach((docName) => lines.push(`• ${docName}`));
        if (adhocCount > 0) {
            const adhocMin = this._entityAdhocDocumentCount || adhocCount;
            lines.push(`• Upload at least ${adhocMin} document(s) from the optional list.`);
        }
        return lines.join('\n');
    }

    handleOpenEntityMandatoryDocsModal() {
        this.showEntityMandatoryDocsModal = true;
        // Always re-pull the latest checklist state so the tick marks reflect
        // the current uploads/deletes instead of the last-rendered (stale) state.
        this._refreshEntityDocumentValidation();
    }

    handleCloseEntityMandatoryDocsModal() {
        this.showEntityMandatoryDocsModal = false;
    }

    handleEntityMandatoryDocsModalOverlayClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCloseEntityMandatoryDocsModal();
        }
    }

    _buildEntityDocumentPool() {
        const combined = [];
        const seen = new Set();
        [...this._entityRequiredDocuments, ...this._entityAdhocDocuments].forEach((docName) => {
            const trimmed = String(docName || '').trim();
            const isGstType = trimmed === 'GST' || trimmed === 'GST Certificate';
            const shouldExclude = ENTITY_DOC_PICKLIST_EXCLUDED.has(trimmed)
                && !(isGstType && !this._gstRequired);
            if (!trimmed || shouldExclude || DARPAN_DOC_TYPES.has(trimmed) || seen.has(trimmed)) {
                return;
            }
            seen.add(trimmed);
            combined.push(trimmed);
        });
        return combined;
    }

    _getEntityUploadedDocumentTypeSet() {
        return new Set(this._entityUploadedDocumentTypes || []);
    }

    _trackEntityUploadedDocumentType(documentType) {
        const trimmed = String(documentType || '').trim();
        if (!trimmed) {
            return;
        }
        const next = new Set(this._entityUploadedDocumentTypes || []);
        next.add(trimmed);
        if (trimmed === 'CIN') {
            next.add('CIN Certificate');
        }
        if (trimmed === 'GST') {
            next.add('GST Certificate');
        }
        this._entityUploadedDocumentTypes = [...next];
    }

    _untrackEntityUploadedDocumentType(documentType) {
        const trimmed = String(documentType || '').trim();
        if (!trimmed) {
            return;
        }
        const next = new Set(this._entityUploadedDocumentTypes || []);
        next.delete(trimmed);
        if (trimmed === 'CIN' || trimmed === 'CIN Certificate') {
            next.delete('CIN');
            next.delete('CIN Certificate');
        }
        if (trimmed === 'GST' || trimmed === 'GST Certificate') {
            next.delete('GST');
            next.delete('GST Certificate');
        }
        this._entityUploadedDocumentTypes = [...next];
    }

    _isCinSectionComplete() {
        return this.hasCinFile
            && this.cinDetailSectionReady
            && String(this.cinNumber || '').trim();
    }

    _buildEntityDocumentPicklistOptions(scope) {
        let pool = this._buildEntityDocumentPool();
        if (scope === 'address' && !pool.includes(ENTITY_ADDRESS_PROOF_ELECTRICITY)) {
            pool = [ENTITY_ADDRESS_PROOF_ELECTRICITY, ...pool];
        }
        const uploaded = this._getEntityUploadedDocumentTypeSet();
        const addressProofsInUse = scope === 'additional'
            ? this._getEntityAddressProofTypesInUse()
            : new Set();
        return pool
            .filter((docName) => !uploaded.has(docName) && !addressProofsInUse.has(docName))
            .map((docName) => ({ label: docName, value: docName }));
    }

    _buildEntityAddressProofOptionsForScope(scope) {
        const values = this._getEntityAddressValues(scope);
        const current = String(values.addressProof || '').trim();
        const options = this._buildEntityDocumentPicklistOptions('address');
        if (current && !options.some((entry) => entry.value === current)) {
            return [{ label: current, value: current }, ...options];
        }
        return options;
    }

    async _refreshEntityDocumentValidation() {
        if (!this._recordId || !this.isNonIndividualApplicant) {
            return;
        }
        try {
            const response = await getKYCInfoPageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_GET,
                recordId      : this._recordId,
                params        : { applicantId: this._applicantId || this._resolveApplicantIdForLoad() }
            });
            if (response?.isSuccess !== false && response?.entityKyc) {
                this._hydrateDarpanDocumentsFromResponse(response.entityKyc.darpanDocuments);
                this._applyEntityConstitutionFromResponse(response.entityKyc);
            }
        } catch (error) {
            console.error('wheelsIndividualKYCMasterPage: _refreshEntityDocumentValidation', error);
        }
    }

    async _saveNonIndividualKycDocNumber(docType, kycNumber, kycState) {
        if (!this._applicantId || this.isReadOnlyScreen) return;
        const config = this._getNonIndividualKycDocConfig(docType);
        if (!config) return;
        const trimmed = String(kycNumber || '').trim();
        if (!trimmed) return;
        const params = {
            docType: config.docType,
            kycNumber: trimmed,
            checklistRecordId: this[config.checklistIdKey]
        };
        if (config.docType === 'GST' && kycState) {
            params.kycState = kycState;
        }
        try {
            await this._invokeNonIndividualKycDocApex(APEX_METHOD_SAVE_NON_INDIVIDUAL_KYC_DOC, params);
        } catch (e) {
            console.error(
                `wheelsIndividualKYCMasterPage: _saveNonIndividualKycDocNumber(${config.docType})`,
                e
            );
        }
    }

    async _hydrateEntityKycFromResponse(entityKyc) {
        if (!entityKyc || typeof entityKyc !== 'object') return;
        this.cinFieldValues = {};
        this.gstFieldValues = {};
        this.registeredAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
        this.officeAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
        this._gstIsRegisteredAddress = '';
        this._officeSameAsRegistered = '';
        this._applyEntityConstitutionFromResponse(entityKyc);
        this._cinChecklistRecordId = entityKyc.cinChecklistRecordId || null;
        this._gstChecklistRecordId = entityKyc.gstChecklistRecordId || null;
        if (entityKyc.cinFile) {
            this.cinFieldValues = { ...this.cinFieldValues, cinFile: entityKyc.cinFile };
            this._trackEntityUploadedDocumentType('CIN Certificate');
        }
        if (entityKyc.gstFile) {
            this.gstFieldValues = { ...this.gstFieldValues, gstFile: entityKyc.gstFile };
            this._trackEntityUploadedDocumentType('GST Certificate');
        }
        if (entityKyc.cinDetails) {
            this._applyCinDetailsFromBackend(entityKyc.cinDetails);
        }
        if (entityKyc.gstDetails) {
            await this._applyGstDetailsFromBackend(entityKyc.gstDetails);
        }

        try {
            await this._hydrateEntityAddressSectionsFromResponse(entityKyc);
        } catch (error) {
            console.error('wheelsIndividualKYCMasterPage: entity address hydration', error);
        }

        this._hydrateEntityAdditionalDocumentsFromResponse(
            entityKyc.additionalDocuments || entityKyc.additionalDocument
        );
        this._hydrateDarpanDocumentsFromResponse(entityKyc.darpanDocuments);
        this._applyDarpan(entityKyc.darpan);

        this._entityAdditionalDocuments = (this._entityAdditionalDocuments || []).filter(
            (entry) => !this._isExcludedFromAdditionalDocumentsSection(entry.documentType)
        );
    }

    _hydrateEntityAdditionalDocumentsFromResponse(payload) {
        let entries = [];
        if (Array.isArray(payload)) {
            entries = payload;
        } else if (payload && typeof payload === 'object' && payload.documentType) {
            entries = [payload];
        }

        this._entityAdditionalDocuments = entries
            .filter((entry) => entry && typeof entry === 'object')
            .map((entry) => ({
                documentType: entry.documentType || '',
                checklistRecordId: entry.checklistRecordId || null,
                proofFile: entry.proofFile || null
            }))
            .filter((entry) => entry.documentType || entry.proofFile)
            .filter((entry) => !this._isExcludedFromAdditionalDocumentsSection(entry.documentType));

        this._entityAdditionalDocumentType = '';
    }

    _entityAdditionalPanelFilesView() {
        return (this._entityAdditionalDocuments || [])
            .filter((entry) => entry.proofFile)
            .filter((entry) => !this._isExcludedFromAdditionalDocumentsSection(entry.documentType))
            .map((entry) => ({
                id: entry.checklistRecordId || entry.documentType,
                name: entry.documentType,
                fileName: this._fileLabel(entry.proofFile) || entry.documentType,
                checklistRecordId: entry.checklistRecordId,
                contentVersionId: entry.proofFile?.contentVersionId || null,
                contentDocumentId: entry.proofFile?.contentDocumentId || null,
                extension: this._fileExtension(entry.proofFile)
            }));
    }

    handleEntityAdditionalDocumentTypeChange(event) {
        if (this.isReadOnlyScreen) return;
        this._entityAdditionalDocumentType = event.detail?.value || '';
    }

    handleDarpanNpoStatusChange(event) {
        if (this.isReadOnlyScreen) return;
        this._darpanNpoStatus = event.target?.value || '';
        this._darpanError = '';
        if (this._darpanNpoStatus !== DARPAN_NPO_STATUS_NPO) {
            this._darpanDeferralApproval = DARPAN_DEFERRAL_NO;
            this._clearDarpanIdFields();
        }
        this._darpanDocumentType = '';
        this._darpanRequiredItems = this._buildLocalDarpanRequiredItems();
    }

    handleDarpanDeferralApprovalChange(event) {
        if (this.isReadOnlyScreen) return;
        this._darpanDeferralApproval = event.target?.value || DARPAN_DEFERRAL_NO;
        this._darpanError = '';
        if (this._darpanDeferralApproval === DARPAN_DEFERRAL_YES) {
            this._darpanNpoStatus = DARPAN_NPO_STATUS_NPO;
            this._clearDarpanIdFields();
        }
        this._darpanDocumentType = '';
        this._darpanRequiredItems = this._buildLocalDarpanRequiredItems();
    }

    handleDarpanIdChange(event) {
        if (this.isReadOnlyScreen) return;
        this._darpanId = String(event.detail?.value || '').trim();
    }

    handleDarpanRegistrationDateChange(event) {
        if (this.isReadOnlyScreen) return;
        this._darpanRegistrationDate = String(event.detail?.value || '').trim();
    }

    handleDarpanDocumentTypeChange(event) {
        if (this.isReadOnlyScreen) return;
        this._darpanDocumentType = event.detail?.value || '';
    }

    handleOpenDarpanMandatoryDocsModal() {
        this.showDarpanMandatoryDocsModal = true;
    }

    handleCloseDarpanMandatoryDocsModal() {
        this.showDarpanMandatoryDocsModal = false;
    }

    handleDarpanMandatoryDocsModalOverlayClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCloseDarpanMandatoryDocsModal();
        }
    }

    _findEntityAdditionalDocumentEntry(fileId) {
        if (!fileId) return null;
        return (this._entityAdditionalDocuments || []).find(
            (entry) => (entry.checklistRecordId || entry.documentType) === fileId
        ) || null;
    }

    async handleEntityPanelUploadRequest(event) {
        const sectionKey = event.detail?.sectionKey;
        const darpanDocType = this._darpanDocTypeFromSectionKey(sectionKey);
        if (sectionKey === 'darpan' || darpanDocType) {
            await this._openEntityAdvancedUpload('darpan', darpanDocType || null);
            return;
        }
        if (sectionKey === 'cin' || sectionKey === 'gst' || sectionKey === 'additional'
            || sectionKey === 'registered' || sectionKey === 'office') {
            await this._openEntityAdvancedUpload(sectionKey);
        }
    }

    handleEntityPanelFilePreview(event) {
        const detail = event.detail || {};
        let contentVersionId = detail.contentVersionId || null;
        let fileName = detail.fileName || '';
        let fileExtension = detail.fileType || '';

        if (!contentVersionId && detail.fileId) {
            const sectionKey = detail.sectionKey;
            if (sectionKey === 'cin' && this.cinFieldValues.cinFile) {
                contentVersionId = this.cinFieldValues.cinFile.contentVersionId || null;
                if (!fileName) fileName = this._fileLabel(this.cinFieldValues.cinFile);
                if (!fileExtension) fileExtension = this._fileExtension(this.cinFieldValues.cinFile) || '';
            } else if (sectionKey === 'gst' && this.gstFieldValues.gstFile) {
                contentVersionId = this.gstFieldValues.gstFile.contentVersionId || null;
                if (!fileName) fileName = this._fileLabel(this.gstFieldValues.gstFile);
                if (!fileExtension) fileExtension = this._fileExtension(this.gstFieldValues.gstFile) || '';
            } else if (sectionKey === 'registered' || sectionKey === 'office') {
                const panelFile = this._entityAddressPanelConfig(sectionKey).files[0];
                if (panelFile?.contentVersionId) {
                    contentVersionId = panelFile.contentVersionId;
                    if (!fileName) fileName = panelFile.fileName || panelFile.name || '';
                    if (!fileExtension) fileExtension = panelFile.extension || '';
                }
            } else if (sectionKey === 'darpan' || this._darpanDocTypeFromSectionKey(sectionKey)) {
                const docTypeFromSection = this._darpanDocTypeFromSectionKey(sectionKey);
                const entry = docTypeFromSection
                    ? this._findDarpanDocumentEntryByType(docTypeFromSection)
                    : this._findDarpanDocumentEntry(detail.fileId);
                contentVersionId = entry?.proofFile?.contentVersionId || null;
                if (!fileName) {
                    fileName = this._fileLabel(entry?.proofFile) || entry?.documentType || '';
                }
                if (!fileExtension) {
                    fileExtension = this._fileExtension(entry?.proofFile) || '';
                }
            } else {
                const entry = this._findEntityAdditionalDocumentEntry(detail.fileId);
                contentVersionId = entry?.proofFile?.contentVersionId || null;
                if (!fileName) {
                    fileName = this._fileLabel(entry?.proofFile) || entry?.documentType || '';
                }
                if (!fileExtension) {
                    fileExtension = this._fileExtension(entry?.proofFile) || '';
                }
            }
        }
        if (!contentVersionId) return;

        this.entityPreviewContentVersionId = contentVersionId;
        this.entityPreviewFileName = fileName;
        this.entityPreviewFileExtension = fileExtension;
        this.showEntityEmbedFilePreview = true;
    }

    handleEntityEmbedFilePreviewClose() {
        this.showEntityEmbedFilePreview = false;
        this.entityPreviewContentVersionId = null;
        this.entityPreviewFileName = '';
        this.entityPreviewFileExtension = '';
    }

    _initFilePreviewContext() {
        const origin = window.location.origin;
        const isSite = location.pathname.split('/').length >= 2 && location.pathname.split('/')[2] === 's';
        if (isSite) {
            this._vfRoot = origin;
        } else {
            const sandboxSuffix = origin.includes('sandbox') ? '.sandbox' : '';
            this._vfRoot = origin.split('.')[0] + '--c' + sandboxSuffix + '.vf.force.com';
        }
        getUserSessionId()
            .then((id) => { this._sessionId = id; })
            .catch(() => { /* preview download may fail without a session */ });
    }

    async _resolveContentDocumentIdFromVersion(contentVersionId) {
        if (!contentVersionId) return null;
        try {
            const response = await this._invokeNonIndividualKycDocApex(
                APEX_METHOD_RESOLVE_CONTENT_DOCUMENT_ID,
                { contentVersionId }
            );
            return response?.isSuccess ? (response.contentDocumentId || null) : null;
        } catch (error) {
            console.error('wheelsIndividualKYCMasterPage: _resolveContentDocumentIdFromVersion', error);
            return null;
        }
    }

    async handleEntityPanelFileDelete(event) {
        const sectionKey = event.detail?.sectionKey;
        if (sectionKey === 'cin') {
            this._handleEntityDocFileRemove('cin');
            await this._refreshEntityDocumentValidation();
            return;
        }
        if (sectionKey === 'gst') {
            this._handleEntityDocFileRemove('gst');
            await this._refreshEntityDocumentValidation();
            return;
        }
        if (sectionKey === 'registered') {
            if (this.registeredPanelUsesGstDocument) {
                return;
            }
            await this._removeEntityAddressProofFile('registered');
            await this._refreshEntityDocumentValidation();
            return;
        }
        if (sectionKey === 'office') {
            await this._removeEntityAddressProofFile('office');
            await this._refreshEntityDocumentValidation();
            return;
        }
        if (sectionKey === 'darpan' || this._darpanDocTypeFromSectionKey(sectionKey)) {
            const fileId = event.detail?.fileId;
            const docTypeFromSection = this._darpanDocTypeFromSectionKey(sectionKey);
            const entry = docTypeFromSection
                ? this._findDarpanDocumentEntryByType(docTypeFromSection)
                : this._findDarpanDocumentEntry(fileId);
            if (!entry) return;
            await this._deleteEntityAdditionalProofFile(entry);
            this._darpanDocuments = this._activeDarpanDocuments().filter(
                (item) => item.documentType !== entry.documentType
            );
            this._darpanRequiredItems = this._buildLocalDarpanRequiredItems();
            await this._refreshEntityDocumentValidation();
            return;
        }
        if (sectionKey !== 'additional') return;

        const fileId = event.detail?.fileId;
        const entry = this._findEntityAdditionalDocumentEntry(fileId);
        if (!entry) return;

        await this._deleteEntityAdditionalProofFile(entry);
        this._untrackEntityUploadedDocumentType(entry.documentType);
        this._entityAdditionalDocuments = (this._entityAdditionalDocuments || []).filter(
            (item) => (item.checklistRecordId || item.documentType) !== fileId
        );
        await this._refreshEntityDocumentValidation();
    }

    async _deleteEntityAdditionalProofFile(entry) {
        if (!entry?.checklistRecordId) return;
        const fileMeta = entry.proofFile;
        try {
            await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_DELETE_FILE,
                recordId      : this._recordId,
                params        : {
                    checklistRecordId: entry.checklistRecordId,
                    contentDocumentId: fileMeta?.contentDocumentId || null,
                    contentVersionId: fileMeta?.contentVersionId || null,
                    softDeleteRow: true
                }
            });
        } catch (error) {
            console.error('wheelsIndividualKYCMasterPage: _deleteEntityAdditionalProofFile', error);
        }
    }

    async _openEntityAdvancedUpload(sectionKey, forcedDocumentType = null) {
        const config = ENTITY_DV_SECTIONS[sectionKey];
        if (!config || !this._recordId || !this._applicantId || this.isReadOnlyScreen) {
            return;
        }

        let documentType = '';
        let documentName = '';
        if (sectionKey === 'darpan') {
            documentType = String(forcedDocumentType || this._darpanDocumentType || '').trim();
            documentName = documentType;
            if (!documentType) {
                this._toast('Document type required', 'Select a Darpan document type before uploading.', 'warning');
                return;
            }
            if (!this._getAllowedDarpanDocumentTypes().includes(documentType)) {
                this._toast('Invalid document type', 'Select a valid Darpan document type.', 'warning');
                return;
            }
            const alreadyUploaded = this._activeDarpanDocuments().some(
                (entry) => String(entry?.documentType || '').trim() === documentType
            );
            if (alreadyUploaded) {
                this._toast(
                    'Document already uploaded',
                    'Choose a different Darpan document type for the next upload.',
                    'warning'
                );
                return;
            }
        } else if (sectionKey === 'additional') {
            documentType = String(this._entityAdditionalDocumentType || '').trim();
            documentName = documentType;
            if (!documentType) {
                this._toast('Document type required', 'Select a document type before uploading.', 'warning');
                return;
            }
            const alreadyUploaded = (this._entityAdditionalDocuments || []).some(
                (entry) => entry.documentType === documentType
            );
            if (alreadyUploaded) {
                this._toast(
                    'Document already uploaded',
                    'Choose a different document type for the next upload.',
                    'warning'
                );
                return;
            }
        } else if (sectionKey === 'registered' || sectionKey === 'office') {
            const values = sectionKey === 'registered'
                ? this.registeredAddressFieldValues
                : this.officeAddressFieldValues;
            documentType = String(values.addressProof || '').trim();
            documentName = documentType;
            if (!documentType) {
                this._toast(
                    'Address proof required',
                    'Select an address proof before uploading.',
                    'warning'
                );
                return;
            }
            if (documentType === ENTITY_ADDRESS_PROOF_GST) {
                this._toast(
                    'Upload not required',
                    'GST address proof does not require a separate upload.',
                    'warning'
                );
                return;
            }
            const hasProofFile = sectionKey === 'registered'
                ? this.hasRegisteredProofFile
                : this.hasOfficeProofFile;
            if (hasProofFile) {
                this._toast(
                    'Document already uploaded',
                    'Remove the current document before uploading again.',
                    'warning'
                );
                return;
            }
        } else if (config.documentType) {
            documentType = config.documentType;
            documentName = config.documentName || config.documentType;
            if (sectionKey === 'cin' && this.hasCinFile) {
                this._toast('Document already uploaded', 'Remove the current CIN document before uploading again.', 'warning');
                return;
            }
            if (sectionKey === 'gst' && this.hasGstFile) {
                this._toast('Document already uploaded', 'Remove the current GST document before uploading again.', 'warning');
                return;
            }
        }

        const svc = this.template.querySelector('c-embed-document-checklist');
        if (!svc) {
            this._toast(
                'Upload unavailable',
                'The document upload service did not load. Please refresh the page and try again.',
                'error'
            );
            return;
        }

        try {
            const masterResponse = await this._invokeNonIndividualKycDocApex(
                APEX_METHOD_GET_ENTITY_DOCUMENT_MASTER,
                {
                    documentName: documentName || documentType,
                    documentCategory: config.documentCategory
                }
            );

            let maxFiles = ENTITY_DV_FALLBACK_MAX_FILES;
            let allowedTypes = ENTITY_DV_FALLBACK_FILE_TYPES;
            if (masterResponse?.isSuccess) {
                maxFiles = masterResponse.maxFilesAllowed ?? ENTITY_DV_FALLBACK_MAX_FILES;
                allowedTypes = masterResponse.allowedFileTypes || ENTITY_DV_FALLBACK_FILE_TYPES;
            }

            const result = await svc.getOrCreateChecklist({
                applicationId: this._recordId,
                applicantId: this._applicantId,
                applicantType: null,
                documentType,
                documentName: documentName || documentType,
                documentCategory: config.documentCategory
            });

            const checklistId = result.checklistId;
            if (sectionKey === 'registered' || sectionKey === 'office') {
                await this._stampEntityAddressChecklist(sectionKey, checklistId, documentType);
                if (sectionKey === 'registered') {
                    this._entityRegisteredChecklistId = checklistId;
                } else {
                    this._entityOfficeChecklistId = checklistId;
                }
            }

            this.entityActiveUploadChecklistId = checklistId;
            this.entityActiveMaxFiles = result.maxFilesAllowed ?? maxFiles;
            this.entityActiveAllowedTypes = result.allowedFileTypes || allowedTypes;
            this.entityActiveUploadSectionKey = sectionKey;
            this.entityActiveUploadDocumentType = documentType;
            this.showEntityMagicUpload = true;
        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Could not prepare the document checklist. Please retry.';
            console.error('wheelsIndividualKYCMasterPage: _openEntityAdvancedUpload', error);
            this._toast('Upload Error', msg, 'error');
        }
    }

    handleEntityMagicUploadClose() {
        this.showEntityMagicUpload = false;
    }

    stopPropagationEntityDv(event) {
        event.stopPropagation();
    }

    handleEntityOverlayMouseDown(event) {
        this._entityOverlayMouseDownOnSelf = event.target === event.currentTarget;
    }

    handleEntityOverlayClick(event) {
        if (event.target === event.currentTarget && this._entityOverlayMouseDownOnSelf) {
            this.handleEntityMagicUploadClose();
        }
        this._entityOverlayMouseDownOnSelf = false;
    }

    async handleEntityMagicUploadComplete(event) {
        const files = (event.detail && event.detail.files) || [];
        if (!files.length) {
            this.showEntityMagicUpload = false;
            return;
        }

        const first = files[0];
        let contentDocumentId = first.documentId || first.contentDocumentId || null;
        if (!contentDocumentId && first.contentVersionId) {
            contentDocumentId = await this._resolveContentDocumentIdFromVersion(first.contentVersionId);
        }

        const fileData = {
            fileName: first.fileName || first.name,
            fileSize: first.size,
            contentVersionId: first.contentVersionId,
            contentDocumentId
        };

        const sectionKey = this.entityActiveUploadSectionKey;
        if (sectionKey === 'cin') {
            this._cinChecklistRecordId = this.entityActiveUploadChecklistId || this._cinChecklistRecordId;
            this.cinFieldValues = { ...this.cinFieldValues, cinFile: fileData };
            this._resetCinDetailFields();
            this._trackEntityUploadedDocumentType('CIN Certificate');
        } else if (sectionKey === 'gst') {
            this._gstChecklistRecordId = this.entityActiveUploadChecklistId || this._gstChecklistRecordId;
            this.gstFieldValues = { ...this.gstFieldValues, gstFile: fileData };
            this._resetGstDetailFields();
            this._trackEntityUploadedDocumentType('GST Certificate');
        } else if (sectionKey === 'additional') {
            const documentType = this.entityActiveUploadDocumentType
                || this._entityAdditionalDocumentType
                || '';
            this._entityAdditionalDocuments = [
                ...(this._entityAdditionalDocuments || []),
                {
                    documentType,
                    checklistRecordId: this.entityActiveUploadChecklistId,
                    proofFile: fileData
                }
            ];
            this._trackEntityUploadedDocumentType(documentType);
            this._entityAdditionalDocumentType = '';
        } else if (sectionKey === 'darpan') {
            const documentType = this.entityActiveUploadDocumentType
                || this._darpanDocumentType
                || '';
            const active = this._activeDarpanDocuments().filter(
                (entry) => String(entry?.documentType || '').trim() !== documentType
            );
            this._darpanDocuments = [
                ...active,
                {
                    documentType,
                    checklistRecordId: this.entityActiveUploadChecklistId,
                    proofFile: fileData
                }
            ];
            this._darpanDocumentType = '';
            this._darpanRequiredItems = this._buildLocalDarpanRequiredItems();
        } else if (sectionKey === 'registered') {
            this._entityRegisteredChecklistId = this.entityActiveUploadChecklistId || this._entityRegisteredChecklistId;
            this.registeredAddressFieldValues = {
                ...this.registeredAddressFieldValues,
                proofFile: fileData
            };
            this._trackEntityUploadedDocumentType(this.registeredAddressFieldValues.addressProof);
            await this._stampEntityAddressChecklist(
                'registered',
                this._entityRegisteredChecklistId,
                this.registeredAddressFieldValues.addressProof
            );
        } else if (sectionKey === 'office') {
            this._entityOfficeChecklistId = this.entityActiveUploadChecklistId || this._entityOfficeChecklistId;
            this.officeAddressFieldValues = {
                ...this.officeAddressFieldValues,
                proofFile: fileData
            };
            this._trackEntityUploadedDocumentType(this.officeAddressFieldValues.addressProof);
            await this._stampEntityAddressChecklist(
                'office',
                this._entityOfficeChecklistId,
                this.officeAddressFieldValues.addressProof
            );
        }

        this.entityActiveUploadDocumentType = '';
        this.entityActiveUploadSectionKey = null;
        this.showEntityMagicUpload = false;

        if (sectionKey === 'cin') {
            await this._runEntityDocExtraction('cin', fileData);
        } else if (sectionKey === 'gst') {
            await this._runEntityDocExtraction('gst', fileData);
        }
        await this._refreshEntityDocumentValidation();
    }

    async _stampEntityAddressChecklist(scope, checklistId, addressProof) {
        if (!checklistId || !this._applicantId || this.isReadOnlyScreen) {
            return;
        }
        try {
            await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_STAMP_ENTITY_ADDRESS_CHECKLIST,
                recordId      : this._recordId,
                params        : {
                    applicantId: this._applicantId,
                    checklistRecordId: checklistId,
                    addressType: scope === 'office' ? 'Office Address' : 'Registered Address',
                    addressProof: addressProof || ''
                }
            });
        } catch (error) {
            console.error('wheelsIndividualKYCMasterPage: _stampEntityAddressChecklist', error);
            this._toast(
                'Upload setup failed',
                error?.body?.message || error?.message || 'Could not prepare the address proof checklist.',
                'error'
            );
            throw error;
        }
    }

    _entityDocPanelFilesView(proofFile, checklistRecordId, fallbackId, displayLabel) {
        if (!proofFile) {
            return [];
        }
        const fileLabel = this._fileLabel(proofFile);
        const rowLabel = displayLabel || fileLabel;
        return [{
            id: checklistRecordId || fallbackId,
            name: rowLabel,
            fileName: fileLabel,
            contentVersionId: proofFile.contentVersionId || null,
            contentDocumentId: proofFile.contentDocumentId || null,
            extension: this._fileExtension(proofFile)
        }];
    }

    async _hydrateEntityAddressSectionsFromResponse(entityKyc) {
        this._gstIsRegisteredAddress = entityKyc.gstIsRegisteredAddress || '';
        this._officeSameAsRegistered = entityKyc.officeSameAsRegistered || '';

        this._entityRegisteredChecklistId = entityKyc.registeredChecklistRecordId || null;
        this._entityOfficeChecklistId = entityKyc.officeChecklistRecordId || null;

        if (entityKyc.registeredAddress) {
            await this._applyEntityAddressFromBackend('registered', entityKyc.registeredAddress);
        } else if (this._gstIsRegisteredAddress === 'Yes') {
            this.registeredAddressFieldValues = { ...this._gstAddressFieldSnapshot() };
            await this._ensureEntityLocationOptionsLoaded('registered');
        }

        if (entityKyc.officeAddress) {
            await this._applyEntityAddressFromBackend('office', entityKyc.officeAddress);
        } else if (this._officeSameAsRegistered === 'Yes') {
            this._syncOfficeAddressFromRegistered();
        }
        this._maybeLoadRegisteredLocationOptions();
    }

    async _applyEntityAddressFromBackend(scope, payload) {
        if (!payload || typeof payload !== 'object') return;
        let addressProof = payload.addressProof || '';
        if (!addressProof && payload.proofFile) {
            const storedType = String(payload.storedDocumentType || '').trim();
            if (storedType) {
                addressProof = storedType;
            }
        }
        this._setEntityAddressValues(scope, {
            addressProof,
            proofFile: payload.proofFile || null,
            kycAddressLine1: payload.kycAddressLine1 || '',
            kycAddressLine2: payload.kycAddressLine2 || '',
            state: payload.state || '',
            district: payload.district || '',
            city: payload.city || '',
            kycPinCode: payload.kycPinCode || ''
        });
        await this._ensureEntityLocationOptionsLoaded(scope);
        if (payload.proofFile && addressProof) {
            this._trackEntityUploadedDocumentType(addressProof);
        }
    }

    _syncOfficeAddressFromRegistered() {
        this.officeAddressFieldValues = { ...this.registeredAddressFieldValues };
        this._entityLocOptions = {
            ...this._entityLocOptions,
            office: {
                state: [...this._entityLocOptions.registered.state],
                district: [...this._entityLocOptions.registered.district],
                city: [...this._entityLocOptions.registered.city]
            }
        };
    }

    _applyCinDetailsFromBackend(details) {
        if (!details || typeof details !== 'object') return;
        this.cinFieldValues = {
            ...this.cinFieldValues,
            cinNumber: details.cinNumber || ''
        };
        this._cinNumberOptions = [];
        this._cinApiState = 'success';
    }

    async _applyGstDetailsFromBackend(details) {
        if (!details || typeof details !== 'object') return;
        this.gstFieldValues = {
            ...this.gstFieldValues,
            gstNumber: details.gstNumber || '',
            kycAddressLine1: details.kycAddressLine1 || '',
            kycAddressLine2: details.kycAddressLine2 || '',
            state: details.state || '',
            district: details.district || '',
            city: details.city || '',
            kycPinCode: details.kycPinCode || ''
        };
        this._gstNumberOptions = [];
        this._gstApiState = 'success';
        await this._ensureEntityLocationOptionsLoaded('gst');
    }

    _resetCinDetailFields() {
        this._cinApiState = 'idle';
        this._cinNumberOptions = [];
        this.cinFieldValues = { ...this.cinFieldValues, cinNumber: '' };
    }

    _resetGstDetailFields() {
        this._gstApiState = 'idle';
        this._gstNumberOptions = [];
        this._gstIsRegisteredAddress = '';
        this._officeSameAsRegistered = '';
        this._entityLocOptions = { ...this._entityLocOptions, gst: { state: [], district: [], city: [] } };
        this._gstStateByNumber = {};
        this.registeredAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
        this.officeAddressFieldValues = { ...EMPTY_ENTITY_ADDRESS };
        this._clearEntityLocLevels('registered', ['district']);
        this._clearEntityLocLevels('office', ['district']);
        this.gstFieldValues = {
            gstFile: this.gstFieldValues.gstFile || null,
            gstNumber: '',
            kycAddressLine1: '',
            kycAddressLine2: '',
            state: '',
            district: '',
            city: '',
            kycPinCode: ''
        };
    }

    async _runEntityDocExtraction(docType, fileMeta) {
        if (this.isReadOnlyScreen || !fileMeta) return;
        const isCin = docType === 'cin';
        const versionId = fileMeta.contentVersionId;
        const processedSet = isCin ? this._cinProcessedVersionIds : this._gstProcessedVersionIds;
        if (!versionId || processedSet.has(versionId)) return;

        if (isCin) {
            this._cinApiState = 'loading';
        } else {
            this._gstApiState = 'loading';
        }

        const integrationName = isCin ? INTEGRATION_NAME_PAN_TO_CIN : INTEGRATION_NAME_PAN_TO_GSTN;
        const label = isCin ? 'CIN' : 'GST';

        try {
            const integrationMaster = await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_GET_INTEGRATION_MASTER,
                recordId      : this._recordId,
                params        : { integrationName }
            });
            if (!integrationMaster?.isSuccess) {
                throw new Error(integrationMaster?.message || `${integrationName} integration is not configured.`);
            }
            const componentRef = integrationMaster?.Component_Reference__c;
            if (!componentRef) {
                throw new Error(`${integrationName} integration is not configured.`);
            }

            if (isCin) {
                this._cinExtractionResponse = null;
            } else {
                this._gstExtractionResponse = null;
            }
            await invokeHandler(componentRef, 'onFileUpload', this);

            const response = isCin ? this._cinExtractionResponse : this._gstExtractionResponse;
            if (!response) {
                throw new Error(`${integrationName} lookup did not return a result.`);
            }

            processedSet.add(versionId);
            if (isCin) {
                this._applyCinExtractionResponse(response);
            } else {
                await this._applyGstExtractionResponse(response);
            }
        } catch (error) {
            if (isCin) {
                this._cinApiState = 'failure';
                this._cinNumberOptions = [];
                this.cinFieldValues = { ...this.cinFieldValues, cinNumber: '' };
            } else {
                this._gstApiState = 'failure';
                this._gstNumberOptions = [];
                this._gstStateByNumber = {};
                this.gstFieldValues = {
                    ...this.gstFieldValues,
                    gstNumber: '',
                    kycAddressLine1: '',
                    kycAddressLine2: '',
                    state: '',
                    district: '',
                    city: '',
                    kycPinCode: ''
                };
                await this._ensureEntityLocationOptionsLoaded('gst');
            }
            this._toast(`${label} Extraction`, error?.body?.message || error?.message || 'Extraction failed.', 'error');
        }
    }

    _applyCinExtractionResponse(response) {
        if (!response?.isSuccess) {
            this._cinApiState = 'failure';
            this._cinNumberOptions = [];
            this.cinFieldValues = { ...this.cinFieldValues, cinNumber: '' };
            this._toast('CIN Extraction', response?.message || 'Extraction failed.', 'error');
            return;
        }

        const numbers = Array.isArray(response.cinNumbers) ? response.cinNumbers.filter(Boolean) : [];
        this._cinNumberOptions = numbers.map(n => ({ label: String(n), value: String(n) }));

        if (numbers.length > 1) {
            this.cinFieldValues = { ...this.cinFieldValues, cinNumber: '' };
        } else if (numbers.length === 1) {
            const cinNumber = String(numbers[0]);
            this.cinFieldValues = { ...this.cinFieldValues, cinNumber };
            this._saveNonIndividualKycDocNumber('CIN', cinNumber);
        } else {
            this.cinFieldValues = { ...this.cinFieldValues, cinNumber: '' };
        }
        this._cinApiState = 'success';
    }

    async _applyGstExtractionResponse(response) {
        if (!response?.isSuccess) {
            this._gstApiState = 'failure';
            this._gstNumberOptions = [];
            this._gstStateByNumber = {};
            this.gstFieldValues = {
                ...this.gstFieldValues,
                gstNumber: '',
                kycAddressLine1: '',
                kycAddressLine2: '',
                state: '',
                district: '',
                city: '',
                kycPinCode: ''
            };
            await this._ensureEntityLocationOptionsLoaded('gst');
            this._toast('GST Extraction', response?.message || 'Extraction failed.', 'error');
            return;
        }

        const numbers = Array.isArray(response.gstNumbers) ? response.gstNumbers.filter(Boolean) : [];
        this._gstNumberOptions = numbers.map(n => ({ label: String(n), value: String(n) }));
        this._gstStateByNumber = {};
        const rawStateMap = response.gstStateByNumber || {};
        Object.keys(rawStateMap).forEach((key) => {
            const value = rawStateMap[key];
            if (value) {
                this._gstStateByNumber[String(key)] = String(value);
            }
        });

        const extracted = response.extractedDetails || {};
        const singleGstNumber = numbers.length === 1 ? String(numbers[0]) : '';
        const singleGstState = singleGstNumber
            ? (this._gstStateByNumber[singleGstNumber] || extracted.state || '')
            : '';

        this.gstFieldValues = {
            ...this.gstFieldValues,
            gstNumber: singleGstNumber,
            kycAddressLine1: extracted.kycAddressLine1 || '',
            kycAddressLine2: extracted.kycAddressLine2 || '',
            state: singleGstState,
            district: '',
            city: '',
            kycPinCode: extracted.kycPinCode || ''
        };
        this._gstApiState = 'success';
        await this._ensureEntityLocationOptionsLoaded('gst');
        this._maybeLoadRegisteredLocationOptions();
        this._maybeSyncGstProofAddressSections();
        if (singleGstNumber) {
            await this._saveNonIndividualKycDocNumber('GST', singleGstNumber, singleGstState);
        }
    }

    async _resolveEntityPinCode(scope, pinCode) {
        try {
            const result = await getCityStateFromPinCode({ pinCode });
            const data = result || {};
            const state = data.state || '';
            const city = data.city || '';

            if (scope === 'gst') {
                this.gstFieldValues = {
                    ...this.gstFieldValues,
                    kycPinCode: pinCode,
                    state,
                    district: '',
                    city
                };
            } else {
                const current = this._getEntityAddressValues(scope);
                this._setEntityAddressValues(scope, {
                    ...current,
                    kycPinCode: pinCode,
                    state,
                    district: '',
                    city
                });
                if (scope === 'registered' && this._officeSameAsRegistered === 'Yes') {
                    this._syncOfficeAddressFromRegistered();
                }
            }

            this._clearEntityLocLevels(scope, ['district']);
            if (state) {
                await this._loadLocationOptions(scope, 'district', state, null);
            }

            this._maybeLoadRegisteredLocationOptions();
            this._maybeSyncGstProofAddressSections();
            if (scope === 'registered') {
                this._maybePrepareEntityOfficeSection();
            }
        } catch (error) {
            console.error('wheelsIndividualKYCMasterPage: _resolveEntityPinCode', error);
        }
    }

    async _ensureEntityLocationOptionsLoaded(scope) {
        const values = scope === 'gst'
            ? this.gstFieldValues
            : this._getEntityAddressValues(scope);
        if (values.state) {
            await this._loadLocationOptions(scope, 'district', values.state, null);
        }
    }

    _maybeLoadRegisteredLocationOptions() {
        const state = String(this.registeredAddressFieldValues.state || '').trim();
        if (state) {
            this._loadLocationOptions('registered', 'district', state, null);
        }
    }

    _clearEntityAddressDetailFields(scope) {
        const current = this._getEntityAddressValues(scope);
        this._setEntityAddressValues(scope, {
            ...current,
            kycAddressLine1: '',
            kycAddressLine2: '',
            state: '',
            district: '',
            city: '',
            kycPinCode: ''
        });
        this._clearEntityLocLevels(scope, ['district']);
    }

    _maybePrepareEntityOfficeSection() {
        if (!this.showEntityOfficeAddressSection) {
            return;
        }
        const state = String(this.officeAddressFieldValues.state || '').trim();
        if (state) {
            this._ensureEntityLocationOptionsLoaded('office');
        }
    }

    async _loadLocationOptions(scope, level, state, district) {
        try {
            const response = await savePageData({
                apexClassName : APEX_LOCATION_CLASS,
                apexMethodName: APEX_LOCATION_OPTIONS,
                recordId      : this._recordId,
                params        : { level, state, district }
            });
            if (!response?.isSuccess) return;
            const options = Array.isArray(response.options) ? response.options : [];
            this._setEntityLocOptions(scope, level, options);
        } catch (e) {
            console.error('wheelsIndividualKYCMasterPage: _loadLocationOptions', e);
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 1 – CURRENT ADDRESS KYC
    // ────────────────────────────────────────────────────────────────────────────
    //  Field key                  │ Type      │ Notes
    //  ─────────────────────────  │ ────────  │ ──────────────────────────────────
    //  addrDocumentType           │ picklist  │ ADDR_DOCUMENT_TYPE_OPTIONS
    //  documentSideMode           │ radio     │ Full Upload | Front and Back
    //                             │           │ Hidden when addrDocumentType=Aadhaar
    //  addressProofFile           │ file      │ Visible when sideMode = Full
    //  addressProofFileFront      │ file      │ Visible when sideMode = Side
    //  addressProofFileBack       │ file      │ Visible when sideMode = Side
    //  ckycId                     │ text      │ Optional 14-digit numeric
    @track kycInfoFieldValues = {};

    @track _kycInfoFileUploadRecordId = null;
    @track showCurrentAddressMagicUpload = false;
    @track currentAddressActiveUploadChecklistId = null;
    @track currentAddressActiveMaxFiles = 1;
    @track currentAddressActiveAllowedTypes = ENTITY_DV_FALLBACK_FILE_TYPES;
    @track currentAddressActiveUploadSlot = null;
    _currentAddressOverlayMouseDownOnSelf = false;
    @track _stageIsComplete           = false;

    /**
     * Aadhaar can only be verified in one bucket per applicant. Once verified
     * (or an eKYC link is in-flight) on the Permanent bucket, hide
     * "Aadhaar Card" from the Current bucket's Address Document Type options
     * so the user cannot start a second verification.
     */
    get addrDocumentTypeOptions() {
        const aadhaarLockedByPerm = this._permIsAadhaarVerified || this._permIsAadhaarLinkInFlight;
        if (aadhaarLockedByPerm && this.addrDocumentType !== 'Aadhaar Card') {
            return ADDR_DOCUMENT_TYPE_OPTIONS.filter(o => o.value !== 'Aadhaar Card');
        }
        return ADDR_DOCUMENT_TYPE_OPTIONS;
    }
    get addrDocumentType()        { return this.kycInfoFieldValues.addrDocumentType || ''; }
    get ckycId()                  { return this.kycInfoFieldValues.ckycId || ''; }

    /**
     * The Address Document Type picker locks once any commitment exists for
     * the current choice:
     *   - a file is uploaded
     *   - Aadhaar has been verified
     *   - an Aadhaar eKYC link is in-flight (sent but not yet verified or
     *     expired). Once the link expires (72hr poll detection) or the customer
     *     completes OTP, the lock semantics shift to the appropriate branch.
     * Always locked when the whole stage is read-only.
     */
    get isAddrDocumentTypeReadOnly() {
        if (this.isReadOnlyScreen) return true;
        return this.hasAddressProofFile
            || this.hasAddressProofFileFront
            || this.hasAddressProofFileBack
            || this._isAadhaarVerified
            || this._isAadhaarLinkInFlight;
    }

    // ── POA / POI toggles (Current Address KYC) ──────────────────────────────
    get addressProofToggle()  { return !!this.kycInfoFieldValues.addressProofToggle;  }
    get identityProofToggle() { return !!this.kycInfoFieldValues.identityProofToggle; }

    /**
     * Toggles classify the document (file-uploaded OR Aadhaar-verified) as
     * POA / POI. Surface them once the proof exists for the chosen doc type:
     *   - File-upload path  → after a file is uploaded
     *   - Aadhaar Card path → after eKYC / Biometric verification succeeds
     * In both cases, when POA/POI is true on NEXT, an Applicant_Address__c
     * record is created/updated by KYCDetailsController.
     */
    get showProofToggles() {
        return this.hasAddressProofForVerification;
    }
    get showProofTogglesStandalone() {
        return this.showProofToggles;
    }
    get proofTogglesWrapClass() {
        return this.addrDocumentType === 'Aadhaar Card'
            ? 'kyc-field-wrap kyc-field-wrap-full'
            : 'kyc-field-wrap';
    }

    handleAddressProofToggleChange(event) {
        if (this.isReadOnlyScreen) return;
        this.kycInfoFieldValues = {
            ...this.kycInfoFieldValues,
            addressProofToggle: !!event.target.checked
        };
        this._persistDirtyStateToStorage();
    }
    handleIdentityProofToggleChange(event) {
        if (this.isReadOnlyScreen) return;
        this.kycInfoFieldValues = {
            ...this.kycInfoFieldValues,
            identityProofToggle: !!event.target.checked
        };
        this._persistDirtyStateToStorage();
    }

    // ── Aadhaar / Others Verification (shared state) ─────────────────────────
    // Aadhaar Card surfaces a 3-tile visual picker; Others surfaces a 2-option
    // dropdown (Video KYC / Digi Locker). Both write into _aadhaarVerificationType
    // and reuse the same verify dispatcher + _isAadhaarVerified completion flag.
    @track _aadhaarVerificationType = '';
    @track _isAadhaarVerified       = false;
    // True when an eKYC OTP link has been generated and the customer has not
    // yet completed (or the link has not yet expired). 
    @track _isAadhaarLinkInFlight   = false;
    // Surfaced banner when the 72hr link has expired without verification.
    @track _aadhaarLinkExpired      = false;

    get showAadhaarVerificationPicker() {
        return this.addrDocumentType === 'Aadhaar Card';
    }
    get aadhaarVerificationType() { return this._aadhaarVerificationType; }
    get isAadhaarVerified()        { return this._isAadhaarVerified; }
    get aadhaarLinkExpired()       { return this._aadhaarLinkExpired; }
    get showAadhaarExpiredBanner() {
        return this._aadhaarLinkExpired && !this._isAadhaarVerified;
    }

    get aadhaarVerificationTiles() {
        const locked = this._isAadhaarVerified
            || this.isReadOnlyScreen
            || this._isAadhaarLinkInFlight;

        const ekycInFlight = this._isAadhaarLinkInFlight && !this._isAadhaarVerified;
        return AADHAAR_VERIFICATION_METHODS.map(m => {
            const isSelected       = m.id === this._aadhaarVerificationType;
            const showVerifiedPill = isSelected && this._isAadhaarVerified;
            const showInfoIcon     = isSelected && m.id === 'eKYC_OTP' && ekycInFlight;
 
            const showCheck        = isSelected && !showVerifiedPill;
            const tileClass = 'kyc-aadhaar-tile'
                + (isSelected ? ' kyc-aadhaar-tile-selected' : '')
                + (locked ? ' kyc-aadhaar-tile-locked' : '');
            return {
                ...m,
                isSelected,
                tileClass,
                ariaPressed: isSelected ? 'true' : 'false',
                showCheck,
                showInfoIcon,
                showVerifiedPill,
                infoTooltip: showInfoIcon
                    ? 'eKYC OTP Verification in progress. Click "View eKYC Link" for status.'
                    : ''
            };
        });
    }

    /**
     * Click-trap on the tile-corner info icon. 
     */
    handleTileInfoClick(event) {
        event.stopPropagation();
        event.preventDefault();
    }
    handleTileInfoKeydown(event) {
        // Keep the icon focused so the tooltip stays visible on Enter/Space.
        if (event.key === 'Enter' || event.key === ' ') {
            event.stopPropagation();
        }
    }

    get aadhaarVerifyDisabled() {
        return !this._aadhaarVerificationType
            || this._isAadhaarVerified
            || this.isReadOnlyScreen;
    }
    get aadhaarVerifyButtonClass() {
        return 'kyc-aadhaar-verify-btn'
            + (this.aadhaarVerifyDisabled ? ' kyc-aadhaar-verify-btn-disabled' : '');
    }
    get aadhaarVerifyButtonLabel() {
        const isOthers = this.addrDocumentType === 'Others';
        if (this._isAadhaarVerified)     return isOthers ? 'Verified' : 'Aadhaar Verified';
        if (this._isAadhaarLinkInFlight) return 'View eKYC Link';
        return isOthers ? 'Verify' : 'Verify Aadhaar';
    }

    // ── Others Verification (dropdown) ───────────────────────────────────────
    get showOtherVerificationPicker() {
        return this.addrDocumentType === 'Others';
    }
    get otherVerificationMethodOptions() { return OTHER_VERIFICATION_METHOD_OPTIONS; }
    get otherVerificationMethod()        { return this._aadhaarVerificationType || ''; }
    get isOtherVerificationDisabled() {
        return this.isReadOnlyScreen
            || this._isAadhaarVerified
            || this._isAadhaarLinkInFlight;
    }

    handleOtherVerificationMethodChange(event) {
        if (this.isOtherVerificationDisabled) return;
        this._aadhaarVerificationType = event.detail?.value || '';
    }

    handleAadhaarMethodSelect(event) {
        // Tiles are locked once verified or while a link is in flight.
        if (this.isReadOnlyScreen
            || this._isAadhaarVerified
            || this._isAadhaarLinkInFlight) return;
        const methodId = event.currentTarget?.dataset?.methodId || '';
        if (!methodId) return;
        this._aadhaarVerificationType = methodId;
    }

    // The eKYC OTP path is REAL (Site URL + customer
    // VF page + polling for AadhaarConsentReceived__c); 
    async handleAadhaarVerifyClick() {
        if (this.aadhaarVerifyDisabled) return;

        const method  = this._aadhaarVerificationType;
        const action  = AADHAAR_METHOD_TO_ACTION[method];
        if (!action) return;

        // If an eKYC link is already outstanding (in flight, not expired),
        // just re-open the modal — don't regenerate / restart polling.
        if (action === APEX_AADHAAR_INIT_EKYC_OTP
            && this._isAadhaarLinkInFlight
            && this._eKycLinkUrl) {
            this.showEkycLinkModal = true;
            if (!this._isPollingConsent) this._startConsentPolling();
            return;
        }

        if (!this._kycInfoFileUploadRecordId) {
            await this._ensureCurrentAddressChecklist();
        }
        if (!this._kycInfoFileUploadRecordId) {
            this._toast('Aadhaar Verification', 'Could not initialise Current address record. Please retry.', 'error');
            return;
        }

        this._beginAadhaarProgress(method);

        try {
            const response = await savePageData({
                apexClassName : APEX_AADHAAR_CLASS,
                apexMethodName: action,
                recordId      : this._recordId,
                params        : {
                    applicantId       : this._applicantId || null,
                    checklistRecordId : this._kycInfoFileUploadRecordId || null,
                    addressType       : ADDR_TYPE_CURRENT
                }
            });
            if (!response?.isSuccess) {
                this._failAadhaarProgress(response?.message || 'Aadhaar verification failed.');
                return;
            }

            if (action === APEX_AADHAAR_INIT_EKYC_OTP) {
                // eKYC OTP path — show the customer-facing link and start
                // polling. We only flip _isAadhaarVerified when the customer
                // completes the consent step on the VF page.
                //
                // The in-flight lock prevents the user from
                // switching Address Document Type or Aadhaar method until the
                // customer completes OR the link expires (72hr).
                this._eKycLinkUrl       = response.kycUrl || '';
                this._eKycLinkCopied    = false;
                this._aadhaarLinkExpired = false;
                this._isAadhaarLinkInFlight = true;
                // Walk the progress modal through each API stage with paced
                await this._walkAadhaarProgressToSuccess();
                this.showEkycLinkModal  = true;
                if (response.aadhaarVerified === true) {
                    await this._handleAadhaarConsentReceived();
                } else {
                    this._startConsentPolling();
                }
            } else {
                // Stub methods — mark verified immediately and surface the
                // extracted-details panel for manual edit 
                this._completeAadhaarVerification();
            }
        } catch (err) {
            this._failAadhaarProgress(err?.message || 'Aadhaar verification failed.');
        }
    }

    _beginAadhaarProgress(method) {
        this.showIntegrationProgressModal            = true;
        this.integrationProgressModalStatus          = 'loading';
        this.integrationProgressModalHeader          = 'Aadhaar Verification';
        this.integrationProgressModalStages          = method === 'eKYC_OTP'
            ? ['GENERATE OTP API', 'SMS GATEWAY CALL API']
            : AADHAAR_STUB_STAGES;
        this.integrationProgressModalCurrentStageIdx = 0;
        this.integrationProgressModalErrorMessage    = '';
    }

    _failAadhaarProgress(message) {
        this.integrationProgressModalStatus       = 'error';
        this.integrationProgressModalErrorMessage = message;
    }

    /**
     * Thin parent-side adapter. The actual stage walkthrough + success-hold
     * pacing lives on c-integration-progress-modal as the generic
     * runProgress() API (default 300ms per stage, 700ms hold on all-green
     * ticks), so the exact same flow can be reused by Mobile / Email OTP
     * verify and any other integration-popup screen without copy-pasting
     * orchestration code.
     *
     * We still own the modal's open/close state on the parent.
     */
    async _walkAadhaarProgressToSuccess() {
        const modal = this.template.querySelector('c-integration-progress-modal');
        if (modal && typeof modal.runProgress === 'function') {
            await modal.runProgress({ stages: this.integrationProgressModalStages });
        }
        this._hideProgress();
    }

    async _handleAadhaarConsentReceived() {
        this._stopConsentPolling();
        this._isAadhaarLinkInFlight = false;
        this._aadhaarLinkExpired    = false;
        this.showEkycLinkModal      = false;
        // Cosmetic progress visualization driven by extractUIDAIOTPAPI LWC.
        await invokeHandler('extractUIDAIOTPAPI', 'onOtpVerified', this);
        // Force reload — pulls the freshly seeded Applicant_KYC__c snapshot
        // into currentExtractedDetails so the user sees populated address fields.
        await this._loadPageData(true);
        this._completeAadhaarVerification();
    }

    /**
     * Called when the poll detects the 72hr eKYC link has expired without
     * verification. Unlocks the Address Document Type + Aadhaar method picker
     */
    _handleAadhaarLinkExpired() {
        this._stopConsentPolling();
        this._isAadhaarLinkInFlight = false;
        this._aadhaarLinkExpired    = true;
        this._isAadhaarVerified     = false;
        this._eKycLinkUrl           = '';
        this.showEkycLinkModal      = false;
        // Show a brief error flash on the integration modal if it's still up.
        if (this.showIntegrationProgressModal) {
            this._failAadhaarProgress('Aadhaar eKYC link expired. Please request a new link.');
            setTimeout(() => this._hideProgress(), 1500);
        }
    }

    _applyAadhaarVerifyState(state) {
        this._aadhaarVerificationType = '';
        this._isAadhaarVerified = false;
        this._isAadhaarLinkInFlight = false;
        this._aadhaarLinkExpired = false;
        this._eKycLinkUrl = '';
        this._eKycLinkCopied = false;
        this.showEkycLinkModal = false;
        if (!state) return;
        const methodLabelToTileId = {
            'eKYC OTP Verification' : 'eKYC_OTP',
            'Biometric Verification': 'Biometric',
            'Video KYC Verification': 'VideoKYC',
            'Digilocker Verification': 'Digilocker',
            'Offline Aadhaar XML'   : 'OfflineXML'
        };
        if (state.verificationMethod && methodLabelToTileId[state.verificationMethod]) {
            this._aadhaarVerificationType = methodLabelToTileId[state.verificationMethod];
        }
        this._aadhaarLinkExpired   = state.linkExpired === true;
        // Aadhar_Verified__c is the authoritative complete signal.
        // consentReceivedDate is just an audit timestamp on the same record.
        if (state.aadhaarVerified === true) {
            this._isAadhaarVerified     = true;
            this._isAadhaarLinkInFlight = false;
            return;
        }
        if (state.linkSent === true && state.kycUrl) {
            this._eKycLinkUrl           = state.kycUrl;
            this._isAadhaarLinkInFlight = true;
            // Auto-resume background polling. Modal stays closed until the
            // user reclicks Verify (button label flips to "View eKYC Link").
            this._startConsentPolling();
        }
    }

    _completeAadhaarVerification() {
        this._isAadhaarVerified = true;
        if (!this.currentExtractedDetails) {
            this.currentExtractedDetails = { kycType: 'Aadhar' };
        }
        this._applyDefaultProofTogglesIfUnset();
        // Quick success flash on the integration modal if it's still up.
        if (this.showIntegrationProgressModal) {
            this.integrationProgressModalStatus = 'success';
            setTimeout(() => this._hideProgress(), 800);
        }
    }

    // ── eKYC OTP polling ──────────────────────────────────────────────────────
    @track showEkycLinkModal = false;
    @track _eKycLinkUrl      = '';
    @track _eKycLinkCopied   = false;
    @track _isPollingConsent = false;
    @track _pollingAttempts  = 0;
    _consentPollHandle       = null;

    get eKycLinkUrl() { return this._eKycLinkUrl; }
    get isPollingConsent() { return this._isPollingConsent; }
    get pollingStatusLabel() {
        if (!this._isPollingConsent) return '';
        return 'Waiting for customer to complete Aadhaar verification…';
    }
    get copyLinkButtonLabel() { return this._eKycLinkCopied ? 'Link Copied' : 'Copy Link'; }
    get copyLinkButtonIcon()  { return this._eKycLinkCopied ? 'utility:check' : 'utility:copy'; }

    _startConsentPolling() {
        this._stopConsentPolling();
        if (!this._applicantId) return;
        this._isPollingConsent = true;
        this._pollingAttempts  = 0;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._consentPollHandle = setInterval(() => this._pollConsent(), EKYC_POLL_INTERVAL_MS);
    }

    _stopConsentPolling() {
        if (this._consentPollHandle) {
            clearInterval(this._consentPollHandle);
            this._consentPollHandle = null;
        }
        this._isPollingConsent = false;
    }

    async _pollConsent() {
        if (!this._applicantId) {
            this._stopConsentPolling();
            return;
        }
        this._pollingAttempts += 1;
        if (this._pollingAttempts > EKYC_POLL_MAX_ATTEMPTS) {
            this._stopConsentPolling();
            return;
        }
        try {
            const response = await savePageData({
                apexClassName : APEX_AADHAAR_CLASS,
                apexMethodName: APEX_AADHAAR_POLL_CONSENT,
                recordId      : this._recordId,
                params        : {
                    applicantId       : this._applicantId,
                    checklistRecordId : this._kycInfoFileUploadRecordId || null,
                    addressType       : ADDR_TYPE_CURRENT
                }
            });
            if (!response?.isSuccess) return;
            // 72hr link expiry detection — Apex clears link state when it
            // detects the expiry; LWC unlocks doc type + verification picker.
            if (response.linkExpired === true) {
                this._handleAadhaarLinkExpired();
                return;
            }

            if (response.aadhaarVerified === true) {
                await this._handleAadhaarConsentReceived();
            }
        } catch (e) {

        }
    }

    handleCheckConsentStatus() {
        this._pollConsent();
    }

    handleCopyEkycLink() {
        const url = this._eKycLinkUrl;
        if (!url) return;
        const dispatch = (ok) => {
            this._eKycLinkCopied = ok;
            if (ok) setTimeout(() => { this._eKycLinkCopied = false; }, 2500);
        };
        if (navigator?.clipboard?.writeText) {
            navigator.clipboard.writeText(url).then(() => dispatch(true)).catch(() => dispatch(false));
        } else {
            // Fallback for older browsers.
            try {
                const ta = document.createElement('textarea');
                ta.value = url;
                ta.style.position = 'fixed';
                ta.style.left = '-9999px';
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
                dispatch(true);
            } catch (e) {
                dispatch(false);
            }
        }
    }

    handleCloseEkycLinkModal() {
        this.showEkycLinkModal = false;
    }

    disconnectedCallback() {
        if (this._menuSelectHandler) {
            window.removeEventListener(LOS_MENU_SELECT_EVENT, this._menuSelectHandler);
            this._menuSelectHandler = null;
        }
        this._stopConsentPolling();
        this._stopPermConsentPolling();
        if (this._dynamicModalHandler) {
            this.removeEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
            this._dynamicModalHandler = null;
        }
        if (this._integrationProgressHandler) {
            window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
            this._integrationProgressHandler = null;
        }
    }

    /**
     * Defaults POA + POI toggles to TRUE when not yet set. Preserves any
     * saved values already loaded from Applicant_Address__c.
     */
    _applyDefaultProofTogglesIfUnset() {
        const v = this.kycInfoFieldValues || {};
        const updates = {};
        if (v.addressProofToggle === undefined || v.addressProofToggle === null) {
            updates.addressProofToggle = true;
        }
        if (v.identityProofToggle === undefined || v.identityProofToggle === null) {
            updates.identityProofToggle = true;
        }
        if (Object.keys(updates).length > 0) {
            this.kycInfoFieldValues = { ...this.kycInfoFieldValues, ...updates };
  
            this._persistDirtyStateToStorage();
        }
    }

    get documentSideMode()         { return this.kycInfoFieldValues.documentSideMode || SIDE_MODE_FULL; }
    get isSideModeFull()           { return this.documentSideMode === SIDE_MODE_FULL; }
    get isSideModeSide()           { return this.documentSideMode === SIDE_MODE_SIDE; }
    get showDocumentSideMode() {
        return !!this.addrDocumentType && !VERIFICATION_ONLY_DOC_TYPES.has(this.addrDocumentType);
    }

    get addressProofFileElement()       { return this.kycInfoFieldValues.addressProofFile      || null; }
    get addressProofFileFrontElement()  { return this.kycInfoFieldValues.addressProofFileFront || null; }
    get addressProofFileBackElement()   { return this.kycInfoFieldValues.addressProofFileBack  || null; }

    get hasAddressProofFile()           { return !!this.addressProofFileName; }
    get hasAddressProofFileFront()      { return !!this.addressProofFileFrontName; }
    get hasAddressProofFileBack()       { return !!this.addressProofFileBackName; }
    get noAddressProofFile()            { return !this.hasAddressProofFile; }
    get noAddressProofFileFront()       { return !this.hasAddressProofFileFront; }
    get noAddressProofFileBack()        { return !this.hasAddressProofFileBack; }

    get showAddressProofUpload() {
        // File upload visible only for OCR-supported physical docs.
        // Aadhaar Card (visual picker) and Others (verification dropdown) have no file upload.
        if (!this.addrDocumentType) return false;
        if (VERIFICATION_ONLY_DOC_TYPES.has(this.addrDocumentType)) return false;
        return this.isSideModeFull;
    }
    get showAddressProofUploadSide() {
        return !!this.addrDocumentType
            && !VERIFICATION_ONLY_DOC_TYPES.has(this.addrDocumentType)
            && this.isSideModeSide;
    }
    get showCurrentDocsRightColumn() {
        return this.showAddressProofUpload || this.showAddressProofUploadSide;
    }
    get currentAddressDocsLayoutClass() {
        return this.showCurrentDocsRightColumn
            ? 'kyc-docs-two-col kyc-docs-two-col--dynamic kyc-docs-two-col--split'
            : 'kyc-docs-two-col kyc-docs-two-col--dynamic';
    }

    get addressProofFileName()      { return this._fileLabel(this.addressProofFileElement); }
    get addressProofFileFrontName() { return this._fileLabel(this.addressProofFileFrontElement); }
    get addressProofFileBackName()  { return this._fileLabel(this.addressProofFileBackElement); }

    get addressProofContentDocumentId()      { return this._fileContentDocumentId(this.addressProofFileElement); }
    get addressProofFrontContentDocumentId() { return this._fileContentDocumentId(this.addressProofFileFrontElement); }
    get addressProofBackContentDocumentId()  { return this._fileContentDocumentId(this.addressProofFileBackElement); }

    get addressProofFileType()      { return this._fileExtension(this.addressProofFileElement); }
    get addressProofFrontFileType() { return this._fileExtension(this.addressProofFileFrontElement); }
    get addressProofBackFileType()  { return this._fileExtension(this.addressProofFileBackElement); }
    get addressProofPanelUploadDisabled()      { return this.isReadOnlyScreen || this.hasAddressProofFile; }
    get addressProofFrontPanelUploadDisabled() { return this.isReadOnlyScreen || this.hasAddressProofFileFront; }
    get addressProofBackPanelUploadDisabled()  { return this.isReadOnlyScreen || this.hasAddressProofFileBack; }
    get addressProofPanelFiles() {
        return this._entityDocPanelFilesView(
            this.addressProofFileElement,
            this._kycInfoFileUploadRecordId,
            'current-address-proof',
            'Upload Address Proof'
        );
    }
    get addressProofFrontPanelFiles() {
        return this._entityDocPanelFilesView(
            this.addressProofFileFrontElement,
            this._kycInfoFileUploadRecordId,
            'current-address-proof-front',
            'Upload Front'
        );
    }
    get addressProofBackPanelFiles() {
        return this._entityDocPanelFilesView(
            this.addressProofFileBackElement,
            this._kycInfoFileUploadRecordId,
            'current-address-proof-back',
            'Upload Back'
        );
    }

    get kycInfoFileUploadRecordId() { return this._kycInfoFileUploadRecordId; }
    get fileUploadDisabled()        { return !this._kycInfoFileUploadRecordId || this.isReadOnlyScreen; }

    get fileUploadPreparing()       { return !this.isReadOnlyScreen && !this._kycInfoFileUploadRecordId; }

    get sideModeFullClass() {
        return 'kyc-radio-label' + (this.isSideModeFull ? ' kyc-radio-label-checked' : '');
    }
    get sideModeSideClass() {
        return 'kyc-radio-label' + (this.isSideModeSide ? ' kyc-radio-label-checked' : '');
    }

    handleAddrDocumentTypeChange(event) {
        if (this.isReadOnlyScreen) return;
        const selected = event.target.value || '';
        const previous = this.kycInfoFieldValues.addrDocumentType || '';

        const isVerificationOnly = VERIFICATION_ONLY_DOC_TYPES.has(selected);
        const next = {
            ...this.kycInfoFieldValues,
            addrDocumentType: selected,
            documentSideMode: isVerificationOnly ? SIDE_MODE_FULL : (this.kycInfoFieldValues.documentSideMode || SIDE_MODE_FULL)
        };
        this.kycInfoFieldValues = next;

        // Switching doc type invalidates the prior OCR; reset so the next
        // upload re-extracts cleanly. Reset shared verification state whenever
        // the user moves off the previous verification-only path (Aadhaar/Others)
        // — the chosen method is owned by that path and must not leak across.
        if (selected !== previous) {
            this.currentExtractedDetails = null;
            this._processedVersionIds = new Set();
            if (VERIFICATION_ONLY_DOC_TYPES.has(previous)) {
                this._aadhaarVerificationType = '';
                this._isAadhaarVerified       = false;
                this._isAadhaarLinkInFlight   = false;
                this._aadhaarLinkExpired      = false;
                this._eKycLinkUrl             = '';
                this._stopConsentPolling();
            }
        }

    }

    handleDocumentSideModeChange(event) {
        if (this.isReadOnlyScreen) return;
        const value = event.target.value;
        // When mode flips, clear the other-mode files so stale state doesn't render.
        const cleared = (value === SIDE_MODE_SIDE)
            ? { addressProofFile: null }
            : { addressProofFileFront: null, addressProofFileBack: null };
        this.kycInfoFieldValues = {
            ...this.kycInfoFieldValues,
            documentSideMode: value,
            ...cleared
        };
    }

    handleCkycIdChange(event) {
        if (this.isReadOnlyScreen) return;
        const raw = event.target.value || '';
        const digitsOnly = raw.replace(/\D+/g, '').slice(0, CKYC_DIGIT_LIMIT);
        this.kycInfoFieldValues = { ...this.kycInfoFieldValues, ckycId: digitsOnly };
        if (raw !== digitsOnly) {
            event.target.value = digitsOnly;
        }
    }

    async handleAddressProofUploadRequest() {
        await this._openCurrentAddressAdvancedUpload('full');
    }
    async handleAddressProofFrontUploadRequest() {
        await this._openCurrentAddressAdvancedUpload('front');
    }
    async handleAddressProofBackUploadRequest() {
        await this._openCurrentAddressAdvancedUpload('back');
    }

    async _openCurrentAddressAdvancedUpload(slot) {
        if (this.isReadOnlyScreen) return;
        const normalizedSlot = this._normalizeCurrentAddressUploadSlot(slot);
        if (normalizedSlot === 'front' && this.hasAddressProofFileFront) {
            this._toast('Document already uploaded', 'Remove the current front file before uploading again.', 'warning');
            return;
        }
        if (normalizedSlot === 'back' && this.hasAddressProofFileBack) {
            this._toast('Document already uploaded', 'Remove the current back file before uploading again.', 'warning');
            return;
        }
        if (normalizedSlot === 'full' && this.hasAddressProofFile) {
            this._toast('Document already uploaded', 'Remove the current address proof file before uploading again.', 'warning');
            return;
        }

        const checklistId = await this._ensureCurrentAddressChecklist();
        if (!checklistId) {
            this._toast('Current Address', 'Could not prepare upload. Please retry.', 'error');
            return;
        }
        this.currentAddressActiveUploadSlot = normalizedSlot;
        this.currentAddressActiveUploadChecklistId = checklistId;
        this.currentAddressActiveMaxFiles = 1;
        this.currentAddressActiveAllowedTypes = ENTITY_DV_FALLBACK_FILE_TYPES;
        this.showCurrentAddressMagicUpload = true;
    }

    handleCurrentAddressMagicUploadClose() {
        this._resetCurrentAddressMagicUploadState();
    }

    stopPropagationCurrentAddressDv(event) {
        event.stopPropagation();
    }

    handleCurrentAddressOverlayMouseDown(event) {
        this._currentAddressOverlayMouseDownOnSelf = event.target === event.currentTarget;
    }

    handleCurrentAddressOverlayClick(event) {
        if (event.target === event.currentTarget && this._currentAddressOverlayMouseDownOnSelf) {
            this._resetCurrentAddressMagicUploadState();
        }
        this._currentAddressOverlayMouseDownOnSelf = false;
    }

    async handleCurrentAddressMagicUploadComplete(event) {
        const files = (event.detail && event.detail.files) || [];
        const slot = this._normalizeCurrentAddressUploadSlot(this.currentAddressActiveUploadSlot);
        this._resetCurrentAddressMagicUploadState();
        if (!files.length) return;

        const first = files[0];
        let contentDocumentId = first.documentId || first.contentDocumentId || null;
        if (!contentDocumentId && first.contentVersionId) {
            contentDocumentId = await this._resolveContentDocumentIdFromVersion(first.contentVersionId);
        }
        const fileData = {
            fileName: first.fileName || first.name || 'File attached',
            fileSize: first.size,
            contentVersionId: first.contentVersionId || null,
            contentDocumentId
        };

        if (slot === 'front') {
            this.kycInfoFieldValues = { ...this.kycInfoFieldValues, addressProofFileFront: fileData };
            this._runOcrExtraction('Front', fileData);
            return;
        }
        if (slot === 'back') {
            this.kycInfoFieldValues = { ...this.kycInfoFieldValues, addressProofFileBack: fileData };
            this._runOcrExtraction('Back', fileData);
            return;
        }
        this.kycInfoFieldValues = { ...this.kycInfoFieldValues, addressProofFile: fileData };
        this._runOcrExtraction('Full', fileData);
    }

    async handleCurrentAddressPanelFilePreview(event) {
        const detail = event.detail || {};
        const slot = this._normalizeCurrentAddressUploadSlot(detail.sectionKey);
        const fileElement = slot === 'front'
            ? this.addressProofFileFrontElement
            : slot === 'back'
                ? this.addressProofFileBackElement
                : this.addressProofFileElement;
        const fallbackFileName = slot === 'front'
            ? 'Upload Front'
            : slot === 'back'
                ? 'Upload Back'
                : 'Upload Address Proof';
        const contentVersionId = detail.contentVersionId || fileElement?.contentVersionId || null;
        const fileName = detail.fileName || this._fileLabel(fileElement) || fallbackFileName;
        const fileExtension =
            detail.fileType
            || this._fileExtension(fileElement)
            || this._fileExtension({ fileName })
            || '';

        if (contentVersionId) {
            this.entityPreviewContentVersionId = contentVersionId;
            this.entityPreviewFileName = fileName;
            this.entityPreviewFileExtension = fileExtension;
            this.showEntityEmbedFilePreview = true;
            return;
        }

        let contentDocumentId = detail.contentDocumentId || this._fileContentDocumentId(fileElement) || null;
        if (!contentDocumentId && fileElement?.contentVersionId) {
            contentDocumentId = await this._resolveContentDocumentIdFromVersion(fileElement.contentVersionId);
        }
        if (!contentDocumentId) return;
        this.previewContentDocumentId = contentDocumentId;
        this.previewFileType = fileExtension || null;
        this.showFilePreviewer = true;
    }

    handleCurrentAddressPanelFileDelete(event) {
        const slot = this._normalizeCurrentAddressUploadSlot(event?.detail?.sectionKey);
        if (slot === 'front') {
            this.handleAddressProofFrontRemove();
            return;
        }
        if (slot === 'back') {
            this.handleAddressProofBackRemove();
            return;
        }
        this.handleAddressProofRemove();
    }

    _normalizeCurrentAddressUploadSlot(slot) {
        if (slot === 'front' || slot === 'addressProofFront') return 'front';
        if (slot === 'back' || slot === 'addressProofBack') return 'back';
        return 'full';
    }

    _resetCurrentAddressMagicUploadState() {
        this.showCurrentAddressMagicUpload = false;
        this.currentAddressActiveUploadChecklistId = null;
        this.currentAddressActiveMaxFiles = 1;
        this.currentAddressActiveAllowedTypes = ENTITY_DV_FALLBACK_FILE_TYPES;
        this.currentAddressActiveUploadSlot = null;
        this._currentAddressOverlayMouseDownOnSelf = false;
    }

    handleAddressProofRemove() {
        if (this.isReadOnlyScreen) return;
        const removed = this.kycInfoFieldValues.addressProofFile;
        this.kycInfoFieldValues = { ...this.kycInfoFieldValues, addressProofFile: null };
        this._resetExtractedStateAfterFileRemoval(removed);
    }
    handleAddressProofFrontRemove() {
        if (this.isReadOnlyScreen) return;
        const removed = this.kycInfoFieldValues.addressProofFileFront;
        this.kycInfoFieldValues = { ...this.kycInfoFieldValues, addressProofFileFront: null };
        this._resetExtractedStateAfterFileRemoval(removed);
    }
    handleAddressProofBackRemove() {
        if (this.isReadOnlyScreen) return;
        const removed = this.kycInfoFieldValues.addressProofFileBack;
        this.kycInfoFieldValues = { ...this.kycInfoFieldValues, addressProofFileBack: null };
        this._resetExtractedStateAfterFileRemoval(removed);
    }

    /**
     * Common cleanup when any file is removed:
     *   1. Fire the server-side delete callout.
     *   2. Clear the in-memory extracted-details panel only when ALL files
     *      for this checklist row are gone
     *   3. Re-open the Address Document Type picker
     */
    _resetExtractedStateAfterFileRemoval(removedFile) {
        // (1) Server-side cleanup — fire-and-forget. The local state has
        // already been cleared so the UI is responsive even if the call lags.
        if (this._kycInfoFileUploadRecordId && removedFile) {
            this._dispatchServerSideFileDelete(removedFile);
        }
        // (2) Defer the in-memory wipe until every file is gone.
        if (this.hasAddressProofFile || this.hasAddressProofFileFront || this.hasAddressProofFileBack) {
            return;
        }
        this.currentExtractedDetails = null;
        this._processedVersionIds    = new Set();

        this.kycInfoFieldValues = {
            ...this.kycInfoFieldValues,
            addressProofToggle  : null,
            identityProofToggle : null
        };
        this._clearDirtyStateFromStorage();
    }

    _dispatchServerSideFileDelete(fileMeta) {
        savePageData({
            apexClassName : APEX_CLASS,
            apexMethodName: APEX_METHOD_DELETE_FILE,
            recordId      : this._recordId,
            params        : {
                checklistRecordId : this._kycInfoFileUploadRecordId,
                contentDocumentId : fileMeta.contentDocumentId || null,
                contentVersionId  : fileMeta.contentVersionId  || null,
                applicantId       : this._applicantId || null
            }
        }).catch(err => {
            console.error('wheelsIndividualKYCMasterPage: deleteCurrentAddressKycFile', err);
        });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 2 – ADDRESS VERIFICATION
    // ────────────────────────────────────────────────────────────────────────────
    // Visible when: addrDocumentType AND addressProofFile both have values.
    //
    //  Field key                        │ Type  │ Options
    // ──────────────────────────────────┼───────┼─────────
    //  isCurrentAddrSameAsPermanent     │ radio │ Yes / No
    //  isOfficeAddrSameAsCurrent        │ radio │ Yes / No
    // ──────────────────────────────────┴───────┴─────────
    @track addressVerificationFieldValues = {};

    get isCurrentAddrSameAsPermanent()    { return this.addressVerificationFieldValues.isCurrentAddrSameAsPermanent || ''; }
    get isOfficeAddrSameAsCurrent()       { return this.addressVerificationFieldValues.isOfficeAddrSameAsCurrent    || ''; }
    get isCurrentAddrSameAsPermanentYes() { return this.isCurrentAddrSameAsPermanent === 'Yes'; }
    get isCurrentAddrSameAsPermanentNo()  { return this.isCurrentAddrSameAsPermanent === 'No';  }
    get isOfficeAddrSameAsCurrentYes()    { return this.isOfficeAddrSameAsCurrent    === 'Yes'; }
    get isOfficeAddrSameAsCurrentNo()     { return this.isOfficeAddrSameAsCurrent    === 'No';  }

    handleIsCurrentAddrSameAsPermanentChange(event) {
        if (this.isReadOnlyScreen) return;
        const value = event.target.value;
        this.addressVerificationFieldValues = { ...this.addressVerificationFieldValues, isCurrentAddrSameAsPermanent: value };
        this._persistDirtyStateToStorage();
    }
    handleIsOfficeAddrSameAsCurrentChange(event) {
        if (this.isReadOnlyScreen) return;
        const value = event.target.value;
        this.addressVerificationFieldValues = { ...this.addressVerificationFieldValues, isOfficeAddrSameAsCurrent: value };
        this._persistDirtyStateToStorage();

        if (value === 'No' && this.isOfficeAddressRequired && !this._officeChecklistId) {
            this._ensureOfficeChecklist();
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 3 – DIRECTOR DECLARATION
    // ────────────────────────────────────────────────────────────────────────────
    // Visible when: isCurrentAddrSameAsPermanent AND isOfficeAddrSameAsCurrent
    //               both have values.
    //
    //  Field key                  │ Type  │ Options
    // ────────────────────────────┼───────┼─────────
    //  isDirectorDeclaration      │ radio │ Yes / No
    //  isSeniorOfficerRelative    │ radio │ Yes / No
    // ────────────────────────────┴───────┴─────────
    @track directorDeclarationFieldValues = {};

    get isDirectorDeclaration()       { return this.directorDeclarationFieldValues.isDirectorDeclaration    || ''; }
    get isSeniorOfficerRelative()     { return this.directorDeclarationFieldValues.isSeniorOfficerRelative  || ''; }
    get isDirectorDeclarationYes()    { return this.isDirectorDeclaration    === 'Yes'; }
    get isDirectorDeclarationNo()     { return this.isDirectorDeclaration    === 'No';  }
    get isSeniorOfficerRelativeYes()  { return this.isSeniorOfficerRelative  === 'Yes'; }
    get isSeniorOfficerRelativeNo()   { return this.isSeniorOfficerRelative  === 'No';  }

    handleIsDirectorDeclarationChange(event) {
        if (this.isReadOnlyScreen) return;
        this.directorDeclarationFieldValues = { ...this.directorDeclarationFieldValues, isDirectorDeclaration: event.target.value };
        this._persistDirtyStateToStorage();
    }
    handleIsSeniorOfficerRelativeChange(event) {
        if (this.isReadOnlyScreen) return;
        this.directorDeclarationFieldValues = { ...this.directorDeclarationFieldValues, isSeniorOfficerRelative: event.target.value };
        this._persistDirtyStateToStorage();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 7 — PEP SCREENING
    // ────────────────────────────────────────────────────────────────────────────
    // Visible when Director Declaration both radios answered.
    // ════════════════════════════════════════════════════════════════════════════
    @track pepScreeningFieldValues = {};

    get isPep()    { return this.pepScreeningFieldValues.isPep || ''; }
    get isPepYes() { return this.isPep === 'Yes'; }
    get isPepNo()  { return this.isPep === 'No';  }

    handleIsPepChange(event) {
        if (this.isReadOnlyScreen) return;
        this.pepScreeningFieldValues = { ...this.pepScreeningFieldValues, isPep: event.target.value };
        this._persistDirtyStateToStorage();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 8 — CROSS-SELL ACCOUNT
    // ────────────────────────────────────────────────────────────────────────────
    // Visible when PEP is answered.
    //
    //  Field key              │ Type  │ Options
    // ────────────────────────┼───────┼─────────
    //  isBankAccountCheck     │ radio │ Yes / No   (Has_Bank_Account__c)
    //  isOpenSavingsAccount   │ radio │ Yes / No   (Interested_In_Opening_Savings_Account__c)
    // ────────────────────────┴───────┴─────────
    // Warning banner shown when both answers are "No".
    // ════════════════════════════════════════════════════════════════════════════
    @track bankAccountCheckFieldValues = {};

    get isBankAccountCheck()         { return this.bankAccountCheckFieldValues.isBankAccountCheck    || ''; }
    get isOpenSavingsAccount()       { return this.bankAccountCheckFieldValues.isOpenSavingsAccount  || ''; }
    get isBankAccountCheckYes()      { return this.isBankAccountCheck    === 'Yes'; }
    get isBankAccountCheckNo()       { return this.isBankAccountCheck    === 'No';  }
    get isOpenSavingsAccountYes()    { return this.isOpenSavingsAccount  === 'Yes'; }
    get isOpenSavingsAccountNo()     { return this.isOpenSavingsAccount  === 'No';  }

    /** Informational banner — fires when the applicant has no bank account */
    get showCrossSellWarning() {
        return this.isBankAccountCheckNo && this.isOpenSavingsAccountNo;
    }

    handleIsBankAccountCheckChange(event) {
        if (this.isReadOnlyScreen) return;
        this.bankAccountCheckFieldValues = { ...this.bankAccountCheckFieldValues, isBankAccountCheck: event.target.value };
        this._persistDirtyStateToStorage();
    }
    handleIsOpenSavingsAccountChange(event) {
        if (this.isReadOnlyScreen) return;
        this.bankAccountCheckFieldValues = { ...this.bankAccountCheckFieldValues, isOpenSavingsAccount: event.target.value };
        this._persistDirtyStateToStorage();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 8.B — ETB CASA REPAYMENT ACCOUNT PICKER
    // ────────────────────────────────────────────────────────────────────────────
    // Visible when "Interested in opening a savings account with us?" === 'Yes'
    // AND at least one CASA account was returned by the ETB CASA integration
    // (Applicant__c.ETB_CASA_Details__c populated by ETBCASAHandlerAPI on the
    // Basic Details NEXT click). The user picks one account → its ACCOUNTID is
    // stamped on Applicant__c.Bank_Account_No__c (sent via the
    // bankAccountCheckFieldValues.bankAccountNo key on the next save).
    //
    // Closed (ACCT_CLS_FLG === 'Y') and Suspended (SUSPENDED_FLG === 'Y')
    // accounts are rendered tinted red and are not selectable; 
    // ════════════════════════════════════════════════════════════════════════════
    @track _crossSellAccountsRaw = [];
    @track _showAccountDetailsModal = false;
    @track _accountDetailsModalRow = null;

    get crossSellAccountsTiles() {
        const selected = this.bankAccountCheckFieldValues.bankAccountNo || '';
        return (this._crossSellAccountsRaw || []).map((acct, idx) => {
            const accountId    = acct.ACCOUNTID || '';
            const isClosed     = (acct.ACCT_CLS_FLG || '').toUpperCase() === 'Y';
            const isSuspended  = (acct.SUSPENDED_FLG || '').toUpperCase() === 'Y';
            const isDisabled   = isClosed || isSuspended;
            const isSelected   = !isDisabled && accountId && accountId === selected;
            const disabledTip  = isClosed
                ? 'This account is closed and cannot be selected.'
                : (isSuspended ? 'This account is suspended and cannot be selected.' : '');
            let tileClass = 'kyc-casa-tile';
            if (isSelected)  tileClass += ' kyc-casa-tile--selected';
            if (isDisabled)  tileClass += ' kyc-casa-tile--disabled';
            return {
                key            : `${accountId || 'na'}-${idx}`,
                accountId,
                acctOpenDate   : acct.ACCT_OPN_DATE || '',
                natureOfAccount: acct.Nature_of_account || '',
                isClosed,
                isSuspended,
                isDisabled,
                isSelected,
                disabledTip,
                tileClass,
                raw            : acct
            };
        });
    }

    /** True when section is shown and at least one CASA account exists. */
    get showCrossSellAccountsPicker() {
        return this.isOpenSavingsAccount === 'Yes'
            && (this._crossSellAccountsRaw || []).length > 0;
    }

    handleCrossSellAccountSelect(event) {
        if (this.isReadOnlyScreen) return;
        const tile = event.currentTarget;
        const accountId = tile?.dataset?.accountId || '';
        const isDisabled = tile?.dataset?.disabled === 'true';
        if (!accountId || isDisabled) return;

        this.bankAccountCheckFieldValues = {
            ...this.bankAccountCheckFieldValues,
            bankAccountNo: accountId
        };
        this._persistDirtyStateToStorage();

        if (this._applicantId) {
            savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_SAVE,
                recordId      : this._recordId,
                params        : { applicantId: this._applicantId, bankAccountNo: accountId }
            }).catch(() => { /* fire-and-forget */ });
        }
    }

    /** Opens the inline modal showing every attribute of a CASA account row. */
    handleCrossSellShowMore(event) {
        event?.stopPropagation?.();
        const accountId = event.currentTarget?.dataset?.accountId || '';
        if (!accountId) return;
        const row = (this._crossSellAccountsRaw || []).find((a) => a.ACCOUNTID === accountId);
        if (!row) return;
        this._accountDetailsModalRow = row;
        this._showAccountDetailsModal = true;
    }

    handleCrossSellAccountDetailsClose() {
        this._showAccountDetailsModal = false;
        this._accountDetailsModalRow  = null;
    }

    /** True when modal is currently rendering. Drives `lwc:if` in the template. */
    get showAccountDetailsModal() { return this._showAccountDetailsModal; }

    /** Rendered field list for the Show More modal — preserves order + labels. */
    get accountDetailsModalFields() {
        const row = this._accountDetailsModalRow || {};
        const labels = [
            { key: 'ACCOUNTID',           label: 'Account ID' },
            { key: 'ACCT_OPN_DATE',       label: 'Account Open Date' },
            { key: 'CUSTNAME',            label: 'Customer Name' },
            { key: 'Account_holder_name', label: 'Account Holder Name' },
            { key: 'Nature_of_account',   label: 'Nature of Account' },
            { key: 'SCHEME_CODE',         label: 'Scheme Code' },
            { key: 'IFSC_CODE',           label: 'IFSC Code' },
            { key: 'SUSPENDED_FLG',       label: 'Suspended' },
            { key: 'ACCT_CLS_FLG',        label: 'Account Closed' }
        ];
        return labels.map(({ key, label }) => ({
            key,
            label,
            value: row[key] != null && String(row[key]).trim() !== '' ? row[key] : '—'
        }));
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 9 — CUSTOMER IMAGE
    // ────────────────────────────────────────────────────────────────────────────
    // Visible when Cross-Sell both radios answered.
    // Single-file upload (no webcam). Checklist is created on-demand when
    // the user clicks upload.
    // ════════════════════════════════════════════════════════════════════════════
    @track customerImageFieldValues = {};
    @track _customerImageChecklistId = null;
    @track showCustomerImageMagicUpload = false;
    @track customerImageActiveUploadChecklistId = null;
    @track customerImageActiveMaxFiles = 1;
    @track customerImageActiveAllowedTypes = 'jpg,jpeg,png';
    _customerImageOverlayMouseDownOnSelf = false;

    get customerImageFileElement()      { return this.customerImageFieldValues.customerImageFile || null; }
    get customerImageFileName()         { return this._fileLabel(this.customerImageFileElement); }
    get customerImageContentDocumentId(){ return this._fileContentDocumentId(this.customerImageFileElement); }
    get customerImageFileType()         { return this._fileExtension(this.customerImageFileElement); }
    get hasCustomerImage()              { return !!this.customerImageFileName; }
    get noCustomerImage()               { return !this.hasCustomerImage; }
    get customerImageChecklistRecordId(){ return this._customerImageChecklistId; }
    get customerImageUploadDisabled()   { return !this._customerImageChecklistId || this.isReadOnlyScreen; }
    get customerImagePanelUploadDisabled() { return this.isReadOnlyScreen || this.hasCustomerImage; }
    get customerImagePanelFiles() {
        return this._entityDocPanelFilesView(
            this.customerImageFileElement,
            this._customerImageChecklistId,
            'customer-image',
            'Customer Photograph'
        );
    }

    handleCustomerImageUpload(event) {
        const f = (event.detail?.files || [])[0];
        if (!f) return;
        const meta = this._fileMetaFromEvent(f);
        this.customerImageFieldValues = { ...this.customerImageFieldValues, customerImageFile: meta };
    }

    async handleCustomerImageUploadRequest() {
        if (this.isReadOnlyScreen) return;
        if (this.hasCustomerImage) {
            this._toast('Document already uploaded', 'Remove the current customer photograph before uploading again.', 'warning');
            return;
        }
        const checklistId = await this._ensureCustomerImageChecklist();
        if (!checklistId) return;
        this.customerImageActiveUploadChecklistId = checklistId;
        this.customerImageActiveMaxFiles = 1;
        this.customerImageActiveAllowedTypes = 'jpg,jpeg,png';
        this.showCustomerImageMagicUpload = true;
    }

    async _ensureCustomerImageChecklist() {
        if (this._customerImageChecklistId) {
            return this._customerImageChecklistId;
        }
        if (!this._recordId) {
            this._toast('Customer Image', 'Application context is not ready. Please refresh and try again.', 'error');
            return null;
        }
        const applicantId = this._resolveApplicantIdForLoad();
        if (!applicantId) {
            this._toast('Customer Image', 'Applicant context is not ready. Please refresh and try again.', 'error');
            return null;
        }
        const svc = this.template.querySelector('c-embed-document-checklist');
        if (!svc) {
            this._toast('Customer Image', 'Upload service is unavailable. Please refresh and try again.', 'error');
            return null;
        }
        try {
            const result = await svc.getOrCreateChecklist({
                applicationId: this._recordId,
                applicantId,
                applicantType: null,
                documentType: CUSTOMER_IMAGE_DOC_TYPE,
                documentName: CUSTOMER_IMAGE_DOC_TYPE,
                documentCategory: null
            });
            const checklistId = result?.checklistId || null;
            if (checklistId != null) {
                this._customerImageChecklistId = checklistId;
                this.customerImageActiveMaxFiles = result?.maxFilesAllowed ?? 1;
                this.customerImageActiveAllowedTypes = result?.allowedFileTypes || 'jpg,jpeg,png';
            }
            return this._customerImageChecklistId;
        } catch (error) {
            this._toast(
                'Customer Image',
                error?.body?.message || error?.message || 'Unable to prepare customer image upload.',
                'error'
            );
            return null;
        }
    }

    handleCustomerImageMagicUploadClose() {
        this._resetCustomerImageMagicUploadState();
    }

    stopPropagationCustomerImageDv(event) {
        event.stopPropagation();
    }

    handleCustomerImageOverlayMouseDown(event) {
        this._customerImageOverlayMouseDownOnSelf = event.target === event.currentTarget;
    }

    handleCustomerImageOverlayClick(event) {
        if (event.target === event.currentTarget && this._customerImageOverlayMouseDownOnSelf) {
            this._resetCustomerImageMagicUploadState();
        }
        this._customerImageOverlayMouseDownOnSelf = false;
    }

    async handleCustomerImageMagicUploadComplete(event) {
        const files = (event.detail && event.detail.files) || [];
        this._resetCustomerImageMagicUploadState();
        if (!files.length) return;

        const first = files[0];
        let contentDocumentId = first.documentId || first.contentDocumentId || null;
        if (!contentDocumentId && first.contentVersionId) {
            contentDocumentId = await this._resolveContentDocumentIdFromVersion(first.contentVersionId);
        }
        const fileData = {
            fileName: first.fileName || first.name || 'File attached',
            fileSize: first.size,
            contentVersionId: first.contentVersionId || null,
            contentDocumentId
        };
        this.customerImageFieldValues = {
            ...this.customerImageFieldValues,
            customerImageFile: fileData
        };
        await this._runCustomerImagePostUploadIntegrations();
    }

    async _runCustomerImagePostUploadIntegrations() {
        if (this.isReadOnlyScreen) return;
        if (!this._recordId || !this._resolveApplicantIdForLoad()) return;

        this.showIntegrationProgressModal = true;
        this.integrationProgressModalHeader = 'Customer Image Verification';
        this.integrationProgressModalStages = CUSTOMER_IMAGE_POST_UPLOAD_INTEGRATIONS.map((item) => item.label);
        this.integrationProgressModalCurrentStageIdx = 0;
        this.integrationProgressModalStatus = 'loading';
        this.integrationProgressModalErrorMessage = '';

        try {
            for (let idx = 0; idx < CUSTOMER_IMAGE_POST_UPLOAD_INTEGRATIONS.length; idx++) {
                const integration = CUSTOMER_IMAGE_POST_UPLOAD_INTEGRATIONS[idx];
                this.integrationProgressModalCurrentStageIdx = idx;
                this.integrationProgressModalStatus = 'loading';

                const integrationMaster = await this._resolveIntegrationMasterConfig(integration.integrationNames);
                const componentRef = integrationMaster?.Component_Reference__c || '';
                if (!integrationMaster?.isSuccess || !componentRef) {
                    const fallbackName = integration.integrationNames[0] || integration.label;
                    throw new Error(integrationMaster?.message || `${fallbackName} integration is not configured.`);
                }

                const runResult = await invokeHandler(componentRef, 'onFileUpload', this);
                if (runResult?.isSuccess === false || runResult?.hasValidationError === true) {
                    throw new Error(runResult?.message || runResult?.displayMessage || `${integration.label} failed.`);
                }
            }

            this.integrationProgressModalStatus = 'success';
            await new Promise((resolve) => setTimeout(resolve, 800));
            this._hideProgress();
        } catch (error) {
            this.integrationProgressModalStatus = 'error';
            this.integrationProgressModalErrorMessage =
                error?.body?.message || error?.message || 'Unable to run customer image verification integrations.';
        }
    }

    async _resolveIntegrationMasterConfig(integrationNames) {
        const names = Array.isArray(integrationNames)
            ? integrationNames.filter((name) => !!String(name || '').trim())
            : [];
        for (const integrationName of names) {
            const response = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD_GET_INTEGRATION_MASTER,
                recordId: this._recordId,
                params: { integrationName }
            });
            if (response?.isSuccess) {
                return response;
            }
        }
        return null;
    }

    async handleCustomerImagePanelFilePreview(event) {
        const detail = event.detail || {};
        const contentVersionId = detail.contentVersionId || this.customerImageFileElement?.contentVersionId || null;
        const fileName = detail.fileName || this.customerImageFileName || 'Customer Photograph';
        const fileExtension =
            detail.fileType ||
            this.customerImageFileType ||
            this._fileExtension({ fileName }) ||
            '';

        if (contentVersionId) {
            this.entityPreviewContentVersionId = contentVersionId;
            this.entityPreviewFileName = fileName;
            this.entityPreviewFileExtension = fileExtension;
            this.showEntityEmbedFilePreview = true;
            return;
        }

        let contentDocumentId = detail.contentDocumentId || this.customerImageContentDocumentId || null;
        if (!contentDocumentId && this.customerImageFileElement?.contentVersionId) {
            contentDocumentId = await this._resolveContentDocumentIdFromVersion(this.customerImageFileElement.contentVersionId);
        }
        if (!contentDocumentId) return;
        this.previewContentDocumentId = contentDocumentId;
        this.previewFileType = fileExtension || null;
        this.showFilePreviewer = true;
    }

    handleCustomerImagePanelFileDelete() {
        this.handleCustomerImageRemove();
    }

    _resetCustomerImageMagicUploadState() {
        this.showCustomerImageMagicUpload = false;
        this.customerImageActiveUploadChecklistId = null;
        this.customerImageActiveMaxFiles = 1;
        this.customerImageActiveAllowedTypes = 'jpg,jpeg,png';
        this._customerImageOverlayMouseDownOnSelf = false;
    }

    handleCustomerImageRemove() {
        if (this.isReadOnlyScreen) return;
        const removed = this.customerImageFieldValues.customerImageFile;
        this.customerImageFieldValues = { ...this.customerImageFieldValues, customerImageFile: null };
        if (this._customerImageChecklistId && removed) {
            savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_DELETE_FILE,
                recordId      : this._recordId,
                params        : {
                    checklistRecordId : this._customerImageChecklistId,
                    contentDocumentId : removed.contentDocumentId,
                    contentVersionId  : removed.contentVersionId
                }
            }).catch(() => { /* fire-and-forget */ });
        }
    }

    // ── Section visibility (chained reveal) ──────────────────────────────────

    get hasAddressProofForVerification() {
        if (!this.addrDocumentType) return false;
        // Verification-only paths (Aadhaar Card, Others): "proof" comes from
        // the selected verification method being successfully run; no file upload.
        if (VERIFICATION_ONLY_DOC_TYPES.has(this.addrDocumentType)) return this._isAadhaarVerified;
        return this.isSideModeFull
            ? this.hasAddressProofFile
            : (this.hasAddressProofFileFront && this.hasAddressProofFileBack);
    }
    get showAddressVerification()  { return this.hasAddressProofForVerification; }
    get showDirectorDeclaration() {
        return this.showAddressVerification
            && !!this.isCurrentAddrSameAsPermanent
            && !!this.isOfficeAddrSameAsCurrent;
    }
    /** PEP reveals once both Director Declaration radios are answered. */
    get showPepScreening() {
        return this.showDirectorDeclaration
            && !!this.isDirectorDeclaration
            && !!this.isSeniorOfficerRelative;
    }
    /** Cross-Sell reveals once PEP is answered. */
    get showCrossSellAccount() {
        return this.showPepScreening && !!this.isPep;
    }
    /** Legacy alias still referenced by the HTML — equals showCrossSellAccount. */
    get showBankAccountCheck() {
        return this.showCrossSellAccount;
    }
    /** Customer Image reveals once both Cross-Sell radios are answered. */
    get showCustomerImageCapture() {
        return this.showCrossSellAccount
            && !!this.isBankAccountCheck
            && !!this.isOpenSavingsAccount;
    }

    // ── Combined field values (for save) ─────────────────────────────────────
    get allFieldValues() {
        return {
            ...this.kycInfoFieldValues,
            ...this.addressVerificationFieldValues,
            ...this.directorDeclarationFieldValues,
            ...this.pepScreeningFieldValues,
            ...this.bankAccountCheckFieldValues,
        };
    }

    // ════════════════════════════════════════════════════════════════════════════
    // Current Address KYC – Extracted Document Details (OCR)
    // ────────────────────────────────────────────────────────────────────────────
    // Driven by Einstein DocumentExtractionPrompt run against the latest uploaded
    // file from Section 1. Persisted to Document_CheckList__c KYC_* fields.
    @track currentExtractedDetails  = null;     // Map of OCR fields, null until a successful extract
    @track isExtractingCurrent      = false;    // true while Einstein call is in flight
    _processedVersionIds            = new Set();

    get extractedDocLabel() {
        return this.addrDocumentType
            ? `Current Address KYC — ${this.addrDocumentType}`
            : 'Current Address KYC';
    }
    get extractedDocType() {
        return this.addrDocumentType || 'Document';
    }
    get extractedDetailsIsReadOnly() {
        return this.isReadOnlyScreen;
    }
    get showCurrentStandaloneExtractedDetails() {
        return this.isExtractingCurrent || !!this.currentExtractedDetails;
    }

    handleExtractedDetailsChange(event) {
        const detail = event?.detail || {};
        if (!detail.field) return;
        const allValues = detail.allValues || {};
        this.currentExtractedDetails = { ...(this.currentExtractedDetails || {}), ...allValues };
    }

    // ── Loading / preview / read-only state ──────────────────────────────────
    @track isLoading                = false;
    @track isSaving                 = false;
    @track showFilePreviewer              = false;
    @track previewContentDocumentId       = null;
    @track previewFileType                 = null;
    @track showEntityEmbedFilePreview      = false;
    @track entityPreviewContentVersionId   = null;
    @track entityPreviewFileName           = '';
    @track entityPreviewFileExtension      = '';
    _sessionId = null;
    _vfRoot    = null;

    // ── Integration Progress Modal (OCR) ─────────────────────────────────────
    @track showIntegrationProgressModal            = false;
    @track integrationProgressModalHeader          = '';
    @track integrationProgressModalStatus          = 'loading';
    @track integrationProgressModalCurrentStageIdx = 0;
    @track integrationProgressModalStages          = [];
    @track integrationProgressModalErrorMessage    = '';

    handleIntegrationProgressUpdate(event) {
        const d = event.detail || {};
        this.showIntegrationProgressModal            = d.show !== false;
        this.integrationProgressModalStatus          = d.status || 'loading';
        this.integrationProgressModalHeader          = d.header || '';
        this.integrationProgressModalCurrentStageIdx = d.currentStageIndex ?? 0;
        this.integrationProgressModalStages          = d.stages || [];
        this.integrationProgressModalErrorMessage    = d.errorMessage || '';
    }
    handleIntegrationProgressModalClose() { this.showIntegrationProgressModal = false; }
    handleIntegrationProgressModalDone()  { this.showIntegrationProgressModal = false; }
    handleIntegrationProgressModalRetry() {
        this.integrationProgressModalStatus          = 'loading';
        this.integrationProgressModalHeader          = '';
        this.integrationProgressModalCurrentStageIdx = 0;
        this.integrationProgressModalErrorMessage    = '';
    }

    _showProgress(stageIndex, errorMessage, status) {
        this.showIntegrationProgressModal            = true;
        this.integrationProgressModalStatus          = status || 'loading';
        this.integrationProgressModalCurrentStageIdx = stageIndex || 0;
        this.integrationProgressModalStages          = OCR_STAGES;
        this.integrationProgressModalErrorMessage    = errorMessage || '';
    }
    _hideProgress() {
        this.showIntegrationProgressModal = false;
    }

    _debugKycNavLog(location, message, data) {
        try {
            console.log(`[KYCNav] ${location} ${message} ${JSON.stringify(data)}`);
        } catch (e) {
            console.log(`[KYCNav] ${location} ${message}`);
        }
    }

    _getNextBlockReasons() {
        const identityCheck = this._validateAtLeastOneAadhaarVerified();
        return {
            isNextDisabled: this.isNextDisabled,
            isLoading: this.isLoading,
            isSaving: this.isSaving,
            isReadOnlyScreen: this.isReadOnlyScreen,
            isStagePast: this._isStagePast,
            stageIsComplete: this._stageIsComplete,
            recordId: this._recordId,
            applicantId: this._applicantId,
            resolvedApplicantId: this._resolveApplicantIdForLoad(),
            currentViewId: this.currentViewId,
            stagePhrase: this.stagePhrase,
            tab: this.tab,
            addrDocumentType: this.addrDocumentType,
            hasAddressProofForVerification: this.hasAddressProofForVerification,
            identityCheckOk: identityCheck.ok,
            identityCheckMessage: identityCheck.message || '',
            showCustomerImageCapture: this.showCustomerImageCapture,
            hasCustomerImage: this.hasCustomerImage,
            showPermanentSection: this.showPermanentSection,
            permAddrDocumentType: this.permAddrDocumentType,
            permHasAddressProofForVerification: this.permHasAddressProofForVerification,
            showOfficeSection: this.showOfficeSection,
            officeChecklistId: this._officeChecklistId,
            isNonIndividual: this.isNonIndividualApplicant,
            isAadhaarVerified: this._isAadhaarVerified,
            permAadhaarVerified: this._permIsAadhaarVerified
        };
    }

    get isReadOnlyScreen() { return this._isStagePast || this._stageIsComplete; }

    /**
     * NEXT is gated until every visible mandatory field across the chained reveal sections is satisfied.
     */
    get isNextDisabled() {
        if (this.isLoading || this.isSaving) return true;
        if (this.isNonIndividualApplicant) {
            return this._isNonIndividualNextDisabled;
        }
        return this._isIndividualNextDisabled;
    }

    get _isIndividualNextDisabled() {
        if (this.isReadOnlyScreen) return false;
        if (!this.showCustomerImageCapture) return true;
        if (!this.hasCustomerImage) return true;
        if (this.showPermanentSection && !this.permHasAddressProofForVerification) return true;
        if (this.showOfficeSection && !this._officeChecklistId) return true;
        return false;
    }

    get _isNonIndividualNextDisabled() {
        if (this.isReadOnlyScreen) return false;
        if (this._cinRequired) {
            if (!this._isCinSectionComplete()) {
                return true;
            }
        }
        if (this._gstRequired) {
            if (!this.hasGstFile || !this.gstDetailSectionReady || !this.isGstMandatoryComplete) {
                return true;
            }
        }
        if (this._entityGstRegisteredQuestionApplies) {
            if (!this._gstIsRegisteredAddress) {
                return true;
            }
            if (this._gstIsRegisteredAddress === 'Yes' && !this.isGstMandatoryComplete) {
                return true;
            }
        }
        if (!this.isRegisteredAddressComplete) {
            return true;
        }
        if (this.showEntityOfficeAddressSection && this._officeSameAsRegistered !== 'Yes'
            && !this._isEntityAddressSectionComplete(
                this.officeAddressFieldValues,
                this.officeShowAddressDetailFields,
                this.hasOfficeProofFile
            )) {
            return true;
        }
        return false;
    }

    _isEntityAddressSectionComplete(values, showDetailFields, hasProofFile) {
        if (!values) return false;
        const proof = String(values.addressProof || '').trim();
        if (!proof) return false;
        if (proof !== ENTITY_ADDRESS_PROOF_GST && !hasProofFile) return false;
        if (!showDetailFields) return false;
        return this._isEntityAddressComplete(values, { requireDistrict: true });
    }

    _isEntityAddressComplete(values, { requireDistrict = true } = {}) {
        if (!values) return false;
        if (!String(values.addressProof || '').trim()) return false;
        if (!String(values.kycAddressLine1 || '').trim()) return false;
        if (!String(values.kycAddressLine2 || '').trim()) return false;
        if (!String(values.state || '').trim()) return false;
        if (requireDistrict && !String(values.district || '').trim()) return false;
        if (!String(values.city || '').trim()) return false;
        if (!String(values.kycPinCode || '').trim()) return false;
        return true;
    }

    get readOnlyHint()     { return this.isReadOnlyScreen ? 'This stage is locked.' : ''; }
    get nextButtonClass() {
        return 'kyc-primary-btn' + (this.isNextDisabled ? ' kyc-primary-btn-disabled' : '');
    }
    get nextButtonLabel() {
        return this.isReadOnlyScreen ? 'Next' : (this.isSaving ? 'Saving…' : 'Next');
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    _initialized = false;

    _isKycMenuDetail(detail = {}) {
        return (detail.overrideLwc || '').trim() === 'wheelsIndividualKYCMasterPage';
    }

    _handleMenuSelectForNav(event) {
        const detail = event?.detail || {};
        if (!this._isKycMenuDetail(detail)) {
            return;
        }
        WheelsIndividualKYCMasterPage._lastMenuDetail = detail;
        this._applyMenuNavFromDetail(detail);
        const nextApplicantId = detail.applicantId || null;
        if (nextApplicantId && nextApplicantId !== this._applicantId) {
            this.applicantId = nextApplicantId;
            return;
        }
        this._schedulePageDataLoad();
    }

    _applyMenuNavFromDetail(detail = {}) {
        this._menuNavApplicantId = detail.applicantId || '';
        this._menuNavContext = {
            currentViewId: detail.id || '',
            stagePhrase: detail.stagePhrase || detail.currentStagePhrase || '',
            tab: detail.tab || detail.label || '',
            applicantId: detail.applicantId || ''
        };
        const navApplicantId = detail.applicantId || null;
        if (navApplicantId && !this._applicantId) {
            this._applicantId = navApplicantId;
        }
        if (detail.isStagePast != null) {
            this._isStagePast = detail.isStagePast === true;
        }
    }

    /**
     * Menu cache is preferred over @api for Next dispatch. After Basic Details
     * auto-navigation, @api currentViewId can still reference Basic_Details while
     * _lastMenuDetail already holds the KYC menu item from losmenuselect.
     */
    _resolveStagePhrase(currentViewId = '') {
        const fromMenu = (
            this._menuNavContext.stagePhrase
            || WheelsIndividualKYCMasterPage._lastMenuDetail?.stagePhrase
            || WheelsIndividualKYCMasterPage._lastMenuDetail?.currentStagePhrase
            || ''
        ).trim();
        if (fromMenu) {
            return fromMenu;
        }
        const fromApi = (this.stagePhrase || '').trim();
        if (fromApi) {
            return fromApi;
        }
        if (!currentViewId) {
            return '';
        }
        const sfIdMatch = String(currentViewId).match(/_([a-zA-Z0-9]{15,18})$/);
        if (sfIdMatch) {
            return currentViewId.slice(0, -sfIdMatch[1].length - 1);
        }
        return '';
    }

    _resolveNavContext() {
        const currentViewId = (
            this.currentViewId
            || this._menuNavContext.currentViewId
            || WheelsIndividualKYCMasterPage._lastMenuDetail?.id
            || ''
        );
        return {
            currentViewId,
            stagePhrase: this._resolveStagePhrase(currentViewId),
            tab: (
                this.tab
                || this._menuNavContext.tab
                || WheelsIndividualKYCMasterPage._lastMenuDetail?.tab
                || STAGE_KYC
            ),
            applicantId: (
                this._applicantId
                || this._menuNavApplicantId
                || this._menuNavContext.applicantId
                || WheelsIndividualKYCMasterPage._lastMenuDetail?.applicantId
                || null
            )
        };
    }

    _getNextDisabledMessage() {
        if (this.isLoading || this.isSaving) {
            return 'Please wait while the page is loading.';
        }
        if (this.isReadOnlyScreen) {
            return '';
        }
        if (!this.hasAddressProofForVerification) {
            return 'Complete Current Address verification before continuing.';
        }
        if (!this.showDirectorDeclaration) {
            return 'Answer the Current / Permanent / Office address questions in Section 3.';
        }
        if (!this.isDirectorDeclaration || !this.isSeniorOfficerRelative) {
            return 'Answer both Director Declaration questions before continuing.';
        }
        if (!this.showPepScreening || !this.isPep) {
            return 'Answer the PEP screening question before continuing.';
        }
        if (!this.isBankAccountCheck || !this.isOpenSavingsAccount) {
            return 'Answer both Cross-Sell account questions before continuing.';
        }
        if (!this.showCustomerImageCapture || !this.hasCustomerImage) {
            return 'Upload the customer photograph before continuing.';
        }
        if (this.showPermanentSection && !this.permHasAddressProofForVerification) {
            return 'Complete Permanent Address verification before continuing.';
        }
        if (this.showOfficeSection && !this._officeChecklistId) {
            return 'Complete Office Address details before continuing.';
        }
        return 'Complete all required KYC sections before continuing.';
    }

    _resolveApplicantIdForLoad() {
        return (
            this._applicantId
            || this._menuNavApplicantId
            || WheelsIndividualKYCMasterPage._lastMenuDetail?.applicantId
            || null
        );
    }

    _isApplicantSubStageContext() {
        const phrase = (
            this.stagePhrase
            || WheelsIndividualKYCMasterPage._lastMenuDetail?.stagePhrase
            || ''
        ).trim();
        if (!phrase) {
            return false;
        }
        return /_(Borrower|G\d+|CoBo\d+|B\d+|Guarantor|Co-?Borrower|Beneficiary)\b/i.test(phrase);
    }

    _schedulePageDataLoad() {
        if (!this._recordId || this._pageLoadScheduled) {
            return;
        }
        this._pageLoadScheduled = true;
        Promise.resolve().then(() => {
            this._pageLoadScheduled = false;
            this._loadPageData();
        });
    }

    connectedCallback() {
        if (!this._recordId) this.isLoading = false;
        this._initFilePreviewContext();
        this._menuSelectHandler = this._handleMenuSelectForNav.bind(this);
        window.addEventListener(LOS_MENU_SELECT_EVENT, this._menuSelectHandler);
        const cachedDetail = WheelsIndividualKYCMasterPage._lastMenuDetail;
        if (cachedDetail && this._isKycMenuDetail(cachedDetail)) {
            this._applyMenuNavFromDetail(cachedDetail);
        }
        this._schedulePageDataLoad();
        // Catch opendynamiccomponentmodal events bubbled from child LWCs
        // (e.g. officeAddressDetails Email Verify) on the host element.
        this._dynamicModalHandler = (e) => this.handleOpenDynamicComponentModal(e);
        this.addEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
        // kycNextIntegration dispatches its progress events on window for reliable
        // delivery when nested inside slot/dynamic-component renderers.
        this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e);
        window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 5 — OFFICE ADDRESS DETAILS
    // ────────────────────────────────────────────────────────────────────────────
    // Office-bucket payload + verification flags hydrate from the page-load
    // payload and stay in sync via the child component's officechange event.
    // The section gates on: applicant is Earning AND "Office same as Current" === No.
    // ════════════════════════════════════════════════════════════════════════════
    @track _incomeCategory               = '';
    @track _officeAddressRequired        = false;
    @track _officeChecklistId            = null;
    @track _officeAddressPayload         = {
        addressLine1: '', addressLine2: '', addressLine3: '',
        pinCode: '', city: '', state: '', country: '',
        email: '', emailVerified: false
    };
    _officeEnsureInFlight                = false;

    /** True when the applicant's income category requires Office capture. */
    get isOfficeAddressRequired() { return this._officeAddressRequired === true; }

    /** Public payload binding for the c-office-address-details child. */
    get officeAddressPayload() { return this._officeAddressPayload; }

    /**
     * Section 5 renders only when the applicant is Earning AND the user's
     * answer to "Is Office Address same as Current?" is No. Mirror of the
     * Permanent gating in Section 4.
     */
    get showOfficeSection() {
        return this.showAddressVerification
            && this.isOfficeAddressRequired
            && this.isOfficeAddrSameAsCurrent === 'No';
    }

    async _ensureOfficeChecklist() {
        if (this._officeChecklistId) return;
        if (!this.isOfficeAddressRequired) return;
        if (!this._recordId || !this._applicantId) return;
        if (this._officeEnsureInFlight) return;
        this._officeEnsureInFlight = true;
        try {
            const response = await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_CREATE_OFFICE,
                recordId      : this._recordId,
                params        : { applicantId: this._applicantId }
            });
            if (response?.isSuccess && response.checklistRecordId) {
                this._officeChecklistId = response.checklistRecordId;
            }
        } catch (e) {
            console.error('wheelsIndividualKYCMasterPage: ensureOfficeChecklist', e);
        } finally {
            this._officeEnsureInFlight = false;
        }
    }

    handleOfficeAddressChange(event) {
        const detail = event?.detail || {};
        this._officeAddressPayload = { ...this._officeAddressPayload, ...detail };
        this._persistDirtyStateToStorage();
    }

    handleOfficeEmailVerify(event) {
        const detail = event?.detail || {};
        this._officeAddressPayload = {
            ...this._officeAddressPayload,
            emailVerified: detail.emailVerified === true
        };
        this._persistDirtyStateToStorage();
    }

    @track showDynamicComponentModal = false;
    @track dynamicComponentName      = '';
    @track dynamicComponentProps     = {};
    _dynamicModalHandler             = null;

    handleDynamicComponentModalClose() {
        this.showDynamicComponentModal = false;
        this.dynamicComponentName = '';
    }
    handleOpenDynamicComponentModal(event) {
        const { componentName, ...extraProps } = event.detail || {};
        this.dynamicComponentName  = componentName || '';
        this.dynamicComponentProps = extraProps;
        this.showDynamicComponentModal = !!this.dynamicComponentName;
    }

    async _loadPageData(forceReload) {
        if (!this._recordId) return;
        const applicantIdForLoad = this._resolveApplicantIdForLoad();
        if (this._isApplicantSubStageContext() && !applicantIdForLoad) {
            return;
        }
        if (this._initialized && !forceReload) return;
        this._initialized = true;
        this.isLoading    = true;
        try {
            const response = await getKYCInfoPageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_GET,
                recordId      : this._recordId,
                params        : { applicantId: applicantIdForLoad }
            });

            if (response?.customerType || response?.applicantId) {
                this._applyCommonPageContext(response);
            }

            if (!response || response.isSuccess === false) {
                this._initialized = false;
                this._toast('KYC Details', response?.message || 'Failed to load KYC page data.', 'error');
                return;
            }

            if (this.isNonIndividualApplicant) {
                await this._loadNonIndividualPageData(response);
            } else {
                await this._loadIndividualPageData(response);
            }
        } catch (error) {
            this._initialized = false;
            console.error('wheelsIndividualKYCMasterPage: _loadPageData error', error);
            this._toast('KYC Details', error?.body?.message || error?.message || 'Unexpected load error.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    _applyCommonPageContext(response) {
        if (response.applicantId && !this._applicantId) {
            this._applicantId = response.applicantId;
        }
        this._customerType    = response.customerType || '';
        this._stageIsComplete = response.stageIsComplete === true;
    }

    async _loadNonIndividualPageData(response) {
        await this._hydrateEntityKycFromResponse(response.entityKyc);
    }

    async _loadIndividualPageData(response) {
        this.currentExtractedDetails = null;
        this.permExtractedDetails = null;
        this._customerImageChecklistId = null;
        this.customerImageFieldValues = {};

        this._kycInfoFileUploadRecordId      = response.kycInfoFileUploadRecordId || null;
        this._permKycInfoFileUploadRecordId  = response.kycInfoPermanentFileUploadRecordId || null;

        // Section 5 — Office Address bucket
        this._incomeCategory        = response.incomeCategory || '';
        this._officeAddressRequired = response.officeAddressRequired === true;
        this._officeChecklistId     = response.officeAddressChecklistId || null;
        if (response.officeAddress && typeof response.officeAddress === 'object') {
            this._officeAddressPayload = {
                ...this._officeAddressPayload,
                ...response.officeAddress
            };
        }

        this._applySection(response.kycInfo, 'kycInfoFieldValues');
        if (response.kycInfoPermanent) {
            this._applySection(response.kycInfoPermanent, 'permKycInfoFieldValues');
        }

        // Section 3 Address Verification picklists (Yes/No)
        if (response.addressVerification) {
            this._applySection(response.addressVerification, 'addressVerificationFieldValues');
        }

        // Sections 6–9 — Director Declaration, PEP, Cross-Sell, Customer Image
        if (response.directorDeclaration) {
            this._applySection(response.directorDeclaration, 'directorDeclarationFieldValues');
        }
        if (response.pepScreening) {
            this._applySection(response.pepScreening, 'pepScreeningFieldValues');
        }
        if (response.bankAccountCheck) {
            this._applySection(response.bankAccountCheck, 'bankAccountCheckFieldValues');
        }
        if (response.crossSell) {
            this._crossSellAccountsRaw = Array.isArray(response.crossSell.accounts)
                ? response.crossSell.accounts
                : [];
            // selectedAccountNo lands here too so the picker tile lights up on reload.
            if (response.crossSell.selectedAccountNo) {
                this.bankAccountCheckFieldValues = {
                    ...this.bankAccountCheckFieldValues,
                    bankAccountNo: response.crossSell.selectedAccountNo
                };
            }
        }
        if (response.customerImageCapture) {
            this._customerImageChecklistId = response.customerImageCapture.checklistRecordId || null;
            if (response.customerImageCapture.customerImageFile) {
                this.customerImageFieldValues = {
                    ...this.customerImageFieldValues,
                    customerImageFile: response.customerImageCapture.customerImageFile
                };
            }
        }

        // restore Aadhaar verify state for returning users (both buckets).
        this._applyAadhaarVerifyState(response.aadhaarVerifyState);
        this._applyPermAadhaarVerifyState(response.aadhaarVerifyStatePermanent);

        const extracted = response.extractedDetails || {};
        if (extracted.current) {
            this.currentExtractedDetails = extracted.current;
            // Default POA/POI to TRUE on first surfacing to allow the user to flow straight through NEXT, or untick before saving.
            // server returns null for both toggles.
            this._applyDefaultProofTogglesIfUnset();
        }
        if (extracted.permanent) {
            this.permExtractedDetails = extracted.permanent;
            this._applyPermDefaultProofTogglesIfUnset();
        }

        // sessionStorage so a browser refresh preserves: POA/POI toggles
        this._restoreDirtyStateFromStorage();

    }

    _applySection(fields, sectionKey) {
        if (!Array.isArray(fields)) return;
        const map = {};
        fields.forEach(f => { if (f?.key != null) map[f.key] = f.value; });
        this[sectionKey] = map;
    }

    async _ensureCurrentAddressChecklist() {
        if (!this._applicantId) return null;
        if (this._kycInfoFileUploadRecordId) return this._kycInfoFileUploadRecordId;
        try {
            const response = await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_CREATE_CURRENT,
                recordId      : this._recordId,
                params        : { applicantId: this._applicantId }
            });
            if (response?.isSuccess && response.checklistRecordId) {
                this._kycInfoFileUploadRecordId = response.checklistRecordId;
            }
            return this._kycInfoFileUploadRecordId;
        } catch (e) {
            console.error('wheelsIndividualKYCMasterPage: ensureCurrentAddressChecklist', e);
            return null;
        }
    }

    // ── File preview ──────────────────────────────────────────────────────────
    handleFilePreviewClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const ds                = event.currentTarget?.dataset || {};
        const contentDocumentId = ds.contentDocumentId || null;
        const fileType          = ds.fileType          || null;
        if (!contentDocumentId) return;
        this.previewContentDocumentId = contentDocumentId;
        this.previewFileType          = fileType;
        this.showFilePreviewer        = true;
    }
    handleFilePreviewClose() {
        this.showFilePreviewer        = false;
        this.previewContentDocumentId = null;
        this.previewFileType          = null;
    }

    async _handleNonIndividualNextButton() {
        this._entityMandatoryDocsError = '';
        this._darpanError = '';
        this.isSaving = true;
        try {
            const params = this._buildNonIndividualSavePayload();
            const saveResponse = await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_SAVE,
                recordId      : this._recordId,
                params
            });
            if (!saveResponse?.isSuccess) {
                if (saveResponse?.darpan && saveResponse.darpan.documentsComplete === false) {
                    const message = saveResponse.darpan.validationMessage
                        || 'Please complete mandatory Darpan document uploads.';
                    this._darpanError = message;
                    this._toast('Darpan Details', message, 'error');
                    return;
                }
                const validationMessage = this._formatEntityMandatoryDocsError(
                    saveResponse?.missingRequiredDocuments,
                    saveResponse?.adhocDocumentsRemaining
                ) || saveResponse?.validationMessage
                    || saveResponse?.message
                    || 'Failed to save entity KYC details.';
                this._entityMandatoryDocsError = validationMessage;
                this._toast('Save Failed', validationMessage, 'error');
                return;
            }
            this._stageIsComplete = true;
            this._clearDirtyStateFromStorage();
            this._toast('Entity KYC', 'KYC details saved successfully.', 'success');
            this._dispatchLosNextStage();
        } catch (error) {
            console.error('wheelsIndividualKYCMasterPage: _handleNonIndividualNextButton', error);
            this._toast(
                'Error',
                error?.body?.message || error?.message || 'An unexpected error occurred.',
                'error'
            );
        } finally {
            this.isSaving = false;
        }
    }

    _buildNonIndividualSavePayload() {
        return {
            applicantId: this._applicantId || null,
            gstIsRegisteredAddress: this._entityGstRegisteredQuestionApplies
                ? this._gstIsRegisteredAddress
                : 'No',
            officeSameAsRegistered: this._officeSameAsRegistered,
            gst: this._serializeEntityGstPayload(),
            registered: this._serializeEntityAddressPayload(this.registeredAddressFieldValues),
            office: this._serializeEntityAddressPayload(this.officeAddressFieldValues),
            additionalDocuments: (this._entityAdditionalDocuments || []).map((entry) => ({
                documentType: entry.documentType || '',
                checklistRecordId: entry.checklistRecordId || null,
                proofFile: entry.proofFile || null
            })),
            darpan: this._serializeDarpanPayload()
        };
    }

    _serializeDarpanPayload() {
        const status = this.isDarpanApplicableEntity
            ? String(this._darpanNpoStatus || '').trim()
            : '';
        const deferralApproval = this.isDarpanApplicableEntity
            && this._darpanDeferralApproval === DARPAN_DEFERRAL_YES;
        const canEdit = status === DARPAN_NPO_STATUS_NPO && !deferralApproval;
        return {
            npoStatus: status,
            deferralApproval,
            darpanId: canEdit ? String(this._darpanId || '').trim() : '',
            registrationDate: canEdit
                ? this._fromDateTimeInputValue(this._darpanRegistrationDate)
                : null,
            documents: this._activeDarpanDocuments().map((entry) => ({
                documentType: entry.documentType || '',
                checklistRecordId: entry.checklistRecordId || null,
                proofFile: entry.proofFile || null
            }))
        };
    }

    _serializeEntityGstPayload() {
        return {
            gstNumber: this.gstFieldValues.gstNumber || '',
            kycAddressLine1: this.gstFieldValues.kycAddressLine1 || '',
            kycAddressLine2: this.gstFieldValues.kycAddressLine2 || '',
            state: this.gstFieldValues.state || '',
            district: this.gstFieldValues.district || '',
            city: this.gstFieldValues.city || '',
            kycPinCode: this.gstFieldValues.kycPinCode || ''
        };
    }

    _serializeEntityAddressPayload(values) {
        if (!values) {
            return {};
        }
        return {
            addressProof: values.addressProof || '',
            proofFile: values.proofFile || null,
            kycAddressLine1: values.kycAddressLine1 || '',
            kycAddressLine2: values.kycAddressLine2 || '',
            state: values.state || '',
            district: values.district || '',
            city: values.city || '',
            kycPinCode: values.kycPinCode || ''
        };
    }

    // ── Next / Save (Individual) ─────────────────────────────────────────────
    async handleNextButton() {
        this._debugKycNavLog(
            'wheelsIndividualKYCMasterPage.js:handleNextButton',
            'KYC Next clicked',
            this._getNextBlockReasons(),
            'A'
        );
        if (this.isNextDisabled) {
            const blockMessage = this._getNextDisabledMessage();
            this._debugKycNavLog(
                'wheelsIndividualKYCMasterPage.js:handleNextButton',
                'Blocked — isNextDisabled',
                { blockMessage, ...this._getNextBlockReasons() },
                'A'
            );
            if (blockMessage) {
                this._toast('Complete required sections', blockMessage, 'warning');
            }
            return;
        }
        if (this.isReadOnlyScreen) {
            this._dispatchLosNextStage();
            return;
        }
        if (this.isNonIndividualApplicant) {
            await this._handleNonIndividualNextButton();
            return;
        }
        // Atleast one bucket must have Aadhaar verified.
        const aadhaarCheck = this._validateAtLeastOneAadhaarVerified();
        if (!aadhaarCheck.ok) {
            this._debugKycNavLog(
                'wheelsIndividualKYCMasterPage.js:handleNextButton',
                'Blocked — identity validation',
                { message: aadhaarCheck.message, ...this._getNextBlockReasons() },
                'B'
            );
            this._toast('Verification Required', aadhaarCheck.message, 'error');
            return;
        }
        this._debugKycNavLog(
            'wheelsIndividualKYCMasterPage.js:handleNextButton',
            'Identity validation OK — saving',
            this._getNextBlockReasons(),
            'A'
        );

        this.isSaving = true;
        try {
            const params = {
                ...this.allFieldValues,
                // Send UI-current Extracted Document Details so the Applicant_Address__c record is created/updated.
                extractedDetails: this.currentExtractedDetails || {},
                applicantId: this._applicantId || null
            };

            if (this.showPermanentSection) {
                params.permanent = {
                    ...this.permKycInfoFieldValues,
                    extractedDetails: this.permExtractedDetails || {}
                };
            }

            // Section 5 — only emit when Office is required AND the user
            // explicitly answered "Office is NOT same as Current".
            if (this.showOfficeSection) {
                const officeChild = this.template.querySelector('c-office-address-details');
                const childValidation = officeChild?.validate?.();
                if (childValidation && childValidation.ok === false) {
                    this._debugKycNavLog(
                        'wheelsIndividualKYCMasterPage.js:handleNextButton',
                        'Blocked — office validation',
                        { message: childValidation.message, ...this._getNextBlockReasons() },
                        'B'
                    );
                    this._toast('Office Address', childValidation.message, 'error');
                    return;
                }
                params.officeAddress = officeChild?.getOfficePayload?.() || this._officeAddressPayload;
            }

            // Section 9 — Customer Image is mandatory once the section is visible.
            if (this.showCustomerImageCapture && !this.hasCustomerImage) {
                this._toast(
                    'Customer Image',
                    'Please upload the customer\u2019s photograph before continuing.',
                    'error'
                );
                return;
            }

            const saveResponse = await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_SAVE,
                recordId      : this._recordId,
                params
            });
            if (!saveResponse?.isSuccess) {
                this._debugKycNavLog(
                    'wheelsIndividualKYCMasterPage.js:handleNextButton',
                    'Blocked — save failed',
                    { saveMessage: saveResponse?.message, ...this._getNextBlockReasons() },
                    'B'
                );
                this._toast('Save Failed', saveResponse?.message || 'Failed to save KYC details.', 'error');
                return;
            }
            // Drop the unsaved sessionStorage
            this._clearDirtyStateFromStorage();
            // Post-save integration chain: CUSTOMER_DEDUPE → VALIDATE_RECENT_LEAD.
            // Stub callouts today; the progress modal advances through stages and the
            // handler throws on failure so navigation does not proceed on integration errors.
            await invokeHandler(HANDLER_KYC_NEXT_INTEGRATION, 'onNextButton', this);
            this._debugKycNavLog(
                'wheelsIndividualKYCMasterPage.js:handleNextButton',
                'Save + integration OK — dispatching losnextstage',
                this._getNextBlockReasons(),
                'C'
            );
            this._dispatchLosNextStage();
        } catch (error) {
            this._debugKycNavLog(
                'wheelsIndividualKYCMasterPage.js:handleNextButton',
                'Blocked — exception',
                {
                    errorMessage: error?.body?.message || error?.message || String(error),
                    ...this._getNextBlockReasons()
                },
                'E'
            );
            this._toast('Error', error?.body?.message || error?.message || 'An unexpected error occurred.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    _validateAtLeastOneAadhaarVerified() {
        if (this._isAadhaarVerified) return { ok: true };
        if (this._isPhysicalDocumentVerified(this.addrDocumentType, this.hasAddressProofForVerification)) {
            return { ok: true };
        }
        // Permanent only applies if the user opened that panel.
        if (!this.showPermanentSection) {
            // Current alone — verification-only path must be completed.
            if (VERIFICATION_ONLY_DOC_TYPES.has(this.addrDocumentType)) {
                const label = this.addrDocumentType === 'Aadhaar Card' ? 'Aadhaar' : 'the selected';
                return { ok: false, message: `Please complete ${label} verification on the Current Address before continuing.` };
            }
            if (this.addrDocumentType) {
                return { ok: false, message: 'Complete Current Address document upload before continuing.' };
            }
            return { ok: false, message: 'Identity verification is mandatory. Select "Aadhaar Card" or "Others" for the Current Address.' };
        }
        if (this._permIsAadhaarVerified) return { ok: true };
        if (this._isPhysicalDocumentVerified(this.permAddrDocumentType, this.permHasAddressProofForVerification)) {
            return { ok: true };
        }
        return {
            ok: false,
            message: 'Identity verification is mandatory. Complete address verification on either the Current or Permanent Address section.'
        };
    }

    /**
     * OCR document path only (Passport / Voter ID / Driving License).
     * Does not read or write _isAadhaarVerified — that flag remains Aadhaar/Others only.
     */
    _isPhysicalDocumentVerified(documentType, hasProofForVerification) {
        return OCR_SUPPORTED_DOC_TYPES.has(documentType) && hasProofForVerification === true;
    }

    _dispatchLosNextStage() {
        const nav = this._resolveNavContext();
        const stagePhrase = this._ensureApplicantTokenOnStagePhrase(nav.stagePhrase);
        const detail = {
            currentViewId: nav.currentViewId,
            id                      : nav.currentViewId,
            applicantId             : nav.applicantId,
            currentLoanStageComplete: nav.tab,
            currentStagePhrase      : stagePhrase
        };
        this._debugKycNavLog(
            'wheelsIndividualKYCMasterPage.js:_dispatchLosNextStage',
            nav.currentViewId && nav.stagePhrase
                ? 'Dispatching losnextstage'
                : 'Blocked — missing nav context',
            { detail, nav, ...this._getNextBlockReasons() },
            'C'
        );
        if (!nav.currentViewId) {
            this._toast(
                'Navigation Error',
                'Current view ID is missing. Please select this stage from the menu and try again.',
                'error'
            );
            return;
        }
        if (!stagePhrase) {
            this._toast(
                'Navigation Error',
                'Stage phrase is missing. Please re-select KYC Details from the menu and try again.',
                'error'
            );
                return;
            }
            window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
            detail,
                bubbles : true,
                composed: true
            }));
    }

    _ensureApplicantTokenOnStagePhrase(stagePhrase) {
        const phrase = (stagePhrase || '').trim();
        if (!phrase || this._stagePhraseHasApplicantToken(phrase)) {
            return phrase;
        }
        const tabLabel = (
            WheelsIndividualKYCMasterPage._lastMenuDetail?.applicantType
            || this._menuNavContext?.applicantType
            || 'Borrower'
        ).trim();
        return tabLabel ? `${phrase}_${tabLabel}` : phrase;
    }

    _stagePhraseHasApplicantToken(phrase) {
        // Sub-applicant tab labels carry a "_<n>" suffix (B1_4, G1_2, CoBo1_1); the
        // optional suffix + (?=_|$) lookahead keeps those recognised so the token is
        // not appended twice.
        return /_(Borrower|Guarantor|Beneficiary|Co-?Borrower|(?:CoBo|G|B)\d+(?:_\d+)?)(?=_|$)/i.test(phrase);
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new CustomEvent('showtoast', {
            detail: { title, message, variant },
            bubbles: true, composed: true
        }));
    }

    // ════════════════════════════════════════════════════════════════════════════
    // sessionStorage persistence for unsaved user edits.
    // Captures POA/POI toggles (Current + Permanent) and Section 3 Yes/No
    // picklists so a browser refresh before NEXT does not lose them.
    // Cleared on a successful save.
    // ════════════════════════════════════════════════════════════════════════════
    get _dirtyStateStorageKey() {
        if (!this._recordId) return null;
        return `mogadev.kyc.dirty.${this._recordId}.${this._applicantId || 'NA'}`;
    }

    _persistDirtyStateToStorage() {
        const key = this._dirtyStateStorageKey;
        if (!key) return;
        try {
            const snapshot = {
                addressProofToggle  : this.kycInfoFieldValues.addressProofToggle  ?? null,
                identityProofToggle : this.kycInfoFieldValues.identityProofToggle ?? null,
                isCurrentAddrSameAsPermanent: this.addressVerificationFieldValues.isCurrentAddrSameAsPermanent || '',
                isOfficeAddrSameAsCurrent   : this.addressVerificationFieldValues.isOfficeAddrSameAsCurrent    || '',
                permAddressProofToggle  : this.permKycInfoFieldValues.addressProofToggle  ?? null,
                permIdentityProofToggle : this.permKycInfoFieldValues.identityProofToggle ?? null,
                isDirectorDeclaration   : this.directorDeclarationFieldValues.isDirectorDeclaration   || '',
                isSeniorOfficerRelative : this.directorDeclarationFieldValues.isSeniorOfficerRelative || '',
                isPep                   : this.pepScreeningFieldValues.isPep                          || '',
                isBankAccountCheck      : this.bankAccountCheckFieldValues.isBankAccountCheck         || '',
                isOpenSavingsAccount    : this.bankAccountCheckFieldValues.isOpenSavingsAccount       || '',
                // Office Address is only persisted server-side on NEXT; snapshot
                // the in-progress payload so a mid-way refresh doesn't lose it.
                officeAddress           : { ...this._officeAddressPayload }
            };
            window.sessionStorage.setItem(key, JSON.stringify(snapshot));
        } catch (e) {
            // sessionStorage can throw in private browsing; degrade silently.
        }
    }

    _restoreDirtyStateFromStorage() {
        const key = this._dirtyStateStorageKey;
        if (!key) return;
        try {
            const raw = window.sessionStorage.getItem(key);
            if (!raw) return;
            const snapshot = JSON.parse(raw);
            if (!snapshot || typeof snapshot !== 'object') return;
            if ('addressProofToggle' in snapshot && snapshot.addressProofToggle !== null) {
                this.kycInfoFieldValues = {
                    ...this.kycInfoFieldValues,
                    addressProofToggle: !!snapshot.addressProofToggle
                };
            }
            if ('identityProofToggle' in snapshot && snapshot.identityProofToggle !== null) {
                this.kycInfoFieldValues = {
                    ...this.kycInfoFieldValues,
                    identityProofToggle: !!snapshot.identityProofToggle
                };
            }
            if (snapshot.isCurrentAddrSameAsPermanent || snapshot.isOfficeAddrSameAsCurrent) {
                this.addressVerificationFieldValues = {
                    ...this.addressVerificationFieldValues,
                    ...(snapshot.isCurrentAddrSameAsPermanent ? { isCurrentAddrSameAsPermanent: snapshot.isCurrentAddrSameAsPermanent } : {}),
                    ...(snapshot.isOfficeAddrSameAsCurrent    ? { isOfficeAddrSameAsCurrent:    snapshot.isOfficeAddrSameAsCurrent    } : {})
                };
            }
            if ('permAddressProofToggle' in snapshot && snapshot.permAddressProofToggle !== null) {
                this.permKycInfoFieldValues = {
                    ...this.permKycInfoFieldValues,
                    addressProofToggle: !!snapshot.permAddressProofToggle
                };
            }
            if ('permIdentityProofToggle' in snapshot && snapshot.permIdentityProofToggle !== null) {
                this.permKycInfoFieldValues = {
                    ...this.permKycInfoFieldValues,
                    identityProofToggle: !!snapshot.permIdentityProofToggle
                };
            }
            if (snapshot.isDirectorDeclaration || snapshot.isSeniorOfficerRelative) {
                this.directorDeclarationFieldValues = {
                    ...this.directorDeclarationFieldValues,
                    ...(snapshot.isDirectorDeclaration   ? { isDirectorDeclaration:   snapshot.isDirectorDeclaration   } : {}),
                    ...(snapshot.isSeniorOfficerRelative ? { isSeniorOfficerRelative: snapshot.isSeniorOfficerRelative } : {})
                };
            }
            if (snapshot.isPep) {
                this.pepScreeningFieldValues = {
                    ...this.pepScreeningFieldValues,
                    isPep: snapshot.isPep
                };
            }
            if (snapshot.isBankAccountCheck || snapshot.isOpenSavingsAccount) {
                this.bankAccountCheckFieldValues = {
                    ...this.bankAccountCheckFieldValues,
                    ...(snapshot.isBankAccountCheck   ? { isBankAccountCheck:   snapshot.isBankAccountCheck   } : {}),
                    ...(snapshot.isOpenSavingsAccount ? { isOpenSavingsAccount: snapshot.isOpenSavingsAccount } : {})
                };
            }
            // Restore the in-progress Office Address. 
            if (snapshot.officeAddress && typeof snapshot.officeAddress === 'object') {
                this._officeAddressPayload = {
                    ...this._officeAddressPayload,
                    ...snapshot.officeAddress
                };
            }
        } catch (e) {
            // Ignore corrupted entries.
        }
    }

    _clearDirtyStateFromStorage() {
        const key = this._dirtyStateStorageKey;
        if (!key) return;
        try { window.sessionStorage.removeItem(key); } catch (e) { /* ignore */ }
    }

    // ── OCR (Current Address KYC) ────────────────────────────────────────────────
    /**
     * Triggers Einstein DocumentExtractionPrompt against the just-uploaded
     * file, persists the parsed fields onto the active address checklist row,
     * and merges the result into currentExtractedDetails so the child LWC
     * re-renders.
     */
    async _runOcrExtraction(side, fileMeta) {
        if (this.isReadOnlyScreen) return;
        if (!fileMeta) return;

        const docType = this.addrDocumentType || '';
        if (!OCR_SUPPORTED_DOC_TYPES.has(docType)) {
            return;
        }
        const versionId = fileMeta.contentVersionId;
        if (!versionId || this._processedVersionIds.has(versionId)) {
            return;
        }

        this.isExtractingCurrent = true;
        this._showProgress(0, '', 'loading');

        try {
            this._showProgress(1, '', 'loading');
            const response = await savePageData({
                apexClassName : APEX_EXTRACT_CLASS,
                apexMethodName: APEX_EXTRACT_METHOD,
                recordId      : this._recordId,
                params        : {
                    applicantId       : this._applicantId || null,
                    documentType      : docType,
                    addressType       : ADDR_TYPE_CURRENT,
                    checklistRecordId : this._kycInfoFileUploadRecordId || null,
                    documentSide      : side,
                    addressProofFile  : {
                        contentDocumentId: fileMeta.contentDocumentId,
                        contentVersionId : fileMeta.contentVersionId,
                        fileName         : fileMeta.fileName
                    }
                }
            });

            if (!response?.isSuccess) {
                const msg = response?.message || 'Failed to extract document details.';
                this._showProgress(0, msg, 'error');
                this._toast('Extraction Failed', msg, 'error');
                return;
            }

            this._processedVersionIds.add(versionId);
            this._showProgress(2, '', 'loading');

            const extracted = response.extractedDetails || {};
            const merged = { ...(this.currentExtractedDetails || {}) };
            Object.keys(extracted).forEach((k) => {
                const v = extracted[k];
                if (v !== null && v !== undefined && String(v).trim() !== '') {
                    merged[k] = v;
                }
            });
            this.currentExtractedDetails = merged;

            // Default POA / POI toggles to TRUE the first time OCR succeeds for this row.
            this._applyDefaultProofTogglesIfUnset();

            this._showProgress(3, '', 'success');
            setTimeout(() => this._hideProgress(), 800);
        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Unexpected error during extraction.';
            this._showProgress(0, msg, 'error');
            this._toast('Extraction Error', msg, 'error');
        } finally {
            this.isExtractingCurrent = false;
        }
    }

    _displayFieldValue(value) {
        const normalized = String(value ?? '').trim();
        return normalized || '—';
    }

    _displayDateTimeFieldValue(value) {
        const normalized = String(value ?? '').trim();
        if (!normalized) {
            return '—';
        }
        const date = new Date(normalized);
        if (Number.isNaN(date.getTime())) {
            return this._displayFieldValue(normalized);
        }
        return date.toLocaleString();
    }

    _toDateTimeInputValue(value) {
        const normalized = String(value ?? '').trim();
        if (!normalized) {
            return '';
        }
        const parsed = new Date(normalized);
        if (!Number.isNaN(parsed.getTime())) {
            const local = new Date(parsed.getTime() - (parsed.getTimezoneOffset() * 60000));
            return local.toISOString().slice(0, 16);
        }
        return normalized.length >= 16 ? normalized.slice(0, 16) : normalized;
    }

    _fromDateTimeInputValue(value) {
        const normalized = String(value ?? '').trim();
        return normalized || null;
    }

    // ── File-shape helpers ───────────────────────────────────────────────────
    _fileMetaFromEvent(f) {
        return {
            fileName         : f.name,
            fileSize         : f.size,
            contentVersionId : f.contentVersionId,
            contentDocumentId: f.documentId
        };
    }
    _fileLabel(v) {
        if (!v) return '';
        if (typeof v === 'object') {
            return v.fileName || v.name || (v.contentVersionId ? 'File attached' : '');
        }
        return String(v);
    }
    _fileContentDocumentId(v) {
        return (v && typeof v === 'object') ? (v.contentDocumentId || null) : null;
    }
    _fileExtension(v) {
        if (!v || typeof v !== 'object') return null;
        const name = v.fileName || v.name || '';
        if (!name || typeof name !== 'string') return null;
        const parts = name.split('.');
        return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : null;
    }

    // ════════════════════════════════════════════════════════════════════════════
    // SECTION 4 – PERMANENT ADDRESS KYC
    // ────────────────────────────────────────────────────────────────────────────
    // Rendered only when isCurrentAddrSameAsPermanent === 'No'. State and
    // handlers are prefixed `perm` / `_perm` to keep them separate from
    // Section 1's Current Address state.
    // ════════════════════════════════════════════════════════════════════════════

    @track permKycInfoFieldValues          = {};
    @track _permKycInfoFileUploadRecordId  = null;
    @track showPermAddressMagicUpload      = false;
    @track permAddressActiveUploadChecklistId = null;
    @track permAddressActiveMaxFiles       = 1;
    @track permAddressActiveAllowedTypes   = ENTITY_DV_FALLBACK_FILE_TYPES;
    @track permAddressActiveUploadSlot     = null;
    _permAddressOverlayMouseDownOnSelf     = false;

    @track permExtractedDetails            = null;
    @track isExtractingPermanent           = false;
    _permProcessedVersionIds               = new Set();

    @track _permAadhaarVerificationType    = '';
    @track _permIsAadhaarVerified          = false;
    @track _permIsAadhaarLinkInFlight      = false;
    @track _permAadhaarLinkExpired         = false;

    @track showPermEkycLinkModal           = false;
    @track _permEKycLinkUrl                = '';
    @track _permEKycLinkCopied             = false;
    @track _permIsPollingConsent           = false;
    @track _permPollingAttempts            = 0;
    _permConsentPollHandle                 = null;

    // ── Gating ───────────────────────────────────────────────────────────────
    /**
     * Section 4 only renders when the user answered "No" to "Is Current
     * Address Same As Permanent Address?" in Section 3 (Address Verification).
     * The Apex save path also skips the Permanent persistence when this is
     * false, so toggling back to "Yes" preserves data without blanking the row.
     */
    get showPermanentSection() {
        return this.showAddressVerification
            && this.isCurrentAddrSameAsPermanent === 'No';
    }

    // ── Address Document Type picklist (cross-section Aadhaar filter) ────────
    /**
     * If Current section is Aadhaar (selected — verified or not), Permanent
     * picker is unrestricted. Otherwise it's filtered to Aadhaar Card only
     * so the "one section must be Aadhaar" rule is enforced at selection time.
     */
    get permAddrDocumentTypeOptions() {
        // Aadhaar/Others on Current already satisfies the "at-least-one verification"
        // mandate → Permanent picker is unrestricted. Otherwise the Permanent picker
        // is locked to verification-only options to force compliance.
        let opts = VERIFICATION_ONLY_DOC_TYPES.has(this.addrDocumentType)
            ? ADDR_DOCUMENT_TYPE_OPTIONS
            : ADDR_DOCUMENT_TYPE_OPTIONS.filter(o => VERIFICATION_ONLY_DOC_TYPES.has(o.value));
        // Aadhaar can only be verified in one bucket per applicant 
        const aadhaarLockedByCurrent = this._isAadhaarVerified || this._isAadhaarLinkInFlight;
        if (aadhaarLockedByCurrent && this.permAddrDocumentType !== 'Aadhaar Card') {
            opts = opts.filter(o => o.value !== 'Aadhaar Card');
        }
        return opts;
    }
    get permAddrDocumentType() { return this.permKycInfoFieldValues.addrDocumentType || ''; }

    get isPermAddrDocumentTypeReadOnly() {
        if (this.isReadOnlyScreen) return true;
        return this.permHasAddressProofFile
            || this.permHasAddressProofFileFront
            || this.permHasAddressProofFileBack
            || this._permIsAadhaarVerified
            || this._permIsAadhaarLinkInFlight;
    }

    handlePermAddrDocumentTypeChange(event) {
        if (this.isReadOnlyScreen) return;
        const selected = event.target.value || '';
        const previous = this.permKycInfoFieldValues.addrDocumentType || '';

        const isVerificationOnly = VERIFICATION_ONLY_DOC_TYPES.has(selected);
        this.permKycInfoFieldValues = {
            ...this.permKycInfoFieldValues,
            addrDocumentType: selected,
            documentSideMode: isVerificationOnly ? SIDE_MODE_FULL : (this.permKycInfoFieldValues.documentSideMode || SIDE_MODE_FULL)
        };

        if (selected !== previous) {
            this.permExtractedDetails = null;
            this._permProcessedVersionIds = new Set();
            if (VERIFICATION_ONLY_DOC_TYPES.has(previous)) {
                this._permAadhaarVerificationType = '';
                this._permIsAadhaarVerified       = false;
                this._permIsAadhaarLinkInFlight   = false;
                this._permAadhaarLinkExpired      = false;
                this._permEKycLinkUrl             = '';
                this._stopPermConsentPolling();
            }
        }

    }

    // ── Side mode picker ─────────────────────────────────────────────────────
    get permDocumentSideMode()   { return this.permKycInfoFieldValues.documentSideMode || SIDE_MODE_FULL; }
    get permIsSideModeFull()     { return this.permDocumentSideMode === SIDE_MODE_FULL; }
    get permIsSideModeSide()     { return this.permDocumentSideMode === SIDE_MODE_SIDE; }
    get permShowDocumentSideMode() {
        return !!this.permAddrDocumentType && !VERIFICATION_ONLY_DOC_TYPES.has(this.permAddrDocumentType);
    }
    get permSideModeFullClass() {
        return 'kyc-radio-label' + (this.permIsSideModeFull ? ' kyc-radio-label-checked' : '');
    }
    get permSideModeSideClass() {
        return 'kyc-radio-label' + (this.permIsSideModeSide ? ' kyc-radio-label-checked' : '');
    }
    handlePermDocumentSideModeChange(event) {
        if (this.isReadOnlyScreen) return;
        const value = event.target.value;
        const cleared = (value === SIDE_MODE_SIDE)
            ? { addressProofFile: null }
            : { addressProofFileFront: null, addressProofFileBack: null };
        this.permKycInfoFieldValues = {
            ...this.permKycInfoFieldValues,
            documentSideMode: value,
            ...cleared
        };
    }

    // ── CKYC ID (Permanent doesn't have its own CKYC ID; it's an applicant-
    // level field, already captured in Section 1. Intentionally omitted.) ───

    // ── POA / POI toggles ────────────────────────────────────────────────────
    get permAddressProofToggle()  { return !!this.permKycInfoFieldValues.addressProofToggle;  }
    get permIdentityProofToggle() { return !!this.permKycInfoFieldValues.identityProofToggle; }
    get permShowProofToggles()    { return this.permHasAddressProofForVerification; }
    get permShowProofTogglesStandalone() {
        return this.permShowProofToggles;
    }
    get permProofTogglesWrapClass() {
        return this.permAddrDocumentType === 'Aadhaar Card'
            ? 'kyc-field-wrap kyc-field-wrap-full'
            : 'kyc-field-wrap';
    }

    handlePermAddressProofToggleChange(event) {
        if (this.isReadOnlyScreen) return;
        this.permKycInfoFieldValues = {
            ...this.permKycInfoFieldValues,
            addressProofToggle: !!event.target.checked
        };
        this._persistDirtyStateToStorage();
    }
    handlePermIdentityProofToggleChange(event) {
        if (this.isReadOnlyScreen) return;
        this.permKycInfoFieldValues = {
            ...this.permKycInfoFieldValues,
            identityProofToggle: !!event.target.checked
        };
        this._persistDirtyStateToStorage();
    }

    // ── File slots (Full / Front / Back) ─────────────────────────────────────
    get permAddressProofFileElement()       { return this.permKycInfoFieldValues.addressProofFile      || null; }
    get permAddressProofFileFrontElement()  { return this.permKycInfoFieldValues.addressProofFileFront || null; }
    get permAddressProofFileBackElement()   { return this.permKycInfoFieldValues.addressProofFileBack  || null; }

    get permHasAddressProofFile()       { return !!this.permAddressProofFileName; }
    get permHasAddressProofFileFront()  { return !!this.permAddressProofFileFrontName; }
    get permHasAddressProofFileBack()   { return !!this.permAddressProofFileBackName; }
    get permNoAddressProofFile()        { return !this.permHasAddressProofFile; }
    get permNoAddressProofFileFront()   { return !this.permHasAddressProofFileFront; }
    get permNoAddressProofFileBack()    { return !this.permHasAddressProofFileBack; }

    get permShowAddressProofUpload() {
        if (!this.permAddrDocumentType) return false;
        if (VERIFICATION_ONLY_DOC_TYPES.has(this.permAddrDocumentType)) return false;
        return this.permIsSideModeFull;
    }
    get permShowAddressProofUploadSide() {
        return !!this.permAddrDocumentType
            && !VERIFICATION_ONLY_DOC_TYPES.has(this.permAddrDocumentType)
            && this.permIsSideModeSide;
    }
    get showPermDocsRightColumn() {
        return this.permShowAddressProofUpload || this.permShowAddressProofUploadSide;
    }
    get permAddressDocsLayoutClass() {
        return this.showPermDocsRightColumn
            ? 'kyc-docs-two-col kyc-docs-two-col--dynamic kyc-docs-two-col--split'
            : 'kyc-docs-two-col kyc-docs-two-col--dynamic';
    }

    get permAddressProofFileName()      { return this._fileLabel(this.permAddressProofFileElement); }
    get permAddressProofFileFrontName() { return this._fileLabel(this.permAddressProofFileFrontElement); }
    get permAddressProofFileBackName()  { return this._fileLabel(this.permAddressProofFileBackElement); }

    get permAddressProofContentDocumentId()      { return this._fileContentDocumentId(this.permAddressProofFileElement); }
    get permAddressProofFrontContentDocumentId() { return this._fileContentDocumentId(this.permAddressProofFileFrontElement); }
    get permAddressProofBackContentDocumentId()  { return this._fileContentDocumentId(this.permAddressProofFileBackElement); }

    get permAddressProofFileType()      { return this._fileExtension(this.permAddressProofFileElement); }
    get permAddressProofFrontFileType() { return this._fileExtension(this.permAddressProofFileFrontElement); }
    get permAddressProofBackFileType()  { return this._fileExtension(this.permAddressProofFileBackElement); }
    get permAddressProofPanelUploadDisabled()      { return this.isReadOnlyScreen || this.permHasAddressProofFile; }
    get permAddressProofFrontPanelUploadDisabled() { return this.isReadOnlyScreen || this.permHasAddressProofFileFront; }
    get permAddressProofBackPanelUploadDisabled()  { return this.isReadOnlyScreen || this.permHasAddressProofFileBack; }
    get permAddressProofPanelFiles() {
        return this._entityDocPanelFilesView(
            this.permAddressProofFileElement,
            this._permKycInfoFileUploadRecordId,
            'perm-address-proof',
            'Upload Address Proof'
        );
    }
    get permAddressProofFrontPanelFiles() {
        return this._entityDocPanelFilesView(
            this.permAddressProofFileFrontElement,
            this._permKycInfoFileUploadRecordId,
            'perm-address-proof-front',
            'Upload Front'
        );
    }
    get permAddressProofBackPanelFiles() {
        return this._entityDocPanelFilesView(
            this.permAddressProofFileBackElement,
            this._permKycInfoFileUploadRecordId,
            'perm-address-proof-back',
            'Upload Back'
        );
    }

    get permKycInfoFileUploadRecordId() { return this._permKycInfoFileUploadRecordId; }
    get permFileUploadDisabled()        { return !this._permKycInfoFileUploadRecordId || this.isReadOnlyScreen; }
    // Permanent twin of fileUploadPreparing (see above).
    get permFileUploadPreparing()       { return !this.isReadOnlyScreen && !this._permKycInfoFileUploadRecordId; }

    async handlePermAddressProofUploadRequest() {
        await this._openPermAddressAdvancedUpload('full');
    }
    async handlePermAddressProofFrontUploadRequest() {
        await this._openPermAddressAdvancedUpload('front');
    }
    async handlePermAddressProofBackUploadRequest() {
        await this._openPermAddressAdvancedUpload('back');
    }

    async _openPermAddressAdvancedUpload(slot) {
        if (this.isReadOnlyScreen) return;
        const normalizedSlot = this._normalizePermAddressUploadSlot(slot);
        if (normalizedSlot === 'front' && this.permHasAddressProofFileFront) {
            this._toast('Document already uploaded', 'Remove the current front file before uploading again.', 'warning');
            return;
        }
        if (normalizedSlot === 'back' && this.permHasAddressProofFileBack) {
            this._toast('Document already uploaded', 'Remove the current back file before uploading again.', 'warning');
            return;
        }
        if (normalizedSlot === 'full' && this.permHasAddressProofFile) {
            this._toast('Document already uploaded', 'Remove the current address proof file before uploading again.', 'warning');
            return;
        }

        const checklistId = await this._ensurePermanentAddressChecklist();
        if (!checklistId) {
            this._toast('Permanent Address', 'Could not prepare upload. Please retry.', 'error');
            return;
        }
        this.permAddressActiveUploadSlot = normalizedSlot;
        this.permAddressActiveUploadChecklistId = checklistId;
        this.permAddressActiveMaxFiles = 1;
        this.permAddressActiveAllowedTypes = ENTITY_DV_FALLBACK_FILE_TYPES;
        this.showPermAddressMagicUpload = true;
    }

    handlePermAddressMagicUploadClose() {
        this._resetPermAddressMagicUploadState();
    }

    stopPropagationPermAddressDv(event) {
        event.stopPropagation();
    }

    handlePermAddressOverlayMouseDown(event) {
        this._permAddressOverlayMouseDownOnSelf = event.target === event.currentTarget;
    }

    handlePermAddressOverlayClick(event) {
        if (event.target === event.currentTarget && this._permAddressOverlayMouseDownOnSelf) {
            this._resetPermAddressMagicUploadState();
        }
        this._permAddressOverlayMouseDownOnSelf = false;
    }

    async handlePermAddressMagicUploadComplete(event) {
        const files = (event.detail && event.detail.files) || [];
        const slot = this._normalizePermAddressUploadSlot(this.permAddressActiveUploadSlot);
        this._resetPermAddressMagicUploadState();
        if (!files.length) return;

        const first = files[0];
        let contentDocumentId = first.documentId || first.contentDocumentId || null;
        if (!contentDocumentId && first.contentVersionId) {
            contentDocumentId = await this._resolveContentDocumentIdFromVersion(first.contentVersionId);
        }
        const fileData = {
            fileName: first.fileName || first.name || 'File attached',
            fileSize: first.size,
            contentVersionId: first.contentVersionId || null,
            contentDocumentId
        };

        if (slot === 'front') {
            this.permKycInfoFieldValues = { ...this.permKycInfoFieldValues, addressProofFileFront: fileData };
            this._runOcrExtractionForPerm('Front', fileData);
            return;
        }
        if (slot === 'back') {
            this.permKycInfoFieldValues = { ...this.permKycInfoFieldValues, addressProofFileBack: fileData };
            this._runOcrExtractionForPerm('Back', fileData);
            return;
        }
        this.permKycInfoFieldValues = { ...this.permKycInfoFieldValues, addressProofFile: fileData };
        this._runOcrExtractionForPerm('Full', fileData);
    }

    async handlePermAddressPanelFilePreview(event) {
        const detail = event.detail || {};
        const slot = this._normalizePermAddressUploadSlot(detail.sectionKey);
        const fileElement = slot === 'front'
            ? this.permAddressProofFileFrontElement
            : slot === 'back'
                ? this.permAddressProofFileBackElement
                : this.permAddressProofFileElement;
        const fallbackFileName = slot === 'front'
            ? 'Upload Front'
            : slot === 'back'
                ? 'Upload Back'
                : 'Upload Address Proof';
        const contentVersionId = detail.contentVersionId || fileElement?.contentVersionId || null;
        const fileName = detail.fileName || this._fileLabel(fileElement) || fallbackFileName;
        const fileExtension =
            detail.fileType
            || this._fileExtension(fileElement)
            || this._fileExtension({ fileName })
            || '';

        if (contentVersionId) {
            this.entityPreviewContentVersionId = contentVersionId;
            this.entityPreviewFileName = fileName;
            this.entityPreviewFileExtension = fileExtension;
            this.showEntityEmbedFilePreview = true;
            return;
        }

        let contentDocumentId = detail.contentDocumentId || this._fileContentDocumentId(fileElement) || null;
        if (!contentDocumentId && fileElement?.contentVersionId) {
            contentDocumentId = await this._resolveContentDocumentIdFromVersion(fileElement.contentVersionId);
        }
        if (!contentDocumentId) return;
        this.previewContentDocumentId = contentDocumentId;
        this.previewFileType = fileExtension || null;
        this.showFilePreviewer = true;
    }

    handlePermAddressPanelFileDelete(event) {
        const slot = this._normalizePermAddressUploadSlot(event?.detail?.sectionKey);
        if (slot === 'front') {
            this.handlePermAddressProofFrontRemove();
            return;
        }
        if (slot === 'back') {
            this.handlePermAddressProofBackRemove();
            return;
        }
        this.handlePermAddressProofRemove();
    }

    _normalizePermAddressUploadSlot(slot) {
        if (slot === 'front' || slot === 'permAddressProofFront') return 'front';
        if (slot === 'back' || slot === 'permAddressProofBack') return 'back';
        return 'full';
    }

    _resetPermAddressMagicUploadState() {
        this.showPermAddressMagicUpload = false;
        this.permAddressActiveUploadChecklistId = null;
        this.permAddressActiveMaxFiles = 1;
        this.permAddressActiveAllowedTypes = ENTITY_DV_FALLBACK_FILE_TYPES;
        this.permAddressActiveUploadSlot = null;
        this._permAddressOverlayMouseDownOnSelf = false;
    }

    handlePermAddressProofRemove() {
        if (this.isReadOnlyScreen) return;
        const removed = this.permKycInfoFieldValues.addressProofFile;
        this.permKycInfoFieldValues = { ...this.permKycInfoFieldValues, addressProofFile: null };
        this._resetPermExtractedStateAfterFileRemoval(removed);
    }
    handlePermAddressProofFrontRemove() {
        if (this.isReadOnlyScreen) return;
        const removed = this.permKycInfoFieldValues.addressProofFileFront;
        this.permKycInfoFieldValues = { ...this.permKycInfoFieldValues, addressProofFileFront: null };
        this._resetPermExtractedStateAfterFileRemoval(removed);
    }
    handlePermAddressProofBackRemove() {
        if (this.isReadOnlyScreen) return;
        const removed = this.permKycInfoFieldValues.addressProofFileBack;
        this.permKycInfoFieldValues = { ...this.permKycInfoFieldValues, addressProofFileBack: null };
        this._resetPermExtractedStateAfterFileRemoval(removed);
    }

    _resetPermExtractedStateAfterFileRemoval(removedFile) {
        if (this._permKycInfoFileUploadRecordId && removedFile) {
            this._dispatchServerSideFileDeleteForPerm(removedFile);
        }
        if (this.permHasAddressProofFile || this.permHasAddressProofFileFront || this.permHasAddressProofFileBack) {
            return;
        }
        this.permExtractedDetails        = null;
        this._permProcessedVersionIds    = new Set();
        this.permKycInfoFieldValues = {
            ...this.permKycInfoFieldValues,
            addressProofToggle  : null,
            identityProofToggle : null
        };
        this._persistDirtyStateToStorage();
    }

    _dispatchServerSideFileDeleteForPerm(fileMeta) {
        savePageData({
            apexClassName : APEX_CLASS,
            apexMethodName: APEX_METHOD_DELETE_FILE,
            recordId      : this._recordId,
            params        : {
                checklistRecordId : this._permKycInfoFileUploadRecordId,
                contentDocumentId : fileMeta.contentDocumentId || null,
                contentVersionId  : fileMeta.contentVersionId  || null,
                applicantId       : this._applicantId || null
            }
        }).catch(err => {
            console.error('wheelsIndividualKYCMasterPage: deletePermanentAddressKycFile', err);
        });
    }

    // ── Aadhaar visual picker (Permanent) ────────────────────────────────────
    get permShowAadhaarVerificationPicker() {
        return this.permAddrDocumentType === 'Aadhaar Card';
    }
    get permAadhaarVerificationType() { return this._permAadhaarVerificationType; }
    get permIsAadhaarVerified()       { return this._permIsAadhaarVerified; }
    get permAadhaarLinkExpired()      { return this._permAadhaarLinkExpired; }
    get permShowAadhaarExpiredBanner() {
        return this._permAadhaarLinkExpired && !this._permIsAadhaarVerified;
    }

    get permAadhaarVerificationTiles() {
        const locked = this._permIsAadhaarVerified
            || this.isReadOnlyScreen
            || this._permIsAadhaarLinkInFlight;
        const ekycInFlight = this._permIsAadhaarLinkInFlight && !this._permIsAadhaarVerified;
        return AADHAAR_VERIFICATION_METHODS.map(m => {
            const isSelected       = m.id === this._permAadhaarVerificationType;
            const showVerifiedPill = isSelected && this._permIsAadhaarVerified;
            const showInfoIcon     = isSelected && m.id === 'eKYC_OTP' && ekycInFlight;
            const showCheck        = isSelected && !showVerifiedPill;
            const tileClass = 'kyc-aadhaar-tile'
                + (isSelected ? ' kyc-aadhaar-tile-selected' : '')
                + (locked ? ' kyc-aadhaar-tile-locked' : '');
            return {
                ...m,
                isSelected,
                tileClass,
                ariaPressed: isSelected ? 'true' : 'false',
                showCheck,
                showInfoIcon,
                showVerifiedPill,
                infoTooltip: showInfoIcon
                    ? 'eKYC OTP Verification in progress. Click "View eKYC Link" for status.'
                    : ''
            };
        });
    }

    get permAadhaarVerifyDisabled() {
        return !this._permAadhaarVerificationType
            || this._permIsAadhaarVerified
            || this.isReadOnlyScreen;
    }
    get permAadhaarVerifyButtonClass() {
        return 'kyc-aadhaar-verify-btn'
            + (this.permAadhaarVerifyDisabled ? ' kyc-aadhaar-verify-btn-disabled' : '');
    }
    get permAadhaarVerifyButtonLabel() {
        const isOthers = this.permAddrDocumentType === 'Others';
        if (this._permIsAadhaarVerified)     return isOthers ? 'Verified' : 'Aadhaar Verified';
        if (this._permIsAadhaarLinkInFlight) return 'View eKYC Link';
        return isOthers ? 'Verify' : 'Verify Aadhaar';
    }

    // ── Others Verification (dropdown) — Permanent mirror ────────────────────
    get permShowOtherVerificationPicker() {
        return this.permAddrDocumentType === 'Others';
    }
    get permOtherVerificationMethodOptions() { return OTHER_VERIFICATION_METHOD_OPTIONS; }
    get permOtherVerificationMethod()        { return this._permAadhaarVerificationType || ''; }
    get isPermOtherVerificationDisabled() {
        return this.isReadOnlyScreen
            || this._permIsAadhaarVerified
            || this._permIsAadhaarLinkInFlight;
    }

    handlePermOtherVerificationMethodChange(event) {
        if (this.isPermOtherVerificationDisabled) return;
        this._permAadhaarVerificationType = event.detail?.value || '';
    }

    handlePermAadhaarMethodSelect(event) {
        if (this.isReadOnlyScreen
            || this._permIsAadhaarVerified
            || this._permIsAadhaarLinkInFlight) return;
        const methodId = event.currentTarget?.dataset?.methodId || '';
        if (!methodId) return;
        this._permAadhaarVerificationType = methodId;
    }

    async handlePermAadhaarVerifyClick() {
        if (this.permAadhaarVerifyDisabled) return;

        const method  = this._permAadhaarVerificationType;
        const action  = AADHAAR_METHOD_TO_ACTION[method];
        if (!action) return;

        if (action === APEX_AADHAAR_INIT_EKYC_OTP
            && this._permIsAadhaarLinkInFlight
            && this._permEKycLinkUrl) {
            this.showPermEkycLinkModal = true;
            if (!this._permIsPollingConsent) this._startPermConsentPolling();
            return;
        }

        // The Aadhaar Apex actions require a checklistRecordId, so create
        // the Permanent checklist row if it doesn't exist yet.
        if (!this._permKycInfoFileUploadRecordId) {
            await this._ensurePermanentAddressChecklist();
        }
        if (!this._permKycInfoFileUploadRecordId) {
            this._toast('Aadhaar Verification', 'Could not initialise Permanent address record. Please retry.', 'error');
            return;
        }

        this._beginPermAadhaarProgress(method);

        try {
            const response = await savePageData({
                apexClassName : APEX_AADHAAR_CLASS,
                apexMethodName: action,
                recordId      : this._recordId,
                params        : {
                    applicantId       : this._applicantId || null,
                    checklistRecordId : this._permKycInfoFileUploadRecordId,
                    addressType       : ADDR_TYPE_PERMANENT
                }
            });
            if (!response?.isSuccess) {
                this._failPermAadhaarProgress(response?.message || 'Aadhaar verification failed.');
                return;
            }

            if (action === APEX_AADHAAR_INIT_EKYC_OTP) {
                this._permEKycLinkUrl        = response.kycUrl || '';
                this._permEKycLinkCopied     = false;
                this._permAadhaarLinkExpired = false;
                this._permIsAadhaarLinkInFlight = true;
                await this._walkAadhaarProgressToSuccess();
                this.showPermEkycLinkModal   = true;
                if (response.aadhaarVerified === true) {
                    await this._handlePermAadhaarConsentReceived();
                } else {
                    this._startPermConsentPolling();
                }
            } else {
                this._completePermAadhaarVerification();
            }
        } catch (err) {
            this._failPermAadhaarProgress(err?.message || 'Aadhaar verification failed.');
        }
    }

    _beginPermAadhaarProgress(method) {
        this.showIntegrationProgressModal            = true;
        this.integrationProgressModalStatus          = 'loading';
        this.integrationProgressModalHeader          = 'Aadhaar Verification';
        this.integrationProgressModalStages          = method === 'eKYC_OTP'
            ? ['GENERATE OTP API', 'SMS GATEWAY CALL API']
            : AADHAAR_STUB_STAGES;
        this.integrationProgressModalCurrentStageIdx = 0;
        this.integrationProgressModalErrorMessage    = '';
    }
    _failPermAadhaarProgress(message) {
        this.integrationProgressModalStatus       = 'error';
        this.integrationProgressModalErrorMessage = message;
    }

    async _handlePermAadhaarConsentReceived() {
        this._stopPermConsentPolling();
        this._permIsAadhaarLinkInFlight = false;
        this._permAadhaarLinkExpired    = false;
        this.showPermEkycLinkModal      = false;
        // Cosmetic progress visualization driven by extractUIDAIOTPAPI LWC
        await invokeHandler('extractUIDAIOTPAPI', 'onOtpVerified', this);
        await this._loadPageData(true);
        this._completePermAadhaarVerification();
    }

    _handlePermAadhaarLinkExpired() {
        this._stopPermConsentPolling();
        this._permIsAadhaarLinkInFlight = false;
        this._permAadhaarLinkExpired    = true;
        this._permIsAadhaarVerified     = false;
        this._permEKycLinkUrl           = '';
        this.showPermEkycLinkModal      = false;
        if (this.showIntegrationProgressModal) {
            this._failPermAadhaarProgress('Aadhaar eKYC link expired. Please request a new link.');
            setTimeout(() => this._hideProgress(), 1500);
        }
    }

    _applyPermAadhaarVerifyState(state) {
        this._permAadhaarVerificationType = '';
        this._permIsAadhaarVerified = false;
        this._permIsAadhaarLinkInFlight = false;
        this._permAadhaarLinkExpired = false;
        this._permEKycLinkUrl = '';
        this._permEKycLinkCopied = false;
        this.showPermEkycLinkModal = false;
        if (!state) return;
        const methodLabelToTileId = {
            'eKYC OTP Verification' : 'eKYC_OTP',
            'Biometric Verification': 'Biometric',
            'Video KYC Verification': 'VideoKYC',
            'Digilocker Verification': 'Digilocker',
            'Offline Aadhaar XML'   : 'OfflineXML'
        };
        if (state.verificationMethod && methodLabelToTileId[state.verificationMethod]) {
            this._permAadhaarVerificationType = methodLabelToTileId[state.verificationMethod];
        }
        this._permAadhaarLinkExpired = state.linkExpired === true;
        if (state.aadhaarVerified === true) {
            this._permIsAadhaarVerified     = true;
            this._permIsAadhaarLinkInFlight = false;
            return;
        }
        if (state.linkSent === true && state.kycUrl) {
            this._permEKycLinkUrl           = state.kycUrl;
            this._permIsAadhaarLinkInFlight = true;
            this._startPermConsentPolling();
        }
    }

    _completePermAadhaarVerification() {
        this._permIsAadhaarVerified = true;
        if (!this.permExtractedDetails) {
            this.permExtractedDetails = { kycType: 'Aadhar' };
        }
        this._applyPermDefaultProofTogglesIfUnset();
        if (this.showIntegrationProgressModal) {
            this.integrationProgressModalStatus = 'success';
            setTimeout(() => this._hideProgress(), 800);
        }
    }

    _applyPermDefaultProofTogglesIfUnset() {
        const v = this.permKycInfoFieldValues || {};
        const updates = {};
        if (v.addressProofToggle === undefined || v.addressProofToggle === null) {
            updates.addressProofToggle = true;
        }
        if (v.identityProofToggle === undefined || v.identityProofToggle === null) {
            updates.identityProofToggle = true;
        }
        if (Object.keys(updates).length > 0) {
            this.permKycInfoFieldValues = { ...this.permKycInfoFieldValues, ...updates };
            this._persistDirtyStateToStorage();
        }
    }

    // ── Permanent eKYC OTP polling ──────────────────────────────────────────
    get permEKycLinkUrl()         { return this._permEKycLinkUrl; }
    get permIsPollingConsent()    { return this._permIsPollingConsent; }
    get permPollingStatusLabel() {
        if (!this._permIsPollingConsent) return '';
        return 'Waiting for customer to complete Aadhaar verification…';
    }
    get permCopyLinkButtonLabel() { return this._permEKycLinkCopied ? 'Link Copied' : 'Copy Link'; }
    get permCopyLinkButtonIcon()  { return this._permEKycLinkCopied ? 'utility:check' : 'utility:copy'; }

    _startPermConsentPolling() {
        this._stopPermConsentPolling();
        if (!this._applicantId) return;
        this._permIsPollingConsent = true;
        this._permPollingAttempts  = 0;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._permConsentPollHandle = setInterval(() => this._pollPermConsent(), EKYC_POLL_INTERVAL_MS);
    }
    _stopPermConsentPolling() {
        if (this._permConsentPollHandle) {
            clearInterval(this._permConsentPollHandle);
            this._permConsentPollHandle = null;
        }
        this._permIsPollingConsent = false;
    }
    async _pollPermConsent() {
        if (!this._applicantId) {
            this._stopPermConsentPolling();
            return;
        }
        this._permPollingAttempts += 1;
        if (this._permPollingAttempts > EKYC_POLL_MAX_ATTEMPTS) {
            this._stopPermConsentPolling();
            return;
        }
        try {
            const response = await savePageData({
                apexClassName : APEX_AADHAAR_CLASS,
                apexMethodName: APEX_AADHAAR_POLL_CONSENT,
                recordId      : this._recordId,
                params        : {
                    applicantId       : this._applicantId,
                    checklistRecordId : this._permKycInfoFileUploadRecordId || null,
                    addressType       : ADDR_TYPE_PERMANENT
                }
            });
            if (!response?.isSuccess) return;
            if (response.linkExpired === true) {
                this._handlePermAadhaarLinkExpired();
                return;
            }
            if (response.aadhaarVerified === true) {
                await this._handlePermAadhaarConsentReceived();
            }
        } catch (e) {
            // Soak transient poll errors; the next tick will retry.
        }
    }
    handlePermCheckConsentStatus() { this._pollPermConsent(); }
    handlePermCopyEkycLink() {
        const url = this._permEKycLinkUrl;
        if (!url) return;
        const dispatch = (ok) => {
            this._permEKycLinkCopied = ok;
            if (ok) setTimeout(() => { this._permEKycLinkCopied = false; }, 2500);
        };
        if (navigator?.clipboard?.writeText) {
            navigator.clipboard.writeText(url).then(() => dispatch(true)).catch(() => dispatch(false));
        } else {
            try {
                const ta = document.createElement('textarea');
                ta.value = url;
                ta.style.position = 'fixed';
                ta.style.left = '-9999px';
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
                dispatch(true);
            } catch (e) {
                dispatch(false);
            }
        }
    }
    handleClosePermEkycLinkModal() { this.showPermEkycLinkModal = false; }

    // ── Extracted details (Permanent OCR / Aadhaar snapshot) ─────────────────
    get permExtractedDocLabel() {
        return this.permAddrDocumentType
            ? `Permanent Address KYC — ${this.permAddrDocumentType}`
            : 'Permanent Address KYC';
    }
    get permExtractedDocType() { return this.permAddrDocumentType || 'Document'; }

    handlePermExtractedDetailsChange(event) {
        const detail = event?.detail || {};
        if (!detail.field) return;
        const allValues = detail.allValues || {};
        this.permExtractedDetails = { ...(this.permExtractedDetails || {}), ...allValues };
    }

    // ── Section gating for Permanent panels & banners ───────────────────────
    get permHasAddressProofForVerification() {
        if (!this.permAddrDocumentType) return false;
        if (VERIFICATION_ONLY_DOC_TYPES.has(this.permAddrDocumentType)) return this._permIsAadhaarVerified;
        return this.permIsSideModeFull
            ? this.permHasAddressProofFile
            : (this.permHasAddressProofFileFront && this.permHasAddressProofFileBack);
    }
    get showPermExtractedDetails() {
        return this.isExtractingPermanent || !!this.permExtractedDetails;
    }
    get showPermStandaloneExtractedDetails() {
        return this.showPermExtractedDetails;
    }

    // ── Permanent checklist ensure ───────────────────────────────────────────
    async _ensurePermanentAddressChecklist() {
        if (!this._applicantId) return null;
        if (this._permKycInfoFileUploadRecordId) return this._permKycInfoFileUploadRecordId;
        try {
            const response = await savePageData({
                apexClassName : APEX_CLASS,
                apexMethodName: APEX_METHOD_CREATE_PERMANENT,
                recordId      : this._recordId,
                params        : { applicantId: this._applicantId }
            });
            if (response?.isSuccess && response.checklistRecordId) {
                this._permKycInfoFileUploadRecordId = response.checklistRecordId;
            }
            return this._permKycInfoFileUploadRecordId;
        } catch (e) {
            console.error('wheelsIndividualKYCMasterPage: ensurePermanentAddressChecklist', e);
            return null;
        }
    }

    // ── OCR (Permanent Address KYC) ──────────────────────────────────────────
    async _runOcrExtractionForPerm(side, fileMeta) {
        if (this.isReadOnlyScreen) return;
        if (!fileMeta) return;

        const docType = this.permAddrDocumentType || '';
        if (!OCR_SUPPORTED_DOC_TYPES.has(docType)) {
            return;
        }
        const versionId = fileMeta.contentVersionId;
        if (!versionId || this._permProcessedVersionIds.has(versionId)) {
            return;
        }

        this.isExtractingPermanent = true;
        this._showProgress(0, '', 'loading');

        try {
            this._showProgress(1, '', 'loading');
            const response = await savePageData({
                apexClassName : APEX_EXTRACT_CLASS,
                apexMethodName: APEX_EXTRACT_METHOD,
                recordId      : this._recordId,
                params        : {
                    applicantId       : this._applicantId || null,
                    documentType      : docType,
                    addressType       : ADDR_TYPE_PERMANENT,
                    checklistRecordId : this._permKycInfoFileUploadRecordId || null,
                    documentSide      : side,
                    addressProofFile  : {
                        contentDocumentId: fileMeta.contentDocumentId,
                        contentVersionId : fileMeta.contentVersionId,
                        fileName         : fileMeta.fileName
                    }
                }
            });

            if (!response?.isSuccess) {
                const msg = response?.message || 'Failed to extract document details.';
                this._showProgress(0, msg, 'error');
                this._toast('Extraction Failed', msg, 'error');
                return;
            }

            this._permProcessedVersionIds.add(versionId);
            this._showProgress(2, '', 'loading');

            // Non-blank-wins merge (see current-bucket equivalent above).
            const extracted = response.extractedDetails || {};
            const merged = { ...(this.permExtractedDetails || {}) };
            Object.keys(extracted).forEach((k) => {
                const v = extracted[k];
                if (v !== null && v !== undefined && String(v).trim() !== '') {
                    merged[k] = v;
                }
            });
            this.permExtractedDetails = merged;

            this._applyPermDefaultProofTogglesIfUnset();

            this._showProgress(3, '', 'success');
            setTimeout(() => this._hideProgress(), 800);
        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Unexpected error during extraction.';
            this._showProgress(0, msg, 'error');
            this._toast('Extraction Error', msg, 'error');
        } finally {
            this.isExtractingPermanent = false;
        }
    }
}