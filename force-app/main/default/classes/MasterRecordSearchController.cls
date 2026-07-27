/**
 * @description Server-side typeahead for dynamicSearchablePicklist (remote mode).
 *              Object and fields come from Search_Config__mdt only — never from LWC.
 */
public with sharing class MasterRecordSearchController {
    private static final Integer MIN_SEARCH_LENGTH = 3;
    private static final Integer MAX_ROW_LIMIT = 50;

    public class SearchOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public SearchOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled
    public static List<SearchOption> searchRecords(
        String searchConfigKey,
        String searchTerm,
        String searchContextJson
    ) {
        try {
            if (String.isBlank(searchTerm) || searchTerm.trim().length() < MIN_SEARCH_LENGTH) {
                return new List<SearchOption>();
            }

            Search_Config__mdt config = getConfig(searchConfigKey);
            Map<String, Object> context = parseContext(searchContextJson);
            String objectName = config.Object_Api_Name__c.trim();
            List<String> searchFields = splitCsv(config.Search_Fields__c);
            String displayField = config.Display_Field__c.trim();
            String valueField = String.isNotBlank(config.Value_Field__c) ? config.Value_Field__c.trim() : 'Id';
            String orderByField = String.isNotBlank(config.Order_By_Field__c)
                ? config.Order_By_Field__c.trim()
                : displayField;
            Integer rowLimit = getRowLimit(config.Row_Limit__c);
            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';

            List<String> likeConditions = new List<String>();
            for (String fieldName : searchFields) {
                likeConditions.add(fieldName + ' LIKE :searchPattern');
            }

            String whereClause = '(' + String.join(likeConditions, ' OR ') + ')';
            if (String.isNotBlank(config.Where_Clause__c)) {
                whereClause += ' AND (' + config.Where_Clause__c.trim() + ')';
            }

            String productType = null;
            String makeCode = null;
            String configKey = searchConfigKey.trim();

            if ('MMV_Fleet_Make'.equalsIgnoreCase(configKey)) {
                productType = resolveMmvProductType(getContextString(context, 'productType'));
                if (String.isBlank(productType)) {
                    return new List<SearchOption>();
                }
                whereClause += ' AND Product_Type__c = :productType';
            } else if ('MMV_Fleet_Model'.equalsIgnoreCase(configKey)) {
                makeCode = getContextString(context, 'makeCode');
                if (String.isBlank(makeCode)) {
                    return new List<SearchOption>();
                }
                whereClause += ' AND Make_Code__c = :makeCode';
            }

            Set<String> selectFields = new Set<String>{ displayField, valueField };
            selectFields.addAll(searchFields);
            selectFields.add(orderByField);

            String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ')
                + ' FROM ' + objectName
                + ' WHERE ' + whereClause
                + ' WITH SECURITY_ENFORCED'
                + ' ORDER BY ' + orderByField + ' ASC'
                + ' LIMIT ' + rowLimit;

            List<SearchOption> options = new List<SearchOption>();
            Set<String> seenValues = new Set<String>();
            for (SObject row : Database.query(soql)) {
                Object labelValue = row.get(displayField);
                Object rawValue = row.get(valueField);
                String label = labelValue != null ? String.valueOf(labelValue).trim() : '';
                String optionValue = rawValue != null ? String.valueOf(rawValue).trim() : '';

                if (String.isBlank(label) && String.isNotBlank(optionValue)) {
                    label = optionValue;
                }
                if (String.isBlank(optionValue) && String.isNotBlank(label)) {
                    optionValue = label;
                }

                if (String.isBlank(label) || String.isBlank(optionValue) || seenValues.contains(optionValue)) {
                    continue;
                }

                seenValues.add(optionValue);
                options.add(new SearchOption(label, optionValue));
            }

            return options;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getDisplayLabel(String searchConfigKey, Id recordId) {
        try {
            if (recordId == null) {
                return '';
            }

            Search_Config__mdt config = getConfig(searchConfigKey);
            if (String.isNotBlank(config.Value_Field__c) && !'Id'.equalsIgnoreCase(config.Value_Field__c.trim())) {
                return getDisplayLabelByValue(searchConfigKey, String.valueOf(recordId), null);
            }

            String displayField = config.Display_Field__c.trim();
            String objectName = config.Object_Api_Name__c.trim();
            String soql = 'SELECT ' + displayField
                + ' FROM ' + objectName
                + ' WHERE Id = :recordId'
                + ' WITH SECURITY_ENFORCED'
                + ' LIMIT 1';

            List<SObject> rows = Database.query(soql);
            if (rows.isEmpty()) {
                return '';
            }

            Object labelValue = rows[0].get(displayField);
            return labelValue != null ? String.valueOf(labelValue) : '';
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getDisplayLabelByValue(
        String searchConfigKey,
        String fieldValue,
        String searchContextJson
    ) {
        try {
            if (String.isBlank(fieldValue)) {
                return '';
            }

            Search_Config__mdt config = getConfig(searchConfigKey);
            String displayField = config.Display_Field__c.trim();
            String valueField = String.isNotBlank(config.Value_Field__c) ? config.Value_Field__c.trim() : 'Id';
            String objectName = config.Object_Api_Name__c.trim();
            Map<String, Object> context = parseContext(searchContextJson);

            String whereClause = valueField + ' = :fieldValue';
            String productType = null;
            String makeCode = null;
            String configKey = searchConfigKey.trim();

            if ('MMV_Fleet_Model'.equalsIgnoreCase(configKey)) {
                makeCode = getContextString(context, 'makeCode');
                if (String.isNotBlank(makeCode)) {
                    whereClause += ' AND Make_Code__c = :makeCode';
                }
            }

            String soql = 'SELECT ' + displayField
                + ' FROM ' + objectName
                + ' WHERE ' + whereClause
                + ' WITH SECURITY_ENFORCED'
                + ' LIMIT 1';

            List<SObject> rows = Database.query(soql);
            if (rows.isEmpty()) {
                return '';
            }

            Object labelValue = rows[0].get(displayField);
            return labelValue != null ? String.valueOf(labelValue) : '';
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    private static Search_Config__mdt getConfig(String searchConfigKey) {
        if (String.isBlank(searchConfigKey)) {
            throw new AuraHandledException('Search configuration key is required.');
        }

        Search_Config__mdt config = Search_Config__mdt.getInstance(searchConfigKey.trim());
        if (config == null || config.Is_Active__c == false) {
            throw new AuraHandledException('Search configuration is not available: ' + searchConfigKey);
        }
        if (String.isBlank(config.Object_Api_Name__c)
            || String.isBlank(config.Search_Fields__c)
            || String.isBlank(config.Display_Field__c)) {
            throw new AuraHandledException('Search configuration is incomplete: ' + searchConfigKey);
        }

        return config;
    }

    private static List<String> splitCsv(String csvValue) {
        List<String> fieldNames = new List<String>();
        for (String part : csvValue.split(',')) {
            if (String.isNotBlank(part)) {
                fieldNames.add(part.trim());
            }
        }
        if (fieldNames.isEmpty()) {
            throw new AuraHandledException('Search Fields must contain at least one field.');
        }
        return fieldNames;
    }

    private static Integer getRowLimit(Decimal configuredLimit) {
        Integer rowLimit = configuredLimit != null ? configuredLimit.intValue() : MAX_ROW_LIMIT;
        return rowLimit > 0 ? Math.min(rowLimit, MAX_ROW_LIMIT) : MAX_ROW_LIMIT;
    }

    private static Map<String, Object> parseContext(String searchContextJson) {
        if (String.isBlank(searchContextJson)) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(searchContextJson);
    }

    private static String getContextString(Map<String, Object> context, String key) {
        if (context == null || !context.containsKey(key) || context.get(key) == null) {
            return null;
        }
        return String.valueOf(context.get(key));
    }

    /**
     * Maps Fleet_Details__c.Product__c values to MMV_Product_Master__c.Product_Type__c picklist.
     */
    @TestVisible
    private static String resolveMmvProductType(String fleetProduct) {
        if (String.isBlank(fleetProduct)) {
            return null;
        }

        String normalized = fleetProduct.trim().toUpperCase();
        if (normalized == 'PASSENGER VEHICLE') {
            return 'Passenger Vehicle';
        }
        if (normalized == 'SMALL COMMERCIAL VEHICLE'
            || normalized == 'LIGHT COMMERCIAL VEHICLE'
            || normalized == 'CONSTRUCTION EQUIPMENT'
            || normalized == 'MEDIUM AND HEAVY COMMERCIAL VEHICLES') {
            return 'Commercial Vehicle';
        }

        // Allow direct MMV picklist values when passed through already.
        if (fleetProduct == 'Passenger Vehicle'
            || fleetProduct == 'Two Wheeler'
            || fleetProduct == 'Commercial Vehicle') {
            return fleetProduct;
        }

        return null;
    }
}