export const PAGE_SIZE = 2
export const CAROUSEL_GRID_CLASS = 'cam-page-applicant-grid cam-page-applicant-grid-carousel'
export const SINGLE_GRID_CLASS = 'cam-page-applicant-grid cam-page-applicant-grid-single'

const SECTION_PAGINATION_ARIA = {
  business: 'Business details applicant pagination',
  beneficiaryIncome: 'Beneficiary income details pagination',
  personal: 'Personal details applicant pagination',
  bankAccount: 'Bank account details applicant pagination',
  exposure: 'Exposure details applicant pagination',
  creditBureau: 'Credit bureau details applicant pagination',
  fiResidence: 'Current FI applicant pagination',
  permanentFi: 'Permanent FI applicant pagination',
  fiRegistered: 'Registered FI applicant pagination',
  fiOffice: 'Office FI applicant pagination',
  brief: 'Brief about applicants credit assessment pagination',
  income: 'Income details applicant pagination',
  financial: 'Financial performance applicant pagination',
  riskProfile: 'Risk profile applicant pagination',
  declaration: 'Declaration applicant pagination'
}

export const INITIAL_PAGINATION_OFFSETS = {
  business: 0,
  beneficiaryIncome: 0,
  personal: 0,
  bankAccount: 0,
  exposure: 0,
  creditBureau: 0,
  fiResidence: 0,
  permanentFi: 0,
  fiRegistered: 0,
  fiOffice: 0,
  brief: 0,
  income: 0,
  financial: 0,
  riskProfile: 0,
  declaration: 0
}

export function createInitialOffsets() {
  return { ...INITIAL_PAGINATION_OFFSETS }
}

export function getSectionItems(component, sectionKey) {
  const itemsBySection = {
    business: component.businessDetailSections,
    beneficiaryIncome: component.beneficiaryIncomeSections,
    personal: component.applicantColumns,
    bankAccount: component.bankAccountColumns,
    exposure: component.exposureSections,
    creditBureau: component.creditBureauColumns,
    fiResidence: component.fiResidenceDetailSections,
    permanentFi: component.permanentFiDetailSections,
    fiRegistered: component.fiRegisteredDetailSections,
    fiOffice: component.fiOfficeDetailSections,
    brief: component.briefColumns,
    income: component.incomeDetailSections,
    financial: component.financialPerformanceSections,
    riskProfile: component.riskProfileSections,
    declaration: component.declarationSections
  }
  return itemsBySection[sectionKey] || []
}

export function resolveGridClass(total) {
  return total === 1 ? SINGLE_GRID_CLASS : CAROUSEL_GRID_CLASS
}

export function buildPaginationNav(sectionKey, total, offset) {
  const rangeStart = total > 0 ? offset + 1 : 0
  const rangeEnd = Math.min(offset + PAGE_SIZE, total)
  const showPagination = total > PAGE_SIZE

  return {
    showPagination,
    isPrevDisabled: !showPagination || offset <= 0,
    isNextDisabled: !showPagination || offset + PAGE_SIZE >= total,
    paginationLabel: total > 0
      ? `Showing ${rangeStart} to ${rangeEnd} of ${total} applicants`
      : '',
    paginationAriaLabel: SECTION_PAGINATION_ARIA[sectionKey] || 'Applicant pagination'
  }
}

export function slicePageItems(items, offset) {
  return (items || []).slice(offset, offset + PAGE_SIZE)
}

export function buildCarouselState(component) {
  const state = {}

  for (const sectionKey of Object.keys(INITIAL_PAGINATION_OFFSETS)) {
    const items = getSectionItems(component, sectionKey)
    const offset = component.carouselOffsets[sectionKey] || 0

    state[sectionKey] = {
      items: slicePageItems(items, offset),
      nav: buildPaginationNav(sectionKey, items.length, offset),
      gridClass: resolveGridClass(items.length)
    }
  }

  return state
}

export function handlePaginationPrev(component, event) {
  const sectionKey = event.currentTarget?.dataset?.section
  if (!sectionKey) {
    return
  }

  const total = getSectionItems(component, sectionKey).length
  if (total <= PAGE_SIZE) {
    return
  }

  const offset = component.carouselOffsets[sectionKey] || 0
  if (offset <= 0) {
    return
  }

  component.carouselOffsets = {
    ...component.carouselOffsets,
    [sectionKey]: Math.max(0, offset - PAGE_SIZE)
  }
  component.carouselState = buildCarouselState(component)
}

export function handlePaginationNext(component, event) {
  const sectionKey = event.currentTarget?.dataset?.section
  if (!sectionKey) {
    return
  }

  const total = getSectionItems(component, sectionKey).length
  if (total <= PAGE_SIZE) {
    return
  }

  const offset = component.carouselOffsets[sectionKey] || 0

  if (offset + PAGE_SIZE >= total) {
    return
  }

  component.carouselOffsets = {
    ...component.carouselOffsets,
    [sectionKey]: offset + PAGE_SIZE
  }
  component.carouselState = buildCarouselState(component)
}

export function resetPagination(component) {
  component.carouselOffsets = createInitialOffsets()
  component.carouselState = buildCarouselState(component)
}