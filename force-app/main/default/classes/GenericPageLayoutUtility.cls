public with sharing class GenericPageLayoutUtility {

    /** Product Type full form -> short form for Agent Branch Name display */
    private static final Map<String, String> PRODUCT_TYPE_SHORT_FORM = new Map<String, String>{
        'Passenger Vehicles' => 'PV',
        'Passenger Vehicles (PV)' => 'PV',
        'Two Wheeler' => 'TW',
        'Two Wheeler (TW)' => 'TW',
        'Tractor' => 'TFE',
        'Tractor (TFE)' => 'TFE',
        'Small Commercial Vehicle' => 'SCV',
        'Small Commercial Vehicle (SCV)' => 'SCV',
        'Light Commercial Vehicle' => 'LCV',
        'Light Commercial Vehicle (LCV)' => 'LCV'
    };

    /**
     * Returns short form for product type (e.g. Passenger Vehicles => PV, Two Wheeler => TW).
     * Used for Agent Branch Name display. Returns original value if no mapping found.
     */
    public static String getProductTypeShortForm(String productType) {
        if (String.isBlank(productType)) {
            return '';
        }
        String trimmed = productType.trim();
        return PRODUCT_TYPE_SHORT_FORM.containsKey(trimmed) ? PRODUCT_TYPE_SHORT_FORM.get(trimmed) : trimmed;
    }

    /**
     * Fetches dependent picklist options mapped by controlling field values from schema.
     * Uses the standard field dependency (controllingField -> dependentField) on the given object.
     *
     * @param objectApiName   API name of the SObject (e.g. 'Applicant__c')
     * @param dependentFieldApiName API name of the dependent picklist field (e.g. 'Applicant_Type__c')
     * @return Map of controlling field value -> List of {label, value} for dependent options.
     *         Empty map if field is not a dependent picklist or on error.
     */
    public static Map<String, List<Map<String, String>>> fetchControlledByDependentToSchema(
        String objectApiName,
        String dependentFieldApiName
    ) {
        Map<String, List<Map<String, String>>> optionsMap = new Map<String, List<Map<String, String>>>();
        if (String.isBlank(objectApiName) || String.isBlank(dependentFieldApiName)) {
            return optionsMap;
        }
        try {
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjType == null) {
                return optionsMap;
            }
            Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();
            Schema.SObjectField depFieldToken = fieldMap.get(dependentFieldApiName);
            if (depFieldToken == null) {
                depFieldToken = fieldMap.get(dependentFieldApiName.toLowerCase());
            }
            if (depFieldToken == null) {
                return optionsMap;
            }
            Schema.DescribeFieldResult depDfr = depFieldToken.getDescribe();
            if (!depDfr.isDependentPicklist()) {
                return optionsMap;
            }
            Schema.sObjectField controllerToken = depDfr.getController();
            if (controllerToken == null) {
                return optionsMap;
            }
            Schema.DescribeFieldResult ctrlDfr = controllerToken.getDescribe();
            List<Schema.PicklistEntry> ctrlEntries = ctrlDfr.getPicklistValues();
            List<Schema.PicklistEntry> depEntries = depDfr.getPicklistValues();
            if (ctrlEntries == null || depEntries == null) {
                return optionsMap;
            }
            List<PicklistEntryWithValidFor> depWrappers = (List<PicklistEntryWithValidFor>) JSON.deserialize(
                JSON.serialize(depEntries), List<PicklistEntryWithValidFor>.class
            );
            for (Integer ctrlIdx = 0; ctrlIdx < ctrlEntries.size(); ctrlIdx++) {
                String ctrlValue = ctrlEntries[ctrlIdx].getValue();
                List<Map<String, String>> opts = new List<Map<String, String>>();
                for (Integer depIdx = 0; depIdx < depWrappers.size(); depIdx++) {
                    PicklistEntryWithValidFor ple = depWrappers[depIdx];
                    if (ple == null || String.isBlank(ple.validFor)) continue;
                    if (isValidFor(ple.validFor, ctrlIdx)) {
                        opts.add(new Map<String, String>{ 'label' => ple.label, 'value' => ple.value });
                    }
                }
                optionsMap.put(ctrlValue, opts);
            }
        } catch (Exception e) {
            System.debug(
                'SFLOSUtility' +
                'fetchControlledByDependentToSchema'+
                'Apex'+ '----> '+
                e + '----> '+
                objectApiName + '.' + dependentFieldApiName
            );
        }
        return optionsMap;
    }

    /**
     * Returns active picklist entries on the given object/field as {label, value} maps.
     */
    public static List<Map<String, String>> getActivePicklistOptions(
        String objectApiName,
        String fieldApiName
    ) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return options;
        }
        try {
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjType == null) {
                return options;
            }
            Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();
            Schema.SObjectField fieldToken = fieldMap.get(fieldApiName);
            if (fieldToken == null) {
                fieldToken = fieldMap.get(fieldApiName.toLowerCase());
            }
            if (fieldToken == null) {
                return options;
            }
            Schema.DescribeFieldResult dfr = fieldToken.getDescribe();
            if (dfr.getType() != Schema.DisplayType.Picklist
                && dfr.getType() != Schema.DisplayType.MultiPicklist) {
                return options;
            }
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.isActive()) {
                    options.add(new Map<String, String>{
                        'label' => pe.getLabel(),
                        'value' => pe.getValue()
                    });
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'GenericPageLayoutUtility.getActivePicklistOptions: '
                + objectApiName + '.' + fieldApiName + ' — ' + e.getMessage());
        }
        return options;
    }

    /**
     * Returns true when the supplied value represents a Non-Individual customer.
     * Case- and separator-insensitive (handles "Non-Individual", "Non Individual",
     * "NonIndividual", "NON_INDIVIDUAL"). Returns false for null/blank.
     */
    public static Boolean isNonIndividualApplicationType(String applicationType) {
        if (String.isBlank(applicationType)) {
            return false;
        }
        String normalised = applicationType.trim().toLowerCase()
            .replace(' ', '').replace('-', '').replace('_', '');
        return normalised == 'nonindividual';
    }

    /**
     * Parses a date-of-birth string from OCR output. Handles ISO YYYY-MM-DD,
     * DD/MM/YYYY, DD-MM-YYYY, MM/DD/YYYY, ordinal suffixes (1st/2nd/...),
     * and month names (e.g. "12 January 1990", "12-Jan-1990").
     * Returns null on blank or unparseable input.
     */
    public static Date parseEinsteinDateOfBirth(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String cleaned = raw.trim()
            .replaceAll('(?i)(\\d+)(st|nd|rd|th)', '$1')
            .replaceAll('[/.]', '-')
            .replaceAll('\\s+', ' ');

        try {
            return parseDateValue(cleaned);
        } catch (Exception ignored) {
        }

        Map<String, String> monthMap = new Map<String, String>{
            'jan' => '01', 'january'   => '01',
            'feb' => '02', 'february'  => '02',
            'mar' => '03', 'march'     => '03',
            'apr' => '04', 'april'     => '04',
            'may' => '05',
            'jun' => '06', 'june'      => '06',
            'jul' => '07', 'july'      => '07',
            'aug' => '08', 'august'    => '08',
            'sep' => '09', 'sept' => '09', 'september' => '09',
            'oct' => '10', 'october'   => '10',
            'nov' => '11', 'november'  => '11',
            'dec' => '12', 'december'  => '12'
        };
        Pattern dayMonthYear = Pattern.compile('^(\\d{1,2})[- ]([A-Za-z]+)[- ](\\d{4})$');
        Matcher dm = dayMonthYear.matcher(cleaned);
        if (dm.matches()) {
            String dd  = dm.group(1).length() == 1 ? '0' + dm.group(1) : dm.group(1);
            String key = dm.group(2).toLowerCase();
            String yyyy = dm.group(3);
            if (monthMap.containsKey(key)) {
                try {
                    return Date.valueOf(yyyy + '-' + monthMap.get(key) + '-' + dd);
                } catch (Exception ignored) {
                }
            }
        }
        return null;
    }

    /**
     * Parses date string. Accepts YYYY-MM-DD (Salesforce) or DD-MM-YYYY / DD/MM/YYYY (UI format).
     * @param strValue Date string in any supported format
     * @return Parsed Date, or null if blank
     * @throws AuraHandledException if string cannot be parsed
     */
    public static Date parseDateValue(String strValue) {
        if (String.isBlank(strValue)) return null;
        strValue = strValue.trim();
        try {
            Pattern yyyyMmDd = Pattern.compile('^\\d{4}-\\d{1,2}-\\d{1,2}$');
            if (yyyyMmDd.matcher(strValue).matches()) {
                return Date.valueOf(strValue);
            }
            Pattern p = Pattern.compile('^(\\d{1,2})[-/](\\d{1,2})[-/](\\d{4})$');
            Matcher m = p.matcher(strValue);
            if (m.matches()) {
                String yyyy = m.group(3);
                String mm = m.group(2).length() == 1 ? '0' + m.group(2) : m.group(2);
                String dd = m.group(1).length() == 1 ? '0' + m.group(1) : m.group(1);
                return Date.valueOf(yyyy + '-' + mm + '-' + dd);
            }
            return Date.valueOf(strValue);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid date: ' + strValue);
        }
    }

    private static Boolean isValidFor(String validForB64, Integer bitIndex) {
        if (String.isBlank(validForB64)) return false;
        String base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        Integer charIndex = bitIndex / 6;
        Integer bitInChar = bitIndex - charIndex * 6;
        if (charIndex >= validForB64.length()) return false;
        Integer charVal = base64Chars.indexOf(validForB64.substring(charIndex, charIndex + 1));
        if (charVal < 0) return false;
        Integer mask = 1 << (5 - bitInChar);
        return (charVal & mask) != 0;
    }

    private class PicklistEntryWithValidFor {
        public String active;
        public String defaultValue;
        public String label;
        public String value;
        public String validFor;
    }
}