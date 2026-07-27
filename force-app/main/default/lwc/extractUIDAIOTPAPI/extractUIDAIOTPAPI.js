import { LightningElement } from 'lwc';

/**
 * Cosmetic progress visualizer for the UIDAI OTP Verify integration.
 *
 * The actual integration runs server-side inside aadharOTPVerification on the
 * Guest VF page (UIDAIAPIHandler does the XML parse + KYC stamp + photo
 * attach). By the time the banker-side polling detects aadhaarVerified=true
 * and invokes this handler, the work is already persisted — this LWC just
 * walks the integration progress modal through human-paced stages and then
 * triggers a refresh on the parent so the freshly-stamped fields render.
 */
const STAGES = [
    'Fetching UIDAI Response',
    'Extracting Aadhaar Details',
    'Saving Aadhaar Photo'
];

const HEADER = 'Aadhaar eKYC Verification';

function dispatch(ctx, payload) {
    const ev = new CustomEvent('integrationprogressupdate', {
        detail: payload,
        bubbles: true,
        composed: true
    });
    ctx.dispatchEvent(ev);
    window.dispatchEvent(ev);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function onLoad(submodulename, ctx) {
    if (submodulename !== 'onOtpVerified') return;

    dispatch(ctx, {
        show: true, status: 'loading', currentStageIndex: 0,
        header: HEADER, stages: STAGES, errorMessage: ''
    });
    await sleep(700);

    dispatch(ctx, {
        show: true, status: 'loading', currentStageIndex: 1,
        header: HEADER, stages: STAGES, errorMessage: ''
    });
    await sleep(700);

    dispatch(ctx, {
        show: true, status: 'loading', currentStageIndex: 2,
        header: HEADER, stages: STAGES, errorMessage: ''
    });
    await sleep(500);

    dispatch(ctx, {
        show: true, status: 'success', currentStageIndex: 2,
        header: HEADER, stages: STAGES, errorMessage: ''
    });
}

export default class ExtractUIDAIOTPAPI extends LightningElement {}