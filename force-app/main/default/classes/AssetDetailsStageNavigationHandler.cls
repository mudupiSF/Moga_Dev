/**
 * @description Vehicle-type stage routing and menu visibility for Dynamic_Stage_Gate__mdt.Override_Apex__c.
 *
 * Configure Override_Apex__c = AssetDetailsStageNavigationHandler on:
 *   • Asset Details       (Wheels_Asset_Details)
 *   • Valuation           (Wheels_Valuation_UR)
 *   • Invoice             (Wheels_Invoice_PSS, Wheels_Invoice_OPS)
 *   • Vehicle Inspection  (Wheels_Vehicle_Inspection_PSS, Wheels_Vehicle_Inspection_OPS)
 *
 * Routing (from Asset__c.Vehicle_type__c):
 *   Asset Details → Next:
 *     • Used / Refinance → Valuation
 *     • New or blank     → Loan Terms (Valuation hidden in menu)
 *   Valuation → Next:
 *     • Loan Terms (Used / Refinance path only; Valuation not shown for New)
 *   Additional Documents → Next (via advanceApplicationStep hook):
 *     • New or blank     → Invoice
 *     • Used / Refinance → Vehicle Inspection
 *   Invoice → Next:
 *     • IHM (skips Vehicle Inspection; Invoice hidden for Used / Refinance)
 *   Vehicle Inspection → Next:
 *     • IHM (Vehicle Inspection hidden for New)
 */
public with sharing class AssetDetailsStageNavigationHandler implements dynamicStageNavigatorController.IStageOverride {

    private static final String STEP_ASSET_DETAILS = 'Asset Details';
    private static final String STEP_VALUATION = 'Valuation';
    private static final String STEP_LOAN_TERMS = 'Loan Terms';
    private static final String STEP_INVOICE = 'Invoice';
    private static final String STEP_VEHICLE_INSPECTION = 'Vehicle Inspection';
    private static final String STEP_IHM = 'IHM';

    private static final String VEHICLE_TYPE_NEW = 'New';
    private static final String VEHICLE_TYPE_USED = 'Used';
    private static final String VEHICLE_TYPE_REFINANCE = 'Refinance';

    public dynamicStageNavigatorController.StageNavigationResult execute(
        Id applicationId,
        String currentStagePhrase,
        String currentLoanStageName,
        Application__c app,
        Dynamic_Stage_Gate__mdt currentRec,
        String effectivePortfolio
    ) {
        dynamicStageNavigatorController.StageNavigationResult result =
            new dynamicStageNavigatorController.StageNavigationResult();

        if (currentRec == null) {
            result.isSuccess = false;
            result.message = 'AssetDetailsStageNavigationHandler: stage metadata record is missing.';
            return result;
        }

        String stepName = currentRec.Steps_Sub_Menu_Name__c;
        String targetMainStage = String.isNotBlank(currentRec.Forward_Main_Stage_Name__c)
            ? currentRec.Forward_Main_Stage_Name__c
            : currentRec.Main_Stage_Name__c;

        if (STEP_ASSET_DETAILS.equalsIgnoreCase(stepName)) {
            String vehicleType = resolveVehicleTypeFromAsset(applicationId);
            String targetStep = resolveTargetStepAfterAssetDetails(vehicleType);

            result.newStep = targetStep;
            result.newMainStage = targetMainStage;
            result.isSuccess = true;
            result.message = 'Routing to ' + targetStep + ' based on vehicle type: '
                + (String.isNotBlank(vehicleType) ? vehicleType : '(blank, treated as New)');
            return result;
        }

        if (STEP_VALUATION.equalsIgnoreCase(stepName)) {
            String vehicleType = resolveVehicleTypeFromAsset(applicationId);
            if (!isUsedOrRefinance(vehicleType)) {
                result.isSuccess = false;
                result.message = 'Valuation is not applicable when vehicle type is '
                    + (String.isNotBlank(vehicleType) ? vehicleType : 'New') + '.';
                return result;
            }

            result.newStep = String.isNotBlank(currentRec.Forward_Steps_Name__c)
                ? currentRec.Forward_Steps_Name__c
                : STEP_LOAN_TERMS;
            result.newMainStage = targetMainStage;
            result.isSuccess = true;
            result.message = 'Routing to ' + result.newStep + ' after Valuation.';
            return result;
        }

        if (STEP_INVOICE.equalsIgnoreCase(stepName)) {
            String vehicleType = resolveVehicleTypeFromAsset(applicationId);
            if (!isNew(vehicleType)) {
                result.isSuccess = false;
                result.message = 'Invoice is not applicable when vehicle type is '
                    + (String.isNotBlank(vehicleType) ? vehicleType : 'New') + '.';
                return result;
            }

            result.newStep = STEP_IHM;
            result.newMainStage = String.isNotBlank(currentRec.Main_Stage_Name__c)
                ? currentRec.Main_Stage_Name__c
                : targetMainStage;
            result.isSuccess = true;
            result.message = 'Routing to ' + STEP_IHM + ' after Invoice (skipping Vehicle Inspection).';
            return result;
        }

        if (STEP_VEHICLE_INSPECTION.equalsIgnoreCase(stepName)) {
            String vehicleType = resolveVehicleTypeFromAsset(applicationId);
            if (!isUsedOrRefinance(vehicleType)) {
                result.isSuccess = false;
                result.message = 'Vehicle Inspection is not applicable when vehicle type is '
                    + (String.isNotBlank(vehicleType) ? vehicleType : 'New') + '.';
                return result;
            }

            result.newStep = String.isNotBlank(currentRec.Forward_Steps_Name__c)
                ? currentRec.Forward_Steps_Name__c
                : STEP_IHM;
            result.newMainStage = targetMainStage;
            result.isSuccess = true;
            result.message = 'Routing to ' + result.newStep + ' after Vehicle Inspection.';
            return result;
        }

        result.isSuccess = false;
        result.message =
            'AssetDetailsStageNavigationHandler: unsupported stage "'
            + stepName + '".';
        return result;
    }

    /**
     * Hides Valuation, Invoice, or Vehicle Inspection in the left menu based on vehicle type.
     * Requires Override_Apex__c on the corresponding CMT rows (same pattern as Valuation).
     */
    public Boolean isVisible(
        Application__c app,
        Dynamic_Stage_Gate__mdt currentRec,
        String effectivePortfolio
    ) {
        if (currentRec == null || app == null) {
            return true;
        }

        String stepName = currentRec.Steps_Sub_Menu_Name__c;
        String vehicleType = resolveVehicleTypeFromAsset(app.Id);

        if (STEP_VALUATION.equalsIgnoreCase(stepName)) {
            return isUsedOrRefinance(vehicleType);
        }
        if (STEP_INVOICE.equalsIgnoreCase(stepName)) {
            return isNew(vehicleType);
        }
        if (STEP_VEHICLE_INSPECTION.equalsIgnoreCase(stepName)) {
            return isUsedOrRefinance(vehicleType);
        }

        return true;
    }

    /**
     * Called by dynamicStageNavigatorController.advanceApplicationStep when leaving
     * Additional Documents (applicant-based; cannot use Override_Apex__c on that step).
     */
    public static String resolveTargetStepAfterAdditionalDocuments(Id applicationId) {
        return resolveTargetStepAfterAdditionalDocuments(resolveVehicleTypeFromAsset(applicationId));
    }

    private static String resolveTargetStepAfterAdditionalDocuments(String vehicleType) {
        if (isUsedOrRefinance(vehicleType)) {
            return STEP_VEHICLE_INSPECTION;
        }
        return STEP_INVOICE;
    }

    private static String resolveTargetStepAfterAssetDetails(String vehicleType) {
        if (isUsedOrRefinance(vehicleType)) {
            return STEP_VALUATION;
        }
        return STEP_LOAN_TERMS;
    }

    private static Boolean isNew(String vehicleType) {
        if (String.isBlank(vehicleType)) {
            return true;
        }
        return VEHICLE_TYPE_NEW.equalsIgnoreCase(vehicleType.trim());
    }

    private static Boolean isUsedOrRefinance(String vehicleType) {
        if (String.isBlank(vehicleType)) {
            return false;
        }
        String normalized = vehicleType.trim();
        return VEHICLE_TYPE_USED.equalsIgnoreCase(normalized)
            || VEHICLE_TYPE_REFINANCE.equalsIgnoreCase(normalized);
    }

    private static String resolveVehicleTypeFromAsset(Id applicationId) {
        if (applicationId == null) {
            return null;
        }

        List<Asset__c> assets = [
            SELECT Vehicle_type__c, Applicant__r.Application__c
            FROM Asset__c
            WHERE Applicant__r.Application__c = :applicationId
               OR Application_Line_Items__r.Application__c = :applicationId
            ORDER BY CreatedDate DESC
        ];
        for (Asset__c asset : assets) {
            if (
                asset.Applicant__r.Application__c == applicationId
                && String.isNotBlank(asset.Vehicle_type__c)
            ) {
                return asset.Vehicle_type__c.trim();
            }
        }
        for (Asset__c asset : assets) {
            if (String.isNotBlank(asset.Vehicle_type__c)) {
                return asset.Vehicle_type__c.trim();
            }
        }
        return null;
    }
}