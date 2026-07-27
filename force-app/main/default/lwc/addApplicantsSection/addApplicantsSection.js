import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const DEFAULT_GUARANTOR_CAP = 3;
const DEFAULT_COBORROWER_CAP = 3;
const DEFAULT_BENEFICIARY_CAP = 10;

export default class AddApplicantsSection extends LightningElement {
    @api recordId;
    @api canAddGuarantor = false;
    @api canAddBeneficiary = false;
    @api removableApplicants = [];
    @api applicationType = '';
    @api isNonIndividual = false;
    @api isTwoWheeler = false;
    /** Gate: buttons appear only after Borrower EMI + Check Eligibility are confirmed. */
    @api showAddButtons = false;
    /** Live counts + caps for the remaining-slot countdown labels. */
    @api guarantorCount = 0;
    @api coBorrowerCount = 0;
    @api beneficiaryCount = 0;
    @api maxGuarantorCount = null;
    @api maxBeneficiaryCount = null;
    /** Disables add guarantor/beneficiary questions only. */
    @api isReadOnlyScreen = false;
    /** Disables remove section; only true when stage is past (not dedupe lock). */
    @api isRemoveReadOnly = false;
    /** Single-in-progress lock: disables Add buttons while another non-borrower journey is open. */
    @api lockForJourneyInProgress = false;
    /** drive the "+ Add Sub-<Role>" buttons (only when an NI of that role exists). */
    @api hasNonIndividualGuarantor = false;
    @api hasNonIndividualBeneficiary = false;

    @track addGuarantorCoBorrower = 'No';
    @track addBeneficiary = 'No';
    // "+ Add Sub-<Role>" selection: when ON, NEXT routes to the role's
    // existing multi-grid (no new top-level created); Customer Type is chosen on Basic Details.
    @track addSubGuarantor = 'No';
    @track addSubBeneficiary = 'No';
    @track wishToRemove = 'No';
    @track applicantToRemove = '';
    @track isProcessing = false;

    get guarantorLabel() {
        return this.isTwoWheeler 
            ? 'Do you wish to add a Co-Borrower to your application?'
            : 'Do you wish to add a Guarantor/Co-borrower to your application?';
    }

    get statusNoteText() {
        return this.isTwoWheeler
            ? 'Adding a Co-Borrower is not required as per the bank\'s policy. Selecting \'Yes\' may increase the processing time of your application.'
            : 'Adding a Co-borrower or Guarantor is not required as per the bank\'s policy. Selecting \'Yes\' may increase the processing time of your application.';
    }

    // "+ Add Sub-<Role>" buttons
    get roleNoun() { return this.isTwoWheeler ? 'Co-Borrower' : 'Guarantor'; }
    get subGuarantorButtonLabel() { return 'Add Sub-Beneficiary'; }
    get subBeneficiaryButtonLabel() { return 'Add Sub-Beneficiary'; }
    get isSubGuarantorActive() { return this.addSubGuarantor === 'Yes'; }
    get isSubBeneficiaryActive() { return this.addSubBeneficiary === 'Yes'; }
    get showSubGuarantorButton() {
        return this.isGuarantorActive && this.hasNonIndividualGuarantor && !this.isReadOnlyScreen;
    }
    get showSubBeneficiaryButton() {
        return this.isBeneficiaryActive && this.hasNonIndividualBeneficiary && !this.isReadOnlyScreen;
    }
    get subGuarantorButtonClass() {
        return this.isSubGuarantorActive ? 'aas-add-btn aas-add-btn--active' : 'aas-add-btn';
    }
    get subBeneficiaryButtonClass() {
        return this.isSubBeneficiaryActive ? 'aas-add-btn aas-add-btn--active' : 'aas-add-btn';
    }

    get showAddApplicantButtons() {
        return this.showGuarantorQuestion || this.showBeneficiaryQuestion;
    }

    get showGuarantorQuestion() {
        return this.canAddGuarantor && this.showAddButtons;
    }

    get showBeneficiaryQuestion() {
        return this.isNonIndividual && this.canAddBeneficiary && this.showAddButtons;
    }

    get isGuarantorActive() {
        return this.addGuarantorCoBorrower === 'Yes';
    }

    get isBeneficiaryActive() {
        return this.addBeneficiary === 'Yes';
    }

    get guarantorRemaining() {
        const used = this.isTwoWheeler ? this.coBorrowerCount : this.guarantorCount;
        const cap = this.isTwoWheeler
            ? DEFAULT_COBORROWER_CAP
            : (this.maxGuarantorCount != null ? Number(this.maxGuarantorCount) : DEFAULT_GUARANTOR_CAP);
        return Math.max(0, cap - (Number(used) || 0));
    }

    get beneficiaryRemaining() {
        const cap = this.maxBeneficiaryCount != null
            ? Number(this.maxBeneficiaryCount)
            : DEFAULT_BENEFICIARY_CAP;
        return Math.max(0, cap - (Number(this.beneficiaryCount) || 0));
    }

    get guarantorButtonLabel() {
        const base = this.isTwoWheeler ? 'Add Co-Borrower' : 'Add Guarantor';
        return this.guarantorRemaining > 0 ? `${base} (Rem:${this.guarantorRemaining})` : base;
    }

    get beneficiaryButtonLabel() {
        return this.beneficiaryRemaining > 0
            ? `Add Beneficiary (Rem:${this.beneficiaryRemaining})`
            : 'Add Beneficiary';
    }

    get isGuarantorButtonDisabled() {
        return this.isReadOnlyScreen
            || this.guarantorRemaining <= 0
            || this.isBeneficiaryActive
            || (this.lockForJourneyInProgress && !this.isGuarantorActive);
    }

    get isBeneficiaryButtonDisabled() {
        return this.isReadOnlyScreen
            || this.beneficiaryRemaining <= 0
            || this.isGuarantorActive
            || (this.lockForJourneyInProgress && !this.isBeneficiaryActive);
    }

    get guarantorButtonClass() {
        return this.isGuarantorActive ? 'aas-add-btn aas-add-btn--active' : 'aas-add-btn';
    }

    get beneficiaryButtonClass() {
        return this.isBeneficiaryActive ? 'aas-add-btn aas-add-btn--active' : 'aas-add-btn';
    }

    get showRemoveSection() {
        return Array.isArray(this.removableApplicants) && this.removableApplicants.length > 0;
    }

    get showRemoveApplicantPicker() {
        return this.wishToRemove === 'Yes';
    }

    get isRemoveButtonDisabled() {
        return this.isRemoveReadOnly || !this.applicantToRemove || this.isProcessing;
    }

    get isWishToRemoveYes() {
        return this.wishToRemove === 'Yes';
    }

    get isWishToRemoveNo() {
        return this.wishToRemove === 'No';
    }

    handleAddGuarantorClick() {
        if (this.isReadOnlyScreen || this.isGuarantorButtonDisabled) {
            return;
        }
        if (this.isGuarantorActive) {
            this.addGuarantorCoBorrower = 'No';
            this.addSubGuarantor = 'No';
        } else {
            this.addGuarantorCoBorrower = 'Yes';
            this.addBeneficiary = 'No';
            this.addSubBeneficiary = 'No';
        }
        this.dispatchChangeEvent();
    }

    handleAddBeneficiaryClick() {
        if (this.isReadOnlyScreen || this.isBeneficiaryButtonDisabled) {
            return;
        }
        if (this.isBeneficiaryActive) {
            this.addBeneficiary = 'No';
            this.addSubBeneficiary = 'No';
        } else {
            this.addBeneficiary = 'Yes';
            this.addGuarantorCoBorrower = 'No';
            this.addSubGuarantor = 'No';
        }
        this.dispatchChangeEvent();
    }

    // "+ Add Sub-<Role>" toggle (route to existing role grid; no new top-level)
    handleAddSubGuarantorClick() {
        if (this.isReadOnlyScreen || !this.showSubGuarantorButton) {
            return;
        }
        this.addSubGuarantor = this.isSubGuarantorActive ? 'No' : 'Yes';
        this.dispatchChangeEvent();
    }

    handleAddSubBeneficiaryClick() {
        if (this.isReadOnlyScreen || !this.showSubBeneficiaryButton) {
            return;
        }
        this.addSubBeneficiary = this.isSubBeneficiaryActive ? 'No' : 'Yes';
        this.dispatchChangeEvent();
    }

    handleWishToRemoveChange(event) {
        if (this.isRemoveReadOnly) {
            return;
        }
        this.wishToRemove = event.target.value;
        if (this.wishToRemove === 'No') {
            this.applicantToRemove = '';
        }
    }

    handleApplicantToRemoveChange(event) {
        if (this.isRemoveReadOnly) {
            return;
        }
        this.applicantToRemove = event.detail.value;
    }

    handleRemoveClick() {
        if (this.isRemoveReadOnly) {
            return;
        }
        if (!this.applicantToRemove) {
            this.showToast('Validation', 'Please select an applicant to remove', 'warning');
            return;
        }

        this.dispatchEvent(new CustomEvent('requestremoveconfirm', {
            detail: { applicantId: this.applicantToRemove },
            bubbles: true,
            composed: true
        }));
    }

    dispatchChangeEvent() {
        this.dispatchEvent(new CustomEvent('selectionchange', {
            detail: {
                addGuarantorCoBorrower: this.addGuarantorCoBorrower,
                addBeneficiary: this.addBeneficiary,
                addSubGuarantor: this.addSubGuarantor,
                addSubBeneficiary: this.addSubBeneficiary
            }
        }));
    }

    @api
    getSelections() {
        return {
            addGuarantorCoBorrower: this.addGuarantorCoBorrower,
            addBeneficiary: this.addBeneficiary,
            addSubGuarantor: this.addSubGuarantor,
            addSubBeneficiary: this.addSubBeneficiary
        };
    }

    @api
    validateSelections() {
        // Customer Type is no longer asked here (chosen on Basic Details);
        // nothing role-type related to validate at this stage.
        return true;
    }

    @api
    resetRemoveUi() {
        this.wishToRemove = 'No';
        this.applicantToRemove = '';
        this.isProcessing = false;
    }

    @api
    resetGuarantorSelection() {
        this.addGuarantorCoBorrower = 'No';
        this.addSubGuarantor = 'No';
        this.dispatchChangeEvent();
    }

    @api
    resetBeneficiarySelection() {
        this.addBeneficiary = 'No';
        this.addSubBeneficiary = 'No';
        this.dispatchChangeEvent();
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