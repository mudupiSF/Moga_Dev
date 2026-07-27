import { LightningElement } from 'lwc';

/**
 * Service layer for sfLOSTwoColumnCardLayoutEdit.
 * Dynamically imports only the section-specific handler module - no business logic here.
 *
 * To add a new section handler:
 * 1. Create lwc/sfLOSClientLayer{SectionName}/ (e.g. sfLOSClientLayerLoanBasicInfo)
 * 2. Export default function(ctx) { ... } from that module
 * 3. Add one entry to HANDLER_MODULES below
 *
 * ctx = component instance: fields, fieldConfig, sectionKey, _fileMap, handleSave, etc.
 */

const HANDLER_MODULES = {
    panFileExtract:                 () => import('c/clientLayerDocumentVerification'),
    pancardVerificationCheck:       () => import('c/clientLayerDocumentVerification'),
    panCheck:                       () => import('c/validatePANAPI'),
    contactInfoCheck:               () => import('c/otpVerification'),
    customerDedupeCheck:            () => import('c/clientLayerCustomerDedupe'),
    vehicleDetailsSectionActions:   () => import('c/clientLayerVehicleDetails'),
    viabilitySectionActions:        () => import('c/clientLayerViability'),
    exposureSectionActions:         () => import('c/clientLayerExposureAnalysis'),
    deviationCallout:               () => import('c/clientLayerDeviation'),
    borrowerNextIntegration:        () => import('c/borrowerNextIntegration'),
    onOfferEngineApi:               () => import('c/clientLayerOfferPage')
};

// Sourav commented this code because we are using loadComponent function to load the component dynamically
/**
 * Invoke the handler for the given name. Dynamically loads only that section's JS.
 * @param {string} name - Handler name (e.g. 'loanBasicInfo', 'documentVerification')
 * @param {object} ctx - The component instance (this from sfLOSTwoColumnCardLayoutEdit)
 * @returns {Promise<void>}
 */
/*export function invokeHandler(name,submodulename, ctx) {
    if (!name || !ctx) return Promise.resolve();
    const loader = HANDLER_MODULES[name];
    if (!loader) return Promise.resolve();
    return loader()
    .then((module) => {
        const handler = module?.onLoad || module?.default;
        if (handler && typeof handler === 'function') {
            return Promise.resolve(handler(submodulename,ctx));
        }
        return Promise.resolve();
    })
    .catch((e) => {
        console.error(`[clientLayerHelper] Failed to load handler "${name}":`, e);
    });
}*/

/**
 * Invoke the handler for the given component name. Dynamically loads only that component's JS.
 * @param {string} componentName - Component name (e.g. 'clientLayerDocumentVerification', 'otpVerification')
 * @param {string} submodulename - Submodule name (e.g. 'onFileUpload', 'onAction')
 * @param {object} ctx - The component instance (this from sfLOSTwoColumnCardLayoutEdit)
 * @returns {Promise<void>}
 */
export async function invokeHandler(componentName, submodulename, ctx) {
    if (!componentName || !ctx) return Promise.resolve();
    await loadComponent(componentName)
    .then((module) => {
        const handler = module?.onLoad || module?.default;
        if (handler && typeof handler === 'function') {
            return Promise.resolve(handler(submodulename, ctx));
        }
        return Promise.resolve();
    })
    .catch((e) => {
        console.error(`[clientLayerHelper] Failed to load handler "${componentName}":`, e);
    });
}

async function loadComponent(componentName) {
    try {
        //const module = await import(`c/${componentName}`);
        //return module;
        return await import(`c/${componentName}`);
    }
    catch (e) {
        console.error(`[clientLayerHelper] Failed to load component "${componentName}":`, e);
        return null;
    }
}

export default class ClientLayerHelper extends LightningElement {}