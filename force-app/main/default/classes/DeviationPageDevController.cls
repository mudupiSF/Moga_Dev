/**
 * Dev-only deviation page data: global deviations + asset groups per application line item.
 * Action: getDeviationPageData
 */
public with sharing class DeviationPageDevController implements Callable {

    private static final String ACTION_GET_DEVIATION_PAGE_DATA = 'getDeviationPageData';
    private static final String TYPE_OF_DEVIATION_GLOBAL = 'Global';
    private static final String TYPE_OF_DEVIATION_ASSET = 'Asset';
    private static final List<String> STUB_DEVIATION_ROLES = new List<String>{
        'HHEAD',
        'ZH',
        'BH'
    };

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_GET_DEVIATION_PAGE_DATA.equalsIgnoreCase(action)) {
            return getDeviationPageDataInternal(safeArgs);
        }

        return failure('Unknown action: ' + action);
    }

    private Map<String, Object> getDeviationPageDataInternal(Map<String, Object> args) {
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
        Integer globalRowIndex = 0;

        if (!lineItemIds.isEmpty()) {
            for (Deviations__c deviation : queryDeviationsForLineItems(lineItemIds)) {
                Id lineItemId = deviation.Application_Line_Items__c;
                if (TYPE_OF_DEVIATION_ASSET.equalsIgnoreCase(deviation.Type_Of_Deviation__c)) {
                    if (!assetDeviationsByLineItem.containsKey(lineItemId)) {
                        assetDeviationsByLineItem.put(lineItemId, new List<Map<String, Object>>());
                    }
                    Integer assetRowIndex = assetDeviationsByLineItem.get(lineItemId).size();
                    assetDeviationsByLineItem.get(lineItemId).add(mapDeviationRow(deviation, assetRowIndex));
                } else if (TYPE_OF_DEVIATION_GLOBAL.equalsIgnoreCase(deviation.Type_Of_Deviation__c)) {
                    globalDeviations.add(mapDeviationRow(deviation, globalRowIndex));
                    globalRowIndex++;
                }
            }
        }

        List<Map<String, Object>> assetDeviationGroups = buildAssetDeviationGroups(lineItems, assetDeviationsByLineItem);

        return new Map<String, Object>{
            'isSuccess' => true,
            'globalDeviations' => globalDeviations,
            'assetDeviationGroups' => assetDeviationGroups
        };
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