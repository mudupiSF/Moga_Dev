import { LightningElement, api } from 'lwc';
import getOrCreateChecklist from '@salesforce/apex/embedDocumentChecklistController.getOrCreateChecklist';

/**
 * Headless wrapper. A host embeds this component and calls getOrCreateChecklist()
 * imperatively before an upload to obtain { checklistId, maxFilesAllowed,
 * allowedFileTypes } for the resolved Document_CheckList__c.
 */
export default class EmbedDocumentChecklist extends LightningElement {
    @api
    getOrCreateChecklist(context) {
        const c = context || {};
        return getOrCreateChecklist({
            applicationId: c.applicationId,
            applicantId: c.applicantId,
            applicantType: c.applicantType,
            assetId: c.assetId,
            documentType: c.documentType,
            documentName: c.documentName,
            documentCategory: c.documentCategory
        });
    }
}