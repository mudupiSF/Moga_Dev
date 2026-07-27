/**
 * repaymentMandate — Repayment Mandate stage for loan applications.
 * Sections: Lifecycle, Initialization helpers, Field handlers, ACH upload,
 * Next/Save, Mandate integrations, UI getters, Utilities.
 */
import { LightningElement, api, track } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const STAGE_REPAYMENT_MANDATE = 'Repayment Mandate';
import checkApiExecutionStatus from '@salesforce/apex/RepaymentMandateController.checkApiExecutionStatus';
import checkRetryCount from '@salesforce/apex/RepaymentMandateController.checkRetryCount';
import getBankIdByBankName from '@salesforce/apex/RepaymentMandateController.getBankIdByBankName';
import saveRepaymentDetailsApex from '@salesforce/apex/RepaymentMandateController.saveRepaymentDetails';
import markRepaymentStageComplete from '@salesforce/apex/RepaymentMandateController.markRepaymentStageComplete';
import initOrGetDocumentWithApplicantId from '@salesforce/apex/RepaymentMandateController.initOrGetDocumentWithApplicantId';
import getDocumentMetadataForOther from '@salesforce/apex/RepaymentMandateController.getDocumentMetadataForOther';
import getETBResponse from '@salesforce/apex/RepaymentMandateController.getETBResponse';
import enachStatusHistory from '@salesforce/apex/RepaymentMandateController.enachStatusHistory';
import enachJournyStatusHistory from '@salesforce/apex/RepaymentMandateController.enachJournyStatusHistory';
import initializeRepaymentMandate from '@salesforce/apex/RepaymentMandateController.initializeRepaymentMandate';
import linkContentDocument from '@salesforce/apex/RepaymentMandateController.linkContentDocument';
import getFileType from '@salesforce/apex/RepaymentMandateController.getFileType';
import deleteContentDocument from '@salesforce/apex/RepaymentMandateController.deleteContentDocument';
import ACH_MANDATE_FORM_RESOURCE from '@salesforce/resourceUrl/datamask__ApexClass';

/** Field API names — plain strings avoid @salesforce/schema when metadata is not in org */
const repaymentField = (apiName) => ({ fieldApiName: apiName });

const Create_Mandate_Id = repaymentField('CreateMandateId__c');
const Create_Mandate_Initiated_Date = repaymentField('CreateMandateInitiatedDate__c');
const createMandateTriggerCount = repaymentField('createMandateTriggerCount__c');
const REPAYMENT_DETAILS_ID = repaymentField('Id');
const URL_FIELD = repaymentField('URL__c');
const RECORD_TYPE_ID = repaymentField('RecordTypeId');
const E_NACH_SESSION = repaymentField('E_Nach_Session__c');
const DEAL_NUMBER = repaymentField('Deal_Number__c');
const MESSAGE = repaymentField('Message__c');
const ENACH_BUTTON_CLICK_TIME_FIELD = repaymentField('Initiate_E_NACH_Btn_Click_Date_And_Time__c');
const E_NACH_API_STATUS = repaymentField('E_NACH_API_Status__c');
const REPAYMENT_METHOD = repaymentField('Repayment_Method__c');
const BRANCH_NAME = repaymentField('Branch_Name__c');
const BRANCH_CITY = repaymentField('Bank_Branch_City__c');
const REPAYMENT_TO_BE_DONE_BY = repaymentField('Repayment_to_be_done_by__c');
const SI_STATUS = repaymentField('SI_Status__c');
const UPI_ID = repaymentField('UPI_Id__c');
const UPI_VPA_CHECK = repaymentField('UPI_Is_VPA_Valid__c');
const IFSC_CODE = repaymentField('IFSC_Code__c');
const ACCOUNT_NUMBER = repaymentField('Account_Number__c');
const ESIGN_TYPE = repaymentField('eSIGNType__c');
const BANK_MASTER = repaymentField('Bank_Master__c');
const INITIATION_METHOD = repaymentField('Initiation_Method__c');
const UPI_MANDATE_STATUS = repaymentField('UPI_Mandate_Status__c');
const TYPE_OF_ACCOUNT = repaymentField('Type_Of_Account__c');
const ALL_MANDATE_DETAILS_CORRECT = repaymentField('All_Mandate_Details_Correctly_Entered__c');
const REMARKS = repaymentField('Remarks__c');

const REPAYMENT_OPS_VIEW_ID = 'Wheels_Repayment_OPS';

const MANDATE_DETAILS_CORRECT_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];

const RETRIGGER_TIME = 600;
const RETRIGGER_STATUS_CHECK_FREQUENCY_TIME = 30;
const RETRIGGER_SI_TIME = 600;
const SMS_ATTEMPTS = 'SI';
const SOMETHING_WENT_WRONG = 'Something went wrong. Please try again.';
const USE_INTEGRATION_STUBS = true;


const AUTO_PAY_MULTIPLIER = 1.5;
const TIMER_INTERVAL = 1000;
const SMS_TIMER_DURATION = 60;
const TIMER_FORMAT = '00:00';

/** Fallbacks when applicant / mandate query returns blank values. */
const DEFAULT_DEAL_NUMBER = 'AA6C00001';
const DEFAULT_CUSTOMER_CODE = '77267686';
const DEFAULT_REPAYMENT_TO_BE_DONE_BY = 'Borrower';

const REPAYMENT_TO_BE_DONE_BY_OPTIONS = [
    { label: 'Borrower', value: 'Borrower' },
    { label: 'Co-borrower', value: 'Co-borrower' },
    { label: 'Beneficiary', value: 'Beneficiary' }
];

/** Legacy stored values mapped to Repayment_Method__c picklist API names. */
const LEGACY_REPAYMENT_METHOD_MAP = {
    N: 'e-NACH',
    E: 'e-SIGN',
    I: 'SI',
    S: 'IES'
};

/** Picklist value → repaymentRecordTypeMap key for RecordTypeId on save. */
const REPAYMENT_METHOD_RECORD_TYPE_KEY = {
    'e-NACH': 'E_NACH',
    ACH: 'E_NACH',
    'e-SIGN': 'E_SIGN',
    SI: 'SI_Online',
    IES: 'IndusEasySavings',
    'UPI Autopay': 'UPI',
    Cash: 'CASH',
    N: 'E_NACH',
    E: 'E_SIGN',
    I: 'SI_Online',
    S: 'IndusEasySavings'
};

const AADHAR_ESIGN_OPTIONS = [
    { label: 'OTP', value: 'OTP', disabled: false },
    { label: 'Bio-metric', value: 'Bio-Metric', disabled: false }
];
const INITIATION_METHOD_OPTIONS = [
    { label: 'SI Online', value: 'SI Online', disabled: false }
];

const ACCOUNT_TYPE_OPTIONS = [
    { label: 'SB', value: 'Savings', disabled: false },
    { label: 'CA', value: 'Current', disabled: false },
    { label: 'CC', value: 'Cash Credit', disabled: false },
    { label: 'SB-NRE', value: 'SB-NRE', disabled: false },
    { label: 'SB - NRO', value: 'SB - NRO', disabled: false },
    { label: 'OTHERS', value: 'OTHER', disabled: false }
];

const DOC_TYPE_ACH_MANDATE = 'ACH Mandate Form';
const DOC_TYPE_BANK_STATEMENT = 'Bank Statement';
const ACCEPTED_ACH_FILE_FORMATS = ['.pdf', '.jpg', '.jpeg', '.png'];

/** Stages that re-enable Next when user returns after revoke. */
const REVOKE_RETURN_STAGES = new Set([
    'Disbursement Request Preparation',
    'Pre Disbursement Check',
    'Pre Payment Request'
]);

export default class RepaymentMandate extends NavigationMixin(LightningElement) {

    /** Application__c record Id (passed from applicationMasterPage). */
    @api recordId;
    @api currentViewId;
    @api stagePhrase;
    @api tab;
    @api applicantId;
    @api isStagePast = false;
    @api applicationStatus;
    @api fromAssetList = false;
    @api applicationLineItemId = '';
    @api assetId = '';
    @api selectedAssetId = '';

    /** Passed when loaded via listOfApplicants group flow; unused on direct stage load. */
    @api applicants;
    @api applicantCompletionOverrides;
    @api groupLabel;
    @api overrideLwc;

    @track _isApplicantStageComplete = false;

    @track isDealInfoExpanded = true;
    @track isSandbox;
    @track dealId = DEFAULT_DEAL_NUMBER;
    @track applicantDetails = {};
    @track pennyDropValidation;
    @track eNachMessage;
    @track enachSession;
    @track url;
    @track eNachStatus;
    @track diableInitiateMandate = true;
    @track accLastDigits = '1234';
    @track repaymentsId;
    @track enachStatusData = [];
    @track disableUPIID = false;
    @track _isNextDisabled = true;
    @track showTable = true;
    @track pspRefNo;
    @track payerTypeName;
    @track failureCheckCounter = 0;
    @track FAILURE_STATUS_DURATION_LIMIT = 300;
    @track showIntiateButton = false;
    @track diableValidateBankDetails = true;
    @track RetryExhausted = false;
    @track repaymentRecordTypeMap = {};
    @track siStatus;
    @track upiMandateStatus;

    timeLeft = RETRIGGER_TIME;
    timeLeftForSI = RETRIGGER_SI_TIME;
    @track timeLeftInMins = '0' + Math.trunc((this.timeLeft - 1) / 60);
    @track timeLeftInSecs = (this.timeLeft - 1) % 60;
    @track showTimer = false;
    showSmsOtptimer = false;
    timervalue = SMS_TIMER_DURATION;
    resendSmsButtonShow = false;
    @track repaymentData = {
        dealNumber: DEFAULT_DEAL_NUMBER,
        customerCode: DEFAULT_CUSTOMER_CODE,
        repaymentToBeDoneBy: DEFAULT_REPAYMENT_TO_BE_DONE_BY,
        repaymentMethod: '',
        upiId: '',
        bankName: '',
        accountNumber: '',
        ifscCode: '',
        branchName: '',
        bankBranchCity: '',
        autoPayLimitAmount: 0,
        initiationMethod: '',
        eSIGNType: '',
        AadharESignType: '',
        accountType: '',
        allMandateDetailsCorrectlyEntered: '',
        remarks: ''
    };

    mandateDetailsCorrectOptions = MANDATE_DETAILS_CORRECT_OPTIONS;
    repaymentToBeDoneByOptions = REPAYMENT_TO_BE_DONE_BY_OPTIONS;
    @track showUPISection = false;
    @track showAadharESignTypeSection = false;
    @track showInitiationMethodSection = false;
    @track repaymentMethodOptions = [];
    @track AadharESignTypeOptions = AADHAR_ESIGN_OPTIONS;
    @track AadharAccountTypeOptions = ACCOUNT_TYPE_OPTIONS;
    @track InitiationMethodOptions = INITIATION_METHOD_OPTIONS;
    @track bankMasterData = [];

    @track isETBCustomer = false;
    @track hasBankAccount = false;
    @track wantsToOpenSavingsAccount = false;
    @track isSavingsAccountCustomer = false;
    @track isETBWithBankAccount = false;
    @track showSuccessMessage = false;

    @track otpBioValue;
    @track mandateID;
    @track mandateTriggerCnt = 0;
    @track disableTriggerESign = true;
    @track disableInitiateESign = false;
    @track countdown = 0;
    @track isCountdownRunning = false;
    @track timer;
    @track applicantPhone;
    isDataUpdated = false;
    @track isCameBackFromRevoke = false;
    @track endDate; // Added by Ajay for PCTP-1414
    @track leadNumber; // Added for ACH Mandate filename
    @track achMandateDocumentId; 
    @track bankStatementDocumentId;
    @track achMandateContentDocumentId; 
    @track bankStatementContentDocumentId; 
    @track achMandateUploaded = false;
    @track bankStatementUploaded = false;
    @track achMandateFileName = '';
    @track bankStatementFileName = '';
    @track achMandateFileType = 'PDF';
    @track bankStatementFileType = 'PDF';

    acceptedAchFormats = ACCEPTED_ACH_FILE_FORMATS;
    @track openPreviewModal = false;
    @track contentDocumentId;
    @track fileType;
    @track isPageLoading = false;
    @track applicantsByType = {};
    
    activeTimers = new Set();
    stagesReachedBeforeRevoke = [];
    
    // ── Lifecycle ───────────────────────────────────────────────────────────

    /** Loads mandate data when the stage is mounted. */
    async connectedCallback() {
        console.log('repaymentMandate recordId:', this.recordId);
        console.log('repaymentMandate currentViewId:', this.currentViewId);
        console.log('repaymentMandate stagePhrase:', this.stagePhrase);
        console.log('repaymentMandate tab:', this.tab);
        console.log('repaymentMandate applicantId:', this.applicantId);
        console.log('repaymentMandate isStagePast:', this.isStagePast);
        console.log('repaymentMandate applicationStatus:', this.applicationStatus);
        console.log('repaymentMandate fromAssetList:', this.fromAssetList);
        console.log('repaymentMandate applicationLineItemId:', this.applicationLineItemId);
        console.log('repaymentMandate assetId:', this.assetId);
        console.log('repaymentMandate selectedAssetId:', this.selectedAssetId);

        try {
            this.isPageLoading = true;
            await this.initializeComponent();
        } catch (error) {
            console.error('Error in connectedCallback:', error);
            this.showToast('Error', 'Failed to initialize component');
        } finally {
            this.isPageLoading = false;
        }
    }

    /** Loads repayment record, picklists, applicant details, documents, and e-NACH history. */
    async initializeComponent() {
        try {
            const result = await initializeRepaymentMandate({
                applicationId: this.loanApplicationId,
                dealId: this.dealId,
                applicationLineItemId: this.applicationLineItemId || null
            });

            if (result.success) {
                if (result.repaymentRecord?.success) {
                    this.repaymentsId = result.repaymentRecord.recordId;
                    this.leadNumber = result.repaymentRecord.leadNumber;
                }
                
                // Process sandbox status
                this.isSandbox = result.sandboxStatus;
                
                // Process penny drop validations
                if (result.pennyDropValidations && result.pennyDropValidations.length > 0) {
                    this.pennyDropValidation = result.pennyDropValidations;
                }
                
                // Process bank master data
                if (result.bankMasterData) {
                    this.bankMasterData = result.bankMasterData;
                }

                if (result.repaymentMethodOptions) {
                    this.setRepaymentMethodOptionsFromServer(result.repaymentMethodOptions);
                }
                
                if (result.applicantDetails) {
                    this.applyApplicantDetailsFromInit(result.applicantDetails);
                    this.filterRepaymentOptions();
                } else {
                    this.applyRepaymentFieldDefaults();
                }
                this.setDropdownOptions();
                this.setDefaultValues();

                if (result.enachStatusHistory) {
                    await this.loadEnachJournyStatusHistory(result.enachStatusHistory);
                }
                if (result.repaymentInfo) {
                    await this.populateRepaymentData(result.repaymentInfo);
                }
                this.applyRepaymentFieldDefaults();
                if(this.enachStatusData.length > 0 && this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['e-SIGN', 'E'])){
                    if(this.enachStatusData[0].Registration_Status == 'Initiated'){
                        if(this.isBothFilesUploaded){
                            this.setNextEnabled(true);
                        }
                        this.disableInitiateESign = true;
                        this.diableInitiateMandate = true;
                        this.showIntiateButton = true;
                    }else{
                        this.disableInitiateESign = false;
                        this.diableValidateBankDetails = false;
                        this.showIntiateButton = false;
                    }
                }
                // Process stages reached before revoke
                if (result.stagesReached && result.stagesReached.length > 0) {
                    this.stagesReachedBeforeRevoke = result.stagesReached;
                    if (this.stagesReachedBeforeRevoke.some((stage) => REVOKE_RETURN_STAGES.has(stage))) {
                        this.isCameBackFromRevoke = true;
                        this.setNextEnabled(true);
                    }
                }

                if(result.repaymentRecordType){
                    this.repaymentRecordTypeMap = result.repaymentRecordType;
                }
                if (result.documentIds) {
                    this.achMandateDocumentId = result.documentIds.achMandateDocumentId;
                    this.bankStatementDocumentId = result.documentIds.bankStatementDocumentId;
                    this.achMandateContentDocumentId = result.documentIds.achMandateContentDocumentId;
                    this.bankStatementContentDocumentId = result.documentIds.bankStatementContentDocumentId;
                    if (this.achMandateContentDocumentId) {
                        this.achMandateUploaded = true;
                        this.achMandateFileName =
                            result.documentIds.achMandateFileName || 'ACH Mandate Form';
                        this.achMandateFileType =
                            result.documentIds.achMandateFileType || 'PDF';
                    }
                    if (this.bankStatementContentDocumentId) {
                        this.bankStatementUploaded = true;
                        this.bankStatementFileName =
                            result.documentIds.bankStatementFileName || 'Bank Statement';
                        this.bankStatementFileType =
                            result.documentIds.bankStatementFileType || 'PDF';
                    }
                    if (this.isAchUploadRequired) {
                        this.setNextEnabled(this.isBothFilesUploaded);
                    }
                }
                await this.ensureDocumentIds();
            } else {
                this.showToast('Error', 'Failed to initialize repayment mandate');
            }
        } catch (error) {
            console.error('Error in initializeComponent:', error);
            this.showToast('Error', 'Failed to initialize component');
        }
    }

    async loadEnachJournyStatusHistory(data = null) {
        const enachStatusHistoryMap = await enachStatusHistory({ applicationId: this.loanApplicationId });
        try {
            this.enachStatusData = [];
            let idx =1;
            let modeOfRegistration = '';
            let sessionId = '';
            let registrationStatus = '';
            
            let result;
            if (data) {
                result = data;
            } else {
                result = await enachJournyStatusHistory({ applicationId: this.loanApplicationId, dealId: this.dealId });
            }
            
            if (result && Array.isArray(result) && result.length > 0) {
                result.forEach((item,index) =>{
                    let reqestVal = JSON.parse(item?.Original_request__c);
                    let responseVal = JSON.parse(item?.Original_response__c);
                    let createdDateTime = item?.Created_DateTime__c;
                    let serviceName = item?.Service_Name__c;
                    let status = item?.Status__c;
                    let formattedDateTime = new Date(createdDateTime).toLocaleString();
                    if (idx > 10){
                        return;
                    }
                    if( reqestVal != null && responseVal != null){
                        if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['e-SIGN', 'E']) && serviceName == 'E-Sign Registration Journey'){
                            modeOfRegistration = 'Aadhaar e-SIGN';
                            sessionId = 'N/A';
                            registrationStatus = status != null && status == 'Success'? 'Initiated' :status;
                            this.enachStatusData.push({
                                rowIndex: idx++,
                                Date_And_Time_Of_Trigger: formattedDateTime || 'N/A',
                                Session_Id: sessionId,
                                Mode_Of_Registration: modeOfRegistration,
                                Registration_Status: registrationStatus
                            });
                        }else if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['e-NACH', 'N', 'ACH']) && serviceName == 'ENACH Registration Journey'){
                            modeOfRegistration =  'e-NACH' ;
                            sessionId = responseVal?.Session_Id || 'N/A';
                            registrationStatus = responseVal?.Resp_Message == 'DB Action Success' ?  (enachStatusHistoryMap && enachStatusHistoryMap[sessionId]) || 'In Progress' : responseVal?.Resp_Message || 'N/A';
                            this.enachStatusData.push({
                                rowIndex: idx++,
                                Date_And_Time_Of_Trigger: formattedDateTime || 'N/A',
                                Session_Id: sessionId,
                                Mode_Of_Registration: modeOfRegistration,
                                Registration_Status: registrationStatus
                            });
                        }else if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['SI', 'I']) && serviceName == 'SIStatus'){
                            modeOfRegistration = 'Standing Instruction';
                            sessionId =responseVal?.Session_Id || 'N/A';
                            registrationStatus = responseVal?.Resp_Message || 'N/A';
                            this.enachStatusData.push({
                                rowIndex: idx++,
                                Date_And_Time_Of_Trigger: formattedDateTime || 'N/A',
                                Session_Id: sessionId,
                                Mode_Of_Registration: modeOfRegistration,
                                Registration_Status: registrationStatus
                            });
                        }


                    }
                });

        } else {
            console.log('No enach journey status history data found');
        }
        } catch (error) {
            console.error('Error loading enach journy status history:', error);
        }
    }

    /** Removes polling timers when the stage is unmounted. */
    disconnectedCallback() {
        this.clearAllTimers();
        if (this.timer) {
            clearInterval(this.timer);
        }
    }

    // ── Initialization helpers (initializeComponent call order) ─────────────

    setRepaymentMethodOptionsFromServer(options) {
        this.repaymentMethodOptions = (options || []).map((option) => ({
            label: option.label,
            value: option.value,
            disabled: false
        }));
    }

    /**
     * Maps getApplicantDetails / ApplicationDetailsWrapper onto component state.
     * Deal number is Applicant__c.Deal_Number__c (text), exposed as dealNumber and dealId.
     */
    applyApplicantDetailsFromInit(details) {
        this.applicantsByType = {
            Borrower: details.borrowerApplicant || null,
            'Co-borrower': details.coBorrowerApplicant || null,
            Beneficiary: details.beneficiaryApplicant || null
        };
        if (this.hasRepaymentFieldValue(details.repaymentToBeDoneBy)) {
            this.repaymentData.repaymentToBeDoneBy = details.repaymentToBeDoneBy;
        }
        if (this.hasRepaymentFieldValue(details.customerCode)) {
            this.repaymentData.customerCode = details.customerCode;
        }
        this.repaymentData.emiAmount = (details.emiAmount ?? 0) * AUTO_PAY_MULTIPLIER;
        this.endDate = details.endDate || '';
        const dealFromApplicant =
            details.dealNumber ||
            details.dealId ||
            details.repayApplicantDetail?.Deal_Number__c;
        if (this.hasRepaymentFieldValue(dealFromApplicant)) {
            this.dealId = dealFromApplicant;
            this.repaymentData.dealNumber = dealFromApplicant;
        }
        this.applySelectedRepaymentApplicant(this.repaymentData.repaymentToBeDoneBy);
        this.applyRepaymentFieldDefaults();
    }

    applySelectedRepaymentApplicant(repaymentToBeDoneBy) {
        const type =
            repaymentToBeDoneBy ||
            this.repaymentData.repaymentToBeDoneBy ||
            DEFAULT_REPAYMENT_TO_BE_DONE_BY;
        const applicant =
            this.applicantsByType?.[type] ||
            this.applicantsByType?.Borrower ||
            null;
        if (!applicant?.Id) {
            return;
        }
        this.applicantDetails = { ...applicant };
        this.applicantId = applicant.Id;
        this.applicantPhone = applicant.Contact_number__c;
        if (this.hasRepaymentFieldValue(applicant.Customer_Code__c)) {
            this.repaymentData.customerCode = applicant.Customer_Code__c;
        }
        if (this.hasRepaymentFieldValue(applicant.Deal_Number__c)) {
            this.applyDealNumberValue(applicant.Deal_Number__c);
        }
    }

    filterRepaymentOptions() {
        if (!this.repaymentMethodOptions?.length) {
            this.setRepaymentMethodOptionsFromServer([]);
        }
    }

    /**
     * Applies default deal number, customer code, and repayment-to-be-done-by when queries return blank.
     */
    applyRepaymentFieldDefaults() {
        if (!this.hasRepaymentFieldValue(this.repaymentData.dealNumber)) {
            this.repaymentData.dealNumber = DEFAULT_DEAL_NUMBER;
        }
        if (!this.hasRepaymentFieldValue(this.dealId)) {
            this.dealId = this.repaymentData.dealNumber;
        }

        if (!this.hasRepaymentFieldValue(this.repaymentData.customerCode)) {
            this.repaymentData.customerCode = DEFAULT_CUSTOMER_CODE;
        }

        if (!this.hasRepaymentFieldValue(this.repaymentData.repaymentToBeDoneBy)) {
            this.repaymentData.repaymentToBeDoneBy = DEFAULT_REPAYMENT_TO_BE_DONE_BY;
        }

        this.applicantDetails = {
            ...this.applicantDetails,
            Deal_Number__c: this.hasRepaymentFieldValue(this.applicantDetails?.Deal_Number__c)
                ? this.applicantDetails.Deal_Number__c
                : this.repaymentData.dealNumber,
            Customer_Code__c: this.hasRepaymentFieldValue(this.applicantDetails?.Customer_Code__c)
                ? this.applicantDetails.Customer_Code__c
                : this.repaymentData.customerCode
        };
    }

    setDropdownOptions() {
        this.filterRepaymentOptions();
    }

    setDefaultValues() {
        if (this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['SI', 'I', 'IES', 'S'])) {
            const indusindBankId = this.getBankIdByName('INDUSIND BANK LTD');
            if (indusindBankId) {
                setTimeout(() => {
                    this.repaymentData = {
                        ...this.repaymentData,
                        bankName: indusindBankId
                    };
                }, 100);
            }
        }
    }

    applyDealNumberValue(dealValue) {
        if (!dealValue) {
            return;
        }
        this.dealId = dealValue;
        this.repaymentData.dealNumber = dealValue;
    }

    async populateRepaymentData(result) {
        this.repaymentData.repaymentMethod = this.normalizeRepaymentMethod(
            result.Repayment_Method__c
        );
        await this.handleRepaymentMethodChange(this.repaymentData.repaymentMethod,'');
        this.repaymentData.accountNumber = result.Account_Number__c;
        this.repaymentData.ifscCode = result.IFSC_Code__c;
        if(this.repaymentData.ifscCode){
            this.diableInitiateMandate = false;
        }
        this.repaymentData.bankName = result.Bank_Master__c;
        this.repaymentData.branchName = result.Branch_Name__c;
        this.repaymentData.bankBranchCity = result.Bank_Branch_City__c;
        
        if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['e-SIGN', 'E'])){
            this.repaymentData.AadharESignType = result.eSIGNType__c;
            this.otpBioValue = result.eSIGNType__c;
            this.repaymentData.accountType=result.Type_Of_Account__c;
        }else if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['UPI Autopay'])){
            this.repaymentData.upiId = result.UPI_Id__c;
        }else if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['SI', 'I'])){
            this.repaymentData.initiationMethod = result.Initiation_Method__c != null ? result.Initiation_Method__c : 'SI Online';
            this.showTable=false;
        }
        this.repaymentsId = result.Id;
        this.applyDealNumberValue(result.Deal_Number__c);
        if (this.hasRepaymentFieldValue(result.Repayment_to_be_done_by__c)) {
            this.repaymentData.repaymentToBeDoneBy = result.Repayment_to_be_done_by__c;
            this.applySelectedRepaymentApplicant(result.Repayment_to_be_done_by__c);
        }
        this.accLastDigits = result?.Account_Number__c ? result.Account_Number__c.slice(-3) : undefined;
        if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['IES', 'S']) && this.repaymentData.bankName!="" ){
            this.setNextEnabled(true);
        }
        if(this.repaymentData.repaymentMethod != null && this.repaymentData.accountNumber != null && this.repaymentData.ifscCode != null && this.repaymentData.bankName != null){
            this.diableValidateBankDetails = false;
        }
        this.repaymentData.allMandateDetailsCorrectlyEntered =
            result.All_Mandate_Details_Correctly_Entered__c || '';
        this.repaymentData.remarks = result.Remarks__c || '';
    }

    async ensureAchMandateDocumentId() {
        if (!this.applicantId || !this.loanApplicationId) {
            return;
        }
        if (this.achMandateDocumentId) {
            return;
        }
        this.achMandateDocumentId = await initOrGetDocumentWithApplicantId({
            applicationId: this.loanApplicationId,
            documentType: DOC_TYPE_ACH_MANDATE,
            applicantId: this.applicantId,
            applicationLineItemId: this.applicationLineItemId || null,
            assetId: this.documentAssetId
        });
    }

    async ensureBankStatementDocumentId() {
        if (!this.applicantId || !this.loanApplicationId) {
            return;
        }
        if (this.bankStatementDocumentId) {
            return;
        }
        this.bankStatementDocumentId = await initOrGetDocumentWithApplicantId({
            applicationId: this.loanApplicationId,
            documentType: DOC_TYPE_BANK_STATEMENT,
            applicantId: this.applicantId,
            applicationLineItemId: this.applicationLineItemId || null,
            assetId: this.documentAssetId
        });
    }

    async ensureDocumentIds() {
        await Promise.all([
            this.ensureAchMandateDocumentId(),
            this.ensureBankStatementDocumentId()
        ]);
    }

    // ── Field & UI handlers ─────────────────────────────────────────────────

    toggleDealInfoSection() {
        this.isDealInfoExpanded = !this.isDealInfoExpanded;
    }

    // ── ACH document upload ─────────────────────────────────────────────────

    /** Downloads the static-resource ACH mandate form when required fields are complete. */
    downloadACHMandateForm() {
        if (this.isAchDocumentsDisabled || this.disableDownloadButton) {
            return;
        }
        try {
            const fileName = `ACH_Mandate_${this.leadNumber || this.repaymentData.dealNumber || 'Form'}.png`;
            const link = document.createElement('a');
            link.href = ACH_MANDATE_FORM_RESOURCE;
            link.setAttribute('download', fileName);
            link.setAttribute('target', '_blank');
            link.rel = 'noopener noreferrer';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            this.showToast('Success', 'ACH Mandate Form downloaded successfully', 'success');
        } catch (error) {
            this.showToast('Error', error.message || 'Failed to download ACH Mandate Form');
        }
    }

    async _linkUploadedDocument(contentDocumentId, documentType) {
        await linkContentDocument({
            documentDataJson: JSON.stringify({
                documentType,
                applicationId: this.loanApplicationId,
                applicantId: this.applicantId,
                applicationLineItemId: this.applicationLineItemId || null,
                assetId: this.documentAssetId,
                contentDocumentId
            })
        });
    }

    async handleAchMandateFileUploadFinished(event) {
        if (
            this.isAchDocumentsDisabled ||
            !this.isFieldEditable ||
            this.isAchFileUploadDisabled
        ) {
            return;
        }

        const uploadedFiles = event.detail?.files || [];
        if (!uploadedFiles.length) {
            return;
        }

        const file = uploadedFiles[0];
        const contentDocumentId = file.documentId || '';

        try {
            if (!this.loanApplicationId || !this.applicantId) {
                this.showToast('Error', 'Missing application or applicant details.');
                return;
            }

            await this.ensureAchMandateDocumentId();
            await this._linkUploadedDocument(contentDocumentId, DOC_TYPE_ACH_MANDATE);

            const uploadedFileType = await getFileType({ contentDocumentId });
            this.achMandateContentDocumentId = contentDocumentId;
            this.achMandateFileName = file.name || 'ACH Mandate Form';
            this.achMandateFileType = uploadedFileType;
            this.achMandateUploaded = true;
            this.isDataUpdated = true;
            this.showToast('Success', 'ACH Mandate Form uploaded successfully', 'success');
            if (this.isAchUploadRequired) {
                this.setNextEnabled(this.isBothFilesUploaded);
            }
        } catch (error) {
            console.error('Error handling ACH Mandate Form upload:', error);
            this.showToast('Error', 'Failed to process uploaded file. Please try again.');
        }
    }

    async handleBankStatementFileUploadFinished(event) {
        if (
            this.isAchDocumentsDisabled ||
            !this.isFieldEditable ||
            this.isAchFileUploadDisabled
        ) {
            return;
        }

        const uploadedFiles = event.detail?.files || [];
        if (!uploadedFiles.length) {
            return;
        }

        const file = uploadedFiles[0];
        const contentDocumentId = file.documentId || '';

        try {
            if (!this.loanApplicationId || !this.applicantId) {
                this.showToast('Error', 'Missing application or applicant details.');
                return;
            }

            await this.ensureBankStatementDocumentId();
            await this._linkUploadedDocument(contentDocumentId, DOC_TYPE_BANK_STATEMENT);

            const uploadedFileType = await getFileType({ contentDocumentId });
            this.bankStatementContentDocumentId = contentDocumentId;
            this.bankStatementFileName = file.name || 'Bank Statement';
            this.bankStatementFileType = uploadedFileType;
            this.bankStatementUploaded = true;
            this.isDataUpdated = true;
            this.showToast('Success', 'Bank Statement uploaded successfully', 'success');
            if (this.isAchUploadRequired) {
                this.setNextEnabled(this.isBothFilesUploaded);
            }
        } catch (error) {
            console.error('Error handling Bank Statement upload:', error);
            this.showToast('Error', 'Failed to process uploaded file. Please try again.');
        }
    }

    async handleAchMandateDelete() {
        if (
            this.isAchDocumentsDisabled ||
            !this.isFieldEditable ||
            !this.achMandateUploaded ||
            !this.achMandateContentDocumentId
        ) {
            return;
        }

        try {
            await deleteContentDocument({
                contentDocumentId: this.achMandateContentDocumentId
            });
            this.achMandateUploaded = false;
            this.achMandateContentDocumentId = null;
            this.achMandateFileName = '';
            this.achMandateFileType = 'PDF';
            this.isDataUpdated = true;
            if (this.isAchUploadRequired) {
                this.setNextEnabled(this.isBothFilesUploaded);
            }
            this.showToast('Success', 'ACH Mandate Form removed', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to remove ACH Mandate Form');
        }
    }

    async handleBankStatementDelete() {
        if (
            this.isAchDocumentsDisabled ||
            !this.isFieldEditable ||
            !this.bankStatementUploaded ||
            !this.bankStatementContentDocumentId
        ) {
            return;
        }

        try {
            await deleteContentDocument({
                contentDocumentId: this.bankStatementContentDocumentId
            });
            this.bankStatementUploaded = false;
            this.bankStatementContentDocumentId = null;
            this.bankStatementFileName = '';
            this.bankStatementFileType = 'PDF';
            this.isDataUpdated = true;
            if (this.isAchUploadRequired) {
                this.setNextEnabled(this.isBothFilesUploaded);
            }
            this.showToast('Success', 'Bank Statement removed', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to remove Bank Statement');
        }
    }
    
    // Preview handlers
    handleAchMandatePreview() {
        if (!this.achMandateContentDocumentId) {
            return;
        }
        this.contentDocumentId = this.achMandateContentDocumentId;
        this.fileType = this.achMandateFileType || 'PDF';
        this.openPreviewModal = true;
    }

    handleBankStatementPreview() {
        if (!this.bankStatementContentDocumentId) {
            return;
        }
        this.contentDocumentId = this.bankStatementContentDocumentId;
        this.fileType = this.bankStatementFileType || 'PDF';
        this.openPreviewModal = true;
    }

    handleFilePreviewClose() {
        this.openPreviewModal = false;
        this.contentDocumentId = null;
        this.fileType = null;
    }
    // ── Next / Save ─────────────────────────────────────────────────────────

    /**
     * Footer Next: navigate when read-only, save when dirty, otherwise validate and advance.
     */
    async handleNextButton() {
        if (this.isApplicationWithdrawn) {
            return;
        }

        if (this.isStagePastView) {
            return;
        }

        if (this.fromAssetList) {
            if (this.isReadOnlyScreen) {
                this.dispatchEvent(new CustomEvent('detailcomplete', {
                    detail: { lineItemId: this.applicationLineItemId || null, saved: false },
                    bubbles: true,
                    composed: true
                }));
                return;
            }
            if (this.isNextDisabled || !(await this.validateFields())) {
                return;
            }
            this.isPageLoading = true;
            try {
                const saved = await this.saveRepaymentDetails();
                if (!saved) {
                    return;
                }
                const stageResult = await markRepaymentStageComplete({
                    applicationLineItemId: this.applicationLineItemId,
                    currentViewId: this.currentViewId
                });
                if (!stageResult?.isSuccess) {
                    this.showToast(
                        'Error',
                        stageResult?.message || 'Unable to complete repayment for this asset.',
                        'error'
                    );
                    return;
                }
                this.showToast('Success', 'Repayment details saved successfully', 'success');
                this.isDataUpdated = false;
                this.dispatchEvent(new CustomEvent('detailcomplete', {
                    detail: { lineItemId: this.applicationLineItemId || null, saved: true },
                    bubbles: true,
                    composed: true
                }));
            } finally {
                this.isPageLoading = false;
            }
            return;
        }

        if (this.isRepaymentOpsView) {
            if (this.isReadOnlyScreen) {
                await this.markStepAndNavigate();
                this.updateRevokeOptions();
                return;
            }

            if (!(await this.validateFields())) {
                return;
            }

            this.isPageLoading = true;
            try {
                const saved = await this.saveRepaymentDetails();
                if (!saved) {
                    return;
                }
                this.showToast('Success', 'Repayment remarks saved successfully', 'success');
                this.isDataUpdated = false;
                await this.markStepAndNavigate();
                this.updateRevokeOptions();
            } finally {
                this.isPageLoading = false;
            }
            return;
        }

        if (this.isReadOnlyScreen) {
            await this.markStepAndNavigate();
            this.updateRevokeOptions();
            return;
        }

        if (this.isNextDisabled) {
            return;
        }

        if (!this.isDataUpdated) {
            if (!(await this.validateFields())) {
                return;
            }
            await this.markStepAndNavigate();
            this.updateRevokeOptions();
            return;
        }

        if (!(await this.validateFields())) {
            return;
        }

        this.isPageLoading = true;
        try {
            const saved = await this.saveRepaymentDetails();
            if (!saved) {
                return;
            }
            this.showToast('Success', 'Repayment details saved successfully', 'success');
            this.isDataUpdated = false;
            this._isApplicantStageComplete = true;
            await this.markStepAndNavigate();
            this.updateRevokeOptions();
        } finally {
            this.isPageLoading = false;
        }
    }

    async markStepAndNavigate() {
        if (!this.applicantId) {
            this.showToast('Warning', 'Applicant is required to continue.', 'warning');
            return;
        }

        this.requestNextStage();
    }

    //Start - PCTP-3257 Rajasekar R
    async updateRevokeOptions(){
        this.dispatchEvent(new CustomEvent('updaterevokeoption',{
            bubbles: true,
            composed: true
        }));
    }
    //End - PCTP-3257 Rajasekar R
    
    async handleCaptureFile() {
        try {
            this.isPageLoading = true;
            this.uploadDocumentType = 'ACH Mandate Form';
            const recordTypes = await getDocumentMetadataForOther({ documentType: this.uploadDocumentType });
            const recordTypeId = recordTypes.recordTypeId;
            await initOrGetDocumentWithApplicantId({
                applicationId: this.loanApplicationId,
                documentType: this.uploadDocumentType,
                applicantId: this.applicantId,
                applicationLineItemId: this.applicationLineItemId || null,
                assetId: this.documentAssetId
            });
            this.showToast('Info', 'Use the upload control to attach ' + this.uploadDocumentType + '.');
        } catch (error) {
            console.error('Error capturing file:', error);
        } finally {
            this.isPageLoading = false;
        }
    }

    async handlebankStatementUpload() {
        try {
            this.isPageLoading = true;
            this.uploadDocumentType = 'Customer Bank Statement';
            await initOrGetDocumentWithApplicantId({
                applicationId: this.loanApplicationId,
                documentType: this.uploadDocumentType,
                applicantId: this.applicantId,
                applicationLineItemId: this.applicationLineItemId || null,
                assetId: this.documentAssetId
            });
            this.showToast('Info', 'Use the upload control to attach the bank statement.');
        } catch (error) {
            console.error('Error capturing file:', error);
        } finally {
            this.isPageLoading = false;
        }
    }
    handleFieldChange(event) {
        this.isDataUpdated = true;
        const name = event.target.name;
        const value = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        let previousrepaymentMethod = this.repaymentData.repaymentMethod;
        if (name === 'accountNumber') {
            const alphaNumericRegex = /^[A-Za-z0-9]+$/;
            if (!alphaNumericRegex.test(value)) {
                this.showToast('Warning', 'Account number should contain only alphanumeric characters');
                event.target.value = value.replace(/[^A-Za-z0-9]/g, '');

                return;
            }
            if(value.length >18){
                const truncatedValue = value.substring(0, 18);
                event.target.value = truncatedValue;
                this.repaymentData[name] = truncatedValue;
                
                this.showToast('Error', 'Account number must be between 9 and 18 digits');
                return;
            }
        }
        this.repaymentData[name] = value;
        
        if (name === 'repaymentMethod') {
            this.handleRepaymentMethodChange(value, previousrepaymentMethod);
        } else if (name === 'ifscCode') {
        
        }else if(name === 'AadharESignType'){
            this.otpBioValue = value;
            this.repaymentData.AadharESignType = value;
        } else if (name === 'repaymentToBeDoneBy') {
            this.applySelectedRepaymentApplicant(value);
        } else if (name === 'initiationMethod') {
            this.repaymentData.initiationMethod = value; 
            if(this.repaymentData.initiationMethod === 'SI Online'){
                this.diableInitiateMandate = false;
            }          
        }
        else if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['UPI Autopay'])){
            this.diableValidateBankDetails = false;
        }
        if (this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['IES', 'S']) && this.repaymentData.bankName !== '') {
            this.setNextEnabled(true);
        } else if (this.isAchUploadRequired) {
            this.setNextEnabled(this.isBothFilesUploaded);
        } else {
            this.setNextEnabled(false);
        }
    }
    
    async handleRepaymentMethodChange(method, previousrepaymentMethod) {
        this.isPageLoading = true;
        if (previousrepaymentMethod && previousrepaymentMethod !== method)
        {
        this.resetSectionVisibility();
        }
        
        await this.loadEnachJournyStatusHistory();
        
        const normalizedMethod = this.normalizeRepaymentMethod(method);

        if (this.isRepaymentMethod(normalizedMethod, ['IES', 'S'])) {
            this.setNextEnabled(true);
        }
        this.showTable = !this.isRepaymentMethod(normalizedMethod, ['IES', 'S']);
        
        if (this.isRepaymentMethod(normalizedMethod, ['SI', 'I', 'IES', 'S'])) {
            await this.setIndusindBank();
        }
        
        if (this.isRepaymentMethod(normalizedMethod, ['e-NACH', 'N', 'e-SIGN', 'E', 'SI', 'I', 'ACH'])) {
            if (this.isRepaymentMethod(normalizedMethod, ['e-SIGN', 'E'])) {
                this.showAadharESignTypeSection = true;
            }
            if (this.isRepaymentMethod(normalizedMethod, ['SI', 'I'])) {
                this.repaymentData.initiationMethod = 'SI Online';
                try {
                    let etbResponseList = await getETBResponse({ applicationId: this.loanApplicationId });
                    if (etbResponseList?.length > 0 && etbResponseList[0].Processed_Response__c) {
                        const processedResponse = JSON.parse(etbResponseList[0].Processed_Response__c);
                        if (processedResponse?.length > 0) {
                            const etbData = processedResponse[0];
                            if (etbData.accountId) {
                                this.repaymentData.accountNumber = etbData.accountId;
                            }
                            if (etbData.ifscCode) {
                                this.repaymentData.ifscCode = etbData.ifscCode;
                            }
                        }
                    } else if (USE_INTEGRATION_STUBS) {
                        const stub = await this.stubEtbAccountPrefill();
                        this.repaymentData.accountNumber = stub.accountId;
                        this.repaymentData.ifscCode = stub.ifscCode;
                    }
                    this.showInitiationMethodSection = true;
                } catch (error) {
                    console.error('Error getting ETB response:', error);
                    if (USE_INTEGRATION_STUBS) {
                        const stub = await this.stubEtbAccountPrefill();
                        this.repaymentData.accountNumber = stub.accountId;
                        this.repaymentData.ifscCode = stub.ifscCode;
                        this.showInitiationMethodSection = true;
                    }
                }
            }
        }
        
        if (this.isRepaymentMethod(normalizedMethod, ['UPI Autopay'])) {
            this.showUPISection = true;
        }

        if (this.isRepaymentMethod(normalizedMethod, ['e-SIGN', 'E'])) {
            this.setNextEnabled(this.isBothFilesUploaded);
        }
        
        this.repaymentData = { ...this.repaymentData };        
        this.isPageLoading = false;
    }

    setRepaymentMethodForNoBankAccount() {
        this.repaymentMethodOptions = this.repaymentMethodOptions.filter(
            (option) => !this.isRepaymentMethod(option.value, ['IES', 'S'])
        );
    }

    setRepaymentMethodForETBCustomer() {
        this.repaymentData.repaymentMethod = 'SI';
        this.repaymentMethodOptions = this.repaymentMethodOptions.filter((option) =>
            this.isRepaymentMethod(option.value, ['SI', 'I'])
        );
        
        this.isETBWithBankAccount = true;
        console.log('Setting repayment method to Standing Instruction for ETB customer');
        this.updateRepaymentData();
    }

    setRepaymentMethodForNewAccount() {
        this.repaymentData.repaymentMethod = 'IES';
        this.repaymentMethodOptions = this.repaymentMethodOptions.filter(
            (option) => !this.isRepaymentMethod(option.value, ['SI', 'I'])
        );
        console.log('Setting repayment method to Indus Easy Savings for new account');
        this.setNextEnabled(true);
        this.updateRepaymentData();
    }

    setRepaymentMethodForExistingAccount() {
        this.repaymentMethodOptions = this.repaymentMethodOptions.filter((option) =>
            this.isRepaymentMethod(option.value, [
                'e-NACH',
                'N',
                'UPI Autopay',
                'e-SIGN',
                'E',
                'ACH'
            ])
        );
    }

    updateRepaymentData() {
        this.repaymentData = { ...this.repaymentData };
        setTimeout(() => {
            this.repaymentData = { ...this.repaymentData };
        }, 100);
    }

    resetSectionVisibility() {
        this.diableValidateBankDetails = true;
        this.showIntiateButton = false;
        this.showUPISection = false;
        this.showAadharESignTypeSection = false;
        this.showInitiationMethodSection = false;
        this.showTable = false;
        this.repaymentData.bankName = '';
        this.repaymentData.accountNumber = '';
        this.repaymentData.ifscCode = '';
        this.repaymentData.branchName = '';
        this.repaymentData.bankBranchCity = '';
        this.repaymentData.initiationMethod = '';
        this.repaymentData.AadharESignType='';
        this.repaymentData.accountType='';

    }


    async setIndusindBank() {
        try {
            const indusindBankId = await getBankIdByBankName({ bankName: 'INDUSIND BANK LTD' });
            if (indusindBankId) {
                this.repaymentData.bankName = indusindBankId;
                this.repaymentData = { ...this.repaymentData };
            }
        } catch (error) {
            console.error('Error getting bank ID by name:', error);
        }
    }

    verifyIFSC(){
        this.handleIFSCChange(this.repaymentData.ifscCode);
    }
    
    async handleIFSCChange(ifscCode) {
        if (ifscCode && !/^[A-Za-z0-9]+$/.test(ifscCode)) {
            this.showToast('Error', 'IFSC Code should contain only alphanumeric characters');
            return;
        }
        if(ifscCode && ifscCode.length != 11){
            this.showToast('Error', 'Enter valid IFSC Code');
            return;
        }
        
        if (ifscCode && ifscCode.length === 11) {
            try {
                this.isPageLoading = true;
                const result = await this.doIFSCCallout();
                
                if (result && result.responseJSONasPlainText){
                    console.log('IFSC code api Check - Success', JSON.stringify(JSON.parse(result.responseJSONasPlainText)));
                    const response = JSON.parse(result.responseJSONasPlainText);
                    this.isPageLoading = false;
                    this.showToast('Success', 'IFSC Code API - Success');
                    this.updateBranchDetails(response);
                } else {
                    this.showToast('Error', 'Invalid IFSC Code, Status code - '+result?.statusCode ? result?.statusCode : '');
                    this.clearBranchDetails();
                }
                this.diableValidateBankDetails = false;
            } catch (error) {
                console.error('Error validating IFSC code:', error);
                this.showToast('Error', 'Failed to validate IFSC code');
                this.diableValidateBankDetails = false;
            } finally {
                this.isPageLoading = false;
            }
        }else{
            this.diableInitiateMandate = true;
        }
    }

    updateBranchDetails(result) {
        this.diableInitiateMandate = false;
        const details = result.localDirectoryDetails.length>0 ? result.localDirectoryDetails[0] : null;
        this.repaymentData.branchName = details?.branchName || '';
        this.repaymentData.bankBranchCity = details?.city || '';
    }

    clearBranchDetails() {
        this.repaymentData.branchName = '';
        this.repaymentData.bankBranchCity = '';
    }

    handleBankChange(event) {
        const bankId = event.detail?.value || '';
        const previousBankId = this.repaymentData.bankName;
        this.repaymentData.bankName = bankId;
        if (bankId !== previousBankId) {
            this.clearBankDependentFields();
        }
        this.repaymentData = { ...this.repaymentData };
        this.isDataUpdated = true;
    }

    clearBankDependentFields() {
        this.repaymentData.accountNumber = '';
        this.repaymentData.ifscCode = '';
        this.repaymentData.branchName = '';
        this.repaymentData.bankBranchCity = '';
    }
    
    async validateFields() {
        if (this.isRepaymentOpsView) {
            if (!this.hasRepaymentFieldValue(this.repaymentData.allMandateDetailsCorrectlyEntered)) {
                this.showToast(
                    'Error',
                    'Please select All Mandate Details Correctly Entered'
                );
                return false;
            }
            if (!this.hasRepaymentFieldValue(this.repaymentData.remarks)) {
                this.showToast('Error', 'Please enter Remarks');
                return false;
            }
            return true;
        }

        const requiredFields = [
            { field: 'repaymentToBeDoneBy', name: 'Repayment to be done by' },
            { field: 'repaymentMethod', name: 'Repayment Method' },
            { field: 'bankName', name: 'Bank Name' }
            // { field: 'accountNumber', name: 'Account Number' },
            // { field: 'ifscCode', name: 'IFSC Code' }
        ];
        
        const missingFields = requiredFields.filter(item => !this.repaymentData[item.field]);
        
        if (missingFields.length > 0) {
            this.showToast('Error', `Please fill in the following required fields: ${missingFields.map(f => f.name).join(', ')}`);
            return false;
        }
        
        if (this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['UPI Autopay']) && !this.repaymentData.upiId) {
            this.showToast('Error', 'UPI ID is required for UPI Autopay');
            return false;
        }
        
        if (this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['e-SIGN', 'E'])) {
            const eSignRequiredFields = [
                { field: 'ifscCode', name: 'IFSC Code' },
                { field: 'bankName', name: 'Bank Name' },
                { field: 'accountNumber', name: 'Account Number' },
                { field: 'AadharESignType', name: 'E-Sign Type' }
            ];

            const missingESignFields = eSignRequiredFields.filter(item => !this.repaymentData[item.field]);

            if (missingESignFields.length > 0) {
                this.showToast('Error', `Please fill in the following required fields for Aadhaar e-SIGN: ${missingESignFields.map(f => f.name).join(', ')}`);
                return false;
            }
        }

        if (this.isAchUploadRequired && !this.isBothFilesUploaded) {
            this.showToast(
                'Error',
                'Please upload ACH Mandate Form and Bank Statement'
            );
            return false;
        }

        return true;
    }

    buildRepaymentUpdateFields() {
        this.applyRepaymentFieldDefaults();

        const repaymentFIELDS = {};
        repaymentFIELDS[REPAYMENT_DETAILS_ID.fieldApiName] = this.repaymentsId;
        repaymentFIELDS[BANK_MASTER.fieldApiName] = this.repaymentData.bankName;
        repaymentFIELDS[REPAYMENT_METHOD.fieldApiName] = this.repaymentData.repaymentMethod;
        repaymentFIELDS[ACCOUNT_NUMBER.fieldApiName] = this.repaymentData.accountNumber;
        repaymentFIELDS[IFSC_CODE.fieldApiName] = this.repaymentData.ifscCode;
        repaymentFIELDS[BRANCH_NAME.fieldApiName] = this.repaymentData.branchName;
        repaymentFIELDS[BRANCH_CITY.fieldApiName] = this.repaymentData.bankBranchCity;
        repaymentFIELDS[REPAYMENT_TO_BE_DONE_BY.fieldApiName] =
            this.repaymentData.repaymentToBeDoneBy;
        repaymentFIELDS[DEAL_NUMBER.fieldApiName] =
            this.repaymentData.dealNumber || this.dealId;

        const method = this.normalizeRepaymentMethod(this.repaymentData.repaymentMethod);

        if (this.isRepaymentMethod(method, ['e-SIGN', 'E'])) {
            repaymentFIELDS[ESIGN_TYPE.fieldApiName] = this.repaymentData.AadharESignType;
            repaymentFIELDS[TYPE_OF_ACCOUNT.fieldApiName] = this.repaymentData.accountType;
        }
        if (this.isRepaymentMethod(method, ['UPI Autopay'])) {
            repaymentFIELDS[UPI_ID.fieldApiName] = this.repaymentData.upiId;
        }
        if (this.isRepaymentMethod(method, ['SI', 'I'])) {
            repaymentFIELDS[INITIATION_METHOD.fieldApiName] = this.repaymentData.initiationMethod;
        }

        const recordTypeKey = REPAYMENT_METHOD_RECORD_TYPE_KEY[method];
        if (recordTypeKey && this.repaymentRecordTypeMap[recordTypeKey]) {
            repaymentFIELDS[RECORD_TYPE_ID.fieldApiName] =
                this.repaymentRecordTypeMap[recordTypeKey];
        }

        if (this.isRepaymentOpsView) {
            repaymentFIELDS[ALL_MANDATE_DETAILS_CORRECT.fieldApiName] =
                this.repaymentData.allMandateDetailsCorrectlyEntered;
            repaymentFIELDS[REMARKS.fieldApiName] = this.repaymentData.remarks;
        }

        return repaymentFIELDS;
    }

    async saveRepaymentDetails() {
        try {
            const repaymentFIELDS = this.buildRepaymentUpdateFields();
            return await saveRepaymentDetailsApex({
                repaymentFieldsJson: JSON.stringify(repaymentFIELDS)
            });
        } catch (error) {
            console.error('Error saving repayment details:', error);
            this.showToast('Error', SOMETHING_WENT_WRONG);
            return false;
        }
    }

    /** Dispatches losnextstage so stageMenu advances to the next screen. */
    requestNextStage() {
        const currentViewId = this.currentViewId;
        if (!currentViewId) {
            this.showToast('Navigation Error', 'Current view ID is missing. Please refresh the page.', 'error');
            return;
        }
        window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
            detail: {
                currentViewId,
                id: currentViewId,
                applicantId: this.applicantId,
                currentLoanStageComplete: this.tab || STAGE_REPAYMENT_MANDATE,
                currentStagePhrase: this.stagePhrase || ''
            },
            bubbles: true,
            composed: true
        }));
    }
    
    async saveRepaymentMandate() {
        // const valid = await this.validateForm();
        // if (!valid) {
        //     return { success: false };
        // }

        try {
            this.isPageLoading = true;

            // Stub success until mandate callouts are integrated.
            // this.showResendTimerSms();
            // await new Promise(resolve => setTimeout(resolve, 1500));
            // this.diableInitiateMandate = true;
            //
            // if (this.repaymentData.repaymentMethod === 'N') {
            //     await this.initiateEnachHandler();
            // } else if (this.repaymentData.repaymentMethod === 'I') {
            //     await this.doSICallout();
            // } else if (this.repaymentData.repaymentMethod === 'UPI Autopay') {
            //     await this.doUPICreateMandate();
            // } else if (this.repaymentData.repaymentMethod === 'E') {
            //     await this.doAadharESignCallout();
            // }
            // setTimeout(async () => {
            //     await this.loadEnachJournyStatusHistory();
            // }, 1000);

            const saved = await this.saveRepaymentDetails();
            if (!saved) {
                return { success: false };
            }

            this.diableInitiateMandate = true;
            this.setNextEnabled(true);
            this.showToast('Success', 'Repayment mandate saved successfully');
            return { success: true };
        } catch (error) {
            console.error('Error saving repayment mandate:', error);
            this.showToast('Error', 'Failed to save repayment mandate');
            this.diableInitiateMandate = false;
            return { success: false };
        } finally {
            this.isPageLoading = false;
        }
    }
    
    async sendMandateSetupLink() {
        if (!await this.validateFields()) {
            return;
        }
        await this.saveRepaymentDetails();
        try {
            this.isPageLoading = true;
            this.showToast('Success', 'Mandate setup link sent successfully');
        } catch (error) {
            console.error('Error sending mandate setup link:', error);
            this.showToast('Error', 'Failed to send mandate setup link');
        } finally {
            this.isPageLoading = false;
        }
    }

    // ── Validate / mandate integrations ─────────────────────────────────────

    async doIFSCCallout() {
        return this.stubDoIFSCCallout();
    }

    handleValidateDetailsButton(){
        if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['UPI Autopay'])){
            this.doUPICheckVPACallout();
        }else{
            this.handlePennyDropApiCall();
        }
    }

    async handlePennyDropApiCall() {
        if (!this.validatePennyDropRequirements()) {
            return;
        }
        
        this.isPageLoading = true;
        const serviceName =this.getRepaymentMethodLabel(this.repaymentData.repaymentMethod)+'Penny_Drop_API';
        const retryCountServiceName = this.getRepaymentMethodLabel(this.repaymentData.repaymentMethod)+'Penny_Drop_API';

        const retryCheckResult = await this.checkRetryCount(serviceName, retryCountServiceName);
        if (!retryCheckResult.isSuccess) {
            this.handleRetryExhausted(retryCheckResult);
            this.diableValidateBankDetails = true;
            return;
        }
        
        try {
            const pennyDropCheck = await this.checkApiSuccess(this.getRepaymentMethodLabel(this.repaymentData.repaymentMethod)+'Penny_Drop_API');
            
            let pennyDropResponse;
            
            if (pennyDropCheck.success && pennyDropCheck.isCached) {
                console.log('Using cached Penny Drop response');
                pennyDropResponse = JSON.parse(pennyDropCheck.response);
            } else {
                console.log('Calling Penny Drop API');
                const pennyDropbody = this.buildPennyDropRequestBody();
                
                pennyDropResponse = await this.stubPennyDropCallout();

                if (pennyDropResponse == '' || pennyDropResponse == undefined || pennyDropResponse == null) {
                    this.showToast('Penny Drop Error', 'No response found. Please re-try');
                    return null;
                }
            }
            
            this.processPennyDropResponse(pennyDropResponse);
            
        } catch (error) {
            console.error('Error in penny drop API call:', error);
            this.showToast('Error', 'Penny Drop API call failed');
        } finally {
            this.isPageLoading = false;
        }
    }

    validatePennyDropRequirements() {
        if (!this.repaymentData.accountNumber) {
            this.showToast('Error', 'Account No is Missing');
            return false;
        }
        if (!this.repaymentData.ifscCode) {
            this.showToast('Error', 'IFSC Code is Missing');
            return false;
        }
        if (this.isIndusindBankRestricted()) {
            this.showToast('Error', 'INDUSIND BANK LTD is not applicable for ACH or e-Nach');
            return false;
        }
        if (this.isNonIndusindBankForSI()) {
            this.showToast('Error', 'Please select INDUSIND BANK LTD only to proceed further');
            return false;
        }
        return true;
    }

    isIndusindBankRestricted() {
        const bank = this.getBankNameById(this.repaymentData.bankName);
        return this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['ACH', 'e-NACH', 'N', 'A']) 
               && bank === 'INDUSIND BANK LTD';
    }

    isNonIndusindBankForSI() {
        const bank = this.getBankNameById(this.repaymentData.bankName);
        return this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['SI', 'I', 'IES', 'S']) 
               && bank !== 'INDUSIND BANK LTD';
    }

    handleRetryExhausted(retryCheckResult) {
        if (retryCheckResult.isRetryExhausted) {
            this.showToast('Error', retryCheckResult.message);
            this.isPageLoading = false;
            this.diableInitiateMandate = true;
            this.RetryExhausted = true;
        }
    }

    processPennyDropResponse(pennyDropResponse) {
        if (!pennyDropResponse) {
            this.showToast('Error', 'No response found. Please retry');
            this.isPageLoading = false;
            return;
        }

        if (pennyDropResponse.status === 'SUCCESS') {
            this.isPageLoading = false;
            this.showIntiateButton = true;
            this.diableInitiateMandate = false;
            this.handlePennyDropSuccess(pennyDropResponse);
        } else if (pennyDropResponse.status === 'FAILED') {
            this.handlePennyDropSuccess(pennyDropResponse); //Need to Remove aftre testing
            this.showToast('Error', 'PennyDrop Callout Failed');
            this.isPageLoading = false;
        } else {
            this.handlePennyDropError(pennyDropResponse);
        }
    }

    handlePennyDropSuccess(pennyDropResponse) {
        const content = pennyDropResponse?.content[0];
        if (content?.StatusCode === 'R000') {
            this.showToast('Success', 'PennyDrop Callout Succeed');
            // const bank = this.getBankNameById(this.repaymentData.bankName);
            // if (this.repaymentData.repaymentMethod !== 'I' && bank !== 'INDUSIND BANK LTD') {
            //     setTimeout(() => {
            //         this.callTextMatchApi(content.BeneficiaryName);                    
            //     }, 1000);
            // }
        } else {
            this.handlePennyDropStatusCodeError(content);
        }
    }

    handlePennyDropStatusCodeError(content) {
        if (this.pennyDropValidation?.includes(content?.StatusDesc)) {
            this.showToast('Error', content.StatusDesc);
            this.isPageLoading = false;
        } else {
            this.isPageLoading = false;
            this.showToast('Information', content?.StatusDesc);
        }
    }

    handlePennyDropError(pennyDropResponse) {
        if (pennyDropResponse.errorMessage) {
            this.showToast('Error', pennyDropResponse.errorMessage);
        } else {
            this.showToast('Error', 'We were unable to verify your bank account at this time. Please check your account details and try again.');
        }
        this.isPageLoading = false;
    }

    buildPennyDropRequestBody() {
        const baseData = {
            BeneficiaryName: this.applicantDetails.Name,
            CreditAccountNumber: this.repaymentData.accountNumber,
            BeneficiaryBankIFSCCode: this.repaymentData.ifscCode,
            BeneficiaryMobileNumber: this.applicantDetails.Contact_number__c,
            EmailID: this.applicantDetails.Email__c,
            CustomerCode: this.applicantDetails.Customer_Code__c,
            DealNo: this.repaymentData.dealNumber,
            MakerId: this.makerId,
            dealId: this.dealId
        };

        return this.isSandbox ? baseData : baseData;
    }

    async callTextMatchApi(beneficiaryName) {
        try {
            this.isPageLoading = true;
            
            const textMatchCheck = await this.checkApiSuccess('Text_Match_API');
            
            let result;
            
            if (textMatchCheck.success && textMatchCheck.isCached) {
                console.log('Using cached Text Match response');
                result = textMatchCheck.response;
            } else {
                console.log('Calling Text Match API');
                const textMatch = this.buildTextMatchRequest(beneficiaryName);
                result = JSON.stringify({ matchScore: 80 });
                console.log('text match response :' + result);
            }

            if (result) {
                this.processTextMatchResponse(result);
            } else {
                this.isPageLoading = false;
                this.showToast('Error', 'Response not found, please retry!');
            }
        } catch (error) {
            console.log('Get error in text match :' + JSON.stringify(error));
            this.showToast('Error', 'Text Match API Failed');
            this.isPageLoading = false;
        }
    }

    buildTextMatchRequest(beneficiaryName) {
        const baseData = {
            applicationId: this.loanApplicationId,
            leadId: '',
            applicantFirstName: this.applicantDetails.Name,
            applicantMiddleName: '',
            applicantLastName: '',
            destinationNames: beneficiaryName
        };

        return baseData;
    }

    processTextMatchResponse(result) {
        const parseResp = JSON.parse(result);
        const matchScore = parseResp.ResponseData.Fields.Applicants.Applicant.Services.Service[0]
            .Operations.Operation[0].Data.Response.RawResponse.MatchService.Source[0].NameMatch;
        
        console.log('Applicant Name match Percentage : ' + matchScore);
        this.matchScore = matchScore;

        if (matchScore) {
            if (matchScore >= 51) {
                this.isPageLoading = false;
                this.diableInitiateMandate = false;
            } else {
                this.showToast('Error', 'We regret to inform you that we are unable to proceed with your application as it does not comply with the bank\'s internal policy');
                this.isPageLoading = false;
                this.diableInitiateMandate = true;
            }
        } else {
            this.showToast('Error - Text Match', 'Something went wrong while processing your request. Please try again.');
            this.isPageLoading = false;
        }
    }

    async initiateEnachHandler() {
        const retryCheckResult = await this.checkENACHRegistrationJourneyRetryCount();
        if (!retryCheckResult.isSuccess) {
            this.handleRetryExhausted(retryCheckResult);
            return;
        }
        
        try {
            const result = await this.stubEnachRegistrationJourney();
            
            await this.processEnachRegistrationResponse(result);
            setTimeout(async () => {
                await this.loadEnachJournyStatusHistory();
            }, 1000);
        } catch (error) {
            this.isPageLoading = false;
            this.diableInitiateMandate = false;
            console.log('error ENCH red--' + JSON.stringify(error));
            this.showToast('Error', 'Enach reg journey failed');
        }
    }

    async processEnachRegistrationResponse(result) {
        const response = JSON.parse(result);
        if (response.Resp_Code === '200') {
            console.log('response doRegistrationJourneyCallout..' + JSON.stringify(result));
            this.updateEnachRegistrationData(response);
            this.showToast('Success', 'ENACH Registration Success');
            setTimeout(() => {
                this.updateRecordDetails(this.buildEnachRepaymentFields(response));
            }, 1000);
            this.enachTriggerHandler();
        } else {
            console.log("E-Nach initiate Error-> " + response.Resp_Msg);
            this.showToast('Error', 'Something went wrong while processing your request. You may select a different payment method to proceed');
            this.diableInitiateMandate = false;
            this.isPageLoading = false;
        }
    }

    updateEnachRegistrationData(response) {
        this.url = response.Registration_Url;
        this.enachSession = response.Session_Id;
        this.eNachMessage = response.Resp_Message;
    }

    buildEnachRepaymentFields(response) {
        const repaymentFIELDS = {};
        repaymentFIELDS[REPAYMENT_DETAILS_ID.fieldApiName] = this.repaymentsId;
        repaymentFIELDS[URL_FIELD.fieldApiName] = response.Registration_Url;
        repaymentFIELDS[E_NACH_SESSION.fieldApiName] = response.Session_Id;
        repaymentFIELDS[MESSAGE.fieldApiName] = response.Resp_Message;
        repaymentFIELDS[ENACH_BUTTON_CLICK_TIME_FIELD.fieldApiName] = new Date().toString();
        repaymentFIELDS[REPAYMENT_METHOD.fieldApiName] = this.repaymentData.repaymentMethod;
        return repaymentFIELDS;
    }

    async enachTriggerHandler() {
        this.isPageLoading = true;
        const smsRequestString = this.buildEnachSmsRequest();
        
        try {
            await this.stubSmsGatewayCallout();
            this.handleEnachSmsSuccess();
        } catch (error) {
            this.handleEnachSmsError();
        }
    }

    buildEnachSmsRequest() {
        return {
            applicantId: this.applicantDetails.Id,
            applicationId: this.loanApplicationId,
            flag: "ENACH",
            url: this.url,
            accountNumEnd: this.accLastDigits
        };
    }

    async handleEnachSmsSuccess() {
        await this.loadEnachJournyStatusHistory();
        if (this.eNachStatus !== 'ENACH Registration Success') {
            const repaymentFIELDS = {};
            repaymentFIELDS[REPAYMENT_DETAILS_ID.fieldApiName] = this.repaymentsId;
            repaymentFIELDS[E_NACH_API_STATUS.fieldApiName] = 'In Progress';
            this.updateRecordDetails(repaymentFIELDS);
        }
        this.showToast('Success', 'An SMS has been sent to the customer\'s mobile number for Enach');
        this.showTimer = true;
        this.isPageLoading = false;
        this.startCountDown();
        this.triggerEnachStatusCheck();
    }

    handleEnachSmsError() {
        this.isPageLoading = false;
        this.showTimer = true;
        this.showToast('Error', 'Something went wrong while processing your request. You may select a different payment method to proceed');
        this.startCountDown();
        console.log("Trigger E-NACH error->", error);
    }

    triggerEnachStatusCheck() {
        const reqwrap = { enachStatus: this.enachSession };
        this.stubEnachStatusAsyncCallout().catch(() => {
            this.showToast('Error', 'Something went wrong while processing your request. You may select a different payment method to proceed');
        });
    }

    startCountDown() {
        const timerId = setInterval(() => {
            if ((this.timeLeft % RETRIGGER_STATUS_CHECK_FREQUENCY_TIME) === 0) {
                console.log('Inside status check frequency block. Current time left : ', this.timeLeft);
                this.checkRepaymentMandateStatus(timerId);
            }
            if (this.timeLeft === 0) {
                this.clearTimer(timerId);
                this.showTimer = false;
                this.diableInitiateMandate = false;
                this.timeLeft = RETRIGGER_TIME; //Reset timer
            } else {
                this.timeLeft--;
                this.updateCountDownDisplay();
            }
        }, TIMER_INTERVAL);
        
        this.activeTimers.add(timerId);
    }

    updateCountDownDisplay() {
        this.timeLeftInMins = '0' + Math.trunc(this.timeLeft / 60);
        let timeLeftInSecsWithFraction = (this.timeLeft % 60).toString();
        this.timeLeftInSecs = timeLeftInSecsWithFraction.length === 2 ? timeLeftInSecsWithFraction : '0' + timeLeftInSecsWithFraction;
    }

    checkRepaymentMandateStatus(timerId) {
        console.log('Mandate status polling disabled until integration status API is wired. timerId:', timerId);
    }

    updateEnachStatusFromResult(result, timerId) {
        this.eNachStatus = result.E_NACH_API_Status__c;
        this.eNachMessage = result.Message__c;
        
        if (this.eNachStatus === 'ENACH Registration Success') {
            console.log('Inside checkRepaymentMandateStatus js method. status success ');
            this.clearTimer(timerId);
            this.showToast('Success','ENACH Mandate completed');
            this.showTimer = false;
            this.setNextEnabled(true);
            this.diableInitiateMandate = true;
            this.showSuccessMessage = true;
        }
        else if(this.eNachStatus === 'ENACH Registration Failed'){
            // Show toast for ENACH Registration Failed
            this.showToast('Error', 'ENACH Registration Failed. Checking for status change...');
            
            // Increment failure counter to track duration
            this.failureCheckCounter += parseInt(RETRIGGER_STATUS_CHECK_FREQUENCY_TIME, 10);
            console.log(`ENACH Failed. Failure counter: ${this.failureCheckCounter}`);

            // If this is the first failure, reset timer to 5 minutes
            if (this.failureCheckCounter === parseInt(RETRIGGER_STATUS_CHECK_FREQUENCY_TIME, 10)) {
                console.log('ENACH Registration Failed - Resetting timer to 5 minutes');
                this.timeLeft = 300; // 5 minutes in seconds
                this.updateCountDownDisplay();
            }
            
            // Check if failure has persisted for 5 minutes
            if (this.failureCheckCounter >= this.FAILURE_STATUS_DURATION_LIMIT) {
                console.log('Failure persisted for 5 minutes. Stopping timer.');
                this.clearTimer(timerId);
                this.showToast('Error', 'ENACH Mandate failed after multiple retries.');
                this.showTimer = false;
                this.diableInitiateMandate = false;
            }
        } 
        else{
            this.failureCheckCounter = 0;
        }
    }

    updateSIStatusFromResult(result, timerId) {
        this.siStatus = result.SI_Status__c;
        this.siMsg = result.Message__c;
        if (this.siStatus === 'SUCCESS') {
            console.log('Inside checkSIResponseStatus js method. status success ');
            this.clearTimer(timerId);
            this.showToast('Success','Standing Instruction Mandate completed');
            this.showTimer = false;
            this.setNextEnabled(true);
            this.diableInitiateMandate = true;
            this.showSuccessMessage = true;
        }
        else if(this.siStatus === 'FAILED'){
            // Show toast for SI Registration Failed
            this.showToast('Error', 'SI Registration Failed. Checking for status change...');
            
            // Increment failure counter to track duration
            this.failureCheckCounter += parseInt(RETRIGGER_STATUS_CHECK_FREQUENCY_TIME, 10);
            console.log(`SI Failed. Failure counter: ${this.failureCheckCounter}`);

            // If this is the first failure, reset timer to 5 minutes
            if (this.failureCheckCounter === parseInt(RETRIGGER_STATUS_CHECK_FREQUENCY_TIME, 10)) {
                console.log('SI Registration Failed - Resetting timer to 5 minutes');
                this.timeLeft = 300; // 5 minutes in seconds
                this.updateCountDownDisplay();
            }
            
            // Check if failure has persisted for 5 minutes
            if (this.failureCheckCounter >= this.FAILURE_STATUS_DURATION_LIMIT) {
                console.log('Failure persisted for 5 minutes. Stopping timer.');
                this.clearTimer(timerId);
                this.showToast('Error', 'SI Mandate failed after multiple retries.');
                this.showTimer = false;
                this.diableInitiateMandate = false;
            }
        } 
        else{
            this.failureCheckCounter = 0;
        }
    }

    updateUPIMandateStatusFromResult(result, timerId) {
        this.upiMandateStatus = result.UPI_Mandate_Status__c;
        this.upiMandateMsg = result.Message__c;
        if (this.upiMandateStatus === 'SUCCESSFUL') {
            console.log('Inside updateUPIMandateStatusFromResult js method. status success ');
            this.clearTimer(timerId);
            this.showToast('Success','UPI Mandate is completed');
            this.setNextEnabled(true);
            this.showTimer = false;
            this.diableInitiateMandate = true;
            this.showSuccessMessage = true;
        }else if(this.upiMandateStatus === 'FAILED'){
            this.clearTimer(timerId);
            this.showToast('Success','UPI Mandate is Failed');
            this.setNextEnabled(false);
            this.showTimer = false;
            this.diableInitiateMandate = false;
            this.showSuccessMessage = false;
        }
    }

    async doSICallout() {
        const retryCheckResult = await this.checkSISMSRetryCount();
        if (!retryCheckResult.isSuccess) {
            this.handleRetryExhausted(retryCheckResult);
            return;
        }
        
        this.refIdnumber = await this.stubGenerateReferenceNo();
        if (this.refIdnumber) {
            await this.processSICallout();
        }
    }

    async processSICallout() {
        const getURLResp = await this.stubGetSIUrl();
        
        if (getURLResp) {
            this.url = getURLResp;
            await this.sendSISms();
        }
    }

    async sendSISms() {
        const smsRequestString = this.buildSISmsRequest();
        console.log('Si sms req---' + JSON.stringify(smsRequestString));
        
        try{
            const smsResp = await this.stubSmsGatewayCallout();
            if (smsResp) {
                await this.updateSIRecord();
                this.showToast('Success', 'Link and an SMS has been sent to the customer\'s mobile number for Standing Instructions');
                this.showTimer = true;
                this.startCountDown();
                this.triggerSIStatusCheck();
            }else{
                this.showToast('Success', 'Something went wrong while processing your request.');
                this.isPageLoading = false;
            }
        }
        catch (error) {
            console.log('Error in sendSISms' + error);
            this.showToast('Error', 'Something went wrong while processing your request.');
        }
    }

    buildSISmsRequest() {
        return {
            applicantId: this.applicantDetails.Id,
            applicationId: this.loanApplicationId,
            flag: "SI_Online",
            url: encodeURIComponent(this.url),
            name: this.applicantDetails.Name
        };
    }

    async updateSIRecord() {
        const fields = {};
        fields[REPAYMENT_DETAILS_ID.fieldApiName] = this.repaymentsId;
        fields[URL_FIELD.fieldApiName] = this.url;
        fields[SI_STATUS.fieldApiName] = "In Progress";
        fields[REPAYMENT_METHOD.fieldApiName] = this.repaymentData.repaymentMethod;
        fields[ENACH_BUTTON_CLICK_TIME_FIELD.fieldApiName] = new Date().toString();;
        await this.updateRecordDetails(fields);
        this.siStatus = "In Progress";
        this.isPageLoading = false;
    }

    triggerSIStatusCheck() {
        const reqwrap = {
            customerCode: this.repaymentData.customerCode,
            dealNumber: this.repaymentData.dealNumber,
            RefId: this.refIdnumber
        };
        
        this.stubSIStatusAsyncCallout().catch(() => {
            this.isPageLoading = false;
            this.diableInitiateMandate = false;
            this.showToast('Error', 'Something went wrong while processing your request.');
        });
    }

    async doUPICheckVPACallout(){
        if(this.repaymentData.upiId == null || this.repaymentData.upiId == ''){
            this.showToast('Error', 'Please enter UPI ID');
            return;
        }

        const regex = /^[a-zA-Z0-9._\-+]{2,256}@[a-zA-Z0-9.\-]{2,64}$/;
        if (!regex.test(this.repaymentData.upiId)) {
            this.showToast('Error', 'Please enter a valid UPI ID (format: username@bank).');
            return;
        }
        const retryCheckResult = await this.checkUPICheckVPARetryCount();
        if (!retryCheckResult.isSuccess) {
            this.handleRetryExhausted(retryCheckResult);
            this.showIntiateButton = true;
            this.disableUPIID = true;
            return;
        }
        this.diableValidateBankDetails=true;
        this.isPageLoading = true;
        const requestWrapper = JSON.stringify({
            vpa: this.repaymentData.upiId,
            applicationId: this.loanApplicationId
        });

        try {
            const result = await this.stubUpiCheckVpa();
            
            if(result && result.responseJSONasPlainText){
                console.log('UPI VPA api Check - Success', JSON.stringify(JSON.parse(result.responseJSONasPlainText)));
                const response = JSON.parse(result.responseJSONasPlainText);
                this.payerTypeName = response.payeeType.name;
                this.pspRefNo = response.requestInfo.pspRefNo;
                if(response.status === 'S' && response.statusDesc == 'VPA is available for transaction' && response.is_vpa_valid == 'Y'){
                    this.showToast('Success', 'UPI Id validated successfully');
                    this.isPageLoading = false;
                    this.disableUPIID = true;
                    this.showIntiateButton = true;
                    this.diableValidateBankDetails = true;
                    this.repaymentData.ifscCode = response.payeeType.merchantInfo.ifsc;
                    
                    setTimeout(() => {
                        const result = this.doIFSCCallout();
                        if (result && result.isSuccess && result.responseJSONasPlainText) { //PCTP-2008 - Null check added
                            console.log('IFSC code api Check - Success', JSON.stringify(JSON.parse(result.responseJSONasPlainText)));
                            const response = JSON.parse(result.responseJSONasPlainText);
                            this.isPageLoading = false;
                            this.showToast('Success', 'IFSC Code API - Success');
                            this.updateBranchDetails(response);
                        } else {
                            this.showToast('Error', 'Invalid IFSC Code');
                            this.clearBranchDetails();
                        }
                    }, 1500);

                    const repaymentFIELDS = {}
                    repaymentFIELDS[REPAYMENT_DETAILS_ID.fieldApiName] = this.repaymentsId;
                    repaymentFIELDS[UPI_ID.fieldApiName] = this.repaymentData.upiId;
                    repaymentFIELDS[UPI_VPA_CHECK.fieldApiName] = response.is_vpa_valid;
                    this.updateRecordDetails(repaymentFIELDS);

                    this.diableInitiateMandate = false;
                    
                }else{
                    this.diableValidateBankDetails=false;
                    this.isPageLoading = false;
                    this.disableUPIID = false;
                    this.showToast('Error', 'UPI Id validation failed');
                }
            }else{
                this.diableValidateBankDetails=false;
                this.isPageLoading = false;
                this.disableUPIID = false;
                this.showToast('Error', 'Something went wrong while processing your request. You may select a different payment method to proceed');
            }
        } catch (error) {
            console.log('UPI VPA api Check - Error', JSON.stringify(error));
            this.showToast('Error', 'Something went wrong while processing your request. You may select a different payment method to proceed -'+JSON.stringify(error));
            throw error;
        }
    }

    async doUPICreateMandate(){
        const retryCheckResult = await this.checkUPIMandateRetryCount();
        if (!retryCheckResult.isSuccess) {
            this.handleRetryExhausted(retryCheckResult);
            return;
        }
        try {
            const requestWrapper = JSON.stringify({
                applicationId: this.loanApplicationId,
                payerTypeName: this.payerTypeName,
                accountNumber: this.repaymentData.accountNumber,
                dealId: this.dealId,
                amount: this.repaymentData.emiAmount,
                repaymentRecordId: this.repaymentsId,
                pspRefNo: this.pspRefNo,
                virtualAddress: this.repaymentData.upiId
            });

            const result = await this.stubUpiCreateMandate();
            
            if(result && result.responseJSONasPlainText){
                console.log('UPI Create Mandate api Check - Success', JSON.stringify(JSON.parse(result.responseJSONasPlainText)));
                const response = JSON.parse(result.responseJSONasPlainText);
                if(response.status == 'S' && response.statusDesc == 'Mandate request initiated successfully'){
                    this.startCountDown();
                    this.showTimer = true;
                    this.isPageLoading = false;
                    this.showToast('Success', 'Mandate request initiated successfully');
                    const repaymentFIELDS = {};
                    repaymentFIELDS[REPAYMENT_DETAILS_ID.fieldApiName] = this.repaymentsId;
                    repaymentFIELDS[UPI_MANDATE_STATUS.fieldApiName] = response.mandateDtls[0].status;
                    repaymentFIELDS[REPAYMENT_METHOD.fieldApiName] = this.repaymentData.repaymentMethod;
                    repaymentFIELDS[ENACH_BUTTON_CLICK_TIME_FIELD.fieldApiName] = new Date().toString();;
                    this.updateRecordDetails(repaymentFIELDS);
                }else{
                    this.diableInitiateMandate = false;
                    this.isPageLoading = false;
                    this.showToast('Error', 'Mandate request initiation Failed');
                }
            }else{
                this.diableInitiateMandate = false;
                this.isPageLoading = false;
                this.showToast('Error', 'Something went wrong');

            }
        }catch (error) {
            console.log('UPI Create Mandate api Check - Error', JSON.stringify(error));
            this.diableInitiateMandate = false;
            this.isPageLoading = false;
            this.showToast('Error', 'UPI Create Mandate api Check - Error '+JSON.stringify(error));
        }
    }

    async updateRecordDetails(fields) {
        let dataSaved = false;
        const recordInput = { fields };
        console.log("before update ", recordInput);
        
        try {
            await updateRecord(recordInput);
            dataSaved = true;
        } catch (error) {
            dataSaved = false;
            this.showToast('Error', SOMETHING_WENT_WRONG);
        }
        return dataSaved;
    }

    async checkRetryCount(serviceName, retryCountServiceName) {
        try {
            const requestJson = JSON.stringify({
                applicationId: this.loanApplicationId,
                retryCountServiceName: retryCountServiceName,
                applicantId: '',
                vehicleId: null,
                serviceName: serviceName
            });

            const result = await checkRetryCount({ requestJson });
            return typeof result === 'string' ? JSON.parse(result) : result;
        } catch (error) {
            return {
                isSuccess: false,
                message: 'Error checking retry count',
                isRetryExhausted: false
            };
        }
    }

    async checkPennyDropRetryCount() {
        return await this.checkRetryCount('Penny_Drop_API', 'Penny_Drop_API');
    }

    async checkENACHRegistrationJourneyRetryCount() {
        return await this.checkRetryCount('Enach_Registration_Journey', 'ENACHRegistrationJourney');
    }

    async checkSISMSRetryCount() {
        return await this.checkRetryCount('SI', SMS_ATTEMPTS);
    }

    async checkUPICheckVPARetryCount(){
        return await this.checkRetryCount('UPI_Check_VPA', 'UPIVPACheck');
    }
    async checkUPIMandateRetryCount(){
        return await this.checkRetryCount('UPI_Create_Mandate', 'UPICreateMandate');
    }

    // Combined Aadhaar E-Sign functionality (combines handleInitiateESign and handleInitiateTriggerESign)
    async doAadharESignCallout() {
        // Validation checks from handleInitiateESign
        if (!this.otpBioValue) {
            this.showToast('Please select E-SIGN Type', 'info');
            this.diableInitiateMandate = false;
            return null;
        }
        
        if (this.otpBioValue == 'BIOMETRIC' && this.bmdSenNo == null) {
            this.showToast('Biometric device is not mapped. Please get Biometric mapped to your tab and then initiate e SIGN through Biometric', 'info');
            return null;
        }

        if (this.otpBioValue != null) {
            this.isPageLoading = true;
            this.diableInitiateMandate = true;
            
            try {
                        const data = await this.stubCreateMandateForESign();
                
                console.log('createMandateForESign response:', data);
                this.isPageLoading = false;
                
                let result = JSON.parse(data);
                if (result.message && result.message != null) {
                    let errMsg = result.message ? result.message : 'Error, please check';
                    this.showToast(errMsg, 'Error');
                    this.isPageLoading = false;
                    this.diableInitiateMandate = false;
                    return;
                } else {
                    if (result.mandate_id != null) {
                        this.mandateID = result.mandate_id;
                        this.disableTriggerESign = false;
                        this.disableInitiateESign = true;
                        
                        const rePayFields = {};
                        rePayFields[REPAYMENT_DETAILS_ID.fieldApiName] = this.repaymentsId;
                        rePayFields[Create_Mandate_Id.fieldApiName] = this.mandateID;
                        rePayFields[Create_Mandate_Initiated_Date.fieldApiName] = new Date().toISOString().split('T')[0];
                        rePayFields[createMandateTriggerCount.fieldApiName] = this.mandateTriggerCnt + 1;
                        
                        await this.updateRecordDetails(rePayFields);
                        this.showToast('Mandate Id Successfully Generated', 'Success');
                        
                        setTimeout(() => {
                            this.triggerESignProcess();
                        }, 1000);

                        if(this.isBothFilesUploaded){
                            this.setNextEnabled(true);
                        }
                    }else{
                        this.showIntiateButton = false;
                    }
                }
            } catch (error) {
                console.log('Error in createMandateForESign:', error);
                this.showToast('Error creating mandate', 'Error');
                this.isPageLoading = false;
                this.diableInitiateMandate = false;
            }
        }
    }

    async triggerESignProcess() {
        let url;
        this.isPageLoading = true;
        
        if (this.otpBioValue == 'OTP') {
            url = '/esign-stub?applicantId=' + this.applicantId;
            this.isPageLoading = false;
            this.startESignCountdown();
        } else {
            this.isPageLoading = false;
            url = '/esign-stub?applicantId=' + this.applicantId;
            this.startESignCountdown();
        }
        console.log('url=========>', url);
        let accLastDigits = this.repaymentData.accountNumber.length > 0 ? 
        this.repaymentData.accountNumber.substring(this.repaymentData.accountNumber.length - 4) : 
        this.repaymentData.accountNumber;
        
        let smsRequestString = {
            applicantId: this.applicantId,
            applicationId: this.loanApplicationId,
            flag: "ESIGN",
            url: url,
            accountNumEnd: accLastDigits
        };
        
        try {
            await this.stubSmsGatewayCallout();
            console.log('SMS sent successfully');
            this.showToast('Info','Link is validated for 24 hours');
        } catch (error) {
            console.log('Error sending SMS:', error);
            this.showToast('Error','Failed to send SMS');
        }

    }

    startESignCountdown() {
        this.disableTriggerESign = true;
        this.countdown = 120;
        this.isCountdownRunning = true;
        this.timer = setInterval(() => {
            this.countdown--;
            if (this.countdown <= 0) {
                clearInterval(this.timer);
                this.disableTriggerESign = false;
                this.isCountdownRunning = false;
            }
        }, 1000);
    }

    /** Application__c Id for Apex callouts (same as recordId from parent). */
    get loanApplicationId() {
        return this.recordId;
    }

    get documentAssetId() {
        return this.assetId || this.selectedAssetId || null;
    }

    get isStagePastView() {
        return this.isStagePast === true || this.isStagePast === 'true';
    }

    get isApplicationWithdrawn() {
        return this.applicationStatus?.isWithdrawn === true;
    }

    get isReadOnlyScreen() {
        return (
            this.isStagePastView ||
            this._isApplicantStageComplete ||
            this.isApplicationWithdrawn
        );
    }

    get isRepaymentOpsView() {
        return this.currentViewId === REPAYMENT_OPS_VIEW_ID;
    }

    get isRepaymentRemarksEditable() {
        return this.isRepaymentOpsView && !this.isReadOnlyScreen;
    }

    get repaymentToBeDoneByDisplay() {
        const match = REPAYMENT_TO_BE_DONE_BY_OPTIONS.find(
            (option) => option.value === this.repaymentData.repaymentToBeDoneBy
        );
        return match?.label || this.repaymentData.repaymentToBeDoneBy || '—';
    }

    get isFieldEditable() {
        return !this.isReadOnlyScreen && !this.isRepaymentOpsView;
    }

    get showActionButtons() {
        return !this.showSuccessMessage && !this.isRepaymentOpsView && !this.isApplicationWithdrawn;
    }

    get showIntiateButtonGetter(){
        if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['UPI Autopay', 'e-NACH', 'N', 'e-SIGN', 'E', 'ACH']) || this.repaymentData.repaymentMethod == null){
            return this.showIntiateButton;
        }else{
            return true;
        }
    }

    // ── UI state getters ────────────────────────────────────────────────────

    get ValidateButtonLabel(){
        if(this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['UPI Autopay'])){
            return 'Validate UPI Details';
        }else{
            return 'Validate Bank Details';
        }
    }

    get isValidateBankDetailsDisabled() {
        return this.isReadOnlyScreen || this.diableValidateBankDetails;
    }

    get makerId() {
        return null;
    }

    get bmdSenNo() {
        return null;
    }

    get showUPIIdField() {
        return this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['UPI Autopay']);
    }

    get isAccountNumberDisabled() {
        return this.isReadOnlyScreen;
    }
    
    get isIFSCDisabled() {
        return this.isReadOnlyScreen || this.isIFSCVerified;
    }
    
    get isBankNameReadonly() {
        return (
            this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['SI', 'I', 'IES', 'S']) ||
            this.isReadOnlyScreen
        );
    }
    
    get isInititationMethodReadonly() {
        if (this.RetryExhausted) {
            return false;
        }
        return this.isReadOnlyScreen;
    }

    get repaymentMethodValue() {
        return this.repaymentData.repaymentMethod;
    }

    /** True when both OPS repayment remark fields are filled. */
    get isOpsRemarksComplete() {
        return (
            this.hasRepaymentFieldValue(this.repaymentData.allMandateDetailsCorrectlyEntered) &&
            this.hasRepaymentFieldValue(this.repaymentData.remarks)
        );
    }

    /** True when Next should be disabled (loading, withdrawn, or stage rules). */
    get isNextDisabled() {
        if (this.isPageLoading || this.isApplicationWithdrawn || this.isStagePastView) {
            return true;
        }
        if (this.isRepaymentOpsView && this.isReadOnlyScreen) {
            return false;
        }
        if (this.isRepaymentRemarksEditable) {
            return !this.isOpsRemarksComplete;
        }
        return this._isNextDisabled;
    }

    /** Toggles stage-flow Next availability (withdrawn state is handled via applicationStatus). */
    setNextEnabled(enabled) {
        const blockedByAchUpload =
            enabled && this.isAchUploadRequired && !this.isBothFilesUploaded;
        this._isNextDisabled = !enabled || blockedByAchUpload;
    }

    get showAchChecklistSection() {
        return this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['e-SIGN', 'E']);
    }

    /** ACH uploads are mandatory for Next when the section is shown and editable. */
    get isAchUploadRequired() {
        return this.showAchChecklistSection && !this.isAchDocumentsDisabled;
    }
    
    get isBothFilesUploaded() {
        return this.achMandateUploaded && this.bankStatementUploaded;
    }

    get isIFSCVerified() {
        return this.repaymentData.branchName && this.repaymentData.branchName.trim() !== '' && 
               this.repaymentData.bankBranchCity && this.repaymentData.bankBranchCity.trim() !== '';
    }

   
    get showInitiateMandateButton() {
        // Don't show button for Indus Easy Savings
        if (this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['IES', 'S'])) {
            return false;
        }
        
        // For Standing Instruction, only show button if SI Online is selected
        if (this.isRepaymentMethod(this.repaymentData.repaymentMethod, ['SI', 'I'])) {
            return this.repaymentData.initiationMethod === 'SI Online';
        }
        // For all other repayment methods, show the button
        return true;
    }
    
    get repaymentMethodDisplay() {
        return this.getRepaymentMethodLabel(this.repaymentData.repaymentMethod) || '—';
    }

    get bankNameDisplay() {
        return this.getBankNameById(this.repaymentData.bankName) || '—';
    }

    get accountTypeDisplay() {
        const match = this.AadharAccountTypeOptions.find(
            (opt) => opt.value === this.repaymentData.accountType
        );
        return match?.label || this.repaymentData.accountType || '—';
    }

    get ifscDisplayValue() {
        if (!this.repaymentData.ifscCode) {
            return '—';
        }
        if (this.isIFSCVerified) {
            return `${this.repaymentData.ifscCode} — ${this.repaymentData.branchName}, ${this.repaymentData.bankBranchCity}`;
        }
        return this.repaymentData.ifscCode;
    }

    get dealInfoIcon() {
        return this.isDealInfoExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    /** Hides ACH download, upload, and delete in OPS view or read-only stage. */
    get isAchDocumentsDisabled() {
        return this.isRepaymentOpsView || this.isReadOnlyScreen;
    }

    get showAchDocumentActions() {
        return !this.isAchDocumentsDisabled;
    }

    get isAchFileUploadDisabled() {
        return this.disableDownloadButton;
    }

    get disableDownloadButton() {
        if (this.isAchDocumentsDisabled) {
            return true;
        }

        const hasBankName = this.hasRepaymentFieldValue(this.repaymentData.bankName);
        const hasAccountNumber = this.hasRepaymentFieldValue(this.repaymentData.accountNumber);
        const hasIfscCode = this.hasRepaymentFieldValue(this.repaymentData.ifscCode);
        const hasAccountType = this.hasRepaymentFieldValue(this.repaymentData.accountType);
        const hasAadharESignType = this.hasRepaymentFieldValue(this.repaymentData.AadharESignType);

        const allFieldsValid =
            hasBankName &&
            hasAccountNumber &&
            hasIfscCode &&
            hasAccountType &&
            hasAadharESignType &&
            this.isIFSCVerified;

        return !allFieldsValid;
    }

    get bankOptions() {
        return (this.bankMasterData || []).map((bank) => ({
            label: bank.Name,
            value: bank.Id
        }));
    }

    // ── Utilities ───────────────────────────────────────────────────────────

    /** Maps legacy single-letter codes to current Repayment_Method__c API values. */
    normalizeRepaymentMethod(method) {
        if (!method) {
            return method;
        }
        return LEGACY_REPAYMENT_METHOD_MAP[method] || method;
    }

    isRepaymentMethod(method, expectedValues) {
        const normalized = this.normalizeRepaymentMethod(method);
        return expectedValues.some(
            (value) => value === normalized || value === method
        );
    }

    getRepaymentMethodLabel(field) {
        const normalized = this.normalizeRepaymentMethod(field);
        const match = this.repaymentMethodOptions.find(
            (option) =>
                option.value === field ||
                option.value === normalized
        );
        return match?.label || field;
    }

    hasRepaymentFieldValue(value) {
        return value != null && String(value).trim() !== '';
    }

    getBankIdByName(bankName) {
        if (!this.bankMasterData || !bankName) {
            return null;
        }

        const bank = this.bankMasterData.find(bank => bank.Name === bankName);
        return bank ? bank.Id : null;
    }

    getBankNameById(bankId) {
        const bank = this.bankMasterData?.find(b => b.Id === bankId);
        return bank?.Name;
    }

    /**
     * Simple method to check if an API has already succeeded
     * @param {String} serviceName - Name of the service to check
     * @returns {Object} - {success: boolean, response: string, isCached: boolean}
     */
    async checkApiSuccess(serviceName) {
        try {
            const result = await checkApiExecutionStatus({
                applicationId: this.loanApplicationId,
                serviceNames: [serviceName]
            });

            if (result.success && result.apiStatusMap[serviceName]) {
                const serviceStatus = result.apiStatusMap[serviceName];
                if (serviceStatus.shouldSkip && serviceStatus.cachedResponse) {
                    return {
                        success: true,
                        response: serviceStatus.cachedResponse,
                        isCached: true
                    };
                }
            }

            return {
                success: false,
                response: null,
                isCached: false
            };
        } catch (error) {
            console.error('Error checking API success:', error);
            return {
                success: false,
                response: null,
                isCached: false
            };
        }
    }

    showToast(title, message, variant) {
        let toastVariant = 'info';
        if (variant === 'Error' || variant === 'error') {
            toastVariant = 'error';
        } else if (variant === 'Success' || variant === 'success') {
            toastVariant = 'success';
        } else if (variant === 'Warning' || variant === 'warning') {
            toastVariant = 'warning';
        } else if (title === 'Error' || title === 'error') {
            toastVariant = 'error';
        } else if (title === 'Success' || title === 'success') {
            toastVariant = 'success';
        }
        this.dispatchEvent(new ShowToastEvent({
            title: title || 'Notification',
            message: message || '',
            variant: toastVariant
        }));
    }

    @api showResendTimerSms() {
        this.clearAllTimers();
        sessionStorage.clear();
        this.showSmsOtptimer = true;
        this.timervalue = TIMER_FORMAT;
        this.resendSmsButtonShow = false;

        const storedTimer = sessionStorage.getItem('timer');
        if (this.isTimerExpired(storedTimer)) {
            this.startSmsTimer();
        } else {
            this.resumeSmsTimer(storedTimer);
        }
    }

    isTimerExpired(timerValue) {
        return !timerValue || timerValue === 'NaN:NaN' || timerValue === TIMER_FORMAT;
    }

    startSmsTimer() {
        let remaining = SMS_TIMER_DURATION;
        const timerId = setInterval(() => {
            if (remaining <= 0) {
                this.clearTimer(timerId);
                this.resendSmsButtonShow = true;
                this.showSmsOtptimer = false;
                sessionStorage.setItem('timer', TIMER_FORMAT);
                return;
            }

            this.updateTimerDisplay(remaining);
            sessionStorage.setItem('timer', this.timervalue);
            remaining--;
        }, TIMER_INTERVAL);

        this.activeTimers.add(timerId);
    }

    resumeSmsTimer(storedTimer) {
        this.timervalue = storedTimer;
        const timerId = setInterval(() => {
            const currentTimer = sessionStorage.getItem('timer');
            if (currentTimer !== TIMER_FORMAT && this.showSmsOtptimer) {
                this.timervalue = currentTimer;
                this.resendSmsButtonShow = false;
            } else {
                this.clearTimer(timerId);
                sessionStorage.removeItem('timer');
                this.showSmsOtptimer = false;
                this.resendSmsButtonShow = true;
            }
        }, TIMER_INTERVAL);

        this.activeTimers.add(timerId);
    }

    updateTimerDisplay(remaining) {
        const minutes = Math.floor(remaining / 60);
        const seconds = remaining % 60;
        const formattedMinutes = minutes < 10 ? '0' + minutes : minutes;
        const formattedSeconds = seconds < 10 ? '0' + seconds : seconds;
        this.timervalue = formattedMinutes + ':' + formattedSeconds;
    }

    clearTimer(timerId) {
        clearInterval(timerId);
        this.activeTimers.delete(timerId);
    }

    clearAllTimers() {
        this.activeTimers.forEach(timerId => clearInterval(timerId));
        this.activeTimers.clear();
    }

    // Local stubs — replace with real callouts when integrations are wired.
    async stubDoIFSCCallout() {
        return {
            responseJSONasPlainText: JSON.stringify({
                localDirectoryDetails: [{ branchName: 'Main Branch', city: 'Mumbai' }]
            })
        };
    }

    async stubPennyDropCallout() {
        return {
            status: 'SUCCESS',
            content: [{ StatusCode: 'R000', StatusDesc: 'Success', BeneficiaryName: this.applicantDetails?.Name }]
        };
    }

    async stubEnachRegistrationJourney() {
        return JSON.stringify({
            Resp_Code: '200',
            Registration_Url: 'https://example.com/enach',
            Session_Id: 'STUB-SESSION-' + Date.now(),
            Resp_Message: 'DB Action Success'
        });
    }

    async stubSmsGatewayCallout() {
        return { success: true };
    }

    async stubEnachStatusAsyncCallout() {
        return { success: true };
    }

    async stubGenerateReferenceNo() {
        return 'REF-' + Date.now();
    }

    async stubGetSIUrl() {
        return 'https://example.com/si-mandate';
    }

    async stubSIStatusAsyncCallout() {
        return { success: true };
    }

    async stubUpiCheckVpa() {
        return {
            responseJSONasPlainText: JSON.stringify({
                status: 'S',
                statusDesc: 'VPA is available for transaction',
                is_vpa_valid: 'Y',
                payeeType: { name: 'Stub Payee', merchantInfo: { ifsc: this.repaymentData.ifscCode || 'HDFC0000001' } },
                requestInfo: { pspRefNo: 'PSP-' + Date.now() }
            })
        };
    }

    async stubUpiCreateMandate() {
        return {
            responseJSONasPlainText: JSON.stringify({
                status: 'S',
                statusDesc: 'Mandate request initiated successfully',
                mandateDtls: [{ status: 'In Progress' }]
            })
        };
    }

    async stubCreateMandateForESign() {
        return JSON.stringify({ mandate_id: 'MANDATE-' + Date.now() });
    }

    async stubEtbAccountPrefill() {
        return { accountId: '123456789012', ifscCode: 'INDB0000001' };
    }

}