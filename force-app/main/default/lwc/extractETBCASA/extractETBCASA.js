/**
 * Headless visualizer for the ETB CASA integration.
 *
 * Resolved by clientLayerHelper.invokeHandler('extractETBCASA', …) and
 * referenced by Integration_Master__c.Component_Reference__c so the
 * standard framework lookup succeeds.
 */

import { LightningElement } from 'lwc';

const STAGES = [
    'Fetching CASA Accounts',
    'Persisting Account List'
];
const HEADER = 'ETB CASA';

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
    if (submodulename !== 'onCasaFetch') return;
    dispatch(ctx, { show: true, status: 'loading', currentStageIndex: 0, header: HEADER, stages: STAGES, errorMessage: '' });
    await sleep(500);
    dispatch(ctx, { show: true, status: 'loading', currentStageIndex: 1, header: HEADER, stages: STAGES, errorMessage: '' });
    await sleep(500);
    dispatch(ctx, { show: true, status: 'success', currentStageIndex: 1, header: HEADER, stages: STAGES, errorMessage: '' });
}

export default class ExtractETBCASA extends LightningElement {}