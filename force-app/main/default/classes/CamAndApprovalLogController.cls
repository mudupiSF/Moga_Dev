public with sharing class CamAndApprovalLogController implements Callable {

    private static final String ACTION_GET_PROPOSAL_SECTION = 'getProposalSectionData';
    private static final String CAM_STAGE_NAME = 'CAM and Approval Log';
    private static final String STATUS_UNDER_REVIEW = 'Under Review';
    private static final String STATUS_REVIEWED = 'Reviewed';
    private static final String EMPTY_DISPLAY = '—';

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_GET_PROPOSAL_SECTION.equalsIgnoreCase(action)) {
            return getProposalSectionInternal(safeArgs);
        }

        throw new CalloutException('Unknown action: ' + action);
    }

    private static Map<String, Object> getProposalSectionInternal(Map<String, Object> args) {
        Map<String, Object> response = emptyProposalSection();
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return response;
        }

        try {
            List<Application__c> applications = [
                SELECT Sub_Stage__c,
                       Main_Stage__c,
                       Stage__c
                FROM Application__c
                WHERE Id = :applicationId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (applications.isEmpty()) {
                return response;
            }

            response.put('statusLabel', displayValue(getProposalStatus(applications[0])));
            response.put('isSuccess', true);
        } catch (Exception e) {
            return failure('Unable to load proposal status: ' + e.getMessage());
        }

        return response;
    }

    private static Map<String, Object> emptyProposalSection() {
        return new Map<String, Object>{
            'isSuccess' => false,
            'statusLabel' => EMPTY_DISPLAY
        };
    }

    private static Map<String, Object> failure(String message) {
        Map<String, Object> response = emptyProposalSection();
        response.put('message', message);
        return response;
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
        try {
            return (Id) String.valueOf(rawValue);
        } catch (Exception e) {
            return null;
        }
    }

    private static String getCurrentStage(Application__c application) {
        if (application == null) {
            return null;
        }
        if (String.isNotBlank(application.Sub_Stage__c)) {
            return application.Sub_Stage__c;
        }
        if (String.isNotBlank(application.Main_Stage__c)) {
            return application.Main_Stage__c;
        }
        return application.Stage__c;
    }

    private static String getProposalStatus(Application__c application) {
        if (application == null) {
            return null;
        }
        return isCamStage(application) ? STATUS_UNDER_REVIEW : STATUS_REVIEWED;
    }

    private static Boolean isCamStage(Application__c application) {
        return CAM_STAGE_NAME.equalsIgnoreCase(getCurrentStage(application));
    }

    private static String displayValue(String value) {
        return String.isBlank(value) ? EMPTY_DISPLAY : value;
    }
}