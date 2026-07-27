@isTest
private class GenericUtilityTest {

    @testSetup
    static void setupPincodeMaster() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            Username          = 'gutility' + System.currentTimeMillis() + '@testorg.example.com',
            Email             = 'gutility@testorg.example.com',
            LastName          = 'GUTest',
            Alias             = 'gutst',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Enhanced_UI_Access' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        System.runAs(u) {
            insert new Pincode_Master__c(
                Pincode__c   = 110001,
                City__c      = 'New Delhi',
                State__c     = 'Delhi',
                Country__c   = 'India',
                Is_Active__c = true
            );
            insert new Pincode_Master__c(
                Pincode__c   = 999999,
                City__c      = 'Inactive City',
                Is_Active__c = false
            );
        }
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Alias = 'gutst' LIMIT 1];
    }

    @isTest
    static void getProductTypeShortForm_mapsKnownValuesAndHandlesBlank() {
        System.runAs(getTestUser()) {
            System.assertEquals('', GenericUtility.getProductTypeShortForm(null));
            System.assertEquals('', GenericUtility.getProductTypeShortForm('   '));
            System.assertEquals('PV', GenericUtility.getProductTypeShortForm('Passenger Vehicles'));
            System.assertEquals('PV', GenericUtility.getProductTypeShortForm('Passenger Vehicles (PV)'));
            System.assertEquals('TW', GenericUtility.getProductTypeShortForm('Two Wheeler'));
            System.assertEquals('SCV', GenericUtility.getProductTypeShortForm('Small Commercial Vehicle (SCV)'));
            System.assertEquals('LCV', GenericUtility.getProductTypeShortForm('Light Commercial Vehicle'));
            System.assertEquals('Custom Product', GenericUtility.getProductTypeShortForm('Custom Product'));
        }
    }

    @isTest
    static void isNonIndividualApplicationType_normalisesVariants() {
        System.runAs(getTestUser()) {
            System.assertEquals(false, GenericUtility.isNonIndividualApplicationType(null));
            System.assertEquals(false, GenericUtility.isNonIndividualApplicationType(''));
            System.assertEquals(false, GenericUtility.isNonIndividualApplicationType('Individual'));
            System.assertEquals(true, GenericUtility.isNonIndividualApplicationType('Non-Individual'));
            System.assertEquals(true, GenericUtility.isNonIndividualApplicationType('Non Individual'));
            System.assertEquals(true, GenericUtility.isNonIndividualApplicationType('NON_INDIVIDUAL'));
            System.assertEquals(true, GenericUtility.isNonIndividualApplicationType('nonindividual'));
        }
    }

    @isTest
    static void parseDateValue_parsesIsoAndUiFormats() {
        System.runAs(getTestUser()) {
            System.assertEquals(null, GenericUtility.parseDateValue(null));
            System.assertEquals(null, GenericUtility.parseDateValue(''));
            System.assertEquals(
                Date.newInstance(1990, 1, 15),
                GenericUtility.parseDateValue('1990-01-15')
            );
            System.assertEquals(
                Date.newInstance(1990, 1, 15),
                GenericUtility.parseDateValue('15/01/1990')
            );
            System.assertEquals(
                Date.newInstance(1990, 12, 5),
                GenericUtility.parseDateValue('05-12-1990')
            );
        }
    }

    @isTest
    static void parseDateValue_throwsForInvalidInput() {
        System.runAs(getTestUser()) {
            Boolean threw = false;
            try {
                GenericUtility.parseDateValue('not-a-date');
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assertEquals(true, threw, 'Invalid date should throw AuraHandledException');
        }
    }

    @isTest
    static void parseEinsteinDateOfBirth_handlesMultipleFormats() {
        System.runAs(getTestUser()) {
            System.assertEquals(null, GenericUtility.parseEinsteinDateOfBirth(null));
            System.assertEquals(null, GenericUtility.parseEinsteinDateOfBirth(''));
            System.assertEquals(null, GenericUtility.parseEinsteinDateOfBirth('unparseable text'));

            System.assertEquals(
                Date.newInstance(1990, 1, 15),
                GenericUtility.parseEinsteinDateOfBirth('1990-01-15')
            );
            System.assertEquals(
                Date.newInstance(1990, 1, 15),
                GenericUtility.parseEinsteinDateOfBirth('15/01/1990')
            );
            System.assertEquals(
                Date.newInstance(1990, 1, 15),
                GenericUtility.parseEinsteinDateOfBirth('15th January 1990')
            );
            System.assertEquals(
                Date.newInstance(1990, 1, 12),
                GenericUtility.parseEinsteinDateOfBirth('12-Jan-1990')
            );
        }
    }

    @isTest
    static void getActivePicklistOptions_returnsOptionsForValidPicklist() {
        System.runAs(getTestUser()) {
            Test.startTest();
            List<Map<String, String>> options = GenericUtility.getActivePicklistOptions(
                'Application__c',
                'Product__c'
            );
            Test.stopTest();

            System.assertNotEquals(null, options);
            System.assert(options.size() > 0, 'Product__c should expose active picklist values');
            System.assert(String.isNotBlank(options[0].get('label')));
            System.assert(String.isNotBlank(options[0].get('value')));
        }
    }

    @isTest
    static void getActivePicklistOptions_returnsEmptyForInvalidInputs() {
        System.runAs(getTestUser()) {
            System.assertEquals(0, GenericUtility.getActivePicklistOptions(null, 'Product__c').size());
            System.assertEquals(0, GenericUtility.getActivePicklistOptions('Application__c', null).size());
            System.assertEquals(
                0,
                GenericUtility.getActivePicklistOptions('NotARealObject__c', 'Product__c').size()
            );
            System.assertEquals(
                0,
                GenericUtility.getActivePicklistOptions('Application__c', 'NotARealField__c').size()
            );
            System.assertEquals(
                0,
                GenericUtility.getActivePicklistOptions('Application__c', 'Total_Loan_Amount__c').size()
            );
        }
    }

    @isTest
    static void fetchControlledByDependentToSchema_returnsDependencyMap() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Map<String, List<Map<String, String>>> dependencyMap =
                GenericUtility.fetchControlledByDependentToSchema(
                    'Application_Line_Item__c',
                    'Sub_Product__c'
                );
            Test.stopTest();

            System.assertNotEquals(null, dependencyMap);
            System.assert(dependencyMap.size() > 0, 'Sub_Product__c should be a dependent picklist in org metadata');
            for (String controllingValue : dependencyMap.keySet()) {
                List<Map<String, String>> opts = dependencyMap.get(controllingValue);
                System.assertNotEquals(null, opts);
            }
        }
    }

    @isTest
    static void fetchControlledByDependentToSchema_returnsEmptyForInvalidInputs() {
        System.runAs(getTestUser()) {
            System.assertEquals(
                0,
                GenericUtility.fetchControlledByDependentToSchema(null, 'Sub_Product__c').size()
            );
            System.assertEquals(
                0,
                GenericUtility.fetchControlledByDependentToSchema('Application_Line_Item__c', null).size()
            );
            System.assertEquals(
                0,
                GenericUtility.fetchControlledByDependentToSchema('NotARealObject__c', 'Sub_Product__c').size()
            );
            System.assertEquals(
                0,
                GenericUtility.fetchControlledByDependentToSchema('Application__c', 'NotARealField__c').size()
            );
            System.assertEquals(
                0,
                GenericUtility.fetchControlledByDependentToSchema('Application__c', 'Product__c').size()
            );
        }
    }

    @isTest
    static void getCityStateFromPinCode_returnsEmptyForBlankOrInvalidPin() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Map<String, String> blankResult = GenericUtility.getCityStateFromPinCode(null);
            Map<String, String> invalidResult = GenericUtility.getCityStateFromPinCode('abc');
            Test.stopTest();

            System.assertEquals('', blankResult.get('city'));
            System.assertEquals('', blankResult.get('state'));
            System.assertEquals('', invalidResult.get('city'));
        }
    }

    @isTest
    static void getCityStateFromPinCode_returnsMatchForActivePincode() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Map<String, String> result = GenericUtility.getCityStateFromPinCode('110001');
            Test.stopTest();

            System.assertEquals('New Delhi', result.get('city'));
            System.assertEquals('Delhi', result.get('state'));
            System.assertEquals('India', result.get('country'));
        }
    }

    @isTest
    static void getCityStateFromPinCode_ignoresInactivePincodeMaster() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Map<String, String> result = GenericUtility.getCityStateFromPinCode('999999');
            Test.stopTest();

            System.assertEquals('', result.get('city'));
            System.assertEquals('', result.get('state'));
        }
    }

    @isTest
    static void getCityStateFromPinCode_returnsEmptyWhenNoMasterRow() {
        System.runAs(getTestUser()) {
            Test.startTest();
            Map<String, String> result = GenericUtility.getCityStateFromPinCode('560001');
            Test.stopTest();

            System.assertEquals('', result.get('city'));
            System.assertEquals('', result.get('state'));
            System.assertEquals('', result.get('country'));
        }
    }
}