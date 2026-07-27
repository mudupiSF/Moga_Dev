/**
 * Section progress via template querySelector — one pass per refresh, no getter DOM reads.
 * Each editable user input exposes data-section-input + data-required="true"
 * + data-editable="true" and either a native value or data-value for LWC base components.
 */

const EDITABLE_REQUIRED_SELECTOR = '[data-section-input][data-required="true"][data-editable="true"]';

const SECTION_CHAIN = [
    { sectionId: 'applicationDetails',   nextKey: 'showLoanBasicInfo' },
    { sectionId: 'loanBasicInfo',        nextKey: 'showLoanDetail' },
    { sectionId: 'loanDetail',           nextKey: 'showProfessionalDetail' },
    { sectionId: 'professionalDetail',   nextKey: 'showDocumentVerification' },
    { sectionId: 'documentVerification', nextKey: 'showContactInfo' }
];

const ALL_SECTION_KEYS = [
    'showLoanBasicInfo',
    'showLoanDetail',
    'showProfessionalDetail',
    'showDocumentVerification',
    'showContactInfo'
];

function inputHasValue(el) {
    if (!el) return false;
    const raw = el.dataset.value !== undefined ? el.dataset.value : el.value;
    if (raw == null) return false;
    if (typeof raw === 'string') return raw.trim() !== '';
    return String(raw).trim() !== '';
}

/** True when every editable required input in the section has a value. */
export function isSectionComplete(template, sectionId) {
    if (!template || !sectionId) return false;
    const root = template.querySelector(`[data-id="${sectionId}"]`);
    if (!root) return false;
    const inputs = root.querySelectorAll(EDITABLE_REQUIRED_SELECTOR);
    if (!inputs.length) return true;
    for (let i = 0; i < inputs.length; i++) {
        if (!inputHasValue(inputs[i])) return false;
    }
    return true;
}


function resolveSectionComplete(template, sectionId, overrides) {
    if (overrides && Object.prototype.hasOwnProperty.call(overrides, sectionId)
        && typeof overrides[sectionId] === 'boolean') {
        return overrides[sectionId];
    }
    return isSectionComplete(template, sectionId);
}

/**
 * Computes which sections after Application Details should be visible.
 *
 * @param {ShadowRoot} template
 * @param {boolean}    isBasicDetailsStage
 * @param {boolean|null} applicationDetailsComplete  (kept positional for back-compat)
 * @param {Object}     [overrides]  per-section completeness overrides keyed by sectionId
 */
export function computeSectionVisibility(template, isBasicDetailsStage, applicationDetailsComplete, overrides) {
    const visibility = Object.fromEntries(ALL_SECTION_KEYS.map((k) => [k, false]));
    if (!isBasicDetailsStage) {
        ALL_SECTION_KEYS.forEach((k) => { visibility[k] = true; });
        return visibility;
    }

    const effectiveOverrides = {
        ...(overrides || {})
    };
    if (typeof applicationDetailsComplete === 'boolean'
        && !Object.prototype.hasOwnProperty.call(effectiveOverrides, 'applicationDetails')) {
        effectiveOverrides.applicationDetails = applicationDetailsComplete;
    }

    let priorComplete = resolveSectionComplete(template, 'applicationDetails', effectiveOverrides);

    for (let i = 0; i < SECTION_CHAIN.length; i++) {
        if (i > 0) {
            if (!priorComplete) break;
            priorComplete = resolveSectionComplete(template, SECTION_CHAIN[i].sectionId, effectiveOverrides);
        }
        if (priorComplete && SECTION_CHAIN[i].nextKey) {
            visibility[SECTION_CHAIN[i].nextKey] = true;
        }
    }
    return visibility;
}

export function areAllSectionsComplete(template, isBasicDetailsStage, applicationDetailsComplete, overrides) {
    if (!isBasicDetailsStage) return true;
    const effectiveOverrides = {
        ...(overrides || {})
    };
    if (typeof applicationDetailsComplete === 'boolean'
        && !Object.prototype.hasOwnProperty.call(effectiveOverrides, 'applicationDetails')) {
        effectiveOverrides.applicationDetails = applicationDetailsComplete;
    }
    return resolveSectionComplete(template, 'applicationDetails',   effectiveOverrides)
        && resolveSectionComplete(template, 'loanBasicInfo',        effectiveOverrides)
        && resolveSectionComplete(template, 'loanDetail',           effectiveOverrides)
        && resolveSectionComplete(template, 'professionalDetail',   effectiveOverrides)
        && resolveSectionComplete(template, 'documentVerification', effectiveOverrides)
        && resolveSectionComplete(template, 'contactInfo',          effectiveOverrides);
}