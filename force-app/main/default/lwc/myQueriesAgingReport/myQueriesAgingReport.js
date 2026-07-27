import { LightningElement, api, track } from 'lwc';
import getQueryAgingChunk from '@salesforce/apex/MyQueriesAgingReportController.getQueryAgingChunk';
export default class MyQueriesAgingReport extends LightningElement {

    showDetails = false;
    queryStatusOptions = [];
    queryPriorityOptions = [];
    queryTypeOptions = [];
    queryOwnerOptions = [];
    queryCreatedDateOptions = [];
    queryDueDateOptions = [];

    @track queryRecords = [];
    queryNextCursorCreatedDate = null;
    queryNextCursorId = null;
    queryHasMore = false;
    queryCurrentPage = 1;
    queryTotalRecords = 0;
    queryCountExceedsThreshold = false;
    queryTotalPages = 0;

    @api showData() {
        this.showDetails = true;
        Promise.all([
            this.fetchAllQueryPages(null, null, null)
        ])
        .then(([queryChunk]) => {
            console.log('queryChunk', JSON.stringify(queryChunk));
            const queryData = queryChunk?.records || [];
            if (queryData.length > 0) {
                this.queryRecords = queryData.sort((a, b) =>
                    (b.agingInDays || 0) - (a.agingInDays || 0)
                );
            }
            else {
                this.queryRecords = [];
            }
            this.queryNextCursorCreatedDate = queryChunk?.nextCursorCreatedDate || null;
            this.queryNextCursorId = queryChunk?.nextCursorId || null;
            this.queryHasMore = queryChunk?.hasMore === true;
            this.queryCurrentPage = 1;
            this.queryFilteredRecords = [...this.queryRecords];
            this.queryDisplayedRecords = this.queryFilteredRecords;
            this.queryTotalRecords = this.resolveTotalRecords(queryChunk?.totalCount, this.queryTotalRecords);
            this.queryCountExceedsThreshold = this.resolveCountExceedsThreshold(queryChunk, this.queryCountExceedsThreshold);
            this.queryTotalPages = this.resolveTotalPages(this.queryTotalRecords);
            
            // Mark as loaded
            this.queryDataLoaded = true;
            
            // Build filter options from the data
            this.buildQueryFilterOptions();
            
            this.isLoading = false;
        })
        .catch(error => {
            console.error('Error loading query aging:', error);
        });
    }

    async fetchAllQueryPages(cursorCreatedDate = null, cursorId = null, cursorDirection = 'forward') {
        const userIds = this.employeeUserIds;
        return getQueryAgingChunk({
            userIds,
            statusFilter: this.querySelectedStatus,
            priorityFilter: this.querySelectedPriority,
            typeFilter: this.querySelectedType,
            ageFilter: this.querySelectedAge,
            managerFilter: null,
            ownerFilter: null,
            pageSize: this.pageSize,
            cursorCreatedDate,
            cursorId,
            cursorDirection
        });
    }

    // Build query filter options (called when query data is loaded)
    buildQueryFilterOptions() {
        // Build Status options from Query records
        const employeeStatuses = new Set();
        this.queryRecords.forEach(record => {
            if (record.status) employeeStatuses.add(record.status);
        });
        
        this.queryStatusOptions = [
            { label: '-- All Statuses --', value: '' },
            ...Array.from(employeeStatuses).sort().map(status => ({ label: status, value: status }))
        ];
        
        // Build Priority options
        const employeePriorities = new Set();
        this.queryRecords.forEach(record => {
            if (record.priority) employeePriorities.add(record.priority);
        });
        
        this.queryPriorityOptions = [
            { label: '-- All Priorities --', value: '' },
            ...Array.from(employeePriorities).sort().map(priority => ({ label: priority, value: priority }))
        ];
        
        // Build Type options
        const queryTypes = new Set();
        this.queryRecords.forEach(record => {
            if (record.queryType) queryTypes.add(record.queryType);
        });
        
        this.queryTypeOptions = [
            { label: '-- All Types --', value: '' },
            ...Array.from(queryTypes).sort().map(type => ({ label: type, value: type }))
        ];
    }

    resolveTotalRecords(serverTotalCount, fallbackTotalCount) {
        return Number.isInteger(serverTotalCount) ? serverTotalCount : (fallbackTotalCount || 0);
    }

    resolveCountExceedsThreshold(chunk, fallbackFlag) {
        if (chunk && typeof chunk.countExceedsThreshold === 'boolean') {
            return chunk.countExceedsThreshold;
        }
        return fallbackFlag === true;
    }

    resolveTotalPages(totalRecords) {
        return totalRecords > 0 ? Math.ceil(totalRecords / this.pageSize) : 0;
    }

    @api hideData() {
        this.showDetails = false;
    }

    
}