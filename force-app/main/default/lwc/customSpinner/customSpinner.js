import { api, LightningElement } from 'lwc';

/**
 * Built-in CSS loader catalog (sourced from https://cssloaders.github.io/).
 * Consumers can override this by passing the `loaders` @api property with
 * the same shape: { id, message, loaderCSS }.
 */
const DEFAULT_LOADERS = [
    {
        id: 1,
        message: '📸 Snapping a high-def photo of your content',
        loaderCSS:
            '.loader{position:relative;width:120px;height:55px;background-repeat:no-repeat;background-image:radial-gradient(circle 2.5px,#ff3d00 100%,transparent 0),linear-gradient(#525252 90px,transparent 0),linear-gradient(#ececec 120px,transparent 0),linear-gradient(to right,#eee 10%,#333 10%,#333 90%,#eee 90%);background-size:5px 5px,90px 10px,120px 45px,100px 15px;background-position:110px 15px,center bottom,center bottom,center 0}.loader:before{content:"";width:70px;background-color:#fff;box-shadow:0 0 10px #0003;position:absolute;left:50%;transform:translatex(-50%);bottom:calc(100% - 10px);animation:printerPaper 4s ease-in infinite}.loader:after{content:"";width:70px;height:80px;background-color:#fff;background-image:linear-gradient(to bottom,#FFF 50%,#ff3d00 51%),linear-gradient(to bottom,#bbb 50%,#0000 51%);background-size:60px 20px,60px 10px;background-repeat:no-repeat,repeat-y;background-position:center 55px,center 0;position:absolute;left:50%;transform:translatex(-50%) rotate(180deg);box-shadow:0 10px #fff inset;top:calc(100% - 8px);animation:PrintedPaper 4s ease-in infinite}@keyframes printerPaper{0%,25%{height:50px}75%,100%{height:0}}@keyframes PrintedPaper{0%,30%{height:0;top:calc(100% - 8px)}80%{height:80px;top:calc(100% - 8px);opacity:1}100%{height:80px;top:calc(100% + 10px);opacity:0}}'
    },
    {
        id: 2,
        message: '🏗️ Architecting the PDF structure...',
        loaderCSS:
            '.loader{width:100px;height:46px;position:relative;border-bottom:5px solid #FFF;border-top:5px solid #FFF;box-sizing:border-box}.loader:before,.loader:after{content:"";position:absolute;left:0;top:-20px;width:32px;height:32px;border-radius:50%;background:#FF3D00;border:5px solid #FFF;box-sizing:border-box;animation:slide 1s infinite ease-in-out alternate}.loader:after{top:20px;animation-direction:alternate-reverse}@keyframes slide{0%,20%{transform:translateX(70px)}80%,100%{transform:translateX(-1px)}}'
    },
    {
        id: 3,
        message: '📏 Calculating layout dimensions and font metrics...',
        loaderCSS:
            '.loader{width:48px;height:48px;position:relative;animation:rotate 4s linear infinite}.loader:before,.loader:after{content:"";display:block;border:24px solid;border-color:#fff0 #fff0 #fff #fff;position:absolute;left:0;top:0;animation:mvx 1s infinite ease-in}.loader:before{left:-1px;top:1px;border-color:#FF3D00 #FF3D00 #fff0 #fff0;animation-name:mvrx}@keyframes rotate{100%{transform:rotate(360deg)}}@keyframes mvx{0%,15%{transform:translate(0,0) rotate(0deg)}50%{transform:translate(-50%,50%) rotate(180deg)}100%{transform:translate(0%,0%) rotate(180deg)}}@keyframes mvrx{0%,15%{transform:translate(0,0) rotate(0deg)}50%{transform:translate(50%,-50%) rotate(180deg)}100%{transform:translate(0%,0%) rotate(180deg)}}'
    },
    {
        id: 4,
        message: '🌩️ Harnessing cloud power to build your pixel-perfect PDF...',
        loaderCSS: `.loader{width:175px;height:80px;display:block;margin:auto;background-image:radial-gradient(circle 25px at 25px 25px,#FFF 100%,transparent 0),radial-gradient(circle 50px at 50px 50px,#FFF 100%,transparent 0),radial-gradient(circle 25px at 25px 25px,#FFF 100%,transparent 0),linear-gradient(#FFF 50px,transparent 0);background-size:50px 50px,100px 76px,50px 50px,120px 40px;background-position:0 30px,37px 0,122px 30px,25px 40px;background-repeat:no-repeat;position:relative;box-sizing:border-box}.loader::before{content:'';left:60px;bottom:18px;position:absolute;width:36px;height:36px;border-radius:50%;background-color:#FF3D00;background-image:radial-gradient(circle 8px at 18px 18px,#FFF 100%,transparent 0),radial-gradient(circle 4px at 18px 0,#FFF 100%,transparent 0),radial-gradient(circle 4px at 0 18px,#FFF 100%,transparent 0),radial-gradient(circle 4px at 36px 18px,#FFF 100%,transparent 0),radial-gradient(circle 4px at 18px 36px,#FFF 100%,transparent 0),radial-gradient(circle 4px at 30px 5px,#FFF 100%,transparent 0),radial-gradient(circle 4px at 30px 5px,#FFF 100%,transparent 0),radial-gradient(circle 4px at 30px 30px,#FFF 100%,transparent 0),radial-gradient(circle 4px at 5px 30px,#FFF 100%,transparent 0),radial-gradient(circle 4px at 5px 5px,#FFF 100%,transparent 0);background-repeat:no-repeat;box-sizing:border-box;animation:rotationBack 3s linear infinite}.loader::after{content:'';left:94px;bottom:15px;position:absolute;width:24px;height:24px;border-radius:50%;background-color:#FF3D00;background-image:radial-gradient(circle 5px at 12px 12px,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 12px 0,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 0 12px,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 24px 12px,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 12px 24px,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 20px 3px,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 20px 3px,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 20px 20px,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 3px 20px,#FFF 100%,transparent 0),radial-gradient(circle 2.5px at 3px 3px,#FFF 100%,transparent 0);background-repeat:no-repeat;box-sizing:border-box;animation:rotationBack 4s linear infinite reverse}@keyframes rotationBack{0%{transform:rotate(0deg)}100%{transform:rotate(-360deg)}}`
    },
    {
        id: 5,
        message: '📑 Folding your digital pages into a PDF...',
        loaderCSS: `.loader{width:200px;height:140px;background:#979794;box-sizing:border-box;position:relative;border-radius:8px;perspective:1000px}.loader:before{content:'';position:absolute;left:10px;right:10px;top:10px;bottom:10px;border-radius:8px;background:#f5f5f5 no-repeat;background-size:60px 10px;background-image:linear-gradient(#ddd 100px,transparent 0),linear-gradient(#ddd 100px,transparent 0),linear-gradient(#ddd 100px,transparent 0),linear-gradient(#ddd 100px,transparent 0),linear-gradient(#ddd 100px,transparent 0),linear-gradient(#ddd 100px,transparent 0);background-position:15px 30px,15px 60px,15px 90px,105px 30px,105px 60px,105px 90px;box-shadow:0 0 10px rgb(0 0 0 / .25)}.loader:after{content:'';position:absolute;width:calc(50% - 10px);right:10px;top:10px;bottom:10px;border-radius:8px;background:#fff no-repeat;background-size:60px 10px;background-image:linear-gradient(#ddd 100px,transparent 0),linear-gradient(#ddd 100px,transparent 0),linear-gradient(#ddd 100px,transparent 0);background-position:50% 30px,50% 60px,50% 90px;transform:rotateY(0deg);transform-origin:left center;animation:paging 1s linear infinite}@keyframes paging{to{transform:rotateY(-180deg)}}`
    },
    {
        id: 6,
        message: '🚀 Almost there! Preparing the final export...',
        loaderCSS: `.loader{width:215px;height:215px;display:block;margin:auto;position:relative;background:#FFF;box-sizing:border-box}.loader::after{content:'';width:calc(100% - 30px);height:calc(100% - 15px);top:15px;left:15px;position:absolute;background-image:linear-gradient(90deg,transparent,rgb(255 255 255 / .5) 50%,transparent 100%),linear-gradient(#DDD 100px,transparent 0),linear-gradient(#DDD 16px,transparent 0),linear-gradient(#DDD 50px,transparent 0);background-repeat:no-repeat;background-size:75px 175px,100% 100px,100% 16px,100% 30px;background-position:-185px 0,center 0,center 115px,center 142px;box-sizing:border-box;animation:animloader 1s linear infinite}@keyframes animloader{to{background-position:185px 0,center 0,center 115px,center 142px}}`
    }
];

export default class CustomSpinner extends LightningElement {
    // Public API
    @api mode = 'css'; // 'css' | 'lightning'
    @api cycleIntervalMs = 10000;
    @api maxMessages = 8;
    @api alternativeText = 'Loading';
    @api lightningSize = 'large'; // 'small' | 'medium' | 'large'
    @api lightningVariant = 'brand'; // 'base' | 'brand' | 'inverse'
    /**
     * When true, disables automatic loader cycling. Consumers retain full
     * imperative control via appendMessage / setCssLoader. Default: false
     * (i.e. auto-cycling is ON, preserving the original behavior).
     */
    @api noAutoCycle = false;

    messages = []; // [{ id, icon, text }]

    _messageSeq = 0;
    _intervalId;
    _currentCssLoaderId; // id from cssLoadersArray currently shown
    _lastRenderedCssLoaderId;
    _customLoaderCSS = ''; // raw CSS pushed by consumer (out-of-catalog)
    _lastRenderedCustomCSS = '';
    _cycleIndex = 0;
    _seenLoaderIds = new Set();
    _isExhausted = false;
    _userLoaders;
    _initialMessages;
    _isMounted = false;
    /**
     * Flag: true once the consumer has supplied their own messages (via
     * `initialMessages`, `setMessages`, or `appendMessage`). When true, the
     * auto-cycler swaps the spinner animation only and stops injecting the
     * built-in loader.message strings, so the visible list contains *only*
     * the consumer's messages.
     */
    _userProvidedMessages = false;
    /**
     * Queue of parsed user messages waiting to be revealed by the cycler.
     * setMessages() seeds this with all-but-the-first items so the cycler
     * can pop one per tick — producing the same progressive reveal effect
     * as the built-in loader catalog.
     */
    _pendingUserMessages = [];

    /**
     * Consumer-supplied loader catalog. Each item:
     *   { id?: string|number, message?: string, loaderCSS: string }
     * When set, replaces the built-in catalog and restarts the cycle.
     * Pass `undefined`/empty array to revert to the built-in catalog.
     */
    @api
    get loaders() {
        return this._userLoaders;
    }
    set loaders(value) {
        if (Array.isArray(value) && value.length) {
            this._userLoaders = value.map((l, idx) => ({
                id: l && (l.id ?? l.Id) != null ? l.id ?? l.Id : `u-${idx + 1}`,
                message: (l && l.message) || '',
                loaderCSS: (l && l.loaderCSS) || ''
            }));
        } else {
            this._userLoaders = undefined;
        }
        if (this._isMounted) {
            this._restartCycle();
        }
    }

    /**
     * Declarative initial messages. Each item may be a string ("📸 Hello")
     * or an object { icon?, text?, message? }.
     */
    @api
    get initialMessages() {
        return this._initialMessages;
    }
    set initialMessages(value) {
        this._initialMessages = value;
        if (Array.isArray(value) && value.length) {
            this.setMessages(value);
        }
    }

    get hasUserProvidedMessages() {
        return this._userProvidedMessages;
    }

    connectedCallback() {
        this._isMounted = true;

        // If the consumer pre-seeded messages via initialMessages, keep them
        // and only kick off auto-cycling if requested.
        const hasSeededMessages = this.messages.length > 0;

        if (this.autoCycle && !hasSeededMessages) {
            this.resetCycle();
            this.showFirstMessage();
            this._startInterval();
        } else if (this.autoCycle && hasSeededMessages) {
            // Keep seeded messages; pick the first loader so the spinner has
            // visuals, advance the cycle past it so the next tick swaps, and
            // only start the timer if there's something left to reveal
            // (queue) — otherwise the spinner stays static after one message.
            this._seenLoaderIds = new Set();
            this._isExhausted = false;
            const first = this.cssLoadersArray[0];
            if (first && !this._customLoaderCSS) {
                this._currentCssLoaderId = first.id;
                this._seenLoaderIds.add(first.id);
                this._cycleIndex = 1;
            } else {
                this._cycleIndex = 0;
            }
            if (this._pendingUserMessages.length) {
                this._startInterval();
            }
        } else if (!this._currentCssLoaderId && !this._customLoaderCSS) {
            // autoCycle=false: show the first catalog loader visually so we
            // never render an empty spinner pane.
            const first = this.cssLoadersArray[0];
            if (first) this._currentCssLoaderId = first.id;
        }
    }

    disconnectedCallback() {
        this._isMounted = false;
        this.stopSequence();
    }

    renderedCallback() {
        if (this.mode !== 'css') return;

        const container = this.template.querySelector('.loader-container');
        if (!container) return;

        // Consumer-supplied raw CSS takes precedence over catalog ids.
        if (this._customLoaderCSS) {
            if (this._lastRenderedCustomCSS === this._customLoaderCSS) return;
            container.innerHTML = `<style>${this._customLoaderCSS}</style><span class="loader" aria-hidden="true"></span>`;
            this._lastRenderedCustomCSS = this._customLoaderCSS;
            this._lastRenderedCssLoaderId = undefined;
            return;
        }

        if (!this._currentCssLoaderId) return;
        if (this._lastRenderedCssLoaderId === this._currentCssLoaderId) return;

        const loader = this.cssLoadersArray.find((l) => l.id === this._currentCssLoaderId);
        if (!loader) return;

        container.innerHTML = `<style>${loader.loaderCSS}</style><span class="loader" aria-hidden="true"></span>`;
        this._lastRenderedCssLoaderId = this._currentCssLoaderId;
        this._lastRenderedCustomCSS = '';
    }

    // ---------- Public imperative methods ----------

    /**
     * Append a single message row. Accepts:
     *   - string: "📸 Some text" (back-compat — parsed into icon + text)
     *   - object: { icon?, text?, message?, loaderCSS? }
     *     If loaderCSS is supplied, the spinner animation is swapped to it.
     */
    @api appendMessage(input) {
        if (!input) return;

        const { icon, text, loaderCSS } = this._parseInputToIconText(input);

        if (text || icon) {
            this._userProvidedMessages = true;
            this.messages = [
                ...this.messages,
                this._buildMessageRow(icon, text)
            ].slice(-1 * this.maxMessages);
        }

        if (loaderCSS) {
            this._applyCustomCss(loaderCSS);
        }
    }

    /**
     * Replace the entire visible message list. Items may be strings
     * ("📸 Hello") or objects { icon?, text?, message?, loaderCSS? }.
     *
     * By default the messages are revealed progressively — the first one is
     * shown immediately and the rest are popped by the cycler one per
     * `cycleIntervalMs` tick, alongside a spinner animation swap. Pass
     * `{ revealAll: true }` to dump them in at once (legacy behavior).
     *
     * Once called with a non-empty array the built-in catalog messages no
     * longer leak into the visible list — only your messages show.
     */
    @api setMessages(items, { revealAll = false } = {}) {
        this.messages = [];
        this._pendingUserMessages = [];
        this._userProvidedMessages = false;

        if (!Array.isArray(items) || !items.length) return;

        const parsed = items
            .map((item) => this._parseInputToIconText(item))
            .filter((p) => p.text || p.icon);
        if (!parsed.length) return;

        this._userProvidedMessages = true;

        if (revealAll) {
            this.messages = parsed
                .map(({ icon, text }) => this._buildMessageRow(icon, text))
                .slice(-1 * this.maxMessages);
            // When dumping everything at once, the spinner should reflect
            // the most-recent item's animation.
            const lastWithCss = [...parsed].reverse().find((p) => p.loaderCSS);
            if (lastWithCss) this._applyCustomCss(lastWithCss.loaderCSS);
        } else {
            const [first, ...rest] = parsed;
            this.messages = [this._buildMessageRow(first.icon, first.text)];
            // Keep each pending item paired with its own loaderCSS so the
            // cycler can swap text + animation atomically on each tick.
            this._pendingUserMessages = rest;
            // The first item's animation (if any) goes up immediately —
            // the cycler will apply each subsequent item's CSS as it's
            // popped, keeping message N visually paired with animation N.
            if (first.loaderCSS) {
                this._applyCustomCss(first.loaderCSS);
            }
        }

        // If we're already mounted, re-prime the cycler so the visual swaps
        // start from a fresh state alongside the progressive reveal.
        if (this._isMounted) this._primeUserMessageCycle();
    }

    @api clearMessages() {
        this.messages = [];
        this._pendingUserMessages = [];
        this._userProvidedMessages = false;
    }

    /**
     * Switch the active spinner animation. Accepts:
     *   - number/string id from cssLoadersArray (existing behavior)
     *   - object { id?, loaderCSS?, message? } for ad-hoc raw CSS
     * Pass `{ appendMessage: true }` in opts to also push the loader's
     * message into the visible list.
     */
    @api setCssLoader(input, { appendMessage = false } = {}) {
        let target;
        const loaders = this.cssLoadersArray;

        if (input && typeof input === 'object') {
            if (input.loaderCSS) {
                this._applyCustomCss(input.loaderCSS);
                if (appendMessage && input.message) {
                    this.appendMessage(input.message);
                }
                return;
            }
            target = loaders.find(
                (l) => l.id === input.id || l.id === Number(input.id)
            );
        } else {
            target = loaders.find((l) => l.id === input || l.id === Number(input));
        }

        if (!target) return;

        this._currentCssLoaderId = target.id;
        this._customLoaderCSS = '';
        this._lastRenderedCustomCSS = '';

        if (appendMessage && target.message) {
            this.appendLoaderMessage(target);
        }
    }


    @api cycleOnce() {
        this.cycleNext();
    }

    @api reset() {
        this._customLoaderCSS = '';
        this._lastRenderedCustomCSS = '';
        this.resetCycle();
    }

    // ---------- Internal getters ----------

    get cssLoadersArray() {
        return this._userLoaders && this._userLoaders.length
            ? this._userLoaders
            : DEFAULT_LOADERS;
    }

    get isCssMode() {
        return this.mode === 'css';
    }

    get isLightningMode() {
        return this.mode === 'lightning';
    }

    get hasMessages() {
        return Array.isArray(this.messages) && this.messages.length > 0;
    }

    get autoCycle() {
        return !this.noAutoCycle;
    }

    // ---------- Internal cycle helpers ----------

    cycleNext() {
        if (this._isExhausted) return;
        const loaders = this.cssLoadersArray;
        if (!loaders.length) return;

        if (this._userProvidedMessages) {
            this._cycleUserMessages();
        } else {
            this._cycleDefaultMessages();
        }
    }

    _cycleDefaultMessages() {
        const loaders = this.cssLoadersArray;
        for (let attempts = 0; attempts < loaders.length; attempts++) {
            const idx = (this._cycleIndex + attempts) % loaders.length;
            const loader = loaders[idx];
            if (!loader) continue;
            if (this._seenLoaderIds.has(loader.id)) continue;

            this._cycleIndex = (idx + 1) % loaders.length;
            this._currentCssLoaderId = loader.id;
            this._customLoaderCSS = '';
            this._seenLoaderIds.add(loader.id);
            this.appendLoaderMessage(loader, { markSeen: false });

            if (this._seenLoaderIds.size >= loaders.length) {
                this._isExhausted = true;
                this.stopSequence();
            }
            return;
        }
    }

    _cycleUserMessages() {
        // Reveal the next queued user message AND swap the spinner animation
        // in the same tick. If the item carried its own loaderCSS, apply it;
        // otherwise advance the catalog cycler so the visual still changes.
        if (this._pendingUserMessages.length) {
            const next = this._pendingUserMessages.shift();
            this.messages = [
                ...this.messages,
                this._buildMessageRow(next.icon, next.text)
            ].slice(-1 * this.maxMessages);

            if (next.loaderCSS) {
                this._applyCustomCss(next.loaderCSS);
            } else {
                // Drop the previous custom CSS (if any) and rotate to the
                // next catalog loader so the spinner still moves.
                this._customLoaderCSS = '';
                this._lastRenderedCustomCSS = '';
                this._swapVisualToNextLoader();
            }
        }

        // Stop the cycler once every queued message has been revealed —
        // the spinner stays on its current animation.
        if (!this._pendingUserMessages.length) {
            this._isExhausted = true;
            this.stopSequence();
        }
    }

    _swapVisualToNextLoader() {
        const loaders = this.cssLoadersArray;
        if (!loaders.length || this._customLoaderCSS) return;

        for (let attempts = 0; attempts < loaders.length; attempts++) {
            const idx = (this._cycleIndex + attempts) % loaders.length;
            const loader = loaders[idx];
            if (!loader) continue;
            if (this._seenLoaderIds.has(loader.id)) continue;

            this._cycleIndex = (idx + 1) % loaders.length;
            this._currentCssLoaderId = loader.id;
            this._seenLoaderIds.add(loader.id);
            return;
        }

        // All loaders already shown — wrap around so visuals keep cycling.
        this._seenLoaderIds = new Set();
        const first = loaders[0];
        if (first) {
            this._currentCssLoaderId = first.id;
            this._seenLoaderIds.add(first.id);
            this._cycleIndex = 1;
        }
    }

    _primeUserMessageCycle() {
        this.stopSequence();
        this._seenLoaderIds = new Set();
        this._isExhausted = false;
        const first = this.cssLoadersArray[0];
        if (first && !this._customLoaderCSS) {
            this._currentCssLoaderId = first.id;
            this._seenLoaderIds.add(first.id);
            this._cycleIndex = 1;
        } else {
            this._cycleIndex = 0;
        }
        if (this.autoCycle && this._pendingUserMessages.length) {
            this._startInterval();
        }
    }

    resetCycle() {
        this.stopSequence();
        this._cycleIndex = 0;
        this._seenLoaderIds = new Set();
        this._isExhausted = false;
        this.clearMessages();
    }

    showFirstMessage() {
        const loaders = this.cssLoadersArray;
        const first = loaders[0];
        if (!first) return;
        this._cycleIndex = 1;
        this._currentCssLoaderId = first.id;
        this.appendLoaderMessage(first);
    }

    stopSequence() {
        if (this._intervalId) {
            clearInterval(this._intervalId);
            this._intervalId = undefined;
        }
    }

    _startInterval() {
        this.stopSequence();
        if (!this.autoCycle) return;
        const delay = Number(this.cycleIntervalMs) || 10000;
        this._intervalId = setInterval(() => this.cycleNext(), delay);
    }

    _restartCycle() {
        this.resetCycle();
        if (this.autoCycle) {
            this.showFirstMessage();
            this._startInterval();
        }
    }

    _applyCustomCss(css) {
        this._customLoaderCSS = css || '';
        this._currentCssLoaderId = undefined;
        this._lastRenderedCssLoaderId = undefined;
        this._lastRenderedCustomCSS = '';
    }

    appendLoaderMessage(loader, { markSeen = true } = {}) {
        if (!loader || loader.id == null) return;
        if (markSeen) {
            if (this._seenLoaderIds.has(loader.id)) return; // uniqueness per run
            this._seenLoaderIds.add(loader.id);
        }

        const parsed = this.parseIconAndText(String(loader.message || ''));
        if (!parsed.text && !parsed.icon) return;

        this.messages = [
            ...this.messages,
            this._buildMessageRow(parsed.icon, parsed.text)
        ].slice(-1 * this.maxMessages);
    }

    _buildMessageRow(icon, text) {
        return {
            id: String(++this._messageSeq),
            icon: icon || '',
            text: text || '',
            rowClass: icon ? 'messageRow' : 'messageRow messageRow--noIcon'
        };
    }

    _parseInputToIconText(input) {
        if (!input) return { icon: '', text: '', loaderCSS: '' };
        if (typeof input === 'string') {
            const p = this.parseIconAndText(input);
            return { icon: p.icon, text: p.text, loaderCSS: '' };
        }
        if (typeof input === 'object') {
            const raw = input.message != null ? input.message : input.text;
            const p = this.parseIconAndText(String(raw || ''));
            return {
                icon: input.icon != null ? String(input.icon) : p.icon,
                text: input.text != null ? String(input.text) : p.text,
                loaderCSS: input.loaderCSS || ''
            };
        }
        return { icon: '', text: '', loaderCSS: '' };
    }

    parseIconAndText(message) {
        // Expected format: "📸 Some text..." — but the first token is only
        // treated as an icon if it contains NO Latin letters or digits (i.e.
        // it's purely emoji/symbol). Plain words like "Loading" stay in text.
        const trimmed = (message || '').trim();
        if (!trimmed) return { icon: '', text: '' };
        const parts = trimmed.split(/\s+/);
        if (parts.length === 1) return { icon: '', text: trimmed };
        const firstToken = parts[0];
        const looksLikeEmoji =
            firstToken.length <= 8 && !/[\p{L}\p{N}]/u.test(firstToken);
        if (!looksLikeEmoji) return { icon: '', text: trimmed };
        const icon = firstToken;
        const text = parts.slice(1).join(' ').trim();
        return { icon, text: text || trimmed };
    }
}