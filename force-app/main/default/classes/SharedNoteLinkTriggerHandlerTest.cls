@IsTest
private class SharedNoteLinkTriggerHandlerTest {

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

    private static Case makeCase(String status) {
        Case c = new Case(
            Status = status,
            Origin = 'Web',
            Subject = 'Test'
        );
        insert c;
        return c;
    }

    private static SharedNote__c makeNote(String type) {
        SharedNote__c note = new SharedNote__c(
            Note_Type__c = type
        );
        insert note;
        return note;
    }

    @IsTest
    static void testNullAndEmpty() {
        SharedNoteLinkTriggerHandler.handleAfterSave(null);
        SharedNoteLinkTriggerHandler.handleAfterSave(
            new List<Shared_Note_Link__c>()
        );
    }

    @IsTest
    static void testNoQualifyingLinks() {
        Case c = makeCase(getOpenStatus());
        SharedNote__c note = makeNote(
            SharedNoteConstants.NOTE_TYPE_EXTERNAL
        );

        Shared_Note_Link__c link = new Shared_Note_Link__c(
            Ticket__c = c.Id,
            Shared_Note__c = note.Id
        );
        insert link;

        Test.startTest();
        SharedNoteLinkTriggerHandler.handleAfterSave(
            new List<Shared_Note_Link__c>{ link }
        );
        Test.stopTest();

        Case result = [
            SELECT Status
            FROM Case
            WHERE Id = :c.Id
        ];

        System.assertEquals(
            getOpenStatus(),
            result.Status
        );
    }

    @IsTest
    static void testReopenTicket() {
        Case c = makeCase(getClosedStatus());
        SharedNote__c note = makeNote(
            SharedNoteConstants.NOTE_TYPE_EXTERNAL
        );

        Shared_Note_Link__c link = new Shared_Note_Link__c(
            Ticket__c = c.Id,
            Shared_Note__c = note.Id
        );
        insert link;

        Test.startTest();
        SharedNoteLinkTriggerHandler.handleAfterSave(
            new List<Shared_Note_Link__c>{ link }
        );
        Test.stopTest();

        Case result = [
            SELECT Status
            FROM Case
            WHERE Id = :c.Id
        ];

        System.assertEquals(
            SharedNoteConstants.CASE_STATUS_IN_PROGRESS,
            result.Status
        );
    }

    @IsTest
    static void testSuppressedTicket() {
        Case c = makeCase(getClosedStatus());
        SharedNote__c note = makeNote(
            SharedNoteConstants.NOTE_TYPE_EXTERNAL
        );

        Shared_Note_Link__c link = new Shared_Note_Link__c(
            Ticket__c = c.Id,
            Shared_Note__c = note.Id
        );
        insert link;

        SharedNoteLinkTriggerHandler.suppressAutoReopenTicketIds.add(c.Id);

        Test.startTest();
        SharedNoteLinkTriggerHandler.handleAfterSave(
            new List<Shared_Note_Link__c>{ link }
        );
        Test.stopTest();

        Case result = [
            SELECT Status
            FROM Case
            WHERE Id = :c.Id
        ];
    }

    @IsTest
    static void testSuppressionAllowsOtherTicket() {
        Case suppressedCase = makeCase(getClosedStatus());
        Case normalCase = makeCase(getClosedStatus());

        SharedNote__c note = makeNote(
            SharedNoteConstants.NOTE_TYPE_EXTERNAL
        );

        Shared_Note_Link__c suppressedLink = new Shared_Note_Link__c(
            Ticket__c = suppressedCase.Id,
            Shared_Note__c = note.Id
        );

        Shared_Note_Link__c normalLink = new Shared_Note_Link__c(
            Ticket__c = normalCase.Id,
            Shared_Note__c = note.Id
        );

        insert new List<Shared_Note_Link__c>{
            suppressedLink,
            normalLink
        };

        SharedNoteLinkTriggerHandler.suppressAutoReopenTicketIds.add(
            suppressedCase.Id
        );

        Test.startTest();
        SharedNoteLinkTriggerHandler.handleAfterSave(
            new List<Shared_Note_Link__c>{
                suppressedLink,
                normalLink
            }
        );
        Test.stopTest();

        Map<Id, Case> results = new Map<Id, Case>([
            SELECT Id, Status
            FROM Case
            WHERE Id IN :new List<Id>{
                suppressedCase.Id,
                normalCase.Id
            }
        ]);
    }
}