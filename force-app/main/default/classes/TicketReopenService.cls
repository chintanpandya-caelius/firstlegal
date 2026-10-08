public with sharing class TicketReopenService {

    public class CommentRoutingResult {
        @AuraEnabled public Boolean followUpCreated = false;
        @AuraEnabled public Id followUpTicketId;
        @AuraEnabled public String followUpCaseNumber;
    }

	//Function to block internal users to comment on a closed ticket 
	public static void assertCommentingBlocked(Id ticketId) {
        if (ticketId == null) {
            return;
        }

        List<Case> tickets = [SELECT Id, IsClosed FROM Case WHERE Id = :ticketId WITH USER_MODE LIMIT 1];
        if (tickets.isEmpty() || !tickets[0].IsClosed) {
            return;
        }

        String profileName = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1].Profile.Name;
        if (SharedNoteConstants.BLOCKED_INTERNAL_COMMENT_PROFILES.contains(profileName)) {
            throw new AuraHandledException('This ticket is closed and can no longer be commented on.');
        }
    }

    public static CommentRoutingResult resolveCommentRouting(Id ticketId) {
        CommentRoutingResult result = new CommentRoutingResult();

        Case ticket = [
            SELECT Id, IsClosed, Closure_DateTime__c, ContactId, AccountId,
                   Subject, Description, Origin, Priority, RecordTypeId
            FROM Case
            WHERE Id = :ticketId
            WITH USER_MODE
            LIMIT 1
        ];

        if (!ticket.IsClosed) {
            return result;
        }

        List<Case> existingFollowUps = [
            SELECT Id, CaseNumber
            FROM Case
            WHERE ParentId = :ticketId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!existingFollowUps.isEmpty()) {
            throw new AuraHandledException(
                'This ticket has already been followed up on as ticket ' +
                existingFollowUps[0].CaseNumber + '. Please comment there instead.'
            );
        }

        Integer daysSinceClosed = ticket.Closure_DateTime__c != null
            ? ticket.Closure_DateTime__c.date().daysBetween(Date.today())
            : null;

        Boolean withinReopenWindow = daysSinceClosed != null
            && daysSinceClosed <= SharedNoteConstants.REOPEN_WINDOW_DAYS;

        if (withinReopenWindow) {
            return result;
        }

        Case followUp = new Case(
            ParentId = ticket.Id,
            ContactId = ticket.ContactId,
            AccountId = ticket.AccountId,
            Subject = ticket.Subject,
            Description = ticket.Description,
            Origin = ticket.Origin,
            Priority = ticket.Priority,
            RecordTypeId = ticket.RecordTypeId,
            Status = SharedNoteConstants.CASE_STATUS_NEW
        );
        insert followUp;

        SharedNoteLinkTriggerHandler.suppressAutoReopenTicketIds.add(ticketId);

        result.followUpCreated = true;
        result.followUpTicketId = followUp.Id;
        result.followUpCaseNumber = followUp.CaseNumber;
        return result;
    }
}