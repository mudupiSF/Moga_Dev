import { LightningElement, api, track } from 'lwc';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';
import savePANDetails from '@salesforce/apex/ApplicantBasicDetailsCaptureController.savePANDetails';
import getAgentBranchName from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getAgentBranchName';
import getAccountName from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getAccountName';
import generatePhoneOTP from '@salesforce/apex/SendPhoneOTPAPIController.generateOTP';
import getConsentSiteUrl from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getConsentSiteUrl';
import recordConsentFormSent from '@salesforce/apex/ApplicantBasicDetailsCaptureController.recordConsentFormSent';
import getApplicantConsentFlags from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getApplicantConsentFlags';
import generateEmailOTP from '@salesforce/apex/SendEmailOTPAPIController.generateOTP';
import getIntegrationMaster from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getIntegrationMaster';
import getNiConstitution from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getNiConstitution';
import getNiMinShareHoldings from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getNiMinShareHoldings';
import updateDocumentChecklist from '@salesforce/apex/ApplicantBasicDetailsCaptureController.updateDocumentChecklist';
import toggleDocumentActivation from '@salesforce/apex/DocumentChecklistToggleController.toggleDocumentActivation';
import deactivateDocument from '@salesforce/apex/DocumentChecklistToggleController.deactivateDocument';
import markPanVerified from '@salesforce/apex/documentVerificationController.markPanVerified';
import getUserSessionId from '@salesforce/apex/embedCustomFileUploadController.getUserSessionId';
//import createCurrentAddressChecklist from '@salesforce/apex/KYCInfoController.createCurrentAddressChecklist';
import createCustomerImageChecklist from '@salesforce/apex/KYCInfoController.createCustomerImageChecklist';
import ensureGuarantorCloneShell from '@salesforce/apex/ApplicantCloneService.ensureGuarantorCloneShell';
import activateSubApplicantShell from '@salesforce/apex/ApplicantSubService.activateSubApplicantShell';
import setPrimaryApplicant from '@salesforce/apex/ApplicantSubService.setPrimaryApplicant';
import getBeneficiaryShareholdingTotal from '@salesforce/apex/ApplicantBasicDetailsCaptureController.getBeneficiaryShareholdingTotal';
import { invokeHandler } from 'c/clientLayerHelper';
import SPECIAL_ICONS from '@salesforce/resourceUrl/special_icons';
import {
    PRODUCT_TYPE_OPTIONS_ALL,
    CUSTOMER_TYPE_OPTIONS,
    SEGMENT_OPTIONS,
    VEHICLE_TYPE_OPTIONS_DEFAULT,
    VEHICLE_TYPE_OPTIONS_TWO_WHEELER
} from './pickListValuesHelper';
import { computeSectionVisibility, areAllSectionsComplete } from './sectionProgressHelper';

const APEX_CLASS = 'ApplicantBasicDetailsCaptureController';
const GETAPPLICANTPAGEDATA_METHOD = 'getApplicantPageData';
const SAVEAPPLICANTPAGEDATA_METHOD = 'saveApplicantPageData';

const STAGE_LEAD_DETAILS = 'Basic Details';
const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const INTEGRATION_PROGRESS_EVENT = 'integrationprogressupdate';

const PAN_MANDATORY_INCOME_THRESHOLD = 400000;
const PAN_MANDATORY_LOAN_THRESHOLD   = 1000000;

const PAN_MANDATORY_RULE = {
    rule: {
        operator: 'OR',
        conditions: [
            {
                operator: 'AND',
                conditions: [
                    { field: 'incomeAvailable', value: 'Yes' },
                    { field: 'annualIncome',    value: PAN_MANDATORY_INCOME_THRESHOLD, operator: 'GT' }
                ]
            },
            { field: 'requiredLoanAmount', value: PAN_MANDATORY_LOAN_THRESHOLD, operator: 'GT' },
            { field: 'isNonIndividualApplicant', value: true, operator: 'EQ' }
        ]
    },
    message: 'PAN is mandatory when Annual Income exceeds ₹4 Lakhs or Required Loan Amount exceeds ₹10 Lakhs or Non-individual applicant',
    icon: 'utility:warning'
};

/** Strict regex used to gate Required Loan Amount: optional decimal with max 2 places. */
const REQUIRED_LOAN_AMOUNT_REGEX = /^\d+(\.\d{1,2})?$/;

/** Indian mobile numbers: 10 digits, first digit between 6 and 9. */
const MOBILE_REGEX = /^[6-9]\d{9}$/;

/** RFC-friendly email validator (intentionally permissive on subdomain length). */
const EMAIL_REGEX = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;

const DOB_MIN_AGE_YEARS = 18;
const DOB_MAX_AGE_YEARS = 80;

const CONSENT_POLL_INTERVAL_MS = 5000;
const CONSENT_POLL_MAX_ATTEMPTS = 60;

const PURPOSE_OF_PURCHASE_OPTS = [
    { label: 'Personal',   value: 'Personal' },
    { label: 'Commercial', value: 'Commercial' }
];
const ACCOUNT_DISPLAY_INFO  = { primaryField: 'Name' };
const ACCOUNT_MATCHING_INFO = { primaryField: { fieldPath: 'Name' } };

const PROFILE_TYPE_OPTS = [
    { label: 'BANK EMPLOYEE',           value: 'BANK EMPLOYEE' },
    { label: 'CONTRACT WORKER',         value: 'CONTRACT WORKER' },
    { label: 'DAILY WAGES',             value: 'DAILY WAGES' },
    { label: 'DOCK AND MINE WORKER',    value: 'DOCK AND MINE WORKER' },
    { label: 'EDITOR',                  value: 'EDITOR' },
    { label: 'GARAGE MECHANIC',         value: 'GARAGE MECHANIC' },
    { label: 'GARDENER',                value: 'GARDENER' },
    { label: 'GOVERNMENT SERVANT',      value: 'GOVERNMENT SERVANT' },
    { label: 'INTELLIGENCE PERSONNEL',  value: 'INTELLIGENCE PERSONNEL' },
    { label: 'JOB WORKER',              value: 'JOB WORKER' },
    { label: 'LAB TECHNICIAN',          value: 'LAB TECHNICIAN' },
    { label: 'MEDICAL - REP',           value: 'MEDICAL - REP' },
    { label: 'POLICE',                  value: 'POLICE' },
    { label: 'SOFTWARE ENGINEER',       value: 'SOFTWARE ENGINEER' }
];

const MARITAL_STATUS_OPTS = [
    { label: 'Married',            value: 'MARRIED' },
    { label: 'Unmarried',          value: 'Unmarried' },
    { label: 'Divorced',           value: 'Divorced' },
    { label: 'Widowed',            value: 'Widowed' }
];
const RESIDENCE_COUNTRY_OPTS = [
    { label: 'India',              value: 'India' },
    { label: 'Non-India Resident', value: 'Non-India Resident' }
];

const hasVal = (v) => {
    if (v == null) return false;
    if (typeof v === 'object' && v.fileName !== undefined) return !!v.fileName;
    return String(v).trim() !== '';
};

const isNonIndividualApplicationType = (value) => {
    const v = (value || '').trim();
    return v === 'Non Individual' || v === 'NI' || v === 'Non-Individual';
};

const isTwoWheelerProductType = (productType) => {
    const pt = (productType || '').trim();
    return pt === '2W' || pt === 'Two Wheeler' || pt === 'Two Wheeler (TW)' || pt === 'TW';
};

const isCvProductType = (productType) => {
    const pt = (productType || '').trim().toLowerCase();
    if (!pt) return false;
    // 'cv' is the umbrella Product__c code emitted by the Intermediate Page;
    // SCV/LCV/MHCE/CE are the specific sub-types used elsewhere.
    return pt === 'cv' || pt === 'scv' || pt === 'lcv' || pt === 'mhce' || pt === 'ce'
        || pt.includes('commercial vehicle')
        || pt.includes('commercial equipment');
};

/** Formats a numeric string in Indian grouping (e.g. 1,23,45,678.90).
 *  Returns the raw value when it isn't a parseable number so user input isn't dropped. */
const formatIndianCurrency = (raw) => {
    if (raw === null || raw === undefined || raw === '') return '';
    const stripped = String(raw).replace(/,/g, '').trim();
    if (stripped === '') return '';
    if (!/^\d*\.?\d*$/.test(stripped)) return String(raw);
    const [intPartRaw, decPart] = stripped.split('.');
    const intPart = (intPartRaw || '').replace(/^0+(?=\d)/, '');
    if (intPart === '') {
        return decPart !== undefined ? `0.${decPart}` : '0';
    }
    const lastThree = intPart.slice(-3);
    const rest = intPart.slice(0, -3);
    const grouped = rest
        ? rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + lastThree
        : lastThree;
    return decPart !== undefined ? `${grouped}.${decPart}` : grouped;
};

/**
 * Format a landline number in Indian STD dialing format: (STD) - SUBSCRIBER
 * e.g. "02212345678" -> "(022) - 12345678". STD code is the leading 3 digits
 * (incl. leading 0) and the subscriber number is the following 8 digits.
 */
const formatIndianLandline = (raw) => {
    const digits = String(raw === null || raw === undefined ? '' : raw).replace(/\D/g, '').slice(0, 11);
    if (digits.length === 0) return '';
    const std = digits.slice(0, 3);
    const subscriber = digits.slice(3);
    return digits.length <= 3 ? `(${std})` : `(${std}) - ${subscriber}`;
};

/** Default Purpose of Purchase derived from the application's Product Type. */
const defaultPurposeOfPurchase = (productType) => {
    if (isCvProductType(productType)) return 'Commercial';
    const pt = (productType || '').trim().toLowerCase();
    if (!pt) return '';
    if (pt === 'pv' || pt === 'passenger vehicles' || pt === 'passenger vehicle'
        || pt === '4w' || pt === 'four wheeler' || pt === 'tw' || pt === '2w'
        || pt === 'two wheeler' || pt === 'pl' || pt === 'personal loan') {
        return 'Personal';
    }
    return '';
};

/** Beneficiary tabs use Applicant_Tab_Label__c tokens such as B1, B2, or a Beneficiary group phrase. */
const isBeneficiaryStagePhrase = (phrase) => {
    if (!phrase) return false;
    if (phrase.includes('Beneficiary')) return true;
    const token = phrase.split('_').pop() || '';
    return /^B/i.test(token) && !/^Borrower/i.test(token);
};

/** Keep only valid Product_Segment__c picklist API values (avoids label defaults like "Motorcycle"). */
const sanitizeSegmentValue = (val) => {
    if (!hasVal(val)) return '';
    const str = String(val).trim();
    const byValue = SEGMENT_OPTIONS.find((o) => o.value === str);
    if (byValue) return byValue.value;
    const byLabel = SEGMENT_OPTIONS.find((o) => o.label === str);
    return byLabel ? byLabel.value : '';
};

export default class ApplicantBasicDetailsCapture extends LightningElement {

    // ── @api props ────────────────────────────────────────────────────────────
    _recordId;
    _applicantId = null;
    _stagePhrase = '';
    _loadTimer = null;
    _loadSeq = 0;
    _applicantIdLoaded = null;

    @api get recordId() { return this._recordId; }
    set recordId(v) {
        this._recordId = v;
        this._schedulePageDataLoad();
    }

    @api get applicantId() { return this._applicantId; }
    set applicantId(v) {
        this._applicantId = v || null;
        this._schedulePageDataLoad();
    }

    /** Alias the cross-section client-layer handlers expect on ctx.
     *  Mirrors `applicantId` so existing handlers built for BorrowerMasterPage work unchanged. */
    get effectiveApplicantId() { return this._applicantId; }

    @api currentViewId;
    @api tab = '';
    _isStagePast = false;
    @track _isApplicantStageComplete = false;

    @api
    get isStagePast() {
        return this._isStagePast;
    }
    set isStagePast(value) {
        const next = value === true || value === 'true';
        this._isStagePast = next;
        this._applyReadOnlyScreen();
    }

    /** Read-only when the parent contract says we're past this stage OR when Apex confirms
     *  the applicant has already completed Basic Details (CMDT-driven stage gate). */
    get isReadOnlyScreen() {
        return this._isStagePast || this._isApplicantStageComplete;
    }

    /** Past / submitted stage — show ready (read-only) field display. */
    get showReadyUi() {
        return this.isReadOnlyScreen;
    }

    /** Active Basic Details — show editable inputs. */
    get isFieldEditable() {
        return !this.isReadOnlyScreen;
    }

    @api get stagePhrase() { return this._stagePhrase; }
    set stagePhrase(v) {
        this._stagePhrase = v || '';
        this._syncBeneficiaryApplicantFromContext();
    }

    @track docChecklistId = '';
    @track productType      = '';
    @track assetType      = '';
    @track applicationType  = '';
    @track customerType     = '';
    @track applicantEntityType    = '';
    @track entityName       = '';
    @track segment          = '';
    @track majorIndustry    = '';
    @track minorIndustry    = '';
    @track industryName     = '';
    @track industryCode     = '';
    @track beneficialOwnerCategory = '';
    @track relationshipWithEntity  = '';
    @track relationshipType        = '';
    @track poaHolder               = false;
    @track shareHolding            = '';
    @track shareHoldingValidationError = '';
    // Primary applicant question (top-level non-borrower only)
    @track isPrimary               = false;
    @track _showPrimaryQuestion    = false;
    @track primaryRoleLabel        = '';
    @track extractedPanCardNumberValidationError = '';
    @track copyToGuarantor = '';
    @track _isSubApplicant = false;

    _isBeneficiaryApplicant = false;
    _majorIndustryOptions = [];
    _minorIndustryOptionsMap = {};
    _industryNameOptions = [];
    _industryNameToCodeMap = {};
    _beneficialOwnerCategoryOptions = [];
    _relationshipWithEntityOptions = [];
    _relationshipTypeOptions = [];
    _entityTypeOptions = [];
    _evaluationTypeOptions = [];
    @track _customerTypeOptions = [];
    @track _incomeCategoryOptions = [];
    @track _genderOptions = [];
    @track numberOfVehicles = '';

    get isBeneficiaryApplicant() {
        return this._isBeneficiaryApplicant || isBeneficiaryStagePhrase(this.stagePhrase);
    }
    get isNonIndividualApplication() {
        return isNonIndividualApplicationType(this.applicationType);
    }
    get isIndividualApplicant() { return this.customerType == 'Individual'; }
    get isNonIndividualApplicant() { return this.customerType == 'Non-Individual'; }
    /** Individual sub-applicant (IN sub-guarantor / sub-beneficiary under an NI parent). */
    get isSubApplicant() { return this._isSubApplicant === true; }

    // ── Clone Applicant (NI Beneficiary → Guarantor) ──────────────────────────
    // Shown only for NI Beneficiary.
    get showCloneApplicantQuestion() {
        return this.isBeneficiaryApplicant && this.isNonIndividualApplicant && !this.isSubApplicant;
    }
    get showApplicationDetailsCard() {
        return true;
    }
    get isCopyToGuarantorYes() { return this.copyToGuarantor === 'Yes'; }
    get isCopyToGuarantorNo()  { return this.copyToGuarantor === 'No'; }
    get copyToGuarantorDisplay() {
        if (this.copyToGuarantor === 'Yes') { return 'Yes'; }
        if (this.copyToGuarantor === 'No') { return 'No'; }
        return '-';
    }
    handleCopyToGuarantorChange(event) {
        this.copyToGuarantor = event.target.value;
    }
    get isApplicationTypeIndividual()    { return (this.applicationType || '') === 'Individual'; }
    get isApplicationTypeNonIndividual() { return isNonIndividualApplicationType(this.applicationType); }
    get isBorrowerFieldEditable() {
        return this.isFieldEditable && this.stagePhrase && this.stagePhrase.includes('Borrower');
    }

    /** Guarantor / co-borrower tabs — application-level fields are inherited from the borrower. */
    get isCoApplicantScreen() {
        if (!this.stagePhrase || this.stagePhrase.includes('Borrower')) {
            return false;
        }
        return !this.isBeneficiaryApplicant;
    }
    /** Customer Type is the source-of-truth picker; Two Wheeler and sub-applicants lock it to Individual. */
    get isCustomerTypeDisabled() {
        return this.isTwoWheelerProduct || this.isSubApplicant;
    }
    get isCustomerTypeEditable() {

        return this.isFieldEditable && !this.isCustomerTypeDisabled && !this.extractedPanCardNumber
            && (this.isBorrowerFieldEditable || this._showPrimaryQuestion);
    }
    get isPurposeOfPurchaseEditable() {
        return this.purposeOfPurchase !== 'Commercial' && this.isBorrowerFieldEditable && this.productTypeLabel !== 'CV';
    }
    get showPurposeOfPurchaseField() {
        return this.productType !== 'PL';
    }
    /** Non-Individual only — disabled for Individual customer type. */
    get isApplicantEntityTypeDisabled() {
        return !hasVal(this.customerType) || this.isIndividualApplicant;
    }
    get productTypeLabel() {
        const opt = PRODUCT_TYPE_OPTIONS_ALL.find(o => o.value === this.productType);
        return opt ? opt.label : this.productType;
    }

    /*get productTypeEmoji() {
        const MAP = {
            'Passenger Vehicles':        '🚗',
            'Two Wheeler':               '🏍️',
            'Tractor':                   '🚜',
            'Small Commercial Vehicle':  '🚛',
            'Light Commercial Vehicle':  '🚛'
        };
        return MAP[this.productType] || '🚗';
    }*/
    get isTwoWheelerProduct()        { return isTwoWheelerProductType(this.productType); }
    /*get showSegmentField()           { return this.isTwoWheelerProduct && this.assetType === 'New'; }*/
    get showApplicantEntityTypeField() {
        if (this.isIndividualApplicant) return false;
        if (this.isFieldEditable) return hasVal(this.applicationType) || hasVal(this.applicantEntityType);
        return hasVal(this.applicationType);
    }
    // get showEntityNameField() {
    //     if (this.isFieldEditable) {
    //         return this.isNonIndividualApplicant && (hasVal(this.entityName) || hasVal(this.applicantEntityType));
    //     }
    //     return this.isNonIndividualApplicant;
    // }
    get isCvProduct()                { return isCvProductType(this.productType); }
    get showMajorMinorIndustryFields() {
        if (!this.isNonIndividualApplicant || this.isCvProduct) return false;
        // if (this.isFieldEditable) {
        //     return hasVal(this.majorIndustry) || hasVal(this.minorIndustry);
        // }
        return true;
    }
    get showIndustryFields() {
        if (!this.isNonIndividualApplicant || !this.isCvProduct) return false;
        // if (this.isFieldEditable) {
        //     return hasVal(this.industryName) || hasVal(this.industryCode);
        // }
        return true;
    }
    get majorIndustryOptions()       { return this._majorIndustryOptions; }
    get minorIndustryOptionsComputed() {
        const key = this.majorIndustry || '';
        return this._minorIndustryOptionsMap[key] || [];
    }
    get industryNameOptions()        { return this._industryNameOptions; }
    get isMinorIndustryDisabled()    { return !hasVal(this.majorIndustry) || this.minorIndustryOptionsComputed.length === 0; }
    get showBeneficiaryFields() {
        if (!this.isBeneficiaryApplicant) return false;
        return true;
    }
    get beneficialOwnerCategoryOptions() { return this._beneficialOwnerCategoryOptions; }
    get relationshipWithEntityOptions()  { return this._relationshipWithEntityOptions; }
    get relationshipTypeOptions()          { return this._relationshipTypeOptions; }
    get beneficialOwnerCategoryLabel() {
        if (!hasVal(this.beneficialOwnerCategory)) return '';
        const opt = this._beneficialOwnerCategoryOptions.find((o) => o.value === this.beneficialOwnerCategory);
        return opt ? opt.label : this.beneficialOwnerCategory;
    }
    get relationshipWithEntityLabel() {
        if (!hasVal(this.relationshipWithEntity)) return '';
        const opt = this._relationshipWithEntityOptions.find((o) => o.value === this.relationshipWithEntity);
        return opt ? opt.label : this.relationshipWithEntity;
    }
    get relationshipTypeLabel() {
        if (!hasVal(this.relationshipType)) return '';
        const opt = this._relationshipTypeOptions.find((o) => o.value === this.relationshipType);
        return opt ? opt.label : this.relationshipType;
    }
    get shareHoldingDisplay() {
        if (!hasVal(this.shareHolding)) return '';
        const n = Number(this.shareHolding);
        if (Number.isNaN(n)) return this.shareHolding;
        return n <= 1 && n > 0 ? String(n * 100) : String(n);
    }
    get poaHolderLabel() { return this.poaHolder ? 'Yes' : 'No'; }
    // Primary applicant question
    get showPrimaryQuestion() { return this._showPrimaryQuestion === true; }
    get primaryQuestionLabel() {
        const role = this.primaryRoleLabel || 'Applicant';
        return `Is this Applicant a Primary ${role} in this Application?`;
    }
    get primaryAnswerLabel() { return this.isPrimary ? 'Yes' : 'No'; }
    get isPrimaryYes() { return this.isPrimary === true; }
    get isPrimaryNo() { return this.isPrimary !== true; }
    /*get showVehicleTypeUsedOption()  { return !this.isTwoWheelerProduct; }
    */
    /*get assetTypeOptions() {
        return this.isTwoWheelerProduct ? VEHICLE_TYPE_OPTIONS_TWO_WHEELER : VEHICLE_TYPE_OPTIONS_DEFAULT;
    }*/

    // ── radio checked-state (one getter per option) ───────────────────────────
    /*get isVehicleTypeNew()               { return this.assetType === 'New'; }
    get isVehicleTypeUsed()              { return this.assetType === 'Used'; }
    get isVehicleTypeRefinance()         { return this.assetType === 'Refinance'; }
    */
    /** Prefers schema-derived options; falls back to the static helper list when Apex hasn't responded yet. */
    get customerTypeOptions() {
        return Array.isArray(this._customerTypeOptions) && this._customerTypeOptions.length > 0
            ? this._customerTypeOptions
            : CUSTOMER_TYPE_OPTIONS;
    }
    get segmentOptions()            { return SEGMENT_OPTIONS; }

    get hasNumberOfVehicles() { return hasVal(this.numberOfVehicles); }
    get applicantEntityTypeOptionsComputed() {
        if (this.isApplicationTypeIndividual) return [];
        return this._entityTypeOptions;
    }
    get applicantEntityTypeLabel() {
        if (!hasVal(this.applicantEntityType)) return '';
        const opt = this._entityTypeOptions.find((o) => o.value === this.applicantEntityType);
        return opt ? opt.label : this.applicantEntityType;
    }

    /*handleVehicleTypeChange(event) {
        this.assetType = event.target.value;
        if (this.assetType !== 'New') {
            this.segment = '';
        }
        this._updateSectionField('loanBasicInfo', 'assetType', this.assetType || '');
        this._scheduleSectionVisibilityRefresh();
    }*/
    /** Customer Type is the editable source; Application Type mirrors it on every change. */
    handleCustomerTypeChange(event) {
        if (this.isCustomerTypeDisabled) return;
        const next = event.detail?.value || '';
        this.customerType = next;
        this.applicationType = isNonIndividualApplicationType(next) ? 'Non-Individual' : 'Individual';
        this.applicantEntityType = '';
        this.shareHolding = '';
        this.shareHoldingValidationError = '';
        this._syncApplicationTypeDependents();
        this._syncIsPanAvailableFromIncomeRule();
        this._scheduleSectionVisibilityRefresh();
    }
    _normalizeShareHoldingForInput(raw) {
        if (raw == null || raw === '') return '';
        const n = Number(raw);
        if (Number.isNaN(n)) return String(raw);
        return n <= 1 && n > 0 ? String(n * 100) : String(n);
    }
    _clearIndustryFields() {
        this.majorIndustry = '';
        this.minorIndustry = '';
        this.industryName  = '';
        this.industryCode  = '';
    }
    _clearIndividualPanIdentityFields() {
        this.documentVerificationFieldValues = {
            ...this.documentVerificationFieldValues,
            extractedFirstName: '',
            extractedLastName: '',
            extractedPanCardNumber: '',
            extractedDateOfBirth: ''
        };
    }
    _clearEntityPanIdentityFields() {
        this.documentVerificationFieldValues = {
            ...this.documentVerificationFieldValues,
            dateOfIncorporation: ''
        };
    }
    _clearNonIndividualContactFields() {
        this.contactInfoFieldValues = {
            ...this.contactInfoFieldValues,
            contactPersonName: '',
            landlineNumber: ''
        };
    }
    _syncNonIndividualIncomeDefaults() {
        if (!this.isNonIndividualApplication) return;
        if (this.professionalDetailFieldValues.incomeAvailable === 'Yes') return;
        this.professionalDetailFieldValues = {
            ...this.professionalDetailFieldValues,
            incomeAvailable: 'Yes'
        };
    }
    /** Forces Occupation Category to NE when Income Available is No (Individual applicants only). */
    _syncOccupationCategoryDefaults() {
        if (!this.isIndividualApplicant) return;
        if (this.incomeAvailable !== 'No') return;
        if (this.professionalDetailFieldValues.occupationCategory === 'Non-Earning') return;
        this.professionalDetailFieldValues = {
            ...this.professionalDetailFieldValues,
            occupationCategory: 'Non-Earning'
        };
    }
    _syncIndustryCodeFromName() {
        const code = this._industryNameToCodeMap[this.industryName] || '';
        this.industryCode = code;
    }
    _applyTwoWheelerDefaults() {
        if (!this.isTwoWheelerProduct) return;
        this.applicationType = 'Individual';
        this.customerType    = 'Individual';
        this.entityName      = '';
        this.applicantEntityType = '';
        this._clearIndustryFields();
        this._clearNonIndividualContactFields();
    }
    _syncApplicationTypeDependents() {
        if (this.isIndividualApplicant) {
            this.applicantEntityType = '';
            this.entityName   = '';
            this._clearIndustryFields();
            this._clearNonIndividualContactFields();
            this._clearEntityPanIdentityFields();
        } else {
            this.applicantEntityType = '';
            this.entityName   = '';
            this._clearIndustryFields();
            this._clearIndividualPanIdentityFields();
            this._syncNonIndividualIncomeDefaults();
        }
        this._scheduleSectionVisibilityRefresh();
    }
    async handleApplicantEntityTypeChange(event) {
        this.applicantEntityType = event.detail?.value || '';
        if(this.isNonIndividualApplicant && this.showBeneficiaryFields){
            if(hasVal(this.extractedPanCardNumber)){
                this.extractedPanCardNumberValidationError = '';
                await this.handleExtractedPanBlur();
            }
        }
        this._scheduleSectionVisibilityRefresh();
    }
    handleEntityNameChange(event) {
        this.entityName = event.target.value || '';
        this._scheduleSectionVisibilityRefresh();
    }
    handleSegmentChange(event) {
        this.segment = sanitizeSegmentValue(event.detail?.value || '');
        this.loanDetailFieldValues = { ...this.loanDetailFieldValues, segment: this.segment };
        this._scheduleSectionVisibilityRefresh();
    }
    handleMajorIndustryChange(event) {
        this.majorIndustry = event.detail?.value || '';
        this.minorIndustry = '';
        this._scheduleSectionVisibilityRefresh();
    }
    handleMinorIndustryChange(event) {
        this.minorIndustry = event.detail?.value || '';
        this._scheduleSectionVisibilityRefresh();
    }
    handleIndustryNameChange(event) {
        this.industryName = event.detail?.value || '';
        this._syncIndustryCodeFromName();
        this._scheduleSectionVisibilityRefresh();
    }
    handleBeneficialOwnerCategoryChange(event) {
        this.beneficialOwnerCategory = event.detail?.value || '';
        this._scheduleSectionVisibilityRefresh();
    }
    handleRelationshipWithEntityChange(event) {
        this.relationshipWithEntity = event.detail?.value || '';
        this._scheduleSectionVisibilityRefresh();
    }
    handleRelationshipTypeChange(event) {
        this.relationshipType = event.detail?.value || '';
        this._scheduleSectionVisibilityRefresh();
    }
    handlePoaHolderChange(event) {
        this.poaHolder = event.target.checked === true;
        this._scheduleSectionVisibilityRefresh();
    }
    handlePrimaryChange(event) {
        this.isPrimary = event.target.value === 'Yes';
    }
    handleShareHoldingChange(event) {
        this.shareHolding = event.target.value || '';
        this.shareHoldingValidationError = '';
        this._scheduleSectionVisibilityRefresh();
    }

    async handleShareHoldingBlur() {
        if(this.showBeneficiaryFields && hasVal(this.shareHolding)){
            await this._validateShareHolding();
        }

    }

    _resolveNiConstitutionProductType() {
        if (isCvProductType(this.productType)) return 'CV';
        const pt = (this.productType || '').trim();
        if (pt === '4W') return 'PV';
        return null;
    }

    async _validateShareHolding() {
        console.log('validateShareHolding', this.shareHolding);
        this.shareHoldingValidationError = '';
        try {
            console.log('validateShareHolding try');
        const entered = Number(this.shareHolding);
        console.log('entered', entered);
        if(entered > 100) {
            this.shareHoldingValidationError = 'Shareholding cannot exceed 100%';
            return;
        }
        
        console.log('applicantId', this.applicantId);
        const beneficiaryShareholdingTotal = await getBeneficiaryShareholdingTotal({applicantId: this.applicantId, applicationId: this.recordId});
        console.log('beneficiaryShareholdingTotal', beneficiaryShareholdingTotal);
        if (beneficiaryShareholdingTotal) {
            if ((beneficiaryShareholdingTotal + entered) > 100) {
                this.shareHoldingValidationError = 'Total combined beneficiary shareholding cannot exceed 100%';
            return;
            }
        }

        const result = await this.getNiMinShareHoldingsDetails();
        console.log('result', JSON.stringify(result));
        if (result) {
            const min = result.Min_Shareholding__c;
            if (min == null || min === '') return;
            const minVal = Number(min);
            if (!Number.isNaN(minVal) && entered < minVal) this.shareHoldingValidationError = `Shareholding must be at least ${minVal}%`;
        }
        
        } catch (error) {
            console.log('error', JSON.stringify(error));
            this.shareHoldingValidationError = error?.body?.message || error?.message || 'Unable to validate shareholding.';
        }   
    }

    get hasShareHoldingValidationError() { return hasVal(this.shareHoldingValidationError); }

    async handleExtractedPanBlur() {
        this.checkingPan = true;
        if(this.isNonIndividualApplicant && this.showBeneficiaryFields && hasVal(this.extractedPanCardNumber)){
            //call apex
            const result = await this.getNiConstitutionRecord();
            if (result) {
                const panFourthChar = result.PAN_Fourth_Char__c;
                if (panFourthChar == null || panFourthChar === '') return;
                if (panFourthChar !== this.extractedPanCardNumber.charAt(3)) this.extractedPanCardNumberValidationError = 'PAN Card Number is not valid.';
            }
        }
        this.checkingPan = false;
    }
    get hasExtractedPanCardNumberValidationError() { return hasVal(this.extractedPanCardNumberValidationError); }

    async getNiConstitutionRecord() {
        if (!this.applicantEntityType || !this._resolveNiConstitutionProductType()) return null;
        return await getNiConstitution({
            applicantEntityType: this.applicantEntityType,
            productType: this._resolveNiConstitutionProductType()
        });
    }

    async getNiMinShareHoldingsDetails() {
        if (!this._resolveNiConstitutionProductType()) return null;
        return await getNiMinShareHoldings({
            productType: this._resolveNiConstitutionProductType(),
            applicantId: this.applicantId,
            applicationId: this.recordId
        });
    }

    _syncBeneficiaryApplicantFromContext(apexFlag) {
        this._isBeneficiaryApplicant = apexFlag === true || isBeneficiaryStagePhrase(this.stagePhrase);
    }

    _getDomInputValue(elementId, fallback) {
        if (!this.template) return fallback;
        const el = this.template.querySelector(`#${elementId}`);
        const domVal = el && typeof el.value === 'string' ? el.value.trim() : '';
        return hasVal(domVal) ? domVal : fallback;
    }

    _isBeneficiaryApplicationDetailsComplete() {
        if (!this.isBeneficiaryApplicant || !this.isNonIndividualApplication) return false;
        const shareHolding = this._getDomInputValue('shareHolding', this.shareHolding);
        return hasVal(this.beneficialOwnerCategory)
            && hasVal(this.relationshipWithEntity)
            && hasVal(this.relationshipType)
            && hasVal(shareHolding);
    }

    /**
     * Authoritative Document Verification completion.
     * Required state per branch:
     *   isPanAvailable === 'Yes' → a real PAN file must be uploaded
     *   isPanAvailable === 'No'  → a real Form 60 file must be uploaded
     *                              (and, for Individual applicants, PAN
     *                               Acknowledgement Number + Gender)
     */
    _isDocumentVerificationSectionComplete() {
        const isPan = this.isPanAvailableValue;
        if (!hasVal(isPan)) return false;
        if (isPan === 'Yes') {
            return !!this.isPanCardUploaded;
        }
        if (isPan === 'No') {
            if (!this.isForm60Uploaded) return false;
            
            if (this.isIndividualApplicant) {
                if (!hasVal(this.panAckNo)) return false;
                if (!hasVal(this.gender))   return false;
            }
            return true;
        }
        return false;
    }

    /** Authoritative Application Details completion — avoids DOM timing gaps. */
    _isApplicationDetailsSectionComplete() {
        if(this.productType == 'PL') {
            if(this.isPrimary) {
                return true;
            }
            else {
                if (!hasVal(this.customerType)) return false;
            }
        }
        else {
            if (this.isBeneficiaryApplicant && this.isNonIndividualApplication) {
                return this._isBeneficiaryApplicationDetailsComplete();
            }
            if (this.isCoApplicantScreen) {
                // Guarantor / Co-borrower now choose their own Customer Type (NI/IN) here.
                if (!hasVal(this.customerType)) return false;
                // NI co-applicants must complete the same entity fields as the borrower
                // before the next section is revealed.
                if (this.isNonIndividualApplicant) {
                    if (this.showApplicantEntityTypeField && !hasVal(this.applicantEntityType)) return false;
                    if (!hasVal(this.entityName)) return false;
                    if (this.showMajorMinorIndustryFields) {
                        if (!hasVal(this.majorIndustry)) return false;
                        if (this.minorIndustryOptionsComputed.length > 0 && !hasVal(this.minorIndustry)) return false;
                    }
                    if (this.showIndustryFields) {
                        if (!hasVal(this.industryName)) return false;
                        if (!hasVal(this.industryCode)) return false;
                    }
                }
                return true;
            }
            if (!hasVal(this.assetType)) return false;
            if (!hasVal(this.applicationType)) return false;
            if (!hasVal(this.customerType)) return false;
            /*if (this.showSegmentField && !hasVal(this.segment)) return false;*/
            if (this.showApplicantEntityTypeField && !hasVal(this.applicantEntityType)) return false;
            if (this.isNonIndividualApplication) {
                if (!hasVal(this.applicantEntityType)) return false;
                if (!hasVal(this.entityName)) return false;
                if (this.showMajorMinorIndustryFields) {
                    if (!hasVal(this.majorIndustry)) return false;
                    if (this.minorIndustryOptionsComputed.length > 0 && !hasVal(this.minorIndustry)) return false;
                }
                if (this.showIndustryFields) {
                    if (!hasVal(this.industryName)) return false;
                    if (!hasVal(this.industryCode)) return false;
                }
            }
        }
        return true;
    }

    @track showLoanBasicInfo = false;
    @track showLoanDetail = false;
    @track showProfessionalDetail = false;
    @track showDocumentVerification = false;
    @track showContactInfo = false;

    _sectionVisTimer = null;
    _sectionRefreshAfterRender = false;

    renderedCallback() {
        if (!this.isProgressiveSectionFlow) return;
        if (this._sectionRefreshAfterRender) {
            this._sectionRefreshAfterRender = false;
            this._refreshSectionVisibility();
        }
    }

    /** Progressive section unlock — borrower only; co-applicants fill their own sections immediately. */
    get isProgressiveSectionFlow() {
        if (!this.isFieldEditable) return false;
        // IN co-applicants (Guarantor / Co-Borrower) reveal all sections at once.
        // NI co-applicants follow the borrower's progressive reveal so Application
        // Details must be completed before later sections open (reset-aware).
        if (this.isCoApplicantScreen && !this.isNonIndividualApplicant) {
            return false;
        }
        return true;
    }

    _showAllSections() {
        this.showLoanBasicInfo        = true;
        this.showLoanDetail           = true;
        this.showProfessionalDetail   = true;
        this.showDocumentVerification = true;
        this.showContactInfo          = true;
    }

    /** Debounced DOM check — runs once per tick, not on every getter. */
    _scheduleSectionVisibilityRefresh() {
        if (!this.isProgressiveSectionFlow) {
            this._showAllSections();
            return;
        }
        if (this._sectionVisTimer != null) return;
        this._sectionVisTimer = setTimeout(() => {
            this._sectionVisTimer = null;
            this._refreshSectionVisibility();
        }, 0);
    }

    _refreshSectionVisibility() {
        if (!this.isProgressiveSectionFlow) {
            this._showAllSections();
            return;
        }
        const prev = {
            showLoanBasicInfo:        this.showLoanBasicInfo,
            showLoanDetail:           this.showLoanDetail,
            showProfessionalDetail:   this.showProfessionalDetail,
            showDocumentVerification: this.showDocumentVerification,
            showContactInfo:          this.showContactInfo
        };
        const vis = computeSectionVisibility(
            this.template,
            this.isFieldEditable,
            this._isApplicationDetailsSectionComplete(),
            this._sectionCompletenessOverrides()
        );
        this.showLoanBasicInfo        = vis.showLoanBasicInfo;
        this.showLoanDetail           = vis.showLoanDetail;
        this.showProfessionalDetail   = vis.showProfessionalDetail;
        this.showDocumentVerification = vis.showDocumentVerification;
        this.showContactInfo          = vis.showContactInfo;
        if (prev.showLoanBasicInfo !== vis.showLoanBasicInfo
            || prev.showLoanDetail !== vis.showLoanDetail
            || prev.showProfessionalDetail !== vis.showProfessionalDetail
            || prev.showDocumentVerification !== vis.showDocumentVerification
            || prev.showContactInfo !== vis.showContactInfo) {
            this._sectionRefreshAfterRender = true;
        }
    }

    // ── field-value map (source of truth; updated by _updateSectionField) ────
    @track loanBasicInfoFieldValues = {};

    // ── value getters ─────────────────────────────────────────────────────────
    get accountId()          { return this.loanBasicInfoFieldValues.accountId         || ''; }
    get accountName()        { return this.loanBasicInfoFieldValues.accountName        || ''; }
    get agentBranchName()    { return this.loanBasicInfoFieldValues.agentBranchName    || 'N/A'; }
    get purposeOfPurchase()  { return this.loanBasicInfoFieldValues.purposeOfPurchase  || ''; }

    // ── lookup display/matching config ────────────────────────────────────────
    get accountDisplayInfo()  { return ACCOUNT_DISPLAY_INFO; }
    get accountMatchingInfo() { return ACCOUNT_MATCHING_INFO; }

    // ── combobox option lists ─────────────────────────────────────────────────
    get purposeOfPurchaseOptions() { return PURPOSE_OF_PURCHASE_OPTS; }

    // ── event handlers ────────────────────────────────────────────────────────
    handleAccountIdChange(event) {
        const accountId = event.detail?.recordId || '';
        this.loanBasicInfoFieldValues = {
            ...this.loanBasicInfoFieldValues,
            accountId,
            accountName: event.detail?.label || event.detail?.value?.displayInfo?.primaryField || ''
        };
        this._refreshAgentBranchName(accountId);
        this._scheduleSectionVisibilityRefresh();
    }
    handlePurposeOfPurchaseChange(event) {
        this._updateSectionField('loanBasicInfo', 'purposeOfPurchase', event.detail?.value || '');
        this._scheduleSectionVisibilityRefresh();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END LOAN BASIC INFO
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // LOAN DETAIL  (HTML section 3)
    // ════════════════════════════════════════════════════════════════════════════

    // ── field-value map ───────────────────────────────────────────────────────
    @track loanDetailFieldValues = {};

    // ── value getters ─────────────────────────────────────────────────────────
    get loanDetailSegment()            { return this.loanDetailFieldValues.segment            || ''; }
    get requiredLoanAmount() { return this.loanDetailFieldValues.requiredLoanAmount || ''; }

    /** Indian-grouped display value; falls back to raw input while the field is being typed in. */
    get requiredLoanAmountDisplay() {
        return this._editingMonetary?.requiredLoanAmount
            ? (this.requiredLoanAmount || '')
            : formatIndianCurrency(this.requiredLoanAmount);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END LOAN DETAIL
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // PROFESSIONAL DETAIL  (HTML section 4)
    // ════════════════════════════════════════════════════════════════════════════

    // ── field-value map ───────────────────────────────────────────────────────
    @track professionalDetailFieldValues = {};

    // ── value getters ─────────────────────────────────────────────────────────
    get profileType()     { return this.professionalDetailFieldValues.profileType     || ''; }
    get incomeAvailable() { return this.professionalDetailFieldValues.incomeAvailable || ''; }
    get annualIncome()    { return this.professionalDetailFieldValues.annualIncome    || ''; }
    get annualIncomeDisplay() {
        return this._editingMonetary?.annualIncome
            ? (this.annualIncome || '')
            : formatIndianCurrency(this.annualIncome);
    }
    get evaluationType()  { return this.professionalDetailFieldValues.evaluationType  || ''; }
    get occupationCategory() { return this.professionalDetailFieldValues.occupationCategory || ''; }

    // ── radio checked-state ───────────────────────────────────────────────────
    get isIncomeAvailableYes() { return this.incomeAvailable === 'Yes'; }
    get isIncomeAvailableNo()  { return this.incomeAvailable === 'No'; }
    get isIncomeAvailableDisabled() {
        return this.isNonIndividualApplication && this.isFieldEditable;
    }
    get isIncomeAvailableEditable() {
        return this.isIncomeAvailableDisabled ? 'false' : 'true';
    }

    // ── visibility ────────────────────────────────────────────────────────────
    // Annual Income & Income Available are Individual-applicant parameters; hidden for NI.
    get showAnnualIncome()   { return this.isIndividualApplicant && this.incomeAvailable === 'Yes'; }
    get showEvaluationType() { return this.isNonIndividualApplication; }

    /** Individual applicants see Occupation Category once Income Available has any value. */
    get showOccupationCategory() {
        return this.isIndividualApplicant
            && (this.incomeAvailable === 'Yes' || this.incomeAvailable === 'No');
    }
    /** When Income Available = No the value is forced to NE and the combobox is locked. */
    get isOccupationCategoryLocked() {
        return this.incomeAvailable === 'No';
    }
    /** Income Yes → SAL/SEP/SENP only. Income No → NE only. */
    get occupationCategoryOptions() {
        const all = Array.isArray(this._incomeCategoryOptions) ? this._incomeCategoryOptions : [];
        if (this.incomeAvailable === 'No') {
            return all.filter((o) => o.value === 'Non-Earning');
        }
        return all.filter((o) => o.value !== 'Non-Earning');
    }
    get occupationCategoryLabel() {
        if (!hasVal(this.occupationCategory)) return '';
        const opt = (this._incomeCategoryOptions || []).find((o) => o.value === this.occupationCategory);
        return opt ? opt.label : this.occupationCategory;
    }

    // ── combobox option lists ─────────────────────────────────────────────────
    get profileTypeOptions()    { return PROFILE_TYPE_OPTS; }
    get evaluationTypeOptions()   { return this._evaluationTypeOptions; }
    get evaluationTypeLabel() {
        if (!hasVal(this.evaluationType)) return '';
        const opt = this._evaluationTypeOptions.find((o) => o.value === this.evaluationType);
        return opt ? opt.label : this.evaluationType;
    }

    // ── event handlers ────────────────────────────────────────────────────────
    handleProfileTypeChange(event) {
        this._updateSectionField('professionalDetail', 'profileType', event.detail?.value || '');
        this._scheduleSectionVisibilityRefresh();
    }
    handleIncomeAvailableChange(event) {
        if (this.isNonIndividualApplication) return;
        const val = event.target.value || '';
        this._updateSectionField('professionalDetail', 'incomeAvailable', val);
        if (val !== 'Yes') {
            this._updateSectionField('professionalDetail', 'annualIncome', '');
        }
        if (val === 'No') {
            this._updateSectionField('professionalDetail', 'occupationCategory', 'Non-Earning');
        } else if (this.occupationCategory === 'Non-Earning') {
            this._updateSectionField('professionalDetail', 'occupationCategory', '');
        }
        this._syncIsPanAvailableFromIncomeRule();
        this._scheduleSectionVisibilityRefresh();
    }
    handleAnnualIncomeInput(event) {
        const raw = event.target?.value || '';
        const sanitized = String(raw).replace(/,/g, '').replace(/[^\d.]/g, '');
        if (sanitized !== raw) {
            event.target.value = sanitized;
        }
        this._updateSectionField('professionalDetail', 'annualIncome', sanitized);
        this._syncIsPanAvailableFromIncomeRule();
        this._scheduleSectionVisibilityRefresh();
    }
    _syncIsPanAvailableFromIncomeRule() {
        const forcePanYes = this._showPancardNote || this.isNonIndividualApplicant;
        if (forcePanYes && this.documentVerificationFieldValues.isPanAvailable !== 'Yes') {
            this._updateSectionField('documentVerification', 'isPanAvailable', 'Yes');
        }
    }
    handleEvaluationTypeChange(event) {
        this._updateSectionField('professionalDetail', 'evaluationType', event.detail?.value || '');
        this._scheduleSectionVisibilityRefresh();
    }
    handleOccupationCategoryChange(event) {
        if (this.isOccupationCategoryLocked) return;
        this._updateSectionField('professionalDetail', 'occupationCategory', event.detail?.value || '');
        this._scheduleSectionVisibilityRefresh();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END PROFESSIONAL DETAIL
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // DOCUMENT VERIFICATION  (HTML section 5)
    // ════════════════════════════════════════════════════════════════════════════

    // ── field-value map ───────────────────────────────────────────────────────
    @track documentVerificationFieldValues = {};
    @track _verificationActionStates = {};         // tracks idle | loading | success per action field
    /** Per-field focus flag so monetary inputs show raw digits while typing
     *  and switch to Indian-grouped formatting on blur. */
    @track _editingMonetary = { requiredLoanAmount: false, annualIncome: false };
    static PAN_MIN_LENGTH = 10;

    // ── file previewer lazy-mount state ───────────────────────────────────────
    @track showFilePreviewer        = false;
    @track previewContentVersionId  = null;
    @track previewFileName          = '';
    @track previewFileExtension     = '';

    // ── advanced upload (Magic UI) state ──────────────────────────────────────
    @track showMagicUpload          = false;
    @track activeUploadChecklistId  = '';
    @track activeUploadDocType      = '';
    @track activeMaxFiles           = null;
    @track activeAllowedTypes       = '';
    @track panCardFiles             = [];
    @track form60Files              = [];
    @track isPanFilesExpanded       = false;
    @track isForm60FilesExpanded    = false;
    _sessionId = null;
    _vfRoot    = null;
    @track checkingPan = false;

    // ── value getters ─────────────────────────────────────────────────────────
    get isPanAvailableValue()           { return (this._showPancardNote || this.isNonIndividualApplicant) ? 'Yes' : (this.documentVerificationFieldValues.isPanAvailable || 'Yes'); }
    get panCardUploadElement()     { return this.documentVerificationFieldValues.panCardUploadElement    || null; }
    get form60UploadElement()      { return this.documentVerificationFieldValues.form60UploadElement     || null; }
    get extractedFirstName()       { return this.documentVerificationFieldValues.extractedFirstName      || ''; }
    get extractedLastName()        { return this.documentVerificationFieldValues.extractedLastName       || ''; }
    get extractedPanCardNumber()   { return this.documentVerificationFieldValues.extractedPanCardNumber  || ''; }
    get extractedDateOfBirth()     { return this.documentVerificationFieldValues.extractedDateOfBirth    || ''; }
    get dateOfIncorporation()      { return this.documentVerificationFieldValues.dateOfIncorporation     || ''; }
    get panAckNo()                 { return this.documentVerificationFieldValues.panAckNo                || ''; }
    get gender()                   { return this.documentVerificationFieldValues.gender                  || ''; }

    get genderOptions()      { return this._genderOptions; }
    get genderLabel() {
        if (!hasVal(this.gender)) return '';
        const opt = (this._genderOptions || []).find((o) => o.value === this.gender);
        return opt ? opt.label : this.gender;
    }

    /** PAN ACK No appears on the Form 60 path once the file has been uploaded. */
    get showPanAckNo() {
        return this.isPanAvailableValue === 'No' && hasVal(this.form60UploadElement);
    }
    /** Gender selection is captured on the Form 60 path for Individual applicants only. */
    get showGenderField() {
        return this.isPanAvailableValue === 'No' && this.isIndividualApplicant;
    }
    /** First / Last name are captured directly on the Form 60 path for Individual applicants. */
    get showForm60NameFields() {
        return this.isPanAvailableValue === 'No' && this.isIndividualApplicant;
    }

    /** DOB 18-80 cross-field rule (UI only, no server validation rules). */
    get dobValidationError() {
        const dob = this.extractedDateOfBirth;
        if (!hasVal(dob)) return '';
        const d = new Date(dob);
        if (Number.isNaN(d.getTime())) return 'Invalid date format';
        const today = new Date();
        let age = today.getFullYear() - d.getFullYear();
        const m = today.getMonth() - d.getMonth();
        if (m < 0 || (m === 0 && today.getDate() < d.getDate())) age--;
        if (age < DOB_MIN_AGE_YEARS) return `Applicant must be at least ${DOB_MIN_AGE_YEARS} years old`;
        if (age > DOB_MAX_AGE_YEARS) return `Applicant cannot be older than ${DOB_MAX_AGE_YEARS} years`;
        return '';
    }
    get hasDobValidationError() { return hasVal(this.dobValidationError); }

    // ── file display-name helpers ─────────────────────────────────────────────
    get isPanCardUploaded() {
        const v = this.panCardUploadElement;
        return v && typeof v === 'object' && (v.contentDocumentId || v.contentVersionId);
    }

    get isForm60Uploaded() {
        const v = this.form60UploadElement;
        return v && typeof v === 'object' && (v.contentDocumentId || v.contentVersionId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // file-name getters — MUST return '' when there is no real file linked.
    // ─────────────────────────────────────────────────────────────────────────
    get panCardFileName() {
        if (!this.isPanCardUploaded) return '';
        const v = this.panCardUploadElement;
        return (v && typeof v === 'object') ? (v.fileName || v.name || 'File attached') : '';
    }
    get form60FileName() {
        if (!this.isForm60Uploaded) return '';
        const v = this.form60UploadElement;
        return (v && typeof v === 'object') ? (v.fileName || v.name || 'File attached') : '';
    }

    // ── file preview metadata helpers ─────────────────────────────────────────
    get panCardContentDocumentId() {
        const v = this.panCardUploadElement;
        return (v && typeof v === 'object') ? (v.contentDocumentId || null) : null;
    }
    get panCardFileType() {
        const v = this.panCardUploadElement;
        if (!v || typeof v !== 'object') return null;
        return this._extractFileExtension(v.fileName || v.name || '');
    }
    get form60ContentDocumentId() {
        const v = this.form60UploadElement;
        return (v && typeof v === 'object') ? (v.contentDocumentId || null) : null;
    }
    get form60FileType() {
        const v = this.form60UploadElement;
        if (!v || typeof v !== 'object') return null;
        return this._extractFileExtension(v.fileName || v.name || '');
    }

    // ── radio checked-state ───────────────────────────────────────────────────
    get isPanAvailableYes() { return this.isPanAvailableValue === 'Yes'; }
    get isPanAvailableNo()  { return this.isPanAvailableValue === 'No'; }

    // ── readonly / visibility ─────────────────────────────────────────────────
    get isIsPanAvailableReadonly() {
        if (this.isReadOnlyScreen) {
            return true;
        }
        if (this.isNonIndividualApplicant) {
            return true;
        }
        const annualIncome = parseFloat(this.professionalDetailFieldValues.annualIncome || 0);
        const requiredLoan = parseFloat(this.loanDetailFieldValues.requiredLoanAmount || 0);
        return annualIncome > PAN_MANDATORY_INCOME_THRESHOLD
            || requiredLoan > PAN_MANDATORY_LOAN_THRESHOLD
            || this.panVerified;
    }
    get isNotIsPanAvailableReadonly() { return !this.isIsPanAvailableReadonly }
    get showPanCard()  { return this.isPanAvailableValue === 'Yes'; }
    get showForm60()   { return !this.isNonIndividualApplicant && this.isPanAvailableValue === 'No'; }
    get showExtractedPanFields() {
        if (this.isPanAvailableValue !== 'Yes') {
            return false;
        }
        const panUploaded = this.isPanAvailableValue === 'Yes' && hasVal(this.panCardUploadElement) && this.isPanCardUploaded;
        if (this.isNonIndividualApplication) {
            return panUploaded
                || hasVal(this.entityName)
                || hasVal(this.dateOfIncorporation)
                || this.panVerified;
        }
        return panUploaded
            || hasVal(this.extractedFirstName)
            || hasVal(this.extractedLastName)
            || hasVal(this.extractedDateOfBirth)
            || this.panVerified;
    }
    get panVerifyActionState()      { return this._verificationActionStates.extractedPanCardNumber || 'idle'; }
    get panVerified()         { return this.panVerifyActionState === 'success'; }
    get panVerifyLoading()    { return this.panVerifyActionState === 'loading'; }
    get panVerifyActionLabel(){ return this.panVerified ? 'Verified' : (this.panVerifyLoading ? '...' : 'Verify'); }
    /** action button picks up the dark-indigo border + turquoise fill treatment. */
    get panVerifyActionBtnClass() {
        return this.panVerified ? 'form-action-btn form-action-btn--verified' : 'form-action-btn';
    }
    /** Same VERIFIED treatment for the read-only info pill that appears after Next save. */
    get panVerifyInfoActionLabelClass() {
        return this.panVerified ? 'form-info-action-label form-info-action-label--verified' : 'form-info-action-label';
    }

    /** PAN field is editable only when verification has not yet succeeded; once verified it is locked. */
    get panInputReadonly()    { return this.panVerified; }
    get panVerifyDisabled()   { return this.panVerified || this.panVerifyLoading || !this._isPanFormatValid(this.extractedPanCardNumber) || hasVal(this.extractedPanCardNumberValidationError) || this.checkingPan }

    /** Indian PAN regex: 5 letters, 4 digits, 1 letter (e.g. AAAPA1234A). */
    _isPanFormatValid(value) {
        if (!value) return false;
        return /^[A-Z]{5}[0-9]{4}[A-Z]$/.test(String(value).trim().toUpperCase());
    }

    // ── event handlers ────────────────────────────────────────────────────────
    handleIsPanAvailableChange(event) {
        if (this.isIsPanAvailableReadonly) {
            return;
        }
        const val = event.target.value;
        this._updateSectionField('documentVerification', 'isPanAvailable', val);
        if (val === 'Yes') this._updateSectionField('documentVerification', 'form60UploadElement', null);
        if (val === 'No')  this._updateSectionField('documentVerification', 'panCardUploadElement', null);
        this._fireToggleDocumentActivation(val);
        this._scheduleSectionVisibilityRefresh();
    }

    /** Fire-and-forget Apex toggle for the PAN vs Form 60 Document_CheckList__c rows. */
    _fireToggleDocumentActivation(isPanAvailable) {
        const applicantId = this.applicantId;
        if (!applicantId) return;
        const activeDocumentType = isPanAvailable === 'Yes' ? 'PAN' : 'Form 60';
        toggleDocumentActivation({ applicantId, activeDocumentType })
            .catch(() => { /* swallow — UI continues with optimistic state */ });
    }

    async handlePanCardUpload(event) {
        const f = (event.detail?.files || [])[0];
        if (!f) return;
        await updateDocumentChecklist({ docChecklistId: this.docChecklistId, documentType: 'PAN', contentVersionId: f.contentVersionId, contentDocumentId: f.documentId })
        .then(() => {
            const fileData = {
                fileName: f.name, fileSize: f.size,
                contentVersionId: f.contentVersionId, contentDocumentId: f.documentId
            };
            this._updateSectionField('documentVerification', 'panCardUploadElement', fileData);
            this._fileMap = { panCardUploadElement: fileData };
            // Recompute gating immediately so Contact Info reveals as soon as
            // the PAN file is attached (parallel to handleForm60Upload).
            this._scheduleSectionVisibilityRefresh();
            getIntegrationMaster({integrationName:'PAN OCR API'})
            .then(integrationMaster => {
                invokeHandler(integrationMaster.Component_Reference__c, 'onFileUpload', this);
            });
        })
        .catch(error => {
            console.error('error updating document checklist - pan card: ', JSON.stringify(error));
        });
        /*const fileData = {
            fileName: f.name, fileSize: f.size,
            contentVersionId: f.contentVersionId, contentDocumentId: f.documentId
        };
        this._updateSectionField('documentVerification', 'panCardUploadElement', fileData);
        this._fileMap = { panCardUploadElement: fileData };

        invokeHandler('pancardVerificationCheck', 'onFileUpload', this);
        this._scheduleSectionVisibilityRefresh();*/
    }

    handleForm60Upload(event) {
        const f = (event.detail?.files || [])[0];
        if (!f) return;
        this._updateSectionField('documentVerification', 'form60UploadElement', {
            fileName: f.name, fileSize: f.size,
            contentVersionId: f.contentVersionId, contentDocumentId: f.documentId
        });
        this._scheduleSectionVisibilityRefresh();
    }

    // ── Advanced Upload (Magic UI) + per-file preview/delete ──────────────────

    /** Computes the VF servlet root + session id used by the embedded preview wrapper. */
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

    get chunkyUploadIconUrl() { return `${SPECIAL_ICONS}/special_icons/upload-file-icon.svg`; }

    // ── PAN file rows (single + multi) ────────────────────────────────────────
    get panFilesView() {
        if (this.panCardFiles && this.panCardFiles.length) return this.panCardFiles;
        const v = this.panCardUploadElement;
        if (v && typeof v === 'object' && (v.contentVersionId || v.contentDocumentId)) {
            const nm = v.fileName || v.name || 'File attached';
            return [{ id: v.contentVersionId || 'pan-0', name: nm, contentVersionId: v.contentVersionId || null, extension: this._extractFileExtension(nm) }];
        }
        return [];
    }
    get panFilesEmpty()  { return this.panFilesView.length === 0; }
    get panFilesSingle() { return this.panFilesView.length === 1; }
    get panFilesMulti()  { return this.panFilesView.length > 1; }
    get panSingleFile()  { return this.panFilesView[0]; }
    get panFilesCountLabel() { return `${this.panFilesView.length} files attached`; }
    get panFilesChevron() { return this.isPanFilesExpanded ? 'utility:chevronup' : 'utility:chevrondown'; }
    get isPanFileReadonly() { return this.isReadOnlyScreen || this.panVerified; }
    get panShowUploadBtn() { return this.panFilesEmpty && !this.isPanFileReadonly; }
    get panShowEmptyPlaceholder() { return this.panFilesEmpty && this.isPanFileReadonly; }
    get panCanDelete() { return !this.isPanFileReadonly; }

    // ── Form 60 file rows (single + multi) ────────────────────────────────────
    get form60FilesView() {
        if (this.form60Files && this.form60Files.length) return this.form60Files;
        const v = this.form60UploadElement;
        if (v && typeof v === 'object' && (v.contentVersionId || v.contentDocumentId)) {
            const nm = v.fileName || v.name || 'File attached';
            return [{ id: v.contentVersionId || 'form60-0', name: nm, contentVersionId: v.contentVersionId || null, extension: this._extractFileExtension(nm) }];
        }
        return [];
    }
    get form60FilesEmpty()  { return this.form60FilesView.length === 0; }
    get form60FilesSingle() { return this.form60FilesView.length === 1; }
    get form60FilesMulti()  { return this.form60FilesView.length > 1; }
    get form60SingleFile()  { return this.form60FilesView[0]; }
    get form60FilesCountLabel() { return `${this.form60FilesView.length} files attached`; }
    get form60FilesChevron() { return this.isForm60FilesExpanded ? 'utility:chevronup' : 'utility:chevrondown'; }
    get isForm60FileReadonly() { return !this.isFieldEditable; }
    get form60ShowUploadBtn() { return this.form60FilesEmpty && !this.isForm60FileReadonly; }
    get form60ShowEmptyPlaceholder() { return this.form60FilesEmpty && this.isForm60FileReadonly; }
    get form60CanDelete() { return !this.isForm60FileReadonly; }

    /** Opens checklist creation (idempotent) then the Advanced Upload pop-up for PAN. */
    handlePanChunkyUpload() {
        console.log('[ABDC] handlePanChunkyUpload fired');
        this._openAdvancedUpload('PAN', 'PAN', 'KYC - Identity & Address Proof');
    }
    /** Opens checklist creation (idempotent) then the Advanced Upload pop-up for Form 60. */
    handleForm60ChunkyUpload() {
        console.log('[ABDC] handleForm60ChunkyUpload fired');
        this._openAdvancedUpload('Form 60', 'Form 60', 'KYC - Identity & Address Proof');
    }

    async _openAdvancedUpload(documentType, documentName, documentCategory) {
        console.log('[ABDC] _openAdvancedUpload start', documentType);
        const svc = this.template.querySelector('c-embed-document-checklist');
        console.log('[ABDC] checklist service element found?', !!svc);
        if (!svc) {
            this._toast('Upload unavailable', 'The document upload service did not load. Please refresh the page and try again.', 'error');
            return;
        }
        const context = {
            applicationId:    this.recordId,
            applicantId:      this.applicantId,
            applicantType:    null,
            documentType,
            documentName,
            documentCategory
        };
        console.log('[ABDC] context', JSON.stringify(context));
        try {
            const result = await svc.getOrCreateChecklist(context);
            console.log('[ABDC] getOrCreateChecklist result', JSON.stringify(result));
            this.docChecklistId         = result.checklistId;
            this.activeUploadChecklistId = result.checklistId;
            this.activeMaxFiles         = result.maxFilesAllowed;
            this.activeAllowedTypes     = result.allowedFileTypes || '';
            this.activeUploadDocType    = documentType;
            this.showMagicUpload        = true;
            console.log('[ABDC] showMagicUpload set true; checklistId=', this.activeUploadChecklistId);
        } catch (error) {
            const msg = error?.body?.message || error?.message || 'Could not prepare the document checklist. Please retry.';
            console.error('[ABDC] getOrCreateChecklist FAILED:', JSON.stringify(error), error);
            this._toast('Upload Error', msg, 'error');
        }
    }

    handleMagicUploadClose() {
        this.showMagicUpload = false;
    }

    stopPropagationDv(event) { event.stopPropagation(); }

    // Record whether the mouse press began on the backdrop itself, so a text
    // selection started inside the dialog (and released over the backdrop) does
    // not get treated as a backdrop click and close the modal.
    handleOverlayMouseDown(event) {
        this._overlayMouseDownOnSelf = event.target === event.currentTarget;
    }

    handleOverlayClick(event) {
        if (event.target === event.currentTarget && this._overlayMouseDownOnSelf) {
            this.handleMagicUploadClose();
        }
        this._overlayMouseDownOnSelf = false;
    }

    handleMagicUploadComplete(event) {
        const files = (event.detail && event.detail.files) || [];
        if (!files.length) { this.showMagicUpload = false; return; }
        const mapped = files.map((f, i) => ({
            id:               f.contentVersionId || `upl-${i}`,
            name:             f.fileName || f.name || 'File attached',
            contentVersionId: f.contentVersionId || null,
            extension:        f.extension || this._extractFileExtension(f.fileName || f.name || '')
        }));
        const first = files[0];
        const fileData = {
            fileName:         first.fileName || first.name,
            fileSize:         first.size,
            contentVersionId: first.contentVersionId,
            contentDocumentId: null,
            documentChecklistId: this.activeUploadChecklistId
        };

        if (this.activeUploadDocType === 'PAN') {
            this.panCardFiles = mapped;
            updateDocumentChecklist({ docChecklistId: this.activeUploadChecklistId, documentType: 'PAN', contentVersionId: first.contentVersionId, contentDocumentId: null })
                .then(() => {
                    this._updateSectionField('documentVerification', 'panCardUploadElement', fileData);
                    this._fileMap = { panCardUploadElement: fileData };
                    this._scheduleSectionVisibilityRefresh();
                    return getIntegrationMaster({ integrationName: 'PAN OCR API' });
                })
                .then((integrationMaster) => {
                    if (integrationMaster) invokeHandler(integrationMaster.Component_Reference__c, 'onFileUpload', this);
                })
                .catch((error) => {
                    console.error('error updating document checklist - pan card: ', JSON.stringify(error));
                });
        } else {
            this.form60Files = mapped;
            this._updateSectionField('documentVerification', 'form60UploadElement', fileData);
            this._scheduleSectionVisibilityRefresh();
        }
        this.showMagicUpload = false;
    }

    togglePanFilesExpand()    { this.isPanFilesExpanded = !this.isPanFilesExpanded; }
    toggleForm60FilesExpand() { this.isForm60FilesExpanded = !this.isForm60FilesExpanded; }

    handleFilePreviewClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const ds = event.currentTarget?.dataset || {};
        const contentVersionId = ds.contentVersionId || null;
        if (!contentVersionId) return;
        this.previewContentVersionId = contentVersionId;
        this.previewFileName         = ds.fileName || '';
        this.previewFileExtension    = ds.fileExtension || this._extractFileExtension(ds.fileName || '') || '';
        this.showFilePreviewer       = true;
    }

    handleFilePreviewClose() {
        this.showFilePreviewer       = false;
        this.previewContentVersionId = null;
        this.previewFileName         = '';
        this.previewFileExtension    = '';
    }

    handlePanFileDelete(event) {
        event?.preventDefault?.();
        event?.stopPropagation?.();
        const id = event.currentTarget?.dataset?.id || null;
        const remaining = this.panFilesView.filter(f => f.id !== id);
        if (remaining.length) {
            this.panCardFiles = remaining;
            return;
        }
        this.panCardFiles = [];
        this.handlePanCardRemove(event);
    }

    handleForm60FileDelete(event) {
        event?.preventDefault?.();
        event?.stopPropagation?.();
        const id = event.currentTarget?.dataset?.id || null;
        const remaining = this.form60FilesView.filter(f => f.id !== id);
        if (remaining.length) {
            this.form60Files = remaining;
            return;
        }
        this.form60Files = [];
        this.handleForm60Remove(event);
    }

    _extractFileExtension(fileName) {
        if (!fileName || typeof fileName !== 'string') return null;
        const parts = fileName.split('.');
        return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : null;
    }

    handleExtractedFirstNameInput(event) {
        if (this.isNonIndividualApplication) return;
        this._updateSectionField('documentVerification', 'extractedFirstName', event.target.value || '');
    }

    handleExtractedPanInput(event) {
        const raw = (event.target?.value || '').toUpperCase().slice(0, 10);
        if (event.target && event.target.value !== raw) {
            event.target.value = raw;
        }
        this.extractedPanCardNumberValidationError = null;
        this.checkingPan = true;
        this._updateSectionField('documentVerification', 'extractedPanCardNumber', raw);
        // Manual edit invalidates the prior verification — user must re-click Verify.
        if (this._verificationActionStates.extractedPanCardNumber === 'success') {
            this._verificationActionStates = { ...this._verificationActionStates, extractedPanCardNumber: 'idle' };
            this._updateSectionField('documentVerification', 'pancardVerificationStatus', 'idle');
        }
    }

    handleExtractedLastNameInput(event) {
        if (this.isNonIndividualApplication) return;
        this._updateSectionField('documentVerification', 'extractedLastName', event.target.value || '');
    }
    handleExtractedDateOfBirthInput(event)   {
        if (this.isNonIndividualApplication) return;
        this._updateSectionField('documentVerification', 'extractedDateOfBirth', event.target.value || '');
        this._scheduleSectionVisibilityRefresh();
    }
    /** Opens the native date picker on first click so the user can edit even when an OCR
     *  value is already filled. Without this, native <input type="date"> requires clicking
     *  the small calendar icon (which the inline 'Editable' badge often obscures). */
    handleDateInputClick(event) {
        if (this.isReadOnlyScreen) return;
        const el = event.target;
        if (el && typeof el.showPicker === 'function') {
            try { el.showPicker(); } catch (_) { /* showPicker can throw in iframes / unsupported browsers */ }
        }
    }
    /** ISO max date for DOB (today minus the configured min age) — prevents picking dates that
     *  would make the applicant younger than 18. Min-age is enforced again in dobValidationError. */
    get dobMaxDateIso() {
        const d = new Date();
        d.setFullYear(d.getFullYear() - DOB_MIN_AGE_YEARS);
        const yyyy = d.getFullYear();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        return `${yyyy}-${mm}-${dd}`;
    }
    handleDateOfIncorporationInput(event) {
        this._updateSectionField('documentVerification', 'dateOfIncorporation', event.target.value || '');
        this._scheduleSectionVisibilityRefresh();
    }
    handleEntityCompanyNameInDocumentInput(event) {
        this.entityName = event.target.value || '';
        this._scheduleSectionVisibilityRefresh();
    }
    handlePanAckNoChange(event) {
        const val = (event.target?.value || '').replace(/\D/g, '').slice(0, 18);
        if (event.target && event.target.value !== val) {
            event.target.value = val;
        }
        this._updateSectionField('documentVerification', 'panAckNo', val);
        this._scheduleSectionVisibilityRefresh();
    }
    handleGenderChange(event) {
        this._updateSectionField('documentVerification', 'gender', event.detail?.value || '');
        this._scheduleSectionVisibilityRefresh();
    }

    /** Deactivates the cached PAN Document_CheckList row, clears the local upload state, and
     *  resets verified flag + extracted identity fields so the next upload starts clean. */
    handlePanCardRemove(event) {
        event?.preventDefault?.();
        event?.stopPropagation?.();
        const upload = this.panCardUploadElement;
        const checklistId = upload && typeof upload === 'object' ? upload.documentChecklistId : null;
        this.panCardFiles = [];
        this._updateSectionField('documentVerification', 'panCardUploadElement', null);
        this._updateSectionField('documentVerification', 'extractedPanCardNumber', '');
        this._updateSectionField('documentVerification', 'pancardVerificationStatus', 'idle');
        this._verificationActionStates = { ...this._verificationActionStates, extractedPanCardNumber: 'idle' };
        if (this.applicantId) {
            markPanVerified({ applicantId: this.applicantId, verified: false }).catch(() => {});
        }
        if (checklistId) {
            deactivateDocument({ documentChecklistId: checklistId })
                .catch(() => { /* swallow — UI continues with cleared state */ });
        }
        this._scheduleSectionVisibilityRefresh();
    }
    /** Deactivates the cached Form 60 Document_CheckList row and clears the local upload state. */
    handleForm60Remove(event) {
        event?.preventDefault?.();
        event?.stopPropagation?.();
        const upload = this.form60UploadElement;
        const checklistId = upload && typeof upload === 'object' ? upload.documentChecklistId : null;
        this.form60Files = [];
        this._updateSectionField('documentVerification', 'form60UploadElement', null);
        if (checklistId) {
            deactivateDocument({ documentChecklistId: checklistId })
                .catch(() => { /* swallow */ });
        }
        this._scheduleSectionVisibilityRefresh();
    }
    /** Re-runs the 3-stage PAN verification modal against the (user-edited) PAN value.
     *  Apex encrypts and persists the new value, then text-match + verify run against the stored cipher. */
    async handlePanVerifyClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const response = await savePANDetails({ applicantId: this.applicantId, panCardNumber: this.extractedPanCardNumber, dateOfBirth: this.extractedDateOfBirth, firstName: this.extractedFirstName, lastName: this.extractedLastName });
        if (response.isSuccess) {
            /*invokeHandler('pancardVerificationCheck', 'onReVerify', this);*/
            getIntegrationMaster({integrationName:'Validate PAN API'})
            .then(integrationMaster => {
                invokeHandler(integrationMaster.Component_Reference__c, 'onVerify', this);
            });
        }
        else {
            this._toast('Error', response.message || 'Failed to save PAN details.', 'error');
            return;
        }
        /*if (this.panVerified || this.panVerifyLoading) return;
        if (!this._isPanFormatValid(this.extractedPanCardNumber)) {
            this._toast('Invalid PAN', 'Enter a valid 10-character PAN (5 letters, 4 digits, 1 letter).', 'warning');
            return;
        }
        if (!this.applicantId) {
            this._toast('Error', 'Applicant context is missing — refresh the page and try again.', 'error');
            return;
        }
        invokeHandler('pancardVerificationCheck', 'onReVerify', this);*/
    }
    

    // ════════════════════════════════════════════════════════════════════════════
    // END DOCUMENT VERIFICATION
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // CONTACT INFO  (HTML section 6)
    // ════════════════════════════════════════════════════════════════════════════

    // ── field-value map ───────────────────────────────────────────────────────
    @track contactInfoFieldValues = {};

    // ── value getters ─────────────────────────────────────────────────────────
    get maritalStatus()    { return this.contactInfoFieldValues.maritalStatus    || '—'; }
    get residenceCountry() { return this.contactInfoFieldValues.residenceCountry || '—'; }
    get contactPersonName() { return this.contactInfoFieldValues.contactPersonName || ''; }
    get landlineNumber()   { return this.contactInfoFieldValues.landlineNumber   || ''; }
    get landlineDisplay()  { return formatIndianLandline(this.contactInfoFieldValues.landlineNumber || ''); }
    get contactNumber()    { return this.contactInfoFieldValues.contactNumber    || ''; }
    get emailAddress()            { return this.contactInfoFieldValues.email            || ''; }
    get contactVerifyActionState() { return this._contactActionStates?.contactNumber || 'idle'; }
    get emailVerifyActionState()   { return this._contactActionStates?.email         || 'idle'; }
    get contactVerified() {
        return this.contactVerifyActionState === 'success';
    }
    get emailVerified() {
        return this.emailVerifyActionState === 'success';
    }
    get contactVerifyLoading(){ return this.contactVerifyActionState === 'loading'; }
    get emailVerifyLoading()  { return this.emailVerifyActionState   === 'loading'; }
    get contactVerifyDisabled(){
        return this.contactVerified
            || this.contactVerifyLoading
            || !MOBILE_REGEX.test(this.contactNumber || '');
    }
    get emailVerifyDisabled()  {
        return this.emailVerified
            || this.emailVerifyLoading
            || !EMAIL_REGEX.test(this.emailAddress || '');
    }
    get isMobileFormatInvalid() {
        return hasVal(this.contactNumber) && !MOBILE_REGEX.test(this.contactNumber);
    }
    get isEmailFormatInvalid() {
        return hasVal(this.emailAddress) && !EMAIL_REGEX.test(this.emailAddress);
    }
    get mobileValidationError() {
        return this.isMobileFormatInvalid ? 'Enter a valid 10-digit Indian mobile number starting with 6-9' : '';
    }
    get emailValidationError() {
        return this.isEmailFormatInvalid ? 'Enter a valid email address' : '';
    }
    get showNonIndividualContactFields() { return !this.isIndividualApplicant; }

    // ── options getters ───────────────────────────────────────────────────────
    get maritalStatusOptions()    { return MARITAL_STATUS_OPTS; }
    get residenceCountryOptions() { return RESIDENCE_COUNTRY_OPTS; }

    // ── verify action labels ──────────────────────────────────────────────────
    get contactVerifyLabel() { return this.contactVerified ? 'Verified' : (this.contactVerifyLoading ? '...' : 'Verify'); }
    get emailVerifyLabel()   { return this.emailVerified   ? 'Verified' : (this.emailVerifyLoading   ? '...' : 'Verify'); }

    /** VERIFIED tile styling for Mobile + Email action buttons  */
    get contactVerifyActionBtnClass() {
        return this.contactVerified ? 'form-action-btn form-action-btn--verified' : 'form-action-btn';
    }
    get emailVerifyActionBtnClass() {
        return this.emailVerified ? 'form-action-btn form-action-btn--verified' : 'form-action-btn';
    }
    get contactVerifyInfoActionLabelClass() {
        return this.contactVerified ? 'form-info-action-label form-info-action-label--verified' : 'form-info-action-label';
    }
    get emailVerifyInfoActionLabelClass() {
        return this.emailVerified ? 'form-info-action-label form-info-action-label--verified' : 'form-info-action-label';
    }

    // ── event handlers ────────────────────────────────────────────────────────
    handleMaritalStatusChange(event)    { this._updateSectionField('contactInfo', 'maritalStatus',    event.detail?.value || ''); }
    handleResidenceCountryChange(event) { this._updateSectionField('contactInfo', 'residenceCountry', event.detail?.value || ''); }
    handleContactPersonNameInput(event) {
        this._updateSectionField('contactInfo', 'contactPersonName', event.target.value || '');
        this._scheduleSectionVisibilityRefresh();
    }
    handleLandlineNumberInput(event) {
        const digits = (event.target.value || '').replace(/\D/g, '').slice(0, 11);
        event.target.value = formatIndianLandline(digits);
        this._updateSectionField('contactInfo', 'landlineNumber', digits);
        this._scheduleSectionVisibilityRefresh();
    }
    handleContactNumberInput(event) {
        const val = (event.target.value || '').replace(/\D/g, '').slice(0, 10);
        event.target.value = val;
        this._updateSectionField('contactInfo', 'contactNumber', val);
        if (this.contactVerified) {
            this._contactActionStates = { ...this._contactActionStates, contactNumber: 'idle' };
        }
        this._scheduleSectionVisibilityRefresh();
    }
    handleEmailInput(event) {
        const val = (event.target.value || '').toLowerCase();
        this._updateSectionField('contactInfo', 'email', val);
        if (this.emailVerified) {
            this._contactActionStates = { ...this._contactActionStates, email: 'idle' };
        }
        this._scheduleSectionVisibilityRefresh();
    }
    
    async handleContactVerifyClick(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.contactVerified || this.contactVerifyLoading) return;
        if (this.contactNumber.length < 10) return;
        this._contactActionStates = { ...this._contactActionStates, contactNumber: 'loading' };
        this._lastActionFieldKey = 'contactNumber';
        //Sourav commented this code because we are using loadComponent function to load the component dynamically
        //invokeHandler('contactInfoCheck', 'onAction', this);
        //invokeHandler('otpVerification', 'onAction', this);
        await generatePhoneOTP({ applicantId: this.applicantId, phoneNumber: this.contactNumber })
        .then(result => {
            if (result.success) {
                invokeHandler('sendPhoneOTPAPI', 'onAction', this)
                .then((response) => {
                    console.log('response', JSON.stringify(response));
                    invokeHandler('otpVerification', 'onAction', this);
                });
            }
            else {
                this._toast('Error', result.message || 'Failed to generate OTP.', 'error');
            }
        });
    }

    async handleEmailVerifyClick(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.emailVerified || this.emailVerifyLoading) return;
        if (this.emailAddress.length < 5) return;
        this._contactActionStates = { ...this._contactActionStates, email: 'loading' };
        this._lastActionFieldKey = 'email';
        //Sourav commented this code because we are using loadComponent function to load the component dynamically
        //invokeHandler('contactInfoCheck', 'onAction', this);
        //invokeHandler('otpVerification', 'onAction', this);
        await generateEmailOTP({ applicantId: this.applicantId, emailAddress: this.emailAddress })
        .then(result => {
            if (result.success) {
                invokeHandler('sendEmailOTPAPI', 'onAction', this)
                .then((response) => {
                    console.log('response', JSON.stringify(response));
                    invokeHandler('otpVerification', 'onAction', this);
                });
            }
            else {
                this._toast('Error', result.message || 'Failed to generate OTP.', 'error');
            }
        });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END CONTACT INFO
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // CLIENT LAYER HANDLER BRIDGE
    // Exposes the same ctx interface expected by sfLOSClientLayerDocumentVerification
    // (and any other client-layer handlers): ctx.fields, ctx.setActionState,
    // ctx.updateFieldValue, ctx._fileMap, ctx._lastActionFieldKey, ctx._contactActionStates
    // ════════════════════════════════════════════════════════════════════════════

    _lastActionFieldKey = '';
    @track _fileMap     = {};
    @track _contactActionStates = {};

    /**
     * Virtual flat field array consumed by client-layer handlers via
     * ctx.fields.find(f => f.key === key). Merges all section field-value maps.
     */
    get fields() {
        const toEntries = (map) => Object.entries(map || {}).map(([key, value]) => ({ key, value }));
        return [
            ...toEntries(this.documentVerificationFieldValues),
            ...toEntries(this.contactInfoFieldValues),
            ...toEntries(this.loanBasicInfoFieldValues),
            ...toEntries(this.loanDetailFieldValues),
            ...toEntries(this.professionalDetailFieldValues),
        ];
    }

    /**
     * Generic action-state setter called by client-layer handlers.
     * Handles: 'panCardNumber' | 'extractedPanCardNumber' → document verification
     *          'email' | 'contactNumber'                  → contact info
     */
    setActionState(key, state) {
        if (!['idle', 'loading', 'success'].includes(state)) return;
        if (key === 'panCardNumber' || key === 'extractedPanCardNumber') {
            this._verificationActionStates = { ...this._verificationActionStates, extractedPanCardNumber: state };
            if (state === 'success') {
                this._updateSectionField('documentVerification', 'pancardVerificationStatus', 'success');
            }
        } else if (key === 'email' || key === 'contactNumber') {
            this._contactActionStates = { ...this._contactActionStates, [key]: state };
        }
    }

    /**
     * Generic field-value updater called by client-layer handlers.
     * Routes the key to the correct section field-value map.
     */
    updateFieldValue(key, value) {
        const documentVerificationKeys = [
            'isPanAvailable', 'panCardUploadElement', 'form60UploadElement',
            'extractedFirstName', 'extractedLastName', 'extractedPanCardNumber',
            'extractedDateOfBirth', 'dateOfIncorporation',
            'pancardVerificationStatus', 'pancardVerificationErrorMessage'
        ];
        const contactInfoKeys = [
            'maritalStatus', 'residenceCountry', 'contactPersonName', 'landlineNumber',
            'contactNumber', 'email',
            'emailVerificationStatus', 'emailVerificationErrorMessage',
            'contactVerificationStatus', 'contactVerificationErrorMessage'
        ];
        if (documentVerificationKeys.includes(key)) this._updateSectionField('documentVerification', key, value);
        else if (contactInfoKeys.includes(key)) this._updateSectionField('contactInfo', key, value);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END CLIENT LAYER HANDLER BRIDGE
    // ════════════════════════════════════════════════════════════════════════════

    // ── Loading / UI state ────────────────────────────────────────────────────
    @track isLoading = true;

    // ── Dynamic Component Modal ───────────────────────────────────────────────
    @track showDynamicComponentModal = false;
    @track dynamicComponentName      = '';
    @track dynamicComponentModalHeader = '';
    @track dynamicComponentProps     = {};

    handleDynamicComponentModalClose() {
        this.showDynamicComponentModal = false;
        this.dynamicComponentName = '';
    }
    handleOpenDynamicComponentModal(event) {
        const { componentName, ...extraProps } = event.detail || {};
        this.openDynamicComponentModal(componentName, extraProps);
    }
    openDynamicComponentModal(componentName, extraProps = {}) {
        this.dynamicComponentName = componentName || '';
        this.dynamicComponentModalHeader = extraProps?.modalHeader || '';
        this.dynamicComponentProps = extraProps;
        this.showDynamicComponentModal = !!this.dynamicComponentName;
    }

    // ── Integration Progress Modal ────────────────────────────────────────────
    @track showIntegrationProgressModal            = false;
    @track integrationProgressModalStatus          = 'loading';
    @track integrationProgressModalHeader    = '';
    @track integrationProgressModalCurrentStageIdx = 0;
    @track integrationProgressModalStages          = [];
    @track integrationProgressModalErrorMessage    = '';

    _integrationProgressHandler;
    _lastAgentBranchKey = '';

    // ── Merged field values (all sections + Application Details) ─────────────
    get allFieldValues() {
        return {
            ...this.loanBasicInfoFieldValues,
            ...this.loanDetailFieldValues,
            ...this.professionalDetailFieldValues,
            ...this.documentVerificationFieldValues,
            ...this.contactInfoFieldValues,
            productType:      this.productType,
            assetType:      this.assetType,
            applicationType:  this.applicationType,
            customerType:     this.customerType,
            applicantEntityType:    this.applicantEntityType,
            entityName:       this.entityName,
            segment:          this.segment,
            majorIndustry:    this.majorIndustry,
            minorIndustry:    this.minorIndustry,
            industryName:     this.industryName,
            industryCode:     this.industryCode,
            beneficialOwnerCategory: this.beneficialOwnerCategory,
            relationshipWithEntity:  this.relationshipWithEntity,
            relationshipType:        this.relationshipType,
            poaHolder:               this.poaHolder,
            shareHolding:            this._getDomInputValue('shareHolding', this.shareHolding),
            numberOfVehicles:        this.numberOfVehicles,
            applicantId:             this.applicantId || null,
            isNonIndividualApplicant: this.isNonIndividualApplicant
        };
    }

    get _showPancardNote() { return !this.panVerified && this._evalRule(PAN_MANDATORY_RULE.rule, this.allFieldValues); }
    get _pancardNoteMsg()  { return this._showPancardNote ? PAN_MANDATORY_RULE.message : ''; }
    get _pancardNoteIcon() { return this._showPancardNote ? PAN_MANDATORY_RULE.icon : 'utility:info'; }

    // ── Footer actions ────────────────────────────────────────────────────────
    _consentLoading = false;
    /** Set when agent opens the consent link modal for the first time in this session. */
    _consentLinkShared = false;
    /** Persisted via Consent_Sent__c when customer verifies OTP on the VF page. */
    _consentOtpVerified = false;
    /** Persisted via Application_Consent_Received__c when customer clicks Accept on VF page. */
    _applicationConsentReceived = false;
    _consentFocusHandler = null;
    @track showConsentLinkModal = false;
    _consentLinkUrl = '';
    _consentLinkCopied = false;
    _consentPollHandle = null;
    _consentPollingAttempts = 0;
    _isPollingApplicationConsent = false;

    get showActionFooter() {
        return !this.isLoading;
    }

    get isContactInfoVerifiedForConsent() {
        return this.contactVerified && this.emailVerified;
    }

    get isApplicationConsentComplete() {
        return this._applicationConsentReceived;
    }

    get isConsentLinkShared() {
        return this._consentLinkShared || this._consentOtpVerified || this._applicationConsentReceived;
    }

    get isConsentDisabled() {
        if (this.isConsentLinkShared || this.isApplicationConsentComplete) {
            return this._consentLoading;
        }
        return this._consentLoading || !this.isContactInfoVerifiedForConsent;
    }

    get consentButtonClass() {
        let cls = 'form-primary-btn p4-button-text';
        if (this.isConsentReviewButton) {
            cls += ' form-footer-btn--confirmed';
        } else if (this.isConsentDisabled) {
            cls += ' form-primary-btn-disabled';
        }
        return cls;
    }

    get isConsentReviewButton() {
        return this._applicationConsentReceived;
    }

    get consentButtonLabel() {
        if (this._applicationConsentReceived) return 'Consent Taken';
        if (this.isConsentLinkShared) return 'View Consent Link';
        return 'Consent';
    }

    get consentLinkUrl() { return this._consentLinkUrl; }
    get copyConsentLinkButtonLabel() { return this._consentLinkCopied ? 'Link Copied' : 'Copy Link'; }
    get copyConsentLinkButtonIcon() { return this._consentLinkCopied ? 'utility:check' : 'utility:copy'; }
    get isPollingApplicationConsent() { return this._isPollingApplicationConsent; }
    get consentPollingStatusLabel() {
        if (!this._isPollingApplicationConsent) return '';
        return 'Waiting for customer to accept consent…';
    }
    get consentLinkShowCheckStatus() { return !this._applicationConsentReceived; }
    get consentLinkIntroText() {
        if (this._applicationConsentReceived) {
            return 'The customer already accepted the consent.';
        }
        return 'Share this link with the customer. The customer verifies OTP and accepts consent on the verification page; this screen updates when consent is received.';
    }

    get isNextDisabled() {
        return this._computeIsNextDisabled();
    }
    get nextButtonClass() {
        return `form-primary-btn p4-button-text${this.isNextDisabled ? ' form-primary-btn-disabled' : ''}`;
    }

    _applyConsentFlagsFromData(data) {
        if (!data) return;
        this._consentOtpVerified = data.consentOtpVerified === true;
        this._applicationConsentReceived = data.applicationConsentReceived === true;
        if (data.consentSent === true) {
            this._consentLinkShared = true;
        }
        if (this._consentOtpVerified || this._applicationConsentReceived) {
            this._consentLinkShared = true;
        }
    }

    async _refreshConsentFlagsFromServer() {
        if (!this.applicantId) return;
        try {
            const flags = await getApplicantConsentFlags({ applicantId: this.applicantId });
            if (!flags?.isSuccess) return;
            const wasReceived = this._applicationConsentReceived;
            this._applyConsentFlagsFromData(flags);
            if (!wasReceived && this._applicationConsentReceived) {
                await this._handleApplicationConsentReceived();
            }
        } catch (error) {
            // Non-blocking refresh when customer accepts on the VF page.
        }
    }

    _bindConsentWindowFocusRefresh() {
        if (this._consentFocusHandler) return;
        this._consentFocusHandler = () => {
            this._refreshConsentFlagsFromServer();
        };
        window.addEventListener('focus', this._consentFocusHandler);
        this._consentVisibilityHandler = () => {
            if (document.visibilityState === 'visible') {
                this._refreshConsentFlagsFromServer();
            }
        };
        document.addEventListener('visibilitychange', this._consentVisibilityHandler);
    }

    /** Opens the consent link modal (same pattern as KYC eKYC link modal). */
    async _prepareAndOpenConsentLinkModal({ skipRecordSent = false } = {}) {
        if (!this.applicantId) {
            this._toast('Error', 'Applicant context is missing.', 'error');
            return;
        }

        this._consentLoading = true;
        try {
            let url = this._consentLinkUrl;
            if (!url) {
                url = await getConsentSiteUrl({
                    applicantId: this.applicantId,
                    loanId: this.recordId || null
                });
            }
            if (!url) {
                this._toast('Error', 'Unable to build consent site URL.', 'error');
                return;
            }
            this._consentLinkUrl = url;
            this._consentLinkCopied = false;

            if (!skipRecordSent && !this._consentLinkShared) {
                const sentResult = await recordConsentFormSent({ applicantId: this.applicantId });
                if (!sentResult?.isSuccess) {
                    this._toast('Error', sentResult?.message || 'Unable to record consent form sent.', 'error');
                    return;
                }
            }
            this._consentLinkShared = true;

            this.showConsentLinkModal = true;
            if (!this._applicationConsentReceived) {
                this._startApplicationConsentPolling();
            }
        } catch (error) {
            this._toast(
                'Error',
                error?.body?.message || error?.message || 'Unable to open consent link.',
                'error'
            );
        } finally {
            this._consentLoading = false;
        }
    }

    _startApplicationConsentPolling() {
        this._stopApplicationConsentPolling();
        if (!this.applicantId || this._applicationConsentReceived) return;
        this._isPollingApplicationConsent = true;
        this._consentPollingAttempts = 0;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._consentPollHandle = setInterval(
            () => this._pollApplicationConsent(),
            CONSENT_POLL_INTERVAL_MS
        );
    }

    _stopApplicationConsentPolling() {
        if (this._consentPollHandle) {
            clearInterval(this._consentPollHandle);
            this._consentPollHandle = null;
        }
        this._isPollingApplicationConsent = false;
    }

    async _pollApplicationConsent() {
        if (!this.applicantId) {
            this._stopApplicationConsentPolling();
            return;
        }
        this._consentPollingAttempts += 1;
        if (this._consentPollingAttempts > CONSENT_POLL_MAX_ATTEMPTS) {
            this._stopApplicationConsentPolling();
            return;
        }
        try {
            const flags = await getApplicantConsentFlags({ applicantId: this.applicantId });
            if (!flags?.isSuccess) return;
            const wasReceived = this._applicationConsentReceived;
            this._applyConsentFlagsFromData(flags);
            if (!wasReceived && flags.applicationConsentReceived === true) {
                await this._handleApplicationConsentReceived();
            }
        } catch (e) {
            // Polling is best-effort; Check Status retries manually.
        }
    }

    async _handleApplicationConsentReceived() {
        this._stopApplicationConsentPolling();
        this.showConsentLinkModal = false;
        this._toast('Success', 'Customer consent received.', 'success');
    }

    handleCloseConsentLinkModal() {
        this.showConsentLinkModal = false;
    }

    handleCheckConsentStatus() {
        this._pollApplicationConsent();
    }

    handleCopyConsentLink() {
        const url = this._consentLinkUrl;
        if (!url) return;
        const markCopied = (ok) => {
            this._consentLinkCopied = ok;
            if (ok) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { this._consentLinkCopied = false; }, 2500);
            }
        };
        if (navigator?.clipboard?.writeText) {
            navigator.clipboard.writeText(url).then(() => markCopied(true)).catch(() => markCopied(false));
            return;
        }
        try {
            const ta = document.createElement('textarea');
            ta.value = url;
            ta.style.position = 'fixed';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
            markCopied(true);
        } catch (e) {
            markCopied(false);
        }
    }

    async _openConsentLinkModalForReview() {
        if (!this._consentLinkUrl) {
            this._consentLoading = true;
            try {
                const url = await getConsentSiteUrl({
                    applicantId: this.applicantId,
                    loanId: this.recordId || null
                });
                if (url) this._consentLinkUrl = url;
            } finally {
                this._consentLoading = false;
            }
        }
        this._consentLinkCopied = false;
        this.showConsentLinkModal = true;
    }

    async handleConsentClick() {
        if (this.isConsentDisabled) return;

        if (this._applicationConsentReceived) {
            await this._refreshConsentFlagsFromServer();
            await this._openConsentLinkModalForReview();
            return;
        }

        if (this.isConsentLinkShared) {
            await this._prepareAndOpenConsentLinkModal({ skipRecordSent: true });
            return;
        }

        const phoneNumber = (this.contactNumber || '').trim();
        if (!phoneNumber || phoneNumber.length < 10) {
            this._toast('Error', 'Please enter a valid 10-digit mobile number before proceeding with Consent.', 'error');
            return;
        }

        await this._prepareAndOpenConsentLinkModal();
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    connectedCallback() {
        if (!this._recordId) this.isLoading = false;
        this._initFilePreviewContext();
        this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e);
        window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        // opendynamiccomponentmodal is dispatched via ctx.dispatchEvent() where ctx IS this
        // component, so the event fires from the host element and bubbles upward — it never
        // re-enters the template. Catch it on the host element itself.
        this._dynamicModalHandler = (e) => this.handleOpenDynamicComponentModal(e);
        this.addEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
        this._bindConsentWindowFocusRefresh();
    }

    disconnectedCallback() {
        if (this._integrationProgressHandler) {
            window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        }
        if (this._dynamicModalHandler) {
            this.removeEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
        }
        if (this._consentFocusHandler) {
            window.removeEventListener('focus', this._consentFocusHandler);
            this._consentFocusHandler = null;
        }
        if (this._consentVisibilityHandler) {
            document.removeEventListener('visibilitychange', this._consentVisibilityHandler);
            this._consentVisibilityHandler = null;
        }
        this._stopApplicationConsentPolling();
    }

    _schedulePageDataLoad() {
        if (this._loadTimer != null) {
            clearTimeout(this._loadTimer);
        }
        this._loadTimer = setTimeout(() => {
            this._loadTimer = null;
            this._loadPageData();
        }, 0);
    }

    async _loadPageData() {
        if (!this.recordId) {
            this._resetAllSections();
            this.isLoading = false;
            return;
        }
        const loadSeq = ++this._loadSeq;
        this.isLoading = true;
        try {
            const data = await getPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: GETAPPLICANTPAGEDATA_METHOD,
                recordId: this.recordId,
                params: { applicantId: this.applicantId || null }
            });
            if (loadSeq !== this._loadSeq) return;

            // ── Apex response is now a flat key→value map ─────────────────────
            const d = data || {};

            // Reset transient per-applicant UI state so a switched applicant never
            // inherits the previously-viewed applicant's verified/submitted markers.
            this._contactActionStates = {};
            this._verificationActionStates = {};
            this._submittedComplete = false;

            this._isApplicantStageComplete = d.isApplicantStageComplete === true;
            this._applyReadOnlyScreen();

            // ── Application Details ───────────────────────────────────────────
            this.productType      = d.productType      || '';
            this.assetType      = d.assetType      || '';
            this._isSubApplicant  = d.isSubApplicant === true;
            // Top-level non-borrower (Guarantor / Co-borrower / Beneficiary): keep Customer Type blank
            // when unset so the user explicitly picks NI/IN; don't inherit the borrower/application type.
            console.log('d', JSON.stringify(d));
            this.customerType     = d.showPrimaryQuestion === true
                ? (d.customerType || '')
                : (d.customerType || d.applicationType || 'Individual');
            this.applicationType  = isNonIndividualApplicationType(this.customerType) ? 'Non-Individual' : 'Individual';
            this._applyTwoWheelerDefaults();
            if (this._isSubApplicant) {
                this.customerType    = 'Individual';
                this.applicationType = 'Individual';
            }
            this._syncBeneficiaryApplicantFromContext(d.isBeneficiaryApplicant === true);
            this.copyToGuarantor = d.hasGuarantorClone === true ? 'Yes' : '';
            this.applicantEntityType    = d.applicantEntityType    || '';
            this.isPrimary               = d.isPrimary;
            if(this.productType == 'PL' && this.isPrimary) {
                this.customerType    = 'Individual';
            }
            this.entityName       = d.entityName       || '';
            this.segment          = sanitizeSegmentValue(d.segment);
            this.majorIndustry    = d.majorIndustry    || '';
            this.minorIndustry    = d.minorIndustry    || '';
            this.industryName     = d.industryName     || '';
            this.industryCode     = d.industryCode     || '';
            this._majorIndustryOptions = Array.isArray(d.majorIndustryOptions) ? d.majorIndustryOptions : [];
            this._minorIndustryOptionsMap = d.minorIndustryOptionsMap || {};
            this._industryNameOptions = Array.isArray(d.industryNameOptions) ? d.industryNameOptions : [];
            this._industryNameToCodeMap = d.industryNameToCodeMap || {};
            if (hasVal(this.industryName) && !hasVal(this.industryCode)) {
                this._syncIndustryCodeFromName();
            }
            this.beneficialOwnerCategory = d.beneficialOwnerCategory || '';
            this.relationshipWithEntity  = d.relationshipWithEntity  || '';
            this.relationshipType        = d.relationshipType        || '';
            this.poaHolder               = d.poaHolder === true || d.poaHolder === 'true';
            this.shareHolding            = this._normalizeShareHoldingForInput(d.shareHolding);
            this._showPrimaryQuestion    = d.showPrimaryQuestion === true;
            this.primaryRoleLabel        = d.primaryRoleLabel || '';
            this.isPrimary               = d.isPrimary === true || d.isPrimary === 'true';
            this._beneficialOwnerCategoryOptions = Array.isArray(d.beneficialOwnerCategoryOptions) ? d.beneficialOwnerCategoryOptions : [];
            this._relationshipWithEntityOptions  = Array.isArray(d.relationshipWithEntityOptions) ? d.relationshipWithEntityOptions : [];
            this._relationshipTypeOptions          = Array.isArray(d.relationshipTypeOptions) ? d.relationshipTypeOptions : [];
            this._entityTypeOptions = Array.isArray(d.entityTypeOptions) ? d.entityTypeOptions : [];
            this._evaluationTypeOptions = Array.isArray(d.evaluationTypeOptions) ? d.evaluationTypeOptions : [];
            this._customerTypeOptions = Array.isArray(d.customerTypeOptions) ? d.customerTypeOptions : [];
            this._incomeCategoryOptions = Array.isArray(d.incomeCategoryOptions) ? d.incomeCategoryOptions : [];
            this.numberOfVehicles = d.numberOfVehicles || '';
            this._applicantIdLoaded = this.applicantId;

            // ── Loan Basic Info ───────────────────────────────────────────────
            this.loanBasicInfoFieldValues = {
                accountId:        d.accountId        ?? null,
                accountName:      d.accountName      || '',
                assetType:      d.assetType      || '',
                agentBranchName:  d.agentBranchName  || '',
                purposeOfPurchase: d.purposeOfPurchase || defaultPurposeOfPurchase(this.productType)
            };
            if (d.accountId && !hasVal(d.accountName)) {
                this._refreshAccountNameFallback(d.accountId);
            }

            // ── Loan Detail ───────────────────────────────────────────────────
            this.loanDetailFieldValues = {
                segment:            this.segment,
                requiredLoanAmount: d.requiredLoanAmount ?? ''
            };

            // ── Professional Detail ───────────────────────────────────────────
            this.professionalDetailFieldValues = {
                profileType:    d.profileType    || '',
                incomeAvailable: d.incomeAvailable || '',
                annualIncome:   d.annualIncome    ?? '',
                evaluationType: d.evaluationType  || '',
                occupationCategory: d.occupationCategory || ''
            };
            this._syncNonIndividualIncomeDefaults();
            this._syncOccupationCategoryDefaults();

            // ── Document Verification ─────────────────────────────────────────
            this.documentVerificationFieldValues = {
                isPanAvailable:          d.isPanAvailable          || '',
                panCardUploadElement:    d.panCardUploadElement     ?? null,
                form60UploadElement:     d.form60UploadElement      ?? null,
                extractedFirstName:      d.extractedFirstName       || '',
                extractedLastName:       d.extractedLastName        || '',
                extractedPanCardNumber:  d.extractedPanCardNumber   || '',
                extractedDateOfBirth:    d.extractedDateOfBirth     || '',
                dateOfIncorporation:     d.dateOfIncorporation      || '',
                panAckNo:                d.panAckNo                  || '',
                gender:                  d.gender                    || '',
                pancardVerificationStatus: d.pancardVerificationStatus || ''
            };
            this.docChecklistId = this.documentVerificationFieldValues.panCardUploadElement?.documentChecklistId ?? this.documentVerificationFieldValues.form60UploadElement?.documentChecklistId;
            this.panCardFiles = [];
            this.form60Files = [];
            if (Array.isArray(d.genderOptions) && d.genderOptions.length > 0) {
                this._genderOptions = d.genderOptions;
            }

            // ── Restore DV action states from persisted verification status ──────
            if (d.pancardVerificationStatus === 'success') {
                this._verificationActionStates = { ...this._verificationActionStates, extractedPanCardNumber: 'success' };
            }

            // ── Contact Info — preserve user-typed values; only overwrite when Apex has non-empty value ─
            const contactInfoLoadKeys = ['maritalStatus', 'residenceCountry', 'contactPersonName', 'landlineNumber', 'contactNumber', 'email'];
            for (const k of contactInfoLoadKeys) {
                if (hasVal(d[k])) this.contactInfoFieldValues = { ...this.contactInfoFieldValues, [k]: d[k] };
            }

            // ── Consent state (per-applicant, loaded from Applicant__c) ──────────
            this._applyConsentFlagsFromData({
                consentOtpVerified: d.consentOtpVerified === true,
                consentSent: d.consentSent === true,
                applicationConsentReceived: d.applicationConsentReceived === true
            });
            if (this._consentLinkShared && !this._applicationConsentReceived) {
                this._startApplicationConsentPolling();
            }

            // ── Restore CI action states from persisted verification status ──────
            if (d.contactVerificationStatus === 'success') {
                this._contactActionStates = { ...this._contactActionStates, contactNumber: 'success' };
            }
            if (d.emailVerificationStatus === 'success') {
                this._contactActionStates = { ...this._contactActionStates, email: 'success' };
            }

        } catch (e) {
            if (loadSeq !== this._loadSeq) return;
            this._resetAllSections();
        } finally {
            if (loadSeq !== this._loadSeq) return;
            this.isLoading = false;
            if (this.isProgressiveSectionFlow) {
                this._scheduleSectionVisibilityRefresh();
            } else {
                this._showAllSections();
            }
        }
    }

    _resetAllSections() {
        this.loanBasicInfoFieldValues = {};
        this._submittedComplete = false;
        this.loanDetailFieldValues = {};
        this.professionalDetailFieldValues = {};
        this.documentVerificationFieldValues = {};
        this.contactInfoFieldValues = {};
        this._showAllSections();
    }

    // ── Generic handlers for Apex sections (use data-section + data-key) ──────
    handleGenericInput(event) {
        const key     = event.target?.dataset?.key;
        const section = event.target?.dataset?.section;
        if (key && section) this._updateSectionField(section, key, event.target.value || '');
    }

    /** Strips commas + non-numeric chars, keeps a single decimal point, and clips to 2 decimal places.
     *  Final-shape validation happens via REQUIRED_LOAN_AMOUNT_REGEX on blur / save. */
    handleRequiredLoanAmountInput(event) {
        const raw = event.target?.value || '';
        let sanitized = String(raw).replace(/,/g, '').replace(/[^\d.]/g, '');
        const firstDot = sanitized.indexOf('.');
        if (firstDot !== -1) {
            sanitized = sanitized.slice(0, firstDot + 1)
                + sanitized.slice(firstDot + 1).replace(/\./g, '');
            const [intPart, decPart = ''] = sanitized.split('.');
            sanitized = `${intPart}.${decPart.slice(0, 2)}`;
        }
        if (sanitized !== raw) {
            event.target.value = sanitized;
        }
        this._updateSectionField('loanDetail', 'requiredLoanAmount', sanitized);
        this._syncIsPanAvailableFromIncomeRule();
        this._scheduleSectionVisibilityRefresh();
    }
    handleRequiredLoanAmountFocus() {
        this._editingMonetary = { ...this._editingMonetary, requiredLoanAmount: true };
    }
    handleRequiredLoanAmountBlur(event) {
        this._editingMonetary = { ...this._editingMonetary, requiredLoanAmount: false };
        const v = (event.target?.value || '').replace(/,/g, '').trim();
        if (hasVal(v) && !REQUIRED_LOAN_AMOUNT_REGEX.test(v)) {
            this._toast('Invalid Required Loan Amount', 'Enter a valid amount with up to two decimal places.', 'warning');
        }
    }
    handleAnnualIncomeFocus() {
        this._editingMonetary = { ...this._editingMonetary, annualIncome: true };
    }
    handleAnnualIncomeBlur() {
        this._editingMonetary = { ...this._editingMonetary, annualIncome: false };
    }

    _updateSectionField(section, key, value) {
        if (section === 'loanBasicInfo')        this.loanBasicInfoFieldValues        = { ...this.loanBasicInfoFieldValues,        [key]: value };
        else if (section === 'loanDetail')      this.loanDetailFieldValues           = { ...this.loanDetailFieldValues,           [key]: value };
        else if (section === 'professionalDetail') this.professionalDetailFieldValues = { ...this.professionalDetailFieldValues,   [key]: value };
        else if (section === 'documentVerification') this.documentVerificationFieldValues = { ...this.documentVerificationFieldValues, [key]: value };
        else if (section === 'contactInfo')     this.contactInfoFieldValues          = { ...this.contactInfoFieldValues,          [key]: value };
        if (this.isProgressiveSectionFlow) {
            this._scheduleSectionVisibilityRefresh();
        }
    }

    // ── Integration Progress Modal handlers ───────────────────────────────────
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
    handleIntegrationProgressModalRetry() {
        this.integrationProgressModalStatus = 'loading';
        if(this.integrationProgressModalHeader === 'Extracting and Validating PAN Data') {
            if(this.integrationProgressModalCurrentStageIdx === 0) {
                getIntegrationMaster({integrationName:'PAN OCR API'})
                .then(integrationMaster => {
                    invokeHandler(integrationMaster.Component_Reference__c, 'onFileUpload', this);
                });
            }
            else if(this.integrationProgressModalCurrentStageIdx === 1) {
                getIntegrationMaster({integrationName:'Validate PAN API'})
                .then(integrationMaster => {
                    invokeHandler(integrationMaster.Component_Reference__c, 'onVerify', this);
                });
            }
        }
        else if(this.integrationProgressModalHeader === 'Verify PAN') {
            getIntegrationMaster({integrationName:'Validate PAN API'})
            .then(integrationMaster => {
                invokeHandler(integrationMaster.Component_Reference__c, 'onVerify', this);
            });
        }
    }
    handleIntegrationProgressModalDone() { this.showIntegrationProgressModal = false; }

    //Save
    async handleSaveButton() {
        if (this.showBeneficiaryFields && hasVal(this.shareHolding)) {
            if (this.hasShareHoldingValidationError) {
                this._toast('Validation Error', this.shareHoldingValidationError, 'error');
                return;
            }
        }
        if (this.isNextDisabled) return;
        if (this.isReadOnlyScreen) {
            const currentViewId = this.currentViewId;
            if (!currentViewId) {
                this._toast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error');
                return;
            }
        }
        this._showGlobalLoader('Saving Basic Details...');
        try {
            const params   = this._normalizeParamsForSave(this.allFieldValues);
            const response = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: SAVEAPPLICANTPAGEDATA_METHOD,
                recordId: this.recordId,
                params: { ...params, applicantId: this.applicantId || null }
            });
            if (!response.isSuccess) {
                this._hideGlobalLoaderIfShown();
                this._toast('Save Failed', response.message || 'Failed to save data.', 'error');
                return;
            }
            else {
                this._toast('Save Successful', 'Data saved successfully.', 'success');
            }
        }
        catch (error) {
            this._hideGlobalLoaderIfShown();
            this._toast('Error', error?.message || 'An unexpected error occurred.', 'error');
        }
        finally {
            this.isLoading = false;
        }
    }
    
    // ── Next / Save ───────────────────────────────────────────────────────────
    /** Plain-text console output — LWC Proxy objects are unreadable in DevTools otherwise. */
    _debugNextLog(step, payload) {
        if (payload === undefined) {
            console.log(`[BasicDetails][Next] ${step}`);
            return;
        }
        try {
            console.log(`[BasicDetails][Next] ${step} ${JSON.stringify(payload)}`);
        } catch (e) {
            console.log(`[BasicDetails][Next] ${step} (unstringifiable payload)`);
        }
    }

    _debugNextError(step, error) {
        const message = error?.body?.message || error?.message || String(error);
        console.error(`[BasicDetails][Next] ${step} ${message}`);
    }

    _getNextDisabledReasons() {
        const reasons = [];
        if (this.isLoading) reasons.push('isLoading');
        if (this.hasDobValidationError) reasons.push('hasDobValidationError');
        if (this.hasShareHoldingValidationError) reasons.push('hasShareHoldingValidationError');
        if (this.isMobileFormatInvalid) reasons.push('isMobileFormatInvalid');
        if (this.isEmailFormatInvalid) reasons.push('isEmailFormatInvalid');
        if (!this.contactVerified) reasons.push('contactNotVerified');
        if (!this.emailVerified) reasons.push('emailNotVerified');
        if (!this._applicationConsentReceived) reasons.push('applicationConsentNotReceived');
        if (this.isBeneficiaryApplicant && this.isNonIndividualApplication
            && !this._isBeneficiaryApplicationDetailsComplete()) {
            reasons.push('beneficiaryApplicationDetailsIncomplete');
        }
        if (!areAllSectionsComplete(
            this.template,
            this.isFieldEditable,
            this._isApplicationDetailsSectionComplete(),
            this._sectionCompletenessOverrides()
        )) {
            reasons.push('sectionsIncomplete');
        }
        return reasons;
    }

    async handleNextButton() {
        await this._refreshConsentFlagsFromServer();
        if (this.showBeneficiaryFields && hasVal(this.shareHolding)) {
            if (this.hasShareHoldingValidationError) {
                this._toast('Validation Error', this.shareHoldingValidationError, 'error');
                return;
            }
        }
        this._debugNextLog('click', {
            applicantId: this.applicantId,
            recordId: this.recordId,
            currentViewId: this.currentViewId,
            stagePhrase: this.stagePhrase,
            isReadOnlyScreen: this.isReadOnlyScreen,
            isPanAvailable: this.isPanAvailableValue,
            consentOtpVerified: this._consentOtpVerified,
            consentLinkShared: this._consentLinkShared,
            applicationConsentReceived: this._applicationConsentReceived
        });

        if (this.isNextDisabled) {
            this._debugNextLog('blocked — disabled reasons', this._getNextDisabledReasons());
            return;
        }
        if (this.isReadOnlyScreen) {
            const currentViewId = this.currentViewId;
            if (!currentViewId) {
                this._toast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error');
                return;
            }
            window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
                detail: {
                    currentViewId,
                    id: currentViewId,
                    applicantId: this.applicantId,
                    currentLoanStageComplete: this.tab || STAGE_LEAD_DETAILS,
                    currentStagePhrase: this.stagePhrase || ''
                },
                bubbles: true,
                composed: true
            }));
            return;
        }
        this.isLoading = true;
        this._showGlobalLoader('Saving Basic Details...');
        try {
            const params = this._normalizeParamsForSave(this.allFieldValues);
            this._debugNextLog('save start', {
                applicantId: this.applicantId,
                recordId: this.recordId,
                paramKeys: Object.keys(params || {})
            });
            const response = await savePageData({
                apexClassName: APEX_CLASS,
                apexMethodName: SAVEAPPLICANTPAGEDATA_METHOD,
                recordId: this.recordId,
                params: { ...params, applicantId: this.applicantId || null }
            });
            this._debugNextLog('save response', {
                isSuccess: response?.isSuccess,
                message: response?.message || null
            });
            if (!response.isSuccess) {
                this._hideGlobalLoaderIfShown();
                this._toast('Save Failed', response.message || 'Failed to save data.', 'error');
                return;
            }
            this._markSubmittedReadOnly();

            // persist the Primary answer; setPrimaryApplicant enforces one Primary per scope.
            if (this._showPrimaryQuestion && this.applicantId) {
                try {
                    await setPrimaryApplicant({ applicantId: this.applicantId, value: this.isPrimary === true });
                } catch (primaryError) {
                    this._debugNextError('set primary applicant failed', primaryError);
                }
            }

            if (this.isBeneficiaryApplicant && this.isNonIndividualApplicant
                    && this.copyToGuarantor === 'Yes' && this.applicantId) {
                try {
                    await ensureGuarantorCloneShell({ beneficiaryId: this.applicantId });
                } catch (cloneError) {
                    this._debugNextError('guarantor clone shell failed', cloneError);
                }
            }

            // Sub-applicant: activate the inactive shell once its Basic Details is saved.
            if (this.isSubApplicant && this.applicantId) {
                try {
                    await activateSubApplicantShell({ applicantId: this.applicantId });
                    // Shell is now a real journey — clear the abandon-discard tracker.
                    if (window.__mogaPendingSubShellId === this.applicantId) {
                        window.__mogaPendingSubShellId = null;
                    }
                } catch (subError) {
                    this._debugNextError('sub-applicant activation failed', subError);
                }
            }

            const currentViewId = this.currentViewId;
            if (!currentViewId) {
                this._hideGlobalLoaderIfShown();
                this._debugNextError('navigation blocked — missing currentViewId');
                this._toast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error');
                return;
            }

            const dispatchNextStage = () => {
                const detail = {
                    currentViewId,
                    id: currentViewId,
                    applicantId: this.applicantId,
                    currentLoanStageComplete: this.tab || STAGE_LEAD_DETAILS,
                    currentStagePhrase: this.stagePhrase || ''
                };
                this._debugNextLog('dispatch losnextstage', detail);
                window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
                    detail,
                    bubbles: true,
                    composed: true
                }));
            };

            if (this.isPanAvailableValue === 'Yes') {
                this._debugNextLog('running borrowerNextIntegration');
                await invokeHandler('borrowerNextIntegration', 'onNextButton', this)
                .then(() => {
                    this._debugNextLog('integration complete');
                    this._preCreateKycChecklists();
                    this._hideGlobalLoaderIfShown();
                    dispatchNextStage();
                })
                .catch((error) => {
                    this._debugNextError('integration failed', error);
                    this._hideGlobalLoaderIfShown();
                    this._toast('Error', error?.message || 'An unexpected error occurred.', 'error');
                });
            } else {
                this._debugNextLog('skipping integration (Form 60 / no PAN path)');
                await this._preCreateKycChecklists();
                this._hideGlobalLoaderIfShown();
                dispatchNextStage();
            }
        } catch (error) {
            this._debugNextError('unexpected error', error);
            this._hideGlobalLoaderIfShown();
            this._toast('Error', error?.body?.message || error?.message || 'An unexpected error occurred.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /** Idempotently pre-creates the placeholder Document_CheckList__c rows that the
     *  KYC Details stage expects. Failures are surfaced as a non-blocking toast so
     *  the user can still advance and fix the issue from the KYC screen. */
    async _preCreateKycChecklists() {
        const applicantId = this.applicantId;
        if (!applicantId) return;
        try {
           // await createCurrentAddressChecklist({ applicantId });
        } catch (e) {
            this._toast('KYC Pre-Create', e?.body?.message || e?.message || 'Failed to pre-create KYC documents', 'warning');
        }
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new CustomEvent('showtoast', {
            detail: { title, message, variant },
            bubbles: true, composed: true
        }));
    }

    /** Shows the global loader exactly once per Next-click flow. Reference-counted
     *  by globalLoader so overlapping flows can't double-show. Pair with
     *  _hideGlobalLoaderIfShown so we never leak a stuck backdrop. */
    _globalLoaderShown = false;
    _showGlobalLoader(message) {
        if (this._globalLoaderShown) return;
        this._globalLoaderShown = true;
        window.dispatchEvent(new CustomEvent('losgloballoader', {
            detail: { show: true, message: message || 'Processing...' }
        }));
    }
    /** Hides the global loader exactly once if we showed it. Called on save error,
     *  missing currentViewId, or unexpected catch — so the user is never left behind
     *  the loading backdrop when navigation fails. */
    _hideGlobalLoaderIfShown() {
        if (this._globalLoaderShown) {
            this._globalLoaderShown = false;
            window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
        }
    }

    /** Fallback path: when the record picker hasn't supplied a display name yet, fetch Account.Name from Apex. */
    async _refreshAccountNameFallback(accountId) {
        if (!accountId) return;
        try {
            const name = await getAccountName({ accountId });
            if (!name) return;
            this.loanBasicInfoFieldValues = {
                ...this.loanBasicInfoFieldValues,
                accountName: name
            };
        } catch (e) {
            /* swallow — the readonly Account name simply stays blank */
        }
    }

    // ── Agent branch name side-effect ─────────────────────────────────────────
    async _refreshAgentBranchName(accountId) {
        if (!this.recordId || !accountId) return;
        const key = `${accountId}|${this.productType}`;
        if (key === this._lastAgentBranchKey) return;
        this._lastAgentBranchKey = key;
        const agentBranchName = await getAgentBranchName({
            recordId: this.recordId,
            accountId,
            productType: this.productType
        });
        this.loanBasicInfoFieldValues = {
            ...this.loanBasicInfoFieldValues,
            agentBranchName: agentBranchName || 'N/A'
        };
    }

    // ── Rule evaluation ───────────────────────────────────────────────────────
    _evalRule(rule, fieldValues) {
        if (!rule || typeof rule !== 'object') return true;
        const getV  = (k) => fieldValues?.[k];
        const op    = (rule.operator || '').toUpperCase();
        if (op === 'AND') {
            const conds = Array.isArray(rule.conditions) ? rule.conditions : [];
            return conds.length > 0 && conds.every(c => this._evalRule(c, fieldValues));
        }
        if (op === 'OR') {
            const conds = Array.isArray(rule.conditions) ? rule.conditions : [];
            return conds.length > 0 && conds.some(c => this._evalRule(c, fieldValues));
        }
        if (op === 'NOT') return !this._evalRule(rule.condition, fieldValues);
        const fieldKey = rule.field;
        if (!fieldKey) return true;
        const refVal  = getV(fieldKey);
        const opLower = (rule.operator || '').toLowerCase();
        if (opLower === 'hasvalue') return !!refVal;
        const val = rule.value;
        if (opLower === 'in' && Array.isArray(val)) return val.includes(refVal);
        if (Array.isArray(val) && opLower !== 'in') return val.includes(refVal);
        if (opLower === 'ne')       return refVal !== val;
        if (opLower === 'gt')       return parseFloat(refVal) > parseFloat(val);
        if (opLower === 'gte')      return parseFloat(refVal) >= parseFloat(val);
        if (opLower === 'lt')       return parseFloat(refVal) < parseFloat(val);
        if (opLower === 'lte')      return parseFloat(refVal) <= parseFloat(val);
        if (opLower === 'contains') return String(refVal ?? '').includes(String(val ?? ''));
        return refVal === val;
    }

    // ── Date normalization ────────────────────────────────────────────────────
    _toSalesforceDate(value) {
        if (!value || typeof value !== 'string') return value;
        const s = value.trim();
        if (/^\d{4}-\d{1,2}-\d{1,2}$/.test(s)) return s;
        const m = s.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/);
        if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
        return value;
    }

    _normalizeParamsForSave(params) {
        const out = { ...params };
        if (out.extractedDateOfBirth) out.extractedDateOfBirth = this._toSalesforceDate(out.extractedDateOfBirth);
        if (out.dateOfIncorporation) out.dateOfIncorporation = this._toSalesforceDate(out.dateOfIncorporation);
        return out;
    }

    // ── Next button disabled computation ──────────────────────────────────────
    _computeIsNextDisabled() {
        if (this.isLoading) return true;
        // Past stages / already-complete applicant stages are read-only — NEXT
        // is hidden by the template (see isFieldEditable gate on the footer button)
        //if (!this.isFieldEditable) return false;
        if (this.hasDobValidationError) return true;
        if (this.hasShareHoldingValidationError) return true;
        if (this.isMobileFormatInvalid) return true;
        if (this.isEmailFormatInvalid) return true;

        if (!this.contactVerified) return true;
        if (!this.emailVerified)   return true;
        if (!this._applicationConsentReceived) return true;
        if (this.isBeneficiaryApplicant && this.isNonIndividualApplication) {
            return !this._isBeneficiaryApplicationDetailsComplete();
        }
        return !areAllSectionsComplete(
            this.template,
            this.isFieldEditable,
            this._isApplicationDetailsSectionComplete(),
            this._sectionCompletenessOverrides()
        );
    }

    _sectionCompletenessOverrides() {
        return {
            documentVerification: this._isDocumentVerificationSectionComplete()
        };
    }

    /** Reuses the existing past-stage read-only path when isReadOnlyScreen is true. */
    _markSubmittedReadOnly() {
        this._submittedComplete = true;
        this._applyReadOnlyScreen();
    }

    _applyReadOnlyScreen() {
        if (!this.isReadOnlyScreen) return;
        this._showAllSections();
    }
}