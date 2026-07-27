import { LightningElement, api, track, wire } from 'lwc';
import getReportingUserIds from '@salesforce/apex/AdvancedAgingReportsController.getReportingUserIds';
//import getAllProducts from '@salesforce/apex/AdvancedAgingReportsController.getAllProducts';
import getApplicationAgingChunk from '@salesforce/apex/AdvancedAgingReportsController.getApplicationAgingChunk';
import getInvestigationAgingChunk from '@salesforce/apex/AdvancedAgingReportsController.getInvestigationAgingChunk';
import getQueryAgingChunk from '@salesforce/apex/AdvancedAgingReportsController.getQueryAgingChunk';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import APPLICATION_OBJECT from '@salesforce/schema/Application__c';
import PRODUCT_FIELD from '@salesforce/schema/Application__c.Product__c';

export default class AdvancedAgingReports extends LightningElement {
    @api managerMode = false; // Deprecated - kept for backwards compatibility
    @api pageSize = 50; // Default page size

    @wire(getObjectInfo, { objectApiName: APPLICATION_OBJECT })
    applicationObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$applicationObjectInfo.data.defaultRecordTypeId',
        fieldApiName: PRODUCT_FIELD
    })
    wiredProductValues({ data, error }) {
        if (data) {
            this.productOptions = data.values.map((option) => ({
                label: option.label,
                value: option.value
            }));
        }
    }
    
    // Response data
    isManager = false;
    showInvestigations = false;
    _activeTab = 'employee'; // Default to employee view
    
    // Getter and setter for activeTab to detect changes
    get activeTab() {
        return this._activeTab;
    }
    
    set activeTab(value) {
        const oldValue = this._activeTab;
        this._activeTab = value;
        
        // Only trigger load if value actually changed
        if (oldValue !== value) {
            this.handleTabChangeInternal(value);
        }
    }
    
    // Employee view data (Applications)
    employeeRecords = [];
    employeeFilteredRecords = [];
    employeeDisplayedRecords = [];
    employeeCurrentPage = 1;
    employeeTotalPages = 0;
    employeeTotalRecords = 0;
    employeeCountExceedsThreshold = false;
    employeeSelectedStage = '';
    employeeSelectedProduct = '';
    employeeSelectedRegion = '';
    employeeSelectedApplicationAge = '';
    employeeSelectedLastStatusAge = '';
    employeeSelectedHasOpenQueries = '';
    employeeSelectedCreatedDate = '<30'; // Default to '< 30 Days'
    employeeApplicationSortedBy = '';
    employeeApplicationSortDirection = 'asc';
    
    // Manager view data (Applications)
    managerRecords = [];
    managerFilteredRecords = [];
    managerDisplayedRecords = [];
    managerCurrentPage = 1;
    managerTotalPages = 0;
    managerTotalRecords = 0;
    managerCountExceedsThreshold = false;
    managerSelectedStage = '';
    managerSelectedManager = '';
    managerSelectedOwner = '';
    managerSelectedProduct = '';
    managerSelectedRegion = '';
    managerSelectedApplicationAge = '';
    managerSelectedLastStatusAge = '';
    managerSelectedHasOpenQueries = '';
    managerSelectedCreatedDate = '<30'; // Default to '< 30 Days'
    managerApplicationSortedBy = '';
    managerApplicationSortDirection = 'asc';
    
    // Employee Investigation data
    employeeInvestigationRecords = [];
    @track employeeInvestigationFilteredRecords = [];
    @track employeeInvestigationDisplayedRecords = [];
    employeeInvestigationCurrentPage = 1;
    employeeInvestigationTotalPages = 0;
    employeeInvestigationTotalRecords = 0;
    employeeInvestigationCountExceedsThreshold = false;
    employeeInvestigationSelectedStatus = '';
    employeeInvestigationSelectedProduct = '';
    employeeInvestigationSelectedRegion = '';
    employeeInvestigationSelectedInvestigationAge = '';
    employeeInvestigationSelectedLastStatusAge = '';
    employeeInvestigationSortedBy = '';
    employeeInvestigationSortDirection = 'asc';
    
    // Manager Investigation data
    managerInvestigationRecords = [];
    managerInvestigationFilteredRecords = [];
    managerInvestigationDisplayedRecords = [];
    managerInvestigationCurrentPage = 1;
    managerInvestigationTotalPages = 0;
    managerInvestigationTotalRecords = 0;
    managerInvestigationCountExceedsThreshold = false;
    managerInvestigationSelectedStatus = '';
    managerInvestigationSelectedManager = '';
    managerInvestigationSelectedOwner = '';
    managerInvestigationSelectedProduct = '';
    managerInvestigationSelectedRegion = '';
    managerInvestigationSelectedInvestigationAge = '';
    managerInvestigationSelectedLastStatusAge = '';
    managerInvestigationSortedBy = '';
    managerInvestigationSortDirection = 'asc';
    
    // Employee Query data
    employeeQueryRecords = [];
    employeeQueryFilteredRecords = [];
    employeeQueryDisplayedRecords = [];
    employeeQueryCurrentPage = 1;
    employeeQueryTotalPages = 0;
    employeeQueryTotalRecords = 0;
    employeeQueryCountExceedsThreshold = false;
    employeeQuerySelectedStatus = '';
    employeeQuerySelectedPriority = '';
    employeeQuerySelectedType = '';
    employeeQuerySelectedAge = '';
    employeeQuerySortedBy = '';
    employeeQuerySortDirection = 'asc';
    
    // Manager Query data
    managerQueryRecords = [];
    managerQueryFilteredRecords = [];
    managerQueryDisplayedRecords = [];
    managerQueryCurrentPage = 1;
    managerQueryTotalPages = 0;
    managerQueryTotalRecords = 0;
    managerQueryCountExceedsThreshold = false;
    managerQuerySelectedStatus = '';
    managerQuerySelectedManager = '';
    managerQuerySelectedOwner = '';
    managerQuerySelectedPriority = '';
    managerQuerySelectedType = '';
    managerQuerySelectedAge = '';
    managerQuerySortedBy = '';
    managerQuerySortDirection = 'asc';
    
    // Column visibility for Applications
    showApplicationColumnModal = false;
    availableColumns = [];
    selectedColumns = [];
    
    // Column visibility for Investigations
    showInvestigationColumnModal = false;
    availableInvestigationColumns = [];
    selectedInvestigationColumns = [];
    
    columns = [];
    investigationColumns = []; // Separate columns for investigations
    queryColumns = []; // Separate columns for queries
    error;
    isLoading = true;
    
    // Page size options
    pageSizeOptions = [
        { label: '5', value: '5' },
        { label: '10', value: '10' },
        { label: '50', value: '50' },
        { label: '100', value: '100' },
        { label: '200', value: '200' }
    ];
    
    // Age filter options
    ageFilterOptions = [
        { label: '-- All --', value: '' },
        { label: '< 1 Day', value: '<1' },
        { label: '1-2 Days', value: '1-2' },
        { label: '2-3 Days', value: '2-3' },
        { label: '3-5 Days', value: '3-5' },
        { label: '5-10 Days', value: '5-10' },
        { label: '10-20 Days', value: '10-20' },
        { label: '20-30 Days', value: '20-30' },
        { label: '> 30 Days', value: '>30' }
    ];
    
    // Has Open Queries filter options
    hasOpenQueriesOptions = [
        { label: '-- All --', value: '' },
        { label: 'Yes', value: 'true' },
        { label: 'No', value: 'false' }
    ];
    
    // Filter options
    stageOptions = [];
    statusOptions = [];  // For investigations
    queryStatusOptions = [];
    queryPriorityOptions = [];
    queryTypeOptions = [];
    managerOptions = [];
    ownerOptions = [];
    @track productOptions = [];
    
    // Created Date filter options
    createdDateFilterOptions = [
        { label: '< 30 Days', value: '<30' },
        { label: '30 - 60 Days', value: '30-60' },
        { label: '60 - 90 Days', value: '60-90' },
        { label: '> 90 Days', value: '>90' }
    ];
    
    // Cache flags to prevent re-querying
    applicationDataLoaded = false;
    investigationDataLoaded = false;
    queryDataLoaded = false;
    
    // User IDs for queries
    employeeUserIds = [];
    managerUserIds = [];
    userIdsLoaded = false;
    isAdmin = false;
    defaultProduct = ''; // Default product from user's Product__c field
    
    // Toggle for "Show applications I own" on My Applications tab - defaulted to true
    employeeShowApplicationsIOwn = true;
    
    // Toggle for "My Team Owns" on My Team tab - defaulted to true
    managerShowApplicationsIOwn = true;
    
    // Loading message
    loadingMessage = 'Loading...';

    // Tab-specific loading states (so tabs remain visible during loading)
    isLoadingApplicationData = false;
    isLoadingInvestigationData = false;
    isLoadingQueryData = false;
    // Applications / Investigations / Queries server-page cursor state.
    // Pagination is "stateless" between pages: Previous derives its cursor from the
    // newest record currently displayed, Next from the oldest one. We therefore only
    // need the boundary advertised by the server (nextCursor*) and the hasMore flag
    // for the forward direction. No history stack is required.
    employeeApplicationNextCursorCreatedDate = null;
    employeeApplicationNextCursorId = null;
    employeeApplicationHasMore = false;
    managerApplicationNextCursorCreatedDate = null;
    managerApplicationNextCursorId = null;
    managerApplicationHasMore = false;
    employeeInvestigationNextCursorCreatedDate = null;
    employeeInvestigationNextCursorId = null;
    employeeInvestigationHasMore = false;
    managerInvestigationNextCursorCreatedDate = null;
    managerInvestigationNextCursorId = null;
    managerInvestigationHasMore = false;
    employeeQueryNextCursorCreatedDate = null;
    employeeQueryNextCursorId = null;
    employeeQueryHasMore = false;
    managerQueryNextCursorCreatedDate = null;
    managerQueryNextCursorId = null;
    managerQueryHasMore = false;
    
    connectedCallback() {
        // Initialize column definitions (applications, investigations, queries) synchronously
        // so column selector modals and datatable columns work before any data loads.
        this.buildColumns();

        // First, get reporting user IDs (shows progress to user)
        this.loadUserIds();
        
        // Poll to detect activeTab changes (workaround for lightning-tabset not firing events)
        setInterval(() => {
            // Get the actual selected tab from the DOM
            const tabset = this.template.querySelector('lightning-tabset');
            if (tabset && tabset.activeTabValue) {
                const domActiveTab = tabset.activeTabValue;
                if (domActiveTab !== this._activeTab) {
                    this.activeTab = domActiveTab; // This will trigger the setter
                }
            }
        }, 500); // Check every 500ms
    }
    
    // STEP 1: Get user IDs first (lightweight query)
    loadUserIds() {
        this.isLoading = true;
        this.loadingMessage = 'Getting direct reports...';
        
        getReportingUserIds()
            .then(data => {
                this.isManager = data.isManager;
                this.showInvestigations = data.showInvestigations || false;
                this.isAdmin = data.isAdmin || false;
                this.employeeUserIds = data.employeeUserIds;
                this.managerUserIds = data.managerUserIds;
                this.defaultProduct = data.defaultProduct || ''; // Get default product from user
                this.userIdsLoaded = true;
                
                // Set default product filter if available
                if (this.defaultProduct) {
                    this.employeeSelectedProduct = this.defaultProduct;
                    this.managerSelectedProduct = this.defaultProduct;
                }
                
                // Load product options first (before application data) so dropdown shows default value immediately
                this.loadProductOptions();
                
                // Now load application data with these user IDs and default product filter
                this.loadApplicationData();
                
                // ALSO load investigation data upfront if user can see investigations
                if (this.showInvestigations) {
                    this.loadInvestigationData();
                }
            })
            .catch(error => {
                this.error = error;
                this.loadingMessage = 'Error loading user information';
                console.error('ApplicationAgingLWC: Error loading user IDs:', error);
                this.isLoading = false;
            });
    }

    // cursorDirection: 'forward' walks toward older records (Next / fresh load),
    //                  'backward' walks toward newer records (Previous) or fetches
    //                  the oldest page when no cursor is given (Last button).
    async fetchAllApplicationPages(tabValue, productFilter, createdDateFilter, cursorCreatedDate = null, cursorId = null, cursorDirection = 'forward') {
        const isEmployeeTab = tabValue === 'employee';
        const userIds = isEmployeeTab ? this.employeeUserIds : this.managerUserIds;
        const showApplicationsIOwn = isEmployeeTab ? this.employeeShowApplicationsIOwn : this.managerShowApplicationsIOwn;
        const stageFilter = isEmployeeTab ? this.employeeSelectedStage : this.managerSelectedStage;
        const regionFilter = isEmployeeTab ? this.employeeSelectedRegion : this.managerSelectedRegion;
        const applicationAgeFilter = isEmployeeTab ? this.employeeSelectedApplicationAge : this.managerSelectedApplicationAge;
        const lastStatusAgeFilter = isEmployeeTab ? this.employeeSelectedLastStatusAge : this.managerSelectedLastStatusAge;
        const hasOpenQueriesFilter = isEmployeeTab ? this.employeeSelectedHasOpenQueries : this.managerSelectedHasOpenQueries;
        const managerFilter = isEmployeeTab ? '' : this.managerSelectedManager;
        const ownerFilter = isEmployeeTab ? '' : this.managerSelectedOwner;

        return getApplicationAgingChunk({
            userIds,
            viewType: tabValue,
            showApplicationsIOwn,
            productFilter: productFilter || null,
            createdDateFilter: createdDateFilter || '<30',
            stageFilter: stageFilter || null,
            regionFilter: regionFilter || null,
            applicationAgeFilter: applicationAgeFilter || null,
            lastStatusAgeFilter: lastStatusAgeFilter || null,
            hasOpenQueriesFilter: hasOpenQueriesFilter || null,
            managerFilter: managerFilter || null,
            ownerFilter: ownerFilter || null,
            pageSize: this.pageSize,
            cursorCreatedDate,
            cursorId,
            cursorDirection
        });
    }

    async fetchAllInvestigationPages(tabValue, cursorCreatedDate = null, cursorId = null, cursorDirection = 'forward') {
        const isEmployeeTab = tabValue === 'employeeInvestigation';
        const userIds = isEmployeeTab ? this.employeeUserIds : this.managerUserIds;
        return getInvestigationAgingChunk({
            userIds,
            isAdmin: this.isAdmin,
            statusFilter: isEmployeeTab ? this.employeeInvestigationSelectedStatus : this.managerInvestigationSelectedStatus,
            productFilter: isEmployeeTab ? this.employeeInvestigationSelectedProduct : this.managerInvestigationSelectedProduct,
            regionFilter: isEmployeeTab ? this.employeeInvestigationSelectedRegion : this.managerInvestigationSelectedRegion,
            investigationAgeFilter: isEmployeeTab ? this.employeeInvestigationSelectedInvestigationAge : this.managerInvestigationSelectedInvestigationAge,
            lastStatusAgeFilter: isEmployeeTab ? this.employeeInvestigationSelectedLastStatusAge : this.managerInvestigationSelectedLastStatusAge,
            managerFilter: isEmployeeTab ? null : this.managerInvestigationSelectedManager,
            ownerFilter: isEmployeeTab ? null : this.managerInvestigationSelectedOwner,
            pageSize: this.pageSize,
            cursorCreatedDate,
            cursorId,
            cursorDirection
        });
    }

    async fetchAllQueryPages(tabValue, cursorCreatedDate = null, cursorId = null, cursorDirection = 'forward') {
        const isEmployeeTab = tabValue === 'employeeQuery';
        const userIds = isEmployeeTab ? this.employeeUserIds : this.managerUserIds;
        return getQueryAgingChunk({
            userIds,
            statusFilter: isEmployeeTab ? this.employeeQuerySelectedStatus : this.managerQuerySelectedStatus,
            priorityFilter: isEmployeeTab ? this.employeeQuerySelectedPriority : this.managerQuerySelectedPriority,
            typeFilter: isEmployeeTab ? this.employeeQuerySelectedType : this.managerQuerySelectedType,
            ageFilter: isEmployeeTab ? this.employeeQuerySelectedAge : this.managerQuerySelectedAge,
            managerFilter: isEmployeeTab ? null : this.managerQuerySelectedManager,
            ownerFilter: isEmployeeTab ? null : this.managerQuerySelectedOwner,
            pageSize: this.pageSize,
            cursorCreatedDate,
            cursorId,
            cursorDirection
        });
    }
    
    // Load application data for a specific tab with its filters
    loadApplicationDataForTab(tabValue) {
        // Make sure we have user IDs first.
        // Always return a promise so callers can safely chain .then/.catch/.finally.
        if (!this.userIdsLoaded) {
            return Promise.resolve();
        }
        
        this.isLoadingApplicationData = true;
        this.loadingMessage = 'Loading application data...';
        
        // Use filters based on the active tab
        // When switching tabs, use only the selected filters for that tab (no defaultProduct fallback)
        let productFilter = '';
        let createdDateFilter = '<30';
        
        if (tabValue === 'employee') {
            // Use employee filters - only use selected product, not defaultProduct
            productFilter = this.employeeSelectedProduct || '';
            createdDateFilter = this.employeeSelectedCreatedDate || '<30';
        } else if (tabValue === 'manager') {
            // Use manager filters - only use selected product, not defaultProduct
            productFilter = this.managerSelectedProduct || '';
            createdDateFilter = this.managerSelectedCreatedDate || '<30';
        }
        
        // Force reload to bypass cache when switching tabs
        this.applicationDataLoaded = false;

        return this.fetchAllApplicationPages(tabValue, productFilter, createdDateFilter)
            .then(chunk => {
                const records = (chunk && chunk.records) ? chunk.records : [];
                const mapped = records.map(record => ({
                    ...record,
                    applicationUrl: `/${record.applicationId}`,
                    agingColorClass: this.getAgingColorClass(record.agingInDays)
                }));

                if (tabValue === 'employee') {
                    this.employeeApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
                    this.employeeApplicationNextCursorId = chunk?.nextCursorId || null;
                    this.employeeApplicationHasMore = chunk?.hasMore === true;
                    this.employeeCurrentPage = 1;
                    this.employeeRecords = [...records];
                    this.employeeFilteredRecords = mapped;
                    this.employeeDisplayedRecords = mapped;
                    this.employeeTotalRecords = this.resolveTotalRecords(chunk?.totalCount, this.employeeTotalRecords);
                    this.employeeCountExceedsThreshold = this.resolveCountExceedsThreshold(chunk, this.employeeCountExceedsThreshold);
                    this.employeeTotalPages = this.resolveTotalPages(this.employeeTotalRecords);
                }
                else {
                    this.managerApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
                    this.managerApplicationNextCursorId = chunk?.nextCursorId || null;
                    this.managerApplicationHasMore = chunk?.hasMore === true;
                    this.managerCurrentPage = 1;
                    this.managerRecords = [...records];
                    this.managerFilteredRecords = mapped;
                    this.managerDisplayedRecords = mapped;
                    this.managerTotalRecords = this.resolveTotalRecords(chunk?.totalCount, this.managerTotalRecords);
                    this.managerCountExceedsThreshold = this.resolveCountExceedsThreshold(chunk, this.managerCountExceedsThreshold);
                    this.managerTotalPages = this.resolveTotalPages(this.managerTotalRecords);
                }

                this.error = undefined;
                this.applicationDataLoaded = true;

                if (!this.productOptions || this.productOptions.length === 0) {
                    this.loadProductOptions();
                } else {
                    this.buildDependentFilterOptions();
                }
                this.isLoadingApplicationData = false;
                if (!this.showInvestigations) {
                    this.isLoading = false;
                }
                this.loadingMessage = 'Loading...';
            })
            .catch(error => {
                this.error = error;
                this.employeeRecords = [];
                this.managerRecords = [];
                this.employeeFilteredRecords = [];
                this.managerFilteredRecords = [];
                this.employeeDisplayedRecords = [];
                this.managerDisplayedRecords = [];
                this.isLoadingApplicationData = false;
                this.isLoading = false;
                console.error('Error loading application data:', error);
            });
    }
    
    // OPTIMIZED: Load application data only (called when application tabs are active) - STEP 2
    // Accepts forceReload parameter to bypass cache when product filter changes
    loadApplicationData(forceReload = false) {
        // Use cache if already loaded and not forcing reload
        if (this.applicationDataLoaded && !forceReload) {
            this.isLoadingApplicationData = false;
            return;
        }
        
        // Make sure we have user IDs first
        if (!this.userIdsLoaded) {
            return;
        }
        
        this.isLoadingApplicationData = true;
        this.loadingMessage = 'Loading application data...';
        this.loadApplicationDataForTab('employee');
    }
    
    // OPTIMIZED: Load investigation data only (called when investigation tabs are active) - STEP 2
    loadInvestigationData() {
        // Use cache if already loaded
        if (this.investigationDataLoaded) {
            this.isLoading = false;
            return;
        }
        // Make sure we have user IDs first
        if (!this.userIdsLoaded) {
            return;
        }
        
        this.isLoading = true;
        this.loadingMessage = 'Loading investigation data...';
        
        Promise.all([
            this.fetchAllInvestigationPages('employeeInvestigation', null, null),
            this.isManager ? this.fetchAllInvestigationPages('managerInvestigation', null, null) : Promise.resolve({ records: [], hasMore: false })
        ])
            .then(([employeeInvChunk, managerInvChunk]) => {
                const employeeInvData = employeeInvChunk?.records || [];
                const managerInvData = managerInvChunk?.records || [];
                if (employeeInvData.length > 0) {
                    this.employeeInvestigationRecords = [...employeeInvData].sort((a, b) =>
                        (b.lastStatusTATInDays || b.agingInDays || 0) - (a.lastStatusTATInDays || a.agingInDays || 0)
                    );
                } else {
                    this.employeeInvestigationRecords = [];
                }

                if (this.isManager) {
                    if (managerInvData.length > 0) {
                        this.managerInvestigationRecords = [...managerInvData].sort((a, b) =>
                            (b.lastStatusTATInDays || b.agingInDays || 0) - (a.lastStatusTATInDays || a.agingInDays || 0)
                        );
                    } else {
                        this.managerInvestigationRecords = [];
                    }
                }
                this.employeeInvestigationNextCursorCreatedDate = employeeInvChunk?.nextCursorCreatedDate || null;
                this.employeeInvestigationNextCursorId = employeeInvChunk?.nextCursorId || null;
                this.employeeInvestigationHasMore = employeeInvChunk?.hasMore === true;
                this.employeeInvestigationCurrentPage = 1;
                this.employeeInvestigationTotalRecords = this.resolveTotalRecords(employeeInvChunk?.totalCount, this.employeeInvestigationTotalRecords);
                this.employeeInvestigationCountExceedsThreshold = this.resolveCountExceedsThreshold(employeeInvChunk, this.employeeInvestigationCountExceedsThreshold);
                this.employeeInvestigationTotalPages = this.resolveTotalPages(this.employeeInvestigationTotalRecords);
                this.employeeInvestigationFilteredRecords = this.employeeInvestigationRecords.map(record => ({
                    ...record,
                    investigationUrl: `/${record.investigationId}`,
                    applicationUrl: record.applicationId ? `/${record.applicationId}` : null,
                    agingColorClass: this.getAgingColorClass(record.agingInDays)
                }));
                this.employeeInvestigationDisplayedRecords = this.employeeInvestigationFilteredRecords;
                if (this.isManager) {
                    this.managerInvestigationNextCursorCreatedDate = managerInvChunk?.nextCursorCreatedDate || null;
                    this.managerInvestigationNextCursorId = managerInvChunk?.nextCursorId || null;
                    this.managerInvestigationHasMore = managerInvChunk?.hasMore === true;
                    this.managerInvestigationCurrentPage = 1;
                    this.managerInvestigationTotalRecords = this.resolveTotalRecords(managerInvChunk?.totalCount, this.managerInvestigationTotalRecords);
                    this.managerInvestigationCountExceedsThreshold = this.resolveCountExceedsThreshold(managerInvChunk, this.managerInvestigationCountExceedsThreshold);
                    this.managerInvestigationTotalPages = this.resolveTotalPages(this.managerInvestigationTotalRecords);
                    this.managerInvestigationFilteredRecords = this.managerInvestigationRecords.map(record => ({
                        ...record,
                        investigationUrl: `/${record.investigationId}`,
                        applicationUrl: record.applicationId ? `/${record.applicationId}` : null,
                        agingColorClass: this.getAgingColorClass(record.agingInDays)
                    }));
                    this.managerInvestigationDisplayedRecords = this.managerInvestigationFilteredRecords;
                }
                
                this.error = undefined;
                this.investigationDataLoaded = true;
                
                // Build investigation columns based on selected columns
                this.updateVisibleInvestigationColumns();
                
                // Build filter options for investigations
                this.buildInvestigationFilterOptions();
                
                this.isLoading = false;
                this.loadingMessage = 'Loading...';  
            })
            .catch(error => {
                this.error = error;
                this.employeeInvestigationRecords = [];
                this.managerInvestigationRecords = [];
                this.loadingMessage = 'Error loading data';
                console.error('Error loading investigation aging:', error);
                this.isLoading = false;
            });
    }
    
    // OPTIMIZED: Load query data only (called when query tabs are active)
    loadQueryData() {
        // Use cache if already loaded
        if (this.queryDataLoaded) {
            this.isLoading = false;
            return;
        }
        
        // Make sure we have user IDs first
        if (!this.userIdsLoaded) {
            return;
        }
        
        this.isLoading = true;
        this.loadingMessage = 'Loading query data...';
        
        Promise.all([
            this.fetchAllQueryPages('employeeQuery', null, null),
            this.isManager ? this.fetchAllQueryPages('managerQuery', null, null) : Promise.resolve({ records: [], hasMore: false })
        ])
        .then(([employeeQueryChunk, managerQueryChunk]) => {
            const employeeQueryData = employeeQueryChunk?.records || [];
            const managerQueryData = managerQueryChunk?.records || [];
            if (employeeQueryData.length > 0) {
                this.employeeQueryRecords = employeeQueryData.sort((a, b) =>
                    (b.agingInDays || 0) - (a.agingInDays || 0)
                );
            } else {
                this.employeeQueryRecords = [];
            }
            if (this.isManager && managerQueryData.length > 0) {
                this.managerQueryRecords = managerQueryData.sort((a, b) =>
                    (b.agingInDays || 0) - (a.agingInDays || 0)
                );
            } else if (this.isManager) {
                this.managerQueryRecords = [];
            }
            this.employeeQueryNextCursorCreatedDate = employeeQueryChunk?.nextCursorCreatedDate || null;
            this.employeeQueryNextCursorId = employeeQueryChunk?.nextCursorId || null;
            this.employeeQueryHasMore = employeeQueryChunk?.hasMore === true;
            this.employeeQueryCurrentPage = 1;
            this.employeeQueryFilteredRecords = [...this.employeeQueryRecords];
            this.employeeQueryDisplayedRecords = this.employeeQueryFilteredRecords;
            this.employeeQueryTotalRecords = this.resolveTotalRecords(employeeQueryChunk?.totalCount, this.employeeQueryTotalRecords);
            this.employeeQueryCountExceedsThreshold = this.resolveCountExceedsThreshold(employeeQueryChunk, this.employeeQueryCountExceedsThreshold);
            this.employeeQueryTotalPages = this.resolveTotalPages(this.employeeQueryTotalRecords);
            if (this.isManager) {
                this.managerQueryNextCursorCreatedDate = managerQueryChunk?.nextCursorCreatedDate || null;
                this.managerQueryNextCursorId = managerQueryChunk?.nextCursorId || null;
                this.managerQueryHasMore = managerQueryChunk?.hasMore === true;
                this.managerQueryCurrentPage = 1;
                this.managerQueryFilteredRecords = [...this.managerQueryRecords];
                this.managerQueryDisplayedRecords = this.managerQueryFilteredRecords;
                this.managerQueryTotalRecords = this.resolveTotalRecords(managerQueryChunk?.totalCount, this.managerQueryTotalRecords);
                this.managerQueryCountExceedsThreshold = this.resolveCountExceedsThreshold(managerQueryChunk, this.managerQueryCountExceedsThreshold);
                this.managerQueryTotalPages = this.resolveTotalPages(this.managerQueryTotalRecords);
            }
            
            // Mark as loaded
            this.queryDataLoaded = true;
            
            // Build filter options from the data
            this.buildQueryFilterOptions();
            
            this.isLoading = false;
        })
        .catch(error => {
            console.error('Error loading query aging:', error);
            this.error = error;
            this.loadingMessage = 'Error loading query information';
            this.isLoading = false;
        });
    }
    
    buildColumns() {
        // Define all available columns for applications
        // Manager is hidden by default - user can select from column selector
        this.availableColumns = [
            { label: 'Application Name', value: 'applicationName', selected: true },
            { label: 'Product', value: 'product', selected: true },
            { label: 'Stage', value: 'stage', selected: true },
            { label: 'Owner', value: 'owner', selected: true },
            { label: 'Total TAT (D)', value: 'applicationTotalTATDays', selected: true },
            { label: 'Status TAT (D)', value: 'lastStatusTATDays', selected: true },
            { label: 'Total TAT (H)', value: 'applicationTotalTATHours', selected: false },
            { label: 'Status TAT (H)', value: 'lastStatusTATHours', selected: false },
            { label: 'Aging (Days)', value: 'agingDays', selected: false },
            { label: 'Aging (Hours)', value: 'agingHours', selected: false },
            { label: 'Latest SLA Date', value: 'slaDate', selected: false },
            { label: 'Manager', value: 'manager', selected: false }
        ];
        
        // Set initially selected columns
        this.selectedColumns = this.availableColumns
            .filter(col => col.selected)
            .map(col => col.value);
        
        // Build visible columns for applications
        this.updateVisibleColumns();
        
        // Build investigation columns based on selection
        this.buildAvailableInvestigationColumns();
        this.updateVisibleInvestigationColumns();
        
        // Build query columns
        this.buildQueryColumns();
    }
    
    buildAvailableInvestigationColumns() {
        // Define all available columns for investigations
        // Default columns: Investigation Name, Status, Product, Application Name, Owner, Total TAT (D), Status TAT (D)
        this.availableInvestigationColumns = [
            { label: 'Investigation Name', value: 'investigationName', selected: true },
            { label: 'Status', value: 'investigationStatus', selected: true },
            { label: 'TAT Stage', value: 'tatStage', selected: false },
            { label: 'Product', value: 'product', selected: true },
            { label: 'Application Name', value: 'applicationName', selected: true },
            { label: 'Application Stage', value: 'applicationStage', selected: false },
            { label: 'Owner', value: 'owner', selected: true },
            { label: 'Total TAT (D)', value: 'investigationTotalTATDays', selected: true },
            { label: 'Total TAT (H)', value: 'investigationTotalTATHours', selected: false },
            { label: 'Status TAT (D)', value: 'lastStatusTATDays', selected: true },
            { label: 'Status TAT (H)', value: 'lastStatusTATHours', selected: false },
            { label: 'Aging (Days)', value: 'agingDays', selected: false },
            { label: 'Aging (Hours)', value: 'agingHours', selected: false },
            { label: 'Manager', value: 'manager', selected: false }
        ];
        
        // Set initially selected columns
        this.selectedInvestigationColumns = this.availableInvestigationColumns
            .filter(col => col.selected)
            .map(col => col.value);
    }
    
    updateVisibleInvestigationColumns() {
        const allInvestigationColumnDefinitions = {
            investigationName: {
                label: 'Investigation Name',
                fieldName: 'investigationUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'investigationName' },
                    target: '_blank'
                },
                sortable: true,
                wrapText: true,
                initialWidth: 120
            },
            investigationStatus: {
                label: 'Status',
                fieldName: 'investigationStatus',
                type: 'text',
                sortable: true
            },
            tatStage: {
                label: 'TAT Stage',
                fieldName: 'tatStage',
                type: 'text',
                sortable: true,
                wrapText: true
            },
            product: {
                label: 'Product',
                fieldName: 'product',
                type: 'text',
                sortable: true,
                initialWidth: 90
            },
            applicationName: {
                label: 'Application Name',
                fieldName: 'applicationUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'applicationName' },
                    target: '_blank'
                },
                sortable: true,
                wrapText: true,
                initialWidth: 140
            },
            applicationStage: {
                label: 'Application Stage',
                fieldName: 'applicationStage',
                type: 'text',
                sortable: true
            },
            owner: {
                label: 'Owner',
                fieldName: 'ownerName',
                type: 'text',
                sortable: true
            },
            investigationTotalTATDays: {
                label: 'Total TAT (D)',
                fieldName: 'investigationTotalTATInDays',
                type: 'number',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'agingColorClass' }
                }
            },
            investigationTotalTATHours: {
                label: 'Total TAT (H)',
                fieldName: 'investigationTotalTATInHours',
                type: 'number',
                sortable: true
            },
            lastStatusTATDays: {
                label: 'Status TAT (D)',
                fieldName: 'lastStatusTATInDays',
                type: 'number',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'agingColorClass' }
                }
            },
            lastStatusTATHours: {
                label: 'Status TAT (H)',
                fieldName: 'lastStatusTATInHours',
                type: 'number',
                sortable: true
            },
            agingDays: {
                label: 'Aging (Days)',
                fieldName: 'agingInDays',
                type: 'number',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'agingColorClass' }
                }
            },
            agingHours: {
                label: 'Aging (Hours)',
                fieldName: 'agingInHours',
                type: 'number',
                sortable: true
            },
            manager: {
                label: 'Manager',
                fieldName: 'ownerManagerName',
                type: 'text',
                sortable: true
            }
        };
        
        // Build columns array based on selected columns
        this.investigationColumns = this.selectedInvestigationColumns
            .map(colValue => allInvestigationColumnDefinitions[colValue])
            .filter(col => col !== undefined);
    }
    
    updateVisibleColumns() {
        const allColumnDefinitions = {
            applicationName: {
                label: 'Application Name',
                fieldName: 'applicationUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'applicationName' },
                    target: '_blank'
                },
                sortable: true,
                wrapText: true
            },
            product: {
                label: 'Product',
                fieldName: 'product',
                type: 'text',
                sortable: true,
                initialWidth: 110
            },
            stage: {
                label: 'Stage',
                fieldName: 'applicationStage',
                type: 'text',
                sortable: true,
                wrapText: true
            },
            owner: {
                label: 'Owner',
                fieldName: 'ownerName',
                type: 'text',
                sortable: true,
                wrapText: true
            },
            manager: {
                label: 'Manager',
                fieldName: 'ownerManagerName',
                type: 'text',
                sortable: true
            },
            applicationTotalTATDays: {
                label: 'Total TAT (D)',
                fieldName: 'applicationTotalTATInDays',
                type: 'number',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'agingColorClass' }
                }
            },
            applicationTotalTATHours: {
                label: 'Total TAT (H)',
                fieldName: 'applicationTotalTATInHours',
                type: 'number',
                sortable: true
            },
            lastStatusTATDays: {
                label: 'Status TAT (D)',
                fieldName: 'lastStatusTATInDays',
                type: 'number',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'agingColorClass' }
                }
            },
            lastStatusTATHours: {
                label: 'Status TAT (H)',
                fieldName: 'lastStatusTATInHours',
                type: 'number',
                sortable: true
            },
            agingDays: {
                label: 'Aging (Days)',
                fieldName: 'agingInDays',
                type: 'number',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'agingColorClass' }
                }
            },
            agingHours: {
                label: 'Aging (Hours)',
                fieldName: 'agingInHours',
                type: 'number',
                sortable: true
            },
            slaDate: {
                label: 'Latest SLA Date',
                fieldName: 'latestSLACreatedDate',
                type: 'date',
                sortable: true,
                typeAttributes: {
                    day: 'numeric',
                    month: 'short',
                    year: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit',
                    second: '2-digit',
                    hour12: true
                }
            }
        };
        
        // Build columns array based on selected columns
        this.columns = this.selectedColumns
            .map(colValue => allColumnDefinitions[colValue])
            .filter(col => col !== undefined);
    }
    
    loadProductOptions() {
        /*// Build product options dropdown
        // Convert Proxy array to regular array before sorting (Apex returns Proxy arrays that can't be sorted in place)
        const productsArray = Array.from(products || []);
        const sortedProducts = productsArray.sort();
        const mappedProducts = sortedProducts.map(product => {
            return { label: product, value: product };
        });
        
        this.productOptions = [
            { label: '-- All Products --', value: '' },
            ...mappedProducts
        ];*/
        
        // Build dependent filter options for applications
        this.buildDependentFilterOptions();
        
        // Build investigation filter options if investigations are enabled
        if (this.showInvestigations) {
            this.buildEmployeeInvestigationDependentFilters();
            if (this.isManager) {
                this.buildManagerInvestigationDependentFilters();
            }
        }
    }
    
    // Fallback method to build product options from current records
    buildFilterOptionsFromRecords() {
        const allProducts = new Set();
        this.employeeRecords.forEach(record => {
            if (record.product) allProducts.add(record.product);
        });
        if (this.isManager) {
            this.managerRecords.forEach(record => {
                if (record.product) allProducts.add(record.product);
            });
        }
        
        this.productOptions = [
            { label: '-- All Products --', value: '' },
            ...Array.from(allProducts).sort().map(product => ({ label: product, value: product }))
        ];
        
        // Build dependent filter options
        this.buildDependentFilterOptions();
    }
    
    buildFilterOptions() {
        // This method is now replaced by loadProductOptions()
        // Keeping for backwards compatibility - calls loadProductOptions
        this.loadProductOptions();
    }
    
    buildDependentFilterOptions() {
        if (this.activeTab === 'employee') {
            this.buildEmployeeDependentFilters();
        } else {
            this.buildManagerDependentFilters();
        }
    }
    
    buildEmployeeDependentFilters() {
        // NOTE: Product filter is now applied server-side, so records are already filtered
        // No need to filter by product here
        let filteredForStage = this.employeeRecords;
        
        // Build stage options based on filtered records
        const stages = new Set();
        filteredForStage.forEach(record => {
            if (record.applicationStage) stages.add(record.applicationStage);
        });
        this.stageOptions = [
            { label: '-- All Stages --', value: '' },
            ...Array.from(stages).sort().map(stage => ({ label: stage, value: stage }))
        ];
        
        // Filter records further for region options
        let filteredForRegion = filteredForStage;
        if (this.employeeSelectedStage) {
            filteredForRegion = filteredForRegion.filter(r => r.applicationStage === this.employeeSelectedStage);
        }
    }
    
    buildManagerDependentFilters() {
        // NOTE: Product filter is now applied server-side, so records are already filtered
        // No need to filter by product here
        let filteredForStage = this.managerRecords;
        
        // Build stage options
        const stages = new Set();
        filteredForStage.forEach(record => {
            if (record.applicationStage) stages.add(record.applicationStage);
        });
        this.stageOptions = [
            { label: '-- All Stages --', value: '' },
            ...Array.from(stages).sort().map(stage => ({ label: stage, value: stage }))
        ];
        
        // Filter records further for manager options
        let filteredForManager = filteredForStage;
        if (this.managerSelectedStage) {
            filteredForManager = filteredForManager.filter(r => r.applicationStage === this.managerSelectedStage);
        }
        
        // Build manager options
        const managers = new Set();
        filteredForManager.forEach(record => {
            if (record.ownerManagerName) managers.add(record.ownerManagerName);
        });
        this.managerOptions = [
            { label: '-- All Managers --', value: '' },
            ...Array.from(managers).sort().map(manager => ({ label: manager, value: manager }))
        ];
        
        // Filter records further for owner options
        let filteredForOwner = filteredForManager;
        if (this.managerSelectedManager) {
            filteredForOwner = filteredForOwner.filter(r => r.ownerManagerName === this.managerSelectedManager);
        }
        
        // Build owner options
        const owners = new Set();
        filteredForOwner.forEach(record => {
            if (record.ownerName) owners.add(record.ownerName);
        });
        this.ownerOptions = [
            { label: '-- All Owners --', value: '' },
            ...Array.from(owners).sort().map(owner => ({ label: owner, value: owner }))
        ];
        
        // Filter records further for region options
        let filteredForRegion = filteredForOwner;
        if (this.managerSelectedOwner) {
            filteredForRegion = filteredForRegion.filter(r => r.ownerName === this.managerSelectedOwner);
        }
    }
    
    // Internal method called when activeTab changes (from setter or event)
    handleTabChangeInternal(newTabValue) {
        // Load data based on active tab (lazy loading + caching)
        if (newTabValue === 'employeeInvestigation' || newTabValue === 'managerInvestigation') {
            // Investigation tab - load investigation data if not already loaded
            this.loadInvestigationData();
        } else if (newTabValue === 'employeeQuery' || newTabValue === 'managerQuery') {
            // Query tab - load query data if not already loaded
            this.loadQueryData();
        } else {
            // Application tab - reload data with correct filters for the active tab
            // When switching between employee and manager tabs, we need to reload with their respective filters
            if (newTabValue === 'employee' || newTabValue === 'manager') {
                this.loadApplicationDataForTab(newTabValue);
            } else {
                this.loadApplicationData();
            }
        }
        
        // For cached application tabs, refresh local mapping state quickly.
        if ((newTabValue === 'employee' || newTabValue === 'manager') && this.applicationDataLoaded) {
            this.applyFilters();
        }
    }
    
    get showEmployeeTab() {
        return true; // Always show employee tab
    }
    
    // My Applications tab visibility
    get showMyApplicationsTab() {
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
    
    handleEmployeeProductChange(event) {
        if (this.activeTab !== 'employee') {
            return;
        }
        this.employeeSelectedProduct = event.detail.value;
        // Reset dependent filters when product changes
        this.employeeSelectedStage = '';
        this.employeeSelectedRegion = '';
        this.loadApplicationDataForTab('employee');
    }
    
    handleEmployeeStageChange(event) {
        this.employeeSelectedStage = event.detail.value;
        // Reset dependent filters when stage changes
        this.employeeSelectedRegion = '';
        this.loadApplicationDataForTab('employee');
    }
    
    handleEmployeeRegionChange(event) {
        this.employeeSelectedRegion = event.detail.value;
        this.loadApplicationDataForTab('employee');
    }
    
    handleEmployeeApplicationAgeChange(event) {
        this.employeeSelectedApplicationAge = event.detail.value;
        this.loadApplicationDataForTab('employee');
    }
    
    handleEmployeeLastStatusAgeChange(event) {
        this.employeeSelectedLastStatusAge = event.detail.value;
        this.loadApplicationDataForTab('employee');
    }
    
    handleEmployeeHasOpenQueriesChange(event) {
        this.employeeSelectedHasOpenQueries = event.detail.value;
        this.loadApplicationDataForTab('employee');
    }
    
    // Handler for "Show applications I own" checkbox
    handleShowApplicationsIOwnChange(event) {
        // Set the appropriate toggle based on active tab
        if (this.activeTab === 'employee') {
            this.employeeShowApplicationsIOwn = event.detail.checked;
        } else if (this.activeTab === 'manager') {
            this.managerShowApplicationsIOwn = event.detail.checked;
        }
        // Reload data when ownership scope changes.
        if (this.activeTab === 'employee' || this.activeTab === 'manager') {
            this.loadApplicationDataForTab(this.activeTab);
        }
    }
    
    handleManagerProductChange(event) {
        if (this.activeTab !== 'manager') {
            return;
        }
        this.managerSelectedProduct = event.detail.value;
        // Reset dependent filters when product changes
        this.managerSelectedStage = '';
        this.managerSelectedManager = '';
        this.managerSelectedOwner = '';
        this.managerSelectedRegion = '';
        this.loadApplicationDataForTab('manager');
    }
    
    handleManagerStageChange(event) {
        this.managerSelectedStage = event.detail.value;
        // Reset dependent filters when stage changes
        this.managerSelectedManager = '';
        this.managerSelectedOwner = '';
        this.managerSelectedRegion = '';
        this.loadApplicationDataForTab('manager');
    }
    
    handleManagerManagerChange(event) {
        this.managerSelectedManager = event.detail.value;
        // Reset dependent filters when manager changes
        this.managerSelectedOwner = '';
        this.managerSelectedRegion = '';
        this.loadApplicationDataForTab('manager');
    }
    
    handleManagerOwnerChange(event) {
        this.managerSelectedOwner = event.detail.value;
        // Reset dependent filters when owner changes
        this.managerSelectedRegion = '';
        this.loadApplicationDataForTab('manager');
    }
    
    handleManagerRegionChange(event) {
        this.managerSelectedRegion = event.detail.value;
        this.loadApplicationDataForTab('manager');
    }
    
    handleManagerApplicationAgeChange(event) {
        this.managerSelectedApplicationAge = event.detail.value;
        this.loadApplicationDataForTab('manager');
    }
    
    handleManagerLastStatusAgeChange(event) {
        this.managerSelectedLastStatusAge = event.detail.value;
        this.loadApplicationDataForTab('manager');
    }
    
    handleManagerHasOpenQueriesChange(event) {
        this.managerSelectedHasOpenQueries = event.detail.value;
        this.loadApplicationDataForTab('manager');
    }
    
    handleEmployeeCreatedDateChange(event) {
        if (this.activeTab !== 'employee') {
            return;
        }
        this.employeeSelectedCreatedDate = event.detail.value || '<30';
        this.loadApplicationDataForTab('employee');
    }

    handleManagerCreatedDateChange(event) {
        if (this.activeTab !== 'manager') {
            return;
        }
        this.managerSelectedCreatedDate = event.detail.value || '<30';
        this.loadApplicationDataForTab('manager');
    }
    
    clearEmployeeFilters() {
        // NOTE: This is ONLY for 'My Applications' tab - Investigation tabs have separate clear filters
        // Safety check: Only process if we're on the employee (My Applications) tab
        if (this.activeTab !== 'employee') {
            return;
        }
        
        this.employeeSelectedStage = '';
        this.employeeSelectedProduct = '';
        this.employeeSelectedRegion = '';
        this.employeeSelectedApplicationAge = '';
        this.employeeSelectedLastStatusAge = '';
        this.employeeSelectedHasOpenQueries = '';
        this.employeeSelectedCreatedDate = '<30'; // Reset to default

        // All application filters are server-driven now; reload first page.
        this.loadApplicationDataForTab('employee');
    }
    
    clearManagerFilters() {
        // NOTE: This is ONLY for 'My Team' tab - Investigation tabs have separate clear filters
        // Safety check: Only process if we're on the manager (My Team) tab
        if (this.activeTab !== 'manager') {
            return;
        }
        
        this.managerSelectedStage = '';
        this.managerSelectedManager = '';
        this.managerSelectedOwner = '';
        this.managerSelectedProduct = '';
        this.managerSelectedRegion = '';
        this.managerSelectedApplicationAge = '';
        this.managerSelectedLastStatusAge = '';
        this.managerSelectedHasOpenQueries = '';
        this.managerSelectedCreatedDate = '<30'; // Reset to default

        // All application filters are server-driven now; reload first page.
        this.loadApplicationDataForTab('manager');
    }
    
    buildQueryColumns() {
        // Define columns for query data table
        this.queryColumns = [
            {
                label: 'Query Number',
                fieldName: 'queryNumber',
                type: 'text',
                sortable: true,
                initialWidth: 120
            },
            {
                label: 'Subject',
                fieldName: 'subject',
                type: 'text',
                sortable: true,
                wrapText: true,
                initialWidth: 200
            },
            {
                label: 'Status',
                fieldName: 'status',
                type: 'text',
                sortable: true,
                initialWidth: 120
            },
            {
                label: 'Priority',
                fieldName: 'priority',
                type: 'text',
                sortable: true,
                initialWidth: 100
            },
            {
                label: 'Type',
                fieldName: 'queryType',
                type: 'text',
                sortable: true,
                initialWidth: 120
            },
            {
                label: 'Application Name',
                fieldName: 'applicationName',
                type: 'text',
                sortable: true,
                initialWidth: 150
            },
            {
                label: 'Product',
                fieldName: 'product',
                type: 'text',
                sortable: true,
                initialWidth: 120
            },
            {
                label: 'Owner',
                fieldName: 'ownerName',
                type: 'text',
                sortable: true,
                initialWidth: 120
            },
            {
                label: 'Manager',
                fieldName: 'ownerManagerName',
                type: 'text',
                sortable: true,
                initialWidth: 120
            },
            {
                label: 'Aging (Days)',
                fieldName: 'agingInDays',
                type: 'number',
                sortable: true,
                typeAttributes: {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2
                },
                initialWidth: 120
            },
            {
                label: 'Aging (Hours)',
                fieldName: 'agingInHours',
                type: 'number',
                sortable: true,
                typeAttributes: {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2
                },
                initialWidth: 120
            },
            {
                label: 'Created Date',
                fieldName: 'createdDate',
                type: 'date',
                sortable: true,
                typeAttributes: {
                    year: 'numeric',
                    month: 'short',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit'
                },
                initialWidth: 150
            }
        ];
    }
    
    applyFilters() {
        if (this.activeTab === 'employee') {
            this.applyEmployeeFilters();
        } else if (this.activeTab === 'manager') {
            this.applyManagerFilters();
        }
    }
    
    applyEmployeeFilters() {
        this.employeeFilteredRecords = this.employeeRecords.map(record => ({
            ...record,
            applicationUrl: `/${record.applicationId}`,
            agingColorClass: this.getAgingColorClass(record.agingInDays)
        }));
        this.employeeDisplayedRecords = this.employeeFilteredRecords;
        
        // Re-apply sort if active
        if (this.employeeApplicationSortedBy) {
            this.sortData('employeeApplication');
        }
    }
    
    applyManagerFilters() {
        this.managerFilteredRecords = this.managerRecords.map(record => ({
            ...record,
            applicationUrl: `/${record.applicationId}`,
            agingColorClass: this.getAgingColorClass(record.agingInDays)
        }));
        this.managerDisplayedRecords = this.managerFilteredRecords;
        
        // Re-apply sort if active
        if (this.managerApplicationSortedBy) {
            this.sortData('managerApplication');
        }
    }
    
    updateEmployeeDisplayedRecords() {
        const start = (this.employeeCurrentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.employeeDisplayedRecords = this.employeeFilteredRecords.slice(start, end);
    }
    
    updateManagerDisplayedRecords() {
        const start = (this.managerCurrentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.managerDisplayedRecords = this.managerFilteredRecords.slice(start, end);
    }
    
    getAgingColorClass(agingInDays) {
        if (!agingInDays) return '';
        if (agingInDays > 7) return 'slds-text-color_error';
        if (agingInDays > 3) return 'slds-text-color_warning';
        return '';
    }

    resolveTotalRecords(serverTotalCount, fallbackTotalCount) {
        return Number.isInteger(serverTotalCount) ? serverTotalCount : (fallbackTotalCount || 0);
    }

    resolveTotalPages(totalRecords) {
        return totalRecords > 0 ? Math.ceil(totalRecords / this.pageSize) : 0;
    }

    resolveCountExceedsThreshold(chunk, fallbackFlag) {
        if (chunk && typeof chunk.countExceedsThreshold === 'boolean') {
            return chunk.countExceedsThreshold;
        }
        return fallbackFlag === true;
    }

    formatTotalRecordsLabel(totalRecords, exceedsThreshold) {
        if (exceedsThreshold) {
            return `${totalRecords.toLocaleString()}+`;
        }
        return totalRecords.toLocaleString();
    }
    
    // ============================================================
    // Application pagination handlers
    // ------------------------------------------------------------
    // All four buttons (First / Previous / Next / Last) run a SINGLE Apex round trip
    // and rely on keyset cursors derived from the currently displayed records:
    //   - Previous cursor = newest record on this page (records[0])  → backward walk
    //   - Next cursor     = oldest record on this page (records[last]) → forward walk
    //   - Last / First    = direction with no cursor (server fetches the boundary page)
    // No cursor-history stack is needed because the boundary records are always at hand.
    // ============================================================

    _mapApplicationRecords(records) {
        return records.map(record => ({
            ...record,
            applicationUrl: `/${record.applicationId}`,
            agingColorClass: this.getAgingColorClass(record.agingInDays)
        }));
    }

    async handleEmployeeFirst() {
        if (this.employeeCurrentPage <= 1) return;
        this.isLoadingApplicationData = true;
        try {
            const productFilter = this.employeeSelectedProduct || '';
            const createdDateFilter = this.employeeSelectedCreatedDate || '<30';
            const chunk = await this.fetchAllApplicationPages('employee', productFilter, createdDateFilter, null, null, 'forward');
            const records = chunk?.records || [];
            const mapped = this._mapApplicationRecords(records);
            this.employeeApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeApplicationNextCursorId = chunk?.nextCursorId || null;
            this.employeeApplicationHasMore = chunk?.hasMore === true;
            this.employeeCurrentPage = 1;
            this.employeeRecords = [...records];
            this.employeeFilteredRecords = mapped;
            this.employeeDisplayedRecords = mapped;
            this.employeeTotalRecords = this.resolveTotalRecords(chunk?.totalCount, this.employeeTotalRecords);
            this.employeeCountExceedsThreshold = this.resolveCountExceedsThreshold(chunk, this.employeeCountExceedsThreshold);
            this.employeeTotalPages = this.resolveTotalPages(this.employeeTotalRecords);
        } finally {
            this.isLoadingApplicationData = false;
        }
    }

    async handleEmployeePrevious() {
        if (this.employeeCurrentPage <= 1) return;
        if (!this.employeeRecords || this.employeeRecords.length === 0) return;
        const firstOnPage = this.employeeRecords[0];
        this.isLoadingApplicationData = true;
        try {
            const productFilter = this.employeeSelectedProduct || '';
            const createdDateFilter = this.employeeSelectedCreatedDate || '<30';
            const chunk = await this.fetchAllApplicationPages(
                'employee',
                productFilter,
                createdDateFilter,
                firstOnPage.applicationCreatedDate,
                firstOnPage.applicationId,
                'backward'
            );
            const records = chunk?.records || [];
            const mapped = this._mapApplicationRecords(records);
            this.employeeApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeApplicationNextCursorId = chunk?.nextCursorId || null;
            // We just came from a forward-reachable page, so a Next is always available.
            this.employeeApplicationHasMore = true;
            this.employeeCurrentPage = Math.max(1, this.employeeCurrentPage - 1);
            this.employeeRecords = [...records];
            this.employeeFilteredRecords = mapped;
            this.employeeDisplayedRecords = mapped;
        } finally {
            this.isLoadingApplicationData = false;
        }
    }

    async handleEmployeeNext() {
        if (!this.employeeApplicationHasMore || !this.employeeApplicationNextCursorId) return;
        this.isLoadingApplicationData = true;
        try {
            const productFilter = this.employeeSelectedProduct || '';
            const createdDateFilter = this.employeeSelectedCreatedDate || '<30';
            const chunk = await this.fetchAllApplicationPages(
                'employee',
                productFilter,
                createdDateFilter,
                this.employeeApplicationNextCursorCreatedDate,
                this.employeeApplicationNextCursorId,
                'forward'
            );
            const records = chunk?.records || [];
            const mapped = this._mapApplicationRecords(records);
            this.employeeApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeApplicationNextCursorId = chunk?.nextCursorId || null;
            this.employeeApplicationHasMore = chunk?.hasMore === true;
            this.employeeCurrentPage += 1;
            this.employeeRecords = [...records];
            this.employeeFilteredRecords = mapped;
            this.employeeDisplayedRecords = mapped;
        } finally {
            this.isLoadingApplicationData = false;
        }
    }

    async handleEmployeeLast() {
        if (this.employeeTotalPages <= 1 && !this.employeeCountExceedsThreshold) return;
        this.isLoadingApplicationData = true;
        try {
            const productFilter = this.employeeSelectedProduct || '';
            const createdDateFilter = this.employeeSelectedCreatedDate || '<30';
            const chunk = await this.fetchAllApplicationPages('employee', productFilter, createdDateFilter, null, null, 'backward');
            const records = chunk?.records || [];
            const mapped = this._mapApplicationRecords(records);
            this.employeeApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeApplicationNextCursorId = chunk?.nextCursorId || null;
            // Backward fetch with no cursor lands on the final page; no further Next exists.
            this.employeeApplicationHasMore = false;
            this.employeeCurrentPage = Math.max(this.employeeTotalPages || 1, 1);
            this.employeeRecords = [...records];
            this.employeeFilteredRecords = mapped;
            this.employeeDisplayedRecords = mapped;
        } finally {
            this.isLoadingApplicationData = false;
        }
    }

    async handleManagerFirst() {
        if (this.managerCurrentPage <= 1) return;
        this.isLoadingApplicationData = true;
        try {
            const productFilter = this.managerSelectedProduct || '';
            const createdDateFilter = this.managerSelectedCreatedDate || '<30';
            const chunk = await this.fetchAllApplicationPages('manager', productFilter, createdDateFilter, null, null, 'forward');
            const records = chunk?.records || [];
            const mapped = this._mapApplicationRecords(records);
            this.managerApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerApplicationNextCursorId = chunk?.nextCursorId || null;
            this.managerApplicationHasMore = chunk?.hasMore === true;
            this.managerCurrentPage = 1;
            this.managerRecords = [...records];
            this.managerFilteredRecords = mapped;
            this.managerDisplayedRecords = mapped;
            this.managerTotalRecords = this.resolveTotalRecords(chunk?.totalCount, this.managerTotalRecords);
            this.managerCountExceedsThreshold = this.resolveCountExceedsThreshold(chunk, this.managerCountExceedsThreshold);
            this.managerTotalPages = this.resolveTotalPages(this.managerTotalRecords);
        } finally {
            this.isLoadingApplicationData = false;
        }
    }

    async handleManagerPrevious() {
        if (this.managerCurrentPage <= 1) return;
        if (!this.managerRecords || this.managerRecords.length === 0) return;
        const firstOnPage = this.managerRecords[0];
        this.isLoadingApplicationData = true;
        try {
            const productFilter = this.managerSelectedProduct || '';
            const createdDateFilter = this.managerSelectedCreatedDate || '<30';
            const chunk = await this.fetchAllApplicationPages(
                'manager',
                productFilter,
                createdDateFilter,
                firstOnPage.applicationCreatedDate,
                firstOnPage.applicationId,
                'backward'
            );
            const records = chunk?.records || [];
            const mapped = this._mapApplicationRecords(records);
            this.managerApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerApplicationNextCursorId = chunk?.nextCursorId || null;
            this.managerApplicationHasMore = true;
            this.managerCurrentPage = Math.max(1, this.managerCurrentPage - 1);
            this.managerRecords = [...records];
            this.managerFilteredRecords = mapped;
            this.managerDisplayedRecords = mapped;
        } finally {
            this.isLoadingApplicationData = false;
        }
    }

    async handleManagerNext() {
        if (!this.managerApplicationHasMore || !this.managerApplicationNextCursorId) return;
        this.isLoadingApplicationData = true;
        try {
            const productFilter = this.managerSelectedProduct || '';
            const createdDateFilter = this.managerSelectedCreatedDate || '<30';
            const chunk = await this.fetchAllApplicationPages(
                'manager',
                productFilter,
                createdDateFilter,
                this.managerApplicationNextCursorCreatedDate,
                this.managerApplicationNextCursorId,
                'forward'
            );
            const records = chunk?.records || [];
            const mapped = this._mapApplicationRecords(records);
            this.managerApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerApplicationNextCursorId = chunk?.nextCursorId || null;
            this.managerApplicationHasMore = chunk?.hasMore === true;
            this.managerCurrentPage += 1;
            this.managerRecords = [...records];
            this.managerFilteredRecords = mapped;
            this.managerDisplayedRecords = mapped;
        } finally {
            this.isLoadingApplicationData = false;
        }
    }

    async handleManagerLast() {
        if (this.managerTotalPages <= 1 && !this.managerCountExceedsThreshold) return;
        this.isLoadingApplicationData = true;
        try {
            const productFilter = this.managerSelectedProduct || '';
            const createdDateFilter = this.managerSelectedCreatedDate || '<30';
            const chunk = await this.fetchAllApplicationPages('manager', productFilter, createdDateFilter, null, null, 'backward');
            const records = chunk?.records || [];
            const mapped = this._mapApplicationRecords(records);
            this.managerApplicationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerApplicationNextCursorId = chunk?.nextCursorId || null;
            this.managerApplicationHasMore = false;
            this.managerCurrentPage = Math.max(this.managerTotalPages || 1, 1);
            this.managerRecords = [...records];
            this.managerFilteredRecords = mapped;
            this.managerDisplayedRecords = mapped;
        } finally {
            this.isLoadingApplicationData = false;
        }
    }
    
    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.detail.value, 10);

        if (this.activeTab === 'employee' || this.activeTab === 'manager') {
            this.loadApplicationDataForTab(this.activeTab);
        } else if (this.activeTab === 'employeeInvestigation') {
            this.investigationDataLoaded = false;
            this.loadInvestigationData();
        } else if (this.activeTab === 'managerInvestigation') {
            this.investigationDataLoaded = false;
            this.loadInvestigationData();
        } else if (this.activeTab === 'employeeQuery') {
            this.queryDataLoaded = false;
            this.loadQueryData();
        } else if (this.activeTab === 'managerQuery') {
            this.queryDataLoaded = false;
            this.loadQueryData();
        }
    }
    
    // Computed properties for employee view
    get employeeHasRecords() {
        return this.employeeFilteredRecords && this.employeeFilteredRecords.length > 0;
    }
    
    get employeeHasFilters() {
        return this.employeeSelectedStage || this.employeeSelectedProduct || this.employeeSelectedRegion || 
               this.employeeSelectedApplicationAge || this.employeeSelectedLastStatusAge || 
               this.employeeSelectedHasOpenQueries || 
               (this.employeeSelectedCreatedDate && this.employeeSelectedCreatedDate !== '<30');
    }
    
    get employeeShowPagination() {
        return this.employeeTotalPages > 1;
    }
    
    get employeeIsPreviousDisabled() {
        return this.employeeCurrentPage <= 1;
    }
    
    get employeeIsNextDisabled() {
        if (this.employeeCountExceedsThreshold) {
            return !this.employeeApplicationHasMore;
        }
        return this.employeeCurrentPage >= this.employeeTotalPages;
    }
    
    get employeePaginationInfo() {
        if (this.employeeTotalRecords === 0 && !this.employeeCountExceedsThreshold) return 'No records';
        const start = (this.employeeCurrentPage - 1) * this.pageSize + 1;
        const displayedCount = (this.employeeDisplayedRecords && this.employeeDisplayedRecords.length) || 0;
        const end = displayedCount > 0
            ? start + displayedCount - 1
            : Math.min(start + this.pageSize - 1, this.employeeTotalRecords);
        const totalLabel = this.formatTotalRecordsLabel(this.employeeTotalRecords, this.employeeCountExceedsThreshold);
        return `Showing ${start} - ${end} of ${totalLabel} records`;
    }
    
    get employeeRowNumberOffset() {
        return (this.employeeCurrentPage - 1) * this.pageSize;
    }
    
    get employeePageInfo() {
        const totalPagesLabel = this.employeeCountExceedsThreshold
            ? `${this.employeeTotalPages}+`
            : `${this.employeeTotalPages}`;
        return `${this.employeeCurrentPage} / ${totalPagesLabel}`;
    }
    
    // Computed properties for manager view
    get managerHasRecords() {
        return this.managerFilteredRecords && this.managerFilteredRecords.length > 0;
    }
    
    get managerHasFilters() {
        return this.managerSelectedStage || this.managerSelectedManager || 
               this.managerSelectedOwner || this.managerSelectedProduct || this.managerSelectedRegion ||
               this.managerSelectedApplicationAge || this.managerSelectedLastStatusAge ||
               this.managerSelectedHasOpenQueries ||
               (this.managerSelectedCreatedDate && this.managerSelectedCreatedDate !== '<30');
    }
    
    get managerShowPagination() {
        return this.managerTotalPages > 1;
    }
    
    get managerIsPreviousDisabled() {
        return this.managerCurrentPage <= 1;
    }
    
    get managerIsNextDisabled() {
        if (this.managerCountExceedsThreshold) {
            return !this.managerApplicationHasMore;
        }
        return this.managerCurrentPage >= this.managerTotalPages;
    }
    
    get managerPaginationInfo() {
        if (this.managerTotalRecords === 0 && !this.managerCountExceedsThreshold) return 'No records';
        const start = (this.managerCurrentPage - 1) * this.pageSize + 1;
        const displayedCount = (this.managerDisplayedRecords && this.managerDisplayedRecords.length) || 0;
        const end = displayedCount > 0
            ? start + displayedCount - 1
            : Math.min(start + this.pageSize - 1, this.managerTotalRecords);
        const totalLabel = this.formatTotalRecordsLabel(this.managerTotalRecords, this.managerCountExceedsThreshold);
        return `Showing ${start} - ${end} of ${totalLabel} records`;
    }
    
    get managerRowNumberOffset() {
        return (this.managerCurrentPage - 1) * this.pageSize;
    }
    
    get managerPageInfo() {
        const totalPagesLabel = this.managerCountExceedsThreshold
            ? `${this.managerTotalPages}+`
            : `${this.managerTotalPages}`;
        return `${this.managerCurrentPage} / ${totalPagesLabel}`;
    }
    
    get selectedPageSize() {
        return String(this.pageSize);
    }
    
    get noEmployeeRecordsMessage() {
        if (this.isLoading) {
            return 'We are loading your data...';
        }
        return this.employeeHasFilters 
            ? 'No records match your filter criteria'
            : 'No application aging records found for you';
    }
    
    get noManagerRecordsMessage() {
        if (this.isLoading) {
            return 'We are loading your data...';
        }
        return this.managerHasFilters 
            ? 'No records match your filter criteria'
            : 'No application aging records found in your team';
    }
    
    // Application Column selection handlers
    openApplicationColumnSelector() {
        this.showApplicationColumnModal = true;
    }
    
    closeApplicationColumnSelector() {
        this.showApplicationColumnModal = false;
    }
    
    handleApplicationColumnSelectionChange(event) {
        this.selectedColumns = event.detail.value;
    }
    
    applyApplicationColumnSelection() {
        // Update available columns with current selection
        this.availableColumns = this.availableColumns.map(col => ({
            ...col,
            selected: this.selectedColumns.includes(col.value)
        }));
        
        // Update visible columns
        this.updateVisibleColumns();
        
        // Close modal
        this.showApplicationColumnModal = false;
    }
    
    get applicationColumnOptions() {
        return this.availableColumns.map(col => ({
            label: col.label,
            value: col.value
        }));
    }
    
    // Investigation Column selection handlers
    openInvestigationColumnSelector() {
        // Build available investigation columns on first open
        if (this.availableInvestigationColumns.length === 0) {
            this.buildAvailableInvestigationColumns();
        }
        this.showInvestigationColumnModal = true;
    }
    
    closeInvestigationColumnSelector() {
        this.showInvestigationColumnModal = false;
    }
    
    handleInvestigationColumnSelectionChange(event) {
        this.selectedInvestigationColumns = event.detail.value;
    }
    
    applyInvestigationColumnSelection() {
        // Update available investigation columns with current selection
        this.availableInvestigationColumns = this.availableInvestigationColumns.map(col => ({
            ...col,
            selected: this.selectedInvestigationColumns.includes(col.value)
        }));
        
        // Update visible investigation columns
        this.updateVisibleInvestigationColumns();
        
        // Close modal
        this.showInvestigationColumnModal = false;
    }
    
    get investigationColumnOptions() {
        return this.availableInvestigationColumns.map(col => ({
            label: col.label,
            value: col.value
        }));
    }
    
    // Getters for button visibility
    get showApplicationColumnsButton() {
        return this.activeTab === 'employee' || this.activeTab === 'manager';
    }
    
    get showInvestigationColumnsButton() {
        return this.activeTab === 'employeeInvestigation' || this.activeTab === 'managerInvestigation';
    }
    
    // Investigation getters
    get showEmployeeInvestigationTab() {
        return this.showInvestigations;
    }
    
    get showMyTeamInvestigationTab() {
        // Show "My Team Investigations" tab if:
        // 1. User has investigations access (showInvestigations), AND
        // 2. User is Admin OR Manager OR acting on behalf of someone (TODO: add when implemented)
        return this.showInvestigations && (this.isAdmin || this.isManager);
    }
    
    // Deprecated - kept for backwards compatibility
    get showManagerInvestigationTab() {
        return this.showMyTeamInvestigationTab;
    }
    
    // Query tab getters
    get showEmployeeQueryTab() {
        return true; // Always show employee queries tab
    }
    
    get showMyTeamQueryTab() {
        // Show "My Team Queries" tab if:
        // 1. User is Admin, OR
        // 2. User is Manager, OR
        // 3. User is acting on behalf of someone else (TODO: add when implemented)
        return this.isAdmin || this.isManager;
    }
    
    get employeeInvestigationHasRecords() {
        return this.employeeInvestigationFilteredRecords && this.employeeInvestigationFilteredRecords.length > 0;
    }
    
    get employeeInvestigationHasFilters() {
        return this.employeeInvestigationSelectedStatus || this.employeeInvestigationSelectedProduct || 
               this.employeeInvestigationSelectedRegion || this.employeeInvestigationSelectedInvestigationAge ||
               this.employeeInvestigationSelectedLastStatusAge;
    }
    
    get employeeInvestigationShowPagination() {
        return this.employeeInvestigationTotalPages > 1;
    }
    
    get employeeInvestigationIsPreviousDisabled() {
        return this.employeeInvestigationCurrentPage <= 1;
    }
    
    get employeeInvestigationIsNextDisabled() {
        if (this.employeeInvestigationCountExceedsThreshold) {
            return !this.employeeInvestigationHasMore;
        }
        return this.employeeInvestigationCurrentPage >= this.employeeInvestigationTotalPages;
    }
    
    get employeeInvestigationPaginationInfo() {
        if (this.employeeInvestigationTotalRecords === 0 && !this.employeeInvestigationCountExceedsThreshold) return 'No records';
        const start = (this.employeeInvestigationCurrentPage - 1) * this.pageSize + 1;
        const displayedCount = (this.employeeInvestigationDisplayedRecords && this.employeeInvestigationDisplayedRecords.length) || 0;
        const end = displayedCount > 0
            ? start + displayedCount - 1
            : Math.min(start + this.pageSize - 1, this.employeeInvestigationTotalRecords);
        const totalLabel = this.formatTotalRecordsLabel(this.employeeInvestigationTotalRecords, this.employeeInvestigationCountExceedsThreshold);
        return `Showing ${start} - ${end} of ${totalLabel} records`;
    }
    
    get employeeInvestigationRowNumberOffset() {
        return (this.employeeInvestigationCurrentPage - 1) * this.pageSize;
    }
    
    get employeeInvestigationPageInfo() {
        const totalPagesLabel = this.employeeInvestigationCountExceedsThreshold
            ? `${this.employeeInvestigationTotalPages}+`
            : `${this.employeeInvestigationTotalPages}`;
        return `${this.employeeInvestigationCurrentPage} / ${totalPagesLabel}`;
    }
    
    get noEmployeeInvestigationRecordsMessage() {
        if (this.isLoading) {
            return 'We are loading your data...';
        }
        return this.employeeInvestigationHasFilters 
            ? 'No investigations match your filter criteria'
            : 'No open investigations found for you';
    }
    
    get managerInvestigationHasRecords() {
        return this.managerInvestigationFilteredRecords && this.managerInvestigationFilteredRecords.length > 0;
    }
    
    get managerInvestigationHasFilters() {
        return this.managerInvestigationSelectedStatus || this.managerInvestigationSelectedManager || 
               this.managerInvestigationSelectedOwner || this.managerInvestigationSelectedProduct || 
               this.managerInvestigationSelectedRegion || this.managerInvestigationSelectedInvestigationAge ||
               this.managerInvestigationSelectedLastStatusAge;
    }
    
    get managerInvestigationShowPagination() {
        return this.managerInvestigationTotalPages > 1;
    }
    
    get managerInvestigationIsPreviousDisabled() {
        return this.managerInvestigationCurrentPage <= 1;
    }
    
    get managerInvestigationIsNextDisabled() {
        if (this.managerInvestigationCountExceedsThreshold) {
            return !this.managerInvestigationHasMore;
        }
        return this.managerInvestigationCurrentPage >= this.managerInvestigationTotalPages;
    }
    
    get managerInvestigationPaginationInfo() {
        if (this.managerInvestigationTotalRecords === 0 && !this.managerInvestigationCountExceedsThreshold) return 'No records';
        const start = (this.managerInvestigationCurrentPage - 1) * this.pageSize + 1;
        const displayedCount = (this.managerInvestigationDisplayedRecords && this.managerInvestigationDisplayedRecords.length) || 0;
        const end = displayedCount > 0
            ? start + displayedCount - 1
            : Math.min(start + this.pageSize - 1, this.managerInvestigationTotalRecords);
        const totalLabel = this.formatTotalRecordsLabel(this.managerInvestigationTotalRecords, this.managerInvestigationCountExceedsThreshold);
        return `Showing ${start} - ${end} of ${totalLabel} records`;
    }
    
    get managerInvestigationRowNumberOffset() {
        return (this.managerInvestigationCurrentPage - 1) * this.pageSize;
    }
    
    get managerInvestigationPageInfo() {
        const totalPagesLabel = this.managerInvestigationCountExceedsThreshold
            ? `${this.managerInvestigationTotalPages}+`
            : `${this.managerInvestigationTotalPages}`;
        return `${this.managerInvestigationCurrentPage} / ${totalPagesLabel}`;
    }
    
    // Query row number offsets
    get employeeQueryRowNumberOffset() {
        return (this.employeeQueryCurrentPage - 1) * this.pageSize;
    }
    
    get managerQueryRowNumberOffset() {
        return (this.managerQueryCurrentPage - 1) * this.pageSize;
    }
    
    get noManagerInvestigationRecordsMessage() {
        if (this.isLoading) {
            return 'We are loading your data...';
        }
        return this.managerInvestigationHasFilters 
            ? 'No investigations match your filter criteria'
            : 'No open investigations found in your team';
    }
    
    // Query getters
    get employeeQueryHasRecords() {
        return this.employeeQueryFilteredRecords && this.employeeQueryFilteredRecords.length > 0;
    }
    
    get employeeQueryHasFilters() {
        return this.employeeQuerySelectedStatus || this.employeeQuerySelectedPriority || 
               this.employeeQuerySelectedType || this.employeeQuerySelectedAge;
    }
    
    get noEmployeeQueryRecordsMessage() {
        if (this.isLoading) {
            return 'We are loading your data...';
        }
        return this.employeeQueryHasFilters 
            ? 'No queries match your filter criteria'
            : 'No open queries found';
    }
    
    get managerQueryHasRecords() {
        return this.managerQueryFilteredRecords && this.managerQueryFilteredRecords.length > 0;
    }

    get employeeQueryIsPreviousDisabled() {
        return this.employeeQueryCurrentPage <= 1;
    }

    get employeeQueryIsNextDisabled() {
        return !this.employeeQueryHasMore;
    }

    get managerQueryIsPreviousDisabled() {
        return this.managerQueryCurrentPage <= 1;
    }

    get managerQueryIsNextDisabled() {
        return !this.managerQueryHasMore;
    }
    
    get managerQueryHasFilters() {
        return this.managerQuerySelectedStatus || this.managerQuerySelectedManager || 
               this.managerQuerySelectedOwner || this.managerQuerySelectedPriority || 
               this.managerQuerySelectedType || this.managerQuerySelectedAge;
    }
    
    get noManagerQueryRecordsMessage() {
        if (this.isLoading) {
            return 'We are loading your data...';
        }
        return this.managerQueryHasFilters 
            ? 'No queries match your filter criteria'
            : 'No open queries found in your team';
    }
    
    // Investigation Filter Handlers - Employee
    handleEmployeeInvestigationStatusChange(event) {
        this.employeeInvestigationSelectedStatus = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleEmployeeInvestigationProductChange(event) {
        this.employeeInvestigationSelectedProduct = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleEmployeeInvestigationRegionChange(event) {
        this.employeeInvestigationSelectedRegion = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleEmployeeInvestigationInvestigationAgeChange(event) {
        this.employeeInvestigationSelectedInvestigationAge = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleEmployeeInvestigationLastStatusAgeChange(event) {
        this.employeeInvestigationSelectedLastStatusAge = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    clearEmployeeInvestigationFilters() {
        this.employeeInvestigationSelectedStatus = '';
        this.employeeInvestigationSelectedProduct = '';
        this.employeeInvestigationSelectedRegion = '';
        this.employeeInvestigationSelectedInvestigationAge = '';
        this.employeeInvestigationSelectedLastStatusAge = '';
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    // Investigation Filter Handlers - Manager
    handleManagerInvestigationStatusChange(event) {
        this.managerInvestigationSelectedStatus = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleManagerInvestigationManagerChange(event) {
        this.managerInvestigationSelectedManager = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleManagerInvestigationOwnerChange(event) {
        this.managerInvestigationSelectedOwner = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleManagerInvestigationProductChange(event) {
        this.managerInvestigationSelectedProduct = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleManagerInvestigationRegionChange(event) {
        this.managerInvestigationSelectedRegion = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleManagerInvestigationInvestigationAgeChange(event) {
        this.managerInvestigationSelectedInvestigationAge = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    handleManagerInvestigationLastStatusAgeChange(event) {
        this.managerInvestigationSelectedLastStatusAge = event.detail.value;
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    clearManagerInvestigationFilters() {
        this.managerInvestigationSelectedStatus = '';
        this.managerInvestigationSelectedManager = '';
        this.managerInvestigationSelectedOwner = '';
        this.managerInvestigationSelectedProduct = '';
        this.managerInvestigationSelectedRegion = '';
        this.managerInvestigationSelectedInvestigationAge = '';
        this.managerInvestigationSelectedLastStatusAge = '';
        this.investigationDataLoaded = false;
        this.loadInvestigationData();
    }
    
    // ============================================================
    // Investigation pagination handlers (see Application handlers for cursor model)
    // ============================================================

    _mapInvestigationRecords(records) {
        return records.map(record => ({
            ...record,
            investigationUrl: `/${record.investigationId}`,
            applicationUrl: record.applicationId ? `/${record.applicationId}` : null,
            agingColorClass: this.getAgingColorClass(record.agingInDays)
        }));
    }

    async handleEmployeeInvestigationFirst() {
        if (this.employeeInvestigationCurrentPage <= 1) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllInvestigationPages('employeeInvestigation', null, null, 'forward');
            const records = chunk?.records || [];
            this.employeeInvestigationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeInvestigationNextCursorId = chunk?.nextCursorId || null;
            this.employeeInvestigationHasMore = chunk?.hasMore === true;
            this.employeeInvestigationCurrentPage = 1;
            this.employeeInvestigationRecords = [...records];
            this.employeeInvestigationFilteredRecords = this._mapInvestigationRecords(records);
            this.employeeInvestigationDisplayedRecords = this.employeeInvestigationFilteredRecords;
            this.employeeInvestigationTotalRecords = this.resolveTotalRecords(chunk?.totalCount, this.employeeInvestigationTotalRecords);
            this.employeeInvestigationCountExceedsThreshold = this.resolveCountExceedsThreshold(chunk, this.employeeInvestigationCountExceedsThreshold);
            this.employeeInvestigationTotalPages = this.resolveTotalPages(this.employeeInvestigationTotalRecords);
        } finally {
            this.isLoading = false;
        }
    }

    async handleEmployeeInvestigationPrevious() {
        if (this.employeeInvestigationCurrentPage <= 1) return;
        if (!this.employeeInvestigationRecords || this.employeeInvestigationRecords.length === 0) return;
        const firstOnPage = this.employeeInvestigationRecords[0];
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllInvestigationPages(
                'employeeInvestigation',
                firstOnPage.tatCreatedDate,
                firstOnPage.tatId,
                'backward'
            );
            const records = chunk?.records || [];
            this.employeeInvestigationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeInvestigationNextCursorId = chunk?.nextCursorId || null;
            this.employeeInvestigationHasMore = true;
            this.employeeInvestigationCurrentPage = Math.max(1, this.employeeInvestigationCurrentPage - 1);
            this.employeeInvestigationRecords = [...records];
            this.employeeInvestigationFilteredRecords = this._mapInvestigationRecords(records);
            this.employeeInvestigationDisplayedRecords = this.employeeInvestigationFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleEmployeeInvestigationNext() {
        if (!this.employeeInvestigationHasMore || !this.employeeInvestigationNextCursorId) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllInvestigationPages(
                'employeeInvestigation',
                this.employeeInvestigationNextCursorCreatedDate,
                this.employeeInvestigationNextCursorId,
                'forward'
            );
            const records = chunk?.records || [];
            this.employeeInvestigationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeInvestigationNextCursorId = chunk?.nextCursorId || null;
            this.employeeInvestigationHasMore = chunk?.hasMore === true;
            this.employeeInvestigationCurrentPage += 1;
            this.employeeInvestigationRecords = [...records];
            this.employeeInvestigationFilteredRecords = this._mapInvestigationRecords(records);
            this.employeeInvestigationDisplayedRecords = this.employeeInvestigationFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleEmployeeInvestigationLast() {
        if (this.employeeInvestigationTotalPages <= 1 && !this.employeeInvestigationCountExceedsThreshold) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllInvestigationPages('employeeInvestigation', null, null, 'backward');
            const records = chunk?.records || [];
            this.employeeInvestigationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeInvestigationNextCursorId = chunk?.nextCursorId || null;
            this.employeeInvestigationHasMore = false;
            this.employeeInvestigationCurrentPage = Math.max(this.employeeInvestigationTotalPages || 1, 1);
            this.employeeInvestigationRecords = [...records];
            this.employeeInvestigationFilteredRecords = this._mapInvestigationRecords(records);
            this.employeeInvestigationDisplayedRecords = this.employeeInvestigationFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleManagerInvestigationFirst() {
        if (this.managerInvestigationCurrentPage <= 1) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllInvestigationPages('managerInvestigation', null, null, 'forward');
            const records = chunk?.records || [];
            this.managerInvestigationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerInvestigationNextCursorId = chunk?.nextCursorId || null;
            this.managerInvestigationHasMore = chunk?.hasMore === true;
            this.managerInvestigationCurrentPage = 1;
            this.managerInvestigationRecords = [...records];
            this.managerInvestigationFilteredRecords = this._mapInvestigationRecords(records);
            this.managerInvestigationDisplayedRecords = this.managerInvestigationFilteredRecords;
            this.managerInvestigationTotalRecords = this.resolveTotalRecords(chunk?.totalCount, this.managerInvestigationTotalRecords);
            this.managerInvestigationCountExceedsThreshold = this.resolveCountExceedsThreshold(chunk, this.managerInvestigationCountExceedsThreshold);
            this.managerInvestigationTotalPages = this.resolveTotalPages(this.managerInvestigationTotalRecords);
        } finally {
            this.isLoading = false;
        }
    }

    async handleManagerInvestigationPrevious() {
        if (this.managerInvestigationCurrentPage <= 1) return;
        if (!this.managerInvestigationRecords || this.managerInvestigationRecords.length === 0) return;
        const firstOnPage = this.managerInvestigationRecords[0];
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllInvestigationPages(
                'managerInvestigation',
                firstOnPage.tatCreatedDate,
                firstOnPage.tatId,
                'backward'
            );
            const records = chunk?.records || [];
            this.managerInvestigationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerInvestigationNextCursorId = chunk?.nextCursorId || null;
            this.managerInvestigationHasMore = true;
            this.managerInvestigationCurrentPage = Math.max(1, this.managerInvestigationCurrentPage - 1);
            this.managerInvestigationRecords = [...records];
            this.managerInvestigationFilteredRecords = this._mapInvestigationRecords(records);
            this.managerInvestigationDisplayedRecords = this.managerInvestigationFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleManagerInvestigationNext() {
        if (!this.managerInvestigationHasMore || !this.managerInvestigationNextCursorId) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllInvestigationPages(
                'managerInvestigation',
                this.managerInvestigationNextCursorCreatedDate,
                this.managerInvestigationNextCursorId,
                'forward'
            );
            const records = chunk?.records || [];
            this.managerInvestigationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerInvestigationNextCursorId = chunk?.nextCursorId || null;
            this.managerInvestigationHasMore = chunk?.hasMore === true;
            this.managerInvestigationCurrentPage += 1;
            this.managerInvestigationRecords = [...records];
            this.managerInvestigationFilteredRecords = this._mapInvestigationRecords(records);
            this.managerInvestigationDisplayedRecords = this.managerInvestigationFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleManagerInvestigationLast() {
        if (this.managerInvestigationTotalPages <= 1 && !this.managerInvestigationCountExceedsThreshold) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllInvestigationPages('managerInvestigation', null, null, 'backward');
            const records = chunk?.records || [];
            this.managerInvestigationNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerInvestigationNextCursorId = chunk?.nextCursorId || null;
            this.managerInvestigationHasMore = false;
            this.managerInvestigationCurrentPage = Math.max(this.managerInvestigationTotalPages || 1, 1);
            this.managerInvestigationRecords = [...records];
            this.managerInvestigationFilteredRecords = this._mapInvestigationRecords(records);
            this.managerInvestigationDisplayedRecords = this.managerInvestigationFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }
    
    updateEmployeeInvestigationDisplayedRecords() {
        const start = (this.employeeInvestigationCurrentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.employeeInvestigationDisplayedRecords = this.employeeInvestigationFilteredRecords.slice(start, end);
    }
    
    updateManagerInvestigationDisplayedRecords() {
        const start = (this.managerInvestigationCurrentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.managerInvestigationDisplayedRecords = this.managerInvestigationFilteredRecords.slice(start, end);
    }
    
    // Build investigation filter options (called when investigation data is loaded)
    buildInvestigationFilterOptions() {
        // DO NOT overwrite productOptions here - it's already set from getAllProducts() Apex call
        // Product options should be shared across all tabs (applications, investigations, queries)
        // Only build investigation-specific dependent filters (status, region, etc.)
        
        // Build dependent filter options for investigations (status, region, etc.)
        this.buildEmployeeInvestigationDependentFilters();
        if (this.isManager) {
            this.buildManagerInvestigationDependentFilters();
        }
    }
    
    // Build investigation filter options
    buildEmployeeInvestigationDependentFilters() {
        let filteredForStatus = this.employeeInvestigationRecords;
        if (this.employeeInvestigationSelectedProduct) {
            filteredForStatus = filteredForStatus.filter(r => r.product === this.employeeInvestigationSelectedProduct);
        }
        
        const statuses = new Set();
        filteredForStatus.forEach(record => {
            if (record.investigationStatus) statuses.add(record.investigationStatus);
        });
        
        this.statusOptions = [
            { label: '-- All Statuses --', value: '' },
            ...Array.from(statuses).sort().map(status => ({ label: status, value: status }))
        ];
        
        // Build region options based on filtered records
        let filteredForRegion = filteredForStatus;
        if (this.employeeInvestigationSelectedStatus) {
            filteredForRegion = filteredForRegion.filter(r => r.investigationStatus === this.employeeInvestigationSelectedStatus);
        }
    }
    
    buildManagerInvestigationDependentFilters() {
        // Filter records based on current product selection
        let filteredForStatus = this.managerInvestigationRecords;
        
        if (this.managerInvestigationSelectedProduct) {
            filteredForStatus = filteredForStatus.filter(r => r.product === this.managerInvestigationSelectedProduct);
        }
        
        // Build status options
        const statuses = new Set();
        filteredForStatus.forEach(record => {
            if (record.investigationStatus) statuses.add(record.investigationStatus);
        });
        
        this.statusOptions = [
            { label: '-- All Statuses --', value: '' },
            ...Array.from(statuses).sort().map(status => ({ label: status, value: status }))
        ];
        
        // Filter records further for manager options
        let filteredForManager = filteredForStatus;
        if (this.managerInvestigationSelectedStatus) {
            filteredForManager = filteredForManager.filter(r => r.investigationStatus === this.managerInvestigationSelectedStatus);
        }
        
        // Build manager options
        const managers = new Set();
        filteredForManager.forEach(record => {
            if (record.ownerManagerName) managers.add(record.ownerManagerName);
        });
        
        this.managerOptions = [
            { label: '-- All Managers --', value: '' },
            ...Array.from(managers).sort().map(manager => ({ label: manager, value: manager }))
        ];
        
        // Filter records further for owner options
        let filteredForOwner = filteredForManager;
        if (this.managerInvestigationSelectedManager) {
            filteredForOwner = filteredForOwner.filter(r => r.ownerManagerName === this.managerInvestigationSelectedManager);
        }
        
        // Build owner options
        const owners = new Set();
        filteredForOwner.forEach(record => {
            if (record.ownerName) owners.add(record.ownerName);
        });
        
        this.ownerOptions = [
            { label: '-- All Owners --', value: '' },
            ...Array.from(owners).sort().map(owner => ({ label: owner, value: owner }))
        ];
        
        // Filter records further for region options
        let filteredForRegion = filteredForOwner;
        if (this.managerInvestigationSelectedOwner) {
            filteredForRegion = filteredForRegion.filter(r => r.ownerName === this.managerInvestigationSelectedOwner);
        }
    }
    
    // Build query filter options (called when query data is loaded)
    buildQueryFilterOptions() {
        // Build Status options from Query records
        const employeeStatuses = new Set();
        this.employeeQueryRecords.forEach(record => {
            if (record.status) employeeStatuses.add(record.status);
        });
        
        const managerStatuses = new Set();
        if (this.isManager) {
            this.managerQueryRecords.forEach(record => {
                if (record.status) managerStatuses.add(record.status);
            });
        }
        
        this.queryStatusOptions = [
            { label: '-- All Statuses --', value: '' },
            ...Array.from(this.isManager ? managerStatuses : employeeStatuses).sort().map(status => ({ label: status, value: status }))
        ];
        
        // Build Priority options
        const employeePriorities = new Set();
        this.employeeQueryRecords.forEach(record => {
            if (record.priority) employeePriorities.add(record.priority);
        });
        
        const managerPriorities = new Set();
        if (this.isManager) {
            this.managerQueryRecords.forEach(record => {
                if (record.priority) managerPriorities.add(record.priority);
            });
        }
        
        this.queryPriorityOptions = [
            { label: '-- All Priorities --', value: '' },
            ...Array.from(this.isManager ? managerPriorities : employeePriorities).sort().map(priority => ({ label: priority, value: priority }))
        ];
        
        // Build Type options
        const employeeTypes = new Set();
        this.employeeQueryRecords.forEach(record => {
            if (record.queryType) employeeTypes.add(record.queryType);
        });
        
        const managerTypes = new Set();
        if (this.isManager) {
            this.managerQueryRecords.forEach(record => {
                if (record.queryType) managerTypes.add(record.queryType);
            });
        }
        
        this.queryTypeOptions = [
            { label: '-- All Types --', value: '' },
            ...Array.from(this.isManager ? managerTypes : employeeTypes).sort().map(type => ({ label: type, value: type }))
        ];
        
        // Build Manager options for manager view
        if (this.isManager) {
            const managers = new Set();
            this.managerQueryRecords.forEach(record => {
                if (record.ownerManagerName) managers.add(record.ownerManagerName);
            });
            
            this.managerOptions = [
                { label: '-- All Managers --', value: '' },
                ...Array.from(managers).sort().map(manager => ({ label: manager, value: manager }))
            ];
            
            // Build Owner options for manager view
            const owners = new Set();
            this.managerQueryRecords.forEach(record => {
                if (record.ownerName) owners.add(record.ownerName);
            });
            
            this.ownerOptions = [
                { label: '-- All Owners --', value: '' },
                ...Array.from(owners).sort().map(owner => ({ label: owner, value: owner }))
            ];
        }
    }
    
    // Employee Query Filter Handlers
    handleEmployeeQueryStatusChange(event) {
        this.employeeQuerySelectedStatus = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    handleEmployeeQueryPriorityChange(event) {
        this.employeeQuerySelectedPriority = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    handleEmployeeQueryTypeChange(event) {
        this.employeeQuerySelectedType = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    handleEmployeeQueryAgeChange(event) {
        this.employeeQuerySelectedAge = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    clearEmployeeQueryFilters() {
        this.employeeQuerySelectedStatus = '';
        this.employeeQuerySelectedPriority = '';
        this.employeeQuerySelectedType = '';
        this.employeeQuerySelectedAge = '';
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    // Manager Query Filter Handlers
    handleManagerQueryStatusChange(event) {
        this.managerQuerySelectedStatus = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    handleManagerQueryManagerChange(event) {
        this.managerQuerySelectedManager = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    handleManagerQueryOwnerChange(event) {
        this.managerQuerySelectedOwner = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    handleManagerQueryPriorityChange(event) {
        this.managerQuerySelectedPriority = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    handleManagerQueryTypeChange(event) {
        this.managerQuerySelectedType = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    handleManagerQueryAgeChange(event) {
        this.managerQuerySelectedAge = event.detail.value;
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    clearManagerQueryFilters() {
        this.managerQuerySelectedStatus = '';
        this.managerQuerySelectedManager = '';
        this.managerQuerySelectedOwner = '';
        this.managerQuerySelectedPriority = '';
        this.managerQuerySelectedType = '';
        this.managerQuerySelectedAge = '';
        this.queryDataLoaded = false;
        this.loadQueryData();
    }
    
    // Pagination Methods for Employee Query
    updateEmployeeQueryDisplayedRecords() {
        const start = (this.employeeQueryCurrentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.employeeQueryDisplayedRecords = this.employeeQueryFilteredRecords.slice(start, end);
    }
    
    // ============================================================
    // Query pagination handlers (see Application handlers for cursor model)
    // ============================================================

    async handleEmployeeQueryFirst() {
        if (this.employeeQueryCurrentPage <= 1) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllQueryPages('employeeQuery', null, null, 'forward');
            const records = chunk?.records || [];
            this.employeeQueryNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeQueryNextCursorId = chunk?.nextCursorId || null;
            this.employeeQueryHasMore = chunk?.hasMore === true;
            this.employeeQueryCurrentPage = 1;
            this.employeeQueryRecords = [...records];
            this.employeeQueryFilteredRecords = [...records];
            this.employeeQueryDisplayedRecords = this.employeeQueryFilteredRecords;
            this.employeeQueryTotalRecords = this.resolveTotalRecords(chunk?.totalCount, this.employeeQueryTotalRecords);
            this.employeeQueryCountExceedsThreshold = this.resolveCountExceedsThreshold(chunk, this.employeeQueryCountExceedsThreshold);
            this.employeeQueryTotalPages = this.resolveTotalPages(this.employeeQueryTotalRecords);
        } finally {
            this.isLoading = false;
        }
    }

    async handleEmployeeQueryPrevious() {
        if (this.employeeQueryCurrentPage <= 1) return;
        if (!this.employeeQueryRecords || this.employeeQueryRecords.length === 0) return;
        const firstOnPage = this.employeeQueryRecords[0];
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllQueryPages(
                'employeeQuery',
                firstOnPage.createdDate,
                firstOnPage.queryId,
                'backward'
            );
            const records = chunk?.records || [];
            this.employeeQueryNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeQueryNextCursorId = chunk?.nextCursorId || null;
            this.employeeQueryHasMore = true;
            this.employeeQueryCurrentPage = Math.max(1, this.employeeQueryCurrentPage - 1);
            this.employeeQueryRecords = [...records];
            this.employeeQueryFilteredRecords = [...records];
            this.employeeQueryDisplayedRecords = this.employeeQueryFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleEmployeeQueryNext() {
        if (!this.employeeQueryHasMore || !this.employeeQueryNextCursorId) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllQueryPages(
                'employeeQuery',
                this.employeeQueryNextCursorCreatedDate,
                this.employeeQueryNextCursorId,
                'forward'
            );
            const records = chunk?.records || [];
            this.employeeQueryNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeQueryNextCursorId = chunk?.nextCursorId || null;
            this.employeeQueryHasMore = chunk?.hasMore === true;
            this.employeeQueryCurrentPage += 1;
            this.employeeQueryRecords = [...records];
            this.employeeQueryFilteredRecords = [...records];
            this.employeeQueryDisplayedRecords = this.employeeQueryFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleEmployeeQueryLast() {
        if (this.employeeQueryTotalPages <= 1 && !this.employeeQueryCountExceedsThreshold) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllQueryPages('employeeQuery', null, null, 'backward');
            const records = chunk?.records || [];
            this.employeeQueryNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.employeeQueryNextCursorId = chunk?.nextCursorId || null;
            this.employeeQueryHasMore = false;
            this.employeeQueryCurrentPage = Math.max(this.employeeQueryTotalPages || 1, 1);
            this.employeeQueryRecords = [...records];
            this.employeeQueryFilteredRecords = [...records];
            this.employeeQueryDisplayedRecords = this.employeeQueryFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    // Pagination Methods for Manager Query
    updateManagerQueryDisplayedRecords() {
        const start = (this.managerQueryCurrentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.managerQueryDisplayedRecords = this.managerQueryFilteredRecords.slice(start, end);
    }

    async handleManagerQueryFirst() {
        if (this.managerQueryCurrentPage <= 1) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllQueryPages('managerQuery', null, null, 'forward');
            const records = chunk?.records || [];
            this.managerQueryNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerQueryNextCursorId = chunk?.nextCursorId || null;
            this.managerQueryHasMore = chunk?.hasMore === true;
            this.managerQueryCurrentPage = 1;
            this.managerQueryRecords = [...records];
            this.managerQueryFilteredRecords = [...records];
            this.managerQueryDisplayedRecords = this.managerQueryFilteredRecords;
            this.managerQueryTotalRecords = this.resolveTotalRecords(chunk?.totalCount, this.managerQueryTotalRecords);
            this.managerQueryCountExceedsThreshold = this.resolveCountExceedsThreshold(chunk, this.managerQueryCountExceedsThreshold);
            this.managerQueryTotalPages = this.resolveTotalPages(this.managerQueryTotalRecords);
        } finally {
            this.isLoading = false;
        }
    }

    async handleManagerQueryPrevious() {
        if (this.managerQueryCurrentPage <= 1) return;
        if (!this.managerQueryRecords || this.managerQueryRecords.length === 0) return;
        const firstOnPage = this.managerQueryRecords[0];
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllQueryPages(
                'managerQuery',
                firstOnPage.createdDate,
                firstOnPage.queryId,
                'backward'
            );
            const records = chunk?.records || [];
            this.managerQueryNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerQueryNextCursorId = chunk?.nextCursorId || null;
            this.managerQueryHasMore = true;
            this.managerQueryCurrentPage = Math.max(1, this.managerQueryCurrentPage - 1);
            this.managerQueryRecords = [...records];
            this.managerQueryFilteredRecords = [...records];
            this.managerQueryDisplayedRecords = this.managerQueryFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleManagerQueryNext() {
        if (!this.managerQueryHasMore || !this.managerQueryNextCursorId) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllQueryPages(
                'managerQuery',
                this.managerQueryNextCursorCreatedDate,
                this.managerQueryNextCursorId,
                'forward'
            );
            const records = chunk?.records || [];
            this.managerQueryNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerQueryNextCursorId = chunk?.nextCursorId || null;
            this.managerQueryHasMore = chunk?.hasMore === true;
            this.managerQueryCurrentPage += 1;
            this.managerQueryRecords = [...records];
            this.managerQueryFilteredRecords = [...records];
            this.managerQueryDisplayedRecords = this.managerQueryFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }

    async handleManagerQueryLast() {
        if (this.managerQueryTotalPages <= 1 && !this.managerQueryCountExceedsThreshold) return;
        this.isLoading = true;
        try {
            const chunk = await this.fetchAllQueryPages('managerQuery', null, null, 'backward');
            const records = chunk?.records || [];
            this.managerQueryNextCursorCreatedDate = chunk?.nextCursorCreatedDate || null;
            this.managerQueryNextCursorId = chunk?.nextCursorId || null;
            this.managerQueryHasMore = false;
            this.managerQueryCurrentPage = Math.max(this.managerQueryTotalPages || 1, 1);
            this.managerQueryRecords = [...records];
            this.managerQueryFilteredRecords = [...records];
            this.managerQueryDisplayedRecords = this.managerQueryFilteredRecords;
        } finally {
            this.isLoading = false;
        }
    }
    
    // ==========================================
    // SORTING HANDLERS
    // ==========================================
    
    handleEmployeeApplicationSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.employeeApplicationSortedBy = sortedBy;
        this.employeeApplicationSortDirection = sortDirection;
        this.sortData('employeeApplication');
        this.employeeCurrentPage = 1; // Reset to page 1
    }

    handleManagerApplicationSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.managerApplicationSortedBy = sortedBy;
        this.managerApplicationSortDirection = sortDirection;
        this.sortData('managerApplication');
        this.managerCurrentPage = 1; // Reset to page 1
    }

    handleEmployeeInvestigationSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.employeeInvestigationSortedBy = sortedBy;
        this.employeeInvestigationSortDirection = sortDirection;
        this.sortData('employeeInvestigation');
        this.employeeInvestigationCurrentPage = 1; // Reset to page 1
    }

    handleManagerInvestigationSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.managerInvestigationSortedBy = sortedBy;
        this.managerInvestigationSortDirection = sortDirection;
        this.sortData('managerInvestigation');
        this.managerInvestigationCurrentPage = 1; // Reset to page 1
    }

    handleEmployeeQuerySort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.employeeQuerySortedBy = sortedBy;
        this.employeeQuerySortDirection = sortDirection;
        this.sortData('employeeQuery');
        this.employeeQueryCurrentPage = 1; // Reset to page 1
    }

    handleManagerQuerySort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.managerQuerySortedBy = sortedBy;
        this.managerQuerySortDirection = sortDirection;
        this.sortData('managerQuery');
        this.managerQueryCurrentPage = 1; // Reset to page 1
    }

    // Generic sort function for all data types
    sortData(dataType) {
        let dataArray, sortedBy, sortDirection;
        
        // Determine which data array to sort
        switch(dataType) {
            case 'employeeApplication':
                dataArray = this.employeeFilteredRecords;
                sortedBy = this.employeeApplicationSortedBy;
                sortDirection = this.employeeApplicationSortDirection;
                break;
            case 'managerApplication':
                dataArray = this.managerFilteredRecords;
                sortedBy = this.managerApplicationSortedBy;
                sortDirection = this.managerApplicationSortDirection;
                break;
            case 'employeeInvestigation':
                dataArray = this.employeeInvestigationFilteredRecords;
                sortedBy = this.employeeInvestigationSortedBy;
                sortDirection = this.employeeInvestigationSortDirection;
                break;
            case 'managerInvestigation':
                dataArray = this.managerInvestigationFilteredRecords;
                sortedBy = this.managerInvestigationSortedBy;
                sortDirection = this.managerInvestigationSortDirection;
                break;
            case 'employeeQuery':
                dataArray = this.employeeQueryFilteredRecords;
                sortedBy = this.employeeQuerySortedBy;
                sortDirection = this.employeeQuerySortDirection;
                break;
            case 'managerQuery':
                dataArray = this.managerQueryFilteredRecords;
                sortedBy = this.managerQuerySortedBy;
                sortDirection = this.managerQuerySortDirection;
                break;
            default:
                return;
        }
        
        // Clone array to avoid mutating original
        let sortedData = [...dataArray];
        
        // Determine sort order multiplier
        const reverse = sortDirection === 'asc' ? 1 : -1;
        
        // Sort the data
        sortedData.sort((a, b) => {
            let aVal = a[sortedBy] || '';
            let bVal = b[sortedBy] || '';
            
            // Handle null/undefined
            if (aVal === null || aVal === undefined) aVal = '';
            if (bVal === null || bVal === undefined) bVal = '';
            
            // Handle numbers
            if (typeof aVal === 'number' && typeof bVal === 'number') {
                return (aVal - bVal) * reverse;
            }
            
            // Handle strings (case-insensitive)
            aVal = String(aVal).toLowerCase();
            bVal = String(bVal).toLowerCase();
            
            if (aVal < bVal) return -1 * reverse;
            if (aVal > bVal) return 1 * reverse;
            return 0;
        });
        
        // Update the filtered records array and refresh displayed records
        switch(dataType) {
            case 'employeeApplication':
                this.employeeFilteredRecords = sortedData;
                this.updateEmployeeDisplayedRecords();
                break;
            case 'managerApplication':
                this.managerFilteredRecords = sortedData;
                this.updateManagerDisplayedRecords();
                break;
            case 'employeeInvestigation':
                this.employeeInvestigationFilteredRecords = sortedData;
                this.updateEmployeeInvestigationDisplayedRecords();
                break;
            case 'managerInvestigation':
                this.managerInvestigationFilteredRecords = sortedData;
                this.updateManagerInvestigationDisplayedRecords();
                break;
            case 'employeeQuery':
                this.employeeQueryFilteredRecords = sortedData;
                this.updateEmployeeQueryDisplayedRecords();
                break;
            case 'managerQuery':
                this.managerQueryFilteredRecords = sortedData;
                this.updateManagerQueryDisplayedRecords();
                break;
        }
    }
    
    // Getters for Query Pagination
    get employeeQueryPageInfo() {
        const totalPagesLabel = this.employeeQueryCountExceedsThreshold
            ? `${this.employeeQueryTotalPages}+`
            : `${this.employeeQueryTotalPages}`;
        return `${this.employeeQueryCurrentPage} / ${totalPagesLabel}`;
    }
    
    get managerQueryPageInfo() {
        const totalPagesLabel = this.managerQueryCountExceedsThreshold
            ? `${this.managerQueryTotalPages}+`
            : `${this.managerQueryTotalPages}`;
        return `${this.managerQueryCurrentPage} / ${totalPagesLabel}`;
    }
}