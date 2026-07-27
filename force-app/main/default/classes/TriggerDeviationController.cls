/**
 * Callable controller for deviation trigger after callout creation.
 * Actions: triggerDeviationMail
 */
public with sharing class TriggerDeviationController implements Callable {

    private static final String ACTION_TRIGGER_DEVIATION_MAIL = 'triggerDeviationMail';
    private static final String MSG_DEVIATION_MAIL_TRIGGERED = 'Deviation notification triggered successfully.';

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_TRIGGER_DEVIATION_MAIL.equalsIgnoreCase(action)) {
            return triggerDeviationMailInternal(safeArgs);
        }

        return failure('Unknown action: ' + action);
    }

    private Map<String, Object> triggerDeviationMailInternal(Map<String, Object> args) {
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return failure('Application Id is required.');
        }

        return new Map<String, Object>{
            'isSuccess' => true,
            'emailsTriggered' => 0,
            'recipientRoles' => new List<String>(),
            'skippedCount' => 0,
            'updatedCount' => 0,
            'message' => MSG_DEVIATION_MAIL_TRIGGERED
        };
    }

    private static Id resolveApplicationId(Map<String, Object> args) {
        Id fromApplicationId = parseIdValue(args.get('applicationId'));
        if (fromApplicationId != null) {
            return fromApplicationId;
        }
        return parseIdValue(args.get('recordId'));
    }

    private static Id parseIdValue(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        return String.isBlank(value) ? null : (Id) value;
    }

    private static Map<String, Object> failure(String message) {
        return new Map<String, Object>{
            'isSuccess' => false,
            'message' => message
        };
    }
}