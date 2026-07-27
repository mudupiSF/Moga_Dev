import { LightningElement, api } from 'lwc';

export default class FaceApiMockResponseViewer extends LightningElement {
    @api integrationName = '';
    @api responseBody = '';

    get hasResponseBody() {
        return !!String(this.responseBody || '').trim();
    }

    get formattedResponseBody() {
        const raw = String(this.responseBody || '').trim();
        if (!raw) return 'No response payload.';
        try {
            return JSON.stringify(JSON.parse(raw), null, 2);
        } catch (e) {
            return raw;
        }
    }
}