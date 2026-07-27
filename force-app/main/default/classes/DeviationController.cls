/**
 * Callable controller for deviation callout and deviation page data.
 * Actions: runDeviationCallout, getDeviations, saveDeviationApprovals
 */
public with sharing class DeviationController implements Callable {

    private static final String ACTION_RUN_DEVIATION_CALLOUT = 'runDeviationCallout';
    private static final String ACTION_GET_DEVIATIONS = 'getDeviations';
    private static final String ACTION_SAVE_DEVIATION_APPROVALS = 'saveDeviationApprovals';
    private static final String INTEGRATION_NAME = 'DeviationCallout';
    private static final String TYPE_GLOBAL = 'global';
    private static final String TYPE_ASSET = 'asset';
    private static final String TYPE_OF_DEVIATION_GLOBAL = 'Global';
    private static final String TYPE_OF_DEVIATION_ASSET = 'Asset';
    private static final String DEVIATION_TYPE_AUTO = 'Auto';
    private static final String DEVIATION_TYPE_MANUAL = 'Manual';
    private static final String LOG_TYPE_DEVIATION = 'Deviation Log';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final Integer DESCRIPTION_MAX_LENGTH = 255;
    private static final Integer REMARK_MAX_LENGTH = 255;
    private static final List<String> STUB_DEVIATION_ROLES = new List<String>{
        'HHEAD',
        'ZH',
        'BH'
    };

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_RUN_DEVIATION_CALLOUT.equalsIgnoreCase(action)) {
            return runDeviationCalloutInternal(safeArgs);
        }
        if (ACTION_GET_DEVIATIONS.equalsIgnoreCase(action)) {
            return getDeviationsInternal(safeArgs);
        }
        if (ACTION_SAVE_DEVIATION_APPROVALS.equalsIgnoreCase(action)) {
            return saveDeviationApprovalsInternal(safeArgs);
        }

        return failure('Unknown action: ' + action);
    }

    private Map<String, Object> getDeviationsInternal(Map<String, Object> args) {
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return failure('Application Id is required.');
        }

        List<Application_Line_Item__c> lineItems = queryApplicationLineItems(applicationId);
        Set<Id> lineItemIds = new Set<Id>();
        for (Application_Line_Item__c lineItem : lineItems) {
            lineItemIds.add(lineItem.Id);
        }

        Map<Id, List<Map<String, Object>>> assetDeviationsByLineItem = new Map<Id, List<Map<String, Object>>>();
        List<Map<String, Object>> globalDeviations = new List<Map<String, Object>>();
        List<Map<String, Object>> assetDeviations = new List<Map<String, Object>>();
        Integer globalRowIndex = 0;

        if (!lineItemIds.isEmpty()) {
            for (Deviations__c deviation : queryDeviationsForLineItems(lineItemIds)) {
                Id lineItemId = deviation.Application_Line_Items__c;
                if (TYPE_OF_DEVIATION_ASSET.equalsIgnoreCase(deviation.Type_Of_Deviation__c)) {
                    if (!assetDeviationsByLineItem.containsKey(lineItemId)) {
                        assetDeviationsByLineItem.put(lineItemId, new List<Map<String, Object>>());
                    }
                    Integer assetRowIndex = assetDeviationsByLineItem.get(lineItemId).size();
                    Map<String, Object> assetRow = mapDeviationRow(deviation, assetRowIndex);
                    assetDeviationsByLineItem.get(lineItemId).add(assetRow);
                    assetDeviations.add(assetRow);
                } else if (TYPE_OF_DEVIATION_GLOBAL.equalsIgnoreCase(deviation.Type_Of_Deviation__c)) {
                    globalDeviations.add(mapDeviationRow(deviation, globalRowIndex));
                    globalRowIndex++;
                }
            }
        }

        List<Map<String, Object>> assetDeviationGroups = buildAssetDeviationGroups(
            lineItems,
            assetDeviationsByLineItem
        );

        return new Map<String, Object>{
            'isSuccess' => true,
            'globalDeviations' => globalDeviations,
            'assetDeviations' => assetDeviations,
            'assetDeviationGroups' => assetDeviationGroups
        };
    }

    private Map<String, Object> saveDeviationApprovalsInternal(Map<String, Object> args) {
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return failure('Application Id is required.');
        }

        List<Object> rawUpdates = getObjectList(args, 'updatedDeviations');
        if (rawUpdates.isEmpty()) {
            return new Map<String, Object>{ 'isSuccess' => true, 'savedCount' => 0 };
        }

        if (!Schema.sObjectType.Deviations__c.isUpdateable()
            || !Schema.sObjectType.Proposal_Approval_Log__c.isCreateable()) {
            return failure('Insufficient access to save deviation approvals.');
        }

        List<Deviations__c> deviationsToUpdate = new List<Deviations__c>();
        List<Proposal_Approval_Log__c> logsToInsert = new List<Proposal_Approval_Log__c>();
        Id submittedById = UserInfo.getUserId();

        for (Object rawUpdate : rawUpdates) {
            Map<String, Object> updatePayload = asStringObjectMap(rawUpdate);
            if (updatePayload == null) {
                continue;
            }
            Id deviationId = parseIdValue(updatePayload.get('id'));
            String approvalStatus = getStringValue(updatePayload, 'approvalStatus');
            if (deviationId == null || !isApprovedOrRejected(approvalStatus)) {
                continue;
            }
            String remarks = truncate(getStringValue(updatePayload, 'remarks'), REMARK_MAX_LENGTH);

            deviationsToUpdate.add(new Deviations__c(
                Id = deviationId,
                Approval_Status__c = approvalStatus,
                Approval_Conditions__c = remarks
            ));

            logsToInsert.add(new Proposal_Approval_Log__c(
                Application__c = applicationId,
                Deviation__c = deviationId,
                Type__c = LOG_TYPE_DEVIATION,
                Status__c = approvalStatus,
                Remark__c = remarks,
                Submitted_By__c = submittedById
            ));
        }

        if (deviationsToUpdate.isEmpty()) {
            return new Map<String, Object>{ 'isSuccess' => true, 'savedCount' => 0 };
        }

        SObjectAccessDecision updateDecision = Security.stripInaccessible(
            AccessType.UPDATABLE,
            deviationsToUpdate
        );
        update updateDecision.getRecords();

        SObjectAccessDecision insertDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            logsToInsert
        );
        insert insertDecision.getRecords();

        return new Map<String, Object>{
            'isSuccess' => true,
            'savedCount' => logsToInsert.size()
        };
    }

    private static Boolean isApprovedOrRejected(String approvalStatus) {
        return STATUS_APPROVED.equalsIgnoreCase(approvalStatus)
            || STATUS_REJECTED.equalsIgnoreCase(approvalStatus);
    }

    private static List<Application_Line_Item__c> queryApplicationLineItems(Id applicationId) {
        return [
            SELECT Id,
                (SELECT Id,
                        Make__c,
                        Model__c,
                        Variant__c
                 FROM Assets__r
                 ORDER BY CreatedDate ASC
                 LIMIT 1)
            FROM Application_Line_Item__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    private static List<Deviations__c> queryDeviationsForLineItems(Set<Id> lineItemIds) {
        return [
            SELECT Id,
                Application_Line_Items__c,
                Deviation_Description__c,
                Deviation_Level__c,
                Role__c,
                Approval_Status__c,
                Approval_Conditions__c,
                Remarks__c,
                Type_Of_Deviation__c
            FROM Deviations__c
            WHERE Application_Line_Items__c IN :lineItemIds
            AND Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    private static List<Map<String, Object>> buildAssetDeviationGroups(
        List<Application_Line_Item__c> lineItems,
        Map<Id, List<Map<String, Object>>> assetDeviationsByLineItem
    ) {
        List<Map<String, Object>> groups = new List<Map<String, Object>>();
        if (lineItems == null || lineItems.isEmpty()) {
            return groups;
        }

        Integer total = lineItems.size();
        for (Integer index = 0; index < total; index++) {
            Application_Line_Item__c lineItem = lineItems[index];
            Asset__c asset = resolveLineItemAsset(lineItem);
            Integer sectionIndex = index + 1;
            String assetLabel = joinDisplayParts(
                new List<String>{ asset?.Make__c, asset?.Model__c, asset?.Variant__c },
                ' '
            );
            String listTitle = String.isNotBlank(assetLabel)
                ? 'Asset ' + sectionIndex + ' - ' + assetLabel
                : 'Asset ' + sectionIndex;

            List<Map<String, Object>> deviations = assetDeviationsByLineItem.containsKey(lineItem.Id)
                ? assetDeviationsByLineItem.get(lineItem.Id)
                : new List<Map<String, Object>>();

            groups.add(new Map<String, Object>{
                'id' => String.valueOf(lineItem.Id),
                'lineItemId' => String.valueOf(lineItem.Id),
                'assetId' => asset != null ? String.valueOf(asset.Id) : null,
                'listTitle' => listTitle,
                'deviations' => deviations
            });
        }

        return groups;
    }

    private static Asset__c resolveLineItemAsset(Application_Line_Item__c lineItem) {
        if (lineItem == null || lineItem.Assets__r == null || lineItem.Assets__r.isEmpty()) {
            return null;
        }
        return lineItem.Assets__r[0];
    }

    private static String joinDisplayParts(List<String> parts, String separator) {
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

    private static List<Deviations__c> queryDeviationsForLineItem(Id lineItemId) {
        return [
            SELECT Id,
                Deviation_Description__c,
                Deviation_Level__c,
                Role__c,
                Approval_Status__c,
                Approval_Conditions__c,
                Remarks__c,
                Type_Of_Deviation__c
            FROM Deviations__c
            WHERE Application_Line_Items__c = :lineItemId
            AND Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    private static Map<String, Object> mapDeviationRow(Deviations__c deviation, Integer rowIndex) {
        return new Map<String, Object>{
            'id' => deviation.Id,
            'description' => deviation.Deviation_Description__c,
            'level' => deviation.Deviation_Level__c,
            'role' => resolveDeviationRole(deviation.Role__c, rowIndex),
            'approvalStatus' => deviation.Approval_Status__c,
            'remarks' => String.isBlank(deviation.Approval_Conditions__c)
                ? resolveDisplayRemarks(deviation.Remarks__c)
                : deviation.Approval_Conditions__c
        };
    }

    private static String resolveDeviationRole(String storedRole, Integer rowIndex) {
        if (String.isNotBlank(storedRole)) {
            return storedRole.trim();
        }
        return resolveStubDeviationRole(rowIndex);
    }

    private static String resolveStubDeviationRole(Integer rowIndex) {
        if (STUB_DEVIATION_ROLES.isEmpty()) {
            return '';
        }
        Integer safeIndex = rowIndex == null || rowIndex < 0 ? 0 : rowIndex;
        return STUB_DEVIATION_ROLES[Math.mod(safeIndex, STUB_DEVIATION_ROLES.size())];
    }

    private static String resolveDisplayRemarks(String remarks) {
        if (String.isBlank(remarks)) {
            return '';
        }
        String trimmed = remarks.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
            return '';
        }
        return remarks;
    }

    private Map<String, Object> runDeviationCalloutInternal(Map<String, Object> args) {
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return failure('Application Id is required.');
        }

        String callType = getStringValue(args, 'type');
        if (String.isBlank(callType)
            || (!TYPE_GLOBAL.equalsIgnoreCase(callType) && !TYPE_ASSET.equalsIgnoreCase(callType))) {
            return failure('Deviation callout type is required (global or asset).');
        }

        if (!Schema.sObjectType.Deviations__c.isCreateable()) {
            return failure('Insufficient access to create deviation records.');
        }

        Id lineItemId = resolveApplicationLineItemId(applicationId);
        if (lineItemId == null) {
            return failure('Application line item is required to create deviations.');
        }

        try {
            Map<String, Object> response = runStubbedDeviationCallout(applicationId, callType);
            List<RuleCandidate> candidates = parseRulesFromResponse(response, callType);

            Set<String> batchKeys = loadExistingDedupeKeys(lineItemId);

            List<Deviations__c> toInsert = new List<Deviations__c>();
            Integer skippedCount = 0;
            Integer rowIndex = 0;

            for (RuleCandidate candidate : candidates) {
                String dedupeKey = buildDedupeKey(candidate.deviationId, candidate.deviationLevel);
                if (batchKeys.contains(dedupeKey)) {
                    skippedCount++;
                    continue;
                }

                batchKeys.add(dedupeKey);
                toInsert.add(buildDeviationRecord(candidate, lineItemId, rowIndex));
                rowIndex++;
            }

            List<Id> createdIds = insertDeviations(toInsert);

            return new Map<String, Object>{
                'isSuccess' => true,
                'integrationName' => INTEGRATION_NAME,
                'callType' => callType.toLowerCase(),
                'ruleCount' => candidates.size(),
                'createdCount' => createdIds.size(),
                'skippedCount' => skippedCount,
                'deviationIds' => createdIds
            };
        } catch (Exception e) {
            return failure('Unable to process deviation callout: ' + e.getMessage());
        }
    }

    private static Map<String, Object> runStubbedDeviationCallout(Id applicationId, String callType) {
        if (TYPE_ASSET.equalsIgnoreCase(callType)) {
            return buildAssetStubResponse();
        }
        return buildGlobalStubResponse();
    }

    private static Map<String, Object> buildGlobalStubResponse() {
        return new Map<String, Object>{
            'Deviations' => new List<Object>{
                new Map<String, Object>{
                    'ApplicantType' => 'Borrower',
                    'Rules' => new List<Object>{
                        buildRule(
                            '3239',
                            'WhatsApp Banking Check for Borrower',
                            'L1,L2',
                            new List<Object>(),
                            'WhatsApp Banking Check for Borrower'
                        ),
                        buildRule(
                            '9001',
                            'New To Credit Customer',
                            'BCC',
                            new List<Object>{
                                conditionEntry('Product', 'C'),
                                conditionEntry('Borrower Customer Segmentation', 'FTB'),
                                conditionEntry('Co Borrower Customer Segmentation', 'FTB'),
                                conditionEntry('Customer Segmentation', 'FTB'),
                                conditionEntry('Multiple Product Flag', 'false'),
                                conditionEntry('Total Exposure', '209434.0'),
                                conditionEntry('Committee Deviation Level', 'BCC')
                            },
                            'BCC - Committee'
                        ),
                        buildRule(
                            '3589220',
                            'BH_Approval',
                            'L1',
                            new List<Object>{ conditionEntry('Product', 'C') },
                            'BH_Approval'
                        )
                    }
                },
                new Map<String, Object>{
                    'ApplicantType' => 'G1',
                    'Rules' => new List<Object>{
                        buildRule(
                            '3239',
                            'WhatsApp Banking Check for G1',
                            'L1,L2',
                            new List<Object>(),
                            'WhatsApp Banking Check for G1'
                        )
                    }
                }
            },
            'grossltv' => '0',
            'netLTV' => '0'
        };
    }

    private static Map<String, Object> buildAssetStubResponse() {
        return new Map<String, Object>{
            'Deviations' => new List<Object>{
                new Map<String, Object>{
                    'ApplicantType' => 'Borrower',
                    'Rules' => new List<Object>{
                        buildRule(
                            '1037',
                            'HIGH RISK PROFILE',
                            'L6',
                            new List<Object>{
                                conditionEntry('Profile Type', 'NEGATIVE'),
                                conditionEntry('Loan Amount', '209434.0'),
                                conditionEntry('Category', 'SEP'),
                                conditionEntry('State Code IBL', 'TS'),
                                conditionEntry('Profession', 'ADVOCATE')
                            },
                            'Profile Deviation-NEGATIVE; Profile - ADVOCATE, Category - SEP, Loan Amount-209434.0,LTV - 6.16'
                        ),
                        buildRule(
                            '8323',
                            'Low Service Charges',
                            'L3',
                            new List<Object>{ conditionEntry('Service Charge', '1400.0') },
                            'Low Service charges - 1400.0'
                        ),
                        buildRule(
                            '9323',
                            'Low Documentation Charges',
                            'L4.5',
                            new List<Object>{ conditionEntry('Doc Charge', '1800.0') },
                            'Low Documentation charges - 1800.0'
                        ),
                        buildRule(
                            '3271',
                            'Age of vehicle loan maturity',
                            null,
                            new List<Object>{ conditionEntry('Age of vehicle loan maturity', '2.2') },
                            'Age of Vehicle loan maturity - 2.2'
                        )
                    }
                },
                new Map<String, Object>{
                    'ApplicantType' => 'G1',
                    'Rules' => new List<Object>()
                }
            },
            'grossltv' => '6.16',
            'netLTV' => '6.16'
        };
    }

    private static Map<String, Object> buildRule(
        String deviationId,
        String deviationName,
        Object level,
        List<Object> conditionValues,
        String displayDeviation
    ) {
        return new Map<String, Object>{
            'DeviationId' => deviationId,
            'DeviationName' => deviationName,
            'Level' => level,
            'conditionValues' => conditionValues,
            'displayDeviation' => displayDeviation
        };
    }

    private static Map<String, Object> conditionEntry(String variableName, String variableValue) {
        return new Map<String, Object>{
            'variableName' => variableName,
            'variableValue' => variableValue
        };
    }

    private static List<RuleCandidate> parseRulesFromResponse(
        Map<String, Object> response,
        String callType
    ) {
        List<RuleCandidate> candidates = new List<RuleCandidate>();
        if (response == null) {
            return candidates;
        }

        String deviationTypeValue = TYPE_GLOBAL.equalsIgnoreCase(callType)
            ? DEVIATION_TYPE_AUTO
            : DEVIATION_TYPE_MANUAL;

        for (Object deviationBlockObj : getObjectList(response, 'Deviations')) {
            if (!(deviationBlockObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> deviationBlock = (Map<String, Object>) deviationBlockObj;
            String applicantType = getStringValue(deviationBlock, 'ApplicantType');

            for (Object ruleObj : getObjectList(deviationBlock, 'Rules')) {
                if (!(ruleObj instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> rule = (Map<String, Object>) ruleObj;
                candidates.add(new RuleCandidate(
                    getStringValue(rule, 'DeviationId'),
                    getStringValue(rule, 'DeviationName'),
                    normalizeLevel(rule.get('Level')),
                    resolveDescription(rule),
                    applicantType,
                    rule.get('conditionValues'),
                    deviationTypeValue,
                    callType
                ));
            }
        }

        return candidates;
    }

    private static Set<String> loadExistingDedupeKeys(Id lineItemId) {
        Set<String> keys = new Set<String>();
        for (Deviations__c existing : [
            SELECT DeviationID__c, Deviation_Level__c
            FROM Deviations__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
        ]) {
            keys.add(buildDedupeKey(existing.DeviationID__c, existing.Deviation_Level__c));
        }
        return keys;
    }

    private static String buildDedupeKey(String deviationId, String deviationLevel) {
        String normalizedId = String.isBlank(deviationId) ? '' : deviationId.trim();
        String normalizedLevel = normalizeLevel(deviationLevel);
        return normalizedId + '|' + normalizedLevel;
    }

    private static String normalizeLevel(Object levelValue) {
        if (levelValue == null) {
            return '';
        }
        return String.valueOf(levelValue).trim();
    }

    private static String resolveDescription(Map<String, Object> rule) {
        String displayDeviation = getStringValue(rule, 'displayDeviation');
        if (String.isNotBlank(displayDeviation)) {
            return truncate(displayDeviation, DESCRIPTION_MAX_LENGTH);
        }
        return truncate(getStringValue(rule, 'DeviationName'), DESCRIPTION_MAX_LENGTH);
    }

    private static Deviations__c buildDeviationRecord(
        RuleCandidate candidate,
        Id lineItemId,
        Integer rowIndex
    ) {
        Deviations__c deviation = new Deviations__c(
            Application_Line_Items__c = lineItemId,
            DeviationID__c = candidate.deviationId,
            Deviation_Description__c = candidate.description,
            Deviation_Level__c = candidate.deviationLevel,
            Role__c = resolveStubDeviationRole(rowIndex),
            Deviation_Type__c = candidate.deviationTypeValue,
            Type_Of_Deviation__c = resolveTypeOfDeviation(candidate.callType),
            Active__c = true,
            Remarks__c = buildRemarksJson(candidate)
        );
        return deviation;
    }

    private static String resolveTypeOfDeviation(String callType) {
        return TYPE_ASSET.equalsIgnoreCase(callType)
            ? TYPE_OF_DEVIATION_ASSET
            : TYPE_OF_DEVIATION_GLOBAL;
    }

    private static String buildRemarksJson(RuleCandidate candidate) {
        Map<String, Object> remarksPayload = new Map<String, Object>{
            'integrationName' => INTEGRATION_NAME,
            'callType' => candidate.callType,
            'applicantType' => candidate.applicantType,
            'deviationName' => candidate.deviationName,
            'conditionValues' => candidate.conditionValues
        };
        return JSON.serialize(remarksPayload);
    }

    private static List<Id> insertDeviations(List<Deviations__c> deviations) {
        if (deviations.isEmpty()) {
            return new List<Id>();
        }

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.CREATABLE,
            deviations
        );
        insert decision.getRecords();

        List<Id> createdIds = new List<Id>();
        for (SObject record : decision.getRecords()) {
            createdIds.add(record.Id);
        }
        return createdIds;
    }

    private static Id resolveApplicationLineItemId(Id applicationId) {
        List<Application_Line_Item__c> lineItems = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return lineItems.isEmpty() ? null : lineItems[0].Id;
    }

    private static Id resolveApplicationId(Map<String, Object> args) {
        Id fromApplicationId = parseIdValue(args.get('applicationId'));
        if (fromApplicationId != null) {
            return fromApplicationId;
        }
        return parseIdValue(args.get('recordId'));
    }

    private static String getStringValue(Map<String, Object> source, String key) {
        if (source == null || !source.containsKey(key) || source.get(key) == null) {
            return '';
        }
        return String.valueOf(source.get(key)).trim();
    }

    private static List<Object> getObjectList(Map<String, Object> source, String key) {
        Object rawValue = source != null ? source.get(key) : null;
        if (rawValue == null) {
            return new List<Object>();
        }
        if (rawValue instanceof List<Object>) {
            return (List<Object>) rawValue;
        }
        try {
            Object reparsed = JSON.deserializeUntyped(JSON.serialize(rawValue));
            if (reparsed instanceof List<Object>) {
                return (List<Object>) reparsed;
            }
        } catch (Exception ex) {
            return new List<Object>();
        }
        return new List<Object>();
    }

    private static Map<String, Object> asStringObjectMap(Object rawValue) {
        if (rawValue instanceof Map<String, Object>) {
            return (Map<String, Object>) rawValue;
        }
        if (rawValue == null) {
            return null;
        }
        try {
            Object reparsed = JSON.deserializeUntyped(JSON.serialize(rawValue));
            if (reparsed instanceof Map<String, Object>) {
                return (Map<String, Object>) reparsed;
            }
        } catch (Exception ex) {
            return null;
        }
        return null;
    }

    private static Id parseIdValue(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        return String.isBlank(value) ? null : (Id) value;
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0) {
            return value == null ? '' : value;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    private static Map<String, Object> failure(String message) {
        return new Map<String, Object>{
            'isSuccess' => false,
            'message' => message
        };
    }

    private class RuleCandidate {
        public String deviationId { get; private set; }
        public String deviationName { get; private set; }
        public String deviationLevel { get; private set; }
        public String description { get; private set; }
        public String applicantType { get; private set; }
        public Object conditionValues { get; private set; }
        public String deviationTypeValue { get; private set; }
        public String callType { get; private set; }

        public RuleCandidate(
            String deviationId,
            String deviationName,
            String deviationLevel,
            String description,
            String applicantType,
            Object conditionValues,
            String deviationTypeValue,
            String callType
        ) {
            this.deviationId = deviationId;
            this.deviationName = deviationName;
            this.deviationLevel = deviationLevel;
            this.description = description;
            this.applicantType = applicantType;
            this.conditionValues = conditionValues;
            this.deviationTypeValue = deviationTypeValue;
            this.callType = callType;
        }
    }
}