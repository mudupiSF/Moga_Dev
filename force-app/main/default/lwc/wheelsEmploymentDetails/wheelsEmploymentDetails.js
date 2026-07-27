import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { invokeHandler } from 'c/clientLayerHelper';
import SPECIAL_ICONS from '@salesforce/resourceUrl/special_icons';
import linkEmploymentDocument from '@salesforce/apex/WheelsEmploymentDetailsController.linkEmploymentDocument';
import loadEmploymentDocuments from '@salesforce/apex/WheelsEmploymentDetailsController.loadEmploymentDocuments';
import deactivateDocument from '@salesforce/apex/DocumentChecklistToggleController.deactivateDocument';
import getUserSessionId from '@salesforce/apex/embedCustomFileUploadController.getUserSessionId';
import generateEmailOTP from '@salesforce/apex/SendEmailOTPAPIController.generateOTP';
import loadEmploymentContext from '@salesforce/apex/WheelsEmploymentDetailsController.loadEmploymentContext';
import saveEmploymentDetails from '@salesforce/apex/WheelsEmploymentDetailsController.saveEmploymentDetails';
import markEmploymentWorkEmailVerified from '@salesforce/apex/WheelsEmploymentDetailsController.markEmploymentWorkEmailVerified';
import markEmploymentStepComplete from '@salesforce/apex/WheelsEmploymentDetailsController.markEmploymentStepComplete';

const INTEGRATION_PROGRESS_EVENT = 'integrationprogressupdate';
const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const STAGE_EMPLOYMENT = 'Occupation Details';
// #region agent log
function debugOccupationLog(location, message, data, hypothesisId) {
    fetch('http://127.0.0.1:7938/ingest/4be970d2-c130-4bf4-a57b-c7fb436b25c2', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Debug-Session-Id': '61f25c' },
        body: JSON.stringify({
            sessionId: '61f25c',
            runId: 'pre-fix',
            hypothesisId,
            location,
            message,
            data,
            timestamp: Date.now()
        })
    }).catch(() => {});
}
// #endregion
const EMPLOYMENT_CATEGORY_PRIMARY = 'Primary';
const EMPLOYMENT_CATEGORY_PREVIOUS = 'Previous';

const TAB_SALARIED              = 'Salaried';
const TAB_SELF_EMP_PROFESSIONAL = 'Self-Employed Professional';
const TAB_SELF_EMP_NON_PROF     = 'Self-Employed Non-Professional';

const PROFESSION_DOCTOR     = 'doctor';
const PROFESSION_CA         = 'ca';
const PROFESSION_ADVOCATE   = 'advocate';
const PROFESSION_ARCHITECT  = 'architect';
const PROFESSION_CONSULTANT = 'consultant';
const PROFESSION_OTHER      = 'other';

const PROFESSION_TYPES = [
    { value: PROFESSION_DOCTOR,     label: 'Doctor / Medical Professional', icon: 'utility:heart',        iconWrapClass: 'form-profession-icon-wrap--doctor' },
    { value: PROFESSION_CA,         label: 'Chartered Accountant',          icon: 'utility:number_input', iconWrapClass: 'form-profession-icon-wrap--ca' },
    { value: PROFESSION_ADVOCATE,   label: 'Advocate / Lawyer',             icon: 'utility:rules',        iconWrapClass: 'form-profession-icon-wrap--advocate' },
    { value: PROFESSION_ARCHITECT,  label: 'Architect',                     icon: 'utility:home',         iconWrapClass: 'form-profession-icon-wrap--architect' },
    { value: PROFESSION_CONSULTANT, label: 'Independent Consultant',          icon: 'utility:case',         iconWrapClass: 'form-profession-icon-wrap--consultant' },
    { value: PROFESSION_OTHER,      label: 'Other Self-Employed Professional', icon: 'utility:user',      iconWrapClass: 'form-profession-icon-wrap--other' }
];

const PROFESSION_FIELD_CONFIG = {
    [PROFESSION_DOCTOR]: {
        regLabel: 'Medical Council Registration No.',
        regPlaceholder: 'e.g. MCI-2023-00123',
        regField: 'medicalCouncilRegistrationNumber',
        bodyLabel: 'Medical Council',
        bodyField: 'professionalBody',
        bodyOptions: 'medicalCouncil'
    },
    [PROFESSION_CA]: {
        regLabel: 'ICAI Membership No.',
        regPlaceholder: 'e.g. 123456',
        regField: 'icaiMembershipNo',
        bodyLabel: 'Professional Body',
        bodyField: 'professionalBody',
        bodyOptions: 'ca'
    },
    [PROFESSION_ADVOCATE]: {
        regLabel: 'Bar Council Enrollment No.',
        regPlaceholder: 'e.g. D/1234/2018',
        regField: 'barCouncilEnrollmentNo',
        bodyLabel: 'Bar Council',
        bodyField: 'barCouncil',
        bodyOptions: 'barCouncil'
    },
    [PROFESSION_ARCHITECT]: {
        regLabel: 'Council of Architecture Reg. No.',
        regPlaceholder: 'e.g. CA/2019/12345',
        regField: 'councilOfArchitectureRegNo',
        bodyLabel: 'Professional Body',
        bodyField: 'professionalBody',
        bodyOptions: 'architect'
    },
    [PROFESSION_CONSULTANT]: {
        regLabel: 'Professional Certification / Licence No.',
        regPlaceholder: 'Enter registration number',
        regField: 'professionalCertificationLicenceNo',
        bodyLabel: 'Professional Body',
        bodyField: 'professionalBody',
        bodyOptions: 'general'
    },
    [PROFESSION_OTHER]: {
        regLabel: 'Registration / Licence No.',
        regPlaceholder: 'Enter registration number',
        regField: 'registrationLicenceNo',
        bodyLabel: 'Professional Body',
        bodyField: 'professionalBody',
        bodyOptions: 'general'
    }
};

const MEDICAL_COUNCIL_OPTIONS = [
    { label: 'Medical Council of India', value: 'Medical Council of India' },
    { label: 'State Medical Council', value: 'State Medical Council' }
];

const CA_BODY_OPTIONS = [
    { label: 'ICAI', value: 'ICAI' },
    { label: 'ICSI', value: 'ICSI' }
];

const BAR_COUNCIL_OPTIONS = [
    { label: 'Bar Council of India', value: 'Bar Council of India' },
    { label: 'State Bar Council', value: 'State Bar Council' }
];

const ARCHITECT_BODY_OPTIONS = [
    { label: 'Council of Architecture', value: 'Council of Architecture' }
];

const PROFESSIONAL_BODY_OPTIONS = [
    { label: 'ICAI', value: 'ICAI' },
    { label: 'ICSI', value: 'ICSI' },
    { label: 'Medical Council of India', value: 'Medical Council of India' },
    { label: 'State Medical Council', value: 'State Medical Council' },
    { label: 'Bar Council of India', value: 'Bar Council of India' },
    { label: 'State Bar Council', value: 'State Bar Council' },
    { label: 'Council of Architecture', value: 'Council of Architecture' },
    { label: 'Other', value: 'Other' }
];

const EMPLOYMENT_TYPE_OPTIONS = [];

const INDUSTRY_SECTOR_OPTIONS = [];

const NATURE_OF_BUSINESS_OPTIONS = [
    { label: 'Trading',       value: 'Trading' },
    { label: 'Manufacturing', value: 'Manufacturing' },
    { label: 'Retail',        value: 'Retail' },
    { label: 'Wholesale',     value: 'Wholesale' },
    { label: 'Services',      value: 'Services' },
    { label: 'Agriculture',   value: 'Agriculture' },
    { label: 'Other',         value: 'Other' }
];

const BUSINESS_CONSTITUTION_OPTIONS = [
    { label: 'Proprietorship',  value: 'Proprietorship' },
    { label: 'Partnership',     value: 'Partnership' },
    { label: 'Private Limited', value: 'Private Limited' },
    { label: 'Public Limited',  value: 'Public Limited' },
    { label: 'LLP',             value: 'LLP' },
    { label: 'Other',           value: 'Other' }
];

const ACC_SECTION_SALARIED = 'salariedEmployment';
const ACC_SECTION_HR_PAYROLL = 'hrPayrollContact';
const ACC_SECTION_SELF_EMP_PROFESSIONAL = 'selfEmployedProfessional';
const ACC_SECTION_SELF_EMP_NON_PROFESSIONAL = 'selfEmployedNonProfessional';
const ACC_SECTION_PREVIOUS = 'previousEmployment';
const ACC_SECTION_SUPPORTING_DOCUMENTS = 'supportingDocuments';

const ACCEPTED_DOCUMENT_FORMATS = ['.pdf', '.jpg', '.jpeg', '.png'];
const EMAIL_REGEX = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
/** Indian mobile numbers: 10 digits, first digit between 6 and 9. */
const MOBILE_REGEX = /^[6-9]\d{9}$/;
const PHONE_MAX_LENGTH = 10;

const getPhoneDigits = (phoneNumber) => String(phoneNumber || '').replace(/\D/g, '');

const isInvalidPhoneNumber = (phoneNumber) => {
    const digits = getPhoneDigits(phoneNumber);
    return hasVal(digits) && !MOBILE_REGEX.test(digits);
};

const getPhoneNumberFormatError = (phoneNumber) => {
    if (!isInvalidPhoneNumber(phoneNumber)) {
        return '';
    }
    const digits = getPhoneDigits(phoneNumber);
    if (digits.length > 0 && digits.length < PHONE_MAX_LENGTH) {
        return 'Phone number must be 10 digits';
    }
    return 'Enter a valid 10-digit mobile number (starts with 6–9)';
};

const hasVal = (value) => value != null && String(value).trim() !== '';

const DOCUMENT_LIST_PROFESSIONAL = 'professional';
const DOCUMENT_LIST_NON_PROFESSIONAL = 'nonProfessional';
const OCCUPATION_DOCUMENT_CATEGORY = 'Occupation Details';

const createDocumentSlot = (key, label) => ({
    key,
    label,
    docType: label,
    uploadLabel: `Upload ${label}`,
    uploadTitle: `Upload ${label} File`,
    uploaded: false,
    fileName: '',
    contentDocumentId: '',
    contentVersionId: '',
    documentChecklistId: '',
    fileType: 'PDF',
    files: [],
    expanded: false
});

/**
 * Employment Details sub-stage for the Wheels QDE flow.
 */
export default class WheelsEmploymentDetails extends LightningElement {

    /** Application__c record Id (passed from applicationMasterPage).
     *  Reactive setter: the host reuses this same instance across applicant/stage
     *  switches (lwc:is + lwc:spread), so connectedCallback does NOT re-fire. Loading
     *  on the setter guarantees the page reloads for the newly-selected applicant. */
    _recordId;
    _applicantId;
    @api get recordId() { return this._recordId; }
    set recordId(value) {
        const next = value || null;
        if (next === this._recordId) return;
        this._recordId = next;
        this._scheduleEmploymentLoad();
    }
    @api get applicantId() { return this._applicantId; }
    set applicantId(value) {
        const next = value || null;
        if (next === this._applicantId) return;
        this._applicantId = next;
        this._hasLoadedEmploymentContext = false;
        this._scheduleEmploymentLoad();
    }

    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api isStagePast = false;
    @api applicationStatus;

    /** Passed when loaded via listOfApplicants group flow; unused on direct stage load. */
    @api applicants;
    @api applicantCompletionOverrides;
    @api groupLabel;
    @api overrideLwc;

    @track isPageLoading = false;
    @track _isNonIndividualApplicant = false;
    @track _activeTab = TAB_SALARIED;
    @track _activeProfession = '';
    @track _openAccordions = {
        [ACC_SECTION_SALARIED]: true,
        [ACC_SECTION_HR_PAYROLL]: true,
        [ACC_SECTION_SELF_EMP_PROFESSIONAL]: true,
        [ACC_SECTION_SELF_EMP_NON_PROFESSIONAL]: true,
        [ACC_SECTION_PREVIOUS]: true,
        [ACC_SECTION_SUPPORTING_DOCUMENTS]: true
    };
    @track showPreviousEmployerForm = false;
    @track editingPreviousEmployerId = null;
    @track showMagicUpload = false;
    @track showFilePreviewer = false;
    @track previewContentVersionId;
    @track previewFileName = '';
    @track previewFileExtension = '';
    @track activeUploadChecklistId = '';
    @track activeUploadDocType = '';
    @track activeUploadDocKey = '';
    @track activeUploadListName = '';
    @track activeMaxFiles = 5;
    @track activeAllowedTypes = '.pdf,.jpg,.jpeg,.png';
    _sessionId = null;
    _vfRoot = null;
    @track _workEmailVerifyState = 'idle';
    _lastActionFieldKey = '';
    _integrationProgressHandler;
    _dynamicModalHandler;
    @track showDynamicComponentModal = false;
    @track dynamicComponentName = '';
    @track dynamicComponentModalHeader = '';
    @track dynamicComponentProps = {};
    @track showIntegrationProgressModal = false;
    @track integrationProgressModalStatus = 'loading';
    @track integrationProgressModalHeader = '';
    @track integrationProgressModalCurrentStageIdx = 0;
    @track integrationProgressModalStages = [];
    @track integrationProgressModalErrorMessage = '';
    @track incomeCategory = '';
    employmentRecordId = null;
    _incomeCategoryLocked = false;
    _hasLoadedEmploymentContext = false;
    _loadTimer = null;

    @track employmentData = {
        employerName: '',
        jobTitle: '',
        employmentType: '',
        industrySector: '',
        employmentStartDate: '',
        monthlyGrossSalary: '',
        workAddress: '',
        workEmail: '',
        hrPayrollEmail: '',
        hrPayrollPhoneNumber: '',
        practiceFirmName: '',
        medicalCouncilRegistrationNumber: '',
        icaiMembershipNo: '',
        professionalBody: '',
        barCouncilEnrollmentNo: '',
        barCouncil: '',
        councilOfArchitectureRegNo: '',
        professionalCertificationLicenceNo: '',
        registrationLicenceNo: '',
        dateOfRegistration: '',
        yearsInPractice: '',
        numberOfEmployees: '',
        annualProfessionalIncome: '',
        panNumber: '',
        gstNumber: '',
        businessFirmName: '',
        natureOfBusiness: '',
        businessConstitution: '',
        dateOfCommencement: '',
        businessVintage: '',
        annualTurnover: '',
        annualNetIncome: '',
        udyamNumber: '',
        businessShopAddress: ''
    };

    @track previousEmployers = [];

    @track newPreviousEmployer = {
        employerName: '',
        jobTitle: '',
        employmentType: '',
        industrySector: '',
        employmentStartDate: '',
        employmentEndDate: '',
        workEmail: '',
        hrPayrollPhoneNumber: ''
    };

    @track professionalDocuments = [
        createDocumentSlot('regCertificate', 'Registration Certificate'),
        createDocumentSlot('practiceLicence', 'Practice Licence'),
        createDocumentSlot('latestItr', 'Latest ITR (last 3 years)')
    ];

    @track nonProfessionalDocuments = [
        createDocumentSlot('businessRegistration', 'Business Registration / Shop Act Licence'),
        createDocumentSlot('gstReturns', 'GST Returns (last 12 months)'),
        createDocumentSlot('latestItr', 'Latest ITR (last 3 years)'),
        createDocumentSlot('bankStatements', 'Bank Statements (last 6 months)')
    ];

    @track _isApplicantStageComplete = false;
    @track _saveDetailsSucceeded = false;
    _savedEmploymentSnapshot = null;
    _deletedPreviousEmploymentIds = [];

    employmentTypeOptions = EMPLOYMENT_TYPE_OPTIONS;
    industrySectorOptions = INDUSTRY_SECTOR_OPTIONS;
    natureOfBusinessOptions = NATURE_OF_BUSINESS_OPTIONS;
    businessConstitutionOptions = BUSINESS_CONSTITUTION_OPTIONS;
    professionalBodyOptions = PROFESSIONAL_BODY_OPTIONS;

    // --- Lifecycle ---

    connectedCallback() {
        console.log('wheelsEmploymentDetails recordId:', this.recordId);
        console.log('wheelsEmploymentDetails currentViewId:', this.currentViewId);
        console.log('wheelsEmploymentDetails stagePhrase:', this.stagePhrase);
        console.log('wheelsEmploymentDetails tab:', this.tab);
        console.log('wheelsEmploymentDetails applicantId:', this.applicantId);
        console.log('wheelsEmploymentDetails isStagePast:', this.isStagePast);
        console.log('wheelsEmploymentDetails applicationStatus:', this.applicationStatus);
        console.log('wheelsEmploymentDetails applicants:', this.applicants);
        console.log('wheelsEmploymentDetails applicantCompletionOverrides:', this.applicantCompletionOverrides);
        console.log('wheelsEmploymentDetails groupLabel:', this.groupLabel);
        console.log('wheelsEmploymentDetails overrideLwc:', this.overrideLwc);

        this._integrationProgressHandler = (e) => this.handleIntegrationProgressUpdate(e);
        window.addEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        this._dynamicModalHandler = (e) => this.handleOpenDynamicComponentModal(e);
        this.addEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);

        this._initFilePreviewContext();
        this._scheduleEmploymentLoad();
    }

    /** Debounces load so the recordId + applicantId setters trigger a single reload against the final applicant context. */
    _scheduleEmploymentLoad() {
        if (this._loadTimer != null) {
            clearTimeout(this._loadTimer);
        }
        this._loadTimer = setTimeout(() => {
            this._loadTimer = null;
            this.loadEmploymentData();
        }, 0);
    }

    _initFilePreviewContext() {
        const origin = window.location.origin;
        const isSite = location.pathname.split('/').length >= 2 && location.pathname.split('/')[2] === 's';
        if (isSite) {
            this._vfRoot = origin;
        } else {
            const sandboxSuffix = origin.includes('sandbox') ? '.sandbox' : '';
            this._vfRoot = `${origin.split('.')[0]}--c${sandboxSuffix}.vf.force.com`;
        }
        getUserSessionId()
            .then((id) => { this._sessionId = id; })
            .catch(() => { /* preview download may fail without a session */ });
    }

    disconnectedCallback() {
        if (this._integrationProgressHandler) {
            window.removeEventListener(INTEGRATION_PROGRESS_EVENT, this._integrationProgressHandler);
        }
        if (this._dynamicModalHandler) {
            this.removeEventListener('opendynamiccomponentmodal', this._dynamicModalHandler);
        }
    }

    // --- Initialization and data load ---

    loadEmploymentData() {
        if (!this.recordId && !this.applicantId) {
            this.initializeDocumentChecklists();
            return;
        }

        this.isPageLoading = true;

        loadEmploymentContext({
            recordId: this.recordId || null,
            applicantId: this.applicantId || null
        })
            .then((result) => {
                this.applyEmploymentContext(result);
                this._hasLoadedEmploymentContext = true;
            })
            .catch((error) => {
                this.showError('Error loading employment details', error);
            })
            .finally(() => {
                this.isPageLoading = false;
                this.initializeDocumentChecklists();
            });
    }

    applyEmploymentContext(context) {
        if (!context) {
            return;
        }

        this._applicantId = context.applicantId || this._applicantId || null;
        this._isNonIndividualApplicant = context.isNonIndividualApplicant === true;
        this.incomeCategory = context.incomeCategory || '';

        const employmentTab = this.mapIncomeCategoryToTab(
            context.employmentTab || context.incomeCategory
        );

        if (employmentTab) {
            this._activeTab = employmentTab;
            this._incomeCategoryLocked = !!this.incomeCategory;
        }

        if (Array.isArray(context.employmentTypeOptions) && context.employmentTypeOptions.length) {
            this.employmentTypeOptions = context.employmentTypeOptions;
        }
        if (Array.isArray(context.industrySectorOptions) && context.industrySectorOptions.length) {
            this.industrySectorOptions = context.industrySectorOptions;
        }
        if (Array.isArray(context.natureOfBusinessOptions) && context.natureOfBusinessOptions.length) {
            this.natureOfBusinessOptions = context.natureOfBusinessOptions;
        }
        if (Array.isArray(context.businessConstitutionOptions) && context.businessConstitutionOptions.length) {
            this.businessConstitutionOptions = context.businessConstitutionOptions;
        }

        this.applyPreviousEmployersFromRecords(context.previousEmployments || []);
        this.applyEmploymentRecord(context.primaryEmployment || context.employment);
        this._deletedPreviousEmploymentIds = [];
        this._saveDetailsSucceeded = false;
        this.captureEmploymentSnapshot();

        console.log('wheelsEmploymentDetails incomeCategory:', this.incomeCategory);
        console.log('wheelsEmploymentDetails employmentTab:', this._activeTab);
    }

    get showNiStageNotApplicableMessage() {
        return this._isNonIndividualApplicant;
    }

    mapIncomeCategoryToTab(incomeCategory) {
        if (!hasVal(incomeCategory)) {
            return TAB_SALARIED;
        }

        const normalized = String(incomeCategory).trim().toLowerCase().replace(/-/g, ' ');

        if (normalized === 'salaried') {
            return TAB_SALARIED;
        }
        if (normalized === 'self employed professional') {
            return TAB_SELF_EMP_PROFESSIONAL;
        }
        if (normalized === 'self employed non professional') {
            return TAB_SELF_EMP_NON_PROF;
        }

        return TAB_SALARIED;
    }

    applyEmploymentRecord(employment) {
        const record = employment || {};

        this.employmentRecordId = record.employmentId || null;
        this.employmentData = {
            ...this.employmentData,
            employerName: record.employerName || '',
            jobTitle: record.jobTitle || '',
            employmentType: record.employmentType || '',
            industrySector: record.industrySector || '',
            employmentStartDate: record.employmentStartDate || '',
            monthlyGrossSalary: record.monthlyGrossSalary || '',
            workAddress: record.workAddress || '',
            workEmail: (record.workEmail || '').toLowerCase(),
            hrPayrollEmail: (record.hrPayrollEmail || '').toLowerCase(),
            hrPayrollPhoneNumber: record.hrPayrollPhoneNumber || '',
            practiceFirmName: record.practiceFirmName || '',
            medicalCouncilRegistrationNumber: record.medicalCouncilRegistrationNumber || '',
            icaiMembershipNo: record.icaiMembershipNo || '',
            professionalBody: record.professionalBody || '',
            barCouncilEnrollmentNo: record.barCouncilEnrollmentNo || '',
            barCouncil: record.barCouncil || '',
            councilOfArchitectureRegNo: record.councilOfArchitectureRegNo || '',
            professionalCertificationLicenceNo: record.professionalCertificationLicenceNo || '',
            registrationLicenceNo: record.registrationLicenceNo || '',
            dateOfRegistration: record.dateOfRegistration || '',
            yearsInPractice: record.yearsInPractice || '',
            numberOfEmployees: record.numberOfEmployees || '',
            annualProfessionalIncome: record.annualProfessionalIncome || '',
            panNumber: record.panNumber || '',
            gstNumber: record.gstNumber || '',
            businessFirmName: record.businessFirmName || '',
            natureOfBusiness: record.natureOfBusiness || '',
            businessConstitution: record.businessConstitution || '',
            dateOfCommencement: record.dateOfCommencement || '',
            businessVintage: record.businessVintage || '',
            annualTurnover: record.annualTurnover || '',
            annualNetIncome: record.annualNetIncome || '',
            udyamNumber: record.udyamNumber || '',
            businessShopAddress: record.businessShopAddress || ''
        };
        if (record.professionType) {
            this._activeProfession = record.professionType;
        } else {
            this._activeProfession = '';
        }
        this.applyWorkEmailVerifyState(record.emailVerified === true);
    }

    applyWorkEmailVerifyState(isVerified) {
        this._workEmailVerifyState = isVerified ? 'success' : 'idle';
    }

    applyPreviousEmployersFromRecords(records) {
        this.previousEmployers = (records || []).map((record) => this.mapPreviousEmployerRecord(record));
    }

    mapPreviousEmployerRecord(record) {
        const mapped = {
            id: record.employmentId || `temp-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
            employmentId: record.employmentId || null,
            employerName: record.employerName || '',
            jobTitle: record.jobTitle || '',
            employmentType: record.employmentType || '',
            industrySector: record.industrySector || '',
            employmentStartDate: record.employmentStartDate || '',
            employmentEndDate: record.employmentEndDate || '',
            workEmail: (record.workEmail || '').toLowerCase(),
            hrPayrollPhoneNumber: record.hrPayrollPhoneNumber || ''
        };
        mapped.summary = this.buildPreviousEmployerSummary(mapped);
        return mapped;
    }

    buildPreviousEmployerSummary(data) {
        const jobPart = data.jobTitle && data.employmentType
            ? `${data.jobTitle} (${data.employmentType})`
            : (data.jobTitle || data.employmentType || '');
        return [
            jobPart,
            data.industrySector,
            this.formatYearRange(data.employmentStartDate, data.employmentEndDate)
        ].filter(Boolean).join(' • ');
    }

    // --- Save payload helpers ---

    normalizeEmploymentPayload(payload = {}) {
        const normalized = {
            employmentCategory: EMPLOYMENT_CATEGORY_PRIMARY
        };

        if (this.isSalaried) {
            return {
                ...normalized,
                employerName: (payload.employerName || '').trim(),
                jobTitle: (payload.jobTitle || '').trim(),
                employmentType: (payload.employmentType || '').trim(),
                industrySector: (payload.industrySector || '').trim(),
                employmentStartDate: (payload.employmentStartDate || '').trim(),
                monthlyGrossSalary: (payload.monthlyGrossSalary || '').trim(),
                workAddress: (payload.workAddress || '').trim(),
                workEmail: (payload.workEmail || '').trim().toLowerCase(),
                hrPayrollEmail: (payload.hrPayrollEmail || '').trim().toLowerCase(),
                hrPayrollPhoneNumber: (payload.hrPayrollPhoneNumber || '').trim()
            };
        }

        if (this.isSelfEmployedProfessional) {
            return {
                ...normalized,
                professionType: (payload.professionType || '').trim(),
                practiceFirmName: (payload.practiceFirmName || '').trim(),
                medicalCouncilRegistrationNumber: (payload.medicalCouncilRegistrationNumber || '').trim(),
                icaiMembershipNo: (payload.icaiMembershipNo || '').trim(),
                professionalBody: (payload.professionalBody || '').trim(),
                barCouncilEnrollmentNo: (payload.barCouncilEnrollmentNo || '').trim(),
                barCouncil: (payload.barCouncil || '').trim(),
                councilOfArchitectureRegNo: (payload.councilOfArchitectureRegNo || '').trim(),
                professionalCertificationLicenceNo: (payload.professionalCertificationLicenceNo || '').trim(),
                registrationLicenceNo: (payload.registrationLicenceNo || '').trim(),
                dateOfRegistration: (payload.dateOfRegistration || '').trim(),
                yearsInPractice: (payload.yearsInPractice || '').trim(),
                numberOfEmployees: (payload.numberOfEmployees || '').trim(),
                annualProfessionalIncome: (payload.annualProfessionalIncome || '').trim(),
                panNumber: (payload.panNumber || '').trim(),
                gstNumber: (payload.gstNumber || '').trim(),
                workAddress: (payload.workAddress || '').trim()
            };
        }

        if (this.isSelfEmployedNonProfessional) {
            return {
                ...normalized,
                businessFirmName: (payload.businessFirmName || '').trim(),
                natureOfBusiness: (payload.natureOfBusiness || '').trim(),
                businessConstitution: (payload.businessConstitution || '').trim(),
                dateOfCommencement: (payload.dateOfCommencement || '').trim(),
                businessVintage: (payload.businessVintage || '').trim(),
                numberOfEmployees: (payload.numberOfEmployees || '').trim(),
                annualTurnover: (payload.annualTurnover || '').trim(),
                annualNetIncome: (payload.annualNetIncome || '').trim(),
                panNumber: (payload.panNumber || '').trim(),
                gstNumber: (payload.gstNumber || '').trim(),
                udyamNumber: (payload.udyamNumber || '').trim(),
                businessShopAddress: (payload.businessShopAddress || '').trim()
            };
        }

        return normalized;
    }

    normalizePreviousEmployerPayload(record = {}) {
        return {
            employmentId: record.employmentId || null,
            employerName: (record.employerName || '').trim(),
            jobTitle: (record.jobTitle || '').trim(),
            employmentType: (record.employmentType || '').trim(),
            industrySector: (record.industrySector || '').trim(),
            employmentStartDate: (record.employmentStartDate || '').trim(),
            employmentEndDate: (record.employmentEndDate || '').trim(),
            workEmail: (record.workEmail || '').trim().toLowerCase(),
            hrPayrollPhoneNumber: (record.hrPayrollPhoneNumber || '').trim(),
            employmentCategory: EMPLOYMENT_CATEGORY_PREVIOUS
        };
    }

    buildPreviousEmployerSavePayload() {
        return this.previousEmployers.map((record) => this.normalizePreviousEmployerPayload(record));
    }

    buildFullSavePayload() {
        return {
            primary: {
                ...this.buildEmploymentSavePayload(),
                employmentId: this.employmentRecordId || null
            },
            previousEmployers: this.showPreviousEmploymentSection
                ? this.buildPreviousEmployerSavePayload()
                : [],
            deletedPreviousEmploymentIds: this.showPreviousEmploymentSection
                ? [...this._deletedPreviousEmploymentIds]
                : []
        };
    }

    captureEmploymentSnapshot() {
        this._savedEmploymentSnapshot = JSON.stringify({
            primary: this.normalizeEmploymentPayload(this.buildEmploymentSavePayload()),
            previous: this.buildPreviousEmployerSavePayload(),
            deleted: [...this._deletedPreviousEmploymentIds].sort()
        });
    }

    hasEmploymentChanges() {
        const currentSnapshot = JSON.stringify({
            primary: this.normalizeEmploymentPayload(this.buildEmploymentSavePayload()),
            previous: this.buildPreviousEmployerSavePayload(),
            deleted: [...this._deletedPreviousEmploymentIds].sort()
        });
        if (this._savedEmploymentSnapshot == null) {
            const primaryValues = Object.values(JSON.parse(currentSnapshot).primary || {});
            const hasPrimary = primaryValues.some((value) => hasVal(value));
            const hasPrevious = (JSON.parse(currentSnapshot).previous || []).length > 0;
            return hasPrimary || hasPrevious;
        }
        return currentSnapshot !== this._savedEmploymentSnapshot;
    }

    isSalesforceId(value) {
        return typeof value === 'string'
            && /^[a-zA-Z0-9]{15,18}$/.test(value)
            && !value.startsWith('temp-');
    }

    applySaveResult(result) {
        if (result?.primaryEmployment) {
            this.applyEmploymentRecord(result.primaryEmployment);
        } else if (result?.primaryEmploymentId) {
            this.employmentRecordId = result.primaryEmploymentId;
        }
        if (Array.isArray(result?.previousEmployments)) {
            this.applyPreviousEmployersFromRecords(result.previousEmployments);
        }
        this._deletedPreviousEmploymentIds = [];
        this.captureEmploymentSnapshot();
    }

    buildEmploymentSavePayload() {
        const base = {
            employmentCategory: EMPLOYMENT_CATEGORY_PRIMARY
        };

        if (this.isSalaried) {
            return {
                ...base,
                employerName: this.employmentData.employerName || '',
                jobTitle: this.employmentData.jobTitle || '',
                employmentType: this.employmentData.employmentType || '',
                industrySector: this.employmentData.industrySector || '',
                employmentStartDate: this.employmentData.employmentStartDate || '',
                monthlyGrossSalary: this.employmentData.monthlyGrossSalary || '',
                workAddress: this.employmentData.workAddress || '',
                workEmail: (this.employmentData.workEmail || '').trim().toLowerCase(),
                hrPayrollEmail: (this.employmentData.hrPayrollEmail || '').trim().toLowerCase(),
                hrPayrollPhoneNumber: (this.employmentData.hrPayrollPhoneNumber || '').trim(),
                emailVerified: this.workEmailVerified
            };
        }

        if (this.isSelfEmployedProfessional) {
            return {
                ...base,
                professionType: this._activeProfession || '',
                practiceFirmName: this.employmentData.practiceFirmName || '',
                medicalCouncilRegistrationNumber: this.employmentData.medicalCouncilRegistrationNumber || '',
                icaiMembershipNo: this.employmentData.icaiMembershipNo || '',
                professionalBody: this.employmentData.professionalBody || '',
                barCouncilEnrollmentNo: this.employmentData.barCouncilEnrollmentNo || '',
                barCouncil: this.employmentData.barCouncil || '',
                councilOfArchitectureRegNo: this.employmentData.councilOfArchitectureRegNo || '',
                professionalCertificationLicenceNo: this.employmentData.professionalCertificationLicenceNo || '',
                registrationLicenceNo: this.employmentData.registrationLicenceNo || '',
                dateOfRegistration: this.employmentData.dateOfRegistration || '',
                yearsInPractice: this.employmentData.yearsInPractice || '',
                numberOfEmployees: this.employmentData.numberOfEmployees || '',
                annualProfessionalIncome: this.employmentData.annualProfessionalIncome || '',
                panNumber: this.employmentData.panNumber || '',
                gstNumber: this.employmentData.gstNumber || '',
                workAddress: this.employmentData.workAddress || ''
            };
        }

        if (this.isSelfEmployedNonProfessional) {
            return {
                ...base,
                businessFirmName: this.employmentData.businessFirmName || '',
                natureOfBusiness: this.employmentData.natureOfBusiness || '',
                businessConstitution: this.employmentData.businessConstitution || '',
                dateOfCommencement: this.employmentData.dateOfCommencement || '',
                businessVintage: this.employmentData.businessVintage || '',
                numberOfEmployees: this.employmentData.numberOfEmployees || '',
                annualTurnover: this.employmentData.annualTurnover || '',
                annualNetIncome: this.employmentData.annualNetIncome || '',
                panNumber: this.employmentData.panNumber || '',
                gstNumber: this.employmentData.gstNumber || '',
                udyamNumber: this.employmentData.udyamNumber || '',
                businessShopAddress: this.employmentData.businessShopAddress || ''
            };
        }

        return base;
    }

    // --- UI event handlers ---

    handleAccordionToggle(event) {
        event?.stopPropagation?.();
        const key = event.currentTarget?.dataset?.section;
        if (!key) {
            return;
        }
        this._openAccordions = {
            ...this._openAccordions,
            [key]: !this._openAccordions[key]
        };
    }

    handleTabChange(event) {
        if (this.isReadOnly || this._incomeCategoryLocked) {
            return;
        }
        this._activeTab = event.currentTarget.dataset.value;
    }

    handleProfessionChange(event) {
        if (this.isReadOnly) {
            return;
        }
        this._activeProfession = event.currentTarget.dataset.value;
        this.employmentData = {
            ...this.employmentData,
            professionType: this._activeProfession
        };
    }

    handleFieldChange(event) {
        const name = event.target.name;
        let value = event.target.value;

        if (name === 'employmentStartDate' && hasVal(value) && this.isFutureDate(value)) {
            this.showWarning('Employment Start Date cannot be future date.');
            value = '';
            event.target.value = '';
        }
        if (name === 'dateOfCommencement' && hasVal(value) && this.isFutureDate(value)) {
            this.showWarning('Date of Commencement cannot be future date.');
            value = '';
            event.target.value = '';
        }

        this.employmentData = { ...this.employmentData, [name]: value };
    }

    handlePreviousEmployerFieldChange(event) {
        const name = event.target.name;
        let value = event.target.value;

        if (name === 'employmentStartDate' && hasVal(value) && this.isFutureDate(value)) {
            this.showWarning('Employment Start Date cannot be future date.');
            value = '';
            event.target.value = '';
        }
        if (name === 'employmentEndDate' && hasVal(value) && this.isFutureDate(value)) {
            this.showWarning('Employment End Date cannot be future date.');
            value = '';
            event.target.value = '';
        }
        if (name === 'workEmail') {
            value = (value || '').toLowerCase();
            event.target.value = value;
        }

        this.newPreviousEmployer = { ...this.newPreviousEmployer, [name]: value };
    }

    handleWorkEmailInput(event) {
        const value = (event.target.value || '').toLowerCase();
        event.target.value = value;
        this.employmentData = { ...this.employmentData, workEmail: value };
        if (this.workEmailVerified) {
            this.applyWorkEmailVerifyState(false);
        }
    }

    handleHrPayrollEmailInput(event) {
        const value = (event.target.value || '').toLowerCase();
        event.target.value = value;
        this.employmentData = { ...this.employmentData, hrPayrollEmail: value };
    }

    handleHrPayrollPhoneNumberInput(event) {
        const value = getPhoneDigits(event.target.value).slice(0, PHONE_MAX_LENGTH);
        event.target.value = value;
        this.employmentData = { ...this.employmentData, hrPayrollPhoneNumber: value };
    }

    handlePreviousEmployerPhoneNumberInput(event) {
        const value = getPhoneDigits(event.target.value).slice(0, PHONE_MAX_LENGTH);
        event.target.value = value;
        this.newPreviousEmployer = { ...this.newPreviousEmployer, hrPayrollPhoneNumber: value };
    }

    async handleWorkEmailVerifyClick(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.workEmailVerified || this.workEmailVerifyLoading) {
            return;
        }

        const workEmail = (this.employmentData.workEmail || '').trim();
        if (!EMAIL_REGEX.test(workEmail)) {
            this.showWarning('Please enter a valid work email address.');
            return;
        }
        if (!this.applicantId) {
            this.showWarning('Applicant details are required before verifying work email.');
            return;
        }

        this._workEmailVerifyState = 'loading';
        this._lastActionFieldKey = 'email';
        await generateEmailOTP({ applicantId: this.applicantId, emailAddress: workEmail })
            .then((result) => {
                if (result?.success) {
                    invokeHandler('sendEmailOTPAPI', 'onAction', this)
                        .then(() => {
                            invokeHandler('otpVerification', 'onAction', this);
                        });
                } else {
                    this._workEmailVerifyState = 'idle';
                    this.showError('Verification Failed', result?.message || 'Failed to generate OTP.');
                }
            })
            .catch((error) => {
                this._workEmailVerifyState = 'idle';
                this.showError('Verification Failed', error);
            });
    }

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

    async handleOtpVerified() {
        this.handleDynamicComponentModalClose();
        if (!this.workEmailVerified || !this.applicantId) {
            return;
        }

        const workEmail = (this.employmentData.workEmail || '').trim();
        if (!workEmail) {
            return;
        }

        try {
            const result = await markEmploymentWorkEmailVerified({
                applicantId: this.applicantId,
                employmentId: this.employmentRecordId,
                workEmail
            });
            if (result?.success) {
                this.employmentRecordId = result.employmentId || this.employmentRecordId;
                this.applyWorkEmailVerifyState(true);
                this.captureEmploymentSnapshot();
            } else {
                this.applyWorkEmailVerifyState(false);
                this.showError('Verification Failed', result?.message || 'Failed to persist work email verification.');
            }
        } catch (error) {
            this.applyWorkEmailVerifyState(false);
            this.showError('Verification Failed', error);
        }
    }

    handleIntegrationProgressUpdate(event) {
        const d = event.detail || {};
        this.showIntegrationProgressModal = d.show !== false;
        this.integrationProgressModalStatus = d.status || 'loading';
        this.integrationProgressModalHeader = d.header || '';
        this.integrationProgressModalCurrentStageIdx = d.currentStageIndex ?? 0;
        this.integrationProgressModalStages = d.stages || [];
        this.integrationProgressModalErrorMessage = d.errorMessage || '';
        if (d.status === 'error' && this._workEmailVerifyState === 'loading') {
            this._workEmailVerifyState = 'idle';
        }
    }

    handleIntegrationProgressModalClose() {
        this.showIntegrationProgressModal = false;
    }

    handleIntegrationProgressModalDone() {
        this.showIntegrationProgressModal = false;
    }

    handleAddAccordionItem(event) {
        const section = event.currentTarget.dataset.section;
        if (section === ACC_SECTION_PREVIOUS) {
            this.editingPreviousEmployerId = null;
            this.newPreviousEmployer = this.createEmptyPreviousEmployer();
            this.showPreviousEmployerForm = true;
        }
    }

    handleCancelPreviousEmployer() {
        this.showPreviousEmployerForm = false;
        this.editingPreviousEmployerId = null;
        this.newPreviousEmployer = this.createEmptyPreviousEmployer();
    }

    handleEditPreviousEmployer(event) {
        if (this.isReadOnly) {
            return;
        }
        const id = event.currentTarget.dataset.id;
        const record = this.previousEmployers.find((r) => r.id === id);
        if (!record) {
            return;
        }
        this.editingPreviousEmployerId = id;
        this.newPreviousEmployer = {
            employerName: record.employerName || '',
            jobTitle: record.jobTitle || '',
            employmentType: record.employmentType || '',
            industrySector: record.industrySector || '',
            employmentStartDate: record.employmentStartDate || '',
            employmentEndDate: record.employmentEndDate || '',
            workEmail: (record.workEmail || '').toLowerCase(),
            hrPayrollPhoneNumber: record.hrPayrollPhoneNumber || ''
        };
        this.showPreviousEmployerForm = true;
    }

    handleSavePreviousEmployer() {
        if (!this.newPreviousEmployer.employerName?.trim()) {
            this.showWarning('Please enter Employer Name.');
            return;
        }
        if (!this.newPreviousEmployer.employmentEndDate) {
            this.showWarning('Please enter Employment End Date for previous employment.');
            return;
        }
        if (hasVal(this.newPreviousEmployer.workEmail)
                && !EMAIL_REGEX.test(this.newPreviousEmployer.workEmail)) {
            this.showWarning('Please enter a valid work email address for previous employment.');
            return;
        }
        if (!this.validatePhoneNumber(this.newPreviousEmployer.hrPayrollPhoneNumber)) {
            return;
        }

        const recordData = {
            ...this.newPreviousEmployer,
            employerName: this.newPreviousEmployer.employerName.trim(),
            workEmail: (this.newPreviousEmployer.workEmail || '').trim().toLowerCase(),
            hrPayrollPhoneNumber: (this.newPreviousEmployer.hrPayrollPhoneNumber || '').trim()
        };

        if (this.editingPreviousEmployerId) {
            this.previousEmployers = this.previousEmployers.map((record) => {
                if (record.id !== this.editingPreviousEmployerId) {
                    return record;
                }
                const updated = {
                    ...record,
                    ...recordData,
                    employmentId: record.employmentId || null
                };
                updated.summary = this.buildPreviousEmployerSummary(updated);
                return updated;
            });
            this.handleCancelPreviousEmployer();
            return;
        }

        const newRecord = this.mapPreviousEmployerRecord({
            ...recordData,
            employmentId: null
        });
        this.previousEmployers = [...this.previousEmployers, newRecord];
        this.handleCancelPreviousEmployer();
    }

    handleDeletePreviousEmployer(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const record = this.previousEmployers.find((item) => item.id === id);
        if (record?.employmentId && this.isSalesforceId(record.employmentId)) {
            this._deletedPreviousEmploymentIds = [...this._deletedPreviousEmploymentIds, record.employmentId];
        }
        if (this.editingPreviousEmployerId === id) {
            this.handleCancelPreviousEmployer();
        }
        this.previousEmployers = this.previousEmployers.filter((item) => item.id !== id);
    }

    createEmptyPreviousEmployer() {
        return {
            employerName: '',
            jobTitle: '',
            employmentType: '',
            industrySector: '',
            employmentStartDate: '',
            employmentEndDate: '',
            workEmail: '',
            hrPayrollPhoneNumber: ''
        };
    }

    async initializeDocumentChecklists() {
        if (!this.recordId || !this.applicantId) {
            return;
        }

        try {
            this.professionalDocuments = await this.hydrateDocumentSlots(this.professionalDocuments);
            this.nonProfessionalDocuments = await this.hydrateDocumentSlots(this.nonProfessionalDocuments);
        } catch (error) {
            this.showError('Initialization Error', error);
        }
    }

    async hydrateDocumentSlots(documents) {
        const documentTypes = documents.map((doc) => doc.docType).filter(Boolean);
        if (!documentTypes.length) {
            return documents;
        }

        let loadedRows = [];
        try {
            loadedRows = await loadEmploymentDocuments({
                applicationId: this.recordId,
                applicantId: this.applicantId,
                documentTypes
            });
        } catch (error) {
            console.warn('wheelsEmploymentDetails loadEmploymentDocuments failed', error);
            return documents;
        }

        const loadedByType = {};
        (loadedRows || []).forEach((row) => {
            if (row?.documentType) {
                loadedByType[row.documentType] = row;
            }
        });

        return documents.map((doc) => this.applyLoadedDocumentRow(doc, loadedByType[doc.docType]));
    }

    applyLoadedDocumentRow(doc, loadedRow) {
        if (!loadedRow?.contentVersionId) {
            return doc;
        }

        const fileName = loadedRow.fileName || doc.label || 'File attached';
        return {
            ...doc,
            documentChecklistId: loadedRow.documentChecklistId || doc.documentChecklistId,
            uploaded: true,
            contentVersionId: loadedRow.contentVersionId,
            contentDocumentId: loadedRow.contentDocumentId || '',
            fileName,
            files: [{
                id: loadedRow.contentVersionId,
                name: fileName,
                contentVersionId: loadedRow.contentVersionId,
                contentDocumentId: loadedRow.contentDocumentId || null,
                extension: this.extractFileExtension(fileName)
            }]
        };
    }

    _getDocumentChecklistService() {
        return this.template.querySelector('c-embed-document-checklist');
    }

    _buildDocumentChecklistContext(doc) {
        return {
            applicationId: this.recordId,
            applicantId: this.applicantId,
            applicantType: null,
            documentType: doc.docType,
            documentName: doc.label,
            documentCategory: OCCUPATION_DOCUMENT_CATEGORY
        };
    }

    // --- Document helpers ---

    getDocumentsByList(listName) {
        if (listName === DOCUMENT_LIST_PROFESSIONAL) {
            return this.professionalDocuments;
        }
        if (listName === DOCUMENT_LIST_NON_PROFESSIONAL) {
            return this.nonProfessionalDocuments;
        }
        return [];
    }

    setDocumentsByList(listName, documents) {
        if (listName === DOCUMENT_LIST_PROFESSIONAL) {
            this.professionalDocuments = documents;
            return;
        }
        if (listName === DOCUMENT_LIST_NON_PROFESSIONAL) {
            this.nonProfessionalDocuments = documents;
        }
    }

    findDocument(listName, key) {
        return this.getDocumentsByList(listName).find((doc) => doc.key === key);
    }

    updateDocumentSlot(listName, slotKey, nextDoc) {
        const updated = this.getDocumentsByList(listName).map((item) => (
            item.key === slotKey ? nextDoc : item
        ));
        this.setDocumentsByList(listName, updated);
    }

    getDocumentFilesView(doc) {
        if (doc?.files?.length) {
            return doc.files;
        }
        if (doc?.contentVersionId || doc?.contentDocumentId) {
            const fileName = doc.fileName || doc.label || 'File attached';
            return [{
                id: doc.contentVersionId || doc.contentDocumentId || `${doc.key}-0`,
                name: fileName,
                contentVersionId: doc.contentVersionId || null,
                contentDocumentId: doc.contentDocumentId || null,
                extension: this.extractFileExtension(fileName)
            }];
        }
        return [];
    }

    buildDocumentCardView(doc, listName) {
        const filesView = this.getDocumentFilesView(doc);
        const readonly = this.isDocumentUploadReadOnly || this.isDocumentsDisabled;
        return {
            ...doc,
            listName,
            filesView,
            filesEmpty: filesView.length === 0,
            filesSingle: filesView.length === 1,
            filesMulti: filesView.length > 1,
            singleFile: filesView[0] || null,
            filesCountLabel: `${filesView.length} files attached`,
            filesChevron: doc.expanded ? 'utility:chevronup' : 'utility:chevrondown',
            showUploadBtn: filesView.length === 0 && !readonly,
            showEmptyPlaceholder: filesView.length === 0 && readonly,
            canDelete: !readonly
        };
    }

    extractFileExtension(fileName) {
        if (!fileName || typeof fileName !== 'string') {
            return null;
        }
        const parts = fileName.split('.');
        return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : null;
    }

    // --- Document upload handlers ---

    handleChunkyUpload(event) {
        if (this.isDocumentsDisabled || !this.isFieldEditable) {
            return;
        }
        const listName = event.currentTarget.dataset.list;
        const slotKey = event.currentTarget.dataset.key;
        const doc = this.findDocument(listName, slotKey);
        if (!doc) {
            return;
        }
        this._openAdvancedUpload(doc, listName, slotKey);
    }

    async _openAdvancedUpload(doc, listName, slotKey) {
        const svc = this._getDocumentChecklistService();
        if (!svc) {
            this.showError(
                'Upload unavailable',
                'The document upload service did not load. Please refresh the page and try again.'
            );
            return;
        }

        try {
            const result = await svc.getOrCreateChecklist(this._buildDocumentChecklistContext(doc));
            if (!result?.checklistId) {
                this.showError('Upload Error', 'Could not prepare the document checklist. Please retry.');
                return;
            }

            this.activeUploadChecklistId = result.checklistId;
            this.activeMaxFiles = result.maxFilesAllowed ?? 5;
            this.activeAllowedTypes = result.allowedFileTypes || '.pdf,.jpg,.jpeg,.png';
            this.activeUploadDocType = doc.docType;
            this.activeUploadDocKey = slotKey;
            this.activeUploadListName = listName;
            this.showMagicUpload = true;
        } catch (error) {
            this.showError('Upload Error', error);
        }
    }

    handleMagicUploadClose() {
        this.showMagicUpload = false;
    }

    stopPropagationDv(event) {
        event.stopPropagation();
    }

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

    async handleMagicUploadComplete(event) {
        const files = (event.detail && event.detail.files) || [];
        if (!files.length) {
            this.showMagicUpload = false;
            return;
        }

        const listName = this.activeUploadListName;
        const slotKey = this.activeUploadDocKey;
        const doc = this.findDocument(listName, slotKey);
        if (!doc) {
            this.showMagicUpload = false;
            return;
        }

        const mapped = files.map((file, index) => ({
            id: file.contentVersionId || `upl-${index}`,
            name: file.fileName || file.name || 'File attached',
            contentVersionId: file.contentVersionId || null,
            contentDocumentId: file.contentDocumentId || null,
            extension: this.extractFileExtension(file.fileName || file.name || '')
        }));
        const first = files[0];
        if (!first.contentVersionId) {
            this.showError('Upload Failed', 'Uploaded file reference is missing.');
            this.showMagicUpload = false;
            return;
        }

        try {
            const linkResult = await linkEmploymentDocument({
                docChecklistId: this.activeUploadChecklistId,
                documentType: doc.docType,
                contentVersionId: first.contentVersionId,
                applicationId: this.recordId,
                applicantId: this.applicantId
            });

            const resolvedFileName = linkResult?.fileName || first.fileName || first.name || doc.label;
            const mappedWithIds = mapped.map((file, index) => ({
                ...file,
                contentDocumentId: index === 0
                    ? (linkResult?.contentDocumentId || file.contentDocumentId || null)
                    : file.contentDocumentId
            }));

            const updatedDocuments = this.getDocumentsByList(listName).map((item) => {
                if (item.key !== slotKey) {
                    return item;
                }
                return {
                    ...item,
                    uploaded: true,
                    files: mappedWithIds,
                    fileName: resolvedFileName,
                    contentVersionId: first.contentVersionId || '',
                    contentDocumentId: linkResult?.contentDocumentId || first.contentDocumentId || '',
                    documentChecklistId: linkResult?.documentChecklistId || this.activeUploadChecklistId
                };
            });
            this.setDocumentsByList(listName, updatedDocuments);
            this.showSuccess(`${doc.label} uploaded successfully.`);
        } catch (error) {
            this.showError('Upload Failed', error);
        } finally {
            this.showMagicUpload = false;
        }
    }

    toggleDocumentFilesExpand(event) {
        const listName = event.currentTarget.dataset.list;
        const slotKey = event.currentTarget.dataset.key;
        const updated = this.getDocumentsByList(listName).map((item) => (
            item.key === slotKey ? { ...item, expanded: !item.expanded } : item
        ));
        this.setDocumentsByList(listName, updated);
    }

    handleDvFilePreviewClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const dataset = event.currentTarget?.dataset || {};
        const contentVersionId = dataset.contentVersionId || null;
        if (!contentVersionId) {
            this.showWarning('No file to preview.');
            return;
        }
        this.previewContentVersionId = contentVersionId;
        this.previewFileName = dataset.fileName || '';
        this.previewFileExtension = dataset.fileExtension
            || this.extractFileExtension(dataset.fileName || '')
            || '';
        this.showFilePreviewer = true;
    }

    handleDvFilePreviewClose() {
        this.showFilePreviewer = false;
        this.previewContentVersionId = null;
        this.previewFileName = '';
        this.previewFileExtension = '';
    }

    handleDocumentFileDelete(event) {
        event?.preventDefault?.();
        event?.stopPropagation?.();
        if (this.isDocumentsDisabled || !this.isFieldEditable) {
            return;
        }
        const listName = event.currentTarget.dataset.list;
        const slotKey = event.currentTarget.dataset.key;
        const fileId = event.currentTarget.dataset.id;
        const doc = this.findDocument(listName, slotKey);
        if (!doc) {
            return;
        }

        const remaining = this.getDocumentFilesView(doc).filter((file) => file.id !== fileId);
        if (remaining.length) {
            this.updateDocumentSlot(listName, slotKey, {
                ...doc,
                files: remaining,
                fileName: remaining[0]?.name || '',
                contentVersionId: remaining[0]?.contentVersionId || '',
                contentDocumentId: remaining[0]?.contentDocumentId || ''
            });
            return;
        }
        this.handleDocumentRemove(listName, slotKey);
    }

    handleDocumentRemove(listName, slotKey) {
        const doc = this.findDocument(listName, slotKey);
        if (!doc) {
            return;
        }
        const checklistId = doc.documentChecklistId;
        this.updateDocumentSlot(listName, slotKey, {
            ...doc,
            uploaded: false,
            files: [],
            fileName: '',
            contentDocumentId: '',
            contentVersionId: '',
            expanded: false
        });
        if (checklistId) {
            deactivateDocument({ documentChecklistId: checklistId }).catch(() => {});
        }
        this.showSuccess(`${doc.label} removed.`);
    }

    // --- Save and navigation ---

    async handleSaveDetails() {
        if (this.isReadOnly || this.isSaveDisabled) {
            return;
        }
        if (!this.applicantId) {
            this.showWarning('Applicant is required to save employment details.');
            return;
        }
        if (!this.validateSaveFields()) {
            return;
        }
        if (!this.hasEmploymentChanges()) {
            this._saveDetailsSucceeded = true;
            this.showSuccess('Employment details are up to date.');
            return;
        }

        this.isPageLoading = true;
        try {
            const result = await saveEmploymentDetails({
                applicantId: this.applicantId,
                employmentJson: JSON.stringify(this.buildFullSavePayload())
            });

            if (result?.success) {
                this.applySaveResult(result);
                this._saveDetailsSucceeded = true;
                this.showSuccess(result.message || 'Employment details saved successfully.');
            } else {
                this._saveDetailsSucceeded = false;
                this.showError('Save Failed', result?.message || 'Failed to save employment details.');
            }
        } catch (error) {
            this._saveDetailsSucceeded = false;
            this.showError('Save Failed', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    validateSaveFields() {
        if (hasVal(this.employmentData.workEmail) && !EMAIL_REGEX.test(this.employmentData.workEmail)) {
            this.showWarning('Please enter a valid work email address.');
            return false;
        }
        if (this.isSalaried && hasVal(this.employmentData.hrPayrollEmail)
                && !EMAIL_REGEX.test(this.employmentData.hrPayrollEmail)) {
            this.showWarning('Please enter a valid HR / payroll work email address.');
            return false;
        }
        if (this.isSalaried && !this.validatePhoneNumber(this.employmentData.hrPayrollPhoneNumber)) {
            return false;
        }
        if (!this.validateEmploymentStartDate()) {
            return false;
        }
        if (this.isSelfEmployedNonProfessional && this.isFutureDate(this.employmentData.dateOfCommencement)) {
            this.showWarning('Date of Commencement cannot be ahead of today.');
            return false;
        }
        if (this.showPreviousEmploymentSection && !this.validatePreviousEmployers()) {
            return false;
        }
        if (this.isSalaried) {
            return this.validateFields();
        }
        if (this.isSelfEmployedProfessional || this.isSelfEmployedNonProfessional) {
            return this.validateFields();
        }
        return true;
    }

    validatePreviousEmployers() {
        for (const record of this.previousEmployers) {
            if (!record.employmentEndDate) {
                this.showWarning('Each previous employment record must have an Employment End Date.');
                return false;
            }
            if (hasVal(record.employmentStartDate) && this.isFutureDate(record.employmentStartDate)) {
                this.showWarning('Previous employment start date cannot be future date.');
                return false;
            }
            if (hasVal(record.employmentEndDate) && this.isFutureDate(record.employmentEndDate)) {
                this.showWarning('Previous employment end date cannot be future date.');
                return false;
            }
            if (hasVal(record.workEmail) && !EMAIL_REGEX.test(record.workEmail)) {
                this.showWarning('Please enter a valid work email address for previous employment.');
                return false;
            }
            if (!this.validatePhoneNumber(record.hrPayrollPhoneNumber)) {
                return false;
            }
        }
        return true;
    }

    async handleNextButton() {
        // #region agent log
        debugOccupationLog('wheelsEmploymentDetails.js:handleNextButton', 'next clicked', {
            applicantId: this.applicantId,
            tab: this.tab,
            stagePhrase: this.stagePhrase,
            isStagePast: this.isStagePast,
            isReadOnlyScreen: this.isReadOnlyScreen,
            isNextDisabled: this.isNextDisabled,
            saveDetailsSucceeded: this._saveDetailsSucceeded,
            hasEmploymentChanges: this.hasEmploymentChanges()
        }, 'A');
        // #endregion
        if (this.isApplicationWithdrawn || this.isStagePast === true || this.isStagePast === 'true') {
            return;
        }

        if (this.isReadOnlyScreen) {
            await this.markEmploymentStepAndNavigate();
            return;
        }

        if (this.isNextDisabled) {
            return;
        }

        this.isPageLoading = true;
        try {
            await this.markEmploymentStepAndNavigate();
        } catch (error) {
            this.showError('Navigation Failed', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async markEmploymentStepAndNavigate() {
        if (!this.applicantId) {
            this.showWarning('Applicant is required to continue.');
            return;
        }

        try {
            const result = await markEmploymentStepComplete({ applicantId: this.applicantId });
            // #region agent log
            debugOccupationLog('wheelsEmploymentDetails.js:markEmploymentStepAndNavigate', 'markEmploymentStepComplete result', {
                success: result?.success,
                message: result?.message
            }, 'B');
            // #endregion
            if (!result?.success) {
                this.showError('Stage Update Failed', result?.message || 'Failed to update applicant loan stage.');
                return;
            }
            this.requestNextStage();
        } catch (error) {
            this.showError('Stage Update Failed', error);
        }
    }

    validateFields() {
        if (this.isSalaried) {
            if (!this.employmentData.employerName?.trim()) {
                this.showWarning('Please enter Employer Name.');
                return false;
            }
            if (!this.employmentData.employmentType) {
                this.showWarning('Please select Employment Type.');
                return false;
            }
            if (!hasVal(this.employmentData.monthlyGrossSalary)) {
                this.showWarning('Please enter Monthly Gross Salary.');
                return false;
            }
            if (!this.validateEmploymentStartDate()) {
                return false;
            }
            return true;
        }
        if (this.isSelfEmployedProfessional) {
            if (!hasVal(this._activeProfession)) {
                this.showWarning('Please select a Profession Type.');
                return false;
            }
            if (!this.employmentData.practiceFirmName?.trim()) {
                this.showWarning('Please enter Practice / Firm Name.');
                return false;
            }
            if (!hasVal(this.employmentData.annualProfessionalIncome)) {
                this.showWarning('Please enter Annual Professional Income.');
                return false;
            }
            return true;
        }
        if (this.isSelfEmployedNonProfessional) {
            if (!this.employmentData.businessFirmName?.trim()) {
                this.showWarning('Please enter Business / Firm Name.');
                return false;
            }
            if (!hasVal(this.employmentData.annualTurnover)) {
                this.showWarning('Please enter Annual Turnover.');
                return false;
            }
            return true;
        }
        return true;
    }

    formatYearRange(startDate, endDate) {
        const start = startDate ? startDate.substring(0, 4) : '';
        const end = endDate ? endDate.substring(0, 4) : '';
        if (start && end) {
            return `${start} - ${end}`;
        }
        return start || end || '';
    }

    getTodayDateString() {
        const today = new Date();
        const year = today.getFullYear();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const day = String(today.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    isFutureDate(dateStr) {
        if (!hasVal(dateStr)) {
            return false;
        }
        return dateStr > this.getTodayDateString();
    }

    // --- Validation helpers ---

    validateEmploymentStartDate() {
        if (this.isFutureDate(this.employmentData.employmentStartDate)) {
            this.showWarning('Employment Start Date cannot be ahead of today.');
            return false;
        }
        return true;
    }

    validatePhoneNumber(phoneNumber) {
        const digits = getPhoneDigits(phoneNumber);
        if (!hasVal(digits)) {
            return true;
        }
        if (digits.length !== PHONE_MAX_LENGTH) {
            this.showWarning('Phone number must be exactly 10 digits.');
            return false;
        }
        if (!MOBILE_REGEX.test(digits)) {
            this.showWarning('Please enter a valid 10-digit mobile number starting with 6, 7, 8, or 9.');
            return false;
        }
        return true;
    }

    requestNextStage() {
        const currentViewId = this.currentViewId;
        // #region agent log
        debugOccupationLog('wheelsEmploymentDetails.js:requestNextStage', 'dispatch losnextstage', {
            currentViewId,
            applicantId: this.applicantId,
            tab: this.tab,
            stagePhrase: this.stagePhrase,
            currentLoanStageComplete: this.tab || STAGE_EMPLOYMENT
        }, 'C');
        // #endregion
        if (!currentViewId) {
            this.showError('Navigation Error', 'Current view ID is missing. Please refresh the page.');
            return;
        }
        window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
            detail: {
                currentViewId,
                id: currentViewId,
                applicantId: this.applicantId,
                currentLoanStageComplete: this.tab || STAGE_EMPLOYMENT,
                currentStagePhrase: this.stagePhrase || ''
            },
            bubbles: true,
            composed: true
        }));
    }

    // --- Template getters ---

    get isApplicationWithdrawn() {
        return this.applicationStatus?.isWithdrawn === true;
    }

    get isReadOnlyScreen() {
        return this.isStagePast === true
            || this.isStagePast === 'true'
            || this._isApplicantStageComplete
            || this.isApplicationWithdrawn
            || this._saveDetailsSucceeded;
    }

    get isReadOnly() {
        return this.isReadOnlyScreen;
    }

    get isFieldEditable() {
        return !this.isReadOnlyScreen;
    }

    get maxEmploymentStartDate() {
        return this.getTodayDateString();
    }

    get isNextDisabled() {
        if (this.isPageLoading || this.isApplicationWithdrawn) {
            return true;
        }
        if (this.isStagePast === true || this.isStagePast === 'true') {
            return true;
        }
        if (!this.isFieldEditable) {
            return false;
        }
        return !this._saveDetailsSucceeded || this.hasEmploymentChanges();
    }

    /** NEXT shows only on the editable screen; hidden on a completed re-visit or a past/withdrawn step.
     *  Stays visible through the active fill -> save -> next flow (does not key off the post-save flag). */
    get showNextButton() {
        if (this.isApplicationWithdrawn) {
            return false;
        }
        if (this.isStagePast === true || this.isStagePast === 'true') {
            return false;
        }
        return !this._isApplicantStageComplete;
    }

    get isSaveDisabled() {
        return this.isPageLoading || this.isReadOnly;
    }

    get workEmailVerifyActionState() {
        return this._workEmailVerifyState || 'idle';
    }

    get contactInfoFieldValues() {
        return {
            email: this.employmentData.workEmail || '',
            contactNumber: ''
        };
    }

    get emailAddress() {
        return this.employmentData.workEmail || '';
    }

    get fields() {
        return [
            { key: 'email', value: this.employmentData.workEmail || '' }
        ];
    }

    setActionState(key, state) {
        if (!['idle', 'loading', 'success'].includes(state)) {
            return;
        }
        if (key === 'email') {
            this._workEmailVerifyState = state;
        }
    }

    updateFieldValue() {
        // Stub for client-layer handlers (sendEmailOTPAPI error paths).
    }

    get workEmailVerified() {
        return this.workEmailVerifyActionState === 'success';
    }

    get workEmailVerifyLoading() {
        return this.workEmailVerifyActionState === 'loading';
    }

    get workEmailVerifyDisabled() {
        return this.workEmailVerified
            || this.workEmailVerifyLoading
            || !EMAIL_REGEX.test(this.employmentData.workEmail || '');
    }

    get isWorkEmailFormatInvalid() {
        return hasVal(this.employmentData.workEmail) && !EMAIL_REGEX.test(this.employmentData.workEmail);
    }

    get workEmailValidationError() {
        return this.isWorkEmailFormatInvalid ? 'Enter a valid email address' : '';
    }

    get isHrPayrollPhoneNumberFormatInvalid() {
        return isInvalidPhoneNumber(this.employmentData.hrPayrollPhoneNumber);
    }

    get hrPayrollPhoneNumberValidationError() {
        return getPhoneNumberFormatError(this.employmentData.hrPayrollPhoneNumber);
    }

    get isHrPayrollEmailFormatInvalid() {
        return hasVal(this.employmentData.hrPayrollEmail)
            && !EMAIL_REGEX.test(this.employmentData.hrPayrollEmail);
    }

    get hrPayrollEmailValidationError() {
        return this.isHrPayrollEmailFormatInvalid ? 'Enter a valid email address' : '';
    }

    get isPreviousEmployerPhoneNumberFormatInvalid() {
        return isInvalidPhoneNumber(this.newPreviousEmployer.hrPayrollPhoneNumber);
    }

    get previousEmployerPhoneNumberValidationError() {
        return getPhoneNumberFormatError(this.newPreviousEmployer.hrPayrollPhoneNumber);
    }

    get workEmailVerifyLabel() {
        if (this.workEmailVerified) {
            return 'Verified';
        }
        if (this.workEmailVerifyLoading) {
            return '...';
        }
        return 'Send OTP';
    }

    get workEmailVerifyShowSendIcon() {
        return !this.workEmailVerified && !this.workEmailVerifyLoading;
    }

    get workEmailVerifyActionBtnClass() {
        const base = 'form-action-btn form-action-btn--send-otp';
        return this.workEmailVerified
            ? `${base} form-action-btn--verified`
            : base;
    }

    get workEmailVerifyInfoActionLabelClass() {
        return this.workEmailVerified
            ? 'form-info-action-label form-info-action-label--verified'
            : 'form-info-action-label';
    }

    get isDocumentsDisabled() {
        return this.isReadOnlyScreen;
    }

    get showDocumentUploadActions() {
        return !this.isDocumentsDisabled;
    }

    get isDocumentFileUploadDisabled() {
        return !this.recordId || !this.applicantId;
    }

    get showPreviousEmploymentSection() {
        return this.mapIncomeCategoryToTab(this.incomeCategory) === TAB_SALARIED;
    }

    get showProfessionalEmploymentFields() {
        return hasVal(this._activeProfession);
    }

    get professionFieldConfig() {
        if (!hasVal(this._activeProfession)) {
            return null;
        }
        return PROFESSION_FIELD_CONFIG[this._activeProfession] || PROFESSION_FIELD_CONFIG[PROFESSION_OTHER];
    }

    get registrationNumberLabel() {
        return this.professionFieldConfig?.regLabel || 'Registration Number';
    }

    get registrationNumberPlaceholder() {
        return this.professionFieldConfig?.regPlaceholder || 'Enter registration number';
    }

    get professionalBodyLabel() {
        return this.professionFieldConfig?.bodyLabel || 'Professional Body';
    }

    get activeRegistrationFieldName() {
        return this.professionFieldConfig?.regField || 'registrationLicenceNo';
    }

    get activeRegistrationFieldValue() {
        return this.employmentData[this.activeRegistrationFieldName] || '';
    }

    get activeBodyFieldName() {
        return this.professionFieldConfig?.bodyField || 'professionalBody';
    }

    get activeBodyFieldValue() {
        return this.employmentData[this.activeBodyFieldName] || '';
    }

    get activeBodyOptions() {
        const optionKey = this.professionFieldConfig?.bodyOptions;
        if (optionKey === 'medicalCouncil') {
            return MEDICAL_COUNCIL_OPTIONS;
        }
        if (optionKey === 'ca') {
            return CA_BODY_OPTIONS;
        }
        if (optionKey === 'barCouncil') {
            return BAR_COUNCIL_OPTIONS;
        }
        if (optionKey === 'architect') {
            return ARCHITECT_BODY_OPTIONS;
        }
        return PROFESSIONAL_BODY_OPTIONS;
    }

    get previewSessionId() {
        return this._sessionId;
    }

    get previewVfRoot() {
        return this._vfRoot;
    }

    get chunkyUploadIconUrl() {
        return `${SPECIAL_ICONS}/special_icons/upload-file-icon.svg`;
    }

    get professionalDocumentCards() {
        return this.professionalDocuments.map((doc) => (
            this.buildDocumentCardView(doc, DOCUMENT_LIST_PROFESSIONAL)
        ));
    }

    get nonProfessionalDocumentCards() {
        return this.nonProfessionalDocuments.map((doc) => (
            this.buildDocumentCardView(doc, DOCUMENT_LIST_NON_PROFESSIONAL)
        ));
    }

    get isDocumentUploadReadOnly() {
        return this.isReadOnly || !this.isFieldEditable;
    }

    get showSupportingDocumentsSection() {
        if (!hasVal(this.incomeCategory)) {
            return this.isSelfEmployedProfessional || this.isSelfEmployedNonProfessional;
        }
        const incomeTab = this.mapIncomeCategoryToTab(this.incomeCategory);
        return incomeTab === TAB_SELF_EMP_PROFESSIONAL
            || incomeTab === TAB_SELF_EMP_NON_PROF;
    }

    get activeDocumentCards() {
        if (this.isSelfEmployedNonProfessional) {
            return this.nonProfessionalDocumentCards;
        }
        if (this.isSelfEmployedProfessional && this.showProfessionalEmploymentFields) {
            return this.professionalDocumentCards;
        }
        return [];
    }

    get hasActiveDocumentCards() {
        return this.activeDocumentCards.length > 0;
    }

    get showSupportingDocumentsIntro() {
        return this.isSelfEmployedProfessional && !this.showProfessionalEmploymentFields;
    }

    get supportingDocumentsSubtitle() {
        if (this.isSelfEmployedNonProfessional) {
            return 'Upload business registration, GST returns, and financial documents';
        }
        return 'Upload registration, licence, and ITR documents for verification';
    }

    get supportingDocumentsCardClass() {
        return `form-card${this.isSupportingDocumentsOpen ? '' : ' form-card--collapsed'}`;
    }

    get isSupportingDocumentsOpen() {
        return !!this._openAccordions[ACC_SECTION_SUPPORTING_DOCUMENTS];
    }

    get supportingDocumentsChevronIcon() {
        return this.isSupportingDocumentsOpen ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get salariedEmploymentCardClass() {
        return `form-card${this.isSalariedEmploymentOpen ? '' : ' form-card--collapsed'}`;
    }

    get isSalariedEmploymentOpen() {
        return !!this._openAccordions[ACC_SECTION_SALARIED];
    }

    get salariedEmploymentChevronIcon() {
        return this.isSalariedEmploymentOpen ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get hrPayrollContactCardClass() {
        return `form-card${this.isHrPayrollContactOpen ? '' : ' form-card--collapsed'}`;
    }

    get isHrPayrollContactOpen() {
        return !!this._openAccordions[ACC_SECTION_HR_PAYROLL];
    }

    get hrPayrollContactChevronIcon() {
        return this.isHrPayrollContactOpen ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get selfEmpProfessionalCardClass() {
        return `form-card${this.isSelfEmpProfessionalOpen ? '' : ' form-card--collapsed'}`;
    }

    get isSelfEmpProfessionalOpen() {
        return !!this._openAccordions[ACC_SECTION_SELF_EMP_PROFESSIONAL];
    }

    get selfEmpProfessionalChevronIcon() {
        return this.isSelfEmpProfessionalOpen ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get selfEmpNonProfCardClass() {
        return `form-card${this.isSelfEmpNonProfOpen ? '' : ' form-card--collapsed'}`;
    }

    get isSelfEmpNonProfOpen() {
        return !!this._openAccordions[ACC_SECTION_SELF_EMP_NON_PROFESSIONAL];
    }

    get selfEmpNonProfChevronIcon() {
        return this.isSelfEmpNonProfOpen ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get previousEmploymentCardClass() {
        return `form-card${this.isPreviousEmploymentOpen ? '' : ' form-card--collapsed'}`;
    }

    get restrictTabsByIncomeCategory() {
        return this._incomeCategoryLocked && hasVal(this.incomeCategory);
    }

    get tabBarClass() {
        if (!this.restrictTabsByIncomeCategory) {
            return 'form-tab-bar';
        }
        return 'form-tab-bar form-tab-bar--restricted';
    }

    get isSalariedTabDisabled() {
        if (this.isReadOnly) {
            return true;
        }
        if (!this.restrictTabsByIncomeCategory) {
            return false;
        }
        return this._activeTab !== TAB_SALARIED;
    }

    get isSelfEmpProfTabDisabled() {
        if (this.isReadOnly) {
            return true;
        }
        if (!this.restrictTabsByIncomeCategory) {
            return false;
        }
        return this._activeTab !== TAB_SELF_EMP_PROFESSIONAL;
    }

    get isSelfEmpNonProfTabDisabled() {
        if (this.isReadOnly) {
            return true;
        }
        if (!this.restrictTabsByIncomeCategory) {
            return false;
        }
        return this._activeTab !== TAB_SELF_EMP_NON_PROF;
    }

    get isSalaried() {
        return this._activeTab === TAB_SALARIED;
    }

    get isSelfEmployedProfessional() {
        return this._activeTab === TAB_SELF_EMP_PROFESSIONAL;
    }

    get isSelfEmployedNonProfessional() {
        return this._activeTab === TAB_SELF_EMP_NON_PROF;
    }

    get salariedTabClass() {
        const classes = ['form-tab-btn'];
        if (this._activeTab === TAB_SALARIED) {
            classes.push('form-tab-btn--active');
        }
        if (this.restrictTabsByIncomeCategory && this._activeTab !== TAB_SALARIED) {
            classes.push('form-tab-btn--restricted-off');
        }
        return classes.join(' ');
    }

    get selfEmpProfTabClass() {
        const classes = ['form-tab-btn'];
        if (this._activeTab === TAB_SELF_EMP_PROFESSIONAL) {
            classes.push('form-tab-btn--active');
        }
        if (this.restrictTabsByIncomeCategory && this._activeTab !== TAB_SELF_EMP_PROFESSIONAL) {
            classes.push('form-tab-btn--restricted-off');
        }
        return classes.join(' ');
    }

    get selfEmpNonProfTabClass() {
        const classes = ['form-tab-btn'];
        if (this._activeTab === TAB_SELF_EMP_NON_PROF) {
            classes.push('form-tab-btn--active');
        }
        if (this.restrictTabsByIncomeCategory && this._activeTab !== TAB_SELF_EMP_NON_PROF) {
            classes.push('form-tab-btn--restricted-off');
        }
        return classes.join(' ');
    }

    get professionTypes() {
        return PROFESSION_TYPES.map((p) => ({
            ...p,
            cssClass: `form-profession-card${this._activeProfession === p.value ? ' form-profession-card--active' : ''}`
        }));
    }

    get hasPreviousEmployers() {
        return this.previousEmployers.length > 0;
    }

    get showPreviousEmploymentIntro() {
        return !this.hasPreviousEmployers;
    }

    get isEditingPreviousEmployer() {
        return !!this.editingPreviousEmployerId;
    }

    get previousEmployerPanelTitle() {
        return this.isEditingPreviousEmployer ? 'Edit Employer Record' : 'New Employer Record';
    }

    get previousEmployerSaveLabel() {
        return this.isEditingPreviousEmployer ? 'Update Employer' : 'Add Employer';
    }

    get previousEmployerAddLinkClass() {
        return `form-add-link${this.hasPreviousEmployers ? ' form-add-link--spaced' : ''}`;
    }

    get previousEmployerRecordCardClass() {
        return `form-record-card${this.isFieldEditable ? ' form-record-card--clickable' : ''}`;
    }

    get isPreviousEmploymentOpen() {
        return !!this._openAccordions[ACC_SECTION_PREVIOUS];
    }

    get previousEmploymentChevronIcon() {
        return this.isPreviousEmploymentOpen ? 'utility:chevronup' : 'utility:chevrondown';
    }

    // --- Toast helpers ---

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success' }));
    }

    showWarning(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message, variant: 'warning' }));
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
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error', mode: 'sticky' }));
    }
}