import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPageData  from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';
import markIhmStageComplete from '@salesforce/apex/WheelsIhmController.markIhmStageComplete';

const APEX_CLASS           = 'WheelsIhmController';
const LOS_NEXT_STAGE_EVENT = 'losnextstage';
const STAGE_IHM            = 'IHM';
const MOVE_BACK_TO_PSS_STAGE = 'moveBackToPssStage';
const LOS_MENU_REFRESH_EVENT = 'losmenurefresh';

export default class WheelsIhmPage extends LightningElement {

    @api recordId;
    @api currentViewId;
    @api applicationLineItemId = '';
    @api assetId = '';
    @track isLoading = false;
    @api stagePhrase = '';
    @api tab = '';
    @api fromAssetList = false;

    _isStagePast = false;
    @api
    get isStagePast() { return this._isStagePast; }
    set isStagePast(value) { this._isStagePast = !!value; }

    @track disableAllFields = false;
    get isReadOnly() { return this._isStagePast || this.disableAllFields || this.isOperationsStage; }
    get isOpsReadOnly() { return this._isStagePast || this.disableAllFields; }

    /** Read-only review mode — use readonly (not disabled) so field values stay legible. */
    get rootLayoutClass() {
        return `form-page-layout${this.isReadOnly || this.isOpsReadOnly ? ' form-page-readonly' : ''}`;
    }
    get nextButtonDisabled() { return (!this.isReadOnly && !this.isOperationsStage) || (!this.isOpsReadOnly && this.isOperationsStage) }
    get isNewVehicleType() { console.log('vehicleType', this.ihmData?.vehicleType); return this.ihmData?.vehicleType == 'New'; }

    yesNoOptions = [
        { label: 'Yes', value: 'Yes', circleClass: 'ihm-radio-circle' },
        { label: 'No', value: 'No', circleClass: 'ihm-radio-circle' }
    ];

    @track ihmData = {
        // Pay-ins (New & Used/Ref)
        serviceCharges:    '₹5,000',
        tradeCertificate:  '₹1,500',
        documentationCharges: '₹2,000',
        dueDateShiftCharges:  '₹500',
        stampingCharges:   '₹1,000',
        totalPayIns:       '₹10,000',

        // IHM Calculation (New)
        loanAmtSanctionedFexclFundInsu: '₹7,50,000',
        totalAmountToBePaid:    '₹1,70,000',
        totalAmountPaidToBank:  '₹50,000',
        totalAmountPaidToDealer:'₹0',
        doesCustomerNeedToPay:  'Yes',
        additionalIhmAmount:    '₹1,20,000',
        remarks: '',

        // IHM Calculation (Used/Ref)
        totalNonFundedInsurance:          '₹63,000',
        totalEmiToBeConsideredForIhm:     '₹31,000',
        valuationCharge:                  '₹5,000',
        valuationChargePaidBy:            '',
        totalMarginMoneyToBeDeductedForIhm: '₹1,04,000',
        areAllDetailsCorrect:             '',
        vehicleType:                        '',
    };

    @track dealerPaymentRows = [];
    @track showFilePreviewer         = false;
    @track previewContentDocumentId  = null;
    @track previewFileType           = null;

    valuationChargePaidByOptions = [
        { label: 'IBL',      value: 'IBL' },
        { label: 'Customer', value: 'Customer' }
    ];

    // ihmId is set after first save so subsequent submits do an update
    _ihmId = null;

    // ── Lifecycle ──────────────────────────────────────────────────────────
    connectedCallback() {
        if (this.fromAssetList && !this.assetId) {
            return;
        }
        this.loadPage();
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

    get isOperationsStage() { return this.tab === 'IHM' && this.currentViewId === 'Wheels_IHM_OPS'; }

    // ── Getters ────────────────────────────────────────────────────────────
    get showTable() { return this.dealerPaymentRows.length > 0; }

    get disableSubmitButton() { return (this.isOperationsStage && this.isOpsReadOnly) || (!this.isOperationsStage && this.isReadOnly); }

    _computeTotalAmountToBePaid() {
        return this.removeCurrencyFormat(this.ihmData?.loanAmtSanctionedFexclFundInsu)
            + this.removeCurrencyFormat(this.ihmData?.totalPayIns)
            - this.removeCurrencyFormat(this.ihmData?.totalAmountPaidToDealer);
    }

    get totalAmountToBePaid() {
        return this._fmt(this._computeTotalAmountToBePaid());
    }

    removeCurrencyFormat(value) {
        const parsed = this._parseAmount(value);
        return parsed == null ? 0 : parsed;
    }

    // ── Load IHM amounts + receipts in one call ────────────────────────────
    async loadPage() {
        if (!this.recordId) {
            return;
        }

        try {
            this.isLoading = true;
            this.disableAllFields = this._isStagePast;
            const page = await getPageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: 'loadIHMPage',
                recordId:       this.recordId,
                params:         this._assetScopeParams()
            });

            // ── IHM amounts ────────────────────────────────────────────────
            const d = page?.ihmData;
            if (d) {
                this._ihmId = d.ihmId || null;
                this.ihmData = {
                    ...this.ihmData,
                    serviceCharges:                     this._fmt(d.serviceCharges),
                    tradeCertificate:                   this._fmt(d.tradeCertificate),
                    documentationCharges:               this._fmt(d.documentationCharges),
                    dueDateShiftCharges:                this._fmt(d.dueDateShiftCharges),
                    stampingCharges:                    this._fmt(d.stampingCharges),
                    totalPayIns:                        this._fmt(d.totalPayIns),
                    totalAmountToBePaid:                this._fmt(d.totalAmountToBePaid),
                    totalAmountPaidToBank:              this._fmt(d.totalAmountPaidToBank),
                    totalAmountPaidToDealer:            this._fmt(d.totalAmountPaidToDealer),
                    doesCustomerNeedToPay:              d.doesCustomerNeedToPay || '',
                    additionalIhmAmount:                this._fmt(d.additionalIhmAmount),
                    remarks:                            d.remarks || '',
                    totalEmiToBeConsideredForIhm:       this._fmt(d.totalEmiToBeConsideredForIhm),
                    valuationCharge:                    this._fmt(d.valuationCharge),
                    valuationChargePaidBy:              d.valuationChargePaidBy || '',
                    totalMarginMoneyToBeDeductedForIhm: this._fmt(d.totalMarginMoneyToBeDeductedForIhm),
                    vehicleType:                        d.vehicleType || '',
                    areAllDetailsCorrect:               d.areAllDetailsCorrect || '',
                    loanAmtSanctionedFexclFundInsu :    this._fmt(d.loanAmtSanctionedFexclFundInsu)
                };
            }

            // ── Receipt rows ───────────────────────────────────────────────
            const rows = page?.receipts || [];
            this.dealerPaymentRows = rows.map((r, i) => ({
                id:               r.documentId || `loaded-${i}`,
                receiptNo:        r.receiptNo   || '',
                receiptDate:      r.receiptDate || '',
                amount:           r.amount      || '',
                remarks:          r.remarks     || '',
                documentId:       r.documentId,
                contentDocumentId:r.contentDocumentId || '',
                fileType:         r.fileType    || '',
                isUploaded:       r.isUploaded  || false,
                hasPendingFile:   false,
                pendingFileName:  '',
                pendingFileBase64:'',
                hasError:         false,
                rowClass:         'ihm-table-row'
            }));
            this.ihmData.totalAmountPaidToDealer = this.calculateTotalAmount();

            if (!this._isStagePast && d?.areAllDetailsCorrect) {
                this.disableAllFields = true;
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to load page data', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Format a numeric value as ₹ currency string
    _fmt(value) {
        if (value == null || value === '') return '₹0';
        const n = parseFloat(value);
        if (isNaN(n)) return '₹0';
        return '₹' + n.toLocaleString('en-IN');
    }

    // Strip ₹ formatting and return a plain number (or null)
    _parseAmount(val) {
        if (val == null || val === '') return null;
        const n = parseFloat(String(val).replace(/[₹,\s]/g, ''));
        return isNaN(n) ? null : n;
    }

    // ── Field change handlers ──────────────────────────────────────────────
    handleRemarksChange(event) {
        this.ihmData.remarks = event.target.value;
    }

    handleValuationChargePaidBy(event) {
        this.ihmData.valuationChargePaidBy = event.target.value;
    }

    // ── Dealer Payment Table — Add / Delete Row ────────────────────────────
    handleAddRow() {
        if (this.dealerPaymentRows.length >= 5) {
            this.showToast('Info', "You can't add more than 5 rows", 'info');
            return;
        }
        // Local only — no Apex until Submit
        this.dealerPaymentRows = [...this.dealerPaymentRows, this._buildNewRow()];
    }

    _buildNewRow() {
        return {
            id:               `new-${Date.now()}`,
            receiptNo:        '',
            receiptDate:      '',
            amount:           '',
            remarks:          '',
            documentId:       null,
            contentDocumentId:'',
            fileType:         '',
            isUploaded:       false,
            hasPendingFile:   false,
            pendingFileName:  '',
            pendingFileBase64:'',
            hasError:         false,
            rowClass:         'ihm-table-row'
        };
    }

    handleIsAllDetailsCorrectChange(event) {
        this.ihmData.areAllDetailsCorrect = event.target.value;
    }

    handleDeleteRow(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const row   = this.dealerPaymentRows[index];
        if (row.documentId) {
            // Saved in DB — delete via Apex
            this._deleteFromDB(row.documentId, index, true);
        } else {
            // Local row — just remove
            this.dealerPaymentRows = this.dealerPaymentRows.filter((r, i) => i !== index);
            this.ihmData.totalAmountPaidToDealer = this.calculateTotalAmount();
        }
    }

    async _deleteFromDB(documentId, index, isDeleteRow) {
        try {
            this.isLoading = true;
            const result = await savePageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: 'deleteDocumentAndContent',
                recordId:       this.recordId,
                params:         { documentId, isDeleteRow }
            });
            if (result.isSuccess) {
                if (isDeleteRow) {
                    this.dealerPaymentRows = this.dealerPaymentRows.filter((r, i) => i !== index);
                    this.ihmData.totalAmountPaidToDealer = this.calculateTotalAmount();
                } else {
                    const updated = [...this.dealerPaymentRows];
                    updated[index] = {
                        ...updated[index],
                        isUploaded: false, contentDocumentId: '', fileType: ''
                    };
                    this.dealerPaymentRows = updated;
                }
                this.showToast('Success', isDeleteRow ? 'Row deleted' : 'File removed', 'success');
            } else {
                this.showToast('Error', result.message || 'Delete failed', 'error');
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Delete failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Receipt field changes ──────────────────────────────────────────────
    handleIHMReceiptChange(event) {
        const index     = parseInt(event.target.dataset.index, 10);
        const fieldName = event.target.name;
        const value     = event.target.value;

        const updated = [...this.dealerPaymentRows];
        updated[index] = { ...updated[index], [fieldName]: value, hasError: false, rowClass: 'ihm-table-row' };

        if (fieldName === 'receiptDate') {
            const entered = new Date(value);
            const today   = new Date();
            today.setHours(23, 59, 59, 999);
            if (entered > today) {
                this.showToast('Error', 'Receipt date cannot be a future date', 'error');
                updated[index] = { ...updated[index], receiptDate: '' };
            }
        }
        if (fieldName === 'amount' && value <= 0) {
            this.showToast('Error', 'Amount must be greater than 0', 'error');
            updated[index] = { ...updated[index], amount: '' };
        }

        this.dealerPaymentRows = updated;
        this.ihmData.totalAmountPaidToDealer = this.calculateTotalAmount();
    }

    calculateTotalAmount() {
        const total = this.dealerPaymentRows.reduce((sum, r) => sum + (parseFloat(r.amount) || 0), 0);
        return '₹' + total.toLocaleString('en-IN');
    }

    // ── File — Stage in memory (no Apex until Submit) ──────────────────────
    handleUploadReceipt(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const input = document.createElement('input');
        input.type  = 'file';
        input.accept = '.pdf,.jpg,.jpeg,.png';
        input.style.display = 'none';
        input.addEventListener('change', (e) => {
            const file = e.target.files[0];
            if (file) this._stageFile(file, index);
        });
        document.body.appendChild(input);
        input.click();
        document.body.removeChild(input);
    }

    async _stageFile(file, index) {
        try {
            if (file.size > 10 * 1024 * 1024) {
                this.showToast('Error', 'File size must be less than 10 MB', 'error');
                return;
            }
            const allowed = ['application/pdf', 'image/jpeg', 'image/jpg', 'image/png'];
            if (!allowed.includes(file.type)) {
                this.showToast('Error', 'Only PDF, JPG, and PNG files are allowed', 'error');
                return;
            }
            this.isLoading = true;
            const base64 = await this.toBase64(file);
            const updated = [...this.dealerPaymentRows];
            updated[index] = {
                ...updated[index],
                hasPendingFile:    true,
                pendingFileName:   file.name,
                pendingFileBase64: base64
            };
            this.dealerPaymentRows = updated;
        } catch (error) {
            this.showToast('Error', 'Failed to read file', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleRemovePendingFile(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const updated = [...this.dealerPaymentRows];
        updated[index] = {
            ...updated[index],
            hasPendingFile: false, pendingFileName: '', pendingFileBase64: ''
        };
        this.dealerPaymentRows = updated;
    }

    // ── File — View / Delete already-uploaded file ─────────────────────────
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

    handleDeleteFile(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const row   = this.dealerPaymentRows[index];
        if (row.documentId && row.isUploaded) {
            // Saved file — remove from DB but keep the row
            this._deleteFromDB(row.documentId, index, false);
        } else if (row.hasPendingFile) {
            // Staged file — just clear from memory
            const updated = [...this.dealerPaymentRows];
            updated[index] = {
                ...updated[index],
                hasPendingFile: false, pendingFileName: '', pendingFileBase64: ''
            };
            this.dealerPaymentRows = updated;
        }
    }

    handleFilePreviewClose() {
        this.showFilePreviewer        = false;
        this.previewContentDocumentId = null;
        this.previewFileType          = null;
    }

    toBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload  = () => resolve(reader.result.split(',')[1]);
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    // ── Submit — save IHM amounts + receipt rows + pending files ──────────
    async handleSubmit() {

        let payload = {
            ihmId:                              this._ihmId,
            ...this._assetScopeParams(),
            serviceCharges:                     this._parseAmount(this.ihmData.serviceCharges),
            tradeCertificate:                   this._parseAmount(this.ihmData.tradeCertificate),
            documentationCharges:               this._parseAmount(this.ihmData.documentationCharges),
            dueDateShiftCharges:                this._parseAmount(this.ihmData.dueDateShiftCharges),
            stampingCharges:                    this._parseAmount(this.ihmData.stampingCharges),
            totalPayIns:                        this._parseAmount(this.ihmData.totalPayIns),
            totalAmountToBePaid:                this._computeTotalAmountToBePaid(),
            totalAmountPaidToBank:              this._parseAmount(this.ihmData.totalAmountPaidToBank),
            totalAmountPaidToDealer:            this._parseAmount(this.ihmData.totalAmountPaidToDealer),
            doesCustomerNeedToPay:              this.ihmData.doesCustomerNeedToPay,
            additionalIhmAmount:                this._parseAmount(this.ihmData.additionalIhmAmount),
            remarks:                            this.ihmData.remarks,
            totalEmiToBeConsideredForIhm:       this._parseAmount(this.ihmData.totalEmiToBeConsideredForIhm),
            valuationCharge:                    this._parseAmount(this.ihmData.valuationCharge),
            valuationChargePaidBy:              this.ihmData.valuationChargePaidBy,
            totalMarginMoneyToBeDeductedForIhm: this._parseAmount(this.ihmData.totalMarginMoneyToBeDeductedForIhm),
            areAllDetailsCorrect:               this.ihmData.areAllDetailsCorrect,
            receipts: this.isOperationsStage ? null : this.dealerPaymentRows.map((r, i) => ({
                rowIndex:    i,
                documentId:  r.documentId || null,
                receiptNo:   r.receiptNo,
                receiptDate: r.receiptDate,
                amount:      r.amount,
                remarks:     r.remarks
            }))
        }
        if(this.isOperationsStage){
            await this.submitDetailsOperations(payload);
        } else {
            await this.submitDetails(payload);
        }
    }

    async submitDetails(payload){
        if (!this.validateForSubmit()) return;
        try {
            this.isLoading = true;

            // 1. Save IHM amounts + receipt rows in one call
            const saveResult = await savePageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: 'saveIHMPage',
                recordId:       this.recordId,
                params: payload
            });

            if (!saveResult.success) {
                this.showToast('Error', saveResult.message || 'Failed to save', 'error');
                return;
            }
            this._ihmId = saveResult.ihmId;

            // Build rowIndex → documentId map for file uploads
            const docIdByIndex = {};
            (saveResult.receipts || []).forEach(r => { docIdByIndex[r.rowIndex] = r.documentId; });

            // 2. Upload any pending files
            for (let i = 0; i < this.dealerPaymentRows.length; i++) {
                const row = this.dealerPaymentRows[i];
                if (!row.hasPendingFile) continue;
                const documentId = docIdByIndex[i] || row.documentId;
                if (!documentId) continue;

                // eslint-disable-next-line no-await-in-loop
                const uploadResult = await savePageData({
                    apexClassName:  APEX_CLASS,
                    apexMethodName: 'createContentVersion',
                    recordId:       this.recordId,
                    params: {
                        title:            row.pendingFileName,
                        pathOnClient:     row.pendingFileName,
                        versionData:      row.pendingFileBase64,
                        documentRecordId: documentId
                    }
                });
                if (!uploadResult.isSuccess) {
                    this.showToast('Warning', `Row ${i + 1}: file upload failed — ${uploadResult.message}`, 'warning');
                }
            }

            // 3. Reload everything from DB
            await this.loadPage();
            this.disableAllFields = true;
            this.showToast('Success', 'IHM submitted successfully', 'success');
            if (this.fromAssetList) {
                await this._completeAssetListIhm();
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Submit failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Validation ─────────────────────────────────────────────────────────
    validateForSubmit() {
        if (!this.ihmData.valuationChargePaidBy && !this.isNewVehicleType) {
            this.showToast('Error', 'Valuation charges paid by is required', 'error');
            return false;
        }
        if (this.dealerPaymentRows.length === 0 && this.isNewVehicleType) {
            this.showToast('Error', 'At least one receipt row is required', 'error');
            return false;
        }

        let isValid = true;
        if(this.isNewVehicleType){
        const updated = this.dealerPaymentRows.map((row, i) => {
            const missing = [];
            if (!row.isUploaded && !row.hasPendingFile) missing.push('Upload Receipt');
            if (!String(row.receiptNo  || '').trim()) missing.push('IHM Receipt No');
            if (!row.receiptDate)                     missing.push('IHM Receipt Date');
            if (row.amount === '' || row.amount == null) missing.push('IHM Amount');
            if (!String(row.remarks   || '').trim()) missing.push('Remarks');

            if (missing.length > 0) {
                this.showToast(`Row ${i + 1} — Missing fields`, missing.join(', '), 'error');
                isValid = false;
            }
            return {
                ...row,
                hasError: missing.length > 0,
                rowClass: missing.length > 0 ? 'ihm-table-row ihm-table-row-error' : 'ihm-table-row'
                };
            });
            this.dealerPaymentRows = updated;
        }
        return isValid;
    }

    async submitDetailsOperations(payload){
        if (!this.validateForSubmitOperations()) return;
        if(this.ihmData.areAllDetailsCorrect != 'Yes'){
            this.isLoading = true;
            const result = await savePageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: MOVE_BACK_TO_PSS_STAGE,
                recordId:       this.recordId,
                params: {
                    applicationId: this.recordId,
                    ...this._assetScopeParams(),
                    areAllDetailsCorrect : this.ihmData.areAllDetailsCorrect,
                    remarks: this.ihmData.remarks
                }
            });
            if(!result.success){
                this.showToast('Error', result.message || 'Submit failed', 'error');
                return;
            }
            this.showToast('Success', 'Stage moved back to Post Sanction', 'success');
            this.isLoading = false;
            window.dispatchEvent(new CustomEvent(LOS_MENU_REFRESH_EVENT, { bubbles: true, composed: true }));
            return;
        }
        try {
            this.isLoading = true;
            console.log('submitDetailsOperations', JSON.stringify(payload));
            const saveResult = await savePageData({
                apexClassName:  APEX_CLASS,
                apexMethodName: 'saveIHMPage',
                recordId:       this.recordId,
                params: payload
            });
            if (!saveResult.success) {
                this.showToast('Error', saveResult.message || 'Failed to save', 'error');
                return;
            }
            this.disableAllFields = true;
            this.showToast('Success', 'IHM submitted successfully', 'success');
            if (this.fromAssetList) {
                await this._completeAssetListIhm();
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Submit failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async _completeAssetListIhm() {
        if (!this.applicationLineItemId) {
            this.showToast('Error', 'Application line item is missing. Please go back and reopen the asset.', 'error');
            return;
        }

        try {
            const result = await markIhmStageComplete({
                applicationLineItemId: this.applicationLineItemId,
                currentViewId: this.currentViewId || null,
                assetId: this.assetId || null
            });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.message || 'Unable to complete IHM for this asset.', 'error');
                return;
            }
            this.returnToAssetList(true);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Unable to complete IHM for this asset.', 'error');
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

    validateForSubmitOperations(){
        if (!this.ihmData.areAllDetailsCorrect) {
            this.showToast('Error', 'Are all details correct?', 'error');
            return false;
        }
        if (!this.ihmData.remarks?.trim()) {
            this.showToast('Error', 'Remarks is required', 'error');
            return false;
        }
        return true;
    }

    // ── Next ───────────────────────────────────────────────────────────────
    handleNext() {
        window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: true, message: 'Processing...' } }));
        window.dispatchEvent(new CustomEvent(LOS_NEXT_STAGE_EVENT, {
            detail: {
                currentViewId:            this.currentViewId,
                id:                       this.recordId,
                currentLoanStageComplete: this.tab || STAGE_IHM,
                currentStagePhrase:       this.stagePhrase || ''
            },
            bubbles: true,
            composed: true
        }));
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { window.dispatchEvent(new CustomEvent('losgloballoader', { detail: { show: false } })); }, 1500);
}

    // ── Toast ──────────────────────────────────────────────────────────────
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}