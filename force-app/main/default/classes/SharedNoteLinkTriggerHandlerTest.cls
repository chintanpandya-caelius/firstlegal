@isTest
private class SharedNoteLinkTriggerHandlerTest {

    private static Case createCase(String status) {
        Case c = new Case(Status = status, Origin = 'Web', Subject = 'Test Case');
        insert c;
        return c;
    }

    private static SharedNote__c createNote(String noteType) {
        SharedNote__c note = new SharedNote__c(Note_Type__c = noteType);
        insert note;
        return note;
    }

    @isTest
    static void testNullAndEmptyListDoNothing() {
        Test.startTest();
        SharedNoteLinkTriggerHandler.handleAfterSave(null);
        SharedNoteLinkTriggerHandler.handleAfterSave(new List<Shared_Note_Link__c>());
        Test.stopTest();
        // No DML, no exception thrown -> early-return branches covered
    }

    @isTest
    static void testNoQualifyingLinksLeavesTicketUnchanged() {
        // Case is NOT Resolved, so it should never qualify
        Case c = createCase(SharedNoteConstants.CASE_STATUS_IN_PROGRESS);
        SharedNote__c note = createNote(SharedNoteConstants.NOTE_TYPE_EXTERNAL);
        Shared_Note_Link__c link = new Shared_Note_Link__c(
            Ticket__c = c.Id,
            Shared_Note__c = note.Id
        );
        insert link;

        Test.startTest();
        SharedNoteLinkTriggerHandler.handleAfterSave(new List<Shared_Note_Link__c>{ link });
        Test.stopTest();

        Case unchanged = [SELECT Status FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            SharedNoteConstants.CASE_STATUS_IN_PROGRESS,
            unchanged.Status,
            'Ticket status should be untouched since query qualifiers were not met'
        );
    }

    @isTest
    static void testQualifyingLinksReopenTicketsAndDedupeByTicket() {
        Case c1 = createCase(SharedNoteConstants.CASE_STATUS_RESOLVED);
        Case c2 = createCase(SharedNoteConstants.CASE_STATUS_RESOLVED);
        SharedNote__c externalNote = createNote(SharedNoteConstants.NOTE_TYPE_EXTERNAL);
        SharedNote__c internalNote = createNote('Internal Note'); // non-qualifying note type

        // Two links pointing at c1 (tests Map dedup), one qualifying link at c2,
        // and one link at c2 with a non-qualifying note type (tests filter).
        Shared_Note_Link__c link1 = new Shared_Note_Link__c(Ticket__c = c1.Id, Shared_Note__c = externalNote.Id);
        Shared_Note_Link__c link2 = new Shared_Note_Link__c(Ticket__c = c1.Id, Shared_Note__c = externalNote.Id);
        Shared_Note_Link__c link3 = new Shared_Note_Link__c(Ticket__c = c2.Id, Shared_Note__c = externalNote.Id);
        Shared_Note_Link__c link4 = new Shared_Note_Link__c(Ticket__c = c2.Id, Shared_Note__c = internalNote.Id);
        insert new List<Shared_Note_Link__c>{ link1, link2, link3, link4 };

        Test.startTest();
        SharedNoteLinkTriggerHandler.handleAfterSave(
            new List<Shared_Note_Link__c>{ link1, link2, link3, link4 }
        );
        Test.stopTest();

        Map<Id, Case> updatedCases = new Map<Id, Case>([
            SELECT Id, Status FROM Case WHERE Id IN :new List<Id>{ c1.Id, c2.Id }
        ]);
        System.assertEquals(
            SharedNoteConstants.CASE_STATUS_IN_PROGRESS,
            updatedCases.get(c1.Id).Status,
            'c1 should be reopened despite two links pointing at it'
        );
        System.assertEquals(
            SharedNoteConstants.CASE_STATUS_IN_PROGRESS,
            updatedCases.get(c2.Id).Status,
            'c2 should be reopened by its one qualifying link'
        );
    }
}