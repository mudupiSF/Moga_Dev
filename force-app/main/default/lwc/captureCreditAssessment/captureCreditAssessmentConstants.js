export const LOS_NEXT_STAGE_EVENT = 'losnextstage'
export const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader'
export const STAGE_CREDIT_ASSESSMENT = 'Credit Assessment'
export const APEX_CLASS = 'CaptureCreditAssessmentController'
export const APEX_PD_CLASS = 'PdController'
export const ACTION_CREATE_PD_RECORDS = 'createPdRecords'
export const ACTION_GET_CREDIT_ASSESSMENT = 'getCreditAssessment'
export const ACTION_SAVE_CREDIT_ASSESSMENT = 'saveCreditAssessment'
export const ACTION_FETCH_NIC_MASTER = 'fetchNicMasterData'

export const PARAM_APPLICANT_ID = 'applicantId'
export const PARAM_REMARKS = 'remarks'
export const PARAM_NIC_CODE = 'nicCode'
export const PARAM_PSL = 'psl'

export const CLIENT_LAYER_DEVIATION = 'clientLayerDeviation'
export const DEVIATION_SUBMODULE_FLOW = 'onCreditAssessmentDeviationFlow'
export const INTEGRATION_PROGRESS_EVENT = 'integrationprogressupdate'

export const PSL_SUB_TYPE_MSME = 'MSME'
export const PSL_SUB_TYPE_AGRI = 'Agri'
export const LOAN_CAT_PSL = 'PSL'
export const LOAN_CAT_NON_PSL = 'Non-PSL'

export const AUDIT_RADIO_OPTIONS = [
    { label: 'Audited', value: 'Audited' },
    { label: 'Unaudited', value: 'Unaudited' }
]

export const AUDIT_RADIO_PROJECTED_OPTIONS = [
    { label: 'Audited', value: 'Audited' },
    { label: 'Unaudited', value: 'Unaudited' },
    { label: 'Projected', value: 'Projected' }
]

export const END_USE_OPTIONS = [
    { label: 'Purchase of Equipment /Vehicle', value: 'Purchase of Equipment /Vehicle' },
    { label: 'Working capital (For Refinance)', value: 'Working capital (For Refinance)' },
    {
        label: 'Margin money for purchase of vehicles (For Refinance)',
        value: 'Margin money for purchase of vehicles (For Refinance)'
    }
]

export const LOAN_CATEGORIZATION_OPTIONS = [
    { label: 'PSL', value: LOAN_CAT_PSL },
    { label: 'Non-PSL', value: LOAN_CAT_NON_PSL }
]

export const NON_PSL_CATEGORIZATION_OPTIONS = [
    { label: 'N1: Traders Retail-Non-MSME', value: 'N1: Traders Retail-Non-MSME' },
    { label: 'N2: Traders Wholesale-Non-MSME', value: 'N2: Traders Wholesale-Non-MSME' },
    {
        label: 'N3: COMMERCIAL & INDUSTRIAL SECTOR (MANUFACTURING)',
        value: 'N3: COMMERCIAL & INDUSTRIAL SECTOR (MANUFACTURING)'
    },
    {
        label: 'N4: COMMERCIAL & INDUSTRIAL SECTOR (SERVICES)',
        value: 'N4: COMMERCIAL & INDUSTRIAL SECTOR (SERVICES)'
    },
    { label: 'N5: NPSL Others', value: 'N5: NPSL Others' }
]

export const PSL_SUB_TYPE_OPTIONS = [
    { label: 'MSME', value: PSL_SUB_TYPE_MSME },
    { label: 'Agri', value: PSL_SUB_TYPE_AGRI }
]

export const TYPE_OF_ACTIVITY_OPTIONS = [
    { label: 'Manufacturing', value: 'Manufacturing' },
    { label: 'Services', value: 'Services' },
    { label: 'Trading', value: 'Trading' }
]

export const TYPE_OF_ENTERPRISE_OPTIONS = [
    { label: 'Micro', value: 'Micro' },
    { label: 'Small', value: 'Small' },
    { label: 'Medium', value: 'Medium' }
]

export const GST_STATUS_OPTIONS = [
    { label: 'Available', value: 'Available' },
    { label: 'Applied For', value: 'Applied For' },
    { label: 'Exempted', value: 'Exempted' }
]

export const AGRI_TYPE_OPTIONS = [
    { label: 'Crop Production', value: 'Crop Production' },
    { label: 'Animal Husbandry', value: 'Animal Husbandry' },
    { label: 'Fisheries', value: 'Fisheries' }
]

export const BORROWER_CATEGORY_OPTIONS = [
    { label: 'Marginal Farmer', value: 'Marginal Farmer' },
    { label: 'Small Farmer', value: 'Small Farmer' },
    { label: 'Other Farmer', value: 'Other Farmer' }
]

export const ACRE_CATEGORY_OPTIONS = [
    {
        label: '> 2.47 acres to 4.94 acres - individual',
        value: '> 2.47 acres to 4.94 acres - individual'
    },
    { label: 'upto 2.47 acres - individual', value: 'upto 2.47 acres - individual' },
    {
        label: 'Tenant Farmers/ Sharecroppers/ Oral lessees - no own land',
        value: 'Tenant Farmers/ Sharecroppers/ Oral lessees - no own land'
    },
    {
        label: 'Other (Medium and Large) - > 4.94 acres - individual',
        value: 'Other (Medium and Large) - > 4.94 acres - individual'
    },
    {
        label: 'Other borrowers engaged in agriculture and allied activities',
        value: 'Other borrowers engaged in agriculture and allied activities'
    }
]

export const PRODUCT_TYPE_PV = 'PV'
export const PRODUCT_TYPE_CV = 'CV'

export const UDHYAM_DOCUMENT_TYPE = 'Udhyam Registration Certificate'
export const UDHYAM_DOCUMENT_CATEGORY = 'Credit Assessment'
export const UDHYAM_ACCEPTED_FORMATS = '.pdf,.jpg,.jpeg,.png'

export const NIC_GROUP_OPTIONS = [
    { label: 'A - Agriculture', value: 'A' },
    { label: 'C - Manufacturing', value: 'C' },
    { label: 'G - Wholesale and retail trade', value: 'G' }
]

export const NIC_CLASS_OPTIONS = [
    { label: '01 - Crop and animal production', value: '01' },
    { label: '10 - Food products', value: '10' },
    { label: '45 - Motor vehicle trade', value: '45' }
]

export const NIC_SUB_CLASS_OPTIONS = [
    { label: '011 - Growing of cereals', value: '011' },
    { label: '101 - Processing of meat', value: '101' },
    { label: '451 - Sale of motor vehicles', value: '451' }
]

export function getLastThreeFinancialYearRanges(referenceDate = new Date()) {
    const currentYear = referenceDate.getFullYear()
    return [
        `${currentYear - 1}-${currentYear}`,
        `${currentYear - 2}-${currentYear - 1}`,
        `${currentYear - 3}-${currentYear - 2}`
    ]
}

export function buildDefaultInvestmentRows(referenceDate = new Date()) {
    const [latestYear, middleYear, oldestYear] = getLastThreeFinancialYearRanges(referenceDate)
    return [
        {
            id: 'inv-1',
            yearRange: latestYear,
            amount: '',
            audited: '',
            options: AUDIT_RADIO_PROJECTED_OPTIONS
        },
        {
            id: 'inv-2',
            yearRange: middleYear,
            amount: '',
            audited: '',
            options: AUDIT_RADIO_OPTIONS
        },
        {
            id: 'inv-3',
            yearRange: oldestYear,
            amount: '',
            audited: '',
            options: AUDIT_RADIO_OPTIONS
        }
    ]
}

export function buildDefaultTurnoverRows(referenceDate = new Date()) {
    const [latestYear, middleYear, oldestYear] = getLastThreeFinancialYearRanges(referenceDate)
    return [
        {
            id: 'to-1',
            yearRange: latestYear,
            amount: '',
            audited: '',
            options: AUDIT_RADIO_PROJECTED_OPTIONS
        },
        {
            id: 'to-2',
            yearRange: middleYear,
            amount: '',
            audited: '',
            options: AUDIT_RADIO_OPTIONS
        },
        {
            id: 'to-3',
            yearRange: oldestYear,
            amount: '',
            audited: '',
            options: AUDIT_RADIO_OPTIONS
        }
    ]
}