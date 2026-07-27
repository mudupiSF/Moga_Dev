import { LightningElement, api } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import softDeleteApplicant from '@salesforce/apex/dynamicStageNavigatorController.softDeleteApplicant'
import createSubApplicantShell from '@salesforce/apex/ApplicantSubService.createSubApplicantShell'
import setPrimaryApplicant from '@salesforce/apex/ApplicantSubService.setPrimaryApplicant'

const LOS_MENU_SELECT_EVENT = 'losmenuselect'
const LOS_MENU_REFRESH_EVENT = 'losmenurefresh'
const DEDUPE_STEP = 'Dedupe and Eligibility'

function displayCustomerType(value) {
  const map = {
    NI: 'Non-Individual',
    IN: 'Individual',
    'Non Individual': 'Non-Individual',
    'Non-Individual': 'Non-Individual'
  }
  return map[value] || value || 'Individual'
}

export default class ListOfApplicants extends LightningElement {
  @api recordId
  @api groupLabel = ''
  @api tab = ''
  @api stagePhrase = ''
  @api currentViewId = ''
  @api overrideLwc = ''
  @api applicantCompletionOverrides = {}
  /** Single-in-progress lock: hides/disables the "+" add-sub tile while a journey is open. */
  @api subCreationLocked = false

  _applicants = []
  @api
  get applicants() {
    return this._applicants
  }
  set applicants(val) {
    this._applicants = Array.isArray(val) ? val : []
  }

  _selectedParentId = null

  get normalizedApplicants() {
    const overrides = this.applicantCompletionOverrides || {}
    const currentStage = this.tab || ''
    return (this._applicants || [])
      .filter((a) => !a.inActiveApplicant)
      .map((a) => this._normalizeTile(a, currentStage, overrides))
  }

  // The selected NI parent whose sub-applicants render in the section below the grid.
  get selectedParent() {
    if (!this._selectedParentId) return null
    return this.normalizedApplicants.find(
      (a) => a.applicantId === this._selectedParentId && a.isSelectable
    ) || null
  }

  get subSectionLabel() {
    const role = (this.groupLabel || 'Applicant').trim()
    return `Sub ${this._pluralize(role)}`
  }

  _pluralize(word) {
    if (/y$/i.test(word)) return word.replace(/y$/i, 'ies')
    return `${word}s`
  }

  // Builds a single tile view-model and recursively normalizes any Individual
  // sub-applicants nested beneath a Non-Individual tile (ITER 6).
  _normalizeTile(a, currentStage, overrides) {
    const overrideComplete = overrides[a.applicantId]
    const currentComplete = overrideComplete ?? a.currentLoanStageComplete ?? ''
    const completedViaOverride = !!overrideComplete && overrideComplete === currentStage
    const isStagePast = a.stepMenuStatus === 'completed'
      || completedViaOverride
      || (!!currentComplete && currentComplete === currentStage)
    const isEditMode = !isStagePast
    const subTiles = (a.subApplicants || [])
      .filter((s) => !s.inActiveApplicant)
      .map((s) => this._normalizeTile(s, currentStage, overrides))
    const hasSubApplicants = subTiles.length > 0
    const customerTypeLabel = displayCustomerType(a.customerType)
    // Provisioning gate: an NI parent that has cleared Dedupe & Eligibility may add IN sub-applicants,
    // unless another non-borrower journey is already in progress (single-in-progress lock).
    const canAddSub = !a.isSubApplicant
      && customerTypeLabel === 'Non-Individual'
      && currentComplete === DEDUPE_STEP
      && !this.subCreationLocked
    // Selectable = an NI parent that has subs or can add them. Subs render in a separate
    // section below (NOT inline), revealed only when its top tile is selected, so parent
    // and sub statuses never visually merge.
    const isSelectable = hasSubApplicants || canAddSub
    const isSelected = isSelectable && a.applicantId === this._selectedParentId
    return {
      applicantId: a.applicantId,
      tabLabel: a.tabLabel || '',
      applicantName: (a.applicantName || '').toUpperCase() || '—',
      customerType: customerTypeLabel,
      isEditMode,
      isStagePast,
      currentLoanStageComplete: currentComplete,
      buttonTitle: isEditMode ? 'Edit Details' : 'View Details',
      cardClass: (isStagePast ? 'applicant-card submitted' : 'applicant-card pending')
        + (isSelectable ? ' selectable' : '')
        + (isSelected ? ' selected' : ''),
      statusBarClass: isStagePast ? 'status-bar submitted' : 'status-bar pending',
      statusIconClass: isStagePast ? 'status-icon submitted' : 'status-icon pending',
      statusBadgeClass: isStagePast ? 'status-badge submitted' : 'status-badge pending',
      statusBadgeText: isStagePast ? 'SUBMITTED' : 'PENDING',
      hasSubApplicants,
      canAddSub,
      isSelectable,
      isSelected,
      subTiles,
      //primary picker
      isPrimary: !!a.isPrimary,
      primaryEligible: !!a.primaryEligible,
      primarySelectable: !!a.primarySelectable,
      primaryDisabled: !a.primarySelectable,
      primaryOnAttr: a.isPrimary ? 'true' : 'false',
      primaryToggleClass: 'primary-toggle' + (a.isPrimary ? ' on' : ' off')
        + (a.primarySelectable ? '' : ' locked'),
      primaryToggleTitle: a.isPrimary ? 'Primary applicant' : 'Set as Primary'
    }
  }

  handleSelectParent(event) {
    const id = event.currentTarget?.dataset?.applicantId
    if (!id) return
    const top = this.normalizedApplicants.find((a) => a.applicantId === id)
    if (!top || !top.isSelectable) return
    this._selectedParentId = this._selectedParentId === id ? null : id
  }

  _findTile(applicantId) {
    const walk = (tiles) => {
      for (const t of tiles) {
        if (t.applicantId === applicantId) return t
        if (t.subTiles && t.subTiles.length) {
          const hit = walk(t.subTiles)
          if (hit) return hit
        }
      }
      return null
    }
    return walk(this.normalizedApplicants)
  }

  _pendingDeleteApplicantId = null
  showRemoveConfirmModal = false
  removeConfirmProps = {}

  handleDeleteApplicant(event) {
    event.stopPropagation()
    const applicantId = event.currentTarget?.dataset?.applicantId
    if (!applicantId) return
    this._pendingDeleteApplicantId = applicantId
    this.removeConfirmProps = {
      componentName: 'confirmation',
      componentProps: {
        title: 'Remove Applicant',
        message: 'Do you wish to proceed with removing the selected Applicant?',
        buttons: [
          { label: 'Cancel', value: 'cancel', variant: 'neutral' },
          { label: 'Confirm', value: 'confirm', variant: 'brand' }
        ]
      }
    }
    this.showRemoveConfirmModal = true
  }

  async handleRemoveModalAction(event) {
    const value = event.detail?.value
    this.showRemoveConfirmModal = false
    this.removeConfirmProps = {}
    if (value !== 'confirm') {
      this._pendingDeleteApplicantId = null
      return
    }
    const applicantId = this._pendingDeleteApplicantId
    this._pendingDeleteApplicantId = null
    if (!applicantId) return
    try {
      const result = await softDeleteApplicant({ applicantId })
      if (result?.isSuccess) {
        this.showToast('Success', result.message || 'Applicant removed.', 'success')
        window.dispatchEvent(new CustomEvent(LOS_MENU_REFRESH_EVENT, { bubbles: true, composed: true }))
      } else {
        this.showToast('Error', result?.message || 'Failed to remove applicant.', 'error')
      }
    } catch (err) {
      this.showToast('Error', err?.body?.message || err?.message || 'Failed to remove applicant.', 'error')
    }
  }

  handleRemoveModalClose() {
    this.showRemoveConfirmModal = false
    this.removeConfirmProps = {}
    this._pendingDeleteApplicantId = null
  }

  handleViewDetails(event) {
    event.stopPropagation()
    const applicantId = event.currentTarget?.dataset?.applicantId
    const tabLabel = event.currentTarget?.dataset?.tabLabel
    if (!applicantId || !tabLabel || !this.stagePhrase) return

    const applicant = this._findTile(applicantId)
    const isStagePast = applicant?.isStagePast || false

    const baseStagePhrase = (this.stagePhrase || '')
      .replace(/_Guarantor$/, '')
      .replace(/_Beneficiary$/, '')
      .replace(/_Co-Borrower$/, '')
      .replace(/_CoBorrower$/, '')
    const detailId = `${baseStagePhrase}_${tabLabel}_${applicantId}`
    const currentStagePhrase = `${baseStagePhrase}_${tabLabel}`

    window.dispatchEvent(new CustomEvent(LOS_MENU_SELECT_EVENT, {
      detail: {
        id: detailId,
        tab: this.tab,
        label: `${this.tab} - ${tabLabel}`,
        applicantId,
        applicantType: tabLabel,
        stagePhrase: currentStagePhrase,
        currentStagePhrase,
        isGroupItem: false,
        isStagePast,
        overrideLwc: this.overrideLwc || ''
      },
      bubbles: true,
      composed: true
    }))
  }

  // "+" sub tile: create/reuse an IN sub-applicant shell, then drill into its Basic Details.
  async handleAddSub(event) {
    event.stopPropagation()
    const parentApplicantId = event.currentTarget?.dataset?.applicantId
    if (!parentApplicantId || !this.stagePhrase) return
    try {
      const res = await createSubApplicantShell({ parentApplicantId })
      if (!res?.isSuccess || !res.subApplicantId) {
        this.showToast('Error', res?.message || 'Unable to add sub-applicant.', 'error')
        return
      }
      // Track the untouched shell so navigating away before Basic Details NEXT discards it.
      window.__mogaPendingSubShellId = res.subApplicantId
      const tabLabel = res.tabLabel
      const baseStagePhrase = (this.stagePhrase || '')
        .replace(/_Guarantor$/, '')
        .replace(/_Beneficiary$/, '')
        .replace(/_Co-Borrower$/, '')
        .replace(/_CoBorrower$/, '')
      const detailId = `${baseStagePhrase}_${tabLabel}_${res.subApplicantId}`
      const currentStagePhrase = `${baseStagePhrase}_${tabLabel}`
      window.dispatchEvent(new CustomEvent(LOS_MENU_SELECT_EVENT, {
        detail: {
          id: detailId,
          tab: this.tab,
          label: `${this.tab} - ${tabLabel}`,
          applicantId: res.subApplicantId,
          applicantType: tabLabel,
          stagePhrase: currentStagePhrase,
          currentStagePhrase,
          isGroupItem: false,
          isStagePast: false,
          overrideLwc: this.overrideLwc || ''
        },
        bubbles: true,
        composed: true
      }))
    } catch (err) {
      this.showToast('Error', err?.body?.message || err?.message || 'Unable to add sub-applicant.', 'error')
    }
  }

  // Primary switch (radio behaviour): clicking another applicant moves Primary to it. Exactly one stays Primary.
  async handleSetPrimary(event) {
    event.stopPropagation()
    const applicantId = event.currentTarget?.dataset?.applicantId
    if (!applicantId) return
    if (event.currentTarget?.disabled) return
    const currentlyOn = event.currentTarget?.dataset?.on === 'true'
    if (currentlyOn) return
    try {
      const res = await setPrimaryApplicant({ applicantId, value: true })
      if (res?.isSuccess) {
        window.dispatchEvent(new CustomEvent(LOS_MENU_REFRESH_EVENT, { bubbles: true, composed: true }))
      } else {
        this.showToast('Error', res?.message || 'Unable to update Primary.', 'error')
      }
    } catch (err) {
      this.showToast('Error', err?.body?.message || err?.message || 'Unable to update Primary.', 'error')
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }))
  }
}