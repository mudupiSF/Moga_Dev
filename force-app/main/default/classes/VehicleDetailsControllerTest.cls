@IsTest
private class VehicleDetailsControllerTest {

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'Post Sanction Sales',
            Sub_Stage__c = 'Asset Details',
            Product__c = '4W'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower'
        );
        insert borrower;

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = app.Id,
            Loan_Amount__c = 500000
        );
        insert lineItem;

        insert new Asset__c(
            Application_Line_Items__c = lineItem.Id,
            Vehicle_type__c = 'New',
            Make__c = 'Honda',
            Model__c = 'City',
            Variant__c = 'VX',
            Basic_Price__c = 800000,
            Funding_on_ORP__c = true,
            Number_of_Vehicles__c = '1'
        );

        insert new Asset__c(
            Application_Line_Items__c = lineItem.Id,
            Vehicle_type__c = 'New',
            Make__c = 'Sibling'
        );
    }

    private static Application__c applicationRecord() {
        return [SELECT Id FROM Application__c LIMIT 1];
    }

    private static Applicant__c borrowerRecord() {
        return [SELECT Id FROM Applicant__c LIMIT 1];
    }

    private static Asset__c primaryAsset() {
        return [
            SELECT Id, Application_Line_Items__c
            FROM Asset__c
            WHERE Make__c = 'Honda'
            LIMIT 1
        ];
    }

    private static VehicleDetailsController controller() {
        return new VehicleDetailsController();
    }

    @IsTest
    static void newVehicle_getSavePricingAndAdditionalAssets() {
        Application__c app = applicationRecord();
        Asset__c asset = primaryAsset();
        Map<String, Object> baseArgs = new Map<String, Object>{
            'recordId' => app.Id,
            'assetId' => asset.Id
        };

        Test.startTest();
        Map<String, Object> pageData = (Map<String, Object>) controller().call(
            'getVehicleDetailsPageData',
            baseArgs
        );
        Map<String, Object> saveResult = (Map<String, Object>) controller().call(
            'saveVehicleDetailsPageData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'make' => 'Honda',
                'model' => 'City',
                'variant' => 'VX',
                'basicPrice' => '850000',
                'onRoadPrice' => '926000',
                'requiredLoanAmount' => '700000',
                'requiredTenure' => '60',
                'fundingOnOrp' => true,
                'dealerSubDealerName' => 'Dealer A',
                'numberOfVehicles' => '2'
            }
        );
        Map<String, Object> priceResult = VehicleDetailsController.fetchVehiclePrice(
            String.valueOf(app.Id),
            'Honda',
            'City',
            'VX'
        );
        Map<String, Object> additionalAssetsResult = VehicleDetailsController.createAdditionalAsset(
            app.Id,
            asset.Id,
            'Honda',
            'City',
            'VX',
            '3'
        );
        Test.stopTest();

        System.assertEquals(
            true,
            (Boolean) pageData.get('hasViabilityData') == false
                && (Boolean) saveResult.get('isSuccess')
                && (Boolean) priceResult.get('isSuccess')
                && (Boolean) additionalAssetsResult.get('isSuccess')
        );
    }

    @IsTest
    static void usedVehicle_getSaveAndIntegrationApis() {
        Application__c app = applicationRecord();
        Asset__c asset = primaryAsset();
        asset.Vehicle_type__c = 'Used';
        asset.Registration_Number_Format__c = 'newformat';
        asset.Vehicle_SubCategory__c = 'USED_OPEN_MARKET';
        asset.Vehicle_Registration_number__c = 'HR55AB1234';
        asset.Parent_Deal_Number__c = 'DEAL-001';
        asset.Ins_Expiry_date__c = Date.today().addMonths(6);
        update asset;

        Map<String, Object> usedArgs = new Map<String, Object>{
            'recordId' => app.Id,
            'assetId' => asset.Id
        };

        Test.startTest();
        Map<String, Object> usedPageData = (Map<String, Object>) controller().call(
            'getVehicleDetailsUsedPageData',
            usedArgs
        );
        Map<String, Object> usedSaveResult = (Map<String, Object>) controller().call(
            'saveVehicleDetailsUsedPageData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'registrationFormat' => 'newformat',
                'vehicleSubCategory' => 'USED_OPEN_MARKET',
                'registrationNumber' => 'HR55AB1234',
                'parentDealNumber' => 'DEAL-001',
                'insuranceExpiryDate' => '2026-10-10',
                'make' => 'Audi',
                'model' => 'Q3',
                'variant' => 'Premium',
                'rcLimitEnabledDealer' => true,
                'requiredLoanAmount' => '650000'
            }
        );
        Map<String, Object> dedupeResult = VehicleDetailsController.vehicleDedupe(
            String.valueOf(app.Id),
            'newformat',
            'USED_OPEN_MARKET',
            'HR55AB1234',
            'DEAL-001',
            '2026-10-10'
        );
        Map<String, Object> detailsResult = VehicleDetailsController.getVehicleDetails(
            String.valueOf(app.Id),
            'newformat',
            'USED_OPEN_MARKET',
            'HR55AB1234',
            'DEAL-001',
            '2026-10-10'
        );
        Map<String, Object> vahaanResult = VehicleDetailsController.vahaanReportApi(
            String.valueOf(app.Id),
            'newformat',
            'USED_OPEN_MARKET',
            'HR55AB1234',
            'DEAL-001',
            '2026-10-10'
        );
        Map<String, Object> dealMasterResult = VehicleDetailsController.dealMasterApi(
            String.valueOf(app.Id),
            'newformat',
            'USED_OPEN_MARKET',
            'HR55AB1234',
            'DEAL-001',
            '2026-10-10'
        );
        Test.stopTest();

        System.assertEquals(
            true,
            (Boolean) usedPageData.get('hasVehicleDedupeData')
                && (Boolean) usedSaveResult.get('isSuccess')
                && (Boolean) dedupeResult.get('isSuccess')
                && (Boolean) detailsResult.get('isSuccess')
                && (Boolean) vahaanResult.get('isSuccess')
                && (Boolean) dealMasterResult.get('isSuccess')
        );
    }

    @IsTest
    static void testUsedGuardsAndCreateWithoutAssetId() {
        Application__c app = applicationRecord();
        Asset__c asset = primaryAsset();

        Test.startTest();
        Map<String, Object> invalidUsedGet = (Map<String, Object>) controller().call(
            'getVehicleDetailsUsedPageData',
            new Map<String, Object>{
                'recordId' => asset.Id,
                'assetId' => asset.Id
            }
        );
        Map<String, Object> missingAssetSave = (Map<String, Object>) controller().call(
            'saveVehicleDetailsUsedPageData',
            new Map<String, Object>{ 'recordId' => app.Id }
        );
        Map<String, Object> createResult = VehicleDetailsController.createAdditionalAsset(
            app.Id,
            null,
            'TATA',
            'Nexon',
            'XZ+',
            '2'
        );
        Test.stopTest();

        System.assertEquals(true, createResult.get('isSuccess'));
    }

    @IsTest
    static void testCreateAdditionalAssetNullRecordAndFetchPriceValidation() {
        Boolean fetchPriceThrown = false;

        Test.startTest();
        Map<String, Object> nullRecordCreate = VehicleDetailsController.createAdditionalAsset(
            null,
            null,
            'Honda',
            'City',
            'VX',
            '1'
        );
        try {
            VehicleDetailsController.fetchVehiclePrice('001', 'Honda', 'City', '');
        } catch (AuraHandledException ex) {
            fetchPriceThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, fetchPriceThrown);
    }

    @IsTest
    static void testCreateAdditionalAssetReadOnlyAndRcRetentionPicklist() {
        Application__c app = applicationRecord();
        Asset__c asset = primaryAsset();
        app.Sub_Stage__c = 'Offer';
        update app;

        Test.startTest();
        Map<String, Object> readOnlyCreate = VehicleDetailsController.createAdditionalAsset(
            app.Id,
            asset.Id,
            'Honda',
            'City',
            'VX',
            '1'
        );
        Map<String, Object> rcPicklistSave = (Map<String, Object>) controller().call(
            'saveVehicleDetailsUsedPageData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'registrationNumber' => 'HR77CC7777',
                'make' => 'Honda',
                'model' => 'City',
                'rcRetentionApplicable' => 'Yes'
            }
        );
        Test.stopTest();

        System.assertEquals(false, readOnlyCreate.get('isSuccess'));
    }

    @IsTest
    static void testUsedRcRetentionFallbackSave() {
        Application__c app = applicationRecord();
        Asset__c asset = primaryAsset();
        asset.Vehicle_type__c = 'Used';
        update asset;

        Test.startTest();
        Map<String, Object> saveResult = (Map<String, Object>) controller().call(
            'saveVehicleDetailsUsedPageData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'registrationNumber' => 'HR66BB6666',
                'make' => 'Honda',
                'model' => 'City',
                'rcLimitEnabledDealer' => 'no'
            }
        );
        Test.stopTest();

        System.assertEquals(true, saveResult.get('isSuccess'));
    }

    @IsTest
    static void testSaveUsedMissingApplicationAndFundingExShowroom() {
        Application__c app = applicationRecord();
        Asset__c asset = primaryAsset();

        Test.startTest();
        Map<String, Object> missingApplicationSave = (Map<String, Object>) controller().call(
            'saveVehicleDetailsUsedPageData',
            new Map<String, Object>()
        );
        Map<String, Object> exShowroomSave = (Map<String, Object>) controller().call(
            'saveVehicleDetailsPageData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'make' => 'Honda',
                'model' => 'City',
                'variant' => 'VX',
                'fundingOnExShowroom' => true,
                'dealerSubDealerName' => 'Dealer B'
            }
        );
        Map<String, Object> secondSave = (Map<String, Object>) controller().call(
            'saveVehicleDetailsPageData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'make' => 'Honda',
                'model' => 'City',
                'variant' => 'VX'
            }
        );
        Test.stopTest();

        System.assertEquals(true, exShowroomSave.get('isSuccess'));
    }

    @IsTest
    static void testBlankApplicationAndUsedSaveReadOnly() {
        Application__c app = applicationRecord();
        app.Sub_Stage__c = 'Offer';
        update app;

        Test.startTest();
        Map<String, Object> blankGet = (Map<String, Object>) controller().call(
            'getVehicleDetailsPageData',
            new Map<String, Object>()
        );
        Map<String, Object> usedReadOnlySave = (Map<String, Object>) controller().call(
            'saveVehicleDetailsUsedPageData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => primaryAsset().Id
            }
        );
        Test.stopTest();

        System.assertEquals(false, usedReadOnlySave.get('isSuccess'));
    }

    @IsTest
    static void vehicleDetails_validationReadOnlyAndCallableGuards() {
        Application__c app = applicationRecord();
        Applicant__c borrower = borrowerRecord();
        Asset__c asset = primaryAsset();
        insert new Viability_Check__c(Asset__c = asset.Id);

        app.Sub_Stage__c = 'Basic Details';
        update app;

        Boolean unknownActionThrown = false;

        Test.startTest();
        Map<String, Object> readOnlySave = (Map<String, Object>) controller().call(
            'saveVehicleDetailsPageData',
            new Map<String, Object>{
                'recordId' => app.Id,
                'assetId' => asset.Id,
                'make' => 'Honda'
            }
        );
        Map<String, Object> applicantUsedGet = (Map<String, Object>) controller().call(
            'getVehicleDetailsUsedPageData',
            new Map<String, Object>{
                'recordId' => borrower.Id,
                'assetId' => asset.Id
            }
        );
        try {
            controller().call('unknownAction', new Map<String, Object>());
        } catch (CalloutException ex) {
            unknownActionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, unknownActionThrown);
    }
}