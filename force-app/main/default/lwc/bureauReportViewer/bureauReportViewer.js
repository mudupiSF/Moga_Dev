import { LightningElement, api } from 'lwc'

const REPORT_DISPLAY_NAMES = {
  CIBIL: 'CIBIL',
  Equifax: 'Equifax',
  CRIF: 'CRIF'
}

export default class BureauReportViewer extends LightningElement {
  @api recordId
  @api isReadOnly = false
  
  _contentVersionId = null
  @api
  get contentVersionId() {
    return this._contentVersionId
  }
  set contentVersionId(value) {
    this._contentVersionId = value
  }

  _applicantId = null
  @api
  get applicantId() {
    return this._applicantId
  }
  set applicantId(value) {
    this._applicantId = value
    if (value) {
      this._reportType = this._applicantId.startsWith('A') ? 'CIBIL' : 'CRIF'
    }
  }

  _reportType = 'CIBIL'

  @api
  get reportType() {
    return this._reportType
  }

  set reportType(value) {
    this._reportType = String(value || 'CIBIL').trim() || 'CIBIL'
  }

  get reportDisplayName() {
    return REPORT_DISPLAY_NAMES[this._reportType] || this._reportType
  }

  get unavailableMessage() {
    return `${this.reportDisplayName} is not available.`
  }

  get showUnavailableState() {
    return !String(this.contentVersionId || '').trim()
  }
}