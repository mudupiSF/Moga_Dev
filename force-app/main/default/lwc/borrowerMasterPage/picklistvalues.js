/**
 * Hardcoded picklist values sourced from Option_Visibility__mdt custom metadata.
 * Format matches the Apex getProductTypeOptions() response: { label, value }
 * Sorted by Order_Sequence__c ASC.
 *
 * Option_Visibility__mdt records:
 * ┌──────────────────────────────┬──────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────────────┬────────────────┐
 * │ Product_Value__c             │ MasterLabel                      │ Profile_Name__c                                                                                               │ Order_Sequence │
 * ├──────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┼────────────────┤
 * │ Passenger Vehicles           │ Passenger Vehicles (PV)          │ System Administrator, IBL Business Executive, IBL Partner Community Counter Staff,                           │ 1              │
 * │                              │                                  │ IBL CVO, IBL Partner Community CVO, IBL Synergy Business Executive                                            │                │
 * ├──────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┼────────────────┤
 * │ Two Wheeler                  │ Two Wheeler (TW)                 │ System Administrator, IBL Business Executive TW, IBL Partner Community Marketing Agent,                      │ 2              │
 * │                              │                                  │ IBL Marketing Officer, IBL Partner Community Marketing Officer,                                               │                │
 * │                              │                                  │ IBL CVO, IBL Partner Community CVO, IBL Synergy Business Executive                                            │                │
 * ├──────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┼────────────────┤
 * │ Tractor                      │ Tractor (TFE)                    │ System Administrator, IBL Synergy Business Executive                                                          │ 3              │
 * ├──────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┼────────────────┤
 * │ Small Commercial Vehicle     │ Small Commercial Vehicle (SCV)   │ System Administrator, IBL Business Executive, IBL Partner Community Counter Staff,                           │ 4              │
 * │                              │                                  │ IBL CVO, IBL Partner Community CVO, IBL Synergy Business Executive                                            │                │
 * ├──────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┼────────────────┤
 * │ Light Commercial Vehicle     │ Light Commercial Vehicle (LCV)   │ System Administrator, IBL Business Executive, IBL Partner Community Counter Staff,                           │ 5              │
 * │                              │                                  │ IBL CVO, IBL Partner Community CVO, IBL Synergy Business Executive                                            │                │
 * └──────────────────────────────┴──────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────────────┴────────────────┘
 */

/** All product type options ordered by Order_Sequence__c ASC (full list, not profile-filtered). */
export const PRODUCT_TYPE_OPTIONS_ALL = [
    { label: 'Passenger Vehicles (PV)',        value: '4W',        orderSequence: 1 },
    { label: 'Two Wheeler (TW)',               value: '2W',               orderSequence: 2 },
    { label: 'Tractor (TFE)',                  value: 'Tractor',                   orderSequence: 3 },
    { label: 'Small Commercial Vehicle (SCV)', value: 'Small Commercial Vehicle',  orderSequence: 4 },
    { label: 'Light Commercial Vehicle (LCV)', value: 'Light Commercial Vehicle',  orderSequence: 5 }
];

/**
 * Profile → allowed product type values mapping.
 * Derived from Profile_Name__c column in Option_Visibility__mdt.
 */
export const PRODUCT_TYPE_PROFILE_MAP = {
    'System Administrator': [
        'Passenger Vehicles',
        'Two Wheeler',
        'Tractor',
        'Small Commercial Vehicle',
        'Light Commercial Vehicle'
    ],
    'IBL Business Executive': [
        'Passenger Vehicles',
        'Small Commercial Vehicle',
        'Light Commercial Vehicle'
    ],
    'IBL Business Executive TW': [
        'Two Wheeler'
    ],
    'IBL Marketing Officer': [
        'Two Wheeler'
    ],
    'IBL Partner Community Marketing Agent': [
        'Two Wheeler'
    ],
    'IBL Partner Community Marketing Officer': [
        'Two Wheeler'
    ],
    'IBL Partner Community Counter Staff': [
        'Passenger Vehicles',
        'Small Commercial Vehicle',
        'Light Commercial Vehicle'
    ],
    'IBL CVO': [
        'Passenger Vehicles',
        'Two Wheeler',
        'Small Commercial Vehicle',
        'Light Commercial Vehicle'
    ],
    'IBL Partner Community CVO': [
        'Passenger Vehicles',
        'Two Wheeler',
        'Small Commercial Vehicle',
        'Light Commercial Vehicle'
    ],
    'IBL Synergy Business Executive': [
        'Passenger Vehicles',
        'Two Wheeler',
        'Tractor',
        'Small Commercial Vehicle',
        'Light Commercial Vehicle'
    ]
};

/**
 * Returns the product type options filtered for a given profile name.
 * Falls back to the full list when no profile match is found.
 *
 * @param {string} profileName - Current user's profile name.
 * @returns {{ label: string, value: string }[]}
 */
export function getProductTypeOptionsForProfile(profileName) {
    const allowedValues = PRODUCT_TYPE_PROFILE_MAP[profileName];
    if (!allowedValues) return [...PRODUCT_TYPE_OPTIONS_ALL];
    return PRODUCT_TYPE_OPTIONS_ALL.filter(opt => allowedValues.includes(opt.value));
}

export const CUSTOMER_TYPE_OPTIONS = [
    { label: 'Non-Individual', value: 'Non-Individual' },
    { label: 'Individual', value: 'Individual' }
];
export const NUMBER_OF_VEHICLES_OPTIONS = [
    { label: 'Single Vehicle', value: 'Single' },
    { label: 'Multiple Vehicles', value: 'Multiple' }
];

export const VEHICLE_TYPE_OPTIONS = [
    { label: 'New', value: 'New' },
    { label: 'Refinance', value: 'Refinance' }
];
export const APPLICATION_TYPE_OPTIONS = [
    { label: 'Individual', value: 'Individual' },
    { label: 'Non-Individual', value: 'Non-Individual' }
];
export const SEGMENT_OPTIONS = [
    { label: 'Motorcycle', value: 'MOTORCYC' },
    { label: 'Scooter',    value: 'SCOOTER' },
    { label: 'Moped',      value: 'MOPEDS' },
    { label: 'E-Scooter',  value: 'ESCOOTER' },
    { label: 'Hi-Street',  value: 'HISTREET' },
    { label: 'Hi-End',     value: 'HIENDBIKE' }
];
/**
 * Convenience export: full list as { label, value } — matches the format
 * returned by sfLOSDirectLoanCreationController.getProductTypeOptions() when
 * the current user has access to all options (e.g. System Administrator).
 */
export const productTypeOptions = PRODUCT_TYPE_OPTIONS_ALL.map(({ label, value }) => ({ label, value }));