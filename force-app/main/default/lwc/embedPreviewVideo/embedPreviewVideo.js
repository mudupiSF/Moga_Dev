/* ════════════════════════════════════════════════════════════════════════════
   embedPreviewVideo
   ────────────────────────────────────────────────────────────────────────────
   Scope: VIDEO file previews ONLY.
   Inline video preview for embedCustomFilePreview. It uses the same native
   <video> approach as the base previewVideo component, with a friendlier inline
   error state when the browser cannot play the format.
   ════════════════════════════════════════════════════════════════════════════ */

import { LightningElement, api, track } from 'lwc';

export default class EmbedPreviewVideo extends LightningElement {
    @api sessionId        = '';
    @api vfRoot           = '';
    @api fileName         = '';
    @api contentVersionId = '';

    @track videoUrl  = '';
    @track errorMsg  = '';

    _contentDocumentId = null;
    _stalledTimer     = null;
    _alreadyFiredFail = false;

    @api
    get contentDocumentId() { return this._contentDocumentId; }
    set contentDocumentId(value) {
        this._contentDocumentId = value;
        if (value) {
            this.videoUrl = '/sfc/servlet.shepherd/document/download/' + value;
        }
    }

    get videoMimeType() {
        const ext = (this.fileName && this.fileName.split('.').pop() || '').toLowerCase();
        if (ext === 'webm') return 'video/webm';
        if (ext === 'mov')  return 'video/quicktime';
        if (ext === 'm4v')  return 'video/x-m4v';
        return 'video/mp4';
    }

    handleDownload() {
        const a    = document.createElement('a');
        a.href     = this.videoUrl;
        a.download = this.fileName || 'video';
        a.click();
    }

    handleClose() {
        this._clearStalledTimer();
        this.dispatchEvent(new CustomEvent('close'));
    }

    /**
     * Native <video> `error` event handler. Fires for:
     *   • MediaError.MEDIA_ERR_ABORTED        (1)
     *   • MediaError.MEDIA_ERR_NETWORK        (2)
     *   • MediaError.MEDIA_ERR_DECODE         (3)
     *   • MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED (4)
     */
    handleVideoError(event) {
        if (this._alreadyFiredFail) return;
        this._alreadyFiredFail = true;
        this._clearStalledTimer();

        const mediaError = event.target && event.target.error;
        const code   = mediaError ? mediaError.code    : 'unknown';
        const detail = mediaError ? mediaError.message : '';

        console.warn('embedPreviewVideo playback error', { code, detail });
        this.errorMsg = 'Video preview is not available in this browser. Please use Download to view the file.';
    }

    /**
     * `stalled` event — buffering too long. We use a 6-second debounce
     * before treating it as a hard failure so that genuine slow networks
     * don't trigger the fallback prematurely.
     */
    handleVideoStalled() {
        if (this._alreadyFiredFail) return;

        if (this._stalledTimer) {
            return; // timer already armed
        }

        this._stalledTimer = setTimeout(() => {
            if (this._alreadyFiredFail) return;

            const videoEl = this.template.querySelector('video');
            if (videoEl && videoEl.readyState >= 3 /* HAVE_FUTURE_DATA */) {
                // Recovered — playback actually became possible
                this._clearStalledTimer();
                return;
            }

            this._alreadyFiredFail = true;
            this.errorMsg = 'Video buffering stalled. Please use Download to view the file.';
        }, 6000);
    }

    _clearStalledTimer() {
        if (this._stalledTimer) {
            clearTimeout(this._stalledTimer);
            this._stalledTimer = null;
        }
    }

    disconnectedCallback() {
        this._clearStalledTimer();
    }
}