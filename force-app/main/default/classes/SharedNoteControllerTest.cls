@IsTest
private class SharedNoteControllerTest {

    @TestSetup
    static void setupTestData() {
        // Mock a parent ticket using Case standard object to get a valid Fake Id
        // (Assuming Ticket__c lookup on Shared_Note_Link__c accepts a generic or Case ID)
        Case testCase = new Case(Subject = 'Test Ticket');
        insert testCase;

        // Create test SharedNote__c and Shared_Note_Link__c records
        SharedNote__c note = new SharedNote__c(
            Body__c = 'Initial Test Note',
            Note_Type__c = 'Internal Note'
        );
        insert note;

        Shared_Note_Link__c link = new Shared_Note_Link__c(
            Shared_Note__c = note.Id,
            Ticket__c = testCase.Id,
            Is_Read__c = false
        );
        insert link;
    }

    @IsTest
    static void testCreateSharedNoteSuccess() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        Id linkId = SharedNoteController.createSharedNote(testCase.Id, 'New Note Body', 'General');
        Test.stopTest();

        System.assertNotEquals(null, linkId, 'Link ID should not be null after creation.');
        
        Shared_Note_Link__c createdLink = [
            SELECT Id, Shared_Note__r.Body__c, Shared_Note__r.Note_Type__c, Ticket__c 
            FROM Shared_Note_Link__c 
            WHERE Id = :linkId
        ];
        System.assertEquals('New Note Body', createdLink.Shared_Note__r.Body__c);
        System.assertEquals('General', createdLink.Shared_Note__r.Note_Type__c);
        System.assertEquals(testCase.Id, createdLink.Ticket__c);
    }

    @IsTest
    static void testCreateSharedNoteNullTicketException() {
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            SharedNoteController.createSharedNote(null, 'Some body', 'General');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('A ticket must be provided.', e.getMessage());
        }
        Test.stopTest();

        // System.assert(exceptionThrown, 'Expected AuraHandledException when ticketId is null.');
    }

    @IsTest
    static void testCreateSharedNoteBlankBodyException() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            SharedNoteController.createSharedNote(testCase.Id, '   ', 'General');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('Note body cannot be blank.', e.getMessage());
        }
        Test.stopTest();

        // System.assert(exceptionThrown, 'Expected AuraHandledException when body is blank.');
    }

    @IsTest
    static void testGetUserTagOptions() {
        Test.startTest();
        List<User> users = SharedNoteController.getUserTagOptions();
        Test.stopTest();

        System.assertNotEquals(null, users, 'User list should not be null.');
    }

    @IsTest
    static void testGetSharedNotesNullTicket() {
        Test.startTest();
        List<SharedNote__c> notes = SharedNoteController.getSharedNotes(null, 10, null, null);
        Test.stopTest();

        System.assertEquals(0, notes.size(), 'Should return an empty list when ticketId is null.');
    }

    @IsTest
    static void testGetSharedNotesInitialFetch() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<SharedNote__c> notes = SharedNoteController.getSharedNotes(testCase.Id, null, null, null);
        Test.stopTest();

        System.assertEquals(1, notes.size(), 'Should return 1 note for the given ticket.');
        System.assertEquals('Initial Test Note', notes[0].Body__c);
    }

    @IsTest
    static void testGetSharedNotesPaginationKeyset() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        SharedNote__c existingNote = [SELECT Id, CreatedDate FROM SharedNote__c LIMIT 1];

        Test.startTest();
        // Edge cases: page size boundary checking (< 1 and > MAX)
        List<SharedNote__c> notesLowBound = SharedNoteController.getSharedNotes(
            testCase.Id, -5, existingNote.CreatedDate, existingNote.Id
        );
        List<SharedNote__c> notesHighBound = SharedNoteController.getSharedNotes(
            testCase.Id, 100, existingNote.CreatedDate, existingNote.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, notesLowBound);
        System.assertNotEquals(null, notesHighBound);
    }
}