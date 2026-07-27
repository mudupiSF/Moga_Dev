import {
  BASIC_INFO_FIELD_ICONS,
  LOAN_FIELD_ICONS,
  RISK_PROFILE_BADGE_CLASS
} from './camPageConstants'

const EMPTY_CELL = '—'
const EMPTY_NA = 'N/A'

const APPLICANT_BADGE_CLASS = {
  Borrower: 'cam-page-badge-borrower',
  'Co-borrower': 'cam-page-badge-coborrower',
  Guarantor: 'cam-page-badge-guarantor',
  Beneficiary: 'cam-page-badge-beneficiary'
}

function displayValue(value) {
  if (value === null || value === undefined || String(value).trim() === '') {
    return EMPTY_CELL
  }
  return String(value)
}

function displayNaValue(value) {
  if (value === null || value === undefined || String(value).trim() === '') {
    return EMPTY_NA
  }
  return String(value)
}

function formatExposureCountLabel(count) {
  const total = Number.isFinite(count) ? count : 0
  return total === 1 ? '1 record' : `${total} records`
}

function resolveApplicantBadgeClass(applicantType) {
  return APPLICANT_BADGE_CLASS[applicantType] || 'cam-page-badge-guarantor'
}

function resolveLoanFieldIcon(fieldId) {
  if (!fieldId) {
    return 'utility:text'
  }
  const suffix = String(fieldId).split('-').pop() || ''
  for (const [key, icon] of Object.entries(LOAN_FIELD_ICONS)) {
    if (suffix === key || String(fieldId).includes(`-${key}`)) {
      return icon
    }
  }
  return 'utility:text'
}

function mapFieldRows(fields, formatValue = displayValue) {
  return (fields || []).map((field) => ({
    ...field,
    valueDisplay: formatValue(field?.value)
  }))
}

function mapApplicantFields(fields) {
  return mapFieldRows(fields, displayValue)
}

function mapApplicantSection(section, fieldMapper = mapApplicantFields) {
  const applicantType = String(section?.applicantType || '').trim()
  return {
    ...section,
    badgeClass: resolveApplicantBadgeClass(applicantType),
    fields: fieldMapper(section?.fields)
  }
}

export function normalizeBasicInfoFields(fields) {
  return (fields || []).map((field) => ({
    ...field,
    icon: BASIC_INFO_FIELD_ICONS[field?.id] || 'utility:text',
    valueDisplay: displayValue(field?.value)
  }))
}

export function normalizeFieldRows(fields) {
  return mapFieldRows(fields, displayValue)
}

export function normalizeFieldSection(section) {
  if (!section) {
    return { fields: [] }
  }
  return {
    ...section,
    fields: mapFieldRows(section.fields, displayNaValue)
  }
}

export function normalizeApplicantFieldSection(section) {
  if (!section) {
    return { fields: [] }
  }
  return mapApplicantSection(section, (fields) => mapFieldRows(fields, displayNaValue))
}

export function normalizeRiskProfileSections(sections) {
  return (sections || []).map((section) => {
    const applicantType = String(section?.applicantType || '').trim()
    const riskLevel = section?.riskLevel
    return {
      ...section,
      badgeClass: resolveApplicantBadgeClass(applicantType),
      riskLevelBadgeClass: resolveRiskProfileLevelBadgeClass(riskLevel),
      riskLevelDisplay: formatRiskProfileLevelDisplay(riskLevel)
    }
  })
}

export function normalizeBriefColumns(brief) {
  if (!brief?.sectionTitle) {
    return []
  }

  return (brief.sections || []).map((section) => {
    const applicantType = String(section?.applicantType || '').trim()
    const remarkField = (section?.fields || []).find((field) => field?.id === 'justificationRemark')

    return {
      id: section?.id || `brief-${applicantType}`,
      title: section?.title || applicantType || 'Applicant',
      badgeClass: resolveApplicantBadgeClass(applicantType),
      fieldLabel: remarkField?.label || 'Justification Remark',
      valueDisplay: displayValue(remarkField?.value),
      showCreditAssessmentButton: section?.showCreditAssessmentButton === true
    }
  })
}

export function normalizeExposureSections(sections) {
  return (sections || []).map((section) => {
    const rows = (section?.rows || []).map((row) => ({
      ...row,
      exposureType: displayValue(row?.exposureType),
      dealStage: displayValue(row?.dealStage),
      dealNo: displayValue(row?.dealNo),
      dealDate: displayValue(row?.dealDate),
      product: displayValue(row?.product),
      statusFlag: displayValue(row?.statusFlag),
      financeAmountDisplay: displayValue(row?.financeAmountDisplay),
      sohDisplay: displayValue(row?.sohDisplay),
      overDueDisplay: displayValue(row?.overDueDisplay)
    }))

    const externalExposureRows = (section?.externalExposureRows || []).map((row) => ({
      ...row,
      accountType: displayValue(row?.accountType),
      ownership: displayValue(row?.ownership),
      highCreditDisplay: displayValue(row?.highCreditDisplay),
      currentBalanceDisplay: displayValue(row?.currentBalanceDisplay),
      amountOverdueDisplay: displayValue(row?.amountOverdueDisplay),
      reasonForOverdue: displayValue(row?.reasonForOverdue),
      financierName: displayValue(row?.financierName)
    }))

    return {
      ...section,
      badgeClass: resolveApplicantBadgeClass(String(section?.applicantType || '').trim()),
      bankExposurePanelTitle: 'Exposure',
      externalExposurePanelTitle: 'External Exposure',
      bankExposurePanelAriaLabel: 'Exposure',
      externalExposurePanelAriaLabel: 'External Exposure',
      rows,
      hasRows: rows.length > 0,
      bankExposureCountLabel: formatExposureCountLabel(rows.length),
      externalExposureRows,
      hasExternalExposureRows: externalExposureRows.length > 0,
      externalExposureCountLabel: formatExposureCountLabel(externalExposureRows.length)
    }
  })
}

export function normalizeAssetSections(sections) {
  return (sections || []).map((section) => ({
    ...section,
    showAssetChip: section?.showSubheading === true && !!section?.title,
    listTitle: section?.title || section?.assetId || 'Asset',
    fields: (section?.fields || []).map((field) => ({
      ...field,
      icon: resolveLoanFieldIcon(field?.id),
      valueDisplay: displayValue(field?.value)
    }))
  }))
}

function normalizeIncomeDetailFields(fields) {
  return (fields || []).map((field) => {
    const displayType = String(field?.displayType || 'text')
    const isButton = displayType === 'button'
    const isLink = displayType === 'link'
    const showAction = field?.showAction === true
    const contentVersionId = String(field?.contentVersionId || '').trim()
    const contentDocumentId = String(field?.contentDocumentId || '').trim()
    const fileType = String(field?.fileType || '').trim()

    return {
      ...field,
      isButton,
      isLink,
      showAction,
      hasDocumentLink: showAction && !!(contentDocumentId || contentVersionId),
      contentVersionId,
      contentDocumentId,
      fileType,
      valueDisplay: displayValue(field?.value),
      actionLabel: field?.actionLabel || ''
    }
  })
}

export function normalizeApplicantDetailSections(sections, includeIncomeFieldTypes = false) {
  return (sections || []).map((section) =>
    mapApplicantSection(
      section,
      includeIncomeFieldTypes ? normalizeIncomeDetailFields : mapApplicantFields
    )
  )
}

export function normalizeApplicantColumns(columns) {
  return (columns || []).map((applicant) => ({
    ...applicant,
    kycButtonLabel: 'View KYC',
    badgeClass: resolveApplicantBadgeClass(String(applicant?.applicantType || '').trim()),
    fields: mapApplicantFields(applicant?.fields)
  }))
}

export function normalizeCreditBureauColumns(columns) {
  return (columns || []).map((applicant) => {
    const reportButtons = (applicant?.reportButtons || []).map((button) => {
      const contentVersionId = String(button?.contentVersionId || '').trim()
      const contentDocumentId = String(button?.contentDocumentId || '').trim()
      const fileType = String(button?.fileType || '').trim()
      const hasDocumentLink = button?.hasDocumentLink === true
        && !!(contentDocumentId || contentVersionId)
      const reportType = String(button?.reportType || '').trim()
      return {
        ...button,
        contentVersionId,
        contentDocumentId,
        fileType,
        hasDocumentLink,
        reportType,
        isDisabled: false
      }
    })

    const bureauType = applicant?.bureauType || 'CIBIL'

    return {
      ...applicant,
      bureauType,
      isCrifBureau: bureauType === 'CRIF',
      badgeClass: resolveApplicantBadgeClass(String(applicant?.applicantType || '').trim()),
      reportButtons,
      hasReportButtons: reportButtons.length > 0,
      fields: mapApplicantFields(applicant?.fields)
    }
  })
}

export const normalizeCibilColumns = normalizeCreditBureauColumns

export function normalizeFiDetailSections(sections) {
  return normalizeApplicantDetailSections(sections).map((section) => {
    const fiAction = section?.fiReportAction || {}
    const hasFiLink = fiAction?.hasFiLink === true && !!fiAction?.verificationId

    return {
      ...section,
      fiReportLabel: fiAction?.label || '',
      fiVerificationId: fiAction?.verificationId || '',
      fiInvestigationId: fiAction?.investigationId || '',
      fiComponentName: fiAction?.componentName || '',
      fiHasLink: hasFiLink,
      showFiReportAction: !!fiAction?.label
    }
  })
}

export function normalizeDeclarationSections(sections) {
  return (sections || []).map((section) => ({
    ...section,
    badgeClass: resolveApplicantBadgeClass(String(section?.applicantType || '').trim()),
    items: (section?.items || []).map((item) => {
      const answerDisplay = displayValue(item?.answer)
      return {
        ...item,
        answerDisplay,
        showAnswer: item?.showAnswer === true || answerDisplay !== EMPTY_CELL
      }
    })
  }))
}

export function normalizeFiWaiverRows(rows) {
  return (rows || []).map((row) => ({
    ...row,
    customerTypeDisplay: displayNaValue(row?.customerTypeDisplay),
    currentAddressDisplay: displayNaValue(row?.currentAddressDisplay),
    permanentAddressDisplay: displayNaValue(row?.permanentAddressDisplay),
    officeAddressDisplay: displayNaValue(row?.officeAddressDisplay)
  }))
}

export function normalizeAnnexureRows(rows) {
  return (rows || []).map((row) => {
    const documentType = String(row?.documentType || '').trim()
    const documentName = String(row?.documentName || '').trim()
    const contentVersionId = String(row?.contentVersionId || '').trim()
    const contentDocumentId = String(row?.contentDocumentId || '').trim()
    const fileType = String(row?.fileType || '').trim()

    return {
      ...row,
      documentTypeDisplay: documentType || EMPTY_CELL,
      documentNameDisplay: documentName || EMPTY_CELL,
      hasDocumentLink: row?.hasDocumentLink === true && !!(contentDocumentId || contentVersionId),
      contentVersionId,
      contentDocumentId,
      fileType
    }
  })
}

export function resolveRiskProfileLevelBadgeClass(riskLevel) {
  const normalized = String(riskLevel || '').trim()
  return RISK_PROFILE_BADGE_CLASS[normalized.toUpperCase()] || 'cam-page-risk-badge cam-page-risk-badge-neutral'
}

export function formatRiskProfileLevelDisplay(riskLevel) {
  return displayNaValue(riskLevel)
}