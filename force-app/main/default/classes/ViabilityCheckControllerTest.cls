@IsTest
private class ViabilityCheckControllerTest {

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'Post Sanction Sales',
            Sub_Stage__c = 'Asset Details',
            Product__c = 'CV'
        );
        insert app;

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = app.Id,
            Loan_Amount__c = 750000
        );
        insert lineItem;

        insert new Asset__c(
            Application_Line_Items__c = lineItem.Id,
            Vehicle_type__c = 'New',
            Purpose_of_purchase__c = 'Commercial'
        );
    }

    private static Application__c applicationRecord() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Asset__c assetRecord() {
        return [SELECT Id FROM Asset__c LIMIT 1];
    }

    private static ViabilityCheckController controller() {
        return new ViabilityCheckController();
    }

    @IsTest
    static void testGetAndSavePvViability() {
        Application__c app = applicationRecord();
        Asset__c asset = assetRecord();

        Test.startTest();
        Map<String, Object> loadResult = ViabilityCheckController.getViabilityCheckData(
            String.valueOf(app.Id),
            String.valueOf(asset.Id)
        );
        Map<String, Object> saveResult = ViabilityCheckController.saveViabilityCheckData(
            String.valueOf(app.Id),
            String.valueOf(asset.Id),
            '120',
            '50000',
            '2',
            '25000',
            'Inter State'
        );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('isSuccess'));
    }

    @IsTest
    static void testSaveCvKmsAndCvApi() {
        Application__c app = applicationRecord();
        Asset__c asset = assetRecord();

        Test.startTest();
        Map<String, Object> cvSaveResult = (Map<String, Object>) controller().call(
            'saveCvViabilityCheckData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'assetDeployment' => 'Construction',
                'daysPerMonth' => '25',
                'hoursPerDay' => '8',
                'ratePerHour' => '500',
                'estimatedMonthlyIncome' => '100000',
                'fuelCostPerLitre' => '100',
                'fuelConsumptionPerHour' => '4',
                'costFuelPerMonth' => '8000',
                'operatorSalary' => '15000',
                'maintenanceParts' => '5000',
                'tyreCost' => '3000',
                'taxCess' => '2000',
                'others' => '1000',
                'totalExpenses' => '34000',
                'grossSurplus' => '66000',
                'instalment' => '20000',
                'netSurplus' => '46000',
                'viabilityRatio' => '2.94'
            }
        );
        Map<String, Object> kmsSaveResult = (Map<String, Object>) controller().call(
            'saveKmsViabilityCheckData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'vehicleRoute' => 'Inter State',
                'fromLocation' => 'Delhi',
                'toLocation' => 'Jaipur',
                'tripsPerMonth' => '20',
                'kilometersPerTrip' => '280',
                'averageRatePerTrip' => '5000',
                'estimatedMonthlyIncome' => '100000',
                'fuelRatePerLitre' => '100',
                'costFuelPerTrip' => '1500',
                'costFuelPerMonth' => '30000',
                'salaries' => '12000',
                'maintenance' => '4000',
                'tyreCost' => '2500',
                'motorTaxPermitCost' => '1500',
                'others' => '1000',
                'totalExpenses' => '51000',
                'grossSurplus' => '49000',
                'instalment' => '18000',
                'netSurplus' => '31000'
            }
        );
        Map<String, Object> apiResult = ViabilityCheckController.cvViabilityApi(
            new Map<String, Object>{
                'estimatedMonthlyIncome' => '90000',
                'totalExpenses' => '45000'
            }
        );
        Test.stopTest();

        System.assertEquals(true, cvSaveResult.get('isSuccess'));
    }

    @IsTest
    static void testCallableGetReloadAndAuraSaveWrappers() {
        Application__c app = applicationRecord();
        Asset__c asset = assetRecord();

        ViabilityCheckController.saveViabilityCheckData(
            String.valueOf(app.Id),
            String.valueOf(asset.Id),
            '10',
            '20000',
            '1',
            '10000',
            'Route'
        );

        Test.startTest();
        Map<String, Object> callableLoad = (Map<String, Object>) controller().call(
            'getViabilityCheckData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id
            }
        );
        Map<String, Object> auraCvSave = ViabilityCheckController.saveCvViabilityCheckData(
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'assetDeployment' => 'Construction',
                'daysPerMonth' => '20',
                'hoursPerDay' => '8',
                'ratePerHour' => '400',
                'estimatedMonthlyIncome' => '80000',
                'fuelCostPerLitre' => '95',
                'fuelConsumptionPerHour' => '3',
                'costFuelPerMonth' => '7000',
                'operatorSalary' => '12000',
                'maintenanceParts' => '4000',
                'tyreCost' => '2500',
                'taxCess' => '1500',
                'others' => '1000',
                'totalExpenses' => '28000',
                'grossSurplus' => '52000',
                'instalment' => '15000',
                'netSurplus' => '37000'
            }
        );
        Map<String, Object> auraKmsSave = ViabilityCheckController.saveKmsViabilityCheckData(
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'vehicleRoute' => 'Route',
                'fromLocation' => 'A',
                'toLocation' => 'B',
                'tripsPerMonth' => '10',
                'kilometersPerTrip' => '100',
                'averageRatePerTrip' => '3000',
                'estimatedMonthlyIncome' => '30000',
                'fuelRatePerLitre' => '95',
                'costFuelPerTrip' => '800',
                'costFuelPerMonth' => '8000',
                'salaries' => '10000',
                'maintenance' => '3000',
                'tyreCost' => '2000',
                'motorTaxPermitCost' => '1000',
                'others' => '500',
                'totalExpenses' => '24500',
                'grossSurplus' => '5500',
                'instalment' => '5000',
                'netSurplus' => '500'
            }
        );
        Map<String, Object> missingRecordSave = (Map<String, Object>) controller().call(
            'saveViabilityCheckData',
            new Map<String, Object>{ 'assetId' => asset.Id }
        );
        Test.stopTest();

        System.assertEquals(asset.Id, callableLoad.get('assetId'));
    }

    @IsTest
    static void testValidationAndUnknownCallableAction() {
        Application__c app = applicationRecord();
        Boolean unknownActionThrown = false;

        Test.startTest();
        Map<String, Object> missingAssetSave = (Map<String, Object>) controller().call(
            'saveViabilityCheckData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'params' => new Map<String, Object>{ 'distance' => '10' }
            }
        );
        try {
            controller().call('unsupportedAction', new Map<String, Object>());
        } catch (CalloutException ex) {
            unknownActionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, unknownActionThrown);
    }
}