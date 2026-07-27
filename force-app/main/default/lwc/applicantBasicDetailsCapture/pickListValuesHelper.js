/** Product type options from Option_Visibility__mdt (Order_Sequence__c ASC). */
export const PRODUCT_TYPE_OPTIONS_ALL = [
    { label: 'Passenger Vehicles (PV)', value: '4W', orderSequence: 1 },
    { label: 'Two Wheeler (TW)', value: '2W', orderSequence: 2 },
    { label: 'Tractor (TFE)', value: 'Tractor', orderSequence: 3 },
    { label: 'Small Commercial Vehicle (SCV)', value: 'Small Commercial Vehicle', orderSequence: 4 },
    { label: 'Light Commercial Vehicle (LCV)', value: 'Light Commercial Vehicle', orderSequence: 5 }
];

export const CUSTOMER_TYPE_OPTIONS = [
    { label: 'Individual', value: 'Individual' },
    { label: 'Non-Individual', value: 'Non-Individual' }
];

export const SEGMENT_OPTIONS = [
    { label: 'Motorcycle', value: 'MOTORCYC' },
    { label: 'Scooter', value: 'SCOOTER' },
    { label: 'Moped', value: 'MOPEDS' },
    { label: 'E-Scooter', value: 'ESCOOTER' },
    { label: 'Hi-Street', value: 'HISTREET' },
    { label: 'Hi-End', value: 'HIENDBIKE' }
];

export const VEHICLE_TYPE_OPTIONS_DEFAULT = [
    { label: 'New', value: 'New' },
    { label: 'Used', value: 'Used' },
    { label: 'Refinance', value: 'Refinance' }
];

export const VEHICLE_TYPE_OPTIONS_TWO_WHEELER = [
    { label: 'New', value: 'New' },
    { label: 'Refinance', value: 'Refinance' }
];