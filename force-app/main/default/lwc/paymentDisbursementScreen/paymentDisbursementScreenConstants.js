export const LABELS = {
    pageTitle: 'Payment Disbursement',
    pageSubtitle: 'Payment Executive — release & adjustment queue',
    pendingLabel: 'Payment Disbursement (Pending)',
    completedLabel: 'Payment Disbursement (Completed)',
    infoBanner: 'Cases eligible after Payment Release Approval appear here. Select a beneficiary row and Submit to trigger the Finacle Disbursement API.',
    preControlsTitle: 'Pre-Disbursement Controls',
    preControlsSubtitle: 'Automated checks completed before release',
    deferralsTitle: 'Pre-Disbursement Deferrals',
    deferralsSubtitle: 'Mandatory items that gate payment release',
    deferralsSuccess: 'All pre-disbursement deferrals cleared — payment release is enabled.',
    workspaceTitle: 'Disbursement Workspace',
    workspaceSubtitle: 'Process direct payments or TA adjustments',
    directTab: 'Direct Disbursement',
    adjustmentTab: 'TA Adjustment',
    workspaceInfo: 'Select one or more beneficiary rows and submit disbursement. To Be Paid Now is editable to support partial / multi-tranche payments. The Financier row applies to balance-transfer / refinance cases (existing-loan payoff); it is absent for a straight Two-Wheeler New deal.',
    adjustmentInfo: 'Applicable when Payment Org From = TA. TA adjustment is applicable only for dealer disbursement. Select a TA reference number, review the details, and submit.',
    adjustmentDetailsTitle: 'Adjustment Details',
    pendingToAdjustLabel: 'Pending to adjust:',
    submit: 'Submit',
    submitSuccess: 'Disbursement submitted successfully.',
    submitAdjustmentSuccess: 'TA adjustment submitted successfully.',
    selectRowValidation: 'Select at least one beneficiary row to submit.',
    selectDealerBeforeTaReferenceValidation:
        'Select a dealer row in Direct Disbursement before selecting a TA reference.',
    selectTaReferenceValidation: 'Select a TA reference number to submit.',
    adjustmentAmountValidation: 'Enter an adjustment amount greater than zero and not exceeding the pending balance.',
    toBePaidValidation: 'Enter a payment amount greater than zero and not exceeding the remaining balance.',
    loadError: 'Could not load beneficiary disbursement data.',
    noBeneficiaries: 'No beneficiary rows found for this application.'
};

const DISPLAY_MONTHS = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

export const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader';

export const PRIMARY_BTN_CLASS = 'form-primary-btn p4-button-text';
export const ACTION_BAR_CLASS = 'pds-action-bar';
export const ACTION_BAR_CLASS_SPLIT = 'pds-action-bar pds-action-bar--split';
export const DISABLED_BENEFICIARY_ROW_CLASS = 'master-table-row master-table-row--muted';

export const APEX_CLASS = 'PaymentDisbursementController';
export const APEX_METHOD_GET_PAGE_DATA = 'getPageData';
export const APEX_METHOD_SAVE_DISBURSEMENT = 'saveDisbursement';

export const PAYMENT_ORIGIN_TA = 'TA';
export const PAYMENT_ORIGIN_TRADE_ADVANCE = 'TRADE ADVANCE';

export const WORKSPACE_TAB_DIRECT = 'direct';
export const WORKSPACE_TAB_ADJUSTMENT = 'adjustment';

export const LOADER_MESSAGE_SAVING_DISBURSEMENT = 'Saving disbursement...';
export const LOADER_MESSAGE_PROCESSING = 'Processing...';

export const INR_FORMAT = new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    maximumFractionDigits: 0
});

export const SUMMARY_COUNTS = {
    pendingCount: 0,
    completedCount: 0
};

export function mapSummaryCountsFromApi(summaryCounts = {}) {
    return {
        pendingCount: Number(summaryCounts.pendingCount) || 0,
        completedCount: Number(summaryCounts.completedCount) || 0
    };
}

/** Static preview — not loaded from Apex; matches BRD / design mock. */
const PRE_DISBURSEMENT_CONTROLS = [
    {
        key: 'npa',
        title: 'NPA / Willful Defaulter Check',
        subtitle: 'No adverse match across borrower & guarantor.',
        statusLabel: 'Passed',
        statusTone: 'info'
    },
    {
        key: 'dedupe',
        title: 'Customer Dedupe',
        subtitle: 'No duplicate live account found.',
        statusLabel: 'Passed',
        statusTone: 'info'
    },
    {
        key: 'cersai',
        title: 'CERSAI Charge Registration',
        subtitle: 'Security Interest ID SI-2026-558210.',
        statusLabel: 'Registered',
        statusTone: 'info'
    },
    {
        key: 'finacle',
        title: 'Finacle Account Opening',
        subtitle: 'Loan A/c 0042010100087654 opened.',
        statusLabel: 'Completed',
        statusTone: 'success'
    }
];

const CONTROL_ICON_CLASSES = {
    success: 'pds-icon-success',
    info: 'pds-icon-success',
    warning: 'pds-icon-warning',
    neutral: 'pds-icon-pending'
};

const CONTROL_ICON_NAMES = {
    success: 'utility:success',
    info: 'utility:success',
    warning: 'utility:warning',
    neutral: 'utility:clock'
};

export const PRE_DISBURSEMENT_DEFERRALS = [
    {
        key: 'agreement',
        label: 'Loan agreement executed & stamped',
        cleared: true,
        statusLabel: 'Cleared'
    },
    {
        key: 'nach',
        label: 'NACH / e-mandate registered & active',
        cleared: true,
        statusLabel: 'Cleared'
    },
    {
        key: 'rc',
        label: 'RC + hypothecation commitment letter on file',
        cleared: true,
        statusLabel: 'Cleared'
    }
];

export const ALL_DEFERRALS_CLEARED = true;

const STATUS_BADGE_CLASSES = {
    success: 'master-status-badge master-status-badge-success p4-badge-text',
    info: 'master-status-badge master-status-badge-neutral p4-badge-text',
    warning: 'master-status-badge master-status-badge-warning p4-badge-text',
    neutral: 'master-status-badge master-status-badge-neutral p4-badge-text'
};

function mapControlItem(item) {
    const tone = item.statusTone || 'neutral';
    return {
        ...item,
        iconName: CONTROL_ICON_NAMES[tone] || 'utility:clock',
        iconClass: CONTROL_ICON_CLASSES[tone] || 'pds-icon-pending',
        statusBadgeClass: STATUS_BADGE_CLASSES[tone] || STATUS_BADGE_CLASSES.neutral
    };
}

export const PRE_DISBURSEMENT_CONTROLS_MAPPED = PRE_DISBURSEMENT_CONTROLS.map(mapControlItem);

export function mapSummaryCard(key, label, value, tone) {
    const iconName = tone === 'completed' ? 'utility:success' : 'utility:clock';
    return {
        key,
        label,
        value: value ?? '0',
        iconName,
        labelClass: 'pds-kpi-label p4-label-text',
        valueClass: 'pds-kpi-value',
        cardClass: `pds-kpi-card pds-kpi-card--${tone}`
    };
}

export function mapDeferralItem(item) {
    const cleared = item.cleared === true;
    return {
        ...item,
        iconName: cleared ? 'utility:success' : 'utility:clock',
        iconClass: cleared ? 'pds-icon-success' : 'pds-icon-pending',
        statusBadgeClass: cleared
            ? 'master-status-badge master-status-badge-neutral p4-badge-text'
            : 'master-status-badge master-status-badge-warning p4-badge-text'
    };
}

export function mapBeneficiaryRow(row, index) {
    const amount = row.disbursementAmount ?? 0;
    const isFullyPaid = row.disbursed === true;
    return {
        ...row,
        rowKey: row.id || `row-${index}`,
        formattedDisbursementAmount: formatCurrency(amount),
        formattedPaidEarlier: formatCurrency(row.paidEarlier ?? 0),
        rowClass: isFullyPaid
            ? 'master-table-row master-table-row--muted'
            : 'master-table-row',
        checkboxDisabled: isFullyPaid,
        toBePaidInputDisabled: isFullyPaid || !row.selected
    };
}

function formatDisplayDate(value) {
    if (!value) {
        return '—';
    }
    const raw = String(value).trim();
    const isoMatch = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (isoMatch) {
        const monthIndex = parseInt(isoMatch[2], 10) - 1;
        return `${isoMatch[3]}-${DISPLAY_MONTHS[monthIndex] || isoMatch[2]}-${isoMatch[1]}`;
    }
    return raw;
}

export function mapBeneficiaryRowsFromApi(rows = []) {
    return rows.map((row) => {
        const disbursementAmount = Number(row.disbursementAmount) || 0;
        const paidEarlier = Number(row.paidEarlier) || 0;
        const toBePaidNow =
            row.toBePaidNow != null && row.toBePaidNow !== ''
                ? Number(row.toBePaidNow)
                : Math.max(disbursementAmount - paidEarlier, 0);
        const disbursed = row.disbursed === true || (disbursementAmount > 0 && paidEarlier >= disbursementAmount);

        return {
            id: row.id,
            beneficiaryType: row.beneficiaryType || 'dealer',
            beneficiaryTypeLabel: row.beneficiaryTypeLabel || 'DEALER / SELLER',
            beneficiaryName: row.beneficiaryName || '',
            beneficiarySubLabel: row.beneficiarySubLabel || '',
            dealDate: formatDisplayDate(row.dealDate),
            firstEmiDate: formatDisplayDate(row.firstEmiDate),
            secondEmiDate: formatDisplayDate(row.secondEmiDate),
            disbursementAmount,
            paidEarlier,
            toBePaidNow,
            accountNumber: row.accountNumber || '',
            ifscCode: row.ifscCode || '',
            bankName: row.bankName || '—',
            selected: false,
            disbursed
        };
    });
}

const TA_REFERENCE_ROWS = [
    {
        id: 'ta-ref-1001',
        referenceNumber: 'TA-REF-1001',
        totalApprovedValue: 50000,
        processedDate: '02-Jun-2026',
        adjustedSoFar: 0,
        pending: 50000,
        dealerName: 'Priya Motors',
        make: 'Honda',
        invoiceNo: 'INV-2025-5567',
        disbursementAmount: 50000,
        alreadyAdjustedAmount: 0,
        toBeAdjustedNow: '',
        selected: false,
        adjusted: false
    },
    {
        id: 'ta-ref-1002',
        referenceNumber: 'TA-REF-1002',
        totalApprovedValue: 30000,
        processedDate: '15-May-2026',
        adjustedSoFar: 30000,
        pending: 30000,
        dealerName: 'Priya Motors',
        make: 'Honda',
        invoiceNo: 'INV-2025-5567',
        disbursementAmount: 30000,
        alreadyAdjustedAmount: 30000,
        toBeAdjustedNow: '',
        selected: false,
        adjusted: false
    }
];

export function cloneTaReferenceRows() {
    return TA_REFERENCE_ROWS.map((row) => ({ ...row }));
}

export function mapTaReferenceRow(
    row,
    index,
    isSectionDisabled = false,
    isTaSelectionBlockedByDealerSelection = false
) {
    return {
        ...row,
        rowKey: row.id || `ta-row-${index}`,
        formattedTotalApproved: formatCurrency(row.totalApprovedValue ?? 0),
        formattedAdjustedSoFar: formatCurrency(row.adjustedSoFar ?? 0),
        formattedPending: formatCurrency(row.pending ?? 0),
        radioDisabled: isSectionDisabled || row.adjusted || isTaSelectionBlockedByDealerSelection,
        rowClass: row.selected ? 'master-table-row master-table-row--selected' : 'master-table-row'
    };
}

export function mapAdjustmentDetailFields(
    row,
    dealerRow = null,
    calculatedDisbursementAmount = null
) {
    if (!row) {
        return [];
    }
    const dealerName = dealerRow?.beneficiaryName || row.dealerName || '—';
    const disbursementAmountValue =
        calculatedDisbursementAmount == null
            ? Number(row.disbursementAmount) || 0
            : Math.max(0, Number(calculatedDisbursementAmount) || 0);
    return [
        { key: 'dealerName', label: 'Dealer Name', value: dealerName, editable: false },
        {
            key: 'disbursementAmount',
            label: 'Disbursement Amount',
            value: formatCurrency(disbursementAmountValue),
            editable: false
        },
        { key: 'make', label: 'Make', value: row.make || '—', editable: false },
        {
            key: 'alreadyAdjustedAmount',
            label: 'Already Adjusted Amount',
            value: formatCurrency(row.alreadyAdjustedAmount ?? 0),
            editable: false
        },
        { key: 'invoiceNo', label: 'Invoice No', value: row.invoiceNo || '—', editable: false },
        {
            key: 'toBeAdjustedNow',
            label: 'To Be Adjusted Now',
            value: row.toBeAdjustedNow ?? '',
            editable: true,
            required: true
        }
    ];
}

function formatCurrency(value) {
    const numeric = Number(value) || 0;
    return INR_FORMAT.format(numeric);
}