export const APEX_CLASS = 'PdController';
export const APEX_METHOD_GET_PAGE_DATA = 'getPageData';
export const APEX_METHOD_SAVE = 'savePdDetails';

export const LABELS = {
    pageTitle: 'Personal Discussion',
    pageSubtitle: 'Capture and review personal discussion for each applicant',
    pdPending: 'PD Pending',
    inProgress: 'In Progress',
    completed: 'Completed',
    flagsRaised: 'Flags Raised',
    flagRaisedLabel: 'Flag Raised',
    flagRaisedInfoMessage: 'A checklist item is marked No. Update responses and complete PD for this applicant.',
    participantsTitle: 'PD Participants',
    participantsFooter: 'A Personal Discussion is captured for each applicant, co-applicant / guarantor.',
    discussionDetails: 'Discussion Details',
    observationsRemarks: 'Observations & Remarks',
    verificationChecklist: 'Verification Checklist',
    pdOutcome: 'PD Outcome',
    personalDiscussionPrefix: 'Personal Discussion',
    save: 'Save',
    saveSuccess: 'Personal Discussion saved successfully.',
    saveError: 'Unable to save Personal Discussion.',
    loading: 'Loading',
    verificationStatusRequired: 'Verification Status is required.',
    contactNumberInvalid: 'Enter a valid 10-digit Indian mobile number starting with 6-9.',
    genericError: 'An unexpected error occurred. Please try again.',
    selectParticipantMessage: 'Select a participant from the list to capture personal discussion.'
};

export const PD_TYPE_OPTIONS = [
    { label: 'Borrower', value: 'Borrower' },
    { label: 'Co-Applicant / Guarantor', value: 'Co-Applicant / Guarantor' }
];

export const PD_MODE_OPTIONS = [
    { label: 'Physical - Residence', value: 'Physical - Residence' },
    { label: 'Physical - Office', value: 'Physical - Office' },
    { label: 'Telephonic', value: 'Telephonic' },
    { label: 'Video Call', value: 'Video Call' }
];

export const VERIFICATION_STATUS_OPTIONS = [
    { label: 'Initiated', value: 'Initiated' },
    { label: 'In Progress', value: 'In Progress' },
    { label: 'Completed', value: 'Completed' },
    { label: 'Rejected', value: 'Rejected' },
    { label: 'Accepted', value: 'Accepted' }
];

export const VERIFICATION_CHECKLIST_ITEMS = [
    { key: 'applicantIdentityKyc', label: 'Applicant identity & KYC details confirmed' },
    { key: 'residenceAddressStability', label: 'Residence / address stability verified' },
    { key: 'occupationIncomeSource', label: 'Occupation & income source confirmed' },
    { key: 'endUsePurposeGenuine', label: 'End-use / purpose of vehicle understood & genuine' },
    { key: 'obligationsRepaymentIntent', label: 'Existing obligations & repayment intent assessed' },
    { key: 'noAdverseProfile', label: 'No adverse / negative profile observed' }
];

export const RECOMMENDATION_OPTIONS = [
    { label: 'Recommended', value: 'Recommended' },
    { label: 'Not Recommended', value: 'Not Recommended' },
    { label: 'Conditional', value: 'Conditional' }
];

/** Indian mobile: 10 digits, first digit 6–9. */
export const CONTACT_NUMBER_REGEX = /^[6-9]\d{9}$/;
export const CONTACT_NUMBER_MAX_LENGTH = 10;

export function sanitizeContactNumber(value) {
    return String(value || '').replace(/\D/g, '').slice(0, CONTACT_NUMBER_MAX_LENGTH);
}

export function getContactNumberValidationError(value, { required = false } = {}) {
    const trimmed = String(value || '').trim();
    if (!trimmed) {
        return required ? 'Contact number is required.' : '';
    }
    if (!CONTACT_NUMBER_REGEX.test(trimmed)) {
        return LABELS.contactNumberInvalid;
    }
    return '';
}

const AVATAR_TONE_CLASSES = [
    'pd-avatar pd-avatar--blue',
    'pd-avatar pd-avatar--purple',
    'pd-avatar pd-avatar--orange'
];

const PD_PARTICIPANT_ROLE_SORT_ORDER = Object.freeze({
    'Primary Applicant': 0,
    Guarantor: 1,
    'Co-Applicant': 2,
    Beneficiary: 3
});

export function sortPdParticipantsByBusinessOrder(participants = []) {
    return [...participants]
        .sort((left, right) => {
            const leftRank = PD_PARTICIPANT_ROLE_SORT_ORDER[left.roleLabel] ?? 99;
            const rightRank = PD_PARTICIPANT_ROLE_SORT_ORDER[right.roleLabel] ?? 99;
            if (leftRank !== rightRank) {
                return leftRank - rightRank;
            }
            return (left.applicantName || '').localeCompare(right.applicantName || '');
        })
        .map((participant, index) => ({
            ...participant,
            avatarToneIndex: index
        }));
}

export function sortPdVerificationFormsByParticipantOrder(verificationForms = [], sortedParticipants = []) {
    const orderByVerificationId = new Map(
        sortedParticipants.map((participant, index) => [participant.verificationId, index])
    );
    return [...verificationForms].sort(
        (left, right) =>
            (orderByVerificationId.get(left.verificationId) ?? 99)
            - (orderByVerificationId.get(right.verificationId) ?? 99)
    );
}

const STATUS_BADGE_CLASSES = {
    Pending: 'pd-status-badge pd-status-badge--pending',
    Initiated: 'pd-status-badge pd-status-badge--pending',
    'In Progress': 'pd-status-badge pd-status-badge--progress',
    Completed: 'pd-status-badge pd-status-badge--completed',
    Accepted: 'pd-status-badge pd-status-badge--completed',
    Rejected: 'pd-status-badge pd-status-badge--danger',
    'Flag Raised': 'pd-status-badge pd-status-badge--danger'
};

export function mapParticipant(participant, selectedVerificationId) {
    const isSelected = participant.verificationId === selectedVerificationId;
    const toneClass = AVATAR_TONE_CLASSES[participant.avatarToneIndex % AVATAR_TONE_CLASSES.length];
    const showFlagRaised = Boolean(participant.flagRaised);
    const displayStatus = showFlagRaised ? 'Flag Raised' : participant.statusLabel;
    const statusClass = STATUS_BADGE_CLASSES[displayStatus] || STATUS_BADGE_CLASSES.Pending;

    return {
        ...participant,
        itemClass: isSelected ? 'pd-participant-item pd-participant-item--selected' : 'pd-participant-item',
        avatarClass: toneClass,
        statusBadgeClass: statusClass,
        statusLabel: displayStatus,
        ariaSelected: isSelected
    };
}

export function resolveOptionLabel(options, value) {
    if (!value) {
        return '';
    }
    const match = options.find((option) => option.value === value);
    return match?.label || value;
}

export function mapSummaryCard(key, label, value, tone) {
    return {
        key,
        label,
        value,
        tone,
        valueClass: `pd-summary-value pd-summary-value--${tone}`,
        labelClass: 'pd-summary-label'
    };
}

export function buildEmptyChecklist() {
    return VERIFICATION_CHECKLIST_ITEMS.reduce((checklist, item) => {
        checklist[item.key] = '';
        return checklist;
    }, {});
}

function normalizeChecklistAnswer(value) {
    const normalized = String(value || '').trim();
    if (!normalized || normalized.toLowerCase() === 'n/a') {
        return '';
    }
    return normalized;
}

export function normalizeVerificationChecklist(checklist = {}) {
    return VERIFICATION_CHECKLIST_ITEMS.reduce((normalizedChecklist, item) => {
        normalizedChecklist[item.key] = normalizeChecklistAnswer(checklist[item.key]);
        return normalizedChecklist;
    }, {});
}

export function hasChecklistFlag(checklist = {}) {
    return Object.values(normalizeVerificationChecklist(checklist)).some(
        (answer) => answer.toLowerCase() === 'no'
    );
}

export function resolvePdReadOnly(form = {}, isClosed = false) {
    if (isClosed) {
        return true;
    }
    if (form.flagRaised) {
        return false;
    }
    const status = form.verificationStatus || '';
    const isCompletedStatus = status === 'Completed' || status === 'Accepted';
    return Boolean(form.isSubmitted && isCompletedStatus);
}

export function buildDisplayValues(form = {}) {
    return {
        pdType: form.pdType || '',
        pdMode: form.pdMode || '',
        verificationWith: form.verificationWith || '',
        contactNumber: form.contactNumber || '',
        pdDateTime: form.pdDateTime || '',
        conductedBy: form.conductedBy || '',
        applicantProfileObservations: form.applicantProfileObservations || '',
        overallRemarks: form.overallRemarks || '',
        additionalRemarks: form.additionalRemarks || '',
        verificationStatus: resolveOptionLabel(VERIFICATION_STATUS_OPTIONS, form.verificationStatus),
        recommendation: resolveOptionLabel(RECOMMENDATION_OPTIONS, form.recommendation),
        finalRemarks: form.finalRemarks || ''
    };
}

function resolveAnswerButtonClass(selectedAnswer, answer, isReadOnly) {
    const isSelected = selectedAnswer === answer;
    const classes = ['pd-answer-btn'];
    if (isSelected) {
        classes.push('pd-answer-btn--selected');
    }
    if (isReadOnly) {
        classes.push('pd-answer-btn--disabled');
    }
    return classes.join(' ');
}

export function mapVerificationChecklistItems(checklist = {}, isReadOnly = false) {
    const safeChecklist = checklist || {};
    return VERIFICATION_CHECKLIST_ITEMS.map((item) => {
        const selectedAnswer = normalizeChecklistAnswer(safeChecklist[item.key]);
        return {
            ...item,
            selectedAnswer,
            yesButtonClass: resolveAnswerButtonClass(selectedAnswer, 'Yes', isReadOnly),
            noButtonClass: resolveAnswerButtonClass(selectedAnswer, 'No', isReadOnly)
        };
    });
}

export function buildEmptyForm() {
    return {
        verificationId: null,
        applicantId: null,
        applicantName: '',
        pdType: '',
        pdMode: '',
        verificationWith: '',
        contactNumber: '',
        pdDateTime: '',
        conductedBy: '',
        verificationChecklist: buildEmptyChecklist(),
        applicantProfileObservations: '',
        overallRemarks: '',
        additionalRemarks: '',
        verificationStatus: '',
        recommendation: '',
        finalRemarks: '',
        flagRaised: false,
        isSubmitted: false
    };
}