({
    /* ============================================================
     * CONSTANTS — kept static (per project rule Q4 = Static like IBL_SIT)
     * ============================================================ */
    DEFAULT_NUMBER_OF_VEHICLES: [
        { label: 'Single Vehicle',    value: 'Single'   },
        { label: 'Multiple Vehicles', value: 'Multiple' }
    ],

    /** Returns an emoji icon based on the Product code (PL, 2W, 4W, CV). */
    iconFor: function(value, label) {
        switch ((value || '').toUpperCase()) {
            case '2W': return '🏍️';
            case '4W': return '🚗';
            case 'CV': return '🚚';
            case 'PL': return '💰';
            default:
                // Fallback by label fragments (for forward-compat with future products)
                var l = (label || '').toLowerCase();
                if (l.indexOf('two') >= 0 || l.indexOf('bike') >= 0)       return '🏍️';
                if (l.indexOf('four') >= 0 || l.indexOf('car') >= 0)       return '🚗';
                if (l.indexOf('commercial') >= 0 || l.indexOf('truck') >= 0) return '🚚';
                if (l.indexOf('personal') >= 0)                             return '👤';
                return '💰';
        }
    },

    /** Returns the long, human-friendly product name for the tile UI.
     *  The org picklist (PL/2W/4W/CV) has label == value, so we synthesize the
     *  long names here without changing org metadata. */
    friendlyNameFor: function(value, label) {
        switch ((value || '').toUpperCase()) {
            case 'PL': return 'Personal Loan';
            case '2W': return 'Two Wheeler';
            case '4W': return 'Four Wheeler';
            case 'CV': return 'Commercial Vehicles';
            default:   return label || value;
        }
    },

    /** Loads Product options from Apex (single dynamic dropdown source);
     *  cascading options stay static as per project rule. */
    loadFormOptions: function(component) {
        component.set('v.isLoadingOptions', true);
        component.set('v.errorMessage', '');

        var self   = this;
        var action = component.get('c.getFormOptions');

        action.setCallback(this, function(response) {
            component.set('v.isLoadingOptions', false);

            if (response.getState() === 'SUCCESS') {
                var data = response.getReturnValue();

                var productOptions = (data.productOptions || []).map(function(opt) {
                    return {
                        value:       opt.value,
                        label:       self.friendlyNameFor(opt.value, opt.label),
                        code:        opt.value,
                        icon:        self.iconFor(opt.value, opt.label)
                    };
                });

                component.set('v.productOptions', productOptions);

                // Driven by the standard field dependency on
                // Application_Line_Item__c (Product__c → Sub_Product__c).
                component.set('v.subProductDependencyMap', data.subProductDependencyMap || {});

            } else {
                var errors  = response.getError();
                var message = (errors && errors[0] && errors[0].message)
                    ? errors[0].message
                    : 'Failed to load form options. Please refresh and try again.';
                component.set('v.errorMessage', message);
                console.error('[commonApplicationCreationAura] loadFormOptions error:', errors);
            }
        });

        $A.enqueueAction(action);
    },

    /* ============================================================
     * Product-specific cascading rules
     * (Replicated from IBL_SIT p4p3IntermediatePage handleProductTypeChange,
     *  with hardcoded "Two Wheeler" string remapped to MOGA DEV's "2W" code.
     *  Customer Type was removed from this screen — it is captured on the
     *  Basic Details screen instead, so no customer-type locking is applied.) */
    applyProductRules: function(component, productValue) {
        if (productValue === '2W') {
            // 2W locks: single vehicle only, auto-default Vehicle Type to New
            component.set('v.numberOfVehiclesOptions', [
                { label: 'Single Vehicle', value: 'Single' }
            ]);
            //component.set('v.selectedNumberOfVehicles', 'Single');
            component.set('v.selectedVehicleType',      'New');
        } else if (productValue === 'PL') {
            // Personal Loan has no vehicle context — clear NoV state so it does
            // not leak from a previous selection, and the UI hides the step.
            this.restoreDefaultOptionLists(component);
            //component.set('v.selectedNumberOfVehicles', '');
            component.set('v.selectedVehicleType',      '');
        } else {
            this.restoreDefaultOptionLists(component);
            // component.set('v.selectedNumberOfVehicles', '');
            component.set('v.selectedVehicleType',      '');
        }
    },

    restoreDefaultOptionLists: function(component) {
        component.set('v.numberOfVehiclesOptions', this.DEFAULT_NUMBER_OF_VEHICLES.slice());
    },

    /** Looks up sub-product options for a given Product.
     *  Reads from v.subProductDependencyMap, which is populated at init time
     *  from the standard field dependency declared on
     *  Application_Line_Item__c.Sub_Product__c (controlled by Product__c). */
    resolveSubProduct: function(component, productValue) {
        var map  = component.get('v.subProductDependencyMap') || {};
        var opts = map[productValue] || [];
        component.set('v.subProductOptions', opts);
        component.set('v.showSubProduct',    opts.length > 0);
    },

    /* ============================================================
     * Validation
     * ============================================================ */
    validateForm: function(component) {
        var product       = component.get('v.selectedProduct');
        var vehicleType   = component.get('v.selectedVehicleType');
        var segment       = component.get('v.selectedSegment');
        var subProduct    = component.get('v.selectedSubProduct');
        var showSubProd   = component.get('v.showSubProduct');
        
        var isValid = false;

        if (!product) {
            isValid = false;
        }
        else if (product === 'PL') {
            isValid = true;
        }
        else if (product === '2W') {
            if (!vehicleType) {
                isValid = false;
            } else if (vehicleType === 'New') {
                isValid = !!segment;
            } else if (vehicleType === 'Refinance') {
                isValid = true;
            } else {
                isValid = false;
            }
        } else {
            isValid = true;
        }

        // If this Product requires a Sub-Product (CV / PL), enforce it.
        if (isValid && showSubProd && !subProduct) {
            isValid = false;
        }

        component.set('v.isFormValid', isValid);
        return isValid;
    },

    /* ============================================================
     * Submit
     * ============================================================ */
    createApplication: function(component) {
        component.set('v.isSubmitting', true);
        component.set('v.errorMessage', '');

        var action = component.get('c.createDirectLoanApplication');
        action.setParams({
            product:           component.get('v.selectedProduct'),
            subProduct:        component.get('v.selectedSubProduct') || '',
            numberOfVehicles:  '', // component.get('v.selectedNumberOfVehicles') || '',
            vehicleType:       component.get('v.selectedVehicleType')      || '',
            segment:           component.get('v.selectedSegment')          || ''
        });

        action.setCallback(this, function(response) {
            if (response.getState() === 'SUCCESS') {
                var result = response.getReturnValue();
                component.set('v.newRecordId',  result.recordId);
                // Skip the configuration-summary panel and route directly to the
                // Application record page. Stage__c='QDE' + Sub_Stage__c='Basic Details'
                // isSubmitting stays true so the "Creating…" spinner keeps showing
                // until the page transition completes.
                var navEvent = $A.get('e.force:navigateToSObject');
                if (navEvent) {
                    navEvent.setParams({ recordId: result.recordId, isredirect: true });
                    navEvent.fire();
                    return;
                }
                var urlEvent = $A.get('e.force:navigateToURL');
                if (urlEvent) {
                    urlEvent.setParams({ url: '/' + result.recordId });
                    urlEvent.fire();
                    return;
                }
                // No navigation primitives available — surface the success panel as a fallback.
                component.set('v.isSubmitting', false);
                component.set('v.isSuccess',    true);
            } else {
                component.set('v.isSubmitting', false);
                var errors  = response.getError();
                var message = (errors && errors[0] && errors[0].message)
                    ? errors[0].message
                    : 'An unexpected error occurred. Please try again.';
                component.set('v.errorMessage', message);
                console.error('[commonApplicationCreationAura] createApplication error:', errors);
            }
        });

        $A.enqueueAction(action);
    },

    /** Navigates to the Application__c list view (recently viewed). */
    navigateToApplicationList: function() {
        var navEvent = $A.get('e.force:navigateToObjectHome');
        if (navEvent) {
            navEvent.setParams({ scope: 'Application__c' });
            navEvent.fire();
            return;
        }
        var urlEvent = $A.get('e.force:navigateToURL');
        if (urlEvent) {
            urlEvent.setParams({ url: '/lightning/o/Application__c/list' });
            urlEvent.fire();
        }
    }
})