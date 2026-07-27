/* eslint-disable @lwc/lwc/no-async-operation */
/* eslint-disable @lwc/lwc/no-inner-html */
/* eslint-disable no-undef */
import { LightningElement, api, track } from 'lwc';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import PAGED from '@salesforce/resourceUrl/PAGED';
import DOMPURIFY from '@salesforce/resourceUrl/DOMPURIFY';
import jsforcescript from '@salesforce/resourceUrl/jsforcescript';
import PAKO_JS from '@salesforce/resourceUrl/pako';
import JZIP from '@salesforce/resourceUrl/JZIP';
import getVFPageUrl from '@salesforce/apex/PDFforceController.getVFPageUrl';
import getTemplate from '@salesforce/apex/PDFforceController.getTemplate';
import loadTemplateJSON from '@salesforce/apex/PDFforceController.loadTemplateJSON';
import findRendererTemplateContentId from '@salesforce/apex/PDFforceController.findRendererTemplateContentId';
import deleteRendererTemplateDocument from '@salesforce/apex/PDFforceController.deleteRendererTemplateDocument';
import createCDLRecords from '@salesforce/apex/PDFforceController.createCDLRecords';
import createContentVersionFromBase64 from '@salesforce/apex/PDFforceController.createContentVersionFromBase64';
import attachGeneratedPdf from '@salesforce/apex/PDFforceController.attachGeneratedPdf';
import getUserSessionId from '@salesforce/apex/PDFforceController.getUserSessionId';
import HANDLEBARSJS from '@salesforce/resourceUrl/HANDLEBARSJS';
import getContentVersionId from '@salesforce/apex/PDFforceController.getContentVersionId';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadTemplateFromSalesforce, robustHandlebarsHealer, readUploadedFileAsDataUrl } from 'c/pDFforceUtils';

// Trim Word's large inline side padding (~1in) without going edge-to-edge.
const PDF_PAGE_SIDE_MARGIN = '10mm';

const PDF_EXPORT_LAYOUT_STYLES = `
  .docx-wrapper {
    padding-left: 0 !important;
    padding-right: 0 !important;
  }
  section.docx:not([data-pdf-force-repeated-section]) {
    padding-left: ${PDF_PAGE_SIDE_MARGIN} !important;
    padding-right: ${PDF_PAGE_SIDE_MARGIN} !important;
    margin-left: 0 !important;
    margin-right: 0 !important;
    width: 100% !important;
    max-width: 100% !important;
    box-sizing: border-box !important;
  }
  section.docx:not([data-pdf-force-repeated-section]) > article {
    padding-left: 0 !important;
    padding-right: 0 !important;
    margin-left: 0 !important;
    margin-right: 0 !important;
    width: 100% !important;
    max-width: 100% !important;
    box-sizing: border-box !important;
  }
`;

export default class PDFforceRenderer extends LightningElement {
  static renderMode = 'light';
  _uiContainerObserver;
  _uiContainerGuardPollId;
  _uiContainerManagerState = [];
  @track vfPageUrl;
  @track loading = true;
  @track userMessage = null;
  // When true (CustomerForm VF / Lightning Out), show inline banner instead of toast.
  @api callingFromVf = false;
  @api formName;
  @api customSpinner = false;
  @api showPreview = false;
  @api hideSignButton = false;
  @api autoSave = false;
  @api autoSaveToCurrentRecord = false;
  @api recordId;
  // Optional target record for the generated PDF on Submit. When unset,
  // Submit falls back to attaching the PDF onto `recordId` itself.
  @api submitRecordId;
  @api fileName = 'Application Form';

  @api templateId = '';
  @api inputJSON = {};
  @api pagedViewer = false;
  @api pagedViewerContent = null;
  // Where to render the "Page X of Y" footer in each page's bottom margin band.
  // Allowed values: 'left' | 'center' | 'right' | 'none'. Defaults to 'center'.
  @api pageNumberPosition = 'center';


  get showRenderer() {
    return (!this.templateId && !this.recordId && !this.inputJSON) ? false : true;
  }


  get spinnerType() {
    return this.customSpinner ? 'css' : 'lightning';
  }

  // Normalized + validated page-number placement used by displayPDF().
  get _pageNumberPosition() {
    const allowed = ['left', 'center', 'right', 'none'];
    const value = String(this.pageNumberPosition || 'center').toLowerCase();
    return allowed.includes(value) ? value : 'center';
  }

  connectedCallback() {
    let origin = window.location.origin;
    let isSite = window.location.pathname.split('/').length >= 2 && window.location.pathname.split('/')[2] == 's';
    let lexOrigin;
    if (isSite) {
      lexOrigin = origin;
    } else {
      let sandBoxString = origin.includes("sandbox") ? ".sandbox" : "";
      lexOrigin = origin.split('.')[0] + '--c' + sandBoxString + ".vf.force.com"
    }
    this.vfRoot = lexOrigin;
    if (!this.pagedViewer) {
      window.addEventListener("message", this.handleVFMessage.bind(this));
    }

    // Scripts (Handlebars, paged.js, jsforce, DOMPurify, pako, JSZip)
    // MUST be loaded before any template-render path runs.
    // displayPDF() calls Handlebars.compile(...) and the decompress
    // helpers call window.pako / JSZip - if we kick off
    // _initLoadFromSavedOrTemplate() in parallel with Promise.all(...)
    // the Apex round-trips can finish first (especially when static
    // resources aren't cached yet) and Handlebars.compile() throws
    // because `Handlebars` is still undefined. The throw is swallowed
    // by displayPDF's try/catch, the merge fields never get
    // substituted, and the user sees raw {{...}} placeholders (or an
    // empty preview).
    //
    // The init decision (load saved renderer state vs. load fresh
    // template) is itself async (it has to await
    // findRendererTemplateContentId before branching), so we wrap it
    // in an async helper and fire-and-forget the outer chain --
    // connectedCallback can't be async (LWC doesn't await it).
    Promise.all([
      loadScript(this, PAGED),
      loadScript(this, HANDLEBARSJS),
      loadScript(this, jsforcescript),
      loadScript(this, DOMPURIFY),
      // pako stays loaded for legacy .json.gz templates saved before
      // the JSZip cutover. JZIP is the current default and must load
      // because handleDecompress routes ZIP-magic payloads to it.
      loadScript(this, PAKO_JS),
      loadScript(this, JZIP),
    ]).then(async () => {
      console.log('PDFforceRenderer loaded');
      if (!this.pagedViewer) {
        getVFPageUrl({ pageName: 'SessionIdProvider' }).then(url => {
          this.vfPageUrl = url;
        }).catch(error => {
          console.error('Error getting VF page URL:', error);
        });

        // Now that Handlebars / pako / JSZip are all globals, it is
        // safe to load + render the template.
        this._initLoadFromSavedOrTemplate();
      } else {
        console.log('coming to pagedViewer', `${this.pagedViewerContent}`);
        setTimeout(() => {
          this.displayPDF(`${this.pagedViewerContent}`);
          this.loading = true;
        }, 3000);
      }

    }).catch((error) => {
      console.log('Error loading PDFforceRenderer', error);
    });
  }

  disconnectedCallback() {
    this.stopUiContainerManagerGuard();
  }

  get userMessageClass() {
    const variant = this.userMessage?.variant || 'info';
    return `pdf-user-message pdf-user-message--${variant}`;
  }

  _showToastMessage(title, message, variant = 'info') {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  _showVfPageMessage(title, message, variant = 'info') {

    this.userMessage = { title, message, variant };
  }

  clearUserMessage() {
    this.userMessage = null;
  }

  _notifyUser(title, message, variant = 'info') {
    if (this.callingFromVf) {
      this._showVfPageMessage(title, message, variant);
    } else {
      this._showToastMessage(title, message, variant);
    }
  }


  handleFormSubmitted() {
    this.dispatchEvent(new CustomEvent('formsubmitted', {detail: {formName: this.formName}}, {
      bubbles: true,
      composed: true
    }));
  }

  //Load the template
  // Pass the input JSON
  //render paged view from the template



  async handleVFMessage(event) {
    console.log('[PDFforceRenderer] Message received', JSON.stringify(event.data));
    if (event.data && event.data.type === 'PDF_GENERATED') {
      const pdfData = event.data.pdf;
      const fileName = event.data.fileName;

      // Submit path: attach the generated PDF to submitRecordId (falls
      // back to recordId) and leave the VF iframe alone so additional
      // submits work without a re-init.
      if (this._pendingPdfAttachment) {
        this._pendingPdfAttachment = false;
        this._attachGeneratedPdfToRecord(pdfData, fileName).finally(() => {
          this.loading = false;
        });
        return;
      }

      if (this.showPreview) {
        this.loading = false;
        this.displayPDF(pdfData);
      } else {
        this.loading = false;
      }
    }

    if (event.data && event.data.type === 'PDF_ERROR') {
      this._pendingPdfAttachment = false;
      this.loading = false;
      this._notifyUser(
        'PDF generation failed',
        event.data.error || 'Unknown error',
        'error'
      );
    }

    if (event.data && event.data.type === 'PDFSave') {
      if (event.data.success) {
        this._notifyUser('Success', event.data.message, 'success');
      } else {
        this._notifyUser('Error', event.data.message, 'error');
      }
    }

  }

  @track signatureFields = [];
  // ContentDocumentId of the renderer's saved payload for the current
  // recordId+templateId pair. Populated either on init (when a saved
  // doc already exists) or right after the first successful save, so
  // subsequent saves create a NEW VERSION on the same ContentDocument
  // instead of piling up duplicate Files per record.
  _savedRendererContentDocumentId = null;
  // Set when we load a saved payload so the displayPDF -> paged.js
  // completion handler knows it should re-stamp completed signatures
  // from signatureFields onto the freshly-rendered pages.
  _restampSignaturesAfterRender = false;

  /**
   * Decides between resuming from a previously-saved renderer payload
   * vs. starting fresh from the template, and dispatches accordingly.
   * Called once from connectedCallback. Sequenced because the saved-
   * state check (findRendererTemplateContentId) is async -- the old
   * fire-and-forget version raced the synchronous branch decision
   * and effectively disabled saved-state resume.
   *
   * No-throw by design: any lookup failure logs and falls through to
   * the template path, so a transient Apex error never wedges init.
   */
  async _initLoadFromSavedOrTemplate() {
    let savedContentDocumentId = null;
    if (this.recordId && this.templateId) {
      try {
        savedContentDocumentId = await findRendererTemplateContentId({
          recordId: this.recordId,
          templateId: this.templateId
        });
      } catch (error) {
        console.error('Error getting savedContentDocumentId', error);
      }
    }

    if (savedContentDocumentId) {
      this._savedRendererContentDocumentId = savedContentDocumentId;
      this._restampSignaturesAfterRender = true;
      this.loadAndRenderContentDocument(savedContentDocumentId);
    } else {
      this.getTemplateFromServer(this.templateId);
    }
  }

  getTemplateFromServer(templateId) {
    // Resolves the template's ContentDocumentId via Apex, then defers
    // to loadAndRenderContentDocument for the (shared) load + render
    // pipeline used by both first-load-from-template and
    // load-from-saved-renderer-payload paths.
    getTemplate({ templateId: templateId })
      .then((contentDocumentId) => this.loadAndRenderContentDocument(contentDocumentId))
      .catch((error) => {
        const msg = error?.body?.message || error?.message || (typeof error === 'object' ? JSON.stringify(error) : String(error));
        console.error('Error fetching template:', msg);
        this._notifyUser('Error', msg, 'error');
        this.loading = false;
      });
  }

  async loadAndRenderContentDocument(contentDocumentId) {
    console.log('[PDFforceRenderer] loadAndRenderContentDocument', contentDocumentId);
    if (!contentDocumentId) {
      this.loading = false;
      return;
    }
    try {
      // IMPORTANT: do NOT use `this.sessionId` here. That field is
      // never assigned in this component (the VF message bridge only
      // sets `this.vfPageUrl`), so it would be `undefined` and jsforce
      // would fail with INVALID_SESSION_ID. The save path
      // (handleSaveDocument) and the builder both pull a fresh
      // session via getUserSessionId() -- which round-trips through
      // PDFforceController.getUserSessionId -> SessionIdProvider.page
      // and returns a session id that's valid for both the Lightning
      // and *.vf.force.com origins. Mirror that here so the load
      // fallback (>= 3 MB files going through pDFforceUtils.loadTemplateFromSalesforce)
      // gets an authenticated connection too.
      const conn = new jsforce.Connection({
        serverUrl: this.vfRoot,
        sessionId: await getUserSessionId()
      });

      // Strategy mirrors pdfTemplateBuilder.loadTemplateVersion:
      //   1) Small files (< 3 MB) come back from Apex (loadTemplateJSON) as
      //      { versionData: <base64>, contentVersion: <CV metadata> }.
      //      The renderer only needs versionData; the builder uses
      //      contentVersion to drive save-as-new-version.
      //   2) Larger files would blow the Apex heap, so versionData is null
      //      and we fall back to fetching VersionData directly via jsforce.
      //      That path returns a Uint8Array of gzip bytes.
      //
      // handleDecompress accepts both shapes and normalizes them before
      // calling pako.ungzip.
      //
      // NOTE: @AuraEnabled methods MUST be invoked from LWC with a single
      // object of named params, otherwise the runtime throws
      // "ServerServiceImpl::unwrapAction Class Cast Exception".
      const apexResult = await loadTemplateJSON({
        template: contentDocumentId,
        recordId: this.recordId
      });
      let rawTemplate = apexResult?.versionData;
      if (!rawTemplate) {
        const fallback = await loadTemplateFromSalesforce(contentDocumentId, conn);
        if (fallback?.error) {
          console.error('loadTemplateFromSalesforce error', fallback.error);
          this._notifyUser(
            'Error',
            fallback.error.errorMessage || 'Failed to load template',
            'error'
          );
          this.loading = false;
          return;
        }
        rawTemplate = fallback?.rawData;
      }

      const decompressed = await this.handleDecompress(rawTemplate);
      if (!decompressed) {
        this._notifyUser('Error', 'Failed to decompress template', 'error');
        this.loading = false;
        return;
      }

      if (decompressed.kind === 'html') {
        // Legacy `.html` / `.html.gz` save (pre-`.json.zip` cutover):
        // raw compiled HTML on the wire, no JSON envelope. The bytes
        // already contain signature stamps + paged.js page wrappers,
        // so render verbatim and skip the re-stamp pass.
        this._restampSignaturesAfterRender = false;
        this._renderSavedCompiledHtml(decompressed.data);
        return;
      }

      // JSON branch handles BOTH:
      //   a) New `.json.zip` envelope written by handleSaveDocument:
      //        { kind: 'compiled', htmlContent, signatureFields, inputJSON }
      //      -> render htmlContent verbatim via _renderSavedCompiledHtml
      //         (same path as the legacy `.html` save above); restore
      //         signatureFields so the UI shows completion state.
      //   b) Legacy template wrapper / pre-`kind` JSON saves:
      //        { htmlContent, signatureFields, inputJSON }
      //      -> go through paged.js (displayPDF) because htmlContent is
      //         the pre-paged Handlebars output, not pre-paginated HTML.
      const payload = decompressed.data || {};
      this.signatureFields = payload.signatureFields || [];
      // Saved renderer payloads also persist the inputJSON snapshot so
      // the reload renders against the same merge data the user saved
      // against. Plain template files (loaded via templateId) don't
      // have it, in which case we leave the @api inputJSON alone.
      // if (payload.inputJSON && typeof payload.inputJSON === 'object') {
      //   this.inputJSON = [...payload.inputJSON];
      // }

      if (payload.kind === 'compiled' && typeof payload.htmlContent === 'string') {
        // Signatures are baked into htmlContent; the UI completion
        // state is restored from signatureFields above. No re-stamp
        // pass and no paged.js re-pagination.
        this._restampSignaturesAfterRender = false;
        this.serverHTML = payload.htmlContent;
        this._renderSavedCompiledHtml(payload.htmlContent);
        return;
      }

      this.serverHTML = payload.htmlContent;
      this.displayPDF(this.serverHTML);
      this.loading = true;
    } catch (error) {
      const msg = error?.body?.message || error?.message || (typeof error === 'object' ? JSON.stringify(error) : String(error));
      console.error('Error loading content document:', msg);
      this._notifyUser('Error', msg, 'error');
      this.loading = false;
    }
  }

  // Normalizes a saved-template payload (base64 string from Apex,
  // Uint8Array from the jsforce fallback, or an ArrayBuffer) into a
  // tagged result the caller can branch on:
  //
  //   { kind: 'json', data: <parsed object> }  -> legacy renderer save
  //     ({ htmlContent, signatureFields, inputJSON }) OR a template
  //     authoring file written by pdfTemplateBuilder.
  //
  //   { kind: 'html', data: <html string> }    -> new renderer save,
  //     i.e. the post-paged.js preview pane HTML with signature
  //     stamps already in place. Rendered directly without Handlebars
  //     or paged.js.
  //
  // Returns null on any decode/parse failure.
  //
  // Format sniffing (mirrors pdfTemplateBuilder.handleDecompress so the
  // two LWCs agree on every wire format the builder can produce):
  //   1) First 4 bytes 50 4B 03 04 -> ZIP (current default, JSZip).
  //      Inner entry is always `payload.json` (or any *.json), and the
  //      content is always JSON for template files.
  //   2) First 2 bytes 1F 8B       -> gzip (legacy, pako). Ungzip
  //      then sniff the decoded string.
  //   3) First byte `{` or `[`     -> raw UTF-8 JSON.
  //   4) Otherwise                 -> raw HTML (renderer's own
  //      compiled-HTML save format, not gzipped because the renderer
  //      saves it as-is for fast reload).
  //
  // Note on base64: PDFforceController.loadTemplateJSON returns
  // EncodingUtil.base64Encode(cv.VersionData) - i.e. a base64 STRING.
  // We always atob() to bytes first, then sniff. pako.ungzip /
  // JSZip.loadAsync on a base64 string would read charCodeAt of the
  // base64 alphabet instead of the real bytes and bail.
  async handleDecompress(payload) {
    try {
      let bytes;
      if (payload instanceof Uint8Array) {
        bytes = payload;
      } else if (payload instanceof ArrayBuffer) {
        bytes = new Uint8Array(payload);
      } else if (typeof payload === 'string') {
        const base64 = payload.startsWith('data:') && payload.includes(',')
          ? payload.split(',')[1]
          : payload;
        const binaryString = atob(base64);
        bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
      } else {
        throw new Error('handleDecompress: unsupported payload type');
      }

      const magic = Array.from(bytes.slice(0, 4))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join(' ');
      const isZip = bytes.length >= 4
        && bytes[0] === 0x50 && bytes[1] === 0x4b
        && bytes[2] === 0x03 && bytes[3] === 0x04;
      const isGzip = bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;

      let decoded;
      if (isZip) {
        // Always JSON for template files; unzipping returns the
        // payload.json text. JSON.parse happens in the JSON branch
        // below so the same error path covers all three formats.
        decoded = await this._unzipPayloadAsync(bytes);
      } else if (isGzip) {
        decoded = window.pako.ungzip(bytes, { to: 'string' });
      } else {
        // TextDecoder handles multi-byte UTF-8 correctly; a
        // String.fromCharCode loop would truncate each byte to
        // Latin-1 and mangle anything outside U+0000..U+00FF.
        decoded = new TextDecoder('utf-8').decode(bytes);
      }

      const firstChar = (decoded || '').trimStart().charAt(0);
      const looksLikeJson = firstChar === '{' || firstChar === '[';
      console.log(
        `[handleDecompress] payload length=${bytes.length} magic=${magic} zip=${isZip} gzip=${isGzip} kind=${looksLikeJson ? 'json' : 'html'}`
      );

      if (looksLikeJson) {
        try {
          return { kind: 'json', data: JSON.parse(decoded) };
        } catch (parseErr) {
          console.warn(
            '[handleDecompress] payload starts with { or [ but JSON.parse failed; falling back to HTML',
            parseErr?.message
          );
        }
      }
      return { kind: 'html', data: decoded };
    } catch (error) {
      console.error('Error decompressing template payload:', error);
      return null;
    }
  }

  /**
   * Read a ZIP archive produced by pdfTemplateBuilder._zipPayloadAsync
   * (or any ZIP containing a single JSON entry) and return the JSON
   * text. Verbatim copy of the builder's helper so both LWCs decode
   * the same way; keep them in sync or factor into c/pDFforceUtils
   * if any divergence creeps in.
   *
   * Tolerant on the entry name: prefers `payload.json`, then any
   * `.json` file, then the first non-directory entry. That way old
   * test fixtures or hand-built ZIPs still load.
   */
  async _unzipPayloadAsync(bytes, { fileName = 'payload.json' } = {}) {
    const J = window.JSZip;
    if (!J || typeof J.loadAsync !== 'function') {
      throw new Error(
        '[_unzipPayloadAsync] window.JSZip is not loaded or missing loadAsync. '
        + 'Check that the JZIP static resource exposes the JSZip global and '
        + 'that connectedCallback() awaits its loadScript before triggering '
        + 'handleDecompress.'
      );
    }
    this._logJsZipVersionOnce();

    // Normalize to a plain Uint8Array. JSZip accepts many input shapes
    // but breaks on subtle ones (e.g. a Uint8Array that's a view over a
    // larger SharedArrayBuffer slice), so we explicitly hand it bytes
    // it cannot misinterpret.
    let input;
    if (bytes instanceof Uint8Array) {
      input = bytes;
    } else if (bytes instanceof ArrayBuffer) {
      input = new Uint8Array(bytes);
    } else {
      throw new Error('[_unzipPayloadAsync] expected Uint8Array or ArrayBuffer, got ' + typeof bytes);
    }

    // Diagnostics: log size + first 4 magic bytes BEFORE attempting to
    // parse. If loadAsync throws, this leaves a breadcrumb that tells us
    // whether we even had a ZIP signature on the wire.
    const head = Array.from(input.slice(0, 4))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join(' ');
    const looksLikeZip = input.length >= 4
      && input[0] === 0x50 && input[1] === 0x4b
      && input[2] === 0x03 && input[3] === 0x04;
    console.log(
      '[_unzipPayloadAsync] bytes=', input.length,
      'head=', head,
      'looksLikeZip=', looksLikeZip
    );
    if (!looksLikeZip) {
      throw new Error(
        '[_unzipPayloadAsync] input does not start with the ZIP magic '
        + '50 4B 03 04. First 4 bytes: ' + head + '. This usually means '
        + 'the bytes were not produced by _zipPayloadAsync (could be raw '
        + 'JSON, gzip, or base64 that was double-decoded).'
      );
    }

    let zip;
    try {
      zip = await J.loadAsync(input);
    } catch (e) {
      throw new Error(
        '[_unzipPayloadAsync] JSZip.loadAsync failed: ' + (e && e.message ? e.message : e)
        + ' (bytes=' + input.length + ', head=' + head + ')'
      );
    }

    let entry = zip.file(fileName);
    if (!entry) {
      const jsonEntries = zip.file(/\.json$/i);
      if (jsonEntries && jsonEntries.length > 0) entry = jsonEntries[0];
    }
    if (!entry) {
      entry = Object.values(zip.files).find((f) => !f.dir);
    }
    if (!entry) {
      const names = Object.keys(zip.files || {});
      throw new Error(
        '[_unzipPayloadAsync] ZIP archive contains no readable entry. Entries: '
        + (names.length ? names.join(', ') : '(none)')
      );
    }
    try {
      return await entry.async('string');
    } catch (e) {
      throw new Error(
        '[_unzipPayloadAsync] entry.async("string") failed for "'
        + entry.name + '": ' + (e && e.message ? e.message : e)
      );
    }
  }

  /**
   * Print the JSZip version once per LWC session so we can correlate
   * runtime errors with the actual library version that won the
   * script load race.
   */
  _logJsZipVersionOnce() {
    if (this._jsZipVersionLogged) return;
    this._jsZipVersionLogged = true;
    const v = (window.JSZip && window.JSZip.version) || '(unknown)';
    const support = (window.JSZip && window.JSZip.support) || null;
    console.log('[JSZip] version=', v, 'support=', support);
  }

  /**
   * Wrap a JSON string in a ZIP archive (single entry `payload.json`)
   * and return the bytes as a Uint8Array. Mirrors
   * pdfTemplateBuilder._zipPayloadAsync exactly so the wire format the
   * renderer writes is byte-compatible with what the builder writes --
   * meaning every loader (Apex findRendererTemplateContentId /
   * getTemplate, pDFforceUtils.loadTemplateFromSalesforce, and this
   * file's own handleDecompress / _unzipPayloadAsync) sees one and
   * only one save format: `.json.zip`.
   *
   * NOTE: deliberately NOT passing `streamFiles: true`. Streamed ZIPs
   * omit local-file-header sizes (they're written in a trailing data
   * descriptor instead) and some readers -- including older JSZip
   * builds and Apex's Compression.ZipReader in some orgs -- refuse to
   * parse them ("Could not load Zip / unknown archive"). Standard
   * non-streamed output is universally compatible.
   */
  async _zipPayloadAsync(jsonString, { level = 9, fileName = 'payload.json' } = {}) {
    const J = window.JSZip;
    if (!J || typeof J.loadAsync !== 'function') {
      throw new Error(
        '[_zipPayloadAsync] window.JSZip is not loaded or missing loadAsync. '
        + 'Check that the JZIP static resource exposes the JSZip global and '
        + 'that connectedCallback() awaits its loadScript before save.'
      );
    }
    this._logJsZipVersionOnce();
    const zip = new J();
    zip.file(fileName, jsonString);
    return zip.generateAsync({
      type: 'uint8array',
      compression: 'DEFLATE',
      compressionOptions: { level },
    });
  }

  /**
   * Renders a previously-saved compiled HTML document directly into the
   * preview pane. The saved HTML already contains:
   *   - The <style> tags that drive the docx layout + paged.js margins
   *   - The .pagedjs_page wrappers paged.js produced on the original render
   *   - Every signature stamp as an inline <img> overlay
   *
   * So we just need to make sure those <style> tags re-attach to
   * document.head (otherwise the preview shows unstyled markup) and
   * the body content goes into .preview-pane.
   */
  _renderSavedCompiledHtml(htmlString) {
    try {
      this.startUiContainerManagerGuard();

      const parser = new DOMParser();
      const doc = parser.parseFromString(htmlString || '', 'text/html');

      // Re-attach styles to document.head so the preview is styled.
      // Tag any untagged style with data-pdfforce-style so a later
      // handleSubmitDocument forwards them back to the VF iframe.
      const styleNodes = doc.querySelectorAll('style');
      styleNodes.forEach((styleNode) => {
        const clone = styleNode.cloneNode(true);
        if (!clone.hasAttribute('data-pdfforce-style')
          && !Array.from(clone.attributes || []).some((a) => a.name.startsWith('data-pagedjs'))) {
          clone.setAttribute('data-pdfforce-style', 'true');
        }
        document.head.appendChild(clone);
      });
     

      const previewPane = this.querySelector('.preview-pane');
      if (previewPane) {
        previewPane.innerHTML = '';
        // The body usually contains the .preview-pane innerHTML AND the
        // style tags (we just cloned them up to head; leave the
        // originals in the body so paged.js's own selectors still
        // match). Use body.innerHTML so we keep paged.js page wrappers.
        if (doc.body) {
          previewPane.insertAdjacentHTML('afterbegin', doc.body.innerHTML);
          this._tightenDocxPageMargins(previewPane);
        } else if (htmlString) {
          previewPane.insertAdjacentHTML('afterbegin', htmlString);
        }
   
      }
    } catch (error) {
      console.error('_renderSavedCompiledHtml error', error);
      this._notifyUser('Error', 'Failed to render saved document', 'error');
    } finally {
      this.loading = false;
    }
  }


  /**
     * Wraps every contiguous run of non-Latin (script-specific) codepoints
     * inside the given subtree in a font-specific <span>. This is the
     * single source of truth for "which text should switch fonts during
     * pdf.html() emission" - one wrap here propagates through paged.js,
     * the visible preview pane, postMessage to the iframe, and
     * pdf.html()'s per-element font selection.
     *
     * Currently handles Devanagari (U+0900..U+097F). Add a new entry to
     * SCRIPT_CONFIG to support more scripts (Bengali, Tamil, Arabic,
     * CJK, etc.) - each script gets its own class name so the iframe
     * stylesheet can map it to a different jsPDF-registered font.
     *
     * Implementation notes:
     *   - We operate on Text nodes (TreeWalker SHOW_TEXT), not innerHTML,
     *     so we never re-parse markup, lose event handlers, or wreck
     *     attribute values that happen to contain matching codepoints.
     *   - Targets are collected first, mutated after - mutating during
     *     walk invalidates the walker.
     *   - Nodes inside <script>, <style>, or ALREADY-wrapped spans are
     *     skipped (idempotent: safe to run twice).
     *
     * @param {Element} root  Subtree to scan.
     * @returns {number} Total spans inserted across all scripts.
     */
  wrapNonLatinRuns(root) {
    if (!root) return 0;

    // =================================================================
    // SCRIPT_CONFIG - which codepoint ranges this LWC should wrap.
    // =================================================================
    // Each entry pairs a Unicode regex with the CSS class name to put
    // on the wrapper span. The className MUST match a corresponding
    // entry in FONT_CONFIG inside SessionIdProvider.page - that file
    // is where the actual TTF (Salesforce Static Resource) is loaded,
    // injected as @font-face, and registered in jsPDF's font catalog.
    //
    // ---------------------------------------------------------------
    // How to add a new script (Bengali / Tamil / Arabic / CJK / ...):
    // ---------------------------------------------------------------
    //   1. In SessionIdProvider.page -> FONT_CONFIG, add an entry
    //      with the static resource, font family, and the className.
    //   2. Here, add an entry below with the SAME className and the
    //      Unicode range regex for that script's block(s).
    //   3. Upload the .ttf as a Salesforce Static Resource named per
    //      the FONT_CONFIG url.
    // No CSS edits, no new functions.
    const SCRIPT_CONFIG = [
      { name: 'devanagari', className: 'pdfforce-devanagari', regex: /[\u0900-\u097F]+/g }
      // Examples - uncomment when adding the matching FONT_CONFIG entry:
      // ,{ name: 'bengali', className: 'pdfforce-bengali', regex: /[\u0980-\u09FF]+/g }
      // ,{ name: 'tamil',   className: 'pdfforce-tamil',   regex: /[\u0B80-\u0BFF]+/g }
      // ,{ name: 'arabic',  className: 'pdfforce-arabic',  regex: /[\u0600-\u06FF\u0750-\u077F]+/g }
      // ,{ name: 'cjk',     className: 'pdfforce-cjk',     regex: /[\u4E00-\u9FFF\u3400-\u4DBF]+/g }
    ];

    const knownClassNames = SCRIPT_CONFIG.map((c) => c.className);
    let totalWrapped = 0;

    const walker = document.createTreeWalker(
      root,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: (node) => {
          const parent = node.parentNode;
          if (!parent) return NodeFilter.FILTER_REJECT;
          const tag = parent.nodeName;
          if (tag === 'SCRIPT' || tag === 'STYLE') return NodeFilter.FILTER_REJECT;
          if (parent.classList) {
            for (const cls of knownClassNames) {
              if (parent.classList.contains(cls)) return NodeFilter.FILTER_REJECT;
            }
          }
          const v = node.nodeValue;
          if (!v) return NodeFilter.FILTER_REJECT;
          for (const cfg of SCRIPT_CONFIG) {
            cfg.regex.lastIndex = 0;
            if (cfg.regex.test(v)) return NodeFilter.FILTER_ACCEPT;
          }
          return NodeFilter.FILTER_REJECT;
        }
      }
    );

    const targets = [];
    let n;
    while ((n = walker.nextNode())) targets.push(n);

    targets.forEach((textNode) => {
      const text = textNode.nodeValue;
      // Build a flat list of (script, start, end) match intervals across
      // all configured scripts, then sort by start position so we can
      // walk the text linearly and emit text/span/text/span/... in order.
      const intervals = [];
      for (const cfg of SCRIPT_CONFIG) {
        cfg.regex.lastIndex = 0;
        let m;
        while ((m = cfg.regex.exec(text)) !== null) {
          intervals.push({
            className: cfg.className,
            start: m.index,
            end: m.index + m[0].length,
            value: m[0]
          });
        }
      }
      if (intervals.length === 0) return;
      intervals.sort((a, b) => a.start - b.start);

      const frag = document.createDocumentFragment();
      let cursor = 0;
      intervals.forEach((iv) => {
        // Defensive: skip overlapping intervals (shouldn't happen with
        // disjoint Unicode ranges, but be safe if SCRIPT_CONFIG grows).
        if (iv.start < cursor) return;
        if (iv.start > cursor) {
          frag.appendChild(document.createTextNode(text.slice(cursor, iv.start)));
        }
        const span = document.createElement('span');
        span.className = iv.className;
        span.textContent = iv.value;
        frag.appendChild(span);
        cursor = iv.end;
        totalWrapped++;
      });
      if (cursor < text.length) {
        frag.appendChild(document.createTextNode(text.slice(cursor)));
      }
      textNode.parentNode.replaceChild(frag, textNode);
    });

    return totalWrapped;
  }

  /**
     * Pre-fetches image data URLs and registers Handlebars helpers.
     * Handlebars helpers must return synchronously, so we fetch first, then register.
     * Returns a Promise that resolves when helpers are ready for templating.
     */
  registerImgHelpersFromData(data = {}) {
    const root = data || {};
    const imgKeys = Object.keys(root).filter((k) => k.startsWith('IMG_'));

    if (imgKeys.length === 0) {
      return Promise.resolve();
    }

    return Promise.all(
      imgKeys.map((k) =>
        getContentVersionId({ contentDocumentId: root[k] })
          .then((dataUrl) => ({ key: k, dataUrl }))
          .catch((err) => {
            console.error(`Error fetching image for ${k}:`, err?.message);
            return { key: k, dataUrl: null };
          })
      )
    ).then((resolved) => {
      const urlMap = {};
      resolved.forEach(({ key, dataUrl }) => { urlMap[key] = dataUrl; });

      imgKeys.forEach((k) => {
        Handlebars.registerHelper(k, function () {
          const url = urlMap[k];
          if (!url) return '';
          return new Handlebars.SafeString(
            `<img src="${url}" alt="Image" style="max-width: 100%; max-height: 100%; display: block;" />`
          );
        });
      });
    });
  }



  @track templateHtml = null;
  async displayPDF(htmlContent) {
    this.loading = true;

    try {
      this.startUiContainerManagerGuard();
      // Build container from HTML
      const container = document.createElement("div");

      // Convert arrayBuffer to html
      const html = htmlContent;
      let inputJSON = this.inputJSON;

      // ---- Diagnostic: what does inputJSON actually look like at the
      // boundary into the renderer? Logs the type, a JSON dump, whether
      // any value contains real Devanagari (U+0900-U+097F), and whether
      // any value contains the characteristic low-byte mangling pattern
      // (`/ 6 6 > 9`) that comes from a UTF-16 -> Latin-1 truncation
      // somewhere upstream of @api inputJSON.
      try {
        const inputType = typeof inputJSON;
        const jsonDump = JSON.stringify(inputJSON);
        const devanagariMatches = (jsonDump || '').match(/[\u0900-\u097F]+/g) || [];
        const looksMangled = /[\u0080-\u00FF]/.test(jsonDump || ''); // any non-ASCII high byte (post-truncation)
       
        if (!devanagariMatches.length && jsonDump && /[/6>9]/.test(jsonDump)) {
          console.warn(
            '[displayPDF] inputJSON has no Devanagari but contains "/", "6", ">", "9" - ' +
            'caller likely mangled the data by passing the JSON through a UTF-16 -> Latin-1 ' +
            'conversion (e.g. URL param, Lightning App Builder string property, Flow text var, ' +
            'or unescape(encodeURIComponent(...))). Inspect the PARENT component that sets ' +
            '@api inputJSON, not the renderer.'
          );
        }
      } catch (diagErr) {
        console.warn('[displayPDF] inputJSON diagnostic failed', diagErr);
      }

      let CleanHtml = robustHandlebarsHealer(html);
      // Guard: if Handlebars never loaded (static-resource fetch
      // failed, or this method was somehow invoked before
      // connectedCallback's Promise.all resolved) we'd silently emit
      // the raw template with {{...}} placeholders. Fail loudly
      // instead so the regression is obvious.
      if (typeof Handlebars === 'undefined' || !Handlebars?.compile) {
        throw new Error(
          '[displayPDF] Handlebars is not loaded; merge fields will not be substituted. '
          + 'Ensure HANDLEBARSJS static resource loaded before rendering.'
        );
      }
      this.templateHtml = Handlebars.compile(CleanHtml);
      await this.registerImgHelpersFromData(inputJSON)
      let compiledHtml = this.templateHtml(inputJSON);
      container.insertAdjacentHTML('beforeend', compiledHtml);

      // ---- Non-Latin text wrapping ------------------------------------
      // After Handlebars has substituted inputJSON values into the
      // template, walk the just-inserted DOM and wrap every contiguous
      // run of non-Latin codepoints in a font-specific <span>. This is
      // the upstream-of-everything point to do this: paged.js, the
      // preview pane, the postMessage to the VF iframe, and pdf.html()
      // all inherit the wrapped DOM verbatim - so non-Latin runs hit
      // jsPDF's text emitter with the right CSS font-family while
      // everything else keeps its original CSS font / weight / face.
      //
      // Why not do this in the Handlebars template itself?
      //   - The same template is used for English-only renders too;
      //     wrapping at template-time would force every author to know
      //     about jsPDF's font catalog.
      //   - inputJSON values can contain mixed scripts ("यश Shah").
      //     A DOM-level walker handles that cleanly by splitting the
      //     text node; a string-level wrap in the template can't.
      //
      // Why not do this in SessionIdProvider.page (the iframe)?
      //   - The iframe receives previewPane.innerHTML which has
      //     already passed through paged.js's clone-and-paginate pass.
      //     Wrapping earlier (here) keeps a single source of truth
      //     and means the visible preview also gets the spans, so
      //     debugging in DevTools matches what the PDF will look like.
      const wrappedCount = this.wrapNonLatinRuns(container);
      if (wrappedCount > 0) {
        console.log('[displayPDF] Wrapped non-Latin runs:', wrappedCount);
      }
      this.preserveDocxSpacing(container);
      console.log('[SessionIdProvider] Container populated with HTML');
      container.style.display = 'block !important';
      container.style.overflow = 'visible !important';
      container.style.height = 'auto !important';
      container.style.maxHeight = 'none !important';
      container.style.position = 'relative !important';
      container.style.breakInside = 'auto !important';
      container.style.boxSizing = 'border-box !important';
      container.style.width = '100% !important';
      // }).catch((err) => {
      //     console.error('[SessionIdProvider] Error registering image helpers:', err?.message);
      // });




      const styles = container.querySelectorAll('style');
      styles.forEach(style => {
        const cloned = style.cloneNode(true);
        // Tag so handleSubmitDocument() can locate these styles in document.head
        // and forward them to the SessionIdProvider iframe along with the HTML.
        cloned.setAttribute('data-pdfforce-style', 'true');
        document.head.appendChild(cloned);
        // style.remove();
      });






      let pageDimensions = { width: 595.28, height: 841.89 };



      const parseLengthToPt = (value) => {
        if (!value || typeof value !== 'string') return null;
        const v = value.trim().toLowerCase();
        const num = parseFloat(v);
        if (Number.isNaN(num)) return null;
        if (v.endsWith('pt')) return num;
        if (v.endsWith('px')) return (num * 72) / 96;
        if (v.endsWith('mm')) return (num * 72) / 25.4;
        if (v.endsWith('cm')) return (num * 72) / 2.54;
        if (v.endsWith('in')) return num * 72;
        return num;
      };

      // Get sections
      const sections = container.querySelectorAll('section.docx');
      if (sections.length > 0) {
        const firstSection = sections[0];
        const computed = window.getComputedStyle(firstSection);
        const widthPt =
          parseLengthToPt(firstSection.style.width) ??
          parseLengthToPt(computed.width) ??
          pageDimensions.width;
        const minHeightPt =
          parseLengthToPt(firstSection.style.minHeight) ??
          parseLengthToPt(computed.minHeight);
        const heightPt =
          parseLengthToPt(firstSection.style.height) ??
          parseLengthToPt(computed.height);
        pageDimensions.width = widthPt;
        pageDimensions.height = minHeightPt || heightPt || pageDimensions.height;
      }
      // Prepare sections for paged.js pagination
      sections.forEach((section, index) => {
        section.classList.remove('canvas-page');
        section.style.pageBreakAfter = 'auto';
        section.style.breakAfter = 'auto';
      });

      console.log('[SessionIdProvider] Sections prepared for pagination');

      // Capture first section header and render it in paged.js top margin boxes.
      const sourceHeader = container.querySelector('section.docx > header');
      const sourceSectionForHeader = sourceHeader?.closest('section.docx') || null;
      const sourceWrapperForHeader = sourceHeader?.closest('.docx-wrapper') || null;
      const parsePxNumber = (value) => {
        if (value === null || value === undefined || value === '') return null;
        const n = Number.parseFloat(value);
        return Number.isFinite(n) ? n : null;
      };
      // Headers authored via the moveable tooling carry data-moveable-valid-* attributes
      // describing absolute placement inside the section. Plain docx headers don't, and
      // we want to preserve their natural padding/margin relative to the section.
      const hasMoveableTags = !!sourceHeader && Array.from(sourceHeader.attributes || [])
        .some((attr) => attr?.name?.startsWith('data-moveable-'));
      const headerTopPx = parsePxNumber(sourceHeader?.getAttribute('data-moveable-valid-top')) ?? 0;
      const headerHeightPx = parsePxNumber(sourceHeader?.getAttribute('data-moveable-valid-height'))
        ?? parsePxNumber(sourceHeader?.style?.height)
        ?? 0;

      // Reserve top margin space large enough to host the repeated header, and for
      // non-moveable headers also capture the section's "page margins" (padding-left,
      // padding-right, padding-top) so the repeated header on each page can be
      // positioned with the same horizontal/vertical inset as the original section.
      let repeatedHeaderTopMarginPx = 0;
      let sectionPaddingPx = { top: 0, left: 0, right: 0 };
      if (sourceHeader) {
        if (hasMoveableTags) {
          repeatedHeaderTopMarginPx = Math.max(0, Math.ceil(headerTopPx + headerHeightPx));
        } else if (sourceSectionForHeader) {
          const measurementHost = document.createElement('div');
          measurementHost.style.position = 'fixed';
          measurementHost.style.left = '-100000px';
          measurementHost.style.top = '0';
          measurementHost.style.visibility = 'hidden';
          measurementHost.style.pointerEvents = 'none';
          measurementHost.style.zIndex = '-1';

          const sectionClone = sourceSectionForHeader.cloneNode(true);
          measurementHost.appendChild(sectionClone);
          document.body.appendChild(measurementHost);
          const measuredHeader = sectionClone.querySelector(':scope > header');
          if (measuredHeader) {
            const sectionRect = sectionClone.getBoundingClientRect();
            const headerRect = measuredHeader.getBoundingClientRect();
            repeatedHeaderTopMarginPx = Math.max(0, Math.ceil(headerRect.bottom - sectionRect.top));
          }
          const sectionComputed = window.getComputedStyle(sectionClone);
          sectionPaddingPx = {
            top: parsePxNumber(sectionComputed.paddingTop) ?? 0,
            left: parsePxNumber(sectionComputed.paddingLeft) ?? 0,
            right: parsePxNumber(sectionComputed.paddingRight) ?? 0
          };
          document.body.removeChild(measurementHost);
        }
      }
      // Preserve the original ancestor chain (.docx-wrapper > section.docx > header)
      // so descendant selectors from the docx-export <style> blocks keep matching the
      // header when it is re-injected into paged.js's .pagedjs_margin-top band.
      const repeatedHeaderTemplate = sourceHeader
        ? {
          html: sourceHeader.outerHTML,
          hasMoveableTags,
          sectionClassName: sourceSectionForHeader?.className || 'docx',
          sectionStyle: sourceSectionForHeader?.getAttribute('style') || '',
          wrapperClassName: sourceWrapperForHeader?.className || 'docx-wrapper',
          wrapperStyle: sourceWrapperForHeader?.getAttribute('style') || '',
          sectionPaddingPx
        }
        : null;

      // Remove source header from flowing content; it'll be rendered in page margin boxes.
      if (sourceHeader) {
        sourceHeader.remove();
      }

      this._tightenDocxPageMargins(container);

      const pageNumberPosition = this._pageNumberPosition;
      const showPageNumbers = pageNumberPosition !== 'none';
      const pageNumberTextAlign = pageNumberPosition === 'left'
        ? 'left'
        : pageNumberPosition === 'right'
          ? 'right'
          : 'center';
      // CSS @page margin box only when a position is configured. When 'none' is
      // chosen we omit the rule entirely so paged.js doesn't reserve a slot.
      const pageNumberMarginBoxRule = showPageNumbers
        ? `@bottom-${pageNumberPosition} {
                          content: "Page " counter(page) " of " counter(pages);
                          font-size: 10px;
                          color: #444;
                          vertical-align: middle;
                      }`
        : '';

      const pageStyles = `
                  @page {
                      size: ${pageDimensions.width}pt ${pageDimensions.height}pt;
                      margin: ${repeatedHeaderTopMarginPx}px 0 12mm 0;
                      padding: 0;
                      ${pageNumberMarginBoxRule}
                  }

                  @page :blank {
                    display: none;
                  }

                  body {
                      margin: 0;
                      padding: 0;
                  }

                  .pagedjs_pages {
                      background: #f0f0f0;
                      padding: 20px 0;
                  }

                  /* The repeated header is injected as a direct child of .pagedjs_margin-top
                     after pagination, so make sure paged.js doesn't hide this band. */
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-top {
                    width: 100% !important;
                    max-width: 100% !important;
                    visibility: visible !important;
                    display: block !important;
                    position: relative !important;
                    overflow: visible !important;
                  }

                  /* The @page margin-top above already reserves
                     section.padding-top + header.height pixels for the
                     repeated header band. paged.js then flows the same
                     section.docx into the body of each page, and it still
                     carries its own padding-top (~50px from docx-preview),
                     which double-counts that space and pushes body content
                     down by an extra padding-top px on every page. Zero
                     it out for body sections only.

                     IMPORTANT: must exclude [data-pdf-force-repeated-section]
                     - the PDFGenerationHandler reuses <section class="docx">
                     to wrap the repeated header on each page and relies on
                     an inline padding-top (sectionEl.style.paddingTop)
                     to position the header correctly inside the margin
                     band. A blanket rule with !important would override
                     that inline style and make the repeated header
                     collapse to the top edge (where it's clipped). */
                  section.docx:not([data-pdf-force-repeated-section]){
                    padding-top: 0 !important;
                    padding-left: ${PDF_PAGE_SIDE_MARGIN} !important;
                    padding-right: ${PDF_PAGE_SIDE_MARGIN} !important;
                    margin-left: 0 !important;
                    margin-right: 0 !important;
                    width: 100% !important;
                    max-width: 100% !important;
                    box-sizing: border-box !important;
                  }

                  section.docx:not([data-pdf-force-repeated-section]) > article {
                    padding-left: 0 !important;
                    padding-right: 0 !important;
                    margin-left: 0 !important;
                    margin-right: 0 !important;
                    width: 100% !important;
                    max-width: 100% !important;
                    box-sizing: border-box !important;
                  }

                  .docx-wrapper {
                    padding-top: 0 !important;
                    padding-left: 0 !important;
                    padding-right: 0 !important;
                  }

                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-top > [data-pdf-force-repeated-header="true"] {
                    position: absolute !important;
                    inset: 0 !important;
                    width: 100% !important;
                    max-width: 100% !important;
                    box-sizing: border-box !important;
                    pointer-events: none !important;
                  }

                  /* Hide top corner/left/center/right cells; the repeated header occupies the full band. */
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-top-left-corner,
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-top-right-corner,
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-top-left,
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-top-center,
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-top-right {
                    display: none !important;
                    visibility: hidden !important;
                  }

                  .pagedjs_page {
                      margin: 20px auto;
                      background: white;
                      box-shadow: 0 4px 8px rgba(0,0,0,0.2);
                  }

                  /* Preserve docx-preview tab/space behavior across paged.js flow */
                  .docx-tab-stop {
                      white-space: pre !important;
                  }

                  section.docx header span,
                  section.docx footer span {
                      white-space: pre-wrap;
                  }


                  thead {
                    display: table-header-group; /* Repeat header */
                   }

                  tbody {
                    display: table-row-group;
                  } 

                  /* Preserve source layout for structural blocks (header/footer and section wrappers). */
                  section.docx > header,
                  section.docx > footer {
                      page-break-inside: avoid;
                      break-inside: avoid;
                      display: block;
                  }

                  section.docx > article {
                      page-break-inside: auto;
                      break-inside: auto;
                  }

                  ${showPageNumbers
          ? `/* Keep the configured footer page-number margin visible even
                       when paged.js marks margins hidden by default */
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-bottom-${pageNumberPosition} {
                      visibility: visible !important;
                  }

                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-bottom-${pageNumberPosition} .pagedjs_margin-content {
                      visibility: visible !important;
                      display: block !important;
                      width: 100% !important;
                      text-align: ${pageNumberTextAlign} !important;
                  }`
          : `/* Page numbers disabled - hide every bottom margin cell so
                       paged.js doesn't render an empty band. */
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-bottom,
                  .pagedjs_pages .pagedjs_pagebox [class*="pagedjs_margin-bottom-"] {
                      display: none !important;
                      visibility: hidden !important;
                  }`}

                  .pagedjs_pagebox {
                      grid-template-columns: unset !important;
                      grid-template-rows: [header] var(--pagedjs-margin-top) [page] calc(var(--pagedjs-pagebox-height) - var(--pagedjs-margin-top) - var(--pagedjs-margin-bottom)) [footer] var(--pagedjs-margin-bottom) !important;
                  }

                  /* Remove empty left/right paged.js margin boxes from render output */
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-left,
                  .pagedjs_pages .pagedjs_pagebox .pagedjs_margin-right,
                  .pagedjs_pages .pagedjs_pagebox [class*="pagedjs_margin-left-"],
                  .pagedjs_pages .pagedjs_pagebox [class*="pagedjs_margin-right-"] {
                      display: none !important;
                      visibility: hidden !important;
                  }
             
          `;

      // Add our page styles
      const styleElement = document.createElement('style');
      styleElement.setAttribute('data-pdfforce-style', 'true');
      styleElement.setAttribute('data-pdfforce-page-styles', 'true');
      styleElement.textContent = pageStyles;
      container.insertBefore(styleElement, container.firstChild);

      let pdfData = [];

      // PDF Generation Handler
      class PDFGenerationHandler extends window.Paged.Handler {
        constructor(chunker, polisher, caller) {
          super(chunker, polisher, caller);
          this.sectionIndex = 0;
          this.pdfData = [];
        }


        async afterRendered(pages) {
          // Log page details
          pages.forEach((page, index) => {
            const content = page.element.querySelector('.pagedjs_page_content');
          });

          // Hide (but keep) empty pages, pages that only contain style tags, 
          // and pages without valid sections (header/article/footer)
          // This preserves styles while excluding them from PDF generation
          let hiddenPagesCount = 0;
          pages.forEach((page, index) => {
            const content = page.element.querySelector('.pagedjs_page_content');
            const pageElement = page.element;
            let shouldHide = false;
            let hideReason = '';

            if (content) {
              // Get all style tags from both page content and page element
              const styleTagsInContent = content.querySelectorAll('style');
              const styleTagsInPage = pageElement.querySelectorAll('style');
              const allStyleTags = [...styleTagsInContent, ...styleTagsInPage];

              // Get all children excluding style tags from content
              const nonStyleChildren = Array.from(content.children).filter(
                child => child.tagName !== 'STYLE'
              );

              // Check for actual content (excluding style tags)
              // Clone content to remove style tags for text check
              const contentClone = content.cloneNode(true);
              contentClone.querySelectorAll('style').forEach(style => style.remove());
              const hasText = contentClone.innerText.trim().length > 0;

              const hasImages = content.querySelectorAll('img').length > 0;
              const hasNonStyleElements = nonStyleChildren.length > 0;

              // Check if page only has style tags (no other content)
              const onlyStyleTags = allStyleTags.length > 0 && !hasText && !hasImages && !hasNonStyleElements;

              // Check if page has valid sections with header/article/footer
              const sections = content.querySelectorAll('section');
              let hasValidSection = false;

              // Check if page only contains footer(s) without article/header
              const allFooters = content.querySelectorAll('footer');
              const allArticles = content.querySelectorAll('article');
              const allHeaders = content.querySelectorAll('header');
              const onlyFooters = allFooters.length > 0 && allArticles.length === 0 && allHeaders.length === 0;

              if (sections.length > 0) {
                sections.forEach(section => {
                  const hasHeader = section.querySelector('header') !== null;
                  const hasArticle = section.querySelector('article') !== null;
                  const hasFooter = section.querySelector('footer') !== null;

                  // A section is valid if it has header or article
                  // Footer alone doesn't make a section valid (it should be with article/header)
                  if (hasHeader || hasArticle) {
                    hasValidSection = true;
                  }
                  // If section only has footer without article/header, it's not valid
                  if (hasFooter && !hasHeader && !hasArticle) {
                    // This is an orphaned footer, mark section as invalid
                  }
                });
              }

              // Hide if empty, only style tags, only footers, or no valid sections
              if ((!hasText && !hasImages && !hasNonStyleElements) || onlyStyleTags) {
                shouldHide = true;
                hideReason = `empty or only style tags - ${allStyleTags.length} style tags, ${nonStyleChildren.length} other elements`;
              } else if (onlyFooters && !hasValidSection) {
                shouldHide = true;
                hideReason = `page only contains footer(s) without article/header (${allFooters.length} footers, ${allArticles.length} articles, ${allHeaders.length} headers)`;
              } else if (!hasValidSection && sections.length > 0) {
                shouldHide = true;
                hideReason = `no section with header/article (${sections.length} sections found but none have header/article - footer alone is not valid)`;
              } else if (!hasValidSection && sections.length === 0) {
                shouldHide = true;
                hideReason = `no sections found`;
              }

              if (shouldHide) {
                pageElement.style.display = 'none';
                pageElement.setAttribute('data-hidden-page', 'true');
                //remove the page of the index from pdfData
                this.pdfData.splice(index, 1);
                hiddenPagesCount++;
              }
            } else {
              // If no content element, check if page only has style tags
              const styleTagsInPage = pageElement.querySelectorAll('style');
              const allChildren = Array.from(pageElement.children);
              const nonStyleChildren = allChildren.filter(
                child => child.tagName !== 'STYLE' && !child.classList.contains('pagedjs_margin-top') &&
                  !child.classList.contains('pagedjs_margin-bottom') &&
                  !child.classList.contains('pagedjs_margin-left') &&
                  !child.classList.contains('pagedjs_margin-right')
              );

              // Check for sections in page element itself
              const sections = pageElement.querySelectorAll('section');
              let hasValidSection = false;

              if (sections.length > 0) {
                sections.forEach(section => {
                  const hasHeader = section.querySelector('header') !== null;
                  const hasArticle = section.querySelector('article') !== null;
                  const hasFooter = section.querySelector('footer') !== null;

                  if (hasHeader || hasArticle || hasFooter) {
                    hasValidSection = true;
                  }
                });
              }

              if (styleTagsInPage.length > 0 && nonStyleChildren.length === 0) {
                shouldHide = true;
                hideReason = 'no content element, only style tags';
              } else if (!hasValidSection) {
                shouldHide = true;
                hideReason = `no valid sections (${sections.length} sections found but none have header/article/footer)`;
              }

              if (shouldHide) {
                pageElement.style.display = 'none';
                pageElement.setAttribute('data-hidden-page', 'true');
                this.pdfData.length > 0 && this.pdfData.splice(index, 1);
                hiddenPagesCount++;
              }
            }
          });
          // const { jsPDF } = window.jspdf;
          // const pdf = new jsPDF('p', 'mm', 'a4');
          // pdfData.forEach((imgData, index) => {

          //   if (index > 0) pdf.addPage();
          //   const imgProps = pdf.getImageProperties(imgData);
          //   const pdfWidth = pdf.internal.pageSize.getWidth();
          //   const pdfHeight = (imgProps.height * pdfWidth) / imgProps.width;
          //   pdf.addImage(imgData, 'JPEG', 0, 0, pdfWidth, pdfHeight);
          // });

          // pdf.save('downloadPdf.pdf');
        }
      }


      class RepeatTableHeadersHandler extends Paged.Handler {
        constructor(chunker, polisher, caller) {
          super(chunker, polisher, caller)
          this.splitTablesRefs = []
        }

        afterPageLayout(pageElement, page, breakToken, chunker) {
          this.chunker = chunker
          this.splitTablesRefs = []

          // Check all the tables on the current page
          const tablesOnPage = pageElement.querySelectorAll("table");

          // Check which tables have sources
          for (let table of tablesOnPage) {
            if (table.dataset.ref) {
              const sourceTable = chunker.source.querySelector(`[data-ref='${table.dataset.ref}']`);
              if (sourceTable) {
                this.splitTablesRefs.push(table.dataset.ref);
              }
            }
          }

          if (breakToken) {
            const node = breakToken.node
            const tables = this.findAllAncestors(node, "table")

            if (node.tagName === "TABLE") tables.push(node)

            if (tables.length > 0) {
              this.splitTablesRefs = tables.map(t => t.dataset.ref)

              let thead = node.tagName === "THEAD" ? node : this.findFirstAncestor(node, "thead")
              if (thead) {
                let lastTheadNode = thead.hasChildNodes() ? thead.lastChild : thead
                breakToken.node = this.nodeAfter(lastTheadNode, chunker.source)
              }

              this.hideEmptyTables(pageElement, node)
            }
          }
        }

        hideEmptyTables(pageElement, breakTokenNode) {
          this.splitTablesRefs.forEach(ref => {
            let table = pageElement.querySelector("[data-ref='" + ref + "']")
            if (table) {
              let sourceBody = table.querySelector("tbody > tr")
              if (!sourceBody || this.refEquals(sourceBody.firstElementChild, breakTokenNode)) {
                table.style.visibility = "hidden"
                table.style.position = "absolute"
                let lineSpacer = table.nextSibling
                if (lineSpacer) {
                  lineSpacer.style.visibility = "hidden"
                  lineSpacer.style.position = "absolute"
                }
              }
            }
          })
        }

        refEquals(a, b) {
          return a && a.dataset && b && b.dataset && a.dataset.ref === b.dataset.ref
        }

        findFirstAncestor(element, selector) {
          while (element.parentNode && element.parentNode.nodeType === 1) {
            if (element.parentNode.matches(selector)) return element.parentNode
            element = element.parentNode
          }
          return null
        }

        findAllAncestors(element, selector) {
          const ancestors = []
          while (element.parentNode && element.parentNode.nodeType === 1) {
            if (element.parentNode.matches(selector)) ancestors.unshift(element.parentNode)
            element = element.parentNode
          }
          return ancestors
        }

        layout(rendered, layout) {
          this.splitTablesRefs.forEach(ref => {
            const renderedTable = rendered.querySelector("[data-ref='" + ref + "']")
            if (renderedTable) {
              if (!renderedTable.getAttribute("repeated-headers")) {
                const sourceTable = this.chunker.source.querySelector("[data-ref='" + ref + "']")
                this.repeatColgroup(sourceTable, renderedTable)
                this.repeatTHead(sourceTable, renderedTable)
                renderedTable.setAttribute("repeated-headers", true)
              }
            }
          })
        }

        repeatColgroup(sourceTable, renderedTable) {
          let colgroup = sourceTable.querySelectorAll("colgroup")
          let firstChild = renderedTable.firstChild
          colgroup.forEach((colgroup) => {
            let clonedColgroup = colgroup.cloneNode(true)
            renderedTable.insertBefore(clonedColgroup, firstChild)
          })
        }

        repeatTHead(sourceTable, renderedTable) {
          let thead = sourceTable.querySelector("thead")
          if (thead) {
            let clonedThead = thead.cloneNode(true)
            renderedTable.insertBefore(clonedThead, renderedTable.firstChild)
          }
        }

        nodeAfter(node, limiter) {
          if (limiter && node === limiter) return
          let significantNode = this.nextSignificantNode(node)
          if (significantNode) return significantNode
          if (node.parentNode) {
            while ((node = node.parentNode)) {
              if (limiter && node === limiter) return
              significantNode = this.nextSignificantNode(node)
              if (significantNode) return significantNode
            }
          }
        }

        nextSignificantNode(sib) {
          while ((sib = sib.nextSibling)) { if (!this.isIgnorable(sib)) return sib }
          return null
        }

        isIgnorable(node) {
          return (
            (node.nodeType === 8)
            || ((node.nodeType === 3) && this.isAllWhitespace(node))
          )
        }

        isAllWhitespace(node) {
          return !(/[^\t\n\r ]/.test(node.textContent))
        }
      }

      // Paged.registerHandlers(RepeatTableHeadersHandler)

      console.log('[SessionIdProvider] Registering Paged.js handlers...');
      window.Paged.registerHandlers(PDFGenerationHandler);
      window.Paged.registerHandlers(RepeatTableHeadersHandler);

      // Validate container has content before running paged.js
      if (!container || !container.innerHTML || container.innerHTML.trim() === '') {
        console.error('[SessionIdProvider] Container is empty, cannot paginate');
        return;
      }

      console.log('[SessionIdProvider] Starting paged.js pagination...');

      // Run paged.js pagination
      let paged = new Paged.Previewer();

      let pagedViewerDiv = document.createElement('div');
      pagedViewerDiv.classList.add('preview-pane');
      pagedViewerDiv.dataset.id = 'previewPane';
      document.body.appendChild(pagedViewerDiv);
      console.log('this.pagedViewerDiv', this.pagedViewer);
      paged.preview(container, [], this.pagedViewer ? pagedViewerDiv : this.querySelector('.preview-pane')).then(async (flow) => {

        //dispatch customevent


        console.log('[SessionIdProvider] Pagination completed successfully');

        // Inject page numbers and repeated headers after pagination (skip hidden pages).
        const previewPane = this.pagedViewer ? pagedViewerDiv : this.querySelector('.preview-pane');
        if (previewPane) {
          const pageElements = Array.from(previewPane.querySelectorAll('.pagedjs_page'))
            .filter((pageEl) => pageEl.getAttribute('data-hidden-page') !== 'true' && pageEl.style.display !== 'none');

          const totalPages = pageElements.length;

          pageElements.forEach((pageEl, index) => {
            const pageNumber = index + 1;
            // Remove old absolute overlays if present.
            const staleOverlay = pageEl.querySelector('[data-manual-page-number]');
            if (staleOverlay) {
              staleOverlay.remove();
            }

            // Prefer paged.js bottom margin box to avoid z-index/content overlap.
            // Skip entirely when caller asked for no page numbers ('none').
            if (showPageNumbers) {
              const marginContent = pageEl.querySelector(
                `.pagedjs_margin-bottom-${pageNumberPosition} .pagedjs_margin-content`
              );
              if (marginContent) {
                const marginBox = marginContent.closest('.pagedjs_margin');
                if (marginBox) {
                  marginBox.classList.add('hasContent');
                  marginBox.style.visibility = 'visible';
                  marginBox.style.transform = 'none';
                }
                marginContent.textContent = `Page ${pageNumber} of ${totalPages}`;
                marginContent.style.width = '100%';
                marginContent.style.textAlign = pageNumberTextAlign;
                marginContent.style.fontSize = '10px';
                marginContent.style.color = '#444';
                marginContent.style.pointerEvents = 'none';
                marginContent.style.display = 'block';
              }
            }

            // Render repeated header as a direct child of paged.js's .pagedjs_margin-top
            // so it occupies the entire top margin band (above corner/left/center/right cells)
            // without relying on @top-center margin-box layout. The header is wrapped in the
            // original .docx-wrapper > section.docx ancestor chain so descendant selectors
            // from the docx-export <style> blocks keep matching the header content.
            if (repeatedHeaderTemplate?.html) {
              const topMarginBox = pageEl.querySelector('.pagedjs_margin-top');
              if (topMarginBox) {
                let headerSlot = topMarginBox.querySelector(':scope > [data-pdf-force-repeated-header="true"]');
                if (!headerSlot) {
                  headerSlot = document.createElement('div');
                  headerSlot.setAttribute('data-pdf-force-repeated-header', 'true');
                  topMarginBox.insertBefore(headerSlot, topMarginBox.firstChild);
                }
                const wrapperClass = repeatedHeaderTemplate.wrapperClassName || 'docx-wrapper';
                const sectionClass = repeatedHeaderTemplate.sectionClassName || 'docx';
                headerSlot.innerHTML = `
                  <div class="${wrapperClass}" data-pdf-force-repeated-wrapper="true">
                    <section class="${sectionClass}" data-pdf-force-repeated-section="true">
                      ${repeatedHeaderTemplate.html}
                    </section>
                  </div>
                `;

                headerSlot.style.position = 'absolute';
                headerSlot.style.inset = '0';
                headerSlot.style.width = '100%';
                headerSlot.style.maxWidth = '100%';
                headerSlot.style.boxSizing = 'border-box';
                headerSlot.style.pointerEvents = 'none';
                headerSlot.style.zIndex = '1';
                // Only moveable headers carry an absolute "top" offset that needs to be
                // re-created in the margin band. Non-moveable headers rely on the
                // section's own padding-top (and the header's own margin) for spacing.
                if (repeatedHeaderTemplate.hasMoveableTags) {
                  headerSlot.style.paddingTop = `${headerTopPx}px`;
                } else {
                  headerSlot.style.paddingTop = '';
                }

                topMarginBox.classList.add('hasContent');
                topMarginBox.style.position = 'relative';
                topMarginBox.style.visibility = 'visible';
                topMarginBox.style.display = 'block';
                topMarginBox.style.width = '100%';
                topMarginBox.style.maxWidth = '100%';
                topMarginBox.style.overflow = 'visible';

                const wrapperEl = headerSlot.querySelector('[data-pdf-force-repeated-wrapper="true"]');
                const sectionEl = headerSlot.querySelector('[data-pdf-force-repeated-section="true"]');
                const repeatedHeaderEl = headerSlot.querySelector('header');

                if (repeatedHeaderTemplate.hasMoveableTags) {
                  // Moveable header: section/wrapper styles must be neutralized because
                  // the header was authored with absolute placement inside the section.
                  if (wrapperEl) {
                    wrapperEl.style.padding = '0';
                    wrapperEl.style.margin = '0';
                    wrapperEl.style.background = 'transparent';
                    wrapperEl.style.width = '100%';
                    wrapperEl.style.maxWidth = '100%';
                    wrapperEl.style.boxSizing = 'border-box';
                    wrapperEl.style.position = 'relative';
                  }
                  if (sectionEl) {
                    sectionEl.style.padding = '0';
                    sectionEl.style.margin = '0';
                    sectionEl.style.minHeight = '0';
                    sectionEl.style.height = 'auto';
                    sectionEl.style.width = '100%';
                    sectionEl.style.maxWidth = '100%';
                    sectionEl.style.boxSizing = 'border-box';
                    sectionEl.style.position = 'relative';
                    sectionEl.style.background = 'transparent';
                    sectionEl.style.boxShadow = 'none';
                  }
                  if (repeatedHeaderEl) {
                    repeatedHeaderEl.style.position = 'relative';
                    repeatedHeaderEl.style.top = '0';
                    repeatedHeaderEl.style.left = '0';
                    repeatedHeaderEl.style.right = '0';
                    repeatedHeaderEl.style.transform = 'none';
                    repeatedHeaderEl.style.margin = '0';
                    repeatedHeaderEl.style.width = '100%';
                    repeatedHeaderEl.style.maxWidth = '100%';
                    repeatedHeaderEl.style.boxSizing = 'border-box';
                  }
                } else {
                  // Plain docx header: replicate the section's "page margins"
                  // (padding-top/left/right) on the cloned section so the repeated
                  // header lines up with the body content on every page. The header
                  // element itself is left untouched so its own padding/margin from
                  // the docx export render naturally.
                  const sectionPadding = repeatedHeaderTemplate.sectionPaddingPx
                    || { top: 0, left: 0, right: 0 };

                  if (wrapperEl) {
                    wrapperEl.style.padding = '0';
                    wrapperEl.style.margin = '0';
                    wrapperEl.style.width = '100%';
                    wrapperEl.style.maxWidth = '100%';
                    wrapperEl.style.boxSizing = 'border-box';
                    wrapperEl.style.background = 'transparent';
                    wrapperEl.style.boxShadow = 'none';
                  }
                  if (sectionEl) {
                    // Strip the original A4-sized section box; we only want it to
                    // act as a styling/selector ancestor for the header content.
                    sectionEl.style.minHeight = '0';
                    sectionEl.style.height = 'auto';
                    sectionEl.style.width = '100%';
                    sectionEl.style.maxWidth = '100%';
                    sectionEl.style.margin = '0';
                    sectionEl.style.boxSizing = 'border-box';
                    sectionEl.style.background = 'transparent';
                    sectionEl.style.boxShadow = 'none';
                    sectionEl.style.position = 'relative';
                    // Reapply the captured page-side paddings so the header is
                    // inset the same amount from the page edge as it was in the
                    // original docx layout.
                    sectionEl.style.paddingTop = `${sectionPadding.top}px`;
                    sectionEl.style.paddingLeft = PDF_PAGE_SIDE_MARGIN;
                    sectionEl.style.paddingRight = PDF_PAGE_SIDE_MARGIN;
                    sectionEl.style.paddingBottom = '0';
                  }
                }
              }
            }
          });

          this._tightenDocxPageMargins(previewPane);
        }

        // When this render came from a saved renderer payload (loaded
        // via loadAndRenderContentDocument with restamp flag set), the
        // signatureFields array contains completed signatures whose
        // signatureImage data URLs need to be re-stamped onto the
        // freshly-rendered pages. handleSignatureImage already does
        // this for live signing; we just replay it here per completed
        // field. Guarded by the flag so a normal first-time render
        // (signatureFields all `completed: false`) does nothing.
        if (this._restampSignaturesAfterRender) {
          this._restampSignaturesAfterRender = false;
          try {
            (this.signatureFields || [])
              .filter((f) => f && f.completed && f.signatureImage)
              .forEach((field) => this.placeSignatureOnPages(field));
          } catch (restampError) {
            console.warn('Failed to re-stamp saved signatures', restampError);
          }
        }

        this.loading = false;
        this.dispatchEvent(new CustomEvent('pagedjscompleted', { detail: { pagedView: pagedViewerDiv } }));
        // document.body.removeChild(pagedViewerDiv);
        //destroy paged Viewer
      }).catch(error => {
        this.logPdfJsError(error);

      });

    } catch (error) {
      console.error('[SessionIdProvider] Error in displayPDF:', error?.message || error);
      this.logPdfJsError(error);
    } finally {
      this.loading = false;
    }



  }

  preserveDocxSpacing(root) {
    if (!root) return;

    // docx-preview often encodes tab alignment as runs of normal spaces inside spans.
    // Convert these to non-breaking spaces so pagination/reflow doesn't collapse them.
    const spans = root.querySelectorAll('section.docx span');
    spans.forEach((span) => {
      if (!span || span.children.length > 0) return;
      const text = span.textContent;
      if (!text) return;
      if (/^[ \t]{2,}$/.test(text)) {
        span.textContent = text.replace(/ /g, '\u00A0').replace(/\t/g, '\u00A0\u00A0\u00A0\u00A0');
      }
    });
  }

  _tightenDocxPageMargins(root) {
    if (!root) return;

    const zeroHorizontalInset = (el) => {
      el.style.setProperty('padding-left', '0', 'important');
      el.style.setProperty('padding-right', '0', 'important');
      el.style.setProperty('margin-left', '0', 'important');
      el.style.setProperty('margin-right', '0', 'important');
    };

    root.querySelectorAll('.docx-wrapper').forEach((wrapper) => {
      zeroHorizontalInset(wrapper);
    });

    root.querySelectorAll('section.docx:not([data-pdf-force-repeated-section])').forEach((section) => {
      section.style.setProperty('padding-left', PDF_PAGE_SIDE_MARGIN, 'important');
      section.style.setProperty('padding-right', PDF_PAGE_SIDE_MARGIN, 'important');
      section.style.setProperty('margin-left', '0', 'important');
      section.style.setProperty('margin-right', '0', 'important');
      section.style.setProperty('width', '100%', 'important');
      section.style.setProperty('max-width', '100%', 'important');
      section.style.setProperty('box-sizing', 'border-box', 'important');
    });

    root.querySelectorAll('section.docx:not([data-pdf-force-repeated-section]) > article').forEach((article) => {
      zeroHorizontalInset(article);
      article.style.setProperty('width', '100%', 'important');
      article.style.setProperty('max-width', '100%', 'important');
      article.style.setProperty('box-sizing', 'border-box', 'important');
    });
  }


  logPdfJsError(e) {
    // Salesforce often proxies errors; these logs usually reveal the real message
    try { console.error('PdfForce Renderer error (string):', String(e)); } catch { }
    try { console.error('PdfForce Renderer error.message:', e?.message); } catch { }
    try { console.error('PdfForce Renderer error.name:', e?.name); } catch { }
    try { console.error('PdfForce Renderer error.stack:', e?.stack); } catch { }
    try { console.error('PdfForce Renderer error JSON:', JSON.stringify(e)); } catch { }
    try { console.error('PdfForce Renderer error keys:', Object.keys(e || {})); } catch { }
    try { console.error('PdfForce Renderer error cause:', e?.cause); } catch { }
  }



  handleCloseModal() {
    this.stopUiContainerManagerGuard();
    this.vfPageUrl = null;
  }

  startUiContainerManagerGuard() {
    this.applyUiContainerManagerGuard();
    if (this._uiContainerObserver || this._uiContainerGuardPollId || !document?.body) return;

    try {
      this._uiContainerObserver = new MutationObserver(() => {
        this.applyUiContainerManagerGuard();
      });
      this._uiContainerObserver.observe(document.body, {
        childList: true,
        subtree: true
      });
    } catch (e) {
      // Lightning Web Security blocks MutationObserver on shared elements like BODY.
      this._uiContainerObserver = null;
      this._uiContainerGuardPollId = setInterval(() => {
        this.applyUiContainerManagerGuard();
      }, 500);
    }
  }

  stopUiContainerManagerGuard() {
    if (this._uiContainerObserver) {
      this._uiContainerObserver.disconnect();
      this._uiContainerObserver = null;
    }
    if (this._uiContainerGuardPollId) {
      clearInterval(this._uiContainerGuardPollId);
      this._uiContainerGuardPollId = null;
    }
    this.restoreUiContainerManager();
  }

  applyUiContainerManagerGuard() {

    let overlays = Array.from(document.querySelectorAll('.DESKTOP.uiContainerManager'));
    overlays = overlays.length > 0 ? overlays : [];
    overlays.forEach((overlay) => {
      if (!overlay) return;
      if (!overlay.dataset.pdfRendererGuarded) {
        this._uiContainerManagerState.push({
          node: overlay,
          display: overlay.style.display,
          visibility: overlay.style.visibility,
          pointerEvents: overlay.style.pointerEvents,
          opacity: overlay.style.opacity,
          zIndex: overlay.style.zIndex
        });
        overlay.dataset.pdfRendererGuarded = 'true';
      }
      overlay.style.display = 'none';
      overlay.style.visibility = 'hidden';
      overlay.style.pointerEvents = 'none';
      overlay.style.opacity = '0';
      overlay.style.zIndex = '-9999';
    });
  }

  restoreUiContainerManager() {
    this._uiContainerManagerState.forEach((entry) => {
      const overlay = entry?.node;
      if (!overlay || !overlay.isConnected) return;
      overlay.style.display = entry.display ?? '';
      overlay.style.visibility = entry.visibility ?? '';
      overlay.style.pointerEvents = entry.pointerEvents ?? '';
      overlay.style.opacity = entry.opacity ?? '';
      overlay.style.zIndex = entry.zIndex ?? '';
      delete overlay.dataset.pdfRendererGuarded;
    });
    this._uiContainerManagerState = [];
  }




  // Flag set right before posting GENERATE_PDF to the VF iframe so that
  // the next PDF_GENERATED message coming back is routed to "attach to
  // record" instead of the legacy "show preview" code path. Reset to
  // false as soon as the message is consumed (in either direction).
  _pendingPdfAttachment = false;

  /**
   * Collects the live preview pane HTML PLUS every <style> tag in
   * document.head that drives the preview (docx-export styles cloned
   * during displayPDF + paged.js's Polisher-inserted styles) and
   * returns a single HTML string. Used by:
   *   - Save: persisted as the renderer's saved compiled HTML.
   *   - Submit: posted to the VF page so jsPDF/html2canvas renders it
   *     with the same fonts/layout the user saw on screen.
   *
   * Returns null when there is no preview pane on the DOM yet.
   */
  _buildCompiledHtmlForExport() {
    const previewPane = this.querySelector('.preview-pane');
    if (!previewPane) return null;

    // The visible preview is styled by <style> tags that live OUTSIDE
    // .preview-pane (in document.head). previewPane.innerHTML alone therefore
    // ships bare HTML, which is why a naive export looks unstyled. Collect
    // every style tag that could be feeding the preview:
    //
    //   - [data-pdfforce-style]          -> docx-export styles cloned in displayPDF
    //                                       and our @page / repeated-header rules
    //   - [data-pagedjs-inserted-styles] -> styles emitted by paged.js's Polisher
    //   - any other [data-pagedjs-*]     -> defensive: paged.js attribute names
    //                                       have varied across versions
    const headStyleNodes = Array.from(
      document.head.querySelectorAll('style')
    ).filter((node) => {
      const attrs = node.getAttributeNames();
      return attrs.some(
        (name) => name === 'data-pdfforce-style' || name.startsWith('data-pagedjs')
      );
    });

    const styleTagsHtml = headStyleNodes
      .map((node) => node.outerHTML)
      .join('\n');

    return `${styleTagsHtml}\n<style data-pdfforce-style="true" data-pdfforce-export-layout="true">${PDF_EXPORT_LAYOUT_STYLES}</style>\n${previewPane.innerHTML}`;
  }

  handleSubmitDocument() {
    if (!this._pdfAttachmentRecordId) {
      this._notifyUser(
        'Cannot submit',
        'A recordId or submit-record-id is required to attach the generated PDF.',
        'warning'
      );
      return;
    }

    if (!this._allSignaturesComplete) {
      this._notifyUser(
        'Signatures required',
        'Please complete all required signatures before submitting.',
        'warning'
      );
      return;
    }

    const htmlContent = this._buildCompiledHtmlForExport();
    if (!htmlContent) {
      this._notifyUser(
        'Nothing to submit',
        'The document has not finished rendering yet. Try again in a moment.',
        'warning'
      );
      return;
    }

    const iframe = this.querySelector('.iframe');
    if (!iframe || !iframe.contentWindow) {
      this._notifyUser(
        'Cannot submit',
        'PDF generator is not ready. Reload the component and try again.',
        'error'
      );
      return;
    }

    this._pendingPdfAttachment = true;
    this.loading = true;
    if (this.callingFromVf) {
      this.clearUserMessage();
    }

    const targetFileName = this.fileName
      ? `${this.fileName}-${Date.now()}.pdf`
      : `PDFForceDocument-${Date.now()}.pdf`;

    iframe.contentWindow.postMessage({
      type: 'GENERATE_PDF',
      htmlContent,
      fileName: targetFileName,
      attachToRecord: true
    }, '*');
  }

  /**
   * Creates a ContentVersion from the PDF data URI the VF page sent
   * back, links it to {submitRecordId} (falling back to {recordId}),
   * and notifies the outcome. Uses Apex createContentVersionFromBase64
   * so guest VF / Lightning Out does not depend on jsforce REST.
   *
   * Accepts:
   *   pdfData  - a `data:application/pdf;base64,...` URI emitted by
   *              jsPDF's pdf.output('datauristring'), OR a bare
   *              base64 string. Both shapes are normalized.
   *   fileName - desired file name (without extension is fine - we
   *              add `.pdf` if missing).
   */
  async _attachGeneratedPdfToRecord(pdfData, fileName) {
    const targetRecordId = this._pdfAttachmentRecordId;

    if (!targetRecordId) {
      this._notifyUser(
        'Attach failed',
        'No target record id is available for attaching the generated PDF.',
        'error'
      );
      return;
    }
    if (!pdfData) {
      this._notifyUser(
        'Attach failed',
        'No PDF payload was returned by the generator.',
        'error'
      );
      return;
    }


    try {
      const base64Payload = typeof pdfData === 'string' && pdfData.includes(',')
        ? pdfData.split(',')[1]
        : pdfData;

      const baseName = fileName
        || (this.fileName ? `${this.fileName}-${Date.now()}` : `PDFForceDocument-${Date.now()}`);
      const pathOnClient = /\.pdf$/i.test(baseName) ? baseName : `${baseName}.pdf`;

      await attachGeneratedPdf({
        recordId: targetRecordId,
        fileName: pathOnClient,
        base64Pdf: base64Payload
      });

      // Submit succeeded - the generated PDF is now the source of
      // truth on the record, so the in-progress saved HTML draft
      // (`PDFForceTemplate-<recordId> <templateId>`) is no longer
      // needed. Delete it best-effort; a cleanup failure must NOT
      // surface as a Submit failure since the PDF is already attached.
      if (this.recordId && this.templateId) {
        try {
          await deleteRendererTemplateDocument({
            recordId: this.recordId,
            templateId: this.templateId
          });
          this._savedRendererContentDocumentId = null;
        } catch (cleanupError) {
          console.warn('deleteRendererTemplateDocument failed after submit', cleanupError);
        }
      }

      this._notifyUser('Submitted', 'PDF attached successfully.', 'success');
      if(this.callingFromVf){
          this.handleFormSubmitted();
      }
    } catch (error) {
      console.error('attachGeneratedPdfToRecord error', error);
      this._notifyUser(
        'Attach failed',
        error?.body?.message || error?.message || 'Failed to attach PDF to record',
        'error'
      );
    }
  }

  @track showSignDocumentModal = false;
  @track signatureProgress = 0;
  @track unsignedSignatureFields = [];

  // signaturePOC.modalOpen must be a real boolean; use a getter so the
  // child receives `true` instead of an empty string from the attribute.
  get signaturePocModalOpen() {
    return true;
  }

  get currentSignatureField() {
    if (!this.signatureFields || this.signatureFields.length === 0) return null;
    return this.signatureFields.find(field => !field.completed) || null;
  }

  get hasCurrentSignatureField() {
    return !!this.currentSignatureField;
  }

  get currentSignatureLabel() {
    return this.currentSignatureField?.signatureValue || 'Signature';
  }

  get currentSignaturePosition() {
    return this.currentSignatureField?.signaturePosition || '';
  }

  get currentSignaturePage() {
    return this.currentSignatureField?.singaturePage || '';
  }

  get signedCount() {
    if (!this.signatureFields) return 0;
    return this.signatureFields.filter(f => f.completed).length;
  }

  get totalSignatureCount() {
    return this.signatureFields ? this.signatureFields.length : 0;
  }

  // True when every defined signature field has been signed. Templates
  // with no signature fields are treated as "complete" so Save/Submit
  // don't get blocked on documents that simply don't need signatures.
  get _allSignaturesComplete() {
    if (!this.signatureFields || this.signatureFields.length === 0) return true;
    return this.signatureFields.every((field) => field && field.completed);
  }

  // Returns the record id that Submit should attach the generated PDF
  // to: `submitRecordId` when provided, otherwise the renderer's own
  // `recordId`. Returns null when neither is set.
  get _pdfAttachmentRecordId() {
    return this.submitRecordId || this.recordId || null;
  }

  get currentSignatureNumber() {
    return Math.min(this.signedCount + 1, this.totalSignatureCount);
  }

  get signatureProgressLabel() {
    return `Signing ${this.currentSignatureNumber} of ${this.totalSignatureCount}`;
  }

  recalculateSignatureProgress() {
    if (!this.totalSignatureCount) {
      this.signatureProgress = 0;
      return;
    }
    this.signatureProgress = (this.signedCount / this.totalSignatureCount) * 100;
  }

  handleSignDocument() {
    this.userMessage = null;
    if (!this.signatureFields || this.signatureFields.length === 0) {
      return;
    }
    this.unsignedSignatureFields = this.signatureFields.filter(field => !field.completed);
    if (this.unsignedSignatureFields.length === 0) {
      return;
    }
    this.showSignDocumentModal = true;
    this.recalculateSignatureProgress();
  }


  handleSignDocumentSave() {
    // Persist signed fields back to caller / saving routine.
    this.showSignDocumentModal = false;
  }


  handleSignatureImage(event) {
    // signaturePOC now dispatches { image, metadata }. Fall back to a raw
    // dataURL string for backwards compatibility.
    const detail = event.detail || {};
    const signatureImage = typeof detail === 'string' ? detail : detail.image;
    const metadata = typeof detail === 'string' ? null : detail.metadata;
    if (!signatureImage) return;

    const currentIndex = this.signatureFields.findIndex(field => !field.completed);
    if (currentIndex === -1) return;

    // Reassign to a new array so LWC re-renders dependent getters.
    const updated = this.signatureFields.map((field, idx) => {
      if (idx !== currentIndex) return field;
      return {
        ...field,
        signatureImage,
        signerMetadata: metadata,
        signedAt: metadata?.timestamp || new Date().toISOString(),
        completed: true
      };
    });
    this.signatureFields = updated;
    this.unsignedSignatureFields = updated.filter(f => !f.completed);
    this.recalculateSignatureProgress();

    // Stamp the signature onto the rendered PDF pages.
    this.placeSignatureOnPages(updated[currentIndex]);

    // Reset capture state inside the signaturePOC for the next signature.
    const signaturePOC = this.refs?.signaturePOCComponent;
    if (signaturePOC && typeof signaturePOC.resetForNext === 'function') {
      signaturePOC.resetForNext();
    }

    // Auto-close once every signature has been captured.
    if (this.unsignedSignatureFields.length === 0) {
      this.showSignDocumentModal = false;
    }
  }

  /**
   * Inject the captured signature image onto the appropriate paged.js page(s).
   * Uses absolute positioning and disables selection / pointer events so the
   * stamp behaves like part of the rendered output.
   */
  placeSignatureOnPages(field) {
    if (!field || !field.signatureImage) return;

    const pages = this.findRenderedPages();
    if (!pages || pages.length === 0) return;

    let targetPages = [];
    const pagePref = (field.singaturePage || '').toLowerCase();
    if (pagePref === 'all pages') {
      targetPages = pages;
    } else {
      // Default: Last Page
      targetPages = [pages[pages.length - 1]];
    }

    targetPages.forEach((pageEl) => {
      this.stampSignatureOnPage(pageEl, field);
    });
  }

  findRenderedPages() {
    // Pages may live inside this component or, when paged-viewer mode is on,
    // they get appended to the parent's `.page-wrapper` (see pdfTemplateBuilder).
    let pages = this.querySelectorAll('.pagedjs_page');
    if (pages && pages.length) return Array.from(pages);
    pages = document.querySelectorAll('.pagedjs_page');
    return pages ? Array.from(pages) : [];
  }

  stampSignatureOnPage(pageEl, field) {
    if (!pageEl) return;

    // The pagebox represents the actual printable page bounds. Fall back to
    // the page itself if pagebox is not present.
    const host = pageEl.querySelector('.pagedjs_pagebox') || pageEl;
    if (!host) return;

    // Remove any prior stamp for this same field id (re-sign safety).
    const fieldKey = `signature-stamp-${field.id}`;
    const existing = host.querySelector(`[data-signature-stamp="${fieldKey}"]`);
    if (existing) existing.remove();

    // Ensure absolute positioning has a containing block.
    const computed = window.getComputedStyle(host);
    if (computed.position === 'static') {
      host.style.position = 'relative';
    }

    const wrapper = document.createElement('div');
    wrapper.dataset.signatureStamp = fieldKey;
    wrapper.setAttribute('contenteditable', 'false');
    wrapper.setAttribute('aria-hidden', 'true');

    const positionStyles = this.getSignaturePositionStyles(field.signaturePosition);
    Object.assign(wrapper.style, {
      position: 'absolute',
      zIndex: '50',
      pointerEvents: 'none',
      userSelect: 'none',
      webkitUserSelect: 'none',
      maxWidth: '160px',
      ...positionStyles
    });

    const img = document.createElement('img');
    img.src = field.signatureImage;
    img.alt = field.signatureValue || 'Signature';
    Object.assign(img.style, {
      display: 'block',
      maxWidth: '100%',
      maxHeight: '60px',
      height: 'auto',
      margin: '0 auto',
      pointerEvents: 'none',
      userSelect: 'none',
      webkitUserSelect: 'none'
    });
    img.setAttribute('draggable', 'false');
    wrapper.appendChild(img);

    // Underline below the signature image.
    const underline = document.createElement('div');
    Object.assign(underline.style, {
      borderTop: '1px solid #0b0f14',
      marginTop: '2px',
      width: '100%'
    });
    wrapper.appendChild(underline);

    if (field.signatureValue) {
      const label = document.createElement('div');
      label.textContent = field.signatureValue;
      Object.assign(label.style, {
        fontSize: '9px',
        color: '#333',
        marginTop: '2px',
        textAlign: 'center'
      });
      wrapper.appendChild(label);
    }

    if (field.auditTrail && field.signerMetadata) {
      const audit = document.createElement('div');
      const m = field.signerMetadata;
      const coords = m.geoLocationCoordinates;
      const latLongLine = coords && coords.latitude != null && coords.longitude != null
        ? `Lat/Long: ${Number(coords.latitude).toFixed(5)}, ${Number(coords.longitude).toFixed(5)}`
        : null;
      const lines = [
        m.userEmail ? `Signed by: ${m.userEmail}` : null,
        m.timestamp ? `At: ${new Date(m.timestamp).toLocaleString()}` : null,
        m.sourceIpAddress ? `IP: ${m.sourceIpAddress}` : null,
        latLongLine,
        (m.originatingCity || m.originatingCountry)
          ? `Location: ${[m.originatingCity, m.originatingCountry].filter(Boolean).join(', ')}`
          : null,
        m.deviceType || m.platformOs
          ? `Device: ${[m.deviceType, m.platformOs].filter(Boolean).join(' / ')}`
          : null
      ].filter(Boolean);
      audit.innerHTML = lines.map(l => `<div>${l}</div>`).join('');
      Object.assign(audit.style, {
        fontSize: '8px',
        color: '#555',
        marginTop: '2px',
        lineHeight: '1.2'
      });
      wrapper.appendChild(audit);
    }

    host.appendChild(wrapper);
  }

  getSignaturePositionStyles(position) {
    const offset = '24px';
    switch (position) {
      case 'bottomLeft':
        return { bottom: offset, left: offset };
      case 'bottomRight':
        return { bottom: offset, right: offset };
      case 'bottomCenter':
        return { bottom: offset, left: '50%', transform: 'translateX(-50%)' };
      case 'topLeft':
        return { top: offset, left: offset };
      case 'topRight':
        return { top: offset, right: offset };
      case 'topCenter':
        return { top: offset, left: '50%', transform: 'translateX(-50%)' };
      default:
        return { bottom: offset, right: offset };
    }
  }

  /**
   * Persists the rendered preview pane HTML (post-paged.js, with every
   * captured signature image already stamped onto each page) as a
   * ContentVersion linked to `this.recordId`.
   *
   * Storage strategy (single wire format, always):
   *   - JSON envelope:
   *       {
   *         kind: 'compiled',         // routes loader to _renderSavedCompiledHtml
   *         htmlContent: <string>,    // post-paged.js HTML with signature stamps baked in
   *         signatureFields: [...],   // restores UI completion state on reload
   *         inputJSON: <any>          // snapshot of merge data the user saved against
   *       }
   *   - Zipped with JSZip (single entry `payload.json`)
   *   - PathOnClient: `<Title>.json.zip`
   *
   * Rationale for switching off `.html` / `.html.gz`:
   *   The two load paths (Apex extension-filtered queries and the
   *   jsforce >= 3 MB fallback in pDFforceUtils.loadTemplateFromSalesforce)
   *   accept only `.json` / `.json.zip` / `.json.gz`. Saving as `.html*`
   *   silently broke the load path -- the file would be written but
   *   on next open the filter would skip it and the renderer would
   *   restart from the template instead of from the saved progress.
   *   Saving as `.json.zip` keeps the renderer in lockstep with the
   *   builder's wire format so every loader sees the same thing.
   *
   * Backward compatibility:
   *   handleDecompress still recognizes legacy `.html` / `.html.gz`
   *   payloads (kind: 'html' branch) AND legacy `.json` / `.json.gz`
   *   wrappers without `kind` (treated as old template wrapper path),
   *   so existing saved files keep loading after this change. New
   *   saves are tagged with `kind: 'compiled'` so the loader knows
   *   to skip paged.js and render the HTML verbatim.
   *
   * File identity (stable across versions for one record/template pair):
   *   Title        = `PDFForceTemplate-<recordId> <templateId>`
   *   PathOnClient = `<Title>.json.zip`
   *
   * On the FIRST save we create a fresh ContentVersion and link it to
   * `recordId` via ContentDocumentLink (createCDLRecords). On every
   * subsequent save we look up the existing ContentDocumentId by Title
   * (findRendererTemplateContentId) and create a new ContentVersion
   * with that ContentDocumentId set, which Salesforce treats as a new
   * version on the same file rather than a duplicate.
   *
   * ContentVersion create runs in Apex (createContentVersionFromBase64).
   *
   * Save is blocked (toast warning, no write, no PDF) until every
   * signature field has been completed.
   */
  async handleSaveDocument() {
    if (!this.recordId || !this.templateId) {
      this.userMessage = null;
      this._notifyUser(
        'Cannot save',
        'Both recordId and templateId are required to save the document.',
        'warning'
      );
      return;
    }
    // if (!this.sessionId || !this.vfRoot) {
    //   this._notifyUser(
    //     'Cannot save',
    //     'Salesforce session is not ready yet. Try again in a moment.',
    //     'warning'
    //   );
    //   return;
    // }
    if (!this._allSignaturesComplete) {
      this._notifyUser(
        'Signatures required',
        'Please complete all required signatures before saving.',
        'warning'
      );
      return;
    }

    this.loading = true;
    if (this.callingFromVf) {
      this.clearUserMessage();
    }
    const compiledHtml = this._buildCompiledHtmlForExport();
    if (!compiledHtml) {
      this._notifyUser(
        'Nothing to save',
        'The document has not finished rendering yet. Try again in a moment.',
        'warning'
      );
      this.loading = false;
      return;
    }


    try {
      // Build the JSON envelope the loader (loadAndRenderContentDocument
      // -> kind: 'compiled' branch) knows how to consume. `kind` is the
      // routing discriminator so legacy `.json` / `.json.gz` wrappers
      // (no kind field) still take the old paged.js path. inputJSON is
      // persisted for forward compat -- the loader currently ignores
      // it but having it in the file means we can light up "reload
      // against the saved merge data" later without a re-save.
      const envelope = {
        kind: 'compiled',
        htmlContent: compiledHtml,
        signatureFields: this.signatureFields || [],
        inputJSON: this.inputJSON || null,
      };
      const jsonString = JSON.stringify(envelope);
      const jsonByteSize = new Blob([jsonString]).size; // accurate UTF-8 byte count

      // Always ZIP -- single wire format keeps the renderer's saves
      // byte-compatible with the builder's saves, so every loader
      // (Apex extension filters + jsforce fallback) accepts them.
      // JSZip is cheap on payloads this size; the threshold-based
      // raw/gzip branch the renderer used to have was only needed
      // when we cared about avoiding compression cost for small
      // files -- ZIP/DEFLATE on a few MB of HTML is sub-second.
      const zipBytes = await this._zipPayloadAsync(jsonString, { level: 9 });
      const payloadBlob = new Blob([zipBytes]);
      const payloadByteSize = zipBytes.length;

      const dataUrl = await readUploadedFileAsDataUrl(payloadBlob);
      const base64Payload = dataUrl.includes(',') ? dataUrl.split(',')[1] : dataUrl;
      const fileExtension = '.json.zip';

      const title = `PDFForceTemplate-${this.recordId} ${this.templateId}`;
      const pathOnClient = `${title}${fileExtension}`;

      console.log(
        '[handleSaveDocument] HTML byte size:', new Blob([compiledHtml]).size,
        'json byte size:', jsonByteSize,
        'zip byte size:', payloadByteSize,
        'base64 size:', base64Payload.length,
        'extension:', fileExtension,
        'title:', title
      );

      // Refresh the ContentDocumentId in case another tab created the
      // file since this component loaded - prevents "duplicate Files"
      // when two saves race.
      let existingContentDocumentId = this._savedRendererContentDocumentId;
      if (!existingContentDocumentId) {
        try {
          existingContentDocumentId = await findRendererTemplateContentId({
            recordId: this.recordId,
            templateId: this.templateId
          });
        } catch (lookupError) {
          console.warn('findRendererTemplateContentId failed during save', lookupError);
        }
      }

      const contentVersionId = await createContentVersionFromBase64({
        title,
        pathOnClient,
        base64Payload,
        description: 'PDFForce renderer compiled HTML (json.zip envelope)',
        contentDocumentId: existingContentDocumentId || null
      });

      if (!existingContentDocumentId) {
        // First save for this record - link the new ContentVersion
        // to the record via ContentDocumentLink, then cache the
        // ContentDocumentId so future saves create a NEW VERSION
        // rather than another duplicate file.
        await createCDLRecords({
          cvIdsList: [contentVersionId],
          recordId: this.recordId
        });
        try {
          this._savedRendererContentDocumentId = await findRendererTemplateContentId({
            recordId: this.recordId,
            templateId: this.templateId
          });
        } catch (lookupError) {
          console.warn('Post-save findRendererTemplateContentId failed', lookupError);
        }
      }

      this._notifyUser(
        'Success',
        existingContentDocumentId ? 'Document version updated' : 'Document saved',
        'success'
      );
    } catch (error) {
      console.error('handleSaveDocument error', error);
      this._notifyUser(
        'Error',
        error?.body?.message || error?.message || 'Failed to save document',
        'error'
      );
    } finally {
      this.loading = false;
    }
  }

}