public with sharing class VehicleDetailsController implements Callable {

    private static final String ACTION_GET = 'getVehicleDetailsPageData';
    private static final String ACTION_SAVE = 'saveVehicleDetailsPageData';
    private static final String ACTION_GET_USED = 'getVehicleDetailsUsedPageData';
    private static final String ACTION_SAVE_USED = 'saveVehicleDetailsUsedPageData';
    private static final String ASSET_DETAILS_SUB_STAGE = 'Asset Details';

    private static final Map<String, String> ASSET_FIELD_MAP = new Map<String, String>{
        'make' => 'Make__c',
        'makeName' => 'Make_Name__c',
        'model' => 'Model__c',
        'modelName' => 'Model_Name__c',
        'variant' => 'Variant__c',
        'variantName' => 'Variant_Name__c',
        'firstYearInsurancePremium' => 'X1st_yr_Insurance_Premium__c',
        'motorInsurancePremium' => 'Motor_Insurance_Premium__c',
        'basicPrice' => 'Basic_Price__c',
        'discountOnBasicPrice' => 'Discount_on_Basic_Price__c',
        'gstAmount' => 'GST_Amount__c',
        'exShowroomPrice' => 'Ex_showroom_price__c',
        'onRoadPrice' => 'On_Road_price__c',
        'requiredLoanAmount' => 'Required_Total_Loan_Amount__c',
        'requiredIrr' => 'Required_CRM_IRR__c',
        'requiredTenure' => 'Required_Tenure__c',
        'fundingOnOrp' => 'Funding_on_ORP__c',
        'fundingOnExShowroom' => 'Funding_on_Ex_Showroom__c',
        'dealerSubDealerName' => 'Dealer_Sub_dealer_name__c',
        'rcLimitEnabledDealer' => 'RC_retention_applicable__c',
        'invoiceInNameOf' => 'Invoice_in_the_name_of__c',
        'vehicleRegisteredInNameOf' => 'Vehicle_registered_in_the_name_of__c',
        'stateOfUtilizationOfAsset' => 'State__c',
        'districtOfUtilizationOfAsset' => 'District__c'
    };

    private static final Map<String, String> PRODUCT_TYPE_FULL_FORM_MAP = new Map<String, String>{
        'CE' => 'CONSTRUCTION EQUIPMENT',
        'TW' => 'Two Wheeler',
        'SCV' => 'SMALL COMMERCIAL VEHICLE',
        'LCV' => 'LIGHT COMMERCIAL VEHICLE',
        'PV' => 'Passenger Vehicle',
        'MHCV' => 'MEDIUM AND HEAVY COMMERCIAL VEHICLES'
    };
    private static final Set<String> ASSET_DECIMAL_KEYS = new Set<String>{
        'firstYearInsurancePremium',
        'motorInsurancePremium',
        'basicPrice',
        'discountOnBasicPrice',
        'gstAmount',
        'exShowroomPrice',
        'onRoadPrice',
        'requiredLoanAmount',
        'requiredIrr',
        'requiredTenure'
    };

    private static final Set<String> ASSET_BOOLEAN_KEYS = new Set<String>{
        'fundingOnOrp',
        'fundingOnExShowroom'
    };
    
    private static final Set<String> ASSET_DATE_KEYS = new Set<String>{
        'insuranceExpiryDate'
    };

    private static final Set<String> ASSET_MMV_UI_KEYS = new Set<String>{
        'make',
        'makeName',
        'model',
        'modelName',
        'variant',
        'variantName'
    };

    private static final Map<String, String> ASSET_USED_FIELD_MAP = new Map<String, String>{
        'registrationFormat' => 'Registration_Number_Format__c',
        'vehicleSubCategory' => 'Vehicle_SubCategory__c',
        'registrationNumber' => 'Vehicle_Registration_number__c',
        'parentDealNumber' => 'Parent_Deal_Number__c',
        'insuranceExpiryDate' => 'Ins_Expiry_date__c',
        'make' => 'Make__c',
        'makeName' => 'Make_Name__c',
        'model' => 'Model__c',
        'modelName' => 'Model_Name__c',
        'variant' => 'Variant__c',
        'variantName' => 'Variant_Name__c',
        'invoiceInNameOf' => 'Invoice_in_the_name_of__c',
        'manufacturingYearMonth' => 'Manufacturer_Year_Month__c',
        'lastOwnerName' => 'Last_owner_name__c',
        'engineNumber' => 'Engine_number__c',
        'chassisNumber' => 'Chassis_number__c',
        'numberOfOwnerships' => 'Number_of_ownerships__c',
        'rcRetentionApplicable' => 'RC_retention_applicable__c',
        'dealerSubDealerName' => 'Dealer_Sub_dealer_name__c',
        'stateOfUtilizationOfAsset' => 'State__c',
        'districtOfUtilizationOfAsset' => 'District__c',
        'requiredLoanAmount' => 'Required_Total_Loan_Amount__c',
        'requiredIrr' => 'Required_CRM_IRR__c',
        'requiredTenure' => 'Required_Tenure__c',
        'fundingOnOrp' => 'Funding_on_ORP__c',
        'fundingOnExShowroom' => 'Funding_on_Ex_Showroom__c'
    };

    private static final Integer MAXIMUM_AVAILABLE_TENURE_MONTHS = 84;

    public Object call(String action, Map<String, Object> args) {
        if (ACTION_GET.equalsIgnoreCase(action)) {
            return getVehicleDetailsPageDataInternal(args);
        }
        if (ACTION_SAVE.equalsIgnoreCase(action)) {
            return saveVehicleDetailsPageDataInternal(args);
        }
        if (ACTION_GET_USED.equalsIgnoreCase(action)) {
            return getVehicleDetailsUsedPageDataInternal(args);
        }
        if (ACTION_SAVE_USED.equalsIgnoreCase(action)) {
            return saveVehicleDetailsUsedPageDataInternal(args);
        }
        throw new CalloutException('Unknown action: ' + action);
    }

    private Map<String, Object> getVehicleDetailsPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        Id applicationId = (Id) args.get('recordId');
        if (applicationId == null) {
            return result;
        }
        result.put('isReadOnly', !isAssetDetailsSubStage(applicationId));
        result.put('maximumAvailableTenure', MAXIMUM_AVAILABLE_TENURE_MONTHS);

        Asset__c asset = resolveAsset(applicationId, args);
        result.put('productType', resolveMmvProductTypeToken(applicationId));
        result.put('productTypeFullForm', PRODUCT_TYPE_FULL_FORM_MAP.get((String) result.get('productType')));
        if (asset != null) {
            putMmvFieldsFromAsset(result, asset);
            result.put('vehicleType', asset.Vehicle_Type__c);
            result.put('numberOfVehicles', getNumberOfVehiclesForDisplay(asset));
            result.put('assetId', asset.Id);
            putPricingFieldsFromAsset(result, asset);
            putLoanFieldsFromAsset(result, asset);
            putDealerFieldsFromAsset(result, asset);
            result.put('hasViabilityData', hasViabilityCheckForAsset(asset.Id));
            result.put('hasHireVsBuyData', HireVsBuyController.hasHireVsBuyForAsset(asset.Id));
        }
        return result;
    }

    private Map<String, Object> getVehicleDetailsUsedPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>();
        Id applicationId = resolveApplicationId((Id) args.get('recordId'), args);
        if (applicationId == null) {
            return result;
        }
        result.put('isReadOnly', !isAssetDetailsSubStage(applicationId));
        result.put('maximumAvailableTenure', MAXIMUM_AVAILABLE_TENURE_MONTHS);

        Asset__c asset = resolveAsset(applicationId, args);
        result.put('productType', resolveMmvProductTypeToken(applicationId));
        result.put('productTypeFullForm', PRODUCT_TYPE_FULL_FORM_MAP.get((String) result.get('productType')));

        if (asset != null) {
            result.put('assetId', asset.Id);
            putVehicleDedupeFieldsFromAsset(result, asset);
            putVehicleDetailsFieldsFromAsset(result, asset);
            putDealerFieldsFromAsset(result, asset);
            putLoanFieldsFromAsset(result, asset);
            result.put('hasVehicleDedupeData', String.isNotBlank(asset.Vehicle_Registration_number__c));
            result.put(
                'hasVehicleDetailsData',
                String.isNotBlank(asset.Make__c) && String.isNotBlank(asset.Model__c)
            );
            result.put('hasViabilityData', hasViabilityCheckForAsset(asset.Id));
            result.put('hasHireVsBuyData', HireVsBuyController.hasHireVsBuyForAsset(asset.Id));
            result.put('hasLoanData', asset.Required_Total_Loan_Amount__c != null);
        }
        return result;
    }

    private static void putVehicleDedupeFieldsFromAsset(Map<String, Object> result, Asset__c asset) {
        result.put('registrationFormat', asset.Registration_Number_Format__c);
        result.put('vehicleSubCategory', asset.Vehicle_SubCategory__c);
        result.put('registrationNumber', asset.Vehicle_Registration_number__c);
        result.put('parentDealNumber', asset.Parent_Deal_Number__c);
        result.put(
            'insuranceExpiryDate',
            asset.Ins_Expiry_date__c == null ? null : String.valueOf(asset.Ins_Expiry_date__c)
        );
    }

    private static void putVehicleDetailsFieldsFromAsset(Map<String, Object> result, Asset__c asset) {
        putMmvFieldsFromAsset(result, asset);
        result.put('vehicleType', asset.Vehicle_Type__c);
        result.put('invoiceInNameOf', asset.Invoice_in_the_name_of__c);
        result.put('manufacturingYearMonth', asset.Manufacturer_Year_Month__c);
        result.put('lastOwnerName', asset.Last_owner_name__c);
        result.put('engineNumber', asset.Engine_number__c);
        result.put('chassisNumber', asset.Chassis_number__c);
        result.put('numberOfOwnerships', asset.Number_of_ownerships__c);
        result.put('rcRetentionApplicable', asset.RC_retention_applicable__c);
    }

    private Map<String, Object> saveVehicleDetailsUsedPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unable to save used vehicle details'
        };
        Id applicationId = resolveApplicationId((Id) args.get('recordId'), args);
        if (applicationId == null) {
            result.put('message', 'Application record is required to save used vehicle details');
            return result;
        }
        if (!isAssetDetailsSubStage(applicationId)) {
            result.put('message', 'Vehicle details are read-only outside Asset Details sub-stage');
            return result;
        }
        Asset__c asset = resolveAsset(applicationId, args);
        if (asset == null) {
            result.put('message', 'Asset ID is required to save used vehicle details');
            return result;
        }
        applyFieldValues(asset, args, ASSET_USED_FIELD_MAP);
        applyUsedRcRetentionFromArgs(asset, args);
        try {
            upsert asset;
            result.put('isSuccess', true);
            result.put('message', 'Used vehicle details saved');
            result.put('assetId', asset.Id);
            result.put('hasVehicleDedupeData', String.isNotBlank(asset.Vehicle_Registration_number__c));
            result.put(
                'hasVehicleDetailsData',
                String.isNotBlank(asset.Make__c) && String.isNotBlank(asset.Model__c)
            );
            result.put('hasViabilityData', hasViabilityCheckForAsset(asset.Id));
            result.put('hasLoanData', asset.Required_Total_Loan_Amount__c != null);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        return result;
    }

    private static void applyUsedRcRetentionFromArgs(SObject record, Map<String, Object> args) {
        if (args == null) {
            return;
        }
        Object rcPicklist = args.get('rcRetentionApplicable');
        if (rcPicklist != null && String.isNotBlank(String.valueOf(rcPicklist))) {
            return;
        }
        if (!args.containsKey('rcLimitEnabledDealer')) {
            return;
        }
        Object raw = args.get('rcLimitEnabledDealer');
        String normalized = String.valueOf(raw).trim().toLowerCase();
        Boolean enabled = normalized == 'true' || normalized == '1' || normalized == 'yes';
        record.put('RC_retention_applicable__c', enabled ? 'Yes' : 'No');
    }

    private static Boolean hasViabilityCheckForAsset(Id assetId) {
        return ViabilityCheckController.hasCompleteViabilityForAsset(assetId);
    }

    private static void putMmvFieldsFromAsset(Map<String, Object> result, Asset__c asset) {
        if (result == null || asset == null) {
            return;
        }
        result.put('make', asset.Make__c);
        result.put('makeName', asset.Make_Name__c);
        result.put('model', asset.Model__c);
        result.put('modelName', asset.Model_Name__c);
        result.put('variant', asset.Variant__c);
        result.put('variantName', asset.Variant_Name__c);
    }

    private static void putPricingFieldsFromAsset(Map<String, Object> result, Asset__c asset) {
        result.put('firstYearInsurancePremium', asset.X1st_yr_Insurance_Premium__c);
        result.put('motorInsurancePremium', asset.Motor_Insurance_Premium__c);
        result.put('basicPrice', asset.Basic_Price__c);
        result.put('discountOnBasicPrice', asset.Discount_on_Basic_Price__c);
        result.put('gstAmount', asset.GST_Amount__c);
        result.put('exShowroomPrice', asset.Ex_showroom_price__c);
        result.put('onRoadPrice', asset.On_Road_price__c);
        result.put('hasPricingData', asset.Basic_Price__c != null);
    }

    private static void putLoanFieldsFromAsset(Map<String, Object> result, Asset__c asset) {
        result.put('requiredLoanAmount', asset.Required_Total_Loan_Amount__c);
        result.put('requiredIrr', asset.Required_CRM_IRR__c);
        result.put(
            'requiredTenure',
            asset.Required_Tenure__c != null ? String.valueOf(asset.Required_Tenure__c.intValue()) : null
        );
        result.put('fundingOnOrp', asset.Funding_on_ORP__c);
        result.put('fundingOnExShowroom', asset.Funding_on_Ex_Showroom__c);
        if (asset.Funding_on_ORP__c == true) {
            result.put('fundingBasedOn', 'On-road Price');
        } else if (asset.Funding_on_Ex_Showroom__c == true) {
            result.put('fundingBasedOn', 'Ex-showroom Price');
        } else {
            result.put('fundingBasedOn', null);
        }
        result.put('hasLoanData', asset.Required_Total_Loan_Amount__c != null);
    }

    private static void putDealerFieldsFromAsset(Map<String, Object> result, Asset__c asset) {
        result.put('dealerSubDealerName', asset.Dealer_Sub_dealer_name__c);
        result.put('invoiceInNameOf', asset.Invoice_in_the_name_of__c);
        result.put('vehicleRegisteredInNameOf', asset.Vehicle_registered_in_the_name_of__c);
        result.put('stateOfUtilizationOfAsset', asset.State__c);
        result.put('districtOfUtilizationOfAsset', asset.District__c);
        result.put('rcLimitEnabledDealer', asset.RC_retention_applicable__c == 'Yes');
    }

    private Map<String, Object> saveVehicleDetailsPageDataInternal(Map<String, Object> args) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unable to save vehicle details'
        };
        Id applicationId = (Id) args.get('recordId');
        if (applicationId == null) {
            return result;
        }
        if (!isAssetDetailsSubStage(applicationId)) {
            result.put('message', 'Vehicle details are read-only outside Asset Details sub-stage');
            return result;
        }
        Asset__c asset = resolveAsset(applicationId, args);
        if (asset == null) {
            result.put('message', 'Asset ID is required to save vehicle details');
            return result;
        }
        applyFieldValues(asset, args, ASSET_FIELD_MAP);
        if (args.containsKey('numberOfVehicles')) {
            asset.Number_of_Vehicles__c = String.valueOf(
                parseNumberOfVehiclesValue(args.get('numberOfVehicles'))
            );
        }
        try {
            upsert asset;
            Integer siblingsUpdated = syncSaveDataToSiblingAssets(asset, args);
            markLineItemStageComplete(asset.Application_Line_Items__c, ASSET_DETAILS_SUB_STAGE);
            result.put('isSuccess', true);
            result.put('message', 'Vehicle details saved');
            result.put('assetId', asset.Id);
            result.put('lineItemId', asset.Application_Line_Items__c);
            result.put('siblingsUpdated', siblingsUpdated);
            result.put('hasPricingData', asset.Basic_Price__c != null);
            result.put('hasLoanData', asset.Required_Total_Loan_Amount__c != null);
            result.put('hasDealerData', String.isNotBlank(asset.Dealer_Sub_dealer_name__c));
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }
        return result;
    }

    /**
     * Called on Fetch Price — persists MMV + vehicle count on the primary asset
     * and creates sibling assets on the same line item when count > 1.
     */
    @AuraEnabled
    public static Map<String, Object> createAdditionalAsset(
        Id recordId,
        Id assetId,
        String make,
        String makeName,
        String model,
        String modelName,
        String variant,
        String variantName,
        String numberOfVehicles
    ) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'message' => 'Unable to create additional assets'
        };

        if (recordId == null) {
            result.put('message', 'Application ID is required.');
            return result;
        }
        if (!isAssetDetailsSubStage(recordId)) {
            result.put('message', 'Vehicle details are read-only outside Asset Details sub-stage');
            return result;
        }

        Map<String, Object> resolveArgs = new Map<String, Object>{ 'assetId' => assetId };
        Asset__c asset = resolveAsset(recordId, resolveArgs);
        if (asset == null) {
            asset = new Asset__c();
        }

        applyFieldValues(asset, new Map<String, Object>{
            'make' => make,
            'makeName' => makeName,
            'model' => model,
            'modelName' => modelName,
            'variant' => variant,
            'variantName' => variantName
        }, ASSET_FIELD_MAP);

        Integer vehicleCount = parseNumberOfVehiclesValue(numberOfVehicles);
        asset.Number_of_Vehicles__c = String.valueOf(vehicleCount);

        try {
            Id lineItemId = ensureLineItemForAsset(asset, recordId);
            if (lineItemId != null) {
                asset.Application_Line_Items__c = lineItemId;
            }
            upsert asset;

            Integer additionalCreated = 0;
            if (vehicleCount > 1 && asset.Application_Line_Items__c != null) {
                additionalCreated = createAdditionalAssetsIfNeeded(asset, vehicleCount);
            }

            result.put('isSuccess', true);
            result.put('message', 'Additional assets created successfully');
            result.put('assetId', asset.Id);
            result.put('additionalAssetsCreated', additionalCreated);
        } catch (Exception e) {
            result.put('message', e.getMessage());
        }

        return result;
    }

    /**
     * Pricing API bridge invoked from clientLayerVehicleDetails.
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> fetchVehiclePrice(
        String recordId,
        String make,
        String model,
        String variant
    ) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required');
        }
        if (String.isBlank(make) || String.isBlank(model) || String.isBlank(variant)) {
            throw new AuraHandledException('Make, model and variant are required');
        }

        Map<String, Object> data = new Map<String, Object>{
            'vehicleMake' => make,
            'vehicleModel' => model,
            'variant' => variant,
            'yearOfManufacture' => 2024,
            'basicPrice' => 850000,
            'discountOnBasicPrice' => 0,
            'exShowroomPrice' => 850000,
            'rtoCharges' => 42000,
            'cess' => 12000,
            'insurance' => 18000,
            'hypCharges' => 3500,
            'fastag' => 500,
            'onRoadPrice' => 926000,
            'fetchedAt' => '2026-03-06T10:30:00Z',
            'recordId' => recordId
        };

        return new Map<String, Object>{
            'isSuccess' => true,
            'statusCode' => 200,
            'message' => 'Vehicle price fetched successfully',
            'data' => data,
            'timestamp' => '2026-03-06T10:30:00Z',
            'referenceId' => 'FETCH-PRICE-REF-123456'
        };
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> vehicleDedupe(
        String recordId,
        String registrationFormat,
        String vehicleSubCategory,
        String registrationNumber,
        String parentDealNumber,
        String insuranceExpiryDate
    ) {
        validateUsedVehicleDedupeInputs(
            recordId,
            registrationFormat,
            vehicleSubCategory,
            registrationNumber
        );

        Map<String, Object> contentItem = new Map<String, Object>{
            'Description' => '',
            'NOC_Number_as_per_DB' => '',
            'Proceed_Flag' => 'Y'
        };
        Map<String, Object> dedupeResponse = new Map<String, Object>{
            'status' => 'SUCCESS',
            'respDesc' => 'Fetched Vehicle Dedupe details.',
            'content' => new List<Object>{ contentItem }
        };

        Map<String, Object> data = new Map<String, Object>{
            'response' => dedupeResponse,
            'registrationFormat' => registrationFormat,
            'vehicleSubCategory' => vehicleSubCategory,
            'registrationNumber' => registrationNumber,
            'parentDealNumber' => parentDealNumber,
            'insuranceExpiryDate' => insuranceExpiryDate,
            'recordId' => recordId
        };

        return buildUsedVehicleApiResponse(
            true,
            200,
            'Fetched Vehicle Dedupe details.',
            data,
            'VEHICLE-DEDUPE-REF-123456'
        );
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getVehicleDetails(
        String recordId,
        String registrationFormat,
        String vehicleSubCategory,
        String registrationNumber,
        String parentDealNumber,
        String insuranceExpiryDate
    ) {
        validateUsedVehicleDedupeInputs(
            recordId,
            registrationFormat,
            vehicleSubCategory,
            registrationNumber
        );

        Map<String, Object> data = new Map<String, Object>{
            'status' => 'COMPLETE',
            'recordId' => recordId
        };

        return buildUsedVehicleApiResponse(
            true,
            200,
            'Vehicle details integration completed',
            data,
            'GET-VEHICLE-DETAILS-REF-123456'
        );
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> vahaanReportApi(
        String recordId,
        String registrationFormat,
        String vehicleSubCategory,
        String registrationNumber,
        String parentDealNumber,
        String insuranceExpiryDate
    ) {
        validateUsedVehicleDedupeInputs(
            recordId,
            registrationFormat,
            vehicleSubCategory,
            registrationNumber
        );

        Map<String, Object> data = new Map<String, Object>{
            'Owner_Name' => 'Anirudh Puri',
            'Chassis_No' => 'AUDICHASSIS2025123456789',
            'Engine_No' => 'AUDIENGINE2025123456789',
            'Ins_Expiry_Date' => '2027-03-31',
            'Ins_Issuance_Date' => '2026-03-01',
            'Insurance_Number' => 'INS-1234567890',
            'Insurer_Name' => 'Best Motor Insurance',
            'Number_of_Ownerships' => 1,
            'Manufacture_Year_Month' => '2025-03'
        };

        return buildUsedVehicleApiResponse(
            true,
            200,
            'Vahaan report fetched successfully',
            data,
            'VAHAAN-REF-123456'
        );
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> dealMasterApi(
        String recordId,
        String registrationFormat,
        String vehicleSubCategory,
        String registrationNumber,
        String parentDealNumber,
        String insuranceExpiryDate
    ) {
        validateUsedVehicleDedupeInputs(
            recordId,
            registrationFormat,
            vehicleSubCategory,
            registrationNumber
        );

        Map<String, Object> data = new Map<String, Object>{
            'Make_Code' => 'AUDIAG',
            'Model_Code' => 'AUDI3TDIQ',
            'Variant_Code' => 'AUDIQ3PPN'
        };

        return buildUsedVehicleApiResponse(
            true,
            200,
            'Deal master details fetched successfully',
            data,
            'DEAL-MASTER-REF-123456'
        );
    }

    private static Map<String, Object> buildUsedVehicleIntegrationData(
        String recordId,
        String registrationFormat,
        String vehicleSubCategory,
        String registrationNumber,
        String parentDealNumber,
        String insuranceExpiryDate
    ) {
        return new Map<String, Object>{
            'registrationFormat' => registrationFormat,
            'vehicleSubCategory' => vehicleSubCategory,
            'registrationNumber' => registrationNumber,
            'parentDealNumber' => parentDealNumber,
            'insuranceExpiryDate' => insuranceExpiryDate,
            'recordId' => recordId
        };
    }

    private static void validateUsedVehicleDedupeInputs(
        String recordId,
        String registrationFormat,
        String vehicleSubCategory,
        String registrationNumber
    ) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required');
        }
        if (String.isBlank(registrationFormat)) {
            throw new AuraHandledException('Vehicle registration format is required');
        }
        if (String.isBlank(vehicleSubCategory)) {
            throw new AuraHandledException('Vehicle sub-category is required');
        }
        if (String.isBlank(registrationNumber)) {
            throw new AuraHandledException('Vehicle registration number is required');
        }
    }

    private static Map<String, Object> buildUsedVehicleApiResponse(
        Boolean isSuccess,
        Integer statusCode,
        String message,
        Map<String, Object> data,
        String referenceId
    ) {
        return new Map<String, Object>{
            'isSuccess' => isSuccess,
            'status' => isSuccess ? 'SUCCESS' : 'FAILED',
            'statusCode' => statusCode,
            'message' => message,
            'data' => data,
            'timestamp' => '2026-05-28T10:30:00Z',
            'referenceId' => referenceId
        };
    }

    /**
     * Resolves the MMV product-type token (SCV/LCV/MHCV/CE/PV/TW) used to filter the
     * hardcoded Make/Model/Variant lists, from the application line item's Product/Sub Product.
     * Scans all line items so a product-less line item (e.g. created at Fetch Price) does
     * not hide the journey's original product/sub-product selection.
     */
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

    private static Id resolveApplicationId(Id recordId, Map<String, Object> args) {
        if (recordId == null) {
            return null;
        }
        Schema.SObjectType token = recordId.getSobjectType();
        if (token == Application__c.SObjectType) {
            return recordId;
        }
        if (token == Applicant__c.SObjectType) {
            List<Applicant__c> applicants = [
                SELECT Application__c
                FROM Applicant__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return applicants.isEmpty() ? null : applicants[0].Application__c;
        }
        return null;
    }

    private static Asset__c resolveAsset(Id applicationId, Map<String, Object> args) {
        Id assetId = parseAssetId(args);
        if (assetId == null || applicationId == null) {
            return null;
        }
        List<Asset__c> assetsById = [
            SELECT
                Id,
                Make__c,
                Make_Name__c,
                Model__c,
                Model_Name__c,
                Variant__c,
                Variant_Name__c,
                Basic_Price__c,
                Discount_on_Basic_Price__c,
                GST_Amount__c,
                Ex_showroom_price__c,
                On_Road_price__c,
                X1st_yr_Insurance_Premium__c,
                Motor_Insurance_Premium__c,
                Required_Total_Loan_Amount__c,
                Required_CRM_IRR__c,
                Required_Tenure__c,
                Funding_on_ORP__c,
                Funding_on_Ex_Showroom__c,
                Dealer_Sub_dealer_name__c,
                RC_retention_applicable__c,
                Invoice_in_the_name_of__c,
                Vehicle_registered_in_the_name_of__c,
                State__c,
                District__c,
                Registration_Number_Format__c,
                Vehicle_SubCategory__c,
                Vehicle_Registration_number__c,
                Parent_Deal_Number__c,
                Ins_Expiry_date__c,
                Manufacturer_Year_Month__c,
                Last_owner_name__c,
                Engine_number__c,
                Chassis_number__c,
                Number_of_ownerships__c,
                Number_of_Vehicles__c,
                Application_Line_Items__c,
                Vehicle_type__c
            FROM Asset__c
            WHERE Id = :assetId
              AND Application_Line_Items__r.Application__c = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return assetsById.isEmpty() ? null : assetsById[0];
    }

    private static Id parseAssetId(Map<String, Object> args) {
        if (args == null || !args.containsKey('assetId')) {
            return null;
        }
        Object raw = args.get('assetId');
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception ex) {
            return null;
        }
    }


    private static void markLineItemStageComplete(Id lineItemId, String stageName) {
        if (lineItemId == null || String.isBlank(stageName)) {
            return;
        }
        if (!Schema.sObjectType.Application_Line_Item__c.isUpdateable()
            || !Schema.sObjectType.Application_Line_Item__c.fields.Stage_Completed__c.isUpdateable()) {
            return;
        }

        List<Application_Line_Item__c> lineItems = [
            SELECT Id, Stage_Completed__c
            FROM Application_Line_Item__c
            WHERE Id = :lineItemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (lineItems.isEmpty()) {
            return;
        }

        Application_Line_Item__c lineItem = lineItems[0];
        if (hasStageCompleted(lineItem.Stage_Completed__c, stageName)) {
            return;
        }

        String stage = stageName.trim();
        String updatedStages = String.isBlank(lineItem.Stage_Completed__c)
            ? stage
            : lineItem.Stage_Completed__c + ';' + stage;

        update new Application_Line_Item__c(
            Id = lineItemId,
            Stage_Completed__c = updatedStages
        );
    }

    private static Boolean hasStageCompleted(String completedStages, String stageName) {
        if (String.isBlank(completedStages) || String.isBlank(stageName)) {
            return false;
        }
        for (String stage : completedStages.split(';')) {
            if (stageName.equalsIgnoreCase(stage.trim())) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isAssetDetailsSubStage(Id applicationId) {
        if (applicationId == null) {
            return false;
        }
        List<Application__c> applications = [
            SELECT Sub_Stage__c
            FROM Application__c
            WHERE Id = :applicationId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return false;
        }
        return String.valueOf(applications[0].Sub_Stage__c).trim().toLowerCase() ==
            ASSET_DETAILS_SUB_STAGE.toLowerCase();
    }

    private static void applyFieldValues(
        SObject record,
        Map<String, Object> args,
        Map<String, String> fieldMap
    ) {
        for (String uiKey : fieldMap.keySet()) {
            if (!args.containsKey(uiKey)) {
                continue;
            }
            Object raw = args.get(uiKey);
            String apiName = fieldMap.get(uiKey);
            if (uiKey == 'rcLimitEnabledDealer') {
                String normalized = String.valueOf(raw).trim().toLowerCase();
                record.put(apiName, (normalized == 'true' || normalized == '1' || normalized == 'yes') ? 'Yes' : 'No');
                continue;
            }
            if (ASSET_BOOLEAN_KEYS.contains(uiKey)) {
                record.put(apiName, parseBoolean(raw));
                continue;
            }
            if (ASSET_MMV_UI_KEYS.contains(uiKey) && (raw == null || String.isBlank(String.valueOf(raw)))) {
                continue;
            }
            if (raw == null || String.valueOf(raw).trim() == '') {
                record.put(apiName, null);
                continue;
            }
            if (ASSET_DECIMAL_KEYS.contains(uiKey)) {
                record.put(apiName, Decimal.valueOf(String.valueOf(raw)));
            } else if (ASSET_DATE_KEYS.contains(uiKey)) {
                record.put(apiName, parseDate(raw));
            } else {
                record.put(apiName, String.valueOf(raw));
            }
        }
    }

    private static Boolean parseBoolean(Object raw) {
        if (raw == null) {
            return false;
        }
        String normalized = String.valueOf(raw).trim().toLowerCase();
        return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    private static Date parseDate(Object raw) {
        if (raw == null) {
            return null;
        }
        String value = String.valueOf(raw).trim();
        if (value == '') {
            return null;
        }
        // Handle ISO datetime values like 2026-10-10T00:00:00.000Z
        Integer tIdx = value.indexOf('T');
        if (tIdx > 0) {
            value = value.substring(0, tIdx);
        }
        return Date.valueOf(value);
    }

    private static Integer parseNumberOfVehiclesValue(Object raw) {
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            return 1;
        }
        try {
            Integer count = Integer.valueOf(String.valueOf(raw).trim());
            return count < 1 ? 1 : count;
        } catch (Exception ex) {
            return 1;
        }
    }

    private static String getNumberOfVehiclesForDisplay(Asset__c asset) {
        if (asset == null) {
            return null;
        }
        if (String.isNotBlank(asset.Number_of_Vehicles__c)) {
            return asset.Number_of_Vehicles__c.trim();
        }
        if (asset.Application_Line_Items__c == null) {
            return null;
        }
        List<Asset__c> lineItemAssets = [
            SELECT Number_of_Vehicles__c
            FROM Asset__c
            WHERE Application_Line_Items__c = :asset.Application_Line_Items__c
              AND Number_of_Vehicles__c != NULL
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return lineItemAssets.isEmpty() ? null : lineItemAssets[0].Number_of_Vehicles__c;
    }

    private static Id ensureLineItemForAsset(Asset__c asset, Id applicationId) {
        if (asset == null || asset.Application_Line_Items__c != null) {
            return asset?.Application_Line_Items__c;
        }
        if (applicationId == null || !Schema.sObjectType.Application_Line_Item__c.isCreateable()) {
            return null;
        }
        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = applicationId
        );
        insert lineItem;
        return lineItem.Id;
    }

    private static Integer syncSaveDataToSiblingAssets(Asset__c primaryAsset, Map<String, Object> args) {
        if (
            primaryAsset == null
            || primaryAsset.Application_Line_Items__c == null
            || args == null
            || !Schema.sObjectType.Asset__c.isUpdateable()
        ) {
            return 0;
        }

        List<Asset__c> siblings = [
            SELECT Id
            FROM Asset__c
            WHERE Application_Line_Items__c = :primaryAsset.Application_Line_Items__c
              AND Id != :primaryAsset.Id
            WITH SECURITY_ENFORCED
        ];
        if (siblings.isEmpty()) {
            return 0;
        }

        for (Asset__c sibling : siblings) {
            applyFieldValues(sibling, args, ASSET_FIELD_MAP);
        }
        update siblings;
        return siblings.size();
    }

    private static Integer createAdditionalAssetsIfNeeded(Asset__c primaryAsset, Integer vehicleCount) {
        if (
            primaryAsset == null
            || primaryAsset.Application_Line_Items__c == null
            || vehicleCount == null
            || vehicleCount < 2
            || !Schema.sObjectType.Asset__c.isCreateable()
        ) {
            return 0;
        }

        Id lineItemId = primaryAsset.Application_Line_Items__c;
        Integer existingCount = [
            SELECT COUNT()
            FROM Asset__c
            WHERE Application_Line_Items__c = :lineItemId
            WITH SECURITY_ENFORCED
        ];

        Integer toCreate = vehicleCount - existingCount;
        if (toCreate < 1) {
            return 0;
        }

        List<Asset__c> newAssets = new List<Asset__c>();
        for (Integer i = 0; i < toCreate; i++) {
            newAssets.add(new Asset__c(
                Application_Line_Items__c = lineItemId,
                Make__c = primaryAsset.Make__c,
                Make_Name__c = primaryAsset.Make_Name__c,
                Model__c = primaryAsset.Model__c,
                Model_Name__c = primaryAsset.Model_Name__c,
                Variant__c = primaryAsset.Variant__c,
                Variant_Name__c = primaryAsset.Variant_Name__c,
                Vehicle_type__c = primaryAsset.Vehicle_type__c
            ));
        }
        insert newAssets;
        return toCreate;
    }
}