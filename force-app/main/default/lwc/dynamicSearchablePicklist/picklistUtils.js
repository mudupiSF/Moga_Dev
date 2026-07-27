/**
 * Pure helpers for dynamicSearchablePicklist.
 */

/**
 * @param {Array<{label:string,value:string}>} options
 * @param {string} term
 * @param {number} minLength
 * @returns {Array<{label:string,value:string}>}
 */
export function filterOptions(options, term, minLength = 3) {
    const list = options || [];
    const normalized = (term || '').trim().toLowerCase();

    if (!normalized || normalized.length < minLength) {
        return list;
    }

    return list.filter(
        (opt) =>
            (opt.label || '').toLowerCase().includes(normalized) ||
            (opt.value || '').toLowerCase().includes(normalized)
    );
}

/**
 * @param {Array<{label:string,value:string}>} options
 * @param {string} value
 * @returns {{label:string,value:string}|null}
 */
export function findOptionByValue(options, value) {
    if (!value) {
        return null;
    }
    return (options || []).find((opt) => opt.value === value) || null;
}

/**
 * @param {Array<{label:string,value:string}>} options
 * @param {string} term
 * @param {number} minLength
 * @returns {boolean}
 */
export function shouldShowMinLengthHint(term, minLength = 3) {
    const normalized = (term || '').trim();
    return normalized.length > 0 && normalized.length < minLength;
}

export function isRemoteMode(mode) {
    return (mode || '').toLowerCase() === 'remote';
}

export const MODE_STATIC = 'static';
export const MODE_REMOTE = 'remote';