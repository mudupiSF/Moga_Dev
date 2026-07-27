@IsTest
private class CommonApplicationCreationControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // getFormOptions
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void getFormOptions_returnsProductOptionsKey() {
        Test.startTest();
        Map<String, Object> result = CommonApplicationCreationController.getFormOptions();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result map must not be null');
        System.assert(result.containsKey('productOptions'),
            'Result must contain productOptions key');

        List<Object> productOptions = (List<Object>) result.get('productOptions');
        System.assertNotEquals(null, productOptions,
            'productOptions must not be null');
    }

    @IsTest
    static void getFormOptions_returnsSubProductDependencyMapKey() {
        Test.startTest();
        Map<String, Object> result = CommonApplicationCreationController.getFormOptions();
        Test.stopTest();

        System.assert(result.containsKey('subProductDependencyMap'),
            'Result must contain subProductDependencyMap key');

        Map<String, Object> depMap = (Map<String, Object>) result.get('subProductDependencyMap');
        System.assertNotEquals(null, depMap,
            'subProductDependencyMap must not be null');
    }

    @IsTest
    static void getFormOptions_productOptionsContainLabelAndValue() {
        Map<String, Object> result = CommonApplicationCreationController.getFormOptions();
        List<Object> productOptions = (List<Object>) result.get('productOptions');

        if (!productOptions.isEmpty()) {
            Map<String, String> firstOpt = (Map<String, String>) productOptions[0];
            System.assert(firstOpt.containsKey('label'), 'Each option must have a label key');
            System.assert(firstOpt.containsKey('value'), 'Each option must have a value key');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createDirectLoanApplication – CV product (full payload)
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void createDirectLoanApplication_cv_returnsRecordId() {
        Test.startTest();
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'CV', 'LCV', '3', 'Truck', 'HCV'
            );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response must not be null');
        System.assertNotEquals(null, response.recordId,
            'recordId must be populated after successful creation');

        Application__c app = [
            SELECT Id, Stage__c, Sub_Stage__c, Product__c
            FROM Application__c
            WHERE Id = :response.recordId
        ];
        System.assertEquals('QDE',           app.Stage__c,     'Stage__c must be QDE');
        System.assertEquals('Basic Details', app.Sub_Stage__c, 'Sub_Stage__c must be Basic Details');
        System.assertEquals('CV',            app.Product__c,   'Product__c must be CV');
    }

    @IsTest
    static void createDirectLoanApplication_cv_createsBorrowerApplicant() {
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'CV', 'LCV', '2', 'Bus', 'MHCV'
            );

        List<Applicant__c> applicants = [
            SELECT Applicant_Type__c
            FROM Applicant__c
            WHERE Application__c = :response.recordId
        ];
        System.assertEquals(1, applicants.size(),
            'Exactly one Applicant__c (Borrower) must be created');
        System.assertEquals('Borrower', applicants[0].Applicant_Type__c,
            'Applicant_Type__c must be Borrower');
    }

    @IsTest
    static void createDirectLoanApplication_cv_createsAssetWithVehicleTypeAndPurpose() {
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'CV', 'SCV', '1', 'Truck', 'LCV'
            );

        Applicant__c borrower = [
            SELECT Id FROM Applicant__c WHERE Application__c = :response.recordId LIMIT 1
        ];
        List<Asset__c> assets = [
            SELECT Vehicle_type__c, Purpose_of_purchase__c
            FROM Asset__c
            WHERE Applicant__c = :borrower.Id
        ];
        System.assertEquals(1, assets.size(), 'Exactly one Asset__c must be created');
        System.assertEquals('Truck',      assets[0].Vehicle_type__c,
            'Vehicle_type__c must match the supplied vehicleType argument');
        System.assertEquals('Commercial', assets[0].Purpose_of_purchase__c,
            'Purpose_of_purchase__c must be Commercial for CV product');
    }

    @IsTest
    static void createDirectLoanApplication_cv_createsLineItemWithSubProductAndVehicleCount() {
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'CV', 'LCV', '5', 'Truck', 'HCV'
            );

        List<Application_Line_Item__c> lineItems = [
            SELECT Product__c, Sub_Product__c, Number_of_Vehicles__c
            FROM Application_Line_Item__c
            WHERE Application__c = :response.recordId
        ];
        System.assertEquals(1, lineItems.size(), 'Exactly one Application_Line_Item__c must be created');
        System.assertEquals('CV',  lineItems[0].Product__c,     'Product__c must mirror Application__c.Product__c');
        System.assertEquals('LCV', lineItems[0].Sub_Product__c, 'Sub_Product__c must match the supplied subProduct');
        System.assertEquals('5',   lineItems[0].Number_of_Vehicles__c,
            'Number_of_Vehicles__c must match the supplied numberOfVehicles');
    }

    @IsTest
    static void createDirectLoanApplication_cv_doesNotCreateDocumentChecklist() {
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'CV', 'LCV', '1', 'Truck', 'HCV'
            );

        List<Document_CheckList__c> docs = [
            SELECT Document_Type__c, Applicant__c
            FROM Document_CheckList__c
            WHERE Application__c = :response.recordId
        ];
        System.assertEquals(0, docs.size(),
            'No Document_CheckList__c should be created at application creation; ' +
            'checklists are created on demand when a document upload is started.');
    }

    @IsTest
    static void createDirectLoanApplication_cv_linksAssetToLineItem() {
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'CV', 'LCV', '2', 'Truck', 'LCV'
            );

        Applicant__c borrower = [
            SELECT Id FROM Applicant__c WHERE Application__c = :response.recordId LIMIT 1
        ];
        Asset__c asset = [
            SELECT Application_Line_Items__c
            FROM Asset__c
            WHERE Applicant__c = :borrower.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, asset.Application_Line_Items__c,
            'Asset__c.Application_Line_Items__c must be set after the line item is created');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createDirectLoanApplication – non-CV product (PL)
    // Purpose_of_purchase__c is NOT set; optional fields are blank
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void createDirectLoanApplication_pl_succeeds() {
        Test.startTest();
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'PL', null, null, null, null
            );
        Test.stopTest();

        System.assertNotEquals(null, response.recordId,
            'recordId must be set for PL product creation');

        Application__c app = [SELECT Product__c FROM Application__c WHERE Id = :response.recordId];
        System.assertEquals('PL', app.Product__c, 'Product__c must be PL');
    }

    @IsTest
    static void createDirectLoanApplication_pl_assetHasNoPurposeOfPurchase() {
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'PL', null, null, null, null
            );

        Applicant__c borrower = [
            SELECT Id FROM Applicant__c WHERE Application__c = :response.recordId LIMIT 1
        ];
        Asset__c asset = [
            SELECT Purpose_of_purchase__c
            FROM Asset__c
            WHERE Applicant__c = :borrower.Id
            LIMIT 1
        ];
        System.assertEquals(null, asset.Purpose_of_purchase__c,
            'Purpose_of_purchase__c must NOT be set for non-CV products');
    }

    @IsTest
    static void createDirectLoanApplication_blankOptionalFields_lineItemHasNoSubProduct() {
        CommonApplicationCreationController.DirectLoanCreationResponse response =
            CommonApplicationCreationController.createDirectLoanApplication(
                'CV', '', '', '', ''
            );

        Application_Line_Item__c lineItem = [
            SELECT Sub_Product__c, Number_of_Vehicles__c
            FROM Application_Line_Item__c
            WHERE Application__c = :response.recordId
            LIMIT 1
        ];
        System.assertEquals(null, lineItem.Sub_Product__c,
            'Sub_Product__c must remain null when blank subProduct is passed');
        System.assertEquals(null, lineItem.Number_of_Vehicles__c,
            'Number_of_Vehicles__c must remain null when blank numberOfVehicles is passed');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DirectLoanCreationResponse inner class
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void directLoanCreationResponse_defaultRecordIdIsNull() {
        CommonApplicationCreationController.DirectLoanCreationResponse resp =
            new CommonApplicationCreationController.DirectLoanCreationResponse();

        System.assertEquals(null, resp.recordId,
            'Default recordId must be null before assignment');
    }
}