@IsTest
private class TicketReopenServiceTest {

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

    private static Case createTicket(
        String status,
        Datetime closureDateTime
    ) {
        Case ticket = new Case(
            Subject = 'Test Ticket',
            Description = 'Test Description',
            Status = status,
            Origin = 'Web',
            Priority = 'Medium',
            Closure_DateTime__c = closureDateTime
        );

        insert ticket;
        return ticket;
    }

    @IsTest
    static void testAssertCommentingBlocked() {
        // Null ticketId should simply return.
        Test.startTest();
        TicketReopenService.assertCommentingBlocked(null);
        Test.stopTest();

        // Open ticket should return without throwing.
        Case openTicket = createTicket(
            getOpenStatus(),
            null
        );

        TicketReopenService.assertCommentingBlocked(openTicket.Id);

        // Deleted ticket exercises the "tickets.isEmpty()" branch.
        Id deletedTicketId = openTicket.Id;
        delete openTicket;
        TicketReopenService.assertCommentingBlocked(deletedTicketId);
    }

    @IsTest
    static void testResolveCommentRoutingOpenTicket() {
        Case openTicket = createTicket(
            getOpenStatus(),
            null
        );

        Test.startTest();
        TicketReopenService.CommentRoutingResult result =
            TicketReopenService.resolveCommentRouting(openTicket.Id);
        Test.stopTest();

        System.assertEquals(
            false,
            result.followUpCreated,
            'Open tickets should not create a follow-up.'
        );
        System.assertEquals(
            null,
            result.followUpTicketId,
            'No follow-up ticket should be created.'
        );
    }

    @IsTest
    static void testResolveCommentRoutingWithinReopenWindow() {
        Datetime recentlyClosed =
            System.now().addDays(-SharedNoteConstants.REOPEN_WINDOW_DAYS);

        Case closedTicket = createTicket(
            getClosedStatus(),
            recentlyClosed
        );

        Test.startTest();
        TicketReopenService.CommentRoutingResult result =
            TicketReopenService.resolveCommentRouting(closedTicket.Id);
        Test.stopTest();

        System.assertEquals(
            false,
            result.followUpCreated,
            'A ticket still inside the reopen window should not create a follow-up.'
        );
        System.assertEquals(
            null,
            result.followUpTicketId,
            'No follow-up should be created inside the reopen window.'
        );
    }

    @IsTest
    static void testResolveCommentRoutingExistingFollowUp() {
        Datetime closedDate =
            System.now().addDays(
                -(SharedNoteConstants.REOPEN_WINDOW_DAYS + 1)
            );

        Case originalTicket = createTicket(
            getClosedStatus(),
            closedDate
        );

        Case existingFollowUp = new Case(
            ParentId = originalTicket.Id,
            Subject = 'Existing Follow-Up',
            Description = 'Existing follow-up ticket',
            Status = getOpenStatus(),
            Origin = 'Web',
            Priority = 'Medium'
        );

        insert existingFollowUp;

        Test.startTest();

        try {
            TicketReopenService.resolveCommentRouting(originalTicket.Id);
            System.assert(
                false,
                'Expected an AuraHandledException for an existing follow-up.'
            );
        } catch (AuraHandledException e) {
        }

        Test.stopTest();
    }

    @IsTest
    static void testResolveCommentRoutingCreatesFollowUp() {
        Datetime closedDate =
            System.now().addDays(
                -(SharedNoteConstants.REOPEN_WINDOW_DAYS + 1)
            );

        Case originalTicket = createTicket(
            getClosedStatus(),
            closedDate
        );

        Test.startTest();

        TicketReopenService.CommentRoutingResult result =
            TicketReopenService.resolveCommentRouting(originalTicket.Id);

        Test.stopTest();

        System.assertEquals(
            true,
            result.followUpCreated,
            'A follow-up should be created for a ticket outside the reopen window.'
        );

        System.assertNotEquals(
            null,
            result.followUpTicketId,
            'The follow-up ticket Id should be populated.'
        );

        Case followUp = [
            SELECT Id,
                   ParentId,
                   Subject,
                   Description,
                   Origin,
                   Priority,
                   Status,
                   RecordTypeId
            FROM Case
            WHERE Id = :result.followUpTicketId
            LIMIT 1
        ];

        System.assertEquals(
            originalTicket.Id,
            followUp.ParentId,
            'The follow-up should reference the original ticket.'
        );

        System.assertEquals(
            originalTicket.Subject,
            followUp.Subject,
            'Subject should be copied from the original ticket.'
        );

        System.assertEquals(
            originalTicket.Description,
            followUp.Description,
            'Description should be copied from the original ticket.'
        );

        System.assertEquals(
            originalTicket.Origin,
            followUp.Origin,
            'Origin should be copied from the original ticket.'
        );

        System.assertEquals(
            originalTicket.Priority,
            followUp.Priority,
            'Priority should be copied from the original ticket.'
        );

        System.assertEquals(
            SharedNoteConstants.CASE_STATUS_NEW,
            followUp.Status,
            'Follow-up should be created with the New status.'
        );

        System.assert(
            SharedNoteLinkTriggerHandler.suppressAutoReopenTicketIds.contains(
                originalTicket.Id
            ),
            'The original ticket should be added to the auto-reopen suppression set.'
        );
    }
}