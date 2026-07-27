public with sharing class SearchableLookupController {
    private static final Integer MAX_RESULTS = 20;

    public class SearchOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public SearchOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /**
     * Description: Searches for records in the specified object and field
     * @param searchObjectApiName The API name of the object to search
     * @param searchFieldApiName The API name of the field to search
     * @param searchTerm The search term
     * @param returnFieldApiNameAsLabel The API name of the field to return as label
     * @param returnFieldApiNameAsValue The API name of the field to return as value
     * @param additionalFilter The additional filter to apply to the query
     * @return A list of search options
     */
    @AuraEnabled(cacheable=true)
    public static List<SearchOption> searchRecords(
        String searchObjectApiName,
        String searchFieldApiName,
        String searchTerm,
        String returnFieldApiNameAsLabel,
        String returnFieldApiNameAsValue,
        String additionalFilter
    ) {
        if (String.isBlank(searchObjectApiName) || String.isBlank(searchFieldApiName)) {
            throw new AuraHandledException('Object API name and field API name are required.');
        }
        if (String.isBlank(returnFieldApiNameAsLabel)) {
            returnFieldApiNameAsLabel = searchFieldApiName;
        }
        if (String.isBlank(returnFieldApiNameAsValue)) {
            returnFieldApiNameAsValue = 'Id';
        }

        String normalizedTerm = String.isBlank(searchTerm) ? '%' : String.escapeSingleQuotes(searchTerm.trim()) + '%';

        Set<String> queryFieldList = new Set<String>{'Id', returnFieldApiNameAsLabel, returnFieldApiNameAsValue};

        String queryString =
            'SELECT ' + String.join(new List<String>(queryFieldList), ', ') +
            ' FROM ' + searchObjectApiName +
            ' WHERE ' + searchFieldApiName + ' != null' +
            ' AND ' + searchFieldApiName + ' LIKE \'' + normalizedTerm + '\'' +
            (String.isBlank(additionalFilter) ? '' : ' AND ' + additionalFilter) +
            ' ORDER BY ' + returnFieldApiNameAsLabel +
            ' LIMIT ' + MAX_RESULTS;
        System.debug('queryString: ' + queryString);

        List<SObject> rows = Database.query(queryString);
        Set<String> seen = new Set<String>();
        List<SearchOption> results = new List<SearchOption>();

        for (SObject row : rows) {
            String labelValue = String.valueOf(row.get(returnFieldApiNameAsLabel));
            String optionValue = String.valueOf(row.get(returnFieldApiNameAsValue));
            if (String.isNotBlank(labelValue) && String.isNotBlank(optionValue) && !seen.contains(optionValue)) {
                seen.add(optionValue);
                results.add(new SearchOption(labelValue, optionValue));
            }
        }
        return results;
    }
}