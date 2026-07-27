/**
 * Common Utility Functions to be used for pdfForce?
 * [Bug] Scaled objects sometimes can not be aligned by edges
 *
 */

const readUploadedFileAsDataUrl = (inputFile) => {
  let temporaryFileReader = new FileReader();
  return new Promise((resolve, reject) => {
    temporaryFileReader.onerror = () => {
      temporaryFileReader.abort();
      reject(new DOMException("Problem parsing input file."));
    };

    temporaryFileReader.onload = () => {
      resolve(temporaryFileReader.result);
    };
    temporaryFileReader.readAsDataURL(inputFile);
  });
};


/**
 * Fetches a ContentVersion's VersionData via the jsforce connection and
 * returns the raw bytes (Uint8Array) so the caller can decompress them
 * with pako. This is the large-file fallback path used when the Apex
 * loadTemplateJSON helper returns null (file >= 3 MB).
 *
 * IMPORTANT: we deliberately do NOT use `jsforceConnection.request(...)`
 * to fetch the file. jsforce's browser transport returns the response as
 * `responseText`, which UTF-8-decodes the bytes. Gzip data has bytes
 * outside the ASCII range and gets mangled into U+FFFD replacement chars,
 * destroying the gzip header and producing "unknown compression method"
 * on ungzip. We use `fetch()` + `response.arrayBuffer()` so we get the
 * bytes verbatim.
 *
 * Returns:
 *   { contentVersion: stringified record, rawData: Uint8Array }
 *   or { error: {...} } on failure.
 */
const loadTemplateFromSalesforce = async (contentDocumentId, jsforceConnection) => {
  let result = {};
  try {
    let records = await jsforceConnection.query(
      `SELECT Id, Title, FileExtension, ContentSize, PathOnClient, VersionData, ContentDocumentId 
         FROM ContentVersion 
         WHERE ContentDocumentId = '${contentDocumentId}' and IsLatest = true`
    );
    console.log('records', JSON.stringify(records));
    if (records.totalSize > 0) {
      result.contentVersion = JSON.stringify(records.records[0]);
      try {
        const versionDataUrl = records.records[0].VersionData;
        // jsforce stores the host in `instanceUrl` and the session id in
        // `accessToken` (regardless of whether the caller passed `serverUrl`
        // + `sessionId` or `instanceUrl` + `accessToken`).
        const baseUrl = jsforceConnection.instanceUrl || '';
        const fullUrl = /^https?:\/\//i.test(versionDataUrl)
          ? versionDataUrl
          : `${baseUrl}${versionDataUrl}`;

        const response = await fetch(fullUrl, {
          method: 'GET',
          headers: {
            Authorization: `Bearer ${jsforceConnection.accessToken}`,
            Accept: 'application/octet-stream'
          }
        });
        if (!response.ok) {
          throw new Error(
            `Failed to fetch VersionData (HTTP ${response.status} ${response.statusText})`
          );
        }
        const arrayBuffer = await response.arrayBuffer();
        result.rawData = new Uint8Array(arrayBuffer);
      } catch (error) {
        console.error('Error getting binary data PdfForceUtils:', {
          errorMessage: error?.message,
          errorStack: error?.stack,
          errorName: error?.name,
          contentDocumentId: contentDocumentId,
          jsforceConnectionExists: !!jsforceConnection
        });
        result.error = {
          errorMessage: error?.message,
          errorStack: error?.stack,
          errorName: error?.name,
          contentDocumentId: contentDocumentId,
          jsforceConnectionExists: !!jsforceConnection
        };
      }
    } else {
      result.error = {
        errorMessage: 'No content version found',
        contentDocumentId: contentDocumentId,
        jsforceConnectionExists: !!jsforceConnection
      };
    }
  } catch (error) {
    console.error('Error getting content version PdfForceUtils:', error);
    result.error = {
      errorMessage: error?.message,
      errorStack: error?.stack,
      errorName: error?.name,
      contentDocumentId: contentDocumentId,
      jsforceConnectionExists: !!jsforceConnection
    };

  }
  return result;
}



/**
   * Normalizes edit-element wrappers in parsed DOM: replaces each wrapper with just
   * the template's innerHTML so Handlebars compiles content once (no duplicates).
   * @param {HTMLElement} container - Container to search for wrappers
   */
const _normalizeEditElementWrappers = (container) => {
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



const robustHandlebarsHealer = (html) => {
  if (!html) return '';

  const parser = new DOMParser();
  let htmlString = `${html}`;
  const doc = parser.parseFromString(htmlString, 'text/html');

  // Normalize edit-element wrappers so Handlebars compiles template content once
  _normalizeEditElementWrappers(doc.body);

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


export {
  readUploadedFileAsDataUrl,
  loadTemplateFromSalesforce,
  robustHandlebarsHealer
};