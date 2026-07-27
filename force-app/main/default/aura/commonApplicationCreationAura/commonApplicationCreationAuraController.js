({
    doInit: function(component, event, helper) {
        helper.loadFormOptions(component);
    },

    /** Click on a product tile */
    handleProductSelect: function(component, event, helper) {
        var target = event.currentTarget;
        var value  = target.dataset.value;
        var label  = target.dataset.label;
        var icon   = target.dataset.icon;

        component.set('v.selectedProduct',      value);
        component.set('v.selectedProductLabel', label);
        component.set('v.selectedProductIcon',  icon);

        // Reset all downstream selections whenever Product changes
        component.set('v.selectedSubProduct',      '');
        component.set('v.selectedSubProductLabel', '');
        component.set('v.selectedVehicleType',     '');
        component.set('v.selectedSegment',         '');
        component.set('v.errorMessage',            '');

        // Apply Product-specific rules (replicated from IBL_SIT p4p3IntermediatePage)
        helper.applyProductRules(component, value);

        // Resolve Sub-Product visibility + options for this Product
        helper.resolveSubProduct(component, value);

        helper.validateForm(component);
    },

    handleVehicleTypeChange: function(component, event, helper) {
        component.set('v.selectedVehicleType', event.currentTarget.dataset.value);
        // If switching away from "New", clear Segment selection
        if (event.currentTarget.dataset.value !== 'New') {
            component.set('v.selectedSegment', '');
        }
        helper.validateForm(component);
    },

    handleSegmentChange: function(component, event, helper) {
        component.set('v.selectedSegment', event.currentTarget.dataset.value);
        helper.validateForm(component);
    },

    handleSubProductSelect: function(component, event, helper) {
        var target = event.currentTarget;
        component.set('v.selectedSubProduct',      target.dataset.value);
        component.set('v.selectedSubProductLabel', target.dataset.label);
        component.set('v.errorMessage',            '');
        helper.validateForm(component);
    },

    /** Validate and submit */
    handleSubmit: function(component, event, helper) {
        if (!helper.validateForm(component)) {
            component.set('v.errorMessage', 'Please complete all required selections to continue.');
            return;
        }
        helper.createApplication(component);
    },

    /** Navigate to the newly created record */
    handleProceed: function(component, event, helper) {
        var recordId = component.get('v.newRecordId');
        if (!recordId) return;
        var navEvent = $A.get('e.force:navigateToSObject');
        if (navEvent) {
            navEvent.setParams({ recordId: recordId, isredirect: true });
            navEvent.fire();
        } else {
            var urlEvent = $A.get('e.force:navigateToURL');
            if (urlEvent) {
                urlEvent.setParams({ url: '/' + recordId });
                urlEvent.fire();
            }
        }
    },

    /** Reset the form back to initial state */
    handleReset: function(component, event, helper) {
        component.set('v.selectedProduct',          '');
        component.set('v.selectedProductLabel',     '');
        component.set('v.selectedProductIcon',      '');
        component.set('v.selectedVehicleType',      '');
        component.set('v.selectedSegment',          '');
        component.set('v.selectedSubProduct',       '');
        component.set('v.selectedSubProductLabel',  '');
        component.set('v.showSubProduct',           false);
        component.set('v.subProductOptions',        []);
        component.set('v.isSuccess',                false);
        component.set('v.newRecordId',              '');
        component.set('v.errorMessage',             '');
        component.set('v.isFormValid',              false);

        // Restore full option lists in case 2W had locked them
        helper.restoreDefaultOptionLists(component);
    },

    /** Navigate to the Application list view (recently viewed) */
    handleCancel: function(component, event, helper) {
        helper.navigateToApplicationList();
    }
})