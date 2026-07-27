export const APEX_CLASS = 'AmlCheckController';
export const APEX_METHOD_GET_PAGE_DATA = 'getPageData';
export const APEX_METHOD_SUBMIT = 'submitInvestigation';
export const SCROLLBAR_HIDE_DELAY_MS = 800;

export const AML_APPLICANT_TYPES = Object.freeze([
    'Borrower',
    'Co-borrower',
    'Guarantor',
    'Beneficiary'
]);

export const DECISION_OPTIONS = [
    { label: 'Positive', value: 'Positive' },
    { label: 'False Positive', value: 'False Positive' }
];

export const LABELS = {
    amlReviewTitle: 'AML Check',
    amlReviewSubtitle: 'Review and record decisions on potential matches',
    casesFound: 'Matches Found',
    copyRemarks: 'Copy Remarks',
    submit: 'Submit',
    applicantDetailsTitle: 'Applicant Details',
    personalInfoTitle: 'Personal Information',
    personalInfoSubtitle: 'Applicant name, type, and date of birth',
    addressInfoTitle: 'Address Information',
    addressInfoSubtitle: 'Residential, office, and permanent addresses',
    identityDocsTitle: 'Identity Documents (Encrypted)',
    identityDocsSubtitle: 'Masked identity proofs for the selected applicant',
    applyDecisionAll: 'Apply Decision to All',
    positiveWarning: 'You selected a positive match. Do you want to proceed?',
    positiveWarningTitle: 'Warning',
    submitSuccess: 'AML Check submitted successfully.',
    mandatoryDetailsError: 'Decision is required for every match row before submit.',
    genericError: 'An unexpected error occurred. Please try again.',
    remarksCopySuccess: 'Remarks copied to all rows successfully.',
    remarksCopyError: 'No remarks found to copy. Enter remarks in at least one row.',
    loading: 'Loading',
    investigationStatus: 'Status',
    noMatches: 'No AML matches found for this investigation.',
    nameLabel: 'Name',
    applicantTypeLabel: 'Applicant Type',
    dobLabel: 'Date of Birth',
    priorityLabel: 'Priority',
    statusLabel: 'Status',
    revealDocument: 'Reveal document value',
    hideDocument: 'Hide document value'
};

const DOC_ICON_CLASS = {
    pan: 'aml-doc-icon aml-doc-icon--orange',
    voterId: 'aml-doc-icon aml-doc-icon--blue',
    drivingLicense: 'aml-doc-icon aml-doc-icon--purple',
    aadhaar: 'aml-doc-icon aml-doc-icon--teal',
    passport: 'aml-doc-icon aml-doc-icon--maroon'
};

const BADGE_NEUTRAL = 'aml-field-badge aml-field-badge--neutral';
const BADGE_STATUS = 'aml-field-badge aml-field-badge--status';

function resolvePriorityBadgeClass(priority) {
    if (priority === 'High') {
        return 'aml-field-badge aml-field-badge--high';
    }
    if (priority === 'Medium') {
        return 'aml-field-badge aml-field-badge--medium';
    }
    return 'aml-field-badge aml-field-badge--low';
}

function buildPersonalFields(applicant) {
    const fields = [
        { key: 'name', label: LABELS.nameLabel, value: applicant.applicantName, isBadge: false },
        { key: 'type', label: LABELS.applicantTypeLabel, value: applicant.applicantType, isBadge: true, badgeClass: BADGE_NEUTRAL },
        { key: 'dob', label: LABELS.dobLabel, value: applicant.dob, isBadge: false }
    ];
    if (applicant.priority) {
        fields.push({
            key: 'priority',
            label: LABELS.priorityLabel,
            value: applicant.priority,
            isBadge: true,
            badgeClass: resolvePriorityBadgeClass(applicant.priority)
        });
    }
    if (applicant.status) {
        fields.push({
            key: 'status',
            label: LABELS.statusLabel,
            value: applicant.status,
            isBadge: true,
            badgeClass: BADGE_STATUS
        });
    }
    return fields;
}

function mapIdentityDocument(document, applicantId, revealedDocKeys) {
    const revealKey = `${applicantId}:${document.docKey}`;
    const isRevealed = revealedDocKeys.has(revealKey);
    return {
        ...document,
        revealKey,
        isDisabled: !document.hasValue,
        iconClass: DOC_ICON_CLASS[document.docKey] || DOC_ICON_CLASS.pan,
        showMaskedValue: isRevealed && document.hasValue,
        lockButtonClass: isRevealed ? 'aml-doc-lock aml-doc-lock--revealed' : 'aml-doc-lock',
        lockIconName: isRevealed ? 'utility:unlock' : 'utility:lock',
        lockIconClass: isRevealed ? 'aml-doc-lock-unlock' : 'aml-doc-lock-icon',
        ariaLabel: isRevealed ? LABELS.hideDocument : LABELS.revealDocument
    };
}

export function mapApplicant(applicant, selectedApplicantId, revealedDocKeys) {
    const applicantId = applicant.applicantId;
    const isSelected = applicantId === selectedApplicantId;
    return {
        ...applicant,
        personalFields: buildPersonalFields(applicant),
        addresses: (applicant.addresses || []).map((address) => ({
            ...address,
            displayValue: address.value || '—',
            valueClass: address.value
                ? 'form-info-value'
                : 'form-info-value aml-empty-value'
        })),
        identityDocuments: (applicant.identityDocuments || []).map((document) => (
            mapIdentityDocument(document, applicantId, revealedDocKeys)
        )),
        tabClass: isSelected ? 'tab-btn tab-btn-active' : 'tab-btn',
        tabSelected: isSelected
    };
}

function resolveScoreBadgeClass(scoreValue) {
    if (scoreValue === null || scoreValue === undefined || scoreValue === '') {
        return 'score-chip';
    }
    const score = parseFloat(String(scoreValue).replace('%', '').trim());
    if (Number.isNaN(score)) {
        return 'score-chip';
    }
    if (score >= 90) {
        return 'score-chip score-chip--good';
    }
    if (score >= 85) {
        return 'score-chip score-chip--high';
    }
    if (score >= 75) {
        return 'score-chip score-chip--medium';
    }
    return 'score-chip score-chip--good';
}

export function mapVerificationRow(row) {
    return {
        id: row.id,
        serialNo: row.serialNo,
        listName: row.listName || '',
        customerName: row.customerName || '',
        nameScore: row.nameScore,
        nameScoreClass: resolveScoreBadgeClass(row.nameScore),
        nationality: row.nationality || '',
        nationalityScore: row.nationalityScore,
        nationalityScoreClass: resolveScoreBadgeClass(row.nationalityScore),
        mlCity: row.mlCity || '',
        mlAddress: row.mlAddress || '',
        mlDateOfBirth: row.mlDateOfBirth || '',
        mlDescription: row.mlDescription || '',
        decision: row.decision || '',
        remarks: row.remarks || '',
        recordCss: row.partialKycFlag ? 'partial-kyc-row' : ''
    };
}