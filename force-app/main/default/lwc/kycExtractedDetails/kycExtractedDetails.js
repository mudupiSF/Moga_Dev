import { LightningElement, api, track } from 'lwc';
import getCityStateFromPinCode from '@salesforce/apex/GenericUtility.getCityStateFromPinCode';

// OCR-derived fields that should never be hand-edited.
const OCR_READONLY_FIELDS = new Set(['docNumber', 'poi', 'doi', 'gender', 'dob']);

// Documents that legitimately have no Date of Expiry. UIDAI eKYC for Aadhaar
const DOE_OPTIONAL_DOCS = new Set(['Voter ID', 'Voter Id', 'Voter ID Card',
                                   'Aadhaar', 'Aadhaar Card', 'Aadhar', 'Aadhar Card']);
const DOI_OPTIONAL_DOCS = new Set(['Aadhaar', 'Aadhaar Card', 'Aadhar', 'Aadhar Card']);
const POI_OPTIONAL_DOCS = new Set(['Aadhaar', 'Aadhaar Card', 'Aadhar', 'Aadhar Card']);

// Per-field optional registry — keyed by extracted-detail field key.
const OPTIONAL_BY_DOC_TYPE = {
    doe: DOE_OPTIONAL_DOCS,
    doi: DOI_OPTIONAL_DOCS,
    poi: POI_OPTIONAL_DOCS
};

export default class KycExtractedDetails extends LightningElement {
    @api isExtracting       = false;
    @api selectedKycDoc     = 'Document';
    @api extractedDetails;
    @api isReadOnly         = false;
    @api addressSectionLabel = '';

    @track editedValues = {};

    // ── State / visibility ───────────────────────────────────────────────────
    get hasDetails()    { return this.extractedDetails != null; }
    get showSection()   { return this.isExtracting || this.hasDetails; }
    get showDetails()   { return !this.isExtracting && this.hasDetails; }

    get containerClass() {
        return this.isExtracting
            ? 'kyc-ext-container kyc-ext-extracting'
            : 'kyc-ext-container kyc-ext-extracted';
    }
    get headerClass() {
        return this.isExtracting
            ? 'kyc-ext-header-title kyc-ext-title-extracting'
            : 'kyc-ext-header-title kyc-ext-title-extracted';
    }

    // ── Field value getters ──────────────────────────────────────────────────
    getFieldValue(fieldKey) {
        if (this.isReadOnly) {
            return this.extractedDetails?.[fieldKey] || '';
        }
        return this.editedValues[fieldKey] !== undefined
            ? this.editedValues[fieldKey]
            : (this.extractedDetails?.[fieldKey] || '');
    }
    get firstNameValue() { return this.getFieldValue('firstName'); }
    get lastNameValue()  { return this.getFieldValue('lastName');  }
    get genderValue()    { return this.getFieldValue('gender');    }
    get dobValue()       { return this.getFieldValue('dob');       }
    get doiValue()       { return this.getFieldValue('doi');       }
    get doeValue()       { return this.getFieldValue('doe');       }
    get address1Value()  { return this.getFieldValue('address1');  }
    get address2Value()  { return this.getFieldValue('address2');  }
    get pinValue()       { return this.getFieldValue('pin');       }
    get cityValue()      { return this.getFieldValue('city');      }
    get stateValue()     { return this.getFieldValue('state');     }
    get docNumberValue() { return this.getFieldValue('docNumber'); }
    get poiValue()       { return this.getFieldValue('poi');       }

    // ── Dynamic input classes ────────────────────────────────────────────────
    isFieldFilled(fieldKey) {
        const value = this.getFieldValue(fieldKey);
        return value && String(value).trim().length > 0;
    }
    isFieldReadOnlyByDefault(fieldKey) {
        return OCR_READONLY_FIELDS.has(fieldKey);
    }
    isFieldOptionalForCurrentDoc(fieldKey) {
        const docSet = OPTIONAL_BY_DOC_TYPE[fieldKey];
        return docSet ? docSet.has(this.selectedKycDoc) : false;
    }
    getInputClassForField(fieldKey) {
        const base = 'kyc-ext-input';
        const lockedByForm  = this.isReadOnly;
        const lockedByField = this.isFieldReadOnlyByDefault(fieldKey);
        let classes = (lockedByForm || lockedByField)
            ? `${base} kyc-ext-input--readonly`
            : base;
       
        if (!lockedByForm
            && !lockedByField
            && !this.isFieldFilled(fieldKey)
            && !this.isFieldOptionalForCurrentDoc(fieldKey)) {
            classes += ' kyc-ext-input--empty';
        }
        return classes;
    }
    getValueDisplayClassForField(fieldKey) {
        const hasValue = this.isFieldFilled(fieldKey);
        if (!hasValue && this.isFieldOptionalForCurrentDoc(fieldKey)) {
            return 'kyc-ext-value';
        }
        return hasValue ? 'kyc-ext-value' : 'kyc-ext-value kyc-ext-value--empty';
    }

    get firstNameInputClass() { return this.getInputClassForField('firstName'); }
    get lastNameInputClass()  { return this.getInputClassForField('lastName');  }
    get genderInputClass()    { return 'kyc-ext-input kyc-ext-input--readonly'; }
    get dobInputClass()       { return 'kyc-ext-input kyc-ext-input--readonly'; }
    get doiInputClass()       { return this.getInputClassForField('doi');       }
    get doeInputClass()       { return this.getInputClassForField('doe');       }
    get address1InputClass()  { return this.getInputClassForField('address1');  }
    get address2InputClass()  { return this.getInputClassForField('address2');  }
    get pinInputClass()       { return this.getInputClassForField('pin');       }
    get cityInputClass()      { return this.getInputClassForField('city');      }
    get stateInputClass()     { return this.getInputClassForField('state');     }
    get docNumberInputClass() { return 'kyc-ext-input kyc-ext-input--readonly'; }
    get poiInputClass()       { return this.getInputClassForField('poi');       }

    get firstNameDisplayClass() { return this.getValueDisplayClassForField('firstName'); }
    get lastNameDisplayClass()  { return this.getValueDisplayClassForField('lastName');  }
    get genderDisplayClass()    { return this.getValueDisplayClassForField('gender');    }
    get dobDisplayClass()       { return this.getValueDisplayClassForField('dob');       }
    get doiDisplayClass()       { return this.getValueDisplayClassForField('doi');       }
    get doeDisplayClass()       { return this.getValueDisplayClassForField('doe');       }
    get address1DisplayClass()  { return this.getValueDisplayClassForField('address1');  }
    get address2DisplayClass()  { return this.getValueDisplayClassForField('address2');  }
    get pinDisplayClass()       { return this.getValueDisplayClassForField('pin');       }
    get cityDisplayClass()      { return this.getValueDisplayClassForField('city');      }
    get stateDisplayClass()     { return this.getValueDisplayClassForField('state');     }
    get docNumberDisplayClass() { return this.getValueDisplayClassForField('docNumber'); }
    get poiDisplayClass()       { return this.getValueDisplayClassForField('poi');       }

    get docNumberLabel() {
        const docType = this.selectedKycDoc || 'Document';
        const labelMap = {
            'Passport':           'Passport Number',
            'Voter ID':           'Voter ID Number',
            'Voter Id':           'Voter ID Number',
            'Driving License':    'License Number',
            'Driving Licence':    'License Number',
            'Aadhaar':            'Aadhaar Number',
            'Aadhaar Card':       'Aadhaar Number'
        };
        return labelMap[docType] || `${docType} Number`;
    }

    // ── Edit handlers ────────────────────────────────────────────────────────
    handleFieldChange(event) {
        if (this.isReadOnly) return;
        const fieldKey = event.target.dataset.field;
        if (this.isFieldReadOnlyByDefault(fieldKey)) return;

        const value = event.target.value;
        this.editedValues = { ...this.editedValues, [fieldKey]: value };

        if (fieldKey === 'pin' && value && value.length === 6) {
            this.fetchCityStateFromPinCode(value);
        }

        this._emitChange(fieldKey, value);
    }

    async fetchCityStateFromPinCode(pinCode) {
        try {
            const result = await getCityStateFromPinCode({ pinCode });
            if (result && result.city && result.state) {
                this.editedValues = {
                    ...this.editedValues,
                    city:  result.city,
                    state: result.state
                };
                this._emitChange('pin', pinCode);
            }
        } catch (error) {
            console.error('[kycExtractedDetails] PIN lookup failed:', error);
        }
    }

    _emitChange(fieldKey, value) {
        this.dispatchEvent(new CustomEvent('extracteddetailschange', {
            detail: {
                field:     fieldKey,
                value:     value,
                allValues: { ...this.extractedDetails, ...this.editedValues }
            },
            bubbles:  true,
            composed: true
        }));
    }
}