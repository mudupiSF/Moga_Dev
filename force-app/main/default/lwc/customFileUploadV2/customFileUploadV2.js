import { LightningElement, api, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import jsforcescript from '@salesforce/resourceUrl/jsforcescript';
import getUserSessionId    from '@salesforce/apex/CustomFileUploadV2Controller.getUserSessionId';
import runUploadValidator  from '@salesforce/apex/CustomFileUploadV2Controller.runUploadValidator';

export default class CustomFileUploadV2 extends LightningElement {
    // ── public config ──────────────────────────────────────────────────────────
    @api recordId;
    @api linkedEntityId;
    @api maxFileSizeMb      = 10;
    @api enableCompression  = false;  // config 1
    @api restrictGallery    = false;  // config 2
    @api allowMerge         = false;  // config 3
    @api hidePreview        = false;  // config 4 — set true to suppress thumbnail grid
    @api blockedExtensions    = '';     // config 5 — comma-separated list e.g. "png,exe,svg"
    @api validatorClass       = '';     // config 6 — Apex class implementing FileValidator.allownewFileUpload
    @api captureLatLong           = false;  // config 7 — capture device GPS and store on ContentVersion
    @api blockPasswordProtected   = false;  // config 8 — reject password-protected PDF/DOCX/XLSX
    @api enableVideo              = false;  // config 9 — show Upload Video and Take Video buttons

    // ── watermark config (10) ─────────────────────────────────────────────────
    @api enableWatermark    = false;          // master switch — burn a watermark onto images/videos at upload
    @api watermarkLatitude  = false;          // include "Lat: x.xxxxxx" in watermark text
    @api watermarkLongitude = false;          // include "Long: y.yyyyyy" in watermark text
    @api watermarkDateTime  = false;          // include capture date-time in watermark text
    @api watermarkPosition  = 'Right Bottom'; // Right Top | Right Bottom | Left Top | Left Bottom | Diagonal

    // ── tracked state ──────────────────────────────────────────────────────────
    @track files            = [];
    @track showCamera       = false;
    @track capturedPhotos   = [];
    @track statusMessage    = '';
    @track statusType       = 'info';
    @track isUploading      = false;
    @track isMerging        = false;
    @track uploadProgress   = 0;

    // edit modal
    @track showEditModal    = false;
    @track editFileId       = null;
    @track editMaskActive   = false;
    @track editHasMasks     = false;
    @track editFileName     = '';

    // merge modal
    @track showMergeModal       = false;
    @track mergeSelectedIds     = [];
    @track mergeOrderedFiles    = [];

    // video upload modal
    @track showVideoModal        = false;
    @track videoFileName         = '';
    @track videoOriginalSize     = '';
    @track videoIsLarge          = false;
    @track videoQuality          = 'medium';
    @track isCompressing         = false;
    @track compressProgress      = 0;
    @track isVideoUploading      = false;
    @track videoUploadProgress   = 0;

    // video recorder modal
    @track showVideoRecorder     = false;
    @track isRecording           = false;
    @track recVideoReady         = false;
    @track recVideoSize          = '';
    @track recDurationLabel      = '0:00';
    @track recPlaybackSrc        = '';

    // ── private ────────────────────────────────────────────────────────────────
    _nextId         = 1;
    _stream         = null;
    _maskingState = {};
    _editImg      = null;
    _editRotation = 0;
    _vfRoot       = null;
    _sessionId    = null;
    _dragSrcId    = null;
    _latLong         = null;  // { latitude, longitude } captured once and reused for all files in session
    _latLongPromise  = null;  // in-flight geolocation promise — concurrent callers share one request
    _rawVideoFile   = null;  // video File object pending user confirmation
    _rawVideoBase64 = null;  // base64 string for recorded video — avoids double FileReader under LWS
    _recStream      = null;  // MediaStream for the recorder live preview
    _mediaRecorder  = null;
    _recChunks      = [];
    _recBlob        = null;  // finished recording blob
    _recDataUrl     = null;  // data URL computed once from blob for playback preview
    _recTimer      = null;  // interval for duration counter
    _recSeconds    = 0;

    // ── computed ───────────────────────────────────────────────────────────────
    get mergeLabel()         { return this.isMerging ? 'Merging…' : 'Merge to PDF'; }
    get uploadLabel()        { return this.isUploading ? 'Uploading…' : 'Upload All'; }
    get noCapturedPhotos()   { return this.capturedPhotos.length === 0; }
    get progressStyle()      { return `width:${this.uploadProgress}%`; }
    get progressLabel()      { return `${this.uploadProgress}%`; }
    get statusClass()        { return `status-msg status-${this.statusType}`; }
    get statusIcon() {
        const map = { success: 'utility:success', error: 'utility:error', info: 'utility:info' };
        return map[this.statusType] || 'utility:info';
    }
    get entityId()           { return this.linkedEntityId || this.recordId; }
    get showPreviewGrid()    { return !this.hidePreview && this.files.length > 0; }
    get showMergeButton()    { return this.allowMerge && this.imageCount >= 2; }
    get showVideoButtons()   { return this.enableVideo && !this.restrictGallery; }
    get imageCount()         { return this.files.filter(f => f.isImage).length; }

    // GPS is needed when the explicit toggle is on, OR when the watermark
    // wants latitude/longitude burned into the photo/video.
    get _needsLatLong() {
        return this.captureLatLong
            || (this.enableWatermark && (this.watermarkLatitude || this.watermarkLongitude));
    }

    // edit modal button class/label
    get editMaskBtnClass()   { return this.editMaskActive ? 'btn btn-tool btn-tool-active' : 'btn btn-tool'; }
    get editMaskLabel()      { return this.editMaskActive ? 'Masking ON' : 'Mask'; }

    // video modal
    get videoQualityClassHigh()   { return this.videoQuality === 'high'   ? 'btn btn-tool btn-tool-active' : 'btn btn-tool'; }
    get videoQualityClassMedium() { return this.videoQuality === 'medium' ? 'btn btn-tool btn-tool-active' : 'btn btn-tool'; }
    get videoQualityClassLow()    { return this.videoQuality === 'low'    ? 'btn btn-tool btn-tool-active' : 'btn btn-tool'; }
    get videoQualityClassNone()   { return this.videoQuality === 'none'   ? 'btn btn-tool btn-tool-active' : 'btn btn-tool'; }
    get videoConfirmLabel()       { return this.isCompressing ? 'Compressing…' : (this.videoQuality === 'none' ? 'Upload' : 'Compress & Upload'); }
    get compressProgressStyle()   { return `width:${this.compressProgress}%`; }
    get compressProgressLabel()   { return `Compressing… ${this.compressProgress}%`; }

    // merge modal — ordered list drives the displayed sequence
    get imageFilesForMerge() {
        const base = this.mergeOrderedFiles.length
            ? this.mergeOrderedFiles
            : this.files.filter(f => f.isImage);
        return base.map((f, idx) => ({
            ...f,
            mergeSelected:  this.mergeSelectedIds.includes(f.id),
            mergeCardClass: this.mergeSelectedIds.includes(f.id)
                ? 'merge-card merge-card-selected'
                : 'merge-card',
            mergeCheckIcon: this.mergeSelectedIds.includes(f.id) ? '✔' : '',
            mergeDataUrl:   f._previewDataUrl || '',
            mergeOrder:     idx + 1,
            isFirst:        idx === 0,
            isLast:         idx === base.length - 1
        }));
    }
    get mergeSelectedLabel() {
        const n = this.mergeSelectedIds.length;
        return n === 0 ? 'Select at least 2 images' : `${n} image(s) selected`;
    }
    get mergeDisabled() { return this.mergeSelectedIds.length < 2 || this.isMerging; }

    // ── session ID — Apex reads VF page server-side, no CORS ──────────────────
    @wire(getUserSessionId)
    _wiredSession({ data, error }) {
        if (data)  this._sessionId = data;
        if (error) this._setStatus('Could not load session — uploads may fail', 'error');
    }

    // ── lifecycle ──────────────────────────────────────────────────────────────
    connectedCallback() {
        const origin = window.location.origin;
        const isSite = location.pathname.split('/').length >= 2 && location.pathname.split('/')[2] === 's';
        if (isSite) {
            this._vfRoot = origin;
        } else {
            const sandboxSuffix = origin.includes('sandbox') ? '.sandbox' : '';
            this._vfRoot = origin.split('.')[0] + '--c' + sandboxSuffix + '.vf.force.com';
        }
        loadScript(this, jsforcescript).catch(() => {
            this._setStatus('Could not load jsforce — uploads may fail', 'error');
        });
        // Eagerly request GPS so it is ready before Upload All is clicked
        if (this._needsLatLong) this._captureLocation();
    }

    // Returns a Promise<{latitude, longitude} | null>.
    // Concurrent callers share one in-flight request (cached in _latLongPromise).
    //
    // Three-tier strategy — Safari/macOS Core Location often fails the first
    // ask with kCLErrorLocationUnknown even when permission is granted:
    //   1. Low-accuracy + 5-min cached position    — fastest, works on desktop
    //   2. High-accuracy + no cache                — better on mobile with GPS chip
    //   3. watchPosition + low-accuracy             — last resort; the stream API
    //      tends to wake up Core Location when getCurrentPosition can't
    //
    // Permission-denied (code 1) short-circuits — no point hammering the OS.
    _captureLocation() {
        if (!navigator.geolocation) return Promise.resolve(null);
        if (this._latLongPromise)   return this._latLongPromise;

        const oneShot = (opts) => new Promise((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(
                pos => resolve({ latitude: pos.coords.latitude, longitude: pos.coords.longitude }),
                err => reject(err),
                opts
            );
        });

        // watchPosition wrapper — resolves on first reading or hard-timeout
        const watchOnce = (opts, hardTimeoutMs) => new Promise((resolve, reject) => {
            let done = false;
            const watchId = navigator.geolocation.watchPosition(
                pos => {
                    if (done) return;
                    done = true;
                    navigator.geolocation.clearWatch(watchId);
                    resolve({ latitude: pos.coords.latitude, longitude: pos.coords.longitude });
                },
                err => {
                    if (done) return;
                    done = true;
                    navigator.geolocation.clearWatch(watchId);
                    reject(err);
                },
                opts
            );
            setTimeout(() => {
                if (done) return;
                done = true;
                navigator.geolocation.clearWatch(watchId);
                reject(new Error('watchPosition timeout'));
            }, hardTimeoutMs);
        });

        const sleep = (ms) => new Promise(r => setTimeout(r, ms));

        this._latLongPromise = (async () => {
            // Tier 1 — high-accuracy fresh fix, RETRY 3x with backoff
            // Core Location's kCLErrorLocationUnknown is usually transient;
            // a second or third call right after the first often succeeds.
            for (let attempt = 1; attempt <= 3; attempt++) {
                try {
                    this._latLong = await oneShot({ enableHighAccuracy: true, timeout: 5000, maximumAge: 0 });
                    this._latLongPromise = null;
                    return this._latLong;
                } catch (err) {
                    // Permission denied — no retry will help
                    if (err && err.code === 1) {
                        // eslint-disable-next-line no-console
                        console.warn(`Geolocation permission denied: ${err.message}`);
                        this._latLong = null;
                        this._latLongPromise = null;
                        return null;
                    }
                    // eslint-disable-next-line no-console
                    console.warn(`Geolocation tier-1 attempt ${attempt}/3 failed (code ${err && err.code}): ${err && err.message}`);
                    if (attempt < 3) await sleep(800);
                }
            }

            // Tier 2 — low-accuracy, accept any cached fix (fallback when GPS chip unavailable)
            try {
                this._latLong = await oneShot({ enableHighAccuracy: false, timeout: 10000, maximumAge: 5 * 60 * 1000 });
                this._latLongPromise = null;
                return this._latLong;
            } catch (err) {
                if (err && err.code === 1) {
                    this._latLong = null;
                    this._latLongPromise = null;
                    return null;
                }
                // eslint-disable-next-line no-console
                console.warn(`Geolocation tier-2 (low-acc cached) failed (code ${err && err.code}): ${err && err.message}. Trying watchPosition…`);
            }

            // Tier 3 — watchPosition (often succeeds when getCurrentPosition can't)
            try {
                this._latLong = await watchOnce({ enableHighAccuracy: false, timeout: 20000, maximumAge: 5 * 60 * 1000 }, 20000);
                this._latLongPromise = null;
                return this._latLong;
            } catch (err) {
                // eslint-disable-next-line no-console
                console.warn(`Geolocation tier-3 (watchPosition) failed: ${err && (err.message || err.code)}`);
                this._latLong = null;
                this._latLongPromise = null;
                return null;
            }
        })();

        return this._latLongPromise;
    }

    // Awaits any in-flight GPS request when the component still needs lat/long.
    // Returns immediately with whatever is cached when no fix is needed.
    //
    // If we don't yet have coords and the watermark needs them, force a fully
    // fresh _captureLocation() (clear any stale failure cache from page-load).
    // If THAT still fails, query navigator.permissions to give the user
    // actionable guidance — including the "revoke + re-grant" workaround.
    async _ensureLatLong() {
        if (this._latLong)        return this._latLong;
        if (!this._needsLatLong)  return null;

        const watermarkWantsCoords = this.enableWatermark
            && (this.watermarkLatitude || this.watermarkLongitude);

        // Show progress so the user knows we're not just hanging
        if (watermarkWantsCoords) {
            this._setStatus('Acquiring GPS location…', 'info');
        }

        // Force a fresh attempt — clear any cached null-promise from an earlier
        // failed call so we don't silently reuse a dead result
        this._latLongPromise = null;
        const coords = await this._captureLocation();

        if (coords) {
            if (watermarkWantsCoords) this._setStatus('Location captured', 'success');
            return coords;
        }

        if (!watermarkWantsCoords) return null;

        // GPS failed and the watermark wanted coords — give actionable guidance
        let hint = '';
        if (navigator.permissions && navigator.permissions.query) {
            try {
                const perm = await navigator.permissions.query({ name: 'geolocation' });
                if (perm.state === 'denied') {
                    hint = ' (location blocked — enable it in browser site settings)';
                } else if (perm.state === 'granted') {
                    // Permission is on but GPS still won't fix — Core Location is stuck.
                    // Point the user at the only known workaround.
                    hint = ' (try: browser settings → revoke location permission for this site, then reload and grant again)';
                } else {
                    hint = ' (permission not yet granted — please allow when prompted)';
                }
            } catch (e) { /* permissions API not supported — ignore */ }
        }
        this._setStatus(`Location unavailable — uploading without lat/long${hint}`, 'error');
        return null;
    }

    renderedCallback() {
        this.files.forEach(f => {
            if (f.isImage) this._initThumbCanvas(f.id);
        });
        if (this.showEditModal) {
            this._initEditCanvas();
        }
    }

    disconnectedCallback() {
        if (this._stream)    this._stream.getTracks().forEach(t => t.stop());
        if (this._recStream) this._recStream.getTracks().forEach(t => t.stop());
        if (this._recTimer)  clearInterval(this._recTimer);
    }

    // ── video recorder ─────────────────────────────────────────────────────────
    async startVideoRecorder() {
        this.showVideoRecorder = true;
        this.isRecording       = false;
        this.recVideoReady     = false;
        this.recDurationLabel  = '0:00';
        this._recBlob          = null;
        this._recChunks        = [];
        setTimeout(() => this._startRecPreview(), 100);
    }

    async _startRecPreview() {
        try {
            this._recStream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
                audio: true
            });
            const vid = this.template.querySelector('[data-id="recPreviewEl"]');
            if (vid) vid.srcObject = this._recStream;
        } catch (err) {
            this._setStatus(`Camera error: ${err.message}`, 'error');
            this.showVideoRecorder = false;
        }
    }

    startRecording() {
        if (!this._recStream) return;
        this._recChunks = [];
        const mimeType  = MediaRecorder.isTypeSupported('video/webm;codecs=vp9,opus')
            ? 'video/webm;codecs=vp9,opus'
            : MediaRecorder.isTypeSupported('video/webm;codecs=vp8,opus')
                ? 'video/webm;codecs=vp8,opus'
                : 'video/webm';

        try {
            this._mediaRecorder = new MediaRecorder(this._recStream, { mimeType });
        } catch (e) {
            this._setStatus(`Recording not supported: ${e.message}`, 'error');
            return;
        }

        this._mediaRecorder.ondataavailable = e => {
            if (e.data && e.data.size > 0) this._recChunks.push(e.data);
        };
        this._mediaRecorder.onstop = () => this._onRecordingDone();
        this._mediaRecorder.start(1000);

        this.isRecording  = true;
        this._recSeconds  = 0;
        this._recTimer    = setInterval(() => {
            this._recSeconds++;
            const m = Math.floor(this._recSeconds / 60);
            const s = String(this._recSeconds % 60).padStart(2, '0');
            this.recDurationLabel = `${m}:${s}`;
        }, 1000);
    }

    stopRecording() {
        if (this._mediaRecorder && this._mediaRecorder.state !== 'inactive') {
            this._mediaRecorder.stop();
        }
        if (this._recTimer) { clearInterval(this._recTimer); this._recTimer = null; }
        this.isRecording = false;
    }

    _onRecordingDone() {
        const mimeType    = (this._mediaRecorder && this._mediaRecorder.mimeType) || 'video/webm';
        this._recBlob     = new Blob(this._recChunks, { type: mimeType });
        this.recVideoSize = this._formatSize(this._recBlob.size);

        // Read the blob ONCE here — LWS only allows one read of a MediaRecorder blob.
        // Store both the full data URL (for playback) and the base64 portion (for upload).
        const reader = new FileReader();
        reader.onload = (ev) => {
            const dataUrl           = ev.target.result;
            this._recDataUrl        = dataUrl;
            this._rawVideoBase64    = dataUrl.split(';base64,')[1];  // base64 only — safe against MIME commas
            this.recPlaybackSrc     = dataUrl;
            this.recVideoReady      = true;
        };
        reader.readAsDataURL(this._recBlob);
    }

    retakeVideo() {
        this.recVideoReady    = false;
        this.recPlaybackSrc   = '';
        this._recBlob         = null;
        this._recDataUrl      = null;
        this._rawVideoBase64  = null;
        this._recChunks       = [];
        this.recDurationLabel = '0:00';
    }

    useRecordedVideo() {
        if (!this._recBlob || !this._rawVideoBase64) return;
        const ext      = this._recBlob.type.includes('mp4') ? '.mp4' : '.webm';
        const fileName = `video_${Date.now()}${ext}`;
        const file     = new File([this._recBlob], fileName, { type: this._recBlob.type });

        // Stop live preview stream before closing
        if (this._recStream) { this._recStream.getTracks().forEach(t => t.stop()); this._recStream = null; }
        this.showVideoRecorder = false;
        this.recVideoReady     = false;
        this.recPlaybackSrc    = '';
        this._recBlob          = null;
        this._recDataUrl       = null;
        // _rawVideoBase64 is kept — confirmVideoUpload will use it then clear it

        this._rawVideoFile     = file;
        this.videoFileName     = fileName;
        this.videoOriginalSize = this._formatSize(file.size);
        this.videoIsLarge      = file.size > 50 * 1024 * 1024;
        this.showVideoModal    = true;
    }

    stopVideoRecorder() {
        if (this.isRecording) this.stopRecording();
        if (this._recStream) { this._recStream.getTracks().forEach(t => t.stop()); this._recStream = null; }
        this.showVideoRecorder = false;
        this.recVideoReady     = false;
        this.recPlaybackSrc    = '';
        this._recBlob          = null;
        this._recDataUrl       = null;
        this._rawVideoBase64   = null;
        this._recChunks        = [];
    }

    // ── file input ─────────────────────────────────────────────────────────────
    openFilePicker() {
        this.template.querySelector('[data-id="fileInput"]').click();
    }

    handleFileSelect(event) {
        if (this._needsLatLong) this._captureLocation();
        Array.from(event.target.files).forEach(f => this._addFile(f));
        event.target.value = '';
    }

    async _addFile(rawFile) {
        if (this.blockedExtensions) {
            const blocked = this.blockedExtensions.split(',').map(e => e.trim().toLowerCase().replace(/^\./, ''));
            const ext     = (rawFile.name.match(/\.([^.]+)$/) || ['', ''])[1].toLowerCase();
            if (blocked.includes(ext)) {
                this._setStatus(`${rawFile.name} — .${ext} files are not allowed`, 'error');
                return;
            }
        }
        const maxBytes = this.maxFileSizeMb * 1024 * 1024;
        if (rawFile.size > maxBytes) {
            this._setStatus(`${rawFile.name} exceeds ${this.maxFileSizeMb} MB limit`, 'error');
            return;
        }
        if (this.blockPasswordProtected) {
            const isProtected = await this._isPasswordProtected(rawFile);
            if (isProtected) {
                this._setStatus(`${rawFile.name} is password-protected and cannot be uploaded`, 'error');
                return;
            }
        }
        const isImage = rawFile.type.startsWith('image/');
        const id      = `f${this._nextId++}`;
        const ext     = (rawFile.name.match(/\.([^.]+)$/) || ['', ''])[1].toLowerCase();
        const nameNoExt = rawFile.name.replace(/\.[^.]+$/, '');
        this.files = [...this.files, {
            id,
            name:            rawFile.name,
            customName:      nameNoExt,
            displayName:     rawFile.name.length > 22 ? rawFile.name.substring(0, 20) + '…' : rawFile.name,
            sizeLabel:       this._formatSize(rawFile.size),
            type:            rawFile.type,
            isImage,
            iconName:        this._fileIconName(ext),
            rotation:        0,
            compressed:      false,
            masked:          false,
            uploaded:        false,
            _raw:            rawFile,
            _masks:          [],
            _imageEl:        null,
            _previewDataUrl: null
        }];
        if (isImage) {
            setTimeout(() => this._loadThumbCanvas(id, rawFile), 50);
        }
    }

    // ── thumbnail canvas ───────────────────────────────────────────────────────
    _initThumbCanvas(fileId) {
        const canvas = this.template.querySelector(`canvas[data-id="${fileId}"]`);
        if (!canvas || canvas._cfuInit) return;
        canvas._cfuInit = true;
    }

    _loadThumbCanvas(fileId, rawFile) {
        const reader = new FileReader();
        reader.onload = (ev) => {
            const img = new Image();
            img.onload = () => {
                this._updateFile(fileId, { _imageEl: img });
                this._drawThumb(fileId, img);
                // Store a data URL for the merge modal picker
                const off = document.createElement('canvas');
                const s   = Math.min(120 / img.width, 120 / img.height, 1);
                off.width  = Math.round(img.width * s);
                off.height = Math.round(img.height * s);
                off.getContext('2d').drawImage(img, 0, 0, off.width, off.height);
                this._updateFile(fileId, { _previewDataUrl: off.toDataURL('image/jpeg', 0.7) });
            };
            img.src = ev.target.result;
        };
        reader.readAsDataURL(rawFile);
    }

    _drawThumb(fileId, img) {
        const canvas = this.template.querySelector(`canvas[data-id="${fileId}"]`);
        if (!canvas) return;
        const file  = this._getFile(fileId);
        const rot   = file ? file.rotation : 0;
        const masks = file ? file._masks   : [];
        this._drawRotatedOnCanvas(canvas, img, rot, masks, 280, 200);
    }

    _drawRotatedOnCanvas(canvas, img, rotation, masks, maxW, maxH) {
        const rad  = (rotation * Math.PI) / 180;
        const swap = rotation === 90 || rotation === 270;
        const w    = swap ? img.height : img.width;
        const h    = swap ? img.width  : img.height;
        const scale = Math.min(maxW / w, maxH / h, 1);
        canvas.width  = Math.round(w * scale);
        canvas.height = Math.round(h * scale);
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.save();
        ctx.translate(canvas.width / 2, canvas.height / 2);
        ctx.rotate(rad);
        ctx.drawImage(img, -img.width * scale / 2, -img.height * scale / 2, img.width * scale, img.height * scale);
        ctx.restore();
        if (masks && masks.length) {
            ctx.fillStyle = '#000';
            masks.forEach(m => ctx.fillRect(m.x, m.y, m.w, m.h));
        }
    }

    // ── edit modal ─────────────────────────────────────────────────────────────
    openEditModal(event) {
        const fileId = event.currentTarget.dataset.id;
        const file   = this._getFile(fileId);
        if (!file || !file.isImage) return;

        this.editFileId     = fileId;
        this.editFileName   = file.displayName;
        this._editImg       = file._imageEl;
        this._editRotation  = file.rotation;
        this.editMaskActive = false;
        this.editHasMasks   = file._masks.length > 0;
        this.showEditModal  = true;
        // Canvas drawn in renderedCallback after modal renders
    }

    _initEditCanvas() {
        const canvas = this.template.querySelector('[data-id="editCanvas"]');
        if (!canvas || canvas._cfuEditInit) return;
        canvas._cfuEditInit = true;
        canvas.addEventListener('mousedown',  (e) => this._editMaskStart(e));
        canvas.addEventListener('mousemove',  (e) => this._editMaskMove(e));
        canvas.addEventListener('mouseup',    ()  => this._editMaskEnd());
        canvas.addEventListener('mouseleave', ()  => this._editMaskEnd());
        canvas.addEventListener('touchstart', (e) => { e.preventDefault(); this._editMaskStart(this._touchEvt(e)); }, { passive: false });
        canvas.addEventListener('touchmove',  (e) => { e.preventDefault(); this._editMaskMove(this._touchEvt(e));  }, { passive: false });
        canvas.addEventListener('touchend',   ()  => this._editMaskEnd());
        this._redrawEditCanvas();
    }

    _redrawEditCanvas() {
        const canvas = this.template.querySelector('[data-id="editCanvas"]');
        if (!canvas || !this._editImg) return;
        const file = this._getFile(this.editFileId);
        this._drawRotatedOnCanvas(canvas, this._editImg, this._editRotation, file ? file._masks : [], 700, 500);
    }

    closeEditModal() {
        // Sync edit-canvas masks/rotation back to thumbnail
        const file = this._getFile(this.editFileId);
        if (file) {
            this._updateFile(this.editFileId, { rotation: this._editRotation });
            this._drawThumb(this.editFileId, this._editImg);
        }
        this.showEditModal = false;
        this.editFileId    = null;
        this._editImg      = null;
    }

    editRotateLeft()  { this._applyEditRotate(-90); }
    editRotateRight() { this._applyEditRotate(90);  }

    _applyEditRotate(dir) {
        this._editRotation = ((this._editRotation + dir) + 360) % 360;
        this._updateFile(this.editFileId, { rotation: this._editRotation });
        this._redrawEditCanvas();
    }

    editCompress() {
        const canvas = this.template.querySelector('[data-id="editCanvas"]');
        if (!canvas) return;
        const file = this._getFile(this.editFileId);
        canvas.toBlob(blob => {
            const compressed = new File([blob], file.name, { type: 'image/jpeg' });
            this._updateFile(this.editFileId, {
                _raw:       compressed,
                compressed: true,
                sizeLabel:  this._formatSize(compressed.size)
            });
            this._setStatus(`Compressed to ${this._formatSize(compressed.size)}`, 'success');
        }, 'image/jpeg', 0.6);
    }

    editToggleMask() {
        this.editMaskActive = !this.editMaskActive;
        const canvas = this.template.querySelector('[data-id="editCanvas"]');
        if (canvas) canvas.style.cursor = this.editMaskActive ? 'crosshair' : 'default';
    }

    editClearMasks() {
        this._updateFile(this.editFileId, { _masks: [], masked: false });
        this.editHasMasks = false;
        this._redrawEditCanvas();
    }

    _editMaskStart(e) {
        if (!this.editMaskActive) return;
        const canvas = this.template.querySelector('[data-id="editCanvas"]');
        if (!canvas) return;
        const rect = canvas.getBoundingClientRect();
        this._maskingState['edit'] = {
            isDrawing: true,
            lastX: e.clientX - rect.left,
            lastY: e.clientY - rect.top
        };
    }

    _editMaskMove(e) {
        const state = this._maskingState['edit'];
        if (!state || !state.isDrawing || !this.editMaskActive) return;
        const canvas = this.template.querySelector('[data-id="editCanvas"]');
        if (!canvas) return;
        const rect  = canvas.getBoundingClientRect();
        const x     = e.clientX - rect.left;
        const y     = e.clientY - rect.top;
        const thick = 28;
        canvas.getContext('2d').fillStyle = '#000';
        canvas.getContext('2d').fillRect(x - thick / 2, y - thick / 2, thick, thick);
        const file  = this._getFile(this.editFileId);
        const masks = [...(file ? file._masks : []), { x: x - thick / 2, y: y - thick / 2, w: thick, h: thick }];
        this._updateFile(this.editFileId, { _masks: masks, masked: true });
        this.editHasMasks = true;
        state.lastX = x;
        state.lastY = y;
    }

    _editMaskEnd() {
        const state = this._maskingState['edit'];
        if (state) state.isDrawing = false;
    }

    // ── merge modal ────────────────────────────────────────────────────────────
    openMergeModal() {
        this.mergeSelectedIds  = [];
        this.mergeOrderedFiles = [...this.files.filter(f => f.isImage)];
        this.showMergeModal    = true;
    }

    closeMergeModal() {
        this.showMergeModal    = false;
        this.mergeOrderedFiles = [];
    }

    toggleMergeSelect(event) {
        const id  = event.currentTarget.dataset.id;
        const idx = this.mergeSelectedIds.indexOf(id);
        if (idx === -1) {
            this.mergeSelectedIds = [...this.mergeSelectedIds, id];
        } else {
            this.mergeSelectedIds = this.mergeSelectedIds.filter(x => x !== id);
        }
    }

    // ── merge reorder: arrow buttons ──────────────────────────────────────────
    mergeMoveLeft(event) {
        event.stopPropagation();
        const id  = event.currentTarget.dataset.id;
        const arr = [...this.mergeOrderedFiles];
        const idx = arr.findIndex(f => f.id === id);
        if (idx <= 0) return;
        [arr[idx - 1], arr[idx]] = [arr[idx], arr[idx - 1]];
        this.mergeOrderedFiles = arr;
    }

    mergeMoveRight(event) {
        event.stopPropagation();
        const id  = event.currentTarget.dataset.id;
        const arr = [...this.mergeOrderedFiles];
        const idx = arr.findIndex(f => f.id === id);
        if (idx < 0 || idx >= arr.length - 1) return;
        [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
        this.mergeOrderedFiles = arr;
    }

    // ── merge reorder: drag-and-drop ──────────────────────────────────────────
    mergeDragStart(event) {
        this._dragSrcId = event.currentTarget.dataset.id;
        event.dataTransfer.effectAllowed = 'move';
    }

    mergeDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
    }

    mergeDrop(event) {
        event.preventDefault();
        const targetId = event.currentTarget.dataset.id;
        if (!this._dragSrcId || this._dragSrcId === targetId) return;
        const arr     = [...this.mergeOrderedFiles];
        const srcIdx  = arr.findIndex(f => f.id === this._dragSrcId);
        const tgtIdx  = arr.findIndex(f => f.id === targetId);
        if (srcIdx < 0 || tgtIdx < 0) return;
        const [moved] = arr.splice(srcIdx, 1);
        arr.splice(tgtIdx, 0, moved);
        this.mergeOrderedFiles = arr;
        this._dragSrcId = null;
    }

    mergeDragEnd() {
        this._dragSrcId = null;
    }

    async doMergePDF() {
        if (this.isMerging || this.mergeSelectedIds.length < 2) return;
        this.isMerging = true;
        this._setStatus('Merging selected images into PDF…', 'info');
        try {
            // Respect the display order (drag/arrow reordered), filter to selected
            const ordered = this.mergeOrderedFiles.length
                ? this.mergeOrderedFiles
                : this.files.filter(f => f.isImage);
            const selectedFiles = ordered
                .filter(f => this.mergeSelectedIds.includes(f.id))
                .map(f => this._getFile(f.id))
                .filter(Boolean);
            const pdfBytes   = await this._buildPDF(selectedFiles);
            const blob       = new Blob([pdfBytes], { type: 'application/pdf' });
            const mergedFile = new File([blob], `merged_${Date.now()}.pdf`, { type: 'application/pdf' });
            // Remove only the selected images, keep the rest
            this.files = this.files.filter(f => !this.mergeSelectedIds.includes(f.id));
            this.closeMergeModal();
            this._addFile(mergedFile);
            this._setStatus(`Merged ${selectedFiles.length} images into PDF`, 'success');
        } catch (err) {
            this._setStatus(`Merge failed: ${err.message}`, 'error');
        }
        this.isMerging = false;
    }

    // ── refresh ────────────────────────────────────────────────────────────────
    handleRefresh() {
        this.files             = [];
        this.capturedPhotos    = [];
        this.showCamera        = false;
        this.showEditModal     = false;
        this.showMergeModal    = false;
        this.showVideoModal    = false;
        this.showVideoRecorder = false;
        this.isRecording       = false;
        this.recVideoReady     = false;
        this.mergeSelectedIds  = [];
        this.mergeOrderedFiles = [];
        this.statusMessage     = '';
        this.uploadProgress    = 0;
        this.isUploading       = false;
        this.isMerging         = false;
        this.isCompressing     = false;
        this.compressProgress  = 0;
        this._nextId           = 1;
        this._latLong          = null;
        this._rawVideoFile     = null;
        this._rawVideoBase64   = null;
        if (this._recStream)  { this._recStream.getTracks().forEach(t => t.stop()); this._recStream = null; }
        if (this._recTimer)   { clearInterval(this._recTimer); this._recTimer = null; }
        this._recBlob    = null;
        this._recChunks  = [];
        if (this._needsLatLong) this._captureLocation();
    }

    // ── video upload ───────────────────────────────────────────────────────────
    openVideoPicker() {
        this.template.querySelector('[data-id="videoInput"]').click();
    }

    handleVideoSelect(event) {
        const file = event.target.files[0];
        event.target.value = '';
        if (!file) return;
        this._rawVideoFile      = file;
        this.videoFileName      = file.name;
        this.videoOriginalSize  = this._formatSize(file.size);
        this.videoIsLarge       = file.size > 50 * 1024 * 1024;
        this.videoQuality       = 'medium';
        this.compressProgress   = 0;
        this.isCompressing      = false;
        this.showVideoModal     = true;
    }

    setVideoQuality(event) {
        this.videoQuality = event.currentTarget.dataset.q;
    }

    closeVideoModal() {
        if (this.isCompressing) return;
        this.showVideoModal  = false;
        this._rawVideoFile   = null;
    }

    async confirmVideoUpload() {
        if (!this._rawVideoFile) return;

        let fileToUpload     = this._rawVideoFile;
        let preloadedB64     = this._rawVideoBase64 || null;  // populated for recorded videos
        this.showVideoModal  = false;
        this._rawVideoFile   = null;
        this._rawVideoBase64 = null;

        if (!this.entityId)   { this._setStatus('No recordId — cannot upload', 'error'); return; }
        if (!this._sessionId) { this._setStatus('Session not ready — please retry', 'error'); return; }

        // Wait for GPS to resolve before drawing the watermark — otherwise
        // lat/long lines will silently be skipped if the user clicked Upload
        // before the initial getCurrentPosition resolved.
        if (this.enableWatermark) await this._ensureLatLong();

        // Burn watermark into the video frames if config asks for it. The
        // resulting file is a fresh File object, so the pre-computed base64
        // (recorded-video shortcut) is no longer valid — drop it and let the
        // upload path re-read the new file.
        if (this.enableWatermark && this._buildWatermarkText()) {
            try {
                fileToUpload = await this._applyVideoWatermark(fileToUpload);
                preloadedB64 = null;
            } catch (err) {
                this._setStatus(`Watermark failed: ${err.message}`, 'error');
                return;
            }
        }

        const MULTIPART_THRESHOLD = 50 * 1024 * 1024;
        if (fileToUpload.size > MULTIPART_THRESHOLD) {
            await this._uploadVideoMultipart(fileToUpload);
        } else {
            await this._uploadVideoStandard(fileToUpload, preloadedB64);
        }
    }

    // Uses MediaRecorder to re-encode video at a lower bitrate
    _compressVideo(file, quality) {
        const bitrates = { high: 1_500_000, medium: 600_000, low: 200_000 };
        const targetBitsPerSec = bitrates[quality] || 600_000;

        return new Promise((resolve, reject) => {
            const url   = URL.createObjectURL(file);
            const video = document.createElement('video');
            video.src   = url;
            video.muted = true;

            video.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Could not load video for compression')); };

            video.onloadedmetadata = () => {
                const canvas  = document.createElement('canvas');
                canvas.width  = video.videoWidth  || 640;
                canvas.height = video.videoHeight || 360;
                const ctx     = canvas.getContext('2d');
                const stream  = canvas.captureStream(30);

                // Prefer VP9, fall back to VP8
                const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
                    ? 'video/webm;codecs=vp9'
                    : 'video/webm;codecs=vp8';

                let recorder;
                try {
                    recorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: targetBitsPerSec });
                } catch (e) {
                    URL.revokeObjectURL(url);
                    reject(new Error(`MediaRecorder not supported: ${e.message}`));
                    return;
                }

                const chunks = [];
                recorder.ondataavailable = e => { if (e.data.size > 0) chunks.push(e.data); };

                const duration = video.duration || 0;
                recorder.onstop = () => {
                    URL.revokeObjectURL(url);
                    const blob     = new Blob(chunks, { type: mimeType });
                    const nameBase = file.name.replace(/\.[^.]+$/, '');
                    resolve(new File([blob], `${nameBase}_compressed.webm`, { type: mimeType }));
                };

                video.play().then(() => {
                    recorder.start(1000); // collect in 1-second chunks

                    // Draw frames and track progress
                    const drawFrame = () => {
                        if (video.paused || video.ended) {
                            recorder.stop();
                            stream.getTracks().forEach(t => t.stop());
                            return;
                        }
                        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                        if (duration > 0) {
                            this.compressProgress = Math.round((video.currentTime / duration) * 100);
                        }
                        requestAnimationFrame(drawFrame);
                    };
                    this.isCompressing    = true;
                    this.compressProgress = 0;
                    drawFrame();
                }).catch(err => {
                    URL.revokeObjectURL(url);
                    reject(err);
                });

                video.onended = () => {
                    recorder.stop();
                    stream.getTracks().forEach(t => t.stop());
                    this.isCompressing    = false;
                    this.compressProgress = 100;
                };
            };
        });
    }

    // Standard jsforce upload — works for files up to ~37 MB actual (50 MB base64 limit)
    async _uploadVideoStandard(file, preloadedBase64 = null) {
        this.isUploading    = true;
        this.uploadProgress = 0;
        this._setStatus(`Uploading ${file.name}…`, 'info');

        try {
            // Use pre-computed base64 for recorded videos — LWS only allows one FileReader
            // read of a MediaRecorder blob, which was already done in _onRecordingDone.
            const base64 = preloadedBase64
                ? preloadedBase64
                : await new Promise((resolve, reject) => {
                    const reader   = new FileReader();
                    reader.onload  = () => { const r = reader.result; resolve(r.split(';base64,')[1]); };
                    reader.onerror = reject;
                    reader.readAsDataURL(file);
                });

            const conn = new window.jsforce.Connection({
                serverUrl: this._vfRoot,
                sessionId: this._sessionId
            });

            const nameBase = file.name.replace(/\.[^.]+$/, '').trim() || 'video';
            const ext      = (file.name.match(/\.[^.]+$/) || ['.webm'])[0];
            const fileName = nameBase + ext;

            const record = {
                Title:                  fileName,
                PathOnClient:           fileName,
                VersionData:            base64,
                FirstPublishLocationId: this.entityId
            };
            if (this.captureLatLong && this._latLong) {
                record.Capture_Latitude__c  = this._latLong.latitude;
                record.Capture_Longitude__c = this._latLong.longitude;
            }

            await new Promise((resolve, reject) => {
                conn.sobject('ContentVersion').create(record, (err, ret) => {
                    if (err || !ret.success) return reject(err || new Error('Upload failed'));
                    resolve(ret);
                });
            });
            this.uploadProgress = 100;
            this._setStatus(`Video uploaded: ${fileName}`, 'success');
        } catch (err) {
            this._setStatus(`Video upload failed: ${err.message}`, 'error');
        } finally {
            this.isUploading = false;
        }
    }

    // Multipart REST upload — handles files > 50 MB (up to 2 GB)
    // Sends JSON metadata + binary file part in a single multipart/form-data POST
    async _uploadVideoMultipart(file) {
        this.isUploading    = true;
        this.uploadProgress = 0;
        this._setStatus(`Uploading large video (${this._formatSize(file.size)}) — this may take a while…`, 'info');

        try {
            const nameBase = file.name.replace(/\.[^.]+$/, '').trim() || 'video';
            const ext      = (file.name.match(/\.[^.]+$/) || ['.webm'])[0];
            const fileName = nameBase + ext;

            const metadata = {
                Title:                  fileName,
                PathOnClient:           fileName,
                FirstPublishLocationId: this.entityId
            };
            if (this.captureLatLong && this._latLong) {
                metadata.Capture_Latitude__c  = this._latLong.latitude;
                metadata.Capture_Longitude__c = this._latLong.longitude;
            }

            const boundary = `boundary_${Date.now()}`;
            const metaJson = JSON.stringify(metadata);

            // Build multipart body: metadata part + file part
            const enc       = new TextEncoder();
            const metaPart  = enc.encode(
                `--${boundary}\r\nContent-Disposition: form-data; name="entity_content"\r\nContent-Type: application/json\r\n\r\n${metaJson}\r\n`
            );
            const filePart1 = enc.encode(
                `--${boundary}\r\nContent-Disposition: form-data; name="VersionData"; filename="${fileName}"\r\nContent-Type: ${file.type || 'video/webm'}\r\n\r\n`
            );
            const filePart2 = enc.encode(`\r\n--${boundary}--\r\n`);

            const fileBytes = await file.arrayBuffer();
            const total     = metaPart.length + filePart1.length + fileBytes.byteLength + filePart2.length;
            const body      = new Uint8Array(total);
            let pos = 0;
            body.set(metaPart,  pos); pos += metaPart.length;
            body.set(filePart1, pos); pos += filePart1.length;
            body.set(new Uint8Array(fileBytes), pos); pos += fileBytes.byteLength;
            body.set(filePart2, pos);

            // Use XHR so we can track upload progress
            await new Promise((resolve, reject) => {
                const xhr = new XMLHttpRequest();
                const apiUrl = `${this._vfRoot}/services/data/v59.0/sobjects/ContentVersion`;
                xhr.open('POST', apiUrl, true);
                xhr.setRequestHeader('Authorization', `Bearer ${this._sessionId}`);
                xhr.setRequestHeader('Content-Type', `multipart/form-data; boundary=${boundary}`);

                xhr.upload.onprogress = (e) => {
                    if (e.lengthComputable) {
                        this.uploadProgress = Math.round((e.loaded / e.total) * 100);
                    }
                };
                xhr.onload = () => {
                    if (xhr.status >= 200 && xhr.status < 300) {
                        resolve(JSON.parse(xhr.responseText));
                    } else {
                        reject(new Error(`HTTP ${xhr.status}: ${xhr.responseText}`));
                    }
                };
                xhr.onerror = () => reject(new Error('Network error during multipart upload'));
                xhr.send(body.buffer);
            });

            this.uploadProgress = 100;
            this._setStatus(`Large video uploaded: ${fileName}`, 'success');
        } catch (err) {
            this._setStatus(`Video upload failed: ${err.message}`, 'error');
        } finally {
            this.isUploading = false;
        }
    }

    // ── remove file ────────────────────────────────────────────────────────────
    removeFile(event) {
        const fileId = event.currentTarget.dataset.id;
        this.files = this.files.filter(f => f.id !== fileId);
    }

    // ── editable filename ──────────────────────────────────────────────────────
    handleCustomNameChange(event) {
        const fileId = event.currentTarget.dataset.id;
        this._updateFile(fileId, { customName: event.target.value });
    }

    // ── camera ─────────────────────────────────────────────────────────────────
    startCamera() {
        this.capturedPhotos = [];
        this.showCamera     = true;
        setTimeout(() => this._startStream(), 100);
    }

    async _startStream() {
        try {
            // exact:environment prevents browser from prompting the gallery on mobile
            this._stream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
                audio: false
            });
            const video = this.template.querySelector('[data-id="videoEl"]');
            if (video) video.srcObject = this._stream;
        } catch (err) {
            this._setStatus(`Camera error: ${err.message}`, 'error');
            this.showCamera = false;
        }
    }

    capturePhoto() {
        const video = this.template.querySelector('[data-id="videoEl"]');
        if (!video) return;
        const off   = document.createElement('canvas');
        off.width   = video.videoWidth  || 640;
        off.height  = video.videoHeight || 480;
        off.getContext('2d').drawImage(video, 0, 0, off.width, off.height);
        this.capturedPhotos = [...this.capturedPhotos, {
            id:      `cap${this._nextId++}`,
            dataUrl: off.toDataURL('image/jpeg', 0.9)
        }];
    }

    deleteCapturedPhoto(event) {
        const id = event.currentTarget.dataset.id;
        this.capturedPhotos = this.capturedPhotos.filter(p => p.id !== id);
    }

    addCapturedToFiles() {
        this.capturedPhotos.forEach((photo, idx) => {
            const blob    = this._dataUrlToBlob(photo.dataUrl);
            const rawFile = new File([blob], `photo_${Date.now()}_${idx + 1}.jpg`, { type: 'image/jpeg' });
            this._addFile(rawFile);
        });
        this.stopCamera();
    }

    stopCamera() {
        if (this._stream) {
            this._stream.getTracks().forEach(t => t.stop());
            this._stream = null;
        }
        this.showCamera     = false;
        this.capturedPhotos = [];
    }

    _dataUrlToBlob(dataUrl) {
        const parts = dataUrl.split(',');
        const mime  = parts[0].match(/:(.*?);/)[1];
        const bstr  = atob(parts[1]);
        let n = bstr.length;
        const u8 = new Uint8Array(n);
        while (n--) u8[n] = bstr.charCodeAt(n);
        return new Blob([u8], { type: mime });
    }

    _touchEvt(e) {
        const t = e.touches[0];
        return { clientX: t.clientX, clientY: t.clientY };
    }

    // ── PDF builder ────────────────────────────────────────────────────────────
    async _buildPDF(imageFiles) {
        const images = [];
        // Use the edit canvas if currently open for that file, otherwise render fresh
        for (const file of imageFiles) {
            const thumb = this.template.querySelector(`canvas[data-id="${file.id}"]`);
            // Draw at full quality into an offscreen canvas
            const off = document.createElement('canvas');
            if (file._imageEl) {
                this._drawRotatedOnCanvas(off, file._imageEl, file.rotation, file._masks, file._imageEl.width, file._imageEl.height);
            } else if (thumb) {
                off.width  = thumb.width;
                off.height = thumb.height;
                off.getContext('2d').drawImage(thumb, 0, 0);
            }
            this._drawImageWatermark(off);
            const blob = await new Promise(res => off.toBlob(res, 'image/jpeg', 0.85));
            const buf  = await blob.arrayBuffer();
            images.push({ bytes: new Uint8Array(buf), width: off.width, height: off.height });
        }

        const pageW = 595, pageH = 842;
        const enc   = (s) => new TextEncoder().encode(s);

        // Each entry: { type: 'text'|'stream'|'imageStream', content, imageIndex }
        const objs = [];
        const add  = (type, content, imageIndex) =>
            objs.push({ num: objs.length + 1, type, content, imageIndex });

        // Obj 1 — Catalog
        add('text', '<< /Type /Catalog /Pages 2 0 R >>');

        // Per page we emit 3 objects: Page, ContentStream, ImageXObject
        // Kids array: page objects are at 3, 6, 9, ... (every 3rd starting at 3)
        const pageObjNums = images.map((_, i) => 3 + i * 3);
        add('text', `<< /Type /Pages /Kids [${pageObjNums.map(n => `${n} 0 R`).join(' ')}] /Count ${images.length} >>`);

        for (let i = 0; i < images.length; i++) {
            const img    = images[i];
            const contId = 3 + i * 3 + 1;   // content stream object number
            const imgId  = 3 + i * 3 + 2;   // image XObject number
            const sc     = Math.min(pageW / img.width, pageH / img.height);
            const dW     = Math.round(img.width  * sc);
            const dH     = Math.round(img.height * sc);
            const xO     = Math.round((pageW - dW) / 2);
            const yO     = Math.round((pageH - dH) / 2);
            const stm    = `q ${dW} 0 0 ${dH} ${xO} ${yO} cm /Im${i} Do Q`;

            // Page dict — /Contents refs the content stream object
            add('text',
                `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageW} ${pageH}] ` +
                `/Resources << /XObject << /Im${i} ${imgId} 0 R >> >> ` +
                `/Contents ${contId} 0 R >>`
            );
            // Content stream — the page drawing instructions
            add('stream', stm);
            // Image XObject — the JPEG bytes
            add('imageStream',
                `<< /Type /XObject /Subtype /Image /Width ${img.width} /Height ${img.height} ` +
                `/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${img.bytes.length} >>`,
                i
            );
        }

        // ── serialize ──────────────────────────────────────────────────────────
        const chunks  = [];
        const push    = (s) => chunks.push(enc(s));
        let   offset  = 0;
        const addLen  = (s) => { offset += s.length; };

        push('%PDF-1.4\n'); offset = 9;
        const offsets = [];

        for (const obj of objs) {
            offsets.push(offset);
            const hdr = `${obj.num} 0 obj\n`;
            push(hdr); offset += hdr.length;

            if (obj.type === 'text') {
                const b = `${obj.content}\nendobj\n`;
                push(b); offset += b.length;

            } else if (obj.type === 'stream') {
                const stmBytes = enc(obj.content);
                const dict = `<< /Length ${stmBytes.length} >>\nstream\n`;
                const tail = '\nendstream\nendobj\n';
                push(dict);    offset += dict.length;
                chunks.push(stmBytes); offset += stmBytes.length;
                push(tail);    offset += tail.length;

            } else {
                // imageStream
                const img  = images[obj.imageIndex];
                const head = `${obj.content}\nstream\n`;
                const tail = '\nendstream\nendobj\n';
                push(head);     offset += head.length;
                chunks.push(img.bytes); offset += img.bytes.length;
                push(tail);     offset += tail.length;
            }
        }

        const xr = offset;
        push(`xref\n0 ${objs.length + 1}\n`);
        push(`0000000000 65535 f \n`);
        offsets.forEach(o => push(`${String(o).padStart(10, '0')} 00000 n \n`));
        push(`trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xr}\n%%EOF\n`);

        const total = chunks.reduce((s, c) => s + c.length, 0);
        const out   = new Uint8Array(total);
        let pos = 0;
        for (const c of chunks) { out.set(c, pos); pos += c.length; }
        return out;
    }

    // ── upload ─────────────────────────────────────────────────────────────────
    async uploadAll() {
        if (this.isUploading) return;
        const pending = this.files.filter(f => !f.uploaded);
        if (!pending.length)   { this._setStatus('No files to upload', 'info'); return; }
        if (!this.entityId)    { this._setStatus('No recordId — place component on a record page or pass recordId', 'error'); return; }
        if (!this._sessionId)  { this._setStatus('Session not ready — please retry in a moment', 'error'); return; }
        if (!this._vfRoot)     { this._setStatus('Server URL not ready — please retry', 'error'); return; }

        // Run custom validator if configured
        if (this.validatorClass) {
            try {
                const errors = await runUploadValidator({
                    validatorClassName: this.validatorClass,
                    recordId:           this.entityId
                });
                if (errors && errors.length > 0) {
                    this._setStatus(errors.join(' | '), 'error');
                    return;
                }
            } catch (err) {
                this._setStatus(`Validator error: ${err.body ? err.body.message : err.message}`, 'error');
                return;
            }
        }

        // Wait once for GPS before the upload loop, so every image in the
        // batch gets the same coordinates baked into its watermark instead
        // of some files racing the geolocation promise.
        if (this.enableWatermark || this.captureLatLong) await this._ensureLatLong();

        this.isUploading    = true;
        this.uploadProgress = 0;
        let done = 0;

        for (const file of pending) {
            try {
                const ret = await this._uploadFile(file);
                this._updateFile(file.id, { uploaded: true, contentVersionId: ret.id || null });
                done++;
                this.uploadProgress = Math.round((done / pending.length) * 100);
            } catch (err) {
                this._setStatus(`Failed: ${file.displayName} — ${err.message}`, 'error');
            }
        }
        this.isUploading = false;
        this._setStatus(`Uploaded ${done} of ${pending.length} file(s)`, done === pending.length ? 'success' : 'error');
    }

    async _uploadFile(file) {
        // Render final blob at full resolution — rotation + masks + watermark baked in
        let blob;
        if (file.isImage) {
            const off = document.createElement('canvas');
            if (file._imageEl) {
                this._drawRotatedOnCanvas(off, file._imageEl, file.rotation, file._masks, file._imageEl.width, file._imageEl.height);
                this._drawImageWatermark(off);
                blob = await new Promise(res => off.toBlob(res, 'image/jpeg', 0.85));
            } else {
                blob = file._raw;
            }
        } else {
            blob = file._raw;
        }

        const ext      = file.isImage ? '.jpg' : (file.name.match(/\.[^.]+$/) || [''])[0];
        const baseName = (file.customName || file.name.replace(/\.[^.]+$/, '')).trim() || file.name.replace(/\.[^.]+$/, '');
        const fileName = baseName + ext;

        // Read as base64 for jsforce — same approach used by fileUpload & documentUploader in this org
        const base64 = await new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload  = () => resolve(reader.result.split(',')[1]);
            reader.onerror = reject;
            reader.readAsDataURL(blob);
        });

        // jsforce Connection — serverUrl is the VF domain (avoids CORS), sessionId from Apex/VF
        const conn = new window.jsforce.Connection({
            serverUrl: this._vfRoot,
            sessionId: this._sessionId
        });

        const record = {
            Title:                  fileName,
            PathOnClient:           fileName,
            VersionData:            base64,
            FirstPublishLocationId: this.entityId
        };
        if (this.captureLatLong && this._latLong) {
            record.Capture_Latitude__c  = this._latLong.latitude;
            record.Capture_Longitude__c = this._latLong.longitude;
        }

        return new Promise((resolve, reject) => {
            conn.sobject('ContentVersion').create(record, (err, ret) => {
                if (err || !ret.success) return reject(err || new Error('jsforce create failed'));
                resolve(ret);
            });
        });
    }

    // ── watermark ──────────────────────────────────────────────────────────────
    // Build the array of watermark lines based on design config + runtime data.
    // Returns null when watermarking is off or no usable line could be assembled
    // (e.g. user asked for lat/long but GPS was denied and date-time is off).
    _buildWatermarkText() {
        if (!this.enableWatermark) return null;
        const lines = [];
        if (this.watermarkDateTime) {
            const d   = new Date();
            const pad = n => String(n).padStart(2, '0');
            lines.push(
                `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
                `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
            );
        }
        if (this.watermarkLatitude && this._latLong) {
            lines.push(`Lat:  ${this._latLong.latitude.toFixed(6)}`);
        }
        if (this.watermarkLongitude && this._latLong) {
            lines.push(`Long: ${this._latLong.longitude.toFixed(6)}`);
        }
        return lines.length ? lines : null;
    }

    // Draws the watermark on the given canvas in place. Designed to be the
    // LAST step after the image has already been drawn — keeps the watermark
    // unmistakably on top of everything else (rotation, masks, etc.).
    //
    // Text-only: no background box, so nothing behind the watermark is
    // occluded. Readability comes from a black stroke (outline) under the
    // white fill — works on both light and dark backgrounds.
    _drawImageWatermark(canvas) {
        const lines = this._buildWatermarkText();
        if (!lines) return;

        const ctx = canvas.getContext('2d');
        const W   = canvas.width;
        const H   = canvas.height;
        // Scale font with the image's shorter side so watermark stays readable
        // on both portrait phone shots and wide DSLR captures.
        const fontSize   = Math.max(14, Math.round(Math.min(W, H) * 0.028));
        const padding    = Math.round(fontSize * 0.6);
        const lineHeight = Math.round(fontSize * 1.3);

        ctx.save();
        ctx.font        = `bold ${fontSize}px sans-serif`;
        ctx.fillStyle   = '#ffffff';
        ctx.strokeStyle = '#000000';
        // Outline width scales with font — thick enough to read on bright backgrounds
        ctx.lineWidth   = Math.max(2, Math.round(fontSize * 0.18));
        ctx.lineJoin    = 'round';
        ctx.miterLimit  = 2;

        const pos = (this.watermarkPosition || 'Right Bottom').trim();

        // Strokes the outline first, then fills the white text — standard
        // "outlined text" technique. No background fill rectangle.
        const drawLine = (line, x, y) => {
            ctx.strokeText(line, x, y);
            ctx.fillText(line, x, y);
        };

        if (pos === 'Diagonal') {
            // Spans the image bottom-left → top-right
            ctx.translate(W / 2, H / 2);
            ctx.rotate(-Math.atan2(H, W));
            ctx.textAlign    = 'center';
            ctx.textBaseline = 'middle';
            lines.forEach((line, i) => {
                const y = (i - (lines.length - 1) / 2) * lineHeight;
                drawLine(line, 0, y);
            });
        } else {
            const widths   = lines.map(l => ctx.measureText(l).width);
            const blockW   = Math.max(...widths);
            const blockH   = lines.length * lineHeight;

            let x;
            let y;
            switch (pos) {
                case 'Right Top':    x = W - blockW - padding; y = padding;                break;
                case 'Right Bottom':
                case 'Right Below':  x = W - blockW - padding; y = H - blockH - padding;   break;
                case 'Left Top':     x = padding;              y = padding;                break;
                case 'Left Bottom':
                case 'Left Below':   x = padding;              y = H - blockH - padding;   break;
                default:             x = W - blockW - padding; y = H - blockH - padding;
            }

            ctx.textAlign    = 'left';
            ctx.textBaseline = 'top';
            lines.forEach((line, i) => {
                drawLine(line, x, y + i * lineHeight);
            });
        }

        ctx.restore();
    }

    // Re-encodes a video file through an offscreen canvas, burning the
    // watermark into every frame. Audio is dropped — adding it would require
    // routing through WebAudio (out of scope for this canvas-overlay pass).
    // The recoded file is returned as a new File and replaces the original
    // in the upload pipeline.
    async _applyVideoWatermark(file) {
        return new Promise((resolve, reject) => {
            const url   = URL.createObjectURL(file);
            const video = document.createElement('video');
            video.src         = url;
            video.muted       = true;
            video.playsInline = true;

            video.onerror = () => {
                URL.revokeObjectURL(url);
                reject(new Error('Could not load video for watermarking'));
            };

            video.onloadedmetadata = () => {
                const canvas  = document.createElement('canvas');
                canvas.width  = video.videoWidth  || 640;
                canvas.height = video.videoHeight || 360;
                const ctx     = canvas.getContext('2d');
                const stream  = canvas.captureStream(30);

                const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
                    ? 'video/webm;codecs=vp9'
                    : MediaRecorder.isTypeSupported('video/webm;codecs=vp8')
                        ? 'video/webm;codecs=vp8'
                        : 'video/webm';

                let recorder;
                try {
                    // Preserve quality — pick a fairly high bitrate proportional to resolution
                    const bits = Math.max(1_500_000, canvas.width * canvas.height * 2);
                    recorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: bits });
                } catch (e) {
                    URL.revokeObjectURL(url);
                    reject(new Error(`MediaRecorder not supported: ${e.message}`));
                    return;
                }

                const chunks = [];
                recorder.ondataavailable = e => { if (e.data && e.data.size > 0) chunks.push(e.data); };
                recorder.onstop = () => {
                    URL.revokeObjectURL(url);
                    this.isCompressing    = false;
                    this.compressProgress = 100;
                    const blob     = new Blob(chunks, { type: mimeType });
                    const nameBase = file.name.replace(/\.[^.]+$/, '');
                    resolve(new File([blob], `${nameBase}_wm.webm`, { type: mimeType }));
                };

                const duration = video.duration || 0;

                video.play().then(() => {
                    recorder.start(1000);
                    this.isCompressing    = true;
                    this.compressProgress = 0;
                    this._setStatus('Adding watermark to video…', 'info');

                    const drawFrame = () => {
                        if (video.paused || video.ended) {
                            if (recorder.state !== 'inactive') recorder.stop();
                            stream.getTracks().forEach(t => t.stop());
                            return;
                        }
                        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                        this._drawImageWatermark(canvas);
                        if (duration > 0) {
                            this.compressProgress = Math.round((video.currentTime / duration) * 100);
                        }
                        requestAnimationFrame(drawFrame);
                    };
                    drawFrame();
                }).catch(err => {
                    URL.revokeObjectURL(url);
                    reject(err);
                });

                video.onended = () => {
                    if (recorder.state !== 'inactive') recorder.stop();
                    stream.getTracks().forEach(t => t.stop());
                };
            };
        });
    }

    // ── helpers ────────────────────────────────────────────────────────────────

    _fileIconName(ext) {
        if (['jpg','jpeg','png','gif','bmp','webp','svg','tiff','tif'].includes(ext)) return 'doctype:image';
        if (ext === 'pdf')                       return 'doctype:pdf';
        if (['xls','xlsx'].includes(ext))        return 'doctype:excel';
        if (ext === 'csv')                       return 'doctype:csv';
        if (['doc','docx'].includes(ext))        return 'doctype:word';
        if (['ppt','pptx'].includes(ext))        return 'doctype:ppt';
        if (ext === 'txt')                       return 'doctype:txt';
        if (ext === 'zip')                       return 'doctype:zip';
        return 'doctype:unknown';
    }

    // Reads the first 8 bytes to detect password protection:
    // PDF: searches first 4 KB for /Encrypt keyword
    // DOCX/XLSX (Open XML): PK magic = fine; D0 CF 11 E0 = OLE2 compound doc = encrypted
    async _isPasswordProtected(file) {
        const ext = (file.name.match(/\.([^.]+)$/) || ['', ''])[1].toLowerCase();
        try {
            if (ext === 'pdf') {
                // Read first 4 KB — enough to find the /Encrypt dict reference in the header
                const slice  = file.slice(0, 4096);
                const buffer = await slice.arrayBuffer();
                const text   = new TextDecoder('latin1').decode(buffer);
                return text.includes('/Encrypt');
            }
            if (['docx','xlsx','pptx','doc','xls','ppt'].includes(ext)) {
                const slice  = file.slice(0, 8);
                const buffer = await slice.arrayBuffer();
                const bytes  = new Uint8Array(buffer);
                // OLE2 magic = D0 CF 11 E0 — used by encrypted Office files
                const isOle2 = bytes[0] === 0xD0 && bytes[1] === 0xCF &&
                               bytes[2] === 0x11 && bytes[3] === 0xE0;
                return isOle2;
            }
        } catch (e) { /* if we can't read, don't block */ }
        return false;
    }

    _getFile(id)             { return this.files.find(f => f.id === id); }
    _updateFile(id, changes) { this.files = this.files.map(f => f.id === id ? { ...f, ...changes } : f); }
    _formatSize(bytes) {
        if (bytes < 1024)        return `${bytes} B`;
        if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
    }
    _setStatus(msg, type = 'info') {
        this.statusMessage = msg;
        this.statusType    = type;
        if (type === 'success') setTimeout(() => { this.statusMessage = ''; }, 4000);
    }
}