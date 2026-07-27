/**
 * Make → Model → Variant options now come from the shared MMV master sample data,
 * filtered by the application's product-type token (SCV/LCV/MHCV/CE/PV/TW).
 * Dependency chain: Make → Model → Variant
 */
export {
  getMakeOptions,
  getModelOptions,
  getVariantOptions,
  getMakeLabel,
  getModelLabel,
  getVariantLabel
} from 'c/mmvMasterData'

export const MAXIMUM_AVAILABLE_TENURE_MONTHS = 84

export const LOAN_INFORMATION_DEFAULTS = {
  requiredLoanAmount: '',
  requiredIrr: '',
  maximumAvailableTenure: String(MAXIMUM_AVAILABLE_TENURE_MONTHS),
  requiredTenure: '',
  fundingBasedOn: ''
}

export const DEALER_REGISTRATION_DEFAULTS = {
  dealerSubDealerName: '',
  rcLimitEnabledDealer: false,
  invoiceInNameOf: '',
  vehicleRegisteredInNameOf: 'Borrower',
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

/** Tenure options 1..maxTenure (months) */
export function getRequiredTenureOptions(maxTenure = MAXIMUM_AVAILABLE_TENURE_MONTHS) {
  const options = []
  for (let m = 1; m <= maxTenure; m += 1) {
    options.push({ label: String(m), value: String(m) })
  }
  return options
}

export function getDistrictOptionsForState(state) {
  if (!state) return []
  return DISTRICT_OPTIONS_BY_STATE[state] ? [...DISTRICT_OPTIONS_BY_STATE[state]] : []
}