/**
 * Headless visualizer for the CIF on PAN integration.
 *
 * Resolved by clientLayerHelper.invokeHandler('extractCIFONPAN', …) and
 * referenced by Integration_Master__c.Component_Reference__c so the
 * standard framework lookup succeeds.
 */

import { LightningElement } from 'lwc';

const STAGES = [
    'Fetching CIF on PAN',
    'Storing Customer Code'
];
const HEADER = 'CIF on PAN';

function dispatch(ctx, payload) {
    const ev = new CustomEvent('integrationprogressupdate', {
        detail: payload,
        bubbles: true,
        composed: true
    });
    ctx?.dispatchEvent?.(ev);
    window.dispatchEvent(ev);
}
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

export async function onLoad(submodulename, ctx) {
    // Skip when borrowerNextIntegration is already orchestrating the modal.
    if (submodulename !== 'onCifFetch') return;
    dispatch(ctx, { show: true, status: 'loading', currentStageIndex: 0, header: HEADER, stages: STAGES, errorMessage: '' });
    await sleep(500);
    dispatch(ctx, { show: true, status: 'loading', currentStageIndex: 1, header: HEADER, stages: STAGES, errorMessage: '' });
    await sleep(500);
    dispatch(ctx, { show: true, status: 'success', currentStageIndex: 1, header: HEADER, stages: STAGES, errorMessage: '' });
}

export default class ExtractCIFONPAN extends LightningElement {}