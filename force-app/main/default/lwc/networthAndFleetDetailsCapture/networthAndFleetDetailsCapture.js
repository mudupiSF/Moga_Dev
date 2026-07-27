import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig';
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData';

const APEX_CLASS = 'NetworthAndFleetDetailsController';
const ACTION_FETCH_NETWORTH_AND_FLEET_DETAILS = 'fetchNetworthAndFleetDetails';
const ACTION_GET_NETWORTH_DETAILS = 'getNetworthDetails';
const ACTION_SAVE_NETWORTH_DETAILS = 'saveNetworthDetails';
const ACTION_GET_FLEET_COUNT = 'getFleetCount';
const ACTION_GET_FLEET_DETAILS = 'getFleetDetails';
const ACTION_SAVE_FLEET_DETAIL = 'saveFleetDetail';
const ACTION_DELETE_FLEET_DETAIL = 'deleteFleetDetail';
const ACTION_UPSERT_DOCUMENT_CHECKLIST = 'upsertDocumentChecklist';
const ACTION_GET_DOCUMENT_CHECKLIST = 'getDocumentChecklist';

const ACCORDION_NETWORTH = 'networth';
const ACCORDION_FLEET = 'fleet';

const TYPE_IMMOVABLE = 'Total Value of Immovable Property';
const TYPE_OTHER_ASSETS = 'Total Value of Other Assets';
const TYPE_LIABILITIES = 'Total Liabilities';

const NETWORTH_DOC_TYPE = 'Networth Detail Document';
const FLEET_DOC_TYPE = 'Fleet Detail Document';

const DOCUMENT_COLLECTED_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];

const VEHICLE_NUMBER_PATTERN = '^([A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4}|[A-Z]{2}[0-9]{2}[A-Z]{2}[0-9]{4})$';
const VEHICLE_NUMBER_MESSAGE = 'Enter a valid vehicle number (e.g. MH12AB1234)';

export default class NetworthAndFleetDetailsCapture extends LightningElement {
    _recordId;
    _applicantId;

    _isStagePast = false
    @api 
    set isStagePast(value) {
      this._isStagePast = value === true || value === 'true'
    }
    get isStagePast() {
      return this._isStagePast
    }
  
    get isReadOnlyScreen() {
      return this.isStagePast
    }

    activeAccordionSection = '';
    disableAllFields = false;
    isCvProduct = false;
    canEditDeleteFleet = false;

    @track networthSectionsA = [];
    @track networthSectionsB = [];
    @track networthSectionsC = [];
    netWorth = 0;
    networthRemarks = '';
    fleetRemarks = '';

    @track fleetData = [];
    @track fleetDetails = [];
    showFleetModal = false;
    showFleetAddForm = false;
    selectedFleetType = '';
    fleetdataExist = false;
    totalFleetCount = 0;

    @track fleetRecord = {};
    @track productOptions = [];
    assetMakeSelectedLabel = '';
    assetModelSelectedLabel = '';
    productType = '';
    makeType = '';
    isEditMode = false;
    editingFleetId = null;

    hasNetworthDocument = false;
    hasFleetDocument = false;
    networthDocumentName = '';
    fleetDocumentName = '';

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.initializeIfReady();
    }

    @api
    get applicantId() {
        return this._applicantId;
    }
    set applicantId(value) {
        this._applicantId = value;
        this.initializeIfReady();
    }

    get documentCollectedOptions() {
        return DOCUMENT_COLLECTED_OPTIONS;
    }

    get isNetworthAccordionOpen() {
        return this.activeAccordionSection === ACCORDION_NETWORTH;
    }

    get isFleetAccordionOpen() {
        return this.activeAccordionSection === ACCORDION_FLEET;
    }

    get networthAccordionItemClass() {
        return this.isNetworthAccordionOpen
            ? 'nf-accordion-item nf-accordion-item-open'
            : 'nf-accordion-item';
    }

    get fleetAccordionItemClass() {
        return this.isFleetAccordionOpen
            ? 'nf-accordion-item nf-accordion-item-open'
            : 'nf-accordion-item';
    }

    get networthAccordionTriggerClass() {
        return this.isNetworthAccordionOpen
            ? 'nf-accordion-trigger nf-accordion-trigger-open'
            : 'nf-accordion-trigger';
    }

    get fleetAccordionTriggerClass() {
        return this.isFleetAccordionOpen
            ? 'nf-accordion-trigger nf-accordion-trigger-open'
            : 'nf-accordion-trigger';
    }

    get networthChevronIcon() {
        return this.isNetworthAccordionOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get fleetChevronIcon() {
        return this.isFleetAccordionOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }

    handleAccordionToggle(event) {
        const section = event.currentTarget?.dataset?.section;
        if (!section) {
            return;
        }
        this.activeAccordionSection =
            this.activeAccordionSection === section ? '' : section;
    }

    get fleetBtnLabel() {
        return this.isCvProduct ? 'View/Edit/Delete' : 'View/Edit';
    }

    get fleetFormTitle() {
        return this.isEditMode ? 'Edit Fleet Details' : 'Add New Fleet';
    }

    get showFleetActionsColumn() {
        return this.isCvProduct;
    }

    get showFleetDocumentUpload() {
        return !this.hasFleetDocument && !this.disableAllFields;
    }

    get showNetworthDocumentUpload() {
        return !this.hasNetworthDocument && !this.disableAllFields;
    }

    get isSaveDisabled() {
        return this.disableAllFields;
    }

    get acceptedFormats() {
        return ['.pdf', '.png', '.jpg', '.jpeg'];
    }

    get fleetSaveButtonLabel() {
        return this.isEditMode ? 'Update' : 'Save';
    }

    get showFleetAddButton() {
        return !this.showFleetAddForm && !this.disableAllFields;
    }

    get mmvMakeSearchContextJson() {
        const productType = this.productType || this.fleetRecord?.Product__c || '';
        return JSON.stringify({ productType });
    }

    get mmvModelSearchContextJson() {
        const makeCode = this.makeType || this.fleetRecord?.Asset_Make__c || '';
        return JSON.stringify({ makeCode });
    }

    get isFleetMakeDisabled() {
        return !(this.productType || this.fleetRecord?.Product__c);
    }

    get isFleetModelDisabled() {
        return !(this.makeType || this.fleetRecord?.Asset_Make__c);
    }

    connectedCallback() {
        this.initializeIfReady();
    }

    async initializeIfReady() {
        if (!this.applicantId || !this.recordId) {
            return;
        }
        await this.loadNetworthAndFleetDetails();
        await this.loadExistingData();
        await this.loadFleetCount();
        await this.loadDocuments();
    }

    async loadNetworthAndFleetDetails() {
        const ctx = await this.invokeReadAction(ACTION_FETCH_NETWORTH_AND_FLEET_DETAILS);
        this.isCvProduct = !!ctx?.isCvProduct;
        this.canEditDeleteFleet = this.isReadOnlyScreen ? false : !!ctx?.canEditDeleteFleet;
        this.disableAllFields = this.isReadOnlyScreen || !ctx?.canEdit;
        this.productOptions = Array.isArray(ctx?.productOptions) ? ctx.productOptions : [];
    }

    async loadExistingData() {
        const result = await this.invokeReadAction(ACTION_GET_NETWORTH_DETAILS);
        const networthDetails = result?.networthDetails || [];
        if (networthDetails.length > 0) {
            this.processNetworthData(networthDetails);
        } else {
            this.initializeDefaultSections();
        }
        this.netWorth = result?.totalNetworth || 0;
        this.networthRemarks = result?.networthRemarks || '';
        this.fleetRemarks = result?.fleetRemarks || '';
    }

    processNetworthData(networthData) {
        this.networthSectionsA = [];
        this.networthSectionsB = [];
        this.networthSectionsC = [];

        networthData.forEach((item) => {
            const section = { ...item, id: item.Id || this.generateUniqueId() };
            if (item.Networth_Type__c === TYPE_IMMOVABLE) {
                this.networthSectionsA.push(section);
            } else if (item.Networth_Type__c === TYPE_OTHER_ASSETS) {
                this.networthSectionsB.push(section);
            } else if (item.Networth_Type__c === TYPE_LIABILITIES) {
                this.networthSectionsC.push(section);
            }
        });
    }

    initializeDefaultSections() {
        this.networthSectionsA = [{ id: this.generateUniqueId(), Networth_Type__c: TYPE_IMMOVABLE }];
        this.networthSectionsB = [{ id: this.generateUniqueId(), Networth_Type__c: TYPE_OTHER_ASSETS }];
        this.networthSectionsC = [{ id: this.generateUniqueId(), Networth_Type__c: TYPE_LIABILITIES }];
    }

    generateUniqueId() {
        return 'NET-' + Math.random().toString(36).substr(2, 9);
    }

    async loadFleetCount() {
        const result = await this.invokeReadAction(ACTION_GET_FLEET_COUNT);
        if (result) {
            this.fleetData = [
                { Id: 'FLEET-1', fleetType: 'Free Fleet', count: result.freeFleet || 0 },
                { Id: 'FLEET-2', fleetType: 'Financed by Others', count: result.financedByOthers || 0 }
            ];
            this.totalFleetCount = result.totalFleet || 0;
        }
    }

    async loadDocuments() {
        const [networthDoc, fleetDoc] = await Promise.all([
            this.invokeReadAction(ACTION_GET_DOCUMENT_CHECKLIST, { documentType: NETWORTH_DOC_TYPE }),
            this.invokeReadAction(ACTION_GET_DOCUMENT_CHECKLIST, { documentType: FLEET_DOC_TYPE })
        ]);
        this.hasNetworthDocument = !!networthDoc?.found;
        this.networthDocumentName = networthDoc?.fileName || '';
        this.hasFleetDocument = !!fleetDoc?.found;
        this.fleetDocumentName = fleetDoc?.fileName || '';
    }

    handleSectionInputChange(event) {
        const sectionId = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target?.value ?? '';

        this.updateSectionValue(this.networthSectionsA, sectionId, field, value);
        this.updateSectionValue(this.networthSectionsB, sectionId, field, value);
        this.updateSectionValue(this.networthSectionsC, sectionId, field, value);
        this.calculateNetWorth();
    }

    updateSectionValue(sectionList, sectionId, field, value) {
        const section = sectionList.find((sec) => sec.id === sectionId);
        if (section) {
            section[field] = value;
        }
    }

    addNetworthSectionA() {
        this.networthSectionsA = [
            ...this.networthSectionsA,
            { id: this.generateUniqueId(), Networth_Type__c: TYPE_IMMOVABLE }
        ];
    }

    addNetworthSectionB() {
        this.networthSectionsB = [
            ...this.networthSectionsB,
            { id: this.generateUniqueId(), Networth_Type__c: TYPE_OTHER_ASSETS }
        ];
    }

    addNetworthSectionC() {
        this.networthSectionsC = [
            ...this.networthSectionsC,
            { id: this.generateUniqueId(), Networth_Type__c: TYPE_LIABILITIES }
        ];
    }

    deleteNetworthSection(event) {
        const sectionId = event.currentTarget.dataset.id;
        this.networthSectionsA = this.networthSectionsA.filter((sec) => sec.id !== sectionId);
        this.networthSectionsB = this.networthSectionsB.filter((sec) => sec.id !== sectionId);
        this.networthSectionsC = this.networthSectionsC.filter((sec) => sec.id !== sectionId);
        this.calculateNetWorth();
    }

    calculateNetWorth() {
        const totalMarketValueA = this.networthSectionsA.reduce(
            (sum, sec) => sum + (parseFloat(sec.Market_Value__c) || 0),
            0
        );
        const totalValueB = this.networthSectionsB.reduce(
            (sum, sec) => sum + (parseFloat(sec.Value_at_Cost_lacs__c) || 0),
            0
        );
        const totalLiabilitiesC = this.networthSectionsC.reduce(
            (sum, sec) => sum + (parseFloat(sec.O_s_as_on_date_In_Lacs__c) || 0),
            0
        );
        this.netWorth = totalMarketValueA + totalValueB - totalLiabilitiesC;
    }

    handleRemarksChange(event) {
        this.networthRemarks = event.target.value;
    }

    handleFleetRemarkChange(event) {
        this.fleetRemarks = event.target.value;
    }

    validityCheckInSection(sectionSelector) {
        const section = this.template.querySelector(sectionSelector);
        if (!section) {
            return true;
        }
        return [...section.querySelectorAll('lightning-combobox, lightning-input, lightning-textarea')].reduce(
            (validSoFar, inputField) => {
                inputField.reportValidity();
                return validSoFar && inputField.checkValidity();
            },
            true
        );
    }

    handleSaveNetworth() {
        const isValid = this.validityCheckInSection('[data-section-content="networth"]');
        if (!isValid) {
            this.showToast('Please fill all required fields', '', 'warning');
            return;
        }
        this.persistNetworthDetails();
    }

    handleSaveFleetSection() {
        const isValid = this.validityCheckInSection('[data-section-content="fleet"]');
        if (!isValid) {
            this.showToast('Please fill all required fields', '', 'warning');
            return;
        }
        this.persistFleetDetails();
    }

    async persistNetworthDetails() {
        try {
            const networthRecords = [
                ...this.networthSectionsA,
                ...this.networthSectionsB,
                ...this.networthSectionsC
            ];
            await this.invokeSaveAction(ACTION_SAVE_NETWORTH_DETAILS, {
                data: JSON.stringify({
                    applicantId: this.applicantId,
                    networthData: networthRecords,
                    netWorth: this.netWorth,
                    networthRemarks: this.networthRemarks
                })
            });
            this.showToast('Success', 'Networth details saved successfully', 'success');
            this.activeAccordionSection = '';
            await this.loadExistingData();
        } catch (error) {
            this.showToast('Error', error?.body?.message || 'Failed to save networth details', 'error');
        }
    }

    async persistFleetDetails() {
        try {
            await this.invokeSaveAction(ACTION_SAVE_FLEET_DETAIL, {
                data: JSON.stringify({
                    applicantId: this.applicantId,
                    fleetRemarks: this.fleetRemarks
                })
            });
            this.showToast('Success', 'Fleet details saved successfully', 'success');
            this.activeAccordionSection = '';
        } catch (error) {
            this.showToast('Error', error?.body?.message || 'Failed to save fleet details', 'error');
        }
    }

    handleViewFleetClick(event) {
        this.selectedFleetType = event.currentTarget.dataset.type;
        this.showFleetModal = true;
        this.fetchFleetDetails();
    }

    async fetchFleetDetails() {
        const result = await this.invokeReadAction(ACTION_GET_FLEET_DETAILS, {
            fleetType: this.selectedFleetType
        });
        this.fleetDetails = result?.fleetDetails || [];
        this.fleetdataExist = this.fleetDetails.length > 0;
    }

    handleCloseFleetModal() {
        this.showFleetModal = false;
        this.resetEditState();
        this.loadFleetCount();
    }

    toggleFleetAddForm() {
        this.showFleetAddForm = !this.showFleetAddForm;
        if (!this.showFleetAddForm) {
            this.resetEditState();
        }
    }

    resetEditState() {
        this.isEditMode = false;
        this.editingFleetId = null;
        this.resetFleetRecord();
    }

    handleEditFleet(event) {
        if (!this.canEditDeleteFleet) {
            this.showToast('Error', 'You do not have permission to edit fleet details.', 'error');
            return;
        }
        const fleetId = event.currentTarget.dataset.fleetId;
        const fleetToEdit = this.fleetDetails.find((fleet) => fleet.Id === fleetId);
        if (!fleetToEdit) {
            return;
        }
        this.isEditMode = true;
        this.editingFleetId = fleetId;
        this.fleetRecord = { ...fleetToEdit };
        this.productType = fleetToEdit.Product__c;
        this.makeType = fleetToEdit.Asset_Make__c;
        this.assetMakeSelectedLabel = '';
        this.assetModelSelectedLabel = '';
        this.showFleetAddForm = true;
    }

    async handleDeleteFleet(event) {
        if (!this.canEditDeleteFleet) {
            this.showToast('Error', 'You do not have permission to delete fleet details.', 'error');
            return;
        }
        const fleetId = event.currentTarget.dataset.fleetId;
        try {
            await this.invokeSaveAction(ACTION_DELETE_FLEET_DETAIL, { fleetId });
            this.showToast('Success', 'Fleet record deleted successfully', 'success');
            await this.fetchFleetDetails();
            await this.loadFleetCount();
        } catch (error) {
            this.showToast('Error', error?.body?.message || 'Failed to delete fleet record', 'error');
        }
    }

    handleFormInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target?.value ?? '';
        this.fleetRecord = { ...this.fleetRecord, [field]: value };
        if (field === 'Product__c') {
            this.productType = value;
            this.makeType = '';
            this.assetMakeSelectedLabel = '';
            this.assetModelSelectedLabel = '';
            this.fleetRecord = {
                ...this.fleetRecord,
                Asset_Make__c: '',
                Asset_Model__c: ''
            };
        }
    }

    handleFleetMakeChange(event) {
        const value = event.detail?.value || '';
        const label = event.detail?.label || '';
        this.makeType = value;
        this.assetMakeSelectedLabel = label;
        this.assetModelSelectedLabel = '';
        this.fleetRecord = {
            ...this.fleetRecord,
            Asset_Make__c: value,
            Asset_Model__c: ''
        };
    }

    handleFleetModelChange(event) {
        const value = event.detail?.value || '';
        const label = event.detail?.label || '';
        this.assetModelSelectedLabel = label;
        this.fleetRecord = {
            ...this.fleetRecord,
            Asset_Model__c: value
        };
    }

    handleFleetSearchError(event) {
        const message = event.detail?.message || 'Search failed.';
        this.showToast('Search Error', message, 'error');
    }

    async handleSaveFleetRecord() {
        const fleetForm = this.template.querySelector('.nf-fleet-form');
        if (!fleetForm) {
            return;
        }
        const inputs = fleetForm.querySelectorAll('lightning-input, lightning-combobox');
        let isValid = true;
        inputs.forEach((input) => {
            if (!input.reportValidity()) {
                isValid = false;
            }
        });
        if (!this.fleetRecord.Product__c || !this.fleetRecord.Asset_Make__c || !this.fleetRecord.Asset_Model__c) {
            isValid = false;
        }
        if (!isValid) {
            this.showToast('Please fill all required fields', '', 'warning');
            return;
        }

        try {
            const response = await this.invokeSaveAction(ACTION_SAVE_FLEET_DETAIL, {
                fleetRecord: this.fleetRecord,
                fleetType: this.selectedFleetType
            });
            const fleetDetails = response?.fleetDetails || [];
            if (fleetDetails.length > 0) {
                const action = this.isEditMode ? 'updated' : 'saved';
                this.showToast('Success', `Fleet record ${action} successfully`, 'success');
                this.fleetDetails = fleetDetails;
                this.fleetdataExist = true;
                this.showFleetAddForm = false;
                this.isEditMode = false;
                this.editingFleetId = null;
                await this.loadFleetCount();
                this.resetFleetRecord();
            }
        } catch (error) {
            this.showToast('Error', error?.body?.message || 'Failed to save fleet record', 'error');
        }
    }

    async handleNetworthUploadFinished(event) {
        await this.handleDocumentUploadFinished(event, NETWORTH_DOC_TYPE);
    }

    async handleFleetUploadFinished(event) {
        await this.handleDocumentUploadFinished(event, FLEET_DOC_TYPE);
    }

    async handleDocumentUploadFinished(event, documentType) {
        const file = event.detail?.files?.[0];
        if (!file) {
            return;
        }
        try {
            await this.invokeSaveAction(ACTION_UPSERT_DOCUMENT_CHECKLIST, {
                documentType,
                contentDocumentId: file.documentId,
                contentVersionId: file.contentVersionId,
                fileName: file.name
            });
            await this.loadDocuments();
            this.showToast('Success', 'Document uploaded successfully', 'success');
        } catch (error) {
            this.showToast('Error', error?.body?.message || 'Failed to upload document', 'error');
        }
    }

    @api
    async refreshCmpHandler() {
        await this.initializeIfReady();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    invokeReadAction(apexMethodName, params = {}) {
        return getPageData({
            apexClassName: APEX_CLASS,
            apexMethodName,
            recordId: this.recordId,
            params: {
                applicantId: this.applicantId,
                ...params
            }
        });
    }

    invokeSaveAction(apexMethodName, params = {}) {
        return savePageData({
            apexClassName: APEX_CLASS,
            apexMethodName,
            recordId: this.recordId,
            params: {
                applicantId: this.applicantId,
                ...params
            }
        });
    }

    resetFleetRecord() {
        this.fleetRecord = {
            Product__c: '',
            Asset_Make__c: '',
            Asset_Model__c: '',
            Vehicle_Number__c: '',
            Year_of_Manufacture__c: '',
            Seasoning__c: '',
            Current_Demand__c: '',
            Financiar_Name__c: '',
            Policy_Expire_Date__c: '',
            Id: ''
        };
        this.productType = '';
        this.makeType = '';
        this.assetMakeSelectedLabel = '';
        this.assetModelSelectedLabel = '';
    }

    get vehicleNumberPattern() {
        return VEHICLE_NUMBER_PATTERN;
    }

    get vehicleNumberMessage() {
        return VEHICLE_NUMBER_MESSAGE;
    }
}