@IsTest
private class TATEventRecorderTest {

    private static Application__c makeApplication() {
        Application__c a = new Application__c();
        insert a;
        return a;
    }

    private static TATEventRecorder.Input baseInput(Id appId) {
        TATEventRecorder.Input inp = new TATEventRecorder.Input();
        inp.applicationId = appId;
        inp.stage         = 'QDE';
        return inp;
    }

    @IsTest
    static void newValueOnlyInsertsRow() {
        Application__c app = makeApplication();
        TATEventRecorder.Input inp = baseInput(app.Id);
        inp.newValue = 'In Progress';

        Test.startTest();
        TATEventRecorder.Result r = TATEventRecorder.record(inp);
        Test.stopTest();

        System.assertNotEquals(null, r.opened, 'A new row should have been inserted.');
        System.assertEquals(null, r.closed, 'Nothing should have been closed.');
        TAT_Event__c persisted = [
            SELECT Application__c, Stage__c, Old_Value__c, New_Value__c,
                   Start_Time__c, End_Time__c, User__c, TAT_Summary__c
            FROM TAT_Event__c WHERE Id = :r.opened.Id
        ];
        System.assertEquals(app.Id, persisted.Application__c);
        System.assertEquals('QDE', persisted.Stage__c);
        System.assertEquals(null, persisted.Old_Value__c);
        System.assertEquals('In Progress', persisted.New_Value__c);
        System.assertNotEquals(null, persisted.Start_Time__c);
        System.assertEquals(null, persisted.End_Time__c);
        System.assertEquals(UserInfo.getUserId(), persisted.User__c);
        System.assertNotEquals(null, persisted.TAT_Summary__c,
            'Recorder must auto-create + link the parent TAT_Summary__c.');

        TAT_Summary__c summary = [
            SELECT Id, Application__c FROM TAT_Summary__c WHERE Id = :persisted.TAT_Summary__c
        ];
        System.assertEquals(app.Id, summary.Application__c,
            'Linked summary must belong to this application.');
    }

    @IsTest
    static void multipleEventsForSameAppShareOneSummary() {
        Application__c app = makeApplication();

        TATEventRecorder.Input first = baseInput(app.Id);
        first.newValue = 'A';
        TATEventRecorder.Result r1 = TATEventRecorder.record(first);

        TATEventRecorder.Input second = baseInput(app.Id);
        second.newValue = 'B';
        TATEventRecorder.Result r2 = TATEventRecorder.record(second);

        TAT_Event__c e1 = [SELECT TAT_Summary__c FROM TAT_Event__c WHERE Id = :r1.opened.Id];
        TAT_Event__c e2 = [SELECT TAT_Summary__c FROM TAT_Event__c WHERE Id = :r2.opened.Id];
        System.assertEquals(e1.TAT_Summary__c, e2.TAT_Summary__c,
            'Both events on the same Application must point to the same Summary.');

        Integer summaryCount = [
            SELECT COUNT() FROM TAT_Summary__c WHERE Application__c = :app.Id
        ];
        System.assertEquals(1, summaryCount, 'Exactly one Summary per Application.');
    }

    @IsTest
    static void oldValueOnlyClosesOpenRow() {
        Application__c app = makeApplication();

        TATEventRecorder.Input open = baseInput(app.Id);
        open.newValue  = 'In Progress';
        open.eventTime = Datetime.newInstance(2026, 1, 1, 9, 0, 0);
        TATEventRecorder.Result openedR = TATEventRecorder.record(open);

        TATEventRecorder.Input close = baseInput(app.Id);
        close.oldValue  = 'In Progress';
        close.eventTime = Datetime.newInstance(2026, 1, 1, 10, 30, 0);

        Test.startTest();
        TATEventRecorder.Result r = TATEventRecorder.record(close);
        Test.stopTest();

        System.assertEquals(null, r.opened, 'Close-only call must not insert anything.');
        System.assertNotEquals(null, r.closed, 'Close-only call must update the open row.');
        System.assertEquals(openedR.opened.Id, r.closed.Id, 'The same row must be updated.');

        TAT_Event__c persisted = [
            SELECT End_Time__c, TAT_Minutes__c
            FROM TAT_Event__c WHERE Id = :r.closed.Id
        ];
        System.assertEquals(close.eventTime, persisted.End_Time__c);
        System.assertEquals(90, persisted.TAT_Minutes__c, '90 minutes elapsed.');
    }

    @IsTest
    static void transitionClosesOldAndInsertsNew() {
        Application__c app = makeApplication();

        TATEventRecorder.Input start = baseInput(app.Id);
        start.newValue  = 'QDE-In Progress';
        start.eventTime = Datetime.newInstance(2026, 1, 1, 9, 0, 0);
        TATEventRecorder.Result startR = TATEventRecorder.record(start);

        TATEventRecorder.Input transition = baseInput(app.Id);
        transition.oldValue  = 'QDE-In Progress';
        transition.newValue  = 'DDE-In Progress';
        transition.eventTime = Datetime.newInstance(2026, 1, 1, 11, 0, 0);

        Test.startTest();
        TATEventRecorder.Result r = TATEventRecorder.record(transition);
        Test.stopTest();

        System.assertNotEquals(null, r.closed, 'Transition must close the previous row.');
        System.assertNotEquals(null, r.opened, 'Transition must insert a new row.');
        System.assertEquals(startR.opened.Id, r.closed.Id);

        TAT_Event__c closed = [
            SELECT End_Time__c, New_Value__c, TAT_Minutes__c
            FROM TAT_Event__c WHERE Id = :r.closed.Id
        ];
        System.assertEquals(transition.eventTime, closed.End_Time__c);
        System.assertEquals('QDE-In Progress', closed.New_Value__c, 'Closed row keeps its original New_Value.');
        System.assertEquals(120, closed.TAT_Minutes__c);

        TAT_Event__c opened = [
            SELECT Application__c, Old_Value__c, New_Value__c, Start_Time__c, End_Time__c
            FROM TAT_Event__c WHERE Id = :r.opened.Id
        ];
        System.assertEquals(app.Id, opened.Application__c);
        System.assertEquals('QDE-In Progress', opened.Old_Value__c);
        System.assertEquals('DDE-In Progress', opened.New_Value__c);
        System.assertEquals(transition.eventTime, opened.Start_Time__c);
        System.assertEquals(null, opened.End_Time__c);
    }

    @IsTest
    static void lookupDistinguishesParallelOpenRows() {
        // Same Application, two parallel verifications. Closing one must not
        // close the other.
        Application__c app = makeApplication();
        Verification__c vA = new Verification__c();
        Verification__c vB = new Verification__c();
        insert new List<Verification__c>{ vA, vB };

        TATEventRecorder.Input openA = baseInput(app.Id);
        openA.verificationId = vA.Id;
        openA.newValue       = 'Started';
        openA.eventTime      = Datetime.newInstance(2026, 1, 1, 9, 0, 0);

        TATEventRecorder.Input openB = baseInput(app.Id);
        openB.verificationId = vB.Id;
        openB.newValue       = 'Started';
        openB.eventTime      = Datetime.newInstance(2026, 1, 1, 9, 5, 0);

        TATEventRecorder.record(new List<TATEventRecorder.Input>{ openA, openB });

        TATEventRecorder.Input closeA = baseInput(app.Id);
        closeA.verificationId = vA.Id;
        closeA.oldValue       = 'Started';
        closeA.eventTime      = Datetime.newInstance(2026, 1, 1, 10, 0, 0);

        Test.startTest();
        TATEventRecorder.Result r = TATEventRecorder.record(closeA);
        Test.stopTest();

        TAT_Event__c closedRow = [
            SELECT Verification__c, End_Time__c
            FROM TAT_Event__c WHERE Id = :r.closed.Id
        ];
        System.assertEquals(vA.Id, closedRow.Verification__c, 'Closed row must be on Verification A, not B.');

        Integer stillOpenForB = [
            SELECT COUNT()
            FROM TAT_Event__c
            WHERE Application__c = :app.Id
              AND Verification__c = :vB.Id
              AND End_Time__c = null
        ];
        System.assertEquals(1, stillOpenForB, 'Verification B row must remain open.');
    }

    @IsTest
    static void closeWithoutOpenRowThrows() {
        Application__c app = makeApplication();
        TATEventRecorder.Input bad = baseInput(app.Id);
        bad.oldValue = 'Never-Existed';

        Boolean threw = false;
        try {
            Test.startTest();
            TATEventRecorder.record(bad);
            Test.stopTest();
        } catch (TATEventRecorder.TATEventException ex) {
            threw = true;
            System.assert(
                ex.getMessage().contains('No open TAT_Event__c found'),
                'Expected explanatory error, got: ' + ex.getMessage()
            );
        }
        System.assert(threw, 'Close-only call with no open row must throw.');
    }

    @IsTest
    static void validateRejectsBadInputs() {
        Application__c app = makeApplication();

        assertThrows(null);
        assertThrows(new List<TATEventRecorder.Input>());
        assertThrows(new List<TATEventRecorder.Input>{ null });

        TATEventRecorder.Input noApp = new TATEventRecorder.Input();
        noApp.newValue = 'X';
        assertThrows(new List<TATEventRecorder.Input>{ noApp });

        TATEventRecorder.Input noValue = baseInput(app.Id);
        assertThrows(new List<TATEventRecorder.Input>{ noValue });
    }

    private static void assertThrows(List<TATEventRecorder.Input> inputs) {
        Boolean threw = false;
        try {
            TATEventRecorder.record(inputs);
        } catch (TATEventRecorder.TATEventException ex) {
            threw = true;
        }
        System.assert(threw, 'Expected TATEventException for input batch: ' + inputs);
    }
}