/**
 * Make → Model → Variant options now come from the shared MMV master sample data,
 * filtered by the application's product-type token (SCV/LCV/MHCV/CE/PV/TW).
 */
export { getMakeOptions, getModelOptions, getVariantOptions } from 'c/mmvMasterData'

/** Deal Master API codes → picklist values */
export const DEAL_MASTER_MAKE_CODE_MAP = {
  AUDIAG: 'A DAYAL DRILLING PVT LTD',
  AMBASSADOR: 'AMBASSADOR'
}

export const DEAL_MASTER_MODEL_CODE_MAP = {
  AUDI3TDIQ: 'SHAKTI 100 CRAW DRIL ATL CORCO AC XAV216',
  AUDIA3CB: 'AUDI A3 CABRIOLET 40 TFSI',
  AUDIA6TD: 'AUDI A6 35 TDI TECHNOLOGY',
  HMAMB: 'HM AMBASSADOR',
  HMAMB2: 'HM AMBASSADOR 2DSZFSSAC'
}

export const DEAL_MASTER_VARIANT_CODE_MAP = {
  AUDIQ3PPN: 'SHAKTI 100 CRAW DRIL ATL CORCO AC XAV216',
  AUDIA3CB: 'AUDI A3 CABRIOLET 40 TFSI',
  AUDIA6TD: 'AUDI A6 35 TDI TECHNOLOGY',
  HMAMB: 'AMBASSADOR',
  HMAMB2: 'HM AMBASSADOR 2DSZFSSAC'
}

export function resolveMakeModelVariantFromDealMaster(dealMasterData) {
  if (!dealMasterData) {
    return { make: '', model: '', variant: '' }
  }
  const makeCode = dealMasterData.Make_Code || dealMasterData.makeCode || ''
  const modelCode = dealMasterData.Model_Code || dealMasterData.modelCode || ''
  const variantCode = dealMasterData.Variant_Code || dealMasterData.variantCode || ''
  return {
    make: DEAL_MASTER_MAKE_CODE_MAP[makeCode] || '',
    model: DEAL_MASTER_MODEL_CODE_MAP[modelCode] || '',
    variant: DEAL_MASTER_VARIANT_CODE_MAP[variantCode] || ''
  }
}

export function mapVahaanReportToFields(vahaanData) {
  if (!vahaanData) return {}
  const ownershipRaw = vahaanData.Number_of_Ownerships ?? vahaanData.numberOfOwnerships
  let numberOfOwnerships = ''
  if (ownershipRaw != null && String(ownershipRaw).trim() !== '') {
    const n = String(ownershipRaw).trim()
    numberOfOwnerships = n === '1' || n === '2' || n === '3' ? n : '>3'
  }
  return {
    lastOwnerName: vahaanData.Owner_Name || vahaanData.ownerName || '',
    chassisNumber: vahaanData.Chassis_No || vahaanData.chassisNo || '',
    engineNumber: vahaanData.Engine_No || vahaanData.engineNo || '',
    manufacturingYearMonth:
      vahaanData.Manufacture_Year_Month || vahaanData.manufactureYearMonth || '',
    numberOfOwnerships,
    insuranceExpiryDate: vahaanData.Ins_Expiry_Date || vahaanData.insExpiryDate || ''
  }
}

export function isVehicleDedupeProceedAllowed(dedupeData) {
  const content = dedupeData?.response?.content
  if (!Array.isArray(content) || content.length === 0) return false
  return content[0]?.Proceed_Flag === 'Y'
}

export const REGISTRATION_FORMAT_NEW = 'New Format (HR55AB1234)'
export const REGISTRATION_FORMAT_OLD = 'Old Format (HR-05-AB-1234)'

export const VEHICLE_SUB_CATEGORY_OPTIONS = [
  { label: 'Used - Broker Sale', value: 'Used - Broker Sale' },
  { label: 'Used - Open Market', value: 'Used - Open Market' },
  { label: 'Used - Pre-Owned', value: 'Used - Pre-Owned' },
  { label: 'Used - Repo Sale', value: 'Used - Repo Sale' }
]

export const VEHICLE_DEDUPE_DEFAULTS = {
  registrationFormat: '',
  vehicleSubCategory: '',
  registrationNumber: '',
  parentDealNumber: '',
  insuranceExpiryDate: ''
}

export const NUMBER_OF_OWNERSHIPS_OPTIONS = [
  { label: '1', value: '1' },
  { label: '2', value: '2' },
  { label: '3', value: '3' },
  { label: '>3', value: '>3' }
]

export const RC_RETENTION_APPLICABLE_OPTIONS = [
  { label: 'Yes', value: 'Yes' },
  { label: 'No', value: 'No' }
]

export const VEHICLE_DETAILS_DEFAULTS = {
  make: '',
  model: '',
  variant: '',
  invoiceInNameOf: '',
  manufacturingYearMonth: '',
  lastOwnerName: '',
  engineNumber: '',
  chassisNumber: '',
  numberOfOwnerships: '',
  rcRetentionApplicable: ''
}

export const DEALER_REGISTRATION_DEFAULTS = {
  dealerSubDealerName: '',
  rcLimitEnabledDealer: false,
  stateOfUtilizationOfAsset: '',
  districtOfUtilizationOfAsset: ''
}

export const DEALER_SUB_DEALER_OPTIONS = [
  { label: 'ABC Motors', value: 'ABC Motors' },
  { label: 'City Auto Hub', value: 'City Auto Hub' },
  { label: 'Prime Wheels', value: 'Prime Wheels' }
]

export const STATE_OF_UTILIZATION_OPTIONS = [
  { label: 'Assam', value: 'Assam' },
  { label: 'Maharashtra', value: 'Maharashtra' },
  { label: 'Karnataka', value: 'Karnataka' },
  { label: 'Delhi', value: 'Delhi' },
  { label: 'Gujarat', value: 'Gujarat' }
]

const DISTRICT_OPTIONS_BY_STATE = {
  Assam: [
    { label: 'Kamrup', value: 'Kamrup' },
    { label: 'Dibrugarh', value: 'Dibrugarh' },
    { label: 'Jorhat', value: 'Jorhat' },
    { label: 'Nagaon', value: 'Nagaon' },
    { label: 'Tinsukia', value: 'Tinsukia' }
  ],
  Maharashtra: [
    { label: 'Mumbai', value: 'Mumbai' },
    { label: 'Pune', value: 'Pune' },
    { label: 'Nagpur', value: 'Nagpur' },
    { label: 'Nashik', value: 'Nashik' },
    { label: 'Thane', value: 'Thane' }
  ],
  Karnataka: [
    { label: 'Bengaluru Urban', value: 'Bengaluru Urban' },
    { label: 'Mysuru', value: 'Mysuru' },
    { label: 'Belagavi', value: 'Belagavi' },
    { label: 'Dharwad', value: 'Dharwad' },
    { label: 'Shivamogga', value: 'Shivamogga' }
  ],
  Delhi: [
    { label: 'Central Delhi', value: 'Central Delhi' },
    { label: 'South Delhi', value: 'South Delhi' },
    { label: 'West Delhi', value: 'West Delhi' },
    { label: 'North Delhi', value: 'North Delhi' },
    { label: 'East Delhi', value: 'East Delhi' }
  ],
  Gujarat: [
    { label: 'Ahmedabad', value: 'Ahmedabad' },
    { label: 'Surat', value: 'Surat' },
    { label: 'Vadodara', value: 'Vadodara' },
    { label: 'Rajkot', value: 'Rajkot' },
    { label: 'Bhavnagar', value: 'Bhavnagar' }
  ]
}

export function getDistrictOptionsForState(state) {
  if (!state) return []
  return DISTRICT_OPTIONS_BY_STATE[state] ? [...DISTRICT_OPTIONS_BY_STATE[state]] : []
}

export const MAXIMUM_AVAILABLE_TENURE_MONTHS = 84

export const LOAN_INFORMATION_DEFAULTS = {
  requiredLoanAmount: '',
  requiredIrr: '',
  maximumAvailableTenure: String(MAXIMUM_AVAILABLE_TENURE_MONTHS),
  requiredTenure: '',
  fundingBasedOn: ''
}

/** Tenure options 1..maxTenure (months) */
export function getRequiredTenureOptions(maxTenure = MAXIMUM_AVAILABLE_TENURE_MONTHS) {
  const options = []
  for (let m = 1; m <= maxTenure; m += 1) {
    options.push({ label: String(m), value: String(m) })
  }
  return options
}