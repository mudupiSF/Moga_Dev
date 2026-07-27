import { LightningElement, api, track } from 'lwc';
import getBorrowerPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';
import getAgentBranchName from '@salesforce/apex/BorrowerMasterPageController.getAgentBranchName';
import { invokeHandler } from 'c/clientLayerHelper';
import { productTypeOptions as HARDCODED_PRODUCT_TYPE_OPTIONS } from './picklistvalues';
import { CUSTOMER_TYPE_OPTIONS as HARDCODED_CUSTOMER_TYPE_OPTIONS } from './picklistvalues';
import {SEGMENT_OPTIONS as HARDCODED_SEGMENT_OPTIONS} from './picklistvalues';

// ── Apex routing constants ───────────────────────────────────────────────────
const APEX_CLASS        = 'BorrowerMasterPageController';
const APEX_METHOD       = 'getBorrowerPageData';
const SAVE_APEX_CLASS   = 'BorrowerMasterPageController';
const SAVE_APEX_METHOD  = 'saveBorrowerPageData';
const STAGE_LEAD_DETAILS              = 'Basic Details';
const LOS_NEXT_STAGE_EVENT            = 'losnextstage';
const INTEGRATION_PROGRESS_EVENT      = 'integrationprogressupdate';

/**
 * ── Section visibility rules ─────────────────────────────────────────────────
 *
 *  Section                  │ Visible when (ALL must be filled)
 * ──────────────────────────┼──────────────────────────────────────────────────
 *  Loan Basic Info          │ productType + numberOfVehicles + applicationType
 *                           │ (+ vehicleType if Two Wheeler; + segment if New)
 *                           │ (+ customerType + applicantType + entityName if NI)
 * ──────────────────────────┼──────────────────────────────────────────────────
 *  Loan Detail              │ vehicleType (from loanBasicInfoFieldValues)
 * ──────────────────────────┼──────────────────────────────────────────────────
 *  Professional Detail      │ requiredLoanAmount (from allFieldValues)
 * ──────────────────────────┼──────────────────────────────────────────────────
 *  Document Verification    │ profileType + incomeAvailable + annualIncome
 * ──────────────────────────┼──────────────────────────────────────────────────
 *  Contact Info             │ profileType + incomeAvailable + annualIncome
 * ──────────────────────────┼──────────────────────────────────────────────────
 *  PAN Mandatory Note       │ incomeAvailable = 'Yes' AND annualIncome > 400 000
 *                           │ → forces isPanAvailable = 'Yes' and locks radio
 * ──────────────────────────┴──────────────────────────────────────────────────
 */
const SHOW_LOAN_DETAIL_RULE = {
    operator: 'AND',
    conditions: [{ field: 'vehicleType', operator: 'hasValue' }]
};
const SHOW_PROFESSIONAL_DETAIL_RULE = {
    operator: 'AND',
    conditions: [{ field: 'requiredLoanAmount', operator: 'hasValue' }]
};
const SHOW_DOCUMENT_VERIFICATION_RULE = {
    operator: 'AND',
    conditions: [
        { field: 'profileType',     operator: 'hasValue' },
        { field: 'incomeAvailable', operator: 'hasValue' },
        { field: 'annualIncome',    operator: 'hasValue' }
    ]
};
const SHOW_CONTACT_INFO_RULE = {
    operator: 'AND',
    conditions: [
        { field: 'profileType',     operator: 'hasValue' },
        { field: 'incomeAvailable', operator: 'hasValue' },
        { field: 'annualIncome',    operator: 'hasValue' }
    ]
};
const ANNUAL_INCOME_MESSAGE_RULE = {
    rule: {
        operator: 'AND',
        conditions: [
            { field: 'incomeAvailable', value: 'Yes' },
            { field: 'annualIncome',    value: 400000, operator: 'GT' }
        ]
    },
    message: 'As the Annual Income is greater than or equal to 4 Lakhs, PAN is mandatory',
    icon: 'utility:warning'
};

// ── Static option lists for Application Details ──────────────────────────────


/**
 * ── Applicant Type options (dependent on Customer Type) ──────────────────────
 *
 *  Customer Type    │ Applicant Type options
 * ──────────────────┼────────────────────────────────────────────────────────
 *  Individual       │ Salaried
 *                   │ Self Employed Professional
 *                   │ Self Employed Non-Professional
 *                   │ Un-employed
 *                   │ Not Salaried
 *                   │ Housewife
 *                   │ Income not Considered
 *                   │ Others
 * ──────────────────┼────────────────────────────────────────────────────────
 *  Non-Individual   │ Public Limited
 *                   │ Private Limited
 *                   │ Partnership
 *                   │ Hindu Undivided Family
 *                   │ Proprietorship
 *                   │ Trust
 *                   │ Society
 *                   │ Partnership & Limited Liability
 * ──────────────────┴────────────────────────────────────────────────────────
 *  Controlled by: applicantTypeOptionsComputed getter → reads customerType
 */
const APPLICANT_TYPE_OPTIONS_MAP = {
    'Individual': [
        { label: 'Salaried',                          value: 'Salaried' },
        { label: 'Self Employed Professional',        value: 'Self Employed Professional' },
        { label: 'Self Employed Non-Professional',    value: 'Self Employed Non-Professional' },
        { label: 'Un-employed',                       value: 'Un-employed' },
        { label: 'Not Salaried',                      value: 'Not Salaried' },
        { label: 'Housewife',                         value: 'Housewife' },
        { label: 'Income not Considered',             value: 'Income not Considered' },
        { label: 'Others',                            value: 'Others' }
    ],
    'Non-Individual': [
        { label: 'Public Limited',                    value: 'Public Limited' },
        { label: 'Private Limited',                   value: 'Private Limited' },
        { label: 'Partnership',                       value: 'Partnership' },
        { label: 'Hindu Undivided Family',            value: 'Hindu Undivided Family' },
        { label: 'Proprietorship',                    value: 'Proprietorship' },
        { label: 'Trust',                             value: 'Trust' },
        { label: 'Society',                           value: 'Society' },
        { label: 'Partnership & Limited Liability',   value: 'Partnership & Limited Liability' }
    ]
};

/**
 * ── Loan Basic Info static option lists ─────────────────────────────────────
 *
 *  Constant                  │ Used for             │ Options
 * ───────────────────────────┼──────────────────────┼───────────────────────
 *  LBI_PURPOSE_OF_PURCHASE   │ Purpose of Purchase  │ Personal
 *  _OPTS                     │ (combobox)           │ Commercial
 * ───────────────────────────┼──────────────────────┼───────────────────────
 *  LBI_ACCOUNT_DISPLAY_INFO  │ lightning-record-    │ primaryField: 'Name'
 *                            │ picker display config│
 * ───────────────────────────┼──────────────────────┼───────────────────────
 *  LBI_ACCOUNT_MATCHING_INFO │ lightning-record-    │ primaryField.fieldPath:
 *                            │ picker search config │   'Name'
 * ───────────────────────────┴──────────────────────┴───────────────────────
 */
const LBI_PURPOSE_OF_PURCHASE_OPTS = [
    { label: 'Personal',   value: 'Personal' },
    { label: 'Commercial', value: 'Commercial' }
];
const LBI_ACCOUNT_DISPLAY_INFO  = { primaryField: 'Name' };
const LBI_ACCOUNT_MATCHING_INFO = { primaryField: { fieldPath: 'Name' } };

/**
 * ── Professional Detail static option lists ──────────────────────────────────
 *
 *  Constant               │ Used for          │ Options
 * ────────────────────────┼───────────────────┼────────────────────────────
 *  PD_PROFILE_TYPE_OPTS   │ Profile Type      │ BANK EMPLOYEE
 *                         │ (combobox)        │ CONTRACT WORKER
 *                         │                   │ DAILY WAGES
 *                         │                   │ DOCK AND MINE WORKER
 *                         │                   │ EDITOR
 *                         │                   │ GARAGE MECHANIC
 *                         │                   │ GARDENER
 *                         │                   │ GOVERNMENT SERVANT
 *                         │                   │ INTELLIGENCE PERSONNEL
 *                         │                   │ JOB WORKER
 *                         │                   │ LAB TECHNICIAN
 *                         │                   │ MEDICAL - REP
 *                         │                   │ POLICE
 *                         │                   │ SOFTWARE ENGINEER
 * ────────────────────────┼───────────────────┼────────────────────────────
 *  PD_EVALUATION_TYPE     │ Evaluation Type   │ Captive Retail
 *  _OPTS                  │ (combobox,        │ Captive strategic
 *                         │  visible for NI   │ Hiring FTU
 *                         │  applicants only) │ Hiring Retail
 *                         │                   │ Hiring Strategic
 *                         │                   │ Not Applicable
 * ────────────────────────┴───────────────────┴────────────────────────────
 */
const PD_PROFILE_TYPE_OPTS = [
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
const PD_EVALUATION_TYPE_OPTS = [
    { label: 'Captive Retail',      value: 'Captive Retail' },
    { label: 'Captive strategic',   value: 'Captive strategic' },
    { label: 'Hiring FTU',          value: 'Hiring FTU' },
    { label: 'Hiring Retail',       value: 'Hiring Retail' },
    { label: 'Hiring Strategic',    value: 'Hiring Strategic' },
    { label: 'Not Applicable',      value: 'Not Applicable' }
];

/**
 * ── Contact Info static option lists ─────────────────────────────────────────
 *
 *  Constant                  │ Used for              │ Options
 * ───────────────────────────┼───────────────────────┼──────────────────────
 *  CI_MARITAL_STATUS_OPTS    │ Marital Status        │ Married
 *                            │ (combobox)            │ Unmarried
 *                            │                       │ Divorced
 *                            │                       │ Widowed
 * ───────────────────────────┼───────────────────────┼──────────────────────
 *  CI_RESIDENCE_COUNTRY_OPTS │ Residence Country     │ India
 *                            │ (combobox)            │ Non-India Resident
 * ───────────────────────────┴───────────────────────┴──────────────────────
 */
const CI_MARITAL_STATUS_OPTS = [
    { label: 'Married',            value: 'MARRIED' },
    { label: 'Unmarried',          value: 'Unmarried' },
    { label: 'Divorced',           value: 'Divorced' },
    { label: 'Widowed',            value: 'Widowed' }
];
const CI_RESIDENCE_COUNTRY_OPTS = [
    { label: 'India',              value: 'India' },
    { label: 'Non-India Resident', value: 'Non-India Resident' }
];

/**
 * ── Helper: hasVal(v) — is a value considered "filled"? ─────────────────────
 *
 *  Input type          │ Returns true when
 * ─────────────────────┼──────────────────────────────────────────────────────
 *  null / undefined    │ never  (always false)
 * ─────────────────────┼──────────────────────────────────────────────────────
 *  File object         │ v.fileName is a non-empty string
 *  { fileName, ... }   │ (used for panCardUploadElement / form60UploadElement)
 * ─────────────────────┼──────────────────────────────────────────────────────
 *  Any other value     │ String(v).trim() is not empty
 *  (string, number,    │ e.g. '0' → true,  ''  → false
 *   boolean, etc.)     │      ' ' → false,  0   → false (String('0') = '0')
 * ─────────────────────┴──────────────────────────────────────────────────────
 *  Used by: _isAppDetailsComplete, _computeIsNextDisabled,
 *           _loadPageData (CI field overwrite guard)
 */
const hasVal = (v) => {
    if (v == null) return false;
    if (typeof v === 'object' && v.fileName !== undefined) return !!v.fileName;
    return String(v).trim() !== '';
};

export default class BorrowerMasterPage extends LightningElement {

    // ── @api props ────────────────────────────────────────────────────────────
    _recordId;
    @api get recordId() { return this._recordId; }
    set recordId(v) { this._recordId = v; this._loadPageData(); }

    @api applicantId;
    @api currentViewId;
    @api tab = '';
    @api stagePhrase = '';

    // ════════════════════════════════════════════════════════════════════════════
    // APPLICATION DETAILS  (HTML section 1)
    // ────────────────────────────────────────────────────────────────────────────
    // Purpose  : First card on the page. Captures the core loan classification
    //            fields that drive visibility of every subsequent section.
    //
    //  @track field        │ What it stores
    // ─────────────────────┼──────────────────────────────────────────────────
    //  productType         │ e.g. 'Two Wheeler' — gates vehicleType + segment
    //  numberOfVehicles    │ 'Single' | 'Multiple' (auto-set for Two Wheeler)
    //  vehicleType         │ 'New' | 'Used' | 'Refinance' (Two Wheeler only)
    //  applicationType     │ 'Individual' | 'Non-Individual'
    //  customerType        │ sub-type of NI applicant (e.g. 'Partnership')
    //  applicantType       │ sub-type of Individual (e.g. 'Salaried')
    //  entityName          │ company / entity name (NI only)
    //  segment             │ segment code (Two Wheeler + New only)
    // ─────────────────────┴──────────────────────────────────────────────────
    //
    //  Key side-effects on field change
    // ─────────────────────────────────────────────────────────────────────────
    //  productType → Two Wheeler  : auto-sets numberOfVehicles='Single',
    //                               applicationType='Individual',
    //                               clears customerType/applicantType/entityName
    //  productType → other        : clears vehicleType + segment
    //  vehicleType → not 'New'    : clears segment
    //  applicationType → Individual: clears customerType/applicantType/entityName
    //
    //  Readonly rules
    // ─────────────────────────────────────────────────────────────────────────
    //  numberOfVehicles  : readonly when productType = 'Two Wheeler'
    //  applicationType   : readonly when Two Wheeler OR not Lead Details stage
    //  All fields        : show bmp-info-cell when isNotLeadDetailsStage
    // ════════════════════════════════════════════════════════════════════════════

    // ── fields ────────────────────────────────────────────────────────────────
    @track productType      = '';
    @track numberOfVehicles = '';
    @track vehicleType      = '';
    @track applicationType  = '';
    @track customerType     = '';
    @track applicantType    = '';
    @track entityName       = '';
    @track segment          = '';

    // ── picklist options ──────────────────────────────────────────────────────
    @track productTypeOptions = [...HARDCODED_PRODUCT_TYPE_OPTIONS];

    // ── visibility / readonly ─────────────────────────────────────────────────
    get _isNI() {
        const at = this.applicationType || '';
        return at === 'Non Individual' || at === 'NI' || at === 'Non-Individual';
    }
    get showVehicleTypeField()       { return true; }
    get productTypeLabel() {
        const opt = this.productTypeOptions.find(o => o.value === this.productType);
        return opt ? opt.label : this.productType;
    }

    get productTypeEmoji() {
        const MAP = {
            'Passenger Vehicles':        '🚗',
            'Two Wheeler':               '🏍️',
            'Tractor':                   '🚜',
            'Small Commercial Vehicle':  '🚛',
            'Light Commercial Vehicle':  '🚛'
        };
        return MAP[this.productType] || '🚗';
    }
    get numberOfVehicleUIROBehaviour() {
        return ((this.productType === 'Two Wheeler' ? true : false) || (this.isLeadDetailsStage));
    }


    get showSegmentField()           { return this.productType === 'Two Wheeler' && this.vehicleType === 'New'; }
    get showNIFields()               { return this._isNI; }
    get isNumberOfVehiclesReadonly() { return this.productType === 'Two Wheeler'; }
    get isApplicationTypeReadonly()  { return this.productType === 'Two Wheeler'; }

    // ── radio checked-state (one getter per option) ───────────────────────────
    get isNumberOfVehiclesSingle()       { return this.numberOfVehicles === 'Single'; }
    get isNumberOfVehiclesMultiple()     { return this.numberOfVehicles === 'Multiple'; }
    get isVehicleTypeNew()               { return this.vehicleType === 'New'; }
    get isVehicleTypeRefinance()         { return this.vehicleType === 'Refinance'; }
    get isApplicationTypeIndividual()    { return this.applicationType === 'Individual'; }
    get isApplicationTypeNonIndividual() { return this.applicationType === 'Non-Individual'; }

    // ── combobox option lists ─────────────────────────────────────────────────
    get customerTypeOptions()       { return HARDCODED_CUSTOMER_TYPE_OPTIONS; }
    get segmentOptions()            { return HARDCODED_SEGMENT_OPTIONS; }
    get applicantTypeOptionsComputed() {
        const ctrl = this.customerType || 'Individual';
        return APPLICANT_TYPE_OPTIONS_MAP[ctrl] || APPLICANT_TYPE_OPTIONS_MAP['Individual'] || [];
    }

    // ── event handlers ─────────────────────────────────────────────────────────
    //
    //  Handler                       │ Trigger         │ Side-effects
    // ───────────────────────────────┼─────────────────┼─────────────────────────────────────────
    //  handleProductTypeChange       │ combobox change │ Two Wheeler → numberOfVehicles='Single',
    //                                │                 │   applicationType='Individual',
    //                                │                 │   clears customerType/applicantType/entityName
    //                                │                 │ Other → clears vehicleType + segment
    //                                │                 │ Always → refreshes agentBranchName
    // ───────────────────────────────┼─────────────────┼─────────────────────────────────────────
    //  handleNumberOfVehiclesChange  │ radio change    │ Updates numberOfVehicles only if not
    //                                │                 │   readonly (i.e. not Two Wheeler)
    // ───────────────────────────────┼─────────────────┼─────────────────────────────────────────
    //  handleVehicleTypeChange       │ radio change    │ Sets vehicleType; clears segment if not
    //                                │                 │   'New'; mirrors value into
    //                                │                 │   loanBasicInfoFieldValues.vehicleType
    // ───────────────────────────────┼─────────────────┼─────────────────────────────────────────
    //  handleApplicationTypeChange   │ radio change    │ Updates applicationType only if not
    //                                │                 │   readonly; if Individual → clears
    //                                │                 │   customerType/applicantType/entityName
    // ───────────────────────────────┼─────────────────┼─────────────────────────────────────────
    //  handleCustomerTypeChange      │ combobox change │ Sets customerType; resets applicantType
    //                                │                 │   (options depend on customerType)
    // ───────────────────────────────┼─────────────────┼─────────────────────────────────────────
    //  handleApplicantTypeChange     │ combobox change │ Sets applicantType only
    // ───────────────────────────────┼─────────────────┼─────────────────────────────────────────
    //  handleEntityNameChange        │ text input      │ Sets entityName only
    // ───────────────────────────────┼─────────────────┼─────────────────────────────────────────
    //  handleSegmentChange           │ combobox change │ Sets segment only
    // ───────────────────────────────┴─────────────────┴─────────────────────────────────────────
    handleProductTypeChange(event) {
        this.productType = event.detail?.value || '';
        if (this.productType === 'Two Wheeler') {
            this.numberOfVehicles = 'Single';
            this.applicationType  = 'Individual';
            this.customerType = ''; this.applicantType = ''; this.entityName = '';
        } else {
            this.vehicleType = ''; this.segment = '';
        }
        this._refreshAgentBranchName(this.loanBasicInfoFieldValues?.accountId || '');
    }
    handleNumberOfVehiclesChange(event) {
        if (!this.isNumberOfVehiclesReadonly) this.numberOfVehicles = event.target.value;
    }
    handleVehicleTypeChange(event) {
        
        this.vehicleType = event.target.value;
        if (this.vehicleType !== 'New') {
            this.segment = '';            
        }
        this._updateSectionField('loanBasicInfo', 'vehicleType', this.vehicleType || '');
    }
    handleApplicationTypeChange(event) {
        if (!this.isApplicationTypeReadonly) {
            this.applicationType = event.target.value;
            if (!this._isNI) { this.customerType = ''; this.applicantType = ''; this.entityName = ''; }
        }
    }
    handleCustomerTypeChange(event) {
        this.customerType  = event.detail?.value || '';
        this.applicantType = '';
    }
    handleApplicantTypeChange(event) { this.applicantType = event.detail?.value || ''; }
    handleEntityNameChange(event)    { this.entityName    = event.target.value   || ''; }
    handleSegmentChange(event)       { this.segment       = event.detail?.value  || ''; }

    // ── next-button readiness (Application Details required fields only) ───────
    _isAppDetailsComplete() {
        if (!hasVal(this.productType))      return false;
        if (!hasVal(this.numberOfVehicles)) return false;
        if (!hasVal(this.applicationType))  return false;
        if (this.productType === 'Two Wheeler') {
            if (!hasVal(this.vehicleType)) return false;
            if (this.vehicleType === 'New' && !hasVal(this.segment)) return false;
        }
        if (this._isNI) {
            if (!hasVal(this.customerType))  return false;
            if (!hasVal(this.applicantType)) return false;
            if (!hasVal(this.entityName))    return false;
        }
        return true;
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END APPLICATION DETAILS
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // LOAN BASIC INFO  (HTML section 2)
    // Fields → Computed → Handlers — everything for this card lives here
    // ════════════════════════════════════════════════════════════════════════════

    // ── editability flag (true when Opportunity is still in Lead Details stage) ─
    // @track isLeadDetailsStage = false;
    get isNotLeadDetailsStage() { return !this.isLeadDetailsStage; }

    // ── field-value map (source of truth; updated by _updateSectionField) ────
    @track loanBasicInfoFieldValues = {};

    // ── value getters ─────────────────────────────────────────────────────────
    get lbiAccountId()          { return this.loanBasicInfoFieldValues.accountId         || ''; }
    get lbiAccountName()        { return this.loanBasicInfoFieldValues.accountName        || ''; }
    get lbiLeadNumber()         { return this.loanBasicInfoFieldValues.leadNumber         || ''; }
    get lbiVehicleType()        { return this.loanBasicInfoFieldValues.vehicleType        || ''; }
    get lbiAgentBranchName()    { return this.loanBasicInfoFieldValues.agentBranchName    || 'N/A'; }
    get lbiPurposeOfPurchase()  { return this.loanBasicInfoFieldValues.purposeOfPurchase  || ''; }

    // ── lookup display/matching config ────────────────────────────────────────
    get lbiAccountDisplayInfo()  { return LBI_ACCOUNT_DISPLAY_INFO; }
    get lbiAccountMatchingInfo() { return LBI_ACCOUNT_MATCHING_INFO; }

    // ── combobox option lists ─────────────────────────────────────────────────
    get lbiPurposeOfPurchaseOptions() { return LBI_PURPOSE_OF_PURCHASE_OPTS; }

    // ── event handlers ────────────────────────────────────────────────────────
    handleLbiAccountIdChange(event) {
        const accountId = event.detail?.recordId || '';
        this.loanBasicInfoFieldValues = {
            ...this.loanBasicInfoFieldValues,
            accountId,
            accountName: event.detail?.label || event.detail?.value?.displayInfo?.primaryField || ''
        };
        this._refreshAgentBranchName(accountId);
    }
    handleLbiPurposeOfPurchaseChange(event) {
        this._updateSectionField('loanBasicInfo', 'purposeOfPurchase', event.detail?.value || '');
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
    get ldSegment()            { return this.loanDetailFieldValues.segment            || ''; }
    get ldRequiredLoanAmount() { return this.loanDetailFieldValues.requiredLoanAmount || ''; }

    // ── visibility (segment visible for Two Wheeler product only) ────────────
    get showLdSegment() { return this.productType === 'TW' || this.productType === 'Two Wheeler'; }

    // ════════════════════════════════════════════════════════════════════════════
    // END LOAN DETAIL
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // PROFESSIONAL DETAIL  (HTML section 4)
    // ════════════════════════════════════════════════════════════════════════════

    // ── field-value map ───────────────────────────────────────────────────────
    @track professionalDetailFieldValues = {};

    // ── value getters ─────────────────────────────────────────────────────────
    get pdProfileType()     { return this.professionalDetailFieldValues.profileType     || ''; }
    get pdIncomeAvailable() { return this.professionalDetailFieldValues.incomeAvailable || ''; }
    get pdAnnualIncome()    { return this.professionalDetailFieldValues.annualIncome    || ''; }
    get pdEvaluationType()  { return this.professionalDetailFieldValues.evaluationType  || ''; }

    // ── radio checked-state ───────────────────────────────────────────────────
    get isPdIncomeAvailableYes() { return this.pdIncomeAvailable === 'Yes'; }
    get isPdIncomeAvailableNo()  { return this.pdIncomeAvailable === 'No'; }

    // ── visibility ────────────────────────────────────────────────────────────
    get showPdAnnualIncome()   { return this.pdIncomeAvailable === 'Yes'; }
    get showPdEvaluationType() { return this._isNI; }

    // ── combobox option lists ─────────────────────────────────────────────────
    get pdProfileTypeOptions()    { return PD_PROFILE_TYPE_OPTS; }
    get pdEvaluationTypeOptions() { return PD_EVALUATION_TYPE_OPTS; }

    // ── event handlers ────────────────────────────────────────────────────────
    handlePdProfileTypeChange(event) {
        this._updateSectionField('professionalDetail', 'profileType', event.detail?.value || '');
    }
    handlePdIncomeAvailableChange(event) {
        this._updateSectionField('professionalDetail', 'incomeAvailable', event.target.value || '');
        if (event.target.value !== 'Yes') {
            this._updateSectionField('professionalDetail', 'annualIncome', '');
        }
        this._syncIsPanAvailableFromIncomeRule();
    }
    handlePdAnnualIncomeInput(event) {
        this._updateSectionField('professionalDetail', 'annualIncome', event.target.value || '');
        this._syncIsPanAvailableFromIncomeRule();
    }
    _syncIsPanAvailableFromIncomeRule() {
        if (this._showPancardNote && this.documentVerificationFieldValues.isPanAvailable !== 'Yes') {
            this._updateSectionField('documentVerification', 'isPanAvailable', 'Yes');
        }
    }
    handlePdEvaluationTypeChange(event) {
        this._updateSectionField('professionalDetail', 'evaluationType', event.detail?.value || '');
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END PROFESSIONAL DETAIL
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // DOCUMENT VERIFICATION  (HTML section 5)
    // ════════════════════════════════════════════════════════════════════════════

    // ── field-value map ───────────────────────────────────────────────────────
    @track documentVerificationFieldValues = {};
    @track _dvActionStates = {};         // tracks idle | loading | success per action field
    static DV_PAN_MIN_LENGTH = 10;

    // ── file previewer lazy-mount state ───────────────────────────────────────
    @track showFilePreviewer        = false;
    @track previewContentDocumentId = null;
    @track previewFileType          = null;

    // ── value getters ─────────────────────────────────────────────────────────
    get dvIsPanAvailable()           { return this._showPancardNote ? 'Yes' : (this.documentVerificationFieldValues.isPanAvailable || 'Yes'); }
    get dvPanCardUploadElement()     { return this.documentVerificationFieldValues.panCardUploadElement    || null; }
    get dvForm60UploadElement()      { return this.documentVerificationFieldValues.form60UploadElement     || null; }
    get dvExtractedFirstName()       { return this.documentVerificationFieldValues.extractedFirstName      || ''; }
    get dvExtractedLastName()        { return this.documentVerificationFieldValues.extractedLastName       || ''; }
    get dvExtractedPanCardNumber()   { return this.documentVerificationFieldValues.extractedPanCardNumber  || ''; }
    get dvExtractedDateOfBirth()     { return this.documentVerificationFieldValues.extractedDateOfBirth    || ''; }

    // ── file display-name helpers ─────────────────────────────────────────────
    get dvPanCardFileName() {
        const v = this.dvPanCardUploadElement;
        if (!v) return '';
        return typeof v === 'object' ? (v.fileName || v.name || (v.contentVersionId ? 'File attached' : '')) : String(v);
    }
    get dvForm60FileName() {
        const v = this.dvForm60UploadElement;
        if (!v) return '';
        return typeof v === 'object' ? (v.fileName || v.name || (v.contentVersionId ? 'File attached' : '')) : String(v);
    }

    // ── file preview metadata helpers ─────────────────────────────────────────
    get dvPanCardContentDocumentId() {
        const v = this.dvPanCardUploadElement;
        return (v && typeof v === 'object') ? (v.contentDocumentId || null) : null;
    }
    get dvPanCardFileType() {
        const v = this.dvPanCardUploadElement;
        if (!v || typeof v !== 'object') return null;
        return this._extractFileExtension(v.fileName || v.name || '');
    }
    get dvForm60ContentDocumentId() {
        const v = this.dvForm60UploadElement;
        return (v && typeof v === 'object') ? (v.contentDocumentId || null) : null;
    }
    get dvForm60FileType() {
        const v = this.dvForm60UploadElement;
        if (!v || typeof v !== 'object') return null;
        return this._extractFileExtension(v.fileName || v.name || '');
    }

    // ── radio checked-state ───────────────────────────────────────────────────
    get isDvIsPanAvailableYes() { return this.dvIsPanAvailable === 'Yes'; }
    get isDvIsPanAvailableNo()  { return this.dvIsPanAvailable === 'No'; }

    // ── readonly / visibility ─────────────────────────────────────────────────
    get isIsPanAvailableReadonly() {
        if (!this.isLeadDetailsStage) return true;
        return parseFloat(this.professionalDetailFieldValues.annualIncome || 0) > 400000;
    }
    get isNotIsPanAvailableReadonly() { return !this.isIsPanAvailableReadonly; }
    get showDvPanCard()  { return this.dvIsPanAvailable === 'Yes'; }
    get showDvForm60()   { return this.dvIsPanAvailable === 'No'; }
    get showDvExtractedPanFields() {
        const panUploaded = this.dvIsPanAvailable === 'Yes' && hasVal(this.dvPanCardUploadElement);
        return panUploaded
            || hasVal(this.dvExtractedFirstName)
            || hasVal(this.dvExtractedLastName)
            || hasVal(this.dvExtractedPanCardNumber)
            || hasVal(this.dvExtractedDateOfBirth);
    }
    get dvPanActionState()      { return this._dvActionStates.extractedPanCardNumber || 'idle'; }
    get dvPanVerified()         { return this.dvPanActionState === 'success'; }
    //get dvPanVerified()         { return false; }
    get dvPanVerifyLoading()    { return this.dvPanActionState === 'loading'; }
    get dvPanVerifyActionLabel(){ return this.dvPanVerified ? 'Verified' : (this.dvPanVerifyLoading ? '...' : 'Verify'); }
    get dvPanVerifyDisabled()   { return this.dvPanVerified || this.dvPanVerifyLoading || this.dvExtractedPanCardNumber.length < BorrowerMasterPage.DV_PAN_MIN_LENGTH; }

    // ── event handlers ────────────────────────────────────────────────────────
    handleDvIsPanAvailableChange(event) {
        const val = event.target.value;
        this._updateSectionField('documentVerification', 'isPanAvailable', val);
        if (val === 'Yes') this._updateSectionField('documentVerification', 'form60UploadElement', null);
        if (val === 'No')  this._updateSectionField('documentVerification', 'panCardUploadElement', null);
    }
    handleDvPanCardUpload(event) {
        const f = (event.detail?.files || [])[0];
        if (!f) return;
        const fileData = {
            fileName: f.name, fileSize: f.size,
            contentVersionId: f.contentVersionId, contentDocumentId: f.documentId
        };
        this._updateSectionField('documentVerification', 'panCardUploadElement', fileData);
        this._fileMap = { panCardUploadElement: fileData };

        invokeHandler('panFileExtract', 'onFileUpload', this);
    }
    handleDvForm60Upload(event) {
        const f = (event.detail?.files || [])[0];
        if (!f) return;
        this._updateSectionField('documentVerification', 'form60UploadElement', {
            fileName: f.name, fileSize: f.size,
            contentVersionId: f.contentVersionId, contentDocumentId: f.documentId
        });
    }

    handleFilePreviewClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const ds = event.currentTarget?.dataset || {};
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

    _extractFileExtension(fileName) {
        if (!fileName || typeof fileName !== 'string') return null;
        const parts = fileName.split('.');
        return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : null;
    }

    handleDvExtractedFirstNameInput(event)     { this._updateSectionField('documentVerification', 'extractedFirstName',     event.target.value || ''); }
    handleDvExtractedLastNameInput(event)      { this._updateSectionField('documentVerification', 'extractedLastName',      event.target.value || ''); }
    handleDvExtractedPanCardNumberInput(event) {
        const val = (event.target.value || '').toUpperCase();
        this._updateSectionField('documentVerification', 'extractedPanCardNumber', val);
        if (this.dvPanActionState === 'success') {
            this._dvActionStates = { ...this._dvActionStates, extractedPanCardNumber: 'idle' };
        }
    }
    handleDvExtractedDateOfBirthInput(event)   { this._updateSectionField('documentVerification', 'extractedDateOfBirth',   event.target.value || ''); }
    handleDvPanVerifyClick(event) {
        event.preventDefault();
        event.stopPropagation();
        /*if (this.dvPanVerified || this.dvPanVerifyLoading) return;
        if (this.dvExtractedPanCardNumber.length < BorrowerMasterPage.DV_PAN_MIN_LENGTH) return;
        this._dvActionStates = { ...this._dvActionStates, extractedPanCardNumber: 'loading' };
        this._lastActionFieldKey = 'panCardNumber';
        invokeHandler('pancardVerificationCheck', 'onAction', this);*/
        
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
    get ciMaritalStatus()    { return this.contactInfoFieldValues.maritalStatus    || ''; }
    get ciResidenceCountry() { return this.contactInfoFieldValues.residenceCountry || ''; }
    get ciContactNumber()    { return this.contactInfoFieldValues.contactNumber    || ''; }
    get ciEmail()            { return this.contactInfoFieldValues.email            || ''; }
    get ciContactActionState() { return this._ciActionStates?.contactNumber || 'idle'; }
    get ciEmailActionState()   { return this._ciActionStates?.email         || 'idle'; }
    get ciContactVerified()    { return this.ciContactActionState === 'success'; }
    get ciEmailVerified()      { return this.ciEmailActionState   === 'success'; }
    get ciContactVerifyLoading(){ return this.ciContactActionState === 'loading'; }
    get ciEmailVerifyLoading()  { return this.ciEmailActionState   === 'loading'; }
    get ciContactVerifyDisabled(){ return this.ciContactVerified || this.ciContactVerifyLoading || this.ciContactNumber.length < 10; }
    get ciEmailVerifyDisabled()  { return this.ciEmailVerified   || this.ciEmailVerifyLoading   || this.ciEmail.length < 5; }

    // ── options getters ───────────────────────────────────────────────────────
    get ciMaritalStatusOpts()    { return CI_MARITAL_STATUS_OPTS; }
    get ciResidenceCountryOpts() { return CI_RESIDENCE_COUNTRY_OPTS; }

    // ── verify action labels ──────────────────────────────────────────────────
    get ciContactVerifyLabel() { return this.ciContactVerified ? 'Verified' : (this.ciContactVerifyLoading ? '...' : 'Verify'); }
    get ciEmailVerifyLabel()   { return this.ciEmailVerified   ? 'Verified' : (this.ciEmailVerifyLoading   ? '...' : 'Verify'); }

    // ── event handlers ────────────────────────────────────────────────────────
    handleCiMaritalStatusChange(event)    { this._updateSectionField('contactInfo', 'maritalStatus',    event.detail?.value || ''); }
    handleCiResidenceCountryChange(event) { this._updateSectionField('contactInfo', 'residenceCountry', event.detail?.value || ''); }
    handleCiContactNumberInput(event) {
        const val = (event.target.value || '').replace(/\D/g, '');
        event.target.value = val;
        this._updateSectionField('contactInfo', 'contactNumber', val);
        if (this.ciContactVerified) {
            this._ciActionStates = { ...this._ciActionStates, contactNumber: 'idle' };
        }
    }
    handleCiEmailInput(event) {
        const val = (event.target.value || '').toLowerCase();
        this._updateSectionField('contactInfo', 'email', val);
        if (this.ciEmailVerified) {
            this._ciActionStates = { ...this._ciActionStates, email: 'idle' };
        }
    }
    handleCiContactVerifyClick(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.ciContactVerified || this.ciContactVerifyLoading) return;
        if (this.ciContactNumber.length < 10) return;
        this._ciActionStates = { ...this._ciActionStates, contactNumber: 'loading' };
        this._lastActionFieldKey = 'contactNumber';
        invokeHandler('contactInfoCheck', 'onAction', this);
    }
    handleCiEmailVerifyClick(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.ciEmailVerified || this.ciEmailVerifyLoading) return;
        if (this.ciEmail.length < 5) return;
        this._ciActionStates = { ...this._ciActionStates, email: 'loading' };
        this._lastActionFieldKey = 'email';
        invokeHandler('contactInfoCheck', 'onAction', this);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END CONTACT INFO
    // ════════════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════════════
    // CLIENT LAYER HANDLER BRIDGE
    // Exposes the same ctx interface expected by sfLOSClientLayerDocumentVerification
    // (and any other client-layer handlers): ctx.fields, ctx.setActionState,
    // ctx.updateFieldValue, ctx._fileMap, ctx._lastActionFieldKey, ctx._ciActionStates
    // ════════════════════════════════════════════════════════════════════════════

    _lastActionFieldKey = '';
    @track _fileMap     = {};
    @track _ciActionStates = {};

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
     * Handles: 'panCardNumber' | 'extractedPanCardNumber' → DV section
     *          'email' | 'contactNumber'                  → CI section
     */
    setActionState(key, state) {
        if (!['idle', 'loading', 'success'].includes(state)) return;
        if (key === 'panCardNumber' || key === 'extractedPanCardNumber') {
            this._dvActionStates = { ...this._dvActionStates, extractedPanCardNumber: state };
            if (state === 'success') {
                this._updateSectionField('documentVerification', 'pancardVerificationStatus', 'success');
            }
        } else if (key === 'email' || key === 'contactNumber') {
            this._ciActionStates = { ...this._ciActionStates, [key]: state };
        }
    }

    /**
     * Generic field-value updater called by client-layer handlers.
     * Routes the key to the correct section field-value map.
     */
    updateFieldValue(key, value) {
        const dvKeys = [
            'isPanAvailable', 'panCardUploadElement', 'form60UploadElement',
            'extractedFirstName', 'extractedLastName', 'extractedPanCardNumber',
            'extractedDateOfBirth', 'pancardVerificationStatus', 'pancardVerificationErrorMessage'
        ];
        const ciKeys = [
            'maritalStatus', 'residenceCountry', 'contactNumber', 'email',
            'emailVerificationStatus', 'emailVerificationErrorMessage',
            'contactVerificationStatus', 'contactVerificationErrorMessage'
        ];
        if (dvKeys.includes(key))      this._updateSectionField('documentVerification', key, value);
        else if (ciKeys.includes(key)) this._updateSectionField('contactInfo', key, value);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // END CLIENT LAYER HANDLER BRIDGE
    // ════════════════════════════════════════════════════════════════════════════

    // ── Loading / UI state ────────────────────────────────────────────────────
    @track isLoading = true;

    // ── Dynamic Component Modal ───────────────────────────────────────────────
    @track showDynamicComponentModal = false;
    @track dynamicComponentName      = '';
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
        this.dynamicComponentProps = extraProps;
        this.showDynamicComponentModal = !!this.dynamicComponentName;
    }

    // ── Integration Progress Modal ────────────────────────────────────────────
    @track showIntegrationProgressModal            = false;
    @track integrationProgressModalStatus          = 'loading';
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
            numberOfVehicles: this.numberOfVehicles,
            vehicleType:      this.vehicleType,
            applicationType:  this.applicationType,
            customerType:     this.customerType,
            applicantType:    this.applicantType,
            entityName:       this.entityName,
            segment:          this.segment
        };
    }

    // ── Section visibility ────────────────────────────────────────────────────
    get showLoanBasicInfo() {
        if (!this.productType || !this.numberOfVehicles || !this.applicationType) return false;
        if (this._isNI && (!this.customerType || !this.applicantType || !this.entityName)) return false;
        if (this.productType === 'Two Wheeler') {
            if (!this.vehicleType) return false;
            if (this.vehicleType === 'New' && !this.segment) return false;
        }
        return true;
    }
    get showLoanDetail()           { return this._evalRule(SHOW_LOAN_DETAIL_RULE,            this.loanBasicInfoFieldValues); }
    get showProfessionalDetail()   { return this._evalRule(SHOW_PROFESSIONAL_DETAIL_RULE,    this.allFieldValues); }
    get showDocumentVerification() { return this._evalRule(SHOW_DOCUMENT_VERIFICATION_RULE,  this.allFieldValues); }
    get showContactInfo()          { return this._evalRule(SHOW_CONTACT_INFO_RULE,            this.allFieldValues); }

    get _showPancardNote() { return this._evalRule(ANNUAL_INCOME_MESSAGE_RULE.rule, this.allFieldValues); }
    get _pancardNoteMsg()  { return this._showPancardNote ? ANNUAL_INCOME_MESSAGE_RULE.message : ''; }
    get _pancardNoteIcon() { return this._showPancardNote ? ANNUAL_INCOME_MESSAGE_RULE.icon : 'utility:info'; }

    // ── Next button ───────────────────────────────────────────────────────────
    get isNextDisabled() { return this._computeIsNextDisabled(); }
    get nextButtonClass() {
        return `bmp-primary-btn p4-button-text${this.isNextDisabled ? ' bmp-primary-btn-disabled' : ''}`;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    connectedCallback() {
        if (!this._recordId) this.isLoading = false;
        this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e);
        window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        // opendynamiccomponentmodal is dispatched via ctx.dispatchEvent() where ctx IS this
        // component, so the event fires from the host element and bubbles upward — it never
        // re-enters the template. Catch it on the host element itself.
        this._dynamicModalHandler = (e) => this.handleOpenDynamicComponentModal(e);
        this.addEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
    }

    disconnectedCallback() {
        if (this._integrationProgressHandler) {
            window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        }
        if (this._dynamicModalHandler) {
            this.removeEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
        }
    }

    async _loadPageData() {
        if (!this.recordId) {
            this._resetAllSections();
            this.isLoading = false;
            return;
        }
        this.isLoading = true;
        try {
            const data = await getBorrowerPageData({
                apexClassName: APEX_CLASS,
                apexMethodName: APEX_METHOD,
                recordId: this.recordId,
                params: {}
            });

            // ── Apex response is now a flat key→value map ─────────────────────
            const d = data || {};

            // ── Stage flag (drives editable vs readonly across all sections) ──
            this.isLeadDetailsStage = typeof d.loanStage === 'string' && d.loanStage.includes(STAGE_LEAD_DETAILS);

            // ── Application Details ───────────────────────────────────────────
            this.productType      = d.productType      || '';
            this.numberOfVehicles = d.numberOfVehicles || '';
            this.vehicleType      = d.vehicleType      || '';
            this.applicationType  = d.applicationType  || '';
            this.customerType     = d.customerType     || '';
            this.applicantType    = d.applicantType    || '';
            this.entityName       = d.entityName       || '';
            this.segment          = d.segment          || '';

            // ── Loan Basic Info ───────────────────────────────────────────────
            this.loanBasicInfoFieldValues = {
                accountId:        d.accountId        ?? null,
                accountName:      d.accountName      || '',
                leadNumber:       d.leadNumber       || '',
                vehicleType:      d.vehicleType      || '',
                agentBranchName:  d.agentBranchName  || '',
                purposeOfPurchase: d.purposeOfPurchase || ''
            };

            // ── Loan Detail ───────────────────────────────────────────────────
            this.loanDetailFieldValues = {
                segment:            d.segment            || '',
                requiredLoanAmount: d.requiredLoanAmount ?? ''
            };

            // ── Professional Detail ───────────────────────────────────────────
            this.professionalDetailFieldValues = {
                profileType:    d.profileType    || '',
                incomeAvailable: d.incomeAvailable || '',
                annualIncome:   d.annualIncome    ?? '',
                evaluationType: d.evaluationType  || ''
            };

            // ── Document Verification ─────────────────────────────────────────
            this.documentVerificationFieldValues = {
                isPanAvailable:          d.isPanAvailable          || '',
                panCardUploadElement:    d.panCardUploadElement     ?? null,
                form60UploadElement:     d.form60UploadElement      ?? null,
                extractedFirstName:      d.extractedFirstName       || '',
                extractedLastName:       d.extractedLastName        || '',
                extractedPanCardNumber:  d.extractedPanCardNumber   || '',
                extractedDateOfBirth:    d.extractedDateOfBirth     || '',
                pancardVerificationStatus: d.pancardVerificationStatus || ''
            };

            // ── Restore DV action states from persisted verification status ──────
            if (d.pancardVerificationStatus === 'success') {
                this._dvActionStates = { ...this._dvActionStates, extractedPanCardNumber: 'success' };
            }

            // ── Contact Info — preserve user-typed values; only overwrite when Apex has non-empty value ─
            const ciKeys = ['maritalStatus', 'residenceCountry', 'contactNumber', 'email'];
            for (const k of ciKeys) {
                if (hasVal(d[k])) this.contactInfoFieldValues = { ...this.contactInfoFieldValues, [k]: d[k] };
            }

            // ── Restore CI action states from persisted verification status ──────
            if (d.contactVerificationStatus === 'success') {
                this._ciActionStates = { ...this._ciActionStates, contactNumber: 'success' };
            }
            if (d.emailVerificationStatus === 'success') {
                this._ciActionStates = { ...this._ciActionStates, email: 'success' };
            }

        } catch (e) {
            this._resetAllSections();
        } finally {
            this.isLoading = false;
        }
    }

    _resetAllSections() {
        this.loanBasicInfoFieldValues = {}; this.isLeadDetailsStage = false;
        this.loanDetailFieldValues = {};
        this.professionalDetailFieldValues = {};
        this.documentVerificationFieldValues = {};
        this.contactInfoFieldValues = {};
    }

    // ── Generic handlers for Apex sections (use data-section + data-key) ──────
    handleGenericInput(event) {
        const key     = event.target?.dataset?.key;
        const section = event.target?.dataset?.section;
        if (key && section) this._updateSectionField(section, key, event.target.value || '');
    }

    _updateSectionField(section, key, value) {
        if (section === 'loanBasicInfo')        this.loanBasicInfoFieldValues        = { ...this.loanBasicInfoFieldValues,        [key]: value };
        else if (section === 'loanDetail')      this.loanDetailFieldValues           = { ...this.loanDetailFieldValues,           [key]: value };
        else if (section === 'professionalDetail') this.professionalDetailFieldValues = { ...this.professionalDetailFieldValues,   [key]: value };
        else if (section === 'documentVerification') this.documentVerificationFieldValues = { ...this.documentVerificationFieldValues, [key]: value };
        else if (section === 'contactInfo')     this.contactInfoFieldValues          = { ...this.contactInfoFieldValues,          [key]: value };
    }

    // ── Integration Progress Modal handlers ───────────────────────────────────
    handleIntegrationProgressUpdate(event) {
        const d = event.detail || {};
        this.showIntegrationProgressModal            = d.show !== false;
        this.integrationProgressModalStatus          = d.status || 'loading';
        this.integrationProgressModalCurrentStageIdx = d.currentStageIndex ?? 0;
        this.integrationProgressModalStages          = d.stages || [];
        this.integrationProgressModalErrorMessage    = d.errorMessage || '';
    }
    handleIntegrationProgressModalClose() { this.showIntegrationProgressModal = false; }
    handleIntegrationProgressModalRetry() {
        this.integrationProgressModalStatus = 'loading';
        this.integrationProgressModalCurrentStageIdx = 0;
        this.integrationProgressModalErrorMessage = '';
    }
    handleIntegrationProgressModalDone() { this.showIntegrationProgressModal = false; }

    // ── Next / Save ───────────────────────────────────────────────────────────
    async handleNextButton() {
        if (this.isNextDisabled) return;
        this.isLoading = true;
        try {
            const params   = this._normalizeParamsForSave(this.allFieldValues);
            const response = await savePageData({
                apexClassName: SAVE_APEX_CLASS,
                apexMethodName: SAVE_APEX_METHOD,
                recordId: this.recordId,
                params
            });
            if (response.isSuccess) {
                //await invokeHandler('borrowerNextIntegration', 'onNextButton', this);
                const stageName = this.tab || STAGE_LEAD_DETAILS;
                const currentViewId = this.currentViewId;
                if (!currentViewId) {
                    this._hideGlobalLoaderIfShown();
                    this._toast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error');
                    return;
                }
                window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
                    detail: {
                        currentViewId,
                        id: currentViewId,
                        applicantId:             this.applicantId,
                        currentLoanStageComplete: this.tab || STAGE_LEAD_DETAILS,
                        currentStagePhrase:       this.stagePhrase || ''
                    },
                    bubbles: true, composed: true
                }));
            } else {
                this._hideGlobalLoaderIfShown();
                this._toast('Save Failed', response.message || 'Failed to save data.', 'error');
            }
        } catch (error) {
            this._hideGlobalLoaderIfShown();
            this._toast('Error', error?.message || 'An unexpected error occurred.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new CustomEvent('showtoast', {
            detail: { title, message, variant },
            bubbles: true, composed: true
        }));
    }

    /** Hides the global loader exactly once if we showed it. Called on save error,
     *  missing currentViewId, or unexpected catch — so the user is never left behind
     *  the loading backdrop when navigation fails. */
    _globalLoaderShown = false;
    _hideGlobalLoaderIfShown() {
        if (this._globalLoaderShown) {
            this._globalLoaderShown = false;
            window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } }));
        }
    }

    // ── Agent branch name side-effect ─────────────────────────────────────────
    _refreshAgentBranchName(accountId) {
        if (!this.recordId || !accountId) return;
        const key = `${accountId}|${this.productType}`;
        if (key === this._lastAgentBranchKey) return;
        this._lastAgentBranchKey = key;
        getAgentBranchName({ recordId: this.recordId, accountId, productType: this.productType })
            .then(name => {
                this.loanBasicInfoFieldValues = { ...this.loanBasicInfoFieldValues, agentBranchName: name || 'N/A' };
            })
            .catch(() => {});
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
        return out;
    }

    // ── Next button disabled computation ──────────────────────────────────────
    _computeIsNextDisabled() {
        if (this.isLoading)                return true;
        if (!this._isAppDetailsComplete()) return true;
        if (this.showLoanBasicInfo) {
            const lbFv = this.loanBasicInfoFieldValues;
            const ldFv = this.loanDetailFieldValues;
            if (!hasVal(lbFv.accountId))       return true;
            if (!hasVal(lbFv.vehicleType))     return true;
            if (!hasVal(lbFv.purposeOfPurchase)) return true;
            if (!hasVal(ldFv.requiredLoanAmount)) return true;
        }
        if (this.showProfessionalDetail) {
            const pdFv = this.professionalDetailFieldValues;
            if (!hasVal(pdFv.profileType))     return true;
            if (!hasVal(pdFv.incomeAvailable)) return true;
            if (pdFv.incomeAvailable === 'Yes' && !hasVal(pdFv.annualIncome)) return true;
        }
        if (this.showDocumentVerification) {
            const dvFv = this.documentVerificationFieldValues;
            if (!hasVal(dvFv.isPanAvailable)) return true;
            if (dvFv.isPanAvailable === 'Yes') {
                const verified = (dvFv.pancardVerificationStatus || '') === 'Success';
                if (!verified && !hasVal(dvFv.panCardUploadElement)) return true;
            }
            if (dvFv.isPanAvailable === 'No' && !hasVal(dvFv.form60UploadElement)) return true;
        }
        if (this.showContactInfo) {
            const cFv = this.contactInfoFieldValues;
            if (!hasVal(cFv.contactNumber || cFv.phone))       return true;
            if (!hasVal(cFv.email || cFv.emailAddress))        return true;
        }
        return false;
    }
}