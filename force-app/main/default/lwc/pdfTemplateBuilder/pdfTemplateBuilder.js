/* eslint-disable radix */
/* eslint-disable @lwc/lwc/no-inner-html */
/* eslint-disable @lwc/lwc/no-async-operation */
/* eslint-disable no-undef */
import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NameField from '@salesforce/schema/PDFforceConfig__c.Name';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import DOCXPreview from '@salesforce/resourceUrl/DOCXPreview';
import DOCXPreview2 from '@salesforce/resourceUrl/DOCXPreview2';
import PAKO_JS from '@salesforce/resourceUrl/pako';
import LOADASH from '@salesforce/resourceUrl/LOADASH';
import PAGED from '@salesforce/resourceUrl/PAGED';
import MOVEABLE_JS from '@salesforce/resourceUrl/MOVEABLE_JS';
import JZIP from '@salesforce/resourceUrl/JZIP';
import jsforcescript from '@salesforce/resourceUrl/jsforcescript';
import createCDLRecords from '@salesforce/apex/PDFforceController.createCDLRecords';
import getTemplateVersions from '@salesforce/apex/PDFforceController.getTemplateVersions';
import loadTemplateJSON from '@salesforce/apex/PDFforceController.loadTemplateJSON';
import getUserSessionId from '@salesforce/apex/PDFforceController.getUserSessionId';
import getVFPageUrl from '@salesforce/apex/PDFforceController.getVFPageUrl';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import HANDLEBARSJS from '@salesforce/resourceUrl/HANDLEBARSJS';
import CODEMIRROR from '@salesforce/resourceUrl/CODEMIRROR';
import getContentVersionId from '@salesforce/apex/PDFforceController.getContentVersionId';
import { NavigationMixin } from "lightning/navigation";
import { loadTemplateFromSalesforce, readUploadedFileAsDataUrl } from 'c/pDFforceUtils';



const FIELDS = ['PDFforceConfig__c.Name', 'PDFforceConfig__c.Active_Version__c', 'PDFforceConfig__c.LastModifiedDate']

export default class PdfTemplateBuilder extends NavigationMixin(LightningElement) {

  static renderMode = 'light';
  @track sessionId;
  @track loading = false;
  @track signatureFields = [];

  @api recordId;
  @track pages = [];
  docxLib; // Reference to docx-preview-sync library (DOCXPreview2)
  docxLibAsync; // Reference to docx-preview library (DOCXPreview) for font extraction
  selectedElement = null; // Reference to currently selected element
  @track elementEditor = false; // Enable element editor (moveable)
  @track stackEditor = false; // Enable stack editor (sortable)
  @track currentTemplateVersion = false;
  _jsonParseTimer;
  @track template = null;
  @track jsonErrorMessage = '';
  cmJsonInstance = null;
  _cmJsonInitialized = false;
  _codeMirrorLoaded = false;
  @track pagedViewer = false;




  @track OrignalHtmlContent = '';

  /**
   * Configurable section context menu options.
   *
   * Shape:
   *  - id: string (optional; falls back to action)
   *  - label: string (required)
   *  - action: string (required)
   *  - disabled: boolean (optional)
   *
   * Handling:
   *  - Internal routing can live in `handleSectionContextMenuItemClick`
   *  - External routing is via `sectionmenuaction` CustomEvent
   */
  @api sectionContextMenuItems = [
    { id: 'log', label: 'Log action', action: 'log' }
  ];

  /**
   * Configurable element context menu options (right-click on selectable elements).
   *
   * Shape:
   *  - id: string (optional; falls back to action)
   *  - label: string (required)
   *  - action: string (required)
   *  - disabled: boolean (optional)
   *
   * Handling:
   *  - External routing is via `elementmenuaction` CustomEvent
   *  - detail: { action, element, sectionEl, clientX, clientY }
   */
  @api elementContextMenuItems = [
    { id: 'editElement', label: 'Edit Element', action: 'editElement' },
    { id: 'Insert Page Break Before', label: 'Insert Page Break Before', action: 'insertPageBreakBefore' },
    { id: 'Move Element', label: 'Resize Element', action: 'moveElement' },
    { id: 'Delete Element', label: 'Delete Element', action: 'deleteElement' },
    
  ];



  components = [
    { id: 'image', label: 'Image', icon: 'doctype:image' },
  ];

  _activeSectionEl;
  _sectionMenuOpen = false;
  _sectionMenuClientX = 0;
  _sectionMenuClientY = 0;

  _activeElementEl;
  _activeElementSectionEl;
  _elementMenuOpen = false;
  _elementMenuClientX = 0;
  _elementMenuClientY = 0;

  @track showEditElementModal = false;
  @track editElementHtml = '';
  cmHtmlInstance = null;
  _cmHtmlDragBlocker = null;
  _cmHtmlInitialized = false;
  _htmlModeLoaded = false;

  _onGlobalKeyDown;
  _onGlobalScrollOrResize;

  @track _moveableInstance = null;
  @track _moveableTarget = null;
  @track _moveableContainer = null;


  @track cancelOperationLabel = 'Cancel'


  @track signaturePositionOptions = [
    { id: 1, value: 'bottomLeft', label: 'Bottom Left' },
    { id: 2, value: 'bottomRight', label: 'Bottom Right' },
    { id: 3, value: 'bottomCenter', label: 'Bottom Center' },
    { id: 4, value: 'topLeft', label: 'Top Left' },
    { id: 5, value: 'topRight', label: 'Top Right' },
    { id: 6, value: 'topCenter', label: 'Top Center' }
  ];




  @track currentSelectedTemplateVersion = null;
  @track currentContentVersion = null;
  @track versionsFetchedFromServer = 0;
  @track disableSaveButton = true;


  get renderLabel() {
    return this.renderer ? 'Final Render' : 'Bare Document';
  }


  //i want to use lds to get current Record id and Name field
  @wire(getRecord, {
    recordId: "$recordId",
    fields: FIELDS,
  })
  record;

  @track templateVersions = [];


  get showUploadButton() {
    return !this.pages.length ? true : false;
  }

  get showActivateButton() {
    return this.pages.length ? true : false;
  }


  get templateTitle() {
    return this.currentContentVersion ? this.currentContentVersion.Title : 'No Template Found';
  }

  //Global Template tag to check if template is uploaded or not
  get templateStage() {
    return (this.currentContentVersion || !this.pagedViewer) ? false : true
  }





  connectedCallback() {
    this.loading = true;
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
    // Add global click handler for deselection


    this._onGlobalKeyDown = (evt) => {
      if (evt.key === 'Escape') {
        if (this._sectionMenuOpen) this.hideSectionContextMenu();
        if (this._elementMenuOpen) this.hideElementContextMenu();
        if (this._moveableInstance) this.destroyMoveableInstance();
      }
    };
    this._onGlobalScrollOrResize = () => {
      if (this._sectionMenuOpen) this.hideSectionContextMenu();
      if (this._elementMenuOpen) this.hideElementContextMenu();
    };

    window.addEventListener('keydown', this._onGlobalKeyDown, true);
    window.addEventListener('scroll', this._onGlobalScrollOrResize, true);
    window.addEventListener('resize', this._onGlobalScrollOrResize, true);



    getTemplateVersions({ recordId: this.recordId }).then(async (result) => {
      this.versionsFetchedFromServer = result.length;
      if (result.length > 0) {
        this.currentTemplateVersion = true;
        this.loadTemplateVersion(result[0].ContentDocumentId);
        this.disableSaveButton = false;
      } else {
        this.disableSaveButton = true;
        this.loading = false;
      }
    }).catch(error => {
      console.error('Error getting template versions:', JSON.stringify(error));
      this.loading = false;
    });


    // Load All the the scripts
    Promise.all([
      loadScript(this, DOCXPreview + '/DOCXPreview/jszip.min.js'),
      loadScript(this, DOCXPreview + '/DOCXPreview/tiff.min.js'),
      loadScript(this, LOADASH),
      loadScript(this, HANDLEBARSJS),
      loadScript(this, MOVEABLE_JS),
      loadScript(this, PAGED),
      loadScript(this, jsforcescript),
      loadScript(this, PAKO_JS),
      loadScript(this, JZIP),
    ])
      // Load CodeMirror (required for JSON editor)
      .then(() => loadStyle(this, CODEMIRROR + '/codemirror.css'))
      .then(() => loadScript(this, CODEMIRROR + '/codemirror.js'))
      .then(() =>
        Promise.all([
          loadScript(this, CODEMIRROR + '/javascript.js'),
          loadScript(this, CODEMIRROR + '/matchbrackets.js'),
          loadScript(this, CODEMIRROR + '/closebrackets.js'),
          loadScript(this, CODEMIRROR + '/active-line.js')
        ])
      )
      .then(() => {
        this._codeMirrorLoaded = true;
        // Step 1: Load DOCXPreview (docx-preview) first to capture renderAsync for font extraction
        return loadScript(this, DOCXPreview + '/DOCXPreview/docx-preview.min.js');
      })
      .then(() => {
        // Step 2: Store reference to the entire docx object before DOCXPreview2 overwrites window.docx
        // Create a deep copy or store reference to the object with renderAsync
        if (window.docx && typeof window.docx.renderAsync === 'function') {
          // Store the entire object reference (both libraries use same window.docx, so we capture it before overwrite)
          this.docxLibAsync = window.docx;
        }
        // Step 3: Load DOCXPreview2 (docx-preview-sync) which will overwrite window.docx
        return loadScript(this, DOCXPreview2);
      })
      .then(() => {
        // Step 4: Store reference to the sync library (now in window.docx)
        this.docxLib = window.docx;

      })
      .catch((error) => {
        // If CodeMirror fails to load, JSON editor will stay as a plain textarea.
        // Log the error so it's easy to spot in browser devtools.
        // eslint-disable-next-line no-console
        console.error('[pdfTemplateBuilder] script/style load failed', error);
        this.loading = false;
      });

  }

  handleBack() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: {
        objectApiName: 'PDFforceConfig__c',
        actionName: 'list',
      }
    });
  }

  renderedCallback() {
    // Initialize CodeMirror JSON editor once scripts are loaded and DOM is ready.
    if (this._cmJsonInitialized) {
      // Keep disabled state in sync after rerenders/content load.
      this.applyJsonEditorDisabledState();
      // Initialize HTML editor when Edit Element modal is shown (must run even on early return)
      if (this.showEditElementModal) {
        requestAnimationFrame(() => this.initEditElementCodeMirror());
      }
      return;
    }
    if (!this._codeMirrorLoaded) return;
    if (!window.CodeMirror) return;

    const ta = this.querySelector('textarea[data-id="jsonTextarea"]');
    if (!ta) return;

    this.cmJsonInstance = window.CodeMirror.fromTextArea(ta, {
      mode: { name: 'javascript', json: true },
      lineNumbers: true,
      lineWrapping: true,
      indentUnit: 2,
      tabSize: 2,
      autoCloseBrackets: true,
      matchBrackets: true,
      gutters: ['CodeMirror-linenumbers'],
      lineNumberFormatter: (line) => line,
      firstLineNumber: 1,
      showCursorWhenSelecting: true,
      // Disable JSON editing until document content is loaded.
      readOnly: this.contentNotLoaded ? 'nocursor' : false
    });

    this.cmJsonInstance.setValue(this.jsonText || '{ }');

    // Handle change events
    this.cmJsonInstance.on('change', () => {
      const value = this.cmJsonInstance.getValue();
      this.handleJsonTextChange(value);
    });

    // Handle paste events to auto-format JSON
    this.cmJsonInstance.on('paste', (cm, e) => {
      // Small delay to let paste complete, then check and format
      setTimeout(() => {
        const pastedText = this.cmJsonInstance.getValue();
        if (pastedText && pastedText.trim()) {
          try {
            // Try to parse and format the pasted JSON
            const parsed = JSON.parse(pastedText);
            const formatted = JSON.stringify(parsed, null, 2);
            if (formatted !== pastedText) {
              // Only format if it's different (not already formatted)
              this.cmJsonInstance.setValue(formatted);
              this.handleJsonTextChange(formatted);
            }
          } catch (e) {
            // If parsing fails, validate and show error
            const lineNumber = this.extractLineNumberFromError(e);
            this.reportValidityCheck(e?.message || 'Invalid JSON pasted.', lineNumber);
          }
        }
      }, 100);
    });

    // Update textarea validity when CodeMirror changes
    this.cmJsonInstance.on('change', () => {
      this.updateTextareaValidity();
    });

    this._cmJsonInitialized = true;
    this.applyJsonEditorDisabledState();

    // Initialize HTML editor when Edit Element modal is shown
    if (this.showEditElementModal) {
      requestAnimationFrame(() => this.initEditElementCodeMirror());
    }
  }




  addSignature() {
    console.log('coming to addSignature', this.signatureFields);
    if (!this.signatureFields || !this.signatureFields.length) this.signatureFields = [];
    this.signatureFields.push({
      id: this.signatureFields.length + 1,
      signatureValue: '',
      signaturePosition: '',
      auditTrail: false,
      singaturePage: 'Last Page'
    });
  }

  @track signaturePageOptions = [
    { id: 1, value: 'Last Page', label: 'Last Page' },
    { id: 2, value: 'All Pages', label: 'All Pages' }
  ];

  removeSignature(event) {
    let currentIndex = parseInt(event.currentTarget.dataset.index) - 1;
    this.signatureFields.splice(currentIndex, 1);
  }


  handleSignatureValueChange(event) {
    let currentName = event.currentTarget.dataset.name;
    let currentValue = currentName === 'auditTrail' ? event.target.checked : event.target.value;
    let currentIndex = parseInt(event.currentTarget.dataset.index) - 1;
    this.signatureFields[currentIndex][currentName] = currentValue;
    console.log('signatureFields', this.signatureFields);
  }

  /**
   * Initialize CodeMirror for the Edit Element modal when it is shown.
   */
  initEditElementCodeMirror(forceReinit = false) {
    if (!this.showEditElementModal || !window.CodeMirror) return;
    const ta = this.querySelector('textarea[data-id="htmlElementTextarea"]');
    if (!ta) return;

    if (this.cmHtmlInstance && forceReinit) {
      try {
        this.cmHtmlInstance.toTextArea();
      } catch (e) { /* no-op */ }
      this.cmHtmlInstance = null;
      this._cmHtmlInitialized = false;
    }

    if (this._cmHtmlInitialized && this.cmHtmlInstance && !forceReinit) {
      this.cmHtmlInstance.setValue(this.editElementHtml || '');
      this.cmHtmlInstance.refresh();
      return;
    }

    const mode = window.CodeMirror.modes.htmlmixed ? 'htmlmixed' : 'xml';
    this.cmHtmlInstance = window.CodeMirror.fromTextArea(ta, {
      mode,
      lineNumbers: true,
      lineWrapping: true,
      indentUnit: 2,
      tabSize: 2,
      matchBrackets: true,
      gutters: ['CodeMirror-linenumbers'],
      lineNumberFormatter: (line) => line,
      firstLineNumber: 1,
      showCursorWhenSelecting: true,
      dragDrop: false,
      readOnly: false
    });
    this.cmHtmlInstance.setValue(this.editElementHtml || '');
    this.cmHtmlInstance.refresh();

    const wrapper = this.cmHtmlInstance.getWrapperElement?.();
    if (wrapper) {
      wrapper.setAttribute('draggable', 'false');
      const blockDrag = (evt) => {
        evt.preventDefault();
        evt.stopPropagation();
      };
      wrapper.addEventListener('dragstart', blockDrag, true);
      wrapper.addEventListener('dragover', blockDrag, true);
      wrapper.addEventListener('drop', blockDrag, true);
      this._cmHtmlDragBlocker = { wrapper, blockDrag };
    }
    this._cmHtmlInitialized = true;
  }

  get jsonEditorHostClass() {
    return `json-editor-host${this.jsonErrorMessage ? ' is-invalid' : ''}${this.contentNotLoaded ? ' is-disabled' : ''}`;
  }

  get hasJsonError() {
    return !!this.jsonErrorMessage;
  }

  get jsonErrorDescribedBy() {
    return this.jsonErrorMessage ? 'json-error-message' : '';
  }

  get disableFormatButton() {
    return this.contentNotLoaded || !this.jsonText || this.jsonText.trim() === '';
  }

  applyJsonEditorDisabledState() {
    const disabled = !!this.contentNotLoaded;

    // Underlying textarea (in case CodeMirror isn't initialized yet)
    const ta = this.querySelector('textarea[data-id="jsonTextarea"]');
    if (ta) {
      ta.disabled = disabled;
      ta.setAttribute('aria-disabled', disabled ? 'true' : 'false');
    }

    // CodeMirror editor
    if (this.cmJsonInstance) {
      try {
        this.cmJsonInstance.setOption('readOnly', disabled ? 'nocursor' : false);
        const wrapper = this.cmJsonInstance.getWrapperElement?.();
        if (wrapper) {
          wrapper.classList.toggle('cm-readonly', disabled);
        }
      } catch (e) {
        // no-op
      }
    }

    // Host styling
    const host = this.querySelector('[data-id="jsonEditorHost"]');
    if (host) {
      host.classList.toggle('is-disabled', disabled);
    }
  }

  reportValidityCheck(message, lineNumber = null) {
    // Surface error close to the JSON editor and mark it visually invalid.
    this.jsonErrorMessage = message || '';
    this.jsonErrorLine = lineNumber;

    // Update textarea validity for HTML5 validation
    this.updateTextareaValidity();

    try {
      if (this.cmJsonInstance && this.jsonErrorMessage) {
        this.cmJsonInstance.focus();
        // Highlight error line if line number is available
        if (lineNumber && lineNumber > 0) {
          const line = lineNumber - 1; // CodeMirror uses 0-based line numbers
          this.cmJsonInstance.addLineClass(line, 'background', 'error-line');

          // Also highlight the line number in the gutter
          const lineElement = this.cmJsonInstance.getLineHandle(line);
          if (lineElement) {
            const gutterElement = this.cmJsonInstance.display.gutters.querySelector(`.CodeMirror-linenumber[data-line="${lineNumber}"]`);
            if (!gutterElement) {
              // Find line number element by position
              const lineEl = this.cmJsonInstance.getLineHandle(line);
              if (lineEl && this.cmJsonInstance.display.gutters) {
                const lineNumbers = this.cmJsonInstance.display.gutters.querySelectorAll('.CodeMirror-linenumber');
                if (lineNumbers[line]) {
                  lineNumbers[line].classList.add('error-line-number');
                  // Remove class after 5 seconds
                  setTimeout(() => {
                    if (lineNumbers[line]) {
                      lineNumbers[line].classList.remove('error-line-number');
                    }
                  }, 5000);
                }
              }
            }
          }

          // Only jump/scroll if the error is NOT on line 1.
          // For line 1 errors, keep the user's cursor where it is (no disruptive jumps).
          if (lineNumber > 1) {
            this.cmJsonInstance.scrollIntoView({ line: line, ch: 0 }, 100);
          }
          // Remove error class after 5 seconds
          setTimeout(() => {
            if (this.cmJsonInstance) {
              this.cmJsonInstance.removeLineClass(line, 'background', 'error-line');
            }
          }, 5000);
        }
      }
    } catch (e) {
      // no-op
    }
  }

  updateTextareaValidity() {
    // Update the underlying textarea for HTML5 validation
    const ta = this.querySelector('textarea[data-id="jsonTextarea"]');
    if (ta) {
      if (this.jsonErrorMessage) {
        ta.setAttribute('aria-invalid', 'true');
        ta.setCustomValidity(this.jsonErrorMessage);
      } else {
        ta.setAttribute('aria-invalid', 'false');
        ta.setCustomValidity('');
      }
      // Trigger validation check
      if (ta.reportValidity) {
        ta.reportValidity();
      }
    }
  }

  clearJsonValidity() {
    this.jsonErrorMessage = '';
    this.jsonErrorLine = null;
    // Remove any error line classes
    if (this.cmJsonInstance) {
      try {
        for (let i = 0; i < this.cmJsonInstance.lineCount(); i++) {
          this.cmJsonInstance.removeLineClass(i, 'background', 'error-line');
        }
        // Remove error classes from line numbers
        if (this.cmJsonInstance.display && this.cmJsonInstance.display.gutters) {
          const lineNumbers = this.cmJsonInstance.display.gutters.querySelectorAll('.CodeMirror-linenumber.error-line-number');
          lineNumbers.forEach(ln => ln.classList.remove('error-line-number'));
        }
      } catch (e) {
        // no-op
      }
    }
    // Update textarea validity
    this.updateTextareaValidity();
  }

  formatJson() {
    const raw = (this.cmJsonInstance ? this.cmJsonInstance.getValue() : this.jsonText) || '';
    if (!raw || raw.trim() === '') {
      this.reportValidityCheck('JSON input is empty.');
      return;
    }

    try {
      const parsed = JSON.parse(raw || '{}');
      const formatted = JSON.stringify(parsed, null, 2);
      this.clearJsonValidity();
      this.jsonText = formatted;
      if (this.cmJsonInstance) {
        // Save cursor position before formatting
        const cursor = this.cmJsonInstance.getCursor();
        this.cmJsonInstance.setValue(formatted);
        // Try to restore cursor position, or move to top
        try {
          const lineCount = this.cmJsonInstance.lineCount();
          const newLine = Math.min(cursor.line, lineCount - 1);
          const newCh = Math.min(cursor.ch, this.cmJsonInstance.getLine(newLine).length);
          this.cmJsonInstance.setCursor({ line: newLine, ch: newCh });
        } catch (e) {
          // If cursor restoration fails, move to top
          this.cmJsonInstance.setCursor(0, 0);
        }
        // Scroll to cursor
        this.cmJsonInstance.scrollIntoView(this.cmJsonInstance.getCursor(), 100);
      }
      this.handleJsonTextChange(formatted);
    } catch (e) {
      const lineNumber = this.extractLineNumberFromError(e);
      this.reportValidityCheck(e?.message || 'Invalid JSON.', lineNumber);
    }
  }

  extractLineNumberFromError(error) {
    if (!error || !error.message) return null;

    const message = error.message;
    const text = this.cmJsonInstance ? this.cmJsonInstance.getValue() : this.jsonText;
    if (!text) return null;

    // Try to extract line number directly from error message
    // Formats: "Unexpected token at line X", "at line X column Y", etc.
    const lineMatch = message.match(/line\s+(\d+)/i) ||
      message.match(/at\s+line\s+(\d+)/i);

    if (lineMatch && lineMatch[1]) {
      return parseInt(lineMatch[1], 10);
    }

    // Try to calculate line number from character position
    const posMatch = message.match(/position\s+(\d+)/i) ||
      message.match(/at\s+position\s+(\d+)/i) ||
      message.match(/column\s+(\d+)/i);

    if (posMatch && posMatch[1]) {
      const pos = parseInt(posMatch[1], 10);
      // Calculate line number from character position
      const lines = text.substring(0, Math.min(pos, text.length)).split('\n');
      return Math.max(1, lines.length);
    }

    // Try to find error position by parsing JSON incrementally
    // This helps identify where JSON.parse fails
    try {
      let errorPos = -1;
      // Try parsing from start, increasing length until error
      for (let i = 1; i <= text.length; i++) {
        try {
          JSON.parse(text.substring(0, i));
        } catch (e) {
          // Found the error position
          errorPos = i - 1;
          break;
        }
      }

      if (errorPos >= 0) {
        const lines = text.substring(0, errorPos).split('\n');
        return Math.max(1, lines.length);
      }
    } catch (e) {
      // Fallback to pattern matching
    }

    // Fallback: try to find the error location by pattern matching
    if (message.includes('Unexpected token') || message.includes('Expected') || message.includes('Unexpected end')) {
      // Look for common JSON error patterns in the text
      const errorPatterns = [
        /,\s*[,}]/,  // Trailing comma
        /:\s*[,}]/,  // Missing value
        /[^\\]"[^"]*$/,  // Unterminated string
        /{[^}]*$/,  // Unterminated object
        /\[[^\]]*$/,  // Unterminated array
      ];

      const lines = text.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        for (const pattern of errorPatterns) {
          if (pattern.test(line)) {
            return i + 1;
          }
        }
      }

      // If no pattern matches, return the line with the most likely error
      // (usually near syntax issues like unmatched brackets)
      let openBraces = 0;
      let openBrackets = 0;
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        for (const char of line) {
          if (char === '{') openBraces++;
          if (char === '}') openBraces--;
          if (char === '[') openBrackets++;
          if (char === ']') openBrackets--;
        }
        // If we have unmatched brackets, this might be where the error is
        if (openBraces < 0 || openBrackets < 0) {
          return i + 1;
        }
      }
    }

    return null;
  }

  handleJsonTextChange(nextText) {
    this.jsonText = nextText;

    // Debounce parsing so typing stays smooth.
    if (this._jsonParseTimer) {
      window.clearTimeout(this._jsonParseTimer);
    }

    this._jsonParseTimer = window.setTimeout(() => {
      const raw = (this.jsonText || '').trim();

      // Common foot-gun: pasting HTML/Handlebars template into the JSON editor.
      if (raw && (raw.startsWith('<') || raw.includes('</') || raw.includes('<span') || raw.includes('<div'))) {
        this.reportValidityCheck(
          'The JSON box expects JSON (example: {"name":"Acme"}). It looks like you pasted HTML/Handlebars template content.'
        );
        return;
      }

      try {
        const parsed = JSON.parse(this.jsonText || '{}');
        this.jsonData = parsed;
        this.clearJsonValidity();

        // Keep existing behavior (user re-enabled): apply template to canvas when possible.
        if (this.template && typeof this.template === 'function') {
          this.registerImgHelpersFromData(this.jsonData).then(() => {
            this.querySelector('.docx-wrapper').innerHTML = this.template(this.jsonData);
          });
        }
      } catch (e) {
        const lineNumber = this.extractLineNumberFromError(e);
        this.reportValidityCheck(e?.message || 'Please enter valid JSON.', lineNumber);
      }
    }, 300);
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


  async loadTemplateVersion(contentDocumentId) {
    this.loading = true;
    try {
      let conn = new jsforce.Connection({
        serverUrl: this.vfRoot,
        sessionId: await getUserSessionId()
      });

      // Strategy:
      //   1) Small files (< 3 MB) come back from Apex (loadTemplateJSON) as
      //      { versionData: <base64>, contentVersion: <CV metadata> }.
      //      Single round-trip, cheap.
      //   2) Larger files would blow the Apex heap, so versionData is null
      //      and we fall back to fetching VersionData directly via jsforce.
      //      That path returns rawData as a Uint8Array of gzip bytes plus
      //      a stringified contentVersion record.
      //
      // We always need the ContentVersion metadata (Id, Title,
      // ContentDocumentId) - saveTemplate uses it to decide between
      // creating a new version on the existing ContentDocument vs creating
      // a brand-new ContentDocument.
      //
      // handleDecompress accepts both shapes (base64 string and Uint8Array)
      // and normalizes them before calling pako.ungzip.
      //
      // NOTE: @AuraEnabled Apex methods MUST be called from LWC with a single
      // object of named params - calling positionally produces a 500 with
      // "ServerServiceImpl::unwrapAction Class Cast Exception".
      const apexResult = await loadTemplateJSON({
        template: contentDocumentId,
        recordId: this.recordId
      });
      let rawTemplate = apexResult?.versionData;

      let contentVersionMeta = apexResult?.contentVersion || null;
      console.log('contentVersionMeta', JSON.stringify(apexResult));
      if (!rawTemplate) {
        console.log('[loadTemplateVersion] file too large for Apex, falling back to jsforce');
        const fallback = await loadTemplateFromSalesforce(contentDocumentId, conn);
        if (fallback?.error) {
          console.error('loadTemplateFromSalesforce error', fallback.error);
          this.showToastMessage('Error', 'Failed to load template', 'error');
          this.loading = false;
          return;
        }
        rawTemplate = fallback?.rawData;
        // Apex already gave us metadata; only use the fallback's record if
        // we didn't get one from Apex (shouldn't happen, but be safe).
        if (!contentVersionMeta && fallback?.contentVersion) {
          try {
            contentVersionMeta = JSON.parse(fallback.contentVersion);
          } catch (e) {
            console.warn('Could not parse fallback contentVersion JSON', e);
          }
        }
      }

      const decompressed = await this.handleDecompress(rawTemplate);
      console.log('decompressed', decompressed);
      if (!decompressed) {
        this.showToastMessage('Error', 'Failed to decompress template', 'error');
        this.loading = false;
        return;
      }

      if (contentVersionMeta) {
        this.currentContentVersion = contentVersionMeta;
      }
      this.OrignalHtmlContent = decompressed.htmlContent;
      this.signatureFields = decompressed.signatureFields || [];


      // Wait for DOM to render pages, then populate with HTML content
      requestAnimationFrame(() => {
        let currentPage = this.querySelector('.page-wrapper');
        if (currentPage) {
          // Wipe first: insertAdjacentHTML('beforeend', ...) APPENDS. If the
          // wrapper already has content from a prior load/toggle, the entire
          // document would be duplicated and OrignalHtmlContent re-snapshotted
          // at 2x, 3x... size. replaceChildren() is the cheap, safe reset.
          currentPage.replaceChildren();
          currentPage.insertAdjacentHTML('beforeend', decompressed.htmlContent);

          // Wait one more frame to ensure DOM is fully updated
          requestAnimationFrame(() => {
            this.handleBarsCompileUtility(currentPage.querySelector('.docx-wrapper').innerHTML);

            currentPage.querySelector('.docx-wrapper').innerHTML = this.template({});

            requestAnimationFrame(() => {
              currentPage.querySelectorAll('section.docx').forEach((section) => {
                section.classList.add('canvas-page');
                // const article = section.querySelector('article');
                // if (article) this.makeArticleChildrenSelectable(article, section);
              });
              this.initSortableForSections();
              this.initComponentsSortable();
            });
          });
        }
      });

      this.loading = false;
      this.contentNotLoaded = false;
    } catch (error) {
      console.error('Error getting content version:', error);
      this.showToastMessage('Error', `Failed to load template version: ${error?.message || 'Unknown error'}`, 'error');
      this.loading = false;
    }
  }








  disconnectedCallback() {

    try {
      if (this._onGlobalKeyDown) {
        window.removeEventListener('keydown', this._onGlobalKeyDown, true);
      }
      if (this._onGlobalScrollOrResize) {
        window.removeEventListener('scroll', this._onGlobalScrollOrResize, true);
        window.removeEventListener('resize', this._onGlobalScrollOrResize, true);
      }
      if (this._debugContextMenu) {
        document.removeEventListener('contextmenu', this._debugContextMenu, true);
      }
      this.destroyMoveableInstance();
      //remove docx-preview docx-preview-sync jsforce pako loadash handlebarsjs moveable js paged jsforcescript
      window.docx = null;
      window.docxLib = null;
      window.docxLibAsync = null;
      window.jsforce = null;
      window.pako = null;
      window.loadash = null;
      window.handlebars = null;
      window.moveable = null;
      window.paged = null;
      window.jsforcescript = null;
      
      
    } catch (e) {
      // no-op
    }
  }


  async handleCompress(jsonString) {
    // 1. Show a loading spinner so the user knows something is happening
    this.isLoading = true;

    // 2. Wait for 100ms to let the browser render the spinner
    await new Promise(resolve => setTimeout(resolve, 100));

    // 3. Compress with JSZip (DEFLATE inside a ZIP container).
    // JSZip.generateAsync is promise-based and yields between work
    // ticks internally, so it does NOT freeze the main thread the way
    // pako.gzip() did. That's why we no longer need the manual
    // _gzipChunkedAsync wrapper for the save path.
    try {
      const compressed = await this._zipPayloadAsync(jsonString, { level: 9 });
      return compressed;
    } catch (error) {
      console.error('Error compressing JSON:', error);
      return null;
    } finally {
      this.isLoading = false;
    }

    /* ===== LEGACY PAKO / GZIP COMPRESS — kept for easy revert ============
     * To revert: comment out the JSZip block above and uncomment this one.
     * You'll also need to:
     *   - flip the extension in saveTemplate back to '.json.gz'
     *   - re-enable _gzipChunkedAsync below (still present, commented).
     *
     * try {
     *   const compressed = await this._gzipChunkedAsync(jsonString, { level: 9 });
     *   return compressed;
     * } catch (error) {
     *   console.error('Error compressing JSON:', error);
     *   return null;
     * } finally {
     *   this.isLoading = false;
     * }
     * ===================================================================*/
  }

  /**
   * Compress `jsonString` into a ZIP archive containing one entry
   * (`payload.json`) and return the raw bytes as a Uint8Array.
   *
   * JSZip's generateAsync is naturally async: it slices work across
   * microtasks, so the CSS spinner keeps animating without us
   * having to manually yield. `streamFiles: true` lets JSZip emit
   * deflate output incrementally rather than buffering twice.
   *
   * Mirrors what `_gzipChunkedAsync` used to return (Uint8Array), so
   * the rest of saveTemplate (Blob -> dataURL -> base64) is unchanged.
   */
  async _zipPayloadAsync(jsonString, { level = 9, fileName = 'payload.json' } = {}) {
    const J = window.JSZip;
    // Stricter than typeof === 'function': some bundles export JSZip as
    // an object (e.g. ESM-wrapped builds), so we check for the actual
    // static method we're about to call.
    if (!J || typeof J.loadAsync !== 'function') {
      throw new Error(
        '[_zipPayloadAsync] window.JSZip is not loaded or missing loadAsync. '
        + 'Check that the JZIP static resource exposes the JSZip global.'
      );
    }
    this._logJsZipVersionOnce();
    const zip = new J();
    zip.file(fileName, jsonString);
    // NOTE: deliberately NOT passing `streamFiles: true`.
    // streamFiles produces ZIPs whose local file headers omit the
    // compressed/uncompressed sizes (they're written in a trailing data
    // descriptor instead). Many ZIP readers -- including older builds
    // of JSZip itself and Apex's Compression.ZipReader in some orgs --
    // refuse to parse them and throw "Could not load Zip / Error on
    // ZipFile unknown archive". Standard non-streamed output is fully
    // compatible everywhere.
    return zip.generateAsync({
      type: 'uint8array',
      compression: 'DEFLATE',
      compressionOptions: { level },
    });
  }



  async handleDecompress(binaryData) {
    // 1. Show a loading spinner so the user knows something is happening
    this.isLoading = true;

    // 2. Wait for 100ms to let the browser render the spinner
    await new Promise(resolve => setTimeout(resolve, 100));

    // 3. Normalize the input into a Uint8Array regardless of how it
    // arrived. The three callers feed us different shapes:
    //   - PDFforceController.loadTemplateJSON returns a base64 STRING
    //     (EncodingUtil.base64Encode(cv.VersionData)).
    //   - The jsforce fallback path returns a Uint8Array of the raw
    //     ContentVersion bytes.
    //   - Some callers wrap the raw bytes in an ArrayBuffer.
    // If a base64 string is passed to pako.ungzip directly, pako reads
    // charCodeAt of each base64 character ('H', '4', 's', 'I', ...)
    // and bails with "unknown compression method". atob() first.
    try {
      let bytes;
      if (binaryData instanceof Uint8Array) {
        bytes = binaryData;
      } else if (binaryData instanceof ArrayBuffer) {
        bytes = new Uint8Array(binaryData);
      } else if (typeof binaryData === 'string') {
        // Strip a data URL prefix if one snuck in.
        const base64 = binaryData.includes(',') && binaryData.startsWith('data:')
          ? binaryData.split(',')[1]
          : binaryData;
        const binaryString = atob(base64);
        bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
      } else {
        throw new Error('handleDecompress: unsupported input type');
      }

      // 4. Format detection via magic-byte sniffing.
      // ----------------------------------------------------------------
      // saveTemplate now writes ONE OF THREE formats. We sniff the first
      // few bytes and route to the matching decoder. The three magic
      // signatures don't overlap, so detection is unambiguous and no
      // migration of stored files is needed:
      //
      //   ZIP   (new, JSZip)      : 50 4B 03 04  -> ".json.zip"
      //   gzip  (legacy, pako)    : 1F 8B 08     -> ".json.gz"
      //   raw   (small templates) : 7B ("{") or
      //                             5B ("[")    -> ".json"
      //
      // Keeping the gzip branch alive means existing customers who
      // have ".json.gz" templates in Salesforce continue to load them
      // even after we cut over to JSZip on the save side. Once every
      // template has been re-saved (and therefore upgraded to ZIP), the
      // gzip branch + the pako script load can be removed.
      const isZip  = bytes.length >= 4 &&
                     bytes[0] === 0x50 && bytes[1] === 0x4b &&
                     bytes[2] === 0x03 && bytes[3] === 0x04;
      const isGzip = bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
      let jsonString;
      if (isZip) {
        jsonString = await this._unzipPayloadAsync(bytes);
      } else if (isGzip) {
        // LEGACY: pako gunzip for templates saved before the JSZip cutover.
        // Inflate in chunks with yields between them, otherwise large
        // templates block the main thread long enough to freeze the CSS
        // spinner (its animations need main-thread paint).
        jsonString = await this._ungzipChunkedAsync(bytes);
      } else {
        // Raw UTF-8 JSON. TextDecoder handles multi-byte sequences
        // correctly (unlike String.fromCharCode loops, which truncate
        // each byte to a Latin-1 char and mangle anything outside
        // U+0000..U+00FF).
        jsonString = new TextDecoder('utf-8').decode(bytes);
      }
      return JSON.parse(jsonString);
    } catch (error) {
      console.error('Error decompressing JSON:', error);
      return null;
    } finally {
      this.isLoading = false;
    }
  }


  async saveTemplate() {
    console.log('Coming to saving template');
    this.loading = true;
    //Pages and its htmlContent
    let jsonTobeSaved = {};

    let div = document.createElement('div');
    div.innerHTML = this.OrignalHtmlContent;
    div.querySelector('.docx-wrapper').querySelectorAll('section.docx').forEach(section => {
      const article = section.querySelector('article');
      if (article) {
        this.unmakeArticleChildrenSelectable(article);
      }
    });
    let editedHtml = div.innerHTML;

    // 0. Optimize inline images BEFORE JSON.stringify so the payload that
    // hits the compressor is small. Word usually embeds camera-resolution
    // photos; downscaling + JPEG-recoding the large ones typically cuts an
    // image-heavy template by 70-90% with no architectural change — same
    // single ContentVersion, same sharing rows, so Community access stays
    // identical to today.
    try {
      editedHtml = await this.optimizeInlineImages(editedHtml);
    } catch (e) {
      // Never block a save because of optimization — fall back to the
      // un-optimized HTML and log so it's debuggable.
      console.warn('[saveTemplate] optimizeInlineImages failed, saving original', e);
    }

    // NOTE: we INTENTIONALLY do not call sanitizeHtmlForPdf() here.
    // Some of its passes (stripping <style> blocks, renaming HTML5
    // semantic elements to <div>, rewriting <img> data-URI MIMEs)
    // are destructive: they make the HTML render correctly in
    // Blob.toPdf but make it render WRONG in the LWC editor on the
    // next load. docxjs's preview CSS lives in <style> blocks and
    // its selectors target tag names like `section.docx > article`,
    // so dropping either breaks the preview.
    //
    // The Apex side (PdfRenderEmailHandler.sanitizeForBlobToPdf)
    // runs the same 9 passes at PDF-render time only, against the
    // post-Handlebars output -- so the persisted ContentVersion
    // stays full-fidelity (loads/edits correctly) AND every render
    // still gets a Blob.toPdf-safe input. The sanitizeHtmlForPdf
    // method is kept on this component for client-side PDF preview
    // (where the destructive transforms are scoped to a throwaway
    // copy) but is no longer invoked here.

    jsonTobeSaved = { htmlContent: editedHtml, signatureFields: this.signatureFields };

    // ---- Diagnostic: confirm Handlebars merge tags survive the save.
    // Counts `{{...}}` runs (both `{{var}}` and `{{#name}}`/`{{/name}}`)
    // in the source DOM and in the about-to-be-saved HTML.
    //
    // If `originalTagCount > 0` but `savedTagCount === 0` the save path
    // is silently stripping merge fields (regression in
    // optimizeInlineImages / unmakeArticleChildrenSelectable / a future
    // sanitizer). If `originalTagCount === 0` the source itself never
    // had any tags (template author didn't add merge fields, or the
    // upstream OrignalHtmlContent was overwritten by a Handlebars
    // render against {} -- happens if `OrignalHtmlContent` is set from
    // the live editor DOM after `this.template({})` rewrites it).
    try {
      const tagPattern = /\{\{[\s\S]*?\}\}/g;
      const originalTagCount = (this.OrignalHtmlContent.match(tagPattern) || []).length;
      const savedTagCount = (editedHtml.match(tagPattern) || []).length;
      console.log(
        '[saveTemplate] handlebars merge tags -- original:', originalTagCount,
        'saved:', savedTagCount
      );
      if (originalTagCount > 0 && savedTagCount === 0) {
        console.warn(
          '[saveTemplate] Merge tags present in OrignalHtmlContent but missing from '
          + 'serialized payload. Investigate optimizeInlineImages / '
          + 'unmakeArticleChildrenSelectable / any sanitizer that ran between '
          + '`div.innerHTML = OrignalHtmlContent` and `editedHtml = div.innerHTML`.'
        );
      } else if (originalTagCount === 0) {
        console.warn(
          '[saveTemplate] No Handlebars merge tags found in OrignalHtmlContent. '
          + 'Either the template author did not add any, or OrignalHtmlContent '
          + 'was last set from the post-Handlebars editor DOM '
          + '(check OrignalHtmlContent assignments in renderFile / toggleDocumentRenderer).'
        );
      }
    } catch (diagErr) {
      console.warn('[saveTemplate] merge-tag diagnostic failed', diagErr);
    }

    try {
      console.log('Converting JSON to String');
      // 1. Convert JSON to String
      const jsonString = JSON.stringify(jsonTobeSaved);

      console.log('JSON String', jsonString);
      // 2. Size-based persistence strategy.
      // --------------------------------------------------------------
      // Compressing every template is overhead we don't always need:
      // the compressor loads in the LWC, decompression happens on every
      // load, and the .json.zip file isn't human-readable for support
      // cases. For small templates the raw JSON is tiny enough to
      // round-trip through ContentVersion without compression. Only for
      // large templates does compression earn its place (storage + Apex
      // heap when PDFforceController.loadTemplateJSON returns base64).
      //
      // Threshold: 3 MB of UTF-8 bytes. This matches the same 3 MB
      // cutoff used in PDFforceController.loadTemplateJSON to decide
      // Apex-vs-jsforce - so a "small" template always comes back via
      // Apex and a "large" one always via jsforce, regardless of
      // whether it's compressed on disk.
      //
      // Format markers (new):
      //   - large templates (> 3 MB JSON): ZIP archive (JSZip), magic
      //     50 4B 03 04, stored as <name>.json.zip, single entry
      //     "payload.json".
      //   - small templates (<= 3 MB JSON): raw UTF-8 JSON bytes,
      //     first byte is "{" (0x7B), stored as <name>.json
      //
      // Legacy format still readable by handleDecompress:
      //   - gzip bytes, magic 1F 8B 08, stored as <name>.json.gz
      //     (templates saved before the JSZip cutover).
      //
      // handleDecompress on the load side sniffs the magic bytes and
      // routes accordingly, so old gzipped templates keep loading fine
      // without any migration.
      const COMPRESS_THRESHOLD_BYTES = 3 * 1024 * 1024;
      const rawJsonBlob = new Blob([jsonString], { type: 'application/json' });
      const jsonByteSize = rawJsonBlob.size; // UTF-8 byte size, not jsString.length
      const shouldCompress = jsonByteSize > COMPRESS_THRESHOLD_BYTES;

      // 3. Produce the bytes that will land in ContentVersion.VersionData.
      // Either zip(jsonString) (JSZip) or the raw UTF-8 JSON itself. In
      // both cases we go through readUploadedFileAsDataUrl + strip the
      // "data:...;base64," prefix - Salesforce's VersionData field
      // expects ONLY the base64 payload. Leaving the prefix on causes
      // SF to base64-decode the whole string (prefix included) and the
      // bytes on disk end up corrupted.
      let payloadBlob;
      let payloadByteSize;
      if (shouldCompress) {
        const compressed = await this.handleCompress(jsonString);
        payloadBlob = new Blob([compressed]);
        payloadByteSize = compressed.length;
      } else {
        payloadBlob = rawJsonBlob;
        payloadByteSize = jsonByteSize;
      }
      const dataUrl = await readUploadedFileAsDataUrl(payloadBlob);
      const base64Temp = dataUrl.includes(',') ? dataUrl.split(',')[1] : dataUrl;

      // PathOnClient extension reflects the on-disk format. handleDecompress
      // doesn't actually need this (it sniffs the bytes), but it makes the
      // file self-describing in Salesforce's Files UI and in download paths.
      // To revert to pako/gzip: change '.json.zip' below back to '.json.gz'.
      const fileExtension = shouldCompress ? '.json.zip' : '.json';

      console.log(
        '[saveTemplate] JSON byte size:', jsonByteSize,
        'shouldCompress:', shouldCompress,
        'payload byte size:', payloadByteSize,
        'base64 size:', base64Temp.length,
        'extension:', fileExtension
      );

      //wait for 3 seconds
      await new Promise(resolve => setTimeout(resolve, 3000));

      var conn = new jsforce.Connection({
        serverUrl: this.vfRoot,
        sessionId: await getUserSessionId()
      });
      let contentVersionList = [];
      console.log('ContentVersion', this.currentContentVersion)

      //if contentVersionId is not null , thne update else create
      if (this.currentContentVersion) {
        try {
          let testSample = await conn.sobject("ContentVersion").create(
            [{
              'Title': this.currentContentVersion.Title,
              'PathOnClient': `${this.currentContentVersion.Title}${fileExtension}`,
              'VersionData': base64Temp,
              'Description': 'PDFForce template',
              'ContentDocumentId': this.currentContentVersion.ContentDocumentId
            }]
          );

          let hasErrors = false;
          for (let val of testSample) {
            if (val.success) {
              contentVersionList.push(val.id);
            }
            if (val.errors && val.errors.length > 0) {
              hasErrors = true;
              console.error('ContentVersion creation errors:', JSON.stringify(val.errors, null, 2));
              console.error('Full error response:', JSON.stringify(val, null, 2));

              // Log each error detail
              val.errors.forEach((error, index) => {
                console.error(`Error ${index + 1}:`, {
                  statusCode: error.statusCode,
                  message: error.message,
                  fields: error.fields
                });
              });
            }
          }

          if (hasErrors) {
            throw new Error('ContentVersion creation failed with errors. Check console for details.');
          }

          if (contentVersionList.length === 0) {
            throw new Error('ContentVersion creation returned no successful results');
          }

          this.showToastMessage('Success', 'Version updated', 'success');
          //Refresh the page
          window.location.reload();
          this.loading = false;
        } catch (error) {
          console.error('Error updating ContentVersion:', error);
          console.error('Error details:', {
            message: error?.message,
            stack: error?.stack,
            name: error?.name,
            fullError: JSON.stringify(error, Object.getOwnPropertyNames(error), 2)
          });
          this.showToastMessage('Error', `Version could not be updated: ${error?.message || 'Unknown error'}`, 'error');
          this.loading = false;
          return; // Exit early to prevent further execution
        }
      } else {
        let testSample = await conn.sobject("ContentVersion").create([{
          'Title': `${this.uploadedFile.name}`,
          'PathOnClient': `${this.uploadedFile.name}${fileExtension}`,
          'VersionData': base64Temp,
          'Description': 'PDFForce template'
        }]);
        for (let val of testSample) {
          if (val.success) {
            contentVersionList.push(val.id);
          }
        }


        createCDLRecords({
          cvIdsList: contentVersionList,
          recordId: this.recordId
        }).then(result => {
          this.showToastMessage('Success', 'New Version Created', 'success');
          window.location.reload();
        })
          .catch(error => {
            this.showToastMessage('Error', 'Files could not be uploaded', 'error');
          }).finally(() => {
            this.loading = false;
          });
      }

    } catch (error) {
      console.error('Error uploading attachment:', error);
      this.loading = false;
    }

  }


  showToastMessage(title, message, variant) {
    const event = new ShowToastEvent({
      title: title,
      message: message,
      variant: variant
    });
    this.dispatchEvent(event);
  }

  get recordName() {
    return this.record.data ? getFieldValue(this.record.data, NameField) : '';
  }






  @track uploadedFile;

  @track pageDimensions = {
    width: 0,
    height: 0,
    margins: null
  };

  @track contentNotLoaded = true;

  // get contentNotLoaded() {
  //   return this.querySelector('.page-wrapper') && this.querySelector('.page-wrapper').innerHTML.trim() === '' ? true : false;
  // }

  async handleTemplateFileUpload(event) {

    let file = event.target.files[0];
    this.uploadedFile = file;

    if (!file) {
      return;
    }

    // Check if docx library is loaded
    if (!this.docxLib) {
      return;
    }

    try {
      this.loading = true;
      // Using JSZip to read the docx structure
      const zip = await JSZip.loadAsync(file);
      const str = await zip.file("word/document.xml").async("string");
      const parser = new DOMParser();
      const xmlDoc = parser.parseFromString(str, "text/xml");

      // Target the section properties
      const pgSz = xmlDoc.getElementsByTagName("w:pgSz")[0];
      const wTwips = pgSz.getAttribute("w:w");
      const hTwips = pgSz.getAttribute("w:h");



      // Target the page margins tag
      const pgMar = xmlDoc.getElementsByTagName("w:pgMar")[0];
      const margins = {
        top: pgMar.getAttribute("w:top") / 20,    // Convert Twips to Points
        right: pgMar.getAttribute("w:right") / 20,
        bottom: pgMar.getAttribute("w:bottom") / 20,
        left: pgMar.getAttribute("w:left") / 20
      };
      this.pageDimensions.margins = margins;

      // Convert Twips to Points (1 pt = 20 twips)
      const widthPt = wTwips / 20;
      const heightPt = hTwips / 20;
      this.pageDimensions.width = widthPt;
      this.pageDimensions.height = heightPt;

      // Extract header if it exists (for repeating in continuous view)
    } catch (error) {
      console.error('Error processing docx file:', error);
      this.showToastMessage('Error', 'Error processing docx file', 'error');
      this.loading = false;
    }


    this.renderFile();
  }



  //Prevent Horizontal Strech for Tables in Docx
  processDocx(htmlFromDocx) {
    // 1. Fix the table structure immediately (Hoisting)
    const fixedHtml = htmlFromDocx
      .replace(/(<tr.*?>)(\s*<td.*?>\s*)({{#.*?}})/g, '$3$1$2')
      .replace(/({{\/.*?}})(\s*<\/td>\s*<\/tr>)/g, '$2$1');

    // 2. Compile once and store the function (not the massive string)
    return fixedHtml;
  }




  renderFile() {
    this.loading = true;
    //Clear out existing pages

    // Read file as ArrayBuffer (required by docx-preview)
    let reader = new FileReader();
    reader.onload = async (e) => {
      let editor = this.querySelector('.page-wrapper');

      const docxOptions = Object.assign(docx.defaultOptions, {
        debug: false,
        experimental: true,
        useBase64URL: true,
      });

      this.docxLibAsync.renderAsync(e.target.result, editor, null, docxOptions).then(() => {
        editor.querySelector('div.docx-wrapper').style.background = 'unset !important';
        editor.querySelector('div.docx-wrapper').style.padding = '0px !important';

        editor.querySelector('.docx-wrapper').querySelectorAll('section.docx').forEach(section => {
          section.classList.add('canvas-page');
          section.style.boxSizing = 'border-box';
          const header = section.querySelector('header');
          if (header) {
            header.style.marginTop = '0px !important';
          }
        });
        this.normalizeDocxTablesForFlow(editor);
        this.adaptDocxSectionWidthToContent(editor);

        this.createCustomStyles(editor);

        // Reset high z-index values after rendering
        this.resetHighZIndex(editor);


        try {

          this.OrignalHtmlContent = this.robustHandlebarsHealer(editor.outerHTML);
          this.handleBarsCompileUtility(this.OrignalHtmlContent);

          editor.querySelector('.docx-wrapper').innerHTML = this.template({});

          editor.querySelector('.docx-wrapper').querySelectorAll('section.docx').forEach((section) => {
            section.classList.add('canvas-page');
            section.style.boxSizing = 'border-box';
            const header = section.querySelector('header');
            if (header) header.style.marginTop = '0px !important';
            // const article = section.querySelector('article');
            // if (article) this.makeArticleChildrenSelectable(article, section);
          });
          this.normalizeDocxTablesForFlow(editor);
          this.adaptDocxSectionWidthToContent(editor);
          this.initSortableForSections();
          this.initComponentsSortable();
        } catch (error) {
          console.error('Error compiling Handlebars template:', error);

          // Surface the error to the user
          const errorMessage = error?.message || 'Handlebars template compilation failed';
          const lineNumber = this.extractLineNumberFromError(error);
          this.reportValidityCheck(`Handlebars compilation error: ${errorMessage}`, lineNumber);
          this.showToastMessage('Handlebars Compilation Error', errorMessage, 'error');

          // Set template to null to prevent using a broken template
          this.template = null;
        } finally {
          this.saveTemplate();
        }
        this.contentNotLoaded = false;
        this.disableSaveButton = false;


      })
        .catch(error => {
          console.error('Error rendering document:', error);
          this.loading = false;
        });
    }
    reader.onerror = (error) => {
      console.error('Error reading file:', error);
      this.loading = false;
    };
    reader.readAsArrayBuffer(this.uploadedFile);
  }


  handleBarsCompileUtility(html, preview = false) {
    try {
      // if (!preview) {
      //   Handlebars.registerHelper('helperMissing', function () {
      //     // Get the last argument which is always the options hash
      //     const options = arguments[arguments.length - 1];
      //     const args = Array.prototype.slice.call(arguments, 0, -1);

      //     // Extract the variable/helper name from options.name
      //     const name = options?.name || '';

      //     // Handle both simple variables and block helpers
      //     // If this is a block helper (has fn property), preserve the block structure

      //       // This is a simple variable like {{firstName}}
      //       return new Handlebars.SafeString(`{{${name}}}`);
      //   });
      // } else {
      //   Handlebars.unregisterHelper('helperMissing');
      // }


      const compileHtml = this.robustHandlebarsHealer(html);
      this.template = Handlebars.compile(compileHtml);
      // Clear any previous errors if compilation succeeds
      this.clearJsonValidity();
    } catch (error) {
      console.error('Error compiling Handlebars template:', error);

      // Surface the error to the user
      const errorMessage = error?.message || 'Handlebars template compilation failed';
      const lineNumber = this.extractLineNumberFromError(error);
      this.reportValidityCheck(`Handlebars compilation error: ${errorMessage}`, lineNumber);
      this.showToastMessage('Handlebars Compilation Error', errorMessage, 'error');

      // Set template to null to prevent using a broken template
      this.template = null;
    }
  }



  /**
   * Normalizes edit-element wrappers in parsed DOM: replaces each wrapper with just
   * the template's innerHTML so Handlebars compiles content once (no duplicates).
   * @param {HTMLElement} container - Container to search for wrappers
   */
  _normalizeEditElementWrappers(container) {
    const wrappers = Array.from(container.querySelectorAll('[data-edit-element-wrapper]'));
    wrappers.forEach((wrapper) => {
      const rawEncoded = wrapper.getAttribute('data-edit-element-html');
      if (rawEncoded) {
        try {
          const decoded = decodeURIComponent(rawEncoded);
          const replacement = wrapper.ownerDocument.createElement('div');
          replacement.innerHTML = decoded;
          const parent = wrapper.parentNode;
          while (replacement.firstChild) {
            parent.insertBefore(replacement.firstChild, wrapper);
          }
          wrapper.remove();
          return;
        } catch (e) {
          // Fallback to template path below.
        }
      }
      const template = wrapper.querySelector('template');
      if (template) {
        const replacement = wrapper.ownerDocument.createElement('div');
        replacement.innerHTML = template.innerHTML;
        const parent = wrapper.parentNode;
        while (replacement.firstChild) {
          parent.insertBefore(replacement.firstChild, wrapper);
        }
        wrapper.remove();
      }
    });
  }

  robustHandlebarsHealer(html) {
    if (!html) return '';

    const parser = new DOMParser();
    let htmlString = `${html}`;
    const doc = parser.parseFromString(htmlString, 'text/html');

    // Normalize edit-element wrappers so Handlebars compiles template content once
    this._normalizeEditElementWrappers(doc.body);

    // Get the full text content, which ignores all tags
    let fullContent = doc.body.innerHTML;
    let changesMade = 0;

    // Pattern 1: Fix delimiters split by tags: {<tag>{ → {{
    const delimiterPattern1 = /\{(<[^>]+>)+\{/g;
    const delimiterMatches1 = fullContent.match(delimiterPattern1);
    if (delimiterMatches1) {
      changesMade += delimiterMatches1.length;
    }
    fullContent = fullContent.replace(delimiterPattern1, '{{');

    const delimiterPattern2 = /\}(<[^>]+>)+\}/g;
    const delimiterMatches2 = fullContent.match(delimiterPattern2);
    if (delimiterMatches2) {
      changesMade += delimiterMatches2.length;
    }
    fullContent = fullContent.replace(delimiterPattern2, '}}');

    // Pattern 2: Remove tags INSIDE Handlebars expressions
    // BUT preserve block helper characters (#, /, ^, >, etc.)
    // Match: {{...content with possible tags...}}
    let expressionsFixed = 0;
    fullContent = fullContent.replace(/\{\{([\s\S]*?)\}\}/g, (match, content) => {
      const hasTags = /<[^>]+>/.test(content);
      if (!hasTags) {
        return match; // No tags, keep as-is
      }

      expressionsFixed++;

      // Check if this is a block helper or other special syntax
      // Block helpers start with: #, /, ^, >, @, else
      // Don't clean these - they're valid Handlebars syntax
      if (content.match(/^\s*[#\/\^>@]/) || content.trim() === 'else') {
        // This is a block helper - only remove HTML tags, keep the helper syntax
        const cleaned = content.replace(/<[^>]+>/g, '');
        return `{{${cleaned}}}`;
      }

      // For regular variables, remove HTML tags
      const cleaned = content.replace(/<[^>]+>/g, '');

      // If after cleaning it looks like a simple variable name, keep it
      if (/^[a-zA-Z_$][a-zA-Z0-9_.]*$/.test(cleaned.trim())) {
        return `{{${cleaned.trim()}}}`;
      }

      // For complex expressions (with spaces, helpers, etc.), keep the cleaned version
      return `{{${cleaned}}}`;
    });

    return fullContent;
  }




  /**
   * Returns the HTML to insert when a component is dropped into an article.
   * @param {string} componentId - Component id (e.g. 'image')
   */
  getComponentHtml(componentId) {
    const map = {
      image: '<p><img src="{{imageUrl}}" alt="{{imageAlt}}" style="max-width:100%;height:auto;" /></p>'
    };
    return map[componentId] || `<p data-component="${componentId}">{{${componentId}}}</p>`;
  }

  /**
   * Initializes Sortable for each section.docx article so items can be reordered
   * and components from the accordion can be dropped. Call after page-wrapper content is loaded.
   */
  initSortableForSections() {
    if (typeof window.Sortable === 'undefined') return;
    const pageWrapper = this.querySelector('.page-wrapper');
    if (!pageWrapper) return;
    const docxWrapper = pageWrapper.querySelector('.docx-wrapper');
    if (!docxWrapper) return;

    docxWrapper.querySelectorAll('section.docx').forEach((section) => {
      const article = section.querySelector('article');
      if (!article) return;

      const sortable = window.Sortable.create(article, {
        group: {
          name: 'components',
          pull: true,
          put: true
        },
        animation: 150,
        ghostClass: 'sortable-ghost',
        chosenClass: 'sortable-chosen',
        dragClass: 'sortable-drag',
        onAdd: (evt) => {
          const item = evt.item;
          const componentId = item.getAttribute?.('data-component-id');
          if (componentId && item.classList?.contains('component-draggable')) {
            const html = this.getComponentHtml(componentId);
            const div = item.ownerDocument.createElement('div');
            div.innerHTML = html.trim();
            const fragment = div.firstChild;
            if (fragment) {
              item.replaceWith(fragment);
              const sectionEl = fragment.closest('section.docx');
              const art = sectionEl?.querySelector('article');
              if (art && sectionEl) this.makeArticleChildrenSelectable(art, sectionEl);
            }
          }
        }
      });
      this._sortableInstances.push(sortable);
    });
  }

  /**
   * Initializes Sortable on the Components accordion so items can be dragged into section articles.
   */
  initComponentsSortable() {
    if (typeof window.Sortable === 'undefined') return;
    const source = this.querySelector('[data-id="componentsSource"]');
    if (!source) return;

    const sortable = window.Sortable.create(source, {
      group: {
        name: 'components',
        pull: 'clone',
        put: false
      },
      sort: false,
      animation: 150,
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag'
    });
    this._sortableInstances.push(sortable);
  }


  /**
   * Makes header, article direct children, and footer separately selectable.
   * @param {HTMLElement} article - The article element
   * @param {HTMLElement} section - The section.docx container
   */
  makeArticleChildrenSelectable(article, section) {
    if (!article && !section) {
      return;
    }

    const sectionEl = section || article?.closest?.('section.docx');
    const articleEl = article || sectionEl?.querySelector?.('article');
    if (!sectionEl || !articleEl) {
      return;
    }

    const selectableElements = [];
    // Iterate section's direct children in order. Anything that isn't the
    // <article> is treated as a top-level selectable target (header, footer,
    // or an edit-element wrapper that replaced one of them after save).
    Array.from(sectionEl.children).forEach((child) => {
      if (child === articleEl) {
        if (articleEl.children.length > 0) {
          selectableElements.push(...Array.from(articleEl.children));
        } else {
          // Keep actions available even when article has no children yet.
          selectableElements.push(articleEl);
        }
      } else {
        selectableElements.push(child);
      }
    });

    selectableElements.forEach((element) => {
      element.classList.add('selectable-element');

      // Set position to relative if not already positioned
      if (!element.style.position || element.style.position === 'static') {
        element.style.position = 'relative';
      }

      if (element._selectableContextMenuHandler) {
        return;
      }

      const clickHandler = (e) => {
        if (this.renderer) return;
        e.stopPropagation();
        this.selectElement(element, sectionEl);
        // Context menu should only appear on right-click.
        this.hideElementContextMenu();
      };

      const contextMenuHandler = (e) => {
        if (this.renderer) return;
        e.preventDefault();
        e.stopPropagation();
        const isAlreadySelected = this.selectedElement === element;
        this.selectElement(element, sectionEl);
        // Always track the live target so Edit Element reads current DOM after saves.
        this._activeElementEl = element;
        this._activeElementSectionEl = sectionEl;

        // Context menu should be shown only for the persisted selected element.
        // If right-click targets a different element, first persist selection only.
        if (!isAlreadySelected) {
          this.hideElementContextMenu();
          return;
        }
        this._elementMenuClientX = e.clientX ?? 0;
        this._elementMenuClientY = e.clientY ?? 0;
        this.showElementContextMenu({ x: e.clientX ?? 0, y: e.clientY ?? 0 });
      };
      element._selectableClickHandler = clickHandler;
      element.addEventListener('click', clickHandler, true);
      element._selectableContextMenuHandler = contextMenuHandler;
      element.addEventListener('contextmenu', contextMenuHandler, true);
    });

  }

  /**
   * Removes selectable behavior/context-menu handlers from header/article/footer targets.
   * Opposite of makeArticleChildrenSelectable.
   * @param {HTMLElement} article - The article element
   */
  /**
   * Build a clean, stable HTML snapshot of a live wrapper element
   * (e.g. `.page-wrapper` or `.docx-wrapper`) WITHOUT the bloat that
   * comes from snapshotting the live DOM:
   *
   *   1. Parses into a `<template>` so the fragment is inert — no
   *      style application, no <img> network load, no script run.
   *   2. Strips authoring-only UI affordances (selectable wrappers,
   *      moveable/sortable handles, edit-mode classes).
   *   3. Serializes via XMLSerializer, which is byte-stable across
   *      repeated round-trips (innerHTML drifts: re-quotes attrs,
   *      re-encodes entities, normalizes whitespace).
   *
   * Use this every time you need to persist or compile the current
   * canvas content. Never assign `wrapper.innerHTML` directly to
   * `this.OrignalHtmlContent` — that captures all the UI chrome and
   * compounds on every save/toggle.
   *
   * @param {Element} wrapperEl source element (live DOM is fine; not mutated)
   * @returns {string} clean HTML suitable for storing as the authoring source
   */
  takeCleanSnapshot(wrapperEl) {
    if (!wrapperEl) return '';
    const tpl = document.createElement('template');
    tpl.innerHTML = wrapperEl.innerHTML;
    const frag = tpl.content;

    frag.querySelectorAll('.docx-wrapper section.docx article').forEach((article) => {
      try {
        this.unmakeArticleChildrenSelectable(article);
      } catch (e) {
        console.warn('[takeCleanSnapshot] unmake failed for article, skipping', e);
      }
    });

    frag.querySelectorAll(
      '.moveable-control-box, .moveable-area, .moveable-line, .moveable-control, [data-sortable-handle]'
    ).forEach((n) => n.remove());

    frag.querySelectorAll('.selected, .selected-element, .selectable-element').forEach((n) => {
      n.classList.remove('selected');
      n.classList.remove('selected-element');
      n.classList.remove('selectable-element');
      if (n.getAttribute('class') === '') n.removeAttribute('class');
    });

    frag.querySelectorAll('[contenteditable]').forEach((n) => n.removeAttribute('contenteditable'));

    try {
      return new XMLSerializer().serializeToString(frag);
    } catch (e) {
      console.warn('[takeCleanSnapshot] XMLSerializer failed, falling back to innerHTML', e);
      const host = document.createElement('div');
      host.appendChild(frag.cloneNode(true));
      return host.innerHTML;
    }
  }

  unmakeArticleChildrenSelectable(article) {
    if (!article) {
      return;
    }

    const sectionEl = article.closest?.('section.docx');
    const selectableElements = [];
    if (sectionEl) {
      // Mirror makeArticleChildrenSelectable: clean up every non-article direct
      // child of the section (header, footer, or an edit-element wrapper that
      // replaced one of them).
      Array.from(sectionEl.children).forEach((child) => {
        if (child !== article) selectableElements.push(child);
      });
      // Backward-compat cleanup for a previously section-level selectable state.
      selectableElements.push(sectionEl);
    }
    selectableElements.push(...Array.from(article.children));
    if (article.children.length === 0) {
      selectableElements.push(article);
    }

    selectableElements.forEach(element => {
      element.classList.remove('selectable-element');
      element.classList.remove('selected');
      element.classList.remove('selected-element');
      if (element._selectableClickHandler) {
        element.removeEventListener('click', element._selectableClickHandler, true);
        delete element._selectableClickHandler;
      }
      if (element._selectableContextMenuHandler) {
        element.removeEventListener('contextmenu', element._selectableContextMenuHandler, true);
        delete element._selectableContextMenuHandler;
      }
      if (element === this.selectedElement) {
        element.removeAttribute('contenteditable');
        element.blur();
        this.selectedElement = null;
      }
    });
  }

  /**
   * Selects an element and stores reference
   * @param {HTMLElement} element - Element to select
   * @param {HTMLElement} container - Container element
   */
  selectElement(element, container) {
    // Deselect previous element if any
    if (this.selectedElement && this.selectedElement !== element) {
      this.deselectElement();
    }

    // Remove selection from all elements
    const allSelectable = container.querySelectorAll('.selectable-element');
    allSelectable.forEach(el => {
      el.classList.remove('selected');
      el.classList.remove('selected-element');
    });






    element.classList.add('selected');
    // element.classList.add('selectable-element');



    this.selectedElement = element;

  }

  /**
   * Deselects the currently selected element and removes contentEditable
   */
  deselectElement() {
    this.destroyMoveableInstance();
    if (this.selectedElement) {
      this.selectedElement.removeAttribute('contenteditable');
      this.selectedElement.blur();

      // Unwrap the drop-zone: restore the element's original positioning and
      // put it back where the wrapper sits in the DOM.
      const element = this.selectedElement;
      const dropZone = this._activeDropZone
        || element.closest?.('[data-pdf-tb-drop-zone="true"]');

      if (dropZone && dropZone.parentNode) {
        // Restore the element's original positioning styles captured during select.
        const ds = element.dataset;
        element.style.position = ds.pdfTbWrapperPrevPosition || '';
        element.style.top = ds.pdfTbWrapperPrevTop || '';
        element.style.left = ds.pdfTbWrapperPrevLeft || '';
        element.style.right = ds.pdfTbWrapperPrevRight || '';
        element.style.bottom = ds.pdfTbWrapperPrevBottom || '';
        element.style.transform = ds.pdfTbWrapperPrevTransform || '';
        element.style.margin = ds.pdfTbWrapperPrevMargin || '';
        if (!ds.pdfTbWrapperPrevMargin && ds.pdfTbWrapperPrevMarginTop) {
          element.style.marginTop = ds.pdfTbWrapperPrevMarginTop;
        }
        element.style.width = '';
        element.style.height = '';

        delete ds.pdfTbWrapperPrevPosition;
        delete ds.pdfTbWrapperPrevTop;
        delete ds.pdfTbWrapperPrevLeft;
        delete ds.pdfTbWrapperPrevRight;
        delete ds.pdfTbWrapperPrevBottom;
        delete ds.pdfTbWrapperPrevTransform;
        delete ds.pdfTbWrapperPrevMargin;
        delete ds.pdfTbWrapperPrevMarginTop;

        // Replace the wrapper with the element in the live DOM.
        dropZone.replaceWith(element);
      }

      this._activeDropZone = null;
      this.selectedElement = null;
    }
  }

  destroyMoveableInstance() {
    if (this._moveableInstance) {
      try {
        this._moveableInstance.destroy();
      } catch (e) {
        // no-op
      }
    }
    this._moveableInstance = null;
    this._moveableTarget = null;
    this._moveableContainer = null;
    this.moveableInitialized = false;
  }



  @track moveableInitialized = false;

  enableMoveableForSelectedElement(element, sectionEl) {
    if (!element) return;
    this.moveableInitialized = true;
    const article = sectionEl?.querySelector('article') || element.closest?.('article');
    if (!article) return;

    const MoveableCtor = window.Moveable || window?.moveable?.default;
    if (!MoveableCtor) {
      this.showToastMessage('Error', 'Moveable library is not available', 'error');
      return;
    }

    this.destroyMoveableInstance();
    this.selectElement(element, sectionEl || article.closest?.('section.docx'));

    // Ensure container can host moveable control box and target movement.
    if (window.getComputedStyle(article).position === 'static') {
      article.style.position = 'relative';
    }

    const baseRect = element.getBoundingClientRect();
    const articleRect = article.getBoundingClientRect();
    const minX = articleRect.left - baseRect.left;
    const maxX = articleRect.right - baseRect.right;
    const minY = articleRect.top - baseRect.top;
    const maxY = articleRect.bottom - baseRect.bottom;

    const initialTransform = element.style.transform || '';
    const transformWithoutTranslate = initialTransform.replace(/translate(?:3d)?\([^)]*\)/g, '').trim();

    this._moveableTarget = element;
    this._moveableContainer = article;
    this._moveableInstance = new MoveableCtor(article, {
      target: element,
      draggable: true,
      origin: false,
      snappable: true,
      throttleDrag: 0
    });
    this._moveableInstance.verticalGuidelines = [100, 200, 500];
    this._moveableInstance.horizontalGuidelines = [100, 200, 500];

    this._moveableInstance.on('dragStart', ({ set }) => {
      set([0, 0]);
    });

    this._moveableInstance.on('drag', ({ beforeTranslate }) => {
      const nextX = Array.isArray(beforeTranslate) ? beforeTranslate[0] : 0;
      const nextY = Array.isArray(beforeTranslate) ? beforeTranslate[1] : 0;

      const clampedX = Math.min(maxX, Math.max(minX, nextX));
      const clampedY = Math.min(maxY, Math.max(minY, nextY));

      const translate = `translate(${clampedX}px, ${clampedY}px)`;
      element.style.transform = transformWithoutTranslate
        ? `${transformWithoutTranslate} ${translate}`
        : translate;
    });
  }

  createCustomStyles(element) {
    // Method 1: Create a style element
    const styleElement = document.createElement('style');
    styleElement.id = 'custom-styles';

    styleElement.textContent = `
     .selectable-element:hover{
      outline: 2px solid #0176d3;
    outline-offset: 2px;
    background-color: rgba(1, 118, 211, 0.1);
    user-select: none;
    touch-action: none;
     } 


   

    

    .canvas-page {
      width: calc(100% - 40px);
      max-width: 100%;
      height: auto;
      min-height: auto;
      max-height: none; 
      background: white;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
      position: relative;
      overflow-x: hidden;
      overflow-y: visible;
      border-radius: 12px 12px 12px 12px;
      padding: 0; 
      margin: 20px auto;
      box-sizing: border-box;
      page-break-after: always !important;
      break-after: always !important;
    }

    .canvas-page:hover {
      box-shadow: 0 24px 48px rgba(0, 0, 0, 0.15);
      transform: translateY(-2px);
    }

    /* Reset z-index values that exceed 9000 to prevent layout issues */
    .page-wrapper *,
    .canvas-page *,
    section.docx *,
    section.docx article *,
    section.docx table *,
    section.docx td *,
    section.docx th *,
    section.docx p *,
    section.docx div *,
    section.docx span * {
      z-index: auto !important;
    }

    .page-wrapper,
    .canvas-page,
    section.docx,
    section.docx article {
      z-index: auto !important;
      position: relative !important;
    }

    /* Keep DOCX tables and long tokens inside page bounds */
    .canvas-page table,
    section.docx table,
    section.docx article table {
      width: 100% !important;
      max-width: 100% !important;
      table-layout: fixed !important;
      box-sizing: border-box;
    }

    .canvas-page table td,
    .canvas-page table th,
    section.docx table td,
    section.docx table th,
    section.docx article table td,
    section.docx article table th {
      white-space: normal !important;
      word-break: break-word !important;
      overflow-wrap: anywhere !important;
    }

   
      .page-break {
 break-after: right !important;
  page-break-after: always !important;
  height: 0;
  display: block;
}
   
  `
      ;
    element.appendChild(styleElement);

    // Also use JavaScript to find and reset elements with z-index > 9000
    this.resetHighZIndex(element);
  }

  /**
   * Normalizes DOCX table sizing so content reflows within the page width.
   * This helps wide Word tables/tokens stay inside section.docx in editor view.
   * @param {HTMLElement} container - Render root that contains docx sections
   */
  normalizeDocxTablesForFlow(container) {
    if (!container) return;

    const sections = container.querySelectorAll('section.docx');
    sections.forEach((section) => {
      section.style.setProperty('max-width', '100%', 'important');
      section.style.setProperty('box-sizing', 'border-box', 'important');

      section.querySelectorAll('table').forEach((table) => {
        table.removeAttribute('width');
        table.style.setProperty('width', '100%', 'important');
        table.style.setProperty('max-width', '100%', 'important');
        table.style.setProperty('table-layout', 'fixed', 'important');
        table.style.setProperty('box-sizing', 'border-box', 'important');

        table.querySelectorAll('col').forEach((col) => {
          col.removeAttribute('width');
          col.style.width = '';
        });

        table.querySelectorAll('td, th').forEach((cell) => {
          cell.removeAttribute('width');
          cell.style.setProperty('white-space', 'normal', 'important');
          cell.style.setProperty('word-break', 'break-word', 'important');
          cell.style.setProperty('overflow-wrap', 'anywhere', 'important');
          cell.style.setProperty('max-width', '100%', 'important');
          cell.style.setProperty('box-sizing', 'border-box', 'important');
        });
      });
    });
  }

  /**
   * Adapts section.docx width to the widest rendered child content,
   * while keeping it within available canvas width.
   * @param {HTMLElement} container - Render root that contains docx sections
   */
  adaptDocxSectionWidthToContent(container) {
    if (!container) return;

    const pageWrapper = container.querySelector('.page-wrapper') || container;
    const wrapperRect = pageWrapper.getBoundingClientRect();
    // Keep same visual side spacing used by canvas-page styling.
    const horizontalGap = 40;
    const maxAllowedWidth = Math.max(320, Math.floor(wrapperRect.width - horizontalGap));

    container.querySelectorAll('section.docx').forEach((section) => {
      let widestChild = 0;

      // Include section's own rendered width baseline.
      widestChild = Math.max(widestChild, section.scrollWidth || 0);

      section.querySelectorAll('table, img, pre, svg, article > *').forEach((el) => {
        widestChild = Math.max(widestChild, el.scrollWidth || 0);
      });

      const targetWidth = Math.min(Math.max(0, widestChild), maxAllowedWidth);
      if (targetWidth > 0) {
        section.style.setProperty('width', `${targetWidth}px`, 'important');
      } else {
        section.style.setProperty('width', '100%', 'important');
      }

      section.style.setProperty('max-width', '100%', 'important');
      section.style.setProperty('box-sizing', 'border-box', 'important');
      section.style.setProperty('margin-left', 'auto', 'important');
      section.style.setProperty('margin-right', 'auto', 'important');
    });
  }

  /**
   * Resets z-index values that exceed 9000 to prevent layout issues
   * @param {HTMLElement} container - Container element to search within
   */
  resetHighZIndex(container) {
    if (!container) return;

    // Get all elements within the container
    const allElements = container.querySelectorAll('*');
    let resetCount = 0;

    allElements.forEach(element => {
      // Get computed z-index value
      const computedStyle = window.getComputedStyle(element);
      const zIndex = computedStyle.zIndex;

      // Check if z-index is a number and exceeds 9000
      if (zIndex !== 'auto' && zIndex !== 'inherit' && zIndex !== 'initial' && zIndex !== 'unset') {
        const zIndexValue = parseInt(zIndex, 10);
        if (!isNaN(zIndexValue) && zIndexValue > 9000) {
          element.style.setProperty('z-index', 'auto', 'important');
          resetCount++;
        }
      }

      // Also check inline styles
      const inlineZIndex = element.style.zIndex;
      if (inlineZIndex) {
        const inlineZIndexValue = parseInt(inlineZIndex, 10);
        if (!isNaN(inlineZIndexValue) && inlineZIndexValue > 9000) {
          element.style.setProperty('z-index', 'auto', 'important');
          resetCount++;
        }
      }
    });

    if (resetCount > 0) {
      // Elements with z-index > 9000 have been reset
    }
  }

  @track showPreviewModal = false;
  @track JSONdata;



  // TODO: Remove this code
  // previewTemplate() {
  //   this.loading = true;

  //   // Create a temporary container for processing
  //   let div = document.createElement('div');
  //   div.innerHTML = this.querySelector('.page-wrapper').innerHTML;
  //   //after each section.docx add <div class="page-break"></div>
  //   div.querySelectorAll('section.docx').forEach(section => {
  //     section.classList.remove('canvas-page');
  //     section.querySelectorAll('article').forEach(article => {
  //       for (let child of article.children) {
  //         child.classList.remove('selectable-element');
  //         child.classList.remove('selected');
  //       }
  //     });
  //     // section.querySelectorAll('footer').classList.remove('myFooter');
  //     // section.insertAdjacentHTML('afterend', '<div class="page-break" style="break-after: page !important; page-break-after: always !important; height: 0; display: block;"></div>');
  //   });
  //   try {
  //     const pageWrapper = this.querySelector('.page-wrapper');
  //     if (!pageWrapper) {
  //       throw new Error('Page wrapper not found');
  //     }

  //     // Handlebars.unregisterHelper('helperMissing');

  //     //collect all the

  //     // Compile the template - this can throw if there are Handlebars syntax errors
  //     this.handleBarsCompileUtility(div.querySelector('.docx-wrapper').innerHTML, true);

  //     // Execute the template with JSON data
  //     div.querySelector('.docx-wrapper').innerHTML = this.template(this.jsonData || {});

  //     // div.querySelector('style#custom-styles').remove();

  //     this.JSONdata = div.innerHTML;

  //     // Convert HTML string to ArrayBuffer for postMessage
  //     const encoder = new TextEncoder();
  //     const arrayBuffer = encoder.encode(this.JSONdata).buffer;

  //     // Wait for iframe to be ready
  //     setTimeout(() => {
  //       const vfIframe = this.querySelector('.iframe');

  //       if (!vfIframe) {
  //         console.error('Iframe element not found in DOM');
  //         this.showToastMessage('Error', 'VF Page iframe not found', 'error');
  //         this.loading = false;
  //         return;
  //       }

  //       if (!vfIframe.contentWindow) {
  //         console.error('Iframe contentWindow not accessible');
  //         this.showToastMessage('Error', 'Cannot access VF Page iframe', 'error');
  //         this.loading = false;
  //         return;
  //       }

  //       // Define message
  //       const message = {
  //         type: 'GENERATE_PDF',
  //         message: arrayBuffer,
  //         pageDimensions: this.pageDimensions
  //       };

  //       // Post message to iframe
  //       vfIframe.contentWindow.postMessage(message, '*');

  //     }, 2000); // Increased timeout to ensure iframe is fully loaded
  //     // this.querySelector('.page-wrapper').style.display = 'none';

  //     // Clear any previous errors if preview succeeds
  //     this.clearJsonValidity();

  //   } catch (e) {
  //     // Surface the error to the user
  //     console.error('[pdfTemplateBuilder] Preview compile failed:', e);
  //     console.error('[pdfTemplateBuilder] Preview compile error details:', {
  //       errorMessage: e.message,
  //       errorStack: e.stack,
  //       errorName: e.name,
  //       pageWrapperExists: !!this.querySelector('.page-wrapper'),
  //       pageWrapperInnerHTML: this.querySelector('.page-wrapper')?.innerHTML?.substring(0, 500),
  //       jsonDataExists: !!this.jsonData,
  //       jsonDataType: typeof this.jsonData,
  //       jsonDataKeys: this.jsonData ? Object.keys(this.jsonData) : null,
  //       templateExists: !!this.template,
  //       templateType: typeof this.template,
  //       handlebarsVersion: typeof Handlebars !== 'undefined' ? 'loaded' : 'not loaded'
  //     });

  //     // Report the error with line number if available
  //     const errorMessage = e?.message || 'Preview compilation failed';
  //     const lineNumber = this.extractLineNumberFromError(e);
  //     this.reportValidityCheck(`Preview error: ${errorMessage}`, lineNumber);
  //     this.showToastMessage('Preview Error', `Failed to compile template for preview: ${errorMessage}`, 'error');

  //     // Don't open preview modal if compilation failed
  //     this.loading = false;
  //     return;
  //   }

  //   this.loading = false;
  //   // this.showPreviewModal = true;
  // }
  // Removing this code

  get disableSaveTemplateButton() {
    return this.renderer ? false : true
  }




  handlePDFModalClose() {
    this.showPreviewModal = false;
    this.querySelector('.page-wrapper').style.display = 'block';
    this.loading = false;
    this.jsonData = '';
  }

  jsonToBase64 = (jsonObj) => {

    return new Promise((resolve, reject) => {
      // 1. Convert Object to String
      const jsonString = JSON.stringify(jsonObj);

      // 2. Make it a Blob (handling UTF-8 automatically)
      const blob = new Blob([jsonString], { type: 'application/json' });

      // 3. Use FileReader
      const reader = new FileReader();
      reader.readAsDataURL(blob);

      reader.onloadend = () => {
        // The result is "data:application/json;base64,YOUR_BASE64..."
        const base64data = reader.result;

        // Strip the metadata prefix to get just the Base64
        const base64 = base64data.split(',')[1];
        resolve(base64);
      };

      reader.onerror = reject;
    });
  };


  @track jsonText = '{ }';
  @track jsonErrorLine = null;


  contextMenuHandler(event) {
    // Handles both right-click (contextmenu) and left-click (click)
    if (event?.type === 'contextmenu') {
      event.preventDefault();
    }
    event.stopPropagation();

    const sectionEl = event.currentTarget;
    const x = event.clientX ?? 0;
    const y = event.clientY ?? 0;

    this._activeSectionEl = sectionEl;
    this._sectionMenuClientX = x;
    this._sectionMenuClientY = y;
    this.showSectionContextMenu({ x, y });
  }

  // Back-compat: template currently references this handler.
  handleSectionRightClick(event) {
    this.contextMenuHandler(event);
  }

  get sectionContextMenuItemsForRender() {
    const items = Array.isArray(this.sectionContextMenuItems) ? this.sectionContextMenuItems : [];
    return items
      .filter((i) => i && (i.id || i.action) && i.label && i.action)
      .map((i) => ({
        id: i.id ?? i.action,
        label: i.label,
        action: i.action,
        disabled: !!i.disabled,
        className: `section-context-menu-item${i.disabled ? ' is-disabled' : ''}`
      }));
  }

  get elementContextMenuItemsForRender() {
    const items = Array.isArray(this.elementContextMenuItems) ? this.elementContextMenuItems : [];
    return items
      .filter((i) => i && (i.id || i.action) && i.label && i.action)
      .map((i) => ({
        id: i.id ?? i.action,
        label: i.label,
        action: i.action,
        disabled: !!i.disabled,
        className: `element-context-menu-item${i.disabled ? ' is-disabled' : ''}`
      }));
  }

  showSectionContextMenu({ x, y }) {
    const menu = this.querySelector('[data-section-context-menu]');
    if (!menu) return;

    // Display first so we can measure.
    menu.style.display = 'block';
    this._sectionMenuOpen = true;

    const menuRect = menu.getBoundingClientRect();
    const margin = 8;
    const maxLeft = window.innerWidth - menuRect.width - margin;
    const maxTop = window.innerHeight - menuRect.height - margin;

    const left = Math.max(margin, Math.min(x, maxLeft));
    const top = Math.max(margin, Math.min(y, maxTop));

    menu.style.left = `${left}px`;
    menu.style.top = `${top}px`;
  }

  hideSectionContextMenu() {
    const menu = this.querySelector('[data-section-context-menu]');
    if (menu) {
      menu.style.display = 'none';
    }
    this._sectionMenuOpen = false;
  }

  showElementContextMenu({ x, y }) {
    const menu = this.querySelector('[data-element-context-menu]');
    if (!menu) return;

    menu.style.display = 'block';
    this._elementMenuOpen = true;

    const menuRect = menu.getBoundingClientRect();
    const margin = 8;
    const maxLeft = window.innerWidth - menuRect.width - margin;
    const maxTop = window.innerHeight - menuRect.height - margin;

    const left = Math.max(margin, Math.min(x, maxLeft));
    const top = Math.max(margin, Math.min(y, maxTop));

    menu.style.left = `${left}px`;
    menu.style.top = `${top}px`;
  }

  hideElementContextMenu() {
    const menu = this.querySelector('[data-element-context-menu]');
    if (menu) {
      menu.style.display = 'none';
    }
    this._elementMenuOpen = false;
  }
  handleElementContextMenuPointerDown(event) {
    event.stopPropagation();
  }

  handleElementContextMenuClick(event) {
    const path = event.composedPath ? event.composedPath() : [event.target];
    const itemEl = path.find(node => node.nodeType === Node.ELEMENT_NODE && node.dataset && node.dataset.action) || event.target?.closest?.('[data-action]');
    if (itemEl && event.currentTarget && itemEl !== event.currentTarget) return;
    const action = itemEl?.dataset?.action;
    const item = (this.elementContextMenuItemsForRender || []).find((i) => i.action === action);
    if (!action || item?.disabled) return;
    if (!this._activeElementEl) return;

    const index = Array.from(this._activeElementEl.parentNode.children).indexOf(this._activeElementEl);

    switch (action) {
      case 'insertPageBreakBefore': {
        const section = this._activeElementEl.parentNode.parentElement;
        // const header = section.querySelector('header'); //Removing header clone so that in final render duplicate repeated header is not created
        const footer = section.querySelector('footer');
        const article = this._activeElementEl.parentNode.nodeName === 'ARTICLE' && this._activeElementEl.parentNode;
        if (!article) break;
        if (index < 0) break;

        let indexToInsertBreak = index - 1;
        if (indexToInsertBreak < 0) break; //Later show message as page break cannot be inserted before the first element
        // Elements to move to new section (from active element to end)
        const elementsAfter = Array.from(this._activeElementEl.parentNode.children).slice(index);

        let clonedSection = section.cloneNode(false);
        // let clonedHeader = header ? header.cloneNode(true) : null;
        let clonedFooter = footer ? footer.cloneNode(true) : null;
        let clonedArticle = this._activeElementEl.parentNode.cloneNode(false);
        elementsAfter.map(el => clonedArticle.appendChild(el));
        // if (clonedHeader) {
        //   clonedSection.appendChild(clonedHeader);
        // }
        clonedSection.appendChild(clonedArticle);
        if (clonedFooter) {
          clonedSection.appendChild(clonedFooter);
        }
        section.after(clonedSection);
        this.makeArticleChildrenSelectable(clonedArticle, clonedSection);

        // // Clone section (already includes header, article, footer with their structure)
        // const newSection = section.cloneNode(true);
        // const newArticle = newSection.querySelector('article');

        // // Clear cloned article - it has duplicated content; we only want elementsAfter
        // while (newArticle.firstChild) {
        //   newArticle.removeChild(newArticle.firstChild);
        // }

        // // Move elements from current article to new article (appendChild moves DOM nodes)
        // elementsAfter.forEach((el) => newArticle.appendChild(el));

        // // Insert new section after current section
        // this.querySelector('docx-wrapper').insertBefore(newSection, section.nextSibling);

        // // Re-attach selectable + context menu to new section
        // this.makeArticleChildrenSelectable(newArticle, newSection);
        // newSection.classList.add('canvas-page');
        break;
      }

      case 'moveElement': {
        const targetEl = this._activeElementEl;
        // Use the enclosing section.docx as the moveable root. It is
        // forced position:relative by our injected CSS and reliably
        // contains both <header>/<footer> and <article> children, so the
        // control box positions correctly for all selectable targets.
        const sectionEl =
          this._activeElementSectionEl || targetEl.closest?.('section.docx');
        if (!targetEl || !sectionEl) break;

        this.destroyMoveableInstance();

        const moveable = new Moveable(sectionEl, {
          target: targetEl,
          draggable: true,
          resizable: true,
          rotatable: true,
          warpable: false,
          snappable: true,
          pinchable: false,
          origin: false,
          keepRatio: false,
          edge: true,
          renderDirections: ['n', 'nw', 'ne', 's', 'sw', 'se', 'w', 'e'],
          throttleDrag: 0,
          throttleResize: 0,
          throttleRotate: 0,
          verticalGuidelines: [100, 200, 500],
          horizontalGuidelines: [100, 200, 500],
        });

        this._moveableInstance = moveable;
        this._moveableTarget = targetEl;
        this._moveableContainer = sectionEl;
        this.moveableInitialized = true;
        this.hideElementContextMenu();
        this.hideSectionContextMenu();

        // Transform-based dragging: works regardless of the target's
        // CSS position (header/footer come back from docx-preview as
        // position:absolute, which made left/top dragging unreliable).
        let baseTransform = '';
        moveable
          .on('dragStart', ({ set }) => {
            baseTransform = (targetEl.style.transform || '')
              .replace(/translate(?:3d)?\([^)]*\)/g, '')
              .trim();
            set([0, 0]);
          })
          .on('drag', ({ target, beforeTranslate }) => {
            const [tx, ty] = beforeTranslate || [0, 0];
            const translate = `translate(${tx}px, ${ty}px)`;
            target.style.transform = baseTransform
              ? `${baseTransform} ${translate}`
              : translate;
          });

        moveable
          .on('resize', ({ target, width, height, delta }) => {
            if (delta[0]) target.style.width = `${width}px`;
            if (delta[1]) target.style.height = `${height}px`;
          });

        moveable.on('rotate', ({ target, transform }) => {
          target.style.transform = transform;
        });

        break;
      }

      case 'editElement':
        this.openEditElementModal(this._activeElementEl, this._activeElementSectionEl);
        this.hideElementContextMenu();
        this.hideSectionContextMenu();
        break;

      case 'duplicateElement':

        let currentElement = this._activeElementEl;
        //if current Element is header tag return
        if (this._activeElementEl.tagName === 'HEADER') {
          this.showToastMessage('Error', 'Header tag cannot be duplicated', 'error');
          return;
        }
        //if current Element is footer tag return
        if (this._activeElementEl.tagName === 'FOOTER') {
          this.showToastMessage('Error', 'Footer tag cannot be duplicated', 'error');
          return;
        }
        let currentArticle = this._activeElementEl.parentNode;
        if (!currentArticle) break;
        let clonedElement = currentElement.cloneNode(true);

        // insert thc cloned Element right after the current Element
        currentArticle.insertBefore(clonedElement, currentElement.nextSibling);
        const currentSection = currentArticle.closest('section.docx');
        this.makeArticleChildrenSelectable(currentArticle, currentSection);

        break;


      case 'deleteElement':
        let deleteElement = this._activeElementEl;
        let deleteArticle = this._activeElementEl.parentNode;
        if (!deleteArticle) break;
        deleteArticle.removeChild(deleteElement);
        break;

      case 'sortElement':
        let sortArticle = this._activeElementEl.parentNode;
        if (!sortArticle) break;
        if (typeof window.Sortable === 'undefined') break;
        this.destroyMoveableInstance();
        this.destroySortElementInstances();
        const sortDocxWrapper = this.querySelector('.page-wrapper')?.querySelector('.docx-wrapper');
        if (!sortDocxWrapper) break;
        sortDocxWrapper.querySelectorAll('section.docx article').forEach((articleEl) => {
          const sortable = window.Sortable.create(articleEl, {
            group: {
              name: 'sectionDocxSort',
              pull: true,
              put: true
            },
            animation: 150,
            draggable: '.selectable-element'
          });
          this._sortElementInstances.push(sortable);
        });
        break;


      case 'addToAllPages':
        //check if the current Element is not header or footer, else return
        if (this._activeElementEl.parentNode.tagName === 'article') {
          this.showToastMessage('Error', 'Only Header or Footer tag can be added to all pages', 'error');
          return;
        }

        let clonedHeaerOrFooterElement = this._activeElementEl.cloneNode(true);
        //query for all section.docx other than the current section
        let allSections = this.querySelector('.page-wrapper').querySelectorAll('section.docx');
        allSections.forEach((section) => {
          // if (section !== this._activeElementSectionEl) {
          //for each section if there is header replace the header, if there is footer replace the footer and make sure inside the section the order remains as Header,arctcle and footer
          let header = section.querySelector('header');
          let footer = section.querySelector('footer');
          let article = section.querySelector('article');
          if (this._activeElementEl.tagName === 'HEADER') {
            if (header) {
              header.replaceChild(clonedHeaerOrFooterElement);
            } else {
              section.insertBefore(clonedHeaerOrFooterElement, article);
            }
          }

          if (this._activeElementEl.tagName === 'FOOTER') {
            if (footer) {
              footer.replaceChild(clonedHeaerOrFooterElement);
            } else {
              section.appendChild(clonedHeaerOrFooterElement);
            }
          }
          // }
        });

        break;

      default:
        break;
    }
    this.dispatchEvent(
      new CustomEvent('elementmenuaction', {
        bubbles: true,
        composed: true,
        detail: {
          action,
          element: this._activeElementEl,
          sectionEl: this._activeElementSectionEl,
          clientX: this._elementMenuClientX,
          clientY: this._elementMenuClientY
        }
      })
    );

    this.hideElementContextMenu();
  }

  /**
   * Resolves a selectable element to a live DOM node (handles nodes replaced after Edit Element save).
   * @param {HTMLElement} element
   * @param {HTMLElement} sectionEl
   * @returns {{ element: HTMLElement, sectionEl: HTMLElement } | null}
   */
  _resolveLiveEditElement(element, sectionEl) {
    if (element?.isConnected) {
      return {
        element,
        sectionEl: sectionEl || element.closest?.('section.docx')
      };
    }
    const selected = this.selectedElement;
    if (selected?.isConnected) {
      return {
        element: selected,
        sectionEl: selected.closest?.('section.docx') || sectionEl
      };
    }
    return null;
  }

  /**
   * Reads the editable HTML source for an element or its edit-element wrapper.
   * Prefers the in-DOM <template> (authoritative, no attribute size limits).
   * @param {HTMLElement} element
   * @returns {string}
   */
  _extractEditElementHtml(element) {
    if (!element) return '';

    const wrapper = element.hasAttribute?.('data-edit-element-wrapper')
      ? element
      : element.closest?.('[data-edit-element-wrapper]');

    if (wrapper) {
      const template = wrapper.querySelector('template');
      if (template) {
        return template.innerHTML;
      }
      const rawEncoded = wrapper.getAttribute('data-edit-element-html');
      if (rawEncoded) {
        try {
          return decodeURIComponent(rawEncoded);
        } catch (e) {
          // Fall through to outerHTML.
        }
      }
      return wrapper.outerHTML;
    }

    return element.outerHTML;
  }

  /**
   * Persists the current bare-document canvas into OrignalHtmlContent so edits survive reload/save.
   */
  _syncAuthoringHtmlFromLiveDom() {
    if (this.renderer) return;
    const pageWrapper = this.querySelector('.page-wrapper');
    if (!pageWrapper) return;
    this.OrignalHtmlContent = this.takeCleanSnapshot(pageWrapper);
  }

  /**
   * Opens the Edit Element modal with the element's HTML in a code editor.
   * If the element is an edit-element wrapper (or a child of one), extracts the
   * template's innerHTML for editing so re-editing does not duplicate the template.
   * @param {HTMLElement} element - The selectable element to edit
   * @param {HTMLElement} sectionEl - The section.docx container
   */
  async openEditElementModal(element, sectionEl) {
    const resolved = this._resolveLiveEditElement(element, sectionEl);
    if (!resolved?.element || !resolved?.sectionEl) return;

    element = resolved.element;
    sectionEl = resolved.sectionEl;

    const wrapper = element.hasAttribute?.('data-edit-element-wrapper')
      ? element
      : element.closest?.('[data-edit-element-wrapper]');
    const elementToEdit = wrapper || element;
    const htmlToEdit = this._extractEditElementHtml(element);

    this._editElementEl = elementToEdit;
    this._editElementSectionEl = sectionEl;
    this.editElementHtml = this.prettifyHtml(htmlToEdit);
    this._cmHtmlInitialized = false;

    // Load CodeMirror HTML mode if not already loaded
    if (!this._htmlModeLoaded) {
      try {
        await loadScript(this, CODEMIRROR + '/xml.js');
        await loadScript(this, CODEMIRROR + '/css.js');
        await loadScript(this, CODEMIRROR + '/htmlmixed.js');
        this._htmlModeLoaded = true;
      } catch (e) {
        console.error('[Edit Element] Failed to load HTML mode:', e);
      }
    }

    this.showEditElementModal = true;
    requestAnimationFrame(() => {
      requestAnimationFrame(() => this.initEditElementCodeMirror(true));
    });
  }

  prettifyHtml(html) {
    if (!html || !html.trim()) return html;
    try {
      const div = document.createElement('div');
      div.innerHTML = html.trim();
      const nodes = Array.from(div.childNodes);
      if (nodes.length === 0) return html.trim();

      const lines = [];
      for (const node of nodes) {
        if (node.nodeType === Node.TEXT_NODE) {
          const text = node.textContent.trim();
          if (text) lines.push(text);
        } else if (node.nodeType === Node.ELEMENT_NODE) {
          lines.push(this._formatHtmlElement(node, 0));
        } else if (node.nodeType === Node.COMMENT_NODE) {
          lines.push(`<!--${node.textContent}-->`);
        }
      }

      return lines.length ? lines.join('\n') : html.trim();
    } catch (e) {
      return html;
    }
  }

  _formatHtmlElement(el, indent) {
    const spaces = '  '.repeat(indent);
    const tag = el.tagName.toLowerCase();
    const voidTags = ['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'];
    const attrStr = Array.from(el.attributes)
      .map(a => (a.value ? `${a.name}="${String(a.value).replace(/"/g, '&quot;')}"` : a.name))
      .join(' ');
    const attrs = attrStr ? ' ' + attrStr : '';

    const children = Array.from(el.childNodes);
    const hasOnlyText = children.length === 1 && children[0].nodeType === Node.TEXT_NODE;
    const textContent = hasOnlyText ? children[0].textContent.trim() : '';

    if (voidTags.includes(tag)) {
      return `${spaces}<${tag}${attrs}>`;
    }
    if (children.length === 0) {
      return `${spaces}<${tag}${attrs}></${tag}>`;
    }
    if (hasOnlyText && textContent.length < 80) {
      return `${spaces}<${tag}${attrs}>${textContent}</${tag}>`;
    }

    const childLines = [];
    for (const child of children) {
      if (child.nodeType === Node.TEXT_NODE) {
        const t = child.textContent.trim();
        if (t) childLines.push('  '.repeat(indent + 1) + t);
      } else if (child.nodeType === Node.ELEMENT_NODE) {
        childLines.push(this._formatHtmlElement(child, indent + 1));
      }
    }
    return `${spaces}<${tag}${attrs}>\n${childLines.join('\n')}\n${spaces}</${tag}>`;
  }

  /**
   * Wraps invalid table children so the browser doesn't hoist them outside the table.
   * Handles:
   * 1. Elements (span, div, p, etc.) before or between tr tags
   * 2. Handlebars blocks ({{#name}} and {{/name}}) that would be hoisted as text nodes
   */
  fixTableInvalidChildren(html) {
    let result = html;
    const hiddenRowStyle = 'style="display:none;height:0;line-height:0;border:none"';
    const hiddenCellStyle = 'style="border:none;padding:0;height:0;line-height:0;overflow:hidden"';

    const wrapInRow = (content) => `<tr ${hiddenRowStyle}><td ${hiddenCellStyle}>${content}</td></tr>`;

    let prev = '';
    while (prev !== result) {
      prev = result;

      for (const tag of ['span', 'div', 'p', 'a', 'strong', 'em', 'b', 'i']) {
        const beforeTr = new RegExp(
          `(<table[^>]*>)(\\s*)(<${tag}(\\s[^>]*)?>([\\s\\S]*?)<\\/${tag}>)(\\s*)(?=<(?:tr|tbody|thead|tfoot|colgroup|caption))`,
          'gi'
        );
        result = result.replace(beforeTr, (_, tableOpen, space1, _fullTag, tagAttrs, tagContent, space2) => {
          const attrs = tagAttrs || '';
          return `${tableOpen}${space1}<tr><td><${tag}${attrs}>${tagContent}</${tag}></td></tr>${space2}`;
        });

        const betweenTrs = new RegExp(
          `(</tr>)(\\s*)(<${tag}(\\s[^>]*)?>([\\s\\S]*?)<\\/${tag}>)(\\s*)(<tr)`,
          'gi'
        );
        result = result.replace(betweenTrs, (_, closeTr, space1, _fullTag, tagAttrs, tagContent, space2, openTr) => {
          const attrs = tagAttrs || '';
          return `${closeTr}${space1}<tr><td><${tag}${attrs}>${tagContent}</${tag}></td></tr>${space2}${openTr}`;
        });
      }

      const hbBlock = '\\{\\{[#^/][^}]*\\}\\}';
      result = result.replace(
        new RegExp('(<table[^>]*>)(\\s*)(' + hbBlock + ')(\\s*)(?=<(?:tr|tbody|thead|tfoot))', 'gi'),
        (_, tableOpen, space1, hb, space2) =>
          `${tableOpen}${space1}${wrapInRow(hb)}${space2}`
      );
      result = result.replace(
        new RegExp('(<(?:tbody|thead|tfoot)[^>]*>)(\\s*)(' + hbBlock + ')(\\s*)(?=<tr)', 'gi'),
        (_, sectionOpen, space1, hb, space2) =>
          `${sectionOpen}${space1}${wrapInRow(hb)}${space2}`
      );
      result = result.replace(
        new RegExp('(</tr>)(\\s*)(' + hbBlock + ')(\\s*)(<tr)', 'gi'),
        (_, closeTr, space1, hb, space2, openTr) =>
          `${closeTr}${space1}${wrapInRow(hb)}${space2}${openTr}`
      );
      result = result.replace(
        new RegExp('(</tr>)(\\s*)(' + hbBlock + ')(\\s*)(</(?:tbody|thead|tfoot|table)>)', 'gi'),
        (_, closeTr, space1, hb, space2, closeTag) =>
          `${closeTr}${space1}${wrapInRow(hb)}${space2}${closeTag}`
      );
    }
    return result;
  }

  sanitizeEditedHtml(html, doc) {
    let out = String(html || '');

    // Remove executable/scriptable containers without DOM parsing
    // so Handlebars tags remain byte-for-byte intact.
    out = out.replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, '');
    out = out.replace(/<noscript[\s\S]*?>[\s\S]*?<\/noscript>/gi, '');
    out = out.replace(/<iframe[\s\S]*?>[\s\S]*?<\/iframe>/gi, '');
    out = out.replace(/<object[\s\S]*?>[\s\S]*?<\/object>/gi, '');
    out = out.replace(/<embed\b[^>]*>/gi, '');

    // Strip inline JS handlers (on*)
    out = out.replace(/\s+on[a-zA-Z0-9_-]+\s*=\s*"[^"]*"/g, '');
    out = out.replace(/\s+on[a-zA-Z0-9_-]+\s*=\s*'[^']*'/g, '');
    out = out.replace(/\s+on[a-zA-Z0-9_-]+\s*=\s*[^\s>]+/g, '');

    // Strip javascript: URLs from common URL attributes
    out = out.replace(/\s+(href|src|xlink:href|formaction)\s*=\s*"javascript:[^"]*"/gi, '');
    out = out.replace(/\s+(href|src|xlink:href|formaction)\s*=\s*'javascript:[^']*'/gi, '');
    out = out.replace(/\s+(href|src|xlink:href|formaction)\s*=\s*javascript:[^\s>]+/gi, '');

    return out;
  }

  stripHandlebarsBlockTagsForPreview(html) {
    if (!html) return html;
    // Keep variable tokens, remove control block tokens that break table parsing/rendering.
    return html
      .replace(/\{\{\s*[#\/\^][^}]*\}\}/g, '')
      .replace(/\{\{\s*else\s*\}\}/g, '');
  }

  handleEditElementModalSave() {
    if (!this.cmHtmlInstance || !this._editElementEl || !this._editElementSectionEl) {
      this.closeEditElementModal();
      return;
    }
    const editedHtml = this.cmHtmlInstance.getValue().trim();
    if (!editedHtml) {
      this.closeEditElementModal();
      return;
    }

    const elementToReplace = this._editElementEl;
    const parent = elementToReplace.parentNode;
    const nextSibling = elementToReplace.nextSibling;
    const sectionEl = this._editElementSectionEl;
    const article = sectionEl ? sectionEl.querySelector('article') : null;

    if (!parent) {
      this.closeEditElementModal();
      return;
    }

    try {
      const doc = elementToReplace.ownerDocument;
      const sanitizedHtml = this.sanitizeEditedHtml(editedHtml, doc);
      const htmlToParse = this.fixTableInvalidChildren(sanitizedHtml);
      const htmlForPreview = this.fixTableInvalidChildren(this.stripHandlebarsBlockTagsForPreview(sanitizedHtml));

      // Create wrapper with template (preserves edited HTML) + cloned content (visible)
      const editWrapper = doc.createElement('div');
      editWrapper.setAttribute('data-edit-element-wrapper', 'true');
      editWrapper.setAttribute('data-edit-element-html', encodeURIComponent(htmlToParse));
      editWrapper.style.display = 'contents'; // Avoid affecting layout (e.g. inside tables)

      const templateEl = doc.createElement('template');
      templateEl.innerHTML = htmlToParse;

      // Build visible clone from block-tag-free HTML to prevent browser hoisting around tables.
      const previewTemplateEl = doc.createElement('template');
      previewTemplateEl.innerHTML = htmlForPreview;
      const clone = previewTemplateEl.content.cloneNode(true);
      editWrapper.appendChild(templateEl);
      editWrapper.appendChild(clone);

      parent.removeChild(elementToReplace);
      parent.insertBefore(editWrapper, nextSibling);

      // Keep context-menu / re-edit targets on the live wrapper, not the removed node.
      this._activeElementEl = editWrapper;
      this._activeElementSectionEl = sectionEl;

      if (article) {
        this.makeArticleChildrenSelectable(article, sectionEl);
      }
      this._syncAuthoringHtmlFromLiveDom();
      this.deselectElement();
    } catch (e) {
      console.error('[Edit Element] Failed to apply HTML:', e);
      this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Failed to apply HTML: ' + (e?.message || 'Unknown error'), variant: 'error' }));
    }
    this.closeEditElementModal();
  }

  closeEditElementModal() {
    if (this._cmHtmlDragBlocker) {
      const { wrapper, blockDrag } = this._cmHtmlDragBlocker;
      try {
        wrapper.removeEventListener('dragstart', blockDrag, true);
        wrapper.removeEventListener('dragover', blockDrag, true);
        wrapper.removeEventListener('drop', blockDrag, true);
      } catch (e) { /* no-op */ }
      this._cmHtmlDragBlocker = null;
    }
    if (this.cmHtmlInstance) {
      try {
        this.cmHtmlInstance.toTextArea();
      } catch (e) { /* no-op */ }
      this.cmHtmlInstance = null;
    }
    this._cmHtmlInitialized = false;
    this._editElementEl = null;
    this._editElementSectionEl = null;
    this.showEditElementModal = false;
    this.deselectElement();
  }

  handleEditElementModalCancel() {
    this.closeEditElementModal();
  }

  handleSectionContextMenuItemClick(event) {
    const action = event?.currentTarget?.dataset?.action;
    const item = (this.sectionContextMenuItemsForRender || []).find((i) => i.action === action);
    if (!action || item?.disabled) return;

    // Internal routing (optional)
    if (action === 'log') {
      // Log section menu action
    }

    // External routing: parent can listen to this.
    this.dispatchEvent(
      new CustomEvent('sectionmenuaction', {
        bubbles: true,
        composed: true,
        detail: {
          action,
          sectionEl: this._activeSectionEl,
          clientX: this._sectionMenuClientX,
          clientY: this._sectionMenuClientY
        }
      })
    );

    this.hideSectionContextMenu();
  }


  @track docxPreviewContent = '';
  @track originalViewSnapshotHtml = '';
  get canvasWorkspaceClass() {
    return `canvas-workspace${this.pagedViewer ? ' paged-viewer-active' : ''}`;
  }

  get pagesContainerClass() {
    return `pages-container${this.pagedViewer ? ' paged-viewer-active' : ''}`;
  }

  scrollBuilderCanvasToTop() {
    const canvasWorkspace = this.querySelector('.canvas-workspace');
    if (canvasWorkspace) {
      canvasWorkspace.scrollTop = 0;
    }

    const pagesContainer = this.querySelector('.pages-container');
    if (pagesContainer) {
      pagesContainer.scrollTop = 0;
    }
  }

  togglePagedViewer(event) {
    if (this.pagedViewer === true) {
      this.loading = true;
      // this.renderer = false;
      // this.toggleDocumentRenderer();

      requestAnimationFrame(() => {
        let currentPage = this.querySelector('.page-wrapper');
        if (currentPage) {
          // Same reasoning as the load path: insertAdjacentHTML appends, so
          // toggling Preview on/off repeatedly would otherwise stack a full
          // copy of OrignalHtmlContent into the wrapper every time.
          currentPage.replaceChildren();
          currentPage.insertAdjacentHTML('beforeend', this.OrignalHtmlContent);

          // Wait one more frame to ensure DOM is fully updated
          requestAnimationFrame(() => {
            this.handleBarsCompileUtility(currentPage.querySelector('.docx-wrapper').innerHTML);

            if (this.renderer === true) {
              currentPage.querySelector('.docx-wrapper').innerHTML = this.template(this.jsonData || {});
            }

            requestAnimationFrame(() => {
              currentPage.querySelectorAll('section.docx').forEach((section) => {
                section.classList.add('canvas-page');
                // const article = section.querySelector('article');
                // if (article) this.makeArticleChildrenSelectable(article, section);
              });
              this.initSortableForSections();
              this.initComponentsSortable();
            });
          });
        }
      });

      this.loading = false;
    }
    this.pagedViewer = event.target.checked;


  }

  handlePagedJSCompleted(event) {
    let painatedView = event.detail.pagedView;
    this.querySelector('.page-wrapper').insertAdjacentElement('beforeend', painatedView);
  }

  @track renderer = true;

  toggleDocumentRenderer() {
    if (this.renderer === true) {

      this.querySelector('.page-wrapper').innerHTML = this.OrignalHtmlContent;
      this.querySelector('.page-wrapper').querySelector('.docx-wrapper').querySelectorAll('section.docx').forEach(section => {
        const article = section.querySelector('article');
        if (article) {
          this.makeArticleChildrenSelectable(article, section);
        }
      });
      this.renderer = false;
      this.contentNotLoaded = true;
    } else {
      try {

        this.destroyMoveableInstance();
        // Snapshot must be CLEAN, not the live DOM. The live DOM has
        // selectable-element wrappers, .selected classes, contenteditable
        // attrs, and possibly moveable/sortable handles. If those bake into
        // OrignalHtmlContent, the next session reopens with them, we wrap
        // again, snapshot again -> wrappers compound across saves.
        const pageWrapper = this.querySelector('.page-wrapper');
        const cleanHtml = this.takeCleanSnapshot(pageWrapper);
        this.OrignalHtmlContent = cleanHtml;
        this.handleBarsCompileUtility(cleanHtml);
        this.querySelector('.page-wrapper').innerHTML = this.template(this.jsonData || {});

        this.renderer = true;
        this.contentNotLoaded = false;
      } catch (error) {
        console.error('Error toggling document renderer:', error);
        this.showToastMessage('Error', 'Error toggling document renderer', 'error');
      }
    }
  }

  /**
   * Yield to the browser's event loop so it gets a chance to paint a
   * frame (the CSS spinner repaints, layout updates, etc.). Uses
   * MessageChannel to bypass the ~4ms clamp setTimeout(0) has in most
   * browsers, while still being a single async hop.
   */
  _yieldToMainThread() {
    return new Promise((resolve) => {
      const channel = new MessageChannel();
      channel.port1.onmessage = () => resolve();
      channel.port2.postMessage(null);
    });
  }

  /**
   * Read a ZIP archive produced by `_zipPayloadAsync` (or any ZIP
   * containing a single JSON entry) and return the JSON text.
   *
   * JSZip.loadAsync handles parsing on a background-ish queue and
   * yields between work units, so we don't need a manual chunking
   * wrapper the way pako required.
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
        + 'Check that the JZIP static resource exposes the JSZip global.'
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
   * runtime errors with the actual library version that won the script
   * load race (DOCXPreview/jszip.min.js vs the JZIP static resource).
   */
  _logJsZipVersionOnce() {
    if (this._jsZipVersionLogged) return;
    this._jsZipVersionLogged = true;
    const v = (window.JSZip && window.JSZip.version) || '(unknown)';
    const support = (window.JSZip && window.JSZip.support) || null;
    console.log('[JSZip] version=', v, 'support=', support);
  }

  /* ===== LEGACY PAKO HELPERS — kept for easy revert =====================
   * These are no longer called by the save path. The LOAD path still
   * calls _ungzipChunkedAsync below for templates saved before the
   * JSZip cutover (".json.gz" files). Once every stored template has
   * been resaved (and therefore upgraded to ".json.zip"), this whole
   * block + the `loadScript(this, PAKO_JS)` call can be deleted.
   *
   * To fully revert to pako:
   *   1. uncomment the LEGACY block inside handleCompress() above
   *    and comment out its JSZip block.
   *   2. flip the extension in saveTemplate from '.json.zip' back
   *    to '.json.gz'.
   *   3. uncomment _gzipChunkedAsync below.
   * ====================================================================*/

  // /**
  //  * gzip a JSON string in fixed-size chunks, awaiting a frame between
  //  * each chunk so the main thread is free to repaint the CSS spinner
  //  * (and react to user input). Returns the same Uint8Array that
  //  * window.pako.gzip(jsonString, { level }) would produce.
  //  *
  //  * If pako's streaming Deflate API isn't available for some reason we
  //  * fall back to the original blocking call so behavior never regresses.
  //  */
  // async _gzipChunkedAsync(jsonString, { level = 9, chunkSize = 256 * 1024 } = {}) {
  //   if (!window.pako || typeof window.pako.Deflate !== 'function') {
  //     return window.pako.gzip(jsonString, { level });
  //   }
  //   const deflator = new window.pako.Deflate({ level, gzip: true });
  //   const bytes = new TextEncoder().encode(jsonString);
  //   for (let off = 0; off < bytes.length; off += chunkSize) {
  //     const end = Math.min(off + chunkSize, bytes.length);
  //     const isLast = end >= bytes.length;
  //     deflator.push(bytes.subarray(off, end), isLast);
  //     if (!isLast) {
  //       // eslint-disable-next-line no-await-in-loop
  //       await this._yieldToMainThread();
  //     }
  //   }
  //   if (deflator.err) {
  //     throw new Error(deflator.msg || 'gzip failed');
  //   }
  //   return deflator.result;
  // }

  /**
   * LEGACY (still active on the LOAD path): inflate gzip bytes to a
   * UTF-8 string in fixed-size chunks, awaiting a frame between each
   * chunk. Mirrors window.pako.ungzip(bytes, { to: 'string' }) output.
   *
   * Called from handleDecompress() when the bytes start with the gzip
   * magic 1F 8B (templates saved before the JSZip cutover). Safe to
   * delete only after every stored template has been re-saved.
   */
  async _ungzipChunkedAsync(bytes, { chunkSize = 256 * 1024 } = {}) {
    if (!window.pako || typeof window.pako.Inflate !== 'function') {
      return window.pako.ungzip(bytes, { to: 'string' });
    }
    const inflator = new window.pako.Inflate({ to: 'string' });
    for (let off = 0; off < bytes.length; off += chunkSize) {
      const end = Math.min(off + chunkSize, bytes.length);
      const isLast = end >= bytes.length;
      inflator.push(bytes.subarray(off, end), isLast);
      if (!isLast) {
        // eslint-disable-next-line no-await-in-loop
        await this._yieldToMainThread();
      }
    }
    if (inflator.err) {
      throw new Error(inflator.msg || 'gunzip failed');
    }
    return inflator.result;
  }

  /**
   * Walks `html`, finds inline base64 images, downscales/re-encodes the
   * big ones, and returns the rewritten HTML. SINGLE-FILE in, single-file
   * out — no extra ContentVersions, no extra ContentDocumentLinks, so the
   * Experience Cloud / Community sharing model stays identical.
   *
   * Behavior:
   *  - SVGs are skipped (vector; rasterizing would lose quality).
   *  - Animated GIFs are skipped (canvas only sees the first frame).
   *  - PNGs that actually use alpha stay PNGs; everything else becomes
   *    JPEG at `jpegQuality`.
   *  - Images whose underlying binary size is below `skipBelowBytes`
   *    (small icons, bullets, logos) are left untouched.
   *  - Duplicate data URLs are processed once and cached.
   *  - Yields between images so the spinner keeps animating.
   *
   * Returns the rewritten HTML, ready to be JSON.stringified and gzipped.
   */
  /**
   * Sanitize an HTML string into a form Salesforce's `Blob.toPdf`
   * (an XHTML-strict, iText-based parser) will accept.
   *
   * !!! RENDER-ONLY -- DO NOT CALL FROM saveTemplate() !!!
   *
   * Several of the passes below are DESTRUCTIVE and will break the
   * LWC builder's editor if the result is persisted. In particular:
   *   - pass (5) strips <style> blocks, which kills docxjs's
   *     preview CSS,
   *   - pass (6) renames HTML5 semantic elements (<section>,
   *     <header>, ...) to <div>, breaking any CSS selector that
   *     targets them by tag name,
   *   - pass (7) rewrites <img> data-URI MIMEs, which is harmless
   *     visually but mutates the user's source HTML.
   *
   * The persisted ContentVersion stays full-fidelity (Apex runs
   * the same nine passes at PDF-render time via
   * PdfRenderEmailHandler.sanitizeForBlobToPdf, against a throwaway
   * copy of the post-Handlebars output). Only invoke this method
   * when you're about to feed the output into a PDF generator and
   * are NOT going to store the result.
   *
   * Nine fixes, in order:
   *   1) Strip MS-Office conditional comments (`<!--[if …]>…<![endif]-->`).
   *      Word/Outlook paste leaves these behind; toPdf treats the
   *      nested HTML as outer-document markup and dies.
   *   2) Strip <script> / <noscript> blocks. Raw `<` / `&` in JS are
   *      not valid XHTML PCDATA and irrelevant in a PDF.
   *   3) Strip XML/Office-namespaced elements (`<o:p>`, `<v:shape>`,
   *      `<w:WordDocument>`, `<m:*>`, `<x:*>`). Tag name contains
   *      `:`; we unwrap so the text inside survives.
   *   4) Strip `xmlns` / `xmlns:*` attributes from every element.
   *      The `<html xmlns:o="...">` form makes some toPdf builds
   *      reject the document outright.
   *   5) Strip `<style>` blocks. The HTML body coming out of the
   *      builder still contains the docxjs CSS reset (~700 lines)
   *      and `@font-face` blocks. iText's XHTML strict mode allows
   *      `<style>` ONLY inside `<head>` -- a `<style>` in the body
   *      makes it die with the unhelpful "An error occurred while
   *      parsing the input string." Inline `style="..."` attributes
   *      survive on every element and carry the actual rendering.
   *   6) Rename HTML5 semantic elements (header, footer, article,
   *      section, nav, aside, main, figure, figcaption, details,
   *      summary) to `<div>`. iText's HTMLWorker / XHTML parser
   *      doesn't know them; they're another silent killer.
   *   7) Fix `<img>` data URIs declared as `application/octet-stream`
   *      (Word's docx-to-HTML export ships PNG/JPEG bytes with that
   *      generic MIME; toPdf can't embed it). We sniff the base64
   *      magic bytes and rewrite the MIME to the actual image type.
   *   8) Self-close void elements (`<br>`, `<hr>`, `<img>`, `<input>`,
   *      `<meta>`, `<link>`, `<col>`, `<area>`, `<base>`, `<embed>`,
   *      `<source>`, `<track>`, `<wbr>`). HTML5 / DOM innerHTML
   *      serialisation writes them open (`<br>`); XHTML requires
   *      self-closing (`<br/>`). Done on the serialised string
   *      because DOM nodes don't expose this choice.
   *   9) Escape stray `&` in attribute values (e.g. `href="?a=1&b=2"`)
   *      that aren't already a well-formed entity.
   *
   * Returns the cleaned HTML and logs a short diff summary so save-
   * time regressions are easy to spot in the console.
   */
  sanitizeHtmlForPdf(html) {
    if (typeof html !== 'string' || !html) return html;
    const t0 = performance.now();
    const inputLen = html.length;

    const div = document.createElement('div');
    div.innerHTML = html;

    // 1. Strip MSO conditional-comment nodes. TreeWalker is O(n)
    //    and avoids live-NodeList overhead.
    let strippedComments = 0;
    const tw = document.createTreeWalker(div, NodeFilter.SHOW_COMMENT);
    const commentsToRemove = [];
    let n = tw.nextNode();
    while (n) {
      const v = n.nodeValue || '';
      // Two flavors of MS conditional comment leak past Word export:
      //   <!--[if gte mso 9]>...<![endif]-->   (recognized by browsers)
      //   <!--[if !mso]><!-->...<!--<![endif]-->  (downlevel-revealed)
      if (/^\s*\[if\b/i.test(v) || /<!\[endif\]/i.test(v)) {
        commentsToRemove.push(n);
      }
      n = tw.nextNode();
    }
    for (const c of commentsToRemove) {
      c.parentNode && c.parentNode.removeChild(c);
      strippedComments++;
    }

    // 2. Strip <script> / <noscript> entirely.
    let strippedScripts = 0;
    for (const s of div.querySelectorAll('script, noscript')) {
      s.parentNode && s.parentNode.removeChild(s);
      strippedScripts++;
    }

    // 3. Unwrap namespaced Office tags. We can't query by `o:p`
    //    (CSS doesn't allow `:` in selectors without escaping), so
    //    we walk all elements and check tagName for ':'. Word's
    //    convention is a 1-2 letter prefix (o, v, w, m, x, st1).
    let unwrappedNs = 0;
    const allArr = Array.from(div.getElementsByTagName('*'));
    for (const el of allArr) {
      const tag = el.tagName || '';
      if (!tag.includes(':')) continue;
      const parent = el.parentNode;
      if (!parent) continue;
      while (el.firstChild) parent.insertBefore(el.firstChild, el);
      parent.removeChild(el);
      unwrappedNs++;
    }

    // 4. Strip xmlns / xmlns:* attributes from every remaining element.
    let strippedXmlns = 0;
    for (const el of div.getElementsByTagName('*')) {
      const names = el.getAttributeNames();
      for (const a of names) {
        if (a === 'xmlns' || a.startsWith('xmlns:')) {
          el.removeAttribute(a);
          strippedXmlns++;
        }
      }
    }

    // 5. Strip <style> blocks. Body-level <style> is invalid XHTML
    //    and is the #1 unfixed cause of the parser dying after the
    //    above passes. Everything visual in the docx output rides
    //    on inline `style="..."` attributes anyway; losing the
    //    `.docx-wrapper` reset doesn't change the printed PDF.
    let strippedStyleBlocks = 0;
    let strippedStyleBytes = 0;
    for (const s of div.querySelectorAll('style')) {
      strippedStyleBytes += (s.textContent || '').length;
      s.parentNode && s.parentNode.removeChild(s);
      strippedStyleBlocks++;
    }

    // 6. Rename HTML5 semantic block elements to <div>. iText's
    //    XHTML parser doesn't know them. We keep all attributes
    //    and children intact.
    const H5_SEMANTIC = [
      'header', 'footer', 'article', 'section', 'nav', 'aside',
      'main', 'figure', 'figcaption', 'details', 'summary'
    ];
    let renamedSemantic = 0;
    for (const tagName of H5_SEMANTIC) {
      // Snapshot — replaceChild mutates the live HTMLCollection.
      const matches = Array.from(div.getElementsByTagName(tagName));
      for (const el of matches) {
        const replacement = document.createElement('div');
        for (const attr of Array.from(el.attributes)) {
          replacement.setAttribute(attr.name, attr.value);
        }
        // Tag the rename for debugging support requests.
        const klass = replacement.getAttribute('class');
        replacement.setAttribute(
          'class',
          (klass ? klass + ' ' : '') + 'pdfforce-h5-' + tagName.toLowerCase()
        );
        while (el.firstChild) replacement.appendChild(el.firstChild);
        el.parentNode && el.parentNode.replaceChild(replacement, el);
        renamedSemantic++;
      }
    }

    // 7. Fix <img src="data:application/octet-stream;base64,..."> to
    //    the right image MIME by sniffing the base64 magic bytes.
    //    Word's docx-to-HTML converter is the main offender.
    let fixedImgMime = 0;
    for (const img of div.querySelectorAll('img[src^="data:"]')) {
      const src = img.getAttribute('src') || '';
      const m = src.match(/^data:([^;,]+);base64,(.{1,16})/);
      if (!m) continue;
      const [, mime, head] = m;
      if (mime.startsWith('image/')) continue;
      let realMime = null;
      if (head.startsWith('iVBORw'))      realMime = 'image/png';
      else if (head.startsWith('/9j/'))   realMime = 'image/jpeg';
      else if (head.startsWith('R0lGOD')) realMime = 'image/gif';
      else if (head.startsWith('UklGR'))  realMime = 'image/webp';
      else if (head.startsWith('PHN2Zy')) realMime = 'image/svg+xml';
      if (!realMime) continue;
      img.setAttribute(
        'src',
        src.replace(/^data:[^;,]+;base64,/, `data:${realMime};base64,`)
      );
      fixedImgMime++;
    }

    // Serialize. The browser writes void elements WITHOUT the closing
    // slash (HTML5 default), so we do the self-closing pass on the
    // string. JS regex on ~10 MB takes single-digit-ms and never hits
    // anything like Apex's "Regex too complicated".
    let out = div.innerHTML;

    // 8. Self-close void elements. The lookbehind `(?<!/)` ensures
    //    `<br/>` (rare in innerHTML output but possible) is left
    //    alone — we only rewrite the open form.
    let selfClosed = 0;
    out = out.replace(
      /<(br|hr|img|input|meta|link|col|area|base|embed|source|track|wbr)\b([^>]*?)(?<!\/)>/gi,
      (m, tag, attrs) => {
        selfClosed++;
        return `<${tag}${attrs}/>`;
      }
    );

    // 9. Escape stray ampersands.
    let escapedAmps = 0;
    out = out.replace(
      /&(?!(?:amp|lt|gt|quot|apos|nbsp|#\d+|#x[0-9a-fA-F]+);)/g,
      () => {
        escapedAmps++;
        return '&amp;';
      }
    );

    const dt = (performance.now() - t0).toFixed(1);
    console.log(
      `[sanitizeHtmlForPdf] ${dt}ms`,
      `in=${inputLen}`,
      `out=${out.length}`,
      `delta=${out.length - inputLen}`,
      '| stripped:',
      `comments=${strippedComments}`,
      `scripts=${strippedScripts}`,
      `nsTags=${unwrappedNs}`,
      `xmlnsAttrs=${strippedXmlns}`,
      `styleBlocks=${strippedStyleBlocks}(${strippedStyleBytes}b)`,
      `| renamed:`,
      `h5Semantic=${renamedSemantic}`,
      `imgMime=${fixedImgMime}`,
      `| rewritten:`,
      `voidSelfClosed=${selfClosed}`,
      `ampsEscaped=${escapedAmps}`
    );

    return out;
  }

  async optimizeInlineImages(html, {
    maxEdge = 1600,
    jpegQuality = 0.82,
    skipBelowBytes = 50 * 1024
  } = {}) {
    if (typeof html !== 'string' || !html) return html;

    const div = document.createElement('div');
    div.innerHTML = html;
    // Word/docxjs emits EVERY embedded image as
    // `data:application/octet-stream;base64,...` rather than
    // `data:image/png;...`. If we only match the latter we silently
    // skip every image, leave the original alpha-PNG bytes in the
    // saved template, and the downstream Apex renderer ends up
    // dropping the image (iText 2.0.8 can't decode RGBA). Catch both.
    const imgs = [...div.querySelectorAll(
      'img[src^="data:image/"], img[src^="data:application/octet-stream"]'
    )];
    if (!imgs.length) return html;

    const cache = new Map(); // original data URL -> optimized data URL
    let originalBytes = 0;
    let optimizedBytes = 0;

    for (const img of imgs) {
      const src = img.getAttribute('src');
      if (!src) continue;

      if (cache.has(src)) {
        img.setAttribute('src', cache.get(src));
        continue;
      }

      // eslint-disable-next-line no-await-in-loop
      const optimized = await this._optimizeOneImage(src, {
        maxEdge,
        jpegQuality,
        skipBelowBytes
      });
      cache.set(src, optimized);
      img.setAttribute('src', optimized);

      originalBytes += src.length;
      optimizedBytes += optimized.length;

      // eslint-disable-next-line no-await-in-loop
      await this._yieldToMainThread();
    }

    console.log(
      '[optimizeInlineImages] images:', imgs.length,
      'unique:', cache.size,
      'data-url bytes before:', originalBytes,
      'after:', optimizedBytes,
      'saved:', (originalBytes - optimizedBytes),
      `(${originalBytes ? (((originalBytes - optimizedBytes) / originalBytes) * 100).toFixed(1) : 0}%)`
    );

    return div.innerHTML;
  }

  async _optimizeOneImage(dataUrl, { maxEdge, jpegQuality, skipBelowBytes }) {
    // Accept both real image/* MIMEs and Word's bogus
    // application/octet-stream tag (which is what docxjs hands us
    // for every embedded image -- see optimizeInlineImages comment).
    const match = dataUrl.match(
      /^data:(image\/[\w+.-]+|application\/octet-stream);base64,(.+)$/
    );
    if (!match) return dataUrl;
    const [, mime, b64] = match;

    // Vector / animated formats: hands off. iText 2.0.8 (the Apex PDF
    // engine downstream) won't render either, but at least they won't
    // smear -- they just no-op.
    if (mime === 'image/svg+xml' || mime === 'image/gif') return dataUrl;

    // Sniff PNG headers (cheap, no full decode) to know whether the
    // PNG carries an alpha channel. We MUST process RGBA / gray+alpha
    // PNGs regardless of size, because iText 2.0.8 (used by both
    // Blob.toPdf and renderAs="advanced_pdf") cannot decode PNG color
    // types 4 or 6 -- it interprets the alpha bytes as additional
    // pixel data and renders the image as a streaky horizontal smear.
    // The fix is to flatten onto a white background and re-encode as
    // JPEG, which iText handles cleanly.
    const isAlphaPng =
      (mime === 'image/png' || mime === 'application/octet-stream')
        && this._pngHasAlphaChannel(b64);

    // Word's octet-stream MIME has no type info; the underlying bytes
    // are most often an RGBA PNG that iText can't decode. Always run
    // octet-stream payloads through the canvas pipeline regardless of
    // size so the saved template ships clean RGB JPEGs.
    const isOctetStream = (mime === 'application/octet-stream');

    // base64 length ≈ ceil(n/3)*4, so the decoded binary is ~length * 3/4.
    const approxBytes = Math.floor(b64.length * 0.75);
    // Skip small images for performance UNLESS they're alpha PNGs
    // or octet-stream payloads -- those are correctness-critical
    // regardless of size.
    if (approxBytes < skipBelowBytes && !isAlphaPng && !isOctetStream) {
      return dataUrl;
    }

    const bitmap = await this._dataUrlToBitmap(dataUrl);
    if (!bitmap) return dataUrl;

    const longest = Math.max(bitmap.width, bitmap.height);
    const scale = longest > maxEdge ? maxEdge / longest : 1;
    const targetW = Math.max(1, Math.round(bitmap.width * scale));
    const targetH = Math.max(1, Math.round(bitmap.height * scale));

    const canvas = document.createElement('canvas');
    canvas.width = targetW;
    canvas.height = targetH;
    const ctx = canvas.getContext('2d');
    if (!ctx) return dataUrl;
    // Composite onto an opaque white background BEFORE drawImage. Any
    // transparent / semi-transparent pixels in the source blend to
    // white, giving us a clean RGB image with no alpha channel. This
    // matches the white PDF page background, so visually the output
    // is what the user expects.
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, targetW, targetH);
    ctx.drawImage(bitmap, 0, 0, targetW, targetH);

    // Always JPEG for bitmap formats. iText 2.0.8 renders 8-bit RGB
    // JPEGs cleanly; PNGs with alpha don't, and there is no in-Apex
    // way to strip alpha after the fact. Quality 0.82 is visually
    // lossless for logos and 5-10x smaller than the source PNG.
    const rawUrl = canvas.toDataURL('image/jpeg', jpegQuality);

    // Strip Exif/ICC/etc. metadata segments. Chrome's canvas always
    // embeds an APP2 ICC color profile (~470 bytes) in the JPEG it
    // emits; iText 2.0.8 doesn't understand JPEG ICC profiles and
    // falls back to a "broken image" placeholder icon when it sees
    // one. Stripping the APP1..APPF / COM segments yields a minimal
    // JFIF JPEG that iText decodes cleanly.
    const outUrl = this._stripJpegMetadataSegments(rawUrl);

    // Defensive: a tiny photo can grow after JPEG re-encode at high
    // quality. Keep whichever is smaller -- EXCEPT for alpha PNGs
    // and octet-stream payloads, where we MUST ship the flattened
    // JPEG even if it's a few bytes larger, because the unmodified
    // original will either smear in the PDF (RGBA) or be tagged with
    // an unknown MIME the renderer can't interpret (octet-stream).
    return (isAlphaPng || isOctetStream || outUrl.length < dataUrl.length)
      ? outUrl
      : dataUrl;
  }

  /**
   * Strip non-essential metadata segments from a JPEG data URL so
   * iText 2.0.8 (the downstream PDF renderer) will decode it. Chrome
   * canvas always embeds an APP2 ICC color profile that iText can't
   * parse; we keep only the markers iText actually uses (SOI, APP0
   * JFIF, DQT, DHT, SOF0/SOF2, DRI, SOS + scan data, EOI) and drop
   * APP1 (Exif), APP2 (ICC), APP3..APPF, and COM.
   */
  _stripJpegMetadataSegments(dataUrl) {
    const m = dataUrl.match(/^data:image\/jpeg;base64,(.+)$/);
    if (!m) return dataUrl;
    let bytes;
    try {
      const bin = atob(m[1]);
      bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    } catch (_e) {
      return dataUrl;
    }
    if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) {
      return dataUrl;
    }

    // First pass: identify byte ranges to KEEP.
    const ranges = [[0, 2]]; // SOI
    let i = 2;
    let truncated = false;
    while (i < bytes.length - 1) {
      if (bytes[i] !== 0xFF) {
        truncated = true;
        break;
      }
      const marker = bytes[i + 1];
      // EOI
      if (marker === 0xD9) {
        ranges.push([i, i + 2]);
        i += 2;
        break;
      }
      // SOS: keep header + scan data up to next non-stuffed marker.
      if (marker === 0xDA) {
        if (i + 4 > bytes.length) { truncated = true; break; }
        const len = (bytes[i + 2] << 8) | bytes[i + 3];
        let j = i + 2 + len;
        while (j < bytes.length - 1) {
          if (bytes[j] === 0xFF
              && bytes[j + 1] !== 0x00
              && bytes[j + 1] !== 0xFF) {
            break;
          }
          j++;
        }
        ranges.push([i, j]);
        i = j;
        continue;
      }
      // Stand-alone (no-payload) markers: RSTn, TEM.
      if ((marker >= 0xD0 && marker <= 0xD7) || marker === 0x01) {
        ranges.push([i, i + 2]);
        i += 2;
        continue;
      }
      // Everything else has a 2-byte length field after the marker.
      if (i + 4 > bytes.length) { truncated = true; break; }
      const len = (bytes[i + 2] << 8) | bytes[i + 3];
      const segEnd = i + 2 + len;
      if (segEnd > bytes.length) { truncated = true; break; }
      // Drop APP1..APPF (Exif, ICC, XMP, Adobe, ...) and COM. Keep
      // APP0 (JFIF) because iText needs it to know this is a JFIF
      // baseline JPEG.
      const isAppN = (marker >= 0xE0 && marker <= 0xEF);
      const isComment = (marker === 0xFE);
      if ((isAppN && marker !== 0xE0) || isComment) {
        i = segEnd;
        continue;
      }
      ranges.push([i, segEnd]);
      i = segEnd;
    }
    if (truncated) return dataUrl;

    // Concatenate kept ranges into one buffer.
    let total = 0;
    for (const [a, b] of ranges) total += (b - a);
    const out = new Uint8Array(total);
    let pos = 0;
    for (const [a, b] of ranges) {
      out.set(bytes.subarray(a, b), pos);
      pos += (b - a);
    }

    // Re-encode to base64. Build the binary string in chunks so we
    // don't blow the JS engine's argument limit on String.fromCharCode
    // with a giant spread on multi-MB photos.
    let s = '';
    const CHUNK = 0x8000;
    for (let k = 0; k < out.length; k += CHUNK) {
      s += String.fromCharCode.apply(
        null,
        out.subarray(k, Math.min(k + CHUNK, out.length))
      );
    }
    let b64;
    try {
      b64 = btoa(s);
    } catch (_e) {
      return dataUrl;
    }
    return 'data:image/jpeg;base64,' + b64;
  }

  /**
   * Sniffs the first ~27 bytes of a PNG (just the signature + IHDR)
   * to check whether the color_type byte indicates an alpha channel.
   * Returns true for color type 4 (gray+alpha) or 6 (RGBA). Cheap:
   * we only base64-decode the first 40 chars (~30 raw bytes), no
   * image-decoder allocation, no canvas.
   */
  _pngHasAlphaChannel(b64) {
    try {
      let sniff = (b64 || '').substring(0, 40);
      while (sniff.length % 4 !== 0) sniff += '=';
      const bin = atob(sniff);
      if (bin.length < 26) return false;
      // PNG signature: 89 50 4E 47 0D 0A 1A 0A.
      if (bin.charCodeAt(0) !== 0x89) return false;
      if (bin.charCodeAt(1) !== 0x50) return false;
      // color_type is the 10th byte of the IHDR data, at raw offset 25
      // (8 sig + 4 IHDR len + 4 'IHDR' + 9 inside IHDR = 25).
      const colorType = bin.charCodeAt(25);
      return colorType === 4 || colorType === 6;
    } catch (_e) {
      return false;
    }
  }

  _dataUrlToBitmap(dataUrl) {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => resolve(null);
      img.src = dataUrl;
    });
  }

  _canvasHasTransparency(ctx, w, h) {
    // Sample a 32x32 grid (max 1024 pixels) instead of every pixel. If any
    // sample is non-opaque we treat the image as needing alpha. Cheap and
    // accurate enough for the JPEG-vs-PNG decision.
    let data;
    try {
      data = ctx.getImageData(0, 0, w, h).data;
    } catch {
      // Tainted canvas (cross-origin source): be safe, keep alpha.
      return true;
    }
    const stepX = Math.max(1, Math.floor(w / 32));
    const stepY = Math.max(1, Math.floor(h / 32));
    for (let y = 0; y < h; y += stepY) {
      for (let x = 0; x < w; x += stepX) {
        if (data[(y * w + x) * 4 + 3] < 255) return true;
      }
    }
    return false;
  }


}