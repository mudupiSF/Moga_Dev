import { LightningElement, api, track } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'

const APEX_CLASS = 'IncomeSourceCaptureController'
const ACTION_GET_INCOME_SOURCES = 'getIncomeSources'
const ACTION_SAVE_INCOME_SOURCE = 'saveIncomeSource'
const ACTION_DELETE_INCOME_SOURCE = 'deleteIncomeSource'
const ACTION_UPSERT_INCOME_SOURCE_DOCUMENT = 'upsertIncomeSourceDocument'
const ACTION_DELETE_INCOME_SOURCE_DOCUMENT = 'deleteIncomeSourceDocument'

const INCOME_SOURCE_ACCEPTED_FORMATS = ['.pdf', '.png', '.jpg', '.jpeg']

const INCOME_SOURCE_UPLOAD_LABELS = {
  ITR: 'Upload ITR or Form 16',
  Financials: 'Upload Financial Statements',
  Banking: 'Upload Bank Statements',
  'Property Income': 'Upload Property Documents',
  'Agricultural Income': 'Upload Agricultural Income Documents',
  GST: 'Upload GST Returns (last 12 months)'
}

const INCOME_SOURCE_OPTIONS = [
  { label: 'GST' , value: 'GST' },
  { label: 'ITR', value: 'ITR' },
  { label: 'Financials', value: 'Financials' },
  { label: 'Agricultural Income', value: 'Agricultural Income' },
  { label: 'Property Income', value: 'Property Income' },
  { label: 'Bank Balance - Gross Amount', value: 'Banking' }
]

const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec']

const buildLast3MonthsLabels = () => {
  const labels = {}
  let currentDate = new Date()
  currentDate = new Date(currentDate.setMonth(currentDate.getMonth() - 1))
  labels.lastMonthDay1 = `${MONTH_NAMES[currentDate.getMonth()]} 1st`
  labels.lastMonthDay10 = `${MONTH_NAMES[currentDate.getMonth()]} 10th`
  labels.lastMonthDay20 = `${MONTH_NAMES[currentDate.getMonth()]} 20th`
  currentDate = new Date(currentDate.setMonth(currentDate.getMonth() - 1))
  labels.last2ndMonthDay1 = `${MONTH_NAMES[currentDate.getMonth()]} 1st`
  labels.last2ndMonthDay10 = `${MONTH_NAMES[currentDate.getMonth()]} 10th`
  labels.last2ndMonthDay20 = `${MONTH_NAMES[currentDate.getMonth()]} 20th`
  currentDate = new Date(currentDate.setMonth(currentDate.getMonth() - 1))
  labels.last3rdMonthDay1 = `${MONTH_NAMES[currentDate.getMonth()]} 1st`
  labels.last3rdMonthDay10 = `${MONTH_NAMES[currentDate.getMonth()]} 10th`
  labels.last3rdMonthDay20 = `${MONTH_NAMES[currentDate.getMonth()]} 20th`
  return labels
}

const createEmptyLast3MonthsValues = () => ({
  lastMonthDay1: '',
  lastMonthDay10: '',
  lastMonthDay20: '',
  last2ndMonthDay1: '',
  last2ndMonthDay10: '',
  last2ndMonthDay20: '',
  last3rdMonthDay1: '',
  last3rdMonthDay10: '',
  last3rdMonthDay20: ''
})

const YES_NO_OPTIONS = [
  { label: 'Yes', value: 'Yes' },
  { label: 'No', value: 'No' }
]

const ASSESSMENT_YEAR_OPTIONS = [
  { label: '2024-25', value: '2024-25' },
  { label: '2023-24', value: '2023-24' },
  { label: '2022-23', value: '2022-23' }
]

const PROPERTY_AREA_UNIT_OPTIONS = [
  { label: 'Acre', value: 'Acre' },
  { label: 'Sq Ft', value: 'Sq Ft' },
  { label: 'Cent', value: 'Cent' }
]

const TYPE_OF_PROPERTY_OPTIONS = [
  { label: 'Residential', value: 'Residential' },
  { label: 'Commercial', value: 'Commercial' },
  { label: 'Agricultural', value: 'Agricultural' }
]

const OWNERSHIP_OPTIONS = [
  { label: 'Self', value: 'Self' },
  { label: 'Joint', value: 'Joint' },
  { label: 'Family', value: 'Family' }
]

const CROPS_PER_YEAR_OPTIONS = [
  { label: '1', value: '1' },
  { label: '2', value: '2' },
  { label: '3', value: '3' }
]

const AGRICULTURAL_INCOME_FIELDS = new Set(['yieldPerAcre', 'pricePerUnit'])

const calculateAgriculturalIncome = (source) => {
  const yieldPerAcre = parseFloat(source.yieldPerAcre)
  const pricePerUnit = parseFloat(source.pricePerUnit)
  if (Number.isNaN(yieldPerAcre) || Number.isNaN(pricePerUnit)) {
    return ''
  }
  return yieldPerAcre * pricePerUnit
}

const createEmptyItrSection = (id = 0) => ({
  id,
  assessmentYear: '',
  itrLastYearDate: '',
  incomeLastYear: '',
  doYouHaveAnotherITR: false
})

const mergeIncomeSource = (loaded, index) => {
  const empty = createEmptyIncomeSource(index)
  const hasSavedRecord = !!loaded.recordId && !!loaded.incomeSource
  return {
    ...empty,
    ...loaded,
    id: String(index),
    heading: `Income Source ${index}`,
    isOpen: loaded.isOpen !== undefined ? loaded.isOpen : !hasSavedRecord,
    incomeSourceLocked: loaded.incomeSourceLocked === true || hasSavedRecord,
    last3MonthsValues: {
      ...empty.last3MonthsValues,
      ...(loaded.last3MonthsValues || {})
    },
    itrSections: loaded.itrSections?.length
      ? loaded.itrSections.map((section, sectionIndex) => ({
        ...createEmptyItrSection(sectionIndex),
        ...section,
        id: section.id ?? sectionIndex
      }))
      : empty.itrSections
  }
}

const createEmptyIncomeSource = (index) => ({
  id: String(index),
  heading: `Income Source ${index}`,
  isOpen: true,
  incomeSource: '',
  itrSections: [createEmptyItrSection(0)],
  financialYear: '',
  totalIncome: '',
  totalExpense: '',
  pbtValue: '',
  patValue: '',
  cashProfit: '',
  shareholderFunds: '',
  securedLoans: '',
  workingCapital: '',
  unsecuredLoans: '',
  currentLiabilities: '',
  sundryCreditors: '',
  currentAssets: '',
  sundryDebtors: '',
  fixedAssets: '',
  nonCurrentAssets: '',
  cashAndBankBalances: '',
  financialAnotherEntry: '',
  propertyAreaUnit: '',
  propertyArea: '',
  cropsPerYear: '',
  yieldPerAcre: '',
  pricePerUnit: '',
  acreUnit: '',
  agriculturalIncome: '',
  typeOfProperty: '',
  surveyNumberAddress: '',
  marketValue: '',
  ownership: '',
  incomeFromProperty: '',
  proofGiven: '',
  bankName: '',
  accountNumber: '',
  bankBranch: '',
  accountOpeningDate: '',
  last3MonthsValues: createEmptyLast3MonthsValues(),
  primaryIncomeSource: false,
  documentUploaded: false,
  recordId: null,
  document: null,
  incomeSourceLocked: false
})

export default class IncomeSourceCapture extends LightningElement {
  _recordId
  _applicantId
  _isStagePast = false

  @api
  set isStagePast(value) {
    this._isStagePast = value === true || value === 'true'
  }
  get isStagePast() {
    return this._isStagePast
  }

  @api
  get recordId() {
    return this._recordId
  }
  set recordId(value) {
    this._recordId = value
    this.loadIncomeSourcesIfReady()
  }

  @api
  get applicantId() {
    return this._applicantId
  }
  set applicantId(value) {
    if (value === this._applicantId) {
      return
    }
    this._applicantId = value
    this.resetForApplicantChange()
  }

  @track incomeSources = []
  @track isLoading = false
  last3MonthsLabels = buildLast3MonthsLabels()
  _loadSeq = 0

  connectedCallback() {
    this.loadIncomeSourcesIfReady()
  }

  get incomeSourceAcceptedFormats() {
    return INCOME_SOURCE_ACCEPTED_FORMATS
  }

  get isReadOnly() {
    return this.isStagePast
  }

  get hasIncomeSources() {
    return this.incomeSources.length > 0
  }

  get displayIncomeSources() {
    return this.incomeSources.map((source) => ({
      ...source,
      accordionItemClass: this.getAccordionItemClass(source.isOpen),
      accordionTriggerClass: this.getAccordionTriggerClass(source.isOpen),
      chevronIcon: this.getChevronIcon(source.isOpen),
      incomeSourceOptions: this.getIncomeSourceOptionsForSection(source.id, source.incomeSource),
      isIncomeSourceDisabled: this.isReadOnly || source.incomeSourceLocked === true,
      showDeleteButton: !this.isReadOnly,
      showUploadButton:
        !!source.incomeSource &&
        !!INCOME_SOURCE_UPLOAD_LABELS[source.incomeSource] &&
        (source.incomeSource !== 'GST' || !!source.recordId),
      uploadButtonLabel: INCOME_SOURCE_UPLOAD_LABELS[source.incomeSource] || '',
      showSectionActions: !this.isReadOnly && !!source.incomeSource,
      showItrSection: source.incomeSource === 'ITR',
      showFinancialSection: source.incomeSource === 'Financials',
      showGstSection: source.incomeSource === 'GST',
      showAgricultureSection: source.incomeSource === 'Agricultural Income',
      showPropertySection: source.incomeSource === 'Property Income',
      showBankingSection: source.incomeSource === 'Banking',
      showUploadInput: !source.documentUploaded && !this.isReadOnly,
      documentFileName: source.document?.fileName || '',
      showDocumentDelete: source.documentUploaded && !this.isReadOnly,
      showFinancialPerformanceGridButton: source.incomeSource === 'Financials'
    }))
  }

  getIncomeSourceOptionsForSection(sourceId, currentValue) {
    const takenValues = new Set(
      this.incomeSources
        .filter((source) => source.id !== sourceId && source.incomeSource)
        .map((source) => source.incomeSource)
    )
    return INCOME_SOURCE_OPTIONS.filter(
      (option) => !takenValues.has(option.value) || option.value === currentValue
    )
  }

  get maxAccountOpeningDate() {
    return new Date().toISOString().split('T')[0]
  }

  get assessmentYearOptions() {
    return ASSESSMENT_YEAR_OPTIONS
  }

  get financialYearOptions() {
    return ASSESSMENT_YEAR_OPTIONS
  }

  get propertyAreaUnitOptions() {
    return PROPERTY_AREA_UNIT_OPTIONS
  }

  get typeOfPropertyOptions() {
    return TYPE_OF_PROPERTY_OPTIONS
  }

  get ownershipOptions() {
    return OWNERSHIP_OPTIONS
  }

  get cropsPerYearOptions() {
    return CROPS_PER_YEAR_OPTIONS
  }

  get yesNoOptions() {
    return YES_NO_OPTIONS
  }

  @api
  addIncomeSource() {
    if (this.isReadOnly) {
      return
    }
    if (this.incomeSources.length >= INCOME_SOURCE_OPTIONS.length) {
      return
    }
    const nextIndex = this.incomeSources.length + 1
    this.incomeSources = [
      ...this.incomeSources,
      createEmptyIncomeSource(nextIndex)
    ]
  }

  resetForApplicantChange() {
    this.incomeSources = []
    this.loadIncomeSourcesIfReady()
  }

  async loadIncomeSourcesIfReady() {
    if (!this.recordId || !this.applicantId) {
      return
    }

    const loadSeq = ++this._loadSeq
    this.isLoading = true
    try {
      const result = await this.invokeReadAction(ACTION_GET_INCOME_SOURCES)
      if (loadSeq !== this._loadSeq) {
        return
      }
      const loadedSources = result?.incomeSources || []
      this.incomeSources = loadedSources.map((source, index) => mergeIncomeSource(source, index + 1))
    } catch (error) {
      if (loadSeq === this._loadSeq) {
        this.showToast('Error', error?.body?.message || 'Failed to load income sources', 'error')
      }
    } finally {
      if (loadSeq === this._loadSeq) {
        this.isLoading = false
      }
    }
  }

  handleAccordionToggle(event) {
    const sourceId = event.currentTarget?.dataset?.sourceId
    if (!sourceId) {
      return
    }
    this.incomeSources = this.incomeSources.map((source) => (
      source.id === sourceId
        ? { ...source, isOpen: !source.isOpen }
        : source
    ))
  }

  handleIncomeSourceTypeChange(event) {
    const sourceId = event.target?.dataset?.sourceId
    const value = event.detail?.value ?? ''
    if (!sourceId || this.isReadOnly) {
      return
    }
    const source = this.incomeSources.find((item) => item.id === sourceId)
    if (source?.incomeSourceLocked) {
      return
    }
    this.incomeSources = this.incomeSources.map((source) => (
      source.id === sourceId
        ? { ...source, incomeSource: value, documentUploaded: false }
        : source
    ))
  }

  async handleDeleteIncomeSource(event) {
    const sourceId = event.currentTarget?.dataset?.sourceId
    if (!sourceId || this.isReadOnly) {
      return
    }
    const source = this.incomeSources.find((item) => item.id === sourceId)
    if (!source?.incomeSource) {
      return
    }

    try {
      await this.invokeSaveAction(ACTION_DELETE_INCOME_SOURCE, {
        incomeSource: source.incomeSource
      })
      this.incomeSources = this.renumberIncomeSources(
        this.incomeSources.filter((item) => item.id !== sourceId)
      )
      this.showToast('Success', `${source.heading} deleted successfully.`, 'success')
    } catch (error) {
      this.showToast('Error', error?.body?.message || 'Failed to delete income source', 'error')
    }
  }

  async handleUploadFinished(event) {
    const sourceId = event.target?.dataset?.sourceId
    const file = event.detail?.files?.[0]
    if (!sourceId || !file || this.isReadOnly) {
      return
    }
    const source = this.incomeSources.find((item) => item.id === sourceId)
    if (!source?.incomeSource) {
      return
    }

    try {
      const response = await this.invokeSaveAction(ACTION_UPSERT_INCOME_SOURCE_DOCUMENT, {
        incomeSource: source.incomeSource,
        contentDocumentId: file.documentId,
        contentVersionId: file.contentVersionId,
        fileName: file.name
      })
      this.incomeSources = this.incomeSources.map((item) => (
        item.id === sourceId
          ? {
            ...item,
            recordId: response?.applicantIncomeId || item.recordId,
            documentUploaded: true,
            document: {
              fileName: file.name || '',
              contentDocumentId: file.documentId || null,
              contentVersionId: file.contentVersionId || null,
              checklistId: response?.checklistId || null,
              applicantIncomeId: response?.applicantIncomeId || item.recordId
            }
          }
          : item
      ))
      this.showToast(
        'Success',
        `${INCOME_SOURCE_UPLOAD_LABELS[source.incomeSource] || 'Document'} uploaded successfully.`,
        'success'
      )
    } catch (error) {
      this.showToast('Error', error?.body?.message || 'Failed to upload document', 'error')
    }
  }

  async handleDocumentDelete(event) {
    const sourceId = event.currentTarget?.dataset?.sourceId
    if (!sourceId || this.isReadOnly) {
      return
    }
    const source = this.incomeSources.find((item) => item.id === sourceId)
    if (!source?.recordId || !source?.incomeSource) {
      return
    }

    try {
      await this.invokeSaveAction(ACTION_DELETE_INCOME_SOURCE_DOCUMENT, {
        applicantIncomeId: source.recordId,
        incomeSource: source.incomeSource
      })
      this.incomeSources = this.incomeSources.map((item) => (
        item.id === sourceId
          ? { ...item, documentUploaded: false, document: null }
          : item
      ))
    } catch (error) {
      this.showToast('Error', error?.body?.message || 'Failed to remove document', 'error')
    }
  }

  async handleSubmit(event) {
    const sourceId = event.currentTarget?.dataset?.sourceId
    if (!sourceId || this.isReadOnly) {
      return
    }
    const source = this.incomeSources.find((item) => item.id === sourceId)
    if (!source?.incomeSource) {
      return
    }
    if (!source.documentUploaded) {
      this.showToast(
        'Validation Error',
        `Please ${INCOME_SOURCE_UPLOAD_LABELS[source.incomeSource] || 'upload the required document'}.`,
        'error'
      )
      return
    }

    try {
      const response = await this.invokeSaveAction(ACTION_SAVE_INCOME_SOURCE, {
        data: JSON.stringify(source)
      })
      const savedSource = response?.incomeSource
      if (savedSource) {
        const currentIndex = this.incomeSources.findIndex((item) => item.id === sourceId)
        this.incomeSources = this.incomeSources.map((item, index) => (
          item.id === sourceId
            ? {
              ...mergeIncomeSource(savedSource, currentIndex >= 0 ? currentIndex + 1 : index + 1),
              isOpen: false,
              incomeSourceLocked: true
            }
            : item
        ))
      }
      this.showToast('Success', `${source.heading} saved successfully.`, 'success')
    } catch (error) {
      this.showToast('Error', error?.body?.message || 'Failed to save income source', 'error')
    }
  }

  renumberIncomeSources(sources) {
    return sources.map((source, index) => ({
      ...source,
      id: String(index + 1),
      heading: `Income Source ${index + 1}`
    }))
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }))
  }

  handlePrimaryToggle(event) {
    const sourceId = event.target?.dataset?.sourceId
    const isChecked = event.target.checked
    if (!sourceId || this.isReadOnly) {
      return
    }
    this.incomeSources = this.incomeSources.map((source) => {
      if (source.id === sourceId) {
        return { ...source, primaryIncomeSource: isChecked }
      }
      if (isChecked) {
        return { ...source, primaryIncomeSource: false }
      }
      return source
    })
  }

  handleFieldChange(event) {
    const sourceId = event.target?.dataset?.sourceId
    const field = event.target?.dataset?.field
    const balanceKey = event.target?.dataset?.balanceKey
    if (!sourceId || (!field && !balanceKey)) {
      return
    }
    const value = event.detail?.value ?? event.target?.value ?? event.target?.checked ?? ''
    this.incomeSources = this.incomeSources.map((source) => {
      if (source.id !== sourceId) {
        return source
      }
      if (balanceKey) {
        return {
          ...source,
          last3MonthsValues: {
            ...source.last3MonthsValues,
            [balanceKey]: value
          }
        }
      }
      const updatedSource = { ...source, [field]: value }
      if (AGRICULTURAL_INCOME_FIELDS.has(field)) {
        updatedSource.agriculturalIncome = calculateAgriculturalIncome(updatedSource)
      }
      return updatedSource
    })
  }

  handleGstSaved(event) {
    const sourceId = event.currentTarget?.dataset?.sourceId
    if (!sourceId) {
      return
    }
    const { applicantIncomeId } = event.detail || {}
    if (!applicantIncomeId) {
      return
    }
    this.incomeSources = this.incomeSources.map((source) => (
      source.id === sourceId
        ? { ...source, recordId: applicantIncomeId, incomeSourceLocked: true }
        : source
    ))
  }

  handleOpenFinancialPerformanceGrid() {
    if (this.isReadOnly || !this.recordId) {
      return
    }

    const params = new URLSearchParams({
      loanId: this.recordId,
      applicantId: this.applicantId || ''
    })
    const url = `/apex/financeGridPage?${params.toString()}`
    const width = window.screen.availWidth || 1200
    const height = window.screen.availHeight || 800
    const features = [
      `width=${width}`,
      `height=${height}`,
      'left=0',
      'top=0',
      'resizable=yes',
      'scrollbars=yes',
      'toolbar=no',
      'status=no'
    ].join(',')

    const popup = window.open(url, 'financeGridPage', features)
    if (popup?.focus) {
      popup.focus()
    }
  }

  handleItrFieldChange(event) {
    const sourceId = event.target?.dataset?.sourceId
    const sectionId = event.target?.dataset?.sectionId
    const field = event.target?.dataset?.field
    if (!sourceId || sectionId == null || !field) {
      return
    }
    const value = field === 'doYouHaveAnotherITR'
      ? event.target.checked
      : (event.detail?.value ?? event.target?.value ?? '')
    this.incomeSources = this.incomeSources.map((source) => {
      if (source.id !== sourceId) {
        return source
      }
      const itrSections = source.itrSections.map((section) => (
        String(section.id) === String(sectionId)
          ? { ...section, [field]: value }
          : section
      ))
      return { ...source, itrSections }
    })
  }

  getAccordionItemClass(isOpen) {
    return isOpen ? 'isc-accordion-item isc-accordion-item-open' : 'isc-accordion-item'
  }

  getAccordionTriggerClass(isOpen) {
    return isOpen ? 'isc-accordion-trigger isc-accordion-trigger-open' : 'isc-accordion-trigger'
  }

  getChevronIcon(isOpen) {
    return isOpen ? 'utility:chevrondown' : 'utility:chevronright'
  }

  invokeReadAction(apexMethodName, params = {}) {
    return getPageData({
      apexClassName: APEX_CLASS,
      apexMethodName,
      recordId: this.recordId,
      params: {
        applicantId: this.applicantId,
        ...params
      }
    })
  }

  invokeSaveAction(apexMethodName, params = {}) {
    return savePageData({
      apexClassName: APEX_CLASS,
      apexMethodName,
      recordId: this.recordId,
      params: {
        applicantId: this.applicantId,
        ...params
      }
    })
  }
}