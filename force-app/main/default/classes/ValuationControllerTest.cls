@IsTest
private class ValuationControllerTest {

    private class TestContext {
        Application__c application;
        Applicant__c borrower;
        Application_Line_Item__c lineItem;
        Asset__c asset;
    }

    @TestSetup
    static void setupData() {
        Application__c app = new Application__c(
            Stage__c = 'Post Sanction Sales',
            Sub_Stage__c = 'Valuation',
            Product__c = '4W'
        );
        insert app;

        Applicant__c borrower = new Applicant__c(
            Application__c = app.Id,
            Applicant_Type__c = 'Borrower',
            Customer_First_Name__c = 'Owner',
            Contact_number__c = '9876543210'
        );
        insert borrower;

        Application_Line_Item__c lineItem = new Application_Line_Item__c(
            Application__c = app.Id,
            Loan_Amount__c = 500000
        );
        insert lineItem;

        insert new Asset__c(
            Applicant__c = borrower.Id,
            Application_Line_Items__c = lineItem.Id,
            Vehicle_type__c = 'Used',
            Product_Segment__c = 'Passenger Vehicles',
            Insurance_type__c = 'Comprehensive',
            Insurance_declared_value__c = 500000,
            Existing_Motor_Insurance_Premium__c = 12000,
            Ins_Expiry_date__c = Date.today().addMonths(6),
            Vehicle_Place_Of_Valuation__c = 'Mumbai',
            Valuer_category__c = 'Empanelled',
            Valuer__c = 'Valuer A',
            Valuer_code__c = 'A',
            Engine_number__c = 'ENG-VAL-1',
            Chassis_number__c = 'CHS-VAL-1',
            Vehicle_Registration_number__c = 'MH01AB1234'
        );
    }

    private static TestContext getContext() {
        TestContext ctx = new TestContext();
        ctx.application = [SELECT Id FROM Application__c ORDER BY CreatedDate DESC LIMIT 1];
        ctx.borrower = [
            SELECT Id
            FROM Applicant__c
            WHERE Application__c = :ctx.application.Id
            AND Applicant_Type__c = 'Borrower'
            LIMIT 1
        ];
        ctx.lineItem = [
            SELECT Id
            FROM Application_Line_Item__c
            WHERE Application__c = :ctx.application.Id
            LIMIT 1
        ];
        ctx.asset = [
            SELECT Id
            FROM Asset__c
            WHERE Applicant__c = :ctx.borrower.Id
            LIMIT 1
        ];
        return ctx;
    }

    @IsTest
    static void getValuationData_loadsAssetAndApplicantFields() {
        TestContext ctx = getContext();
        ValuationController.clearMfcSessionForTests();

        Test.startTest();
        Map<String, Object> result = ValuationController.getValuationData(
            ctx.application.Id,
            ctx.asset.Id,
            null,
            ctx.borrower.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
        System.assertEquals(String.valueOf(ctx.asset.Id), result.get('resolvedAssetId'));

        Map<String, Object> insurance = (Map<String, Object>) result.get('existingInsurance');
        System.assertEquals('Comprehensive', insurance.get('insuranceType'));
        System.assert(
            String.valueOf(insurance.get('insuranceDeclaredValue')).startsWith('500000'),
            String.valueOf(insurance.get('insuranceDeclaredValue'))
        );

        Map<String, Object> valuation = (Map<String, Object>) result.get('vehicleValuation');
        System.assertEquals('Owner', valuation.get('ownerName'));
        System.assertEquals('9876543210', valuation.get('ownerContactNumber'));
        System.assertEquals('Mumbai', valuation.get('vehiclePlaceOfValuation'));
        System.assertNotEquals(null, result.get('picklists'));
        System.assertNotEquals(null, result.get('valuerMasterOptions'));
    }

    @IsTest
    static void getValuationData_returnsDefaultsWhenAssetMissing() {
        ValuationController.clearMfcSessionForTests();

        Map<String, Object> result = ValuationController.getValuationData(
            '001000000000000AAA',
            null,
            null,
            null
        );

        System.assertEquals(true, result.get('isSuccess'));
        System.assertEquals(true, result.get('assetNotFound'));
        Map<String, Object> valuation = (Map<String, Object>) result.get('vehicleValuation');
        System.assertEquals('A', valuation.get('valuerCode'));
    }

    @IsTest
    static void saveValuationData_persistsAssetAndApplicant() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(
            new Map<String, Object>{
                'existingInsurance' => new Map<String, Object>{
                    'insuranceType' => 'Third Party',
                    'insuranceDeclaredValue' => '450000',
                    'existingMotorInsurancePremium' => '9000',
                    'insExpiryDate' => '2026-12-31'
                },
                'vehicleValuation' => new Map<String, Object>{
                    'ownerName' => 'Updated Owner',
                    'ownerContactNumber' => '9000000001',
                    'vehiclePlaceOfValuation' => 'Pune',
                    'valuerCategory' => 'MFC',
                    'valuer' => 'Valuer B',
                    'valuerCode' => 'B',
                    'slaNumber' => 'SLA-99',
                    'colorOfVehicle' => 'Red',
                    'kmsRun' => '15000'
                }
            }
        );

        Test.startTest();
        Map<String, Object> result = ValuationController.saveValuationData(
            ctx.application.Id,
            ctx.asset.Id,
            null,
            ctx.borrower.Id,
            payload
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), result.get('message'));

        Asset__c asset = [
            SELECT
                Insurance_type__c,
                Insurance_declared_value__c,
                Vehicle_Place_Of_Valuation__c,
                Valuer_category__c,
                Color_of_Vehicle__c,
                KMS_Run__c
            FROM Asset__c
            WHERE Id = :ctx.asset.Id
        ];
        System.assertEquals('Third Party', asset.Insurance_type__c);
        System.assertEquals(450000, asset.Insurance_declared_value__c);
        System.assertEquals('Pune', asset.Vehicle_Place_Of_Valuation__c);
        System.assertEquals('Red', asset.Color_of_Vehicle__c);

        Applicant__c borrower = [
            SELECT Customer_First_Name__c, Contact_number__c
            FROM Applicant__c
            WHERE Id = :ctx.borrower.Id
        ];
        System.assertEquals('Updated Owner', borrower.Customer_First_Name__c);
        System.assertEquals('9000000001', borrower.Contact_number__c);
    }

    @IsTest
    static void saveValuationData_requiresAsset() {
        Map<String, Object> result = ValuationController.saveValuationData(
            UserInfo.getUserId(),
            null,
            null,
            null,
            '{"existingInsurance":{},"vehicleValuation":{}}'
        );
        System.assertEquals(false, result.get('isSuccess'));
    }

    @IsTest
    static void mfcValuation_setsSessionAndReturnsSuccess() {
        TestContext ctx = getContext();
        ValuationController.clearMfcSessionForTests();
        ValuationController.getValuationData(ctx.application.Id, ctx.asset.Id, null, ctx.borrower.Id);

        Test.startTest();
        Map<String, Object> result = ValuationController.mfcValuation(ctx.application.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
        System.assertEquals(true, result.get('mfcGetValuationDone'));
        System.assertNotEquals(null, result.get('mfcRequestId'));

        Map<String, Object> reload = ValuationController.getValuationData(
            ctx.application.Id,
            ctx.asset.Id,
            null,
            ctx.borrower.Id
        );
        Map<String, Object> context = (Map<String, Object>) reload.get('valuationContext');
        System.assertNotEquals('', context.get('mfcRequestId'));
        System.assertEquals(false, context.get('oemDealer'));
    }

    @IsTest
    static void mfcFetchValuationReport_returnsSuccess() {
        Map<String, Object> result = ValuationController.mfcFetchValuationReport(UserInfo.getUserId());
        System.assertEquals(true, result.get('isSuccess'));
    }

    @IsTest
    static void getVehicleInspectionData_loadsInspectionFields() {
        TestContext ctx = getContext();

        Test.startTest();
        Map<String, Object> result = ValuationController.getVehicleInspectionData(
            ctx.application.Id,
            ctx.asset.Id,
            ctx.borrower.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'));
        Map<String, Object> inspection = (Map<String, Object>) result.get('vehicleInspection');
        System.assertEquals('ENG-VAL-1', inspection.get('engineNumber'));
        System.assertEquals('CHS-VAL-1', inspection.get('chassisNumber'));
        System.assertEquals('MH01AB1234', inspection.get('vehicleRegistrationNumber'));
        System.assertNotEquals(null, result.get('picklists'));
    }

    @IsTest
    static void saveVehicleInspectionData_persistsInspectionAndOperations() {
        TestContext ctx = getContext();
        String payload = JSON.serialize(
            new Map<String, Object>{
                'vehicleInspection' => new Map<String, Object>{
                    'engineNumber' => 'ENG-UPDATED',
                    'chassisNumber' => 'CHS-UPDATED',
                    'vehicleRegistrationNumber' => 'MH02CD5678',
                    'locationOfVehicleInspection' => 'Dealer Yard'
                },
                'operationsSection' => new Map<String, Object>{
                    'remarks' => 'Inspection complete',
                    'vehicleInspectionApprovedByCvo' => 'Yes',
                    'cvoRemarks' => 'Approved'
                }
            }
        );

        Test.startTest();
        Map<String, Object> result = ValuationController.saveVehicleInspectionData(
            ctx.application.Id,
            ctx.asset.Id,
            ctx.borrower.Id,
            payload
        );
        Test.stopTest();

        System.assertEquals(true, result.get('isSuccess'), result.get('message'));

        Asset__c asset = [
            SELECT
                Engine_number__c,
                Chassis_number__c,
                Vehicle_Registration_number__c,
                Remark__c,
                CVO_remarks__c
            FROM Asset__c
            WHERE Id = :ctx.asset.Id
        ];
        System.assertEquals('ENG-UPDATED', asset.Engine_number__c);
        System.assertEquals('CHS-UPDATED', asset.Chassis_number__c);
        System.assertEquals('MH02CD5678', asset.Vehicle_Registration_number__c);
        System.assertEquals('Inspection complete', asset.Remark__c);
        System.assertEquals('Approved', asset.CVO_remarks__c);
    }
}