/**
 * Callable controller for approval log page data.
 * Actions: getApprovalLogs, getApprovalLogUserContext, createForwardLog, createProposalLog, getLoanTermGroups
 */
public with sharing class ApprovalLogController implements Callable {

    private static final String ACTION_GET_APPROVAL_LOGS = 'getApprovalLogs';
    private static final String ACTION_GET_APPROVAL_LOG_USER_CONTEXT = 'getApprovalLogUserContext';
    private static final String ACTION_CREATE_FORWARD_LOG = 'createForwardLog';
    private static final String ACTION_CREATE_PROPOSAL_LOG = 'createProposalLog';
    private static final String ACTION_GET_LOAN_TERM_GROUPS = 'getLoanTermGroups';

    private static final String LOG_TYPE_FORWARD = 'Forward Log';
    private static final String LOG_TYPE_DEVIATION = 'Deviation Log';
    private static final String LOG_TYPE_PROPOSAL = 'Proposal Log';

    private static final String PROPOSAL_STATUS_APPROVE = 'Approve';
    private static final String PROPOSAL_STATUS_CONDITIONALLY_APPROVE = 'Conditionally Approve';
    private static final String PROPOSAL_STATUS_REJECT = 'Reject';
    private static final String PROPOSAL_STATUS_HOLD = 'Hold';
    private static final String PROPOSAL_STATUS_ACCEPT = 'Accept';

    private static final List<String> APPROVAL_CVO_BE_ROLES = new List<String>{ 'CVO', 'BE' };
    private static final List<String> APPROVAL_HIGHER_AUTHORITY_ROLES = new List<String>{ 'MA', 'MO' };
    private static final List<String> FORWARD_TO_ROLES = new List<String>{
        'SCM', 'HHEAD', 'NCM', 'CVO', 'BE'
    };
    private static final Integer REMARK_MAX_LENGTH = 255;
    private static final String PROFILE_SYSTEM_ADMINISTRATOR = 'System Administrator';
    private static final String APPROVAL_HISTORY_ADMIN_ROLE = 'Admin';

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_GET_APPROVAL_LOGS.equalsIgnoreCase(action)) {
            return getApprovalLogsInternal(safeArgs);
        }
        if (ACTION_GET_APPROVAL_LOG_USER_CONTEXT.equalsIgnoreCase(action)) {
            return getApprovalLogUserContextInternal(safeArgs);
        }
        if (ACTION_CREATE_FORWARD_LOG.equalsIgnoreCase(action)) {
            return createForwardLogInternal(safeArgs);
        }
        if (ACTION_CREATE_PROPOSAL_LOG.equalsIgnoreCase(action)) {
            return createProposalLogInternal(safeArgs);
        }
        if (ACTION_GET_LOAN_TERM_GROUPS.equalsIgnoreCase(action)) {
            return getLoanTermGroupsInternal(safeArgs);
        }

        return failure('Unknown action: ' + action);
    }

    private Map<String, Object> getApprovalLogUserContextInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'userRole' => '',
            'isLeadOwner' => false,
            'isHigherAuthority' => false
        };
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return result;
        }

        List<Application__c> applications = [
            SELECT Id, OwnerId
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return result;
        }

        Application__c application = applications[0];
        List<User> users = [
            SELECT Id, Title, Profile.Name, UserRole.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        String userRole = resolveCurrentUserApprovalRole(users);
        Boolean isLeadOwner = application.OwnerId == UserInfo.getUserId();
        Boolean isHigherAuthority = resolveIsHigherAuthority(userRole, isLeadOwner);

        result.put('isSuccess', true);
        result.put('userRole', userRole);
        result.put('isLeadOwner', isLeadOwner);
        result.put('isHigherAuthority', isHigherAuthority);
        result.put('profileName', users[0].Profile != null ? users[0].Profile.Name : null);
        return result;
    }

    private String resolveCurrentUserApprovalRole(List<User> users) {
        
        if (users.isEmpty()) {
            return '';
        }
        User currentUser = users[0];
        List<String> roleSources = new List<String>{
            currentUser.UserRole != null ? currentUser.UserRole.Name : null,
            currentUser.title
        };
        for (String roleSource : roleSources) {
            String resolvedRole = extractApprovalRoleToken(roleSource);
            if (String.isNotBlank(resolvedRole)) {
                return resolvedRole;
            }
        }
        return '';
    }

    private Boolean resolveIsHigherAuthority(String userRole, Boolean isLeadOwner) {
        if (roleListContains(APPROVAL_HIGHER_AUTHORITY_ROLES, userRole)) {
            return true;
        }
        return roleListContains(APPROVAL_CVO_BE_ROLES, userRole) && isLeadOwner == true;
    }

    private Boolean roleListContains(List<String> roles, String value) {
        if (String.isBlank(value) || roles == null) {
            return false;
        }
        for (String role : roles) {
            if (value == role) {
                return true;
            }
        }
        return false;
    }

    private Map<String, Object> createForwardLogInternal(Map<String, Object> args) {
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return failure('Application Id is required.');
        }

        String forwardToRole = getStringValue(args, 'forwardToRole');
        if (!isValidForwardToRole(forwardToRole)) {
            return failure('Forward To role is required.');
        }

        String remarks = truncate(getStringValue(args, 'remarks'), REMARK_MAX_LENGTH);
        if (String.isBlank(remarks)) {
            return failure('Remarks are required.');
        }

        if (!Schema.sObjectType.Proposal_Approval_Log__c.isCreateable()) {
            return failure('Insufficient access to create forward log.');
        }

        Id forwardedToUserId = resolveForwardToUserId(forwardToRole);
        Proposal_Approval_Log__c forwardLog = new Proposal_Approval_Log__c(
            Application__c = applicationId,
            Type__c = LOG_TYPE_FORWARD,
            Status__c = forwardToRole,
            Remark__c = remarks,
            Forwarded_By__c = UserInfo.getUserId(),
            Forwarded_To__c = forwardedToUserId
        );

        SObjectAccessDecision insertDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<Proposal_Approval_Log__c>{ forwardLog }
        );
        insert insertDecision.getRecords();

        return new Map<String, Object>{
            'isSuccess' => true,
            'forwardLogId' => String.valueOf(forwardLog.Id)
        };
    }

    private Map<String, Object> createProposalLogInternal(Map<String, Object> args) {
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return failure('Application Id is required.');
        }

        String status = getStringValue(args, 'status');
        if (!isProposalDecisionStatus(status)) {
            return failure('Valid proposal status is required.');
        }

        String proposalRemarks = truncate(getStringValue(args, 'proposalRemarks'), REMARK_MAX_LENGTH);
        if (String.isBlank(proposalRemarks)) {
            return failure('Proposal remarks are required.');
        }

        if (!Schema.sObjectType.Proposal_Approval_Log__c.isCreateable()) {
            return failure('Insufficient access to create proposal log.');
        }

        Proposal_Approval_Log__c proposalLog = new Proposal_Approval_Log__c(
            Application__c = applicationId,
            Type__c = LOG_TYPE_PROPOSAL,
            Status__c = status,
            Proposal_Remark__c = proposalRemarks,
            Remark__c = proposalRemarks,
            Submitted_By__c = UserInfo.getUserId()
        );

        SObjectAccessDecision insertDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<Proposal_Approval_Log__c>{ proposalLog }
        );
        insert insertDecision.getRecords();

        return new Map<String, Object>{
            'isSuccess' => true,
            'proposalLogId' => String.valueOf(proposalLog.Id),
            'decisionFieldsDecision' => status,
            'decisionFieldsRemarks' => proposalRemarks
        };
    }

    private Boolean isValidForwardToRole(String forwardToRole) {
        if (String.isBlank(forwardToRole)) {
            return false;
        }
        for (String allowedRole : FORWARD_TO_ROLES) {
            if (allowedRole.equalsIgnoreCase(forwardToRole)) {
                return true;
            }
        }
        return false;
    }

    private Id resolveForwardToUserId(String roleToken) {
        if (String.isBlank(roleToken)) {
            return null;
        }
        String likePattern = '%' + roleToken + '%';
        String upperToken = roleToken.toUpperCase();
        List<User> candidates = [
            SELECT Id, Title, UserRole.Name
            FROM User
            WHERE IsActive = true
            AND (Title LIKE :likePattern OR UserRole.Name LIKE :likePattern)
            WITH SECURITY_ENFORCED
            LIMIT 100
        ];
        for (User candidate : candidates) {
            if (roleTextContainsToken(candidate.Title, upperToken)
                || roleTextContainsToken(
                    candidate.UserRole != null ? candidate.UserRole.Name : null,
                    upperToken
                )) {
                return candidate.Id;
            }
        }
        return null;
    }

    private Boolean roleTextContainsToken(String roleText, String upperToken) {
        if (String.isBlank(roleText) || String.isBlank(upperToken)) {
            return false;
        }
        return roleText.toUpperCase().contains(upperToken);
    }

    private Map<String, Object> getApprovalLogsInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'forwardLogs' => new List<Map<String, Object>>(),
            'approvalHistory' => new List<Map<String, Object>>(),
            'approvalConditions' => new List<Map<String, Object>>(),
            'loanTerms' => new Map<String, Object>(),
            'emiDateOptions' => new List<Map<String, Object>>(),
            'firstEmiDueDate' => ''
        };
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return result;
        }

        List<Proposal_Approval_Log__c> allLogRecords = queryProposalApprovalLogs(applicationId);
        List<Map<String, Object>> forwardLogs = new List<Map<String, Object>>();
        List<Map<String, Object>> approvalHistory = new List<Map<String, Object>>();
        List<Proposal_Approval_Log__c> conditionalApprovalLogs = new List<Proposal_Approval_Log__c>();

        for (Proposal_Approval_Log__c logRecord : allLogRecords) {
            if (LOG_TYPE_FORWARD.equalsIgnoreCase(logRecord.Type__c)) {
                forwardLogs.add(mapForwardLogRow(logRecord));
            } else if (isConditionalApprovalCondition(logRecord)) {
                conditionalApprovalLogs.add(logRecord);
            } else if (
                LOG_TYPE_DEVIATION.equalsIgnoreCase(logRecord.Type__c)
                || LOG_TYPE_PROPOSAL.equalsIgnoreCase(logRecord.Type__c)
            ) {
                approvalHistory.add(mapApprovalHistoryRow(logRecord));
            }
        }

        Map<String, Object> proposalSummary = buildProposalSummary(allLogRecords, approvalHistory);
        Map<String, Object> finalLoanTermsPayload = buildFinalLoanTerms(applicationId);

        result.put('isSuccess', true);
        result.put('forwardLogs', forwardLogs);
        result.put('approvalHistory', approvalHistory);
        result.put('approvalConditions', mapApprovalConditionRows(conditionalApprovalLogs));
        result.put('isProposalSubmitted', proposalSummary.get('isProposalSubmitted'));
        result.put('proposalLogId', proposalSummary.get('proposalLogId'));
        result.put('decisionFieldsDecision', proposalSummary.get('decisionFieldsDecision'));
        result.put('decisionFieldsRemarks', proposalSummary.get('decisionFieldsRemarks'));
        result.put('proposalRejectedByAuthority', proposalSummary.get('proposalRejectedByAuthority'));
        result.put('loanTerms', finalLoanTermsPayload.get('loanTerms'));
        result.put('emiDateOptions', finalLoanTermsPayload.get('emiDateOptions'));
        result.put('firstEmiDueDate', finalLoanTermsPayload.get('firstEmiDueDate'));
        return result;
    }

    private Map<String, Object> getLoanTermGroupsInternal(Map<String, Object> args) {
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return failure('Application Id is required.');
        }

        List<Proposal_Approval_Log__c> allLogRecords = queryProposalApprovalLogs(applicationId);
        List<Map<String, Object>> approvalHistory = new List<Map<String, Object>>();
        for (Proposal_Approval_Log__c logRecord : allLogRecords) {
            if (LOG_TYPE_DEVIATION.equalsIgnoreCase(logRecord.Type__c)
                || LOG_TYPE_PROPOSAL.equalsIgnoreCase(logRecord.Type__c)) {
                approvalHistory.add(mapApprovalHistoryRow(logRecord));
            }
        }

        Map<String, Object> proposalSummary = buildProposalSummary(allLogRecords, approvalHistory);

        List<Application_Line_Item__c> lineItems = queryApplicationLineItems(applicationId);
        List<Map<String, Object>> loanTermGroups = new List<Map<String, Object>>();
        Integer total = lineItems.size();
        String productType = lineItems[0].Product__c;

        for (Integer index = 0; index < total; index++) {
            Application_Line_Item__c lineItem = lineItems[index];
            Integer sectionIndex = index + 1;
            Asset__c asset = resolveLineItemAsset(lineItem);
            String assetLabel = joinDisplayParts(
                new List<String>{ asset?.Make__c, asset?.Model__c, asset?.Variant__c },
                ' '
            );
            String listTitle = String.isNotBlank(assetLabel)
                ? 'Asset ' + sectionIndex + ' - ' + assetLabel
                : 'Asset ' + sectionIndex;

            Decimal fundedPremiumTotal = resolveFundedPremiumTotal(lineItem);
            Date firstEmiDate = lineItem.First_EMI_Date__c;

            Map<String, Object> loanTerms = new Map<String, Object>{
                'vehicleVariant' => resolveVehicleVariant(lineItem),
                'loanAmount' => formatDecimal(lineItem.Loan_Amount__c, 0),
                'netIRR' => formatDecimal(lineItem.CRM_IRR__c, 2),
                'imputedIRR' => '',
                'crmIRR' => formatDecimal(lineItem.CRM_IRR__c, 2),
                'fundedPremium' => formatDecimal(fundedPremiumTotal, 0),
                'grossIRR' => formatDecimal(lineItem.ROI__c, 2),
                'monthlyEMI' => formatDecimal(lineItem.EMI_Amount__c, 0),
                'loanTenure' => formatDecimal(lineItem.Tenure__c, 0),
                'secondEMIDueDate' => formatDisplayDate(lineItem.Second_EMI_Date__c)
            };

            loanTermGroups.add(new Map<String, Object>{
                'id' => String.valueOf(lineItem.Id),
                'lineItemId' => String.valueOf(lineItem.Id),
                'assetId' => asset != null ? String.valueOf(asset.Id) : null,
                'listTitle' => listTitle,
                'loanTerms' => loanTerms,
                'emiDateOptions' => buildEmiDateOptions(firstEmiDate),
                'firstEmiDueDate' => formatIsoDate(firstEmiDate)
            });
        }

        return new Map<String, Object>{
            'isSuccess' => true,
            'loanTermGroups' => loanTermGroups,
            'productType' => productType,
            'isProposalSubmitted' => proposalSummary.get('isProposalSubmitted'),
            'proposalLogId' => proposalSummary.get('proposalLogId'),
            'decisionFieldsDecision' => proposalSummary.get('decisionFieldsDecision'),
            'decisionFieldsRemarks' => proposalSummary.get('decisionFieldsRemarks'),
            'proposalRejectedByAuthority' => proposalSummary.get('proposalRejectedByAuthority')
        };
    }

    private Map<String, Object> buildFinalLoanTerms(Id applicationId) {
        Application_Line_Item__c lineItem = queryLineItem(applicationId);
        Decimal fundedPremiumTotal = resolveFundedPremiumTotal(lineItem);

        Map<String, Object> loanTerms = new Map<String, Object>{
            'vehicleVariant' => resolveVehicleVariant(lineItem),
            'loanAmount' => formatDecimal(lineItem != null ? lineItem.Loan_Amount__c : null, 0),
            'netIRR' => formatDecimal(lineItem != null ? lineItem.CRM_IRR__c : null, 2),
            'imputedIRR' => '',
            'crmIRR' => formatDecimal(lineItem != null ? lineItem.CRM_IRR__c : null, 2),
            'fundedPremium' => formatDecimal(fundedPremiumTotal, 0),
            'grossIRR' => formatDecimal(lineItem != null ? lineItem.ROI__c : null, 2),
            'monthlyEMI' => formatDecimal(lineItem != null ? lineItem.EMI_Amount__c : null, 0),
            'loanTenure' => formatDecimal(lineItem != null ? lineItem.Tenure__c : null, 0),
            'secondEMIDueDate' => formatDisplayDate(lineItem != null ? lineItem.Second_EMI_Date__c : null)
        };

        Date firstEmiDate = lineItem != null ? lineItem.First_EMI_Date__c : null;
        return new Map<String, Object>{
            'loanTerms' => loanTerms,
            'emiDateOptions' => buildEmiDateOptions(firstEmiDate),
            'firstEmiDueDate' => formatIsoDate(firstEmiDate)
        };
    }

    private Map<String, Object> buildProposalSummary(
        List<Proposal_Approval_Log__c> allLogRecords,
        List<Map<String, Object>> approvalHistory
    ) {
        Proposal_Approval_Log__c latestProposalLog = resolveLatestProposalDecisionLog(allLogRecords);
        return new Map<String, Object>{
            'isProposalSubmitted' => latestProposalLog != null,
            'proposalLogId' => latestProposalLog != null ? String.valueOf(latestProposalLog.Id) : '',
            'decisionFieldsDecision' => resolveLatestProposalDecision(latestProposalLog),
            'decisionFieldsRemarks' => resolveLatestProposalRemarks(latestProposalLog),
            'proposalRejectedByAuthority' => resolveProposalRejectedFlag(approvalHistory)
        };
    }

    private List<Application_Line_Item__c> queryApplicationLineItems(Id applicationId) {
        return [
            SELECT Id,
                   Loan_Amount__c,
                   CRM_IRR__c,
                   ROI__c,
                   EMI_Amount__c,
                   Tenure__c,
                   First_EMI_Date__c,
                   Second_EMI_Date__c,
                   Product__c,
                   (SELECT Id, Make__c, Model__c, Variant__c
                    FROM Assets__r
                    ORDER BY CreatedDate ASC
                    LIMIT 1),
                   (SELECT Funded_Premium__c
                    FROM Insurances__r
                    WHERE Is_Active__c = true)
            FROM Application_Line_Item__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    private Application_Line_Item__c queryLineItem(Id applicationId) {
        List<Application_Line_Item__c> lineItems = queryApplicationLineItems(applicationId);
        return lineItems.isEmpty() ? null : lineItems[0];
    }

    private Asset__c resolveLineItemAsset(Application_Line_Item__c lineItem) {
        if (lineItem == null || lineItem.Assets__r == null || lineItem.Assets__r.isEmpty()) {
            return null;
        }
        return lineItem.Assets__r[0];
    }

    private String joinDisplayParts(List<String> parts, String separator) {
        List<String> cleaned = new List<String>();
        if (parts != null) {
            for (String part : parts) {
                if (String.isNotBlank(part)) {
                    cleaned.add(part.trim());
                }
            }
        }
        return cleaned.isEmpty() ? '' : String.join(cleaned, separator);
    }

    private Proposal_Approval_Log__c resolveLatestProposalDecisionLog(List<Proposal_Approval_Log__c> allLogRecords) {
        if (allLogRecords == null) {
            return null;
        }
        for (Proposal_Approval_Log__c logRecord : allLogRecords) {
            if (LOG_TYPE_PROPOSAL.equalsIgnoreCase(logRecord.Type__c)
                && (
                    isProposalDecisionStatus(logRecord.Status__c)
                    || isProposalDecisionStatus(logRecord.Proposal_Action__c)
                )) {
                return logRecord;
            }
        }
        return null;
    }

    private String resolveLatestProposalDecision(Proposal_Approval_Log__c logRecord) {
        if (logRecord == null) {
            return '';
        }
        if (isProposalDecisionStatus(logRecord.Status__c)) {
            return logRecord.Status__c;
        }
        if (isProposalDecisionStatus(logRecord.Proposal_Action__c)) {
            return logRecord.Proposal_Action__c;
        }
        return coalesceText(logRecord.Status__c, logRecord.Proposal_Action__c);
    }

    private String resolveLatestProposalRemarks(Proposal_Approval_Log__c logRecord) {
        if (logRecord == null) {
            return '';
        }
        return coalesceText(logRecord.Proposal_Remark__c, logRecord.Remark__c);
    }

    private String resolveProposalRejectedFlag(List<Map<String, Object>> approvalHistory) {
        if (approvalHistory == null) {
            return 'NO';
        }
        for (Map<String, Object> historyRow : approvalHistory) {
            String actionValue = historyRow != null ? String.valueOf(historyRow.get('action')) : '';
            if (PROPOSAL_STATUS_REJECT.equalsIgnoreCase(actionValue)) {
                return 'YES';
            }
        }
        return 'NO';
    }

    private String resolveVehicleVariant(Application_Line_Item__c lineItem) {
        if (lineItem == null || lineItem.Assets__r == null || lineItem.Assets__r.isEmpty()) {
            return '';
        }
        Asset__c asset = lineItem.Assets__r[0];
        List<String> parts = new List<String>();
        if (String.isNotBlank(asset.Make__c)) {
            parts.add(asset.Make__c);
        }
        if (String.isNotBlank(asset.Model__c)) {
            parts.add(asset.Model__c);
        }
        if (String.isNotBlank(asset.Variant__c)) {
            parts.add(asset.Variant__c);
        }
        return String.join(parts, ' ');
    }

    private Decimal resolveFundedPremiumTotal(Application_Line_Item__c lineItem) {
        Decimal total = 0;
        if (lineItem == null || lineItem.Insurances__r == null) {
            return total;
        }
        for (Insurance__c insuranceRecord : lineItem.Insurances__r) {
            if (insuranceRecord.Funded_Premium__c != null) {
                total += insuranceRecord.Funded_Premium__c;
            }
        }
        return total;
    }

    private List<Map<String, Object>> buildEmiDateOptions(Date firstEmiDate) {
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        if (firstEmiDate == null) {
            return options;
        }
        for (Integer monthOffset = 0; monthOffset < 3; monthOffset++) {
            Date optionDate = firstEmiDate.addMonths(monthOffset);
            options.add(new Map<String, Object>{
                'label' => formatDisplayDate(optionDate),
                'value' => formatIsoDate(optionDate)
            });
        }
        return options;
    }

    private String formatIsoDate(Date value) {
        if (value == null) {
            return '';
        }
        DateTime dateTimeValue = DateTime.newInstance(value, Time.newInstance(0, 0, 0, 0));
        return dateTimeValue.format('yyyy-MM-dd');
    }

    private String formatDisplayDate(Date value) {
        if (value == null) {
            return '';
        }
        DateTime dateTimeValue = DateTime.newInstance(value, Time.newInstance(0, 0, 0, 0));
        return dateTimeValue.format('dd-MMM-yyyy');
    }

    private String formatDecimal(Decimal value, Integer scale) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value.setScale(scale, System.RoundingMode.HALF_UP));
    }

    private List<Proposal_Approval_Log__c> queryProposalApprovalLogs(Id applicationId) {
        return [
            SELECT Id,
                   Type__c,
                   Status__c,
                   Remark__c,
                   Proposal_Action__c,
                   Proposal_Remark__c,
                   CreatedDate,
                   Submitted_By__c,
                   Submitted_By__r.Name,
                   Submitted_By__r.Title,
                   Submitted_By__r.Profile.Name,
                   Submitted_By__r.UserRole.Name,
                   Forwarded_By__c,
                   Forwarded_By__r.Name,
                   Forwarded_By__r.Title,
                   Forwarded_By__r.UserRole.Name,
                   Forwarded_To__c,
                   Forwarded_To__r.Name,
                   Forwarded_To__r.Title,
                   Forwarded_To__r.UserRole.Name
            FROM Proposal_Approval_Log__c
            WHERE Application__c = :applicationId
            ORDER BY CreatedDate DESC
        ];
    }

    private Map<String, Object> mapForwardLogRow(Proposal_Approval_Log__c logRecord) {
        return new Map<String, Object>{
            'id' => String.valueOf(logRecord.Id),
            'from' => formatUserDisplay(logRecord.Forwarded_By__r),
            'to' => formatForwardTargetDisplay(logRecord),
            'date' => formatDateTime(logRecord.CreatedDate),
            'remarks' => coalesceText(logRecord.Remark__c, logRecord.Proposal_Remark__c)
        };
    }

    private String formatForwardTargetDisplay(Proposal_Approval_Log__c logRecord) {
        String roleLabel = logRecord.Status__c;
        String userName = logRecord.Forwarded_To__r != null ? logRecord.Forwarded_To__r.Name : '';
        if (String.isNotBlank(roleLabel) && String.isNotBlank(userName)) {
            return roleLabel + ' — ' + userName;
        }
        if (String.isNotBlank(roleLabel)) {
            return roleLabel;
        }
        return formatUserDisplay(logRecord.Forwarded_To__r);
    }

    private Boolean isConditionalApprovalCondition(Proposal_Approval_Log__c logRecord) {
        if (!LOG_TYPE_PROPOSAL.equalsIgnoreCase(logRecord.Type__c)) {
            return false;
        }
        String statusValue = logRecord.Status__c;
        return String.isNotBlank(statusValue) && !isProposalDecisionStatus(statusValue);
    }

    private Boolean isProposalDecisionStatus(String statusValue) {
        if (String.isBlank(statusValue)) {
            return false;
        }
        return PROPOSAL_STATUS_APPROVE.equalsIgnoreCase(statusValue)
            || PROPOSAL_STATUS_CONDITIONALLY_APPROVE.equalsIgnoreCase(statusValue)
            || PROPOSAL_STATUS_REJECT.equalsIgnoreCase(statusValue)
            || PROPOSAL_STATUS_HOLD.equalsIgnoreCase(statusValue)
            || PROPOSAL_STATUS_ACCEPT.equalsIgnoreCase(statusValue);
    }

    private List<Map<String, Object>> mapApprovalConditionRows(List<Proposal_Approval_Log__c> logRecords) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        if (logRecords == null || logRecords.isEmpty()) {
            return rows;
        }

        Integer rowNumber = 1;
        for (Integer index = logRecords.size() - 1; index >= 0; index--) {
            rows.add(mapApprovalConditionRow(logRecords[index], rowNumber));
            rowNumber++;
        }
        return rows;
    }

    private Map<String, Object> mapApprovalConditionRow(Proposal_Approval_Log__c logRecord, Integer rowNumber) {
        return new Map<String, Object>{
            'id' => String.valueOf(logRecord.Id),
            'sno' => String.valueOf(rowNumber),
            'approvalCondition' => coalesceText(logRecord.Status__c, logRecord.Remark__c),
            'action' => logRecord.Proposal_Action__c != null ? logRecord.Proposal_Action__c : '',
            'remarks' => logRecord.Proposal_Remark__c != null ? logRecord.Proposal_Remark__c : ''
        };
    }

    private Map<String, Object> mapApprovalHistoryRow(Proposal_Approval_Log__c logRecord) {
        User submittedBy = logRecord.Submitted_By__r;
        String actionValue = LOG_TYPE_PROPOSAL.equalsIgnoreCase(logRecord.Type__c)
            ? coalesceText(logRecord.Proposal_Action__c, logRecord.Status__c)
            : logRecord.Status__c;
        return new Map<String, Object>{
            'id' => String.valueOf(logRecord.Id),
            'role' => resolveApprovalHistoryRole(submittedBy),
            'user' => submittedBy != null ? submittedBy.Name : '',
            'action' => actionValue,
            'date' => formatDateTime(logRecord.CreatedDate),
            'remarks' => coalesceText(logRecord.Remark__c, logRecord.Proposal_Remark__c)
        };
    }

    private String formatUserDisplay(User userRecord) {
        if (userRecord == null) {
            return '';
        }
        String roleToken = resolveUserApprovalRole(userRecord);
        String userName = userRecord.Name != null ? userRecord.Name : '';
        if (String.isNotBlank(roleToken)) {
            return roleToken + ' — ' + userName;
        }
        return userName;
    }

    private String resolveApprovalHistoryRole(User userRecord) {
        if (userRecord == null) {
            return '';
        }
        if (isSystemAdministratorProfile(userRecord.Profile != null ? userRecord.Profile.Name : null)) {
            return APPROVAL_HISTORY_ADMIN_ROLE;
        }
        return userRecord.UserRole != null ? userRecord.UserRole.Name : '';
    }

    private Boolean isSystemAdministratorProfile(String profileName) {
        if (String.isBlank(profileName)) {
            return false;
        }
        return PROFILE_SYSTEM_ADMINISTRATOR.equalsIgnoreCase(profileName);
    }

    private String resolveUserApprovalRole(User userRecord) {
        if (userRecord == null) {
            return '';
        }
        List<String> roleSources = new List<String>{
            userRecord.UserRole != null ? userRecord.UserRole.Name : null,
            userRecord.Title
        };
        for (String roleSource : roleSources) {
            String resolvedRole = extractApprovalRoleToken(roleSource);
            if (String.isNotBlank(resolvedRole)) {
                return resolvedRole;
            }
        }
        return '';
    }

    private String extractApprovalRoleToken(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        String upperValue = value.toUpperCase();
        for (String roleToken : APPROVAL_CVO_BE_ROLES) {
            if (upperValue.contains(roleToken)) {
                return roleToken;
            }
        }
        for (String roleToken : APPROVAL_HIGHER_AUTHORITY_ROLES) {
            if (upperValue.contains(roleToken)) {
                return roleToken;
            }
        }
        return '';
    }

    private String formatDateTime(DateTime value) {
        if (value == null) {
            return '';
        }
        return value.format('dd-MMM-yyyy HH:mm');
    }

    private String coalesceText(String primaryValue, String fallbackValue) {
        return String.isNotBlank(primaryValue) ? primaryValue : (fallbackValue != null ? fallbackValue : '');
    }

    private Id resolveApplicationId(Map<String, Object> args) {
        Id fromApplicationId = normalizeToApplicationId(parseIdValue(args.get('applicationId')));
        if (fromApplicationId != null) {
            return fromApplicationId;
        }
        return normalizeToApplicationId(parseIdValue(args.get('recordId')));
    }

    private Id normalizeToApplicationId(Id sourceId) {
        if (sourceId == null) {
            return null;
        }

        Schema.SObjectType sourceType = sourceId.getSObjectType();
        if (sourceType == Application__c.SObjectType) {
            return sourceId;
        }

        try {
            if (sourceType == Proposal_Approval_Log__c.SObjectType) {
                List<Proposal_Approval_Log__c> logs = [
                    SELECT Application__c
                    FROM Proposal_Approval_Log__c
                    WHERE Id = :sourceId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                return logs.isEmpty() ? null : logs[0].Application__c;
            }
            if (sourceType == Application_Line_Item__c.SObjectType) {
                List<Application_Line_Item__c> lineItems = [
                    SELECT Application__c
                    FROM Application_Line_Item__c
                    WHERE Id = :sourceId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                return lineItems.isEmpty() ? null : lineItems[0].Application__c;
            }
        } catch (Exception ex) {
            return null;
        }

        return null;
    }

    private Id parseIdValue(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        return String.isBlank(value) ? null : (Id) value;
    }

    private String getStringValue(Map<String, Object> source, String key) {
        if (source == null || !source.containsKey(key) || source.get(key) == null) {
            return '';
        }
        return String.valueOf(source.get(key)).trim();
    }

    private String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0) {
            return value == null ? '' : value;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    private Map<String, Object> failure(String message) {
        return new Map<String, Object>{
            'isSuccess' => false,
            'message' => message
        };
    }
}