/**
 * leadInformation
 * the leadInformation LWC on MOGA DEV's Application Record Page. 
 */

import { LightningElement, api, track, wire } from 'lwc';
import getLeadInformation from '@salesforce/apex/LeadInformationController.getLeadInformation';

const FIELD_CONFIG = [
    { key: 'applicationNumber',  label: 'Application Number', sequence: 1 },
    { key: 'leadSource',  label: 'Application Source', sequence: 2 },
    { key: 'productType', label: 'Product Type', sequence: 3 },
    { key: 'vehicleType', label: 'Vehicle Type', sequence: 4 }
];

export default class LeadInformation extends LightningElement {
    @api recordId;

    @track isCollapsed = false;
    _wiredData;

    @wire(getLeadInformation, { recordId: '$recordId' })
    wiredLeadInfo(result) {
        this._wiredData = result;
    }

    get isExpanded()         { return !this.isCollapsed; }
    get cardClass()          { return this.isExpanded ? 'li-card' : 'li-card li-card--collapsed'; }
    get collapseIconName()   { return this.isCollapsed ? 'utility:down' : 'utility:up'; }
    get collapseIconTitle()  { return this.isCollapsed ? 'Expand Lead Information' : 'Collapse Lead Information'; }

    get isLoading() { return !!(this.recordId && this._wiredData?.loading); }
    get hasError()  { return !!(this.recordId && this._wiredData?.error); }
    get leadData()  { return this._wiredData?.data || {}; }

    get displayFields() {
        const data = this.leadData;
        return [...FIELD_CONFIG]
            .sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0))
            .map((field) => ({
                ...field,
                displayValue: this._display(data ? data[field.key] : null)
            }));
    }

    _display(value) {
        if (value === null || value === undefined || String(value).trim() === '') {
            return '—';
        }
        return String(value);
    }

    handleToggleCollapse() {
        this.isCollapsed = !this.isCollapsed;
    }

    // Action stubs — wired in a follow-up phase.
    handleRevoke()   { /* TODO: wire Revoke flow for MOGA DEV */ }
    handleWithdraw() { /* TODO: wire Withdraw flow (port sfLOSWithdrawApplicationModal) */ }
    handleTransfer() { /* TODO: wire Transfer flow for MOGA DEV */ }
}