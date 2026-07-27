export const TAB_DEVIATIONS = 'deviations'
export const TAB_CAM = 'cam'
export const TAB_APPROVAL_LOG_PAGE = 'approvalLogPage'

export const APEX_CLASS = 'CamAndApprovalLogController'
export const ACTION_GET_PROPOSAL_SECTION = 'getProposalSectionData'

export const WORKSPACE_TABS = [
  { value: TAB_CAM, label: 'CAM', tabId: 'camal-tab-cam', panelId: 'camal-panel-cam' },
  {
    value: TAB_DEVIATIONS,
    label: 'Deviations',
    tabId: 'camal-tab-deviations',
    panelId: 'camal-panel-deviations'
  },
  {
    value: TAB_APPROVAL_LOG_PAGE,
    label: 'Approval Logs',
    tabId: 'camal-tab-approval-log',
    panelId: 'camal-panel-approval-log'
  }
]

export const EMPTY_PROPOSAL_SECTION = {
  statusLabel: '—'
}