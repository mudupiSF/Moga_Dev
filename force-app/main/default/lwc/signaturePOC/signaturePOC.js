import { LightningElement, track, api, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import signaturePad from '@salesforce/resourceUrl/signaturePad';
import USER_ID from '@salesforce/user/Id';
import USER_EMAIL_FIELD from '@salesforce/schema/User.Email';

export default class SignaturePOC extends LightningElement {
    fullName = 'Tom Jones';
    activeTab = 'style';
    selectedStyle = 'style1';
    @api modalOpen = false;
    @api signatureImageUrl = null;
    @track signaturePad = null;
    signaturePadLibraryLoaded = false;
    signaturePadInitInProgress = false;
    fontMap = {
        style1: '"Brush Script MT", "Segoe Script", cursive',
        style2: '"Lucida Handwriting", "Apple Chancery", cursive',
        style3: '"Snell Roundhand", "Bradley Hand", cursive'
      };

    // Signer audit metadata
    userId = USER_ID;
    userEmail = null;
    @track _geoCoords = null;
    @track _localIpAddress = null;

    @wire(getRecord, { recordId: '$userId', fields: [USER_EMAIL_FIELD] })
    wiredUser({ data }) {
        if (data) {
            this.userEmail = getFieldValue(data, USER_EMAIL_FIELD);
        }
    }

    connectedCallback() {
        this.fetchBrowserGeolocation();
        this.fetchLocalIpAddress();
    }

    /**
     * Discover the local network IP via WebRTC ICE candidate gathering.
     * No external STUN server is configured, so only host candidates
     * (private LAN IPs) are exposed - this stays inside browser data only.
     * Some browsers obfuscate the host with mDNS (`*.local`); in that case
     * we keep the value as-is so the audit trail still records something.
     */
    fetchLocalIpAddress() {
        if (typeof window === 'undefined' || typeof window.RTCPeerConnection !== 'function') {
            return;
        }
        let pc;
        try {
            pc = new window.RTCPeerConnection({ iceServers: [] });
        } catch (e) {
            return;
        }

        const ipRegex = /([0-9]{1,3}(?:\.[0-9]{1,3}){3}|[a-f0-9]{1,4}(?::[a-f0-9]{1,4}){2,}|[\w-]+\.local)/i;
        const seen = new Set();

        const finalize = () => {
            try { pc.close(); } catch (e) { /* ignore */ }
        };

        pc.onicecandidate = (event) => {
            if (!event || !event.candidate) {
                finalize();
                return;
            }
            const match = ipRegex.exec(event.candidate.candidate || '');
            if (match && match[1] && !seen.has(match[1])) {
                seen.add(match[1]);
                // Prefer the first non-mDNS IPv4-style address; fall back to whatever we got.
                if (!this._localIpAddress || (this._localIpAddress.endsWith('.local') && !match[1].endsWith('.local'))) {
                    this._localIpAddress = match[1];
                }
            }
        };

        try {
            pc.createDataChannel('');
            pc.createOffer()
                .then((offer) => pc.setLocalDescription(offer))
                .catch(() => finalize());
        } catch (e) {
            finalize();
        }

        // Safety: stop gathering after a short window even if no event fires.
        setTimeout(finalize, 1500);
    }

    fetchBrowserGeolocation() {
        if (!('geolocation' in navigator)) return;
        try {
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    this._geoCoords = {
                        latitude: position.coords.latitude,
                        longitude: position.coords.longitude,
                        accuracy: position.coords.accuracy
                    };
                },
                () => {
                    this._geoCoords = null;
                },
                { enableHighAccuracy: false, timeout: 5000, maximumAge: 60000 }
            );
        } catch (error) {
            this._geoCoords = null;
        }
    }

    detectDeviceType() {
        const ua = (navigator.userAgent || '').toLowerCase();
        if (/(tablet|ipad|playbook|silk)|(android(?!.*mobi))/i.test(ua)) {
            return 'Tablet';
        }
        if (/mobile|iphone|ipod|android|blackberry|opera mini|iemobile|wpdesktop/i.test(ua)) {
            return 'Mobile';
        }
        return 'Desktop';
    }

    detectPlatformOs() {
        const uaData = navigator.userAgentData;
        if (uaData && uaData.platform) {
            const p = uaData.platform.toLowerCase();
            if (p.includes('mac')) return 'macOS';
            if (p.includes('win')) return 'Windows';
            if (p.includes('android')) return 'Android';
            if (p.includes('ios')) return 'iOS';
            if (p.includes('linux')) return 'Linux';
        }
        const ua = (navigator.userAgent || '').toLowerCase();
        if (/iphone|ipad|ipod/.test(ua)) return 'iOS';
        if (/android/.test(ua)) return 'Android';
        if (/mac os x|macintosh/.test(ua)) return 'macOS';
        if (/windows/.test(ua)) return 'Windows';
        if (/linux/.test(ua)) return 'Linux';
        return 'Unknown';
    }

    /**
     * Derive an originating city from the browser's IANA timezone
     * (e.g. "America/Los_Angeles" -> "Los Angeles"). Best-effort only;
     * not all timezones encode a city.
     */
    detectOriginatingCity() {
        try {
            const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
            if (!tz || !tz.includes('/')) return null;
            const tail = tz.split('/').pop();
            return tail ? tail.replace(/_/g, ' ') : null;
        } catch (e) {
            return null;
        }
    }

    /**
     * Derive an originating country from the browser locale
     * (e.g. "en-US" -> "US"). Falls back to null when no region is present.
     */
    detectOriginatingCountry() {
        try {
            const locale = navigator.language || (navigator.languages && navigator.languages[0]);
            if (!locale) return null;
            const parts = locale.split('-');
            if (parts.length < 2) return null;
            const region = parts[parts.length - 1].toUpperCase();
            // Try to map region code (e.g. "US") to display name when supported.
            if (typeof Intl !== 'undefined' && typeof Intl.DisplayNames === 'function') {
                try {
                    const dn = new Intl.DisplayNames([locale], { type: 'region' });
                    return dn.of(region) || region;
                } catch (e) {
                    return region;
                }
            }
            return region;
        } catch (e) {
            return null;
        }
    }

    buildSignerMetadata() {
        return {
            userId: this.userId || null,
            userEmail: this.userEmail || null,
            // Public IP isn't exposed by browsers without an external service,
            // so this is the local/private IP discovered via WebRTC instead.
            sourceIpAddress: this._localIpAddress || null,
            geoLocationCoordinates: this._geoCoords,
            originatingCity: this.detectOriginatingCity(),
            originatingCountry: this.detectOriginatingCountry(),
            deviceType: this.detectDeviceType(),
            platformOs: this.detectPlatformOs(),
            userAgent: navigator.userAgent || null,
            timezone: (() => {
                try { return Intl.DateTimeFormat().resolvedOptions().timeZone || null; }
                catch (e) { return null; }
            })(),
            locale: navigator.language || null,
            timestamp: new Date().toISOString()
        };
    }

    get isStyleTab() {
        return this.activeTab === 'style';
    }

    get isDrawTab() {
        return this.activeTab === 'draw';
    }

    get styleTabClass() {
        return `tab-link${this.isStyleTab ? ' tab-link_active' : ''}`;
    }

    get drawTabClass() {
        return `tab-link${this.isDrawTab ? ' tab-link_active' : ''}`;
    }


    renderedCallback() {
        if (this.activeTab === 'draw' && !this.signaturePad) {
            this.ensureSignaturePadInitialized();
        }
    }

    async ensureSignaturePadInitialized() {
        if (this.signaturePad || this.signaturePadInitInProgress) return;
        this.signaturePadInitInProgress = true;
        try {
            if (!this.signaturePadLibraryLoaded) {
                await loadScript(this, signaturePad);
                this.signaturePadLibraryLoaded = true;
            }
            await Promise.resolve();
            const canvas = this.template.querySelector('[data-id="drawCanvas"]');
            if (canvas && window.SignaturePad) {
                this.signaturePad = new window.SignaturePad(canvas);
            }
        } catch (error) {
            // eslint-disable-next-line no-console
            console.log('Error loading scripts ' + error);
        } finally {
            this.signaturePadInitInProgress = false;
        }
    }


    handleNameChange(event) {
        this.fullName = event.target.value;
    }

    handleClear() {
        if (this.signaturePad) {
            this.signaturePad.clear();
        }
    }


    handleStyleChange(event) {
        this.selectedStyle = event.currentTarget.dataset.style;
    }

    handleStyleTabActive() {
        this.activeTab = 'style';
    }

    async handleDrawTabActive() {
        this.activeTab = 'draw';
        await this.ensureSignaturePadInitialized();
    }


    handleAcceptAndSign() {
        if (this.activeTab === 'style') {
            // Convert typed signature text to image
            const canvas = this.template.querySelector('[data-id="typedCanvas"]');
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            const name = (this.fullName || '').trim() || 'Signature';
            const fontFamily = this.fontMap[this.selectedStyle] || this.fontMap.style1;

            ctx.clearRect(0, 0, canvas.width, canvas.height);

            ctx.fillStyle = '#0b0f14';
            ctx.textBaseline = 'middle';
            ctx.font = `56px ${fontFamily}`;
            ctx.fillText(name, 20, canvas.height / 2);

            this.signatureImage = this.getTrimmedSignatureDataUrl(canvas);
        } else {
            // Convert drawn signature canvas to image
            if (!this.signaturePad || this.signaturePad.isEmpty()) {
                return;
            }
            const drawCanvas = this.template.querySelector('[data-id="drawCanvas"]');
            if (!drawCanvas) return;
            this.signatureImage = this.getTrimmedSignatureDataUrl(drawCanvas);
        }
        if (!this.signatureImage) return;
        // dispatch event to parent with signature image AND signer audit metadata
        this.dispatchEvent(new CustomEvent('signatureimage', {
            detail: {
                image: this.signatureImage,
                metadata: this.buildSignerMetadata()
            }
        }));
        // Clear local capture state so the component is ready for the next signature.
        // Visibility (modalOpen) is controlled by the parent.
        this.handleClear();
        this.signatureImage = null;
    }

    @api
    resetForNext() {
        this.handleClear();
        this.signatureImage = null;
        this.activeTab = 'style';
    }

    getTrimmedSignatureDataUrl(sourceCanvas) {
        if (!sourceCanvas) return null;
        const sourceCtx = sourceCanvas.getContext('2d');
        if (!sourceCtx) return null;

        const { width, height } = sourceCanvas;
        const imageData = sourceCtx.getImageData(0, 0, width, height);
        const data = imageData.data;

        let minX = width;
        let minY = height;
        let maxX = -1;
        let maxY = -1;

        // Find non-transparent pixel bounds (alpha > 0).
        for (let y = 0; y < height; y++) {
            for (let x = 0; x < width; x++) {
                const alpha = data[(y * width + x) * 4 + 3];
                if (alpha > 0) {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }

        if (maxX < minX || maxY < minY) {
            return null;
        }

        const padding = 8;
        const trimX = Math.max(0, minX - padding);
        const trimY = Math.max(0, minY - padding);
        const trimRight = Math.min(width - 1, maxX + padding);
        const trimBottom = Math.min(height - 1, maxY + padding);
        const trimWidth = trimRight - trimX + 1;
        const trimHeight = trimBottom - trimY + 1;

        const outputCanvas = document.createElement('canvas');
        outputCanvas.width = trimWidth;
        outputCanvas.height = trimHeight;
        const outputCtx = outputCanvas.getContext('2d');
        if (!outputCtx) return null;

        outputCtx.clearRect(0, 0, trimWidth, trimHeight);
        outputCtx.drawImage(
            sourceCanvas,
            trimX,
            trimY,
            trimWidth,
            trimHeight,
            0,
            0,
            trimWidth,
            trimHeight
        );

        return outputCanvas.toDataURL('image/png');
    }


    closeModal(){
        this.modalOpen = false;
        
        this.handleClear()
    }

}