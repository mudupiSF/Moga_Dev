import { LightningElement, api, track } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import getGstPerformanceData from '@salesforce/apex/FinancialPerformanceGridController.getGstPerformanceData'
import saveGstPerformanceData from '@salesforce/apex/FinancialPerformanceGridController.saveGstPerformanceData'

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
]

const FINANCIAL_YEAR_OPTIONS = [
  { label: 'FY 21-22', value: 'FY2021' },
  { label: 'FY 22-23', value: 'FY2022' },
  { label: 'FY 23-24', value: 'FY2023' },
  { label: 'FY 24-25', value: 'FY2024' },
  { label: 'FY 25-26', value: 'FY2025' }
]

const buildEmptyMonthRows = () =>
  MONTHS.map((month) => ({
    month,
    amount: '',
    recordId: null
  }))

export default class FinancialPerformanceGrid extends LightningElement {
  _applicantIncomeId
  _applicantId
  _isReadOnly = false

  financialYearOptions = FINANCIAL_YEAR_OPTIONS
  selectedFinancialYear = FINANCIAL_YEAR_OPTIONS[0].value
  financialPerformanceId = null
  gstrTotal = 0
  isLoading = false
  isSaving = false

  @track monthRows = buildEmptyMonthRows()
  @track yearDataByName = {}

  get saveLabel(){
    return 'Save '+this.selectedYearLabel;
  }

  @api
  get applicantIncomeId() {
    return this._applicantIncomeId
  }
  set applicantIncomeId(value) {
    if (value === this._applicantIncomeId) {
      return
    }
    this._applicantIncomeId = value
    if (value) {
      this.loadGstData()
    } else {
      this.resetGridState()
    }
  }

  @api
  get isReadOnly() {
    return this._isReadOnly
  }
  set isReadOnly(value) {
    this._isReadOnly = value === true || value === 'true'
  }

  @api
  get applicantId() {
    return this._applicantId
  }
  set applicantId(value) {
    this._applicantId = value
  }

  get selectedYearLabel() {
    const match = this.financialYearOptions.find(
      (option) => option.value === this.selectedFinancialYear
    )
    return match?.label || ''
  }

  get showSaveButton() {
    return !this.isReadOnly && !!this.applicantId
  }

  get isBusy() {
    return this.isLoading || this.isSaving
  }

  connectedCallback() {
    if (this.applicantIncomeId) {
      this.loadGstData()
    }
  }

  resetGridState() {
    this.yearDataByName = {}
    this.financialPerformanceId = null
    this.selectedFinancialYear = FINANCIAL_YEAR_OPTIONS[0].value
    this.monthRows = buildEmptyMonthRows()
    this.recalculateTotal()
  }

  async loadGstData() {
    if (!this.applicantIncomeId) {
      return
    }

    this.isLoading = true
    try {
      const response = await this.fetchGstPerformanceData()
      this.yearDataByName = this.buildYearDataMap(response?.records || [])
      this.selectedFinancialYear = this.resolveDefaultFinancialYear()
      this.applySelectedYearToGrid()
    } catch (error) {
      this.showToast('Error', this.getErrorMessage(error), 'error')
    } finally {
      this.isLoading = false
    }
  }

  async fetchGstPerformanceData() {
    return getGstPerformanceData({
      applicantIncomeId: this.applicantIncomeId
    })
  }

  notifyParentSaved(applicantIncomeId) {
    this.dispatchEvent(
      new CustomEvent('gstsaved', {
        bubbles: true,
        composed: true,
        detail: { applicantIncomeId }
      })
    )
  }

  buildYearDataMap(records) {
    const yearDataMap = {}
    records.forEach((record) => {
      if (!record?.financialYearName) {
        return
      }
      const monthsByName = {}
      ;(record.months || []).forEach((monthRow) => {
        if (monthRow?.month) {
          monthsByName[monthRow.month] = monthRow
        }
      })
      yearDataMap[record.financialYearName] = {
        financialPerformanceId: record.financialPerformanceId,
        monthsByName
      }
    })
    return yearDataMap
  }

  resolveDefaultFinancialYear() {
    const yearsWithData = FINANCIAL_YEAR_OPTIONS.filter(
      (option) => this.yearDataByName[option.value]
    )
    if (yearsWithData.length === 1) {
      return yearsWithData[0].value
    }
    if (yearsWithData.length > 0) {
      return yearsWithData[0].value
    }
    return FINANCIAL_YEAR_OPTIONS[0].value
  }

  applySelectedYearToGrid() {
    const yearData = this.yearDataByName[this.selectedFinancialYear]
    this.financialPerformanceId = yearData?.financialPerformanceId || null
    this.monthRows = MONTHS.map((month) => {
      const saved = yearData?.monthsByName?.[month]
      return {
        month,
        amount: saved?.amount ?? '',
        recordId: saved?.recordId ?? null
      }
    })
    this.recalculateTotal()
  }

  async handleFinancialYearChange(event) {
    this.selectedFinancialYear = event.detail.value
    if (this.applicantIncomeId) {
      try {
        const response = await this.fetchGstPerformanceData()
        this.yearDataByName = this.buildYearDataMap(response?.records || [])
      } catch (error) {
        this.showToast('Error', this.getErrorMessage(error), 'error')
      }
    }
    this.applySelectedYearToGrid()
  }

  handleAmountChange(event) {
    const month = event.target.dataset.month
    const amount = event.detail.value
    this.monthRows = this.monthRows.map((row) =>
      row.month === month ? { ...row, amount } : row
    )
    this.recalculateTotal()
  }

  recalculateTotal() {
    this.gstrTotal = this.monthRows.reduce((sum, row) => {
      const value = parseFloat(row.amount)
      return sum + (Number.isNaN(value) ? 0 : value)
    }, 0)
  }

  buildSavePayload() {
    return this.monthRows
      .filter((row) => row.amount !== '' && row.amount !== null && row.amount !== undefined)
      .map((row) => ({
        month: row.month,
        amount: parseFloat(row.amount),
        recordId: row.recordId
      }))
  }

  async handleSave() {
    if (this.isReadOnly || !this.applicantId || this.isSaving) {
      return
    }

    const payload = this.buildSavePayload()
    if (!payload.length) {
      this.showToast('Error', 'Please enter GST amount for at least one month.', 'error')
      return
    }

    this.isSaving = true
    try {
      const result = await saveGstPerformanceData({
        applicantId: this.applicantId,
        applicantIncomeId: this.applicantIncomeId,
        financialYearName: this.selectedFinancialYear,
        monthsJson: JSON.stringify(payload)
      })

      if (result?.applicantIncomeId) {
        this._applicantIncomeId = result.applicantIncomeId
        this.notifyParentSaved(result.applicantIncomeId)
      }

      const savedMonthsByName = {}
      ;(result?.months || []).forEach((monthRow) => {
        if (monthRow?.month) {
          savedMonthsByName[monthRow.month] = monthRow
        }
      })

      this.financialPerformanceId = result?.financialPerformanceId || this.financialPerformanceId
      this.monthRows = this.monthRows.map((row) => {
        const saved = savedMonthsByName[row.month]
        if (!saved) {
          return row
        }
        return {
          ...row,
          amount: saved.amount ?? row.amount,
          recordId: saved.recordId ?? row.recordId
        }
      })

      this.yearDataByName = {
        ...this.yearDataByName,
        [this.selectedFinancialYear]: {
          financialPerformanceId: this.financialPerformanceId,
          monthsByName: this.monthRows.reduce((map, row) => {
            map[row.month] = {
              month: row.month,
              amount: row.amount,
              recordId: row.recordId
            }
            return map
          }, {})
        }
      }

      this.showToast('Success', 'GST details saved successfully.', 'success')
    } catch (error) {
      this.showToast('Error', this.getErrorMessage(error), 'error')
    } finally {
      this.isSaving = false
    }
  }

  getErrorMessage(error) {
    return error?.body?.message || error?.message || 'An unexpected error occurred.'
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    )
  }
}