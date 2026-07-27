/**
 * @description Factory class to create appropriate stage transition handlers
 * based on product type. Uses singleton pattern for efficiency.
 *
 * @author 
 * @date 2026
 */
public class StageTransitionFactory {

    // Product type constants
    public static final String PRODUCT_COMMERCIAL_VEHICLE = 'COMMERCIAL_VEHICLE';
    public static final String PRODUCT_PERSONAL_LOAN = 'PERSONAL_LOAN';
    

    // Cache for handler instances (singleton pattern)
    private static Map<String, StageTransitionHandler> handlerCache = new Map<String, StageTransitionHandler>();

    /**
     * @description Get the appropriate stage transition handler for a product type
     * Uses singleton pattern to reuse instances
     * @param productType Product type string
     * @return StageTransitionHandler implementation for the product
     * @throws IllegalArgumentException if product type is not supported
     */
    public static StageTransitionHandler getHandler(String productType) {
        String normalizedProductType = productType.toUpperCase();

        // Return cached handler if exists
        if (handlerCache.containsKey(normalizedProductType)) {
            return handlerCache.get(normalizedProductType);
        }

        // Create new handler based on product type
        StageTransitionHandler handler;

        if (normalizedProductType == PRODUCT_COMMERCIAL_VEHICLE) {
            handler = new CommercialVehicleStageHandler();
        }
        // Add more product types here as needed
        // else if (normalizedProductType == PRODUCT_PERSONAL_LOAN) {
        //     handler = new PersonalLoanStageHandler();
        // }
        else {
            throw new IllegalArgumentException(
                'Unsupported product type: ' + productType +
                '. Supported types: COMMERCIAL_VEHICLE'
            );
        }

        // Cache the handler
        handlerCache.put(normalizedProductType, handler);
        return handler;
    }

    /**
     * @description Clear handler cache (useful for testing or reloading)
     */
    @TestVisible
    private static void clearCache() {
        handlerCache.clear();
    }

    /**
     * @description Get all supported product types
     * @return List of supported product type strings
     */
    public static List<String> getSupportedProducts() {
        return new List<String>{
            PRODUCT_COMMERCIAL_VEHICLE
            // Add more as implemented
        };
    }
}