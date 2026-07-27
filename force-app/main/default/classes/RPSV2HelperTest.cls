@isTest
private class RPSV2HelperTest {
    
    @isTest
    static void testEquatedEMIWithoutMoratorium() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                1000000, '10.5', Date.today(), 240, 5, '1',
                Date.today().addDays(30), 'EQUATED_EMI', 0, 'CAPITALIZE', 0,
                'FLOATING', '365', 'ACTUAL', 'NONE', 0, null, null,
                'MONTHLY', false, false, false, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
        System.assertNotEquals(null, schedule[0].instalmentAmount, 'First installment amount should not be null');
    }
    
    @isTest
    static void testEquatedPrincipalWithoutMoratorium() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                1000000, '10.5', Date.today(), 240, 5, '1',
                Date.today().addDays(30), 'EQUATED_PRINCIPAL', 0, 'CAPITALIZE', 0,
                'FLOATING', '365', 'ACTUAL', 'NONE', 0, null, null,
                'MONTHLY', false, false, false, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
        
        if (schedule.size() > 2) {
            Integer firstPrincipal = schedule[0].principalComp;
            Integer secondPrincipal = schedule[1].principalComp;
            System.assertEquals(firstPrincipal, secondPrincipal, 'Principal should be equal in equated principal method');
        }
    }
    
    @isTest
    static void testEquatedInterestWithoutMoratorium() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                1000000, '10.5', Date.today(), 240, 5, '1',
                Date.today().addDays(30), 'EQUATED_INTEREST', 0, 'CAPITALIZE', 0,
                'FLOATING', '365', 'ACTUAL', 'NONE', 0, null, null,
                'MONTHLY', false, false, false, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
    }
    
    @isTest
    static void testEquatedEMIWithMoratoriumCapitalize() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                1000000, '10.5', Date.today(), 240, 5, '1',
                Date.today().addDays(30), 'EQUATED_EMI', 12, 'NO_PAYMENT', 0,
                'FLOATING', '365', 'ACTUAL', 'NONE', 0, null, null,
                'MONTHLY', false, false, false, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
    }
    
    @isTest
    static void testEquatedEMIWithMoratoriumInterestOnly() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                1000000, '10.5', Date.today(), 240, 5, '1',
                Date.today().addDays(30), 'EQUATED_EMI', 12, 'INTEREST_ONLY', 0,
                'FLOATING', '365', 'ACTUAL', 'NONE', 0, null, null,
                'MONTHLY', false, false, false, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
    }
    
    @isTest
    static void testQuarterlyFrequency() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                1000000, '10.5', Date.today(), 240, 5, '3',
                Date.today().addDays(90), 'EQUATED_EMI', 0, 'CAPITALIZE', 0,
                'FLOATING', '365', 'ACTUAL', 'NONE', 0, null, null,
                'MONTHLY', false, false, false, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
    }
    
    @isTest
    static void testAccurateInterest() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                100000, '10', Date.today(), 12, 1, '1',
                Date.today().addDays(30), 'EQUATED_EMI', 0, 'NO_PAYMENT', 0,
                'FLOATING', '360', '30', 'NONE', 0, null, null,
                'MONTHLY', false, true, false, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
        System.assertNotEquals(null, schedule[0].interestRaw, 'interestRaw should be populated with accurateInterest');
        System.assertNotEquals(null, schedule[0].carryForward, 'carryForward should be populated with accurateInterest');
    }
    
    @isTest
    static void testFirstMonthPreEmi30days() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                1000000, '10.5', Date.today(), 36, 5, '1',
                Date.today().addDays(30), 'EQUATED_EMI', 0, 'NO_PAYMENT', 0,
                'FLOATING', '365', 'ACTUAL', 'SIMPLE', 3, null, null,
                'MONTHLY', false, false, true, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
    }
    
    @isTest
    static void testFixedCalculationMode() {
        Test.startTest();
        
        List<RPSV2Helper.RepaymentWrapper> schedule = 
            RPSV2Helper.emiRepaymentScheduleHlEnhanced(
                1000000, '10.5', Date.today(), 12, 5, '1',
                Date.today().addDays(30), 'EQUATED_EMI', 0, 'NO_PAYMENT', 0,
                'FIXED', '360', '30', 'NONE', 0, null, null,
                'MONTHLY', false, false, false, false
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should have installments');
    }
}