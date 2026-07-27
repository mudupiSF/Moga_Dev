/**
 * Helper for residenceFI.
 */
import getPageData from '@salesforce/apex/GenericPageLayoutController.getFieldConfig'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'
import getUserSessionId from '@salesforce/apex/embedCustomFileUploadController.getUserSessionId'
import deactivateDocument from '@salesforce/apex/DocumentChecklistToggleController.deactivateDocument'
import SPECIAL_ICONS from '@salesforce/resourceUrl/special_icons'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'

const APEX_CLASS = 'FIInvestigationController'
const LOS_GLOBAL_LOADER_EVENT = 'losgloballoader'

export const FI_LABEL = 'Current Residence FI'

const ACTIONS = {
  GET_RESIDENCE_FI: 'getResidenceFiData',
  GET_BY_INVESTIGATION: 'getFiDataByInvestigation',
  SAVE_FI_DATA: 'saveFiData',
  UPDATE_FI_LOCATION: 'updateFiLocation',
  INIT_OR_GET_FI_DOCUMENT: 'initOrGetFiDocument',
  LINK_FI_DOCUMENT: 'linkFiDocument',
  GET_FI_DOCUMENT_PREVIEW: 'getFiDocumentPreviewInfo',
  SAVE_FI_SIGNATURE: 'saveFiSignature'
}

export const DOC_TYPE_FI_SIGNATURE = 'FI Signature'
export const DOC_TYPE_RESIDENCE_FRONT = 'Residence Front View'
export const DOC_TYPE_FI_KYC = 'FI KYC Document'
export const DOC_TYPE_OFFICE_BUILDING_FRONT = 'Office Building Front View'
export const DOC_TYPE_OFFICE_APPROACH_ROAD = 'Office Approach Road'
export const DOC_TYPE_OFFICE_BUILDING_INNER = 'Office Building Inner View'

export const ACCEPTED_UPLOAD_FORMATS = ['.pdf', '.png', '.jpeg', '.jpg']
export const CHUNKY_UPLOAD_ICON_URL = `${SPECIAL_ICONS}/special_icons/upload-file-icon.svg`
export const MAGIC_UPLOAD_MAX_FILES = 5

export const FI_DECISION_OPTIONS = [
  { label: 'Accepted', value: 'Accepted' },
  { label: 'Rejected', value: 'Rejected' }
]

export const RESIDENCE_TYPE_OPTIONS = [
  { label: 'Owned', value: 'Owned' },
  { label: 'Rented', value: 'Rented' },
  { label: 'Company Provided', value: 'Company Provided' },
  { label: 'Parental', value: 'Parental' },
  { label: 'Others', value: 'Others' }
]

export const RELATIONSHIP_OPTIONS = [
  { label: 'Self', value: 'SELF' },
  { label: 'Spouse', value: 'Spouse' },
  { label: 'Parent', value: 'Parent' },
  { label: 'Sibling', value: 'Sibling' },
  { label: 'Other', value: 'Other' }
]

export const FI_OBSERVATION_OPTIONS = [
  { label: 'Positive', value: 'Positive' },
  { label: 'Negative', value: 'Negative' },
  { label: 'Refer to Credit', value: 'Refer to Credit' },
  { label: 'Inconclusive', value: 'Inconclusive' }
]

export const PROFILE_TO_PRODUCT_MATCH_OPTIONS = [
  { label: 'Yes', value: 'Yes' },
  { label: 'No', value: 'No' }
]

export const YES_NO_OPTIONS = [
  { label: 'Yes', value: 'Yes' },
  { label: 'No', value: 'No' }
]

export const TOTAL_BUSINESS_STABILITY_OPTIONS = [
  { label: '<1 Year', value: '<1 Year' },
  { label: 'B/w 1-2 Years', value: 'B/w 1-2 Years' },
  { label: 'B/w 2-3 Years', value: 'B/w 2-3 Years' },
  { label: '>3 years', value: '>3 years' },
  { label: '> 5 years', value: '> 5 years' }
]

export const BUSINESS_PREMISE_NI_OPTIONS = [
  { label: 'Owned', value: 'Owned' },
  { label: 'Parent Owned', value: 'Parent Owned' },
  { label: 'Co Lease', value: 'Co Lease' },
  { label: 'Rented', value: 'Rented' }
]

export const OFFICE_BUSINESS_TYPE_OPTIONS = [
  { label: 'Manufacturing', value: 'Manufacturing' },
  { label: 'Trading', value: 'Trading' },
  { label: 'Services', value: 'Services' },
  { label: 'Professional', value: 'Professional' },
  { label: 'Other', value: 'Other' }
]

export const LOCATION_OPTIONS = [
  { label: 'Commercial', value: 'Commercial' },
  { label: 'Residential', value: 'Residential' },
  { label: 'Industrial', value: 'Industrial' },
  { label: 'Mixed', value: 'Mixed' }
]

export const POLITICAL_PHOTO_OPTIONS = [
  { label: 'Available', value: 'Available' },
  { label: 'Not Available', value: 'Not Available' }
]

export const OFFICE_BUSINESS_SIZE_OPTIONS = [
  { label: 'Below 200', value: 'Below 200' },
  { label: '200-500', value: '200-500' },
  { label: '500-1000', value: '500-1000' },
  { label: 'Above 1000', value: 'Above 1000' }
]

export const NAME_TEXT_PATTERN = "[A-Za-z\\s.'-]*"
export const NAME_TEXT_PATTERN_MESSAGE = 'Enter letters only.'

export function resolveOptionLabel(value, options = []) {
  const normalized = (value ?? '').toString().trim()
  if (!normalized) {
    return ''
  }
  const match = options.find((option) => option.value === normalized)
  return match?.label ?? normalized
}

export function formatBooleanDisplay(value) {
  if (value === true || value === 'true') {
    return 'Yes'
  }
  if (value === false || value === 'false') {
    return 'No'
  }
  return ''
}

/** Indian mobile: 10 digits, first digit 6–9. */
const MOBILE_REGEX = /^[6-9]\d{9}$/

/** Landline / phone: 6–11 digits. */
const PHONE_REGEX = /^\d{6,11}$/

const MOBILE_MAX_LENGTH = 10
const PHONE_MAX_LENGTH = 11

function sanitizeDigits(value, maxLength) {
  return String(value || '').replace(/\D/g, '').slice(0, maxLength)
}

function sanitizeDecimalYear(value) {
  let raw = String(value ?? '').replace(/[^\d.]/g, '')
  const dotIndex = raw.indexOf('.')
  if (dotIndex === -1) {
    return raw.slice(0, 3)
  }
  const intPart = raw.slice(0, dotIndex).slice(0, 3)
  const decPart = raw.slice(dotIndex + 1).replace(/\./g, '').slice(0, 1)
  if (raw.endsWith('.') && !decPart) {
    return `${intPart}.`
  }
  return decPart ? `${intPart}.${decPart}` : intPart
}

function sanitizeNameText(value) {
  return String(value ?? '').replace(/[^A-Za-z\s.'-]/g, '')
}

export function getMobileValidationError(value, { required = false } = {}) {
  const trimmed = String(value || '').trim()
  if (!trimmed) {
    return required ? 'Mobile number is required.' : ''
  }
  if (!MOBILE_REGEX.test(trimmed)) {
    return 'Enter a valid 10-digit Indian mobile number starting with 6-9.'
  }
  return ''
}

export function getPhoneValidationError(value, { required = false } = {}) {
  const trimmed = String(value || '').trim()
  if (!trimmed) {
    return required ? 'Phone number is required.' : ''
  }
  if (!PHONE_REGEX.test(trimmed)) {
    return 'Enter a valid phone number (6 to 11 digits).'
  }
  return ''
}

export function validateContactFields(formData, { phoneRequired = false, mobileRequired = false } = {}) {
  const phoneError = getPhoneValidationError(formData?.phoneNumber, { required: phoneRequired })
  const mobileError = getMobileValidationError(formData?.mobile, { required: mobileRequired })
  if (phoneError || mobileError) {
    return {
      ok: false,
      phoneError,
      mobileError,
      message: phoneError || mobileError
    }
  }
  return { ok: true, phoneError: '', mobileError: '' }
}

function applyInputValidity(inputElement, errorMessage) {
  if (!inputElement?.setCustomValidity) {
    return !errorMessage
  }
  inputElement.setCustomValidity(errorMessage || '')
  inputElement.reportValidity()
  return !errorMessage
}

export function reportContactFieldValidity(template, validationResult) {
  if (!template || !validationResult) {
    return false
  }
  const phoneInput = template.querySelector('lightning-input[name="phoneNumber"]')
  const mobileInput = template.querySelector('lightning-input[name="mobile"]')
  applyInputValidity(phoneInput, validationResult.phoneError)
  applyInputValidity(mobileInput, validationResult.mobileError)
  return validationResult.ok === true
}

export function sanitizeContactFieldValue(fieldName, value) {
  if (fieldName === 'mobile') {
    return sanitizeDigits(value, MOBILE_MAX_LENGTH)
  }
  if (fieldName === 'phoneNumber') {
    return sanitizeDigits(value, PHONE_MAX_LENGTH)
  }
  if (fieldName === 'noOfAttempts') {
    return sanitizeDigits(value, 2)
  }
  if (fieldName === 'numberOfDependent' || fieldName === 'numberOfEarningMember') {
    return sanitizeDigits(value, 3)
  }
  if (fieldName === 'yearsInCity' || fieldName === 'yearsInResidence') {
    return sanitizeDecimalYear(value)
  }
  if (fieldName === 'nameOfPersonMet') {
    return sanitizeNameText(value)
  }
  return value
}

export function buildFiSavePayload(component, submittedByFiUser) {
  return {
    investigationId: component.investigationId,
    verificationId: component.verificationId,
    applicantId: component.applicantId,
    fiLabel: FI_LABEL,
    submittedByFiUser,
    isNonIndividual: component.isNonIndividual === true,
    fiDecision: component.fiDecision || '',
    remarks: component.remarks || '',
    formData: component.formData || {}
  }
}

async function invokeApexMethod(apexMethodName, recordId, params) {
  return getPageData({
    apexClassName: APEX_CLASS,
    apexMethodName,
    recordId: recordId || null,
    params: params || null
  })
}

async function invokeFiSave(apexMethodName, recordId, params) {
  return savePageData({
    apexClassName: APEX_CLASS,
    apexMethodName,
    recordId: recordId || null,
    params: params || null
  })
}

export function buildEmptyNiResidenceFormFields() {
  return {
    employerBusinessName: '',
    yearsInThisAddress: '',
    resiCumOff: '',
    kmFromBranch: '',
    officeBpFi: '',
    resiFi: '',
    fiLatitude: '',
    fiLongitude: '',
    frontside: '',
    leftside: '',
    rearside: '',
    rightside: '',
    leadGenTime: '',
    requestGenTime: '',
    officeVerifiedTime: '',
    resiVerifiedTime: '',
    companyName: '',
    senpContactName: '',
    totalBusinessStability: '',
    businessPremise: '',
    orgType: '',
    businessNature: '',
    currentBusinessStability: '',
    businessPremisesOwnedRental: '',
    rentalPremisesRentPerMonth: '',
    officeBoard: '',
    locatability: '',
    politicalPhoto: '',
    officeApproach: '',
    officeBusinessType: '',
    location: '',
    touringOrTransferableJob: '',
    officeBusinessSiteSqft: '',
    behaviour: '',
    numberOfEmployeesSeen: '',
    activityAtOffice: '',
    howManyEmployeesInOffice: '',
    locality: '',
    photoNotAllowed: '',
    fiRecommendation: '',
    verifierRemarks: '',
    rejectReason: '',
    fleetCount: '',
    freeFleet: '',
    iblFleet: '',
    financedByOthers: '',
    fleetTotal: ''
  }
}

export function buildEmptyForm() {
  return {
    residenceType: '',
    addressLine1: '',
    addressLine2: '',
    landmark: '',
    city: '',
    pinCode: '',
    state: '',
    phoneNumber: '',
    mobile: '',
    customerHouseSame: false,
    numberOfDependent: '',
    numberOfEarningMember: '',
    nameOfPersonMet: '',
    relationship: '',
    yearsInCity: '',
    kycLatitude: '',
    kycLongitude: '',
    fiLatitude: '',
    fiLongitude: '',
    coordinatesVerified: '',
    coordinatesDistance: '',
    yearsInResidence: '',
    profileToProductMatch: '',
    noOfAttempts: '',
    fiObservation: '',
    fiFeedback: '',
    ...buildEmptyNiResidenceFormFields()
  }
}

export function parseFormDataJson(jsonPayload) {
  if (!jsonPayload) {
    return {}
  }
  try {
    const parsed = JSON.parse(jsonPayload)
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}
  } catch (e) {
    return {}
  }
}

export function getErrorMessage(error) {
  return error?.body?.message || error?.message || 'Unexpected error'
}

export function showGlobalLoader(message) {
  window.dispatchEvent(new CustomEvent(LOS_GLOBAL_LOADER_EVENT, {
    detail: { show: true, message: message || 'Loading...' }
  }))
}

export function hideGlobalLoader() {
  window.dispatchEvent(new CustomEvent(LOS_GLOBAL_LOADER_EVENT, {
    detail: { show: false }
  }))
}

export function dispatchToast(component, title, message, variant) {
  component.dispatchEvent(new ShowToastEvent({ title, message, variant }))
}

export function readFieldValue(event) {
  const name = event.target?.name
  if (!name) {
    return { name: null, value: null }
  }
  const value = event.target.type === 'checkbox'
    ? event.target.checked
    : event.detail?.value ?? event.target.value
  return { name, value }
}

export function applyDecisionFieldChange(component, event) {
  const { name, value } = readFieldValue(event)
  if (name === 'fiDecision') {
    component.fiDecision = value
  } else if (name === 'remarks') {
    component.remarks = value
  }
}

export const FI_DECISION_ACCEPTED = 'Accepted'
export const FI_DECISION_REJECTED = 'Rejected'

export function isFiDecisionFinal(fiDecision) {
  return fiDecision === FI_DECISION_ACCEPTED || fiDecision === FI_DECISION_REJECTED
}

export function isFinalVerificationStatus(status) {
  const normalized = (status || '').trim()
  return normalized === 'Completed'
    || normalized === FI_DECISION_ACCEPTED
    || normalized === FI_DECISION_REJECTED
}

export function isVerificationCompletedByFiUser(status) {
  return (status || '').trim().toLowerCase() === 'completed'
}

export function isRejectedVerification(result) {
  const decision = String(result?.fiDecision || '').trim()
  const status = String(result?.fiStatus || '').trim()
  return result?.isRejected === true
    || decision === FI_DECISION_REJECTED
    || status === FI_DECISION_REJECTED
}

export function isLockedVerification(result) {
  if (result?.isLocked === true || result?.isCompleted === true) {
    return true
  }
  if (isRejectedVerification(result)) {
    return true
  }
  if (isFiDecisionFinal(result?.fiDecision)) {
    return true
  }
  if (isFinalVerificationStatus(result?.fiStatus)) {
    return true
  }
  return false
}

export function resolveReadOnly(result) {
  return isLockedVerification(result)
}

export function resolveDecisionReadOnly(result) {
  if (isFiDecisionFinal(result?.fiDecision)) {
    return true
  }
  return !isVerificationCompletedByFiUser(result?.fiStatus)
}

export function buildHeaderData(result) {
  return {
    fiStatus: result?.fiStatus || '',
    applicantName: result?.applicantName || '',
    productType: result?.productType || '',
    fiLabel: result?.fiLabel || FI_LABEL,
    investigationCaseName: result?.investigationCaseName || ''
  }
}

export async function loadResidenceFiRecord({ recordId, applicantId, applicationId, verificationId }) {
  if (verificationId) {
    const result = await invokeApexMethod(ACTIONS.GET_BY_INVESTIGATION, recordId || null, {
      verificationId
    })
    return { result }
  }

  if (recordId && recordId.length >= 15) {
    const result = await invokeApexMethod(ACTIONS.GET_BY_INVESTIGATION, recordId, {
      investigationId: recordId,
      fiLabel: FI_LABEL
    })
    return { result }
  }

  if (applicantId) {
    const result = await invokeApexMethod(ACTIONS.GET_RESIDENCE_FI, null, {
      applicantId,
      applicationId: applicationId || null
    })
    return { result }
  }

  return { result: null }
}

export async function saveResidenceFi(component, submittedByFiUser) {
  await invokeFiSave(ACTIONS.SAVE_FI_DATA, component.investigationId, {
    dataJson: JSON.stringify(buildFiSavePayload(component, submittedByFiUser))
  })
}

export async function captureFiLocation(component, onCoordinatesCaptured) {
  if (component.isReadOnly || component.isFiSubmitted === true) {
    dispatchToast(component, 'Error', 'Capture FI location is not available after submission.', 'error')
    return false
  }

  if (!navigator.geolocation) {
    dispatchToast(component, 'Error', 'Geolocation is not supported by your browser.', 'error')
    return false
  }

  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          const saveResult = await invokeFiSave(ACTIONS.UPDATE_FI_LOCATION, component.investigationId, {
            investigationId: component.investigationId,
            verificationId: component.verificationId,
            applicantId: component.applicantId,
            fiLabel: FI_LABEL,
            latitude: position.coords.latitude,
            longitude: position.coords.longitude
          })
          if (typeof onCoordinatesCaptured === 'function') {
            onCoordinatesCaptured(position.coords.latitude, position.coords.longitude, saveResult)
          }
          dispatchToast(component, 'Success', 'FI location captured.', 'success')
          resolve(true)
        } catch (error) {
          dispatchToast(component, 'Error', getErrorMessage(error), 'error')
          resolve(false)
        }
      },
      () => {
        dispatchToast(component, 'Error', 'Unable to retrieve your location.', 'error')
        resolve(false)
      }
    )
  })
}

function buildDocumentContext(component) {
  return {
    applicationId: component.applicationId || null,
    applicantId: component.applicantId || null,
    verificationId: component.verificationId || null,
    investigationId: component.investigationId || null,
    fiLabel: FI_LABEL
  }
}

export async function loadFiDocumentPreviewMap(component) {
  const context = buildDocumentContext(component)
  if (!context.verificationId && (!context.applicationId || !context.applicantId)) {
    return {}
  }
  const previewMap = await invokeApexMethod(ACTIONS.GET_FI_DOCUMENT_PREVIEW, component.investigationId, context)
  return previewMap && typeof previewMap === 'object' ? previewMap : {}
}

export async function initOrGetFiDocument(component, documentType) {
  const context = buildDocumentContext(component)
  const result = await invokeApexMethod(ACTIONS.INIT_OR_GET_FI_DOCUMENT, component.investigationId, {
    ...context,
    documentType
  })
  return result?.documentId || null
}

export async function linkFiDocumentContentVersion(component, documentType, contentVersionId, checklistId) {
  const context = buildDocumentContext(component)
  await invokeFiSave(ACTIONS.LINK_FI_DOCUMENT, component.investigationId, {
    ...context,
    documentType,
    contentVersionId,
    documentId: checklistId || null
  })
}

export async function saveFiSignature(checklistId, base64Data, fileName, investigationId) {
  await invokeFiSave(ACTIONS.SAVE_FI_SIGNATURE, investigationId, {
    documentId: checklistId,
    base64Data,
    fileName: fileName || 'Signature.png'
  })
}

export function hasDocumentPreview(previewMap, documentType) {
  const info = previewMap?.[documentType]
  return Boolean(info?.contentVersionId || info?.contentDocumentId)
}

export function getDocumentPreviewInfo(previewMap, documentType) {
  return previewMap?.[documentType] || null
}

export function getDocumentPreviewFileName(previewMap, documentType, fallback = 'Document') {
  const fileName = getDocumentPreviewInfo(previewMap, documentType)?.fileName
  const normalized = String(fileName || '').trim()
  return normalized || fallback
}

export function parseAddressProofDocuments(result) {
  const rows = result?.addressProofDocuments
  return Array.isArray(rows) ? rows : []
}

function buildContactDisplayErrors(formData) {
  const phoneNumber = formData?.phoneNumber
  const mobile = formData?.mobile
  return {
    phoneNumberError: String(phoneNumber || '').trim() ? getPhoneValidationError(phoneNumber) : '',
    mobileError: String(mobile || '').trim() ? getMobileValidationError(mobile) : ''
  }
}

export function buildResidencePreviewFileNames(previewMap = {}) {
  return {
    kyc: getDocumentPreviewFileName(previewMap, DOC_TYPE_FI_KYC, 'KYC document'),
    signature: getDocumentPreviewFileName(previewMap, DOC_TYPE_FI_SIGNATURE, 'Signature'),
    residenceFront: getDocumentPreviewFileName(previewMap, DOC_TYPE_RESIDENCE_FRONT, 'Residence image')
  }
}

export function buildResidenceDocFlags(documentPreviewMap = {}) {
  return {
    hasSignatureDoc: hasDocumentPreview(documentPreviewMap, DOC_TYPE_FI_SIGNATURE),
    hasResidenceFrontDoc: hasDocumentPreview(documentPreviewMap, DOC_TYPE_RESIDENCE_FRONT),
    hasKycDoc: hasDocumentPreview(documentPreviewMap, DOC_TYPE_FI_KYC)
  }
}

export function buildResidenceDisplayValues(formData = {}, fiDecision = '') {
  return {
    residenceType: resolveOptionLabel(formData.residenceType, RESIDENCE_TYPE_OPTIONS),
    relationship: resolveOptionLabel(formData.relationship, RELATIONSHIP_OPTIONS),
    profileToProductMatch: resolveOptionLabel(formData.profileToProductMatch, PROFILE_TO_PRODUCT_MATCH_OPTIONS),
    fiObservation: resolveOptionLabel(formData.fiObservation, FI_OBSERVATION_OPTIONS),
    customerHouseSame: formatBooleanDisplay(formData.customerHouseSame),
    fiDecision: resolveOptionLabel(fiDecision, FI_DECISION_OPTIONS),
    resiCumOff: resolveOptionLabel(formData.resiCumOff, YES_NO_OPTIONS),
    totalBusinessStability: resolveOptionLabel(formData.totalBusinessStability, TOTAL_BUSINESS_STABILITY_OPTIONS),
    businessPremise: resolveOptionLabel(formData.businessPremise, BUSINESS_PREMISE_NI_OPTIONS),
    officeBusinessType: resolveOptionLabel(formData.officeBusinessType, OFFICE_BUSINESS_TYPE_OPTIONS),
    location: resolveOptionLabel(formData.location, LOCATION_OPTIONS),
    politicalPhoto: resolveOptionLabel(formData.politicalPhoto, POLITICAL_PHOTO_OPTIONS),
    officeBusinessSiteSqft: resolveOptionLabel(formData.officeBusinessSiteSqft, OFFICE_BUSINESS_SIZE_OPTIONS)
  }
}

export function buildResidenceContactErrors(formData = {}) {
  return buildContactDisplayErrors(formData)
}

export function buildResidenceUiFlags(state) {
  const docFlags = buildResidenceDocFlags(state.documentPreviewMap)
  const isReadOnly = state.isReadOnly === true
  const renderAsReadOnly = state.renderAsReadOnly === true
  const isNonIndividual = state.isNonIndividual === true
  const showDecisionButtons = isReadOnly && state.isDecisionReadOnly !== true
  const submitDisabled = isNonIndividual
    ? isReadOnly
    : (isReadOnly || !docFlags.hasSignatureDoc || !docFlags.hasResidenceFrontDoc)
  return {
    showFiActionButtons: !isReadOnly,
    showDecisionButtons,
    showFooter: (!isReadOnly || showDecisionButtons) && !renderAsReadOnly,
    captureLocationDisabled: state.isFiLocationCaptured || isReadOnly || state.isFiSubmitted === true,
    submitDisabled
  }
}

export function buildFiDocCardUiFlags(hasDocument, isEditable, checklistId = null) {
  const hasDoc = hasDocument === true
  const editable = isEditable === true
  return {
    showUploadBtn: !hasDoc && editable,
    showEmptyPlaceholder: !hasDoc && !editable,
    showUploadedRow: hasDoc,
    showDeleteBtn: hasDoc && editable,
    checklistId: checklistId || null
  }
}

function buildDocCardUi(previewMap, documentType, hasDocument, isEditable) {
  const checklistId = getDocumentPreviewInfo(previewMap, documentType)?.documentId || null
  return buildFiDocCardUiFlags(hasDocument, isEditable, checklistId)
}

function buildResidenceNiDocFlags(documentPreviewMap = {}) {
  return {
    hasApproachRoadDoc: hasDocumentPreview(documentPreviewMap, DOC_TYPE_OFFICE_APPROACH_ROAD),
    hasBuildingInnerDoc: hasDocumentPreview(documentPreviewMap, DOC_TYPE_OFFICE_BUILDING_INNER),
    hasBuildingFrontDoc: hasDocumentPreview(documentPreviewMap, DOC_TYPE_OFFICE_BUILDING_FRONT)
  }
}

function buildResidenceNiPreviewFileNames(previewMap = {}) {
  return {
    approachRoad: getDocumentPreviewFileName(previewMap, DOC_TYPE_OFFICE_APPROACH_ROAD, 'Office approach road'),
    buildingInner: getDocumentPreviewFileName(previewMap, DOC_TYPE_OFFICE_BUILDING_INNER, 'Office building inner view'),
    buildingFront: getDocumentPreviewFileName(previewMap, DOC_TYPE_OFFICE_BUILDING_FRONT, 'Office building front view')
  }
}

export function buildResidenceDocumentUi(previewMap, isEditable, isNonIndividual = false) {
  if (isNonIndividual) {
    const flags = buildResidenceNiDocFlags(previewMap)
    return {
      fileNames: buildResidenceNiPreviewFileNames(previewMap),
      approachRoad: buildDocCardUi(previewMap, DOC_TYPE_OFFICE_APPROACH_ROAD, flags.hasApproachRoadDoc, isEditable),
      buildingInner: buildDocCardUi(previewMap, DOC_TYPE_OFFICE_BUILDING_INNER, flags.hasBuildingInnerDoc, isEditable),
      buildingFront: buildDocCardUi(previewMap, DOC_TYPE_OFFICE_BUILDING_FRONT, flags.hasBuildingFrontDoc, isEditable)
    }
  }
  const flags = buildResidenceDocFlags(previewMap)
  return {
    fileNames: buildResidencePreviewFileNames(previewMap),
    kyc: buildDocCardUi(previewMap, DOC_TYPE_FI_KYC, flags.hasKycDoc, isEditable),
    signature: buildDocCardUi(previewMap, DOC_TYPE_FI_SIGNATURE, flags.hasSignatureDoc, isEditable),
    residenceFront: buildDocCardUi(previewMap, DOC_TYPE_RESIDENCE_FRONT, flags.hasResidenceFrontDoc, isEditable)
  }
}

export async function deleteFiDocument(component, documentType, reloadPreview) {
  if (component.isReadOnly || !documentType) {
    return
  }

  const checklistId = getDocumentPreviewInfo(component.documentPreviewMap, documentType)?.documentId
  if (!checklistId) {
    return
  }

  component.isLoading = true
  try {
    const nextMap = { ...component.documentPreviewMap }
    delete nextMap[documentType]
    component.documentPreviewMap = nextMap
    await deactivateDocument({ documentChecklistId: checklistId })
    if (typeof reloadPreview === 'function') {
      await reloadPreview()
    }
    dispatchToast(component, 'Success', 'Document removed.', 'success')
  } catch (error) {
    if (typeof reloadPreview === 'function') {
      await reloadPreview()
    }
    dispatchToast(component, 'Error', getErrorMessage(error), 'error')
  } finally {
    component.isLoading = false
  }
}

export function initFilePreviewContext(component) {
  const origin = window.location.origin
  const isSite = location.pathname.split('/').length >= 2 && location.pathname.split('/')[2] === 's'
  component.vfRoot = isSite
    ? origin
    : `${origin.split('.')[0]}--c${origin.includes('sandbox') ? '.sandbox' : ''}.vf.force.com`
  getUserSessionId()
    .then((id) => { component.sessionId = id })
    .catch(() => { /* preview download may fail without a session */ })
}

function extractFileExtension(fileName) {
  if (!fileName || typeof fileName !== 'string') {
    return null
  }
  const parts = fileName.split('.')
  return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : null
}

export async function openFiMagicUpload(component, documentType) {
  if (component.isReadOnly || !component.applicationId || !component.applicantId) {
    dispatchToast(component, 'Error', 'Applicant and application are required before uploading documents.', 'error')
    return
  }

  component.isLoading = true
  try {
    const checklistId = await initOrGetFiDocument(component, documentType)
    if (!checklistId) {
      dispatchToast(component, 'Error', 'Unable to prepare document upload.', 'error')
      return
    }
    component.activeUploadDocumentType = documentType
    component.activeUploadChecklistId = checklistId
    component.showMagicUpload = true
  } catch (error) {
    dispatchToast(component, 'Error', getErrorMessage(error), 'error')
  } finally {
    component.isLoading = false
  }
}

export function closeFiMagicUpload(component) {
  component.showMagicUpload = false
  component.activeUploadDocumentType = ''
  component.activeUploadChecklistId = ''
}

export async function completeFiMagicUpload(component, event, reloadPreview) {
  const files = (event.detail && event.detail.files) || []
  const documentType = component.activeUploadDocumentType
  const checklistId = component.activeUploadChecklistId
  if (!files.length || !documentType || !checklistId) {
    component.showMagicUpload = false
    return
  }

  const first = files[0]
  if (!first.contentVersionId) {
    dispatchToast(component, 'Error', 'Uploaded file reference is missing.', 'error')
    component.showMagicUpload = false
    return
  }

  closeFiMagicUpload(component)
  component.isLoading = true
  try {
    await linkFiDocumentContentVersion(component, documentType, first.contentVersionId, checklistId)
    if (typeof reloadPreview === 'function') {
      await reloadPreview()
    }
    dispatchToast(component, 'Success', 'Document uploaded successfully.', 'success')
  } catch (error) {
    dispatchToast(component, 'Error', getErrorMessage(error), 'error')
  } finally {
    component.isLoading = false
  }
}

export function applyFiDocumentPreview(component, documentType) {
  const previewInfo = getDocumentPreviewInfo(component.documentPreviewMap, documentType)
  if (!previewInfo) {
    dispatchToast(component, 'Info', 'Document preview is not available.', 'info')
    return
  }

  if (previewInfo.contentVersionId) {
    component.previewContentVersionId = previewInfo.contentVersionId
    component.previewFileName = previewInfo.fileName || ''
    component.previewFileExtension = previewInfo.fileType || extractFileExtension(previewInfo.fileName || '') || ''
    component.showFilePreviewer = true
    return
  }

  if (previewInfo.contentDocumentId) {
    component.previewContentDocumentId = previewInfo.contentDocumentId
    component.previewFileType = previewInfo.fileType || ''
    component.showPreviewModal = true
    return
  }

  dispatchToast(component, 'Info', 'Document preview is not available.', 'info')
}

export function closeEmbedPreview(component) {
  component.showFilePreviewer = false
  component.previewContentVersionId = null
  component.previewFileName = ''
  component.previewFileExtension = ''
}

export function openAddressProofPreview(component, contentDocumentId) {
  if (!contentDocumentId) {
    dispatchToast(component, 'Info', 'Document preview is not available.', 'info')
    return
  }
  component.previewContentDocumentId = contentDocumentId
  component.previewFileType = ''
  component.showPreviewModal = true
}

export function closeFilePreview(component, event) {
  event?.stopPropagation?.()
  event?.stopImmediatePropagation?.()
  component.showPreviewModal = false
  component.previewContentDocumentId = ''
  component.previewFileType = ''
}