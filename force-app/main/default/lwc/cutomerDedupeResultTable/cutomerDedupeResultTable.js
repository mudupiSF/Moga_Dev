import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { invokeHandler } from 'c/clientLayerHelper';


export default class CutomerDedupeResultTable extends LightningElement {
    


    @api cardTitle = 'Customer Dedupe';
    @api cardSubtitle = 'Matching customer records';
    @api headerIcon = 'standard:people';
    @api recordId;
    @api applicantId;
    @api matches = [];
    @api isLoading = false;
    
    @track selectedCifId = null;
    @track isProcessing = false;

    get hasMatches() {
        return !this.isLoading && this.matches && this.matches.length > 0;
    }

    get noResults() {
        return !this.isLoading && (!this.matches || this.matches.length === 0);
    }

    get validButtonClass() {
        return `action-btn action-valid${!this.selectedCifId || this.isProcessing ? ' p4-primary-btn-disabled' : ''}`;
    }

    get invalidButtonClass() {
        return `action-btn action-invalid${!this.selectedCifId || this.isProcessing ? ' p4-primary-btn-disabled' : ''}`;
    }

    get matchRows() {
        return (this.matches || []).map((m, idx) => {
            const isExact = Number(m.matchPercent) === 100;
            return {
                ...m,
                key: m.cifId || String(idx),
                selected: m.cifId === this.selectedCifId,
                matchBadgeClass: isExact
                    ? 'match-badge match-badge-exact'
                    : 'match-badge match-badge-partial',
                flagList: this._buildFlagList(m.flags)
            };
        });
    }

    _buildFlagList(flags) {
        if (!flags || typeof flags !== 'object') return [];
        return Object.keys(flags).map((label) => {
            const active = !!flags[label];
            return {
                key: label,
                label,
                active,
                className: active ? 'flag-chip flag-active' : 'flag-chip flag-inactive'
            };
        });
    }

    handleCheckboxChange(event) {
        const cifId = event.currentTarget.dataset.id;
        this.selectedCifId = this.selectedCifId === cifId ? null : cifId;
    }

    handleValidClick() {
        if (!this.selectedCifId || this.isProcessing) return;
        
        this.isProcessing = true;
        const selectedMatch = this.matches.find(m => m.cifId === this.selectedCifId);
        this.lastValidatedMatch = selectedMatch;
        
        // Use clientLayerHelper to invoke the validation flow with progress modal
        // invokeHandler('clientLayerCustomerDedupe', 'onValidClick', this)
        //     .then(() => {
        //         this.dispatchEvent(new CustomEvent('matchvalidated', {
        //             detail: { cifId: this.selectedCifId, type: 'valid' }
        //         }));
        //     })
        //     .catch((error) => {
        //         console.error('Error in handleValidClick:', error);
        //         this.showToast('Error', error?.body?.message || error?.message || 'Validation failed', 'error');
        //     })
        //     .finally(() => {
        //         this.isProcessing = false;
        //     });
    }

    handleInvalidClick() {
        if (!this.selectedCifId || this.isProcessing) return;
        
        this.isProcessing = true;
        const selectedMatch = this.matches.find(m => m.cifId === this.selectedCifId);
        this.lastValidatedMatch = selectedMatch;
        
        // Use clientLayerHelper to invoke the validation flow with progress modal
        // invokeHandler('clientLayerCustomerDedupe', 'onInvalidClick', this)
        //     .then(() => {
        //         this.dispatchEvent(new CustomEvent('matchvalidated', {
        //             detail: { cifId: this.selectedCifId, type: 'invalid' }
        //         }));
        //     })
        //     .catch((error) => {
        //         console.error('Error in handleInvalidClick:', error);
        //         this.showToast('Error', error?.body?.message || error?.message || 'Validation failed', 'error');
        //     })
        //     .finally(() => {
        //         this.isProcessing = false;
        //     });
    }

    handleCheckEligibility() {
        this.dispatchEvent(new CustomEvent('checkeligibility'));
    }

    showToast(title, message, variant = 'info') {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}