import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import LightningConfirm from 'lightning/confirm';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';
import sheetjs from '@salesforce/resourceUrl/sheetJS';
import FinanceGridTemplate from '@salesforce/resourceUrl/FinanceGridTemplate';
import formulas from './financeGridContentHelper';

const APEX_CLASS = 'FinanceGridController';
const ACTION_FETCH_FINANCIAL_PERFORMANCE_RECORDS = 'fetchFinancialPerformanceRecords';
const ACTION_SAVE_FINANCIAL_PERFORMANCE_RECORDS = 'saveFinancialPerformanceRecords';
const ACTION_SAVE_GST_RECORDS = 'saveGstRecords';
const ACTION_UPLOAD_FINANCIAL_PERFORMANCE_EXCEL = 'uploadFinancialPerformanceExcel';
const ACTION_DELETE_FINANCIAL_PERFORMANCE_EXCEL = 'deleteFinancialPerformanceExcel';
const MSG_DATA_SAVED_SUCCESS = 'Data Saved Successfully';

const FORM_26_CLIENT_LIMIT = 10;

const PNL_DROPDOWN_OPTIONS = [
    { label: 'Audited', value: 'Audited' },
    { label: 'Provisionals', value: 'Provisionals' },
    { label: 'Projections', value: 'Projections' }
];

const GST_MONTHS = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
];

/** Static grid layout **/
const GRID_METADATA = [
    { DeveloperName: 'PnL_Type', MasterLabel: 'Profit and Loss Account', Is_Section__c: false, Field_API_Name__c: 'Profit_and_Loss_Account__c', Datatype__c: 'dropdown', Order__c: 10 },
    { DeveloperName: 'CA_Member', MasterLabel: 'Signing CA Member No', Is_Section__c: false, Field_API_Name__c: 'Signing_CA_Member_No__c', Datatype__c: 'text', Order__c: 20 },
    { DeveloperName: 'UDIN', MasterLabel: 'UDIN No', Is_Section__c: false, Field_API_Name__c: 'UDIN_No__c', Datatype__c: 'text', Order__c: 30 },
    { DeveloperName: 'Sec_Income', MasterLabel: 'INCOME', Is_Section__c: true, Field_API_Name__c: null, Datatype__c: null, Order__c: 40 },
    { DeveloperName: 'Revenue', MasterLabel: 'Revenue from operations', Is_Section__c: false, Field_API_Name__c: 'Revenue_from_operations__c', Datatype__c: 'number', Order__c: 50 },
    { DeveloperName: 'Other_Income', MasterLabel: 'Other Income', Is_Section__c: false, Field_API_Name__c: 'Other_Income__c', Datatype__c: 'number', Order__c: 60 },
    { DeveloperName: 'Income', MasterLabel: 'Total Income', Is_Section__c: false, Field_API_Name__c: 'Income__c', Datatype__c: 'number', Order__c: 70 },
    { DeveloperName: 'Sec_Expenses', MasterLabel: 'EXPENSES', Is_Section__c: true, Field_API_Name__c: null, Datatype__c: null, Order__c: 80 },
    { DeveloperName: 'Cost_of_goods', MasterLabel: 'Cost of goods', Is_Section__c: false, Field_API_Name__c: 'Cost_of_goods__c', Datatype__c: 'number', Order__c: 90 },
    { DeveloperName: 'Direct_Expenses', MasterLabel: 'Direct Expenses', Is_Section__c: false, Field_API_Name__c: 'Direct_Expenses__c', Datatype__c: 'number', Order__c: 100 },
    { DeveloperName: 'Employee_costs', MasterLabel: 'Employee costs', Is_Section__c: false, Field_API_Name__c: 'Employee_costs__c', Datatype__c: 'number', Order__c: 110 },
    { DeveloperName: 'Administration_Expenses', MasterLabel: 'Administration Expenses', Is_Section__c: false, Field_API_Name__c: 'Administration_Expenses__c', Datatype__c: 'number', Order__c: 120 },
    { DeveloperName: 'Selling_Distribution', MasterLabel: 'Selling and Distribution Expenses', Is_Section__c: false, Field_API_Name__c: 'Selling_and_Distribution_Expenses__c', Datatype__c: 'number', Order__c: 130 },
    { DeveloperName: 'Financial_Expenses', MasterLabel: 'Financial Expenses', Is_Section__c: false, Field_API_Name__c: 'Financial_Expenses__c', Datatype__c: 'number', Order__c: 140 },
    { DeveloperName: 'Depreciation', MasterLabel: 'Depreciation', Is_Section__c: false, Field_API_Name__c: 'Depreciation__c', Datatype__c: 'number', Order__c: 150 },
    { DeveloperName: 'Expenses', MasterLabel: 'Total Expenses', Is_Section__c: false, Field_API_Name__c: 'Expenses__c', Datatype__c: 'number', Order__c: 160 },
    { DeveloperName: 'Sec_Profit', MasterLabel: 'PROFIT', Is_Section__c: true, Field_API_Name__c: null, Datatype__c: null, Order__c: 170 },
    { DeveloperName: 'PBT', MasterLabel: 'Profit before tax', Is_Section__c: false, Field_API_Name__c: 'Profit_before_tax__c', Datatype__c: 'number', Order__c: 180 },
    { DeveloperName: 'Provision_for_tax', MasterLabel: 'Provision for tax', Is_Section__c: false, Field_API_Name__c: 'Provision_for_tax__c', Datatype__c: 'number', Order__c: 190 },
    { DeveloperName: 'PAT', MasterLabel: 'Profit after tax', Is_Section__c: false, Field_API_Name__c: 'Profit_after_tax__c', Datatype__c: 'number', Order__c: 200 },
    { DeveloperName: 'Preference_dividend', MasterLabel: 'Preference dividend (including tax)', Is_Section__c: false, Field_API_Name__c: 'Preference_dividend_including_tax__c', Datatype__c: 'number', Order__c: 210 },
    { DeveloperName: 'Profit_avail_equity', MasterLabel: 'Profit available for equity shareholders', Is_Section__c: false, Field_API_Name__c: 'Profit_available_for_equity_shareholders__c', Datatype__c: 'number', Order__c: 220 },
    { DeveloperName: 'Cash_profit', MasterLabel: 'Cash Profit', Is_Section__c: false, Field_API_Name__c: 'Cash_profit__c', Datatype__c: 'number', Order__c: 230 },
    { DeveloperName: 'Sec_BS', MasterLabel: 'BALANCE SHEET', Is_Section__c: true, Field_API_Name__c: null, Datatype__c: null, Order__c: 240 },
    { DeveloperName: 'Sec_Liabilities', MasterLabel: 'LIABILITIES', Is_Section__c: true, Field_API_Name__c: null, Datatype__c: null, Order__c: 250 },
    { DeveloperName: 'Equity', MasterLabel: 'Equity Capital', Is_Section__c: false, Field_API_Name__c: 'Equity_Capital__c', Datatype__c: 'number', Order__c: 260 },
    { DeveloperName: 'Share_App_Money', MasterLabel: 'Share Application Money', Is_Section__c: false, Field_API_Name__c: 'Share_Application_Money__c', Datatype__c: 'number', Order__c: 270 },
    { DeveloperName: 'Reserves_Surplus', MasterLabel: 'Reserves & Surplus', Is_Section__c: false, Field_API_Name__c: 'Reserves_Surplus__c', Datatype__c: 'number', Order__c: 280 },
    { DeveloperName: 'Secured_loan', MasterLabel: 'Secured loan', Is_Section__c: false, Field_API_Name__c: 'Secured_loan__c', Datatype__c: 'number', Order__c: 290 },
    { DeveloperName: 'Secured_loans_OD', MasterLabel: 'Secured loans OD/CC Working Capital', Is_Section__c: false, Field_API_Name__c: 'Secured_loans_OD_CC_Working_Capital__c', Datatype__c: 'number', Order__c: 300 },
    { DeveloperName: 'Unsecured_loans', MasterLabel: 'Unsecured loans', Is_Section__c: false, Field_API_Name__c: 'Unsecured_loans__c', Datatype__c: 'number', Order__c: 310 },
    { DeveloperName: 'Deferred_tax', MasterLabel: 'Deffered tax liability', Is_Section__c: false, Field_API_Name__c: 'Deffered_tax_liability__c', Datatype__c: 'number', Order__c: 320 },
    { DeveloperName: 'Other_LTL', MasterLabel: 'Other long term liabilities', Is_Section__c: false, Field_API_Name__c: 'Other_long_term_liabilities__c', Datatype__c: 'number', Order__c: 330 },
    { DeveloperName: 'Current_Liab', MasterLabel: 'Current Liabilities and Provision', Is_Section__c: false, Field_API_Name__c: 'Current_Liabilities_and_Provision__c', Datatype__c: 'number', Order__c: 340 },
    { DeveloperName: 'Sundry_creditors', MasterLabel: 'Sundry creditors', Is_Section__c: false, Field_API_Name__c: 'Sundry_creditors__c', Datatype__c: 'number', Order__c: 350 },
    { DeveloperName: 'Other_CLP', MasterLabel: 'Other current liabilities and provisions', Is_Section__c: false, Field_API_Name__c: 'Other_current_liabilities_and_provisions__c', Datatype__c: 'number', Order__c: 360 },
    { DeveloperName: 'Liab_Total', MasterLabel: 'Liabilities Total', Is_Section__c: false, Field_API_Name__c: 'Liabilities_Total__c', Datatype__c: 'number', Order__c: 370 },
    { DeveloperName: 'Sec_Assets', MasterLabel: 'ASSETS', Is_Section__c: true, Field_API_Name__c: null, Datatype__c: null, Order__c: 380 },
    { DeveloperName: 'Fixed_Assets', MasterLabel: 'Fixed Assets', Is_Section__c: false, Field_API_Name__c: 'Fixed_Assets__c', Datatype__c: 'number', Order__c: 390 },
    { DeveloperName: 'Capital_WIP', MasterLabel: 'Capital WIP', Is_Section__c: false, Field_API_Name__c: 'Capital_WIP__c', Datatype__c: 'number', Order__c: 400 },
    { DeveloperName: 'Investments', MasterLabel: 'Investments', Is_Section__c: false, Field_API_Name__c: 'Investments__c', Datatype__c: 'number', Order__c: 410 },
    { DeveloperName: 'LT_loans_adv', MasterLabel: 'Long term loans and advances', Is_Section__c: false, Field_API_Name__c: 'Long_term_loans_and_advances__c', Datatype__c: 'number', Order__c: 420 },
    { DeveloperName: 'Other_NCA', MasterLabel: 'other non current assets', Is_Section__c: false, Field_API_Name__c: 'other_non_current_assets__c', Datatype__c: 'number', Order__c: 430 },
    { DeveloperName: 'Current_assets', MasterLabel: 'Current assets', Is_Section__c: false, Field_API_Name__c: 'Current_assets__c', Datatype__c: 'number', Order__c: 440 },
    { DeveloperName: 'Sundry_debtors', MasterLabel: 'Sundry debtors', Is_Section__c: false, Field_API_Name__c: 'Sundry_debtors__c', Datatype__c: 'number', Order__c: 450 },
    { DeveloperName: 'Closing_stock', MasterLabel: 'Closing stock', Is_Section__c: false, Field_API_Name__c: 'Closing_stock__c', Datatype__c: 'number', Order__c: 460 },
    { DeveloperName: 'Cash_bank', MasterLabel: 'Cash and Bank Balances', Is_Section__c: false, Field_API_Name__c: 'Cash_and_bank_balances__c', Datatype__c: 'number', Order__c: 470 },
    { DeveloperName: 'Other_CA', MasterLabel: 'Other current assets', Is_Section__c: false, Field_API_Name__c: 'Other_current_assets__c', Datatype__c: 'number', Order__c: 480 },
    { DeveloperName: 'Assets_Total', MasterLabel: 'Assets Total', Is_Section__c: false, Field_API_Name__c: 'Assets_Total__c', Datatype__c: 'number', Order__c: 490 },
    { DeveloperName: 'Sec_Ratios', MasterLabel: 'RATIOS', Is_Section__c: true, Field_API_Name__c: null, Datatype__c: null, Order__c: 500 },
    { DeveloperName: 'ROCE', MasterLabel: 'Return on Capital Employed', Is_Section__c: false, Field_API_Name__c: 'Return_on_Capital_Employed__c', Datatype__c: 'number', Order__c: 510 },
    { DeveloperName: 'ROSHF', MasterLabel: 'Return On Share Holders Fund', Is_Section__c: false, Field_API_Name__c: 'Return_On_Share_Holders_Fund__c', Datatype__c: 'number', Order__c: 520 },
    { DeveloperName: 'PAT_Income', MasterLabel: 'PAT / Income (%)', Is_Section__c: false, Field_API_Name__c: 'PAT_Income__c', Datatype__c: 'text', Order__c: 530 },
    { DeveloperName: 'PAT_Assets', MasterLabel: 'PAT / Assets employed (%)', Is_Section__c: false, Field_API_Name__c: 'PAT_Assets_employed__c', Datatype__c: 'text', Order__c: 540 },
    { DeveloperName: 'Face_Value', MasterLabel: 'Face Value of Shares', Is_Section__c: false, Field_API_Name__c: 'Face_Value_of_Shares__c', Datatype__c: 'number', Order__c: 550 },
    { DeveloperName: 'EPS', MasterLabel: 'EPS', Is_Section__c: false, Field_API_Name__c: 'EPS__c', Datatype__c: 'number', Order__c: 560 },
    { DeveloperName: 'Increase_TO', MasterLabel: 'Increase in TO', Is_Section__c: false, Field_API_Name__c: 'Increase_in_TO__c', Datatype__c: 'number', Order__c: 570 },
    { DeveloperName: 'Increase_Cash_Profit', MasterLabel: 'Increase in Cash Profit', Is_Section__c: false, Field_API_Name__c: 'Increase_in_Cash_Profit__c', Datatype__c: 'number', Order__c: 580 },
    { DeveloperName: 'Interest_Coverage', MasterLabel: 'Interest Coverage', Is_Section__c: false, Field_API_Name__c: 'Interest_Coverage__c', Datatype__c: 'number', Order__c: 590 },
    { DeveloperName: 'Debt_Ratio', MasterLabel: 'Debt Ratio', Is_Section__c: false, Field_API_Name__c: 'Debt_Ratio__c', Datatype__c: 'number', Order__c: 600 },
    { DeveloperName: 'Debt_Equity', MasterLabel: 'Debt Equity', Is_Section__c: false, Field_API_Name__c: 'Debt_Equity__c', Datatype__c: 'number', Order__c: 610 },
    { DeveloperName: 'Current_Ratio', MasterLabel: 'Current Ratio', Is_Section__c: false, Field_API_Name__c: 'Current_Ratio__c', Datatype__c: 'number', Order__c: 620 },
    { DeveloperName: 'Quick_Asset', MasterLabel: 'Quick Asset Ratio', Is_Section__c: false, Field_API_Name__c: 'Quick_Asset_Ratio__c', Datatype__c: 'number', Order__c: 630 },
    { DeveloperName: 'Cash_Ratio', MasterLabel: 'Cash Ratio', Is_Section__c: false, Field_API_Name__c: 'Cash_Ratio__c', Datatype__c: 'number', Order__c: 640 },
    { DeveloperName: 'TOL_TNW', MasterLabel: 'TOL/TNW', Is_Section__c: false, Field_API_Name__c: 'TOL_TNW__c', Datatype__c: 'number', Order__c: 650 },
    { DeveloperName: 'DSCR', MasterLabel: 'DSCR', Is_Section__c: false, Field_API_Name__c: 'DSCR__c', Datatype__c: 'number', Order__c: 660 },
    { DeveloperName: 'Debtors_TO', MasterLabel: 'Debtors / TO', Is_Section__c: false, Field_API_Name__c: 'Debtors_TO__c', Datatype__c: 'number', Order__c: 670 },
    { DeveloperName: 'Debtors_TO_Ratio', MasterLabel: 'Debtors / TO Ratio', Is_Section__c: false, Field_API_Name__c: 'Debtors_TO_Ratio__c', Datatype__c: 'number', Order__c: 680 },
    { DeveloperName: 'Debtor_days', MasterLabel: 'Debtor days', Is_Section__c: false, Field_API_Name__c: 'Debtor_days__c', Datatype__c: 'number', Order__c: 690 }
];

export default class FinanceGridContent extends LightningElement {
    @api recordId;
    @api loanId;

    isLoading = true;
    hasFYRecords = true;
    showGSTDetails = false;
    gstDetailsYearValue;
    selectedYear = '';
    selectedYearLabel = '';
    form26Total = 0;
    gstrTotal = 0;
    nextClientId = 2;
    limitForm26 = FORM_26_CLIENT_LIMIT;
    errorMessage = 'GST and 26AS sections appear after financial performance is saved.';

    @track years = [];
    @track gstYears = [];
    @track yearsWithFlags = [];
    @track sectionsWithFlags = [];
    @track financialPerformanceRecords = [];
    yearsMap = {};
    excelRowsApplied = 0;
    excelLibraryLoaded = false;
    excelFileUploaded = false;
    excelFileName = '';
    excelChecklistId = null;
    _pendingApplyToInputs = false;
    _pageToastTimer;

    showPageToast = false;
    pageToastTitle = '';
    pageToastMessage = '';
    pageToastVariant = 'info';

    clients = [{ Name_of_the_Client__c: '', Amount__c: '', Id: 1 }];
    gst3rRecords = GST_MONTHS.map((month) => ({ Month__c: month, Amount__c: '' }));

    get pageToastClass() {
        const classes = {
            success: 'fg-page-toast--success',
            error: 'fg-page-toast--error',
            warning: 'fg-page-toast--warning',
            info: 'fg-page-toast--info'
        };
        return `fg-page-toast slds-notify slds-notify_toast ${classes[this.pageToastVariant] || classes.info}`;
    }

    connectedCallback() {
        const applicationId = this.resolveApplicationId();
        if (applicationId) {
            this.recordId = applicationId;
        }

        this.generateYears();
        this.buildGridLayout();
        loadScript(this, sheetjs)
            .then(() => {
                this.excelLibraryLoaded = true;
            })
            .catch(() => {
                this.showToast('Error', 'Could not load Excel parser library.', 'error');
            });
        this.fetchRecords();
    }

    disconnectedCallback() {
        if (this._pageToastTimer) {
            clearTimeout(this._pageToastTimer);
        }
    }

    renderedCallback() {
        if (this._pendingApplyToInputs) {
            this._pendingApplyToInputs = false;
            this.applyRecordsToInputs();
        }
    }

    fetchRecords() {
        if (!this.recordId) {
            this.initializeFinancialYearSlots();
            this.isLoading = false;
            return Promise.resolve();
        }

        this.isLoading = true;
        return this.invokeReadAction(ACTION_FETCH_FINANCIAL_PERFORMANCE_RECORDS)
            .then((result) => {
                const records = this.normalizeFetchedRecords(result?.records || []);
                this.applyExcelDocumentFromFetch(result?.excelDocument);
                if (records.length) {
                    this.hasFYRecords = true;
                    this.loadRecordsFromApex(records);
                } else {
                    this.hasFYRecords = false;
                    this.initializeFinancialYearSlots();
                }
            })
            .catch((error) => {
                this.showToast('Error', this.reduceError(error), 'error');
                this.initializeFinancialYearSlots();
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    applyExcelDocumentFromFetch(excelDocument) {
        if (excelDocument?.found) {
            this.excelFileUploaded = true;
            this.excelFileName = excelDocument.fileName || 'Uploaded file';
            this.excelChecklistId = excelDocument.checklistId || null;
            return;
        }
        this.excelFileUploaded = false;
        this.excelFileName = '';
        this.excelChecklistId = null;
    }

    normalizeFetchedRecords(rawRecords) {
        return rawRecords.map((rec) => {
            const normalized = { ...rec };
            const gst = normalized.GST__r;
            if (gst && !Array.isArray(gst)) {
                normalized.GST__r = gst.records || [];
            }
            return normalized;
        });
    }

    findRecordForYear(recordsFromApex, year) {
        return recordsFromApex.find(
            (rec) => rec.Name === year || this.resolveYearKey(rec.Name) === year
        );
    }

    loadRecordsFromApex(recordsFromApex) {
        this.financialPerformanceRecords = this.years.map((year) => {
            const existing = this.findRecordForYear(recordsFromApex, year);
            if (existing) {
                const record = { ...existing };
                delete record.attributes;
                return { year, recordId: existing.Id, record };
            }
            return { year, recordId: null, record: { Name: year } };
        });

        this.refreshAuditedRowsFromRecords();
        this._pendingApplyToInputs = true;
    }

    applyRecordsToInputs() {
        this.financialPerformanceRecords.forEach((item) => {
            if (!item.record) {
                return;
            }
            Object.keys(item.record).forEach((key) => {
                if (key === 'Id' || key === 'attributes' || key === 'GST__r' || key === 'Application__c') {
                    return;
                }
                const value = item.record[key];
                const inputElement = this.template.querySelector(
                    `lightning-input[data-year="${item.year}"][data-field-api="${key}"], ` +
                        `lightning-combobox[data-year="${item.year}"][data-field-api="${key}"]`
                );
                if (inputElement && value !== undefined && value !== null && value !== '') {
                    inputElement.value = value;
                }
            });
        });
    }

    resolveApplicationId() {
        return this.recordId || this.loanId || new URLSearchParams(window.location.search).get('loanId');
    }

    getFinRecordForYear(year) {
        return this.financialPerformanceRecords.find((item) => item.year === year) || null;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    isSalesforceId(value) {
        const id = value != null ? String(value) : '';
        return id.length === 15 || id.length === 18;
    }

    getGstChildRecords(finRecord) {
        const gst = finRecord?.record?.GST__r;
        return Array.isArray(gst) ? gst : gst?.records || [];
    }

    isGstRecordType(gst, recordTypeName) {
        const devName = recordTypeName === 'Form 26 AS Credits' ? 'Form_26_AS_Credits' : 'GSTR_3B';
        return gst?.RecordType?.Name === recordTypeName || gst?.RecordType?.DeveloperName === devName;
    }

    syncGstPanelsFromDom() {
        const form26Inputs = this.template.querySelectorAll('lightning-input[data-id][data-field]');
        if (form26Inputs.length) {
            this.clients = this.clients.map((client) => {
                const key = String(client.Id);
                const nameInput = [...form26Inputs].find(
                    (el) => String(el.dataset.id) === key && el.dataset.field === 'name'
                );
                const amountInput = [...form26Inputs].find(
                    (el) => String(el.dataset.id) === key && el.dataset.field === 'amount'
                );
                return {
                    ...client,
                    Name_of_the_Client__c: nameInput ? nameInput.value : client.Name_of_the_Client__c,
                    Amount__c: amountInput ? amountInput.value : client.Amount__c
                };
            });
        }

        const gstrInputs = this.template.querySelectorAll('lightning-input[data-month]');
        if (gstrInputs.length) {
            this.gst3rRecords = this.gst3rRecords.map((row) => {
                const input = [...gstrInputs].find((el) => el.dataset.month === row.Month__c);
                return input ? { ...row, Amount__c: input.value } : row;
            });
        }
        this.updateGstTotals();
    }

    updateGstTotals() {
        this.form26Total = this.clients.reduce((sum, client) => {
            if (!client.Name_of_the_Client__c?.trim()) {
                return sum;
            }
            const amount = parseFloat(client.Amount__c);
            return Number.isNaN(amount) ? sum : sum + amount;
        }, 0);
        this.gstrTotal = this.gst3rRecords.reduce((sum, row) => {
            const amount = parseFloat(row.Amount__c);
            return Number.isNaN(amount) ? sum : sum + amount;
        }, 0);
    }

    getInputValue(event) {
        return event.detail?.value ?? event.target?.value ?? '';
    }

    buildForm26Payload(finRecordId) {
        return this.clients
            .filter((client) => client.Name_of_the_Client__c?.trim())
            .map((client) => {
                const payload = {
                    Name_of_the_Client__c: client.Name_of_the_Client__c.trim(),
                    Amount__c: parseFloat(client.Amount__c) || null,
                    Financial_Performance__c: finRecordId
                };
                if (this.isSalesforceId(client.Id)) {
                    payload.Id = String(client.Id);
                }
                return payload;
            });
    }

    buildGstrPayload(finRecordId) {
        return this.gst3rRecords
            .filter((row) => row.Month__c && !Number.isNaN(parseFloat(row.Amount__c)))
            .map((row) => {
                const payload = {
                    Month__c: row.Month__c,
                    Amount__c: parseFloat(row.Amount__c),
                    Financial_Performance__c: finRecordId
                };
                if (this.isSalesforceId(row.Id)) {
                    payload.Id = String(row.Id);
                }
                return payload;
            });
    }

    async saveGstPayload(records, recordType, financialPerformanceId) {
        const result = await this.invokeSaveAction(ACTION_SAVE_GST_RECORDS, {
            data: JSON.stringify(records),
            recordType,
            financialPerformanceId
        });
        return result?.gstRecords || [];
    }

    generateYears() {
        const currentYear = new Date().getFullYear();
        const currentYearLastTwoDigits = currentYear % 100;
        this.years = [];
        this.gstYears = [];

        for (let i = 1; i <= 5; i++) {
            const fyStart = currentYearLastTwoDigits - i;
            const fyEnd = currentYearLastTwoDigits - i + 1;
            const yearLabel = `FY${currentYear - i}`;
            this.years.push(yearLabel);
            this.gstYears.push({
                label: `FY${String(fyStart).padStart(2, '0')}-${String(fyEnd).padStart(2, '0')}`,
                value: yearLabel
            });
        }

        this.yearsWithFlags = this.years.map((label, index) => ({
            label,
            showSigning: false,
            isLatest: index === 0
        }));
    }

    buildGridLayout() {
        this.sectionsWithFlags = GRID_METADATA.map((sec) => {
            const api = sec.Field_API_Name__c;
            const isPnl = api === 'Profit_and_Loss_Account__c';
            const isSigner = api === 'Signing_CA_Member_No__c';
            const isUdin = api === 'UDIN_No__c';
            const isSection = sec.Is_Section__c === true || sec.Is_Section__c === 'true';

            return {
                ...sec,
                isDropdown: sec.Datatype__c === 'dropdown',
                options: sec.Datatype__c === 'dropdown' ? PNL_DROPDOWN_OPTIONS : null,
                isSection,
                isPnl,
                isSigner,
                isUdin,
                isDefaultRow: !isSection && !isPnl && !isSigner && !isUdin,
                showSignerRow: false,
                showUdinRow: false,
                sectionGapKey: `${sec.DeveloperName}_gap`,
                sectionKey: `${sec.DeveloperName}_section`,
                pnlKey: `${sec.DeveloperName}_pnl`,
                signerKey: `${sec.DeveloperName}_signer`,
                udinKey: `${sec.DeveloperName}_udin`,
                defaultKey: `${sec.DeveloperName}_default`
            };
        });
    }

    initializeFinancialYearSlots() {
        this.financialPerformanceRecords = this.years.map((year) => ({
            year,
            recordId: null,
            record: { Name: year }
        }));
        this.hasFYRecords = true;
    }

    handleInputChange(event) {
        const fieldAPI = event.target.dataset.fieldApi;
        const year = event.target.dataset.year;
        let newValue = event.target.type === 'number' ? +event.target.value : event.target.value;

        if (fieldAPI === 'Profit_and_Loss_Account__c') {
            const audited = newValue === 'Audited';
            this.yearsWithFlags = this.yearsWithFlags.map((y) => ({
                ...y,
                showSigning: y.label === year ? audited : y.showSigning
            }));
            const anyAudited = this.yearsWithFlags.some((y) => y.showSigning);
            this.sectionsWithFlags = this.sectionsWithFlags.map((sec) => {
                if (sec.isSigner) {
                    return { ...sec, showSignerRow: anyAudited };
                }
                if (sec.isUdin) {
                    return { ...sec, showUdinRow: anyAudited };
                }
                return sec;
            });
            if (!audited) {
                this.updateFinancialRecords('Signing_CA_Member_No__c', year, null);
                this.updateFinancialRecords('UDIN_No__c', year, null);
            }
        }

        this.updateFinancialRecords(fieldAPI, year, newValue, event);
    }

    updateFinancialRecords(fieldAPI, year, newValue, event) {
        this.financialPerformanceRecords = this.financialPerformanceRecords.map((item) => {
            if (item.year !== year) {
                return item;
            }
            const base = item.record ? { ...item.record } : {};
            return {
                ...item,
                record: { ...base, [fieldAPI]: newValue, Name: year }
            };
        });

        if (event) {
            this.recalculateFormulas(year, event);
        }
    }

    recalculateFormulas(year, event) {
        const currentField = event.target.dataset.fieldApi;
        formulas.forEach((formula) => {
            if (!formula.dependencies.includes(currentField)) {
                return;
            }
            const newRecord = {};
            formula.dependencies.forEach((field) => {
                const inputElement = this.template.querySelector(
                    `lightning-input[data-year="${year}"][data-field-api="${field}"], lightning-combobox[data-year="${year}"][data-field-api="${field}"]`
                );
                if (inputElement) {
                    newRecord[field] = inputElement.value ? inputElement.value : 0;
                }
            });
            const value = formula.calculate(newRecord);
            const formatted = typeof value === 'number' && !Number.isNaN(value) ? value.toFixed(2) : value;
            const inputElementToUpdate = this.template.querySelector(
                `lightning-input[data-year="${year}"][data-field-api="${formula.field}"], lightning-combobox[data-year="${year}"][data-field-api="${formula.field}"]`
            );
            if (inputElementToUpdate && formatted !== undefined && formatted !== null) {
                inputElementToUpdate.value = formatted;
                this.updateFinancialRecords(formula.field, year, formatted);
            }
        });
    }

    handleSave() {
        if (!this.recordId) {
            this.showToast('Error', 'Application Id is missing.', 'error');
            return;
        }

        const latestYear = this.yearsWithFlags.find((y) => y.isLatest)?.label;
        if (!latestYear) {
            this.showToast('Error', 'Could not determine latest financial year.', 'error');
            return;
        }

        const signingEl = this.template.querySelector(
            `lightning-input[data-field-api="Signing_CA_Member_No__c"][data-year="${latestYear}"]`
        );
        const udinEl = this.template.querySelector(
            `lightning-input[data-field-api="UDIN_No__c"][data-year="${latestYear}"]`
        );

        if (signingEl) {
            signingEl.setCustomValidity('');
            signingEl.reportValidity();
            if (!signingEl.value) {
                signingEl.setCustomValidity('Signing CA Member No is required');
                signingEl.showHelpMessageIfInvalid();
                this.showToast('Error', `Signing CA Member No is required for ${latestYear}`, 'error');
                return;
            }
        }

        if (udinEl) {
            udinEl.setCustomValidity('');
            udinEl.reportValidity();
            if (!udinEl.value) {
                udinEl.setCustomValidity('UDIN No is required');
                udinEl.showHelpMessageIfInvalid();
                this.showToast('Error', `UDIN No is required for ${latestYear}`, 'error');
                return;
            }
        }

        const recordObjects = this.financialPerformanceRecords
            .filter((item) => {
                if (item.recordId) {
                    return true;
                }
                if (!item.record) {
                    return false;
                }
                return Object.keys(item.record).some(
                    (key) =>
                        key !== 'Name' &&
                        key !== 'Application__c' &&
                        key !== 'attributes' &&
                        key !== 'GST__r' &&
                        item.record[key] !== null &&
                        item.record[key] !== '' &&
                        item.record[key] !== undefined
                );
            })
            .map((item) => {
                const newRecord = item.record ? { ...item.record } : { Name: item.year };
                newRecord.Application__c = this.recordId;
                newRecord.Name = item.year;
                if (item.recordId) {
                    newRecord.Id = item.recordId;
                }
                delete newRecord.GST__r;
                delete newRecord.attributes;
                return newRecord;
            });

        this.isLoading = true;
        this.invokeSaveAction(ACTION_SAVE_FINANCIAL_PERFORMANCE_RECORDS, {
            data: JSON.stringify(recordObjects)
        })
            .then(async () => {
                this.showToast('Success', MSG_DATA_SAVED_SUCCESS, 'success');
                this.hasFYRecords = true;
                await this.fetchRecords();
            })
            .catch((error) => {
                this.showToast('Error', this.reduceError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleClose() {
        window.close();
    }

    downloadFile() {
        const link = document.createElement('a');
        link.href = FinanceGridTemplate;
        link.download = 'Financial Performance Template.xlsx';
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    handleExcelFileChange(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        this.excelFileName = file.name;
        this.parseExcelFile(file);
    }

    async handleExcelFileRemove() {
        if (this.recordId && this.excelChecklistId) {
            this.isLoading = true;
            try {
                await this.invokeSaveAction(ACTION_DELETE_FINANCIAL_PERFORMANCE_EXCEL);
            } catch (error) {
                this.showToast('Error', this.reduceError(error), 'error');
                return;
            } finally {
                this.isLoading = false;
            }
        }
        this.excelFileUploaded = false;
        this.excelFileName = '';
        this.excelChecklistId = null;
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('Failed to read the Excel file.'));
            reader.readAsDataURL(file);
        });
    }

    async persistExcelFileToServer(file) {
        if (!this.recordId || !file) {
            return;
        }
        const base64Body = await this.readFileAsBase64(file);
        const result = await this.invokeSaveAction(ACTION_UPLOAD_FINANCIAL_PERFORMANCE_EXCEL, {
            fileName: file.name,
            base64Body
        });
        this.applyExcelDocumentFromFetch(result?.excelDocument);
    }

    parseExcelFile(file) {
        const reader = new FileReader();

        reader.onload = async (loadEvent) => {
            try {
                const workbook = XLSX.read(loadEvent.target.result, { type: 'binary' });
                const allSheetsData = workbook.SheetNames.map((name) => ({
                    name,
                    data: XLSX.utils.sheet_to_json(workbook.Sheets[name], { header: 1 })
                }));

                if (!allSheetsData.length) {
                    this.showToast('Error', 'No data found in the uploaded Excel file.', 'error');
                    return;
                }
                this.parseJsonData(allSheetsData);
                this.excelFileUploaded = true;
                this.excelFileName = file.name;
                if (this.recordId) {
                    this.isLoading = true;
                    try {
                        await this.persistExcelFileToServer(file);
                    } catch (error) {
                        this.showToast('Error', this.reduceError(error), 'error');
                    } finally {
                        this.isLoading = false;
                    }
                }
            } catch (error) {
                this.excelFileUploaded = false;
                this.excelFileName = '';
                this.excelChecklistId = null;
                this.showToast('Error', error?.message || 'Could not read the Excel file.', 'error');
            }
        };

        reader.onerror = () => {
            this.excelFileUploaded = false;
            this.excelFileName = '';
            this.excelChecklistId = null;
            this.showToast('Error', 'Failed to read the Excel file.', 'error');
        };

        reader.readAsArrayBuffer(file);
    }

    parseJsonData(jsonData) {
        const sheet = jsonData[0];
        const data = sheet?.data;
        if (!Array.isArray(data) || data.length < 2) {
            this.showToast('Error', 'The Excel template format is invalid or empty.', 'error');
            return;
        }

        const headerRow = data[0];
        if (!Array.isArray(headerRow) || headerRow.length < 2) {
            this.showToast('Error', 'Could not read financial year columns from the template.', 'error');
            return;
        }

        this.yearsMap = headerRow.slice(1).reduce((acc, curr, index) => {
            const resolvedYear = this.resolveYearKey(curr);
            if (resolvedYear) {
                acc[index + 1] = resolvedYear;
            }
            return acc;
        }, {});

        if (!Object.keys(this.yearsMap).length) {
            this.showToast(
                'Error',
                'Year columns in the file do not match this grid (expected labels like FY2025).',
                'error'
            );
            return;
        }

        this.excelRowsApplied = 0;
        data.slice(1).forEach((row) => {
            if (row?.length > 1) {
                this.applyExcelRow(row);
            }
        });

        this.refreshAuditedRowsFromRecords();

        if (this.excelRowsApplied > 0) {
            this.showToast('Success', 'Excel data loaded into the financial grid.', 'success');
        } else {
            this.showToast(
                'Warning',
                'No matching rows were found. Use the blank template and ensure section labels match the grid.',
                'warning'
            );
        }
    }

    applyExcelRow(row) {
        const fieldLabel = this.resolveFieldLabel(row[0]);
        if (!fieldLabel) {
            return;
        }

        for (let columnIndex = 1; columnIndex < row.length; columnIndex++) {
            const cellValue = row[columnIndex];
            const year = this.yearsMap[columnIndex];
            if (!year || cellValue === undefined || cellValue === null || cellValue === '') {
                continue;
            }
            this.setGridValueFromExcel(year, fieldLabel, cellValue);
        }
    }

    resolveYearKey(excelYear) {
        if (excelYear === undefined || excelYear === null) {
            return null;
        }
        const normalized = String(excelYear).trim();
        if (!normalized) {
            return null;
        }

        if (this.years.includes(normalized)) {
            return normalized;
        }

        const caseMatch = this.years.find((year) => year.toLowerCase() === normalized.toLowerCase());
        if (caseMatch) {
            return caseMatch;
        }

        const gstMatch = this.gstYears.find(
            (option) =>
                option.label === normalized ||
                option.label.toLowerCase() === normalized.toLowerCase()
        );
        if (gstMatch) {
            return gstMatch.value;
        }

        const yearDigits = normalized.match(/\d{4}/);
        if (yearDigits) {
            const fyKey = `FY${yearDigits[0]}`;
            if (this.years.includes(fyKey)) {
                return fyKey;
            }
        }

        return null;
    }

    resolveFieldLabel(rawLabel) {
        if (rawLabel === undefined || rawLabel === null) {
            return null;
        }
        const trimmed = String(rawLabel).trim();
        if (!trimmed) {
            return null;
        }

        const exact = this.sectionsWithFlags.find((section) => section.MasterLabel === trimmed);
        if (exact) {
            return exact.MasterLabel;
        }

        const caseInsensitive = this.sectionsWithFlags.find(
            (section) =>
                section.MasterLabel &&
                section.MasterLabel.toLowerCase() === trimmed.toLowerCase()
        );
        return caseInsensitive ? caseInsensitive.MasterLabel : null;
    }

    setGridValueFromExcel(year, fieldLabel, rawValue) {
        const inputElement = this.template.querySelector(
            `lightning-input[data-year="${year}"][data-field-label="${fieldLabel}"], ` +
                `lightning-combobox[data-year="${year}"][data-field-label="${fieldLabel}"]`
        );

        if (!inputElement) {
            return;
        }

        const fieldAPI = inputElement.dataset.fieldApi;
        let newValue = rawValue;
        if (inputElement.tagName === 'LIGHTNING-INPUT' && inputElement.type === 'number') {
            const numeric = Number(rawValue);
            if (Number.isNaN(numeric)) {
                return;
            }
            newValue = numeric;
        } else {
            newValue = String(rawValue).trim();
        }

        inputElement.value = newValue;
        this.handleInputChange({
            target: {
                dataset: { fieldApi: fieldAPI, year },
                type: inputElement.type,
                value: newValue
            }
        });

        this.excelRowsApplied += 1;
    }

    refreshAuditedRowsFromRecords() {
        this.yearsWithFlags = this.yearsWithFlags.map((yearFlag) => {
            const wrap = this.financialPerformanceRecords.find((item) => item.year === yearFlag.label);
            return {
                ...yearFlag,
                showSigning: wrap?.record?.Profit_and_Loss_Account__c === 'Audited'
            };
        });

        const anyAudited = this.yearsWithFlags.some((yearFlag) => yearFlag.showSigning);
        this.sectionsWithFlags = this.sectionsWithFlags.map((section) => {
            if (section.isSigner) {
                return { ...section, showSignerRow: anyAudited };
            }
            if (section.isUdin) {
                return { ...section, showUdinRow: anyAudited };
            }
            return section;
        });
    }

    async handleGSTYearSelection(event) {
        this.form26Total = 0;
        this.gstrTotal = 0;
        const oldValue = this.gstDetailsYearValue;
        const newValue = event.target.value;

        if (!this.selectedYear) {
            this.applyGstYearSelection(newValue);
            return;
        }

        const confirmed = await LightningConfirm.open({
            message: 'Changing financial year will clear unsaved GST data. Continue?',
            label: 'Change financial year'
        });

        if (confirmed) {
            this.applyGstYearSelection(newValue);
        } else if (oldValue) {
            this.gstDetailsYearValue = '';
            await Promise.resolve();
            this.gstDetailsYearValue = oldValue;
            this.initEmptyGstPanels();
        }
    }

    applyGstYearSelection(yearValue) {
        this.selectedYear = yearValue;
        const selectedOption = this.gstYears.find((option) => option.value === yearValue);
        this.selectedYearLabel = selectedOption ? selectedOption.label : yearValue;
        this.gstDetailsYearValue = yearValue;
        this.showGSTDetails = true;
        this.loadGstForSelectedYear();
    }

    initEmptyGstPanels() {
        this.clients = [{ Name_of_the_Client__c: '', Amount__c: '', Id: 1 }];
        this.gst3rRecords = GST_MONTHS.map((month) => ({ Month__c: month, Amount__c: '' }));
        this.nextClientId = 2;
        this.updateGstTotals();
    }

    loadGstForSelectedYear() {
        this.initEmptyGstPanels();
        const finRecord = this.getFinRecordForYear(this.selectedYear);
        if (!finRecord?.recordId) {
            return;
        }

        const gstRecords = this.getGstChildRecords(finRecord);
        if (!gstRecords.length) {
            return;
        }

        this.clients = gstRecords
            .filter((gst) => this.isGstRecordType(gst, 'Form 26 AS Credits'))
            .map((gst, index) => ({
                Name_of_the_Client__c: gst.Name_of_the_Client__c || '',
                Amount__c: gst.Amount__c || '',
                Id: gst.Id || index + 1
            }));

        const gstrByMonth = new Map(
            gstRecords
                .filter((gst) => this.isGstRecordType(gst, 'GSTR 3B') && gst.Month__c)
                .map((gst) => [gst.Month__c, gst])
        );
        this.gst3rRecords = GST_MONTHS.map((month) => {
            const saved = gstrByMonth.get(month);
            return saved
                ? { Month__c: month, Amount__c: saved.Amount__c || '', Id: saved.Id }
                : { Month__c: month, Amount__c: '' };
        });
        this.updateGstTotals();
    }

    handleAddClient() {
        if (this.clients.length >= this.limitForm26) {
            this.showToast('Error', `You cannot add more than ${this.limitForm26} clients.`, 'error');
            return;
        }
        this.clients = [
            ...this.clients,
            { Name_of_the_Client__c: '', Amount__c: '', Id: this.nextClientId++ }
        ];
    }

    handleClientNameChange(event) {
        const clientId = event.target.dataset.id;
        const newValue = String(this.getInputValue(event)).trim();
        this.clients = this.clients.map((client) => {
            if (client.Id == clientId) {
                return { ...client, Name_of_the_Client__c: newValue };
            }
            return client;
        });
        this.updateGstTotals();
    }

    handleform26Change(event) {
        const clientId = event.target.dataset.id;
        const amount = this.getInputValue(event);
        this.clients = this.clients.map((client) => {
            if (client.Id == clientId) {
                return { ...client, Amount__c: amount };
            }
            return client;
        });
        this.updateGstTotals();
    }

    handleGstMonthValueChange(event) {
        const month = event.target.dataset.month;
        const amount = this.getInputValue(event);
        this.gst3rRecords = this.gst3rRecords.map((row) =>
            row.Month__c === month ? { ...row, Amount__c: amount } : row
        );
        this.updateGstTotals();
    }

    async saveGSTRRecords() {
        if (!this.selectedYear) {
            this.showToast('Error', 'Select a financial year for GST details.', 'error');
            return;
        }

        this.syncGstPanelsFromDom();
        const finRecord = this.getFinRecordForYear(this.selectedYear);
        if (!finRecord?.recordId) {
            this.showToast('Error', 'Please save financial details before adding GST information.', 'error');
            return;
        }

        const form26Payload = this.buildForm26Payload(finRecord.recordId);
        const gstrPayload = this.buildGstrPayload(finRecord.recordId);
        if (!form26Payload.length && !gstrPayload.length) {
            this.showToast(
                'Error',
                'No GST details to save. Enter Form 26 AS client amounts and/or GSTR 3B monthly amounts.',
                'error'
            );
            return;
        }

        this.isLoading = true;
        try {
            if (form26Payload.length) {
                const saved = await this.saveGstPayload(
                    form26Payload,
                    'Form 26 AS Credits',
                    finRecord.recordId
                );
                this.clients = this.clients.map((client) => {
                    const row = saved.find((s) => s.Name_of_the_Client__c === client.Name_of_the_Client__c);
                    return row ? { ...client, Id: row.Id } : client;
                });
            }

            if (gstrPayload.length) {
                const saved = await this.saveGstPayload(gstrPayload, 'GSTR 3B', finRecord.recordId);
                this.gst3rRecords = this.gst3rRecords.map((row) => {
                    const match =
                        saved.find((s) => s.Id === row.Id) ||
                        saved.find((s) => s.Month__c === row.Month__c);
                    return match ? { ...row, Id: match.Id } : row;
                });
            }

            this.showToast('Success', MSG_DATA_SAVED_SUCCESS, 'success');
            await this.fetchRecords();
            if (this.showGSTDetails) {
                this.loadGstForSelectedYear();
            }
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleDismissPageToast() {
        this.showPageToast = false;
        if (this._pageToastTimer) {
            clearTimeout(this._pageToastTimer);
            this._pageToastTimer = null;
        }
    }

    showToast(title, message, variant = 'info') {
        if (this._pageToastTimer) {
            clearTimeout(this._pageToastTimer);
        }
        this.pageToastTitle = message ? title : '';
        this.pageToastMessage = message || title || '';
        this.pageToastVariant = variant;
        this.showPageToast = true;

        if (variant !== 'error') {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._pageToastTimer = setTimeout(() => {
                this.showPageToast = false;
            }, 6000);
        }
    }

    invokeReadAction(apexMethodName, params) {
        return getPageData({
            apexClassName: APEX_CLASS,
            apexMethodName,
            recordId: this.recordId,
            params: params || {}
        });
    }

    invokeSaveAction(apexMethodName, params) {
        return savePageData({
            apexClassName: APEX_CLASS,
            apexMethodName,
            recordId: this.recordId,
            params: params || {}
        });
    }
}