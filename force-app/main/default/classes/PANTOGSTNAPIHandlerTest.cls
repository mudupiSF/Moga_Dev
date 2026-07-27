@IsTest
private class PANTOGSTNAPIHandlerTest {

    private static final String MOCK_RESPONSE =
        '{"result":{"gstinList":[{"gstin":"37AAACB4868Q1ZZ","status":"INACTIVE","state":"ANDHRA PRADESH (NEW)"},{"gstin":"29AAACB4868Q1ZW","status":"ACTIVE","state":"KARNATAKA"},{"gstin":"27AAACB4868Q1Z0","status":"ACTIVE","state":"MAHARASHTRA"}]}}';

    @IsTest
    static void parseGstDataFromResponse_returnsActiveGstinsOnly() {
        PANTOGSTNAPIHandler.GstExtractionParseResult parsed =
            PANTOGSTNAPIHandler.parseGstDataFromResponse(MOCK_RESPONSE);
        System.assertEquals(2, parsed.gstNumbers.size());
        System.assertEquals('29AAACB4868Q1ZW', parsed.gstNumbers[0]);
        System.assertEquals('27AAACB4868Q1Z0', parsed.gstNumbers[1]);
        System.assertEquals('Karnataka', parsed.defaultState);
        System.assertEquals('Karnataka', parsed.gstStateByNumber.get('29AAACB4868Q1ZW'));
        System.assertEquals('Maharashtra', parsed.gstStateByNumber.get('27AAACB4868Q1Z0'));
    }

    @IsTest
    static void parseGstDataFromResponse_allInactiveReturnsEmpty() {
        String allInactive =
            '{"result":{"gstinList":[{"gstin":"37AAACB4868Q1ZZ","status":"INACTIVE","state":"KARNATAKA"}]}}';
        PANTOGSTNAPIHandler.GstExtractionParseResult parsed =
            PANTOGSTNAPIHandler.parseGstDataFromResponse(allInactive);
        System.assertEquals(0, parsed.gstNumbers.size());
    }

    @IsTest
    static void normalizeStateName_titleCasesApiValue() {
        System.assertEquals('Maharashtra', PANTOGSTNAPIHandler.normalizeStateName('MAHARASHTRA'));
        System.assertEquals('Andhra Pradesh', PANTOGSTNAPIHandler.normalizeStateName('ANDHRA PRADESH (NEW)'));
    }

    @IsTest
    static void validateInputData_requiresPan() {
        PANTOGSTNAPIHandler handler = new PANTOGSTNAPIHandler();
        Applicant__c applicant = new Applicant__c(Id = getFakeApplicantId());
        List<ApplicationUtility.IntegrationResponseWrapper> results =
            handler.validateInputData(new List<Object>{ applicant });
        System.assertEquals(true, results[0].hasValidationError);
    }

    private static Id getFakeApplicantId() {
        String prefix = Schema.SObjectType.Applicant__c.getKeyPrefix();
        return (Id) (prefix + '000000000001');
    }
}