export const APEX_CLASS = 'ApprovalLogController'
export const ACTION_GET_APPROVAL_LOGS = 'getApprovalLogs'
export const ACTION_GET_APPROVAL_LOG_USER_CONTEXT = 'getApprovalLogUserContext'
export const ACTION_CREATE_FORWARD_LOG = 'createForwardLog'
export const ACTION_GET_LOAN_TERM_GROUPS = 'getLoanTermGroups'

export const MSG_LOAD_FAILED = 'Unable to load approval logs.'
export const MSG_FORWARD_SAVE_SUCCESS = 'Proposal forwarded successfully.'
export const MSG_FORWARD_SAVE_FAILED = 'Unable to forward proposal.'
export const MSG_DEVIATIONS_LOAD_FAILED = 'Unable to load deviation approvals.'
export const MSG_DEVIATIONS_NOT_APPROVED = 'All deviations must be approved before proceeding.'
export const MSG_CIBIL_IN_PROGRESS = 'Please wait for CIBIL verification to complete.'
export const MSG_NAVIGATION_VIEW_MISSING = 'Current view ID is missing. Please refresh the page.'

export const DEVIATION_APEX_CLASS = 'DeviationController'
export const ACTION_GET_DEVIATIONS = 'getDeviations'
export const APPROVAL_STATUS_APPROVED = 'Approved'

export const LOS_NEXT_STAGE_EVENT = 'losnextstage'
export const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader'
export const STAGE_TAB_DEFAULT = 'CAM and Approval Log'

export const YES_NO_OPTIONS = [
  { label: 'Yes', value: 'Yes' },
  { label: 'No', value: 'No' }
]

export const ACTION_ID_INSURANCE = 'insurance'
export const ACTION_ID_PAYIN = 'payin'
export const ACTION_ID_SCHEDULE = 'schedule'
export const ACTION_ID_DOWNLOAD_CAM = 'pdf'

export const ACTION_BUTTONS = [
  { id: ACTION_ID_INSURANCE, label: 'Insurance Recompute', iconName: 'utility:shield' },
  { id: ACTION_ID_PAYIN, label: 'Change Pay-ins / Pay-outs', iconName: 'utility:currency' },
  { id: ACTION_ID_SCHEDULE, label: 'Installment Schedule', iconName: 'utility:date_time' },
  { id: ACTION_ID_DOWNLOAD_CAM, label: 'Download CAM', iconName: 'utility:download' }
]

export const GLOBAL_ACTION_BUTTONS = [
  { id: ACTION_ID_DOWNLOAD_CAM, label: 'Download CAM', iconName: 'utility:download' }
]

export const ASSET_ACTION_BUTTONS = [
  { id: ACTION_ID_INSURANCE, label: 'Insurance Recompute', iconName: 'utility:shield' },
  { id: ACTION_ID_PAYIN, label: 'Change Pay-In', iconName: 'utility:currency' },
  { id: ACTION_ID_SCHEDULE, label: 'Installment Schedule', iconName: 'utility:date_time' }
]

export const FORWARD_LOG_HEADERS = [
  { key: 'from', label: 'Forwarded From' },
  { key: 'to', label: 'Forwarded To' },
  { key: 'date', label: 'Date & Time' },
  { key: 'remarks', label: 'Remarks' }
]

export const APPROVAL_HISTORY_HEADERS = [
  { key: 'role', label: 'Role' },
  { key: 'user', label: 'User' },
  { key: 'action', label: 'Action' },
  { key: 'date', label: 'Date & Time' },
  { key: 'remarks', label: 'Remarks' }
]

export const FORWARD_PROPOSAL_NO = 'No'
export const FORWARD_PROPOSAL_YES = 'Yes'
export const CIBIL_CONSENT_YES = 'Yes'

export const FORWARD_TO_OPTIONS = [
  { label: 'SCM', value: 'SCM' },
  { label: 'HHEAD', value: 'HHEAD' },
  { label: 'NCM', value: 'NCM' },
  { label: 'CVO', value: 'CVO' },
  { label: 'BE', value: 'BE' },
]

export const DECISION_OPTIONS = [
  { label: 'Accept', value: 'Accept' },
  { label: 'Reject', value: 'Reject' }
]

export const DECISION_ACCEPT = 'Accept'
export const DECISION_REJECT = 'Reject'

export const APPROVAL_CONDITIONS_HEADERS = [
  { key: 'sno', label: 'ID' },
  { key: 'approvalCondition', label: 'Approval Condition' },
  { key: 'action', label: 'Action' },
  { key: 'remarks', label: 'Remarks' },
  { key: 'submit', label: 'Action' }
]

export const APPROVAL_CONDITION_ACTION_OPTIONS = [
  { label: 'Action Taken', value: 'Action Taken' },
  { label: 'Action Not Taken', value: 'Action Not Taken' }
]

export const PROPOSAL_STATUS_OPTIONS = [
  { label: 'Approve', value: 'Approve' },
  { label: 'Conditionally Approve', value: 'Conditionally Approve' },
  { label: 'Reject', value: 'Reject' },
  { label: 'Hold', value: 'Hold' }
]

export const RS_PREFIX = 'Rs. '

export const EMPTY_LOAN_TERMS = {
  decisionFieldsDecision: '',
  decisionFieldsRemarks: '',
  proposalRejectedByAuthority: '',
  vehicleVariant: '',
  loanAmount: '',
  netIRR: '',
  imputedIRR: '',
  crmIRR: '',
  fundedPremium: '',
  grossIRR: '',
  monthlyEMI: '',
  loanTenure: '',
  secondEMIDueDate: ''
}

export const FINAL_LOAN_TERMS_BECVO = [
  //{ id: 'fltl-decision', label: 'Decision', termKey: 'decisionFieldsDecision' },
  //{ id: 'fltl-remarks', label: 'Remarks', termKey: 'decisionFieldsRemarks' },
  {
    id: 'fltl-rejected',
    label: 'Proposal Rejected by any authority',
    termKey: 'proposalRejectedByAuthority'
  },
  //{ id: 'fltl-variant', label: 'Vehicle Variant', termKey: 'vehicleVariant' },
  { id: 'fltl-loan', label: 'Loan Amount', inputType: 'loanAmount' },
  { id: 'fltl-net-irr', label: 'Net IRR', termKey: 'netIRR' },
  { id: 'fltl-imputed-irr', label: 'Imputed IRR', termKey: 'imputedIRR' },
  { id: 'fltr-crm-irr', label: 'CRM IRR', inputType: 'crmIrr' },
  { id: 'fltr-funded', label: 'Funded Premium', termKey: 'fundedPremium', useRsPrefix: true },
  { id: 'fltr-gross-irr', label: 'Gross IRR', termKey: 'grossIRR' },
  { id: 'fltr-emi', label: 'EMI', termKey: 'monthlyEMI', useRsPrefix: true },
  { id: 'fltr-tenure', label: 'Tenure', termKey: 'loanTenure' },
  { id: 'fltr-first-emi', label: '1st EMI Due Date', inputType: 'emiCombobox' },
  { id: 'fltr-second-emi', label: '2nd EMI Due Date', termKey: 'secondEMIDueDate' }
]

export const CVO_BE_ROLES = ['CVO', 'BE']

export const HIGHER_AUTHORITY_ROLES = ['MA', 'MO']