/**
 * Location master options for dependent State / District / City picklists.
 */
public with sharing class LocationMasterController implements Callable {

    private static final String ACTION_GET_OPTIONS = 'getLocationOptions';

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_GET_OPTIONS.equalsIgnoreCase(action)) {
            return getLocationOptionsInternal(args);
        }
        return errorResponse('Unknown action: ' + action);
    }

    private Map<String, Object> getLocationOptionsInternal(Map<String, Object> args) {
        String level     = toSafeString(args.get('level'));
        String stateName = toSafeString(args.get('state'));
        String district  = toSafeString(args.get('district'));

        if (String.isBlank(level)) {
            return errorResponse('level is required.');
        }

        List<Map<String, String>> options = new List<Map<String, String>>();
        if ('state'.equalsIgnoreCase(level)) {
            options = stateOptions();
        } else if ('district'.equalsIgnoreCase(level)) {
            if (String.isBlank(stateName)) {
                return errorResponse('state is required for district options.');
            }
            options = districtOptionsForState(stateName);
        } else if ('city'.equalsIgnoreCase(level)) {
            if (String.isBlank(stateName)) {
                return errorResponse('state is required for city options.');
            }
            options = cityOptionsForState(stateName, district);
        } else {
            return errorResponse('Unsupported level: ' + level);
        }

        return new Map<String, Object>{
            'isSuccess' => true,
            'options'   => options
        };
    }

    private static List<Map<String, String>> stateOptions() {
        List<Map<String, String>> out = new List<Map<String, String>>();
        for (State_Master__c row : [
            SELECT Name
            FROM State_Master__c
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
        ]) {
            if (String.isNotBlank(row.Name)) {
                out.add(optionEntry(row.Name));
            }
        }
        return out;
    }

    private static List<Map<String, String>> districtOptionsForState(String stateName) {
        String resolvedStateName = resolveStateMasterName(stateName);
        List<Map<String, String>> out = new List<Map<String, String>>();
        for (District_Master__c row : [
            SELECT Name
            FROM District_Master__c
            WHERE State_Master__r.Name = :resolvedStateName
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
        ]) {
            if (String.isNotBlank(row.Name)) {
                out.add(optionEntry(row.Name));
            }
        }
        return out;
    }

    private static String resolveStateMasterName(String stateName) {
        if (String.isBlank(stateName)) {
            return '';
        }
        String needle = stateName.trim();
        for (State_Master__c row : [
            SELECT Name
            FROM State_Master__c
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
        ]) {
            if (String.isNotBlank(row.Name) && row.Name.equalsIgnoreCase(needle)) {
                return row.Name;
            }
        }
        return needle;
    }

    private static List<Map<String, String>> cityOptionsForState(String stateName, String districtName) {
        List<Map<String, String>> out = new List<Map<String, String>>();
        for (City_Master__c row : [
            SELECT Name
            FROM City_Master__c
            WHERE State_Master__r.Name = :stateName
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
        ]) {
            if (String.isNotBlank(row.Name)) {
                out.add(optionEntry(row.Name));
            }
        }
        return out;
    }

    private static Map<String, String> optionEntry(String label) {
        return new Map<String, String>{ 'label' => label, 'value' => label };
    }

    private static String toSafeString(Object raw) {
        return raw == null ? null : String.valueOf(raw).trim();
    }

    private static Map<String, Object> errorResponse(String message) {
        return new Map<String, Object>{
            'isSuccess' => false,
            'message'   => message
        };
    }
}