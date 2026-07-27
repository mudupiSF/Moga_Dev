@IsTest
private class TATSummaryServiceTest {

    private static Application__c makeApp() {
        Application__c a = new Application__c();
        insert a;
        return a;
    }

    @IsTest
    static void ensureSummaries_createsOneWhenMissing() {
        Application__c app = makeApp();

        Test.startTest();
        Map<Id, Id> result = TATSummaryService.ensureSummariesExist(new Set<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertNotEquals(null, result.get(app.Id));

        Integer cnt = [SELECT COUNT() FROM TAT_Summary__c WHERE Application__c = :app.Id];
        System.assertEquals(1, cnt);
    }

    @IsTest
    static void ensureSummaries_reusesWhenPresent() {
        Application__c app = makeApp();
        TAT_Summary__c preExisting = new TAT_Summary__c(Application__c = app.Id);
        insert preExisting;

        Test.startTest();
        Map<Id, Id> result = TATSummaryService.ensureSummariesExist(new Set<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(preExisting.Id, result.get(app.Id));
        Integer cnt = [SELECT COUNT() FROM TAT_Summary__c WHERE Application__c = :app.Id];
        System.assertEquals(1, cnt, 'Must not create duplicates.');
    }

    @IsTest
    static void updateSummaries_sumsMinutesByStage() {
        Application__c app = makeApp();
        Id appId = app.Id;

        // Three QDE events, one Legal Verification event — direct insert so the
        // test isolates updateSummaries() and doesn't rely on the recorder.
        TAT_Summary__c summary = new TAT_Summary__c(Application__c = appId);
        insert summary;

        insert new List<TAT_Event__c>{
            qdeEvent(appId, summary.Id, 30, 20),
            qdeEvent(appId, summary.Id, 45, 30),
            qdeEvent(appId, summary.Id, 15, 10),
            legalEvent(appId, summary.Id, 120, 90)
        };

        Test.startTest();
        TATSummaryService.updateSummaries(appId);
        Test.stopTest();

        TAT_Summary__c reloaded = [
            SELECT QDE_TAT_Mins__c, QDE_BH_Mins__c,
                   Legal_Verification_TAT_Mins__c, Legal_Verification_BH_Mins__c,
                   Total_TAT_Mins__c, Total_BH_Mins__c
            FROM TAT_Summary__c WHERE Id = :summary.Id
        ];
        System.assertEquals(90,  reloaded.QDE_TAT_Mins__c,  '30+45+15');
        System.assertEquals(60,  reloaded.QDE_BH_Mins__c,   '20+30+10');
        System.assertEquals(120, reloaded.Legal_Verification_TAT_Mins__c);
        System.assertEquals(90,  reloaded.Legal_Verification_BH_Mins__c);
        System.assertEquals(210, reloaded.Total_TAT_Mins__c, '30+45+15+120');
        System.assertEquals(150, reloaded.Total_BH_Mins__c,  '20+30+10+90');
    }

    @IsTest
    static void updateSummaries_resetsStaleNumbersBeforeRecomputing() {
        Application__c app = makeApp();
        TAT_Summary__c summary = new TAT_Summary__c(
            Application__c = app.Id,
            QDE_TAT_Mins__c   = 999,   // stale value
            QDE_BH_Mins__c    = 999,
            Total_TAT_Mins__c = 999,
            Total_BH_Mins__c  = 999
        );
        insert summary;

        // No events on this Application — recompute should zero the stale numbers.

        Test.startTest();
        TATSummaryService.updateSummaries(app.Id);
        Test.stopTest();

        TAT_Summary__c reloaded = [
            SELECT QDE_TAT_Mins__c, QDE_BH_Mins__c,
                   Total_TAT_Mins__c, Total_BH_Mins__c
            FROM TAT_Summary__c WHERE Id = :summary.Id
        ];
        System.assertEquals(0, reloaded.QDE_TAT_Mins__c,   'Stale QDE TAT must reset.');
        System.assertEquals(0, reloaded.QDE_BH_Mins__c,    'Stale QDE BH must reset.');
        System.assertEquals(0, reloaded.Total_TAT_Mins__c, 'Stale grand total must reset.');
        System.assertEquals(0, reloaded.Total_BH_Mins__c,  'Stale grand total BH must reset.');
    }

    @IsTest
    static void updateSummaries_bulkCoversMultipleApplications() {
        Application__c a1 = makeApp();
        Application__c a2 = makeApp();

        TAT_Summary__c s1 = new TAT_Summary__c(Application__c = a1.Id);
        TAT_Summary__c s2 = new TAT_Summary__c(Application__c = a2.Id);
        insert new List<TAT_Summary__c>{ s1, s2 };

        insert new List<TAT_Event__c>{
            qdeEvent(a1.Id, s1.Id, 40, 30),
            qdeEvent(a2.Id, s2.Id, 70, 50)
        };

        Test.startTest();
        TATSummaryService.updateSummaries(new Set<Id>{ a1.Id, a2.Id });
        Test.stopTest();

        Map<Id, TAT_Summary__c> byId = new Map<Id, TAT_Summary__c>([
            SELECT Id, QDE_TAT_Mins__c, QDE_BH_Mins__c,
                   Total_TAT_Mins__c, Total_BH_Mins__c
            FROM TAT_Summary__c WHERE Id IN :new Set<Id>{ s1.Id, s2.Id }
        ]);
        System.assertEquals(40, byId.get(s1.Id).QDE_TAT_Mins__c);
        System.assertEquals(30, byId.get(s1.Id).QDE_BH_Mins__c);
        System.assertEquals(70, byId.get(s2.Id).QDE_TAT_Mins__c);
        System.assertEquals(50, byId.get(s2.Id).QDE_BH_Mins__c);
        System.assertEquals(40, byId.get(s1.Id).Total_TAT_Mins__c);
        System.assertEquals(30, byId.get(s1.Id).Total_BH_Mins__c);
        System.assertEquals(70, byId.get(s2.Id).Total_TAT_Mins__c);
        System.assertEquals(50, byId.get(s2.Id).Total_BH_Mins__c);
    }

    @IsTest
    static void updateSummaries_unknownStageIsSilentlySkipped() {
        Application__c app = makeApp();
        TAT_Summary__c summary = new TAT_Summary__c(Application__c = app.Id);
        insert summary;

        // Stage doesn't correspond to any *_TAT_Mins__c field on TAT_Summary__c.
        TAT_Event__c e = new TAT_Event__c();
        e.Application__c        = app.Id;
        e.TAT_Summary__c        = summary.Id;
        e.Stage__c              = 'No Such Stage';
        e.Start_Time__c         = Datetime.now().addMinutes(-30);
        e.End_Time__c           = Datetime.now();
        e.TAT_Minutes__c        = 30;
        e.TAT_Business_Minutes__c = 20;
        insert e;

        Test.startTest();
        TATSummaryService.updateSummaries(app.Id);   // must not throw
        Test.stopTest();

        Integer survivingCount = [SELECT COUNT() FROM TAT_Summary__c WHERE Id = :summary.Id];
        System.assertEquals(1, survivingCount);

        // Unknown stages have no per-stage fields, but they MUST still
        // contribute to the grand total — otherwise reporting under-counts.
        TAT_Summary__c reloaded = [
            SELECT Total_TAT_Mins__c, Total_BH_Mins__c
            FROM TAT_Summary__c WHERE Id = :summary.Id
        ];
        System.assertEquals(30, reloaded.Total_TAT_Mins__c, 'Unknown stage still rolls into Total TAT.');
        System.assertEquals(20, reloaded.Total_BH_Mins__c,  'Unknown stage still rolls into Total BH.');
    }

    @IsTest
    static void emptyInputsAreNoOps() {
        Test.startTest();
        Map<Id, Id> r = TATSummaryService.ensureSummariesExist(null);
        System.assertEquals(0, r.size());
        r = TATSummaryService.ensureSummariesExist(new Set<Id>());
        System.assertEquals(0, r.size());

        TATSummaryService.updateSummaries((Set<Id>) null);
        TATSummaryService.updateSummaries(new Set<Id>());
        Test.stopTest();

        Integer summaryCount = [SELECT COUNT() FROM TAT_Summary__c];
        System.assertEquals(0, summaryCount, 'No summaries should be created from empty input.');
    }

    // ── helpers ────────────────────────────────────────────────────────────

    private static TAT_Event__c qdeEvent(Id appId, Id summaryId, Integer tatMins, Integer bhMins) {
        TAT_Event__c e = new TAT_Event__c();
        e.Application__c          = appId;
        e.TAT_Summary__c          = summaryId;
        e.Stage__c                = 'QDE';
        e.Start_Time__c           = Datetime.now().addMinutes(-tatMins);
        e.End_Time__c             = Datetime.now();
        e.TAT_Minutes__c          = tatMins;
        e.TAT_Business_Minutes__c = bhMins;
        return e;
    }

    private static TAT_Event__c legalEvent(Id appId, Id summaryId, Integer tatMins, Integer bhMins) {
        TAT_Event__c e = qdeEvent(appId, summaryId, tatMins, bhMins);
        e.Stage__c = 'Legal Verification';
        return e;
    }
}