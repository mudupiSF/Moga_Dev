import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import getVerificationStatusForLoan from '@salesforce/apex/QCFieldDocumentVerifcationController.getVerificationStatusForLoan';
import saveFieldVerification from '@salesforce/apex/QCFieldDocumentVerifcationController.saveFieldVerification';
import runOnLoadValidationCallback from '@salesforce/apex/QCFieldDocumentVerifcationController.runOnLoadValidationCallback';
import runActionCallback from '@salesforce/apex/QCFieldDocumentVerifcationController.runActionCallback';
import checkUserPermissions from '@salesforce/apex/QCFieldDocumentVerifcationController.checkUserPermissions';
import STATUS_FIELD from '@salesforce/schema/Application__c.Stage__c';
import FORM_FACTOR from '@salesforce/client/formFactor';
import QC_BACK_BUTTON_LABEL from '@salesforce/label/c.QC_Back_Button_Label';
import QC_FORWARD_BUTTON_LABEL from '@salesforce/label/c.QC_Forward_Button_Label';

export default class QcFieldDocumentVerificationConsole extends LightningElement {
    @api recordId; // Loan Application ID
    @api themeConfigJson;
    @api uiConfigJson;
    labels = {
        backButton: QC_BACK_BUTTON_LABEL,
        forwardButton: QC_FORWARD_BUTTON_LABEL
    };

    // Design attributes to control action visibility
    @api readOnly = false;

    
    @track verificationData = []; // Raw data from Apex
    @track loanApplicationData = null; // Level 1 - Loan Application
    @track applicants = []; // Level 2 - Applicants with nested Level 3 data
    @track filteredApplicantsData = []; // Store filtered result
    @track allChildTabsFlat = []; // Flat list of all child tabs with parent info
    @track isLoading = false;
    @track error;
    
    @track enableSendBackButton = false;
    @track enableSendForwardButton = false;
    
    // Store original data for cancel functionality
    @track originalVerificationData = null;
    @track originalLoanApplicationData = null;
    @track originalApplicants = null;
    
    // User permissions
    @track canEditFields = false;
    
    // Field value mismatches warning
    @track hasMismatches = false;
    @track reverifiedFields = new Set(); // Track fields that have been reverified (using fieldVerificationId as key)
    
    // Component initialization guard to prevent duplicate renders
    _isInitialized = false;
    
    @track recordTypeDeveloperName = '';
    @track currentStage = '';
    
    // Dynamic callback validation messages
    @track validationMessages = [];
    @track hasValidationMessages = false;
    
    // Filters
    @track selectedFilterOn = 'Status';
    @track selectedFilterBy = 'Not Verified';
    
    // Change counters - track fields that differ from their DB values
    @track changedStatusCount = 0; // Count of fields with changed verification status
    @track changedCommentsCount = 0; // Count of fields with changed comments
    @track bucketUiState = {}; // UI state for shared document preview buckets
    @track selectedBucketHeight = '600';
    previewHeightStorageKey = 'cpcqcptSimple.previewHeight';
    useGenericPreviewPane = true;
    _autoMismatchFilterApplied = false;
    uiConfig = {};
    _themeApplied = false;
    
    // Filter options
    filterOnOptions = [
        { label: 'Status', value: 'Status' },
        { label: 'Document Attached', value: 'Document' },
        { label: 'Mismatches', value: 'Mismatches' }
    ];
    statusFilterByOptions = [
        { label: 'All', value: 'All' },
        { label: 'Not Verified', value: 'Not Verified' },
        { label: 'Manually Verified', value: 'Manually Verified' },
        { label: 'Data Update Needed', value: 'Data Update Needed' },
        { label: 'Cannot Verify', value: 'Cannot Verify' },
        { label: 'Digitally Verified', value: 'Digitally Verified' }
    ];
    documentFilterByOptions = [
        { label: 'Fields With Documents', value: 'WithDocuments' },
        { label: 'Fields Without Documents', value: 'WithoutDocuments' }
    ];
    mismatchFilterByOptions = [
        { label: 'Data Mismatch', value: 'DataMismatch' },
        { label: 'Document Mismatch', value: 'DocumentMismatch' },
        { label: 'Documents Deleted', value: 'DocumentsDeleted' },
        { label: 'Documents Uploaded for Cannot Verify fields', value: 'CannotVerifyDocsUploaded' }
    ];

    bucketHeightOptions = [
        { label: '400 px', value: '400' },
        { label: '600 px', value: '600' },
        { label: '800 px', value: '800' },
        { label: '1000 px', value: '1000' },
        { label: '1200 px', value: '1200' }
    ];
    
    // Verification status radio options (user can manually select these)
    // Note: "Digitally Verified" is excluded - it can only be set by backend/integrations
    verificationRadioOptions = [
        { label: 'Manually Verified', value: 'Manually Verified' },
        { label: 'Data Update Needed', value: 'Data Update Needed' },
        { label: 'Not Verified', value: 'Not Verified' }
    ];
    verificationRadioOptionsWithCannotVerify = [
        { label: 'Manually Verified', value: 'Manually Verified' },
        { label: 'Data Update Needed', value: 'Data Update Needed' },
        { label: 'Not Verified', value: 'Not Verified' },
        { label: 'Cannot Verify', value: 'Cannot Verify' }
    ];
    
    connectedCallback() {
        // Guard: Prevent duplicate initialization if component is already initialized
        if (this._isInitialized) {
            return;
        }
        
        this._isInitialized = true;
        this._autoMismatchFilterApplied = false;
        this.initializeDynamicUiConfig();
        this.loadPreviewHeightPreference();
        
        this.runDynamicOnLoadValidations();
        this.checkPermissions();
        this.loadData();
    }
    
    disconnectedCallback() {
        // Reset initialization flag when component is disconnected
        this._isInitialized = false;
        this._autoMismatchFilterApplied = false;
    }

    renderedCallback() {
        if (this._themeApplied) {
            return;
        }
        this._themeApplied = true;
        this.applyThemeVariables();
    }

    initializeDynamicUiConfig() {
        const defaults = {
            title: 'Quality View',
            iconName: 'standard:calibration',
            primaryColor: '#5b3cc4',
            accentColor: '#0ea5a3',
            surfaceTint: '#f6f3ff',
            showDataUpdateLinkLabel: 'Show Data Update Needed Fields',
            showMismatchLinkLabel: 'Show Mismatched Fields',
            filterOnLabel: 'Filter On',
            filterByLabel: 'Filter By',
            bulkCannotVerifyLabel: 'Update Cannot Verify'
        };

        const parseConfig = (raw) => {
            if (!raw || typeof raw !== 'string') {
                return {};
            }
            try {
                const parsed = JSON.parse(raw);
                return parsed && typeof parsed === 'object' ? parsed : {};
            } catch (e) {
                return {};
            }
        };

        const themeConfig = parseConfig(this.themeConfigJson);
        const uiConfig = parseConfig(this.uiConfigJson);
        this.uiConfig = { ...defaults, ...themeConfig, ...uiConfig };
    }

    get cardTitle() {
        return this.uiConfig.title || 'Quality View';
    }

    get cardIconName() {
        return this.uiConfig.iconName || 'standard:calibration';
    }

    get filterOnLabel() {
        return this.uiConfig.filterOnLabel || 'Filter On';
    }

    get filterByLabel() {
        return this.uiConfig.filterByLabel || 'Filter By';
    }

    get bulkCannotVerifyLabel() {
        return this.uiConfig.bulkCannotVerifyLabel || 'Update Cannot Verify';
    }

    get showDataUpdateLinkLabel() {
        return this.uiConfig.showDataUpdateLinkLabel || 'Show Data Update Needed Fields';
    }

    get showMismatchLinkLabel() {
        return this.uiConfig.showMismatchLinkLabel || 'Show Mismatched Fields';
    }

    get dynamicThemeStyle() {
        return `--qc-primary:${this.uiConfig.primaryColor || '#5b3cc4'};--qc-accent:${this.uiConfig.accentColor || '#0ea5a3'};--qc-surface-tint:${this.uiConfig.surfaceTint || '#f6f3ff'};`;
    }

    applyThemeVariables() {
        const root = this.template?.querySelector('.qc-root');
        if (!root) {
            return;
        }
        root.style.setProperty('--qc-primary', this.uiConfig.primaryColor || '#5b3cc4');
        root.style.setProperty('--qc-accent', this.uiConfig.accentColor || '#0ea5a3');
        root.style.setProperty('--qc-surface-tint', this.uiConfig.surfaceTint || '#f6f3ff');
    }

    get totalFieldsCount() {
        return (this.verificationData || []).reduce((sum, section) => sum + ((section.fields || []).length), 0);
    }

    get verifiedFieldsCount() {
        return (this.verificationData || []).reduce((sum, section) => {
            return sum + (section.fields || []).filter((f) => f.verificationStatus === 'Manually Verified' || f.verificationStatus === 'Digitally Verified').length;
        }, 0);
    }

    get pendingFieldsCount() {
        return Math.max(this.totalFieldsCount - this.verifiedFieldsCount, 0);
    }
    
    async runDynamicOnLoadValidations() {
        try {
            const callbackResult = await runOnLoadValidationCallback({ recordId: this.recordId });
            const hasWErrors = callbackResult?.hasWErrors === true;
            const callbackMessages = Array.isArray(callbackResult?.validationMessages)
                ? callbackResult.validationMessages
                : [];

            this.validationMessages = callbackMessages
                .filter((msg) => msg && msg.message)
                .map((msg, index) => {
                    const type = (msg.errorType || 'ERROR').toUpperCase();
                    return {
                        ...msg,
                        errorType: type,
                        header: msg.header || 'Validation',
                        messageKey: `${index}-${msg.header || 'Validation'}-${msg.message}`,
                        isWarning: type === 'WARNING',
                        isError: type !== 'WARNING'
                    };
                });
            this.hasValidationMessages = hasWErrors && this.validationMessages.length > 0;

            this.evaluateSendBackVisibility();
        } catch (error) {
            console.error('Error running dynamic on-load validations:', error);
            this.validationMessages = [];
            this.hasValidationMessages = false;
            this.evaluateSendBackVisibility();
        }
    }
    
    /**
     * Check user permissions to edit fields and if user is owner's manager
     */
    async checkPermissions() {
        try {
            const result = await checkUserPermissions({ loanApplicationId: this.recordId });
            
            this.canEditFields = result.canEdit;
            if (this.canEditFields === false) {
                this.readOnly = true;
            }
            
        } catch (error) {
            console.error('Error checking permissions:', error);
            this.canEditFields = false;
        }
    }
    
    /**
     * Load all verification data from Apex (WITHOUT documents for speed)
     */
    async loadData() {
        this.isLoading = true;
        this.error = null;
        
        try {
            // Load data WITH documents (testing optimizations)
            const result = await getVerificationStatusForLoan({ 
                loanApplicationId: this.recordId,
                queryDocumentChecklist: true  // Include documents to test full performance
            });
                        
            this.verificationData = result || [];
            
            // Debug: Log sample field data to check fieldValueFromVerifiedFields
            if (this.verificationData && this.verificationData.length > 0) {
                // Log ALL fields with fieldVerificationId to see what we're getting
                let fieldCount = 0;
                let mismatchCount = 0;
                for (const section of this.verificationData) {
                    if (section.fields && section.fields.length > 0) {
                        for (const field of section.fields) {
                            if (field.fieldVerificationId) {
                                const verifiedValue = field.fieldValueFromVerifiedFields != null ? String(field.fieldValueFromVerifiedFields).trim() : '';
                                const currentValue = field.currentValueInDB != null ? String(field.currentValueInDB).trim() : '';
                                const isMismatch = verifiedValue !== currentValue;
                                
                                if (isMismatch) mismatchCount++;
                                
                                fieldCount++;
                            }
                        }
                    }
                }
            }
            
            // Organize and display data immediately
            this.organizeData();
            this.storeOriginalData();
            this.buildFilterOptions();
            // Reset change counters (default to 0)
            this.changedStatusCount = 0;
            this.changedCommentsCount = 0;
            this.evaluateSendBackVisibility();
            
        } catch (error) {
            console.error('Error loading data:', error);
            this.error = error.body?.message || error.message || 'Unknown error';
            this.showToast('Error', this.error, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    /**
     * Evaluate if Send Back and Send Forward buttons should be visible
     * 
     * ✅ PRIORITY RULE (checked FIRST):
     * - If there are OPEN CASES → Always show Send Back, hide Send Forward
     * - If there are FAILED INTEGRATIONS → Always show Send Back, hide Send Forward
     * 
     * ✅ FIELD-BASED RULES (if no open cases/failed integrations):
     * - PRIMARY: User MUST take action on ALL fields (no "Not Verified" status)
     * - SECONDARY: Show Send Back if ANY field is "Data Update Needed" OR integration failed
     * 
     * ✅ SEND FORWARD VISIBILITY:
     * - All integrations must be "Success" AND
     * - Every field must be either "Digitally Verified", "Cannot Verify" or "Manually Verified" AND
     * - No open cases AND
     * - No failed integrations
     */
    evaluateSendBackVisibility() {
                
        // Check if verification data is loaded
        if (!this.verificationData || this.verificationData.length === 0) {
            this.enableSendBackButton = true; // Always enabled
            this.enableSendForwardButton = false;
            return;
        }
        
        let hasNotVerified = false;
        let hasDataUpdateNeeded = false;
        let hasMismatches = false;
        let allFieldsVerified = true;
        
        // Helper function to check fields in a field array
        const checkFields = (fields) => {
            if (!fields || fields.length === 0) return;
            
            for (const field of fields) {
                // Skip fields with empty values - they don't need verification (hidden fields)
                if (!field.currentValueInDB || field.currentValueInDB.trim() === '') {
                    continue;
                }
                
                    const status = field.verificationStatus;
                
                // Skip if status is null/undefined (shouldn't happen, but safety check)
                if (!status) {
                    continue;
                }
                
                // Check for mismatches:
                // - Manually Verified: saved verified values/doc ids differ from current values/doc ids
                // - Cannot Verify: documents now exist for the field (needs user action)
                let fieldHasMismatch = false;
                if (status === 'Manually Verified') {
                    if (field.hasMismatch !== undefined) {
                        // Use the property already set in processFields
                        fieldHasMismatch = field.hasMismatch;
                    } else if (field.fieldVerificationId) {
                        // Calculate if not already set (fallback)
                        const verifiedValue = field.fieldValueFromVerifiedFields != null ? String(field.fieldValueFromVerifiedFields).trim() : '';
                        const currentValue = field.currentValueInDB != null ? String(field.currentValueInDB).trim() : '';
                        fieldHasMismatch = verifiedValue !== currentValue;
                    }
                    
                    if (fieldHasMismatch) {
                        hasMismatches = true;
                        allFieldsVerified = false;
                    }
                } else if (status === 'Cannot Verify') {
                    const hasDocuments =
                        (field.documentAttachments && field.documentAttachments.length > 0) ||
                        ((field.totalAttachments || 0) > 0) ||
                        field.hasDocuments === true;
                    if (hasDocuments) {
                        hasMismatches = true;
                        allFieldsVerified = false;
                    }
                }
                    
                    if (status === 'Not Verified') {
                        hasNotVerified = true;
                        allFieldsVerified = false;
                    }
                    if (status === 'Data Update Needed') {
                        hasDataUpdateNeeded = true;
                        allFieldsVerified = false;
                    }
                    // For Send Forward: Only "Digitally Verified", "Cannot Verify" or "Manually Verified" count as verified
                    if (status !== 'Digitally Verified' && status !== 'Cannot Verify' && status !== 'Manually Verified') {
                        allFieldsVerified = false;
                    }
                }
        };
        
        // Check Loan Application fields (Level 1)
        if (this.loanApplicationData && this.loanApplicationData.fields) {
            checkFields(this.loanApplicationData.fields);
        }
        
        // Check Level 2 objects (Applicants, Guardian, etc.) and their children (Level 3)
        // Use this.applicants (source data) instead of filteredApplicantsData to ensure we check ALL sections including Guardian
        if (this.applicants && this.applicants.length > 0) {
            for (const objectGroup of this.applicants) {
                if (objectGroup.records && objectGroup.records.length > 0) {
                    for (const record of objectGroup.records) {
                        // Check Level 2 record's own fields (including Guardian fields)
                        if (record.fields && record.fields.length > 0) {
                            checkFields(record.fields);
                        }
                        
                        // Check Level 3 child records
                        if (record.childRecords && record.childRecords.size > 0) {
                            record.childRecords.forEach((childList) => {
                                if (childList && childList.length > 0) {
                                    for (const childRec of childList) {
                                        if (childRec.fields && childRec.fields.length > 0) {
                                            checkFields(childRec.fields);
                                        }
                                        // Check Level 4 nested child records
                                        if (childRec.childRecords && childRec.childRecords.size > 0) {
                                            childRec.childRecords.forEach((nestedList) => {
                                                if (nestedList && nestedList.length > 0) {
                                                    for (const nestedRec of nestedList) {
                                                        if (nestedRec.fields && nestedRec.fields.length > 0) {
                                                            checkFields(nestedRec.fields);
                                                        }
                                                    }
                                                }
                                            });
                                        }
                                    }
                                }
                            });
                        }
                    }
                }
            }
        }
        
        // Dynamic validation warnings from callback.
        const hasWarnings = this.hasValidationMessages;
        
        // Check for unsaved changes
        const hasUnsavedChanges = this.changedStatusCount > 0 || this.changedCommentsCount > 0;
        
        // Store mismatch flag for UI display
        this.hasMismatches = hasMismatches;
        let mismatchFilterAutoSwitched = false;
        if (hasMismatches) {
            if (!this._autoMismatchFilterApplied) {
                this.selectedFilterOn = 'Mismatches';
                if (this.selectedFilterBy !== 'DataMismatch' &&
                    this.selectedFilterBy !== 'DocumentMismatch' &&
                    this.selectedFilterBy !== 'DocumentsDeleted' &&
                    this.selectedFilterBy !== 'CannotVerifyDocsUploaded') {
                    this.selectedFilterBy = 'DataMismatch';
                }
                this._autoMismatchFilterApplied = true;
                mismatchFilterAutoSwitched = true;
            }
        } else {
            this._autoMismatchFilterApplied = false;
        }
        if (mismatchFilterAutoSwitched) {
            this.updateFilteredApplicants();
        }
        
        // ============================================================
        // SEND BACK BUTTON LOGIC
        // ============================================================
        // Enable Send Back when:
        // 1. There are warnings (open cases OR failed integrations) OR
        // 2. All visible fields have been acted upon (no "Not Verified") AND any field is "Data Update Needed"
        // 3. NO unsaved changes (all changes must be saved first) - same as Submit button
        // Only check visible fields (those with values, not hidden)
        // ============================================================
        this.enableSendBackButton = (hasWarnings || hasMismatches || !allFieldsVerified) && !hasUnsavedChanges;
        
        // ============================================================
        // SUBMIT BUTTON LOGIC
        // ============================================================
        // Enable Submit ONLY when:
        // 1. NO warnings (no open cases, no failed integrations) AND
        // 2. All visible fields are verified (Digitally Verified, Cannot Verify or Manually Verified) AND
        // 3. NO mismatches (fieldValueFromVerifiedFields must match currentValueInDB) AND
        // 4. NO unsaved changes (all changes must be saved first) AND
        // 5. NO reconsent required (if reconsent is required, submit button is hidden) AND
        // 6. NO stage gate validation errors
        // Only check visible fields (those with values, not hidden)
        // ============================================================
        this.enableSendForwardButton = !hasWarnings && allFieldsVerified && !hasMismatches && !hasUnsavedChanges;
        
    }
    
    /**
     * Handle Send Back button click - Open modal
     */
    handleSendBack() {
        this.runDynamicAction('Back');
    }

    /**
     * Get record data to populate current stage
     */
    @wire(getRecord, {
        recordId: '$recordId',
        fields: [STATUS_FIELD, 'Application__c.RecordType.DeveloperName']
    })
    wiredRecord({ error, data }) {
        if (data) {
            this.currentStage = getFieldValue(data, STATUS_FIELD);
            console.log('[QC][wiredRecord] record wire data', {
                currentStage: this.currentStage
            });
            // Extract RecordType DeveloperName
            if (data.fields.RecordType && data.fields.RecordType.value && data.fields.RecordType.value.fields) {
                this.recordTypeDeveloperName = data.fields.RecordType.value.fields.DeveloperName.value || '';
            }
            
            // Re-evaluate button visibility when sub stage changes
            this.evaluateSendBackVisibility();
        } else if (error) {
            console.error('Error loading record:', error);
        }
    }
    
    /**
     * Handle click on "Show Data Update Needed Fields" link
     * Opens dataUpdateNeeded component in a new tab (Standard Salesforce)
     */
    handleDataUpdateClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        // Standard Salesforce - Use NavigationMixin to generate URL for Lightning App Page
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'DataUpdateNeeded' // Replace with your actual Lightning App Page API Name if different
            },
            state: {
                c__recordId: this.recordId
            }
        }).then(url => {
            window.open(url, '_blank');
        }).catch(error => {
            console.error('Error generating URL:', error);
            // Fallback: Direct URL pattern for Lightning App Page
            // Format: /lightning/n/{AppPageApiName}?c__recordId={recordId}
            const baseUrl = window.location.origin;
            const url = `${baseUrl}/lightning/n/DataUpdateNeeded?c__recordId=${this.recordId}`;
            window.open(url, '_blank');
        });
    }
    
    /**
     * Collect all mismatch data from verification data
     * @return Array of mismatch records
     */
    collectMismatchData() {
        const mismatchData = [];
        
        // Helper function to collect mismatches from fields
        const collectFromFields = (fields, recordId, objectName, sectionName, recordLabel) => {
            if (!fields || fields.length === 0) return;
            
            fields.forEach(field => {
                const hasValueMismatch = field.hasValueMismatch === true;
                const hasDocumentMismatch = field.hasDocumentMismatch === true || field.hasCannotVerifyDocumentMismatch === true;
                const hasAnyMismatch = field.hasMismatch === true || hasValueMismatch || hasDocumentMismatch;
                if (hasAnyMismatch) {
                    mismatchData.push({
                        id: field.fieldVerificationId || field.uniqueKey,
                        objectName: field.objectName || objectName,
                        fieldLabel: field.fieldLabel || field.fieldName,
                        fieldName: field.fieldName,
                        fieldValueOnRecord: field.currentValueInDB || '',
                        verifiedValue: field.fieldValueFromVerifiedFields || '',
                        timestampOfVerification: field.manuallyVerifiedDate || null,
                        recordId: field.recordId || recordId,
                        sectionName: sectionName,
                        recordLabel: recordLabel,
                        lookupFieldName: this.getLookupFieldName(field, objectName),
                        verificationStatus: field.verificationStatus || '',
                        hasMismatch: hasAnyMismatch,
                        hasValueMismatch: hasValueMismatch,
                        hasDocumentMismatch: hasDocumentMismatch
                    });
                }
            });
        };
        
        // Collect from Loan Application fields (Level 1)
        if (this.loanApplicationData && this.loanApplicationData.fields) {
            collectFromFields(
                this.loanApplicationData.fields,
                this.loanApplicationData.recordId,
                'Application__c',
                this.loanApplicationData.sectionName,
                this.loanApplicationData.recordLabel
            );
        }
        
        // Collect from Level 2 objects (Applicants, etc.) and their children (Level 3)
        if (this.applicants && this.applicants.length > 0) {
            this.applicants.forEach(objectGroup => {
                if (objectGroup.records && objectGroup.records.length > 0) {
                    objectGroup.records.forEach(record => {
                        // Collect from Level 2 record's own fields
                        if (record.fields && record.fields.length > 0) {
                            collectFromFields(
                                record.fields,
                                record.recordId,
                                record.objectName,
                                record.sectionName,
                                record.recordLabel
                            );
                        }
                        
                        // Collect from Level 3 child records
                        if (record.childRecords && record.childRecords.size > 0) {
                            record.childRecords.forEach((childList) => {
                                if (childList && childList.length > 0) {
                                    childList.forEach(childRec => {
                                        if (childRec.fields && childRec.fields.length > 0) {
                                            collectFromFields(
                                                childRec.fields,
                                                childRec.recordId,
                                                childRec.objectName,
                                                childRec.sectionName,
                                                childRec.recordLabel
                                            );
                                        }
                                        // Collect from Level 4 nested child records
                                        if (childRec.childRecords && childRec.childRecords.size > 0) {
                                            childRec.childRecords.forEach((nestedList) => {
                                                if (nestedList && nestedList.length > 0) {
                                                    nestedList.forEach(nestedRec => {
                                                        if (nestedRec.fields && nestedRec.fields.length > 0) {
                                                            collectFromFields(
                                                                nestedRec.fields,
                                                                nestedRec.recordId,
                                                                nestedRec.objectName,
                                                                nestedRec.sectionName,
                                                                nestedRec.recordLabel
                                                            );
                                                        }
                                                    });
                                                }
                                            });
                                        }
                                    });
                                }
                            });
                        }
                    });
                }
            });
        }
        
        return mismatchData;
    }
    
    /**
     * Get lookup field name for display
     */
    getLookupFieldName(field, objectName) {
        // Determine lookup field name based on object name
        const lookupMap = {
            'Applicant__c': 'Applicant',
            'Applicant_Address__c': 'Applicant Address',
            'Applicant_Employment__c': 'Applicant Employment',
            'Applicant_Income__c': 'Applicant Income',
            'Application__c': 'Application'
        };
        
        return lookupMap[objectName] || objectName;
    }
    
    /**
     * Opens CpcqcShowMismatches component in a new tab (Standard Salesforce)
     * Passes mismatch data as JSON parameter
     */
    handleShowMismatchesClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        // Collect mismatch data from existing verification data
        const mismatchData = this.collectMismatchData();
        
        // Convert to JSON string for URL parameter
        const mismatchDataJson = encodeURIComponent(JSON.stringify(mismatchData));
        
        // Standard Salesforce - Use NavigationMixin to generate URL for Lightning App Page
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Showing_Mismatches_in_Verified_Fields' // Lightning App Page API Name
            },
            state: {
                c__recordId: this.recordId,
                c__mismatchData: mismatchDataJson
            }
        }).then(url => {
            window.open(url, '_blank');
        }).catch(error => {
            console.error('Error generating URL:', error);
            // Fallback: Direct URL pattern for Lightning App Page
            // Format: /lightning/n/{AppPageApiName}?c__recordId={recordId}&c__mismatchData={json}
            const baseUrl = window.location.origin;
            const url = `${baseUrl}/lightning/n/CpcqcShowMismatches?c__recordId=${this.recordId}&c__mismatchData=${mismatchDataJson}`;
            window.open(url, '_blank');
        });
    }
    
    /**
     * Handle Send Forward button click
     */
    async handleSendForward() {
        await this.runDynamicAction('Submit');
    }

    async runDynamicAction(methodName, inputData = {}, outputData = '{}') {
        this.isLoading = true;
        try {
            const actionResult = await runActionCallback({
                recordId: this.recordId,
                methodName,
                inputData: JSON.stringify(inputData || {}),
                outputData,
                isEventAction: false
            });
            await this.processDynamicActionResult(actionResult, methodName);
            return actionResult;
        } catch (error) {
            this.showToast('Error', error?.body?.message || error?.message || 'Action failed', 'error');
            throw error;
        } finally {
            this.isLoading = false;
        }
    }

    async processDynamicActionResult(actionResult, currentMethodName) {
        if (!actionResult?.success) {
            throw new Error(actionResult?.message || `${currentMethodName} action failed`);
        }

        if (actionResult?.message) {
            this.showToast(
                actionResult?.toastVariant === 'error' ? 'Error' : 'Success',
                actionResult.message,
                actionResult?.toastVariant || 'success'
            );
        }

        if (actionResult?.shouldRefresh) {
            setTimeout(() => {
                window.location.reload();
            }, 1000);
        }
    }
    
    /**
     * Organize the flat data into tab-based structure
     * Structure: 
     *   - Loan Application (Level 1)
     *   - Level 2 objects (e.g., Applicants) - Each as a tab
     *     - Level 3 child objects (e.g., Address, Employment, Income) - Nested tabs
     */
    organizeData() {
                        
        // Log all unique object names and sections
        const uniqueObjects = new Set();
        const uniqueSections = new Set();
        this.verificationData.forEach(item => {
            uniqueObjects.add(item.objectName);
            uniqueSections.add(`${item.objectName} - ${item.sectionName}`);
        });
                                
        // Helper to get objectLevel from fields (it's in the fields array, not at top level)
        const getObjectLevel = (item) => {
            // First check if objectLevel is set directly on the item (for empty sections)
            if (item.objectLevel != null) {
                return Number(item.objectLevel);
            }
            // Otherwise check fields array (for normal sections)
            if (item.fields && item.fields.length > 0 && item.fields[0].objectLevel) {
                return Number(item.fields[0].objectLevel);
            }
            return null;
        };
        
        // Helper to get parentRecordId from fields
        const getParentRecordId = (item) => {
            // First check if parentRecordId is set directly on the item (for empty sections)
            if (item.parentRecordId) {
                return item.parentRecordId;
            }
            // Otherwise check fields (for normal sections)
            if (item.fields && item.fields.length > 0 && item.fields[0].parentRecordId) {
                return item.fields[0].parentRecordId;
            }
            return null;
        };
        
        // Debug: Log object levels
        this.verificationData.forEach((item, index) => {
            const level = getObjectLevel(item);
            const parentId = getParentRecordId(item);
        });
        
        // Level 1: Loan Application
        const loanAppData = this.verificationData.find(item => getObjectLevel(item) === 1);
        
                
        if (loanAppData) {
            this.loanApplicationData = {
                recordId: loanAppData.recordId,
                recordLabel: loanAppData.recordLabel,
                sectionName: loanAppData.sectionName,
                fields: this.processFields(loanAppData.fields, loanAppData.recordId)
            };
                    } else {
            console.warn('No Loan Application data found (objectLevel 1)');
        }
        
        // Level 2: Group by Object Type first, then by records
        // Only include Level 3 items WITHOUT parentRecordId (standalone DedicatedQuery sections)
        const level2ObjectsMap = new Map(); // Map<objectName, Map<recordId, recordData>>
        
        this.verificationData.forEach(item => {
            const level = getObjectLevel(item);
            const parentId = getParentRecordId(item);
            
            // Process Level 2 items
            // Also include Level 3 items WITHOUT parentRecordId (standalone sections)
            // Skip Level 3 items WITH parentRecordId (those are children, not top-level)
            if (level === 2 || (level === 3 && !parentId)) {
                // Group by object name first
                if (!level2ObjectsMap.has(item.objectName)) {
                    level2ObjectsMap.set(item.objectName, new Map());
                }
                
                const recordsMap = level2ObjectsMap.get(item.objectName);
                
                // Handle empty sections (recordId is null from Apex placeholder)
                if (!item.recordId) {
                                        // Still need to create a placeholder so section appears
                    const compositeKey = `empty_${item.sectionName || item.objectName}`;
                    recordsMap.set(compositeKey, {
                        recordId: null,
                        recordLabel: item.recordLabel || 'No records',
                        sectionName: item.sectionName,
                        objectName: item.objectName,
                        objectLevel: level,
                        fields: [],
                        childRecords: new Map(), // Generic child records grouped by objectName
                        isEmpty: true // Flag for empty section
                    });
                    return; // Skip further processing
                }
                
                // Use composite key: recordId + sectionName to handle same record in multiple sections
                const compositeKey = `${item.recordId}_${item.sectionName || ''}`;
                
                                if (!recordsMap.has(compositeKey)) {
                    recordsMap.set(compositeKey, {
                        recordId: item.recordId,
                        recordLabel: item.recordLabel,
                        sectionName: item.sectionName,
                        objectName: item.objectName,
                        objectLevel: level,
                        fields: this.processFields(item.fields, item.recordId),
                        childRecords: new Map(), // Child records grouped by sectionName
                    });
                }
            } else if (level === 3 && parentId) {
                            }
        });
        
        // Now process Level 3 records as children (only those with parentRecordId)
        // These were NOT added to level2ObjectsMap in the previous loop
        this.verificationData.forEach(item => {
            const level = getObjectLevel(item);
            
            if (level === 3) {
                const parentId = getParentRecordId(item);
                const childParentSectionName = item.parentSectionName; // From Apex
                
                
                // Only process Level 3 items that have a parent (children)
                if (!parentId) {
                    // This is a standalone section, already processed in previous loop
                    return;
                }
                
                                                                                                                                
                // Validation: Child MUST have parentSectionName to avoid attaching to wrong parents
                if (!childParentSectionName) {
                    console.error('❌ ERROR: Child record missing parentSectionName! This child will be skipped.');
                    console.error('   Child:', item.objectName, '-', item.sectionName);
                    console.error('   This is required when multiple sections use the same parent object.');
                    console.error('   Please check QC_Verification_Parent__mdt.Parent_QC_Section_Name__c');
                    return; // SKIP this child - don't attach anywhere
                }
                
                // Find parent records that match BOTH parentId AND parentSectionName
                let parentRecords = [];
                let checkedParents = [];
                
                for (let recordsMap of level2ObjectsMap.values()) {
                    // Check all entries in the map for matching parentId
                    for (let [compositeKey, record] of recordsMap.entries()) {
                        if (record.recordId === parentId) {
                            checkedParents.push(record.sectionName);
                            
                            // STRICT matching - only attach if parent section name matches
                            if (record.sectionName === childParentSectionName) {
                                parentRecords.push(record);
                                                            } else {
                                                            }
                        }
                    }
                }
                
                                                
                if (parentRecords.length > 0) {
                    const childRecord = {
                        recordId: item.recordId, // May be null for empty sections
                        recordLabel: item.recordLabel,
                        sectionName: item.sectionName,
                        objectName: item.objectName, // CRITICAL: This is the actual object API name (e.g., "LoanApplicantEmployment")
                        fields: item.recordId ? this.processFields(item.fields, item.recordId) : [],
                        childRecords: new Map(), // Level 4 children grouped by section name
                        childTabs: [],
                        hasChildren: false,
                        isEmpty: item.isEmpty || !item.recordId // Flag for empty sections
                    };
                    
                    
                    // Attach child to matching parent records using section name as key FOR UI GROUPING
                    // But preserve objectName in the child record for save operations
                    parentRecords.forEach(parentRecord => {
                        // Use section name as the grouping key for UI display
                        const sectionKey = item.sectionName || item.objectName;
                        if (!parentRecord.childRecords.has(sectionKey)) {
                            parentRecord.childRecords.set(sectionKey, []);
                        }
                        parentRecord.childRecords.get(sectionKey).push(childRecord);
                                            });
                } else {
                    console.error('❌ No matching parent found for child!');
                    console.error('   Child:', item.objectName, '-', item.sectionName);
                    console.error('   Expected parent section:', childParentSectionName);
                    console.error('   Parent recordId:', parentId);
                    console.error('   Checked sections:', checkedParents);
                    console.error('   Is empty section?', item.isEmpty);
                }
            }
        });

        // Process Level 4 records as children of Level 3 records.
        this.verificationData.forEach(item => {
            const level = getObjectLevel(item);
            if (level !== 4) return;

            const parentId = getParentRecordId(item);
            if (!parentId) return;
            const parentSectionName = item.parentSectionName;

            const parentChildRecords = [];
            for (let recordsMap of level2ObjectsMap.values()) {
                for (let [, level2Record] of recordsMap.entries()) {
                    if (!level2Record.childRecords || level2Record.childRecords.size === 0) continue;
                    level2Record.childRecords.forEach((level3List) => {
                        (level3List || []).forEach((level3Record) => {
                            if (level3Record.recordId !== parentId) return;
                            if (parentSectionName && level3Record.sectionName !== parentSectionName) return;
                            parentChildRecords.push(level3Record);
                        });
                    });
                }
            }

            if (parentChildRecords.length > 0) {
                const level4Record = {
                    recordId: item.recordId,
                    recordLabel: item.recordLabel,
                    sectionName: item.sectionName,
                    objectName: item.objectName,
                    fields: item.recordId ? this.processFields(item.fields, item.recordId) : [],
                    isEmpty: item.isEmpty || !item.recordId
                };

                parentChildRecords.forEach((parentChildRecord) => {
                    const sectionKey = item.sectionName || item.objectName;
                    if (!parentChildRecord.childRecords.has(sectionKey)) {
                        parentChildRecord.childRecords.set(sectionKey, []);
                    }
                    parentChildRecord.childRecords.get(sectionKey).push(level4Record);
                });
            }
        });
        
        // Convert to array structure: Group by section name (not just object type)
        // This allows multiple sections with the same object to have separate tabs
        const level2Objects = [];
        let tabIndex = 0;
        
        // Helper function to get icon for object type
        const getIconForObject = (objectName) => {
            const iconMap = {
                'Applicant_Address__c': 'standard:address',
                'Applicant_Employment__c': 'standard:work_type',
                'Applicant_Income__c': 'standard:currency'
            };
            return iconMap[objectName] || 'standard:record';
        };
        
        level2ObjectsMap.forEach((recordsMap, objectName) => {
            const recordsArray = Array.from(recordsMap.values());
            
            // Group by sectionName to handle multiple sections with same objectName
            const sectionGroups = new Map();
            recordsArray.forEach(record => {
                const sectionKey = record.sectionName || objectName;
                if (!sectionGroups.has(sectionKey)) {
                    sectionGroups.set(sectionKey, []);
                }
                sectionGroups.get(sectionKey).push(record);
            });
            
            // Create separate tabs for each section
            sectionGroups.forEach((sectionRecords, sectionName) => {
                const records = sectionRecords.map(record => {
                    // Dynamically build child tabs from ALL child object types
                    // Build child tabs from section-grouped child records
                    const childTabs = [];
                    
                    // Iterate through all child sections (already grouped by section name)
                    if (record.childRecords && record.childRecords.size > 0) {
                        record.childRecords.forEach((childRecordsList, sectionName) => {
                            // Get object name from first child record for icon
                            const objectName = childRecordsList.length > 0 ? childRecordsList[0].objectName : '';
                            const mappedChildRecords = (childRecordsList || []).map((childRec) => {
                                const nestedTabs = [];
                                if (childRec.childRecords && childRec.childRecords.size > 0) {
                                    childRec.childRecords.forEach((nestedRecordsList, nestedSectionName) => {
                                        const nestedObjectName = nestedRecordsList.length > 0 ? nestedRecordsList[0].objectName : '';
                                        const nestedHasRecords = nestedRecordsList && nestedRecordsList.length > 0 &&
                                            nestedRecordsList.some((rec) => rec.recordId != null);
                                        nestedTabs.push({
                                            label: nestedSectionName,
                                            icon: getIconForObject(nestedObjectName),
                                            objectName: nestedObjectName,
                                            sectionKey: `${nestedObjectName}_${nestedSectionName}`,
                                            records: nestedRecordsList,
                                            hasRecords: nestedHasRecords,
                                            hasFilteredFields: nestedHasRecords
                                        });
                                    });
                                }
                                return {
                                    ...childRec,
                                    childTabs: nestedTabs,
                                    hasChildren: nestedTabs.some((tab) => tab.hasFilteredFields)
                                };
                            });
                            
                            // Check if records have actual data (not just empty placeholders)
                            const hasRealRecords = mappedChildRecords && mappedChildRecords.length > 0 &&
                                mappedChildRecords.some(rec => rec.recordId != null);
                            
                            childTabs.push({
                                label: sectionName,
                                icon: getIconForObject(objectName),
                                objectName: objectName,
                                sectionKey: `${objectName}_${sectionName}`,
                                records: mappedChildRecords,
                                hasRecords: hasRealRecords
                            });
                        });
                    } else {
                    }
                    
                    return {
                        ...record,
                        tabId: `level2-${tabIndex++}`,
                        tabLabel: record.recordLabel,
                        childTabs: childTabs,
                        hasChildren: childTabs.length > 0,
                        hasFields: record.fields && record.fields.length > 0,
                        showIntegrationTabs: false
                    };
                });
                
                level2Objects.push({
                    objectName: objectName,
                    sectionName: sectionName,
                    sectionKey: `${objectName}_${sectionName}`, // Unique key for multiple sections
                    records: records
                });
            });
        });
        
        this.applicants = level2Objects;
        this.updateFilteredApplicants(); // Initialize filtered data
        // Reset change counters (default to 0)
        this.changedStatusCount = 0;
        this.changedCommentsCount = 0;
        
                                    }
    
    /**
     * Process fields array and add UI properties including document preview
     * Returns flat array of fields (backward compatible)
     */
    processFields(fields, recordId) {
        if (!fields || fields.length === 0) return [];
        
        return fields.map(field => {
            
            // Process document attachments for preview
            let processedAttachments = [];
            if (field.documentAttachments && field.documentAttachments.length > 0) {
                processedAttachments = field.documentAttachments.map(doc => {
                    const ext = doc.fileExtension ? doc.fileExtension.toLowerCase() : '';
                    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp'];
                    const excelExtensions = ['xls', 'xlsx', 'csv'];
                    const isPdf = ext === 'pdf';
                    const isImage = imageExtensions.includes(ext);
                    const isExcel = excelExtensions.includes(ext);
                    
                    // Use ContentVersion ID for preview URLs
                    // For images, use full download URL to get original quality (not blurred thumbnail)
                    // For PDFs, use thumbnail rendition for faster loading
                    let previewUrl;
                    if (doc.contentVersionId) {
                        if (isImage) {
                            // Use full download URL for images to get original quality
                            previewUrl = `/sfc/servlet.shepherd/version/download/${doc.contentVersionId}`;
                        } else {
                            // Use thumbnail rendition for PDFs and other files
                            previewUrl = `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${doc.contentVersionId}&operationContext=CHATTER&contentId=${doc.contentDocumentId}`;
                        }
                    } else {
                        previewUrl = `/sfc/servlet.shepherd/document/download/${doc.contentDocumentId}`;
                    }
                    
                    return {
                        ...doc,
                        previewUrl: previewUrl,
                        isPdf: isPdf,
                        isImage: isImage,
                        isExcel: isExcel,
                        fileTypeUpper: ext ? ext.toUpperCase() : '',
                        isOther: !isPdf && !isImage && !isExcel
                    };
                });
            }
            
            // Detect tampering: If field is "Manually Verified" and stored value differs from current value
            const isTampered = (field.verificationStatus === 'Verified' || field.verificationStatus === 'Digitally Verified') &&
                               field.storedFieldValue !== null && 
                               field.storedFieldValue !== undefined &&
                               field.storedFieldValue !== field.currentValueInDB;
            
            // Detect mismatch: Only check if status is "Manually Verified"
            // fieldVerificationId exists and fieldValueFromVerifiedFields != currentValueInDB
            // Handle null/undefined/empty string comparisons correctly
            let hasValueMismatch = false;
            let hasDocumentMismatch = false;
            let hasCannotVerifyDocumentMismatch = false;
            if (field.fieldVerificationId && field.verificationStatus === 'Manually Verified') {
                // Check if fieldValueFromVerifiedFields property exists (it should come from Apex)
                if (field.hasOwnProperty('fieldValueFromVerifiedFields') || field.fieldValueFromVerifiedFields !== undefined) {
                    const verifiedValue = field.fieldValueFromVerifiedFields != null ? String(field.fieldValueFromVerifiedFields).trim() : '';
                    const currentValue = field.currentValueInDB != null ? String(field.currentValueInDB).trim() : '';
                    hasValueMismatch = verifiedValue !== currentValue;
                    // Property doesn't exist - log warning (this should not happen if Apex is working correctly)
                    console.warn('⚠️ fieldValueFromVerifiedFields property missing for field:', field.fieldName, 'Raw field:', field);
                }
                // Include document id mismatch for manually verified fields.
                hasDocumentMismatch = this.hasDocumentMismatch({
                    ...field,
                    documentAttachments: processedAttachments
                });
            }
            if (field.verificationStatus === 'Cannot Verify') {
                hasCannotVerifyDocumentMismatch = processedAttachments.length > 0;
            }
            const hasMismatch = hasValueMismatch || hasDocumentMismatch || hasCannotVerifyDocumentMismatch;
            
            // DB Status: Always show the stored value from DB (field.verificationStatus from server)
            // This is the actual status stored in the database
            // After save and reload, this will reflect the newly saved status
            // Default to "Not verified" if no status exists
            const dbStatus = field.verificationStatus || 'Not verified';
            
            // Store original DB values for comparison to detect actual changes
            const originalDbStatus = dbStatus;
            const originalDbComments = field.verificationComments || '';
            
            
            return {
                ...field,
                recordId: recordId,
                uniqueKey: `${recordId}_${field.fieldName}`,
                hasChanges: false, // Reset hasChanges flag - this is fresh data from DB
                // Map childSectionName from Apex to childSection for UI
                childSection: field.childSectionName,
                // Lock fields that are digitally verified OR user doesn't have permission OR readOnly is true
                isDigitallyVerified: field.verificationStatus === 'Digitally Verified',
                isCannotVerify: field.verificationStatus === 'Cannot Verify',
                isManuallyVerified: field.verificationStatus === 'Manually Verified',
                isFieldLocked: field.verificationStatus === 'Digitally Verified' || !this.canEditFields || this.readOnly,
                // Tampering detection
                isTampered: isTampered,
                // Mismatch detection: fieldValueFromVerifiedFields != currentValueInDB (only for Manually Verified)
                hasMismatch: hasMismatch,
                hasValueMismatch: hasValueMismatch,
                hasDocumentMismatch: hasDocumentMismatch,
                hasCannotVerifyDocumentMismatch: hasCannotVerifyDocumentMismatch,
                storedFieldValue: field.storedFieldValue || '', // Store for reference
                // Store timestamp for mismatch display
                manuallyVerifiedDate: field.manuallyVerifiedDate || null,
                // Reverify button properties
                reverifyLabel: 'Re-Verify',
                reverifyVariant: 'neutral',
                // Store original verified value for restoration when unclicking Reverify
                originalVerifiedValue: field.fieldValueFromVerifiedFields || null,
                originalVerifiedDocumentIds: field.verifiedStatusDocumentIds || null,
                originalVerifiedDocumentNames: field.verifiedStatusDocumentNames || null,
                // DB Status: Store the actual DB status from server (will update after save and reload)
                // This value comes from Verified_Fields__c.Status__c in the database
                dbStatus: dbStatus,
                // Store original DB values to detect if user changed back to original
                originalDbStatus: originalDbStatus,
                originalDbComments: originalDbComments,
                // Document properties
                documentAttachments: processedAttachments,
                hasDocuments: processedAttachments.length > 0,
                verificationRadioOptions: this.getVerificationOptionsForField(field, processedAttachments.length > 0),
                currentDocIndex: 0,
                currentDocIndexDisplay: 1,
                currentDoc: processedAttachments.length > 0 ? processedAttachments[0] : null,
                hasMultipleDocs: (field.totalAttachments || 0) > 1,
                disablePrevDoc: true,
                disableNextDoc: (field.totalAttachments || 0) <= 1,
                zoomLevel: 100,
                rotationAngle: 0,
                naturalWidth: null,
                naturalHeight: null,
                zoomWrapperStyle: 'zoom: 1; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0;',
                imageStyle: this.buildFieldImageStyle({ zoomLevel: 100, rotationAngle: 0, naturalWidth: null, naturalHeight: null })
            };
        });
    }
    
    /**
     * Group fields by Child_Section__c for display
     * Returns array of field groups, or null if no grouping needed
     */
    getGroupedFieldsForDisplay(fields) {
        if (!fields || fields.length === 0) return null;
        
        // Check if any field has childSection
        const hasChildSections = fields.some(field => field.childSection);
        
        if (!hasChildSections) {
            // No child sections - return null to use default flat display
            return null;
        }
        
        // Group fields by childSection
        const groupedFields = new Map();
        
        fields.forEach(field => {
            const sectionName = field.childSection || 'Default';
            
            if (!groupedFields.has(sectionName)) {
                groupedFields.set(sectionName, []);
            }
            groupedFields.get(sectionName).push(field);
        });
        
        // Convert to array of groups
        const fieldGroups = [];
        groupedFields.forEach((fieldsInSection, sectionName) => {
            fieldGroups.push({
                sectionName: sectionName,
                fields: fieldsInSection
            });
        });
        
        
        return fieldGroups;
    }
    
    /**
     * Build filter dropdown options from data
     */
    buildFilterOptions() {
        // No complex filter options needed for tab-based UI
            }
    
    /**
     * Check if a field has a mismatch (only for Manually Verified fields)
     * fieldVerificationId exists and fieldValueFromVerifiedFields != currentValueInDB
     */
    hasMismatch(field) {
        if (!field || !field.fieldVerificationId) {
            return false;
        }
        if (field.verificationStatus === 'Manually Verified') {
            // Handle null/undefined/empty string comparisons correctly
            const verifiedValue = field.fieldValueFromVerifiedFields != null ? String(field.fieldValueFromVerifiedFields).trim() : '';
            const currentValue = field.currentValueInDB != null ? String(field.currentValueInDB).trim() : '';
            const hasValueMismatch = verifiedValue !== currentValue;
            const hasDocumentMismatch = this.hasDocumentMismatch(field);
            return hasValueMismatch || hasDocumentMismatch;
        }
        if (field.verificationStatus === 'Cannot Verify') {
            const hasDocuments =
                (field.documentAttachments && field.documentAttachments.length > 0) ||
                ((field.totalAttachments || 0) > 0) ||
                field.hasDocuments === true;
            return hasDocuments;
        }
        return false;
    }

    hasPreviousVerifiedDocuments(field) {
        if (!field) return false;
        const previousIds = field.originalVerifiedDocumentIds ?? field.verifiedStatusDocumentIds;
        const previousNames = field.originalVerifiedDocumentNames ?? field.verifiedStatusDocumentNames;
        const hasIds = previousIds != null && String(previousIds).trim() !== '';
        const hasNames = previousNames != null && String(previousNames).trim() !== '';
        return hasIds || hasNames;
    }
    
    /**
     * Filter fields based on selected filters
     */
    isFieldPendingChange(field) {
        if (!field) return false;

        const originalDbStatus = (field.originalDbStatus !== undefined && field.originalDbStatus !== null)
            ? field.originalDbStatus
            : (field.dbStatus || 'Not verified');
        const originalDbComments = (field.originalDbComments || '').trim();
        const currentStatus = field.verificationStatus || 'Not verified';
        const currentComments = (field.verificationComments || '').trim();

        const statusChanged = currentStatus !== originalDbStatus;
        const commentsChanged = currentComments !== originalDbComments;
        const needsReverify = field.needsReverify === true ||
            (field.fieldVerificationId && this.reverifiedFields && this.reverifiedFields.has(field.fieldVerificationId));

        return statusChanged || commentsChanged || needsReverify;
    }

    filterFields(fields) {
        if (!fields || fields.length === 0) return [];
        const filterOn = this.selectedFilterOn;
        const filterBy = this.selectedFilterBy;
        const isStatusFilter = filterOn === 'Status';
        const isDocumentPresenceFilter = filterOn === 'Document';
        const isMismatchFilter = filterOn === 'Mismatches';
        
        return fields.filter(field => {
            // Filter out fields with empty values
            if (!field.currentValueInDB || field.currentValueInDB.trim() === '') {
                return false;
            }
            
            // Filter by verification status
            if (isStatusFilter && filterBy && filterBy !== 'All') {
                if (field.verificationStatus !== filterBy) {
                    // Keep unsaved edits visible under status filters until user clicks Save.
                    if (!this.isFieldPendingChange(field)) {
                        return false;
                    }
                }
            }
            
            // Filter by mismatches
            if (isMismatchFilter) {
                const fieldHasDataMismatch = field.hasValueMismatch === true;
                const fieldHasDocumentMismatch = field.hasDocumentMismatch === true;
                const hasDocuments =
                    (field.documentAttachments && field.documentAttachments.length > 0) ||
                    ((field.totalAttachments || 0) > 0) ||
                    field.hasDocuments === true;
                const originalStatus = field.originalDbStatus || field.dbStatus || field.verificationStatus || 'Not verified';
                const fieldHasMismatch =
                    filterBy === 'DataMismatch'
                        ? fieldHasDataMismatch
                        : (filterBy === 'DocumentMismatch'
                            ? fieldHasDocumentMismatch
                            : (filterBy === 'DocumentsDeleted'
                                ? (originalStatus === 'Manually Verified' && this.hasPreviousVerifiedDocuments(field) && !hasDocuments)
                                : (filterBy === 'CannotVerifyDocsUploaded'
                                    ? (originalStatus === 'Cannot Verify' && hasDocuments)
                                    : (field.hasMismatch !== undefined ? field.hasMismatch : this.hasMismatch(field)))));
                if (!fieldHasMismatch) {
                    // Keep reverified/dirty fields visible in mismatch view until Save.
                    if (!this.isFieldPendingChange(field)) {
                        return false;
                    }
                }
            }

            // Filter by document presence
            if (isDocumentPresenceFilter) {
                // IMPORTANT: This must use dynamically mapped checklist documents only.
                // Do not use persisted Verified_Fields__c document ids for filtering.
                const hasDocuments =
                    (field.documentAttachments && field.documentAttachments.length > 0) ||
                    ((field.totalAttachments || 0) > 0) ||
                    field.hasDocuments === true;
                if (filterBy === 'WithDocuments' && !hasDocuments) {
                    return false;
                }
                if (filterBy === 'WithoutDocuments' && hasDocuments) {
                    return false;
                }
            }
            
            return true;
        });
    }

    normalizeCsvFromArray(values) {
        if (!values || values.length === 0) return '';
        const normalized = values
            .map((item) => (item == null ? '' : String(item).trim()))
            .filter((item) => item.length > 0)
            .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
        return normalized.join(',');
    }
    
    /**
     * Get filtered loan application fields
     */
    get loanApplicationFields() {
        if (!this.loanApplicationData) return [];
        return this.filterFields(this.loanApplicationData.fields);
    }
    
    /**
     * Get grouped loan application fields for display
     * Returns grouped structure if Child_Section__c is set, otherwise returns null
     */
    get loanApplicationFieldsGrouped() {
        if (!this.loanApplicationData) return null;
        const filteredFields = this.filterFields(this.loanApplicationData.fields);
        return this.getGroupedFieldsForDisplay(filteredFields);
    }
    
    /**
     * Check if loan application fields should be grouped
     */
    get shouldGroupLoanApplicationFields() {
        return this.loanApplicationFieldsGrouped !== null;
    }

    normalizeCommaSeparatedValue(value) {
        if (!value) return '';
        return String(value)
            .split(',')
            .map((part) => part.trim())
            .filter((part) => part.length > 0)
            .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }))
            .join(',');
    }

    getCurrentDocumentIdsFromField(field) {
        const docs = field?.documentAttachments || [];
        return this.normalizeCsvFromArray(docs.map((doc) => doc?.contentVersionId || doc?.contentDocumentId || ''));
    }

    getCurrentDocumentVersionIdsFromField(field) {
        const docs = field?.documentAttachments || [];
        return this.normalizeCsvFromArray(docs.map((doc) => doc?.contentVersionId || ''));
    }

    getCurrentDocumentEntityIdsFromField(field) {
        const docs = field?.documentAttachments || [];
        return this.normalizeCsvFromArray(docs.map((doc) => doc?.contentDocumentId || ''));
    }

    getCurrentDocumentNamesFromField(field) {
        const docs = field?.documentAttachments || [];
        return this.normalizeCsvFromArray(docs.map((doc) => doc?.title || doc?.fileName || ''));
    }

    hasDocumentMismatch(field) {
        if (!field || !field.fieldVerificationId) {
            return false;
        }
        if (field.verificationStatus !== 'Manually Verified') {
            return false;
        }

        // Production guard: if saved verified document id is blank/null, do not flag mismatch.
        const savedVerifiedDocIds = this.normalizeCommaSeparatedValue(field.verifiedStatusDocumentIds || '');
        if (!savedVerifiedDocIds) {
            return false;
        }

        const currentVersionIds = this.getCurrentDocumentVersionIdsFromField(field);
        const currentEntityIds = this.getCurrentDocumentEntityIdsFromField(field);

        // Support existing production data where saved ids may be either version ids or document ids.
        if (savedVerifiedDocIds === currentVersionIds || savedVerifiedDocIds === currentEntityIds) {
            return false;
        }
        return true;
    }

    getVerificationOptionsForField(field, hasDocuments) {
        // Cannot Verify should be shown only for fields without mapped documents.
        if (!hasDocuments || field?.verificationStatus === 'Cannot Verify') {
            return this.verificationRadioOptionsWithCannotVerify;
        }
        return this.verificationRadioOptions;
    }

    getFieldDocumentSubCategory(field) {
        const rawValue = field?.documentSubCategoryName ||
            field?.documentSubCategory ||
            field?.documentSubcategory ||
            field?.subCategory ||
            field?.documentMasterName ||
            field?.documentCategoryName ||
            field?.documentCategory ||
            'Uncategorized';
        return this.normalizeCommaSeparatedValue(rawValue) || 'Uncategorized';
    }

    getFieldBucketGroupKey(field) {
        const subCategory = this.getFieldDocumentSubCategory(field) || 'Uncategorized';
        const additionalFilterApi = field?.additionalDocumentApiNameToFilter || '';
        const additionalFilterValue = this.normalizeCommaSeparatedValue(field?.additionalDocumentValueToFilter || '');
        const sourceMode = field?.documentSourceMode || (field?.fallbackToParentDocument ? 'SELF_WITH_PARENT_FALLBACK' : 'SELF_ONLY');
        const docSetSignature = this.getFieldDocumentSetSignature(field);
        return `${subCategory}-${additionalFilterApi}-${additionalFilterValue}-${sourceMode}-${docSetSignature}`;
    }

    getFieldDocumentSetSignature(field) {
        const attachments = Array.isArray(field?.documentAttachments) ? field.documentAttachments : [];
        if (!attachments.length) {
            return 'NO_DOCS';
        }
        const ids = attachments
            .map((doc) => doc?.contentVersionId || doc?.contentDocumentId || '')
            .filter((id) => id)
            .sort();
        return ids.length ? ids.join('|') : 'NO_DOCS';
    }

    buildDocumentBuckets(fields, keyPrefix = 'LA') {
        if (!fields || fields.length === 0) return [];

        const bucketMap = new Map();
        fields.forEach((field) => {
            const subCategory = this.getFieldDocumentSubCategory(field);
            const bucketGroupKey = this.getFieldBucketGroupKey(field);
            const bucketKey = `${keyPrefix}_${bucketGroupKey}`.replace(/\s+/g, '_');
            if (!bucketMap.has(bucketKey)) {
                bucketMap.set(bucketKey, {
                    bucketKey,
                    subCategory,
                    additionalFilterApiName: field?.additionalDocumentApiNameToFilter || '',
                    additionalFilterValue: this.normalizeCommaSeparatedValue(field?.additionalDocumentValueToFilter || ''),
                    fields: [],
                    allDocs: []
                });
            }
            const bucket = bucketMap.get(bucketKey);
            const stableFieldIdentity =
                field.fieldVerificationId ||
                field.uniqueKey ||
                `${field.recordId || 'NO_RECORD'}_${field.fieldName || 'NO_FIELD'}`;
            const stableFieldQualifier = (field.fieldLabel || field.childSection || '').replace(/\s+/g, '_');

            bucket.fields.push({
                ...field,
                // Use a deterministic key so filtered list re-order/removal does not leak UI state to sibling rows.
                fieldBucketKey: `${bucketKey}_${stableFieldIdentity}_${stableFieldQualifier}`
            });
            if (field.documentAttachments && field.documentAttachments.length > 0) {
                bucket.allDocs.push(...field.documentAttachments);
            }
        });

        return Array.from(bucketMap.values()).map((bucket) => {
            const deduped = [];
            const seen = new Set();
            bucket.allDocs.forEach((doc) => {
                const key = doc.contentVersionId || doc.contentDocumentId || `${doc.title || ''}_${doc.fileExtension || ''}`;
                if (!seen.has(key)) {
                    seen.add(key);
                    deduped.push(doc);
                }
            });

            const state = this.bucketUiState[bucket.bucketKey] || {
                currentDocIndex: 0,
                zoomLevel: 100,
                rotationAngle: 0,
                naturalWidth: null,
                naturalHeight: null
            };
            const maxIndex = deduped.length > 0 ? deduped.length - 1 : 0;
            const currentDocIndex = Math.max(0, Math.min(state.currentDocIndex || 0, maxIndex));
            const currentDoc = deduped.length > 0 ? deduped[currentDocIndex] : null;
            const zoomLevel = state.zoomLevel || 100;
            const rotationAngle = state.rotationAngle || 0;
            const naturalWidth = state.naturalWidth ?? null;
            const naturalHeight = state.naturalHeight ?? null;

            return {
                ...bucket,
                allDocs: deduped,
                documentAttachments: deduped,
                hasDocuments: deduped.length > 0,
                hasMultipleDocs: deduped.length > 1,
                previewPaneHeightPx: this.getPreviewPaneHeightForBucket(deduped.length),
                totalAttachments: deduped.length,
                currentDocIndex,
                currentDocIndexDisplay: deduped.length > 0 ? currentDocIndex + 1 : 0,
                currentDoc,
                disablePrevDoc: currentDocIndex === 0,
                disableNextDoc: currentDocIndex >= maxIndex,
                zoomLevel,
                rotationAngle,
                naturalWidth,
                naturalHeight,
                imageStyle: this.buildBucketImageStyle({ naturalWidth, naturalHeight }),
                zoomWrapperStyle: this.getBucketZoomWrapperStyle({ zoomLevel, rotationAngle, naturalWidth, naturalHeight })
            };
        });
    }

    buildBucketImageStyle(bucketState) {
        if (bucketState.naturalWidth != null && bucketState.naturalHeight != null) {
            return `width: ${bucketState.naturalWidth}px; height: ${bucketState.naturalHeight}px; max-width: none; display: block;`;
        }
        return 'display: block; max-width: 100%;';
    }

    getBucketZoomWrapperStyle(bucketState) {
        const zoom = (bucketState.zoomLevel || 100) / 100;
        const rot = bucketState.rotationAngle || 0;
        const baseStyle = `zoom: ${zoom}; transform: rotate(${rot}deg); transition: transform 0.3s; transform-origin: 50% 50%; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0;`;
        if (bucketState.naturalWidth == null || bucketState.naturalHeight == null) {
            return baseStyle;
        }
        const rotNorm = Math.abs(rot % 360);
        const swap = rotNorm === 90 || rotNorm === 270;
        const w = swap ? Math.max(bucketState.naturalWidth, bucketState.naturalHeight) : bucketState.naturalWidth;
        const h = swap ? Math.max(bucketState.naturalWidth, bucketState.naturalHeight) : bucketState.naturalHeight;
        return `width: ${w}px; height: ${h}px; ${baseStyle}`;
    }

    get loanApplicationBucketedSections() {
        if (!this.loanApplicationData) return [];
        const filteredFields = this.filterFields(this.loanApplicationData.fields);
        const grouped = this.getGroupedFieldsForDisplay(filteredFields);

        if (grouped) {
            return grouped.map((section) => ({
                sectionName: section.sectionName,
                showSectionHeader: true,
                buckets: this.buildDocumentBuckets(section.fields, `LA_${section.sectionName}`)
            }));
        }

        return [{
            sectionName: 'All Fields',
            showSectionHeader: false,
            buckets: this.buildDocumentBuckets(filteredFields, 'LA_ALL')
        }];
    }

    getBucketByKey(bucketKey) {
        const sections = this.loanApplicationBucketedSections || [];
        for (const section of sections) {
            const found = (section.buckets || []).find((bucket) => bucket.bucketKey === bucketKey);
            if (found) return found;
        }
        const applicants = this.filteredApplicantsData || [];
        for (const group of applicants) {
            for (const record of (group.records || [])) {
                for (const fieldSection of (record.fieldSectionTabs || [])) {
                    const found = (fieldSection.buckets || []).find((bucket) => bucket.bucketKey === bucketKey);
                    if (found) return found;
                }
                for (const childTab of (record.childTabs || [])) {
                    for (const childRecord of (childTab.records || [])) {
                        const found = (childRecord.buckets || []).find((bucket) => bucket.bucketKey === bucketKey);
                        if (found) return found;
                        for (const nestedTab of (childRecord.childTabs || [])) {
                            for (const nestedRecord of (nestedTab.records || [])) {
                                const nestedFound = (nestedRecord.buckets || []).find((bucket) => bucket.bucketKey === bucketKey);
                                if (nestedFound) return nestedFound;
                            }
                        }
                    }
                }
            }
        }
        return null;
    }

    resolveBucketKeyFromEvent(event) {
        const direct = event?.currentTarget?.dataset?.bucket || event?.target?.dataset?.bucket;
        if (direct) return direct;
        const path = event?.composedPath ? event.composedPath() : [];
        for (const node of path) {
            if (node?.dataset?.bucket) {
                return node.dataset.bucket;
            }
        }
        return null;
    }
    
    /**
     * Get grouped fields for a record
     * Returns grouped structure if Child_Section__c is set, otherwise returns null
     */
    getGroupedFieldsForRecord(record) {
        if (!record || !record.fields) return null;
        const filteredFields = this.filterFields(record.fields);
        return this.getGroupedFieldsForDisplay(filteredFields);
    }
    
    /**
     * Get filtered Level 2 objects with filtered fields
     */
    get filteredApplicants() {
        return this.filteredApplicantsData;
    }

    get activeFilterValueForHighlight() {
        if (this.selectedFilterOn === 'Status') {
            return this.selectedFilterBy === 'All' ? '' : (this.selectedFilterBy || '');
        }
        return this.selectedFilterBy || '';
    }

    get isStatusFilterActive() {
        return !!this.activeFilterValueForHighlight;
    }

    get loanApplicationTabLabel() {
        const baseLabel = 'Loan Application';
        if (!this.isStatusFilterActive || !this.loanApplicationData?.fields) {
            return baseLabel;
        }
        const hasFilteredFields = this.filterFields(this.loanApplicationData.fields).length > 0;
        return this.getHighlightedTabLabel(baseLabel, hasFilteredFields);
    }

    getHighlightedTabLabel(baseLabel, hasFilteredFields) {
        if (!this.isStatusFilterActive || !hasFilteredFields) {
            return baseLabel;
        }
        return `${baseLabel} 🔴`;
    }

    hasRenderableFilteredFieldsInBuckets(buckets) {
        return (buckets || []).some((bucket) => (bucket?.fields || []).length > 0);
    }
    
    updateFilteredApplicants() {
        if (!this.applicants || this.applicants.length === 0) {
            this.filteredApplicantsData = [];
            return;
        }
        
        
        // Apply filters to fields but keep all tabs/records visible
        this.filteredApplicantsData = this.applicants.map(objectGroup => {
            const filteredRecords = objectGroup.records.map(record => {
                // Rebuild childTabs with filtered data, preserving section-based grouping
                const filteredChildTabs = record.childTabs ? record.childTabs.map(childTab => {
                    const mappedChildRecords = childTab.records.map(childRecord => {
                        const filteredChildFields = this.filterFields(childRecord.fields);
                        const childBuckets = this.buildDocumentBuckets(filteredChildFields, `CHILD_${childRecord.recordId}_${childTab.sectionKey}`);
                        const filteredNestedTabs = childRecord.childTabs ? childRecord.childTabs.map(nestedTab => {
                            const mappedNestedRecords = (nestedTab.records || []).map(nestedRecord => {
                                const filteredNestedFields = this.filterFields(nestedRecord.fields);
                                const nestedBuckets = this.buildDocumentBuckets(filteredNestedFields, `NESTED_${nestedRecord.recordId}_${nestedTab.sectionKey}`);
                                return {
                                    ...nestedRecord,
                                    fields: filteredNestedFields,
                                    buckets: nestedBuckets
                                };
                            });
                            const hasNestedFilteredFields = mappedNestedRecords.some((nestedRecord) =>
                                (nestedRecord.fields || []).length > 0 || this.hasRenderableFilteredFieldsInBuckets(nestedRecord.buckets)
                            )
                            return {
                                label: nestedTab.label,
                                displayLabel: this.getHighlightedTabLabel(nestedTab.label, hasNestedFilteredFields),
                                icon: nestedTab.icon,
                                objectName: nestedTab.objectName,
                                sectionKey: nestedTab.sectionKey,
                                hasRecords: nestedTab.hasRecords,
                                hasFilteredFields: hasNestedFilteredFields,
                                records: mappedNestedRecords
                            };
                        }) : [];
                        const hasOwnChildFilteredFields =
                            (filteredChildFields || []).length > 0 ||
                            this.hasRenderableFilteredFieldsInBuckets(childBuckets);
                        const hasChildFilteredFields =
                            hasOwnChildFilteredFields ||
                            filteredNestedTabs.some((tab) => tab.hasFilteredFields);
                        return {
                            ...childRecord,
                            fields: filteredChildFields,
                            buckets: childBuckets,
                            childTabs: filteredNestedTabs,
                            hasChildren: filteredNestedTabs.some((tab) => tab.hasFilteredFields),
                            hasFilteredFields: hasChildFilteredFields,
                            displayChildTabLabel: this.getHighlightedTabLabel(childTab.label, hasOwnChildFilteredFields)
                        };
                    });
                    const hasFilteredFields = mappedChildRecords.some((childRecord) =>
                        (childRecord.fields || []).length > 0 ||
                        this.hasRenderableFilteredFieldsInBuckets(childRecord.buckets) ||
                        (childRecord.childTabs || []).some((nestedTab) => nestedTab.hasFilteredFields)
                    );
                    return {
                        label: childTab.label,
                        displayLabel: this.getHighlightedTabLabel(childTab.label, hasFilteredFields),
                        icon: childTab.icon,
                        objectName: childTab.objectName,
                        sectionKey: childTab.sectionKey,
                        hasRecords: childTab.hasRecords,
                        hasFilteredFields,
                        records: mappedChildRecords
                    };
                }) : [];
                
                
                // Group fields by childSectionName to create separate tabs
                const filteredFields = this.filterFields(record.fields);
                const fieldsByChildSection = new Map();
                
                filteredFields.forEach(field => {
                    const sectionName = field.childSection || 'Personal Information';
                    if (!fieldsByChildSection.has(sectionName)) {
                        fieldsByChildSection.set(sectionName, []);
                    }
                    fieldsByChildSection.get(sectionName).push(field);
                });
                
                // Create field section tabs (Personal Info + Child Sections)
                const fieldSectionTabs = [];
                fieldsByChildSection.forEach((fields, sectionName) => {
                    const sectionBuckets = this.buildDocumentBuckets(fields, `APP_${record.recordId}_${sectionName}`);
                    const hasFilteredFields = (fields || []).length > 0 || this.hasRenderableFilteredFieldsInBuckets(sectionBuckets);
                    fieldSectionTabs.push({
                        tabId: `${record.recordId}_${sectionName.replace(/\s+/g, '_')}`,
                        label: sectionName,
                        displayLabel: this.getHighlightedTabLabel(sectionName, hasFilteredFields),
                        icon: sectionName === 'Personal Info' ? 'standard:user' : 'standard:record',
                        fields: fields,
                        buckets: sectionBuckets,
                        isPersonalInfo: sectionName === 'Personal Info',
                        hasFilteredFields
                    });
                });

                const hasRecordFilteredFields =
                    fieldSectionTabs.some(sectionTab => sectionTab.hasFilteredFields) ||
                    filteredChildTabs.some(childTab => childTab.hasFilteredFields);
                
                return {
                    tabId: record.tabId,
                    tabLabel: record.tabLabel,
                    displayTabLabel: this.getHighlightedTabLabel(record.tabLabel, hasRecordFilteredFields),
                    recordId: record.recordId,
                    recordLabel: record.recordLabel,
                    sectionName: record.sectionName,
                    objectName: record.objectName,
                    fields: this.filterFields(record.fields),
                    fieldSectionTabs: fieldSectionTabs, // NEW: Tabs for field sections
                    hasFieldSections: fieldSectionTabs.length > 0,
                    childTabs: filteredChildTabs,
                    hasChildren: filteredChildTabs.length > 0,
                    hasFields: record.hasFields,
                    hasFilteredFields: hasRecordFilteredFields,
                    showIntegrationTabs: record.showIntegrationTabs
                };
            });

            const hasObjectGroupFilteredFields = filteredRecords.some(record => record.hasFilteredFields);
            
            return {
                objectName: objectGroup.objectName,
                sectionName: objectGroup.sectionName,
                displaySectionName: this.getHighlightedTabLabel(objectGroup.sectionName, hasObjectGroupFilteredFields),
                sectionKey: objectGroup.sectionKey,
                hasFilteredFields: hasObjectGroupFilteredFields,
                records: filteredRecords
            };
        });
        
        
        // Create a flat list of child tabs with parent mapping
        this.allChildTabsFlat = [];
        this.filteredApplicantsData.forEach(group => {
            group.records.forEach(rec => {
                if (rec.childTabs && rec.childTabs.length > 0) {
                    rec.childTabs.forEach(tab => {
                        this.allChildTabsFlat.push({
                            ...tab,
                            parentRecordId: rec.recordId,
                            parentLabel: rec.recordLabel
                        });
                    });
                }
            });
        });
        
    }
    
    /**
     * Check if Send Back button should be disabled
     */
    get disableSendBackButton() {
        return !this.enableSendBackButton;
    }

    /**
     * Check if Submit button should be disabled
     */
    get disableSubmitButton() {
        // Submit is disabled only if enableSendForwardButton is false
        // Warnings (open cases/failed integrations) are informational and don't block Submit
        return !this.enableSendForwardButton;
    }

    get showSubmitActionButton() {
        // Hide final action buttons when callback validation warnings/errors exist.
        return !this.hasValidationMessages;
    }

    get validationWarningMessages() {
        return (this.validationMessages || []).filter((msg) => msg.isWarning);
    }

    get validationErrorMessages() {
        return (this.validationMessages || []).filter((msg) => msg.isError);
    }

    get groupedValidationWarningMessages() {
        return this.groupValidationMessagesByHeader(this.validationWarningMessages);
    }

    get groupedValidationErrorMessages() {
        return this.groupValidationMessagesByHeader(this.validationErrorMessages);
    }

    get hasValidationWarningMessages() {
        return this.validationWarningMessages.length > 0;
    }

    get hasValidationErrorMessages() {
        return this.validationErrorMessages.length > 0;
    }

    groupValidationMessagesByHeader(messages) {
        const groupsByHeader = new Map();
        (messages || []).forEach((msg, index) => {
            const header = msg?.header || 'Validation';
            if (!groupsByHeader.has(header)) {
                groupsByHeader.set(header, {
                    groupKey: `${header}-${index}`,
                    header,
                    messages: []
                });
            }
            groupsByHeader.get(header).messages.push({
                messageKey: msg?.messageKey || `${header}-msg-${index}`,
                message: msg?.message || ''
            });
        });
        return Array.from(groupsByHeader.values());
    }
    
    get bucketRowClass() {
        return `slds-grid slds-wrap bucket-row bucket-row-${this.selectedBucketHeight}`;
    }

    get selectedBucketHeightPx() {
        return `${this.selectedBucketHeight || '600'}px`;
    }

    get previewPaneHeightPx() {
        const rawHeight = parseInt(this.selectedBucketHeight || '600', 10);
        const safeHeight = Number.isFinite(rawHeight) ? rawHeight : 600;
        // Keep preview strictly inside bucket area (toolbar + controls need headroom).
        return `${Math.max(280, Math.floor(safeHeight * 0.8))}px`;
    }

    getPreviewPaneHeightForBucket(documentCount) {
        const rawHeight = parseInt(this.selectedBucketHeight || '600', 10);
        const safeHeight = Number.isFinite(rawHeight) ? rawHeight : 600;
        // When the multi-doc navigator appears, reserve more vertical space for controls.
        const ratio = documentCount > 1 ? 0.7 : 0.8;
        return `${Math.max(240, Math.floor(safeHeight * ratio))}px`;
    }

    handleBucketHeightChange(event) {
        const nextHeight = event.detail.value || '600';
        this.selectedBucketHeight = this.isValidPreviewHeight(nextHeight) ? nextHeight : '600';
        this.savePreviewHeightPreference(this.selectedBucketHeight);
    }
    
    /**
     * Check if there's any data to display
     */
    get hasData() {
        return this.loanApplicationData || this.applicants.length > 0;
    }
    
    /**
     * Check if we have applicants
     */
    get hasApplicants() {
        return this.displayedApplicants && this.displayedApplicants.length > 0;
    }
    
    /**
     * Get applicants to display - always show all sections including empty ones
     */
    get displayedApplicants() {
        return this.filteredApplicantsData;
    }
    
    /**
     * Check if there are any applicants with integration tabs
     */
    get hasApplicantIntegrations() {
        return false;
    }
    
    /**
     * Get list of applicants for integration tabs (displayed at the end)
     */
    get applicantIntegrationsList() {
        return [];
    }
    
    // ============================================================================
    // FILTER HANDLERS
    // ============================================================================
    
    get filterByOptions() {
        if (this.selectedFilterOn === 'Document') {
            return this.documentFilterByOptions;
        }
        if (this.selectedFilterOn === 'Mismatches') {
            return this.mismatchFilterByOptions;
        }
        return this.statusFilterByOptions;
    }

    get isMismatchFilterOn() {
        return this.selectedFilterOn === 'Mismatches';
    }

    get filterByColumnClass() {
        return this.isMismatchFilterOn
            ? 'slds-col filter-control-col mismatch-filter-col'
            : 'slds-col filter-control-col';
    }

    handleFilterOnChange(event) {
        this.selectedFilterOn = event.detail.value;
        if (this.selectedFilterOn === 'Status') {
            this.selectedFilterBy = 'Not Verified';
        } else if (this.selectedFilterOn === 'Document') {
            this.selectedFilterBy = 'WithDocuments';
        } else if (this.selectedFilterOn === 'Mismatches') {
            this.selectedFilterBy = 'DataMismatch';
        } else {
            const nextOptions = this.filterByOptions;
            this.selectedFilterBy = nextOptions.length > 0 ? nextOptions[0].value : '';
        }
        this.updateFilteredApplicants(); // Reapply filters
    }

    handleFilterByChange(event) {
        this.selectedFilterBy = event.detail.value;
        this.updateFilteredApplicants(); // Reapply filters
    }
    
    // ============================================================================
    // FIELD EDIT HANDLERS
    // ============================================================================
    
    handleVerificationStatusChangeInline(event) {
        try {
        const fieldName = event.target.dataset.field;
        const recordId = event.target.dataset.record;
        const newStatus = event.detail.value;
        
            if (!fieldName || !recordId) {
                console.error('Missing fieldName or recordId:', { fieldName, recordId });
                return;
            }
            
            // Find the field to check if it's locked and get original DB value
        const field = this.findField(fieldName, recordId);
            if (!field) {
                console.error('Field not found:', fieldName, recordId);
                return;
            }
            
            if (field.isFieldLocked) {
            this.showToast('Error', 'Cannot modify digitally verified fields', 'error');
            return;
        }
        
            // Get original DB status for comparison
            const originalDbStatus = (field.originalDbStatus !== undefined && field.originalDbStatus !== null) 
                ? field.originalDbStatus 
                : (field.dbStatus || 'Not verified');
                
            // Check if status was changed before update
            const wasChanged = (field.verificationStatus || 'Not verified') !== originalDbStatus;
            
            // Update verification status
        this.updateFieldProperty(fieldName, recordId, 'verificationStatus', newStatus);
            
            // Check if status is changed after update
            const isChanged = newStatus !== originalDbStatus;
            
            // Update counter: increment if changed, decrement if reverted
            if (isChanged && !wasChanged) {
                // Status just changed from original
                this.changedStatusCount++;
            } else if (!isChanged && wasChanged) {
                // Status reverted to original
                this.changedStatusCount = Math.max(0, this.changedStatusCount - 1);
            }
            
            // Force reactivity by updating the counters explicitly (LWC needs this for reactive properties)
            this.changedStatusCount = this.changedStatusCount;
            
            // Trigger reactivity to ensure Save button visibility updates
            this.triggerReactivity();
            
            // Re-evaluate button visibility after field update
            this.evaluateSendBackVisibility();
        } catch (error) {
            console.error('Error in handleVerificationStatusChangeInline:', error);
            this.showToast('Error', 'An error occurred while updating verification status', 'error');
        }
    }
    
    handleVerificationCommentsChange(event) {
        try {
        const fieldName = event.target.dataset.field;
        const recordId = event.target.dataset.record;
            const newValue = event.detail.value || '';
            
            if (!fieldName || !recordId) {
                console.error('Missing fieldName or recordId:', { fieldName, recordId });
                return;
            }
        
        // Find the field to check if it's locked and get original DB value
        const field = this.findField(fieldName, recordId);
            if (!field) {
                console.error('Field not found:', fieldName, recordId);
                return;
            }
            
            if (field.isFieldLocked) {
            this.showToast('Error', 'Cannot modify digitally verified fields', 'error');
            return;
        }
        
            // Get original DB comments for comparison
            const originalDbComments = field.originalDbComments || '';
            const currentComments = (field.verificationComments || '').trim();
                
            // Check if comments were changed before update
            const wasChanged = currentComments !== originalDbComments.trim();
            
            // Update comments
        this.updateFieldProperty(fieldName, recordId, 'verificationComments', newValue);
            
            // Check if comments are changed after update
            const isChanged = newValue.trim() !== originalDbComments.trim();
            
            // Update counter: increment if changed, decrement if reverted
            if (isChanged && !wasChanged) {
                // Comments just changed from original
                this.changedCommentsCount++;
            } else if (!isChanged && wasChanged) {
                // Comments reverted to original
                this.changedCommentsCount = Math.max(0, this.changedCommentsCount - 1);
            }
            
            // Force reactivity by updating the counters explicitly (LWC needs this for reactive properties)
            this.changedCommentsCount = this.changedCommentsCount;
            
            // Trigger reactivity to ensure Save button visibility updates
            this.triggerReactivity();
            
            // Re-evaluate button visibility after field update
            this.evaluateSendBackVisibility();
        } catch (error) {
            console.error('Error in handleVerificationCommentsChange:', error);
            this.showToast('Error', 'An error occurred while updating verification comments', 'error');
        }
    }
    
    /**
     * Update a field property in the organized data
     */
    updateFieldProperty(fieldName, recordId, property, value) {
        let updated = false;
        
        // Update in loan application
        if (this.loanApplicationData && this.loanApplicationData.recordId === recordId) {
            this.loanApplicationData = {
                ...this.loanApplicationData,
                fields: this.loanApplicationData.fields.map(field => {
                    if (field.fieldName === fieldName) {
                        updated = true;
                        return { ...field, [property]: value };
                    }
                    return field;
                })
            };
        }
        
        // Update in Level 2 objects and their children (includes LoanApplicant, Guardian, LoanApplicationProperty, etc.)
        this.applicants = this.applicants.map(objectGroup => ({
            ...objectGroup,
            records: objectGroup.records.map(record => {
                // Check record's own fields (Level 2)
                if (record.recordId === recordId) {
                    updated = true;
                    return {
                        ...record,
                        fields: record.fields.map(field => {
                            if (field.fieldName === fieldName) {
                                return { ...field, [property]: value };
                            }
                            return field;
                        })
                    };
                }
                
                // Check child records - generic approach using childRecords Map (Level 3)
                if (record.childRecords && record.childRecords.size > 0) {
                    const updatedChildRecords = new Map();
                    let childUpdated = false;
                    
                    record.childRecords.forEach((childList, childObjectName) => {
                        const updatedChildList = childList.map(childRec => {
                            if (childRec.recordId === recordId) {
                                updated = true;
                                childUpdated = true;
                                return {
                                    ...childRec,
                                    fields: childRec.fields.map(field => {
                                        if (field.fieldName === fieldName) {
                                            return { ...field, [property]: value };
                                        }
                                        return field;
                                    })
                                };
                            }

                            if (childRec.childRecords && childRec.childRecords.size > 0) {
                                const updatedNestedChildRecords = new Map();
                                let nestedUpdated = false;

                                childRec.childRecords.forEach((nestedList, nestedSectionName) => {
                                    const updatedNestedList = (nestedList || []).map((nestedRec) => {
                                        if (nestedRec.recordId === recordId) {
                                            updated = true;
                                            childUpdated = true;
                                            nestedUpdated = true;
                                            return {
                                                ...nestedRec,
                                                fields: (nestedRec.fields || []).map((field) => {
                                                    if (field.fieldName === fieldName) {
                                                        return { ...field, [property]: value };
                                                    }
                                                    return field;
                                                })
                                            };
                                        }
                                        return nestedRec;
                                    });
                                    updatedNestedChildRecords.set(nestedSectionName, updatedNestedList);
                                });

                                if (nestedUpdated) {
                                    const updatedNestedTabs = (childRec.childTabs || []).map((nestedTab) => ({
                                        ...nestedTab,
                                        records: (nestedTab.records || []).map((nestedRecord) => {
                                            if (nestedRecord.recordId === recordId) {
                                                return {
                                                    ...nestedRecord,
                                                    fields: (nestedRecord.fields || []).map((field) => {
                                                        if (field.fieldName === fieldName) {
                                                            return { ...field, [property]: value };
                                                        }
                                                        return field;
                                                    })
                                                };
                                            }
                                            return nestedRecord;
                                        })
                                    }));

                                    return {
                                        ...childRec,
                                        childRecords: updatedNestedChildRecords,
                                        childTabs: updatedNestedTabs
                                    };
                                }
                            }
                            return childRec;
                        });
                        updatedChildRecords.set(childObjectName, updatedChildList);
                    });
                    
                    if (childUpdated) {
                        // Update childTabs to match the updated childRecords
                        // childTabs is what the UI actually uses, so we need to update it
                        const updatedChildTabs = record.childTabs ? record.childTabs.map(childTab => {
                            // Check if this tab contains the updated record
                            const hasUpdatedRecord = childTab.records && childTab.records.some(r => r.recordId === recordId);
                            const hasUpdatedNestedRecord = childTab.records && childTab.records.some(r =>
                                (r.childTabs || []).some((nestedTab) =>
                                    (nestedTab.records || []).some((nestedRecord) => nestedRecord.recordId === recordId)
                                )
                            );
                            if (hasUpdatedRecord || hasUpdatedNestedRecord) {
                                return {
                                    ...childTab,
                                    records: childTab.records.map(childRecord => {
                                        if (childRecord.recordId === recordId) {
                                            return {
                                                ...childRecord,
                                                fields: childRecord.fields.map(field => {
                                                    if (field.fieldName === fieldName) {
                                                        return { ...field, [property]: value };
                                                    }
                                                    return field;
                                                })
                                            };
                                        }
                                        if (hasUpdatedNestedRecord && childRecord.childTabs && childRecord.childTabs.length > 0) {
                                            return {
                                                ...childRecord,
                                                childTabs: childRecord.childTabs.map((nestedTab) => ({
                                                    ...nestedTab,
                                                    records: (nestedTab.records || []).map((nestedRecord) => {
                                                        if (nestedRecord.recordId === recordId) {
                                                            return {
                                                                ...nestedRecord,
                                                                fields: (nestedRecord.fields || []).map((field) => {
                                                                    if (field.fieldName === fieldName) {
                                                                        return { ...field, [property]: value };
                                                                    }
                                                                    return field;
                                                                })
                                                            };
                                                        }
                                                        return nestedRecord;
                                                    })
                                                }))
                                            };
                                        }
                                        return childRecord;
                                    })
                                };
                            }
                            return childTab;
                        }) : [];
                        
                        // Create a completely new record object to ensure reactivity
                        return {
                            ...record,
                            childRecords: updatedChildRecords,
                            childTabs: updatedChildTabs
                        };
                    }
                }
                
                return record;
            })
        }));
        
        // CRITICAL: After updating this.applicants, refresh filteredApplicantsData
        // This ensures that filtered data also reflects the changes
        if (updated) {
            // Update filteredApplicantsData to reflect the changes
            // This is critical because the UI uses filteredApplicantsData, not applicants directly
            this.updateFilteredApplicants();
            
            // Force deep reactivity by creating new array references
            // This ensures LWC detects the changes
            this.applicants = this.applicants.map(objectGroup => ({
                ...objectGroup,
                records: objectGroup.records.map(record => ({
                    ...record,
                    // Ensure childRecords Map is recreated for reactivity
                    childRecords: record.childRecords ? new Map(record.childRecords) : new Map(),
                    // Ensure childTabs array is deeply recreated for reactivity
                    childTabs: record.childTabs ? record.childTabs.map(tab => ({
                        ...tab,
                        records: tab.records ? tab.records.map(rec => ({
                            ...rec,
                            fields: rec.fields ? [...rec.fields] : []
                        })) : []
                    })) : []
                }))
            }));
        }
        
        if (!updated) {
            console.warn('⚠️ Field not found for update:', fieldName, 'recordId:', recordId);
            console.warn('   Searching in verificationData as fallback...');
            
            // Fallback: Try to update in verificationData directly
            if (this.verificationData && this.verificationData.length > 0) {
                for (let item of this.verificationData) {
                    if (item.recordId === recordId && item.fields) {
                        const fieldIndex = item.fields.findIndex(f => f && f.fieldName === fieldName);
                        if (fieldIndex >= 0) {
                            item.fields[fieldIndex][property] = value;
                            updated = true;
                            // Re-organize data to reflect the change
                            this.organizeData();
                            break;
                        }
                    }
                }
            }
        }
    }
    
    
    /**
     * Get all fields with changes (for saving)
     */
    getChangedFields() {
        const changedFields = [];
        
        // Helper to collect changed fields from a field array
        const collectChangedFields = (fields, recordId, objectName, parentRecordId = null) => {
            if (!fields || fields.length === 0) return;
            
            fields.forEach(field => {
                // Check if field has changed from DB value
                const originalDbStatus = (field.originalDbStatus !== undefined && field.originalDbStatus !== null) 
                    ? field.originalDbStatus 
                    : (field.dbStatus || 'Not verified');
                const originalDbComments = field.originalDbComments || '';
                
                const currentStatus = field.verificationStatus || 'Not verified';
                const currentComments = (field.verificationComments || '').trim();
                
                const statusChanged = currentStatus !== originalDbStatus;
                const commentsChanged = currentComments !== originalDbComments.trim();
                
                // Check if field needs reverification (marked by Reverify button)
                const needsReverify = field.needsReverify === true || 
                                     (field.fieldVerificationId && this.reverifiedFields.has(field.fieldVerificationId));
                
                if (statusChanged || commentsChanged || needsReverify) {
                    const docs = field.documentAttachments || [];
                    const isMarkedNotVerified = (field.verificationStatus || '') === 'Not Verified';
                    const verifiedStatusDocumentNames = isMarkedNotVerified
                        ? ''
                        : this.normalizeCsvFromArray(
                            docs.map((doc) => doc?.title || doc?.fileName || '')
                        );
                    const verifiedStatusDocumentIds = isMarkedNotVerified
                        ? ''
                        : this.normalizeCsvFromArray(
                            docs.map((doc) => doc?.contentVersionId || doc?.contentDocumentId || '')
                        );
                    const changeData = {
                        fieldName: field.fieldName,
                        fieldVerificationId: field.fieldVerificationId,
                        verificationStatus: field.verificationStatus,
                        verificationComments: field.verificationComments || '',
                        // For reverified fields, update fieldValue to currentValueInDB
                        fieldValue: needsReverify ? (field.currentValueInDB || '') : (field.currentValueInDB || ''),
                        recordId: recordId,
                        objectName: objectName,
                        loanApplicationId: this.recordId,
                        verifiedStatusDocumentNames,
                        verifiedStatusDocumentIds
                    };
                    
                    // Only add applicantId for Level 3 objects (child objects under Level 2)
                    if (parentRecordId) {
                        changeData.applicantId = parentRecordId;
                    }
                    
                    changedFields.push(changeData);
                }
            });
        };
        
        // Loan Application fields
        if (this.loanApplicationData && this.loanApplicationData.fields) {
            collectChangedFields(
                this.loanApplicationData.fields,
                this.loanApplicationData.recordId,
                'Application__c'
            );
        }
        
        // Level 2 object fields and their children
        if (this.applicants && this.applicants.length > 0) {
        this.applicants.forEach(objectGroup => {
                if (objectGroup.records && objectGroup.records.length > 0) {
            objectGroup.records.forEach(record => {
                // Record's own fields (Level 2)
                        if (record.fields && record.fields.length > 0) {
                collectChangedFields(
                    record.fields,
                    record.recordId,
                    record.objectName
                );
                        }
                
                // Child records (Level 3)
                if (record.childRecords && record.childRecords.size > 0) {
                    record.childRecords.forEach((childList, sectionKey) => {
                                if (childList && childList.length > 0) {
                        childList.forEach(childRec => {
                                        if (childRec.fields && childRec.fields.length > 0) {
                            collectChangedFields(
                                childRec.fields,
                                childRec.recordId,
                                childRec.objectName,
                                record.recordId
                            );
                                        }
                                        if (childRec.childRecords && childRec.childRecords.size > 0) {
                                            childRec.childRecords.forEach((nestedList) => {
                                                if (!nestedList || nestedList.length === 0) return;
                                                nestedList.forEach((nestedRec) => {
                                                    if (nestedRec.fields && nestedRec.fields.length > 0) {
                                                        collectChangedFields(
                                                            nestedRec.fields,
                                                            nestedRec.recordId,
                                                            nestedRec.objectName,
                                                            record.recordId
                                                        );
                                                    }
                                                });
                                            });
                                        }
                        });
                                }
                    });
                }
            });
                }
        });
        }
        
        return changedFields;
    }
    
    /**
     * Check if there are any unsaved changes AND user has permission to save
     * Uses counter-based approach: show Save/Cancel if either status or comments counter > 0
     * Also includes reverified fields
     */
    get hasChanges() {
        const hasReverifiedFields = this.reverifiedFields && this.reverifiedFields.size > 0;
        const hasChanges = this.canEditFields && (this.changedStatusCount > 0 || this.changedCommentsCount > 0 || hasReverifiedFields);
        return hasChanges;
    }
    
    /**
     * Check if fields should be disabled
     * Fields are disabled if:
     * - User doesn't have edit permission OR
     * - Field is digitally verified
     */
    get fieldsDisabled() {
        return !this.canEditFields;
    }
    
    /**
     * Store original data for cancel functionality
     */
    storeOriginalData() {
        // Deep clone the data structures to preserve original state
        this.originalLoanApplicationData = this.loanApplicationData ? JSON.parse(JSON.stringify(this.loanApplicationData)) : null;
        this.originalApplicants = this.applicants ? JSON.parse(JSON.stringify(this.applicants)) : null;
        this.originalVerificationData = this.verificationData ? JSON.parse(JSON.stringify(this.verificationData)) : null;
        
    }
    
    /**
     * Cancel all changes and revert to original data
     */
    handleCancelChanges() {
        // Clear reverified fields set
        this.reverifiedFields.clear();
        // Simply refresh the page to revert all changes
        window.location.reload();
    }
    
    /**
     * Get save button label
     */
    get saveButtonLabel() {
        return 'Save';
    }

    get showBulkCannotVerifyButton() {
        if (this.selectedFilterOn !== 'Document' || this.selectedFilterBy !== 'WithoutDocuments' || this.readOnly || !this.canEditFields) {
            return false;
        }
        return this.collectFieldsForCannotVerifyUpdate().length > 0;
    }
    
    // ============================================================================
    // SAVE HANDLER
    // ============================================================================
    
    async handleSaveAllChanges() {
        const changedFields = this.getChangedFields();
        
        if (changedFields.length === 0) {
            this.showToast('Info', 'No changes to save', 'info');
            return;
        }
        
        // Validate: Comments are mandatory when status is "Data Update Needed"
        const fieldsWithoutComments = changedFields.filter(field => 
            field.verificationStatus === 'Data Update Needed' && 
            (!field.verificationComments || field.verificationComments.trim() === '')
        );
        
        if (fieldsWithoutComments.length > 0) {
            this.showToast('Error', 'Comments are mandatory when status is "Data Update Needed"', 'error');
            return;
        }
        
        this.isLoading = true;
        
        try {
                        
            await saveFieldVerification({ 
                verificationData: JSON.stringify(changedFields) 
            });
            
            this.showToast('Success', `${changedFields.length} field(s) saved successfully`, 'success');
            
            // Reset change counters after successful save
            this.changedStatusCount = 0;
            this.changedCommentsCount = 0;
            
            // Clear reverified fields set after successful save
            this.reverifiedFields.clear();
            
            // Reload data to get updated verification status from database
            // This ensures DB Status reflects the saved values
            await this.loadData();
            
            // Store the new state as original data after save
            this.storeOriginalData();
            
            // Re-evaluate send back visibility after save
            this.evaluateSendBackVisibility();
            
            // Force UI update to ensure DB Status is displayed correctly
            this.triggerReactivity();
            
        } catch (error) {
            console.error('Error saving:', error);
            this.showToast('Error', error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    collectFieldsForCannotVerifyUpdate() {
        const updates = [];
        const seen = new Set();

        const addFieldUpdate = (field, recordId, objectName, applicantId = null) => {
            if (!field || !field.fieldName || !recordId || !objectName) return;
            const key = `${recordId}_${field.fieldName}`;
            if (seen.has(key)) return;
            seen.add(key);

            // Skip fields that are locked (digitally verified/cannot verify/no permission).
            if (field.isFieldLocked) return;
            // Skip fields already marked as Cannot Verify.
            if ((field.verificationStatus || '').toLowerCase() === 'cannot verify') return;

            const docs = field.documentAttachments || [];
            const verifiedStatusDocumentNames = this.normalizeCsvFromArray(
                docs.map((doc) => doc?.title || doc?.fileName || '')
            );
            const verifiedStatusDocumentIds = this.normalizeCsvFromArray(
                docs.map((doc) => doc?.contentVersionId || doc?.contentDocumentId || '')
            );

            updates.push({
                fieldName: field.fieldName,
                fieldVerificationId: field.fieldVerificationId,
                verificationStatus: 'Cannot Verify',
                verificationComments: field.verificationComments || '',
                fieldValue: field.currentValueInDB || '',
                recordId,
                objectName,
                loanApplicationId: this.recordId,
                applicantId: applicantId || undefined,
                verifiedStatusDocumentNames,
                verifiedStatusDocumentIds
            });
        };

        // Loan Application buckets (already filtered by selected filter in getter).
        (this.loanApplicationBucketedSections || []).forEach((section) => {
            (section.buckets || []).forEach((bucket) => {
                (bucket.fields || []).forEach((field) => {
                    addFieldUpdate(field, field.recordId || this.loanApplicationData?.recordId, field.objectName || this.loanApplicationData?.objectName || 'Application__c');
                });
            });
        });

        // Applicant and child tab buckets (already filtered in filteredApplicantsData).
        (this.filteredApplicantsData || []).forEach((group) => {
            (group.records || []).forEach((record) => {
                (record.fieldSectionTabs || []).forEach((fieldSection) => {
                    (fieldSection.buckets || []).forEach((bucket) => {
                        (bucket.fields || []).forEach((field) => {
                            addFieldUpdate(field, field.recordId || record.recordId, field.objectName || record.objectName);
                        });
                    });
                });

                (record.childTabs || []).forEach((childTab) => {
                    (childTab.records || []).forEach((childRecord) => {
                        (childRecord.buckets || []).forEach((bucket) => {
                            (bucket.fields || []).forEach((field) => {
                                addFieldUpdate(
                                    field,
                                    field.recordId || childRecord.recordId,
                                    field.objectName || childRecord.objectName,
                                    record.recordId
                                );
                            });
                        });
                        (childRecord.childTabs || []).forEach((nestedTab) => {
                            (nestedTab.records || []).forEach((nestedRecord) => {
                                (nestedRecord.buckets || []).forEach((nestedBucket) => {
                                    (nestedBucket.fields || []).forEach((field) => {
                                        addFieldUpdate(
                                            field,
                                            field.recordId || nestedRecord.recordId,
                                            field.objectName || nestedRecord.objectName,
                                            record.recordId
                                        );
                                    });
                                });
                            });
                        });
                    });
                });
            });
        });

        return updates;
    }

    async handleBulkCannotVerifyUpdate() {
        const confirmed = await LightningConfirm.open({
            message: 'No documents are attached to the fields, We will be marking it as Cannot Verify',
            variant: 'header',
            label: 'Confirm Update'
        });
        if (!confirmed) return;

        const updates = this.collectFieldsForCannotVerifyUpdate();
        if (!updates.length) {
            this.showToast('Info', 'No fields found to update.', 'info');
            return;
        }

        this.isLoading = true;
        try {
            await saveFieldVerification({
                verificationData: JSON.stringify(updates)
            });
            this.showToast('Success', `${updates.length} field(s) updated to Cannot Verify.`, 'success');
            this.changedStatusCount = 0;
            this.changedCommentsCount = 0;
            this.reverifiedFields.clear();
            await this.loadData();
            this.storeOriginalData();
            this.evaluateSendBackVisibility();
            this.triggerReactivity();
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message || 'Failed to update fields.', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // ============================================================================
    // DOCUMENT HANDLERS
    // ============================================================================
    
    /**
     * Capture image natural dimensions on load - enables proper zoom scroll area
     */
    handleDocumentImageLoad(event) {
        const img = event.target;
        if (!img || !img.naturalWidth || !img.naturalHeight) return;
        
        const fieldName = img.dataset?.field;
        const recordId = img.dataset?.record;
        if (!fieldName || !recordId) return;
        
        const field = this.findField(fieldName, recordId);
        if (!field) return;
        
        field.naturalWidth = img.naturalWidth;
        field.naturalHeight = img.naturalHeight;
        field.imageStyle = this.buildFieldImageStyle(field);
        this.updateFieldZoomWrapperStyle(field);
        this.triggerReactivity();
    }
    
    /**
     * Build image style - dimensions only; rotation and zoom are on the wrapper for reliable behavior
     */
    buildFieldImageStyle(field) {
        if (field.naturalWidth != null && field.naturalHeight != null) {
            return `width: ${field.naturalWidth}px; height: ${field.naturalHeight}px; max-width: none; display: block;`;
        }
        return 'display: block; max-width: 100%;';
    }
    
    /**
     * Update zoom wrapper - zoom + rotation applied here so both work at 100% and when zoomed
     * Rotation on wrapper avoids conflicts with image's object-fit; zoom enables proper scroll
     */
    updateFieldZoomWrapperStyle(field) {
        const zoom = (field.zoomLevel || 100) / 100;
        const rot = field.rotationAngle || 0;
        const baseStyle = `zoom: ${zoom}; transform: rotate(${rot}deg); transition: transform 0.3s; transform-origin: 50% 50%; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0;`;
        
        if (!field || field.naturalWidth == null || field.naturalHeight == null) {
            field.zoomWrapperStyle = baseStyle;
            return;
        }
        const rotNorm = Math.abs(rot % 360);
        const swap = rotNorm === 90 || rotNorm === 270;
        const w = swap ? Math.max(field.naturalWidth, field.naturalHeight) : field.naturalWidth;
        const h = swap ? Math.max(field.naturalWidth, field.naturalHeight) : field.naturalHeight;
        field.zoomWrapperStyle = `width: ${w}px; height: ${h}px; ${baseStyle}`;
    }
    
    handleNextDoc(event) {
        const fieldName = event.currentTarget.dataset.field;
        const recordId = event.currentTarget.dataset.record;
        this.updateDocumentIndex(fieldName, recordId, 1);
    }
    
    handlePrevDoc(event) {
        const fieldName = event.currentTarget.dataset.field;
        const recordId = event.currentTarget.dataset.record;
        this.updateDocumentIndex(fieldName, recordId, -1);
    }

    updateBucketDocumentIndex(bucketKey, direction) {
        const bucket = this.getBucketByKey(bucketKey);
        if (!bucket || !bucket.hasDocuments) return;
        const next = bucket.currentDocIndex + direction;
        if (next < 0 || next >= bucket.totalAttachments) return;
        const prevState = this.bucketUiState[bucketKey] || {};
        this.bucketUiState = {
            ...this.bucketUiState,
            [bucketKey]: {
                ...prevState,
                currentDocIndex: next,
                naturalWidth: null,
                naturalHeight: null
            }
        };
        // Rebuild applicant/child precomputed buckets with latest bucketUiState.
        this.updateFilteredApplicants();
    }

    handleBucketNextDoc(event) {
        const bucketKey = this.resolveBucketKeyFromEvent(event);
        if (!bucketKey) return;
        this.updateBucketDocumentIndex(bucketKey, 1);
    }

    handleBucketPrevDoc(event) {
        const bucketKey = this.resolveBucketKeyFromEvent(event);
        if (!bucketKey) return;
        this.updateBucketDocumentIndex(bucketKey, -1);
    }

    updateBucketView(bucketKey, updateFn) {
        const prevState = this.bucketUiState[bucketKey] || { currentDocIndex: 0, zoomLevel: 100, rotationAngle: 0 };
        this.bucketUiState = {
            ...this.bucketUiState,
            [bucketKey]: {
                ...prevState,
                ...updateFn(prevState)
            }
        };
        // Rebuild applicant/child precomputed buckets with latest bucketUiState.
        this.updateFilteredApplicants();
    }

    handleBucketDocumentImageLoad(event) {
        const img = event.target;
        if (!img || !img.naturalWidth || !img.naturalHeight) return;
        const bucketKey = img.dataset?.bucket;
        if (!bucketKey) return;
        this.updateBucketView(bucketKey, () => ({
            naturalWidth: img.naturalWidth,
            naturalHeight: img.naturalHeight
        }));
    }

    handleBucketDownload(event) {
        const bucketKey = this.resolveBucketKeyFromEvent(event);
        if (!bucketKey) return;
        const bucket = this.getBucketByKey(bucketKey);
        if (!bucket || !bucket.currentDoc) {
            this.showToast('Error', 'Document not found', 'error');
            return;
        }
        const doc = bucket.currentDoc;
        let downloadUrl;
        if (doc.contentVersionId) {
            downloadUrl = `/sfc/servlet.shepherd/version/download/${doc.contentVersionId}`;
        } else if (doc.contentDocumentId) {
            downloadUrl = `/sfc/servlet.shepherd/document/download/${doc.contentDocumentId}`;
        } else {
            this.showToast('Error', 'Download URL not available', 'error');
            return;
        }
        const fileName = doc.title || doc.fileName || `document_${bucket.subCategory || 'download'}.${doc.fileExtension || 'pdf'}`;
        const link = document.createElement('a');
        link.href = downloadUrl;
        link.download = fileName;
        link.target = '_blank';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
    
    updateDocumentIndex(fieldName, recordId, direction) {
        const field = this.findField(fieldName, recordId);
        if (!field || !field.documentAttachments) return;
        
        const newIndex = field.currentDocIndex + direction;
        if (newIndex >= 0 && newIndex < field.documentAttachments.length) {
            field.currentDocIndex = newIndex;
            field.currentDocIndexDisplay = newIndex + 1;
            field.currentDoc = field.documentAttachments[newIndex];
            field.disablePrevDoc = newIndex === 0;
            field.disableNextDoc = newIndex === field.documentAttachments.length - 1;
            // Reset natural dimensions - new image will set them on load
            field.naturalWidth = null;
            field.naturalHeight = null;
            this.updateFieldZoomWrapperStyle(field);
            
            // Trigger reactivity
            this.triggerReactivity();
        }
    }
    
    handleZoomIn(event) {
        event.stopPropagation();
        const bucketKey = this.resolveBucketKeyFromEvent(event);
        if (bucketKey) {
            this.updateBucketView(bucketKey, (state) => ({ zoomLevel: Math.min(200, (state.zoomLevel || 100) + 25) }));
            return;
        }
        const fieldName = event.currentTarget?.dataset?.field || event.target?.dataset?.field;
        const recordId = event.currentTarget?.dataset?.record || event.target?.dataset?.record;
        if (fieldName && recordId) {
        this.updateZoom(fieldName, recordId, 25);
        }
    }
    
    handleZoomOut(event) {
        event.stopPropagation();
        const bucketKey = this.resolveBucketKeyFromEvent(event);
        if (bucketKey) {
            this.updateBucketView(bucketKey, (state) => ({ zoomLevel: Math.max(25, (state.zoomLevel || 100) - 25) }));
            return;
        }
        const fieldName = event.currentTarget?.dataset?.field || event.target?.dataset?.field;
        const recordId = event.currentTarget?.dataset?.record || event.target?.dataset?.record;
        if (fieldName && recordId) {
        this.updateZoom(fieldName, recordId, -25);
        }
    }
    
    updateZoom(fieldName, recordId, delta) {
        const field = this.findField(fieldName, recordId);
        if (!field) {
            console.error('Field not found:', fieldName, recordId);
            return;
        }
        
        if (field.zoomLevel === undefined) {
            field.zoomLevel = 100;
        }
        
        field.zoomLevel = Math.max(25, Math.min(200, field.zoomLevel + delta));
        field.imageStyle = this.buildFieldImageStyle(field);
        this.updateFieldZoomWrapperStyle(field);
        this.triggerReactivity();
    }
    
    handleRotateLeft(event) {
        event.stopPropagation();
        const bucketKey = this.resolveBucketKeyFromEvent(event);
        if (bucketKey) {
            this.updateBucketView(bucketKey, (state) => ({ rotationAngle: ((state.rotationAngle || 0) - 90) % 360 }));
            return;
        }
        const fieldName = event.currentTarget?.dataset?.field || event.target?.dataset?.field;
        const recordId = event.currentTarget?.dataset?.record || event.target?.dataset?.record;
        if (fieldName && recordId) {
        this.updateRotation(fieldName, recordId, -90);
        }
    }
    
    handleRotateRight(event) {
        event.stopPropagation();
        const bucketKey = this.resolveBucketKeyFromEvent(event);
        if (bucketKey) {
            this.updateBucketView(bucketKey, (state) => ({ rotationAngle: ((state.rotationAngle || 0) + 90) % 360 }));
            return;
        }
        const fieldName = event.currentTarget?.dataset?.field || event.target?.dataset?.field;
        const recordId = event.currentTarget?.dataset?.record || event.target?.dataset?.record;
        if (fieldName && recordId) {
        this.updateRotation(fieldName, recordId, 90);
        }
    }
    
    updateRotation(fieldName, recordId, delta) {
        const field = this.findField(fieldName, recordId);
        if (!field) {
            console.error('Field not found:', fieldName, recordId);
            return;
        }
        
        if (field.rotationAngle === undefined) {
            field.rotationAngle = 0;
        }
        
        field.rotationAngle = (field.rotationAngle + delta) % 360;
        field.imageStyle = this.buildFieldImageStyle(field);
        this.updateFieldZoomWrapperStyle(field);
        this.triggerReactivity();
    }
    
    handleResetView(event) {
        event.stopPropagation();
        const bucketKey = this.resolveBucketKeyFromEvent(event);
        if (bucketKey) {
            this.updateBucketView(bucketKey, () => ({ zoomLevel: 100, rotationAngle: 0 }));
            return;
        }
        const fieldName = event.currentTarget?.dataset?.field || event.target?.dataset?.field;
        const recordId = event.currentTarget?.dataset?.record || event.target?.dataset?.record;
        if (fieldName && recordId) {
        const field = this.findField(fieldName, recordId);
            if (!field) {
                console.error('Field not found:', fieldName, recordId);
                return;
            }
        
        field.zoomLevel = 100;
        field.rotationAngle = 0;
        field.imageStyle = this.buildFieldImageStyle(field);
        this.updateFieldZoomWrapperStyle(field);
        this.triggerReactivity();
        }
    }
    
    handleDownload(event) {
        event.stopPropagation();
        const fieldName = event.currentTarget?.dataset?.field || event.target?.dataset?.field;
        const recordId = event.currentTarget?.dataset?.record || event.target?.dataset?.record;
        
        if (!fieldName || !recordId) {
            console.error('Missing fieldName or recordId for download');
            return;
        }
        
        const field = this.findField(fieldName, recordId);
        if (!field || !field.currentDoc) {
            console.error('Field or document not found:', fieldName, recordId);
            this.showToast('Error', 'Document not found', 'error');
            return;
        }
        
        const doc = field.currentDoc;
        let downloadUrl;
        
        // Construct download URL based on available IDs
        if (doc.contentVersionId) {
            // Use ContentVersion download URL
            downloadUrl = `/sfc/servlet.shepherd/version/download/${doc.contentVersionId}`;
        } else if (doc.contentDocumentId) {
            // Fallback to ContentDocument download URL
            downloadUrl = `/sfc/servlet.shepherd/document/download/${doc.contentDocumentId}`;
        } else {
            console.error('No contentVersionId or contentDocumentId found for download');
            this.showToast('Error', 'Download URL not available', 'error');
            return;
        }
        
        // Get file name from document title or use a default
        const fileName = doc.title || doc.fileName || `document_${field.fieldLabel || 'download'}.${doc.fileExtension || 'pdf'}`;
        
        // Create a temporary anchor element and trigger download
        const link = document.createElement('a');
        link.href = downloadUrl;
        link.download = fileName;
        link.target = '_blank';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        
    }
    
    findField(fieldName, recordId) {
        // Search in loan application FIRST - use this.loanApplicationData.fields (processed/updated data)
        if (this.loanApplicationData && this.loanApplicationData.recordId === recordId) {
            if (this.loanApplicationData.fields?.length > 0) {
                const field = this.loanApplicationData.fields.find(f => f && f.fieldName === fieldName);
                if (field) return field;
            }
            
            // Fallback: Search in raw verificationData
            const rawLoanAppData = this.verificationData?.find(v => v.objectLevel === 1 && v.recordId === recordId);
            if (rawLoanAppData?.fields) {
                const field = rawLoanAppData.fields.find(f => f && f.fieldName === fieldName);
                if (field) return field;
            }
        }
        
        // Search in UNFILTERED source data (this.applicants)
        if (this.applicants?.length > 0) {
        for (let objectGroup of this.applicants) {
                if (!objectGroup.records?.length) continue;
                
            for (let record of objectGroup.records) {
                if (record.recordId === recordId) {
                        if (record.fields?.length > 0) {
                            const field = record.fields.find(f => f && f.fieldName === fieldName);
                            if (field) return field;
                        }
                        
                        // Check verificationData (raw source)
                        const sourceRecord = this.verificationData?.find(v => 
                            v.objectLevel === 2 && v.recordId === recordId && v.objectName === record.objectName
                        );
                        if (sourceRecord?.fields) {
                            const field = sourceRecord.fields.find(f => f && f.fieldName === fieldName);
                            if (field) return field;
                        }
                    }
                    
                    // Search in child records (Level 3)
                    if (record.childRecords?.size > 0) {
                        for (let childList of record.childRecords.values()) {
                            if (!childList?.length) continue;
                            
                        for (let childRec of childList) {
                            if (childRec.recordId === recordId) {
                                    if (childRec.fields?.length > 0) {
                                        const field = childRec.fields.find(f => f && f.fieldName === fieldName);
                                        if (field) return field;
                                    }
                                    
                                    // Check verificationData for Level 3
                                    const sourceChildRecord = this.verificationData?.find(v => 
                                        v.objectLevel === 3 && v.recordId === recordId && v.objectName === childRec.objectName
                                    );
                                    if (sourceChildRecord?.fields) {
                                        const field = sourceChildRecord.fields.find(f => f && f.fieldName === fieldName);
                                        if (field) return field;
                                    }
                                }

                                if (childRec.childRecords?.size > 0) {
                                    for (let nestedList of childRec.childRecords.values()) {
                                        if (!nestedList?.length) continue;
                                        for (let nestedRec of nestedList) {
                                            if (nestedRec.recordId === recordId) {
                                                if (nestedRec.fields?.length > 0) {
                                                    const field = nestedRec.fields.find(f => f && f.fieldName === fieldName);
                                                    if (field) return field;
                                                }

                                                const sourceNestedRecord = this.verificationData?.find(v =>
                                                    v.objectLevel === 4 && v.recordId === recordId && v.objectName === nestedRec.objectName
                                                );
                                                if (sourceNestedRecord?.fields) {
                                                    const field = sourceNestedRecord.fields.find(f => f && f.fieldName === fieldName);
                                                    if (field) return field;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Fallback: Check filteredApplicantsData
        if (this.filteredApplicantsData?.length > 0) {
            for (let objectGroup of this.filteredApplicantsData) {
                if (!objectGroup.records?.length) continue;
                
                for (let record of objectGroup.records) {
                    if (record.recordId === recordId) {
                        if (record.fields?.length > 0) {
                            const field = record.fields.find(f => f && f.fieldName === fieldName);
                            if (field) return field;
                        }
                        
                        // Check fieldSectionTabs
                        if (record.fieldSectionTabs?.length > 0) {
                            for (let fieldSection of record.fieldSectionTabs) {
                                if (fieldSection.fields?.length > 0) {
                                    const field = fieldSection.fields.find(f => f && f.fieldName === fieldName);
                                    if (field) return field;
                                }
                            }
                        }
                    }

                    if (record.childTabs?.length > 0) {
                        for (let childTab of record.childTabs) {
                            for (let childRecord of (childTab.records || [])) {
                                if (childRecord.recordId === recordId && childRecord.fields?.length > 0) {
                                    const field = childRecord.fields.find(f => f && f.fieldName === fieldName);
                                    if (field) return field;
                                }

                                if (childRecord.childTabs?.length > 0) {
                                    for (let nestedTab of childRecord.childTabs) {
                                        for (let nestedRecord of (nestedTab.records || [])) {
                                            if (nestedRecord.recordId === recordId && nestedRecord.fields?.length > 0) {
                                                const field = nestedRecord.fields.find(f => f && f.fieldName === fieldName);
                                                if (field) return field;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        console.error('Field not found:', { fieldName, recordId });
        return null;
    }
    
    triggerReactivity() {
        // Force re-render by creating new object references
        if (this.loanApplicationData) {
            this.loanApplicationData = { 
                ...this.loanApplicationData,
                fields: this.loanApplicationData.fields ? [...this.loanApplicationData.fields] : []
            };
        }
        // Deep clone applicants array with nested Maps and arrays for proper reactivity
        // IMPORTANT: This preserves the updated structure while triggering reactivity
        this.applicants = this.applicants.map(objectGroup => ({
            ...objectGroup,
            records: objectGroup.records.map(record => ({
                ...record,
                // Recreate childRecords Map for reactivity (preserves updates)
                childRecords: record.childRecords ? new Map(record.childRecords) : new Map(),
                // Recreate childTabs array for reactivity (preserves updates)
                childTabs: record.childTabs ? record.childTabs.map(tab => ({
                    ...tab,
                    records: tab.records ? tab.records.map(rec => ({
                        ...rec,
                        fields: rec.fields ? [...rec.fields] : []
                    })) : []
                })) : [],
                // Recreate fields array for reactivity
                fields: record.fields ? [...record.fields] : []
            }))
        }));
        
        // Also update filteredApplicantsData to ensure UI reflects changes
        this.updateFilteredApplicants();
    }
    
    // ============================================================================
    // UTILITY
    // ============================================================================

    isValidPreviewHeight(heightValue) {
        return this.bucketHeightOptions.some((option) => option.value === heightValue);
    }

    loadPreviewHeightPreference() {
        try {
            const cachedHeight = window.localStorage.getItem(this.previewHeightStorageKey);
            if (this.isValidPreviewHeight(cachedHeight)) {
                this.selectedBucketHeight = cachedHeight;
                return;
            }
        } catch (e) {
            // Ignore storage access issues and use default.
        }
        this.selectedBucketHeight = '600';
    }

    savePreviewHeightPreference(heightValue) {
        try {
            window.localStorage.setItem(this.previewHeightStorageKey, heightValue);
        } catch (e) {
            // Ignore storage access issues silently.
        }
    }
    
    /**
     * Check if a field has been reverified
     */
    isFieldReverified(fieldVerificationId) {
        return fieldVerificationId && this.reverifiedFields.has(fieldVerificationId);
    }
    
    /**
     * Handle Reverify button click
     * Adds field to reverified list for saving later
     */
    handleReverify(event) {
        const fieldVerificationId = event.currentTarget.dataset.fieldVerificationId;
        const fieldName = event.currentTarget.dataset.fieldName;
        const recordId = event.currentTarget.dataset.recordId;
        const currentValue = event.currentTarget.dataset.currentValue || '';
        
        if (!fieldVerificationId) {
            return;
        }
        
        // Get the field to access current values
        const fieldObj = this.findField(fieldName, recordId);
        
        // Toggle reverified state
        if (this.reverifiedFields.has(fieldVerificationId)) {
            // Already reverified, remove it
            this.reverifiedFields.delete(fieldVerificationId);
            this.updateFieldProperty(fieldName, recordId, 'needsReverify', false);
            this.updateFieldProperty(fieldName, recordId, 'reverifyLabel', 'Re-Verify');
            this.updateFieldProperty(fieldName, recordId, 'reverifyVariant', 'neutral');
            
            // Restore original verified value from originalVerifiedValue property
            if (fieldObj && fieldObj.originalVerifiedValue !== null && fieldObj.originalVerifiedValue !== undefined) {
                this.updateFieldProperty(fieldName, recordId, 'fieldValueFromVerifiedFields', fieldObj.originalVerifiedValue);
            }
            if (fieldObj && fieldObj.originalVerifiedDocumentIds !== null && fieldObj.originalVerifiedDocumentIds !== undefined) {
                this.updateFieldProperty(fieldName, recordId, 'verifiedStatusDocumentIds', fieldObj.originalVerifiedDocumentIds);
            }
            if (fieldObj && fieldObj.originalVerifiedDocumentNames !== null && fieldObj.originalVerifiedDocumentNames !== undefined) {
                this.updateFieldProperty(fieldName, recordId, 'verifiedStatusDocumentNames', fieldObj.originalVerifiedDocumentNames);
            }
            this.changedStatusCount = Math.max(0, this.changedStatusCount - 1);
        } else {
            // Add to reverified fields set
            // First, store the current verified value as original if not already stored
            if (fieldObj) {
                const currentVerifiedValue = fieldObj.fieldValueFromVerifiedFields;
                // Only store if originalVerifiedValue is not already set (preserve it across multiple clicks)
                if (fieldObj.originalVerifiedValue === null || fieldObj.originalVerifiedValue === undefined || fieldObj.originalVerifiedValue === '') {
                    // Store the current verified value before changing it
                    this.updateFieldProperty(fieldName, recordId, 'originalVerifiedValue', currentVerifiedValue);
                }
                if (fieldObj.originalVerifiedDocumentIds === null || fieldObj.originalVerifiedDocumentIds === undefined) {
                    this.updateFieldProperty(fieldName, recordId, 'originalVerifiedDocumentIds', fieldObj.verifiedStatusDocumentIds || null);
                }
                if (fieldObj.originalVerifiedDocumentNames === null || fieldObj.originalVerifiedDocumentNames === undefined) {
                    this.updateFieldProperty(fieldName, recordId, 'originalVerifiedDocumentNames', fieldObj.verifiedStatusDocumentNames || null);
                }
            }
            
            this.reverifiedFields.add(fieldVerificationId);
            this.updateFieldProperty(fieldName, recordId, 'needsReverify', true);
            this.updateFieldProperty(fieldName, recordId, 'reverifyLabel', 'Verified');
            this.updateFieldProperty(fieldName, recordId, 'reverifyVariant', 'brand');
            // Update fieldValueFromVerifiedFields for saving (but don't hide the verified value section)
            this.updateFieldProperty(fieldName, recordId, 'fieldValueFromVerifiedFields', currentValue);
            if (fieldObj) {
                this.updateFieldProperty(fieldName, recordId, 'verifiedStatusDocumentIds', this.getCurrentDocumentIdsFromField(fieldObj));
                this.updateFieldProperty(fieldName, recordId, 'verifiedStatusDocumentNames', this.getCurrentDocumentNamesFromField(fieldObj));
            }
            this.changedStatusCount++;
        }

        // Refresh mismatch flags immediately after reverify toggle so UI and submit logic stay in sync.
        const updatedField = this.findField(fieldName, recordId);
        if (updatedField) {
            const verifiedValue = updatedField.fieldValueFromVerifiedFields != null ? String(updatedField.fieldValueFromVerifiedFields).trim() : '';
            const currentValueTrimmed = updatedField.currentValueInDB != null ? String(updatedField.currentValueInDB).trim() : '';
            const updatedHasValueMismatch = updatedField.verificationStatus === 'Manually Verified' && verifiedValue !== currentValueTrimmed;
            const updatedHasDocumentMismatch = this.hasDocumentMismatch(updatedField);
            this.updateFieldProperty(fieldName, recordId, 'hasValueMismatch', updatedHasValueMismatch);
            this.updateFieldProperty(fieldName, recordId, 'hasDocumentMismatch', updatedHasDocumentMismatch);
            this.updateFieldProperty(fieldName, recordId, 'hasMismatch', updatedHasValueMismatch || updatedHasDocumentMismatch);
        }
        
        // Force deep reactivity to ensure UI updates for nested child records
        this.triggerReactivity();
        
        // Re-evaluate mismatches to update hasMismatches flag
        this.evaluateSendBackVisibility();
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}