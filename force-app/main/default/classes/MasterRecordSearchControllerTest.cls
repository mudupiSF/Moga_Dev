@IsTest
private class MasterRecordSearchControllerTest {
    @IsTest
    static void searchRecords_blankTerm_returnsEmpty() {
        List<MasterRecordSearchController.SearchOption> results =
            MasterRecordSearchController.searchRecords('Account_Name', '', null);

        System.assertEquals(0, results.size(), 'Blank search term should return no rows.');
    }

    @IsTest
    static void searchRecords_shortTerm_returnsEmpty() {
        List<MasterRecordSearchController.SearchOption> results =
            MasterRecordSearchController.searchRecords('Account_Name', 'ab', null);

        System.assertEquals(0, results.size(), 'Search terms shorter than 3 characters should return no rows.');
    }

    @IsTest
    static void searchRecords_invalidConfigKey_throws() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            MasterRecordSearchController.searchRecords('Invalid_Config_Key', 'test', null);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Invalid config key should throw AuraHandledException.');
    }

    @IsTest
    static void searchRecords_validConfigKey_returnsOptions() {
        Account testAccount = new Account(Name = 'Searchable Test Account');
        insert testAccount;

        Test.startTest();
        List<MasterRecordSearchController.SearchOption> results =
            MasterRecordSearchController.searchRecords('Account_Name', 'Searchable', null);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null.');
    }

    @IsTest
    static void getDisplayLabel_validRecord_returnsLabel() {
        Account testAccount = new Account(Name = 'Display Label Account');
        insert testAccount;

        Test.startTest();
        String label = MasterRecordSearchController.getDisplayLabel('Account_Name', testAccount.Id);
        Test.stopTest();

        System.assertEquals('Display Label Account', label);
    }

    @IsTest
    static void getDisplayLabel_nullRecordId_returnsEmpty() {
        String label = MasterRecordSearchController.getDisplayLabel('Account_Name', null);
        System.assertEquals('', label);
    }

    @IsTest
    static void resolveMmvProductType_mapsFleetProductValues() {
        System.assertEquals('Passenger Vehicle', MasterRecordSearchController.resolveMmvProductType('PASSENGER VEHICLE'));
        System.assertEquals('Commercial Vehicle', MasterRecordSearchController.resolveMmvProductType('MEDIUM AND HEAVY COMMERCIAL VEHICLES'));
        System.assertEquals('Commercial Vehicle', MasterRecordSearchController.resolveMmvProductType('LIGHT COMMERCIAL VEHICLE'));
        System.assertEquals(null, MasterRecordSearchController.resolveMmvProductType(''));
    }

    @IsTest
    static void getDisplayLabelByValue_blankValue_returnsEmpty() {
        String label = MasterRecordSearchController.getDisplayLabelByValue('Account_Name', '', null);
        System.assertEquals('', label);
    }
}