/**
 * @description Rule Engine to evaluate WHERE clause conditions in Apex
 * Supports complex conditions with AND, OR, IN, NOT IN, =, !=, >, <, >=, <=, LIKE, etc.
 * @author System
 * @date 2025-11-26
 */
public class WhereClauseEvaluator {
    
    /**
     * @description Evaluate a WHERE clause against a single record
     * @param record The SObject record to evaluate
     * @param whereClause The WHERE clause string (e.g., "Status__c = 'Active' AND Type__c = 'Primary'")
     * @return Boolean - true if record matches the condition, false otherwise
     */
    public static Boolean evaluateRecord(SObject record, String whereClause) {
        if (String.isBlank(whereClause)) {
            return true; // No filter means all records pass
        }
        
        try {
            System.debug('=== WhereClauseEvaluator.evaluateRecord ===');
            System.debug('WHERE Clause: ' + whereClause);
            System.debug('Record: ' + record);
            
            // Parse and evaluate the WHERE clause
            return evaluateExpression(record, whereClause.trim());
            
        } catch (Exception e) {
            System.debug('ERROR in WhereClauseEvaluator: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            return true; // On error, don't filter out the record
        }
    }
    
    /**
     * @description Filter a list of records based on WHERE clause
     * @param records List of SObject records
     * @param whereClause The WHERE clause string
     * @return List<SObject> - Filtered list of records
     */
    public static List<SObject> filterRecords(List<SObject> records, String whereClause) {
        if (String.isBlank(whereClause) || records == null || records.isEmpty()) {
            return records;
        }
        
        List<SObject> filteredRecords = new List<SObject>();
        
        for (SObject record : records) {
            if (evaluateRecord(record, whereClause)) {
                filteredRecords.add(record);
            }
        }
        
        System.debug('Filtered ' + records.size() + ' records down to ' + filteredRecords.size() + ' records');
        
        return filteredRecords;
    }
    
    /**
     * @description Evaluate a complex expression (handles AND/OR)
     */
    private static Boolean evaluateExpression(SObject record, String expression) {
        expression = expression.trim();
        
        // Handle OR (lowest precedence)
        if (expression.containsIgnoreCase(' OR ')) {
            List<String> orParts = splitByOperator(expression, ' OR ');
            for (String orPart : orParts) {
                if (evaluateExpression(record, orPart.trim())) {
                    return true; // Any true means OR is true
                }
            }
            return false;
        }
        
        // Handle AND (higher precedence)
        if (expression.containsIgnoreCase(' AND ')) {
            List<String> andParts = splitByOperator(expression, ' AND ');
            for (String andPart : andParts) {
                if (!evaluateExpression(record, andPart.trim())) {
                    return false; // Any false means AND is false
                }
            }
            return true;
        }
        
        // Handle parentheses
        if (expression.startsWith('(') && expression.endsWith(')')) {
            return evaluateExpression(record, expression.substring(1, expression.length() - 1));
        }
        
        // Evaluate single condition
        return evaluateCondition(record, expression);
    }
    
    /**
     * @description Split expression by operator while respecting quotes and parentheses
     */
    private static List<String> splitByOperator(String expression, String operator) {
        List<String> parts = new List<String>();
        Integer level = 0;
        Boolean inQuotes = false;
        Integer lastSplit = 0;
        
        for (Integer i = 0; i < expression.length(); i++) {
            String c = expression.substring(i, i + 1);
            
            if (c == '\'') {
                inQuotes = !inQuotes;
            } else if (!inQuotes) {
                if (c == '(') {
                    level++;
                } else if (c == ')') {
                    level--;
                } else if (level == 0 && i + operator.length() <= expression.length()) {
                    String substr = expression.substring(i, i + operator.length());
                    if (substr.equalsIgnoreCase(operator)) {
                        parts.add(expression.substring(lastSplit, i));
                        lastSplit = i + operator.length();
                        i += operator.length() - 1;
                    }
                }
            }
        }
        
        parts.add(expression.substring(lastSplit));
        return parts;
    }
    
    /**
     * @description Evaluate a single condition (e.g., "Status__c = 'Active'")
     */
    private static Boolean evaluateCondition(SObject record, String condition) {
        condition = condition.trim();
        
        System.debug('Evaluating condition: ' + condition);
        
        // Handle IN operator
        if (condition.containsIgnoreCase(' IN ')) {
            return evaluateInCondition(record, condition, false);
        }
        
        // Handle NOT IN operator
        if (condition.containsIgnoreCase(' NOT IN ')) {
            return evaluateInCondition(record, condition, true);
        }
        
        // Handle LIKE operator
        if (condition.containsIgnoreCase(' LIKE ')) {
            return evaluateLikeCondition(record, condition);
        }
        
        // Handle comparison operators (order matters: >= before >, <= before <)
        if (condition.contains('>=')) {
            return evaluateComparison(record, condition, '>=');
        } else if (condition.contains('<=')) {
            return evaluateComparison(record, condition, '<=');
        } else if (condition.contains('!=') || condition.contains('<>')) {
            return evaluateComparison(record, condition, '!=');
        } else if (condition.contains('=')) {
            return evaluateComparison(record, condition, '=');
        } else if (condition.contains('>')) {
            return evaluateComparison(record, condition, '>');
        } else if (condition.contains('<')) {
            return evaluateComparison(record, condition, '<');
        }
        
        System.debug('Unknown condition format: ' + condition);
        return true; // Unknown format, don't filter
    }
    
    /**
     * @description Evaluate IN or NOT IN condition
     */
    private static Boolean evaluateInCondition(SObject record, String condition, Boolean isNotIn) {
        String operator = isNotIn ? ' NOT IN ' : ' IN ';
        List<String> parts = condition.split(operator, 2);
        
        if (parts.size() != 2) {
            return true;
        }
        
        String fieldName = parts[0].trim();
        String valueList = parts[1].trim();
        
        // Remove parentheses
        if (valueList.startsWith('(') && valueList.endsWith(')')) {
            valueList = valueList.substring(1, valueList.length() - 1);
        }
        
        // Parse values
        List<String> values = new List<String>();
        for (String val : valueList.split(',')) {
            values.add(removeQuotes(val.trim()));
        }
        
        // Get field value
        Object fieldValue = getFieldValue(record, fieldName);
        String fieldValueStr = fieldValue != null ? String.valueOf(fieldValue) : '';
        
        Boolean isIn = values.contains(fieldValueStr);
        
        System.debug('Field: ' + fieldName + ', Value: ' + fieldValueStr + ', IN: ' + values + ', Result: ' + isIn);
        
        return isNotIn ? !isIn : isIn;
    }
    
    /**
     * @description Evaluate LIKE condition
     */
    private static Boolean evaluateLikeCondition(SObject record, String condition) {
        List<String> parts = condition.split(' LIKE ', 2);
        
        if (parts.size() != 2) {
            return true;
        }
        
        String fieldName = parts[0].trim();
        String pattern = removeQuotes(parts[1].trim());
        
        // Get field value
        Object fieldValue = getFieldValue(record, fieldName);
        String fieldValueStr = fieldValue != null ? String.valueOf(fieldValue) : '';
        
        // Simple LIKE implementation
        // % = any characters, _ = single character
        Boolean matchResult = evaluateLikePattern(fieldValueStr, pattern);
        
        System.debug('Field: ' + fieldName + ', Value: ' + fieldValueStr + ', LIKE: ' + pattern + ', Result: ' + matchResult);
        
        return matchResult;
    }
    
    /**
     * @description Evaluate comparison condition (=, !=, >, <, >=, <=)
     */
    private static Boolean evaluateComparison(SObject record, String condition, String operator) {
        List<String> parts = condition.split(operator, 2);
        
        if (parts.size() != 2) {
            return true;
        }
        
        String fieldName = parts[0].trim();
        String expectedValueStr = removeQuotes(parts[1].trim());
        
        // Get field value
        Object fieldValue = getFieldValue(record, fieldName);
        
        System.debug('Field: ' + fieldName + ', Actual: ' + fieldValue + ', Operator: ' + operator + ', Expected: ' + expectedValueStr);
        
        // Handle null values
        if (fieldValue == null) {
            if (expectedValueStr.equalsIgnoreCase('null')) {
                return operator == '=' || operator == '>=';
            } else {
                return operator == '!=' || operator == '<>';
            }
        }
        
        // Convert to string for comparison
        String fieldValueStr = String.valueOf(fieldValue);
        
        // Perform comparison
        if (operator == '=') {
            return fieldValueStr.equalsIgnoreCase(expectedValueStr);
        } else if (operator == '!=' || operator == '<>') {
            return !fieldValueStr.equalsIgnoreCase(expectedValueStr);
        } else if (operator == '>') {
            return compareValues(fieldValueStr, expectedValueStr) > 0;
        } else if (operator == '<') {
            return compareValues(fieldValueStr, expectedValueStr) < 0;
        } else if (operator == '>=') {
            return compareValues(fieldValueStr, expectedValueStr) >= 0;
        } else if (operator == '<=') {
            return compareValues(fieldValueStr, expectedValueStr) <= 0;
        }
        
        return true;
    }
    
    /**
     * @description Compare two values (handles strings, numbers, dates)
     */
    private static Integer compareValues(String val1, String val2) {
        // Try numeric comparison
        try {
            Decimal num1 = Decimal.valueOf(val1);
            Decimal num2 = Decimal.valueOf(val2);
            if (num1 > num2) return 1;
            if (num1 < num2) return -1;
            return 0;
        } catch (Exception e) {
            // Not numeric, fall through to string comparison
        }
        
        // Try date comparison
        try {
            Date date1 = Date.valueOf(val1);
            Date date2 = Date.valueOf(val2);
            if (date1 > date2) return 1;
            if (date1 < date2) return -1;
            return 0;
        } catch (Exception e) {
            // Not date, fall through to string comparison
        }
        
        // String comparison
        return val1.compareTo(val2);
    }
    
    /**
     * @description Get field value from record (supports dot notation for relationships)
     */
    private static Object getFieldValue(SObject record, String fieldName) {
        try {
            // Handle relationship fields (e.g., Account.Name)
            if (fieldName.contains('.')) {
                List<String> parts = fieldName.split('\\.');
                SObject currentRecord = record;
                
                for (Integer i = 0; i < parts.size() - 1; i++) {
                    currentRecord = currentRecord.getSObject(parts[i]);
                    if (currentRecord == null) {
                        return null;
                    }
                }
                
                return currentRecord.get(parts[parts.size() - 1]);
            }
            
            // Simple field
            return record.get(fieldName);
        } catch (Exception e) {
            System.debug('Error getting field value for ' + fieldName + ': ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Remove quotes from a string value
     */
    private static String removeQuotes(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        
        value = value.trim();
        
        if ((value.startsWith('\'') && value.endsWith('\'')) ||
            (value.startsWith('"') && value.endsWith('"'))) {
            return value.substring(1, value.length() - 1);
        }
        
        return value;
    }
    
    /**
     * @description Evaluate LIKE pattern matching
     * Supports % (any characters) and _ (single character)
     */
    private static Boolean evaluateLikePattern(String value, String pattern) {
        if (String.isBlank(pattern)) {
            return String.isBlank(value);
        }
        
        // Convert to lowercase for case-insensitive matching
        value = value != null ? value.toLowerCase() : '';
        pattern = pattern.toLowerCase();
        
        // Handle simple cases
        if (pattern == '%') {
            return true; // % matches everything
        }
        
        if (!pattern.contains('%') && !pattern.contains('_')) {
            return value.equals(pattern); // No wildcards, exact match
        }
        
        // Handle pattern with wildcards
        Integer valueIndex = 0;
        Integer patternIndex = 0;
        Integer starIndex = -1;
        Integer matchIndex = 0;
        
        while (valueIndex < value.length()) {
            if (patternIndex < pattern.length()) {
                String patternChar = pattern.substring(patternIndex, patternIndex + 1);
                
                if (patternChar == '%') {
                    // Remember position of * and where we matched
                    starIndex = patternIndex;
                    matchIndex = valueIndex;
                    patternIndex++;
                    continue;
                } else if (patternChar == '_' || patternChar == value.substring(valueIndex, valueIndex + 1)) {
                    // _ matches any single character, or characters match
                    patternIndex++;
                    valueIndex++;
                    continue;
                }
            }
            
            // No match, backtrack if we have a *
            if (starIndex != -1) {
                patternIndex = starIndex + 1;
                matchIndex++;
                valueIndex = matchIndex;
                continue;
            }
            
            return false;
        }
        
        // Check remaining pattern characters
        while (patternIndex < pattern.length() && pattern.substring(patternIndex, patternIndex + 1) == '%') {
            patternIndex++;
        }
        
        return patternIndex == pattern.length();
    }
}