import { LightningElement } from 'lwc'
import savePageData from '@salesforce/apex/GenericPageLayoutController.savePageData'

const APEX_CLASS = 'CustomerExposureServiceController'
const APEX_METHOD = 'invokeCustomerExposure'

export async function onLoad(submodulename, ctx) {
  if (submodulename !== 'onNext' || !ctx) {
    return
  }

  ctx._customerExposureResult = {
    isSuccess: false,
    message: 'Customer exposure failed.'
  }

  if (!ctx.recordId) {
    ctx._customerExposureResult = {
      isSuccess: false,
      message: 'Application record Id is missing.'
    }
    return
  }

  try {
    const response = await savePageData({
      apexClassName: APEX_CLASS,
      apexMethodName: APEX_METHOD,
      recordId: ctx.recordId,
      params: {
        applicantId: ctx.applicantId || null
      }
    })
    ctx._customerExposureResult = response || ctx._customerExposureResult
  } catch (error) {
    ctx._customerExposureResult = {
      isSuccess: false,
      message: error?.body?.message || error?.message || 'Customer exposure failed.'
    }
  }
}

export default class ClientLayerCustomerExposure extends LightningElement {}