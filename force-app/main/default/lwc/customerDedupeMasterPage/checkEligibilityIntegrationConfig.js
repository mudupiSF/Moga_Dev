/**
 * Customer Dedupe integration stage plans.
 *
 * Check Eligibility (NPA / CIBIL / CRIF / BRE):
 *   To wire live APIs — replace the matching run* method in CustomerDedupeIntegrationService.
 *   Stage plan is customer-type-aware:
 *     Individual     → NPA → CIBIL → BRE
 *     Non-Individual → NPA → CRIF  → BRE
 *
 * Dedupe Next forward (AML / ScoreCard — Borrower Next advances application):
 *   To wire live APIs — replace runScorecardForwardIntegration in CustomerDedupeIntegrationService.
 *   AML is already live via AMLCheckAPIController.
 */

export const CHECK_ELIGIBILITY_STAGE_KEYS = {
    NPA: 'NPA',
    CIBIL: 'CIBIL',
    CRIF: 'CRIF',
    BRE: 'BRE'
};

export const DEDUPE_FORWARD_STAGE_KEYS = {
    AML: 'AML',
    SCORECARD: 'SCORECARD',
    FI_CREATION: 'FI_CREATION'
};

const STAGE_NPA = {
    key: CHECK_ELIGIBILITY_STAGE_KEYS.NPA,
    includeApplicantInLabel: true,
    labelTemplate: 'NPA for {applicant}'
};

const STAGE_CIBIL = {
    key: CHECK_ELIGIBILITY_STAGE_KEYS.CIBIL,
    includeApplicantInLabel: true,
    labelTemplate: 'CIBIL for {applicant}'
};

const STAGE_CRIF = {
    key: CHECK_ELIGIBILITY_STAGE_KEYS.CRIF,
    includeApplicantInLabel: true,
    labelTemplate: 'CRIF for {applicant}'
};

const STAGE_BRE = {
    key: CHECK_ELIGIBILITY_STAGE_KEYS.BRE,
    includeApplicantInLabel: false,
    label: 'BRE Check Eligibility API'
};

/**
 * @param {string}  applicantTabLabel e.g. Borrower, G1
 * @param {boolean} isNonIndividual   true for Non-Individual customer type
 * @returns {{ key: string, label: string }[]}
 */
export function buildCheckEligibilityStagePlan(applicantTabLabel = 'Borrower', isNonIndividual = false) {
    const applicant = (applicantTabLabel || 'Borrower').trim() || 'Borrower';

    const definitions = isNonIndividual
        ? [STAGE_NPA, STAGE_CRIF, STAGE_BRE]
        : [STAGE_NPA, STAGE_CIBIL, STAGE_BRE];

    return definitions.map((definition) => {
        if (definition.includeApplicantInLabel) {
            return {
                key: definition.key,
                label: definition.labelTemplate.replace('{applicant}', applicant)
            };
        }
        return {
            key: definition.key,
            label: definition.label
        };
    });
}

export function getCheckEligibilityStageLabels(stagePlan) {
    return (stagePlan || []).map((stage) => stage.label);
}

const STAGE_AML = {
    key: DEDUPE_FORWARD_STAGE_KEYS.AML,
    label: 'AML Check'
};

const STAGE_SCORECARD = {
    key: DEDUPE_FORWARD_STAGE_KEYS.SCORECARD,
    label: 'ScoreCard API'
};

const STAGE_FI_CREATION = {
    key: DEDUPE_FORWARD_STAGE_KEYS.FI_CREATION,
    label: 'Creating FI Investigations'
};

/** @param {boolean} includeCvNiFi Append FI creation for CV Non-Individual borrower forward */
export function buildDedupeForwardStagePlan(includeCvNiFi = false) {
    const definitions = [STAGE_AML, STAGE_SCORECARD];
    if (includeCvNiFi === true) {
        definitions.push(STAGE_FI_CREATION);
    }
    return definitions.map((definition) => ({
        key: definition.key,
        label: definition.label
    }));
}

export function getDedupeForwardStageLabels(stagePlan) {
    return (stagePlan || []).map((stage) => stage.label);
}

/** Used by modal retry to detect the Borrower-forward integration chain. */
export function isDedupeForwardStageLabels(stages) {
    const baseExpected = getDedupeForwardStageLabels(buildDedupeForwardStagePlan(false));
    return baseExpected.every((label) => (stages || []).includes(label));
}