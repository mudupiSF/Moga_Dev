import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDashboardConfigurations from '@salesforce/apex/OverallLoanDashboardController.getDashboardConfigurations';
import getDashboardData from '@salesforce/apex/OverallLoanDashboardController.getData';

export default class OverallLoanDashboard extends NavigationMixin(LightningElement) {
    @api widgetTab;
    
    dashboardConfigs = [];
    dashboardDataMap = {}; 
    error;
    isLoading = true;
    
    @wire(getDashboardConfigurations, { widgetTab: '$widgetTab' })
    wiredConfigurations({ error, data }) {
        if (data) {
            this.dashboardConfigs = data;
            this.error = undefined;
            // Fetch data for each configuration
            this.fetchAllDashboardData(data);
        }
        else if (error) {
            this.error = error;
            this.dashboardConfigs = [];
            this.isLoading = false;
        }
    }

    fetchAllDashboardData(configs) {
        if (!configs || configs.length === 0) {
            this.isLoading = false;
            return;
        }

        const dataPromises = configs.map(config => {
            return getDashboardData({ soql: config.soql })
                .then(result => {
                    return {
                        configId: config.id,
                        data: result.data || [],
                        error: null
                    };
                })
                .catch(error => {
                    return {
                        configId: config.id,
                        data: [],
                        error: error
                    };
                });
        });

        Promise.all(dataPromises)
            .then(results => {
                // Build map of config ID to data
                const dataMap = {};
                results.forEach(result => {
                    dataMap[result.configId] = {
                        data: result.data,
                        error: result.error
                    };
                });
                this.dashboardDataMap = dataMap;
                this.isLoading = false;
            })
            .catch(() => {
                this.isLoading = false;
            });
    }

    get hasConfigurations() {
        return this.dashboardConfigs && this.dashboardConfigs.length > 0;
    }

    get dashboardsWithData() {
        return this.dashboardConfigs.map(config => {
            const dataInfo = this.dashboardDataMap[config.id] || { data: [], error: null };
            return {
                ...config,
                data: dataInfo.data,
                hasData: dataInfo.data && dataInfo.data.length > 0,
                hasError: !!dataInfo.error,
                reportUrl: config.reportId ? `/${config.reportId}` : '#',
                showReportLink: config.reportId && config.reportLabel,
                colorClass: this.getColorClass(config.color),
                debugData: config.id,
                // Store navigation-related fields
                queryType: config.queryType,
                sObjectType: config.sObjectType,
                developerName: config.developerName
            };
        });
    }

    getColorClass(color) {
        switch(color) {
            case 'Green':
                return 'slds-text-color_success';
            case 'Yellow':
                return 'color-yellow';
            case 'Amber':
                return 'color-amber';
            case 'Red':
                return 'slds-text-color_error';
            default:
                return '';
        }
    }

    handleNavigateToReport(event) {
        event.preventDefault();
        const reportId = event.currentTarget.dataset.reportId;
        const queryType = event.currentTarget.dataset.queryType;
        const sObjectType = event.currentTarget.dataset.sobjectType;
        const developerName = event.currentTarget.dataset.developerName;
        
        // Detect if we're in a Community/Experience Site
        const isCommunity = window.location.pathname.includes('/s/');
        
        // Check if QueryType is Report
        if (queryType === 'Report') {
            // Navigate to Report using standard__recordPage
            if (reportId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: reportId,
                        objectApiName: 'Report',
                        actionName: 'view'
                    }
                });
            }
        }
        else {
            // Navigate to List View
            if (!sObjectType) {
                return;
            }
            if (isCommunity) {
                // COMMUNITY: Construct custom URL for community navigation
                // URL Pattern: /s/{lowercaseSObjectName}/{sObjectName}/Default?{sObjectName}-filterId={developerName}
                const baseUrl = window.location.origin + window.location.pathname.split('/s/')[0];
                const sObjectLower = sObjectType.toLowerCase().replace(/__c/g, '');
                const communityUrl = `${baseUrl}/s/${sObjectLower}/${sObjectType}/Default?${sObjectType}-filterId=${developerName}`;
                window.location.href = communityUrl;
            }
            else {
                // STANDARD SALESFORCE: Use NavigationMixin for list view
                const navigationPayload = {
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: sObjectType,
                        actionName: 'list'
                    }
                };
                
                // Add filterName to state if provided
                if (developerName) {
                    navigationPayload.state = {
                        filterName: developerName
                    };
                }
                this[NavigationMixin.Navigate](navigationPayload);
            }
        }
    }

    get noConfigurationMessage() {
        return 'No active dashboard configurations found for your persona. Please create Dashboard Configuration records.';
    }
}