import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPageData  from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';
import createRepaymentSchedule from '@salesforce/apex/OfferPageController.createRepaymentSchedule';
import markPaymentRequestStageComplete from '@salesforce/apex/WheelsPaymentRequestController.markPaymentRequestStageComplete';

const APEX_CLASS            = 'WheelsPaymentRequestController';
const LOS_NEXT_STAGE_EVENT  = 'losnextstage';
const STAGE_PAYMENT_REQUEST = 'Payment Request';
const MOVE_BACK_TO_PSS_STAGE = 'moveBackToPssStage';
const LOS_MENU_REFRESH_EVENT = 'losmenurefresh';
const OPS_VIEW_ID           = 'Wheels_Payment_Request_OPS';

export default class WheelsPaymentRequest extends LightningElement {

    @api recordId;
    @api currentViewId;
    @api applicationLineItemId = '';
    @api assetId = '';
    @api stagePhrase = '';
    @api tab = '';
    @api fromAssetList = false;

    @track isLoading         = false;
    @track isNewVehicle      = true;
    @track isUsedOrRefinance = false;

    _isStagePast = false;
    @api
    get isStagePast() { return this._isStagePast; }
    set isStagePast(value) { this._isStagePast = !!value; }

    @track disableAllFields = false;
    get isOperationsStage() {
        return this.tab === STAGE_PAYMENT_REQUEST && this.currentViewId === OPS_VIEW_ID;
    }
    get isOpsReadOnly() { return this._isStagePast || this.disableAllFields; }
    get isReadOnly() { return this._isStagePast || this.disableAllFields || this.isOperationsStage; }
    get disableSubmitButton() {
        return (this.isOperationsStage && this.isOpsReadOnly) || (!this.isOperationsStage && this.isReadOnly);
    }
    get disableNextButton() {
        return (!this.isReadOnly && !this.isOperationsStage) || (!this.isOpsReadOnly && this.isOperationsStage);
    }

    yesNoOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    @track operationData = {
        areAllDetailsCorrect: '',
        remarks: ''
    };

    // ── Business Payment ───────────────────────────────────────────────────
    @track businessPayment = {
        paymentOriginatedFrom:    '',
        vehicleSoldBy:            '',
        // User lookups — store Id, display Name separately
        businessSourcedBy:        '',
        businessSourcedByName:    '',
        businessDoneBy:           '',
        businessDoneByName:       '',
        fiDoneBy:                 '',
        fiDoneByName:             '',
        collectionExecutive:      '',
        doIssuance:               '',
        doIssuanceDate:           '',
        doToBeAuthorizedBy:       '',
        vehicleRegisteredInName:  '',
        balanceTransfer:          '',
        purchaseDocCategory:      '',
        originalPurchaseValue:    '',
        originalPurchaseDate:     '',
        fundEndUse:               ''
    };
    showDoIssuanceDate       = false;
    showDoAuthorizedBy       = false;
    showOriginalPurchaseInfo = false;

    // ── Vehicle Details ────────────────────────────────────────────────────
    @track vehicleDetails = {
        showDetails:         false,
        delivery:            'No',
        rtaTaxRemittedUpto:  '',
        regNumber:           '',
        engineNumber:        '',
        chassisNumber:       '',
        isNameTransferred:   '',
        currentVehicleOwner: '',
        lienMarked:          '',
        markedOn:            '',
        nowLienInTheNameOf:  ''
    };
    isMarkedOnDisabled = true;
    isLienNameDisabled = true;

    // ── Adjustment ────────────────────────────────────────────────────────
    @track adjustmentRows = [
        { id: 1, dealNumber: '', customerName: '', customerCode: '', amount: '', verified: false }
    ];
    _verifyingAdjustmentIndex = null;

    // ── Beneficiary ────────────────────────────────────────────────────────
    @track beneficiaryRows = [
        { id: 1, name: '', accountNumber: '', ifscCode: '', amount: '', verified: false }
    ];

    // ── Disbursement ───────────────────────────────────────────────────────
    @track disbursement = {
        dealerPayment:   '',
        paymentDate:     '',
        firstEmiDueDate: '',
        crmIrr:          '',
        emiAmount:       '',
        holidayPeriod:   '0'
    };
    disbursementModified = false;
    _firstEmiDateStr     = '';  // yyyy-MM-dd from backend, cleared when user picks new day

    // ── Picklist options (populated from Apex) ─────────────────────────────
    @track _doIssuanceModeOptions   = [];
    @track _purchaseDocOptions      = [];
    @track _fundEndUseOptions       = [];

    // ── Integration / Modal ────────────────────────────────────────────────
    showIntegrationModal         = false;
    integrationStatus            = 'loading';
    integrationCurrentStageIndex = 0;
    integrationSuccessMessage    = '';
    integrationStages            = [];
    _verifyingRowIndex           = null;

    showDynamicModal      = false;
    dynamicComponentName  = '';
    dynamicComponentProps = {};

    showSellerBankDetailSection = false;
    @track sellerBankDetails = {
        bankName:       '',
        accountNumber:  '',
        ifscCode:       '',
        pinCode:        '',
        branchName:     '',
        bankBranchCity: '',
        ifscVerified:   false,
        verified:       false
    };

    collectionExecutiveOptions = [
        { label: 'CE001 | Rahul Sharma', value: 'CE001' },
        { label: 'CE002 | Priya Singh', value: 'CE002' },
        { label: 'CE003 | Amit Kumar', value: 'CE003' }
    ]

    doAuthorizedByOptions = [
        { label: 'Branch Manager', value: 'Branch_Manager' },
        { label: 'Regional Manager', value: 'Regional_Manager' }
    ]

    // ── Lifecycle ──────────────────────────────────────────────────────────
    connectedCallback() {
        if (this.fromAssetList && !this.assetId) {
            return;
        }
        this.loadPageData();
    }

    _assetScopeParams() {
        const params = {};
        if (this.assetId) {
            params.assetId = this.assetId;
        }
        if (this.applicationLineItemId) {
            params.applicationLineItemId = this.applicationLineItemId;
        }
        return params;
    }

    async loadPageData() {
        if (!this.recordId) return;
        try {
            this.isLoading = true;
            const data = await getPageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: 'getPageData',
                recordId:       this.recordId,
                params:         this._assetScopeParams()
            });

            // Picklist options from schema
            if (data.doIssuanceModeOptions?.length) this._doIssuanceModeOptions = data.doIssuanceModeOptions;
            if (data.purchaseDocOptions?.length)     this._purchaseDocOptions    = data.purchaseDocOptions;
            if (data.fundEndUseOptions?.length)      this._fundEndUseOptions     = data.fundEndUseOptions;

            // Vehicle type
            const vt = data.asset?.Vehicle_type__c;
            if (vt) {
                this.isNewVehicle      = vt === 'New';
                this.isUsedOrRefinance = vt === 'Used' || vt === 'Refinance';
            }

            // Current user defaults for User lookup fields
            const userId   = data.currentUserId   || '';
            const userName = data.currentUserName  || '';

            // Disbursement Details
            const dd = data.disbursementDetails;
            const doIssuanceVal = dd?.Do_Issuance_Mode__c || (this._doIssuanceModeOptions[0]?.value || '');
            this.businessPayment = {
                ...this.businessPayment,
                paymentOriginatedFrom:    dd?.Payment_Originated_From__c            || '',
                vehicleSoldBy:            dd?.Vehicle_Sold_By__c                    || '',
                businessSourcedBy:        dd?.Business_Sourced_By__c               || userId,
                businessSourcedByName:    data.businessSourcedByName               || userName,
                businessDoneBy:           dd?.Business_Done_By__c                  || userId,
                businessDoneByName:       data.businessDoneByName                  || userName,
                fiDoneBy:                 dd?.FI_Done_By__c                        || userId,
                fiDoneByName:             data.fiDoneByName                        || userName,
                collectionExecutive:      dd?.Collection_Executive__c              || '',
                doIssuance:               doIssuanceVal,
                doIssuanceDate:           dd?.DO_Issuance_Date__c                  || '',
                doToBeAuthorizedBy:       dd?.Do_To_be_authorized_by__c            || '',
                vehicleRegisteredInName:  dd?.Vehicle_Registered_in_Name__c        || '',
                balanceTransfer:          dd?.Balance_Transfer_Amount_in_Rs__c     || '',
                purchaseDocCategory:      dd?.Purchase_Document_Category__c               || '',
                fundEndUse:               dd?.Fund_End_Use__c                             || '',
                originalPurchaseValue:    dd?.Original_Purchase_value_in_Rs__c != null
                                              ? String(dd.Original_Purchase_value_in_Rs__c) : '',
                originalPurchaseDate:     dd?.Original_purchase_date__c                   || ''
            };
            this.showDoIssuanceDate   = doIssuanceVal === 'Along_with_payment';
            this.showDoAuthorizedBy   = doIssuanceVal === 'Separate';
            this.showOriginalPurchaseInfo = (dd?.Purchase_Document_Category__c === 'Invoice');
            this.operationData = {
                areAllDetailsCorrect: dd?.Are_all_details_correct__c || '',
                remarks: dd?.Remarks__c || ''
            };

            // Application_Line_Item__c
            const li = data.lineItem;
            if (li) {
                this._firstEmiDateStr = li.First_EMI_Date__c || '';
                const emiDay = this._firstEmiDateStr
                    ? parseInt(this._firstEmiDateStr.split('-')[2], 10)
                    : 0;
                this.disbursement = {
                    dealerPayment:   dd?.Dealer_Payment__c != null ? String(dd.Dealer_Payment__c) : (li.Loan_Amount__c != null ? String(li.Loan_Amount__c) : ''),
                    paymentDate:     dd?.Payment_to_be_made_on__c || '',
                    firstEmiDueDate: emiDay ? String(emiDay) : '',
                    crmIrr:          li.CRM_IRR__c   != null ? String(li.CRM_IRR__c)   : '',
                    emiAmount:       li.EMI_Amount__c != null ? String(li.EMI_Amount__c) : '',
                    holidayPeriod:   li.Holiday_period__c != null ? String(li.Holiday_period__c) : '0'
                };
            }

            // Asset__c → vehicle details
            const asset = data.asset;
            if (asset) {
                const hasDetails = !!(asset.Vehicle_Registration_number__c || asset.Engine_number__c || asset.Chassis_number__c);
                this.vehicleDetails = {
                    ...this.vehicleDetails,
                    showDetails:         hasDetails,
                    delivery:            hasDetails ? 'Yes' : 'No',
                    rtaTaxRemittedUpto:  asset.RTA_taxes_remitted_upto__c   || '',
                    regNumber:           asset.Vehicle_Registration_number__c || '',
                    engineNumber:        asset.Engine_number__c              || '',
                    chassisNumber:       asset.Chassis_number__c             || '',
                    isNameTransferred:   asset.Name_transferred__c           || '',
                    currentVehicleOwner: asset.Current_vehicle_owner__c      || '',
                    lienMarked:          asset.Lien_marked_to_bank__c ? 'Yes' : 'No',
                    markedOn:            asset.Marked_on__c                  || '',
                    nowLienInTheNameOf:  asset.Now_lien_in_the_name_of__c    || ''
                };
                const lienYes = this.vehicleDetails.lienMarked === 'Yes';
                this.isMarkedOnDisabled = !lienYes;
                this.isLienNameDisabled = !lienYes;
            }

            // Beneficiary rows
            this.beneficiaryRows = data.beneficiaryRows?.length
                ? data.beneficiaryRows.map((ben, i) => ({
                    id:            i + 1,
                    name:          ben.Beneficiary_Name__c || '',
                    accountNumber: ben.Account_Number__c   || '',
                    ifscCode:      ben.IFSC_Code__c        || '',
                    amount:        ben.Amount__c != null   ? String(ben.Amount__c) : '',
                    verified:      !!(ben.Account_Number__c && ben.IFSC_Code__c)
                }))
                : [{ id: 1, name: '', accountNumber: '', ifscCode: '', amount: '', verified: false }];

            // Adjustment rows
            this.adjustmentRows = data.adjustmentRows?.length
                ? data.adjustmentRows.map((adj, i) => ({
                    id:           i + 1,
                    dealNumber:   adj.Deal_Number__c   || '',
                    customerName: adj.Customer_Name__c || '',
                    customerCode: adj.Customer_Code__c || '',
                    amount:       adj.Amount__c != null ? String(adj.Amount__c) : '',
                    verified:     !!(adj.Customer_Name__c)
                }))
                : [{ id: 1, dealNumber: '', customerName: '', customerCode: '', amount: '', verified: false }];

        } catch (error) {
            console.error('[WheelsPaymentRequest] loadPageData:', error);
            this.showToast('Warning', 'Could not load page data.', 'warning');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Option helpers ─────────────────────────────────────────────────────
    _opts(arr, current) {
        return arr.map(o => ({
            ...o,
            isSelected:  o.value === current,
            circleClass: o.value === current ? 'wpr-radio-circle wpr-radio-circle--on' : 'wpr-radio-circle'
        }));
    }

    // Picklist getters — now dynamic from Apex
    get doIssuanceOptions()     { return this._doIssuanceModeOptions; }
    get purchaseDocOptions()    { return this._purchaseDocOptions; }
    get fundEndUseOptions()     { return this._fundEndUseOptions; }

    // Static option arrays
    _po  = [{ label:'State Office',value:'SO'},{label:'Trade Advance',value:'TA'},{label:'Hub',value:'HUB'}];
    _yn  = [{ label:'Yes',value:'Yes'},{label:'No',value:'No'}];
    _emi = [{ label:'5th of Month',value:'5'},{label:'10th of Month',value:'10'}];

    get paymentOriginOptions()     { return this._opts(this._po,  this.businessPayment.paymentOriginatedFrom); }
    get deliveryOptions()          { return this._opts(this._yn,  this.vehicleDetails.delivery); }
    get isNameTransferredOptions() { return this._opts(this._yn,  this.vehicleDetails.isNameTransferred); }
    get lienMarkedOptions()        { return this._opts(this._yn,  this.vehicleDetails.lienMarked); }
    get emiDateOptions()           { return this._opts(this._emi, this.disbursement.firstEmiDueDate); }

    // ── Computed ───────────────────────────────────────────────────────────
    // Mirrors offerPage._computedFirstEmiDateStr + secondEmiDueDate with holiday_period
    get secondEmiDueDate() {
        const day = parseInt(this.disbursement.firstEmiDueDate, 10);
        if (!day) return '—';
        const moratorium = parseInt(this.disbursement.holidayPeriod || '0', 10);
        let firstDate;
        if (this._firstEmiDateStr) {
            const p = this._firstEmiDateStr.split('-');
            firstDate = new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, day);
        } else {
            const t = new Date();
            t.setDate(t.getDate() + moratorium);
            firstDate = t.getDate() < day
                ? new Date(t.getFullYear(), t.getMonth(),     day)
                : new Date(t.getFullYear(), t.getMonth() + 1, day);
        }
        const second = new Date(firstDate.getFullYear(), firstDate.getMonth() + 1, day);
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        return `${day} ${months[second.getMonth()]} ${second.getFullYear()}`;
    }

    get totalBeneficiaryAmount() {
        return this.beneficiaryRows.reduce((s, r) => s + (parseFloat(r.amount) || 0), 0).toLocaleString('en-IN');
    }

    get showRemoveBeneficiary()  { return this.beneficiaryRows.length > 1; }
    get disableAddBeneficiary()  { return this.isReadOnly || this.beneficiaryRows.length >= 4; }
    get totalAdjustmentAmount()  { return this.adjustmentRows.reduce((s, r) => s + (parseFloat(r.amount) || 0), 0).toLocaleString('en-IN'); }
    get showRemoveAdjustment()   { return this.adjustmentRows.length > 1; }
    get disableAddAdjustment()   { return this.isReadOnly || this.adjustmentRows.length >= 8; }
    get showInstallmentScheduleBtn() { return this.disbursementModified; }

    // ── Business Payment handlers ──────────────────────────────────────────
    handleRadioChange(event) {
        this.businessPayment = { ...this.businessPayment, [event.target.dataset.field]: event.target.value };
    }

    handleDoIssuanceChange(event) {
        const v = event.detail.value;
        console.log('v', v);
        this.businessPayment  = {
            ...this.businessPayment,
            doIssuance:         v,
            doIssuanceDate:     v === 'Along_with_payment' ? new Date().toISOString().split('T')[0] : '',
            doToBeAuthorizedBy: v !== 'Separate' ? '' : this.businessPayment.doToBeAuthorizedBy
        };
        this.showDoIssuanceDate = v === 'Along_with_payment';
        this.showDoAuthorizedBy = v === 'Separate';
    }

    handleSelectChange(event) {
        this.businessPayment = { ...this.businessPayment, [event.target.dataset.field]: event.detail.value };
    }

    handleInputChange(event) {
        this.businessPayment = { ...this.businessPayment, [event.target.dataset.field]: event.target.value };
    }

    handlePurchaseDocChange(event) {
        const v = event.detail.value;
        this.businessPayment         = { ...this.businessPayment, purchaseDocCategory: v };
        this.showOriginalPurchaseInfo = v === 'Invoice';
    }

    handleIsAllDetailsCorrectChange(event) {
        this.operationData = {
            ...this.operationData,
            areAllDetailsCorrect: event.detail.value
        };
    }

    handleRemarksChange(event) {
        this.operationData = {
            ...this.operationData,
            remarks: event.target.value
        };
    }

    // ── Vehicle Detail handlers ────────────────────────────────────────────
    handleVehicleRadioChange(event) {
        const field = event.target.dataset.field;
        const v     = event.target.value;
        this.vehicleDetails = {
            ...this.vehicleDetails,
            [field]:     v,
            showDetails: field === 'delivery' ? v === 'Yes' : this.vehicleDetails.showDetails
        };
    }

    handleVehicleInputChange(event) {
        this.vehicleDetails = { ...this.vehicleDetails, [event.target.dataset.field]: event.target.value };
    }

    handleLienChange(event) {
        const v = event.target.value;
        this.vehicleDetails = {
            ...this.vehicleDetails,
            lienMarked:         v,
            markedOn:           v !== 'Yes' ? '' : this.vehicleDetails.markedOn,
            nowLienInTheNameOf: v !== 'Yes' ? '' : this.vehicleDetails.nowLienInTheNameOf
        };
        this.isMarkedOnDisabled = v !== 'Yes';
        this.isLienNameDisabled = v !== 'Yes';
    }

    // ── Disbursement handlers ──────────────────────────────────────────────
    handleDisbursementChange(event) {
        this.disbursement         = { ...this.disbursement, [event.target.dataset.field]: event.target.value };
        this.disbursementModified = true;
    }

    handleEmiDateChange(event) {
        this.disbursement         = { ...this.disbursement, firstEmiDueDate: event.detail.value };
        this._firstEmiDateStr     = '';  // clear stored date — user picked a new day
        this.disbursementModified = true;
    }

    // ── Installment Schedule ───────────────────────────────────────────────
    async handleInstallmentSchedule() {
        this.integrationStages            = ['Offer Engine API'];
        this.integrationStatus            = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.integrationSuccessMessage    = '';
        this.showIntegrationModal         = true;
        try {
            this.isLoading = true;
            const scheduleCreated = await this._createRepaymentScheduleRecords();
            if (scheduleCreated) {
                this.integrationCurrentStageIndex = 1;
                this.showIntegrationModal = false;
                this._openInstallmentScheduleModal();
            }
        } finally {
            this.isLoading = false;
        }
    }

    async _createRepaymentScheduleRecords() {
        try {
            const result = await createRepaymentSchedule({
                jsonData: JSON.stringify({
                    applicationId: this.recordId,
                    loanAmount: null,
                    interestRate: null,
                    tenure: null,
                    emiAmount: null,
                    installmentType: null,
                    firstEmiDate: null
                })
            });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.message || 'Error while creating Repayment Schedule records', 'error');
                return false;
            }
            return true;
        } catch (error) {
            this.showToast('Error', 'Error while creating Repayment Schedule records', 'error');
            return false;
        }
    }

    _openInstallmentScheduleModal() {
        this.dynamicComponentName  = 'installmentSchedue';
        this.dynamicComponentProps = { recordId: this.recordId, fromPaymentRequest: true };
        this.showDynamicModal      = true;
    }

    // ── Beneficiary handlers ───────────────────────────────────────────────
    handleBeneficiaryChange(event) {
        const i    = parseInt(event.target.dataset.index, 10);
        const rows = [...this.beneficiaryRows];
        rows[i]    = { ...rows[i], [event.target.dataset.field]: event.target.value };
        this.beneficiaryRows = rows;
    }

    handleAddBeneficiary() {
        if (this.beneficiaryRows.length >= 4) { this.showToast('Info', "Maximum 4 beneficiary rows allowed", 'info'); return; }
        this.beneficiaryRows = [...this.beneficiaryRows, { id: this.beneficiaryRows.length + 1, name: '', accountNumber: '', ifscCode: '', amount: '', verified: false }];
    }

    handleRemoveBeneficiary(event) {
        const i = parseInt(event.currentTarget.dataset.index, 10);
        if (!isNaN(i)) this.beneficiaryRows = this.beneficiaryRows.filter((_, idx) => idx !== i);
    }

    handleVerifyBeneficiary(event) {
        const i = parseInt(event.currentTarget.dataset.index, 10);
        if (isNaN(i)) return;
        const row = this.beneficiaryRows[i];
        if (!row?.accountNumber || !row?.ifscCode) {
            this.showToast('Warning', 'Please enter account number and IFSC code before verifying', 'warning');
            return;
        }
        this._verifyingRowIndex           = i;
        this.integrationStages            = ['IFSC API', 'Penny Drop API'];
        this.integrationStatus            = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.showIntegrationModal         = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.integrationCurrentStageIndex = 1;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.integrationCurrentStageIndex = 2;
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.showIntegrationModal = false;
                    const rows = [...this.beneficiaryRows];
                    rows[this._verifyingRowIndex] = { ...rows[this._verifyingRowIndex], verified: true };
                    this.beneficiaryRows      = rows;
                    this._verifyingRowIndex   = null;
                }, 600);
            }, 2000);
        }, 2000);
    }

    // ── Adjustment handlers ────────────────────────────────────────────────
    handleAdjustmentChange(event) {
        const i    = parseInt(event.target.dataset.index, 10);
        const rows = [...this.adjustmentRows];
        rows[i]    = { ...rows[i], [event.target.dataset.field]: event.target.value };
        this.adjustmentRows = rows;
    }

    handleAddAdjustment() {
        if (this.adjustmentRows.length >= 8) { this.showToast('Info', "Maximum 8 adjustment rows allowed", 'info'); return; }
        this.adjustmentRows = [...this.adjustmentRows, { id: this.adjustmentRows.length + 1, dealNumber: '', customerName: '', customerCode: '', amount: '', verified: false }];
    }

    handleRemoveAdjustment(event) {
        const i = parseInt(event.currentTarget.dataset.index, 10);
        if (!isNaN(i)) this.adjustmentRows = this.adjustmentRows.filter((_, idx) => idx !== i);
    }

    handleVerifyAdjustment(event) {
        const i   = parseInt(event.currentTarget.dataset.index, 10);
        if (isNaN(i)) return;
        const row = this.adjustmentRows[i];
        if (!row.dealNumber?.trim()) { this.showToast('Validation', 'Please enter a Deal Number before verifying', 'warning'); return; }
        const isDuplicate = this.adjustmentRows.some((adj, idx) => idx !== i && adj.verified && adj.dealNumber === row.dealNumber.trim());
        if (isDuplicate) { this.showToast('Validation', 'This Deal Number is already verified in another row', 'warning'); return; }

        this._verifyingAdjustmentIndex    = i;
        this.integrationStages            = ['Customer Name Search API'];
        this.integrationStatus            = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.showIntegrationModal         = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.integrationCurrentStageIndex = 1;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.showIntegrationModal = false;
                const rows = [...this.adjustmentRows];
                rows[this._verifyingAdjustmentIndex] = { ...rows[this._verifyingAdjustmentIndex], customerName: `Customer - ${row.dealNumber}`, verified: true };
                this.adjustmentRows            = rows;
                this._verifyingAdjustmentIndex = null;
            }, 600);
        }, 2000);
    }

    // ── Integration / Dynamic modal handlers ─────────────────────────────
    handleIntegrationModalClose() {
        this.showIntegrationModal = false;
    }

    handleModalClose() {
        this.showDynamicModal      = false;
        this.dynamicComponentProps = {};
        if(this.dynamicComponentName === 'installmentSchedue') {
            this.disbursementModified = false;
        }
        this.dynamicComponentName  = '';

    }

    get dynamicModalHeader() {
        return this.dynamicComponentName === 'installmentSchedue' ? 'Installment Schedule' : '';
    }

    // ── Seller Bank Details handlers ──────────────────────────────────────
    handleSellerBankChange(event) {
        this.sellerBankDetails = { ...this.sellerBankDetails, [event.target.dataset.field]: event.target.value };
    }

    handleVerifySellerBank() {
        if (!this.sellerBankDetails.bankName || !this.sellerBankDetails.accountNumber || !this.sellerBankDetails.ifscCode) {
            this.showToast('Warning', 'Please fill bank name, account number and IFSC code before verifying', 'warning');
            return;
        }
        this.integrationStages            = ['IFSC API', 'Penny Drop API'];
        this.integrationStatus            = 'loading';
        this.integrationCurrentStageIndex = 0;
        this.showIntegrationModal         = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.integrationCurrentStageIndex = 1;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.integrationCurrentStageIndex = 2;
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.showIntegrationModal = false;
                    this.sellerBankDetails    = { ...this.sellerBankDetails, ifscVerified: true, branchName: 'Main Branch', bankBranchCity: 'Mumbai', verified: true };
                }, 600);
            }, 2000);
        }, 2000);
    }

    // ── Submit ─────────────────────────────────────────────────────────────
    async handleSubmit() {
        if (this.isOperationsStage) {
            await this.submitDetailsOperations();
            return;
        }

        // Validation 1: Disbursement modified — must re-run installment schedule
        if (this.disbursementModified) {
            this.showToast('Re-run Required',
                'Please re-run offer engine by clicking Installment Schedule btn as you have updated Disbursement section',
                'warning');
            return;
        }

        this.beneficiaryRows = this.beneficiaryRows.length > 1 ? this.beneficiaryRows.filter(r => r.verified) : this.beneficiaryRows;
        this.adjustmentRows = this.adjustmentRows.length > 1 ? this.adjustmentRows.filter(r => r.verified) : this.adjustmentRows;

        // Validation 2: At least one beneficiary row must be filled
        const validBeneficiary = this.beneficiaryRows.some(r => r.name?.trim() && r.accountNumber?.trim() && r.amount && r.ifscCode?.trim() && r.verified);
        if (!validBeneficiary) {
            this.showToast('Validation', 'At least one beneficiary row with Name, Account Number and Amount is required', 'warning');
            return;
        }

        let adjustmentToCreate = this.adjustmentRows.filter(r => r.verified);

        try {
            this.isLoading = true;
            const result = await savePageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: 'savePaymentRequest',
                recordId:       this.recordId,
                params: {
                    ...this._assetScopeParams(),
                    businessPayment: this.businessPayment,
                    vehicleDetails:  this.vehicleDetails,
                    disbursement:    this.disbursement,
                    beneficiaryRows: this.beneficiaryRows,
                    adjustmentRows:  adjustmentToCreate
                }
            });
            if (result.success) {
                // Show integration modal: NPA Check → PACT API
                this.integrationStages                = ['NPA Check API'];
                this.integrationStatus                = 'loading';
                this.integrationCurrentStageIndex     = 0;
                this.integrationSuccessMessage        = 'Payment request submitted successfully';
                this.showIntegrationModal             = true;

                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(async () => {
                    this.integrationCurrentStageIndex = 1;
                    this.disableAllFields = true;
                    this.showIntegrationModal = false;
                    this.showToast('Success', 'Payment request submitted successfully', 'success');
                    if (this.fromAssetList) {
                        await this._completeAssetListPaymentRequest();
                    }
                }, 1500);
            } else {
                this.showToast('Error', result.message || 'Submit failed', 'error');
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Submit failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    validateForSubmitOperations() {
        if (!this.operationData.areAllDetailsCorrect) {
            this.showToast('Error', 'Are all details correct?', 'error');
            return false;
        }
        if (!this.operationData.remarks?.trim()) {
            this.showToast('Error', 'Remarks is required', 'error');
            return false;
        }
        return true;
    }

    async submitDetailsOperations() {
        if (!this.validateForSubmitOperations()) {
            return;
        }

        if (this.operationData.areAllDetailsCorrect !== 'Yes') {
            try {
                this.isLoading = true;
                const result = await savePageData({
                    apexClassName:  APEX_CLASS,
                    apexMethodName: MOVE_BACK_TO_PSS_STAGE,
                    recordId:       this.recordId,
                    params: {
                        applicationId: this.recordId,
                        ...this._assetScopeParams(),
                        areAllDetailsCorrect: this.operationData.areAllDetailsCorrect,
                        remarks: this.operationData.remarks
                    }
                });
                if (!result.success) {
                    this.showToast('Error', result.message || 'Submit failed', 'error');
                    return;
                }
                
                this.showToast('Success', 'Stage moved back to Post Sanction', 'success');
                window.dispatchEvent(new CustomEvent(LOS_MENU_REFRESH_EVENT, { bubbles: true, composed: true }));
            } catch (error) {
                this.showToast('Error', error.body?.message || 'Submit failed', 'error');
            } finally {
                this.isLoading = false;
            }
            return;
        }

        try {
            this.isLoading = true;
            const result = await savePageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: 'savePaymentRequest',
                recordId:       this.recordId,
                params: {
                    ...this._assetScopeParams(),
                    operationData: {
                        areAllDetailsCorrect: this.operationData.areAllDetailsCorrect,
                        remarks: this.operationData.remarks
                    },
                    businessPayment: null,
                    vehicleDetails:  null,
                    disbursement:    null,
                    beneficiaryRows: null,
                    adjustmentRows:  null
                }
            });
            if (!result.success) {
                this.showToast('Error', result.message || 'Failed to save', 'error');
                return;
            }

            if (result.success) {
                // Show integration modal: NPA Check → PACT API
                this.integrationStages                = ['NPA Check API', 'PACT API'];
                this.integrationStatus                = 'loading';
                this.integrationCurrentStageIndex     = 0;
                this.integrationSuccessMessage        = 'Payment request submitted successfully';
                this.showIntegrationModal             = true;

                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.integrationCurrentStageIndex = 1;
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(async () => {
                        this.integrationCurrentStageIndex = 2;
                        this.disableAllFields = true;
                        this.showIntegrationModal = false;
                        this.showToast('Success', 'Payment request submitted successfully', 'success');
                        if (this.fromAssetList) {
                            await this._completeAssetListPaymentRequest();
                        }
                    }, 1500);
                }, 1500);
            } else {
                this.showToast('Error', result.message || 'Submit failed', 'error');
            }

        } catch (error) {
            this.showToast('Error', error.body?.message || 'Submit failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async _completeAssetListPaymentRequest() {
        if (!this.applicationLineItemId) {
            this.showToast('Error', 'Application line item is missing. Please go back and reopen the asset.', 'error');
            return;
        }

        try {
            const result = await markPaymentRequestStageComplete({
                applicationLineItemId: this.applicationLineItemId,
                currentViewId: this.currentViewId || null,
                assetId: this.assetId || null
            });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.message || 'Unable to complete payment request for this asset.', 'error');
                return;
            }
            this.returnToAssetList(true);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Unable to complete payment request for this asset.', 'error');
        }
    }

    returnToAssetList(saved) {
        this.dispatchEvent(
            new CustomEvent('detailcomplete', {
                detail: {
                    lineItemId: this.applicationLineItemId || null,
                    saved
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleNext() {
        if (this._isStagePast && this.fromAssetList) {
            this.returnToAssetList(false);
            return;
        }
        window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: true, message: 'Processing...' } }));
        window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
            detail: {
                currentViewId:            this.currentViewId,
                id:                       this.recordId,
                currentLoanStageComplete: this.tab || STAGE_PAYMENT_REQUEST,
                currentStagePhrase:       this.stagePhrase || ''
            },
            bubbles: true,
            composed: true
        }));
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } })); }, 1500);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}