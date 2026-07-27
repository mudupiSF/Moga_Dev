import { LightningElement, api } from 'lwc';
import getReportingUserIds from '@salesforce/apex/ApplicationAgingReportsController.getReportingUserIds';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ApplicationAgingReportsContainer extends LightningElement {

    isAdmin = false;
    isManager = false;
    showInvestigations = false;
    isLoaded = false;
    userIdsLoaded = false;
    defaultTab = 'employeeQuery';
    hasDefaultTabRendered = false;
    selectedTab = '';

    get activeTab() {
        if(this.selectedTab) {
            return this.selectedTab;
        }
        return this.defaultTab;
    }

    set activeTab(value) {
        this.selectedTab = value;
    }
    // My Loans tab visibility
    get showMyLoansTab() {
        // Admin sees everything, OR non-FCU users
        return this.isAdmin || !this.showInvestigations;
    }
    
    get showMyTeamTab() {
        // Show "My Team" tab if:
        // 1. User is Manager (or Admin), AND
        // 2. User is NOT an FCU user (or is Admin)
        return (this.isAdmin || this.isManager) && 
               (this.isAdmin || !this.showInvestigations);
    }

    // Getters for button visibility
    get showApplicationColumnsButton() {
        return this.activeTab === 'employee' || this.activeTab === 'manager';
    }
    
    get showInvestigationColumnsButton() {
        return this.activeTab === 'employeeInvestigation' || this.activeTab === 'managerInvestigation';
    }

    connectedCallback() {
        // First, get reporting user IDs (shows progress to user)
        this.loadUserReportingIds();
    }

    // STEP 1: Get user IDs first (lightweight query)
    loadUserReportingIds() {
        this.isLoaded = false;
        
        getReportingUserIds()
        .then(data => {
            this.isManager = data.isManager;
            this.showInvestigations = data.showInvestigations || false;
            this.isAdmin = data.isAdmin || false;
            this.employeeUserIds = data.employeeUserIds;
            this.managerUserIds = data.managerUserIds;
            this.defaultProduct = data.defaultProduct || ''; // Get default product from user
            this.userIdsLoaded = true;
            
            /*// Set default product filter if available
            if (this.defaultProduct) {
                this.employeeSelectedProduct = this.defaultProduct;
                this.managerSelectedProduct = this.defaultProduct;
            }
            
            // Load product options first (before loan data) so dropdown shows default value immediately
            this.loadProductOptions();
            
            // Now load loan data with these user IDs and default product filter
            this.loadLoanData();
            
            // ALSO load investigation data upfront if user can see investigations
            if (this.showInvestigations) {
                this.loadInvestigationData();
            }*/
            this.isLoaded = true;
        })
        .catch(error => {
            this.showToast('Error', error.body?.message || error.message, 'error');
            this.isLoaded = true;
        });
    }

    handleActive(event) {
        const newTabValue = event.target.value;
        const myQueriesAgingReport = this.template.querySelector('c-my-queries-aging-report');
        // Load data based on active tab (lazy loading + caching)
        if (newTabValue === 'employeeInvestigation' || newTabValue === 'managerInvestigation') {
            this.loadInvestigationData();
        }
        else if (newTabValue === 'employeeQuery' || newTabValue === 'managerQuery') {
            if(myQueriesAgingReport) {
                myQueriesAgingReport.showData();
            }
        }
        else {
            if(myQueriesAgingReport) {
                myQueriesAgingReport.hideData();
            }
            /*if (newTabValue === 'employee' || newTabValue === 'manager') {
                this.loadLoanDataForTab();
            }
            else {
                this.loadLoanData();
            }*/
        }
        /*// Only apply filters if data is already loaded (for cached data)
        if ((newTabValue === 'employeeInvestigation' || newTabValue === 'managerInvestigation') && this.investigationDataLoaded) {
            this.applyFilters();
        }
        else if ((newTabValue === 'employeeQuery' || newTabValue === 'managerQuery') && this.queryDataLoaded) {
            this.applyFilters();
        }
        else if ((newTabValue === 'employee' || newTabValue === 'manager') && this.loanDataLoaded) {
            this.applyFilters();
        }*/
    }

    renderedCallback() {
        if(!this.hasDefaultTabRendered) {
            this.selectedTab = this.defaultTab;
            const queryCmp = this.template.querySelector('c-my-queries-aging-report');
            if(queryCmp) {
                queryCmp.showData();
                this.hasDefaultTabRendered = true;
            }
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}