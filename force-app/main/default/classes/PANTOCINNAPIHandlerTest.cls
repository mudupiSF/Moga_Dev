@IsTest
private class PANTOCINNAPIHandlerTest {

    private static final String MOCK_RESPONSE =
        '{"result":{"PanName":"BNP PARIBAS","company":[{"companyName":"Company A","companyID":"U72900TN2008PTC069413"},{"companyName":"Company B","companyID":"U74999MH2011FTC220472"}]}}';

    @IsTest
    static void parseCinNumbersFromResponse_returnsAllCompanyIds() {
        List<String> cinNumbers = PANTOCINNAPIHandler.parseCinNumbersFromResponse(MOCK_RESPONSE);
        System.assertEquals(2, cinNumbers.size());
        System.assertEquals('U72900TN2008PTC069413', cinNumbers[0]);
        System.assertEquals('U74999MH2011FTC220472', cinNumbers[1]);
    }

    @IsTest
    static void parseCinNumbersFromResponse_blankReturnsEmpty() {
        System.assertEquals(0, PANTOCINNAPIHandler.parseCinNumbersFromResponse(null).size());
        System.assertEquals(0, PANTOCINNAPIHandler.parseCinNumbersFromResponse('').size());
    }

    @IsTest
    static void validateInputData_requiresPan() {
        PANTOCINNAPIHandler handler = new PANTOCINNAPIHandler();
        Applicant__c applicant = new Applicant__c(Id = getFakeApplicantId());
        List<ApplicationUtility.IntegrationResponseWrapper> results =
            handler.validateInputData(new List<Object>{ applicant });
        System.assertEquals(true, results[0].hasValidationError);
    }

    @IsTest
    static void validateInputData_acceptsPan() {
        PANTOCINNAPIHandler handler = new PANTOCINNAPIHandler();
        Applicant__c applicant = new Applicant__c(
            Id = getFakeApplicantId(),
            PAN_Number__c = 'ABCDE1234F'
        );
        List<ApplicationUtility.IntegrationResponseWrapper> results =
            handler.validateInputData(new List<Object>{ applicant });
        System.assertEquals(false, results[0].hasValidationError);
    }

    @IsTest
    static void maskDocumentNumber_leavesLastFourVisible() {
        System.assertEquals(
            '**************9413',
            KYCAddressExtractionController.maskDocumentNumber('U72900TN2008PTC069413')
        );
    }

    private static Id getFakeApplicantId() {
        String prefix = Schema.SObjectType.Applicant__c.getKeyPrefix();
        return (Id) (prefix + '000000000001');
    }
}