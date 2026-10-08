@IsTest
private class CaseTriggerHandlerTest {

    private static String getOpenStatus() {
        return [
            SELECT MasterLabel
            FROM CaseStatus
            WHERE IsClosed = false
            LIMIT 1
        ].MasterLabel;
    }

    private static String getClosedStatus() {
        return [
            SELECT MasterLabel
            FROM CaseStatus
            WHERE IsClosed = true
            LIMIT 1
        ].MasterLabel;
    }

    @IsTest
    static void testCaptureCaseClosure_OpenToClosed() {
        String openStatus = getOpenStatus();
        String closedStatus = getClosedStatus();

        Case newCase = new Case(
            Status = closedStatus
        );

        Test.startTest();

        Datetime beforeCall = System.now();

        CaseTriggerHandler.captureCaseClosure(
            new List<Case>{ newCase },
            null
        );

        Datetime afterCall = System.now();

        Test.stopTest();

        System.assertNotEquals(
            null,
            newCase.Closure_DateTime__c,
            'Closure_DateTime__c should be populated when the Case becomes closed.'
        );

        System.assert(
            newCase.Closure_DateTime__c >= beforeCall &&
            newCase.Closure_DateTime__c <= afterCall,
            'Closure_DateTime__c should be set to the current time.'
        );
    }

    @IsTest
    static void testCaptureCaseClosure_ClosedToOpen() {
        String openStatus = getOpenStatus();
        String closedStatus = getClosedStatus();

        Case oldCase = new Case(
            Id = '500000000000001',
            Status = closedStatus
        );

        Case newCase = new Case(
            Id = oldCase.Id,
            Status = openStatus,
            Closure_DateTime__c = System.now().addDays(-2)
        );

        Map<Id, Case> oldCasesMap = new Map<Id, Case>{
            oldCase.Id => oldCase
        };

        Test.startTest();

        CaseTriggerHandler.captureCaseClosure(
            new List<Case>{ newCase },
            oldCasesMap
        );

        Test.stopTest();

        System.assertEquals(
            null,
            newCase.Closure_DateTime__c,
            'Closure_DateTime__c should be cleared when a closed Case is reopened.'
        );
    }

    @IsTest
    static void testCaptureCaseClosure_NoStatusTransition() {
        String openStatus = getOpenStatus();
        String closedStatus = getClosedStatus();

        // Open -> Open
        Case oldOpenCase = new Case(
            Id = '500000000000002',
            Status = openStatus
        );

        Case newOpenCase = new Case(
            Id = oldOpenCase.Id,
            Status = openStatus,
            Closure_DateTime__c = null
        );

        // Closed -> Closed
        Datetime existingClosureDate = System.now().addDays(-1);

        Case oldClosedCase = new Case(
            Id = '500000000000003',
            Status = closedStatus
        );

        Case newClosedCase = new Case(
            Id = oldClosedCase.Id,
            Status = closedStatus,
            Closure_DateTime__c = existingClosureDate
        );

        Map<Id, Case> oldCasesMap = new Map<Id, Case>{
            oldOpenCase.Id => oldOpenCase,
            oldClosedCase.Id => oldClosedCase
        };

        Test.startTest();

        CaseTriggerHandler.captureCaseClosure(
            new List<Case>{
                newOpenCase,
                newClosedCase
            },
            oldCasesMap
        );

        Test.stopTest();

        System.assertEquals(
            null,
            newOpenCase.Closure_DateTime__c,
            'Open -> Open should not populate Closure_DateTime__c.'
        );

        System.assertEquals(
            existingClosureDate,
            newClosedCase.Closure_DateTime__c,
            'Closed -> Closed should not change the existing closure date.'
        );
    }
}