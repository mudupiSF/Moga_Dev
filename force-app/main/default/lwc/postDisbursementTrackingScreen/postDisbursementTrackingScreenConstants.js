export const LABELS = {
    pageTitle: 'Post-Disbursement Tracking',
    pageSubtitle: 'Operations — PDD, security perfection & file closure',
    documentsReceived: 'Documents Received',
    pending: 'Pending',
    overdue: 'Overdue',
    pddCompletion: 'PDD Completion',
    applicationSummaryTitle: 'Application Summary',
    applicationSummarySubtitle: 'Read-only details carried from the deal',
    pddTitle: 'Post-Disbursement Documents (PDD)',
    pddSubtitle: 'Deferral register with ageing',
    hypothecationTitle: 'Hypothecation / RC Endorsement',
    hypothecationSubtitle: 'Security perfection',
    insuranceTitle: 'Insurance Verification',
    insuranceSubtitle: 'Asset cover',
    repaymentTitle: 'Repayment Setup',
    repaymentSubtitle: 'Auto-debit mandate & schedule',
    communicationTitle: 'Customer Communication',
    communicationSubtitle: 'RBI-mandated disclosures',
    bureauTitle: 'Credit Bureau Reporting',
    bureauSubtitle: 'CIBIL / bureau onboarding',
    refreshPdd: 'Refresh PDD list',
    markReceived: 'Mark Received',
    dispatch: 'Dispatch',
    done: 'Done',
    markReceivedSuccess: 'Document marked as received.',
    dispatchSuccess: 'Communication dispatch initiated.',
    flagForReporting: 'Flag for Reporting',
    flagForReportingSuccess: 'Case flagged for bureau reporting.',
    qcTitle: 'Post-Disbursement QC & File Closure',
    qcSubtitle: 'Final control gate',
    qcReviewTitle: 'Post-disbursement QC / audit review',
    signOff: 'Sign Off',
    signOffSuccess: 'QC sign-off recorded.',
    closeHandover: 'Close & Handover to Servicing',
    closeHandoverSuccess: 'File closed and handed over to servicing.',
    qcFooterNote: 'File can be closed only after all PDDs, communication and bureau reporting are complete.',
    missingViewId: 'Current view ID is missing. Please refresh and try again.',
    loadError: 'Could not load post-disbursement tracking data.',
    saveError: 'Unable to save post-disbursement status.'
};

export const STAGE_POST_DISBURSEMENT_TRACKING = 'Post-Disbursement Tracking';
export const LOS_NEXT_STAGE_EVENT = 'losnextstage';
export const APEX_CLASS = 'PostDisbursementTrackingController';
export const APEX_METHOD_GET_PAGE_DATA = 'getPageData';
export const APEX_METHOD_SAVE_TRACKING = 'saveTrackingState';

export const SUMMARY_STATS = {
    documentsReceived: 0,
    documentsTotal: 5,
    pendingCount: 5,
    overdueCount: 0,
    pddCompletionPercent: 0
};

export const APPLICATION_SUMMARY = {
    leadNumber: 'LEAD-2025-08420',
    borrowerName: 'Rajesh Kumar Sharma',
    loanAccountNumber: '0042010100087654',
    productType: 'Two Wheeler'
};

export const SUMMARY_FIELDS = [
    { key: 'leadNumber', label: 'Lead Number' },
    { key: 'borrowerName', label: 'Borrower Name' },
    { key: 'loanAccountNumber', label: 'Loan Account Number' },
    { key: 'productType', label: 'Product Type' }
];

export const PDD_DOCUMENTS = [
    {
        id: 'rc',
        documentName: 'RC copy',
        owner: 'Sales Officer',
        expectedDate: null,
        ageingDays: 0,
        status: 'Pending',
        canMarkReceived: true
    },
    {
        id: 'invoice',
        documentName: 'Tax invoice',
        owner: 'Dealer',
        expectedDate: null,
        ageingDays: 0,
        status: 'Pending',
        canMarkReceived: true
    },
    {
        id: 'insurance',
        documentName: 'Insurance policy',
        owner: 'Operations',
        expectedDate: null,
        ageingDays: 0,
        status: 'Pending',
        canMarkReceived: true
    },
    {
        id: 'form34',
        documentName: 'Form 34 (HP endorsement)',
        owner: 'Operations',
        expectedDate: null,
        ageingDays: 0,
        status: 'Pending',
        canMarkReceived: true
    },
    {
        id: 'delivery',
        documentName: 'Delivery challan',
        owner: 'Sales Officer',
        expectedDate: null,
        ageingDays: 0,
        status: 'Pending',
        canMarkReceived: true
    }
];

export const HYPOTHECATION_ALERT = null;

export const HYPOTHECATION_FIELDS = [
    { label: 'Endorsement', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Registration No.', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Hypothecatee', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Marked On', value: null, badgeLabel: null, badgeTone: null },
    { label: 'RC Retention Applicable', value: null, badgeLabel: null, badgeTone: null }
];

export const INSURANCE_FIELDS = [
    { label: 'Policy Type', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Sum Insured (IDV)', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Motor Insurance Premium', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Bank Interest', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Valid Till', value: null, badgeLabel: null, badgeTone: null }
];

export const REPAYMENT_FIELDS = [
    { label: 'Mandate', value: null, badgeLabel: null, badgeTone: null },
    { label: 'EMI Amount', value: null, badgeLabel: null, badgeTone: null },
    { label: 'First EMI Date', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Tenure', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Mandate Reference', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Debit Account', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Repayment Mode', value: null, badgeLabel: null, badgeTone: null },
    { label: 'Bounce Charge Rule', value: null, badgeLabel: null, badgeTone: null }
];

export const COMMUNICATIONS = [
    {
        id: 'welcome',
        label: 'Welcome letter / sanction-cum-disbursement intimation',
        status: 'Dispatched',
        canDispatch: false
    },
    {
        id: 'kfs',
        label: 'Key Fact Statement (KFS)',
        status: 'Dispatched',
        canDispatch: false
    }
];

export const BUREAU_FIELDS = [
    { label: 'Reporting Status', value: 'Not Started', badgeLabel: 'Not Started', badgeTone: 'warning' },
    { label: 'Bureaus', value: 'CIBIL, Experian, CRIF, Equifax', badgeLabel: null, badgeTone: null },
    { label: 'Next Submission Cycle', value: '30-Jun-2026', badgeLabel: null, badgeTone: null }
];

export const QC_CHECKLIST = [
    { id: 'pdds', label: 'All PDDs received', complete: false },
    { id: 'communication', label: 'Customer communication dispatched', complete: true },
    { id: 'bureau', label: 'Credit bureau reporting flagged', complete: false }
];

const SUMMARY_ICONS = {
    success: 'utility:success',
    pending: 'utility:clock',
    overdue: 'utility:error',
    completion: 'utility:clock'
};

const SUMMARY_VALUE_CLASSES = {
    success: 'pds-kpi-value',
    pending: 'pds-kpi-value',
    overdue: 'pds-kpi-value',
    completion: 'pds-kpi-value'
};

const STATUS_BADGE_CLASSES = {
    Pending: 'master-status-badge master-status-badge-warning p4-badge-text',
    Overdue: 'master-status-badge master-status-badge-danger p4-badge-text',
    Received: 'master-status-badge master-status-badge-neutral p4-badge-text',
    success: 'master-status-badge master-status-badge-success p4-badge-text',
    warning: 'master-status-badge master-status-badge-warning p4-badge-text'
};

export function mapSummaryStat(key, label, value, tone) {
    return {
        key,
        label,
        value,
        iconName: SUMMARY_ICONS[tone] || 'utility:clock',
        labelClass: 'pds-kpi-label p4-label-text',
        valueClass: SUMMARY_VALUE_CLASSES[tone] || 'pds-kpi-value',
        cardClass: `pds-kpi-card pds-kpi-card--${tone}`
    };
}

export function mapSummaryField(field, applicationSummary = {}) {
    return {
        ...field,
        value: applicationSummary[field.key] || '—'
    };
}

export function mapPddRow(row) {
    const isOverdue = row.status !== 'Received' && Number(row.ageingDays || 0) > 0;
    const ageingClass = isOverdue
        ? 'pdts-text--danger p4-field-value-normal'
        : 'p4-field-value-normal';
    return {
        ...row,
        statusBadgeClass: isOverdue
            ? STATUS_BADGE_CLASSES.Overdue
            : STATUS_BADGE_CLASSES[row.status] || STATUS_BADGE_CLASSES.Pending,
        ageingClass,
        showMarkReceived: row.canMarkReceived,
        showDone: !row.canMarkReceived
    };
}

export function mapDetailField(field) {
    return {
        ...field,
        showBadge: Boolean(field.badgeLabel),
        badgeClass: STATUS_BADGE_CLASSES[field.badgeTone] || STATUS_BADGE_CLASSES.warning
    };
}

export function mapDetailFields(fields = []) {
    return fields.map(mapDetailField);
}

export function mapCommunicationItem(item) {
    const canDispatch = item.canDispatch !== false;
    return {
        ...item,
        canDispatch,
        showDispatch: canDispatch,
        showDone: !canDispatch,
        iconName: canDispatch ? 'utility:warning' : 'utility:success',
        iconClass: canDispatch ? 'pdts-icon-warning' : 'pdts-icon-success',
        iconAlt: canDispatch ? 'Pending' : 'Dispatched'
    };
}

export function mapQcChecklistItem(item) {
    return {
        ...item,
        iconName: item.complete ? 'utility:success' : 'utility:warning',
        iconClass: item.complete ? 'pdts-icon-success' : 'pdts-icon-warning'
    };
}

export function cloneQcChecklist() {
    return QC_CHECKLIST.map((item) => ({ ...item }));
}

export function clonePddDocuments() {
    return PDD_DOCUMENTS.map((doc) => ({ ...doc }));
}

export function cloneCommunications() {
    return COMMUNICATIONS.map((item) => ({ ...item }));
}

export function computeSummaryStats(documents) {
    const stats = {
        documentsTotal: documents.length,
        documentsReceived: 0,
        pendingCount: 0,
        overdueCount: 0,
        pddCompletionPercent: 0
    };
    documents.forEach((doc) => {
        if (doc.status === 'Received') {
            stats.documentsReceived += 1;
            return;
        }
        stats.pendingCount += 1;
        if (Number(doc.ageingDays || 0) > 0) {
            stats.overdueCount += 1;
        }
    });
    stats.pddCompletionPercent = stats.documentsTotal
        ? Math.round((stats.documentsReceived / stats.documentsTotal) * 100)
        : 0;
    return stats;
}