export const PRODUCT_CV = 'CV'
export const CALCULATION_BASIS_HOURLY = 'Hourly'
export const CALCULATION_BASIS_KMS = 'KMS'

export const CV_HOURLY_INCOME_KEYS = [
  'assetDeployment',
  'daysPerMonth',
  'hoursPerDay',
  'ratePerHour',
  'estimatedMonthlyIncome'
]

export const CV_HOURLY_EXPENSE_KEYS = [
  'fuelCostPerLitre',
  'fuelConsumptionPerHour',
  'costFuelPerMonth',
  'operatorSalary',
  'maintenanceParts',
  'tyreCost',
  'taxCess',
  'others',
  'totalExpenses',
  'grossSurplus',
  'instalment',
  'netSurplus'
]

export const KMS_INCOME_KEYS = [
  'vehicleRoute',
  'fromLocation',
  'toLocation',
  'tripsPerMonth',
  'kilometersPerTrip',
  'averageRatePerTrip',
  'estimatedMonthlyIncome'
]

export const KMS_EXPENSE_KEYS = [
  'fuelRatePerLitre',
  'costFuelPerTrip',
  'costFuelPerMonth',
  'salaries',
  'maintenance',
  'tyreCost',
  'motorTaxPermitCost',
  'others',
  'totalExpenses',
  'grossSurplus',
  'instalment',
  'netSurplus'
]

export const BASE_VIABILITY_DEFAULTS = {
  distance: '',
  grossReceiptsMonth: '',
  numberOfVehiclesOwned: '',
  expense: '',
  vehicleRoute: '',
  viabilityRatio: ''
}

export const CV_HOURLY_DEFAULTS = {
  assetDeployment: '',
  daysPerMonth: '',
  hoursPerDay: '',
  ratePerHour: '',
  estimatedMonthlyIncome: '',
  fuelCostPerLitre: '',
  fuelConsumptionPerHour: '',
  costFuelPerMonth: '',
  operatorSalary: '',
  maintenanceParts: '',
  tyreCost: '',
  taxCess: '',
  others: '',
  totalExpenses: '',
  grossSurplus: '',
  instalment: '',
  netSurplus: '',
  viabilityRatio: ''
}

export const KMS_DEFAULTS = {
  vehicleRoute: '',
  fromLocation: '',
  toLocation: '',
  tripsPerMonth: '',
  kilometersPerTrip: '',
  averageRatePerTrip: '',
  estimatedMonthlyIncome: '',
  fuelRatePerLitre: '',
  costFuelPerTrip: '',
  costFuelPerMonth: '',
  salaries: '',
  maintenance: '',
  tyreCost: '',
  motorTaxPermitCost: '',
  others: '',
  totalExpenses: '',
  grossSurplus: '',
  instalment: '',
  netSurplus: '',
  viabilityRatio: ''
}