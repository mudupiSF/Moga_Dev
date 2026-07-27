/**
 * OCR prompt-response parsing for document verification (PAN extraction).
 */
public with sharing class DocumentVerificationOcrParser {

    /**
     * Parses raw Einstein prompt text into a result map (sanitize + JSON parse + field mapping + DOB normalize).
     * Returns null when the text is blank, JSON is invalid, or the payload is not an object map.
     */
    public static Map<String, Object> buildResultFromPromptText(String responseText) {
        if (String.isBlank(responseText)) {
            return null;
        }
        String cleaned = sanitizePromptJson(responseText);

        Map<String, Object> parsed;
        try {
            Object resultObject = JSON.deserializeUntyped(cleaned);
            if (!(resultObject instanceof Map<String, Object>)) {
                return null;
            }
            parsed = parseDocumentExtractionResult((Map<String, Object>) resultObject);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'DocumentVerificationOcrParser.buildResultFromPromptText parse error: ' + ex.getMessage());
            return null;
        }

        if (parsed == null) {
            return null;
        }

        String extractedPan = parsed.get('panCardNumber') != null
            ? String.valueOf(parsed.get('panCardNumber')).trim().toUpperCase() : null;
        if (String.isNotBlank(extractedPan)) {
            parsed.put('panCardNumber', extractedPan);
        }

        Object rawDob = parsed.get('date_of_birth');
        if (rawDob != null) {
            parsed.put('date_of_birth', normalizeDobToIso(String.valueOf(rawDob)));
        }

        return parsed;
    }

    public static String sanitizePromptJson(String input) {
        if (String.isBlank(input)) return input;
        String s = input.replaceAll('[\\u00A0\\u2007\\u202F\\uFEFF]', '').trim();
        if (s.startsWith('```')) {
            Integer objStart = s.indexOf('{');
            Integer objEnd = s.lastIndexOf('}');
            Integer arrStart = s.indexOf('[');
            Integer arrEnd = s.lastIndexOf(']');
            if (objStart >= 0 && objEnd > objStart) {
                if (arrStart < 0 || objStart < arrStart) {
                    s = s.substring(objStart, objEnd + 1).trim();
                } else {
                    s = s.substring(arrStart, arrEnd + 1).trim();
                }
            } else if (arrStart >= 0 && arrEnd > arrStart) {
                s = s.substring(arrStart, arrEnd + 1).trim();
            }
        }
        return s;
    }

    public static Map<String, Object> parseDocumentExtractionResult(Map<String, Object> result) {
        Map<String, Object> documentExtractionResult = new Map<String, Object>();
        documentExtractionResult.put('document_type', result.get('document_type'));
        documentExtractionResult.put('classification', result.get('classification'));
        documentExtractionResult.put('confidence', result.get('confidence'));
        documentExtractionResult.put('metadata', result.get('metadata'));

        Object documentDataObj = result.get('document_data');
        if (documentDataObj instanceof Map<String, Object>) {
            Map<String, Object> documentData = (Map<String, Object>) documentDataObj;
            documentExtractionResult.put('full_name', documentData.get('full_name'));
            documentExtractionResult.put('father_name', documentData.get('father_name'));
            documentExtractionResult.put('panCardNumber', documentData.get('document_number'));
            documentExtractionResult.put('date_of_birth', documentData.get('date_of_birth'));
            documentExtractionResult.put('issuing_authority', documentData.get('issuing_authority'));
        }
        return documentExtractionResult;
    }

    public static String normalizeDobToIso(String raw) {
        if (String.isBlank(raw)) return null;
        try {
            Date parsed = GenericUtility.parseEinsteinDateOfBirth(raw);
            return parsed == null ? null : String.valueOf(parsed);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'DocumentVerificationOcrParser.normalizeDobToIso failed for "' + raw + '": ' + e.getMessage());
            return null;
        }
    }
}