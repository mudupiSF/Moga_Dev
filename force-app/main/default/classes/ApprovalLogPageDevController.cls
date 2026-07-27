/**
 * Dev-only approval log data: loan term groups per application line item.
 * Action: getLoanTermGroups
 */
public with sharing class ApprovalLogPageDevController implements Callable {

    private static final String ACTION_GET_LOAN_TERM_GROUPS = 'getLoanTermGroups';
    private static final String LOG_TYPE_PROPOSAL = 'Proposal';
    private static final String PROPOSAL_STATUS_REJECT = 'Reject';

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> safeArgs = args != null ? args : new Map<String, Object>();

        if (ACTION_GET_LOAN_TERM_GROUPS.equalsIgnoreCase(action)) {
            return getLoanTermGroupsInternal(safeArgs);
        }

        return failure('Unknown action: ' + action);
    }

    private Map<String, Object> getLoanTermGroupsInternal(Map<String, Object> args) {
        Id applicationId = resolveApplicationId(args);
        if (applicationId == null) {
            return failure('Application Id is required.');
        }

        List<Proposal_Approval_Log__c> allLogRecords = queryProposalApprovalLogs(applicationId);
        List<Map<String, Object>> approvalHistory = buildApprovalHistoryRows(allLogRecords);
        Proposal_Approval_Log__c latestProposalLog = resolveLatestProposalDecisionLog(allLogRecords);

        String decisionValue = resolveLatestProposalDecision(latestProposalLog);
        String decisionRemarks = resolveLatestProposalRemarks(latestProposalLog);
        String rejectedFlag = resolveProposalRejectedFlag(approvalHistory);

        List<Application_Line_Item__c> lineItems = queryApplicationLineItems(applicationId);
        List<Map<String, Object>> loanTermGroups = new List<Map<String, Object>>();
        Integer total = lineItems.size();

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
                'decisionFieldsDecision' => decisionValue,
                'decisionFieldsRemarks' => decisionRemarks,
                'proposalRejectedByAuthority' => rejectedFlag,
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
            'loanTermGroups' => loanTermGroups
        };
    }

    private static List<Application_Line_Item__c> queryApplicationLineItems(Id applicationId) {
        return [
            SELECT Id,
                Loan_Amount__c,
                CRM_IRR__c,
                ROI__c,
                EMI_Amount__c,
                Tenure__c,
                First_EMI_Date__c,
                Second_EMI_Date__c,
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

    private static List<Proposal_Approval_Log__c> queryProposalApprovalLogs(Id applicationId) {
        return [
            SELECT Id,
                Type__c,
                Status__c,
                Remark__c,
                Proposal_Action__c,
                Proposal_Remark__c,
                CreatedDate
            FROM Proposal_Approval_Log__c
            WHERE Application__c = :applicationId
            ORDER BY CreatedDate DESC
        ];
    }

    private static List<Map<String, Object>> buildApprovalHistoryRows(List<Proposal_Approval_Log__c> allLogRecords) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        if (allLogRecords == null) {
            return rows;
        }
        for (Proposal_Approval_Log__c logRecord : allLogRecords) {
            if ('Deviation'.equalsIgnoreCase(logRecord.Type__c)
                || LOG_TYPE_PROPOSAL.equalsIgnoreCase(logRecord.Type__c)) {
                rows.add(new Map<String, Object>{
                    'action' => coalesceText(logRecord.Status__c, logRecord.Proposal_Action__c)
                });
            }
        }
        return rows;
    }

    private static Proposal_Approval_Log__c resolveLatestProposalDecisionLog(List<Proposal_Approval_Log__c> allLogRecords) {
        if (allLogRecords == null) {
            return null;
        }
        for (Proposal_Approval_Log__c logRecord : allLogRecords) {
            if (LOG_TYPE_PROPOSAL.equalsIgnoreCase(logRecord.Type__c)) {
                return logRecord;
            }
        }
        return null;
    }

    private static String resolveLatestProposalDecision(Proposal_Approval_Log__c logRecord) {
        if (logRecord == null) {
            return '';
        }
        return coalesceText(logRecord.Status__c, logRecord.Proposal_Action__c);
    }

    private static String resolveLatestProposalRemarks(Proposal_Approval_Log__c logRecord) {
        if (logRecord == null) {
            return '';
        }
        return coalesceText(logRecord.Proposal_Remark__c, logRecord.Remark__c);
    }

    private static String resolveProposalRejectedFlag(List<Map<String, Object>> approvalHistory) {
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

    private static Asset__c resolveLineItemAsset(Application_Line_Item__c lineItem) {
        if (lineItem == null || lineItem.Assets__r == null || lineItem.Assets__r.isEmpty()) {
            return null;
        }
        return lineItem.Assets__r[0];
    }

    private static String resolveVehicleVariant(Application_Line_Item__c lineItem) {
        Asset__c asset = resolveLineItemAsset(lineItem);
        if (asset == null) {
            return '';
        }
        return joinDisplayParts(
            new List<String>{ asset.Make__c, asset.Model__c, asset.Variant__c },
            ' '
        );
    }

    private static Decimal resolveFundedPremiumTotal(Application_Line_Item__c lineItem) {
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

    private static List<Map<String, Object>> buildEmiDateOptions(Date firstEmiDate) {
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

    private static String formatIsoDate(Date value) {
        if (value == null) {
            return '';
        }
        DateTime dateTimeValue = DateTime.newInstance(value, Time.newInstance(0, 0, 0, 0));
        return dateTimeValue.format('yyyy-MM-dd');
    }

    private static String formatDisplayDate(Date value) {
        if (value == null) {
            return '';
        }
        DateTime dateTimeValue = DateTime.newInstance(value, Time.newInstance(0, 0, 0, 0));
        return dateTimeValue.format('dd-MMM-yyyy');
    }

    private static String formatDecimal(Decimal value, Integer scale) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value.setScale(scale, System.RoundingMode.HALF_UP));
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

    private static String coalesceText(String primary, String fallback) {
        if (String.isNotBlank(primary)) {
            return primary.trim();
        }
        return String.isNotBlank(fallback) ? fallback.trim() : '';
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