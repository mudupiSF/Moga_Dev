export const LOS_NEXT_STAGE_EVENT = 'losnextstage'
export const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader'
export const STAGE_INVESTIGATION_REPORTS = 'Investigation Reports'

export const APEX_CLASS = 'InvestigationDetailsController'
export const ACTION_GET_INVESTIGATION_RECORDS = 'getInvestigationRecords'
export const CUSTOMER_EXPOSURE_HANDLER = 'clientLayerCustomerExposure'
export const EMPTY_CELL_VALUE = '—'
export const EMPTY_SECTION_MESSAGE = 'No records found.'

export const PAGE_SIZE = 5

export const FI_LABEL_COMPONENT_MAP = {
  'Current Residence FI': 'residenceFI',
  'Permanent Residence FI': 'permanentFI',
  'Registered Address FI': 'permanentFI',
  'Office FI': 'officeFI',
  'AML Investigation': 'amlCheckScreen',
  AML: 'amlCheckScreen'
}

export const FI_TABLE_COLUMNS = [
  { key: 'name', label: 'FI Type', fieldName: 'name', type: 'link' },
  { key: 'applicantName', label: 'Applicant Name', fieldName: 'applicantName', type: 'text' },
  { key: 'applicantType', label: 'Applicant Type', fieldName: 'applicantType', type: 'text' },
  { key: 'status', label: 'Status', fieldName: 'status', type: 'status' }
]

export const FCU_TABLE_COLUMNS = [
  { key: 'name', label: 'Report Name', fieldName: 'name', type: 'link' },
  { key: 'applicantName', label: 'Applicant Name', fieldName: 'applicantName', type: 'text' },
  { key: 'applicantType', label: 'Applicant Type', fieldName: 'applicantType', type: 'text' },
  { key: 'status', label: 'Status', fieldName: 'status', type: 'status' }
]

export const AML_TABLE_COLUMNS = [
  { key: 'name', label: 'Report Name', fieldName: 'name', type: 'link' },
  { key: 'applicantName', label: 'Applicant Name', fieldName: 'applicantName', type: 'text' },
  { key: 'applicantType', label: 'Applicant Type', fieldName: 'applicantType', type: 'text' },
  { key: 'status', label: 'Status', fieldName: 'status', type: 'status' }
]

export const SECTION_DEFINITIONS = [
  {
    id: 'fi',
    label: 'FI',
    description: 'Field investigation reports by address type',
    icon: 'utility:home',
    iconVariant: 'fi',
    investigationType: 'FI',
    tableColumns: FI_TABLE_COLUMNS
  },
  {
    id: 'fcu',
    label: 'FCU',
    description: 'Financial credit verification reports',
    icon: 'utility:currency',
    iconVariant: 'fcu',
    investigationType: 'FCU',
    tableColumns: FCU_TABLE_COLUMNS
  },
  {
    id: 'aml',
    label: 'AML',
    description: 'Anti-money laundering screening reports',
    icon: 'utility:shield',
    iconVariant: 'aml',
    investigationType: 'AML',
    tableColumns: AML_TABLE_COLUMNS
  }
]

export const DEFAULT_ACTIVE_SECTION_ID = SECTION_DEFINITIONS[0]?.id || ''