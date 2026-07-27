public with sharing class ViabilityCheckController implements Callable {

    private static final String ACTION_GET = 'getViabilityCheckData';
    private static final String ACTION_SAVE = 'saveViabilityCheckData';
    private static final String ACTION_SAVE_CV = 'saveCvViabilityCheckData';
    private static final String ACTION_SAVE_KMS = 'saveKmsViabilityCheckData';
    private static final String ACTION_CV_API = 'cvViabilityApi';
    private static final String TYPE_VIABILITY = 'Viability';

    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> normalizedArgs = normalizeArgs(args);
        if (ACTION_GET.equalsIgnoreCase(action)) {
            return getViabilityCheckDataInternal(normalizedArgs);
        }
        if (ACTION_SAVE.equalsIgnoreCase(action)) {
            return saveViabilityCheckDataInternal(normalizedArgs);
        }
        if (ACTION_SAVE_CV.equalsIgnoreCase(action)) {
            return saveCvViabilityCheckDataInternal(normalizedArgs);
        }
        if (ACTION_SAVE_KMS.equalsIgnoreCase(action)) {
            return saveKmsViabilityCheckDataInternal(normalizedArgs);
        }
        if (ACTION_CV_API.equalsIgnoreCase(action)) {
            return cvViabilityApiInternal(normalizedArgs);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getViabilityCheckData(String recordId, String assetId) {
        Map<String, Object> args = new Map<String, Object>();
        args.put('recordId', recordId);
        args.put('assetId', assetId);
        return getViabilityCheckDataInternal(args);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> saveViabilityCheckData(
        String recordId,
        String assetId,
        String distance,
        String grossReceiptsMonth,
        String numberOfVehiclesOwned,
        String expense,
        String vehicleRoute
    ) {
        Map<String, Object> args = new Map<String, Object>{
            'recordId' => recordId,
            'assetId' => assetId,
            'distance' => distance,
            'grossReceiptsMonth' => grossReceiptsMonth,
            'numberOfVehiclesOwned' => numberOfVehiclesOwned,
            'expense' => expense,
            'vehicleRoute' => vehicleRoute
        };
        return saveViabilityCheckDataInternal(args);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> saveCvViabilityCheckData(Map<String, Object> payload) {
        return saveCvViabilityCheckDataInternal(payload);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> saveKmsViabilityCheckData(Map<String, Object> payload) {
        return saveKmsViabilityCheckDataInternal(payload);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> cvViabilityApi(Map<String, Object> payload) {
        return cvViabilityApiInternal(payload);
    }

    private static Map<String, Object> getViabilityCheckDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            Id applicationId = parseRecordId(args != null ? args.get('recordId') : null);
            if (applicationId == null) {
                return result;
            }
            String productType = resolveApplicationProduct(applicationId);
            result.put('productType', productType);

            Asset__c asset = resolveAsset(applicationId, args);
            if (asset == null) {
                return result;
            }
            result.put('assetId', asset.Id);
            result.put('purposeOfPurchase', asset.Purpose_of_purchase__c);

            Viability_Check__c viability = resolveViabilityByAsset(asset.Id);
            if (viability == null) {
                return result;
            }
            result.put('viabilityId', viability.Id);
            result.put('hasCompleteViabilityData', isViabilityCheckComplete(viability));
            result.put('distance', viability.Distance__c);
            result.put('grossReceiptsMonth', viability.Gross_Receipts_Month__c);
            result.put('numberOfVehiclesOwned', viability.Number_of_vehicle_owned__c);
            result.put('expense', viability.TOTAL_EXPENSES__c);
            result.put('vehicleRoute', viability.Vehicle_Route__c);
            result.put('viabilityRatio', viability.Viability_Ratio__c);
            result.put('assetDeployment', viability.Asset_Deployment__c);
            result.put('daysPerMonth', viability.NO_OF_DAYS_THE_MACHINE_WILL_WORK_PER_MON__c);
            result.put('hoursPerDay', viability.NO_OF_HOURS_MACHINE_WILL_WORK_PER_DAY__c);
            result.put('ratePerHour', viability.RATE_PER_HOUR_ESTIMATED_TO_REALISE_RS__c);
            result.put('estimatedMonthlyIncome', viability.ESTIMATED_AVERAGE_INCOME_MONTH__c);
            result.put('fuelCostPerLitre', viability.FUEL_COST_PER_LITRE_RS__c);
            result.put('fuelConsumptionPerHour', viability.FUEL_CONSUMPTION_PER_HOUR__c);
            result.put('costFuelPerMonth', viability.Cost_Of_Fuel_Per_Month__c);
            result.put('costFuelPerTrip', viability.Cost_Of_Fuel_Per_Trip__c);
            result.put('fromLocation', viability.From_Location__c);
            result.put('toLocation', viability.To_Location__c);
            result.put('tripsPerMonth', viability.Trips_Per_Month__c);
            result.put('kilometersPerTrip', viability.No_Of_Kms_Per_Trip__c);
            result.put('averageRatePerTrip', viability.Average_Rate_Per_Trip__c);
            result.put('operatorSalary', viability.OPERATORS_SALARY__c);
            result.put('maintenanceParts', viability.MAINTAINENCE_PARTS_COST__c);
            result.put('tyreCost', viability.TYRE_COST__c);
            result.put('taxCess', viability.MOTOR_TAX_PERMIT_COST__c);
            result.put('totalExpenses', viability.TOTAL_EXPENSES__c);
            result.put('others', viability.OTHERS__c);
            result.put('grossSurplus', viability.GROSS_SURPLUS__c);
            result.put('instalment', viability.INSTALMENT_AMOUNT__c);
            result.put('netSurplus', viability.NET_SURPLUS__c);
        } catch (Exception e) {
            result.put('loadError', e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> saveViabilityCheckDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unable to save viability details'
        };
        Id applicationId = parseRecordId(args.get('recordId'));
        if (applicationId == null) {
            result.put('message', 'Record ID is required');
            return result;
        }
        Asset__c asset = resolveAsset(applicationId, args);
        if (asset == null) {
            result.put('message', 'Asset ID is required before saving viability');
            return result;
        }

        Viability_Check__c viability = resolveViabilityByAsset(asset.Id);
        if (viability == null) {
            viability = new Viability_Check__c(
                Asset__c = asset.Id,
                Type__c = TYPE_VIABILITY
            );
        }
        viability.Type__c = TYPE_VIABILITY;

        viability.Distance__c = parseDecimal(args.get('distance'));
        viability.Gross_Receipts_Month__c = parseDecimal(args.get('grossReceiptsMonth'));
        viability.Number_of_vehicle_owned__c = parseDecimal(args.get('numberOfVehiclesOwned'));
        viability.TOTAL_EXPENSES__c = parseDecimal(args.get('expense'));
        viability.Vehicle_Route__c = parseString(args.get('vehicleRoute'));
        viability.Viability_Ratio__c = calculateViabilityRatio(
            viability.Gross_Receipts_Month__c,
            viability.TOTAL_EXPENSES__c
        );

        try {
            upsert viability;
            result.put('isSuccess', true);
            result.put('message', 'Viability details saved');
            result.put('viabilityId', viability.Id);
            result.put('assetId', asset.Id);
            result.put('viabilityRatio', viability.Viability_Ratio__c);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> saveCvViabilityCheckDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unable to save viability details'
        };
        Id applicationId = parseRecordId(args.get('recordId'));
        if (applicationId == null) {
            result.put('message', 'Record ID is required');
            return result;
        }
        Asset__c asset = resolveAsset(applicationId, args);
        if (asset == null) {
            result.put('message', 'Asset ID is required before saving viability');
            return result;
        }

        Viability_Check__c viability = resolveViabilityByAsset(asset.Id);
        if (viability == null) {
            viability = new Viability_Check__c(
                Asset__c = asset.Id,
                Type__c = TYPE_VIABILITY
            );
        }
        viability.Type__c = TYPE_VIABILITY;

        viability.Asset_Deployment__c = parseString(args.get('assetDeployment'));
        viability.NO_OF_DAYS_THE_MACHINE_WILL_WORK_PER_MON__c = parseDecimal(args.get('daysPerMonth'));
        viability.NO_OF_HOURS_MACHINE_WILL_WORK_PER_DAY__c = parseDecimal(args.get('hoursPerDay'));
        viability.RATE_PER_HOUR_ESTIMATED_TO_REALISE_RS__c = parseDecimal(args.get('ratePerHour'));
        viability.ESTIMATED_AVERAGE_INCOME_MONTH__c = parseDecimal(args.get('estimatedMonthlyIncome'));
        viability.FUEL_COST_PER_LITRE_RS__c = parseDecimal(args.get('fuelCostPerLitre'));
        viability.FUEL_CONSUMPTION_PER_HOUR__c = parseDecimal(args.get('fuelConsumptionPerHour'));
        viability.Cost_Of_Fuel_Per_Month__c = parseDecimal(args.get('costFuelPerMonth'));
        viability.OPERATORS_SALARY__c = parseDecimal(args.get('operatorSalary'));
        viability.MAINTAINENCE_PARTS_COST__c = parseDecimal(args.get('maintenanceParts'));
        viability.TYRE_COST__c = parseDecimal(args.get('tyreCost'));
        viability.MOTOR_TAX_PERMIT_COST__c = parseDecimal(args.get('taxCess'));
        viability.OTHERS__c = parseDecimal(args.get('others'));
        viability.TOTAL_EXPENSES__c = parseDecimal(args.get('totalExpenses'));
        viability.GROSS_SURPLUS__c = parseDecimal(args.get('grossSurplus'));
        viability.INSTALMENT_AMOUNT__c = parseDecimal(args.get('instalment'));
        viability.NET_SURPLUS__c = parseDecimal(args.get('netSurplus'));
        // CV flow: prefer ratio returned by external API.
        // Fallback to computed ratio only when API ratio is absent.
        Decimal apiRatio = parseDecimal(args.get('viabilityRatio'));
        viability.Viability_Ratio__c = apiRatio != null
            ? apiRatio
            : calculateViabilityRatio(
                viability.ESTIMATED_AVERAGE_INCOME_MONTH__c,
                viability.TOTAL_EXPENSES__c
            );

        try {
            upsert viability;
            result.put('isSuccess', true);
            result.put('message', 'Viability details saved');
            result.put('viabilityId', viability.Id);
            result.put('assetId', asset.Id);
            result.put('viabilityRatio', viability.Viability_Ratio__c);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> saveKmsViabilityCheckDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unable to save viability details'
        };
        Id applicationId = parseRecordId(args.get('recordId'));
        if (applicationId == null) {
            result.put('message', 'Record ID is required');
            return result;
        }
        Asset__c asset = resolveAsset(applicationId, args);
        if (asset == null) {
            result.put('message', 'Asset ID is required before saving viability');
            return result;
        }

        Viability_Check__c viability = resolveViabilityByAsset(asset.Id);
        if (viability == null) {
            viability = new Viability_Check__c(
                Asset__c = asset.Id,
                Type__c = TYPE_VIABILITY
            );
        }
        viability.Type__c = TYPE_VIABILITY;

        // KMS UI fields mapped to Viability_Check__c columns. 
        viability.Vehicle_Route__c = parseString(args.get('vehicleRoute'));
        viability.From_Location__c = parseString(args.get('fromLocation'));
        viability.To_Location__c = parseString(args.get('toLocation'));
        viability.Trips_Per_Month__c = parseDecimal(args.get('tripsPerMonth'));
        viability.No_Of_Kms_Per_Trip__c = parseDecimal(args.get('kilometersPerTrip'));
        viability.Average_Rate_Per_Trip__c = parseDecimal(args.get('averageRatePerTrip'));
        viability.ESTIMATED_AVERAGE_INCOME_MONTH__c = parseDecimal(args.get('estimatedMonthlyIncome'));
        viability.FUEL_COST_PER_LITRE_RS__c = parseDecimal(args.get('fuelRatePerLitre'));
        viability.Cost_Of_Fuel_Per_Trip__c = parseDecimal(args.get('costFuelPerTrip'));
        viability.Cost_Of_Fuel_Per_Month__c = parseDecimal(args.get('costFuelPerMonth'));
        viability.OPERATORS_SALARY__c = parseDecimal(args.get('salaries'));
        viability.MAINTAINENCE_PARTS_COST__c = parseDecimal(args.get('maintenance'));
        viability.TYRE_COST__c = parseDecimal(args.get('tyreCost'));
        viability.MOTOR_TAX_PERMIT_COST__c = parseDecimal(args.get('motorTaxPermitCost'));
        viability.OTHERS__c = parseDecimal(args.get('others'));
        viability.TOTAL_EXPENSES__c = parseDecimal(args.get('totalExpenses'));
        viability.GROSS_SURPLUS__c = parseDecimal(args.get('grossSurplus'));
        viability.INSTALMENT_AMOUNT__c = parseDecimal(args.get('instalment'));
        viability.NET_SURPLUS__c = parseDecimal(args.get('netSurplus'));
        viability.Viability_Ratio__c = calculateViabilityRatio(
            viability.ESTIMATED_AVERAGE_INCOME_MONTH__c,
            viability.TOTAL_EXPENSES__c
        );

        try {
            upsert viability;
            result.put('isSuccess', true);
            result.put('message', 'Viability details saved');
            result.put('viabilityId', viability.Id);
            result.put('assetId', asset.Id);
            result.put('viabilityRatio', viability.Viability_Ratio__c);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> cvViabilityApiInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => true,
            'message' => 'CV viability API placeholder success'
        };
        Map<String, Object> data = new Map<String, Object>{
            'calculationBasis' => 'Hourly',
            'cvHourlyValues' => new Map<String, Object>{
                'estimatedMonthlyIncome' => args != null ? args.get('estimatedMonthlyIncome') : null,
                'totalExpenses' => args != null ? args.get('totalExpenses') : null,
                'viabilityRatio' => calculateViabilityRatio(
                    parseDecimal(args != null ? args.get('estimatedMonthlyIncome') : null),
                    parseDecimal(args != null ? args.get('totalExpenses') : null)
                )
            },
            'kmsValues' => new Map<String, Object>()
        };
        result.put('data', data);
        return result;
    }

    public static Boolean hasCompleteViabilityForAsset(Id assetId) {
        if (assetId == null) {
            return false;
        }
        return isViabilityCheckComplete(resolveViabilityByAsset(assetId));
    }

    private static Boolean isViabilityCheckComplete(Viability_Check__c record) {
        if (record == null || record.TOTAL_EXPENSES__c == null) {
            return false;
        }
        if (String.isNotBlank(record.Asset_Deployment__c)) {
            return record.ESTIMATED_AVERAGE_INCOME_MONTH__c != null;
        }
        if (String.isNotBlank(record.From_Location__c) || record.Trips_Per_Month__c != null) {
            return String.isNotBlank(record.Vehicle_Route__c)
                && record.ESTIMATED_AVERAGE_INCOME_MONTH__c != null;
        }
        return record.Distance__c != null
            && record.Gross_Receipts_Month__c != null
            && String.isNotBlank(record.Vehicle_Route__c);
    }

    private static Id parseRecordId(Object raw) {
        if (raw == null) {
            return null;
        }
        String value = String.valueOf(raw).trim();
        if (value == '') {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, Object> normalizeArgs(Map<String, Object> args) {
        if (args == null) {
            return new Map<String, Object>();
        }
        Map<String, Object> normalized = new Map<String, Object>();
        normalized.putAll(args);
        Object rawParams = args.get('params');
        try {
            Map<String, Object> params = (Map<String, Object>) rawParams;
            if (params != null) {
                normalized.putAll(params);
            }
        } catch (Exception e) {
            // Ignore malformed params and continue with top-level args.
        }
        return normalized;
    }

    private static String resolveApplicationProduct(Id applicationId) {
        if (applicationId == null) {
            return '';
        }
        List<Application__c> applications = [
            SELECT Id, Product__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (applications.isEmpty() || applications[0].Product__c == null) {
            return '';
        }
        return applications[0].Product__c;
    }

    private static Asset__c resolveAsset(Id applicationId, Map<String, Object> args) {
        Id assetId = parseRecordId(args != null ? args.get('assetId') : null);
        if (assetId == null || applicationId == null) {
            return null;
        }
        List<Asset__c> assets = [
            SELECT Id, Purpose_of_purchase__c
            FROM Asset__c
            WHERE Id = :assetId
              AND Application_Line_Items__r.Application__c = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return assets.isEmpty() ? null : assets[0];
    }

    private static Viability_Check__c resolveViabilityByAsset(Id assetId) {
        List<Viability_Check__c> records = [
            SELECT
                Id,
                Asset__c,
                Distance__c,
                Gross_Receipts_Month__c,
                Number_of_vehicle_owned__c,
                TOTAL_EXPENSES__c,
                Vehicle_Route__c,
                Asset_Deployment__c,
                Viability_Ratio__c,
                NO_OF_DAYS_THE_MACHINE_WILL_WORK_PER_MON__c,
                NO_OF_HOURS_MACHINE_WILL_WORK_PER_DAY__c,
                RATE_PER_HOUR_ESTIMATED_TO_REALISE_RS__c,
                ESTIMATED_AVERAGE_INCOME_MONTH__c,
                FUEL_COST_PER_LITRE_RS__c,
                FUEL_CONSUMPTION_PER_HOUR__c,
                Cost_Of_Fuel_Per_Month__c,
                Cost_Of_Fuel_Per_Trip__c,
                From_Location__c,
                To_Location__c,
                Trips_Per_Month__c,
                No_Of_Kms_Per_Trip__c,
                Average_Rate_Per_Trip__c,
                OPERATORS_SALARY__c,
                MAINTAINENCE_PARTS_COST__c,
                TYRE_COST__c,
                MOTOR_TAX_PERMIT_COST__c,
                OTHERS__c,
                GROSS_SURPLUS__c,
                INSTALMENT_AMOUNT__c,
                NET_SURPLUS__c
            FROM Viability_Check__c
            WHERE Asset__c = :assetId
              AND (Type__c = :TYPE_VIABILITY OR Type__c = null)
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    private static String parseString(Object raw) {
        if (raw == null) return null;
        String value = String.valueOf(raw).trim();
        return value == '' ? null : value;
    }

    private static Decimal parseDecimal(Object raw) {
        if (raw == null) return null;
        String value = String.valueOf(raw).trim().replace(',', '');
        if (value == '') return null;
        return Decimal.valueOf(value);
    }

    private static Decimal calculateViabilityRatio(Decimal grossReceiptsMonth, Decimal expense) {
        if (expense == null || expense <= 0) {
            return 0;
        }
        Decimal gross = grossReceiptsMonth == null ? 0 : grossReceiptsMonth;
        return (gross / expense).setScale(2);
    }
}