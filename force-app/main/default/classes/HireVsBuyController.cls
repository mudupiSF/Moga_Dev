public with sharing class HireVsBuyController implements Callable {

    private static final String ACTION_GET = 'getHireVsBuyData';
    private static final String ACTION_SAVE = 'saveHireVsBuyData';
    public static final String TYPE_HIRE_VS_BUY = 'Hire Vs Buy';

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> normalizedArgs = normalizeArgs(args);
        if (ACTION_GET.equalsIgnoreCase(action)) {
            return getHireVsBuyDataInternal(normalizedArgs);
        }
        if (ACTION_SAVE.equalsIgnoreCase(action)) {
            return saveHireVsBuyDataInternal(normalizedArgs);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    public static Boolean hasHireVsBuyForAsset(Id assetId) {
        if (assetId == null) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM Viability_Check__c
            WHERE Asset__c = :assetId
              AND Type__c = :TYPE_HIRE_VS_BUY
            WITH SECURITY_ENFORCED
        ] > 0;
    }

    private static Map<String, Object> getHireVsBuyDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            Id applicationId = parseRecordId(args != null ? args.get('recordId') : null);
            if (applicationId == null) {
                result.put('loadError', 'Application record is required');
                return result;
            }

            AssetContext assetContext = resolveAssetContext(applicationId, args);
            if (assetContext == null) {
                result.put('loadError', 'Asset ID is required to load Hire vs Buy details');
                return result;
            }

            putAssetContext(result, assetContext);
            Viability_Check__c record = resolveHireVsBuyByAsset(assetContext.asset.Id);
            if (record != null) {
                result.put('hasExistingData', true);
                result.put('viabilityId', record.Id);
                putFormValuesFromRecord(result, record);
            } else {
                result.put('hasExistingData', false);
                putDefaultFormValues(result);
            }
        } catch (Exception e) {
            result.put('loadError', e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> saveHireVsBuyDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unable to save Hire vs Buy details'
        };
        Id applicationId = parseRecordId(args != null ? args.get('recordId') : null);
        if (applicationId == null) {
            result.put('message', 'Application record is required');
            return result;
        }

        AssetContext assetContext = resolveAssetContext(applicationId, args);
        if (assetContext == null) {
            result.put('message', 'Asset ID is required before saving Hire vs Buy');
            return result;
        }

        Viability_Check__c record = resolveHireVsBuyByAsset(assetContext.asset.Id);
        if (record == null) {
            record = new Viability_Check__c(
                Asset__c = assetContext.asset.Id,
                Type__c = TYPE_HIRE_VS_BUY
            );
        }

        applyFormValuesToRecord(record, args, assetContext.asset.Model__c);

        try {
            upsert record;
            result.put('isSuccess', true);
            result.put('message', 'Hire vs Buy details saved');
            result.put('viabilityId', record.Id);
            result.put('hasExistingData', true);
            putAssetContext(result, assetContext);
            putFormValuesFromRecord(result, record);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        return result;
    }

    private static void putAssetContext(Map<String, Object> result, AssetContext assetContext) {
        result.put('assetId', assetContext.asset.Id);
        result.put('assetMake', assetContext.asset.Make__c);
        result.put('assetModel', assetContext.asset.Model__c);
        result.put('vehicleModelCode', assetContext.asset.Model__c);
        result.put('productType', assetContext.productType);
    }

    private static void putDefaultFormValues(Map<String, Object> result) {
        result.put('typeOfWork', 'Market Load');
        result.put('hoursPerDay', 8);
        result.put('workingDaysPerMonth', 25);
        result.put('monthlyRunningHours', 0);
        result.put('ratePerHour', 450);
        result.put('monthlyChargesForHire', 0);
        result.put('fuelAverageLitrePerHour', 2.5);
        result.put('costPerLitreFuel', 100);
        result.put('fuelCost', 0);
        result.put('driversSalaryAllowances', 15000);
        result.put('insuranceTaxesEtc', 5000);
        result.put('repairServicingMisc', 2000);
        result.put('emi', 12000);
        result.put('existingEmi', 0);
        result.put('totalEmi', 0);
        result.put('totalExpensesOwnership', 0);
        result.put('hireVsBuyDifference', 0);
        result.put('hireVsBuyFavourable', 'NON FAVOURABLE');
    }

    private static void putFormValuesFromRecord(Map<String, Object> result, Viability_Check__c record) {
        result.put('typeOfWork', record.Type_of_work__c);
        result.put('hoursPerDay', record.NO_OF_HOURS_MACHINE_WILL_WORK_PER_DAY__c);
        result.put('workingDaysPerMonth', record.NO_OF_DAYS_THE_MACHINE_WILL_WORK_PER_MON__c);
        result.put('monthlyRunningHours', record.Monthly_running_in_hours__c);
        result.put('ratePerHour', record.RATE_PER_HOUR_ESTIMATED_TO_REALISE_RS__c);
        result.put('monthlyChargesForHire', record.Monthly_charges_for_hire__c);
        result.put('fuelAverageLitrePerHour', record.FUEL_CONSUMPTION_PER_HOUR__c);
        result.put('costPerLitreFuel', record.FUEL_COST_PER_LITRE_RS__c);
        result.put('fuelCost', record.Cost_Of_Fuel_Per_Month__c);
        result.put('driversSalaryAllowances', record.OPERATORS_SALARY__c);
        result.put('insuranceTaxesEtc', record.MOTOR_TAX_PERMIT_COST__c);
        result.put('repairServicingMisc', record.MAINTAINENCE_PARTS_COST__c);
        result.put('emi', record.INSTALMENT_AMOUNT__c);
        result.put('existingEmi', record.Emi__c);
        result.put('totalEmi', record.Total_EMI__c);
        result.put('totalExpensesOwnership', record.TOTAL_EXPENSES__c);
        result.put('hireVsBuyDifference', record.HireVsBuy_Amt__c);
        result.put('hireVsBuyFavourable', record.HireVsBuy_Decision__c);
    }

    private static void applyFormValuesToRecord(
        Viability_Check__c record,
        Map<String, Object> args,
        String assetModel
    ) {
        record.Type__c = TYPE_HIRE_VS_BUY;
        record.Vehicle_Model__c = assetModel;
        record.Type_of_work__c = parseString(args.get('typeOfWork'));
        record.NO_OF_HOURS_MACHINE_WILL_WORK_PER_DAY__c = parseDecimal(args.get('hoursPerDay'));
        record.NO_OF_DAYS_THE_MACHINE_WILL_WORK_PER_MON__c = parseDecimal(args.get('workingDaysPerMonth'));
        record.Monthly_running_in_hours__c = parseDecimal(args.get('monthlyRunningHours'));
        record.RATE_PER_HOUR_ESTIMATED_TO_REALISE_RS__c = parseDecimal(args.get('ratePerHour'));
        record.Monthly_charges_for_hire__c = parseDecimal(args.get('monthlyChargesForHire'));
        record.FUEL_CONSUMPTION_PER_HOUR__c = parseDecimal(args.get('fuelAverageLitrePerHour'));
        record.FUEL_COST_PER_LITRE_RS__c = parseDecimal(args.get('costPerLitreFuel'));
        record.Cost_Of_Fuel_Per_Month__c = parseDecimal(args.get('fuelCost'));
        record.OPERATORS_SALARY__c = parseDecimal(args.get('driversSalaryAllowances'));
        record.MOTOR_TAX_PERMIT_COST__c = parseDecimal(args.get('insuranceTaxesEtc'));
        record.MAINTAINENCE_PARTS_COST__c = parseDecimal(args.get('repairServicingMisc'));
        record.INSTALMENT_AMOUNT__c = parseDecimal(args.get('emi'));
        record.Emi__c = parseDecimal(args.get('existingEmi'));
        record.Total_EMI__c = parseDecimal(args.get('totalEmi'));
        record.TOTAL_EXPENSES__c = parseDecimal(args.get('totalExpensesOwnership'));
        record.HireVsBuy_Amt__c = parseDecimal(args.get('hireVsBuyDifference'));
        record.HireVsBuy_Decision__c = parseString(args.get('hireVsBuyFavourable'));
    }

    private static Viability_Check__c resolveHireVsBuyByAsset(Id assetId) {
        List<Viability_Check__c> records = [
            SELECT
                Id,
                Type_of_work__c,
                NO_OF_HOURS_MACHINE_WILL_WORK_PER_DAY__c,
                NO_OF_DAYS_THE_MACHINE_WILL_WORK_PER_MON__c,
                Monthly_running_in_hours__c,
                RATE_PER_HOUR_ESTIMATED_TO_REALISE_RS__c,
                Monthly_charges_for_hire__c,
                FUEL_CONSUMPTION_PER_HOUR__c,
                FUEL_COST_PER_LITRE_RS__c,
                Cost_Of_Fuel_Per_Month__c,
                OPERATORS_SALARY__c,
                MOTOR_TAX_PERMIT_COST__c,
                MAINTAINENCE_PARTS_COST__c,
                INSTALMENT_AMOUNT__c,
                Emi__c,
                Total_EMI__c,
                TOTAL_EXPENSES__c,
                HireVsBuy_Amt__c,
                HireVsBuy_Decision__c
            FROM Viability_Check__c
            WHERE Asset__c = :assetId
              AND Type__c = :TYPE_HIRE_VS_BUY
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    private static AssetContext resolveAssetContext(Id applicationId, Map<String, Object> args) {
        Id assetId = parseRecordId(args != null ? args.get('assetId') : null);
        if (assetId == null) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT
                Id,
                Model__c,
                Make__c
            FROM Asset__c
            WHERE Id = :assetId
              AND Application_Line_Items__r.Application__c = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (assets.isEmpty()) {
            return null;
        }
        Asset__c asset = assets[0];
        return new AssetContext(asset, resolveMmvProductTypeToken(applicationId));
    }

    private static String resolveMmvProductTypeToken(Id applicationId) {
        if (applicationId == null) {
            return '';
        }
        List<Application_Line_Item__c> items = [
            SELECT Product__c, Sub_Product__c
            FROM Application_Line_Item__c
            WHERE Application__c = :applicationId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
        for (Application_Line_Item__c item : items) {
            String token = GenericUtility.resolveProductTypeToken(item.Product__c, item.Sub_Product__c);
            if (String.isNotBlank(token)) {
                return token;
            }
        }
        return '';
    }

    private static Map<String, Object> normalizeArgs(Map<String, Object> args) {
        if (args == null) {
            return new Map<String, Object>();
        }
        if (args.containsKey('params') && args.get('params') instanceof Map<String, Object>) {
            Map<String, Object> merged = new Map<String, Object>(args);
            merged.putAll((Map<String, Object>) args.get('params'));
            return merged;
        }
        return args;
    }

    private static Id parseRecordId(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        return String.isBlank(value) ? null : (Id) value;
    }

    private static String parseString(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        return String.isBlank(value) ? null : value;
    }

    private static Decimal parseDecimal(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        if (String.isBlank(value)) {
            return null;
        }
        return Decimal.valueOf(value);
    }

    private class AssetContext {
        private Asset__c asset;
        private String productType;

        private AssetContext(Asset__c assetRecord, String applicationProductType) {
            asset = assetRecord;
            productType = applicationProductType == null ? '' : applicationProductType;
        }
    }
}